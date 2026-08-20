import CryptoKit
import Foundation

/// Fixed-width GETF packet produced from the tracked Zurich Bold font source.
struct GoldenEyeTitleTextPacket: Sendable {
    static let magic = Array("GETF".utf8)
    static let version: UInt32 = 1
    static let glyphCount = 94
    static let cellWidth = 16
    static let cellHeight = 16
    static let atlasColumns = 16
    static let atlasRows = 6
    static let atlasWidth = cellWidth * atlasColumns
    static let atlasHeight = cellHeight * atlasRows
    static let headerSize = 112

    struct Glyph: Sendable {
        let index: UInt32
        let baseline: Int32
        let height: Int
        let width: Int
        let kerningIndex: Int
    }

    enum Error: Swift.Error, CustomStringConvertible {
        case truncated(String)
        case invalid(String)
        case hashMismatch

        var description: String {
            switch self {
            case .truncated(let value): return "title text packet truncated: \(value)"
            case .invalid(let value): return "title text packet invalid: \(value)"
            case .hashMismatch: return "title text packet SHA-256 mismatch"
            }
        }
    }

    let sourceLength: UInt32
    let sourceHash: [UInt8]
    let packetHash: [UInt8]
    let glyphs: [Glyph]
    let kerning: [Int32]
    let atlas: [UInt8]

    static func load(from url: URL) throws -> GoldenEyeTitleTextPacket {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count >= headerSize else { throw Error.truncated("header") }
        guard Array(data[0..<4]) == magic else { throw Error.invalid("magic") }
        guard readUInt32(data, at: 4) == version else { throw Error.invalid("version") }
        let count = Int(readUInt32(data, at: 8))
        let cellWidth = Int(readUInt32(data, at: 12))
        let cellHeight = Int(readUInt32(data, at: 16))
        let columns = Int(readUInt32(data, at: 20))
        let rows = Int(readUInt32(data, at: 24))
        let sourceLength = readUInt32(data, at: 28)
        let metricBytes = Int(readUInt32(data, at: 32))
        let kerningBytes = Int(readUInt32(data, at: 36))
        let atlasBytes = Int(readUInt32(data, at: 40))
        guard count == glyphCount, cellWidth == Self.cellWidth, cellHeight == Self.cellHeight,
              columns == atlasColumns, rows == atlasRows,
              metricBytes == count * 20, kerningBytes == 169 * 4,
              atlasBytes == atlasWidth * atlasHeight else {
            throw Error.invalid("fixed packet dimensions")
        }
        guard readUInt32(data, at: 108) == 0 else { throw Error.invalid("reserved") }
        let sourceHash = Array(data[44..<76])
        let packetHash = Array(data[76..<108])
        var canonical = data
        canonical.replaceSubrange(76..<108, with: repeatElement(UInt8(0), count: 32))
        guard Array(SHA256.hash(data: canonical)) == packetHash else { throw Error.hashMismatch }
        let metricBase = headerSize
        let kerningBase = metricBase + metricBytes
        let atlasBase = kerningBase + kerningBytes
        guard atlasBase + atlasBytes == data.count else { throw Error.truncated("payload") }

        var glyphs: [Glyph] = []
        for index in 0..<count {
            let offset = metricBase + index * 20
            let glyph = Glyph(
                index: readUInt32(data, at: offset),
                baseline: Int32(bitPattern: readUInt32(data, at: offset + 4)),
                height: Int(readUInt32(data, at: offset + 8)),
                width: Int(readUInt32(data, at: offset + 12)),
                kerningIndex: Int(Int32(bitPattern: readUInt32(data, at: offset + 16)))
            )
            guard glyph.index == UInt32(index), glyph.width > 0, glyph.width <= cellWidth,
                  glyph.height > 0, glyph.height <= cellHeight,
                  (0..<13).contains(glyph.kerningIndex) else {
                throw Error.invalid("glyph \(index) metrics")
            }
            glyphs.append(glyph)
        }
        var kerning: [Int32] = []
        for index in 0..<169 {
            kerning.append(Int32(bitPattern: readUInt32(data, at: kerningBase + index * 4)))
        }
        return GoldenEyeTitleTextPacket(
            sourceLength: sourceLength,
            sourceHash: sourceHash,
            packetHash: packetHash,
            glyphs: glyphs,
            kerning: kerning,
            atlas: Array(data[atlasBase..<atlasBase + atlasBytes])
        )
    }

    func intensity(glyph: Int, row: Int, column: Int) -> UInt8 {
        guard glyphs.indices.contains(glyph), row >= 0, row < glyphs[glyph].height,
              column >= 0, column < glyphs[glyph].width else { return 0 }
        let x = (glyph % Self.atlasColumns) * Self.cellWidth + column
        let y = (glyph / Self.atlasColumns) * Self.cellHeight + row
        return atlas[y * Self.atlasWidth + x]
    }

    func makeGeometry(screen: UInt32, catalog: GoldenEyeTitleCatalogPacket) throws -> GoldenEyeTitleTextGeometry {
        let placements: [(Int, Float, Float, Bool, Bool)]
        switch screen {
        case 0:
            placements = [
                (7, 220, 30, true, true), (8, 34, 83, false, true), (9, 226, 84, false, true),
                (10, 226, 97, false, true), (11, 226, 110, false, true), (12, 226, 122, false, true),
                (13, 227, 134, false, true), (14, 219, 211, false, true), (15, 60, 169, false, true),
                (16, 60, 201, false, true), (17, 99, 266, false, true), (18, 80, 280, false, true),
            ]
        case 5:
            // SELECTFILE is a source IA8 image rather than an LtitleE
            // string. The GETI icon lane binds that image when available;
            // retain the readable fixed-font label as a bounded fallback.
            // SELECTFILE is rendered by the source-derived GETI image lane;
            // only the Copy/Erase catalog strings remain in this text pass.
            placements = [(27, 247, 278, false, false), (28, 357, 278, false, false)]
        case 6:
            placements = [(29, 170, 220, false, false), (30, 170, 252, false, false)]
        default:
            placements = []
        }
        var vertices: [GoldenEyeTitleGeometryGPUVertex] = []
        var indices: [UInt32] = []
        var glyphCount = 0
        var pixelQuadCount = 0
        let defaultGlyph = glyphs[0x48 - 0x21]
        for (stringID, anchorX, anchorY, centerX, centerY) in placements {
            let text: String
            if stringID == -1 {
                text = "SELECT FILE"
            } else {
                guard let catalogText = catalog.string(at: stringID) else { continue }
                text = catalogText
            }
            let size = measure(text)
            let startX = centerX ? anchorX - size.width * 0.5 : anchorX
            let startY = centerY ? anchorY - size.height * 0.5 : anchorY
            var cursorX = startX
            var cursorY = startY
            var previous = defaultGlyph
            for byte in text.utf8 {
                if byte == 0x20 { cursorX += 5; previous = defaultGlyph; continue }
                if byte == 0x0A { cursorX = startX; cursorY += 14; previous = defaultGlyph; continue }
                guard (0x21...0x7E).contains(byte) else { continue }
                let glyphIndex = Int(byte) - 0x21
                let glyph = glyphs[glyphIndex]
                let kern = kerning[previous.kerningIndex * 13 + glyph.kerningIndex]
                cursorX -= Float(kern - 1)
                glyphCount += 1
                for row in 0..<glyph.height {
                    var column = 0
                    while column < glyph.width {
                        let value = intensity(glyph: glyphIndex, row: row, column: column)
                        guard value != 0 else { column += 1; continue }
                        var run = 1
                        while column + run < glyph.width,
                              intensity(glyph: glyphIndex, row: row, column: column + run) == value { run += 1 }
                        let x0 = cursorX + Float(column)
                        let x1 = x0 + Float(run)
                        let y0 = cursorY + Float(glyph.baseline) + Float(row)
                        let y1 = y0 + 1
                        let color = SIMD4<Float>(repeating: Float(value) / 255)
                        let base = UInt32(vertices.count)
                        func clip(_ x: Float, _ y: Float) -> SIMD2<Float> { SIMD2(x / 440 * 2 - 1, 1 - y / 330 * 2) }
                        vertices.append(GoldenEyeTitleGeometryGPUVertex(position: clip(x0, y0), color: color))
                        vertices.append(GoldenEyeTitleGeometryGPUVertex(position: clip(x1, y0), color: color))
                        vertices.append(GoldenEyeTitleGeometryGPUVertex(position: clip(x0, y1), color: color))
                        vertices.append(GoldenEyeTitleGeometryGPUVertex(position: clip(x1, y1), color: color))
                        indices.append(contentsOf: [base, base + 1, base + 2, base + 2, base + 1, base + 3])
                        pixelQuadCount += 1
                        column += run
                    }
                }
                cursorX += Float(glyph.width)
                previous = glyph
            }
        }
        return GoldenEyeTitleTextGeometry(
            vertices: vertices,
            indices: indices,
            glyphCount: glyphCount,
            pixelQuadCount: pixelQuadCount,
            bounds: GoldenEyeTitleUIBounds.records(screen: screen, catalog: catalog, packet: self)
        )
    }

    private func measure(_ text: String) -> (width: Float, height: Float) {
        var previous = glyphs[0x48 - 0x21]
        var lineWidth: Float = 0
        var longest: Float = 0
        // Source textMeasure increments height when it consumes a newline;
        // a trailing LtitleE newline still represents one rendered line.
        var lines: Float = 0
        for byte in text.utf8 {
            if byte == 0x20 { lineWidth += 5; previous = glyphs[0x48 - 0x21] }
            else if byte == 0x0A { longest = max(longest, lineWidth); lineWidth = 0; lines += 1; previous = glyphs[0x48 - 0x21] }
            else if (0x21...0x7E).contains(byte) {
                let glyph = glyphs[Int(byte) - 0x21]
                let kern = kerning[previous.kerningIndex * 13 + glyph.kerningIndex]
                lineWidth += Float(glyph.width) - Float(Int(kern) - 1)
                previous = glyph
            }
        }
        return (max(longest, lineWidth), max(14, max(1, lines) * 14))
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
    }
}

struct GoldenEyeTitleTextGeometry: Sendable {
    let vertices: [GoldenEyeTitleGeometryGPUVertex]
    let indices: [UInt32]
    let glyphCount: Int
    let pixelQuadCount: Int
    let bounds: [String]
}
