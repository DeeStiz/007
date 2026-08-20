import Foundation
import Metal
import QuartzCore

/// Standalone M27 renderer for the bounded stage-background packet and its
/// additive source-environment packet. It owns a private GPU vertex buffer
/// and uploads copied vertices through a shared staging buffer. The packet
/// remains the authority for draw ranges; no source display-list pointer, ROM
/// address, or title packet enters this renderer.
@available(macOS 26.0, *)
final class GoldenEyeMetalStageBackgroundRenderer: GoldenEyeFrameRenderer,
    GoldenEyeDrawableFrameRenderer,
    GoldenEyeStageSourceEnvironmentFrameRendererV6,
    @unchecked Sendable
{
    private let state: GoldenEyeMetalDeviceState
    private let layer: CAMetalLayer
    private let pipeline: GoldenEyeStageBackgroundPipeline
    private var packet: GoldenEyeStageBackgroundDrawPacket
    private let vertexBuffer: any MTLBuffer
    private let stagingBuffer: any MTLBuffer
    private var uploadPending = true
    private var frameIndex = 0
    private var nextSignalValue: UInt64 = 1
    private var lastSignalBySlot: [UInt64] = [0, 0]
    private var renderedFrames = 0
    private var renderedDraws = 0
    private var lastError: String?
    private let vertexCapacity: Int

    init(
        state: GoldenEyeMetalDeviceState,
        layer: CAMetalLayer,
        pipeline: GoldenEyeStageBackgroundPipeline,
        assetRoot: URL,
        stageID: UInt32 = 33
    ) throws {
        self.state = state
        self.layer = layer
        self.pipeline = pipeline

        let catalog = try GoldenEyeStageAssetCatalog.load(stageAssetRoot: assetRoot)
        let scene = try GoldenEyeStageScenePacket.load(stageID: stageID, catalog: catalog)
        guard let viewport = GoldenEyeProjectionV10.ViewportV10(
            drawableWidth: GoldenEyeProjectionV10.canonicalWidth,
            drawableHeight: GoldenEyeProjectionV10.canonicalHeight
        ),
        let projection = GoldenEyeProjectionV10.PacketV10(
            viewport: viewport,
            modelView: .identity,
            projection: .identity
        ) else {
            throw GoldenEyeStageBackgroundDrawPacketError.invalidViewport
        }
        let packet: GoldenEyeStageBackgroundDrawPacket
        if ProcessInfo.processInfo.environment["GOLDENEYE_STAGE_SOURCE_ENVIRONMENT"] == "1" {
            packet = try GoldenEyeStageSourceEnvironmentDrawPacketBuilderV6.make(
                scene: scene,
                viewport: viewport,
                projection: projection
            )
        } else {
            packet = try GoldenEyeStageBackgroundDrawPacketBuilder.make(
                scene: scene,
                viewport: viewport,
                projection: projection
            )
        }
        self.packet = packet
        guard !packet.vertices.isEmpty else {
            throw GoldenEyeStageBackgroundPipelineError.creationFailed("empty stage background vertex packet")
        }

        let stride = MemoryLayout<GoldenEyeStageBackgroundDrawVertex>.stride
        let vertexCapacity = max(packet.vertices.count, 65_536)
        let vertexBytes = packet.vertices.count * stride
        guard let staging = state.device.makeBuffer(
            length: vertexCapacity * stride,
            options: .storageModeShared
        ) else {
            throw GoldenEyeStageBackgroundPipelineError.creationFailed("shared stage background staging buffer")
        }
        guard let privateVertices = state.device.makeBuffer(
            length: vertexCapacity * stride,
            options: .storageModePrivate
        ) else {
            throw GoldenEyeStageBackgroundPipelineError.creationFailed("private stage background vertex buffer")
        }
        guard vertexBytes == 0 || packet.vertices.withUnsafeBytes({ bytes in
            guard let baseAddress = bytes.baseAddress else { return false }
            staging.contents().copyMemory(from: baseAddress, byteCount: bytes.count)
            return true
        }) else {
            throw GoldenEyeStageBackgroundPipelineError.creationFailed("shared stage background vertex upload")
        }
        staging.label = "GoldenEye.M27.StageBackground.Vertices.Staging"
        privateVertices.label = "GoldenEye.M27.StageBackground.Vertices.Private"
        self.stagingBuffer = staging
        self.vertexBuffer = privateVertices
        self.vertexCapacity = vertexCapacity

        state.sceneResidency.addAllocation(staging)
        state.sceneResidency.addAllocation(privateVertices)
        state.sceneResidency.commit()
        state.argumentTable.setAddress(privateVertices.gpuAddress, index: 0)

        let diagnosticCodes = Set(packet.diagnostics.map { $0.code.rawValue }).sorted()
        try? (
            "init=1 stage=\(packet.stageID) rooms=\(packet.roomCount) portals=\(packet.portalCount) "
            + "commands=\(packet.commandCount) vertices=\(packet.vertexCount) "
            + "unsupportedMask=\(packet.unsupportedMask) diagnosticCodes=\(diagnosticCodes) "
            + "packetHash=\(packet.packetHash) sourceHash=\(packet.sourceHash) "
            + "scenePacketHash=\(packet.scenePacketHash) privateVertex=1 "
            + "privateVertexLabel=\(privateVertices.label ?? "") "
            + "privateVertexStoragePrivate=\(privateVertices.storageMode == .private ? 1 : 0) "
            + "stagingResident=1 resourceAllocations=\(state.sceneResidency.allocationCount)\n"
        ).write(
            toFile: "/tmp/goldeneye-m27-stage-background.log",
            atomically: true,
            encoding: .utf8
        )
    }

    /// Owner-side handoff for copied source portal/environment geometry. The
    /// packet remains explicitly unsupported for room triangles, props,
    /// characters, effects, and HUD, but these source portal polygons replace
    /// the old room-marker/portal-edge diagnostic workload when supplied.
    func submit(
        sourceEnvironmentPacket packet: GoldenEyeStageBackgroundDrawPacket,
        nativeTick: UInt64
    ) throws {
        guard packet.stageID == self.packet.stageID else {
            throw GoldenEyeStageBackgroundPipelineError.creationFailed(
                "source environment stage \(packet.stageID) does not match renderer stage \(self.packet.stageID)"
            )
        }
        guard packet.vertices.count <= vertexCapacity else {
            throw GoldenEyeStageBackgroundPipelineError.creationFailed(
                "source environment vertex capacity (packet.vertices.count) > (vertexCapacity)"
            )
        }
        let byteCount = packet.vertices.count * MemoryLayout<GoldenEyeStageBackgroundDrawVertex>.stride
        guard byteCount == 0 || packet.vertices.withUnsafeBytes({ bytes in
            guard let baseAddress = bytes.baseAddress else { return false }
            stagingBuffer.contents().copyMemory(from: baseAddress, byteCount: bytes.count)
            return true
        }) else {
            throw GoldenEyeStageBackgroundPipelineError.creationFailed(
                "source environment vertex upload"
            )
        }
        self.packet = packet
        uploadPending = true
        try? "sourceEnvironment=1 nativeTick=\(nativeTick) stage=\(packet.stageID) commands=\(packet.commands.count) vertices=\(packet.vertices.count) packetHash=\(packet.packetHash) unsupportedMask=\(packet.unsupportedMask)\n".write(
            toFile: "/tmp/goldeneye-m27-stage-background.log",
            atomically: false,
            encoding: .utf8
        )
    }

    func renderFrame() -> Bool {
        guard let drawable = layer.nextDrawable() else {
            lastError = "drawable unavailable"
            return false
        }
        let timing = GE120DisplayTiming(
            targetTimestamp: CACurrentMediaTime(),
            targetPresentationTimestamp: CACurrentMediaTime(),
            drawableWidth: drawable.texture.width,
            drawableHeight: drawable.texture.height,
            callbackSequence: UInt64(frameIndex)
        )
        return render(drawable: drawable, timing: timing)
    }

    func render(
        drawable: any CAMetalDrawable,
        timing: GE120DisplayTiming
    ) -> Bool {
        _ = timing
        let slotIndex = frameIndex % state.frameSlots.count
        let slot = state.frameSlots[slotIndex]
        let priorSignal = lastSignalBySlot[slotIndex]
        if priorSignal != 0,
           !state.completionEvent.wait(untilSignaledValue: priorSignal, timeoutMS: 1_000) {
            lastError = "timed out waiting for frame slot \(slotIndex)"
            return false
        }

        slot.allocator.reset()
        slot.commandBuffer.beginCommandBuffer(allocator: slot.allocator)
        slot.commandBuffer.useResidencySet(state.sceneResidency)
        slot.commandBuffer.useResidencySet(state.layerResidency)
        slot.commandBuffer.pushDebugGroup("GoldenEye.M27.StageBackground.Frame.\(frameIndex)")

        let uploadWasPending = uploadPending
        if uploadWasPending {
            guard let upload = slot.commandBuffer.makeComputeCommandEncoder() else {
                slot.commandBuffer.popDebugGroup()
                slot.commandBuffer.endCommandBuffer()
                lastError = "compute upload encoder unavailable"
                return false
            }
            upload.label = "GoldenEye.M27.StageBackground.VertexUpload"
            upload.copy(
                sourceBuffer: stagingBuffer,
                sourceOffset: 0,
                destinationBuffer: vertexBuffer,
                destinationOffset: 0,
                size: packet.vertices.count * MemoryLayout<GoldenEyeStageBackgroundDrawVertex>.stride
            )
            upload.endEncoding()
        }

        let pass = MTL4RenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(
            red: 0.012,
            green: 0.018,
            blue: 0.028,
            alpha: 1.0
        )
        guard let encoder = slot.commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            slot.commandBuffer.popDebugGroup()
            slot.commandBuffer.endCommandBuffer()
            lastError = "render encoder unavailable"
            return false
        }
        encoder.label = "GoldenEye.M27.StageBackground.RenderEncoder"
        if uploadWasPending {
            encoder.barrier(
                afterQueueStages: .blit,
                beforeStages: [.vertex, .fragment],
                visibilityOptions: .device
            )
        }
        encoder.setRenderPipelineState(pipeline.pipeline)
        state.argumentTable.setAddress(vertexBuffer.gpuAddress, index: 0)
        encoder.setArgumentTable(state.argumentTable, stages: [.vertex, .fragment])

        var frameDraws = 0
        for (drawIndex, command) in packet.commands.enumerated() {
            let end = Int(command.vertexStart) + Int(command.vertexCount)
            guard command.vertexCount > 0,
                  Int(command.vertexStart) < packet.vertices.count,
                  end <= packet.vertices.count else {
                encoder.endEncoding()
                slot.commandBuffer.popDebugGroup()
                slot.commandBuffer.endCommandBuffer()
                lastError = "malformed command range \(drawIndex)"
                return false
            }
            let primitive: MTLPrimitiveType
            switch command.primitive {
            case .roomMarker, .portalEdge:
                primitive = .line
            case .portalPolygon, .roomTriangle:
                primitive = .triangle
            }
            encoder.pushDebugGroup(
                "GoldenEye.M27.StageBackground.Draw.\(drawIndex).\(command.primitive.rawValue).Source.\(command.sourceIndex)"
            )
            encoder.drawPrimitives(
                primitiveType: primitive,
                vertexStart: Int(command.vertexStart),
                vertexCount: Int(command.vertexCount)
            )
            encoder.popDebugGroup()
            frameDraws += 1
        }
        encoder.endEncoding()
        slot.commandBuffer.popDebugGroup()
        slot.commandBuffer.endCommandBuffer()

        state.queue.waitForDrawable(drawable)
        state.queue.commit([slot.commandBuffer])
        let signalValue = nextSignalValue
        nextSignalValue &+= 1
        state.queue.signalEvent(state.completionEvent, value: signalValue)
        state.queue.signalDrawable(drawable)
        drawable.present()

        lastSignalBySlot[slotIndex] = signalValue
        uploadPending = false
        frameIndex += 1
        renderedFrames += 1
        renderedDraws += frameDraws
        if frameIndex == 1 || frameIndex % 60 == 0 {
            writeRuntimeEvidence()
        }
        if state.captureActive {
            state.stopCapture()
        }
        return true
    }

    func shutdown() {
        for value in lastSignalBySlot where value != 0 {
            _ = state.completionEvent.wait(untilSignaledValue: value, timeoutMS: 2_000)
        }
        writeRuntimeEvidence(shutdown: true)
    }

    private func writeRuntimeEvidence(shutdown: Bool = false) {
        let line = "status=\(lastError == nil ? 0 : 1) stage=\(packet.stageID) "
            + "rooms=\(packet.roomCount) portals=\(packet.portalCount) "
            + "commands=\(packet.commandCount) vertices=\(packet.vertexCount) "
            + "sourceEnvironment=\(packet.commands.contains { $0.primitive == .portalPolygon } ? 1 : 0) "
            + "portalTriangles=\(packet.commands.reduce(into: 0) { count, command in if command.primitive == .portalPolygon { count += 1 } }) "
            + "unsupportedMask=\(packet.unsupportedMask) packetHash=\(packet.packetHash) "
            + "privateVertex=1 uploadComplete=\(uploadPending ? 0 : 1) "
            + "privateVertexLabel=\(vertexBuffer.label ?? "") "
            + "privateVertexStoragePrivate=\(vertexBuffer.storageMode == .private ? 1 : 0) "
            + "frames=\(renderedFrames) draws=\(renderedDraws) "
            + "resourceAllocations=\(state.sceneResidency.allocationCount) "
            + "lastSignal=\(nextSignalValue - 1) shutdown=\(shutdown ? 1 : 0) "
            + "lastError=\(lastError ?? "none")\n"
        try? line.write(
            toFile: "/tmp/goldeneye-m27-stage-background.log",
            atomically: true,
            encoding: .utf8
        )
    }
}
