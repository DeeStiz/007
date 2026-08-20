import Foundation

@main
struct GoldenEyeTitleUVPacketSmoke {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
        let packets = try GoldenEyeTitleUVPacket.loadAll(from: root)
        let expected: [(UInt32, Int, Int)] = [(4, 36, 46), (5, 192, 39), (3, 1023, 145)]
        guard packets.count == expected.count else {
            throw Failure.message("packet count \(packets.count) != \(expected.count)")
        }
        var sawNonZeroST = false
        for (packet, expectedValue) in zip(packets, expected) {
            guard packet.modelHandle == expectedValue.0,
                  packet.records.count == expectedValue.1,
                  packet.indices.count == expectedValue.1,
                  packet.sourceCommandCount == expectedValue.2,
                  packet.hasUnsupportedCommands,
                  packet.records.allSatisfy({ $0.sourceCommandHash != 0 && $0.sourceVertexHash != 0 }),
                  packet.indices.enumerated().allSatisfy({ $0.element == UInt32($0.offset) }) else {
                throw Failure.message("packet evidence mismatch for handle \(packet.modelHandle)")
            }
            sawNonZeroST = sawNonZeroST || packet.records.contains(where: { $0.s != 0 || $0.t != 0 })
            guard packet.records.contains(where: { $0.materialHandle != 0 }) else {
                throw Failure.message("packet \(packet.modelHandle) lacks source material evidence")
            }
        }
        guard sawNonZeroST else { throw Failure.message("all source UV values are zero") }
        let total = packets.reduce(0) { $0 + $1.records.count }
        print("goldeneye_title_uv_packet_smoke: PASS packets=\(packets.count) records=\(total)")
    }

    enum Failure: Error, CustomStringConvertible {
        case message(String)
        var description: String {
            switch self { case .message(let value): return value }
        }
    }
}
