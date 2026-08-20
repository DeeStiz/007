import Foundation
#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

@main
struct GoldenEyeSourceSwitchPacketV6Smoke {
    static func main() {
        do {
            var authority = try GoldenEyeSourceFrontendAuthorityV6()
            var switchFrame: GoldenEyeSourceFrontendFrameV6?
            for tick in UInt64(1)...UInt64(482) {
                let timeline = try GoldenEyeSourceFrontendTimelineV6(nativeTick: tick)
                let frame = try authority.step(
                    timeline,
                    modelResultModel: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GUNBARREL),
                    modelResultOperation: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_BLOOD_TICK),
                    modelResultFlags: UInt32(
                        GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_BLOOD_COMPLETE |
                            GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_EXECUTED
                    )
                )
                if tick == 482 {
                    switchFrame = frame
                }
            }
            guard let frame = switchFrame else { throw Failure.missingFrame }
            let operations = frame.renderEvents.map(\.operation)
            let screens = frame.renderEvents.map(\.screen)
            guard frame.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_SWITCH),
                  frame.unsupportedCount == 0,
                  operations == [
                    UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_FRAME_BEGIN),
                    UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_CLEAR_BLACK)
                  ],
                  screens.allSatisfy({
                      $0 == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_SWITCH)
                  }),
                  frame.textEvents.isEmpty,
                  frame.modelEvents.allSatisfy({
                      $0.operation != UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_DRAW)
                  }) else {
                throw Failure.notTransitionOnly
            }
            print(
                "screen=\(frame.screen) unsupported=\(frame.unsupportedCount) "
                    + "modelOperations=\(frame.modelEvents.map(\.operation)) "
                    + "texts=\(frame.textEvents.count) renders=\(operations) "
                    + "renderScreens=\(screens) diagnostics=\(frame.diagnosticEvents.count)"
            )
            print("goldeneye_source_switch_packet_v6_smoke: PASS")
        } catch {
            fputs("goldeneye_source_switch_packet_v6_smoke: \(error)\n", stderr)
            exit(1)
        }
    }

    private enum Failure: Error {
        case missingFrame
        case notTransitionOnly
    }
}
