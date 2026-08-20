import Foundation

#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

enum GoldenEyeRamRomPlaybackServiceError: Error, Sendable, Equatable, CustomStringConvertible {
    case missingAssetRoot
    case missingAsset(URL)
    case assetTooLarge(URL)
    case beginFailed(UInt32)
    case stepFailed(UInt64, UInt32)
    case restoreFailed(UInt32)

    var description: String {
        switch self {
        case .missingAssetRoot:
            return "RAMROM playback asset root is unavailable"
        case let .missingAsset(url):
            return "RAMROM playback asset is missing: \(url.path)"
        case let .assetTooLarge(url):
            return "RAMROM playback asset exceeds UInt32 byte-count contract: \(url.path)"
        case let .beginFailed(status):
            return "RAMROM playback begin failed with status \(status)"
        case let .stepFailed(tick, status):
            return "RAMROM playback step failed at native tick \(tick) with status \(status)"
        case let .restoreFailed(status):
            return "RAMROM playback restore snapshot failed with status \(status)"
        }
    }
}

enum GoldenEyeRamRomPlaybackEventKind: UInt32, Sendable, Equatable {
    case none = 0
    case installState = 1
    case sample = 2
    case packetAdvance = 3
    case fadeToTitle = 4
    case returnToTitle = 5
    case stageLoadUnsupported = 6
    case error = 7

    init(rawValue: UInt32) {
        switch rawValue {
        case Self.none.rawValue: self = .none
        case Self.installState.rawValue: self = .installState
        case Self.sample.rawValue: self = .sample
        case Self.packetAdvance.rawValue: self = .packetAdvance
        case Self.fadeToTitle.rawValue: self = .fadeToTitle
        case Self.returnToTitle.rawValue: self = .returnToTitle
        case Self.stageLoadUnsupported.rawValue: self = .stageLoadUnsupported
        default: self = .error
        }
    }
}

struct GoldenEyeRamRomPlaybackEvent: Sendable, Equatable {
    let kind: GoldenEyeRamRomPlaybackEventKind
    let flags: UInt32
    let diagnosticCode: UInt32
    let nativeTick: UInt64
    let referenceTick: UInt64
    let pairPhase: UInt32
    let demoID: UInt32
    let stageID: UInt32
    let packetIndex: UInt32
    let packetCount: UInt32
    let frameIndex: UInt32
    let recordCount: UInt32
    let controllerCount: UInt32
    let speedframes: UInt32
    let rngSeed: UInt32
    let sampleCount: UInt32
    let sourceAnchor: UInt32
    let sourceFrame: UInt32
    let abortButtons: UInt32
    let sampleHash: UInt64
    let stateHash: UInt64
    let recordingHash: UInt64
    let rngHash: UInt64

    var isFadeToTitle: Bool { kind == .fadeToTitle }
    var isReturnToTitle: Bool { kind == .returnToTitle }
    var isRealInputAbort: Bool {
        (flags & UInt32(GE_RAMROM_PLAYBACK_EVENT_FLAG_ABORTED_INPUT)) != 0
    }

    init(_ event: GERamRomPlaybackEventV5, absoluteNativeTick: UInt64? = nil) {
        kind = GoldenEyeRamRomPlaybackEventKind(rawValue: UInt32(event.event_type))
        flags = UInt32(event.flags)
        diagnosticCode = UInt32(event.diagnostic_code)
        nativeTick = absoluteNativeTick ?? UInt64(event.native_tick)
        referenceTick = UInt64(event.reference_tick)
        pairPhase = UInt32(event.pair_phase)
        demoID = UInt32(event.demo_id)
        stageID = UInt32(event.stage_id)
        packetIndex = UInt32(event.packet_index)
        packetCount = UInt32(event.packet_count)
        frameIndex = UInt32(event.frame_index)
        recordCount = UInt32(event.record_count)
        controllerCount = UInt32(event.controller_count)
        speedframes = UInt32(event.speedframes)
        rngSeed = UInt32(event.rng_seed)
        sampleCount = UInt32(event.sample_count)
        sourceAnchor = UInt32(event.source_anchor)
        sourceFrame = UInt32(event.source_frame)
        abortButtons = UInt32(event.abort_buttons)
        sampleHash = UInt64(event.sample_hash)
        stateHash = UInt64(event.state_hash)
        recordingHash = UInt64(event.recording_hash)
        rngHash = UInt64(event.rng_hash)
    }
}

struct GoldenEyeRamRomRestoreSnapshot: Sendable, Equatable {
    let demoID: UInt32
    let stageID: UInt32
    let registerHash: UInt64
    let saveHash: UInt64
    let saveData: Data
    let randomSeed: UInt64
    let randomizerSeed: UInt64
    let sourceHeaderHash: UInt64
}

struct GoldenEyeRamRomServiceInput: Sendable, Equatable {
    let pressedButtons: UInt32
    let heldButtons: UInt32
    let releasedButtons: UInt32
    let focused: Bool
    let sourceMask: UInt32

    init(
        pressedButtons: UInt32 = 0,
        heldButtons: UInt32 = 0,
        releasedButtons: UInt32 = 0,
        focused: Bool = true,
        sourceMask: UInt32 = 0
    ) {
        self.pressedButtons = pressedButtons
        self.heldButtons = heldButtons
        self.releasedButtons = releasedButtons
        self.focused = focused
        self.sourceMask = sourceMask
    }
}

/// Owner-thread adapter for the fixed-width native RAMROM controller.
///
/// `Data` is held only while a demo is active and is passed to C for the
/// duration of each begin/step call.  The C playback state retains no pointer
/// into this data.  The service is intentionally `@unchecked Sendable` for
/// the same reason as the native title owner: every mutating method is called
/// by the single engine-owner thread.
@available(macOS 27.0, *)
final class GoldenEyeRamRomPlaybackService: @unchecked Sendable {
    let assetRoot: URL

    private var activeData: Data?
    private var activeRequest: GoldenEyeRamRomLaunchRequest?
    private var state = GERamRomPlaybackStateV5()
    private var startNativeTick: UInt64 = 0
    private var hasStartedTick = false
    private var pendingRestore: GoldenEyeRamRomRestoreSnapshot?
    private(set) var lastEvent: GoldenEyeRamRomPlaybackEvent?
    private(set) var lastError: String?

    init(assetRoot: URL) {
        self.assetRoot = assetRoot.standardizedFileURL
    }

    static func fromEnvironment() -> Self? {
        guard let value = ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_ASSET_ROOT"],
              !value.isEmpty else {
            return nil
        }
        return Self(assetRoot: URL(fileURLWithPath: value, isDirectory: true))
    }

    var isActive: Bool { activeData != nil && activeRequest != nil }

    var currentRequest: GoldenEyeRamRomLaunchRequest? { activeRequest }

    /// Starts the selected source recording. The first playback tick is
    /// aligned to the next even owner tick, preserving the source-anchor
    /// contract if the title transition itself completed on an odd tick.
    func begin(
        request: GoldenEyeRamRomLaunchRequest,
        atNativeTick nativeTick: UInt64
    ) throws -> GoldenEyeRamRomPlaybackEvent {
        guard request.demoID > 0, request.demoID <= UInt8(GE_RAMROM_V5_DEMO_COUNT) else {
            throw GoldenEyeRamRomPlaybackServiceError.beginFailed(
                UInt32(GE_STATUS_INVALID_ARGUMENT)
            )
        }
        guard activeData == nil else {
            throw GoldenEyeRamRomPlaybackServiceError.beginFailed(
                UInt32(GE_STATUS_INVALID_STATE)
            )
        }

        let url = assetRoot
            .appendingPathComponent("ramrom", isDirectory: true)
            .appendingPathComponent(request.assetName, isDirectory: false)
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            throw GoldenEyeRamRomPlaybackServiceError.missingAsset(url)
        }
        guard data.count <= Int(UInt32.max) else {
            throw GoldenEyeRamRomPlaybackServiceError.assetTooLarge(url)
        }

        var nativeState = GERamRomPlaybackStateV5()
        var nativeEvent = GERamRomPlaybackEventV5()
        let status: UInt32 = data.withUnsafeBytes { rawBytes in
            guard let baseAddress = rawBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return UInt32(GE_STATUS_INVALID_ARGUMENT)
            }
            return UInt32(
                ge_ramrom_playback_v5_begin(
                    baseAddress,
                    UInt32(data.count),
                    UInt32(request.demoID),
                    &nativeState,
                    &nativeEvent
                )
            )
        }
        guard status == UInt32(GE_STATUS_OK) else {
            throw GoldenEyeRamRomPlaybackServiceError.beginFailed(status)
        }

        activeData = data
        activeRequest = request
        state = nativeState
        // Align the first source anchor. The C seam starts at relative tick 0.
        startNativeTick = (nativeTick | 1) &+ 1
        hasStartedTick = false
        pendingRestore = nil
        lastError = nil
        let event = GoldenEyeRamRomPlaybackEvent(
            nativeEvent,
            absoluteNativeTick: nativeTick
        )
        lastEvent = event
        return event
    }

    /// Advances one owner tick. Calls before the aligned first even tick emit
    /// no C step and return nil; this keeps the service's relative C tick at 0.
    func step(
        nativeTick: UInt64,
        input: GoldenEyeRamRomServiceInput
    ) throws -> GoldenEyeRamRomPlaybackEvent? {
        guard let data = activeData, activeRequest != nil else { return nil }
        guard nativeTick >= startNativeTick else { return nil }
        let relativeTick = nativeTick - startNativeTick
        if hasStartedTick, relativeTick == 0 {
            throw GoldenEyeRamRomPlaybackServiceError.stepFailed(
                nativeTick,
                UInt32(GE_STATUS_INVALID_ARGUMENT)
            )
        }

        let nativeInput = Self.makeNativeInput(input)
        var nativeEvent = GERamRomPlaybackEventV5()
        let status: UInt32 = data.withUnsafeBytes { rawBytes in
            guard let baseAddress = rawBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return UInt32(GE_STATUS_INVALID_ARGUMENT)
            }
            return UInt32(
                ge_ramrom_playback_v5_step(
                    baseAddress,
                    UInt32(data.count),
                    relativeTick,
                    nativeInput,
                    &state,
                    &nativeEvent
                )
            )
        }
        guard status == UInt32(GE_STATUS_OK) else {
            lastError = GoldenEyeRamRomPlaybackServiceError
                .stepFailed(nativeTick, status)
                .description
            throw GoldenEyeRamRomPlaybackServiceError.stepFailed(nativeTick, status)
        }
        hasStartedTick = true

        let event = GoldenEyeRamRomPlaybackEvent(
            nativeEvent,
            absoluteNativeTick: nativeTick
        )
        lastEvent = event
        if event.isReturnToTitle {
            try captureRestoreSnapshot()
            activeData = nil
            activeRequest = nil
        }
        return event
    }

    /// The renderer/title owner may call this to record the explicit stage
    /// boundary while the demo remains active. No pseudo-stage is substituted.
    func stageLoadDiagnostic() -> GoldenEyeRamRomPlaybackEvent? {
        guard isActive else { return nil }
        var event = GERamRomPlaybackEventV5()
        let status = ge_ramrom_playback_v5_load_stage(&state, &event)
        guard UInt32(status) == UInt32(GE_STATUS_UNSUPPORTED_COMMAND) else {
            return nil
        }
        let result = GoldenEyeRamRomPlaybackEvent(event)
        lastEvent = result
        return result
    }

    func takeRestoreSnapshot() -> GoldenEyeRamRomRestoreSnapshot? {
        defer { pendingRestore = nil }
        return pendingRestore
    }

    /// Used only when an owner-side error prevents the C seam from producing
    /// its normal return event. It leaves the source restore metadata intact.
    func stopAfterFailure() -> GoldenEyeRamRomRestoreSnapshot? {
        if pendingRestore == nil, isActive {
            try? captureRestoreSnapshot()
        }
        activeData = nil
        activeRequest = nil
        return takeRestoreSnapshot()
    }

    private func captureRestoreSnapshot() throws {
        var install = GERamRomPlaybackInstallV5()
        let status = ge_ramrom_playback_v5_copy_install(&state, &install, 1)
        guard UInt32(status) == UInt32(GE_STATUS_OK) else {
            throw GoldenEyeRamRomPlaybackServiceError.restoreFailed(UInt32(status))
        }

        let saveBytes: Data = withUnsafeBytes(of: install.save_data) { rawBytes in
            Data(rawBytes)
        }
        pendingRestore = GoldenEyeRamRomRestoreSnapshot(
            demoID: UInt32(activeRequest?.demoID ?? 0),
            stageID: UInt32(install.source_header.stage_id),
            registerHash: UInt64(install.register_hash),
            saveHash: UInt64(install.save_hash),
            saveData: saveBytes,
            randomSeed: UInt64(install.source_header.random_seed),
            randomizerSeed: UInt64(install.source_header.randomizer_seed),
            sourceHeaderHash: UInt64(install.source_header.header_hash)
        )
    }

    private static func makeNativeInput(_ input: GoldenEyeRamRomServiceInput) -> GERamRomPlaybackInputV5 {
        var value = GERamRomPlaybackInputV5()
        value.header.abi_version = UInt32(GE_NATIVE_ABI_VERSION)
        value.header.struct_size = UInt32(MemoryLayout<GERamRomPlaybackInputV5>.size)
        value.record_version = UInt32(GE_RAMROM_PLAYBACK_V5_RECORD_VERSION)
        value.flags = UInt32(GE_RAMROM_PLAYBACK_INPUT_REAL)
        if input.focused {
            value.flags |= UInt32(GE_RAMROM_PLAYBACK_INPUT_FOCUSED)
        }
        value.pressed_buttons = input.pressedButtons
        value.held_buttons = input.heldButtons
        value.released_buttons = input.releasedButtons
        value.source_mask = input.sourceMask
        value.controller_count = 1
        value.reserved0 = 0
        return value
    }
}
