import Foundation
#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

@main
struct GoldenEyeSourceFrontendInitializationV6Smoke {
    static func main() {
        do {
            try run()
            print("goldeneye_source_frontend_initialization_v6_smoke: PASS")
        } catch {
            fputs("goldeneye_source_frontend_initialization_v6_smoke: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func run() throws {
        var authority = try GoldenEyeSourceFrontendAuthorityV6()
        let initialization = authority.lastFrame
        precondition(initialization.nativeTick == 0)
        precondition(initialization.screenEvents.contains {
            $0.event == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_EVENT_SCREEN_ENTER)
        })
        precondition(initialization.audioEvents.contains {
            $0.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_AUDIO_OP_STOP_MUSIC) &&
                $0.sourceSample == 0
        })
        precondition(initialization.saveEvents.contains {
            $0.operation == 1 && $0.folder == UInt32.max
        })

        var ledger = GoldenEyeSourceFrontendInitializationLedgerV6()
        let firstConsume = try ledger.consume(frame: initialization)
        precondition(firstConsume)
        precondition(!ledger.pendingModelLoads.isEmpty)
        let duplicateConsume = try ledger.consume(frame: initialization)
        precondition(!duplicateConsume)

        // A pause/resume interval does not create a second owner lifecycle or
        // replay tick-zero events.
        _ = try authority.step(try GoldenEyeSourceFrontendTimelineV6(nativeTick: 1))
        let pausedConsume = try ledger.consume(frame: initialization)
        precondition(!pausedConsume)

        // A newly constructed owner/authority gets one fresh initialization
        // service, independent of the prior run.
        let restartedAuthority = try GoldenEyeSourceFrontendAuthorityV6()
        var restartedLedger = GoldenEyeSourceFrontendInitializationLedgerV6()
        let restartConsume = try restartedLedger.consume(frame: restartedAuthority.lastFrame)
        precondition(restartConsume)
        let restartDuplicate = try restartedLedger.consume(frame: restartedAuthority.lastFrame)
        precondition(!restartDuplicate)
    }
}
