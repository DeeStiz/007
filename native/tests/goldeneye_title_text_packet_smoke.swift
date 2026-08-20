import Foundation

@main
struct GoldenEyeTitleTextPacketSmoke {
    static func main() throws {
        guard CommandLine.arguments.count >= 2 else {
            throw NSError(domain: "goldeneye-title-text", code: 2, userInfo: [NSLocalizedDescriptionKey: "asset root argument is required"])
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let packetURL = root.appendingPathComponent("title/title-font.getf")
        let packet = try GoldenEyeTitleFontPacket.load(from: packetURL)
        precondition(packet.glyphs.count == 94)
        precondition(packet.kerning.count == 13 * 13)
        precondition(packet.glyph(for: "A") != nil)

        let catalogURL = root.appendingPathComponent("title/LtitleE.gecat")
        let catalog = try GoldenEyeTitleCatalogPacket.load(from: catalogURL)
        precondition(catalog.strings.count == 302)
        precondition(catalog.string(at: 7) == "TWYCROSS BOARD OF GAME CLASSIFICATION\n")
        precondition(catalog.string(at: 27) == "Copy\n")
        precondition(catalog.string(at: 29) == "SELECT MISSION\n")
        precondition(catalog.string(at: 30) == "MULTIPLAYER\n")

        var evidence: [String] = []
        evidence.append("packet=glyphs=\(packet.glyphs.count) kerning=\(packet.kerning.count)")
        evidence.append("catalog=strings=\(catalog.strings.count)")
        let textPacket = try GoldenEyeTitleTextPacket.load(from: packetURL)
        for screen in [UInt32(0), 5, 6] {
            let geometry = try textPacket.makeGeometry(screen: screen, catalog: catalog)
            precondition(!geometry.vertices.isEmpty && !geometry.indices.isEmpty)
            precondition(geometry.indices.count % 6 == 0)
            precondition(geometry.glyphCount > 0 && geometry.pixelQuadCount > 0)
            let bounds = geometry.bounds.joined(separator: ";")
            if screen == 5 {
                precondition(bounds.contains("IMAGE_SELECTFILE=[49,276,171,294]"))
                precondition(bounds.contains("COPYICON=[209,271,241,299]"))
                precondition(bounds.contains("DELICON=[319,271,351,299]"))
            }
            evidence.append("screen=\(screen) glyphs=\(geometry.glyphCount) pixelQuads=\(geometry.pixelQuadCount) vertices=\(geometry.vertices.count) indices=\(geometry.indices.count) bounds=\(bounds)")
        }

        let copy = try Data(contentsOf: packetURL)
        var tampered = copy
        tampered[tampered.count - 1] ^= 0x01
        let tamperedURL = root.appendingPathComponent("title/title-font-tampered.getf")
        try tampered.write(to: tamperedURL, options: .atomic)
        do {
            _ = try GoldenEyeTitleFontPacket.load(from: tamperedURL)
            preconditionFailure("tampered title font packet was accepted")
        } catch GoldenEyeTitleFontPacket.Error.hashMismatch {
            evidence.append("tamper=hash-mismatch")
        }

        let line = evidence.joined(separator: "\n") + "\n"
            + "font_packet_sha256=f9b4fe4730619cd955b353583c549c133b0a4e50755fe82f6b5bd1a7e45c80f3\n"
            + "catalog_packet_sha256=9f11305b9f9fb2d7ce4a2d66728a36bbcd5b37d754edd57a8028ad3794651c56\n"
            + "runtime_rom_access=false\nvisual_parity=not-claimed\n"
        try line.write(toFile: "/tmp/goldeneye-m16-title-text.log", atomically: true, encoding: .utf8)
        print("goldeneye_title_text_packet_smoke: PASS")
        print(line, terminator: "")
    }
}
