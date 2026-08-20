import Foundation
import CryptoKit
import Metal
import QuartzCore

private func readHDTexture(_ texture: any MTLTexture, width: Int, height: Int) -> Data {
    var bytes = Data(repeating: 0, count: width * height * 4)
    bytes.withUnsafeMutableBytes { rawBytes in
        texture.getBytes(
            rawBytes.baseAddress!,
            bytesPerRow: width * 4,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )
    }
    return bytes
}

private func sha256(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
}

private func hasNonBlackRGB(_ bytes: Data) -> Bool {
    var offset = 0
    while offset + 2 < bytes.count {
        if bytes[offset] != 0 || bytes[offset + 1] != 0 || bytes[offset + 2] != 0 {
            return true
        }
        offset += 4
    }
    return false
}

private func nonBlackRGBPixelCount(_ bytes: Data) -> Int {
    var count = 0
    var offset = 0
    while offset + 2 < bytes.count {
        if bytes[offset] != 0 || bytes[offset + 1] != 0 || bytes[offset + 2] != 0 {
            count += 1
        }
        offset += 4
    }
    return count
}

private func decodedRGBAStats(_ bytes: Data) -> (nonBlack: Int, nonTransparent: Int, maxAlpha: Int) {
    var nonBlack = 0
    var nonTransparent = 0
    var maxAlpha = 0
    var offset = 0
    while offset + 3 < bytes.count {
        let r = bytes[offset]
        let g = bytes[offset + 1]
        let b = bytes[offset + 2]
        let a = bytes[offset + 3]
        if r != 0 || g != 0 || b != 0 { nonBlack += 1 }
        if a != 0 { nonTransparent += 1 }
        maxAlpha = max(maxAlpha, Int(a))
        offset += 4
    }
    return (nonBlack, nonTransparent, maxAlpha)
}

private func decodedRGBASampleStats(
    _ bytes: Data,
    width: Int,
    height: Int,
    normalizedUVs: [(Double, Double)]
) -> (nonBlack: Int, nonTransparent: Int) {
    guard width > 0, height > 0 else { return (0, 0) }
    var nonBlack = 0
    var nonTransparent = 0
    for (u, v) in normalizedUVs {
        let x = min(width - 1, max(0, Int((min(1, max(0, u)) * Double(width - 1)).rounded())))
        let y = min(height - 1, max(0, Int((min(1, max(0, v)) * Double(height - 1)).rounded())))
        let offset = (y * width + x) * 4
        guard offset + 3 < bytes.count else { continue }
        if bytes[offset] != 0 || bytes[offset + 1] != 0 || bytes[offset + 2] != 0 {
            nonBlack += 1
        }
        if bytes[offset + 3] != 0 { nonTransparent += 1 }
    }
    return (nonBlack, nonTransparent)
}

private func decodedRGBAEdgeStats(
    _ bytes: Data,
    width: Int,
    height: Int
) -> [String: Int] {
    guard width > 0, height > 0 else { return [:] }
    func count(_ coordinates: [(Int, Int)]) -> Int {
        coordinates.reduce(into: 0) { count, coordinate in
            let offset = (coordinate.1 * width + coordinate.0) * 4
            guard offset + 2 < bytes.count else { return }
            if bytes[offset] != 0 || bytes[offset + 1] != 0 || bytes[offset + 2] != 0 {
                count += 1
            }
        }
    }
    return [
        "leftColumn": count((0..<height).map { (0, $0) }),
        "rightColumn": count((0..<height).map { (width - 1, $0) }),
        "topRow": count((0..<width).map { ($0, 0) }),
        "bottomRow": count((0..<width).map { ($0, height - 1) }),
    ]
}

private func isolatedLegalSnapshot(
    _ source: GoldenEyeSourceSceneSnapshotV6,
    drawIndex: Int
) throws -> GoldenEyeSourceSceneSnapshotV6 {
    guard drawIndex >= 0, drawIndex < source.drawCommands.count else {
        throw GoldenEyeSourceSceneSnapshotV6Error.invalidRecord("Legal isolated draw index")
    }
    let sourceDraw = source.drawCommands[drawIndex]
    let firstVertex = Int(sourceDraw.first_vertex)
    let vertexEnd = firstVertex + Int(sourceDraw.vertex_count)
    let firstIndex = Int(sourceDraw.first_index)
    let indexEnd = firstIndex + Int(sourceDraw.index_count)
    guard vertexEnd <= source.vertices.count, indexEnd <= source.indices.count else {
        throw GoldenEyeSourceSceneSnapshotV6Error.rangeOverflow("Legal isolated draw range")
    }
    let vertices = Array(source.vertices[firstVertex..<vertexEnd])
    let sourceIndices = Array(source.indices[firstIndex..<indexEnd])
    var indices: [GESourceIndexV6] = []
    indices.reserveCapacity(sourceIndices.count)
    for sourceIndex in sourceIndices {
        var index = sourceIndex
        guard index.vertex0 >= sourceDraw.first_vertex,
              index.vertex1 >= sourceDraw.first_vertex,
              index.vertex2 >= sourceDraw.first_vertex else {
            throw GoldenEyeSourceSceneSnapshotV6Error.rangeOverflow("Legal isolated index base")
        }
        index.vertex0 -= sourceDraw.first_vertex
        index.vertex1 -= sourceDraw.first_vertex
        index.vertex2 -= sourceDraw.first_vertex
        indices.append(index)
    }
    var draw = sourceDraw
    draw.first_vertex = 0
    draw.first_index = 0
    draw.vertex_count = UInt32(vertices.count)
    draw.index_count = UInt32(indices.count)

    let transforms = source.transforms.filter { $0.handle == sourceDraw.transform_handle }
    let states = source.renderStates.filter { $0.state_handle == sourceDraw.render_state_handle }
    guard transforms.count == 1, states.count == 1 else {
        throw GoldenEyeSourceSceneSnapshotV6Error.missingHandle(
            "isolated Legal transform/state",
            sourceDraw.transform_handle
        )
    }

    var summary = source.summary
    summary.transform_count = UInt32(transforms.count)
    summary.pose_count = 0
    summary.vertex_count = UInt32(vertices.count)
    summary.index_count = UInt32(indices.count)
    summary.draw_count = 1
    summary.render_state_count = UInt32(states.count)
    summary.text_count = 0
    summary.audio_count = 0
    summary.diagnostic_count = 0
    summary.scene_hash = source.summary.scene_hash ^ UInt64(drawIndex + 1)
    summary.render_hash = source.summary.render_hash ^ UInt64(drawIndex + 1)
    summary.frame_hash = source.summary.frame_hash ^ UInt64(drawIndex + 1)
    if summary.scene_hash == 0 { summary.scene_hash = 1 }
    if summary.render_hash == 0 { summary.render_hash = 1 }
    if summary.frame_hash == 0 { summary.frame_hash = 1 }

    return try GoldenEyeSourceSceneSnapshotV6(
        summary: summary,
        resources: source.resources,
        transforms: transforms,
        animationPoses: [],
        vertices: vertices,
        indices: indices,
        renderStates: states,
        drawCommands: [draw],
        textEvents: [],
        audioEvents: [],
        diagnostics: [],
        lightingFrameContext: source.lightingFrameContext
    )
}

private func q16Values<T>(_ value: T, count: Int) -> [Int32] {
    withUnsafeBytes(of: value) { rawBytes in
        Array(rawBytes.bindMemory(to: Int32.self).prefix(count))
    }
}

private func signedQ16(_ value: Int32) -> Double {
    Double(value) / 65_536.0
}

private func legalDrawDiagnostics(
    snapshot: GoldenEyeSourceSceneSnapshotV6,
    geometryModesByState: [UInt32: UInt32]
) -> [[String: Any]] {
    let transforms = snapshot.transformByHandle
    let states = snapshot.renderStateByHandle
    return snapshot.drawCommands.map { draw in
        let vertexStart = Int(draw.first_vertex)
        let vertexEnd = vertexStart + Int(draw.vertex_count)
        let vertices = Array(snapshot.vertices[vertexStart..<vertexEnd])
        let positions = vertices.flatMap { q16Values($0.position_q16, count: 3) }
        let texcoords = vertices.flatMap { q16Values($0.texcoord_q16, count: 2) }
        let transform = transforms[draw.transform_handle]
        var ndc: [(Double, Double, Double, Double)] = []
        if let transform {
            let matrix = q16Values(transform.matrix_q16, count: 16)
            for vertex in vertices {
                let p = q16Values(vertex.position_q16, count: 3)
                if let clip = try? GoldenEyeSourceProjectionBindingV6.apply(
                    matrixQ16: matrix,
                    pointQ16: (p[0], p[1], p[2])
                ), clip.w != 0 {
                    let w = signedQ16(clip.w)
                    ndc.append((signedQ16(clip.x) / w, signedQ16(clip.y) / w, signedQ16(clip.z) / w, w))
                }
            }
        }
        let ndcX = ndc.map { $0.0 }
        let ndcY = ndc.map { $0.1 }
        let ndcZ = ndc.map { $0.2 }
        let screenX = ndcX.map { ($0 + 1.0) * 160.0 }
        let screenY = ndcY.map { (1.0 - $0) * 120.0 }
        let state = states[draw.render_state_handle]
        return [
            "drawHandle": draw.draw_handle,
            "transformHandle": draw.transform_handle,
            "resourceHandle": draw.resource_handle,
            "renderStateHandle": draw.render_state_handle,
            "sourceVertexIDs": vertices.map(\.source_index),
            "sourcePositions": stride(from: 0, to: positions.count, by: 3).map {
                [signedQ16(positions[$0]), signedQ16(positions[$0 + 1]), signedQ16(positions[$0 + 2])]
            },
            "normalizedUV": stride(from: 0, to: texcoords.count, by: 2).map {
                [signedQ16(texcoords[$0]), signedQ16(texcoords[$0 + 1])]
            },
            "ndcBounds": [
                ndcX.min() ?? .nan, ndcX.max() ?? .nan,
                ndcY.min() ?? .nan, ndcY.max() ?? .nan,
                ndcZ.min() ?? .nan, ndcZ.max() ?? .nan,
            ],
            "sourcePixelBounds": [
                screenX.min() ?? .nan, screenX.max() ?? .nan,
                screenY.min() ?? .nan, screenY.max() ?? .nan,
            ],
            "clipW": ndc.map(\.3),
            "geometryMode": geometryModesByState[draw.render_state_handle] ?? 0,
            "cullMode": state?.cull_mode ?? 0,
            "rawOtherModeH": state?.raw_othermode_h ?? 0,
            "rawOtherModeL": state?.raw_othermode_l ?? 0,
        ]
    }
}

@available(macOS 27.0, *)
@main
struct GoldenEyeLegalReferenceCaptureV6Smoke {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4) else {
            print("goldeneye_legal_reference_capture_v6_smoke: SKIP (Metal 4 device unavailable)")
            return
        }
        let root = URL(
            fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/native/source-frontend-v6",
            isDirectory: true
        )
        let metallibURL = URL(
            fileURLWithPath: CommandLine.arguments.dropFirst().dropFirst().first
                ?? "build/native/source-scene-renderer-v6/GoldenEyeSourceSceneV6.metallib"
        )
        let twoDMetallibURL = URL(
            fileURLWithPath: CommandLine.arguments.dropFirst().dropFirst().dropFirst().first
                ?? "build/native/source-2d-metal-v6/GoldenEyeSource2DV6.metallib"
        )
        guard FileManager.default.fileExists(atPath: metallibURL.path) else {
            print("goldeneye_legal_reference_capture_v6_smoke: SKIP (source-scene metallib unavailable)")
            return
        }
        guard FileManager.default.fileExists(atPath: twoDMetallibURL.path) else {
            print("goldeneye_legal_reference_capture_v6_smoke: SKIP (source-2D metallib unavailable)")
            return
        }
        let output = URL(
            fileURLWithPath: CommandLine.arguments.dropFirst().dropFirst().dropFirst().dropFirst().first
                ?? "build/native/legal-reference-capture-v6/legal-reference-320x240-composite.raw"
        )
        let outputStem = output.deletingPathExtension().lastPathComponent
        let threeDOutput = output.deletingLastPathComponent()
            .appendingPathComponent(outputStem + "-3d.raw")
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let frame = try GoldenEyeLegalFrameV6.build(rootURL: root)
        precondition(frame.text.sourceEvents.count == 12, "Legal text events must be present")
        precondition(frame.scene.unsupportedVisibleCount == 0, "Legal scene has unsupported visible work")
        let legalModel = try GoldenEyeSourceModelV6.load(
            from: root.appendingPathComponent("legalpage.gesm")
        )
        let rawGfxCount = legalModel.commands.filter { $0.semantic.hasPrefix("rawGfx") }.count
        precondition(rawGfxCount == 12, "Legal raw Gfx command count")
        precondition(frame.scene.sourceTriangleSlotCount == 12, "Legal source triangle slots")
        precondition(frame.scene.stateWordEvidence.count == 6, "Legal material state evidence")
        var textureCoordinateHash: UInt64 = 1_469_598_103_934_665_603
        for vertex in frame.scene.snapshot.vertices {
            withUnsafeBytes(of: vertex.texcoord_q16) { raw in
                for byte in raw {
                    textureCoordinateHash = (textureCoordinateHash ^ UInt64(byte)) &* 1_099_511_628_211
                }
            }
        }
        let drawMaterialHandles = frame.scene.snapshot.drawCommands.map { $0.resource_handle }
        let drawTriangleCounts = frame.scene.snapshot.drawCommands.map { $0.index_count }
        let sourceVertexIDsByDraw = frame.scene.snapshot.drawCommands.map { draw in
            let first = Int(draw.first_vertex)
            let end = first + Int(draw.vertex_count)
            return Array(frame.scene.snapshot.vertices[first..<end]).map(\.source_index)
        }
        // The first four source triangles use the first G_VTX cache load;
        // after the second gsSPVertex(0x050021A8, 8, 0), the cache-local
        // indices must resolve to model vertices 16...23.  Keep this as
        // evidence here rather than silently accepting a duplicate first
        // material quad from a builder that loses the cache-load base.
        let expectedSourceVertexIDsByDraw: [[UInt32]] = [
            [0, 1, 2, 0, 2, 3],
            [4, 5, 6, 4, 6, 7],
            [8, 9, 10, 8, 10, 11],
            [12, 13, 14, 12, 14, 15],
            [16, 17, 18, 16, 18, 19],
            [20, 21, 22, 20, 22, 23],
        ]
        let sourceVertexCoverageMatches = sourceVertexIDsByDraw == expectedSourceVertexIDsByDraw
        precondition(
            sourceVertexCoverageMatches,
            "Legal source G_VTX cache loads must resolve second-load vertices 16...23; observed \(sourceVertexIDsByDraw)"
        )
        precondition(drawMaterialHandles.count == 6, "Legal source material draw count")
        precondition(drawMaterialHandles.first == 0, "Legal shade-only material ordering")
        precondition(Set(drawMaterialHandles.dropFirst()) == Set(frame.modelTextureHandles), "all five Legal textures are submitted")
        precondition(drawTriangleCounts.allSatisfy { $0 > 0 }, "each Legal material has source triangles")
        let preparation = try GoldenEyeSourceProductPreparationV6.load(rootURL: root)
        let twoDAssets = try GoldenEyeSource2DAssetsV6(
            catalog: preparation.catalog,
            requiredIcons: []
        )
        let twoDFrame = try GoldenEyeSource2DLowererV6(assets: twoDAssets).makeLegalFrame(
            nativeTick: frame.source.nativeTick,
            sourceTimer: frame.source.sourceTimer,
            textEvents: []
        )
        let twoDBatch = try GoldenEyeSource2DMetalBatchBuilderV6.build(
            frame: twoDFrame,
            assets: twoDAssets,
            outputWidth: 320,
            outputHeight: 240,
            mode: .reference320x240
        )
        precondition(twoDBatch.draws.contains { $0.primitive == .glyph }, "Legal glyph batch")

        let layer = CAMetalLayer()
        let hdWidth = 640
        let hdHeight = 480
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.drawableSize = CGSize(width: hdWidth, height: hdHeight)
        layer.framebufferOnly = false
        layer.maximumDrawableCount = 2
        layer.allowsNextDrawableTimeout = true
        layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        let state = try GoldenEyeMetalDeviceState(device: device, layer: layer)
        layer.framebufferOnly = false
        let uploadEvent = device.makeSharedEvent()!
        uploadEvent.label = "GoldenEye.Legal.Reference.TextureUpload"
        let textureStore = try GoldenEyeSourceTextureStoreV6(
            context: GoldenEyeSourceTextureStoreV6MetalContext(
                device: device,
                queue: state.queue,
                residency: state.sceneResidency,
                completionEvent: uploadEvent
            )
        )
        let models = preparation.models.keys.sorted().compactMap { name in
            preparation.models[name].map { (name: name, model: $0) }
        }
        let texturePlan = try GoldenEyeSourceTextureUploadPlanV6.make(
            catalog: preparation.catalog,
            models: models
        )
        _ = try textureStore.upload(plan: texturePlan)
        try textureStore.drain()

        let pipeline = try GoldenEyeSourceScenePipelineV6(
            device: device,
            libraryURL: metallibURL,
            pixelFormat: .bgra8Unorm
        )
        let twoDRenderer = try GoldenEyeSource2DMetalRendererV6(
            state: state,
            assets: twoDAssets,
            libraryURL: twoDMetallibURL,
            outputMode: .reference320x240
        )
        let twoDHDRenderer = try GoldenEyeSource2DMetalRendererV6(
            state: state,
            assets: twoDAssets,
            libraryURL: twoDMetallibURL,
            outputMode: .faithfulHD
        )
        let renderer = try GoldenEyeSourceSceneRendererV6(
            state: state,
            pipeline: pipeline,
            textureResolver: { handle in textureStore.texture(handle: handle) },
            outputMode: .reference320x240,
            frontFacing: .counterClockwise
        )
        // First capture the authored 3D scene without the overlay. This
        // separates projection/winding failure from a later glyph composite.
        let threeDCapture = try renderer.captureReference320x240(
            snapshot: frame.scene.snapshot,
            to: threeDOutput
        )
        precondition(threeDCapture.evidence.triangleCount == 12, "3D-only triangle count")
        precondition(hasNonBlackRGB(threeDCapture.bytes), "3D-only Legal frame is all black")
        var encoded2DBatch: GoldenEyeSource2DMetalBatchV6?
        let capture = try renderer.captureReference320x240(
            snapshot: frame.scene.snapshot,
            to: output,
            overlay: { encoder, slotIndex in
                encoded2DBatch = try twoDRenderer.encodeOverlay(
                    frame: twoDFrame,
                    into: encoder,
                    drawableWidth: 320,
                    drawableHeight: 240,
                    slotIndex: slotIndex
                )
            }
        )
        precondition(capture.width == 320 && capture.height == 240, "reference dimensions")
        precondition(capture.bytes.count == 320 * 240 * 4, "reference raw byte count")
        precondition(capture.evidence.drawCount == 6, "reference 3D draw count")
        precondition(capture.evidence.triangleCount == 12, "reference triangle count")
        guard let encoded2DBatch else { preconditionFailure("missing encoded Legal 2D batch") }
        precondition(encoded2DBatch.draws.filter { $0.primitive == .glyph }.count == 253, "encoded Legal glyph count")
        precondition(capture.rawSHA256.count == 64, "reference raw hash")
        guard let pngURL = capture.pngURL else { preconditionFailure("missing lossless PNG") }
        guard let threeDPngURL = threeDCapture.pngURL else { preconditionFailure("missing 3D-only PNG") }
        let decoded3D = try GoldenEyeReferenceCaptureCodecV6.decodePNG(Data(contentsOf: threeDPngURL))
        func rgbMismatch(_ decoded: Data, _ raw: Data) -> [(Int, UInt8, UInt8)] {
            stride(from: 0, to: min(decoded.count, raw.count), by: 4).compactMap { offset in
                let decodedPixel = (decoded[offset], decoded[offset + 1], decoded[offset + 2])
                let rawPixel = (raw[offset], raw[offset + 1], raw[offset + 2])
                guard decodedPixel != rawPixel else { return nil }
                return (offset, decoded[offset], raw[offset])
            }
        }
        let threeDMismatch = rgbMismatch(decoded3D.bgra8, threeDCapture.bytes)
        if !threeDMismatch.isEmpty {
            let sample = threeDMismatch.prefix(8).map { "\($0.0):\($0.1)/\($0.2)" }.joined(separator: ",")
            preconditionFailure("3D-only PNG RGB is not lossless (mismatch=\(threeDMismatch.count) sample=\(sample))")
        }
        let decoded = try GoldenEyeReferenceCaptureCodecV6.decodePNG(Data(contentsOf: pngURL))
        precondition(decoded.width == 320 && decoded.height == 240, "PNG dimensions")
        let compositeMismatch = rgbMismatch(decoded.bgra8, capture.bytes)
        if !compositeMismatch.isEmpty {
            let sample = compositeMismatch.prefix(8).map { "\($0.0):\($0.1)/\($0.2)" }.joined(separator: ",")
            preconditionFailure("PNG RGB is not lossless (mismatch=\(compositeMismatch.count) sample=\(sample))")
        }
        precondition(hasNonBlackRGB(capture.bytes), "composited Legal frame is not all black")
        precondition(capture.rawSHA256 != threeDCapture.rawSHA256, "2D composite did not change the 3D target")
        precondition(FileManager.default.fileExists(atPath: output.appendingPathExtension("json").path), "capture metadata")
        precondition(FileManager.default.fileExists(atPath: threeDOutput.appendingPathExtension("json").path), "3D-only metadata")

        let hd3DOutput = output.deletingLastPathComponent()
            .appendingPathComponent("legal-faithful-hd-\(hdWidth)x\(hdHeight)-3d.raw")
        let hdOutput = output.deletingLastPathComponent()
            .appendingPathComponent("legal-faithful-hd-\(hdWidth)x\(hdHeight).raw")
        let hdRenderer = try GoldenEyeSourceSceneRendererV6(
            state: state,
            pipeline: pipeline,
            textureResolver: { handle in textureStore.texture(handle: handle) },
            outputMode: .faithfulHD,
            frontFacing: .counterClockwise
        )
        guard let hd3DDrawable = layer.nextDrawable() else {
            throw NSError(domain: "LegalCapture", code: 10, userInfo: [
                NSLocalizedDescriptionKey: "Faithful HD 3D drawable unavailable"
            ])
        }
        let hd3DTexture = hd3DDrawable.texture
        let hd3DEvidence = try hdRenderer.render(
            snapshot: frame.scene.snapshot,
            suppliedDrawable: hd3DDrawable
        )
        guard let hdDrawable = layer.nextDrawable() else {
            throw NSError(domain: "LegalCapture", code: 11, userInfo: [
                NSLocalizedDescriptionKey: "Faithful HD composite drawable unavailable"
            ])
        }
        let hdTexture = hdDrawable.texture
        var encodedHD2DBatch: GoldenEyeSource2DMetalBatchV6?
        let hdEvidence = try hdRenderer.render(
            snapshot: frame.scene.snapshot,
            suppliedDrawable: hdDrawable,
            overlay: { encoder, slotIndex in
                encodedHD2DBatch = try twoDHDRenderer.encodeOverlay(
                    frame: twoDFrame,
                    into: encoder,
                    drawableWidth: hdWidth,
                    drawableHeight: hdHeight,
                    slotIndex: slotIndex
                )
            }
        )
        hdRenderer.shutdown()
        twoDHDRenderer.shutdown()
        let hd3DBytes = readHDTexture(hd3DTexture, width: hdWidth, height: hdHeight)
        let hdBytes = readHDTexture(hdTexture, width: hdWidth, height: hdHeight)
        let hd3DSHA256 = sha256(hd3DBytes)
        let hdSHA256 = sha256(hdBytes)
        precondition(hd3DEvidence.triangleCount == 12, "Faithful HD 3D triangle count")
        precondition(hdEvidence.triangleCount == 12, "Faithful HD composite triangle count")
        precondition(hdBytes.count == hdWidth * hdHeight * 4, "Faithful HD byte count")
        precondition(hd3DSHA256 != hdSHA256, "Faithful HD overlay did not change target")
        guard let encodedHD2DBatch else { preconditionFailure("missing Faithful HD 2D batch") }
        precondition(encodedHD2DBatch.draws.filter { $0.primitive == .glyph }.count == 253, "Faithful HD glyph count")
        try hd3DBytes.write(to: hd3DOutput, options: .atomic)
        try hdBytes.write(to: hdOutput, options: .atomic)
        let hd3DPNGURL = hd3DOutput.deletingPathExtension().appendingPathExtension("png")
        let hdPNGURL = hdOutput.deletingPathExtension().appendingPathExtension("png")
        try GoldenEyeReferenceCaptureCodecV6.encodePNG(
            bgra8: hd3DBytes,
            width: hdWidth,
            height: hdHeight,
            bytesPerRow: hdWidth * 4
        ).write(to: hd3DPNGURL, options: .atomic)
        try GoldenEyeReferenceCaptureCodecV6.encodePNG(
            bgra8: hdBytes,
            width: hdWidth,
            height: hdHeight,
            bytesPerRow: hdWidth * 4
        ).write(to: hdPNGURL, options: .atomic)

        let drawDiagnostics = legalDrawDiagnostics(
            snapshot: frame.scene.snapshot,
            geometryModesByState: frame.scene.geometryModesByState
        )
        var isolatedMaterialEvidence: [[String: Any]] = []
        for drawIndex in 1..<frame.scene.snapshot.drawCommands.count {
            let draw = frame.scene.snapshot.drawCommands[drawIndex]
            let textureIndex = drawIndex - 1
            let expectedHandle = frame.modelTextureHandles[textureIndex]
            precondition(draw.resource_handle == expectedHandle, "Legal material handle order (drawIndex)")
            let isolatedSnapshot = try isolatedLegalSnapshot(
                frame.scene.snapshot,
                drawIndex: drawIndex
            )
            let materialURL = output.deletingLastPathComponent().appendingPathComponent(
                "legal-reference-320x240-material-\(drawIndex)-\(String(draw.resource_handle, radix: 16)).raw"
            )
            let isolatedCapture = try renderer.captureReference320x240(
                snapshot: isolatedSnapshot,
                to: materialURL
            )
            precondition(isolatedCapture.evidence.drawCount == 1, "isolated Legal draw count")
            precondition(isolatedCapture.evidence.triangleCount == Int(draw.index_count), "isolated Legal triangle count")
            guard let descriptor = texturePlan.descriptors.first(where: {
                $0.resourceHandle == draw.resource_handle
            }), let level = descriptor.levels.first else {
                preconditionFailure("missing uploaded payload for Legal material (draw.resource_handle)")
            }
            let decodedStats = decodedRGBAStats(level.decoded)
            let isolatedNonBlackPixels = nonBlackRGBPixelCount(isolatedCapture.bytes)
            let intentionallyEmpty = decodedStats.nonBlack == 0 || decodedStats.nonTransparent == 0
            let contributed = isolatedNonBlackPixels > 0
            let materialVertexStart = Int(draw.first_vertex)
            let materialVertexEnd = materialVertexStart + Int(draw.vertex_count)
            let materialUVs = frame.scene.snapshot.vertices[materialVertexStart..<materialVertexEnd].map {
                let values = q16Values($0.texcoord_q16, count: 2)
                return (signedQ16(values[0]), signedQ16(values[1]))
            }
            let sampledStats = decodedRGBASampleStats(
                level.decoded,
                width: Int(level.width),
                height: Int(level.height),
                normalizedUVs: materialUVs
            )
            let edgeStats = decodedRGBAEdgeStats(
                level.decoded,
                width: Int(level.width),
                height: Int(level.height)
            )
            let uValues = materialUVs.map(\.0)
            let vValues = materialUVs.map(\.1)
            let nearRightEdge = (uValues.min() ?? 0) >= 0.98 && (uValues.max() ?? 0) <= 1.02
            let nearBottomEdge = (vValues.min() ?? 0) >= 0.98 && (vValues.max() ?? 0) <= 1.02
            let sourceEdgeIsBlack = sampledStats.nonBlack == 0 && (
                (nearRightEdge && edgeStats["rightColumn"] == 0) ||
                (nearBottomEdge && edgeStats["bottomRow"] == 0 && edgeStats["topRow"] == 0)
            )
            // Edge sampling is diagnostic only. A non-empty decoded payload
            // must contribute visible pixels; collapsed UVs cannot be
            // accepted as an intentional black material.
            let sourceBlackOrTransparentProof = intentionallyEmpty
            let state = frame.scene.snapshot.renderStateByHandle[draw.render_state_handle]
            let sourceOffset = frame.scene.snapshot.indices[Int(draw.first_index)].source_index
            let packetIndex = Int(sourceOffset) / MemoryLayout<GEGBISourceCommandV6>.stride
            let modelCommandIndex = packetIndex - 2
            let sourceCommand = modelCommandIndex >= 0 && modelCommandIndex < legalModel.commands.count
                ? legalModel.commands[modelCommandIndex]
                : nil
            let setup = sourceCommand.flatMap { command in
                frame.scene.textureSetups
                    .filter {
                        $0.displayListID == command.displayListID && $0.ordinal <= command.ordinal
                    }
                    .max {
                        if $0.ordinal != $1.ordinal { return $0.ordinal < $1.ordinal }
                        return $0.sequence < $1.sequence
                    }
            }
            let sourceST = frame.scene.snapshot.vertices[materialVertexStart..<materialVertexEnd].map {
                let values = q16Values($0.texcoord_q16, count: 2)
                return [signedQ16(values[0]), signedQ16(values[1])]
            }
            let sourceST10_5 = frame.scene.snapshot.vertices[materialVertexStart..<materialVertexEnd].map {
                let sourceIndex = Int($0.source_index)
                guard legalModel.vertices.indices.contains(sourceIndex) else { return [Int32.min, Int32.min] }
                let source = legalModel.vertices[sourceIndex]
                return [source.s, source.t]
            }
            isolatedMaterialEvidence.append([
                "drawIndex": drawIndex,
                "resourceHandle": draw.resource_handle,
                "expectedResourceHandle": expectedHandle,
                "sourceVertexIDs": drawDiagnostics[drawIndex]["sourceVertexIDs"] ?? [],
                "sourceCommandOffset": sourceOffset,
                "sourceCommandOrdinal": sourceCommand?.ordinal ?? 0,
                "sourceCommandSemantic": sourceCommand?.semantic ?? "missing",
                "sourceST10_5": sourceST10_5,
                "loweredTexcoord": sourceST,
                "sourcePixelBounds": drawDiagnostics[drawIndex]["sourcePixelBounds"] ?? [],
                "normalizedUV": drawDiagnostics[drawIndex]["normalizedUV"] ?? [],
                "rawOtherModeH": state?.raw_othermode_h ?? 0,
                "rawOtherModeL": state?.raw_othermode_l ?? 0,
                "wrapS": state?.wrap_s ?? 0,
                "wrapT": state?.wrap_t ?? 0,
                "filterMode": state?.filter_mode ?? 0,
                "combiner": state.map {
                    [
                        $0.cycle0_color_a, $0.cycle0_color_b, $0.cycle0_color_c, $0.cycle0_color_d,
                        $0.cycle0_alpha_a, $0.cycle0_alpha_b, $0.cycle0_alpha_c, $0.cycle0_alpha_d,
                    ]
                } ?? [],
                "payloadRecordID": descriptor.payloadRecordID,
                "payloadWidth": level.width,
                "payloadHeight": level.height,
                "payloadNonBlackPixels": decodedStats.nonBlack,
                "payloadNonTransparentPixels": decodedStats.nonTransparent,
                "payloadMaxAlpha": decodedStats.maxAlpha,
                "payloadSampledNonBlackVertices": sampledStats.nonBlack,
                "payloadSampledNonTransparentVertices": sampledStats.nonTransparent,
                "payloadEdgeNonBlackPixels": edgeStats,
                "sourceUVNearRightEdge": nearRightEdge,
                "sourceUVNearBottomEdge": nearBottomEdge,
                "sourceEdgeIsBlack": sourceEdgeIsBlack,
                "sourceBlackOrTransparentProof": sourceBlackOrTransparentProof,
                "setupSequence": setup?.sequence ?? 0,
                "setupKind": setup?.kind.rawValue ?? UInt32.max,
                "setupResourceHandle": setup?.resourceHandle ?? 0,
                "setupTile": setup?.tile ?? 0,
                "setupTextureScaleS": setup?.textureScaleS ?? 0,
                "setupTextureScaleT": setup?.textureScaleT ?? 0,
                "setupMaxLOD": setup?.maxLOD ?? 0,
                "setupTileBounds": setup.map {
                    [$0.tileState.bounds.ulsQ2, $0.tileState.bounds.ultQ2,
                     $0.tileState.bounds.lrsQ2, $0.tileState.bounds.lrtQ2]
                } ?? [],
                "setupAddressS": setup?.tileState.addressS.rawValue ?? UInt32.max,
                "setupAddressT": setup?.tileState.addressT.rawValue ?? UInt32.max,
                "setupMaskS": setup?.tileState.maskS ?? 0,
                "setupMaskT": setup?.tileState.maskT ?? 0,
                "setupShiftS": setup?.tileState.shiftS ?? 0,
                "setupShiftT": setup?.tileState.shiftT ?? 0,
                "isolatedNonBlackPixels": isolatedNonBlackPixels,
                "isolatedRawSHA256": isolatedCapture.rawSHA256,
                "isolatedPNGPath": isolatedCapture.pngURL?.path ?? "",
                "contributedNonBlack": contributed,
                "intentionallyEmpty": intentionallyEmpty,
            ])
        }

        let allMaterialContributionsClosed = isolatedMaterialEvidence.count == 5 &&
            isolatedMaterialEvidence.allSatisfy {
                ($0["contributedNonBlack"] as? Bool == true) ||
                ($0["sourceBlackOrTransparentProof"] as? Bool == true)
            }

        let textEvidence = [
            "screen": "Legal",
            "frontFacing": "counterClockwise",
            "sourceTextEventCount": frame.text.sourceEvents.count,
            "sourceTextEventHash": frame.text.sourceEventHash,
            "glyphPacketHash": frame.text.glyphPacketHash,
            "glyphGeometryHash": twoDBatch.geometryHash,
            "glyphDrawCount": encoded2DBatch.draws.filter { $0.primitive == .glyph }.count,
            "threeDRawSHA256": threeDCapture.rawSHA256,
            "compositeRawSHA256": capture.rawSHA256,
            "faithfulHDWidth": hdWidth,
            "faithfulHDHeight": hdHeight,
            "faithfulHD3DRawSHA256": hd3DSHA256,
            "faithfulHDRawSHA256": hdSHA256,
            "faithfulHD3DPath": hd3DOutput.path,
            "faithfulHDPath": hdOutput.path,
            "faithfulHD3DPNGPath": hd3DPNGURL.path,
            "faithfulHDPNGPath": hdPNGURL.path,
            "faithfulHDGlyphDrawCount": encodedHD2DBatch.draws.filter { $0.primitive == .glyph }.count,
            "threeDPngPath": threeDPngURL.path,
            "compositePngPath": pngURL.path,
            "sourceTextOrder": frame.text.sourceEvents.map(\.textID),
            "sourceCommandCount": frame.sourceCommandCount,
            "rawGfxCount": rawGfxCount,
            "sourceTriangleSlotCount": frame.scene.sourceTriangleSlotCount,
            "textureCoordinateHash": textureCoordinateHash,
            "stateWordEvidence": frame.scene.stateWordEvidence.map {
                "state=\($0.stateIndex):h=0x\(String($0.otherModeH, radix: 16)):l=0x\(String($0.otherModeL, radix: 16)):c=0x\(String($0.combineW0, radix: 16))/0x\(String($0.combineW1, radix: 16))"
            },
            "sourceTextureHandles": frame.modelTextureHandles,
            "drawMaterialHandles": drawMaterialHandles,
            "drawTriangleCounts": drawTriangleCounts,
            "sourceVertexIDsByDraw": sourceVertexIDsByDraw,
            "expectedSourceVertexIDsByDraw": expectedSourceVertexIDsByDraw,
            "sourceVertexCoverageMatches": sourceVertexCoverageMatches,
            "decoderSourceVertexIDsByDraw": frame.scene.decoderDraws.map {
                [$0.source_vertex_a, $0.source_vertex_b, $0.source_vertex_c]
            },
            "decoderVertexSlotsByDraw": frame.scene.decoderDraws.map {
                [$0.vertex_slot_a, $0.vertex_slot_b, $0.vertex_slot_c]
            },
            "drawDiagnostics": drawDiagnostics,
            "isolatedMaterialEvidence": isolatedMaterialEvidence,
            "unsupportedVisibleCommands": frame.scene.unsupportedVisibleCount,
            "projectionConsumption": "\(frame.projectionConsumption.consumedDrawCount)/\(frame.projectionConsumption.requiredDrawCount)",
            "pixelParityClaimed": false,
            "sourceSemanticClosure": allMaterialContributionsClosed,
            "sourceCompleteVisualAcceptance": false,
        ] as [String: Any]
        let textJSON = try JSONSerialization.data(withJSONObject: textEvidence, options: [.sortedKeys])
        try textJSON.write(to: output.deletingPathExtension().appendingPathExtension("text.json"), options: .atomic)
        precondition(
            allMaterialContributionsClosed,
            "Legal source-semantic material closure requires every nonempty texture draw to contribute nonblack pixels"
        )

        twoDRenderer.shutdown()
        renderer.shutdown()
        try textureStore.shutdown()
        let metadataURL = output.appendingPathExtension("json")
        print("capture_3d_raw=\(threeDOutput.path)")
        print("capture_3d_png=\(threeDPngURL.path)")
        print("capture_composite_raw=\(output.path)")
        print("capture_composite_png=\(pngURL.path)")
        print("capture_composite_json=\(metadataURL.path)")
        print("goldeneye_legal_reference_capture_v6_smoke: PASS")
    }
}
