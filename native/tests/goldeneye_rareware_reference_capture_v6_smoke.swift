import Foundation
import Metal
import QuartzCore
import CryptoKit

@available(macOS 27.0, *)
private struct RarewareCaptureScene {
    let frame: GoldenEyeRarewareFrameV6
    let build: GoldenEyeGBISceneBuildResultV6
    let textureSetups: [GoldenEyeSourceTextureSetupV6]
}

@available(macOS 27.0, *)
@main
struct GoldenEyeRarewareReferenceCaptureV6Smoke {
    private static let rarewareScreen = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_RAREWARE)
    private static let modelMatrixHandle: UInt32 = 0xF300_0001

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4) else {
            print("goldeneye_rareware_reference_capture_v6_smoke: SKIP (Metal 4 device unavailable)")
            return
        }
        let arguments = Array(CommandLine.arguments.dropFirst())
        let root = URL(
            fileURLWithPath: arguments.first ?? "build/native/source-frontend-v6",
            isDirectory: true
        )
        let sceneLibraryURL = URL(
            fileURLWithPath: arguments.dropFirst().first
                ?? "build/native/rareware-capture-v6/GoldenEyeSourceSceneV6.metallib"
        )
        let outputDirectory = URL(
            fileURLWithPath: arguments.dropFirst().dropFirst().first
                ?? "build/native/rareware-reference-capture-v6",
            isDirectory: true
        )
        guard FileManager.default.fileExists(atPath: sceneLibraryURL.path) else {
            print("goldeneye_rareware_reference_capture_v6_smoke: SKIP (source-scene metallib unavailable)")
            return
        }
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let preparation = try GoldenEyeSourceProductPreparationV6.load(rootURL: root)
        let model = try preparation.model(named: GoldenEyeRarewareFrameV6.modelName)
        let phases: [(name: String, nativeTick: UInt64, sourceTimer: UInt32, pairPhase: UInt32)] = [
            ("odd-t20", 41, 20, 1),
            ("even-t70", 142, 70, 0),
            ("front-t200", 402, 200, 0),
            ("late-t260", 522, 260, 0),
        ]
        let scenes = try phases.map { phase in
            try makeScene(
                model: model,
                nativeTick: phase.nativeTick,
                sourceTimer: phase.sourceTimer,
                pairPhase: phase.pairPhase
            )
        }
        for scene in scenes {
            let diagnosticCommands = scene.build.snapshot.diagnostics.prefix(8).map { $0.command_id }
            precondition(
                scene.build.snapshot.summary.unsupported_visible_count == 0,
                "Rareware scene has unsupported visible work at \(scene.frame.sourceTimer) " +
                    "unsupported=\(scene.build.unsupportedVisibleCount) " +
                    "decoder=\(scene.build.decoderUnsupportedCount) " +
                    "reasons=\(scene.build.unsupportedReasons.prefix(4)) " +
                    "diagnosticCommands=\(diagnosticCommands)"
            )
            precondition(
                scene.build.decoderUnsupportedCount == 0,
                "Rareware decoder unsupported at \(scene.frame.sourceTimer) " +
                    "decoder=\(scene.build.decoderUnsupportedCount) " +
                    "reasons=\(scene.build.unsupportedReasons.prefix(4)) " +
                    "diagnosticCommands=\(diagnosticCommands)"
            )
            precondition(scene.build.projectionConsumption.isComplete, "Rareware projection incomplete")
            precondition(scene.build.triangleCount == GoldenEyeRarewareFrameV6.expectedTriangleCount,
                         "Rareware triangle count")
        }

        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.isOpaque = true
        layer.framebufferOnly = true
        layer.displaySyncEnabled = false
        layer.maximumDrawableCount = 2
        let state = try GoldenEyeMetalDeviceState(device: device, layer: layer)
        guard let uploadEvent = device.makeSharedEvent() else {
            throw CaptureError("texture upload shared event unavailable")
        }
        uploadEvent.label = "GoldenEye.Rareware.Reference.TextureUpload"
        let textureStore = try GoldenEyeSourceTextureStoreV6(
            context: GoldenEyeSourceTextureStoreV6MetalContext(
                device: device,
                queue: state.queue,
                residency: state.sceneResidency,
                completionEvent: uploadEvent
            )
        )
        let texturePlan = try GoldenEyeSourceTextureUploadPlanV6.make(
            catalog: preparation.catalog,
            models: [(name: GoldenEyeRarewareFrameV6.modelName, model: model)]
        )
        _ = try textureStore.upload(plan: texturePlan)
        try textureStore.drain()
        let textureBindingAdapter = try GoldenEyeSourceSceneTextureBindingAdapterV6(
            store: textureStore,
            plan: texturePlan
        )
        let pipeline = try GoldenEyeSourceScenePipelineV6(
            device: device,
            libraryURL: sceneLibraryURL,
            pixelFormat: .bgra8Unorm
        )

        var phaseMetadata: [[String: Any]] = []
        let referenceRenderer = try GoldenEyeSourceSceneRendererV6(
            state: state,
            pipeline: pipeline,
            textureResolver: { handle in textureStore.texture(handle: handle) },
            textureBindingAdapter: textureBindingAdapter,
            outputMode: .reference320x240,
            frontFacing: .counterClockwise
        )
        for (phase, scene) in zip(phases, scenes) {
            let rawURL = outputDirectory.appendingPathComponent("rareware-320x240-\(phase.name).raw")
            let capture = try referenceRenderer.captureReference320x240(
                snapshot: scene.build.snapshot,
                to: rawURL
            )
            precondition(capture.width == 320 && capture.height == 240)
            precondition(capture.evidence.triangleCount == Int(GoldenEyeRarewareFrameV6.expectedTriangleCount))
            let stats = pixelStats(capture.bytes)
            if phase.sourceTimer < 260 {
                precondition(stats.nonBlackPixels > 0, "Rareware phase is unexpectedly black")
            } else {
                precondition(stats.nonBlackPixels == 0, "Rareware late fade is not black")
            }
            phaseMetadata.append([
                "name": phase.name,
                "nativeTick": phase.nativeTick,
                "sourceTimer": phase.sourceTimer,
                "pairPhase": phase.pairPhase,
                "rotationDegreesQ16": scene.frame.rotationDegreesQ16,
                "fadeAlpha": scene.frame.fadeAlpha,
                "frameHash": String(format: "%016llx", scene.frame.frameHash),
                "sceneHash": String(format: "%016llx", scene.build.snapshot.summary.scene_hash),
                "renderHash": String(format: "%016llx", scene.build.snapshot.summary.render_hash),
                "rawSHA256": capture.rawSHA256,
                "png": capture.pngURL?.path ?? "",
                "nonBlackPixels": stats.nonBlackPixels,
                "maxRGB": stats.maxRGB,
                "drawCount": capture.evidence.drawCount,
                "triangleCount": capture.evidence.triangleCount,
                "unsupportedVisibleCount": scene.build.unsupportedVisibleCount,
                "projectionConsumed": scene.build.projectionConsumption.consumedDrawCount,
                "projectionRequired": scene.build.projectionConsumption.requiredDrawCount,
            ])
        }
        // Isolate each lowered draw at the near-front, non-zero-fade phase.
        // The four letter-material draws must each contribute pixels; a full
        // scene hash alone could hide a missing mip-chain binding behind the
        // plaque/body passes.  The isolated snapshots retain the source
        // transforms/resources and only compact one validated draw's copied
        // vertex/index range.
        guard let frontScene = scenes.first(where: { $0.frame.sourceTimer == 200 }) else {
            throw CaptureError("front-facing Rareware phase is missing")
        }
        var isolatedMetadata: [[String: Any]] = []
        for drawIndex in frontScene.build.snapshot.drawCommands.indices {
            let isolated = try isolatedSnapshot(
                frontScene.build.snapshot,
                drawIndex: drawIndex
            )
            let rawURL = outputDirectory.appendingPathComponent(
                "rareware-isolated-draw\(drawIndex)-front-t200.raw"
            )
            let capture = try referenceRenderer.captureReference320x240(
                snapshot: isolated,
                to: rawURL
            )
            let stats = pixelStats(capture.bytes)
            let isolatedVisible = stats.nonBlackPixels > 0
            if !isolatedVisible {
                FileHandle.standardError.write(Data(
                    "rareware isolated draw=\(drawIndex) resource=0x\(String(frontScene.build.snapshot.drawCommands[drawIndex].resource_handle, radix: 16)) is black\n".utf8
                ))
            }
            precondition(isolatedVisible, "isolated Rareware draw \(drawIndex) is black")
            let draw = frontScene.build.snapshot.drawCommands[drawIndex]
            guard let renderState = frontScene.build.snapshot.renderStateByHandle[draw.render_state_handle],
                  let setup = frontScene.textureSetups.first(where: {
                      $0.resourceHandle == draw.resource_handle && $0.tile == 0
                  }) else {
                throw CaptureError("missing typed Rareware setup for isolated draw \(drawIndex)")
            }
            if (1...4).contains(drawIndex) {
                precondition(setup.maxLOD == 5, "letter draw \(drawIndex) lost source maxLOD=5")
                precondition(setup.levels.count == 6, "letter draw \(drawIndex) lost six-level mip chain")
                precondition(setup.tileState.bounds.ulsQ2 == 2 && setup.tileState.bounds.ultQ2 == 2 &&
                             setup.tileState.bounds.lrsQ2 == 126 && setup.tileState.bounds.lrtQ2 == 126,
                             "letter draw \(drawIndex) source tile bounds drifted")
                precondition(renderState.raw_othermode_h == 0x0019_2c00,
                             "letter draw \(drawIndex) lost source perspective/filter/LOD word")
                let hasLODSelector = [
                    renderState.cycle0_color_a, renderState.cycle0_color_b,
                    renderState.cycle0_color_c, renderState.cycle0_color_d,
                    renderState.cycle0_alpha_a, renderState.cycle0_alpha_b,
                    renderState.cycle0_alpha_c, renderState.cycle0_alpha_d,
                    renderState.cycle1_color_a, renderState.cycle1_color_b,
                    renderState.cycle1_color_c, renderState.cycle1_color_d,
                    renderState.cycle1_alpha_a, renderState.cycle1_alpha_b,
                    renderState.cycle1_alpha_c, renderState.cycle1_alpha_d,
                ].contains(9)
                precondition(hasLODSelector, "letter draw \(drawIndex) lost LOD_FRACTION selector")
            }
            isolatedMetadata.append([
                "drawIndex": drawIndex,
                "resourceHandle": draw.resource_handle,
                "rawSHA256": capture.rawSHA256,
                "png": capture.pngURL?.path ?? "",
                "nonBlackPixels": stats.nonBlackPixels,
                "maxRGB": stats.maxRGB,
                "drawCount": capture.evidence.drawCount,
                "triangleCount": capture.evidence.triangleCount,
                "setupTile": setup.tile,
                "setupMaxLOD": setup.maxLOD,
                "setupMipLevels": setup.levels.count,
                "tileBoundsQ2": [setup.tileState.bounds.ulsQ2, setup.tileState.bounds.ultQ2,
                                 setup.tileState.bounds.lrsQ2, setup.tileState.bounds.lrtQ2],
                "rawOtherModeH": renderState.raw_othermode_h,
            ])
        }
        referenceRenderer.shutdown()

        layer.framebufferOnly = false
        layer.drawableSize = CGSize(width: 1_280, height: 960)
        layer.frame = CGRect(x: 0, y: 0, width: 1_280, height: 960)
        for (phase, scene) in zip(phases, scenes) {
            guard let drawable = layer.nextDrawable() else {
                throw CaptureError("Faithful HD drawable unavailable for \(phase.name)")
            }
            let hdRenderer = try GoldenEyeSourceSceneRendererV6(
                state: state,
                pipeline: pipeline,
                textureResolver: { handle in textureStore.texture(handle: handle) },
                textureBindingAdapter: textureBindingAdapter,
                outputMode: .faithfulHD,
                frontFacing: .counterClockwise
            )
            let evidence = try hdRenderer.render(
                snapshot: scene.build.snapshot,
                suppliedDrawable: drawable
            )
            hdRenderer.shutdown()
            let bytes = try readback(texture: drawable.texture, width: 1_280, height: 960)
            let rawURL = outputDirectory.appendingPathComponent("rareware-faithful-hd-\(phase.name).raw")
            let pngURL = outputDirectory.appendingPathComponent("rareware-faithful-hd-\(phase.name).png")
            try bytes.write(to: rawURL, options: .atomic)
            try GoldenEyeReferenceCaptureCodecV6.encodePNG(
                bgra8: bytes,
                width: 1_280,
                height: 960,
                bytesPerRow: 1_280 * 4
            ).write(to: pngURL, options: .atomic)
            precondition(evidence.triangleCount == Int(GoldenEyeRarewareFrameV6.expectedTriangleCount))
            let stats = pixelStats(bytes)
            if phase.sourceTimer < 260 {
                precondition(stats.nonBlackPixels > 0, "Rareware HD phase is unexpectedly black")
            } else {
                precondition(stats.nonBlackPixels == 0, "Rareware HD late fade is not black")
            }
            if let index = phaseMetadata.firstIndex(where: { ($0["name"] as? String) == phase.name }) {
                phaseMetadata[index]["hdRawSHA256"] = sha256(bytes)
                phaseMetadata[index]["hdPNG"] = pngURL.path
                phaseMetadata[index]["hdNonBlackPixels"] = stats.nonBlackPixels
                phaseMetadata[index]["hdMaxRGB"] = stats.maxRGB
                phaseMetadata[index]["hdDrawCount"] = evidence.drawCount
                phaseMetadata[index]["hdTriangleCount"] = evidence.triangleCount
            }
        }

        let metadata: [String: Any] = [
            "screen": "Rareware",
            "frontFacing": "counterClockwise",
            "sourceDisplayListCount": GoldenEyeRarewareFrameV6.expectedDisplayListCount,
            "sourceCommandCount": GoldenEyeRarewareFrameV6.expectedCommandCount,
            "sourceVertexCount": GoldenEyeRarewareFrameV6.expectedVertexCount,
            "sourceTriangleCount": GoldenEyeRarewareFrameV6.expectedTriangleCount,
            "sourceTextureCount": GoldenEyeRarewareFrameV6.expectedTextureCount,
            "sourceMipCount": GoldenEyeRarewareFrameV6.expectedMipCount,
            "sourceMipChainCount": GoldenEyeRarewareFrameV6.expectedMipChainCount,
            "sourceCommandHash": String(format: "%016llx", GoldenEyeRarewareFrameV6.expectedSourceCommandHash),
            "sourceSFXAssetID": GoldenEyeRarewareFrameV6.rarewareSFXAssetID,
            "sourceTextureHandles": scenes.first?.frame.textureHandles ?? [],
            "sourceMipLevelsByTexture": scenes.first?.frame.mipLevelsByTexture ?? [],
            "phases": phaseMetadata,
            "isolatedFrontDraws": isolatedMetadata,
            "faithfulHDWidth": 1_280,
            "faithfulHDHeight": 960,
            "metalValidationRequested": true,
            "unsupportedVisibleCount": scenes.map { $0.build.unsupportedVisibleCount }.max() ?? 0,
            "projectionConsumptionComplete": scenes.allSatisfy { $0.build.projectionConsumption.isComplete },
        ]
        let metadataURL = outputDirectory.appendingPathComponent("rareware-reference.json")
        try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys, .prettyPrinted])
            .write(to: metadataURL, options: .atomic)

        try textureStore.shutdown()
        state.stopCapture()
        print("rareware_reference_metadata=\(metadataURL.path)")
        print("goldeneye_rareware_reference_capture_v6_smoke: PASS")
    }

    private static func makeScene(
        model: GoldenEyeSourceModelV6,
        nativeTick: UInt64,
        sourceTimer: UInt32,
        pairPhase: UInt32
    ) throws -> RarewareCaptureScene {
        let frame = try GoldenEyeRarewareFrameV6.make(
            model: model,
            nativeTick: nativeTick,
            referenceTick: nativeTick / 2,
            sourceTimer: sourceTimer,
            pairPhase: pairPhase
        )
        let resolver = GESourceModelDynamicResolverV6(resolvedModels: [GoldenEyeRarewareFrameV6.modelName])
        let compilation = GESourceModelCompilerV6.compile(
            model,
            modelName: GoldenEyeRarewareFrameV6.modelName,
            dynamicResolver: resolver
        )
        guard compilation.status == .complete,
              compilation.diagnostics.isEmpty,
              let compiledScene = compilation.scene else {
            throw CaptureError("Rareware dynamic source compilation failed")
        }
        let setupScene = GoldenEyeGBISceneBuilderV6.rarewareSceneWithOuterSetup(
            model: model,
            scene: compiledScene
        )
        let preparationRoot = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first
            ?? "build/native/source-frontend-v6", isDirectory: true)
        let catalog = try GoldenEyeSourceFrontendCatalog.load(preparedAssetRoot: preparationRoot)
        let setupResult = try GoldenEyeSourceTextureSetupResolverV6.resolve(
            modelName: GoldenEyeRarewareFrameV6.modelName,
            model: model,
            catalog: catalog,
            compiledCommands: setupScene.commands
        )
        let matrixInput = try GoldenEyeSourceFrontendMatrixInputV6(
            screen: rarewareScreen,
            nativeTick: nativeTick,
            referenceTick: nativeTick / 2,
            sourceTimer: sourceTimer,
            pairPhase: pairPhase
        )
        let matrixFrame = try GoldenEyeSourceFrontendMatricesV6.make(
            input: matrixInput,
            modelMatrixHandle: modelMatrixHandle,
            viewportWidth: 440,
            viewportHeight: 330
        )
        let sceneFrame = try GoldenEyeGBISceneFrameContextV6(
            nativeTick: nativeTick,
            referenceTick: nativeTick / 2,
            sourceTimer: sourceTimer,
            pairPhase: pairPhase,
            screen: rarewareScreen,
            viewportWidth: 440,
            viewportHeight: 330
        )
        let resolvedScene = GoldenEyeGBIResolvedSceneInputV6(
            scene: setupScene,
            vertexResources: try GoldenEyeGBISceneBuilderV6.vertexResourceOverrides(
                model: model,
                scene: setupScene
            ),
            additionalTextureHandles: model.textures.map(\.resourceHandle)
        )
        let build = try GoldenEyeGBISceneBuilderV6.build(
            model: model,
            modelName: GoldenEyeRarewareFrameV6.modelName,
            matrices: matrixFrame.resources.matrices,
            viewports: matrixFrame.resources.viewports,
            frame: sceneFrame,
            dynamicResolver: resolver,
            textureSetups: setupResult.setups,
            resolvedScene: resolvedScene
        )
        return RarewareCaptureScene(
            frame: frame,
            build: build,
            textureSetups: setupResult.setups
        )
    }

    private static func pixelStats(_ bytes: Data) -> (nonBlackPixels: Int, maxRGB: UInt8) {
        var nonBlack = 0
        var maximum: UInt8 = 0
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            let blue = bytes[offset]
            let green = bytes[offset + 1]
            let red = bytes[offset + 2]
            if blue != 0 || green != 0 || red != 0 { nonBlack += 1 }
            maximum = max(maximum, max(red, max(green, blue)))
        }
        return (nonBlack, maximum)
    }

    private static func isolatedSnapshot(
        _ snapshot: GoldenEyeSourceSceneSnapshotV6,
        drawIndex: Int
    ) throws -> GoldenEyeSourceSceneSnapshotV6 {
        guard snapshot.drawCommands.indices.contains(drawIndex) else {
            throw CaptureError("isolated draw index out of range")
        }
        var draw = snapshot.drawCommands[drawIndex]
        let firstVertex = Int(draw.first_vertex)
        let vertexEnd = firstVertex + Int(draw.vertex_count)
        let firstIndex = Int(draw.first_index)
        let indexEnd = firstIndex + Int(draw.index_count)
        guard firstVertex >= 0, firstIndex >= 0,
              vertexEnd <= snapshot.vertices.count,
              indexEnd <= snapshot.indices.count else {
            throw CaptureError("isolated draw range out of bounds")
        }
        let vertices = Array(snapshot.vertices[firstVertex..<vertexEnd])
        var indices = Array(snapshot.indices[firstIndex..<indexEnd])
        for index in indices.indices {
            indices[index].vertex0 &-= UInt32(firstVertex)
            indices[index].vertex1 &-= UInt32(firstVertex)
            indices[index].vertex2 &-= UInt32(firstVertex)
        }
        draw.draw_handle = 0xF700_0000 | UInt32(drawIndex + 1)
        draw.first_vertex = 0
        draw.first_index = 0
        draw.vertex_count = UInt32(vertices.count)
        draw.index_count = UInt32(indices.count)
        draw.draw_hash ^= UInt64(drawIndex + 1)
        if draw.draw_hash == 0 { draw.draw_hash = 1 }

        var summary = snapshot.summary
        summary.vertex_count = UInt32(vertices.count)
        summary.index_count = UInt32(indices.count)
        summary.draw_count = 1
        summary.unsupported_visible_count = 0
        summary.scene_hash ^= UInt64(drawIndex + 1)
        summary.render_hash ^= UInt64(drawIndex + 1) << 16
        summary.frame_hash ^= UInt64(drawIndex + 1) << 32
        if summary.scene_hash == 0 { summary.scene_hash = 1 }
        if summary.render_hash == 0 { summary.render_hash = 1 }
        if summary.frame_hash == 0 { summary.frame_hash = 1 }
        return try GoldenEyeSourceSceneSnapshotV6(
            summary: summary,
            resources: snapshot.resources,
            transforms: snapshot.transforms,
            animationPoses: snapshot.animationPoses,
            vertices: vertices,
            indices: indices,
            renderStates: snapshot.renderStates,
            drawCommands: [draw],
            textEvents: snapshot.textEvents,
            audioEvents: snapshot.audioEvents,
            diagnostics: snapshot.diagnostics,
            lightingFrameContext: snapshot.lightingFrameContext
        )
    }

    private static func readback(
        texture: any MTLTexture,
        width: Int,
        height: Int
    ) throws -> Data {
        guard texture.width == width, texture.height == height else {
            throw CaptureError("drawable dimensions do not match HD target")
        }
        var bytes = Data(repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            texture.getBytes(
                raw.baseAddress!,
                bytesPerRow: width * 4,
                from: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0
            )
        }
        return bytes
    }
}

@available(macOS 27.0, *)
private struct CaptureError: Error, CustomStringConvertible {
    let detail: String
    init(_ detail: String) { self.detail = detail }
    var description: String { "Rareware capture failed: \(detail)" }
}

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
