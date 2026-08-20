import Foundation

@main
struct GoldenEyeFileModePairedV6Smoke {
    static func main() throws {
        try exactEvenEndpointAndMidpoint()
        try axisChangesAtPairBoundaries()
        try oddActionsCommitOnce()
        try sourceAnchorIdleTiming()
        print("goldeneye_file_mode_paired_v6_smoke: PASS")
    }

    private static func exactEvenEndpointAndMidpoint() throws {
        var paired = try GoldenEyeFileModeAuthorityV6()
        var reference = try GoldenEyeFileModeAuthorityV6()
        let initialY = paired.lastFrame.state.cursorYQ16

        let odd = try paired.step(.init(
            nativeTick: 1,
            sequence: 1,
            stickY: 75,
            synthetic: true
        ))
        _ = try reference.step(.init(
            nativeTick: 1,
            sequence: 1,
            synthetic: true
        ))
        let even = try paired.step(.init(
            nativeTick: 2,
            sequence: 2,
            stickY: 75,
            synthetic: true
        ))
        let referenceEven = try reference.step(.init(
            nativeTick: 2,
            sequence: 2,
            stickY: 75,
            synthetic: true
        ))

        precondition(odd.state.cursorYQ16 > initialY)
        precondition(odd.state.cursorYQ16 < even.state.cursorYQ16)
        precondition(even.state.cursorYQ16 == referenceEven.state.cursorYQ16)
        precondition(even.state.cursorXQ16 == referenceEven.state.cursorXQ16)
        precondition(even.state.stateAnchorEquivalent(to: referenceEven.state))
    }

    private static func axisChangesAtPairBoundaries() throws {
        var axisPair = try GoldenEyeFileModeAuthorityV6()
        var axisReference = try GoldenEyeFileModeAuthorityV6()
        _ = try axisPair.step(.init(nativeTick: 1, sequence: 1, synthetic: true))
        _ = try axisReference.step(.init(nativeTick: 1, sequence: 1, synthetic: true))
        _ = try axisPair.step(.init(nativeTick: 2, sequence: 2, synthetic: true))
        _ = try axisReference.step(.init(nativeTick: 2, sequence: 2, synthetic: true))
        let axisOdd = try axisPair.step(.init(
            nativeTick: 3,
            sequence: 3,
            stickX: -75,
            synthetic: true
        ))
        let axisEven = try axisPair.step(.init(nativeTick: 4, sequence: 4, stickX: -75, synthetic: true))
        _ = try axisReference.step(.init(nativeTick: 3, sequence: 3, stickX: -75, synthetic: true))
        let axisReferenceEven = try axisReference.step(.init(nativeTick: 4, sequence: 4, stickX: -75, synthetic: true))
        precondition(axisOdd.state.cursorXQ16 < 220 * 65_536)
        precondition(axisEven.state.cursorXQ16 == axisReferenceEven.state.cursorXQ16)
        precondition(axisEven.state.cursorYQ16 == axisReferenceEven.state.cursorYQ16)
    }

    private static func oddActionsCommitOnce() throws {
        var authority = try GoldenEyeFileModeAuthorityV6()
        let confirm = try authority.step(.init(
            nativeTick: 1,
            sequence: 1,
            pressed: UInt32(GE_FILE_MODE_V6_BUTTON_A),
            synthetic: true
        ))
        let confirmEven = try authority.step(.init(
            nativeTick: 2,
            sequence: 2,
            released: UInt32(GE_FILE_MODE_V6_BUTTON_A),
            synthetic: true
        ))
        precondition(confirm.state.screen == GE_FILE_MODE_V6_SCREEN_MODE_SELECT.rawValue)
        precondition(confirm.saveEvents.filter { $0.command == GE_FILE_MODE_V6_SAVE_CREATE.rawValue }.count == 1)
        precondition(confirmEven.saveEvents.isEmpty)
        precondition(confirmEven.events.filter { $0.kind == GE_FILE_MODE_V6_EVENT_SCREEN.rawValue }.isEmpty)
        precondition(confirmEven.events.filter { $0.kind == GE_FILE_MODE_V6_EVENT_SFX.rawValue }.isEmpty)

        let cancel = try authority.step(.init(
            nativeTick: 3,
            sequence: 3,
            pressed: UInt32(GE_FILE_MODE_V6_BUTTON_B),
            synthetic: true
        ))
        let cancelEven = try authority.step(.init(
            nativeTick: 4,
            sequence: 4,
            released: UInt32(GE_FILE_MODE_V6_BUTTON_B),
            synthetic: true
        ))
        precondition(cancel.state.screen == GE_FILE_MODE_V6_SCREEN_FILE_SELECT.rawValue)
        precondition(cancel.events.filter { $0.kind == GE_FILE_MODE_V6_EVENT_SCREEN.rawValue }.count == 1)
        precondition(cancelEven.events.filter { $0.kind == GE_FILE_MODE_V6_EVENT_SCREEN.rawValue }.isEmpty)
        precondition(cancelEven.events.filter { $0.kind == GE_FILE_MODE_V6_EVENT_SFX.rawValue }.isEmpty)
    }

    private static func sourceAnchorIdleTiming() throws {
        var authority = try GoldenEyeFileModeAuthorityV6()
        var frame = authority.lastFrame
        for tick in UInt64(1)...UInt64(GE_FILE_MODE_V6_FILE_IDLE_THRESHOLD * 2 - 1) {
            frame = try authority.step(.init(
                nativeTick: tick,
                sequence: tick,
                synthetic: true
            ))
        }
        precondition(frame.state.screen == GE_FILE_MODE_V6_SCREEN_FILE_SELECT.rawValue)
        frame = try authority.step(.init(
            nativeTick: UInt64(GE_FILE_MODE_V6_FILE_IDLE_THRESHOLD * 2),
            sequence: UInt64(GE_FILE_MODE_V6_FILE_IDLE_THRESHOLD * 2),
            synthetic: true
        ))
        precondition(frame.state.screen == GE_FILE_MODE_V6_SCREEN_LEGAL.rawValue)
        precondition(frame.events.contains {
            $0.kind == GE_FILE_MODE_V6_EVENT_SCREEN.rawValue &&
                $0.targetScreen == GE_FILE_MODE_V6_SCREEN_LEGAL.rawValue
        })
    }
}

private extension GoldenEyeFileModeStateSnapshotV6 {
    func stateAnchorEquivalent(to other: Self) -> Bool {
        screen == other.screen && flags == other.flags &&
            fileOption == other.fileOption && eraseChoice == other.eraseChoice &&
            selectedFolder == other.selectedFolder && hoveredFolder == other.hoveredFolder &&
            modeSelection == other.modeSelection && controllerCount == other.controllerCount &&
            idleTimer == other.idleTimer && cursorXQ16 == other.cursorXQ16 &&
            cursorYQ16 == other.cursorYQ16 && route == other.route
    }
}
