import Foundation
import CryptoKit
import Metal
import QuartzCore
import simd

@available(macOS 26.0, *)
@main
struct GoldenEyeNintendoReferenceCaptureV6Smoke {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4) else {
            print("goldeneye_nintendo_reference_capture_v6_smoke: SKIP (Metal 4 device unavailable)")
            return
        }

        let arguments = Array(CommandLine.arguments.dropFirst())
        let root = URL(
            fileURLWithPath: arguments.first ?? "build/native/source-frontend-v6",
            isDirectory: true
        )
        let sceneLibraryURL = URL(
            fileURLWithPath: arguments.dropFirst().first
                ?? "build/native/source-scene-renderer-v6/GoldenEyeSourceSceneV6.metallib"
        )
        guard FileManager.default.fileExists(atPath: sceneLibraryURL.path) else {
            print("goldeneye_nintendo_reference_capture_v6_smoke: SKIP (source-scene metallib unavailable)")
            return
        }
        let outputDirectory = URL(
            fileURLWithPath: arguments.dropFirst().dropFirst().first
                ?? "build/native/nintendo-reference-capture-v6",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let evenTick = UInt64(ProcessInfo.processInfo.environment["GE_NINTENDO_CAPTURE_TICK"] ?? "590") ?? 590
        precondition(evenTick > 0 && evenTick & 1 == 0, "Nintendo capture tick must be a positive even native tick")
        let even = try GoldenEyeNintendoFrameV6.build(rootURL: root, nativeTick: evenTick)
        let odd = try GoldenEyeNintendoFrameV6.build(rootURL: root, nativeTick: evenTick + 1)
        let nextEven = try GoldenEyeNintendoFrameV6.build(rootURL: root, nativeTick: evenTick + 2)
        try validatePairedCadence(even: even, odd: odd, nextEven: nextEven)

        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.drawableSize = CGSize(width: 640, height: 480)
        layer.framebufferOnly = false
        layer.maximumDrawableCount = 2
        layer.allowsNextDrawableTimeout = true
        layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        let state = try GoldenEyeMetalDeviceState(device: device, layer: layer)
        // The product layer remains framebuffer-only.  This capture-only
        // layer is made readable after state initialization so the supplied
        // CAMetalDrawable can be copied into a deterministic HD artifact.
        layer.framebufferOnly = false
        guard let uploadEvent = device.makeSharedEvent() else {
            throw NSError(domain: "NintendoCapture", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "texture upload shared event unavailable"
            ])
        }
        uploadEvent.label = "GoldenEye.Nintendo.Reference.TextureUpload"
        let textureStore = try GoldenEyeSourceTextureStoreV6(
            context: GoldenEyeSourceTextureStoreV6MetalContext(
                device: device,
                queue: state.queue,
                residency: state.sceneResidency,
                completionEvent: uploadEvent
            )
        )
        let preparation = try GoldenEyeSourceProductPreparationV6.load(rootURL: root)
        let models = preparation.models.keys.sorted().compactMap { name in
            preparation.models[name].map { (name: name, model: $0) }
        }
        _ = try textureStore.upload(
            plan: GoldenEyeSourceTextureUploadPlanV6.make(
                catalog: preparation.catalog,
                models: models
            )
        )
        try textureStore.drain()

        let pipeline = try GoldenEyeSourceScenePipelineV6(
            device: device,
            libraryURL: sceneLibraryURL,
            pixelFormat: .bgra8Unorm
        )
        let renderer = try GoldenEyeSourceSceneRendererV6(
            state: state,
            pipeline: pipeline,
            textureResolver: { handle in textureStore.texture(handle: handle) },
            outputMode: .reference320x240,
            frontFacing: .counterClockwise
        )

        guard let hdEvenDrawable = layer.nextDrawable() else {
            throw NSError(domain: "NintendoCapture", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Faithful HD even drawable unavailable"
            ])
        }
        let hdEvenTexture = hdEvenDrawable.texture
        let hdRenderer = try GoldenEyeSourceSceneRendererV6(
            state: state,
            pipeline: pipeline,
            textureResolver: { handle in textureStore.texture(handle: handle) },
            outputMode: .faithfulHD,
            frontFacing: .counterClockwise
        )
        let hdEvenEvidence = try hdRenderer.render(
            snapshot: even.scene.snapshot,
            suppliedDrawable: hdEvenDrawable
        )
        guard let hdOddDrawable = layer.nextDrawable() else {
            throw NSError(domain: "NintendoCapture", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Faithful HD odd drawable unavailable"
            ])
        }
        let hdOddTexture = hdOddDrawable.texture
        let hdOddEvidence = try hdRenderer.render(
            snapshot: odd.scene.snapshot,
            suppliedDrawable: hdOddDrawable
        )
        hdRenderer.shutdown()
        let hdEvenBytes = readHDTexture(hdEvenTexture)
        let hdOddBytes = readHDTexture(hdOddTexture)
        let hdEvenSHA256 = sha256(hdEvenBytes)
        let hdOddSHA256 = sha256(hdOddBytes)
        precondition(hdEvenEvidence.triangleCount == Int(GoldenEyeNintendoFrameV6.renderedTriangleCount))
        precondition(hdOddEvidence.triangleCount == Int(GoldenEyeNintendoFrameV6.renderedTriangleCount))
        precondition(hdEvenBytes.count == 640 * 480 * 4)
        precondition(hdOddBytes.count == 640 * 480 * 4)
        precondition(hdEvenSHA256 != hdOddSHA256)

        let hdEvenURL = outputDirectory.appendingPathComponent("nintendo-faithful-hd-even.raw")
        let hdOddURL = outputDirectory.appendingPathComponent("nintendo-faithful-hd-odd.raw")
        try hdEvenBytes.write(to: hdEvenURL, options: .atomic)
        try hdOddBytes.write(to: hdOddURL, options: .atomic)
        let hdEvenPNG = try GoldenEyeReferenceCaptureCodecV6.encodePNG(
            bgra8: hdEvenBytes,
            width: 640,
            height: 480,
            bytesPerRow: 640 * 4
        )
        let hdOddPNG = try GoldenEyeReferenceCaptureCodecV6.encodePNG(
            bgra8: hdOddBytes,
            width: 640,
            height: 480,
            bytesPerRow: 640 * 4
        )
        let hdEvenPNGURL = outputDirectory.appendingPathComponent("nintendo-faithful-hd-even.png")
        let hdOddPNGURL = outputDirectory.appendingPathComponent("nintendo-faithful-hd-odd.png")
        try hdEvenPNG.write(to: hdEvenPNGURL, options: .atomic)
        try hdOddPNG.write(to: hdOddPNGURL, options: .atomic)

        let evenURL = outputDirectory.appendingPathComponent("nintendo-320x240-even.raw")
        let oddURL = outputDirectory.appendingPathComponent("nintendo-320x240-odd.raw")
        let evenCapture = try renderer.captureReference320x240(
            snapshot: even.scene.snapshot,
            to: evenURL
        )
        let oddCapture = try renderer.captureReference320x240(
            snapshot: odd.scene.snapshot,
            to: oddURL
        )
        precondition(evenCapture.width == 320 && evenCapture.height == 240)
        precondition(oddCapture.width == 320 && oddCapture.height == 240)
        precondition(evenCapture.bytes.count == 320 * 240 * 4)
        precondition(oddCapture.bytes.count == 320 * 240 * 4)
        precondition(evenCapture.rawSHA256.count == 64)
        precondition(oddCapture.rawSHA256.count == 64)
        precondition(evenCapture.rawSHA256 != oddCapture.rawSHA256)
        precondition(evenCapture.evidence.triangleCount == Int(GoldenEyeNintendoFrameV6.renderedTriangleCount))
        precondition(oddCapture.evidence.triangleCount == Int(GoldenEyeNintendoFrameV6.renderedTriangleCount))

        // Keep a clockwise comparison beside the source-faithful +Y/CCW
        // baseline.  This is diagnostic evidence only; the static frontend
        // captures above use the canonical counter-clockwise winding.
        let windingRenderer = try GoldenEyeSourceSceneRendererV6(
            state: state,
            pipeline: pipeline,
            textureResolver: { handle in textureStore.texture(handle: handle) },
            outputMode: .reference320x240,
            frontFacing: .clockwise
        )
        let windingURL = outputDirectory.appendingPathComponent("nintendo-winding-clockwise.raw")
        let windingCapture = try windingRenderer.captureReference320x240(
            snapshot: even.scene.snapshot,
            to: windingURL
        )
        windingRenderer.shutdown()
        precondition(windingCapture.evidence.triangleCount == Int(GoldenEyeNintendoFrameV6.renderedTriangleCount))

        let perDrawCoverage = try capturePerDrawCoverage(
            snapshot: even.scene.snapshot,
            renderer: renderer,
            outputDirectory: outputDirectory
        )
        guard let textureResource = even.scene.snapshot.resources.first(where: {
            $0.resource_kind == UInt32(GE_SOURCE_RESOURCE_V6_TEXTURE)
        }) else {
            throw NSError(domain: "NintendoCapture", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "Nintendo texture resource missing from scene snapshot"
            ])
        }
        let boundTextureHandles = Set(even.scene.snapshot.drawCommands.map(\.resource_handle))
        precondition(boundTextureHandles == Set([textureResource.handle]))
        precondition(textureResource.format == UInt32(GE_SOURCE_RESOURCE_V6_FORMAT_I8))
        let stateEvidence = even.scene.snapshot.drawCommands.map { draw -> [String: Any] in
            let state = even.scene.snapshot.renderStates.first {
                $0.state_handle == draw.render_state_handle
            }
            let geometryMode = even.scene.snapshot.lightingFrameContext?.geometryModesByState[
                draw.render_state_handle
            ] ?? 0
            return [
                "drawHandle": draw.draw_handle,
                "renderStateHandle": draw.render_state_handle,
                "resourceHandle": draw.resource_handle,
                "geometryMode": geometryMode,
                "rawOtherModeH": state?.raw_othermode_h ?? 0,
                "rawOtherModeL": state?.raw_othermode_l ?? 0,
                "rawRenderMode": state?.raw_render_mode ?? 0,
                "combinerCycleCount": state?.combiner_cycle_count ?? 0,
                "cycle0Color": [state?.cycle0_color_a ?? 0, state?.cycle0_color_b ?? 0, state?.cycle0_color_c ?? 0, state?.cycle0_color_d ?? 0],
                "cycle0Alpha": [state?.cycle0_alpha_a ?? 0, state?.cycle0_alpha_b ?? 0, state?.cycle0_alpha_c ?? 0, state?.cycle0_alpha_d ?? 0],
                "cullMode": state?.cull_mode ?? 0,
                "filterMode": state?.filter_mode ?? 0,
                "wrapS": state?.wrap_s ?? 0,
                "wrapT": state?.wrap_t ?? 0,
            ]
        }

        let commandOrder = even.model.commands.enumerated().map { index, command in
            [
                "index": index,
                "displayListID": command.displayListID,
                "ordinal": command.ordinal,
                "semantic": command.semantic,
                "sourceHash": String(format: "%016llx", command.sourceHash),
            ] as [String: Any]
        }
        let metadata: [String: Any] = [
            "screen": "Nintendo",
            "sourceNodeCount": GoldenEyeNintendoFrameV6.sourceNodeCount,
            "sourceDisplayListCount": GoldenEyeNintendoFrameV6.sourceDisplayListCount,
            "sourceCommandCount": GoldenEyeNintendoFrameV6.sourceCommandCount,
            "sourceVertexCount": GoldenEyeNintendoFrameV6.sourceVertexCount,
            "sourceTriangleCount": GoldenEyeNintendoFrameV6.sourceTriangleCount,
            "sourceTextureCount": GoldenEyeNintendoFrameV6.sourceTextureCount,
            "renderedTriangleCount": GoldenEyeNintendoFrameV6.renderedTriangleCount,
            "suppressedDegenerateCount": GoldenEyeNintendoFrameV6.suppressedDegeneratePrimitives.count,
            "suppressedDegenerate": GoldenEyeNintendoFrameV6.suppressedDegeneratePrimitives.map {
                [
                    "sourceCommandIndex": $0.sourceCommandIndex,
                    "packetByteOffset": $0.packetByteOffset,
                    "sourceLine": $0.sourceLine,
                    "semantic": $0.semantic,
                    "visible": false,
                ] as [String: Any]
            },
            "textureWidth": even.model.textures[0].width,
            "textureHeight": even.model.textures[0].height,
            "textureDepth": even.model.textures[0].depth,
            "textureMipCount": even.model.textures[0].mipCount,
            "sourceOrderHash": String(format: "%016llx", GoldenEyeNintendoFrameV6.sourceOrderHash),
            "commandOrderCount": commandOrder.count,
            "commandOrder": commandOrder,
            "evenNativeTick": even.source.nativeTick,
            "oddNativeTick": odd.source.nativeTick,
            "evenSourceTimer": even.source.sourceTimer,
            "oddSourceTimer": odd.source.sourceTimer,
            "ambientQ16": GoldenEyeSourceSceneLightingProviderV6.nintendoAmbientQ16(
                sourceTimer: even.source.sourceTimer,
                pairPhase: 0
            ),
            "ambientClampedByte": GoldenEyeSourceSceneLightingProviderV6.nintendoAmbientQ16(
                sourceTimer: even.source.sourceTimer,
                pairPhase: 0
            ) / 65_536,
            "directionalColor": [0.0, 0.0, 0.0, 1.0],
            "reflectionRight": [1.0, 0.0, 0.0, 0.0],
            "reflectionUp": [0.0, 1.0, 0.0, 0.0],
            "evenFrameHash": String(format: "%016llx", even.frameHash),
            "oddFrameHash": String(format: "%016llx", odd.frameHash),
            "evenRawSHA256": evenCapture.rawSHA256,
            "oddRawSHA256": oddCapture.rawSHA256,
            "windingClockwiseRawSHA256": windingCapture.rawSHA256,
            "windingClockwisePNG": windingCapture.pngURL?.path ?? "",
            "productionFrontFacing": "counterClockwise",
            "debugWindingFrontFacing": "clockwise",
            "productionCullMode": "back",
            "evenPNG": evenCapture.pngURL?.path ?? "",
            "oddPNG": oddCapture.pngURL?.path ?? "",
            "hdWidth": 640,
            "hdHeight": 480,
            "hdEvenRawSHA256": hdEvenSHA256,
            "hdOddRawSHA256": hdOddSHA256,
            "hdEvenPNG": hdEvenPNGURL.path,
            "hdOddPNG": hdOddPNGURL.path,
            "packetCommandCount": even.scene.packetCommandCount,
            "packetListCount": even.scene.packetListCount,
            "packetVertexCount": even.scene.packetVertexCount,
            "packetImageCount": even.scene.packetImageCount,
            "textureResourceHandle": textureResource.handle,
            "textureResourceFormat": textureResource.format,
            "textureResourceWidth": textureResource.width,
            "textureResourceHeight": textureResource.height,
            "textureResourceMipLevels": textureResource.level_count,
            "boundTextureHandles": boundTextureHandles.sorted(),
            "stateEvidence": stateEvidence,
            "decoderDrawCount": even.scene.decoderDraws.count,
            "visibleNodeIDs": Array(0..<GoldenEyeNintendoFrameV6.sourceNodeCount),
            "displayListIDs": Array(0..<GoldenEyeNintendoFrameV6.sourceDisplayListCount),
            "perDrawCoverage": perDrawCoverage,
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys, .prettyPrinted])
        try metadataData.write(
            to: outputDirectory.appendingPathComponent("nintendo-reference.json"),
            options: .atomic
        )

        renderer.shutdown()
        try textureStore.shutdown()
        print("nintendo_even_png=\(evenCapture.pngURL?.path ?? "")")
        print("nintendo_odd_png=\(oddCapture.pngURL?.path ?? "")")
        print("nintendo_metadata=\(outputDirectory.appendingPathComponent("nintendo-reference.json").path)")
        print("goldeneye_nintendo_reference_capture_v6_smoke: PASS")
    }

    private static func capturePerDrawCoverage(
        snapshot: GoldenEyeSourceSceneSnapshotV6,
        renderer: GoldenEyeSourceSceneRendererV6,
        outputDirectory: URL
    ) throws -> [[String: Any]] {
        var values: [[String: Any]] = []
        for (index, draw) in snapshot.drawCommands.enumerated() {
            var summary = snapshot.summary
            summary.draw_count = 1
            summary.frame_hash &+= UInt64(index + 1)
            let subset = try GoldenEyeSourceSceneSnapshotV6(
                summary: summary,
                resources: snapshot.resources,
                transforms: snapshot.transforms,
                animationPoses: snapshot.animationPoses,
                vertices: snapshot.vertices,
                indices: snapshot.indices,
                renderStates: snapshot.renderStates,
                drawCommands: [draw],
                textEvents: snapshot.textEvents,
                audioEvents: snapshot.audioEvents,
                diagnostics: snapshot.diagnostics,
                lightingFrameContext: snapshot.lightingFrameContext
            )
            let url = outputDirectory.appendingPathComponent("nintendo-draw-\(index).raw")
            let capture = try renderer.captureReference320x240(snapshot: subset, to: url)
            var nonBlack = 0
            var minX = 320
            var minY = 240
            var maxX = -1
            var maxY = -1
            let transform = snapshot.transforms.first {
                $0.handle == draw.transform_handle
            }.map(matrix(from:))
            let clipBounds = transform.map {
                clipBounds(for: draw, snapshot: snapshot, transform: $0)
            } ?? []
            let winding = transform.map {
                windingMetrics(for: draw, snapshot: snapshot, transform: $0)
            } ?? [:]
            for pixel in 0..<(320 * 240) {
                let offset = pixel * 4
                guard capture.bytes[offset] != 0 || capture.bytes[offset + 1] != 0 || capture.bytes[offset + 2] != 0 else {
                    continue
                }
                nonBlack += 1
                let x = pixel % 320
                let y = pixel / 320
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
            values.append([
                "drawIndex": index,
                "drawHandle": draw.draw_handle,
                "resourceHandle": draw.resource_handle,
                "renderStateHandle": draw.render_state_handle,
                "triangleCount": draw.index_count,
                "nonBlackPixelCount": nonBlack,
                "bbox": [minX, minY, maxX, maxY],
                "clipBounds": clipBounds,
                "frontClockwiseCount": winding["frontClockwiseCount"] ?? 0,
                "backCounterClockwiseCount": winding["backCounterClockwiseCount"] ?? 0,
                "degenerateCount": winding["degenerateCount"] ?? 0,
                "projectedCentroidXMin": winding["projectedCentroidXMin"] ?? 0,
                "projectedCentroidXMax": winding["projectedCentroidXMax"] ?? 0,
                "sourceCentroidXMin": winding["sourceCentroidXMin"] ?? 0,
                "sourceCentroidXMax": winding["sourceCentroidXMax"] ?? 0,
                "projectedSourceOrderCorrelation": winding["projectedSourceOrderCorrelation"] ?? 0,
                "rawSHA256": capture.rawSHA256,
            ])
        }
        return values
    }

    private static func matrix(from source: GESourceTransformV6) -> simd_float4x4 {
        var copy = source.matrix_q16
        let values = withUnsafeBytes(of: &copy) { raw in
            Array(raw.bindMemory(to: Int32.self).prefix(16))
        }
        func column(_ index: Int) -> SIMD4<Float> {
            let base = index * 4
            return SIMD4<Float>(
                Float(values[base]) / 65_536.0,
                Float(values[base + 1]) / 65_536.0,
                Float(values[base + 2]) / 65_536.0,
                Float(values[base + 3]) / 65_536.0
            )
        }
        let columns = [column(0), column(1), column(2), column(3)]
        return simd_float4x4(columns[0], columns[1], columns[2], columns[3])
    }

    private static func clipBounds(
        for draw: GESourceDrawCommandV6,
        snapshot: GoldenEyeSourceSceneSnapshotV6,
        transform: simd_float4x4
    ) -> [Float] {
        let start = Int(draw.first_vertex)
        let end = min(snapshot.gpuVertices.count, start + Int(draw.vertex_count))
        guard start < end else { return [] }
        var values: [(Float, Float, Float, Float)] = []
        for vertex in snapshot.gpuVertices[start..<end] {
            let clip = transform * vertex.position
            values.append((clip.x, clip.y, clip.z, clip.w))
        }
        guard !values.isEmpty else { return [] }
        let ndc = values.compactMap { x, y, z, w -> SIMD3<Float>? in
            guard abs(w) > 0.000001 else { return nil }
            return SIMD3(x / w, y / w, z / w)
        }
        guard !ndc.isEmpty else { return [] }
        return [
            ndc.map(\.x).min()!, ndc.map(\.y).min()!, ndc.map(\.z).min()!,
            ndc.map(\.x).max()!, ndc.map(\.y).max()!, ndc.map(\.z).max()!,
        ]
    }

    private static func windingMetrics(
        for draw: GESourceDrawCommandV6,
        snapshot: GoldenEyeSourceSceneSnapshotV6,
        transform: simd_float4x4
    ) -> [String: Any] {
        var frontClockwise = 0
        var backCounterClockwise = 0
        var degenerate = 0
        var projectedX: [Float] = []
        var sourceX: [Float] = []
        let firstIndex = Int(draw.first_index)
        let indexEnd = min(snapshot.gpuIndices.count, firstIndex + Int(draw.index_count))
        for index in firstIndex..<indexEnd {
            let indices = snapshot.gpuIndices[index]
            let positions = [indices.vertex0, indices.vertex1, indices.vertex2].compactMap { vertexIndex -> SIMD3<Float>? in
                guard Int(vertexIndex) < snapshot.gpuVertices.count else { return nil }
                let vertex = snapshot.gpuVertices[Int(vertexIndex)].position
                let clip = transform * vertex
                guard abs(clip.w) > 0.000001 else { return nil }
                return SIMD3(clip.x / clip.w, clip.y / clip.w, clip.z / clip.w)
            }
            guard positions.count == 3 else { continue }
            let a = positions[0]
            let b = positions[1]
            let c = positions[2]
            let area = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
            if abs(area) < 0.000001 {
                degenerate += 1
            } else if area < 0 {
                frontClockwise += 1
            } else {
                backCounterClockwise += 1
            }
            projectedX.append((a.x + b.x + c.x) / 3)
            let sourcePositionX = [indices.vertex0, indices.vertex1, indices.vertex2].compactMap { vertexIndex -> Float? in
                guard Int(vertexIndex) < snapshot.gpuVertices.count else { return nil }
                return snapshot.gpuVertices[Int(vertexIndex)].position.x
            }
            if sourcePositionX.count == 3 {
                sourceX.append(sourcePositionX.reduce(0, +) / 3)
            }
        }
        let orderCorrelation: Float
        if projectedX.count == sourceX.count, projectedX.count > 1 {
            let projectedMean = projectedX.reduce(0, +) / Float(projectedX.count)
            let sourceMean = sourceX.reduce(0, +) / Float(sourceX.count)
            let covariance = zip(projectedX, sourceX).reduce(Float(0)) {
                $0 + ($1.0 - projectedMean) * ($1.1 - sourceMean)
            }
            let projectedVariance = projectedX.reduce(Float(0)) { $0 + ($1 - projectedMean) * ($1 - projectedMean) }
            let sourceVariance = sourceX.reduce(Float(0)) { $0 + ($1 - sourceMean) * ($1 - sourceMean) }
            orderCorrelation = covariance / max(sqrt(projectedVariance * sourceVariance), 0.000001)
        } else {
            orderCorrelation = 0
        }
        return [
            "frontClockwiseCount": frontClockwise,
            "backCounterClockwiseCount": backCounterClockwise,
            "degenerateCount": degenerate,
            "projectedCentroidXMin": projectedX.min() ?? 0,
            "projectedCentroidXMax": projectedX.max() ?? 0,
            "sourceCentroidXMin": sourceX.min() ?? 0,
            "sourceCentroidXMax": sourceX.max() ?? 0,
            "projectedSourceOrderCorrelation": orderCorrelation,
        ]
    }

    private static func readHDTexture(_ texture: any MTLTexture) -> Data {
        var bytes = Data(repeating: 0, count: 640 * 480 * 4)
        bytes.withUnsafeMutableBytes { rawBytes in
            texture.getBytes(
                rawBytes.baseAddress!,
                bytesPerRow: 640 * 4,
                from: MTLRegionMake2D(0, 0, 640, 480),
                mipmapLevel: 0
            )
        }
        return bytes
    }

    private static func sha256(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private static func validatePairedCadence(
        even: GoldenEyeNintendoFrameV6,
        odd: GoldenEyeNintendoFrameV6,
        nextEven: GoldenEyeNintendoFrameV6
    ) throws {
        guard even.source.nativeTick & 1 == 0,
              odd.source.nativeTick & 1 == 1,
              nextEven.source.nativeTick & 1 == 0,
              odd.source.referenceTick == even.source.referenceTick,
              nextEven.source.referenceTick == even.source.referenceTick + 1,
              odd.source.sourceTimer == even.source.sourceTimer,
              nextEven.source.sourceTimer == even.source.sourceTimer + 1,
              even.source.sourceTimer < nextEven.source.sourceTimer,
              even.frameHash != odd.frameHash,
              odd.frameHash != nextEven.frameHash,
              even.matrixFrame.matrixHash != odd.matrixFrame.matrixHash,
              odd.matrixFrame.matrixHash != nextEven.matrixFrame.matrixHash else {
            throw GoldenEyeNintendoFrameV6.Error.invalidCadence(
                "even=\(even.source.nativeTick)/\(even.source.sourceTimer) odd=\(odd.source.nativeTick)/\(odd.source.sourceTimer) next=\(nextEven.source.nativeTick)/\(nextEven.source.sourceTimer)"
            )
        }
        let evenValues = even.matrixFrame.modelMatrixQ16
        let oddValues = odd.matrixFrame.modelMatrixQ16
        let nextValues = nextEven.matrixFrame.modelMatrixQ16
        for index in 0..<16 {
            let lower = min(evenValues[index], nextValues[index])
            let upper = max(evenValues[index], nextValues[index])
            guard oddValues[index] >= lower, oddValues[index] <= upper else {
                throw GoldenEyeNintendoFrameV6.Error.invalidCadence(
                    "odd model matrix field \(index) is outside paired anchors"
                )
            }
        }
    }
}
