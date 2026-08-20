import Foundation
import Metal
import QuartzCore
import CryptoKit

@available(macOS 27.0, *)
@main
struct GoldenEyeGoldenEyeLogoReferenceCaptureV6Smoke {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4) else {
            print("goldeneye_goldeneye_logo_reference_capture_v6_smoke: SKIP (Metal 4 device unavailable)")
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
        let outputDirectory = URL(
            fileURLWithPath: arguments.dropFirst().dropFirst().first
                ?? "build/native/goldeneye-logo-reference-capture-v6",
            isDirectory: true
        )
        guard FileManager.default.fileExists(atPath: sceneLibraryURL.path) else {
            print("goldeneye_goldeneye_logo_reference_capture_v6_smoke: SKIP (source-scene metallib unavailable)")
            return
        }
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let odd = try GoldenEyeGoldenEyeLogoFrameV6.build(
            rootURL: root,
            nativeTick: GoldenEyeGoldenEyeLogoFrameV6.routeGoldenEyeNativeTick + 1
        )
        let even = try GoldenEyeGoldenEyeLogoFrameV6.build(
            rootURL: root,
            nativeTick: GoldenEyeGoldenEyeLogoFrameV6.routeGoldenEyeNativeTick + 2
        )
        precondition(odd.scene.snapshot.summary.unsupported_visible_count == 0)
        precondition(even.scene.snapshot.summary.unsupported_visible_count == 0)
        precondition(odd.scene.triangleCount == GoldenEyeGoldenEyeLogoFrameV6.sourceTriangleCount)
        precondition(even.scene.triangleCount == GoldenEyeGoldenEyeLogoFrameV6.sourceTriangleCount)

        let preparation = try GoldenEyeSourceProductPreparationV6.load(rootURL: root)
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
        uploadEvent.label = "GoldenEye.GoldenEye.Reference.TextureUpload"
        let textureStore = try GoldenEyeSourceTextureStoreV6(
            context: GoldenEyeSourceTextureStoreV6MetalContext(
                device: device,
                queue: state.queue,
                residency: state.sceneResidency,
                completionEvent: uploadEvent
            )
        )
        let model = try preparation.model(named: GoldenEyeGoldenEyeLogoFrameV6.modelName)
        let texturePlan = try GoldenEyeSourceTextureUploadPlanV6.make(
            catalog: preparation.catalog,
            models: [(name: GoldenEyeGoldenEyeLogoFrameV6.modelName, model: model)]
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
        let referenceRenderer = try GoldenEyeSourceSceneRendererV6(
            state: state,
            pipeline: pipeline,
            textureResolver: { handle in textureStore.texture(handle: handle) },
            textureBindingAdapter: textureBindingAdapter,
            outputMode: .reference320x240,
            frontFacing: .counterClockwise
        )
        let oddReferenceURL = outputDirectory.appendingPathComponent("goldeneye-320x240-odd.raw")
        let evenReferenceURL = outputDirectory.appendingPathComponent("goldeneye-320x240-even.raw")
        let oddReference = try referenceRenderer.captureReference320x240(
            snapshot: odd.scene.snapshot,
            to: oddReferenceURL
        )
        let evenReference = try referenceRenderer.captureReference320x240(
            snapshot: even.scene.snapshot,
            to: evenReferenceURL
        )
        precondition(oddReference.width == 320 && oddReference.height == 240)
        precondition(evenReference.width == 320 && evenReference.height == 240)
        precondition(oddReference.evidence.triangleCount == Int(GoldenEyeGoldenEyeLogoFrameV6.sourceTriangleCount))
        precondition(evenReference.evidence.triangleCount == Int(GoldenEyeGoldenEyeLogoFrameV6.sourceTriangleCount))
        // The GoldenEye logo model/camera is source-static across this pair;
        // authority hashes and ticks differ, while rendered pixels may
        // legitimately remain identical.
        precondition(hasNonBlackRGB(oddReference.bytes))
        precondition(hasNonBlackRGB(evenReference.bytes))
        precondition(hasGoldRGB(oddReference.bytes))
        precondition(hasRedRGB(oddReference.bytes))
        precondition(hasGoldRGB(evenReference.bytes))
        precondition(hasRedRGB(evenReference.bytes))
        referenceRenderer.shutdown()

        // Faithful HD uses the exact same supplied-drawable path as the
        // product. The harness owns drawable acquisition; the product
        // renderer receives it and never calls nextDrawable itself.
        let hdWidth = 1_280
        let hdHeight = 960
        // The product keeps its presentation layer framebuffer-only. The
        // capture harness explicitly disables that optimization only after
        // the supplied drawable is rendered so it can copy the HD evidence
        // back for a lossless PNG; no production path uses this readback.
        layer.framebufferOnly = false
        layer.drawableSize = CGSize(width: hdWidth, height: hdHeight)
        layer.frame = CGRect(x: 0, y: 0, width: hdWidth, height: hdHeight)
        guard let drawable = layer.nextDrawable() else {
            throw CaptureError("Faithful HD supplied drawable unavailable")
        }
        let hdRenderer = try GoldenEyeSourceSceneRendererV6(
            state: state,
            pipeline: pipeline,
            textureResolver: { handle in textureStore.texture(handle: handle) },
            textureBindingAdapter: textureBindingAdapter,
            outputMode: .faithfulHD,
            frontFacing: .counterClockwise
        )
        let hdEvidence = try hdRenderer.render(
            snapshot: even.scene.snapshot,
            suppliedDrawable: drawable
        )
        hdRenderer.shutdown()
        let hdBytes = try readback(
            texture: drawable.texture,
            width: hdWidth,
            height: hdHeight
        )
        let hdRawURL = outputDirectory.appendingPathComponent("goldeneye-faithful-hd.raw")
        let hdPNGURL = outputDirectory.appendingPathComponent("goldeneye-faithful-hd.png")
        try hdBytes.write(to: hdRawURL, options: .atomic)
        try GoldenEyeReferenceCaptureCodecV6.encodePNG(
            bgra8: hdBytes,
            width: hdWidth,
            height: hdHeight,
            bytesPerRow: hdWidth * 4
        ).write(to: hdPNGURL, options: .atomic)
        precondition(hdEvidence.triangleCount == Int(GoldenEyeGoldenEyeLogoFrameV6.sourceTriangleCount))
        precondition(hasNonBlackRGB(hdBytes))
        precondition(hasGoldRGB(hdBytes))
        precondition(hasRedRGB(hdBytes))

        let metadata: [String: Any] = [
            "screen": "GoldenEye",
            "frontFacing": "counterClockwise",
            "sourceNodeCount": GoldenEyeGoldenEyeLogoFrameV6.sourceNodeCount,
            "sourceDisplayListCount": GoldenEyeGoldenEyeLogoFrameV6.sourceDisplayListCount,
            "sourceCommandCount": GoldenEyeGoldenEyeLogoFrameV6.sourceCommandCount,
            "sourceVertexCount": GoldenEyeGoldenEyeLogoFrameV6.sourceVertexCount,
            "sourceTriangleCount": GoldenEyeGoldenEyeLogoFrameV6.sourceTriangleCount,
            "sourceTriangleSlotCount": GoldenEyeGoldenEyeLogoFrameV6.sourceTriangleSlotCount,
            "sourceTextureCount": GoldenEyeGoldenEyeLogoFrameV6.sourceTextureCount,
            "sourceMipCount": GoldenEyeGoldenEyeLogoFrameV6.sourceMipCount,
            "sourceTLUTCount": GoldenEyeGoldenEyeLogoFrameV6.sourceTLUTCount,
            "sourceOrderHash": String(format: "%016llx", GoldenEyeGoldenEyeLogoFrameV6.sourceOrderHash),
            "packetCommandCount": even.scene.packetCommandCount,
            "packetListCount": even.scene.packetListCount,
            "packetVertexCount": even.scene.packetVertexCount,
            "packetImageCount": even.scene.packetImageCount,
            "decoderDrawCount": even.scene.decoderDraws.count,
            "stateCount": even.scene.decoderStateCount,
            "drawCount": even.scene.snapshot.drawCommands.count,
            "materialTextureHandles": even.materialTextureHandles,
            "textureSetupCount": even.textureSetups.count,
            "textureSetupResources": Array(Set(even.textureSetups.map(\.resourceHandle))).sorted(),
            "omittedDegenerateTriangles": even.omittedDegenerateTriangles.map {
                [
                    "sourceCommandIndex": $0.sourceCommandIndex,
                    "packetByteOffset": $0.packetByteOffset,
                    "tupleIndex": $0.tupleIndex,
                    "sourceVertexIndices": [$0.sourceVertexA, $0.sourceVertexB, $0.sourceVertexC],
                    "reason": $0.reason,
                ] as [String: Any]
            },
            "oddNativeTick": odd.source.nativeTick,
            "evenNativeTick": even.source.nativeTick,
            "oddSourceTimer": odd.source.sourceTimer,
            "evenSourceTimer": even.source.sourceTimer,
            "oddReferenceRawSHA256": oddReference.rawSHA256,
            "evenReferenceRawSHA256": evenReference.rawSHA256,
            "faithfulHDWidth": hdWidth,
            "faithfulHDHeight": hdHeight,
            "faithfulHDRawSHA256": sha256(hdBytes),
            "oddPNG": oddReference.pngURL?.path ?? "",
            "evenPNG": evenReference.pngURL?.path ?? "",
            "faithfulHDPNG": hdPNGURL.path,
            "projectionConsumptionComplete": even.scene.projectionConsumption.isComplete,
            "unsupportedVisibleCount": even.scene.unsupportedVisibleCount,
            "hasGoldPixels": hasGoldRGB(evenReference.bytes),
            "hasRedPixels": hasRedRGB(evenReference.bytes),
            "hasGoldPixelsHD": hasGoldRGB(hdBytes),
            "hasRedPixelsHD": hasRedRGB(hdBytes),
            "sourceModelHash": even.model.header.packetHash.map { String(format: "%02x", $0) }.joined(),
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys, .prettyPrinted])
        let metadataURL = outputDirectory.appendingPathComponent("goldeneye-reference.json")
        try metadataData.write(to: metadataURL, options: .atomic)

        try textureStore.shutdown()
        state.stopCapture()
        print("goldeneye_320x240_odd_png=\(oddReference.pngURL?.path ?? "")")
        print("goldeneye_320x240_even_png=\(evenReference.pngURL?.path ?? "")")
        print("goldeneye_faithful_hd_png=\(hdPNGURL.path)")
        print("goldeneye_reference_metadata=\(metadataURL.path)")
        print("goldeneye_goldeneye_logo_reference_capture_v6_smoke: PASS")
    }

    private static func hasNonBlackRGB(_ bytes: Data) -> Bool {
        stride(from: 0, to: bytes.count, by: 4).contains { offset in
            bytes[offset] != 0 || bytes[offset + 1] != 0 || bytes[offset + 2] != 0
        }
    }

    private static func hasGoldRGB(_ bytes: Data) -> Bool {
        stride(from: 0, to: bytes.count, by: 4).contains { offset in
            let blue = bytes[offset]
            let green = bytes[offset + 1]
            let red = bytes[offset + 2]
            return red > 150 && green > 80 && blue < 100
        }
    }

    private static func hasRedRGB(_ bytes: Data) -> Bool {
        stride(from: 0, to: bytes.count, by: 4).contains { offset in
            let blue = bytes[offset]
            let green = bytes[offset + 1]
            let red = bytes[offset + 2]
            return red > 150 && green < 90 && blue < 90
        }
    }

    private static func readback(
        texture: any MTLTexture,
        width: Int,
        height: Int
    ) throws -> Data {
        guard texture.width == width, texture.height == height else {
            throw CaptureError("drawable dimensions (texture.width)x(texture.height) != (width)x(height)")
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

private struct CaptureError: Error, CustomStringConvertible {
    let detail: String

    init(_ detail: String) { self.detail = detail }
    var description: String { "GoldenEye capture failed: \(detail)" }
}

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
