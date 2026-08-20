import Foundation

#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

/// The normalized input consumed by the source File Select/Mode Select
/// authority.  Axes use the N64 range [-80, 80]; a keyboard or d-pad adapter
/// should submit +/-75, matching the source dead-zone and cursor velocity.
public struct GoldenEyeFileModeInputV6: Sendable, Equatable {
    public var held: UInt32
    public var pressed: UInt32
    public var released: UInt32
    public var stickX: Int16
    public var stickY: Int16
    public var controllerCount: UInt32
    public var clockTimer: UInt32
    public var nativeTick: UInt64
    public var sequence: UInt64
    public var focused: Bool
    public var controllerConnected: Bool
    public var synthetic: Bool

    public init(
        nativeTick: UInt64,
        sequence: UInt64,
        held: UInt32 = 0,
        pressed: UInt32 = 0,
        released: UInt32 = 0,
        stickX: Int16 = 0,
        stickY: Int16 = 0,
        controllerCount: UInt32 = 1,
        clockTimer: UInt32 = 1,
        focused: Bool = true,
        controllerConnected: Bool = true,
        synthetic: Bool = false
    ) {
        self.nativeTick = nativeTick
        self.sequence = sequence
        self.held = held
        self.pressed = pressed
        self.released = released
        self.stickX = stickX
        self.stickY = stickY
        self.controllerCount = controllerCount
        self.clockTimer = clockTimer
        self.focused = focused
        self.controllerConnected = controllerConnected
        self.synthetic = synthetic
    }
}

public struct GoldenEyeFileModeStateSnapshotV6: Sendable, Equatable {
    public let screen: UInt32
    public let flags: UInt32
    public let fileOption: UInt32
    public let eraseChoice: UInt32
    public let selectedFolder: UInt32
    public let hoveredFolder: UInt32
    public let modeSelection: UInt32
    public let controllerCount: UInt32
    public let idleTimer: UInt32
    public let cursorXQ16: Int32
    public let cursorYQ16: Int32
    public let nativeTick: UInt64
    public let referenceTick: UInt64
    public let eventSequence: UInt64
    public let route: UInt32

    init(_ value: GEFileModeStateV6) {
        screen = UInt32(value.screen)
        flags = UInt32(value.flags)
        fileOption = UInt32(value.file_option)
        eraseChoice = UInt32(value.erase_choice)
        selectedFolder = UInt32(value.selected_folder)
        hoveredFolder = UInt32(value.hovered_folder)
        modeSelection = UInt32(value.mode_selection)
        controllerCount = UInt32(value.controller_count)
        idleTimer = UInt32(value.idle_timer)
        cursorXQ16 = Int32(value.cursor_x_q16)
        cursorYQ16 = Int32(value.cursor_y_q16)
        nativeTick = UInt64(value.native_tick)
        referenceTick = UInt64(value.reference_tick)
        eventSequence = UInt64(value.event_sequence)
        route = UInt32(value.route)
    }
}

public struct GoldenEyeFileModeEventSnapshotV6: Sendable, Equatable {
    public let kind: UInt32
    public let screen: UInt32
    public let targetScreen: UInt32
    public let command: UInt32
    public let folder: UInt32
    public let destinationFolder: UInt32
    public let value0: UInt32
    public let value1: UInt32
    public let xQ16: Int32
    public let yQ16: Int32
    public let nativeTick: UInt64
    public let referenceTick: UInt64
    public let sequence: UInt64

    init(_ value: GEFileModeEventV6) {
        kind = UInt32(value.kind)
        screen = UInt32(value.screen)
        targetScreen = UInt32(value.target_screen)
        command = UInt32(value.command)
        folder = UInt32(value.folder)
        destinationFolder = UInt32(value.destination_folder)
        value0 = UInt32(value.value0)
        value1 = UInt32(value.value1)
        xQ16 = Int32(value.x_q16)
        yQ16 = Int32(value.y_q16)
        nativeTick = UInt64(value.native_tick)
        referenceTick = UInt64(value.reference_tick)
        sequence = UInt64(value.sequence)
    }
}

public struct GoldenEyeFileModeFrameV6: Sendable, Equatable {
    public let state: GoldenEyeFileModeStateSnapshotV6
    public let events: [GoldenEyeFileModeEventSnapshotV6]
    public let stateHash: UInt64
    public let eventHash: UInt64
    public var saveEvents: [GoldenEyeFileModeEventSnapshotV6] {
        events.filter { $0.kind == GE_FILE_MODE_V6_EVENT_SAVE.rawValue }
    }

    /// Source switch visibility is part of the immutable menu snapshot, not
    /// renderer state: File Select shows all four wallet instances while Mode
    /// Select shows the selected wallet's switch branch.
    public var walletSwitchMask: UInt32 {
        switch state.screen {
        case GE_FILE_MODE_V6_SCREEN_FILE_SELECT.rawValue:
            return 0x0f
        case GE_FILE_MODE_V6_SCREEN_MODE_SELECT.rawValue:
            return 1 << min(state.selectedFolder, 3)
        default:
            return 0
        }
    }

    /// Text packet selection is exposed as source semantic flags so the text
    /// renderer can consume it without reading a live C model or save pointer.
    public var textFlags: UInt32 {
        var result: UInt32 = 0
        if state.screen == GE_FILE_MODE_V6_SCREEN_FILE_SELECT.rawValue {
            result |= 1 << 0 // SELECT FILE/progress surface
            if state.fileOption == GE_FILE_MODE_V6_OPTION_COPY.rawValue { result |= 1 << 1 }
            if state.fileOption == GE_FILE_MODE_V6_OPTION_ERASE.rawValue { result |= 1 << 2 }
            if state.flags & GE_FILE_MODE_V6_STATE_FLAG_ERASE_CONFIRM != 0 { result |= 1 << 3 }
        } else if state.screen == GE_FILE_MODE_V6_SCREEN_MODE_SELECT.rawValue {
            result |= 1 << 4 // solo/multiplayer mode rows
            if state.flags & GE_FILE_MODE_V6_STATE_FLAG_MULTI_AVAILABLE != 0 { result |= 1 << 5 }
        }
        return result
    }

    /// Last semantic action in this immutable frame.  SFX events are kept
    /// separate so action persistence cannot be confused with presentation.
    public var lastAction: UInt32 {
        events.reversed().first(where: {
            $0.kind == GE_FILE_MODE_V6_EVENT_SAVE.rawValue ||
                $0.kind == GE_FILE_MODE_V6_EVENT_ROUTE.rawValue
        })?.command ?? 0
    }

    public var lastSFX: UInt32 {
        events.reversed().first(where: {
            $0.kind == GE_FILE_MODE_V6_EVENT_SFX.rawValue
        })?.command ?? 0
    }

    public var selectedProgressFolder: UInt32 { state.selectedFolder }

    init(_ value: GEFileModeFrameV6) {
        state = GoldenEyeFileModeStateSnapshotV6(value.state)
        stateHash = UInt64(value.state_hash)
        eventHash = UInt64(value.event_hash)
        let count = min(
            max(Int(value.event_count), 0),
            Int(GE_FILE_MODE_V6_MAX_EVENTS)
        )
        events = withUnsafeBytes(of: value.events) { rawBytes in
            Array(rawBytes.bindMemory(to: GEFileModeEventV6.self).prefix(count))
                .map(GoldenEyeFileModeEventSnapshotV6.init)
        }
    }
}

public enum GoldenEyeFileModeAuthorityV6Error: Error, Sendable, Equatable,
    CustomStringConvertible
{
    case cStatus(UInt32)
    case invalidSave

    public var description: String {
        switch self {
        case let .cStatus(status): return "File/Mode C status " + String(status)
        case .invalidSave: return "File/Mode save snapshot could not be represented"
        }
    }
}

/// Swift owns the copied semantic save and forwards persistence commands to
/// SaveStore; C owns all cursor, folder, confirmation, mode, and source-SFX
/// decisions.  The C state never stores a pointer or Swift object.
public struct GoldenEyeFileModeAuthorityV6: @unchecked Sendable {
    public private(set) var state: GEFileModeStateV6
    public private(set) var saveState: GoldenEyeSaveState
    public private(set) var lastFrame: GoldenEyeFileModeFrameV6

    // Private paired-cadence sidecar.  These copies are never part of the
    // frozen GEFileModeStateV6 ABI: a non-committed odd preview is rebased to
    // the last even source anchor before the next even step.  An odd-tick
    // pressed action is retained as the new anchor so it commits exactly once.
    private var pairedAnchorState: GEFileModeStateV6
    private var pairedAnchorSave: GoldenEyeSaveState
    private var oddActionCommitted = false

    public init(
        saveState: GoldenEyeSaveState = .blank,
        startingBeforeNativeTick: UInt64 = 0
    ) throws {
        guard let cSave = Self.makeCSave(saveState) else {
            throw GoldenEyeFileModeAuthorityV6Error.invalidSave
        }
        var mutableSave = cSave
        var cState = GEFileModeStateV6()
        var cFrame = GEFileModeFrameV6()
        let status = ge_file_mode_v6_init(&cState, &mutableSave, &cFrame)
        guard status == GE_STATUS_OK else {
            throw GoldenEyeFileModeAuthorityV6Error.cStatus(UInt32(status))
        }
        cState.native_tick = startingBeforeNativeTick
        cState.reference_tick = startingBeforeNativeTick / 2
        cState.last_input_sequence = startingBeforeNativeTick
        self.state = cState
        self.saveState = saveState
        self.lastFrame = GoldenEyeFileModeFrameV6(cFrame)
        self.pairedAnchorState = cState
        self.pairedAnchorSave = saveState
    }

    /// SaveStore remains the only wire-format owner.  This call replaces the
    /// copied semantic projection used on the next menu step and does not
    /// encode, write, or reinterpret the frozen 596-byte GESWSAVE file.
    public mutating func installSaveState(_ saveState: GoldenEyeSaveState) throws {
        guard Self.makeCSave(saveState) != nil else {
            throw GoldenEyeFileModeAuthorityV6Error.invalidSave
        }
        self.saveState = saveState
        self.pairedAnchorSave = saveState
        self.oddActionCommitted = false
    }

    @discardableResult
    public mutating func step(
        _ input: GoldenEyeFileModeInputV6
    ) throws -> GoldenEyeFileModeFrameV6 {
        guard var cSave = Self.makeCSave(saveState) else {
            throw GoldenEyeFileModeAuthorityV6Error.invalidSave
        }
        let isOddPreview = input.nativeTick & 1 == 1

        if !isOddPreview, !oddActionCommitted {
            // The preceding odd frame is only a visual half-step. Restore
            // the exact source anchor before executing this 60 Hz endpoint.
            state = pairedAnchorState
            saveState = pairedAnchorSave
            // C still owns the native timeline and requires sequential native
            // ticks. Rebase only the visual/menu fields; stamp the restored
            // source anchor as the immediately preceding odd tick so this
            // even call remains 6 after 5, not 6 after 4.
            state.native_tick = input.nativeTick - 1
            state.reference_tick = (input.nativeTick - 1) / 2
            guard let restoredSave = Self.makeCSave(saveState) else {
                throw GoldenEyeFileModeAuthorityV6Error.invalidSave
            }
            cSave = restoredSave
        }

        var cInput = Self.makeCInput(input, clockTimer: isOddPreview ? 0 : 1)
        var cFrame = GEFileModeFrameV6()
        let status = ge_file_mode_v6_step(&state, &cInput, &cSave, &cFrame)
        guard status == GE_STATUS_OK else {
            throw GoldenEyeFileModeAuthorityV6Error.cStatus(UInt32(status))
        }
        saveState = try Self.makeSwiftSave(cSave)
        let frame = GoldenEyeFileModeFrameV6(cFrame)

        if isOddPreview {
            if Self.oddStepCommitsAction(input: input, frame: frame) {
                // An input-triggered source action is allowed to commit on
                // either native tick. Preserve it as the next anchor so the
                // following even step cannot replay the same action.
                pairedAnchorState = state
                pairedAnchorSave = saveState
                oddActionCommitted = true
            } else {
                oddActionCommitted = false
            }
        } else {
            pairedAnchorState = state
            pairedAnchorSave = saveState
            oddActionCommitted = false
        }

        lastFrame = frame
        return frame
    }

    private static func makeCInput(
        _ input: GoldenEyeFileModeInputV6,
        clockTimer: UInt32
    ) -> GEFileModeInputV6 {
        var value = GEFileModeInputV6()
        value.header.abi_version = GE_NATIVE_ABI_VERSION
        value.header.struct_size = UInt32(MemoryLayout<GEFileModeInputV6>.size)
        value.record_version = UInt32(GE_FILE_MODE_V6_RECORD_VERSION)
        if input.nativeTick & 1 == 0 {
            value.flags |= UInt32(GE_FILE_MODE_V6_INPUT_FLAG_SOURCE_ANCHOR)
        }
        if input.focused {
            value.flags |= UInt32(GE_FILE_MODE_V6_INPUT_FLAG_FOCUSED)
        }
        if input.controllerConnected {
            value.flags |= UInt32(GE_FILE_MODE_V6_INPUT_FLAG_CONTROLLER_CONNECTED)
        }
        if input.synthetic {
            value.flags |= UInt32(GE_FILE_MODE_V6_INPUT_FLAG_SYNTHETIC)
        }
        value.buttons_held = input.held
        value.buttons_pressed = input.pressed
        value.buttons_released = input.released
        value.stick_x = input.stickX
        value.stick_y = input.stickY
        value.controller_count = input.controllerCount
        value.clock_timer = clockTimer
        value.native_tick = input.nativeTick
        value.reference_tick = input.nativeTick / 2
        value.sequence = input.sequence
        return value
    }

    private static func oddStepCommitsAction(
        input: GoldenEyeFileModeInputV6,
        frame: GoldenEyeFileModeFrameV6
    ) -> Bool {
        guard input.pressed != 0 else { return false }
        return frame.events.contains {
            $0.kind == GE_FILE_MODE_V6_EVENT_SAVE.rawValue ||
                $0.kind == GE_FILE_MODE_V6_EVENT_SCREEN.rawValue ||
                $0.kind == GE_FILE_MODE_V6_EVENT_ROUTE.rawValue ||
                $0.kind == GE_FILE_MODE_V6_EVENT_SFX.rawValue
        }
    }

    public static func semanticSnapshot(
        from save: GoldenEyeSaveState
    ) throws -> GESaveSnapshotV1 {
        guard let result = makeCSave(save) else {
            throw GoldenEyeFileModeAuthorityV6Error.invalidSave
        }
        return result
    }

    public static func saveState(
        from snapshot: GESaveSnapshotV1
    ) throws -> GoldenEyeSaveState {
        try makeSwiftSave(snapshot)
    }

    private static func makeCSave(_ save: GoldenEyeSaveState) -> GESaveSnapshotV1? {
        guard save.folders.count == Int(GE_FILE_MODE_V6_FOLDER_COUNT),
              save.selectedFolder < UInt8(GE_FILE_MODE_V6_FOLDER_COUNT),
              save.selectedBond < 4 else {
            return nil
        }
        var value = GESaveSnapshotV1()
        value.header.abi_version = GE_NATIVE_ABI_VERSION
        value.header.struct_size = UInt32(MemoryLayout<GESaveSnapshotV1>.size)
        value.record_version = UInt32(GE_FILE_MODE_V6_RECORD_VERSION)
        value.selected_folder = UInt32(save.selectedFolder)
        value.selected_bond = UInt32(save.selectedBond)
        value.generation = save.generation
        var folderBytes = Array(repeating: UInt8(0), count: 4 * 96)
        for index in 0..<Int(GE_FILE_MODE_V6_FOLDER_COUNT) {
            folderBytes.replaceSubrange(
                (index * 96)..<((index + 1) * 96),
                with: save.folders[index].bytes
            )
        }
        folderBytes.withUnsafeBytes { source in
            withUnsafeMutableBytes(of: &value.folders) { destination in
                destination.copyMemory(from: source)
            }
        }
        return value
    }

    private static func makeSwiftSave(_ save: GESaveSnapshotV1) throws -> GoldenEyeSaveState {
        var folders: [GoldenEyeSaveFolder] = []
        folders.reserveCapacity(Int(GE_FILE_MODE_V6_FOLDER_COUNT))
        let folderBytes = withUnsafeBytes(of: save.folders) { Array($0) }
        for index in 0..<Int(GE_FILE_MODE_V6_FOLDER_COUNT) {
            let bytes = Array(folderBytes[(index * 96)..<((index + 1) * 96)])
            folders.append(try GoldenEyeSaveFolder(bytes: bytes))
        }
        return GoldenEyeSaveState(
            folders: folders,
            selectedFolder: UInt8(save.selected_folder),
            selectedBond: UInt8(save.selected_bond),
            generation: save.generation
        )
    }
}
