#include "ge_source_texture_coordinates_v6.h"

#include <limits.h>
#include <stddef.h>
#include <string.h>

#define GE_TEXTURE_COORDINATES_V6_HASH_OFFSET UINT64_C(1469598103934665603)
#define GE_TEXTURE_COORDINATES_V6_HASH_PRIME UINT64_C(1099511628211)

static uint64_t ge_tc_hash_byte(uint64_t hash, uint8_t value)
{
    return (hash ^ (uint64_t)value) * GE_TEXTURE_COORDINATES_V6_HASH_PRIME;
}

static uint64_t ge_tc_hash_u32(uint64_t hash, uint32_t value)
{
    for (uint32_t index = 0u; index < 4u; index++) {
        hash = ge_tc_hash_byte(hash, (uint8_t)(value >> (index * 8u)));
    }
    return hash;
}

static uint64_t ge_tc_hash_i32(uint64_t hash, int32_t value)
{
    return ge_tc_hash_u32(hash, (uint32_t)value);
}

static uint64_t ge_tc_hash_u64(uint64_t hash, uint64_t value)
{
    for (uint32_t index = 0u; index < 8u; index++) {
        hash = ge_tc_hash_byte(hash, (uint8_t)(value >> (index * 8u)));
    }
    return hash;
}

static uint64_t ge_tc_hash_i64(uint64_t hash, int64_t value)
{
    return ge_tc_hash_u64(hash, (uint64_t)value);
}

static int ge_tc_mul_add_overflow_i64(int64_t left,
                                      int64_t right,
                                      int64_t addend,
                                      int64_t *out)
{
    if (right != 0 &&
        ((left > 0 && right > 0 && left > (INT64_MAX - addend) / right) ||
         (left < 0 && right < 0 && left < (INT64_MAX - addend) / right) ||
         (left > 0 && right < 0 && right < (INT64_MIN - addend) / left) ||
         (left < 0 && right > 0 && left < (INT64_MIN - addend) / right))) {
        return 0;
    }
    *out = left * right + addend;
    return 1;
}

static int64_t ge_tc_floor_div_pow2(int64_t value, uint32_t shift)
{
    if (shift == 0u) {
        return value;
    }
    const int64_t divisor = INT64_C(1) << shift;
    if (value >= 0) {
        return value / divisor;
    }
    /* The RSP's signed coordinate shift is arithmetic.  Make the rounding
       direction explicit instead of relying on the host compiler's >> rule. */
    const int64_t magnitude = value == INT64_MIN ? INT64_MAX : -value;
    const int64_t rounded = (magnitude + divisor - 1) / divisor;
    return -rounded;
}

static int ge_tc_shift_q16(int64_t value, uint32_t shift, int64_t *out)
{
    if (shift <= 10u) {
        *out = ge_tc_floor_div_pow2(value, shift);
        return 1;
    }
    const uint32_t left = 16u - shift;
    if (left >= 63u) {
        return 0;
    }
    const int64_t multiplier = INT64_C(1) << left;
    if ((value > 0 && value > INT64_MAX / multiplier) ||
        (value < 0 && value < INT64_MIN / multiplier)) {
        return 0;
    }
    *out = value * multiplier;
    return 1;
}

static int64_t ge_tc_mod(int64_t value, int64_t period)
{
    int64_t remainder = value % period;
    if (remainder < 0) {
        remainder += period;
    }
    return remainder;
}

static int ge_tc_address(int64_t value,
                         uint32_t mode,
                         uint32_t mask,
                         int64_t tile_max_q16,
                         int64_t *out)
{
    if (tile_max_q16 < 0 || out == NULL) {
        return 0;
    }
    /* The RDP treats G_TX_NOMASK (zero) as an implicit clamp, even when the
       descriptor's mirror/wrap bit is clear.  A non-zero mask is required for
       a repeating or mirrored address period. */
    if (mask == 0u || mode == GE_SOURCE_TEXTURE_COORDINATES_V6_ADDRESS_CLAMP) {
        if (value < 0) {
            *out = 0;
        } else if (value > tile_max_q16) {
            *out = tile_max_q16;
        } else {
            *out = value;
        }
        return 1;
    }
    if (mode != GE_SOURCE_TEXTURE_COORDINATES_V6_ADDRESS_WRAP &&
        mode != GE_SOURCE_TEXTURE_COORDINATES_V6_ADDRESS_MIRROR) {
        return 0;
    }

    /* G_TX_NOMASK repeats over the declared tile extent.  A non-zero mask
       selects the source's power-of-two address period. */
    int64_t period = mask == 0u ? tile_max_q16 + INT64_C(65536) :
        (INT64_C(1) << mask) * INT64_C(65536);
    if (period <= 0) {
        return 0;
    }
    int64_t remainder = ge_tc_mod(value, period);
    if (mode == GE_SOURCE_TEXTURE_COORDINATES_V6_ADDRESS_MIRROR) {
        const int64_t double_period = period > INT64_MAX / 2 ? 0 : period * 2;
        if (double_period <= 0) {
            return 0;
        }
        const int64_t mirrored = ge_tc_mod(value, double_period);
        remainder = mirrored < period ? mirrored : double_period - mirrored;
    }
    *out = remainder;
    return 1;
}

static GEStatusV1 ge_tc_fail(GETextureCoordinateResultV6 *result,
                             GEStatusV1 status,
                             uint32_t diagnostic)
{
    result->status = status;
    result->diagnostic = diagnostic;
    result->result_hash = 0u;
    return status;
}

GEStatusV1 ge_source_texture_coordinates_v6_unpack_tile_size(
    uint32_t w0,
    uint32_t w1,
    uint32_t out_bounds[4])
{
    if (out_bounds == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if ((w0 >> 24) != GE_SOURCE_TEXTURE_COORDINATES_V6_OP_SETTILESIZE ||
        ((w1 >> 24) & 7u) >= 8u) {
        return GE_STATUS_UNSUPPORTED_COMMAND;
    }
    out_bounds[0] = (w0 >> 12) & 0xfffu;
    out_bounds[1] = w0 & 0xfffu;
    out_bounds[2] = (w1 >> 12) & 0xfffu;
    out_bounds[3] = w1 & 0xfffu;
    return GE_STATUS_OK;
}

uint64_t ge_source_texture_coordinates_v6_hash_input(
    const GETextureCoordinateInputV6 *input)
{
    if (input == NULL) {
        return 0u;
    }
    uint64_t hash = GE_TEXTURE_COORDINATES_V6_HASH_OFFSET;
    hash = ge_tc_hash_u32(hash, input->record_version);
    hash = ge_tc_hash_u32(hash, input->flags);
    hash = ge_tc_hash_u32(hash, input->source_command_offset);
    hash = ge_tc_hash_u32(hash, input->source_vertex_index);
    hash = ge_tc_hash_u32(hash, input->texture_handle);
    hash = ge_tc_hash_i32(hash, input->source_s10_5);
    hash = ge_tc_hash_i32(hash, input->source_t10_5);
    hash = ge_tc_hash_u32(hash, input->texture_command_w0);
    hash = ge_tc_hash_u32(hash, input->texture_command_w1);
    hash = ge_tc_hash_u32(hash, input->tile_command_w0);
    hash = ge_tc_hash_u32(hash, input->tile_command_w1);
    hash = ge_tc_hash_u32(hash, input->tile_size_command_w0);
    hash = ge_tc_hash_u32(hash, input->tile_size_command_w1);
    hash = ge_tc_hash_u32(hash, input->max_level);
    hash = ge_tc_hash_u32(hash, input->level_count);
    hash = ge_tc_hash_u32(hash, input->level_width);
    hash = ge_tc_hash_u32(hash, input->level_height);
    hash = ge_tc_hash_u64(hash, input->source_state_hash);
    hash = ge_tc_hash_u64(hash, input->source_command_hash);
    return hash;
}

uint64_t ge_source_texture_coordinates_v6_hash_result(
    const GETextureCoordinateResultV6 *result)
{
    if (result == NULL) {
        return 0u;
    }
    uint64_t hash = GE_TEXTURE_COORDINATES_V6_HASH_OFFSET;
    hash = ge_tc_hash_u32(hash, result->record_version);
    hash = ge_tc_hash_u32(hash, result->status);
    hash = ge_tc_hash_u32(hash, result->flags);
    hash = ge_tc_hash_u32(hash, result->diagnostic);
    hash = ge_tc_hash_u32(hash, result->source_command_offset);
    hash = ge_tc_hash_u32(hash, result->source_vertex_index);
    hash = ge_tc_hash_u32(hash, result->texture_handle);
    hash = ge_tc_hash_u32(hash, result->max_level);
    hash = ge_tc_hash_u32(hash, result->selected_tile);
    hash = ge_tc_hash_u32(hash, result->level_width);
    hash = ge_tc_hash_u32(hash, result->level_height);
    hash = ge_tc_hash_u32(hash, result->scale_s_q0_16);
    hash = ge_tc_hash_u32(hash, result->scale_t_q0_16);
    hash = ge_tc_hash_i32(hash, result->source_s10_5);
    hash = ge_tc_hash_i32(hash, result->source_t10_5);
    hash = ge_tc_hash_i32(hash, result->tile_uls_q2);
    hash = ge_tc_hash_i32(hash, result->tile_ult_q2);
    hash = ge_tc_hash_i32(hash, result->tile_lrs_q2);
    hash = ge_tc_hash_i32(hash, result->tile_lrt_q2);
    hash = ge_tc_hash_i32(hash, result->tile_width_q16);
    hash = ge_tc_hash_i32(hash, result->tile_height_q16);
    hash = ge_tc_hash_i64(hash, result->scaled_s_q16);
    hash = ge_tc_hash_i64(hash, result->scaled_t_q16);
    hash = ge_tc_hash_i64(hash, result->shifted_s_q16);
    hash = ge_tc_hash_i64(hash, result->shifted_t_q16);
    hash = ge_tc_hash_i64(hash, result->local_s_q16);
    hash = ge_tc_hash_i64(hash, result->local_t_q16);
    hash = ge_tc_hash_i64(hash, result->addressed_s_q16);
    hash = ge_tc_hash_i64(hash, result->addressed_t_q16);
    hash = ge_tc_hash_i64(hash, result->normalized_s_q16);
    hash = ge_tc_hash_i64(hash, result->normalized_t_q16);
    hash = ge_tc_hash_i64(hash, result->tile_normalized_s_q16);
    hash = ge_tc_hash_i64(hash, result->tile_normalized_t_q16);
    hash = ge_tc_hash_u32(hash, result->address_s);
    hash = ge_tc_hash_u32(hash, result->address_t);
    hash = ge_tc_hash_u32(hash, result->mask_s);
    hash = ge_tc_hash_u32(hash, result->mask_t);
    hash = ge_tc_hash_u32(hash, result->shift_s);
    hash = ge_tc_hash_u32(hash, result->shift_t);
    hash = ge_tc_hash_u32(hash, result->tile_format);
    hash = ge_tc_hash_u32(hash, result->tile_size);
    hash = ge_tc_hash_u32(hash, result->tile_line);
    hash = ge_tc_hash_u32(hash, result->tile_tmem);
    hash = ge_tc_hash_u32(hash, result->tile_palette);
    hash = ge_tc_hash_u64(hash, result->source_hash);
    return hash;
}

static int ge_tc_normalize_q16(int64_t texel_q16,
                               uint32_t dimension,
                               int64_t *out)
{
    if (dimension == 0u || out == NULL) {
        return 0;
    }
    /* texel_q16 is already Q16, so division by the pixel dimension retains
       the normalized Q16 representation (31*65536 / 32 = 63488). */
    *out = texel_q16 / (int64_t)dimension;
    return 1;
}

static int ge_tc_normalize_ratio_q16(int64_t numerator_q16,
                                     int64_t denominator_q16,
                                     int64_t *out)
{
    if (denominator_q16 <= 0 || out == NULL ||
        numerator_q16 > INT64_MAX / INT64_C(65536) ||
        numerator_q16 < INT64_MIN / INT64_C(65536)) {
        return 0;
    }
    *out = (numerator_q16 * INT64_C(65536)) / denominator_q16;
    return 1;
}

GEStatusV1 ge_source_texture_coordinates_v6_lower(
    const GETextureCoordinateInputV6 *input,
    GETextureCoordinateResultV6 *result)
{
    if (input == NULL || result == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    memset(result, 0, sizeof(*result));
    result->header.abi_version = GE_SOURCE_TEXTURE_COORDINATES_V6_ABI_VERSION;
    result->header.struct_size = (uint32_t)sizeof(*result);
    result->record_version = GE_SOURCE_TEXTURE_COORDINATES_V6_RECORD_VERSION;

    if (input->header.abi_version != GE_SOURCE_TEXTURE_COORDINATES_V6_ABI_VERSION) {
        return ge_tc_fail(result, GE_STATUS_INVALID_VERSION,
                          GE_SOURCE_TEXTURE_COORDINATES_V6_DIAG_ARGUMENT);
    }
    if (input->header.struct_size != sizeof(*input) ||
        input->record_version != GE_SOURCE_TEXTURE_COORDINATES_V6_RECORD_VERSION) {
        return ge_tc_fail(result, GE_STATUS_INVALID_SIZE,
                          GE_SOURCE_TEXTURE_COORDINATES_V6_DIAG_ARGUMENT);
    }
    if ((input->flags & ~GE_SOURCE_TEXTURE_COORDINATES_V6_FLAG_MASK) != 0u ||
        input->reserved0 != 0u || input->reserved1 != 0u) {
        return ge_tc_fail(result, GE_STATUS_RESERVED_BITS,
                          GE_SOURCE_TEXTURE_COORDINATES_V6_DIAG_ARGUMENT);
    }
    if (input->source_s10_5 < INT16_MIN || input->source_s10_5 > INT16_MAX ||
        input->source_t10_5 < INT16_MIN || input->source_t10_5 > INT16_MAX) {
        return ge_tc_fail(result, GE_STATUS_INVALID_ARGUMENT,
                          GE_SOURCE_TEXTURE_COORDINATES_V6_DIAG_ARGUMENT);
    }
    if (input->texture_handle == 0u || input->level_count == 0u ||
        input->max_level >= input->level_count || input->level_width == 0u ||
        input->level_height == 0u || input->level_width > 16384u ||
        input->level_height > 16384u) {
        return ge_tc_fail(result, GE_STATUS_INVALID_ARGUMENT,
                          GE_SOURCE_TEXTURE_COORDINATES_V6_DIAG_DIMENSIONS);
    }

    const uint32_t texture_opcode = input->texture_command_w0 >> 24;
    if (texture_opcode != GE_SOURCE_TEXTURE_COORDINATES_V6_OP_TEXTURE) {
        return ge_tc_fail(result, GE_STATUS_UNSUPPORTED_COMMAND,
                          GE_SOURCE_TEXTURE_COORDINATES_V6_DIAG_OPCODE);
    }
    const uint32_t enabled = input->texture_command_w0 & 0xffu;
    const uint32_t selected_tile = (input->texture_command_w0 >> 8) & 7u;
    const uint32_t max_level = (input->texture_command_w0 >> 11) & 7u;
    if (enabled == 0u || max_level != input->max_level) {
        return ge_tc_fail(result, GE_STATUS_INVALID_STATE,
                          GE_SOURCE_TEXTURE_COORDINATES_V6_DIAG_LEVEL);
    }

    if ((input->tile_command_w0 >> 24) != GE_SOURCE_TEXTURE_COORDINATES_V6_OP_SETTILE ||
        ((input->tile_command_w1 >> 24) & 7u) != selected_tile ||
        (input->tile_size_command_w0 >> 24) != GE_SOURCE_TEXTURE_COORDINATES_V6_OP_SETTILESIZE ||
        ((input->tile_size_command_w1 >> 24) & 7u) != selected_tile) {
        return ge_tc_fail(result, GE_STATUS_INVALID_STATE,
                          GE_SOURCE_TEXTURE_COORDINATES_V6_DIAG_TILE);
    }

    uint32_t bounds[4] = {0u, 0u, 0u, 0u};
    GEStatusV1 bounds_status =
        ge_source_texture_coordinates_v6_unpack_tile_size(
            input->tile_size_command_w0, input->tile_size_command_w1, bounds);
    if (bounds_status != GE_STATUS_OK || bounds[2] < bounds[0] || bounds[3] < bounds[1]) {
        return ge_tc_fail(result, bounds_status == GE_STATUS_OK ? GE_STATUS_MALFORMED_STREAM : bounds_status,
                          GE_SOURCE_TEXTURE_COORDINATES_V6_DIAG_TILE);
    }

    const uint32_t cmt = (input->tile_command_w1 >> 18) & 3u;
    const uint32_t cms = (input->tile_command_w1 >> 8) & 3u;
    if (cmt == 3u || cms == 3u) {
        return ge_tc_fail(result, GE_STATUS_UNSUPPORTED_COMMAND,
                          GE_SOURCE_TEXTURE_COORDINATES_V6_DIAG_ADDRESS_MODE);
    }
    const uint32_t maskt = (input->tile_command_w1 >> 14) & 0xfu;
    const uint32_t shiftt = (input->tile_command_w1 >> 10) & 0xfu;
    const uint32_t masks = (input->tile_command_w1 >> 4) & 0xfu;
    const uint32_t shifts = input->tile_command_w1 & 0xfu;
    const uint32_t format = (input->tile_command_w0 >> 21) & 7u;
    const uint32_t size = (input->tile_command_w0 >> 19) & 3u;
    const uint32_t line = (input->tile_command_w0 >> 9) & 0x1ffu;
    const uint32_t tmem = input->tile_command_w0 & 0x1ffu;
    const uint32_t palette = (input->tile_command_w1 >> 20) & 0xfu;

    const int64_t tile_width_q2 = (int64_t)(bounds[2] - bounds[0]) + 4;
    const int64_t tile_height_q2 = (int64_t)(bounds[3] - bounds[1]) + 4;
    if (tile_width_q2 <= 0 || tile_height_q2 <= 0 ||
        tile_width_q2 > (int64_t)input->level_width * 4 ||
        tile_height_q2 > (int64_t)input->level_height * 4) {
        return ge_tc_fail(result, GE_STATUS_TEXTURE_FORMAT,
                          GE_SOURCE_TEXTURE_COORDINATES_V6_DIAG_DIMENSIONS);
    }

    memset(result, 0, sizeof(*result));
    result->header.abi_version = GE_SOURCE_TEXTURE_COORDINATES_V6_ABI_VERSION;
    result->header.struct_size = (uint32_t)sizeof(*result);
    result->record_version = GE_SOURCE_TEXTURE_COORDINATES_V6_RECORD_VERSION;
    result->status = GE_STATUS_OK;
    result->flags = GE_SOURCE_TEXTURE_COORDINATES_V6_FLAG_TEXTURE_ENABLED |
                    GE_SOURCE_TEXTURE_COORDINATES_V6_FLAG_TILE_CONFIGURED |
                    GE_SOURCE_TEXTURE_COORDINATES_V6_FLAG_TILE_BOUNDS |
                    (input->flags & GE_SOURCE_TEXTURE_COORDINATES_V6_FLAG_SOURCE_ANCHOR);
    result->source_command_offset = input->source_command_offset;
    result->source_vertex_index = input->source_vertex_index;
    result->texture_handle = input->texture_handle;
    result->max_level = max_level;
    result->selected_tile = selected_tile;
    result->level_width = input->level_width;
    result->level_height = input->level_height;
    result->scale_s_q0_16 = (input->texture_command_w1 >> 16) & 0xffffu;
    result->scale_t_q0_16 = input->texture_command_w1 & 0xffffu;
    result->source_s10_5 = input->source_s10_5;
    result->source_t10_5 = input->source_t10_5;
    result->tile_uls_q2 = (int32_t)bounds[0];
    result->tile_ult_q2 = (int32_t)bounds[1];
    result->tile_lrs_q2 = (int32_t)bounds[2];
    result->tile_lrt_q2 = (int32_t)bounds[3];
    result->tile_width_q16 = (int32_t)(tile_width_q2 << 14);
    result->tile_height_q16 = (int32_t)(tile_height_q2 << 14);
    result->address_s = cms;
    result->address_t = cmt;
    result->mask_s = masks;
    result->mask_t = maskt;
    result->shift_s = shifts;
    result->shift_t = shiftt;
    result->tile_format = format;
    result->tile_size = size;
    result->tile_line = line;
    result->tile_tmem = tmem;
    result->tile_palette = palette;
    result->source_hash = ge_source_texture_coordinates_v6_hash_input(input);

    /* GE Vtx S/T is S10.5.  gSPTexture's scale is Q0.16, so the RDP-facing
       Q16 texel coordinate is (S10.5 / 32) * scale.  Keep the product in
       signed 64-bit space and perform the /32 as an explicit arithmetic
       shift; this preserves the source's negative-coordinate rounding. */
    int64_t scaled_s_product = 0;
    int64_t scaled_t_product = 0;
    if (!ge_tc_mul_add_overflow_i64((int64_t)input->source_s10_5,
                                    (int64_t)result->scale_s_q0_16, 0,
                                    &scaled_s_product) ||
        !ge_tc_mul_add_overflow_i64((int64_t)input->source_t10_5,
                                    (int64_t)result->scale_t_q0_16, 0,
                                    &scaled_t_product)) {
        return ge_tc_fail(result, GE_STATUS_TEXTURE_OVERFLOW,
                          GE_SOURCE_TEXTURE_COORDINATES_V6_DIAG_OVERFLOW);
    }
    result->scaled_s_q16 = ge_tc_floor_div_pow2(scaled_s_product, 5u);
    result->scaled_t_q16 = ge_tc_floor_div_pow2(scaled_t_product, 5u);
    const int64_t origin_s_q16 = (int64_t)bounds[0] << 14;
    const int64_t origin_t_q16 = (int64_t)bounds[1] << 14;
    /* Shift the incoming coordinate before applying the tile origin.  This is
       observable for nonzero ULS/ULT and matches the RDP's post-perspective
       shift stage. */
    if (!ge_tc_shift_q16(result->scaled_s_q16, shifts, &result->shifted_s_q16) ||
        !ge_tc_shift_q16(result->scaled_t_q16, shiftt, &result->shifted_t_q16)) {
        return ge_tc_fail(result, GE_STATUS_TEXTURE_OVERFLOW,
                          GE_SOURCE_TEXTURE_COORDINATES_V6_DIAG_OVERFLOW);
    }
    result->local_s_q16 = result->shifted_s_q16 - origin_s_q16;
    result->local_t_q16 = result->shifted_t_q16 - origin_t_q16;
    const int64_t max_s_q16 = ((int64_t)bounds[2] - bounds[0]) << 14;
    const int64_t max_t_q16 = ((int64_t)bounds[3] - bounds[1]) << 14;
    if (!ge_tc_address(result->local_s_q16, cms, masks, max_s_q16,
                       &result->addressed_s_q16) ||
        !ge_tc_address(result->local_t_q16, cmt, maskt, max_t_q16,
                       &result->addressed_t_q16)) {
        return ge_tc_fail(result, GE_STATUS_UNSUPPORTED_COMMAND,
                          GE_SOURCE_TEXTURE_COORDINATES_V6_DIAG_ADDRESS_MODE);
    }
    const int64_t physical_s_q16 = origin_s_q16 + result->addressed_s_q16;
    const int64_t physical_t_q16 = origin_t_q16 + result->addressed_t_q16;
    if (!ge_tc_normalize_q16(physical_s_q16, input->level_width,
                             &result->normalized_s_q16) ||
        !ge_tc_normalize_q16(physical_t_q16, input->level_height,
                             &result->normalized_t_q16) ||
        !ge_tc_normalize_ratio_q16(result->addressed_s_q16,
                                   (int64_t)result->tile_width_q16,
                             &result->tile_normalized_s_q16) ||
        !ge_tc_normalize_ratio_q16(result->addressed_t_q16,
                                   (int64_t)result->tile_height_q16,
                             &result->tile_normalized_t_q16)) {
        return ge_tc_fail(result, GE_STATUS_TEXTURE_OVERFLOW,
                          GE_SOURCE_TEXTURE_COORDINATES_V6_DIAG_OVERFLOW);
    }
    result->result_hash = ge_source_texture_coordinates_v6_hash_result(result);
    return GE_STATUS_OK;
}
