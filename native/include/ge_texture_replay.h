#ifndef GE_TEXTURE_REPLAY_H
#define GE_TEXTURE_REPLAY_H

#include <stdint.h>

/* SwiftPM may import this public header before goldeneye_native.h. */
#include "ge_native_foundation.h"
#include "ge_classic_replay.h"

#define GE_TEXTURE_REPLAY_ABI_VERSION ((uint32_t)3u)
#define GE_TEXTURE_REPLAY_PACKET_VERSION ((uint32_t)1u)
#define GE_TEXTURE_SOURCE_BLOB_CAPACITY ((uint32_t)4096u)
#define GE_TEXTURE_DECODED_BYTE_CAPACITY ((uint32_t)16384u)
#define GE_TEXTURE_PALETTE_ENTRY_CAPACITY ((uint32_t)256u)
#define GE_TEXTURE_MIP_CAPACITY ((uint32_t)7u)
#define GE_TEXTURE_MATERIAL_CAPACITY ((uint32_t)3u)
#define GE_TEXTURE_DRAW_CAPACITY GE_CLASSIC_DRAW_CAPACITY

/* Values mirror tools/mktex/src/libpdtex/pdtex.h. */
#define GE_TEXTURE_FORMAT_IA4 ((uint32_t)6u)
#define GE_TEXTURE_FORMAT_I8 ((uint32_t)7u)
#define GE_TEXTURE_FORMAT_RGBA16_CI8 ((uint32_t)9u)
#define GE_TEXTURE_COMPRESSION_HUFFMAN_LOOKUP ((uint32_t)6u)
#define GE_TEXTURE_COMPRESSION_HUFFMAN_BLUR ((uint32_t)8u)

typedef struct GETextureSourceBlobV3 {
    GEAbiHeaderV1 header;
    uint32_t texture_id;
    uint32_t byte_count;
    uint32_t reserved;
    uint8_t bytes[GE_TEXTURE_SOURCE_BLOB_CAPACITY];
} GETextureSourceBlobV3;

typedef struct GETextureMaterialDescriptorV3 {
    uint32_t texture_id;
    uint32_t width;
    uint32_t height;
    uint32_t mipmap_tiles;
    uint32_t format;
    uint32_t compression;
    uint32_t s_flags;
    uint32_t t_flags;
    uint32_t source_byte_count;
    uint64_t source_hash;
} GETextureMaterialDescriptorV3;

typedef struct GETextureMaterialSetV3 {
    GEAbiHeaderV1 header;
    uint32_t material_count;
    uint32_t reserved;
    GETextureMaterialDescriptorV3 materials[GE_TEXTURE_MATERIAL_CAPACITY];
} GETextureMaterialSetV3;

typedef struct GETextureDecodeResultV3 {
    GEAbiHeaderV1 header;
    GEStatusV1 status;
    uint32_t texture_id;
    uint32_t source_format;
    uint32_t source_compression;
    uint32_t width;
    uint32_t height;
    uint32_t mip_count;
    uint32_t pixel_byte_count;
    uint32_t palette_count;
    uint32_t reserved;
    uint64_t source_hash;
    uint64_t decoded_hash;
    uint32_t mip_offsets[GE_TEXTURE_MIP_CAPACITY];
    uint32_t mip_widths[GE_TEXTURE_MIP_CAPACITY];
    uint32_t mip_heights[GE_TEXTURE_MIP_CAPACITY];
    uint8_t pixels[GE_TEXTURE_DECODED_BYTE_CAPACITY];
    uint8_t palette_rgba[GE_TEXTURE_PALETTE_ENTRY_CAPACITY * 4u];
} GETextureDecodeResultV3;

typedef struct GETextureMaterialStateV3 {
    uint32_t texture_id;
    uint32_t tile;
    uint32_t texture_state;
    uint32_t format;
    uint32_t size;
    uint32_t mip_level;
    uint32_t s_flags;
    uint32_t t_flags;
    uint32_t tmem_offset;
    uint32_t tlut_base;
    uint32_t tlut_count;
    uint32_t material_flags;
    uint64_t state_hash;
} GETextureMaterialStateV3;

typedef struct GETexturedVertexV3 {
    float x;
    float y;
    float z;
    float w;
    float s;
    float t;
    uint8_t r;
    uint8_t g;
    uint8_t b;
    uint8_t a;
    uint32_t source_vertex;
} GETexturedVertexV3;

typedef struct GETexturedDrawPacketV3 {
    GEAbiHeaderV1 header;
    uint32_t packet_version;
    uint32_t source_list_handle;
    uint32_t source_command_offset;
    uint32_t list_depth;
    uint32_t material_flags;
    uint32_t texture_id;
    uint32_t vertex_count;
    uint32_t triangle_count;
    uint64_t packet_hash;
    GETextureMaterialStateV3 material;
    GEClassicTransformSnapshotV2 transform;
    GETexturedVertexV3 vertices[GE_CLASSIC_CACHE_CAPACITY];
    GEClassicTriangleV2 triangles[GE_CLASSIC_TRIANGLE_CAPACITY];
} GETexturedDrawPacketV3;

typedef struct GETexturedReplayResultV3 {
    GEAbiHeaderV1 header;
    GEStatusV1 status;
    uint32_t reserved;
    uint32_t error_opcode;
    uint32_t error_offset;
    uint32_t error_list_handle;
    uint32_t error_list_depth;
    uint32_t commands_processed;
    uint32_t draw_count;
    uint32_t vertex_count;
    uint32_t triangle_count;
    uint64_t packet_hash;
    uint64_t event_hash;
    uint64_t material_hash;
    GETexturedDrawPacketV3 draws[GE_TEXTURE_DRAW_CAPACITY];
} GETexturedReplayResultV3;

GETextureDecodeResultV3 ge_texture_decode_v3(GETextureSourceBlobV3 blob);
GETexturedReplayResultV3 ge_classic_replay_textured_prop_v3(
    GEClassicAssetBlobV2 prop_blob,
    GETextureMaterialSetV3 materials);

#if defined(__cplusplus)
#define GE_TEXTURE_STATIC_ASSERT(condition, message) static_assert((condition), message)
#else
#define GE_TEXTURE_STATIC_ASSERT(condition, message) _Static_assert((condition), message)
#endif

GE_TEXTURE_STATIC_ASSERT(sizeof(GETextureSourceBlobV3) == 4116u, "GETextureSourceBlobV3 layout drift");
GE_TEXTURE_STATIC_ASSERT(sizeof(GETextureMaterialDescriptorV3) == 48u, "GETextureMaterialDescriptorV3 layout drift");
GE_TEXTURE_STATIC_ASSERT(sizeof(GETextureMaterialStateV3) == 56u, "GETextureMaterialStateV3 layout drift");
GE_TEXTURE_STATIC_ASSERT(sizeof(GETexturedVertexV3) == 32u, "GETexturedVertexV3 layout drift");

#undef GE_TEXTURE_STATIC_ASSERT

#endif /* GE_TEXTURE_REPLAY_H */
