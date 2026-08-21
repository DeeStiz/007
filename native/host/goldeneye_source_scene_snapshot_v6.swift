#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif
import Foundation
import simd

/// A value-only view of one source-produced frame.
///
/// This is intentionally a strict copy-in boundary.  The imported C records
/// are copied into immutable Swift arrays; no source pointer, segmented
/// address, display-list pointer, filesystem path, or Metal object is retained
/// by the snapshot.  The renderer only consumes the triangle command family in
/// this first lane.  Other command families remain present in the snapshot so
/// that they can be diagnosed rather than silently replaced with a fallback.
public enum GoldenEyeSourceSceneSnapshotV6Error: Error, CustomStringConvertible, Equatable {
    case invalidEnvelope(String)
    case invalidRecord(String)
    case reservedField(String)
    case duplicateHandle(String, UInt32)
    case missingHandle(String, UInt32)
    case countMismatch(String, expected: Int, actual: Int)
    case rangeOverflow(String)
    case invalidHash(String)

    public var description: String {
        switch self {
        case .invalidEnvelope(let name):
            return "invalid V6 ABI envelope for \(name)"
        case .invalidRecord(let name):
            return "invalid V6 record: \(name)"
        case .reservedField(let name):
            return "non-zero V6 reserved field: \(name)"
        case .duplicateHandle(let kind, let handle):
            return "duplicate V6 \(kind) handle \(handle)"
        case .missingHandle(let kind, let handle):
            return "missing V6 \(kind) handle \(handle)"
        case .countMismatch(let name, let expected, let actual):
            return "V6 \(name) count mismatch: expected \(expected), got \(actual)"
        case .rangeOverflow(let name):
            return "V6 range overflow: \(name)"
        case .invalidHash(let name):
            return "invalid V6 hash: \(name)"
        }
    }
}

/// The exact source values used by the first triangle Metal lowering.
public struct GoldenEyeSourceSceneGPUVertexV6: Sendable, Equatable {
    public let position: SIMD4<Float>
    public let texcoord: SIMD4<Float>
    public let normal: SIMD4<Float>
    public let color: SIMD4<Float>

    public init(
        source: GESourceVertexV6,
        eyeSpaceZQ16: Int32? = nil,
        fogCoordinateQ16: Int32? = nil
    ) {
        let position = Self.q16Values(source.position_q16, count: 3)
        let texcoord = Self.q16Values(source.texcoord_q16, count: 2)
        let normal = Self.q16Values(source.normal_q16, count: 3)
        self.position = SIMD4(
            Self.q16(position[0]), Self.q16(position[1]), Self.q16(position[2]), 1
        )
        self.texcoord = SIMD4(
            Self.q16(texcoord[0]), Self.q16(texcoord[1]), 0,
            // The existing fourth texture lane is unused by the source
            // shader. Keep the GPU vertex stride at 64 bytes while carrying
            // the optional fog coordinate in a dedicated metadata lane;
            // normal.w remains a true homogeneous-normal component (zero).
            fogCoordinateQ16.map(Self.q16) ?? 1
        )
        self.normal = SIMD4(
            Self.q16(normal[0]), Self.q16(normal[1]), Self.q16(normal[2]),
            0
        )
        self.color = Self.rgba(source.color_rgba)
    }

    private static func q16(_ value: Int32) -> Float {
        Float(value) / 65_536.0
    }

    private static func rgba(_ value: UInt32) -> SIMD4<Float> {
        SIMD4(
            Float((value >> 24) & 0xff) / 255.0,
            Float((value >> 16) & 0xff) / 255.0,
            Float((value >> 8) & 0xff) / 255.0,
            Float(value & 0xff) / 255.0
        )
    }

    private static func q16Values<T>(_ value: T, count: Int) -> [Int32] {
        withUnsafeBytes(of: value) { rawBytes in
            Array(rawBytes.bindMemory(to: Int32.self).prefix(count))
        }
    }
}

/// Copied index values.  Source indices remain in source order and are not
/// rewritten into a synthetic triangle or a generated quad.
public struct GoldenEyeSourceSceneGPUIndexV6: Sendable, Equatable {
    public let vertex0: UInt32
    public let vertex1: UInt32
    public let vertex2: UInt32

    public init(source: GESourceIndexV6) {
        self.vertex0 = source.vertex0
        self.vertex1 = source.vertex1
        self.vertex2 = source.vertex2
    }
}

/// Explicit source-local timing and decoded GBI state sidecar for one scene
/// frame.  The renderer must not recover the Nintendo menu timer from the
/// global reference tick, and must not infer geometry mode from a screen or
/// render-state convenience enum.  Model-view matrices are copied by source
/// state handle so normal/reflection lowering remains independent of any
/// projection/clip transform used for vertex positions.
public struct GoldenEyeSourceSceneLightingFrameContextV6: Sendable, Equatable {
    public let screen: UInt32
    public let nativeTick: UInt64
    public let referenceTick: UInt64
    public let sourceTimer: UInt32
    public let pairPhase: UInt32
    public let geometryModesByState: [UInt32: UInt32]
    public let modelViewQ16ByState: [UInt32: [Int32]]

    public init(
        screen: UInt32,
        nativeTick: UInt64,
        referenceTick: UInt64,
        sourceTimer: UInt32,
        pairPhase: UInt32,
        geometryModesByState: [UInt32: UInt32],
        modelViewQ16ByState: [UInt32: [Int32]]
    ) throws {
        // A single decoded GBI packet is bounded to 2,048 states, but a
        // source stage composition explicitly remaps the sidecars from the
        // environment plus each visible static-prop packet into one value
        // namespace. Keep a finite composed bound while admitting the
        // source-authored state records needed by that packet; missing or
        // malformed entries still fail at the renderer boundary.
        let maxComposedStateCount = 16_384
        guard nativeTick > 0, pairPhase <= 1,
              geometryModesByState.count <= maxComposedStateCount,
              modelViewQ16ByState.count <= maxComposedStateCount,
              geometryModesByState.keys.allSatisfy({ $0 != 0 }),
              modelViewQ16ByState.keys.allSatisfy({ $0 != 0 }),
              modelViewQ16ByState.values.allSatisfy({ $0.count == 16 }) else {
            throw GoldenEyeSourceSceneSnapshotV6Error.invalidRecord(
                "lighting frame context"
            )
        }
        self.screen = screen
        self.nativeTick = nativeTick
        self.referenceTick = referenceTick
        self.sourceTimer = sourceTimer
        self.pairPhase = pairPhase
        self.geometryModesByState = geometryModesByState
        self.modelViewQ16ByState = modelViewQ16ByState
    }
}

/// Immutable source scene snapshot consumed by the V6 renderer foundation.
public final class GoldenEyeSourceSceneSnapshotV6: @unchecked Sendable {
    public let summary: GESourceFrameSummaryV6
    public let resources: [GESourceResourceV6]
    public let transforms: [GESourceTransformV6]
    public let animationPoses: [GESourceAnimationPoseV6]
    public let vertices: [GESourceVertexV6]
    public let indices: [GESourceIndexV6]
    public let renderStates: [GESourceRenderStateV6]
    public let drawCommands: [GESourceDrawCommandV6]
    public let textEvents: [GESourceTextEventV6]
    public let audioEvents: [GESourceAudioEventV6]
    public let diagnostics: [GESourceDiagnosticV6]
    public let lightingFrameContext: GoldenEyeSourceSceneLightingFrameContextV6?

    /// Canonical per-record hashes, in the same order as their corresponding
    /// immutable arrays.  These are calculated with the V6 little-endian hash
    /// rules and are useful to the renderer's evidence stream.
    public let resourceHashes: [UInt64]
    public let transformHashes: [UInt64]
    public let animationPoseHashes: [UInt64]
    public let vertexHashes: [UInt64]
    public let indexHashes: [UInt64]
    public let renderStateHashes: [UInt64]
    public let drawCommandHashes: [UInt64]
    public let textEventHashes: [UInt64]
    public let audioEventHashes: [UInt64]
    public let diagnosticHashes: [UInt64]

    /// A deterministic aggregate of the copied records.  The source summary's
    /// hashes remain authoritative; this value is an independent inspection
    /// hash and is never substituted for a source hash.
    public let copiedRecordAggregateHash: UInt64

    public let gpuVertices: [GoldenEyeSourceSceneGPUVertexV6]
    public let gpuIndices: [GoldenEyeSourceSceneGPUIndexV6]
    /// Optional additive stage fog coordinate, parallel to `vertices`. Title
    /// and legacy snapshots leave this nil and retain their existing hashes.
    public let eyeSpaceZQ16: [Int32]?
    public let fogCoordinateQ16: [Int32]?

    public init(
        summary: GESourceFrameSummaryV6,
        resources: [GESourceResourceV6],
        transforms: [GESourceTransformV6],
        animationPoses: [GESourceAnimationPoseV6],
        vertices: [GESourceVertexV6],
        indices: [GESourceIndexV6],
        renderStates: [GESourceRenderStateV6],
        drawCommands: [GESourceDrawCommandV6],
        textEvents: [GESourceTextEventV6],
        audioEvents: [GESourceAudioEventV6],
        diagnostics: [GESourceDiagnosticV6],
        lightingFrameContext: GoldenEyeSourceSceneLightingFrameContextV6? = nil,
        eyeSpaceZQ16: [Int32]? = nil,
        fogCoordinateQ16: [Int32]? = nil
    ) throws {
        try Self.validate(
            summary: summary,
            resources: resources,
            transforms: transforms,
            animationPoses: animationPoses,
            vertices: vertices,
            indices: indices,
            renderStates: renderStates,
            drawCommands: drawCommands,
            textEvents: textEvents,
            audioEvents: audioEvents,
            diagnostics: diagnostics
        )
        if let eyeSpaceZQ16, eyeSpaceZQ16.count != vertices.count {
            throw GoldenEyeSourceSceneSnapshotV6Error.countMismatch(
                "eye-space fog coordinates", expected: vertices.count, actual: eyeSpaceZQ16.count
            )
        }
        if let fogCoordinateQ16, fogCoordinateQ16.count != vertices.count {
            throw GoldenEyeSourceSceneSnapshotV6Error.countMismatch(
                "fog coordinates", expected: vertices.count, actual: fogCoordinateQ16.count
            )
        }

        self.summary = summary
        self.resources = resources
        self.transforms = transforms
        self.animationPoses = animationPoses
        self.vertices = vertices
        self.indices = indices
        self.renderStates = renderStates
        self.drawCommands = drawCommands
        self.textEvents = textEvents
        self.audioEvents = audioEvents
        self.diagnostics = diagnostics
        self.lightingFrameContext = lightingFrameContext
        self.eyeSpaceZQ16 = eyeSpaceZQ16
        self.fogCoordinateQ16 = fogCoordinateQ16

        self.resourceHashes = resources.map(Self.hash(resource:))
        self.transformHashes = transforms.map(Self.hash(transform:))
        self.animationPoseHashes = animationPoses.map(Self.hash(animationPose:))
        self.vertexHashes = vertices.map(Self.hash(vertex:))
        self.indexHashes = indices.map(Self.hash(index:))
        self.renderStateHashes = renderStates.map(Self.hash(renderState:))
        self.drawCommandHashes = drawCommands.map(Self.hash(drawCommand:))
        self.textEventHashes = textEvents.map(Self.hash(textEvent:))
        self.audioEventHashes = audioEvents.map(Self.hash(audioEvent:))
        self.diagnosticHashes = diagnostics.map(Self.hash(diagnostic:))

        var aggregate = GEV6Hash.offset
        for hash in self.resourceHashes { aggregate = GEV6Hash.u64(aggregate, hash) }
        for hash in self.transformHashes { aggregate = GEV6Hash.u64(aggregate, hash) }
        for hash in self.animationPoseHashes { aggregate = GEV6Hash.u64(aggregate, hash) }
        for hash in self.vertexHashes { aggregate = GEV6Hash.u64(aggregate, hash) }
        for hash in self.indexHashes { aggregate = GEV6Hash.u64(aggregate, hash) }
        for hash in self.renderStateHashes { aggregate = GEV6Hash.u64(aggregate, hash) }
        for hash in self.drawCommandHashes { aggregate = GEV6Hash.u64(aggregate, hash) }
        for hash in self.textEventHashes { aggregate = GEV6Hash.u64(aggregate, hash) }
        for hash in self.audioEventHashes { aggregate = GEV6Hash.u64(aggregate, hash) }
        for hash in self.diagnosticHashes { aggregate = GEV6Hash.u64(aggregate, hash) }
        if let eyeSpaceZQ16 {
            aggregate = GEV6Hash.u64(aggregate, GEV6Hash.offset ^ 0x4559_455a)
            for value in eyeSpaceZQ16 {
                aggregate = GEV6Hash.u32(aggregate, UInt32(bitPattern: value))
            }
        }
        if let fogCoordinateQ16 {
            aggregate = GEV6Hash.u64(aggregate, GEV6Hash.offset ^ 0x464f_4751)
            for value in fogCoordinateQ16 {
                aggregate = GEV6Hash.u32(aggregate, UInt32(bitPattern: value))
            }
        }
        self.copiedRecordAggregateHash = aggregate

        self.gpuVertices = vertices.enumerated().map { index, vertex in
            GoldenEyeSourceSceneGPUVertexV6(
                source: vertex,
                eyeSpaceZQ16: eyeSpaceZQ16?[index],
                fogCoordinateQ16: fogCoordinateQ16?[index]
            )
        }
        self.gpuIndices = indices.map(GoldenEyeSourceSceneGPUIndexV6.init(source:))
    }

    /// Reframe an already validated immutable topology without rehashing or
    /// rebuilding its resources, vertices, indices, draw commands, text,
    /// audio, diagnostics, or GPU vertex/index views.  The title owner uses
    /// this additive initializer for its 120 Hz cache hits; only transforms,
    /// render-state fades and the source lighting sidecar are frame-local.
    init(
        reframing source: GoldenEyeSourceSceneSnapshotV6,
        summary: GESourceFrameSummaryV6,
        transforms: [GESourceTransformV6],
        renderStates: [GESourceRenderStateV6],
        lightingFrameContext: GoldenEyeSourceSceneLightingFrameContextV6?
    ) throws {
        guard transforms.count == source.transforms.count,
              renderStates.count == source.renderStates.count,
              transforms.map(\.handle) == source.transforms.map(\.handle),
              renderStates.map(\.state_handle) == source.renderStates.map(\.state_handle),
              summary.transform_count == UInt32(transforms.count),
              summary.resource_count == UInt32(source.resources.count),
              summary.pose_count == UInt32(source.animationPoses.count),
              summary.vertex_count == UInt32(source.vertices.count),
              summary.index_count == UInt32(source.indices.count),
              summary.draw_count == UInt32(source.drawCommands.count),
              summary.render_state_count == UInt32(renderStates.count),
              summary.text_count == UInt32(source.textEvents.count),
              summary.audio_count == UInt32(source.audioEvents.count),
              summary.diagnostic_count == UInt32(source.diagnostics.count) else {
            throw GoldenEyeSourceSceneSnapshotV6Error.invalidRecord("reframed topology counts")
        }
        try transforms.forEach { try Self.validate(transform: $0) }
        try renderStates.forEach { try Self.validate(renderState: $0) }

        self.summary = summary
        self.resources = source.resources
        self.transforms = transforms
        self.animationPoses = source.animationPoses
        self.vertices = source.vertices
        self.indices = source.indices
        self.renderStates = renderStates
        self.drawCommands = source.drawCommands
        self.textEvents = source.textEvents
        self.audioEvents = source.audioEvents
        self.diagnostics = source.diagnostics
        self.lightingFrameContext = lightingFrameContext
        self.eyeSpaceZQ16 = source.eyeSpaceZQ16
        self.fogCoordinateQ16 = source.fogCoordinateQ16

        self.resourceHashes = source.resourceHashes
        self.transformHashes = transforms.map(Self.hash(transform:))
        self.animationPoseHashes = source.animationPoseHashes
        self.vertexHashes = source.vertexHashes
        self.indexHashes = source.indexHashes
        self.renderStateHashes = renderStates.map(Self.hash(renderState:))
        self.drawCommandHashes = source.drawCommandHashes
        self.textEventHashes = source.textEventHashes
        self.audioEventHashes = source.audioEventHashes
        self.diagnosticHashes = source.diagnosticHashes

        var aggregate = GEV6Hash.offset
        for hash in self.resourceHashes { aggregate = GEV6Hash.u64(aggregate, hash) }
        for hash in self.transformHashes { aggregate = GEV6Hash.u64(aggregate, hash) }
        for hash in self.animationPoseHashes { aggregate = GEV6Hash.u64(aggregate, hash) }
        for hash in self.vertexHashes { aggregate = GEV6Hash.u64(aggregate, hash) }
        for hash in self.indexHashes { aggregate = GEV6Hash.u64(aggregate, hash) }
        for hash in self.renderStateHashes { aggregate = GEV6Hash.u64(aggregate, hash) }
        for hash in self.drawCommandHashes { aggregate = GEV6Hash.u64(aggregate, hash) }
        for hash in self.textEventHashes { aggregate = GEV6Hash.u64(aggregate, hash) }
        for hash in self.audioEventHashes { aggregate = GEV6Hash.u64(aggregate, hash) }
        for hash in self.diagnosticHashes { aggregate = GEV6Hash.u64(aggregate, hash) }
        self.copiedRecordAggregateHash = aggregate
        self.gpuVertices = source.gpuVertices
        self.gpuIndices = source.gpuIndices
    }

    public var resourceByHandle: [UInt32: GESourceResourceV6] {
        Dictionary(uniqueKeysWithValues: resources.map { ($0.handle, $0) })
    }

    public var transformByHandle: [UInt32: GESourceTransformV6] {
        Dictionary(uniqueKeysWithValues: transforms.map { ($0.handle, $0) })
    }

    public var renderStateByHandle: [UInt32: GESourceRenderStateV6] {
        Dictionary(uniqueKeysWithValues: renderStates.map { ($0.state_handle, $0) })
    }

    public var isPresentable: Bool {
        summary.flags & UInt32(GE_SOURCE_FRAME_V6_FLAG_PRESENTABLE) != 0
    }

    private static func validate(
        summary: GESourceFrameSummaryV6,
        resources: [GESourceResourceV6],
        transforms: [GESourceTransformV6],
        animationPoses: [GESourceAnimationPoseV6],
        vertices: [GESourceVertexV6],
        indices: [GESourceIndexV6],
        renderStates: [GESourceRenderStateV6],
        drawCommands: [GESourceDrawCommandV6],
        textEvents: [GESourceTextEventV6],
        audioEvents: [GESourceAudioEventV6],
        diagnostics: [GESourceDiagnosticV6]
    ) throws {
        try validateEnvelope(summary.header, expectedSize: MemoryLayout<GESourceFrameSummaryV6>.size, name: "frame summary")
        guard summary.record_version == UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION) else {
            throw GoldenEyeSourceSceneSnapshotV6Error.invalidRecord("frame summary record version")
        }
        guard summary.flags & ~UInt32(GE_SOURCE_FRAME_V6_FLAG_MASK) == 0 else {
            throw GoldenEyeSourceSceneSnapshotV6Error.invalidRecord("frame summary flags")
        }
        guard summary.screen <= UInt32(GE_SOURCE_FRAME_V6_SCREEN_MAX), summary.pair_phase <= 1 else {
            throw GoldenEyeSourceSceneSnapshotV6Error.invalidRecord("frame summary screen/pair phase")
        }
        guard summary.viewport_width > 0, summary.viewport_height > 0,
              summary.logical_width > 0, summary.logical_height > 0 else {
            throw GoldenEyeSourceSceneSnapshotV6Error.invalidRecord("frame summary dimensions")
        }
        if summary.flags & UInt32(GE_SOURCE_FRAME_V6_FLAG_PRESENTABLE) != 0 {
            guard summary.scene_hash != 0, summary.render_hash != 0,
                  summary.state_hash != 0, summary.frame_hash != 0 else {
                throw GoldenEyeSourceSceneSnapshotV6Error.invalidHash("presentable frame summary")
            }
        }
        guard summary.reserved0 == 0, summary.reserved1 == 0 else {
            throw GoldenEyeSourceSceneSnapshotV6Error.reservedField("frame summary")
        }

        try validateCount("resources", expected: Int(summary.resource_count), actual: resources.count)
        try validateCount("transforms", expected: Int(summary.transform_count), actual: transforms.count)
        try validateCount("animation poses", expected: Int(summary.pose_count), actual: animationPoses.count)
        try validateCount("vertices", expected: Int(summary.vertex_count), actual: vertices.count)
        try validateCount("indices", expected: Int(summary.index_count), actual: indices.count)
        try validateCount("draw commands", expected: Int(summary.draw_count), actual: drawCommands.count)
        try validateCount("render states", expected: Int(summary.render_state_count), actual: renderStates.count)
        try validateCount("text events", expected: Int(summary.text_count), actual: textEvents.count)
        try validateCount("audio events", expected: Int(summary.audio_count), actual: audioEvents.count)
        try validateCount("diagnostics", expected: Int(summary.diagnostic_count), actual: diagnostics.count)

        try resources.forEach { try validate(resource: $0) }
        try transforms.forEach { try validate(transform: $0) }
        try animationPoses.forEach { try validate(animationPose: $0) }
        try vertices.forEach { try validate(vertex: $0) }
        try indices.forEach { try validate(index: $0) }
        try renderStates.forEach { try validate(renderState: $0) }
        try drawCommands.forEach { try validate(drawCommand: $0) }
        try textEvents.forEach { try validate(textEvent: $0) }
        try audioEvents.forEach { try validate(audioEvent: $0) }
        try diagnostics.forEach { try validate(diagnostic: $0) }

        try requireUnique(resources.map(\.handle), kind: "resource")
        try requireUnique(transforms.map(\.handle), kind: "transform")
        try requireUnique(animationPoses.map(\.pose_handle), kind: "animation pose")
        try requireUnique(vertices.map(\.handle), kind: "vertex")
        try requireUnique(indices.map(\.handle), kind: "index")
        try requireUnique(renderStates.map(\.state_handle), kind: "render state")
        try requireUnique(drawCommands.map(\.draw_handle), kind: "draw")
        try requireUnique(textEvents.map(\.text_handle), kind: "text")
        try requireUnique(audioEvents.map(\.event_handle), kind: "audio")

        let resourceHandles = Set(resources.map(\.handle))
        let transformHandles = Set(transforms.map(\.handle))
        let stateHandles = Set(renderStates.map(\.state_handle))
        for draw in drawCommands where draw.command_kind == UInt32(GE_SOURCE_DRAW_V6_TRIANGLES) {
            if draw.transform_handle != 0, !transformHandles.contains(draw.transform_handle) {
                throw GoldenEyeSourceSceneSnapshotV6Error.missingHandle("transform", draw.transform_handle)
            }
            if draw.resource_handle != 0, !resourceHandles.contains(draw.resource_handle) {
                throw GoldenEyeSourceSceneSnapshotV6Error.missingHandle("resource", draw.resource_handle)
            }
            if draw.render_state_handle != 0, !stateHandles.contains(draw.render_state_handle) {
                throw GoldenEyeSourceSceneSnapshotV6Error.missingHandle("render state", draw.render_state_handle)
            }
            try validateRange(
                first: draw.first_vertex, count: draw.vertex_count,
                total: vertices.count, name: "draw \(draw.draw_handle) vertices"
            )
            try validateRange(
                first: draw.first_index, count: draw.index_count,
                total: indices.count, name: "draw \(draw.draw_handle) indices"
            )
            // A V6 index record is one source triangle (three scalar indices),
            // so index_count counts GESourceIndexV6 records rather than
            // individual UInt32 entries.
            guard draw.index_count > 0 else {
                throw GoldenEyeSourceSceneSnapshotV6Error.invalidRecord(
                    "triangle draw \(draw.draw_handle) index count"
                )
            }
            // A composed frame uses one shared Metal vertex buffer. Global
            // bounds alone are insufficient: an otherwise in-range index can
            // accidentally address a neighboring model's vertices after
            // concatenation and produce cross-model strips. Keep the copied
            // draw span authoritative and reject that alias at the immutable
            // snapshot boundary before any GPU command is encoded.
            let vertexStart = UInt64(draw.first_vertex)
            let vertexEnd = vertexStart + UInt64(draw.vertex_count)
            let indexStart = Int(draw.first_index)
            let indexEnd = indexStart + Int(draw.index_count)
            for index in indices[indexStart..<indexEnd] {
                for vertex in [index.vertex0, index.vertex1, index.vertex2] {
                    let value = UInt64(vertex)
                    guard value >= vertexStart, value < vertexEnd else {
                        throw GoldenEyeSourceSceneSnapshotV6Error.rangeOverflow(
                            "draw \(draw.draw_handle) index \(index.handle) vertex \(vertex) outside \(vertexStart)..<\(vertexEnd)"
                        )
                    }
                }
            }
        }
        for index in indices {
            guard Int(index.vertex0) < vertices.count,
                  Int(index.vertex1) < vertices.count,
                  Int(index.vertex2) < vertices.count else {
                throw GoldenEyeSourceSceneSnapshotV6Error.rangeOverflow("index \(index.handle) vertex reference")
            }
        }
    }

    private static func validateEnvelope(
        _ header: GEAbiHeaderV1,
        expectedSize: Int,
        name: String
    ) throws {
        guard header.abi_version == UInt32(GE_NATIVE_ABI_VERSION),
              header.struct_size == UInt32(expectedSize) else {
            throw GoldenEyeSourceSceneSnapshotV6Error.invalidEnvelope(name)
        }
    }

    private static func validateCount(_ name: String, expected: Int, actual: Int) throws {
        guard expected == actual else {
            throw GoldenEyeSourceSceneSnapshotV6Error.countMismatch(name, expected: expected, actual: actual)
        }
    }

    private static func validateRange(first: UInt32, count: UInt32, total: Int, name: String) throws {
        guard Int(first) <= total, Int(count) <= total - Int(first) else {
            throw GoldenEyeSourceSceneSnapshotV6Error.rangeOverflow(name)
        }
    }

    private static func requireUnique(_ handles: [UInt32], kind: String) throws {
        var seen = Set<UInt32>()
        for handle in handles {
            guard handle != UInt32(GE_SOURCE_SCENE_V6_HANDLE_INVALID) else {
                throw GoldenEyeSourceSceneSnapshotV6Error.invalidRecord("zero \(kind) handle")
            }
            guard seen.insert(handle).inserted else {
                throw GoldenEyeSourceSceneSnapshotV6Error.duplicateHandle(kind, handle)
            }
        }
    }

    private static func validate(resource value: GESourceResourceV6) throws {
        try validateEnvelope(value.header, expectedSize: MemoryLayout<GESourceResourceV6>.size, name: "resource")
        guard value.record_version == UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION),
              value.resource_kind > 0, value.resource_kind <= UInt32(GE_SOURCE_RESOURCE_V6_KIND_MAX),
              value.flags & ~UInt32(GE_SOURCE_RESOURCE_V6_FLAG_MASK) == 0,
              value.handle != 0, value.format <= UInt32(GE_SOURCE_RESOURCE_V6_FORMAT_MAX),
              value.mip_count > 0, value.mip_count <= 32,
              value.level_count > 0, value.level_count <= 32,
              value.byte_size > 0 else {
            throw GoldenEyeSourceSceneSnapshotV6Error.invalidRecord("resource \(value.handle)")
        }
        if value.resource_kind == UInt32(GE_SOURCE_RESOURCE_V6_TEXTURE) {
            guard value.format != UInt32(GE_SOURCE_RESOURCE_V6_FORMAT_NONE),
                  value.width > 0, value.height > 0, value.depth > 0 else {
                throw GoldenEyeSourceSceneSnapshotV6Error.invalidRecord("texture \(value.handle) dimensions")
            }
            guard value.content_hash != 0, value.provenance_hash != 0 else {
                throw GoldenEyeSourceSceneSnapshotV6Error.invalidHash("texture \(value.handle)")
            }
        }
        guard value.reserved0 == 0, value.reserved1 == 0 else {
            throw GoldenEyeSourceSceneSnapshotV6Error.reservedField("resource \(value.handle)")
        }
    }

    private static func validate(transform value: GESourceTransformV6) throws {
        try validateEnvelope(value.header, expectedSize: MemoryLayout<GESourceTransformV6>.size, name: "transform")
        guard value.record_version == UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION),
              value.transform_kind > 0, value.transform_kind <= UInt32(GE_SOURCE_TRANSFORM_V6_KIND_MAX),
              value.flags & ~UInt32(GE_SOURCE_TRANSFORM_V6_FLAG_MASK) == 0,
              value.handle != 0 else {
            throw GoldenEyeSourceSceneSnapshotV6Error.invalidRecord("transform \(value.handle)")
        }
        guard value.reserved0 == 0, value.reserved1 == 0, value.reserved2 == 0 else {
            throw GoldenEyeSourceSceneSnapshotV6Error.reservedField("transform \(value.handle)")
        }
    }

    private static func validate(animationPose value: GESourceAnimationPoseV6) throws {
        try validateEnvelope(value.header, expectedSize: MemoryLayout<GESourceAnimationPoseV6>.size, name: "animation pose")
        guard value.record_version == UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION),
              value.flags & ~UInt32(GE_SOURCE_POSE_V6_FLAG_MASK) == 0,
              value.pose_handle != 0, value.skeleton_handle != 0, value.node_handle != 0,
              value.pose_hash != 0 else {
            throw GoldenEyeSourceSceneSnapshotV6Error.invalidRecord("animation pose \(value.pose_handle)")
        }
        guard value.reserved0 == 0, value.reserved1 == 0, value.reserved2 == 0 else {
            throw GoldenEyeSourceSceneSnapshotV6Error.reservedField("animation pose \(value.pose_handle)")
        }
    }

    private static func validate(vertex value: GESourceVertexV6) throws {
        try validateEnvelope(value.header, expectedSize: MemoryLayout<GESourceVertexV6>.size, name: "vertex")
        guard value.record_version == UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION),
              value.handle != 0,
              value.flags & ~UInt32(GE_SOURCE_VERTEX_V6_FLAG_MASK) == 0 else {
            throw GoldenEyeSourceSceneSnapshotV6Error.invalidRecord("vertex \(value.handle)")
        }
        guard value.reserved0 == 0, value.reserved1 == 0 else {
            throw GoldenEyeSourceSceneSnapshotV6Error.reservedField("vertex \(value.handle)")
        }
    }

    private static func validate(index value: GESourceIndexV6) throws {
        try validateEnvelope(value.header, expectedSize: MemoryLayout<GESourceIndexV6>.size, name: "index")
        guard value.record_version == UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION),
              value.handle != 0,
              value.flags & ~UInt32(GE_SOURCE_INDEX_V6_FLAG_MASK) == 0 else {
            throw GoldenEyeSourceSceneSnapshotV6Error.invalidRecord("index \(value.handle)")
        }
        guard value.reserved0 == 0, value.reserved1 == 0 else {
            throw GoldenEyeSourceSceneSnapshotV6Error.reservedField("index \(value.handle)")
        }
    }

    private static func validate(renderState value: GESourceRenderStateV6) throws {
        try validateEnvelope(value.header, expectedSize: MemoryLayout<GESourceRenderStateV6>.size, name: "render state")
        guard value.record_version == UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION),
              value.state_handle != 0, value.material_handle != 0,
              value.flags & ~UInt32(GE_SOURCE_RENDER_STATE_V6_FLAG_MASK) == 0,
              value.combiner_cycle_count >= 1, value.combiner_cycle_count <= 2,
              value.depth_mode <= UInt32(GE_SOURCE_DEPTH_V6_MAX),
              value.alpha_mode <= UInt32(GE_SOURCE_ALPHA_V6_MAX),
              value.coverage_mode <= UInt32(GE_SOURCE_COVERAGE_V6_MAX),
              value.cull_mode <= UInt32(GE_SOURCE_CULL_V6_MAX),
              value.filter_mode <= UInt32(GE_SOURCE_FILTER_V6_MAX),
              value.wrap_s <= UInt32(GE_SOURCE_WRAP_V6_MAX),
              value.wrap_t <= UInt32(GE_SOURCE_WRAP_V6_MAX),
              value.lod_max_q16 >= value.lod_min_q16 else {
            throw GoldenEyeSourceSceneSnapshotV6Error.invalidRecord("render state \(value.state_handle)")
        }
        guard value.reserved0 == 0, value.reserved1 == 0 else {
            throw GoldenEyeSourceSceneSnapshotV6Error.reservedField("render state \(value.state_handle)")
        }
    }

    private static func validate(drawCommand value: GESourceDrawCommandV6) throws {
        try validateEnvelope(value.header, expectedSize: MemoryLayout<GESourceDrawCommandV6>.size, name: "draw command")
        guard value.record_version == UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION),
              value.command_kind > 0, value.command_kind <= UInt32(GE_SOURCE_DRAW_V6_KIND_MAX),
              value.flags & ~UInt32(GE_SOURCE_DRAW_V6_FLAG_MASK) == 0,
              value.draw_handle != 0, value.instance_count > 0,
              value.scissor_width > 0, value.scissor_height > 0,
              value.draw_hash != 0 else {
            throw GoldenEyeSourceSceneSnapshotV6Error.invalidRecord("draw command \(value.draw_handle)")
        }
        guard value.reserved0 == 0, value.reserved1 == 0 else {
            throw GoldenEyeSourceSceneSnapshotV6Error.reservedField("draw command \(value.draw_handle)")
        }
    }

    private static func validate(textEvent value: GESourceTextEventV6) throws {
        try validateEnvelope(value.header, expectedSize: MemoryLayout<GESourceTextEventV6>.size, name: "text event")
        guard value.record_version == UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION),
              value.event_kind > 0, value.event_kind <= UInt32(GE_SOURCE_TEXT_V6_KIND_MAX),
              value.flags & ~UInt32(GE_SOURCE_TEXT_V6_FLAG_MASK) == 0,
              value.text_handle != 0, value.glyph_run_handle != 0,
              value.glyph_count > 0, value.string_hash != 0 else {
            throw GoldenEyeSourceSceneSnapshotV6Error.invalidRecord("text event \(value.text_handle)")
        }
        guard value.reserved0 == 0, value.reserved1 == 0 else {
            throw GoldenEyeSourceSceneSnapshotV6Error.reservedField("text event \(value.text_handle)")
        }
    }

    private static func validate(audioEvent value: GESourceAudioEventV6) throws {
        try validateEnvelope(value.header, expectedSize: MemoryLayout<GESourceAudioEventV6>.size, name: "audio event")
        guard value.record_version == UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION),
              value.event_kind > 0, value.event_kind <= UInt32(GE_SOURCE_AUDIO_V6_KIND_MAX),
              value.flags & ~UInt32(GE_SOURCE_AUDIO_V6_FLAG_MASK) == 0,
              value.event_handle != 0, value.asset_handle != 0,
              value.event_hash != 0 else {
            throw GoldenEyeSourceSceneSnapshotV6Error.invalidRecord("audio event \(value.event_handle)")
        }
        guard value.reserved0 == 0, value.reserved1 == 0, value.reserved2 == 0,
              value.reserved3 == 0, value.reserved4 == 0 else {
            throw GoldenEyeSourceSceneSnapshotV6Error.reservedField("audio event \(value.event_handle)")
        }
    }

    private static func validate(diagnostic value: GESourceDiagnosticV6) throws {
        try validateEnvelope(value.header, expectedSize: MemoryLayout<GESourceDiagnosticV6>.size, name: "diagnostic")
        guard value.record_version == UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION),
              value.diagnostic_kind > 0, value.diagnostic_kind <= UInt32(GE_SOURCE_DIAGNOSTIC_V6_KIND_MAX),
              value.severity <= UInt32(GE_SOURCE_DIAGNOSTIC_V6_SEVERITY_MAX) else {
            throw GoldenEyeSourceSceneSnapshotV6Error.invalidRecord("diagnostic")
        }
        guard value.reserved0 == 0, value.reserved1 == 0 else {
            throw GoldenEyeSourceSceneSnapshotV6Error.reservedField("diagnostic")
        }
    }

    private static func hash(resource value: GESourceResourceV6) -> UInt64 {
        var hash = GEV6Hash.header(value.header)
        hash = GEV6Hash.u32(hash, value.record_version)
        hash = GEV6Hash.u32(hash, value.resource_kind)
        hash = GEV6Hash.u32(hash, value.flags)
        hash = GEV6Hash.u32(hash, value.handle)
        hash = GEV6Hash.u32(hash, value.source_id)
        hash = GEV6Hash.u32(hash, value.format)
        hash = GEV6Hash.u32(hash, value.width)
        hash = GEV6Hash.u32(hash, value.height)
        hash = GEV6Hash.u32(hash, value.depth)
        hash = GEV6Hash.u32(hash, value.mip_count)
        hash = GEV6Hash.u32(hash, value.level_count)
        hash = GEV6Hash.u32(hash, value.byte_size)
        hash = GEV6Hash.u64(hash, value.content_hash)
        hash = GEV6Hash.u64(hash, value.provenance_hash)
        hash = GEV6Hash.u32(hash, value.reserved0)
        return GEV6Hash.u32(hash, value.reserved1)
    }

    private static func hash(transform value: GESourceTransformV6) -> UInt64 {
        var hash = GEV6Hash.header(value.header)
        hash = GEV6Hash.u32(hash, value.record_version)
        hash = GEV6Hash.u32(hash, value.transform_kind)
        hash = GEV6Hash.u32(hash, value.flags)
        hash = GEV6Hash.u32(hash, value.handle)
        hash = GEV6Hash.u32(hash, value.parent_handle)
        hash = GEV6Hash.u32(hash, value.source_node)
        hash = GEV6Hash.u32(hash, value.viewport_id)
        hash = GEV6Hash.u32(hash, value.reserved0)
        hash = GEV6Hash.i32Tuple(hash, value.matrix_q16, count: 16)
        hash = GEV6Hash.u32(hash, value.reserved1)
        return GEV6Hash.u32(hash, value.reserved2)
    }

    private static func hash(animationPose value: GESourceAnimationPoseV6) -> UInt64 {
        var hash = GEV6Hash.header(value.header)
        hash = GEV6Hash.u32(hash, value.record_version)
        hash = GEV6Hash.u32(hash, value.pose_handle)
        hash = GEV6Hash.u32(hash, value.skeleton_handle)
        hash = GEV6Hash.u32(hash, value.node_handle)
        hash = GEV6Hash.u32(hash, value.parent_handle)
        hash = GEV6Hash.u32(hash, value.flags)
        hash = GEV6Hash.u32(hash, value.animation_tick)
        hash = GEV6Hash.u32(hash, value.reserved0)
        hash = GEV6Hash.i32Tuple(hash, value.translation_q16, count: 3)
        hash = GEV6Hash.i32Tuple(hash, value.rotation_q16, count: 4)
        hash = GEV6Hash.i32Tuple(hash, value.scale_q16, count: 3)
        hash = GEV6Hash.u64(hash, value.pose_hash)
        hash = GEV6Hash.u32(hash, value.reserved1)
        return GEV6Hash.u32(hash, value.reserved2)
    }

    private static func hash(vertex value: GESourceVertexV6) -> UInt64 {
        var hash = GEV6Hash.header(value.header)
        hash = GEV6Hash.u32(hash, value.record_version)
        hash = GEV6Hash.u32(hash, value.handle)
        hash = GEV6Hash.u32(hash, value.flags)
        hash = GEV6Hash.i32Tuple(hash, value.position_q16, count: 3)
        hash = GEV6Hash.i32Tuple(hash, value.texcoord_q16, count: 2)
        hash = GEV6Hash.i32Tuple(hash, value.normal_q16, count: 3)
        hash = GEV6Hash.u32(hash, value.color_rgba)
        hash = GEV6Hash.u32(hash, value.source_index)
        hash = GEV6Hash.u32(hash, value.reserved0)
        return GEV6Hash.u32(hash, value.reserved1)
    }

    private static func hash(index value: GESourceIndexV6) -> UInt64 {
        var hash = GEV6Hash.header(value.header)
        hash = GEV6Hash.u32(hash, value.record_version)
        hash = GEV6Hash.u32(hash, value.handle)
        hash = GEV6Hash.u32(hash, value.flags)
        hash = GEV6Hash.u32(hash, value.vertex0)
        hash = GEV6Hash.u32(hash, value.vertex1)
        hash = GEV6Hash.u32(hash, value.vertex2)
        hash = GEV6Hash.u32(hash, value.source_index)
        hash = GEV6Hash.u32(hash, value.reserved0)
        return GEV6Hash.u32(hash, value.reserved1)
    }

    private static func hash(renderState value: GESourceRenderStateV6) -> UInt64 {
        let fields: [UInt32] = [
            value.record_version, value.state_handle, value.flags, value.material_handle,
            value.combiner_cycle_count, value.cycle0_color_a, value.cycle0_color_b,
            value.cycle0_color_c, value.cycle0_color_d, value.cycle0_alpha_a,
            value.cycle0_alpha_b, value.cycle0_alpha_c, value.cycle0_alpha_d,
            value.cycle1_color_a, value.cycle1_color_b, value.cycle1_color_c,
            value.cycle1_color_d, value.cycle1_alpha_a, value.cycle1_alpha_b,
            value.cycle1_alpha_c, value.cycle1_alpha_d, value.primitive_rgba,
            value.environment_rgba, value.fog_rgba, value.blend_rgba, value.depth_mode,
            value.alpha_mode, value.coverage_mode, value.cull_mode, value.filter_mode,
            value.wrap_s, value.wrap_t, value.lod_min_q16, value.lod_max_q16,
            value.raw_othermode_h, value.raw_othermode_l, value.raw_render_mode,
            value.raw_blender_a, value.raw_blender_b, value.raw_blender_c, value.raw_blender_d,
            value.reserved0, value.reserved1
        ]
        var hash = GEV6Hash.header(value.header)
        for field in fields { hash = GEV6Hash.u32(hash, field) }
        return hash
    }

    private static func hash(drawCommand value: GESourceDrawCommandV6) -> UInt64 {
        var hash = GEV6Hash.header(value.header)
        for field in [
            value.record_version, value.command_kind, value.flags, value.draw_handle,
            value.transform_handle, value.resource_handle, value.render_state_handle,
            value.first_vertex, value.vertex_count, value.first_index, value.index_count,
            value.instance_count, value.text_handle, value.sort_key
        ] { hash = GEV6Hash.u32(hash, field) }
        hash = GEV6Hash.i32(hash, value.depth_q16)
        hash = GEV6Hash.i32(hash, value.scissor_x)
        hash = GEV6Hash.i32(hash, value.scissor_y)
        hash = GEV6Hash.u32(hash, value.scissor_width)
        hash = GEV6Hash.u32(hash, value.scissor_height)
        hash = GEV6Hash.u64(hash, value.draw_hash)
        hash = GEV6Hash.u32(hash, value.reserved0)
        return GEV6Hash.u32(hash, value.reserved1)
    }

    private static func hash(textEvent value: GESourceTextEventV6) -> UInt64 {
        var hash = GEV6Hash.header(value.header)
        for field in [
            value.record_version, value.event_kind, value.flags, value.text_handle,
            value.glyph_run_handle
        ] { hash = GEV6Hash.u32(hash, field) }
        for field in [value.x_q16, value.y_q16, value.scale_x_q16, value.scale_y_q16] {
            hash = GEV6Hash.i32(hash, field)
        }
        hash = GEV6Hash.u32(hash, value.color_rgba)
        hash = GEV6Hash.i32(hash, value.scissor_x)
        hash = GEV6Hash.i32(hash, value.scissor_y)
        hash = GEV6Hash.u32(hash, value.scissor_width)
        hash = GEV6Hash.u32(hash, value.scissor_height)
        hash = GEV6Hash.u32(hash, value.glyph_count)
        hash = GEV6Hash.u64(hash, value.string_hash)
        hash = GEV6Hash.u32(hash, value.reserved0)
        return GEV6Hash.u32(hash, value.reserved1)
    }

    private static func hash(audioEvent value: GESourceAudioEventV6) -> UInt64 {
        var hash = GEV6Hash.header(value.header)
        for field in [
            value.record_version, value.event_kind, value.flags, value.event_handle,
            value.asset_handle, value.slot, value.voice, value.note, value.velocity,
            value.reserved0
        ] { hash = GEV6Hash.u32(hash, field) }
        hash = GEV6Hash.i32(hash, value.pitch_q16)
        hash = GEV6Hash.i32(hash, value.pan_q16)
        hash = GEV6Hash.i32(hash, value.gain_q16)
        hash = GEV6Hash.u32(hash, value.reserved1)
        hash = GEV6Hash.u64(hash, value.sample_index)
        hash = GEV6Hash.u32(hash, value.duration_frames)
        hash = GEV6Hash.u32(hash, value.loop_begin)
        hash = GEV6Hash.u32(hash, value.loop_end)
        hash = GEV6Hash.u32(hash, value.reserved2)
        hash = GEV6Hash.u64(hash, value.event_hash)
        hash = GEV6Hash.u32(hash, value.reserved3)
        return GEV6Hash.u32(hash, value.reserved4)
    }

    private static func hash(diagnostic value: GESourceDiagnosticV6) -> UInt64 {
        var hash = GEV6Hash.header(value.header)
        for field in [
            value.record_version, value.diagnostic_kind, value.flags, value.severity,
            value.code, value.source_id, value.command_id, value.first_bad_index,
            value.item_count
        ] { hash = GEV6Hash.u32(hash, field) }
        hash = GEV6Hash.u64(hash, value.detail_hash)
        hash = GEV6Hash.u32(hash, value.reserved0)
        return GEV6Hash.u32(hash, value.reserved1)
    }
}

private enum GEV6Hash {
    static let offset: UInt64 = 1_469_598_103_934_665_603
    static let prime: UInt64 = 1_099_511_628_211

    static func byte(_ hash: UInt64, _ value: UInt8) -> UInt64 {
        (hash ^ UInt64(value)) &* prime
    }

    static func u32(_ hash: UInt64, _ value: UInt32) -> UInt64 {
        var result = hash
        result = byte(result, UInt8(truncatingIfNeeded: value))
        result = byte(result, UInt8(truncatingIfNeeded: value >> 8))
        result = byte(result, UInt8(truncatingIfNeeded: value >> 16))
        return byte(result, UInt8(truncatingIfNeeded: value >> 24))
    }

    static func i32(_ hash: UInt64, _ value: Int32) -> UInt64 {
        u32(hash, UInt32(bitPattern: value))
    }

    static func u64(_ hash: UInt64, _ value: UInt64) -> UInt64 {
        let result = u32(hash, UInt32(truncatingIfNeeded: value))
        return u32(result, UInt32(truncatingIfNeeded: value >> 32))
    }

    static func header(_ value: GEAbiHeaderV1) -> UInt64 {
        u32(u32(offset, value.abi_version), value.struct_size)
    }

    static func i32Tuple<T>(_ hash: UInt64, _ value: T, count: Int) -> UInt64 {
        let values: [Int32] = withUnsafeBytes(of: value) { rawBytes in
            Array(rawBytes.bindMemory(to: Int32.self).prefix(count))
        }
        var result = hash
        for item in values { result = i32(result, item) }
        return result
    }
}
