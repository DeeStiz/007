#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif
import Foundation

private func setHeader(_ header: inout GEAbiHeaderV1, size: Int) {
    header.abi_version = UInt32(GE_NATIVE_ABI_VERSION)
    header.struct_size = UInt32(size)
}

private func packBlender(_ mode: UInt32, _ cycle0Shift: UInt32, _ cycle1Shift: UInt32) -> UInt32 {
    ((mode >> cycle0Shift) & 3) | (((mode >> cycle1Shift) & 3) << 2)
}

private func applyOtherMode(_ value: UInt32, shift: UInt32, length: UInt32, data: UInt32) -> UInt32 {
    precondition(length > 0 && length <= 32 && shift < 32 && length <= 32 - shift)
    let mask = length == 32 ? UInt32.max : ((UInt32(1) << length) - 1) << shift
    return (value & ~mask) | (data & mask)
}

private func composeRenderMode(_ firstCycle: UInt32, _ secondCycle: UInt32) -> UInt32 {
    firstCycle | secondCycle
}

private func makeState(
    rawH: UInt32,
    rawL: UInt32,
    colors0: [UInt32],
    alphas0: [UInt32],
    colors1: [UInt32] = Array(repeating: 7, count: 4),
    alphas1: [UInt32] = Array(repeating: 7, count: 4),
    lodMax: UInt32 = 0
) -> GESourceRenderStateV6 {
    precondition(colors0.count == 4 && alphas0.count == 4 && colors1.count == 4 && alphas1.count == 4)
    let rawMode = rawL & 0xffff_fff8
    let zCompare = (rawMode >> 4) & 1
    let zUpdate = (rawMode >> 5) & 1
    let aa = (rawMode >> 3) & 1
    var state = GESourceRenderStateV6()
    setHeader(&state.header, size: MemoryLayout<GESourceRenderStateV6>.size)
    state.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
    state.state_handle = 0x7000_0001
    state.material_handle = 0x7100_0001
    state.flags = (aa != 0 ? UInt32(GE_SOURCE_RENDER_STATE_V6_FLAG_ANTIALIAS) : 0)
    if zCompare != 0 || zUpdate != 0 { state.flags |= UInt32(GE_SOURCE_RENDER_STATE_V6_FLAG_DEPTH_TEST) }
    if zUpdate != 0 { state.flags |= UInt32(GE_SOURCE_RENDER_STATE_V6_FLAG_DEPTH_WRITE) }
    state.combiner_cycle_count = ((rawH >> 20) & 3) == 0 ? 1 : 2
    state.cycle0_color_a = colors0[0]; state.cycle0_color_b = colors0[1]
    state.cycle0_color_c = colors0[2]; state.cycle0_color_d = colors0[3]
    state.cycle0_alpha_a = alphas0[0]; state.cycle0_alpha_b = alphas0[1]
    state.cycle0_alpha_c = alphas0[2]; state.cycle0_alpha_d = alphas0[3]
    state.cycle1_color_a = colors1[0]; state.cycle1_color_b = colors1[1]
    state.cycle1_color_c = colors1[2]; state.cycle1_color_d = colors1[3]
    state.cycle1_alpha_a = alphas1[0]; state.cycle1_alpha_b = alphas1[1]
    state.cycle1_alpha_c = alphas1[2]; state.cycle1_alpha_d = alphas1[3]
    state.primitive_rgba = 0xffff_ffff
    state.environment_rgba = 0x1020_3040
    state.depth_mode = zCompare != 0 ? UInt32(GE_SOURCE_DEPTH_V6_LEQUAL) :
        (zUpdate != 0 ? UInt32(GE_SOURCE_DEPTH_V6_ALWAYS) : UInt32(GE_SOURCE_DEPTH_V6_DISABLED))
    state.alpha_mode = rawL & 3
    state.coverage_mode = (rawMode >> 8) & 3
    state.cull_mode = UInt32(GE_SOURCE_CULL_V6_BACK)
    switch (rawH >> 12) & 3 {
    case 0: state.filter_mode = UInt32(GE_SOURCE_FILTER_V6_POINT)
    case 2: state.filter_mode = UInt32(GE_SOURCE_FILTER_V6_BILINEAR)
    case 3: state.filter_mode = UInt32(GE_SOURCE_FILTER_V6_TRILINEAR)
    default: preconditionFailure("unknown source filter bits")
    }
    state.wrap_s = UInt32(GE_SOURCE_WRAP_V6_CLAMP)
    state.wrap_t = UInt32(GE_SOURCE_WRAP_V6_CLAMP)
    state.lod_min_q16 = 0
    state.lod_max_q16 = lodMax
    state.raw_othermode_h = rawH
    state.raw_othermode_l = rawL
    state.raw_render_mode = rawMode
    state.raw_blender_a = packBlender(rawMode, 30, 28)
    state.raw_blender_b = packBlender(rawMode, 26, 24)
    state.raw_blender_c = packBlender(rawMode, 22, 20)
    state.raw_blender_d = packBlender(rawMode, 18, 16)
    return state
}

private func expectUnsupported(
    _ state: GESourceRenderStateV6,
    flags: UInt32,
    _ message: String,
    hasTexture: Bool = true,
    textureMipLevels: UInt32? = nil,
    _ predicate: (GoldenEyeSourceScenePipelineV6Error) -> Bool
) throws {
    do {
        try GoldenEyeSourceScenePipelineV6.validateSupportedState(
            state,
            drawFlags: flags,
            hasTexture: hasTexture,
            textureMipLevels: textureMipLevels
        )
        preconditionFailure("pipeline corpus accepted unsupported \(message)")
    } catch let error as GoldenEyeSourceScenePipelineV6Error {
        print("pipeline corpus \(message): \(error)")
        precondition(predicate(error), "pipeline corpus wrong error for \(message): \(error)")
    }
}

@main
struct GoldenEyeSourceScenePipelineCorpusV6Smoke {
    static func main() throws {
        let opaque = UInt32(GE_SOURCE_DRAW_V6_FLAG_OPAQUE) |
            UInt32(GE_SOURCE_DRAW_V6_FLAG_SOURCE_ORDERED)
        let texel0 = GoldenEyeSourceSceneCombinerSelectorV6.texel0
        let texel1 = GoldenEyeSourceSceneCombinerSelectorV6.texel1
        let lodFraction = GoldenEyeSourceSceneCombinerSelectorV6.lodFraction
        let shade = GoldenEyeSourceSceneCombinerSelectorV6.shade
        let zero = GoldenEyeSourceSceneCombinerSelectorV6.zero
        let one = GoldenEyeSourceSceneCombinerSelectorV6.one
        let combined = GoldenEyeSourceSceneCombinerSelectorV6.combined

        // These are the source command updates, applied in source order. The
        // initial cycle values come from the source setup words; subsequent
        // SETOTHERMODE_H writes are masked updates, not whole-register writes.
        let legalH = applyOtherMode(
            applyOtherMode(applyOtherMode(0, shift: 20, length: 2, data: 0), shift: 17, length: 2, data: 0),
            shift: 12, length: 2, data: 0x0000_2000
        )
        let nintendoH = applyOtherMode(
            applyOtherMode(applyOtherMode(0, shift: 20, length: 2, data: 0), shift: 17, length: 2, data: 0),
            shift: 12, length: 2, data: 0x0000_2000
        )
        let goldenEyeH = applyOtherMode(
            applyOtherMode(applyOtherMode(0x0010_0000, shift: 16, length: 1, data: 0x0001_0000), shift: 17, length: 2, data: 0),
            shift: 12, length: 2, data: 0x0000_2000
        )
        let walletH = applyOtherMode(
            applyOtherMode(applyOtherMode(0x0010_0000, shift: 16, length: 1, data: 0x0001_0000), shift: 17, length: 2, data: 0),
            shift: 12, length: 2, data: 0x0000_2000
        )
        let rarewareOneH = applyOtherMode(0, shift: 20, length: 2, data: 0)
        let rarewareTwoH = applyOtherMode(
            applyOtherMode(0, shift: 20, length: 2, data: 0x0010_0000),
            shift: 16, length: 1, data: 0x0001_0000
        )
        precondition(legalH == 0x0000_2000, "Legal/Nintendo cumulative OtherMode.H")
        precondition(nintendoH == 0x0000_2000, "Nintendo cumulative OtherMode.H")
        precondition(goldenEyeH == 0x0011_2000, "GoldenEye cumulative OtherMode.H")
        precondition(walletH == 0x0011_2000, "Wallet cumulative OtherMode.H")
        precondition(goldenEyeH == walletH, "GoldenEye/Wallet source H divergence")
        precondition(rarewareOneH == 0x0000_0000, "Rareware one-cycle cumulative OtherMode.H")
        precondition(rarewareTwoH == 0x0011_0000, "Rareware two-cycle cumulative OtherMode.H")
        let legalL = composeRenderMode(0x0050_2048, 0)
        let nintendoL = composeRenderMode(0x0050_2048, 0)
        let goldenEyeL = composeRenderMode(0x0c18_2048, 0)
        let walletL = composeRenderMode(0x0c18_2048, 0)
        let rarewareOneL = composeRenderMode(0x0055_2048, 0x0011_2048)
        let rarewareTwoL = composeRenderMode(0x0f0a_4000, 0x0302_4000)
        precondition(legalL == 0x0050_2048, "Legal/Nintendo cumulative OtherMode.L")
        precondition(nintendoL == 0x0050_2048, "Nintendo cumulative OtherMode.L")
        precondition(goldenEyeL == 0x0c18_2048, "GoldenEye cumulative OtherMode.L")
        precondition(walletL == 0x0c18_2048, "Wallet cumulative OtherMode.L")
        precondition(goldenEyeL == walletL, "GoldenEye/Wallet source L divergence")
        precondition(rarewareOneL == 0x0055_2048, "Rareware one-cycle cumulative OtherMode.L")
        precondition(rarewareTwoL == 0x0f0a_4000, "Rareware two-cycle cumulative OtherMode.L")

        let cases: [(String, GESourceRenderStateV6)] = [
            ("Legal", makeState(rawH: legalH, rawL: legalL,
                colors0: [texel0, zero, shade, zero], alphas0: [texel0, zero, one, zero])),
            ("Nintendo", makeState(rawH: nintendoH, rawL: nintendoL,
                colors0: [texel0, zero, shade, zero], alphas0: [texel0, zero, one, zero])),
            ("GoldenEye", makeState(rawH: goldenEyeH, rawL: goldenEyeL,
                colors0: [texel0, zero, shade, zero], alphas0: [texel0, zero, one, zero],
                colors1: [combined, zero, shade, zero], alphas1: [combined, zero, one, zero], lodMax: 65_536)),
            ("Wallet", makeState(rawH: walletH, rawL: walletL,
                colors0: [texel0, zero, shade, zero], alphas0: [texel0, zero, one, zero],
                colors1: [combined, zero, shade, zero], alphas1: [combined, zero, one, zero], lodMax: 65_536)),
            ("Rareware", makeState(rawH: rarewareOneH, rawL: rarewareOneL,
                colors0: [texel0, zero, shade, zero], alphas0: [texel0, zero, one, one])),
        ]
        var keyHashes: [UInt64] = []
        for (name, state) in cases {
            try GoldenEyeSourceScenePipelineV6.validateSupportedState(state, drawFlags: opaque)
            let key = GoldenEyeSourceScenePipelineKeyV6(sourceState: state, drawFlags: opaque)
            keyHashes.append(key.evidenceHash)
            print("pipeline corpus \(name): key=\(String(key.evidenceHash, radix: 16)) rawH=0x\(String(state.raw_othermode_h, radix: 16)) rawL=0x\(String(state.raw_othermode_l, radix: 16)) PASS")
        }
        precondition(keyHashes[0] == keyHashes[1], "same source state did not reuse its key")
        precondition(keyHashes[2] == keyHashes[3], "same GoldenEye/Wallet state did not reuse its key")
        precondition(Set(keyHashes).count == cases.count - 2, "pipeline corpus key collision")

        let legalShadeOnly = makeState(
            rawH: legalH,
            rawL: legalL,
            colors0: [shade, zero, one, zero],
            alphas0: [shade, zero, one, zero]
        )
        let legalShadeCombineW0: UInt32 = 0x00ff_ffff
        let legalShadeCombineW1: UInt32 = 0xfffe_793c
        precondition(legalShadeCombineW0 == 0x00ff_ffff && legalShadeCombineW1 == 0xfffe_793c)
        try GoldenEyeSourceScenePipelineV6.validateSupportedState(
            legalShadeOnly,
            drawFlags: opaque,
            hasTexture: false
        )
        try GoldenEyeSourceScenePipelineV6.validateSupportedState(
            legalShadeOnly,
            drawFlags: opaque,
            hasTexture: true
        )
        try expectUnsupported(cases[0].1, flags: opaque, "Legal TEXEL0 without resource", hasTexture: false) {
            if case .unsupportedCombiner = $0 { return true }
            return false
        }
        print("pipeline corpus Legal shade-only: combine=0x\(String(legalShadeCombineW0, radix: 16))/0x\(String(legalShadeCombineW1, radix: 16)) rawH=0x\(String(legalH, radix: 16)) rawL=0x\(String(legalL, radix: 16)) no-texture PASS")

        var mipState = cases[2].1
        mipState.cycle0_color_a = GoldenEyeSourceSceneCombinerSelectorV6.texel1
        mipState.lod_max_q16 = 65_536
        mipState.raw_othermode_h |= 1 << 16
        do {
            try GoldenEyeSourceScenePipelineV6.validateSupportedState(
                mipState,
                drawFlags: opaque,
                textureMipLevels: 2
            )
        } catch {
            print("pipeline corpus mip reject: \(error)")
            throw error
        }

        // Rareware's second source pass is intentionally retained as a typed
        // gap: its exact source tuple uses LOD_FRACTION and FORCE_BLEND. The
        // corrected cumulative H/L words are still asserted before the gap is
        // reported, so this cannot regress to a guessed one-cycle fixture.
        let rarewareTwo = makeState(
            rawH: rarewareTwoH,
            rawL: rarewareTwoL,
            colors0: [texel0, texel0, 9, texel0],
            alphas0: [texel0, texel0, zero, texel0],
            colors1: [combined, zero, shade, zero],
            alphas1: [combined, zero, shade, zero],
            lodMax: 65_536
        )
        try expectUnsupported(rarewareTwo, flags: opaque, "Rareware second-pass LOD/FORCE_BLEND") {
            switch $0 {
            case .unsupportedCombiner, .unsupportedRasterState: return true
            default: return false
            }
        }
        print("pipeline corpus RarewareTwo: rawH=0x\(String(rarewareTwoH, radix: 16)) rawL=0x\(String(rarewareTwoL, radix: 16)) typed-gap PASS")

        // GoldenEye's logo uses a distinct two-cycle LOD equation from the
        // Rareware segment.  The exact source tuple is
        // (OtherMode.H=0x00112000, OtherMode.L=0x0C182048,
        //  combine=0x26A004/0x1F1093FF), represented here by the normalized
        // selectors preserved in GESourceRenderStateV6.  Both the six-level
        // logo texture and its one-level auxiliary texture are source-valid.
        let goldenEyeLOD = makeState(
            rawH: goldenEyeH,
            rawL: goldenEyeL,
            colors0: [texel1, texel0, lodFraction, texel0],
            alphas0: [texel1, texel0, lodFraction, texel0],
            colors1: [combined, zero, shade, zero],
            alphas1: [combined, zero, shade, zero],
            lodMax: 5 << 16
        )
        try GoldenEyeSourceScenePipelineV6.validateSupportedState(
            goldenEyeLOD,
            drawFlags: opaque,
            hasTexture: true,
            textureMipLevels: 6
        )
        print("pipeline corpus GoldenEyeLOD: rawH=0x\(String(goldenEyeH, radix: 16)) rawL=0x\(String(goldenEyeL, radix: 16)) mipLevels=6 PASS")

        var goldenEyeAuxiliary = goldenEyeLOD
        goldenEyeAuxiliary.lod_max_q16 = 0
        try GoldenEyeSourceScenePipelineV6.validateSupportedState(
            goldenEyeAuxiliary,
            drawFlags: opaque,
            hasTexture: true,
            textureMipLevels: 1
        )
        print("pipeline corpus GoldenEyeLOD auxiliary: rawH=0x\(String(goldenEyeH, radix: 16)) rawL=0x\(String(goldenEyeL, radix: 16)) mipLevels=1 maxLOD=0 PASS")

        var goldenEyeWrongH = goldenEyeLOD
        goldenEyeWrongH.raw_othermode_h = 0x0011_0000
        try expectUnsupported(goldenEyeWrongH, flags: opaque, "GoldenEye LOD wrong OtherMode.H", hasTexture: true, textureMipLevels: 6) {
            switch $0 {
            case .unsupportedCombiner, .unsupportedRasterState: return true
            default: return false
            }
        }
        var goldenEyeWrongL = goldenEyeLOD
        goldenEyeWrongL.raw_othermode_l = 0x0c18_4340
        goldenEyeWrongL.raw_render_mode = 0x0c18_4340
        goldenEyeWrongL.raw_blender_a = packBlender(goldenEyeWrongL.raw_render_mode, 30, 28)
        goldenEyeWrongL.raw_blender_b = packBlender(goldenEyeWrongL.raw_render_mode, 26, 24)
        goldenEyeWrongL.raw_blender_c = packBlender(goldenEyeWrongL.raw_render_mode, 22, 20)
        goldenEyeWrongL.raw_blender_d = packBlender(goldenEyeWrongL.raw_render_mode, 18, 16)
        try expectUnsupported(goldenEyeWrongL, flags: opaque, "GoldenEye LOD wrong OtherMode.L", hasTexture: true, textureMipLevels: 6) {
            switch $0 {
            case .unsupportedCombiner, .unsupportedRasterState: return true
            default: return false
            }
        }
        var goldenEyeAuxiliaryOverflow = goldenEyeAuxiliary
        goldenEyeAuxiliaryOverflow.lod_max_q16 = 65_536
        try expectUnsupported(goldenEyeAuxiliaryOverflow, flags: opaque, "GoldenEye one-level auxiliary maxLOD", hasTexture: true, textureMipLevels: 1) {
            switch $0 {
            case .unsupportedCombiner, .unsupportedRasterState: return true
            default: return false
            }
        }

        var unsupportedSelector = cases[2].1
        unsupportedSelector.cycle0_color_c = 9 // LOD_FRACTION needs a source LOD payload.
        try expectUnsupported(unsupportedSelector, flags: opaque, "LOD_FRACTION") {
            if case .unsupportedCombiner = $0 { return true }
            return false
        }

        // Geometry fog is admitted only for G_FOG plus the exact
        // G_RM_FOG_SHADE_A first-cycle blender tuple.  The fragment shader
        // supplies the source fm/fo/color payload; G_RM_FOG_PRIM_A and a
        // fog render word without G_FOG remain fail-closed.
        var fogShadeState = cases[0].1
        let fogShadeMode: UInt32 = 0xc800_0000 // G_RM_FOG_SHADE_A
        fogShadeState.flags = UInt32(GE_SOURCE_RENDER_STATE_V6_FLAG_FOG)
        fogShadeState.depth_mode = UInt32(GE_SOURCE_DEPTH_V6_DISABLED)
        fogShadeState.coverage_mode = UInt32(GE_SOURCE_COVERAGE_V6_CLAMP)
        fogShadeState.alpha_mode = UInt32(GE_SOURCE_ALPHA_V6_DISABLED)
        // G_SETFOGCOLOR carries an authored alpha byte; the stage renderer
        // supplies the EnvironmentRecord color and exact fm/fo payload.
        fogShadeState.fog_rgba = 0x1020_30ff
        fogShadeState.raw_othermode_l = fogShadeMode
        fogShadeState.raw_render_mode = fogShadeMode
        fogShadeState.raw_blender_a = packBlender(fogShadeMode, 30, 28)
        fogShadeState.raw_blender_b = packBlender(fogShadeMode, 26, 24)
        fogShadeState.raw_blender_c = packBlender(fogShadeMode, 22, 20)
        fogShadeState.raw_blender_d = packBlender(fogShadeMode, 18, 16)
        precondition(GoldenEyeSourceScenePipelineV6.isFogShadeGeometryState(fogShadeState))
        try GoldenEyeSourceScenePipelineV6.validateSupportedState(
            fogShadeState, drawFlags: opaque, hasTexture: true
        )
        var fogPrimState = fogShadeState
        let fogPrimMode: UInt32 = 0xc400_0000 // G_RM_FOG_PRIM_A
        fogPrimState.raw_othermode_l = fogPrimMode
        fogPrimState.raw_render_mode = fogPrimMode
        fogPrimState.raw_blender_a = packBlender(fogPrimMode, 30, 28)
        fogPrimState.raw_blender_b = packBlender(fogPrimMode, 26, 24)
        fogPrimState.raw_blender_c = packBlender(fogPrimMode, 22, 20)
        fogPrimState.raw_blender_d = packBlender(fogPrimMode, 18, 16)
        try expectUnsupported(fogPrimState, flags: opaque, "G_RM_FOG_PRIM_A", hasTexture: true) {
            if case .unsupportedRasterState = $0 { return true }
            return false
        }
        var fogWithoutGeometry = fogShadeState
        fogWithoutGeometry.flags = 0
        try expectUnsupported(fogWithoutGeometry, flags: opaque, "fog blender without G_FOG", hasTexture: true) {
            if case .unsupportedRasterState = $0 { return true }
            return false
        }
        print("pipeline corpus G_FOG/G_RM_FOG_SHADE_A exact tuple PASS")
        var invalidWrap = cases[0].1
        invalidWrap.wrap_s = 99
        try expectUnsupported(invalidWrap, flags: opaque, "unknown wrap") {
            if case .unsupportedRasterState = $0 { return true }
            return false
        }
        var unsupportedCoverage = cases[2].1
        unsupportedCoverage.raw_othermode_l = 0x0c18_4340
        unsupportedCoverage.raw_render_mode = 0x0c18_4340
        unsupportedCoverage.coverage_mode = 3
        unsupportedCoverage.flags = UInt32(GE_SOURCE_RENDER_STATE_V6_FLAG_COVERAGE) |
            UInt32(GE_SOURCE_RENDER_STATE_V6_FLAG_COVERAGE_SAVE)
        unsupportedCoverage.raw_blender_a = packBlender(unsupportedCoverage.raw_render_mode, 30, 28)
        unsupportedCoverage.raw_blender_b = packBlender(unsupportedCoverage.raw_render_mode, 26, 24)
        unsupportedCoverage.raw_blender_c = packBlender(unsupportedCoverage.raw_render_mode, 22, 20)
        unsupportedCoverage.raw_blender_d = packBlender(unsupportedCoverage.raw_render_mode, 18, 16)
        try GoldenEyeSourceScenePipelineV6.validateSupportedState(
            unsupportedCoverage,
            drawFlags: UInt32(GE_SOURCE_DRAW_V6_FLAG_TRANSLUCENT) |
                UInt32(GE_SOURCE_DRAW_V6_FLAG_SOURCE_ORDERED)
        )
        print("pipeline corpus coverage-save: typed source alpha blend PASS")
        print("goldeneye_source_scene_pipeline_corpus_v6_smoke: PASS cases=\(cases.count) keys=\(keyHashes.count)")
    }
}
