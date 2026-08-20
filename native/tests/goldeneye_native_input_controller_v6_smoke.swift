import Foundation

@main
struct GoldenEyeNativeInputControllerV6Smoke {
    private static func drain(
        _ mailbox: GoldenEyeInputMailbox,
        at tick: UInt64
    ) -> GoldenEyeInputSnapshot {
        mailbox.drain(at: tick)
    }

    static func main() {
        // Aliased keyboard actions retain their edge until every physical key
        // contributing that action is released.
        let aliases = GoldenEyeInputMailbox()
        aliases.enqueueKeyboard(keyCode: 0x24, isDown: true, timestampNanoseconds: 1)
        aliases.enqueueKeyboard(keyCode: 0x31, isDown: true, timestampNanoseconds: 1)
        var snapshot = drain(aliases, at: 1)
        precondition(snapshot.pressed == GoldenEyeN64Buttons.start.rawValue | GoldenEyeN64Buttons.a.rawValue)
        aliases.enqueueKeyboard(keyCode: 0x24, isDown: false, timestampNanoseconds: 2)
        snapshot = drain(aliases, at: 2)
        precondition(snapshot.released == GoldenEyeN64Buttons.start.rawValue)
        precondition(snapshot.held == GoldenEyeN64Buttons.a.rawValue)
        aliases.enqueueKeyboard(keyCode: 0x31, isDown: false, timestampNanoseconds: 3)
        snapshot = drain(aliases, at: 3)
        precondition(snapshot.released == GoldenEyeN64Buttons.a.rawValue)

        // A connected controller contributes a physical count before its
        // first sample, and its first non-neutral sample is baseline-only.
        let merge = GoldenEyeInputMailbox()
        merge.markControllerConnected(controllerID: 11)
        snapshot = drain(merge, at: 1)
        precondition(snapshot.controllerCount == 1)
        precondition(snapshot.sourceFlags & GoldenEyeInputSourceFlags.edgeSuppressed.rawValue != 0)
        merge.enqueueController(controllerID: 11, buttons: [], stickX: 0, stickY: 0, timestampNanoseconds: 2)
        snapshot = drain(merge, at: 2)
        precondition(snapshot.sourceFlags & GoldenEyeInputSourceFlags.edgeSuppressed.rawValue == 0)

        // The merge is per-axis and magnitude based: -40 analog does not
        // erase -75 digital, while -80 analog does win.
        merge.enqueueKeyboard(keyCode: 0x00, isDown: true, timestampNanoseconds: 3)
        merge.enqueueController(controllerID: 11, buttons: [], stickX: -40, stickY: 0, timestampNanoseconds: 3)
        snapshot = drain(merge, at: 3)
        precondition(snapshot.stickX == -75)
        merge.enqueueController(controllerID: 11, buttons: [], stickX: -80, stickY: 0, timestampNanoseconds: 4)
        snapshot = drain(merge, at: 4)
        precondition(snapshot.stickX == -80)

        // D-pad buttons are independent even when opposing directions are
        // held, and their digital axis contribution cancels to zero.
        merge.enqueueController(
            controllerID: 11,
            buttons: [.dpadUp, .dpadDown],
            stickX: 0,
            stickY: 0,
            timestampNanoseconds: 5
        )
        snapshot = drain(merge, at: 5)
        precondition(snapshot.pressed & GoldenEyeN64Buttons.dpadUp.rawValue != 0)
        precondition(snapshot.pressed & GoldenEyeN64Buttons.dpadDown.rawValue != 0)
        precondition(snapshot.stickY == 0)

        // Inactive controller samples are drained but cannot leak into the
        // single-player aggregate.  Switching the active ID makes its latest
        // immutable state authoritative without changing physical count.
        merge.markControllerConnected(controllerID: 12)
        merge.enqueueController(controllerID: 12, buttons: [], stickX: 0, stickY: 0, active: false, timestampNanoseconds: 6)
        snapshot = drain(merge, at: 6)
        precondition(snapshot.controllerCount == 2)
        merge.enqueueController(controllerID: 12, buttons: [.a], stickX: 0, stickY: 0, active: false, timestampNanoseconds: 7)
        snapshot = drain(merge, at: 7)
        precondition(snapshot.pressed & GoldenEyeN64Buttons.a.rawValue == 0)
        merge.setActiveController(controllerID: 12)
        snapshot = drain(merge, at: 8)
        precondition(snapshot.pressed & GoldenEyeN64Buttons.a.rawValue != 0)
        precondition(snapshot.controllerCount == 2)

        // Focus and disconnect clear state and suppress stale reconnect edges
        // until a neutral state is observed.
        let recovery = GoldenEyeInputMailbox()
        recovery.enqueueController(controllerID: 21, buttons: [], stickX: 0, stickY: 0, timestampNanoseconds: 1)
        _ = drain(recovery, at: 1)
        recovery.enqueueController(controllerID: 21, buttons: [.a], stickX: 0, stickY: 0, timestampNanoseconds: 2)
        snapshot = drain(recovery, at: 2)
        precondition(snapshot.pressed == GoldenEyeN64Buttons.a.rawValue)
        recovery.enqueueFocusLost(timestampNanoseconds: 3)
        snapshot = drain(recovery, at: 3)
        precondition(snapshot.held == 0 && snapshot.pressed == 0 && snapshot.released == 0)
        recovery.enqueueFocusGained(timestampNanoseconds: 4)
        recovery.enqueueController(controllerID: 21, buttons: [.a], stickX: 0, stickY: 0, timestampNanoseconds: 4)
        snapshot = drain(recovery, at: 4)
        precondition(snapshot.pressed == 0)
        precondition(snapshot.sourceFlags & GoldenEyeInputSourceFlags.edgeSuppressed.rawValue != 0)
        recovery.enqueueController(controllerID: 21, buttons: [], stickX: 0, stickY: 0, timestampNanoseconds: 5)
        snapshot = drain(recovery, at: 5)
        precondition(snapshot.sourceFlags & GoldenEyeInputSourceFlags.edgeSuppressed.rawValue == 0)
        recovery.enqueueControllerDisconnected(controllerID: 21, timestampNanoseconds: 6)
        snapshot = drain(recovery, at: 6)
        precondition(snapshot.controllerCount == 0)
        recovery.enqueueController(controllerID: 21, buttons: [.a], stickX: 0, stickY: 0, timestampNanoseconds: 7)
        snapshot = drain(recovery, at: 7)
        precondition(snapshot.pressed == 0)

        print("goldeneye_native_input_controller_v6_smoke: PASS")
    }
}
