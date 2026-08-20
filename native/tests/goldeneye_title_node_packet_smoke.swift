import Foundation

@main
struct GoldenEyeTitleNodePacketSmoke {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let packets = try GoldenEyeTitleNodePacket.loadAll(from: root)
        precondition(packets.count == 4)
        let expectedHandles: Set<UInt32> = [3, 4, 5, 6]
        precondition(Set(packets.map(\.modelHandle)) == expectedHandles)
        precondition(packets.allSatisfy { !$0.nodes.isEmpty && $0.sourceLength > 0 })
        precondition(packets.first(where: { $0.modelHandle == 5 })!.nodes.count == 42)
        precondition(packets.first(where: { $0.modelHandle == 6 })!.textures.count == 84)
        let totalNodes = packets.reduce(0) { $0 + $1.nodes.count }
        let totalTextures = packets.reduce(0) { $0 + $1.textures.count }
        let packetHashes = packets.map { $0.packetHash.map { String(format: "%02x", $0) }.joined() }
        print("goldeneye_title_node_packet_smoke: PASS models=\(packets.count) nodes=\(totalNodes) textures=\(totalTextures) packets=\(packetHashes.joined(separator: ","))")
    }
}
