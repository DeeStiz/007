import CryptoKit
import Foundation

/// Source-derived frontend texture packets emitted by
/// ``prepare_native_title_icons.py``.  The packet carries decoded RGBA8
/// pixels, while every source row remains represented by fixed-width metadata
/// and a SHA-256 provenance hash.  No ROM path, pointer, display-list word, or
/// Metal object crosses this boundary.
struct GoldenEyeTitleIconPacket: Sendable {
    static let magic = Array("GETI".utf8)
    static let version: UInt32 = 1
    static let iconCount = 7
    static let headerSize = 96
    static let recordSize = 108
    static let maxTextureDimension = 512
    static let maxPayloadBytes = 1_048_576

    enum Icon: Int, CaseIterable, Hashable, Sendable {
        case copy = 0
        case erase = 1
        case selectFile = 2
        case crosshair = 3
        case check = 4
        case dot = 5
        case cursorX = 6

        var sourceName: String {
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

    struct Record: Sendable {
        let icon: Icon
        let width: Int
        let height: Int
        let format: UInt32
        let compression: UInt32
        let sFlags: UInt32
        let tFlags: UInt32
        let sourceByteCount: Int
        let decodedByteCount: Int
        let payloadOffset: Int
        let sourceHash: [UInt8]
        let decodedHash: [UInt8]

        var pixelCount: Int { width * height }
    }

    enum Error: Swift.Error, CustomStringConvertible {
        case truncated(String)
        case invalid(String)
        case hashMismatch

        var description: String {
            switch self {
            case .truncated(let detail): return "title icon packet truncated: \(detail)"
            case .invalid(let detail): return "title icon packet invalid: \(detail)"
            case .hashMismatch: return "title icon packet SHA-256 mismatch"
            }
        }
    }

    let sourceConcatByteCount: Int
    let sourceConcatHash: [UInt8]
    let packetHash: [UInt8]
    let records: [Record]
    private let payload: Data

    static func load(from url: URL) throws -> GoldenEyeTitleIconPacket {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count >= headerSize else { throw Error.truncated("header") }
        guard Array(data[0..<4]) == magic else { throw Error.invalid("magic") }
        guard readUInt32(data, at: 4) == version else { throw Error.invalid("version") }
        let count = Int(readUInt32(data, at: 8))
        let recordBytes = Int(readUInt32(data, at: 12))
        let payloadBytes = Int(readUInt32(data, at: 16))
        let sourceConcatBytes = Int(readUInt32(data, at: 20))
        guard count == iconCount, recordBytes == count * recordSize else {
            throw Error.invalid("fixed icon count/record size")
        }
        guard payloadBytes > 0, payloadBytes <= maxPayloadBytes,
              sourceConcatBytes > 0, sourceConcatBytes <= 1_000_000 else {
            throw Error.invalid("payload/source byte count")
        }
        guard readUInt32(data, at: 24) == 0, readUInt32(data, at: 92) == 0 else {
            throw Error.invalid("reserved header field")
        }
        let sourceHash = Array(data[28..<60])
        let packetHash = Array(data[60..<92])
        guard sourceHash.contains(where: { $0 != 0 }) else { throw Error.invalid("source hash is empty") }
        var canonical = data
        canonical.replaceSubrange(60..<92, with: repeatElement(UInt8(0), count: 32))
        guard Array(SHA256.hash(data: canonical)) == packetHash else { throw Error.hashMismatch }

        let recordBase = headerSize
        let payloadBase = recordBase + recordBytes
        let payloadEnd = payloadBase.addingReportingOverflow(payloadBytes)
        guard !payloadEnd.overflow, payloadEnd.partialValue == data.count else {
            throw Error.truncated("record/payload bounds")
        }

        var records: [Record] = []
        records.reserveCapacity(count)
        var expectedOffset = 0
        for index in 0..<count {
            let offset = recordBase + index * recordSize
            let iconID = Int(readUInt32(data, at: offset))
            guard iconID == index, let icon = Icon(rawValue: iconID) else {
                throw Error.invalid("icon (index) identity")
            }
            let width = Int(readUInt32(data, at: offset + 4))
            let height = Int(readUInt32(data, at: offset + 8))
            let format = readUInt32(data, at: offset + 12)
            let compression = readUInt32(data, at: offset + 16)
            let sFlags = readUInt32(data, at: offset + 20)
            let tFlags = readUInt32(data, at: offset + 24)
            let sourceByteCount = Int(readUInt32(data, at: offset + 28))
            let decodedByteCount = Int(readUInt32(data, at: offset + 32))
            let payloadOffset = Int(readUInt32(data, at: offset + 36))
            guard readUInt32(data, at: offset + 40) == 0 else {
                throw Error.invalid("icon (index) reserved field")
            }
            guard width > 0, height > 0,
                  width <= maxTextureDimension, height <= maxTextureDimension,
                  width.multipliedReportingOverflow(by: height).overflow == false,
                  decodedByteCount == width * height * 4,
                  sourceByteCount > 0, sourceByteCount <= 4096,
                  format <= 12, compression <= 8,
                  sFlags <= 3, tFlags <= 3,
                  payloadOffset == expectedOffset else {
                throw Error.invalid("icon (index) dimensions/metadata/payload offset")
            }
            let end = payloadOffset.addingReportingOverflow(decodedByteCount)
            guard !end.overflow, end.partialValue <= payloadBytes else {
                throw Error.truncated("icon (index) pixel payload")
            }
            let sourceDigest = Array(data[(offset + 44)..<(offset + 76)])
            let decodedDigest = Array(data[(offset + 76)..<(offset + 108)])
            guard sourceDigest.contains(where: { $0 != 0 }), decodedDigest.contains(where: { $0 != 0 }) else {
                throw Error.invalid("icon (index) hash is empty")
            }
            let pixels = data[(payloadBase + payloadOffset)..<(payloadBase + end.partialValue)]
            guard Array(SHA256.hash(data: pixels)) == decodedDigest else {
                throw Error.hashMismatch
            }
            records.append(Record(
                icon: icon,
                width: width,
                height: height,
                format: format,
                compression: compression,
                sFlags: sFlags,
                tFlags: tFlags,
                sourceByteCount: sourceByteCount,
                decodedByteCount: decodedByteCount,
                payloadOffset: payloadOffset,
                sourceHash: sourceDigest,
                decodedHash: decodedDigest
            ))
            expectedOffset = end.partialValue
        }
        guard expectedOffset == payloadBytes else { throw Error.invalid("unused pixel payload") }
        return GoldenEyeTitleIconPacket(
            sourceConcatByteCount: sourceConcatBytes,
            sourceConcatHash: sourceHash,
            packetHash: packetHash,
            records: records,
            payload: Data(data[payloadBase..<payloadEnd.partialValue])
        )
    }

    func record(for icon: Icon) -> Record? {
        records.first { $0.icon == icon }
    }

    func pixels(for icon: Icon) -> Data? {
        guard let record = record(for: icon) else { return nil }
        let start = record.payloadOffset
        let end = start + record.decodedByteCount
        guard end <= payload.count else { return nil }
        return payload[start..<end]
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }
}
