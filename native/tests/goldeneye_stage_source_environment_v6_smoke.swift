import Foundation

enum GoldenEyeTitleHash {
    static func fnv1a(_ words: [UInt64]) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for word in words {
            var value = word.littleEndian
            withUnsafeBytes(of: &value) { bytes in
                for byte in bytes {
                    hash ^= UInt64(byte)
                    hash &*= 0x100000001b3
                }
            }
        }
        return hash
    }
}

@main
struct GoldenEyeStageSourceEnvironmentV6Smoke {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("usage: goldeneye_stage_source_environment_v6_smoke /absolute/stage-asset-root")
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let catalog = try GoldenEyeStageAssetCatalog.load(stageAssetRoot: root)
        let scenes = try GoldenEyeStageScenePacket.loadAll(catalog: catalog)
        precondition(scenes.count == 7)
        guard let viewport = GoldenEyeProjectionV10.ViewportV10(
            drawableWidth: 440, drawableHeight: 330
        ), let projection = GoldenEyeProjectionV10.PacketV10(
            viewport: viewport,
            modelView: .identity,
            projection: .identity
        ) else {
            fatalError("could not construct canonical projection")
        }

        var aggregate = GoldenEyeCastSceneV6Hash.offsetBasis
        var totalEnvironmentTriangles = 0
        var totalVertices = 0
        var totalCommands = 0
        var totalMetalDraws = 0
        var materialAggregate = GoldenEyeCastSceneV6Hash.offsetBasis
        var stageRows: [(UInt32, Int, UInt64, UInt32)] = []
        var metalRows: [(UInt32, Int, Int)] = []
        var materialRows: [(UInt32, Int, UInt32, UInt32, UInt64)] = []
        for scene in scenes {
            let packet = try GoldenEyeStageSourceEnvironmentDrawPacketBuilderV6.make(
                scene: scene, viewport: viewport, projection: projection
            )
            let material = try GoldenEyeStageSourceMaterialLowererV6.make(scene: scene)
            precondition(material.hasSourceState)
            precondition(material.textureStateCommandCount > 0)
            precondition(material.unsupportedTextureBindingCount == material.textureStateCommandCount)
            let sourceSnapshot = try GoldenEyeStageSourceSceneSnapshotAdapterV6.make(
                packet: packet, nativeTick: 2, materialPacket: material
            )
            precondition(sourceSnapshot.summary.draw_count == UInt32(sourceSnapshot.drawCommands.count))
            precondition(sourceSnapshot.summary.draw_count <= UInt32(packet.commands.count))
            totalMetalDraws += sourceSnapshot.drawCommands.count
            metalRows.append((scene.stageID, packet.commands.count, sourceSnapshot.drawCommands.count))
            materialAggregate = GoldenEyeCastSceneV6Hash.mix(materialAggregate, material.packetHash)
            materialRows.append((
                scene.stageID, material.states.count,
                material.textureStateCommandCount, material.unsupportedCommandCount,
                material.packetHash
            ))
            if scene.stageID == 33 {
                let stageTextures = try GoldenEyeStageTextureCatalogV6.load(stageAssetRoot: root)
                if let firstRoom = scene.rooms.first {
                    let visiblePacket = try GoldenEyeStageSourceEnvironmentDrawPacketBuilderV6.make(
                        scene: scene,
                        viewport: viewport,
                        projection: projection,
                        visibleRoomIndices: [firstRoom.roomIndex]
                    )
                    precondition(!visiblePacket.commands.isEmpty)
                    precondition(visiblePacket.commands.allSatisfy {
                        $0.sourceIndex == firstRoom.roomIndex
                    })
                    let visibleSnapshot = try GoldenEyeStageSourceSceneSnapshotAdapterV6.make(
                        packet: visiblePacket,
                        nativeTick: 2,
                        materialPacket: material,
                        stageTextureCatalog: stageTextures
                    )
                    precondition(visibleSnapshot.summary.draw_count > 0)
                    let cameraInput = GoldenEyeStageEnvironmentCameraInputV6(
                        stageID: scene.stageID,
                        nativeTick: 2,
                        currentRoom: firstRoom.roomIndex,
                        visibleRoomIndices: [firstRoom.roomIndex],
                        modelView: .identity,
                        projection: .identity
                    )
                    let cameraSnapshot = try GoldenEyeStageEnvironmentCameraAdapterV6.make(
                        scene: scene,
                        camera: cameraInput,
                        materialPacket: material,
                        stageTextureCatalog: stageTextures,
                        environmentOnlyCapture: true
                    )
                    precondition(cameraSnapshot.summary.draw_count == visibleSnapshot.summary.draw_count)
                    do {
                        _ = try GoldenEyeStageEnvironmentCameraAdapterV6.make(
                            scene: scene,
                            camera: cameraInput,
                            materialPacket: material,
                            stageTextureCatalog: stageTextures
                        )
                        preconditionFailure("fog-enabled production stage must fail closed")
                    } catch let error as GoldenEyeStageEnvironmentCameraAdapterV6.Error {
                        guard case .fogUnavailable(33, _) = error else {
                            throw error
                        }
                    }
                    let playerCamera = GoldenEyeStagePlayerCameraSnapshotInputV6(
                        stageID: scene.stageID,
                        nativeTick: 2,
                        currentRoom: firstRoom.roomIndex,
                        cameraPositionQ16: SIMD3(0, 0, 1_000 * 65_536),
                        cameraForwardQ16: SIMD3(0, 0, -65_536),
                        cameraUpQ16: SIMD3(0, 65_536, 0),
                        yawQ16: 0,
                        pitchQ16: 0
                    )
                    let derivedInput = try GoldenEyeStageEnvironmentCameraAdapterV6.input(
                        scene: scene, snapshot: playerCamera
                    )
                    precondition(derivedInput.currentRoom == firstRoom.roomIndex)
                    precondition(derivedInput.visibleRoomIndices.contains(firstRoom.roomIndex))
                    precondition(derivedInput.projection != .identity)
                    precondition(derivedInput.roomCoordinateScaleQ16 == Int32(
                        (1.0 / 0.23363999 * 65_536.0).rounded()
                    ))
                    // The source STAN/portal room ID is one-based while the
                    // bounded background packet omits its leading null row.
                    let sourceRoomCamera = GoldenEyeStagePlayerCameraSnapshotInputV6(
                        stageID: scene.stageID,
                        nativeTick: 2,
                        currentRoom: 114,
                        cameraPositionQ16: SIMD3(221315072, 9437184, 24051712),
                        cameraForwardQ16: SIMD3(0, -4572, -65376),
                        cameraUpQ16: SIMD3(0, 65536, 0),
                        yawQ16: 180 * 65_536,
                        pitchQ16: -4 * 65_536
                    )
                    let mappedSourceRoom = try GoldenEyeStageEnvironmentCameraAdapterV6.input(
                        scene: scene, snapshot: sourceRoomCamera
                    )
                    precondition(mappedSourceRoom.visibleRoomIndices.contains(113))
                    // The source owner can legitimately publish a pole view
                    // (pitch +/-90) while retaining the world-up vector. The
                    // adapter must use the copied yaw to choose the
                    // continuous limiting right axis rather than rejecting
                    // this source camera basis as singular.
                    let poleCamera = GoldenEyeStagePlayerCameraSnapshotInputV6(
                        stageID: scene.stageID,
                        nativeTick: 2,
                        currentRoom: firstRoom.roomIndex,
                        cameraPositionQ16: SIMD3(0, 0, 1_000 * 65_536),
                        cameraForwardQ16: SIMD3(0, -65_536, 0),
                        cameraUpQ16: SIMD3(0, 65_536, 0),
                        yawQ16: 15 * 65_536,
                        pitchQ16: -90 * 65_536
                    )
                    let poleInput = try GoldenEyeStageEnvironmentCameraAdapterV6.input(
                        scene: scene, snapshot: poleCamera
                    )
                    precondition(poleInput.modelView != .identity)
                }
                let snapshot = try GoldenEyeStageSourceSceneSnapshotAdapterV6.make(
                    packet: packet, nativeTick: 2
                )
                precondition(!snapshot.isPresentable)
                precondition(snapshot.summary.screen == UInt32(GE_SOURCE_FRAME_V6_SCREEN_RAMROM))
                precondition(snapshot.summary.draw_count == UInt32(snapshot.drawCommands.count))
                precondition(snapshot.summary.draw_count < UInt32(packet.commands.count))
                precondition(snapshot.summary.vertex_count == UInt32(packet.vertices.count))
                precondition(snapshot.summary.unsupported_visible_count > 0)
                let materialSnapshot = sourceSnapshot
                precondition(!materialSnapshot.isPresentable)
                precondition(materialSnapshot.summary.draw_count == UInt32(materialSnapshot.drawCommands.count))
                precondition(materialSnapshot.summary.draw_count <= UInt32(packet.commands.count))
                let uniqueMaterialStateCount = Set(material.states.map(\.stateHash)).count
                precondition(materialSnapshot.summary.render_state_count ==
                             UInt32(min(uniqueMaterialStateCount + 1, 2_048)))
                precondition(materialSnapshot.renderStates.count ==
                             min(uniqueMaterialStateCount + 1, 2_048))
                precondition(materialSnapshot.drawCommands.contains {
                    $0.render_state_handle != 1
                })
                precondition(materialSnapshot.renderStates.dropFirst().contains {
                    $0.raw_othermode_l != 0 &&
                    $0.raw_render_mode == ($0.raw_othermode_l & 0xffff_fff8)
                })
                precondition(materialSnapshot.renderStates.dropFirst().contains {
                    $0.combiner_cycle_count >= 1 &&
                    ($0.cycle0_color_a == UInt32(GE_SOURCE_COMBINER_V6_KEY_TEXEL0) ||
                     $0.cycle0_color_a == UInt32(GE_SOURCE_COMBINER_V6_KEY_TEXEL1) ||
                     $0.cycle0_color_a == UInt32(GE_SOURCE_COMBINER_V6_KEY_SHADE))
                })
                precondition(materialSnapshot.vertices.contains {
                    $0.texcoord_q16.0 != 0 || $0.texcoord_q16.1 != 0
                })
                let texturedSnapshot = try GoldenEyeStageSourceSceneSnapshotAdapterV6.make(
                    packet: packet,
                    nativeTick: 2,
                    materialPacket: material,
                    stageTextureCatalog: stageTextures
                )
                precondition(texturedSnapshot.summary.resource_count > 0)
                precondition(texturedSnapshot.drawCommands.contains {
                    $0.resource_handle != 0
                })
                precondition(texturedSnapshot.resources.contains {
                    $0.resource_kind == UInt32(GE_SOURCE_RESOURCE_V6_TEXTURE)
                })
            }
            precondition(packet.hasUnsupportedWork)
            precondition(packet.commands.allSatisfy {
                // Portals remain copied visibility inputs; only source room
                // surfaces enter the product draw list.
                $0.primitive == .roomTriangle
            })
            precondition(packet.commands.allSatisfy { $0.vertexCount == 3 })
            precondition(packet.commands.count > 0)
            precondition(packet.vertices.count == packet.commands.count * 3)
            precondition(packet.vertices.contains { $0.sourceTextureCoordinatesPresent })
            let sourceCommandCount = packet.commands.count
            totalEnvironmentTriangles += sourceCommandCount
            totalVertices += packet.vertices.count
            totalCommands += sourceCommandCount
            aggregate = GoldenEyeCastSceneV6Hash.mix(aggregate, packet.packetHash)
            aggregate = GoldenEyeCastSceneV6Hash.mix(aggregate, packet.sourceHash)
            stageRows.append((scene.stageID, sourceCommandCount, packet.packetHash, packet.unsupportedMask))

            let repeated = try GoldenEyeStageSourceEnvironmentDrawPacketBuilderV6.make(
                scene: scene, viewport: viewport, projection: projection
            )
            precondition(packet == repeated)
        }
        precondition(stageRows.count == 7)
        let expectedRows: [(UInt32, Int, UInt64, UInt32)] = [
            (9, 5512, 4963216971587413481, 60),
            (20, 28639, 7255660490891708475, 60),
            (25, 10415, 17144747270193818655, 60),
            (26, 18757, 11489158572439398986, 60),
            (33, 13982, 7880595388395817258, 60),
            (34, 15481, 335037241637048974, 60),
            (35, 3298, 15885629354570869667, 60),
        ]
        let sortedRows = stageRows.sorted(by: { $0.0 < $1.0 })
        precondition(zip(sortedRows, expectedRows).allSatisfy { lhs, rhs in
            lhs.0 == rhs.0 && lhs.1 == rhs.1 && lhs.2 == rhs.2 && lhs.3 == rhs.3
        })
        precondition(aggregate == 14163285202610776526)
        precondition(materialAggregate == 8604049448195931432)
        precondition(materialRows.count == 7)
        let expectedMaterialRows: [(UInt32, Int, UInt32, UInt32, UInt64)] = [
            (9, 1411, 113, 0, 15784589468719617992),
            (20, 7333, 555, 0, 4484748419374539182),
            (25, 2657, 154, 0, 15496176961668206762),
            (26, 4777, 423, 0, 14756327828969665842),
            (33, 3635, 368, 0, 5082137231559705023),
            (34, 3988, 328, 0, 808239429714295832),
            (35, 868, 100, 0, 13522031614748956545),
        ]
        let sortedMaterialRows = materialRows.sorted(by: { $0.0 < $1.0 })
        precondition(zip(sortedMaterialRows, expectedMaterialRows).allSatisfy { lhs, rhs in
            lhs.0 == rhs.0 && lhs.1 == rhs.1 && lhs.2 == rhs.2 &&
                lhs.3 == rhs.3 && lhs.4 == rhs.4
        })
        print(
                "goldeneye_stage_source_environment_v6_smoke: PASS stages=7 " +
                "environmentTriangles=\(totalEnvironmentTriangles) vertices=\(totalVertices) " +
                "commands=\(totalCommands) metalDraws=\(totalMetalDraws) " +
                "aggregateHash=\(aggregate) materialAggregate=\(materialAggregate)"
        )
        for row in stageRows.sorted(by: { $0.0 < $1.0 }) {
            print(
                "stage=\(row.0) environmentTriangles=\(row.1) packetHash=\(row.2) " +
                    "unsupportedMask=\(row.3)"
            )
        }
        for row in materialRows.sorted(by: { $0.0 < $1.0 }) {
            print(
                "materialStage=\(row.0) states=\(row.1) textureCommands=\(row.2) " +
                    "unsupportedCommands=\(row.3) packetHash=\(row.4)"
            )
        }
        for row in metalRows.sorted(by: { $0.0 < $1.0 }) {
            print("metalStage=\(row.0) sourceTriangles=\(row.1) drawCount=\(row.2)")
        }
    }
}
