import Metal
import QuartzCore
import GoldenEyeNative

@available(macOS 26.0, *)
final class GoldenEyeMetalTriangleRenderer: GoldenEyeFrameRenderer, @unchecked Sendable {
    private struct GPUVertex {
        var position: SIMD2<Float>
        var color: SIMD4<Float>
    }

    private let state: GoldenEyeMetalDeviceState
    private let layer: CAMetalLayer
    private let pipeline: GoldenEyeBaselinePipeline
    private let vertexBuffer: any MTLBuffer
    private var frameIndex = 0
    private var nextSignalValue: UInt64 = 1
    private var lastSignalBySlot: [UInt64] = [0, 0]
    private var renderedFrames = 0
    private let normalizedPacket: GEGBINormalizationResultV1

    init(state: GoldenEyeMetalDeviceState, layer: CAMetalLayer, pipeline: GoldenEyeBaselinePipeline) throws {
        self.state = state
        self.layer = layer
        self.pipeline = pipeline
        let stream = ge_native_gbi_fixture_stream()
        let normalized = ge_native_normalize_gbi(stream)
        guard normalized.status == GE_STATUS_OK else {
            throw GoldenEyeBaselinePipelineError.creationFailed("M7 packet status \(normalized.status)")
        }
        self.normalizedPacket = normalized

        let sourceVertices = [
            normalized.packet.vertices.0,
            normalized.packet.vertices.1,
            normalized.packet.vertices.2,
        ]
        var gpuVertices = sourceVertices.map { vertex in
            GPUVertex(
                position: SIMD2<Float>(Float(vertex.x) / 320.0, Float(vertex.y) / 320.0),
                color: SIMD4<Float>(
                    Float(vertex.r) / 255.0,
                    Float(vertex.g) / 255.0,
                    Float(vertex.b) / 255.0,
                    Float(vertex.a) / 255.0
                )
            )
        }
        guard let vertexBuffer = Self.deviceBuffer(device: state.device, values: &gpuVertices) else {
            throw GoldenEyeBaselinePipelineError.creationFailed("triangle vertex buffer")
        }
        vertexBuffer.label = "GoldenEye.M8.Triangle.VertexBuffer"
        self.vertexBuffer = vertexBuffer
        state.sceneResidency.addAllocation(vertexBuffer)
        state.sceneResidency.commit()
        state.argumentTable.setAddress(vertexBuffer.gpuAddress, index: 0)
    }

    private static func deviceBuffer<T>(device: any MTLDevice, values: inout [T]) -> (any MTLBuffer)? {
        values.withUnsafeBytes { bytes in
            device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
        }
    }

    func renderFrame() -> Bool {
        let slotIndex = frameIndex % state.frameSlots.count
        let slot = state.frameSlots[slotIndex]
        let priorSignal = lastSignalBySlot[slotIndex]
        if priorSignal != 0 {
            guard state.completionEvent.wait(untilSignaledValue: priorSignal, timeoutMS: 1_000) else {
                print("GoldenEye M8 timed out waiting for slot \(slotIndex)")
                return false
            }
        }
        guard let drawable = layer.nextDrawable() else { return false }

        slot.allocator.reset()
        slot.commandBuffer.beginCommandBuffer(allocator: slot.allocator)
        slot.commandBuffer.useResidencySet(state.sceneResidency)
        slot.commandBuffer.useResidencySet(state.layerResidency)
        slot.commandBuffer.pushDebugGroup("GoldenEye.M8.Triangle.Frame.\(frameIndex)")
        let pass = MTL4RenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1)
        guard let encoder = slot.commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            slot.commandBuffer.popDebugGroup()
            slot.commandBuffer.endCommandBuffer()
            return false
        }
        encoder.label = "GoldenEye.M8.Triangle.RenderEncoder"
        encoder.setRenderPipelineState(pipeline.pipeline)
        encoder.setArgumentTable(state.argumentTable, stages: [.vertex, .fragment])
        encoder.pushDebugGroup("GoldenEye.M8.Triangle.Draw.0")
        encoder.drawPrimitives(
            primitiveType: .triangle,
            vertexStart: 0,
            vertexCount: Int(normalizedPacket.packet.vertex_count)
        )
        encoder.popDebugGroup()
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
        frameIndex += 1
        renderedFrames += 1
        if state.captureActive { state.stopCapture() }
        return true
    }

    func shutdown() {
        for value in lastSignalBySlot where value != 0 {
            _ = state.completionEvent.wait(untilSignaledValue: value, timeoutMS: 2_000)
        }
        try? "frames=\(renderedFrames) draws=\(renderedFrames) packetHash=\(normalizedPacket.packet_hash) lastSignal=\(nextSignalValue - 1) resourceAllocations=\(state.sceneResidency.allocationCount)\n".write(
            toFile: "/tmp/goldeneye-m8-triangle.log",
            atomically: true,
            encoding: .utf8
        )
    }
}
