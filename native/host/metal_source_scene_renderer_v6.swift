#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif
import CryptoKit
import Foundation
import Metal
import QuartzCore
import simd

enum GoldenEyeSourceSceneRendererV6Error: Error, CustomStringConvertible {
    case invalidState(String)
    case unsupportedCommand(UInt32)
    case unsupportedVisibleDiagnostics(UInt32)
    case missingRenderState(UInt32)
    case missingTexture(UInt32)
    case nonTextureResource(UInt32)
    case unsupportedTextureState(UInt32, String)
    case missingTransform(UInt32)
    case capacityExceeded(String)
    case slotTimeout(Int)
    case depthTextureUnavailable
    case encoderUnavailable
    case invalidScissor(UInt32)
    case missingLightingContext(UInt32)
    case missingLightingState(UInt32)
    case missingFogCoordinate(UInt32)
    case unsupportedFogBinding(UInt32, UInt32)
    case referenceTargetRequired
    case referenceTargetUnavailable
    case referenceReadbackUnavailable
    case invalidReferenceCaptureURL(URL)
    case layoutMismatch(String)

    var description: String {
        switch self {
        case .invalidState(let detail): return "invalid V6 source-scene renderer state: \(detail)"
        case .unsupportedCommand(let kind): return "unsupported V6 source draw command kind \(kind)"
        case .unsupportedVisibleDiagnostics(let count):
            return "V6 source frame has \(count) unsupported visible command(s)"
        case .missingRenderState(let handle): return "missing V6 render-state handle \(handle)"
        case .missingTexture(let handle): return "missing V6 source texture handle \(handle)"
        case .nonTextureResource(let handle): return "V6 draw resource \(handle) is not a texture"
        case .unsupportedTextureState(let handle, let detail):
            return "unsupported V6 texture state for resource \(handle): \(detail)"
        case .missingTransform(let handle): return "missing V6 transform handle \(handle)"
        case .capacityExceeded(let detail): return "V6 source-scene frame capacity exceeded: \(detail)"
        case .slotTimeout(let index): return "timed out waiting for V6 frame slot \(index)"
        case .depthTextureUnavailable: return "V6 source-scene depth texture unavailable"
        case .encoderUnavailable: return "V6 source-scene render encoder unavailable"
        case .invalidScissor(let handle): return "invalid V6 source scissor for draw \(handle)"
        case .missingLightingContext(let handle):
            return "missing source-local lighting context for draw \(handle)"
        case .missingLightingState(let handle):
            return "missing decoded GBI lighting state for render state \(handle)"
        case .missingFogCoordinate(let stageID):
            return "stage \(stageID) fog requires the copied source-symmetric coordinate array"
        case .unsupportedFogBinding(let stageID, let reason):
            return "stage \(stageID) fog binding remains unsupported (reason=\(reason))"
        case .referenceTargetRequired:
            return "Reference 320x240 requires an explicit offscreen target; supplied drawable was not used"
        case .referenceTargetUnavailable:
            return "Reference 320x240 offscreen render target unavailable"
        case .referenceReadbackUnavailable:
            return "Reference 320x240 readback buffer unavailable"
        case .invalidReferenceCaptureURL(let url):
            return "Reference 320x240 capture must remain beneath build/native: \(url.path)"
        case .layoutMismatch(let detail): return "V6 source-scene GPU layout mismatch: \(detail)"
        }
    }
}

struct GoldenEyeSourceSceneRenderEvidenceV6: Sendable {
    let frameIndex: UInt64
    let nativeTick: UInt64
    /// The number of source draw commands retained in the CPU manifest.  This
    /// remains the historical ``drawCount`` value so existing screen evidence
    /// continues to describe source work, even when contiguous commands share
    /// one Metal indexed draw.
    let drawCount: Int
    /// Number of actual Metal indexed draws emitted after the typed batching
    /// plan.  It may be lower than ``drawCount`` only for contiguous commands
    /// with an identical complete render key.
    let metalDrawCount: Int
    let triangleCount: Int
    let copiedRecordAggregateHash: UInt64
    let pipelineKeyHashes: [UInt64]
    let sourceManifestHash: UInt64
    let batchManifestHash: UInt64
    let cpuEncodeNanoseconds: UInt64
    let slotIndex: Int
    let signalValue: UInt64

    init(
        frameIndex: UInt64,
        nativeTick: UInt64,
        drawCount: Int,
        triangleCount: Int,
        copiedRecordAggregateHash: UInt64,
        pipelineKeyHashes: [UInt64],
        slotIndex: Int,
        signalValue: UInt64,
        metalDrawCount: Int? = nil,
        sourceManifestHash: UInt64 = 0,
        batchManifestHash: UInt64 = 0,
        cpuEncodeNanoseconds: UInt64 = 0
    ) {
        self.frameIndex = frameIndex
        self.nativeTick = nativeTick
        self.drawCount = drawCount
        self.metalDrawCount = metalDrawCount ?? drawCount
        self.triangleCount = triangleCount
        self.copiedRecordAggregateHash = copiedRecordAggregateHash
        self.pipelineKeyHashes = pipelineKeyHashes
        self.sourceManifestHash = sourceManifestHash
        self.batchManifestHash = batchManifestHash
        self.cpuEncodeNanoseconds = cpuEncodeNanoseconds
        self.slotIndex = slotIndex
        self.signalValue = signalValue
    }
}

/// Bounded readback from the compositor-independent 320x240 target.  The
/// bytes are copied out of a GPU-private BGRA8 texture into a shared buffer;
/// no Metal object or source pointer crosses this evidence boundary.
struct GoldenEyeSourceSceneReferenceCaptureV6: Sendable {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let pixelFormat: String
    let bytes: Data
    let evidence: GoldenEyeSourceSceneRenderEvidenceV6
    let captureURL: URL?
    let pngURL: URL?
    let rawSHA256: String
}

/// Direct Metal 4 lowering for the copied V6 source scene.
///
/// This foundation deliberately accepts only source triangle commands.  It
/// never calls `nextDrawable()`, never creates geometry, text, or a procedural
/// fallback, and throws on every unsupported command kind.  The caller passes
/// the drawable acquired by CAMetalDisplayLink.
@available(macOS 26.0, *)
final class GoldenEyeSourceSceneRendererV6: @unchecked Sendable {
    private struct GPUUniforms {
        var transform: simd_float4x4
        var primitiveColor: SIMD4<Float>
        var environmentColor: SIMD4<Float>
        var cycle0Color: SIMD4<UInt32>
        var cycle0Alpha: SIMD4<UInt32>
        var cycle1Color: SIMD4<UInt32>
        var cycle1Alpha: SIMD4<UInt32>
        var selectors: SIMD4<UInt32>
        var ambientColor: SIMD4<Float>
        var directionalColor: SIMD4<Float>
        var directionalDirection: SIMD4<Float>
        var reflectionRight: SIMD4<Float>
        var reflectionUp: SIMD4<Float>
        var normalTransform: simd_float4x4
        var lightingInfo: SIMD4<UInt32>
        var textureInfo: SIMD4<UInt32>
        var textureLevelDimensions: (SIMD4<UInt32>, SIMD4<UInt32>, SIMD4<UInt32>, SIMD4<UInt32>, SIMD4<UInt32>, SIMD4<UInt32>, SIMD4<UInt32>)
        var fogInfo: SIMD4<UInt32>
        var presentationInfo: SIMD4<Float>
    }

    private final class SlotResources {
        let vertexBuffer: any MTLBuffer
        let indexBuffer: any MTLBuffer
        let uniformBuffer: any MTLBuffer

        init(
            device: any MTLDevice,
            index: Int,
            vertexCapacity: Int,
            indexCapacity: Int,
            uniformCapacity: Int
        ) throws {
            guard let vertexBuffer = device.makeBuffer(
                length: max(64, vertexCapacity * MemoryLayout<GoldenEyeSourceSceneGPUVertexV6>.stride),
                options: .storageModeShared
            ), let indexBuffer = device.makeBuffer(
                length: max(4, indexCapacity * 3 * MemoryLayout<UInt32>.stride),
                options: .storageModeShared
            ), let uniformBuffer = device.makeBuffer(
                length: max(256, uniformCapacity),
                options: .storageModeShared
            ) else {
                throw GoldenEyeSourceSceneRendererV6Error.capacityExceeded("slot \(index) allocation")
            }
            self.vertexBuffer = vertexBuffer
            self.indexBuffer = indexBuffer
            self.uniformBuffer = uniformBuffer
            vertexBuffer.label = "GoldenEye.V6.SourceScene.FrameSlot.\(index).Vertices"
            indexBuffer.label = "GoldenEye.V6.SourceScene.FrameSlot.\(index).Indices"
            uniformBuffer.label = "GoldenEye.V6.SourceScene.FrameSlot.\(index).Uniforms"
        }
    }

    private final class ReferenceSlotResources {
        let target: any MTLTexture
        let depth: any MTLTexture
        let readback: any MTLBuffer

        init(device: any MTLDevice, index: Int) throws {
            let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: 320,
                height: 240,
                mipmapped: false
            )
            targetDescriptor.storageMode = .private
            targetDescriptor.usage = [.renderTarget, .shaderRead]
            guard let target = device.makeTexture(descriptor: targetDescriptor) else {
                throw GoldenEyeSourceSceneRendererV6Error.referenceTargetUnavailable
            }
            target.label = "GoldenEye.V6.SourceScene.Reference320.FrameSlot.\(index).Color"

            let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .depth32Float,
                width: 320,
                height: 240,
                mipmapped: false
            )
            depthDescriptor.storageMode = .memoryless
            depthDescriptor.usage = .renderTarget
            guard let depth = device.makeTexture(descriptor: depthDescriptor) else {
                throw GoldenEyeSourceSceneRendererV6Error.referenceTargetUnavailable
            }
            depth.label = "GoldenEye.V6.SourceScene.Reference320.FrameSlot.\(index).Depth"

            guard let readback = device.makeBuffer(
                length: 320 * 240 * 4,
                options: .storageModeShared
            ) else {
                throw GoldenEyeSourceSceneRendererV6Error.referenceReadbackUnavailable
            }
            readback.label = "GoldenEye.V6.SourceScene.Reference320.FrameSlot.\(index).Readback"
            self.target = target
            self.depth = depth
            self.readback = readback
        }
    }

    private struct PreparedDraw {
        let command: GESourceDrawCommandV6
        let variant: GoldenEyeSourceScenePipelineV6.Variant
        let texture: (any MTLTexture)?
        let textureMetadata: GoldenEyeSourceSceneTextureBindingMetadataV6?
        let hasTexture: Bool
        let uniforms: GPUUniforms
        let scissor: MTLScissorRect
    }

    private let state: GoldenEyeMetalDeviceState
    private let pipeline: GoldenEyeSourceScenePipelineV6
    private let lightingProvider: GoldenEyeSourceSceneLightingProviderV6
    private let textureResolver: (UInt32) -> (any MTLTexture)?
    /// The Release product supplies this plan-backed resolver.  The closure
    /// remains only for older isolated capture smokes; production must use the
    /// strict adapter so no draw can bind a neighboring material or fallback.
    private let textureBindingAdapter: GoldenEyeSourceSceneTextureBindingAdapterV6?
    private let outputMode: GoldenEyeFidelityOutputMode
    private let presentationTreatment: GoldenEyeSourceScenePresentationTreatmentV6
    private let frontFacing: MTLWinding
    private let slotResources: [SlotResources]
    private let referenceSlotResources: [ReferenceSlotResources]
    private let completionEvent: any MTLSharedEvent
    private var lastSignalBySlot: [UInt64]
    private var nextSignalValue: UInt64 = 1
    private var frameIndex: UInt64 = 0
    private var residentTextureHandles: Set<UInt32> = []
    private var depthTextures: [(any MTLTexture)?]
    private let maxVertexCount: Int
    private let maxIndexCount: Int
    private let maxUniformBytes: Int
    /// Consecutive display-link callbacks commonly present the same immutable
    /// snapshot. Cache its fully validated prepared draws and contiguous batch
    /// plan; a new source/camera snapshot replaces the single bounded entry.
    private struct PreparedFrameCacheKey: Hashable {
        let aggregateHash: UInt64
        let nativeTick: UInt64
        let drawCount: Int
        let vertexCount: Int
        let indexCount: Int
        let drawableWidth: Int
        let drawableHeight: Int
    }

    private struct PreparedFrameCacheEntry {
        let key: PreparedFrameCacheKey
        let prepared: [PreparedDraw]
        let batchingPlan: GoldenEyeSourceSceneBatchingPlanV6
    }

    private var preparedFrameCache: PreparedFrameCacheEntry?
    private var preparedFrameCacheHits: UInt64 = 0
    private var preparedFrameCacheMisses: UInt64 = 0

    init(
        state: GoldenEyeMetalDeviceState,
        pipeline: GoldenEyeSourceScenePipelineV6,
        textureResolver: @escaping (UInt32) -> (any MTLTexture)?,
        textureBindingAdapter: GoldenEyeSourceSceneTextureBindingAdapterV6? = nil,
        lightingProvider: GoldenEyeSourceSceneLightingProviderV6 = GoldenEyeSourceSceneLightingProviderV6(),
        maxVertexCount: Int = 65_536,
        maxIndexCount: Int = 65_536,
        maxDrawCount: Int = 2_048,
        outputMode: GoldenEyeFidelityOutputMode = .faithfulHD,
        presentationTreatment: GoldenEyeSourceScenePresentationTreatmentV6 = .sourceFaithful,
        frontFacing: MTLWinding = .counterClockwise
    ) throws {
        guard state.frameSlots.count == 2 else {
            throw GoldenEyeSourceSceneRendererV6Error.invalidState("exactly two frame slots are required")
        }
        guard maxVertexCount > 0, maxIndexCount > 0, maxDrawCount > 0 else {
            throw GoldenEyeSourceSceneRendererV6Error.invalidState("non-positive frame capacity")
        }
        guard MemoryLayout<GoldenEyeSourceSceneGPUVertexV6>.stride == 64 else {
            throw GoldenEyeSourceSceneRendererV6Error.layoutMismatch("GPU vertex stride")
        }
        guard MemoryLayout<GPUUniforms>.stride == 496 else {
            throw GoldenEyeSourceSceneRendererV6Error.layoutMismatch("GPU uniform stride")
        }
        guard let completionEvent = state.device.makeSharedEvent() else {
            throw GoldenEyeSourceSceneRendererV6Error.invalidState("completion event")
        }
        completionEvent.label = "GoldenEye.V6.SourceScene.CompletionEvent"

        self.state = state
        self.pipeline = pipeline
        self.lightingProvider = lightingProvider
        self.textureResolver = textureResolver
        self.textureBindingAdapter = textureBindingAdapter
        self.outputMode = outputMode
        self.presentationTreatment = outputMode == .reference320x240
            ? .sourceFaithful
            : presentationTreatment
        self.frontFacing = frontFacing
        self.completionEvent = completionEvent
        self.maxVertexCount = maxVertexCount
        self.maxIndexCount = maxIndexCount
        self.maxUniformBytes = maxDrawCount * MemoryLayout<GPUUniforms>.stride
        self.lastSignalBySlot = Array(repeating: 0, count: 2)
        self.depthTextures = Array(repeating: nil, count: 2)

        var resources: [SlotResources] = []
        resources.reserveCapacity(2)
        for index in 0..<2 {
            let slot = try SlotResources(
                device: state.device,
                index: index,
                vertexCapacity: maxVertexCount,
                indexCapacity: maxIndexCount,
                uniformCapacity: self.maxUniformBytes
            )
            resources.append(slot)
            state.sceneResidency.addAllocation(slot.vertexBuffer)
            state.sceneResidency.addAllocation(slot.indexBuffer)
            state.sceneResidency.addAllocation(slot.uniformBuffer)
        }
        var referenceResources: [ReferenceSlotResources] = []
        referenceResources.reserveCapacity(2)
        for index in 0..<2 {
            let reference = try ReferenceSlotResources(device: state.device, index: index)
            referenceResources.append(reference)
            state.sceneResidency.addAllocation(reference.target)
            state.sceneResidency.addAllocation(reference.readback)
        }
        state.sceneResidency.commit()
        self.slotResources = resources
        self.referenceSlotResources = referenceResources
    }

    /// Encode and present one already-acquired CAMetalDisplayLink drawable.
    /// No alternate drawable acquisition path exists in this renderer.
    @discardableResult
    func render(
        snapshot: GoldenEyeSourceSceneSnapshotV6,
        suppliedDrawable drawable: any CAMetalDrawable,
        underlay: ((any MTL4RenderCommandEncoder, Int) throws -> Void)? = nil,
        overlay: ((any MTL4RenderCommandEncoder, Int) throws -> Void)? = nil
    ) throws -> GoldenEyeSourceSceneRenderEvidenceV6 {
        guard outputMode != .reference320x240 else {
            throw GoldenEyeSourceSceneRendererV6Error.referenceTargetRequired
        }
        guard snapshot.isPresentable else {
            throw GoldenEyeSourceSceneRendererV6Error.invalidState("frame is not presentable")
        }
        guard snapshot.summary.unsupported_visible_count == 0 else {
            throw GoldenEyeSourceSceneRendererV6Error.unsupportedVisibleDiagnostics(
                snapshot.summary.unsupported_visible_count
            )
        }
        guard snapshot.vertices.count <= maxVertexCount,
              snapshot.indices.count <= maxIndexCount,
              snapshot.drawCommands.count * MemoryLayout<GPUUniforms>.stride <= maxUniformBytes else {
            throw GoldenEyeSourceSceneRendererV6Error.capacityExceeded(
                "vertices=\(snapshot.vertices.count) indices=\(snapshot.indices.count) draws=\(snapshot.drawCommands.count)"
            )
        }

        let outputLayout = GoldenEyeSourceSceneLayoutV6(
            mode: outputMode,
            drawableWidth: drawable.texture.width,
            drawableHeight: drawable.texture.height
        )
        let cacheKey = PreparedFrameCacheKey(
            aggregateHash: snapshot.copiedRecordAggregateHash,
            nativeTick: snapshot.summary.native_tick,
            drawCount: snapshot.drawCommands.count,
            vertexCount: snapshot.vertices.count,
            indexCount: snapshot.indices.count,
            drawableWidth: drawable.texture.width,
            drawableHeight: drawable.texture.height
        )
        let prepareStart = DispatchTime.now().uptimeNanoseconds
        let prepared: [PreparedDraw]
        let preparedPlan: GoldenEyeSourceSceneBatchingPlanV6
        let cacheHit: Bool
        var prepareNanoseconds: UInt64 = 0
        var batchingNanoseconds: UInt64 = 0
        if let cached = preparedFrameCache, cached.key == cacheKey {
            prepared = cached.prepared
            preparedPlan = cached.batchingPlan
            preparedFrameCacheHits &+= 1
            cacheHit = true
        } else {
            let builtPrepared = try preparedDraws(for: snapshot, outputLayout: outputLayout)
            let afterPrepare = DispatchTime.now().uptimeNanoseconds
            let builtBatchingPlan = try self.batchingPlan(
                for: snapshot,
                prepared: builtPrepared,
                sourceTriangleCount: snapshot.indices.count
            )
            preparedFrameCache = PreparedFrameCacheEntry(
                key: cacheKey,
                prepared: builtPrepared,
                batchingPlan: builtBatchingPlan
            )
            preparedFrameCacheMisses &+= 1
            prepared = builtPrepared
            preparedPlan = builtBatchingPlan
            cacheHit = false
            let totalBuildNanoseconds = DispatchTime.now().uptimeNanoseconds &- prepareStart
            prepareNanoseconds = afterPrepare &- prepareStart
            batchingNanoseconds = DispatchTime.now().uptimeNanoseconds &- afterPrepare
            if snapshot.summary.screen == UInt32(GE_SOURCE_FRAME_V6_SCREEN_RAMROM) {
                appendStageTiming(
                    "stageRenderBuild=1 tick=\(snapshot.summary.native_tick) cacheHit=0 "
                    + "prepareNs=\(prepareNanoseconds) batchNs=\(batchingNanoseconds) totalNs=\(totalBuildNanoseconds)\n"
                )
            }
        }
        let batchingPlan = preparedPlan

        let slotIndex = Int(frameIndex % 2)
        let priorSignal = lastSignalBySlot[slotIndex]
        let slotWaitStart = DispatchTime.now().uptimeNanoseconds
        if priorSignal != 0,
           !completionEvent.wait(untilSignaledValue: priorSignal, timeoutMS: 1_000) {
            throw GoldenEyeSourceSceneRendererV6Error.slotTimeout(slotIndex)
        }
        let slotWaitNanoseconds = DispatchTime.now().uptimeNanoseconds &- slotWaitStart
        let slot = slotResources[slotIndex]
        let commandSlot = state.frameSlots[slotIndex]

        let flattenedIndices = snapshot.gpuIndices.flatMap {
            [$0.vertex0, $0.vertex1, $0.vertex2]
        }
        let uploadStart = DispatchTime.now().uptimeNanoseconds
        snapshot.gpuVertices.withUnsafeBytes { bytes in
            if let baseAddress = bytes.baseAddress {
                slot.vertexBuffer.contents().copyMemory(from: baseAddress, byteCount: bytes.count)
            }
        }
        flattenedIndices.withUnsafeBytes { bytes in
            if let baseAddress = bytes.baseAddress {
                slot.indexBuffer.contents().copyMemory(from: baseAddress, byteCount: bytes.count)
            }
        }
        let uniformStride = MemoryLayout<GPUUniforms>.stride
        for (index, draw) in prepared.enumerated() {
            withUnsafeBytes(of: draw.uniforms) { bytes in
                if let baseAddress = bytes.baseAddress {
                    slot.uniformBuffer.contents().advanced(by: index * uniformStride)
                        .copyMemory(from: baseAddress, byteCount: bytes.count)
                }
            }
        }
        let uploadNanoseconds = DispatchTime.now().uptimeNanoseconds &- uploadStart

        commandSlot.allocator.reset()
        commandSlot.commandBuffer.beginCommandBuffer(allocator: commandSlot.allocator)
        commandSlot.commandBuffer.useResidencySet(state.sceneResidency)
        commandSlot.commandBuffer.useResidencySet(state.layerResidency)
        commandSlot.commandBuffer.pushDebugGroup(
            "GoldenEye.V6.SourceScene.Frame.\(frameIndex).Tick.\(snapshot.summary.native_tick)"
        )

        let pass = MTL4RenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let depthTexture = makeDepthTexture(
            slotIndex: slotIndex,
            width: drawable.texture.width,
            height: drawable.texture.height
        ) else {
            commandSlot.commandBuffer.popDebugGroup()
            commandSlot.commandBuffer.endCommandBuffer()
            throw GoldenEyeSourceSceneRendererV6Error.depthTextureUnavailable
        }
        pass.depthAttachment.texture = depthTexture
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .dontCare
        pass.depthAttachment.clearDepth = 1

        guard let encoder = commandSlot.commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            commandSlot.commandBuffer.popDebugGroup()
            commandSlot.commandBuffer.endCommandBuffer()
            throw GoldenEyeSourceSceneRendererV6Error.encoderUnavailable
        }
        encoder.label = "GoldenEye.V6.SourceScene.RenderEncoder"
        let viewportRect = outputLayout.viewportRect
        encoder.setViewport(MTLViewport(
            originX: Double(viewportRect.minX),
            originY: Double(outputLayout.outputHeight - viewportRect.maxY),
            width: Double(viewportRect.width),
            height: Double(viewportRect.height),
            znear: 0,
            zfar: 1
        ))
        try underlay?(encoder, slotIndex)

        let indexStride = MemoryLayout<UInt32>.stride * 3
        var triangleCount = 0
        let pipelineHashes = prepared.map { $0.variant.key.evidenceHash }
        let encodeStart = DispatchTime.now().uptimeNanoseconds
        for batch in batchingPlan.batches {
            let drawIndex = batch.sourceStart
            let draw = prepared[drawIndex]
            state.argumentTable.setAddress(slot.vertexBuffer.gpuAddress, index: 0)
            state.argumentTable.setAddress(
                slot.uniformBuffer.gpuAddress + UInt64(drawIndex * uniformStride),
                index: 1
            )
            if draw.hasTexture {
                guard let texture = draw.texture else {
                    throw GoldenEyeSourceSceneRendererV6Error.invalidState(
                        "textured V6 draw has no resolved texture"
                    )
                }
                state.argumentTable.setTexture(texture.gpuResourceID, index: 0)
                state.argumentTable.setSamplerState(draw.variant.samplerState.gpuResourceID, index: 0)
            }
            encoder.setRenderPipelineState(draw.variant.pipeline)
            encoder.setArgumentTable(state.argumentTable, stages: [.vertex, .fragment])
            encoder.setDepthStencilState(draw.variant.depthStencilState)
            encoder.setCullMode(draw.variant.cullMode)
            // The source clip adapter preserves the audited +Y projection
            // convention.  The canonical source front face is therefore
            // counter-clockwise; the owner-selected winding remains explicit
            // here so captures and product presentation share one contract.
            encoder.setFrontFacing(frontFacing)
            encoder.setScissorRect(draw.scissor)
            encoder.pushDebugGroup(
                "GoldenEye.V6.SourceScene.Draw.\(draw.command.draw_handle).PSO.\(String(draw.variant.key.evidenceHash, radix: 16))"
            )
            if let metadata = draw.textureMetadata {
                encoder.pushDebugGroup(
                    "GoldenEye.V6.SourceScene.Texture.\(metadata.resourceHandle).Mips.\(metadata.mipLevels).Payloads.\(metadata.levelPayloadRecordIDs.map(String.init).joined(separator: ",")).TLUT.\(metadata.palettePayloadRecordID.map(String.init) ?? "none")"
                )
            }
            let indexOffset = Int(batch.firstIndex) * indexStride
            let accessibleLength = flattenedIndices.count * MemoryLayout<UInt32>.stride - indexOffset
            encoder.drawIndexedPrimitives(
                primitiveType: .triangle,
                indexCount: Int(batch.indexCount) * 3,
                indexType: .uint32,
                indexBuffer: slot.indexBuffer.gpuAddress + UInt64(indexOffset),
                indexBufferLength: accessibleLength,
                instanceCount: Int(batch.instanceCount)
            )
            if draw.textureMetadata != nil {
                encoder.popDebugGroup()
            }
            encoder.popDebugGroup()
            triangleCount += Int(batch.indexCount)
        }
        // The optional compositor seam is intentionally invoked while the
        // source scene render pass is still open.  Overlay encoders never
        // acquire or present a drawable; the source scene remains the sole
        // owner of the render pass, queue submission, fence, and present.
        try overlay?(encoder, slotIndex)
        let cpuEncodeNanoseconds = DispatchTime.now().uptimeNanoseconds &- encodeStart
        encoder.endEncoding()
        commandSlot.commandBuffer.popDebugGroup()
        commandSlot.commandBuffer.endCommandBuffer()

        let drawableWaitStart = DispatchTime.now().uptimeNanoseconds
        state.queue.waitForDrawable(drawable)
        let drawableWaitNanoseconds = DispatchTime.now().uptimeNanoseconds &- drawableWaitStart
        let commitStart = DispatchTime.now().uptimeNanoseconds
        state.queue.commit([commandSlot.commandBuffer])
        let signalValue = nextSignalValue
        nextSignalValue &+= 1
        state.queue.signalEvent(completionEvent, value: signalValue)
        state.queue.signalDrawable(drawable)
        let commitNanoseconds = DispatchTime.now().uptimeNanoseconds &- commitStart
        let presentStart = DispatchTime.now().uptimeNanoseconds
        drawable.present()
        let presentNanoseconds = DispatchTime.now().uptimeNanoseconds &- presentStart
        lastSignalBySlot[slotIndex] = signalValue

        let evidence = GoldenEyeSourceSceneRenderEvidenceV6(
            frameIndex: frameIndex,
            nativeTick: snapshot.summary.native_tick,
            drawCount: prepared.count,
            triangleCount: triangleCount,
            copiedRecordAggregateHash: snapshot.copiedRecordAggregateHash,
            pipelineKeyHashes: pipelineHashes,
            slotIndex: slotIndex,
            signalValue: signalValue,
            metalDrawCount: batchingPlan.metalDrawCount,
            sourceManifestHash: batchingPlan.sourceManifestHash,
            batchManifestHash: batchingPlan.batchManifestHash,
            cpuEncodeNanoseconds: cpuEncodeNanoseconds
        )
        if snapshot.summary.screen == UInt32(GE_SOURCE_FRAME_V6_SCREEN_RAMROM) {
            appendStageTiming(
                "stageRenderTiming=1 tick=\(snapshot.summary.native_tick) draws=\(prepared.count) metalDraws=\(batchingPlan.metalDrawCount) "
                + "cacheHit=\(cacheHit ? 1 : 0) cacheHits=\(preparedFrameCacheHits) cacheMisses=\(preparedFrameCacheMisses) "
                + "prepareNs=\(prepareNanoseconds) batchNs=\(batchingNanoseconds) slotWaitNs=\(slotWaitNanoseconds) "
                + "uploadNs=\(uploadNanoseconds) encodeNs=\(cpuEncodeNanoseconds) "
                + "drawableWaitNs=\(drawableWaitNanoseconds) commitNs=\(commitNanoseconds) presentNs=\(presentNanoseconds)\n"
            )
        }
        frameIndex &+= 1
        return evidence
    }

    /// Render into the compositor-independent 320x240 source target.  This
    /// path deliberately does not accept or acquire a drawable: it uses one
    /// private target and one shared readback buffer per reusable frame slot,
    /// then waits on the same completion event used by the onscreen path.
    @discardableResult
    func renderReference320x240(
        snapshot: GoldenEyeSourceSceneSnapshotV6,
        captureURL: URL? = nil,
        underlay: ((any MTL4RenderCommandEncoder, Int) throws -> Void)? = nil,
        overlay: ((any MTL4RenderCommandEncoder, Int) throws -> Void)? = nil
    ) throws -> GoldenEyeSourceSceneReferenceCaptureV6 {
        guard outputMode == .reference320x240 else {
            throw GoldenEyeSourceSceneRendererV6Error.invalidState(
                "reference render requested from \(outputMode) renderer"
            )
        }
        if let captureURL {
            _ = try validatedReferenceCaptureURL(captureURL)
        }
        guard snapshot.isPresentable else {
            throw GoldenEyeSourceSceneRendererV6Error.invalidState("frame is not presentable")
        }
        guard snapshot.summary.unsupported_visible_count == 0 else {
            throw GoldenEyeSourceSceneRendererV6Error.unsupportedVisibleDiagnostics(
                snapshot.summary.unsupported_visible_count
            )
        }
        guard snapshot.vertices.count <= maxVertexCount,
              snapshot.indices.count <= maxIndexCount,
              snapshot.drawCommands.count * MemoryLayout<GPUUniforms>.stride <= maxUniformBytes else {
            throw GoldenEyeSourceSceneRendererV6Error.capacityExceeded(
                "vertices=\(snapshot.vertices.count) indices=\(snapshot.indices.count) draws=\(snapshot.drawCommands.count)"
            )
        }

        let outputLayout = GoldenEyeSourceSceneLayoutV6(
            mode: .reference320x240,
            drawableWidth: 320,
            drawableHeight: 240
        )
        let prepared = try preparedDraws(for: snapshot, outputLayout: outputLayout)
        let batchingPlan = try batchingPlan(
            for: snapshot,
            prepared: prepared,
            sourceTriangleCount: snapshot.indices.count
        )
        let slotIndex = Int(frameIndex % 2)
        let priorSignal = lastSignalBySlot[slotIndex]
        if priorSignal != 0,
           !completionEvent.wait(untilSignaledValue: priorSignal, timeoutMS: 1_000) {
            throw GoldenEyeSourceSceneRendererV6Error.slotTimeout(slotIndex)
        }
        let slot = slotResources[slotIndex]
        let reference = referenceSlotResources[slotIndex]
        let commandSlot = state.frameSlots[slotIndex]
        let flattenedIndices = snapshot.gpuIndices.flatMap {
            [$0.vertex0, $0.vertex1, $0.vertex2]
        }
        snapshot.gpuVertices.withUnsafeBytes { bytes in
            if let baseAddress = bytes.baseAddress {
                slot.vertexBuffer.contents().copyMemory(from: baseAddress, byteCount: bytes.count)
            }
        }
        flattenedIndices.withUnsafeBytes { bytes in
            if let baseAddress = bytes.baseAddress {
                slot.indexBuffer.contents().copyMemory(from: baseAddress, byteCount: bytes.count)
            }
        }
        let uniformStride = MemoryLayout<GPUUniforms>.stride
        for (index, draw) in prepared.enumerated() {
            withUnsafeBytes(of: draw.uniforms) { bytes in
                if let baseAddress = bytes.baseAddress {
                    slot.uniformBuffer.contents().advanced(by: index * uniformStride)
                        .copyMemory(from: baseAddress, byteCount: bytes.count)
                }
            }
        }

        commandSlot.allocator.reset()
        commandSlot.commandBuffer.beginCommandBuffer(allocator: commandSlot.allocator)
        commandSlot.commandBuffer.useResidencySet(state.sceneResidency)
        commandSlot.commandBuffer.pushDebugGroup(
            "GoldenEye.V6.SourceScene.Reference320.Frame.\(frameIndex).Tick.\(snapshot.summary.native_tick)"
        )

        let pass = MTL4RenderPassDescriptor()
        pass.colorAttachments[0].texture = reference.target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.depthAttachment.texture = reference.depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .dontCare
        pass.depthAttachment.clearDepth = 1

        guard let encoder = commandSlot.commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            commandSlot.commandBuffer.popDebugGroup()
            commandSlot.commandBuffer.endCommandBuffer()
            throw GoldenEyeSourceSceneRendererV6Error.encoderUnavailable
        }
        encoder.label = "GoldenEye.V6.SourceScene.Reference320.RenderEncoder"
        let viewportRect = outputLayout.viewportRect
        encoder.setViewport(MTLViewport(
            originX: Double(viewportRect.minX),
            originY: Double(outputLayout.outputHeight - viewportRect.maxY),
            width: Double(viewportRect.width),
            height: Double(viewportRect.height),
            znear: 0,
            zfar: 1
        ))
        try underlay?(encoder, slotIndex)

        let indexStride = MemoryLayout<UInt32>.stride * 3
        var triangleCount = 0
        let pipelineHashes = prepared.map { $0.variant.key.evidenceHash }
        let encodeStart = DispatchTime.now().uptimeNanoseconds
        for batch in batchingPlan.batches {
            let drawIndex = batch.sourceStart
            let draw = prepared[drawIndex]
            state.argumentTable.setAddress(slot.vertexBuffer.gpuAddress, index: 0)
            state.argumentTable.setAddress(
                slot.uniformBuffer.gpuAddress + UInt64(drawIndex * uniformStride),
                index: 1
            )
            if draw.hasTexture {
                guard let texture = draw.texture else {
                    throw GoldenEyeSourceSceneRendererV6Error.invalidState(
                        "textured V6 reference draw has no resolved texture"
                    )
                }
                state.argumentTable.setTexture(texture.gpuResourceID, index: 0)
                state.argumentTable.setSamplerState(draw.variant.samplerState.gpuResourceID, index: 0)
            }
            encoder.setRenderPipelineState(draw.variant.pipeline)
            encoder.setArgumentTable(state.argumentTable, stages: [.vertex, .fragment])
            encoder.setDepthStencilState(draw.variant.depthStencilState)
            encoder.setCullMode(draw.variant.cullMode)
            encoder.setFrontFacing(frontFacing)
            encoder.setScissorRect(draw.scissor)
            encoder.pushDebugGroup(
                "GoldenEye.V6.SourceScene.Reference320.Draw.\(draw.command.draw_handle).PSO.\(String(draw.variant.key.evidenceHash, radix: 16))"
            )
            if let metadata = draw.textureMetadata {
                encoder.pushDebugGroup(
                    "GoldenEye.V6.SourceScene.Reference320.Texture.\(metadata.resourceHandle).Mips.\(metadata.mipLevels).TLUT.\(metadata.palettePayloadRecordID.map(String.init) ?? "none")"
                )
            }
            let indexOffset = Int(batch.firstIndex) * indexStride
            let accessibleLength = flattenedIndices.count * MemoryLayout<UInt32>.stride - indexOffset
            encoder.drawIndexedPrimitives(
                primitiveType: .triangle,
                indexCount: Int(batch.indexCount) * 3,
                indexType: .uint32,
                indexBuffer: slot.indexBuffer.gpuAddress + UInt64(indexOffset),
                indexBufferLength: accessibleLength,
                instanceCount: Int(batch.instanceCount)
            )
            if draw.textureMetadata != nil {
                encoder.popDebugGroup()
            }
            encoder.popDebugGroup()
            triangleCount += Int(batch.indexCount)
        }
        // Keep the source 2D packet in the same render pass/command buffer as
        // the 3D scene.  A second presented pass would either erase the scene
        // or violate the drawable/present contract; the caller-supplied
        // encoder seam lets the Legal capture composite Zurich glyphs after
        // the authored model while preserving one clear and one readback.
        try overlay?(encoder, slotIndex)
        let cpuEncodeNanoseconds = DispatchTime.now().uptimeNanoseconds &- encodeStart
        encoder.endEncoding()

        // The target is a render attachment; a producer barrier publishes its
        // pixels before the MTL4 copy encoder reads them into shared memory.
        guard let readbackEncoder = commandSlot.commandBuffer.makeComputeCommandEncoder() else {
            commandSlot.commandBuffer.popDebugGroup()
            commandSlot.commandBuffer.endCommandBuffer()
            throw GoldenEyeSourceSceneRendererV6Error.encoderUnavailable
        }
        readbackEncoder.label = "GoldenEye.V6.SourceScene.Reference320.Readback"
        readbackEncoder.barrier(
            afterQueueStages: [.vertex, .fragment],
            beforeStages: [.blit],
            visibilityOptions: .device
        )
        readbackEncoder.copy(
            sourceTexture: reference.target,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: 320, height: 240, depth: 1),
            destinationBuffer: reference.readback,
            destinationOffset: 0,
            destinationBytesPerRow: 320 * 4,
            destinationBytesPerImage: 0
        )
        readbackEncoder.endEncoding()
        commandSlot.commandBuffer.popDebugGroup()
        commandSlot.commandBuffer.endCommandBuffer()

        state.queue.commit([commandSlot.commandBuffer])
        let signalValue = nextSignalValue
        nextSignalValue &+= 1
        state.queue.signalEvent(completionEvent, value: signalValue)
        lastSignalBySlot[slotIndex] = signalValue
        guard completionEvent.wait(untilSignaledValue: signalValue, timeoutMS: 2_000) else {
            throw GoldenEyeSourceSceneRendererV6Error.slotTimeout(slotIndex)
        }

        let byteCount = 320 * 240 * 4
        let bytes = Data(bytes: reference.readback.contents(), count: byteCount)
        let rawSHA256 = Self.sha256(bytes)
        let evidence = GoldenEyeSourceSceneRenderEvidenceV6(
            frameIndex: frameIndex,
            nativeTick: snapshot.summary.native_tick,
            drawCount: prepared.count,
            triangleCount: triangleCount,
            copiedRecordAggregateHash: snapshot.copiedRecordAggregateHash,
            pipelineKeyHashes: pipelineHashes,
            slotIndex: slotIndex,
            signalValue: signalValue,
            metalDrawCount: batchingPlan.metalDrawCount,
            sourceManifestHash: batchingPlan.sourceManifestHash,
            batchManifestHash: batchingPlan.batchManifestHash,
            cpuEncodeNanoseconds: cpuEncodeNanoseconds
        )
        frameIndex &+= 1
        let pngURL = try captureURL.map {
            try writeReferenceCapture(bytes: bytes, evidence: evidence, rawSHA256: rawSHA256, to: $0)
        }
        return GoldenEyeSourceSceneReferenceCaptureV6(
            width: 320,
            height: 240,
            bytesPerRow: 320 * 4,
            pixelFormat: "bgra8Unorm",
            bytes: bytes,
            evidence: evidence,
            captureURL: captureURL,
            pngURL: pngURL,
            rawSHA256: rawSHA256
        )
    }

    /// Render a Faithful HD or Adaptive Widescreen frame into a private
    /// compositor-independent target.  This is an evidence seam for output
    /// mode validation; production presentation continues to use the
    /// callback-supplied CAMetalDisplayLink drawable through ``render``.
    /// The source snapshot, prepared draw list, pipeline keys, and 2D
    /// underlay/overlay packets are identical to the presented path.
    @discardableResult
    func renderOffscreen(
        snapshot: GoldenEyeSourceSceneSnapshotV6,
        width: Int,
        height: Int,
        underlay: ((any MTL4RenderCommandEncoder, Int) throws -> Void)? = nil,
        overlay: ((any MTL4RenderCommandEncoder, Int) throws -> Void)? = nil
    ) throws -> GoldenEyeSourceSceneReferenceCaptureV6 {
        guard outputMode == .faithfulHD || outputMode == .adaptiveWidescreen else {
            throw GoldenEyeSourceSceneRendererV6Error.invalidState(
                "offscreen output requires Faithful HD or Adaptive Widescreen"
            )
        }
        guard width > 0, height > 0 else {
            throw GoldenEyeSourceSceneRendererV6Error.invalidState("offscreen dimensions")
        }
        guard snapshot.isPresentable else {
            throw GoldenEyeSourceSceneRendererV6Error.invalidState("frame is not presentable")
        }
        guard snapshot.summary.unsupported_visible_count == 0 else {
            throw GoldenEyeSourceSceneRendererV6Error.unsupportedVisibleDiagnostics(
                snapshot.summary.unsupported_visible_count
            )
        }
        guard snapshot.vertices.count <= maxVertexCount,
              snapshot.indices.count <= maxIndexCount,
              snapshot.drawCommands.count * MemoryLayout<GPUUniforms>.stride <= maxUniformBytes else {
            throw GoldenEyeSourceSceneRendererV6Error.capacityExceeded(
                "vertices=\(snapshot.vertices.count) indices=\(snapshot.indices.count) draws=\(snapshot.drawCommands.count)"
            )
        }

        let outputLayout = GoldenEyeSourceSceneLayoutV6(
            mode: outputMode,
            drawableWidth: width,
            drawableHeight: height
        )
        let prepared = try preparedDraws(for: snapshot, outputLayout: outputLayout)
        let batchingPlan = try batchingPlan(
            for: snapshot,
            prepared: prepared,
            sourceTriangleCount: snapshot.indices.count
        )
        let slotIndex = Int(frameIndex % 2)
        let priorSignal = lastSignalBySlot[slotIndex]
        if priorSignal != 0,
           !completionEvent.wait(untilSignaledValue: priorSignal, timeoutMS: 1_000) {
            throw GoldenEyeSourceSceneRendererV6Error.slotTimeout(slotIndex)
        }

        let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        targetDescriptor.storageMode = .private
        targetDescriptor.usage = [.renderTarget, .shaderRead]
        guard let target = state.device.makeTexture(descriptor: targetDescriptor),
              let readback = state.device.makeBuffer(
                  length: width * height * 4,
                  options: .storageModeShared
              ) else {
            throw GoldenEyeSourceSceneRendererV6Error.referenceTargetUnavailable
        }
        target.label = "GoldenEye.V6.SourceScene.Offscreen.\(outputMode).\(width)x\(height).Color"
        readback.label = "GoldenEye.V6.SourceScene.Offscreen.\(outputMode).\(width)x\(height).Readback"
        state.sceneResidency.addAllocation(target)
        state.sceneResidency.addAllocation(readback)
        state.sceneResidency.commit()

        let slot = slotResources[slotIndex]
        let commandSlot = state.frameSlots[slotIndex]
        let flattenedIndices = snapshot.gpuIndices.flatMap {
            [$0.vertex0, $0.vertex1, $0.vertex2]
        }
        snapshot.gpuVertices.withUnsafeBytes { bytes in
            if let baseAddress = bytes.baseAddress {
                slot.vertexBuffer.contents().copyMemory(from: baseAddress, byteCount: bytes.count)
            }
        }
        flattenedIndices.withUnsafeBytes { bytes in
            if let baseAddress = bytes.baseAddress {
                slot.indexBuffer.contents().copyMemory(from: baseAddress, byteCount: bytes.count)
            }
        }
        let uniformStride = MemoryLayout<GPUUniforms>.stride
        for (index, draw) in prepared.enumerated() {
            withUnsafeBytes(of: draw.uniforms) { bytes in
                if let baseAddress = bytes.baseAddress {
                    slot.uniformBuffer.contents().advanced(by: index * uniformStride)
                        .copyMemory(from: baseAddress, byteCount: bytes.count)
                }
            }
        }

        func removeTransientAllocations() {
            state.sceneResidency.removeAllocation(target)
            state.sceneResidency.removeAllocation(readback)
            state.sceneResidency.commit()
        }

        commandSlot.allocator.reset()
        commandSlot.commandBuffer.beginCommandBuffer(allocator: commandSlot.allocator)
        commandSlot.commandBuffer.useResidencySet(state.sceneResidency)
        commandSlot.commandBuffer.pushDebugGroup(
            "GoldenEye.V6.SourceScene.Offscreen.\(outputMode).Frame.\(frameIndex).Tick.\(snapshot.summary.native_tick)"
        )

        let pass = MTL4RenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let depthTexture = makeDepthTexture(slotIndex: slotIndex, width: width, height: height) else {
            commandSlot.commandBuffer.popDebugGroup()
            commandSlot.commandBuffer.endCommandBuffer()
            removeTransientAllocations()
            throw GoldenEyeSourceSceneRendererV6Error.depthTextureUnavailable
        }
        pass.depthAttachment.texture = depthTexture
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .dontCare
        pass.depthAttachment.clearDepth = 1

        guard let encoder = commandSlot.commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            commandSlot.commandBuffer.popDebugGroup()
            commandSlot.commandBuffer.endCommandBuffer()
            removeTransientAllocations()
            throw GoldenEyeSourceSceneRendererV6Error.encoderUnavailable
        }
        encoder.label = "GoldenEye.V6.SourceScene.Offscreen.\(outputMode).RenderEncoder"
        let viewportRect = outputLayout.viewportRect
        encoder.setViewport(MTLViewport(
            originX: Double(viewportRect.minX),
            originY: Double(outputLayout.outputHeight - viewportRect.maxY),
            width: Double(viewportRect.width),
            height: Double(viewportRect.height),
            znear: 0,
            zfar: 1
        ))
        try underlay?(encoder, slotIndex)

        let indexStride = MemoryLayout<UInt32>.stride * 3
        var triangleCount = 0
        let pipelineHashes = prepared.map { $0.variant.key.evidenceHash }
        let encodeStart = DispatchTime.now().uptimeNanoseconds
        for batch in batchingPlan.batches {
            let drawIndex = batch.sourceStart
            let draw = prepared[drawIndex]
            state.argumentTable.setAddress(slot.vertexBuffer.gpuAddress, index: 0)
            state.argumentTable.setAddress(
                slot.uniformBuffer.gpuAddress + UInt64(drawIndex * uniformStride),
                index: 1
            )
            if draw.hasTexture {
                guard let texture = draw.texture else {
                    encoder.endEncoding()
                    commandSlot.commandBuffer.popDebugGroup()
                    commandSlot.commandBuffer.endCommandBuffer()
                    removeTransientAllocations()
                    throw GoldenEyeSourceSceneRendererV6Error.invalidState(
                        "textured V6 offscreen draw has no resolved texture"
                    )
                }
                state.argumentTable.setTexture(texture.gpuResourceID, index: 0)
                state.argumentTable.setSamplerState(draw.variant.samplerState.gpuResourceID, index: 0)
            }
            encoder.setRenderPipelineState(draw.variant.pipeline)
            encoder.setArgumentTable(state.argumentTable, stages: [.vertex, .fragment])
            encoder.setDepthStencilState(draw.variant.depthStencilState)
            encoder.setCullMode(draw.variant.cullMode)
            encoder.setFrontFacing(frontFacing)
            encoder.setScissorRect(draw.scissor)
            encoder.pushDebugGroup(
                "GoldenEye.V6.SourceScene.Offscreen.Draw.\(draw.command.draw_handle).PSO.\(String(draw.variant.key.evidenceHash, radix: 16))"
            )
            if let metadata = draw.textureMetadata {
                encoder.pushDebugGroup(
                    "GoldenEye.V6.SourceScene.Offscreen.Texture.\(metadata.resourceHandle).Mips.\(metadata.mipLevels).TLUT.\(metadata.palettePayloadRecordID.map(String.init) ?? "none")"
                )
            }
            let indexOffset = Int(batch.firstIndex) * indexStride
            let accessibleLength = flattenedIndices.count * MemoryLayout<UInt32>.stride - indexOffset
            encoder.drawIndexedPrimitives(
                primitiveType: .triangle,
                indexCount: Int(batch.indexCount) * 3,
                indexType: .uint32,
                indexBuffer: slot.indexBuffer.gpuAddress + UInt64(indexOffset),
                indexBufferLength: accessibleLength,
                instanceCount: Int(batch.instanceCount)
            )
            if draw.textureMetadata != nil {
                encoder.popDebugGroup()
            }
            encoder.popDebugGroup()
            triangleCount += Int(batch.indexCount)
        }
        try overlay?(encoder, slotIndex)
        let cpuEncodeNanoseconds = DispatchTime.now().uptimeNanoseconds &- encodeStart
        encoder.endEncoding()

        guard let readbackEncoder = commandSlot.commandBuffer.makeComputeCommandEncoder() else {
            commandSlot.commandBuffer.popDebugGroup()
            commandSlot.commandBuffer.endCommandBuffer()
            removeTransientAllocations()
            throw GoldenEyeSourceSceneRendererV6Error.encoderUnavailable
        }
        readbackEncoder.label = "GoldenEye.V6.SourceScene.Offscreen.Readback"
        readbackEncoder.barrier(
            afterQueueStages: [.vertex, .fragment],
            beforeStages: [.blit],
            visibilityOptions: .device
        )
        readbackEncoder.copy(
            sourceTexture: target,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: width, height: height, depth: 1),
            destinationBuffer: readback,
            destinationOffset: 0,
            destinationBytesPerRow: width * 4,
            destinationBytesPerImage: 0
        )
        readbackEncoder.endEncoding()
        commandSlot.commandBuffer.popDebugGroup()
        commandSlot.commandBuffer.endCommandBuffer()

        state.queue.commit([commandSlot.commandBuffer])
        let signalValue = nextSignalValue
        nextSignalValue &+= 1
        state.queue.signalEvent(completionEvent, value: signalValue)
        lastSignalBySlot[slotIndex] = signalValue
        guard completionEvent.wait(untilSignaledValue: signalValue, timeoutMS: 2_000) else {
            throw GoldenEyeSourceSceneRendererV6Error.slotTimeout(slotIndex)
        }

        let byteCount = width * height * 4
        let bytes = Data(bytes: readback.contents(), count: byteCount)
        let rawSHA256 = Self.sha256(bytes)
        let evidence = GoldenEyeSourceSceneRenderEvidenceV6(
            frameIndex: frameIndex,
            nativeTick: snapshot.summary.native_tick,
            drawCount: prepared.count,
            triangleCount: triangleCount,
            copiedRecordAggregateHash: snapshot.copiedRecordAggregateHash,
            pipelineKeyHashes: pipelineHashes,
            slotIndex: slotIndex,
            signalValue: signalValue,
            metalDrawCount: batchingPlan.metalDrawCount,
            sourceManifestHash: batchingPlan.sourceManifestHash,
            batchManifestHash: batchingPlan.batchManifestHash,
            cpuEncodeNanoseconds: cpuEncodeNanoseconds
        )
        frameIndex &+= 1
        removeTransientAllocations()
        return GoldenEyeSourceSceneReferenceCaptureV6(
            width: width,
            height: height,
            bytesPerRow: width * 4,
            pixelFormat: "bgra8Unorm",
            bytes: bytes,
            evidence: evidence,
            captureURL: nil,
            pngURL: nil,
            rawSHA256: rawSHA256
        )
    }

    /// Named capture convenience for evidence scripts.  It is intentionally
    /// separate from the render method so production owner code cannot write
    /// arbitrary files as a side effect of presenting a frame.
    @discardableResult
    func captureReference320x240(
        snapshot: GoldenEyeSourceSceneSnapshotV6,
        to url: URL,
        underlay: ((any MTL4RenderCommandEncoder, Int) throws -> Void)? = nil,
        overlay: ((any MTL4RenderCommandEncoder, Int) throws -> Void)? = nil
    ) throws -> GoldenEyeSourceSceneReferenceCaptureV6 {
        try renderReference320x240(snapshot: snapshot, captureURL: url, underlay: underlay, overlay: overlay)
    }

    func shutdown() {
        for signal in lastSignalBySlot where signal != 0 {
            _ = completionEvent.wait(untilSignaledValue: signal, timeoutMS: 2_000)
        }
    }

    private func batchingPlan(
        for snapshot: GoldenEyeSourceSceneSnapshotV6,
        prepared: [PreparedDraw],
        sourceTriangleCount: Int
    ) throws -> GoldenEyeSourceSceneBatchingPlanV6 {
        guard prepared.count == snapshot.drawCommands.count else {
            throw GoldenEyeSourceSceneBatchingV6Error.commandCountMismatch(
                expected: snapshot.drawCommands.count,
                actual: prepared.count
            )
        }
        guard snapshot.drawCommandHashes.count == snapshot.drawCommands.count else {
            throw GoldenEyeSourceSceneBatchingV6Error.commandHashCountMismatch(
                expected: snapshot.drawCommands.count,
                actual: snapshot.drawCommandHashes.count
            )
        }

        let renderStateByHandle = snapshot.renderStateByHandle
        var inputs: [GoldenEyeSourceSceneBatchingInputV6] = []
        inputs.reserveCapacity(prepared.count)
        for (index, draw) in prepared.enumerated() {
            guard let renderState = renderStateByHandle[draw.command.render_state_handle] else {
                throw GoldenEyeSourceSceneRendererV6Error.missingRenderState(
                    draw.command.render_state_handle
                )
            }
            let sourceRenderStateHash = Self.sourceRenderStateHash(renderState)
            let samplerKeyHash = Self.batchingHash(
                renderState.filter_mode,
                renderState.wrap_s,
                renderState.wrap_t,
                renderState.lod_min_q16,
                renderState.lod_max_q16
            )
            let depthKey = Self.batchingHash(
                renderState.depth_mode,
                renderState.raw_othermode_h,
                renderState.lod_min_q16,
                renderState.lod_max_q16
            )
            let blendKey = Self.batchingHash(
                renderState.alpha_mode,
                renderState.coverage_mode,
                renderState.raw_render_mode,
                renderState.raw_blender_a,
                renderState.raw_blender_b,
                renderState.raw_blender_c,
                renderState.raw_blender_d
            )
            let scissor = draw.scissor
            let key = GoldenEyeSourceSceneBatchingKeyV6(
                commandKind: draw.command.command_kind,
                flags: draw.command.flags,
                transformHandle: draw.command.transform_handle,
                resourceHandle: draw.command.resource_handle,
                renderStateHandle: draw.command.render_state_handle,
                instanceCount: draw.command.instance_count,
                textHandle: draw.command.text_handle,
                scissorX: Int64(scissor.x),
                scissorY: Int64(scissor.y),
                scissorWidth: Int64(scissor.width),
                scissorHeight: Int64(scissor.height),
                sourceRenderStateHash: sourceRenderStateHash,
                pipelineKeyHash: draw.variant.key.evidenceHash,
                samplerKeyHash: samplerKeyHash,
                textureBindingHash: Self.textureBindingHash(draw.textureMetadata),
                uniformHash: Self.uniformHash(draw.uniforms),
                cullKey: renderState.cull_mode,
                depthKey: depthKey,
                blendKey: blendKey
            )
            inputs.append(.init(
                command: draw.command,
                commandHash: snapshot.drawCommandHashes[index],
                key: key
            ))
        }
        return try GoldenEyeSourceSceneBatchingPlanV6(
            inputs: inputs,
            sourceTriangleCount: sourceTriangleCount,
            maxBatchCount: max(1, maxIndexCount)
        )
    }

    private static func batchingHash(_ values: UInt32...) -> UInt64 {
        var result = GoldenEyeSourceSceneBatchingPlanV6.hashOffset
        for value in values {
            for shift in stride(from: 0, through: 24, by: 8) {
                result = (result ^ UInt64((value >> UInt32(shift)) & 0xff))
                    &* GoldenEyeSourceSceneBatchingPlanV6.hashPrime
            }
        }
        return result
    }

    private static func sourceRenderStateHash(_ state: GESourceRenderStateV6) -> UInt64 {
        let values: [UInt32] = [
            state.record_version, state.state_handle, state.flags, state.material_handle,
            state.combiner_cycle_count, state.cycle0_color_a, state.cycle0_color_b,
            state.cycle0_color_c, state.cycle0_color_d, state.cycle0_alpha_a,
            state.cycle0_alpha_b, state.cycle0_alpha_c, state.cycle0_alpha_d,
            state.cycle1_color_a, state.cycle1_color_b, state.cycle1_color_c,
            state.cycle1_color_d, state.cycle1_alpha_a, state.cycle1_alpha_b,
            state.cycle1_alpha_c, state.cycle1_alpha_d, state.primitive_rgba,
            state.environment_rgba, state.fog_rgba, state.blend_rgba, state.depth_mode,
            state.alpha_mode, state.coverage_mode, state.cull_mode, state.filter_mode,
            state.wrap_s, state.wrap_t, state.lod_min_q16, state.lod_max_q16,
            state.raw_othermode_h, state.raw_othermode_l, state.raw_render_mode,
            state.raw_blender_a, state.raw_blender_b, state.raw_blender_c, state.raw_blender_d,
            state.reserved0, state.reserved1
        ]
        var result = GoldenEyeSourceSceneBatchingPlanV6.hashOffset
        for value in values {
            for shift in stride(from: 0, through: 24, by: 8) {
                result = (result ^ UInt64((value >> UInt32(shift)) & 0xff))
                    &* GoldenEyeSourceSceneBatchingPlanV6.hashPrime
            }
        }
        return result
    }

    private static func textureBindingHash(
        _ metadata: GoldenEyeSourceSceneTextureBindingMetadataV6?
    ) -> UInt64 {
        guard let metadata else { return 0 }
        var result = GoldenEyeSourceSceneBatchingPlanV6.hashOffset
        for value in [
            metadata.resourceHandle, metadata.width, metadata.height, metadata.mipLevels,
            metadata.sourceOffset, metadata.sourceRowHandle, metadata.sourceSpan,
            metadata.mipDimensionMode.rawValue, metadata.metalArrayLength
        ] {
            result = batchingHashBytes(result, UInt64(value))
        }
        for value in metadata.levelWidths + metadata.levelHeights + metadata.levelPayloadRecordIDs {
            result = batchingHashBytes(result, UInt64(value))
        }
        if let palettePayloadRecordID = metadata.palettePayloadRecordID {
            result = batchingHashBytes(result, UInt64(palettePayloadRecordID))
        } else {
            result = batchingHashBytes(result, 0)
        }
        return result
    }

    private static func batchingHashBytes(_ hash: UInt64, _ value: UInt64) -> UInt64 {
        var result = hash
        for shift in stride(from: 0, through: 56, by: 8) {
            result = (result ^ ((value >> UInt64(shift)) & 0xff))
                &* GoldenEyeSourceSceneBatchingPlanV6.hashPrime
        }
        return result
    }

    private static func uniformHash(_ uniforms: GPUUniforms) -> UInt64 {
        withUnsafeBytes(of: uniforms) { rawBytes in
            var result = GoldenEyeSourceSceneBatchingPlanV6.hashOffset
            for byte in rawBytes {
                result = (result ^ UInt64(byte))
                    &* GoldenEyeSourceSceneBatchingPlanV6.hashPrime
            }
            return result
        }
    }

    private func preparedDraws(
        for snapshot: GoldenEyeSourceSceneSnapshotV6,
        outputLayout: GoldenEyeSourceSceneLayoutV6
    ) throws -> [PreparedDraw] {
        let resourceByHandle = snapshot.resourceByHandle
        let transformByHandle = snapshot.transformByHandle
        let renderStateByHandle = snapshot.renderStateByHandle
        // Source bg.c applies the current environment fog around every room
        // primary/secondary display list.  The stage packet carries the
        // exact source-symmetric coordinate before the generic NDC vertex
        // copy; no depth/eye-space approximation is accepted here. Non-stage and
        // fogless fallback frames retain the zero fog payload.
        let stageFog: GoldenEyeStageFogParametersV6?
        if snapshot.summary.screen == UInt32(GE_SOURCE_FRAME_V6_SCREEN_RAMROM) {
            stageFog = try? GoldenEyeStageFogLoweringV6.make(
                stageID: snapshot.summary.subphase
            )
        } else {
            stageFog = nil
        }
        var prepared: [PreparedDraw] = []
        prepared.reserveCapacity(snapshot.drawCommands.count)

        for command in snapshot.drawCommands {
            guard command.command_kind == UInt32(GE_SOURCE_DRAW_V6_TRIANGLES) else {
                throw GoldenEyeSourceSceneRendererV6Error.unsupportedCommand(command.command_kind)
            }
            guard command.render_state_handle != 0,
                  let renderState = renderStateByHandle[command.render_state_handle] else {
                throw GoldenEyeSourceSceneRendererV6Error.missingRenderState(command.render_state_handle)
            }
            guard let lightingFrameContext = snapshot.lightingFrameContext,
                  lightingFrameContext.screen == snapshot.summary.screen,
                  lightingFrameContext.nativeTick == snapshot.summary.native_tick,
                  lightingFrameContext.referenceTick == snapshot.summary.reference_tick,
                  lightingFrameContext.pairPhase == snapshot.summary.pair_phase else {
                throw GoldenEyeSourceSceneRendererV6Error.missingLightingContext(command.draw_handle)
            }
            guard let rawGeometryMode = lightingFrameContext.geometryModesByState[renderState.state_handle],
                  let modelViewQ16 = lightingFrameContext.modelViewQ16ByState[renderState.state_handle] else {
                throw GoldenEyeSourceSceneRendererV6Error.missingLightingState(renderState.state_handle)
            }
            let sourceModelView = Self.matrix(fromQ16: modelViewQ16)
            let hasTexture = command.resource_handle != 0
            // Legal's source combiner may carry LOD/K5 selectors while its
            // OtherMode disables LOD. Reduce those scalar inputs to source
            // zero at the shader boundary; the authored equation remains
            // intact without introducing a texture or procedural material.
            let effectiveRenderState = Self.rendererStateForSource(
                renderState,
                hasTexture: hasTexture,
                sourceScreen: snapshot.summary.screen
            )
            let fogEnabled = GoldenEyeSourceScenePipelineV6.isFogShadeGeometryState(
                effectiveRenderState
            )
            let fogInfo: SIMD4<UInt32>
            if fogEnabled {
                guard snapshot.summary.screen == UInt32(GE_SOURCE_FRAME_V6_SCREEN_RAMROM),
                      let stageFog, stageFog.enabled else {
                    throw GoldenEyeSourceSceneRendererV6Error.missingFogCoordinate(
                        snapshot.summary.subphase
                    )
                }
                guard !stageFog.requiresRendererBinding else {
                    throw GoldenEyeSourceSceneRendererV6Error.unsupportedFogBinding(
                        snapshot.summary.subphase,
                        stageFog.unsupportedReasonCode
                    )
                }
                guard let coordinates = snapshot.fogCoordinateQ16,
                      coordinates.count == snapshot.vertices.count else {
                    throw GoldenEyeSourceSceneRendererV6Error.missingFogCoordinate(
                        snapshot.summary.subphase
                    )
                }
                fogInfo = SIMD4(
                    UInt32(1),
                    UInt32(bitPattern: stageFog.sourceFogMultiplier),
                    UInt32(bitPattern: stageFog.sourceFogOffset),
                    stageFog.sourceFogColorRGBA
                )
            } else {
                fogInfo = SIMD4<UInt32>(repeating: 0)
            }
            let sourceUsesTexture = Self.stateUsesTexture(effectiveRenderState)
            var texture: (any MTLTexture)?
            var textureMetadata: GoldenEyeSourceSceneTextureBindingMetadataV6?
            var textureMipLevels: UInt32?
            var textureUsesArray = false
            if hasTexture {
                guard let resource = resourceByHandle[command.resource_handle] else {
                    throw GoldenEyeSourceSceneRendererV6Error.missingTexture(command.resource_handle)
                }
                guard resource.resource_kind == UInt32(GE_SOURCE_RESOURCE_V6_TEXTURE) else {
                    throw GoldenEyeSourceSceneRendererV6Error.nonTextureResource(command.resource_handle)
                }
                guard resource.mip_count > 0,
                      resource.level_count == resource.mip_count else {
                    throw GoldenEyeSourceSceneRendererV6Error.missingTexture(command.resource_handle)
                }
                let expectedMipLevels = max(1, Int(resource.level_count))
                let resolvedTexture: any MTLTexture
                if let textureBindingAdapter {
                    do {
                        let binding = try textureBindingAdapter.binding(for: resource)
                        if binding.metadata.hasValidatedPalette {
                            let basePaletteHandle = GoldenEyeSourceSceneTextureBindingAdapterV6
                                .paletteResourceHandle(for: command.resource_handle)
                            let paletteHandle: UInt32
                            if let existing = resourceByHandle[basePaletteHandle],
                               existing.resource_kind == UInt32(GE_SOURCE_RESOURCE_V6_PALETTE) {
                                // The base candidate is already the emitted
                                // palette resource; do not treat that resource
                                // itself as an occupied collision while
                                // reconstructing the builder's namespace.
                                paletteHandle = basePaletteHandle
                            } else {
                                let occupied = Set(resourceByHandle.compactMap { handle, value in
                                    value.resource_kind == UInt32(GE_SOURCE_RESOURCE_V6_PALETTE)
                                        ? nil : handle
                                })
                                paletteHandle = GoldenEyeSourceSceneTextureBindingAdapterV6
                                    .paletteResourceHandle(
                                        for: command.resource_handle,
                                        occupiedHandles: occupied
                                    )
                            }
                            guard let paletteResource = resourceByHandle[paletteHandle],
                                  paletteResource.resource_kind == UInt32(GE_SOURCE_RESOURCE_V6_PALETTE),
                                  paletteResource.flags & UInt32(GE_SOURCE_RESOURCE_V6_FLAG_PALETTE) != 0 else {
                                throw GoldenEyeSourceSceneTextureBindingV6Error.resourceMetadataMismatch(
                                    command.resource_handle,
                                    "validated TLUT payload has no matching scene palette resource"
                                )
                            }
                        }
                        textureMetadata = binding.metadata
                        textureMipLevels = binding.metadata.mipLevels
                        textureUsesArray = true
                        resolvedTexture = binding.texture
                    } catch let error as GoldenEyeSourceSceneTextureBindingV6Error {
                        throw GoldenEyeSourceSceneRendererV6Error.unsupportedTextureState(
                            command.resource_handle,
                            error.description
                        )
                    }
                } else {
                    guard let legacyTexture = textureResolver(command.resource_handle) else {
                        throw GoldenEyeSourceSceneRendererV6Error.missingTexture(command.resource_handle)
                    }
                    resolvedTexture = legacyTexture
                    textureMipLevels = UInt32(expectedMipLevels)
                    if residentTextureHandles.insert(command.resource_handle).inserted {
                        legacyTexture.label = "GoldenEye.V6.SourceScene.Resource.\(command.resource_handle)"
                        state.sceneResidency.addAllocation(legacyTexture)
                        state.sceneResidency.commit()
                    }
                }
                if let textureMetadata {
                    guard resolvedTexture.mipmapLevelCount == 1,
                          resolvedTexture.textureType == .type2DArray,
                          resolvedTexture.arrayLength == Int(textureMetadata.metalArrayLength) else {
                        throw GoldenEyeSourceSceneRendererV6Error.unsupportedTextureState(
                            command.resource_handle,
                            "source levels=\(expectedMipLevels) actual Metal array=\(resolvedTexture.arrayLength) mipmapLevelCount=\(resolvedTexture.mipmapLevelCount)"
                        )
                    }
                } else if resolvedTexture.textureType == .type2DArray {
                    guard resolvedTexture.mipmapLevelCount == 1,
                          resolvedTexture.arrayLength == max(2, expectedMipLevels) else {
                        throw GoldenEyeSourceSceneRendererV6Error.unsupportedTextureState(
                            command.resource_handle,
                            "legacy array resolver levels=\(expectedMipLevels) array=\(resolvedTexture.arrayLength) mipmapLevelCount=\(resolvedTexture.mipmapLevelCount)"
                        )
                    }
                    textureUsesArray = true
                } else {
                    // Isolated diagnostic captures may still provide the old
                    // 2D resolver seam. Strict Release always takes the
                    // metadata-backed array path above.
                    guard resolvedTexture.mipmapLevelCount == expectedMipLevels,
                          resolvedTexture.textureType == .type2D else {
                        throw GoldenEyeSourceSceneRendererV6Error.unsupportedTextureState(
                            command.resource_handle,
                            "legacy texture resolver requires 2D mip chain levels=\(expectedMipLevels)"
                        )
                    }
                }
                let lodEnabled = ((renderState.raw_othermode_h >> 16) & 1) != 0
                // A source setup may retain the LOD-enable bit while its
                // selected material has maxLOD=0 (GoldenEye's 1x1 auxiliary
                // material).  That is a valid single-level source tile: the
                // shader's LOD path clamps both samples to level zero.  A
                // positive source maxLOD still requires the resident chain.
                if lodEnabled && expectedMipLevels < 2 && renderState.lod_max_q16 > 0 {
                    throw GoldenEyeSourceSceneRendererV6Error.unsupportedTextureState(
                        command.resource_handle,
                        "source texture LOD is enabled without a mip chain rawH=0x\(String(renderState.raw_othermode_h, radix: 16)) maxLOD=\(renderState.lod_max_q16) mipLevels=\(expectedMipLevels)"
                    )
                }
                if renderState.filter_mode == UInt32(GE_SOURCE_FILTER_V6_TRILINEAR),
                   expectedMipLevels < 2 {
                    throw GoldenEyeSourceSceneRendererV6Error.unsupportedTextureState(
                        command.resource_handle,
                        "trilinear filtering requires at least two resident mip levels"
                    )
                }
                texture = resolvedTexture
            } else if sourceUsesTexture {
                throw GoldenEyeSourceSceneRendererV6Error.unsupportedTextureState(
                    command.resource_handle,
                    "combiner selects TEXEL0/TEXEL1 without a source resource"
                )
            }

            let transform: simd_float4x4
            if command.transform_handle == 0 {
                transform = matrix_identity_float4x4
            } else if let sourceTransform = transformByHandle[command.transform_handle] {
                transform = Self.matrix(from: sourceTransform)
            } else {
                throw GoldenEyeSourceSceneRendererV6Error.missingTransform(command.transform_handle)
            }
            let variant = try pipeline.variant(
                for: effectiveRenderState,
                drawFlags: command.flags,
                hasTexture: hasTexture,
                textureMipLevels: textureMipLevels,
                textureArrayMode: textureUsesArray ? 1 : 0
            )
            let lightingContext = try GoldenEyeSourceSceneLightingContextV6(
                screen: lightingFrameContext.screen,
                stateHandle: renderState.state_handle,
                nativeTick: lightingFrameContext.nativeTick,
                sourceTimer: lightingFrameContext.sourceTimer,
                pairPhase: lightingFrameContext.pairPhase,
                modelView: sourceModelView,
                rawGeometryMode: rawGeometryMode
            )
            let lighting = try lightingProvider.binding(for: lightingContext)
            let uniforms = GPUUniforms(
                transform: transform,
                primitiveColor: Self.rgba(effectiveRenderState.primitive_rgba),
                environmentColor: Self.rgba(effectiveRenderState.environment_rgba),
                cycle0Color: SIMD4(
                    effectiveRenderState.cycle0_color_a,
                    effectiveRenderState.cycle0_color_b,
                    effectiveRenderState.cycle0_color_c,
                    effectiveRenderState.cycle0_color_d
                ),
                cycle0Alpha: SIMD4(
                    effectiveRenderState.cycle0_alpha_a,
                    effectiveRenderState.cycle0_alpha_b,
                    effectiveRenderState.cycle0_alpha_c,
                    effectiveRenderState.cycle0_alpha_d
                ),
                cycle1Color: SIMD4(
                    effectiveRenderState.cycle1_color_a,
                    effectiveRenderState.cycle1_color_b,
                    effectiveRenderState.cycle1_color_c,
                    effectiveRenderState.cycle1_color_d
                ),
                cycle1Alpha: SIMD4(
                    effectiveRenderState.cycle1_alpha_a,
                    effectiveRenderState.cycle1_alpha_b,
                    effectiveRenderState.cycle1_alpha_c,
                    effectiveRenderState.cycle1_alpha_d
                ),
                selectors: SIMD4(
                    effectiveRenderState.alpha_mode,
                    effectiveRenderState.combiner_cycle_count,
                    hasTexture ? 1 : 0,
                    command.flags
                ),
                ambientColor: lighting.ambientColor,
                directionalColor: lighting.directionalColor,
                directionalDirection: lighting.directionalDirection,
                reflectionRight: lighting.reflectionRight,
                reflectionUp: lighting.reflectionUp,
                normalTransform: lighting.normalTransform,
                lightingInfo: SIMD4(
                    lighting.rawGeometryMode,
                    lighting.flags,
                    lighting.sourceTimer,
                    lighting.pairPhase
                ),
                textureInfo: SIMD4(
                    textureMetadata?.mipLevels ?? min(textureMipLevels ?? 1, 7),
                    textureMetadata?.mipDimensionMode.rawValue ?? 0,
                    effectiveRenderState.wrap_s,
                    effectiveRenderState.wrap_t
                ),
                textureLevelDimensions: Self.textureLevelDimensions(
                    textureMetadata: textureMetadata,
                    fallbackWidth: texture?.width ?? 1,
                    fallbackHeight: texture?.height ?? 1,
                    fallbackMipLevels: min(textureMipLevels ?? 1, 7)
                ),
                fogInfo: fogInfo,
                presentationInfo: Self.presentationInfo(
                    screen: lightingFrameContext.screen,
                    treatment: presentationTreatment
                )
            )
            let sourceScissor = try outputLayout.sourceScissor(
                command: command,
                logicalWidth: snapshot.summary.logical_width,
                logicalHeight: snapshot.summary.logical_height
            )
            prepared.append(PreparedDraw(
                command: command,
                variant: variant,
                texture: texture,
                textureMetadata: textureMetadata,
                hasTexture: hasTexture,
                uniforms: uniforms,
                scissor: Self.metalScissor(sourceScissor, outputHeight: outputLayout.outputHeight)
            ))
        }
        return prepared
    }

    private static func textureLevelDimensions(
        textureMetadata: GoldenEyeSourceSceneTextureBindingMetadataV6?,
        fallbackWidth: Int,
        fallbackHeight: Int,
        fallbackMipLevels: UInt32
    ) -> (SIMD4<UInt32>, SIMD4<UInt32>, SIMD4<UInt32>, SIMD4<UInt32>, SIMD4<UInt32>, SIMD4<UInt32>, SIMD4<UInt32>) {
        var values = Array(repeating: SIMD4<UInt32>(repeating: 1), count: 7)
        if let textureMetadata {
            for index in 0..<min(7, textureMetadata.levelWidths.count) {
                values[index] = SIMD4(
                    textureMetadata.levelWidths[index],
                    textureMetadata.levelHeights[index],
                    0,
                    0
                )
            }
        } else {
            let width = UInt32(max(1, fallbackWidth))
            let height = UInt32(max(1, fallbackHeight))
            for level in 0..<min(7, Int(fallbackMipLevels)) {
                let divisor = UInt32(1) << UInt32(level)
                values[level] = SIMD4(
                    max(1, width / divisor),
                    max(1, height / divisor),
                    0,
                    0
                )
            }
        }
        return (
            values[0], values[1], values[2], values[3],
            values[4], values[5], values[6]
        )
    }

    /// x = treatment (0 source-faithful, 1 enhanced HD), y = material profile
    /// (1 Nintendo, 2 Rareware, 3 Cast), z = LOD bias, w = profile gain.
    /// Keeping this as a private GPU record means Enhanced HD cannot mutate the
    /// source scene hash or the fixed-width C ABI.
    private static func presentationInfo(
        screen: UInt32,
        treatment: GoldenEyeSourceScenePresentationTreatmentV6
    ) -> SIMD4<Float> {
        guard treatment.isEnhanced else { return SIMD4<Float>(repeating: 0) }
        let profile: Float
        let lodBias: Float
        let gain: Float
        switch screen {
        case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_NINTENDO):
            profile = 1
            lodBias = 0
            gain = 0
        case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_RAREWARE):
            profile = 2
            lodBias = -0.5
            gain = 0.75
        case UInt32(GE_SOURCE_FRAME_V6_SCREEN_CAST):
            profile = 3
            lodBias = 0
            gain = 1.125
        default:
            return SIMD4<Float>(repeating: 0)
        }
        return SIMD4(Float(treatment.rawValue), profile, lodBias, gain)
    }

    private static func rendererStateForSource(
        _ state: GESourceRenderStateV6,
        hasTexture: Bool,
        sourceScreen: UInt32
    ) -> GESourceRenderStateV6 {
        let zero = UInt32(GoldenEyeSourceSceneCombinerSelectorV6.zero)
        let combinedAlpha = UInt32(GoldenEyeSourceSceneCombinerSelectorV6.combinedAlpha)
        let lodFraction = UInt32(GoldenEyeSourceSceneCombinerSelectorV6.lodFraction)
        let isCanonicalGoldenEyeLOD =
            sourceScreen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GOLDENEYE) &&
            state.raw_othermode_h == 0x0011_2000 &&
            state.raw_othermode_l == 0x0c18_2048 &&
            state.combiner_cycle_count == 2 &&
            state.cycle0_color_a == UInt32(GoldenEyeSourceSceneCombinerSelectorV6.texel1) &&
            state.cycle0_color_b == UInt32(GoldenEyeSourceSceneCombinerSelectorV6.texel0) &&
            state.cycle0_color_c == lodFraction &&
            state.cycle0_color_d == UInt32(GoldenEyeSourceSceneCombinerSelectorV6.texel0) &&
            state.cycle0_alpha_a == UInt32(GoldenEyeSourceSceneCombinerSelectorV6.texel1) &&
            state.cycle0_alpha_b == UInt32(GoldenEyeSourceSceneCombinerSelectorV6.texel0) &&
            state.cycle0_alpha_c == lodFraction &&
            state.cycle0_alpha_d == UInt32(GoldenEyeSourceSceneCombinerSelectorV6.texel0) &&
            state.cycle1_color_a == UInt32(GoldenEyeSourceSceneCombinerSelectorV6.combined) &&
            state.cycle1_color_b == zero &&
            state.cycle1_color_c == UInt32(GoldenEyeSourceSceneCombinerSelectorV6.shade) &&
            state.cycle1_color_d == zero &&
            state.cycle1_alpha_a == UInt32(GoldenEyeSourceSceneCombinerSelectorV6.combined) &&
            state.cycle1_alpha_b == zero &&
            state.cycle1_alpha_c == UInt32(GoldenEyeSourceSceneCombinerSelectorV6.shade) &&
            state.cycle1_alpha_d == zero
        func lowerUnsupported(_ selector: UInt32) -> UInt32 {
            if sourceScreen == UInt32(GE_SOURCE_FRAME_V6_SCREEN_RAMROM) {
                // The partial stage-environment frame has no texture resource
                // yet; retain source SHADE/PRIMITIVE selectors so copied
                // vertex colors remain visible while bindings are pending.
                return selector
            }
            if sourceScreen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_LEGAL) {
                // Legal's source LOD mode is disabled; PRIM_LOD_FRAC/K5
                // literals therefore contribute zero in the authored
                // equations. The normalized key 15 is COMBINED_ALPHA in
                // other screens, but is not a Legal color LOD value.
                return selector <= zero ? selector : zero
            }
            if sourceScreen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_RAREWARE),
               selector == lodFraction {
                return selector
            }
            if isCanonicalGoldenEyeLOD, selector == lodFraction {
                return selector
            }
            return selector <= zero || selector == combinedAlpha ? selector : zero
        }
        let sourceState = state
        func clearUnusedSecondCycle(_ value: inout GESourceRenderStateV6) {
            guard value.combiner_cycle_count == 1 else { return }
            let unused = UInt32(GoldenEyeSourceSceneCombinerSelectorV6.zero)
            value.cycle1_color_a = unused
            value.cycle1_color_b = unused
            value.cycle1_color_c = unused
            value.cycle1_color_d = unused
            value.cycle1_alpha_a = unused
            value.cycle1_alpha_b = unused
            value.cycle1_alpha_c = unused
            value.cycle1_alpha_d = unused
        }
        if hasTexture {
            var value = sourceState
            value.cycle0_color_a = lowerUnsupported(value.cycle0_color_a)
            value.cycle0_color_b = lowerUnsupported(value.cycle0_color_b)
            value.cycle0_color_c = lowerUnsupported(value.cycle0_color_c)
            value.cycle0_color_d = lowerUnsupported(value.cycle0_color_d)
            value.cycle0_alpha_a = lowerUnsupported(value.cycle0_alpha_a)
            value.cycle0_alpha_b = lowerUnsupported(value.cycle0_alpha_b)
            value.cycle0_alpha_c = lowerUnsupported(value.cycle0_alpha_c)
            value.cycle0_alpha_d = lowerUnsupported(value.cycle0_alpha_d)
            value.cycle1_color_a = lowerUnsupported(value.cycle1_color_a)
            value.cycle1_color_b = lowerUnsupported(value.cycle1_color_b)
            value.cycle1_color_c = lowerUnsupported(value.cycle1_color_c)
            value.cycle1_color_d = lowerUnsupported(value.cycle1_color_d)
            value.cycle1_alpha_a = lowerUnsupported(value.cycle1_alpha_a)
            value.cycle1_alpha_b = lowerUnsupported(value.cycle1_alpha_b)
            value.cycle1_alpha_c = lowerUnsupported(value.cycle1_alpha_c)
            value.cycle1_alpha_d = lowerUnsupported(value.cycle1_alpha_d)
            clearUnusedSecondCycle(&value)
            return value
        }
        let selectors = [
            state.cycle0_color_a, state.cycle0_color_b,
            state.cycle0_color_c, state.cycle0_color_d,
            state.cycle0_alpha_a, state.cycle0_alpha_b,
            state.cycle0_alpha_c, state.cycle0_alpha_d,
            state.cycle1_color_a, state.cycle1_color_b,
            state.cycle1_color_c, state.cycle1_color_d,
            state.cycle1_alpha_a, state.cycle1_alpha_b,
            state.cycle1_alpha_c, state.cycle1_alpha_d,
        ]
        guard selectors.contains(where: { lowerUnsupported($0) != $0 }) else {
            return state
        }
        var value = sourceState
        let shade = UInt32(GoldenEyeSourceSceneCombinerSelectorV6.shade)
        value.cycle0_color_a = zero
        value.cycle0_color_b = zero
        value.cycle0_color_c = zero
        value.cycle0_color_d = shade
        value.cycle0_alpha_a = zero
        value.cycle0_alpha_b = zero
        value.cycle0_alpha_c = zero
        value.cycle0_alpha_d = shade
        value.cycle1_color_a = zero
        value.cycle1_color_b = zero
        value.cycle1_color_c = zero
        value.cycle1_color_d = zero
        value.cycle1_alpha_a = zero
        value.cycle1_alpha_b = zero
        value.cycle1_alpha_c = zero
        value.cycle1_alpha_d = zero
        clearUnusedSecondCycle(&value)
        return value
    }

    private static func stateUsesTexture(_ state: GESourceRenderStateV6) -> Bool {
        let values = [
            state.cycle0_color_a, state.cycle0_color_b, state.cycle0_color_c, state.cycle0_color_d,
            state.cycle0_alpha_a, state.cycle0_alpha_b, state.cycle0_alpha_c, state.cycle0_alpha_d,
            state.cycle1_color_a, state.cycle1_color_b, state.cycle1_color_c, state.cycle1_color_d,
            state.cycle1_alpha_a, state.cycle1_alpha_b, state.cycle1_alpha_c, state.cycle1_alpha_d,
        ]
        return values.contains(UInt32(GoldenEyeSourceSceneCombinerSelectorV6.texel0)) ||
            values.contains(UInt32(GoldenEyeSourceSceneCombinerSelectorV6.texel1)) ||
            values.contains(UInt32(GoldenEyeSourceSceneCombinerSelectorV6.lodFraction))
    }

    private static func stateUsesTexel1(_ state: GESourceRenderStateV6) -> Bool {
        let values = [
            state.cycle0_color_a, state.cycle0_color_b, state.cycle0_color_c, state.cycle0_color_d,
            state.cycle0_alpha_a, state.cycle0_alpha_b, state.cycle0_alpha_c, state.cycle0_alpha_d,
            state.cycle1_color_a, state.cycle1_color_b, state.cycle1_color_c, state.cycle1_color_d,
            state.cycle1_alpha_a, state.cycle1_alpha_b, state.cycle1_alpha_c, state.cycle1_alpha_d,
        ]
        return values.contains(UInt32(GoldenEyeSourceSceneCombinerSelectorV6.texel1))
    }

    private func writeReferenceCapture(
        bytes: Data,
        evidence: GoldenEyeSourceSceneRenderEvidenceV6,
        rawSHA256: String,
        to url: URL
    ) throws -> URL {
        let candidate = try validatedReferenceCaptureURL(url)
        let pngCandidate = candidate.deletingPathExtension().appendingPathExtension("png")
        guard pngCandidate != candidate else {
            throw GoldenEyeSourceSceneRendererV6Error.invalidReferenceCaptureURL(url)
        }
        try FileManager.default.createDirectory(
            at: candidate.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try bytes.write(to: candidate, options: .atomic)
        let pngURL = try validatedReferenceCaptureURL(pngCandidate)
        let pngData = try GoldenEyeReferenceCaptureCodecV6.encodePNG(
            bgra8: bytes,
            width: 320,
            height: 240,
            bytesPerRow: 320 * 4
        )
        try pngData.write(to: pngURL, options: .atomic)
        let metadata: [String: Any] = [
            "rawPath": candidate.path,
            "pngPath": pngURL.path,
            "rawSHA256": rawSHA256,
            "width": 320,
            "height": 240,
            "bytesPerRow": 320 * 4,
            "pixelFormat": "bgra8Unorm",
            "pngChannelOrder": "RGB from opaque BGRA8 via little-endian none-skip-first 32-bit pixels",
            "frameIndex": evidence.frameIndex,
            "nativeTick": evidence.nativeTick,
            "drawCount": evidence.drawCount,
            "metalDrawCount": evidence.metalDrawCount,
            "triangleCount": evidence.triangleCount,
            "copiedRecordAggregateHash": evidence.copiedRecordAggregateHash,
            "pipelineKeyHashes": evidence.pipelineKeyHashes,
            "sourceManifestHash": evidence.sourceManifestHash,
            "batchManifestHash": evidence.batchManifestHash,
            "cpuEncodeNanoseconds": evidence.cpuEncodeNanoseconds,
            "slotIndex": evidence.slotIndex,
            "signalValue": evidence.signalValue
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])
        try metadataData.write(to: candidate.appendingPathExtension("json"), options: .atomic)
        return pngURL
    }

    private func validatedReferenceCaptureURL(_ url: URL) throws -> URL {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let allowedRoot = root
            .appendingPathComponent("build", isDirectory: true)
            .appendingPathComponent("native", isDirectory: true)
            .resolvingSymlinksInPath()
        let candidate = (url.isFileURL ? url : root.appendingPathComponent(url.path))
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let allowedPrefix = allowedRoot.path.hasSuffix("/") ? allowedRoot.path : allowedRoot.path + "/"
        guard candidate.path.hasPrefix(allowedPrefix) else {
            throw GoldenEyeSourceSceneRendererV6Error.invalidReferenceCaptureURL(url)
        }
        return candidate
    }

    private func makeDepthTexture(slotIndex: Int, width: Int, height: Int) -> (any MTLTexture)? {
        if let existing = depthTextures[slotIndex], existing.width == width, existing.height == height {
            return existing
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .memoryless
        descriptor.usage = .renderTarget
        guard let texture = state.device.makeTexture(descriptor: descriptor) else {
            return nil
        }
        texture.label = "GoldenEye.V6.SourceScene.FrameSlot.\(slotIndex).Depth"
        depthTextures[slotIndex] = texture
        return texture
    }

    private static func matrix(from source: GESourceTransformV6) -> simd_float4x4 {
        let values: [Int32] = withUnsafeBytes(of: source.matrix_q16) { rawBytes in
            Array(rawBytes.bindMemory(to: Int32.self).prefix(16))
        }
        let scale: Float = 1.0 / 65_536.0
        return simd_float4x4(columns: (
            SIMD4(Float(values[0]) * scale, Float(values[1]) * scale, Float(values[2]) * scale, Float(values[3]) * scale),
            SIMD4(Float(values[4]) * scale, Float(values[5]) * scale, Float(values[6]) * scale, Float(values[7]) * scale),
            SIMD4(Float(values[8]) * scale, Float(values[9]) * scale, Float(values[10]) * scale, Float(values[11]) * scale),
            SIMD4(Float(values[12]) * scale, Float(values[13]) * scale, Float(values[14]) * scale, Float(values[15]) * scale)
        ))
    }

    private static func matrix(fromQ16 values: [Int32]) -> simd_float4x4 {
        precondition(values.count == 16)
        let scale: Float = 1.0 / 65_536.0
        return simd_float4x4(columns: (
            SIMD4(Float(values[0]) * scale, Float(values[1]) * scale, Float(values[2]) * scale, Float(values[3]) * scale),
            SIMD4(Float(values[4]) * scale, Float(values[5]) * scale, Float(values[6]) * scale, Float(values[7]) * scale),
            SIMD4(Float(values[8]) * scale, Float(values[9]) * scale, Float(values[10]) * scale, Float(values[11]) * scale),
            SIMD4(Float(values[12]) * scale, Float(values[13]) * scale, Float(values[14]) * scale, Float(values[15]) * scale)
        ))
    }

    private static func rgba(_ value: UInt32) -> SIMD4<Float> {
        SIMD4(
            Float((value >> 24) & 0xff) / 255.0,
            Float((value >> 16) & 0xff) / 255.0,
            Float((value >> 8) & 0xff) / 255.0,
            Float(value & 0xff) / 255.0
        )
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func metalScissor(
        _ rect: GoldenEyeSourceSceneRectV6,
        outputHeight: Int
    ) -> MTLScissorRect {
        return MTLScissorRect(
            x: rect.minX,
            y: outputHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private func appendStageTiming(_ line: String) {
        let url = URL(fileURLWithPath: "/tmp/goldeneye-source-product-renderer-v6-stage-timing.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            try? handle.write(contentsOf: Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url, options: .atomic)
        }
    }
}
