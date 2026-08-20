import Foundation
#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

@main
struct GoldenEyeSourceFrontendPresentationV6Smoke {
    static func main() {
        do {
            try run()
            print("goldeneye_source_frontend_presentation_v6_smoke: PASS")
        } catch {
            fputs("goldeneye_source_frontend_presentation_v6_smoke: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func run() throws {
        var authority = try GoldenEyeSourceFrontendAuthorityV6()
        var adapter = GoldenEyeSourceFrontendPresentationAdapterV6()

        let first = try authority.step(
            try GoldenEyeSourceFrontendTimelineV6(nativeTick: 1)
        )
        let firstPresentation = try adapter.snapshot(from: first)
        precondition(firstPresentation.sourceScreen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_LEGAL))
        precondition(firstPresentation.pairPhase == 1)
        precondition(firstPresentation.timer120 == 1)
        precondition(firstPresentation.stateHash == first.stateHash)
        precondition(firstPresentation.renderEventHash == first.renderEventHash)

        var switchFrame: GoldenEyeSourceFrontendFrameV6?
        var nintendoFrame: GoldenEyeSourceFrontendFrameV6?
        for tick in UInt64(2)...UInt64(490) {
            let frame = try authority.step(
                try GoldenEyeSourceFrontendTimelineV6(nativeTick: tick)
            )
            if tick == 482 { switchFrame = frame }
            if tick == 490 { nintendoFrame = frame }
        }
        precondition(switchFrame?.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_SWITCH))
        let switchPresentation = try adapter.snapshot(from: switchFrame!)
        precondition(switchPresentation.sourceScreen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_LEGAL))
        precondition(nintendoFrame?.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_NINTENDO))
        let nintendoPresentation = try adapter.snapshot(from: nintendoFrame!)
        precondition(nintendoPresentation.sourceScreen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_NINTENDO))
        precondition(nintendoPresentation.referenceTick == 245)
        precondition(nintendoPresentation.timer120 == 0)
        precondition(nintendoPresentation.modelHash == nintendoFrame!.modelHash)
        precondition(nintendoPresentation.audioEventHash == nintendoFrame!.audioEventHash)
    }
}
