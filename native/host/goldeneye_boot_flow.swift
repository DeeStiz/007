import Foundation
import Metal
import QuartzCore

/// The title controller is deliberately a value type.  AppKit and Metal never
/// mutate it directly; the owner thread advances it and publishes immutable
/// snapshots to the renderer.  Source-autonomous branches are evaluated on
/// even native ticks so the projected 60 Hz anchors remain reproducible.
enum GoldenEyeTitleScreen: UInt32, Sendable {
    case legal = 0
    case nintendo = 1
    case rareware = 2
    case gunbarrel = 3
    case goldenEye = 4
    case fileSelect = 5
    case modeSelect = 6
    case cast = 7
    case ramrom = 8
}

struct GoldenEyeTitleInput: Sendable, Equatable {
    var held: UInt16 = 0
    var pressed: UInt16 = 0
    var released: UInt16 = 0
    var stickX: Int8 = 0
    var stickY: Int8 = 0
    var focused: Bool = true
}

struct GoldenEyeTitleSnapshot: Sendable, Equatable {
    var nativeTick: UInt64
    var referenceTick: UInt64
    var pairPhase: UInt8
    var screen: GoldenEyeTitleScreen
    var subphase: UInt32
    var timer120: UInt32
    var gunbarrelTimer120: UInt32
    var titleXQ16: Int32
    var titleRotationQ16: Int32
    var titleScaleQ16: Int32
    var alphaQ16: Int32
    var titleLightQ8: UInt16
    var selection: Int16
    var demoIndex: UInt8
    var stateHash: UInt64
    var renderHash: UInt64
    var audioHash: UInt64
}

/// Optional bridge used by the first native host integration.  Renderers that
/// have not yet adopted scene packets can still consume the immutable title
/// snapshot to expose phase/clock evidence without reading mutable game state.
protocol GoldenEyeTitleSnapshotRenderer: AnyObject {
    func submit(titleSnapshot: GoldenEyeTitleSnapshot)
}

@available(macOS 26.0, *)
protocol GoldenEyeDrawableFrameRenderer: AnyObject {
    func render(drawable: any CAMetalDrawable, timing: GE120DisplayTiming) -> Bool
}

struct GoldenEyeBootFlow: Sendable {
    private static let buttonA: UInt16 = 1 << 0
    private static let buttonB: UInt16 = 1 << 1
    private static let buttonStart: UInt16 = 1 << 2
    private static let buttonZ: UInt16 = 1 << 3
    private static let confirmMask: UInt16 = buttonA | buttonStart | buttonZ
    private static let cancelMask: UInt16 = buttonB

    private(set) var nativeTick: UInt64 = 0
    private(set) var screen: GoldenEyeTitleScreen = .legal
    private(set) var subphase: UInt32 = 0
    private(set) var timer120: UInt32 = 0
    private(set) var gunbarrelTimer120: UInt32 = 0
    private(set) var titleXQ16: Int32 = 0
    private(set) var titleRotationQ16: Int32 = 0
    private(set) var titleScaleQ16: Int32 = 0x0001_0000
    private(set) var alphaQ16: Int32 = 0x0001_0000
    private(set) var titleLightQ8: UInt16 = 0x00ff
    private(set) var selection: Int16 = 0
    private(set) var demoIndex: UInt8 = 0

    private var firstBoot = true
    private var legalFirstVisit = true
    private var pendingScreen: GoldenEyeTitleScreen?
    private var transitionRemaining120: UInt32 = 0
    private var gunbarrelMode: UInt8 = 2
    private var gunbarrelTransitionXQ16: Int32 = 0
    private var castIndex: UInt16 = 1
    private var lastInputSequence: UInt64 = 0
    private var fileOption: UInt8 = 0
    private var saveState = GoldenEyeSaveState.blank
    private var eraseConfirmationPending = false
    private var eraseConfirmationChoice: UInt8 = 0 // source default: Cancel
    private var attractRoute: GoldenEyeAttractRoute
    private var ramRomRestorePoint: GoldenEyeRamRomRestorePoint?
    private var ramRomPlaybackOwned = false

    private struct GoldenEyeRamRomRestorePoint: Sendable, Equatable {
        let selection: Int16
        let fileOption: UInt8
        let selectedFolder: UInt8
        let stateHash: UInt64
    }

    init(
        ramRomCatalog: GoldenEyeRamRomRouteCatalog = .fromEnvironment(),
        randomSeed: UInt64 = GoldenEyeBootFlow.defaultRandomSeed()
    ) {
        attractRoute = GoldenEyeAttractRoute(
            catalog: ramRomCatalog,
            randomSeed: randomSeed
        )
    }

    /// Explicit deterministic selection is used by the 14-demo acceptance
    /// harness.  Production leaves this nil and consumes the source-style
    /// random word only after the normal cast route reaches its sentinel.
    mutating func requestRamRomDemo(catalogIndex: UInt8?) -> Bool {
        attractRoute.requestDemo(catalogIndex: catalogIndex)
    }

    mutating func setCastProgress(_ progress: GoldenEyeCastProgress) {
        attractRoute.setProgress(progress)
    }

    /// One-shot handoff to the future stage/gameplay owner.  Taking the request
    /// does not pretend that a stage loaded; the title remains in `.ramrom`
    /// until that owner explicitly reports completion, abort, or failure.
    mutating func takeRamRomLaunchRequest() -> GoldenEyeRamRomLaunchRequest? {
        attractRoute.takeLaunchRequest()
    }

    @discardableResult
    mutating func restoreAfterRamRom(_ reason: GoldenEyeRamRomExitReason) -> Bool {
        guard screen == .ramrom,
              attractRoute.finishDemo(reason),
              let restore = ramRomRestorePoint else {
            return false
        }
        ramRomPlaybackOwned = false
        selection = restore.selection
        fileOption = restore.fileOption
        saveState.selectedFolder = restore.selectedFolder
        ramRomRestorePoint = nil
        subphase = UInt32(reason.rawValue)
        schedule(.fileSelect)
        return true
    }

    /// The native playback service owns RAMROM input while this flag is set.
    /// The fallback title-only route remains available for the isolated title
    /// smokes and for a host that has no guarded RAMROM asset root.
    mutating func setRamRomPlaybackOwned(_ owned: Bool) {
        ramRomPlaybackOwned = owned
    }

    /// Installs the asynchronously loaded semantic save before File Select
    /// becomes interactive. This is owner-thread-only state; persistence is
    /// handled by GoldenEyeSaveRuntime.
    mutating func installSaveState(_ state: GoldenEyeSaveState) {
        saveState = state
        if screen == .fileSelect {
            selection = Int16(state.selectedFolder)
        }
    }

    func saveStateSnapshot() -> GoldenEyeSaveState {
        saveState
    }

    mutating func step(input: GoldenEyeTitleInput = GoldenEyeTitleInput()) -> GoldenEyeTitleSnapshot {
        nativeTick &+= 1
        let pairPhase = UInt8(nativeTick & 1)
        lastInputSequence &+= 1

        if !input.focused {
            return snapshot(pairPhase: pairPhase)
        }

        if transitionRemaining120 != 0 {
            transitionRemaining120 -= 1
            if transitionRemaining120 == 0, let pendingScreen {
                self.pendingScreen = nil
                enter(pendingScreen)
            }
            return snapshot(pairPhase: pairPhase)
        }

        timer120 &+= 1
        switch screen {
        case .legal:
            updateLegal(input: input, pairPhase: pairPhase)
        case .nintendo:
            updateNintendo(input: input, pairPhase: pairPhase)
        case .rareware:
            updateRareware(input: input, pairPhase: pairPhase)
        case .gunbarrel:
            updateGunbarrel(input: input, pairPhase: pairPhase)
        case .goldenEye:
            updateGoldenEye(input: input, pairPhase: pairPhase)
        case .fileSelect:
            updateFileSelect(input: input)
        case .modeSelect:
            updateModeSelect(input: input)
        case .cast:
            updateCast(input: input, pairPhase: pairPhase)
        case .ramrom:
            updateRamrom(input: input, pairPhase: pairPhase)
        }
        return snapshot(pairPhase: pairPhase)
    }

    private mutating func updateLegal(input: GoldenEyeTitleInput, pairPhase: UInt8) {
        // The original first-boot legal page intentionally ignores all input.
        guard pairPhase == 0, timer120 >= 482 else { return }
        legalFirstVisit = false
        schedule(.nintendo)
    }

    private mutating func updateNintendo(input: GoldenEyeTitleInput, pairPhase: UInt8) {
        // Source `constructor_menu01_nintendo` advances one degree per 60 Hz
        // frame and grows scale by 1.07977 before clamping at 1.1. Use exact
        // fixed-point half-steps so every even native anchor remains source
        // aligned while the odd state is a real visual state.
        titleRotationQ16 &+= 572 // 0.5 degrees in Q16 radians
        let scaled = (Int64(titleScaleQ16) * 68_100) >> 16 // sqrt(1.07977)
        titleScaleQ16 = min(0x0001_1999, Int32(clamping: scaled))
        let referenceTimer = Int64(timer120 >> 1)
        let ambient = 255 - ((referenceTimer * 255 - 94_350) / 100)
        titleLightQ8 = UInt16(clamping: ambient)
        if isConfirm(input) {
            if firstBoot {
                schedule(.rareware)
            } else {
                schedule(.fileSelect)
            }
            return
        }
        guard pairPhase == 0, timer120 >= 1002 else { return }
        schedule(.rareware)
    }

    private mutating func updateRareware(input: GoldenEyeTitleInput, pairPhase: UInt8) {
        if isConfirm(input) {
            schedule(firstBoot ? .gunbarrel : .fileSelect)
            return
        }
        guard pairPhase == 0, timer120 >= 580 else { return }
        schedule(.gunbarrel)
    }

    private mutating func updateGunbarrel(input: GoldenEyeTitleInput, pairPhase: UInt8) {
        if isConfirm(input) {
            schedule(firstBoot ? .goldenEye : .fileSelect)
            return
        }

        // The source intro's visual mode machine is bounded by the authored
        // 682-source-frame title seam. Keep the discrete screen transition on
        // that anchor even if a guarded model packet is shorter/longer than a
        // future blood/animation implementation.
        if pairPhase == 0, timer120 >= 682 * 2 {
            firstBoot = false
            schedule(.goldenEye)
            return
        }

        // These are source-authored paired dynamics.  The odd tick is a real
        // half-step; the even tick is the quantized source anchor.
        gunbarrelTimer120 &+= 1
        switch gunbarrelMode {
        case 2:
            titleXQ16 &+= 6 * 0x8000
            if titleXQ16 > 1390 * 0x1_0000 { gunbarrelMode = 3; titleXQ16 = 1276 * 0x1_0000 }
        case 3:
            // Source XDEC3 is 5.8183274 per 60 Hz frame. The native
            // authority executes the exact half increment at 120 Hz.
            titleXQ16 -= 190_000
            if titleXQ16 <= -80 * 0x1_0000 { gunbarrelMode = 4; gunbarrelTimer120 = 0 }
        case 4:
            if pairPhase == 0, gunbarrelTimer120 > 40 { gunbarrelMode = 5; gunbarrelTimer120 = 0 }
        case 5:
            if pairPhase == 0, gunbarrelTimer120 >= 137 * 2 {
                gunbarrelMode = 6
                gunbarrelTimer120 = 0
                gunbarrelTransitionXQ16 = titleXQ16
                titleRotationQ16 = 0
            }
        case 6:
            // Source INCVAL is 0x38e per 60 Hz frame; 0x1c7 is the exact
            // native half-step. Reconstruct the authored 64-unit sway in
            // fixed visual space without exposing a floating source pointer.
            titleRotationQ16 &+= 0x0000_01c7
            let radians = Double(UInt32(truncatingIfNeeded: titleRotationQ16 & 0x0000_ffff))
                / 65_536.0 * (Double.pi * 2.0)
            titleXQ16 = gunbarrelTransitionXQ16
                &+ Int32((sin(radians) * 64.0 * 65_536.0).rounded())
            if pairPhase == 0, gunbarrelTimer120 >= 216 { gunbarrelMode = 7; gunbarrelTimer120 = 0 }
        case 7:
            alphaQ16 = min(0x0001_0000, alphaQ16 + 0x0000_0400)
            if alphaQ16 >= 0x0000_F700, pairPhase == 0 { gunbarrelMode = 8; gunbarrelTimer120 = 0 }
        case 8:
            if pairPhase == 0, gunbarrelTimer120 >= 60 { gunbarrelMode = 9; gunbarrelTimer120 = 0 }
        default:
            schedule(.goldenEye)
        }
        subphase = UInt32(gunbarrelMode)
    }

    private mutating func updateGoldenEye(input: GoldenEyeTitleInput, pairPhase: UInt8) {
        if isConfirm(input) {
            firstBoot = false
            schedule(.fileSelect)
            return
        }
        guard pairPhase == 0, timer120 >= 360 else { return }
        // A hands-off source boot enters the cast/demo route.
        firstBoot = false
        castIndex = attractRoute.beginCast(.normalAttract)
        subphase = UInt32(castIndex)
        schedule(.cast)
    }

    private mutating func updateFileSelect(input: GoldenEyeTitleInput) {
        if eraseConfirmationPending {
            if input.stickY > 30 || input.stickX < -30 {
                eraseConfirmationChoice = 0
            }
            if input.stickY < -30 || input.stickX > 30 {
                eraseConfirmationChoice = 1
            }
            subphase = 3 + UInt32(eraseConfirmationChoice)
            if isCancel(input) {
                eraseConfirmationPending = false
                eraseConfirmationChoice = 0
                subphase = UInt32(fileOption)
            } else if isConfirm(input) {
                if eraseConfirmationChoice == 1 {
                    try? GoldenEyeSaveActions.eraseFolder(&saveState, at: Int(selection))
                }
                eraseConfirmationPending = false
                eraseConfirmationChoice = 0
                fileOption = 0
                subphase = 0
            }
            return
        }
        if input.stickY > 30 { selection = max(0, selection - 1) }
        if input.stickY < -30 { selection = min(3, selection + 1) }
        if input.stickX > 30 { fileOption = min(2, fileOption + 1) }
        if input.stickX < -30 { fileOption = fileOption > 0 ? fileOption - 1 : 0 }
        subphase = UInt32(fileOption)
        if isConfirm(input) {
            switch fileOption {
            case 0:
                if saveState.folders[Int(selection)].isReset {
                    try? GoldenEyeSaveActions.createFolder(&saveState, at: Int(selection))
                } else {
                    try? GoldenEyeSaveActions.selectFolder(&saveState, index: Int(selection))
                }
                schedule(.modeSelect)
            case 1:
                _ = try? GoldenEyeSaveActions.copyFolderToFirstBlank(
                    &saveState,
                    from: Int(selection)
                )
            default:
                if !saveState.folders[Int(selection)].isReset {
                    eraseConfirmationPending = true
                    eraseConfirmationChoice = 0
                    subphase = 3
                }
            }
        }
        if isCancel(input) {
            if fileOption != 0 { fileOption = 0; subphase = 0 }
            else { selection = 0 }
        }
    }

    private mutating func updateModeSelect(input: GoldenEyeTitleInput) {
        if input.stickY > 30 { selection = max(0, selection - 1) }
        if input.stickY < -30 { selection = min(1, selection + 1) }
        if isCancel(input) { schedule(.fileSelect) }
        // Mission selection is intentionally outside this goal.  Keeping the
        // state interactive is enough to prove the native main-menu boundary.
    }

    private mutating func updateCast(input: GoldenEyeTitleInput, pairPhase: UInt8) {
        if hasRealButtonPress(input) {
            schedule(.fileSelect)
            return
        }
        guard pairPhase == 0, timer120 >= 181 * 2 else { return }
        switch attractRoute.advanceCast() {
        case let .showCast(sourceIndex):
            castIndex = sourceIndex
            subphase = UInt32(sourceIndex)
            schedule(.cast)
        case let .launchDemo(request):
            ramRomRestorePoint = GoldenEyeRamRomRestorePoint(
                selection: selection,
                fileOption: fileOption,
                selectedFolder: saveState.selectedFolder,
                stateHash: snapshot(pairPhase: pairPhase).stateHash
            )
            demoIndex = request.catalogIndex
            subphase = UInt32(request.demoID)
            schedule(.ramrom)
        case .missionSelect:
            // The extended credits route returns to mission selection.  This
            // bounded native goal currently exposes Mode Select as that menu
            // boundary without claiming mission-select rendering parity.
            schedule(.modeSelect)
        case .catalogUnavailable:
            // Missing or mismatched private assets fail closed at File Select;
            // no timer-only pseudo-demo is substituted.
            subphase = UInt32.max
            schedule(.fileSelect)
        }
    }

    private mutating func updateRamrom(input: GoldenEyeTitleInput, pairPhase: UInt8) {
        _ = pairPhase
        guard !ramRomPlaybackOwned else { return }
        if hasRealButtonPress(input) {
            _ = restoreAfterRamRom(.realInputAbort)
        }
    }

    private func isConfirm(_ input: GoldenEyeTitleInput) -> Bool {
        (input.pressed & Self.confirmMask) != 0
    }

    private func isCancel(_ input: GoldenEyeTitleInput) -> Bool {
        (input.pressed & Self.cancelMask) != 0
    }

    private func hasRealButtonPress(_ input: GoldenEyeTitleInput) -> Bool {
        input.pressed != 0
    }

    private mutating func schedule(_ next: GoldenEyeTitleScreen) {
        pendingScreen = next
        transitionRemaining120 = 8
    }

    private mutating func enter(_ next: GoldenEyeTitleScreen) {
        screen = next
        subphase = 0
        timer120 = 0
        gunbarrelTimer120 = 0
        titleRotationQ16 = 0
        titleScaleQ16 = 0x0001_0000
        alphaQ16 = 0x0001_0000
        titleLightQ8 = 0x00ff
        if next == .gunbarrel {
            gunbarrelMode = 2
            titleXQ16 = -30 * 0x1_0000
            gunbarrelTransitionXQ16 = -100 * 0x1_0000
        } else if next == .cast {
            if attractRoute.castSourceIndex == nil {
                castIndex = attractRoute.beginCast(.normalAttract)
            } else {
                castIndex = attractRoute.castSourceIndex!
            }
            subphase = UInt32(castIndex)
        } else if next == .ramrom {
            if let selectedDemo = attractRoute.selectedDemo {
                demoIndex = selectedDemo.catalogIndex
                subphase = UInt32(selectedDemo.demoID)
            }
        } else if next == .fileSelect {
            fileOption = 0
            selection = Int16(saveState.selectedFolder)
        }
    }

    private func snapshot(pairPhase: UInt8) -> GoldenEyeTitleSnapshot {
        let selectedRecordingHash = attractRoute.selectedDemo?.recordingHash ?? 0
        let stateHash = GoldenEyeTitleHash.fnv1a([
            nativeTick, UInt64(screen.rawValue), UInt64(subphase), UInt64(timer120),
            UInt64(gunbarrelTimer120), UInt64(bitPattern: Int64(titleXQ16)),
            UInt64(bitPattern: Int64(titleRotationQ16)), UInt64(bitPattern: Int64(alphaQ16)),
            UInt64(titleLightQ8),
            UInt64(bitPattern: Int64(selection)), UInt64(demoIndex),
            attractRoute.catalog.catalogHash, selectedRecordingHash
        ])
        let renderHash = GoldenEyeTitleHash.fnv1a([
            UInt64(screen.rawValue), UInt64(subphase), UInt64(bitPattern: Int64(titleXQ16)),
            UInt64(bitPattern: Int64(titleRotationQ16)), UInt64(bitPattern: Int64(titleScaleQ16)),
            UInt64(bitPattern: Int64(alphaQ16)), UInt64(titleLightQ8), UInt64(bitPattern: Int64(selection))
        ])
        return GoldenEyeTitleSnapshot(
            nativeTick: nativeTick,
            referenceTick: nativeTick >> 1,
            pairPhase: pairPhase,
            screen: screen,
            subphase: subphase,
            timer120: timer120,
            gunbarrelTimer120: gunbarrelTimer120,
            titleXQ16: titleXQ16,
            titleRotationQ16: titleRotationQ16,
            titleScaleQ16: titleScaleQ16,
            alphaQ16: alphaQ16,
            titleLightQ8: titleLightQ8,
            selection: selection,
            demoIndex: demoIndex,
            stateHash: stateHash,
            renderHash: renderHash,
            audioHash: 0
        )
    }

    private static func defaultRandomSeed() -> UInt64 {
        if let value = ProcessInfo.processInfo.environment["GOLDENEYE_TITLE_RANDOM_SEED"] {
            let isHex = value.hasPrefix("0x") || value.hasPrefix("0X")
            let digits = isHex ? String(value.dropFirst(2)) : value
            if let parsed = UInt64(digits, radix: isHex ? 16 : 10) {
                return parsed
            }
        }
        return DispatchTime.now().uptimeNanoseconds
    }
}

enum GoldenEyeTitleHash {
    static func fnv1a(_ words: [UInt64]) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for word in words {
            var value = word.littleEndian
            withUnsafeBytes(of: &value) { bytes in
                for byte in bytes {
                    hash ^= UInt64(byte)
                    hash &*= 0x100000001b3
                }
            }
        }
        return hash
    }
}
