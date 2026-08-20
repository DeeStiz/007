import Foundation
#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

/// Resolves the screen that the product renderer must present from one copied
/// source frame.  The source C frontend keeps its branded route screen at
/// FILE_SELECT while the additive File/Mode authority advances its own screen
/// to MODE_SELECT.  Rendering must consume that value-only sidecar without
/// mutating or rewriting the source frame summary.
enum GoldenEyeSourceFrontendScreenSelectionV6 {
    static func renderableScreen(
        for frame: GoldenEyeSourceFrontendFrameV6
    ) -> UInt32 {
        guard frame.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_FILE_SELECT),
              let menuScreen = frame.fileModeFrame?.state.screen,
              menuScreen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_FILE_SELECT)
                  || menuScreen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_MODE_SELECT)
        else {
            return frame.screen
        }
        return menuScreen
    }

    static func containsModelDraw(
        _ frame: GoldenEyeSourceFrontendFrameV6,
        model: UInt32,
        operation: UInt32,
        renderedScreen: UInt32
    ) -> Bool {
        if frame.modelEvents.contains(where: {
            $0.model == model && $0.operation == operation
        }) {
            return frame.screen == renderedScreen
                || (frame.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_FILE_SELECT)
                    && renderedScreen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_MODE_SELECT))
        }
        // Gunbarrel's initial source subphase emits only its pipeline and
        // continuous values while the LOAD event remains the model lifecycle
        // authority.  The product can lower that typed pipeline using the
        // guarded Gunbarrel sidecar without manufacturing a source model draw.
        return frame.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL)
            && model == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GUNBARREL)
            && operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_DRAW)
            && frame.renderEvents.contains(where: {
                $0.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_GUNBARREL_PIPELINE)
            })
    }
}
