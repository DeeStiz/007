import Foundation
import GoldenEyeNative
import GoldenEyeOriginalFrontend

/// A source-only projection shared by the independent original frontend and
/// the native V6 authority.  It intentionally contains no C record, pointer,
/// source address, model object, or scheduler state.
public struct GoldenEyeOriginalPairedProjectionV6: Sendable, Equatable {
    public let nativeTick: UInt64
    public let referenceTick: UInt64
    public let screen: UInt32
    public let pendingScreen: UInt32
    public let sourceTimer: UInt32
    public let transitionTimer: UInt32
    public let rarewareMode: UInt32
    public let rarewareCounter: UInt32
    public let gunbarrelMode: UInt32
    public let gunbarrelCounter: UInt32
    public let flags: UInt32
    public let stateHash: UInt64
    public let screenEventHash: UInt64
    public let audioEventHash: UInt64
    public let eventHash: UInt64

    fileprivate init(
        nativeTick: UInt64,
        referenceTick: UInt64,
        screen: UInt32,
        pendingScreen: UInt32,
        sourceTimer: UInt32,
        transitionTimer: UInt32,
        rarewareMode: UInt32,
        rarewareCounter: UInt32,
        gunbarrelMode: UInt32,
        gunbarrelCounter: UInt32,
        flags: UInt32,
        stateHash: UInt64,
        screenEventHash: UInt64,
        audioEventHash: UInt64,
        eventHash: UInt64
    ) {
        self.nativeTick = nativeTick
        self.referenceTick = referenceTick
        self.screen = screen
        self.pendingScreen = pendingScreen
        self.sourceTimer = sourceTimer
        self.transitionTimer = transitionTimer
        self.rarewareMode = rarewareMode
        self.rarewareCounter = rarewareCounter
        self.gunbarrelMode = gunbarrelMode
        self.gunbarrelCounter = gunbarrelCounter
        self.flags = flags
        self.stateHash = stateHash
        self.screenEventHash = screenEventHash
        self.audioEventHash = audioEventHash
        self.eventHash = eventHash
    }
}

public struct GoldenEyeOriginalPairedFrameV6: Sendable, Equatable {
    public let projection: GoldenEyeOriginalPairedProjectionV6
    public let nativeFrame: GoldenEyeSourceFrontendFrameV6
    /// The frame exposed to the product owner. Even anchors use original C
    /// scalar authority with native typed arrays retained as verified
    /// lowerings; odd ticks are explicit native 120 Hz extensions.
    public let authoritativeFrame: GoldenEyeSourceFrontendFrameV6
    public let originalEventCount: UInt32
    public let originalRenderEventCount: UInt32
    public let originalAudioEventCount: UInt32
    public let originalModelEventCount: UInt32
    public let originalSourceGap: Bool
    public let originalExecuted: Bool

    fileprivate init(
        projection: GoldenEyeOriginalPairedProjectionV6,
        nativeFrame: GoldenEyeSourceFrontendFrameV6,
        authoritativeFrame: GoldenEyeSourceFrontendFrameV6,
        originalEventCount: UInt32,
        originalRenderEventCount: UInt32,
        originalAudioEventCount: UInt32,
        originalModelEventCount: UInt32,
        originalSourceGap: Bool,
        originalExecuted: Bool
    ) {
        self.projection = projection
        self.nativeFrame = nativeFrame
        self.authoritativeFrame = authoritativeFrame
        self.originalEventCount = originalEventCount
        self.originalRenderEventCount = originalRenderEventCount
        self.originalAudioEventCount = originalAudioEventCount
        self.originalModelEventCount = originalModelEventCount
        self.originalSourceGap = originalSourceGap
        self.originalExecuted = originalExecuted
    }
}

public enum GoldenEyeOriginalPairedAuthorityV6Error: Error, Sendable, Equatable,
    CustomStringConvertible
{
    case invalidTick(expected: UInt64, actual: UInt64)
    case invalidInput(UInt32)
    case originalStatus(tick: UInt64, screen: UInt32, status: UInt32)
    case sourceGap(tick: UInt64, screen: UInt32, operation: UInt32, value0: UInt32)
    case originalUnsupported(tick: UInt64, screen: UInt32, count: UInt32)
    case nativeUnsupported(tick: UInt64, screen: UInt32, count: UInt32)
    case nativeFlags(tick: UInt64, screen: UInt32, flags: UInt32)
    case projectionMismatch(
        tick: UInt64,
        field: String,
        native: UInt64,
        original: UInt64
    )
    case eventHashMismatch(
        tick: UInt64,
        kind: String,
        native: UInt64,
        original: UInt64
    )
    case originalCanonicalFrameInvalid(tick: UInt64, screen: UInt32)

    public var description: String {
        switch self {
        case let .invalidTick(expected, actual):
            return "paired authority expected tick \(expected), got \(actual)"
        case let .invalidInput(buttons):
            return "paired authority received invalid source input bits 0x" +
                String(buttons, radix: 16)
        case let .originalStatus(tick, screen, status):
            return "original frontend status \(status) at tick \(tick), screen \(screen)"
        case let .sourceGap(tick, screen, operation, value0):
            return "original frontend SOURCE_GAP at tick \(tick), screen \(screen), " +
                "operation \(operation), value0 \(value0)"
        case let .originalUnsupported(tick, screen, count):
            return "original frontend unsupported_count \(count) at tick \(tick), screen \(screen)"
        case let .nativeUnsupported(tick, screen, count):
            return "native V6 unsupported_count \(count) at tick \(tick), screen \(screen)"
        case let .nativeFlags(tick, screen, flags):
            return "native V6 unsupported flags 0x" + String(flags, radix: 16) +
                " at tick \(tick), screen \(screen)"
        case let .projectionMismatch(tick, field, native, original):
            return "paired projection mismatch at tick \(tick) field \(field): " +
                "native \(native) original \(original)"
        case let .eventHashMismatch(tick, kind, native, original):
            return "paired event hash mismatch at tick \(tick) kind \(kind): " +
                "native \(native) original \(original)"
        case let .originalCanonicalFrameInvalid(tick, screen):
            return "original canonical frame cannot represent tick \(tick), screen \(screen)"
        }
    }
}

/// Runs the native V6 authority at 120 Hz while evaluating the linked
/// `GoldenEyeOriginalFrontend` target once per even native tick.  Odd ticks
/// are deliberately V6-only paired extensions; no claim is made that the
/// original source was executed on those ticks.
public struct GoldenEyeOriginalPairedAuthorityV6: @unchecked Sendable {
    public private(set) var nativeAuthority: GoldenEyeSourceFrontendAuthorityV6
    public private(set) var originalState: GEOriginalFrontendStateV6
    public private(set) var lastProjection: GoldenEyeOriginalPairedProjectionV6
    public private(set) var lastFrame: GoldenEyeOriginalPairedFrameV6
    /// The last directly compiled original C frame. It is exposed as a copied
    /// value so tests and diagnostics can compare the product authority fields
    /// without crossing a pointer or retaining C state.
    public private(set) var originalFrame: GEOriginalFrontendFrameV6

    private var originalEvents: [GEOriginalFrontendEventV6]

    public init() throws {
        let native = try GoldenEyeSourceFrontendAuthorityV6()
        var original = GEOriginalFrontendStateV6()
        let status = ge_original_frontend_v6_init(&original)
        guard status == UInt32(GE_ORIGINAL_STATUS_OK) else {
            throw GoldenEyeOriginalPairedAuthorityV6Error.originalStatus(
                tick: 0,
                screen: UInt32(GE_ORIGINAL_FRONTEND_V6_SCREEN_LEGAL),
                status: UInt32(status)
            )
        }

        let initialProjection = Self.projection(
            nativeAuthority: native,
            originalState: original,
            originalFrame: nil,
            nativeTick: 0,
            screenEventHash: Self.hashOffset,
            audioEventHash: Self.hashOffset
        )
        let emptyNativeFrame = native.lastFrame
        self.nativeAuthority = native
        self.originalState = original
        self.originalFrame = GEOriginalFrontendFrameV6()
        self.originalEvents = []
        self.lastProjection = initialProjection
        self.lastFrame = GoldenEyeOriginalPairedFrameV6(
            projection: initialProjection,
            nativeFrame: emptyNativeFrame,
            authoritativeFrame: emptyNativeFrame.withProvenance(.nativeBootstrap),
            originalEventCount: 0,
            originalRenderEventCount: 0,
            originalAudioEventCount: 0,
            originalModelEventCount: 0,
            originalSourceGap: false,
            originalExecuted: false
        )
    }

    /// Test-only mutation hook used to prove that the original projection
    /// comparison remains active. It changes only the copied native authority;
    /// the directly compiled original state is untouched.
    internal mutating func mutateNativeProjectionForTesting(sourceTimer: UInt32) {
        nativeAuthority.mutateProjectionForTesting(sourceTimer: sourceTimer)
    }

    /// Executes one native tick.  The complete product input/result mailbox is
    /// forwarded to the native V6 authority on every tick.  The linked
    /// original target receives only the fields represented by its frozen
    /// input ABI (buttons, controller count, clock timer, connection and
    /// synthetic flags) on an even source anchor.
    @discardableResult
    public mutating func step(
        nativeTick: UInt64,
        buttonsPressed: UInt32 = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_NONE),
        controllerCount: UInt32 = 1,
        fileModeControllerCount: UInt32? = nil,
        clockTimer: UInt32 = 1,
        focused: Bool = true,
        controllerConnected: Bool = true,
        synthetic: Bool = true,
        fileModeHeld: UInt32 = 0,
        fileModePressed: UInt32? = nil,
        fileModeReleased: UInt32 = 0,
        fileModeStickX: Int16 = 0,
        fileModeStickY: Int16 = 0,
        modelResultModel: UInt32 = 0,
        modelResultOperation: UInt32 = 0,
        modelResultFlags: UInt32 = 0,
        modelResultValue0: UInt32 = 0,
        modelResultValue1: UInt32 = 0
    ) throws -> GoldenEyeOriginalPairedFrameV6 {
        let expected = UInt64(nativeAuthority.state.native_tick) + 1
        guard nativeTick == expected else {
            throw GoldenEyeOriginalPairedAuthorityV6Error.invalidTick(
                expected: expected,
                actual: nativeTick
            )
        }
        guard buttonsPressed & ~UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_MASK) == 0 else {
            throw GoldenEyeOriginalPairedAuthorityV6Error.invalidInput(buttonsPressed)
        }

        let nativeFrame = try nativeAuthority.step(
            GoldenEyeSourceFrontendTimelineV6(nativeTick: nativeTick),
            buttonsPressed: buttonsPressed,
            controllerCount: controllerCount,
            fileModeControllerCount: fileModeControllerCount,
            clockTimer: clockTimer,
            focused: focused,
            controllerConnected: controllerConnected,
            synthetic: synthetic,
            fileModeHeld: fileModeHeld,
            fileModePressed: fileModePressed,
            fileModeReleased: fileModeReleased,
            fileModeStickX: fileModeStickX,
            fileModeStickY: fileModeStickY,
            modelResultModel: modelResultModel,
            modelResultOperation: modelResultOperation,
            modelResultFlags: modelResultFlags,
            modelResultValue0: modelResultValue0,
            modelResultValue1: modelResultValue1,
            pairedLifecycle: true
        )

        // Any native unsupported result is a hard failure even on an odd
        // extension.  This keeps the paired lane from turning a missing
        // producer/lowerer into an apparently valid frame.
        if nativeFrame.unsupportedCount != 0 {
            fputs(
                    "paired_native_gap=tick=\(nativeTick) screen=\(nativeFrame.screen) "
                        + "pending=\(nativeAuthority.state.pending_reload) flags=0x\(String(nativeFrame.flags, radix: 16)) "
                        + "model=\(modelResultModel) op=\(modelResultOperation)\n",
                stderr
            )
            throw GoldenEyeOriginalPairedAuthorityV6Error.nativeUnsupported(
                tick: nativeTick,
                screen: nativeFrame.screen,
                count: nativeFrame.unsupportedCount
            )
        }
        if (nativeFrame.flags & Self.nativeUnsupportedFlag) != 0 {
            let modelEvents = nativeFrame.modelEvents.map {
                "model=\($0.model),op=\($0.operation),result=\($0.resultFlags)"
            }.joined(separator: ";")
            fputs(
                    "paired_native_flags=tick=\(nativeTick) screen=\(nativeFrame.screen) "
                        + "pending=\(nativeAuthority.state.pending_reload) flags=0x\(String(nativeFrame.flags, radix: 16)) "
                        + "model=\(modelResultModel) op=\(modelResultOperation) events=[\(modelEvents)]\n",
                stderr
            )
            throw GoldenEyeOriginalPairedAuthorityV6Error.nativeFlags(
                tick: nativeTick,
                screen: nativeFrame.screen,
                flags: nativeFrame.flags
            )
        }

        if nativeTick & 1 == 1 {
            // No original call belongs here.  The odd frame is an explicit
            // paired extension of the native authority and remains marked as
            // such by `originalExecuted == false`.
            let projection = Self.projection(
                nativeAuthority: nativeAuthority,
                originalState: originalState,
                originalFrame: nil,
                nativeTick: nativeTick,
                screenEventHash: Self.hashOffset,
                audioEventHash: Self.hashOffset
            )
            let authoritativeFrame = nativeFrame.withProvenance(.native120Extension)
            let frame = GoldenEyeOriginalPairedFrameV6(
                projection: projection,
                nativeFrame: nativeFrame,
                authoritativeFrame: authoritativeFrame,
                originalEventCount: 0,
                originalRenderEventCount: 0,
                originalAudioEventCount: 0,
                originalModelEventCount: 0,
                originalSourceGap: false,
                originalExecuted: false
            )
            lastProjection = projection
            lastFrame = frame
            return frame
        }

        // The original target receives one and only one call here.  Its
        // frozen capture flag is the only render-side request mapped into the
        // original ABI; model/file-mode results remain native-side inputs.
        var input = GEOriginalFrontendInputV6()
        input.header.abi_version = UInt32(GE_NATIVE_ABI_VERSION)
        input.header.struct_size = UInt32(MemoryLayout<GEOriginalFrontendInputV6>.size)
        input.record_version = UInt32(GE_ORIGINAL_FRONTEND_V6_RECORD_VERSION)
        input.flags = UInt32(GE_ORIGINAL_FRONTEND_V6_INPUT_CAPTURE_RENDER)
        if controllerConnected {
            input.flags |= UInt32(GE_ORIGINAL_FRONTEND_V6_INPUT_CONNECTED)
        }
        if synthetic {
            input.flags |= UInt32(GE_ORIGINAL_FRONTEND_V6_INPUT_SYNTHETIC)
        }
        input.buttons_pressed = buttonsPressed == 0 ?
            UInt32(GE_ORIGINAL_FRONTEND_V6_BUTTON_NONE) :
            UInt32(GE_ORIGINAL_FRONTEND_V6_BUTTON_ANY)
        input.controller_count = controllerCount
        input.clock_timer = clockTimer
        input.native_tick = nativeTick
        input.sequence = nativeTick

        originalEvents = Array(
            repeating: GEOriginalFrontendEventV6(),
            // The linked source target may report model/audio sink events
            // from a single source anchor.  Keep this bounded but well above
            // the native common-event projection so an event-buffer overflow
            // cannot masquerade as a source-fidelity gap.
            count: 512
        )
        var eventCount: UInt32 = 0
        var frame = GEOriginalFrontendFrameV6()
        let status = originalEvents.withUnsafeMutableBufferPointer { buffer in
            ge_original_frontend_v6_step(
                &originalState,
                &input,
                buffer.baseAddress,
                UInt32(buffer.count),
                &eventCount,
                &frame
            )
        }
        guard status == UInt32(GE_ORIGINAL_STATUS_OK) else {
            throw GoldenEyeOriginalPairedAuthorityV6Error.originalStatus(
                tick: nativeTick,
                screen: UInt32(originalState.screen),
                status: UInt32(status)
            )
        }
        originalFrame = frame
        originalEvents.removeSubrange(Int(eventCount)..<originalEvents.count)

        if let gap = originalEvents.first(where: {
            $0.kind == UInt32(GE_ORIGINAL_FRONTEND_V6_EVENT_SOURCE_GAP)
        }) {
            throw GoldenEyeOriginalPairedAuthorityV6Error.sourceGap(
                tick: nativeTick,
                screen: UInt32(gap.screen),
                operation: UInt32(gap.operation),
                value0: UInt32(gap.value0)
            )
        }
        if originalState.unsupported_count != 0 {
            throw GoldenEyeOriginalPairedAuthorityV6Error.originalUnsupported(
                tick: nativeTick,
                screen: UInt32(originalState.screen),
                count: UInt32(originalState.unsupported_count)
            )
        }

        let nativeScreenHash = Self.screenEventHash(nativeFrame.screenEvents)
        let nativeAudioHash = Self.audioEventHash(nativeFrame.audioEvents)
        let originalScreenHash = Self.screenEventHash(originalEvents)
        let originalAudioHash = Self.audioEventHash(originalEvents)
        guard nativeScreenHash == originalScreenHash else {
            throw GoldenEyeOriginalPairedAuthorityV6Error.eventHashMismatch(
                tick: nativeTick,
                kind: "screen",
                native: nativeScreenHash,
                original: originalScreenHash
            )
        }
        guard nativeAudioHash == originalAudioHash else {
            let nativeEvents = nativeFrame.audioEvents.map {
                "op=\($0.operation),asset=\($0.assetID),seq=\($0.sequence)"
            }.joined(separator: ";")
            let originalAudioEvents = originalEvents.filter {
                $0.kind == UInt32(GE_ORIGINAL_FRONTEND_V6_EVENT_AUDIO)
            }.map {
                "op=\($0.operation),value0=\($0.value0),seq=\($0.native_tick)"
            }.joined(separator: ";")
            fputs(
                "paired_audio_divergence=tick=\(nativeTick) native=[\(nativeEvents)] original=[\(originalAudioEvents)] "
                    + "nativeGunMode=\(nativeAuthority.state.gunbarrel_mode) nativeGunCounter=\(nativeAuthority.state.gunbarrel_counter)\n",
                stderr
            )
            throw GoldenEyeOriginalPairedAuthorityV6Error.eventHashMismatch(
                tick: nativeTick,
                kind: "audio",
                native: nativeAudioHash,
                original: originalAudioHash
            )
        }

        try Self.compareProjection(
            nativeAuthority: nativeAuthority,
            nativeFrame: nativeFrame,
            originalState: originalState,
            originalFrame: frame,
            nativeTick: nativeTick,
            screenEventHash: nativeScreenHash,
            audioEventHash: nativeAudioHash
        )

        guard let originalCanonical = GoldenEyeSourceFrontendOriginalCanonicalV6(
            flags: UInt32(frame.flags),
            screen: UInt32(frame.screen),
            pendingScreen: UInt32(frame.pending_screen),
            rarewareMode: UInt32(frame.rareware_mode),
            rarewareCounter: UInt32(frame.rareware_counter),
            gunbarrelMode: UInt32(frame.gunbarrel_mode),
            gunbarrelCounter: UInt32(frame.gunbarrel_counter),
            nativeTick: UInt64(frame.native_tick),
            sourceFrame: UInt64(frame.source_frame),
            sourceTimer: UInt32(frame.source_timer),
            transitionTimer: UInt32(frame.transition_timer),
            unsupportedCount: UInt32(originalState.unsupported_count),
            stateHash: UInt64(frame.state_hash),
            renderHash: UInt64(frame.render_hash),
            audioHash: UInt64(frame.audio_hash)
        ) else {
            throw GoldenEyeOriginalPairedAuthorityV6Error.originalCanonicalFrameInvalid(
                tick: nativeTick,
                screen: UInt32(frame.screen)
            )
        }
        let authoritativeFrame = GoldenEyeSourceFrontendFrameV6(
            authoritative: originalCanonical,
            sidecar: nativeFrame
        )

        let projection = Self.projection(
            nativeAuthority: nativeAuthority,
            originalState: originalState,
            originalFrame: frame,
            nativeTick: nativeTick,
            screenEventHash: nativeScreenHash,
            audioEventHash: nativeAudioHash
        )
        let result = GoldenEyeOriginalPairedFrameV6(
            projection: projection,
            nativeFrame: nativeFrame,
            authoritativeFrame: authoritativeFrame,
            originalEventCount: eventCount,
            originalRenderEventCount: UInt32(originalEvents.filter {
                $0.kind == UInt32(GE_ORIGINAL_FRONTEND_V6_EVENT_RENDER)
            }.count),
            originalAudioEventCount: UInt32(originalEvents.filter {
                $0.kind == UInt32(GE_ORIGINAL_FRONTEND_V6_EVENT_AUDIO)
            }.count),
            originalModelEventCount: UInt32(originalEvents.filter {
                $0.kind == UInt32(GE_ORIGINAL_FRONTEND_V6_EVENT_MODEL)
            }.count),
            originalSourceGap: false,
            originalExecuted: true
        )
        lastProjection = projection
        lastFrame = result
        return result
    }

    private static let hashOffset: UInt64 = 1_469_598_103_934_665_603
    private static let hashPrime: UInt64 = 1_099_511_628_211
    // These values are duplicated here because the standalone original
    // module deliberately exposes only its value records, not the private C
    // enum names from the source-port implementation.
    private static let nativeUnsupportedFlag: UInt32 = 1 << 5
    private static let originalScreenEnter: UInt32 = 1
    private static let originalScreenExit: UInt32 = 2
    private static let originalScreenTransition: UInt32 = 3
    private static let originalAudioStop: UInt32 = 6
    private static let originalAudioMusic: UInt32 = 7
    private static let originalAudioSFX: UInt32 = 8
    private static let nativeScreenEnter: UInt32 = 1
    private static let nativeScreenExit: UInt32 = 2
    private static let nativeScreenTransition: UInt32 = 3
    private static let nativeAudioStop: UInt32 = 1
    private static let nativeAudioMusic: UInt32 = 2
    private static let nativeAudioSFX: UInt32 = 3

    private static func hash(_ values: [UInt64]) -> UInt64 {
        var result = hashOffset
        for value in values {
            var remaining = value
            for _ in 0..<8 {
                result ^= remaining & 0xff
                result &*= hashPrime
                remaining >>= 8
            }
        }
        return result
    }

    private static func screenEventHash(
        _ events: [GoldenEyeSourceFrontendScreenEventV6]
    ) -> UInt64 {
        var values: [UInt64] = []
        values.reserveCapacity(events.count * 4)
        for event in events where event.event != Self.nativeScreenExit {
            values.append(UInt64(event.event))
            values.append(UInt64(event.screen))
            // A source enter event is emitted before/after target init on the
            // two adapters, so its timer is not a shared semantic.  The
            // transition request remains exact and carries target/timer.
            if event.event == Self.nativeScreenTransition {
                values.append(UInt64(event.targetScreen))
                values.append(UInt64(event.sourceTimer))
            }
        }
        return hash(values)
    }

    private static func screenEventHash(
        _ events: [GEOriginalFrontendEventV6]
    ) -> UInt64 {
        var values: [UInt64] = []
        values.reserveCapacity(events.count * 4)
        for event in events where event.kind == UInt32(GE_ORIGINAL_FRONTEND_V6_EVENT_SCREEN) {
            let operation = UInt32(event.operation)
            let eventCode: UInt32
            switch operation {
            case Self.originalScreenEnter:
                eventCode = Self.nativeScreenEnter
            case Self.originalScreenExit:
                eventCode = Self.nativeScreenExit
            case Self.originalScreenTransition:
                eventCode = Self.nativeScreenTransition
            default:
                eventCode = operation
            }
            // The two source projections intentionally report different
            // internal switch-exit targets (native target vs MENU_SWITCH).
            // Enter and transition requests are the shared source semantics;
            // exit markers are omitted from this normalized event hash.
            if eventCode == Self.nativeScreenExit {
                continue
            }
            values.append(UInt64(eventCode))
            values.append(UInt64(event.screen))
            if eventCode == Self.nativeScreenTransition {
                values.append(UInt64(event.target_screen))
                values.append(UInt64(event.source_timer))
            }
        }
        return hash(values)
    }

    private static func audioEventHash(
        _ events: [GoldenEyeSourceFrontendAudioEventV6]
    ) -> UInt64 {
        var values: [UInt64] = []
        values.reserveCapacity(events.count * 2)
        for event in events {
            values.append(UInt64(event.operation))
            values.append(UInt64(event.assetID))
        }
        return hash(values)
    }

    private static func audioEventHash(
        _ events: [GEOriginalFrontendEventV6]
    ) -> UInt64 {
        var values: [UInt64] = []
        values.reserveCapacity(events.count * 2)
        for event in events where event.kind == UInt32(GE_ORIGINAL_FRONTEND_V6_EVENT_AUDIO) {
            let originalOperation = UInt32(event.operation)
            let operation: UInt32
            switch originalOperation {
            case Self.originalAudioStop:
                operation = Self.nativeAudioStop
            case Self.originalAudioMusic:
                operation = Self.nativeAudioMusic
            case Self.originalAudioSFX:
                operation = Self.nativeAudioSFX
            default:
                operation = originalOperation
            }
            values.append(UInt64(operation))
            values.append(UInt64(event.value0))
        }
        return hash(values)
    }

    private static func pendingScreen(
        _ state: GEFrontendRuntimeV6State
    ) -> UInt32 {
        let invalid = UInt32.max
        if UInt32(state.pending_reload) != invalid {
            return UInt32(state.pending_reload)
        }
        if UInt32(state.pending_direct) != invalid {
            return UInt32(state.pending_direct)
        }
        return invalid
    }

    private static func projection(
        nativeAuthority: GoldenEyeSourceFrontendAuthorityV6,
        originalState: GEOriginalFrontendStateV6,
        originalFrame: GEOriginalFrontendFrameV6?,
        nativeTick: UInt64,
        screenEventHash: UInt64,
        audioEventHash: UInt64
    ) -> GoldenEyeOriginalPairedProjectionV6 {
        let runtime = nativeAuthority.state
        let frame = originalFrame
        let screen = frame.map { UInt32($0.screen) } ?? UInt32(runtime.screen)
        let pending = frame.map { UInt32($0.pending_screen) } ?? pendingScreen(runtime)
        let timer = frame.map { UInt32($0.source_timer) } ?? UInt32(runtime.source_timer)
        let transition = frame.map { UInt32($0.transition_timer) } ??
            UInt32(runtime.transition_timer)
        let rarewareMode = frame.map { UInt32($0.rareware_mode) } ?? UInt32(runtime.rareware_mode)
        let rarewareCounter = frame.map { UInt32($0.rareware_counter) } ??
            UInt32(runtime.rareware_counter)
        let gunbarrelMode = frame.map { UInt32($0.gunbarrel_mode) } ??
            UInt32(runtime.gunbarrel_mode)
        let gunbarrelCounter = frame.map { UInt32($0.gunbarrel_counter) } ??
            UInt32(runtime.gunbarrel_counter)
        let flags = frame.map { UInt32($0.flags) } ?? (UInt32(runtime.flags) & 0x3f)
        let stateHash = hash([
            UInt64(screen), UInt64(pending), UInt64(timer), UInt64(transition),
            UInt64(rarewareMode), UInt64(rarewareCounter), UInt64(gunbarrelMode),
            UInt64(gunbarrelCounter), UInt64(flags), nativeTick
        ])
        return GoldenEyeOriginalPairedProjectionV6(
            nativeTick: nativeTick,
            referenceTick: nativeTick / 2,
            screen: screen,
            pendingScreen: pending,
            sourceTimer: timer,
            transitionTimer: transition,
            rarewareMode: rarewareMode,
            rarewareCounter: rarewareCounter,
            gunbarrelMode: gunbarrelMode,
            gunbarrelCounter: gunbarrelCounter,
            flags: flags,
            stateHash: stateHash,
            screenEventHash: screenEventHash,
            audioEventHash: audioEventHash,
            eventHash: hash([screenEventHash, audioEventHash])
        )
    }

    private static func compareProjection(
        nativeAuthority: GoldenEyeSourceFrontendAuthorityV6,
        nativeFrame: GoldenEyeSourceFrontendFrameV6,
        originalState: GEOriginalFrontendStateV6,
        originalFrame: GEOriginalFrontendFrameV6,
        nativeTick: UInt64,
        screenEventHash: UInt64,
        audioEventHash: UInt64
    ) throws {
        let runtime = nativeAuthority.state
        let originalStateFields: [(String, UInt64, UInt64)] = [
            ("original.screen", UInt64(originalState.screen), UInt64(originalFrame.screen)),
            ("original.pendingScreen", UInt64(originalState.pending_screen), UInt64(originalFrame.pending_screen)),
            ("original.sourceTimer", UInt64(originalState.source_timer), UInt64(originalFrame.source_timer)),
            ("original.transitionTimer", UInt64(originalState.transition_timer), UInt64(originalFrame.transition_timer)),
            ("original.rarewareMode", UInt64(originalState.rareware_mode), UInt64(originalFrame.rareware_mode)),
            ("original.rarewareCounter", UInt64(originalState.rareware_counter), UInt64(originalFrame.rareware_counter)),
            ("original.gunbarrelMode", UInt64(originalState.gunbarrel_mode), UInt64(originalFrame.gunbarrel_mode)),
            ("original.gunbarrelCounter", UInt64(originalState.gunbarrel_counter), UInt64(originalFrame.gunbarrel_counter)),
            ("original.flags", UInt64(originalState.flags), UInt64(originalFrame.flags)),
            ("original.nativeTick", UInt64(originalState.native_tick), UInt64(originalFrame.native_tick)),
            ("original.sourceFrame", UInt64(originalState.source_frame), UInt64(originalFrame.source_frame)),
            ("original.renderHash", UInt64(originalState.render_hash), UInt64(originalFrame.render_hash)),
            ("original.audioHash", UInt64(originalState.audio_hash), UInt64(originalFrame.audio_hash)),
        ]
        for (field, stateValue, frameValue) in originalStateFields where stateValue != frameValue {
            throw GoldenEyeOriginalPairedAuthorityV6Error.projectionMismatch(
                tick: nativeTick,
                field: field,
                native: stateValue,
                original: frameValue
            )
        }
        let originalScreen = UInt32(originalFrame.screen)
        let originalPending = UInt32(originalFrame.pending_screen)
        let runtimePending = pendingScreen(runtime)
        let fields: [(String, UInt64, UInt64)] = [
            ("screen", UInt64(nativeFrame.screen), UInt64(originalScreen)),
            ("pendingScreen", UInt64(runtimePending), UInt64(originalPending)),
            ("sourceTimer", UInt64(runtime.source_timer), UInt64(originalFrame.source_timer)),
            ("transitionTimer", UInt64(runtime.transition_timer), UInt64(originalFrame.transition_timer)),
            ("flags", UInt64(runtime.flags & 0x3f), UInt64(originalFrame.flags)),
            ("sourceFrame", UInt64(nativeFrame.sourceFrame), UInt64(originalFrame.source_frame))
        ]
        for (field, native, original) in fields where native != original {
            throw GoldenEyeOriginalPairedAuthorityV6Error.projectionMismatch(
                tick: nativeTick,
                field: field,
                native: native,
                original: original
            )
        }

        if nativeFrame.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_RAREWARE) {
            let fields: [(String, UInt64, UInt64)] = [
                ("rarewareMode", UInt64(runtime.rareware_mode), UInt64(originalFrame.rareware_mode)),
                ("rarewareCounter", UInt64(runtime.rareware_counter), UInt64(originalFrame.rareware_counter))
            ]
            for (field, native, original) in fields where native != original {
                throw GoldenEyeOriginalPairedAuthorityV6Error.projectionMismatch(
                    tick: nativeTick,
                    field: field,
                    native: native,
                    original: original
                )
            }
        }
        if nativeFrame.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL) {
            let fields: [(String, UInt64, UInt64)] = [
                ("gunbarrelMode", UInt64(runtime.gunbarrel_mode), UInt64(originalFrame.gunbarrel_mode)),
                ("gunbarrelCounter", UInt64(runtime.gunbarrel_counter), UInt64(originalFrame.gunbarrel_counter))
            ]
            for (field, native, original) in fields where native != original {
                throw GoldenEyeOriginalPairedAuthorityV6Error.projectionMismatch(
                    tick: nativeTick,
                    field: field,
                    native: native,
                    original: original
                )
            }
        }
        _ = originalState
        _ = screenEventHash
        _ = audioEventHash
    }
}
