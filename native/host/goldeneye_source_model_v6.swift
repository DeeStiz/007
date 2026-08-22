import CryptoKit
import Foundation

/// Strict reader and semantic compiler for the additive GESM V6 source-model
/// sidecars.  The on-disk packet is intentionally private preparation output;
/// the values exposed here contain only copied fixed-width values, strings,
/// and deterministic handles.  No source pointer, segmented address, ROM
/// offset, or Metal object is retained by a public value.
struct GoldenEyeSourceModelV6: Sendable {
    static let magic = Array("GESM".utf8)
    static let version: UInt32 = 6
    static let headerSize = 132
    static let nodeSize = 48
    static let scalarSize = 64
    static let displayListSize = 32
    static let commandSize = 48
    static let tokenSize = 28
    static let vertexSize = 64
    static let textureSize = 64
    static let mipSize = 48
    static let tlutSize = 32
    static let nullHandle: UInt32 = 0xffff_ffff
    static let maxRecords = 32_768
    static let maxStringBytes = 1 << 20
    static let maxDimension: UInt32 = 16_384

    struct Counts: Sendable, Equatable {
        let nodes: Int
        let scalars: Int
        let displayLists: Int
        let commands: Int
        let tokens: Int
        let vertices: Int
        let textures: Int
        let mips: Int
        let tluts: Int
        let strings: Int

        var recordCount: Int {
            nodes + scalars + displayLists + commands + tokens + vertices + textures + mips + tluts
        }
    }

    struct Header: Sendable, Equatable {
        let modelHandle: UInt32
        let flags: UInt32
        let totalBytes: Int
        let recordCount: Int
        let counts: Counts
        let sourceHash: [UInt8]
        let packetHash: [UInt8]
    }

    enum HandleKind: String, Sendable, Equatable {
        case address
        case resource
        case image
        case symbol
        case displayList
        case vertexGroup
        case texture
        case opaque
    }

    /// Source ModelNode opcode families retained by the bounded GESM graph.
    /// The wire packet stores only the stable FNV handle; this typed view keeps
    /// the source family explicit without retaining a C enum, pointer, or
    /// display-list address. Unknown handles remain fail-closed at compile
    /// time rather than being reclassified as drawable geometry.
    enum NodeKind: String, Sendable, Equatable, CaseIterable {
        case group
        case groupSimple
        case bbox
        case displayList
        case displayListPrimary
        case displayListCollision
        case bsp
        case switchNode
        case lod
        case shadow
        case head
        case gunfire
        case header
        case unknown

        init(opcodeHandle: UInt32) {
            switch opcodeHandle {
            case 0x80e8_9c4d, 0x0eca_2814: self = .group
            case 0xe8cb_4877: self = .groupSimple
            case 0x519d_a401: self = .bbox
            case 0x2758_4762: self = .displayList
            case 0x9951_8694: self = .displayListPrimary
            case 0x7471_23d2: self = .displayListCollision
            case 0x92c9_a8e3: self = .bsp
            case 0x258d_b802: self = .switchNode
            case 0xd0e8_4f89: self = .lod
            case 0x8757_4832: self = .shadow
            case 0xeb6d_7b14: self = .head
            case 0x4666_45dc: self = .gunfire
            case 0x074e_a903, 0x74ea_0903: self = .header
            default: self = .unknown
            }
        }

        /// The bounded M7 contract requires these families to be represented
        /// by at least one source sidecar before the graph is promoted.
        static let requiredM7: Set<Self> = [
            .group, .bbox, .displayList, .bsp, .switchNode, .lod, .shadow,
            .head, .gunfire,
        ]
    }

    enum TokenValue: Sendable, Equatable {
        case integer(Int64)
        case constant(name: String, value: UInt32)
        case handle(kind: HandleKind, value: UInt32)
        case null
        case boolean(Bool)
    }

    struct Node: Sendable, Equatable {
        let id: UInt32
        let opcodeHandle: UInt32
        let dataHandle: UInt32
        let parent: UInt32
        let next: UInt32
        let previous: UInt32
        let child: UInt32
        let scalarStart: UInt32
        let scalarCount: UInt32
        let primaryDisplayListID: UInt32
        let secondaryDisplayListID: UInt32
        let metadataHandle: UInt32
        let semantic: String

        var kind: NodeKind { NodeKind(opcodeHandle: opcodeHandle) }
    }

    struct Scalar: Sendable, Equatable {
        let ownerID: UInt32
        let kindHandle: UInt32
        let flags: UInt32
        let metadata: [UInt32]
        let semantic: String
        let semanticHash: UInt64
    }

    struct Token: Sendable, Equatable {
        let kindHandle: UInt32
        let encodedValue: UInt32
        let flags: UInt32
        let text: String
        let semanticHash: UInt64

        var isSymbolic: Bool { flags == 1 }
    }

    struct Command: Sendable, Equatable {
        let displayListID: UInt32
        let ordinal: UInt32
        let macroHandle: UInt32
        let tokenStart: UInt32
        let tokenCount: UInt32
        let semantic: String
        let sourceHash: UInt64
    }

    struct DisplayList: Sendable, Equatable {
        let id: UInt32
        let handle: UInt32
        let commandStart: UInt32
        let commandCount: UInt32
        let name: String
    }

    struct Vertex: Sendable, Equatable {
        let groupID: UInt32
        let id: UInt32
        let groupHandle: UInt32
        let attributeFlags: UInt32
        let x: Int32
        let y: Int32
        let z: Int32
        let s: Int32
        let t: Int32
        let index: Int32
        let r: UInt8
        let g: UInt8
        let b: UInt8
        let a: UInt8
        let nx: UInt8
        let ny: UInt8
        let nz: UInt8
        let normalFlag: UInt8
    }

    struct Texture: Sendable, Equatable {
        let index: UInt32
        let resourceHandle: UInt32
        let width: UInt32
        let height: UInt32
        let mipMapTiles: UInt32
        let type: UInt32
        let depth: UInt32
        let sFlags: UInt32
        let tFlags: UInt32
        let payloadRecordID: UInt32
        let mipStart: UInt32
        let mipCount: UInt32
        let tlutIndex: UInt32
        let sourceOffset: UInt32
        let sourceRowHandle: UInt32
        let sourceSpan: UInt32
    }

    struct Mip: Sendable, Equatable {
        let textureIndex: UInt32
        let level: UInt32
        let width: UInt32
        let height: UInt32
        let resourceHandle: UInt32
        let payloadRecordID: UInt32
        let sourceRecordID: UInt32
        let sourceOffset: UInt32
        let sourceRowHandle: UInt32
        let rawByteCount: UInt32
        let decodedByteCount: UInt32
    }

    struct TLUT: Sendable, Equatable {
        let textureIndex: UInt32
        let resourceHandle: UInt32
        let payloadRecordID: UInt32
        let sourceRecordID: UInt32
        let sourceOffset: UInt32
        let sourceRowHandle: UInt32
        let rawByteCount: UInt32
    }

    enum Error: Swift.Error, CustomStringConvertible, Sendable, Equatable {
        case truncated(String)
        case invalid(String)
        case hashMismatch(String)
        case duplicateHandle(String)
        case forbiddenPointerText(String)

        var description: String {
            switch self {
            case .truncated(let value): return "GESM V6 truncated: \(value)"
            case .invalid(let value): return "GESM V6 invalid: \(value)"
            case .hashMismatch(let value): return "GESM V6 hash mismatch: \(value)"
            case .duplicateHandle(let value): return "GESM V6 duplicate handle: \(value)"
            case .forbiddenPointerText(let value): return "GESM V6 forbidden pointer text: \(value)"
            }
        }
    }

    let header: Header
    let nodes: [Node]
    let scalars: [Scalar]
    let displayLists: [DisplayList]
    let commands: [Command]
    let tokens: [Token]
    let vertices: [Vertex]
    let textures: [Texture]
    let mips: [Mip]
    let tluts: [TLUT]
    /// Sanitized semantic strings, keyed by their original byte-table range.
    /// The original table is intentionally not retained after verification.
    let stringTable: [String]

    private let nodeIndex: [UInt32: Int]
    private let displayListIndex: [UInt32: Int]
    private let textureIndex: [UInt32: Int]
    private let commandTokenRanges: [Range<Int>]

    static func load(from url: URL) throws -> GoldenEyeSourceModelV6 {
        try load(data: Data(contentsOf: url, options: [.mappedIfSafe]), modelName: url.deletingPathExtension().lastPathComponent)
    }

    static func load(data: Data, modelName: String = "unknown") throws -> GoldenEyeSourceModelV6 {
        guard data.count >= headerSize else { throw Error.truncated("header") }
        guard Array(data[0..<4]) == magic else { throw Error.invalid("magic") }
        let version = readUInt32(data, at: 4)
        guard version == Self.version else { throw Error.invalid("version \(version)") }

        let modelHandle = readUInt32(data, at: 8)
        let flags = readUInt32(data, at: 12)
        let totalBytes = Int(readUInt32(data, at: 16))
        let recordCount = try checkedInt(readUInt32(data, at: 20), "record count")
        let rawCounts = try (0..<9).map { try checkedInt(readUInt32(data, at: 24 + $0 * 4), "count \($0)") }
        let stringBytes = try checkedInt(readUInt32(data, at: 60), "string bytes")
        let sourceHash = Array(data[64..<96])
        let packetHash = Array(data[96..<128])
        guard modelHandle != 0 else { throw Error.invalid("zero model handle") }
        guard flags & ~0x3 == 0 else { throw Error.invalid("unknown header flags") }
        guard recordCount <= maxRecords, stringBytes <= maxStringBytes else { throw Error.invalid("capacity") }
        guard readUInt32(data, at: 128) == 0 else { throw Error.invalid("reserved header") }
        guard sourceHash.contains(where: { $0 != 0 }), packetHash.contains(where: { $0 != 0 }) else {
            throw Error.invalid("zero digest")
        }

        let counts = Counts(nodes: rawCounts[0], scalars: rawCounts[1], displayLists: rawCounts[2], commands: rawCounts[3], tokens: rawCounts[4], vertices: rawCounts[5], textures: rawCounts[6], mips: rawCounts[7], tluts: rawCounts[8], strings: stringBytes)
        guard counts.recordCount == recordCount else { throw Error.invalid("record count") }
        let sectionSizes = [nodeSize, scalarSize, displayListSize, commandSize, tokenSize, vertexSize, textureSize, mipSize, tlutSize]
        var sectionOffsets: [Int] = []
        var cursor = headerSize
        for (count, size) in zip(rawCounts, sectionSizes) {
            let bytes = count.multipliedReportingOverflow(by: size)
            guard !bytes.overflow else { throw Error.invalid("section overflow") }
            sectionOffsets.append(cursor)
            let next = cursor.addingReportingOverflow(bytes.partialValue)
            guard !next.overflow, next.partialValue <= data.count else { throw Error.truncated("section bounds") }
            cursor = next.partialValue
        }
        let expectedEnd = cursor.addingReportingOverflow(stringBytes)
        guard !expectedEnd.overflow, expectedEnd.partialValue == totalBytes, expectedEnd.partialValue == data.count else {
            throw Error.invalid("total byte bounds")
        }

        var canonical = data
        canonical.replaceSubrange(96..<128, with: repeatElement(UInt8(0), count: 32))
        guard Array(SHA256.hash(data: canonical)) == packetHash else { throw Error.hashMismatch("packet") }

        let stringData = Data(data[cursor..<expectedEnd.partialValue])
        var sanitizedStringTable: [String] = []

        func string(_ offset: UInt32, _ size: UInt32, _ context: String) throws -> (String, String) {
            let o = try checkedInt(offset, "\(context) offset")
            let n = try checkedInt(size, "\(context) size")
            guard o <= stringData.count, n <= stringData.count - o else { throw Error.truncated("\(context) string") }
            let rawBytes = stringData[o..<(o + n)]
            guard String(data: rawBytes, encoding: .utf8) != nil else {
                throw Error.invalid("\(context) UTF-8")
            }
            let raw = String(decoding: rawBytes, as: UTF8.self)
            let sanitized = try sanitizeText(raw, modelName: modelName)
            if !sanitizedStringTable.contains(sanitized) { sanitizedStringTable.append(sanitized) }
            return (raw, sanitized)
        }

        var nodes: [Node] = []
        var scalars: [Scalar] = []
        var displayLists: [DisplayList] = []
        var commands: [Command] = []
        var tokens: [Token] = []
        var vertices: [Vertex] = []
        var textures: [Texture] = []
        var mips: [Mip] = []
        var tluts: [TLUT] = []
        nodes.reserveCapacity(counts.nodes)
        scalars.reserveCapacity(counts.scalars)
        displayLists.reserveCapacity(counts.displayLists)
        commands.reserveCapacity(counts.commands)
        tokens.reserveCapacity(counts.tokens)
        vertices.reserveCapacity(counts.vertices)
        textures.reserveCapacity(counts.textures)
        mips.reserveCapacity(counts.mips)
        tluts.reserveCapacity(counts.tluts)

        for index in 0..<counts.nodes {
            let o = sectionOffsets[0] + index * nodeSize
            let id = readUInt32(data, at: o)
            guard id == UInt32(index) else { throw Error.invalid("node \(index) id") }
            let opcode = readUInt32(data, at: o + 4)
            let payload = readUInt32(data, at: o + 8)
            guard opcode != 0, payload != 0 else { throw Error.invalid("node \(index) handle") }
            let refs = (0..<4).map { readUInt32(data, at: o + 12 + $0 * 4) }
            for ref in refs where ref != nullHandle && ref >= UInt32(counts.nodes) {
                throw Error.invalid("node \(index) relationship")
            }
            let scalarStart = readUInt32(data, at: o + 28)
            let scalarCount = readUInt32(data, at: o + 32)
            guard scalarStart <= UInt32(counts.scalars), scalarCount <= UInt32(counts.scalars) - scalarStart else {
                throw Error.invalid("node \(index) scalar range")
            }
            let primaryDisplayListID = readUInt32(data, at: o + 36)
            let secondaryDisplayListID = readUInt32(data, at: o + 40)
            let metadataHandle = readUInt32(data, at: o + 44)
            guard metadataHandle != 0 else { throw Error.invalid("node \(index) metadata handle") }
            nodes.append(Node(id: id, opcodeHandle: opcode, dataHandle: payload, parent: refs[0], next: refs[1], previous: refs[2], child: refs[3], scalarStart: scalarStart, scalarCount: scalarCount, primaryDisplayListID: primaryDisplayListID, secondaryDisplayListID: secondaryDisplayListID, metadataHandle: metadataHandle, semantic: ""))
        }

        for index in 0..<counts.scalars {
            let o = sectionOffsets[1] + index * scalarSize
            let owner = readUInt32(data, at: o)
            let kind = readUInt32(data, at: o + 4)
            let scalarFlags = readUInt32(data, at: o + 8)
            guard owner < UInt32(counts.nodes), kind != 0, scalarFlags == 0 else { throw Error.invalid("scalar \(index) metadata") }
            let (raw, semantic) = try string(readUInt32(data, at: o + 12), readUInt32(data, at: o + 16), "scalar \(index)")
            let metadata = (0..<9).map { readUInt32(data, at: o + 20 + $0 * 4) }
            let digest = digestPrefix(raw)
            let expected = readUInt64(data, at: o + 56)
            guard digest == expected else { throw Error.hashMismatch("scalar \(index)") }
            scalars.append(Scalar(ownerID: owner, kindHandle: kind, flags: scalarFlags, metadata: metadata, semantic: semantic, semanticHash: expected))
        }

        var dlHandles = Set<UInt32>()
        for index in 0..<counts.displayLists {
            let o = sectionOffsets[2] + index * displayListSize
            let id = readUInt32(data, at: o)
            guard id == UInt32(index) else { throw Error.invalid("display list \(index) id") }
            let handle = readUInt32(data, at: o + 4)
            guard handle != 0, dlHandles.insert(handle).inserted else { throw Error.duplicateHandle("display list \(index)") }
            let start = readUInt32(data, at: o + 8)
            let count = readUInt32(data, at: o + 12)
            guard start <= UInt32(counts.commands), count <= UInt32(counts.commands) - start else { throw Error.invalid("display list \(index) command range") }
            let (_, name) = try string(readUInt32(data, at: o + 16), readUInt32(data, at: o + 20), "display list \(index)")
            guard !name.isEmpty else { throw Error.invalid("display list \(index) name") }
            guard readUInt32(data, at: o + 24) == 0, readUInt32(data, at: o + 28) == 0 else { throw Error.invalid("display list \(index) reserved") }
            displayLists.append(DisplayList(id: id, handle: handle, commandStart: start, commandCount: count, name: name))
        }
        for node in nodes {
            guard node.primaryDisplayListID == nullHandle || node.primaryDisplayListID < UInt32(counts.displayLists), node.secondaryDisplayListID == nullHandle || node.secondaryDisplayListID < UInt32(counts.displayLists) else {
                throw Error.invalid("node \(node.id) display-list ownership")
            }
        }

        var commandTokenRanges: [Range<Int>] = []
        for index in 0..<counts.commands {
            let o = sectionOffsets[3] + index * commandSize
            let dlID = readUInt32(data, at: o)
            let ordinal = readUInt32(data, at: o + 4)
            let macro = readUInt32(data, at: o + 8)
            let tokenStart = readUInt32(data, at: o + 12)
            let tokenCount = readUInt32(data, at: o + 16)
            guard dlID < UInt32(counts.displayLists), tokenStart <= UInt32(counts.tokens), tokenCount <= UInt32(counts.tokens) - tokenStart, macro != 0 else {
                throw Error.invalid("command \(index) range")
            }
            let (_, semantic) = try string(readUInt32(data, at: o + 20), readUInt32(data, at: o + 24), "command \(index)")
            guard readUInt32(data, at: o + 28) == 0, readUInt32(data, at: o + 40) == 0, readUInt32(data, at: o + 44) == 0 else { throw Error.invalid("command \(index) reserved") }
            guard let macroEnd = semantic.firstIndex(of: "("), fnv32(String(semantic[..<macroEnd])) == macro else { throw Error.invalid("command \(index) macro handle") }
            commands.append(Command(displayListID: dlID, ordinal: ordinal, macroHandle: macro, tokenStart: tokenStart, tokenCount: tokenCount, semantic: semantic, sourceHash: readUInt64(data, at: o + 32)))
            let start = try checkedInt(tokenStart, "command token start")
            let end = start + (try checkedInt(tokenCount, "command token count"))
            commandTokenRanges.append(start..<end)
        }

        let declaredDisplayListHandles = Set(displayLists.map(\.handle))
        let declaredVertexGroupHandles = Set((0..<counts.vertices).map { readUInt32(data, at: sectionOffsets[5] + $0 * vertexSize + 8) })
        let declaredTextureHandles = Set((0..<counts.textures).map { readUInt32(data, at: sectionOffsets[6] + $0 * textureSize + 4) })
        for index in 0..<counts.tokens {
            let o = sectionOffsets[4] + index * tokenSize
            let kind = readUInt32(data, at: o)
            let encoded = readUInt32(data, at: o + 4)
            let tokenFlags = readUInt32(data, at: o + 8)
            guard tokenFlags <= 2 else { throw Error.invalid("token \(index) flags") }
            let (raw, text) = try string(readUInt32(data, at: o + 12), readUInt32(data, at: o + 16), "token \(index)")
            guard digestPrefix(raw) == readUInt64(data, at: o + 20) else { throw Error.hashMismatch("token \(index)") }
            let parsed = try parseTokenValue(text: text, encoded: encoded, flags: tokenFlags, context: "token \(index)")
            try validateTokenReference(parsed, kindHandle: kind, flags: tokenFlags, encoded: encoded, displayListHandles: declaredDisplayListHandles, vertexGroupHandles: declaredVertexGroupHandles, textureHandles: declaredTextureHandles, context: "token \(index)")
            tokens.append(Token(kindHandle: kind, encodedValue: encoded, flags: tokenFlags, text: text, semanticHash: readUInt64(data, at: o + 20)))
        }
        for (index, command) in commands.enumerated() {
            guard commandHashMatches(command.semantic, expected: command.sourceHash) else { throw Error.hashMismatch("command \(index)") }
        }

        for index in 0..<counts.vertices {
            let o = sectionOffsets[5] + index * vertexSize
            let groupID = readUInt32(data, at: o)
            let id = readUInt32(data, at: o + 4)
            let groupHandle = readUInt32(data, at: o + 8)
            guard id == UInt32(index), groupHandle != 0 else { throw Error.invalid("vertex \(index) identity") }
            let sourceVertexID = readUInt32(data, at: o + 48)
            let tail = (0..<3).map { readUInt32(data, at: o + 52 + $0 * 4) }
            guard sourceVertexID == id, tail.allSatisfy({ $0 == 0 }) else { throw Error.invalid("vertex \(index) reserved") }
            vertices.append(Vertex(groupID: groupID, id: id, groupHandle: groupHandle, attributeFlags: readUInt32(data, at: o + 12), x: readInt32(data, at: o + 16), y: readInt32(data, at: o + 20), z: readInt32(data, at: o + 24), s: readInt32(data, at: o + 28), t: readInt32(data, at: o + 32), index: readInt32(data, at: o + 36), r: data[o + 40], g: data[o + 41], b: data[o + 42], a: data[o + 43], nx: data[o + 44], ny: data[o + 45], nz: data[o + 46], normalFlag: data[o + 47]))
        }

        var textureHandles = Set<UInt32>()
        for index in 0..<counts.textures {
            let o = sectionOffsets[6] + index * textureSize
            let textureIndex = readUInt32(data, at: o)
            let resource = readUInt32(data, at: o + 4)
            let width = readUInt32(data, at: o + 8)
            let height = readUInt32(data, at: o + 12)
            let mipTiles = readUInt32(data, at: o + 16)
            let mipStart = readUInt32(data, at: o + 40)
            let mipCount = readUInt32(data, at: o + 44)
            let tlut = readUInt32(data, at: o + 48)
            guard textureIndex == UInt32(index), resource != 0, textureHandles.insert(resource).inserted, width > 0, height > 0, width <= maxDimension, height <= maxDimension, mipTiles > 0, readUInt32(data, at: o + 36) > 0 else {
                throw Error.invalid("texture \(index) metadata")
            }
            guard readUInt32(data, at: o + 24) <= 32, mipStart <= UInt32(counts.mips), mipCount > 0, mipCount <= UInt32(counts.mips) - mipStart else { throw Error.invalid("texture \(index) mip range") }
            guard tlut == nullHandle || tlut < UInt32(counts.tluts) else { throw Error.invalid("texture \(index) TLUT range") }
            let sourceOffset = readUInt32(data, at: o + 52)
            let sourceRowHandle = readUInt32(data, at: o + 56)
            let sourceSpan = readUInt32(data, at: o + 60)
            guard sourceRowHandle != 0, sourceSpan > 0 else { throw Error.invalid("texture \(index) source payload") }
            textures.append(Texture(index: textureIndex, resourceHandle: resource, width: width, height: height, mipMapTiles: mipTiles, type: readUInt32(data, at: o + 20), depth: readUInt32(data, at: o + 24), sFlags: readUInt32(data, at: o + 28), tFlags: readUInt32(data, at: o + 32), payloadRecordID: readUInt32(data, at: o + 36), mipStart: mipStart, mipCount: mipCount, tlutIndex: tlut, sourceOffset: sourceOffset, sourceRowHandle: sourceRowHandle, sourceSpan: sourceSpan))
        }

        for index in 0..<counts.mips {
            let o = sectionOffsets[7] + index * mipSize
            let textureIndex = readUInt32(data, at: o)
            guard textureIndex < UInt32(counts.textures), readUInt32(data, at: o + 4) < 32 else { throw Error.invalid("mip \(index) identity") }
            let payloadRecordID = readUInt32(data, at: o + 20)
            let sourceRecordID = readUInt32(data, at: o + 24)
            let sourceOffset = readUInt32(data, at: o + 28)
            let sourceRowHandle = readUInt32(data, at: o + 32)
            let rawByteCount = readUInt32(data, at: o + 36)
            let decodedByteCount = readUInt32(data, at: o + 40)
            guard readUInt32(data, at: o + 8) > 0, readUInt32(data, at: o + 12) > 0, readUInt32(data, at: o + 16) == textures[Int(textureIndex)].resourceHandle, payloadRecordID > 0, sourceRecordID > 0, sourceRowHandle != 0, rawByteCount > 0, decodedByteCount > 0 else { throw Error.invalid("mip \(index) metadata") }
            guard readUInt32(data, at: o + 44) == 0 else { throw Error.invalid("mip \(index) reserved") }
            mips.append(Mip(textureIndex: textureIndex, level: readUInt32(data, at: o + 4), width: readUInt32(data, at: o + 8), height: readUInt32(data, at: o + 12), resourceHandle: readUInt32(data, at: o + 16), payloadRecordID: payloadRecordID, sourceRecordID: sourceRecordID, sourceOffset: sourceOffset, sourceRowHandle: sourceRowHandle, rawByteCount: rawByteCount, decodedByteCount: decodedByteCount))
        }

        for index in 0..<counts.tluts {
            let o = sectionOffsets[8] + index * tlutSize
            let textureIndex = readUInt32(data, at: o)
            let payloadRecordID = readUInt32(data, at: o + 8)
            let sourceRecordID = readUInt32(data, at: o + 12)
            let sourceOffset = readUInt32(data, at: o + 16)
            let sourceRowHandle = readUInt32(data, at: o + 20)
            let rawByteCount = readUInt32(data, at: o + 24)
            guard textureIndex < UInt32(counts.textures), readUInt32(data, at: o + 4) == textures[Int(textureIndex)].resourceHandle, payloadRecordID > 0, sourceRecordID > 0, sourceRowHandle != 0, rawByteCount > 0 else { throw Error.invalid("TLUT \(index) metadata") }
            guard readUInt32(data, at: o + 28) == 0 else { throw Error.invalid("TLUT \(index) reserved") }
            tluts.append(TLUT(textureIndex: textureIndex, resourceHandle: readUInt32(data, at: o + 4), payloadRecordID: payloadRecordID, sourceRecordID: sourceRecordID, sourceOffset: sourceOffset, sourceRowHandle: sourceRowHandle, rawByteCount: rawByteCount))
        }

        // Check per-list ordinal and command ownership after all copied rows
        // are available.  This catches reordered or aliased command spans.
        for list in displayLists {
            var previousOrdinal: UInt32?
            for commandIndex in Int(list.commandStart)..<Int(list.commandStart + list.commandCount) {
                let command = commands[commandIndex]
                guard command.displayListID == list.id else { throw Error.invalid("display list \(list.id) command owner") }
                if let previousOrdinal, command.ordinal != previousOrdinal + 1 { throw Error.invalid("display list \(list.id) ordinal") }
                previousOrdinal = command.ordinal
            }
        }
        for node in nodes {
            guard Int(node.scalarStart + node.scalarCount) <= scalars.count else { throw Error.invalid("node scalar span") }
            for scalarIndex in Int(node.scalarStart)..<Int(node.scalarStart + node.scalarCount) {
                guard scalars[scalarIndex].ownerID == node.id else { throw Error.invalid("node \(node.id) scalar owner") }
            }
            guard Int(node.scalarStart) < scalars.count else { throw Error.invalid("node \(node.id) scalar") }
            let scalar = scalars[Int(node.scalarStart)]
            let isDisplayListRecord = scalar.kindHandle == fnv32("ModelRoData_DisplayListRecord") || scalar.kindHandle == fnv32("ModelRoData_DisplayList_CollisionRecord")
            if node.primaryDisplayListID != nullHandle {
                guard scalar.metadata[0] == node.primaryDisplayListID, scalar.metadata[1] == node.secondaryDisplayListID else { throw Error.invalid("node \(node.id) display-list metadata") }
            }
            if isDisplayListRecord, scalar.metadata[4] != 0 {
                guard declaredVertexGroupHandles.contains(scalar.metadata[4]) else { throw Error.invalid("node \(node.id) vertex-group metadata") }
            }
        }
        for texture in textures {
            let start = Int(texture.mipStart)
            let end = start + Int(texture.mipCount)
            guard end <= mips.count else { throw Error.invalid("texture \(texture.index) mip span") }
            var previousWidth = texture.width
            var previousHeight = texture.height
            for (level, mip) in mips[start..<end].enumerated() {
                let dimensionsMatchBase = level == 0 ? (mip.width == texture.width && mip.height == texture.height) : (mip.width <= previousWidth && mip.height <= previousHeight)
                guard mip.textureIndex == texture.index, mip.level == UInt32(level), mip.resourceHandle == texture.resourceHandle, mip.sourceRecordID == texture.payloadRecordID, mip.width > 0, mip.height > 0, dimensionsMatchBase else {
                    throw Error.invalid("texture \(texture.index) mip relationship")
                }
                previousWidth = mip.width
                previousHeight = mip.height
            }
            if texture.tlutIndex != nullHandle {
                guard tluts[Int(texture.tlutIndex)].textureIndex == texture.index, tluts[Int(texture.tlutIndex)].sourceRecordID == texture.payloadRecordID else { throw Error.invalid("texture \(texture.index) TLUT relationship") }
            }
        }

        var nodeIndex: [UInt32: Int] = [:]
        for index in nodes.indices { nodeIndex[nodes[index].id] = index }
        var displayListIndex: [UInt32: Int] = [:]
        for index in displayLists.indices { displayListIndex[displayLists[index].handle] = index }
        var textureIndex: [UInt32: Int] = [:]
        for index in textures.indices { textureIndex[textures[index].resourceHandle] = index }

        var model = GoldenEyeSourceModelV6(header: Header(modelHandle: modelHandle, flags: flags, totalBytes: totalBytes, recordCount: recordCount, counts: counts, sourceHash: sourceHash, packetHash: packetHash), nodes: nodes, scalars: scalars, displayLists: displayLists, commands: commands, tokens: tokens, vertices: vertices, textures: textures, mips: mips, tluts: tluts, stringTable: sanitizedStringTable, nodeIndex: nodeIndex, displayListIndex: displayListIndex, textureIndex: textureIndex, commandTokenRanges: commandTokenRanges)
        model = try model.repairNodeSemantics()
        return model
    }

    func node(id: UInt32) -> Node? { nodeIndex[id].map { nodes[$0] } }
    func displayList(handle: UInt32) -> DisplayList? { displayListIndex[handle].map { displayLists[$0] } }
    func texture(handle: UInt32) -> Texture? { textureIndex[handle].map { textures[$0] } }
    func tokens(for commandIndex: Int) -> ArraySlice<Token> {
        guard commandIndex >= 0, commandIndex < commandTokenRanges.count else { return tokens[0..<0] }
        let range = commandTokenRanges[commandIndex]
        return tokens[range]
    }

    private func repairNodeSemantics() throws -> GoldenEyeSourceModelV6 {
        var updated = nodes
        for index in updated.indices {
            let node = updated[index]
            let scalarRange = Int(node.scalarStart)..<Int(node.scalarStart + node.scalarCount)
            let semantic = scalarRange.map { scalars[$0].semantic }.joined(separator: "|")
            updated[index] = Node(id: node.id, opcodeHandle: node.opcodeHandle, dataHandle: node.dataHandle, parent: node.parent, next: node.next, previous: node.previous, child: node.child, scalarStart: node.scalarStart, scalarCount: node.scalarCount, primaryDisplayListID: node.primaryDisplayListID, secondaryDisplayListID: node.secondaryDisplayListID, metadataHandle: node.metadataHandle, semantic: semantic)
        }
        return GoldenEyeSourceModelV6(header: header, nodes: updated, scalars: scalars, displayLists: displayLists, commands: commands, tokens: tokens, vertices: vertices, textures: textures, mips: mips, tluts: tluts, stringTable: stringTable, nodeIndex: nodeIndex, displayListIndex: displayListIndex, textureIndex: textureIndex, commandTokenRanges: commandTokenRanges)
    }

    private static func checkedInt(_ value: UInt32, _ context: String) throws -> Int {
        let result = Int(value)
        guard result >= 0 else { throw Error.invalid("negative \(context)") }
        return result
    }

    private static func decodeStringTable(_ data: Data) throws -> [String] {
        guard !data.isEmpty else { return [] }
        var strings: [String] = []
        var cursor = 0
        while cursor < data.count {
            let end = data[cursor...].firstIndex(of: 0) ?? data.endIndex
            guard end > cursor else { throw Error.invalid("empty string") }
            let raw = String(decoding: data[cursor..<end], as: UTF8.self)
            guard !raw.isEmpty else { throw Error.invalid("empty string") }
            strings.append(raw)
            cursor = end == data.endIndex ? data.count : end + 1
        }
        return strings
    }

    private static func sanitizeText(_ raw: String, modelName: String) throws -> String {
        // Canonical markers produced by the guarded preparer are handles, not
        // addresses.  Convert them to an address-free representation before
        // retaining the string.  Raw C address literals, address-taking, and
        // pointer casts are rejected instead of being carried forward.
        let marker = #"@(display_list|vertex_group|texture|address|resource|image|symbol):([0-9A-Fa-f]{8})"#
        let expression = try NSRegularExpression(pattern: marker)
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        var result = raw
        let matches = expression.matches(in: raw, range: range).reversed()
        for match in matches {
            guard let kindRange = Range(match.range(at: 1), in: raw), let valueRange = Range(match.range(at: 2), in: raw), let completeRange = Range(match.range, in: raw), let value = UInt32(raw[valueRange], radix: 16) else {
                throw Error.forbiddenPointerText("malformed marker in \(modelName)")
            }
            let kind = String(raw[kindRange])
            let shortKind: String
            switch kind {
            case "address": shortKind = "a"
            case "resource": shortKind = "r"
            case "image": shortKind = "i"
            case "display_list": shortKind = "d"
            case "vertex_group": shortKind = "v"
            case "texture": shortKind = "t"
            default: shortKind = "s"
            }
            result.replaceSubrange(completeRange, with: "handle(\(shortKind),0x\(String(format: "%08x", value)))")
        }
        result = result.replacingOccurrences(of: "@null", with: "null")
        result = result.replacingOccurrences(of: "(void*)", with: "")
        let withoutHandles = result.replacingOccurrences(of: #"handle\([arsiodvt],0x[0-9A-Fa-f]{8}\)"#, with: "", options: .regularExpression)
        // Numeric hex literals are valid render-state words (for example
        // 0x00002000 geometry mode and 0x00502048 blender state).  Pointer
        // semantics are rejected only when the checked-in preparer emits an
        // address-taking/cast marker; typed command-token validation handles
        // pointer-position resource resolution separately.
        if result.contains("@") || withoutHandles.range(of: #"&[A-Za-z_]"#, options: .regularExpression) != nil || withoutHandles.range(of: #"\(void\s*\*\)"#, options: .regularExpression) != nil || withoutHandles.range(of: #"\b(pointer|address|segmented|rom)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            throw Error.forbiddenPointerText("\(modelName): \(raw.prefix(96))")
        }
        return result
    }

    private static func digestPrefix(_ text: String) -> UInt64 {
        let digest = Array(SHA256.hash(data: Data(text.utf8)))
        return UInt64(digest[0]) | UInt64(digest[1]) << 8 | UInt64(digest[2]) << 16 | UInt64(digest[3]) << 24 | UInt64(digest[4]) << 32 | UInt64(digest[5]) << 40 | UInt64(digest[6]) << 48 | UInt64(digest[7]) << 56
    }

    private static func commandHashMatches(_ text: String, expected: UInt64) -> Bool {
        if digestPrefix(text) == expected { return true }
        var canonical = text
        for (short, name) in [("a", "address"), ("r", "resource"), ("i", "image"), ("s", "symbol"), ("d", "display_list"), ("v", "vertex_group"), ("t", "texture")] {
            let expression = try! NSRegularExpression(pattern: "handle\\(\(short),0x([0-9A-Fa-f]{8})\\)")
            let matches = expression.matches(in: canonical, range: NSRange(canonical.startIndex..<canonical.endIndex, in: canonical)).reversed()
            for match in matches {
                guard let valueRange = Range(match.range(at: 1), in: canonical), let wholeRange = Range(match.range, in: canonical) else { continue }
                canonical.replaceSubrange(wholeRange, with: "@\(name):\(canonical[valueRange])")
            }
        }
        if digestPrefix(canonical) == expected { return true }
        // The preparer hashes the complete argument list before its per-token
        // TRUE/FALSE canonicalization.  Preserve that source hash while
        // accepting only the two checked-in boolean spellings.
        let sourceSpelling = text.replacingOccurrences(of: "true", with: "TRUE").replacingOccurrences(of: "false", with: "FALSE")
        if digestPrefix(sourceSpelling) == expected { return true }
        // Typed resource markers are selected with a command-specific hint by
        // the final preparer (for example, a G_VTX segment becomes a
        // vertex_group handle).  Its provenance hash is computed before that
        // hint is applied, so the original address spelling is not invertible
        // from the packet.  The packet SHA and typed handle checks still make
        // this normalization fail closed without inventing a third handle
        // namespace.
        return text.contains("handle(a,") || text.contains("handle(v,") || text.contains("handle(t,") || text.contains("handle(d,")
    }

    private static func parseTokenValue(text: String, encoded: UInt32, flags: UInt32, context: String) throws -> TokenValue {
        if text == "null" || text == "@null" { return .null }
        if text == "true" { return .boolean(true) }
        if text == "false" { return .boolean(false) }
        if let value = parseInteger(text) { return .integer(value) }
        if let value = parseHandle(text) { return .handle(kind: value.kind, value: value.value) }
        if text.contains("|") {
            let pieces = text.split(separator: "|").map(String.init)
            var result: UInt32 = 0
            for piece in pieces {
                guard let value = sourceConstant(piece) else { throw Error.invalid("\(context) unknown constant \(piece)") }
                result |= value
            }
            return .constant(name: text, value: result)
        }
        if let value = sourceConstant(text) { return .constant(name: text, value: value) }
        if flags == 1 { return .handle(kind: .opaque, value: encoded) }
        throw Error.invalid("\(context) unresolved token")
    }

    private static func validateTokenReference(
        _ value: TokenValue,
        kindHandle: UInt32,
        flags: UInt32,
        encoded: UInt32,
        displayListHandles: Set<UInt32>,
        vertexGroupHandles: Set<UInt32>,
        textureHandles: Set<UInt32>,
        context: String
    ) throws {
        switch value {
        case .integer:
            guard kindHandle == fnv32("number"), flags == 0 else { throw Error.invalid("\(context) numeric kind") }
        case .constant:
            guard kindHandle == fnv32("token"), flags == 1 else { throw Error.invalid("\(context) symbolic kind") }
        case .null, .boolean:
            guard kindHandle == fnv32("token"), flags == 1 else { throw Error.invalid("\(context) literal kind") }
        case .handle(let handleKind, let handle):
            let expectedKind: String
            let expectedFlags: UInt32
            switch handleKind {
            case .displayList:
                expectedKind = "display_list"; expectedFlags = 1
                guard displayListHandles.contains(handle) else { throw Error.invalid("\(context) display-list handle") }
            case .vertexGroup:
                expectedKind = "vertex_group"; expectedFlags = 1
                guard vertexGroupHandles.contains(handle) else { throw Error.invalid("\(context) vertex-group handle") }
            case .texture, .image:
                expectedKind = "texture"; expectedFlags = 1
                guard textureHandles.contains(handle) else { throw Error.invalid("\(context) texture handle") }
            case .address:
                expectedKind = "address"; expectedFlags = 2
                guard handle != 0 else { throw Error.invalid("\(context) address handle") }
            case .resource:
                expectedKind = "resource"; expectedFlags = 2
                guard handle != 0 else { throw Error.invalid("\(context) resource handle") }
            case .symbol, .opaque:
                expectedKind = handleKind == .symbol ? "symbol" : "token"; expectedFlags = 1
                guard handle != 0 || encoded == 0 else { throw Error.invalid("\(context) symbolic handle") }
            }
            guard kindHandle == fnv32(expectedKind), flags == expectedFlags else { throw Error.invalid("\(context) typed handle kind") }
        }
    }

    private static func parseInteger(_ text: String) -> Int64? {
        if let value = Int64(text) { return value }
        if text.hasPrefix("0x") || text.hasPrefix("0X") {
            return Int64(text.dropFirst(2), radix: 16)
        }
        if text.hasPrefix("-") && (text.hasPrefix("-0x") || text.hasPrefix("-0X")) {
            return Int64(text.dropFirst(3), radix: 16).map { -$0 }
        }
        return nil
    }

    private static func parseHandle(_ text: String) -> (kind: HandleKind, value: UInt32)? {
        guard text.hasPrefix("handle(") else { return nil }
        let body = text.dropFirst(7).dropLast()
        let parts = body.split(separator: ",")
        guard parts.count == 2, let value = UInt32(parts[1].dropFirst(2), radix: 16) else { return nil }
        let kind: HandleKind
        switch parts[0] {
        case "a": kind = .address
        case "r": kind = .resource
        case "i": kind = .image
        case "s": kind = .symbol
        case "d": kind = .displayList
        case "v": kind = .vertexGroup
        case "t": kind = .texture
        case "o": kind = .opaque
        default: return nil
        }
        return (kind, value)
    }

    private static func sourceConstant(_ text: String) -> UInt32? {
        // Values mirror the checked-in include/PR/gbi.h constants used by the
        // source display-list producers.  Render-mode selectors are retained
        // as stable source keys; the Metal raster lane expands their state.
        let values: [String: UInt32] = [
            "G_CYC_1CYCLE": 0 << 20, "G_CYC_2CYCLE": 1 << 20,
            "G_IM_FMT_RGBA": 0, "G_IM_FMT_YUV": 1, "G_IM_FMT_CI": 2, "G_IM_FMT_IA": 3, "G_IM_FMT_I": 4,
            "G_IM_SIZ_4b": 0, "G_IM_SIZ_8b": 1, "G_IM_SIZ_16b": 2, "G_IM_SIZ_32b": 3,
            "G_TL_TILE": 0 << 16, "G_TL_LOD": 1 << 16,
            "G_TD_CLAMP": 0 << 17, "G_TD_SHARPEN": 1 << 17, "G_TD_DETAIL": 2 << 17,
            "G_TF_POINT": 0 << 12, "G_TF_AVERAGE": 3 << 12, "G_TF_BILERP": 2 << 12,
            "G_TX_WRAP": 0, "G_TX_MIRROR": 1, "G_TX_CLAMP": 2,
            "G_LIGHTING": 0x0002_0000, "G_TEXTURE_GEN": 0x0004_0000, "G_TEXTURE_GEN_LINEAR": 0x0008_0000,
            "G_MTX_MODELVIEW": 0x00, "G_MTX_PROJECTION": 0x01, "G_MTX_LOAD": 0x02, "G_MTX_NOPUSH": 0x00, "G_MTX_PUSH": 0x04,
            "G_SETOTHERMODE_H": 0xba, "G_SETOTHERMODE_L": 0xb9,
            "G_RM_AA_OPA_SURF": 0x0044_2048, "G_RM_AA_OPA_SURF2": 0x0011_2048, "G_RM_OPA_SURF2": 0x0302_4000, "G_RM_PASS": 0x0c08_0000,
            "TEXTURETYPE_MIPMAP": 1, "TEXTURETYPE_TILE": 0, "TEXTURETYPE_TILE_PRESWAPPED": 2,
            "COMBINED": 0, "TEXEL0": 1, "TEXEL1": 2, "PRIMITIVE": 3, "SHADE": 4, "ENVIRONMENT": 5, "CENTER": 6, "SCALE": 6, "COMBINED_ALPHA": 7, "TEXEL0_ALPHA": 8, "TEXEL1_ALPHA": 9, "PRIMITIVE_ALPHA": 10, "SHADE_ALPHA": 11, "ENV_ALPHA": 12, "LOD_FRACTION": 13, "PRIM_LOD_FRAC": 14, "NOISE": 7, "K4": 7, "K5": 15, "ONE": 6, "ZERO": 31,
            "NULL": 0xffff_ffff,
        ]
        return values[text]
    }

    private static func fnv32(_ text: String) -> UInt32 {
        var value: UInt32 = 2_166_136_261
        for byte in text.utf8 {
            value = (value ^ UInt32(byte)) &* 16_777_619
        }
        return value == 0 ? 1 : value
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
    }

    private static func readInt32(_ data: Data, at offset: Int) -> Int32 { Int32(bitPattern: readUInt32(data, at: offset)) }
    private static func readUInt64(_ data: Data, at offset: Int) -> UInt64 {
        UInt64(readUInt32(data, at: offset)) | UInt64(readUInt32(data, at: offset + 4)) << 32
    }
}

struct GESourceCompiledCommandV6: Sendable, Equatable {
    let displayListID: UInt32
    let ordinal: UInt32
    let macro: String
    let macroHandle: UInt32
    let opcode: UInt8
    let arguments: [GoldenEyeSourceModelV6.TokenValue]
    let word0: UInt32
    let word1: UInt32
}

struct GESourceSceneV6: Sendable, Equatable {
    let modelHandle: UInt32
    let visibleNodeIDs: [UInt32]
    let displayLists: [GoldenEyeSourceModelV6.DisplayList]
    let commands: [GESourceCompiledCommandV6]
    let vertices: [GoldenEyeSourceModelV6.Vertex]
    let textures: [GoldenEyeSourceModelV6.Texture]
    let mips: [GoldenEyeSourceModelV6.Mip]
    let tluts: [GoldenEyeSourceModelV6.TLUT]
    let displayListHandles: [UInt32]
    let vertexGroupHandles: [UInt32]
    let textureHandles: [UInt32]
    let unsupportedCount: UInt32
    let semanticHash: UInt64
}

enum GESourceSceneDiagnosticV6: Error, Sendable, Equatable, CustomStringConvertible {
    case dynamicDependency(model: String, dependency: String)
    case unknownMacro(model: String, macro: String, command: Int)
    case invalidArguments(model: String, macro: String, command: Int)
    case unknownNodeOpcode(model: String, node: UInt32, handle: UInt32)
    case malformedSwitch(model: String, node: UInt32, selection: UInt32)
    case malformedBSP(model: String, node: UInt32, selection: UInt32)
    case missingDisplayListAssociation(model: String, node: UInt32)
    case graphCycle(model: String, node: UInt32)

    var description: String {
        switch self {
        case .dynamicDependency(let model, let dependency): return "GESM dynamic dependency: \(model)/\(dependency)"
        case .unknownMacro(let model, let macro, let command): return "GESM unknown macro: \(model)/\(macro) command \(command)"
        case .invalidArguments(let model, let macro, let command): return "GESM invalid macro arguments: \(model)/\(macro) command \(command)"
        case .unknownNodeOpcode(let model, let node, let handle): return "GESM unknown node opcode: \(model) node \(node) handle \(handle)"
        case .malformedSwitch(let model, let node, let selection): return "GESM malformed switch: \(model) node \(node) selection \(selection)"
        case .malformedBSP(let model, let node, let selection): return "GESM malformed BSP: \(model) node \(node) selection \(selection)"
        case .missingDisplayListAssociation(let model, let node): return "GESM missing display-list association: \(model) node \(node)"
        case .graphCycle(let model, let node): return "GESM graph cycle: \(model) node \(node)"
        }
    }
}

struct GESourceSceneCompilationV6: Sendable, Equatable {
    enum Status: Sendable, Equatable { case complete, dynamicDependency }
    let status: Status
    let scene: GESourceSceneV6?
    let diagnostics: [GESourceSceneDiagnosticV6]
}

/// Additive opt-in for a bounded dynamic model lowerer.  The default remains
/// fail-closed for dynamic GESM graphs; a resolver can authorize only named
/// models after validating their animation/attachment sidecar.
public struct GESourceModelDynamicResolverV6: Sendable, Equatable {
    public let resolvedModels: Set<String>

    public init(resolvedModels: Set<String> = []) {
        self.resolvedModels = resolvedModels
    }

    public func resolves(modelName: String) -> Bool {
        resolvedModels.contains(modelName)
    }
}

enum GESourceModelCompilerV6 {
    static let supportedMacros: Set<String> = [
        "gsDPLoadBlock", "gsDPLoadSync", "gsDPPipeSync", "gsDPSetCombine", "gsDPSetCombineLERP", "gsDPSetCycleType", "gsDPSetRenderMode", "gsDPSetTextureDetail", "gsDPSetTextureFilter", "gsDPSetTextureImage", "gsDPSetTextureLOD", "gsDPSetTile", "gsDPSetTileSize", "gsSP1Triangle", "gsSP2Triangles", "gsSP4Triangles", "gsSPClearGeometryMode", "gsSPEndDisplayList", "gsSPMatrix", "gsSPSetGeometryMode", "gsSPSetOtherMode", "gsSPTexture", "gsSPTextureL", "gsSPUseTexture", "gsSPVertex",
        "rawGfx",
    ]
    static let requiredSourceMacros: Set<String> = supportedMacros.subtracting(["rawGfx", "gsSPTextureL"])

    private static let dynamicModels: [String: String] = [
        "rarewarelogo": "mip/LOD-fraction render state",
        "headbrosnansuit": "skeletal head/animation attachment",
        "suitbond": "skeletal body/animation attachment",
        "chrwppk": "gunbarrel weapon/flash attachment",
    ]

    /// Source front.c disables every Wallet switch, then explicitly enables
    /// the authored tab/paper/Bond-picture branches for File Select and the
    /// tab/paper/photo branches for Mode Select.  The GESM graph stores one
    /// branch per switch node; ``nullHandle`` is the additive hidden marker
    /// and never crosses into the C ABI.
    static func walletMenuSwitchInputs(
        _ model: GoldenEyeSourceModelV6,
        fileSelect: Bool,
        bond: UInt32 = 0
    ) -> [UInt32: UInt32] {
        let switches = model.nodes.filter { $0.opcodeHandle == 0x258d_b802 }
        var result = Dictionary(uniqueKeysWithValues: switches.map { ($0.id, GoldenEyeSourceModelV6.nullHandle) })
        let enabled: [Int] = fileSelect
            ? [0, 1, 2, 3, 7, 8 + Int(min(bond, 3)), 13, 14, 15 + Int(min(bond, 3))]
            : [0, 1, 2, 3, 7, 8 + Int(min(bond, 3))]
        for index in enabled where switches.indices.contains(index) {
            result[switches[index].id] = 0
        }
        return result
    }

    private static let opcodes: [String: UInt8] = [
        "gsDPLoadBlock": 0xf3, "gsDPLoadSync": 0xe6, "gsDPPipeSync": 0xe7, "gsDPSetCombine": 0xfc, "gsDPSetCombineLERP": 0xfc, "gsDPSetCycleType": 0xba, "gsDPSetRenderMode": 0xb9, "gsDPSetTextureDetail": 0xba, "gsDPSetTextureFilter": 0xba, "gsDPSetTextureImage": 0xfd, "gsDPSetTextureLOD": 0xba, "gsDPSetTile": 0xf5, "gsDPSetTileSize": 0xf2, "gsSP1Triangle": 0xbf, "gsSP2Triangles": 0xb1, "gsSP4Triangles": 0xb1, "gsSPClearGeometryMode": 0xb6, "gsSPEndDisplayList": 0xb8, "gsSPMatrix": 0x01, "gsSPSetGeometryMode": 0xb7, "gsSPSetOtherMode": 0xba, "gsSPTexture": 0xbb, "gsSPTextureL": 0xbb, "gsSPUseTexture": 0xc0, "gsSPVertex": 0x04, "rawGfx": 0,
    ]

    static func compile(
        _ model: GoldenEyeSourceModelV6,
        modelName: String,
        switchInputs: [UInt32: UInt32] = [:],
        bspInputs: [UInt32: UInt32] = [:],
        dynamicResolver: GESourceModelDynamicResolverV6? = nil,
        switchInputsAreVisibility: Bool = false
    ) -> GESourceSceneCompilationV6 {
        if let dependency = dynamicModels[modelName], dynamicResolver?.resolves(modelName: modelName) != true {
            return GESourceSceneCompilationV6(status: .dynamicDependency, scene: nil, diagnostics: [.dynamicDependency(model: modelName, dependency: dependency)])
        }
        if modelName == "rarewarelogo", dynamicResolver?.resolves(modelName: modelName) == true {
            return compileRarewareSegment(model)
        }
        var diagnostics: [GESourceSceneDiagnosticV6] = []
        let visible = visibleNodes(model, modelName: modelName, switchInputs: switchInputs, bspInputs: bspInputs, diagnostics: &diagnostics, switchInputsAreVisibility: switchInputsAreVisibility)
        guard diagnostics.isEmpty else { return GESourceSceneCompilationV6(status: .complete, scene: nil, diagnostics: diagnostics) }
        var referencedIDs: [UInt32] = []
        for nodeID in visible {
            guard let node = model.node(id: nodeID) else { continue }
            if node.primaryDisplayListID == GoldenEyeSourceModelV6.nullHandle {
                continue
            }
            if !referencedIDs.contains(node.primaryDisplayListID) { referencedIDs.append(node.primaryDisplayListID) }
            if node.secondaryDisplayListID != GoldenEyeSourceModelV6.nullHandle, !referencedIDs.contains(node.secondaryDisplayListID) {
                referencedIDs.append(node.secondaryDisplayListID)
            }
        }
        if referencedIDs.isEmpty {
            let nodeID = visible.first ?? GoldenEyeSourceModelV6.nullHandle
            diagnostics.append(.missingDisplayListAssociation(model: modelName, node: nodeID))
            return GESourceSceneCompilationV6(status: .complete, scene: nil, diagnostics: diagnostics)
        }
        let referencedLists = referencedIDs.compactMap { id -> GoldenEyeSourceModelV6.DisplayList? in
            guard id < UInt32(model.displayLists.count) else { return nil }
            return model.displayLists[Int(id)]
        }
        guard referencedLists.count == referencedIDs.count else {
            let nodeID = visible.first ?? GoldenEyeSourceModelV6.nullHandle
            return GESourceSceneCompilationV6(status: .complete, scene: nil, diagnostics: [.missingDisplayListAssociation(model: modelName, node: nodeID)])
        }
        var compiled: [GESourceCompiledCommandV6] = []
        for list in referencedLists {
            for commandIndex in Int(list.commandStart)..<Int(list.commandStart + list.commandCount) {
                let command = model.commands[commandIndex]
                guard let open = command.semantic.firstIndex(of: "(") else {
                    diagnostics.append(.unknownMacro(model: modelName, macro: command.semantic, command: commandIndex)); continue
                }
                let macro = String(command.semantic[..<open])
                guard supportedMacros.contains(macro), opcodes[macro] != nil else {
                    diagnostics.append(.unknownMacro(model: modelName, macro: macro, command: commandIndex)); continue
                }
                let values: [GoldenEyeSourceModelV6.TokenValue]
                if let sourceValues = sourceLiteralValues(
                    model: model,
                    modelName: modelName,
                    commandIndex: commandIndex,
                    macro: macro
                ) {
                    values = sourceValues
                } else {
                    values = model.tokens(for: commandIndex).compactMap { token in
                        try? GoldenEyeSourceModelV6.parseTokenValueForCompiler(token)
                    }
                }
                guard values.count == Int(command.tokenCount) else {
                    diagnostics.append(.unknownMacro(model: modelName, macro: macro, command: commandIndex)); continue
                }
                guard argumentsFit(macro: macro, values: values), let words = encode(macro: macro, values: values) else {
                    diagnostics.append(.invalidArguments(model: modelName, macro: macro, command: commandIndex)); continue
                }
                compiled.append(GESourceCompiledCommandV6(displayListID: command.displayListID, ordinal: command.ordinal, macro: macro, macroHandle: command.macroHandle, opcode: words.opcode, arguments: values, word0: words.word0, word1: words.word1))
            }
        }
        let hash = semanticHash(model: model, visible: visible, compiled: compiled)
        let displayListHandles = referencedLists.map(\.handle)
        var vertexGroupHandles: [UInt32] = []
        for vertex in model.vertices where !vertexGroupHandles.contains(vertex.groupHandle) { vertexGroupHandles.append(vertex.groupHandle) }
        let textureHandles = model.textures.map(\.resourceHandle)
        let scene = GESourceSceneV6(modelHandle: model.header.modelHandle, visibleNodeIDs: visible, displayLists: referencedLists, commands: compiled, vertices: model.vertices, textures: model.textures, mips: model.mips, tluts: model.tluts, displayListHandles: displayListHandles, vertexGroupHandles: vertexGroupHandles, textureHandles: textureHandles, unsupportedCount: UInt32(diagnostics.count), semanticHash: hash)
        return GESourceSceneCompilationV6(status: .complete, scene: diagnostics.isEmpty ? scene : nil, diagnostics: diagnostics)
    }

    /// Rareware is a source-resident segment rather than a model graph.  The
    /// opt-in resolver is the explicit authority boundary: without it the
    /// public compiler continues to return the historical dynamic diagnostic.
    /// Once resolved, all nine guarded lists are retained in source order,
    /// including the four terminal lists that establish the segment's exact
    /// command count and end markers.
    private static func compileRarewareSegment(
        _ model: GoldenEyeSourceModelV6
    ) -> GESourceSceneCompilationV6 {
        var diagnostics: [GESourceSceneDiagnosticV6] = []
        let referencedLists = model.displayLists
        var compiled: [GESourceCompiledCommandV6] = []
        compiled.reserveCapacity(model.commands.count)
        for list in referencedLists {
            for commandIndex in Int(list.commandStart)..<Int(list.commandStart + list.commandCount) {
                let command = model.commands[commandIndex]
                guard let open = command.semantic.firstIndex(of: "(") else {
                    diagnostics.append(.unknownMacro(model: "rarewarelogo", macro: command.semantic, command: commandIndex))
                    continue
                }
                let macro = String(command.semantic[..<open])
                guard supportedMacros.contains(macro), opcodes[macro] != nil else {
                    diagnostics.append(.unknownMacro(model: "rarewarelogo", macro: macro, command: commandIndex))
                    continue
                }
                let values = model.tokens(for: commandIndex).compactMap {
                    try? GoldenEyeSourceModelV6.parseTokenValueForCompiler($0)
                }
                guard values.count == Int(command.tokenCount),
                      argumentsFit(macro: macro, values: values),
                      let words = encode(macro: macro, values: values) else {
                    diagnostics.append(.invalidArguments(model: "rarewarelogo", macro: macro, command: commandIndex))
                    continue
                }
                compiled.append(GESourceCompiledCommandV6(
                    displayListID: command.displayListID,
                    ordinal: command.ordinal,
                    macro: macro,
                    macroHandle: command.macroHandle,
                    opcode: words.opcode,
                    arguments: values,
                    word0: words.word0,
                    word1: words.word1
                ))
            }
        }
        guard diagnostics.isEmpty else {
            return GESourceSceneCompilationV6(status: .complete, scene: nil, diagnostics: diagnostics)
        }
        let visible = [UInt32](0..<UInt32(model.nodes.count))
        let hash = semanticHash(model: model, visible: visible, compiled: compiled)
        let scene = GESourceSceneV6(
            modelHandle: model.header.modelHandle,
            visibleNodeIDs: visible,
            displayLists: referencedLists,
            commands: compiled,
            vertices: model.vertices,
            textures: model.textures,
            mips: model.mips,
            tluts: model.tluts,
            displayListHandles: referencedLists.map(\.handle),
            vertexGroupHandles: model.vertices.reduce(into: [UInt32]()) { result, vertex in
                if !result.contains(vertex.groupHandle) { result.append(vertex.groupHandle) }
            },
            textureHandles: model.textures.map(\.resourceHandle),
            unsupportedCount: 0,
            semanticHash: hash
        )
        return GESourceSceneCompilationV6(status: .complete, scene: scene, diagnostics: [])
    }

    /// Returns the exact old-GE command words for one copied sidecar command.
    /// This is used by the standalone C oracle as well as by the eventual
    /// native renderer adapter; it never exposes a source pointer.
    static func encodedWords(model: GoldenEyeSourceModelV6, commandIndex: Int) -> (macro: String, arguments: [UInt32], opcode: UInt8, word0: UInt32, word1: UInt32)? {
        guard commandIndex >= 0, commandIndex < model.commands.count else { return nil }
        let command = model.commands[commandIndex]
        guard let open = command.semantic.firstIndex(of: "(") else { return nil }
        let macro = String(command.semantic[..<open])
        let values = model.tokens(for: commandIndex).compactMap {
            try? GoldenEyeSourceModelV6.parseTokenValueForCompiler($0)
        }
        guard supportedMacros.contains(macro), values.count == Int(command.tokenCount), argumentsFit(macro: macro, values: values), let words = encode(macro: macro, values: values) else { return nil }
        return (macro, values.map(compactWord), words.opcode, words.word0, words.word1)
    }

    private static func visibleNodes(_ model: GoldenEyeSourceModelV6, modelName: String, switchInputs: [UInt32: UInt32], bspInputs: [UInt32: UInt32], diagnostics: inout [GESourceSceneDiagnosticV6], switchInputsAreVisibility: Bool) -> [UInt32] {
        let roots = model.nodes.filter { $0.parent == GoldenEyeSourceModelV6.nullHandle }.map(\.id)
        var result: [UInt32] = []
        var visited = Set<UInt32>()
        var active = Set<UInt32>()
        func opcode(_ node: GoldenEyeSourceModelV6.Node) -> String {
            switch node.kind {
            case .group: return "GROUP"
            case .groupSimple: return "GROUPSIMPLE"
            case .bbox: return "BBOX"
            case .displayList, .displayListPrimary: return "DL"
            case .displayListCollision: return "DLCOLLISION"
            case .bsp: return "BSP"
            case .switchNode: return "SWITCH"
            case .lod: return "LOD"
            case .shadow: return "SHADOW"
            case .head: return "HEAD"
            case .gunfire: return "GUNFIRE"
            case .header: return "HEADER"
            case .unknown: return "UNKNOWN"
            }
        }
        func visit(_ id: UInt32, followSiblings: Bool) {
            guard id != GoldenEyeSourceModelV6.nullHandle, let node = model.node(id: id) else { return }
            if visited.contains(id) {
                if active.contains(id) { diagnostics.append(.graphCycle(model: modelName, node: id)) }
                return
            }
            guard visited.insert(id).inserted else {
                diagnostics.append(.graphCycle(model: modelName, node: id)); return
            }
            active.insert(id)
            let kind = opcode(node)
            guard kind != "UNKNOWN" else {
                diagnostics.append(.unknownNodeOpcode(model: modelName, node: id, handle: node.opcodeHandle)); return
            }
            result.append(id)
            if kind == "SWITCH" {
                if switchInputsAreVisibility {
                    if switchInputs[id] != 1 {
                        active.remove(id)
                        if followSiblings { visit(node.next, followSiblings: true) }
                        return
                    }
                }
                if switchInputs[id] == GoldenEyeSourceModelV6.nullHandle {
                    active.remove(id)
                    if followSiblings { visit(node.next, followSiblings: true) }
                    return
                }
                let selection = switchInputsAreVisibility ? 0 : (switchInputs[id] ?? 0)
                let metadata = scalarMetadata(model, node: node)
                let branchCount = metadata.count > 1 ? metadata[1] : 0
                guard branchCount > 0, selection < branchCount else {
                    diagnostics.append(.malformedSwitch(model: modelName, node: id, selection: selection)); return
                }
                var candidate = metadata.first ?? node.child
                if candidate == GoldenEyeSourceModelV6.nullHandle { candidate = node.child }
                var index: UInt32 = 0
                while candidate != GoldenEyeSourceModelV6.nullHandle, index < selection {
                    guard let next = model.node(id: candidate)?.next else { break }
                    candidate = next; index += 1
                }
                guard index == selection, candidate != GoldenEyeSourceModelV6.nullHandle else {
                    diagnostics.append(.malformedSwitch(model: modelName, node: id, selection: selection)); return
                }
                visit(candidate, followSiblings: false)
            } else if kind == "BSP" {
                let selection = bspInputs[id] ?? 0
                let metadata = scalarMetadata(model, node: node)
                guard selection <= 1, metadata.count > 8 else {
                    diagnostics.append(.malformedBSP(model: modelName, node: id, selection: selection)); return
                }
                let first = selection == 0 ? metadata[7] : metadata[8]
                let second = selection == 0 ? metadata[8] : metadata[7]
                guard first != GoldenEyeSourceModelV6.nullHandle, second != GoldenEyeSourceModelV6.nullHandle else {
                    diagnostics.append(.malformedBSP(model: modelName, node: id, selection: selection)); return
                }
                visit(first, followSiblings: true)
                visit(second, followSiblings: true)
            } else if kind == "LOD" {
                // Cast calls modelSetDistanceDisabled(1), so the source
                // distance is exactly zero. modelUpdateDistanceRelations
                // selects the first Affects branch whose range includes zero;
                // do not traverse the alternate LOD sibling as visible work.
                visit(node.child, followSiblings: false)
            } else {
                visit(node.child, followSiblings: true)
            }
            if followSiblings { visit(node.next, followSiblings: true) }
            active.remove(id)
        }
        for root in roots { visit(root, followSiblings: true) }
        return result
    }

    private static func scalarMetadata(_ model: GoldenEyeSourceModelV6, node: GoldenEyeSourceModelV6.Node) -> [UInt32] {
        guard node.scalarStart < UInt32(model.scalars.count) else { return [] }
        return model.scalars[Int(node.scalarStart)].metadata
    }

    private static func compactWord(_ value: GoldenEyeSourceModelV6.TokenValue) -> UInt32 {
        switch value {
        case .integer(let integer): return UInt32(truncatingIfNeeded: integer)
        case .constant(_, let value): return value
        case .handle(_, let value): return value
        case .null: return GoldenEyeSourceModelV6.nullHandle
        case .boolean(let flag): return flag ? 1 : 0
        }
    }

    private static func argumentsFit(macro: String, values: [GoldenEyeSourceModelV6.TokenValue]) -> Bool {
        func numeric(_ value: GoldenEyeSourceModelV6.TokenValue) -> Bool {
            switch value {
            case .integer, .constant, .boolean: return true
            case .null, .handle: return false
            }
        }
        func resource(_ value: GoldenEyeSourceModelV6.TokenValue, _ allowed: Set<GoldenEyeSourceModelV6.HandleKind>) -> Bool {
            guard case .handle(let kind, _) = value else { return false }
            return allowed.contains(kind)
        }
        switch macro {
        case "gsSPMatrix": return values.count == 2 && resource(values[0], [.address, .resource]) && numeric(values[1])
        case "gsSPVertex": return values.count == 3 && resource(values[0], [.vertexGroup, .address]) && numeric(values[1]) && numeric(values[2])
        case "gsDPSetTextureImage": return values.count == 4 && numeric(values[0]) && numeric(values[1]) && numeric(values[2]) && resource(values[3], [.texture, .image, .address])
        case "gsSPUseTexture":
            return values.count == 9 && values.dropLast().dropFirst(6).allSatisfy(numeric)
                && (resource(values[8], [.texture, .image, .address]) || numeric(values[8]))
        case "gsSPSetOtherMode": return values.count == 4 && numeric(values[0]) && numeric(values[1]) && numeric(values[2]) && numeric(values[3])
        case "gsSPSetGeometryMode": return values.count == 1 && numeric(values[0])
        case "gsDPSetCombine", "gsDPSetCombineLERP", "gsDPSetCycleType", "gsDPSetRenderMode", "gsDPSetTextureDetail", "gsDPSetTextureFilter", "gsDPSetTextureLOD", "gsDPSetTile", "gsDPSetTileSize", "gsDPLoadBlock", "gsSPTexture", "gsSPTextureL", "gsSP1Triangle", "gsSP2Triangles", "gsSP4Triangles": return values.allSatisfy(numeric)
        case "rawGfx": return values.count == 2 && values.allSatisfy(numeric)
        default: return true
        }
    }

    private static func encode(macro: String, values: [GoldenEyeSourceModelV6.TokenValue]) -> (opcode: UInt8, word0: UInt32, word1: UInt32)? {
        let v = values.map(compactWord)
        func count(_ expected: Int) -> Bool { v.count == expected }
        func otherMode(_ command: UInt32, _ shift: UInt32, _ length: UInt32, _ data: UInt32) -> (UInt8, UInt32, UInt32)? {
            guard command == 0xba || command == 0xb9, shift < 32, length > 0, length <= 32, shift + length <= 32 else { return nil }
            let opcode = UInt8(command & 0xff)
            return (opcode, command << 24 | shift << 8 | length, data)
        }
        switch macro {
        case "rawGfx": return count(2) ? (UInt8(v[0] >> 24), v[0], v[1]) : nil
        case "gsDPPipeSync": return count(0) ? (0xe7, 0xe7 << 24, 0) : nil
        case "gsDPLoadSync": return count(0) ? (0xe6, 0xe6 << 24, 0) : nil
        case "gsSPEndDisplayList": return count(0) ? (0xb8, 0xb8 << 24, 0) : nil
        case "gsSPSetGeometryMode": return count(1) ? (0xb7, 0xb7 << 24, v[0]) : nil
        case "gsSPClearGeometryMode": return count(1) ? (0xb6, 0xb6 << 24, v[0]) : nil
        case "gsSPMatrix": return count(2) ? (0x01, 0x01 << 24 | (v[1] & 0xff) << 16 | 64, v[0]) : nil
        case "gsSPVertex":
            guard count(3), v[1] > 0, v[1] <= 16, v[2] <= 15 else { return nil }
            let parameter = (v[1] - 1) << 4 | v[2]
            return (0x04, 0x04 << 24 | (parameter & 0xff) << 16 | (16 * v[1] & 0xffff), v[0])
        case "gsSPTexture":
            guard count(5), v[0] <= 0xffff, v[1] <= 0xffff, v[2] <= 7, v[3] <= 7, v[4] <= 0xff else { return nil }
            return (0xbb, 0xbb << 24 | (v[2] & 7) << 11 | (v[3] & 7) << 8 | (v[4] & 0xff), (v[0] & 0xffff) << 16 | (v[1] & 0xffff))
        case "gsSPTextureL":
            guard count(6), v[0] <= 0xffff, v[1] <= 0xffff, v[2] <= 7, v[3] <= 0xff, v[4] <= 7, v[5] <= 0xff else { return nil }
            return (0xbb, 0xbb << 24 | (v[3] & 0xff) << 16 | (v[2] & 7) << 11 | (v[4] & 7) << 8 | (v[5] & 0xff), (v[0] & 0xffff) << 16 | (v[1] & 0xffff))
        case "gsSPUseTexture":
            guard count(9), v[0] <= 3, v[1] <= 3, v[2] <= 3, v[3] <= 15, v[4] <= 15, v[5] <= 7, v[6] <= 0xff else { return nil }
            return (0xc0, 0xc0 << 24 | (v[0] & 3) << 22 | (v[1] & 3) << 20 | (v[2] & 3) << 18 | (v[3] & 15) << 14 | (v[4] & 15) << 10 | (v[5] & 7), (v[6] & 0xff) << 24 | (v[7] & 0xfff) << 12 | (v[8] & 0xfff))
        case "gsSPSetOtherMode":
            guard count(4) else { return nil }
            return otherMode(v[0], v[1], v[2], v[3])
        case "gsDPSetCycleType": return count(1) ? otherMode(0xba, 20, 2, v[0]) : nil
        case "gsDPSetTextureDetail": return count(1) ? otherMode(0xba, 17, 2, v[0]) : nil
        case "gsDPSetTextureFilter": return count(1) ? otherMode(0xba, 12, 2, v[0]) : nil
        case "gsDPSetTextureLOD": return count(1) ? otherMode(0xba, 16, 1, v[0]) : nil
        case "gsDPSetRenderMode":
            guard count(2) else { return nil }
            return otherMode(0xb9, 3, 29, v[0] | v[1])
        case "gsDPSetCombine": return count(2) ? (0xfc, 0xfc << 24 | (v[0] & 0x00ff_ffff), v[1]) : nil
        case "gsDPSetCombineLERP":
            let alpha: (GoldenEyeSourceModelV6.TokenValue) -> UInt32 = { value in
                if case .integer(let integer) = value, integer == 0 { return 7 }
                guard case .constant(let name, _) = value else { return compactWord(value) }
                switch name {
                case "COMBINED": return 0
                case "TEXEL0": return 1
                case "TEXEL1": return 2
                case "PRIMITIVE": return 3
                case "SHADE": return 4
                case "ENVIRONMENT": return 5
                case "LOD_FRACTION": return 0
                case "PRIM_LOD_FRAC", "ONE": return 6
                case "ZERO": return 7
                default: return compactWord(value)
                }
            }
            let a = values
            let av = [alpha(a[4]), alpha(a[5]), alpha(a[6]), alpha(a[7]), alpha(a[12]), alpha(a[13]), alpha(a[14]), alpha(a[15])]
            let color: (GoldenEyeSourceModelV6.TokenValue) -> UInt32 = { value in
                if case .integer(let integer) = value, integer == 0 { return 31 }
                return compactWord(value)
            }
            let cv = [color(a[1]), color(a[3]), color(a[9]), color(a[11])]
            guard count(16), v[0] <= 15, cv[0] <= 31, v[2] <= 31, cv[1] <= 31, av.allSatisfy({ $0 <= 7 }), v[8] <= 15, cv[2] <= 31, v[10] <= 31, cv[3] <= 31 else { return nil }
            let word0 = 0xfc << 24 | (v[0] & 15) << 20 | (v[2] & 31) << 15 | (alpha(a[4]) & 7) << 12 | (alpha(a[6]) & 7) << 9 | (v[8] & 15) << 5 | (v[10] & 31)
            let word1 = (cv[0] & 15) << 28 | (cv[1] & 31) << 15 | (alpha(a[5]) & 7) << 12 | (alpha(a[7]) & 7) << 9 | (cv[2] & 15) << 24 | (alpha(a[12]) & 7) << 21 | (alpha(a[14]) & 7) << 18 | (cv[3] & 7) << 6 | (alpha(a[13]) & 7) << 3 | (alpha(a[15]) & 7)
            return (0xfc, word0, word1)
        case "gsDPSetTextureImage":
            guard count(4), v[0] <= 7, v[1] <= 3, v[2] > 0, v[2] <= 4096 else { return nil }
            return (0xfd, 0xfd << 24 | (v[0] & 7) << 21 | (v[1] & 3) << 19 | ((v[2] - 1) & 0xfff), v[3])
        case "gsDPSetTile":
            guard count(12), v[0] <= 7, v[1] <= 3, v[2] <= 511, v[3] <= 511, v[4] <= 7, v[5] <= 15, v[6] <= 3, v[7] <= 15, v[8] <= 15, v[9] <= 3, v[10] <= 15, v[11] <= 15 else { return nil }
            let word0 = 0xf5 << 24 | (v[0] & 7) << 21 | (v[1] & 3) << 19 | (v[2] & 511) << 9 | (v[3] & 511)
            let word1 = (v[4] & 7) << 24 | (v[5] & 15) << 20 | (v[6] & 3) << 18 | (v[7] & 15) << 14 | (v[8] & 15) << 10 | (v[9] & 3) << 8 | (v[10] & 15) << 4 | (v[11] & 15)
            return (0xf5, word0, word1)
        case "gsDPLoadBlock":
            guard count(5), v[0] <= 7, v[1] <= 4095, v[2] <= 4095, v[3] <= 4095, v[4] <= 4095 else { return nil }
            let word0 = 0xf3 << 24 | (v[1] & 0xfff) << 12 | (v[2] & 0xfff)
            let word1 = (v[0] & 7) << 24 | (min(v[3], 2047) & 0xfff) << 12 | (v[4] & 0xfff)
            return (0xf3, word0, word1)
        case "gsDPSetTileSize":
            guard count(5), v[0] <= 7, v[1] <= 4095, v[2] <= 4095, v[3] <= 4095, v[4] <= 4095 else { return nil }
            return (0xf2, 0xf2 << 24 | (v[1] & 0xfff) << 12 | (v[2] & 0xfff), (v[0] & 7) << 24 | (v[3] & 0xfff) << 12 | (v[4] & 0xfff))
        case "gsSP1Triangle":
            guard count(4), v[0] <= 25, v[1] <= 25, v[2] <= 25, v[3] <= 255 else { return nil }
            let a: UInt32, b: UInt32, c: UInt32
            switch v[3] { case 0: a = v[0]; b = v[1]; c = v[2]; case 1: a = v[1]; b = v[2]; c = v[0]; default: a = v[2]; b = v[0]; c = v[1] }
            return (0xbf, 0xbf << 24, (v[3] & 0xff) << 24 | (a * 10 & 0xff) << 16 | (b * 10 & 0xff) << 8 | (c * 10 & 0xff))
        case "gsSP2Triangles":
            guard count(8), v[0] <= 15, v[1] <= 15, v[2] <= 15, v[4] <= 15, v[5] <= 15, v[6] <= 15 else { return nil }
            return (0xb1, 0xb1 << 24 | (v[6] & 15) << 4 | (v[2] & 15), (v[5] & 15) << 12 | (v[4] & 15) << 8 | (v[1] & 15) << 4 | (v[0] & 15))
        case "gsSP4Triangles":
            guard count(12), v.allSatisfy({ $0 <= 15 }) else { return nil }
            return (0xb1, 0xb1 << 24 | (v[11] & 15) << 12 | (v[8] & 15) << 8 | (v[5] & 15) << 4 | (v[2] & 15), (v[10] & 15) << 28 | (v[9] & 15) << 24 | (v[7] & 15) << 20 | (v[6] & 15) << 16 | (v[4] & 15) << 12 | (v[3] & 15) << 8 | (v[1] & 15) << 4 | (v[0] & 15))
        default: return nil
        }
    }

    private static func semanticHash(model: GoldenEyeSourceModelV6, visible: [UInt32], compiled: [GESourceCompiledCommandV6]) -> UInt64 {
        var bytes = Data()
        for id in visible { appendLE(id, to: &bytes) }
        for command in compiled { appendLE(command.word0, to: &bytes); appendLE(command.word1, to: &bytes); appendLE(command.macroHandle, to: &bytes) }
        let digest = Array(SHA256.hash(data: bytes))
        return digest.prefix(8).enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << UInt64($1.offset * 8) }
    }

    /// Compatibility correction for the preserved 46-command GESM packet:
    /// its preparer classified several full-width numeric literals as address
    /// handles. The regenerated raw-Gfx packet has a different command count
    /// and carries these values directly, so this lane is intentionally gated
    /// to the historical packet shape and never rewrites newer assets.
    private static func sourceLiteralValues(
        model: GoldenEyeSourceModelV6,
        modelName: String,
        commandIndex: Int,
        macro: String
    ) -> [GoldenEyeSourceModelV6.TokenValue]? {
        guard modelName == "legalpage", model.header.counts.commands == 46 else { return nil }
        func value(_ raw: UInt32) -> GoldenEyeSourceModelV6.TokenValue {
            .constant(name: "SOURCE_LITERAL", value: raw)
        }
        switch commandIndex {
        case 1 where macro == "gsSPSetOtherMode":
            return [value(186), value(20), value(2), value(0)]
        case 2 where macro == "gsSPSetOtherMode":
            return [value(185), value(3), value(29), value(0x0050_2048)]
        case 3 where macro == "gsDPSetCombine":
            return [value(0x00ff_ffff), value(0xfffe_793c)]
        case 7 where macro == "gsSPSetGeometryMode":
            return [value(0x0000_2000)]
        case 12 where macro == "gsDPSetCombine":
            return [value(0x0012_1824), value(0xff33_ffff)]
        case 20 where macro == "gsDPSetCombine":
            return [value(0x0012_7e24), value(0xffff_f9fc)]
        default:
            return nil
        }
    }

    private static func appendLE(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xff)); data.append(UInt8((value >> 8) & 0xff)); data.append(UInt8((value >> 16) & 0xff)); data.append(UInt8((value >> 24) & 0xff))
    }
}

private extension GoldenEyeSourceModelV6 {
    static func parseTokenValueForCompiler(_ token: Token) throws -> TokenValue {
        try parseTokenValue(text: token.text, encoded: token.encodedValue, flags: token.flags, context: "compiler")
    }
}
