import Foundation
#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

@available(macOS 26.0, *)
private final class HeadlessSourceFrameConsumerV6: GoldenEyeSourceFrontendFrameRendererV6,
    @unchecked Sendable
{
    private(set) var submittedScreens: [UInt32] = []
    private(set) var submittedFrames: UInt64 = 0
    private(set) var switchFrames: [GoldenEyeSourceFrontendFrameV6] = []
    private(set) var modeFrames: [GoldenEyeSourceFrontendFrameV6] = []

    func submit(sourceFrontendFrame frame: GoldenEyeSourceFrontendFrameV6) throws {
        let screen = GoldenEyeSourceFrontendScreenSelectionV6.renderableScreen(for: frame)
        guard frame.nativeTick > 0,
              frame.stateHash != 0,
              frame.renderHash != 0,
              frame.renderEventHash != 0,
              frame.unsupportedCount == 0,
              frame.diagnosticEvents.isEmpty else {
            throw NSError(
                domain: "HeadlessSourceFrameConsumerV6",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "non-consumable source frame tick=\(frame.nativeTick) screen=\(frame.screen) "
                        + "rendered=\(screen) unsupported=\(frame.unsupportedCount) "
                        + "diagnostics=\(frame.diagnosticEvents.count)"
                ]
            )
        }

        if frame.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_SWITCH) {
            let visibleModelDraws = frame.modelEvents.filter {
                $0.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_DRAW)
            }
            guard visibleModelDraws.isEmpty,
                  frame.renderEvents.contains(where: {
                      $0.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_CLEAR_BLACK)
                  }) else {
                throw NSError(
                    domain: "HeadlessSourceFrameConsumerV6",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "switch frame contains visible work"]
                )
            }
            switchFrames.append(frame)
        } else {
            let draw = frame.modelEvents.first(where: {
                $0.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_DRAW)
            })
            let isInitialGunbarrel = screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL)
                && frame.renderEvents.contains(where: {
                    $0.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_GUNBARREL_PIPELINE
                    )
                })
            guard (draw == nil && isInitialGunbarrel) ||
                  (draw != nil && GoldenEyeSourceFrontendScreenSelectionV6.containsModelDraw(
                      frame,
                      model: draw!.model,
                      operation: draw!.operation,
                      renderedScreen: screen
                  )),
                  frame.renderEvents.contains(where: {
                      $0.operation != UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_UNSUPPORTED)
                  }) else {
                throw NSError(
                    domain: "HeadlessSourceFrameConsumerV6",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey:
                        "renderable source frame has no consumable model draw tick=\(frame.nativeTick) screen=\(screen) "
                        + "modelCount=\(frame.modelEvents.count) renderCount=\(frame.renderEvents.count)"]
                )
            }
            if screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_MODE_SELECT) {
                modeFrames.append(frame)
            }
        }
        submittedScreens.append(screen)
        submittedFrames &+= 1
    }
}

private enum SourceRouteKindV6 {
    case permittedSkipToMode
    case handsOffToCast
}

@main
struct GoldenEyeSourceProductBootRouteV6Smoke {
    static func main() {
        do {
            try run()
            print("goldeneye_source_product_boot_route_v6_smoke: PASS")
        } catch {
            fputs("goldeneye_source_product_boot_route_v6_smoke: \(error)\n", stderr)
            exit(1)
        }
    }

    @available(macOS 26.0, *)
    private static func run() throws {
        try runRoute(.permittedSkipToMode)
        try runRoute(.handsOffToCast)
    }

    @available(macOS 26.0, *)
    private static func runRoute(_ route: SourceRouteKindV6) throws {
        var authority = try GoldenEyeSourceFrontendAuthorityV6()
        let consumer = HeadlessSourceFrameConsumerV6()
        var sawScreens: Set<UInt32> = []
        var sawCast = false
        var sentMenuConfirm = false
        var sawMode = false
        var lastSwitchAnchorTimer: UInt32 = 0
        var switchRunAnchorTimers: Set<UInt32> = []

        for tick in UInt64(1)...UInt64(5_000) {
            let buttons: UInt32
            switch route {
            case .permittedSkipToMode:
                // The source only permits this input edge after the first
                // main-menu flag has been cleared.  It preserves Legal,
                // Nintendo, Rareware, Gunbarrel, and GoldenEye while taking
                // the authored GoldenEye -> File Select shortcut.
                if authority.state.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GOLDENEYE),
                   !sawScreens.contains(UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_FILE_SELECT)) {
                    buttons = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_ANY)
                } else if !sentMenuConfirm,
                          authority.state.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_FILE_SELECT),
                          sawScreens.contains(UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_FILE_SELECT)) {
                    buttons = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_CONFIRM)
                    sentMenuConfirm = true
                } else {
                    buttons = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_NONE)
                }
            case .handsOffToCast:
                buttons = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_NONE)
            }

            let result = modelResultForSourceState(
                authority.state,
                nativeTick: tick
            )
            let frame = try authority.step(
                try GoldenEyeSourceFrontendTimelineV6(nativeTick: tick),
                buttonsPressed: buttons,
                controllerCount: 1,
                fileModeControllerCount: 1,
                clockTimer: 1,
                focused: true,
                controllerConnected: true,
                synthetic: true,
                modelResultModel: result.model,
                modelResultOperation: result.operation,
                modelResultFlags: result.flags,
                modelResultValue0: result.value0,
                modelResultValue1: result.value1,
                pairedLifecycle: true
            )

            if frame.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_CAST) {
                sawCast = true
                guard route == .handsOffToCast else {
                    throw NSError(domain: "SourceRoute", code: 10, userInfo: [
                        NSLocalizedDescriptionKey: "permitted skip entered Cast"
                    ])
                }
                guard frame.renderEvents.contains(where: {
                    $0.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_CAST_PIPELINE)
                }), frame.unsupportedCount == 0, frame.diagnosticEvents.isEmpty else {
                    throw NSError(domain: "SourceRoute", code: 11, userInfo: [
                        NSLocalizedDescriptionKey: "Cast source pipeline was not emitted cleanly"
                    ])
                }
                break
            }

            try consumer.submit(sourceFrontendFrame: frame)
            sawScreens.insert(GoldenEyeSourceFrontendScreenSelectionV6.renderableScreen(for: frame))
            if frame.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_SWITCH),
               frame.nativeTick & 1 == 0 {
                lastSwitchAnchorTimer = frame.transitionTimer
                switchRunAnchorTimers.insert(frame.transitionTimer)
            }
            if consumer.modeFrames.contains(where: { $0.nativeTick == frame.nativeTick }) {
                sawMode = true
                break
            }
        }

        let expectedRenderable: Set<UInt32> = [
            UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_LEGAL),
            UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_NINTENDO),
            UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_RAREWARE),
            UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL),
            UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GOLDENEYE)
        ]
        guard expectedRenderable.isSubset(of: sawScreens) else {
            throw NSError(domain: "SourceRoute", code: 12, userInfo: [
                NSLocalizedDescriptionKey:
                    "missing branded source screens: \(expectedRenderable.subtracting(sawScreens))"
            ])
        }
        guard !consumer.switchFrames.isEmpty,
              switchRunAnchorTimers == Set([0, 1, 2, 3]),
              lastSwitchAnchorTimer == 3 else {
            throw NSError(domain: "SourceRoute", code: 13, userInfo: [
                NSLocalizedDescriptionKey: "missing four-source-tick black switch evidence timers=\(switchRunAnchorTimers.sorted()) last=\(lastSwitchAnchorTimer) frames=\(consumer.switchFrames.map { $0.nativeTick })"
            ])
        }

        switch route {
        case .permittedSkipToMode:
            guard sawScreens.contains(UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_FILE_SELECT)),
                  sawMode,
                  !consumer.modeFrames.isEmpty else {
                throw NSError(domain: "SourceRoute", code: 14, userInfo: [
                    NSLocalizedDescriptionKey: "permitted skip did not submit File/Mode frames"
                ])
            }
            print("route=permitted-skip screens=\(sawScreens.sorted()) submitted=\(consumer.submittedFrames) mode=1")
        case .handsOffToCast:
            guard sawCast else {
                throw NSError(domain: "SourceRoute", code: 15, userInfo: [
                    NSLocalizedDescriptionKey: "hands-off route did not reach Cast boundary"
                ])
            }
            print("route=hands-off screens=\(sawScreens.sorted()) submitted=\(consumer.submittedFrames) cast-handoff=1")
        }
    }

    private static func modelResultForSourceState(
        _ state: GEFrontendRuntimeV6State,
        nativeTick: UInt64
    ) -> (model: UInt32, operation: UInt32, flags: UInt32, value0: UInt32, value1: UInt32) {
        let executed = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_EXECUTED)
        let bloodComplete = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_BLOOD_COMPLETE)
        if state.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL),
           state.gunbarrel_mode == 5,
           nativeTick & 1 == 0 {
            return (
                UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GUNBARREL),
                UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_BLOOD_TICK),
                executed | bloodComplete, 0, 0
            )
        }
        if state.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_SWITCH),
           state.pending_reload != UInt32.max {
            let model: UInt32
            switch state.pending_reload {
            case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_NINTENDO):
                model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_NINTENDOLOGO)
            case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_RAREWARE):
                model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RAREWARELOGO)
            case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL):
                model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GUNBARREL)
            case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GOLDENEYE):
                model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GOLDENEYELOGO)
            case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_FILE_SELECT),
                 UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_MODE_SELECT):
                model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_WALLETBOND)
            default:
                model = 0
            }
            if model != 0 {
                return (model, UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_DRAW), executed, 0, 0)
            }
        }
        let transitionLikely =
            (state.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_LEGAL) && state.source_timer >= 240) ||
            (state.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_NINTENDO) && state.source_timer >= 500) ||
            (state.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GOLDENEYE) && state.source_timer >= 180) ||
            (state.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_RAREWARE) && state.rareware_mode == 2) ||
            (state.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL) && state.gunbarrel_mode == 9)
        if nativeTick & 1 == 0,
           state.screen != UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_SWITCH),
           transitionLikely {
            let model: UInt32
            switch state.screen {
            case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_LEGAL):
                model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_LEGALPAGE)
            case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_NINTENDO):
                model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_NINTENDOLOGO)
            case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_RAREWARE):
                model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RAREWARELOGO)
            case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL):
                model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GUNBARREL)
            case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GOLDENEYE):
                model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GOLDENEYELOGO)
            case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_FILE_SELECT),
                 UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_MODE_SELECT):
                model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_WALLETBOND)
            default:
                model = 0
            }
            if model != 0 {
                return (model, UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_RELEASE), executed, 0, 0)
            }
        }
        let model: UInt32
        switch state.screen {
        case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_LEGAL):
            model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_LEGALPAGE)
        case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_NINTENDO):
            model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_NINTENDOLOGO)
        case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_RAREWARE):
            model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RAREWARELOGO)
        case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL):
            model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GUNBARREL)
        case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GOLDENEYE):
            model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GOLDENEYELOGO)
        case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_FILE_SELECT),
             UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_MODE_SELECT):
            model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_WALLETBOND)
        default:
            model = 0
        }
        guard model != 0 else { return (0, 0, 0, 0, 0) }
        return (model, UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_DRAW), executed, 0, 0)
    }
}
