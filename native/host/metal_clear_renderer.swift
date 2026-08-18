import Metal
import QuartzCore

protocol GoldenEyeFrameRenderer: AnyObject, Sendable {
    func renderFrame() -> Bool
    func shutdown()
}

@available(macOS 26.0, *)
final class GoldenEyeMetalClearRenderer: GoldenEyeFrameRenderer, @unchecked Sendable {
    private let state: GoldenEyeMetalDeviceState
    private let layer: CAMetalLayer
    private var frameIndex = 0
    private var nextSignalValue: UInt64 = 1
    private var lastSignalBySlot: [UInt64] = [0, 0]
    private var renderedFrames = 0

    init(state: GoldenEyeMetalDeviceState, layer: CAMetalLayer) {
        self.state = state
        self.layer = layer
    }

    func renderFrame() -> Bool {
        let slotIndex = frameIndex % state.frameSlots.count
        let slot = state.frameSlots[slotIndex]
        let priorSignal = lastSignalBySlot[slotIndex]
        if priorSignal != 0 {
            guard state.completionEvent.wait(untilSignaledValue: priorSignal, timeoutMS: 1_000) else {
                print("GoldenEye M5 timed out waiting for slot \(slotIndex)")
                return false
            }
        }

        guard let drawable = layer.nextDrawable() else {
            print("GoldenEye M5 failed to acquire drawable")
            return false
        }

        slot.allocator.reset()
        slot.commandBuffer.beginCommandBuffer(allocator: slot.allocator)
        slot.commandBuffer.useResidencySet(state.sceneResidency)
        slot.commandBuffer.useResidencySet(state.layerResidency)
        slot.commandBuffer.pushDebugGroup("GoldenEye.M5.Clear.Frame.\(frameIndex)")

        let pass = MTL4RenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(
            red: 0.035,
            green: 0.065,
            blue: 0.12,
            alpha: 1.0
        )
        guard let encoder = slot.commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            slot.commandBuffer.popDebugGroup()
            slot.commandBuffer.endCommandBuffer()
            print("GoldenEye M5 failed to create clear encoder")
            return false
        }
        encoder.label = "GoldenEye.M5.Clear.RenderEncoder"
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
        if state.captureActive {
            state.stopCapture()
        }
        return true
    }

    func shutdown() {
        for value in lastSignalBySlot where value != 0 {
            _ = state.completionEvent.wait(untilSignaledValue: value, timeoutMS: 2_000)
        }
        try? "frames=\(renderedFrames) lastSignal=\(nextSignalValue - 1) resourceAllocations=\(state.sceneResidency.allocationCount)\n".write(
            toFile: "/tmp/goldeneye-m5-clear.log",
            atomically: true,
            encoding: .utf8
        )
    }
}
