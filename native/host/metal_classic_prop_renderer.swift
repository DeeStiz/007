import Foundation
import Metal
import QuartzCore
import GoldenEyeNative

/// Errors are deliberately local to the classic-prop renderer.  The replay
/// result is a value-only C record; malformed counts, indices, or an absent
/// replay result must never turn into an unchecked GPU read.
@available(macOS 26.0, *)
enum GoldenEyeClassicPropRendererError: Error, CustomStringConvertible {
    case missingLibrary(URL)
    case pipelineCreationFailed(String)
    case replayFailed(GEStatusV1)
    case malformedReplay(String)
    case emptyReplay
    case bufferCreationFailed(String)

    var description: String {
        switch self {
        case .missingLibrary(let url):
            return "missing classic prop metallib at \(url.path)"
        case .pipelineCreationFailed(let component):
            return "classic prop pipeline creation failed for \(component)"
        case .replayFailed(let status):
            return "classic prop replay failed with status \(status)"
        case .malformedReplay(let detail):
            return "classic prop replay is malformed: \(detail)"
        case .emptyReplay:
            return "classic prop replay produced no indexed geometry"
        case .bufferCreationFailed(let component):
            return "classic prop buffer creation failed for \(component)"
        }
    }
}

/// MTL4 pipeline helper for the explicitly diagnostic vertex-color material.
///
/// Integration seam (kept out of main.swift by delegation): package/build
/// integration must compile `native/shaders/GoldenEyeClassicProp.metal` for
/// macOS 27 (`xcrun metal -mmacosx-version-min=27.0`) and run `metallib`, then
/// copy the resulting `GoldenEyeClassicProp.metallib` into the app's
/// `Contents/Resources` directory.  No texture, TMEM, TLUT, or combiner
/// resource is expected by this pipeline.
@available(macOS 26.0, *)
final class GoldenEyeClassicPropPipeline {
    let pipeline: any MTLRenderPipelineState
    let label = "GoldenEye.M5.ClassicProp.Pipeline"

    init(device: any MTLDevice, libraryURL: URL) throws {
        guard let library = try? device.makeLibrary(URL: libraryURL) else {
            throw GoldenEyeClassicPropRendererError.missingLibrary(libraryURL)
        }

        let compilerDescriptor = MTL4CompilerDescriptor()
        guard let compiler = try? device.makeCompiler(descriptor: compilerDescriptor) else {
            throw GoldenEyeClassicPropRendererError.pipelineCreationFailed("MTL4 compiler")
        }

        let vertexFunction = MTL4LibraryFunctionDescriptor()
        vertexFunction.library = library
        vertexFunction.name = "goldeneye_classic_prop_vertex"
        let fragmentFunction = MTL4LibraryFunctionDescriptor()
        fragmentFunction.library = library
        fragmentFunction.name = "goldeneye_classic_prop_fragment"

        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.label = label
        descriptor.vertexFunctionDescriptor = vertexFunction
        descriptor.fragmentFunctionDescriptor = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? compiler.makeRenderPipelineState(descriptor: descriptor) else {
            throw GoldenEyeClassicPropRendererError.pipelineCreationFailed("MTL4 render pipeline")
        }
        self.pipeline = pipeline
    }

    convenience init(device: any MTLDevice, bundle: Bundle = .main) throws {
        guard let libraryURL = bundle.url(forResource: "GoldenEyeClassicProp", withExtension: "metallib") else {
            throw GoldenEyeClassicPropRendererError.missingLibrary(
                bundle.bundleURL.appendingPathComponent("GoldenEyeClassicProp.metallib")
            )
        }
        try self.init(device: device, libraryURL: libraryURL)
    }
}

/// A bounded Metal 4 consumer of `GEClassicReplayResultV2`.
///
/// The caller supplies an immutable, fixed-width `GEClassicAssetBlobV2` that
/// was validated at the C boundary.  The first owner-loop frame invokes the
/// C replay function by value, copies the returned draw packets, and creates
/// resident shared buffers.  Swift never observes a C pointer, Gfx object,
/// segmented address, or mutable display-list graph.
@available(macOS 26.0, *)
final class GoldenEyeMetalClassicPropRenderer: GoldenEyeFrameRenderer, @unchecked Sendable {
    private struct GPUVertex {
        var position: SIMD4<Float>
        var color: SIMD4<Float>
    }

    private struct GPUTransient {
        var diagnosticTint: SIMD4<Float>
        var materialFlags: UInt32
        var stateHashLow: UInt32
        var stateHashHigh: UInt32
        var reserved: UInt32
    }

    private struct DrawRange {
        let indexOffset: Int
        let indexCount: Int
        let vertexOffset: Int
        let transientIndex: Int
        let sourceListHandle: UInt32
        let sourceCommandOffset: UInt32
        let listDepth: UInt32
    }

    private struct ReplayEvidence {
        let status: GEStatusV1
        let commandsProcessed: UInt32
        let listEnters: UInt32
        let listReturns: UInt32
        let drawCount: UInt32
        let vertexCount: UInt32
        let triangleCount: UInt32
        let packetHash: UInt64
        let eventHash: UInt64
        let stateHash: UInt64
    }

    private let state: GoldenEyeMetalDeviceState
    private let layer: CAMetalLayer
    private let pipeline: GoldenEyeClassicPropPipeline
    private let assetBlob: GEClassicAssetBlobV2

    private var didReplay = false
    private var replayEvidence: ReplayEvidence?
    private var drawRanges: [DrawRange] = []
    private var vertexBuffer: (any MTLBuffer)?
    private var indexBuffer: (any MTLBuffer)?
    private var transientBuffer: (any MTLBuffer)?
    private var indexBufferLength = 0

    private var frameIndex = 0
    private var nextSignalValue: UInt64 = 1
    private var lastSignalBySlot: [UInt64] = [0, 0]
    private var renderedFrames = 0
    private var renderedDraws = 0

    init(
        state: GoldenEyeMetalDeviceState,
        layer: CAMetalLayer,
        pipeline: GoldenEyeClassicPropPipeline,
        assetBlob: GEClassicAssetBlobV2
    ) {
        self.state = state
        self.layer = layer
        self.pipeline = pipeline
        self.assetBlob = assetBlob
    }

    /// Copies a fixed C tuple into Swift values without indexing the imported
    /// tuple fields by hand.  The bounds check is against the tuple's actual
    /// byte count, not a caller-provided count, before any typed view is made.
    private static func copiedDraws(
        from result: GEClassicReplayResultV2
    ) throws -> [GEClassicDrawPacketV2] {
        let stride = MemoryLayout<GEClassicDrawPacketV2>.stride
        return try withUnsafeBytes(of: result.draws) { rawBytes in
            guard stride > 0, rawBytes.count % stride == 0 else {
                throw GoldenEyeClassicPropRendererError.malformedReplay("draw tuple stride")
            }
            let capacity = rawBytes.count / stride
            let requested = Int(result.draw_count)
            guard requested <= capacity else {
                throw GoldenEyeClassicPropRendererError.malformedReplay("draw count \(requested) > \(capacity)")
            }
            let typed = rawBytes.bindMemory(to: GEClassicDrawPacketV2.self)
            return Array(typed.prefix(requested))
        }
    }

    private static func copiedVertices(
        from packet: GEClassicDrawPacketV2
    ) throws -> [GEClassicClipVertexV2] {
        let stride = MemoryLayout<GEClassicClipVertexV2>.stride
        return try withUnsafeBytes(of: packet.vertices) { rawBytes in
            guard stride > 0, rawBytes.count % stride == 0 else {
                throw GoldenEyeClassicPropRendererError.malformedReplay("vertex tuple stride")
            }
            let capacity = rawBytes.count / stride
            let requested = Int(packet.vertex_count)
            guard requested <= capacity else {
                throw GoldenEyeClassicPropRendererError.malformedReplay("vertex count \(requested) > \(capacity)")
            }
            let typed = rawBytes.bindMemory(to: GEClassicClipVertexV2.self)
            return Array(typed.prefix(requested))
        }
    }

    private static func copiedTriangles(
        from packet: GEClassicDrawPacketV2
    ) throws -> [GEClassicTriangleV2] {
        let stride = MemoryLayout<GEClassicTriangleV2>.stride
        return try withUnsafeBytes(of: packet.triangles) { rawBytes in
            guard stride > 0, rawBytes.count % stride == 0 else {
                throw GoldenEyeClassicPropRendererError.malformedReplay("triangle tuple stride")
            }
            let capacity = rawBytes.count / stride
            let requested = Int(packet.triangle_count)
            guard requested <= capacity else {
                throw GoldenEyeClassicPropRendererError.malformedReplay("triangle count \(requested) > \(capacity)")
            }
            let typed = rawBytes.bindMemory(to: GEClassicTriangleV2.self)
            return Array(typed.prefix(requested))
        }
    }

    private static func deviceBuffer<T>(
        device: any MTLDevice,
        values: inout [T],
        label: String
    ) -> (any MTLBuffer)? {
        guard !values.isEmpty else { return nil }
        let buffer = values.withUnsafeBytes { rawBytes -> (any MTLBuffer)? in
            guard let baseAddress = rawBytes.baseAddress, !rawBytes.isEmpty else { return nil }
            return device.makeBuffer(
                bytes: baseAddress,
                length: rawBytes.count,
                options: .storageModeShared
            )
        }
        buffer?.label = label
        return buffer
    }

    /// Runs exactly once, on the owner thread's first `renderFrame` call.
    /// The replay entry point takes the immutable fixed-width blob by value;
    /// no caller-owned bytes remain referenced after this function returns.
    private func prepareReplayIfNeeded() -> Bool {
        guard !didReplay else { return replayEvidence?.status == GE_STATUS_OK }
        didReplay = true

        let result = ge_classic_replay_prop_blob(assetBlob)
        replayEvidence = ReplayEvidence(
            status: result.status,
            commandsProcessed: result.commands_processed,
            listEnters: result.list_enters,
            listReturns: result.list_returns,
            drawCount: result.draw_count,
            vertexCount: result.vertex_count,
            triangleCount: result.triangle_count,
            packetHash: result.packet_hash,
            eventHash: result.event_hash,
            stateHash: result.state_hash
        )
        guard result.status == GE_STATUS_OK else {
            print("GoldenEye classic prop replay failed: status=\(result.status) opcode=0x\(String(result.error_opcode, radix: 16)) offset=\(result.error_offset) list=\(result.error_list_handle) depth=\(result.error_list_depth)")
            return false
        }

        do {
            let packets = try Self.copiedDraws(from: result)
            var vertices: [GPUVertex] = []
            var indices: [UInt32] = []
            var transient: [GPUTransient] = []
            var ranges: [DrawRange] = []
            vertices.reserveCapacity(Int(result.vertex_count))
            indices.reserveCapacity(Int(result.triangle_count) * 3)
            transient.reserveCapacity(packets.count)
            ranges.reserveCapacity(packets.count)

            for (packetIndex, packet) in packets.enumerated() {
                let packetVertices = try Self.copiedVertices(from: packet)
                let packetTriangles = try Self.copiedTriangles(from: packet)
                guard !packetVertices.isEmpty, !packetTriangles.isEmpty else {
                    continue
                }

                let vertexOffset = vertices.count
                let indexOffset = indices.count
                let transientIndex = transient.count
                for vertex in packetVertices {
                    vertices.append(
                        GPUVertex(
                            position: SIMD4<Float>(vertex.x, vertex.y, vertex.z, vertex.w),
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
                    guard a < packetVertices.count, b < packetVertices.count, c < packetVertices.count else {
                        throw GoldenEyeClassicPropRendererError.malformedReplay(
                            "packet \(packetIndex) index outside vertex cache"
                        )
                    }
                    // Indices stay packet-local; baseVertex on the MTL4 draw
                    // supplies the flattened vertex offset.
                    indices.append(UInt32(a))
                    indices.append(UInt32(b))
                    indices.append(UInt32(c))
                }

                let stateHash = packet.state.state_hash
                transient.append(
                    GPUTransient(
                        // White keeps the source vertex colors visible while
                        // explicitly selecting the diagnostic material path.
                        diagnosticTint: SIMD4<Float>(repeating: 1.0),
                        materialFlags: packet.material_flags,
                        stateHashLow: UInt32(truncatingIfNeeded: stateHash),
                        stateHashHigh: UInt32(truncatingIfNeeded: stateHash >> 32),
                        reserved: UInt32(packetIndex)
                    )
                )
                ranges.append(
                    DrawRange(
                        indexOffset: indexOffset,
                        indexCount: packetTriangles.count * 3,
                        vertexOffset: vertexOffset,
                        transientIndex: transientIndex,
                        sourceListHandle: packet.source_list_handle,
                        sourceCommandOffset: packet.source_command_offset,
                        listDepth: packet.list_depth
                    )
                )
            }

            guard !vertices.isEmpty, !indices.isEmpty, !transient.isEmpty, !ranges.isEmpty else {
                throw GoldenEyeClassicPropRendererError.emptyReplay
            }

            guard let vertexBuffer = Self.deviceBuffer(
                device: state.device,
                values: &vertices,
                label: "GoldenEye.M5.ClassicProp.VertexBuffer"
            ) else {
                throw GoldenEyeClassicPropRendererError.bufferCreationFailed("vertex buffer")
            }
            guard let indexBuffer = Self.deviceBuffer(
                device: state.device,
                values: &indices,
                label: "GoldenEye.M5.ClassicProp.IndexBuffer"
            ) else {
                throw GoldenEyeClassicPropRendererError.bufferCreationFailed("index buffer")
            }
            guard let transientBuffer = Self.deviceBuffer(
                device: state.device,
                values: &transient,
                label: "GoldenEye.M5.ClassicProp.TransientBuffer"
            ) else {
                throw GoldenEyeClassicPropRendererError.bufferCreationFailed("transient buffer")
            }

            // The buffers are shared only for CPU upload; GPU ownership is
            // retained by the renderer and explicitly declared to Metal 4.
            state.sceneResidency.addAllocation(vertexBuffer)
            state.sceneResidency.addAllocation(indexBuffer)
            state.sceneResidency.addAllocation(transientBuffer)
            state.sceneResidency.commit()
            state.argumentTable.setAddress(vertexBuffer.gpuAddress, index: 0)
            state.argumentTable.setAddress(indexBuffer.gpuAddress, index: 1)
            state.argumentTable.setAddress(transientBuffer.gpuAddress, index: 2)

            self.vertexBuffer = vertexBuffer
            self.indexBuffer = indexBuffer
            self.transientBuffer = transientBuffer
            self.indexBufferLength = indices.count * MemoryLayout<UInt32>.stride
            self.drawRanges = ranges
            return true
        } catch {
            print("GoldenEye classic prop replay flatten failed: \(error)")
            replayEvidence = nil
            return false
        }
    }

    func renderFrame() -> Bool {
        guard prepareReplayIfNeeded(),
              vertexBuffer != nil,
              indexBuffer != nil,
              transientBuffer != nil,
              let indexBuffer else {
            return false
        }

        let slotIndex = frameIndex % state.frameSlots.count
        let slot = state.frameSlots[slotIndex]
        let priorSignal = lastSignalBySlot[slotIndex]
        if priorSignal != 0 {
            guard state.completionEvent.wait(untilSignaledValue: priorSignal, timeoutMS: 1_000) else {
                print("GoldenEye classic prop timed out waiting for slot \(slotIndex)")
                return false
            }
        }

        guard let drawable = layer.nextDrawable() else {
            print("GoldenEye classic prop failed to acquire drawable")
            return false
        }

        // Reuse is legal only after the shared-event retirement wait above.
        slot.allocator.reset()
        slot.commandBuffer.beginCommandBuffer(allocator: slot.allocator)
        slot.commandBuffer.useResidencySet(state.sceneResidency)
        slot.commandBuffer.useResidencySet(state.layerResidency)
        slot.commandBuffer.pushDebugGroup("GoldenEye.M5.ClassicProp.Frame.\(frameIndex)")

        let pass = MTL4RenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1.0)
        guard let encoder = slot.commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            slot.commandBuffer.popDebugGroup()
            slot.commandBuffer.endCommandBuffer()
            print("GoldenEye classic prop failed to create render encoder")
            return false
        }
        encoder.label = "GoldenEye.M5.ClassicProp.RenderEncoder"
        encoder.setRenderPipelineState(pipeline.pipeline)
        encoder.setArgumentTable(state.argumentTable, stages: [.vertex, .fragment])

        for (drawIndex, range) in drawRanges.enumerated() {
            let byteOffset = range.indexOffset * MemoryLayout<UInt32>.stride
            let remainingIndexBytes = indexBufferLength - byteOffset
            guard remainingIndexBytes > 0 else {
                encoder.endEncoding()
                slot.commandBuffer.popDebugGroup()
                slot.commandBuffer.endCommandBuffer()
                print("GoldenEye classic prop index range escaped index buffer")
                return false
            }
            encoder.pushDebugGroup(
                "GoldenEye.M5.ClassicProp.Draw.\(drawIndex).List.\(range.sourceListHandle).Command.\(range.sourceCommandOffset).Depth.\(range.listDepth)"
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

        // Metal 4 presentation is queue-level: wait before commit, signal the
        // drawable after commit, then present it.  The shared event retires
        // the slot and all three resident buffers for subsequent reuse.
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
        let evidence: String
        if let replayEvidence {
            evidence = "status=\(replayEvidence.status) commands=\(replayEvidence.commandsProcessed) enters=\(replayEvidence.listEnters) returns=\(replayEvidence.listReturns) drawPackets=\(replayEvidence.drawCount) vertices=\(replayEvidence.vertexCount) triangles=\(replayEvidence.triangleCount) packetHash=\(replayEvidence.packetHash) eventHash=\(replayEvidence.eventHash) stateHash=\(replayEvidence.stateHash)"
        } else {
            evidence = "status=unavailable"
        }
        try? "replay=classic-prop material=vertex-color-diagnostic \(evidence) frames=\(renderedFrames) draws=\(renderedDraws) lastSignal=\(nextSignalValue - 1) resourceAllocations=\(state.sceneResidency.allocationCount)\n".write(
            toFile: "/tmp/goldeneye-classic-prop.log",
            atomically: true,
            encoding: .utf8
        )
    }
}
