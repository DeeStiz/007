#include "ge_classic_raster_v5.h"

#include <string.h>

enum {
    GE_RASTER_AA_EN = 0x8u,
    GE_RASTER_Z_CMP = 0x10u,
    GE_RASTER_Z_UPD = 0x20u,
    GE_RASTER_IM_RD = 0x40u,
    GE_RASTER_CLR_ON_CVG = 0x80u,
    GE_RASTER_CVG_DST_SHIFT = 8u,
    GE_RASTER_ZMODE_SHIFT = 10u,
    GE_RASTER_CVG_X_ALPHA = 0x1000u,
    GE_RASTER_ALPHA_CVG_SEL = 0x2000u,
    GE_RASTER_FORCE_BL = 0x4000u,
    GE_RASTER_BLEND_FOG = 3u,
};

static uint64_t ge_raster_hash_byte(uint64_t hash, uint8_t value)
{
    return (hash ^ (uint64_t)value) * UINT64_C(1099511628211);
}

static uint64_t ge_raster_hash_u32(uint64_t hash, uint32_t value)
{
    hash = ge_raster_hash_byte(hash, (uint8_t)(value & 0xffu));
    hash = ge_raster_hash_byte(hash, (uint8_t)((value >> 8) & 0xffu));
    hash = ge_raster_hash_byte(hash, (uint8_t)((value >> 16) & 0xffu));
    return ge_raster_hash_byte(hash, (uint8_t)(value >> 24));
}

static uint64_t ge_raster_hash_u64(uint64_t hash, uint64_t value)
{
    hash = ge_raster_hash_u32(hash, (uint32_t)value);
    return ge_raster_hash_u32(hash, (uint32_t)(value >> 32));
}

static uint64_t ge_raster_hash_init(void)
{
    return UINT64_C(1469598103934665603);
}

static uint32_t ge_raster_pack_blender(uint32_t raw_mode, uint32_t shift)
{
    return ((raw_mode >> shift) & 3u) |
           (((raw_mode >> (shift - 4u)) & 3u) << 2) |
           (((raw_mode >> (shift - 8u)) & 3u) << 4) |
           (((raw_mode >> (shift - 12u)) & 3u) << 6);
}

static int ge_raster_mode_supported(uint32_t raw_mode)
{
    return raw_mode == GE_CLASSIC_RASTER_MODE_OPAQUE ||
           raw_mode == GE_CLASSIC_RASTER_MODE_AUTHORED;
}

static GEClassicRasterStateV5 ge_raster_state(uint32_t raw_mode,
                                              uint32_t raw_other_mode_l)
{
    GEClassicRasterStateV5 state;
    memset(&state, 0, sizeof(state));
    state.header.abi_version = GE_NATIVE_ABI_VERSION;
    state.header.struct_size = (uint32_t)sizeof(state);
    state.raw_render_mode = raw_mode;
    state.raw_other_mode_l = raw_other_mode_l;
    state.aa_enable = (raw_mode & GE_RASTER_AA_EN) != 0u;
    state.z_compare = (raw_mode & GE_RASTER_Z_CMP) != 0u;
    state.z_update = (raw_mode & GE_RASTER_Z_UPD) != 0u;
    state.image_read = (raw_mode & GE_RASTER_IM_RD) != 0u;
    state.clear_on_coverage = (raw_mode & GE_RASTER_CLR_ON_CVG) != 0u;
    state.coverage_destination = (raw_mode >> GE_RASTER_CVG_DST_SHIFT) & 3u;
    state.z_mode = (raw_mode >> GE_RASTER_ZMODE_SHIFT) & 3u;
    state.coverage_x_alpha = (raw_mode & GE_RASTER_CVG_X_ALPHA) != 0u;
    state.alpha_coverage_select = (raw_mode & GE_RASTER_ALPHA_CVG_SEL) != 0u;
    state.force_blend = (raw_mode & GE_RASTER_FORCE_BL) != 0u;
    state.alpha_compare = raw_other_mode_l & 3u;
    state.alpha_policy = state.alpha_compare == GE_CLASSIC_RASTER_ALPHA_NONE
        ? GE_CLASSIC_RASTER_POLICY_NATIVE
        : GE_CLASSIC_RASTER_POLICY_EXPLICIT_APPROXIMATION;
    state.alpha_threshold_q8 = state.alpha_compare == GE_CLASSIC_RASTER_ALPHA_THRESHOLD
        ? 128u
        : 0u;
    state.depth_compare_policy = state.z_compare
        ? GE_CLASSIC_RASTER_DEPTH_LESS_EQUAL
        : GE_CLASSIC_RASTER_DEPTH_ALWAYS;
    state.depth_write = state.z_update;
    state.blend_cycle0 = ge_raster_pack_blender(raw_mode, 30u);
    state.blend_cycle1 = ge_raster_pack_blender(raw_mode, 28u);
    /* Type-4 source setup emits FOG color (0,0,0,38). */
    state.fog_color_rgba8 = UINT32_C(0x00000026);
    state.fog_alpha_q8 = 38u;
    state.fog_enable = (((state.blend_cycle0 >> 0) & 3u) == GE_RASTER_BLEND_FOG) ||
                       (((state.blend_cycle1 >> 0) & 3u) == GE_RASTER_BLEND_FOG);
    state.state_hash = ge_raster_hash_init();
    state.state_hash = ge_raster_hash_u32(state.state_hash, state.raw_render_mode);
    state.state_hash = ge_raster_hash_u32(state.state_hash, state.raw_other_mode_l);
    state.state_hash = ge_raster_hash_u32(state.state_hash, state.aa_enable);
    state.state_hash = ge_raster_hash_u32(state.state_hash, state.z_compare);
    state.state_hash = ge_raster_hash_u32(state.state_hash, state.z_update);
    state.state_hash = ge_raster_hash_u32(state.state_hash, state.image_read);
    state.state_hash = ge_raster_hash_u32(state.state_hash, state.clear_on_coverage);
    state.state_hash = ge_raster_hash_u32(state.state_hash, state.coverage_destination);
    state.state_hash = ge_raster_hash_u32(state.state_hash, state.z_mode);
    state.state_hash = ge_raster_hash_u32(state.state_hash, state.coverage_x_alpha);
    state.state_hash = ge_raster_hash_u32(state.state_hash, state.alpha_coverage_select);
    state.state_hash = ge_raster_hash_u32(state.state_hash, state.force_blend);
    state.state_hash = ge_raster_hash_u32(state.state_hash, state.alpha_compare);
    state.state_hash = ge_raster_hash_u32(state.state_hash, state.alpha_policy);
    state.state_hash = ge_raster_hash_u32(state.state_hash, state.alpha_threshold_q8);
    state.state_hash = ge_raster_hash_u32(state.state_hash, state.depth_compare_policy);
    state.state_hash = ge_raster_hash_u32(state.state_hash, state.depth_write);
    state.state_hash = ge_raster_hash_u32(state.state_hash, state.fog_enable);
    state.state_hash = ge_raster_hash_u32(state.state_hash, state.fog_color_rgba8);
    state.state_hash = ge_raster_hash_u32(state.state_hash, state.fog_alpha_q8);
    state.state_hash = ge_raster_hash_u32(state.state_hash, state.blend_cycle0);
    state.state_hash = ge_raster_hash_u32(state.state_hash, state.blend_cycle1);
    return state;
}

GEClassicRasterResultV5 ge_classic_lower_raster_v5(GEClassicRasterInputV5 input)
{
    GEClassicRasterResultV5 result;
    memset(&result, 0, sizeof(result));
    result.header.abi_version = GE_NATIVE_ABI_VERSION;
    result.header.struct_size = (uint32_t)sizeof(result);
    result.status = GE_STATUS_OK;
    if (input.header.abi_version != GE_CLASSIC_RASTER_ABI_VERSION) {
        result.status = GE_STATUS_INVALID_VERSION;
        return result;
    }
    if (input.header.struct_size != sizeof(input)) {
        result.status = GE_STATUS_INVALID_SIZE;
        return result;
    }
    if (input.reserved != 0u || input.mode_count == 0u ||
        input.mode_count > GE_CLASSIC_RASTER_MODE_CAPACITY) {
        result.status = input.reserved != 0u ? GE_STATUS_RESERVED_BITS : GE_STATUS_INVALID_ARGUMENT;
        return result;
    }
    if (input.raw_other_mode_l & ~UINT32_C(3)) {
        result.status = GE_STATUS_MALFORMED_STREAM;
        return result;
    }
    uint64_t aggregate = ge_raster_hash_init();
    for (uint32_t index = 0; index < input.mode_count; index++) {
        if (!ge_raster_mode_supported(input.raw_modes[index])) {
            result.status = GE_STATUS_UNSUPPORTED_COMMAND;
            result.state_count = index;
            return result;
        }
        result.states[index] = ge_raster_state(input.raw_modes[index], input.raw_other_mode_l);
        aggregate = ge_raster_hash_u32(aggregate, input.raw_modes[index]);
        aggregate = ge_raster_hash_u64(aggregate, result.states[index].state_hash);
    }
    result.state_count = input.mode_count;
    result.aggregate_hash = aggregate;
    return result;
}

GEClassicRasterResultV5 ge_classic_lower_ammo_crate_raster_v5(void)
{
    GEClassicRasterInputV5 input;
    memset(&input, 0, sizeof(input));
    input.header.abi_version = GE_NATIVE_ABI_VERSION;
    input.header.struct_size = (uint32_t)sizeof(input);
    input.mode_count = GE_CLASSIC_RASTER_MODE_CAPACITY;
    input.raw_modes[0] = GE_CLASSIC_RASTER_MODE_OPAQUE;
    input.raw_modes[1] = GE_CLASSIC_RASTER_MODE_AUTHORED;
    input.raw_other_mode_l = 0u;
    return ge_classic_lower_raster_v5(input);
}
