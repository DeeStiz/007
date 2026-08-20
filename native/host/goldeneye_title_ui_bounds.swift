import Foundation

/// Source control/icon bounds retained alongside the direct text packet.
/// These are interaction/layout facts from ``src/game/front.c`` and
/// ``assets/oddtextures.c``.  The guarded GETI packet now carries the
/// decoded icon pixels; these records remain layout evidence rather than a
/// claim of full source display-list/material parity.
enum GoldenEyeTitleUIBounds {
    static func records(
        screen: UInt32,
        catalog: GoldenEyeTitleCatalogPacket,
        packet: GoldenEyeTitleTextPacket
    ) -> [String] {
        switch screen {
        case 0:
            return [
                "TITLE_STR_07=(220,30,center,center)",
                "TITLE_STR_08=(34,83,left,center)",
                "TITLE_STR_09=(226,84,left,center)",
                "TITLE_STR_10=(226,97,left,center)",
                "TITLE_STR_11=(226,110,left,center)",
                "TITLE_STR_12=(226,122,left,center)",
                "TITLE_STR_13=(227,134,left,center)",
                "TITLE_STR_14=(219,211,left,center)",
                "TITLE_STR_15=(60,169,left,center)",
                "TITLE_STR_16=(60,201,left,center)",
                "TITLE_STR_17=(99,266,left,center)",
                "TITLE_STR_18=(80,280,left,center)",
            ]
        case 5:
            return [
                "IMAGE_SELECTFILE=[49,276,171,294] source=0x7aX0x12",
                "COPYICON=[209,271,241,299] source=0x20X0x1c",
                "DELICON=[319,271,351,299] source=0x20X0x1c",
                "CROSSHAIR1=[204,149,236,181] source=0x20X0x20 cursor=(220,165)",
                "COPY_CONTROL=[209,271,241,299] textAnchor=(247,278)",
                "ERASE_CONTROL=[319,271,351,299] textAnchor=(357,278)",
            ]
        case 6:
            let selectWidth = textWidth(catalog.string(at: 29) ?? "SELECT MISSION\n", packet: packet)
            let multiplayerWidth = textWidth(catalog.string(at: 30) ?? "MULTIPLAYER\n", packet: packet)
            return [
                "MODE_ROW_1=(150,220;170,220)",
                "MODE_ROW_2=(150,252;170,252)",
                "MODE_HIGHLIGHT_1=[148,218,\(format(selectWidth + 175)),234]",
                "MODE_HIGHLIGHT_2=[148,250,\(format(multiplayerWidth + 175)),266]",
            ]
        default:
            return []
        }
    }

    private static func textWidth(_ text: String, packet: GoldenEyeTitleTextPacket) -> Float {
        let defaultGlyph = packet.glyphs[0x48 - 0x21]
        var previous = defaultGlyph
        var width: Float = 0
        var longest: Float = 0
        for byte in text.utf8 {
            if byte == 0x20 {
                width += 5
                previous = defaultGlyph
            } else if byte == 0x0A {
                longest = max(longest, width)
                width = 0
                previous = defaultGlyph
            } else if (0x21...0x7E).contains(byte) {
                let glyph = packet.glyphs[Int(byte) - 0x21]
                let kern = packet.kerning[previous.kerningIndex * 13 + glyph.kerningIndex]
                width += Float(glyph.width) - Float(kern - 1)
                previous = glyph
            }
        }
        return max(longest, width)
    }

    private static func format(_ value: Float) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
