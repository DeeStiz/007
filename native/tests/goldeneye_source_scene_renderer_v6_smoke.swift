#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif
import Foundation

private func setHeader(_ header: inout GEAbiHeaderV1, size: Int) {
    header.abi_version = UInt32(GE_NATIVE_ABI_VERSION)
    header.struct_size = UInt32(size)
}

private func setIdentity(_ matrix: inout (Int32, Int32, Int32, Int32,
                                          Int32, Int32, Int32, Int32,
                                          Int32, Int32, Int32, Int32,
                                          Int32, Int32, Int32, Int32)) {
    withUnsafeMutableBytes(of: &matrix) { rawBytes in
        let values = rawBytes.bindMemory(to: Int32.self)
        for index in 0..<16 {
            values[index] = index % 5 == 0 ? 65_536 : 0
        }
    }
}

private func makeResource() -> GESourceResourceV6 {
    var value = GESourceResourceV6()
    setHeader(&value.header, size: MemoryLayout<GESourceResourceV6>.size)
    value.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
    value.resource_kind = UInt32(GE_SOURCE_RESOURCE_V6_TEXTURE)
    value.flags = UInt32(GE_SOURCE_RESOURCE_V6_FLAG_RESIDENT)
        | UInt32(GE_SOURCE_RESOURCE_V6_FLAG_MIP_CHAIN)
    value.handle = 1
    value.source_id = 0x1001
    value.format = UInt32(GE_SOURCE_RESOURCE_V6_FORMAT_RGBA16)
    value.width = 64
    value.height = 32
    value.depth = 1
    value.mip_count = 3
    value.level_count = 3
    value.byte_size = 2_730
    value.content_hash = 0x0123_4567_89ab_cdf0
    value.provenance_hash = 0xfedc_ba98_7654_320f
    return value
}

private func makeTransform() -> GESourceTransformV6 {
    var value = GESourceTransformV6()
    setHeader(&value.header, size: MemoryLayout<GESourceTransformV6>.size)
    value.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
    value.transform_kind = UInt32(GE_SOURCE_TRANSFORM_V6_MODELVIEW)
    value.flags = UInt32(GE_SOURCE_TRANSFORM_V6_FLAG_SOURCE_QUANTIZED)
        | UInt32(GE_SOURCE_TRANSFORM_V6_FLAG_INTERPOLATABLE)
    value.handle = 11
    value.parent_handle = 10
    value.source_node = 0x42
    value.viewport_id = 1
    setIdentity(&value.matrix_q16)
    return value
}

private func makeVertex(_ handle: UInt32, x: Int32, y: Int32) -> GESourceVertexV6 {
    var value = GESourceVertexV6()
    setHeader(&value.header, size: MemoryLayout<GESourceVertexV6>.size)
    value.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
    value.handle = handle
    value.flags = UInt32(GE_SOURCE_VERTEX_V6_FLAG_SOURCE_QUANTIZED)
    value.position_q16.0 = x
    value.position_q16.1 = y
    value.position_q16.2 = 0
    value.texcoord_q16.0 = x == 0 ? 0 : 65_536
    value.texcoord_q16.1 = y == 0 ? 0 : 65_536
    value.normal_q16.2 = 65_536
    value.color_rgba = 0xff_ff_ff_ff
    value.source_index = handle - 81
    return value
}

private func makeIndex() -> GESourceIndexV6 {
    var value = GESourceIndexV6()
    setHeader(&value.header, size: MemoryLayout<GESourceIndexV6>.size)
    value.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
    value.handle = 71
    value.flags = UInt32(GE_SOURCE_INDEX_V6_FLAG_SOURCE_ORDERED)
    value.vertex0 = 0
    value.vertex1 = 1
    value.vertex2 = 2
    value.source_index = 0
    return value
}

private func makeRenderState() -> GESourceRenderStateV6 {
    var value = GESourceRenderStateV6()
    setHeader(&value.header, size: MemoryLayout<GESourceRenderStateV6>.size)
    value.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
    value.state_handle = 31
    // Canonical title opaque mode: AA/alpha-coverage, no Z compare/update,
    // and the source one-cycle blender (IN * A_IN + MEM * A_IN).
    value.flags = UInt32(GE_SOURCE_RENDER_STATE_V6_FLAG_ANTIALIAS)
    value.material_handle = 32
    value.combiner_cycle_count = 1
    value.cycle0_color_a = 1 // TEXEL0
    value.cycle0_color_b = 7 // ZERO
    value.cycle0_color_c = 4 // SHADE
    value.cycle0_color_d = 7 // ZERO
    value.cycle0_alpha_a = 1 // TEXEL0
    value.cycle0_alpha_b = 7 // ZERO
    value.cycle0_alpha_c = 6 // ONE
    value.cycle0_alpha_d = 7 // ZERO
    value.cycle1_color_a = 7 // ZERO (unused in one-cycle state)
    value.cycle1_color_b = 7 // ZERO (unused in one-cycle state)
    value.cycle1_color_c = 7 // ZERO (unused in one-cycle state)
    value.cycle1_color_d = 7 // ZERO (unused in one-cycle state)
    value.cycle1_alpha_a = 7 // ZERO (unused in one-cycle state)
    value.cycle1_alpha_b = 7 // ZERO (unused in one-cycle state)
    value.cycle1_alpha_c = 7 // ZERO (unused in one-cycle state)
    value.cycle1_alpha_d = 7 // ZERO (unused in one-cycle state)
    value.raw_othermode_h = 1 << 19 // perspective-correct source sampling
    value.raw_othermode_l = 0x0050_2048
    value.primitive_rgba = 0xffff_ffff
    value.environment_rgba = 0x1020_3040
    value.depth_mode = UInt32(GE_SOURCE_DEPTH_V6_DISABLED)
    value.alpha_mode = UInt32(GE_SOURCE_ALPHA_V6_DISABLED)
    value.coverage_mode = UInt32(GE_SOURCE_COVERAGE_V6_CLAMP)
    value.cull_mode = UInt32(GE_SOURCE_CULL_V6_BACK)
    value.filter_mode = UInt32(GE_SOURCE_FILTER_V6_POINT)
    value.wrap_s = UInt32(GE_SOURCE_WRAP_V6_CLAMP)
    value.wrap_t = UInt32(GE_SOURCE_WRAP_V6_CLAMP)
    value.raw_render_mode = 0x0050_2048
    value.raw_blender_a = 0
    value.raw_blender_b = 0
    value.raw_blender_c = 5
    value.raw_blender_d = 0
    return value
}

private func makeDraw() -> GESourceDrawCommandV6 {
    var value = GESourceDrawCommandV6()
    setHeader(&value.header, size: MemoryLayout<GESourceDrawCommandV6>.size)
    value.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
    value.command_kind = UInt32(GE_SOURCE_DRAW_V6_TRIANGLES)
    value.flags = UInt32(GE_SOURCE_DRAW_V6_FLAG_OPAQUE)
        | UInt32(GE_SOURCE_DRAW_V6_FLAG_SOURCE_ORDERED)
    value.draw_handle = 41
    value.transform_handle = 11
    value.resource_handle = 1
    value.render_state_handle = 31
    value.first_vertex = 0
    value.vertex_count = 3
    value.first_index = 0
    value.index_count = 1
    value.instance_count = 1
    value.scissor_width = 320
    value.scissor_height = 240
    value.draw_hash = 0xabcd_ef01_2345_6789
    return value
}

private func makeSummary() -> GESourceFrameSummaryV6 {
    var value = GESourceFrameSummaryV6()
    setHeader(&value.header, size: MemoryLayout<GESourceFrameSummaryV6>.size)
    value.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
    value.flags = UInt32(GE_SOURCE_FRAME_V6_FLAG_PRESENTABLE)
        | UInt32(GE_SOURCE_FRAME_V6_FLAG_SOURCE_ANCHOR)
    value.screen = UInt32(GE_SOURCE_FRAME_V6_SCREEN_GOLDENEYE)
    value.native_tick = 2
    value.reference_tick = 1
    value.viewport_width = 320
    value.viewport_height = 240
    value.logical_width = 320
    value.logical_height = 240
    value.transform_count = 1
    value.resource_count = 1
    value.vertex_count = 3
    value.index_count = 1
    value.draw_count = 1
    value.render_state_count = 1
    value.scene_hash = 0x1111_1111_1111_1111
    value.render_hash = 0x2222_2222_2222_2222
    value.state_hash = 0x3333_3333_3333_3333
    value.audio_hash = 0x4444_4444_4444_4444
    value.frame_hash = 0x5555_5555_5555_5555
    return value
}

@main
struct GoldenEyeSourceSceneRendererV6Smoke {
    static func main() throws {
        let resource = makeResource()
        let transform = makeTransform()
        let vertices = [
            makeVertex(81, x: -65_536, y: -65_536),
            makeVertex(82, x: 65_536, y: -65_536),
            makeVertex(83, x: 0, y: 65_536),
        ]
        let index = makeIndex()
        let renderState = makeRenderState()
        let draw = makeDraw()
        let summary = makeSummary()

        let faithful640 = GoldenEyeSourceSceneLayoutV6(
            mode: .faithfulHD,
            drawableWidth: 640,
            drawableHeight: 480
        )
        precondition(faithful640.viewportRect == .init(minX: 0, minY: 0, maxX: 640, maxY: 480))
        precondition(faithful640.sourceCoreRect == faithful640.viewportRect)
        let faithful640Scissor = try faithful640.sourceScissor(
            command: draw,
            logicalWidth: summary.logical_width,
            logicalHeight: summary.logical_height
        )
        precondition(faithful640Scissor == .init(minX: 0, minY: 0, maxX: 640, maxY: 480))

        let faithful1080 = GoldenEyeSourceSceneLayoutV6(
            mode: .faithfulHD,
            drawableWidth: 1920,
            drawableHeight: 1080
        )
        precondition(faithful1080.viewportRect == .init(minX: 240, minY: 0, maxX: 1680, maxY: 1080))
        let faithful1080Scissor = try faithful1080.sourceScissor(
            command: draw,
            logicalWidth: summary.logical_width,
            logicalHeight: summary.logical_height
        )
        precondition(faithful1080Scissor == .init(minX: 240, minY: 0, maxX: 1680, maxY: 1080))

        let adaptive1080 = GoldenEyeSourceSceneLayoutV6(
            mode: .adaptiveWidescreen,
            drawableWidth: 1920,
            drawableHeight: 1080
        )
        precondition(adaptive1080.viewportRect == .init(minX: 0, minY: 0, maxX: 1920, maxY: 1080))
        precondition(adaptive1080.sourceCoreRect == .init(minX: 240, minY: 0, maxX: 1680, maxY: 1080))
        let adaptive1080Scissor: GoldenEyeSourceSceneRectV6
        adaptive1080Scissor = try adaptive1080.sourceScissor(
            command: draw,
            logicalWidth: summary.logical_width,
            logicalHeight: summary.logical_height
        )
        precondition(adaptive1080Scissor == adaptive1080.sourceCoreRect)

        let adaptive1440 = GoldenEyeSourceSceneLayoutV6(
            mode: .adaptiveWidescreen,
            drawableWidth: 3440,
            drawableHeight: 1440
        )
        precondition(adaptive1440.viewportRect == .init(minX: 0, minY: 0, maxX: 3440, maxY: 1440))
        precondition(adaptive1440.sourceCoreRect == .init(minX: 760, minY: 0, maxX: 2680, maxY: 1440))
        let adaptive1440Scissor = try adaptive1440.sourceScissor(
            command: draw,
            logicalWidth: summary.logical_width,
            logicalHeight: summary.logical_height
        )
        fflush(stdout)
        precondition(adaptive1440Scissor == adaptive1440.sourceCoreRect)

        let reference = GoldenEyeSourceSceneLayoutV6(
            mode: .reference320x240,
            drawableWidth: 1920,
            drawableHeight: 1080
        )
        precondition(reference.viewportRect == .init(minX: 0, minY: 0, maxX: 320, maxY: 240))

        let snapshot = try GoldenEyeSourceSceneSnapshotV6(
            summary: summary,
            resources: [resource],
            transforms: [transform],
            animationPoses: [],
            vertices: vertices,
            indices: [index],
            renderStates: [renderState],
            drawCommands: [draw],
            textEvents: [],
            audioEvents: [],
            diagnostics: []
        )

        precondition(snapshot.resources.count == 1)
        precondition(snapshot.vertices.count == 3)
        precondition(snapshot.gpuVertices[0].position.x == -1)
        precondition(snapshot.gpuIndices[0] == GoldenEyeSourceSceneGPUIndexV6(source: index))
        precondition(snapshot.resourceHashes[0] == 0x0a9e_70f2_c9b4_32c9)
        precondition(snapshot.transformHashes[0] == 0x2b7a_4629_ed8f_eff3)
        precondition(snapshot.drawCommandHashes[0] != 0)
        precondition(snapshot.copiedRecordAggregateHash != 0)

        // Global vertex bounds must not allow a composed draw to address a
        // neighboring model's otherwise-valid vertex range. This reproduces
        // the cross-model strip class that only appears after concatenating
        // multiple source scenes.
        var crossModelSummary = summary
        crossModelSummary.vertex_count = 6
        let crossModelVertices = vertices + [
            makeVertex(84, x: -32_768, y: -32_768),
            makeVertex(85, x: 32_768, y: -32_768),
            makeVertex(86, x: 0, y: 32_768),
        ]
        var crossModelIndex = index
        crossModelIndex.vertex2 = 3
        do {
            _ = try GoldenEyeSourceSceneSnapshotV6(
                summary: crossModelSummary,
                resources: [resource],
                transforms: [transform],
                animationPoses: [],
                vertices: crossModelVertices,
                indices: [crossModelIndex],
                renderStates: [renderState],
                drawCommands: [draw],
                textEvents: [],
                audioEvents: [],
                diagnostics: []
            )
            preconditionFailure("cross-model vertex alias was accepted")
        } catch let error as GoldenEyeSourceSceneSnapshotV6Error {
            guard case .rangeOverflow(let name) = error,
                  name.contains("outside") else {
                throw error
            }
        }

        let opaqueKey = GoldenEyeSourceScenePipelineKeyV6(
            sourceState: renderState,
            drawFlags: draw.flags
        )
        var alteredState = renderState
        alteredState.raw_render_mode = 1
        let alteredKey = GoldenEyeSourceScenePipelineKeyV6(
            sourceState: alteredState,
            drawFlags: draw.flags
        )
        precondition(opaqueKey != alteredKey)
        precondition(opaqueKey.words.count == 42)
        precondition(opaqueKey.evidenceHash != alteredKey.evidenceHash)
        try GoldenEyeSourceScenePipelineV6.validateSupportedState(
            renderState,
            drawFlags: draw.flags
        )

        var shadeOnlyState = renderState
        shadeOnlyState.cycle0_color_a = 4 // SHADE
        shadeOnlyState.cycle0_color_b = 7 // ZERO
        shadeOnlyState.cycle0_color_c = 6 // ONE
        shadeOnlyState.cycle0_color_d = 7 // ZERO
        shadeOnlyState.cycle0_alpha_a = 4 // SHADE
        shadeOnlyState.cycle0_alpha_b = 7 // ZERO
        shadeOnlyState.cycle0_alpha_c = 6 // ONE
        shadeOnlyState.cycle0_alpha_d = 7 // ZERO
        try GoldenEyeSourceScenePipelineV6.validateSupportedState(
            shadeOnlyState,
            drawFlags: draw.flags,
            hasTexture: false
        )
        do {
            try GoldenEyeSourceScenePipelineV6.validateSupportedState(
                renderState,
                drawFlags: draw.flags,
                hasTexture: false
            )
            preconditionFailure("TEXEL0 state was accepted without a source texture")
        } catch let error as GoldenEyeSourceScenePipelineV6Error {
            if case .unsupportedCombiner = error {
                // expected
            } else {
                throw error
            }
        }
        let noTextureKey = GoldenEyeSourceScenePipelineKeyV6(
            sourceState: shadeOnlyState,
            drawFlags: draw.flags,
            hasTexture: false
        )
        let textureKey = GoldenEyeSourceScenePipelineKeyV6(
            sourceState: shadeOnlyState,
            drawFlags: draw.flags,
            hasTexture: true
        )
        precondition(noTextureKey != textureKey)
        precondition(noTextureKey.evidenceHash != textureKey.evidenceHash)

        var twoCycleState = renderState
        twoCycleState.combiner_cycle_count = 2
        twoCycleState.raw_othermode_h = (1 << 20) | (1 << 19)
        twoCycleState.raw_othermode_l = 0x0c18_2048
        twoCycleState.raw_render_mode = 0x0c18_2048
        twoCycleState.raw_blender_a = 0
        twoCycleState.raw_blender_b = 3
        twoCycleState.raw_blender_c = 4
        twoCycleState.raw_blender_d = 2
        twoCycleState.cycle1_color_a = 0 // COMBINED
        twoCycleState.cycle1_color_b = 7 // ZERO
        twoCycleState.cycle1_color_c = 6 // ONE
        twoCycleState.cycle1_color_d = 7 // ZERO
        twoCycleState.cycle1_alpha_a = 0 // COMBINED
        twoCycleState.cycle1_alpha_b = 7 // ZERO
        twoCycleState.cycle1_alpha_c = 6 // ONE
        twoCycleState.cycle1_alpha_d = 7 // ZERO
        try GoldenEyeSourceScenePipelineV6.validateSupportedState(
            twoCycleState,
            drawFlags: draw.flags
        )

        var texelOneState = renderState
        texelOneState.cycle0_color_a = 2 // TEXEL1, explicitly unsupported
        do {
            try GoldenEyeSourceScenePipelineV6.validateSupportedState(
                texelOneState,
                drawFlags: draw.flags
            )
            preconditionFailure("TEXEL1 selector was accepted")
        } catch let error as GoldenEyeSourceScenePipelineV6Error {
            if case .unsupportedCombiner = error {
                // expected
            } else {
                throw error
            }
        }

        // A typed one-level setup may select TEXEL1 while maxLOD is zero;
        // source tile semantics alias that request to level zero.  The same
        // selector with a non-zero maxLOD must remain fail-closed.
        try GoldenEyeSourceScenePipelineV6.validateSupportedState(
            texelOneState,
            drawFlags: draw.flags,
            textureMipLevels: 1
        )
        var invalidOneLevelLOD = texelOneState
        invalidOneLevelLOD.lod_max_q16 = 1 << 16
        do {
            try GoldenEyeSourceScenePipelineV6.validateSupportedState(
                invalidOneLevelLOD,
                drawFlags: draw.flags,
                textureMipLevels: 1
            )
            preconditionFailure("one-level TEXEL1 accepted non-zero maxLOD")
        } catch let error as GoldenEyeSourceScenePipelineV6Error {
            if case .unsupportedCombiner = error {
                // expected
            } else {
                throw error
            }
        }

        var fogState = renderState
        fogState.flags |= UInt32(GE_SOURCE_RENDER_STATE_V6_FLAG_FOG)
        fogState.fog_rgba = 0x1020_3040
        do {
            try GoldenEyeSourceScenePipelineV6.validateSupportedState(
                fogState,
                drawFlags: draw.flags
            )
            preconditionFailure("fog state was accepted")
        } catch let error as GoldenEyeSourceScenePipelineV6Error {
            if case .unsupportedRasterState = error {
                // expected
            } else {
                throw error
            }
        }

        var blenderState = renderState
        blenderState.raw_render_mode = 1
        blenderState.raw_othermode_l = 1
        blenderState.raw_blender_a = 1
        do {
            try GoldenEyeSourceScenePipelineV6.validateSupportedState(
                blenderState,
                drawFlags: draw.flags
            )
            preconditionFailure("raw blender state was accepted")
        } catch let error as GoldenEyeSourceScenePipelineV6Error {
            if case .unsupportedRasterState = error {
                // expected
            } else {
                throw error
            }
        }

        var malformed = resource
        malformed.reserved0 = 1
        do {
            _ = try GoldenEyeSourceSceneSnapshotV6(
                summary: summary,
                resources: [malformed],
                transforms: [transform],
                animationPoses: [],
                vertices: vertices,
                indices: [index],
                renderStates: [renderState],
                drawCommands: [draw],
                textEvents: [],
                audioEvents: [],
                diagnostics: []
            )
            preconditionFailure("reserved-field mutation was accepted")
        } catch let error as GoldenEyeSourceSceneSnapshotV6Error {
            precondition(error == .reservedField("resource 1"))
        }

        var unsupported = draw
        unsupported.command_kind = UInt32(GE_SOURCE_DRAW_V6_TEXTURE_RECT)
        let unsupportedSnapshot = try GoldenEyeSourceSceneSnapshotV6(
            summary: summary,
            resources: [resource],
            transforms: [transform],
            animationPoses: [],
            vertices: vertices,
            indices: [index],
            renderStates: [renderState],
            drawCommands: [unsupported],
            textEvents: [],
            audioEvents: [],
            diagnostics: []
        )
        precondition(unsupportedSnapshot.drawCommands[0].command_kind == UInt32(GE_SOURCE_DRAW_V6_TEXTURE_RECT))

        print("goldeneye_source_scene_renderer_v6_smoke: PASS")
    }
}
