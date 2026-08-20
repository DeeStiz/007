import Foundation
import Metal
import QuartzCore

private func hasNonBlackRGB(_ bytes: Data) -> Bool {
    stride(from: 0, to: bytes.count, by: 4).contains { offset in
        bytes[offset] != 0 || bytes[offset + 1] != 0 || bytes[offset + 2] != 0
    }
}

private func bgraPixel(_ bytes: Data, x: Int, y: Int, width: Int = 320) -> (UInt8, UInt8, UInt8, UInt8) {
    let offset = (y * width + x) * 4
    guard x >= 0, y >= 0, offset >= 0, offset + 3 < bytes.count else {
        return (0, 0, 0, 0)
    }
    return (bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
}

private func source2DManifestHash(_ batch: GoldenEyeSource2DMetalBatchV6) -> UInt64 {
    var hash: UInt64 = 1_469_598_103_934_665_603
    func mix(_ value: UInt64) { hash = (hash ^ value) &* 1_099_511_628_211 }
    for draw in batch.draws {
        mix(UInt64(draw.primitive.rawValue))
        mix(UInt64(draw.resourceID))
        mix(UInt64(draw.vertexStart))
        mix(draw.sequence)
    }
    return hash == 0 ? 1 : hash
}

private func require(_ value: @autoclosure () -> Bool, _ message: String) {
    guard value() else { preconditionFailure("file-mode-metal-capture: " + message) }
}

@available(macOS 27.0, *)
@main
@MainActor
struct GoldenEyeFileModeMetalReferenceCaptureV6Smoke {
    private struct CaptureState {
        let name: String
        let screen: UInt32
        let save: GoldenEyeSaveState
        let menu: GoldenEyeSource2DFileModeViewV6
        let source2D: GoldenEyeSource2DFrameV6
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4) else {
            print("goldeneye_file_mode_metal_reference_capture_v6_smoke: SKIP (Metal 4 device unavailable)")
            return
        }
        let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/native/source-frontend-v6", isDirectory: true)
        let sceneLibrary = URL(fileURLWithPath: CommandLine.arguments.dropFirst().dropFirst().first ?? "build/native/source-scene-renderer-v6/GoldenEyeSourceSceneV6.metallib")
        let twoDLibrary = URL(fileURLWithPath: CommandLine.arguments.dropFirst().dropFirst().dropFirst().first ?? "build/native/source-2d-metal-v6/GoldenEyeSource2DV6.metallib")
        let outputRoot = URL(fileURLWithPath: CommandLine.arguments.dropFirst().dropFirst().dropFirst().dropFirst().first ?? "build/native/file-mode-metal-reference-capture-v6", isDirectory: true)
        guard FileManager.default.fileExists(atPath: sceneLibrary.path), FileManager.default.fileExists(atPath: twoDLibrary.path) else {
            print("goldeneye_file_mode_metal_reference_capture_v6_smoke: SKIP (metallib unavailable)")
            return
        }
        try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)

        let preparation = try GoldenEyeSourceProductPreparationV6.load(rootURL: root)
        let model = try preparation.model(named: "walletbond")
        let backgroundRecord = try preparation.catalog.record(kind: .background, name: "gunbarrel-background", family: "gunbarrel")
        let background = try GoldenEyeFileModeBackgroundContractV6(encoded: preparation.catalog.copyOut(.decoded, for: backgroundRecord))
        require(background.rowCount == 299 && background.sourceColumn(forCanvasColumn: 0) == 28 && background.sourceColumn(forCanvasColumn: 412) == nil, "File/Mode source background rows/offset")
        let assets = try GoldenEyeSource2DAssetsV6(catalog: preparation.catalog)
        let lowerer = GoldenEyeSource2DLowererV6(assets: assets)
        let modelMatrixHandle = try Self.firstModelMatrixHandle(model)
        let fileMatrices = try GoldenEyeSourceFrontendMatricesV6.make(
            input: .init(screen: 5, nativeTick: 2, referenceTick: 1, sourceTimer: 0, pairPhase: 0),
            modelMatrixHandle: modelMatrixHandle,
            viewportWidth: 440,
            viewportHeight: 330,
            selectedFolder: 0
        )
        let fileFrame = try GoldenEyeGBISceneFrameContextV6(
            nativeTick: 2, referenceTick: 1, sourceTimer: 0, pairPhase: 0,
            screen: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_FILE_SELECT),
            viewportWidth: 440, viewportHeight: 330
        )
        let fileScene = try Self.buildWalletScene(
            model: model,
            modelName: "walletbond",
            catalog: preparation.catalog,
            matrices: fileMatrices.resources.matrices,
            viewports: fileMatrices.resources.viewports,
            frame: fileFrame
        )
        require(fileScene.summary.draw_count == 32, "four-wallet draw count")
        require(fileScene.summary.index_count == 112, "four-wallet triangle count")
        require(fileScene.summary.unsupported_visible_count == 0, "four-wallet unsupported work")
        for draw in fileScene.drawCommands.prefix(4) {
            let start = Int(draw.first_vertex)
            let end = start + Int(draw.vertex_count)
            let vertices = fileScene.vertices[start..<end]
            let uv = vertices.flatMap { withUnsafeBytes(of: $0.texcoord_q16) { Array($0.bindMemory(to: Int32.self).prefix(2)) } }
            let positions = vertices.flatMap { withUnsafeBytes(of: $0.position_q16) { Array($0.bindMemory(to: Int32.self).prefix(3)) } }
            let colors = vertices.map { String(format: "%08x", $0.color_rgba) }
            FileHandle.standardError.write(Data(("wallet-draw handle=" + String(draw.draw_handle) + " resource=" + String(draw.resource_handle) + " uv=" + String(describing: (uv.min() ?? 0, uv.max() ?? 0)) + " pos=" + String(describing: (positions.min() ?? 0, positions.max() ?? 0)) + "\n").utf8))
            FileHandle.standardError.write(Data(("wallet-draw-colors=" + colors.joined(separator: ",") + "\n").utf8))
            if let renderState = fileScene.renderStateByHandle[draw.render_state_handle] {
                let rawGeometry = fileScene.lightingFrameContext?.geometryModesByState[renderState.state_handle] ?? 0
                FileHandle.standardError.write(Data(("wallet-state handle=" + String(renderState.state_handle) + " cycles=" + String(renderState.combiner_cycle_count) + " combiner=" + String(renderState.cycle0_color_a) + "," + String(renderState.cycle0_color_b) + "," + String(renderState.cycle0_color_c) + "," + String(renderState.cycle0_color_d) + " alpha=" + String(renderState.cycle0_alpha_a) + "," + String(renderState.cycle0_alpha_b) + "," + String(renderState.cycle0_alpha_c) + "," + String(renderState.cycle0_alpha_d) + " cycle1=" + String(renderState.cycle1_color_a) + "," + String(renderState.cycle1_color_b) + "," + String(renderState.cycle1_color_c) + "," + String(renderState.cycle1_color_d) + " alpha1=" + String(renderState.cycle1_alpha_a) + "," + String(renderState.cycle1_alpha_b) + "," + String(renderState.cycle1_alpha_c) + "," + String(renderState.cycle1_alpha_d) + " rawL=" + String(renderState.raw_othermode_l, radix: 16) + " mode=" + String(renderState.raw_render_mode, radix: 16) + " cull=" + String(renderState.cull_mode) + " depth=" + String(renderState.depth_mode) + " alphaMode=" + String(renderState.alpha_mode) + " geometry=" + String(rawGeometry, radix: 16) + " primitive=" + String(renderState.primitive_rgba, radix: 16) + " env=" + String(renderState.environment_rgba, radix: 16) + " filter=" + String(renderState.filter_mode) + "\n").utf8))
            }
            if let transform = fileScene.transformByHandle[draw.transform_handle] {
                let matrix = withUnsafeBytes(of: transform.matrix_q16) { Array($0.bindMemory(to: Int32.self).prefix(16)) }
                var ndc: [(Double, Double, Double, Double)] = []
                for vertex in vertices {
                    let p = withUnsafeBytes(of: vertex.position_q16) { Array($0.bindMemory(to: Int32.self).prefix(3)) }
                    if let clip = try? GoldenEyeSourceProjectionBindingV6.apply(matrixQ16: matrix, pointQ16: (p[0], p[1], p[2])), clip.w != 0 {
                        let w = Double(clip.w) / 65_536.0
                        ndc.append((Double(clip.x) / Double(clip.w), Double(clip.y) / Double(clip.w), Double(clip.z) / Double(clip.w), w))
                    }
                }
                FileHandle.standardError.write(Data(("wallet-draw-ndc=" + String(describing: ndc.prefix(3)) + "\n").utf8))
            }
        }

        var completedFolders = (0..<4).map { GoldenEyeSaveFolder.created(folder: $0) }
        for index in completedFolders.indices { completedFolders[index].setStageTimeByte(index, value: 1) }
        let fresh = GoldenEyeSaveState.blank
        let partial = GoldenEyeSaveState(folders: [completedFolders[0], .blank(folder: 1), .blank(folder: 2), .blank(folder: 3)])
        let full = GoldenEyeSaveState(folders: completedFolders, selectedFolder: 2)
        let fileAuthority = try GoldenEyeFileModeAuthorityV6(saveState: fresh)
        let freshView = try GoldenEyeSource2DFileModeViewV6(frame: fileAuthority.lastFrame, saveState: fresh)
        let partialView = try GoldenEyeSource2DFileModeViewV6(frame: fileAuthority.lastFrame, saveState: partial)
        let fullView = try GoldenEyeSource2DFileModeViewV6(frame: fileAuthority.lastFrame, saveState: full)
        let states: [CaptureState] = [
            .init(name: "file-fresh", screen: 5, save: fresh, menu: freshView, source2D: try lowerer.makeFileSelectFrame(nativeTick: 2, sourceTimer: 0, menu: freshView)),
            .init(name: "file-partial", screen: 5, save: partial, menu: partialView, source2D: try lowerer.makeFileSelectFrame(nativeTick: 2, sourceTimer: 1, menu: partialView)),
            .init(name: "file-full", screen: 5, save: full, menu: fullView, source2D: try lowerer.makeFileSelectFrame(nativeTick: 2, sourceTimer: 2, menu: fullView)),
            .init(name: "file-copy-active", screen: 5, save: full, menu: try Self.copyView(save: full), source2D: try lowerer.makeFileSelectFrame(nativeTick: 2, sourceTimer: 2, menu: Self.copyView(save: full))),
            .init(name: "file-erase-dialog", screen: 5, save: full, menu: try Self.eraseDialogView(save: full), source2D: try lowerer.makeFileSelectFrame(nativeTick: 2, sourceTimer: 2, menu: Self.eraseDialogView(save: full))),
        ]

        let modeSolo = try Self.modeView(save: full, multiplayer: false)
        let modeMulti = try Self.modeView(save: full, multiplayer: true)
        let modeStates: [CaptureState] = [
            .init(name: "mode-solo-previous", screen: 6, save: full, menu: modeSolo, source2D: try lowerer.makeModeSelectFrame(nativeTick: 2, sourceTimer: 0, menu: modeSolo)),
            .init(name: "mode-multiplayer-previous", screen: 6, save: full, menu: modeMulti, source2D: try lowerer.makeModeSelectFrame(nativeTick: 2, sourceTimer: 0, menu: modeMulti)),
        ]

        let layer = CAMetalLayer()
        let state = try GoldenEyeMetalDeviceState(device: device, layer: layer)
        let uploadEvent = device.makeSharedEvent()!
        let store = try GoldenEyeSourceTextureStoreV6(context: .init(device: device, queue: state.queue, residency: state.sceneResidency, completionEvent: uploadEvent))
        // Every guarded model remains part of the plan so strict adapter
        // metadata is complete.
        let modelPairs = preparation.models.keys.sorted().compactMap { key -> (name: String, model: GoldenEyeSourceModelV6)? in
            guard let value = preparation.models[key] else { return nil }
            return (key, value)
        }
        let plan = try GoldenEyeSourceTextureUploadPlanV6.make(catalog: preparation.catalog, models: modelPairs)
        let expectedWalletPayloads: Set<String> = [
            "FOLDERTEX.payload", "PAPERTEX.payload", "MI6.payload",
            "MI6_UL.payload", "MI6_UR.payload", "MI6_LL.payload", "MI6_LR.payload",
            "BROSNAN_UL.payload", "BROSNAN_UR.payload", "BROSNAN_LL.payload", "BROSNAN_LR.payload"
        ]
        let walletPayloadNames = Set(model.textures.compactMap { preparation.catalog.record(id: $0.payloadRecordID)?.name })
        require(expectedWalletPayloads.isSubset(of: walletPayloadNames), "Wallet cover/photo/MI6 source payload linkage")
        let walletDescriptors = Dictionary(uniqueKeysWithValues: plan.descriptors.filter { $0.modelName == "walletbond" }.map { ($0.resourceHandle, $0) })
        let walletPayloadNameByHandle = Dictionary(uniqueKeysWithValues: plan.descriptors
            .filter { $0.modelName == "walletbond" }
            .compactMap { descriptor -> (UInt32, String)? in
                guard let name = preparation.catalog.record(id: descriptor.payloadRecordID)?.name else { return nil }
                return (descriptor.resourceHandle, name)
            })
        let fileMaterialHandles = Set(fileScene.drawCommands.map(\.resource_handle).filter { $0 != 0 })
        require(!fileMaterialHandles.isEmpty, "File Select has no sampled wallet materials")
        require(fileMaterialHandles.allSatisfy { handle in
            guard let descriptor = walletDescriptors[handle], let level = descriptor.levels.first else { return false }
            return hasNonBlackRGB(level.decoded)
        }, "File Select sampled wallet material payload is black")
        let expectedFileMaterialPayloads: Set<String> = [
            "FOLDERTEX.payload", "PAPERTEX.payload",
            "MI6_UL.payload", "MI6_UR.payload", "MI6_LL.payload", "MI6_LR.payload"
        ]
        let fileMaterialPayloads = Set(fileMaterialHandles.compactMap { walletPayloadNameByHandle[$0] })
        FileHandle.standardError.write(Data(("file-material-payloads-pre=\(fileMaterialPayloads.sorted().joined(separator: ","))\n").utf8))
        require(expectedFileMaterialPayloads.isSubset(of: fileMaterialPayloads), "File Select cover/photo/MI6 quadrant draw linkage")
        print("file-material-payloads=\(fileMaterialPayloads.sorted().joined(separator: ","))")
        if let walletTexture = plan.descriptors.first(where: { $0.modelName == "walletbond" }) {
            let level = walletTexture.levels[0]
            let png = try GoldenEyeReferenceCaptureCodecV6.encodePNG(
                bgra8: level.decoded,
                width: Int(level.width),
                height: Int(level.height),
                bytesPerRow: Int(level.width) * 4
            )
            try png.write(to: outputRoot.appendingPathComponent("wallet-texture-level0.png"), options: .atomic)
        }
        _ = try store.upload(plan: plan)
        try store.drain()
        for descriptor in plan.descriptors where descriptor.modelName == "walletbond" {
            let level = descriptor.levels[0]
            let center = (Int(level.height / 2) * Int(level.width) + Int(level.width / 2)) * 4
            let centerBytes = center + 4 <= level.decoded.count
                ? Array(level.decoded[center..<(center + 4)])
                : []
            FileHandle.standardError.write(Data(("wallet-texture handle=" + String(descriptor.resourceHandle) + " size=" + String(level.width) + "x" + String(level.height) + " levels=" + String(descriptor.mipLevels) + " center=" + String(describing: centerBytes) + " bytes=" + String(level.decoded.count) + "\n").utf8))
            if fileScene.drawCommands.contains(where: { $0.resource_handle == descriptor.resourceHandle }) {
                let png = try GoldenEyeReferenceCaptureCodecV6.encodePNG(
                    bgra8: level.decoded,
                    width: Int(level.width),
                    height: Int(level.height),
                    bytesPerRow: Int(level.width) * 4
                )
                try png.write(to: outputRoot.appendingPathComponent("wallet-texture-\(descriptor.resourceHandle).png"), options: .atomic)
            }
        }
        let adapter = try GoldenEyeSourceSceneTextureBindingAdapterV6(store: store, plan: plan)
        let pipeline = try GoldenEyeSourceScenePipelineV6(device: device, libraryURL: sceneLibrary, pixelFormat: .bgra8Unorm)
        let renderer320 = try GoldenEyeSourceSceneRendererV6(state: state, pipeline: pipeline, textureResolver: { store.texture(handle: $0) }, textureBindingAdapter: adapter, outputMode: .reference320x240, frontFacing: .counterClockwise)
        let source2D320 = try GoldenEyeSource2DMetalRendererV6(state: state, assets: assets, libraryURL: twoDLibrary, outputMode: .reference320x240)
        let backgroundFrame = lowerer.makeFileModeBackgroundFrame(nativeTick: 2, sourceTimer: 0)
        print("background-resource-pre id=\(assets.fileModeBackground.sourceRecordID) bytes=\(assets.fileModeBackground.pixels.count) visible=\(hasNonBlackRGB(Data(assets.fileModeBackground.pixels))) frameRows=\(backgroundFrame.textureRects.count)")
        require(hasNonBlackRGB(Data(assets.fileModeBackground.pixels)), "File/Mode background resource is black")
        let backgroundBatch = try source2D320.batch(frame: backgroundFrame, outputWidth: 320, outputHeight: 240)
        print("background-batch-pre draws=\(backgroundBatch.draws.count) resourceMatch=\(backgroundBatch.draws.allSatisfy { $0.resourceID == assets.fileModeBackground.sourceRecordID })")
        require(backgroundBatch.draws.count == 299 && backgroundBatch.draws.allSatisfy { $0.resourceID == assets.fileModeBackground.sourceRecordID }, "File/Mode background row draw packet")
        print("background-resource=\(assets.fileModeBackground.sourceRecordID) rows=\(backgroundBatch.draws.count) geometryHash=\(backgroundBatch.geometryHash)")
        let backgroundOnly = try Self.capture2DOnly(frame: backgroundFrame, renderer: source2D320, state: state, device: device, outputRoot: outputRoot)
        require(hasNonBlackRGB(backgroundOnly), "File/Mode background standalone target is black")
        let backgroundTop = bgraPixel(backgroundOnly, x: 0, y: 12)
        let backgroundMiddle = bgraPixel(backgroundOnly, x: 0, y: 120)
        let backgroundBottom = bgraPixel(backgroundOnly, x: 0, y: 228)
        require(backgroundTop.0 > 0 && backgroundMiddle.0 > backgroundTop.0 && backgroundBottom.0 > backgroundMiddle.0,
                "File/Mode background row gradient readback")
        require((300..<320).allSatisfy { x in
            (12...228).allSatisfy { y in bgraPixel(backgroundOnly, x: x, y: y).0 == 0 }
        }, "File/Mode background right border readback")
        print("background-readback top=\(backgroundTop.0) middle=\(backgroundMiddle.0) bottom=\(backgroundBottom.0) border=black")

        let baselineBackgroundBatch = backgroundBatch
        var baseline2DBatches: [String: GoldenEyeSource2DMetalBatchV6] = [:]
        var baselineSceneEvidence: [String: GoldenEyeSourceSceneRenderEvidenceV6] = [:]
        var baselineSnapshots: [String: GoldenEyeSourceSceneSnapshotV6] = [:]
        var captureStatesByName: [String: CaptureState] = [:]
        for item in states + modeStates { captureStatesByName[item.name] = item }

        for item in states + modeStates {
            let snapshot: GoldenEyeSourceSceneSnapshotV6
            if item.screen == 5 {
                snapshot = fileScene
            } else {
                let matrices = try GoldenEyeSourceFrontendMatricesV6.make(input: .init(screen: 6, nativeTick: 2, referenceTick: 1, sourceTimer: 0, pairPhase: 0), modelMatrixHandle: modelMatrixHandle, viewportWidth: 440, viewportHeight: 330, selectedFolder: item.menu.frame.state.selectedFolder)
                let frame = try GoldenEyeGBISceneFrameContextV6(nativeTick: 2, referenceTick: 1, sourceTimer: 0, pairPhase: 0, screen: 6, viewportWidth: 440, viewportHeight: 330)
                snapshot = try Self.buildSingleWalletScene(model: model, catalog: preparation.catalog, matrices: matrices.resources, frame: frame)
            }
            if item.screen == 6 {
                let materialHandles = Set(snapshot.drawCommands.map(\.resource_handle).filter { $0 != 0 })
                require(!materialHandles.isEmpty, "Mode Select has no selected wallet material")
                require(materialHandles.allSatisfy { handle in
                    guard let descriptor = walletDescriptors[handle], let level = descriptor.levels.first else { return false }
                    return hasNonBlackRGB(level.decoded)
                }, "Mode Select selected wallet material payload is black")
                if item.name == "mode-solo-previous" {
                    let expectedModeMaterialPayloads: Set<String> = [
                        "FOLDERTEX.payload", "PAPERTEX.payload", "MI6.payload",
                        "EYESONLY_L.payload", "EYESONLY_R.payload",
                        "FORYOUR_L.payload", "FORYOUR_R.payload",
                        "OHMSS_L.payload", "OHMSS_R.payload", "GBGRADIENT.payload"
                    ]
                    let modeMaterialPayloads = Set(materialHandles.compactMap { walletPayloadNameByHandle[$0] })
                    FileHandle.standardError.write(Data(("mode-material-payloads-pre=\(modeMaterialPayloads.sorted().joined(separator: ","))\n").utf8))
                    require(expectedModeMaterialPayloads.isSubset(of: modeMaterialPayloads), "Mode Select selected wallet material linkage")
                    print("mode-material-payloads=\(modeMaterialPayloads.sorted().joined(separator: ","))")
                }
            }
            var batch: GoldenEyeSource2DMetalBatchV6?
            let output = outputRoot.appendingPathComponent(item.name + "-320x240.raw")
            if item.name == "file-fresh" {
                let threeD = try renderer320.captureReference320x240(snapshot: snapshot, to: outputRoot.appendingPathComponent("file-fresh-3d.raw"))
                require(hasNonBlackRGB(threeD.bytes), "File Select 3D wallet target is all black")
                print("capture=file-fresh-3d nonblack=\(hasNonBlackRGB(threeD.bytes)) sha=\(threeD.rawSHA256)")
            }
            if item.name == "mode-solo-previous" {
                for draw in snapshot.drawCommands.prefix(4) {
                    let start = Int(draw.first_vertex)
                    let end = start + Int(draw.vertex_count)
                    let vertices = snapshot.vertices[start..<end]
                    let positions = vertices.flatMap { withUnsafeBytes(of: $0.position_q16) { Array($0.bindMemory(to: Int32.self).prefix(3)) } }
                    let state = snapshot.renderStateByHandle[draw.render_state_handle]
                    FileHandle.standardError.write(Data(("mode-draw handle=" + String(draw.draw_handle) + " resource=" + String(draw.resource_handle) + " pos=" + String(describing: (positions.min() ?? 0, positions.max() ?? 0)) + " cull=" + String(state?.cull_mode ?? 999) + "\n").utf8))
                    if let transform = snapshot.transformByHandle[draw.transform_handle] {
                        let matrix = withUnsafeBytes(of: transform.matrix_q16) { Array($0.bindMemory(to: Int32.self).prefix(16)) }
                        var ndc: [(Double, Double, Double, Double)] = []
                        for vertex in vertices.prefix(3) {
                            let p = withUnsafeBytes(of: vertex.position_q16) { Array($0.bindMemory(to: Int32.self).prefix(3)) }
                            if let clip = try? GoldenEyeSourceProjectionBindingV6.apply(matrixQ16: matrix, pointQ16: (p[0], p[1], p[2])), clip.w != 0 {
                                ndc.append((Double(clip.x) / Double(clip.w), Double(clip.y) / Double(clip.w), Double(clip.z) / Double(clip.w), Double(clip.w) / 65_536.0))
                            }
                        }
                        FileHandle.standardError.write(Data(("mode-draw-ndc=" + String(describing: ndc) + "\n").utf8))
                    }
                }
                let threeD = try renderer320.captureReference320x240(snapshot: snapshot, to: outputRoot.appendingPathComponent("mode-solo-previous-3d.raw"))
                require(hasNonBlackRGB(threeD.bytes), "Mode Select selected wallet target is all black")
                print("capture=mode-solo-previous-3d nonblack=\(hasNonBlackRGB(threeD.bytes)) sha=\(threeD.rawSHA256)")
            }
            let capture = try renderer320.captureReference320x240(
                snapshot: snapshot,
                to: output,
                underlay: { encoder, slot in
                    _ = try source2D320.encode(
                        frame: backgroundFrame,
                        into: encoder,
                        drawableWidth: 320,
                        drawableHeight: 240,
                        slotIndex: slot,
                        includeFills: true,
                        skipInitialSourceClear: false
                    )
                },
                overlay: { encoder, slot in
                    batch = try source2D320.encodeOverlay(frame: item.source2D, into: encoder, drawableWidth: 320, drawableHeight: 240, slotIndex: slot)
                }
            )
            require(hasNonBlackRGB(capture.bytes), item.name + " is all black")
            require(capture.evidence.drawCount > 0, item.name + " has no 3D draws")
            require(batch?.draws.isEmpty == false, item.name + " has no 2D draws")
            if let batch {
                baseline2DBatches[item.name] = batch
                baselineSceneEvidence[item.name] = capture.evidence
                baselineSnapshots[item.name] = snapshot
            }
            print("capture=\(item.name) 320x240 draws=\(capture.evidence.drawCount) triangles=\(capture.evidence.triangleCount) sha=\(capture.rawSHA256) png=\(capture.pngURL?.path ?? "")")
        }

        renderer320.shutdown()
        source2D320.shutdown()
        let outputSpecs: [(mode: GoldenEyeFidelityOutputMode, width: Int, height: Int, name: String)] = [
            (.faithfulHD, 1280, 960, "faithful-hd"),
            (.adaptiveWidescreen, 1920, 1080, "adaptive-widescreen")
        ]
        for spec in outputSpecs {
            FileHandle.standardError.write(Data(("offscreen-output-start mode=\(spec.name) size=\(spec.width)x\(spec.height)\n").utf8))
            let sceneRenderer = try GoldenEyeSourceSceneRendererV6(
                state: state,
                pipeline: pipeline,
                textureResolver: { store.texture(handle: $0) },
                textureBindingAdapter: adapter,
                outputMode: spec.mode,
                frontFacing: .counterClockwise
            )
            FileHandle.standardError.write(Data(("offscreen-scene-renderer-init-pass mode=\(spec.name)\n").utf8))
            let source2DRenderer = try GoldenEyeSource2DMetalRendererV6(
                state: state,
                assets: assets,
                libraryURL: twoDLibrary,
                outputMode: spec.mode
            )
            FileHandle.standardError.write(Data(("offscreen-2d-renderer-init-pass mode=\(spec.name)\n").utf8))
            let layout = GoldenEyeFidelityLayout(
                mode: spec.mode,
                drawableWidth: Double(spec.width),
                drawableHeight: Double(spec.height)
            )
            try Self.validateOutputLayout(
                mode: spec.mode,
                width: spec.width,
                height: spec.height,
                layout: layout,
                modeFrame: captureStatesByName["mode-solo-previous"]?.source2D
            )
            FileHandle.standardError.write(Data(("offscreen-layout-pass mode=\(spec.name)\n").utf8))
            let outputBackgroundBatch = try source2DRenderer.batch(
                frame: backgroundFrame,
                outputWidth: spec.width,
                outputHeight: spec.height
            )
            require(outputBackgroundBatch.draws.count == baselineBackgroundBatch.draws.count,
                    spec.name + " background draw count changed")
            require(outputBackgroundBatch.resourceHash == baselineBackgroundBatch.resourceHash,
                    spec.name + " background resource manifest changed")
            require(source2DManifestHash(outputBackgroundBatch) == source2DManifestHash(baselineBackgroundBatch),
                    spec.name + " background source draw manifest changed")
            FileHandle.standardError.write(Data(("offscreen-background-batch-pass mode=\(spec.name)\n").utf8))
            let backgroundBytes = try Self.capture2DOnly(
                frame: backgroundFrame,
                renderer: source2DRenderer,
                state: state,
                device: device,
                outputRoot: outputRoot,
                width: spec.width,
                height: spec.height,
                outputName: spec.name + "-background-only"
            )
            require(hasNonBlackRGB(backgroundBytes), spec.name + " background is all black")
            FileHandle.standardError.write(Data(("offscreen-background-readback-pass mode=\(spec.name)\n").utf8))
            if spec.mode == .adaptiveWidescreen {
                require(bgraPixel(backgroundBytes, x: 0, y: spec.height / 2, width: spec.width).0 == 0,
                        "adaptive left gutter is not black")
                require(bgraPixel(backgroundBytes, x: spec.width - 1, y: spec.height / 2, width: spec.width).0 == 0,
                        "adaptive right gutter is not black")
            }
            for name in ["file-fresh", "file-partial", "mode-solo-previous"] {
                FileHandle.standardError.write(Data(("offscreen-scene-start mode=\(spec.name) name=\(name)\n").utf8))
                guard let item = captureStatesByName[name],
                      let snapshot = baselineSnapshots[name],
                      let baseline2DBatch = baseline2DBatches[name],
                      let baselineEvidence = baselineSceneEvidence[name] else {
                    throw GoldenEyeSourceSceneRendererV6Error.invalidState("missing baseline \(name)")
                }
                let output2DBatch = try source2DRenderer.batch(
                    frame: item.source2D,
                    outputWidth: spec.width,
                    outputHeight: spec.height
                )
                require(output2DBatch.sourceFrameHash == baseline2DBatch.sourceFrameHash,
                        spec.name + " " + name + " source 2D frame changed")
                require(output2DBatch.resourceHash == baseline2DBatch.resourceHash,
                        spec.name + " " + name + " source 2D resource manifest changed")
                require(source2DManifestHash(output2DBatch) == source2DManifestHash(baseline2DBatch),
                        spec.name + " " + name + " source 2D draw manifest changed")
                let capture = try sceneRenderer.renderOffscreen(
                    snapshot: snapshot,
                    width: spec.width,
                    height: spec.height,
                    underlay: { encoder, slot in
                        _ = try source2DRenderer.encode(
                            frame: backgroundFrame,
                            into: encoder,
                            drawableWidth: spec.width,
                            drawableHeight: spec.height,
                            slotIndex: slot,
                            includeFills: true,
                            skipInitialSourceClear: false
                        )
                    },
                    overlay: { encoder, slot in
                        _ = try source2DRenderer.encodeOverlay(
                            frame: item.source2D,
                            into: encoder,
                            drawableWidth: spec.width,
                            drawableHeight: spec.height,
                            slotIndex: slot
                        )
                    }
                )
                require(hasNonBlackRGB(capture.bytes), spec.name + " " + name + " is all black")
                require(capture.evidence.drawCount == baselineEvidence.drawCount,
                        spec.name + " " + name + " scene draw count changed")
                require(capture.evidence.triangleCount == baselineEvidence.triangleCount,
                        spec.name + " " + name + " scene triangle count changed")
                require(capture.evidence.copiedRecordAggregateHash == baselineEvidence.copiedRecordAggregateHash,
                        spec.name + " " + name + " scene resource manifest changed")
                require(capture.evidence.pipelineKeyHashes == baselineEvidence.pipelineKeyHashes,
                        spec.name + " " + name + " scene pipeline manifest changed")
                try Self.writeOffscreenArtifacts(
                    capture: capture,
                    name: name,
                    mode: spec.mode,
                    outputRoot: outputRoot,
                    layout: layout,
                    source2DBatch: output2DBatch,
                    baseline2DBatch: baseline2DBatch,
                    backgroundBatch: outputBackgroundBatch,
                    baselineBackgroundBatch: baselineBackgroundBatch,
                    baselineEvidence: baselineEvidence
                )
                let outputPNG = outputRoot.appendingPathComponent(name + "-" + spec.name + ".png")
                print("capture=\(name) mode=\(spec.name) \(spec.width)x\(spec.height) sha=\(capture.rawSHA256) png=\(outputPNG.path)")
            }
            source2DRenderer.shutdown()
            sceneRenderer.shutdown()
        }

        try store.shutdown()
        state.stopCapture()
        print("goldeneye_file_mode_metal_reference_capture_v6_smoke: PASS")
    }

    private static func validateOutputLayout(
        mode: GoldenEyeFidelityOutputMode,
        width: Int,
        height: Int,
        layout: GoldenEyeFidelityLayout,
        modeFrame: GoldenEyeSource2DFrameV6?
    ) throws {
        let epsilon = 0.000_001
        func near(_ lhs: Double, _ rhs: Double) -> Bool { abs(lhs - rhs) <= epsilon }
        FileHandle.standardError.write(Data(("layout-evidence mode=\(mode) scale=\(layout.scale) origin=\(layout.originX),\(layout.originY) core=\(layout.sourceRectInOutput.minX),\(layout.sourceRectInOutput.minY),\(layout.sourceRectInOutput.maxX),\(layout.sourceRectInOutput.maxY)\n").utf8))
        require(near(layout.sourceRectInOutput.width, GoldenEyeFidelityLayout.sourceWidth * layout.scale),
                "\(mode) source width is stretched")
        require(near(layout.sourceRectInOutput.height, GoldenEyeFidelityLayout.sourceHeight * layout.scale),
                "\(mode) source height is stretched")
        let origin = layout.sourceToOutput(.init(x: 0, y: 0))
        let far = layout.sourceToOutput(.init(x: GoldenEyeFidelityLayout.sourceWidth, y: GoldenEyeFidelityLayout.sourceHeight))
        require(near(far.x - origin.x, GoldenEyeFidelityLayout.sourceWidth * layout.scale),
                "\(mode) source art horizontal scale changed")
        require(near(far.y - origin.y, GoldenEyeFidelityLayout.sourceHeight * layout.scale),
                "\(mode) source art vertical scale changed")
        switch mode {
        case .faithfulHD:
            require(width == 1280 && height == 960, "Faithful HD target dimensions")
            require(near(layout.scale, 1280.0 / 440.0) && near(layout.originX, 0) && near(layout.originY, 0),
                    "Faithful HD 4:3 core mapping")
            require(near(layout.sideGutter, 0), "Faithful HD side gutter")
        case .adaptiveWidescreen:
            require(width == 1920 && height == 1080, "Adaptive target dimensions")
            let expectedScale = 1080.0 / 330.0
            let expectedGutterPixels = (1920.0 - 440.0 * expectedScale) * 0.5
            require(near(layout.scale, expectedScale) && near(layout.originY, 0),
                    "Adaptive 4:3 core scale")
            require(near(layout.sideGutter * layout.scale, expectedGutterPixels),
                    "Adaptive declared side gutter")
            require(near(layout.sourceRectInOutput.minX, expectedGutterPixels)
                    && near(layout.sourceRectInOutput.maxX, Double(width) - expectedGutterPixels),
                    "Adaptive source core bounds")
        case .reference320x240:
            throw GoldenEyeSourceSceneRendererV6Error.invalidState("output layout helper received reference mode")
        }
        guard let modeFrame else {
            throw GoldenEyeSourceSceneRendererV6Error.invalidState("Mode Select frame missing for layout evidence")
        }
        let verticalTabGlyphs = modeFrame.glyphs.filter { $0.flags & 2 != 0 }
        FileHandle.standardError.write(Data(("layout-tab-glyphs=\(verticalTabGlyphs.map { String($0.x) }.joined(separator: ","))\n").utf8))
        require(!verticalTabGlyphs.isEmpty && verticalTabGlyphs.allSatisfy { $0.x == 398 },
                "Mode Select right-edge tab source anchor")
        let tabOutput = layout.sourceToOutput(.init(x: 398, y: 236))
        require(tabOutput.x >= layout.sourceRectInOutput.minX - epsilon
                && tabOutput.x < layout.sourceRectInOutput.maxX + epsilon,
                "Mode Select right-edge tab leaves the source core")
        for point in [
            GoldenEyeFidelityLayout.Point(x: 0, y: 0),
            GoldenEyeFidelityLayout.Point(x: 110, y: 285),
            GoldenEyeFidelityLayout.Point(x: 398, y: 236),
            GoldenEyeFidelityLayout.Point(x: 439, y: 329)
        ] {
            let roundTrip = layout.outputToSource(layout.sourceToOutput(point))
            require(near(roundTrip.x, point.x) && near(roundTrip.y, point.y),
                    "\(mode) inverse hit mapping")
        }
    }

    private static func writeOffscreenArtifacts(
        capture: GoldenEyeSourceSceneReferenceCaptureV6,
        name: String,
        mode: GoldenEyeFidelityOutputMode,
        outputRoot: URL,
        layout: GoldenEyeFidelityLayout,
        source2DBatch: GoldenEyeSource2DMetalBatchV6,
        baseline2DBatch: GoldenEyeSource2DMetalBatchV6,
        backgroundBatch: GoldenEyeSource2DMetalBatchV6,
        baselineBackgroundBatch: GoldenEyeSource2DMetalBatchV6,
        baselineEvidence: GoldenEyeSourceSceneRenderEvidenceV6
    ) throws {
        let modeName: String
        switch mode {
        case .faithfulHD: modeName = "faithful-hd"
        case .reference320x240: modeName = "reference-320x240"
        case .adaptiveWidescreen: modeName = "adaptive-widescreen"
        }
        let stem = "\(name)-\(modeName)"
        let rawURL = outputRoot.appendingPathComponent(stem + ".raw")
        let pngURL = outputRoot.appendingPathComponent(stem + ".png")
        let jsonURL = outputRoot.appendingPathComponent(stem + ".json")
        try capture.bytes.write(to: rawURL, options: .atomic)
        let png = try GoldenEyeReferenceCaptureCodecV6.encodePNG(
            bgra8: capture.bytes,
            width: capture.width,
            height: capture.height,
            bytesPerRow: capture.bytesPerRow
        )
        try png.write(to: pngURL, options: .atomic)

        let metadata: [String: Any] = [
            "name": name,
            "mode": modeName,
            "frontFacing": "counterClockwise",
            "width": capture.width,
            "height": capture.height,
            "bytesPerRow": capture.bytesPerRow,
            "pixelFormat": capture.pixelFormat,
            "rawSHA256": capture.rawSHA256,
            "rawPath": rawURL.path,
            "pngPath": pngURL.path,
            "sourceScene": [
                "drawCount": capture.evidence.drawCount,
                "triangleCount": capture.evidence.triangleCount,
                "copiedRecordAggregateHash": String(capture.evidence.copiedRecordAggregateHash),
                "pipelineKeyHashes": capture.evidence.pipelineKeyHashes.map(String.init),
                "baselineDrawCount": baselineEvidence.drawCount,
                "baselineTriangleCount": baselineEvidence.triangleCount,
                "baselineCopiedRecordAggregateHash": String(baselineEvidence.copiedRecordAggregateHash),
                "baselinePipelineKeyHashes": baselineEvidence.pipelineKeyHashes.map(String.init)
            ],
            "source2D": [
                "drawCount": source2DBatch.draws.count,
                "sourceFrameHash": String(source2DBatch.sourceFrameHash),
                "resourceHash": String(source2DBatch.resourceHash),
                "manifestHash": String(source2DManifestHash(source2DBatch)),
                "geometryHash": String(source2DBatch.geometryHash),
                "baselineDrawCount": baseline2DBatch.draws.count,
                "baselineSourceFrameHash": String(baseline2DBatch.sourceFrameHash),
                "baselineResourceHash": String(baseline2DBatch.resourceHash),
                "baselineManifestHash": String(source2DManifestHash(baseline2DBatch)),
                "baselineGeometryHash": String(baseline2DBatch.geometryHash)
            ],
            "background": [
                "drawCount": backgroundBatch.draws.count,
                "resourceHash": String(backgroundBatch.resourceHash),
                "manifestHash": String(source2DManifestHash(backgroundBatch)),
                "geometryHash": String(backgroundBatch.geometryHash),
                "baselineDrawCount": baselineBackgroundBatch.draws.count,
                "baselineResourceHash": String(baselineBackgroundBatch.resourceHash),
                "baselineManifestHash": String(source2DManifestHash(baselineBackgroundBatch)),
                "baselineGeometryHash": String(baselineBackgroundBatch.geometryHash)
            ],
            "layout": [
                "scale": layout.scale,
                "originX": layout.originX,
                "originY": layout.originY,
                "sideGutter": layout.sideGutter,
                "sourceRectMinX": layout.sourceRectInOutput.minX,
                "sourceRectMinY": layout.sourceRectInOutput.minY,
                "sourceRectMaxX": layout.sourceRectInOutput.maxX,
                "sourceRectMaxY": layout.sourceRectInOutput.maxY
            ]
        ]
        let json = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys, .prettyPrinted])
        try json.write(to: jsonURL, options: .atomic)
    }

    private static func capture2DOnly(
        frame: GoldenEyeSource2DFrameV6,
        renderer: GoldenEyeSource2DMetalRendererV6,
        state: GoldenEyeMetalDeviceState,
        device: any MTLDevice,
        outputRoot: URL,
        width: Int = 320,
        height: Int = 240,
        outputName: String = "file-mode-background-only"
    ) throws -> Data {
        // Use the same compositor-independent target contract as the source
        // scene reference renderer. Reading a CAMetalLayer drawable after a
        // present is not reliable: the layer may recycle the surface before
        // the diagnostic copy command runs, which can turn a valid background
        // into an all-black false failure.
        let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        targetDescriptor.storageMode = .private
        targetDescriptor.usage = [.renderTarget, .shaderRead]
        guard let target = device.makeTexture(descriptor: targetDescriptor),
              let readback = device.makeBuffer(length: width * height * 4, options: .storageModeShared),
              let event = device.makeSharedEvent() else {
            throw GoldenEyeSourceSceneRendererV6Error.referenceTargetUnavailable
        }
        target.label = "GoldenEye.V6.FileMode.Background.\(width)x\(height).Color"
        readback.label = "GoldenEye.V6.FileMode.Background.\(width)x\(height).Readback"
        state.sceneResidency.addAllocation(target)
        state.sceneResidency.addAllocation(readback)
        state.sceneResidency.commit()

        let allocatorDescriptor = MTL4CommandAllocatorDescriptor()
        allocatorDescriptor.label = "GoldenEye.FileMode.Background.\(width)x\(height).Allocator"
        guard let allocator = try? device.makeCommandAllocator(descriptor: allocatorDescriptor),
              let commandBuffer = device.makeCommandBuffer() else {
            state.sceneResidency.removeAllocation(target)
            state.sceneResidency.removeAllocation(readback)
            state.sceneResidency.commit()
            throw GoldenEyeSourceSceneRendererV6Error.referenceReadbackUnavailable
        }
        commandBuffer.label = "GoldenEye.FileMode.Background.\(width)x\(height).CommandBuffer"
        commandBuffer.beginCommandBuffer(allocator: allocator)
        commandBuffer.useResidencySet(state.sceneResidency)
        let pass = MTL4RenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            commandBuffer.endCommandBuffer()
            state.sceneResidency.removeAllocation(target)
            state.sceneResidency.removeAllocation(readback)
            state.sceneResidency.commit()
            throw GoldenEyeSourceSceneRendererV6Error.encoderUnavailable
        }
        _ = try renderer.encode(
            frame: frame,
            into: renderEncoder,
            drawableWidth: width,
            drawableHeight: height,
            slotIndex: 0,
            includeFills: true
        )
        renderEncoder.endEncoding()
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            commandBuffer.endCommandBuffer()
            state.sceneResidency.removeAllocation(target)
            state.sceneResidency.removeAllocation(readback)
            state.sceneResidency.commit()
            throw GoldenEyeSourceSceneRendererV6Error.referenceReadbackUnavailable
        }
        encoder.label = "GoldenEye.FileMode.Background.\(width)x\(height).Readback"
        encoder.barrier(afterQueueStages: [.vertex, .fragment], beforeStages: [.blit], visibilityOptions: .device)
        encoder.copy(sourceTexture: target, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: width, height: height, depth: 1), destinationBuffer: readback, destinationOffset: 0, destinationBytesPerRow: width * 4, destinationBytesPerImage: 0)
        encoder.endEncoding()
        commandBuffer.endCommandBuffer()
        state.queue.commit([commandBuffer])
        state.queue.signalEvent(event, value: 1)
        guard event.wait(untilSignaledValue: 1, timeoutMS: 2_000) else {
            throw GoldenEyeSourceSceneRendererV6Error.slotTimeout(0)
        }
        let bytes = Data(bytes: readback.contents(), count: width * height * 4)
        let png = try GoldenEyeReferenceCaptureCodecV6.encodePNG(bgra8: bytes, width: width, height: height, bytesPerRow: width * 4)
        try png.write(to: outputRoot.appendingPathComponent(outputName + ".png"), options: .atomic)
        state.sceneResidency.removeAllocation(target)
        state.sceneResidency.removeAllocation(readback)
        state.sceneResidency.commit()
        return bytes
    }

    private static func firstModelMatrixHandle(_ model: GoldenEyeSourceModelV6) throws -> UInt32 {
        for (index, command) in model.commands.enumerated() where command.semantic.hasPrefix("gsSPMatrix") {
            guard let token = model.tokens(for: index).first, token.encodedValue != 0 else { continue }
            return token.encodedValue
        }
        throw GoldenEyeSourceModelV6.Error.invalid("wallet model matrix handle")
    }

    private static func matrixRoles(_ matrices: [GoldenEyeGBIMatrixResourceV6]) throws -> [GoldenEyeSourceMatrixRoleSidecarV6] {
        try matrices.compactMap { matrix in
            guard matrix.roleFlags != 0 else { return nil }
            return try GoldenEyeSourceMatrixRoleSidecarV6(handle: matrix.handle, roleFlags: matrix.roleFlags)
        }
    }

    private static func buildSingleWalletScene(
        model: GoldenEyeSourceModelV6,
        catalog: GoldenEyeSourceFrontendCatalog,
        matrices: GoldenEyeSourceProductFrameResourcesV6,
        frame: GoldenEyeGBISceneFrameContextV6
    ) throws -> GoldenEyeSourceSceneSnapshotV6 {
        try GoldenEyeWalletSwitchTextResolverV6.validate(model: model)
        let visual = try GoldenEyeWalletSwitchTextResolverV6.resolve(route: .modeSelect)
        let compiled = GESourceModelCompilerV6.compile(model, modelName: "walletbond", switchInputs: visual.switchInputs, switchInputsAreVisibility: true)
        guard let scene = compiled.scene, compiled.diagnostics.isEmpty else {
            FileHandle.standardError.write(Data(("wallet-route-diagnostics " + String(describing: compiled.diagnostics) + "\n").utf8))
            throw GoldenEyeSourceModelV6.Error.invalid("wallet scene compile")
        }
        let setups = try GoldenEyeSourceTextureSetupResolverV6.resolve(modelName: "walletbond", model: model, catalog: catalog, compiledCommands: scene.commands)
        let result = try GoldenEyeGBISceneBuilderV6.build(model: model, modelName: "walletbond", switchInputs: visual.switchInputs, matrices: matrices.matrices, viewports: matrices.viewports, matrixRoles: try matrixRoles(matrices.matrices), frame: frame, textureSetups: setups.setups, switchInputsAreVisibility: true)
        require(result.presentable && result.unsupportedVisibleCount == 0, "single wallet scene closure")
        return result.snapshot
    }

    private static func buildWalletScene(
        model: GoldenEyeSourceModelV6,
        modelName: String,
        catalog: GoldenEyeSourceFrontendCatalog,
        matrices: [GoldenEyeGBIMatrixResourceV6],
        viewports: [GoldenEyeGBIViewportResourceV6],
        frame: GoldenEyeGBISceneFrameContextV6
    ) throws -> GoldenEyeSourceSceneSnapshotV6 {
        let modelMatrices = matrices.filter { $0.roleFlags & GoldenEyeSourceMatrixRoleSidecarV6.modelView != 0 }
        guard modelMatrices.count == 4 else { throw GoldenEyeSourceModelV6.Error.invalid("four wallet matrices") }
        let sourceHandle = modelMatrices[0].handle
        let nonModel = matrices.filter { $0.roleFlags & GoldenEyeSourceMatrixRoleSidecarV6.modelView == 0 }
        try GoldenEyeWalletSwitchTextResolverV6.validate(model: model)
        let fileSelect = frame.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_FILE_SELECT)
        let visual = try GoldenEyeWalletSwitchTextResolverV6.resolve(route: fileSelect ? .fileSelect : .modeSelect)
        let switchInputs = visual.switchInputs
        let compiled = GESourceModelCompilerV6.compile(model, modelName: modelName, switchInputs: switchInputs, switchInputsAreVisibility: true)
        guard let scene = compiled.scene, compiled.diagnostics.isEmpty else {
            FileHandle.standardError.write(Data(("wallet-route-diagnostics " + String(describing: compiled.diagnostics) + "\n").utf8))
            throw GoldenEyeSourceModelV6.Error.invalid("wallet scene compile")
        }
        let setups = try GoldenEyeSourceTextureSetupResolverV6.resolve(modelName: modelName, model: model, catalog: catalog, compiledCommands: scene.commands)
        var results: [GoldenEyeGBISceneBuildResultV6] = []
        for matrix in modelMatrices {
            let scoped = nonModel + [try GoldenEyeGBIMatrixResourceV6(handle: sourceHandle, values: matrix.values, roleFlags: GoldenEyeSourceMatrixRoleSidecarV6.modelView)]
            let result = try GoldenEyeGBISceneBuilderV6.build(model: model, modelName: modelName, switchInputs: switchInputs, matrices: scoped, viewports: viewports, matrixRoles: try matrixRoles(scoped), frame: frame, textureSetups: setups.setups, switchInputsAreVisibility: true)
            FileHandle.standardError.write(Data(("wallet-instance draws=" + String(result.snapshot.drawCommands.count) + " triangles=" + String(result.triangleCount) + " unsupported=" + String(result.unsupportedVisibleCount) + "\n").utf8))
            require(result.presentable && result.unsupportedVisibleCount == 0 && result.snapshot.drawCommands.count == 8, "wallet instance closure")
            results.append(result)
        }
        return try GoldenEyeSourceSceneComposerV6.combine(results, frame: frame)
    }

    private static func copyView(save: GoldenEyeSaveState) throws -> GoldenEyeSource2DFileModeViewV6 {
        var authority = try GoldenEyeFileModeAuthorityV6(saveState: save)
        var tick: UInt64 = 0
        for _ in 0..<21 { tick += 1; _ = try authority.step(.init(nativeTick: tick, sequence: tick, stickY: 75, synthetic: true)) }
        tick += 1
        let frame = try authority.step(.init(nativeTick: tick, sequence: tick, pressed: UInt32(GE_FILE_MODE_V6_BUTTON_A), synthetic: true))
        return try GoldenEyeSource2DFileModeViewV6(frame: frame, saveState: authority.saveState)
    }

    private static func eraseDialogView(save: GoldenEyeSaveState) throws -> GoldenEyeSource2DFileModeViewV6 {
        var authority = try GoldenEyeFileModeAuthorityV6(saveState: save)
        var tick: UInt64 = 0
        for _ in 0..<21 { tick += 1; _ = try authority.step(.init(nativeTick: tick, sequence: tick, stickX: 75, stickY: 75, synthetic: true)) }
        tick += 1
        _ = try authority.step(.init(nativeTick: tick, sequence: tick, pressed: UInt32(GE_FILE_MODE_V6_BUTTON_A), synthetic: true))
        for index in 0..<46 { tick += 1; _ = try authority.step(.init(nativeTick: tick, sequence: tick, stickX: -75, stickY: index < 20 ? -75 : 0, synthetic: true)) }
        tick += 1
        let frame = try authority.step(.init(nativeTick: tick, sequence: tick, pressed: UInt32(GE_FILE_MODE_V6_BUTTON_A), synthetic: true))
        return try GoldenEyeSource2DFileModeViewV6(frame: frame, saveState: authority.saveState)
    }

    private static func modeView(save: GoldenEyeSaveState, multiplayer: Bool) throws -> GoldenEyeSource2DFileModeViewV6 {
        var authority = try GoldenEyeFileModeAuthorityV6(saveState: save)
        var tick: UInt64 = 1
        var frame = try authority.step(.init(nativeTick: tick, sequence: tick, pressed: UInt32(GE_FILE_MODE_V6_BUTTON_A), controllerCount: 2, synthetic: true))
        if multiplayer {
            for _ in 0..<4 { tick += 1; frame = try authority.step(.init(nativeTick: tick, sequence: tick, stickY: 75, controllerCount: 2, synthetic: true)) }
        }
        return try GoldenEyeSource2DFileModeViewV6(frame: frame, saveState: authority.saveState)
    }
}
