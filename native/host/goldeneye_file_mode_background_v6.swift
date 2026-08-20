import CryptoKit
import Foundation

/// Source-owned File/Mode background contract from title2.c.  The payload is
/// the guarded 440x299 I8 row stream; this value-only record keeps the exact
/// row data and the source compositor constants separate from any Metal pass.
public struct GoldenEyeFileModeBackgroundContractV6: Sendable, Equatable {
    public static let width: Int32 = 440
    public static let height: Int32 = 299
    public static let yOrigin: Int32 = 16
    public static let xOffset: Int32 = -28
    public static let topColor: UInt8 = 0x14
    public static let bottomColor: UInt8 = 0x32
    public static let environmentAlpha: UInt8 = 0x14

    public let pixels: [UInt8]
    /// RGBA8 source-composited rows for the native 2D texture resource. The
    /// x offset and black border remain packet geometry, not baked pixels.
    public let compositedPixels: [UInt8]
    public let sourceSHA256: String
    public let contractHash: UInt64

    public init(encoded: Data) throws {
        guard encoded.count >= 10 else { throw Error.truncated }
        let width = Int(Self.readBE16(encoded, at: 0))
        let height = Int(Self.readBE16(encoded, at: 2))
        guard width == Int(Self.width), height == Int(Self.height) else {
            throw Error.dimensions(width: width, height: height)
        }
        var cursor = 10
        var decoded: [UInt8] = []
        decoded.reserveCapacity(width * height)
        while decoded.count < width * height {
            guard cursor + 1 < encoded.count else { throw Error.truncated }
            let run = Int(encoded[cursor])
            let value = encoded[cursor + 1]
            cursor += 2
            guard run > 0, decoded.count + run <= width * height else {
                throw Error.invalidRun
            }
            decoded.append(contentsOf: repeatElement(value, count: run))
        }
        guard decoded.count == width * height else { throw Error.invalidRun }
        pixels = decoded
        var composited = [UInt8]()
        composited.reserveCapacity(width * height * 4)
        for row in 0..<height {
            let delta = Int(Self.bottomColor) - Int(Self.topColor)
            let primitive = Int(Self.topColor) + (delta * row) / Int(Self.height)
            let alpha = Int(Self.environmentAlpha)
            for column in 0..<width {
                let texel = Int(decoded[row * width + column])
                let value = max(0, min(255, primitive + ((texel - primitive) * alpha + 127) / 255))
                composited.append(UInt8(value)); composited.append(UInt8(value));
                composited.append(UInt8(value)); composited.append(255)
            }
        }
        compositedPixels = composited
        sourceSHA256 = SHA256.hash(data: encoded).map { String(format: "%02x", $0) }.joined()
        var hash: UInt64 = 1_469_598_103_934_665_603
        func mix(_ value: UInt64) { hash = (hash ^ value) &* 1_099_511_628_211 }
        mix(UInt64(width)); mix(UInt64(height)); mix(UInt64(Self.yOrigin));
        mix(UInt64(bitPattern: Int64(Self.xOffset))); mix(UInt64(Self.topColor));
        mix(UInt64(Self.bottomColor)); mix(UInt64(Self.environmentAlpha))
        for byte in decoded { mix(UInt64(byte)) }
        contractHash = hash == 0 ? 1 : hash
    }

    public enum Error: Swift.Error, CustomStringConvertible, Sendable, Equatable {
        case truncated
        case dimensions(width: Int, height: Int)
        case invalidRun

        public var description: String {
            switch self {
            case .truncated: return "File/Mode background payload is truncated"
            case let .dimensions(width, height): return "File/Mode background dimensions " + String(width) + "x" + String(height)
            case .invalidRun: return "File/Mode background RLE run is invalid"
            }
        }
    }

    public var rowCount: Int { Int(Self.height) }

    public var rightBorderWidth: Int { max(0, -Int(Self.xOffset)) }

    public func sourceIntensity(row: Int, column: Int) -> UInt8 {
        guard (0..<Int(Self.height)).contains(row), (0..<Int(Self.width)).contains(column) else { return 0 }
        return pixels[row * Int(Self.width) + column]
    }

    /// The source texture rectangle starts at x=-28, leaving a 28-pixel
    /// opaque-black right border on the 440-unit canvas.
    public func sourceColumn(forCanvasColumn column: Int) -> Int? {
        let source = column - Int(Self.xOffset)
        return (0..<Int(Self.width)).contains(source) ? source : nil
    }

    /// PrimColor's per-row source interpolation. The source loop uses 299.0f
    /// and emits rows 0...298, so this intentionally does not force row 298
    /// to the bottom endpoint.
    public func primaryColor(row: Int) -> UInt8 {
        guard (0..<Int(Self.height)).contains(row) else { return 0 }
        let delta = Int(Self.bottomColor) - Int(Self.topColor)
        return UInt8(max(0, min(255, Int(Self.topColor) + (delta * row) / Int(Self.height))))
    }

    /// The source combiner is TEXEL0-PRIMITIVE multiplied by ENV_ALPHA, then
    /// added to PRIMITIVE. All three channels use the same grayscale values.
    public func compositedIntensity(row: Int, column: Int) -> UInt8 {
        guard let sourceColumn = sourceColumn(forCanvasColumn: column),
              (0..<Int(Self.height)).contains(row) else { return 0 }
        let texel = Int(sourceIntensity(row: row, column: sourceColumn))
        let primitive = Int(primaryColor(row: row))
        let alpha = Int(Self.environmentAlpha)
        let value = primitive + ((texel - primitive) * alpha + 127) / 255
        return UInt8(max(0, min(255, value)))
    }

    private static func readBE16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }
}
