struct GoldenEyeKeyboardSnapshot: Equatable {
    let sequence: UInt64
    let held: UInt32
    let pressed: UInt32
    let released: UInt32
}

struct GoldenEyeKeyboardInputState {
    private(set) var held: UInt32 = 0
    private(set) var pendingPressed: UInt32 = 0
    private(set) var pendingReleased: UInt32 = 0
    private var sequence: UInt64 = 0

    mutating func keyDown(keyCode: UInt16, isRepeat: Bool) {
        guard let mask = Self.mask(for: keyCode) else { return }
        if !isRepeat && (held & mask) == 0 {
            pendingPressed |= mask
        }
        held |= mask
    }

    mutating func keyUp(keyCode: UInt16) {
        guard let mask = Self.mask(for: keyCode) else { return }
        if (held & mask) != 0 {
            pendingReleased |= mask
        }
        held &= ~mask
    }

    mutating func flagsChanged(keyCode: UInt16, isDown: Bool) {
        if isDown {
            keyDown(keyCode: keyCode, isRepeat: false)
        } else {
            keyUp(keyCode: keyCode)
        }
    }

    mutating func snapshot() -> GoldenEyeKeyboardSnapshot {
        sequence &+= 1
        let snapshot = GoldenEyeKeyboardSnapshot(
            sequence: sequence,
            held: held,
            pressed: pendingPressed,
            released: pendingReleased
        )
        pendingPressed = 0
        pendingReleased = 0
        return snapshot
    }

    mutating func reset() {
        held = 0
        pendingPressed = 0
        pendingReleased = 0
    }

    static func mask(for keyCode: UInt16) -> UInt32? {
        // macOS virtual-key codes are layout-independent HID usages. Keep the
        // M3 fixture bounded; the full GoldenEye key map belongs to a later
        // input milestone.
        let index: UInt32?
        switch keyCode {
        case 0x00: index = 0 // A
        case 0x01: index = 1 // S
        case 0x02: index = 2 // D
        case 0x0D: index = 3 // W
        case 0x31: index = 4 // Space
        case 0x35: index = 5 // Escape
        case 0x7B: index = 6 // Left arrow
        case 0x7C: index = 7 // Right arrow
        case 0x7D: index = 8 // Down arrow
        case 0x7E: index = 9 // Up arrow
        case 0x37: index = 10 // Command
        case 0x38: index = 11 // Shift
        case 0x39: index = 12 // Caps Lock
        case 0x3A: index = 13 // Option
        case 0x3B: index = 14 // Control
        default: index = nil
        }
        guard let index else { return nil }
        return UInt32(1) << index
    }
}
