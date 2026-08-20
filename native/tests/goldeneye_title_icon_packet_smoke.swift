import CryptoKit
import Foundation

@main
struct GoldenEyeTitleIconPacketSmoke {
    static func main() throws {
        guard CommandLine.arguments.count >= 2 else {
            throw NSError(domain: "goldeneye-title-icons", code: 2, userInfo: [NSLocalizedDescriptionKey: "asset root argument is required"])
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let packetURL = root.appendingPathComponent("title-icons.geti")
        let packet = try GoldenEyeTitleIconPacket.load(from: packetURL)
        precondition(packet.records.count == GoldenEyeTitleIconPacket.iconCount)
        precondition(packet.sourceConcatByteCount == 6_984)
        precondition(packet.records.map(\.icon.sourceName) == ["COPYICON", "DELICON", "SELECTFILE", "CROSSHAIR1", "CHECK", "DOT", "X"])
        let expectedDimensions = [(32, 28), (32, 28), (122, 18), (32, 32), (20, 20), (16, 16), (15, 15)]
        precondition(packet.records.indices.allSatisfy { index in
            packet.records[index].width == expectedDimensions[index].0
                && packet.records[index].height == expectedDimensions[index].1
        })
        for icon in GoldenEyeTitleIconPacket.Icon.allCases {
            guard let record = packet.record(for: icon), let pixels = packet.pixels(for: icon) else {
                preconditionFailure("missing \(icon.sourceName)")
            }
            precondition(pixels.count == record.decodedByteCount)
            precondition(Array(SHA256.hash(data: pixels)) == record.decodedHash)
        }

        var tampered = try Data(contentsOf: packetURL)
        tampered[tampered.count - 1] ^= 0x01
        let tamperedURL = root.appendingPathComponent("title-icons-tampered.geti")
        try tampered.write(to: tamperedURL, options: .atomic)
        do {
            _ = try GoldenEyeTitleIconPacket.load(from: tamperedURL)
            preconditionFailure("tampered icon packet was accepted")
        } catch GoldenEyeTitleIconPacket.Error.hashMismatch {
            print("tamper=hash-mismatch")
        }

        var malformed = try Data(contentsOf: packetURL)
        // The first record's reserved word is at header + ten little-endian
        // words; setting it must fail before any payload is consumed.
        malformed[GoldenEyeTitleIconPacket.headerSize + 40] = 1
        malformed.replaceSubrange(60..<92, with: repeatElement(UInt8(0), count: 32))
        let malformedHash = Array(SHA256.hash(data: malformed))
        malformed.replaceSubrange(60..<92, with: malformedHash)
        let malformedURL = root.appendingPathComponent("title-icons-malformed.geti")
        try malformed.write(to: malformedURL, options: .atomic)
        do {
            _ = try GoldenEyeTitleIconPacket.load(from: malformedURL)
            preconditionFailure("malformed icon packet was accepted")
        } catch GoldenEyeTitleIconPacket.Error.invalid {
            print("malformed=reserved-field-rejected")
        }
        print("goldeneye_title_icon_packet_smoke: PASS packet=\(packet.packetHash.map { String(format: "%02x", $0) }.joined())")
    }
}
