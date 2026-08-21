#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif
import Foundation

private func setHeader(_ header: inout GEAbiHeaderV1, size: Int) {
    header.abi_version = UInt32(GE_NATIVE_ABI_VERSION)
    header.struct_size = UInt32(size)
}

private func packBlender(_ mode: UInt32, _ shift: UInt32) -> UInt32 {
    ((mode >> shift) & 3) |
        (((mode >> (shift - 2)) & 3) << 2)
}

private func rarewareState() -> GESourceRenderStateV6 {
    let zero = GoldenEyeSourceSceneCombinerSelectorV6.zero
    let texel0 = GoldenEyeSourceSceneCombinerSelectorV6.texel0
    let combined = GoldenEyeSourceSceneCombinerSelectorV6.combined
    let primitive = GoldenEyeSourceSceneCombinerSelectorV6.primitive
    let lod = GoldenEyeSourceSceneCombinerSelectorV6.lodFraction
    var value = GESourceRenderStateV6()
    setHeader(&value.header, size: MemoryLayout<GESourceRenderStateV6>.size)
    value.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
    value.state_handle = 0x7700_0001
    value.material_handle = 0x7700_0002
    value.combiner_cycle_count = 2
    value.cycle0_color_a = texel0
    value.cycle0_color_b = texel0
    value.cycle0_color_c = lod
    value.cycle0_color_d = texel0
    value.cycle0_alpha_a = texel0
    value.cycle0_alpha_b = texel0
    value.cycle0_alpha_c = lod
    value.cycle0_alpha_d = texel0
    value.cycle1_color_a = combined
    value.cycle1_color_b = zero
    value.cycle1_color_c = primitive
    value.cycle1_color_d = zero
    value.cycle1_alpha_a = combined
    value.cycle1_alpha_b = zero
    value.cycle1_alpha_c = primitive
    value.cycle1_alpha_d = zero
    value.raw_othermode_h = 0x0019_2c00
    value.raw_othermode_l = 0x0f0a_4000
    value.raw_render_mode = value.raw_othermode_l
    value.primitive_rgba = 0xffff_ffff
    value.environment_rgba = 0
    value.fog_rgba = 0
    value.blend_rgba = 0
    value.depth_mode = UInt32(GE_SOURCE_DEPTH_V6_DISABLED)
    value.alpha_mode = UInt32(GE_SOURCE_ALPHA_V6_DISABLED)
    value.coverage_mode = UInt32(GE_SOURCE_COVERAGE_V6_CLAMP)
    value.cull_mode = UInt32(GE_SOURCE_CULL_V6_BACK)
    value.filter_mode = UInt32(GE_SOURCE_FILTER_V6_BILINEAR)
    value.wrap_s = UInt32(GE_SOURCE_WRAP_V6_CLAMP)
    value.wrap_t = UInt32(GE_SOURCE_WRAP_V6_CLAMP)
    value.lod_min_q16 = 0
    value.lod_max_q16 = 5 << 16
    value.raw_blender_a = packBlender(value.raw_render_mode, 30)
    value.raw_blender_b = packBlender(value.raw_render_mode, 26)
    value.raw_blender_c = packBlender(value.raw_render_mode, 22)
    value.raw_blender_d = packBlender(value.raw_render_mode, 18)
    return value
}

private func expectUnsupported(
    _ state: GESourceRenderStateV6,
    _ message: String,
    drawFlags: UInt32 = UInt32(GE_SOURCE_DRAW_V6_FLAG_OPAQUE) |
        UInt32(GE_SOURCE_DRAW_V6_FLAG_SOURCE_ORDERED),
    _ expected: (GoldenEyeSourceScenePipelineV6Error) -> Bool
) {
    do {
        try GoldenEyeSourceScenePipelineV6.validateSupportedState(
            state,
            drawFlags: drawFlags
        )
        preconditionFailure("accepted unsupported Rareware state: \(message)")
    } catch let error as GoldenEyeSourceScenePipelineV6Error {
        precondition(expected(error), "wrong Rareware rejection for \(message): \(error)")
        print("rareware LOD pipeline \(message): \(error) PASS")
    } catch {
        preconditionFailure("unexpected error for \(message): \(error)")
    }
}

@main
struct GoldenEyeRarewareLODPipelineV6Smoke {
    static func main() throws {
        let state = rarewareState()
        let opaque = UInt32(GE_SOURCE_DRAW_V6_FLAG_OPAQUE) |
            UInt32(GE_SOURCE_DRAW_V6_FLAG_SOURCE_ORDERED)
        try GoldenEyeSourceScenePipelineV6.validateSupportedState(
            state,
            drawFlags: opaque,
            textureMipLevels: 6
        )
        let key = GoldenEyeSourceScenePipelineKeyV6(sourceState: state, drawFlags: opaque)
        precondition(key.words.contains(GoldenEyeSourceSceneCombinerSelectorV6.lodFraction))
        print("rareware LOD pipeline canonical: key=\(String(key.evidenceHash, radix: 16)) PASS")

        var oneLevelAlias = state
        oneLevelAlias.combiner_cycle_count = 1
        oneLevelAlias.raw_othermode_h = 0
        oneLevelAlias.raw_othermode_l = 0x0050_2048
        oneLevelAlias.raw_render_mode = oneLevelAlias.raw_othermode_l
        oneLevelAlias.filter_mode = UInt32(GE_SOURCE_FILTER_V6_POINT)
        oneLevelAlias.flags = UInt32(GE_SOURCE_RENDER_STATE_V6_FLAG_ANTIALIAS)
        oneLevelAlias.lod_min_q16 = 0
        oneLevelAlias.lod_max_q16 = 0
        oneLevelAlias.cycle0_color_a = GoldenEyeSourceSceneCombinerSelectorV6.texel1
        oneLevelAlias.cycle0_color_b = GoldenEyeSourceSceneCombinerSelectorV6.zero
        oneLevelAlias.cycle0_color_c = GoldenEyeSourceSceneCombinerSelectorV6.shade
        oneLevelAlias.cycle0_color_d = GoldenEyeSourceSceneCombinerSelectorV6.zero
        oneLevelAlias.cycle0_alpha_a = GoldenEyeSourceSceneCombinerSelectorV6.texel1
        oneLevelAlias.cycle0_alpha_b = GoldenEyeSourceSceneCombinerSelectorV6.zero
        oneLevelAlias.cycle0_alpha_c = GoldenEyeSourceSceneCombinerSelectorV6.one
        oneLevelAlias.cycle0_alpha_d = GoldenEyeSourceSceneCombinerSelectorV6.zero
        oneLevelAlias.cycle1_color_a = GoldenEyeSourceSceneCombinerSelectorV6.zero
        oneLevelAlias.cycle1_color_b = GoldenEyeSourceSceneCombinerSelectorV6.zero
        oneLevelAlias.cycle1_color_c = GoldenEyeSourceSceneCombinerSelectorV6.zero
        oneLevelAlias.cycle1_color_d = GoldenEyeSourceSceneCombinerSelectorV6.zero
        oneLevelAlias.cycle1_alpha_a = GoldenEyeSourceSceneCombinerSelectorV6.zero
        oneLevelAlias.cycle1_alpha_b = GoldenEyeSourceSceneCombinerSelectorV6.zero
        oneLevelAlias.cycle1_alpha_c = GoldenEyeSourceSceneCombinerSelectorV6.zero
        oneLevelAlias.cycle1_alpha_d = GoldenEyeSourceSceneCombinerSelectorV6.zero
        oneLevelAlias.raw_blender_a = packBlender(oneLevelAlias.raw_render_mode, 30)
        oneLevelAlias.raw_blender_b = packBlender(oneLevelAlias.raw_render_mode, 26)
        oneLevelAlias.raw_blender_c = packBlender(oneLevelAlias.raw_render_mode, 22)
        oneLevelAlias.raw_blender_d = packBlender(oneLevelAlias.raw_render_mode, 18)
        try GoldenEyeSourceScenePipelineV6.validateSupportedState(
            oneLevelAlias,
            drawFlags: opaque,
            textureMipLevels: 1
        )
        print("rareware LOD pipeline one-level TEXEL1 alias: PASS")

        var noMip = state
        noMip.lod_max_q16 = 0
        expectUnsupported(noMip, "missing mip chain") {
            if case .unsupportedRasterState = $0 { return true }
            return false
        }

        var nonRareware = state
        nonRareware.raw_othermode_l = 0x0c18_2048
        nonRareware.raw_render_mode = nonRareware.raw_othermode_l
        nonRareware.raw_blender_a = packBlender(nonRareware.raw_render_mode, 30)
        nonRareware.raw_blender_b = packBlender(nonRareware.raw_render_mode, 26)
        nonRareware.raw_blender_c = packBlender(nonRareware.raw_render_mode, 22)
        nonRareware.raw_blender_d = packBlender(nonRareware.raw_render_mode, 18)
        expectUnsupported(nonRareware, "non-Rareware LOD tuple") {
            if case .unsupportedCombiner = $0 { return true }
            return false
        }

        expectUnsupported(
            state,
            "translucent draw mismatch",
            drawFlags: UInt32(GE_SOURCE_DRAW_V6_FLAG_TRANSLUCENT) |
                UInt32(GE_SOURCE_DRAW_V6_FLAG_SOURCE_ORDERED)
        ) {
            if case .unsupportedRasterState = $0 { return true }
            return false
        }

        print("goldeneye_rareware_lod_pipeline_v6_smoke: PASS")
    }
}
