import Foundation

#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

/// The dynamic RAMROM scene seam is intentionally a composition contract, not
/// a renderer.  It joins immutable owner snapshots to corrected GESM model
/// catalogs and produces source-scene compilation results plus ordered
/// instance/effect records.  Missing pages remain diagnostics; no model,
/// pose, attachment, intro item mapping, texture, or effect is guessed.
enum GoldenEyeRamRomDynamicSceneKindV6: UInt32, Sendable, Equatable, CaseIterable {
    case player = 1
    case guardCharacter = 2
    case door = 3
    case weapon = 4
    case projectile = 5
    case effect = 6
    case hud = 7
    case watch = 8
    case fade = 9
    case sfx = 10

    var order: UInt32 { rawValue }
}

struct GoldenEyeRamRomDynamicSceneModelResultV6: Sendable, Equatable {
    let role: GoldenEyeRamRomDynamicSceneKindV6
    let entityID: UInt32
    let modelName: String
    let modelHandle: UInt32
    let sourceScene: GESourceSceneV6?
    let commandCount: UInt32
    let vertexCount: UInt32
    let textureCount: UInt32
    let unsupportedCount: UInt32
    let sourceHash: UInt64
    let sceneHash: UInt64
    let missingFields: [String]

    var presentable: Bool {
        sourceScene != nil && unsupportedCount == 0 && missingFields.isEmpty
    }
}

struct GoldenEyeRamRomDynamicSceneAttachmentV6: Sendable, Equatable {
    let modelName: String
    let modelHandle: UInt32
    let parentJoint: UInt32
    let sourceMatrixHandle: UInt32
    let transformQ16: [Int32]
    let sourceHash: UInt64
}

struct GoldenEyeRamRomDynamicSceneElementV6: Sendable, Equatable {
    let kind: GoldenEyeRamRomDynamicSceneKindV6
    let sourceOrder: UInt32
    let entityID: UInt32
    let modelName: String?
    let modelHandle: UInt32
    let animationID: UInt32
    let animationFrameQ16: Int32
    let transformQ16: [Int32]
    let attachments: [GoldenEyeRamRomDynamicSceneAttachmentV6]
    let resourceHandle: UInt32
    let imageHandle: UInt32
    let sourceEventID: UInt32
    let frameIndex: UInt32
    let colourRGBA8: UInt32
    let alphaQ16: UInt32
    let sourceHash: UInt64
    let missingFields: [String]

    var presentable: Bool { missingFields.isEmpty }
}

struct GoldenEyeRamRomDynamicSceneVisualRecordV6: Sendable, Equatable {
    let kind: GoldenEyeRamRomDynamicSceneKindV6
    let sourceOrder: UInt32
    let entityID: UInt32
    let resourceHandle: UInt32
    let imageHandle: UInt32
    let frameIndex: UInt32
    let positionQ16: [Int32]
    let scaleQ16: UInt32
    let rotationQ16: Int32
    let colourRGBA8: UInt32
    let alphaQ16: UInt32
    let sourceSFXID: UInt32
    let sourceHash: UInt64
    let missingFields: [String]
}

struct GoldenEyeRamRomDynamicSceneReadinessV6: Sendable, Equatable {
    let gameplaySnapshot: Bool
    let playerCameraSnapshot: Bool
    let guardDoorSnapshot: Bool
    let weaponEffectSnapshot: Bool
    let introItemToModelMapping: Bool
    let stageModelSidecars: Bool
    let setupDependencies: Bool
    let visibleDependencies: Bool
    let castGESMCatalog: Bool
    let posePages: Bool
    let effectPages: Bool

    var isComplete: Bool {
        gameplaySnapshot && playerCameraSnapshot && guardDoorSnapshot &&
            weaponEffectSnapshot && introItemToModelMapping && stageModelSidecars &&
            setupDependencies && visibleDependencies && castGESMCatalog && posePages && effectPages
    }

    var missingFields: [String] {
        var values: [String] = []
        if !gameplaySnapshot { values.append("gameplay.snapshot") }
        if !playerCameraSnapshot { values.append("player_camera.snapshot") }
        if !guardDoorSnapshot { values.append("guard_door.snapshot") }
        if !weaponEffectSnapshot { values.append("weapon_effect.snapshot") }
        if !introItemToModelMapping { values.append("intro.item_to_render_model") }
        if !stageModelSidecars { values.append("stage_model_sidecars.complete") }
        if !setupDependencies { values.append("stage_setup_dependencies.complete") }
        if !visibleDependencies { values.append("ramrom_visible_dependencies.complete") }
        if !castGESMCatalog { values.append("cast_gesm_catalog.complete") }
        if !posePages { values.append("guard.pose_pages") }
        if !effectPages { values.append("weapon_effect.pages") }
        return values
    }
}

struct GoldenEyeRamRomDynamicGameplaySnapshotV6: Sendable, Equatable {
    let stageID: UInt32
    let demoID: UInt32
    let nativeTick: UInt64
    let sourceFrame: UInt32
    let stateHash: UInt64
    let playerWeaponHandle: UInt32
    let playerAnimationID: UInt32
    let guardCount: UInt32
    let doorCount: UInt32
    let effectCount: UInt32
    let projectileCount: UInt32

    init(_ value: GERamRomGameplaySnapshotV6) throws {
        var copy = value
        guard ge_ramrom_gameplay_v6_validate_snapshot(&copy) == GE_STATUS_OK else {
            throw GoldenEyeRamRomDynamicSceneError.invalidOwnerSnapshot("gameplay")
        }
        stageID = UInt32(value.stage_id); demoID = UInt32(value.demo_id)
        nativeTick = UInt64(value.native_tick); sourceFrame = UInt32(value.source_frame)
        stateHash = UInt64(value.state_hash)
        playerWeaponHandle = UInt32(value.player_weapon)
        playerAnimationID = UInt32(value.player_animation)
        guardCount = UInt32(value.guard_count); doorCount = UInt32(value.door_count)
        effectCount = UInt32(value.effect_count); projectileCount = UInt32(value.projectile_count)
    }
}

struct GoldenEyeRamRomDynamicPlayerCameraSnapshotV6: Sendable, Equatable {
    let stageID: UInt32
    let nativeTick: UInt64
    let currentRoom: UInt32
    let playerPositionQ16: [Int32]
    let cameraPositionQ16: [Int32]
    let cameraForwardQ16: [Int32]
    let stateHash: UInt64

    init(_ value: GEPlayerCameraSnapshotV6) throws {
        var copy = value
        guard ge_player_camera_owner_validate_snapshot(&copy) == GE_STATUS_OK else {
            throw GoldenEyeRamRomDynamicSceneError.invalidOwnerSnapshot("player_camera")
        }
        stageID = UInt32(value.stage_id); nativeTick = UInt64(value.native_tick)
        currentRoom = UInt32(value.current_room)
        playerPositionQ16 = Self.words(value.player_position_q16)
        cameraPositionQ16 = Self.words(value.camera_position_q16)
        cameraForwardQ16 = Self.words(value.camera_forward_q16)
        stateHash = UInt64(value.state_hash)
    }

    private static func words<T>(_ tuple: T) -> [Int32] {
        withUnsafeBytes(of: tuple) { Array($0.bindMemory(to: Int32.self)) }
    }
}

struct GoldenEyeRamRomDynamicGuardSnapshotV6: Sendable, Equatable {
    let entityID: UInt32
    let bodyModelHandle: UInt32
    let headModelHandle: UInt32
    let weaponModelHandle: UInt32
    let skeletonHandle: UInt32
    let animationID: UInt32
    let animationFrameQ16: Int32
    let poseCount: UInt32
    let sourceAnchor: Bool
    let interpolated: Bool
    let transformQ16: [Int32]
    let attachments: [GoldenEyeRamRomDynamicSceneAttachmentV6]
    let sourceHash: UInt64

    init(_ value: GEGuardDoorOwnerGuardStateV6, entityID: UInt32) {
        let source = value.source
        self.entityID = entityID
        bodyModelHandle = UInt32(source.body_model_handle)
        headModelHandle = UInt32(source.head_model_handle)
        weaponModelHandle = UInt32(source.weapon_model_handle)
        skeletonHandle = UInt32(source.skeleton_handle)
        animationID = UInt32(source.animation_id)
        animationFrameQ16 = Int32(source.animation_frame_q16)
        poseCount = UInt32(value.pose_count)
        sourceAnchor = value.source_anchor != 0
        interpolated = value.interpolated != 0
        transformQ16 = Self.words(source.world_transform_q16)
        let attachmentRows = Self.words(value.attachments, as: GEGuardDoorOwnerAttachmentV6.self)
        attachments = attachmentRows.prefix(Int(source.attachment_count)).map {
            GoldenEyeRamRomDynamicSceneAttachmentV6(
                modelName: "", modelHandle: UInt32($0.model_handle),
                parentJoint: UInt32($0.parent_joint), sourceMatrixHandle: UInt32($0.source_matrix_handle),
                transformQ16: Self.words($0.transform_q16), sourceHash: UInt64($0.source_hash)
            )
        }
        sourceHash = UInt64(source.source_hash)
    }

    private static func words<T>(_ tuple: T) -> [Int32] {
        withUnsafeBytes(of: tuple) { Array($0.bindMemory(to: Int32.self)) }
    }

    private static func words<T, V>(_ tuple: T, as: V.Type) -> [V] {
        withUnsafeBytes(of: tuple) { Array($0.bindMemory(to: V.self)) }
    }
}

struct GoldenEyeRamRomDynamicDoorSnapshotV6: Sendable, Equatable {
    let entityID: UInt32
    let modelHandle: UInt32
    let transformQ16: [Int32]
    let sourceHash: UInt64
    let sourceAnchor: Bool
    let interpolated: Bool
}

struct GoldenEyeRamRomDynamicGuardDoorSnapshotV6: Sendable, Equatable {
    let stageID: UInt32
    let demoID: UInt32
    let nativeTick: UInt64
    let sourceAnchor: Bool
    let interpolated: Bool
    let guards: [GoldenEyeRamRomDynamicGuardSnapshotV6]
    let doors: [GoldenEyeRamRomDynamicDoorSnapshotV6]
    let stateHash: UInt64
    let eventHash: UInt64

    init(_ value: GEGuardDoorOwnerStateV6) throws {
        let copy = value
        guard copy.header.abi_version == GE_NATIVE_ABI_VERSION,
              copy.header.struct_size == UInt32(MemoryLayout<GEGuardDoorOwnerStateV6>.size),
              copy.record_version == GE_GUARD_DOOR_OWNER_V6_RECORD_VERSION,
              copy.guard_count <= GE_GUARD_DOOR_OWNER_V6_MAX_GUARDS,
              copy.door_count <= GE_GUARD_DOOR_OWNER_V6_MAX_DOORS,
              copy.state_hash != 0 else {
            throw GoldenEyeRamRomDynamicSceneError.invalidOwnerSnapshot("guard_door")
        }
        stageID = UInt32(value.stage_id); demoID = UInt32(value.demo_id)
        nativeTick = UInt64(value.native_tick)
        sourceAnchor = value.source_anchor != 0; interpolated = value.pair_phase != 0
        let guardRows = Self.words(value.guards, as: GEGuardDoorOwnerGuardStateV6.self)
        guards = guardRows.prefix(Int(value.guard_count)).enumerated().map {
            GoldenEyeRamRomDynamicGuardSnapshotV6($0.element, entityID: UInt32($0.offset + 1))
        }
        let doorRows = Self.words(value.doors, as: GEGuardDoorOwnerDoorStateV6.self)
        doors = doorRows.prefix(Int(value.door_count)).enumerated().map { index, row in
            GoldenEyeRamRomDynamicDoorSnapshotV6(
                entityID: UInt32(index + 0x1000), modelHandle: UInt32(row.source.model_handle),
                transformQ16: Self.words(row.transform_q16), sourceHash: UInt64(row.source.source_hash64),
                sourceAnchor: row.source_anchor != 0, interpolated: row.interpolated != 0
            )
        }
        stateHash = UInt64(value.state_hash); eventHash = UInt64(value.event_hash)
    }

    private static func words<T>(_ tuple: T) -> [Int32] {
        withUnsafeBytes(of: tuple) { Array($0.bindMemory(to: Int32.self)) }
    }

    private static func words<T, V>(_ tuple: T, as: V.Type) -> [V] {
        withUnsafeBytes(of: tuple) { Array($0.bindMemory(to: V.self)) }
    }
}

struct GoldenEyeRamRomDynamicWeaponHandSnapshotV6: Sendable, Equatable {
    let handIndex: UInt32
    let weaponID: UInt32
    let modelHandle: UInt32
    let animationID: UInt32
    let animationFrameQ16: Int32
    let magazine: UInt32
    let reserve: UInt32
    let sourceHash: UInt64
}

struct GoldenEyeRamRomDynamicWeaponEventSnapshotV6: Sendable, Equatable {
    let category: UInt32
    let flags: UInt32
    let sourceEventID: UInt32
    let resourceHandle: UInt32
    let sourceResourceID: UInt32
    let imageHandle: UInt32
    let sourceSFXID: UInt32
    let sequence: UInt32
    let frameIndex: UInt32
    let positionQ16: [Int32]
    let scaleQ16: UInt32
    let rotationQ16: Int32
    let colourRGBA8: UInt32
    let alphaQ16: UInt32
    let sourceHash: UInt64
}

struct GoldenEyeRamRomDynamicWeaponEffectSnapshotV6: Sendable, Equatable {
    let stageID: UInt32
    let demoID: UInt32
    let nativeTick: UInt64
    let sourceAnchor: Bool
    let rightWeaponID: UInt32
    let rightModelHandle: UInt32
    let hands: [GoldenEyeRamRomDynamicWeaponHandSnapshotV6]
    let events: [GoldenEyeRamRomDynamicWeaponEventSnapshotV6]
    let rightHUDImageHandle: UInt32
    let leftHUDImageHandle: UInt32
    let rightHUDWidth: UInt32
    let rightHUDHeight: UInt32
    let leftHUDWidth: UInt32
    let leftHUDHeight: UInt32
    let viewLeftQ16: Int32
    let viewTopQ16: Int32
    let viewWidthQ16: UInt32
    let viewHeightQ16: UInt32
    let crosshairImageHandle: UInt32
    let crosshairXQ16: Int32
    let crosshairYQ16: Int32
    let hudVisible: Bool
    let sightVisible: Bool
    let watchVisible: Bool
    let watchModelHandle: UInt32
    let fadeVisible: Bool
    let fadeQ16: UInt32
    let sourceHash: UInt64
    let stateHash: UInt64
    let renderHash: UInt64
    let audioHash: UInt64

    init(_ value: GERamRomWeaponEffectOwnerStateV6) throws {
        var copy = value
        guard ge_ramrom_weapon_effect_v6_validate_state(&copy) == GE_STATUS_OK else {
            throw GoldenEyeRamRomDynamicSceneError.invalidOwnerSnapshot("weapon_effect")
        }
        let frame = value.render_frame
        stageID = UInt32(frame.stage_id); demoID = UInt32(frame.demo_id)
        nativeTick = UInt64(frame.native_tick); sourceAnchor = frame.source_anchor != 0
        rightWeaponID = UInt32(frame.hands.0.weapon_id); rightModelHandle = UInt32(frame.hands.0.model_handle)
        let handRows = Self.words(frame.hands, as: GERamRomWeaponHandV6.self)
        hands = handRows.prefix(Int(frame.hand_count)).map {
            GoldenEyeRamRomDynamicWeaponHandSnapshotV6(
                handIndex: UInt32($0.hand_index), weaponID: UInt32($0.weapon_id),
                modelHandle: UInt32($0.model_handle), animationID: UInt32($0.animation_id),
                animationFrameQ16: Int32($0.animation_frame_q16), magazine: UInt32($0.magazine),
                reserve: UInt32($0.reserve), sourceHash: UInt64($0.source_hash)
            )
        }
        let eventRows = Self.words(frame.events, as: GERamRomWeaponEffectEventV6.self)
        events = eventRows.prefix(Int(frame.event_count)).map {
            GoldenEyeRamRomDynamicWeaponEventSnapshotV6(
                category: UInt32($0.category), flags: UInt32($0.flags), sourceEventID: UInt32($0.source_event_id),
                resourceHandle: UInt32($0.resource_handle), sourceResourceID: UInt32($0.source_resource_id),
                imageHandle: UInt32($0.image_handle), sourceSFXID: UInt32($0.source_sfx_id),
                sequence: UInt32($0.sequence), frameIndex: UInt32($0.frame_index),
                positionQ16: Self.words($0.position_q16), scaleQ16: UInt32($0.scale_q16.0),
                rotationQ16: Int32($0.rotation_q16.1), colourRGBA8: UInt32($0.colour_rgba),
                alphaQ16: UInt32($0.alpha_q16), sourceHash: UInt64($0.source_hash)
            )
        }
        rightHUDImageHandle = UInt32(frame.right_hud_image_handle)
        leftHUDImageHandle = UInt32(frame.left_hud_image_handle)
        rightHUDWidth = UInt32(frame.right_hud_width); rightHUDHeight = UInt32(frame.right_hud_height)
        leftHUDWidth = UInt32(frame.left_hud_width); leftHUDHeight = UInt32(frame.left_hud_height)
        viewLeftQ16 = Int32(frame.view_left_q16); viewTopQ16 = Int32(frame.view_top_q16)
        viewWidthQ16 = UInt32(frame.view_width_q16); viewHeightQ16 = UInt32(frame.view_height_q16)
        crosshairImageHandle = UInt32(frame.crosshair_image_handle)
        crosshairXQ16 = Int32(frame.crosshair_x_q16); crosshairYQ16 = Int32(frame.crosshair_y_q16)
        hudVisible = frame.hud_visible != 0; sightVisible = frame.sight_visible != 0
        watchVisible = frame.watch_visible != 0; watchModelHandle = UInt32(frame.watch_model_handle)
        fadeVisible = frame.fade_visible != 0; fadeQ16 = UInt32(frame.fade_q16)
        sourceHash = UInt64(value.source_hash); stateHash = UInt64(value.snapshot.state_hash)
        renderHash = UInt64(value.snapshot.render_hash); audioHash = UInt64(value.snapshot.resource_hash)
    }

    /// Join point for the additive source-page builder. The frame is already
    /// validated by the C owner; publication hashes remain caller-supplied.
    init(
        sourceFrame value: GERamRomWeaponEffectFrameV6,
        stateHash: UInt64,
        renderHash: UInt64,
        audioHash: UInt64
    ) throws {
        var frame = value
        guard ge_ramrom_weapon_effect_v6_validate_frame(&frame) == GE_STATUS_OK,
              stateHash != 0, renderHash != 0, audioHash != 0 else {
            throw GoldenEyeRamRomDynamicSceneError.invalidOwnerSnapshot("weapon_effect_frame")
        }
        stageID = UInt32(frame.stage_id); demoID = UInt32(frame.demo_id)
        nativeTick = UInt64(frame.native_tick); sourceAnchor = frame.source_anchor != 0
        rightWeaponID = UInt32(frame.hands.0.weapon_id); rightModelHandle = UInt32(frame.hands.0.model_handle)
        let handRows = Self.words(frame.hands, as: GERamRomWeaponHandV6.self)
        hands = handRows.prefix(Int(frame.hand_count)).map {
            GoldenEyeRamRomDynamicWeaponHandSnapshotV6(
                handIndex: UInt32($0.hand_index), weaponID: UInt32($0.weapon_id),
                modelHandle: UInt32($0.model_handle), animationID: UInt32($0.animation_id),
                animationFrameQ16: Int32($0.animation_frame_q16), magazine: UInt32($0.magazine),
                reserve: UInt32($0.reserve), sourceHash: UInt64($0.source_hash)
            )
        }
        let eventRows = Self.words(frame.events, as: GERamRomWeaponEffectEventV6.self)
        events = eventRows.prefix(Int(frame.event_count)).map {
            GoldenEyeRamRomDynamicWeaponEventSnapshotV6(
                category: UInt32($0.category), flags: UInt32($0.flags), sourceEventID: UInt32($0.source_event_id),
                resourceHandle: UInt32($0.resource_handle), sourceResourceID: UInt32($0.source_resource_id),
                imageHandle: UInt32($0.image_handle), sourceSFXID: UInt32($0.source_sfx_id),
                sequence: UInt32($0.sequence), frameIndex: UInt32($0.frame_index),
                positionQ16: Self.words($0.position_q16), scaleQ16: UInt32($0.scale_q16.0),
                rotationQ16: Int32($0.rotation_q16.1), colourRGBA8: UInt32($0.colour_rgba),
                alphaQ16: UInt32($0.alpha_q16), sourceHash: UInt64($0.source_hash)
            )
        }
        rightHUDImageHandle = UInt32(frame.right_hud_image_handle); leftHUDImageHandle = UInt32(frame.left_hud_image_handle)
        rightHUDWidth = UInt32(frame.right_hud_width); rightHUDHeight = UInt32(frame.right_hud_height)
        leftHUDWidth = UInt32(frame.left_hud_width); leftHUDHeight = UInt32(frame.left_hud_height)
        viewLeftQ16 = Int32(frame.view_left_q16); viewTopQ16 = Int32(frame.view_top_q16)
        viewWidthQ16 = UInt32(frame.view_width_q16); viewHeightQ16 = UInt32(frame.view_height_q16)
        crosshairImageHandle = UInt32(frame.crosshair_image_handle)
        crosshairXQ16 = Int32(frame.crosshair_x_q16); crosshairYQ16 = Int32(frame.crosshair_y_q16)
        hudVisible = frame.hud_visible != 0; sightVisible = frame.sight_visible != 0
        watchVisible = frame.watch_visible != 0; watchModelHandle = UInt32(frame.watch_model_handle)
        fadeVisible = frame.fade_visible != 0; fadeQ16 = UInt32(frame.fade_q16)
        sourceHash = UInt64(frame.source_hash); self.stateHash = stateHash
        self.renderHash = renderHash; self.audioHash = audioHash
    }

    private static func words<T>(_ tuple: T) -> [Int32] {
        withUnsafeBytes(of: tuple) { Array($0.bindMemory(to: Int32.self)) }
    }

    private static func words<T, V>(_ tuple: T, as: V.Type) -> [V] {
        withUnsafeBytes(of: tuple) { Array($0.bindMemory(to: V.self)) }
    }
}

struct GoldenEyeRamRomDynamicSceneOwnerInputsV6: Sendable, Equatable {
    let gameplay: GoldenEyeRamRomDynamicGameplaySnapshotV6?
    let playerCamera: GoldenEyeRamRomDynamicPlayerCameraSnapshotV6?
    let guardDoor: GoldenEyeRamRomDynamicGuardDoorSnapshotV6?
    let weaponEffect: GoldenEyeRamRomDynamicWeaponEffectSnapshotV6?
    let playerTransformQ16: [Int32]?
    let watchTransformQ16: [Int32]?
    let introItemToModelHandle: [UInt32: UInt32]

    init(
        gameplay: GoldenEyeRamRomDynamicGameplaySnapshotV6? = nil,
        playerCamera: GoldenEyeRamRomDynamicPlayerCameraSnapshotV6? = nil,
        guardDoor: GoldenEyeRamRomDynamicGuardDoorSnapshotV6? = nil,
        weaponEffect: GoldenEyeRamRomDynamicWeaponEffectSnapshotV6? = nil,
        playerTransformQ16: [Int32]? = nil,
        watchTransformQ16: [Int32]? = nil,
        introItemToModelHandle: [UInt32: UInt32] = [:]
    ) {
        self.gameplay = gameplay; self.playerCamera = playerCamera
        self.guardDoor = guardDoor; self.weaponEffect = weaponEffect
        self.playerTransformQ16 = playerTransformQ16
        self.watchTransformQ16 = watchTransformQ16
        self.introItemToModelHandle = introItemToModelHandle
    }

    static func withWeaponEffectFrame(
        gameplay: GoldenEyeRamRomDynamicGameplaySnapshotV6?,
        playerCamera: GoldenEyeRamRomDynamicPlayerCameraSnapshotV6?,
        guardDoor: GoldenEyeRamRomDynamicGuardDoorSnapshotV6?,
        sourceFrame: GERamRomWeaponEffectFrameV6,
        weaponStateHash: UInt64,
        weaponRenderHash: UInt64,
        weaponAudioHash: UInt64,
        playerTransformQ16: [Int32]?,
        watchTransformQ16: [Int32]?,
        introItemToModelHandle: [UInt32: UInt32]
    ) throws -> Self {
        let weapon = try GoldenEyeRamRomDynamicWeaponEffectSnapshotV6(
            sourceFrame: sourceFrame, stateHash: weaponStateHash,
            renderHash: weaponRenderHash, audioHash: weaponAudioHash
        )
        return Self(
            gameplay: gameplay, playerCamera: playerCamera, guardDoor: guardDoor,
            weaponEffect: weapon, playerTransformQ16: playerTransformQ16,
            watchTransformQ16: watchTransformQ16,
            introItemToModelHandle: introItemToModelHandle
        )
    }
}

enum GoldenEyeRamRomDynamicSceneError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidOwnerSnapshot(String)
    case routeMismatch
    case strictMissing([String])

    var description: String {
        switch self {
        case let .invalidOwnerSnapshot(owner): return "dynamic RAMROM owner snapshot is invalid: \(owner)"
        case .routeMismatch: return "dynamic RAMROM scene route mismatch"
        case let .strictMissing(fields): return "dynamic RAMROM scene is fail-closed: \(fields.joined(separator: ","))"
        }
    }
}

struct GoldenEyeRamRomDynamicSceneResultV6: Sendable, Equatable {
    let stageID: UInt32
    let demoID: UInt8
    let stageName: String
    let nativeTick: UInt64
    let pairPhase: UInt32
    let readiness: GoldenEyeRamRomDynamicSceneReadinessV6
    let elements: [GoldenEyeRamRomDynamicSceneElementV6]
    let visualRecords: [GoldenEyeRamRomDynamicSceneVisualRecordV6]
    let modelResults: [GoldenEyeRamRomDynamicSceneModelResultV6]
    let sourceScenes: [GESourceSceneV6]
    let missingFields: [String]
    let sceneHash: UInt64
    let fixtureOnly: Bool

    var presentable: Bool {
        !fixtureOnly && readiness.isComplete && missingFields.isEmpty &&
            elements.allSatisfy(\.presentable) && modelResults.allSatisfy(\.presentable)
    }

    var fixturePresentable: Bool {
        fixtureOnly && missingFields.isEmpty && elements.count >= 8
    }

    func requirePresentable() throws -> Self {
        guard presentable else { throw GoldenEyeRamRomDynamicSceneError.strictMissing(missingFields) }
        return self
    }
}

/// Additive dynamic source scene composer for the seven-stage/all14 RAMROM
/// attract route.  It resolves only prepared model handles and owner-supplied
/// source pages; it never converts an INTRO item ID, missing pose, or missing
/// effect into a guessed model or billboard.
enum GoldenEyeRamRomDynamicSceneComposerV6 {
    struct Route: Sendable, Equatable {
        let demoID: UInt8
        let stageID: UInt32
        let stageName: String
    }

    static let routes: [Route] = [
        .init(demoID: 1, stageID: 33, stageName: "Dam"),
        .init(demoID: 2, stageID: 33, stageName: "Dam"),
        .init(demoID: 3, stageID: 34, stageName: "Facility"),
        .init(demoID: 4, stageID: 34, stageName: "Facility"),
        .init(demoID: 5, stageID: 34, stageName: "Facility"),
        .init(demoID: 6, stageID: 35, stageName: "Runway"),
        .init(demoID: 7, stageID: 35, stageName: "Runway"),
        .init(demoID: 8, stageID: 9, stageName: "Bunker I"),
        .init(demoID: 9, stageID: 9, stageName: "Bunker I"),
        .init(demoID: 10, stageID: 20, stageName: "Silo"),
        .init(demoID: 11, stageID: 20, stageName: "Silo"),
        .init(demoID: 12, stageID: 26, stageName: "Frigate"),
        .init(demoID: 13, stageID: 26, stageName: "Frigate"),
        .init(demoID: 14, stageID: 25, stageName: "Train"),
    ]

    static func readinessMatrix(
        inputsByDemo: [UInt8: GoldenEyeRamRomDynamicSceneOwnerInputsV6] = [:]
    ) -> [UInt8: GoldenEyeRamRomDynamicSceneReadinessV6] {
        Dictionary(uniqueKeysWithValues: routes.map { route in
            let input = inputsByDemo[route.demoID]
            return (route.demoID, GoldenEyeRamRomDynamicSceneReadinessV6(
                gameplaySnapshot: input?.gameplay != nil,
                playerCameraSnapshot: input?.playerCamera != nil,
                guardDoorSnapshot: input?.guardDoor != nil,
                weaponEffectSnapshot: input?.weaponEffect != nil,
                introItemToModelMapping: !(input?.introItemToModelHandle.isEmpty ?? true),
                stageModelSidecars: false, setupDependencies: false,
                visibleDependencies: false, castGESMCatalog: false,
                posePages: false, effectPages: false
            ))
        })
    }

    static func compose(
        route: Route,
        inputs: GoldenEyeRamRomDynamicSceneOwnerInputsV6,
        sidecars: GoldenEyeStageModelSidecarCatalogV6,
        dependencies: GoldenEyeStageSetupDependencyCatalogV6,
        visibleDependencies: GoldenEyeRamRomVisibleDependencyCatalogV6,
        castCatalog: GoldenEyeCastPreparedAssetCatalogV6? = nil,
        nativeTick: UInt64,
        strict: Bool = false
    ) throws -> GoldenEyeRamRomDynamicSceneResultV6 {
        guard inputs.gameplay?.stageID == nil ||
            (inputs.gameplay?.stageID == route.stageID && inputs.gameplay?.demoID == UInt32(route.demoID)) else {
            throw GoldenEyeRamRomDynamicSceneError.routeMismatch
        }
        var missing = Set<String>()
        let gameplay = inputs.gameplay
        let playerCamera = inputs.playerCamera
        let guardDoor = inputs.guardDoor
        let weapon = inputs.weaponEffect
        if gameplay == nil { missing.insert("gameplay.snapshot") }
        if playerCamera == nil { missing.insert("player_camera.snapshot") }
        if gameplay?.guardCount ?? 0 > 0, guardDoor == nil { missing.insert("guard_door.snapshot") }
        if gameplay?.doorCount ?? 0 > 0, guardDoor == nil { missing.insert("guard_door.snapshot") }
        if gameplay?.playerWeaponHandle ?? 0 != 0, weapon == nil { missing.insert("weapon_effect.snapshot") }
        if gameplay?.effectCount ?? 0 > 0 || gameplay?.projectileCount ?? 0 > 0, weapon == nil {
            missing.insert("weapon_effect.snapshot")
        }
        if !sidecars.isComplete { missing.insert("stage_model_sidecars.complete") }
        if !dependencies.isReady { missing.insert("stage_setup_dependencies.complete") }
        if !visibleDependencies.isComplete { missing.insert("ramrom_visible_dependencies.complete") }
        if castCatalog == nil || (castCatalog?.models.count ?? 0) <= 8 {
            missing.insert("cast_gesm_catalog.complete")
        }
        if inputs.playerTransformQ16?.count != 16 { missing.insert("player.transform_q16") }
        if weapon != nil && weapon?.events.isEmpty == true { missing.insert("weapon_effect.pages") }
        if guardDoor != nil && guardDoor?.guards.contains(where: { $0.poseCount == 0 }) == true {
            missing.insert("guard.pose_pages")
        }

        var elements: [GoldenEyeRamRomDynamicSceneElementV6] = []
        var visuals: [GoldenEyeRamRomDynamicSceneVisualRecordV6] = []
        var models: [GoldenEyeRamRomDynamicSceneModelResultV6] = []
        var scenes: [GESourceSceneV6] = []
        var handleModels = Dictionary(uniqueKeysWithValues: sidecars.models.map { ($0.value.header.modelHandle, ($0.key, $0.value)) })
        var castHandles = Set<UInt32>()
        if let castCatalog {
            for (name, model) in castCatalog.models {
                if let prior = handleModels[model.header.modelHandle], prior.0 != name {
                    missing.insert("model_handle_collision:\(model.header.modelHandle)")
                } else {
                    handleModels[model.header.modelHandle] = (name, model)
                    castHandles.insert(model.header.modelHandle)
                }
            }
        }

        func addModel(
            role: GoldenEyeRamRomDynamicSceneKindV6,
            entityID: UInt32,
            handle: UInt32,
            animationID: UInt32,
            frameQ16: Int32,
            transform: [Int32],
            attachments: [GoldenEyeRamRomDynamicSceneAttachmentV6],
            resourceHandle: UInt32 = 0,
            imageHandle: UInt32 = 0,
            sourceEventID: UInt32 = 0,
            frameIndex: UInt32 = 0,
            colour: UInt32 = 0xffff_ffff,
            alpha: UInt32 = 65_536,
            sourceHash: UInt64
        ) {
            guard transform.count == 16 else {
                missing.insert("(role):(entityID).transform_q16")
                return
            }
            guard let (name, model) = handleModels[handle] else {
                missing.insert("(role):(entityID).model_handle_(handle)")
                return
            }
            let compile = GESourceModelCompilerV6.compile(
                model, modelName: name,
                dynamicResolver: GESourceModelDynamicResolverV6(resolvedModels: [name])
            )
            let modelMissing: [String]
            let scene: GESourceSceneV6?
            let payloadsReady = castHandles.contains(handle) || (
                model.textures.allSatisfy({ sidecars.payload(id: $0.payloadRecordID) != nil }) &&
                model.mips.allSatisfy({ sidecars.payload(id: $0.payloadRecordID) != nil }) &&
                model.tluts.allSatisfy({ sidecars.payload(id: $0.payloadRecordID) != nil })
            )
            if let compiled = compile.scene, compile.diagnostics.isEmpty, payloadsReady {
                scene = compiled
                modelMissing = []
            } else {
                scene = nil
                modelMissing = compile.diagnostics.map(\.description).isEmpty
                    ? ["model:\(name).source_payloads"] : compile.diagnostics.map(\.description)
            }
            let modelResult = GoldenEyeRamRomDynamicSceneModelResultV6(
                role: role, entityID: entityID, modelName: name, modelHandle: handle,
                sourceScene: scene, commandCount: UInt32(scene?.commands.count ?? 0),
                vertexCount: UInt32(scene?.vertices.count ?? 0),
                textureCount: UInt32(scene?.textures.count ?? 0),
                unsupportedCount: UInt32(modelMissing.count), sourceHash: model.header.sourceHash.reduce(0) { ($0 << 5) ^ UInt64($1) },
                sceneHash: scene?.semanticHash ?? 0, missingFields: modelMissing
            )
            models.append(modelResult)
            if let scene { scenes.append(scene) }
            if !modelMissing.isEmpty { missing.formUnion(modelMissing) }
            elements.append(.init(
                kind: role, sourceOrder: 0, entityID: entityID, modelName: name,
                modelHandle: handle, animationID: animationID, animationFrameQ16: frameQ16,
                transformQ16: transform, attachments: attachments, resourceHandle: resourceHandle,
                imageHandle: imageHandle, sourceEventID: sourceEventID, frameIndex: frameIndex,
                colourRGBA8: colour, alphaQ16: alpha, sourceHash: sourceHash,
                missingFields: modelMissing
            ))
        }

        if let gameplay, let camera = playerCamera, let weapon,
           let transform = inputs.playerTransformQ16 {
            guard let mappedHandle = inputs.introItemToModelHandle[weapon.rightWeaponID] else {
                missing.insert("intro.item_to_render_model:\(weapon.rightWeaponID)")
                missing.insert("player_viewmodel.model")
                // Keep HUD/watch/effects below available for diagnostics; no
                // player model is emitted without the source mapping.
                _ = gameplay; _ = camera
                addNonModelVisuals(weapon: weapon, visuals: &visuals, missing: &missing)
                return try finish(route: route, nativeTick: nativeTick, readiness: readiness(
                    inputs: inputs, sidecars: sidecars, dependencies: dependencies,
                    visibleDependencies: visibleDependencies, castCatalog: castCatalog, missing: missing
                ), elements: elements, visuals: visuals, models: models, scenes: scenes,
                missing: missing, strict: strict)
            }
            addModel(role: .player, entityID: 1, handle: mappedHandle,
                     animationID: weapon.hands.first?.animationID ?? gameplay.playerAnimationID,
                     frameQ16: weapon.hands.first?.animationFrameQ16 ?? 0,
                     transform: transform, attachments: [], sourceHash: weapon.sourceHash)
            _ = camera
        } else if gameplay != nil {
            missing.insert("player_viewmodel.source_pages")
        }

        if let weapon, weapon.watchVisible {
            guard let watchTransform = inputs.watchTransformQ16,
                  watchTransform.count == 16 else {
                missing.insert("watch.transform_q16")
                return try finish(route: route, nativeTick: nativeTick, readiness: readiness(
                    inputs: inputs, sidecars: sidecars, dependencies: dependencies,
                    visibleDependencies: visibleDependencies, castCatalog: castCatalog, missing: missing
                ), elements: elements, visuals: visuals, models: models, scenes: scenes,
                missing: missing, strict: strict)
            }
            addModel(role: .watch, entityID: 0x200, handle: weapon.watchModelHandle,
                     animationID: 0, frameQ16: 0, transform: watchTransform,
                     attachments: [], sourceHash: weapon.sourceHash)
        }

        if let guardDoor {
            for guardRecord in guardDoor.guards {
                guard guardRecord.poseCount > 0 else { continue }
                var attachments: [GoldenEyeRamRomDynamicSceneAttachmentV6] = []
                var unresolved = false
                for attachment in guardRecord.attachments {
                    guard let (name, _) = handleModels[attachment.modelHandle] else {
                        missing.insert("guard:\(guardRecord.entityID).attachment_model_\(attachment.modelHandle)")
                        unresolved = true; continue
                    }
                    attachments.append(.init(
                        modelName: name, modelHandle: attachment.modelHandle,
                        parentJoint: attachment.parentJoint, sourceMatrixHandle: attachment.sourceMatrixHandle,
                        transformQ16: attachment.transformQ16, sourceHash: attachment.sourceHash
                    ))
                }
                let attachmentModels = Set(attachments.map(\.modelHandle))
                guard !unresolved,
                      !attachments.isEmpty,
                      guardRecord.bodyModelHandle != 0,
                      guardRecord.headModelHandle != 0,
                      guardRecord.weaponModelHandle != 0,
                      attachmentModels.contains(guardRecord.headModelHandle),
                      attachmentModels.contains(guardRecord.weaponModelHandle) else {
                    missing.insert("guard:\(guardRecord.entityID).head_weapon_attachments")
                    continue
                }
                addModel(role: .guardCharacter, entityID: guardRecord.entityID,
                         handle: guardRecord.bodyModelHandle, animationID: guardRecord.animationID,
                         frameQ16: guardRecord.animationFrameQ16, transform: guardRecord.transformQ16,
                         attachments: attachments, sourceHash: guardRecord.sourceHash)
            }
            for door in guardDoor.doors {
                addModel(role: .door, entityID: door.entityID, handle: door.modelHandle,
                         animationID: 0, frameQ16: 0, transform: door.transformQ16,
                         attachments: [], sourceHash: door.sourceHash)
            }
        }
        if weapon != nil { addNonModelVisuals(weapon: weapon!, visuals: &visuals, missing: &missing) }

        elements.sort { lhs, rhs in
            (lhs.kind.order, lhs.entityID, lhs.sourceOrder, lhs.modelHandle) <
                (rhs.kind.order, rhs.entityID, rhs.sourceOrder, rhs.modelHandle)
        }
        visuals.sort { lhs, rhs in
            (lhs.kind.order, lhs.entityID, lhs.sourceOrder) < (rhs.kind.order, rhs.entityID, rhs.sourceOrder)
        }
        return try finish(route: route, nativeTick: nativeTick, readiness: readiness(
            inputs: inputs, sidecars: sidecars, dependencies: dependencies,
            visibleDependencies: visibleDependencies, castCatalog: castCatalog, missing: missing
        ), elements: elements, visuals: visuals, models: models, scenes: scenes,
        missing: missing, strict: strict)
    }

    private static func addNonModelVisuals(
        weapon: GoldenEyeRamRomDynamicWeaponEffectSnapshotV6,
        visuals: inout [GoldenEyeRamRomDynamicSceneVisualRecordV6],
        missing: inout Set<String>
    ) {
        for event in weapon.events {
            let kind: GoldenEyeRamRomDynamicSceneKindV6
            switch event.category {
            case 2: kind = .projectile
            case 3, 4, 5, 1: kind = .effect
            case 10: kind = .sfx
            default:
                missing.insert("effect.category_(event.category)"); continue
            }
            guard event.resourceHandle != 0 || kind == .sfx else {
                missing.insert("effect:(event.sourceEventID).resource_handle"); continue
            }
            visuals.append(.init(
                kind: kind, sourceOrder: event.sequence, entityID: event.sourceEventID,
                resourceHandle: event.resourceHandle, imageHandle: event.imageHandle,
                frameIndex: event.frameIndex, positionQ16: event.positionQ16,
                scaleQ16: event.scaleQ16, rotationQ16: event.rotationQ16,
                colourRGBA8: event.colourRGBA8, alphaQ16: event.alphaQ16,
                sourceSFXID: event.sourceSFXID, sourceHash: event.sourceHash,
                missingFields: []
            ))
        }
        if weapon.hudVisible {
            guard weapon.rightHUDImageHandle != 0,
                  weapon.rightHUDWidth > 0, weapon.rightHUDHeight > 0,
                  weapon.viewWidthQ16 > 0, weapon.viewHeightQ16 > 0 else {
                missing.insert("hud.right_image_handle"); return
            }
            let rightX = weapon.viewLeftQ16 + Int32(weapon.viewWidthQ16) - 59
            let rightY = weapon.viewTopQ16 + Int32(weapon.viewHeightQ16) - 20
            visuals.append(.init(
                kind: .hud, sourceOrder: 0, entityID: 0x100,
                resourceHandle: weapon.rightHUDImageHandle, imageHandle: weapon.rightHUDImageHandle,
                frameIndex: 0, positionQ16: [rightX, rightY, 0], scaleQ16: 65_536, rotationQ16: 0,
                colourRGBA8: 0xffff_ffff, alphaQ16: 65_536, sourceSFXID: 0,
                sourceHash: weapon.sourceHash, missingFields: []
            ))
            if weapon.leftHUDImageHandle != 0, weapon.leftHUDWidth > 0, weapon.leftHUDHeight > 0 {
                let leftX = weapon.viewLeftQ16 + 59
                let leftY = weapon.viewTopQ16 + Int32(weapon.viewHeightQ16) - 20
                visuals.append(.init(
                    kind: .hud, sourceOrder: 1, entityID: 0x102,
                    resourceHandle: weapon.leftHUDImageHandle, imageHandle: weapon.leftHUDImageHandle,
                    frameIndex: 0, positionQ16: [leftX, leftY, 0], scaleQ16: 65_536, rotationQ16: 0,
                    colourRGBA8: 0xffff_ffff, alphaQ16: 65_536, sourceSFXID: 0,
                    sourceHash: weapon.sourceHash, missingFields: []
                ))
            }
        }
        if weapon.sightVisible {
            guard weapon.crosshairImageHandle != 0 else {
                missing.insert("hud.crosshair_image_handle"); return
            }
            visuals.append(.init(
                kind: .hud, sourceOrder: 1, entityID: 0x101,
                resourceHandle: weapon.crosshairImageHandle, imageHandle: weapon.crosshairImageHandle,
                frameIndex: 0, positionQ16: [weapon.crosshairXQ16, weapon.crosshairYQ16, 0], scaleQ16: 65_536, rotationQ16: 0,
                colourRGBA8: 0xffff_ff6e, alphaQ16: 65_536, sourceSFXID: 0,
                sourceHash: weapon.sourceHash, missingFields: []
            ))
        }
        if weapon.fadeVisible {
            visuals.append(.init(
                kind: .fade, sourceOrder: 0, entityID: 0x300,
                resourceHandle: 0, imageHandle: 0, frameIndex: 0,
                positionQ16: [0, 0, 0], scaleQ16: 65_536, rotationQ16: 0,
                colourRGBA8: 0x0000_00ff, alphaQ16: weapon.fadeQ16,
                sourceSFXID: 0, sourceHash: weapon.sourceHash, missingFields: []
            ))
        }
    }

    private static func readiness(
        inputs: GoldenEyeRamRomDynamicSceneOwnerInputsV6,
        sidecars: GoldenEyeStageModelSidecarCatalogV6,
        dependencies: GoldenEyeStageSetupDependencyCatalogV6,
        visibleDependencies: GoldenEyeRamRomVisibleDependencyCatalogV6,
        castCatalog: GoldenEyeCastPreparedAssetCatalogV6?,
        missing: Set<String>
    ) -> GoldenEyeRamRomDynamicSceneReadinessV6 {
        GoldenEyeRamRomDynamicSceneReadinessV6(
            gameplaySnapshot: inputs.gameplay != nil,
            playerCameraSnapshot: inputs.playerCamera != nil,
            guardDoorSnapshot: inputs.guardDoor != nil || !(inputs.gameplay?.guardCount ?? 0 > 0),
            weaponEffectSnapshot: inputs.weaponEffect != nil || (inputs.gameplay?.playerWeaponHandle ?? 0) == 0,
            introItemToModelMapping: inputs.weaponEffect == nil || inputs.introItemToModelHandle[inputs.weaponEffect!.rightWeaponID] != nil,
            stageModelSidecars: sidecars.isComplete,
            setupDependencies: dependencies.isReady,
            visibleDependencies: visibleDependencies.isComplete,
            castGESMCatalog: castCatalog?.models.count ?? 0 > 8,
            posePages: !missing.contains("guard.pose_pages"),
            effectPages: inputs.weaponEffect?.events.isEmpty == false
        )
    }

    private static func finish(
        route: Route,
        nativeTick: UInt64,
        readiness: GoldenEyeRamRomDynamicSceneReadinessV6,
        elements: [GoldenEyeRamRomDynamicSceneElementV6],
        visuals: [GoldenEyeRamRomDynamicSceneVisualRecordV6],
        models: [GoldenEyeRamRomDynamicSceneModelResultV6],
        scenes: [GESourceSceneV6],
        missing: Set<String>,
        strict: Bool
    ) throws -> GoldenEyeRamRomDynamicSceneResultV6 {
        let values = Array(missing).sorted()
        if strict && !values.isEmpty { throw GoldenEyeRamRomDynamicSceneError.strictMissing(values) }
        var hash: UInt64 = 1_469_598_103_934_665_603
        func mix(_ value: UInt64) { hash = (hash ^ value) &* 1_099_511_628_211 }
        mix(UInt64(route.stageID)); mix(UInt64(route.demoID)); mix(nativeTick)
        for element in elements { mix(UInt64(element.kind.rawValue)); mix(UInt64(element.entityID)); mix(element.sourceHash) }
        for visual in visuals { mix(UInt64(visual.kind.rawValue)); mix(UInt64(visual.entityID)); mix(visual.sourceHash) }
        for model in models { mix(model.sceneHash); mix(model.sourceHash) }
        for value in values { mix(value.utf8.reduce(0) { ($0 &* 31) &+ UInt64($1) }) }
        return GoldenEyeRamRomDynamicSceneResultV6(
            stageID: route.stageID, demoID: route.demoID, stageName: route.stageName,
            nativeTick: nativeTick, pairPhase: UInt32(nativeTick & 1), readiness: readiness,
            elements: elements, visualRecords: visuals, modelResults: models,
            sourceScenes: scenes, missingFields: values, sceneHash: hash == 0 ? 1 : hash,
            fixtureOnly: false
        )
    }

    /// Deterministic contract fixture only. It is never selected by
    /// production composition and intentionally carries no prepared model
    /// payload; its label prevents it being mistaken for runtime evidence.
    static func fixtureOnly() -> GoldenEyeRamRomDynamicSceneResultV6 {
        let route = routes[0]
        let kinds: [GoldenEyeRamRomDynamicSceneKindV6] = [.player, .guardCharacter, .door, .weapon, .projectile, .effect, .hud, .watch, .fade]
        let elements = kinds.enumerated().map { index, kind in
            GoldenEyeRamRomDynamicSceneElementV6(
                kind: kind, sourceOrder: UInt32(index), entityID: UInt32(index + 1),
                modelName: kind == .hud || kind == .fade ? nil : "fixture.\(kind)",
                modelHandle: UInt32(0xf100_0000 | UInt32(index + 1)), animationID: kind == .guardCharacter ? 7 : 0,
                animationFrameQ16: Int32(index * 65_536), transformQ16: [Int32](repeating: 65_536, count: 16),
                attachments: [], resourceHandle: UInt32(0xf200_0000 | UInt32(index + 1)), imageHandle: 0,
                sourceEventID: UInt32(index + 1), frameIndex: 0, colourRGBA8: 0xffff_ffff,
                alphaQ16: 65_536, sourceHash: UInt64(0xf300_0000 | UInt32(index + 1)), missingFields: []
            )
        }
        let readiness = GoldenEyeRamRomDynamicSceneReadinessV6(
            gameplaySnapshot: true, playerCameraSnapshot: true, guardDoorSnapshot: true,
            weaponEffectSnapshot: true, introItemToModelMapping: true, stageModelSidecars: true,
            setupDependencies: true, visibleDependencies: true, castGESMCatalog: true,
            posePages: true, effectPages: true
        )
        return GoldenEyeRamRomDynamicSceneResultV6(
            stageID: route.stageID, demoID: route.demoID, stageName: route.stageName,
            nativeTick: 2, pairPhase: 0, readiness: readiness, elements: elements,
            visualRecords: [], modelResults: [], sourceScenes: [], missingFields: [],
            sceneHash: 0xf400_0001, fixtureOnly: true
        )
    }
}
