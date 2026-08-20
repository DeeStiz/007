import Foundation
import Darwin

#if canImport(GameController)
import GameController
#endif

/// The button vocabulary used at the native C/Swift boundary.
///
/// These values are deliberately independent of Apple's controller element
/// names and of the legacy `GEInputSnapshotV1` fixture.  The owner thread can
/// copy the raw value into the eventual V5 input record without carrying an
/// Objective-C object or a pointer across the boundary.
public struct GoldenEyeN64Buttons: OptionSet, Sendable, Equatable, Hashable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let a = Self(rawValue: 1 << 0)
    public static let b = Self(rawValue: 1 << 1)
    public static let z = Self(rawValue: 1 << 2)
    public static let start = Self(rawValue: 1 << 3)
    public static let dpadUp = Self(rawValue: 1 << 4)
    public static let dpadDown = Self(rawValue: 1 << 5)
    public static let dpadLeft = Self(rawValue: 1 << 6)
    public static let dpadRight = Self(rawValue: 1 << 7)
    public static let cUp = Self(rawValue: 1 << 8)
    public static let cDown = Self(rawValue: 1 << 9)
    public static let cLeft = Self(rawValue: 1 << 10)
    public static let cRight = Self(rawValue: 1 << 11)
    public static let leftShoulder = Self(rawValue: 1 << 12)
    public static let rightShoulder = Self(rawValue: 1 << 13)
}

public struct GoldenEyeInputSourceFlags: OptionSet, Sendable, Equatable, Hashable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let keyboard = Self(rawValue: 1 << 0)
    public static let controller = Self(rawValue: 1 << 1)
    public static let focused = Self(rawValue: 1 << 2)
    public static let controllerConnected = Self(rawValue: 1 << 3)
    public static let edgeSuppressed = Self(rawValue: 1 << 4)
    public static let queueOverflowed = Self(rawValue: 1 << 5)
}

public enum GoldenEyeInputEventKind: UInt8, Sendable, Equatable {
    case keyboard = 1
    case controller = 2
    case focusLost = 3
    case focusGained = 4
    case controllerDisconnected = 5
}

public enum GoldenEyeInputSource: UInt8, Sendable, Equatable {
    case keyboard = 1
    case controller = 2
    case system = 3
}

/// A fixed-width value copied into the mailbox.  `controlMask` is used for
/// keyboard controls so opposing keys can be resolved deterministically after
/// every queued event has been applied.
public struct GoldenEyeRawInputEvent: Sendable, Equatable {
    public let timestampNanoseconds: UInt64
    public let sequence: UInt64
    public let kind: GoldenEyeInputEventKind
    public let source: GoldenEyeInputSource
    public let controllerID: UInt32
    public let controlMask: UInt16
    public let isDown: Bool
    public let buttons: UInt32
    public let stickX: Int16
    public let stickY: Int16
    public let z: Int16
    /// Controller events are sampled for every connected device, but only the
    /// framework's current controller is authoritative for single-player
    /// aggregate state.
    public let controllerIsActive: Bool

    public init(
        timestampNanoseconds: UInt64,
        sequence: UInt64 = 0,
        kind: GoldenEyeInputEventKind,
        source: GoldenEyeInputSource,
        controllerID: UInt32 = 0,
        controlMask: UInt16 = 0,
        isDown: Bool = false,
        buttons: UInt32 = 0,
        stickX: Int16 = 0,
        stickY: Int16 = 0,
        z: Int16 = 0,
        controllerIsActive: Bool = true
    ) {
        self.timestampNanoseconds = timestampNanoseconds
        self.sequence = sequence
        self.kind = kind
        self.source = source
        self.controllerID = controllerID
        self.controlMask = controlMask
        self.isDown = isDown
        self.buttons = buttons
        self.stickX = stickX
        self.stickY = stickY
        self.z = z
        self.controllerIsActive = controllerIsActive
    }

    fileprivate func assigning(sequence: UInt64) -> Self {
        Self(
            timestampNanoseconds: timestampNanoseconds,
            sequence: sequence,
            kind: kind,
            source: source,
            controllerID: controllerID,
            controlMask: controlMask,
            isDown: isDown,
            buttons: buttons,
            stickX: stickX,
            stickY: stickY,
            z: z,
            controllerIsActive: controllerIsActive
        )
    }
}

/// Immutable input handed to one native tick.  Axes use the source-friendly
/// -80...80 range; GameController's own deadzone and saturation are respected
/// and no second deadzone is applied here.
public struct GoldenEyeInputSnapshot: Sendable, Equatable {
    public let timestampNanoseconds: UInt64
    public let sequence: UInt64
    public let held: UInt32
    public let pressed: UInt32
    public let released: UInt32
    public let stickX: Int16
    public let stickY: Int16
    public let z: Int16
    /// Number of physically connected controllers observed by the host.  This
    /// is copied independently from the active controller's sampled state so
    /// Mode Select can expose multiplayer availability without carrying a
    /// `GCController` object across the owner boundary.
    public let controllerCount: UInt32
    public let sourceFlags: UInt32

    /// Explicit semantic alias used by the source owner. `controllerCount`
    /// remains the frozen copied field name; both denote physical devices.
    public var physicalControllerCount: UInt32 { controllerCount }

    public init(
        timestampNanoseconds: UInt64,
        sequence: UInt64,
        held: UInt32,
        pressed: UInt32,
        released: UInt32,
        stickX: Int16,
        stickY: Int16,
        z: Int16,
        sourceFlags: UInt32,
        controllerCount: UInt32 = 0
    ) {
        self.timestampNanoseconds = timestampNanoseconds
        self.sequence = sequence
        self.held = held
        self.pressed = pressed
        self.released = released
        self.stickX = stickX
        self.stickY = stickY
        self.z = z
        self.controllerCount = controllerCount
        self.sourceFlags = sourceFlags
    }
}

/// Keyboard control bits are intentionally separate from N64 buttons.  The
/// mailbox derives a stick vector from the four directional bits and resolves
/// simultaneous opposite directions to zero.
public struct GoldenEyeKeyboardControls: OptionSet, Sendable, Equatable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let up = Self(rawValue: 1 << 0)
    public static let down = Self(rawValue: 1 << 1)
    public static let left = Self(rawValue: 1 << 2)
    public static let right = Self(rawValue: 1 << 3)
    public static let confirm = Self(rawValue: 1 << 4)
    public static let cancel = Self(rawValue: 1 << 5)
    public static let z = Self(rawValue: 1 << 6)
}

public enum GoldenEyeInputMapping {
    public static let digitalAxisMagnitude: Int16 = 75
    public static let controllerAxisMagnitude: Int16 = 80

    /// Layout-independent macOS virtual key codes.  This keeps keyboard
    /// mapping independent from the user's selected keyboard layout.
    public static func keyboardMapping(for keyCode: UInt16) -> (GoldenEyeKeyboardControls, GoldenEyeN64Buttons)? {
        switch keyCode {
        case 0x0D, 0x7E: // W, Up
            return ([.up], [.dpadUp])
        case 0x01, 0x7D: // S, Down
            return ([.down], [.dpadDown])
        case 0x00, 0x7B: // A, Left
            return ([.left], [.dpadLeft])
        case 0x02, 0x7C: // D, Right
            return ([.right], [.dpadRight])
        case 0x24, 0x4C: // Return, keypad Enter -> Start
            return ([.confirm], [.start])
        case 0x31, 0x08: // Space, C -> A
            return ([.confirm], [.a])
        case 0x35, 0x33: // Escape, Delete/Backspace
            return ([.cancel], [.b])
        case 0x06, 0x0B: // Z, B fallback -> Z trigger
            return ([.z], [.z])
        default:
            return nil
        }
    }

    public static func digitalStick(for controls: GoldenEyeKeyboardControls) -> (x: Int16, y: Int16) {
        let x: Int16
        if controls.contains(.left) && !controls.contains(.right) {
            x = -digitalAxisMagnitude
        } else if controls.contains(.right) && !controls.contains(.left) {
            x = digitalAxisMagnitude
        } else {
            x = 0
        }

        let y: Int16
        if controls.contains(.up) && !controls.contains(.down) {
            y = digitalAxisMagnitude
        } else if controls.contains(.down) && !controls.contains(.up) {
            y = -digitalAxisMagnitude
        } else {
            y = 0
        }
        return (x, y)
    }

    /// GameController already applies the platform deadzone and saturation.
    /// This function only converts the normalized axis to the N64-friendly
    /// integer range and clamps malformed test values.
    public static func controllerAxis(_ value: Float) -> Int16 {
        let bounded = min(max(value, -1.0), 1.0)
        return Int16((bounded * Float(controllerAxisMagnitude)).rounded())
    }
}

/// A mailbox with a bounded, lock-protected event ring.  The lock is the sole
/// synchronization mechanism for this value-only channel: AppKit and
/// GameController producers may enqueue concurrently, while the native owner
/// thread drains it.  No Foundation or controller object is returned from the
/// mailbox, so its `@unchecked Sendable` invariant is limited to this lock and
/// the fixed-size storage.
public final class GoldenEyeInputMailbox: @unchecked Sendable {
    public static let capacity = 256

    private struct ControllerState: Sendable {
        var buttons: UInt32
        var stickX: Int16
        var stickY: Int16
        var z: Int16
    }

    private let lock = NSLock()
    private var events: [GoldenEyeRawInputEvent]
    private var readIndex = 0
    private var writeIndex = 0
    private var eventCount = 0
    private var sequence: UInt64 = 0
    private var overflowed = false

    private var keyboardControls: GoldenEyeKeyboardControls = []
    private var keyboardButtons: UInt32 = 0
    // Counts keep aliases such as Return/Space (both Confirm) independent:
    // releasing one key must not release the action while the other remains
    // held.  They also make opposing directional keys deterministic.
    private var keyboardControlCounts = [UInt16](repeating: 0, count: 16)
    private var keyboardButtonCounts = [UInt16](repeating: 0, count: 32)
    private var controllers: [UInt32: ControllerState] = [:]
    private var connectedControllerIDs: Set<UInt32> = []
    private var baselineControllerIDs: Set<UInt32> = []
    private var activeControllerID: UInt32?
    private var held: UInt32 = 0
    private var stickX: Int16 = 0
    private var stickY: Int16 = 0
    private var z: Int16 = 0
    private var pendingPressed: UInt32 = 0
    private var pendingReleased: UInt32 = 0
    private var focused = true
    private var suppressEdgesUntilNeutral = false
    private var controllerBaselinePending = false
    private var suppressionRequiresAllNeutral = false

    public init() {
        let empty = GoldenEyeRawInputEvent(
            timestampNanoseconds: 0,
            kind: .focusGained,
            source: .system
        )
        events = Array(repeating: empty, count: Self.capacity)
    }

    public var hasPendingEvents: Bool {
        lock.lock()
        defer { lock.unlock() }
        return eventCount != 0
    }

    /// Publish the framework's current-controller choice before the next
    /// owner-thread drain.  The ID is value-only and may be absent while the
    /// framework is between current-controller notifications.
    public func setActiveController(controllerID: UInt32?) {
        lock.lock()
        activeControllerID = controllerID
        recomputeAggregate()
        lock.unlock()
    }

    /// Register physical presence independently of sampled input.  This lets
    /// a copied snapshot report connected-controller count even when a newly
    /// attached controller has not emitted its first immutable state yet.
    public func markControllerConnected(controllerID: UInt32) {
        lock.lock()
        if connectedControllerIDs.insert(controllerID).inserted {
            if !suppressEdgesUntilNeutral {
                suppressEdgesUntilNeutral = true
                controllerBaselinePending = true
                suppressionRequiresAllNeutral = false
            }
            baselineControllerIDs.insert(controllerID)
        }
        lock.unlock()
    }

    public func markControllerDisconnected(controllerID: UInt32) {
        lock.lock()
        connectedControllerIDs.remove(controllerID)
        baselineControllerIDs.remove(controllerID)
        controllers.removeValue(forKey: controllerID)
        if activeControllerID == controllerID {
            activeControllerID = controllers.keys.sorted().last
        }
        recomputeAggregate()
        lock.unlock()
    }

    public func enqueueKeyboard(
        keyCode: UInt16,
        isDown: Bool,
        isRepeat: Bool = false,
        timestampNanoseconds: UInt64 = GoldenEyeMonotonicClock.nowNanoseconds()
    ) {
        guard let (controls, buttons) = GoldenEyeInputMapping.keyboardMapping(for: keyCode) else {
            return
        }
        // AppKit repeats do not produce new edges.  A key-up is always kept so
        // a held key cannot become stuck after a repeat sequence.
        if isRepeat && isDown {
            return
        }
        let event = GoldenEyeRawInputEvent(
            timestampNanoseconds: timestampNanoseconds,
            kind: .keyboard,
            source: .keyboard,
            controlMask: controls.rawValue,
            isDown: isDown,
            buttons: buttons.rawValue,
            stickX: 0,
            stickY: 0,
            z: 0
        )
        enqueue(event)
    }

    public func enqueueController(
        controllerID: UInt32,
        buttons: GoldenEyeN64Buttons,
        stickX: Int16,
        stickY: Int16,
        z: Int16 = 0,
        active: Bool = true,
        timestampNanoseconds: UInt64 = GoldenEyeMonotonicClock.nowNanoseconds()
    ) {
        let event = GoldenEyeRawInputEvent(
            timestampNanoseconds: timestampNanoseconds,
            kind: .controller,
            source: .controller,
            controllerID: controllerID,
            buttons: buttons.rawValue,
            stickX: Self.clampAxis(stickX),
            stickY: Self.clampAxis(stickY),
            z: Self.clampAxis(z),
            controllerIsActive: active
        )
        enqueue(event)
    }

    public func enqueueFocusLost(timestampNanoseconds: UInt64 = GoldenEyeMonotonicClock.nowNanoseconds()) {
        enqueue(GoldenEyeRawInputEvent(timestampNanoseconds: timestampNanoseconds, kind: .focusLost, source: .system))
    }

    public func enqueueFocusGained(timestampNanoseconds: UInt64 = GoldenEyeMonotonicClock.nowNanoseconds()) {
        enqueue(GoldenEyeRawInputEvent(timestampNanoseconds: timestampNanoseconds, kind: .focusGained, source: .system))
    }

    public func enqueueControllerDisconnected(
        controllerID: UInt32,
        timestampNanoseconds: UInt64 = GoldenEyeMonotonicClock.nowNanoseconds()
    ) {
        enqueue(
            GoldenEyeRawInputEvent(
                timestampNanoseconds: timestampNanoseconds,
                kind: .controllerDisconnected,
                source: .controller,
                controllerID: controllerID
            )
        )
    }

    /// Drain all states available at the start of a native tick.  A producer
    /// that arrives after the drain belongs to the following tick, preserving
    /// deterministic once-only edge consumption.
    public func drain(at timestampNanoseconds: UInt64 = GoldenEyeMonotonicClock.nowNanoseconds()) -> GoldenEyeInputSnapshot {
        lock.lock()
        var drained: [GoldenEyeRawInputEvent] = []
        drained.reserveCapacity(eventCount)
        while eventCount > 0 {
            let event = events[readIndex]
            // Do not consume an AppKit/controller event that arrived after
            // this authoritative tick's raw-clock deadline. It remains at
            // the head of the bounded ring for the next tick, preserving
            // deterministic edge ownership at 120 Hz.
            guard event.timestampNanoseconds <= timestampNanoseconds else { break }
            drained.append(event)
            readIndex = (readIndex + 1) % Self.capacity
            eventCount -= 1
        }
        let didOverflow = overflowed
        overflowed = false
        var pressed = pendingPressed
        var released = pendingReleased
        pendingPressed = 0
        pendingReleased = 0
        for event in drained {
            apply(event: event)
        }
        pressed |= pendingPressed
        released |= pendingReleased
        pendingPressed = 0
        pendingReleased = 0
        let sequence = self.sequence
        let sourceFlags = makeSourceFlags(queueOverflowed: didOverflow)
        // Count physical devices, not merely devices that have produced a
        // state in this tick.  The N64 source consumes at most four, but the
        // copied host snapshot retains the physical count for availability
        // decisions and diagnostics.
        let controllerCount = UInt32(connectedControllerIDs.count)
        let snapshot = GoldenEyeInputSnapshot(
            timestampNanoseconds: max(timestampNanoseconds, drained.last?.timestampNanoseconds ?? timestampNanoseconds),
            sequence: sequence,
            held: held,
            pressed: pressed,
            released: released,
            stickX: stickX,
            stickY: stickY,
            z: z,
            sourceFlags: sourceFlags.rawValue,
            controllerCount: controllerCount
        )
        lock.unlock()
        return snapshot
    }

    /// Clear all held state after AppKit focus loss.  It is safe to call this
    /// synchronously from the main actor; the owner receives the reset as a
    /// normal event on its next drain.
    public func reset() {
        enqueueFocusLost()
    }

    private func enqueue(_ event: GoldenEyeRawInputEvent) {
        lock.lock()
        defer { lock.unlock() }
        sequence &+= 1
        let sequenced = event.assigning(sequence: sequence)
        if eventCount == Self.capacity {
            readIndex = (readIndex + 1) % Self.capacity
            eventCount -= 1
            overflowed = true
        }
        events[writeIndex] = sequenced
        writeIndex = (writeIndex + 1) % Self.capacity
        eventCount += 1
    }

    private func apply(event: GoldenEyeRawInputEvent) {
        switch event.kind {
        case .focusLost:
            focused = false
            keyboardControls = []
            keyboardButtons = 0
            keyboardControlCounts = [UInt16](repeating: 0, count: keyboardControlCounts.count)
            keyboardButtonCounts = [UInt16](repeating: 0, count: keyboardButtonCounts.count)
            controllers.removeAll(keepingCapacity: true)
            baselineControllerIDs.removeAll(keepingCapacity: true)
            held = 0
            stickX = 0
            stickY = 0
            z = 0
            pendingPressed = 0
            pendingReleased = 0
            suppressEdgesUntilNeutral = true
            controllerBaselinePending = false
            suppressionRequiresAllNeutral = true

        case .focusGained:
            focused = true

        case .keyboard:
            guard focused else { return }
            incrementKeyboardCounts(
                controls: GoldenEyeKeyboardControls(rawValue: event.controlMask),
                buttons: GoldenEyeN64Buttons(rawValue: event.buttons),
                isDown: event.isDown
            )
            recomputeAggregate()

        case .controller:
            if connectedControllerIDs.insert(event.controllerID).inserted {
                if !suppressEdgesUntilNeutral {
                    suppressEdgesUntilNeutral = true
                    controllerBaselinePending = true
                    suppressionRequiresAllNeutral = false
                }
                baselineControllerIDs.insert(event.controllerID)
            }
            if event.controllerIsActive {
                activeControllerID = event.controllerID
            }
            guard focused else { return }
            controllers[event.controllerID] = ControllerState(
                buttons: event.buttons,
                stickX: Self.clampAxis(event.stickX),
                stickY: Self.clampAxis(event.stickY),
                z: Self.clampAxis(event.z)
            )
            if event.buttons == 0 && event.stickX == 0 && event.stickY == 0 && event.z == 0 {
                baselineControllerIDs.remove(event.controllerID)
            }
            recomputeAggregate()

        case .controllerDisconnected:
            connectedControllerIDs.remove(event.controllerID)
            baselineControllerIDs.remove(event.controllerID)
            controllers.removeValue(forKey: event.controllerID)
            if activeControllerID == event.controllerID {
                activeControllerID = controllers.keys.sorted().last
            }
            // A disconnect is treated like focus loss for deterministic edge
            // behavior: stale held buttons never become a new press on
            // reconnect.  The next neutral sample clears the suppression.
            keyboardControls = []
            keyboardButtons = 0
            keyboardControlCounts = [UInt16](repeating: 0, count: keyboardControlCounts.count)
            keyboardButtonCounts = [UInt16](repeating: 0, count: keyboardButtonCounts.count)
            controllers.removeAll(keepingCapacity: true)
            baselineControllerIDs.removeAll(keepingCapacity: true)
            activeControllerID = nil
            held = 0
            stickX = 0
            stickY = 0
            z = 0
            pendingPressed = 0
            pendingReleased = 0
            suppressEdgesUntilNeutral = true
            controllerBaselinePending = false
            suppressionRequiresAllNeutral = true
        }
    }

    private func incrementKeyboardCounts(
        controls: GoldenEyeKeyboardControls,
        buttons: GoldenEyeN64Buttons,
        isDown: Bool
    ) {
        let controlBits = UInt32(controls.rawValue)
        for bit in 0..<keyboardControlCounts.count where controlBits & (UInt32(1) << bit) != 0 {
            if isDown {
                keyboardControlCounts[bit] = keyboardControlCounts[bit] == .max
                    ? .max
                    : keyboardControlCounts[bit] &+ 1
            } else if keyboardControlCounts[bit] != 0 {
                keyboardControlCounts[bit] &-= 1
            }
        }

        let buttonBits = buttons.rawValue
        for bit in 0..<keyboardButtonCounts.count where buttonBits & (UInt32(1) << bit) != 0 {
            if isDown {
                keyboardButtonCounts[bit] = keyboardButtonCounts[bit] == .max
                    ? .max
                    : keyboardButtonCounts[bit] &+ 1
            } else if keyboardButtonCounts[bit] != 0 {
                keyboardButtonCounts[bit] &-= 1
            }
        }

        var nextControls: GoldenEyeKeyboardControls = []
        for bit in 0..<keyboardControlCounts.count where keyboardControlCounts[bit] != 0 {
            nextControls.insert(GoldenEyeKeyboardControls(rawValue: UInt16(1) << bit))
        }
        keyboardControls = nextControls

        var nextButtons: UInt32 = 0
        for bit in 0..<keyboardButtonCounts.count where keyboardButtonCounts[bit] != 0 {
            nextButtons |= UInt32(1) << bit
        }
        keyboardButtons = nextButtons
    }

    private func recomputeAggregate() {
        // GameController.current is the single-player authority.  Other
        // connected devices remain represented in `controllerCount`, but
        // their buttons do not leak into the active controller's input.
        let active = activeControllerID.flatMap { controllers[$0] }
        let controllerButtons = active?.buttons ?? 0
        let newHeld = keyboardButtons | controllerButtons
        let oldHeld = held
        let newPressed = newHeld & ~oldHeld
        let newReleased = oldHeld & ~newHeld
        held = newHeld

        let digital = GoldenEyeInputMapping.digitalStick(for: keyboardControls)
        let controllerX = active?.stickX ?? 0
        let controllerY = active?.stickY ?? 0
        let controllerZ = active?.z ?? 0
        // Merge each axis independently by magnitude.  This preserves a
        // +/-75 keyboard direction when a controller reports a smaller
        // analog value, while a full +/-80 analog value wins naturally.
        stickX = Self.largerMagnitude(controllerX, digital.x)
        stickY = Self.largerMagnitude(controllerY, digital.y)
        z = Self.largerMagnitude(
            controllerZ,
            keyboardControls.contains(.z) ? GoldenEyeInputMapping.digitalAxisMagnitude : 0
        )

        if suppressEdgesUntilNeutral {
            let neutral = suppressionRequiresAllNeutral
                ? newHeld == 0 && keyboardControls.isEmpty && stickX == 0 && stickY == 0 && z == 0
                : controllerBaselinePending && baselineControllerIDs.isEmpty
            if neutral {
                suppressEdgesUntilNeutral = false
                controllerBaselinePending = false
                suppressionRequiresAllNeutral = false
            }
        } else {
            pendingPressed |= newPressed
            pendingReleased |= newReleased
        }
    }

    private func makeSourceFlags(queueOverflowed: Bool) -> GoldenEyeInputSourceFlags {
        var flags: GoldenEyeInputSourceFlags = []
        if keyboardButtons != 0 || !keyboardControls.isEmpty {
            flags.insert(.keyboard)
        }
        if !connectedControllerIDs.isEmpty {
            flags.insert(.controller)
            flags.insert(.controllerConnected)
        }
        if focused {
            flags.insert(.focused)
        }
        if suppressEdgesUntilNeutral {
            flags.insert(.edgeSuppressed)
        }
        if queueOverflowed {
            flags.insert(.queueOverflowed)
        }
        return flags
    }

    private static func clampAxis(_ value: Int16) -> Int16 {
        min(max(value, -GoldenEyeInputMapping.controllerAxisMagnitude), GoldenEyeInputMapping.controllerAxisMagnitude)
    }

    private static func largerMagnitude(_ lhs: Int16, _ rhs: Int16) -> Int16 {
        abs(lhs) >= abs(rhs) ? lhs : rhs
    }
}

public enum GoldenEyeMonotonicClock {
    public static func nowNanoseconds() -> UInt64 {
        var time = timespec()
        guard clock_gettime(CLOCK_MONOTONIC_RAW, &time) == 0 else {
            return UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000_000.0)
        }
        return UInt64(time.tv_sec) &* 1_000_000_000 &+ UInt64(time.tv_nsec)
    }
}

#if canImport(GameController)

/// Bridges Apple's modern buffered polling API into the value-only mailbox.
/// `poll()` belongs on the native owner thread.  Connection notifications are
/// only used to attach/detach the framework objects; no controller object is
/// retained by the mailbox or passed into C.
public final class GoldenEyeGameControllerAdapter: @unchecked Sendable {
    public static let inputStateQueueDepth = 20

    private let mailbox: GoldenEyeInputMailbox
    private let notificationCenter: NotificationCenter
    private let lock = NSLock()
    private var controllers: [ObjectIdentifier: (controller: GCController, id: UInt32)] = [:]
    private var nextID: UInt32 = 1
    private var currentControllerID: UInt32?
    private var observers: [NSObjectProtocol] = []
    private var gcBaseTimestamp: TimeInterval?
    private var rawBaseTimestamp: UInt64?

    public init(mailbox: GoldenEyeInputMailbox, notificationCenter: NotificationCenter = .default) {
        self.mailbox = mailbox
        self.notificationCenter = notificationCenter
        observers.append(
            notificationCenter.addObserver(
                forName: .GCControllerDidConnect,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                guard let controller = notification.object as? GCController else { return }
                self?.attach(controller)
            }
        )
        observers.append(
            notificationCenter.addObserver(
                forName: .GCControllerDidDisconnect,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                guard let controller = notification.object as? GCController else { return }
                self?.detach(controller)
            }
        )
        observers.append(
            notificationCenter.addObserver(
                forName: .GCControllerDidBecomeCurrent,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                guard let controller = notification.object as? GCController else { return }
                self?.setCurrent(controller)
            }
        )
        observers.append(
            notificationCenter.addObserver(
                forName: .GCControllerDidStopBeingCurrent,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                guard let controller = notification.object as? GCController else { return }
                self?.clearCurrent(controller)
            }
        )
        for controller in GCController.controllers() {
            attach(controller)
        }
        if let current = GCController.current {
            setCurrent(current)
        }
    }

    deinit {
        stop()
    }

    public func stop() {
        lock.lock()
        let currentObservers = observers
        observers.removeAll()
        let currentControllers = Array(controllers.values)
        controllers.removeAll()
        currentControllerID = nil
        lock.unlock()

        for observer in currentObservers {
            notificationCenter.removeObserver(observer)
        }
        for value in currentControllers {
            mailbox.markControllerDisconnected(controllerID: value.id)
        }
    }

    /// Drain each controller's immutable buffered state queue.  The queue
    /// depth is configured to 20 on connection, matching Apple's recommended
    /// margin for a 120 Hz owner loop.
    public func poll() {
        lock.lock()
        let currentControllers = Array(controllers.values)
        let currentID = currentControllerID
        let frameworkCurrent = GCController.current.map(ObjectIdentifier.init)
        let frameworkCurrentID = frameworkCurrent.flatMap { objectID in
            controllers[objectID]?.id
        }
        let effectiveCurrentID = frameworkCurrentID ?? currentID
        lock.unlock()

        // Stable ID order keeps simultaneous buffered states deterministic;
        // `active` still follows GameController.current for single-player
        // aggregation.
        for value in currentControllers.sorted(by: { $0.id < $1.id }) {
            let input = value.controller.input
            while let state = input.nextInputState() {
                let sample = sample(state: state)
                mailbox.enqueueController(
                    controllerID: value.id,
                    buttons: sample.buttons,
                    stickX: sample.stickX,
                    stickY: sample.stickY,
                    z: sample.z,
                    active: value.id == effectiveCurrentID,
                    timestampNanoseconds: timestamp(for: state.lastEventTimestamp)
                )
            }
        }
        mailbox.setActiveController(controllerID: effectiveCurrentID)
    }

    private func attach(_ controller: GCController) {
        let key = ObjectIdentifier(controller)
        lock.lock()
        if controllers[key] != nil {
            lock.unlock()
            return
        }
        let id = nextID
        nextID &+= 1
        controllers[key] = (controller, id)
        lock.unlock()
        mailbox.markControllerConnected(controllerID: id)

        // Apple posts current/connect notifications in a defined sequence,
        // but a custom notification center or a launch-time already-connected
        // controller can make the current notification arrive before the
        // adapter has installed its ID map.
        if GCController.current === controller {
            setCurrent(controller)
        }

        let input = controller.input
        input.inputStateQueueDepth = Self.inputStateQueueDepth
    }

    private func detach(_ controller: GCController) {
        let key = ObjectIdentifier(controller)
        lock.lock()
        let value = controllers.removeValue(forKey: key)
        lock.unlock()
        guard let value else { return }
        mailbox.enqueueControllerDisconnected(controllerID: value.id)
    }

    private func setCurrent(_ controller: GCController) {
        let key = ObjectIdentifier(controller)
        lock.lock()
        let id = controllers[key]?.id
        currentControllerID = id
        lock.unlock()
        mailbox.setActiveController(controllerID: id)
    }

    private func clearCurrent(_ controller: GCController) {
        let key = ObjectIdentifier(controller)
        lock.lock()
        if controllers[key]?.id == currentControllerID {
            currentControllerID = nil
        }
        let id = currentControllerID
        lock.unlock()
        mailbox.setActiveController(controllerID: id)
    }

    private func timestamp(for gameControllerTimestamp: TimeInterval) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        let now = GoldenEyeMonotonicClock.nowNanoseconds()
        guard gameControllerTimestamp.isFinite, gameControllerTimestamp >= 0 else {
            return now
        }
        guard let base = gcBaseTimestamp, let rawBase = rawBaseTimestamp else {
            gcBaseTimestamp = gameControllerTimestamp
            rawBaseTimestamp = now
            return now
        }
        let delta = gameControllerTimestamp - base
        if delta <= 0 {
            return rawBase
        }
        let scaledDelta = delta * 1_000_000_000.0
        guard scaledDelta.isFinite, scaledDelta < Double(UInt64.max) else {
            return now
        }
        let deltaNanoseconds = UInt64(scaledDelta)
        return rawBase &+ deltaNanoseconds
    }

    private func sample(state: GCControllerInputState) -> (buttons: GoldenEyeN64Buttons, stickX: Int16, stickY: Int16, z: Int16) {
        var buttons: GoldenEyeN64Buttons = []
        if state.buttons[.a]?.pressedInput.isPressed == true {
            buttons.insert(.a)
        }
        if state.buttons[.b]?.pressedInput.isPressed == true {
            buttons.insert(.b)
        }
        if state.buttons[.menu]?.pressedInput.isPressed == true || state.buttons[.options]?.pressedInput.isPressed == true {
            buttons.insert(.start)
        }
        // Either trigger can serve as a confirm action on controllers whose
        // face buttons are hard to identify; the left trigger is the native Z
        // mapping and the right trigger is an additional A mapping.
        if state.buttons[.rightTrigger]?.pressedInput.isPressed == true {
            buttons.insert(.a)
        }
        if state.buttons[.leftTrigger]?.pressedInput.isPressed == true {
            buttons.insert(.z)
        }

        if state.buttons[.leftShoulder]?.pressedInput.isPressed == true {
            buttons.insert(.leftShoulder)
        }
        if state.buttons[.rightShoulder]?.pressedInput.isPressed == true {
            buttons.insert(.rightShoulder)
        }

        // A physical d-pad is four independent inputs.  Reading those press
        // states preserves simultaneous opposing directions; deriving buttons
        // from x/y would incorrectly collapse that case.  Its axis is a
        // digital +/-75 contribution, not an analog +/-80 contribution.
        var dpadX: Int16 = 0
        var dpadY: Int16 = 0
        if let dpad = state.dpads[.directionPad] {
            let up = dpad.up.isPressed
            let down = dpad.down.isPressed
            let left = dpad.left.isPressed
            let right = dpad.right.isPressed
            if up { buttons.insert(.dpadUp) }
            if down { buttons.insert(.dpadDown) }
            if left { buttons.insert(.dpadLeft) }
            if right { buttons.insert(.dpadRight) }
            if left && !right { dpadX = -GoldenEyeInputMapping.digitalAxisMagnitude }
            if right && !left { dpadX = GoldenEyeInputMapping.digitalAxisMagnitude }
            if down && !up { dpadY = -GoldenEyeInputMapping.digitalAxisMagnitude }
            if up && !down { dpadY = GoldenEyeInputMapping.digitalAxisMagnitude }
        }

        // The left thumbstick remains analog.  GameController has already
        // applied its device deadzone and saturation, so this is only the
        // normalized-to-N64 conversion.
        let analogDpad = state.dpads[.leftThumbstick]
        let analogX = analogDpad.map { GoldenEyeInputMapping.controllerAxis($0.xAxis.value) } ?? 0
        let analogY = analogDpad.map { GoldenEyeInputMapping.controllerAxis($0.yAxis.value) } ?? 0
        let x = abs(analogX) >= abs(dpadX) ? analogX : dpadX
        let y = abs(analogY) >= abs(dpadY) ? analogY : dpadY

        // Map the right stick's individual directions to the N64 C buttons;
        // its analog magnitude is not part of the source-facing left-stick
        // axis record.
        if let cPad = state.dpads[.rightThumbstick] {
            if cPad.up.isPressed { buttons.insert(.cUp) }
            if cPad.down.isPressed { buttons.insert(.cDown) }
            if cPad.left.isPressed { buttons.insert(.cLeft) }
            if cPad.right.isPressed { buttons.insert(.cRight) }
        }
        let z: Int16 = buttons.contains(.z) ? GoldenEyeInputMapping.controllerAxisMagnitude : 0
        return (buttons, x, y, z)
    }
}

#else

/// Compile-time fallback for non-Apple host tooling.  The package target is
/// macOS-only, but keeping this API available lets pure mailbox tests build on
/// a Linux CI worker without importing GameController.
public final class GoldenEyeGameControllerAdapter: @unchecked Sendable {
    public static let inputStateQueueDepth = 20

    public init(mailbox: GoldenEyeInputMailbox) {}
    public func poll() {}
    public func stop() {}
}

#endif
