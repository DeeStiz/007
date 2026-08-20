import Foundation
import Metal
import QuartzCore

@available(macOS 27.0, *)
@main
struct GoldenEyeStageGameplayCameraReferenceCaptureV6Smoke {
    private struct Route {
        let demoID: UInt32
        let stageID: UInt32
        let slot: UInt32
        let name: String
    }

    private static let routes: [Route] = [
        .init(demoID: 1, stageID: 33, slot: 1, name: "ramrom_Dam_1.bin"),
        .init(demoID: 2, stageID: 33, slot: 1, name: "ramrom_Dam_2.bin"),
        .init(demoID: 3, stageID: 34, slot: 1, name: "ramrom_Facility_1.bin"),
        .init(demoID: 4, stageID: 34, slot: 1, name: "ramrom_Facility_2.bin"),
        .init(demoID: 5, stageID: 34, slot: 1, name: "ramrom_Facility_3.bin"),
        .init(demoID: 6, stageID: 35, slot: 1, name: "ramrom_Runway_1.bin"),
        .init(demoID: 7, stageID: 35, slot: 1, name: "ramrom_Runway_2.bin"),
        .init(demoID: 8, stageID: 9, slot: 0, name: "ramrom_BunkerI_1.bin"),
        .init(demoID: 9, stageID: 9, slot: 0, name: "ramrom_BunkerI_2.bin"),
        .init(demoID: 10, stageID: 20, slot: 1, name: "ramrom_Silo_1.bin"),
        .init(demoID: 11, stageID: 20, slot: 1, name: "ramrom_Silo_2.bin"),
        .init(demoID: 12, stageID: 26, slot: 1, name: "ramrom_Frigate_1.bin"),
        .init(demoID: 13, stageID: 26, slot: 1, name: "ramrom_Frigate_2.bin"),
        .init(demoID: 14, stageID: 25, slot: 0, name: "ramrom_Train.bin"),
    ]

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4) else {
            print("goldeneye_stage_gameplay_camera_reference_capture_v6_smoke: SKIP (Metal 4 unavailable)")
            return
        }
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count >= 5 else {
            throw CaptureError("usage: stage-root boot-root visible-root metallib output")
        }
        let stageRoot = URL(fileURLWithPath: args[0], isDirectory: true)
        let bootRoot = URL(fileURLWithPath: args[1], isDirectory: true)
        let visibleRoot = URL(fileURLWithPath: args[2], isDirectory: true)
        let libraryURL = URL(fileURLWithPath: args[3])
        let outputRoot = URL(fileURLWithPath: args[4], isDirectory: true)
        try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)

        let catalog = try GoldenEyeStageAssetCatalog.load(stageAssetRoot: stageRoot)
        let scenes = try GoldenEyeStageScenePacket.loadAll(catalog: catalog)
        let dependencies = try GoldenEyeStageSetupDependencyCatalogV6.load(stageAssetRoot: stageRoot)
        let sidecars = try GoldenEyeStageModelSidecarCatalogV6.load(stageAssetRoot: stageRoot)
        let visibleDependencies = try GoldenEyeRamRomVisibleDependencyCatalogV6.load(rootURL: visibleRoot)
        let stageTextures = try GoldenEyeStageTextureCatalogV6.load(stageAssetRoot: stageRoot)

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
            throw CaptureError("stage texture upload event unavailable")
        }
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
        let bindingAdapter = try GoldenEyeSourceSceneTextureBindingAdapterV6(store: store, plan: plan)
        let pipeline = try GoldenEyeSourceScenePipelineV6(
            device: device, libraryURL: libraryURL, pixelFormat: .bgra8Unorm
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

        var checkpointCount = 0
        for route in routes {
            guard let scene = scenes.first(where: { $0.stageID == route.stageID }) else {
                throw CaptureError("missing stage \(route.stageID)")
            }
            let sourcePages = try GoldenEyeRamRomGameplaySourcePagesV6.make(
                stagePacket: scene,
                dependencies: dependencies,
                sidecars: sidecars,
                visibleDependencies: visibleDependencies,
                slotNumber: route.slot
            )
            let recordingURL = bootRoot.appendingPathComponent("ramrom", isDirectory: true)
                .appendingPathComponent(route.name, isDirectory: false)
            let data = try Data(contentsOf: recordingURL, options: [.mappedIfSafe])
            var header = GERamRomHeaderV5()
            var summary = GERamRomParseSummaryV5()
            let parseStatus = data.withUnsafeBytes { raw -> UInt32 in
                guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return UInt32(GE_STATUS_INVALID_ARGUMENT)
                }
                let headerStatus = ge_ramrom_v5_read_header(base, UInt32(data.count), &header)
                guard headerStatus == UInt32(GE_STATUS_OK) else { return headerStatus }
                return ge_ramrom_v5_parse(base, UInt32(data.count), &summary)
            }
            guard parseStatus == UInt32(GE_STATUS_OK) else {
                throw CaptureError("demo \(route.demoID) parse status \(parseStatus)")
            }
            let styles = intValues(header.controller_styles)
            let options = try GoldenEyeRamRomSourceOptionStateV6(
                controlStyle: UInt32(clamping: Int64(styles.first ?? 0)),
                invertLook: 0,
                sourceHash: 0x4f5054494f4e5f55,
                provenance: ["RAMROM controller_styles[0]", "src/game/options.c:104"]
            )
            let pages = try GoldenEyeRamRomPlayerCameraPageBuilderV6.make(
                stagePacket: scene,
                sourcePages: sourcePages,
                ramromHeader: header,
                optionState: options,
                demoID: route.demoID
            )
            let material = try GoldenEyeStageSourceMaterialLowererV6.make(scene: scene)
            let owner = try GoldenEyeRamRomPlayerCameraOwnerV6(pages: pages)
            let totalSamples = Int(summary.record_count)
            let checkpoints = Set([0, max(0, totalSamples / 2), max(0, totalSamples - 1)])
            var sampleOrdinal = 0
            var nativeTick: UInt64 = 0
            for packetIndex in 0..<summary.packet_count {
                var packet = GERamRomPacketV5()
                let packetStatus = data.withUnsafeBytes { raw -> UInt32 in
                    guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        return UInt32(GE_STATUS_INVALID_ARGUMENT)
                    }
                    return ge_ramrom_v5_read_packet(base, UInt32(data.count), packetIndex, &packet)
                }
                guard packetStatus == UInt32(GE_STATUS_OK) else {
                    throw CaptureError("demo \(route.demoID) packet status \(packetStatus)")
                }
                for frameIndex in 0..<packet.record_count {
                    var sample = GERamRomSampleV5()
                    let sampleStatus = data.withUnsafeBytes { raw -> UInt32 in
                        guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                            return UInt32(GE_STATUS_INVALID_ARGUMENT)
                        }
                        return ge_ramrom_v5_copy_sample(
                            base, UInt32(data.count), packetIndex, frameIndex, 0, &sample
                        )
                    }
                    guard sampleStatus == UInt32(GE_STATUS_OK) else {
                        throw CaptureError("demo \(route.demoID) sample status \(sampleStatus)")
                    }
                    let publication = try owner.step(nativeTick: nativeTick, input: input(sample))
                    nativeTick += 1
                    _ = try owner.step(nativeTick: nativeTick, input: noInput())
                    nativeTick += 1
                    if checkpoints.contains(sampleOrdinal) {
                        let snapshot = owner.snapshot
                        let cameraSnapshot = GoldenEyeStagePlayerCameraSnapshotInputV6(
                            stageID: UInt32(snapshot.stage_id),
                            nativeTick: max(1, UInt64(snapshot.native_tick)),
                            currentRoom: UInt32(snapshot.current_room),
                            cameraPositionQ16: simdValues(snapshot.camera_position_q16),
                            cameraForwardQ16: simdValues(snapshot.camera_forward_q16),
                            cameraUpQ16: simdValues(snapshot.camera_up_q16),
                            yawQ16: Int32(snapshot.yaw_q16),
                            pitchQ16: Int32(snapshot.pitch_q16)
                        )
                        let cameraInput = try GoldenEyeStageEnvironmentCameraAdapterV6.input(
                            scene: scene, snapshot: cameraSnapshot
                        )
                        let environmentSnapshot = try GoldenEyeStageEnvironmentCameraAdapterV6.make(
                            scene: scene,
                            camera: cameraInput,
                            materialPacket: material,
                            stageTextureCatalog: stageTextures,
                            environmentOnlyCapture: true
                        )
                        let tag = sampleOrdinal == 0 ? "start" : (sampleOrdinal == totalSamples / 2 ? "mid" : "end")
                        let baseName = String(format: "demo-%02u-%@", route.demoID, tag)
                        let rawURL = outputRoot.appendingPathComponent("\(baseName).raw")
                        let capture = try renderer.captureReference320x240(
                            snapshot: environmentSnapshot, to: rawURL
                        )
                        let pixelCount = capture.width * capture.height
                        var nonBlackPixelCount = 0
                        var texturedNonBlackPixelCount = 0
                        for pixel in stride(from: 0, to: capture.bytes.count, by: 4) {
                            let blue = capture.bytes[pixel]
                            let green = capture.bytes[pixel + 1]
                            let red = capture.bytes[pixel + 2]
                            if red != 0 || green != 0 || blue != 0 {
                                nonBlackPixelCount += 1
                                if environmentSnapshot.drawCommands.contains(where: {
                                    $0.resource_handle != 0
                                }) {
                                    texturedNonBlackPixelCount += 1
                                }
                            }
                        }
                        let depthValues = environmentSnapshot.vertices.map { $0.position_q16.2 }
                        let depthMin = depthValues.min() ?? 0
                        let depthMax = depthValues.max() ?? 0
                        let mappedCurrentRoom = cameraSnapshot.currentRoom > 0
                            ? cameraSnapshot.currentRoom - 1 : cameraSnapshot.currentRoom
                        let currentRoomTriangleCount = environmentSnapshot.drawCommands.reduce(
                            into: 0
                        ) { count, command in
                            if command.sort_key == mappedCurrentRoom {
                                count += Int(command.index_count)
                            }
                        }
                        let texturedDrawCount = environmentSnapshot.drawCommands.reduce(
                            into: 0
                        ) { count, command in
                            if command.resource_handle != 0 { count += Int(command.index_count) }
                        }
                        let pngURL = outputRoot.appendingPathComponent("\(baseName).png")
                        try GoldenEyeReferenceCaptureCodecV6.encodePNG(
                            bgra8: capture.bytes,
                            width: capture.width,
                            height: capture.height,
                            bytesPerRow: capture.bytesPerRow
                        ).write(to: pngURL, options: .atomic)
                        let portalNeighbors = scene.setup.portals.reduce(into: Set<UInt32>()) { result, portal in
                            if portal.connectedRoom1 == cameraSnapshot.currentRoom { result.insert(portal.connectedRoom2) }
                            if portal.connectedRoom2 == cameraSnapshot.currentRoom { result.insert(portal.connectedRoom1) }
                        }
                        let metadata: [String: Any] = [
                            "demoID": route.demoID,
                            "stageID": route.stageID,
                            "checkpoint": tag,
                            "sampleOrdinal": sampleOrdinal,
                            "totalSamples": totalSamples,
                            "nativeTick": snapshot.native_tick,
                            "currentRoom": cameraSnapshot.currentRoom,
                            "visibleRoomIndices": cameraInput.visibleRoomIndices,
                            "visibleRoomCount": cameraInput.visibleRoomIndices.count,
                            "portalNeighborCount": portalNeighbors.count,
                            "cameraPositionQ16": intValues(snapshot.camera_position_q16),
                            "cameraWorldPositionQ16": [
                                cameraInput.cameraPositionQ16.x,
                                cameraInput.cameraPositionQ16.y,
                                cameraInput.cameraPositionQ16.z,
                            ],
                            "roomCoordinateScaleQ16": cameraInput.roomCoordinateScaleQ16,
                            "cameraForwardQ16": intValues(snapshot.camera_forward_q16),
                            "cameraUpQ16": intValues(snapshot.camera_up_q16),
                            "cameraHash": publication.cameraHash,
                            "roomHash": publication.roomHash,
                            "ownerHash": publication.ownerStateHash,
                            "sourceTriangles": environmentSnapshot.summary.index_count,
                            "metalDraws": environmentSnapshot.summary.draw_count,
                            "resourceCount": environmentSnapshot.summary.resource_count,
                            "texturedDrawCount": texturedDrawCount,
                            "currentRoomTriangleCount": currentRoomTriangleCount,
                            "depthMinQ16": depthMin,
                            "depthMaxQ16": depthMax,
                            "nonBlackPixelCount": nonBlackPixelCount,
                            "nonBlackPixelRatio": Double(nonBlackPixelCount) / Double(max(1, pixelCount)),
                            "texturedNonBlackPixelCount": texturedNonBlackPixelCount,
                            "blackWithoutFade": nonBlackPixelCount == 0,
                            "rawSHA256": capture.rawSHA256,
                            "png": pngURL.path,
                        ]
                        let json = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys, .prettyPrinted])
                        try json.write(to: outputRoot.appendingPathComponent("\(baseName).json"), options: .atomic)
                        checkpointCount += 1
                    }
                    sampleOrdinal += 1
                }
            }
        }
        renderer.shutdown()
        precondition(checkpointCount == 42)
        print("goldeneye_stage_gameplay_camera_reference_capture_v6_smoke: PASS demos=14 checkpoints=42")
    }

    private static func input(_ sample: GERamRomSampleV5) -> GERamRomGameplayInputV6 {
        var value = noInput()
        value.stick_x = Int16(sample.stick_x)
        value.stick_y = Int16(sample.stick_y)
        value.pressed_buttons = UInt32(sample.buttons)
        value.held_buttons = UInt32(sample.buttons)
        return value
    }

    private static func noInput() -> GERamRomGameplayInputV6 {
        var value = GERamRomGameplayInputV6()
        value.header.abi_version = GE_NATIVE_ABI_VERSION
        value.header.struct_size = UInt32(MemoryLayout<GERamRomGameplayInputV6>.size)
        value.record_version = GE_RAMROM_GAMEPLAY_V6_RECORD_VERSION
        value.flags = GE_RAMROM_GAMEPLAY_V6_INPUT_RECORDED |
            GE_RAMROM_GAMEPLAY_V6_INPUT_FOCUSED |
            GE_RAMROM_GAMEPLAY_V6_INPUT_CONTROLLER
        value.controller_count = 1
        value.controller_index = 0
        value.source_mask = GE_RAMROM_GAMEPLAY_V6_INPUT_CONTROLLER
        return value
    }

    private static func intValues<T>(_ tuple: T) -> [Int32] {
        withUnsafeBytes(of: tuple) { Array($0.bindMemory(to: Int32.self)) }
    }

    private static func simdValues<T>(_ tuple: T) -> SIMD3<Int32> {
        let values = intValues(tuple)
        return SIMD3(values[0], values[1], values[2])
    }

    private struct CaptureError: Error, CustomStringConvertible {
        let message: String
        init(_ message: String) { self.message = message }
        var description: String { message }
    }
}
