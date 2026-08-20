import Foundation

@main
struct GoldenEyeTitleTexturePacketSmoke {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let packets = try GoldenEyeTitleTexturePacket.loadAll(from: root)
        precondition(packets.count == 4)
        precondition(Set(packets.map(\.modelHandle)) == Set([3, 4, 5, 6]))
        precondition(packets.first(where: { $0.modelHandle == 4 })!.records.count == 5)
        precondition(packets.first(where: { $0.modelHandle == 5 })!.records.count == 1)
        precondition(packets.first(where: { $0.modelHandle == 3 })!.records.count == 2)
        precondition(packets.first(where: { $0.modelHandle == 6 })!.records.count == 84)

        let direct = packets.first(where: { $0.modelHandle == 4 })!
        precondition(direct.records.allSatisfy { $0.isDirectModel && !$0.isSymbolicID })
        precondition(direct.records[0].format == 0 && direct.records[0].size == 2)
        precondition(direct.records[1].format == 4 && direct.records[1].renderDepth == 0)
        precondition(direct.records[0].rgbaByteCount(packet: direct) == direct.records[0].decodedByteCount)

        let goldenEye = packets.first(where: { $0.modelHandle == 3 })!
        precondition(goldenEye.records[0].hasMipChain && !goldenEye.records[1].hasMipChain)

        let wallet = packets.first(where: { $0.modelHandle == 6 })!
        precondition(wallet.records.allSatisfy { $0.isImageStream && $0.isSymbolicID })
        precondition(wallet.records[0..<4].allSatisfy { $0.hasMipChain })
        // DOT and the mission-map rows are single-level source streams.
        precondition(!wallet.records[23].hasMipChain && !wallet.records[24].hasMipChain)
        precondition(wallet.records[0].width == 65 && wallet.records[0].height == 65)
        precondition(wallet.rgba8(for: 0).count == 65 * 65 * 4)

        // Strict tamper guard: a changed decoded byte must be rejected by the
        // canonical packet hash before any payload is exposed.
        let packetURL = root.appendingPathComponent("walletbond.gett")
        var tampered = try Data(contentsOf: packetURL)
        tampered[tampered.index(tampered.startIndex, offsetBy: 128 + 144 * 84)] ^= 0x01
        do {
            _ = try GoldenEyeTitleTexturePacket.load(data: tampered)
            preconditionFailure("tampered packet was accepted")
        } catch GoldenEyeTitleTexturePacket.Error.hashMismatch {
            // expected
        }
        print("goldeneye_title_texture_packet_smoke: PASS models=\(packets.count) records=\(packets.reduce(0) { $0 + $1.records.count })")
    }
}

private extension GoldenEyeTitleTexturePacket.Record {
    func rgbaByteCount(packet: GoldenEyeTitleTexturePacket) -> Int {
        packet.rgba8(for: packet.records.firstIndex(of: self) ?? 0).count
    }
}
