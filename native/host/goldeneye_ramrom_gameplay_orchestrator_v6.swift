import Foundation

#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

public struct GoldenEyeRamRomGameplayReadinessV6: Sendable, Equatable {
    public let playerCameraReady: Bool
    public let gameplayReady: Bool
    public let guardDoorReady: Bool
    public let weaponEffectReady: Bool
    public let missingFields: [String]

    public var isReady: Bool {
        playerCameraReady && gameplayReady && guardDoorReady && weaponEffectReady && missingFields.isEmpty
    }
}

public struct GoldenEyeRamRomGameplayFrameV6 {
    public let nativeTick: UInt64
    public let referenceTick: UInt64
    public let pairPhase: UInt32
    public let demoID: UInt32
    public let stageID: UInt32
    public let gameplaySnapshot: GERamRomGameplaySnapshotV6
    public let gameplayEvent: GERamRomGameplayEventV6
    public let playerCamera: GoldenEyeRamRomPlayerCameraPublicationV6
    public let guardDoorEventHash: UInt64
    public let weaponEffectEventHash: UInt64
    public private(set) var readiness: GoldenEyeRamRomGameplayReadinessV6
    public let stateHash: UInt64
}

public struct GoldenEyeRamRomGameplayRestoreSnapshotV6 {
    public let nativeTick: UInt64
    public let gameplay: GERamRomGameplaySnapshotV6
    public let playerCamera: GEPlayerCameraSnapshotV6
}

public enum GoldenEyeRamRomGameplayOrchestratorErrorV6: Error, Sendable, Equatable, CustomStringConvertible {
    case missingAssetRoot
    case missingStageRoot
    case missingVisibleRoot
    case invalidTick(UInt64, UInt64)
    case cStatus(UInt32, String)
    case sourceNotReady([String])
    case missingWeaponFrame(UInt64)
    case inactive
    case restoreMismatch

    public var description: String {
        switch self {
        case .missingAssetRoot: return "RAMROM gameplay asset root is unavailable"
        case .missingStageRoot: return "RAMROM gameplay stage asset root is unavailable"
        case .missingVisibleRoot: return "RAMROM gameplay visible-dependency root is unavailable"
        case let .invalidTick(expected, actual): return "RAMROM gameplay expected tick \(expected), got \(actual)"
        case let .cStatus(status, operation): return "RAMROM gameplay \(operation) failed with status \(status)"
        case let .sourceNotReady(fields): return "RAMROM gameplay source pages are not ready: \(fields.joined(separator: ","))"
        case let .missingWeaponFrame(tick): return "weapon/effect source frame is missing at native tick \(tick)"
        case .inactive: return "RAMROM gameplay orchestrator is inactive"
        case .restoreMismatch: return "RAMROM gameplay restore snapshot does not match the selected route"
        }
    }
}

/// One owner-thread composition of the source RAMROM gameplay seams. The
/// recording bytes are held only for the active route and are borrowed by C
/// for each begin/step call. No renderer, ROM path, or pointer crosses this
/// boundary.
@available(macOS 27.0, *)
public final class GoldenEyeRamRomGameplayOrchestratorV6: @unchecked Sendable {
    let request: GoldenEyeRamRomLaunchRequest
    public let pages: GoldenEyeRamRomPlayerCameraPagesV6
    public private(set) var readiness: GoldenEyeRamRomGameplayReadinessV6

    private let recording: Data
    private let playerOwner: GoldenEyeRamRomPlayerCameraOwnerV6
    private var gameplaySetup: GERamRomGameplaySetupV6
    private var gameplayState = GERamRomGameplayStateV6()
    /* Borrowed owner page; its storage is caller-owned and never enters a
       public snapshot or gameplay record. A pointer avoids placing the
       1.9-MB optional C state on the owner-thread stack. */
    private var guardDoorOwner: UnsafeMutablePointer<GEGuardDoorOwnerStateV6>?
    private let ownsGuardDoorOwner: Bool
    private var weaponSetup: GERamRomWeaponEffectSetupV6?
    private var weaponEffectOwner: GERamRomWeaponEffectOwnerStateV6?
    private let weaponFrames: [UInt64: GERamRomWeaponEffectFrameV6]
    private var expectedRelativeTick: UInt64 = 0
    private let startNativeTick: UInt64
    private var active = true
    private var lastFrame: GoldenEyeRamRomGameplayFrameV6?
    private var restoreSnapshot: GoldenEyeRamRomGameplayRestoreSnapshotV6?

    public var isActive: Bool { active }
    public var currentFrame: GoldenEyeRamRomGameplayFrameV6? { lastFrame }

    init(
        request: GoldenEyeRamRomLaunchRequest,
        recording: Data,
        pages: GoldenEyeRamRomPlayerCameraPagesV6,
        atNativeTick nativeTick: UInt64,
        guardDoorOwner: UnsafeMutablePointer<GEGuardDoorOwnerStateV6>? = nil,
        weaponSetup: GERamRomWeaponEffectSetupV6? = nil,
        weaponInitialFrame: GERamRomWeaponEffectFrameV6? = nil,
        weaponFrames: [UInt64: GERamRomWeaponEffectFrameV6] = [:],
        additionalMissingFields: [String] = [],
        ownsGuardDoorOwner: Bool = false
    ) throws {
        guard request.demoID > 0, request.stageID == pages.stageID else {
            throw GoldenEyeRamRomGameplayOrchestratorErrorV6.sourceNotReady(["route_identity"])
        }
        guard !recording.isEmpty else {
            throw GoldenEyeRamRomGameplayOrchestratorErrorV6.sourceNotReady(["recording_bytes"])
        }
        self.request = request
        self.recording = recording
        self.pages = pages
        self.startNativeTick = nativeTick
        self.playerOwner = try GoldenEyeRamRomPlayerCameraOwnerV6(pages: pages)
        self.gameplaySetup = pages.setup
        self.weaponFrames = weaponFrames
        self.guardDoorOwner = guardDoorOwner
        self.ownsGuardDoorOwner = ownsGuardDoorOwner
        self.weaponSetup = weaponSetup
        self.weaponEffectOwner = nil
        self.readiness = GoldenEyeRamRomGameplayReadinessV6(
            playerCameraReady: true, gameplayReady: false,
            guardDoorReady: false, weaponEffectReady: false,
            missingFields: ["gameplay_begin_pending"]
        )

        var event = GERamRomGameplayEventV6()
        let beginStatus: UInt32 = recording.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return UInt32(GE_STATUS_INVALID_ARGUMENT)
            }
            return pages.entities.withUnsafeBufferPointer { entityBuffer in
                pages.attachments.withUnsafeBufferPointer { attachmentBuffer in
                    withUnsafeMutablePointer(to: &self.gameplaySetup) { setupPointer in
                        withUnsafeMutablePointer(to: &self.gameplayState) { statePointer in
                            withUnsafeMutablePointer(to: &event) { eventPointer in
                                if let guardOwner = self.guardDoorOwner {
                                    let status = ge_ramrom_gameplay_v6_begin_with_source_pages_and_guard_door_owner(
                                        base, UInt32(recording.count), UInt32(request.demoID), setupPointer,
                                        entityBuffer.baseAddress, UInt32(entityBuffer.count),
                                        attachmentBuffer.baseAddress, UInt32(attachmentBuffer.count),
                                        guardOwner, statePointer, eventPointer
                                    )
                                    return status
                                }
                                return ge_ramrom_gameplay_v6_begin_with_source_pages(
                                    base, UInt32(recording.count), UInt32(request.demoID), setupPointer,
                                    entityBuffer.baseAddress, UInt32(entityBuffer.count),
                                    attachmentBuffer.baseAddress, UInt32(attachmentBuffer.count),
                                    statePointer, eventPointer
                                )
                            }
                        }
                    }
                }
            }
        }
        guard beginStatus == UInt32(GE_STATUS_OK) else {
            throw GoldenEyeRamRomGameplayOrchestratorErrorV6.cStatus(beginStatus, "begin")
        }

        var missing: [String] = additionalMissingFields
        let guardReady = self.guardDoorOwner != nil
        if !guardReady { missing.append("guard_door_authoritative_pages") }
        var weaponReady = false
        if let weaponSetup, let weaponInitialFrame {
            var setupCopy = weaponSetup
            var initialFrameCopy = weaponInitialFrame
            var owner = GERamRomWeaponEffectOwnerStateV6()
            var weaponEvent = GERamRomGameplayEventV6()
            let status = ge_ramrom_gameplay_v6_install_weapon_effect(
                &self.gameplayState, &setupCopy, &initialFrameCopy, &owner, &weaponEvent
            )
            if status == UInt32(GE_STATUS_OK) {
                self.weaponEffectOwner = owner
                weaponReady = true
            } else {
                missing.append("weapon_effect_owner_status_\(status)")
            }
        } else {
            missing.append("weapon_effect_authoritative_pages")
        }
        self.readiness = GoldenEyeRamRomGameplayReadinessV6(
            playerCameraReady: true, gameplayReady: true,
            guardDoorReady: guardReady, weaponEffectReady: weaponReady,
            missingFields: missing
        )
        let initialPublication = GoldenEyeRamRomPlayerCameraPublicationV6(
            snapshot: playerOwner.snapshot, nativeTickOverride: nativeTick
        )
        var gameplaySnapshot = GERamRomGameplaySnapshotV6()
        _ = ge_ramrom_gameplay_v6_copy_snapshot(&self.gameplayState, &gameplaySnapshot)
        lastFrame = Self.makeFrame(
            nativeTick: nativeTick, request: request, gameplaySnapshot: gameplaySnapshot,
            gameplayEvent: event, playerCamera: initialPublication,
            guardDoorHash: self.guardDoorOwner?.pointee.state_hash ?? 0,
            weaponEffectHash: self.weaponEffectOwner?.snapshot.state_hash ?? 0,
            readiness: readiness
        )
    }

    deinit {
        if ownsGuardDoorOwner, let pointer = guardDoorOwner {
            pointer.deinitialize(count: 1)
            pointer.deallocate()
        }
    }

    /// Build a production route from the guarded external asset roots. Missing
    /// stage/player/save/options evidence remains an explicit source error.
    static func fromEnvironment(
        request: GoldenEyeRamRomLaunchRequest, atNativeTick nativeTick: UInt64
    ) throws -> Self {
        guard let assetRootValue = ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_ASSET_ROOT"],
              !assetRootValue.isEmpty else { throw GoldenEyeRamRomGameplayOrchestratorErrorV6.missingAssetRoot }
        guard let stageRootValue = ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_STAGE_ASSET_ROOT"],
              !stageRootValue.isEmpty else { throw GoldenEyeRamRomGameplayOrchestratorErrorV6.missingStageRoot }
        guard let visibleRootValue = ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_RAMROM_VISIBLE_ROOT"],
              !visibleRootValue.isEmpty else { throw GoldenEyeRamRomGameplayOrchestratorErrorV6.missingVisibleRoot }
        let assetRoot = URL(fileURLWithPath: assetRootValue, isDirectory: true)
        let stageRoot = URL(fileURLWithPath: stageRootValue, isDirectory: true)
        let visibleRoot = URL(fileURLWithPath: visibleRootValue, isDirectory: true)
        let catalog = try GoldenEyeStageAssetCatalog.load(stageAssetRoot: stageRoot)
        let packet = try GoldenEyeStageScenePacket.load(stageID: request.stageID, catalog: catalog)
        let dependencies = try GoldenEyeStageSetupDependencyCatalogV6.load(stageAssetRoot: stageRoot)
        let sidecars = try GoldenEyeStageModelSidecarCatalogV6.load(stageAssetRoot: stageRoot)
        let visible = try GoldenEyeRamRomVisibleDependencyCatalogV6.load(rootURL: visibleRoot)
        let weaponAssets = try GoldenEyeRamRomWeaponAssetCatalogV6.load(rootURL: visibleRoot)
        let slot = sourceSlot(stageID: request.stageID)
        let sourcePages = try GoldenEyeRamRomGameplaySourcePagesV6.make(
            stagePacket: packet, dependencies: dependencies, sidecars: sidecars,
            visibleDependencies: visible, slotNumber: slot
        )
        let recordingURL = assetRoot.appendingPathComponent("ramrom", isDirectory: true)
            .appendingPathComponent(request.assetName, isDirectory: false)
        let recording = try Data(contentsOf: recordingURL, options: [.mappedIfSafe])
        var header = GERamRomHeaderV5()
        let status = recording.withUnsafeBytes { raw -> UInt32 in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return UInt32(GE_STATUS_INVALID_ARGUMENT)
            }
            return ge_ramrom_v5_read_header(base, UInt32(recording.count), &header)
        }
        guard status == UInt32(GE_STATUS_OK) else {
            throw GoldenEyeRamRomGameplayOrchestratorErrorV6.cStatus(status, "recording header")
        }
        let style = withUnsafeBytes(of: header.controller_styles) {
            Array($0.bindMemory(to: UInt32.self)).first ?? 0
        }
        let options = try GoldenEyeRamRomSourceOptionStateV6(
            controlStyle: style, invertLook: 0,
            sourceHash: 0x4f5054494f4e5f55,
            provenance: ["RAMROM header controller_styles[0]", "src/game/options.c:104 default look option"]
        )
        let playerPages = try GoldenEyeRamRomPlayerCameraPageBuilderV6.make(
            stagePacket: packet, sourcePages: sourcePages, ramromHeader: header,
            optionState: options, demoID: UInt32(request.demoID)
        )
        var missing: [String] = []
        var guardPointer: UnsafeMutablePointer<GEGuardDoorOwnerStateV6>?
        let guardPages = try GoldenEyeRamRomGuardDoorPagesV6.make(
            stagePacket: packet, dependencies: dependencies, sidecars: sidecars,
            visibleDependencies: visible, demoID: request.demoID,
            slotNumber: GoldenEyeRamRomGuardDoorPagesV6.routeTable()
                .first(where: { $0.demo == request.demoID })?.slot ?? sourceSlot(stageID: request.stageID)
        )
        if guardPages.sourceReady {
            let state = try GoldenEyeRamRomGuardDoorPagesV6.makeOwnerState(
                from: guardPages, rngSeed: UInt64(header.randomizer_seed)
            )
            let pointer = UnsafeMutablePointer<GEGuardDoorOwnerStateV6>.allocate(capacity: 1)
            pointer.initialize(to: state)
            guardPointer = pointer
        } else {
            missing.append(contentsOf: guardPages.missingFields)
        }
        let weaponModels = Self.weaponModels(sidecars: sidecars)
        let mapping = GoldenEyeRamRomSourceWeaponMappingV6.resolveExact(
            itemIDs: [playerPages.source.initial_weapon], stageName: packet.stageName,
            visibleDependencies: visible, models: weaponModels,
            weaponAssets: weaponAssets
        )
        if !mapping.isComplete {
            missing.append(contentsOf: mapping.missingFields)
            missing.append("weapon_source_runtime_page")
        }
        return try Self(
            request: request, recording: recording, pages: playerPages,
            atNativeTick: nativeTick, guardDoorOwner: guardPointer,
            additionalMissingFields: Array(Set(missing)).sorted(),
            ownsGuardDoorOwner: guardPointer != nil
        )
    }

    @discardableResult
    public func step(
        nativeTick: UInt64, externalInput: GERamRomGameplayInputV6? = nil
    ) throws -> GoldenEyeRamRomGameplayFrameV6 {
        guard active else { throw GoldenEyeRamRomGameplayOrchestratorErrorV6.inactive }
        guard nativeTick == startNativeTick + expectedRelativeTick else {
            throw GoldenEyeRamRomGameplayOrchestratorErrorV6.invalidTick(
                startNativeTick + expectedRelativeTick, nativeTick
            )
        }
        var gameplayEvent = GERamRomGameplayEventV6()
        let gameplayStatus: UInt32 = recording.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return UInt32(GE_STATUS_INVALID_ARGUMENT)
            }
            let input = externalInput ?? Self.noInput()
            return withUnsafeMutablePointer(to: &gameplayState) { statePointer in
                    withUnsafeMutablePointer(to: &gameplayEvent) { eventPointer in
                        if let ownerPointer = self.guardDoorOwner {
                            return ge_ramrom_gameplay_v6_step_with_guard_door_owner(
                                base, UInt32(recording.count), expectedRelativeTick,
                                input, ownerPointer, statePointer, eventPointer
                            )
                        }
                        if var owner = self.weaponEffectOwner {
                            if expectedRelativeTick & 1 == 0 && expectedRelativeTick != 0 &&
                                self.weaponFrames[expectedRelativeTick] == nil {
                                return UInt32(GE_STATUS_UNSUPPORTED_COMMAND)
                            }
                            var weaponEvent = GERamRomWeaponEffectEventRecordV6()
                            let status = withUnsafeMutablePointer(to: &owner) { ownerPointer in
                                if var sourceFrame = self.weaponFrames[expectedRelativeTick] {
                                    return withUnsafePointer(to: &sourceFrame) { sourcePointer in
                                        ge_ramrom_gameplay_v6_step_with_weapon_effect(
                                            base, UInt32(recording.count), expectedRelativeTick,
                                            input, sourcePointer, ownerPointer, statePointer,
                                            eventPointer, &weaponEvent
                                        )
                                    }
                                }
                                return ge_ramrom_gameplay_v6_step_with_weapon_effect(
                                    base, UInt32(recording.count), expectedRelativeTick,
                                    input, nil, ownerPointer, statePointer, eventPointer,
                                    &weaponEvent
                                )
                            }
                            if status == UInt32(GE_STATUS_OK) {
                                self.weaponEffectOwner = owner
                            }
                            return status
                        }
                        return ge_ramrom_gameplay_v6_step(
                            base, UInt32(recording.count), expectedRelativeTick,
                            input, statePointer, eventPointer
                        )
                    }
            }
        }
        guard gameplayStatus == UInt32(GE_STATUS_OK) else {
            throw GoldenEyeRamRomGameplayOrchestratorErrorV6.cStatus(gameplayStatus, "step")
        }
        var weaponEventHash = weaponEffectOwner?.snapshot.state_hash ?? 0
        if guardDoorOwner != nil, var owner = weaponEffectOwner {
            if expectedRelativeTick & 1 == 0 && expectedRelativeTick != 0,
               weaponFrames[expectedRelativeTick] == nil {
                throw GoldenEyeRamRomGameplayOrchestratorErrorV6.missingWeaponFrame(expectedRelativeTick)
            }
            var weaponEvent = GERamRomWeaponEffectEventRecordV6()
            let weaponStatus = withUnsafeMutablePointer(to: &owner) { ownerPointer in
                if var sourceFrame = weaponFrames[expectedRelativeTick] {
                    return withUnsafePointer(to: &sourceFrame) { sourcePointer in
                        ge_ramrom_weapon_effect_v6_step(
                            expectedRelativeTick, gameplayInputForWeapon(gameplayEvent: gameplayEvent),
                            sourcePointer, ownerPointer, &weaponEvent
                        )
                    }
                }
                return ge_ramrom_weapon_effect_v6_step(
                    expectedRelativeTick, gameplayInputForWeapon(gameplayEvent: gameplayEvent),
                    nil, ownerPointer, &weaponEvent
                )
            }
            guard weaponStatus == UInt32(GE_STATUS_OK) else {
                throw GoldenEyeRamRomGameplayOrchestratorErrorV6.cStatus(weaponStatus, "weapon step")
            }
            weaponEffectOwner = owner
            weaponEventHash = weaponEvent.event_hash
        }
        let gameplayInput = externalInput ?? Self.inputFromGameplaySnapshot(gameplayState.snapshot)
        _ = try playerOwner.step(nativeTick: expectedRelativeTick, input: gameplayInput)
        let rebasedPublication = GoldenEyeRamRomPlayerCameraPublicationV6(
            snapshot: playerOwner.snapshot, nativeTickOverride: nativeTick
        )
        var snapshot = GERamRomGameplaySnapshotV6()
        _ = ge_ramrom_gameplay_v6_copy_snapshot(&gameplayState, &snapshot)
        let frame = Self.makeFrame(
            nativeTick: nativeTick, request: request, gameplaySnapshot: snapshot,
            gameplayEvent: gameplayEvent, playerCamera: rebasedPublication,
            guardDoorHash: guardDoorOwner?.pointee.state_hash ?? 0,
            weaponEffectHash: weaponEventHash,
            readiness: readiness
        )
        expectedRelativeTick += 1
        lastFrame = frame
        return frame
    }

    static func externalInput(_ input: GoldenEyeRamRomServiceInput) -> GERamRomGameplayInputV6 {
        var value = noInput()
        value.flags |= UInt32(GE_RAMROM_GAMEPLAY_V6_INPUT_REAL)
        if !input.focused { value.flags &= ~UInt32(GE_RAMROM_GAMEPLAY_V6_INPUT_FOCUSED) }
        value.pressed_buttons = input.pressedButtons
        value.held_buttons = input.heldButtons
        value.released_buttons = input.releasedButtons
        value.source_mask = input.sourceMask
        return value
    }

    public func takeRestoreSnapshot() -> GoldenEyeRamRomGameplayRestoreSnapshotV6? {
        guard let frame = lastFrame else { return nil }
        let snapshot = GoldenEyeRamRomGameplayRestoreSnapshotV6(
            nativeTick: frame.nativeTick, gameplay: frame.gameplaySnapshot,
            playerCamera: frame.playerCamera.sourceSnapshot
        )
        restoreSnapshot = snapshot
        active = false
        return snapshot
    }

    public func restore(_ snapshot: GoldenEyeRamRomGameplayRestoreSnapshotV6) throws {
        guard snapshot.gameplay.demo_id == request.demoID,
              snapshot.gameplay.stage_id == request.stageID else {
            throw GoldenEyeRamRomGameplayOrchestratorErrorV6.restoreMismatch
        }
        var gameplaySnapshot = snapshot.gameplay
        let gameplayStatus = ge_ramrom_gameplay_v6_restore(&gameplayState, &gameplaySnapshot)
        guard gameplayStatus == UInt32(GE_STATUS_OK) else {
            throw GoldenEyeRamRomGameplayOrchestratorErrorV6.cStatus(gameplayStatus, "restore")
        }
        try playerOwner.restore(snapshot: snapshot.playerCamera)
        expectedRelativeTick = snapshot.nativeTick >= startNativeTick
            ? snapshot.nativeTick - startNativeTick + 1
            : 0
        active = true
        restoreSnapshot = nil
    }

    private static func makeFrame(
        nativeTick: UInt64, request: GoldenEyeRamRomLaunchRequest,
        gameplaySnapshot: GERamRomGameplaySnapshotV6,
        gameplayEvent: GERamRomGameplayEventV6,
        playerCamera: GoldenEyeRamRomPlayerCameraPublicationV6,
        guardDoorHash: UInt64, weaponEffectHash: UInt64,
        readiness: GoldenEyeRamRomGameplayReadinessV6
    ) -> GoldenEyeRamRomGameplayFrameV6 {
        let hash = mixWords([
            nativeTick, UInt64(gameplaySnapshot.state_hash), playerCamera.ownerStateHash,
            guardDoorHash, weaponEffectHash, UInt64(readiness.missingFields.count),
        ])
        return GoldenEyeRamRomGameplayFrameV6(
            nativeTick: nativeTick, referenceTick: nativeTick >> 1,
            pairPhase: UInt32(nativeTick & 1), demoID: UInt32(request.demoID),
            stageID: request.stageID, gameplaySnapshot: gameplaySnapshot,
            gameplayEvent: gameplayEvent, playerCamera: playerCamera,
            guardDoorEventHash: guardDoorHash, weaponEffectEventHash: weaponEffectHash,
            readiness: readiness, stateHash: hash
        )
    }

    private static func sourceSlot(stageID: UInt32) -> UInt32 {
        switch stageID {
        case 9, 25: return 0
        default: return 1
        }
    }

    private static func weaponModels(
        sidecars: GoldenEyeStageModelSidecarCatalogV6
    ) -> [String: GoldenEyeSourceModelV6] {
        var result: [String: GoldenEyeSourceModelV6] = [:]
        for row in GoldenEyeRamRomSourceWeaponMappingV6.table {
            guard let alias = row.modelAlias else { continue }
            let suffix = "_\(alias)"
            if let match = sidecars.models.first(where: { $0.key.hasSuffix(suffix) }) {
                result[alias] = match.value
            }
        }
        return result
    }

    private static func noInput() -> GERamRomGameplayInputV6 {
        var value = GERamRomGameplayInputV6()
        value.header.abi_version = GE_NATIVE_ABI_VERSION
        value.header.struct_size = UInt32(MemoryLayout<GERamRomGameplayInputV6>.size)
        value.record_version = UInt32(GE_RAMROM_GAMEPLAY_V6_RECORD_VERSION)
        value.flags = UInt32(GE_RAMROM_GAMEPLAY_V6_INPUT_RECORDED) |
            UInt32(GE_RAMROM_GAMEPLAY_V6_INPUT_FOCUSED) |
            UInt32(GE_RAMROM_GAMEPLAY_V6_INPUT_CONTROLLER)
        value.controller_count = 1
        value.controller_index = 0
        value.source_mask = UInt32(GE_RAMROM_GAMEPLAY_V6_INPUT_CONTROLLER)
        return value
    }

    private static func inputFromGameplaySnapshot(
        _ snapshot: GERamRomGameplaySnapshotV6
    ) -> GERamRomGameplayInputV6 {
        var input = noInput()
        input.stick_x = snapshot.pair_phase == 0 ? snapshot.input_stick_x : 0
        input.stick_y = snapshot.pair_phase == 0 ? snapshot.input_stick_y : 0
        input.pressed_buttons = snapshot.pair_phase == 0 ? snapshot.input_buttons : 0
        input.held_buttons = snapshot.pair_phase == 0 ? snapshot.input_buttons : 0
        return input
    }

    private func gameplayInputForWeapon(
        gameplayEvent: GERamRomGameplayEventV6
    ) -> GERamRomGameplayInputV6 {
        var input = Self.noInput()
        input.stick_x = gameplayEvent.stick_x
        input.stick_y = gameplayEvent.stick_y
        input.pressed_buttons = gameplayEvent.buttons
        input.held_buttons = gameplayEvent.buttons
        return input
    }

    private static func mixWords(_ values: [UInt64]) -> UInt64 {
        values.reduce(UInt64(1_469_598_103_934_665_603)) { hash, value in
            var result = hash
            for shift in stride(from: 0, to: 64, by: 8) {
                result = (result ^ ((value >> UInt64(shift)) & 0xff)) &* 1_099_511_628_211
            }
            return result
        }
    }
}
