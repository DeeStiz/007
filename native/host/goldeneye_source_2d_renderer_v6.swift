import Foundation
import Metal
import QuartzCore
import simd

/// GPU-side errors are explicit.  A source frame with an unknown icon/font,
/// malformed glyph metrics, or a capacity overflow is rejected before any
/// visible fallback can be encoded.
@available(macOS 26.0, *)
enum GoldenEyeSource2DMetalRendererV6Error: Error, Sendable, CustomStringConvertible {
    case unsupportedFrame(UInt32)
    case missingResource(UInt32)
    case missingFont(UInt32)
    case invalidGlyph(UInt32, UInt32)
    case invalidTextureCoordinates
    case invalidDimensions
    case capacityExceeded(Int)
    case invalidScissor
    case metalAllocationFailed(String)
    case uploadFailed(String)
    case encoderUnavailable
    case slotTimeout(Int)

    var description: String {
        switch self {
        case .unsupportedFrame(let count):
            return "source 2D V6 frame has unsupported visible events: \(count)"
        case .missingResource(let id):
            return "source 2D V6 texture resource is missing: \(id)"
        case .missingFont(let id):
            return "source 2D V6 font resource is missing: \(id)"
        case .invalidGlyph(let font, let glyph):
            return "source 2D V6 glyph is invalid: font=\(font) glyph=\(glyph)"
        case .invalidTextureCoordinates:
            return "source 2D V6 texture coordinates are outside Q16 source range"
        case .invalidDimensions:
            return "source 2D V6 output dimensions are invalid"
        case .capacityExceeded(let count):
            return "source 2D V6 vertex capacity exceeded: \(count)"
        case .invalidScissor:
            return "source 2D V6 scissor is empty or outside output"
        case .metalAllocationFailed(let name):
            return "source 2D V6 Metal allocation failed: \(name)"
        case .uploadFailed(let detail):
            return "source 2D V6 texture upload failed: \(detail)"
        case .encoderUnavailable:
            return "source 2D V6 command encoder unavailable"
        case .slotTimeout(let slot):
            return "source 2D V6 frame slot timeout: \(slot)"
        }
    }
}

/// The host-side vertex mirrors ``GoldenEyeSource2DV6Vertex`` in the shader.
/// It is intentionally a fixed-width, pointer-free value and is written into
/// a reusable shared frame buffer rather than passed with setBytes.
struct GoldenEyeSource2DMetalVertexV6: Sendable, Equatable {
    var position: SIMD2<Float>
    var uv: SIMD2<Float>
    var color: SIMD4<Float>

    init(position: SIMD2<Float>, uv: SIMD2<Float> = .zero, color: SIMD4<Float>) {
        self.position = position
        self.uv = uv
        self.color = color
    }
}

private struct GoldenEyeSource2DMetalUniformsV6 {
    var outputSize: SIMD2<Float>
    var origin: SIMD2<Float>
    var scale: Float
    var logicalWidth: Float
    var logicalHeight: Float
    var reserved0: UInt32 = 0
    var reserved1: UInt32 = 0
}

enum GoldenEyeSource2DMetalPrimitiveV6: UInt32, Sendable, Equatable {
    case fill = 0
    case texture = 1
    case glyph = 2
}

struct GoldenEyeSource2DMetalDrawV6: Sendable, Equatable {
    let primitive: GoldenEyeSource2DMetalPrimitiveV6
    let resourceID: UInt32
    let vertexStart: Int
    let scissor: MTLScissorRect
    let sequence: UInt64

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.primitive == rhs.primitive && lhs.resourceID == rhs.resourceID
            && lhs.vertexStart == rhs.vertexStart && lhs.sequence == rhs.sequence
            && lhs.scissor.x == rhs.scissor.x && lhs.scissor.y == rhs.scissor.y
            && lhs.scissor.width == rhs.scissor.width && lhs.scissor.height == rhs.scissor.height
    }
}

/// CPU batch lowering is kept separate from Metal object creation so tests
/// can prove the exact Legal packet (including glyph atlas coordinates) on a
/// machine without a drawable.  The same values are written to the GPU frame
/// buffer by ``GoldenEyeSource2DMetalRendererV6``.
struct GoldenEyeSource2DMetalBatchV6: Sendable, Equatable {
    let vertices: [GoldenEyeSource2DMetalVertexV6]
    let draws: [GoldenEyeSource2DMetalDrawV6]
    let sourceFrameHash: UInt64
    let resourceHash: UInt64
    let geometryHash: UInt64
}

private struct GoldenEyeSource2DUploadRangeV6 {
    let offset: Int
    let bytesPerRow: Int
    let width: Int
    let height: Int
    let bytes: [UInt8]
    let pixelFormat: MTLPixelFormat
    let key: UInt32
}

private struct GoldenEyeSource2DTextureRecordV6 {
    let key: UInt32
    let texture: any MTLTexture
}

/// Strict source 2D batch builder.  Icons are catalog RGBA8 payloads and
/// fonts are source I8 atlases built from the decoded GETF metrics/pixels.
/// No block font, procedural icon, or placeholder shape is synthesized here.
enum GoldenEyeSource2DMetalBatchBuilderV6 {
    static let atlasWidth = 16 * 16
    static let atlasHeight = 6 * 16

    static func fontUploadKey(_ fontID: UInt32) -> UInt32 {
        0xF000_0000 | (fontID & 0x0FFF_FFFF)
    }

    static func build(
        frame: GoldenEyeSource2DFrameV6,
        assets: GoldenEyeSource2DAssetsV6,
        outputWidth: Int,
        outputHeight: Int,
        mode: GoldenEyeFidelityOutputMode
    ) throws -> GoldenEyeSource2DMetalBatchV6 {
        guard outputWidth > 0, outputHeight > 0 else {
            throw GoldenEyeSource2DMetalRendererV6Error.invalidDimensions
        }
        guard frame.unsupportedVisibleCount == 0 else {
            throw GoldenEyeSource2DMetalRendererV6Error.unsupportedFrame(frame.unsupportedVisibleCount)
        }
        guard frame.logicalWidth == GoldenEyeSource2DLowererV6.logicalWidth,
              frame.logicalHeight == GoldenEyeSource2DLowererV6.logicalHeight else {
            throw GoldenEyeSource2DMetalRendererV6Error.invalidDimensions
        }
        let layout = GoldenEyeFidelityLayout(
            mode: mode,
            drawableWidth: Double(outputWidth),
            drawableHeight: Double(outputHeight)
        )
        if mode == .reference320x240, (outputWidth, outputHeight) != (320, 240) {
            throw GoldenEyeSource2DMetalRendererV6Error.invalidDimensions
        }

        var vertices: [GoldenEyeSource2DMetalVertexV6] = []
        var draws: [GoldenEyeSource2DMetalDrawV6] = []
        vertices.reserveCapacity((frame.fills.count + frame.textureRects.count + frame.glyphs.count) * 6)

        func appendQuad(
            rect: GoldenEyeSource2DRectV6,
            uv0: SIMD2<Float>,
            uv1: SIMD2<Float>,
            color: SIMD4<Float>,
            primitive: GoldenEyeSource2DMetalPrimitiveV6,
            resourceID: UInt32,
            scissor: GoldenEyeSource2DScissorV6,
            sequence: UInt64,
            rotate90Clockwise: Bool = false
        ) throws {
            let effectiveRect = rotate90Clockwise
                ? GoldenEyeSource2DRectV6(
                    x: rect.x, y: rect.y,
                    width: rect.height, height: rect.width
                )
                : rect
            let sourceRect = GoldenEyeFidelityLayout.Rect(
                minX: Double(effectiveRect.x), minY: Double(effectiveRect.y),
                maxX: Double(effectiveRect.x) + Double(effectiveRect.width),
                maxY: Double(effectiveRect.y) + Double(effectiveRect.height)
            )
            let outputRect = layout.sourceToOutputRect(sourceRect)
            let x0 = Float(outputRect.minX)
            let y0 = Float(outputRect.minY)
            let x1 = Float(outputRect.maxX)
            let y1 = Float(outputRect.maxY)
            guard x1 > x0, y1 > y0 else { throw GoldenEyeSource2DMetalRendererV6Error.invalidScissor }
            let start = vertices.count
            let p0 = SIMD2<Float>(Float(effectiveRect.x), Float(effectiveRect.y))
            let p1 = SIMD2<Float>(Float(effectiveRect.x) + Float(effectiveRect.width), Float(effectiveRect.y))
            let p2 = SIMD2<Float>(Float(effectiveRect.x) + Float(effectiveRect.width), Float(effectiveRect.y) + Float(effectiveRect.height))
            let p3 = SIMD2<Float>(Float(effectiveRect.x), Float(effectiveRect.y) + Float(effectiveRect.height))
            if rotate90Clockwise {
                // A source ROT_90CW text run rotates each glyph and swaps its
                // output extent.  Rotate UVs with the quad so Bank Gothic's
                // authored atlas pixels are not replaced by a host font or a
                // merely vertical stack of unrotated letters.
                vertices.append(.init(position: p0, uv: SIMD2(uv0.x, uv1.y), color: color))
                vertices.append(.init(position: p1, uv: SIMD2(uv0.x, uv0.y), color: color))
                vertices.append(.init(position: p2, uv: SIMD2(uv1.x, uv0.y), color: color))
                vertices.append(.init(position: p0, uv: SIMD2(uv0.x, uv1.y), color: color))
                vertices.append(.init(position: p2, uv: SIMD2(uv1.x, uv0.y), color: color))
                vertices.append(.init(position: p3, uv: SIMD2(uv1.x, uv1.y), color: color))
            } else {
                vertices.append(.init(position: p0, uv: SIMD2(uv0.x, uv0.y), color: color))
                vertices.append(.init(position: p1, uv: SIMD2(uv1.x, uv0.y), color: color))
                vertices.append(.init(position: p2, uv: SIMD2(uv1.x, uv1.y), color: color))
                vertices.append(.init(position: p0, uv: SIMD2(uv0.x, uv0.y), color: color))
                vertices.append(.init(position: p2, uv: SIMD2(uv1.x, uv1.y), color: color))
                vertices.append(.init(position: p3, uv: SIMD2(uv0.x, uv1.y), color: color))
            }
            let clipSource = intersect(scissor.rect, frame.scissor.rect)
            let clip = try metalScissor(source: clipSource, layout: layout)
            _ = (x0, y0, x1, y1) // vertex positions stay in source space for exact mapping
            draws.append(.init(primitive: primitive, resourceID: resourceID, vertexStart: start, scissor: clip, sequence: sequence))
        }

        for fill in frame.fills {
            try appendQuad(
                rect: fill.rect,
                uv0: .zero,
                uv1: SIMD2(1, 1),
                color: rgba(fill.rgba),
                primitive: .fill,
                resourceID: 0,
                scissor: fill.scissor,
                sequence: fill.sequence
            )
        }

        for textureRect in frame.textureRects {
            guard textureRect.u0Q16 <= 65_536, textureRect.v0Q16 <= 65_536,
                  textureRect.u1Q16 <= 65_536, textureRect.v1Q16 <= 65_536,
                  textureRect.u1Q16 >= textureRect.u0Q16,
                  textureRect.v1Q16 >= textureRect.v0Q16 else {
                throw GoldenEyeSource2DMetalRendererV6Error.invalidTextureCoordinates
            }
            guard assets.icons.values.contains(where: { $0.sourceRecordID == textureRect.resourceRecordID })
                    || assets.fileModeBackground.sourceRecordID == textureRect.resourceRecordID else {
                throw GoldenEyeSource2DMetalRendererV6Error.missingResource(textureRect.resourceRecordID)
            }
            // front.c's display_image_at_position() passes flipY=1 for the
            // frontend image rows and cursor.  The decoded GETI payload is
            // kept in source row order, so apply that source operation at the
            // texture boundary by reversing V while preserving U.
            let flipV = textureRect.flags & 1 != 0
            try appendQuad(
                rect: textureRect.rect,
                uv0: SIMD2(
                    Float(textureRect.u0Q16) / 65_536.0,
                    Float(flipV ? textureRect.v1Q16 : textureRect.v0Q16) / 65_536.0
                ),
                uv1: SIMD2(
                    Float(textureRect.u1Q16) / 65_536.0,
                    Float(flipV ? textureRect.v0Q16 : textureRect.v1Q16) / 65_536.0
                ),
                color: rgba(textureRect.tintRGBA),
                primitive: .texture,
                resourceID: textureRect.resourceRecordID,
                scissor: textureRect.scissor,
                sequence: textureRect.sequence
            )
        }

        for glyph in frame.glyphs {
            guard let fontID = GoldenEyeSource2DFontIDV6(rawValue: glyph.fontID) else {
                throw GoldenEyeSource2DMetalRendererV6Error.missingFont(glyph.fontID)
            }
            let font = assets.font(fontID)
            guard font.glyphs.indices.contains(Int(glyph.glyphIndex)) else {
                throw GoldenEyeSource2DMetalRendererV6Error.invalidGlyph(glyph.fontID, glyph.glyphIndex)
            }
            let sourceGlyph = font.glyphs[Int(glyph.glyphIndex)]
            let rotated = glyph.flags & 2 != 0
            let sourceWidth = UInt32(sourceGlyph.width)
            let sourceHeight = UInt32(sourceGlyph.height)
            let expectedWidth = rotated ? sourceHeight : sourceWidth
            let expectedHeight = rotated ? sourceWidth : sourceHeight
            guard expectedWidth == glyph.width,
                  expectedHeight == glyph.height,
                  glyph.width > 0, glyph.height > 0,
                  glyph.width <= 16, glyph.height <= 16 else {
                throw GoldenEyeSource2DMetalRendererV6Error.invalidGlyph(glyph.fontID, glyph.glyphIndex)
            }
            let cellX = (Int(glyph.glyphIndex) % 16) * 16
            let cellY = (Int(glyph.glyphIndex) / 16) * 16
            try appendQuad(
                rect: .init(x: glyph.x, y: glyph.y, width: glyph.width, height: glyph.height),
                uv0: SIMD2(Float(cellX) / Float(atlasWidth), Float(cellY) / Float(atlasHeight)),
                uv1: SIMD2(
                    Float(cellX + Int(sourceWidth)) / Float(atlasWidth),
                    Float(cellY + Int(sourceHeight)) / Float(atlasHeight)
                ),
                color: rgba(glyph.rgba),
                primitive: .glyph,
                resourceID: glyph.fontID,
                scissor: glyph.scissor,
                sequence: glyph.sequence,
                rotate90Clockwise: glyph.flags & 2 != 0
            )
        }

        return GoldenEyeSource2DMetalBatchV6(
            vertices: vertices,
            draws: draws,
            sourceFrameHash: frame.frameHash,
            resourceHash: resourceHash(assets: assets),
            geometryHash: hash(vertices: vertices, draws: draws)
        )
    }

    private static func resourceHash(assets: GoldenEyeSource2DAssetsV6) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603
        func append(_ value: UInt64) { hash = (hash ^ value) &* 1_099_511_628_211 }
        func appendDigest(_ digest: String) {
            for byte in digest.utf8 { append(UInt64(byte)) }
        }
        append(UInt64(assets.textCatalogRecordID))
        for icon in assets.icons.values.sorted(by: { $0.sourceRecordID < $1.sourceRecordID }) {
            append(UInt64(icon.sourceRecordID)); append(UInt64(icon.width)); append(UInt64(icon.height)); appendDigest(icon.decodedSHA256)
        }
        append(UInt64(assets.fileModeBackground.sourceRecordID))
        append(UInt64(assets.fileModeBackground.width)); append(UInt64(assets.fileModeBackground.height))
        appendDigest(assets.fileModeBackground.decodedSHA256)
        for font in [assets.zurichBold, assets.bankGothic] {
            append(UInt64(font.id)); append(UInt64(font.sourceRecordID)); append(UInt64(font.kerningRecordID))
            appendDigest(font.sourceSHA256); appendDigest(font.payloadSHA256)
        }
        return hash == 0 ? 1 : hash
    }

    static func atlas(for font: GoldenEyeSourceFontV6) throws -> [UInt8] {
        guard font.glyphs.count == 94 else {
            throw GoldenEyeSource2DMetalRendererV6Error.missingFont(font.id)
        }
        var bytes = [UInt8](repeating: 0, count: atlasWidth * atlasHeight)
        for (index, glyph) in font.glyphs.enumerated() {
            let width = Int(glyph.width)
            let height = Int(glyph.height)
            let stride = max(width, Int(glyph.stride))
            guard width > 0, height > 0, width <= 16, height <= 16,
                  stride >= width, glyph.pixels.count >= stride * height else {
                throw GoldenEyeSource2DMetalRendererV6Error.invalidGlyph(font.id, UInt32(index))
            }
            let cellX = (index % 16) * 16
            let cellY = (index / 16) * 16
            for row in 0..<height {
                let sourceStart = row * stride
                let destinationStart = (cellY + row) * atlasWidth + cellX
                bytes[destinationStart..<(destinationStart + width)] = glyph.pixels[sourceStart..<(sourceStart + width)]
            }
        }
        return bytes
    }

    private static func rgba(_ value: UInt32) -> SIMD4<Float> {
        SIMD4(
            Float((value >> 24) & 0xff) / 255.0,
            Float((value >> 16) & 0xff) / 255.0,
            Float((value >> 8) & 0xff) / 255.0,
            Float(value & 0xff) / 255.0
        )
    }

    private static func metalScissor(
        source: GoldenEyeSource2DRectV6,
        layout: GoldenEyeFidelityLayout
    ) throws -> MTLScissorRect {
        let sourceRect = GoldenEyeFidelityLayout.Rect(
            minX: Double(source.x), minY: Double(source.y),
            maxX: Double(source.x) + Double(source.width),
            maxY: Double(source.y) + Double(source.height)
        )
        let output = layout.sourceToOutputRect(sourceRect)
        let minX = max(0, Int(floor(output.minX)))
        let minY = max(0, Int(floor(output.minY)))
        let maxX = min(Int(layout.outputWidth.rounded(.up)), Int(ceil(output.maxX)))
        let maxY = min(Int(layout.outputHeight.rounded(.up)), Int(ceil(output.maxY)))
        guard maxX > minX, maxY > minY else {
            throw GoldenEyeSource2DMetalRendererV6Error.invalidScissor
        }
        let outputHeight = Int(layout.outputHeight.rounded(.up))
        return MTLScissorRect(
            x: minX,
            y: max(0, outputHeight - maxY),
            width: maxX - minX,
            height: maxY - minY
        )
    }

    private static func intersect(
        _ lhs: GoldenEyeSource2DRectV6,
        _ rhs: GoldenEyeSource2DRectV6
    ) -> GoldenEyeSource2DRectV6 {
        let minX = max(lhs.x, rhs.x)
        let minY = max(lhs.y, rhs.y)
        let maxX = min(
            Int64(lhs.x) + Int64(lhs.width),
            Int64(rhs.x) + Int64(rhs.width)
        )
        let maxY = min(
            Int64(lhs.y) + Int64(lhs.height),
            Int64(rhs.y) + Int64(rhs.height)
        )
        guard maxX > Int64(minX), maxY > Int64(minY) else {
            return .init(x: minX, y: minY, width: 0, height: 0)
        }
        return .init(
            x: minX,
            y: minY,
            width: UInt32(min(UInt64(maxX - Int64(minX)), UInt64(UInt32.max))),
            height: UInt32(min(UInt64(maxY - Int64(minY)), UInt64(UInt32.max)))
        )
    }

    private static func hash(vertices: [GoldenEyeSource2DMetalVertexV6], draws: [GoldenEyeSource2DMetalDrawV6]) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603
        func append(_ value: UInt64) { hash = (hash ^ value) &* 1_099_511_628_211 }
        for vertex in vertices {
            for value in [
                UInt64(vertex.position.x.bitPattern), UInt64(vertex.position.y.bitPattern),
                UInt64(vertex.uv.x.bitPattern), UInt64(vertex.uv.y.bitPattern),
                UInt64(vertex.color.x.bitPattern), UInt64(vertex.color.y.bitPattern),
                UInt64(vertex.color.z.bitPattern), UInt64(vertex.color.w.bitPattern)
            ] { append(value) }
        }
        for draw in draws {
            append(UInt64(draw.primitive.rawValue)); append(UInt64(draw.resourceID)); append(UInt64(draw.vertexStart)); append(draw.sequence)
            append(UInt64(draw.scissor.x)); append(UInt64(draw.scissor.y)); append(UInt64(draw.scissor.width)); append(UInt64(draw.scissor.height))
        }
        return hash == 0 ? 1 : hash
    }
}

/// Direct Metal 4 renderer/compositor for source 2D frames.  ``encode`` is
/// the compositing seam: callers may open one render pass, draw the source 3D
/// scene, call this method, then close the same encoder and command buffer.
/// The standalone ``render`` helper exists for focused capture tests and also
/// consumes only a caller-supplied drawable.
@available(macOS 26.0, *)
final class GoldenEyeSource2DMetalRendererV6: @unchecked Sendable {
    private let state: GoldenEyeMetalDeviceState
    private let assets: GoldenEyeSource2DAssetsV6
    private let pipeline: GoldenEyeSource2DPipelineV6
    private let outputMode: GoldenEyeFidelityOutputMode
    private let maxVerticesPerFrame: Int
    private let vertexBuffers: [any MTLBuffer]
    private let uniformBuffers: [any MTLBuffer]
    private let iconTextures: [UInt32: any MTLTexture]
    private let fontTextures: [UInt32: any MTLTexture]
    private let uploadStaging: any MTLBuffer
    private let uploadEvent: any MTLSharedEvent
    private let frameEvent: any MTLSharedEvent
    private var nextFrameSignal: UInt64 = 1
    private var lastSignalBySlot: [UInt64]
    private var frameIndex: UInt64 = 0

    init(
        state: GoldenEyeMetalDeviceState,
        assets: GoldenEyeSource2DAssetsV6,
        libraryURL: URL,
        outputMode: GoldenEyeFidelityOutputMode = .faithfulHD,
        maxVerticesPerFrame: Int = 32_768
    ) throws {
        guard state.device.supportsFamily(.metal4), maxVerticesPerFrame > 0 else {
            throw GoldenEyeSource2DMetalRendererV6Error.metalAllocationFailed("Metal 4 or vertex capacity")
        }
        self.state = state
        self.assets = assets
        self.outputMode = outputMode
        self.maxVerticesPerFrame = maxVerticesPerFrame
        pipeline = try GoldenEyeSource2DPipelineV6(device: state.device, libraryURL: libraryURL)

        var vertexBuffers: [any MTLBuffer] = []
        var uniformBuffers: [any MTLBuffer] = []
        for slot in 0..<state.frameSlots.count {
            guard let vertices = state.device.makeBuffer(
                length: maxVerticesPerFrame * MemoryLayout<GoldenEyeSource2DMetalVertexV6>.stride,
                options: [.storageModeShared]
            ), let uniforms = state.device.makeBuffer(
                length: MemoryLayout<GoldenEyeSource2DMetalUniformsV6>.stride,
                options: [.storageModeShared]
            ) else {
                throw GoldenEyeSource2DMetalRendererV6Error.metalAllocationFailed("frame slot \(slot)")
            }
            vertices.label = "GoldenEye.V6.Source2D.FrameSlot.\(slot).Vertices"
            uniforms.label = "GoldenEye.V6.Source2D.FrameSlot.\(slot).Uniforms"
            vertexBuffers.append(vertices)
            uniformBuffers.append(uniforms)
        }
        self.vertexBuffers = vertexBuffers
        self.uniformBuffers = uniformBuffers
        self.lastSignalBySlot = Array(repeating: 0, count: state.frameSlots.count)

        var ranges: [GoldenEyeSource2DUploadRangeV6] = []
        var cursor = 0
        func appendRange(
            key: UInt32,
            bytes: [UInt8],
            bytesPerRow: Int,
            width: Int,
            height: Int,
            pixelFormat: MTLPixelFormat
        ) {
            cursor = (cursor + 255) & ~255
            ranges.append(.init(offset: cursor, bytesPerRow: bytesPerRow, width: width, height: height, bytes: bytes, pixelFormat: pixelFormat, key: key))
            cursor += bytes.count
        }

        var iconKeys = Set<UInt32>()
        for icon in assets.icons.values.sorted(by: { $0.sourceRecordID < $1.sourceRecordID }) {
            guard icon.width > 0, icon.height > 0,
                  icon.pixels.count == Int(icon.width * icon.height * 4) else {
                throw GoldenEyeSource2DMetalRendererV6Error.invalidDimensions
            }
            iconKeys.insert(icon.sourceRecordID)
            appendRange(
                key: icon.sourceRecordID, bytes: icon.pixels,
                bytesPerRow: Int(icon.width) * 4,
                width: Int(icon.width), height: Int(icon.height), pixelFormat: .rgba8Unorm
            )
        }
        let background = assets.fileModeBackground
        guard background.width == UInt32(GoldenEyeFileModeBackgroundContractV6.width),
              background.height == UInt32(GoldenEyeFileModeBackgroundContractV6.height),
              background.pixels.count == Int(background.width * background.height * 4) else {
            throw GoldenEyeSource2DMetalRendererV6Error.invalidDimensions
        }
        iconKeys.insert(background.sourceRecordID)
        appendRange(
            key: background.sourceRecordID,
            bytes: background.pixels,
            bytesPerRow: Int(background.width) * 4,
            width: Int(background.width),
            height: Int(background.height),
            pixelFormat: .rgba8Unorm
        )
        let zurichAtlas = try GoldenEyeSource2DMetalBatchBuilderV6.atlas(for: assets.zurichBold)
        let bankAtlas = try GoldenEyeSource2DMetalBatchBuilderV6.atlas(for: assets.bankGothic)
        appendRange(
            key: GoldenEyeSource2DMetalBatchBuilderV6.fontUploadKey(GoldenEyeSource2DFontIDV6.zurichBold.rawValue),
            bytes: zurichAtlas, bytesPerRow: GoldenEyeSource2DMetalBatchBuilderV6.atlasWidth,
            width: GoldenEyeSource2DMetalBatchBuilderV6.atlasWidth,
            height: GoldenEyeSource2DMetalBatchBuilderV6.atlasHeight, pixelFormat: .r8Unorm
        )
        appendRange(
            key: GoldenEyeSource2DMetalBatchBuilderV6.fontUploadKey(GoldenEyeSource2DFontIDV6.bankGothic.rawValue),
            bytes: bankAtlas, bytesPerRow: GoldenEyeSource2DMetalBatchBuilderV6.atlasWidth,
            width: GoldenEyeSource2DMetalBatchBuilderV6.atlasWidth,
            height: GoldenEyeSource2DMetalBatchBuilderV6.atlasHeight, pixelFormat: .r8Unorm
        )
        guard cursor > 0, cursor <= state.device.maxBufferLength,
              let staging = state.device.makeBuffer(
                length: cursor,
                options: [.storageModeShared, .cpuCacheModeWriteCombined]
              ) else {
            throw GoldenEyeSource2DMetalRendererV6Error.metalAllocationFailed("staging")
        }
        staging.label = "GoldenEye.V6.Source2D.Upload.Staging"
        self.uploadStaging = staging

        var texturesByKey: [UInt32: any MTLTexture] = [:]
        for range in ranges {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: range.pixelFormat,
                width: range.width,
                height: range.height,
                mipmapped: false
            )
            descriptor.storageMode = .private
            descriptor.usage = .shaderRead
            guard let texture = state.device.makeTexture(descriptor: descriptor) else {
                throw GoldenEyeSource2DMetalRendererV6Error.metalAllocationFailed("texture \(range.key)")
            }
            texture.label = range.pixelFormat == .r8Unorm
                ? "GoldenEye.V6.Source2D.Font.\(range.key).Atlas"
                : "GoldenEye.V6.Source2D.Icon.\(range.key)"
            texturesByKey[range.key] = texture
            range.bytes.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                staging.contents().advanced(by: range.offset).copyMemory(from: base, byteCount: bytes.count)
            }
        }
        iconTextures = texturesByKey.filter { iconKeys.contains($0.key) }
        fontTextures = Dictionary(uniqueKeysWithValues: texturesByKey.compactMap { key, value in
            iconKeys.contains(key) ? nil : (key & 0x0FFF_FFFF, value)
        })

        guard let uploadEvent = state.device.makeSharedEvent() else {
            throw GoldenEyeSource2DMetalRendererV6Error.uploadFailed("completion event")
        }
        uploadEvent.label = "GoldenEye.V6.Source2D.Upload.Completion"
        self.uploadEvent = uploadEvent
        guard let frameEvent = state.device.makeSharedEvent() else {
            throw GoldenEyeSource2DMetalRendererV6Error.uploadFailed("frame completion event")
        }
        frameEvent.label = "GoldenEye.V6.Source2D.Frame.Completion"
        self.frameEvent = frameEvent

        for buffer in vertexBuffers + uniformBuffers { state.sceneResidency.addAllocation(buffer) }
        for texture in texturesByKey.values { state.sceneResidency.addAllocation(texture) }
        state.sceneResidency.addAllocation(staging)
        state.sceneResidency.commit()

        let allocatorDescriptor = MTL4CommandAllocatorDescriptor()
        allocatorDescriptor.label = "GoldenEye.V6.Source2D.Upload.Allocator"
        guard let allocator = try? state.device.makeCommandAllocator(descriptor: allocatorDescriptor),
              let commandBuffer = state.device.makeCommandBuffer() else {
            throw GoldenEyeSource2DMetalRendererV6Error.uploadFailed("command buffer/allocator")
        }
        commandBuffer.label = "GoldenEye.V6.Source2D.Upload.CommandBuffer"
        commandBuffer.beginCommandBuffer(allocator: allocator)
        commandBuffer.useResidencySet(state.sceneResidency)
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            commandBuffer.endCommandBuffer()
            throw GoldenEyeSource2DMetalRendererV6Error.uploadFailed("compute encoder")
        }
        encoder.label = "GoldenEye.V6.Source2D.Upload.Copy"
        for range in ranges {
            guard let texture = texturesByKey[range.key] else {
                encoder.endEncoding(); commandBuffer.endCommandBuffer()
                throw GoldenEyeSource2DMetalRendererV6Error.uploadFailed("texture map")
            }
            encoder.copy(
                sourceBuffer: staging,
                sourceOffset: range.offset,
                sourceBytesPerRow: range.bytesPerRow,
                sourceBytesPerImage: 0,
                sourceSize: MTLSize(width: range.width, height: range.height, depth: 1),
                destinationTexture: texture,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
            )
        }
        encoder.barrier(afterStages: .blit, beforeQueueStages: .fragment, visibilityOptions: .device)
        encoder.endEncoding()
        commandBuffer.endCommandBuffer()
        state.queue.commit([commandBuffer])
        state.queue.signalEvent(uploadEvent, value: 1)
        guard uploadEvent.wait(untilSignaledValue: 1, timeoutMS: 2_000) else {
            throw GoldenEyeSource2DMetalRendererV6Error.uploadFailed("completion timeout")
        }
    }

    /// Builds the same deterministic batch used by ``encode``.  This is
    /// useful to the source evidence harness and has no Metal side effects.
    func batch(
        frame: GoldenEyeSource2DFrameV6,
        outputWidth: Int,
        outputHeight: Int
    ) throws -> GoldenEyeSource2DMetalBatchV6 {
        try GoldenEyeSource2DMetalBatchBuilderV6.build(
            frame: frame,
            assets: assets,
            outputWidth: outputWidth,
            outputHeight: outputHeight,
            mode: outputMode
        )
    }

    /// Encode 2D after an existing 3D scene in the same MTL4 render encoder.
    /// The caller owns the command-buffer begin/end and render-pass lifetime.
    @discardableResult
    func encode(
        frame: GoldenEyeSource2DFrameV6,
        into encoder: any MTL4RenderCommandEncoder,
        drawableWidth: Int,
        drawableHeight: Int,
        slotIndex: Int,
        includeFills: Bool = true,
        skipInitialSourceClear: Bool = false
    ) throws -> GoldenEyeSource2DMetalBatchV6 {
        guard state.frameSlots.indices.contains(slotIndex) else {
            throw GoldenEyeSource2DMetalRendererV6Error.slotTimeout(slotIndex)
        }
        let batch = try batch(frame: frame, outputWidth: drawableWidth, outputHeight: drawableHeight)
        guard batch.vertices.count <= maxVerticesPerFrame else {
            throw GoldenEyeSource2DMetalRendererV6Error.capacityExceeded(batch.vertices.count)
        }
        let vertexBuffer = vertexBuffers[slotIndex]
        batch.vertices.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            vertexBuffer.contents().copyMemory(from: base, byteCount: bytes.count)
        }
        let layout = GoldenEyeFidelityLayout(
            mode: outputMode,
            drawableWidth: Double(drawableWidth),
            drawableHeight: Double(drawableHeight)
        )
        var uniforms = GoldenEyeSource2DMetalUniformsV6(
            outputSize: SIMD2(Float(layout.outputWidth), Float(layout.outputHeight)),
            // Adaptive widescreen keeps the 440-unit source core centered in
            // the expanded viewport.  Faithful HD/reference have no side
            // gutter, so this is exactly their existing origin.
            origin: SIMD2(
                Float(layout.originX + layout.sideGutter * layout.scale),
                Float(layout.originY)
            ),
            scale: Float(layout.scale),
            logicalWidth: Float(GoldenEyeSource2DLowererV6.logicalWidth),
            logicalHeight: Float(GoldenEyeSource2DLowererV6.logicalHeight)
        )
        withUnsafeBytes(of: &uniforms) { bytes in
            guard let base = bytes.baseAddress else { return }
            uniformBuffers[slotIndex].contents().copyMemory(from: base, byteCount: bytes.count)
        }
        // Source-scene rendering may have left a 4:3/expanded 3D viewport on
        // the encoder.  The 2D packet maps its own logical coordinates to the
        // complete output target, so restore the full target viewport before
        // compositing and leave it as the final encoder state.
        encoder.setViewport(MTLViewport(
            originX: 0,
            originY: 0,
            width: Double(drawableWidth),
            height: Double(drawableHeight),
            znear: 0,
            zfar: 1
        ))
        state.argumentTable.setAddress(vertexBuffer.gpuAddress, index: 0)
        state.argumentTable.setAddress(uniformBuffers[slotIndex].gpuAddress, index: 1)
        encoder.setArgumentTable(state.argumentTable, stages: [.vertex, .fragment])
        encoder.setDepthStencilState(pipeline.depthStencilState)
        encoder.setCullMode(.none)
        encoder.pushDebugGroup("GoldenEye.V6.Source2D.Frame.Tick.\(frame.nativeTick).Hash.\(String(batch.geometryHash, radix: 16))")

        var skippedInitialSourceClear = false
        for draw in batch.draws {
            if draw.primitive == .fill {
                if !includeFills { continue }
                // The source 3D renderer already owns the render-pass clear.
                // In an overlay pass suppress only the authored first black
                // fill; later source fills remain visible (fades, selection
                // bars, and other 2D state) in their original sequence.
                if skipInitialSourceClear, !skippedInitialSourceClear {
                    skippedInitialSourceClear = true
                    continue
                }
            }
            switch draw.primitive {
            case .fill:
                encoder.setRenderPipelineState(pipeline.fill)
            case .texture:
                guard let texture = iconTextures[draw.resourceID] else {
                    encoder.popDebugGroup()
                    throw GoldenEyeSource2DMetalRendererV6Error.missingResource(draw.resourceID)
                }
                state.argumentTable.setTexture(texture.gpuResourceID, index: 0)
                state.argumentTable.setSamplerState(pipeline.sampler.gpuResourceID, index: 0)
                encoder.setArgumentTable(state.argumentTable, stages: [.vertex, .fragment])
                encoder.setRenderPipelineState(pipeline.texture)
            case .glyph:
                guard let texture = fontTextures[draw.resourceID] else {
                    encoder.popDebugGroup()
                    throw GoldenEyeSource2DMetalRendererV6Error.missingFont(draw.resourceID)
                }
                state.argumentTable.setTexture(texture.gpuResourceID, index: 0)
                state.argumentTable.setSamplerState(pipeline.sampler.gpuResourceID, index: 0)
                encoder.setArgumentTable(state.argumentTable, stages: [.vertex, .fragment])
                encoder.setRenderPipelineState(pipeline.glyph)
            }
            encoder.setScissorRect(draw.scissor)
            encoder.pushDebugGroup("GoldenEye.V6.Source2D.Draw.\(draw.primitive.rawValue).Resource.\(draw.resourceID).Sequence.\(draw.sequence)")
            encoder.drawPrimitives(
                primitiveType: .triangle,
                vertexStart: draw.vertexStart,
                vertexCount: 6
            )
            encoder.popDebugGroup()
        }
        encoder.popDebugGroup()
        _ = uniforms
        return batch
    }

    /// Overlay-only convenience for a source render pass that already drew
    /// its clear/background and 3D scene.  It preserves source ordering of
    /// authored fills, texture rectangles, and glyphs while suppressing only
    /// the frame's initial source clear packet.
    @discardableResult
    func encodeOverlay(
        frame: GoldenEyeSource2DFrameV6,
        into encoder: any MTL4RenderCommandEncoder,
        drawableWidth: Int,
        drawableHeight: Int,
        slotIndex: Int
    ) throws -> GoldenEyeSource2DMetalBatchV6 {
        try encode(
            frame: frame,
            into: encoder,
            drawableWidth: drawableWidth,
            drawableHeight: drawableHeight,
            slotIndex: slotIndex,
            includeFills: true,
            skipInitialSourceClear: true
        )
    }

    /// Standalone display-link-compatible helper used by the 2D capture
    /// harness.  It uses the callback-owned drawable and never acquires one.
    @discardableResult
    func render(
        frame: GoldenEyeSource2DFrameV6,
        suppliedDrawable drawable: any CAMetalDrawable
    ) throws -> GoldenEyeSource2DMetalBatchV6 {
        let slotIndex = Int(frameIndex % UInt64(state.frameSlots.count))
        let prior = lastSignalBySlot[slotIndex]
        if prior != 0,
           !frameEvent.wait(untilSignaledValue: prior, timeoutMS: 1_000) {
            throw GoldenEyeSource2DMetalRendererV6Error.slotTimeout(slotIndex)
        }
        let slot = state.frameSlots[slotIndex]
        slot.allocator.reset()
        slot.commandBuffer.beginCommandBuffer(allocator: slot.allocator)
        slot.commandBuffer.useResidencySet(state.sceneResidency)
        slot.commandBuffer.useResidencySet(state.layerResidency)
        let pass = MTL4RenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let encoder = slot.commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            slot.commandBuffer.endCommandBuffer()
            throw GoldenEyeSource2DMetalRendererV6Error.encoderUnavailable
        }
        let batch = try encode(
            frame: frame,
            into: encoder,
            drawableWidth: drawable.texture.width,
            drawableHeight: drawable.texture.height,
            slotIndex: slotIndex,
            includeFills: true
        )
        encoder.endEncoding()
        slot.commandBuffer.endCommandBuffer()
        state.queue.waitForDrawable(drawable)
        state.queue.commit([slot.commandBuffer])
        let signal = nextFrameSignal
        nextFrameSignal &+= 1
        state.queue.signalEvent(frameEvent, value: signal)
        state.queue.signalDrawable(drawable)
        drawable.present()
        lastSignalBySlot[slotIndex] = signal
        frameIndex &+= 1
        return batch
    }

    func shutdown() {
        for signal in lastSignalBySlot where signal != 0 {
            _ = frameEvent.wait(untilSignaledValue: signal, timeoutMS: 2_000)
        }
        for buffer in vertexBuffers + uniformBuffers { state.sceneResidency.removeAllocation(buffer) }
        for texture in iconTextures.values { state.sceneResidency.removeAllocation(texture) }
        for texture in fontTextures.values { state.sceneResidency.removeAllocation(texture) }
        state.sceneResidency.removeAllocation(uploadStaging)
        state.sceneResidency.commit()
    }
}
