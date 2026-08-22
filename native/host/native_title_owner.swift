import Foundation
import Metal
import QuartzCore
import GoldenEyeNative

/// Product-mode adapter that runs the native title controller on the exact
/// 120 Hz owner scheduler.  The legacy bounded owner remains available for
/// the completed M1–M12 probes; this adapter is selected only by the native
/// boot launcher so those frozen evidence lanes are not rewritten.
@available(macOS 26.0, *)
final class GoldenEyeNativeTitleOwner: @unchecked Sendable {
    private final class CallbackBox {
        weak var owner: GoldenEyeNativeTitleOwner?
    }

    private let renderer: any GoldenEyeFrameRenderer
    private let inputMailbox: GoldenEyeInputMailbox?
    private let audioService: GoldenEyeNativeAudioService?
    private let saveRuntime: GoldenEyeSaveRuntime
    private let ramRomPlayback: GoldenEyeRamRomPlaybackService?
    /// The V6 adapter owns only copied presentation frames.  The V5 C service
    /// remains the sole packet/checksum/RNG authority; no stage diagnostic
    /// renderer is called from this owner path.
    private let ramRomAuthority: GoldenEyeRamRomAuthorityV6?
    private let displayLink: GE120DisplayLinkRuntime?
    private let inputPoller: (() -> Void)?
    private let callbackBox: CallbackBox
    private let engineOwner: GE120EngineOwner
    private let lock = NSLock()
    private var pendingInput = GoldenEyeKeyboardSnapshot(sequence: 0, held: 0, pressed: 0, released: 0)
    /// The handwritten flow is retained only for an explicit Debug probe.  A
    /// normal run, including every Release run, owns source state through the
    /// copied-value V6 authority below.
    private let diagnosticTitleFlowEnabled: Bool
    private var diagnosticTitleFlow = GoldenEyeBootFlow()
    private var sourceAuthority: GoldenEyeOriginalPairedAuthorityV6?
    private var sourceModelHandshake = GoldenEyeSourceFrontendModelHandshakeV6()
    private var sourceInitializationLedger = GoldenEyeSourceFrontendInitializationLedgerV6()
    private var sourceAuthorityFailure: String?
    private var sourceFrameCount: UInt64 = 0
    private var sourceEventCount: UInt64 = 0
    private var sourceLastStateHash: UInt64 = 0
    private var sourceLastRenderHash: UInt64 = 0
    private var sourceLastAudioHash: UInt64 = 0
    private var sourceLastAudioEventHash: UInt64 = 0
    private var measurementStartStateHash: UInt64 = 0
    private var measurementStartRenderHash: UInt64 = 0
    private var measurementStartAudioHash: UInt64 = 0
    private var measurementStartAudioEventHash: UInt64 = 0
    private var measurementEpochGeneration: UInt64 = 0
    private var measurementEpochNanoseconds: UInt64 = 0
    private var didInitializeNative = false
    private var lastStatus: GEStatusV1 = GE_STATUS_OK
    private var lastAudioScreen: GoldenEyeTitleScreen = .legal
    private var didInstallSaveState = false
    private var lastSaveRuntimeRevision: UInt64 = 0
    private var stageScenePackets: [UInt32: GoldenEyeStageScenePacket] = [:]
    private var stageEnvironmentPackets: [UInt32: GoldenEyeStageBackgroundDrawPacket] = [:]
    private var stageMaterialPackets: [UInt32: GoldenEyeStageSourceMaterialPacketV6] = [:]
    private var gameplayVisiblePropModelIndices: [UInt32: Set<UInt32>] = [:]
    private var stageLifecycle: GoldenEyeStageLifecycleV6?
    /// The production owner consumes decoded stage bytes through the bounded
    /// source-ordered transfer queue. It is synchronous and owner-thread-only;
    /// it does not emulate the N64 scheduler or expose a ROM pointer.
    private var stageTransferQueue: GoldenEyeStageTransferQueueV6?
    private var activeStageLifecycleID: UInt32?
    private var stageScenePreparationAttempted = false
    /// Explicit opt-in for the source gameplay-camera room+static-prop route.
    /// The default Release path remains the existing RAMROM environment
    /// submission until this scoped lane has its own runtime/capture evidence.
    private var gameplayCameraSubmissionEnabled: Bool {
        ProcessInfo.processInfo.environment["GOLDENEYE_STAGE_GAMEPLAY_CAMERA_V7"] == "1"
    }
    private var didPlayGunbarrelRifleSFX = false
    private var fileModeAudioSessionActive = false
    private var sourceRamRomEndNeedsMenuInput = false
    private var ramRomGameplayOrchestrator: GoldenEyeRamRomGameplayOrchestratorV6?
    private var ramRomGameplayLastFrame: GoldenEyeRamRomGameplayFrameV6?
    private let gameplayCameraSubmissionQueue = DispatchQueue(
        label: "GoldenEye.V7.GameplayCameraSubmission",
        qos: .userInitiated
    )
    private let gameplayCameraSubmissionStateLock = NSLock()
    private var gameplayCameraSubmissionInFlight = false
    private var gameplayCameraSubmissionFailure: String?
    private var gameplayCameraFramePublished = false
    /// The V7 evidence lane retains the first stage scene for Cast/SWITCH
    /// ownership, but it may publish a bounded source-anchor window so camera,
    /// portal, and dynamic-door hashes are observed across more than one frame.
    /// The window is opt-in V7 evidence only; the default is four even anchors.
    private var gameplayCameraSubmissionCount: UInt32 = 0
    private var gameplayCameraNextSubmissionTick: UInt64 = 0
    private var gameplayCameraAnchorWindow: UInt32 {
        let raw = ProcessInfo.processInfo.environment[
            "GOLDENEYE_STAGE_GAMEPLAY_CAMERA_ANCHORS"
        ]
        guard let raw, let value = UInt32(raw), (1...8).contains(value) else {
            return 4
        }
        return value
    }
    private var gameplayCameraAnchorInterval: UInt64 {
        let raw = ProcessInfo.processInfo.environment[
            "GOLDENEYE_STAGE_GAMEPLAY_CAMERA_ANCHOR_INTERVAL"
        ]
        guard let raw, let value = UInt64(raw), (2...1_200).contains(value) else {
            return 120
        }
        return value & ~UInt64(1)
    }
    private var prewarmedRamRomGameplayRequest: GoldenEyeRamRomLaunchRequest?
    private var prewarmedRamRomGameplay: GoldenEyeRamRomGameplayOrchestratorV6?
    private var productionCastRoute: GoldenEyeAttractRoute?
    private var productionCastSourceIndex: UInt16?
    private var productionCastSeed: UInt64 = 0

    init(
        renderer: any GoldenEyeFrameRenderer,
        layer: CAMetalLayer? = nil,
        inputMailbox: GoldenEyeInputMailbox? = nil,
        audioService: GoldenEyeNativeAudioService? = nil,
        saveRuntime: GoldenEyeSaveRuntime? = nil,
        ramRomPlayback: GoldenEyeRamRomPlaybackService? = .fromEnvironment(),
        inputPoller: (() -> Void)? = nil,
        diagnosticTitleFlowEnabled: Bool = GoldenEyeNativeTitleOwner.defaultDiagnosticTitleFlowEnabled
    ) throws {
        self.renderer = renderer
        self.inputMailbox = inputMailbox
        self.audioService = audioService
        self.saveRuntime = saveRuntime ?? GoldenEyeSaveRuntime()
        self.ramRomPlayback = ramRomPlayback
        self.ramRomAuthority = ramRomPlayback.map(GoldenEyeRamRomAuthorityV6.init)
        self.inputPoller = inputPoller
        self.diagnosticTitleFlowEnabled = diagnosticTitleFlowEnabled
        if diagnosticTitleFlowEnabled {
            self.sourceAuthority = nil
        } else {
            // Initialization is deliberately eager.  Release must fail before
            // the owner starts if the source C authority cannot construct its
            // first copied frame.
            self.sourceAuthority = try GoldenEyeOriginalPairedAuthorityV6()
        }
        if let layer {
            guard let drawableRenderer = renderer as? GoldenEyeDrawableFrameRenderer else {
                preconditionFailure("Native title product requires supplied-drawable renderer ownership")
            }
            self.displayLink = GE120DisplayLinkRuntime(layer: layer) { drawable, timing in
                drawableRenderer.render(drawable: drawable, timing: timing)
            }
        } else {
            self.displayLink = nil
        }
        let box = CallbackBox()
        self.callbackBox = box
        self.engineOwner = GE120EngineOwner(
            displayLink: self.displayLink,
            measurementResetHandler: { [weak box] generation, rawNanoseconds in
                box?.owner?.resetMeasurementCounters(
                    generation: generation,
                    rawNanoseconds: rawNanoseconds
                )
            },
            gameResetHandler: { [weak box] in
                box?.owner?.resetGameState() ?? false
            }
        ) { [weak box] tick in
            box?.owner?.step(tick)
        }
        box.owner = self
        if !diagnosticTitleFlowEnabled {
            // Stage packet/material preparation is source-owned launch work,
            // not a measured 120 Hz step. Doing it before the owner starts
            // prevents the first RAMROM handoff from creating a multi-second
            // catch-up debt on the owner thread.
            stageScenePreparationAttempted = true
            do {
                try prepareStageSceneCatalog()
            } catch {
                stageScenePreparationAttempted = false
                try? "scenePrewarmError=\(error)\n".write(
                    toFile: "/tmp/goldeneye-stage-scene-owner.log",
                    atomically: false,
                    encoding: .utf8
                )
            }
        }
        if gameplayCameraSubmissionEnabled,
           !diagnosticTitleFlowEnabled,
           let request = makeSourceRamRomRequest() {
            do {
                prewarmedRamRomGameplay = try GoldenEyeRamRomGameplayOrchestratorV6.fromEnvironment(
                    request: request, atNativeTick: 0
                )
                prewarmedRamRomGameplayRequest = request
            } catch {
                prewarmedRamRomGameplayRequest = nil
                prewarmedRamRomGameplay = nil
            }
        }
        if diagnosticTitleFlowEnabled,
           let rawDemo = ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_RAMROM_DEMO_INDEX"],
           let demoIndex = UInt8(rawDemo), demoIndex < 14 {
            _ = diagnosticTitleFlow.requestRamRomDemo(catalogIndex: demoIndex)
        }
    }

    /// Debug-only opt-in for the old handwritten flow.  Release has no
    /// environment switch that can select it.
    private static var defaultDiagnosticTitleFlowEnabled: Bool {
        _isDebugAssertConfiguration() &&
            ProcessInfo.processInfo.environment["GOLDENEYE_DIAGNOSTIC_TITLE_FLOW"] == "1"
    }

    func start() {
        saveRuntime.start()
        try? audioService?.start()
        engineOwner.start()
        let presentationPath = displayLink == nil ? "compatibility" : "suppliedDrawable"
        let suppliedDrawable = displayLink == nil ? 0 : 1
        let authority = diagnosticTitleFlowEnabled ? "diagnostic-handwritten" : "original-paired-v6"
        try? "presentationPath=\(presentationPath) scheduler=native120 authority=\(authority) displayLink=\(suppliedDrawable) suppliedDrawable=\(suppliedDrawable) compatibilityDrawable=\(1 - suppliedDrawable)\n".write(
            toFile: "/tmp/goldeneye-native-title-owner.log",
            atomically: true,
            encoding: .utf8
        )
    }

    func waitUntilRunning(timeout: TimeInterval = 5.0) -> Bool {
        engineOwner.waitUntilRunning(timeout: timeout)
    }

    func submit(input: GoldenEyeKeyboardSnapshot) {
        lock.lock()
        pendingInput = GoldenEyeKeyboardSnapshot(
            sequence: input.sequence,
            held: input.held,
            pressed: pendingInput.pressed | input.pressed,
            released: pendingInput.released | input.released
        )
        lock.unlock()
    }

    func resetInput() {
        lock.lock()
        pendingInput = GoldenEyeKeyboardSnapshot(sequence: pendingInput.sequence, held: 0, pressed: 0, released: 0)
        lock.unlock()
    }

    func setPaused(_ paused: Bool) {
        // Freeze the Core Audio graph before rebasing the scheduler. The
        // realtime callback must not drain buffered PCM while owner ticks are
        // suspended.
        audioService?.setPaused(paused)
        engineOwner.requestPaused(paused)
    }

    func requestDrawableSize(_ size: CGSize) {
        engineOwner.requestDrawableSize(size)
    }

    func requestPreferredFrameRateRange(_ range: CAFrameRateRange) {
        engineOwner.requestPreferredFrameRateRange(range)
    }

    func telemetry() -> GE120EngineOwnerTelemetry {
        engineOwner.telemetry()
    }

    @discardableResult
    func resetMeasurementEpoch(timeout: TimeInterval = 5.0) -> Bool {
        engineOwner.resetMeasurementEpoch(timeout: timeout)
    }

    @discardableResult
    func resetGame(timeout: TimeInterval = 5.0) -> Bool {
        engineOwner.resetGame(timeout: timeout)
    }

    func saveRuntimeSnapshot() -> GoldenEyeSaveRuntimeSnapshot {
        saveRuntime.snapshot()
    }

    func stop() {
        engineOwner.stopAndWait()
        gameplayCameraSubmissionQueue.sync { }
        releaseStageServices()
        // Drain the two completion-fenced Metal slots before taking the
        // display telemetry snapshot. Presented handlers are asynchronous and
        // may only receive their non-zero presentedTime while the final GPU
        // work is draining; sampling first made every Release run report
        // presentedTimeSamples=0 despite successful present calls.
        renderer.shutdown()
        let telemetry = engineOwner.telemetry()
        let presentationPath = displayLink == nil ? "compatibility" : "suppliedDrawable"
        let suppliedDrawable = displayLink == nil ? 0 : 1
        let display = telemetry.display
        let scheduler = telemetry.scheduler
        let sampledSpanNanoseconds = scheduler.lastSampledNanoseconds >= scheduler.firstSampledNanoseconds
            ? scheduler.lastSampledNanoseconds - scheduler.firstSampledNanoseconds
            : 0
        let scheduledSpanNanoseconds = scheduler.lastScheduledNanoseconds >= scheduler.firstScheduledNanoseconds
            ? scheduler.lastScheduledNanoseconds - scheduler.firstScheduledNanoseconds
            : 0
        let logicElapsedSeconds = Double(sampledSpanNanoseconds) / 1_000_000_000
        let scheduledElapsedSeconds = Double(scheduledSpanNanoseconds) / 1_000_000_000
        let logicTickRate = logicElapsedSeconds > 0
            ? Double(scheduler.emittedTickCount > 1 ? scheduler.emittedTickCount - 1 : scheduler.emittedTickCount) / logicElapsedSeconds
            : 0
        let scheduledTickRate = scheduledElapsedSeconds > 0
            ? Double(scheduler.emittedTickCount > 1 ? scheduler.emittedTickCount - 1 : scheduler.emittedTickCount) / scheduledElapsedSeconds
            : 0
        let presentedSpan = (display?.lastPresentedTime ?? 0) - (display?.firstPresentedTime ?? 0)
        let presentedSamples = display?.presentedTimeSampleCount ?? 0
        let presentedFPS = presentedSpan > 0
            ? Double(presentedSamples > 1 ? presentedSamples - 1 : presentedSamples) / presentedSpan
            : 0
        let timebase = GE120TimebaseConfiguration.goldenEye
        let layer = displayLink?.currentLayer
        let authority = diagnosticTitleFlowEnabled ? "diagnostic-handwritten" : "original-paired-v6"
        let audioTelemetry = audioService?.pauseTelemetry
        let measurementTelemetry = telemetry
        let preferredFrameRateMinimum = display?.preferredFrameRateMinimum ?? 60
        let preferredFrameRateMaximum = display?.preferredFrameRateMaximum ?? 120
        let preferredFrameRatePreferred = display?.preferredFrameRatePreferred ?? 120
        let preferredFrameRateRange = "\(preferredFrameRateMinimum)-\(preferredFrameRateMaximum)/\(preferredFrameRatePreferred)"
        let line = "presentationPath=\(presentationPath) authority=\(authority) state=\(telemetry.state) "
            + "suppliedDrawable=\(suppliedDrawable) compatibilityDrawable=\(1 - suppliedDrawable) "
            + "schedulerClock=CLOCK_MONOTONIC_RAW nativeRate=\(timebase.nativeRateNumerator)/\(timebase.nativeRateDenominator) "
            + "referenceRate=\(timebase.referenceRateNumerator)/\(timebase.referenceRateDenominator) "
            + "maxCatchUpTicks=\(timebase.maxCatchUpTicks) maxDebtTicks=\(timebase.maxDebtTicks) "
            + "layerMaximumDrawableCount=\(layer?.maximumDrawableCount ?? 0) "
            + "layerDisplaySync=\((layer?.displaySyncEnabled ?? false) ? 1 : 0) "
            + "layerFramebufferOnly=\((layer?.framebufferOnly ?? false) ? 1 : 0) "
            + "preferredFrameRateRange=\(preferredFrameRateRange) "
            + "frameRateRangeOverrideVersion=\(display?.frameRateRangeOverrideVersion ?? "none") "
            + "audioPaused=\((audioTelemetry?.paused ?? false) ? 1 : 0) "
            + "audioPauseCount=\(audioTelemetry?.pauseCount ?? 0) "
            + "audioResumeCount=\(audioTelemetry?.resumeCount ?? 0) "
            + "sourceFrames=\(sourceFrameCount) sourceEvents=\(sourceEventCount) "
            + "sourceAuthorityFailure=\(sourceAuthorityFailure ?? "none") "
            + "measurementEpochGeneration=\(measurementTelemetry.measurementEpochGeneration) "
            + "measurementEpochRawNs=\(measurementTelemetry.measurementEpochNanoseconds) "
            + "schedulerMeasurementEpochRawNs=\(scheduler.measurementEpochNanoseconds) "
            + "displayMeasurementEpochRawNs=\(display?.measurementEpochNanoseconds ?? 0) "
            + "authorityStartStateHash=\(measurementStartStateHash) "
            + "authorityStartRenderHash=\(measurementStartRenderHash) "
            + "authorityStartAudioHash=\(measurementStartAudioHash) "
            + "authorityStartAudioEventHash=\(measurementStartAudioEventHash) "
            + "authorityEndStateHash=\(sourceLastStateHash) "
            + "authorityEndRenderHash=\(sourceLastRenderHash) "
            + "authorityEndAudioHash=\(sourceLastAudioHash) "
            + "authorityEndAudioEventHash=\(sourceLastAudioEventHash) "
            + "ownerThread=\(telemetry.ownerThreadIdentifier) "
            + "ticks=\(telemetry.scheduler.emittedTickCount) "
            + "logicStartRawNs=\(scheduler.firstSampledNanoseconds) "
            + "logicEndRawNs=\(scheduler.lastSampledNanoseconds) "
            + "logicElapsedMs=\(logicElapsedSeconds * 1000) "
            + "logicTickRateHz=\(logicTickRate) "
            + "scheduledTickRateHz=\(scheduledTickRate) "
            + "droppedTicks=\(scheduler.droppedTickCount) "
            + "lateWakes=\(scheduler.lateWakeCount) "
            + "catchUpBatches=\(scheduler.catchUpBatchCount) "
            + "catchUpTicks=\(scheduler.catchUpTickCount) "
            + "maximumDebtTicks=\(scheduler.maximumDebtTicks) "
            + "fatalDebtTicks=\(scheduler.fatalDebtTicks) "
            + "pauseCount=\(scheduler.pauseCount) "
            + "resumeCount=\(scheduler.resumeCount) "
            + "rebaseCount=\(scheduler.rebaseCount) "
            + "callbacks=\(display?.callbackCount ?? 0) "
            + "unexpectedCallbacks=\(display?.callbacksOnUnexpectedThread ?? 0) "
            + "marshaledCallbacks=\(display?.callbacksMarshaledToOwner ?? 0) "
            + "migrationMarshalTimeouts=\(display?.migrationMarshalTimeouts ?? 0) "
            + "marshaledCallbackDrops=\(display?.marshaledCallbackDropCount ?? 0) "
            + "staleCallbackDrops=\(display?.staleCallbackDropCount ?? 0) "
            + "unhandledUnexpectedCallbacks=\(display?.unhandledUnexpectedCallbacks ?? 0) "
            + "marshalQueueHighWater=\(display?.marshalQueueHighWater ?? 0) "
            + "deferredInitialFrames=\(display?.deferredInitialFrameCount ?? 0) "
            + "resizeApplies=\(display?.appliedResizeCount ?? 0) "
            + "rateApplies=\(display?.appliedRateCount ?? 0) "
            + "renderFailures=\(display?.renderFailureCount ?? 0) "
            + "targetDeltaCount=\(display?.targetDeltaCount ?? 0) "
            + "targetDeltaMinMs=\((display?.minimumTargetDelta ?? 0) * 1000) "
            + "targetDeltaMaxMs=\((display?.maximumTargetDelta ?? 0) * 1000) "
            + "targetDeltaMedianMs=\((display?.targetDeltaMedian ?? 0) * 1000) "
            + "targetDeltaP95Ms=\((display?.targetDeltaP95 ?? 0) * 1000) "
            + "targetSpanMs=\(((display?.lastTargetPresentationTimestamp ?? 0) - (display?.firstTargetPresentationTimestamp ?? 0)) * 1000) "
            + "presentedTimeSamples=\(display?.presentedTimeSampleCount ?? 0) "
            + "rejectedPresentedTimeSamples=\(display?.rejectedPresentedTimeSampleCount ?? 0) "
            + "presentedSpanMs=\(((display?.lastPresentedTime ?? 0) - (display?.firstPresentedTime ?? 0)) * 1000) "
            + "presentedFPS=\(presentedFPS) "
            + "presentedDeltaMinMs=\((display?.minimumPresentedDelta ?? 0) * 1000) "
            + "presentedDeltaMaxMs=\((display?.maximumPresentedDelta ?? 0) * 1000) "
            + "presentedDeltaMedianMs=\((display?.presentedDeltaMedian ?? 0) * 1000) "
            + "presentedDeltaP95Ms=\((display?.presentedDeltaP95 ?? 0) * 1000) "
            + "presentedOneSecondMinFrames=\(display?.minimumPresentedOneSecondFrames ?? 0) "
            + "presentedOneSecondWindows=\(display?.presentedOneSecondWindowCount ?? 0) "
            + "presentedWindowHash=\(display?.lastPresentedWindowHash ?? 0) "
            + "rendererCallbackCount=\(display?.callbackDurationCount ?? 0) "
            + "rendererCallbackMedianMs=\((display?.callbackDurationMedian ?? 0) * 1000) "
            + "rendererCallbackP95Ms=\((display?.callbackDurationP95 ?? 0) * 1000) "
            + "callbackDurationMaxMs=\((display?.maximumCallbackDuration ?? 0) * 1000) "
            + "rendererGPUTiming=\((display?.gpuTimingAvailable ?? false) ? "available" : "unavailable") "
            + "rendererGPUP95Ms=0 "
            + "lastPresentedTime=\(display?.lastPresentedTime ?? 0) "
            + "paused=\(display?.paused ?? false)\n"
        try? line.write(toFile: "/tmp/goldeneye-native-title-owner.log", atomically: true, encoding: .utf8)
        if didInitializeNative {
            lastStatus = ge_native_shutdown()
            didInitializeNative = false
        }
        saveRuntime.stop()
        audioService?.stop()
        _ = ramRomPlayback?.stopAfterFailure()
    }

    private func releaseStageServices() {
        if var lifecycle = stageLifecycle,
           let activeStageLifecycleID {
            _ = try? lifecycle.deactivate(stageID: activeStageLifecycleID)
            _ = try? lifecycle.unload(stageID: activeStageLifecycleID)
        }
        if var transferQueue = stageTransferQueue,
           let activeStageLifecycleID {
            _ = try? transferQueue.deactivate(stageID: activeStageLifecycleID)
            _ = try? transferQueue.unload(stageID: activeStageLifecycleID)
        }
        stageLifecycle = nil
        stageTransferQueue = nil
        activeStageLifecycleID = nil
    }

    private func takeGameplayCameraSubmissionFailure() -> String? {
        gameplayCameraSubmissionStateLock.lock()
        defer { gameplayCameraSubmissionStateLock.unlock() }
        let failure = gameplayCameraSubmissionFailure
        gameplayCameraSubmissionFailure = nil
        return failure
    }

    private func takeInput() -> GoldenEyeKeyboardSnapshot {
        lock.lock()
        let input = pendingInput
        pendingInput = GoldenEyeKeyboardSnapshot(
            sequence: input.sequence,
            held: input.held,
            pressed: 0,
            released: 0
        )
        lock.unlock()
        return input
    }

    /// Rebuild the source-authoritative state on the 120 Hz owner thread. The
    /// renderer remains alive so its Metal resources and prepared catalogs are
    /// reused; its next submitted frame replaces the old scene snapshot.
    private func resetGameState() -> Bool {
        precondition(engineOwner.isOwnerThread, "Game reset belongs to the owner thread")

        // Drain the bounded V7 submission queue before clearing its route
        // counters so an old composition cannot publish after the new source
        // authority starts.
        gameplayCameraSubmissionQueue.sync { }
        gameplayCameraSubmissionStateLock.lock()
        gameplayCameraSubmissionInFlight = false
        gameplayCameraSubmissionFailure = nil
        gameplayCameraSubmissionStateLock.unlock()

        if didInitializeNative {
            let shutdownStatus = ge_native_shutdown()
            guard shutdownStatus == GE_STATUS_OK else {
                sourceAuthorityFailure = "native shutdown during reset failed: \(shutdownStatus)"
                appendSourceOwnerEvidence("gameReset=0 reason=shutdown status=\(shutdownStatus)")
                return false
            }
            didInitializeNative = false
        }

        do {
            if diagnosticTitleFlowEnabled {
                diagnosticTitleFlow = GoldenEyeBootFlow()
                sourceAuthority = nil
            } else {
                sourceAuthority = try GoldenEyeOriginalPairedAuthorityV6()
            }
        } catch {
            sourceAuthorityFailure = String(describing: error)
            appendSourceOwnerEvidence("gameReset=0 reason=authority error=\(error)")
            return false
        }

        lock.lock()
        pendingInput = GoldenEyeKeyboardSnapshot(
            sequence: pendingInput.sequence,
            held: 0,
            pressed: 0,
            released: 0
        )
        lock.unlock()

        sourceAuthorityFailure = nil
        sourceModelHandshake = GoldenEyeSourceFrontendModelHandshakeV6()
        sourceInitializationLedger = GoldenEyeSourceFrontendInitializationLedgerV6()
        sourceFrameCount = 0
        sourceEventCount = 0
        sourceLastStateHash = 0
        sourceLastRenderHash = 0
        sourceLastAudioHash = 0
        sourceLastAudioEventHash = 0
        measurementStartStateHash = 0
        measurementStartRenderHash = 0
        measurementStartAudioHash = 0
        measurementStartAudioEventHash = 0
        didInstallSaveState = false
        lastSaveRuntimeRevision = 0
        lastAudioScreen = .legal
        didPlayGunbarrelRifleSFX = false
        fileModeAudioSessionActive = false
        sourceRamRomEndNeedsMenuInput = false
        _ = ramRomPlayback?.stopAfterFailure()
        stageScenePackets.removeAll(keepingCapacity: true)
        stageEnvironmentPackets.removeAll(keepingCapacity: true)
        stageMaterialPackets.removeAll(keepingCapacity: true)
        releaseStageServices()
        stageScenePreparationAttempted = false
        ramRomGameplayOrchestrator = nil
        ramRomGameplayLastFrame = nil
        prewarmedRamRomGameplayRequest = nil
        prewarmedRamRomGameplay = nil
        gameplayVisiblePropModelIndices.removeAll(keepingCapacity: true)
        gameplayCameraFramePublished = false
        gameplayCameraSubmissionCount = 0
        gameplayCameraNextSubmissionTick = 0
        productionCastRoute = nil
        productionCastSourceIndex = nil
        productionCastSeed = 0
        audioService?.resetForGame()
        appendSourceOwnerEvidence(
            "gameReset=1 authority=\(diagnosticTitleFlowEnabled ? "diagnostic-handwritten" : "original-paired-v6")"
        )
        return true
    }

    private func step(_ tick: GE120Tick) {
        guard sourceAuthorityFailure == nil else { return }
        if !didInitializeNative {
            var request = GEInitRequestV1()
            request.header.abi_version = UInt32(GE_NATIVE_ABI_VERSION)
            request.header.struct_size = UInt32(MemoryLayout<GEInitRequestV1>.size)
            request.flags = 0
            request.reserved = 0
            lastStatus = ge_native_initialize(request)
            guard lastStatus == GE_STATUS_OK else { return }
            didInitializeNative = true
        }

        inputPoller?()
        let keyboard = takeInput()
        let mailboxSnapshot = inputMailbox?.drain(at: tick.scheduledNanoseconds)
        if diagnosticTitleFlowEnabled,
           !didInstallSaveState,
           let loadedState = saveRuntime.snapshot().state {
            diagnosticTitleFlow.installSaveState(loadedState)
            didInstallSaveState = true
        }
        var nativeInput = GEInputSnapshotV1()
        nativeInput.header.abi_version = UInt32(GE_NATIVE_ABI_VERSION)
        nativeInput.header.struct_size = UInt32(MemoryLayout<GEInputSnapshotV1>.size)
        nativeInput.sequence = mailboxSnapshot?.sequence ?? tick.nativeTick
        nativeInput.held = mailboxSnapshot?.held ?? keyboard.held
        nativeInput.pressed = mailboxSnapshot?.pressed ?? keyboard.pressed
        nativeInput.released = mailboxSnapshot?.released ?? keyboard.released
        nativeInput.reserved = 0
        let result = ge_native_step(nativeInput)
        lastStatus = result.status
        guard result.status == GE_STATUS_OK else { return }

        // The additive source authority starts at native tick one by contract;
        // tick zero is the owner initialization sample. Do not feed that
        // sample into the source timeline or turn a valid launch into an
        // authority failure before the first source update.
        if !diagnosticTitleFlowEnabled, tick.nativeTick == 0 {
            audioService?.tick(nativeTick: tick.nativeTick)
            if displayLink == nil {
                _ = renderer.renderFrame()
            }
            return
        }

        if diagnosticTitleFlowEnabled {
            let titleSnapshot = diagnosticTitleFlow.step(
                input: mailboxSnapshot.map(titleInput(from:)) ?? titleInput(from: keyboard)
            )
            serviceRamRom(
                titleSnapshot: titleSnapshot,
                nativeTick: tick.nativeTick,
                mailboxInput: mailboxSnapshot,
                keyboardInput: keyboard
            )
            serviceDiagnosticAudio(titleSnapshot: titleSnapshot, nativeTick: tick.nativeTick)
            (renderer as? GoldenEyeTitleSnapshotRenderer)?.submit(titleSnapshot: titleSnapshot)
        } else {
            let sourceInput = mailboxSnapshot.map(sourceFrontendInput(from:))
                ?? sourceFrontendInput(from: keyboard)
            do {
                guard sourceAuthority != nil else {
                    throw GoldenEyeOriginalPairedAuthorityV6Error.originalStatus(
                        tick: tick.nativeTick,
                        screen: 0,
                        status: UInt32(GE_STATUS_INVALID_STATE)
                    )
                }
                if !sourceInitializationLedger.consumed {
                    try serviceSourceInitializationEvents(
                        frame: sourceAuthority!.lastFrame.authoritativeFrame
                    )
                }
                let modelResult = sourceModelHandshake.takeForAuthority()
                let wasGunbarrel = sourceAuthority!.nativeAuthority.state.screen ==
                    UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL)
                let effectiveButtonsPressed: UInt32
                if sourceRamRomEndNeedsMenuInput && tick.nativeTick & 1 == 0 {
                    effectiveButtonsPressed = sourceInput.buttonsPressed | UInt32(
                        GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_ANY
                    )
                    sourceRamRomEndNeedsMenuInput = false
                } else {
                    effectiveButtonsPressed = sourceInput.buttonsPressed
                }
                let pairedFrame = try sourceAuthority!.step(
                    nativeTick: tick.nativeTick,
                    buttonsPressed: effectiveButtonsPressed,
                    controllerCount: sourceInput.effectiveControllerCount,
                    fileModeControllerCount: sourceInput.physicalControllerCount,
                    clockTimer: sourceInput.clockTimer,
                    focused: sourceInput.focused,
                    controllerConnected: sourceInput.controllerConnected,
                    synthetic: false,
                    fileModeHeld: sourceInput.fileModeHeld,
                    fileModePressed: sourceInput.fileModePressed,
                    fileModeReleased: sourceInput.fileModeReleased,
                    fileModeStickX: sourceInput.fileModeStickX,
                    fileModeStickY: sourceInput.fileModeStickY,
                    modelResultModel: modelResult.model,
                    modelResultOperation: modelResult.operation,
                    modelResultFlags: modelResult.flags,
                    modelResultValue0: modelResult.value0,
                    modelResultValue1: modelResult.value1
                )
                let frame = pairedFrame.authoritativeFrame
                let enteringGunbarrel = !wasGunbarrel &&
                    frame.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL)
                if enteringGunbarrel,
                   let lifecycle = renderer as? GoldenEyeSourceFrontendModelLifecycleV6 {
                    // Cast/SWITCH frames are consumed by their own source
                    // owners and therefore do not pass through renderer.submit.
                    // Reset on the authoritative source transition instead of
                    // inferring entry from the renderer's stale last frame.
                    lifecycle.resetGunbarrelBloodStream()
                }
                sourceLastStateHash = frame.stateHash
                sourceLastRenderHash = frame.renderHash
                sourceLastAudioHash = frame.audioHash
                sourceLastAudioEventHash = frame.audioEventHash
                let castFrameConsumed = serviceSourceCast(
                    sourceFrame: frame,
                    nativeTick: tick.nativeTick
                )
                let stageFrameConsumed = serviceSourceRamRom(
                    sourceFrame: frame,
                    nativeTick: tick.nativeTick,
                    mailboxInput: mailboxSnapshot,
                    keyboardInput: keyboard
                )
                if !castFrameConsumed && !stageFrameConsumed {
                    try publishSourceFrontendFrame(frame, tick: tick)
                }
                sourceModelHandshake.retainSuccessfulResult(
                    (renderer as? GoldenEyeSourceFrontendModelResultProviderV6)?.takeModelExecutionResult()
                )
                let hasFileModeAudioSession = frame.fileModeFrame != nil
                if hasFileModeAudioSession && !fileModeAudioSessionActive {
                    audioService?.resetFileModeAudioSession()
                }
                fileModeAudioSessionActive = hasFileModeAudioSession
                audioService?.consume(
                    sourceAudioEvents: frame.audioEvents,
                    nativeTick: tick.nativeTick
                )
                if let fileModeFrame = frame.fileModeFrame {
                    audioService?.consume(
                        fileModeSFXEvents: fileModeFrame.events,
                        nativeTick: tick.nativeTick
                    )
                }
            } catch {
                sourceAuthorityFailure = String(describing: error)
                appendSourceOwnerEvidence(
                    "authorityFailure=\(sourceAuthorityFailure ?? "unknown") nativeTick=\(tick.nativeTick)"
                )
                return
            }
        }

        if diagnosticTitleFlowEnabled {
            saveRuntime.submit(state: diagnosticTitleFlow.saveStateSnapshot())
        }
        let saveSnapshot = saveRuntime.snapshot()
        if saveSnapshot.revision != lastSaveRuntimeRevision {
            lastSaveRuntimeRevision = saveSnapshot.revision
            let quarantine = saveSnapshot.quarantinedPath ?? "-"
            let line = "status=\(saveSnapshot.status.rawValue) persistence=\(saveSnapshot.persistenceEnabled ? 1 : 0) "
                + "generation=\(saveSnapshot.state?.generation ?? 0) revision=\(saveSnapshot.revision) "
                + "message=\(saveSnapshot.message) quarantine=\(quarantine)\n"
            try? line.write(toFile: "/tmp/goldeneye-save-runtime-owner.log", atomically: true, encoding: .utf8)
        }
        audioService?.tick(nativeTick: tick.nativeTick)
        if displayLink == nil {
            _ = renderer.renderFrame()
        }
        if tick.nativeTick % 120 == 0 {
            let telemetry = engineOwner.telemetry()
            let line = "nativeTick=\(tick.nativeTick) referenceTick=\(tick.referenceTick) "
                + "pairPhase=\(tick.pairPhase) emitted=\(telemetry.scheduler.emittedTickCount) "
                + "catchUp=\(telemetry.scheduler.catchUpTickCount) debt=\(telemetry.scheduler.maximumDebtTicks)\n"
            if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: "/tmp/goldeneye-native-120.log")) {
                handle.seekToEndOfFile()
                try? handle.write(contentsOf: Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(
                    to: URL(fileURLWithPath: "/tmp/goldeneye-native-120.log"),
                    options: .atomic
                )
            }
        }
    }

    private struct SourceFrontendInput {
        let buttonsPressed: UInt32
        let effectiveControllerCount: UInt32
        let physicalControllerCount: UInt32
        let clockTimer: UInt32
        let focused: Bool
        let controllerConnected: Bool
        let fileModeHeld: UInt32
        let fileModePressed: UInt32
        let fileModeReleased: UInt32
        let fileModeStickX: Int16
        let fileModeStickY: Int16
    }

    private func sourceFrontendInput(from input: GoldenEyeInputSnapshot) -> SourceFrontendInput {
        let pressed = input.pressed
        var buttons: UInt32 = 0
        if pressed != 0 { buttons |= UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_ANY) }
        if pressed & (GoldenEyeN64Buttons.a.rawValue | GoldenEyeN64Buttons.z.rawValue | GoldenEyeN64Buttons.start.rawValue) != 0 {
            buttons |= UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_CONFIRM)
        }
        if pressed & GoldenEyeN64Buttons.b.rawValue != 0 {
            buttons |= UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_CANCEL)
        }
        if pressed & GoldenEyeN64Buttons.dpadUp.rawValue != 0 {
            buttons |= UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_UP)
        }
        if pressed & GoldenEyeN64Buttons.dpadDown.rawValue != 0 {
            buttons |= UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_DOWN)
        }
        if pressed & GoldenEyeN64Buttons.dpadLeft.rawValue != 0 {
            buttons |= UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_LEFT)
        }
        if pressed & GoldenEyeN64Buttons.dpadRight.rawValue != 0 {
            buttons |= UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_RIGHT)
        }
        let sourceFlags = GoldenEyeInputSourceFlags(rawValue: input.sourceFlags)
        // OS focus suppresses new input in the mailbox, but it must not stop
        // the source frontend clock.  The keyboard-backed virtual controller
        // remains connected while GoldenEye is backgrounded so Legal/File/
        // Mode/Cast/RAMROM continue to advance with a neutral snapshot.
        let keyboardActive = sourceFlags.contains(.keyboard) ||
            input.physicalControllerCount == 0
        let effectiveCount = max(
            input.physicalControllerCount,
            keyboardActive ? 1 : 0
        )
        return SourceFrontendInput(
            buttonsPressed: buttons,
            effectiveControllerCount: effectiveCount,
            physicalControllerCount: input.physicalControllerCount,
            clockTimer: 1,
            focused: true,
            controllerConnected: sourceFlags.contains(.controllerConnected) || keyboardActive,
            fileModeHeld: Self.fileModeButtons(fromN64: input.held),
            fileModePressed: Self.fileModeButtons(fromN64: input.pressed),
            fileModeReleased: Self.fileModeButtons(fromN64: input.released),
            fileModeStickX: input.stickX,
            fileModeStickY: input.stickY
        )
    }

    private func sourceFrontendInput(from keyboard: GoldenEyeKeyboardSnapshot) -> SourceFrontendInput {
        let pressed = keyboard.pressed
        var buttons: UInt32 = 0
        if pressed != 0 { buttons |= UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_ANY) }
        if pressed & ((1 << 4) | (1 << 15) | (1 << 16) | (1 << 17)) != 0 {
            buttons |= UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_CONFIRM)
        }
        if pressed & (1 << 5) != 0 {
            buttons |= UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_CANCEL)
        }
        if pressed & ((1 << 9) | (1 << 3)) != 0 {
            buttons |= UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_UP)
        }
        if pressed & (1 << 8) != 0 {
            buttons |= UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_DOWN)
        }
        if pressed & (1 << 6) != 0 {
            buttons |= UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_LEFT)
        }
        if pressed & (1 << 7) != 0 {
            buttons |= UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_RIGHT)
        }
        return SourceFrontendInput(
            buttonsPressed: buttons,
            effectiveControllerCount: 1,
            physicalControllerCount: 0,
            clockTimer: 1,
            focused: true,
            controllerConnected: true,
            fileModeHeld: Self.fileModeButtons(fromKeyboard: keyboard.held),
            fileModePressed: Self.fileModeButtons(fromKeyboard: keyboard.pressed),
            fileModeReleased: Self.fileModeButtons(fromKeyboard: keyboard.released),
            fileModeStickX: Self.keyboardStickX(keyboard.held),
            fileModeStickY: Self.keyboardStickY(keyboard.held)
        )
    }

    private static func fileModeButtons(fromN64 buttons: UInt32) -> UInt32 {
        var result: UInt32 = 0
        if buttons & GoldenEyeN64Buttons.a.rawValue != 0 { result |= UInt32(GE_FILE_MODE_V6_BUTTON_A) }
        if buttons & GoldenEyeN64Buttons.b.rawValue != 0 { result |= UInt32(GE_FILE_MODE_V6_BUTTON_B) }
        if buttons & GoldenEyeN64Buttons.start.rawValue != 0 { result |= UInt32(GE_FILE_MODE_V6_BUTTON_START) }
        if buttons & GoldenEyeN64Buttons.z.rawValue != 0 { result |= UInt32(GE_FILE_MODE_V6_BUTTON_Z) }
        if buttons & GoldenEyeN64Buttons.leftShoulder.rawValue != 0 { result |= UInt32(GE_FILE_MODE_V6_BUTTON_L) }
        if buttons & GoldenEyeN64Buttons.rightShoulder.rawValue != 0 { result |= UInt32(GE_FILE_MODE_V6_BUTTON_R) }
        if buttons & GoldenEyeN64Buttons.dpadUp.rawValue != 0 { result |= UInt32(GE_FILE_MODE_V6_BUTTON_DPAD_UP) }
        if buttons & GoldenEyeN64Buttons.dpadDown.rawValue != 0 { result |= UInt32(GE_FILE_MODE_V6_BUTTON_DPAD_DOWN) }
        if buttons & GoldenEyeN64Buttons.dpadLeft.rawValue != 0 { result |= UInt32(GE_FILE_MODE_V6_BUTTON_DPAD_LEFT) }
        if buttons & GoldenEyeN64Buttons.dpadRight.rawValue != 0 { result |= UInt32(GE_FILE_MODE_V6_BUTTON_DPAD_RIGHT) }
        if buttons & GoldenEyeN64Buttons.cUp.rawValue != 0 { result |= UInt32(GE_FILE_MODE_V6_BUTTON_C_UP) }
        if buttons & GoldenEyeN64Buttons.cDown.rawValue != 0 { result |= UInt32(GE_FILE_MODE_V6_BUTTON_C_DOWN) }
        if buttons & GoldenEyeN64Buttons.cLeft.rawValue != 0 { result |= UInt32(GE_FILE_MODE_V6_BUTTON_C_LEFT) }
        if buttons & GoldenEyeN64Buttons.cRight.rawValue != 0 { result |= UInt32(GE_FILE_MODE_V6_BUTTON_C_RIGHT) }
        return result
    }

    private static func fileModeButtons(fromKeyboard buttons: UInt32) -> UInt32 {
        var n64: UInt32 = 0
        if buttons & (1 << 4) != 0 { n64 |= GoldenEyeN64Buttons.a.rawValue }
        if buttons & (1 << 5) != 0 { n64 |= GoldenEyeN64Buttons.b.rawValue }
        if buttons & (1 << 15) != 0 { n64 |= GoldenEyeN64Buttons.start.rawValue }
        if buttons & (1 << 16) != 0 { n64 |= GoldenEyeN64Buttons.z.rawValue }
        if buttons & (1 << 3) != 0 || buttons & (1 << 9) != 0 { n64 |= GoldenEyeN64Buttons.dpadUp.rawValue }
        if buttons & (1 << 8) != 0 { n64 |= GoldenEyeN64Buttons.dpadDown.rawValue }
        if buttons & (1 << 6) != 0 { n64 |= GoldenEyeN64Buttons.dpadLeft.rawValue }
        if buttons & (1 << 7) != 0 { n64 |= GoldenEyeN64Buttons.dpadRight.rawValue }
        return fileModeButtons(fromN64: n64)
    }

    private static func keyboardStickX(_ held: UInt32) -> Int16 {
        if held & (1 << 6) != 0 && held & (1 << 7) == 0 { return -75 }
        if held & (1 << 7) != 0 && held & (1 << 6) == 0 { return 75 }
        return 0
    }

    private static func keyboardStickY(_ held: UInt32) -> Int16 {
        if held & (1 << 9) != 0 && held & (1 << 8) == 0 { return 75 }
        if held & (1 << 8) != 0 && held & (1 << 9) == 0 { return -75 }
        return 0
    }

    private func serviceSourceInitializationEvents(
        frame: GoldenEyeSourceFrontendFrameV6
    ) throws {
        guard try sourceInitializationLedger.consume(frame: frame) else { return }

        // Tick-zero STOP_MUSIC/other cues are source events at sample index
        // zero, not inferred screen transitions.  The audio service's V6
        // binding owns the exactly-once filtering and route semantics.
        audioService?.consume(sourceAudioEvents: frame.audioEvents, nativeTick: 0)

        var lines: [String] = [
            "initEvents=1 tick=0 screenEvents=\(frame.screenEvents.count) "
                + "modelEvents=\(frame.modelEvents.count) audioEvents=\(frame.audioEvents.count) "
                + "saveEvents=\(frame.saveEvents.count)"
        ]
        lines.append(contentsOf: frame.screenEvents.map {
            "initScreenEvent=\($0.event) screen=\($0.screen) target=\($0.targetScreen) sequence=\($0.sequence)"
        })

        for event in frame.modelEvents {
            guard event.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_LOAD) else {
                lines.append(
                    "initModelEvent=\(event.model) operation=\(event.operation) handled=0"
                )
                continue
            }
            if let lifecycle = renderer as? GoldenEyeSourceFrontendModelLifecycleV6 {
                try lifecycle.acknowledgeSourceModelLoad(model: event.model)
                _ = sourceInitializationLedger.acknowledgeModelLoad(model: event.model)
                lines.append("initModelLoad=\(event.model) handled=preparation")
            } else {
                lines.append("initModelLoad=\(event.model) handled=pending-draw")
            }
        }

        for event in frame.saveEvents {
            if event.operation == 1 { // GE_SOURCE_FRONTEND_V6_SAVE_VALIDATE
                let saveSnapshot = saveRuntime.snapshot()
                if let state = saveSnapshot.state {
                    try GoldenEyeSaveActions.validate(state)
                    lines.append(
                        "initSaveValidate=1 result=validated revision=\(saveSnapshot.revision)"
                    )
                } else {
                    // SaveStore performs the asynchronous wire-format load;
                    // preserve this source validation event as pending rather
                    // than manufacturing a blank state while it is loading.
                    lines.append(
                        "initSaveValidate=1 result=pending status=\(saveSnapshot.status.rawValue) revision=\(saveSnapshot.revision)"
                    )
                }
            } else {
                lines.append(
                    "initSaveEvent=\(event.operation) folder=\(event.folder) handled=0"
                )
            }
        }
        appendSourceOwnerEvidence(lines.joined(separator: "\n"))
    }

    private func publishSourceFrontendFrame(
        _ frame: GoldenEyeSourceFrontendFrameV6,
        tick: GE120Tick
    ) throws {
        sourceFrameCount &+= 1
        sourceEventCount &+= UInt64(
            frame.screenEvents.count + frame.modelEvents.count + frame.textEvents.count
                + frame.audioEvents.count + frame.saveEvents.count
                + frame.renderEvents.count + frame.diagnosticEvents.count
        )
        do {
            guard let sourceRenderer = renderer as? GoldenEyeSourceFrontendFrameRendererV6 else {
                throw GoldenEyeSourceFrontendOwnerError.rendererDoesNotAcceptSourceFrames
            }
            try sourceRenderer.submit(sourceFrontendFrame: frame)
        } catch {
            appendSourceOwnerEvidence("submissionFailure=\(error) tick=\(tick.nativeTick)")
            throw error
        }

        for event in frame.modelEvents where
            event.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_DRAW) {
            if sourceInitializationLedger.acknowledgeModelLoad(model: event.model) {
                appendSourceOwnerEvidence(
                    "initModelLoad=\(event.model) handled=pending-draw tick=\(tick.nativeTick)"
                )
            }
        }

        var lines: [String] = []
        lines.append(
            "tick=\(tick.nativeTick) sourceTick=\(frame.nativeTick) referenceTick=\(frame.referenceTick) "
                + "screen=\(frame.screen) subphase=\(frame.subphase) timer=\(frame.sourceTimer) "
                + "unsupported=\(frame.unsupportedCount) stateHash=\(frame.stateHash) "
                + "renderHash=\(frame.renderHash) audioHash=\(frame.audioHash) "
                + "screenHash=\(frame.screenHash) modelHash=\(frame.modelHash) "
                + "textHash=\(frame.textHash) audioEventHash=\(frame.audioEventHash) "
                + "saveHash=\(frame.saveHash) renderEventHash=\(frame.renderEventHash) "
                + "diagnosticHash=\(frame.diagnosticHash)"
        )
        lines.append(contentsOf: frame.screenEvents.map {
            "screenEvent=\($0.event) screen=\($0.screen) target=\($0.targetScreen) "
                + "sourceTimer=\($0.sourceTimer) sequence=\($0.sequence)"
        })
        lines.append(contentsOf: frame.modelEvents.map {
            "modelEvent=\($0.model) operation=\($0.operation) subphase=\($0.subphase) "
                + "resultFlags=\($0.resultFlags) value0=\($0.resultValue0) value1=\($0.resultValue1)"
        })
        lines.append(contentsOf: frame.textEvents.map {
            "textEvent=\($0.textID) x=\($0.x) y=\($0.y) flags=\($0.flags)"
        })
        lines.append(contentsOf: frame.audioEvents.map {
            "audioEvent=\($0.operation) asset=\($0.assetID) sample=\($0.sourceSample)"
        })
        lines.append(contentsOf: frame.saveEvents.map {
            "saveEvent=\($0.operation) folder=\($0.folder)"
        })
        lines.append(contentsOf: frame.renderEvents.map {
            "renderEvent=\($0.operation) subphase=\($0.subphase) value0=\($0.value0) value1=\($0.value1)"
        })
        lines.append(contentsOf: frame.diagnosticEvents.map {
            "diagnostic=\($0.code) severity=\($0.severity) detail0=\($0.detail0) detail1=\($0.detail1)"
        })
        appendSourceOwnerEvidence(lines.joined(separator: "\n"))
    }

    private func appendSourceOwnerEvidence(_ body: String) {
        let line = body + "\n"
        let url = URL(fileURLWithPath: "/tmp/goldeneye-source-frontend-owner.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            try? handle.write(contentsOf: Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url, options: .atomic)
        }
    }

    private func appendGameplayCameraOwnerEvidence(_ body: String) {
        let line = body + "\n"
        let url = URL(fileURLWithPath: "/tmp/goldeneye-stage-gameplay-camera-owner.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            try? handle.write(contentsOf: Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url, options: .atomic)
        }
    }

    /// Called by the owner thread exactly at the measurement boundary. The
    /// source authority hash values are retained as an explicit warmup-end
    /// boundary; source failure remains sticky and is never hidden by reset.
    private func resetMeasurementCounters(generation: UInt64, rawNanoseconds: UInt64) {
        measurementEpochGeneration = generation
        measurementEpochNanoseconds = rawNanoseconds
        measurementStartStateHash = sourceLastStateHash
        measurementStartRenderHash = sourceLastRenderHash
        measurementStartAudioHash = sourceLastAudioHash
        measurementStartAudioEventHash = sourceLastAudioEventHash
        sourceFrameCount = 0
        sourceEventCount = 0
        appendSourceOwnerEvidence(
            "measurementEpochReset=1 generation=\(generation) rawNs=\(rawNanoseconds) "
                + "stateHash=\(measurementStartStateHash) "
                + "renderHash=\(measurementStartRenderHash) "
                + "audioHash=\(measurementStartAudioHash) "
                + "audioEventHash=\(measurementStartAudioEventHash)"
        )
    }

    private func serviceDiagnosticAudio(
        titleSnapshot: GoldenEyeTitleSnapshot,
        nativeTick: UInt64
    ) {
        if titleSnapshot.screen != lastAudioScreen {
            if titleSnapshot.screen != .gunbarrel {
                didPlayGunbarrelRifleSFX = false
            }
            switch titleSnapshot.screen {
            case .nintendo:
                audioService?.play(.nintendo, nativeTick: nativeTick)
            case .rareware:
                audioService?.playSFX(258, nativeTick: nativeTick)
            case .gunbarrel:
                audioService?.play(.gunbarrel, nativeTick: nativeTick)
            case .fileSelect:
                audioService?.play(.folders, nativeTick: nativeTick)
                audioService?.playSFX(18, nativeTick: nativeTick)
            default:
                break
            }
            lastAudioScreen = titleSnapshot.screen
        }
        if titleSnapshot.screen == .gunbarrel,
           !didPlayGunbarrelRifleSFX,
           titleSnapshot.gunbarrelTimer120 >= 460 {
            audioService?.playSFX(111, nativeTick: nativeTick)
            didPlayGunbarrelRifleSFX = true
        }
    }

    /// Production source-front-end handoff for the complete source Cast route.
    /// The owner keeps a copied source-randomized roster cursor and submits
    /// every selected row through the guarded extended Cast catalog. An
    /// explicit source index is accepted only as a deterministic test override;
    /// Release otherwise advances the source-ordered route and never falls
    /// back to Bond or a procedural character.
    private func serviceSourceCast(
        sourceFrame: GoldenEyeSourceFrontendFrameV6,
        nativeTick: UInt64
    ) -> Bool {
        guard !diagnosticTitleFlowEnabled,
              sourceFrame.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_CAST),
              sourceFrame.sourceTimer < 181,
              let renderer = renderer as? GoldenEyeCastSourceSceneFrameRendererV6 else {
            return false
        }
        if gameplayCameraSubmissionEnabled && gameplayCameraFramePublished {
            // The bounded V7 production lane retains its first submitted
            // gameplay frame for supplied-drawable inspection; source Cast
            // authority/playback continues, but later Cast packets must not
            // replace the published stage scene before it is observed.
            return true
        }
        do {
            let explicitIndex = ProcessInfo.processInfo.environment[
                "GOLDENEYE_NATIVE_CAST_SOURCE_INDEX"
            ].flatMap(UInt16.init)
            if productionCastRoute == nil && productionCastSourceIndex == nil {
                if let explicitIndex {
                    guard explicitIndex < 30 else {
                        throw GoldenEyeCastSceneV6Error.invalidSourceIndex(explicitIndex)
                    }
                    productionCastSourceIndex = explicitIndex
                } else {
                    let catalog = GoldenEyeRamRomRouteCatalog.fromEnvironment()
                    productionCastSeed = Self.sourceCastSeed()
                    var route = GoldenEyeAttractRoute(
                        catalog: catalog,
                        randomSeed: productionCastSeed
                    )
                    productionCastSourceIndex = route.beginCast(.normalAttract)
                    productionCastRoute = route
                }
            } else if sourceFrame.sourceTimer == 0,
                      explicitIndex == nil,
                      var route = productionCastRoute {
                    switch route.advanceCast() {
                    case .showCast(let next):
                        productionCastSourceIndex = next
                    case .launchDemo, .missionSelect, .catalogUnavailable:
                        productionCastRoute = route
                        return false
                    }
                    productionCastRoute = route
                }
            guard let sourceIndex = productionCastSourceIndex else {
                throw GoldenEyeCastSceneV6Error.authorityMismatch(
                    "source Cast roster cursor is unavailable"
                )
            }
            let identity = try GoldenEyeCastSourceTableV6.identity(
                sourceIndex: sourceIndex
            )
            let generatedRandomWord = Self.sourceCastWord(
                seed: productionCastSeed == 0 ? Self.sourceCastSeed() : productionCastSeed,
                sourceIndex: sourceIndex,
                nativeTick: nativeTick
            )
            // A deterministic source-index override may also carry the
            // copied second random word used by front.c's Natalya variant.
            // Keep this test-only seam opt-in and ignore it for the normal
            // source-ordered route so production never invents roster state.
            let randomWord = explicitIndex == nil
                ? generatedRandomWord
                : (Self.sourceCastRandomWordOverride() ?? generatedRandomWord)
            let animation = try GoldenEyeCastSceneComposerV6.animation(
                randomWord: randomWord
            )
            let weapon: GoldenEyeCastWeaponV6? = animation.usesWeaponCamera
                ? (animation.cameraPreset == 2
                    ? GoldenEyeCastSourceTableV6.rifleWeapons[
                        Int(randomWord % UInt32(GoldenEyeCastSourceTableV6.rifleWeapons.count))
                    ]
                    : GoldenEyeCastSourceTableV6.pistolWeapons[
                        Int(randomWord % UInt32(GoldenEyeCastSourceTableV6.pistolWeapons.count))
                    ])
                : nil
            let cameraWord0 = Self.sourceCastWord(
                seed: UInt64(randomWord), sourceIndex: sourceIndex, nativeTick: 0
            )
            let cameraWord1 = Self.sourceCastWord(
                seed: UInt64(randomWord), sourceIndex: sourceIndex, nativeTick: 1
            )
            let cameraWord2 = Self.sourceCastWord(
                seed: UInt64(randomWord), sourceIndex: sourceIndex, nativeTick: 2
            )
            let distanceQ16 = Int32(
                clamping: 70 * 65_536 + Int64(cameraWord0 % (80 * 65_536))
            )
            let angleFraction = Double(cameraWord1) / Double(UInt32.max)
            let angleQ16 = Int32(
                ((angleFraction - 0.5) * Double.pi * 2.0 * 65_536.0).rounded()
            )
            let heightQ16 = Int32(
                clamping: -100 * 65_536 + Int64(cameraWord2 % (200 * 65_536))
            )
            let flip = (Self.sourceCastWord(
                seed: UInt64(randomWord), sourceIndex: sourceIndex, nativeTick: 3
            ) & 1) != 0
            let fadeQ16: Int32
            if sourceFrame.sourceTimer < 30 {
                fadeQ16 = Int32(
                    (Double(sourceFrame.sourceTimer) / 30.0 * 65_536.0).rounded()
                )
            } else if sourceFrame.sourceTimer >= 151 {
                fadeQ16 = Int32(
                    (Double(181 - sourceFrame.sourceTimer) / 30.0 * 65_536.0).rounded()
                )
            } else {
                fadeQ16 = 65_536
            }
            let request = try GoldenEyeCastSourceSceneRequestV6(
                identity: identity,
                animation: animation,
                weapon: weapon,
                nativeTick: nativeTick,
                sourceTimer: sourceFrame.sourceTimer,
                sourceFrameQ16: Int32(
                    clamping: Int64(sourceFrame.sourceTimer) *
                        Int64(animation.playbackSpeedQ16)
                ),
                fadeQ16: max(0, min(65_536, fadeQ16)),
                randomWord: randomWord,
                cameraDistanceQ16: distanceQ16,
                cameraAngleQ16: angleQ16,
                cameraHeightQ16: heightQ16,
                flip: flip
            )
            try renderer.submit(castSceneRequest: request)
            appendSourceOwnerEvidence(
                "castSceneSubmit=1 tick=\(nativeTick) sourceIndex=\(sourceIndex) "
                    + "sourceTimer=\(sourceFrame.sourceTimer)"
            )
            return true
        } catch {
            sourceAuthorityFailure = "source Cast scene: \(error)"
            writeRamRomFailure(error)
            return true
        }
    }

    private static func sourceCastSeed() -> UInt64 {
        guard let raw = ProcessInfo.processInfo.environment[
            "GOLDENEYE_TITLE_RANDOM_SEED"
        ] else { return 1 }
        let isHex = raw.hasPrefix("0x") || raw.hasPrefix("0X")
        return UInt64(
            isHex ? String(raw.dropFirst(2)) : raw,
            radix: isHex ? 16 : 10
        ) ?? 1
    }

    private static func sourceCastRandomWordOverride() -> UInt32? {
        guard let raw = ProcessInfo.processInfo.environment[
            "GOLDENEYE_NATIVE_CAST_RANDOM_WORD"
        ], !raw.isEmpty else { return nil }
        let isHex = raw.hasPrefix("0x") || raw.hasPrefix("0X")
        return UInt32(
            isHex ? String(raw.dropFirst(2)) : raw,
            radix: isHex ? 16 : 10
        )
    }

    private static func sourceCastWord(
        seed: UInt64,
        sourceIndex: UInt16,
        nativeTick: UInt64
    ) -> UInt32 {
        var value = seed &+
            UInt64(sourceIndex) &* 0x9E37_79B9 &+
            nativeTick &* 0xD1B5_4A32_D192_ED03
        value ^= value >> 30
        value &*= 0xBF58_476D_1CE4_E5B9
        value ^= value >> 27
        value &*= 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return UInt32(truncatingIfNeeded: value)
    }

    private func serviceSourceRamRom(
        sourceFrame: GoldenEyeSourceFrontendFrameV6,
        nativeTick: UInt64,
        mailboxInput: GoldenEyeInputSnapshot?,
        keyboardInput: GoldenEyeKeyboardSnapshot
    ) -> Bool {
        let castEndTransition = sourceFrame.screen ==
            UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_SWITCH)
            && sourceFrame.screenEvents.contains {
                $0.event == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_EVENT_TRANSITION)
                    && $0.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_CAST)
                    && $0.targetScreen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_CAST)
            }
        guard !diagnosticTitleFlowEnabled,
              let ramRomPlayback,
              let ramRomAuthority else { return false }
        let activeSwitchPlayback = ramRomAuthority.isActive
            && sourceFrame.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_SWITCH)
        guard sourceFrame.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_CAST)
                || castEndTransition || activeSwitchPlayback else { return false }

        if !ramRomAuthority.isActive,
           (sourceFrame.sourceTimer >= 181 || castEndTransition),
           let request = makeSourceRamRomRequest() {
            do {
                _ = prepareStageScene(stageID: request.stageID)
                let scene = stageScenePackets[request.stageID]
                let environmentPacket = stageEnvironmentPackets[request.stageID]
                let coverage = scene.map { packet in
                    GoldenEyeRamRomStageCoverageV6.from(
                        packet: packet,
                        environmentPacket: environmentPacket,
                        materialPacket: stageMaterialPackets[packet.stageID],
                        stageTexturesReady: (renderer as? GoldenEyeStageSourceMaterialFrameRendererV6)?.stageTextureDependenciesReady ?? false
                    )
                }
                let beginFrame = try ramRomAuthority.begin(
                    request: request,
                    // A Cast-end transition spends four source anchors in
                    // SWITCH before the next Cast frame is visible. Start
                    // the playback clock at that next Cast anchor so the C
                    // service's first relative sample remains zero.
                    atNativeTick: castEndTransition ? nativeTick &+ 8 : nativeTick,
                    stageCoverage: coverage,
                    environmentPacket: environmentPacket
                )
                let gameplayStartTick = ((castEndTransition ? nativeTick &+ 8 : nativeTick) | 1) &+ 1
                do {
                    if let prewarmedRequest = prewarmedRamRomGameplayRequest,
                       prewarmedRequest == request,
                       let prewarmedGameplay = prewarmedRamRomGameplay {
                        try prewarmedGameplay.rebaseStartNativeTick(gameplayStartTick)
                        ramRomGameplayOrchestrator = prewarmedGameplay
                        prewarmedRamRomGameplayRequest = nil
                        prewarmedRamRomGameplay = nil
                    } else {
                        ramRomGameplayOrchestrator = try GoldenEyeRamRomGameplayOrchestratorV6.fromEnvironment(
                            request: request, atNativeTick: gameplayStartTick
                        )
                    }
                    ramRomGameplayLastFrame = nil
                } catch {
                    if gameplayCameraSubmissionEnabled {
                        throw error
                    }
                    ramRomGameplayOrchestrator = nil
                    sourceAuthorityFailure = "source RAMROM gameplay begin: \(error)"
                    writeRamRomFailure(error)
                }
                if !gameplayCameraSubmissionEnabled, let environmentPacket {
                    try submitStageEnvironment(
                        packet: environmentPacket,
                        nativeTick: nativeTick
                    )
                }
                writeRamRomAuthorityFrame(beginFrame, prefix: "source-begin")
            } catch {
                sourceAuthorityFailure = "source RAMROM begin: \(error)"
                writeRamRomFailure(error)
                return false
            }
        }

        guard ramRomAuthority.isActive else { return false }
        let titleInput = mailboxInput.map(titleInput(from:)) ?? titleInput(from: keyboardInput)
        do {
            guard let authorityFrame = try ramRomAuthority.step(
                nativeTick: nativeTick,
                input: GoldenEyeRamRomServiceInput(
                    pressedButtons: UInt32(titleInput.pressed),
                    heldButtons: UInt32(titleInput.held),
                    releasedButtons: UInt32(titleInput.released),
                    focused: titleInput.focused,
                    sourceMask: mailboxInput?.sourceFlags ?? 0
                )
            ) else { return false }
            var didSubmitGameplayCamera = false
            if let gameplayOrchestrator = ramRomGameplayOrchestrator {
                do {
                    let externalInput = authorityFrame.isRealInputAbort
                        ? GoldenEyeRamRomGameplayOrchestratorV6.externalInput(
                            GoldenEyeRamRomServiceInput(
                                pressedButtons: UInt32(titleInput.pressed),
                                heldButtons: UInt32(titleInput.held),
                                releasedButtons: UInt32(titleInput.released),
                                focused: titleInput.focused,
                                sourceMask: mailboxInput?.sourceFlags ?? 0
                            )
                        )
                        : nil
                    let gameplayFrame = try gameplayOrchestrator.step(
                        nativeTick: nativeTick, externalInput: externalInput
                    )
                    ramRomGameplayLastFrame = gameplayFrame
                    writeRamRomGameplayFrame(gameplayFrame, prefix: "source-runtime")
                    if gameplayCameraSubmissionEnabled {
                        if let failure = takeGameplayCameraSubmissionFailure() {
                            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                                "V7 gameplay-camera submission failed: \(failure)"
                            )
                        }
                        guard let gameplayRenderer = renderer as? GoldenEyeStageGameplayCameraFrameRendererV7 else {
                            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                                "V7 gameplay-camera route requires the source product renderer"
                            )
                        }
                        if nativeTick & 1 == 0,
                           nativeTick >= gameplayCameraNextSubmissionTick,
                           gameplayCameraSubmissionCount < gameplayCameraAnchorWindow {
                            let accepted = try submitGameplayCamera(
                                frame: gameplayFrame,
                                nativeTick: nativeTick,
                                receiver: gameplayRenderer,
                                windowIndex: gameplayCameraSubmissionCount
                            )
                            if accepted {
                                gameplayCameraFramePublished = true
                                gameplayCameraSubmissionCount &+= 1
                                gameplayCameraNextSubmissionTick = nativeTick &+
                                    gameplayCameraAnchorInterval
                            }
                        }
                        didSubmitGameplayCamera = gameplayCameraSubmissionCount > 0
                    }
                } catch {
                    sourceAuthorityFailure = "source RAMROM gameplay step: \(error)"
                    writeRamRomFailure(error)
                    if gameplayCameraSubmissionEnabled {
                        throw error
                    }
                    ramRomGameplayOrchestrator = nil
                }
            }
            if gameplayCameraSubmissionEnabled {
                guard didSubmitGameplayCamera else {
                    throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                        "V7 gameplay-camera route did not submit a scoped frame"
                    )
                }
            } else if !didSubmitGameplayCamera,
               let environmentPacket = ramRomAuthority.environmentPacket {
                try submitStageEnvironment(
                    packet: environmentPacket,
                    nativeTick: nativeTick
                )
            }
            if authorityFrame.isFadeToTitle || authorityFrame.isReturnToTitle {
                writeRamRomAuthorityFrame(authorityFrame, prefix: "source-runtime")
            }
            if authorityFrame.isReturnToTitle {
                _ = ramRomPlayback.takeRestoreSnapshot()
                sourceRamRomEndNeedsMenuInput = true
                ramRomGameplayOrchestrator = nil
                productionCastRoute = nil
                productionCastSourceIndex = nil
            }
            return true
        } catch {
            sourceAuthorityFailure = "source RAMROM step: \(error)"
            _ = ramRomAuthority.stopAfterFailure()
            writeRamRomFailure(error)
            return false
        }
    }

    private func makeSourceRamRomRequest() -> GoldenEyeRamRomLaunchRequest? {
        let catalog = GoldenEyeRamRomRouteCatalog.fromEnvironment()
        guard catalog.isComplete, !catalog.entries.isEmpty else { return nil }
        let seed: UInt64 = {
            guard let value = ProcessInfo.processInfo.environment["GOLDENEYE_TITLE_RANDOM_SEED"] else {
                return 1
            }
            let hex = value.hasPrefix("0x") || value.hasPrefix("0X")
            return UInt64(hex ? String(value.dropFirst(2)) : value, radix: hex ? 16 : 10) ?? 1
        }()
        var route = GoldenEyeAttractRoute(catalog: catalog, randomSeed: seed)
        _ = route.beginCast(.normalAttract)
        if let raw = ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_RAMROM_DEMO_INDEX"],
           let index = UInt8(raw), index < UInt8(catalog.entries.count) {
            _ = route.requestDemo(catalogIndex: index)
        } else {
            _ = route.requestDemo(catalogIndex: nil)
        }
        for _ in 0..<GoldenEyeRamRomRouteCatalog.sourceAssetNames.count + 34 {
            if case let .launchDemo(request) = route.advanceCast() {
                return request
            }
        }
        return nil
    }

    /// RAMROM is a native owner-side service.  The title value state only
    /// records the cast-to-demo handoff and the eventual fade/return; C owns
    /// packet/checksum/source-anchor semantics while the Swift service owns
    /// asset lifetime and restore routing.
    private func serviceRamRom(
        titleSnapshot: GoldenEyeTitleSnapshot,
        nativeTick: UInt64,
        mailboxInput: GoldenEyeInputSnapshot?,
        keyboardInput: GoldenEyeKeyboardSnapshot
    ) {
        guard diagnosticTitleFlowEnabled,
              let ramRomPlayback,
              let ramRomAuthority else { return }

        if titleSnapshot.screen == .ramrom,
           !ramRomPlayback.isActive,
           let request = diagnosticTitleFlow.takeRamRomLaunchRequest() {
            do {
                let sceneReady = prepareStageScene(stageID: request.stageID)
                let scene = stageScenePackets[request.stageID]
                let stageCoverage = scene.map { packet in
                    GoldenEyeRamRomStageCoverageV6.from(
                        packet: packet,
                        environmentPacket: stageEnvironmentPackets[packet.stageID],
                        materialPacket: stageMaterialPackets[packet.stageID],
                        stageTexturesReady: (renderer as? GoldenEyeStageSourceMaterialFrameRendererV6)?.stageTextureDependenciesReady ?? false
                    )
                }
                let environmentPacket = stageEnvironmentPackets[request.stageID]
                let coverageByStage = Dictionary(
                    uniqueKeysWithValues: stageScenePackets.map { stageID, packet in
                        (
                            stageID,
                            GoldenEyeRamRomStageCoverageV6.from(
                                packet: packet,
                                environmentPacket: stageEnvironmentPackets[stageID],
                                materialPacket: stageMaterialPackets[stageID],
                                stageTexturesReady: (renderer as? GoldenEyeStageSourceMaterialFrameRendererV6)?.stageTextureDependenciesReady ?? false
                            )
                        )
                    }
                )
                let routeCatalog = GoldenEyeRamRomRouteCatalog.fromEnvironment()
                let coverageManifest = GoldenEyeRamRomUnsupportedManifestV6.make(
                    routes: routeCatalog.entries,
                    coverageByStage: coverageByStage,
                    environmentByStage: stageEnvironmentPackets
                )
                try? "stage=\(request.stageID) sceneReady=\(sceneReady ? 1 : 0) demo=\(request.demoID) rooms=\(scene?.rooms.count ?? 0) setupObjects=\(scene?.setup.objects.count ?? 0) portals=\(scene?.setup.portals.count ?? 0) packetHash=\(scene?.packetHash ?? 0)\n".write(
                    toFile: "/tmp/goldeneye-stage-scene-owner.log",
                    atomically: false,
                    encoding: .utf8
                )
                try? "coverageManifestEntries=\(coverageManifest.entries.count) aggregateHash=\(coverageManifest.aggregateHash) complete=\(coverageManifest.isComplete ? 1 : 0)\n".write(
                    toFile: "/tmp/goldeneye-stage-scene-owner.log",
                    atomically: false,
                    encoding: .utf8
                )
                if let environmentPacket {
                    try submitStageEnvironment(
                        packet: environmentPacket,
                        nativeTick: nativeTick
                    )
                }
                let beginFrame = try ramRomAuthority.begin(
                    request: request,
                    atNativeTick: nativeTick,
                    stageCoverage: stageCoverage,
                    environmentPacket: environmentPacket
                )
                diagnosticTitleFlow.setRamRomPlaybackOwned(true)
                writeRamRomAuthorityFrame(beginFrame, prefix: "begin")
            } catch {
                diagnosticTitleFlow.setRamRomPlaybackOwned(false)
                _ = diagnosticTitleFlow.restoreAfterRamRom(.failed)
                writeRamRomFailure(error)
                return
            }
        }

        guard ramRomPlayback.isActive else { return }
        let titleInput = mailboxInput.map(titleInput(from:)) ?? titleInput(from: keyboardInput)
        do {
            guard let frame = try ramRomAuthority.step(
                nativeTick: nativeTick,
                input: GoldenEyeRamRomServiceInput(
                    pressedButtons: UInt32(titleInput.pressed),
                    heldButtons: UInt32(titleInput.held),
                    releasedButtons: UInt32(titleInput.released),
                    focused: titleInput.focused,
                    sourceMask: mailboxInput?.sourceFlags ?? 0
                )
            ) else { return }
            if frame.isFadeToTitle || frame.isReturnToTitle {
                writeRamRomAuthorityFrame(frame, prefix: "runtime")
            }
            guard frame.isReturnToTitle else { return }
            _ = ramRomPlayback.takeRestoreSnapshot()
            diagnosticTitleFlow.setRamRomPlaybackOwned(false)
            let reason: GoldenEyeRamRomExitReason = frame.isRealInputAbort
                ? .realInputAbort
                : .completed
            _ = diagnosticTitleFlow.restoreAfterRamRom(reason)
        } catch {
            diagnosticTitleFlow.setRamRomPlaybackOwned(false)
            _ = ramRomPlayback.stopAfterFailure()
            _ = diagnosticTitleFlow.restoreAfterRamRom(.failed)
            writeRamRomFailure(error)
        }
    }

    private func submitStageEnvironment(
        packet: GoldenEyeStageBackgroundDrawPacket,
        nativeTick: UInt64
    ) throws {
        if let materialPacket = stageMaterialPackets[packet.stageID],
           let materialReceiver = renderer as? GoldenEyeStageSourceMaterialFrameRendererV6 {
            try materialReceiver.submit(
                sourceEnvironmentPacket: packet,
                materialPacket: materialPacket,
                nativeTick: nativeTick
            )
            return
        }
        guard let receiver = renderer as? GoldenEyeStageSourceEnvironmentFrameRendererV6 else {
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                "Release renderer does not accept source stage environment packets"
            )
        }
        try receiver.submit(
            sourceEnvironmentPacket: packet,
            nativeTick: nativeTick
        )
    }

    private func submitGameplayCamera(
        frame: GoldenEyeRamRomGameplayFrameV6,
        nativeTick: UInt64,
        receiver: GoldenEyeStageGameplayCameraFrameRendererV7,
        windowIndex: UInt32
    ) throws -> Bool {
        gameplayCameraSubmissionStateLock.lock()
        guard !gameplayCameraSubmissionInFlight else {
            gameplayCameraSubmissionStateLock.unlock()
            return false
        }
        gameplayCameraSubmissionInFlight = true
        gameplayCameraSubmissionStateLock.unlock()
        var enqueued = false
        defer {
            if !enqueued {
                gameplayCameraSubmissionStateLock.lock()
                gameplayCameraSubmissionInFlight = false
                gameplayCameraSubmissionStateLock.unlock()
            }
        }
        let source = frame.playerCamera.sourceSnapshot
        guard UInt32(source.stage_id) == frame.stageID,
              source.current_room != UInt32.max,
              let scene = stageScenePackets[frame.stageID] else {
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                "V7 gameplay-camera source snapshot or prepared stage is invalid"
            )
        }
        let visiblePropModelIndices: Set<UInt32>
        if let cached = gameplayVisiblePropModelIndices[frame.stageID] {
            visiblePropModelIndices = cached
        } else {
            let environment = ProcessInfo.processInfo.environment
            guard let rawRoot = environment["GOLDENEYE_NATIVE_RAMROM_VISIBLE_ROOT"]
                    ?? environment["GOLDENEYE_NATIVE_VISIBLE_DEPENDENCY_ROOT"],
                  !rawRoot.isEmpty else {
                throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                    "V7 gameplay-camera visible dependency root is unavailable"
                )
            }
            let catalog = try GoldenEyeRamRomVisibleDependencyCatalogV6.load(
                rootURL: URL(fileURLWithPath: rawRoot, isDirectory: true)
            )
            let indices = Set(catalog.dependencies.compactMap { dependency -> UInt32? in
                guard dependency.category == "props",
                      dependency.stages.contains(scene.stageName) else { return nil }
                return dependency.modelIndex
            })
            guard !indices.isEmpty else {
                throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                    "V7 gameplay-camera visible prop dependency set is empty for stage \(scene.stageName)"
                )
            }
            gameplayVisiblePropModelIndices[frame.stageID] = indices
            visiblePropModelIndices = indices
        }

        func vector<T>(_ tuple: T) -> SIMD3<Int32> {
            let values = withUnsafeBytes(of: tuple) { Array($0.bindMemory(to: Int32.self)) }
            return SIMD3(values[0], values[1], values[2])
        }

        let cameraInput = GoldenEyeStagePlayerCameraSnapshotInputV6(
            stageID: frame.stageID,
            nativeTick: nativeTick,
            currentRoom: UInt32(source.current_room),
            cameraPositionQ16: vector(source.camera_position_q16),
            cameraForwardQ16: vector(source.camera_forward_q16),
            cameraUpQ16: vector(source.camera_up_q16),
            yawQ16: source.yaw_q16,
            pitchQ16: source.pitch_q16,
            coordinateDomain: .runtimeScaled
        )
        var dynamicDoorProps: [GoldenEyeStageGameplayCameraDynamicPropV7] = []
        dynamicDoorProps.reserveCapacity(frame.dynamicDoors.count)
        for door in frame.dynamicDoors {
            guard let object = scene.setup.objects.first(where: { $0.sourceRecordOffset == door.sourceRecordOffset }),
                  object.type == 1 else {
                throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                    "dynamic door source offset does not resolve to a type-1 setup object: \(door.sourceRecordOffset)"
                )
            }
            dynamicDoorProps.append(GoldenEyeStageGameplayCameraDynamicPropV7(
                objectIndex: object.index,
                transformQ16: door.transformQ16,
                sourceHash: door.sourceHash,
                openState: door.openState,
                portalNumber: door.portalNumber
            ))
        }
        let snapshot = GoldenEyeStageGameplayCameraSnapshotV7(
            demoID: UInt8(clamping: frame.demoID),
            stageID: frame.stageID,
            nativeTick: nativeTick,
            playerCamera: cameraInput,
            // The C player/camera owner publishes one authoritative room. The
            // V7 adapter validates that room against the source table and
            // lowerer; it never invents portal visibility from an identity
            // camera. Static prop indices come from the guarded setup rows.
            visibleRoomIndices:
                GoldenEyeStageEnvironmentCameraAdapterV6.sourceGameplayVisibleRoomIDs(
                    scene: scene,
                    currentRoom: UInt32(source.current_room)
                ),
            visibleStaticPropObjectIndices:
                GoldenEyeStageGameplayCameraPacketAdapterV7.staticPropObjectIndices(
                    in: scene, visiblePropModelIndices: visiblePropModelIndices
                ),
            dynamicPropTransforms: dynamicDoorProps
        )
        guard let productRenderer = receiver as? GoldenEyeSourceProductRendererV6 else {
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                "V7 gameplay-camera submission requires the source product renderer"
            )
        }
        let capturedRoom = source.current_room
        let capturedDynamicDoorCount = dynamicDoorProps.count
        let capturedWindowIndex = windowIndex
        gameplayCameraSubmissionQueue.async {
            defer {
                self.gameplayCameraSubmissionStateLock.lock()
                self.gameplayCameraSubmissionInFlight = false
                self.gameplayCameraSubmissionStateLock.unlock()
            }
            do {
                try productRenderer.submit(stageGameplayCameraSnapshot: snapshot)
                self.appendGameplayCameraOwnerEvidence(
                    "stageGameplayCameraOwner=1 windowIndex=\(capturedWindowIndex) demo=\(snapshot.demoID) stage=\(snapshot.stageID) nativeTick=\(snapshot.nativeTick) room=\(capturedRoom) props=\(snapshot.visibleStaticPropObjectIndices.count) dynamicDoors=\(capturedDynamicDoorCount)"
                )
            } catch {
                self.gameplayCameraSubmissionStateLock.lock()
                self.gameplayCameraSubmissionFailure = String(describing: error)
                self.gameplayCameraSubmissionStateLock.unlock()
                self.appendGameplayCameraOwnerEvidence(
                    "stageGameplayCameraOwner=0 error=\(error)"
                )
            }
        }
        enqueued = true
        return true
    }

    /// Loads one guarded stage scene packet at the RAMROM handoff. The packet
    /// contains copied background rooms and bounded decoded resource bytes;
    /// it deliberately does not start gameplay or claim a renderer path.
    private func prepareStageScene(stageID: UInt32) -> Bool {
        if stageScenePackets[stageID] != nil {
            do {
                _ = try activateStageLifecycle(stageID: stageID)
                return true
            } catch {
                try? "stageLifecycleError=\(error) stage=\(stageID)\n".write(
                    toFile: "/tmp/goldeneye-stage-scene-owner.log",
                    atomically: false,
                    encoding: .utf8
                )
                return false
            }
        }
        if !stageScenePreparationAttempted {
            stageScenePreparationAttempted = true
            do {
                try prepareStageSceneCatalog()
            } catch {
                stageScenePreparationAttempted = false
                try? "scenePreparationError=\(error)\n".write(
                    toFile: "/tmp/goldeneye-stage-scene-owner.log",
                    atomically: false,
                    encoding: .utf8
                )
            }
        }
        guard stageScenePackets[stageID] != nil else { return false }
        do {
            _ = try activateStageLifecycle(stageID: stageID)
            return true
        } catch {
            try? "stageLifecycleError=\(error) stage=\(stageID)\n".write(
                toFile: "/tmp/goldeneye-stage-scene-owner.log",
                atomically: false,
                encoding: .utf8
            )
            return false
        }
    }

    /// Prepare all seven immutable stage packets before the RAMROM handoff.
    /// Release invokes this during owner initialization when the V7 route is
    /// enabled, keeping the expensive catalog/transfer/material work outside
    /// the measured 120 Hz source timeline. The owner still activates only
    /// the requested stage at the handoff and retains all fail-closed guards.
    private func prepareStageSceneCatalog() throws {
        let catalog: GoldenEyeStageAssetCatalog
        if let root = ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_STAGE_ASSET_ROOT"],
           !root.isEmpty {
            catalog = try GoldenEyeStageAssetCatalog.load(
                stageAssetRoot: URL(fileURLWithPath: root, isDirectory: true)
            )
        } else {
            catalog = try GoldenEyeStageAssetCatalog.fromEnvironment().get()
        }
        stageLifecycle = try GoldenEyeStageLifecycleV6(catalog: catalog)
        var transferQueue = try GoldenEyeStageTransferQueueV6(
            catalog: catalog,
            maxPending: 8,
            maxChunkBytes: 64 * 1024
        )
        let packets = try GoldenEyeStageScenePacket.loadAll(
            catalog: catalog,
            transferQueue: &transferQueue
        )
        stageTransferQueue = transferQueue
        for packet in packets {
            stageScenePackets[packet.stageID] = packet
            guard let viewport = GoldenEyeProjectionV10.ViewportV10(
                drawableWidth: 440, drawableHeight: 330
            ), let projection = GoldenEyeProjectionV10.PacketV10(
                viewport: viewport,
                modelView: .identity,
                projection: .identity
            ) else {
                throw GoldenEyeStageSourceEnvironmentDrawPacketError.noPortalGeometry
            }
            let environmentPacket = try GoldenEyeStageSourceEnvironmentDrawPacketBuilderV6.make(
                scene: packet,
                viewport: viewport,
                projection: projection
            )
            stageEnvironmentPackets[packet.stageID] = environmentPacket
            stageMaterialPackets[packet.stageID] = try GoldenEyeStageSourceMaterialLowererV6.make(
                scene: packet
            )
        }
        let expectedStageIDs: Set<UInt32> = [9, 20, 25, 26, 33, 34, 35]
        guard Set(stageScenePackets.keys) == expectedStageIDs,
              Set(stageEnvironmentPackets.keys) == expectedStageIDs,
              Set(stageMaterialPackets.keys) == expectedStageIDs else {
            throw GoldenEyeSourceProductRendererV6Error.sourceBuild(
                "corrected stage catalog did not produce the complete seven-stage packet set"
            )
        }
        let environmentAggregate = expectedStageIDs.sorted().reduce(UInt64(14_695_981_039_346_656_037)) { hash, id in
            GoldenEyeCastSceneV6Hash.mix(
                GoldenEyeCastSceneV6Hash.mix(hash, UInt64(id)),
                stageEnvironmentPackets[id]?.packetHash ?? 0
            )
        }
        let materialAggregate = expectedStageIDs.sorted().reduce(UInt64(14_695_981_039_346_656_037)) { hash, id in
            GoldenEyeCastSceneV6Hash.mix(
                GoldenEyeCastSceneV6Hash.mix(hash, UInt64(id)),
                stageMaterialPackets[id]?.packetHash ?? 0
            )
        }
        appendOwnerEvidenceLine(
            "catalogHash=\(catalog.catalogHash) stages=\(stageScenePackets.count) allSeven=1 environmentAggregate=\(environmentAggregate) materialAggregate=\(materialAggregate)\n",
            path: "/tmp/goldeneye-stage-scene-owner.log"
        )
    }

    private func activateStageLifecycle(
        stageID: UInt32
    ) throws -> GoldenEyeStageLifecycleSnapshotV6 {
        guard var lifecycle = stageLifecycle else {
            throw GoldenEyeStageLifecycleErrorV6.unknownStage(stageID)
        }
        if let activeStageLifecycleID, activeStageLifecycleID != stageID {
            _ = try lifecycle.deactivate(stageID: activeStageLifecycleID)
            _ = try lifecycle.unload(stageID: activeStageLifecycleID)
            if var transferQueue = stageTransferQueue {
                _ = try transferQueue.deactivate(stageID: activeStageLifecycleID)
                _ = try transferQueue.unload(stageID: activeStageLifecycleID)
                stageTransferQueue = transferQueue
            }
        }
        let current = try lifecycle.snapshot(stageID: stageID)
        let snapshot: GoldenEyeStageLifecycleSnapshotV6
        switch current.phase {
        case .unloaded:
            _ = try lifecycle.load(stageID: stageID)
            snapshot = try lifecycle.activate(stageID: stageID)
        case .loaded:
            snapshot = try lifecycle.activate(stageID: stageID)
        case .active:
            snapshot = current
        }
        stageLifecycle = lifecycle
        if var transferQueue = stageTransferQueue {
            let payloadSnapshot = try transferQueue.activate(stageID: stageID)
            let transferSnapshot = transferQueue.snapshot
            stageTransferQueue = transferQueue
            let payloadLine = "stageTransferQueue=active stage=\(payloadSnapshot.stageID) "
                + "resources=\(payloadSnapshot.resourceCount) "
                + "decodedBytes=\(payloadSnapshot.decodedBytes) "
                + "decodedHash=\(payloadSnapshot.decodedHash) "
                + "loadCount=\(payloadSnapshot.loadCount) "
                + "completedRequests=\(transferSnapshot.completedCount) "
                + "transferHash=\(transferSnapshot.transferHash)\n"
            appendOwnerEvidenceLine(
                payloadLine,
                path: "/tmp/goldeneye-stage-scene-owner.log"
            )
        }
        activeStageLifecycleID = stageID
        appendOwnerEvidenceLine(
            "stageLifecycle=active stage=\(snapshot.stageID) phase=\(snapshot.phase.rawValue) loadCount=\(snapshot.loadCount) handles=\(snapshot.resourceHandles.count) stateHash=\(snapshot.stateHash)\n",
            path: "/tmp/goldeneye-stage-scene-owner.log"
        )
        return snapshot
    }

    private func writeRamRomEvent(
        _ event: GoldenEyeRamRomPlaybackEvent,
        prefix: String
    ) {
        let line = "prefix=\(prefix) kind=\(event.kind.rawValue) nativeTick=\(event.nativeTick) "
            + "referenceTick=\(event.referenceTick) pairPhase=\(event.pairPhase) "
            + "demo=\(event.demoID) stage=\(event.stageID) packet=\(event.packetIndex)/\(event.packetCount) "
            + "flags=\(event.flags) diagnostic=\(event.diagnosticCode) "
            + "recordingHash=\(event.recordingHash) rngHash=\(event.rngHash)\n"
        appendOwnerEvidenceLine(
            line,
            path: "/tmp/goldeneye-ramrom-playback-owner.log"
        )
    }

    private func writeRamRomAuthorityFrame(
        _ frame: GoldenEyeRamRomAuthorityFrameV6,
        prefix: String
    ) {
        let coverage = frame.stageCoverage
        let line = "prefix=\(prefix) kind=\(frame.eventKind.rawValue) nativeTick=\(frame.nativeTick) "
            + "referenceTick=\(frame.referenceTick) pairPhase=\(frame.pairPhase) "
            + "demo=\(frame.demoID) stage=\(frame.stageID) packet=\(frame.packetIndex)/\(frame.packetCount) "
            + "sourceFrame=\(frame.sourceFrame) speedframes=\(frame.speedframes) "
            + "recordingHash=\(frame.recordingHash) rngHash=\(frame.rngHash) "
            + "authorityStateHash=\(frame.authorityStateHash) sampleHash=\(frame.sampleHash) "
            + "sourceAnchor=\(frame.isSourceAnchor ? 1 : 0) renderable=\(frame.isRenderable ? 1 : 0) "
            + "environmentPacketHash=\(frame.environmentPacketHash) environmentCommands=\(frame.environmentCommandCount) "
            + "environmentVertices=\(frame.environmentVertexCount) environmentGeometry=\(frame.hasEnvironmentGeometry ? 1 : 0) "
            + "unsupportedVisibleMask=\(coverage?.unsupportedVisibleCommandMask ?? UInt32.max) "
            + "unsupportedVisibleCount=\(coverage?.unsupportedVisibleCommandCount ?? UInt32.max) "
            + "flags=\(frame.eventFlags) diagnostic=\(frame.diagnosticCode)\n"
        appendOwnerEvidenceLine(
            line,
            path: "/tmp/goldeneye-ramrom-playback-owner.log"
        )
    }

    private func writeRamRomGameplayFrame(
        _ frame: GoldenEyeRamRomGameplayFrameV6,
        prefix: String
    ) {
        let line = "prefix=\(prefix) nativeTick=\(frame.nativeTick) "
            + "referenceTick=\(frame.referenceTick) pairPhase=\(frame.pairPhase) "
            + "demo=\(frame.demoID) stage=\(frame.stageID) "
            + "gameplayStateHash=\(frame.gameplaySnapshot.state_hash) "
            + "gameplayEventHash=\(frame.gameplayEvent.event_hash) "
            + "playerHash=\(frame.playerCamera.playerHash) "
            + "cameraHash=\(frame.playerCamera.cameraHash) "
            + "roomHash=\(frame.playerCamera.roomHash) "
            + "ownerHash=\(frame.stateHash) "
            + "readiness=\(frame.readiness.isReady ? 1 : 0) "
            + "missing=\(frame.readiness.missingFields.joined(separator: ","))\n"
        appendOwnerEvidenceLine(
            line,
            path: "/tmp/goldeneye-ramrom-gameplay-owner.log"
        )
    }

    private func appendOwnerEvidenceLine(_ line: String, path: String) {
        let url = URL(fileURLWithPath: path)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            try? handle.write(contentsOf: Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url, options: .atomic)
        }
    }

    private func writeRamRomFailure(_ error: Error) {
        try? "error=\(error)\n".write(
            toFile: "/tmp/goldeneye-ramrom-playback-owner.log",
            atomically: true,
            encoding: .utf8
        )
    }

    private func titleInput(from keyboard: GoldenEyeKeyboardSnapshot) -> GoldenEyeTitleInput {
        var pressed: UInt16 = 0
        if keyboard.pressed & (1 << 4) != 0 { pressed |= 1 << 0 }
        if keyboard.pressed & (1 << 5) != 0 { pressed |= 1 << 1 }
        if keyboard.pressed & (1 << 15) != 0 { pressed |= 1 << 2 }
        if keyboard.pressed & (1 << 16) != 0 { pressed |= 1 << 3 }
        if keyboard.pressed & (1 << 17) != 0 { pressed |= 1 << 0 }
        var stickX: Int8 = 0
        var stickY: Int8 = 0
        if keyboard.held & (1 << 6) != 0 { stickX = -75 }
        if keyboard.held & (1 << 7) != 0 { stickX = 75 }
        if keyboard.held & (1 << 8) != 0 { stickY = -75 }
        if keyboard.held & (1 << 9) != 0 { stickY = 75 }
        return GoldenEyeTitleInput(
            held: 0,
            pressed: pressed,
            released: 0,
            stickX: stickX,
            stickY: stickY,
            focused: true
        )
    }

    private func titleInput(from snapshot: GoldenEyeInputSnapshot) -> GoldenEyeTitleInput {
        GoldenEyeTitleInput(
            held: UInt16(truncatingIfNeeded: snapshot.held),
            pressed: UInt16(truncatingIfNeeded: snapshot.pressed),
            released: UInt16(truncatingIfNeeded: snapshot.released),
            stickX: Int8(clamping: snapshot.stickX),
            stickY: Int8(clamping: snapshot.stickY),
            focused: (snapshot.sourceFlags & GoldenEyeInputSourceFlags.focused.rawValue) != 0
        )
    }
}
