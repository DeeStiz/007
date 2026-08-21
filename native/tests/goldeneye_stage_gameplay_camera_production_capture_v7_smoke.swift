import CryptoKit
import Foundation
import Metal
import QuartzCore

@available(macOS 27.0, *)
@main
struct GoldenEyeStageGameplayCameraProductionCaptureV7Smoke {
    private static let stageIDs: [UInt32] = [33, 34]
    private static let staticPropTypes: Set<UInt32> = [
        1, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 17, 20, 21, 36, 39, 40,
        41, 42, 43, 45, 47,
    ]

    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count >= 3 else {
            throw CaptureError(
                "usage: goldeneye_stage_gameplay_camera_production_capture_v7_smoke "
                    + "/absolute/stage-root /absolute/visible-root /absolute/metallib [output]"
            )
        }
        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4) else {
            print(
                "goldeneye_stage_gameplay_camera_production_capture_v7_smoke: "
                    + "SKIP (Metal 4 device unavailable)"
            )
            return
        }

        let stageRoot = URL(fileURLWithPath: arguments[0], isDirectory: true)
        let visibleRoot = URL(fileURLWithPath: arguments[1], isDirectory: true)
        let libraryURL = URL(fileURLWithPath: arguments[2])
        let outputRoot = URL(
            fileURLWithPath: arguments.count >= 4
                ? arguments[3]
                : "build/native/stage-gameplay-camera-production-capture-v7",
            isDirectory: true
        )
        guard FileManager.default.fileExists(atPath: libraryURL.path) else {
            print(
                "goldeneye_stage_gameplay_camera_production_capture_v7_smoke: "
                    + "SKIP (source-scene metallib unavailable)"
            )
            return
        }
        try FileManager.default.createDirectory(
            at: outputRoot,
            withIntermediateDirectories: true
        )

        let catalog = try GoldenEyeStageAssetCatalog.load(stageAssetRoot: stageRoot)
        let scenes = try GoldenEyeStageScenePacket.loadAll(catalog: catalog)
        let textures = try GoldenEyeStageTextureCatalogV6.load(stageAssetRoot: stageRoot)
        let sidecars = try GoldenEyeStageModelSidecarCatalogV6.load(stageAssetRoot: stageRoot)
        let setupDependencies = try GoldenEyeStageSetupDependencyCatalogV6.load(
            stageAssetRoot: stageRoot
        )
        let visible = try GoldenEyeRamRomVisibleDependencyCatalogV6.load(rootURL: visibleRoot)

        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.isOpaque = true
        layer.framebufferOnly = false
        layer.displaySyncEnabled = false
        layer.maximumDrawableCount = 2
        layer.allowsNextDrawableTimeout = true
        layer.drawableSize = CGSize(width: 640, height: 480)
        layer.frame = CGRect(x: 0, y: 0, width: 640, height: 480)

        let state = try GoldenEyeMetalDeviceState(device: device, layer: layer)
        guard let uploadEvent = device.makeSharedEvent() else {
            throw CaptureError("stage texture upload shared event unavailable")
        }
        uploadEvent.label = "GoldenEye.Stage.GameplayCamera.Production.TextureUpload"
        let store = try GoldenEyeSourceTextureStoreV6(
            context: GoldenEyeSourceTextureStoreV6MetalContext(
                device: device,
                queue: state.queue,
                residency: state.sceneResidency,
                completionEvent: uploadEvent
            )
        )
        let plan = try GoldenEyeSourceTextureUploadPlanV6.make(
            descriptors: textures.uploadDescriptors()
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
            outputMode: .faithfulHD,
            frontFacing: .counterClockwise
        )

        var packetHashes: [UInt64] = []
        var compositionHashes: [UInt64] = []
        var renderHashes: [String] = []
        for stageID in stageIDs {
            guard let scene = scenes.first(where: { $0.stageID == stageID }),
                  let room = scene.rooms.first else {
                throw CaptureError("stage \(stageID) has no source room")
            }
            let roomPosition = try q16Position(room.positionBits)
            let cameraPosition = SIMD3(
                roomPosition.x,
                roomPosition.y,
                Int32(clamping: Int64(roomPosition.z) + Int64(32 * 65_536))
            )
            let visiblePropModelIndices = Set(
                visible.dependencies.compactMap { dependency -> UInt32? in
                    guard dependency.category == "props",
                          dependency.stages.contains(scene.stageName) else { return nil }
                    return dependency.modelIndex
                }
            )
            let staticProps = scene.setup.objects
                .filter {
                    staticPropTypes.contains($0.type)
                        && visiblePropModelIndices.contains($0.key0)
                }
                .map(\.index)
                .sorted()
            guard !staticProps.isEmpty else {
                throw CaptureError("stage \(stageID) has no guarded static prop placements")
            }

            let camera = GoldenEyeStagePlayerCameraSnapshotInputV6(
                stageID: stageID,
                nativeTick: 2,
                currentRoom: room.roomIndex + 1,
                cameraPositionQ16: cameraPosition,
                cameraForwardQ16: SIMD3(0, 0, -65_536),
                cameraUpQ16: SIMD3(0, 65_536, 0),
                yawQ16: 0,
                pitchQ16: 0
            )
            let input = GoldenEyeStageGameplayCameraSnapshotV7(
                demoID: 0,
                stageID: stageID,
                nativeTick: 2,
                playerCamera: camera,
                visibleRoomIndices: [room.roomIndex + 1],
                visibleStaticPropObjectIndices: staticProps
            )
            let packet = try GoldenEyeStageGameplayCameraPacketAdapterV7.make(
                scene: scene,
                snapshot: input,
                stageTextures: textures,
                sidecars: sidecars,
                setupDependencies: setupDependencies,
                visibleDependencies: visible
            )
            let repeated = try GoldenEyeStageGameplayCameraPacketAdapterV7.make(
                scene: scene,
                snapshot: input,
                stageTextures: textures,
                sidecars: sidecars,
                setupDependencies: setupDependencies,
                visibleDependencies: visible
            )
            guard packet.isPresentable,
                  packet.cameraInput.modelView != .identity,
                  packet.cameraInput.projection != .identity,
                  packet.subset.unsupportedMask == 0,
                  packet.subset.fullSceneUnsupportedMask == 0x38,
                  packet.composition.snapshot.summary.unsupported_visible_count == 0,
                  packet.composition.snapshot.drawCommands.count
                    > packet.environmentPacket.commands.count,
                  packet.packetHash == repeated.packetHash,
                  packet.composition.compositionHash == repeated.composition.compositionHash else {
                throw CaptureError("stage \(stageID) failed presentable deterministic V7 contract")
            }

            guard let drawable = layer.nextDrawable() else {
                throw CaptureError("stage \(stageID) supplied drawable unavailable")
            }
            let evidence = try renderer.render(
                snapshot: packet.composition.snapshot,
                suppliedDrawable: drawable
            )
            let bytes = try readback(
                texture: drawable.texture,
                width: drawable.texture.width,
                height: drawable.texture.height
            )
            guard hasNonBlackRGB(bytes),
                  evidence.drawCount > packet.environmentPacket.commands.count,
                  evidence.triangleCount == packet.composition.snapshot.indices.count else {
                throw CaptureError("stage \(stageID) supplied drawable did not draw room+props")
            }
            let rawSHA256 = sha256(bytes)
            let baseName = "stage-\(stageID)-demo-00-gameplay-camera"
            let rawURL = outputRoot.appendingPathComponent("\(baseName).raw")
            let pngURL = outputRoot.appendingPathComponent("\(baseName).png")
            try bytes.write(to: rawURL, options: .atomic)
            try GoldenEyeReferenceCaptureCodecV6.encodePNG(
                bgra8: bytes,
                width: drawable.texture.width,
                height: drawable.texture.height,
                bytesPerRow: drawable.texture.width * 4
            ).write(to: pngURL, options: .atomic)
            let metadata: [String: Any] = [
                "demoID": 0,
                "stageID": stageID,
                "cameraHash": String(matrixHash(packet.cameraInput.modelView)),
                "projectionHash": String(matrixHash(packet.cameraInput.projection)),
                "environmentCommands": packet.environmentPacket.commands.count,
                "staticPropPlacements": packet.subset.staticPropPlacementCount,
                "drawableStaticPropPlacements": packet.subset.drawableStaticPropPlacementCount,
                "sceneDraws": packet.composition.snapshot.drawCommands.count,
                "sceneTriangles": packet.composition.snapshot.indices.count,
                "unsupportedMask": packet.subset.unsupportedMask,
                "fullSceneUnsupportedMask": packet.subset.fullSceneUnsupportedMask,
                "packetHash": String(packet.packetHash),
                "compositionHash": String(packet.composition.compositionHash),
                "renderSourceHash": String(evidence.sourceManifestHash),
                "renderBatchHash": String(evidence.batchManifestHash),
                "metalDrawCount": evidence.metalDrawCount,
                "rawSHA256": rawSHA256,
                "raw": rawURL.path,
                "png": pngURL.path,
            ]
            let metadataData = try JSONSerialization.data(
                withJSONObject: metadata,
                options: [.sortedKeys, .prettyPrinted]
            )
            try metadataData.write(
                to: outputRoot.appendingPathComponent("\(baseName).json"),
                options: .atomic
            )
            packetHashes.append(packet.packetHash)
            compositionHashes.append(packet.composition.compositionHash)
            renderHashes.append(rawSHA256)
            print(
                "stage=\(stageID) demo=0 camera=nonIdentity "
                    + "roomCommands=\(packet.environmentPacket.commands.count) "
                    + "props=\(packet.subset.drawableStaticPropPlacementCount)/"
                    + "\(packet.subset.staticPropPlacementCount) "
                    + "sceneDraws=\(packet.composition.snapshot.drawCommands.count) "
                    + "metalDraws=\(evidence.metalDrawCount) "
                    + "unsupportedMask=0x\(String(packet.subset.unsupportedMask, radix: 16)) "
                    + "fullSceneUnsupportedMask=0x\(String(packet.subset.fullSceneUnsupportedMask, radix: 16)) "
                    + "packetHash=\(packet.packetHash) compositionHash=\(packet.composition.compositionHash) "
                    + "rawSHA256=\(rawSHA256)"
            )
        }
        renderer.shutdown()
        guard packetHashes.count == stageIDs.count,
              compositionHashes.count == stageIDs.count,
              renderHashes.count == stageIDs.count,
              packetHashes[0] != packetHashes[1],
              compositionHashes[0] != compositionHashes[1],
              renderHashes[0] != renderHashes[1] else {
            throw CaptureError("stage production capture hashes were not stage-scoped")
        }
        print(
            "goldeneye_stage_gameplay_camera_production_capture_v7_smoke: PASS "
                + "demo=0 stages=33,34 suppliedDrawable=1 roomProps=1 deterministic=1"
        )
    }

    private static func q16Position(
        _ bits: (UInt32, UInt32, UInt32)
    ) throws -> SIMD3<Int32> {
        func convert(_ bits: UInt32) throws -> Int32 {
            let value = Float(bitPattern: bits)
            let scaled = Double(value) * 65_536.0
            guard value.isFinite,
                  scaled >= Double(Int32.min),
                  scaled <= Double(Int32.max) else {
                throw CaptureError("invalid source room position")
            }
            return Int32(scaled.rounded(.toNearestOrAwayFromZero))
        }
        return SIMD3(try convert(bits.0), try convert(bits.1), try convert(bits.2))
    }

    private static func matrixHash(_ matrix: GoldenEyeProjectionV10.MatrixQ16) -> UInt64 {
        (0..<16).reduce(1_469_598_103_934_665_603) { hash, index in
            var result = hash
            let word = UInt64(UInt32(bitPattern: matrix.values[index]))
            for shift in stride(from: 0, through: 56, by: 8) {
                result = (result ^ ((word >> UInt64(shift)) & 0xff)) &* 1_099_511_628_211
            }
            return result == 0 ? 1 : result
        }
    }

    private static func readback(
        texture: any MTLTexture,
        width: Int,
        height: Int
    ) throws -> Data {
        guard width > 0, height > 0 else { throw CaptureError("invalid supplied drawable size") }
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

    private static func hasNonBlackRGB(_ data: Data) -> Bool {
        stride(from: 0, to: data.count, by: 4).contains { offset in
            data[offset] != 0 || data[offset + 1] != 0 || data[offset + 2] != 0
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private struct CaptureError: Error, CustomStringConvertible {
        let message: String
        init(_ message: String) { self.message = message }
        var description: String { message }
    }
}
