#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif
import Foundation

/// Swift's value-only adapter for the classic GE/F3D texture-coordinate
/// lowerer.  The C record keeps the exact source command words and all fixed-
/// point intermediates; this type adds ergonomic construction and checked
/// conversion for the later Metal scene consumer.
public enum GoldenEyeSourceTextureCoordinatesV6Error: Error, CustomStringConvertible, Equatable, Sendable {
    case invalid(UInt32, UInt32)

    public var description: String {
        switch self {
        case let .invalid(status, diagnostic):
            return "source texture-coordinate lowering failed: status=\(status) diagnostic=\(diagnostic)"
        }
    }
}

public struct GoldenEyeSourceTextureCoordinateV6: Sendable {
    public let result: GETextureCoordinateResultV6

    public init(result: GETextureCoordinateResultV6) throws {
        guard result.status == GE_STATUS_OK else {
            throw GoldenEyeSourceTextureCoordinatesV6Error.invalid(
                result.status,
                result.diagnostic
            )
        }
        self.result = result
    }

    public var normalized: SIMD2<Float> {
        SIMD2(
            Self.q16(result.normalized_s_q16),
            Self.q16(result.normalized_t_q16)
        )
    }

    public var tileNormalized: SIMD2<Float> {
        SIMD2(
            Self.q16(result.tile_normalized_s_q16),
            Self.q16(result.tile_normalized_t_q16)
        )
    }

    public var scaledTexel: SIMD2<Double> {
        SIMD2(
            Double(result.scaled_s_q16) / 65_536.0,
            Double(result.scaled_t_q16) / 65_536.0
        )
    }

    public var sourceLink: (commandOffset: UInt32, vertexIndex: UInt32, textureHandle: UInt32) {
        (
            result.source_command_offset,
            result.source_vertex_index,
            result.texture_handle
        )
    }

    public var coordinateHash: UInt64 { result.result_hash }

    public static func lower(
        _ input: GETextureCoordinateInputV6
    ) throws -> GoldenEyeSourceTextureCoordinateV6 {
        var input = input
        var result = GETextureCoordinateResultV6()
        let status = ge_source_texture_coordinates_v6_lower(&input, &result)
        guard status == GE_STATUS_OK else {
            throw GoldenEyeSourceTextureCoordinatesV6Error.invalid(
                status,
                result.diagnostic
            )
        }
        return try GoldenEyeSourceTextureCoordinateV6(result: result)
    }

    /// Build an input from source values without converting the S10.5 vertex
    /// coordinates through Float.  The caller supplies exact classic command
    /// words so the tile's lrt and all mask/shift fields remain observable.
    public static func input(
        sourceCommandOffset: UInt32,
        sourceVertexIndex: UInt32,
        textureHandle: UInt32,
        sourceS10_5: Int32,
        sourceT10_5: Int32,
        textureCommandW0: UInt32,
        textureCommandW1: UInt32,
        tileCommandW0: UInt32,
        tileCommandW1: UInt32,
        tileSizeCommandW0: UInt32,
        tileSizeCommandW1: UInt32,
        maxLevel: UInt32,
        levelCount: UInt32,
        levelWidth: UInt32,
        levelHeight: UInt32,
        flags: UInt32 = 0,
        sourceStateHash: UInt64 = 0,
        sourceCommandHash: UInt64 = 0
    ) -> GETextureCoordinateInputV6 {
        var value = GETextureCoordinateInputV6()
        value.header.abi_version = GE_SOURCE_TEXTURE_COORDINATES_V6_ABI_VERSION
        value.header.struct_size = UInt32(MemoryLayout<GETextureCoordinateInputV6>.size)
        value.record_version = GE_SOURCE_TEXTURE_COORDINATES_V6_RECORD_VERSION
        value.flags = flags
        value.source_command_offset = sourceCommandOffset
        value.source_vertex_index = sourceVertexIndex
        value.texture_handle = textureHandle
        value.source_s10_5 = sourceS10_5
        value.source_t10_5 = sourceT10_5
        value.texture_command_w0 = textureCommandW0
        value.texture_command_w1 = textureCommandW1
        value.tile_command_w0 = tileCommandW0
        value.tile_command_w1 = tileCommandW1
        value.tile_size_command_w0 = tileSizeCommandW0
        value.tile_size_command_w1 = tileSizeCommandW1
        value.max_level = maxLevel
        value.level_count = levelCount
        value.level_width = levelWidth
        value.level_height = levelHeight
        value.source_state_hash = sourceStateHash
        value.source_command_hash = sourceCommandHash
        value.reserved0 = 0
        value.reserved1 = 0
        return value
    }

    public static func q16(_ value: Int64) -> Float {
        Float(Double(value) / 65_536.0)
    }

    private static func q16(_ value: Int32) -> Float {
        q16(Int64(value))
    }
}
