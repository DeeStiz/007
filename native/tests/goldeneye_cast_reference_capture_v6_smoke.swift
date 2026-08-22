import Foundation
import Metal
import QuartzCore
import CryptoKit
import simd

@available(macOS 27.0, *)
@main
struct GoldenEyeCastReferenceCaptureV6Smoke {
    private static let castScreen: UInt32 = 7

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4) else {
            print("goldeneye_cast_reference_capture_v6_smoke: SKIP (Metal 4 device unavailable)")
            return
        }
        let arguments = Array(CommandLine.arguments.dropFirst())
        let root = URL(fileURLWithPath: arguments.first ?? "build/native/source-frontend-v6", isDirectory: true)
        let sidecarURL = URL(fileURLWithPath: arguments.dropFirst().first ?? "build/native/gunbarrel-v6-prepared/gunbarrel.gbar")
        let sceneLibraryURL = URL(fileURLWithPath: arguments.dropFirst().dropFirst().first ?? "build/native/source-scene-renderer-v6/GoldenEyeSourceSceneV6.metallib")
        let output = URL(fileURLWithPath: arguments.dropFirst().dropFirst().dropFirst().first ?? "build/native/cast-reference-capture-v6", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let strictRegression = ProcessInfo.processInfo.environment["GE_CAST_STRICT_REGRESSION"] == "1"

        let preparation = try GoldenEyeCastPreparedAssetCatalogV6.load(rootURL: root)
        let sidecar = try GoldenEyeGunbarrelDynamicSidecarV6(loading: sidecarURL)
        guard sidecar.resolvesGunbarrelModels else { throw CaptureError("dynamic sidecar incomplete") }
        let sourceIndex = UInt16(
            ProcessInfo.processInfo.environment["GE_CAST_SOURCE_INDEX"] ?? "1"
        ) ?? 1
        // front.c consumes a second random word for Natalya's alternate
        // jungle-fatigues body. Keep the ordinary identity fixture stable,
        // while allowing a capture to carry that copied source word
        // explicitly instead of silently equating it with the row index.
        let randomWord = UInt32(
            ProcessInfo.processInfo.environment["GE_CAST_RANDOM_WORD"] ?? String(sourceIndex)
        ) ?? UInt32(sourceIndex)
        let identity = try GoldenEyeCastSourceTableV6.identity(sourceIndex: sourceIndex)
        let animation = try GoldenEyeCastSceneComposerV6.animation(randomWord: randomWord)
        let handles = preparation.models.reduce(into: [String: UInt32]()) { result, entry in
            result[entry.key] = entry.value.header.modelHandle
        }
        let binding = try GoldenEyeCastSceneComposerV6.resolveModels(
            identity: identity,
            animation: animation,
            availableModelNames: Set(preparation.models.keys),
            availableHandles: handles,
            randomWord: randomWord
        )
        let catalog = preparation.catalog
        let sourceTimer = UInt32(
            ProcessInfo.processInfo.environment["GE_CAST_SOURCE_TIMER"] ?? "0"
        ) ?? 0
        let fadeQ16: Int32 = sourceTimer < 30
            ? Int32((Int64(sourceTimer) * 65_536) / 30)
            : (sourceTimer >= 151
                ? Int32((Int64(181 - sourceTimer) * 65_536) / 30)
                : 65_536)
        let textFadePacket = try GoldenEyeCastSceneComposerV6.textFadePacket(
            identity: identity,
            fadeQ16: fadeQ16,
            fullActorIntro: false
        )
        let castClipName = try Self.castAnimationClipName(animation.animationID)
        let castClip = try sidecar.clip(named: castClipName)
        // init_menu18_displaycast starts at the authored frame and the first
        // NTSC modelTickAnim advances by modelSetAnimPlaySpeed(.5), so the
        // first captured pose is the deterministic 21.5-style half-step.
        let castFrameQ16 = Int64(animation.startFrameQ16) + 32_768
        let clip = (
            clipName: castClipName,
            frame: UInt32(max(0, castFrameQ16 / 65_536)) % castClip.frameCount
        )
        // Cast applies model.scale=0.1 and anim_translation_scale=0.1 in
        // model.c. The shared Gunbarrel sidecar's default root decoder uses
        // the title's 0.1878 scale, so use the Cast translation scale here.
        let castAnimationTranslationScaleQ16 =
            GoldenEyeSourceNodeTransformContextV6.cast.rootTranslationScaleQ16
        let randomSeed = ProcessInfo.processInfo.environment["GE_CAST_RANDOM_SEED"]
            .flatMap { UInt64($0.hasPrefix("0x") ? $0.dropFirst(2) : Substring($0), radix: 16) }
            ?? 0x0000_0000_1234_5678
        let randomFixture = Self.sourceCastRandomFixture(seed: randomSeed)
        let castFlip = ProcessInfo.processInfo.environment["GE_CAST_FLIP"].flatMap(Bool.init)
            ?? randomFixture.flip
        let castRootMotion = try sidecar.rootMotion(
            clipName: clip.clipName,
            frame: clip.frame,
            flip: castFlip,
            translationScaleQ16: castAnimationTranslationScaleQ16
        )
        let nextRootMotion = try sidecar.rootMotion(
            clipName: clip.clipName,
            frame: (clip.frame + 1) % castClip.frameCount,
            flip: castFlip,
            translationScaleQ16: castAnimationTranslationScaleQ16
        )
        let frameFractionQ16 = castFrameQ16 & 0xffff
        let blendRoot: (Int32, Int32) -> Int32 = { lhs, rhs in
            Int32(clamping: Int64(lhs) + ((Int64(rhs) - Int64(lhs)) * frameFractionQ16 >> 16))
        }
        let castRootOffset = SIMD3<Float>(
            Float(blendRoot(castRootMotion.translationQ16.x, nextRootMotion.translationQ16.x)) / 65_536.0,
            Float(blendRoot(castRootMotion.translationQ16.y, nextRootMotion.translationQ16.y)) / 65_536.0,
            Float(blendRoot(castRootMotion.translationQ16.z, nextRootMotion.translationQ16.z)) / 65_536.0
        )
        // model.c calls getsuboffset(), then transforms the source root
        // velocity through cast_model->render_pos before applying the two
        // CAST_DAMP accumulators. The guarded root matrix is the Cast .1
        // header basis, so this is the exact value-only first-frame transform.
        let rootDelta = SIMD3<Float>(castRootOffset.x, 0, castRootOffset.z)
        let transformedRootVelocity = castRootOffset
            + rootDelta * Float(GoldenEyeSourceNodeTransformContextV6.cast.modelScale)
        var castCameraState = GoldenEyeCastCameraStateV6()
        let smoothedCamera = castCameraState.update(
            suboffset: castRootOffset,
            transformedVelocity: transformedRootVelocity,
            clockTimer: 1,
            globalTimerDelta: 1
        )
        let cameraMode = ProcessInfo.processInfo.environment["GE_CAST_CAMERA_MODE"] ?? "source-rng"
        let camera = cameraMode == "midpoint"
            ? (distance: Float(110.0), angle: Float(0.0), height: Float(0.0))
            : randomFixture.cameraStart
        print(
            "cast_source_rng=seed=0x\(String(randomSeed, radix: 16)):flipWord=0x\(String(randomFixture.flipWord, radix: 16)):flip=\(castFlip):"
                + "cameraMode=\(cameraMode):distance=\(camera.distance):angle=\(camera.angle):height=\(camera.height)"
        )
        let sourceModelView = Self.sourceCastModelView(
            distance: camera.distance,
            angle: camera.angle,
            height: camera.height,
            rootOffset: smoothedCamera.rootOffset,
            targetOffset: smoothedCamera.targetOffset
        )
        let frame = try GoldenEyeGBISceneFrameContextV6(
            nativeTick: 2, referenceTick: 1, sourceTimer: sourceTimer,
            pairPhase: 0, screen: castScreen, subphase: UInt32(identity.sourceIndex),
            viewportWidth: 440, viewportHeight: 330
        )
        let projectionHandle: UInt32 = 0xF200_0001
        var results: [GoldenEyeGBISceneBuildResultV6] = []
        var matrixHandlesByName: [String: [UInt32]] = [:]
        var bodyAttachmentTransforms: [UInt32: [Int32]] = [:]
        var bodyPoseCount = 0
        let isolatedModel = ProcessInfo.processInfo.environment["GE_CAST_ISOLATE_MODEL"]
        let modelFilter = ProcessInfo.processInfo.environment["GE_CAST_MODELS"]?
            .split(separator: ",").map(String.init)
        let modelOrder = ProcessInfo.processInfo.environment["GE_CAST_MODEL_ORDER"]?
            .split(separator: ",").compactMap { token -> String? in
                switch token {
                case "body": return binding.bodyName
                case "head": return binding.headName
                case "weapon": return binding.weaponName
                default: return nil
                }
            }
            ?? [binding.bodyName, binding.headName, binding.weaponName]
        if strictRegression {
            let captureOnlyEnvironment: [String] = [
                "GE_CAST_ISOLATE_MODEL", "GE_CAST_DRAW_INDEX", "GE_CAST_DRAW_LIMIT",
                "GE_CAST_LEGACY_TEXTURES", "GE_CAST_WINDING", "GE_CAST_MODELS",
                "GE_CAST_RANDOM_WORD"
            ]
            guard captureOnlyEnvironment.allSatisfy({
                ProcessInfo.processInfo.environment[$0] == nil
            }) else {
                throw CaptureError("strict Cast regression received capture-only environment overrides")
            }
            guard modelOrder == [binding.bodyName, binding.headName, binding.weaponName] else {
                throw CaptureError("strict Cast regression must compose body, head, weapon in source order")
            }
        }
        var bodyVertexLoadAudit: VertexLoadAudit?
        for modelName in modelOrder {
            guard !modelName.isEmpty else { continue }
            let model = try preparation.model(named: modelName)
            let compilation = GESourceModelCompilerV6.compile(
                model, modelName: modelName, dynamicResolver: sidecar.dynamicResolver
            )
            guard compilation.status == .complete,
                  let scene = compilation.scene,
                  compilation.diagnostics.isEmpty,
                  scene.unsupportedCount == 0 else {
                throw CaptureError("cast source traversal incomplete for \(modelName)")
            }
            if strictRegression, modelName == binding.bodyName {
                let audit = Self.vertexLoadAudit(scene)
                guard audit.loadCount >= 2,
                      audit.addressLoadCount > 0,
                      audit.mixedTriangleCount > 0 else {
                    throw CaptureError(
                        "strict Cast regression did not exercise mixed per-load provenance "
                            + "loads=\(audit.loadCount) addressLoads=\(audit.addressLoadCount) "
                            + "mixedTriangles=\(audit.mixedTriangleCount)"
                    )
                }
                bodyVertexLoadAudit = audit
            }
            let matrixHandles = Self.matrixHandles(scene)
            guard !matrixHandles.isEmpty else { throw CaptureError("no model matrix for \(modelName)") }
            matrixHandlesByName[modelName] = matrixHandles
            let isBody = modelName == binding.bodyName
            let isHead = modelName == binding.headName
            let attachmentSwitch: UInt32? = isHead ? 4 : (isBody ? nil : (castFlip ? 5 : 3))
            let modelViewValues: [Int32]
            if isBody {
                modelViewValues = sourceModelView
            } else {
                guard let attachmentSwitch,
                      let attachment = bodyAttachmentTransforms[attachmentSwitch] else {
                    throw CaptureError(
                        "cast \(modelName) has no source body attachment matrix for switch \(attachmentSwitch ?? 0)"
                    )
                }
                // Source constructor_menu18_displaycast sets the attached
                // model's basemtx to the body's resolved switch matrix. Keep
                // that order explicit: camera/model-view first, then the
                // source neck or gun-hand transform.
                let attached = castFlip && !isHead
                    ? Self.multiplyQ16(attachment, Self.zRotationPiQ16())
                    : attachment
                modelViewValues = Self.multiplyQ16(sourceModelView, attached)
            }
            var matrices = try matrixHandles.map {
                try Self.makeMatrix(
                    $0,
                    values: modelViewValues,
                    roleFlags: GoldenEyeSourceMatrixRoleSidecarV6.modelView
                )
            }
            matrices.append(try Self.makeProjectionMatrix(projectionHandle))
            let setup = try GoldenEyeSourceTextureSetupResolverV6.resolve(
                modelName: modelName, model: model, catalog: catalog,
                compiledCommands: scene.commands
            )
            let poseModelHandle: UInt32 = switch modelName {
            case binding.bodyName: sidecar.attachment.bodyModelHandle
            case binding.headName: sidecar.attachment.headModelHandle
            default: sidecar.attachment.weaponModelHandle
            }
            let interpolatedClipPoses = try Self.interpolatedSourcePoseRecords(
                sidecar: sidecar,
                modelHandle: poseModelHandle,
                clipName: clip.clipName,
                frameQ16: castFrameQ16,
                flip: castFlip,
                translationScaleQ16: isBody ? castAnimationTranslationScaleQ16 : 12_307
            )
            // Cast animates the body only. The head and weapon are separate
            // source model instances whose basemtx is the body's neck/hand
            // switch matrix; feeding them a second independent skeleton is a
            // bind-pose diagnostic and stretches the attachments.
            let poses = isBody ? interpolatedClipPoses : []
            if isBody {
                bodyPoseCount = poses.count
                let lowering = try GoldenEyeSourceNodeTransformLowererV6.lower(
                    model: model,
                    scene: scene,
                    poses: interpolatedClipPoses,
                    modelName: modelName,
                    transformContext: .cast
                )
                for switchIndex in [3 as UInt32, 4, 5] {
                    guard let handle = lowering.attachmentBoneHandle(
                        model: model, modelName: modelName, switchIndex: switchIndex
                    ), let transform = lowering.transformByHandle[handle] else {
                        continue
                    }
                    bodyAttachmentTransforms[switchIndex] = Self.matrixValues(transform.matrix_q16)
                }
                if !binding.headName.isEmpty {
                    guard bodyAttachmentTransforms[4] != nil else {
                        throw CaptureError(
                            "cast body is missing source neck switch 4 attachment; available=\(bodyAttachmentTransforms.keys.sorted())"
                        )
                    }
                }
                if !binding.weaponName.isEmpty {
                    guard bodyAttachmentTransforms[castFlip ? 5 : 3] != nil else {
                        throw CaptureError(
                            "cast body is missing source gun-hand switch \(castFlip ? 5 : 3) attachment; available=\(bodyAttachmentTransforms.keys.sorted())"
                        )
                    }
                }
            }
            let roles = try matrices.compactMap { matrix -> GoldenEyeSourceMatrixRoleSidecarV6? in
                guard matrix.roleFlags != 0 else { return nil }
                return try GoldenEyeSourceMatrixRoleSidecarV6(handle: matrix.handle, roleFlags: matrix.roleFlags)
            }
            let result = try GoldenEyeGBISceneBuilderV6.build(
                model: model, modelName: modelName, matrices: matrices,
                viewports: [Self.viewport()], matrixRoles: roles, frame: frame,
                dynamicResolver: sidecar.dynamicResolver, animationPoses: poses,
                transformContext: .cast,
                renderSetupContext: .cast,
                textureSetups: setup.setups
            )
            guard result.presentable, result.unsupportedVisibleCount == 0,
                  !result.snapshot.drawCommands.isEmpty else {
                throw CaptureError(
                    "cast model \(modelName) failed closure presentable=\(result.presentable) "
                        + "unsupported=\(result.unsupportedVisibleCount) "
                        + "draws=\(result.snapshot.drawCommands.count) "
                        + "reasons=\(result.unsupportedReasons)"
                )
            }
            if strictRegression {
                guard result.snapshot.diagnostics.isEmpty,
                      result.snapshot.summary.diagnostic_count == 0,
                      result.vertexResourceTotal > 0,
                      result.vertexResourceManifestHash != 0 else {
                    throw CaptureError(
                        "strict Cast regression emitted diagnostics or an empty vertex-resource manifest for \(modelName)"
                    )
                }
            }
            if (isolatedModel == nil || isolatedModel == modelName)
                && (modelFilter == nil || modelFilter!.contains(modelName)) {
                results.append(result)
            }
        }
        let snapshot = try GoldenEyeCastSceneComposerV6.compose(results, frame: frame)
        if strictRegression {
            guard results.count == 3,
                  snapshot.diagnostics.isEmpty,
                  snapshot.summary.diagnostic_count == 0,
                  snapshot.summary.unsupported_visible_count == 0 else {
                throw CaptureError(
                    "strict Cast regression requires clean three-scene composition "
                        + "results=\(results.count) diagnostics=\(snapshot.diagnostics.count) "
                        + "summaryDiagnostics=\(snapshot.summary.diagnostic_count) "
                        + "unsupported=\(snapshot.summary.unsupported_visible_count)"
                )
            }
        }
        let includesBody = (isolatedModel == nil || isolatedModel == binding.bodyName)
            && (modelFilter == nil || modelFilter!.contains(binding.bodyName))
        let expectedPoseCount = includesBody
            ? bodyPoseCount : 0
        guard snapshot.animationPoses.count == expectedPoseCount else {
            throw CaptureError("cast snapshot must carry body poses only, got \(snapshot.animationPoses.count)")
        }
        let renderSnapshot: GoldenEyeSourceSceneSnapshotV6
        let isolatedDraws: [GESourceDrawCommandV6]?
        if let drawIndexText = ProcessInfo.processInfo.environment["GE_CAST_DRAW_INDEX"],
           let drawIndex = Int(drawIndexText),
           drawIndex >= 0, drawIndex < snapshot.drawCommands.count {
            isolatedDraws = [snapshot.drawCommands[drawIndex]]
            print("cast_draw_isolation=index=\(drawIndex):draw=\(String(snapshot.drawCommands[drawIndex].draw_handle, radix: 16))")
        } else if let drawLimitText = ProcessInfo.processInfo.environment["GE_CAST_DRAW_LIMIT"],
                  let drawLimit = Int(drawLimitText), drawLimit > 0 {
            isolatedDraws = Array(snapshot.drawCommands.prefix(min(drawLimit, snapshot.drawCommands.count)))
            print("cast_draw_isolation=prefix=\(isolatedDraws!.count)")
        } else {
            isolatedDraws = nil
        }
        if let isolatedDraws {
            var summary = snapshot.summary
            summary.draw_count = UInt32(isolatedDraws.count)
            summary.scene_hash ^= UInt64(isolatedDraws.count)
            summary.render_hash ^= UInt64(isolatedDraws.count)
            summary.state_hash ^= UInt64(isolatedDraws.count)
            summary.frame_hash ^= UInt64(isolatedDraws.count)
            renderSnapshot = try GoldenEyeSourceSceneSnapshotV6(
                summary: summary,
                resources: snapshot.resources,
                transforms: snapshot.transforms,
                animationPoses: snapshot.animationPoses,
                vertices: snapshot.vertices,
                indices: snapshot.indices,
                renderStates: snapshot.renderStates,
                drawCommands: isolatedDraws,
                textEvents: snapshot.textEvents,
                audioEvents: snapshot.audioEvents,
                diagnostics: snapshot.diagnostics,
                lightingFrameContext: snapshot.lightingFrameContext
            )
        } else {
            renderSnapshot = snapshot
        }

        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.isOpaque = true
        layer.framebufferOnly = false
        layer.displaySyncEnabled = false
        layer.maximumDrawableCount = 2
        let state = try GoldenEyeMetalDeviceState(device: device, layer: layer)
        // Device state applies the production framebuffer-only default. This
        // capture harness explicitly opts out before acquiring its readback
        // drawable; the Release product keeps the default enabled.
        layer.framebufferOnly = false
        guard let uploadEvent = device.makeSharedEvent() else { throw CaptureError("texture upload event") }
        let store = try GoldenEyeSourceTextureStoreV6(
            context: GoldenEyeSourceTextureStoreV6MetalContext(
                device: device, queue: state.queue, residency: state.sceneResidency,
                completionEvent: uploadEvent
            )
        )
        let models = preparation.models.keys.sorted().compactMap { name in
            preparation.models[name].map { (name: name, model: $0) }
        }
        let plan = try GoldenEyeSourceTextureUploadPlanV6.make(catalog: catalog, models: models)
        _ = try store.upload(plan: plan)
        try store.drain()
        let adapter = try GoldenEyeSourceSceneTextureBindingAdapterV6(store: store, plan: plan)
        let strictTextureAdapter = ProcessInfo.processInfo.environment["GE_CAST_LEGACY_TEXTURES"] == nil
        let pipeline = try GoldenEyeSourceScenePipelineV6(
            device: device, libraryURL: sceneLibraryURL, pixelFormat: .bgra8Unorm
        )

        let referenceRenderer = try GoldenEyeSourceSceneRendererV6(
            state: state, pipeline: pipeline,
            textureResolver: { store.texture(handle: $0) },
            textureBindingAdapter: strictTextureAdapter ? adapter : nil, outputMode: .reference320x240,
            frontFacing: ProcessInfo.processInfo.environment["GE_CAST_WINDING"] == "ccw"
                ? .counterClockwise : .clockwise
        )
        let reference = try referenceRenderer.captureReference320x240(
            snapshot: renderSnapshot,
            to: output.appendingPathComponent("cast-bond-320x240.raw")
        )
        referenceRenderer.shutdown()
        guard Self.hasVisiblePixels(reference.bytes) else { throw CaptureError("cast reference is empty") }
        print("cast_reference_pixel_bounds=\(Self.pixelBounds(reference.bytes, width: 320, height: 240))")

        let width = 1_280
        let height = 960
        layer.drawableSize = CGSize(width: width, height: height)
        layer.frame = CGRect(x: 0, y: 0, width: width, height: height)
        guard let drawable = layer.nextDrawable() else { throw CaptureError("cast HD drawable") }
        let hdRenderer = try GoldenEyeSourceSceneRendererV6(
            state: state, pipeline: pipeline,
            textureResolver: { store.texture(handle: $0) },
            textureBindingAdapter: strictTextureAdapter ? adapter : nil, outputMode: .faithfulHD,
            frontFacing: ProcessInfo.processInfo.environment["GE_CAST_WINDING"] == "ccw"
                ? .counterClockwise : .clockwise
        )
        let evidence = try hdRenderer.render(snapshot: renderSnapshot, suppliedDrawable: drawable)
        hdRenderer.shutdown()
        let hdBytes = try Self.readback(texture: drawable.texture, width: width, height: height)
        guard Self.hasVisiblePixels(hdBytes) else { throw CaptureError("cast HD is empty") }
        print("cast_hd_pixel_bounds=\(Self.pixelBounds(hdBytes, width: width, height: height))")
        let hdRaw = output.appendingPathComponent("cast-bond-faithful-hd.raw")
        let hdPNG = output.appendingPathComponent("cast-bond-faithful-hd.png")
        try hdBytes.write(to: hdRaw, options: .atomic)
        try GoldenEyeReferenceCaptureCodecV6.encodePNG(
            bgra8: hdBytes, width: width, height: height, bytesPerRow: width * 4
        ).write(to: hdPNG, options: .atomic)

        let missing = GoldenEyeCastSceneComposerV6.validIdentityIndices.filter { sourceIndex in
            do {
                let row = try GoldenEyeCastSourceTableV6.identity(sourceIndex: sourceIndex)
                let rowAnimation = try GoldenEyeCastSceneComposerV6.animation(randomWord: UInt32(sourceIndex))
                _ = try GoldenEyeCastSceneComposerV6.resolveModels(
                    identity: row,
                    animation: rowAnimation,
                    availableModelNames: Set(preparation.models.keys),
                    availableHandles: preparation.models.reduce(into: [String: UInt32]()) {
                        $0[$1.key] = $1.value.header.modelHandle
                    },
                    randomWord: UInt32(sourceIndex)
                )
                return false
            } catch {
                return true
            }
        }
        let metadata: [String: Any] = [
            "screen": "Cast",
            "identityCount": GoldenEyeCastSceneComposerV6.validIdentityIndices.count,
            "capturedIdentity": identity.sourceIndex,
            "randomWord": randomWord,
            "capturedBody": binding.bodyName,
            "capturedHead": binding.headName,
            "capturedWeapon": binding.weaponName,
            "animationID": animation.animationID,
            "animationClip": clip.clipName,
            "animationFrame": clip.frame,
            "castTextSourceHashes": textFadePacket.sourceTextHashes,
            "castTextVisibleHashes": textFadePacket.visibleTextHashes,
            "castTextYQ16": textFadePacket.textYQ16,
            "castTextFadeQ16": textFadePacket.fadeQ16,
            "castTextFadeAlphaQ8": textFadePacket.fadeAlphaQ8,
            "castTextFadeOverlayRequired": textFadePacket.fadeOverlayRequired,
            "castTextSource2DFullActorIntro": textFadePacket.source2DFullActorIntro,
            "castTextSourceOrderHash": textFadePacket.sourceOrderHash,
            "bodyPoseOnly": true,
            "bodyPoseCount": bodyPoseCount,
            "sourceAttachmentSwitches": bodyAttachmentTransforms.keys.sorted(),
            "sourceAttachmentMatricesQ16": Dictionary(uniqueKeysWithValues: bodyAttachmentTransforms.map {
                (String($0.key), $0.value)
            }),
            "poseCount": snapshot.animationPoses.count,
            "drawCount": snapshot.drawCommands.count,
            "triangleCount": evidence.triangleCount,
            "unsupportedVisibleCount": snapshot.summary.unsupported_visible_count,
            "diagnosticCount": snapshot.summary.diagnostic_count,
            "missingPreparedIdentityCount": missing.count,
            "missingPreparedIdentityIndices": missing,
            "referenceRawSHA256": reference.rawSHA256,
            "faithfulHDRawSHA256": Self.sha256(hdBytes),
            "faithfulHDWidth": width,
            "faithfulHDHeight": height,
            "projectionConsumptionComplete": results.allSatisfy { $0.projectionConsumption.isComplete },
            "strictRegression": strictRegression,
            "bodyVertexLoadCount": bodyVertexLoadAudit?.loadCount ?? 0,
            "bodyAddressVertexLoadCount": bodyVertexLoadAudit?.addressLoadCount ?? 0,
            "bodyMixedVertexLoadTriangleCount": bodyVertexLoadAudit?.mixedTriangleCount ?? 0,
            "vertexResourceTotals": Dictionary(uniqueKeysWithValues: results.enumerated().map {
                (String($0.offset), Int($0.element.vertexResourceTotal))
            }),
            "vertexResourceManifestHashes": Dictionary(uniqueKeysWithValues: results.enumerated().map {
                (String($0.offset), String($0.element.vertexResourceManifestHash, radix: 16))
            }),
            "sourceModelHandles": handles,
            "matrixHandles": matrixHandlesByName,
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys, .prettyPrinted])
        try metadataData.write(to: output.appendingPathComponent("cast-reference.json"), options: .atomic)
        try store.shutdown()
        state.stopCapture()
        print("goldeneye_cast_reference_capture_v6_smoke: PASS capturedIdentity=\(identity.sourceIndex) missingPrepared=\(missing.count) reference=\(reference.rawSHA256) hd=\(Self.sha256(hdBytes))")
    }

    private static func matrixHandles(_ scene: GESourceSceneV6) -> [UInt32] {
        var values = Set<UInt32>()
        for command in scene.commands where command.macro == "gsSPMatrix" {
            guard let token = command.arguments.first else { continue }
            switch token {
            case .handle(_, let handle): values.insert(handle)
            case .integer(let value): values.insert(UInt32(truncatingIfNeeded: value))
            case .constant(_, let value): values.insert(value)
            default: break
            }
        }
        return values.filter { $0 != 0 }.sorted()
    }

    private struct VertexLoadAudit {
        let loadCount: Int
        let addressLoadCount: Int
        let mixedTriangleCount: Int
    }

    /// Verify that the strict fixture reaches the source hazard fixed by the
    /// decoder provenance path: one triangle must consume cache slots loaded
    /// by different gsSPVertex commands, including an address-marked load.
    private static func vertexLoadAudit(_ scene: GESourceSceneV6) -> VertexLoadAudit {
        func integer(_ token: GoldenEyeSourceModelV6.TokenValue) -> UInt32? {
            switch token {
            case .integer(let value) where value >= 0:
                return UInt32(exactly: value)
            case .constant(_, let value):
                return value
            default:
                return nil
            }
        }
        func triangleIndices(_ command: GESourceCompiledCommandV6) -> [[UInt32]] {
            let groupSize: Int
            switch command.macro {
            case "gsSP1Triangle": groupSize = 4
            case "gsSP2Triangles": groupSize = 8
            case "gsSP4Triangles": groupSize = 16
            default: return []
            }
            guard command.arguments.count == groupSize else { return [] }
            return stride(from: 0, to: groupSize, by: 4).compactMap { offset in
                guard let a = integer(command.arguments[offset]),
                      let b = integer(command.arguments[offset + 1]),
                      let c = integer(command.arguments[offset + 2]) else {
                    return nil
                }
                return [a, b, c]
            }
        }

        var slotLoad: [UInt32: Int] = [:]
        var loadCount = 0
        var addressLoadCount = 0
        var mixedTriangleCount = 0
        for command in scene.commands {
            if command.macro == "gsSPVertex", command.arguments.count == 3,
               let count = integer(command.arguments[1]),
               let first = integer(command.arguments[2]) {
                if case .handle(.address, _) = command.arguments[0] {
                    addressLoadCount += 1
                }
                for slot in first..<(first + count) {
                    slotLoad[slot] = loadCount
                }
                loadCount += 1
                continue
            }
            for triangle in triangleIndices(command) {
                guard let first = slotLoad[triangle[0]],
                      let second = slotLoad[triangle[1]],
                      let third = slotLoad[triangle[2]],
                      Set([first, second, third]).count > 1 else {
                    continue
                }
                mixedTriangleCount += 1
            }
        }
        return VertexLoadAudit(
            loadCount: loadCount,
            addressLoadCount: addressLoadCount,
            mixedTriangleCount: mixedTriangleCount
        )
    }

    private static func castAnimationClipName(_ animationID: UInt32) throws -> String {
        let names: [UInt32: String] = [
            63: "spotting_bond",
            66: "fire_standing_draw_one_handed_weapon_fast",
            67: "fire_standing_draw_one_handed_weapon_slow",
            72: "fire_step_right_one_handed_weapon",
            76: "fire_kneel_forward_one_handed_weapon_fast",
            89: "running_one_handed_weapon",
            98: "draw_one_handed_weapon_and_stand_up",
            99: "aim_one_handed_weapon_left_right",
            100: "cock_one_handed_weapon_and_turn_around",
            102: "cock_one_handed_weapon_turn_around_and_stand_up",
            103: "draw_one_handed_weapon_and_turn_around",
            153: "drop_weapon_and_show_fight_stance",
            163: "laughing_in_disbelief",
            70: "fire_hip_forward_one_handed_weapon",
            74: "fire_standing_left_one_handed_weapon_fast",
            80: "fire_kneel_left_one_handed_weapon_fast",
            97: "draw_one_handed_weapon_and_look_around",
            150: "aim_one_handed_weapon_left",
            151: "aim_one_handed_weapon_right",
            152: "conversation",
            161: "conversation_listener",
            160: "conversation_cleaned",
        ]
        guard let value = names[animationID] else {
            throw CaptureError("cast animation (animationID) has no prepared source clip")
        }
        return value
    }

    private static func matrixValues<T>(_ tuple: T) -> [Int32] {
        withUnsafeBytes(of: tuple) { raw in
            Array(raw.bindMemory(to: Int32.self).prefix(16))
        }
    }

    private static func multiplyQ16(_ lhs: [Int32], _ rhs: [Int32]) -> [Int32] {
        guard lhs.count == 16, rhs.count == 16 else {
            return Array(repeating: 0, count: 16)
        }
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
        return result
    }

    private static func zRotationPiQ16() -> [Int32] {
        [
            -65_536, 0, 0, 0,
            0, -65_536, 0, 0,
            0, 0, 65_536, 0,
            0, 0, 0, 65_536,
        ]
    }

    private static func interpolatedSourcePoseRecords(
        sidecar: GoldenEyeGunbarrelDynamicSidecarV6,
        modelHandle: UInt32,
        clipName: String,
        frameQ16: Int64,
        flip: Bool,
        translationScaleQ16: Int32
    ) throws -> [GESourceAnimationPoseV6] {
        let clip = try sidecar.clip(named: clipName)
        let frame = UInt32(max(0, frameQ16 >> 16)) % clip.frameCount
        let nextFrame = (frame + 1) % clip.frameCount
        let fraction = frameQ16 & 0xffff
        let first = try sidecar.poses(
            modelHandle: modelHandle, clipName: clipName, frame: frame,
            flip: flip, translationScaleQ16: translationScaleQ16
        ).map { Self.sourcePoseRecord($0) }
        guard fraction != 0 else { return first }
        let second = try sidecar.poses(
            modelHandle: modelHandle, clipName: clipName, frame: nextFrame,
            flip: flip, translationScaleQ16: translationScaleQ16
        ).map { Self.sourcePoseRecord($0) }
        guard first.count == second.count else {
            throw CaptureError("Cast interpolated pose count mismatch")
        }
        func blend(_ lhs: Int32, _ rhs: Int32) -> Int32 {
            Int32(clamping: Int64(lhs) + ((Int64(rhs) - Int64(lhs)) * fraction >> 16))
        }
        return zip(first, second).map { lhs, rhs in
            guard lhs.node_handle == rhs.node_handle else { return lhs }
            var value = lhs
            value.translation_q16 = (
                blend(lhs.translation_q16.0, rhs.translation_q16.0),
                blend(lhs.translation_q16.1, rhs.translation_q16.1),
                blend(lhs.translation_q16.2, rhs.translation_q16.2)
            )
            value.rotation_q16 = (
                blend(lhs.rotation_q16.0, rhs.rotation_q16.0),
                blend(lhs.rotation_q16.1, rhs.rotation_q16.1),
                blend(lhs.rotation_q16.2, rhs.rotation_q16.2),
                blend(lhs.rotation_q16.3, rhs.rotation_q16.3)
            )
            value.scale_q16 = (
                blend(lhs.scale_q16.0, rhs.scale_q16.0),
                blend(lhs.scale_q16.1, rhs.scale_q16.1),
                blend(lhs.scale_q16.2, rhs.scale_q16.2)
            )
            value.pose_hash = lhs.pose_hash ^ rhs.pose_hash ^ UInt64(fraction)
            return value
        }
    }

    private static func sourcePoseRecord(
        _ pose: GoldenEyeGunbarrelPoseV6,
        rootTranslationScaleQ16: Int32? = nil
    ) -> GESourceAnimationPoseV6 {
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
        let rootTranslation: SIMD3<Int32>
        if pose.jointIndex == 0, let rootTranslationScaleQ16 {
            rootTranslation = SIMD3(
                Int32((Int64(pose.translationQ16.x) * Int64(rootTranslationScaleQ16)) / 12_307),
                Int32((Int64(pose.translationQ16.y) * Int64(rootTranslationScaleQ16)) / 12_307),
                Int32((Int64(pose.translationQ16.z) * Int64(rootTranslationScaleQ16)) / 12_307)
            )
        } else {
            rootTranslation = pose.translationQ16
        }
        value.translation_q16 = (rootTranslation.x, rootTranslation.y, rootTranslation.z)
        value.rotation_q16 = (pose.rotationQ16.x, pose.rotationQ16.y, pose.rotationQ16.z, pose.rotationQ16.w)
        value.scale_q16 = (pose.scaleQ16.x, pose.scaleQ16.y, pose.scaleQ16.z)
        value.pose_hash = pose.poseHash
        return value
    }

    private static func makeMatrix(
        _ handle: UInt32,
        values: [Int32],
        roleFlags: UInt32
    ) throws -> GoldenEyeGBIMatrixResourceV6 {
        return try GoldenEyeGBIMatrixResourceV6(handle: handle, values: values, roleFlags: roleFlags)
    }

    /// Exact source constructor_menu18_displaycast midpoint camera: FOV 46,
    /// distance 70...150, height -100...100, then +52.5 eye and -10 target
    /// offsets. Root smoothing is zero at the deterministic capture origin.
    private static func sourceCastModelView(
        distance: Float,
        angle: Float,
        height: Float,
        rootOffset: SIMD3<Float> = SIMD3(repeating: 0),
        targetOffset: SIMD3<Float>? = nil
    ) -> [Int32] {
        let targetOffset = targetOffset ?? rootOffset
        let cameraX = distance * sin(angle) + cos(angle) * 0.2 * distance + rootOffset.x
        let cameraY = height + 52.5 + rootOffset.y
        let cameraZ = distance * cos(angle) - sin(angle) * 0.2 * distance + rootOffset.z
        let targetX = cos(angle) * 0.2 * distance + targetOffset.x
        let targetY = targetOffset.y
        let targetZ = -sin(angle) * 0.2 * distance + targetOffset.z
        let eye = SIMD3(cameraX, cameraY, cameraZ)
        let target = SIMD3(targetX, targetY, targetZ)
        let forward = simd_normalize(target - eye)
        let up = SIMD3<Float>(0, 1, 0)
        let right = simd_normalize(simd_cross(forward, up))
        let correctedUp = simd_cross(right, forward)
        let scale: Float = 1.0 // camera basis; Cast model scale is in root context
        let values: [Float] = [
            right.x * scale, correctedUp.x * scale, -forward.x * scale, 0,
            right.y * scale, correctedUp.y * scale, -forward.y * scale, 0,
            right.z * scale, correctedUp.z * scale, -forward.z * scale, 0,
            -simd_dot(right, eye), -simd_dot(correctedUp, eye), simd_dot(forward, eye), 1,
        ]
        // The authored model scale belongs to the 3x3 model basis. Keep the
        // look-at translation in camera units; scaling it would turn the
        // source 110-unit Cast camera into an 11-unit near clip and crop the
        // actor even when the skeleton/attachments are correct.
        return values.map { Int32($0 * 65_536.0) }
    }

    private static func sourceCastRandomFixture(seed: UInt64) -> (
        flipWord: UInt32,
        flip: Bool,
        cameraStart: (distance: Float, angle: Float, height: Float)
    ) {
        var state = seed &+ 1 // randomSetSeed(seed) stores seed + 1.
        func next(_ state: inout UInt64) -> UInt32 {
            let mixed = (((state << 32) | (state >> 1)) ^ (state << 12))
            state = mixed ^ ((mixed >> 20) & 0x0fff)
            return UInt32(truncatingIfNeeded: state)
        }
        let flipWord = next(&state)
        _ = next(&state) // intro animation selection; the capture fixes row 1.
        let distStart = Float(next(&state)) / Float(UInt32.max)
        _ = next(&state) // distEnd; g_MenuTimer=0 uses distStart.
        let angleStart = (Float(next(&state)) / Float(UInt32.max) - 0.5) * Float.pi * 2.0
        _ = next(&state) // angleEnd; g_MenuTimer=0 uses angleStart.
        let heightStart = (Float(next(&state)) / Float(UInt32.max)) * 200.0 - 100.0
        return (
            flipWord: flipWord,
            flip: (flipWord & 1) != 0,
            cameraStart: (distance: distStart * 80.0 + 70.0, angle: angleStart, height: heightStart)
        )
    }

    private static func makeProjectionMatrix(_ handle: UInt32) throws -> GoldenEyeGBIMatrixResourceV6 {
        let f: Double = 1.0 / tan(46.0 * .pi / 360.0)
        let aspect = 4.0 / 3.0
        let near = 10.0
        let far = 2_000.0
        let values = [
            Int32((f / aspect) * 65_536), 0, 0, 0,
            0, Int32(f * 65_536), 0, 0,
            0, 0, Int32(((far + near) / (near - far)) * 65_536), -65_536,
            0, 0, Int32(((2.0 * far * near) / (near - far)) * 65_536), 0,
        ]
        return try GoldenEyeGBIMatrixResourceV6(handle: handle, values: values, roleFlags: GoldenEyeSourceMatrixRoleSidecarV6.projection)
    }

    private static func viewport() throws -> GoldenEyeGBIViewportResourceV6 {
        try GoldenEyeGBIViewportResourceV6(
            handle: 0x9000_0001,
            values: [160 << 16, 120 << 16, 1 << 16, 1 << 16, 160 << 16, 120 << 16, 0, 1 << 16]
        )
    }

    private static func hasVisiblePixels(_ data: Data) -> Bool {
        stride(from: 0, to: data.count, by: 4).contains {
            data[$0] != 0 || data[$0 + 1] != 0 || data[$0 + 2] != 0
        }
    }

    private static func pixelBounds(_ data: Data, width: Int, height: Int) -> String {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                guard offset + 2 < data.count else { continue }
                if data[offset] != 0 || data[offset + 1] != 0 || data[offset + 2] != 0 {
                    minX = min(minX, x); minY = min(minY, y)
                    maxX = max(maxX, x); maxY = max(maxY, y)
                }
            }
        }
        return "\(minX),\(minY),\(maxX),\(maxY)"
    }

    private static func readback(texture: any MTLTexture, width: Int, height: Int) throws -> Data {
        guard let buffer = texture.device.makeBuffer(length: width * height * 4, options: .storageModeShared) else {
            throw CaptureError("HD readback buffer")
        }
        let commandBuffer = texture.device.makeCommandQueue()!.makeCommandBuffer()!
        let blit = commandBuffer.makeBlitCommandEncoder()!
        blit.copy(
            from: texture, sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: width, height: height, depth: 1),
            to: buffer, destinationOffset: 0,
            destinationBytesPerRow: width * 4, destinationBytesPerImage: width * height * 4
        )
        blit.endEncoding(); commandBuffer.commit(); commandBuffer.waitUntilCompleted()
        return Data(bytes: buffer.contents(), count: width * height * 4)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private struct CaptureError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}
