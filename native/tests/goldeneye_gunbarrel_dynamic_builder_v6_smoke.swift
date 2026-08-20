#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif
import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), "goldeneye_gunbarrel_dynamic_builder_v6_smoke: \(message)")
}

private let arguments = Array(CommandLine.arguments.dropFirst())
private let root = URL(fileURLWithPath: arguments.first ?? "build/native/source-frontend-v6", isDirectory: true)
private let sidecarURL = URL(fileURLWithPath: arguments.dropFirst().first ?? "build/native/gunbarrel-v6-prepared/gunbarrel.gbar")

private func makeMatrix(_ handle: UInt32, roleFlags: UInt32 = 0) throws -> GoldenEyeGBIMatrixResourceV6 {
    var values = Array(repeating: Int32(0), count: 16)
    values[0] = 65_536; values[5] = 65_536; values[10] = 65_536; values[15] = 65_536
    return try GoldenEyeGBIMatrixResourceV6(handle: handle, values: values, roleFlags: roleFlags)
}

private func firstMatrixHandle(_ scene: GESourceSceneV6) -> UInt32 {
    for command in scene.commands where command.macro == "gsSPMatrix" {
        if case .handle(_, let value) = command.arguments.first { return value }
    }
    return 0
}

private func matrixHandles(_ scene: GESourceSceneV6) -> [UInt32] {
    var handles = Set<UInt32>()
    for command in scene.commands where command.macro == "gsSPMatrix" {
        guard let argument = command.arguments.first else { continue }
        switch argument {
        case .handle(_, let value): handles.insert(value)
        case .integer(let value): handles.insert(UInt32(truncatingIfNeeded: value))
        case .constant(_, let value): handles.insert(value)
        default: break
        }
    }
    return handles.filter { $0 != 0 }.sorted()
}

private func sourcePoseRecord(_ pose: GoldenEyeGunbarrelPoseV6) -> GESourceAnimationPoseV6 {
    var value = GESourceAnimationPoseV6()
    value.header.abi_version = GE_NATIVE_ABI_VERSION
    value.header.struct_size = UInt32(MemoryLayout<GESourceAnimationPoseV6>.size)
    value.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
    value.pose_handle = UInt32(truncatingIfNeeded: pose.poseHash | 0xD700_0000)
    value.skeleton_handle = pose.skeletonHandle
    value.node_handle = pose.nodeHandle
    value.parent_handle = pose.parentHandle
    value.flags = UInt32(GE_SOURCE_POSE_V6_FLAG_INTERPOLATABLE)
        | (pose.jointIndex == 0 ? UInt32(GE_SOURCE_POSE_V6_FLAG_ROOT) : 0)
        | (pose.modelHandle == 9 ? UInt32(GE_SOURCE_POSE_V6_FLAG_WEAPON_ATTACHMENT) : 0)
    value.animation_tick = pose.animationTick
    value.translation_q16 = (pose.translationQ16.x, pose.translationQ16.y, pose.translationQ16.z)
    value.rotation_q16 = (pose.rotationQ16.x, pose.rotationQ16.y, pose.rotationQ16.z, pose.rotationQ16.w)
    value.scale_q16 = (pose.scaleQ16.x, pose.scaleQ16.y, pose.scaleQ16.z)
    value.pose_hash = pose.poseHash
    return value
}

@main
struct GoldenEyeGunbarrelDynamicBuilderV6Smoke {
    static func main() throws {
        // Source model graphs may place non-Group records between animated
        // GroupRecords.  The lowerer must walk through those nodes to the
        // nearest Group ancestor rather than silently detaching the joint.
        let nestedParentFixture: [UInt32: UInt32] = [
            10: GoldenEyeSourceModelV6.nullHandle,
            11: 10, // BBOX/LOD intermediary
            12: 11, // second non-Group intermediary
            13: 12,
        ]
        let nestedGroupFixture: [UInt32: UInt32] = [10: 3, 13: 7]
        expect(
            GoldenEyeSourceNodeTransformLowererV6.nearestGroupAncestorJoint(
                nodeID: 13,
                parentByNode: nestedParentFixture,
                groupJointByNode: nestedGroupFixture
            ) == 3,
            "nested non-Group ancestor resolves to nearest Group joint"
        )
        print("gunbarrel_nested_group_fixture=PASS ancestorJoint=3")

        let sidecar = try GoldenEyeGunbarrelDynamicSidecarV6(loading: sidecarURL)
        expect(sidecar.resolvesGunbarrelModels, "sidecar resolver completeness")
        let root0 = try sidecar.rootMotion(clipName: "bond_eye_walk", frame: 0)
        let root1 = try sidecar.rootMotion(clipName: "bond_eye_walk", frame: 1)
        expect(root0.scaleQ16 == 12_307, "source model scale descriptor")
        expect(root0.descriptorHash == root1.descriptorHash, "root descriptor hash")
        expect(root0.translationQ16 != root1.translationQ16
            || root0.headingQ16 != root1.headingQ16,
               "root motion frame progression")
        print("gunbarrel_root_motion=frame0:\(root0.translationQ16.x),\(root0.translationQ16.y),\(root0.translationQ16.z),heading=\(root0.headingQ16):frame1:\(root1.translationQ16.x),\(root1.translationQ16.y),\(root1.translationQ16.z),heading=\(root1.headingQ16)")
        let resolver = sidecar.dynamicResolver
        let frame = try GoldenEyeGBISceneFrameContextV6(
            nativeTick: 2,
            referenceTick: 1,
            sourceTimer: 1,
            pairPhase: 0,
            screen: UInt32(GE_SOURCE_FRAME_V6_SCREEN_GUNBARREL),
            subphase: 0,
            viewportWidth: 640,
            viewportHeight: 480
        )
        let projectionHandle: UInt32 = 0xF200_0001
        let viewport = try GoldenEyeGBIViewportResourceV6(
            handle: 0x9000_0001,
            values: [160 << 16, 120 << 16, 1 << 16, 1 << 16, 160 << 16, 120 << 16, 0, 1 << 16]
        )
        var totalDraws = 0
        var totalPoses = 0
        var allNodeKinds = Set<GoldenEyeSourceNodeKindV6>()
        for name in ["suitbond", "headbrosnansuit", "chrwppk"] {
            let model = try GoldenEyeSourceModelV6.load(from: root.appendingPathComponent("\(name).gesm"))
            let compiled = GESourceModelCompilerV6.compile(model, modelName: name, dynamicResolver: resolver)
            expect(compiled.status == .complete && compiled.diagnostics.isEmpty, "\(name) dynamic compiler")
            guard let scene = compiled.scene else { preconditionFailure("missing \(name) scene") }
            let handles = matrixHandles(scene)
            let matrixHandle = handles.first ?? 0
            expect(matrixHandle != 0, "\(name) model matrix")
            var roles = try handles.map {
                try GoldenEyeSourceMatrixRoleSidecarV6(
                    handle: $0,
                    roleFlags: GoldenEyeSourceMatrixRoleSidecarV6.modelView
                )
            }
            roles.append(try GoldenEyeSourceMatrixRoleSidecarV6(
                handle: projectionHandle,
                roleFlags: GoldenEyeSourceMatrixRoleSidecarV6.projection
            ))
            let setup = try GoldenEyeSourceTextureSetupResolverV6.resolve(
                modelName: name,
                model: model,
                catalog: try GoldenEyeSourceFrontendCatalog.load(preparedAssetRoot: root),
                compiledCommands: scene.commands
            )
            let poses: [GESourceAnimationPoseV6]
            if name == "chrwppk" {
                // PP7 inherits body joint9/matrix15 in the source attachment
                // path; it has no independent synthetic weapon skeleton.
                poses = []
            } else {
                poses = try sidecar.poses(
                    modelHandle: model.header.modelHandle,
                    clipName: "bond_eye_walk",
                    frame: 0
                ).map(sourcePoseRecord)
            }
            let nodeLowering = try GoldenEyeSourceNodeTransformLowererV6.lower(
                model: model,
                scene: scene,
                poses: poses,
                modelName: name
            )
            allNodeKinds.formUnion(nodeLowering.bindings.map(\.kind))
            let exactHandles = nodeLowering.exactMatrixAssociations.keys.sorted().map {
                String($0, radix: 16)
            }.joined(separator: ",")
            print("gunbarrel_node_lowering=\(name):bones=\(nodeLowering.transforms.count):bindings=\(nodeLowering.bindings.count):groupExact=\(nodeLowering.exactMatrixSelectorCount):commandExact=\(nodeLowering.exactSourceMatrixNodeCount):fallback=\(nodeLowering.fallbackBindingCount):matrixHandles=\(exactHandles)")
            let result = try GoldenEyeGBISceneBuilderV6.build(
                model: model,
                modelName: name,
                matrices: try handles.map { try makeMatrix($0) } + [try makeMatrix(projectionHandle)],
                viewports: [viewport],
                matrixRoles: roles,
                frame: frame,
                dynamicResolver: resolver,
                animationPoses: poses,
                textureSetups: setup.setups
            )
            print("gunbarrel_builder_probe=\(name):presentable=\(result.presentable ? 1 : 0):unsupported=\(result.unsupportedVisibleCount):decoder=\(result.decoderUnsupportedCount):draws=\(result.snapshot.drawCommands.count):diagnostics=\(result.snapshot.diagnostics.count):reasons=\(result.unsupportedReasons.prefix(3))")
            expect(result.presentable, "\(name) presentable")
            expect(result.unsupportedVisibleCount == 0, "\(name) unsupported visible")
            expect(result.decoderUnsupportedCount == 0, "\(name) decoder unsupported")
            expect(!result.snapshot.drawCommands.isEmpty, "\(name) nonzero draws")
            expect(result.snapshot.animationPoses.count == poses.count, "\(name) pose copy-out")
            expect(result.snapshot.lightingFrameContext != nil, "\(name) lighting context")
            let boneTransforms = result.snapshot.transforms.filter {
                $0.transform_kind == UInt32(GE_SOURCE_TRANSFORM_V6_BONE)
            }
            let nodeClipTransforms = result.snapshot.transforms.filter {
                $0.transform_kind == UInt32(GE_SOURCE_TRANSFORM_V6_CLIP_COMPOSITE)
                    && $0.handle & 0xFF00_0000 == 0xAD00_0000
            }
            let matrix1Transforms = result.snapshot.transforms.filter {
                $0.transform_kind == UInt32(GE_SOURCE_TRANSFORM_V6_BONE)
                    && $0.handle & 0xFF00_0000 == 0xAE00_0000
            }
            let matrix2Transforms = result.snapshot.transforms.filter {
                $0.transform_kind == UInt32(GE_SOURCE_TRANSFORM_V6_BONE)
                    && $0.handle & 0xFF00_0000 == 0xB000_0000
            }
            print("gunbarrel_matrix1_probe=\(name):\(matrix1Transforms.map { String($0.handle, radix: 16) }.joined(separator: ","))")
            print("gunbarrel_matrix2_probe=\(name):\(matrix2Transforms.map { String($0.handle, radix: 16) }.joined(separator: ","))")
            if name == "suitbond" {
                let root = result.snapshot.transforms.first(where: {
                    $0.transform_kind == UInt32(GE_SOURCE_TRANSFORM_V6_BONE)
                        && ($0.source_node & 0x0000_FFFF) == 1
                })
                let rootValues = root.map {
                    withUnsafeBytes(of: $0.matrix_q16) {
                        Array($0.bindMemory(to: Int32.self).prefix(16))
                    }
                } ?? []
                let boneProbe = result.snapshot.transforms
                    .filter { $0.transform_kind == UInt32(GE_SOURCE_TRANSFORM_V6_BONE) }
                    .prefix(3)
                    .map { String($0.handle, radix: 16) + "/" + String($0.source_node, radix: 16) }
                    .joined(separator: ",")
                print("gunbarrel_bone_probe=\(boneProbe)")
                print("gunbarrel_root_matrix=\(rootValues.count > 14 ? "\(rootValues[12]),\(rootValues[13]),\(rootValues[14])" : "missing")")
                expect(rootValues.count == 16
                    && (rootValues[13] != 0 || rootValues[14] != 0),
                    "\(name) decoded root translation reaches bone matrix")
                expect(matrix1Transforms.count == 5,
                       "\(name) exact Matrix1 transform count")
                expect(matrix2Transforms.isEmpty,
                       "\(name) no Matrix2 transforms without source MatrixID2")
            }
            expect(name == "chrwppk"
                ? boneTransforms.count == 1
                : boneTransforms.count >= poses.count,
                "\(name) pose matrices lowered")
            if name == "chrwppk", let weaponBone = boneTransforms.first {
                let weaponValues = withUnsafeBytes(of: weaponBone.matrix_q16) {
                    Array($0.bindMemory(to: Int32.self).prefix(16))
                }
                expect(weaponValues.count == 16
                    && weaponValues[0] == 65_536
                    && weaponValues[5] == 65_536
                    && weaponValues[10] == 65_536,
                       "\(name) GroupSimple local basis is identity before hand attachment")
            }
            expect(!nodeClipTransforms.isEmpty,
                   "\(name) clip/bone matrices lowered")
            expect(name == "suitbond" ? !matrix1Transforms.isEmpty : true,
                   "\(name) Matrix1 quaternion-half lowering")
            let expectedFallbackBindings: Int
            switch name {
            case "suitbond": expectedFallbackBindings = 25
            case "headbrosnansuit": expectedFallbackBindings = 1
            default: expectedFallbackBindings = 0
            }
            expect(
                nodeLowering.fallbackBindingCount == expectedFallbackBindings,
                "\(name) fallback bindings retained only for non-visible metadata"
            )
            let expectedCommandExact = name == "headbrosnansuit" ? 1 : 0
            let expectedGroupExact = name == "suitbond" ? 20 : 0
            expect(nodeLowering.exactMatrixSelectorCount == expectedGroupExact,
                   "\(name) exact GroupRecord matrix count")
            expect(
                nodeLowering.exactSourceMatrixNodeCount == expectedCommandExact,
                "\(name) exact source-command matrix count"
            )
            expect(
                result.exactNodeTransformHandles.count
                    == expectedGroupExact + expectedCommandExact,
                "\(name) exact matrix handle count"
            )
            print("gunbarrel_builder_provenance=\(name):exactDraws=\(result.exactNodeTransformDrawCount):fallbackDraws=\(result.fallbackNodeTransformDrawCount):snapshotDraws=\(result.snapshot.drawCommands.count):exactHandles=\(result.exactNodeTransformHandles.count)")
            if name == "chrwppk" {
                expect(result.exactNodeTransformDrawCount == 0
                    && result.fallbackNodeTransformDrawCount == 0,
                    "\(name) no synthetic weapon provenance")
            } else {
                expect(result.exactNodeTransformDrawCount == result.triangleCount,
                    "\(name) every draw has exact node provenance")
                expect(result.fallbackNodeTransformDrawCount == 0,
                       "\(name) no fallback transform consumed")
            }
            expect(result.snapshot.drawCommands.allSatisfy {
                $0.transform_handle & 0xFF00_0000 == 0xAD00_0000
            }, "\(name) draws consume composed source transforms")
            print("gunbarrel_builder_transforms=\(name):bones=\(boneTransforms.count):nodeClip=\(nodeClipTransforms.count)")
            if name == "chrwppk" {
                let suppressed = try GoldenEyeGBISceneBuilderV6.build(
                    model: model,
                    modelName: name,
                    matrices: try handles.map { try makeMatrix($0) } + [try makeMatrix(projectionHandle)],
                    viewports: [viewport],
                    matrixRoles: roles,
                    frame: frame,
                    dynamicResolver: resolver,
                    animationPoses: poses,
                    textureSetups: setup.setups,
                    omittedDisplayListIDs: Set<UInt32>([1])
                )
                expect(suppressed.presentable && suppressed.unsupportedVisibleCount == 0, "muzzle switch suppressed state")
                expect(suppressed.snapshot.drawCommands.count < result.snapshot.drawCommands.count, "muzzle switch removes secondary draw")
                print("gunbarrel_muzzle_switch=PASS visible=\(result.snapshot.drawCommands.count) suppressed=\(suppressed.snapshot.drawCommands.count)")
            }
            totalDraws += result.snapshot.drawCommands.count
            totalPoses += result.snapshot.animationPoses.count
            print("gunbarrel_builder_scene=\(name):draws=\(result.snapshot.drawCommands.count):poses=\(result.snapshot.animationPoses.count):unsupported=\(result.unsupportedVisibleCount)")
        }
        expect(totalDraws > 0 && totalPoses == 32, "aggregate dynamic draw/pose totals")
        for kind in [GoldenEyeSourceNodeKindV6.header, .group, .head, .lod,
                     .dlCollision, .shadow, .gunfire] {
            expect(allNodeKinds.contains(kind), "source node kind \(kind) mapped")
        }
        print("goldeneye_gunbarrel_dynamic_builder_v6_smoke: PASS draws=\(totalDraws) poses=\(totalPoses) weaponSkeleton=0")
    }
}
