import Foundation

/// The stage setup contains a character table entry, but it does not contain
/// the mutable character state that the source `chr` owner uses while a demo
/// is running.  This additive contract keeps those two facts separate:
/// placement/body/head provenance is still useful evidence, while a character
/// is renderable only after the source animation, head selection, and
/// attachment transforms have been copied into the frame.
public enum GoldenEyeRamRomCharacterSceneV6Error: Error, Sendable, Equatable,
    CustomStringConvertible
{
    case unknownStage(UInt32)
    case invalidMatrix(UInt32, Int)
    case invalidAnimationState(UInt32, String)
    case duplicateAnimationState(UInt32)
    case duplicateAttachment(UInt32, UInt32)

    public var description: String {
        switch self {
        case let .unknownStage(stageID):
            return "RAMROM character scene has no source stage \(stageID)"
        case let .invalidMatrix(objectIndex, count):
            return "RAMROM character \(objectIndex) matrix has \(count) words, expected 16"
        case let .invalidAnimationState(objectIndex, field):
            return "RAMROM character \(objectIndex) animation field is invalid: \(field)"
        case let .duplicateAnimationState(objectIndex):
            return "RAMROM character \(objectIndex) has duplicate animation state"
        case let .duplicateAttachment(objectIndex, switchIndex):
            return "RAMROM character \(objectIndex) has duplicate attachment switch \(switchIndex)"
        }
    }
}

public enum GoldenEyeRamRomCharacterAttachmentKindV6: UInt32, Sendable, Equatable {
    case head = 1
    case weapon = 2
    case hand = 3
}

/// A copied source attachment transform.  `switchIndex` is the source
/// SwitchNodes index, not a host array index.  The matrix is column-major
/// Q16 and contains no model pointer or segmented address.
public struct GoldenEyeRamRomCharacterAttachmentV6: Sendable, Equatable {
    public let kind: GoldenEyeRamRomCharacterAttachmentKindV6
    public let switchIndex: UInt32
    public let parentJoint: UInt32
    public let modelName: String
    public let transformQ16: [Int32]
    public let sourceMatrixHandle: UInt32

    public init(
        kind: GoldenEyeRamRomCharacterAttachmentKindV6,
        switchIndex: UInt32,
        parentJoint: UInt32,
        modelName: String,
        transformQ16: [Int32],
        sourceMatrixHandle: UInt32
    ) {
        self.kind = kind
        self.switchIndex = switchIndex
        self.parentJoint = parentJoint
        self.modelName = modelName
        self.transformQ16 = transformQ16
        self.sourceMatrixHandle = sourceMatrixHandle
    }
}

/// One source skeletal joint at a source 60 Hz anchor or at the declared
/// 120 Hz continuous interpolation step.  Euler/translation/scale values
/// retain the source animation representation so the existing node lowerer
/// can convert them to `GESourceAnimationPoseV6` without guessing.
public struct GoldenEyeRamRomCharacterJointPoseV6: Sendable, Equatable {
    public let jointID: UInt32
    public let parentJointID: UInt32
    public let translationQ16: (Int32, Int32, Int32)
    public let rotationQ16: (Int32, Int32, Int32, Int32)
    public let scaleQ16: (Int32, Int32, Int32)

    public init(
        jointID: UInt32,
        parentJointID: UInt32,
        translationQ16: (Int32, Int32, Int32),
        rotationQ16: (Int32, Int32, Int32, Int32),
        scaleQ16: (Int32, Int32, Int32)
    ) {
        self.jointID = jointID
        self.parentJointID = parentJointID
        self.translationQ16 = translationQ16
        self.rotationQ16 = rotationQ16
        self.scaleQ16 = scaleQ16
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.jointID == rhs.jointID && lhs.parentJointID == rhs.parentJointID &&
            lhs.translationQ16.0 == rhs.translationQ16.0 &&
            lhs.translationQ16.1 == rhs.translationQ16.1 &&
            lhs.translationQ16.2 == rhs.translationQ16.2 &&
            lhs.rotationQ16.0 == rhs.rotationQ16.0 &&
            lhs.rotationQ16.1 == rhs.rotationQ16.1 &&
            lhs.rotationQ16.2 == rhs.rotationQ16.2 &&
            lhs.rotationQ16.3 == rhs.rotationQ16.3 &&
            lhs.scaleQ16.0 == rhs.scaleQ16.0 &&
            lhs.scaleQ16.1 == rhs.scaleQ16.1 &&
            lhs.scaleQ16.2 == rhs.scaleQ16.2
    }
}

/// The minimum mutable source data needed to render one guard.  The current
/// RAMROM gameplay snapshot does not provide this record yet; callers pass an
/// empty map and receive an explicit missing-field result rather than a
/// T-pose or a diagnostic character.
public struct GoldenEyeRamRomCharacterAnimationStateV6: Sendable, Equatable {
    public let animationID: UInt32
    public let sourceFrameQ16: Int32
    public let poseHash: UInt64
    public let sourceAnchor: Bool
    public let interpolated: Bool
    public let continuousPoseDeclared: Bool
    public let headTableIndex: UInt32?
    public let joints: [GoldenEyeRamRomCharacterJointPoseV6]
    public let attachments: [GoldenEyeRamRomCharacterAttachmentV6]
    public let renderContext: GoldenEyeRamRomCharacterRenderContextV6?
    public let animationMergeQ16: Int32
    public let animationFlipFlags: UInt32
    public let rootMotionQ16: (Int32, Int32, Int32)
    public let visibilityState: UInt32
    public let deathState: UInt32
    public let actionState: UInt32
    public let rngCheckpoint: UInt64
    public let worldTransformQ16: [Int32]

    public init(
        animationID: UInt32,
        sourceFrameQ16: Int32,
        poseHash: UInt64,
        sourceAnchor: Bool,
        interpolated: Bool,
        continuousPoseDeclared: Bool,
        headTableIndex: UInt32?,
        joints: [GoldenEyeRamRomCharacterJointPoseV6],
        attachments: [GoldenEyeRamRomCharacterAttachmentV6],
        renderContext: GoldenEyeRamRomCharacterRenderContextV6?,
        animationMergeQ16: Int32 = 65_536,
        animationFlipFlags: UInt32 = 0,
        rootMotionQ16: (Int32, Int32, Int32) = (0, 0, 0),
        visibilityState: UInt32 = 1,
        deathState: UInt32 = 0,
        actionState: UInt32 = 0,
        rngCheckpoint: UInt64 = 0,
        worldTransformQ16: [Int32] = []
    ) {
        self.animationID = animationID
        self.sourceFrameQ16 = sourceFrameQ16
        self.poseHash = poseHash
        self.sourceAnchor = sourceAnchor
        self.interpolated = interpolated
        self.continuousPoseDeclared = continuousPoseDeclared
        self.headTableIndex = headTableIndex
        self.joints = joints
        self.attachments = attachments
        self.renderContext = renderContext
        self.animationMergeQ16 = animationMergeQ16
        self.animationFlipFlags = animationFlipFlags
        self.rootMotionQ16 = rootMotionQ16
        self.visibilityState = visibilityState
        self.deathState = deathState
        self.actionState = actionState
        self.rngCheckpoint = rngCheckpoint
        self.worldTransformQ16 = worldTransformQ16
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.animationID == rhs.animationID && lhs.sourceFrameQ16 == rhs.sourceFrameQ16 &&
            lhs.poseHash == rhs.poseHash && lhs.sourceAnchor == rhs.sourceAnchor &&
            lhs.interpolated == rhs.interpolated &&
            lhs.continuousPoseDeclared == rhs.continuousPoseDeclared &&
            lhs.headTableIndex == rhs.headTableIndex && lhs.joints == rhs.joints &&
            lhs.attachments == rhs.attachments && lhs.renderContext == rhs.renderContext &&
            lhs.animationMergeQ16 == rhs.animationMergeQ16 &&
            lhs.animationFlipFlags == rhs.animationFlipFlags &&
            lhs.rootMotionQ16.0 == rhs.rootMotionQ16.0 &&
            lhs.rootMotionQ16.1 == rhs.rootMotionQ16.1 &&
            lhs.rootMotionQ16.2 == rhs.rootMotionQ16.2 &&
            lhs.visibilityState == rhs.visibilityState && lhs.deathState == rhs.deathState &&
            lhs.actionState == rhs.actionState && lhs.rngCheckpoint == rhs.rngCheckpoint &&
            lhs.worldTransformQ16 == rhs.worldTransformQ16
    }
}

public struct GoldenEyeRamRomCharacterHeadCandidateV6: Sendable, Equatable {
    public let tableIndex: UInt32
    public let modelName: String
    public let sourceSymbol: String

    public init(tableIndex: UInt32, modelName: String, sourceSymbol: String) {
        self.tableIndex = tableIndex
        self.modelName = modelName
        self.sourceSymbol = sourceSymbol
    }
}

public enum GoldenEyeRamRomCharacterHeadResolutionV6: UInt32, Sendable, Equatable {
    case missing = 0
    case embedded = 1
    case sourceSelected = 2
    case sourceRandomizedPending = 3
}

public enum GoldenEyeRamRomCharacterPlacementProvenanceV6: UInt32, Sendable, Equatable {
    case missing = 0
    case objectMatrix = 1
    case padBasisAndPosition = 2
    case ownerWorldTransform = 3
}

/// Source `ModelRenderData`/PropType state for one gameplay character draw.
/// This is independent of the gunbarrel Type-4 setup. A stage guard must
/// supply its own source event values before a composer selects depth, blend,
/// fog, or combiner state.
public struct GoldenEyeRamRomCharacterRenderContextV6: Sendable, Equatable {
    public let propType: UInt32
    public let renderFlags: UInt32
    public let zBufferMode: UInt32
    public let environmentRGBA: UInt32
    public let fogRGBA: UInt32
    public let rawOtherModeH: UInt32
    public let rawOtherModeL: UInt32
    public let rawRenderMode: UInt32
    public let primaryType4ZMode: UInt32
    public let secondaryType4ZMode: UInt32
    public let sourceEventHash: UInt64

    public init(
        propType: UInt32,
        renderFlags: UInt32,
        zBufferMode: UInt32,
        environmentRGBA: UInt32,
        fogRGBA: UInt32,
        rawOtherModeH: UInt32,
        rawOtherModeL: UInt32,
        rawRenderMode: UInt32,
        primaryType4ZMode: UInt32,
        secondaryType4ZMode: UInt32,
        sourceEventHash: UInt64
    ) {
        self.propType = propType
        self.renderFlags = renderFlags
        self.zBufferMode = zBufferMode
        self.environmentRGBA = environmentRGBA
        self.fogRGBA = fogRGBA
        self.rawOtherModeH = rawOtherModeH
        self.rawOtherModeL = rawOtherModeL
        self.rawRenderMode = rawRenderMode
        self.primaryType4ZMode = primaryType4ZMode
        self.secondaryType4ZMode = secondaryType4ZMode
        self.sourceEventHash = sourceEventHash
    }
}

/// One setup guard after the bounded source data has been joined.  This is
/// the adapter record consumed by a future stage composer; it is not itself
/// a renderer fallback.
public struct GoldenEyeRamRomCharacterSourceSnapshotV6: Sendable, Equatable {
    public let stageID: UInt32
    public let demoID: UInt8
    public let stageName: String
    public let objectIndex: UInt32
    public let sourceRecordOffset: UInt32
    public let characterID: UInt32
    public let modelIndex: UInt32
    public let padID: UInt32
    public let bodyModelName: String
    public let bodySidecarName: String
    public let bodySidecarReady: Bool
    public let placementMatrixQ16: [Int32]
    public let placementProvenance: GoldenEyeRamRomCharacterPlacementProvenanceV6
    public let headResolution: GoldenEyeRamRomCharacterHeadResolutionV6
    public let headTableIndex: UInt32?
    public let resolvedHeadModelName: String?
    public let headCandidates: [GoldenEyeRamRomCharacterHeadCandidateV6]
    public let animation: GoldenEyeRamRomCharacterAnimationStateV6?
    public let renderContext: GoldenEyeRamRomCharacterRenderContextV6?
    public let missingFields: [String]
    public let unsupportedVisibleCommandCount: UInt32
    public let sourceHash: UInt64
    public let recordHash: UInt64

    public var staticPlacementReady: Bool {
        placementMatrixQ16.count == 16 && placementProvenance != .missing && bodySidecarReady
    }

    public var isRenderable: Bool {
        if let animation, animation.visibilityState == 0 || animation.deathState != 0 {
            return true
        }
        return unsupportedVisibleCommandCount == 0 && animation != nil && renderContext != nil && staticPlacementReady
    }

    public init(
        stageID: UInt32,
        demoID: UInt8,
        stageName: String,
        objectIndex: UInt32,
        sourceRecordOffset: UInt32,
        characterID: UInt32,
        modelIndex: UInt32,
        padID: UInt32,
        bodyModelName: String,
        bodySidecarName: String,
        bodySidecarReady: Bool,
        placementMatrixQ16: [Int32],
        placementProvenance: GoldenEyeRamRomCharacterPlacementProvenanceV6,
        headResolution: GoldenEyeRamRomCharacterHeadResolutionV6,
        headTableIndex: UInt32?,
        resolvedHeadModelName: String?,
        headCandidates: [GoldenEyeRamRomCharacterHeadCandidateV6],
        animation: GoldenEyeRamRomCharacterAnimationStateV6?,
        renderContext: GoldenEyeRamRomCharacterRenderContextV6?,
        missingFields: [String],
        unsupportedVisibleCommandCount: UInt32,
        sourceHash: UInt64,
        recordHash: UInt64
    ) {
        self.stageID = stageID
        self.demoID = demoID
        self.stageName = stageName
        self.objectIndex = objectIndex
        self.sourceRecordOffset = sourceRecordOffset
        self.characterID = characterID
        self.modelIndex = modelIndex
        self.padID = padID
        self.bodyModelName = bodyModelName
        self.bodySidecarName = bodySidecarName
        self.bodySidecarReady = bodySidecarReady
        self.placementMatrixQ16 = placementMatrixQ16
        self.placementProvenance = placementProvenance
        self.headResolution = headResolution
        self.headTableIndex = headTableIndex
        self.resolvedHeadModelName = resolvedHeadModelName
        self.headCandidates = headCandidates
        self.animation = animation
        self.renderContext = renderContext
        self.missingFields = missingFields
        self.unsupportedVisibleCommandCount = unsupportedVisibleCommandCount
        self.sourceHash = sourceHash
        self.recordHash = recordHash
    }
}

/// Immutable character-only source scene input for one RAMROM demo.  The
/// stage composer can merge `characters` into its existing room snapshot;
/// no model graph, ROM payload, filesystem path, or Metal object crosses this
/// boundary.
public struct GoldenEyeRamRomCharacterSceneSnapshotV6: Sendable, Equatable {
    public let nativeTick: UInt64
    public let referenceTick: UInt64
    public let pairPhase: UInt32
    public let stageID: UInt32
    public let demoID: UInt8
    public let variant: UInt32
    public let stageName: String
    public let setupHash: UInt64
    public let characters: [GoldenEyeRamRomCharacterSourceSnapshotV6]
    public let staticPlacementCount: UInt32
    public let bodySidecarReadyCount: UInt32
    public let resolvedHeadCount: UInt32
    public let animationReadyCount: UInt32
    public let attachmentReadyCount: UInt32
    public let unsupportedVisibleCommandCount: UInt32
    public let missingFields: [String]
    public let sceneHash: UInt64

    public var isPresentable: Bool {
        unsupportedVisibleCommandCount == 0 && characters.allSatisfy(\.isRenderable)
    }

    public init(
        nativeTick: UInt64,
        referenceTick: UInt64,
        pairPhase: UInt32,
        stageID: UInt32,
        demoID: UInt8,
        variant: UInt32,
        stageName: String,
        setupHash: UInt64,
        characters: [GoldenEyeRamRomCharacterSourceSnapshotV6],
        staticPlacementCount: UInt32,
        bodySidecarReadyCount: UInt32,
        resolvedHeadCount: UInt32,
        animationReadyCount: UInt32,
        attachmentReadyCount: UInt32,
        unsupportedVisibleCommandCount: UInt32,
        missingFields: [String],
        sceneHash: UInt64
    ) {
        self.nativeTick = nativeTick
        self.referenceTick = referenceTick
        self.pairPhase = pairPhase
        self.stageID = stageID
        self.demoID = demoID
        self.variant = variant
        self.stageName = stageName
        self.setupHash = setupHash
        self.characters = characters
        self.staticPlacementCount = staticPlacementCount
        self.bodySidecarReadyCount = bodySidecarReadyCount
        self.resolvedHeadCount = resolvedHeadCount
        self.animationReadyCount = animationReadyCount
        self.attachmentReadyCount = attachmentReadyCount
        self.missingFields = missingFields
        self.unsupportedVisibleCommandCount = unsupportedVisibleCommandCount
        self.sceneHash = sceneHash
    }
}

/// Joins source setup guards to the prepared model/visible-dependency
/// catalogs.  It intentionally does not mutate the existing stage composer;
/// the returned snapshots are a strict additive input API for that composer.
public enum GoldenEyeRamRomCharacterSceneAdapterV6 {
    public struct DemoRoute: Sendable, Equatable {
        public let demoID: UInt8
        public let stageID: UInt32
        public let stageName: String
        public let variant: UInt32

        public init(demoID: UInt8, stageID: UInt32, stageName: String, variant: UInt32) {
            self.demoID = demoID
            self.stageID = stageID
            self.stageName = stageName
            self.variant = variant
        }
    }

    public static let sourceRoutes: [DemoRoute] = [
        DemoRoute(demoID: 1, stageID: 33, stageName: "Dam", variant: 1),
        DemoRoute(demoID: 2, stageID: 33, stageName: "Dam", variant: 2),
        DemoRoute(demoID: 3, stageID: 34, stageName: "Facility", variant: 1),
        DemoRoute(demoID: 4, stageID: 34, stageName: "Facility", variant: 2),
        DemoRoute(demoID: 5, stageID: 34, stageName: "Facility", variant: 3),
        DemoRoute(demoID: 6, stageID: 35, stageName: "Runway", variant: 1),
        DemoRoute(demoID: 7, stageID: 35, stageName: "Runway", variant: 2),
        DemoRoute(demoID: 8, stageID: 9, stageName: "Bunker I", variant: 1),
        DemoRoute(demoID: 9, stageID: 9, stageName: "Bunker I", variant: 2),
        DemoRoute(demoID: 10, stageID: 20, stageName: "Silo", variant: 1),
        DemoRoute(demoID: 11, stageID: 20, stageName: "Silo", variant: 2),
        DemoRoute(demoID: 12, stageID: 26, stageName: "Frigate", variant: 1),
        DemoRoute(demoID: 13, stageID: 26, stageName: "Frigate", variant: 2),
        DemoRoute(demoID: 14, stageID: 25, stageName: "Train", variant: 1),
    ]

    /// Lower one demo's setup character rows.  `animationStates` is keyed by
    /// the copied setup object index.  An absent state is deliberate evidence
    /// that the current gameplay snapshot cannot yet render this character.
    static func make(
        stageID: UInt32,
        stageName: String,
        demoID: UInt8,
        nativeTick: UInt64,
        setup: GoldenEyeStageSetupPacket,
        dependencies: GoldenEyeStageSetupDependencyCatalogV6,
        visibleDependencies: GoldenEyeRamRomVisibleDependencyCatalogV6,
        sidecars: GoldenEyeStageModelSidecarCatalogV6,
        animationStates: [UInt32: GoldenEyeRamRomCharacterAnimationStateV6] = [:],
        placementOverrides: [UInt32: [Int32]] = [:]
    ) throws -> GoldenEyeRamRomCharacterSceneSnapshotV6 {
        guard sourceRoutes.contains(where: { $0.demoID == demoID && $0.stageID == stageID && $0.stageName == stageName }) else {
            throw GoldenEyeRamRomCharacterSceneV6Error.unknownStage(stageID)
        }
        guard let route = sourceRoutes.first(where: { $0.demoID == demoID }) else {
            throw GoldenEyeRamRomCharacterSceneV6Error.unknownStage(stageID)
        }
        guard nativeTick > 0 else {
            throw GoldenEyeRamRomCharacterSceneV6Error.invalidAnimationState(0, "native_tick")
        }
        var seenStates = Set<UInt32>()
        for objectIndex in animationStates.keys {
            guard seenStates.insert(objectIndex).inserted else {
                throw GoldenEyeRamRomCharacterSceneV6Error.duplicateAnimationState(objectIndex)
            }
        }

        let objects = setup.objects.filter { $0.type == 9 }
        var characters: [GoldenEyeRamRomCharacterSourceSnapshotV6] = []
        characters.reserveCapacity(objects.count)
        for object in objects {
            let dependency = dependencies.dependencies.first {
                $0.stage == stageName && $0.kind == "character" &&
                    $0.modelIndex == object.key0
            }
            let bodyName = dependency?.modelName ?? ""
            let bodySidecarName = bodyName.isEmpty
                ? ""
                : "stage_character_\(String(format: "%03u", object.key0))_\(bodyName)"
            let model = sidecars.models[bodySidecarName]
            let bodyReady = model != nil
            var missing: [String] = []
            if dependency == nil { missing.append("setup.character_dependency") }
            if !bodyReady { missing.append("body.model_sidecar") }

            let sourcePlacement = placementMatrix(object: object, setup: setup)
            let hasOwnerPlacement = placementOverrides[object.index] != nil
            let placement = placementOverrides[object.index] ?? sourcePlacement
            let placementProvenance: GoldenEyeRamRomCharacterPlacementProvenanceV6 =
                hasOwnerPlacement
                    ? .ownerWorldTransform
                    : object.matrixWords.count == 16
                        ? .objectMatrix
                        : placement.count == 16 ? .padBasisAndPosition : .missing
            if placement.count != 16 { missing.append("placement.matrix_q16") }

            let candidates = headCandidates(
                visibleDependencies: visibleDependencies,
                stageName: stageName
            )
            let embeddedHead = model?.nodes.contains(where: { $0.opcodeHandle == 0xEB6D_7B14 }) == true
            let state = animationStates[object.index]
            let headIndex = state?.headTableIndex
            let resolvedHead: String?
            let headResolution: GoldenEyeRamRomCharacterHeadResolutionV6
            if embeddedHead {
                resolvedHead = nil
                headResolution = .embedded
            } else if let headIndex,
                      let candidate = candidates.first(where: { $0.tableIndex == headIndex }) {
                resolvedHead = candidate.modelName
                headResolution = .sourceSelected
            } else {
                resolvedHead = nil
                headResolution = candidates.isEmpty ? .missing : .sourceRandomizedPending
                if candidates.isEmpty {
                    missing.append("head.source_table")
                } else {
                    missing.append("head_selection.table_index")
                }
            }

            if let state {
                try validate(state: state, objectIndex: object.index, nativeTick: nativeTick)
                if state.joints.isEmpty { missing.append("animation.pose_joints") }
                if state.poseHash == 0 { missing.append("animation.pose_hash") }
                if state.renderContext == nil { missing.append("render_context.model_render_data") }
                if let context = state.renderContext {
                    if context.sourceEventHash == 0 {
                        missing.append("render_context.source_event_hash")
                    }
                    if context.primaryType4ZMode == 0 || context.secondaryType4ZMode == 0 {
                        missing.append("render_context.type4_z_modes")
                    }
                }
                let requiredSwitches = model.map(requiredSwitchIndices) ?? []
                let suppliedSwitches = Set(state.attachments.map(\.switchIndex))
                for switchIndex in requiredSwitches where !suppliedSwitches.contains(switchIndex) {
                    missing.append("attachment.switch_\(switchIndex).transform")
                }
                if suppliedSwitches.count != state.attachments.count {
                    let duplicate = state.attachments
                        .groupedBySwitchIndex()
                        .first(where: { $0.value.count > 1 })?.key ?? 0
                    throw GoldenEyeRamRomCharacterSceneV6Error.duplicateAttachment(object.index, duplicate)
                }
            } else {
                missing.append("animation.animation_id")
                missing.append("animation.source_frame_q16")
                missing.append("animation.pose_joints")
                missing.append("animation.pose_hash")
                missing.append("render_context.model_render_data")
                let requiredSwitches = model.map(requiredSwitchIndices) ?? []
                if requiredSwitches.isEmpty {
                    missing.append("attachment.switch_transforms")
                } else {
                    for switchIndex in requiredSwitches {
                        missing.append("attachment.switch_\(switchIndex).transform")
                    }
                }
            }

            let uniqueMissing = Array(Set(missing)).sorted()
            let hidden = state.map { $0.visibilityState == 0 || $0.deathState != 0 } ?? false
            let unsupported = hidden ? 0 : (uniqueMissing.isEmpty ? 0 : UInt32(uniqueMissing.count))
            let sourceHash = dependency.map { fnvString($0.sourceSHA256) } ?? setup.sourceHash
            let recordHash = hashRecord(
                stageID: stageID, demoID: demoID, object: object,
                bodyName: bodyName, placement: placement,
                headResolution: headResolution, headIndex: headIndex,
                resolvedHead: resolvedHead, state: state,
                missing: uniqueMissing
            )
            characters.append(
                GoldenEyeRamRomCharacterSourceSnapshotV6(
                    stageID: stageID, demoID: demoID, stageName: stageName,
                    objectIndex: object.index, sourceRecordOffset: object.sourceRecordOffset,
                    characterID: object.key0, modelIndex: object.key0,
                    padID: object.key1,
                    bodyModelName: bodyName, bodySidecarName: bodySidecarName,
                    bodySidecarReady: bodyReady, placementMatrixQ16: placement,
                    placementProvenance: placementProvenance,
                    headResolution: headResolution, headTableIndex: headIndex,
                    resolvedHeadModelName: resolvedHead,
                    headCandidates: candidates, animation: state,
                    renderContext: state?.renderContext,
                    missingFields: uniqueMissing,
                    unsupportedVisibleCommandCount: unsupported,
                    sourceHash: sourceHash, recordHash: recordHash
                )
            )
        }

        let staticCount = characters.reduce(into: UInt32(0)) { if $1.placementMatrixQ16.count == 16 { $0 += 1 } }
        let sidecarCount = characters.reduce(into: UInt32(0)) { if $1.bodySidecarReady { $0 += 1 } }
        let headCount = characters.reduce(into: UInt32(0)) { if $1.headResolution == .embedded || $1.headResolution == .sourceSelected { $0 += 1 } }
        let animationCount = characters.reduce(into: UInt32(0)) { if $1.animation != nil && !$1.missingFields.contains(where: { $0.hasPrefix("animation.") }) { $0 += 1 } }
        let attachmentCount = characters.reduce(into: UInt32(0)) { if $1.animation != nil && !$1.missingFields.contains(where: { $0.hasPrefix("attachment.") }) { $0 += 1 } }
        let unsupported = characters.reduce(0, { $0 &+ $1.unsupportedVisibleCommandCount })
        let missingFields = Array(Set(characters.flatMap(\.missingFields))).sorted()
        var sceneHash = setup.packetHash
        for character in characters { sceneHash = fnvWord(character.recordHash, into: sceneHash) }
        sceneHash = fnvWord(nativeTick, into: sceneHash)
        return GoldenEyeRamRomCharacterSceneSnapshotV6(
            nativeTick: nativeTick, referenceTick: nativeTick >> 1,
            pairPhase: UInt32(nativeTick & 1), stageID: stageID, demoID: demoID,
            variant: route.variant,
            stageName: stageName, setupHash: setup.packetHash,
            characters: characters, staticPlacementCount: staticCount,
            bodySidecarReadyCount: sidecarCount, resolvedHeadCount: headCount,
            animationReadyCount: animationCount, attachmentReadyCount: attachmentCount,
            unsupportedVisibleCommandCount: unsupported,
            missingFields: missingFields, sceneHash: sceneHash
        )
    }

    /// Produce all fourteen route rows from seven setup packets.  This is the
    /// per-demo coverage API used by validation and can be passed directly to
    /// a later scene-composition stage.
    static func makeAll(
        setupsByStage: [UInt32: (name: String, packet: GoldenEyeStageSetupPacket)],
        dependencies: GoldenEyeStageSetupDependencyCatalogV6,
        visibleDependencies: GoldenEyeRamRomVisibleDependencyCatalogV6,
        sidecars: GoldenEyeStageModelSidecarCatalogV6,
        nativeTick: UInt64 = 2,
        animationStatesByDemo: [UInt8: [UInt32: GoldenEyeRamRomCharacterAnimationStateV6]] = [:]
    ) throws -> [GoldenEyeRamRomCharacterSceneSnapshotV6] {
        try sourceRoutes.map { route in
            guard let stage = setupsByStage[route.stageID] else {
                throw GoldenEyeRamRomCharacterSceneV6Error.unknownStage(route.stageID)
            }
            return try make(
                stageID: route.stageID, stageName: stage.name, demoID: route.demoID,
                nativeTick: nativeTick, setup: stage.packet,
                dependencies: dependencies, visibleDependencies: visibleDependencies,
                sidecars: sidecars,
                animationStates: animationStatesByDemo[route.demoID] ?? [:]
            )
        }
    }

    private static func validate(
        state: GoldenEyeRamRomCharacterAnimationStateV6,
        objectIndex: UInt32,
        nativeTick: UInt64
    ) throws {
        guard state.animationID != 0 else {
            throw GoldenEyeRamRomCharacterSceneV6Error.invalidAnimationState(objectIndex, "animation_id")
        }
        guard state.poseHash != 0 else {
            throw GoldenEyeRamRomCharacterSceneV6Error.invalidAnimationState(objectIndex, "pose_hash")
        }
        if state.interpolated {
            guard nativeTick & 1 == 1, state.continuousPoseDeclared else {
                throw GoldenEyeRamRomCharacterSceneV6Error.invalidAnimationState(objectIndex, "interpolation_policy")
            }
        } else {
            guard nativeTick & 1 == 0, state.sourceAnchor else {
                throw GoldenEyeRamRomCharacterSceneV6Error.invalidAnimationState(objectIndex, "source_anchor_policy")
            }
        }
        guard state.joints.count <= 256,
              state.joints.map(\.jointID).count == Set(state.joints.map(\.jointID)).count else {
            throw GoldenEyeRamRomCharacterSceneV6Error.invalidAnimationState(objectIndex, "pose_joints")
        }
        guard state.joints.allSatisfy({
            $0.jointID < 256 && ($0.parentJointID == UInt32.max || $0.parentJointID < 256)
        }) else {
            throw GoldenEyeRamRomCharacterSceneV6Error.invalidAnimationState(objectIndex, "pose_joint_parent")
        }
        for attachment in state.attachments where attachment.transformQ16.count != 16 {
            throw GoldenEyeRamRomCharacterSceneV6Error.invalidAnimationState(objectIndex, "attachment_transform")
        }
        guard state.attachments.allSatisfy({
            !$0.modelName.isEmpty && $0.sourceMatrixHandle != 0 && $0.parentJoint < 256
        }) else {
            throw GoldenEyeRamRomCharacterSceneV6Error.invalidAnimationState(objectIndex, "attachment_binding")
        }
        guard state.worldTransformQ16.isEmpty || state.worldTransformQ16.count == 16 else {
            throw GoldenEyeRamRomCharacterSceneV6Error.invalidAnimationState(objectIndex, "world_transform_q16")
        }
    }

    private static func headCandidates(
        visibleDependencies: GoldenEyeRamRomVisibleDependencyCatalogV6,
        stageName: String
    ) -> [GoldenEyeRamRomCharacterHeadCandidateV6] {
        visibleDependencies.dependencies.compactMap { dependency in
            guard dependency.category == "heads", dependency.stages.contains(stageName) else { return nil }
            let parts = dependency.symbol.split(separator: "_").map(String.init)
            guard parts.count >= 3, parts[0] == "chr", let index = UInt32(parts[1]) else { return nil }
            let name = parts.dropFirst(2).joined(separator: "_")
            return GoldenEyeRamRomCharacterHeadCandidateV6(
                tableIndex: index, modelName: name, sourceSymbol: dependency.symbol
            )
        }.sorted { $0.tableIndex < $1.tableIndex }
    }

    private static func requiredSwitchIndices(_ model: GoldenEyeSourceModelV6) -> [UInt32] {
        let values = model.nodes.compactMap { node -> UInt32? in
            guard node.opcodeHandle == 0x258D_B802,
                  node.scalarStart < UInt32(model.scalars.count) else { return nil }
            let metadata = model.scalars[Int(node.scalarStart)].metadata
            return metadata.count > 2 ? metadata[2] : nil
        }
        return Array(Set(values)).sorted()
    }

    private static func placementMatrix(
        object: GoldenEyeStageSetupObjectPacket,
        setup: GoldenEyeStageSetupPacket
    ) -> [Int32] {
        if object.matrixWords.count == 16 {
            return q16Matrix(object.matrixWords)
        }
        let pad: GoldenEyeStageSetupPadPacket?
        if object.key1 < 10_000 {
            pad = setup.pads.first(where: { $0.index == object.key1 })
        } else {
            let boundIndex = object.key1 - 10_000
            pad = setup.boundPads.first(where: { $0.index == boundIndex }).map {
                GoldenEyeStageSetupPadPacket(
                    index: $0.index, sourceRecordOffset: $0.sourceRecordOffset,
                    position: $0.position, up: $0.up, look: $0.look,
                    linkOffset: $0.linkOffset, stanOffset: $0.stanOffset
                )
            }
        }
        guard let pad else { return [] }
        return padMatrix(position: pad.position, up: pad.up, look: pad.look)
    }

    private static func q16Matrix(_ words: [UInt32]) -> [Int32] {
        guard words.count == 16 else { return [] }
        var result: [Int32] = []
        result.reserveCapacity(16)
        for word in words {
            let value = Double(Float(bitPattern: word)) * 65_536.0
            guard value.isFinite, value >= Double(Int32.min), value <= Double(Int32.max) else { return [] }
            result.append(Int32(value.rounded(.toNearestOrAwayFromZero)))
        }
        return result
    }

    /// Exact source `matrix_4x4_set_basis_and_position_target` lowering used
    /// when a type-9 setup object carries only a pad reference.  Source code
    /// supplies basis = -pad.look and recomputes the orthogonal right/up
    /// vectors before placing the character at pad.pos.
    private static func padMatrix(
        position: GoldenEyeStageSetupVectorBits,
        up: GoldenEyeStageSetupVectorBits,
        look: GoldenEyeStageSetupVectorBits
    ) -> [Int32] {
        guard let p = floatVector(position), let u = floatVector(up), let l = floatVector(look) else { return [] }
        let basisX = -l.0
        let basisY = -l.1
        let basisZ = -l.2
        let basisLength = vectorLength(basisX, basisY, basisZ)
        guard basisLength.isFinite, basisLength > 0 else { return [] }
        let normalizedBasisX = basisX / basisLength
        let normalizedBasisY = basisY / basisLength
        let normalizedBasisZ = basisZ / basisLength
        let rightX = u.1 * normalizedBasisZ - u.2 * normalizedBasisY
        let rightY = u.2 * normalizedBasisX - u.0 * normalizedBasisZ
        let rightZ = u.0 * normalizedBasisY - u.1 * normalizedBasisX
        let rightLength = vectorLength(rightX, rightY, rightZ)
        guard rightLength.isFinite, rightLength > 0 else { return [] }
        let normalizedRightX = rightX / rightLength
        let normalizedRightY = rightY / rightLength
        let normalizedRightZ = rightZ / rightLength
        let correctedUpX = normalizedBasisY * normalizedRightZ - normalizedBasisZ * normalizedRightY
        let correctedUpY = normalizedBasisZ * normalizedRightX - normalizedBasisX * normalizedRightZ
        let correctedUpZ = normalizedBasisX * normalizedRightY - normalizedBasisY * normalizedRightX
        let upLength = vectorLength(correctedUpX, correctedUpY, correctedUpZ)
        guard upLength.isFinite, upLength > 0 else { return [] }
        let normalizedUpX = correctedUpX / upLength
        let normalizedUpY = correctedUpY / upLength
        let normalizedUpZ = correctedUpZ / upLength
        let columns: [[Double]] = [
            [normalizedRightX, normalizedRightY, normalizedRightZ, 0],
            [normalizedUpX, normalizedUpY, normalizedUpZ, 0],
            [normalizedBasisX, normalizedBasisY, normalizedBasisZ, 0],
            [p.0, p.1, p.2, 1],
        ]
        return columns.flatMap { column in
            column.map { value in
                let q16 = value * 65_536.0
                guard q16.isFinite, q16 >= Double(Int32.min), q16 <= Double(Int32.max) else { return Int32(0) }
                return Int32(q16.rounded(.toNearestOrAwayFromZero))
            }
        }
    }

    private static func floatVector(_ value: GoldenEyeStageSetupVectorBits) -> (Double, Double, Double)? {
        let result = (
            Double(Float(bitPattern: value.x)),
            Double(Float(bitPattern: value.y)),
            Double(Float(bitPattern: value.z))
        )
        return result.0.isFinite && result.1.isFinite && result.2.isFinite ? result : nil
    }

    private static func vectorLength(_ x: Double, _ y: Double, _ z: Double) -> Double {
        sqrt(x * x + y * y + z * z)
    }

    private static func hashRecord(
        stageID: UInt32,
        demoID: UInt8,
        object: GoldenEyeStageSetupObjectPacket,
        bodyName: String,
        placement: [Int32],
        headResolution: GoldenEyeRamRomCharacterHeadResolutionV6,
        headIndex: UInt32?,
        resolvedHead: String?,
        state: GoldenEyeRamRomCharacterAnimationStateV6?,
        missing: [String]
    ) -> UInt64 {
        var hash = fnvWord(UInt64(stageID))
        hash = fnvWord(UInt64(demoID), into: hash)
        for value in [object.index, object.sourceRecordOffset, object.key0, object.key1, object.state] {
            hash = fnvWord(UInt64(value), into: hash)
        }
        hash = fnvString(bodyName, into: hash)
        for value in placement { hash = fnvWord(UInt64(bitPattern: Int64(value)), into: hash) }
        hash = fnvWord(UInt64(headResolution.rawValue), into: hash)
        hash = fnvWord(UInt64(headIndex ?? UInt32.max), into: hash)
        hash = fnvString(resolvedHead ?? "", into: hash)
        if let state {
            hash = fnvWord(UInt64(state.animationID), into: hash)
            hash = fnvWord(UInt64(bitPattern: Int64(state.sourceFrameQ16)), into: hash)
            hash = fnvWord(state.poseHash, into: hash)
            for joint in state.joints { hash = fnvWord(UInt64(joint.jointID), into: hash) }
            for attachment in state.attachments { hash = fnvWord(UInt64(attachment.switchIndex), into: hash) }
            if let context = state.renderContext {
                for value in [context.propType, context.renderFlags, context.zBufferMode,
                              context.environmentRGBA, context.fogRGBA,
                              context.rawOtherModeH, context.rawOtherModeL,
                              context.rawRenderMode, context.primaryType4ZMode,
                              context.secondaryType4ZMode] {
                    hash = fnvWord(UInt64(value), into: hash)
                }
                hash = fnvWord(context.sourceEventHash, into: hash)
            }
            hash = fnvWord(UInt64(bitPattern: Int64(state.animationMergeQ16)), into: hash)
            hash = fnvWord(UInt64(state.animationFlipFlags), into: hash)
            for value in [state.rootMotionQ16.0, state.rootMotionQ16.1, state.rootMotionQ16.2] {
                hash = fnvWord(UInt64(bitPattern: Int64(value)), into: hash)
            }
            hash = fnvWord(UInt64(state.visibilityState), into: hash)
            hash = fnvWord(UInt64(state.deathState), into: hash)
            hash = fnvWord(UInt64(state.actionState), into: hash)
            hash = fnvWord(state.rngCheckpoint, into: hash)
            for value in state.worldTransformQ16 {
                hash = fnvWord(UInt64(bitPattern: Int64(value)), into: hash)
            }
        }
        for field in missing { hash = fnvString(field, into: hash) }
        return hash == 0 ? 1 : hash
    }

    private static func fnvString(_ value: String, into initial: UInt64 = 1_469_598_103_934_665_603) -> UInt64 {
        value.utf8.reduce(initial) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }

    private static func fnvWord(_ value: UInt64, into initial: UInt64 = 1_469_598_103_934_665_603) -> UInt64 {
        var hash = initial
        for shift in stride(from: 0, to: 64, by: 8) {
            hash = (hash ^ ((value >> UInt64(shift)) & 0xff)) &* 1_099_511_628_211
        }
        return hash
    }
}

private extension Array where Element == GoldenEyeRamRomCharacterAttachmentV6 {
    func groupedBySwitchIndex() -> [UInt32: [Element]] {
        Dictionary(grouping: self, by: \.switchIndex)
    }
}
