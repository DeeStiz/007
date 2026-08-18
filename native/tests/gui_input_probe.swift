import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2, let pidValue = Int32(CommandLine.arguments[1]) else {
    fputs("usage: gui_input_probe <pid>\n", stderr)
    exit(2)
}

let pid = pidValue
func postKey(_ keyCode: CGKeyCode, down: Bool) {
    guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down) else {
        fputs("could not create keyboard event\n", stderr)
        exit(3)
    }
    // Post through the HID tap after activating the target. This exercises
    // AppKit's normal responder path rather than calling the view directly.
    event.post(tap: .cghidEventTap)
}

postKey(0x0D, down: true) // W
usleep(120_000)
postKey(0x0D, down: false)
usleep(120_000)

let target = NSRunningApplication(processIdentifier: pid)
_ = target?.hide()
usleep(180_000)
_ = target?.activate(options: [.activateAllWindows])
print("gui_input_probe: posted keyDown/keyUp and hide/activate focus transition")
