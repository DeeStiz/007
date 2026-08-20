import CryptoKit
import Foundation

/// Additive M8 source texture/material packet emitted by
/// ``prepare_native_title_textures.py``.  The parser validates the on-disk
/// fixed-width GETT envelope and exposes only copied RGBA8 payloads; source
/// offsets and symbolic image IDs remain provenance values, never addresses.
struct GoldenEyeTitleTexturePacket: Sendable {
    static let magic = Array("GETT".utf8)
    static let version: UInt32 = 1
    static let abiVersion: UInt32 = 1 // GE_NATIVE_ABI_VERSION
    static let headerSize = 128
    static let recordSize = 144
    static let maxRecords = 256
    static let maxTextureDimension: UInt32 = 4096
    static let maxPayloadBytes = 8 * 1024 * 1024
    static let knownFlags: UInt32 = (1 << 12) - 1

    static let flagDirectModel: UInt32 = 1 << 0
    static let flagImageStream: UInt32 = 1 << 1
    static let flagDecodedRGBA8: UInt32 = 1 << 2
    static let flagMipChain: UInt32 = 1 << 3
    static let flagSymbolicID: UInt32 = 1 << 4
    static let flagTiled: UInt32 = 1 << 5
    static let flagClampS: UInt32 = 1 << 6
    static let flagClampT: UInt32 = 1 << 7
    static let flagMirrorS: UInt32 = 1 << 8
    static let flagMirrorT: UInt32 = 1 << 9
    static let flagBilerp: UInt32 = 1 << 10
    static let flagDetailClamp: UInt32 = 1 << 11

    struct Record: Sendable, Equatable {
        let resourceID: UInt32
        let width: Int
        let height: Int
        let mipMapTiles: UInt32
        let type: UInt32
        let renderDepth: UInt32
        let sFlags: UInt32
        let tFlags: UInt32
        let format: UInt32
        let size: UInt32
        let sourceStrideBytes: UInt32
        let decodedByteCount: Int
        let sourceOffset: UInt32
        let payloadOffset: Int
        let flags: UInt32
        let sourceByteCount: Int
        let sourceHash: [UInt8]
        let decodedHash: [UInt8]

        var isDirectModel: Bool { (flags & Self.flagDirectModel) != 0 }
        var isImageStream: Bool { (flags & Self.flagImageStream) != 0 }
        var hasMipChain: Bool { (flags & Self.flagMipChain) != 0 }
        var isSymbolicID: Bool { (flags & Self.flagSymbolicID) != 0 }

        private static let flagDirectModel: UInt32 = 1 << 0
        private static let flagImageStream: UInt32 = 1 << 1
        private static let flagMipChain: UInt32 = 1 << 3
        private static let flagSymbolicID: UInt32 = 1 << 4
    }

    enum Error: Swift.Error, CustomStringConvertible {
        case truncated(String)
        case invalid(String)
        case hashMismatch

        var description: String {
            switch self {
            case .truncated(let detail): return "title texture packet truncated: \(detail)"
            case .invalid(let detail): return "title texture packet invalid: \(detail)"
            case .hashMismatch: return "title texture packet SHA-256 mismatch"
            }
        }
    }

    let modelHandle: UInt32
    let packetFlags: UInt32
    let sourceByteCount: Int
    let sourceHash: [UInt8]
    let packetHash: [UInt8]
    let records: [Record]
    private let payload: Data

    static func load(from url: URL) throws -> GoldenEyeTitleTexturePacket {
        try load(data: Data(contentsOf: url, options: [.mappedIfSafe]))
    }

    static func load(data: Data) throws -> GoldenEyeTitleTexturePacket {
        guard data.count >= headerSize else { throw Error.truncated("header") }
        guard Array(data[0..<4]) == magic else { throw Error.invalid("magic") }
        guard readUInt32(data, at: 4) == version else { throw Error.invalid("version") }
        guard readUInt32(data, at: 8) == abiVersion else { throw Error.invalid("ABI version") }
        guard readUInt32(data, at: 12) == UInt32(headerSize) else { throw Error.invalid("header size") }

        let modelHandle = readUInt32(data, at: 16)
        let recordCount = Int(readUInt32(data, at: 20))
        let recordStride = Int(readUInt32(data, at: 24))
        let payloadByteCount = Int(readUInt32(data, at: 28))
        let sourceByteCount = Int(readUInt32(data, at: 32))
        let packetFlags = readUInt32(data, at: 36)
        guard recordCount > 0, recordCount <= maxRecords,
              recordStride == recordSize,
              payloadByteCount > 0, payloadByteCount <= maxPayloadBytes,
              sourceByteCount > 0,
              packetFlags == 1 || packetFlags == 2 else {
            throw Error.invalid("counts/stride/flags")
        }
        guard data[104..<128].allSatisfy({ $0 == 0 }) else {
            throw Error.invalid("reserved header fields")
        }

        let sourceHash = Array(data[40..<72])
        let packetHash = Array(data[72..<104])
        guard sourceHash.contains(where: { $0 != 0 }) else { throw Error.invalid("source hash") }
        var canonical = data
        canonical.replaceSubrange(72..<104, with: repeatElement(UInt8(0), count: 32))
        guard Array(SHA256.hash(data: canonical)) == packetHash else { throw Error.hashMismatch }

        let recordsBytes = recordCount.multipliedReportingOverflow(by: recordStride)
        guard !recordsBytes.overflow else { throw Error.invalid("record size overflow") }
        let payloadBase = headerSize.addingReportingOverflow(recordsBytes.partialValue)
        guard !payloadBase.overflow else { throw Error.invalid("payload base overflow") }
        let expectedLength = payloadBase.partialValue.addingReportingOverflow(payloadByteCount)
        guard !expectedLength.overflow, expectedLength.partialValue == data.count else {
            throw Error.truncated("record/payload bounds")
        }

        var records: [Record] = []
        records.reserveCapacity(recordCount)
        var expectedPayloadOffset = 0
        for index in 0..<recordCount {
            let offset = headerSize + index * recordStride
            guard readUInt32(data, at: offset) == abiVersion,
                  readUInt32(data, at: offset + 4) == UInt32(recordStride),
                  readUInt32(data, at: offset + 8) == version else {
                throw Error.invalid("record \(index) ABI/version")
            }
            let resourceID = readUInt32(data, at: offset + 12)
            let width = Int(readUInt32(data, at: offset + 16))
            let height = Int(readUInt32(data, at: offset + 20))
            let mipMapTiles = readUInt32(data, at: offset + 24)
            let type = readUInt32(data, at: offset + 28)
            let renderDepth = readUInt32(data, at: offset + 32)
            let sFlags = readUInt32(data, at: offset + 36)
            let tFlags = readUInt32(data, at: offset + 40)
            let format = readUInt32(data, at: offset + 44)
            let size = readUInt32(data, at: offset + 48)
            let sourceStrideBytes = readUInt32(data, at: offset + 52)
            let decodedByteCount = Int(readUInt32(data, at: offset + 56))
            let sourceOffset = readUInt32(data, at: offset + 60)
            let payloadOffset = Int(readUInt32(data, at: offset + 64))
            let flags = readUInt32(data, at: offset + 68)
            let sourceRowByteCount = Int(readUInt32(data, at: offset + 72))
            guard readUInt32(data, at: offset + 76) == 0 else {
                throw Error.invalid("record \(index) reserved field")
            }
            let sourceDigest = Array(data[(offset + 80)..<(offset + 112)])
            let decodedDigest = Array(data[(offset + 112)..<(offset + 144)])
            let pixelCount = width.multipliedReportingOverflow(by: height)
            guard width > 0, height > 0,
                  width <= Int(maxTextureDimension), height <= Int(maxTextureDimension),
                  !pixelCount.overflow,
                  decodedByteCount == pixelCount.partialValue * 4,
                  sourceRowByteCount > 0, sourceRowByteCount <= 4 * 1024 * 1024,
                  payloadOffset == expectedPayloadOffset,
                  flags & ~knownFlags == 0,
                  (flags & flagDecodedRGBA8) != 0,
                  ((flags & flagDirectModel) != 0) != ((flags & flagImageStream) != 0),
                  (flags & flagImageStream) == 0 || (flags & flagSymbolicID) != 0,
                  sourceDigest.contains(where: { $0 != 0 }),
                  decodedDigest.contains(where: { $0 != 0 }) else {
                throw Error.invalid("record \(index) metadata")
            }
            let end = payloadOffset.addingReportingOverflow(decodedByteCount)
            guard !end.overflow, end.partialValue <= payloadByteCount else {
                throw Error.truncated("record \(index) payload")
            }
            let pixels = data[(payloadBase.partialValue + payloadOffset)..<(payloadBase.partialValue + end.partialValue)]
            guard Array(SHA256.hash(data: pixels)) == decodedDigest else {
                throw Error.hashMismatch
            }
            records.append(Record(
                resourceID: resourceID, width: width, height: height,
                mipMapTiles: mipMapTiles, type: type, renderDepth: renderDepth,
                sFlags: sFlags, tFlags: tFlags, format: format, size: size,
                sourceStrideBytes: sourceStrideBytes,
                decodedByteCount: decodedByteCount, sourceOffset: sourceOffset,
                payloadOffset: payloadOffset, flags: flags,
                sourceByteCount: sourceRowByteCount, sourceHash: sourceDigest,
                decodedHash: decodedDigest
            ))
            expectedPayloadOffset = end.partialValue
        }
        guard expectedPayloadOffset == payloadByteCount else {
            throw Error.invalid("unused payload")
        }
        return GoldenEyeTitleTexturePacket(
            modelHandle: modelHandle, packetFlags: packetFlags,
            sourceByteCount: sourceByteCount, sourceHash: sourceHash,
            packetHash: packetHash, records: records,
            payload: Data(data[payloadBase.partialValue..<data.count])
        )
    }

    static func loadAll(from titleRoot: URL) throws -> [GoldenEyeTitleTexturePacket] {
        try ["legalpage", "nintendologo", "goldeneyelogo", "walletbond"].map {
            try load(from: titleRoot.appendingPathComponent("\($0).gett"))
        }
    }

    func rgba8(for recordIndex: Int) -> Data {
        let record = records[recordIndex]
        let end = record.payloadOffset + record.decodedByteCount
        return Data(payload[record.payloadOffset..<end])
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
    }
}
