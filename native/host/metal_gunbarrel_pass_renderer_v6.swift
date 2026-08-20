#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif
import Foundation
import Metal

enum GoldenEyeGunbarrelPassRendererV6Error: Error, CustomStringConvertible {
    case sourceBuild(String)

    var description: String {
        switch self {
        case .sourceBuild(let detail):
            return "Gunbarrel Metal pass setup failed: \(detail)"
        }
    }
}

/// Direct Metal 4 compositor for the source-owned Gunbarrel non-model work.
/// It is intentionally separate from the triangle scene material cache: the
/// source title path renders its I8 rows, generated 30-vertex sight mask, I4
/// blood rectangle, and fade rectangles around the model display lists.
@available(macOS 26.0, *)
final class GoldenEyeGunbarrelPassRendererV6: @unchecked Sendable {
    private struct Vertex {
        var position: SIMD2<Float>
        var uv: SIMD2<Float>
        var color: SIMD4<Float>
    }

    private struct Uniforms {
        var kind: UInt32
        var mode: UInt32
        var titleXQ16: Int32
        var fadeAlphaQ8: UInt32
        var bloodFrame: UInt32
        var reserved0: UInt32
        var reserved1: SIMD4<Float>
    }

    private enum Kind: UInt32 {
        case background = 0
        case hole = 1
        case blood = 2
        case fade = 3
    }

    private let state: GoldenEyeMetalDeviceState
    private let pipeline: any MTLRenderPipelineState
    private let depthState: any MTLDepthStencilState
    private let sampler: any MTLSamplerState
    private let background: any MTLTexture
    private let blood: any MTLTexture
    private let backgroundVertices: any MTLBuffer
    private let holeVertices: any MTLBuffer
    private let fullscreenVertices: any MTLBuffer
    private let uniformBuffers: [any MTLBuffer]

    init(
        state: GoldenEyeMetalDeviceState,
        sourcePipeline: GoldenEyeSourceScenePipelineV6,
        backgroundData: Data,
        bloodData: Data
    ) throws {
        guard MemoryLayout<Uniforms>.stride == 48 else {
            throw GoldenEyeGunbarrelPassRendererV6Error.sourceBuild("Gunbarrel pass uniform layout")
        }
        self.state = state
        let backgroundPixels = try Self.decodeBackground(backgroundData)
        let bloodFrame = try GoldenEyeGunbarrelBloodDecoderV6.decodeInitial(bloodData)

        let backgroundDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: backgroundPixels.width,
            height: backgroundPixels.height,
            mipmapped: false
        )
        backgroundDescriptor.storageMode = .shared
        backgroundDescriptor.usage = [.shaderRead]
        guard let background = state.device.makeTexture(descriptor: backgroundDescriptor) else {
            throw GoldenEyeGunbarrelPassRendererV6Error.sourceBuild("Gunbarrel background texture allocation")
        }
        background.label = "GoldenEye.V6.Gunbarrel.Background.I8.440x299"
        background.replace(
            region: MTLRegionMake2D(0, 0, backgroundPixels.width, backgroundPixels.height),
            mipmapLevel: 0,
            withBytes: backgroundPixels.pixels,
            bytesPerRow: backgroundPixels.width
        )

        let bloodDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: Int(bloodFrame.width),
            height: Int(bloodFrame.height),
            mipmapped: false
        )
        bloodDescriptor.storageMode = .shared
        bloodDescriptor.usage = [.shaderRead]
        guard let blood = state.device.makeTexture(descriptor: bloodDescriptor) else {
            throw GoldenEyeGunbarrelPassRendererV6Error.sourceBuild("Gunbarrel blood texture allocation")
        }
        blood.label = "GoldenEye.V6.Gunbarrel.Blood.I4.96x80"
        blood.replace(
            region: MTLRegionMake2D(0, 0, Int(bloodFrame.width), Int(bloodFrame.height)),
            mipmapLevel: 0,
            withBytes: bloodFrame.pixels,
            bytesPerRow: Int(bloodFrame.width)
        )

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .notMipmapped
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let sampler = state.device.makeSamplerState(descriptor: samplerDescriptor) else {
            throw GoldenEyeGunbarrelPassRendererV6Error.sourceBuild("Gunbarrel pass sampler allocation")
        }

        let pipeline = try sourcePipeline.auxiliaryPipeline(
            vertexFunctionName: "goldeneye_gunbarrel_pass_vertex",
            fragmentFunctionName: "goldeneye_gunbarrel_pass_fragment",
            label: "GoldenEye.V6.Gunbarrel.Pass.PSO",
            blending: true
        )
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .always
        depthDescriptor.isDepthWriteEnabled = false
        guard let depthState = state.device.makeDepthStencilState(descriptor: depthDescriptor) else {
            throw GoldenEyeGunbarrelPassRendererV6Error.sourceBuild("Gunbarrel pass depth state")
        }

        let backgroundVertices = try Self.makeBuffer(
            device: state.device,
            label: "GoldenEye.V6.Gunbarrel.Background.Vertices",
            values: Self.backgroundQuad()
        )
        let fullscreenVertices = try Self.makeBuffer(
            device: state.device,
            label: "GoldenEye.V6.Gunbarrel.Fullscreen.Vertices",
            values: Self.fullscreenQuad()
        )
        let holeVertices = try Self.makeBuffer(
            device: state.device,
            label: "GoldenEye.V6.Gunbarrel.Hole.Vertices.30x28",
            values: Self.holeTriangleVertices()
        )
        var uniformBuffers: [any MTLBuffer] = []
        for index in 0..<state.frameSlots.count {
            guard let buffer = state.device.makeBuffer(
                length: max(256, MemoryLayout<Uniforms>.stride),
                options: .storageModeShared
            ) else {
                throw GoldenEyeGunbarrelPassRendererV6Error.sourceBuild("Gunbarrel pass uniforms slot \(index)")
            }
            buffer.label = "GoldenEye.V6.Gunbarrel.Pass.Uniforms.\(index)"
            uniformBuffers.append(buffer)
        }

        self.background = background
        self.blood = blood
        self.sampler = sampler
        self.pipeline = pipeline
        self.depthState = depthState
        self.backgroundVertices = backgroundVertices
        self.holeVertices = holeVertices
        self.fullscreenVertices = fullscreenVertices
        self.uniformBuffers = uniformBuffers

        for resource in [background, blood, backgroundVertices, holeVertices, fullscreenVertices] {
            state.sceneResidency.addAllocation(resource)
        }
        for buffer in uniformBuffers {
            state.sceneResidency.addAllocation(buffer)
        }
        state.sceneResidency.commit()
    }

    func encodeUnderlay(
        pass: GoldenEyeGunbarrelRenderPassV6,
        encoder: any MTL4RenderCommandEncoder,
        slotIndex: Int
    ) throws {
        guard pass.mode >= 2, pass.mode <= 7 else { return }
        if pass.backgroundVisible {
            try encode(kind: .background, pass: pass, encoder: encoder, slotIndex: slotIndex)
        }
        guard pass.holeVisible, pass.holeTriangleCount > 0 else { return }
        // title.c's mode-2 sweep submits the generated sight geometry twice:
        // the leading ring follows g_TitleX and the trailing ring follows
        // titleTransitionX.  Later modes keep one enlarged ring centered on
        // the moving backdrop.
        try encode(
            kind: .hole,
            pass: pass,
            holeXQ16: pass.titleXQ16,
            encoder: encoder,
            slotIndex: slotIndex
        )
        if pass.holePassCount > 1 {
            try encode(
                kind: .hole,
                pass: pass,
                holeXQ16: pass.transitionXQ16,
                encoder: encoder,
                slotIndex: slotIndex
            )
        }
    }

    func encodeOverlay(
        pass: GoldenEyeGunbarrelRenderPassV6,
        encoder: any MTL4RenderCommandEncoder,
        slotIndex: Int
    ) throws {
        if pass.bloodVisible, pass.bloodPayloadAvailable {
            try encode(kind: .blood, pass: pass, encoder: encoder, slotIndex: slotIndex)
        }
        switch pass.fade {
        case .none:
            break
        case .red, .black, .clearBlack:
            try encode(kind: .fade, pass: pass, encoder: encoder, slotIndex: slotIndex)
        }
    }

    private func encode(
        kind: Kind,
        pass: GoldenEyeGunbarrelRenderPassV6,
        holeXQ16: Int32? = nil,
        encoder: any MTL4RenderCommandEncoder,
        slotIndex: Int
    ) throws {
        let safeSlot = min(max(slotIndex, 0), uniformBuffers.count - 1)
        var uniforms = Uniforms(
            kind: kind.rawValue,
            mode: pass.mode,
            // For hole draws this field is the selected ring center.  The
            // background/fade/blood passes retain the source title position.
            titleXQ16: holeXQ16 ?? pass.titleXQ16,
            fadeAlphaQ8: pass.fadeAlphaQ8,
            bloodFrame: pass.bloodFrameIndex,
            reserved0: 0,
            reserved1: SIMD4<Float>(repeating: 0)
        )
        let uniform = uniformBuffers[safeSlot]
        withUnsafeBytes(of: &uniforms) { bytes in
            if let baseAddress = bytes.baseAddress {
                uniform.contents().copyMemory(from: baseAddress, byteCount: bytes.count)
            }
        }
        let vertices: any MTLBuffer
        let count: Int
        switch kind {
        case .background:
            vertices = backgroundVertices
            count = 6
        case .hole:
            vertices = holeVertices
            count = 28 * 3
        case .blood, .fade:
            vertices = fullscreenVertices
            count = 6
        }
        state.argumentTable.setAddress(vertices.gpuAddress, index: 0)
        state.argumentTable.setAddress(uniform.gpuAddress, index: 1)
        let texture = kind == .blood ? blood : background
        state.argumentTable.setTexture(texture.gpuResourceID, index: 0)
        state.argumentTable.setSamplerState(sampler.gpuResourceID, index: 0)
        encoder.setRenderPipelineState(pipeline)
        encoder.setArgumentTable(state.argumentTable, stages: [.vertex, .fragment])
        encoder.setDepthStencilState(depthState)
        encoder.setCullMode(.none)
        let centerSuffix = holeXQ16.map { ".Center.\($0)" } ?? ""
        encoder.pushDebugGroup("GoldenEye.V6.Gunbarrel.Pass.\(kind.rawValue).Mode.\(pass.mode)\(centerSuffix)")
        encoder.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: count)
        encoder.popDebugGroup()
    }

    private static func makeBuffer<T>(
        device: any MTLDevice,
        label: String,
        values: [T]
    ) throws -> any MTLBuffer {
        let byteCount = values.count * MemoryLayout<T>.stride
        let buffer: (any MTLBuffer)? = values.withUnsafeBytes { rawBytes in
            guard let baseAddress = rawBytes.baseAddress else { return nil }
            return device.makeBuffer(
                bytes: baseAddress,
                length: byteCount,
                options: .storageModeShared
            )
        }
        guard let buffer else {
            throw GoldenEyeGunbarrelPassRendererV6Error.sourceBuild("Gunbarrel pass buffer \(label)")
        }
        buffer.label = label
        return buffer
    }

    private static func backgroundQuad() -> [Vertex] {
        let color = SIMD4<Float>(repeating: 1)
        return [
            Vertex(position: SIMD2(0, 16), uv: SIMD2(0, 0), color: color),
            Vertex(position: SIMD2(440, 16), uv: SIMD2(1, 0), color: color),
            Vertex(position: SIMD2(0, 315), uv: SIMD2(0, 1), color: color),
            Vertex(position: SIMD2(440, 16), uv: SIMD2(1, 0), color: color),
            Vertex(position: SIMD2(440, 315), uv: SIMD2(1, 1), color: color),
            Vertex(position: SIMD2(0, 315), uv: SIMD2(0, 1), color: color),
        ]
    }

    private static func fullscreenQuad() -> [Vertex] {
        let color = SIMD4<Float>(repeating: 1)
        return [
            Vertex(position: SIMD2(0, 0), uv: SIMD2(0, 0), color: color),
            Vertex(position: SIMD2(440, 0), uv: SIMD2(1, 0), color: color),
            Vertex(position: SIMD2(0, 330), uv: SIMD2(0, 1), color: color),
            Vertex(position: SIMD2(440, 0), uv: SIMD2(1, 0), color: color),
            Vertex(position: SIMD2(440, 330), uv: SIMD2(1, 1), color: color),
            Vertex(position: SIMD2(0, 330), uv: SIMD2(0, 1), color: color),
        ]
    }

    private static func holeTriangleVertices() -> [Vertex] {
        var source: [Vertex] = []
        source.reserveCapacity(30)
        let pi = Float.pi
        for step in stride(from: 0, through: 30, by: 2) {
            let angle = Float(step) * pi / 30
            let sinValue = sin(angle) * 64
            let cosValue = cos(angle) * -64
            // The source computes 143 - cos(angle) * -111.  `cosValue` is
            // already scaled to the 64-unit radius and must not be reused in
            // the colour expression (that would clamp nearly every vertex to
            // black or white instead of producing the authored gradient).
            let brightness = (143 - cos(angle) * -111) / 255
            let color = SIMD4<Float>(repeating: max(0, min(1, brightness)))
            source.append(Vertex(position: SIMD2(sinValue, cosValue), uv: .zero, color: color))
            if step != 0 && step < 30 {
                // title3.c stores the paired vertex as (-sinval, cosval),
                // not (-sinval, -cosval).  Keeping the second coordinate
                // unchanged is what makes the two 14-vertex triangle strips
                // form the source circular hole.
                source.append(Vertex(position: SIMD2(-sinValue, cosValue), uv: .zero, color: color))
            }
        }
        var output: [Vertex] = []
        output.reserveCapacity(28 * 3)
        func appendReversed(_ base: Int) {
            for index in stride(from: 13, through: 0, by: -1) {
                output.append(source[base + index])
                output.append(source[base + index + 1])
                output.append(source[base + index + 2])
            }
        }
        appendReversed(0)
        appendReversed(14)
        return output
    }

    private static func decodeBackground(_ data: Data) throws -> (width: Int, height: Int, pixels: [UInt8]) {
        guard data.count >= 10 else {
            throw GoldenEyeGunbarrelPassRendererV6Error.sourceBuild("Gunbarrel background header truncated")
        }
        let width = Int(UInt16(data[0]) << 8 | UInt16(data[1]))
        let height = Int(UInt16(data[2]) << 8 | UInt16(data[3]))
        guard width == 440, height == 299 else {
            throw GoldenEyeGunbarrelPassRendererV6Error.sourceBuild("Gunbarrel background dimensions \(width)x\(height)")
        }
        var cursor = 10
        var pixels: [UInt8] = []
        pixels.reserveCapacity(width * height)
        while pixels.count < width * height {
            guard cursor + 1 < data.count else {
                throw GoldenEyeGunbarrelPassRendererV6Error.sourceBuild("Gunbarrel background RLE truncation")
            }
            let run = Int(data[cursor])
            let value = data[cursor + 1]
            cursor += 2
            guard run > 0, pixels.count + run <= width * height else {
                throw GoldenEyeGunbarrelPassRendererV6Error.sourceBuild("Gunbarrel background RLE run")
            }
            pixels.append(contentsOf: repeatElement(value, count: run))
        }
        return (width, height, pixels)
    }
}
