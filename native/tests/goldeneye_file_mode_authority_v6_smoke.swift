import Foundation

@main
struct GoldenEyeFileModeAuthorityV6Smoke {
    static func main() {
        do {
            try run()
            print("goldeneye_file_mode_authority_v6_smoke: PASS")
        } catch {
            fputs("goldeneye_file_mode_authority_v6_smoke: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func run() throws {
        precondition(MemoryLayout<GESaveFolderV1>.size == 96)
        precondition(MemoryLayout<GESaveSnapshotV1>.size == 432)
        precondition(MemoryLayout<GEFileModeInputV6>.size == 72)
        precondition(MemoryLayout<GEFileModeStateV6>.size == 104)
        precondition(MemoryLayout<GEFileModeEventV6>.size == 88)
        precondition(MemoryLayout<GEFileModeFrameV6>.size == 2960)

        var authority = try GoldenEyeFileModeAuthorityV6()
        precondition(authority.lastFrame.state.screen ==
                     GE_FILE_MODE_V6_SCREEN_FILE_SELECT.rawValue)
        precondition(authority.lastFrame.state.cursorXQ16 == 220 * 65_536)
        precondition(authority.lastFrame.state.cursorYQ16 == 165 * 65_536)

        let first = try authority.step(.init(
            nativeTick: 1,
            sequence: 1,
            pressed: UInt32(GE_FILE_MODE_V6_BUTTON_A),
            synthetic: true
        ))
        precondition(first.state.screen == GE_FILE_MODE_V6_SCREEN_MODE_SELECT.rawValue)
        precondition(first.saveEvents.contains {
            $0.command == GE_FILE_MODE_V6_SAVE_CREATE.rawValue
        })
        precondition(authority.saveState.folders[0].isUsable)

        let back = try authority.step(.init(
            nativeTick: 2,
            sequence: 2,
            pressed: UInt32(GE_FILE_MODE_V6_BUTTON_B),
            synthetic: true
        ))
        precondition(back.state.screen == GE_FILE_MODE_V6_SCREEN_FILE_SELECT.rawValue)
        precondition(back.events.contains {
            $0.kind == GE_FILE_MODE_V6_EVENT_SFX.rawValue &&
                $0.command == GE_FILE_MODE_V6_SFX_DOOR_METAL_CLOSE2.rawValue
        })

        /* A short between-tick tap is one event; releasing on the next native
         * tick does not repeat the source action. */
        let tap = try authority.step(.init(
            nativeTick: 3,
            sequence: 3,
            pressed: UInt32(GE_FILE_MODE_V6_BUTTON_A),
            synthetic: true
        ))
        precondition(tap.events.filter {
            $0.kind == GE_FILE_MODE_V6_EVENT_SCREEN.rawValue
        }.count == 1)
        let release = try authority.step(.init(
            nativeTick: 4,
            sequence: 4,
            released: UInt32(GE_FILE_MODE_V6_BUTTON_A),
            synthetic: true
        ))
        precondition(release.events.isEmpty)

        /* Controller count is copied into the source state and gates the MP
         * row without making a mission launch claim. */
        _ = try authority.step(.init(
            nativeTick: 5,
            sequence: 5,
            stickY: 75,
            controllerCount: 2,
            synthetic: true
        ))
        _ = try authority.step(.init(
            nativeTick: 6,
            sequence: 6,
            stickY: 75,
            controllerCount: 2,
            synthetic: true
        ))
        _ = try authority.step(.init(
            nativeTick: 7,
            sequence: 7,
            stickY: 75,
            controllerCount: 2,
            synthetic: true
        ))
        _ = try authority.step(.init(
            nativeTick: 8,
            sequence: 8,
            stickY: 75,
            controllerCount: 2,
            synthetic: true
        ))
        _ = try authority.step(.init(
            nativeTick: 9,
            sequence: 9,
            stickY: 75,
            controllerCount: 2,
            synthetic: true
        ))
        _ = try authority.step(.init(
            nativeTick: 10,
            sequence: 10,
            stickY: 75,
            controllerCount: 2,
            synthetic: true
        ))
        _ = try authority.step(.init(
            nativeTick: 11,
            sequence: 11,
            stickY: 75,
            controllerCount: 2,
            synthetic: true
        ))
        _ = try authority.step(.init(
            nativeTick: 12,
            sequence: 12,
            stickY: 75,
            controllerCount: 2,
            synthetic: true
        ))
        let multi = try authority.step(.init(
            nativeTick: 13,
            sequence: 13,
            pressed: UInt32(GE_FILE_MODE_V6_BUTTON_START),
            controllerCount: 2,
            synthetic: true
        ))
        precondition(multi.state.screen == GE_FILE_MODE_V6_SCREEN_MULTI_ROUTE.rawValue)
        let hasMultiRoute = multi.events.contains {
            $0.kind == GE_FILE_MODE_V6_EVENT_ROUTE.rawValue &&
                $0.command == GE_FILE_MODE_V6_SCREEN_MULTI_ROUTE.rawValue
        }
        precondition(hasMultiRoute)
    }
}
