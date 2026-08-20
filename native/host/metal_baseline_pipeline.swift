import Metal

@available(macOS 26.0, *)
enum GoldenEyeBaselinePipelineError: Error, CustomStringConvertible {
    case missingLibrary(URL)
    case creationFailed(String)

    var description: String {
        switch self {
        case .missingLibrary(let url): return "missing baseline metallib at \(url.path)"
        case .creationFailed(let component): return "baseline pipeline creation failed for \(component)"
        }
    }
}

@available(macOS 26.0, *)
final class GoldenEyeBaselinePipeline {
    let pipeline: any MTLRenderPipelineState
    let label = "GoldenEye.M6.BaselinePipeline"

    init(device: any MTLDevice, libraryURL: URL) throws {
        guard let library = try? device.makeLibrary(URL: libraryURL) else {
            throw GoldenEyeBaselinePipelineError.missingLibrary(libraryURL)
        }
        let compilerDescriptor = MTL4CompilerDescriptor()
        guard let compiler = try? device.makeCompiler(descriptor: compilerDescriptor) else {
            throw GoldenEyeBaselinePipelineError.creationFailed("MTL4 compiler")
        }
        let vertexFunction = MTL4LibraryFunctionDescriptor()
        vertexFunction.library = library
        vertexFunction.name = "goldeneye_baseline_vertex"
        let fragmentFunction = MTL4LibraryFunctionDescriptor()
        fragmentFunction.library = library
        fragmentFunction.name = "goldeneye_baseline_fragment"
        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.label = label
        descriptor.vertexFunctionDescriptor = vertexFunction
        descriptor.fragmentFunctionDescriptor = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? compiler.makeRenderPipelineState(descriptor: descriptor) else {
            throw GoldenEyeBaselinePipelineError.creationFailed("MTL4 render pipeline")
        }
        self.pipeline = pipeline
    }
}
