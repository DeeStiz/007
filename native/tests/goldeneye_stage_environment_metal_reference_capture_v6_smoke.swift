import Foundation
import Metal
import QuartzCore

@available(macOS 27.0, *)
@main
struct GoldenEyeStageEnvironmentMetalReferenceCaptureV6Smoke {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4) else {
            print("goldeneye_stage_environment_metal_reference_capture_v6_smoke: SKIP (Metal 4 device unavailable)")
            return
        }
        let arguments = Array(CommandLine.arguments.dropFirst())
        let root = URL(fileURLWithPath: arguments.first ?? "build/native/stage-assets-image-decoder-v6", isDirectory: true)
        let libraryURL = URL(fileURLWithPath: arguments.dropFirst().first
            ?? "build/native/source-scene-renderer-v6/GoldenEyeSourceSceneV6.metallib")
        let output = URL(fileURLWithPath: arguments.dropFirst().dropFirst().first
            ?? "build/native/stage-environment-metal-reference-capture-v6", isDirectory: true)
        let stageID = UInt32(arguments.dropFirst().dropFirst().dropFirst().first ?? "33") ?? 33
        guard FileManager.default.fileExists(atPath: libraryURL.path) else {
            print("goldeneye_stage_environment_metal_reference_capture_v6_smoke: SKIP (source-scene metallib unavailable)")
            return
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let catalog = try GoldenEyeStageAssetCatalog.load(stageAssetRoot: root)
        let scene = try GoldenEyeStageScenePacket.load(stageID: stageID, catalog: catalog)
        let material = try GoldenEyeStageSourceMaterialLowererV6.make(scene: scene)
        let stageTextures = try GoldenEyeStageTextureCatalogV6.load(stageAssetRoot: root)
        let viewport = try requireViewport()
        let projection = try requireCaptureProjection(viewport: viewport)
        let environment = try GoldenEyeStageSourceEnvironmentDrawPacketBuilderV6.make(
            scene: scene,
            viewport: viewport,
            projection: projection,
            environmentOnlyCapture: true
        )
        let snapshot = try GoldenEyeStageSourceSceneSnapshotAdapterV6.make(
            packet: environment,
            nativeTick: 2,
            materialPacket: material,
            stageTextureCatalog: stageTextures
        )
        precondition(environment.commands.allSatisfy { $0.primitive == .roomTriangle })
        precondition(environment.unsupportedMask == 0)
        precondition(material.unsupportedCommandCount == 0)
        precondition(snapshot.summary.resource_count > 0)
        precondition(snapshot.summary.draw_count < snapshot.summary.index_count)

        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.isOpaque = true
        layer.framebufferOnly = false
        layer.displaySyncEnabled = false
        layer.drawableSize = CGSize(width: 320, height: 240)
        layer.frame = CGRect(x: 0, y: 0, width: 320, height: 240)
        let state = try GoldenEyeMetalDeviceState(device: device, layer: layer)
        guard let uploadEvent = device.makeSharedEvent() else {
            throw CaptureError("stage texture upload shared event unavailable")
        }
        uploadEvent.label = "GoldenEye.Stage.Environment.TextureUpload"
        let store = try GoldenEyeSourceTextureStoreV6(
            context: GoldenEyeSourceTextureStoreV6MetalContext(
                device: device,
                queue: state.queue,
                residency: state.sceneResidency,
                completionEvent: uploadEvent
            )
        )
        let plan = try GoldenEyeSourceTextureUploadPlanV6.make(
            descriptors: stageTextures.uploadDescriptors()
        )
        _ = try store.upload(plan: plan)
        try store.drain()
        let bindingAdapter = try GoldenEyeSourceSceneTextureBindingAdapterV6(
            store: store,
            plan: plan
        )
        let pipeline = try GoldenEyeSourceScenePipelineV6(
            device: device,
            libraryURL: libraryURL,
            pixelFormat: .bgra8Unorm
        )
        let renderer = try GoldenEyeSourceSceneRendererV6(
            state: state,
            pipeline: pipeline,
            textureResolver: { handle in store.texture(handle: handle) },
            textureBindingAdapter: bindingAdapter,
            maxVertexCount: 100_000,
            maxIndexCount: 100_000,
            maxDrawCount: 4_096,
            outputMode: .reference320x240,
            frontFacing: .counterClockwise
        )
        let capturePrefix: String
        if scene.stageID == 33 {
            capturePrefix = "dam-room-environment"
        } else {
            let safeName = scene.stageName.lowercased()
                .replacingOccurrences(of: " ", with: "-")
            capturePrefix = "stage-\(scene.stageID)-\(safeName)-environment"
        }
        let rawURL = output.appendingPathComponent("\(capturePrefix)-320x240.raw")
        let capture = try renderer.captureReference320x240(snapshot: snapshot, to: rawURL)
        renderer.shutdown()
        precondition(capture.width == 320 && capture.height == 240)
        precondition(capture.evidence.triangleCount == environment.commands.count)
        precondition(capture.evidence.drawCount == snapshot.drawCommands.count)
        let nonBlackRGB = hasNonBlackRGB(capture.bytes)
        let texturedColor = hasTexturedColor(capture.bytes)

        let pngURL = output.appendingPathComponent("\(capturePrefix)-320x240.png")
        try GoldenEyeReferenceCaptureCodecV6.encodePNG(
            bgra8: capture.bytes,
            width: capture.width,
            height: capture.height,
            bytesPerRow: capture.bytesPerRow
        ).write(to: pngURL, options: .atomic)
        let metadata: [String: Any] = [
            "stage": scene.stageName,
            "stageID": scene.stageID,
            "sourceTriangles": environment.commands.count,
            "sourceVertices": environment.vertices.count,
            "metalDraws": snapshot.drawCommands.count,
            "resourceCount": snapshot.resources.count,
            "materialStates": material.states.count,
            "unsupportedMask": environment.unsupportedMask,
            "unsupportedMaterialCommands": material.unsupportedCommandCount,
            "nonBlackRGB": nonBlackRGB,
            "texturedColor": texturedColor,
            "packetHash": String(environment.packetHash),
            "rawSHA256": capture.rawSHA256,
            "png": pngURL.path,
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys, .prettyPrinted])
        try metadataData.write(
            to: output.appendingPathComponent("\(capturePrefix)-reference.json"),
            options: .atomic
        )
        print(
            "goldeneye_stage_environment_metal_reference_capture_v6_smoke: PASS " +
            "stage=\(scene.stageID) sourceTriangles=\(environment.commands.count) " +
            "metalDraws=\(snapshot.drawCommands.count) resources=\(snapshot.resources.count) " +
            "nonBlack=\(nonBlackRGB ? 1 : 0) textured=\(texturedColor ? 1 : 0) " +
            "rawSHA256=\(capture.rawSHA256)"
        )
    }

    private static func requireViewport() throws -> GoldenEyeProjectionV10.ViewportV10 {
        guard let viewport = GoldenEyeProjectionV10.ViewportV10(
            drawableWidth: GoldenEyeProjectionV10.canonicalWidth,
            drawableHeight: GoldenEyeProjectionV10.canonicalHeight
        ) else { throw CaptureError("canonical viewport unavailable") }
        return viewport
    }

    private static func requireCaptureProjection(
        viewport: GoldenEyeProjectionV10.ViewportV10
    ) throws -> GoldenEyeProjectionV10.PacketV10 {
        // The capture intentionally uses an explicit bounded source-space
        // orthographic scale so all copied Dam rooms can be inspected in one
        // compositor-independent frame. Runtime camera authority remains in
        // the stage owner; this is not a gameplay camera fallback.
        var values = SIMD16<Int32>(repeating: 0)
        let scaleXY: Int32 = 8
        let scaleZ: Int32 = 2
        values[0] = scaleXY
        values[5] = scaleXY
        values[10] = scaleZ
        // Metal's post-divide depth range is [0, 1]; the source room-space
        // inspection points may straddle negative Z, so translate the
        // bounded structural capture into that range. Runtime camera
        // authority supplies its own source projection later.
        values[11] = 32_768
        values[15] = Int32(GoldenEyeProjectionV10.q16One)
        let projection = GoldenEyeProjectionV10.MatrixQ16(values: values)
        guard let packet = GoldenEyeProjectionV10.PacketV10(
            viewport: viewport,
            modelView: .identity,
            projection: projection,
            cullMode: GoldenEyeProjectionV10.cullNone
        ) else { throw CaptureError("capture projection rejected") }
        return packet
    }

    private static func hasNonBlackRGB(_ data: Data) -> Bool {
        stride(from: 0, to: data.count, by: 4).contains { index in
            data[index] != 0 || data[index + 1] != 0 || data[index + 2] != 0
        }
    }

    private static func hasTexturedColor(_ data: Data) -> Bool {
        var distinct: Set<UInt32> = []
        for index in stride(from: 0, to: data.count, by: 4) {
            let word = UInt32(data[index]) |
                UInt32(data[index + 1]) << 8 |
                UInt32(data[index + 2]) << 16
            distinct.insert(word)
            if distinct.count >= 8 { return true }
        }
        return false
    }

    private struct CaptureError: Error, CustomStringConvertible {
        let message: String
        init(_ message: String) { self.message = message }
        var description: String { message }
    }
}
