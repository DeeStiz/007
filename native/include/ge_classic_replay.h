#ifndef GE_CLASSIC_REPLAY_H
#define GE_CLASSIC_REPLAY_H

/*
 * Versioned, value-only classic GoldenEye GE/F3D replay contract.
 *
 * This header is included by goldeneye_native.h after the V1 records have
 * been declared.  Nothing in this contract contains a pointer, host address,
 * Gfx object, N64 physical address, or SDK object.  The fixed capacities are
 * deliberate: malformed or unbounded source data must fail closed.
 */

#include <stdint.h>

/* SwiftPM imports public headers in filename order, so make this header
   self-contained while retaining the intentional goldeneye_native.h include
   at the end of that header. Include guards make the cycle harmless. */
#include "goldeneye_native.h"

#define GE_CLASSIC_REPLAY_ABI_VERSION ((uint32_t)2u)
#define GE_CLASSIC_REPLAY_PACKET_VERSION ((uint32_t)1u)
#define GE_CLASSIC_COMMAND_CAPACITY ((uint32_t)128u)
#define GE_CLASSIC_LIST_CAPACITY ((uint32_t)8u)
#define GE_CLASSIC_VERTEX_CAPACITY ((uint32_t)64u)
#define GE_CLASSIC_VERTEX_RESOURCE_CAPACITY ((uint32_t)8u)
#define GE_CLASSIC_MATRIX_CAPACITY ((uint32_t)8u)
#define GE_CLASSIC_SEGMENT_CAPACITY ((uint32_t)16u)
#define GE_CLASSIC_STACK_CAPACITY ((uint32_t)8u)
#define GE_CLASSIC_DRAW_CAPACITY ((uint32_t)8u)
#define GE_CLASSIC_CACHE_CAPACITY ((uint32_t)32u)
#define GE_CLASSIC_TRIANGLE_CAPACITY ((uint32_t)32u)
#define GE_CLASSIC_ASSET_BLOB_CAPACITY ((uint32_t)2048u)
#define GE_CLASSIC_MATERIAL_VERTEX_COLOR ((uint32_t)1u)
#define GE_CLASSIC_MATERIAL_TEXTURE_STATE_DEFERRED ((uint32_t)2u)

/* Classic wire words remain exactly two 32-bit words. */
typedef struct GEClassicCommandV2 {
    uint32_t w0;
    uint32_t w1;
} GEClassicCommandV2;

typedef struct GEClassicListResourceV2 {
    uint32_t handle;
    uint32_t first_command;
    uint32_t command_count;
    uint32_t flags;
} GEClassicListResourceV2;

typedef struct GEClassicVertexResourceV2 {
    uint32_t handle;
    uint32_t first_vertex;
    uint32_t vertex_count;
    uint32_t reserved;
} GEClassicVertexResourceV2;

/* Matrix elements are signed s15.16 values, stored in host-independent words. */
typedef struct GEClassicMatrixResourceV2 {
    uint32_t handle;
    int32_t values[16];
} GEClassicMatrixResourceV2;

/* Segment entries map classic segment IDs to deterministic resource handles. */
typedef struct GEClassicSegmentResourceV2 {
    uint32_t segment;
    uint32_t resource_handle;
    uint32_t byte_offset;
    uint32_t reserved;
} GEClassicSegmentResourceV2;

/* Values use Q16.16 so the host viewport is deterministic across the ABI. */
typedef struct GEClassicViewportV2 {
    int32_t scale_x;
    int32_t scale_y;
    int32_t scale_z;
    int32_t translate_x;
    int32_t translate_y;
    int32_t translate_z;
    uint32_t width;
    uint32_t height;
} GEClassicViewportV2;

typedef struct GEClassicReplayFixtureV2 {
    GEAbiHeaderV1 header;
    uint32_t packet_version;
    uint32_t command_count;
    uint32_t list_count;
    uint32_t vertex_count;
    uint32_t vertex_resource_count;
    uint32_t matrix_count;
    uint32_t segment_count;
    uint32_t root_list_handle;
    uint32_t reserved0;
    GEClassicCommandV2 commands[GE_CLASSIC_COMMAND_CAPACITY];
    GEClassicListResourceV2 lists[GE_CLASSIC_LIST_CAPACITY];
    GEVertexV1 vertices[GE_CLASSIC_VERTEX_CAPACITY];
    GEClassicVertexResourceV2 vertex_resources[GE_CLASSIC_VERTEX_RESOURCE_CAPACITY];
    GEClassicMatrixResourceV2 matrices[GE_CLASSIC_MATRIX_CAPACITY];
    GEClassicSegmentResourceV2 segments[GE_CLASSIC_SEGMENT_CAPACITY];
    GEClassicViewportV2 viewport;
} GEClassicReplayFixtureV2;

typedef struct GEClassicAssetBlobV2 {
    GEAbiHeaderV1 header;
    uint32_t byte_count;
    uint32_t reserved;
    uint8_t bytes[GE_CLASSIC_ASSET_BLOB_CAPACITY];
} GEClassicAssetBlobV2;

typedef struct GEClassicStateSnapshotV2 {
    uint32_t geometry_mode;
    uint32_t other_mode_h;
    uint32_t other_mode_l;
    uint32_t combine_w0;
    uint32_t combine_w1;
    uint32_t texture_id;
    uint32_t texture_state;
    uint32_t matrix_handle;
    uint32_t list_handle;
    uint32_t command_offset;
    uint32_t list_depth;
    uint32_t material_flags;
    uint64_t state_hash;
} GEClassicStateSnapshotV2;

typedef struct GEClassicTransformSnapshotV2 {
    float modelview[16];
    float projection[16];
    float viewport[8];
    uint64_t transform_hash;
} GEClassicTransformSnapshotV2;

typedef struct GEClassicClipVertexV2 {
    float x;
    float y;
    float z;
    float w;
    uint8_t r;
    uint8_t g;
    uint8_t b;
    uint8_t a;
    uint32_t source_vertex;
} GEClassicClipVertexV2;

typedef struct GEClassicTriangleV2 {
    uint16_t a;
    uint16_t b;
    uint16_t c;
    uint16_t reserved;
} GEClassicTriangleV2;

typedef struct GEClassicDrawPacketV2 {
    GEAbiHeaderV1 header;
    uint32_t packet_version;
    uint32_t source_list_handle;
    uint32_t source_command_offset;
    uint32_t list_depth;
    uint32_t material_flags;
    uint32_t vertex_count;
    uint32_t triangle_count;
    uint64_t packet_hash;
    GEClassicStateSnapshotV2 state;
    GEClassicTransformSnapshotV2 transform;
    GEClassicClipVertexV2 vertices[GE_CLASSIC_CACHE_CAPACITY];
    GEClassicTriangleV2 triangles[GE_CLASSIC_TRIANGLE_CAPACITY];
} GEClassicDrawPacketV2;

typedef struct GEClassicReplayResultV2 {
    GEAbiHeaderV1 header;
    GEStatusV1 status;
    uint32_t reserved;
    uint32_t error_opcode;
    uint32_t error_offset;
    uint32_t error_list_handle;
    uint32_t error_list_depth;
    uint32_t commands_processed;
    uint32_t list_enters;
    uint32_t list_returns;
    uint32_t draw_count;
    uint32_t vertex_count;
    uint32_t triangle_count;
    uint64_t packet_hash;
    uint64_t event_hash;
    uint64_t state_hash;
    GEClassicDrawPacketV2 draws[GE_CLASSIC_DRAW_CAPACITY];
} GEClassicReplayResultV2;

/* Pure value-only entry points.  The C implementation copies all input data. */
GEClassicReplayFixtureV2 ge_classic_nested_fixture(void);
GEClassicReplayResultV2 ge_classic_replay_fixture(GEClassicReplayFixtureV2 fixture);
GEClassicReplayResultV2 ge_classic_replay_prop_blob(GEClassicAssetBlobV2 blob);

#if defined(__cplusplus)
#define GE_CLASSIC_STATIC_ASSERT(condition, message) static_assert((condition), message)
#else
#define GE_CLASSIC_STATIC_ASSERT(condition, message) _Static_assert((condition), message)
#endif

GE_CLASSIC_STATIC_ASSERT(sizeof(GEClassicCommandV2) == 8u, "GEClassicCommandV2 layout drift");
GE_CLASSIC_STATIC_ASSERT(sizeof(GEClassicListResourceV2) == 16u, "GEClassicListResourceV2 layout drift");
GE_CLASSIC_STATIC_ASSERT(sizeof(GEClassicVertexResourceV2) == 16u, "GEClassicVertexResourceV2 layout drift");
GE_CLASSIC_STATIC_ASSERT(sizeof(GEClassicMatrixResourceV2) == 68u, "GEClassicMatrixResourceV2 layout drift");
GE_CLASSIC_STATIC_ASSERT(sizeof(GEClassicSegmentResourceV2) == 16u, "GEClassicSegmentResourceV2 layout drift");
GE_CLASSIC_STATIC_ASSERT(sizeof(GEClassicViewportV2) == 32u, "GEClassicViewportV2 layout drift");
GE_CLASSIC_STATIC_ASSERT(sizeof(GEClassicAssetBlobV2) == 2064u, "GEClassicAssetBlobV2 layout drift");
GE_CLASSIC_STATIC_ASSERT(sizeof(GEClassicStateSnapshotV2) == 56u, "GEClassicStateSnapshotV2 layout drift");
GE_CLASSIC_STATIC_ASSERT(sizeof(GEClassicTransformSnapshotV2) == 168u, "GEClassicTransformSnapshotV2 layout drift");
GE_CLASSIC_STATIC_ASSERT(sizeof(GEClassicClipVertexV2) == 24u, "GEClassicClipVertexV2 layout drift");
GE_CLASSIC_STATIC_ASSERT(sizeof(GEClassicTriangleV2) == 8u, "GEClassicTriangleV2 layout drift");

#undef GE_CLASSIC_STATIC_ASSERT

#endif /* GE_CLASSIC_REPLAY_H */
