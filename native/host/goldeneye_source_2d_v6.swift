import CryptoKit
import Foundation

/// Value-only source frontend 2D resources.  These records intentionally keep
/// the decoded pixels and source metrics separate from any Metal object.  A
/// renderer may upload them, but the source 2D frame itself contains only
/// fixed-width values and deterministic record IDs.
public struct GoldenEyeSourceFontV6: Sendable, Equatable {
    public struct Glyph: Sendable, Equatable {
        public let character: UInt32
        public let sourceIndex: UInt32
        public let baseline: Int32
        public let height: Int32
        public let width: Int32
        public let kerningIndex: Int32
        public let stride: Int32
        public let pixels: [UInt8]

        public var bitmapByteCount: Int { pixels.count }
    }

    public let id: UInt32
    public let sourceRecordID: UInt32
    public let kerningRecordID: UInt32
    public let glyphs: [Glyph]
    public let kerning: [Int32]
    public let sourceSHA256: String
    public let payloadSHA256: String

    public func glyph(forASCII ascii: UInt8) -> Glyph? {
        guard (0x21...0x7e).contains(ascii) else { return nil }
        let index = Int(ascii - 0x21)
        return glyphs.indices.contains(index) ? glyphs[index] : nil
    }

    public func kerningValue(previous: Glyph, current: Glyph) -> Int32 {
        let row = Int(previous.kerningIndex)
        let column = Int(current.kerningIndex)
        guard (0..<13).contains(row), (0..<13).contains(column) else { return 0 }
        return kerning[row * 13 + column]
    }
}

/// A source image used by a texture-rectangle operation.  `pixels` is the
/// catalog's decoded RGBA8 payload, never a source-text descriptor.
public struct GoldenEyeSourceIconV6: Sendable, Equatable {
    public let sourceRecordID: UInt32
    public let sourceName: String
    public let width: UInt32
    public let height: UInt32
    public let pixels: [UInt8]
    public let decodedSHA256: String
}

public enum GoldenEyeSource2DFontIDV6: UInt32, Sendable, Equatable {
    case zurichBold = 1
    case bankGothic = 2
}

public enum GoldenEyeSource2DIconIDV6: UInt32, CaseIterable, Sendable, Equatable {
    case copy = 0
    case erase = 1
    case selectFile = 2
    case crosshair = 3
    case check = 4
    case dot = 5
    case cursorX = 6

    public var sourceName: String {
        switch self {
        case .copy: return "COPYICON"
        case .erase: return "DELICON"
        case .selectFile: return "SELECTFILE"
        case .crosshair: return "CROSSHAIR1"
        case .check: return "CHECK"
        case .dot: return "DOT"
        case .cursorX: return "X"
        }
    }
}

public enum GoldenEyeSource2DError: Error, Sendable, Equatable, CustomStringConvertible {
    case missingPayload(category: String, family: String, name: String)
    case preparationGap(category: String, family: String, name: String, evidence: String)
    case malformedPayload(String)
    case invalidSourceEvent(String)
    case unsupportedVisibleEvent(UInt32)
    case missingText(UInt32)

    public var description: String {
        switch self {
        case let .missingPayload(category, family, name):
            return "source 2D V6 payload is missing: \(category)/\(family)/\(name)"
        case let .preparationGap(category, family, name, evidence):
            return "source 2D V6 preparation gap: \(category)/\(family)/\(name): \(evidence)"
        case let .malformedPayload(detail):
            return "source 2D V6 payload is malformed: \(detail)"
        case let .invalidSourceEvent(detail):
            return "source 2D V6 source event is invalid: \(detail)"
        case let .unsupportedVisibleEvent(operation):
            return "source 2D V6 visible render operation is unsupported: \(operation)"
        case let .missingText(id):
            return "source 2D V6 text catalog entry is missing: \(id)"
        }
    }
}

/// The complete decoded frontend 2D dependency set.  The default initializer
/// requires every production icon plus both source fonts.  Callers may pass a
/// narrower requirement set only for an explicit screen-specific test; a
/// missing row always throws a typed preparation gap rather than selecting a
/// procedural or block-font replacement.
public struct GoldenEyeSource2DAssetsV6: Sendable, Equatable {
    public let zurichBold: GoldenEyeSourceFontV6
    public let bankGothic: GoldenEyeSourceFontV6
    public let textStrings: [String]
    public let icons: [GoldenEyeSource2DIconIDV6: GoldenEyeSourceIconV6]
    public let fileModeBackground: GoldenEyeSourceIconV6
    public let textCatalogRecordID: UInt32
    public let iconRecordIDs: [GoldenEyeSource2DIconIDV6: UInt32]

    public init(
        catalog: GoldenEyeSourceFrontendCatalog,
        requiredIcons: [GoldenEyeSource2DIconIDV6] = GoldenEyeSource2DIconIDV6.allCases
    ) throws {
        let zurichPacket = try Self.copyCatalogPayload(
            catalog,
            kind: .font,
            name: "title-font.getf",
            family: "frontend",
            expectedCategory: "font_packet"
        )
        let zurichRecord = try catalog.record(kind: .font, name: "title-font.getf", family: "frontend")
        zurichBold = try Self.parseGETF(
            zurichPacket,
            id: UInt32(GoldenEyeSource2DFontIDV6.zurichBold.rawValue),
            sourceRecordID: zurichRecord.id,
            kerningRecordID: 0,
            sourceSHA256: zurichRecord.sourceSHA256,
            payloadSHA256: zurichRecord.decodedSHA256
        )

        let bankChart = try Self.copyCatalogPayload(
            catalog,
            kind: .font,
            name: "fontBankGothic_fontchartable.bin",
            family: "frontend",
            expectedCategory: "font_payload"
        )
        let bankKerning = try Self.copyCatalogPayload(
            catalog,
            kind: .font,
            name: "fontBankGothic_kerning.bin",
            family: "frontend",
            expectedCategory: "font_payload"
        )
        let bankChartRecord = try catalog.record(kind: .font, name: "fontBankGothic_fontchartable.bin", family: "frontend")
        let bankKerningRecord = try catalog.record(kind: .font, name: "fontBankGothic_kerning.bin", family: "frontend")
        bankGothic = try Self.parseSourceFont(
            chartAndPixels: bankChart,
            kerningData: bankKerning,
            id: UInt32(GoldenEyeSource2DFontIDV6.bankGothic.rawValue),
            sourceRecordID: bankChartRecord.id,
            kerningRecordID: bankKerningRecord.id,
            sourceSHA256: bankChartRecord.sourceSHA256,
            payloadSHA256: Self.combineDigests(bankChartRecord.decodedSHA256, bankKerningRecord.decodedSHA256)
        )

        let catalogRecord = try catalog.record(kind: .font, name: "LtitleE.gecat", family: "frontend")
        guard catalogRecord.category == "text_catalog" else {
            throw GoldenEyeSource2DError.preparationGap(
                category: "text_catalog", family: "frontend", name: "LtitleE.gecat",
                evidence: "resolved category=\(catalogRecord.category), expected text_catalog"
            )
        }
        let textPacket = try catalog.copyOut(.decoded, for: catalogRecord)
        textStrings = try Self.parseGETC(textPacket)
        guard textStrings.count == 302 else {
            throw GoldenEyeSource2DError.malformedPayload("GETC string count \(textStrings.count) != 302")
        }
        textCatalogRecordID = catalogRecord.id

        var loadedIcons: [GoldenEyeSource2DIconIDV6: GoldenEyeSourceIconV6] = [:]
        var recordIDs: [GoldenEyeSource2DIconIDV6: UInt32] = [:]
        for icon in requiredIcons {
            let name = "\(icon.sourceName).payload"
            let record: GoldenEyeSourceFrontendRecord
            do {
                record = try catalog.record(kind: .texture, name: name, family: "frontend")
            } catch {
                throw GoldenEyeSource2DError.preparationGap(
                    category: "texture_payload", family: "frontend", name: name,
                    evidence: "consumable decoded RGBA8 icon row is absent; source image descriptors are not renderable"
                )
            }
            guard record.category == "texture_payload",
                  record.flags.contains("GLOBAL_TEXTURE_PAYLOAD"),
                  record.flags.contains("DECODED_RGBA8_BASE_LEVEL") else {
                throw GoldenEyeSource2DError.preparationGap(
                    category: record.category, family: record.family, name: record.name,
                    evidence: "required GLOBAL_TEXTURE_PAYLOAD + DECODED_RGBA8_BASE_LEVEL flags are absent"
                )
            }
            let metadata = try Self.objectMetadata(record, context: name)
            let width = try Self.metadataUInt(metadata, key: "width", context: name)
            let height = try Self.metadataUInt(metadata, key: "height", context: name)
            guard width > 0, height > 0, width <= UInt64(UInt32.max), height <= UInt64(UInt32.max) else {
                throw GoldenEyeSource2DError.malformedPayload("icon \(name) dimensions")
            }
            let expected = width.multipliedReportingOverflow(by: height)
            guard !expected.overflow else { throw GoldenEyeSource2DError.malformedPayload("icon \(name) dimension overflow") }
            let expectedBytes = expected.partialValue.multipliedReportingOverflow(by: 4)
            guard !expectedBytes.overflow, expectedBytes.partialValue == UInt64(record.decodedSize) else {
                throw GoldenEyeSource2DError.malformedPayload("icon \(name) decoded RGBA8 byte count")
            }
            let pixels = try catalog.copyOut(.decoded, for: record)
            guard pixels.count == Int(expectedBytes.partialValue) else {
                throw GoldenEyeSource2DError.malformedPayload("icon \(name) copy-out byte count")
            }
            guard pixels.contains(where: { $0 != 0 }) else {
                throw GoldenEyeSource2DError.preparationGap(
                    category: record.category, family: record.family, name: record.name,
                    evidence: "decoded RGBA8 payload is entirely zero (record=\(record.id), source_sha256=\(record.sourceSHA256), decoded_sha256=\(record.decodedSHA256), decoded_size=\(record.decodedSize)); tex2png produced no visible pixels"
                )
            }
            guard metadata["source_row"] == .string(icon.sourceName) else {
                throw GoldenEyeSource2DError.malformedPayload("icon \(name) source-row linkage")
            }
            let value = GoldenEyeSourceIconV6(
                sourceRecordID: record.id,
                sourceName: icon.sourceName,
                width: UInt32(width),
                height: UInt32(height),
                pixels: Array(pixels),
                decodedSHA256: record.decodedSHA256
            )
            loadedIcons[icon] = value
            recordIDs[icon] = record.id
        }
        icons = loadedIcons
        iconRecordIDs = recordIDs

        let backgroundRecord = try catalog.record(
            kind: .background,
            name: "gunbarrel-background",
            family: "gunbarrel"
        )
        let background = try GoldenEyeFileModeBackgroundContractV6(
            encoded: catalog.copyOut(.decoded, for: backgroundRecord)
        )
        fileModeBackground = GoldenEyeSourceIconV6(
            sourceRecordID: backgroundRecord.id,
            sourceName: "gunbarrel-background",
            width: UInt32(GoldenEyeFileModeBackgroundContractV6.width),
            height: UInt32(GoldenEyeFileModeBackgroundContractV6.height),
            pixels: background.compositedPixels,
            decodedSHA256: SHA256.hash(data: Data(background.compositedPixels)).map { String(format: "%02x", $0) }.joined()
        )
    }

    public func font(_ id: GoldenEyeSource2DFontIDV6) -> GoldenEyeSourceFontV6 {
        id == .zurichBold ? zurichBold : bankGothic
    }

    public func icon(_ id: GoldenEyeSource2DIconIDV6) throws -> GoldenEyeSourceIconV6 {
        guard let value = icons[id] else {
            throw GoldenEyeSource2DError.preparationGap(
                category: "texture_payload", family: "frontend", name: "\(id.sourceName).payload",
                evidence: "icon was not included in the explicit asset requirement set"
            )
        }
        return value
    }

    public func text(id: UInt32) throws -> String {
        guard id < UInt32(textStrings.count) else { throw GoldenEyeSource2DError.missingText(id) }
        return textStrings[Int(id)]
    }

    private static func copyCatalogPayload(
        _ catalog: GoldenEyeSourceFrontendCatalog,
        kind: GoldenEyeSourceFrontendResourceKind,
        name: String,
        family: String,
        expectedCategory: String
    ) throws -> Data {
        let record: GoldenEyeSourceFrontendRecord
        do {
            record = try catalog.record(kind: kind, name: name, family: family)
        } catch {
            throw GoldenEyeSource2DError.preparationGap(
                category: expectedCategory, family: family, name: name,
                evidence: "required consumable payload record is absent: \(error)"
            )
        }
        guard record.category == expectedCategory else {
            throw GoldenEyeSource2DError.preparationGap(
                category: expectedCategory, family: family, name: name,
                evidence: "resolved category=\(record.category), expected \(expectedCategory)"
            )
        }
        do {
            return try catalog.copyOut(.decoded, for: record)
        } catch {
            throw GoldenEyeSource2DError.preparationGap(
                category: record.category, family: record.family, name: record.name,
                evidence: "decoded copy-out rejected: \(error)"
            )
        }
    }

    private static func objectMetadata(
        _ record: GoldenEyeSourceFrontendRecord,
        context: String
    ) throws -> [String: GoldenEyeSourceFrontendJSONValue] {
        guard case let .object(value) = record.metadata else {
            throw GoldenEyeSource2DError.malformedPayload("\(context) metadata is not an object")
        }
        return value
    }

    private static func metadataUInt(
        _ metadata: [String: GoldenEyeSourceFrontendJSONValue],
        key: String,
        context: String
    ) throws -> UInt64 {
        guard let value = metadata[key], case let .integer(integer) = value,
              integer >= 0 else {
            throw GoldenEyeSource2DError.malformedPayload("\(context) metadata.\(key)")
        }
        return UInt64(integer)
    }

    private static func parseGETF(
        _ data: Data,
        id: UInt32,
        sourceRecordID: UInt32,
        kerningRecordID: UInt32,
        sourceSHA256: String,
        payloadSHA256: String
    ) throws -> GoldenEyeSourceFontV6 {
        let headerSize = 112
        guard data.count >= headerSize else { throw GoldenEyeSource2DError.malformedPayload("GETF header truncated") }
        guard data[0..<4] == Data("GETF".utf8), readLE32(data, at: 4) == 1 else {
            throw GoldenEyeSource2DError.malformedPayload("GETF magic/version")
        }
        let glyphCount = Int(readLE32(data, at: 8))
        let cellWidth = Int(readLE32(data, at: 12))
        let cellHeight = Int(readLE32(data, at: 16))
        let columns = Int(readLE32(data, at: 20))
        let rows = Int(readLE32(data, at: 24))
        let metricBytes = Int(readLE32(data, at: 32))
        let kerningBytes = Int(readLE32(data, at: 36))
        let atlasBytes = Int(readLE32(data, at: 40))
        guard glyphCount == 94, cellWidth == 16, cellHeight == 16,
              columns == 16, rows == 6, metricBytes == 94 * 20,
              kerningBytes == 169 * 4, atlasBytes == 16 * 16 * 16 * 6,
              readLE32(data, at: 108) == 0 else {
            throw GoldenEyeSource2DError.malformedPayload("GETF fixed dimensions/reserved")
        }
        let packetDigest = Data(data[76..<108])
        var canonical = data
        canonical.replaceSubrange(76..<108, with: Data(repeating: 0, count: 32))
        guard Data(SHA256.hash(data: canonical)) == packetDigest else {
            throw GoldenEyeSource2DError.malformedPayload("GETF packet digest")
        }
        let metricBase = headerSize
        let kerningBase = metricBase + metricBytes
        let atlasBase = kerningBase + kerningBytes
        guard atlasBase + atlasBytes == data.count else {
            throw GoldenEyeSource2DError.malformedPayload("GETF payload bounds")
        }
        var glyphs: [GoldenEyeSourceFontV6.Glyph] = []
        glyphs.reserveCapacity(glyphCount)
        for index in 0..<glyphCount {
            let offset = metricBase + index * 20
            let sourceIndex = readLE32(data, at: offset)
            let baseline = Int32(bitPattern: readLE32(data, at: offset + 4))
            let height = Int(readLE32(data, at: offset + 8))
            let width = Int(readLE32(data, at: offset + 12))
            let kerningIndex = Int32(bitPattern: readLE32(data, at: offset + 16))
            guard sourceIndex == UInt32(index), width > 0, width <= cellWidth,
                  height > 0, height <= cellHeight, (0..<13).contains(Int(kerningIndex)) else {
                throw GoldenEyeSource2DError.malformedPayload("GETF glyph \(index) metrics")
            }
            var pixels: [UInt8] = []
            pixels.reserveCapacity(width * height)
            let cellX = (index % columns) * cellWidth
            let cellY = (index / columns) * cellHeight
            for row in 0..<height {
                let source = atlasBase + (cellY + row) * (columns * cellWidth) + cellX
                pixels.append(contentsOf: data[source..<(source + width)])
            }
            glyphs.append(.init(
                character: UInt32(0x21 + index), sourceIndex: sourceIndex,
                baseline: baseline, height: Int32(height), width: Int32(width),
                kerningIndex: kerningIndex, stride: Int32(width), pixels: pixels
            ))
        }
        var kerning: [Int32] = []
        kerning.reserveCapacity(169)
        for index in 0..<169 {
            kerning.append(Int32(bitPattern: readLE32(data, at: kerningBase + index * 4)))
        }
        return GoldenEyeSourceFontV6(
            id: id, sourceRecordID: sourceRecordID, kerningRecordID: kerningRecordID,
            glyphs: glyphs, kerning: kerning,
            sourceSHA256: sourceSHA256, payloadSHA256: payloadSHA256
        )
    }

    private static func parseSourceFont(
        chartAndPixels data: Data,
        kerningData: Data,
        id: UInt32,
        sourceRecordID: UInt32,
        kerningRecordID: UInt32,
        sourceSHA256: String,
        payloadSHA256: String
    ) throws -> GoldenEyeSourceFontV6 {
        let chartWordCount = 94 * 6
        guard data.count >= chartWordCount * 4, data.count % 4 == 0,
              kerningData.count == 169 * 4 else {
            throw GoldenEyeSource2DError.malformedPayload("source font chart/kerning dimensions")
        }
        let words = (0..<(data.count / 4)).map { readBE32(data, at: $0 * 4) }
        let fontBase = UInt32(0xB80)
        var glyphs: [GoldenEyeSourceFontV6.Glyph] = []
        glyphs.reserveCapacity(94)
        let pixelBase = chartWordCount * 4
        let fontBytes = data[pixelBase..<data.count]
        for index in 0..<94 {
            let base = index * 6
            let sourceIndex = words[base]
            let baseline = Int32(bitPattern: words[base + 1])
            let height = Int(words[base + 2])
            let width = Int(words[base + 3])
            let kerningIndex = Int32(bitPattern: words[base + 4])
            let offset = words[base + 5]
            guard sourceIndex < 0x80, width > 0, width <= 16, height > 0, height <= 16,
                  (0..<13).contains(Int(kerningIndex)), offset >= fontBase else {
                throw GoldenEyeSource2DError.malformedPayload("source font glyph \(index) metrics")
            }
            let rowStride = (width + 7) & 0xF8
            let pixelOffset = Int(offset - fontBase) + 12
            let pixelEnd = pixelOffset.addingReportingOverflow(rowStride * height)
            guard pixelOffset >= 0, !pixelEnd.overflow, pixelEnd.partialValue <= fontBytes.count else {
                throw GoldenEyeSource2DError.malformedPayload("source font glyph \(index) pixels")
            }
            var pixels: [UInt8] = []
            pixels.reserveCapacity(rowStride * height)
            for row in 0..<height {
                let rowStart = pixelOffset + row * rowStride
                // Data slices retain the parent index space.  Index the
                // original packet with the explicit payload base instead of
                // treating the slice as zero-based.
                let sourceStart = pixelBase + rowStart
                pixels.append(contentsOf: data[sourceStart..<(sourceStart + rowStride)])
            }
            glyphs.append(.init(
                character: UInt32(0x21 + index), sourceIndex: sourceIndex,
                baseline: baseline, height: Int32(height), width: Int32(width),
                kerningIndex: kerningIndex, stride: Int32(rowStride), pixels: pixels
            ))
        }
        let kerning = (0..<169).map { index in
            Int32(bitPattern: readBE32(kerningData, at: index * 4))
        }
        return GoldenEyeSourceFontV6(
            id: id, sourceRecordID: sourceRecordID, kerningRecordID: kerningRecordID,
            glyphs: glyphs, kerning: kerning,
            sourceSHA256: sourceSHA256, payloadSHA256: payloadSHA256
        )
    }

    private static func parseGETC(_ data: Data) throws -> [String] {
        let headerSize = 92
        guard data.count >= headerSize, data[0..<4] == Data("GETC".utf8), readLE32(data, at: 4) == 1 else {
            throw GoldenEyeSource2DError.malformedPayload("GETC header")
        }
        let count = Int(readLE32(data, at: 8))
        let payloadLength = Int(readLE32(data, at: 12))
        guard count > 0, count <= 4096, payloadLength >= count * 4,
              headerSize + payloadLength == data.count,
              readLE32(data, at: 20) == 0, readLE32(data, at: 88) == 0 else {
            throw GoldenEyeSource2DError.malformedPayload("GETC dimensions/reserved")
        }
        let digest = Data(data[56..<88])
        var canonical = data
        canonical.replaceSubrange(56..<88, with: Data(repeating: 0, count: 32))
        guard Data(SHA256.hash(data: canonical)) == digest else {
            throw GoldenEyeSource2DError.malformedPayload("GETC packet digest")
        }
        let payloadBase = headerSize + count * 4
        var offsets: [Int] = []
        offsets.reserveCapacity(count)
        for index in 0..<count {
            let offset = Int(readLE32(data, at: headerSize + index * 4))
            guard offset >= payloadBase, offset < data.count,
                  offsets.last.map({ offset >= $0 }) ?? true else {
                throw GoldenEyeSource2DError.malformedPayload("GETC offset \(index)")
            }
            offsets.append(offset)
        }
        return try offsets.map { offset in
            let bytes = data[offset..<data.count]
            guard let nul = bytes.firstIndex(of: 0) else {
                throw GoldenEyeSource2DError.malformedPayload("GETC unterminated string")
            }
            return String(decoding: bytes[..<nul], as: UTF8.self)
        }
    }

    private static func combineDigests(_ first: String, _ second: String) -> String {
        let data = Data((first + second).utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func readLE32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
    }

    private static func readBE32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) << 24 | UInt32(data[offset + 1]) << 16
            | UInt32(data[offset + 2]) << 8 | UInt32(data[offset + 3])
    }
}

public struct GoldenEyeSource2DRectV6: Sendable, Equatable {
    public let x: Int32
    public let y: Int32
    public let width: UInt32
    public let height: UInt32

    public init(x: Int32, y: Int32, width: UInt32, height: UInt32) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    public static let sourceCanvas = Self(x: 0, y: 0, width: 440, height: 330)
}

public struct GoldenEyeSource2DScissorV6: Sendable, Equatable {
    public let rect: GoldenEyeSource2DRectV6
    public init(_ rect: GoldenEyeSource2DRectV6 = .sourceCanvas) { self.rect = rect }
}

public struct GoldenEyeSource2DFillV6: Sendable, Equatable {
    public let rect: GoldenEyeSource2DRectV6
    public let scissor: GoldenEyeSource2DScissorV6
    public let rgba: UInt32
    public let flags: UInt32
    public let sequence: UInt64
}

public struct GoldenEyeSource2DTextureRectV6: Sendable, Equatable {
    public let resourceRecordID: UInt32
    public let rect: GoldenEyeSource2DRectV6
    public let scissor: GoldenEyeSource2DScissorV6
    public let u0Q16: UInt32
    public let v0Q16: UInt32
    public let u1Q16: UInt32
    public let v1Q16: UInt32
    public let tintRGBA: UInt32
    public let flags: UInt32
    public let sequence: UInt64
}

public struct GoldenEyeSource2DGlyphV6: Sendable, Equatable {
    public let fontID: UInt32
    public let fontRecordID: UInt32
    public let glyphIndex: UInt32
    public let character: UInt32
    public let x: Int32
    public let y: Int32
    public let width: UInt32
    public let height: UInt32
    public let baseline: Int32
    public let scissor: GoldenEyeSource2DScissorV6
    public let rgba: UInt32
    public let stringID: UInt32
    public let flags: UInt32
    public let sequence: UInt64
}

public struct GoldenEyeSource2DTextEventV6: Sendable, Equatable {
    public let screen: UInt32
    public let textID: UInt32
    public let x: Int32
    public let y: Int32
    public let nativeTick: UInt64
    public let sourceTimer: UInt32
    public let flags: UInt32
    public let sequence: UInt64

    public init(screen: UInt32, textID: UInt32, x: Int32, y: Int32, nativeTick: UInt64 = 0, sourceTimer: UInt32 = 0, flags: UInt32 = 0, sequence: UInt64 = 0) {
        self.screen = screen; self.textID = textID; self.x = x; self.y = y
        self.nativeTick = nativeTick; self.sourceTimer = sourceTimer; self.flags = flags; self.sequence = sequence
    }
}

public struct GoldenEyeSource2DRenderEventV6: Sendable, Equatable {
    public let screen: UInt32
    public let operation: UInt32
    public let subphase: UInt32
    public let nativeTick: UInt64
    public let referenceTick: UInt64
    public let sourceTimer: UInt32
    public let value0: Int32
    public let value1: Int32
    public let flags: UInt32
    public let sequence: UInt64

    public init(screen: UInt32, operation: UInt32, subphase: UInt32 = 0, nativeTick: UInt64 = 0, referenceTick: UInt64 = 0, sourceTimer: UInt32 = 0, value0: Int32 = 0, value1: Int32 = 0, flags: UInt32 = 0, sequence: UInt64 = 0) {
        self.screen = screen; self.operation = operation; self.subphase = subphase
        self.nativeTick = nativeTick; self.referenceTick = referenceTick; self.sourceTimer = sourceTimer
        self.value0 = value0; self.value1 = value1; self.flags = flags; self.sequence = sequence
    }
}

public struct GoldenEyeSource2DFrameV6: Sendable, Equatable {
    public let screen: UInt32
    public let nativeTick: UInt64
    public let sourceTimer: UInt32
    public let logicalWidth: UInt32
    public let logicalHeight: UInt32
    public let scissor: GoldenEyeSource2DScissorV6
    public let fills: [GoldenEyeSource2DFillV6]
    public let textureRects: [GoldenEyeSource2DTextureRectV6]
    public let glyphs: [GoldenEyeSource2DGlyphV6]
    public let unsupportedVisibleCount: UInt32
    public let frameHash: UInt64
}

/// Deterministic source 2D lowering.  The coordinate and text placement
/// constants below are copied from `legalpage_text_array` and the frontend
/// constructors in `src/game/front.c`; they are not approximations of the
/// source layout.
public struct GoldenEyeSource2DLowererV6: Sendable {
    public static let logicalWidth: UInt32 = 440
    public static let logicalHeight: UInt32 = 330
    public static let renderFrameBegin: UInt32 = 1
    public static let renderClearBlack: UInt32 = 2
    public static let renderSourceModel: UInt32 = 3
    public static let renderSourceText: UInt32 = 4
    public static let renderRarewarePipeline: UInt32 = 5
    public static let renderGunbarrelPipeline: UInt32 = 6
    public static let renderUnsupported: UInt32 = 7

    public let assets: GoldenEyeSource2DAssetsV6

    public init(assets: GoldenEyeSource2DAssetsV6) { self.assets = assets }

    public func makeLegalFrame(
        nativeTick: UInt64,
        sourceTimer: UInt32,
        fadeAlpha: UInt8 = 255,
        textEvents: [GoldenEyeSource2DTextEventV6] = []
    ) throws -> GoldenEyeSource2DFrameV6 {
        let clip = GoldenEyeSource2DScissorV6()
        var fills: [GoldenEyeSource2DFillV6] = [
            GoldenEyeSource2DFillV6(rect: .sourceCanvas, scissor: clip, rgba: 0x000000FF, flags: 0, sequence: 0)
        ]
        var glyphs: [GoldenEyeSource2DGlyphV6] = []
        if textEvents.isEmpty {
            let placements: [(UInt32, Int32, Int32, Bool, Bool)] = [
                (7, 220, 30, true, true), (8, 34, 83, false, true), (9, 226, 84, false, true),
                (10, 226, 97, false, true), (11, 226, 110, false, true), (12, 226, 122, false, true),
                (13, 227, 134, false, true), (14, 219, 211, false, true), (15, 60, 169, false, true),
                (16, 60, 201, false, true), (17, 99, 266, false, true), (18, 80, 280, false, true)
            ]
            for (id, x, y, centerX, centerY) in placements {
                try appendText(
                    id: id, fontID: .zurichBold, anchorX: x, anchorY: y,
                    centeredX: centerX, centeredY: centerY, color: 0xFFFFFFFF,
                    scissor: clip, sequence: UInt64(id), into: &glyphs
                )
            }
        } else {
            for event in textEvents {
                guard event.screen == 0, (7...18).contains(event.textID) else {
                    throw GoldenEyeSource2DError.invalidSourceEvent("Legal text event \(event.textID) is outside source IDs 7...18")
                }
                try appendText(
                    id: event.textID, fontID: .zurichBold, anchorX: event.x, anchorY: event.y,
                    centeredX: false, centeredY: false, color: 0xFFFFFFFF,
                    scissor: clip, sequence: event.sequence, into: &glyphs
                )
            }
        }
        if fadeAlpha < 255 {
            fills.append(.init(
                rect: .sourceCanvas, scissor: clip,
                rgba: UInt32(255 - fadeAlpha), flags: 1, sequence: UInt64(nativeTick)
            ))
        }
        return makeFrame(
            screen: 0, nativeTick: nativeTick, sourceTimer: sourceTimer,
            scissor: clip, fills: fills, textureRects: [], glyphs: glyphs, unsupported: 0
        )
    }

    public func makeFileSelectFrame(
        nativeTick: UInt64,
        sourceTimer: UInt32,
        fadeAlpha: UInt8 = 255,
        cursorCenter: (x: Int32, y: Int32)? = nil
    ) throws -> GoldenEyeSource2DFrameV6 {
        let clip = GoldenEyeSource2DScissorV6()
        var fills: [GoldenEyeSource2DFillV6] = [
            .init(rect: .sourceCanvas, scissor: clip, rgba: 0x000000FF, flags: 0, sequence: 0)
        ]
        var textures: [GoldenEyeSource2DTextureRectV6] = []
        try appendIcon(.selectFile, rect: .init(x: 49, y: 276, width: 122, height: 18), scissor: clip, sequence: 0, into: &textures)
        try appendIcon(.copy, rect: .init(x: 209, y: 271, width: 32, height: 28), scissor: clip, sequence: 1, into: &textures)
        try appendIcon(.erase, rect: .init(x: 319, y: 271, width: 32, height: 28), scissor: clip, sequence: 2, into: &textures)
        if let cursorCenter {
            try appendIcon(
                .crosshair,
                rect: .init(x: cursorCenter.x - 16, y: cursorCenter.y - 16, width: 32, height: 32),
                scissor: clip, sequence: 3, into: &textures
            )
        }
        var glyphs: [GoldenEyeSource2DGlyphV6] = []
        try appendText(id: 27, fontID: .zurichBold, anchorX: 247, anchorY: 278, centeredX: false, centeredY: false, color: 0xFFFFFFFF, scissor: clip, sequence: 4, into: &glyphs)
        try appendText(id: 28, fontID: .zurichBold, anchorX: 357, anchorY: 278, centeredX: false, centeredY: false, color: 0xFFFFFFFF, scissor: clip, sequence: 5, into: &glyphs)
        if fadeAlpha < 255 {
            fills.append(.init(rect: .sourceCanvas, scissor: clip, rgba: UInt32(255 - fadeAlpha), flags: 1, sequence: UInt64(nativeTick)))
        }
        return makeFrame(screen: 5, nativeTick: nativeTick, sourceTimer: sourceTimer, scissor: clip, fills: fills, textureRects: textures, glyphs: glyphs, unsupported: 0)
    }

    public func makeModeSelectFrame(
        nativeTick: UInt64,
        sourceTimer: UInt32,
        selectedRow: UInt32 = 0,
        fadeAlpha: UInt8 = 255
    ) throws -> GoldenEyeSource2DFrameV6 {
        guard selectedRow <= 1 else { throw GoldenEyeSource2DError.invalidSourceEvent("mode selection row \(selectedRow)") }
        let clip = GoldenEyeSource2DScissorV6()
        var fills: [GoldenEyeSource2DFillV6] = [
            .init(rect: .sourceCanvas, scissor: clip, rgba: 0x000000FF, flags: 0, sequence: 0)
        ]
        var glyphs: [GoldenEyeSource2DGlyphV6] = []
        let entries: [(UInt32, Int32, Int32, UInt32)] = [(29, 170, 220, 0), (30, 170, 252, 1)]
        for (id, x, y, row) in entries {
            let width = try measureText(id: id, fontID: .zurichBold).width
            if selectedRow == row {
                fills.append(.init(
                    rect: .init(x: 148, y: y - 2, width: UInt32(max(0, Int(width) + 175)), height: 16),
                    scissor: clip, rgba: 0x00000032, flags: 2, sequence: UInt64(row)
                ))
            }
            try appendText(id: id, fontID: .zurichBold, anchorX: x, anchorY: y, centeredX: false, centeredY: false, color: 0xFFFFFFFF, scissor: clip, sequence: UInt64(2 + row), into: &glyphs)
        }
        if fadeAlpha < 255 {
            fills.append(.init(rect: .sourceCanvas, scissor: clip, rgba: UInt32(255 - fadeAlpha), flags: 1, sequence: UInt64(nativeTick)))
        }
        return makeFrame(screen: 6, nativeTick: nativeTick, sourceTimer: sourceTimer, scissor: clip, fills: fills, textureRects: [], glyphs: glyphs, unsupported: 0)
    }

    /// Lower the three source Cast name lines using the same Zurich payload
    /// and kerning path as Legal/File Select.  The source constructor places
    /// the lines at x=315 (centered), y=108/152/174 and applies one full-screen
    /// primitive fade after the model pass; no host font or proxy text is
    /// introduced here.
    func makeCastFrame(
        nativeTick: UInt64,
        sourceTimer: UInt32,
        textSourceHashes: [UInt32],
        fadeAlpha: UInt8,
        fullActorIntro: Bool
    ) throws -> GoldenEyeSource2DFrameV6 {
        let clip = GoldenEyeSource2DScissorV6()
        var fills: [GoldenEyeSource2DFillV6] = []
        var glyphs: [GoldenEyeSource2DGlyphV6] = []
        guard textSourceHashes.count == 3 else {
            throw GoldenEyeSource2DError.invalidSourceEvent(
                "Cast text source hash count (textSourceHashes.count) != 3"
            )
        }
        let ids = textSourceHashes
        let ys: [Int32] = [108, 152, 174]
        for (index, sourceHash) in ids.enumerated() {
            if index == 0 && !fullActorIntro { continue }
            let textID = try sourceTextID(for: sourceHash)
            let measured = try measureText(id: textID, fontID: .zurichBold)
            try appendText(
                id: textID,
                fontID: .zurichBold,
                anchorX: 315 - measured.width / 2,
                anchorY: ys[index],
                centeredX: false,
                centeredY: false,
                color: 0xFFFF_FF00 | UInt32(fadeAlpha),
                scissor: clip,
                sequence: UInt64(index),
                into: &glyphs
            )
        }
        if fadeAlpha < 255 {
            fills.append(.init(
                rect: .sourceCanvas,
                scissor: clip,
                rgba: UInt32(255 - fadeAlpha),
                flags: 1,
                sequence: UInt64(nativeTick)
            ))
        }
        return makeFrame(
            // GE_SOURCE_FRAME_V6_SCREEN_CAST is the additive V6 value 7;
            // keep this source-2D contract independently compilable without
            // importing the native scene header.
            screen: 7,
            nativeTick: nativeTick,
            sourceTimer: sourceTimer,
            scissor: clip,
            fills: fills,
            textureRects: [],
            glyphs: glyphs,
            unsupported: 0
        )
    }

    /// Lowers only source 2D operations from the independent V6 frontend event
    /// stream.  Model/character operations intentionally remain with the 3D
    /// scene lowerer; unknown 2D-visible operations fail closed.
    public func lower(
        screen: UInt32,
        nativeTick: UInt64,
        sourceTimer: UInt32,
        renderEvents: [GoldenEyeSource2DRenderEventV6],
        textEvents: [GoldenEyeSource2DTextEventV6] = []
    ) throws -> GoldenEyeSource2DFrameV6 {
        for event in renderEvents {
            switch event.operation {
            case Self.renderFrameBegin, Self.renderClearBlack, Self.renderSourceModel,
                 Self.renderSourceText, Self.renderRarewarePipeline, Self.renderGunbarrelPipeline:
                continue
            default:
                throw GoldenEyeSource2DError.unsupportedVisibleEvent(event.operation)
            }
        }
        switch screen {
        case 0: return try makeLegalFrame(nativeTick: nativeTick, sourceTimer: sourceTimer, textEvents: textEvents)
        case 5: return try makeFileSelectFrame(nativeTick: nativeTick, sourceTimer: sourceTimer)
        case 6: return try makeModeSelectFrame(nativeTick: nativeTick, sourceTimer: sourceTimer)
        default:
            return makeFrame(screen: screen, nativeTick: nativeTick, sourceTimer: sourceTimer, scissor: .init(), fills: [], textureRects: [], glyphs: [], unsupported: 0)
        }
    }

    func appendIcon(
        _ id: GoldenEyeSource2DIconIDV6,
        rect: GoldenEyeSource2DRectV6,
        scissor: GoldenEyeSource2DScissorV6,
        sequence: UInt64,
        into output: inout [GoldenEyeSource2DTextureRectV6]
    ) throws {
        let icon = try assets.icon(id)
        guard icon.width == rect.width, icon.height == rect.height else {
            throw GoldenEyeSource2DError.invalidSourceEvent("icon \(id.sourceName) dimensions do not match source rect")
        }
        output.append(.init(
            resourceRecordID: icon.sourceRecordID, rect: rect, scissor: scissor,
            u0Q16: 0, v0Q16: 0, u1Q16: 65_536, v1Q16: 65_536,
            // front.c displays every frontend image with flipY=1.  Keep the
            // operation as a typed packet flag; the Metal batch lowerer maps
            // bit zero to V reversal rather than inferring it from an asset
            // name.
            tintRGBA: 0xFFFFFFFF, flags: 1, sequence: sequence
        ))
    }

    func measureText(id: UInt32, fontID: GoldenEyeSource2DFontIDV6) throws -> (width: Int32, height: Int32) {
        let text = try assets.text(id: id)
        let font = assets.font(fontID)
        guard let defaultGlyph = font.glyph(forASCII: Character("H").asciiValue ?? 0x48),
              let lineGlyph = font.glyph(forASCII: Character("[").asciiValue ?? 0x5b) else {
            throw GoldenEyeSource2DError.malformedPayload("font (fontID.rawValue) missing H/[ glyph")
        }
        let lineHeight = Int32(lineGlyph.baseline + lineGlyph.height)
        var previous = defaultGlyph
        var width: Int32 = 0
        var longest: Int32 = 0
        var height: Int32 = 0
        let bytes = Array(text.utf8)
        for index in bytes.indices {
            let byte = bytes[index]
            if byte == 0x20 {
                if index + 1 < bytes.count, bytes[index + 1] != 0x0a { width += 5 }
                previous = defaultGlyph
            } else if byte == 0x0a {
                longest = max(longest, width); width = 0; height += lineHeight; previous = defaultGlyph
            } else if let glyph = font.glyph(forASCII: byte) {
                let kern = font.kerningValue(previous: previous, current: glyph)
                width += glyph.width - (kern - 1)
                previous = glyph
            } else {
                throw GoldenEyeSource2DError.invalidSourceEvent("text \(id) contains non-ASCII byte \(byte)")
            }
        }
        return (max(longest, width), height)
    }

    func appendText(
        id: UInt32,
        fontID: GoldenEyeSource2DFontIDV6,
        anchorX: Int32,
        anchorY: Int32,
        centeredX: Bool,
        centeredY: Bool,
        color: UInt32,
        scissor: GoldenEyeSource2DScissorV6,
        sequence: UInt64,
        into output: inout [GoldenEyeSource2DGlyphV6]
    ) throws {
        let text = try assets.text(id: id)
        let font = assets.font(fontID)
        let measured = try measureText(id: id, fontID: fontID)
        guard let defaultGlyph = font.glyph(forASCII: Character("H").asciiValue ?? 0x48) else {
            throw GoldenEyeSource2DError.malformedPayload("font \(fontID.rawValue) missing H glyph")
        }
        var cursorX = centeredX ? anchorX - measured.width / 2 : anchorX
        var cursorY = centeredY ? anchorY - measured.height / 2 : anchorY
        let savedX = cursorX
        let lineGlyph = font.glyph(forASCII: Character("[").asciiValue ?? 0x5b) ?? defaultGlyph
        let lineHeight = max(Int32(14), lineGlyph.baseline + lineGlyph.height)
        var previous = defaultGlyph
        var glyphIndex: UInt32 = 0
        for byte in text.utf8 {
            if byte == 0x20 {
                cursorX += 5; previous = defaultGlyph
            } else if byte == 0x0a {
                cursorY += lineHeight; cursorX = savedX; previous = defaultGlyph
            } else {
                guard let glyph = font.glyph(forASCII: byte), let index = font.glyphs.firstIndex(of: glyph) else {
                    throw GoldenEyeSource2DError.invalidSourceEvent("text \(id) contains non-ASCII byte \(byte)")
                }
                let kern = font.kerningValue(previous: previous, current: glyph)
                cursorX -= kern - 1
                output.append(.init(
                    fontID: font.id, fontRecordID: font.sourceRecordID, glyphIndex: UInt32(index),
                    character: UInt32(byte), x: cursorX, y: cursorY + glyph.baseline,
                    width: UInt32(glyph.width), height: UInt32(glyph.height), baseline: glyph.baseline,
                    scissor: scissor, rgba: color, stringID: id, flags: 1, sequence: sequence + UInt64(glyphIndex)
                ))
                glyphIndex += 1
                cursorX += glyph.width
                previous = glyph
            }
        }
    }

    private func sourceTextID(for sourceHash: UInt32) throws -> UInt32 {
        // Cast identity records carry the source symbol hash, not the
        // localized GETC bytes. Resolve that symbol through front.c's stable
        // LTITLE string IDs; hashing the localized spelling would fail as
        // soon as the language payload changes case or adds its newline.
        if let id = Self.castTextIDs[sourceHash], assets.textStrings.indices.contains(Int(id)) {
            return id
        }
        throw GoldenEyeSource2DError.invalidSourceEvent(
            "Cast text source hash 0x\(String(sourceHash, radix: 16)) is absent from GETC"
        )
    }

    private static let castTextIDs: [UInt32: UInt32] = [
        sourceHash("LF"): 227,
        sourceHash("THEACTORS"): 228,
        sourceHash("STARRING"): 229,
        sourceHash("ALSOFEATURING"): 230,
        sourceHash("GUESTSTAR"): 231,
        sourceHash("007"): 232,
        sourceHash("JAMESBOND"): 233,
        sourceHash("NATALYASIMONOVA"): 234,
        sourceHash("006"): 235,
        sourceHash("ALECTREVELYAN"): 236,
        sourceHash("JANUSOPPERATIVE"): 237,
        sourceHash("XENIAONPTOPP"): 238,
        sourceHash("GENERAL"): 239,
        sourceHash("ARKADYOURUMOV"): 240,
        sourceHash("BORISGRISHENKO"): 241,
        sourceHash("EXKGBAGENT"): 242,
        sourceHash("VELENTINZUKOVSKY"): 243,
        sourceHash("DEFENSEMINISTER"): 244,
        sourceHash("DIMITRIMISHKIN"): 245,
        sourceHash("MAYDAY"): 246,
        sourceHash("JAWS"): 247,
        sourceHash("ODDJOB"): 248,
        sourceHash("BERONSAMEDI"): 249,
        sourceHash("JUNGLECOMMANDO"): 250,
        sourceHash("STPETERSBURGGUARD"): 251,
        sourceHash("RUSSIANINFANTRY"): 252,
        sourceHash("RUSSIANSOLDIER"): 253,
        sourceHash("JANUSMARINE"): 254,
        sourceHash("JANUSSPECIALFORCES"): 255,
        sourceHash("RUSSIANCOMMANDANT"): 256,
        sourceHash("NAVALOFFICER"): 257,
        sourceHash("SIBERIANGUARD"): 258,
        sourceHash("ARCTICCOMMANDO"): 259,
        sourceHash("SIBERIANSPECIALFORCES"): 260,
        sourceHash("MOONRAKERELITE"): 261,
        sourceHash("HELICOPTERPILOT"): 262,
        sourceHash("SCIENTIST"): 263,
        sourceHash("CIVILIAN"): 264,
    ]

    private static func sourceHash(_ value: String) -> UInt32 {
        value.utf8.reduce(UInt32(2_166_136_261)) {
            ($0 ^ UInt32($1)) &* 16_777_619
        }
    }

    func makeFrame(
        screen: UInt32,
        nativeTick: UInt64,
        sourceTimer: UInt32,
        scissor: GoldenEyeSource2DScissorV6,
        fills: [GoldenEyeSource2DFillV6],
        textureRects: [GoldenEyeSource2DTextureRectV6],
        glyphs: [GoldenEyeSource2DGlyphV6],
        unsupported: UInt32
    ) -> GoldenEyeSource2DFrameV6 {
        var hash: UInt64 = 1_469_598_103_934_665_603
        func append(_ value: UInt64) { hash = (hash ^ value) &* 1_099_511_628_211 }
        append(UInt64(screen)); append(nativeTick); append(UInt64(sourceTimer))
        for fill in fills {
            append(UInt64(bitPattern: Int64(fill.rect.x))); append(UInt64(bitPattern: Int64(fill.rect.y)))
            append(UInt64(fill.rect.width)); append(UInt64(fill.rect.height)); append(UInt64(fill.rgba)); append(UInt64(fill.flags)); append(fill.sequence)
        }
        for texture in textureRects {
            append(UInt64(texture.resourceRecordID)); append(UInt64(bitPattern: Int64(texture.rect.x))); append(UInt64(bitPattern: Int64(texture.rect.y)))
            append(UInt64(texture.rect.width)); append(UInt64(texture.rect.height)); append(UInt64(texture.tintRGBA)); append(texture.sequence)
        }
        for glyph in glyphs {
            append(UInt64(glyph.fontID)); append(UInt64(glyph.fontRecordID)); append(UInt64(glyph.glyphIndex)); append(UInt64(glyph.character))
            append(UInt64(bitPattern: Int64(glyph.x))); append(UInt64(bitPattern: Int64(glyph.y))); append(UInt64(glyph.width)); append(UInt64(glyph.height)); append(UInt64(glyph.stringID)); append(glyph.sequence)
        }
        return GoldenEyeSource2DFrameV6(
            screen: screen, nativeTick: nativeTick, sourceTimer: sourceTimer,
            logicalWidth: Self.logicalWidth, logicalHeight: Self.logicalHeight,
            scissor: scissor, fills: fills, textureRects: textureRects, glyphs: glyphs,
            unsupportedVisibleCount: unsupported, frameHash: hash
        )
    }
}
