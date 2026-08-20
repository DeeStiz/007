import CryptoKit
import Foundation

/// Runtime value-only view of the source Zurich Bold packet.  The packet is
/// prepared from ``assets/font/fontZurichBold.c``; no ROM, C pointer, or
/// display-list word is retained by this type.
struct GoldenEyeTitleFontPacket: Sendable {
    struct Glyph: Sendable {
        let character: UInt32
        let baseline: Int32
        let height: Int32
        let width: Int32
        let kerningIndex: Int32
        let bitmapOffset: Int
        let bitmapByteCount: Int
        let stride: Int
    }

    enum Error: Swift.Error, CustomStringConvertible {
        case truncated
        case invalid(String)
        case hashMismatch

        var description: String {
            switch self {
            case .truncated: return "title font packet truncated"
            case .invalid(let detail): return "title font packet invalid: \(detail)"
            case .hashMismatch: return "title font packet SHA-256 mismatch"
            }
        }
    }

    let sourceLength: UInt32
    let sourceHash: [UInt8]
    let packetHash: [UInt8]
    let glyphs: [Glyph]
    let kerning: [Int32]
    private let bitmapBytes: [UInt8]

    static func load(from url: URL) throws -> GoldenEyeTitleFontPacket {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let headerSize = 112
        guard data.count >= headerSize else { throw Error.truncated }
        guard Array(data[0..<4]) == Array("GETF".utf8) else { throw Error.invalid("magic") }
        guard readUInt32(data, at: 4) == 1 else { throw Error.invalid("version") }
        let glyphCount = Int(readUInt32(data, at: 8))
        let cellWidth = Int(readUInt32(data, at: 12))
        let cellHeight = Int(readUInt32(data, at: 16))
        let atlasColumns = Int(readUInt32(data, at: 20))
        let atlasRows = Int(readUInt32(data, at: 24))
        let sourceLength = readUInt32(data, at: 28)
        let metricBytes = Int(readUInt32(data, at: 32))
        let kerningBytes = Int(readUInt32(data, at: 36))
        let atlasBytes = Int(readUInt32(data, at: 40))
        guard glyphCount == 94, cellWidth == 16, cellHeight == 16,
              atlasColumns == 16, atlasRows == 6,
              metricBytes == glyphCount * 20,
              kerningBytes == 13 * 13 * 4,
              atlasBytes == atlasColumns * cellWidth * atlasRows * cellHeight else {
            throw Error.invalid("fixed packet dimensions")
        }
        guard readUInt32(data, at: 108) == 0 else { throw Error.invalid("reserved") }
        let sourceHash = Array(data[44..<76])
        let packetHash = Array(data[76..<108])
        var canonical = data
        canonical.replaceSubrange(76..<108, with: repeatElement(UInt8(0), count: 32))
        guard Array(SHA256.hash(data: canonical)) == packetHash else { throw Error.hashMismatch }

        let recordBase = headerSize
        let kerningBase = recordBase + metricBytes
        let bitmapBase = kerningBase + kerningBytes
        guard bitmapBase + atlasBytes == data.count else { throw Error.truncated }

        var glyphs: [Glyph] = []
        glyphs.reserveCapacity(glyphCount)
        var packedBitmaps: [UInt8] = []
        let atlasWidth = atlasColumns * cellWidth
        for index in 0..<glyphCount {
            let offset = recordBase + index * 20
            let sourceIndex = readUInt32(data, at: offset)
            let baseline = readInt32(data, at: offset + 4)
            let height = Int(readUInt32(data, at: offset + 8))
            let width = Int(readUInt32(data, at: offset + 12))
            let kerningIndex = readInt32(data, at: offset + 16)
            guard sourceIndex == UInt32(index), width > 0, width <= cellWidth,
                  height > 0, height <= cellHeight,
                  kerningIndex >= 0, kerningIndex < 13 else {
                throw Error.invalid("glyph \(index) metrics")
            }
            let bitmapOffset = packedBitmaps.count
            let cellX = (index % atlasColumns) * cellWidth
            let cellY = (index / atlasColumns) * cellHeight
            for row in 0..<height {
                let source = bitmapBase + (cellY + row) * atlasWidth + cellX
                guard source + width <= bitmapBase + atlasBytes else { throw Error.truncated }
                packedBitmaps.append(contentsOf: data[source..<(source + width)])
                if width < cellWidth {
                    packedBitmaps.append(contentsOf: repeatElement(UInt8(0), count: cellWidth - width))
                }
            }
            glyphs.append(
                Glyph(
                    // The source chart stores a zero-based table index;
                    // expose the printable ASCII code expected by the
                    // source text renderer after the value-only copy.
                    character: UInt32(0x21 + index),
                    baseline: baseline,
                    height: Int32(height),
                    width: Int32(width),
                    kerningIndex: kerningIndex,
                    bitmapOffset: bitmapOffset,
                    bitmapByteCount: cellWidth * height,
                    stride: cellWidth
                )
            )
        }

        var kerning: [Int32] = []
        kerning.reserveCapacity(13 * 13)
        for index in 0..<(13 * 13) {
            kerning.append(readInt32(data, at: kerningBase + index * 4))
        }
        return GoldenEyeTitleFontPacket(
            sourceLength: sourceLength,
            sourceHash: sourceHash,
            packetHash: packetHash,
            glyphs: glyphs,
            kerning: kerning,
            bitmapBytes: packedBitmaps
        )
    }

    func glyph(for character: Character) -> Glyph? {
        guard let scalar = character.unicodeScalars.first, scalar.isASCII else { return nil }
        let value = Int(scalar.value)
        guard (0x21...0x7E).contains(value) else { return nil }
        return glyphs[value - 0x21]
    }

    func bitmap(for glyph: Glyph) -> ArraySlice<UInt8> {
        bitmapBytes[glyph.bitmapOffset..<(glyph.bitmapOffset + glyph.bitmapByteCount)]
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }

    private static func readInt32(_ data: Data, at offset: Int) -> Int32 {
        Int32(bitPattern: readUInt32(data, at: offset))
    }
}

/// Guarded source LtitleE packet used by the renderer.  Keeping this packet
/// separate from the legacy decoded catalog prevents a runtime fallback to
/// an unverified text source.
struct GoldenEyeTitleCatalogPacket: Sendable {
    enum Error: Swift.Error, CustomStringConvertible {
        case truncated
        case invalid(String)
        case hashMismatch

        var description: String {
            switch self {
            case .truncated: return "title catalog packet truncated"
            case .invalid(let detail): return "title catalog packet invalid: \(detail)"
            case .hashMismatch: return "title catalog packet SHA-256 mismatch"
            }
        }
    }

    let sourceLength: UInt32
    let sourceHash: [UInt8]
    let packetHash: [UInt8]
    let strings: [String]

    static func load(from url: URL) throws -> GoldenEyeTitleCatalogPacket {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let headerSize = 92
        guard data.count >= headerSize else { throw Error.truncated }
        guard Array(data[0..<4]) == Array("GETC".utf8) else { throw Error.invalid("magic") }
        guard readUInt32(data, at: 4) == 1 else { throw Error.invalid("version") }
        let stringCount = Int(readUInt32(data, at: 8))
        let payloadLength = Int(readUInt32(data, at: 12))
        let sourceLength = readUInt32(data, at: 16)
        guard stringCount > 0, stringCount <= 4096,
              payloadLength >= stringCount * 4,
              headerSize + payloadLength == data.count else {
            throw Error.invalid("catalog dimensions")
        }
        guard readUInt32(data, at: 20) == 0, readUInt32(data, at: 88) == 0 else {
            throw Error.invalid("reserved")
        }
        let sourceHash = Array(data[24..<56])
        let packetHash = Array(data[56..<88])
        var canonical = data
        canonical.replaceSubrange(56..<88, with: repeatElement(UInt8(0), count: 32))
        guard Array(SHA256.hash(data: canonical)) == packetHash else { throw Error.hashMismatch }

        let offsetBase = headerSize
        let payloadBase = offsetBase + stringCount * 4
        guard payloadBase <= data.count else { throw Error.truncated }
        var offsets: [Int] = []
        offsets.reserveCapacity(stringCount)
        for index in 0..<stringCount {
            let offset = Int(readUInt32(data, at: offsetBase + index * 4))
            guard offset >= payloadBase, offset < data.count,
                  offsets.last.map({ offset >= $0 }) ?? true else {
                throw Error.invalid("string offset \(index)")
            }
            offsets.append(offset)
        }
        var strings: [String] = []
        strings.reserveCapacity(stringCount)
        for offset in offsets {
            let bytes = data[offset..<data.count]
            guard let nul = bytes.firstIndex(of: 0) else { throw Error.invalid("unterminated string") }
            strings.append(String(decoding: bytes[..<nul], as: UTF8.self))
        }
        return GoldenEyeTitleCatalogPacket(
            sourceLength: sourceLength,
            sourceHash: sourceHash,
            packetHash: packetHash,
            strings: strings
        )
    }

    func string(at index: Int) -> String? {
        strings.indices.contains(index) ? strings[index] : nil
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }
}
