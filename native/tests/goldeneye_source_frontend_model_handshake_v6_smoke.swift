import Foundation
#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

@available(macOS 26.0, *)
private final class FakeSourceRendererV6: GoldenEyeSourceFrontendFrameRendererV6,
    GoldenEyeSourceFrontendModelResultProviderV6,
    @unchecked Sendable
{
    private(set) var submittedFrames: [GoldenEyeSourceFrontendFrameV6] = []
    private var nextResult: GoldenEyeSourceProductModelExecutionResultV6?

    func submit(sourceFrontendFrame frame: GoldenEyeSourceFrontendFrameV6) throws {
        if submittedFrames.isEmpty {
            guard frame.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_LEGAL),
                  frame.modelEvents.contains(where: {
                      $0.model == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_LEGALPAGE) &&
                          $0.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_DRAW)
                  }) else {
                throw NSError(domain: "FakeSourceRendererV6", code: 1)
            }
            nextResult = .executed(
                model: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_LEGALPAGE),
                operation: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_DRAW)
            )
        }
        submittedFrames.append(frame)
    }

    func takeModelExecutionResult() -> GoldenEyeSourceProductModelExecutionResultV6? {
        defer { nextResult = nil }
        return nextResult
    }
}
@main
struct GoldenEyeSourceFrontendModelHandshakeV6Smoke {
    static func main() {
        do {
            try run()
            print("goldeneye_source_frontend_model_handshake_v6_smoke: PASS")
        } catch {
            fputs("goldeneye_source_frontend_model_handshake_v6_smoke: \(error)\n", stderr)
            exit(1)
        }
    }

    @available(macOS 26.0, *)
    private static func run() throws {
        var authority = try GoldenEyeSourceFrontendAuthorityV6()
        var handshake = GoldenEyeSourceFrontendModelHandshakeV6()
        let renderer = FakeSourceRendererV6()

        let input1 = handshake.takeForAuthority()
        precondition(input1 == .none)
        let frame1 = try authority.step(
            try GoldenEyeSourceFrontendTimelineV6(nativeTick: 1),
            modelResultModel: input1.model,
            modelResultOperation: input1.operation,
            modelResultFlags: input1.flags,
            modelResultValue0: input1.value0,
            modelResultValue1: input1.value1
        )
        precondition(frame1.modelEvents.contains {
            $0.model == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_LEGALPAGE) &&
                $0.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_DRAW) &&
                $0.resultFlags == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_NONE)
        })
        try renderer.submit(sourceFrontendFrame: frame1)
        handshake.retainSuccessfulResult(renderer.takeModelExecutionResult())

        let input2 = handshake.takeForAuthority()
        precondition(input2.model == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_LEGALPAGE))
        precondition(input2.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_DRAW))
        precondition(input2.flags == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_EXECUTED))
        let frame2 = try authority.step(
            try GoldenEyeSourceFrontendTimelineV6(nativeTick: 2),
            modelResultModel: input2.model,
            modelResultOperation: input2.operation,
            modelResultFlags: input2.flags,
            modelResultValue0: input2.value0,
            modelResultValue1: input2.value1
        )
        precondition(frame2.modelEvents.contains {
            $0.model == input2.model &&
                $0.operation == input2.operation &&
                $0.resultFlags == input2.flags
        })
        try renderer.submit(sourceFrontendFrame: frame2)
        handshake.retainSuccessfulResult(renderer.takeModelExecutionResult())
        precondition(renderer.takeModelExecutionResult() == nil)

        let input3 = handshake.takeForAuthority()
        precondition(input3 == .none)
        let frame3 = try authority.step(
            try GoldenEyeSourceFrontendTimelineV6(nativeTick: 3),
            modelResultModel: input3.model,
            modelResultOperation: input3.operation,
            modelResultFlags: input3.flags,
            modelResultValue0: input3.value0,
            modelResultValue1: input3.value1
        )
        precondition(frame3.modelEvents.contains {
            $0.model == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_LEGALPAGE) &&
                $0.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_DRAW) &&
                $0.resultFlags == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_NONE)
        })
        precondition(renderer.submittedFrames.count == 2)
    }
}
