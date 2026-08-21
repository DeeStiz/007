import Foundation

@main
struct GoldenEyeStageGameplayCameraPacketV7Smoke {
    private static let stageIDs: [UInt32] = [33, 34]
    private static let staticPropTypes: Set<UInt32> = [
        1, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 17, 20, 21, 36, 39, 40,
        41, 42, 43, 45, 47,
    ]

    static func main() throws {
        guard CommandLine.arguments.count == 2 || CommandLine.arguments.count == 3 else {
            fatalError("usage: goldeneye_stage_gameplay_camera_packet_v7_smoke /absolute/stage-root [/absolute/visible-root]")
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let visibleRoot = URL(
            fileURLWithPath: CommandLine.arguments.count == 3
                ? CommandLine.arguments[2]
                : "build/native/ramrom-visible-dependencies-v6",
            isDirectory: true
        )
        let catalog = try GoldenEyeStageAssetCatalog.load(stageAssetRoot: root)
        let textures = try GoldenEyeStageTextureCatalogV6.load(stageAssetRoot: root)
        let sidecars = try GoldenEyeStageModelSidecarCatalogV6.load(stageAssetRoot: root)
        let dependencies = try GoldenEyeStageSetupDependencyCatalogV6.load(stageAssetRoot: root)
        let visible = try GoldenEyeRamRomVisibleDependencyCatalogV6.load(rootURL: visibleRoot)

        var packetHashes: [UInt64] = []
        for stageID in stageIDs {
            let scene = try GoldenEyeStageScenePacket.load(stageID: stageID, catalog: catalog)
            guard let room = scene.rooms.first else {
                fatalError("stage \(stageID) has no source rooms")
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
            guard !staticProps.isEmpty else {
                fatalError("stage \(stageID) has no static prop placements")
            }
            let playerCamera = GoldenEyeStagePlayerCameraSnapshotInputV6(
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
                playerCamera: playerCamera,
                visibleRoomIndices: [room.roomIndex + 1],
                visibleStaticPropObjectIndices: staticProps
            )
            let packet = try GoldenEyeStageGameplayCameraPacketAdapterV7.make(
                scene: scene,
                snapshot: input,
                stageTextures: textures,
                sidecars: sidecars,
                setupDependencies: dependencies,
                visibleDependencies: visible
            )
            let repeated = try GoldenEyeStageGameplayCameraPacketAdapterV7.make(
                scene: scene,
                snapshot: input,
                stageTextures: textures,
                sidecars: sidecars,
                setupDependencies: dependencies,
                visibleDependencies: visible
            )
            precondition(packet.isPresentable)
            precondition(packet.cameraInput.modelView != .identity)
            precondition(packet.cameraInput.projection != .identity)
            let clipRange = GoldenEyeStageEnvironmentCameraAdapterV6
                .sourceGameplayClipRangeForTesting(stageID: stageID)
            let expectedClipRange: (near: Double, far: Double) = stageID == 33
                ? (5.0, 15_000.0)
                : (10.0, 5_000.0)
            precondition(clipRange != nil)
            precondition(abs(clipRange!.near - expectedClipRange.near) < 0.000_001)
            precondition(abs(clipRange!.far - expectedClipRange.far) < 0.000_001)
            precondition(packet.subset.fullSceneUnsupportedMask == 0x38)
            precondition(packet.subset.unsupportedMask == 0)
            precondition(packet.composition.snapshot.summary.unsupported_visible_count == 0)
            precondition(packet.composition.snapshot.eyeSpaceZQ16?.count ==
                         packet.composition.snapshot.vertices.count)
            precondition(packet.composition.snapshot.fogCoordinateQ16?.count ==
                         packet.composition.snapshot.vertices.count)
            precondition(packet.composition.snapshot.fogCoordinateQ16?.contains { $0 != 0 } == true)
            precondition(packet.subset.roomGeometryCommandCount > 0)
            precondition(packet.subset.staticPropPlacementCount == UInt32(staticProps.count))
            precondition(packet.subset.drawableStaticPropPlacementCount == UInt32(staticProps.count))
            precondition(packet.composition.snapshot.drawCommands.count > packet.environmentPacket.commands.count)
            // Every visible composed draw must retain the source GBI
            // geometry-mode/model-view sidecar after state-handle remapping.
            // The Metal renderer intentionally fails closed when this map is
            // incomplete; assert the production packet contract here so a
            // dropped context cannot reach supplied-drawable capture.
            guard let lighting = packet.composition.snapshot.lightingFrameContext else {
                fatalError("stage (stageID) composition missing lighting frame context")
            }
            precondition(packet.composition.snapshot.drawCommands.allSatisfy { draw in
                guard let state = packet.composition.snapshot.renderStateByHandle[draw.render_state_handle] else {
                    return false
                }
                return lighting.geometryModesByState[state.state_handle] != nil
                    && lighting.modelViewQ16ByState[state.state_handle]?.count == 16
            })
            precondition(packet.packetHash == repeated.packetHash)
            precondition(packet.subset.metadataHash == repeated.subset.metadataHash)

            var dynamicPacketHash: UInt64?
            var dynamicCompositionHash: UInt64?
            if stageID == stageIDs[0],
               let door = scene.setup.objects.first(where: {
                   $0.type == 1 && staticProps.contains($0.index)
               }) {
                let baseTransform = door.matrixWords.map { word in
                    Int32((Double(Float(bitPattern: word)) * 65_536.0).rounded(.toNearestOrAwayFromZero))
                }
                var movedTransform = baseTransform
                movedTransform[12] &+= 65_536
                let dynamicInput = GoldenEyeStageGameplayCameraSnapshotV7(
                    demoID: input.demoID,
                    stageID: input.stageID,
                    nativeTick: input.nativeTick,
                    playerCamera: input.playerCamera,
                    visibleRoomIndices: input.visibleRoomIndices,
                    visibleStaticPropObjectIndices: input.visibleStaticPropObjectIndices,
                    dynamicPropTransforms: [GoldenEyeStageGameplayCameraDynamicPropV7(
                        objectIndex: door.index, transformQ16: movedTransform,
                        sourceHash: 0xD00D_0007, openState: 1, portalNumber: 0
                    )]
                )
                let dynamicPacket = try GoldenEyeStageGameplayCameraPacketAdapterV7.make(
                    scene: scene,
                    snapshot: dynamicInput,
                    stageTextures: textures,
                    sidecars: sidecars,
                    setupDependencies: dependencies,
                    visibleDependencies: visible
                )
                precondition(dynamicPacket.isPresentable)
                precondition(dynamicPacket.packetHash != packet.packetHash)
                precondition(dynamicPacket.composition.compositionHash != packet.composition.compositionHash)
                precondition(dynamicPacket.subset.fullSceneUnsupportedMask == 0x38)
                dynamicPacketHash = dynamicPacket.packetHash
                dynamicCompositionHash = dynamicPacket.composition.compositionHash
            }
            packetHashes.append(packet.packetHash)
            print(
                "stage=\(stageID) demo=\(packet.demoID) cameraHash=\(matrixHash(packet.cameraInput.modelView)) " +
                    "environmentCommands=\(packet.environmentPacket.commands.count) " +
                    "props=\(packet.subset.drawableStaticPropPlacementCount)/\(packet.subset.staticPropPlacementCount) " +
                    "sceneDraws=\(packet.composition.snapshot.drawCommands.count) " +
                    "unsupportedMask=0x\(String(packet.subset.unsupportedMask, radix: 16)) " +
                    "fullSceneUnsupportedMask=0x\(String(packet.subset.fullSceneUnsupportedMask, radix: 16)) " +
                    "packetHash=\(packet.packetHash) " +
                    "dynamicPacketHash=\(dynamicPacketHash.map(String.init) ?? "none") " +
                    "dynamicCompositionHash=\(dynamicCompositionHash.map(String.init) ?? "none")"
            )

            if stageID == stageIDs[0] {
                let unsupportedInput = GoldenEyeStageGameplayCameraSnapshotV7(
                    demoID: input.demoID,
                    stageID: input.stageID,
                    nativeTick: input.nativeTick,
                    playerCamera: input.playerCamera,
                    visibleRoomIndices: input.visibleRoomIndices,
                    visibleStaticPropObjectIndices: input.visibleStaticPropObjectIndices,
                    visibleCategories: [.roomGeometry, .staticProps, .characters]
                )
                do {
                    _ = try GoldenEyeStageGameplayCameraPacketAdapterV7.make(
                        scene: scene,
                        snapshot: unsupportedInput,
                        stageTextures: textures,
                        sidecars: sidecars,
                        setupDependencies: dependencies,
                        visibleDependencies: visible
                    )
                    fatalError("unsupported visible category was accepted")
                } catch let error as GoldenEyeStageGameplayCameraPacketV7Error {
                    guard case .unsupportedVisibleCategory(.characters) = error else {
                        throw error
                    }
                }
            }
        }
        precondition(packetHashes.count == 2)
        precondition(packetHashes[0] != packetHashes[1])
        print(
            "goldeneye_stage_gameplay_camera_packet_v7_smoke: PASS demos=2 stages=33,34 " +
                "fullSceneUnsupportedMask=0x38 deterministic=1 failClosed=1"
        )
    }

    private static func q16Position(
        _ bits: (UInt32, UInt32, UInt32)
    ) throws -> SIMD3<Int32> {
        func convert(_ bits: UInt32) throws -> Int32 {
            let value = Float(bitPattern: bits)
            let scaled = Double(value) * 65_536.0
            guard value.isFinite, scaled >= Double(Int32.min), scaled <= Double(Int32.max) else {
                throw SmokeError("invalid source room position")
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

    private struct SmokeError: Error, CustomStringConvertible {
        let message: String
        init(_ message: String) { self.message = message }
        var description: String { message }
    }
}
