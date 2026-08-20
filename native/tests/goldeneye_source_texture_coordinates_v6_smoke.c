#include "ge_source_texture_coordinates_v6.h"

#include <assert.h>
#include <inttypes.h>
#include <stdio.h>
#include <string.h>

static uint32_t texture_w0(uint32_t tile, uint32_t level, uint32_t enabled)
{
    return (GE_SOURCE_TEXTURE_COORDINATES_V6_OP_TEXTURE << 24) |
           ((level & 7u) << 11) | ((tile & 7u) << 8) | (enabled & 0xffu);
}

static uint32_t tile_w0(uint32_t format, uint32_t size, uint32_t line, uint32_t tmem)
{
    return (GE_SOURCE_TEXTURE_COORDINATES_V6_OP_SETTILE << 24) |
           ((format & 7u) << 21) | ((size & 3u) << 19) |
           ((line & 0x1ffu) << 9) | (tmem & 0x1ffu);
}

static uint32_t tile_w1(uint32_t tile, uint32_t cmt, uint32_t maskt,
                        uint32_t shiftt, uint32_t cms, uint32_t masks,
                        uint32_t shifts)
{
    return ((tile & 7u) << 24) | ((cmt & 3u) << 18) |
           ((maskt & 0xfu) << 14) | ((shiftt & 0xfu) << 10) |
           ((cms & 3u) << 8) | ((masks & 0xfu) << 4) | (shifts & 0xfu);
}

static uint32_t tile_size_w0(uint32_t uls, uint32_t ult)
{
    return (GE_SOURCE_TEXTURE_COORDINATES_V6_OP_SETTILESIZE << 24) |
           ((uls & 0xfffu) << 12) | (ult & 0xfffu);
}

static uint32_t tile_size_w1(uint32_t tile, uint32_t lrs, uint32_t lrt)
{
    return ((tile & 7u) << 24) | ((lrs & 0xfffu) << 12) | (lrt & 0xfffu);
}

static GETextureCoordinateInputV6 fixture_with_scale(
    uint32_t width, uint32_t height, int32_t s, int32_t t,
    uint32_t scale_s, uint32_t scale_t, uint32_t cmt, uint32_t cms,
    uint32_t maskt, uint32_t masks, uint32_t shiftt, uint32_t shifts,
    uint32_t lrs, uint32_t lrt, uint32_t tile_command_w0,
    uint32_t tile_command_w1, uint32_t tile_size_command_w0,
    uint32_t tile_size_command_w1)
{
    GETextureCoordinateInputV6 value;
    memset(&value, 0, sizeof(value));
    value.header.abi_version = GE_SOURCE_TEXTURE_COORDINATES_V6_ABI_VERSION;
    value.header.struct_size = sizeof(value);
    value.record_version = GE_SOURCE_TEXTURE_COORDINATES_V6_RECORD_VERSION;
    value.flags = GE_SOURCE_TEXTURE_COORDINATES_V6_FLAG_SOURCE_ANCHOR;
    value.source_command_offset = 0x120u;
    value.source_vertex_index = 7u;
    value.texture_handle = 0x7001u;
    value.source_s10_5 = s;
    value.source_t10_5 = t;
    value.texture_command_w0 = texture_w0(0u, 0u, 1u);
    value.texture_command_w1 = (scale_s << 16) | scale_t;
    value.tile_command_w0 = tile_command_w0 != 0u
        ? tile_command_w0 : tile_w0(0u, 2u, 8u, 0u);
    value.tile_command_w1 = tile_command_w1 != 0u
        ? tile_command_w1
        : tile_w1(0u, cmt, maskt, shiftt, cms, masks, shifts);
    value.tile_size_command_w0 = tile_size_command_w0 != 0u
        ? tile_size_command_w0 : tile_size_w0(0u, 0u);
    value.tile_size_command_w1 = tile_size_command_w1 != 0u
        ? tile_size_command_w1 : tile_size_w1(0u, lrs, lrt);
    value.max_level = 0u;
    value.level_count = 1u;
    value.level_width = width;
    value.level_height = height;
    value.source_state_hash = UINT64_C(0x0102030405060708);
    value.source_command_hash = UINT64_C(0x1112131415161718);
    return value;
}

static GETextureCoordinateInputV6 fixture(uint32_t width, uint32_t height,
                                           int32_t s, int32_t t,
                                           uint32_t cmt, uint32_t cms,
                                           uint32_t maskt, uint32_t masks,
                                           uint32_t shiftt, uint32_t shifts,
                                           uint32_t lrs, uint32_t lrt)
{
    return fixture_with_scale(width, height, s, t, 0xffffu, 0xffffu,
                              cmt, cms, maskt, masks, shiftt, shifts,
                              lrs, lrt, 0u, 0u, 0u, 0u);
}

static GETextureCoordinateInputV6 fixture_scale(uint32_t width, uint32_t height,
                                                 int32_t s, int32_t t,
                                                 uint32_t scale_s, uint32_t scale_t,
                                                 uint32_t cmt, uint32_t cms,
                                                 uint32_t maskt, uint32_t masks,
                                                 uint32_t shiftt, uint32_t shifts,
                                                 uint32_t lrs, uint32_t lrt)
{
    return fixture_with_scale(width, height, s, t, scale_s, scale_t,
                              cmt, cms, maskt, masks, shiftt, shifts,
                              lrs, lrt, 0u, 0u, 0u, 0u);
}

static GETextureCoordinateResultV6 lower(GETextureCoordinateInputV6 value)
{
    GETextureCoordinateResultV6 result;
    GEStatusV1 status = ge_source_texture_coordinates_v6_lower(&value, &result);
    assert(status == GE_STATUS_OK);
    assert(result.status == GE_STATUS_OK);
    assert(result.result_hash != 0u);
    assert(result.source_hash == ge_source_texture_coordinates_v6_hash_input(&value));
    return result;
}

static void test_unpack_preserves_lrt(void)
{
    uint32_t bounds[4] = {0u, 0u, 0u, 0u};
    assert(ge_source_texture_coordinates_v6_unpack_tile_size(
               tile_size_w0(0x123u, 0x234u),
               tile_size_w1(3u, 0x345u, 0x456u), bounds) == GE_STATUS_OK);
    assert(bounds[0] == 0x123u && bounds[1] == 0x234u &&
           bounds[2] == 0x345u && bounds[3] == 0x456u);
}

static void test_s105_edges(void)
{
    /* The source uses (width - 1) << 5 for the last texel.  The 0x400 and
       0x1000 values are the corresponding one-past-the-edge coordinates;
       clamp must land on the last source texel, not on an arbitrary /256
       normalized value. */
    GETextureCoordinateResultV6 legal_last = lower(
        fixture(32u, 32u, 31 * 32, 31 * 32, 2u, 2u, 0u, 0u, 0u, 0u,
                31u * 4u, 31u * 4u));
    assert(legal_last.scale_s_q0_16 == 0xffffu);
    assert(legal_last.normalized_s_q16 == INT64_C(63487)); /* 31.9995 / 32 */
    assert(legal_last.normalized_t_q16 == INT64_C(63487));

    GETextureCoordinateResultV6 legal_boundary = lower(
        fixture(32u, 32u, 0x400, 0x400, 2u, 2u, 0u, 0u, 0u, 0u,
                31u * 4u, 31u * 4u));
    assert(legal_boundary.scaled_s_q16 == INT64_C(32) * 65536 - 32);
    assert(legal_boundary.normalized_s_q16 == INT64_C(63488));

    GETextureCoordinateResultV6 nintendo_texgen = lower(
        fixture_scale(128u, 128u, 0x1000, 0x1000, 0x0800u, 0x0800u,
                      2u, 2u, 0u, 0u, 0u, 0u, 127u * 4u, 127u * 4u));
    assert(nintendo_texgen.scale_s_q0_16 == 0x0800u);
    assert(nintendo_texgen.scaled_s_q16 == INT64_C(4) * 65536);
    assert(nintendo_texgen.normalized_s_q16 == INT64_C(2048)); /* 4 / 128 */

    /* Exact GoldenEye source-model word 5:
       gsSPTexture(2048,2048,5,0,1).  Level 5 selects the maximum LOD for a
       six-level chain; it does not select a level-5 1x1 texture for UV
       normalization.  The base tile and base dimensions remain authoritative
       while the RDP derives the active mip from LOD state. */
    GETextureCoordinateInputV6 goldeneye = fixture_scale(
        32u, 32u, 0x400, 0x400, 0x0800u, 0x0800u,
        2u, 2u, 0u, 0u, 0u, 0u, 31u * 4u, 31u * 4u);
    goldeneye.texture_command_w0 = 0xbb002801u;
    goldeneye.max_level = 5u;
    goldeneye.level_count = 6u;
    GETextureCoordinateResultV6 goldeneye_result = lower(goldeneye);
    assert(goldeneye_result.max_level == 5u);
    assert(goldeneye_result.selected_tile == 0u);
    assert(goldeneye_result.level_width == 32u && goldeneye_result.level_height == 32u);
    assert(goldeneye_result.scaled_s_q16 == INT64_C(65536));
    assert(goldeneye_result.normalized_s_q16 == INT64_C(2048)); /* 1 / 32 */

    goldeneye.level_count = 5u;
    GETextureCoordinateResultV6 malformed_lod;
    assert(ge_source_texture_coordinates_v6_lower(&goldeneye, &malformed_lod) ==
           GE_STATUS_INVALID_ARGUMENT);
}

static void test_address_modes_and_shift(void)
{
    GETextureCoordinateResultV6 wrapped = lower(
        fixture_scale(32u, 32u, 0x800, 0x800, 0x8000u, 0x8000u,
                      0u, 0u, 5u, 5u, 0u, 0u, 31u * 4u, 31u * 4u));
    assert(wrapped.addressed_s_q16 == 0);
    assert(wrapped.normalized_s_q16 == 0);
    assert(wrapped.address_s == GE_SOURCE_TEXTURE_COORDINATES_V6_ADDRESS_WRAP);

    GETextureCoordinateResultV6 mirrored = lower(
        fixture_scale(32u, 32u, 48 * 64, 0, 0x8000u, 0x8000u,
                      0u, 1u, 0u, 5u, 0u, 0u, 31u * 4u, 31u * 4u));
    assert(mirrored.addressed_s_q16 == INT64_C(16) * 65536);
    assert(mirrored.normalized_s_q16 == INT64_C(32768));
    assert(mirrored.address_s == GE_SOURCE_TEXTURE_COORDINATES_V6_ADDRESS_MIRROR);

    GETextureCoordinateResultV6 shifted = lower(
        fixture_scale(32u, 32u, 31 * 64, 0, 0x8000u, 0x8000u,
                      2u, 2u, 0u, 0u, 1u, 1u, 31u * 4u, 31u * 4u));
    assert(shifted.shifted_s_q16 == INT64_C(15) * 65536 + 32768);
    assert(shifted.normalized_s_q16 == INT64_C(31744)); /* 15.5 / 32 */
    assert(shifted.shift_s == 1u && shifted.shift_t == 1u);
}

static void test_nonzero_origin_shift_order(void)
{
    /* Exact source-derived Rareware frontend words (source-model words 41
       and 42): tile 1 has mask=4/shift=1 and
       gsDPSetTileSize(1,2,2,62,62). GoldenEye's title display list has no
       nonzero SETTILESIZE command, so this uses the source's tile descriptor
       and size pair to exercise the same ordered state without inventing a
       tile-bound encoding. */
    GETextureCoordinateInputV6 value = fixture_with_scale(
        16u, 16u, 512, 512, 0x8000u, 0x8000u,
        0u, 0u, 4u, 4u, 1u, 1u, 62u, 62u,
        0xf5100900u, 0x01010441u, 0xf2002002u, 0x0103e03eu);
    value.texture_command_w0 = 0xbb000101u;
    GETextureCoordinateResultV6 result = lower(value);
    assert(result.tile_uls_q2 == 2 && result.tile_ult_q2 == 2);
    assert(result.tile_lrs_q2 == 62 && result.tile_lrt_q2 == 62);
    /* T is shifted while still in incoming texture-image space, then ULT is
       subtracted.  Shifting the already-origin-relative value would produce
       3.75 rather than the source-ordered 3.5 texel local coordinate. */
    assert(result.shifted_t_q16 == INT64_C(262144)); /* 4 texels */
    assert(result.local_t_q16 == INT64_C(229376)); /* 3.5 texels */
    assert(result.addressed_t_q16 == INT64_C(229376));
    assert(result.normalized_t_q16 == INT64_C(16384)); /* 4 / 16 */
}

static void test_fail_closed(void)
{
    GETextureCoordinateInputV6 value = fixture(32u, 32u, 0, 0, 0u, 0u, 0u, 0u,
                                               0u, 0u, 31u * 4u, 31u * 4u);
    GETextureCoordinateResultV6 result;

    value.texture_command_w0 = 0xd7000001u;
    assert(ge_source_texture_coordinates_v6_lower(&value, &result) ==
           GE_STATUS_UNSUPPORTED_COMMAND);
    value = fixture(32u, 32u, 0, 0, 0u, 0u, 0u, 0u, 0u, 0u,
                    31u * 4u, 31u * 4u);
    value.tile_command_w1 |= 3u << 8;
    assert(ge_source_texture_coordinates_v6_lower(&value, &result) ==
           GE_STATUS_UNSUPPORTED_COMMAND);
    value = fixture(32u, 32u, 0, 0, 0u, 0u, 0u, 0u, 0u, 0u,
                    31u * 4u, 31u * 4u);
    value.tile_size_command_w1 &= ~(0xfffu << 12);
    value.tile_size_command_w1 |= 31u * 4u << 12;
    value.tile_size_command_w1 &= ~0xfffu;
    value.tile_size_command_w1 |= 0u;
    value.reserved0 = 1u;
    assert(ge_source_texture_coordinates_v6_lower(&value, &result) ==
           GE_STATUS_RESERVED_BITS);
}

int main(void)
{
    test_unpack_preserves_lrt();
    test_s105_edges();
    test_address_modes_and_shift();
    test_nonzero_origin_shift_order();
    test_fail_closed();
    GETextureCoordinateInputV6 hash_input = fixture(
        32u, 32u, 0x400, 0x400, 2u, 2u, 0u, 0u, 0u, 0u,
        31u * 4u, 31u * 4u);
    GETextureCoordinateResultV6 hash_result = lower(hash_input);
    GETextureCoordinateInputV6 goldeneye_hash_input = fixture_scale(
        32u, 32u, 0x400, 0x400, 0x0800u, 0x0800u,
        2u, 2u, 0u, 0u, 0u, 0u, 31u * 4u, 31u * 4u);
    goldeneye_hash_input.texture_command_w0 = 0xbb002801u;
    goldeneye_hash_input.max_level = 5u;
    goldeneye_hash_input.level_count = 6u;
    GETextureCoordinateResultV6 goldeneye_hash_result = lower(goldeneye_hash_input);
    printf("goldeneye_source_texture_coordinates_v6_smoke: PASS sourceHash=%" PRIu64
           " resultHash=%" PRIu64 " goldeneye6SourceHash=%" PRIu64
           " goldeneye6ResultHash=%" PRIu64 "\n",
           ge_source_texture_coordinates_v6_hash_input(&hash_input),
           hash_result.result_hash,
           ge_source_texture_coordinates_v6_hash_input(&goldeneye_hash_input),
           goldeneye_hash_result.result_hash);
    return 0;
}
