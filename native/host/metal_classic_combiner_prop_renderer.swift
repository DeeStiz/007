import Foundation
import Metal
import QuartzCore
import GoldenEyeNative

/// Errors for the bounded V4 combiner/render-mode consumer.  The renderer
/// fails closed when a sidecar key does not correlate with the frozen V3
/// geometry/material result; it never falls back to the previous diagnostic
/// vertex-color renderer.
@available(macOS 26.0, *)
enum GoldenEyeClassicCombinerPropRendererError: Error, CustomStringConvertible {
    case missingLibrary(URL)
    case pipelineCreationFailed(String)
    case loweringFailed(GEStatusV1)
    case replayFailed(GEStatusV1)
    case malformedLowering(String)
    case malformedReplay(String)
    case malformedTexture(String)
    case missingTexture(UInt32)
    case emptyReplay
    case bufferCreationFailed(String)
    case textureCreationFailed(UInt32)
    case samplerCreationFailed
    case computeEncoderUnavailable

    var description: String {
        switch self {
        case .missingLibrary(let url):
            return "missing classic combiner prop metallib at \(url.path)"
        case .pipelineCreationFailed(let component):
            return "classic combiner prop pipeline creation failed for \(component)"
        case .loweringFailed(let status):
            return "classic combiner V4 lowering failed with status \(status)"
        case .replayFailed(let status):
            return "classic textured V3 replay failed with status \(status)"
        case .malformedLowering(let detail):
            return "classic combiner V4 lowering is malformed: \(detail)"
        case .malformedReplay(let detail):
            return "classic combiner textured replay is malformed: \(detail)"
        case .malformedTexture(let detail):
            return "classic combiner texture is malformed: \(detail)"
        case .missingTexture(let textureID):
            return "classic combiner references missing texture \(textureID)"
        case .emptyReplay:
            return "classic combiner replay produced no indexed geometry"
        case .bufferCreationFailed(let component):
            return "classic combiner buffer creation failed for \(component)"
        case .textureCreationFailed(let textureID):
            return "classic combiner texture creation failed for \(textureID)"
        case .samplerCreationFailed:
            return "classic combiner sampler creation failed"
        case .computeEncoderUnavailable:
            return "classic combiner could not create the Metal 4 compute encoder"
        }
    }
}

/// Metal 4 pipelines for the captured ModelType-4 combiner.  The combiner
/// remains in MSL; the two authored render-mode words select the bounded
/// pipeline blend mapping.  The additive M9 lane also creates explicit depth
/// states for the source Z compare/update bits; the V4 key remains unchanged.
@available(macOS 26.0, *)
final class GoldenEyeClassicCombinerPropPipeline {
    static let opaqueRenderMode: UInt32 = 0xC4112078
    static let authoredRenderMode: UInt32 = 0xC4104DD8

    private let pipelines: [UInt32: any MTLRenderPipelineState]
    private let depthStates: [UInt32: any MTLDepthStencilState]
    let label = "GoldenEye.M12.ClassicCombiner.Pipeline"

    init(device: any MTLDevice, libraryURL: URL) throws {
        guard let library = try? device.makeLibrary(URL: libraryURL) else {
            throw GoldenEyeClassicCombinerPropRendererError.missingLibrary(libraryURL)
        }

        let compilerDescriptor = MTL4CompilerDescriptor()
        guard let compiler = try? device.makeCompiler(descriptor: compilerDescriptor) else {
            throw GoldenEyeClassicCombinerPropRendererError.pipelineCreationFailed("MTL4 compiler")
        }

        func buildPipeline(name: String, blendEnabled: Bool) throws -> any MTLRenderPipelineState {
            let vertexFunction = MTL4LibraryFunctionDescriptor()
            vertexFunction.library = library
            vertexFunction.name = "goldeneye_classic_combiner_prop_vertex"
            let fragmentFunction = MTL4LibraryFunctionDescriptor()
            fragmentFunction.library = library
            fragmentFunction.name = "goldeneye_classic_combiner_prop_fragment"

            let descriptor = MTL4RenderPipelineDescriptor()
            descriptor.label = name
            descriptor.vertexFunctionDescriptor = vertexFunction
            descriptor.fragmentFunctionDescriptor = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            // The primary source mode selects alpha coverage; the authored
            // decal mode uses explicit blend/coverage handling instead.
            descriptor.alphaToCoverageState = blendEnabled ? .disabled : .enabled
            if blendEnabled {
                // The authored C4104DD8 mode is a bounded decal/translucent
                // mapping.  This is the Metal blend approximation for the
                // color path; Z, coverage, fog, and alpha compare stay in the
                // V4 deferred flags rather than being silently invented here.
                descriptor.colorAttachments[0].blendingState = .enabled
                descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
                descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                descriptor.colorAttachments[0].rgbBlendOperation = .add
                descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
                descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
                descriptor.colorAttachments[0].alphaBlendOperation = .add
            } else {
                // C4112078 is the primary opaque source mode. Its depth and
                // coverage bits are recorded by V4 and owned by a later goal.
                // TODO(depth-fog-alpha-goal): provide the depth attachment and
                // exact coverage/alpha state before claiming RDP parity.
                descriptor.colorAttachments[0].blendingState = .disabled
            }
            guard let pipeline = try? compiler.makeRenderPipelineState(descriptor: descriptor) else {
                throw GoldenEyeClassicCombinerPropRendererError.pipelineCreationFailed(name)
            }
            return pipeline
        }

        let opaque = try buildPipeline(
            name: "GoldenEye.M12.ClassicCombiner.Pipeline.Opaque.C4112078",
            blendEnabled: false
        )
        let authored = try buildPipeline(
            name: "GoldenEye.M12.ClassicCombiner.Pipeline.Authored.C4104DD8",
            blendEnabled: true
        )
        let opaqueDepthDescriptor = MTLDepthStencilDescriptor()
        opaqueDepthDescriptor.label = "GoldenEye.M9.Depth.Opaque.C4112078"
        opaqueDepthDescriptor.depthCompareFunction = .lessEqual
        opaqueDepthDescriptor.isDepthWriteEnabled = true
        guard let opaqueDepth = device.makeDepthStencilState(descriptor: opaqueDepthDescriptor) else {
            throw GoldenEyeClassicCombinerPropRendererError.pipelineCreationFailed("opaque depth state")
        }

        let decalDepthDescriptor = MTLDepthStencilDescriptor()
        decalDepthDescriptor.label = "GoldenEye.M9.Depth.Decal.C4104DD8"
        decalDepthDescriptor.depthCompareFunction = .lessEqual
        decalDepthDescriptor.isDepthWriteEnabled = false
        guard let decalDepth = device.makeDepthStencilState(descriptor: decalDepthDescriptor) else {
            throw GoldenEyeClassicCombinerPropRendererError.pipelineCreationFailed("decal depth state")
        }

        self.pipelines = [
            Self.opaqueRenderMode: opaque,
            Self.authoredRenderMode: authored,
        ]
        self.depthStates = [
            Self.opaqueRenderMode: opaqueDepth,
            Self.authoredRenderMode: decalDepth,
        ]
    }

    convenience init(device: any MTLDevice, bundle: Bundle = .main) throws {
        guard let libraryURL = bundle.url(
            forResource: "GoldenEyeClassicCombinerProp",
            withExtension: "metallib"
        ) else {
            throw GoldenEyeClassicCombinerPropRendererError.missingLibrary(
                bundle.bundleURL.appendingPathComponent("GoldenEyeClassicCombinerProp.metallib")
            )
        }
        try self.init(device: device, libraryURL: libraryURL)
    }

    func pipeline(for rawRenderMode: UInt32) throws -> any MTLRenderPipelineState {
        guard let pipeline = pipelines[rawRenderMode] else {
            throw GoldenEyeClassicCombinerPropRendererError.malformedLowering(
                "unsupported render-mode word 0x\(String(rawRenderMode, radix: 16))"
            )
        }
        return pipeline
    }

    func depthState(for rawRenderMode: UInt32) throws -> any MTLDepthStencilState {
        guard let state = depthStates[rawRenderMode] else {
            throw GoldenEyeClassicCombinerPropRendererError.malformedLowering(
                "unsupported depth render-mode word 0x\(String(rawRenderMode, radix: 16))"
            )
        }
        return state
    }
}

/// Metal 4 consumer for the V4 lowering sidecar plus the additive M9 raster
/// policy and frozen V3 textured geometry/material result. The sidecars are
/// keyed by source command offset/render mode; V3 remains the only source for
/// vertices, UVs, triangles, and texture IDs.
@available(macOS 26.0, *)
final class GoldenEyeMetalClassicCombinerPropRenderer: GoldenEyeFrameRenderer, @unchecked Sendable {
    private static let decodedResultPixelsOffset = 148
    private static let decodedResultSize = 17_560

    private struct GPUVertex {
        var position: SIMD4<Float>
        var texcoord: SIMD2<Float>
        var color: SIMD4<Float>
    }

    // Keep this layout in lockstep with
    // GoldenEyeClassicCombinerPropTransient in the V4 MSL.  Every field is a
    // fixed-width word copied from a V4 key or the correlated V3 packet.
    private struct GPUTransient {
        var textureID: UInt32
        var materialFlags: UInt32
        var sourceCommandOffset: UInt32
        var combinerKey: UInt32
        var renderModeKey: UInt32
        var otherModeH: UInt32
        var otherModeL: UInt32
        var combineW0: UInt32
        var combineW1: UInt32
        var combinerFlags: UInt32
        var renderModeFlags: UInt32
        var stateHashLow: UInt32
        var stateHashHigh: UInt32
        var reserved0: UInt32
        var reserved1: UInt32
        var reserved2: UInt32
        var alphaCompare: UInt32
        var alphaPolicy: UInt32
        var alphaThresholdQ8: UInt32
        var fogEnabled: UInt32
        var fogColorRGBA8: UInt32
        var fogAlphaQ8: UInt32
        var coverageFlags: UInt32
    }

    private struct DrawRange {
        let indexOffset: Int
        let indexCount: Int
        let vertexOffset: Int
        let transientIndex: Int
        let textureID: UInt32
        let sourceCommandOffset: UInt32
        let rawRenderMode: UInt32
        let keyHash: UInt64
    }

    private struct TextureUpload {
        let texture: any MTLTexture
        let staging: any MTLBuffer
        let width: Int
        let height: Int
        let sourceHash: UInt64
        let decodedHash: UInt64
    }

    private struct PendingStagingRetirement {
        let signalValue: UInt64
        let buffer: any MTLBuffer
    }

    private struct ReplayEvidence {
        let loweringStatus: GEStatusV1
        let replayStatus: GEStatusV1
        let commandsProcessed: UInt32
        let setupCommandsProcessed: UInt32
        let replayCommandsProcessed: UInt32
        let drawCount: UInt32
        let vertexCount: UInt32
        let triangleCount: UInt32
        let setupHash: UInt64
        let eventHash: UInt64
        let keyHash: UInt64
        let packetHash: UInt64
        let replayEventHash: UInt64
        let materialHash: UInt64
    }

    private let state: GoldenEyeMetalDeviceState
    private let layer: CAMetalLayer
    private let pipeline: GoldenEyeClassicCombinerPropPipeline
    private let loweringResult: GEClassicCombinerLoweringResultV4
    private let rasterResult: GEClassicRasterResultV5
    private let texturedReplayResult: GETexturedReplayResultV3
    private let decodedResults: [GETextureDecodeResultV3]

    private var replayEvidence: ReplayEvidence
    private var drawRanges: [DrawRange] = []
    private var vertexBuffer: (any MTLBuffer)?
    private var indexBuffer: (any MTLBuffer)?
    private var transientBuffer: (any MTLBuffer)?
    private var indexBufferLength = 0
    private var textureUploads: [UInt32: TextureUpload] = [:]
    private var sampler: (any MTLSamplerState)?
    private var pendingStagingRetirement: [PendingStagingRetirement] = []
    private var depthTextures: [String: any MTLTexture] = [:]
    private var retiredDepthTextures: [(signalValue: UInt64, texture: any MTLTexture)] = []
    private var uploadPending = true

    private var frameIndex = 0
    private var nextSignalValue: UInt64 = 1
    private var lastSignalBySlot: [UInt64] = [0, 0]
    private var renderedFrames = 0
    private var renderedDraws = 0

    init(
        state: GoldenEyeMetalDeviceState,
        layer: CAMetalLayer,
        pipeline: GoldenEyeClassicCombinerPropPipeline,
        loweringResult: GEClassicCombinerLoweringResultV4,
        rasterResult: GEClassicRasterResultV5,
        texturedReplayResult: GETexturedReplayResultV3,
        decodedTextures: [GETextureDecodeResultV3]
    ) throws {
        guard loweringResult.status == GE_STATUS_OK else {
            throw GoldenEyeClassicCombinerPropRendererError.loweringFailed(loweringResult.status)
        }
        guard texturedReplayResult.status == GE_STATUS_OK else {
            throw GoldenEyeClassicCombinerPropRendererError.replayFailed(texturedReplayResult.status)
        }
        guard rasterResult.status == GE_STATUS_OK,
              rasterResult.state_count == GE_CLASSIC_RASTER_MODE_CAPACITY else {
            throw GoldenEyeClassicCombinerPropRendererError.loweringFailed(rasterResult.status)
        }
        self.state = state
        self.layer = layer
        self.pipeline = pipeline
        self.loweringResult = loweringResult
        self.rasterResult = rasterResult
        self.texturedReplayResult = texturedReplayResult
        self.decodedResults = decodedTextures
        self.replayEvidence = ReplayEvidence(
            loweringStatus: loweringResult.status,
            replayStatus: texturedReplayResult.status,
            commandsProcessed: loweringResult.commands_processed,
            setupCommandsProcessed: loweringResult.setup_commands_processed,
            replayCommandsProcessed: texturedReplayResult.commands_processed,
            drawCount: loweringResult.draw_count,
            vertexCount: texturedReplayResult.vertex_count,
            triangleCount: texturedReplayResult.triangle_count,
            setupHash: loweringResult.setup_hash,
            eventHash: loweringResult.event_hash,
            keyHash: loweringResult.key_hash,
            packetHash: texturedReplayResult.packet_hash,
            replayEventHash: texturedReplayResult.event_hash,
            materialHash: texturedReplayResult.material_hash
        )
        try self.prepareReplayAndResources()
    }

    /// Convenience seam for the owner integration.  Both C entry points take
    /// fixed records by value; the renderer copies every result before Metal
    /// resource creation and never retains a caller-owned pointer or graph.
    convenience init(
        state: GoldenEyeMetalDeviceState,
        layer: CAMetalLayer,
        pipeline: GoldenEyeClassicCombinerPropPipeline,
        propBlob: GEClassicAssetBlobV2,
        materials: GETextureMaterialSetV3,
        textureBlobs: [GETextureSourceBlobV3]
    ) throws {
        let texturedReplay = ge_classic_replay_textured_prop_v3(propBlob, materials)
        let lowering = ge_classic_lower_ammo_crate_v4(propBlob)
        let raster = ge_classic_lower_ammo_crate_raster_v5()
        let decoded = textureBlobs.map { ge_texture_decode_v3($0) }
        try self.init(
            state: state,
            layer: layer,
            pipeline: pipeline,
            loweringResult: lowering,
            rasterResult: raster,
            texturedReplayResult: texturedReplay,
            decodedTextures: decoded
        )
    }

    private static func tupleBytes<T>(_ value: T) -> [UInt8] {
        withUnsafeBytes(of: value) { Array($0) }
    }

    private static func tupleWords<T>(_ value: T) -> [UInt32] {
        withUnsafeBytes(of: value) { rawBytes in
            Array(rawBytes.bindMemory(to: UInt32.self))
        }
    }

    private static func copiedDrawKeys(
        from result: GEClassicCombinerLoweringResultV4
    ) throws -> [GEClassicCombinerDrawKeyV4] {
        let stride = MemoryLayout<GEClassicCombinerDrawKeyV4>.stride
        return try withUnsafeBytes(of: result.draws) { rawBytes in
            guard stride > 0, rawBytes.count % stride == 0 else {
                throw GoldenEyeClassicCombinerPropRendererError.malformedLowering("draw-key tuple stride")
            }
            let capacity = rawBytes.count / stride
            let requested = Int(result.draw_count)
            guard requested <= capacity else {
                throw GoldenEyeClassicCombinerPropRendererError.malformedLowering(
                    "draw count \(requested) > \(capacity)"
                )
            }
            let typed = rawBytes.bindMemory(to: GEClassicCombinerDrawKeyV4.self)
            return Array(typed.prefix(requested))
        }
    }

    private static func copiedTexturedDraws(
        from result: GETexturedReplayResultV3
    ) throws -> [GETexturedDrawPacketV3] {
        let stride = MemoryLayout<GETexturedDrawPacketV3>.stride
        return try withUnsafeBytes(of: result.draws) { rawBytes in
            guard stride > 0, rawBytes.count % stride == 0 else {
                throw GoldenEyeClassicCombinerPropRendererError.malformedReplay("draw tuple stride")
            }
            let capacity = rawBytes.count / stride
            let requested = Int(result.draw_count)
            guard requested <= capacity else {
                throw GoldenEyeClassicCombinerPropRendererError.malformedReplay(
                    "draw count \(requested) > \(capacity)"
                )
            }
            let typed = rawBytes.bindMemory(to: GETexturedDrawPacketV3.self)
            return Array(typed.prefix(requested))
        }
    }

    private static func copiedRasterStates(
        from result: GEClassicRasterResultV5
    ) throws -> [GEClassicRasterStateV5] {
        let stride = MemoryLayout<GEClassicRasterStateV5>.stride
        return try withUnsafeBytes(of: result.states) { rawBytes in
            guard stride > 0, rawBytes.count % stride == 0 else {
                throw GoldenEyeClassicCombinerPropRendererError.malformedLowering(
                    "raster-state tuple stride"
                )
            }
            let capacity = rawBytes.count / stride
            let requested = Int(result.state_count)
            guard requested <= capacity else {
                throw GoldenEyeClassicCombinerPropRendererError.malformedLowering(
                    "raster state count \(requested) > \(capacity)"
                )
            }
            let typed = rawBytes.bindMemory(to: GEClassicRasterStateV5.self)
            return Array(typed.prefix(requested))
        }
    }

    private static func copiedVertices(
        from packet: GETexturedDrawPacketV3
    ) throws -> [GETexturedVertexV3] {
        let stride = MemoryLayout<GETexturedVertexV3>.stride
        return try withUnsafeBytes(of: packet.vertices) { rawBytes in
            guard stride > 0, rawBytes.count % stride == 0 else {
                throw GoldenEyeClassicCombinerPropRendererError.malformedReplay("vertex tuple stride")
            }
            let capacity = rawBytes.count / stride
            let requested = Int(packet.vertex_count)
            guard requested <= capacity else {
                throw GoldenEyeClassicCombinerPropRendererError.malformedReplay(
                    "vertex count \(requested) > \(capacity)"
                )
            }
            let typed = rawBytes.bindMemory(to: GETexturedVertexV3.self)
            return Array(typed.prefix(requested))
        }
    }

    private static func copiedTriangles(
        from packet: GETexturedDrawPacketV3
    ) throws -> [GEClassicTriangleV2] {
        let stride = MemoryLayout<GEClassicTriangleV2>.stride
        return try withUnsafeBytes(of: packet.triangles) { rawBytes in
            guard stride > 0, rawBytes.count % stride == 0 else {
                throw GoldenEyeClassicCombinerPropRendererError.malformedReplay("triangle tuple stride")
            }
            let capacity = rawBytes.count / stride
            let requested = Int(packet.triangle_count)
            guard requested <= capacity else {
                throw GoldenEyeClassicCombinerPropRendererError.malformedReplay(
                    "triangle count \(requested) > \(capacity)"
                )
            }
            let typed = rawBytes.bindMemory(to: GEClassicTriangleV2.self)
            return Array(typed.prefix(requested))
        }
    }

    private static func sharedBuffer<T>(
        device: any MTLDevice,
        values: inout [T],
        label: String
    ) -> (any MTLBuffer)? {
        guard !values.isEmpty else { return nil }
        let buffer = values.withUnsafeBytes { rawBytes -> (any MTLBuffer)? in
            guard let baseAddress = rawBytes.baseAddress, !rawBytes.isEmpty else { return nil }
            return device.makeBuffer(bytes: baseAddress, length: rawBytes.count, options: .storageModeShared)
        }
        buffer?.label = label
        return buffer
    }

    private static func rgbaPixels(
        from result: GETextureDecodeResultV3
    ) throws -> [UInt8] {
        guard result.status == GE_STATUS_OK else {
            throw GoldenEyeClassicCombinerPropRendererError.malformedTexture(
                "texture \(result.texture_id) decode status \(result.status)"
            )
        }
        let width = Int(result.width)
        let height = Int(result.height)
        guard width > 0, height > 0 else {
            throw GoldenEyeClassicCombinerPropRendererError.malformedTexture(
                "texture \(result.texture_id) dimensions"
            )
        }
        let count = width.multipliedReportingOverflow(by: height)
        guard !count.overflow, count.partialValue > 0 else {
            throw GoldenEyeClassicCombinerPropRendererError.malformedTexture(
                "texture \(result.texture_id) dimensions overflow"
            )
        }
        let resultBytes = Self.tupleBytes(result)
        guard resultBytes.count == Self.decodedResultSize else {
            throw GoldenEyeClassicCombinerPropRendererError.malformedTexture(
                "texture \(result.texture_id) record size \(resultBytes.count)"
            )
        }
        let pixels = Array(resultBytes[Self.decodedResultPixelsOffset..<Self.decodedResultSize])
        let offsets = Self.tupleWords(result.mip_offsets)
        let mipCount = min(Int(result.mip_count), offsets.count)
        let baseOffset = mipCount > 0 ? Int(offsets[0]) : 0
        let declared = Int(result.pixel_byte_count)
        let nextOffset = mipCount > 1 ? Int(offsets[1]) : declared
        let required = count.partialValue * 4
        guard baseOffset >= 0, nextOffset >= baseOffset,
              nextOffset <= pixels.count, nextOffset - baseOffset >= required else {
            throw GoldenEyeClassicCombinerPropRendererError.malformedTexture(
                "texture \(result.texture_id) normalized RGBA8 mip range"
            )
        }
        return Array(pixels[baseOffset..<(baseOffset + required)])
    }

    private static func renderModeKey(for rawMode: UInt32) throws -> UInt32 {
        switch rawMode {
        case GoldenEyeClassicCombinerPropPipeline.opaqueRenderMode,
             GoldenEyeClassicCombinerPropPipeline.authoredRenderMode:
            return rawMode
        default:
            throw GoldenEyeClassicCombinerPropRendererError.malformedLowering(
                "unsupported render mode 0x\(String(rawMode, radix: 16))"
            )
        }
    }

    private func prepareReplayAndResources() throws {
        guard loweringResult.draw_count == 4,
              texturedReplayResult.draw_count == 4 else {
            throw GoldenEyeClassicCombinerPropRendererError.malformedLowering(
                "expected four V4/V3 draw groups"
            )
        }
        let keys = try Self.copiedDrawKeys(from: loweringResult)
        let packets = try Self.copiedTexturedDraws(from: texturedReplayResult)
        let rasterStates = try Self.copiedRasterStates(from: rasterResult)
        var rasterByMode: [UInt32: GEClassicRasterStateV5] = [:]
        for raster in rasterStates {
            guard raster.header.abi_version == GE_CLASSIC_RASTER_ABI_VERSION,
                  raster.header.struct_size == UInt32(MemoryLayout<GEClassicRasterStateV5>.size),
                  rasterByMode[raster.raw_render_mode] == nil else {
                throw GoldenEyeClassicCombinerPropRendererError.malformedLowering(
                    "duplicate or invalid M9 raster state"
                )
            }
            rasterByMode[raster.raw_render_mode] = raster
        }
        guard keys.count == packets.count else {
            throw GoldenEyeClassicCombinerPropRendererError.malformedLowering(
                "V4/V3 draw count mismatch"
            )
        }

        var keysByCommand: [UInt32: GEClassicCombinerDrawKeyV4] = [:]
        for key in keys {
            guard key.header.abi_version == GE_NATIVE_ABI_VERSION,
                  key.header.struct_size == UInt32(MemoryLayout<GEClassicCombinerDrawKeyV4>.size),
                  key.packet_version == GE_CLASSIC_COMBINER_PACKET_VERSION,
                  keysByCommand[key.source_command_offset] == nil else {
                throw GoldenEyeClassicCombinerPropRendererError.malformedLowering(
                    "duplicate or invalid V4 draw key"
                )
            }
            _ = try Self.renderModeKey(for: key.render_mode.raw_mode)
            guard key.combiner.raw_w0 == 0xFC26A004,
                  key.combiner.raw_w1 == 0x1F1093FF else {
                throw GoldenEyeClassicCombinerPropRendererError.malformedLowering(
                    "unsupported V4 combiner words"
                )
            }
            keysByCommand[key.source_command_offset] = key
        }

        var vertices: [GPUVertex] = []
        var indices: [UInt32] = []
        var transient: [GPUTransient] = []
        var ranges: [DrawRange] = []
        vertices.reserveCapacity(Int(texturedReplayResult.vertex_count))
        indices.reserveCapacity(Int(texturedReplayResult.triangle_count) * 3)
        transient.reserveCapacity(packets.count)
        ranges.reserveCapacity(packets.count)

        for (packetIndex, packet) in packets.enumerated() {
            guard let key = keysByCommand[packet.source_command_offset] else {
                throw GoldenEyeClassicCombinerPropRendererError.malformedLowering(
                    "no V4 key for V3 command offset \(packet.source_command_offset)"
                )
            }
            let packetVertices = try Self.copiedVertices(from: packet)
            let packetTriangles = try Self.copiedTriangles(from: packet)
            guard !packetVertices.isEmpty, !packetTriangles.isEmpty,
                  key.texture_id == packet.texture_id else {
                throw GoldenEyeClassicCombinerPropRendererError.malformedReplay(
                    "V4/V3 packet \(packetIndex) correlation"
                )
            }

            let vertexOffset = vertices.count
            let indexOffset = indices.count
            let transientIndex = transient.count
            for vertex in packetVertices {
                vertices.append(
                    GPUVertex(
                        position: SIMD4<Float>(vertex.x, vertex.y, vertex.z, vertex.w),
                        texcoord: SIMD2<Float>(vertex.s, vertex.t),
                        color: SIMD4<Float>(
                            Float(vertex.r) / 255.0,
                            Float(vertex.g) / 255.0,
                            Float(vertex.b) / 255.0,
                            Float(vertex.a) / 255.0
                        )
                    )
                )
            }
            for triangle in packetTriangles {
                let a = Int(triangle.a)
                let b = Int(triangle.b)
                let c = Int(triangle.c)
                guard a >= 0, b >= 0, c >= 0,
                      a < packetVertices.count, b < packetVertices.count,
                      c < packetVertices.count else {
                    throw GoldenEyeClassicCombinerPropRendererError.malformedReplay(
                        "packet \(packetIndex) triangle index"
                    )
                }
                indices.append(UInt32(a))
                indices.append(UInt32(b))
                indices.append(UInt32(c))
            }

            let rawRenderMode = key.render_mode.raw_mode
            guard let raster = rasterByMode[rawRenderMode] else {
                throw GoldenEyeClassicCombinerPropRendererError.malformedLowering(
                    "no M9 raster state for render mode 0x\(String(rawRenderMode, radix: 16))"
                )
            }
            let stateHash = key.key_hash
            transient.append(
                GPUTransient(
                    textureID: key.texture_id,
                    materialFlags: key.material_flags,
                    sourceCommandOffset: key.source_command_offset,
                    combinerKey: UInt32(truncatingIfNeeded: stateHash),
                    renderModeKey: rawRenderMode,
                    otherModeH: key.other_mode.raw_h,
                    otherModeL: key.other_mode.raw_l,
                    combineW0: key.combiner.raw_w0,
                    combineW1: key.combiner.raw_w1,
                    combinerFlags: key.combiner.selector_flags,
                    renderModeFlags: key.render_mode.deferred_flags,
                    stateHashLow: UInt32(truncatingIfNeeded: stateHash),
                    stateHashHigh: UInt32(truncatingIfNeeded: stateHash >> 32),
                    reserved0: UInt32(packetIndex),
                    reserved1: key.render_mode.aa_enable,
                    reserved2: key.render_mode.z_compare,
                    alphaCompare: raster.alpha_compare,
                    alphaPolicy: raster.alpha_policy,
                    alphaThresholdQ8: raster.alpha_threshold_q8,
                    fogEnabled: raster.fog_enable,
                    fogColorRGBA8: raster.fog_color_rgba8,
                    fogAlphaQ8: raster.fog_alpha_q8,
                    coverageFlags: raster.clear_on_coverage |
                        (raster.coverage_x_alpha << 1) |
                        (raster.alpha_coverage_select << 2) |
                        (raster.coverage_destination << 8)
                )
            )
            ranges.append(
                DrawRange(
                    indexOffset: indexOffset,
                    indexCount: packetTriangles.count * 3,
                    vertexOffset: vertexOffset,
                    transientIndex: transientIndex,
                    textureID: key.texture_id,
                    sourceCommandOffset: key.source_command_offset,
                    rawRenderMode: rawRenderMode,
                    keyHash: stateHash
                )
            )
        }

        guard !vertices.isEmpty, !indices.isEmpty, !transient.isEmpty, !ranges.isEmpty else {
            throw GoldenEyeClassicCombinerPropRendererError.emptyReplay
        }
        guard let vertexBuffer = Self.sharedBuffer(
            device: state.device,
            values: &vertices,
            label: "GoldenEye.M12.ClassicCombiner.VertexBuffer"
        ) else {
            throw GoldenEyeClassicCombinerPropRendererError.bufferCreationFailed("vertex buffer")
        }
        guard let indexBuffer = Self.sharedBuffer(
            device: state.device,
            values: &indices,
            label: "GoldenEye.M12.ClassicCombiner.IndexBuffer"
        ) else {
            throw GoldenEyeClassicCombinerPropRendererError.bufferCreationFailed("index buffer")
        }
        guard let transientBuffer = Self.sharedBuffer(
            device: state.device,
            values: &transient,
            label: "GoldenEye.M12.ClassicCombiner.TransientBuffer"
        ) else {
            throw GoldenEyeClassicCombinerPropRendererError.bufferCreationFailed("transient buffer")
        }

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.label = "GoldenEye.M12.ClassicCombiner.NearestSampler"
        samplerDescriptor.minFilter = .nearest
        samplerDescriptor.magFilter = .nearest
        samplerDescriptor.mipFilter = .notMipmapped
        samplerDescriptor.sAddressMode = .repeat
        samplerDescriptor.tAddressMode = .repeat
        samplerDescriptor.normalizedCoordinates = true
        samplerDescriptor.supportArgumentBuffers = true
        guard let sampler = state.device.makeSamplerState(descriptor: samplerDescriptor) else {
            throw GoldenEyeClassicCombinerPropRendererError.samplerCreationFailed
        }

        var uploads: [UInt32: TextureUpload] = [:]
        for result in decodedResults {
            guard uploads[result.texture_id] == nil else {
                throw GoldenEyeClassicCombinerPropRendererError.malformedTexture(
                    "duplicate texture ID \(result.texture_id)"
                )
            }
            let width = Int(result.width)
            let height = Int(result.height)
            let rgba = try Self.rgbaPixels(from: result)
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: width,
                height: height,
                mipmapped: false
            )
            descriptor.storageMode = .private
            descriptor.usage = .shaderRead
            guard let texture = state.device.makeTexture(descriptor: descriptor) else {
                throw GoldenEyeClassicCombinerPropRendererError.textureCreationFailed(result.texture_id)
            }
            texture.label = "GoldenEye.M12.ClassicCombiner.Texture.\(result.texture_id)"
            let staging = rgba.withUnsafeBytes { rawBytes -> (any MTLBuffer)? in
                guard let baseAddress = rawBytes.baseAddress else { return nil }
                return state.device.makeBuffer(
                    bytes: baseAddress,
                    length: rawBytes.count,
                    options: .storageModeShared
                )
            }
            guard let staging else {
                throw GoldenEyeClassicCombinerPropRendererError.bufferCreationFailed(
                    "texture \(result.texture_id) staging"
                )
            }
            staging.label = "GoldenEye.M12.ClassicCombiner.Staging.\(result.texture_id)"
            uploads[result.texture_id] = TextureUpload(
                texture: texture,
                staging: staging,
                width: width,
                height: height,
                sourceHash: result.source_hash,
                decodedHash: result.decoded_hash
            )
        }
        for range in ranges {
            guard uploads[range.textureID] != nil else {
                throw GoldenEyeClassicCombinerPropRendererError.missingTexture(range.textureID)
            }
        }

        state.sceneResidency.addAllocation(vertexBuffer)
        state.sceneResidency.addAllocation(indexBuffer)
        state.sceneResidency.addAllocation(transientBuffer)
        for textureID in uploads.keys.sorted() {
            guard let upload = uploads[textureID] else { continue }
            state.sceneResidency.addAllocation(upload.texture)
            state.sceneResidency.addAllocation(upload.staging)
        }
        state.sceneResidency.commit()

        state.argumentTable.setAddress(vertexBuffer.gpuAddress, index: 0)
        state.argumentTable.setAddress(indexBuffer.gpuAddress, index: 1)
        state.argumentTable.setAddress(transientBuffer.gpuAddress, index: 2)
        state.argumentTable.setSamplerState(sampler.gpuResourceID, index: 0)

        self.vertexBuffer = vertexBuffer
        self.indexBuffer = indexBuffer
        self.transientBuffer = transientBuffer
        self.indexBufferLength = indices.count * MemoryLayout<UInt32>.stride
        self.drawRanges = ranges
        self.textureUploads = uploads
        self.sampler = sampler
    }

    private func retireCompletedStaging() {
        let completedValue = state.completionEvent.signaledValue
        var didRemove = false
        pendingStagingRetirement.removeAll { pending in
            guard completedValue >= pending.signalValue else { return false }
            state.sceneResidency.removeAllocation(pending.buffer)
            didRemove = true
            return true
        }
        if didRemove {
            state.sceneResidency.commit()
        }
    }

    private func retireCompletedDepthTextures() {
        let completedValue = state.completionEvent.signaledValue
        var didRemove = false
        retiredDepthTextures.removeAll { pending in
            guard completedValue >= pending.signalValue else { return false }
            state.sceneResidency.removeAllocation(pending.texture)
            didRemove = true
            return true
        }
        if didRemove {
            state.sceneResidency.commit()
        }
    }

    private func depthTexture(for drawable: any CAMetalDrawable) throws -> any MTLTexture {
        let key = "\(drawable.texture.width)x\(drawable.texture.height)"
        if let existing = depthTextures[key] {
            return existing
        }
        // A resize can leave an older depth attachment referenced by either
        // reusable frame slot. Retire it behind the largest submitted signal
        // instead of removing residency while the GPU may still test it.
        let retirementSignal = lastSignalBySlot.max() ?? 0
        for oldTexture in depthTextures.values {
            if retirementSignal == 0 {
                state.sceneResidency.removeAllocation(oldTexture)
            } else {
                retiredDepthTextures.append((signalValue: retirementSignal, texture: oldTexture))
            }
        }
        if !depthTextures.isEmpty {
            depthTextures.removeAll(keepingCapacity: true)
            state.sceneResidency.commit()
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: drawable.texture.width,
            height: drawable.texture.height,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget]
        guard let texture = state.device.makeTexture(descriptor: descriptor) else {
            throw GoldenEyeClassicCombinerPropRendererError.textureCreationFailed(0)
        }
        texture.label = "GoldenEye.M9.ClassicCombiner.Depth.\(key)"
        state.sceneResidency.addAllocation(texture)
        state.sceneResidency.commit()
        depthTextures[key] = texture
        return texture
    }

    private func encodePendingTextureUploads(
        on commandBuffer: any MTL4CommandBuffer
    ) throws {
        guard uploadPending else { return }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw GoldenEyeClassicCombinerPropRendererError.computeEncoderUnavailable
        }
        encoder.label = "GoldenEye.M12.ClassicCombiner.TextureUploadCompute"
        for textureID in textureUploads.keys.sorted() {
            guard let upload = textureUploads[textureID] else { continue }
            encoder.copy(
                sourceBuffer: upload.staging,
                sourceOffset: 0,
                sourceBytesPerRow: upload.width * 4,
                sourceBytesPerImage: 0,
                sourceSize: MTLSize(width: upload.width, height: upload.height, depth: 1),
                destinationTexture: upload.texture,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
            )
        }
        encoder.barrier(
            afterStages: .blit,
            beforeQueueStages: [.vertex, .fragment],
            visibilityOptions: .device
        )
        encoder.endEncoding()
    }

    func renderFrame() -> Bool {
        guard let vertexBuffer, let indexBuffer, transientBuffer != nil, sampler != nil else {
            return false
        }
        retireCompletedStaging()
        retireCompletedDepthTextures()

        let slotIndex = frameIndex % state.frameSlots.count
        let slot = state.frameSlots[slotIndex]
        let priorSignal = lastSignalBySlot[slotIndex]
        if priorSignal != 0 {
            guard state.completionEvent.wait(untilSignaledValue: priorSignal, timeoutMS: 1_000) else {
                print("GoldenEye classic combiner timed out waiting for slot \(slotIndex)")
                return false
            }
            retireCompletedStaging()
        }
        guard let drawable = layer.nextDrawable() else {
            print("GoldenEye classic combiner failed to acquire drawable")
            return false
        }

        slot.allocator.reset()
        slot.commandBuffer.beginCommandBuffer(allocator: slot.allocator)
        slot.commandBuffer.useResidencySet(state.sceneResidency)
        slot.commandBuffer.useResidencySet(state.layerResidency)
        slot.commandBuffer.pushDebugGroup("GoldenEye.M12.ClassicCombiner.Frame.\(frameIndex)")

        do {
            let depthTexture = try self.depthTexture(for: drawable)
            let uploadWasPending = uploadPending
            try encodePendingTextureUploads(on: slot.commandBuffer)

            let pass = MTL4RenderPassDescriptor()
            pass.colorAttachments[0].texture = drawable.texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1.0)
            pass.depthAttachment.texture = depthTexture
            pass.depthAttachment.loadAction = .clear
            pass.depthAttachment.storeAction = .dontCare
            pass.depthAttachment.clearDepth = 1.0
            guard let encoder = slot.commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
                throw GoldenEyeClassicCombinerPropRendererError.pipelineCreationFailed("render encoder")
            }
            encoder.label = "GoldenEye.M12.ClassicCombiner.RenderEncoder"
            if uploadWasPending {
                encoder.barrier(
                    afterQueueStages: .blit,
                    beforeStages: [.vertex, .fragment],
                    visibilityOptions: .device
                )
            }

            for (drawIndex, range) in drawRanges.enumerated() {
                guard let upload = textureUploads[range.textureID] else {
                    encoder.endEncoding()
                    throw GoldenEyeClassicCombinerPropRendererError.missingTexture(range.textureID)
                }
                let pipelineState = try pipeline.pipeline(for: range.rawRenderMode)
                encoder.setRenderPipelineState(pipelineState)
                encoder.setDepthStencilState(try pipeline.depthState(for: range.rawRenderMode))
                state.argumentTable.setTexture(upload.texture.gpuResourceID, index: 0)
                encoder.setArgumentTable(state.argumentTable, stages: [.vertex, .fragment])

                let byteOffset = range.indexOffset * MemoryLayout<UInt32>.stride
                let remainingIndexBytes = self.indexBufferLength - byteOffset
                guard byteOffset >= 0,
                      remainingIndexBytes >= range.indexCount * MemoryLayout<UInt32>.stride else {
                    encoder.endEncoding()
                    throw GoldenEyeClassicCombinerPropRendererError.malformedReplay(
                        "draw \(drawIndex) index range escaped index buffer"
                    )
                }
                encoder.pushDebugGroup(
                    "GoldenEye.M12.ClassicCombiner.Draw.\(drawIndex).Texture.\(range.textureID).Command.\(range.sourceCommandOffset).Mode.0x\(String(range.rawRenderMode, radix: 16)).Key.\(range.keyHash)"
                )
                encoder.drawIndexedPrimitives(
                    primitiveType: .triangle,
                    indexCount: range.indexCount,
                    indexType: .uint32,
                    indexBuffer: indexBuffer.gpuAddress + UInt64(byteOffset),
                    indexBufferLength: remainingIndexBytes,
                    instanceCount: 1,
                    baseVertex: range.vertexOffset,
                    baseInstance: range.transientIndex
                )
                encoder.popDebugGroup()
                renderedDraws += 1
            }
            encoder.endEncoding()
            slot.commandBuffer.popDebugGroup()
            slot.commandBuffer.endCommandBuffer()
        } catch {
            slot.commandBuffer.popDebugGroup()
            slot.commandBuffer.endCommandBuffer()
            print("GoldenEye classic combiner encoding failed: \(error)")
            return false
        }

        state.queue.waitForDrawable(drawable)
        state.queue.commit([slot.commandBuffer])
        let signalValue = nextSignalValue
        nextSignalValue &+= 1
        if uploadPending {
            uploadPending = false
            pendingStagingRetirement.append(contentsOf: textureUploads.values.map { upload in
                PendingStagingRetirement(signalValue: signalValue, buffer: upload.staging)
            })
        }
        state.queue.signalEvent(state.completionEvent, value: signalValue)
        state.queue.signalDrawable(drawable)
        drawable.present()
        lastSignalBySlot[slotIndex] = signalValue
        frameIndex += 1
        renderedFrames += 1
        if state.captureActive {
            state.stopCapture()
        }
        _ = vertexBuffer
        return true
    }

    func shutdown() {
        for value in lastSignalBySlot where value != 0 {
            _ = state.completionEvent.wait(untilSignaledValue: value, timeoutMS: 2_000)
        }
        retireCompletedStaging()
        retireCompletedDepthTextures()
        if !pendingStagingRetirement.isEmpty {
            for pending in pendingStagingRetirement {
                state.sceneResidency.removeAllocation(pending.buffer)
            }
            state.sceneResidency.commit()
            pendingStagingRetirement.removeAll()
        }
        let depthVariantCount = depthTextures.count + retiredDepthTextures.count
        let finalSignal = lastSignalBySlot.max() ?? 0
        if finalSignal != 0 {
            retiredDepthTextures.append(contentsOf: depthTextures.values.map {
                (signalValue: finalSignal, texture: $0)
            })
            depthTextures.removeAll(keepingCapacity: false)
            _ = state.completionEvent.wait(untilSignaledValue: finalSignal, timeoutMS: 2_000)
            retireCompletedDepthTextures()
        }

        let textureEvidence = textureUploads.keys.sorted().compactMap { textureID in
            guard let upload = textureUploads[textureID] else { return nil }
            return "id=\(textureID),size=\(upload.width)x\(upload.height),sourceHash=\(upload.sourceHash),decodedHash=\(upload.decodedHash)"
        }.joined(separator: ";")
        let evidence = "status=\(replayEvidence.replayStatus) loweringStatus=\(replayEvidence.loweringStatus) replayStatus=\(replayEvidence.replayStatus) commands=\(replayEvidence.replayCommandsProcessed) propCommands=\(replayEvidence.commandsProcessed) setupCommands=\(replayEvidence.setupCommandsProcessed) drawPackets=\(replayEvidence.drawCount) vertices=\(replayEvidence.vertexCount) triangles=\(replayEvidence.triangleCount) setupHash=\(replayEvidence.setupHash) eventHash=\(replayEvidence.eventHash) keyHash=\(replayEvidence.keyHash) packetHash=\(replayEvidence.packetHash) replayEventHash=\(replayEvidence.replayEventHash) materialHash=\(replayEvidence.materialHash) textures=\(textureEvidence) depthTextures=\(depthVariantCount) frames=\(renderedFrames) draws=\(renderedDraws) uploadsPending=\(uploadPending) lastSignal=\(nextSignalValue - 1) resourceAllocations=\(state.sceneResidency.allocationCount)\n"
        try? evidence.write(
            toFile: "/tmp/goldeneye-classic-combiner.log",
            atomically: true,
            encoding: .utf8
        )
    }
}
