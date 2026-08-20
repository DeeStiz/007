import CryptoKit
import Foundation

/// Fixed-width packet emitted by prepare_native_title_geometry.py.  The
/// packet is intentionally smaller than the source model contract: it holds
/// only source-colored vertices and triangle indices from the explicitly
/// supported GBI subset.  Unsupported commands remain evidence fields.
struct GoldenEyeTitleGeometryPacket: Sendable {
    static let magic = Array("GETP".utf8)
    static let version: UInt32 = 1
    static let headerSize = 128
    static let vertexStride = 16
    static let maxVertices = 4_096
    static let maxIndices = 12_288

    // Additive source-model/material evidence bits emitted by the guarded
    // preparation script.  They are deliberately kept in the existing flags
    // word so packet records remain fixed-width and pointer-free.
    static let materialFlagsMask: UInt32 = (1 << 3) | (1 << 4) | (1 << 5)
    static let modelFlagsMask: UInt32 = (1 << 6) | (1 << 7) | (1 << 8)
        | (1 << 9)

    struct Vertex: Sendable {
        let x: Int32
        let y: Int32
        let z: Int32
        let red: UInt8
        let green: UInt8
        let blue: UInt8
        let alpha: UInt8
    }

    enum Error: Swift.Error, CustomStringConvertible {
        case truncated(String)
        case invalid(String)
        case hashMismatch

        var description: String {
            switch self {
            case .truncated(let detail): return "title geometry packet truncated: \(detail)"
            case .invalid(let detail): return "title geometry packet invalid: \(detail)"
            case .hashMismatch: return "title geometry packet SHA-256 mismatch"
            }
        }
    }

    let modelHandle: UInt32
    let flags: UInt32
    let sourceLength: UInt32
    let commandCount: UInt32
    let unsupportedCommandCount: UInt32
    let sourceHash: [UInt8]
    let packetHash: [UInt8]
    let boundsMin: SIMD3<Int32>
    let boundsMax: SIMD3<Int32>
    let vertices: [Vertex]
    let indices: [UInt32]

    var hasUnsupportedCommands: Bool { (flags & (1 << 1)) != 0 }
    var isPartialSourceSlice: Bool { (flags & (1 << 2)) != 0 }
    var materialFlags: UInt32 { flags & Self.materialFlagsMask }
    var modelFlags: UInt32 { flags & Self.modelFlagsMask }
    var usesDynamicVertexSegment: Bool { (flags & (1 << 9)) != 0 }

    static func load(from url: URL) throws -> GoldenEyeTitleGeometryPacket {
        let data = try Data(contentsOf: url)
        guard data.count >= headerSize else {
            throw Error.truncated("header (data.count)/(headerSize) bytes")
        }
        guard Array(data[0..<4]) == magic else {
            throw Error.invalid("magic")
        }
        guard readUInt32(data, at: 4) == version else {
            throw Error.invalid("version (readUInt32(data, at: 4))")
        }
        let modelHandle = readUInt32(data, at: 8)
        let flags = readUInt32(data, at: 12)
        let sourceLength = readUInt32(data, at: 16)
        let commandCount = readUInt32(data, at: 20)
        let unsupportedCommandCount = readUInt32(data, at: 24)
        let vertexCount = Int(readUInt32(data, at: 28))
        let indexCount = Int(readUInt32(data, at: 32))
        guard vertexCount > 0, vertexCount <= maxVertices else {
            throw Error.invalid("vertex count (vertexCount)")
        }
        guard indexCount > 0, indexCount <= maxIndices, indexCount % 3 == 0 else {
            throw Error.invalid("index count (indexCount)")
        }
        let end = headerSize
            .addingReportingOverflow(vertexCount * vertexStride)
        guard !end.overflow else { throw Error.invalid("vertex size overflow") }
        let indicesEnd = end.partialValue.addingReportingOverflow(indexCount * 4)
        guard !indicesEnd.overflow, indicesEnd.partialValue == data.count else {
            throw Error.truncated("payload size does not match counts")
        }

        let sourceHash = Array(data[60..<92])
        let packetHash = Array(data[92..<124])
        var canonical = data
        canonical.replaceSubrange(92..<124, with: repeatElement(UInt8(0), count: 32))
        let expectedHash = Array(SHA256.hash(data: canonical))
        guard expectedHash == packetHash else { throw Error.hashMismatch }
        guard readUInt32(data, at: 124) == 0 else {
            throw Error.invalid("reserved field")
        }

        var vertices: [Vertex] = []
        vertices.reserveCapacity(vertexCount)
        for index in 0..<vertexCount {
            let offset = headerSize + index * vertexStride
            vertices.append(
                Vertex(
                    x: readInt32(data, at: offset),
                    y: readInt32(data, at: offset + 4),
                    z: readInt32(data, at: offset + 8),
                    red: data[offset + 12],
                    green: data[offset + 13],
                    blue: data[offset + 14],
                    alpha: data[offset + 15]
                )
            )
        }

        var indices: [UInt32] = []
        indices.reserveCapacity(indexCount)
        for index in 0..<indexCount {
            let value = readUInt32(data, at: end.partialValue + index * 4)
            guard value < UInt32(vertexCount) else {
                throw Error.invalid("index (value) outside vertex count (vertexCount)")
            }
            indices.append(value)
        }

        return GoldenEyeTitleGeometryPacket(
            modelHandle: modelHandle,
            flags: flags,
            sourceLength: sourceLength,
            commandCount: commandCount,
            unsupportedCommandCount: unsupportedCommandCount,
            sourceHash: sourceHash,
            packetHash: packetHash,
            boundsMin: SIMD3(
                readInt32(data, at: 36), readInt32(data, at: 40), readInt32(data, at: 44)
            ),
            boundsMax: SIMD3(
                readInt32(data, at: 48), readInt32(data, at: 52), readInt32(data, at: 56)
            ),
            vertices: vertices,
            indices: indices
        )
    }

    /// Convert source integer coordinates to the canonical 440x330 logical
    /// canvas.  The margin preserves the source-shaped 4:3 frame while the
    /// renderer's adaptive layout handles wider drawables.
    func normalizedVertices(logicalWidth: Float = 440, logicalHeight: Float = 330) -> [GoldenEyeTitleGeometryGPUVertex] {
        normalizedVertices(logicalWidth: logicalWidth, logicalHeight: logicalHeight, placement: nil)
    }

    func normalizedVertices(
        logicalWidth: Float = 440,
        logicalHeight: Float = 330,
        placement: GoldenEyeTitleGeometryPlacement?
    ) -> [GoldenEyeTitleGeometryGPUVertex] {
        let minX = Float(boundsMin.x)
        let maxX = Float(boundsMax.x)
        let minY = Float(boundsMin.y)
        let maxY = Float(boundsMax.y)
        let width = max(maxX - minX, 1)
        let height = max(maxY - minY, 1)
        let marginX = logicalWidth * 0.06
        let marginY = logicalHeight * 0.10
        let contentWidth = logicalWidth - marginX * 2
        let contentHeight = logicalHeight - marginY * 2
        return vertices.map { vertex in
            let x = marginX + (Float(vertex.x) - minX) / width * contentWidth
            let y = marginY + (maxY - Float(vertex.y)) / height * contentHeight
            let placed: SIMD2<Float>
            if let placement {
                placed = placement.center + (SIMD2<Float>(x, y) - SIMD2<Float>(logicalWidth * 0.5, logicalHeight * 0.5)) * placement.scale
            } else {
                placed = SIMD2<Float>(x, y)
            }
            let clipX = placed.x / logicalWidth * 2 - 1
            let clipY = 1 - placed.y / logicalHeight * 2
            return GoldenEyeTitleGeometryGPUVertex(
                position: SIMD2<Float>(clipX, clipY),
                color: SIMD4<Float>(
                    Float(vertex.red) / 255,
                    Float(vertex.green) / 255,
                    Float(vertex.blue) / 255,
                    Float(vertex.alpha) / 255
                )
            )
        }
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

/// Runtime-only placement for a bounded multi-model title scene.  This is
/// not a source ABI record and stores no source pointer/address; it simply
/// keeps the separately lowered gunbarrel body, head, and attached WPPK in a
/// coherent canonical 440x330 composition.
struct GoldenEyeTitleGeometryPlacement: Sendable {
    let center: SIMD2<Float>
    let scale: Float

    static let gunbarrelBody = GoldenEyeTitleGeometryPlacement(
        center: SIMD2<Float>(214, 208), scale: 0.50
    )
    static let gunbarrelHead = GoldenEyeTitleGeometryPlacement(
        center: SIMD2<Float>(214, 124), scale: 0.28
    )
    static let gunbarrelWeapon = GoldenEyeTitleGeometryPlacement(
        center: SIMD2<Float>(292, 198), scale: 0.20
    )
}

struct GoldenEyeTitleGeometryGPUVertex: Sendable {
    var position: SIMD2<Float>
    var color: SIMD4<Float>
}

/// Prepared source texture atlas emitted from assets/rarewarelogo.c.  The
/// source has four 32x43 RGBA5551 images; preparation packs them into a 64x86
/// RGBA8 atlas.  Runtime verifies this packet hash and never opens a ROM.
struct GoldenEyeRarewareTexturePacket: Sendable {
    enum Error: Swift.Error, CustomStringConvertible {
        case truncated
        case invalid(String)
        case hashMismatch

        var description: String {
            switch self {
            case .truncated: return "rareware texture packet truncated"
            case .invalid(let detail): return "rareware texture packet invalid: \(detail)"
            case .hashMismatch: return "rareware texture packet SHA-256 mismatch"
            }
        }
    }

    let width: Int
    let height: Int
    let sourceHash: [UInt8]
    let packetHash: [UInt8]
    let rgba8: [UInt8]

    static func load(from url: URL) throws -> GoldenEyeRarewareTexturePacket {
        let data = try Data(contentsOf: url)
        let headerSize = 84
        guard data.count >= headerSize else { throw Error.truncated }
        guard Array(data[0..<4]) == Array("GETX".utf8) else { throw Error.invalid("magic") }
        guard readUInt32(data, at: 4) == 1 else { throw Error.invalid("version") }
        let width = Int(readUInt32(data, at: 8))
        let height = Int(readUInt32(data, at: 12))
        let payloadLength = Int(readUInt32(data, at: 16))
        guard width == 64, height == 86, payloadLength == width * height * 4 else {
            throw Error.invalid("dimensions/payload")
        }
        guard data.count == headerSize + payloadLength else { throw Error.truncated }
        let sourceHash = Array(data[20..<52])
        let packetHash = Array(data[52..<84])
        var canonical = data
        canonical.replaceSubrange(52..<84, with: repeatElement(UInt8(0), count: 32))
        guard Array(SHA256.hash(data: canonical)) == packetHash else { throw Error.hashMismatch }
        return GoldenEyeRarewareTexturePacket(
            width: width,
            height: height,
            sourceHash: sourceHash,
            packetHash: packetHash,
            rgba8: Array(data[headerSize..<data.count])
        )
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }
}
