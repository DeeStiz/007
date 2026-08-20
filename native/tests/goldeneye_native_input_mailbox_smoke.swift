import Foundation

@main
struct GoldenEyeNativeInputMailboxSmoke {
    static func main() {
        let mailbox = GoldenEyeInputMailbox()

        mailbox.enqueueKeyboard(keyCode: 0x0D, isDown: true, timestampNanoseconds: 1)
        var snapshot = mailbox.drain(at: 1)
        precondition(snapshot.stickY == 75)
        precondition(snapshot.pressed == GoldenEyeN64Buttons.dpadUp.rawValue)

        mailbox.enqueueKeyboard(keyCode: 0x01, isDown: true, timestampNanoseconds: 2)
        snapshot = mailbox.drain(at: 2)
        precondition(snapshot.stickY == 0, "opposing digital axes must cancel")
        mailbox.enqueueKeyboard(keyCode: 0x0D, isDown: false, timestampNanoseconds: 3)
        snapshot = mailbox.drain(at: 3)
        precondition(snapshot.stickY == -75)
        mailbox.enqueueKeyboard(keyCode: 0x01, isDown: false, timestampNanoseconds: 4)
        _ = mailbox.drain(at: 4)

        mailbox.enqueueKeyboard(keyCode: 0x24, isDown: true, timestampNanoseconds: 4)
        snapshot = mailbox.drain(at: 4)
        precondition(snapshot.pressed == GoldenEyeN64Buttons.start.rawValue)
        mailbox.enqueueKeyboard(keyCode: 0x24, isDown: true, isRepeat: true, timestampNanoseconds: 5)
        snapshot = mailbox.drain(at: 5)
        precondition(snapshot.pressed == 0)
        mailbox.enqueueKeyboard(keyCode: 0x24, isDown: false, timestampNanoseconds: 6)
        snapshot = mailbox.drain(at: 6)
        precondition(snapshot.released == GoldenEyeN64Buttons.start.rawValue)

        mailbox.enqueueKeyboard(keyCode: 0x31, isDown: true, timestampNanoseconds: 6)
        snapshot = mailbox.drain(at: 6)
        precondition(snapshot.pressed == GoldenEyeN64Buttons.a.rawValue)
        mailbox.enqueueKeyboard(keyCode: 0x31, isDown: false, timestampNanoseconds: 6)
        _ = mailbox.drain(at: 6)

        mailbox.enqueueController(controllerID: 1, buttons: [.a], stickX: 80, stickY: 0, timestampNanoseconds: 7)
        snapshot = mailbox.drain(at: 7)
        precondition(snapshot.pressed == 0)
        precondition(snapshot.stickX == 80)
        precondition(snapshot.sourceFlags & GoldenEyeInputSourceFlags.controllerConnected.rawValue != 0)
        mailbox.enqueueController(controllerID: 1, buttons: [], stickX: 0, stickY: 0, timestampNanoseconds: 8)
        snapshot = mailbox.drain(at: 8)
        precondition(snapshot.sourceFlags & GoldenEyeInputSourceFlags.edgeSuppressed.rawValue == 0)
        mailbox.enqueueController(controllerID: 1, buttons: [.a, .dpadRight], stickX: 80, stickY: 0, timestampNanoseconds: 9)
        snapshot = mailbox.drain(at: 9)
        precondition(snapshot.pressed == (GoldenEyeN64Buttons.a.rawValue | GoldenEyeN64Buttons.dpadRight.rawValue))

        mailbox.enqueueFocusLost(timestampNanoseconds: 10)
        snapshot = mailbox.drain(at: 10)
        precondition(snapshot.held == 0 && snapshot.pressed == 0 && snapshot.released == 0)
        mailbox.enqueueFocusGained(timestampNanoseconds: 9)
        mailbox.enqueueController(controllerID: 1, buttons: [.a], stickX: 0, stickY: 0, timestampNanoseconds: 10)
        snapshot = mailbox.drain(at: 10)
        precondition(snapshot.pressed == 0)
        precondition(snapshot.sourceFlags & GoldenEyeInputSourceFlags.edgeSuppressed.rawValue != 0)
        mailbox.enqueueController(controllerID: 1, buttons: [], stickX: 0, stickY: 0, timestampNanoseconds: 11)
        snapshot = mailbox.drain(at: 11)
        precondition(snapshot.sourceFlags & GoldenEyeInputSourceFlags.edgeSuppressed.rawValue == 0)
        mailbox.enqueueController(controllerID: 1, buttons: [.a], stickX: 0, stickY: 0, timestampNanoseconds: 12)
        snapshot = mailbox.drain(at: 12)
        precondition(snapshot.pressed == GoldenEyeN64Buttons.a.rawValue)

        for _ in 0..<(GoldenEyeInputMailbox.capacity + 1) {
            mailbox.enqueueKeyboard(keyCode: 0x0D, isDown: true)
        }
        snapshot = mailbox.drain()
        precondition(snapshot.sourceFlags & GoldenEyeInputSourceFlags.queueOverflowed.rawValue != 0)

        mailbox.enqueueFocusLost(timestampNanoseconds: 20)
        _ = mailbox.drain(at: 20)
        mailbox.enqueueFocusGained(timestampNanoseconds: 21)
        _ = mailbox.drain(at: 21)
        mailbox.enqueueController(controllerID: 1, buttons: [], stickX: 0, stickY: 0, timestampNanoseconds: 22)
        _ = mailbox.drain(at: 22)
        mailbox.enqueueKeyboard(keyCode: 0x24, isDown: true, timestampNanoseconds: 100)
        snapshot = mailbox.drain(at: 50)
        precondition(snapshot.pressed == 0 && snapshot.held == 0)
        snapshot = mailbox.drain(at: 100)
        precondition(snapshot.pressed == GoldenEyeN64Buttons.start.rawValue)
        mailbox.enqueueKeyboard(keyCode: 0x24, isDown: false, timestampNanoseconds: 101)
        snapshot = mailbox.drain(at: 200)
        precondition(snapshot.released == GoldenEyeN64Buttons.start.rawValue)
        precondition(snapshot.held == 0)

        print("goldeneye_native_input_mailbox_smoke: PASS")
    }
}
