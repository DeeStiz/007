#ifndef GE_SOURCE_TEXTURE_COORDINATES_V6_H
#define GE_SOURCE_TEXTURE_COORDINATES_V6_H

/*
 * Value-only lowering for the classic GE/F3D texture-coordinate path.
 *
 * The source vertex fields are signed S10.5 texel coordinates.  The source
 * gSPTexture command carries a 16-bit Q0.16 scale, while SETTILE and
 * SETTILESIZE are retained as their original command words so that all four
 * 10.2 tile bounds survive the boundary.  This helper intentionally does not
 * retain a Gfx pointer, segmented address, ROM offset, or Metal object.
 *
 * The result keeps both the pre-addressed and addressed fixed-point values.
 * The former is useful for source evidence; the latter is the value a native
 * sampler can consume after source mask/shift/address-mode semantics have
 * been applied.  All Q16 fields are signed 16.16 values and all hashes use
 * the deterministic little-endian FNV-1a rules implemented in the C file.
 */

#include <stdint.h>

#include "ge_native_foundation.h"

#ifdef __cplusplus
extern "C" {
#endif

#define GE_SOURCE_TEXTURE_COORDINATES_V6_ABI_VERSION ((uint32_t)6u)
#define GE_SOURCE_TEXTURE_COORDINATES_V6_RECORD_VERSION ((uint32_t)1u)

#define GE_SOURCE_TEXTURE_COORDINATES_V6_OP_TEXTURE ((uint32_t)0xbbu)
#define GE_SOURCE_TEXTURE_COORDINATES_V6_OP_SETTILE ((uint32_t)0xf5u)
#define GE_SOURCE_TEXTURE_COORDINATES_V6_OP_SETTILESIZE ((uint32_t)0xf2u)

#define GE_SOURCE_TEXTURE_COORDINATES_V6_FLAG_TEXTURE_ENABLED ((uint32_t)1u << 0)
#define GE_SOURCE_TEXTURE_COORDINATES_V6_FLAG_TILE_CONFIGURED ((uint32_t)1u << 1)
#define GE_SOURCE_TEXTURE_COORDINATES_V6_FLAG_TILE_BOUNDS ((uint32_t)1u << 2)
#define GE_SOURCE_TEXTURE_COORDINATES_V6_FLAG_SOURCE_ANCHOR ((uint32_t)1u << 3)
#define GE_SOURCE_TEXTURE_COORDINATES_V6_FLAG_MASK ((uint32_t)0x0fu)

/* Address modes are the decoded two-bit G_TX_* CMT/CMS values. */
#define GE_SOURCE_TEXTURE_COORDINATES_V6_ADDRESS_WRAP ((uint32_t)0u)
#define GE_SOURCE_TEXTURE_COORDINATES_V6_ADDRESS_MIRROR ((uint32_t)1u)
#define GE_SOURCE_TEXTURE_COORDINATES_V6_ADDRESS_CLAMP ((uint32_t)2u)

#define GE_SOURCE_TEXTURE_COORDINATES_V6_DIAG_NONE ((uint32_t)0u)
#define GE_SOURCE_TEXTURE_COORDINATES_V6_DIAG_ARGUMENT ((uint32_t)1u)
#define GE_SOURCE_TEXTURE_COORDINATES_V6_DIAG_OPCODE ((uint32_t)2u)
#define GE_SOURCE_TEXTURE_COORDINATES_V6_DIAG_TILE ((uint32_t)3u)
#define GE_SOURCE_TEXTURE_COORDINATES_V6_DIAG_LEVEL ((uint32_t)4u)
#define GE_SOURCE_TEXTURE_COORDINATES_V6_DIAG_DIMENSIONS ((uint32_t)5u)
#define GE_SOURCE_TEXTURE_COORDINATES_V6_DIAG_ADDRESS_MODE ((uint32_t)6u)
#define GE_SOURCE_TEXTURE_COORDINATES_V6_DIAG_OVERFLOW ((uint32_t)7u)

/*
 * The input is deliberately command-word based.  GEGBITileStateV6 predates
 * this sidecar and stores only a 32-bit packed tile-size value; that loses the
 * lrt field.  Keeping the exact SETTILESIZE words here preserves uls, ult,
 * lrs, and lrt without changing the frozen GBI V6 record.
 */
typedef struct GETextureCoordinateInputV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t flags;
    uint32_t source_command_offset;
    uint32_t source_vertex_index;
    uint32_t texture_handle;
    int32_t source_s10_5;
    int32_t source_t10_5;
    uint32_t texture_command_w0;
    uint32_t texture_command_w1;
    uint32_t tile_command_w0;
    uint32_t tile_command_w1;
    uint32_t tile_size_command_w0;
    uint32_t tile_size_command_w1;
    /* gSPTexture level is the maximum LOD level, not the active mip. */
    uint32_t max_level;
    uint32_t level_count;
    uint32_t level_width;
    uint32_t level_height;
    uint64_t source_state_hash;
    uint64_t source_command_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GETextureCoordinateInputV6;

typedef struct GETextureCoordinateResultV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    GEStatusV1 status;
    uint32_t flags;
    uint32_t diagnostic;
    uint32_t source_command_offset;
    uint32_t source_vertex_index;
    uint32_t texture_handle;
    /* Preserved gSPTexture maximum LOD level.  Sampling remains base-tile
       normalized; the RDP selects the mip dynamically from LOD state. */
    uint32_t max_level;
    uint32_t selected_tile;
    uint32_t level_width;
    uint32_t level_height;
    uint32_t scale_s_q0_16;
    uint32_t scale_t_q0_16;
    int32_t source_s10_5;
    int32_t source_t10_5;
    int32_t tile_uls_q2;
    int32_t tile_ult_q2;
    int32_t tile_lrs_q2;
    int32_t tile_lrt_q2;
    int32_t tile_width_q16;
    int32_t tile_height_q16;
    int64_t scaled_s_q16;
    int64_t scaled_t_q16;
    int64_t shifted_s_q16;
    int64_t shifted_t_q16;
    int64_t local_s_q16;
    int64_t local_t_q16;
    int64_t addressed_s_q16;
    int64_t addressed_t_q16;
    int64_t normalized_s_q16;
    int64_t normalized_t_q16;
    int64_t tile_normalized_s_q16;
    int64_t tile_normalized_t_q16;
    uint32_t address_s;
    uint32_t address_t;
    uint32_t mask_s;
    uint32_t mask_t;
    uint32_t shift_s;
    uint32_t shift_t;
    uint32_t tile_format;
    uint32_t tile_size;
    uint32_t tile_line;
    uint32_t tile_tmem;
    uint32_t tile_palette;
    uint64_t source_hash;
    uint64_t result_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GETextureCoordinateResultV6;

/*
 * Decode a classic SETTILESIZE pair without losing any 10.2 field.  The
 * output array is [uls, ult, lrs, lrt], all unsigned 12-bit Q2 values.
 */
GEStatusV1 ge_source_texture_coordinates_v6_unpack_tile_size(
    uint32_t w0,
    uint32_t w1,
    uint32_t out_bounds[4]);

GEStatusV1 ge_source_texture_coordinates_v6_lower(
    const GETextureCoordinateInputV6 *input,
    GETextureCoordinateResultV6 *result);

uint64_t ge_source_texture_coordinates_v6_hash_input(
    const GETextureCoordinateInputV6 *input);

uint64_t ge_source_texture_coordinates_v6_hash_result(
    const GETextureCoordinateResultV6 *result);

#if defined(__cplusplus)
#define GE_SOURCE_TEXTURE_COORDINATES_V6_STATIC_ASSERT(condition, message) \
    static_assert((condition), message)
#else
#define GE_SOURCE_TEXTURE_COORDINATES_V6_STATIC_ASSERT(condition, message) \
    _Static_assert((condition), message)
#endif

GE_SOURCE_TEXTURE_COORDINATES_V6_STATIC_ASSERT(
    sizeof(GETextureCoordinateInputV6) == 104u,
    "GETextureCoordinateInputV6 layout drift");
GE_SOURCE_TEXTURE_COORDINATES_V6_STATIC_ASSERT(
    sizeof(GETextureCoordinateResultV6) == 264u,
    "GETextureCoordinateResultV6 layout drift");

#undef GE_SOURCE_TEXTURE_COORDINATES_V6_STATIC_ASSERT

#ifdef __cplusplus
}
#endif

#endif /* GE_SOURCE_TEXTURE_COORDINATES_V6_H */
