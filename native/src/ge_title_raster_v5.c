#include "ge_title_raster_v5.h"

#include <string.h>

enum {
    GE_TITLE_RASTER_H_CYCLE_SHIFT = 20u,
    GE_TITLE_RASTER_H_LOD_SHIFT = 16u,
    GE_TITLE_RASTER_L_ALPHA_MASK = 3u,
    GE_TITLE_RASTER_L_DEPTH_SOURCE_SHIFT = 2u,
    GE_TITLE_RASTER_L_RENDER_SHIFT = 3u,
    GE_TITLE_RASTER_AA_SHIFT = 3u,
    GE_TITLE_RASTER_Z_CMP_SHIFT = 4u,
    GE_TITLE_RASTER_Z_UPD_SHIFT = 5u,
    GE_TITLE_RASTER_IMAGE_READ_SHIFT = 6u,
    GE_TITLE_RASTER_CLEAR_CVG_SHIFT = 7u,
    GE_TITLE_RASTER_CVG_DST_SHIFT = 8u,
    GE_TITLE_RASTER_ZMODE_SHIFT = 10u,
    GE_TITLE_RASTER_CVG_X_ALPHA_SHIFT = 12u,
    GE_TITLE_RASTER_ALPHA_CVG_SHIFT = 13u,
    GE_TITLE_RASTER_FORCE_BLEND_SHIFT = 14u,
};

#define GE_TITLE_RASTER_L_RENDER_MASK UINT32_C(0xfffffff8)

static uint64_t ge_title_raster_hash_byte(uint64_t hash, uint8_t value)
{
    return (hash ^ (uint64_t)value) * UINT64_C(1099511628211);
}

static uint64_t ge_title_raster_hash_u32(uint64_t hash, uint32_t value)
{
    hash = ge_title_raster_hash_byte(hash, (uint8_t)(value & 0xffu));
    hash = ge_title_raster_hash_byte(hash, (uint8_t)((value >> 8) & 0xffu));
    hash = ge_title_raster_hash_byte(hash, (uint8_t)((value >> 16) & 0xffu));
    return ge_title_raster_hash_byte(hash, (uint8_t)(value >> 24));
}

static uint64_t ge_title_raster_hash_u64(uint64_t hash, uint64_t value)
{
    hash = ge_title_raster_hash_u32(hash, (uint32_t)value);
    return ge_title_raster_hash_u32(hash, (uint32_t)(value >> 32));
}

static uint64_t ge_title_raster_hash_init(void)
{
    return UINT64_C(1469598103934665603);
}

static uint32_t ge_title_raster_pack_blender(uint32_t raw_mode, uint32_t shift)
{
    return ((raw_mode >> shift) & 3u) |
           (((raw_mode >> (shift - 4u)) & 3u) << 2) |
           (((raw_mode >> (shift - 8u)) & 3u) << 4) |
           (((raw_mode >> (shift - 12u)) & 3u) << 6);
}

static int ge_title_raster_source_known(uint32_t source_model_mask)
{
    return source_model_mask != 0u &&
           (source_model_mask & ~GE_TITLE_RASTER_V5_SOURCE_MASK) == 0u;
}

static int ge_title_raster_tuple_known(uint32_t raw_h,
                                       uint32_t raw_l,
                                       uint32_t combine_w0,
                                       uint32_t combine_w1)
{
    if (raw_h == GE_TITLE_RASTER_V5_H_ONE_CYCLE &&
        raw_l == GE_TITLE_RASTER_V5_L_ONE_CYCLE) {
        return (combine_w0 == UINT32_C(0x00ffffff) &&
                    combine_w1 == UINT32_C(0xfffe793c)) ||
               (combine_w0 == UINT32_C(0x00121824) &&
                    combine_w1 == UINT32_C(0xff33ffff)) ||
               (combine_w0 == UINT32_C(0x00127e24) &&
                    combine_w1 == UINT32_C(0xfffff9fc));
    }
    if (raw_h == GE_TITLE_RASTER_V5_H_TWO_CYCLE &&
        raw_l == GE_TITLE_RASTER_V5_L_TWO_CYCLE) {
        return (combine_w0 == UINT32_C(0x0026a004) &&
                (combine_w1 == UINT32_C(0x1f1093ff) ||
                 combine_w1 == UINT32_C(0x1ffc93fc)));
    }
    if (raw_h == GE_TITLE_RASTER_V5_H_ONE_CYCLE &&
        raw_l == GE_TITLE_RASTER_V5_L_RAREWARE_ONE_CYCLE) {
        return combine_w0 == UINT32_C(0x00119623) &&
               combine_w1 == UINT32_C(0x002c0000);
    }
    if (raw_h == GE_TITLE_RASTER_V5_H_TWO_CYCLE &&
        raw_l == GE_TITLE_RASTER_V5_L_RAREWARE_TWO_CYCLE) {
        return combine_w0 == UINT32_C(0x00169a03) &&
               combine_w1 == UINT32_C(0x100c9200);
    }
    return raw_h == GE_TITLE_RASTER_V5_H_TWO_CYCLE &&
           raw_l == GE_TITLE_RASTER_V5_L_TWO_CYCLE_FORCE_BLEND &&
           combine_w0 == UINT32_C(0x0026a004) &&
           combine_w1 == UINT32_C(0x1f1093ff);
}

static uint32_t ge_title_raster_tuple_source_mask(
    uint32_t raw_h,
    uint32_t raw_l,
    uint32_t combine_w0,
    uint32_t combine_w1)
{
    if (raw_h == GE_TITLE_RASTER_V5_H_ONE_CYCLE &&
        raw_l == GE_TITLE_RASTER_V5_L_ONE_CYCLE) {
        if (combine_w0 == UINT32_C(0x00121824) &&
            combine_w1 == UINT32_C(0xff33ffff)) {
            return GE_TITLE_RASTER_V5_SOURCE_LEGAL;
        }
        return GE_TITLE_RASTER_V5_SOURCE_LEGAL |
               GE_TITLE_RASTER_V5_SOURCE_NINTENDO |
               GE_TITLE_RASTER_V5_SOURCE_WALLET;
    }
    if (raw_h == GE_TITLE_RASTER_V5_H_TWO_CYCLE &&
        raw_l == GE_TITLE_RASTER_V5_L_TWO_CYCLE) {
        return combine_w1 == UINT32_C(0x1f1093ff)
            ? GE_TITLE_RASTER_V5_SOURCE_GOLDENEYE
            : GE_TITLE_RASTER_V5_SOURCE_WALLET;
    }
    if (raw_h == GE_TITLE_RASTER_V5_H_TWO_CYCLE &&
        raw_l == GE_TITLE_RASTER_V5_L_TWO_CYCLE_FORCE_BLEND) {
        return GE_TITLE_RASTER_V5_SOURCE_WALLET;
    }
    if (raw_h == GE_TITLE_RASTER_V5_H_ONE_CYCLE &&
        raw_l == GE_TITLE_RASTER_V5_L_RAREWARE_ONE_CYCLE) {
        return GE_TITLE_RASTER_V5_SOURCE_RAREWARE;
    }
    if (raw_h == GE_TITLE_RASTER_V5_H_TWO_CYCLE &&
        raw_l == GE_TITLE_RASTER_V5_L_RAREWARE_TWO_CYCLE) {
        return GE_TITLE_RASTER_V5_SOURCE_RAREWARE;
    }
    return 0u;
}

static GETitleRasterStateV5 ge_title_raster_state(
    GETitleRasterSourceStateV5 source)
{
    GETitleRasterStateV5 state;
    memset(&state, 0, sizeof(state));
    state.header.abi_version = GE_NATIVE_ABI_VERSION;
    state.header.struct_size = (uint32_t)sizeof(state);
    state.source_model_mask = source.source_model_mask;
    state.raw_other_mode_h = source.raw_other_mode_h;
    state.raw_other_mode_l = source.raw_other_mode_l;
    state.raw_render_mode = source.raw_other_mode_l & GE_TITLE_RASTER_L_RENDER_MASK;
    state.raw_combine_w0 = source.raw_combine_w0;
    state.raw_combine_w1 = source.raw_combine_w1;
    state.cycle_type = (source.raw_other_mode_h >> GE_TITLE_RASTER_H_CYCLE_SHIFT) & 3u;
    state.texture_lod = (source.raw_other_mode_h >> GE_TITLE_RASTER_H_LOD_SHIFT) & 1u;
    state.alpha_compare = source.raw_other_mode_l & GE_TITLE_RASTER_L_ALPHA_MASK;
    state.depth_source = (source.raw_other_mode_l >> GE_TITLE_RASTER_L_DEPTH_SOURCE_SHIFT) & 1u;
    state.aa_enable = (state.raw_render_mode >> GE_TITLE_RASTER_AA_SHIFT) & 1u;
    state.z_compare = (state.raw_render_mode >> GE_TITLE_RASTER_Z_CMP_SHIFT) & 1u;
    state.z_update = (state.raw_render_mode >> GE_TITLE_RASTER_Z_UPD_SHIFT) & 1u;
    state.image_read = (state.raw_render_mode >> GE_TITLE_RASTER_IMAGE_READ_SHIFT) & 1u;
    state.clear_on_coverage = (state.raw_render_mode >> GE_TITLE_RASTER_CLEAR_CVG_SHIFT) & 1u;
    state.coverage_destination =
        (state.raw_render_mode >> GE_TITLE_RASTER_CVG_DST_SHIFT) & 3u;
    state.z_mode = (state.raw_render_mode >> GE_TITLE_RASTER_ZMODE_SHIFT) & 3u;
    state.coverage_x_alpha =
        (state.raw_render_mode >> GE_TITLE_RASTER_CVG_X_ALPHA_SHIFT) & 1u;
    state.alpha_coverage_select =
        (state.raw_render_mode >> GE_TITLE_RASTER_ALPHA_CVG_SHIFT) & 1u;
    state.force_blend =
        (state.raw_render_mode >> GE_TITLE_RASTER_FORCE_BLEND_SHIFT) & 1u;
    state.blend_cycle0 = ge_title_raster_pack_blender(state.raw_render_mode, 30u);
    state.blend_cycle1 = ge_title_raster_pack_blender(state.raw_render_mode, 28u);

    /* These are facts about this vector, not a generic RDP equivalence claim. */
    if (state.z_compare == 0u && state.z_update == 0u) {
        state.lowering_flags |= GE_TITLE_RASTER_V5_LOWER_NO_DEPTH;
    }
    if (state.alpha_compare == 0u) {
        state.lowering_flags |= GE_TITLE_RASTER_V5_LOWER_ALPHA_NONE;
    }
    if (state.aa_enable != 0u || state.coverage_destination != 0u ||
        state.clear_on_coverage != 0u) {
        state.lowering_flags |= GE_TITLE_RASTER_V5_DEFERRED_COVERAGE;
    }
    if (state.force_blend != 0u) {
        state.lowering_flags |= GE_TITLE_RASTER_V5_DEFERRED_FORCE_BLEND;
    }

    state.state_hash = ge_title_raster_hash_init();
    state.state_hash = ge_title_raster_hash_u32(state.state_hash, state.source_model_mask);
    state.state_hash = ge_title_raster_hash_u32(state.state_hash, state.raw_other_mode_h);
    state.state_hash = ge_title_raster_hash_u32(state.state_hash, state.raw_other_mode_l);
    state.state_hash = ge_title_raster_hash_u32(state.state_hash, state.raw_render_mode);
    state.state_hash = ge_title_raster_hash_u32(state.state_hash, state.raw_combine_w0);
    state.state_hash = ge_title_raster_hash_u32(state.state_hash, state.raw_combine_w1);
    state.state_hash = ge_title_raster_hash_u32(state.state_hash, state.cycle_type);
    state.state_hash = ge_title_raster_hash_u32(state.state_hash, state.texture_lod);
    state.state_hash = ge_title_raster_hash_u32(state.state_hash, state.alpha_compare);
    state.state_hash = ge_title_raster_hash_u32(state.state_hash, state.depth_source);
    state.state_hash = ge_title_raster_hash_u32(state.state_hash, state.aa_enable);
    state.state_hash = ge_title_raster_hash_u32(state.state_hash, state.z_compare);
    state.state_hash = ge_title_raster_hash_u32(state.state_hash, state.z_update);
    state.state_hash = ge_title_raster_hash_u32(state.state_hash, state.image_read);
    state.state_hash = ge_title_raster_hash_u32(state.state_hash, state.clear_on_coverage);
    state.state_hash = ge_title_raster_hash_u32(state.state_hash, state.coverage_destination);
    state.state_hash = ge_title_raster_hash_u32(state.state_hash, state.z_mode);
    state.state_hash = ge_title_raster_hash_u32(state.state_hash, state.coverage_x_alpha);
    state.state_hash = ge_title_raster_hash_u32(state.state_hash, state.alpha_coverage_select);
    state.state_hash = ge_title_raster_hash_u32(state.state_hash, state.force_blend);
    state.state_hash = ge_title_raster_hash_u32(state.state_hash, state.blend_cycle0);
    state.state_hash = ge_title_raster_hash_u32(state.state_hash, state.blend_cycle1);
    state.state_hash = ge_title_raster_hash_u32(state.state_hash, state.lowering_flags);
    return state;
}

GETitleRasterInputV5 ge_title_raster_source_vector_v5(void)
{
    GETitleRasterInputV5 input;
    memset(&input, 0, sizeof(input));
    input.header.abi_version = GE_NATIVE_ABI_VERSION;
    input.header.struct_size = (uint32_t)sizeof(input);
    input.state_count = GE_TITLE_RASTER_V5_STATE_CAPACITY;

    input.states[0] = (GETitleRasterSourceStateV5){
        GE_TITLE_RASTER_V5_SOURCE_LEGAL |
            GE_TITLE_RASTER_V5_SOURCE_NINTENDO |
            GE_TITLE_RASTER_V5_SOURCE_WALLET,
        GE_TITLE_RASTER_V5_H_ONE_CYCLE,
        GE_TITLE_RASTER_V5_L_ONE_CYCLE,
        UINT32_C(0x00ffffff), UINT32_C(0xfffe793c), 0u};
    input.states[1] = (GETitleRasterSourceStateV5){
        GE_TITLE_RASTER_V5_SOURCE_LEGAL,
        GE_TITLE_RASTER_V5_H_ONE_CYCLE,
        GE_TITLE_RASTER_V5_L_ONE_CYCLE,
        UINT32_C(0x00121824), UINT32_C(0xff33ffff), 0u};
    input.states[2] = (GETitleRasterSourceStateV5){
        GE_TITLE_RASTER_V5_SOURCE_LEGAL |
            GE_TITLE_RASTER_V5_SOURCE_NINTENDO |
            GE_TITLE_RASTER_V5_SOURCE_WALLET,
        GE_TITLE_RASTER_V5_H_ONE_CYCLE,
        GE_TITLE_RASTER_V5_L_ONE_CYCLE,
        UINT32_C(0x00127e24), UINT32_C(0xfffff9fc), 0u};
    input.states[3] = (GETitleRasterSourceStateV5){
        GE_TITLE_RASTER_V5_SOURCE_GOLDENEYE,
        GE_TITLE_RASTER_V5_H_TWO_CYCLE,
        GE_TITLE_RASTER_V5_L_TWO_CYCLE,
        UINT32_C(0x0026a004), UINT32_C(0x1f1093ff), 0u};
    input.states[4] = (GETitleRasterSourceStateV5){
        GE_TITLE_RASTER_V5_SOURCE_WALLET,
        GE_TITLE_RASTER_V5_H_TWO_CYCLE,
        GE_TITLE_RASTER_V5_L_TWO_CYCLE,
        UINT32_C(0x0026a004), UINT32_C(0x1ffc93fc), 0u};
    input.states[5] = (GETitleRasterSourceStateV5){
        GE_TITLE_RASTER_V5_SOURCE_WALLET,
        GE_TITLE_RASTER_V5_H_TWO_CYCLE,
        GE_TITLE_RASTER_V5_L_TWO_CYCLE_FORCE_BLEND,
        UINT32_C(0x0026a004), UINT32_C(0x1f1093ff), 0u};
    input.states[6] = (GETitleRasterSourceStateV5){
        GE_TITLE_RASTER_V5_SOURCE_RAREWARE,
        GE_TITLE_RASTER_V5_H_ONE_CYCLE,
        GE_TITLE_RASTER_V5_L_RAREWARE_ONE_CYCLE,
        UINT32_C(0x00119623), UINT32_C(0x002c0000), 0u};
    input.states[7] = (GETitleRasterSourceStateV5){
        GE_TITLE_RASTER_V5_SOURCE_RAREWARE,
        GE_TITLE_RASTER_V5_H_TWO_CYCLE,
        GE_TITLE_RASTER_V5_L_RAREWARE_TWO_CYCLE,
        UINT32_C(0x00169a03), UINT32_C(0x100c9200), 0u};
    return input;
}

GETitleRasterResultV5 ge_title_lower_raster_v5(GETitleRasterInputV5 input)
{
    GETitleRasterResultV5 result;
    memset(&result, 0, sizeof(result));
    result.header.abi_version = GE_NATIVE_ABI_VERSION;
    result.header.struct_size = (uint32_t)sizeof(result);
    result.status = GE_STATUS_OK;
    if (input.header.abi_version != GE_NATIVE_ABI_VERSION) {
        result.status = GE_STATUS_INVALID_VERSION;
        return result;
    }
    if (input.header.struct_size != sizeof(input)) {
        result.status = GE_STATUS_INVALID_SIZE;
        return result;
    }
    if (input.reserved != 0u || input.state_count == 0u ||
        input.state_count > GE_TITLE_RASTER_V5_STATE_CAPACITY) {
        result.status = input.reserved != 0u
            ? GE_STATUS_RESERVED_BITS : GE_STATUS_INVALID_ARGUMENT;
        return result;
    }

    uint64_t aggregate = ge_title_raster_hash_init();
    for (uint32_t index = 0u; index < input.state_count; index++) {
        const GETitleRasterSourceStateV5 source = input.states[index];
        if (source.reserved != 0u) {
            result.status = GE_STATUS_RESERVED_BITS;
            result.state_count = index;
            return result;
        }
        if (!ge_title_raster_source_known(source.source_model_mask)) {
            result.status = GE_STATUS_INVALID_ARGUMENT;
            result.state_count = index;
            return result;
        }
        if (!ge_title_raster_tuple_known(source.raw_other_mode_h,
                                         source.raw_other_mode_l,
                                         source.raw_combine_w0,
                                         source.raw_combine_w1)) {
            result.status = GE_STATUS_UNSUPPORTED_COMMAND;
            result.state_count = index;
            return result;
        }
        const uint32_t source_mask = ge_title_raster_tuple_source_mask(
            source.raw_other_mode_h,
            source.raw_other_mode_l,
            source.raw_combine_w0,
            source.raw_combine_w1);
        if ((source.source_model_mask & ~source_mask) != 0u) {
            result.status = GE_STATUS_INVALID_ARGUMENT;
            result.state_count = index;
            return result;
        }
        result.states[index] = ge_title_raster_state(source);
        aggregate = ge_title_raster_hash_u32(aggregate, source.source_model_mask);
        aggregate = ge_title_raster_hash_u32(aggregate, source.raw_other_mode_h);
        aggregate = ge_title_raster_hash_u32(aggregate, source.raw_other_mode_l);
        aggregate = ge_title_raster_hash_u32(aggregate, source.raw_combine_w0);
        aggregate = ge_title_raster_hash_u32(aggregate, source.raw_combine_w1);
        aggregate = ge_title_raster_hash_u64(aggregate, result.states[index].state_hash);
    }
    result.state_count = input.state_count;
    result.aggregate_hash = aggregate;
    return result;
}

GETitleRasterResultV5 ge_title_lower_source_raster_v5(void)
{
    return ge_title_lower_raster_v5(ge_title_raster_source_vector_v5());
}
