import Metal

/// Pipeline for the standalone M27 diagnostic stage overlay.  This is kept
/// separate from the title pipeline so stage packet binding can be validated
/// without changing GETP/GETT or the branded frontend renderer.
@available(macOS 26.0, *)
enum GoldenEyeStageBackgroundPipelineError: Error, CustomStringConvertible {
    case missingLibrary(URL)
    case compilerUnavailable
    case creationFailed(String)

    var description: String {
        switch self {
        case .missingLibrary(let url):
            return "missing GoldenEye stage background metallib at \(url.path)"
        case .compilerUnavailable:
            return "Metal 4 compiler is unavailable for the stage background renderer"
        case .creationFailed(let component):
            return "GoldenEye stage background pipeline creation failed for \(component)"
        }
    }
}

@available(macOS 26.0, *)
final class GoldenEyeStageBackgroundPipeline {
    let pipeline: any MTLRenderPipelineState
    let label = "GoldenEye.M27.StageBackground.Pipeline"

    init(device: any MTLDevice, libraryURL: URL) throws {
        guard let library = try? device.makeLibrary(URL: libraryURL) else {
            throw GoldenEyeStageBackgroundPipelineError.missingLibrary(libraryURL)
        }
        let compilerDescriptor = MTL4CompilerDescriptor()
        guard let compiler = try? device.makeCompiler(descriptor: compilerDescriptor) else {
            throw GoldenEyeStageBackgroundPipelineError.compilerUnavailable
        }

        let vertexFunction = MTL4LibraryFunctionDescriptor()
        vertexFunction.library = library
        vertexFunction.name = "goldeneye_stage_background_vertex"
        let fragmentFunction = MTL4LibraryFunctionDescriptor()
        fragmentFunction.library = library
        fragmentFunction.name = "goldeneye_stage_background_fragment"

        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.label = label
        descriptor.vertexFunctionDescriptor = vertexFunction
        descriptor.fragmentFunctionDescriptor = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].blendingState = .enabled
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        guard let pipeline = try? compiler.makeRenderPipelineState(descriptor: descriptor) else {
            throw GoldenEyeStageBackgroundPipelineError.creationFailed("MTL4 render pipeline")
        }
        self.pipeline = pipeline
    }
}
