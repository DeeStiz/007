#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif
import Foundation

enum GoldenEyeSourceSceneComposerV6Error: Error, CustomStringConvertible {
    case empty
    case textureCollision(UInt32)
    case invalidResult(index: Int, reason: String)

    var description: String {
        switch self {
        case .empty: return "source scene composer received no scenes"
        case .textureCollision(let handle): return "source scene texture collision 0x\(String(handle, radix: 16))"
        case .invalidResult(let index, let reason):
            return "source scene composer input \(index) is not presentable: \(reason)"
        }
    }
}

/// Bounded value-only composition for repeated source model instances.  It is
/// shared by the File Select owner and the Metal reference harness so the
/// four-wallet frame cannot drift between production and evidence capture.
enum GoldenEyeSourceSceneComposerV6 {
    static func combine(
        _ results: [GoldenEyeGBISceneBuildResultV6],
        frame: GoldenEyeGBISceneFrameContextV6
    ) throws -> GoldenEyeSourceSceneSnapshotV6 {
        guard !results.isEmpty else { throw GoldenEyeSourceSceneComposerV6Error.empty }
        var resources: [GESourceResourceV6] = []
        var transforms: [GESourceTransformV6] = []
        var poses: [GESourceAnimationPoseV6] = []
        var vertices: [GESourceVertexV6] = []
        var indices: [GESourceIndexV6] = []
        var states: [GESourceRenderStateV6] = []
        var draws: [GESourceDrawCommandV6] = []
        var diagnostics: [GESourceDiagnosticV6] = []
        var resourceHandles = Set<UInt32>()
        var resourceHashes: [UInt32: UInt64] = [:]
        var transformHandles = Set<UInt32>()
        var poseHandles = Set<UInt32>()
        var stateHandles = Set<UInt32>()
        var drawHandles = Set<UInt32>()
        var geometryModesByState: [UInt32: UInt32] = [:]
        var modelViewQ16ByState: [UInt32: [Int32]] = [:]

        for (sceneIndex, result) in results.enumerated() {
            guard result.presentable,
                  result.snapshot.isPresentable,
                  result.unsupportedVisibleCount == 0,
                  result.decoderUnsupportedCount == 0,
                  result.snapshot.summary.unsupported_visible_count == 0 else {
                throw GoldenEyeSourceSceneComposerV6Error.invalidResult(
                    index: sceneIndex,
                    reason: "unsupported=\(result.unsupportedVisibleCount) decoder=\(result.decoderUnsupportedCount) presentable=\(result.presentable && result.snapshot.isPresentable)"
                )
            }
            let scene = result.snapshot
            let vertexOffset = UInt32(vertices.count)
            let indexOffset = UInt32(indices.count)
            let resourcePrefix = UInt32(0xE000_0000) | UInt32(sceneIndex + 1) << 20
            let transformPrefix = UInt32(0xE100_0000) | UInt32(sceneIndex + 1) << 20
            let statePrefix = UInt32(0xE200_0000) | UInt32(sceneIndex + 1) << 20
            let drawPrefix = UInt32(0xE300_0000) | UInt32(sceneIndex + 1) << 20
            let posePrefix = UInt32(0xE400_0000) | UInt32(sceneIndex + 1) << 20
            let vertexPrefix = UInt32(0xE500_0000) | UInt32(sceneIndex + 1) << 20
            let indexPrefix = UInt32(0xE600_0000) | UInt32(sceneIndex + 1) << 20
            var resourceMap: [UInt32: UInt32] = [:]
            var transformMap: [UInt32: UInt32] = [:]
            var stateMap: [UInt32: UInt32] = [:]

            for source in scene.resources {
                var value = source
                let sharedTexture = source.resource_kind == UInt32(GE_SOURCE_RESOURCE_V6_TEXTURE)
                    || source.resource_kind == UInt32(GE_SOURCE_RESOURCE_V6_PALETTE)
                if sharedTexture, let priorHash = resourceHashes[source.handle] {
                    guard priorHash == source.content_hash else {
                        throw GoldenEyeSourceSceneComposerV6Error.textureCollision(source.handle)
                    }
                    resourceMap[source.handle] = source.handle
                    continue
                }
                if !sharedTexture || resourceHandles.contains(source.handle) {
                    value.handle = resourcePrefix | UInt32(resources.count & 0x000F_FFFF)
                }
                resourceMap[source.handle] = value.handle
                resourceHandles.insert(value.handle)
                resourceHashes[value.handle] = value.content_hash
                resources.append(value)
            }
            for source in scene.transforms {
                var value = source
                value.handle = transformPrefix | UInt32(transforms.count & 0x000F_FFFF)
                transformMap[source.handle] = value.handle
                transformHandles.insert(value.handle)
                transforms.append(value)
            }
            for source in scene.renderStates {
                var value = source
                value.state_handle = statePrefix | UInt32(states.count & 0x000F_FFFF)
                stateMap[source.state_handle] = value.state_handle
                stateHandles.insert(value.state_handle)
                states.append(value)
            }
            if let lighting = scene.lightingFrameContext {
                for (sourceHandle, mode) in lighting.geometryModesByState {
                    if let mapped = stateMap[sourceHandle] { geometryModesByState[mapped] = mode }
                }
                for (sourceHandle, matrix) in lighting.modelViewQ16ByState {
                    if let mapped = stateMap[sourceHandle] { modelViewQ16ByState[mapped] = matrix }
                }
            }
            for source in scene.vertices {
                var value = source
                value.handle = vertexPrefix | UInt32(vertices.count & 0x000F_FFFF)
                vertices.append(value)
            }
            for source in scene.indices {
                var value = source
                value.handle = indexPrefix | UInt32(indices.count & 0x000F_FFFF)
                // Draw first_vertex/first_index are rebased below, so the
                // copied triangle's vertex references must be rebased by the
                // same source-scene vertex offset. Leaving these local makes
                // later head/weapon scenes index into the body's vertices
                // after composition, producing cross-model strips and wrong
                // attachments despite valid isolated scenes.
                value.vertex0 &+= vertexOffset
                value.vertex1 &+= vertexOffset
                value.vertex2 &+= vertexOffset
                indices.append(value)
            }
            for source in scene.animationPoses {
                var value = source
                value.pose_handle = posePrefix | UInt32(poses.count & 0x000F_FFFF)
                poseHandles.insert(value.pose_handle)
                poses.append(value)
            }
            for source in scene.drawCommands {
                var value = source
                value.draw_handle = drawPrefix | UInt32(draws.count & 0x000F_FFFF)
                value.transform_handle = transformMap[source.transform_handle] ?? source.transform_handle
                value.render_state_handle = stateMap[source.render_state_handle] ?? source.render_state_handle
                value.resource_handle = resourceMap[source.resource_handle] ?? source.resource_handle
                value.first_vertex &+= vertexOffset
                value.first_index &+= indexOffset
                drawHandles.insert(value.draw_handle)
                draws.append(value)
            }
            diagnostics.append(contentsOf: scene.diagnostics)
        }

        var summary = GESourceFrameSummaryV6()
        summary.header.abi_version = UInt32(GE_NATIVE_ABI_VERSION)
        summary.header.struct_size = UInt32(MemoryLayout<GESourceFrameSummaryV6>.size)
        summary.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
        summary.flags = UInt32(GE_SOURCE_FRAME_V6_FLAG_PRESENTABLE)
            | (frame.pairPhase == 0 ? UInt32(GE_SOURCE_FRAME_V6_FLAG_SOURCE_ANCHOR) : UInt32(GE_SOURCE_FRAME_V6_FLAG_INTERPOLATED))
        summary.screen = frame.screen
        summary.subphase = frame.subphase
        summary.native_tick = frame.nativeTick
        summary.reference_tick = frame.referenceTick
        summary.pair_phase = frame.pairPhase
        summary.viewport_width = frame.viewportWidth
        summary.viewport_height = frame.viewportHeight
        summary.logical_width = frame.logicalWidth
        summary.logical_height = frame.logicalHeight
        summary.transform_count = UInt32(transforms.count)
        summary.resource_count = UInt32(resources.count)
        summary.pose_count = UInt32(poses.count)
        summary.vertex_count = UInt32(vertices.count)
        summary.index_count = UInt32(indices.count)
        summary.draw_count = UInt32(draws.count)
        summary.render_state_count = UInt32(states.count)
        summary.text_count = 0
        summary.audio_count = 0
        summary.diagnostic_count = UInt32(diagnostics.count)
        summary.unsupported_visible_count = 0
        var hash: UInt64 = 1_469_598_103_934_665_603
        for result in results {
            hash ^= result.snapshot.copiedRecordAggregateHash
            hash &*= 1_099_511_628_211
            hash ^= result.eventHash
            hash &*= 1_099_511_628_211
        }
        hash ^= UInt64(summary.pose_count) << 32 | UInt64(summary.draw_count)
        if hash == 0 { hash = 1 }
        summary.scene_hash = hash
        summary.render_hash = hash ^ 0x9E37_79B9_7F4A_7C15
        summary.state_hash = hash ^ 0xD1B5_4A32_D192_ED03
        summary.audio_hash = 1
        summary.frame_hash = hash ^ UInt64(frame.nativeTick)
        summary.reserved0 = 0
        summary.reserved1 = 0
        let lighting = try GoldenEyeSourceSceneLightingFrameContextV6(
            screen: frame.screen,
            nativeTick: frame.nativeTick,
            referenceTick: frame.referenceTick,
            sourceTimer: frame.sourceTimer ?? 0,
            pairPhase: frame.pairPhase,
            geometryModesByState: geometryModesByState,
            modelViewQ16ByState: modelViewQ16ByState
        )
        return try GoldenEyeSourceSceneSnapshotV6(
            summary: summary,
            resources: resources,
            transforms: transforms,
            animationPoses: poses,
            vertices: vertices,
            indices: indices,
            renderStates: states,
            drawCommands: draws,
            textEvents: [],
            audioEvents: [],
            diagnostics: diagnostics,
            lightingFrameContext: lighting
        )
    }
}
