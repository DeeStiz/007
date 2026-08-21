import Foundation

#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), "goldeneye_cast_attachment_v6_smoke: \(message)")
}

private let arguments = Array(CommandLine.arguments.dropFirst())
private let root = URL(
    fileURLWithPath: arguments.first ?? "build/native/cast-frontend-v6-image-decoder-v6-fullweapons",
    isDirectory: true
)
private let sidecarURL = URL(
    fileURLWithPath: arguments.dropFirst().first
        ?? "build/native/gunbarrel-v6-prepared/gunbarrel.gbar"
)

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
    value.animation_tick = pose.animationTick
    value.translation_q16 = (pose.translationQ16.x, pose.translationQ16.y, pose.translationQ16.z)
    value.rotation_q16 = (pose.rotationQ16.x, pose.rotationQ16.y, pose.rotationQ16.z, pose.rotationQ16.w)
    value.scale_q16 = (pose.scaleQ16.x, pose.scaleQ16.y, pose.scaleQ16.z)
    value.pose_hash = pose.poseHash
    return value
}

private func compactTextureArgument(_ value: GoldenEyeSourceModelV6.TokenValue) -> UInt32? {
    switch value {
    case let .handle(_, value): return value
    case let .integer(value): return value >= 0 ? UInt32(value) : nil
    case let .constant(_, value): return value
    default: return nil
    }
}

@main
struct GoldenEyeCastAttachmentV6Smoke {
    static func main() throws {
        let sidecar = try GoldenEyeGunbarrelDynamicSidecarV6(loading: sidecarURL)
        expect(sidecar.resolvesGunbarrelModels, "validated animation/attachment sidecar")

        // These rows use the source guard skeleton and are deliberately
        // exercised with the actual body packets selected by the Cast table.
        // The resolver authorizes only the prepared dynamic roster; no pose or
        // matrix is synthesized when a source graph cannot lower it.
        let bodyNames = ["djbond", "boilerbond", "natalya", "boilertrev", "xenia"]
        let embeddedHeadBodies = Set(["natalya", "boilertrev", "xenia"])
        let resolver = GESourceModelDynamicResolverV6(
            resolvedModels: Set(bodyNames + ["headbrosnansuit", "chrwppk"])
        )
        let catalog = try GoldenEyeSourceFrontendCatalog.loadCast(preparedAssetRoot: root)
        let clip = try sidecar.clip(named: "fire_standing_draw_one_handed_weapon_fast")
        let poses = try sidecar.poses(
            modelHandle: sidecar.attachment.bodyModelHandle,
            clipName: clip.name,
            frame: 0,
            translationScaleQ16: GoldenEyeSourceNodeTransformContextV6.cast.rootTranslationScaleQ16
        ).map(sourcePoseRecord)
        expect(poses.count == 16, "source guard pose count")

        for name in bodyNames {
            let model = try GoldenEyeSourceModelV6.load(
                from: root.appendingPathComponent("\(name).gesm")
            )
            let compilation = GESourceModelCompilerV6.compile(
                model,
                modelName: name,
                dynamicResolver: resolver
            )
            expect(compilation.status == .complete, "\(name) source compilation status")
            guard let scene = compilation.scene else {
                throw Failure("\(name) source compilation has no scene")
            }
            expect(compilation.diagnostics.isEmpty, "\(name) source diagnostics")
            expect(scene.unsupportedCount == 0, "\(name) unsupported source commands")

            if name == "natalya",
               ProcessInfo.processInfo.environment["GE_CAST_ATTACHMENT_VERTEX_AUDIT"] == "1" {
                let groups = model.vertices.reduce(into: [UInt32]()) { result, vertex in
                    if !result.contains(vertex.groupHandle) { result.append(vertex.groupHandle) }
                }
                let metadataGroups = model.nodes.compactMap { node -> UInt32? in
                    guard node.scalarStart < UInt32(model.scalars.count) else { return nil }
                    let metadata = model.scalars[Int(node.scalarStart)].metadata
                    return metadata.count > 4 ? metadata[4] : nil
                }
                let vertexCommands = scene.commands.compactMap { command -> String? in
                    guard command.macro == "gsSPVertex" else { return nil }
                    return "dl=\(command.displayListID):ord=\(command.ordinal):args=\(command.arguments)"
                }
                print("cast_vertex_audit=natalya groups=\(groups) metadataGroups=\(metadataGroups) commands=\(vertexCommands)")
            }

            do {
                let setup = try GoldenEyeSourceTextureSetupResolverV6.resolve(
                    modelName: name,
                    model: model,
                    catalog: catalog,
                    compiledCommands: scene.commands
                )
                print("cast_texture_audit=\(name) setups=\(setup.setups.count) aliases=\(setup.aliases.count) PASS")
            } catch {
                let useTextures = scene.commands.compactMap { command -> UInt32? in
                    guard command.macro == "gsSPUseTexture", command.arguments.count == 9 else { return nil }
                    return compactTextureArgument(command.arguments[8])
                }
                let modelTextureHandles = model.textures.map { $0.resourceHandle }.sorted()
                print("cast_texture_audit=\(name) error=\(error) modelTextures=\(modelTextureHandles) useTextures=\(useTextures)")
                throw error
            }

            if name == "natalya" {
                // Tamper one source-authored low-12-bit alias. A missing
                // alias must remain a hard failure; accepting it would turn
                // a catalog/provenance defect into a placeholder texture.
                var tampered = scene.commands.enumerated().map { offset, command in
                    GoldenEyeSourceTextureSetupCommandV6(
                        sequence: UInt32(offset), compiled: command
                    )
                }
                if let index = tampered.firstIndex(where: {
                    $0.macro == "gsSPUseTexture" && $0.arguments.count == 9
                }) {
                    let original = tampered[index]
                    var arguments = original.arguments
                    arguments[8] = 0x0bad_f00d
                    tampered[index] = GoldenEyeSourceTextureSetupCommandV6(
                        sequence: original.sequence,
                        displayListID: original.displayListID,
                        ordinal: original.ordinal,
                        macro: original.macro,
                        arguments: arguments,
                        word0: original.word0,
                        word1: original.word1,
                        sourceHash: original.sourceHash
                    )
                    do {
                        _ = try GoldenEyeSourceTextureSetupResolverV6.resolve(
                            modelName: name,
                            model: model,
                            catalog: catalog,
                            commands: tampered
                        )
                        preconditionFailure("tampered Natalya texture alias was accepted")
                    } catch {
                        print("cast_texture_tamper=natalya rejected=\(error) PASS")
                    }
                } else {
                    preconditionFailure("Natalya has no gsSPUseTexture command to tamper")
                }
            }

            let lowering = try GoldenEyeSourceNodeTransformLowererV6.lower(
                model: model,
                scene: scene,
                poses: poses,
                modelName: name,
                transformContext: .cast
            )
            let switchIndices: [UInt32] = [3, 4, 5]
            let attachments: [UInt32: UInt32] = switchIndices.reduce(into: [:]) { result, switchIndex in
                if let handle = lowering.attachmentBoneHandle(
                    model: model,
                    modelName: name,
                    switchIndex: switchIndex
                ), lowering.transformByHandle[handle] != nil {
                    result[switchIndex] = handle
                }
            }
            let groupCount = (try? GoldenEyeCastSkeletonTransformV6.groups(model: model).count) ?? 0
            print("cast_attachment_body=\(name) poses=\(poses.count) bindings=\(lowering.bindings.count) exactMatrices=\(lowering.exactMatrixAssociations.count) matrixTransforms=\(lowering.matrixTransformHandles.count) groups=\(groupCount) switches=\(attachments.keys.sorted())")
            if !embeddedHeadBodies.contains(name) {
                expect(attachments[4] != nil, "\(name) source neck attachment")
            }
            expect(attachments[3] != nil, "\(name) source primary-hand attachment")
            expect(attachments[5] != nil, "\(name) source mirrored-hand attachment")
        }

        print("goldeneye_cast_attachment_v6_smoke: PASS bodies=\(bodyNames.count)")
    }
}

private struct Failure: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}
