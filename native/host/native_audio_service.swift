import AVFoundation
import Foundation
import GoldenEyeNative

/// Native source-rate audio bridge for the title slice. The C core performs
/// bounded sequence/bank parsing and deterministic PCM generation; Swift owns
/// AVAudioEngine lifecycle and refills the fixed C SPSC source-node ring from
/// immutable rendered track data. A player-node buffer path remains only as a
/// bounded fallback when the source-node adapter cannot be created.
@available(macOS 27.0, *)
final class GoldenEyeNativeAudioService: @unchecked Sendable {
    /// The extracted N64 PCM is already close to full-scale.  Unity gain on
    /// the host mixer therefore makes the title sound badly overdriven next
    /// to normal macOS applications.  Keep the product default conservative
    /// while allowing a bounded launch-time trim for hardware/listener tuning.
    private static let defaultMasterVolume: Float = 0.2

    enum Track: String, CaseIterable, Hashable, Sendable {
        case nintendo = "Mnint_rare_logo.bin"
        case gunbarrel = "Mintro_eye.bin"
        case folders = "Mfolders.bin"
    }

    private struct RenderedPCM: Sendable {
        let samples: [Int16]
        let frames: UInt32
        let hash: UInt64
        let effectsHash: UInt64
    }

    private let assetRoot: URL
    private let masterVolume: Float
    /// The V5 renderer remains the source-vector authority.  Product playback
    /// can apply the additive V6 small-room bus after that render without
    /// changing the frozen V5 hash or any C reference evidence.
    private let effectsEnabled: Bool
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let sfxPlayer = AVAudioPlayerNode()
    private let lock = NSLock()
    private var started = false
    private var currentTrack: Track?
    private var lastRenderHash: UInt64 = 0
    private var lastEffectsHash: UInt64 = 0
    private var pcmSource: UnsafeMutablePointer<GEAudioPCMSourceV5>?
    private var sourceAdapter: OpaquePointer?
    private var sourceNode: AVAudioSourceNode?
    private var renderedTrackCache: [Track: RenderedPCM] = [:]
    private var renderedSFXCache: [UInt32: RenderedPCM] = [:]
    private var renderedSamples: [Int16] = []
    private var renderedFrameCount: UInt32 = 0
    private var trackStartSampleIndex: UInt64 = 0
    /// The next exact source-clock block that still needs to enter the ring.
    /// It advances only after a complete block is written; a full ring must
    /// never make the producer skip source samples.
    private var nextRefillNativeTick: UInt64?
    private var routeGeneration: UInt32 = 0
    private var realtimeActive = false
    private var audioPaused = false
    private var pauseCount: UInt64 = 0
    private var resumeCount: UInt64 = 0
    private var sfxNodeSampleOrigin: Int64?
    private var sourceAudioBinding = GoldenEyeSourceAudioBindingV6()
    /// File/Mode is an additive source sidecar with its own C event-sequence
    /// namespace. Keep a separate once-only binding so a menu sequence cannot
    /// suppress or reorder an authoritative frontend audio event.
    private var fileModeAudioBinding = GoldenEyeSourceAudioBindingV6()

    private struct ScheduledSFX {
        let startSampleIndex: UInt64
        let samples: [Int16]
        let frames: UInt32
        let sequence: UInt64
    }

    private var scheduledSFX: [ScheduledSFX] = []
    private var refillScratch = Array(
        repeating: Int16(0),
        count: Int(GE_AUDIO_OUTPUT_V5_DEFAULT_TARGET_FILL_FRAMES) *
            Int(GE_AUDIO_OUTPUT_V5_CHANNELS)
    )

    private var immediateDebugCuesEnabled: Bool {
        ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_AUDIO_IMMEDIATE_DEBUG"] == "1"
    }

    init(assetRoot: URL) {
        self.assetRoot = assetRoot
        if let rawVolume = ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_AUDIO_VOLUME"],
           let parsedVolume = Double(rawVolume),
           parsedVolume.isFinite {
            self.masterVolume = Float(min(max(parsedVolume, 0.0), 1.0))
        } else {
            self.masterVolume = Self.defaultMasterVolume
        }
        self.effectsEnabled = ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_AUDIO_EFFECTS"] != "0"
    }

    func start() throws {
        lock.lock()
        if started {
            lock.unlock()
            return
        }
        started = true
        lock.unlock()

        // Decode and effect-process the bounded title/SFX payloads before the
        // 120 Hz owner starts.  Rendering a 131,072-frame music track on the
        // owner thread starves both the source ring and the title scheduler.
        prewarmAudioAssets()
        let realtimeReady = makeRealtimeSourceNode()
        engine.attach(sfxPlayer)
        let sfxFormat = try makeFormat()
        try engine.connectNode(sfxPlayer, to: engine.mainMixerNode, format: sfxFormat)
        if !realtimeReady {
            engine.attach(player)
            let format = try makeFormat()
            try engine.connectNode(player, to: engine.mainMixerNode, format: format)
        }
        engine.mainMixerNode.outputVolume = masterVolume
        engine.prepare()
        do {
            try engine.start()
            // Keep the dedicated effects node's timeline running from the
            // same Core Audio clock. It renders silence until a validated
            // source event is scheduled at an explicit sample time.
            try? sfxPlayer.playAudio()
        } catch {
            lock.lock()
            started = false
            realtimeActive = false
            lock.unlock()
            if realtimeReady, let node = sourceNode {
                engine.detach(node)
            } else {
                engine.detach(player)
            }
            engine.detach(sfxPlayer)
            tearDownRealtimeSource()
            throw error
        }
    }

    func play(_ track: Track, nativeTick: UInt64 = 0) {
        guard immediateDebugCuesEnabled else {
            recordSuppressedImmediateCue("music=\(track.rawValue) nativeTick=\(nativeTick)")
            return
        }
        guard let rendered = try? renderedMusic(for: track) else {
            print("GoldenEye audio: unable to render (track.rawValue)")
            return
        }
        lock.lock()
        guard started else {
            lock.unlock()
            return
        }
        currentTrack = track
        lock.unlock()

        if realtimeActive, let source = pcmSource {
            routeGeneration &+= 1
            _ = ge_audio_pcm_source_begin_route_recovery_v5(
                source,
                GE_AUDIO_OUTPUT_V5_SAMPLE_RATE,
                GE_AUDIO_OUTPUT_V5_CHANNELS,
                routeGeneration
            )
            renderedSamples = rendered.samples
            renderedFrameCount = rendered.frames
            lastRenderHash = rendered.hash
            trackStartSampleIndex = ge_audio_pcm_source_sample_index_for_tick_v5(nativeTick)
            nextRefillNativeTick = nativeTick
            // Fill a bounded source-rate preroll immediately.  Subsequent
            // owner ticks refill one exact 735/4 quantum; the Core Audio
            // callback only consumes the C ring.
            for offset in 0..<24 {
                refillRealtime(nativeTick: nativeTick &+ UInt64(offset))
            }
            let runningStatus = ge_audio_pcm_source_mark_running_v5(source)
            try? "track=\(track.rawValue) realtime=1 nativeTick=\(nativeTick) frames=\(rendered.frames) hash=\(rendered.hash) effects=\(effectsEnabled ? 1 : 0) effectsHash=\(lastEffectsHash) markRunning=\(runningStatus)\n".write(
                toFile: "/tmp/goldeneye-native-audio.log",
                atomically: true,
                encoding: .utf8
            )
            return
        }

        guard let buffer = makeBuffer(from: rendered) else {
            print("GoldenEye audio: unable to allocate PCM buffer (track.rawValue)")
            return
        }

        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let line = "track=\(track.rawValue) renderHash=\(self.lastRenderHash) effects=\(self.effectsEnabled ? 1 : 0) effectsHash=\(self.lastEffectsHash)\n"
            self.lock.unlock()
            try? line.write(toFile: "/tmp/goldeneye-native-audio.log", atomically: true, encoding: .utf8)
        }
        try? player.playAudio()
    }

    /// Render and schedule one source SFX from the guarded SFX bank. This is
    /// deliberately a separate player node so effects can overlap the music
    /// source-node route without entering the realtime callback or changing
    /// the frozen V5 music vectors.
    func playSFX(_ soundIndex: UInt32, nativeTick: UInt64 = 0) {
        guard immediateDebugCuesEnabled else {
            recordSuppressedImmediateCue("sfx=\(soundIndex) nativeTick=\(nativeTick)")
            return
        }
        guard started, let rendered = try? renderedSFX(soundIndex: soundIndex) else { return }
        guard let buffer = makeBuffer(from: rendered) else { return }
        sfxPlayer.scheduleBuffer(buffer, at: nil, options: [])
        try? sfxPlayer.playAudio()
        try? "soundIndex=\(soundIndex) nativeTick=\(nativeTick) frames=\(rendered.frames) hash=\(rendered.hash) effectsHash=\(lastEffectsHash)\n".write(
            toFile: "/tmp/goldeneye-native-audio-sfx.log",
            atomically: false,
            encoding: .utf8
        )
    }

    /// Called by the native owner for every authoritative 120 Hz tick.  This
    /// function is owner-side only; the realtime Core Audio callback never
    /// enters Swift and never performs refill work.
    func tick(nativeTick: UInt64) {
        lock.lock()
        let shouldRefill = realtimeActive && !audioPaused
        lock.unlock()
        guard shouldRefill else { return }
        refillRealtime(nativeTick: nativeTick)
    }

    /// Freeze and resume the Core Audio graph with the owner scheduler. The
    /// owner stops calling `tick` while paused, but that alone would let the
    /// realtime source-node callback drain its already-buffered PCM. Pausing
    /// the engine itself keeps the audio cursor and callback cadence frozen.
    func setPaused(_ paused: Bool) {
        lock.lock()
        guard started, audioPaused != paused else {
            lock.unlock()
            return
        }
        audioPaused = paused
        if paused {
            pauseCount &+= 1
        } else {
            resumeCount &+= 1
        }
        let active = realtimeActive
        lock.unlock()

        if paused {
            engine.pause()
        } else {
            do {
                try engine.start()
                try? sfxPlayer.playAudio()
                if !active { try? player.playAudio() }
            } catch {
                lock.lock()
                audioPaused = true
                lock.unlock()
                try? "event=resumeFailed error=\(error)\n".write(
                    toFile: "/tmp/goldeneye-native-audio-pause.log",
                    atomically: false,
                    encoding: .utf8
                )
                return
            }
        }
        lock.lock()
        let pauses = pauseCount
        let resumes = resumeCount
        let state = audioPaused
        lock.unlock()
        let eventName = paused ? "pause" : "resume"
        try? "event=\(eventName) paused=\(state ? 1 : 0) pauseCount=\(pauses) resumeCount=\(resumes) realtime=\(active ? 1 : 0)\n".write(
            toFile: "/tmp/goldeneye-native-audio-pause.log",
            atomically: false,
            encoding: .utf8
        )
    }

    /// Drop any music/SFX timeline left by the previous game session while
    /// keeping the prepared AVAudioEngine graph alive for the next title
    /// frame. This is called only by the native owner thread during Reset.
    func resetForGame() {
        guard started else {
            sourceAudioBinding.reset()
            fileModeAudioBinding.reset()
            return
        }
        stopSourceMusic(at: 0, nativeTick: 0)
        sfxPlayer.stop()
        try? sfxPlayer.playAudio()
        lock.lock()
        sourceAudioBinding.reset()
        scheduledSFX.removeAll(keepingCapacity: false)
        sfxNodeSampleOrigin = nil
        audioPaused = false
        lock.unlock()
        try? "event=gameReset routeGeneration=\(routeGeneration)\n".write(
            toFile: "/tmp/goldeneye-native-audio-binding.log",
            atomically: false,
            encoding: .utf8
        )
    }

    var pauseTelemetry: (paused: Bool, pauseCount: UInt64, resumeCount: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        return (audioPaused, pauseCount, resumeCount)
    }

    /// Consume the source frontend's immutable V6 audio records.  Playback is
    /// driven only by these sample-indexed commands in production; the legacy
    /// `play`/`playSFX` methods above are explicitly debug-gated compatibility
    /// probes.  A rejected asset is recorded and produces no replacement cue.
    func consume(
        sourceAudioEvents: [GoldenEyeSourceFrontendAudioEventV6],
        nativeTick: UInt64,
        paused: Bool = false
    ) {
        let inputs = sourceAudioEvents.map {
            GoldenEyeSourceAudioInputV6(
                operation: $0.operation,
                assetID: $0.assetID,
                nativeTick: $0.nativeTick,
                sourceSample: $0.sourceSample,
                flags: $0.flags,
                sequence: $0.sequence
            )
        }
        let result = sourceAudioBinding.consume(inputs, nativeTick: nativeTick, paused: paused)
        if !result.rejections.isEmpty || result.duplicateCount != 0 || result.suppressedCount != 0 {
            let rejectionText = result.rejections.map {
                "\($0.sequence):\($0.reason)"
            }.joined(separator: ",")
            let line = "nativeTick=\(nativeTick) rejected=\(rejectionText.isEmpty ? "-" : rejectionText) "
                + "duplicates=\(result.duplicateCount) suppressed=\(result.suppressedCount)\n"
            try? line.write(
                toFile: "/tmp/goldeneye-native-audio-binding.log",
                atomically: false,
                encoding: .utf8
            )
        }
        applySourceAudioCommands(result.commands, nativeTick: nativeTick, paused: paused)
    }

    /// Forward source File/Mode SFX sidecar events through the same
    /// sample-indexed scheduling path. The sidecar has an independent binding
    /// sequence namespace, so menu actions cannot consume frontend sequence
    /// numbers or replay after a pause/reset.
    func consume(
        fileModeSFXEvents: [GoldenEyeFileModeEventSnapshotV6],
        nativeTick: UInt64,
        paused: Bool = false
    ) {
        let inputs = fileModeSFXEvents
            .filter { $0.kind == GE_FILE_MODE_V6_EVENT_SFX.rawValue }
            .map {
                GoldenEyeSourceAudioInputV6(
                    operation: GoldenEyeSourceAudioBindingV6.playSFXOperation,
                    assetID: $0.command,
                    nativeTick: $0.nativeTick,
                    sequence: $0.sequence
                )
            }
        guard !inputs.isEmpty else { return }
        let result = fileModeAudioBinding.consume(inputs, nativeTick: nativeTick, paused: paused)
        if !result.rejections.isEmpty || result.duplicateCount != 0 || result.suppressedCount != 0 {
            let rejectionText = result.rejections.map {
                "\($0.sequence):\($0.reason)"
            }.joined(separator: ",")
            let line = "fileMode nativeTick=\(nativeTick) rejected=\(rejectionText.isEmpty ? "-" : rejectionText) "
                + "duplicates=\(result.duplicateCount) suppressed=\(result.suppressedCount)\n"
            try? line.write(
                toFile: "/tmp/goldeneye-native-audio-binding.log",
                atomically: false,
                encoding: .utf8
            )
        }
        applySourceAudioCommands(result.commands, nativeTick: nativeTick, paused: paused)
    }

    /// Reset only the additive File/Mode event cursor when the source menu
    /// authority is recreated after leaving and re-entering the menu.
    func resetFileModeAudioSession() {
        fileModeAudioBinding.reset()
        try? "event=fileModeAudioSessionReset=1\n".write(
            toFile: "/tmp/goldeneye-native-audio-binding.log",
            atomically: false,
            encoding: .utf8
        )
    }

    private func applySourceAudioCommands(
        _ commands: [GoldenEyeSourceAudioCommandV6],
        nativeTick: UInt64,
        paused: Bool
    ) {
        guard started, !paused else { return }
        guard realtimeActive else {
            recordSuppressedImmediateCue("source-events-without-realtime-output nativeTick=\(nativeTick)")
            return
        }
        for command in commands {
            switch command.kind {
            case .stopMusic:
                stopSourceMusic(at: command.sampleIndex, nativeTick: command.nativeTick)
            case .music:
                guard let track = track(forMusicAsset: command.assetID) else {
                    recordSuppressedImmediateCue("unmapped-music=\(command.assetID) sequence=\(command.sequence)")
                    continue
                }
                startSourceMusic(
                    track,
                    at: command.sampleIndex,
                    nativeTick: command.nativeTick,
                    sequence: command.sequence
                )
            case .sfx:
                scheduleSourceSFX(
                    soundIndex: command.assetID,
                    at: command.sampleIndex,
                    nativeTick: command.nativeTick,
                    sequence: command.sequence
                )
            }
        }
    }

    func stop() {
        lock.lock()
        let wasStarted = started
        started = false
        currentTrack = nil
        realtimeActive = false
        audioPaused = false
        sourceAudioBinding.reset()
        fileModeAudioBinding.reset()
        scheduledSFX.removeAll(keepingCapacity: false)
        let node = sourceNode
        lock.unlock()
        guard wasStarted else { return }
        engine.stop()
        if let node {
            engine.detach(node)
        } else {
            player.stop()
            engine.detach(player)
        }
        sfxPlayer.stop()
        engine.detach(sfxPlayer)
        sfxNodeSampleOrigin = nil
        tearDownRealtimeSource()
    }

    private func makeFormat() throws -> AVAudioFormat {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 22_050,
            channels: 2,
            interleaved: true
        ) else {
            throw NSError(domain: "GoldenEyeAudio", code: 1, userInfo: [NSLocalizedDescriptionKey: "22,050 Hz stereo format unavailable"])
        }
        return format
    }

    private func track(forMusicAsset assetID: UInt32) -> Track? {
        switch assetID {
        case GoldenEyeSourceAudioBindingV6.musicIntroSwoosh:
            return .nintendo
        case GoldenEyeSourceAudioBindingV6.musicIntro:
            return .gunbarrel
        case GoldenEyeSourceAudioBindingV6.musicFolders:
            return .folders
        default:
            return nil
        }
    }

    private func recordSuppressedImmediateCue(_ detail: String) {
        let line = "suppressed=1 detail=\(detail)\n"
        try? line.write(
            toFile: "/tmp/goldeneye-native-audio-binding.log",
            atomically: false,
            encoding: .utf8
        )
    }

    private func startSourceMusic(
        _ track: Track,
        at sampleIndex: UInt64,
        nativeTick: UInt64,
        sequence: UInt64
    ) {
        guard let rendered = try? renderedMusic(for: track) else {
            recordSuppressedImmediateCue(
                "unreadable-music=\(track.rawValue) sequence=\(sequence)"
            )
            return
        }
        guard let source = pcmSource else {
            recordSuppressedImmediateCue(
                "missing-pcm-source music=\(track.rawValue) sequence=\(sequence)"
            )
            return
        }

        routeGeneration &+= 1
        guard ge_audio_pcm_source_begin_route_recovery_v5(
            source,
            GE_AUDIO_OUTPUT_V5_SAMPLE_RATE,
            GE_AUDIO_OUTPUT_V5_CHANNELS,
            routeGeneration
        ) == GE_STATUS_OK else {
            recordSuppressedImmediateCue(
                "route-recovery-failed music=\(track.rawValue) sequence=\(sequence)"
            )
            return
        }
        lock.lock()
        currentTrack = track
        lock.unlock()
        renderedSamples = rendered.samples
        renderedFrameCount = rendered.frames
        lastRenderHash = rendered.hash
        trackStartSampleIndex = sampleIndex
        scheduledSFX.removeAll(keepingCapacity: true)
        nextRefillNativeTick = nativeTick

        // Build the fixed preroll through the same exact 735/4 producer path
        // used on later owner ticks.  The callback remains a pure ring reader.
        for offset in 0..<24 {
            refillRealtime(nativeTick: nativeTick &+ UInt64(offset))
        }
        let runningStatus = ge_audio_pcm_source_mark_running_v5(source)
        if runningStatus != GE_STATUS_OK {
            recordSuppressedImmediateCue(
                "mark-running-failed status=\(runningStatus) music=\(track.rawValue) sequence=\(sequence)"
            )
        }
    }

    private func stopSourceMusic(at sampleIndex: UInt64, nativeTick: UInt64) {
        lock.lock()
        currentTrack = nil
        lock.unlock()
        renderedSamples.removeAll(keepingCapacity: true)
        renderedFrameCount = 0
        scheduledSFX.removeAll(keepingCapacity: true)
        trackStartSampleIndex = sampleIndex
        nextRefillNativeTick = nil

        guard let source = pcmSource else { return }
        routeGeneration &+= 1
        let status = ge_audio_pcm_source_begin_route_recovery_v5(
            source,
            GE_AUDIO_OUTPUT_V5_SAMPLE_RATE,
            GE_AUDIO_OUTPUT_V5_CHANNELS,
            routeGeneration
        )
        if status != GE_STATUS_OK {
            recordSuppressedImmediateCue("stop-route-recovery-failed status=\(status)")
        }
    }

    private func scheduleSourceSFX(
        soundIndex: UInt32,
        at sampleIndex: UInt64,
        nativeTick: UInt64,
        sequence: UInt64
    ) {
        guard let rendered = try? renderedSFX(soundIndex: soundIndex) else {
            recordSuppressedImmediateCue(
                "unreadable-sfx=\(soundIndex) sequence=\(sequence)"
            )
            return
        }
        guard let source = pcmSource else {
            recordSuppressedImmediateCue(
                "missing-pcm-source sfx=\(soundIndex) sequence=\(sequence)"
            )
            return
        }
        // A source-node ring is intentionally look-ahead buffered.  If an
        // event arrives after its sample has already been committed to the
        // ring, do not play it immediately at an arbitrary wall-clock time.
        // Keep the explicit diagnostic and fail closed for this late cue.
        var sourceSnapshot = GEAudioPCMSourceSnapshotV5()
        ge_audio_pcm_source_snapshot_v5(source, &sourceSnapshot)
        if sourceSnapshot.producer_sample_cursor > sampleIndex {
            guard scheduleSFXOnNode(
                rendered,
                at: sampleIndex,
                soundIndex: soundIndex,
                sequence: sequence
            ) else {
                recordSuppressedImmediateCue(
                    "late-sfx sample=\(sampleIndex) producer=\(sourceSnapshot.producer_sample_cursor) "
                        + "sound=\(soundIndex) sequence=\(sequence)"
                )
                return
            }
            return
        }

        scheduledSFX.append(
            ScheduledSFX(
                startSampleIndex: sampleIndex,
                samples: rendered.samples,
                frames: rendered.frames,
                sequence: sequence
            )
        )

        // Rareware can be the first source cue after a silent route.  Start a
        // source timeline for SFX-only playback without inventing a music
        // track; the mixer below will use silence as its base.
        if currentTrack == nil {
            routeGeneration &+= 1
            guard ge_audio_pcm_source_begin_route_recovery_v5(
                source,
                GE_AUDIO_OUTPUT_V5_SAMPLE_RATE,
                GE_AUDIO_OUTPUT_V5_CHANNELS,
                routeGeneration
            ) == GE_STATUS_OK else {
                scheduledSFX.removeLast()
                recordSuppressedImmediateCue("sfx-only-route-recovery-failed sequence=\(sequence)")
                return
            }
            trackStartSampleIndex = sampleIndex
            nextRefillNativeTick = nativeTick
            for offset in 0..<24 {
                refillRealtime(nativeTick: nativeTick &+ UInt64(offset))
            }
            let runningStatus = ge_audio_pcm_source_mark_running_v5(source)
            if runningStatus != GE_STATUS_OK {
                recordSuppressedImmediateCue(
                    "sfx-only-mark-running-failed status=\(runningStatus) sequence=\(sequence)"
                )
            }
        }
    }

    /// The music source-node ring is deliberately filled ahead of the
    /// owner.  A one-shot arriving after that look-ahead is scheduled on the
    /// already-running effects node at an explicit Core Audio sample time,
    /// never at `nil`/wall-clock-immediate time.  The node's origin is learned
    /// once from the same 22,050 Hz output clock and the source sample index.
    private func scheduleSFXOnNode(
        _ rendered: RenderedPCM,
        at sampleIndex: UInt64,
        soundIndex: UInt32,
        sequence: UInt64
    ) -> Bool {
        guard let buffer = makeBuffer(from: rendered),
              sampleIndex <= UInt64(Int64.max),
              let nodeTime = sfxPlayer.lastRenderTime,
              let playerTime = sfxPlayer.playerTime(forNodeTime: nodeTime),
              playerTime.isSampleTimeValid else {
            return false
        }
        let now = playerTime.sampleTime
        if sfxNodeSampleOrigin == nil {
            let source = Int64(sampleIndex)
            let origin = now.subtractingReportingOverflow(source)
            guard !origin.overflow else { return false }
            sfxNodeSampleOrigin = origin.partialValue
        }
        guard let origin = sfxNodeSampleOrigin else { return false }
        let sourceSample = Int64(sampleIndex)
        let target = origin.addingReportingOverflow(sourceSample)
        guard !target.overflow, target.partialValue >= now else {
            return false
        }
        let at = AVAudioTime(
            sampleTime: AVAudioFramePosition(target.partialValue),
            atRate: Double(GE_AUDIO_OUTPUT_V5_SAMPLE_RATE)
        )
        sfxPlayer.scheduleBuffer(buffer, at: at, options: [])
        try? "sfx=\(soundIndex) sequence=\(sequence) sample=\(sampleIndex) nodeSample=\(target.partialValue) scheduled=1\n".write(
            toFile: "/tmp/goldeneye-native-audio-binding.log",
            atomically: false,
            encoding: .utf8
        )
        return true
    }

    private func prewarmAudioAssets() {
        for track in Track.allCases {
            _ = try? renderedMusic(for: track)
        }
        for soundIndex in GoldenEyeSourceAudioBindingV6.supportedSFXIDs {
            _ = try? renderedSFX(soundIndex: soundIndex)
        }
    }

    private func renderedMusic(for track: Track) throws -> RenderedPCM {
        if let cached = renderedTrackCache[track] {
            lastRenderHash = cached.hash
            lastEffectsHash = cached.effectsHash
            return cached
        }
        let rendered = try renderPCM(for: track)
        let value = RenderedPCM(
            samples: rendered.samples,
            frames: rendered.frames,
            hash: rendered.hash,
            effectsHash: lastEffectsHash
        )
        renderedTrackCache[track] = value
        return value
    }

    private func renderedSFX(soundIndex: UInt32) throws -> RenderedPCM {
        if let cached = renderedSFXCache[soundIndex] {
            lastRenderHash = cached.hash
            lastEffectsHash = cached.effectsHash
            return cached
        }
        let rendered = try renderSFX(soundIndex: soundIndex)
        let value = RenderedPCM(
            samples: rendered.samples,
            frames: rendered.frames,
            hash: rendered.hash,
            effectsHash: lastEffectsHash
        )
        renderedSFXCache[soundIndex] = value
        return value
    }

    private func renderPCM(for track: Track) throws -> (samples: [Int16], frames: UInt32, hash: UInt64) {
        let audioURL = assetRoot.appendingPathComponent("audio", isDirectory: true)
        let sequence = try Data(contentsOf: audioURL.appendingPathComponent(track.rawValue))
        let ctl = try Data(contentsOf: audioURL.appendingPathComponent("instruments.ctl"))
        let tbl = try Data(contentsOf: audioURL.appendingPathComponent("instruments.tbl"))
        let frameCount: UInt32 = 131_072
        var samples = Array(repeating: Int16(0), count: Int(frameCount) * 2)
        var result = GEAudioRenderResultV5()
        var diagnostic = GEAudioDiagnosticV5()

        let status: GEStatusV1 = sequence.withUnsafeBytes { sequenceBytes in
            ctl.withUnsafeBytes { ctlBytes in
                tbl.withUnsafeBytes { tblBytes in
                    samples.withUnsafeMutableBufferPointer { sampleBuffer in
                        ge_audio_render_sequence_v5(
                            sequenceBytes.bindMemory(to: UInt8.self).baseAddress,
                            UInt32(sequence.count),
                            ctlBytes.bindMemory(to: UInt8.self).baseAddress,
                            UInt32(ctl.count),
                            tblBytes.bindMemory(to: UInt8.self).baseAddress,
                            UInt32(tbl.count),
                            frameCount,
                            sampleBuffer.baseAddress,
                            UInt32(sampleBuffer.count),
                            &result,
                            &diagnostic
                        )
                    }
                }
            }
        }
        guard status == GE_STATUS_OK else {
            let messageBytes = withUnsafeBytes(of: diagnostic.message) { rawBytes in
                Array(rawBytes.bindMemory(to: UInt8.self))
            }
            let message = String(decoding: messageBytes.prefix { $0 != 0 }, as: UTF8.self)
            throw NSError(domain: "GoldenEyeAudio", code: Int(status), userInfo: [NSLocalizedDescriptionKey: message])
        }

        lock.lock()
        lastRenderHash = result.pcm_hash
        lock.unlock()

        // V6 effects are deliberately downstream of the V5 render.  This
        // keeps the source PCM vector stable while giving the product route a
        // deterministic reverb tail.  The call is owner-side and bounded; the
        // AVAudioSourceNode callback never enters this path.
        if effectsEnabled {
            lastEffectsHash = applySmallRoomReverb(
                to: &samples,
                frames: result.frames_rendered
            ) ?? 0
        } else {
            lastEffectsHash = 0
        }

        return (samples, result.frames_rendered, result.pcm_hash)
    }

    private func renderSFX(soundIndex: UInt32) throws -> (samples: [Int16], frames: UInt32, hash: UInt64) {
        let audioURL = assetRoot.appendingPathComponent("audio", isDirectory: true)
        let ctl = try Data(contentsOf: audioURL.appendingPathComponent("sfx.ctl"))
        let tbl = try Data(contentsOf: audioURL.appendingPathComponent("sfx.tbl"))
        let frameCount: UInt32 = 8192
        var samples = Array(repeating: Int16(0), count: Int(frameCount) * 2)
        var result = GEAudioRenderResultV5()
        var diagnostic = GEAudioDiagnosticV5()
        let status: GEStatusV1 = ctl.withUnsafeBytes { ctlBytes in
            tbl.withUnsafeBytes { tblBytes in
                samples.withUnsafeMutableBufferPointer { sampleBuffer in
                    ge_audio_render_sfx_v5(
                        ctlBytes.bindMemory(to: UInt8.self).baseAddress,
                        UInt32(ctl.count),
                        tblBytes.bindMemory(to: UInt8.self).baseAddress,
                        UInt32(tbl.count),
                        soundIndex,
                        frameCount,
                        sampleBuffer.baseAddress,
                        UInt32(sampleBuffer.count),
                        &result,
                        &diagnostic
                    )
                }
            }
        }
        guard status == GE_STATUS_OK else {
            throw NSError(
                domain: "GoldenEyeAudio",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "SFX \(soundIndex) failed with code \(diagnostic.code)"]
            )
        }
        if effectsEnabled {
            lastEffectsHash = applySmallRoomReverb(to: &samples, frames: result.frames_rendered) ?? 0
        }
        return (samples, result.frames_rendered, result.pcm_hash)
    }

    private func applySmallRoomReverb(to samples: inout [Int16], frames: UInt32) -> UInt64? {
        guard frames > 0, samples.count >= Int(frames) * 2 else { return nil }
        var config = GEAudioReverbConfigV6()
        var diagnostic = GEAudioDiagnosticV5()
        guard ge_audio_reverb_config_for_preset_v6(
            GE_AUDIO_EFFECTS_V6_REVERB_PRESET_SMALL_ROOM,
            GE_AUDIO_EFFECTS_V6_SAMPLE_RATE,
            &config,
            &diagnostic
        ) == GE_STATUS_OK else { return nil }

        // This bus owns four 8,192-frame stereo delay banks (~128 KiB).  Do
        // not initialize it with `GEAudioReverbBusV6()` here: Swift's Debug
        // lowering materializes several copies of that value on the caller's
        // stack, which exhausts the 544 KiB owner-thread stack before the C
        // initializer can run.  The C initializer clears and fully writes
        // the allocation, so keep the storage raw and heap-backed.
        let bus = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<GEAudioReverbBusV6>.stride,
            alignment: MemoryLayout<GEAudioReverbBusV6>.alignment
        ).assumingMemoryBound(to: GEAudioReverbBusV6.self)
        defer { bus.deallocate() }
        guard ge_audio_reverb_bus_init_v6(bus, &config, &diagnostic) == GE_STATUS_OK else {
            return nil
        }
        var result = GEAudioReverbResultV6()
        let status = samples.withUnsafeMutableBufferPointer { buffer -> GEStatusV1 in
            ge_audio_reverb_bus_process_v6(
                bus,
                buffer.baseAddress,
                frames,
                buffer.baseAddress,
                UInt32(buffer.count),
                &result,
                &diagnostic
            )
        }
        guard status == GE_STATUS_OK, result.frames_processed == frames else { return nil }
        return result.output_hash
    }

    private func makeBuffer(from rendered: RenderedPCM) -> AVAudioPCMBuffer? {
        guard let format = try? makeFormat() else { return nil }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(rendered.frames)
        ) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(rendered.frames)
        guard let destination = buffer.int16ChannelData?.pointee,
              let base = rendered.samples.withUnsafeBufferPointer({ $0.baseAddress }) else {
            return nil
        }
        destination.update(from: base, count: Int(rendered.frames) * 2)
        return buffer
    }

    private func makeRealtimeSourceNode() -> Bool {
        let source = UnsafeMutablePointer<GEAudioPCMSourceV5>.allocate(capacity: 1)
        source.initialize(to: GEAudioPCMSourceV5())
        guard ge_audio_pcm_source_init_v5(
            source,
            GE_AUDIO_OUTPUT_V5_DEFAULT_PREROLL_FRAMES,
            GE_AUDIO_OUTPUT_V5_DEFAULT_TARGET_FILL_FRAMES
        ) == GE_STATUS_OK else {
            source.deinitialize(count: 1)
            source.deallocate()
            return false
        }
        var diagnostic = GEAudioDiagnosticV5()
        guard let adapter = ge_audio_source_node_adapter_create_v5(source, &diagnostic),
              let rawNode = ge_audio_source_node_adapter_node_v5(adapter) else {
            source.deinitialize(count: 1)
            source.deallocate()
            return false
        }
        let node = Unmanaged<AVAudioSourceNode>.fromOpaque(rawNode).takeUnretainedValue()
        engine.attach(node)
        do {
            try engine.connectNode(node, to: engine.mainMixerNode, format: node.outputFormat(forBus: 0))
        } catch {
            ge_audio_source_node_adapter_destroy_v5(adapter)
            source.deinitialize(count: 1)
            source.deallocate()
            return false
        }
        pcmSource = source
        sourceAdapter = adapter
        sourceNode = node
        realtimeActive = true
        return true
    }

    private func tearDownRealtimeSource() {
        if let adapter = sourceAdapter {
            ge_audio_source_node_adapter_destroy_v5(adapter)
        }
        sourceAdapter = nil
        sourceNode = nil
        if let source = pcmSource {
            source.deinitialize(count: 1)
            source.deallocate()
        }
        pcmSource = nil
        renderedSamples.removeAll(keepingCapacity: false)
        scheduledSFX.removeAll(keepingCapacity: false)
        sourceAudioBinding.reset()
        fileModeAudioBinding.reset()
        sfxNodeSampleOrigin = nil
        renderedFrameCount = 0
        trackStartSampleIndex = 0
        nextRefillNativeTick = nil
    }

    private func refillRealtime(nativeTick: UInt64) {
        guard let source = pcmSource,
              renderedFrameCount != 0 || !scheduledSFX.isEmpty else {
            return
        }
        let refillTick = nextRefillNativeTick ?? nativeTick
        let frameCount = ge_audio_pcm_source_frame_count_for_tick_v5(refillTick)
        let sampleIndex = ge_audio_pcm_source_sample_index_for_tick_v5(refillTick)
        guard sampleIndex >= trackStartSampleIndex else {
            nextRefillNativeTick = refillTick &+ 1
            return
        }
        let relativeSampleIndex = sampleIndex - trackStartSampleIndex
        let stereoCount = Int(frameCount) * Int(GE_AUDIO_OUTPUT_V5_CHANNELS)
        guard stereoCount <= refillScratch.count else {
            return
        }

        // Keep the exact pending source block until the ring has room for the
        // whole block.  The C API may legally write a partial block when the
        // ring is nearly full; retrying that same tick after a partial write
        // would duplicate samples, so wait before calling it instead.
        var sourceSnapshot = GEAudioPCMSourceSnapshotV5()
        ge_audio_pcm_source_snapshot_v5(source, &sourceSnapshot)
        guard sourceSnapshot.available_frames <= sourceSnapshot.capacity_frames,
              sourceSnapshot.capacity_frames >= frameCount,
              sourceSnapshot.capacity_frames - sourceSnapshot.available_frames >= frameCount else {
            return
        }

        // Mix the source-owned music timeline and any already validated SFX
        // events into a fixed owner-side scratch block.  No allocation or
        // Swift work occurs in the Core Audio callback; it only drains the C
        // ring populated here.
        for frame in 0..<Int(frameCount) {
            let globalSample = sampleIndex + UInt64(frame)
            var left = Int32(0)
            var right = Int32(0)
            if relativeSampleIndex < UInt64(renderedFrameCount),
               UInt64(frame) < UInt64(renderedFrameCount) - relativeSampleIndex {
                let sourceFrame = Int(relativeSampleIndex + UInt64(frame))
                let sourceOffset = sourceFrame * Int(GE_AUDIO_OUTPUT_V5_CHANNELS)
                if sourceOffset + 1 < renderedSamples.count {
                    left = Int32(renderedSamples[sourceOffset])
                    right = Int32(renderedSamples[sourceOffset + 1])
                }
            }
            for sfx in scheduledSFX {
                guard globalSample >= sfx.startSampleIndex else { continue }
                let relativeSFX = globalSample - sfx.startSampleIndex
                guard relativeSFX < UInt64(sfx.frames) else { continue }
                let sfxOffset = Int(relativeSFX) * Int(GE_AUDIO_OUTPUT_V5_CHANNELS)
                guard sfxOffset + 1 < sfx.samples.count else { continue }
                left += Int32(sfx.samples[sfxOffset])
                right += Int32(sfx.samples[sfxOffset + 1])
            }
            refillScratch[frame * Int(GE_AUDIO_OUTPUT_V5_CHANNELS)] = Int16(
                max(Int32(Int16.min), min(Int32(Int16.max), left))
            )
            refillScratch[frame * Int(GE_AUDIO_OUTPUT_V5_CHANNELS) + 1] = Int16(
                max(Int32(Int16.min), min(Int32(Int16.max), right))
            )
        }

        var refillResult = GEAudioPCMRefillResultV5()
        let status = refillScratch.withUnsafeBufferPointer { samples -> GEStatusV1 in
            guard let base = samples.baseAddress else { return GE_STATUS_INVALID_ARGUMENT }
            var diagnostic = GEAudioDiagnosticV5()
            return ge_audio_pcm_source_refill_tick_v5(
                source,
                refillTick,
                sampleIndex,
                base,
                frameCount,
                &refillResult,
                &diagnostic
            )
        }
        if status == GE_STATUS_OK && refillResult.written_frame_count == frameCount {
            nextRefillNativeTick = refillTick &+ 1
            let consumedThrough = sampleIndex + UInt64(frameCount)
            scheduledSFX.removeAll { event in
                event.startSampleIndex + UInt64(event.frames) <= consumedThrough
            }
        } else if status != GE_STATUS_INVALID_STATE {
            try? "nativeTick=\(nativeTick) refillStatus=\(status)\n".write(
                toFile: "/tmp/goldeneye-native-audio-realtime.log",
                atomically: false,
                encoding: .utf8
            )
            return
        }
    }
}
