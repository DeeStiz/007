#ifndef GE_TITLE_TEXTURE_V8_H
#define GE_TITLE_TEXTURE_V8_H

/*
 * Additive source-derived title texture contract.
 *
 * GETT packets contain copied, fixed-width source metadata and decoded RGBA8
 * payloads.  The packet is deliberately independent of GETP and the frozen
 * V1--V4 contracts: source-local image offsets and symbolic image tokens are
 * evidence keys only.  No record contains a pointer, ROM address, path, Gfx
 * word, or Metal object.
 */

#include <stdint.h>

#include "ge_native_foundation.h"

#ifdef __cplusplus
extern "C" {
#endif

#define GE_TITLE_TEXTURE_V8_CONTRACT_VERSION ((uint32_t)1u)
#define GE_TITLE_TEXTURE_V8_HEADER_SIZE ((uint32_t)128u)
#define GE_TITLE_TEXTURE_V8_RECORD_SIZE ((uint32_t)144u)

#define GE_TITLE_TEXTURE_V8_FORMAT_RGBA ((uint32_t)0u)
#define GE_TITLE_TEXTURE_V8_FORMAT_YUV ((uint32_t)1u)
#define GE_TITLE_TEXTURE_V8_FORMAT_CI ((uint32_t)2u)
#define GE_TITLE_TEXTURE_V8_FORMAT_IA ((uint32_t)3u)
#define GE_TITLE_TEXTURE_V8_FORMAT_I ((uint32_t)4u)

#define GE_TITLE_TEXTURE_V8_SIZE_4B ((uint32_t)0u)
#define GE_TITLE_TEXTURE_V8_SIZE_8B ((uint32_t)1u)
#define GE_TITLE_TEXTURE_V8_SIZE_16B ((uint32_t)2u)
#define GE_TITLE_TEXTURE_V8_SIZE_32B ((uint32_t)3u)

#define GE_TITLE_TEXTURE_V8_FLAG_DIRECT_MODEL ((uint32_t)1u << 0)
#define GE_TITLE_TEXTURE_V8_FLAG_IMAGE_STREAM ((uint32_t)1u << 1)
#define GE_TITLE_TEXTURE_V8_FLAG_DECODED_RGBA8 ((uint32_t)1u << 2)
#define GE_TITLE_TEXTURE_V8_FLAG_MIP_CHAIN ((uint32_t)1u << 3)
#define GE_TITLE_TEXTURE_V8_FLAG_SYMBOLIC_ID ((uint32_t)1u << 4)
#define GE_TITLE_TEXTURE_V8_FLAG_TILED ((uint32_t)1u << 5)
#define GE_TITLE_TEXTURE_V8_FLAG_CLAMP_S ((uint32_t)1u << 6)
#define GE_TITLE_TEXTURE_V8_FLAG_CLAMP_T ((uint32_t)1u << 7)
#define GE_TITLE_TEXTURE_V8_FLAG_MIRROR_S ((uint32_t)1u << 8)
#define GE_TITLE_TEXTURE_V8_FLAG_MIRROR_T ((uint32_t)1u << 9)
#define GE_TITLE_TEXTURE_V8_FLAG_BILERP ((uint32_t)1u << 10)
#define GE_TITLE_TEXTURE_V8_FLAG_DETAIL_CLAMP ((uint32_t)1u << 11)
#define GE_TITLE_TEXTURE_V8_FLAG_MASK ((uint32_t)0x0fffu)

typedef struct GETitleTexturePacketHeaderV8 {
    uint8_t magic[4];
    uint32_t packet_version;
    GEAbiHeaderV1 header;
    uint32_t model_handle;
    uint32_t record_count;
    uint32_t record_stride;
    uint32_t payload_byte_count;
    uint32_t source_byte_count;
    uint32_t flags;
    uint8_t source_sha256[32];
    uint8_t packet_sha256[32];
    uint32_t reserved0[6];
} GETitleTexturePacketHeaderV8;

typedef struct GETitleTextureRecordV8 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t resource_id;
    uint32_t width;
    uint32_t height;
    uint32_t mip_map_tiles;
    uint32_t type;
    uint32_t render_depth;
    uint32_t s_flags;
    uint32_t t_flags;
    uint32_t format;
    uint32_t size;
    uint32_t source_stride_bytes;
    uint32_t decoded_byte_count;
    uint32_t source_offset;
    uint32_t payload_offset;
    uint32_t flags;
    uint32_t source_byte_count;
    uint32_t reserved0;
    uint8_t source_sha256[32];
    uint8_t decoded_sha256[32];
} GETitleTextureRecordV8;

#if defined(__cplusplus)
#define GE_TITLE_TEXTURE_V8_STATIC_ASSERT(condition, message) static_assert((condition), message)
#else
#define GE_TITLE_TEXTURE_V8_STATIC_ASSERT(condition, message) _Static_assert((condition), message)
#endif

GE_TITLE_TEXTURE_V8_STATIC_ASSERT(sizeof(GEAbiHeaderV1) == 8u,
                                  "GEAbiHeaderV1 layout drift");
GE_TITLE_TEXTURE_V8_STATIC_ASSERT(sizeof(GETitleTexturePacketHeaderV8) == 128u,
                                  "GETitleTexturePacketHeaderV8 layout drift");
GE_TITLE_TEXTURE_V8_STATIC_ASSERT(sizeof(GETitleTextureRecordV8) == 144u,
                                  "GETitleTextureRecordV8 layout drift");

#undef GE_TITLE_TEXTURE_V8_STATIC_ASSERT

#ifdef __cplusplus
}
#endif

#endif /* GE_TITLE_TEXTURE_V8_H */
