#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif
import Foundation

/// Source model-node classes that can contribute a transform to a visible
/// display list.  These values are copied from the portable model graph; they
/// are deliberately independent of the private opcode handles used by GESM.
enum GoldenEyeSourceNodeKindV6: UInt32, Sendable, Equatable {
    case unknown = 0
    case header = 1
    case group = 2
    case head = 3
    case lod = 4
    case dlCollision = 5
    case shadow = 6
    case gunfire = 7
    case groupSimple = 8
    case bbox = 9
    case displayList = 10
    case bsp = 11
    case switchNode = 12
}

/// Provenance of a node-to-transform association. Exact associations are
/// derived from a source GroupRecord matrix selector and a source model-view
/// handle observed in the decoded draw state. Display-list associations are
/// retained only as diagnostic evidence and are never valid for exercised
/// dynamic draws.
enum GoldenEyeSourceNodeTransformProvenanceV6: UInt32, Sendable, Equatable {
    case exactGroupRecordMatrixSelector = 1
    case exactSourceMatrixNode = 2
    case displayListFallback = 3
    case metadataOnly = 4
}

/// One value-only association between a source model node and its display
/// list.  The association is useful to the GBI bridge because a triangle
/// packet carries a display-list identity, while the source animation stream
/// carries joint/node identities.
struct GoldenEyeSourceNodeTransformBindingV6: Sendable, Equatable {
    let nodeID: UInt32
    let sourceNode: UInt32
    let kind: GoldenEyeSourceNodeKindV6
    let parentNodeID: UInt32
    let primaryDisplayListID: UInt32
    let secondaryDisplayListID: UInt32
    let transformHandle: UInt32
    let poseIndex: UInt32
    let provenance: GoldenEyeSourceNodeTransformProvenanceV6
    let sourceMatrixHandle: UInt32
}

/// Per-draw evidence produced by the exact source matrix/node lookup.
struct GoldenEyeSourceNodeTransformAssociationV6: Sendable, Equatable {
    let transformHandle: UInt32
    let provenance: GoldenEyeSourceNodeTransformProvenanceV6
    let nodeID: UInt32
    let poseIndex: UInt32
    let sourceMatrixHandle: UInt32
    let displayListID: UInt32
}

/// Typed source model-instance scale context.  The original model renderer
/// applies the instance scale at the header/root basis; it must not also be
/// baked into the Cast camera matrix or repeated on every joint.  Root-motion
/// translation has its own source scale because model.c multiplies it by both
/// model.scale and anim_translation_scale before the header matrix runs.
struct GoldenEyeSourceNodeTransformContextV6: Sendable, Equatable {
    let modelScaleQ16: Int32
    let rootTranslationScaleQ16: Int32

    var modelScale: Double {
        Double(modelScaleQ16) / 65_536.0
    }

    static let standard = Self(modelScaleQ16: 65_536, rootTranslationScaleQ16: 65_536)
    static let gunbarrel = Self(modelScaleQ16: 12_307, rootTranslationScaleQ16: 12_307)
    static let cast = Self(modelScaleQ16: 6_554, rootTranslationScaleQ16: 655)

    static func inferred(modelName: String?) -> Self {
        switch modelName?.lowercased() {
        case "suitbond", "headbrosnansuit", "chrwppk":
            return .gunbarrel
        default:
            return .standard
        }
    }
}

/// Immutable result of the node/pose lowering pass.  No source pointers,
/// segmented addresses, or Metal objects are retained here.
struct GoldenEyeSourceNodeTransformLoweringV6: Sendable {
    let modelHandle: UInt32
    let modelRole: UInt32
    let transforms: [GESourceTransformV6]
    let bindings: [GoldenEyeSourceNodeTransformBindingV6]
    let displayListTransformHandles: [UInt32: UInt32]
    let matrixTransformHandles: [UInt32: UInt32]
    let exactMatrixAssociations: [UInt32: GoldenEyeSourceNodeTransformAssociationV6]
    let fallbackDisplayListAssociations: [UInt32: GoldenEyeSourceNodeTransformAssociationV6]

    var transformByHandle: [UInt32: GESourceTransformV6] {
        Dictionary(uniqueKeysWithValues: transforms.map { ($0.handle, $0) })
    }

    var exactMatrixSelectorCount: Int {
        exactMatrixAssociations.values.filter {
            $0.provenance == .exactGroupRecordMatrixSelector
        }.count
    }

    var exactSourceMatrixNodeCount: Int {
        exactMatrixAssociations.values.filter {
            $0.provenance == .exactSourceMatrixNode
        }.count
    }

    var fallbackBindingCount: Int {
        bindings.filter { $0.provenance == .displayListFallback }.count
    }

    func association(
        for command: GESourceCompiledCommandV6,
        modelViewHandle: UInt32 = 0
    ) -> GoldenEyeSourceNodeTransformAssociationV6? {
        if let exact = exactMatrixAssociations[modelViewHandle] {
            return exact
        }
        return fallbackDisplayListAssociations[command.displayListID]
    }

    func transformHandle(
        for command: GESourceCompiledCommandV6,
        modelViewHandle: UInt32 = 0
    ) -> UInt32? {
        association(for: command, modelViewHandle: modelViewHandle)?.transformHandle
    }

    func attachmentBoneHandle(
        model: GoldenEyeSourceModelV6,
        modelName: String,
        switchIndex: UInt32
    ) -> UInt32? {
        func matrixTransformHandle(for groupNode: GoldenEyeSourceModelV6.Node) -> UInt32? {
            guard groupNode.scalarStart < UInt32(model.scalars.count) else { return nil }
            let scalar = model.scalars[Int(groupNode.scalarStart)]
            guard scalar.kindHandle == 0x2982_BA70,
                  scalar.semantic.first == "{" else { return nil }
            let fields = GoldenEyeSourceNodeTransformLowererV6.splitTopLevel(scalar.semantic)
            guard fields.count >= 5,
                  let matrixID = GoldenEyeSourceNodeTransformLowererV6.parseUnsigned(fields[2]),
                  matrixID != UInt32.max else { return nil }
            let sourceHandle = GoldenEyeSourceNodeTransformLowererV6.matrixHandle(
                modelName: modelName, matrixID: matrixID
            )
            return exactMatrixAssociations[sourceHandle]?.transformHandle
                ?? matrixTransformHandles[sourceHandle]
        }

        for node in model.nodes where node.opcodeHandle == 0x258D_B802 {
            guard node.scalarStart < UInt32(model.scalars.count) else { continue }
            let metadata = model.scalars[Int(node.scalarStart)].metadata
            guard metadata.count > 2, metadata[2] == switchIndex,
                  node.child != GoldenEyeSourceModelV6.nullHandle,
                  node.child < UInt32(model.nodes.count) else { continue }
            let child = model.nodes[Int(node.child)]
            guard child.scalarStart < UInt32(model.scalars.count) else { continue }
            let fields = GoldenEyeSourceNodeTransformLowererV6.splitTopLevel(
                model.scalars[Int(child.scalarStart)].semantic
            )
            guard fields.count >= 3,
                  let matrixID = GoldenEyeSourceNodeTransformLowererV6.parseMatrixSelector(fields[2]) else { continue }
            let sourceHandle = GoldenEyeSourceNodeTransformLowererV6.matrixHandle(
                modelName: modelName, matrixID: matrixID
            )
            return exactMatrixAssociations[sourceHandle]?.transformHandle
                ?? matrixTransformHandles[sourceHandle]
        }

        // Character body Model.c files expose the attachment targets through
        // the external SwitchNodes[] table. Those targets are ordinary Group
        // or HEAD nodes in the guarded GESM graph, so no SWITCH opcode exists
        // to scan at runtime. Preserve the source table's authored selectors:
        // switch 3 is the right gun hand (JointID 9), switch 5 is its mirrored
        // hand (JointID 8), and switch 4 is the HEAD placeholder under the
        // neck GroupRecord.
        let targetGroup: GoldenEyeSourceModelV6.Node?
        switch switchIndex {
        case 3:
            targetGroup = model.nodes.first(where: { node in
                guard node.scalarStart < UInt32(model.scalars.count) else { return false }
                let scalar = model.scalars[Int(node.scalarStart)]
                guard scalar.kindHandle == 0x2982_BA70 else { return false }
                let fields = GoldenEyeSourceNodeTransformLowererV6.splitTopLevel(scalar.semantic)
                return fields.count > 2
                    && GoldenEyeSourceNodeTransformLowererV6.parseUnsigned(fields[1]) == 9
            })
        case 5:
            targetGroup = model.nodes.first(where: { node in
                guard node.scalarStart < UInt32(model.scalars.count) else { return false }
                let scalar = model.scalars[Int(node.scalarStart)]
                guard scalar.kindHandle == 0x2982_BA70 else { return false }
                let fields = GoldenEyeSourceNodeTransformLowererV6.splitTopLevel(scalar.semantic)
                return fields.count > 2
                    && GoldenEyeSourceNodeTransformLowererV6.parseUnsigned(fields[1]) == 8
            })
        case 4:
            guard let head = model.nodes.first(where: {
                $0.opcodeHandle == 0xEB6D_7B14
            }) else { return nil }
            var cursor = head.parent
            var visited = Set<UInt32>()
            var found: GoldenEyeSourceModelV6.Node?
            while cursor != GoldenEyeSourceModelV6.nullHandle,
                  visited.insert(cursor).inserted,
                  cursor < UInt32(model.nodes.count) {
                let parent = model.nodes[Int(cursor)]
                if parent.scalarStart < UInt32(model.scalars.count),
                   model.scalars[Int(parent.scalarStart)].kindHandle == 0x2982_BA70 {
                    found = parent
                    break
                }
                cursor = parent.parent
            }
            targetGroup = found
        default:
            targetGroup = nil
        }
        if let targetGroup,
           let transformHandle = matrixTransformHandle(for: targetGroup) {
            return transformHandle
        }
        return nil
    }
}

enum GoldenEyeSourceNodeTransformLowererV6 {
    // These are the FNV-1a handles emitted by the guarded source preparer.
    private static let opcodeKinds: [UInt32: GoldenEyeSourceNodeKindV6] = [
        0x74EA_0903: .header,
        0x074E_A903: .header,
        0x80E8_9C4D: .group,
        0x0ECA_2814: .group,
        0xE8CB_4877: .groupSimple,
        0x519D_A401: .bbox,
        0x2758_4762: .displayList,
        0x92C9_A8E3: .bsp,
        0x258D_B802: .switchNode,
        0xD0E8_4F89: .lod,
        0x8757_4832: .shadow,
        0xEB6D_7B14: .head,
        0x7471_23D2: .dlCollision,
        0x4666_45DC: .gunfire,
    ]

    private static let drawableKinds: Set<GoldenEyeSourceNodeKindV6> = [
        .header, .group, .head, .lod, .dlCollision, .shadow, .gunfire,
        .groupSimple, .bbox, .displayList,
    ]

    private static let bonePrefix: UInt32 = 0xAB00_0000
    private static let matrix1Prefix: UInt32 = 0xAE00_0000
    private static let matrix2Prefix: UInt32 = 0xB000_0000
    private static let roleBody: UInt32 = 1
    private static let roleHead: UInt32 = 2
    private static let roleWeapon: UInt32 = 3

    enum Error: Swift.Error, CustomStringConvertible, Sendable, Equatable {
        case invalidPose(UInt32)
        case duplicatePoseNode(UInt32)
        case matrixOverflow(UInt32)
        case unsupportedParentCycle(UInt32)
        case malformedGroup(UInt32)

        var description: String {
            switch self {
            case .invalidPose(let handle): return "invalid dynamic pose 0x" + String(handle, radix: 16)
            case .duplicatePoseNode(let handle): return "duplicate dynamic pose node 0x" + String(handle, radix: 16)
            case .matrixOverflow(let handle): return "dynamic pose matrix overflow 0x" + String(handle, radix: 16)
            case .unsupportedParentCycle(let handle): return "dynamic pose parent cycle 0x" + String(handle, radix: 16)
            case .malformedGroup(let node): return "malformed source GroupRecord node " + String(node)
            }
        }
    }

    /// Lower the source animation records into actual Q16 matrices and bind
    /// visible model nodes/display lists to those matrices.  Empty poses are
    /// a valid static-model case and produce no records, preserving every
    /// existing Legal/Nintendo/GoldenEye/Wallet/Rareware hash.
    static func lower(
        model: GoldenEyeSourceModelV6,
        scene: GESourceSceneV6,
        poses: [GESourceAnimationPoseV6],
        modelName: String? = nil,
        transformContext: GoldenEyeSourceNodeTransformContextV6? = nil
    ) throws -> GoldenEyeSourceNodeTransformLoweringV6 {
        let role = modelRole(for: model.header.modelHandle, modelName: modelName)
        let context = transformContext
            ?? GoldenEyeSourceNodeTransformContextV6.inferred(modelName: modelName)
        guard poses.count <= 256 else { throw Error.invalidPose(UInt32(poses.count)) }
        guard !poses.isEmpty else {
            if role == roleWeapon,
               let attachment = model.nodes.compactMap({ node -> (UInt32, [Int32], UInt32, UInt32)? in
                   guard node.opcodeHandle == 0xE8CB_4877,
                         node.scalarStart < UInt32(model.scalars.count) else {
                       return nil
                   }
                   let scalar = model.scalars[Int(node.scalarStart)]
                   guard let origin = splitTopLevel(scalar.semantic).first.flatMap(parseVector),
                         let list = model.nodes.first(where: {
                             $0.primaryDisplayListID != GoldenEyeSourceModelV6.nullHandle
                         })?.primaryDisplayListID else {
                       return nil
                   }
                   return (node.id, origin, node.opcodeHandle, list)
               }).first {
                let handle = matrix1Prefix
                    | ((model.header.modelHandle & 0xff) << 8)
                var value = GESourceTransformV6()
                setHeader(&value.header, size: MemoryLayout<GESourceTransformV6>.size)
                value.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
                value.transform_kind = UInt32(GE_SOURCE_TRANSFORM_V6_BONE)
                value.flags = UInt32(GE_SOURCE_TRANSFORM_V6_FLAG_SOURCE_QUANTIZED)
                value.handle = handle
                value.source_node = attachment.2
                var matrix = Array(repeating: Int32(0), count: 16)
                // chrwppk is attached beneath the body's already-scaled
                // hand matrix. Source process_15_subposition contributes the
                // GroupSimple origin/identity only; applying the Gunbarrel
                // .18779343 instance scale again here shrinks the PP7 twice.
                // Keep the static weapon local basis at one and let the body
                // attachment carry the authored scale.
                let localScaleQ16: Int32 = role == roleWeapon
                    ? 65_536
                    : context.modelScaleQ16
                matrix[0] = localScaleQ16; matrix[5] = localScaleQ16
                matrix[10] = localScaleQ16; matrix[15] = 65_536
                matrix[12] = attachment.1[0]
                matrix[13] = attachment.1[1]
                matrix[14] = attachment.1[2]
                setMatrix(&value.matrix_q16, values: matrix, handle: handle)
                guard ge_source_scene_v6_validate_transform(&value) == GE_STATUS_OK else {
                    throw Error.invalidPose(handle)
                }
                let lists = scene.displayLists.map(\.id)
                let staticBindings = model.nodes.compactMap {
                    node -> GoldenEyeSourceNodeTransformBindingV6? in
                    guard let kind = opcodeKinds[node.opcodeHandle],
                          drawableKinds.contains(kind) else { return nil }
                    let provenance: GoldenEyeSourceNodeTransformProvenanceV6 =
                        kind == .groupSimple
                            ? .exactSourceMatrixNode
                            : .metadataOnly
                    return GoldenEyeSourceNodeTransformBindingV6(
                        nodeID: node.id,
                        sourceNode: node.opcodeHandle,
                        kind: kind,
                        parentNodeID: node.parent,
                        primaryDisplayListID: node.primaryDisplayListID,
                        secondaryDisplayListID: node.secondaryDisplayListID,
                        transformHandle: handle,
                        poseIndex: 0,
                        provenance: provenance,
                        sourceMatrixHandle: 0
                    )
                }
                let listAssociations = Dictionary(uniqueKeysWithValues: lists.map {
                    ($0, GoldenEyeSourceNodeTransformAssociationV6(
                        transformHandle: handle,
                        provenance: .exactSourceMatrixNode,
                        nodeID: attachment.0,
                        poseIndex: 0,
                        sourceMatrixHandle: 0,
                        displayListID: $0
                    ))
                })
                return GoldenEyeSourceNodeTransformLoweringV6(
                    modelHandle: model.header.modelHandle,
                    modelRole: role,
                    transforms: [value],
                    bindings: staticBindings,
                    displayListTransformHandles: Dictionary(uniqueKeysWithValues: lists.map { ($0, handle) }),
                    matrixTransformHandles: [:],
                    exactMatrixAssociations: [:],
                    fallbackDisplayListAssociations: listAssociations
                )
            }
            return GoldenEyeSourceNodeTransformLoweringV6(
                modelHandle: model.header.modelHandle,
                modelRole: role,
                transforms: [],
                bindings: [],
                displayListTransformHandles: [:],
                matrixTransformHandles: [:],
                exactMatrixAssociations: [:],
                fallbackDisplayListAssociations: [:]
            )
        }

        let poseNodes = Dictionary(grouping: poses, by: \.node_handle)
        guard poseNodes.allSatisfy({ $0.value.count == 1 }) else {
            let duplicate = poseNodes.first(where: { $0.value.count > 1 })?.key ?? 0
            throw Error.duplicatePoseNode(duplicate)
        }

        // Character animation is driven by the model graph's GroupRecord
        // hierarchy, not by the compact pose packet's storage order. Each
        // group supplies the source joint ID, local origin, and matrix slot;
        // reconstruct that parent relation before building world matrices.
        var originByJoint: [UInt32: [Int32]] = [:]
        var parentJointByJoint: [UInt32: UInt32] = [:]
        var groupJointByNode: [UInt32: UInt32] = [:]
        for node in model.nodes {
            guard node.scalarStart < UInt32(model.scalars.count) else { continue }
            let scalar = model.scalars[Int(node.scalarStart)]
            guard scalar.kindHandle == 0x2982_BA70, scalar.semantic.first == "{" else { continue }
            let fields = splitTopLevel(scalar.semantic)
            guard fields.count >= 5,
                  let joint = parseUnsigned(fields[1]),
                  let origin = parseVector(fields[0]) else {
                throw Error.malformedGroup(node.id)
            }
            originByJoint[joint] = origin
            groupJointByNode[node.id] = joint
        }
        let parentByNode = Dictionary(uniqueKeysWithValues: model.nodes.map { ($0.id, $0.parent) })
        for node in model.nodes {
            guard let joint = groupJointByNode[node.id] else { continue }
            if let parentJoint = nearestGroupAncestorJoint(
                nodeID: node.id,
                parentByNode: parentByNode,
                groupJointByNode: groupJointByNode
            ), parentJoint != joint {
                parentJointByJoint[joint] = parentJoint
            }
        }

        var worldByNode: [UInt32: [Int32]] = [:]
        var active = Set<UInt32>()
        func worldMatrix(for pose: GESourceAnimationPoseV6) throws -> [Int32] {
            if let cached = worldByNode[pose.node_handle] { return cached }
            guard active.insert(pose.node_handle).inserted else {
                throw Error.unsupportedParentCycle(pose.node_handle)
            }
            defer { active.remove(pose.node_handle) }
            // Pose node handles encode jointIndex + 1; GroupRecord JointID
            // is the actual skeleton index. Normalize before resolving the
            // source group origin and parent relation.
            let encodedJoint = pose.node_handle & 0x0000_FFFF
            let joint = encodedJoint == 0 ? 0 : encodedJoint - 1
            let local = localMatrix(
                for: pose,
                originQ16: originByJoint[joint] ?? [0, 0, 0],
                // Header AnimPart0 carries the source root-motion
                // translation/heading.  Group joints consume authored
                // GroupRecord origins and rotations; their serialized
                // translation tuple is scratch/stream metadata, not another
                // local offset to add to every joint.
                includePoseTranslation: joint == 0,
                basisScale: role == roleBody && joint == 0 ? context.modelScale : 1.0
            )
            let world: [Int32]
            if let parentJoint = parentJointByJoint[joint],
               let parent = poses.first(where: {
                   sourceJointIndex(fromPoseNodeHandle: $0.node_handle) == parentJoint
               }) {
                world = multiply(try worldMatrix(for: parent), local, handle: pose.node_handle)
            } else if joint != 0,
                      let root = poses.first(where: {
                          sourceJointIndex(fromPoseNodeHandle: $0.node_handle) == 0
                      }) {
                // Header/root motion is the parent of the source group tree
                // even when the serialized GroupRecord chain starts at
                // JointID 1.
                world = multiply(try worldMatrix(for: root), local, handle: pose.node_handle)
            } else if let parent = poseNodes[pose.parent_handle]?.first,
                      pose.parent_handle != 0 {
                world = multiply(try worldMatrix(for: parent), local, handle: pose.node_handle)
            } else {
                world = local
            }
            worldByNode[pose.node_handle] = world
            return world
        }

        var transforms: [GESourceTransformV6] = []
        transforms.reserveCapacity(poses.count)
        var handleByPoseNode: [UInt32: UInt32] = [:]
        for (index, pose) in poses.enumerated() {
            let handle = boneHandle(modelHandle: model.header.modelHandle, index: index)
            handleByPoseNode[pose.node_handle] = handle
            var value = GESourceTransformV6()
            setHeader(&value.header, size: MemoryLayout<GESourceTransformV6>.size)
            value.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
            value.transform_kind = UInt32(GE_SOURCE_TRANSFORM_V6_BONE)
            value.flags = UInt32(GE_SOURCE_TRANSFORM_V6_FLAG_SOURCE_QUANTIZED)
                | ((pose.flags & UInt32(GE_SOURCE_POSE_V6_FLAG_INTERPOLATABLE)) != 0
                    ? UInt32(GE_SOURCE_TRANSFORM_V6_FLAG_INTERPOLATABLE) : 0)
            value.handle = handle
            value.parent_handle = pose.parent_handle
            value.source_node = pose.node_handle
            value.viewport_id = 0
            setMatrix(&value.matrix_q16, values: try worldMatrix(for: pose), handle: pose.node_handle)
            guard ge_source_scene_v6_validate_transform(&value) == GE_STATUS_OK else {
                throw Error.invalidPose(pose.pose_handle)
            }
            transforms.append(value)
        }

        // GroupRecord carries the source joint and the matrix selectors used
        // by the model renderer. Prefer this exact matrix-to-joint linkage at
        // draw time; the display-list association below remains a bounded
        // fallback for source nodes whose matrix selector is not present in a
        // guarded packet.
        var matrixTransformHandles: [UInt32: UInt32] = [:]
        var matrixNodeByHandle: [UInt32: (nodeID: UInt32, poseIndex: UInt32, provenance: GoldenEyeSourceNodeTransformProvenanceV6)] = [:]
        var emittedMatrix1Handles = Set<UInt32>()
        if let modelName {
            let poseByJoint = Dictionary(uniqueKeysWithValues: poses.compactMap { pose -> (UInt32, UInt32)? in
                guard let joint = sourceJointIndex(fromPoseNodeHandle: pose.node_handle),
                      let handle = handleByPoseNode[pose.node_handle] else { return nil }
                return (joint, handle)
            })
            for node in model.nodes {
                guard node.scalarStart < UInt32(model.scalars.count) else { continue }
                let scalar = model.scalars[Int(node.scalarStart)]
                let semantic = scalar.semantic
                // ModelRoData_GroupRecord's validated kind handle. Other
                // records (notably BSP vectors) also begin with a brace but
                // do not carry joint/matrix selector fields.
                guard scalar.kindHandle == 0x2982_BA70, semantic.first == "{" else { continue }
                let fields = splitTopLevel(semantic)
                guard fields.count >= 5,
                      let joint = parseUnsigned(fields[1]) else {
                    throw Error.malformedGroup(node.id)
                }
            let matrixFields = fields[2...4]
            guard matrixFields.allSatisfy({ parseUnsigned($0) != nil }) else {
                throw Error.malformedGroup(node.id)
            }
            let parsedMatrixFields = matrixFields.map(parseMatrixSelector)
            let matrixIDs = parsedMatrixFields.compactMap { $0 }
            guard !matrixIDs.isEmpty else { continue }
            guard let boneHandle = poseByJoint[joint] else { continue }
                for matrixID in matrixIDs {
                    let sourceHandle = matrixHandle(modelName: modelName, matrixID: matrixID)
                    matrixTransformHandles[sourceHandle] = boneHandle
                    let poseIndex = poses.firstIndex(where: {
                        handleByPoseNode[$0.node_handle] == boneHandle
                    }).map(UInt32.init) ?? 0
                    matrixNodeByHandle[sourceHandle] = (
                        nodeID: node.id,
                        poseIndex: poseIndex,
                        provenance: .exactGroupRecordMatrixSelector
                    )
                    if matrixFields.count > 1,
                       let matrix1ID = parseMatrixSelector(matrixFields[matrixFields.index(after: matrixFields.startIndex)]),
                       matrix1ID == matrixID {
                        let matrix1Pose = poses[Int(poseIndex)]
                        let halfHandle = matrix1Prefix
                            | ((model.header.modelHandle & 0xff) << 8)
                            | UInt32((poseIndex + 1) & 0xff)
                        let halfValues = localMatrix(
                            for: matrix1Pose,
                            originQ16: originByJoint[joint] ?? [0, 0, 0],
                            rotationFraction: 0.5,
                            includePoseTranslation: false
                        )
                        let halfWorld: [Int32]
                        if let parentJoint = parentJointByJoint[joint],
                           let parent = poses.first(where: {
                               sourceJointIndex(fromPoseNodeHandle: $0.node_handle)
                                   == parentJoint
                           }) {
                            halfWorld = multiply(
                                try worldMatrix(for: parent),
                                halfValues,
                                handle: matrix1Pose.node_handle
                            )
                        } else if joint != 0,
                                  let root = poses.first(where: {
                                      sourceJointIndex(fromPoseNodeHandle: $0.node_handle) == 0
                                  }) {
                            halfWorld = multiply(
                                try worldMatrix(for: root),
                                halfValues,
                                handle: matrix1Pose.node_handle
                            )
                        } else {
                            halfWorld = halfValues
                        }
                        guard emittedMatrix1Handles.insert(halfHandle).inserted else {
                            matrixTransformHandles[sourceHandle] = halfHandle
                            continue
                        }
                        var half = GESourceTransformV6()
                        setHeader(&half.header, size: MemoryLayout<GESourceTransformV6>.size)
                        half.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
                        half.transform_kind = UInt32(GE_SOURCE_TRANSFORM_V6_BONE)
                        half.flags = UInt32(GE_SOURCE_TRANSFORM_V6_FLAG_SOURCE_QUANTIZED)
                            | UInt32(GE_SOURCE_TRANSFORM_V6_FLAG_INTERPOLATABLE)
                        half.handle = halfHandle
                        half.source_node = matrix1Pose.node_handle
                        setMatrix(&half.matrix_q16, values: halfWorld, handle: halfHandle)
                        guard ge_source_scene_v6_validate_transform(&half) == GE_STATUS_OK else {
                            throw Error.invalidPose(matrix1Pose.pose_handle)
                        }
                        if !transforms.contains(where: { $0.handle == halfHandle }) {
                            transforms.append(half)
                        }
                        matrixTransformHandles[sourceHandle] = halfHandle
                    }
                    if matrixFields.count > 2,
                       let matrix2ID = parseMatrixSelector(
                           matrixFields[matrixFields.index(matrixFields.startIndex, offsetBy: 2)]
                       ),
                       matrix2ID == matrixID {
                        let matrix2Pose = poses[Int(poseIndex)]
                        let matrix2Handle = matrix2Prefix
                            | ((model.header.modelHandle & 0xff) << 8)
                            | UInt32((poseIndex + 1) & 0xff)
                        let angle = Double(matrix2Pose.rotation_q16.1) / 65_536.0
                        let tau = Double.pi * 2.0
                        let halfAngle = angle < Double.pi
                            ? angle * 0.5
                            : tau - (tau - angle) * 0.5
                        var scalarAngle = halfAngle
                        if halfAngle >= Double.pi {
                            scalarAngle = tau - halfAngle
                        }
                        let stretch = scalarAngle < 0.890118
                            ? sqrt((sin(scalarAngle) / cos(scalarAngle)) + 1.0)
                            : 1.5
                        var matrix2 = yRotationQ16(halfAngle)
                        // matrix_column_3_scalar_multiply_2 in model.c
                        // scales only the source third column (indices 8..10),
                        // preserving the orthogonal X/Y axes.
                        matrix2[8] = q16Mul(matrix2[8], q16(stretch))
                        matrix2[9] = q16Mul(matrix2[9], q16(stretch))
                        matrix2[10] = q16Mul(matrix2[10], q16(stretch))
                        let origin = originByJoint[joint] ?? [0, 0, 0]
                        matrix2[12] = origin[0]
                        matrix2[13] = origin[1]
                        matrix2[14] = origin[2]
                        let matrix2World: [Int32]
                        if let parentJoint = parentJointByJoint[joint],
                           let parent = poses.first(where: {
                               sourceJointIndex(fromPoseNodeHandle: $0.node_handle) == parentJoint
                           }) {
                            matrix2World = multiply(
                                try worldMatrix(for: parent),
                                matrix2,
                                handle: matrix2Pose.node_handle
                            )
                        } else if joint != 0,
                                  let root = poses.first(where: {
                                      sourceJointIndex(fromPoseNodeHandle: $0.node_handle) == 0
                                  }) {
                            matrix2World = multiply(
                                try worldMatrix(for: root),
                                matrix2,
                                handle: matrix2Pose.node_handle
                            )
                        } else {
                            matrix2World = matrix2
                        }
                        var value = GESourceTransformV6()
                        setHeader(&value.header, size: MemoryLayout<GESourceTransformV6>.size)
                        value.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
                        value.transform_kind = UInt32(GE_SOURCE_TRANSFORM_V6_BONE)
                        value.flags = UInt32(GE_SOURCE_TRANSFORM_V6_FLAG_SOURCE_QUANTIZED)
                            | UInt32(GE_SOURCE_TRANSFORM_V6_FLAG_INTERPOLATABLE)
                        value.handle = matrix2Handle
                        value.source_node = matrix2Pose.node_handle
                        setMatrix(&value.matrix_q16, values: matrix2World, handle: matrix2Handle)
                        guard ge_source_scene_v6_validate_transform(&value) == GE_STATUS_OK else {
                            throw Error.invalidPose(matrix2Pose.pose_handle)
                        }
                        if !transforms.contains(where: { $0.handle == matrix2Handle }) {
                            transforms.append(value)
                        }
                        matrixTransformHandles[sourceHandle] = matrix2Handle
                    }
                }
            }
        }

        // Display-list ownership is source graph data.  Keep one stable
        // first-owner association for shared lists and assign successive
        // visible lists to the successive source joints.  This mirrors the
        // model renderer's source-order traversal while remaining bounded for
        // models with more display lists than joints.
        let visible = Set(scene.visibleNodeIDs)
        let candidateNodes = model.nodes
            .filter { visible.contains($0.id) }
            .compactMap { node -> (GoldenEyeSourceModelV6.Node, GoldenEyeSourceNodeKindV6)? in
                guard let kind = opcodeKinds[node.opcodeHandle], drawableKinds.contains(kind) else {
                    return nil
                }
                return (node, kind)
            }
            .sorted { $0.0.id < $1.0.id }
        var bindings: [GoldenEyeSourceNodeTransformBindingV6] = []
        bindings.reserveCapacity(candidateNodes.count)
        var displayListTransformHandles: [UInt32: UInt32] = [:]
        var sourceListPoseHandles: [UInt32: (handle: UInt32, poseIndex: UInt32, nodeID: UInt32)] = [:]
        var poseCursor = 0
        for (node, kind) in candidateNodes {
            let listIDs = [node.primaryDisplayListID, node.secondaryDisplayListID]
                .filter { $0 != GoldenEyeSourceModelV6.nullHandle }
            let hasVisibleList = listIDs.contains { listID in
                scene.displayLists.contains(where: { $0.id == listID })
            }
            // Keep non-drawable graph nodes in the mapping as well. Their
            // transform is consumed by a later attachment/child traversal;
            // they must not steal the source-order slot of a drawable list.
            let poseIndex: UInt32
            if hasVisibleList {
                poseIndex = UInt32(poseCursor % poses.count)
                poseCursor += 1
            } else {
                poseIndex = UInt32(Int(node.id) % poses.count)
            }
            let pose = poses[Int(poseIndex)]
            let transformHandle = handleByPoseNode[pose.node_handle] ?? boneHandle(
                modelHandle: model.header.modelHandle,
                index: Int(poseIndex)
            )
            let exactMatrixHandle = matrixNodeByHandle.first(where: {
                $0.value.nodeID == node.id
            })?.key ?? 0
            let provenance: GoldenEyeSourceNodeTransformProvenanceV6
            if exactMatrixHandle != 0 {
                provenance = matrixNodeByHandle[exactMatrixHandle]?.provenance
                    ?? .exactGroupRecordMatrixSelector
            } else if hasVisibleList {
                provenance = .displayListFallback
            } else {
                provenance = .metadataOnly
            }
            let binding = GoldenEyeSourceNodeTransformBindingV6(
                nodeID: node.id,
                sourceNode: node.opcodeHandle,
                kind: kind,
                parentNodeID: node.parent,
                primaryDisplayListID: node.primaryDisplayListID,
                secondaryDisplayListID: node.secondaryDisplayListID,
                transformHandle: transformHandle,
                poseIndex: poseIndex,
                provenance: provenance,
                sourceMatrixHandle: exactMatrixHandle
            )
            bindings.append(binding)
            for listID in listIDs where scene.displayLists.contains(where: { $0.id == listID }) {
                sourceListPoseHandles[listID] = sourceListPoseHandles[listID] ?? (
                    handle: transformHandle,
                    poseIndex: poseIndex,
                    nodeID: node.id
                )
                if provenance == .displayListFallback {
                    displayListTransformHandles[listID] = displayListTransformHandles[listID] ?? transformHandle
                }
            }
        }

        // Character packets without GroupRecords (the guarded head and
        // weapon graphs) still carry exact gsSPMatrix source commands. Bind
        // those matrix handles to the source display-list owner and its
        // source-order pose slot. This is exact command/node evidence, not a
        // procedural display-list guess.
        for command in scene.commands where command.macro == "gsSPMatrix" {
            guard let argument = command.arguments.first else { continue }
            let sourceMatrixHandle = compact(argument)
            guard sourceMatrixHandle != 0,
                  matrixTransformHandles[sourceMatrixHandle] == nil,
                  let listBinding = sourceListPoseHandles[command.displayListID] else {
                continue
            }
            matrixTransformHandles[sourceMatrixHandle] = listBinding.handle
            matrixNodeByHandle[sourceMatrixHandle] = (
                nodeID: listBinding.nodeID,
                poseIndex: listBinding.poseIndex,
                provenance: .exactSourceMatrixNode
            )
        }

        var exactMatrixAssociations: [UInt32: GoldenEyeSourceNodeTransformAssociationV6] = [:]
        for (sourceMatrixHandle, transformHandle) in matrixTransformHandles {
            guard let node = matrixNodeByHandle[sourceMatrixHandle] else {
                continue
            }
            let displayListID = bindings.first(where: {
                $0.nodeID == node.nodeID && $0.primaryDisplayListID != GoldenEyeSourceModelV6.nullHandle
            })?.primaryDisplayListID ?? GoldenEyeSourceModelV6.nullHandle
            exactMatrixAssociations[sourceMatrixHandle] = GoldenEyeSourceNodeTransformAssociationV6(
                transformHandle: transformHandle,
                provenance: node.provenance,
                nodeID: node.nodeID,
                poseIndex: node.poseIndex,
                sourceMatrixHandle: sourceMatrixHandle,
                displayListID: displayListID
            )
        }
        let finalBindings = bindings.map { binding
            -> GoldenEyeSourceNodeTransformBindingV6 in
            guard let exact = matrixNodeByHandle.first(where: {
                $0.value.nodeID == binding.nodeID
            }) else {
                return binding
            }
            return GoldenEyeSourceNodeTransformBindingV6(
                nodeID: binding.nodeID,
                sourceNode: binding.sourceNode,
                kind: binding.kind,
                parentNodeID: binding.parentNodeID,
                primaryDisplayListID: binding.primaryDisplayListID,
                secondaryDisplayListID: binding.secondaryDisplayListID,
                transformHandle: binding.transformHandle,
                poseIndex: binding.poseIndex,
                provenance: exact.value.provenance,
                sourceMatrixHandle: exact.key
            )
        }
        var fallbackAssociations: [UInt32: GoldenEyeSourceNodeTransformAssociationV6] = [:]
        for binding in finalBindings where binding.provenance == .displayListFallback {
            let listIDs = [binding.primaryDisplayListID, binding.secondaryDisplayListID]
                .filter { $0 != GoldenEyeSourceModelV6.nullHandle }
            for listID in listIDs where fallbackAssociations[listID] == nil {
                fallbackAssociations[listID] = GoldenEyeSourceNodeTransformAssociationV6(
                    transformHandle: binding.transformHandle,
                    provenance: .displayListFallback,
                    nodeID: binding.nodeID,
                    poseIndex: binding.poseIndex,
                    sourceMatrixHandle: 0,
                    displayListID: listID
                )
            }
        }
        let exactNodeIDs = Set(matrixNodeByHandle.values.map(\.nodeID))
        let finalDisplayListTransformHandles = displayListTransformHandles.filter {
            listID, _ in
            guard let binding = bindings.first(where: {
                $0.primaryDisplayListID == listID
                    || $0.secondaryDisplayListID == listID
            }) else {
                return true
            }
            return !exactNodeIDs.contains(binding.nodeID)
        }
        return GoldenEyeSourceNodeTransformLoweringV6(
            modelHandle: model.header.modelHandle,
            modelRole: role,
            transforms: transforms,
            bindings: finalBindings,
            displayListTransformHandles: finalDisplayListTransformHandles,
            matrixTransformHandles: matrixTransformHandles,
            exactMatrixAssociations: exactMatrixAssociations,
            fallbackDisplayListAssociations: fallbackAssociations
        )
    }

    /// Compose an animation/bone matrix after the source clip matrix.  The
    /// source clip record remains the exact projection/model-view result;
    /// this additive record carries the real skeletal transform to Metal.
    static func composeClip(
        clip: GESourceTransformV6,
        bone: GESourceTransformV6,
        handle: UInt32
    ) throws -> GESourceTransformV6 {
        guard clip.transform_kind == UInt32(GE_SOURCE_TRANSFORM_V6_CLIP_COMPOSITE),
              bone.transform_kind == UInt32(GE_SOURCE_TRANSFORM_V6_BONE),
              clip.parent_handle != 0, clip.source_node != 0, clip.viewport_id != 0 else {
            throw Error.invalidPose(bone.source_node)
        }
        var value = GESourceTransformV6()
        setHeader(&value.header, size: MemoryLayout<GESourceTransformV6>.size)
        value.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
        value.transform_kind = UInt32(GE_SOURCE_TRANSFORM_V6_CLIP_COMPOSITE)
        value.flags = UInt32(GE_SOURCE_TRANSFORM_V6_FLAG_SOURCE_QUANTIZED)
            | UInt32(GE_SOURCE_TRANSFORM_V6_FLAG_CLIP_COMPOSITE)
            | (bone.flags & UInt32(GE_SOURCE_TRANSFORM_V6_FLAG_INTERPOLATABLE))
        value.handle = handle
        value.parent_handle = clip.parent_handle
        value.source_node = bone.source_node
        value.viewport_id = clip.viewport_id
        let clipValues = matrixValues(clip.matrix_q16)
        let boneValues = matrixValues(bone.matrix_q16)
        setMatrix(&value.matrix_q16, values: multiply(clipValues, boneValues, handle: handle), handle: handle)
        guard ge_source_scene_v6_validate_transform(&value) == GE_STATUS_OK else {
            throw Error.invalidPose(handle)
        }
        return value
    }

    static func nodeKind(opcodeHandle: UInt32) -> GoldenEyeSourceNodeKindV6 {
        opcodeKinds[opcodeHandle] ?? .unknown
    }

    fileprivate static func matrixHandle(modelName: String, matrixID: UInt32) -> UInt32 {
        var value: UInt32 = 2_166_136_261
        let text = "\(modelName):address:0x\(String(matrixID &* 0x40, radix: 16))"
        for byte in text.utf8 { value = (value ^ UInt32(byte)) &* 16_777_619 }
        return value == 0 ? 1 : value
    }

    private static func modelRole(for handle: UInt32, modelName: String?) -> UInt32 {
        if let modelName {
            let lower = modelName.lowercased()
            if lower.contains("head") { return roleHead }
            if lower.contains("ppk") || lower.contains("weapon") || lower.contains("gun") { return roleWeapon }
            if lower.contains("suit") || lower.contains("body") { return roleBody }
        }
        switch handle {
        case 7: return roleHead
        case 9: return roleWeapon
        default: return roleBody
        }
    }

    private static func boneHandle(modelHandle: UInt32, index: Int) -> UInt32 {
        bonePrefix | ((modelHandle & 0xff) << 8) | UInt32((index + 1) & 0xff)
    }

    private static func localMatrix(
        for pose: GESourceAnimationPoseV6,
        originQ16: [Int32],
        rotationFraction: Double = 1.0,
        includePoseTranslation: Bool = true,
        basisScale: Double = 1.0
    ) -> [Int32] {
        let rx = Double(pose.rotation_q16.0) / 65_536.0
        let ry = Double(pose.rotation_q16.1) / 65_536.0
        let rz = Double(pose.rotation_q16.2) / 65_536.0
        let sx = Double(pose.scale_q16.0) / 65_536.0 * basisScale
        let sy = Double(pose.scale_q16.1) / 65_536.0 * basisScale
        let sz = Double(pose.scale_q16.2) / 65_536.0 * basisScale
        let valueRotation: [Int32]
        if rotationFraction == 0.5 {
            valueRotation = quaternionHalfRotationQ16(rx: rx, ry: ry, rz: rz)
        } else {
            let cx = q16(cos(rx)); let sxv = q16(sin(rx))
            let cy = q16(cos(ry)); let syv = q16(sin(ry))
            let cz = q16(cos(rz)); let szv = q16(sin(rz))
            let identity = q16(1)
            let rxm: [Int32] = [identity, 0, 0, 0, 0, cx, sxv, 0, 0, -sxv, cx, 0, 0, 0, 0, identity]
            let rym: [Int32] = [cy, 0, -syv, 0, 0, identity, 0, 0, syv, 0, cy, 0, 0, 0, 0, identity]
            let rzm: [Int32] = [cz, szv, 0, 0, -szv, cz, 0, 0, 0, 0, identity, 0, 0, 0, 0, identity]
            valueRotation = multiply(multiply(rzm, rym, handle: pose.node_handle), rxm, handle: pose.node_handle)
        }
        var value = valueRotation
        value[0] = q16Mul(value[0], q16(sx)); value[1] = q16Mul(value[1], q16(sx)); value[2] = q16Mul(value[2], q16(sx))
        value[4] = q16Mul(value[4], q16(sy)); value[5] = q16Mul(value[5], q16(sy)); value[6] = q16Mul(value[6], q16(sy))
        value[8] = q16Mul(value[8], q16(sz)); value[9] = q16Mul(value[9], q16(sz)); value[10] = q16Mul(value[10], q16(sz))
        value[12] = (originQ16.first ?? 0) &+ (includePoseTranslation ? pose.translation_q16.0 : 0)
        value[13] = (originQ16.dropFirst().first ?? 0) &+ (includePoseTranslation ? pose.translation_q16.1 : 0)
        value[14] = (originQ16.dropFirst(2).first ?? 0) &+ (includePoseTranslation ? pose.translation_q16.2 : 0)
        return value
    }

    private static func quaternionHalfRotationQ16(
        rx: Double,
        ry: Double,
        rz: Double
    ) -> [Int32] {
        // modelBuildGroupMatrices first constructs the full quaternion from
        // the XYZ Euler angles, then applies quaternion_7F05BC68(q, 0.5f,
        // q2).  Building a half-Euler quaternion and taking another square
        // root (the former implementation) produces q^(1/4), which visibly
        // breaks the character's Matrix1 attachment pose.
        let sx = sin(rx * 0.5), cx = cos(rx * 0.5)
        let sy = sin(ry * 0.5), cy = cos(ry * 0.5)
        let sz = sin(rz * 0.5), cz = cos(rz * 0.5)
        let qx = (sx * cy * cz) - (cx * sy * sz)
        let qy = (cx * sy * cz) + (sx * cy * sz)
        let qz = (cx * cy * sz) - (sx * sy * cz)
        let qw = (cx * cy * cz) + (sx * sy * sz)

        // This is the t=0.5 branch of quaternion_7F05BC68, including its
        // shortest-path sign rule. Keep the source's component ordering
        // (w,x,y,z), then convert with the same quaternion matrix equation.
        let phi = qw < 0.0 ? -qw : qw
        let signedIdentity = qw < 0.0 ? -1.0 : 1.0
        let factor: Double
        if phi <= 0.99998999 {
            let angle = acos(max(-1.0, min(1.0, phi)))
            let sine = sin(angle)
            factor = abs(sine) > 0.0000001
                ? sin(angle * 0.5) / sine
                : 0.5
        } else {
            // Matches the near-identity fallback in the source helper.
            factor = 0.5
        }
        let hwq = (qw * factor) + (signedIdentity * factor)
        let hxq = qx * factor
        let hyq = qy * factor
        let hzq = qz * factor
        let xx = hxq * hxq
        let yy = hyq * hyq
        let zz = hzq * hzq
        let xy = hxq * hyq
        let xz = hxq * hzq
        let yz = hyq * hzq
        let wx = hwq * hxq
        let wy = hwq * hyq
        let wz = hwq * hzq
        return [
            q16(1 - 2 * (yy + zz)), q16(2 * (xy + wz)), q16(2 * (xz - wy)), 0,
            q16(2 * (xy - wz)), q16(1 - 2 * (xx + zz)), q16(2 * (yz + wx)), 0,
            q16(2 * (xz + wy)), q16(2 * (yz - wx)), q16(1 - 2 * (xx + yy)), 0,
            0, 0, 0, q16(1),
        ]
    }

    private static func yRotationQ16(_ angle: Double) -> [Int32] {
        let c = q16(cos(angle))
        let s = q16(sin(angle))
        let one = q16(1)
        return [
            c, 0, -s, 0,
            0, one, 0, 0,
            s, 0, c, 0,
            0, 0, 0, one,
        ]
    }

    private static func matrixValues<T>(_ tuple: T) -> [Int32] {
        withUnsafeBytes(of: tuple) { raw in
            Array(raw.bindMemory(to: Int32.self).prefix(16))
        }
    }

    private static func setMatrix<T>(_ destination: inout T, values: [Int32], handle: UInt32) {
        precondition(values.count == 16, "matrix \(handle) must have sixteen Q16 values")
        withUnsafeMutableBytes(of: &destination) { raw in
            for index in 0..<16 { raw.storeBytes(of: values[index], toByteOffset: index * MemoryLayout<Int32>.stride, as: Int32.self) }
        }
    }

    private static func setHeader(_ header: inout GEAbiHeaderV1, size: Int) {
        header.abi_version = GE_NATIVE_ABI_VERSION
        header.struct_size = UInt32(size)
    }

    private static func q16(_ value: Double) -> Int32 {
        let scaled = (value * 65_536.0).rounded()
        return Int32(clamping: Int64(scaled))
    }

    private static func q16Mul(_ lhs: Int32, _ rhs: Int32) -> Int32 {
        Int32(clamping: (Int64(lhs) * Int64(rhs)) >> 16)
    }

    private static func multiply(_ lhs: [Int32], _ rhs: [Int32], handle: UInt32) -> [Int32] {
        guard lhs.count == 16, rhs.count == 16 else { return Array(repeating: 0, count: 16) }
        var result = Array(repeating: Int32(0), count: 16)
        for column in 0..<4 {
            for row in 0..<4 {
                var value: Int64 = 0
                for index in 0..<4 {
                    value += Int64(lhs[index * 4 + row]) * Int64(rhs[column * 4 + index])
                }
                result[column * 4 + row] = Int32(clamping: value >> 16)
            }
        }
        _ = handle
        return result
    }

    fileprivate static func splitTopLevel(_ value: String) -> [String] {
        var result: [String] = []
        var depth = 0
        var start = value.startIndex
        for index in value.indices {
            switch value[index] {
            case "{", "(": depth += 1
            case "}", ")": depth -= 1
            case "," where depth == 0:
                result.append(String(value[start..<index]).trimmingCharacters(in: .whitespacesAndNewlines))
                start = value.index(after: index)
            default: break
            }
        }
        result.append(String(value[start...]).trimmingCharacters(in: .whitespacesAndNewlines))
        return result
    }

    fileprivate static func parseUnsigned(_ value: String) -> UInt32? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "NULL" || trimmed == "null" { return UInt32.max }
        if trimmed.lowercased().hasPrefix("0x") {
            return UInt32(trimmed.dropFirst(2), radix: 16)
        }
        return UInt32(trimmed)
    }

    /// GroupRecord MatrixIDs are signed 16-bit selectors.  `-1` is emitted
    /// by the guarded preparer as `0xFFFF` and means that the optional matrix
    /// slot is absent; it is not a resource handle.  Keep this distinction at
    /// the parser boundary so sentinel rows cannot become visible transforms.
    fileprivate static func parseMatrixSelector(_ value: String) -> UInt32? {
        guard let selector = parseUnsigned(value), selector != 0xFFFF,
              selector != UInt32.max else { return nil }
        return selector
    }

    /// Return the nearest GroupRecord ancestor, walking through any number
    /// of non-Group nodes.  Model graphs commonly place BBOX/LOD/display-list
    /// nodes between a group and its next animated group; stopping at the
    /// first non-Group parent silently loses the skeleton hierarchy.
    static func nearestGroupAncestorJoint(
        nodeID: UInt32,
        parentByNode: [UInt32: UInt32],
        groupJointByNode: [UInt32: UInt32]
    ) -> UInt32? {
        var parent = parentByNode[nodeID] ?? GoldenEyeSourceModelV6.nullHandle
        var visited = Set<UInt32>()
        while parent != GoldenEyeSourceModelV6.nullHandle,
              visited.insert(parent).inserted {
            if let joint = groupJointByNode[parent] { return joint }
            guard let next = parentByNode[parent] else { return nil }
            parent = next
        }
        return nil
    }

    private static func compact(_ value: GoldenEyeSourceModelV6.TokenValue) -> UInt32 {
        switch value {
        case .integer(let integer):
            return UInt32(truncatingIfNeeded: integer)
        case .constant(_, let value):
            return value
        case .handle(_, let value):
            return value
        case .null:
            return GoldenEyeSourceModelV6.nullHandle
        case .boolean(let flag):
            return flag ? 1 : 0
        }
    }

    private static func sourceJointIndex(fromPoseNodeHandle handle: UInt32) -> UInt32? {
        let encoded = handle & 0x0000_FFFF
        guard encoded > 0 else { return nil }
        return encoded - 1
    }

    private static func parseVector(_ value: String) -> [Int32]? {
        let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: "{} \t\n"))
        let values = trimmed.split(separator: ",").compactMap {
            Double($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard values.count == 3 else { return nil }
        return values.map { q16($0) }
    }
}

private extension Int32 {
    init(clamping value: Int64) {
        self = Int32(Swift.max(Int64(Int32.min), Swift.min(Int64(Int32.max), value)))
    }
}
