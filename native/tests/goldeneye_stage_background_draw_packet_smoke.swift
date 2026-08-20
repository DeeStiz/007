import Foundation

@main
struct GoldenEyeStageBackgroundDrawPacketSmoke {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw NSError(
                domain: "stage-background-draw",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "stage asset root required"]
            )
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let catalog = try GoldenEyeStageAssetCatalog.load(stageAssetRoot: root)
        let scenes = try GoldenEyeStageScenePacket.loadAll(catalog: catalog)
        precondition(scenes.count == 7)
        // This is the MSL buffer contract: eight 32-bit words, no hidden
        // Swift reference or alignment padding.
        precondition(MemoryLayout<GoldenEyeStageBackgroundDrawVertex>.stride == 32)

        guard let canonicalViewport = GoldenEyeProjectionV10.ViewportV10(
            drawableWidth: 440,
            drawableHeight: 330
        ),
        let wideViewport = GoldenEyeProjectionV10.ViewportV10(
            drawableWidth: 1920,
            drawableHeight: 1080
        ) else {
            throw NSError(domain: "stage-background-draw", code: 3)
        }
        let identity = GoldenEyeProjectionV10.MatrixQ16.identity
        guard let canonicalProjection = GoldenEyeProjectionV10.PacketV10(
            viewport: canonicalViewport,
            modelView: identity,
            projection: identity
        ),
        let wideProjection = GoldenEyeProjectionV10.PacketV10(
            viewport: wideViewport,
            modelView: identity,
            projection: identity
        ) else {
            throw NSError(domain: "stage-background-draw", code: 4)
        }

        var aggregate: UInt64 = 1_469_598_103_934_665_603
        var totalRooms = 0
        var totalPortals = 0
        var totalCommands = 0
        var totalVertices = 0
        var unsupportedCodes = Set<GoldenEyeStageBackgroundDrawDiagnosticCode>()

        for scene in scenes {
            let packet = try GoldenEyeStageBackgroundDrawPacketBuilder.make(
                scene: scene,
                viewport: canonicalViewport,
                projection: canonicalProjection
            )
            let repeated = try GoldenEyeStageBackgroundDrawPacketBuilder.make(
                scene: scene,
                viewport: canonicalViewport,
                projection: canonicalProjection
            )
            precondition(packet == repeated)
            precondition(packet.abiVersion == GoldenEyeStageBackgroundDrawPacket.abiVersion)
            precondition(packet.contractVersion == GoldenEyeStageBackgroundDrawPacket.contractVersion)
            precondition(packet.headerBytes == GoldenEyeStageBackgroundDrawPacket.headerBytes)
            precondition(packet.roomCount == UInt32(scene.rooms.count))
            precondition(packet.portalCount == UInt32(scene.setup.portals.count))
            precondition(packet.commandCount == UInt32(packet.commands.count))
            precondition(packet.vertexCount == UInt32(packet.vertices.count))
            precondition(packet.hasUnsupportedWork)
            precondition(packet.commands.allSatisfy { command in
                let end = Int(command.vertexStart) + Int(command.vertexCount)
                return command.vertexStart < packet.vertexCount && end <= packet.vertices.count
            })
            precondition(packet.commands.contains { $0.primitive == .roomMarker })
            precondition(packet.commands.contains { $0.primitive == .portalEdge })
            for diagnostic in packet.diagnostics {
                unsupportedCodes.insert(diagnostic.code)
            }
            aggregate = hashWord(packet.packetHash, into: aggregate)
            totalRooms += scene.rooms.count
            totalPortals += scene.setup.portals.count
            totalCommands += packet.commands.count
            totalVertices += packet.vertices.count
        }

        let requiredCodes: Set<GoldenEyeStageBackgroundDrawDiagnosticCode> = [
            .unsupportedBackgroundDisplayLists,
            .unsupportedRoomGeometry,
            .unsupportedProps,
            .unsupportedCharacters,
            .unsupportedAI,
            .unsupportedEffects,
        ]
        precondition(requiredCodes.isSubset(of: unsupportedCodes))
        precondition(totalRooms == 468)
        precondition(totalPortals == 612)
        precondition(totalCommands == 1_080)
        precondition(totalVertices == 4_032)
        precondition(aggregate == 4_308_406_056_569_914_737)

        let wide = try GoldenEyeStageBackgroundDrawPacketBuilder.make(
            scene: scenes[0],
            viewport: wideViewport,
            projection: wideProjection
        )
        let canonicalFirst = try GoldenEyeStageBackgroundDrawPacketBuilder.make(
            scene: scenes[0],
            viewport: canonicalViewport,
            projection: canonicalProjection
        )
        precondition(wide.viewportFlags == wideViewport.flags)
        precondition(wide.packetHash != canonicalFirst.packetHash)

        do {
            _ = try GoldenEyeStageBackgroundDrawPacketBuilder.make(
                scene: scenes[0],
                viewport: wideViewport,
                projection: canonicalProjection
            )
            preconditionFailure("viewport mismatch was accepted")
        } catch GoldenEyeStageBackgroundDrawPacketError.viewportMismatch {
            // Expected fail-closed behavior.
        }

        print(
            "goldeneye_stage_background_draw_packet_smoke: PASS " +
            "stages=\(scenes.count) rooms=\(totalRooms) portals=\(totalPortals) " +
            "commands=\(totalCommands) vertices=\(totalVertices) " +
            "unsupported=\(requiredCodes.count) aggregateHash=\(aggregate)"
        )
    }

    private static func hashWord(_ word: UInt64, into initial: UInt64) -> UInt64 {
        var hash = initial
        for shift in stride(from: 0, to: 64, by: 8) {
            hash = (hash ^ ((word >> UInt64(shift)) & 0xff)) &* 1_099_511_628_211
        }
        return hash
    }
}
