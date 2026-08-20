#ifndef GE_TITLE_UV_V1_H
#define GE_TITLE_UV_V1_H

/*
 * Additive source-derived title UV/material stream.
 *
 * GETU is deliberately independent of GETP and GETT.  It contains copied
 * source vertex coordinates, signed N64 s/t values, a deterministic
 * source-local texture handle, and a value-only command hash for every
 * triangle corner.  No pointer, segmented address, ROM address, Gfx word,
 * path, or Metal object crosses this boundary.  The source-local texture
 * handle is an evidence key matching the guarded GETT resource_id field.
 */

#include <stdint.h>

#include "ge_native_foundation.h"

#ifdef __cplusplus
extern "C" {
#endif

#define GE_TITLE_UV_V1_CONTRACT_VERSION ((uint32_t)1u)
#define GE_TITLE_UV_V1_HEADER_SIZE ((uint32_t)128u)
#define GE_TITLE_UV_V1_RECORD_SIZE ((uint32_t)64u)

#define GE_TITLE_UV_V1_FLAG_HAS_TRIANGLES ((uint32_t)1u << 0)
#define GE_TITLE_UV_V1_FLAG_HAS_UNSUPPORTED ((uint32_t)1u << 1)
#define GE_TITLE_UV_V1_FLAG_PARTIAL_SOURCE ((uint32_t)1u << 2)
#define GE_TITLE_UV_V1_FLAG_HAS_TEXTURE_HANDLES ((uint32_t)1u << 3)
#define GE_TITLE_UV_V1_FLAG_SIGNED_ST ((uint32_t)1u << 4)
#define GE_TITLE_UV_V1_FLAG_COMMAND_HASHES ((uint32_t)1u << 5)
#define GE_TITLE_UV_V1_FLAG_CORNER_EXPANSION ((uint32_t)1u << 6)
#define GE_TITLE_UV_V1_FLAG_MASK ((uint32_t)0x7fu)

typedef struct GETitleUVPacketHeaderV1 {
    uint8_t magic[4];
    uint32_t packet_version;
    GEAbiHeaderV1 header;
    uint32_t model_handle;
    uint32_t record_count;
    uint32_t record_stride;
    uint32_t index_count;
    uint32_t flags;
    uint32_t source_command_count;
    uint32_t unsupported_command_count;
    uint32_t source_byte_count;
    uint8_t source_sha256[32];
    uint8_t packet_sha256[32];
    uint32_t reserved0[4];
} GETitleUVPacketHeaderV1;

typedef struct GETitleUVRecordV1 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t vertex_index;
    int32_t x;
    int32_t y;
    int32_t z;
    int32_t s;
    int32_t t;
    uint32_t material_handle;
    uint64_t source_command_hash;
    uint64_t source_vertex_hash;
    uint32_t flags;
    uint32_t reserved0;
} GETitleUVRecordV1;

#if defined(__cplusplus)
#define GE_TITLE_UV_V1_STATIC_ASSERT(condition, message) static_assert((condition), message)
#else
#define GE_TITLE_UV_V1_STATIC_ASSERT(condition, message) _Static_assert((condition), message)
#endif

GE_TITLE_UV_V1_STATIC_ASSERT(sizeof(GEAbiHeaderV1) == 8u,
                              "GEAbiHeaderV1 layout drift");
GE_TITLE_UV_V1_STATIC_ASSERT(sizeof(GETitleUVPacketHeaderV1) == 128u,
                              "GETitleUVPacketHeaderV1 layout drift");
GE_TITLE_UV_V1_STATIC_ASSERT(sizeof(GETitleUVRecordV1) == 64u,
                              "GETitleUVRecordV1 layout drift");

#undef GE_TITLE_UV_V1_STATIC_ASSERT

#ifdef __cplusplus
}
#endif

#endif /* GE_TITLE_UV_V1_H */
