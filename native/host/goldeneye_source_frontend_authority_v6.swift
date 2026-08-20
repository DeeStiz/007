import Foundation
#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

/// A caller-owned timeline coordinate.  The authority never manufactures a
/// tick internally; every step must identify the native 120 Hz tick being
/// executed, which keeps scheduler ownership outside this value type.
public struct GoldenEyeSourceFrontendTimelineV6: Sendable, Equatable {
    public let nativeTick: UInt64

    public init(nativeTick: UInt64) throws {
        guard nativeTick > 0 else {
            throw GoldenEyeSourceFrontendAuthorityV6Error.invalidTimeline
        }
        self.nativeTick = nativeTick
    }

    public var isSourceAnchor: Bool {
        nativeTick & 1 == 0
    }
}

/// Identifies which authority supplied the scalar fields of a copied source
/// frame.  The original C frontend ABI does not carry the typed model/text/
/// save/render arrays used by the existing renderer, so those arrays remain a
/// verified native sidecar on original-canonical frames.
public enum GoldenEyeSourceFrontendFrameProvenanceV6: String, Sendable, Equatable {
    /// Tick-zero bootstrap before the original source has executed a step.
    case nativeBootstrap
    /// Even native tick whose scalar projection and hashes came from the
    /// directly compiled original C frontend after paired comparison.
    case originalCanonical
    /// Odd native tick: a continuous 120 Hz extension of the preceding
    /// original anchor. The original C frontend is not called on this tick.
    case native120Extension
}

/// Scalar values copied from the directly compiled original frontend.  This
/// record intentionally contains no C record or pointer; the paired authority
/// performs the C-to-value copy before constructing it.
public struct GoldenEyeSourceFrontendOriginalCanonicalV6: Sendable, Equatable {
    public let flags: UInt32
    public let screen: UInt32
    public let pendingScreen: UInt32
    public let subphase: UInt32
    public let nativeTick: UInt64
    public let referenceTick: UInt64
    public let sourceFrame: UInt32
    public let sourceTimer: UInt32
    public let sourceThreshold: UInt32
    public let transitionTimer: UInt32
    public let unsupportedCount: UInt32
    public let stateHash: UInt64
    public let renderHash: UInt64
    public let audioHash: UInt64
    public let rarewareMode: UInt32
    public let rarewareCounter: UInt32
    public let gunbarrelMode: UInt32
    public let gunbarrelCounter: UInt32

    /// Returns nil if the source frame cannot be represented by the existing
    /// fixed-width Swift summary without truncating its source-frame counter.
    public init?(
        flags: UInt32,
        screen: UInt32,
        pendingScreen: UInt32,
        rarewareMode: UInt32,
        rarewareCounter: UInt32,
        gunbarrelMode: UInt32,
        gunbarrelCounter: UInt32,
        nativeTick: UInt64,
        sourceFrame: UInt64,
        sourceTimer: UInt32,
        transitionTimer: UInt32,
        unsupportedCount: UInt32,
        stateHash: UInt64,
        renderHash: UInt64,
        audioHash: UInt64
    ) {
        guard nativeTick > 0, sourceFrame <= UInt64(UInt32.max) else {
            return nil
        }
        self.flags = flags
        self.screen = screen
        self.pendingScreen = pendingScreen
        self.subphase = Self.subphase(
            screen: screen,
            pendingScreen: pendingScreen,
            rarewareMode: rarewareMode,
            gunbarrelMode: gunbarrelMode
        )
        self.nativeTick = nativeTick
        self.referenceTick = nativeTick >> 1
        self.sourceFrame = UInt32(sourceFrame)
        self.sourceTimer = sourceTimer
        self.sourceThreshold = Self.sourceThreshold(screen: screen, subphase: self.subphase)
        self.transitionTimer = transitionTimer
        self.unsupportedCount = unsupportedCount
        self.stateHash = stateHash
        self.renderHash = renderHash
        self.audioHash = audioHash
        self.rarewareMode = rarewareMode
        self.rarewareCounter = rarewareCounter
        self.gunbarrelMode = gunbarrelMode
        self.gunbarrelCounter = gunbarrelCounter
    }

    private static func subphase(
        screen: UInt32,
        pendingScreen: UInt32,
        rarewareMode: UInt32,
        gunbarrelMode: UInt32
    ) -> UInt32 {
        switch screen {
        case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_RAREWARE):
            return rarewareMode
        case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL):
            return gunbarrelMode
        case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_SWITCH):
            return pendingScreen == UInt32.max ? 0 : pendingScreen
        default:
            return 0
        }
    }

    private static func sourceThreshold(screen: UInt32, subphase: UInt32) -> UInt32 {
        switch screen {
        case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_LEGAL):
            return 241
        case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_NINTENDO):
            return 501
        case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_RAREWARE):
            return subphase == 2 ? 0 : 290
        case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GOLDENEYE):
            return 180
        case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_FILE_SELECT):
            return 1_801
        case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_SWITCH):
            return 4
        case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_CAST):
            return 181
        default:
            return 0
        }
    }
}

public struct GoldenEyeSourceFrontendFrameSummaryV6: Sendable, Equatable {
    public let provenance: GoldenEyeSourceFrontendFrameProvenanceV6
    public let flags: UInt32
    public let screen: UInt32
    public let subphase: UInt32
    public let nativeTick: UInt64
    public let referenceTick: UInt64
    public let sourceFrame: UInt32
    public let sourceTimer: UInt32
    public let sourceThreshold: UInt32
    public let transitionTimer: UInt32
    public let selection: UInt32
    public let unsupportedCount: UInt32
    public let stateHash: UInt64
    public let renderHash: UInt64
    public let audioHash: UInt64
    public let screenHash: UInt64
    public let modelHash: UInt64
    public let textHash: UInt64
    public let audioEventHash: UInt64
    public let saveHash: UInt64
    public let renderEventHash: UInt64
    public let diagnosticHash: UInt64
    public let screenEvents: UInt32
    public let modelEvents: UInt32
    public let textEvents: UInt32
    public let audioEvents: UInt32
    public let saveEvents: UInt32
    public let renderEvents: UInt32
    public let diagnosticEvents: UInt32
    /// The source keeps the Rareware animation counter separate from the
    /// inherited menu timer.  It is carried only by the authoritative paired
    /// value frame; the copied runtime snapshot does not expose it directly,
    /// so the Swift authority attaches it from its fixed-width state record.
    public let rarewareCounter: UInt32

    init(
        _ snapshot: GEFrontendRuntimeV6Snapshot,
        provenance: GoldenEyeSourceFrontendFrameProvenanceV6 = .nativeBootstrap
    ) {
        self.provenance = provenance
        flags = UInt32(snapshot.flags)
        screen = UInt32(snapshot.screen)
        subphase = UInt32(snapshot.subphase)
        nativeTick = UInt64(snapshot.native_tick)
        referenceTick = UInt64(snapshot.reference_tick)
        sourceFrame = UInt32(snapshot.source_frame)
        sourceTimer = UInt32(snapshot.source_timer)
        sourceThreshold = UInt32(snapshot.source_threshold)
        transitionTimer = UInt32(snapshot.transition_timer)
        selection = UInt32(snapshot.selection)
        unsupportedCount = UInt32(snapshot.unsupported_count)
        stateHash = UInt64(snapshot.state_hash)
        renderHash = UInt64(snapshot.render_hash)
        audioHash = UInt64(snapshot.audio_hash)
        screenHash = UInt64(snapshot.screen_hash)
        modelHash = UInt64(snapshot.model_hash)
        textHash = UInt64(snapshot.text_hash)
        audioEventHash = UInt64(snapshot.audio_event_hash)
        saveHash = UInt64(snapshot.save_hash)
        renderEventHash = UInt64(snapshot.render_event_hash)
        diagnosticHash = UInt64(snapshot.diagnostic_hash)
        screenEvents = UInt32(snapshot.screen_count)
        modelEvents = UInt32(snapshot.model_count)
        textEvents = UInt32(snapshot.text_count)
        audioEvents = UInt32(snapshot.audio_count)
        saveEvents = UInt32(snapshot.save_count)
        renderEvents = UInt32(snapshot.render_count)
        diagnosticEvents = UInt32(snapshot.diagnostic_count)
        rarewareCounter = 0
    }

    /// Builds a summary whose source projection and scalar hashes are
    /// authoritative from the directly compiled original frontend. Fields
    /// absent from that ABI (selection and typed event/hash counts) remain
    /// copied from the verified native lowerer sidecar.
    init(
        original: GoldenEyeSourceFrontendOriginalCanonicalV6,
        sidecar: GoldenEyeSourceFrontendFrameSummaryV6,
        provenance: GoldenEyeSourceFrontendFrameProvenanceV6 = .originalCanonical
    ) {
        self.provenance = provenance
        flags = original.flags
        screen = original.screen
        subphase = original.subphase
        nativeTick = original.nativeTick
        referenceTick = original.referenceTick
        sourceFrame = original.sourceFrame
        sourceTimer = original.sourceTimer
        sourceThreshold = original.sourceThreshold
        transitionTimer = original.transitionTimer
        selection = sidecar.selection
        unsupportedCount = original.unsupportedCount
        stateHash = original.stateHash
        renderHash = original.renderHash
        audioHash = original.audioHash
        screenHash = sidecar.screenHash
        modelHash = sidecar.modelHash
        textHash = sidecar.textHash
        audioEventHash = sidecar.audioEventHash
        saveHash = sidecar.saveHash
        renderEventHash = sidecar.renderEventHash
        diagnosticHash = sidecar.diagnosticHash
        screenEvents = sidecar.screenEvents
        modelEvents = sidecar.modelEvents
        textEvents = sidecar.textEvents
        audioEvents = sidecar.audioEvents
        saveEvents = sidecar.saveEvents
        renderEvents = sidecar.renderEvents
        diagnosticEvents = sidecar.diagnosticEvents
        rarewareCounter = original.rarewareCounter
    }

    fileprivate init(
        relabeling source: GoldenEyeSourceFrontendFrameSummaryV6,
        provenance: GoldenEyeSourceFrontendFrameProvenanceV6,
        rarewareCounter: UInt32? = nil
    ) {
        self.provenance = provenance
        flags = source.flags
        screen = source.screen
        subphase = source.subphase
        nativeTick = source.nativeTick
        referenceTick = source.referenceTick
        sourceFrame = source.sourceFrame
        sourceTimer = source.sourceTimer
        sourceThreshold = source.sourceThreshold
        transitionTimer = source.transitionTimer
        selection = source.selection
        unsupportedCount = source.unsupportedCount
        stateHash = source.stateHash
        renderHash = source.renderHash
        audioHash = source.audioHash
        screenHash = source.screenHash
        modelHash = source.modelHash
        textHash = source.textHash
        audioEventHash = source.audioEventHash
        saveHash = source.saveHash
        renderEventHash = source.renderEventHash
        diagnosticHash = source.diagnosticHash
        screenEvents = source.screenEvents
        modelEvents = source.modelEvents
        textEvents = source.textEvents
        audioEvents = source.audioEvents
        saveEvents = source.saveEvents
        renderEvents = source.renderEvents
        diagnosticEvents = source.diagnosticEvents
        self.rarewareCounter = rarewareCounter ?? source.rarewareCounter
    }
}

public struct GoldenEyeSourceFrontendScreenEventV6: Sendable, Equatable {
    public let event: UInt32
    public let screen: UInt32
    public let targetScreen: UInt32
    public let nativeTick: UInt64
    public let sourceFrame: UInt32
    public let sourceTimer: UInt32
    public let transitionTimer: UInt32
    public let flags: UInt32
    public let sequence: UInt64

    init(_ value: GEFrontendRuntimeV6ScreenEvent) {
        event = UInt32(value.event)
        screen = UInt32(value.screen)
        targetScreen = UInt32(value.target_screen)
        nativeTick = UInt64(value.native_tick)
        sourceFrame = UInt32(value.source_frame)
        sourceTimer = UInt32(value.source_timer)
        transitionTimer = UInt32(value.transition_timer)
        flags = UInt32(value.flags)
        sequence = UInt64(value.sequence)
    }
}

public struct GoldenEyeSourceFrontendModelEventV6: Sendable, Equatable {
    public let screen: UInt32
    public let model: UInt32
    public let operation: UInt32
    public let nativeTick: UInt64
    public let referenceTick: UInt64
    public let sourceTimer: UInt32
    public let subphase: UInt32
    public let flags: UInt32
    public let sequence: UInt64
    public let resultFlags: UInt32
    public let resultValue0: UInt32
    public let resultValue1: UInt32

    public var gunbarrelSourceSubstep: UInt32? {
        guard flags & UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_FLAG_GUNBARREL_TIMER_VALID) != 0 else {
            return nil
        }
        return (flags & UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GUNBARREL_TIMER_MASK)) >>
            UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GUNBARREL_TIMER_SHIFT)
    }

    init(_ value: GEFrontendRuntimeV6ModelEvent) {
        screen = UInt32(value.screen)
        model = UInt32(value.model)
        operation = UInt32(value.operation)
        nativeTick = UInt64(value.native_tick)
        referenceTick = UInt64(value.reference_tick)
        sourceTimer = UInt32(value.source_timer)
        subphase = UInt32(value.subphase)
        flags = UInt32(value.flags)
        sequence = UInt64(value.sequence)
        resultFlags = UInt32(value.result_flags)
        resultValue0 = UInt32(value.result_value0)
        resultValue1 = UInt32(value.result_value1)
    }
}

public struct GoldenEyeSourceFrontendTextEventV6: Sendable, Equatable {
    public let screen: UInt32
    public let textID: UInt32
    public let x: Int32
    public let y: Int32
    public let nativeTick: UInt64
    public let sourceTimer: UInt32
    public let flags: UInt32
    public let sequence: UInt64

    init(_ value: GEFrontendRuntimeV6TextEvent) {
        screen = UInt32(value.screen)
        textID = UInt32(value.text_id)
        x = Int32(value.x)
        y = Int32(value.y)
        nativeTick = UInt64(value.native_tick)
        sourceTimer = UInt32(value.source_timer)
        flags = UInt32(value.flags)
        sequence = UInt64(value.sequence)
    }
}

public struct GoldenEyeSourceFrontendAudioEventV6: Sendable, Equatable {
    public let screen: UInt32
    public let operation: UInt32
    public let assetID: UInt32
    public let nativeTick: UInt64
    public let sourceSample: UInt64
    public let sourceTimer: UInt32
    public let flags: UInt32
    public let sequence: UInt64

    init(_ value: GEFrontendRuntimeV6AudioEvent) {
        screen = UInt32(value.screen)
        operation = UInt32(value.operation)
        assetID = UInt32(value.asset_id)
        nativeTick = UInt64(value.native_tick)
        sourceSample = UInt64(value.source_sample)
        sourceTimer = UInt32(value.source_timer)
        flags = UInt32(value.flags)
        sequence = UInt64(value.sequence)
    }
}

public struct GoldenEyeSourceFrontendSaveEventV6: Sendable, Equatable {
    public let screen: UInt32
    public let operation: UInt32
    public let folder: UInt32
    public let nativeTick: UInt64
    public let sequence: UInt64

    init(_ value: GEFrontendRuntimeV6SaveEvent) {
        screen = UInt32(value.screen)
        operation = UInt32(value.operation)
        folder = UInt32(value.folder)
        nativeTick = UInt64(value.native_tick)
        sequence = UInt64(value.sequence)
    }
}

public struct GoldenEyeSourceFrontendRenderEventV6: Sendable, Equatable {
    public let screen: UInt32
    public let operation: UInt32
    public let subphase: UInt32
    public let nativeTick: UInt64
    public let referenceTick: UInt64
    public let sourceTimer: UInt32
    public let value0: Int32
    public let value1: Int32
    public let flags: UInt32
    public let sequence: UInt64

    init(_ value: GEFrontendRuntimeV6RenderEvent) {
        screen = UInt32(value.screen)
        operation = UInt32(value.operation)
        subphase = UInt32(value.subphase)
        nativeTick = UInt64(value.native_tick)
        referenceTick = UInt64(value.reference_tick)
        sourceTimer = UInt32(value.source_timer)
        value0 = Int32(value.value0)
        value1 = Int32(value.value1)
        flags = UInt32(value.flags)
        sequence = UInt64(value.sequence)
    }
}

public struct GoldenEyeSourceFrontendDiagnosticEventV6: Sendable, Equatable {
    public let screen: UInt32
    public let code: UInt32
    public let severity: UInt32
    public let sourceTimer: UInt32
    public let nativeTick: UInt64
    public let sequence: UInt64
    public let detail0: UInt32
    public let detail1: UInt32

    init(_ value: GEFrontendRuntimeV6DiagnosticEvent) {
        screen = UInt32(value.screen)
        code = UInt32(value.code)
        severity = UInt32(value.severity)
        sourceTimer = UInt32(value.source_timer)
        nativeTick = UInt64(value.native_tick)
        sequence = UInt64(value.sequence)
        detail0 = UInt32(value.detail0)
        detail1 = UInt32(value.detail1)
    }
}

public struct GoldenEyeSourceFrontendFrameV6: Sendable, Equatable {
    public let summary: GoldenEyeSourceFrontendFrameSummaryV6
    public var provenance: GoldenEyeSourceFrontendFrameProvenanceV6 { summary.provenance }
    /// Additive File/Mode snapshot.  The legacy source summary and hashes are
    /// unchanged; this copied sidecar carries wallet switches, text flags,
    /// cursor/action state, and menu save/SFX events without a pointer.
    public let fileModeFrame: GoldenEyeFileModeFrameV6?
    /// Copied semantic save state paired with the File/Mode frame.  This is
    /// deliberately Swift value data; the 596-byte wire file and SaveStore
    /// remain outside the source frontend ABI.  Keeping the four folders on
    /// the immutable frame lets the renderer emit the source progress text
    /// for every wallet without reaching back into mutable authority state.
    public let fileModeSaveState: GoldenEyeSaveState?
    public let screenEvents: [GoldenEyeSourceFrontendScreenEventV6]
    public let modelEvents: [GoldenEyeSourceFrontendModelEventV6]
    public let textEvents: [GoldenEyeSourceFrontendTextEventV6]
    public let audioEvents: [GoldenEyeSourceFrontendAudioEventV6]
    public let saveEvents: [GoldenEyeSourceFrontendSaveEventV6]
    public let renderEvents: [GoldenEyeSourceFrontendRenderEventV6]
    public let diagnosticEvents: [GoldenEyeSourceFrontendDiagnosticEventV6]
    /// Source-authoritative Rareware animation counter.  Unlike `sourceTimer`,
    /// this advances while the source is on the Rareware screen.
    public let rarewareCounter: UInt32

    public var flags: UInt32 { summary.flags }
    public var screen: UInt32 { summary.screen }
    public var subphase: UInt32 { summary.subphase }
    public var nativeTick: UInt64 { summary.nativeTick }
    public var referenceTick: UInt64 { summary.referenceTick }
    public var sourceFrame: UInt32 { summary.sourceFrame }
    public var sourceTimer: UInt32 { summary.sourceTimer }
    public var sourceThreshold: UInt32 { summary.sourceThreshold }
    public var transitionTimer: UInt32 { summary.transitionTimer }
    public var unsupportedCount: UInt32 { summary.unsupportedCount }
    public var stateHash: UInt64 { summary.stateHash }
    public var renderHash: UInt64 { summary.renderHash }
    public var audioHash: UInt64 { summary.audioHash }
    public var screenHash: UInt64 { summary.screenHash }
    public var modelHash: UInt64 { summary.modelHash }
    public var textHash: UInt64 { summary.textHash }
    public var audioEventHash: UInt64 { summary.audioEventHash }
    public var saveHash: UInt64 { summary.saveHash }
    public var renderEventHash: UInt64 { summary.renderEventHash }
    public var diagnosticHash: UInt64 { summary.diagnosticHash }
    public var walletSwitchMask: UInt32 { fileModeFrame?.walletSwitchMask ?? 0 }
    public var menuTextFlags: UInt32 { fileModeFrame?.textFlags ?? 0 }
    public var menuLastAction: UInt32 { fileModeFrame?.lastAction ?? 0 }
    public var menuLastSFX: UInt32 { fileModeFrame?.lastSFX ?? 0 }

    init(
        _ frame: GEFrontendRuntimeV6Frame,
        fileModeFrame: GoldenEyeFileModeFrameV6? = nil,
        fileModeSaveState: GoldenEyeSaveState? = nil,
        provenance: GoldenEyeSourceFrontendFrameProvenanceV6 = .nativeBootstrap
    ) {
        summary = GoldenEyeSourceFrontendFrameSummaryV6(
            frame.snapshot,
            provenance: provenance
        )
        self.fileModeFrame = fileModeFrame
        self.fileModeSaveState = fileModeSaveState
        screenEvents = Self.copy(
            frame.events.screens,
            count: Int(frame.events.screen_count),
            as: GEFrontendRuntimeV6ScreenEvent.self
        ).map(GoldenEyeSourceFrontendScreenEventV6.init)
        modelEvents = Self.copy(
            frame.events.models,
            count: Int(frame.events.model_count),
            as: GEFrontendRuntimeV6ModelEvent.self
        ).map(GoldenEyeSourceFrontendModelEventV6.init)
        textEvents = Self.copy(
            frame.events.texts,
            count: Int(frame.events.text_count),
            as: GEFrontendRuntimeV6TextEvent.self
        ).map(GoldenEyeSourceFrontendTextEventV6.init)
        audioEvents = Self.copy(
            frame.events.audio,
            count: Int(frame.events.audio_count),
            as: GEFrontendRuntimeV6AudioEvent.self
        ).map(GoldenEyeSourceFrontendAudioEventV6.init)
        saveEvents = Self.copy(
            frame.events.saves,
            count: Int(frame.events.save_count),
            as: GEFrontendRuntimeV6SaveEvent.self
        ).map(GoldenEyeSourceFrontendSaveEventV6.init)
        renderEvents = Self.copy(
            frame.events.renders,
            count: Int(frame.events.render_count),
            as: GEFrontendRuntimeV6RenderEvent.self
        ).map(GoldenEyeSourceFrontendRenderEventV6.init)
        diagnosticEvents = Self.copy(
            frame.events.diagnostics,
            count: Int(frame.events.diagnostic_count),
            as: GEFrontendRuntimeV6DiagnosticEvent.self
        ).map(GoldenEyeSourceFrontendDiagnosticEventV6.init)
        rarewareCounter = 0
    }

    /// Retains the native typed frame arrays as verified lowerings/sidecars,
    /// while replacing only scalar authority fields represented by the
    /// original C frame/state ABI.
    init(
        authoritative original: GoldenEyeSourceFrontendOriginalCanonicalV6,
        sidecar: GoldenEyeSourceFrontendFrameV6
    ) {
        summary = GoldenEyeSourceFrontendFrameSummaryV6(
            original: original,
            sidecar: sidecar.summary
        )
        fileModeFrame = sidecar.fileModeFrame
        fileModeSaveState = sidecar.fileModeSaveState
        screenEvents = sidecar.screenEvents
        modelEvents = sidecar.modelEvents
        textEvents = sidecar.textEvents
        audioEvents = sidecar.audioEvents
        saveEvents = sidecar.saveEvents
        renderEvents = sidecar.renderEvents
        diagnosticEvents = sidecar.diagnosticEvents
        rarewareCounter = original.rarewareCounter
    }

    private init(
        summary: GoldenEyeSourceFrontendFrameSummaryV6,
        sidecar: GoldenEyeSourceFrontendFrameV6
    ) {
        self.summary = summary
        fileModeFrame = sidecar.fileModeFrame
        fileModeSaveState = sidecar.fileModeSaveState
        screenEvents = sidecar.screenEvents
        modelEvents = sidecar.modelEvents
        textEvents = sidecar.textEvents
        audioEvents = sidecar.audioEvents
        saveEvents = sidecar.saveEvents
        renderEvents = sidecar.renderEvents
        diagnosticEvents = sidecar.diagnosticEvents
        rarewareCounter = summary.rarewareCounter
    }

    func withProvenance(
        _ provenance: GoldenEyeSourceFrontendFrameProvenanceV6
    ) -> Self {
        Self(
            summary: GoldenEyeSourceFrontendFrameSummaryV6(
                relabeling: summary,
                provenance: provenance
            ),
            sidecar: self
        )
    }

    func withRarewareCounter(_ counter: UInt32) -> Self {
        Self(
            summary: GoldenEyeSourceFrontendFrameSummaryV6(
                relabeling: summary,
                provenance: summary.provenance,
                rarewareCounter: counter
            ),
            sidecar: self
        )
    }

    private static func copy<T, C>(
        _ values: C,
        count: Int,
        as type: T.Type
    ) -> [T] {
        let safeCount = min(max(count, 0), Int(GE_SOURCE_FRONTEND_RUNTIME_V6_MAX_EVENTS))
        return withUnsafeBytes(of: values) { rawBytes in
            let typed = rawBytes.bindMemory(to: T.self)
            return Array(typed.prefix(safeCount))
        }
    }
}

public enum GoldenEyeSourceFrontendAuthorityV6Error: Error, Sendable, Equatable,
    CustomStringConvertible
{
    case cStatus(UInt32)
    case invalidTimeline
    case timelineOutOfOrder(expected: UInt64, actual: UInt64)

    public var description: String {
        switch self {
        case let .cStatus(status):
            return "source frontend V6 C status " + String(status)
        case .invalidTimeline:
            return "source frontend V6 timeline ticks start at one"
        case let .timelineOutOfOrder(expected, actual):
            return "source frontend V6 expected tick " + String(expected) + ", got " + String(actual)
        }
    }
}

/// Swift's value authority around the C source facade.  It owns no callback
/// table and no scheduler counter.  The mutable C state is copied in and out
/// on every explicit timeline step; render/model requests remain diagnostic
/// until a complete scene adapter returns a positive result in the C seam.
public struct GoldenEyeSourceFrontendAuthorityV6: @unchecked Sendable {
    public private(set) var state: GEFrontendRuntimeV6State
    public private(set) var lastFrame: GoldenEyeSourceFrontendFrameV6
    public private(set) var fileModeFrame: GoldenEyeFileModeFrameV6?
    private var fileModeAuthority: GoldenEyeFileModeAuthorityV6?
    private var installedFileModeSaveState: GoldenEyeSaveState?

    public var fileModeSaveState: GoldenEyeSaveState? {
        fileModeAuthority?.saveState ?? installedFileModeSaveState
    }

    public var lastSummary: GoldenEyeSourceFrontendFrameSummaryV6 {
        lastFrame.summary
    }

    public init() throws {
        var cState = GEFrontendRuntimeV6State()
        var cFrame = GEFrontendRuntimeV6Frame()
        let status = ge_frontend_runtime_v6_init(&cState, &cFrame)
        guard status == GE_STATUS_OK else {
            throw GoldenEyeSourceFrontendAuthorityV6Error.cStatus(UInt32(status))
        }
        state = cState
        fileModeFrame = nil
        fileModeAuthority = nil
        installedFileModeSaveState = nil
        lastFrame = GoldenEyeSourceFrontendFrameV6(cFrame)
            .withRarewareCounter(UInt32(cState.rareware_counter))
    }

    /// Internal parity-test hook. Production callers never mutate authority
    /// state outside `step`; the paired smoke uses this to prove that an
    /// original/native projection mismatch is rejected on the next anchor.
    internal mutating func mutateProjectionForTesting(sourceTimer: UInt32) {
        state.source_timer = sourceTimer
    }

    /// Installs the already decoded SaveStore semantic value.  The frozen
    /// 596-byte GESWSAVE wire record never crosses this authority boundary;
    /// only the copied four-folder projection is passed to File/Mode C.
    public mutating func installSaveState(_ save: GoldenEyeSaveState) throws {
        installedFileModeSaveState = save
        if var fileModeAuthority {
            try fileModeAuthority.installSaveState(save)
            self.fileModeAuthority = fileModeAuthority
        }
    }

    @discardableResult
    public mutating func step(
        _ timeline: GoldenEyeSourceFrontendTimelineV6,
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
        modelResultValue1: UInt32 = 0,
        pairedLifecycle: Bool = false
    ) throws -> GoldenEyeSourceFrontendFrameV6 {
        let expectedTick = UInt64(state.native_tick) + 1
        guard timeline.nativeTick == expectedTick else {
            throw GoldenEyeSourceFrontendAuthorityV6Error.timelineOutOfOrder(
                expected: expectedTick,
                actual: timeline.nativeTick
            )
        }
        guard buttonsPressed & ~UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_MASK) == 0,
              controllerCount <= 4,
              (fileModeControllerCount ?? controllerCount) <= 4,
              clockTimer <= 4,
              modelResultOperation <= UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_BLOOD_TICK),
              modelResultFlags & ~UInt32(0x03) == 0,
              modelResultOperation != 0 ||
                  (modelResultModel == 0 && modelResultFlags == 0 &&
                   modelResultValue0 == 0 && modelResultValue1 == 0) else {
            throw GoldenEyeSourceFrontendAuthorityV6Error.cStatus(
                UInt32(GE_STATUS_MALFORMED_STREAM)
            )
        }

        var input = GEFrontendRuntimeV6Input()
        input.header.abi_version = GE_NATIVE_ABI_VERSION
        input.header.struct_size = UInt32(MemoryLayout<GEFrontendRuntimeV6Input>.size)
        input.record_version = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_RECORD_VERSION)
        input.flags = timeline.isSourceAnchor
            ? UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_INPUT_FLAG_SOURCE_ANCHOR)
            : 0
        if focused {
            input.flags |= UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_INPUT_FLAG_FOCUSED)
        }
        if controllerConnected {
            input.flags |= UInt32(
                GE_SOURCE_FRONTEND_RUNTIME_V6_INPUT_FLAG_CONTROLLER_CONNECTED
            )
        }
        if synthetic {
            input.flags |= UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_INPUT_FLAG_SYNTHETIC)
        }
        if pairedLifecycle {
            input.flags |= UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_INPUT_FLAG_PAIRED_ORACLE)
        }
        input.buttons_pressed = buttonsPressed
        input.controller_count = controllerCount
        input.clock_timer = clockTimer
        input.native_tick = timeline.nativeTick
        input.sequence = timeline.nativeTick
        input.model_result_model = modelResultModel
        input.model_result_operation = modelResultOperation
        input.model_result_flags = modelResultFlags
        input.model_result_value0 = modelResultValue0
        input.model_result_value1 = modelResultValue1

        var cFrame = GEFrontendRuntimeV6Frame()
        let status = ge_frontend_runtime_v6_step(&state, &input, &cFrame)
        guard status == GE_STATUS_OK else {
            throw GoldenEyeSourceFrontendAuthorityV6Error.cStatus(UInt32(status))
        }
        let sourceFrame = GoldenEyeSourceFrontendFrameV6(cFrame)
            .withRarewareCounter(UInt32(state.rareware_counter))
        var menuFrame: GoldenEyeFileModeFrameV6?
        let menuActive = fileModeAuthority != nil ||
            sourceFrame.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_FILE_SELECT) ||
            sourceFrame.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_MODE_SELECT)
        if menuActive {
            if fileModeAuthority == nil {
                let save = installedFileModeSaveState ?? .blank
                fileModeAuthority = try GoldenEyeFileModeAuthorityV6(
                    saveState: save,
                    startingBeforeNativeTick: timeline.nativeTick - 1
                )
            }
            var menuButtons = fileModePressed
            if menuButtons == nil {
                menuButtons = Self.fileModeButtons(fromSourceButtons: buttonsPressed)
            }
            let menuInput = GoldenEyeFileModeInputV6(
                nativeTick: timeline.nativeTick,
                sequence: timeline.nativeTick,
                held: fileModeHeld,
                pressed: menuButtons ?? 0,
                released: fileModeReleased,
                stickX: fileModeStickX,
                stickY: fileModeStickY,
                controllerCount: fileModeControllerCount ?? controllerCount,
                clockTimer: timeline.isSourceAnchor ? clockTimer : 0,
                focused: focused,
                controllerConnected: controllerConnected,
                synthetic: synthetic
            )
            menuFrame = try fileModeAuthority!.step(menuInput)
            installedFileModeSaveState = fileModeAuthority!.saveState
        } else {
            fileModeAuthority = nil
            installedFileModeSaveState = nil
        }
        fileModeFrame = menuFrame
        let frame = GoldenEyeSourceFrontendFrameV6(
            cFrame,
            fileModeFrame: menuFrame,
            fileModeSaveState: fileModeAuthority?.saveState
        ).withRarewareCounter(UInt32(state.rareware_counter))
        lastFrame = frame
        return frame
    }

    private static func fileModeButtons(fromSourceButtons buttons: UInt32) -> UInt32 {
        var result: UInt32 = 0
        if buttons & UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_CONFIRM) != 0 {
            result |= UInt32(GE_FILE_MODE_V6_BUTTON_A)
        }
        if buttons & UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_CANCEL) != 0 {
            result |= UInt32(GE_FILE_MODE_V6_BUTTON_B)
        }
        if buttons & UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_UP) != 0 {
            result |= UInt32(GE_FILE_MODE_V6_BUTTON_DPAD_UP)
        }
        if buttons & UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_DOWN) != 0 {
            result |= UInt32(GE_FILE_MODE_V6_BUTTON_DPAD_DOWN)
        }
        if buttons & UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_LEFT) != 0 {
            result |= UInt32(GE_FILE_MODE_V6_BUTTON_DPAD_LEFT)
        }
        if buttons & UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_RIGHT) != 0 {
            result |= UInt32(GE_FILE_MODE_V6_BUTTON_DPAD_RIGHT)
        }
        return result
    }
}
