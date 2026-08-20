import Foundation

@main
struct GoldenEyeStageScenePacketSmoke {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first
            ?? "build/native/stage-assets", isDirectory: true)
        let catalog = try GoldenEyeStageAssetCatalog.load(stageAssetRoot: root)
        let packets = try GoldenEyeStageScenePacket.loadAll(catalog: catalog)
        precondition(packets.count == 7)
        precondition(packets.allSatisfy { $0.resources.count == 3 })
        precondition(packets.allSatisfy { $0.isRenderablePayloadReady })
        precondition(packets.allSatisfy { $0.background.roomCount == UInt32($0.rooms.count) })
        precondition(packets.allSatisfy { !$0.setup.objects.isEmpty && !$0.setup.portals.isEmpty })
        precondition(packets.allSatisfy { $0.packetHash != 0 })
        let repeated = try GoldenEyeStageScenePacket.loadAll(catalog: catalog)
        precondition(repeated == packets)
        let roomCount = packets.reduce(0) { $0 + $1.rooms.count }
        let payloadBytes = packets.reduce(0) { partial, packet in
            partial + packet.resources.reduce(0) { $0 + Int($1.decodedBytes) }
        }
        let hash = packets.reduce(UInt64(1469598103934665603)) { hash, packet in
            (hash ^ packet.packetHash) &* 1099511628211
        }
        print("goldeneye_stage_scene_packet_smoke: PASS stages=\(packets.count) rooms=\(roomCount) payload_bytes=\(payloadBytes) hash=\(hash)")
    }
}
