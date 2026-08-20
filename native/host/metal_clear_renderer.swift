import Metal
import QuartzCore

protocol GoldenEyeFrameRenderer: AnyObject, Sendable {
    func renderFrame() -> Bool
    func shutdown()
}

@available(macOS 26.0, *)
final class GoldenEyeMetalClearRenderer: GoldenEyeFrameRenderer, GoldenEyeTitleSnapshotRenderer, GoldenEyeDrawableFrameRenderer, @unchecked Sendable {
    private let state: GoldenEyeMetalDeviceState
    private let layer: CAMetalLayer
    private var frameIndex = 0
    private var nextSignalValue: UInt64 = 1
    private var lastSignalBySlot: [UInt64] = [0, 0]
    private var renderedFrames = 0
    private var latestTitleSnapshot: GoldenEyeTitleSnapshot?

    init(state: GoldenEyeMetalDeviceState, layer: CAMetalLayer) {
        self.state = state
        self.layer = layer
    }

    func submit(titleSnapshot: GoldenEyeTitleSnapshot) {
        latestTitleSnapshot = titleSnapshot
        guard titleSnapshot.pairPhase == 0 else { return }
        let line = "tick=\(titleSnapshot.nativeTick) screen=\(titleSnapshot.screen.rawValue) "
            + "subphase=\(titleSnapshot.subphase) timer120=\(titleSnapshot.timer120) "
            + "stateHash=\(titleSnapshot.stateHash) renderHash=\(titleSnapshot.renderHash)\n"
        if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: "/tmp/goldeneye-native-title.log")) {
            handle.seekToEndOfFile()
            try? handle.write(contentsOf: Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(
                to: URL(fileURLWithPath: "/tmp/goldeneye-native-title.log"),
                options: .atomic
            )
        }
    }

    func renderFrame() -> Bool {
        guard let drawable = layer.nextDrawable() else {
            print("GoldenEye M5 failed to acquire drawable")
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

    func render(drawable: any CAMetalDrawable, timing: GE120DisplayTiming) -> Bool {
        _ = timing
        let slotIndex = frameIndex % state.frameSlots.count
        let slot = state.frameSlots[slotIndex]
        let priorSignal = lastSignalBySlot[slotIndex]
        if priorSignal != 0 {
            guard state.completionEvent.wait(untilSignaledValue: priorSignal, timeoutMS: 1_000) else {
                print("GoldenEye M5 timed out waiting for slot \(slotIndex)")
                return false
            }
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
        let color = clearColor(for: latestTitleSnapshot?.screen ?? .legal)
        pass.colorAttachments[0].clearColor = MTLClearColor(
            red: color.red,
            green: color.green,
            blue: color.blue,
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
        try? "frames=\(renderedFrames) lastSignal=\(nextSignalValue - 1) completionSignaled=\(state.completionEvent.signaledValue) resourceAllocations=\(state.sceneResidency.allocationCount)\n".write(
            toFile: "/tmp/goldeneye-m5-clear.log",
            atomically: true,
            encoding: .utf8
        )
    }

    private func clearColor(for screen: GoldenEyeTitleScreen) -> (red: Double, green: Double, blue: Double) {
        switch screen {
        case .legal: return (0.010, 0.010, 0.014)
        case .nintendo: return (0.42, 0.015, 0.018)
        case .rareware: return (0.015, 0.11, 0.24)
        case .gunbarrel: return (0.16, 0.018, 0.020)
        case .goldenEye: return (0.26, 0.22, 0.13)
        case .fileSelect: return (0.055, 0.070, 0.080)
        case .modeSelect: return (0.080, 0.060, 0.050)
        case .cast: return (0.012, 0.012, 0.012)
        case .ramrom: return (0.020, 0.090, 0.045)
        }
    }
}
