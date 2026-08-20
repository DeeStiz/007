#include "ge_classic_combiner.h"

#include <stddef.h>
#include <string.h>

enum {
    GE_COMBINER_OP_MTX = 0x01,
    GE_COMBINER_OP_VTX = 0x04,
    GE_COMBINER_OP_TRI4 = 0xb1,
    GE_COMBINER_OP_ENDDL = 0xb8,
    GE_COMBINER_OP_SETOTHERMODE_L = 0xb9,
    GE_COMBINER_OP_SETOTHERMODE_H = 0xba,
    GE_COMBINER_OP_TEXTURE = 0xbb,
    GE_COMBINER_OP_SETTEX = 0xc0,
    GE_COMBINER_OP_SETCOMBINE = 0xfc,
    GE_COMBINER_OP_PIPE_SYNC = 0xe7,
    GE_COMBINER_OP_SETOTHERMODE_L_ALT = 0xe2,
    GE_COMBINER_OP_SETOTHERMODE_H_ALT = 0xe3,
    GE_COMBINER_PROP_SIZE = 1488u,
    GE_COMBINER_PROP_COMMAND_OFFSET = 0x518u,
    GE_COMBINER_PROP_COMMAND_COUNT = 22u,
    GE_COMBINER_SETUP_COMMAND_COUNT = 3u,
    GE_COMBINER_SETUP_COMMANDS = 3u,
};

enum {
    GE_COMBINER_MATERIAL_SOURCE_SETUP = 1u << 0,
    GE_COMBINER_MATERIAL_TEXEL0_SHADE = 1u << 1,
    GE_COMBINER_MATERIAL_TEXTURED = 1u << 2,
    GE_COMBINER_MATERIAL_OPAQUE_PRIMARY = 1u << 3,
    GE_COMBINER_MATERIAL_DEFERRED_DEPTH = 1u << 4,
    GE_COMBINER_MATERIAL_DEFERRED_FOG = 1u << 5,
    GE_COMBINER_MATERIAL_DEFERRED_ALPHA = 1u << 6,
    GE_COMBINER_MATERIAL_DEFERRED_COVERAGE = 1u << 7,
};

static const GEClassicCombinerCommandV4 ge_combiner_setup_commands[GE_COMBINER_SETUP_COMMAND_COUNT] = {
    { UINT32_C(0xba001402), UINT32_C(0x00100000) },
    { UINT32_C(0xfc26a004), UINT32_C(0x1f1093ff) },
    { UINT32_C(0xb900031d), UINT32_C(0xc4112078) },
};

static const GEClassicCombinerCommandV4 ge_combiner_tri4_commands[5] = {
    { UINT32_C(0xb1007632), UINT32_C(0x64542010) },
    { UINT32_C(0xb100feba), UINT32_C(0xecdca898) },
    { UINT32_C(0xb1007632), UINT32_C(0x64542010) },
    { UINT32_C(0xb100feba), UINT32_C(0xecdca898) },
    { UINT32_C(0xb1007632), UINT32_C(0x64542010) },
};

static uint32_t ge_combiner_be32(const uint8_t *bytes)
{
    return ((uint32_t)bytes[0] << 24) |
           ((uint32_t)bytes[1] << 16) |
           ((uint32_t)bytes[2] << 8) |
           (uint32_t)bytes[3];
}

static uint64_t ge_combiner_hash_byte(uint64_t hash, uint8_t value)
{
    return (hash ^ (uint64_t)value) * UINT64_C(1099511628211);
}

static uint64_t ge_combiner_hash_u32(uint64_t hash, uint32_t value)
{
    hash = ge_combiner_hash_byte(hash, (uint8_t)(value & 0xffu));
    hash = ge_combiner_hash_byte(hash, (uint8_t)((value >> 8) & 0xffu));
    hash = ge_combiner_hash_byte(hash, (uint8_t)((value >> 16) & 0xffu));
    return ge_combiner_hash_byte(hash, (uint8_t)(value >> 24));
}

static uint64_t ge_combiner_hash_u64(uint64_t hash, uint64_t value)
{
    hash = ge_combiner_hash_u32(hash, (uint32_t)value);
    return ge_combiner_hash_u32(hash, (uint32_t)(value >> 32));
}

static uint64_t ge_combiner_hash_init(void)
{
    return UINT64_C(1469598103934665603);
}

static uint64_t ge_combiner_hash_cycle(uint64_t hash,
                                       const GEClassicCombinerCycleV4 *cycle)
{
    hash = ge_combiner_hash_u32(hash, cycle->rgb_a);
    hash = ge_combiner_hash_u32(hash, cycle->rgb_b);
    hash = ge_combiner_hash_u32(hash, cycle->rgb_c);
    hash = ge_combiner_hash_u32(hash, cycle->rgb_d);
    hash = ge_combiner_hash_u32(hash, cycle->alpha_a);
    hash = ge_combiner_hash_u32(hash, cycle->alpha_b);
    hash = ge_combiner_hash_u32(hash, cycle->alpha_c);
    return ge_combiner_hash_u32(hash, cycle->alpha_d);
}

static uint64_t ge_combiner_hash_combiner(uint64_t hash,
                                          const GEClassicCombinerStateV4 *state)
{
    hash = ge_combiner_hash_u32(hash, state->raw_w0);
    hash = ge_combiner_hash_u32(hash, state->raw_w1);
    hash = ge_combiner_hash_cycle(hash, &state->cycles[0]);
    hash = ge_combiner_hash_cycle(hash, &state->cycles[1]);
    return ge_combiner_hash_u32(hash, state->selector_flags);
}

static uint64_t ge_combiner_hash_other_mode(uint64_t hash,
                                            const GEClassicOtherModeV4 *mode)
{
    hash = ge_combiner_hash_u32(hash, mode->raw_h);
    hash = ge_combiner_hash_u32(hash, mode->raw_l);
    hash = ge_combiner_hash_u32(hash, mode->pipeline_mode);
    hash = ge_combiner_hash_u32(hash, mode->cycle_type);
    hash = ge_combiner_hash_u32(hash, mode->texture_perspective);
    hash = ge_combiner_hash_u32(hash, mode->texture_detail);
    hash = ge_combiner_hash_u32(hash, mode->texture_lod);
    hash = ge_combiner_hash_u32(hash, mode->texture_lut);
    hash = ge_combiner_hash_u32(hash, mode->texture_filter);
    hash = ge_combiner_hash_u32(hash, mode->texture_convert);
    hash = ge_combiner_hash_u32(hash, mode->combine_key);
    hash = ge_combiner_hash_u32(hash, mode->color_dither);
    hash = ge_combiner_hash_u32(hash, mode->alpha_dither);
    hash = ge_combiner_hash_u32(hash, mode->alpha_compare);
    hash = ge_combiner_hash_u32(hash, mode->depth_source);
    return ge_combiner_hash_u32(hash, mode->render_mode);
}

static uint64_t ge_combiner_hash_blender(uint64_t hash,
                                         const GEClassicBlenderCycleV4 *cycle)
{
    hash = ge_combiner_hash_u32(hash, cycle->m1a);
    hash = ge_combiner_hash_u32(hash, cycle->m1b);
    hash = ge_combiner_hash_u32(hash, cycle->m2a);
    return ge_combiner_hash_u32(hash, cycle->m2b);
}

static uint64_t ge_combiner_hash_render_mode(uint64_t hash,
                                             const GEClassicRenderModeV4 *mode)
{
    hash = ge_combiner_hash_u32(hash, mode->raw_mode);
    hash = ge_combiner_hash_u32(hash, mode->aa_enable);
    hash = ge_combiner_hash_u32(hash, mode->z_compare);
    hash = ge_combiner_hash_u32(hash, mode->z_update);
    hash = ge_combiner_hash_u32(hash, mode->image_read);
    hash = ge_combiner_hash_u32(hash, mode->clear_on_coverage);
    hash = ge_combiner_hash_u32(hash, mode->coverage_destination);
    hash = ge_combiner_hash_u32(hash, mode->z_mode);
    hash = ge_combiner_hash_u32(hash, mode->coverage_x_alpha);
    hash = ge_combiner_hash_u32(hash, mode->alpha_coverage_select);
    hash = ge_combiner_hash_u32(hash, mode->force_blend);
    hash = ge_combiner_hash_blender(hash, &mode->blender[0]);
    hash = ge_combiner_hash_blender(hash, &mode->blender[1]);
    return ge_combiner_hash_u32(hash, mode->deferred_flags);
}

static int ge_combiner_is_h_opcode(uint32_t opcode)
{
    return opcode == GE_COMBINER_OP_SETOTHERMODE_H ||
           opcode == GE_COMBINER_OP_SETOTHERMODE_H_ALT;
}

static int ge_combiner_is_l_opcode(uint32_t opcode)
{
    return opcode == GE_COMBINER_OP_SETOTHERMODE_L ||
           opcode == GE_COMBINER_OP_SETOTHERMODE_L_ALT;
}

static int ge_combiner_is_known_texture(uint32_t texture_id)
{
    return texture_id == GE_CLASSIC_COMBINER_TEXTURE_AMMOCRATE1 ||
           texture_id == GE_CLASSIC_COMBINER_TEXTURE_AMMOTEXT765 ||
           texture_id == GE_CLASSIC_COMBINER_TEXTURE_CRATEROPE;
}

static int ge_combiner_valid_range(uint32_t shift, uint32_t length)
{
    return length != 0u && length <= 32u && shift <= 31u &&
           length <= 32u - shift;
}

static uint32_t ge_combiner_range_mask(uint32_t shift, uint32_t length)
{
    if (length == 32u) {
        return UINT32_MAX;
    }
    return ((UINT32_C(1) << length) - UINT32_C(1)) << shift;
}

static void ge_combiner_decode_render_mode(GEClassicRenderModeV4 *render_mode,
                                           uint32_t raw_mode)
{
    memset(render_mode, 0, sizeof(*render_mode));
    render_mode->raw_mode = raw_mode & UINT32_C(0xfffffff8);
    render_mode->aa_enable = (raw_mode >> 3) & 1u;
    render_mode->z_compare = (raw_mode >> 4) & 1u;
    render_mode->z_update = (raw_mode >> 5) & 1u;
    render_mode->image_read = (raw_mode >> 6) & 1u;
    render_mode->clear_on_coverage = (raw_mode >> 7) & 1u;
    render_mode->coverage_destination = (raw_mode >> 8) & 3u;
    render_mode->z_mode = (raw_mode >> 10) & 3u;
    render_mode->coverage_x_alpha = (raw_mode >> 12) & 1u;
    render_mode->alpha_coverage_select = (raw_mode >> 13) & 1u;
    render_mode->force_blend = (raw_mode >> 14) & 1u;

    render_mode->blender[0].m1a = (raw_mode >> 30) & 3u;
    render_mode->blender[0].m1b = (raw_mode >> 26) & 3u;
    render_mode->blender[0].m2a = (raw_mode >> 22) & 3u;
    render_mode->blender[0].m2b = (raw_mode >> 18) & 3u;
    render_mode->blender[1].m1a = (raw_mode >> 28) & 3u;
    render_mode->blender[1].m1b = (raw_mode >> 24) & 3u;
    render_mode->blender[1].m2a = (raw_mode >> 20) & 3u;
    render_mode->blender[1].m2b = (raw_mode >> 16) & 3u;
    render_mode->deferred_flags = GE_CLASSIC_COMBINER_DEFERRED_DEPTH |
                                  GE_CLASSIC_COMBINER_DEFERRED_FOG |
                                  GE_CLASSIC_COMBINER_DEFERRED_ALPHA |
                                  GE_CLASSIC_COMBINER_DEFERRED_COVERAGE;
}

static void ge_combiner_refresh_other_mode(GEClassicOtherModeV4 *mode)
{
    mode->pipeline_mode = (mode->raw_h >> 23) & 1u;
    mode->cycle_type = (mode->raw_h >> 20) & 3u;
    mode->texture_perspective = (mode->raw_h >> 19) & 1u;
    mode->texture_detail = (mode->raw_h >> 17) & 3u;
    mode->texture_lod = (mode->raw_h >> 16) & 1u;
    mode->texture_lut = (mode->raw_h >> 14) & 3u;
    mode->texture_filter = (mode->raw_h >> 12) & 3u;
    mode->texture_convert = (mode->raw_h >> 9) & 7u;
    mode->combine_key = (mode->raw_h >> 8) & 1u;
    mode->color_dither = (mode->raw_h >> 6) & 3u;
    mode->alpha_dither = (mode->raw_h >> 4) & 3u;
    mode->alpha_compare = mode->raw_l & 3u;
    mode->depth_source = (mode->raw_l >> 2) & 1u;
    mode->render_mode = mode->raw_l & UINT32_C(0xfffffff8);
}

static GEStatusV1 ge_combiner_apply_other_mode(GEClassicOtherModeV4 *mode,
                                               GEClassicRenderModeV4 *render_mode,
                                               GEClassicCombinerCommandV4 command)
{
    uint32_t opcode = command.w0 >> 24;
    uint32_t shift = (command.w0 >> 8) & 0xffu;
    uint32_t length = command.w0 & 0xffu;
    if ((!ge_combiner_is_h_opcode(opcode) && !ge_combiner_is_l_opcode(opcode)) ||
        !ge_combiner_valid_range(shift, length)) {
        return GE_STATUS_MALFORMED_STREAM;
    }

    uint32_t mask = ge_combiner_range_mask(shift, length);
    if ((command.w1 & ~mask) != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    uint32_t *register_value = ge_combiner_is_h_opcode(opcode)
        ? &mode->raw_h : &mode->raw_l;
    *register_value = (*register_value & ~mask) | (command.w1 & mask);
    ge_combiner_refresh_other_mode(mode);
    ge_combiner_decode_render_mode(render_mode, mode->render_mode);
    return GE_STATUS_OK;
}

static int ge_combiner_selector_supported_rgb(uint32_t selector)
{
    /* The bounded source path needs only classic texel/shade/LOD/combined
       selectors and the canonical zero value. */
    return selector == 0u || selector == 1u || selector == 2u ||
           selector == 4u || selector == 7u || selector == 13u ||
           selector == 15u ||
           selector == 31u;
}

static int ge_combiner_selector_supported_alpha(uint32_t selector)
{
    return selector == 0u || selector == 1u || selector == 2u ||
           selector == 4u || selector == 7u;
}

static GEStatusV1 ge_combiner_decode_combiner(GEClassicCombinerStateV4 *state,
                                              GEClassicCombinerCommandV4 command)
{
    if ((command.w0 >> 24) != GE_COMBINER_OP_SETCOMBINE) {
        return GE_STATUS_MALFORMED_STREAM;
    }

    memset(state, 0, sizeof(*state));
    state->raw_w0 = command.w0;
    state->raw_w1 = command.w1;

    GEClassicCombinerCycleV4 *cycle0 = &state->cycles[0];
    GEClassicCombinerCycleV4 *cycle1 = &state->cycles[1];
    cycle0->rgb_a = (command.w0 >> 20) & 0xfu;
    cycle0->rgb_c = (command.w0 >> 15) & 0x1fu;
    cycle0->alpha_a = (command.w0 >> 12) & 0x7u;
    cycle0->alpha_c = (command.w0 >> 9) & 0x7u;
    cycle1->rgb_a = (command.w0 >> 5) & 0xfu;
    cycle1->rgb_c = command.w0 & 0x1fu;

    cycle0->rgb_b = (command.w1 >> 28) & 0xfu;
    cycle0->rgb_d = (command.w1 >> 15) & 0x7u;
    cycle0->alpha_b = (command.w1 >> 12) & 0x7u;
    cycle0->alpha_d = (command.w1 >> 9) & 0x7u;
    cycle1->rgb_b = (command.w1 >> 24) & 0xfu;
    cycle1->alpha_a = (command.w1 >> 21) & 0x7u;
    cycle1->alpha_c = (command.w1 >> 18) & 0x7u;
    cycle1->rgb_d = (command.w1 >> 6) & 0x7u;
    cycle1->alpha_b = (command.w1 >> 3) & 0x7u;
    cycle1->alpha_d = command.w1 & 0x7u;

    for (uint32_t index = 0; index < GE_CLASSIC_COMBINER_CYCLE_CAPACITY; index++) {
        const GEClassicCombinerCycleV4 *cycle = &state->cycles[index];
        if (!ge_combiner_selector_supported_rgb(cycle->rgb_a) ||
            !ge_combiner_selector_supported_rgb(cycle->rgb_b) ||
            !ge_combiner_selector_supported_rgb(cycle->rgb_c) ||
            !ge_combiner_selector_supported_rgb(cycle->rgb_d) ||
            !ge_combiner_selector_supported_alpha(cycle->alpha_a) ||
            !ge_combiner_selector_supported_alpha(cycle->alpha_b) ||
            !ge_combiner_selector_supported_alpha(cycle->alpha_c) ||
            !ge_combiner_selector_supported_alpha(cycle->alpha_d)) {
            return GE_STATUS_UNSUPPORTED_COMMAND;
        }
    }

    /* The source setup is TRILERP/MODULATEIA2.  It is the only two-cycle
       material combination admitted by this bounded sidecar. */
    if (command.w0 != UINT32_C(0xfc26a004) ||
        command.w1 != UINT32_C(0x1f1093ff)) {
        return GE_STATUS_UNSUPPORTED_COMMAND;
    }
    state->selector_flags = GE_CLASSIC_COMBINER_FLAG_TEXEL0_SHADE;
    return GE_STATUS_OK;
}

static void ge_combiner_init_result(GEClassicCombinerLoweringResultV4 *result)
{
    memset(result, 0, sizeof(*result));
    /* Keep the public envelope consistent with the frozen V1/V2/V3 records;
       the sidecar version is carried by its packet/input constants. */
    result->header.abi_version = GE_NATIVE_ABI_VERSION;
    result->header.struct_size = (uint32_t)sizeof(*result);
    result->status = GE_STATUS_OK;
}

static void ge_combiner_set_error(GEClassicCombinerLoweringResultV4 *result,
                                  GEStatusV1 status,
                                  uint32_t opcode,
                                  uint32_t offset)
{
    result->status = status;
    result->error_opcode = opcode;
    result->error_offset = offset;
}

static GEStatusV1 ge_combiner_validate_input(
    const GEClassicCombinerInputV4 *input)
{
    if (input->header.abi_version != GE_CLASSIC_COMBINER_REPLAY_ABI_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    if (input->header.struct_size != sizeof(*input)) {
        return GE_STATUS_INVALID_SIZE;
    }
    if (input->reserved0 != 0u || input->reserved1 != 0u) {
        return GE_STATUS_RESERVED_BITS;
    }
    if (input->setup_command_count != GE_COMBINER_SETUP_COMMAND_COUNT ||
        input->command_count == 0u ||
        input->command_count > GE_CLASSIC_COMBINER_COMMAND_CAPACITY) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    for (uint32_t index = 0; index < input->setup_command_count; index++) {
        if (input->setup[index].w0 != ge_combiner_setup_commands[index].w0 ||
            input->setup[index].w1 != ge_combiner_setup_commands[index].w1) {
            return GE_STATUS_ASSET_MISMATCH;
        }
    }
    return GE_STATUS_OK;
}

static uint32_t ge_combiner_tri4_count(GEClassicCombinerCommandV4 command)
{
    uint32_t z[4] = {
        command.w0 & 0xfu,
        (command.w0 >> 4) & 0xfu,
        (command.w0 >> 8) & 0xfu,
        (command.w0 >> 12) & 0xfu,
    };
    uint32_t x[4] = {
        command.w1 & 0xfu,
        (command.w1 >> 8) & 0xfu,
        (command.w1 >> 16) & 0xfu,
        (command.w1 >> 24) & 0xfu,
    };
    uint32_t y[4] = {
        (command.w1 >> 4) & 0xfu,
        (command.w1 >> 12) & 0xfu,
        (command.w1 >> 20) & 0xfu,
        (command.w1 >> 28) & 0xfu,
    };
    uint32_t count = 0u;
    for (uint32_t index = 0; index < 4u; index++) {
        if (!(x[index] == 0u && y[index] == 0u && z[index] == 0u)) {
            count++;
        }
    }
    return count;
}

static int ge_combiner_same_state(const GEClassicCombinerDrawKeyV4 *draw,
                                  const GEClassicCombinerStateV4 *combiner,
                                  const GEClassicOtherModeV4 *other_mode,
                                  const GEClassicRenderModeV4 *render_mode,
                                  uint32_t texture_id)
{
    return draw->texture_id == texture_id &&
           memcmp(&draw->combiner, combiner, sizeof(*combiner)) == 0 &&
           memcmp(&draw->other_mode, other_mode, sizeof(*other_mode)) == 0 &&
           memcmp(&draw->render_mode, render_mode, sizeof(*render_mode)) == 0;
}

static uint64_t ge_combiner_hash_draw(const GEClassicCombinerDrawKeyV4 *draw)
{
    uint64_t hash = ge_combiner_hash_init();
    hash = ge_combiner_hash_u32(hash, draw->source_command_offset);
    hash = ge_combiner_hash_u32(hash, draw->texture_id);
    hash = ge_combiner_hash_u32(hash, draw->triangle_group_count);
    hash = ge_combiner_hash_u32(hash, draw->material_flags);
    hash = ge_combiner_hash_combiner(hash, &draw->combiner);
    hash = ge_combiner_hash_other_mode(hash, &draw->other_mode);
    return ge_combiner_hash_render_mode(hash, &draw->render_mode);
}

static GEStatusV1 ge_combiner_validate_canonical_texture_command(
    uint32_t index,
    GEClassicCombinerCommandV4 command,
    uint32_t *texture_id)
{
    static const GEClassicCombinerCommandV4 expected[] = {
        { UINT32_C(0xc0080002), UINT32_C(0x00000021) },
        { UINT32_C(0xc0580002), UINT32_C(0x00000027) },
        { UINT32_C(0xc0580002), UINT32_C(0x00000025) },
    };
    uint32_t id = command.w1 & 0xfffu;
    if (!ge_combiner_is_known_texture(id)) {
        return GE_STATUS_TEXTURE_FORMAT;
    }
    if (index == 3u) {
        if (memcmp(&command, &expected[0], sizeof(command)) != 0) {
            return GE_STATUS_ASSET_MISMATCH;
        }
    } else if (index == 15u) {
        if (memcmp(&command, &expected[1], sizeof(command)) != 0) {
            return GE_STATUS_ASSET_MISMATCH;
        }
    } else if (index == 18u) {
        if (memcmp(&command, &expected[2], sizeof(command)) != 0) {
            return GE_STATUS_ASSET_MISMATCH;
        }
    } else {
        return GE_STATUS_MALFORMED_STREAM;
    }
    *texture_id = id;
    return GE_STATUS_OK;
}

GEClassicCombinerInputV4 ge_classic_ammo_crate_combiner_input_v4(
    GEClassicAssetBlobV2 blob)
{
    GEClassicCombinerInputV4 input;
    memset(&input, 0, sizeof(input));
    input.header.abi_version = GE_CLASSIC_COMBINER_REPLAY_ABI_VERSION;
    input.header.struct_size = (uint32_t)sizeof(input);

    if (blob.header.abi_version != GE_NATIVE_ABI_VERSION) {
        return input;
    }
    if (blob.header.struct_size != sizeof(blob) || blob.reserved != 0u ||
        blob.byte_count != GE_COMBINER_PROP_SIZE ||
        blob.byte_count > GE_CLASSIC_ASSET_BLOB_CAPACITY) {
        return input;
    }

    input.setup_command_count = GE_COMBINER_SETUP_COMMAND_COUNT;
    memcpy(input.setup, ge_combiner_setup_commands,
           sizeof(ge_combiner_setup_commands));
    input.command_count = GE_COMBINER_PROP_COMMAND_COUNT;
    for (uint32_t index = 0; index < GE_COMBINER_PROP_COMMAND_COUNT; index++) {
        uint32_t offset = GE_COMBINER_PROP_COMMAND_OFFSET + index * 8u;
        input.commands[index].w0 = ge_combiner_be32(&blob.bytes[offset]);
        input.commands[index].w1 = ge_combiner_be32(&blob.bytes[offset + 4u]);
    }
    return input;
}

GEClassicCombinerLoweringResultV4 ge_classic_lower_combiner_v4(
    GEClassicCombinerInputV4 input)
{
    GEClassicCombinerLoweringResultV4 result;
    ge_combiner_init_result(&result);

    GEStatusV1 status = ge_combiner_validate_input(&input);
    if (status != GE_STATUS_OK) {
        ge_combiner_set_error(&result, status, 0u, 0u);
        return result;
    }

    GEClassicCombinerStateV4 combiner;
    GEClassicOtherModeV4 other_mode;
    GEClassicRenderModeV4 render_mode;
    memset(&combiner, 0, sizeof(combiner));
    memset(&other_mode, 0, sizeof(other_mode));
    memset(&render_mode, 0, sizeof(render_mode));

    result.source_setup.header.abi_version = GE_NATIVE_ABI_VERSION;
    result.source_setup.header.struct_size = (uint32_t)sizeof(result.source_setup);
    result.source_setup.command_count = input.setup_command_count;
    memcpy(result.source_setup.commands, input.setup,
           sizeof(result.source_setup.commands));

    uint64_t setup_hash = ge_combiner_hash_init();
    uint64_t event_hash = ge_combiner_hash_init();
    for (uint32_t index = 0; index < input.setup_command_count; index++) {
        GEClassicCombinerCommandV4 command = input.setup[index];
        uint32_t opcode = command.w0 >> 24;
        uint32_t offset = index * (uint32_t)sizeof(command);
        setup_hash = ge_combiner_hash_u32(setup_hash, command.w0);
        setup_hash = ge_combiner_hash_u32(setup_hash, command.w1);
        event_hash = ge_combiner_hash_u32(event_hash, UINT32_C(0x53545550));
        event_hash = ge_combiner_hash_u32(event_hash, command.w0);
        event_hash = ge_combiner_hash_u32(event_hash, command.w1);

        if (index == 0u) {
            if (!ge_combiner_is_h_opcode(opcode)) {
                ge_combiner_set_error(&result, GE_STATUS_MALFORMED_STREAM,
                                      opcode, offset);
                return result;
            }
            status = ge_combiner_apply_other_mode(&other_mode, &render_mode,
                                                  command);
        } else if (index == 1u) {
            status = ge_combiner_decode_combiner(&combiner, command);
        } else if (index == 2u) {
            if (!ge_combiner_is_l_opcode(opcode)) {
                ge_combiner_set_error(&result, GE_STATUS_MALFORMED_STREAM,
                                      opcode, offset);
                return result;
            }
            status = ge_combiner_apply_other_mode(&other_mode, &render_mode,
                                                  command);
        } else {
            status = GE_STATUS_MALFORMED_STREAM;
        }
        if (status != GE_STATUS_OK) {
            ge_combiner_set_error(&result, status, opcode, offset);
            return result;
        }
        result.setup_commands_processed++;
    }

    setup_hash = ge_combiner_hash_combiner(setup_hash, &combiner);
    setup_hash = ge_combiner_hash_other_mode(setup_hash, &other_mode);
    setup_hash = ge_combiner_hash_render_mode(setup_hash, &render_mode);
    result.source_setup.combiner = combiner;
    result.source_setup.other_mode = other_mode;
    result.source_setup.render_mode = render_mode;
    result.source_setup.setup_hash = setup_hash;
    result.setup_hash = setup_hash;

    uint32_t current_texture_id = 0u;
    uint32_t texture_sequence_count = 0u;
    uint32_t draw_pending = 1u;
    uint32_t saw_end = 0u;
    for (uint32_t index = 0; index < input.command_count; index++) {
        GEClassicCombinerCommandV4 command = input.commands[index];
        uint32_t opcode = command.w0 >> 24;
        uint32_t offset = UINT32_C(0x10) + index * (uint32_t)sizeof(command);
        result.commands_processed++;
        event_hash = ge_combiner_hash_u32(event_hash, command.w0);
        event_hash = ge_combiner_hash_u32(event_hash, command.w1);

        if (saw_end != 0u) {
            ge_combiner_set_error(&result, GE_STATUS_MALFORMED_STREAM,
                                  opcode, offset);
            return result;
        }

        switch (opcode) {
        case GE_COMBINER_OP_PIPE_SYNC:
            if ((index != 0u && index != 12u) || command.w1 != 0u) {
                ge_combiner_set_error(&result, GE_STATUS_MALFORMED_STREAM,
                                      opcode, offset);
                return result;
            }
            break;

        case GE_COMBINER_OP_SETOTHERMODE_H:
        case GE_COMBINER_OP_SETOTHERMODE_H_ALT:
            if (index != 1u && index != 4u && index != 5u) {
                ge_combiner_set_error(&result, GE_STATUS_MALFORMED_STREAM,
                                      opcode, offset);
                return result;
            }
            status = ge_combiner_apply_other_mode(&other_mode, &render_mode,
                                                  command);
            if (status != GE_STATUS_OK) {
                ge_combiner_set_error(&result, status, opcode, offset);
                return result;
            }
            draw_pending = 1u;
            event_hash = ge_combiner_hash_u32(event_hash, UINT32_C(0x4f544852));
            break;

        case GE_COMBINER_OP_SETOTHERMODE_L:
        case GE_COMBINER_OP_SETOTHERMODE_L_ALT:
            if (index != 13u) {
                ge_combiner_set_error(&result, GE_STATUS_MALFORMED_STREAM,
                                      opcode, offset);
                return result;
            }
            status = ge_combiner_apply_other_mode(&other_mode, &render_mode,
                                                  command);
            if (status != GE_STATUS_OK) {
                ge_combiner_set_error(&result, status, opcode, offset);
                return result;
            }
            draw_pending = 1u;
            event_hash = ge_combiner_hash_u32(event_hash, UINT32_C(0x4f544852));
            break;

        case GE_COMBINER_OP_SETCOMBINE:
            status = ge_combiner_decode_combiner(&combiner, command);
            if (status != GE_STATUS_OK) {
                ge_combiner_set_error(&result, status, opcode, offset);
                return result;
            }
            draw_pending = 1u;
            event_hash = ge_combiner_hash_u32(event_hash, UINT32_C(0x434f4d42));
            break;

        case GE_COMBINER_OP_TEXTURE:
            if (command.w1 != UINT32_MAX ||
                ((index == 2u) && command.w0 != UINT32_C(0xbb003001)) ||
                ((index == 14u) && command.w0 != UINT32_C(0xbb083001)) ||
                ((index == 17u) && command.w0 != UINT32_C(0xbb082801))) {
                ge_combiner_set_error(&result, GE_STATUS_MALFORMED_STREAM,
                                      opcode, offset);
                return result;
            }
            draw_pending = 1u;
            event_hash = ge_combiner_hash_u32(event_hash, UINT32_C(0x54455854));
            break;

        case GE_COMBINER_OP_SETTEX:
        {
            uint32_t texture_id = 0u;
            status = ge_combiner_validate_canonical_texture_command(index,
                                                                     command,
                                                                     &texture_id);
            if (status != GE_STATUS_OK) {
                ge_combiner_set_error(&result, status, opcode, offset);
                return result;
            }
            if (texture_sequence_count >= 3u ||
                (texture_sequence_count > 0u &&
                 texture_id == (texture_sequence_count == 1u
                                ? GE_CLASSIC_COMBINER_TEXTURE_AMMOCRATE1
                                : GE_CLASSIC_COMBINER_TEXTURE_AMMOTEXT765))) {
                ge_combiner_set_error(&result, GE_STATUS_MALFORMED_STREAM,
                                      opcode, offset);
                return result;
            }
            texture_sequence_count++;
            current_texture_id = texture_id;
            draw_pending = 1u;
            event_hash = ge_combiner_hash_u32(event_hash, UINT32_C(0x53455458));
            event_hash = ge_combiner_hash_u32(event_hash, texture_id);
            break;
        }

        case GE_COMBINER_OP_MTX:
            if (index != 6u || command.w0 != UINT32_C(0x01020040) ||
                command.w1 != UINT32_C(0x03000000)) {
                ge_combiner_set_error(&result, GE_STATUS_MALFORMED_STREAM,
                                      opcode, offset);
                return result;
            }
            draw_pending = 1u;
            break;

        case GE_COMBINER_OP_VTX:
            if ((index == 7u && (command.w0 != UINT32_C(0x04f00100) ||
                                command.w1 != UINT32_C(0x04000000))) ||
                (index == 10u && (command.w0 != UINT32_C(0x04f00100) ||
                                  command.w1 != UINT32_C(0x04000100))) ||
                (index == 19u && (command.w0 != UINT32_C(0x04700080) ||
                                  command.w1 != UINT32_C(0x04000200))) ||
                (index != 7u && index != 10u && index != 19u)) {
                ge_combiner_set_error(&result, GE_STATUS_MALFORMED_STREAM,
                                      opcode, offset);
                return result;
            }
            draw_pending = 1u;
            break;

        case GE_COMBINER_OP_TRI4:
        {
            uint32_t tri4_index;
            if (index == 8u) {
                tri4_index = 0u;
            } else if (index == 9u) {
                tri4_index = 1u;
            } else if (index == 11u) {
                tri4_index = 2u;
            } else if (index == 16u) {
                tri4_index = 3u;
            } else if (index == 20u) {
                tri4_index = 4u;
            } else {
                ge_combiner_set_error(&result, GE_STATUS_MALFORMED_STREAM,
                                      opcode, offset);
                return result;
            }
            if (memcmp(&command, &ge_combiner_tri4_commands[tri4_index],
                       sizeof(command)) != 0) {
                ge_combiner_set_error(&result, GE_STATUS_ASSET_MISMATCH,
                                      opcode, offset);
                return result;
            }
            uint32_t triangle_count = ge_combiner_tri4_count(command);
            if (current_texture_id == 0u || triangle_count == 0u) {
                ge_combiner_set_error(&result, GE_STATUS_MALFORMED_STREAM,
                                      opcode, offset);
                return result;
            }
            if (result.draw_count == 0u || draw_pending != 0u) {
                if (result.draw_count >= GE_CLASSIC_COMBINER_DRAW_CAPACITY) {
                    ge_combiner_set_error(&result, GE_STATUS_REPLAY_BUDGET,
                                          opcode, offset);
                    return result;
                }
                GEClassicCombinerDrawKeyV4 *draw =
                    &result.draws[result.draw_count++];
                memset(draw, 0, sizeof(*draw));
                draw->header.abi_version = GE_NATIVE_ABI_VERSION;
                draw->header.struct_size = (uint32_t)sizeof(*draw);
                draw->packet_version = GE_CLASSIC_COMBINER_PACKET_VERSION;
                draw->source_command_offset = offset;
                draw->texture_id = current_texture_id;
                draw->material_flags = GE_CLASSIC_COMBINER_FLAG_SOURCE_SETUP |
                                       GE_CLASSIC_COMBINER_FLAG_TEXEL0_SHADE |
                                       GE_CLASSIC_COMBINER_FLAG_TEXTURED |
                                       GE_CLASSIC_COMBINER_FLAG_DEFERRED_DEPTH |
                                       GE_CLASSIC_COMBINER_FLAG_DEFERRED_FOG |
                                       GE_CLASSIC_COMBINER_FLAG_DEFERRED_ALPHA |
                                       GE_CLASSIC_COMBINER_FLAG_DEFERRED_COVERAGE;
                draw->combiner = combiner;
                draw->other_mode = other_mode;
                draw->render_mode = render_mode;
                if (render_mode.z_mode == 0u && render_mode.z_compare != 0u &&
                    render_mode.z_update != 0u) {
                    draw->material_flags |= GE_CLASSIC_COMBINER_FLAG_OPAQUE_PRIMARY;
                }
            } else {
                GEClassicCombinerDrawKeyV4 *draw =
                    &result.draws[result.draw_count - 1u];
                if (!ge_combiner_same_state(draw, &combiner, &other_mode,
                                             &render_mode, current_texture_id)) {
                    ge_combiner_set_error(&result, GE_STATUS_INVALID_STATE,
                                          opcode, offset);
                    return result;
                }
            }
            GEClassicCombinerDrawKeyV4 *draw =
                &result.draws[result.draw_count - 1u];
            draw->triangle_group_count += triangle_count;
            draw_pending = 0u;
            event_hash = ge_combiner_hash_u32(event_hash, UINT32_C(0x54524934));
            event_hash = ge_combiner_hash_u32(event_hash, triangle_count);
            break;
        }

        case GE_COMBINER_OP_ENDDL:
            if (index + 1u != input.command_count || command.w1 != 0u) {
                ge_combiner_set_error(&result, GE_STATUS_MALFORMED_STREAM,
                                      opcode, offset);
                return result;
            }
            saw_end = 1u;
            break;

        default:
            ge_combiner_set_error(&result, GE_STATUS_UNSUPPORTED_COMMAND,
                                  opcode, offset);
            return result;
        }
    }

    if (saw_end == 0u || texture_sequence_count != 3u ||
        result.draw_count != GE_CLASSIC_COMBINER_DRAW_CAPACITY ||
        result.draws[0].source_command_offset != UINT32_C(0x50) ||
        result.draws[1].source_command_offset != UINT32_C(0x68) ||
        result.draws[2].source_command_offset != UINT32_C(0x90) ||
        result.draws[3].source_command_offset != UINT32_C(0xb0) ||
        result.draws[0].texture_id != GE_CLASSIC_COMBINER_TEXTURE_AMMOCRATE1 ||
        result.draws[1].texture_id != GE_CLASSIC_COMBINER_TEXTURE_AMMOCRATE1 ||
        result.draws[2].texture_id != GE_CLASSIC_COMBINER_TEXTURE_AMMOTEXT765 ||
        result.draws[3].texture_id != GE_CLASSIC_COMBINER_TEXTURE_CRATEROPE) {
        ge_combiner_set_error(&result, GE_STATUS_ASSET_MISMATCH,
                              GE_COMBINER_OP_TRI4, 0u);
        return result;
    }

    uint64_t key_hash = ge_combiner_hash_init();
    for (uint32_t index = 0; index < result.draw_count; index++) {
        GEClassicCombinerDrawKeyV4 *draw = &result.draws[index];
        draw->key_hash = ge_combiner_hash_draw(draw);
        key_hash = ge_combiner_hash_u64(key_hash, draw->key_hash);
        key_hash = ge_combiner_hash_u32(key_hash, draw->triangle_group_count);
    }
    result.event_hash = event_hash;
    result.key_hash = key_hash;
    result.status = GE_STATUS_OK;
    return result;
}

GEClassicCombinerLoweringResultV4 ge_classic_lower_ammo_crate_v4(
    GEClassicAssetBlobV2 blob)
{
    GEClassicCombinerLoweringResultV4 result;
    ge_combiner_init_result(&result);
    if (blob.header.abi_version != GE_NATIVE_ABI_VERSION) {
        ge_combiner_set_error(&result, GE_STATUS_INVALID_VERSION, 0u, 0u);
        return result;
    }
    if (blob.header.struct_size != sizeof(blob)) {
        ge_combiner_set_error(&result, GE_STATUS_INVALID_SIZE, 0u, 0u);
        return result;
    }
    if (blob.reserved != 0u) {
        ge_combiner_set_error(&result, GE_STATUS_RESERVED_BITS, 0u, 0u);
        return result;
    }
    if (blob.byte_count != GE_COMBINER_PROP_SIZE ||
        blob.byte_count > GE_CLASSIC_ASSET_BLOB_CAPACITY) {
        ge_combiner_set_error(&result, GE_STATUS_ASSET_MISMATCH, 0u, 0u);
        return result;
    }
    GEClassicCombinerInputV4 input =
        ge_classic_ammo_crate_combiner_input_v4(blob);
    return ge_classic_lower_combiner_v4(input);
}
