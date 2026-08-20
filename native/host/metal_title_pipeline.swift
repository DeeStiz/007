import Metal

@available(macOS 26.0, *)
enum GoldenEyeTitlePipelineError: Error, CustomStringConvertible {
    case missingLibrary(URL)
    case compilerUnavailable
    case creationFailed(String)

    var description: String {
        switch self {
        case .missingLibrary(let url):
            return "missing GoldenEye title metallib at \(url.path)"
        case .compilerUnavailable:
            return "Metal 4 compiler is unavailable for the title renderer"
        case .creationFailed(let component):
            return "GoldenEye title pipeline creation failed for \(component)"
        }
    }
}

/// Metal 4 PSO for the native title frontend.  The source is intentionally a
/// single fullscreen pass: title state arrives as an immutable fixed-width
/// uniform record and the fragment shader owns only the 4:3-safe frontend
/// shaping.  This is a visual vertical-slice renderer, not an N64 display-list
/// or model interpreter.
@available(macOS 26.0, *)
final class GoldenEyeTitlePipeline {
    let pipeline: any MTLRenderPipelineState
    let geometryPipeline: any MTLRenderPipelineState
    let uvPipeline: any MTLRenderPipelineState
    let iconPipeline: any MTLRenderPipelineState
    let label = "GoldenEye.M15.Title.Pipeline"

    init(device: any MTLDevice, libraryURL: URL) throws {
        guard let library = try? device.makeLibrary(URL: libraryURL) else {
            throw GoldenEyeTitlePipelineError.missingLibrary(libraryURL)
        }
        let compilerDescriptor = MTL4CompilerDescriptor()
        guard let compiler = try? device.makeCompiler(descriptor: compilerDescriptor) else {
            throw GoldenEyeTitlePipelineError.compilerUnavailable
        }

        let vertexFunction = MTL4LibraryFunctionDescriptor()
        vertexFunction.library = library
        vertexFunction.name = "goldeneye_title_vertex"
        let fragmentFunction = MTL4LibraryFunctionDescriptor()
        fragmentFunction.library = library
        fragmentFunction.name = "goldeneye_title_fragment"

        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.label = label
        descriptor.vertexFunctionDescriptor = vertexFunction
        descriptor.fragmentFunctionDescriptor = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].blendingState = .disabled
        guard let pipeline = try? compiler.makeRenderPipelineState(descriptor: descriptor) else {
            throw GoldenEyeTitlePipelineError.creationFailed("MTL4 render pipeline")
        }

        let geometryVertexFunction = MTL4LibraryFunctionDescriptor()
        geometryVertexFunction.library = library
        geometryVertexFunction.name = "goldeneye_title_geometry_vertex"
        let geometryFragmentFunction = MTL4LibraryFunctionDescriptor()
        geometryFragmentFunction.library = library
        geometryFragmentFunction.name = "goldeneye_title_geometry_fragment"
        let geometryDescriptor = MTL4RenderPipelineDescriptor()
        geometryDescriptor.label = "(label).Geometry"
        geometryDescriptor.vertexFunctionDescriptor = geometryVertexFunction
        geometryDescriptor.fragmentFunctionDescriptor = geometryFragmentFunction
        geometryDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        geometryDescriptor.colorAttachments[0].blendingState = .disabled
        guard let geometryPipeline = try? compiler.makeRenderPipelineState(descriptor: geometryDescriptor) else {
            throw GoldenEyeTitlePipelineError.creationFailed("MTL4 title geometry pipeline")
        }

        let uvVertexFunction = MTL4LibraryFunctionDescriptor()
        uvVertexFunction.library = library
        uvVertexFunction.name = "goldeneye_title_uv_vertex"
        let uvFragmentFunction = MTL4LibraryFunctionDescriptor()
        uvFragmentFunction.library = library
        uvFragmentFunction.name = "goldeneye_title_uv_fragment"
        let uvDescriptor = MTL4RenderPipelineDescriptor()
        uvDescriptor.label = "\(label).GETU"
        uvDescriptor.vertexFunctionDescriptor = uvVertexFunction
        uvDescriptor.fragmentFunctionDescriptor = uvFragmentFunction
        uvDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        uvDescriptor.colorAttachments[0].blendingState = .enabled
        uvDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        uvDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        uvDescriptor.colorAttachments[0].rgbBlendOperation = .add
        uvDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        uvDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        uvDescriptor.colorAttachments[0].alphaBlendOperation = .add
        guard let uvPipeline = try? compiler.makeRenderPipelineState(descriptor: uvDescriptor) else {
            throw GoldenEyeTitlePipelineError.creationFailed("MTL4 title GETU UV pipeline")
        }
        let iconVertexFunction = MTL4LibraryFunctionDescriptor()
        iconVertexFunction.library = library
        iconVertexFunction.name = "goldeneye_title_icon_vertex"
        let iconFragmentFunction = MTL4LibraryFunctionDescriptor()
        iconFragmentFunction.library = library
        iconFragmentFunction.name = "goldeneye_title_icon_fragment"
        let iconDescriptor = MTL4RenderPipelineDescriptor()
        iconDescriptor.label = "\(label).Icons"
        iconDescriptor.vertexFunctionDescriptor = iconVertexFunction
        iconDescriptor.fragmentFunctionDescriptor = iconFragmentFunction
        iconDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        iconDescriptor.colorAttachments[0].blendingState = .enabled
        iconDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        iconDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        iconDescriptor.colorAttachments[0].rgbBlendOperation = .add
        iconDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        iconDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        iconDescriptor.colorAttachments[0].alphaBlendOperation = .add
        guard let iconPipeline = try? compiler.makeRenderPipelineState(descriptor: iconDescriptor) else {
            throw GoldenEyeTitlePipelineError.creationFailed("MTL4 title icon pipeline")
        }
        self.pipeline = pipeline
        self.geometryPipeline = geometryPipeline
        self.uvPipeline = uvPipeline
        self.iconPipeline = iconPipeline
    }

    convenience init(device: any MTLDevice, bundle: Bundle = .main) throws {
        guard let url = bundle.url(forResource: "GoldenEyeTitle", withExtension: "metallib") else {
            throw GoldenEyeTitlePipelineError.missingLibrary(
                bundle.bundleURL.appendingPathComponent("GoldenEyeTitle.metallib")
            )
        }
        try self.init(device: device, libraryURL: url)
    }
}
