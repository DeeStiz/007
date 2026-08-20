import Foundation
import Metal
import QuartzCore

/// A supplied-drawable seam for CAMetalDisplayLink.  The display-link path
/// gives the owner an already-acquired drawable; implementations must submit,
/// signal, and present that drawable without calling nextDrawable().
@available(macOS 26.0, *)
protocol GoldenEyeSuppliedDrawableRenderer: AnyObject {
    func render(
        suppliedDrawable drawable: any CAMetalDrawable,
        timing: GE120DisplayTiming?
    ) -> Bool
}

@available(macOS 26.0, *)
enum GoldenEyeTitleRendererError: Error, CustomStringConvertible {
    case invalidAsset(String)
    case textureCreationFailed
    case samplerCreationFailed
    case uniformBufferCreationFailed(Int)
    case slotTimeout(Int)
    case drawableUnavailable
    case encoderUnavailable
    case computeEncoderUnavailable

    var description: String {
        switch self {
        case .invalidAsset(let detail):
            return "invalid GoldenEye title asset: \(detail)"
        case .textureCreationFailed:
            return "GoldenEye title texture creation failed"
        case .samplerCreationFailed:
            return "GoldenEye title sampler creation failed"
        case .uniformBufferCreationFailed(let index):
            return "GoldenEye title uniform buffer \(index) creation failed"
        case .slotTimeout(let index):
            return "GoldenEye title timed out waiting for frame slot \(index)"
        case .drawableUnavailable:
            return "GoldenEye title drawable unavailable"
        case .encoderUnavailable:
            return "GoldenEye title render encoder unavailable"
        case .computeEncoderUnavailable:
            return "GoldenEye title Metal 4 compute encoder unavailable"
        }
    }
}

/// The prepared gunbarrel asset is an N64 RLE-8 intensity image.  Its
/// preparation is external-ROM-only; runtime receives only the ignored,
/// hash-guarded extracted file under GOLDENEYE_NATIVE_ASSET_ROOT.
private struct GoldenEyeTitleAssetPack {
    let background: any MTLTexture
    let sampler: any MTLSamplerState
    let backgroundWidth: Int
    let backgroundHeight: Int
    let hasPreparedBackground: Bool
    let rarewareTexture: any MTLTexture
    let rarewareWidth: Int
    let rarewareHeight: Int
    let hasPreparedRareware: Bool
    let rarewarePacketHash: [UInt8]?
}

@available(macOS 26.0, *)
private struct GoldenEyeTitleGeometryResource {
    let packet: GoldenEyeTitleGeometryPacket
    let vertexBuffer: any MTLBuffer
    let indexBuffer: any MTLBuffer
}

@available(macOS 26.0, *)
private struct GoldenEyeTitleTextResource {
    let vertexBuffer: any MTLBuffer
    let indexBuffer: any MTLBuffer
    let vertexCount: Int
    let indexCount: Int
    let stringIDs: [Int]
    let bounds: [String]
}

@available(macOS 26.0, *)
private struct GoldenEyeTitleIconResource {
    let record: GoldenEyeTitleIconPacket.Record
    let texture: any MTLTexture
    let vertexBuffer: any MTLBuffer
    let indexBuffer: any MTLBuffer
    let indexCount: Int
}

/// A resident, source-derived GETT texture. The packet stores only copied
/// metadata and decoded RGBA8 bytes; the renderer owns a GPU-private shader
/// texture plus a shared staging buffer and keeps both in the long-lived scene
/// residency set until the renderer has drained the GPU during shutdown.
@available(macOS 26.0, *)
private struct GoldenEyeTitleTextureResource {
    let modelHandle: UInt32
    let resourceID: UInt32
    let width: Int
    let height: Int
    let recordCount: Int
    let decodedByteCount: Int
    let packetHash: [UInt8]
    let decodedHash: [UInt8]
    let sourceSFlags: UInt32
    let sourceTFlags: UInt32
    let texture: any MTLTexture
    let staging: any MTLBuffer
}

/// A bounded GETU corner stream paired with the first validated GETT
/// material for its model.  GETU is intentionally not a display-list
/// interpreter: only complete, material-homogeneous triangle groups with a
/// resident texture are uploaded.  Unsupported/material-unmatched corners
/// remain no-draw evidence in the shutdown log.
@available(macOS 26.0, *)
private struct GoldenEyeTitleUVResource {
    let modelHandle: UInt32
    let materialHandle: UInt32
    let packetRecordCount: Int
    let packetIndexCount: Int
    let drawIndexCount: Int
    let skippedRecordCount: Int
    let sourceCommandCount: UInt32
    let unsupportedCommandCount: UInt32
    let sourceHash: [UInt8]
    let packetHash: [UInt8]
    let vertexBuffer: any MTLBuffer
    let indexBuffer: any MTLBuffer
}

private struct GoldenEyeTitleUVGPUVertex: Sendable {
    /// Canonical logical-pixel position, not clip space.  The UV vertex
    /// shader applies the same 440x330 adaptive transform as title geometry.
    var position: SIMD2<Float>
    var uv: SIMD2<Float>
    var color: SIMD4<Float>
}

@available(macOS 26.0, *)
final class GoldenEyeMetalTitleRenderer: GoldenEyeFrameRenderer,
    GoldenEyeTitleSnapshotRenderer,
    GoldenEyeSuppliedDrawableRenderer,
    @unchecked Sendable
{
    private struct GPUUniforms {
        var screen: UInt32
        var subphase: UInt32
        var selection: UInt32
        var assetFlags: UInt32
        var timer120: UInt32
        var nativeTickLow: UInt32
        var nativeTickHigh: UInt32
        var reserved0: UInt32
        var viewportWidth: Float
        var viewportHeight: Float
        var logicalWidth: Float
        var logicalHeight: Float
        var titleXQ16: Float
        var titleRotationQ16: Float
        var titleScaleQ16: Float
        var alphaQ16: Float
        var titleLightQ8: Float
        var assetWidth: Float
        var assetHeight: Float
        var reserved1: Float
        var reserved2: Float
    }

    private struct UniformSlot {
        let buffer: any MTLBuffer
        let index: Int
    }

    private let state: GoldenEyeMetalDeviceState
    private let layer: CAMetalLayer
    private let pipeline: GoldenEyeTitlePipeline
    private let titleUVPipelineEnabled: Bool
    private let assets: GoldenEyeTitleAssetPack
    private let textCatalog: GoldenEyeTitleTextCatalog?
    private let nodePackets: [GoldenEyeTitleNodePacket]
    private let geometryResources: [UInt32: GoldenEyeTitleGeometryResource]
    private let textResources: [UInt32: GoldenEyeTitleTextResource]
    private let iconResources: [Int: GoldenEyeTitleIconResource]
    private let titleTextureResources: [UInt32: GoldenEyeTitleTextureResource]
    private let titleUVResources: [UInt32: GoldenEyeTitleUVResource]
    private let uniformSlots: [UniformSlot]
    private let lock = NSLock()
    private var latestSnapshot = GoldenEyeTitleSnapshot(
        nativeTick: 0,
        referenceTick: 0,
        pairPhase: 0,
        screen: .legal,
        subphase: 0,
        timer120: 0,
        gunbarrelTimer120: 0,
        titleXQ16: 0,
        titleRotationQ16: 0,
        titleScaleQ16: 0x0001_0000,
        alphaQ16: 0x0001_0000,
        titleLightQ8: 0x00ff,
        selection: 0,
        demoIndex: 0,
        stateHash: 0,
        renderHash: 0,
        audioHash: 0
    )
    private var frameIndex = 0
    private var nextSignalValue: UInt64 = 1
    private var lastSignalBySlot: [UInt64] = [0, 0]
    private var renderedFrames = 0
    private var renderedDraws = 0
    private var renderedScreenFrames: [UInt32: Int] = [:]
    private var lastAssetError: String?
    private var titleTextureUploadPending = false

    init(
        state: GoldenEyeMetalDeviceState,
        layer: CAMetalLayer,
        pipeline: GoldenEyeTitlePipeline,
        assetRoot: URL? = nil
    ) throws {
        self.state = state
        self.layer = layer
        self.pipeline = pipeline

        let pack = try Self.makeAssetPack(device: state.device, assetRoot: assetRoot)
        self.assets = pack
        self.textCatalog = assetRoot.flatMap { try? GoldenEyeTitleTextCatalog.load(assetRoot: $0) }
        if let assetRoot {
            let nodeRoot = assetRoot.appendingPathComponent("title", isDirectory: true)
            let nodeNames = ["legalpage", "nintendologo", "goldeneyelogo", "walletbond"]
            if nodeNames.allSatisfy({ FileManager.default.fileExists(atPath: nodeRoot.appendingPathComponent("\($0).getn").path) }) {
                self.nodePackets = try GoldenEyeTitleNodePacket.loadAll(from: nodeRoot)
            } else {
                self.nodePackets = []
            }
        } else {
            self.nodePackets = []
        }
        let geometryResources = try Self.makeGeometryResources(device: state.device, assetRoot: assetRoot)
        self.geometryResources = geometryResources
        let textResources = try Self.makePacketTextResources(device: state.device, assetRoot: assetRoot)
        self.textResources = textResources
        let iconResources = try Self.makeIconResources(device: state.device, assetRoot: assetRoot)
        self.iconResources = iconResources
        let titleTextureResources = try Self.makeTitleTextureResources(device: state.device, assetRoot: assetRoot)
        self.titleTextureResources = titleTextureResources
        let titleUVResources = try Self.makeTitleUVResources(
            device: state.device,
            assetRoot: assetRoot,
            titleTextureResources: titleTextureResources
        )
        self.titleUVResources = titleUVResources
        self.titleUVPipelineEnabled = ProcessInfo.processInfo.environment[
            "GOLDENEYE_TITLE_GETU_DRAW"
        ] == "1" && !titleUVResources.isEmpty

        var slots: [UniformSlot] = []
        slots.reserveCapacity(state.frameSlots.count)
        for index in 0..<state.frameSlots.count {
            guard let buffer = state.device.makeBuffer(
                length: MemoryLayout<GPUUniforms>.stride,
                options: .storageModeShared
            ) else {
                throw GoldenEyeTitleRendererError.uniformBufferCreationFailed(index)
            }
            buffer.label = "GoldenEye.M15.Title.Uniforms.Slot.\(index)"
            slots.append(UniformSlot(buffer: buffer, index: index))
            state.sceneResidency.addAllocation(buffer)
        }
        state.sceneResidency.addAllocation(pack.background)
        if !(pack.rarewareTexture === pack.background) {
            state.sceneResidency.addAllocation(pack.rarewareTexture)
        }
        for resource in geometryResources.values {
            state.sceneResidency.addAllocation(resource.vertexBuffer)
            state.sceneResidency.addAllocation(resource.indexBuffer)
        }
        for resource in textResources.values {
            state.sceneResidency.addAllocation(resource.vertexBuffer)
            state.sceneResidency.addAllocation(resource.indexBuffer)
        }
        for resource in iconResources.values {
            state.sceneResidency.addAllocation(resource.texture)
            state.sceneResidency.addAllocation(resource.vertexBuffer)
            state.sceneResidency.addAllocation(resource.indexBuffer)
        }
        for resource in titleTextureResources.values {
            state.sceneResidency.addAllocation(resource.texture)
            state.sceneResidency.addAllocation(resource.staging)
        }
        for resource in titleUVResources.values {
            state.sceneResidency.addAllocation(resource.vertexBuffer)
            state.sceneResidency.addAllocation(resource.indexBuffer)
        }
        state.sceneResidency.commit()
        self.uniformSlots = slots
        self.titleTextureUploadPending = !titleTextureResources.isEmpty
        self.lastAssetError = nil

        // The asset pack already owns a fallback-compatible texture.  Bind
        // the real sampler once; the argument table texture is rebound to the
        // prepared texture for every supplied-drawable frame.
        state.argumentTable.setSamplerState(pack.sampler.gpuResourceID, index: 0)
    }

    convenience init(
        state: GoldenEyeMetalDeviceState,
        layer: CAMetalLayer,
        pipeline: GoldenEyeTitlePipeline,
        bundle: Bundle = .main
    ) throws {
        let root: URL?
        if let value = ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_ASSET_ROOT"], !value.isEmpty {
            root = URL(fileURLWithPath: value, isDirectory: true)
        } else {
            root = nil
        }
        try self.init(state: state, layer: layer, pipeline: pipeline, assetRoot: root)
        _ = bundle
    }

    func submit(titleSnapshot: GoldenEyeTitleSnapshot) {
        lock.lock()
        latestSnapshot = titleSnapshot
        lock.unlock()
    }

    /// Compatibility adapter for the current timer/owner host.  The future
    /// CAMetalDisplayLink path must call `render(suppliedDrawable:timing:)` so
    /// it can consume the callback-owned drawable directly.
    func renderFrame() -> Bool {
        guard let drawable = layer.nextDrawable() else {
            lastAssetError = GoldenEyeTitleRendererError.drawableUnavailable.description
            return false
        }
        return render(suppliedDrawable: drawable, timing: nil)
    }

    func render(
        suppliedDrawable drawable: any CAMetalDrawable,
        timing: GE120DisplayTiming?
    ) -> Bool {
        let slotIndex = frameIndex % uniformSlots.count
        let priorSignal = lastSignalBySlot[slotIndex]
        if priorSignal != 0,
           !state.completionEvent.wait(untilSignaledValue: priorSignal, timeoutMS: 1_000) {
            lastAssetError = GoldenEyeTitleRendererError.slotTimeout(slotIndex).description
            return false
        }

        lock.lock()
        let snapshot = latestSnapshot
        lock.unlock()
        renderedScreenFrames[snapshot.screen.rawValue, default: 0] += 1

        let slot = state.frameSlots[slotIndex]
        let uniforms = makeUniforms(snapshot: snapshot, drawable: drawable)
        withUnsafeBytes(of: uniforms) { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            uniformSlots[slotIndex].buffer.contents().copyMemory(
                from: baseAddress,
                byteCount: bytes.count
            )
        }

        state.argumentTable.setAddress(uniformSlots[slotIndex].buffer.gpuAddress, index: 0)
        let titleTexture = titleTexture(for: snapshot.screen)
        let sourceTexture: any MTLTexture
        if let titleTexture {
            sourceTexture = titleTexture.texture
        } else if snapshot.screen == .rareware && assets.hasPreparedRareware {
            sourceTexture = assets.rarewareTexture
        } else {
            sourceTexture = assets.background
        }
        state.argumentTable.setTexture(sourceTexture.gpuResourceID, index: 0)

        slot.allocator.reset()
        slot.commandBuffer.beginCommandBuffer(allocator: slot.allocator)
        slot.commandBuffer.useResidencySet(state.sceneResidency)
        slot.commandBuffer.useResidencySet(state.layerResidency)
        slot.commandBuffer.pushDebugGroup("GoldenEye.M15.Title.Frame.\(frameIndex)")

        let uploadWasPending = titleTextureUploadPending
        guard encodePendingTitleTextureUploads(on: slot.commandBuffer) else {
            slot.commandBuffer.popDebugGroup()
            slot.commandBuffer.endCommandBuffer()
            return false
        }

        let pass = MTL4RenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = clearColor(for: snapshot.screen)
        guard let encoder = slot.commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            slot.commandBuffer.popDebugGroup()
            slot.commandBuffer.endCommandBuffer()
            lastAssetError = GoldenEyeTitleRendererError.encoderUnavailable.description
            return false
        }
        encoder.label = "GoldenEye.M15.Title.RenderEncoder"
        if uploadWasPending {
            encoder.barrier(
                afterQueueStages: .blit,
                beforeStages: [.vertex, .fragment],
                visibilityOptions: .device
            )
        }
        encoder.setRenderPipelineState(pipeline.pipeline)
        encoder.setArgumentTable(state.argumentTable, stages: [.vertex, .fragment])
        encoder.pushDebugGroup(
            "GoldenEye.M15.Title.Draw.Screen.\(snapshot.screen.rawValue).Tick.\(snapshot.nativeTick)"
        )
        if let titleTexture {
            encoder.pushDebugGroup(
                "GoldenEye.M8.Title.Texture.Model.\(titleTexture.modelHandle).Resource.\(titleTexture.resourceID).\(titleTexture.width)x\(titleTexture.height)"
            )
        }
        encoder.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: 3)
        if titleTexture != nil {
            encoder.popDebugGroup()
        }
        renderedDraws += 1

        // GETU is an additive, explicitly guarded corner/material lane.  It
        // is opt-in so the established fullscreen/GETT path remains the
        // production fallback while the partial source stream is audited.
        // Only triangles whose three corners share the resident primary GETT
        // material are uploaded; no unsupported display-list command is
        // synthesized here.
        if titleUVPipelineEnabled,
           let uvResource = titleUVResource(for: snapshot.screen),
           let material = titleTextureResources[uvResource.modelHandle],
           uvResource.drawIndexCount > 0 {
            state.argumentTable.setTexture(material.texture.gpuResourceID, index: 0)
            state.argumentTable.setAddress(uvResource.vertexBuffer.gpuAddress, index: 1)
            encoder.setRenderPipelineState(pipeline.uvPipeline)
            encoder.setArgumentTable(state.argumentTable, stages: [.vertex, .fragment])
            encoder.pushDebugGroup(
                "GoldenEye.M8.Title.GETU.Model.\(uvResource.modelHandle).Material.0x\(String(uvResource.materialHandle, radix: 16)).Indices.\(uvResource.drawIndexCount)"
            )
            encoder.drawIndexedPrimitives(
                primitiveType: .triangle,
                indexCount: uvResource.drawIndexCount,
                indexType: .uint32,
                indexBuffer: uvResource.indexBuffer.gpuAddress,
                indexBufferLength: uvResource.drawIndexCount * MemoryLayout<UInt32>.stride,
                instanceCount: 1,
                baseVertex: 0,
                baseInstance: 0
            )
            encoder.popDebugGroup()
            renderedDraws += 1
        }

        for (handle, _) in Self.geometryDraws(for: snapshot.screen) {
            guard let geometry = geometryResources[handle] else { continue }
            state.argumentTable.setAddress(geometry.vertexBuffer.gpuAddress, index: 1)
            encoder.setRenderPipelineState(pipeline.geometryPipeline)
            encoder.setArgumentTable(state.argumentTable, stages: [.vertex, .fragment])
            encoder.pushDebugGroup(
                "GoldenEye.M15.Title.Geometry.Handle.\(handle).Vertices.\(geometry.packet.vertices.count).Indices.\(geometry.packet.indices.count).MaterialFlags.0x\(String(geometry.packet.materialFlags, radix: 16)).ModelFlags.0x\(String(geometry.packet.modelFlags, radix: 16))"
            )
            encoder.drawIndexedPrimitives(
                primitiveType: .triangle,
                indexCount: geometry.packet.indices.count,
                indexType: .uint32,
                indexBuffer: geometry.indexBuffer.gpuAddress,
                indexBufferLength: geometry.packet.indices.count * MemoryLayout<UInt32>.stride,
                instanceCount: 1,
                baseVertex: 0,
                baseInstance: 0
            )
            encoder.popDebugGroup()
            renderedDraws += 1
        }
        if let text = textResources[snapshot.screen.rawValue] {
            state.argumentTable.setAddress(text.vertexBuffer.gpuAddress, index: 1)
            encoder.setRenderPipelineState(pipeline.geometryPipeline)
            encoder.setArgumentTable(state.argumentTable, stages: [.vertex, .fragment])
            encoder.pushDebugGroup(
                "GoldenEye.M15.Title.Text.Strings.\(text.stringIDs.map(String.init).joined(separator: ",")).GlyphVertices.\(text.vertexCount)"
            )
            encoder.drawIndexedPrimitives(
                primitiveType: .triangle,
                indexCount: text.indexCount,
                indexType: .uint32,
                indexBuffer: text.indexBuffer.gpuAddress,
                indexBufferLength: text.indexCount * MemoryLayout<UInt32>.stride,
                instanceCount: 1,
                baseVertex: 0,
                baseInstance: 0
            )
            encoder.popDebugGroup()
            renderedDraws += 1
        }
        if snapshot.screen == .fileSelect {
            // The source frontend draws the SELECT/COPY/ERASE controls at
            // these authored 440x330 centers and uses the 32x32 crosshair
            // for the initial cursor.  All seven packet rows are prepared;
            // these four are the rows reachable on the File Select surface.
            for icon in [
                GoldenEyeTitleIconPacket.Icon.selectFile,
                .copy,
                .erase,
                .crosshair,
            ] {
                guard let resource = iconResources[icon.rawValue] else { continue }
                state.argumentTable.setTexture(resource.texture.gpuResourceID, index: 0)
                state.argumentTable.setAddress(resource.vertexBuffer.gpuAddress, index: 1)
                encoder.setRenderPipelineState(pipeline.iconPipeline)
                encoder.setArgumentTable(state.argumentTable, stages: [.vertex, .fragment])
                encoder.pushDebugGroup("GoldenEye.M16.Title.Icon.\(icon.sourceName)")
                encoder.drawIndexedPrimitives(
                    primitiveType: .triangle,
                    indexCount: resource.indexCount,
                    indexType: .uint32,
                    indexBuffer: resource.indexBuffer.gpuAddress,
                    indexBufferLength: resource.indexCount * MemoryLayout<UInt32>.stride,
                    instanceCount: 1,
                    baseVertex: 0,
                    baseInstance: 0
                )
                encoder.popDebugGroup()
                renderedDraws += 1
            }
        }
        encoder.popDebugGroup()
        encoder.endEncoding()
        slot.commandBuffer.popDebugGroup()
        slot.commandBuffer.endCommandBuffer()

        // This is the Metal 4 supplied-drawable contract: wait before commit,
        // signal the drawable after submission, and present exactly once.
        state.queue.waitForDrawable(drawable)
        state.queue.commit([slot.commandBuffer])
        let signalValue = nextSignalValue
        nextSignalValue &+= 1
        if titleTextureUploadPending {
            // Keep the shared staging buffers resident for the lifetime of
            // this renderer. They are harmless after the one-time copy, and
            // retaining them avoids removing an allocation while a capture or
            // a delayed queue submission could still reference it.
            titleTextureUploadPending = false
        }
        state.queue.signalEvent(state.completionEvent, value: signalValue)
        state.queue.signalDrawable(drawable)
        drawable.present()

        lastSignalBySlot[slotIndex] = signalValue
        frameIndex += 1
        renderedFrames += 1
        if state.captureActive { state.stopCapture() }
        _ = timing
        return true
    }

    func shutdown() {
        for value in lastSignalBySlot where value != 0 {
            _ = state.completionEvent.wait(untilSignaledValue: value, timeoutMS: 2_000)
        }
        let error = lastAssetError ?? "none"
        let geometryEvidence = geometryResources.keys.sorted().compactMap { handle -> String? in
            guard let packet = geometryResources[handle] else { return nil }
            let source = packet.packet.sourceHash.map { String(format: "%02x", $0) }.joined()
            let payload = packet.packet.packetHash.map { String(format: "%02x", $0) }.joined()
            return "\(handle):vertices=\(packet.packet.vertices.count),indices=\(packet.packet.indices.count),materialFlags=0x\(String(packet.packet.materialFlags, radix: 16)),modelFlags=0x\(String(packet.packet.modelFlags, radix: 16)),source=\(source),packet=\(payload)"
        }.joined(separator: ";")
        let textEvidence = textResources.keys.sorted().compactMap { handle -> String? in
            guard let resource = textResources[handle] else { return nil }
            return "\(handle):vertices=\(resource.vertexCount),indices=\(resource.indexCount),bounds=\(resource.bounds.joined(separator: ";"))"
        }.joined(separator: ";")
        let screenFrameEvidence = renderedScreenFrames.keys.sorted().map { handle in
            "\(handle):\(renderedScreenFrames[handle] ?? 0)"
        }.joined(separator: ",")
        let iconEvidence = iconResources.values
            .sorted { $0.record.icon.rawValue < $1.record.icon.rawValue }
            .map { resource in
                let hash = resource.record.decodedHash.map { String(format: "%02x", $0) }.joined()
                return "\(resource.record.icon.sourceName):\(resource.record.width)x\(resource.record.height):\(hash)"
            }
            .joined(separator: ";")
        let titleTextureEvidence = titleTextureResources.values
            .sorted { ($0.modelHandle, $0.resourceID) < ($1.modelHandle, $1.resourceID) }
            .map { resource in
                let packetHash = resource.packetHash.map { String(format: "%02x", $0) }.joined()
                let decodedHash = resource.decodedHash.map { String(format: "%02x", $0) }.joined()
                return "model=\(resource.modelHandle):resource=\(resource.resourceID):\(resource.width)x\(resource.height):records=\(resource.recordCount):bytes=\(resource.decodedByteCount):packet=\(packetHash):decoded=\(decodedHash)"
            }
            .joined(separator: ";")
        let titleUVEvidence = titleUVResources.values
            .sorted { $0.modelHandle < $1.modelHandle }
            .map { resource in
                let sourceHash = resource.sourceHash.map { String(format: "%02x", $0) }.joined()
                let packetHash = resource.packetHash.map { String(format: "%02x", $0) }.joined()
                return "model=\(resource.modelHandle):material=0x\(String(resource.materialHandle, radix: 16)):records=\(resource.packetRecordCount):packetIndices=\(resource.packetIndexCount):drawIndices=\(resource.drawIndexCount):skippedRecords=\(resource.skippedRecordCount):commands=\(resource.sourceCommandCount):unsupported=\(resource.unsupportedCommandCount):source=\(sourceHash):packet=\(packetHash)"
            }
            .joined(separator: ";")
        let line = "frames=\(renderedFrames) draws=\(renderedDraws) "
            + "screenFrames=\(screenFrameEvidence) "
            + "preparedBackground=\(assets.hasPreparedBackground ? 1 : 0) "
            + "background=\(assets.backgroundWidth)x\(assets.backgroundHeight) "
            + "preparedRareware=\(assets.hasPreparedRareware ? 1 : 0) "
            + "rarewareTexture=\(assets.rarewareWidth)x\(assets.rarewareHeight) "
            + "rarewareTextureHash=\(assets.rarewarePacketHash?.map { String(format: "%02x", $0) }.joined() ?? "none") "
            + "titleTextCount=\(textCatalog?.strings.count ?? 0) "
            + "titleTextSHA256=\(textCatalog?.sourceSHA256 ?? "none") "
            + "titleNodeCount=\(nodePackets.count) titleNodeNodes=\(nodePackets.reduce(0) { $0 + $1.nodes.count }) titleNodeTextures=\(nodePackets.reduce(0) { $0 + $1.textures.count }) "
            + "geometryHandles=\(geometryResources.keys.sorted().map(String.init).joined(separator: ",")) "
            + "textHandles=\(textResources.keys.sorted().map(String.init).joined(separator: ",")) "
            + "titleIconCount=\(iconResources.count) titleIconEvidence=\(iconEvidence) "
            + "titleTextureCount=\(titleTextureResources.count) titleTextureEvidence=\(titleTextureEvidence) "
            + "titleTextureUploadPending=\(titleTextureUploadPending) "
            + "titleUVCount=\(titleUVResources.count) titleUVDrawEnabled=\(titleUVPipelineEnabled ? 1 : 0) titleUVEvidence=\(titleUVEvidence) "
            + "geometryEvidence=\(geometryEvidence) "
            + "textEvidence=\(textEvidence) "
            + "lastSignal=\(nextSignalValue - 1) lastError=\(error) "
            + "visualParity=not-claimed suppliedDrawable=1 compatibilityNextDrawable=1\n"
        var evidence = line
        for handle in geometryResources.keys.sorted() {
            guard let resource = geometryResources[handle] else { continue }
            evidence += "geometry_handle=\(handle) vertices=\(resource.packet.vertices.count) "
                + "indices=\(resource.packet.indices.count) commands=\(resource.packet.commandCount) "
                + "unsupported=\(resource.packet.unsupportedCommandCount) "
                + "materialFlags=0x\(String(resource.packet.materialFlags, radix: 16)) "
                + "modelFlags=0x\(String(resource.packet.modelFlags, radix: 16)) "
                + "dynamicVertexSegment=\(resource.packet.usesDynamicVertexSegment ? 1 : 0) "
                + "sourceHash=\(resource.packet.sourceHash.map { String(format: "%02x", $0) }.joined()) "
                + "packetHash=\(resource.packet.packetHash.map { String(format: "%02x", $0) }.joined())\n"
        }
        try? evidence.write(
            toFile: "/tmp/goldeneye-m15-title.log",
            atomically: true,
            encoding: .utf8
        )
    }

    private func makeUniforms(
        snapshot: GoldenEyeTitleSnapshot,
        drawable: any CAMetalDrawable
    ) -> GPUUniforms {
        let hasSourceGeometry = Self.geometryDraws(for: snapshot.screen)
            .contains { geometryResources[$0.0] != nil }
        let hasSourceText = textResources[snapshot.screen.rawValue] != nil
        let hasTitleTexture = titleTexture(for: snapshot.screen) != nil
        return GPUUniforms(
            screen: snapshot.screen.rawValue,
            subphase: snapshot.subphase,
            selection: UInt32(max(0, Int(snapshot.selection))),
            assetFlags: (assets.hasPreparedBackground ? 1 : 0)
                | (hasSourceGeometry || hasSourceText ? 2 : 0)
                | (snapshot.screen == .rareware && assets.hasPreparedRareware ? 4 : 0)
                | (!nodePackets.isEmpty ? 8 : 0)
                | (hasTitleTexture ? 16 : 0),
            timer120: snapshot.timer120,
            nativeTickLow: UInt32(truncatingIfNeeded: snapshot.nativeTick),
            nativeTickHigh: UInt32(truncatingIfNeeded: snapshot.nativeTick >> 32),
            reserved0: 0,
            viewportWidth: Float(drawable.texture.width),
            viewportHeight: Float(drawable.texture.height),
            logicalWidth: 440,
            logicalHeight: 330,
            titleXQ16: Float(snapshot.titleXQ16) / 65_536,
            titleRotationQ16: Float(snapshot.titleRotationQ16) / 65_536,
            titleScaleQ16: Float(snapshot.titleScaleQ16) / 65_536,
            alphaQ16: Float(snapshot.alphaQ16) / 65_536,
            titleLightQ8: Float(snapshot.titleLightQ8) / 255.0,
            assetWidth: Float(assets.backgroundWidth),
            assetHeight: Float(assets.backgroundHeight),
            reserved1: 0,
            reserved2: 0
        )
    }

    private func titleTexture(for screen: GoldenEyeTitleScreen) -> GoldenEyeTitleTextureResource? {
        switch screen {
        case .legal: return titleTextureResources[4]
        case .nintendo: return titleTextureResources[5]
        case .goldenEye: return titleTextureResources[3]
        case .fileSelect, .modeSelect: return titleTextureResources[6]
        default: return nil
        }
    }

    private func titleUVResource(for screen: GoldenEyeTitleScreen) -> GoldenEyeTitleUVResource? {
        switch screen {
        case .legal: return titleUVResources[4]
        case .nintendo: return titleUVResources[5]
        case .goldenEye: return titleUVResources[3]
        default: return nil
        }
    }

    /// Upload the guarded GETT payloads into their GPU-private textures once,
    /// before any title draw can sample them. Metal 4 performs texture copies
    /// on the compute encoder; the producer and consumer barriers make the
    /// copy-to-fragment dependency explicit on Apple TBDR devices.
    private func encodePendingTitleTextureUploads(
        on commandBuffer: any MTL4CommandBuffer
    ) -> Bool {
        guard titleTextureUploadPending else { return true }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            lastAssetError = GoldenEyeTitleRendererError.computeEncoderUnavailable.description
            return false
        }
        encoder.label = "GoldenEye.M8.Title.GETT.TextureUploadCompute"
        for resource in titleTextureResources.values.sorted(by: {
            ($0.modelHandle, $0.resourceID) < ($1.modelHandle, $1.resourceID)
        }) {
            encoder.copy(
                sourceBuffer: resource.staging,
                sourceOffset: 0,
                sourceBytesPerRow: resource.width * 4,
                sourceBytesPerImage: 0,
                sourceSize: MTLSize(width: resource.width, height: resource.height, depth: 1),
                destinationTexture: resource.texture,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
            )
        }
        let graphicsStages: MTLStages = [.vertex, .fragment]
        encoder.barrier(
            afterStages: .blit,
            beforeQueueStages: graphicsStages,
            visibilityOptions: .device
        )
        encoder.endEncoding()
        return true
    }

    private func clearColor(for screen: GoldenEyeTitleScreen) -> MTLClearColor {
        switch screen {
        case .legal: return MTLClearColor(red: 0.005, green: 0.005, blue: 0.008, alpha: 1)
        case .nintendo: return MTLClearColor(red: 0.19, green: 0.005, blue: 0.008, alpha: 1)
        case .rareware: return MTLClearColor(red: 0.003, green: 0.02, blue: 0.08, alpha: 1)
        case .gunbarrel: return MTLClearColor(red: 0.01, green: 0.01, blue: 0.01, alpha: 1)
        case .goldenEye: return MTLClearColor(red: 0.015, green: 0.011, blue: 0.004, alpha: 1)
        case .fileSelect: return MTLClearColor(red: 0.012, green: 0.018, blue: 0.03, alpha: 1)
        case .modeSelect: return MTLClearColor(red: 0.03, green: 0.018, blue: 0.006, alpha: 1)
        case .cast: return MTLClearColor(red: 0.004, green: 0.004, blue: 0.004, alpha: 1)
        case .ramrom: return MTLClearColor(red: 0.004, green: 0.02, blue: 0.008, alpha: 1)
        }
    }

    private static func geometryDraws(
        for screen: GoldenEyeTitleScreen
    ) -> [(UInt32, GoldenEyeTitleGeometryPlacement?)] {
        // The branded GETP rows are intentionally partial slices: their
        // unsupported source commands can describe texture-backed quads or
        // stateful rectangles that are not yet lowered by the native title
        // pipeline. Drawing those rows by default turns missing state into
        // opaque white blocks. Keep the packet loads and hashes for evidence,
        // but require an explicit diagnostic opt-in until M7-M11 provide the
        // complete model/material path.
        let allowPartialGeometry = ProcessInfo.processInfo.environment[
            "GOLDENEYE_TITLE_PARTIAL_GEOMETRY"
        ] == "1"
        switch screen {
        case .legal: return allowPartialGeometry ? [(4, nil)] : []
        case .nintendo: return allowPartialGeometry ? [(5, nil)] : []
        case .goldenEye: return allowPartialGeometry ? [(3, nil)] : []
        case .rareware: return allowPartialGeometry ? [(1, nil)] : []
        case .fileSelect: return [(6, nil)]
        case .gunbarrel:
            return [
                (8, .gunbarrelBody),
                (7, .gunbarrelHead),
                (9, .gunbarrelWeapon),
            ]
        default: return []
        }
    }

    private static func makeGeometryResources(
        device: any MTLDevice,
        assetRoot: URL?
    ) throws -> [UInt32: GoldenEyeTitleGeometryResource] {
        guard let titleRoot = assetRoot?.appendingPathComponent("title", isDirectory: true) else {
            return [:]
        }
        let packetNames: [(UInt32, String)] = [
            (1, "rarewarelogo"),
            (4, "legalpage"),
            (5, "nintendologo"),
            (3, "goldeneyelogo"),
            (6, "walletbond"),
            (7, "headbrosnansuit"),
            (8, "suitbond"),
            (9, "chrwppk"),
        ]
        var resources: [UInt32: GoldenEyeTitleGeometryResource] = [:]
        for (handle, name) in packetNames {
            let url = titleRoot.appendingPathComponent("\(name).gepk")
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let packet = try GoldenEyeTitleGeometryPacket.load(from: url)
            guard packet.modelHandle == handle else {
                throw GoldenEyeTitleRendererError.invalidAsset(
                    "geometry handle mismatch for \(name): expected \(handle), got \(packet.modelHandle)"
                )
            }
            let placement: GoldenEyeTitleGeometryPlacement? = switch handle {
            case 7: .gunbarrelHead
            case 8: .gunbarrelBody
            case 9: .gunbarrelWeapon
            default: nil
            }
            let vertices = packet.normalizedVertices(placement: placement)
            let vertexBytes = vertices.withUnsafeBytes { bytes -> (any MTLBuffer)? in
                guard let baseAddress = bytes.baseAddress else { return nil }
                return device.makeBuffer(bytes: baseAddress, length: bytes.count, options: .storageModeShared)
            }
            guard let vertexBuffer = vertexBytes else {
                throw GoldenEyeTitleRendererError.invalidAsset("geometry vertex buffer for \(name)")
            }
            let indices = packet.indices
            let indexBytes = indices.withUnsafeBytes { bytes -> (any MTLBuffer)? in
                guard let baseAddress = bytes.baseAddress else { return nil }
                return device.makeBuffer(bytes: baseAddress, length: bytes.count, options: .storageModeShared)
            }
            guard let indexBuffer = indexBytes else {
                throw GoldenEyeTitleRendererError.invalidAsset("geometry index buffer for \(name)")
            }
            vertexBuffer.label = "GoldenEye.M15.Title.Geometry.\(name).Vertices"
            indexBuffer.label = "GoldenEye.M15.Title.Geometry.\(name).Indices"
            resources[handle] = GoldenEyeTitleGeometryResource(
                packet: packet,
                vertexBuffer: vertexBuffer,
                indexBuffer: indexBuffer
            )
        }
        return resources
    }

    private static func makeTextResources(
        device: any MTLDevice,
        assetRoot: URL?
    ) throws -> [UInt32: GoldenEyeTitleTextResource] {
        guard let titleRoot = assetRoot?.appendingPathComponent("title", isDirectory: true) else { return [:] }
        let fontURL = titleRoot.appendingPathComponent("title-font.getf")
        let catalogURL = titleRoot.appendingPathComponent("LtitleE.gecat")
        guard FileManager.default.fileExists(atPath: fontURL.path),
              FileManager.default.fileExists(atPath: catalogURL.path) else { return [:] }
        let font = try GoldenEyeTitleFontPacket.load(from: fontURL)
        let catalog = try GoldenEyeTitleCatalogPacket.load(from: catalogURL)

        struct Placement {
            let x: Float
            let y: Float
            let horizontal: Int
            let vertical: Int
            let stringID: Int
        }
        let legal: [Placement] = [
            Placement(x: 220, y: 30, horizontal: 1, vertical: 1, stringID: 7),
            Placement(x: 34, y: 83, horizontal: 0, vertical: 1, stringID: 8),
            Placement(x: 226, y: 84, horizontal: 0, vertical: 1, stringID: 9),
            Placement(x: 226, y: 97, horizontal: 0, vertical: 1, stringID: 10),
            Placement(x: 226, y: 110, horizontal: 0, vertical: 1, stringID: 11),
            Placement(x: 226, y: 122, horizontal: 0, vertical: 1, stringID: 12),
            Placement(x: 227, y: 134, horizontal: 0, vertical: 1, stringID: 13),
            Placement(x: 219, y: 211, horizontal: 0, vertical: 1, stringID: 14),
            Placement(x: 60, y: 169, horizontal: 0, vertical: 1, stringID: 15),
            Placement(x: 60, y: 201, horizontal: 0, vertical: 1, stringID: 16),
            Placement(x: 99, y: 266, horizontal: 0, vertical: 1, stringID: 17),
            Placement(x: 80, y: 280, horizontal: 0, vertical: 1, stringID: 18),
        ]
        let fileSelect: [Placement] = [
            Placement(x: 106, y: 256, horizontal: 1, vertical: 0, stringID: 4),
            Placement(x: 220, y: 256, horizontal: 1, vertical: 0, stringID: 5),
            Placement(x: 334, y: 256, horizontal: 1, vertical: 0, stringID: 6),
            Placement(x: 285, y: 247, horizontal: 1, vertical: 0, stringID: 27),
            Placement(x: 357, y: 247, horizontal: 1, vertical: 0, stringID: 28),
        ]
        let modeSelect: [Placement] = [
            Placement(x: 170, y: 220, horizontal: 1, vertical: 0, stringID: 29),
            Placement(x: 170, y: 252, horizontal: 1, vertical: 0, stringID: 30),
        ]
        let layouts: [(UInt32, [Placement])] = [(0, legal), (5, fileSelect), (6, modeSelect)]
        var resources: [UInt32: GoldenEyeTitleTextResource] = [:]
        for (screen, placements) in layouts {
            var vertices: [GoldenEyeTitleGeometryGPUVertex] = []
            var indices: [UInt32] = []
            var stringIDs: [Int] = []
            for placement in placements {
                guard let text = catalog.string(at: placement.stringID) else { continue }
                stringIDs.append(placement.stringID)
                appendTextGeometry(
                    text,
                    at: SIMD2<Float>(placement.x, placement.y),
                    horizontal: placement.horizontal,
                    vertical: placement.vertical,
                    font: font,
                    vertices: &vertices,
                    indices: &indices
                )
            }
            guard !vertices.isEmpty, !indices.isEmpty else { continue }
            let vertexBuffer = vertices.withUnsafeBytes { bytes -> (any MTLBuffer)? in
                guard let baseAddress = bytes.baseAddress else { return nil }
                return device.makeBuffer(bytes: baseAddress, length: bytes.count, options: .storageModeShared)
            }
            let indexBuffer = indices.withUnsafeBytes { bytes -> (any MTLBuffer)? in
                guard let baseAddress = bytes.baseAddress else { return nil }
                return device.makeBuffer(bytes: baseAddress, length: bytes.count, options: .storageModeShared)
            }
            guard let vertexBuffer, let indexBuffer else {
                throw GoldenEyeTitleRendererError.invalidAsset("text buffer for screen \(screen)")
            }
            vertexBuffer.label = "GoldenEye.M15.Title.Text.Screen.\(screen).Vertices"
            indexBuffer.label = "GoldenEye.M15.Title.Text.Screen.\(screen).Indices"
            resources[screen] = GoldenEyeTitleTextResource(
                vertexBuffer: vertexBuffer,
                indexBuffer: indexBuffer,
                vertexCount: vertices.count,
                indexCount: indices.count,
                stringIDs: stringIDs,
                bounds: []
            )
        }
        return resources
    }

    private static func makePacketTextResources(
        device: any MTLDevice,
        assetRoot: URL?
    ) throws -> [UInt32: GoldenEyeTitleTextResource] {
        guard let assetRoot else { return [:] }
        let titleRoot = assetRoot.appendingPathComponent("title", isDirectory: true)
        let fontURL = titleRoot.appendingPathComponent("title-font.getf")
        let catalogURL = titleRoot.appendingPathComponent("LtitleE.gecat")
        guard FileManager.default.fileExists(atPath: fontURL.path),
              FileManager.default.fileExists(atPath: catalogURL.path) else { return [:] }
        let packet = try GoldenEyeTitleTextPacket.load(from: fontURL)
        let catalog = try GoldenEyeTitleCatalogPacket.load(from: catalogURL)
        var resources: [UInt32: GoldenEyeTitleTextResource] = [:]
        for screen in [UInt32(0), 5, 6] {
            let geometry = try packet.makeGeometry(screen: screen, catalog: catalog)
            guard !geometry.vertices.isEmpty, !geometry.indices.isEmpty else { continue }
            let vertexBuffer = geometry.vertices.withUnsafeBytes { bytes -> (any MTLBuffer)? in
                guard let baseAddress = bytes.baseAddress else { return nil }
                return device.makeBuffer(bytes: baseAddress, length: bytes.count, options: .storageModeShared)
            }
            let indexBuffer = geometry.indices.withUnsafeBytes { bytes -> (any MTLBuffer)? in
                guard let baseAddress = bytes.baseAddress else { return nil }
                return device.makeBuffer(bytes: baseAddress, length: bytes.count, options: .storageModeShared)
            }
            guard let vertexBuffer, let indexBuffer else {
                throw GoldenEyeTitleRendererError.invalidAsset("text packet buffers for screen \(screen)")
            }
            vertexBuffer.label = "GoldenEye.M16.Title.Text.Screen.\(screen).Vertices"
            indexBuffer.label = "GoldenEye.M16.Title.Text.Screen.\(screen).Indices"
            resources[screen] = GoldenEyeTitleTextResource(
                vertexBuffer: vertexBuffer,
                indexBuffer: indexBuffer,
                vertexCount: geometry.vertices.count,
                indexCount: geometry.indices.count,
                stringIDs: [],
                bounds: geometry.bounds
            )
        }
        return resources
    }

    private static func makeIconResources(
        device: any MTLDevice,
        assetRoot: URL?
    ) throws -> [Int: GoldenEyeTitleIconResource] {
        guard let assetRoot else { return [:] }
        let packetURL = assetRoot.appendingPathComponent("title/title-icons.geti")
        guard FileManager.default.fileExists(atPath: packetURL.path) else { return [:] }
        let packet = try GoldenEyeTitleIconPacket.load(from: packetURL)
        let centers: [GoldenEyeTitleIconPacket.Icon: SIMD2<Float>] = [
            .copy: SIMD2(225, 285),
            .erase: SIMD2(335, 285),
            .selectFile: SIMD2(110, 285),
            .crosshair: SIMD2(220, 165),
            // CHECK/DOT/X are retained and hash-validated for the later
            // source frontend surfaces; they are not placed on File Select.
            .check: SIMD2(280, 186),
            .dot: SIMD2(220, 165),
            .cursorX: SIMD2(220, 165),
        ]
        var resources: [Int: GoldenEyeTitleIconResource] = [:]
        let indices: [UInt32] = [0, 1, 2, 0, 2, 3]
        for icon in GoldenEyeTitleIconPacket.Icon.allCases {
            guard let record = packet.record(for: icon), let pixels = packet.pixels(for: icon),
                  let center = centers[icon] else { continue }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: record.width,
                height: record.height,
                mipmapped: false
            )
            descriptor.usage = [.shaderRead]
            descriptor.storageMode = .shared
            guard let texture = device.makeTexture(descriptor: descriptor) else {
                throw GoldenEyeTitleRendererError.textureCreationFailed
            }
            texture.label = "GoldenEye.M16.Title.Icon.\(icon.sourceName)"
            pixels.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.baseAddress else { return }
                texture.replace(
                    region: MTLRegionMake2D(0, 0, record.width, record.height),
                    mipmapLevel: 0,
                    withBytes: baseAddress,
                    bytesPerRow: record.width * 4
                )
            }
            let vertices = GoldenEyeTitleIconGeometry.quad(record: record, center: center)
            guard let vertexBuffer = vertices.withUnsafeBytes({ bytes -> (any MTLBuffer)? in
                guard let baseAddress = bytes.baseAddress else { return nil }
                return device.makeBuffer(bytes: baseAddress, length: bytes.count, options: .storageModeShared)
            }), let indexBuffer = indices.withUnsafeBytes({ bytes -> (any MTLBuffer)? in
                guard let baseAddress = bytes.baseAddress else { return nil }
                return device.makeBuffer(bytes: baseAddress, length: bytes.count, options: .storageModeShared)
            }) else {
                throw GoldenEyeTitleRendererError.invalidAsset("icon buffers for \(icon.sourceName)")
            }
            vertexBuffer.label = "GoldenEye.M16.Title.Icon.\(icon.sourceName).Vertices"
            indexBuffer.label = "GoldenEye.M16.Title.Icon.\(icon.sourceName).Indices"
            resources[icon.rawValue] = GoldenEyeTitleIconResource(
                record: record,
                texture: texture,
                vertexBuffer: vertexBuffer,
                indexBuffer: indexBuffer,
                indexCount: indices.count
            )
        }
        return resources
    }

    /// Load the additive GETT packets emitted by the guarded title-texture
    /// preparation lane.  The packet is little-endian, fixed-width, and
    /// contains decoded RGBA8 bytes; no source path, ROM address, or pointer
    /// is retained.  The renderer keeps the first visible record per model
    /// as the bounded fullscreen-material binding while validating every
    /// packet and record envelope before creating a Metal resource.
    private static func makeTitleTextureResources(
        device: any MTLDevice,
        assetRoot: URL?
    ) throws -> [UInt32: GoldenEyeTitleTextureResource] {
        guard let titleRoot = assetRoot?.appendingPathComponent("title", isDirectory: true) else {
            return [:]
        }
        let names = ["legalpage", "nintendologo", "goldeneyelogo", "walletbond"]
        guard names.allSatisfy({
            FileManager.default.fileExists(atPath: titleRoot.appendingPathComponent("\($0).gett").path)
        }) else {
            // When an explicit private asset root is supplied, a missing
            // GETT row is a preparation failure, not permission to silently
            // substitute a procedural material.  The nil-root path remains
            // available for the no-asset diagnostic host mode.
            throw GoldenEyeTitleRendererError.invalidAsset(
                "required GETT title texture packet is missing under \(titleRoot.path)"
            )
        }
        let packets = try GoldenEyeTitleTexturePacket.loadAll(from: titleRoot)
        var resources: [UInt32: GoldenEyeTitleTextureResource] = [:]
        for packet in packets {
            guard let record = packet.records.first else {
                throw GoldenEyeTitleRendererError.invalidAsset(
                    "GETT packet has no primary record for model \(packet.modelHandle)"
                )
            }
            // A packet is one model.  If preparation emitted a duplicate
            // packet for that handle, fail closed rather than silently
            // replacing a resident texture with an ambiguous payload.
            guard resources[packet.modelHandle] == nil else {
                throw GoldenEyeTitleRendererError.invalidAsset(
                    "duplicate GETT model handle \(packet.modelHandle)"
                )
            }
            let pixels = packet.rgba8(for: 0)
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: record.width,
                height: record.height,
                mipmapped: false
            )
            descriptor.usage = [.shaderRead]
            descriptor.storageMode = .private
            guard let texture = device.makeTexture(descriptor: descriptor) else {
                throw GoldenEyeTitleRendererError.textureCreationFailed
            }
            texture.label = "GoldenEye.M8.Title.GETT.Model.\(packet.modelHandle).Resource.\(record.resourceID)"
            guard let staging = pixels.withUnsafeBytes({ bytes -> (any MTLBuffer)? in
                guard let baseAddress = bytes.baseAddress else { return nil }
                return device.makeBuffer(
                    bytes: baseAddress,
                    length: bytes.count,
                    options: .storageModeShared
                )
            }) else {
                throw GoldenEyeTitleRendererError.invalidAsset(
                    "GETT staging buffer for model \(packet.modelHandle) resource \(record.resourceID)"
                )
            }
            staging.label = "GoldenEye.M8.Title.GETT.Model.\(packet.modelHandle).Resource.\(record.resourceID).Staging"
            resources[packet.modelHandle] = GoldenEyeTitleTextureResource(
                modelHandle: packet.modelHandle,
                resourceID: record.resourceID,
                width: record.width,
                height: record.height,
                recordCount: packet.records.count,
                decodedByteCount: packet.records.reduce(0) { $0 + $1.decodedByteCount },
                packetHash: packet.packetHash,
                decodedHash: record.decodedHash,
                sourceSFlags: record.sFlags,
                sourceTFlags: record.tFlags,
                texture: texture,
                staging: staging
            )
        }
        return resources
    }

    /// Build a deliberately narrow GPU stream from GETU.  The preparation
    /// packet is corner-expanded, so a material transition cannot inherit a
    /// texture from an adjacent source triangle.  This lane binds only the
    /// first validated GETT material for each branded model; unmatched
    /// materials (and mixed-material triangles) are counted and skipped.
    /// The existing fullscreen pass remains authoritative unless
    /// GOLDENEYE_TITLE_GETU_DRAW=1 is explicitly set.
    private static func makeTitleUVResources(
        device: any MTLDevice,
        assetRoot: URL?,
        titleTextureResources: [UInt32: GoldenEyeTitleTextureResource]
    ) throws -> [UInt32: GoldenEyeTitleUVResource] {
        guard let titleRoot = assetRoot?.appendingPathComponent("title", isDirectory: true) else {
            return [:]
        }
        let names = ["legalpage", "nintendologo", "goldeneyelogo"]
        let existing = names.filter {
            FileManager.default.fileExists(atPath: titleRoot.appendingPathComponent("\($0).getu").path)
        }
        guard existing.isEmpty || existing.count == names.count else {
            throw GoldenEyeTitleRendererError.invalidAsset(
                "GETU title UV packet set is incomplete under \(titleRoot.path)"
            )
        }
        guard !existing.isEmpty else { return [:] }

        let packets = try GoldenEyeTitleUVPacket.loadAll(from: titleRoot)
        var resources: [UInt32: GoldenEyeTitleUVResource] = [:]
        for packet in packets {
            guard let texture = titleTextureResources[packet.modelHandle] else {
                throw GoldenEyeTitleRendererError.invalidAsset(
                    "GETU model \(packet.modelHandle) has no validated GETT material"
                )
            }
            guard resources[packet.modelHandle] == nil else {
                throw GoldenEyeTitleRendererError.invalidAsset(
                    "duplicate GETU model handle \(packet.modelHandle)"
                )
            }
            guard packet.records.count % 3 == 0,
                  packet.indices.count == packet.records.count else {
                throw GoldenEyeTitleRendererError.invalidAsset(
                    "GETU model \(packet.modelHandle) triangle/index count"
                )
            }

            var minX = Int32.max
            var maxX = Int32.min
            var minY = Int32.max
            var maxY = Int32.min
            for record in packet.records {
                minX = min(minX, record.position.x)
                maxX = max(maxX, record.position.x)
                minY = min(minY, record.position.y)
                maxY = max(maxY, record.position.y)
            }
            let sourceWidth = max(Int64(maxX) - Int64(minX), 1)
            let sourceHeight = max(Int64(maxY) - Int64(minY), 1)
            let halfExtent = titleUVHalfExtent(for: packet.modelHandle)

            var vertices: [GoldenEyeTitleUVGPUVertex] = []
            var indices: [UInt32] = []
            vertices.reserveCapacity(packet.records.count)
            indices.reserveCapacity(packet.records.count)
            var skippedRecords = 0
            var firstMaterial: UInt32?

            for triangleStart in stride(from: 0, to: packet.records.count, by: 3) {
                let corners = packet.records[triangleStart..<(triangleStart + 3)]
                guard let first = corners.first,
                      corners.allSatisfy({ $0.materialHandle == first.materialHandle }) else {
                    skippedRecords += 3
                    continue
                }
                guard first.materialHandle == texture.resourceID else {
                    skippedRecords += 3
                    continue
                }
                firstMaterial = firstMaterial ?? first.materialHandle
                let base = UInt32(vertices.count)
                for record in corners {
                    let xOffset = Float(Int64(record.position.x) - Int64(minX)) / Float(sourceWidth)
                    let yOffset = Float(Int64(maxY) - Int64(record.position.y)) / Float(sourceHeight)
                    let position = SIMD2<Float>(
                        220 + (xOffset * 2 - 1) * halfExtent.x,
                        165 + (yOffset * 2 - 1) * halfExtent.y
                    )
                    let uv = SIMD2<Float>(
                        titleUVCoordinate(
                            record.s,
                            extent: texture.width,
                            sourceFlags: texture.sourceSFlags
                        ),
                        titleUVCoordinate(
                            record.t,
                            extent: texture.height,
                            sourceFlags: texture.sourceTFlags
                        )
                    )
                    vertices.append(
                        GoldenEyeTitleUVGPUVertex(
                            position: position,
                            uv: uv,
                            color: SIMD4<Float>(repeating: 1)
                        )
                    )
                }
                indices.append(contentsOf: [base, base + 1, base + 2])
            }

            guard let materialHandle = firstMaterial, !vertices.isEmpty, !indices.isEmpty else {
                // Keep the boundary explicit in preparation evidence rather
                // than creating a zero-length Metal allocation.
                continue
            }
            guard let vertexBuffer = vertices.withUnsafeBytes({ bytes -> (any MTLBuffer)? in
                guard let baseAddress = bytes.baseAddress else { return nil }
                return device.makeBuffer(bytes: baseAddress, length: bytes.count, options: .storageModeShared)
            }), let indexBuffer = indices.withUnsafeBytes({ bytes -> (any MTLBuffer)? in
                guard let baseAddress = bytes.baseAddress else { return nil }
                return device.makeBuffer(bytes: baseAddress, length: bytes.count, options: .storageModeShared)
            }) else {
                throw GoldenEyeTitleRendererError.invalidAsset(
                    "GETU GPU buffers for model \(packet.modelHandle)"
                )
            }
            vertexBuffer.label = "GoldenEye.M8.Title.GETU.Model.\(packet.modelHandle).Vertices"
            indexBuffer.label = "GoldenEye.M8.Title.GETU.Model.\(packet.modelHandle).Indices"
            resources[packet.modelHandle] = GoldenEyeTitleUVResource(
                modelHandle: packet.modelHandle,
                materialHandle: materialHandle,
                packetRecordCount: packet.records.count,
                packetIndexCount: packet.indices.count,
                drawIndexCount: indices.count,
                skippedRecordCount: skippedRecords,
                sourceCommandCount: packet.sourceCommandCount,
                unsupportedCommandCount: packet.unsupportedCommandCount,
                sourceHash: packet.sourceHash,
                packetHash: packet.packetHash,
                vertexBuffer: vertexBuffer,
                indexBuffer: indexBuffer
            )
        }
        return resources
    }

    private static func titleUVHalfExtent(for modelHandle: UInt32) -> SIMD2<Float> {
        switch modelHandle {
        case 4: return SIMD2<Float>(167, 113)
        case 5: return SIMD2<Float>(96, 52)
        case 3: return SIMD2<Float>(126, 78)
        default: return SIMD2<Float>(120, 72)
        }
    }

    private static func titleUVCoordinate(
        _ value: Int32,
        extent: Int,
        sourceFlags: UInt32
    ) -> Float {
        let denominator = Float(max(extent, 1) * 32)
        let coordinate = Float(value) / denominator
        // Clamp rows are explicit in ModelFileTextures.  Wrap/mirror rows
        // are still bounded to the sampler's edge contract in this partial
        // lane; no unbounded source addressing crosses the ABI.
        if sourceFlags == 2 {
            return min(max(coordinate, 0), 1)
        }
        return min(max(coordinate, 0), 1)
    }

    private static func appendTextGeometry(
        _ text: String,
        at origin: SIMD2<Float>,
        horizontal: Int,
        vertical: Int,
        font: GoldenEyeTitleFontPacket,
        vertices: inout [GoldenEyeTitleGeometryGPUVertex],
        indices: inout [UInt32]
    ) {
        let lineGlyph = font.glyphs[0x5B - 0x21]
        let lineHeight = Float(lineGlyph.baseline + lineGlyph.height)
        var width: Float = 0
        var lineWidth: Float = 0
        var lineCount = 1
        var previous = 0x48
        for character in text {
            if character == " " { lineWidth += 5; previous = 0x48; continue }
            if character == "\n" {
                width = max(width, lineWidth)
                lineWidth = 0
                lineCount += 1
                previous = 0x48
                continue
            }
            guard let glyph = font.glyph(for: character) else { continue }
            let previousGlyph = font.glyphs[previous - 0x21]
            let kern = font.kerning[Int(previousGlyph.kerningIndex) * 13 + Int(glyph.kerningIndex)]
            lineWidth += Float(glyph.width - kern + 1)
            previous = Int(glyph.character)
        }
        width = max(width, lineWidth)
        let totalHeight = lineHeight * Float(lineCount)
        let startX = origin.x - (horizontal == 1 ? width * 0.5 : 0)
        let startY = origin.y - (vertical == 1 ? totalHeight * 0.5 : 0)
        var cursor = SIMD2<Float>(startX, startY)
        previous = 0x48
        for character in text {
            if character == " " { cursor.x += 5; previous = 0x48; continue }
            if character == "\n" {
                cursor.x = startX
                cursor.y += lineHeight
                previous = 0x48
                continue
            }
            guard let glyph = font.glyph(for: character) else { continue }
            let previousGlyph = font.glyphs[previous - 0x21]
            let kern = font.kerning[Int(previousGlyph.kerningIndex) * 13 + Int(glyph.kerningIndex)]
            let bitmap = font.bitmap(for: glyph)
            for row in 0..<Int(glyph.height) {
                for column in 0..<Int(glyph.width) {
                    let intensity = bitmap[row * glyph.stride + column]
                    guard intensity > 4 else { continue }
                    let x = cursor.x + Float(column)
                    let y = cursor.y + Float(glyph.baseline) + Float(row)
                    let x0 = x / 440 * 2 - 1
                    let x1 = (x + 1) / 440 * 2 - 1
                    let y0 = 1 - y / 330 * 2
                    let y1 = 1 - (y + 1) / 330 * 2
                    let color = SIMD4<Float>(repeating: Float(intensity) / 255)
                    let base = UInt32(vertices.count)
                    vertices.append(GoldenEyeTitleGeometryGPUVertex(position: SIMD2(x0, y0), color: color))
                    vertices.append(GoldenEyeTitleGeometryGPUVertex(position: SIMD2(x1, y0), color: color))
                    vertices.append(GoldenEyeTitleGeometryGPUVertex(position: SIMD2(x1, y1), color: color))
                    vertices.append(GoldenEyeTitleGeometryGPUVertex(position: SIMD2(x0, y1), color: color))
                    indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
                }
            }
            cursor.x += Float(glyph.width - kern + 1)
            previous = Int(glyph.character)
        }
    }

    private static func makeAssetPack(
        device: any MTLDevice,
        assetRoot: URL?
    ) throws -> GoldenEyeTitleAssetPack {
        let titleRoot = assetRoot?.appendingPathComponent("title", isDirectory: true)
        let backgroundURL = titleRoot?.appendingPathComponent("gunbarrel-background.bin")
        let decoded: (width: Int, height: Int, pixels: [UInt8])
        if let backgroundURL, let data = try? Data(contentsOf: backgroundURL) {
            decoded = try decodeRLE8(data)
        } else {
            decoded = (1, 1, [0])
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: decoded.width,
            height: decoded.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw GoldenEyeTitleRendererError.textureCreationFailed
        }
        texture.label = decoded.width > 1
            ? "GoldenEye.M15.Title.PreparedGunbarrelIntensity"
            : "GoldenEye.M15.Title.FallbackIntensity"
        texture.replace(
            region: MTLRegionMake2D(0, 0, decoded.width, decoded.height),
            mipmapLevel: 0,
            withBytes: decoded.pixels,
            bytesPerRow: decoded.width
        )

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .notMipmapped
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            throw GoldenEyeTitleRendererError.samplerCreationFailed
        }
        let rarewarePacket: GoldenEyeRarewareTexturePacket?
        if let titleRoot {
            let textureURL = titleRoot.appendingPathComponent("rarewarelogo.getx")
            if FileManager.default.fileExists(atPath: textureURL.path) {
                rarewarePacket = try GoldenEyeRarewareTexturePacket.load(from: textureURL)
            } else {
                rarewarePacket = nil
            }
        } else {
            rarewarePacket = nil
        }
        let rarewareTexture: any MTLTexture
        if let rarewarePacket {
            let rarewareDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: rarewarePacket.width,
                height: rarewarePacket.height,
                mipmapped: false
            )
            rarewareDescriptor.usage = [.shaderRead]
            rarewareDescriptor.storageMode = .shared
            guard let texture = device.makeTexture(descriptor: rarewareDescriptor) else {
                throw GoldenEyeTitleRendererError.textureCreationFailed
            }
            texture.label = "GoldenEye.M15.Title.PreparedRarewareAtlas"
            texture.replace(
                region: MTLRegionMake2D(0, 0, rarewarePacket.width, rarewarePacket.height),
                mipmapLevel: 0,
                withBytes: rarewarePacket.rgba8,
                bytesPerRow: rarewarePacket.width * 4
            )
            rarewareTexture = texture
        } else {
            rarewareTexture = texture
        }
        return GoldenEyeTitleAssetPack(
            background: texture,
            sampler: sampler,
            backgroundWidth: decoded.width,
            backgroundHeight: decoded.height,
            hasPreparedBackground: decoded.width > 1,
            rarewareTexture: rarewareTexture,
            rarewareWidth: rarewarePacket?.width ?? decoded.width,
            rarewareHeight: rarewarePacket?.height ?? decoded.height,
            hasPreparedRareware: rarewarePacket != nil,
            rarewarePacketHash: rarewarePacket?.packetHash
        )
    }

    private static func decodeRLE8(_ data: Data) throws -> (width: Int, height: Int, pixels: [UInt8]) {
        guard data.count >= 10 else {
            throw GoldenEyeTitleRendererError.invalidAsset("RLE header is truncated")
        }
        let width = Int(UInt16(data[0]) << 8 | UInt16(data[1]))
        let height = Int(UInt16(data[2]) << 8 | UInt16(data[3]))
        guard width > 0, height > 0, width <= 440, height <= 330 else {
            throw GoldenEyeTitleRendererError.invalidAsset("RLE dimensions \(width)x\(height)")
        }
        let pixelCount = width.multipliedReportingOverflow(by: height)
        guard !pixelCount.overflow else {
            throw GoldenEyeTitleRendererError.invalidAsset("RLE dimensions overflow")
        }
        var output: [UInt8] = []
        output.reserveCapacity(pixelCount.partialValue)
        var cursor = 10
        while output.count < pixelCount.partialValue {
            guard cursor + 1 < data.count else {
                throw GoldenEyeTitleRendererError.invalidAsset("RLE stream ends at \(output.count) pixels")
            }
            let count = Int(data[cursor])
            let value = data[cursor + 1]
            cursor += 2
            guard count > 0, output.count + count <= pixelCount.partialValue else {
                throw GoldenEyeTitleRendererError.invalidAsset("RLE run exceeds \(width)x\(height)")
            }
            output.append(contentsOf: repeatElement(value, count: count))
        }
        return (width, height, output)
    }
}

@available(macOS 26.0, *)
extension GoldenEyeMetalTitleRenderer: GoldenEyeDrawableFrameRenderer {
    func render(drawable: any CAMetalDrawable, timing: GE120DisplayTiming) -> Bool {
        render(suppliedDrawable: drawable, timing: timing)
    }
}
