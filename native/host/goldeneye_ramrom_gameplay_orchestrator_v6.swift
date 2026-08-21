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

/// Copied dynamic door state available to the scoped stage renderer. This is
/// intentionally separate from guard readiness and carries no C pointer.
public struct GoldenEyeRamRomDoorTransformV7: Sendable, Equatable {
    public let sourceRecordOffset: UInt32
    public let objectID: UInt32
    public let modelHandle: UInt32
    public let portalNumber: UInt32
    public let openState: UInt32
    public let openPositionQ16: Int32
    public let transformQ16: [Int32]
    public let sourceAnchor: Bool
    public let interpolated: Bool
    public let sourceHash: UInt64
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
    public let dynamicDoors: [GoldenEyeRamRomDoorTransformV7]
    public private(set) var readiness: GoldenEyeRamRomGameplayReadinessV6
    public let stateHash: UInt64
}

public struct GoldenEyeRamRomGameplayRestoreSnapshotV6 {
    public let nativeTick: UInt64
    public let gameplay: GERamRomGameplaySnapshotV6
    public let playerCamera: GEPlayerCameraSnapshotV6
    /// Copied door-only owner state keeps dynamic door transforms coherent
    /// across rewind without exposing the large C owner allocation.
    public let dynamicDoors: [GoldenEyeRamRomDoorTransformV7]
    public let doorOwnerStateBytes: Data?
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
    private var doorOnlyOwner: UnsafeMutablePointer<GEGuardDoorOwnerStateV6>?
    private let ownsDoorOnlyOwner: Bool
    private let doorSourceRows: [GEGuardDoorOwnerDoorSourceV6]
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
        doorOnlyOwner: UnsafeMutablePointer<GEGuardDoorOwnerStateV6>? = nil,
        doorSourceRows: [GEGuardDoorOwnerDoorSourceV6] = [],
        weaponSetup: GERamRomWeaponEffectSetupV6? = nil,
        weaponInitialFrame: GERamRomWeaponEffectFrameV6? = nil,
        weaponFrames: [UInt64: GERamRomWeaponEffectFrameV6] = [:],
        additionalMissingFields: [String] = [],
        ownsGuardDoorOwner: Bool = false,
        ownsDoorOnlyOwner: Bool = false
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
        self.doorOnlyOwner = doorOnlyOwner
        self.ownsDoorOnlyOwner = ownsDoorOnlyOwner
        self.doorSourceRows = doorSourceRows
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
            dynamicDoors: dynamicDoorPublications(),
            readiness: readiness
        )
    }

    deinit {
        if ownsGuardDoorOwner, let pointer = guardDoorOwner {
            pointer.deinitialize(count: 1)
            pointer.deallocate()
        }
        if ownsDoorOnlyOwner, let pointer = doorOnlyOwner {
            UnsafeMutableRawPointer(pointer).deallocate()
        }
    }

    private func stepDoorOwner(relativeTick: UInt64) throws {
        guard let pointer = doorOnlyOwner, relativeTick > 0 else { return }
        var event = GEGuardDoorOwnerEventV6()
        let doorCount = pointer.pointee.door_count
        let status: UInt32
        if relativeTick & 1 == 1 {
            status = ge_guard_door_owner_v6_step(
                relativeTick, nil, 0, nil, doorCount, nil, 0, nil, 0,
                pointer, &event
            )
        } else {
            status = doorSourceRows.withUnsafeBufferPointer { doorBuffer in
                ge_guard_door_owner_v6_step(
                    relativeTick, nil, 0, doorBuffer.baseAddress, doorCount,
                    nil, 0, nil, 0, pointer, &event
                )
            }
        }
        guard status == UInt32(GE_STATUS_OK) else {
            throw GoldenEyeRamRomGameplayOrchestratorErrorV6.cStatus(status, "door owner step")
        }
    }

    private func dynamicDoorPublications() -> [GoldenEyeRamRomDoorTransformV7] {
        guard let pointer = doorOnlyOwner else { return [] }
        let total = Int(pointer.pointee.door_count)
        guard total > 0 else { return [] }
        var result: [GoldenEyeRamRomDoorTransformV7] = []
        var first = 0
        while first < total {
            let capacity = min(Int(GE_GUARD_DOOR_OWNER_V6_PAGE_ITEMS), total - first)
            var states = Array(repeating: GEGuardDoorOwnerDoorStateV6(), count: capacity)
            var copied: UInt32 = 0
            let status = states.withUnsafeMutableBufferPointer { buffer in
                ge_guard_door_owner_v6_copy_door_page(
                    pointer, UInt32(first), UInt32(capacity), buffer.baseAddress, &copied
                )
            }
            guard status == UInt32(GE_STATUS_OK), copied > 0 else {
                return []
            }
            result.append(contentsOf: states.prefix(Int(copied)).map { state in
                GoldenEyeRamRomDoorTransformV7(
                    sourceRecordOffset: state.source.source_record_offset,
                    objectID: state.source.object_id,
                    modelHandle: state.source.model_handle,
                    portalNumber: state.source.portal_number,
                    openState: state.source.open_state,
                    openPositionQ16: state.source.open_position_q16,
                    transformQ16: Self.int32Values(state.transform_q16),
                    sourceAnchor: state.source_anchor != 0,
                    interpolated: state.interpolated != 0,
                    sourceHash: state.source.source_hash64
                )
            })
            first += Int(copied)
        }
        return result
    }

    private static func int32Values<T>(_ value: T) -> [Int32] {
        withUnsafeBytes(of: value) { Array($0.bindMemory(to: Int32.self)) }
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
        var doorOnlyPointer: UnsafeMutablePointer<GEGuardDoorOwnerStateV6>?
        var doorSourceRows: [GEGuardDoorOwnerDoorSourceV6] = []
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
            do {
                let allocation = try GoldenEyeRamRomGuardDoorPagesV6.makeDoorOnlyOwnerPointer(
                    from: guardPages, rngSeed: UInt64(header.randomizer_seed)
                )
                doorOnlyPointer = allocation.pointer
                doorSourceRows = allocation.doors
                if allocation.skippedDoorCount > 0 {
                    missing.append("door_owner_skipped_invalid_rows_\(allocation.skippedDoorCount)")
                }
            } catch {
                missing.append("door_owner_v7: \(error)")
            }
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
        do {
            return try Self(
                request: request, recording: recording, pages: playerPages,
                atNativeTick: nativeTick, guardDoorOwner: guardPointer,
                doorOnlyOwner: doorOnlyPointer,
                doorSourceRows: guardPointer == nil ? doorSourceRows : guardPages.doors,
                additionalMissingFields: Array(Set(missing)).sorted(),
                ownsGuardDoorOwner: guardPointer != nil,
                ownsDoorOnlyOwner: doorOnlyPointer != nil
            )
        } catch {
            if let pointer = guardPointer {
                pointer.deinitialize(count: 1)
                pointer.deallocate()
            }
            if let pointer = doorOnlyPointer {
                UnsafeMutableRawPointer(pointer).deallocate()
            }
            throw error
        }
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
        try stepDoorOwner(relativeTick: expectedRelativeTick)
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
        let playerCameraSnapshot = playerOwner.snapshot
        var gameplayPlayerCameraSnapshot = Self.gameplayPlayerCameraSnapshot(
            from: playerCameraSnapshot
        )
        let playerCameraStatus = withUnsafeMutablePointer(to: &gameplayState) { statePointer in
            return withUnsafeMutablePointer(to: &gameplayPlayerCameraSnapshot) { cameraPointer in
                withUnsafeMutablePointer(to: &gameplayEvent) { eventPointer in
                    ge_ramrom_gameplay_v6_apply_player_camera_snapshot_v7(
                        statePointer, cameraPointer, eventPointer
                    )
                }
            }
        }
        guard playerCameraStatus == UInt32(GE_STATUS_OK) else {
            throw GoldenEyeRamRomGameplayOrchestratorErrorV6.cStatus(
                playerCameraStatus, "apply player camera snapshot"
            )
        }
        let rebasedPublication = GoldenEyeRamRomPlayerCameraPublicationV6(
            snapshot: playerCameraSnapshot, nativeTickOverride: nativeTick
        )
        var snapshot = GERamRomGameplaySnapshotV6()
        _ = ge_ramrom_gameplay_v6_copy_snapshot(&gameplayState, &snapshot)
        let frame = Self.makeFrame(
            nativeTick: nativeTick, request: request, gameplaySnapshot: snapshot,
            gameplayEvent: gameplayEvent, playerCamera: rebasedPublication,
            guardDoorHash: guardDoorOwner?.pointee.state_hash ?? 0,
            weaponEffectHash: weaponEventHash,
            dynamicDoors: dynamicDoorPublications(),
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
        let doorOwnerStateBytes: Data?
        if let pointer = doorOnlyOwner {
            doorOwnerStateBytes = Data(
                bytes: UnsafeRawPointer(pointer),
                count: MemoryLayout<GEGuardDoorOwnerStateV6>.stride
            )
        } else {
            doorOwnerStateBytes = nil
        }
        let snapshot = GoldenEyeRamRomGameplayRestoreSnapshotV6(
            nativeTick: frame.nativeTick, gameplay: frame.gameplaySnapshot,
            playerCamera: frame.playerCamera.sourceSnapshot,
            dynamicDoors: frame.dynamicDoors,
            doorOwnerStateBytes: doorOwnerStateBytes
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
        if let bytes = snapshot.doorOwnerStateBytes {
            guard let pointer = doorOnlyOwner,
                  bytes.count == MemoryLayout<GEGuardDoorOwnerStateV6>.stride else {
                throw GoldenEyeRamRomGameplayOrchestratorErrorV6.restoreMismatch
            }
            bytes.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                UnsafeMutableRawPointer(pointer).copyMemory(
                    from: base, byteCount: MemoryLayout<GEGuardDoorOwnerStateV6>.stride
                )
            }
            guard dynamicDoorPublications() == snapshot.dynamicDoors else {
                throw GoldenEyeRamRomGameplayOrchestratorErrorV6.restoreMismatch
            }
        } else if !snapshot.dynamicDoors.isEmpty || doorOnlyOwner != nil {
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
        dynamicDoors: [GoldenEyeRamRomDoorTransformV7],
        readiness: GoldenEyeRamRomGameplayReadinessV6
    ) -> GoldenEyeRamRomGameplayFrameV6 {
        let hash = mixWords([
            nativeTick, UInt64(gameplaySnapshot.state_hash), playerCamera.ownerStateHash,
            guardDoorHash, weaponEffectHash, UInt64(dynamicDoors.count),
            dynamicDoors.reduce(UInt64(0)) { hash, door in
                mixWords([hash, UInt64(door.sourceRecordOffset), UInt64(door.openPositionQ16),
                          UInt64(door.openState), UInt64(door.portalNumber)] +
                    door.transformQ16.map { UInt64(bitPattern: Int64($0)) } + [door.sourceHash])
            },
            UInt64(readiness.missingFields.count),
        ])
        return GoldenEyeRamRomGameplayFrameV6(
            nativeTick: nativeTick, referenceTick: nativeTick >> 1,
            pairPhase: UInt32(nativeTick & 1), demoID: UInt32(request.demoID),
            stageID: request.stageID, gameplaySnapshot: gameplaySnapshot,
            gameplayEvent: gameplayEvent, playerCamera: playerCamera,
            guardDoorEventHash: guardDoorHash, weaponEffectEventHash: weaponEffectHash,
            dynamicDoors: dynamicDoors,
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

    private static func gameplayPlayerCameraSnapshot(
        from source: GEPlayerCameraSnapshotV6
    ) -> GERamRomGameplayPlayerCameraSnapshotV7 {
        var value = GERamRomGameplayPlayerCameraSnapshotV7()
        value.header.abi_version = source.header.abi_version
        value.header.struct_size = UInt32(
            MemoryLayout<GERamRomGameplayPlayerCameraSnapshotV7>.size
        )
        value.record_version = UInt32(GE_RAMROM_GAMEPLAY_PLAYER_CAMERA_V7_RECORD_VERSION)
        value.flags = source.flags
        value.demo_id = source.demo_id
        value.stage_id = source.stage_id
        value.native_tick = source.native_tick
        value.reference_tick = source.reference_tick
        value.pair_phase = source.pair_phase
        value.source_anchor = source.source_anchor
        value.current_room = source.current_room
        value.current_pad = source.current_pad
        value.weapon_model_handle = source.weapon_model_handle
        value.weapon_action = source.weapon_action
        value.player_health = source.player_health
        value.hud_ammo = source.hud_ammo
        value.player_animation = source.player_animation
        value.player_position_q16 = source.player_position_q16
        value.player_velocity_q16 = source.player_velocity_q16
        value.camera_position_q16 = source.camera_position_q16
        value.camera_forward_q16 = source.camera_forward_q16
        value.camera_up_q16 = source.camera_up_q16
        value.yaw_q16 = source.yaw_q16
        value.pitch_q16 = source.pitch_q16
        value.source_hash = source.source_hash
        value.state_hash = source.state_hash
        value.render_hash = source.render_hash
        value.reserved0 = source.reserved0
        value.reserved1 = source.reserved1
        return value
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
