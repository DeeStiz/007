import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum GoldenEyeReferenceCaptureCodecV6Error: Error, CustomStringConvertible {
    case invalidDimensions
    case invalidByteCount
    case colorSpaceUnavailable
    case imageCreationFailed
    case pngDestinationUnavailable
    case pngFinalizeFailed
    case pngSourceUnavailable
    case pngImageUnavailable
    case contextUnavailable

    var description: String {
        switch self {
        case .invalidDimensions: return "invalid reference capture dimensions"
        case .invalidByteCount: return "reference capture byte count does not match dimensions"
        case .colorSpaceUnavailable: return "sRGB color space unavailable"
        case .imageCreationFailed: return "could not create image from BGRA8 capture"
        case .pngDestinationUnavailable: return "could not create PNG destination"
        case .pngFinalizeFailed: return "could not finalize PNG destination"
        case .pngSourceUnavailable: return "could not create PNG image source"
        case .pngImageUnavailable: return "could not decode PNG image"
        case .contextUnavailable: return "could not create BGRA8 decode context"
        }
    }
}

/// Lossless presentation codec for the raw 320x240 reference evidence.
/// Metal's `.bgra8Unorm` byte order is retained in the raw file.  CoreGraphics
/// receives the same bytes as little-endian premultiplied-first 32-bit pixels,
/// which explicitly maps BGRA memory to the intended RGBA image channels.
enum GoldenEyeReferenceCaptureCodecV6 {
    struct DecodedPNG: Sendable {
        let width: Int
        let height: Int
        let bytesPerRow: Int
        let bgra8: Data
    }

    static func encodePNG(
        bgra8: Data,
        width: Int,
        height: Int,
        bytesPerRow: Int
    ) throws -> Data {
        guard width > 0, height > 0, bytesPerRow >= width * 4 else {
            throw GoldenEyeReferenceCaptureCodecV6Error.invalidDimensions
        }
        guard bgra8.count >= bytesPerRow * height else {
            throw GoldenEyeReferenceCaptureCodecV6Error.invalidByteCount
        }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw GoldenEyeReferenceCaptureCodecV6Error.colorSpaceUnavailable
        }
        // Reference targets are opaque BGRA8 evidence. `premultipliedFirst`
        // would round anti-aliased glyph RGB values during PNG round-trip;
        // skip the known opaque alpha byte so the raw RGB bytes remain exact.
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue)
        )
        guard let provider = CGDataProvider(data: bgra8 as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw GoldenEyeReferenceCaptureCodecV6Error.imageCreationFailed
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw GoldenEyeReferenceCaptureCodecV6Error.pngDestinationUnavailable
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw GoldenEyeReferenceCaptureCodecV6Error.pngFinalizeFailed
        }
        return output as Data
    }

    static func decodePNG(_ png: Data) throws -> DecodedPNG {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil) else {
            throw GoldenEyeReferenceCaptureCodecV6Error.pngSourceUnavailable
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw GoldenEyeReferenceCaptureCodecV6Error.pngImageUnavailable
        }
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var output = Data(repeating: 0, count: bytesPerRow * height)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw GoldenEyeReferenceCaptureCodecV6Error.colorSpaceUnavailable
        }
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue)
        )
        let drawn = output.withUnsafeMutableBytes { rawBytes -> Bool in
            guard let baseAddress = rawBytes.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo.rawValue
                  ) else {
                return false
            }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else {
            throw GoldenEyeReferenceCaptureCodecV6Error.contextUnavailable
        }
        return DecodedPNG(width: width, height: height, bytesPerRow: bytesPerRow, bgra8: output)
    }
}
