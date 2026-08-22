import Foundation
#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

/// A copied presentation view of one source-frontend frame.  This is not a
/// scene result: it contains only values already emitted by the C source
/// authority.  Model, text, audio, save, render, and diagnostic records remain
/// available on ``GoldenEyeSourceFrontendFrameV6`` for a complete consumer.
public struct GoldenEyeSourceFrontendPresentationSnapshotV6: Sendable, Equatable {
    public let nativeTick: UInt64
    public let referenceTick: UInt64
    public let pairPhase: UInt8
    public let sourceScreen: UInt32
    public let sourceSubphase: UInt32
    public let sourceTimer: UInt32
    public let transitionTimer: UInt32
    public let selection: UInt32
    public let titleXQ16: Int32
    public let titleRotationQ16: Int32
    public let titleScaleQ16: Int32
    public let alphaQ16: Int32
    public let titleLightQ8: UInt16
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
    public let unsupportedCount: UInt32

    init(frame: GoldenEyeSourceFrontendFrameV6, renderedScreen: UInt32, titleXQ16: Int32, alphaQ16: Int32) {
        let summary = frame.summary
        nativeTick = summary.nativeTick
        referenceTick = summary.referenceTick
        pairPhase = UInt8(summary.nativeTick & 1)
        sourceScreen = renderedScreen
        sourceSubphase = summary.subphase
        sourceTimer = summary.sourceTimer
        transitionTimer = summary.transitionTimer
        selection = summary.selection
        self.titleXQ16 = titleXQ16
        titleRotationQ16 = 0
        titleScaleQ16 = 0x0001_0000
        self.alphaQ16 = alphaQ16
        titleLightQ8 = 0x00ff
        stateHash = summary.stateHash
        renderHash = summary.renderHash
        audioHash = summary.audioHash
        screenHash = summary.screenHash
        modelHash = summary.modelHash
        textHash = summary.textHash
        audioEventHash = summary.audioEventHash
        saveHash = summary.saveHash
        renderEventHash = summary.renderEventHash
        diagnosticHash = summary.diagnosticHash
        unsupportedCount = summary.unsupportedCount
    }

    public var isReferenceAnchor: Bool { pairPhase == 0 }

    /// The legacy title renderer's timer fields are native-tick values.  The
    /// source timer is a 60 Hz source value, so this conversion is exact for
    /// both halves of a paired native tick.
    public var timer120: UInt32 {
        let doubled = UInt64(sourceTimer) &* 2
        return UInt32(truncatingIfNeeded: doubled &+ UInt64(pairPhase))
    }

    public var gunbarrelTimer120: UInt32 { timer120 }
}

/// Renderer-side handoff for the complete source frame.  A renderer may
/// implement this in addition to a legacy title snapshot consumer.  The
/// owner never fabricates a model result when this protocol is absent.
@available(macOS 26.0, *)
protocol GoldenEyeSourceFrontendFrameRendererV6: AnyObject {
    func submit(sourceFrontendFrame: GoldenEyeSourceFrontendFrameV6) throws
}

@available(macOS 26.0, *)
protocol GoldenEyeSourceFrontendModelResultProviderV6: AnyObject, Sendable {
    func takeModelExecutionResult() -> GoldenEyeSourceProductModelExecutionResultV6?
}

@available(macOS 26.0, *)
protocol GoldenEyeSourceFrontendModelLifecycleV6: AnyObject, Sendable {
    func acknowledgeSourceModelLoad(model: UInt32) throws
    /// Resets source-owned Gunbarrel blood state at an authoritative screen
    /// entry, including entries whose Cast/SWITCH frames bypass the renderer.
    func resetGunbarrelBloodStream()
}

enum GoldenEyeSourceFrontendOwnerError: Error, Sendable, Equatable, CustomStringConvertible {
    case rendererDoesNotAcceptSourceFrames

    var description: String {
        switch self {
        case .rendererDoesNotAcceptSourceFrames:
            return "Release renderer does not accept copied source frontend frames"
        }
    }
}

/// Converts only source-emitted state and render-event values into the small
/// compatibility presentation view used by the existing title host.  The
/// adapter deliberately does not create geometry, materials, text, audio, or
/// model results.  A full source scene renderer should consume the original
/// frame protocol above instead.
struct GoldenEyeSourceFrontendPresentationAdapterV6: Sendable {
    private(set) var lastRenderableScreen: UInt32 = GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_LEGAL

    mutating func snapshot(
        from frame: GoldenEyeSourceFrontendFrameV6
    ) throws -> GoldenEyeSourceFrontendPresentationSnapshotV6 {
        let sourceScreen = frame.screen
        if sourceScreen != GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_SWITCH {
            guard sourceScreen == GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_LEGAL ||
                    sourceScreen == GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_NINTENDO ||
                    sourceScreen == GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_RAREWARE ||
                    sourceScreen == GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL ||
                    sourceScreen == GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GOLDENEYE ||
                    sourceScreen == GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_FILE_SELECT ||
                    sourceScreen == GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_MODE_SELECT ||
                    sourceScreen == GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_CAST else {
                throw GoldenEyeSourceFrontendPresentationError.unsupportedScreen(sourceScreen)
            }
            lastRenderableScreen = sourceScreen
        }

        var titleXQ16: Int32 = 0
        var alphaQ16: Int32 = 0x0001_0000
        for event in frame.renderEvents {
            switch event.operation {
            case GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_GUNBARREL_PIPELINE:
                titleXQ16 = event.value0
            case GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_RAREWARE_PIPELINE:
                let alpha = min(max(event.value0, 0), 255)
                alphaQ16 = alpha * 257
            default:
                continue
            }
        }
        return GoldenEyeSourceFrontendPresentationSnapshotV6(
            frame: frame,
            renderedScreen: lastRenderableScreen,
            titleXQ16: titleXQ16,
            alphaQ16: alphaQ16
        )
    }
}

enum GoldenEyeSourceFrontendPresentationError: Error, Sendable, Equatable, CustomStringConvertible {
    case unsupportedScreen(UInt32)

    var description: String {
        switch self {
        case .unsupportedScreen(let screen):
            return "source frontend presentation cannot represent screen \(screen)"
        }
    }
}
