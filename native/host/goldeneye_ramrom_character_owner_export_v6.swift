import Foundation

/// One copied per-guard owner record produced by the portable gameplay lane.
/// This is the only mutable-character input accepted by the stage-character
/// scene adapter. It carries source identity, placement, animation, exact
/// attachment transforms, and the gameplay ModelRenderData state; no MIPS
/// register, source pointer, ROM address, filesystem path, or Metal object is
/// retained.
public struct GoldenEyeRamRomCharacterOwnerExportV6: Sendable, Equatable {
    public let nativeTick: UInt64
    public let referenceTick: UInt64
    public let pairPhase: UInt32
    public let sourceAnchor: Bool
    public let interpolated: Bool
    public let continuousPoseDeclared: Bool
    public let demoID: UInt8
    public let stageID: UInt32
    public let objectIndex: UInt32
    public let characterID: UInt32
    public let bodyModelIndex: UInt32
    public let headTableIndex: UInt32?
    public let rngCheckpoint: UInt64
    public let padID: UInt32
    public let worldTransformQ16: [Int32]
    public let animationID: UInt32
    public let animationFrameQ16: Int32
    public let animationMergeQ16: Int32
    public let animationFlipFlags: UInt32
    public let rootMotionQ16: (Int32, Int32, Int32)
    public let poseHash: UInt64
    public let joints: [GoldenEyeRamRomCharacterJointPoseV6]
    public let attachments: [GoldenEyeRamRomCharacterAttachmentV6]
    public let visibilityState: UInt32
    public let deathState: UInt32
    public let actionState: UInt32
    public let renderContext: GoldenEyeRamRomCharacterRenderContextV6?
    public let sourceEventHash: UInt64

    public init(
        nativeTick: UInt64,
        referenceTick: UInt64,
        pairPhase: UInt32,
        sourceAnchor: Bool,
        interpolated: Bool,
        continuousPoseDeclared: Bool,
        demoID: UInt8,
        stageID: UInt32,
        objectIndex: UInt32,
        characterID: UInt32,
        bodyModelIndex: UInt32,
        headTableIndex: UInt32?,
        rngCheckpoint: UInt64,
        padID: UInt32,
        worldTransformQ16: [Int32],
        animationID: UInt32,
        animationFrameQ16: Int32,
        animationMergeQ16: Int32,
        animationFlipFlags: UInt32,
        rootMotionQ16: (Int32, Int32, Int32),
        poseHash: UInt64,
        joints: [GoldenEyeRamRomCharacterJointPoseV6],
        attachments: [GoldenEyeRamRomCharacterAttachmentV6],
        visibilityState: UInt32,
        deathState: UInt32,
        actionState: UInt32,
        renderContext: GoldenEyeRamRomCharacterRenderContextV6?,
        sourceEventHash: UInt64
    ) {
        self.nativeTick = nativeTick
        self.referenceTick = referenceTick
        self.pairPhase = pairPhase
        self.sourceAnchor = sourceAnchor
        self.interpolated = interpolated
        self.continuousPoseDeclared = continuousPoseDeclared
        self.demoID = demoID
        self.stageID = stageID
        self.objectIndex = objectIndex
        self.characterID = characterID
        self.bodyModelIndex = bodyModelIndex
        self.headTableIndex = headTableIndex
        self.rngCheckpoint = rngCheckpoint
        self.padID = padID
        self.worldTransformQ16 = worldTransformQ16
        self.animationID = animationID
        self.animationFrameQ16 = animationFrameQ16
        self.animationMergeQ16 = animationMergeQ16
        self.animationFlipFlags = animationFlipFlags
        self.rootMotionQ16 = rootMotionQ16
        self.poseHash = poseHash
        self.joints = joints
        self.attachments = attachments
        self.visibilityState = visibilityState
        self.deathState = deathState
        self.actionState = actionState
        self.renderContext = renderContext
        self.sourceEventHash = sourceEventHash
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.nativeTick == rhs.nativeTick && lhs.referenceTick == rhs.referenceTick &&
            lhs.pairPhase == rhs.pairPhase && lhs.sourceAnchor == rhs.sourceAnchor &&
            lhs.interpolated == rhs.interpolated &&
            lhs.continuousPoseDeclared == rhs.continuousPoseDeclared &&
            lhs.demoID == rhs.demoID && lhs.stageID == rhs.stageID &&
            lhs.objectIndex == rhs.objectIndex && lhs.characterID == rhs.characterID &&
            lhs.bodyModelIndex == rhs.bodyModelIndex && lhs.headTableIndex == rhs.headTableIndex &&
            lhs.rngCheckpoint == rhs.rngCheckpoint && lhs.padID == rhs.padID &&
            lhs.worldTransformQ16 == rhs.worldTransformQ16 && lhs.animationID == rhs.animationID &&
            lhs.animationFrameQ16 == rhs.animationFrameQ16 &&
            lhs.animationMergeQ16 == rhs.animationMergeQ16 &&
            lhs.animationFlipFlags == rhs.animationFlipFlags &&
            lhs.rootMotionQ16.0 == rhs.rootMotionQ16.0 &&
            lhs.rootMotionQ16.1 == rhs.rootMotionQ16.1 &&
            lhs.rootMotionQ16.2 == rhs.rootMotionQ16.2 &&
            lhs.poseHash == rhs.poseHash && lhs.joints == rhs.joints &&
            lhs.attachments == rhs.attachments && lhs.visibilityState == rhs.visibilityState &&
            lhs.deathState == rhs.deathState && lhs.actionState == rhs.actionState &&
            lhs.renderContext == rhs.renderContext && lhs.sourceEventHash == rhs.sourceEventHash
    }

    public var isVisible: Bool {
        visibilityState != 0 && deathState == 0
    }
}

public enum GoldenEyeRamRomCharacterOwnerExportV6Error: Error, Sendable,
    Equatable, CustomStringConvertible
{
    case invalid(UInt32, String)
    case routeMismatch(UInt32, UInt32, UInt32, UInt32)
    case setupMismatch(UInt32, String)
    case duplicateObject(UInt32)

    public var description: String {
        switch self {
        case let .invalid(objectIndex, field):
            return "RAMROM owner export \(objectIndex) is invalid: \(field)"
        case let .routeMismatch(expectedDemo, actualDemo, expectedStage, actualStage):
            return "RAMROM owner export route \(actualDemo)/\(actualStage) does not match \(expectedDemo)/\(expectedStage)"
        case let .setupMismatch(objectIndex, field):
            return "RAMROM owner export \(objectIndex) disagrees with setup: \(field)"
        case let .duplicateObject(objectIndex):
            return "RAMROM owner export has duplicate object \(objectIndex)"
        }
    }
}

public enum GoldenEyeRamRomCharacterOwnerExportV6Adapter {
    /// Exact fields absent from the existing V5 playback event and stage
    /// summary. The portable gameplay owner must populate these before a
    /// guard can be promoted from static placement evidence to a visible
    /// source scene draw.
    public static let requiredAuthorityFields: [String] = [
        "object_index", "character_id", "body_model_index", "head_table_index",
        "rng_checkpoint", "pad_id", "world_transform_q16",
        "animation_id", "animation_frame_q16", "animation_merge_q16",
        "animation_flip_flags", "root_motion_q16", "pose_hash", "pose_joints",
        "attachment_switch_transforms", "visibility_state", "death_state",
        "action_state", "model_render_data.prop_type", "model_render_data.flags",
        "model_render_data.zbuffer", "model_render_data.environment_rgba",
        "model_render_data.fog_rgba", "model_render_data.othermode_h",
        "model_render_data.othermode_l", "model_render_data.primary_type4_z",
        "model_render_data.secondary_type4_z", "source_event_hash",
    ]

    public static let currentV5MissingAuthority: [String] = [
        "GERamRomPlaybackEventV5 exports controller samples and packet/RNG metadata only",
        "GoldenEyeStageGameplayFrame exports setup guard summaries without ChrRecord state",
        "portable chr.c requires mutable ChrRecord/PropRecord/Model/ModelNode/AIList ownership",
    ]

    /// Validate the source cadence and fixed-width fields before they reach
    /// the scene adapter. Even native ticks are source anchors; odd ticks are
    /// accepted only when the owner explicitly declares continuous pose
    /// interpolation. No RNG or AI work occurs here.
    public static func validate(
        _ export: GoldenEyeRamRomCharacterOwnerExportV6,
        expectedNativeTick: UInt64? = nil
    ) throws {
        if let expectedNativeTick, export.nativeTick != expectedNativeTick {
            throw GoldenEyeRamRomCharacterOwnerExportV6Error.invalid(
                export.objectIndex, "native_tick"
            )
        }
        guard export.nativeTick > 0,
              export.referenceTick == export.nativeTick >> 1,
              export.pairPhase == UInt32(export.nativeTick & 1) else {
            throw GoldenEyeRamRomCharacterOwnerExportV6Error.invalid(
                export.objectIndex, "timebase"
            )
        }
        if export.interpolated {
            guard export.nativeTick & 1 == 1,
                  !export.sourceAnchor,
                  export.continuousPoseDeclared else {
                throw GoldenEyeRamRomCharacterOwnerExportV6Error.invalid(
                    export.objectIndex, "interpolation_policy"
                )
            }
        } else {
            guard export.nativeTick & 1 == 0,
                  export.sourceAnchor else {
                throw GoldenEyeRamRomCharacterOwnerExportV6Error.invalid(
                    export.objectIndex, "source_anchor_policy"
                )
            }
        }
        guard export.demoID > 0, export.demoID <= 14,
              export.stageID == stageID(forDemo: export.demoID) else {
            throw GoldenEyeRamRomCharacterOwnerExportV6Error.invalid(
                export.objectIndex, "route"
            )
        }
        guard export.worldTransformQ16.count == 16 else {
            throw GoldenEyeRamRomCharacterOwnerExportV6Error.invalid(
                export.objectIndex, "world_transform_q16"
            )
        }
        guard export.animationID != 0, export.poseHash != 0 else {
            throw GoldenEyeRamRomCharacterOwnerExportV6Error.invalid(
                export.objectIndex, "animation_identity"
            )
        }
        guard export.joints.count <= 256,
              export.joints.map(\.jointID).count == Set(export.joints.map(\.jointID)).count,
              export.joints.allSatisfy({
                  $0.jointID < 256 &&
                      ($0.parentJointID == UInt32.max || $0.parentJointID < 256)
              }) else {
            throw GoldenEyeRamRomCharacterOwnerExportV6Error.invalid(
                export.objectIndex, "pose_joints"
            )
        }
        guard export.attachments.count <= 32,
              export.attachments.map(\.switchIndex).count == Set(export.attachments.map(\.switchIndex)).count,
              export.attachments.allSatisfy({
                  !$0.modelName.isEmpty && $0.sourceMatrixHandle != 0 &&
                      $0.parentJoint < 256 && $0.transformQ16.count == 16
              }) else {
            throw GoldenEyeRamRomCharacterOwnerExportV6Error.invalid(
                export.objectIndex, "attachments"
            )
        }
        if export.headTableIndex != nil && export.rngCheckpoint == 0 {
            throw GoldenEyeRamRomCharacterOwnerExportV6Error.invalid(
                export.objectIndex, "head_rng_checkpoint"
            )
        }
        guard export.sourceEventHash != 0 else {
            throw GoldenEyeRamRomCharacterOwnerExportV6Error.invalid(
                export.objectIndex, "source_event_hash"
            )
        }
        guard let context = export.renderContext,
              context.sourceEventHash == export.sourceEventHash,
              context.primaryType4ZMode != 0,
              context.secondaryType4ZMode != 0 else {
            throw GoldenEyeRamRomCharacterOwnerExportV6Error.invalid(
                export.objectIndex, "render_context"
            )
        }
    }

    /// Convert the portable owner row into the existing character-scene
    /// animation contract. The source world matrix and gameplay state remain
    /// on the owner row for the stage composer; this conversion only provides
    /// the pose/attachment/render inputs expected by that adapter.
    public static func animationState(
        from export: GoldenEyeRamRomCharacterOwnerExportV6,
        expectedNativeTick: UInt64? = nil
    ) throws -> GoldenEyeRamRomCharacterAnimationStateV6 {
        try validate(export, expectedNativeTick: expectedNativeTick)
        return GoldenEyeRamRomCharacterAnimationStateV6(
            animationID: export.animationID,
            sourceFrameQ16: export.animationFrameQ16,
            poseHash: export.poseHash,
            sourceAnchor: export.sourceAnchor,
            interpolated: export.interpolated,
            continuousPoseDeclared: export.continuousPoseDeclared,
            headTableIndex: export.headTableIndex,
            joints: export.joints,
            attachments: export.attachments,
            renderContext: export.renderContext,
            animationMergeQ16: export.animationMergeQ16,
            animationFlipFlags: export.animationFlipFlags,
            rootMotionQ16: export.rootMotionQ16,
            visibilityState: export.visibilityState,
            deathState: export.deathState,
            actionState: export.actionState,
            rngCheckpoint: export.rngCheckpoint,
            worldTransformQ16: export.worldTransformQ16
        )
    }

    private static func stageID(forDemo demoID: UInt8) -> UInt32 {
        switch demoID {
        case 1, 2: return 33
        case 3, 4, 5: return 34
        case 6, 7: return 35
        case 8, 9: return 9
        case 10, 11: return 20
        case 12, 13: return 26
        case 14: return 25
        default: return 0
        }
    }
}

extension GoldenEyeRamRomCharacterSceneAdapterV6 {
    /// Feed the portable owner rows into the existing stage-character scene
    /// adapter. Missing objects remain fail-closed through the adapter's
    /// normal per-guard missing-field evidence.
    static func makeWithOwnerExports(
        stageID: UInt32,
        stageName: String,
        demoID: UInt8,
        nativeTick: UInt64,
        setup: GoldenEyeStageSetupPacket,
        dependencies: GoldenEyeStageSetupDependencyCatalogV6,
        visibleDependencies: GoldenEyeRamRomVisibleDependencyCatalogV6,
        sidecars: GoldenEyeStageModelSidecarCatalogV6,
        ownerExports: [GoldenEyeRamRomCharacterOwnerExportV6]
    ) throws -> GoldenEyeRamRomCharacterSceneSnapshotV6 {
        var states: [UInt32: GoldenEyeRamRomCharacterAnimationStateV6] = [:]
        var placements: [UInt32: [Int32]] = [:]
        for export in ownerExports {
            try GoldenEyeRamRomCharacterOwnerExportV6Adapter.validate(
                export, expectedNativeTick: nativeTick
            )
            guard export.demoID == demoID, export.stageID == stageID else {
                throw GoldenEyeRamRomCharacterOwnerExportV6Error.routeMismatch(
                    UInt32(demoID), UInt32(export.demoID), stageID, export.stageID
                )
            }
            guard let object = setup.objects.first(where: { $0.index == export.objectIndex }) else {
                throw GoldenEyeRamRomCharacterOwnerExportV6Error.setupMismatch(
                    export.objectIndex, "object_index"
                )
            }
            let dependency = dependencies.dependencies.first {
                $0.stage == stageName && $0.kind == "character" &&
                    $0.setupOffset == object.sourceRecordOffset
            }
            let bodyMatches = dependency?.modelIndex == export.bodyModelIndex
                || (dependency == nil && object.key0 == export.bodyModelIndex)
            guard object.type == 9,
                  object.key0 == export.characterID,
                  bodyMatches,
                  object.key1 == export.padID else {
                throw GoldenEyeRamRomCharacterOwnerExportV6Error.setupMismatch(
                    export.objectIndex, "identity_or_pad"
                )
            }
            guard states.updateValue(
                try GoldenEyeRamRomCharacterOwnerExportV6Adapter.animationState(
                    from: export, expectedNativeTick: nativeTick
                ), forKey: export.objectIndex
            ) == nil else {
                throw GoldenEyeRamRomCharacterOwnerExportV6Error.duplicateObject(export.objectIndex)
            }
            placements[export.objectIndex] = export.worldTransformQ16
        }
        return try make(
            stageID: stageID, stageName: stageName, demoID: demoID,
            nativeTick: nativeTick, setup: setup, dependencies: dependencies,
            visibleDependencies: visibleDependencies, sidecars: sidecars,
            animationStates: states, placementOverrides: placements
        )
    }
}
