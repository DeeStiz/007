import Foundation
#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

@main
struct GoldenEyeTitleTimebaseV6Smoke {
    static func main() {
        do {
            try run()
            print("goldeneye_title_timebase_v6_swift_smoke: PASS")
        } catch {
            fputs("goldeneye_title_timebase_v6_swift_smoke: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func run() throws {
        var authority = try GoldenEyeSourceFrontendAuthorityV6()
        var nextTick = UInt64(authority.state.native_tick) + 1

        while authority.state.screen != UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_NINTENDO) {
            _ = try authority.step(
                GoldenEyeSourceFrontendTimelineV6(nativeTick: nextTick),
                controllerCount: 1,
                clockTimer: 1,
                focused: true,
                controllerConnected: true,
                synthetic: true
            )
            nextTick += 1
            precondition(nextTick < 700)
        }

        // Nintendo's first odd projection is after the first source anchor.
        let priorNintendoRenderHash = authority.lastFrame.summary.renderHash
        let oddNintendo = try authority.step(
            GoldenEyeSourceFrontendTimelineV6(nativeTick: nextTick),
            controllerCount: 1,
            clockTimer: 1,
            focused: true,
            controllerConnected: true,
            synthetic: true
        )
        precondition(oddNintendo.nativeTick & 1 == 1)
        let nintendoContinuous = oddNintendo.renderEvents.filter {
            $0.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_CONTINUOUS_STATE)
        }
        precondition(nintendoContinuous.count == 2)
        precondition(nintendoContinuous.allSatisfy {
            ($0.flags & UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_FLAG_HALF_STEP)) != 0 &&
                ($0.flags & UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_FLAG_Q16_VALUES)) != 0
        })
        precondition(oddNintendo.summary.renderHash != priorNintendoRenderHash)
        nextTick += 1

        // The first odd frame after Rareware enters carries rotation/alpha
        // midpoints while the source counter remains anchor-owned.
        while authority.state.screen != UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_RAREWARE) {
            _ = try authority.step(
                GoldenEyeSourceFrontendTimelineV6(nativeTick: nextTick),
                controllerCount: 1,
                clockTimer: 1,
                focused: true,
                controllerConnected: true,
                synthetic: true
            )
            nextTick += 1
            precondition(nextTick < 2_000)
        }
        if nextTick & 1 == 0 {
            nextTick += 1
        }
        let oddRareware = try authority.step(
            GoldenEyeSourceFrontendTimelineV6(nativeTick: nextTick),
            controllerCount: 1,
            clockTimer: 1,
            focused: true,
            controllerConnected: true,
            synthetic: true
        )
        let rarewareContinuous = oddRareware.renderEvents.first {
            $0.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_CONTINUOUS_STATE) &&
                $0.subphase == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_CONTINUOUS_RAREWARE_ROTATION_ALPHA)
        }
        precondition(rarewareContinuous != nil)
        precondition(oddRareware.summary.renderHash != 0)
    }
}
