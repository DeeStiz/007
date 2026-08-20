import Metal

/// Errors from the source 2D Metal 4 pipeline.  There is intentionally no
/// fallback pipeline: a missing function or unsupported pixel format must
/// keep the frame out of the faithful renderer.
@available(macOS 26.0, *)
enum GoldenEyeSource2DPipelineV6Error: Error, Sendable, CustomStringConvertible {
    case missingLibrary(URL)
    case compilerUnavailable
    case pipelineUnavailable(String)
    case samplerUnavailable

    var description: String {
        switch self {
        case .missingLibrary(let url):
            return "source 2D V6 metallib is missing: \(url.path)"
        case .compilerUnavailable:
            return "source 2D V6 MTL4Compiler is unavailable"
        case .pipelineUnavailable(let name):
            return "source 2D V6 pipeline is unavailable: \(name)"
        case .samplerUnavailable:
            return "source 2D V6 sampler is unavailable"
        }
    }
}

/// Fixed Metal 4 PSOs for the source 2D packet.  All three pipelines consume
/// the same value-only vertex record.  Fills, texture rectangles, and source
/// glyphs are separate PSOs so the renderer never infers a texture or font
/// from a missing resource.
@available(macOS 26.0, *)
final class GoldenEyeSource2DPipelineV6: @unchecked Sendable {
    let fill: any MTLRenderPipelineState
    let texture: any MTLRenderPipelineState
    let glyph: any MTLRenderPipelineState
    let sampler: any MTLSamplerState
    let depthStencilState: any MTLDepthStencilState

    private let device: any MTLDevice

    init(
        device: any MTLDevice,
        libraryURL: URL,
        pixelFormat: MTLPixelFormat = .bgra8Unorm
    ) throws {
        guard FileManager.default.fileExists(atPath: libraryURL.path) else {
            throw GoldenEyeSource2DPipelineV6Error.missingLibrary(libraryURL)
        }
        guard let library = try? device.makeLibrary(URL: libraryURL) else {
            throw GoldenEyeSource2DPipelineV6Error.missingLibrary(libraryURL)
        }
        let compilerDescriptor = MTL4CompilerDescriptor()
        guard let compiler = try? device.makeCompiler(descriptor: compilerDescriptor) else {
            throw GoldenEyeSource2DPipelineV6Error.compilerUnavailable
        }

        func function(_ name: String) -> MTL4LibraryFunctionDescriptor {
            let descriptor = MTL4LibraryFunctionDescriptor()
            descriptor.library = library
            descriptor.name = name
            return descriptor
        }

        func makePipeline(
            label: String,
            vertex: String,
            fragment: String,
            blending: Bool
        ) throws -> any MTLRenderPipelineState {
            let descriptor = MTL4RenderPipelineDescriptor()
            descriptor.label = label
            descriptor.vertexFunctionDescriptor = function(vertex)
            descriptor.fragmentFunctionDescriptor = function(fragment)
            descriptor.colorAttachments[0].pixelFormat = pixelFormat
            descriptor.inputPrimitiveTopology = .triangle
            if blending {
                descriptor.colorAttachments[0].blendingState = .enabled
                descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
                descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                descriptor.colorAttachments[0].rgbBlendOperation = .add
                // Source 2D fragments carry straight-alpha intensity. Keep
                // the opaque reference target's alpha at one while blending
                // RGB by source alpha; using sourceAlpha for the alpha
                // channel would produce partially transparent readback
                // pixels and make lossless PNG evidence impossible.
                descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
                descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
                descriptor.colorAttachments[0].alphaBlendOperation = .add
            } else {
                descriptor.colorAttachments[0].blendingState = .disabled
            }
            guard let pipeline = try? compiler.makeRenderPipelineState(descriptor: descriptor) else {
                throw GoldenEyeSource2DPipelineV6Error.pipelineUnavailable(label)
            }
            return pipeline
        }

        self.device = device
        fill = try makePipeline(
            label: "GoldenEye.V6.Source2D.Fill",
            vertex: "goldeneye_source_2d_v6_fill_vertex",
            fragment: "goldeneye_source_2d_v6_fill_fragment",
            blending: true
        )
        texture = try makePipeline(
            label: "GoldenEye.V6.Source2D.Texture",
            vertex: "goldeneye_source_2d_v6_texture_vertex",
            fragment: "goldeneye_source_2d_v6_texture_fragment",
            blending: true
        )
        glyph = try makePipeline(
            label: "GoldenEye.V6.Source2D.Glyph",
            vertex: "goldeneye_source_2d_v6_glyph_vertex",
            fragment: "goldeneye_source_2d_v6_glyph_fragment",
            blending: true
        )

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .nearest
        samplerDescriptor.magFilter = .nearest
        samplerDescriptor.mipFilter = .notMipmapped
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerDescriptor.label = "GoldenEye.V6.Source2D.SourceSampler"
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            throw GoldenEyeSource2DPipelineV6Error.samplerUnavailable
        }
        self.sampler = sampler
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .always
        depthDescriptor.isDepthWriteEnabled = false
        guard let depthStencilState = device.makeDepthStencilState(descriptor: depthDescriptor) else {
            throw GoldenEyeSource2DPipelineV6Error.pipelineUnavailable("2D depth state")
        }
        self.depthStencilState = depthStencilState
    }

    convenience init(device: any MTLDevice, bundle: Bundle = .main) throws {
        guard let libraryURL = bundle.url(
            forResource: "GoldenEyeSource2DV6",
            withExtension: "metallib"
        ) else {
            throw GoldenEyeSource2DPipelineV6Error.missingLibrary(
                bundle.bundleURL.appendingPathComponent("GoldenEyeSource2DV6.metallib")
            )
        }
        try self.init(device: device, libraryURL: libraryURL)
    }
}
