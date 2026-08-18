import Metal
import QuartzCore

@available(macOS 26.0, *)
enum GoldenEyeMetalDeviceStateError: Error, CustomStringConvertible {
    case metal4Unavailable(String)
    case creationFailed(String)

    var description: String {
        switch self {
        case .metal4Unavailable(let name):
            return "Metal 4 is unavailable on device \(name)"
        case .creationFailed(let component):
            return "Metal 4 creation failed for \(component)"
        }
    }
}

@available(macOS 26.0, *)
final class GoldenEyeMetalFrameSlot {
    let index: Int
    let commandBuffer: any MTL4CommandBuffer
    let allocator: any MTL4CommandAllocator

    init(index: Int, device: any MTLDevice) throws {
        self.index = index
        let allocatorDescriptor = MTL4CommandAllocatorDescriptor()
        allocatorDescriptor.label = "GoldenEye.M4.FrameSlot.\(index).Allocator"
        guard let allocator = try? device.makeCommandAllocator(descriptor: allocatorDescriptor) else {
            throw GoldenEyeMetalDeviceStateError.creationFailed("command allocator \(index)")
        }
        guard let commandBuffer = device.makeCommandBuffer() else {
            throw GoldenEyeMetalDeviceStateError.creationFailed("command buffer \(index)")
        }
        commandBuffer.label = "GoldenEye.M4.FrameSlot.\(index).CommandBuffer"
        self.allocator = allocator
        self.commandBuffer = commandBuffer
    }
}

@available(macOS 26.0, *)
final class GoldenEyeMetalDeviceState {
    let device: any MTLDevice
    let queue: any MTL4CommandQueue
    let frameSlots: [GoldenEyeMetalFrameSlot]
    let argumentTable: any MTL4ArgumentTable
    let sceneResidency: any MTLResidencySet
    let layerResidency: any MTLResidencySet
    let completionEvent: any MTLSharedEvent
    private let captureManager: MTLCaptureManager?
    private(set) var captureActive = false

    init(device: any MTLDevice, layer: CAMetalLayer) throws {
        guard device.supportsFamily(.metal4) else {
            throw GoldenEyeMetalDeviceStateError.metal4Unavailable(device.name)
        }
        self.device = device

        let queueDescriptor = MTL4CommandQueueDescriptor()
        queueDescriptor.label = "GoldenEye.M4.Queue"
        guard let queue = try? device.makeMTL4CommandQueue(descriptor: queueDescriptor) else {
            throw GoldenEyeMetalDeviceStateError.creationFailed("command queue")
        }
        self.queue = queue

        let environment = ProcessInfo.processInfo.environment
        let captureOutputPath: String?
        if environment["GOLDENEYE_M5_CAPTURE"] == "1" {
            captureOutputPath = "/tmp/goldeneye-m5-clear.gputrace"
        } else if environment["GOLDENEYE_M8_CAPTURE"] == "1" {
            captureOutputPath = "/tmp/goldeneye-m8-triangle.gputrace"
        } else if environment["GOLDENEYE_M10_CAPTURE"] == "1" {
            captureOutputPath = "/tmp/goldeneye-m10-classic-prop.gputrace"
        } else {
            captureOutputPath = nil
        }
        if let captureOutputPath {
            let manager = MTLCaptureManager.shared()
            let descriptor = MTLCaptureDescriptor()
            descriptor.captureObject = queue
            descriptor.destination = .gpuTraceDocument
            descriptor.outputURL = URL(fileURLWithPath: captureOutputPath)
            do {
                try manager.startCapture(with: descriptor)
                captureManager = manager
                captureActive = true
                try? "started\n".write(
                    toFile: "/tmp/goldeneye-capture-status.log",
                    atomically: true,
                    encoding: .utf8
                )
            } catch {
                try? "error=\(error)\n".write(
                    toFile: "/tmp/goldeneye-capture-status.log",
                    atomically: true,
                    encoding: .utf8
                )
                throw GoldenEyeMetalDeviceStateError.creationFailed("GPU capture: \(error)")
            }
        } else {
            captureManager = nil
        }

        var slots: [GoldenEyeMetalFrameSlot] = []
        slots.reserveCapacity(2)
        for index in 0..<2 {
            slots.append(try GoldenEyeMetalFrameSlot(index: index, device: device))
        }
        self.frameSlots = slots

        let argumentDescriptor = MTL4ArgumentTableDescriptor()
        argumentDescriptor.label = "GoldenEye.M4.ArgumentTable.Scene"
        argumentDescriptor.maxBufferBindCount = 4
        argumentDescriptor.maxTextureBindCount = 1
        argumentDescriptor.maxSamplerStateBindCount = 1
        argumentDescriptor.initializeBindings = true
        argumentDescriptor.supportAttributeStrides = true
        guard let argumentTable = try? device.makeArgumentTable(descriptor: argumentDescriptor) else {
            throw GoldenEyeMetalDeviceStateError.creationFailed("argument table")
        }
        self.argumentTable = argumentTable

        let residencyDescriptor = MTLResidencySetDescriptor()
        residencyDescriptor.label = "GoldenEye.M4.SceneResidency"
        residencyDescriptor.initialCapacity = 2
        guard let sceneResidency = try? device.makeResidencySet(descriptor: residencyDescriptor) else {
            throw GoldenEyeMetalDeviceStateError.creationFailed("scene residency set")
        }
        sceneResidency.requestResidency()
        queue.addResidencySet(sceneResidency)
        self.sceneResidency = sceneResidency

        layer.device = device
        layer.isOpaque = true
        layer.framebufferOnly = true
        layerResidency = layer.residencySet
        queue.addResidencySet(layerResidency)

        guard let completionEvent = device.makeSharedEvent() else {
            throw GoldenEyeMetalDeviceStateError.creationFailed("shared completion event")
        }
        completionEvent.label = "GoldenEye.M4.CompletionEvent"
        self.completionEvent = completionEvent
    }

    var evidenceLine: String {
        let slotLabels = frameSlots.map { $0.commandBuffer.label ?? "" }.joined(separator: ",")
        return "metal4=1 queue=\(queue.label ?? "") slots=\(frameSlots.count) "
            + "slotLabels=\(slotLabels) "
            + "argumentTable=\(argumentTable.label ?? "") "
            + "sceneResidencyDescriptor=GoldenEye.M4.SceneResidency "
            + "layerResidency=1 completionEvent=\(completionEvent.label ?? "")"
    }

    func stopCapture() {
        guard captureActive else { return }
        captureManager?.stopCapture()
        captureActive = false
        try? "stopped\n".write(
            toFile: "/tmp/goldeneye-capture-status.log",
            atomically: true,
            encoding: .utf8
        )
    }
}
