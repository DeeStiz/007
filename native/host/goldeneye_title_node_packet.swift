import CryptoKit
import Foundation

/// Value-only M7 frontend model hierarchy packet. Source-local offsets are
/// evidence keys, not runtime addresses; no C pointer or display-list word is
/// retained in this Swift value.
struct GoldenEyeTitleNodePacket: Sendable {
    static let magic = Array("GETN".utf8)
    static let version: UInt32 = 1
    static let headerSize = 100
    static let nodeStride = 48
    static let textureStride = 32
    static let maxNodes = 4096
    static let maxTextures = 256

    struct Node: Sendable, Equatable {
        let nodeOffset: UInt32
        let opcode: UInt32
        let recordOffset: UInt32
        let parentOffset: UInt32
        let nextOffset: UInt32
        let previousOffset: UInt32
        let childOffset: UInt32
        let primaryDisplayListOffset: UInt32
        let secondaryDisplayListOffset: UInt32
        let vertexArrayOffset: UInt32
        let vertexCount: UInt32
        let modelType: UInt32
    }

    struct Texture: Sendable, Equatable {
        let modelOffsetOrToken: UInt32
        let width: UInt32
        let height: UInt32
        let mipMapTiles: UInt32
        let type: UInt32
        let renderDepth: UInt32
        let sFlags: UInt32
        let tFlags: UInt32
    }

    enum Error: Swift.Error, CustomStringConvertible {
        case truncated(String)
        case invalid(String)
        case hashMismatch

        var description: String {
            switch self {
            case .truncated(let detail): return "title node packet truncated: \(detail)"
            case .invalid(let detail): return "title node packet invalid: \(detail)"
            case .hashMismatch: return "title node packet SHA-256 mismatch"
            }
        }
    }

    let modelHandle: UInt32
    let sourceLength: UInt32
    let sourceHash: [UInt8]
    let packetHash: [UInt8]
    let nodes: [Node]
    let textures: [Texture]

    static func load(from url: URL) throws -> GoldenEyeTitleNodePacket {
        let data = try Data(contentsOf: url)
        guard data.count >= headerSize else { throw Error.truncated("header") }
        guard Array(data[0..<4]) == magic else { throw Error.invalid("magic") }
        guard readUInt32(data, at: 4) == version else { throw Error.invalid("version") }
        let handle = readUInt32(data, at: 8)
        let nodeCount = Int(readUInt32(data, at: 12))
        let textureCount = Int(readUInt32(data, at: 16))
        guard nodeCount > 0, nodeCount <= maxNodes,
              textureCount <= maxTextures else { throw Error.invalid("counts") }
        guard readUInt32(data, at: 20) == nodeStride,
              readUInt32(data, at: 24) == textureStride else { throw Error.invalid("strides") }
        let sourceLength = readUInt32(data, at: 28)
        let nodeBytes = nodeCount.multipliedReportingOverflow(by: nodeStride)
        let textureBytes = textureCount.multipliedReportingOverflow(by: textureStride)
        guard !nodeBytes.overflow, !textureBytes.overflow else { throw Error.invalid("size overflow") }
        let expected = headerSize + nodeBytes.partialValue + textureBytes.partialValue
        guard expected == data.count else { throw Error.truncated("payload length") }
        let sourceHash = Array(data[32..<64])
        let packetHash = Array(data[64..<96])
        guard readUInt32(data, at: 96) == 0 else { throw Error.invalid("reserved") }
        var canonical = data
        canonical.replaceSubrange(64..<96, with: repeatElement(UInt8(0), count: 32))
        guard Array(SHA256.hash(data: canonical)) == packetHash else { throw Error.hashMismatch }

        var nodes: [Node] = []
        nodes.reserveCapacity(nodeCount)
        var nodeOffsets = Set<UInt32>()
        for index in 0..<nodeCount {
            let offset = headerSize + index * nodeStride
            let values = (0..<12).map { readUInt32(data, at: offset + $0 * 4) }
            guard nodeOffsets.insert(values[0]).inserted else { throw Error.invalid("duplicate node offset") }
            nodes.append(Node(
                nodeOffset: values[0], opcode: values[1], recordOffset: values[2],
                parentOffset: values[3], nextOffset: values[4], previousOffset: values[5],
                childOffset: values[6], primaryDisplayListOffset: values[7],
                secondaryDisplayListOffset: values[8], vertexArrayOffset: values[9],
                vertexCount: values[10], modelType: values[11]
            ))
        }
        for node in nodes {
            for reference in [node.parentOffset, node.nextOffset, node.previousOffset, node.childOffset] where reference != UInt32.max {
                guard nodeOffsets.contains(reference) else { throw Error.invalid("node link outside packet") }
            }
        }

        var textures: [Texture] = []
        textures.reserveCapacity(textureCount)
        let textureStart = headerSize + nodeBytes.partialValue
        for index in 0..<textureCount {
            let offset = textureStart + index * textureStride
            let values = (0..<8).map { readUInt32(data, at: offset + $0 * 4) }
            guard values[1] > 0, values[2] > 0, values[1] <= 4096, values[2] <= 4096 else {
                throw Error.invalid("texture dimensions")
            }
            textures.append(Texture(
                modelOffsetOrToken: values[0], width: values[1], height: values[2],
                mipMapTiles: values[3], type: values[4], renderDepth: values[5],
                sFlags: values[6], tFlags: values[7]
            ))
        }
        return GoldenEyeTitleNodePacket(
            modelHandle: handle, sourceLength: sourceLength, sourceHash: sourceHash,
            packetHash: packetHash, nodes: nodes, textures: textures
        )
    }

    static func loadAll(from titleRoot: URL) throws -> [GoldenEyeTitleNodePacket] {
        try ["legalpage", "nintendologo", "goldeneyelogo", "walletbond"].map {
            try load(from: titleRoot.appendingPathComponent("\($0).getn"))
        }
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) | UInt32(data[offset + 1]) << 8 |
            UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
    }
}
