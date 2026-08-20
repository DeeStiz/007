import CryptoKit
import Foundation

/// Additive GETU source UV/material packet.
///
/// GETU is a corner-expanded stream: each record is one triangle corner from
/// the guarded primary display list.  Keeping corners separate preserves the
/// active material when a source vertex is reused across texture changes.
/// The parser exposes only copied fixed-width values; source hashes and
/// source-local material handles are evidence keys, never addresses.
struct GoldenEyeTitleUVPacket: Sendable {
    static let magic = Array("GETU".utf8)
    static let version: UInt32 = 1
    static let abiVersion: UInt32 = 1
    static let headerSize = 128
    static let recordSize = 64
    static let maxRecords = 32_768
    static let maxIndices = 32_768
    static let knownFlags: UInt32 = (1 << 7) - 1
    static let flagHasTriangles: UInt32 = 1 << 0
    static let flagHasUnsupported: UInt32 = 1 << 1
    static let flagPartialSource: UInt32 = 1 << 2
    static let flagHasTextureHandles: UInt32 = 1 << 3
    static let flagSignedST: UInt32 = 1 << 4
    static let flagCommandHashes: UInt32 = 1 << 5
    static let flagCornerExpansion: UInt32 = 1 << 6

    struct Record: Sendable, Equatable {
        let vertexIndex: UInt32
        let position: SIMD3<Int32>
        let s: Int32
        let t: Int32
        let materialHandle: UInt32
        let sourceCommandHash: UInt64
        let sourceVertexHash: UInt64
        let flags: UInt32
    }

    enum Error: Swift.Error, CustomStringConvertible {
        case truncated(String)
        case invalid(String)
        case hashMismatch

        var description: String {
            switch self {
            case .truncated(let detail): return "title UV packet truncated: \(detail)"
            case .invalid(let detail): return "title UV packet invalid: \(detail)"
            case .hashMismatch: return "title UV packet SHA-256 mismatch"
            }
        }
    }

    let modelHandle: UInt32
    let flags: UInt32
    let sourceCommandCount: UInt32
    let unsupportedCommandCount: UInt32
    let sourceByteCount: UInt32
    let sourceHash: [UInt8]
    let packetHash: [UInt8]
    let records: [Record]
    let indices: [UInt32]

    var hasUnsupportedCommands: Bool { (flags & Self.flagHasUnsupported) != 0 }

    static func load(from url: URL) throws -> GoldenEyeTitleUVPacket {
        try load(data: Data(contentsOf: url, options: [.mappedIfSafe]))
    }

    static func loadAll(from titleRoot: URL) throws -> [GoldenEyeTitleUVPacket] {
        try ["legalpage", "nintendologo", "goldeneyelogo"].map {
            try load(from: titleRoot.appendingPathComponent("\($0).getu"))
        }
    }

    static func load(data: Data) throws -> GoldenEyeTitleUVPacket {
        guard data.count >= headerSize else { throw Error.truncated("header") }
        guard Array(data[0..<4]) == magic else { throw Error.invalid("magic") }
        guard readUInt32(data, at: 4) == version else { throw Error.invalid("version") }
        guard readUInt32(data, at: 8) == abiVersion else { throw Error.invalid("ABI version") }
        guard readUInt32(data, at: 12) == UInt32(headerSize) else {
            throw Error.invalid("header size")
        }

        let modelHandle = readUInt32(data, at: 16)
        let recordCount = Int(readUInt32(data, at: 20))
        let recordStride = Int(readUInt32(data, at: 24))
        let indexCount = Int(readUInt32(data, at: 28))
        let flags = readUInt32(data, at: 32)
        let sourceCommandCount = readUInt32(data, at: 36)
        let unsupportedCommandCount = readUInt32(data, at: 40)
        let sourceByteCount = readUInt32(data, at: 44)
        guard modelHandle != 0,
              recordCount > 0, recordCount <= maxRecords,
              recordStride == recordSize,
              indexCount > 0, indexCount <= maxIndices, indexCount % 3 == 0,
              sourceCommandCount > 0, sourceByteCount > 0,
              flags & ~knownFlags == 0,
              (flags & flagHasTriangles) != 0,
              (flags & flagPartialSource) != 0,
              (flags & flagSignedST) != 0,
              (flags & flagCommandHashes) != 0,
              (flags & flagCornerExpansion) != 0 else {
            throw Error.invalid("counts/stride/flags")
        }
        guard data[112..<128].allSatisfy({ $0 == 0 }) else {
            throw Error.invalid("reserved header fields")
        }

        let sourceHash = Array(data[48..<80])
        let packetHash = Array(data[80..<112])
        guard sourceHash.contains(where: { $0 != 0 }), packetHash.contains(where: { $0 != 0 }) else {
            throw Error.invalid("source/packet hash")
        }
        var canonical = data
        canonical.replaceSubrange(80..<112, with: repeatElement(UInt8(0), count: 32))
        guard Array(SHA256.hash(data: canonical)) == packetHash else {
            throw Error.hashMismatch
        }

        let recordsBytes = recordCount.multipliedReportingOverflow(by: recordStride)
        guard !recordsBytes.overflow else { throw Error.invalid("record size overflow") }
        let recordsEnd = headerSize.addingReportingOverflow(recordsBytes.partialValue)
        guard !recordsEnd.overflow else { throw Error.invalid("records end overflow") }
        let indexBytes = indexCount.multipliedReportingOverflow(by: 4)
        guard !indexBytes.overflow else { throw Error.invalid("index size overflow") }
        let expectedLength = recordsEnd.partialValue.addingReportingOverflow(indexBytes.partialValue)
        guard !expectedLength.overflow, expectedLength.partialValue == data.count else {
            throw Error.truncated("record/index bounds")
        }

        var records: [Record] = []
        records.reserveCapacity(recordCount)
        for index in 0..<recordCount {
            let offset = headerSize + index * recordStride
            guard readUInt32(data, at: offset) == abiVersion,
                  readUInt32(data, at: offset + 4) == UInt32(recordSize),
                  readUInt32(data, at: offset + 8) == version,
                  readUInt32(data, at: offset + 12) == UInt32(index) else {
                throw Error.invalid("record \(index) ABI/version/index")
            }
            let sourceCommandHash = readUInt64(data, at: offset + 40)
            let sourceVertexHash = readUInt64(data, at: offset + 48)
            let recordFlags = readUInt32(data, at: offset + 56)
            guard sourceCommandHash != 0, sourceVertexHash != 0,
                  recordFlags == flags,
                  readUInt32(data, at: offset + 60) == 0 else {
                throw Error.invalid("record \(index) hash/flags/reserved")
            }
            records.append(Record(
                vertexIndex: UInt32(index),
                position: SIMD3(
                    readInt32(data, at: offset + 16),
                    readInt32(data, at: offset + 20),
                    readInt32(data, at: offset + 24)
                ),
                s: readInt32(data, at: offset + 28),
                t: readInt32(data, at: offset + 32),
                materialHandle: readUInt32(data, at: offset + 36),
                sourceCommandHash: sourceCommandHash,
                sourceVertexHash: sourceVertexHash,
                flags: recordFlags
            ))
        }

        var indices: [UInt32] = []
        indices.reserveCapacity(indexCount)
        for index in 0..<indexCount {
            let value = readUInt32(data, at: recordsEnd.partialValue + index * 4)
            guard value < UInt32(recordCount), value == UInt32(index) else {
                throw Error.invalid("index \(index) outside corner stream")
            }
            indices.append(value)
        }

        return GoldenEyeTitleUVPacket(
            modelHandle: modelHandle,
            flags: flags,
            sourceCommandCount: sourceCommandCount,
            unsupportedCommandCount: unsupportedCommandCount,
            sourceByteCount: sourceByteCount,
            sourceHash: sourceHash,
            packetHash: packetHash,
            records: records,
            indices: indices
        )
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }

    private static func readUInt64(_ data: Data, at offset: Int) -> UInt64 {
        UInt64(readUInt32(data, at: offset))
            | UInt64(readUInt32(data, at: offset + 4)) << 32
    }

    private static func readInt32(_ data: Data, at offset: Int) -> Int32 {
        Int32(bitPattern: readUInt32(data, at: offset))
    }
}
