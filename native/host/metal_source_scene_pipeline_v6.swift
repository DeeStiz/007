#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif
import Metal

/// Pipeline construction errors are explicit so an unsupported source raster
/// state cannot silently select the old diagnostic renderer.
enum GoldenEyeSourceScenePipelineV6Error: Error, CustomStringConvertible {
    case missingLibrary(URL)
    case compilerUnavailable
    case pipelineUnavailable(String)
    case depthStateUnavailable(String)
    case samplerUnavailable(String)
    case unsupportedCombiner(String)
    case unsupportedRasterState(String)

    var description: String {
        switch self {
        case .missingLibrary(let url): return "missing V6 source-scene metallib at \(url.path)"
        case .compilerUnavailable: return "V6 source-scene MTL4Compiler unavailable"
        case .pipelineUnavailable(let key): return "V6 source-scene pipeline unavailable: \(key)"
        case .depthStateUnavailable(let key): return "V6 source-scene depth state unavailable: \(key)"
        case .samplerUnavailable(let key): return "V6 source-scene sampler unavailable: \(key)"
        case .unsupportedCombiner(let detail): return "unsupported V6 source combiner: \(detail)"
        case .unsupportedRasterState(let detail): return "unsupported V6 source raster state: \(detail)"
        }
    }
}

enum GoldenEyeSourceSceneLayoutV6Error: Error, CustomStringConvertible {
    case invalidOutputRect

    var description: String {
        switch self {
        case .invalidOutputRect: return "invalid V6 fidelity output rectangle"
        }
    }
}

/// Integer render rectangles derived from the shared 440x330 fidelity policy.
/// The origin is top-left, matching ``GoldenEyeFidelityLayout``; conversion to
/// Metal's viewport/scissor origin happens at the final boundary.
struct GoldenEyeSourceSceneRectV6: Equatable, Sendable {
    let minX: Int
    let minY: Int
    let maxX: Int
    let maxY: Int

    var width: Int { maxX - minX }
    var height: Int { maxY - minY }
}

struct GoldenEyeSourceSceneLayoutV6: Equatable, Sendable {
    let fidelity: GoldenEyeFidelityLayout
    let viewportRect: GoldenEyeSourceSceneRectV6
    let sourceCoreRect: GoldenEyeSourceSceneRectV6

    init(mode: GoldenEyeFidelityOutputMode, drawableWidth: Int, drawableHeight: Int) {
        let fidelity = GoldenEyeFidelityLayout(
            mode: mode,
            drawableWidth: Double(drawableWidth),
            drawableHeight: Double(drawableHeight)
        )
        self.fidelity = fidelity
        self.sourceCoreRect = Self.integerRect(fidelity.sourceRectInOutput)
        switch mode {
        case .adaptiveWidescreen:
            // 3D source scenes may consume the expanded viewport.  UI/source
            // scissors still use sourceCoreRect below, so the 440x330 core is
            // never stretched.
            self.viewportRect = GoldenEyeSourceSceneRectV6(
                minX: 0,
                minY: 0,
                maxX: drawableWidth,
                maxY: drawableHeight
            )
        case .faithfulHD, .reference320x240:
            self.viewportRect = self.sourceCoreRect
        }
    }

    func sourceScissor(
        command: GESourceDrawCommandV6,
        logicalWidth: UInt32,
        logicalHeight: UInt32
    ) throws -> GoldenEyeSourceSceneRectV6 {
        guard logicalWidth > 0, logicalHeight > 0 else {
            throw GoldenEyeSourceSceneLayoutV6Error.invalidOutputRect
        }
        let scaleX = GoldenEyeFidelityLayout.sourceWidth / Double(logicalWidth)
        let scaleY = GoldenEyeFidelityLayout.sourceHeight / Double(logicalHeight)
        let sourceRect = GoldenEyeFidelityLayout.Rect(
            minX: Double(command.scissor_x) * scaleX,
            minY: Double(command.scissor_y) * scaleY,
            maxX: Double(command.scissor_x + Int32(command.scissor_width)) * scaleX,
            maxY: Double(command.scissor_y + Int32(command.scissor_height)) * scaleY
        )
        let outputRect = fidelity.sourceToOutputRect(sourceRect)
        let integer = Self.integerRect(outputRect)
        let clipped = GoldenEyeSourceSceneRectV6(
            minX: max(0, min(fidelity.outputWidthInt, integer.minX)),
            minY: max(0, min(fidelity.outputHeightInt, integer.minY)),
            maxX: max(0, min(fidelity.outputWidthInt, integer.maxX)),
            maxY: max(0, min(fidelity.outputHeightInt, integer.maxY))
        )
        guard clipped.width > 0, clipped.height > 0 else {
            throw GoldenEyeSourceSceneLayoutV6Error.invalidOutputRect
        }
        return clipped
    }

    var outputWidth: Int { fidelity.outputWidthInt }
    var outputHeight: Int { fidelity.outputHeightInt }

    private static func integerRect(_ rect: GoldenEyeFidelityLayout.Rect) -> GoldenEyeSourceSceneRectV6 {
        GoldenEyeSourceSceneRectV6(
            minX: Int(rect.minX.rounded()),
            minY: Int(rect.minY.rounded()),
            maxX: Int(rect.maxX.rounded()),
            maxY: Int(rect.maxY.rounded())
        )
    }
}

private extension GoldenEyeFidelityLayout {
    var outputWidthInt: Int { Int(outputWidth.rounded()) }
    var outputHeightInt: Int { Int(outputHeight.rounded()) }
}

/// A deterministic cache key copied directly from source render-state words.
/// Raw OtherMode and blender words remain in the key even when their decoded
/// fields are also present. This prevents unlike source equations from being
/// merged by a host-side convenience enum or a guessed default. Texture
/// presence is also part of the key: Legal shade-only draws use a fragment
/// function with no texture binding, while textured draws use the sampled
/// variant even when their render-state words happen to match.
struct GoldenEyeSourceScenePipelineKeyV6: Hashable, Sendable {
    let words: [UInt32]

    init(
        sourceState: GESourceRenderStateV6,
        drawFlags: UInt32,
        hasTexture: Bool = true,
        textureArrayMode: UInt32 = 0
    ) {
        self.words = [
            sourceState.state_handle,
            sourceState.material_handle,
            sourceState.flags,
            sourceState.combiner_cycle_count,
            sourceState.cycle0_color_a,
            sourceState.cycle0_color_b,
            sourceState.cycle0_color_c,
            sourceState.cycle0_color_d,
            sourceState.cycle0_alpha_a,
            sourceState.cycle0_alpha_b,
            sourceState.cycle0_alpha_c,
            sourceState.cycle0_alpha_d,
            sourceState.cycle1_color_a,
            sourceState.cycle1_color_b,
            sourceState.cycle1_color_c,
            sourceState.cycle1_color_d,
            sourceState.cycle1_alpha_a,
            sourceState.cycle1_alpha_b,
            sourceState.cycle1_alpha_c,
            sourceState.cycle1_alpha_d,
            sourceState.primitive_rgba,
            sourceState.environment_rgba,
            sourceState.fog_rgba,
            sourceState.blend_rgba,
            sourceState.depth_mode,
            sourceState.alpha_mode,
            sourceState.coverage_mode,
            sourceState.cull_mode,
            sourceState.filter_mode,
            sourceState.wrap_s,
            sourceState.wrap_t,
            sourceState.lod_min_q16,
            sourceState.lod_max_q16,
            sourceState.raw_othermode_h,
            sourceState.raw_othermode_l,
            sourceState.raw_render_mode,
            sourceState.raw_blender_a,
            sourceState.raw_blender_b,
            sourceState.raw_blender_c,
            sourceState.raw_blender_d,
            drawFlags,
            hasTexture ? (textureArrayMode == 0 ? 1 : 2) : 0
        ]
    }

    var evidenceHash: UInt64 {
        var result: UInt64 = 1_469_598_103_934_665_603
        for word in words {
            result ^= UInt64(word)
            result &*= 1_099_511_628_211
        }
        return result
    }
}

/// Normalized V6 combiner selectors.  Upstream source lowering owns raw GBI
/// slot decoding; every color and alpha slot reaches this renderer with the
/// same selector values, including the single canonical ZERO value.
enum GoldenEyeSourceSceneCombinerSelectorV6 {
    static let combined: UInt32 = 0
    static let texel0: UInt32 = 1
    static let texel1: UInt32 = 2
    static let primitive: UInt32 = 3
    static let shade: UInt32 = 4
    static let environment: UInt32 = 5
    static let one: UInt32 = 6
    static let zero: UInt32 = 7
    /// Source RDP LOD_FRACTION.  This is intentionally kept distinct from
    /// TEXEL1: Rareware's two-cycle pass uses the fractional LOD register in
    /// its combiner while the paired mip samples are supplied by the shader.
    static let lodFraction: UInt32 = 9
    static let combinedAlpha: UInt32 = 15
}

/// The subset of the classic RDP blender which can be represented exactly by
/// a Metal fixed-function color attachment.  The source blender has two color
/// selectors (m1a/m2a) and two alpha-factor selectors (m1b/m2b).  We keep the
/// selectors in the value-only V6 state and only admit equations whose color
/// inputs are the source pixel and destination pixel; blend-color and fog
/// inputs remain typed unsupported states until they are carried to the shader
/// as source values.
private struct GoldenEyeSourceSceneBlendMappingV6 {
    let enabled: Bool
    let sourceRGB: MTLBlendFactor
    let destinationRGB: MTLBlendFactor
    let sourceAlpha: MTLBlendFactor
    let destinationAlpha: MTLBlendFactor
}

private struct GoldenEyeSourceSceneLoweredRasterV6 {
    let depthCompare: MTLCompareFunction
    let depthWrite: Bool
    let alphaToCoverage: Bool
    let blend: GoldenEyeSourceSceneBlendMappingV6
    let texturePerspective: Bool
}

@available(macOS 26.0, *)
final class GoldenEyeSourceScenePipelineV6 {
    final class Variant {
        let key: GoldenEyeSourceScenePipelineKeyV6
        let pipeline: any MTLRenderPipelineState
        let depthStencilState: any MTLDepthStencilState
        let samplerState: any MTLSamplerState
        let cullMode: MTLCullMode
        let label: String

        init(
            key: GoldenEyeSourceScenePipelineKeyV6,
            pipeline: any MTLRenderPipelineState,
            depthStencilState: any MTLDepthStencilState,
            samplerState: any MTLSamplerState,
            cullMode: MTLCullMode,
            label: String
        ) {
            self.key = key
            self.pipeline = pipeline
            self.depthStencilState = depthStencilState
            self.samplerState = samplerState
            self.cullMode = cullMode
            self.label = label
        }
    }

    private let device: any MTLDevice
    private let compiler: any MTL4Compiler
    private let library: any MTLLibrary
    private let pixelFormat: MTLPixelFormat
    private var variants: [GoldenEyeSourceScenePipelineKeyV6: Variant] = [:]

    init(
        device: any MTLDevice,
        libraryURL: URL,
        pixelFormat: MTLPixelFormat = .bgra8Unorm
    ) throws {
        guard FileManager.default.fileExists(atPath: libraryURL.path) else {
            throw GoldenEyeSourceScenePipelineV6Error.missingLibrary(libraryURL)
        }
        guard let library = try? device.makeLibrary(URL: libraryURL) else {
            throw GoldenEyeSourceScenePipelineV6Error.missingLibrary(libraryURL)
        }
        let compilerDescriptor = MTL4CompilerDescriptor()
        guard let compiler = try? device.makeCompiler(descriptor: compilerDescriptor) else {
            throw GoldenEyeSourceScenePipelineV6Error.compilerUnavailable
        }
        self.device = device
        self.compiler = compiler
        self.library = library
        self.pixelFormat = pixelFormat
    }

    func variant(
        for sourceState: GESourceRenderStateV6,
        drawFlags: UInt32,
        hasTexture: Bool = true,
        textureMipLevels: UInt32? = nil,
        textureArrayMode: UInt32 = 0
    ) throws -> Variant {
        let lowered = try Self.lowerRasterState(
            sourceState,
            drawFlags: drawFlags,
            hasTexture: hasTexture,
            textureMipLevels: textureMipLevels
        )
        let key = GoldenEyeSourceScenePipelineKeyV6(
            sourceState: sourceState,
            drawFlags: drawFlags,
            hasTexture: hasTexture,
            textureArrayMode: textureArrayMode
        )
        if let existing = variants[key] {
            return existing
        }

        let label = "GoldenEye.V6.SourceScene.PSO.\(String(key.evidenceHash, radix: 16))"
        let vertexFunction = MTL4LibraryFunctionDescriptor()
        vertexFunction.library = library
        vertexFunction.name = lowered.texturePerspective
            ? "goldeneye_source_scene_v6_vertex"
            : "goldeneye_source_scene_v6_vertex_no_perspective"
        let fragmentFunction = MTL4LibraryFunctionDescriptor()
        fragmentFunction.library = library
        if !hasTexture {
            fragmentFunction.name = lowered.texturePerspective
                ? "goldeneye_source_scene_v6_fragment_no_texture"
                : "goldeneye_source_scene_v6_fragment_no_texture_no_perspective"
        } else if textureArrayMode != 0 {
            fragmentFunction.name = lowered.texturePerspective
                ? "goldeneye_source_scene_v6_fragment_array"
                : "goldeneye_source_scene_v6_fragment_array_no_perspective"
        } else {
            fragmentFunction.name = lowered.texturePerspective
                ? "goldeneye_source_scene_v6_fragment"
                : "goldeneye_source_scene_v6_fragment_no_perspective"
        }

        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.label = label
        descriptor.vertexFunctionDescriptor = vertexFunction
        descriptor.fragmentFunctionDescriptor = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        descriptor.inputPrimitiveTopology = .triangle

        descriptor.alphaToCoverageState = lowered.alphaToCoverage ? .enabled : .disabled
        if lowered.blend.enabled {
            descriptor.colorAttachments[0].blendingState = .enabled
            descriptor.colorAttachments[0].sourceRGBBlendFactor = lowered.blend.sourceRGB
            descriptor.colorAttachments[0].destinationRGBBlendFactor = lowered.blend.destinationRGB
            descriptor.colorAttachments[0].rgbBlendOperation = .add
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = lowered.blend.sourceAlpha
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = lowered.blend.destinationAlpha
            descriptor.colorAttachments[0].alphaBlendOperation = .add
        } else {
            descriptor.colorAttachments[0].blendingState = .disabled
        }

        guard let pipeline = try? compiler.makeRenderPipelineState(descriptor: descriptor) else {
            throw GoldenEyeSourceScenePipelineV6Error.pipelineUnavailable(label)
        }

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = lowered.depthCompare
        depthDescriptor.isDepthWriteEnabled = lowered.depthWrite
        guard let depthState = device.makeDepthStencilState(descriptor: depthDescriptor) else {
            throw GoldenEyeSourceScenePipelineV6Error.depthStateUnavailable(label)
        }

        let samplerDescriptor = MTLSamplerDescriptor()
        switch sourceState.filter_mode {
        case UInt32(GE_SOURCE_FILTER_V6_POINT):
            samplerDescriptor.minFilter = .nearest
            samplerDescriptor.magFilter = .nearest
            samplerDescriptor.mipFilter = .notMipmapped
        case UInt32(GE_SOURCE_FILTER_V6_BILINEAR):
            samplerDescriptor.minFilter = .linear
            samplerDescriptor.magFilter = .linear
            samplerDescriptor.mipFilter = .nearest
        case UInt32(GE_SOURCE_FILTER_V6_TRILINEAR):
            samplerDescriptor.minFilter = .linear
            samplerDescriptor.magFilter = .linear
            samplerDescriptor.mipFilter = .linear
        default:
            throw GoldenEyeSourceScenePipelineV6Error.unsupportedRasterState("filter")
        }
        samplerDescriptor.sAddressMode = try Self.addressMode(for: sourceState.wrap_s)
        samplerDescriptor.tAddressMode = try Self.addressMode(for: sourceState.wrap_t)
        samplerDescriptor.lodMinClamp = Float(sourceState.lod_min_q16) / 65_536.0
        samplerDescriptor.lodMaxClamp = Float(sourceState.lod_max_q16) / 65_536.0
        samplerDescriptor.label = "\(label).Sampler"
        guard let samplerState = device.makeSamplerState(descriptor: samplerDescriptor) else {
            throw GoldenEyeSourceScenePipelineV6Error.samplerUnavailable(label)
        }

        let variant = Variant(
            key: key,
            pipeline: pipeline,
            depthStencilState: depthState,
            samplerState: samplerState,
            cullMode: try Self.cullMode(for: sourceState.cull_mode),
            label: label
        )
        variants[key] = variant
        return variant
    }

    var cachedVariantCount: Int { variants.count }

    /// Build a small source-owned auxiliary pass from the same Metal 4
    /// library.  Gunbarrel background/hole/blood/fade passes share the source
    /// scene device/compiler/residency path but intentionally do not enter the
    /// triangle material cache.
    func auxiliaryPipeline(
        vertexFunctionName: String,
        fragmentFunctionName: String,
        label: String,
        blending: Bool = true
    ) throws -> any MTLRenderPipelineState {
        let vertex = MTL4LibraryFunctionDescriptor()
        vertex.library = library
        vertex.name = vertexFunctionName
        let fragment = MTL4LibraryFunctionDescriptor()
        fragment.library = library
        fragment.name = fragmentFunctionName
        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.label = label
        descriptor.vertexFunctionDescriptor = vertex
        descriptor.fragmentFunctionDescriptor = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        descriptor.inputPrimitiveTopology = .triangle
        if blending {
            descriptor.colorAttachments[0].blendingState = .enabled
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].rgbBlendOperation = .add
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].alphaBlendOperation = .add
        } else {
            descriptor.colorAttachments[0].blendingState = .disabled
        }
        guard let pipeline = try? compiler.makeRenderPipelineState(descriptor: descriptor) else {
            throw GoldenEyeSourceScenePipelineV6Error.pipelineUnavailable(label)
        }
        return pipeline
    }

    /// Validate the exact subset consumed by GoldenEyeSourceSceneV6.metal.
    /// This is public to the pure smoke so unsupported state is tested without
    /// requiring a GPU device or a drawable.  The lowering routine also backs
    /// the live PSO path; there is no validation-only interpretation that can
    /// drift from the descriptor actually submitted to Metal.
    static func validateSupportedState(
        _ sourceState: GESourceRenderStateV6,
        drawFlags: UInt32,
        hasTexture: Bool = true,
        textureMipLevels: UInt32? = nil
    ) throws {
        _ = try lowerRasterState(
            sourceState,
            drawFlags: drawFlags,
            hasTexture: hasTexture,
            textureMipLevels: textureMipLevels
        )
    }

    /// The only geometry-fog blender admitted by the source shader is
    /// G_RM_FOG_SHADE_A: FOG color selected by the first blender color lane,
    /// SHADE alpha as its factor, and IN/1MA for the destination.  The
    /// fragment lowerer supplies the exact fog alpha/color; every other fog
    /// blender (including G_RM_FOG_PRIM_A) remains fail-closed.
    static func isFogShadeGeometryState(_ sourceState: GESourceRenderStateV6) -> Bool {
        sourceState.flags & UInt32(GE_SOURCE_RENDER_STATE_V6_FLAG_FOG) != 0 &&
            isFogShadeBlender(sourceState.raw_render_mode)
    }

    private static func isFogShadeBlender(_ rawMode: UInt32) -> Bool {
        ((rawMode >> 30) & 3) == 3 && // G_BL_CLR_FOG
            ((rawMode >> 26) & 3) == 2 && // G_BL_A_SHADE
            ((rawMode >> 22) & 3) == 0 && // G_BL_CLR_IN
            ((rawMode >> 18) & 3) == 0    // G_BL_1MA
    }

    private static func lowerRasterState(
        _ sourceState: GESourceRenderStateV6,
        drawFlags: UInt32,
        hasTexture: Bool,
        textureMipLevels: UInt32?
    ) throws -> GoldenEyeSourceSceneLoweredRasterV6 {
        let supportedRGB: Set<UInt32> = [
            GoldenEyeSourceSceneCombinerSelectorV6.combined,
            GoldenEyeSourceSceneCombinerSelectorV6.texel0,
            GoldenEyeSourceSceneCombinerSelectorV6.texel1,
            GoldenEyeSourceSceneCombinerSelectorV6.primitive,
            GoldenEyeSourceSceneCombinerSelectorV6.shade,
            GoldenEyeSourceSceneCombinerSelectorV6.environment,
            GoldenEyeSourceSceneCombinerSelectorV6.one,
            GoldenEyeSourceSceneCombinerSelectorV6.zero,
            GoldenEyeSourceSceneCombinerSelectorV6.lodFraction,
            GoldenEyeSourceSceneCombinerSelectorV6.combinedAlpha
        ]
        let supportedAlpha: Set<UInt32> = [
            GoldenEyeSourceSceneCombinerSelectorV6.combined,
            GoldenEyeSourceSceneCombinerSelectorV6.texel0,
            GoldenEyeSourceSceneCombinerSelectorV6.texel1,
            GoldenEyeSourceSceneCombinerSelectorV6.primitive,
            GoldenEyeSourceSceneCombinerSelectorV6.shade,
            GoldenEyeSourceSceneCombinerSelectorV6.environment,
            GoldenEyeSourceSceneCombinerSelectorV6.one,
            GoldenEyeSourceSceneCombinerSelectorV6.zero,
            GoldenEyeSourceSceneCombinerSelectorV6.lodFraction,
            GoldenEyeSourceSceneCombinerSelectorV6.combinedAlpha
        ]
        let cycles: [[UInt32]] = [
            [sourceState.cycle0_color_a, sourceState.cycle0_color_b,
             sourceState.cycle0_color_c, sourceState.cycle0_color_d,
             sourceState.cycle0_alpha_a, sourceState.cycle0_alpha_b,
             sourceState.cycle0_alpha_c, sourceState.cycle0_alpha_d],
            [sourceState.cycle1_color_a, sourceState.cycle1_color_b,
             sourceState.cycle1_color_c, sourceState.cycle1_color_d,
             sourceState.cycle1_alpha_a, sourceState.cycle1_alpha_b,
             sourceState.cycle1_alpha_c, sourceState.cycle1_alpha_d]
        ]
        guard sourceState.combiner_cycle_count == 1 || sourceState.combiner_cycle_count == 2 else {
            throw GoldenEyeSourceScenePipelineV6Error.unsupportedCombiner("cycle count")
        }
        for (cycleIndex, cycle) in cycles.enumerated() {
            let rgb = Array(cycle[0..<4])
            let alpha = Array(cycle[4..<8])
            if cycleIndex == 1, sourceState.combiner_cycle_count == 1,
               rgb.contains(where: { $0 != GoldenEyeSourceSceneCombinerSelectorV6.zero }) ||
               alpha.contains(where: { $0 != GoldenEyeSourceSceneCombinerSelectorV6.zero }) {
                throw GoldenEyeSourceScenePipelineV6Error.unsupportedCombiner(
                    "non-zero second cycle in one-cycle state"
                )
            }
            guard rgb.allSatisfy(supportedRGB.contains), alpha.allSatisfy(supportedAlpha.contains) else {
                throw GoldenEyeSourceScenePipelineV6Error.unsupportedCombiner(
                    "cycle \(cycleIndex) uses LOD/noise/key/center/scale or another unsupported selector"
                )
            }
            let usesTexture = cycle.contains(GoldenEyeSourceSceneCombinerSelectorV6.texel0) ||
                cycle.contains(GoldenEyeSourceSceneCombinerSelectorV6.texel1) ||
                cycle.contains(GoldenEyeSourceSceneCombinerSelectorV6.lodFraction)
            if usesTexture && !hasTexture {
                throw GoldenEyeSourceScenePipelineV6Error.unsupportedCombiner(
                    "cycle \(cycleIndex) selects TEXEL0/TEXEL1 without a source texture"
                )
            }
            if cycle.contains(GoldenEyeSourceSceneCombinerSelectorV6.texel1) {
                guard let textureMipLevels else {
                    throw GoldenEyeSourceScenePipelineV6Error.unsupportedCombiner(
                        "TEXEL1 requires typed texture setup evidence"
                    )
                }
                if textureMipLevels < 2, sourceState.lod_max_q16 != 0 {
                    throw GoldenEyeSourceScenePipelineV6Error.unsupportedCombiner(
                        "TEXEL1 level-one alias requires source maxLOD zero"
                    )
                }
            }
            if cycle.contains(GoldenEyeSourceSceneCombinerSelectorV6.lodFraction),
               sourceState.combiner_cycle_count != 2 {
                throw GoldenEyeSourceScenePipelineV6Error.unsupportedCombiner(
                    "LOD_FRACTION requires the source two-cycle pass"
                )
            }
        }

        let rawH = sourceState.raw_othermode_h
        let rawL = sourceState.raw_othermode_l
        let expectedCycleType = sourceState.combiner_cycle_count == 1 ? 0 : 1
        let rawCycleType = (rawH >> 20) & 3
        let rawFilter = (rawH >> 12) & 3
        let filterMatches: Bool
        switch sourceState.filter_mode {
        case UInt32(GE_SOURCE_FILTER_V6_POINT): filterMatches = rawFilter == 0
        case UInt32(GE_SOURCE_FILTER_V6_BILINEAR): filterMatches = rawFilter == 2 || rawFilter == 3
        case UInt32(GE_SOURCE_FILTER_V6_TRILINEAR): filterMatches = rawFilter == 3
        default: throw GoldenEyeSourceScenePipelineV6Error.unsupportedRasterState("unknown texture filter")
        }
        let texturePerspective = ((rawH >> 19) & 1) != 0
        let rawTextureConvert = (rawH >> 9) & 7
        guard rawCycleType == expectedCycleType,
              ((rawH >> 23) & 1) == 0,
              ((rawH >> 17) & 3) == 0,
              ((rawH >> 14) & 3) == 0,
              filterMatches,
              (rawTextureConvert == 0 || rawTextureConvert == 6),
              ((rawH >> 8) & 1) == 0,
              ((rawH >> 6) & 3) == 0,
              ((rawH >> 4) & 3) == 0 else {
            throw GoldenEyeSourceScenePipelineV6Error.unsupportedRasterState("raw othermode texture/dither bits")
        }
        let lodEnabled = ((rawH >> 16) & 1) != 0
        let usesLOD = cycles.flatMap { $0 }.contains(
            GoldenEyeSourceSceneCombinerSelectorV6.lodFraction
        )
        if usesLOD {
            let goldenEyeLODCombiner =
                sourceState.combiner_cycle_count == 2 &&
                sourceState.cycle0_color_a == GoldenEyeSourceSceneCombinerSelectorV6.texel1 &&
                sourceState.cycle0_color_b == GoldenEyeSourceSceneCombinerSelectorV6.texel0 &&
                sourceState.cycle0_color_c == GoldenEyeSourceSceneCombinerSelectorV6.lodFraction &&
                sourceState.cycle0_color_d == GoldenEyeSourceSceneCombinerSelectorV6.texel0 &&
                sourceState.cycle0_alpha_a == GoldenEyeSourceSceneCombinerSelectorV6.texel1 &&
                sourceState.cycle0_alpha_b == GoldenEyeSourceSceneCombinerSelectorV6.texel0 &&
                sourceState.cycle0_alpha_c == GoldenEyeSourceSceneCombinerSelectorV6.lodFraction &&
                sourceState.cycle0_alpha_d == GoldenEyeSourceSceneCombinerSelectorV6.texel0 &&
                sourceState.cycle1_color_a == GoldenEyeSourceSceneCombinerSelectorV6.combined &&
                sourceState.cycle1_color_b == GoldenEyeSourceSceneCombinerSelectorV6.zero &&
                sourceState.cycle1_color_c == GoldenEyeSourceSceneCombinerSelectorV6.shade &&
                sourceState.cycle1_color_d == GoldenEyeSourceSceneCombinerSelectorV6.zero &&
                sourceState.cycle1_alpha_a == GoldenEyeSourceSceneCombinerSelectorV6.combined &&
                sourceState.cycle1_alpha_b == GoldenEyeSourceSceneCombinerSelectorV6.zero &&
                sourceState.cycle1_alpha_c == GoldenEyeSourceSceneCombinerSelectorV6.shade &&
                sourceState.cycle1_alpha_d == GoldenEyeSourceSceneCombinerSelectorV6.zero
            let rarewareLODCombiner =
                sourceState.cycle0_alpha_c == GoldenEyeSourceSceneCombinerSelectorV6.lodFraction
            // Stage model sidecars use the exact GoldenEye LOD selector
            // equation with the source opaque stage render mode. Admit only
            // those two authored opaque modes; arbitrary stage LOD/noise/key
            // selectors still fail closed below.
            let stageLODCombiner =
                rawH == 0x0011_2000 &&
                (rawL == 0xc411_2078 || rawL == 0xc410_4dd8 || rawL == 0xc411_2d58 || rawL == 0xc410_49d8 || rawL == 0xc410_4b50) &&
                goldenEyeLODCombiner
            let stageOneLevelLOD =
                rawH == 0x0010_2000 &&
                (rawL == 0xc411_2078 || rawL == 0xc410_49d8) &&
                goldenEyeLODCombiner && textureMipLevels == 1 &&
                sourceState.lod_min_q16 == 0 && sourceState.lod_max_q16 == 0
            guard (rawH == 0x0019_2c00 && rawL == 0x0f0a_4000 && rarewareLODCombiner) ||
                  (rawH == 0x0011_2000 && rawL == 0x0c18_2048 && goldenEyeLODCombiner) ||
                  stageLODCombiner || stageOneLevelLOD else {
                throw GoldenEyeSourceScenePipelineV6Error.unsupportedCombiner(
                    "LOD_FRACTION requires the canonical Rareware or GoldenEye source tuple rawH=0x\(String(rawH, radix: 16)) rawL=0x\(String(rawL, radix: 16)) filter=\(sourceState.filter_mode) "
                        + "cycles=\(sourceState.cycle0_color_a),\(sourceState.cycle0_color_b),\(sourceState.cycle0_color_c),\(sourceState.cycle0_color_d);"
                        + "\(sourceState.cycle1_color_a),\(sourceState.cycle1_color_b),\(sourceState.cycle1_color_c),\(sourceState.cycle1_color_d) "
                        + "alpha=\(sourceState.cycle0_alpha_a),\(sourceState.cycle0_alpha_b),\(sourceState.cycle0_alpha_c),\(sourceState.cycle0_alpha_d);"
                        + "\(sourceState.cycle1_alpha_a),\(sourceState.cycle1_alpha_b),\(sourceState.cycle1_alpha_c),\(sourceState.cycle1_alpha_d) "
                        + "lod=\(sourceState.lod_min_q16)...\(sourceState.lod_max_q16) mip=\(textureMipLevels ?? 0)"
                )
            }
            guard lodEnabled || stageOneLevelLOD else {
                throw GoldenEyeSourceScenePipelineV6Error.unsupportedRasterState(
                    "LOD_FRACTION requires source texture LOD"
                )
            }
            guard let textureMipLevels, textureMipLevels > 0 else {
                throw GoldenEyeSourceScenePipelineV6Error.unsupportedRasterState(
                    "LOD_FRACTION requires typed texture setup evidence"
                )
            }
            let lastResidentLOD = UInt32(textureMipLevels - 1) << 16
            guard sourceState.lod_max_q16 <= lastResidentLOD else {
                throw GoldenEyeSourceScenePipelineV6Error.unsupportedRasterState(
                    "LOD_FRACTION exceeds resident mip chain"
                )
            }
            if textureMipLevels == 1 {
                guard sourceState.lod_max_q16 == 0 else {
                    throw GoldenEyeSourceScenePipelineV6Error.unsupportedRasterState(
                        "one-level GoldenEye auxiliary texture requires maxLOD zero"
                    )
                }
            }
        }
        if sourceState.filter_mode == UInt32(GE_SOURCE_FILTER_V6_TRILINEAR),
           (!lodEnabled || sourceState.lod_max_q16 == 0) {
            throw GoldenEyeSourceScenePipelineV6Error.unsupportedRasterState(
                "trilinear filtering requires a resident mip chain"
            )
        }
        if lodEnabled {
            guard sourceState.lod_max_q16 >= sourceState.lod_min_q16 else {
                throw GoldenEyeSourceScenePipelineV6Error.unsupportedRasterState("reversed LOD clamp")
            }
        } else {
            guard sourceState.lod_min_q16 == 0, sourceState.lod_max_q16 == 0 else {
                throw GoldenEyeSourceScenePipelineV6Error.unsupportedRasterState("LOD clamp without texture LOD")
            }
        }

        let alphaMode = rawL & 3
        guard alphaMode == sourceState.alpha_mode,
              alphaMode == UInt32(GE_SOURCE_ALPHA_V6_DISABLED) else {
            throw GoldenEyeSourceScenePipelineV6Error.unsupportedRasterState(
                "alpha compare requires source blend-color payload"
            )
        }
        guard ((rawL >> 2) & 1) == 0,
              (rawL & 0xfffffff8) == sourceState.raw_render_mode else {
            throw GoldenEyeSourceScenePipelineV6Error.unsupportedRasterState("raw othermode/decoded mismatch")
        }

        let mode = sourceState.raw_render_mode
        let aa = ((mode >> 3) & 1) != 0
        let zCompare = ((mode >> 4) & 1) != 0
        let zUpdate = ((mode >> 5) & 1) != 0
        let coverageDestination = (mode >> 8) & 3
        let zMode = (mode >> 10) & 3
        let coverageXAlpha = ((mode >> 12) & 1) != 0
        let alphaCoverageSelect = ((mode >> 13) & 1) != 0
        let forceBlend = ((mode >> 14) & 1) != 0
        guard sourceState.flags & ~UInt32(GE_SOURCE_RENDER_STATE_V6_FLAG_MASK) == 0 else {
            throw GoldenEyeSourceScenePipelineV6Error.unsupportedRasterState("unknown render-state flags")
        }
        let expectedDepth: UInt32
        if zCompare { expectedDepth = UInt32(GE_SOURCE_DEPTH_V6_LEQUAL) }
        else if zUpdate { expectedDepth = UInt32(GE_SOURCE_DEPTH_V6_ALWAYS) }
        else { expectedDepth = UInt32(GE_SOURCE_DEPTH_V6_DISABLED) }
        guard sourceState.depth_mode == expectedDepth,
              (sourceState.flags & UInt32(GE_SOURCE_RENDER_STATE_V6_FLAG_DEPTH_TEST) != 0) == (expectedDepth != UInt32(GE_SOURCE_DEPTH_V6_DISABLED)),
              (sourceState.flags & UInt32(GE_SOURCE_RENDER_STATE_V6_FLAG_DEPTH_WRITE) != 0) == zUpdate,
              (sourceState.flags & UInt32(GE_SOURCE_RENDER_STATE_V6_FLAG_ANTIALIAS) != 0) == aa,
              (sourceState.flags & UInt32(GE_SOURCE_RENDER_STATE_V6_FLAG_COVERAGE) != 0) == (coverageDestination != 0) else {
            throw GoldenEyeSourceScenePipelineV6Error.unsupportedRasterState("render-mode/decoded depth or coverage mismatch")
        }
        let fogEnabled = sourceState.flags & UInt32(GE_SOURCE_RENDER_STATE_V6_FLAG_FOG) != 0
        let fogAlpha = sourceState.fog_rgba & 0xff
        let typedNoOpFog = fogAlpha == 0
        if fogEnabled {
            // G_FOG + G_RM_FOG_SHADE_A is the exact geometry-fog path.  The
            // source G_SETFOGCOLOR register carries an authored alpha byte
            // (normally 0xff); the renderer binds the stage EnvironmentRecord
            // color and the typed fm/fo pair, so a nonzero source fog-register
            // alpha is not a reason to reject this exact mode.
            guard Self.isFogShadeGeometryState(sourceState) else {
                throw GoldenEyeSourceScenePipelineV6Error.unsupportedRasterState(
                    "G_FOG requires the exact G_RM_FOG_SHADE_A blender tuple"
                )
            }
        } else {
            // The source Gunbarrel/cast Type-4 setup emits the fog register as
            // opaque white RGB with zero alpha (0xFFFFFF00). It is a typed
            // no-op until a per-fragment prop factor is available.
            guard !Self.isFogShadeBlender(mode),
                  sourceState.fog_rgba == 0 || typedNoOpFog else {
                throw GoldenEyeSourceScenePipelineV6Error.unsupportedRasterState(
                    "fog requires a shader fog payload flags=0x\(String(sourceState.flags, radix: 16)) fog=0x\(String(sourceState.fog_rgba, radix: 16))"
                )
            }
        }
        let rarewareForcedPass = mode == 0x0f0a_4000 && sourceState.combiner_cycle_count == 2
        let coverageSave = coverageDestination == 3 &&
            sourceState.coverage_mode == UInt32(GE_SOURCE_COVERAGE_V6_SAVE) &&
            sourceState.flags & UInt32(GE_SOURCE_RENDER_STATE_V6_FLAG_COVERAGE_SAVE) != 0
        let gunbarrelSecondary = mode == 0xc410_41c8
            && drawFlags & UInt32(GE_SOURCE_DRAW_V6_FLAG_TRANSLUCENT) != 0
        // Cast uses the same authored Type-4 translucent equation as
        // Gunbarrel, but its source render mode enables ZMODE_XLU
        // (0xc41049d8): coverage WRAP, Z compare, no depth write, and
        // FORCE_BLEND. Keep this exact tuple typed rather than allowing an
        // arbitrary depth/coverage combination through the generic path.
        let castSecondary = mode == 0xc410_49d8
            && sourceState.combiner_cycle_count == 2
            && drawFlags & UInt32(GE_SOURCE_DRAW_V6_FLAG_TRANSLUCENT) != 0
            && sourceState.depth_mode == UInt32(GE_SOURCE_DEPTH_V6_LEQUAL)
            && sourceState.flags & UInt32(GE_SOURCE_RENDER_STATE_V6_FLAG_DEPTH_TEST) != 0
            && sourceState.flags & UInt32(GE_SOURCE_RENDER_STATE_V6_FLAG_DEPTH_WRITE) == 0
            && sourceState.coverage_mode == UInt32(GE_SOURCE_COVERAGE_V6_WRAP)
        let stageXluMode = mode == 0xc410_49d8 || mode == 0xc410_4b50 || mode == 0x0c18_49d8 || mode == 0x0050_49d8
        let stageDecalMode = mode == 0xc410_4dd8 || mode == 0xc411_2d58 || mode == 0x0c18_4dd8 || mode == 0x0c19_2d58 ||
            mode == 0x0c18_4e50 || mode == 0x0050_4dd8 || mode == 0x0050_4e50 ||
            // Source G_RM_AA_ZB_OPA_DECAL as emitted by the guarded
            // static-prop sidecars. Coverage wrap/zmode decal remains
            // explicit; the Metal mapping below supplies only the proven
            // straight-alpha color-memory equation.
            mode == 0x0055_2d58
        guard (coverageDestination == 0 || coverageSave || stageXluMode || stageDecalMode || gunbarrelSecondary || castSecondary),
              (zMode == 0 || stageXluMode || stageDecalMode || castSecondary), !coverageXAlpha,
              !forceBlend || alphaCoverageSelect || stageXluMode || stageDecalMode || rarewareForcedPass || coverageSave || gunbarrelSecondary || castSecondary else {
            throw GoldenEyeSourceScenePipelineV6Error.unsupportedRasterState(
                "coverage/decal/forced blend mode raw=0x\(String(mode, radix: 16)) "
                    + "cov=\(coverageDestination) zmode=\(zMode) force=\(forceBlend ? 1 : 0) "
                    + "alphaCoverage=\(alphaCoverageSelect ? 1 : 0) drawFlags=0x\(String(drawFlags, radix: 16))"
            )
        }
        func pairedBlender(_ cycle0Shift: UInt32, _ cycle1Shift: UInt32) -> UInt32 {
            ((mode >> cycle0Shift) & 3) | (((mode >> cycle1Shift) & 3) << 2)
        }
        guard sourceState.raw_blender_a == pairedBlender(30, 28),
              sourceState.raw_blender_b == pairedBlender(26, 24),
              sourceState.raw_blender_c == pairedBlender(22, 20),
              sourceState.raw_blender_d == pairedBlender(18, 16) else {
            throw GoldenEyeSourceScenePipelineV6Error.unsupportedRasterState("raw blender/packed blender mismatch")
        }
        let blend = try blendMapping(rawMode: mode, cycleCount: sourceState.combiner_cycle_count)
        let drawKindMask = UInt32(GE_SOURCE_DRAW_V6_FLAG_OPAQUE) |
            UInt32(GE_SOURCE_DRAW_V6_FLAG_DECAL) |
            UInt32(GE_SOURCE_DRAW_V6_FLAG_TRANSLUCENT)
        let drawKind = drawFlags & drawKindMask
        guard drawKind != 0, drawKind & (drawKind - 1) == 0 else {
            throw GoldenEyeSourceScenePipelineV6Error.unsupportedRasterState("ambiguous draw blend mode")
        }
        if !blend.enabled, drawKind != UInt32(GE_SOURCE_DRAW_V6_FLAG_OPAQUE) {
            throw GoldenEyeSourceScenePipelineV6Error.unsupportedRasterState("draw mode disagrees with opaque blender")
        }

        _ = try cullMode(for: sourceState.cull_mode)
        _ = try addressMode(for: sourceState.wrap_s)
        _ = try addressMode(for: sourceState.wrap_t)
        return GoldenEyeSourceSceneLoweredRasterV6(
            depthCompare: try compareFunction(for: sourceState.depth_mode),
            depthWrite: zUpdate,
            alphaToCoverage: aa && alphaCoverageSelect,
            blend: blend,
            texturePerspective: texturePerspective
        )
    }

    private static func blendMapping(
        rawMode: UInt32,
        cycleCount: UInt32
    ) throws -> GoldenEyeSourceSceneBlendMappingV6 {
        if cycleCount == 1 && isFogShadeBlender(rawMode) {
            // The source geometry fog is lowered in the fragment equation;
            // no Metal attachment blend remains for a one-cycle fog pass.
            return GoldenEyeSourceSceneBlendMappingV6(
                enabled: false,
                sourceRGB: .one,
                destinationRGB: .zero,
                sourceAlpha: .one,
                destinationAlpha: .zero
            )
        }
        if rawMode == 0xc410_4dd8 || rawMode == 0xc411_2d58 || rawMode == 0xc410_49d8 || rawMode == 0xc410_4b50 ||
            rawMode == 0x0c18_49d8 || rawMode == 0x0c18_4dd8 ||
            rawMode == 0x0c19_2d58 || rawMode == 0x0c18_4e50 ||
            rawMode == 0x0050_49d8 || rawMode == 0x0050_4dd8 || rawMode == 0x0050_4e50 ||
            rawMode == 0x0055_2d58 {
            // Source stage XLU/decal room passes use coverage wrap and
            // source-alpha-over-memory color. Metal has no N64 coverage
            // register, so the typed stage tuple maps to the corresponding
            // straight-alpha attachment equation while retaining the source
            // depth/coverage flags for validation.
            return GoldenEyeSourceSceneBlendMappingV6(
                enabled: true,
                sourceRGB: .sourceAlpha,
                destinationRGB: .oneMinusSourceAlpha,
                sourceAlpha: .one,
                destinationAlpha: .oneMinusSourceAlpha
            )
        }
        // Rareware's authored second pass uses G_RM_PASS/G_RM_OPA_SURF2.
        // FORCE_BLEND is part of the copied source render-mode evidence, but
        // the PASS blender still writes the source color directly; treating
        // it as a generic alpha blend would change the logo edge colors.
        if rawMode == 0x0f0a_4000 && cycleCount == 2 {
            return GoldenEyeSourceSceneBlendMappingV6(
                enabled: false,
                sourceRGB: .one,
                destinationRGB: .zero,
                sourceAlpha: .one,
                destinationAlpha: .zero
            )
        }
        if rawMode == 0x0c18_4340 && cycleCount == 2 {
            // Wallet's source coverage-save/force-blend mode has no direct
            // Metal coverage-memory target. Preserve its alpha-weighted
            // source/destination equation in the color attachment while the
            // typed V6 coverage-save bit remains available for diagnostics.
            return GoldenEyeSourceSceneBlendMappingV6(
                enabled: true,
                sourceRGB: .sourceAlpha,
                destinationRGB: .oneMinusSourceAlpha,
                sourceAlpha: .one,
                destinationAlpha: .oneMinusSourceAlpha
            )
        }
        if rawMode == 0xc410_41c8 && cycleCount == 2 {
            // Gunbarrel Type-4 secondary is the source translucent pass with
            // coverage WRAP/force-blend; Metal's straight alpha blend is the
            // corresponding color-memory equation.
            return GoldenEyeSourceSceneBlendMappingV6(
                enabled: true,
                sourceRGB: .sourceAlpha,
                destinationRGB: .oneMinusSourceAlpha,
                sourceAlpha: .one,
                destinationAlpha: .oneMinusSourceAlpha
            )
        }
        if rawMode == 0xc410_49d8 && cycleCount == 2 {
            // Cast Type-4 secondary is the depth-tested counterpart of the
            // Gunbarrel translucent pass. Its source blender still resolves
            // to straight source-alpha over the destination color.
            return GoldenEyeSourceSceneBlendMappingV6(
                enabled: true,
                sourceRGB: .sourceAlpha,
                destinationRGB: .oneMinusSourceAlpha,
                sourceAlpha: .one,
                destinationAlpha: .oneMinusSourceAlpha
            )
        }
        func unpack(_ shift: UInt32) -> (UInt32, UInt32, UInt32, UInt32) {
            (
                (rawMode >> shift) & 3,
                (rawMode >> (shift - 4)) & 3,
                (rawMode >> (shift - 8)) & 3,
                (rawMode >> (shift - 12)) & 3
            )
        }
        let cycle = unpack(cycleCount == 1 ? 30 : 28)
        let m1a = cycle.0
        let m1b = cycle.1
        let m2a = cycle.2
        let m2b = cycle.3
        guard m1a == 0 else {
            throw GoldenEyeSourceScenePipelineV6Error.unsupportedRasterState("blender m1a is not source color")
        }
        if m2a == 0, m1b == 3, m2b == 2 {
            return GoldenEyeSourceSceneBlendMappingV6(
                enabled: false,
                sourceRGB: .one,
                destinationRGB: .zero,
                sourceAlpha: .one,
                destinationAlpha: .zero
            )
        }
        guard m2a == 1 else {
            throw GoldenEyeSourceScenePipelineV6Error.unsupportedRasterState("blender m2a is not memory color")
        }
        // N64's m1b and m2b fields use the same two-bit encoding but they
        // describe different coefficient namespaces.  In particular m2b=0
        // is G_BL_1MA (one-minus-source-alpha), not source alpha.  Sharing one
        // lookup table made otherwise opaque title/cast tuples look washed out
        // and produced the wrong destination equation for future XLU draws.
        func sourceFactor(_ selector: UInt32) throws -> MTLBlendFactor {
            switch selector {
            case 0: return .sourceAlpha
            case 1: return .destinationAlpha
            case 2: return .one
            case 3: return .zero
            default: throw GoldenEyeSourceScenePipelineV6Error.unsupportedRasterState("unknown blender alpha selector")
            }
        }
        func destinationFactor(_ selector: UInt32) throws -> MTLBlendFactor {
            switch selector {
            case 0: return .oneMinusSourceAlpha
            case 1: return .destinationAlpha
            case 2: return .one
            case 3: return .zero
            default: throw GoldenEyeSourceScenePipelineV6Error.unsupportedRasterState("unknown blender destination selector")
            }
        }
        return GoldenEyeSourceSceneBlendMappingV6(
            enabled: true,
            sourceRGB: try sourceFactor(m1b),
            destinationRGB: try destinationFactor(m2b),
            sourceAlpha: try sourceFactor(m1b),
            destinationAlpha: try destinationFactor(m2b)
        )
    }

    private static func compareFunction(for value: UInt32) throws -> MTLCompareFunction {
        switch value {
        case UInt32(GE_SOURCE_DEPTH_V6_LESS): return .less
        case UInt32(GE_SOURCE_DEPTH_V6_LEQUAL): return .lessEqual
        case UInt32(GE_SOURCE_DEPTH_V6_EQUAL): return .equal
        case UInt32(GE_SOURCE_DEPTH_V6_ALWAYS): return .always
        case UInt32(GE_SOURCE_DEPTH_V6_DISABLED): return .always
        default: throw GoldenEyeSourceScenePipelineV6Error.unsupportedRasterState("unknown depth compare")
        }
    }

    private static func cullMode(for value: UInt32) throws -> MTLCullMode {
        switch value {
        case UInt32(GE_SOURCE_CULL_V6_NONE): return .none
        case UInt32(GE_SOURCE_CULL_V6_FRONT): return .front
        case UInt32(GE_SOURCE_CULL_V6_BACK): return .back
        case UInt32(GE_SOURCE_CULL_V6_BOTH):
            throw GoldenEyeSourceScenePipelineV6Error.unsupportedRasterState("both-face cull")
        default:
            throw GoldenEyeSourceScenePipelineV6Error.unsupportedRasterState("unknown cull mode")
        }
    }

    private static func addressMode(for value: UInt32) throws -> MTLSamplerAddressMode {
        switch value {
        case UInt32(GE_SOURCE_WRAP_V6_CLAMP): return .clampToEdge
        case UInt32(GE_SOURCE_WRAP_V6_REPEAT): return .repeat
        case UInt32(GE_SOURCE_WRAP_V6_MIRROR): return .mirrorRepeat
        default: throw GoldenEyeSourceScenePipelineV6Error.unsupportedRasterState("unknown texture address mode")
        }
    }
}
