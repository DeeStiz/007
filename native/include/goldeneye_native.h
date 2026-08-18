#ifndef GOLDENEYE_NATIVE_H
#define GOLDENEYE_NATIVE_H

// M1 deliberately exposes only copied, fixed-width values.  No public record
// contains a pointer, host address, function pointer, Gfx object, or N64 ABI
// type.  The owner thread is captured internally by the C implementation.

#include <stdint.h>
#include "ge_native_foundation.h"

#ifdef __cplusplus
extern "C" {
#endif

#define GE_NATIVE_PACKET_VERSION ((uint32_t)1u)
#define GE_NATIVE_VERTEX_CAPACITY ((uint32_t)3u)
#define GE_NATIVE_COMMAND_CAPACITY ((uint32_t)2u)

typedef struct GEInitRequestV1 {
    GEAbiHeaderV1 header;
    uint32_t flags;
    uint32_t reserved;
} GEInitRequestV1;

typedef struct GEInputSnapshotV1 {
    GEAbiHeaderV1 header;
    uint64_t sequence;
    uint32_t held;
    uint32_t pressed;
    uint32_t released;
    uint32_t reserved;
} GEInputSnapshotV1;

typedef struct GECommandWordsV1 {
    uint32_t w0;
    uint32_t w1;
} GECommandWordsV1;

typedef struct GEFixturePacketV1 {
    GEAbiHeaderV1 header;
    uint32_t packet_version;
    uint32_t vertex_count;
    uint32_t command_count;
    uint32_t reserved0;
    uint64_t packet_hash;
    GEVertexV1 vertices[GE_NATIVE_VERTEX_CAPACITY];
    GECommandWordsV1 commands[GE_NATIVE_COMMAND_CAPACITY];
    uint32_t reserved1;
} GEFixturePacketV1;

typedef struct GEFixtureResultV1 {
    GEAbiHeaderV1 header;
    GEStatusV1 status;
    uint32_t reserved;
    GEFixturePacketV1 packet;
} GEFixtureResultV1;

typedef struct GEFrameResultV1 {
    GEAbiHeaderV1 header;
    GEStatusV1 status;
    uint32_t reserved;
    uint64_t tick;
    uint32_t held;
    uint32_t pressed;
    uint32_t released;
    uint32_t reserved1;
    uint64_t packet_hash;
    uint64_t event_hash;
} GEFrameResultV1;

#define GE_NATIVE_GBI_COMMAND_CAPACITY ((uint32_t)4u)
#define GE_NATIVE_GBI_RESOURCE_CAPACITY ((uint32_t)1u)

typedef struct GEResourceHandleV1 {
    uint32_t handle;
    uint32_t first_vertex;
    uint32_t vertex_count;
    uint32_t reserved;
} GEResourceHandleV1;

typedef struct GEGBIStreamV1 {
    GEAbiHeaderV1 header;
    uint32_t command_count;
    uint32_t resource_count;
    uint32_t reserved0[2];
    GECommandWordsV1 commands[GE_NATIVE_GBI_COMMAND_CAPACITY];
    GEVertexV1 vertices[GE_NATIVE_VERTEX_CAPACITY];
    GEResourceHandleV1 resources[GE_NATIVE_GBI_RESOURCE_CAPACITY];
    uint32_t reserved1;
} GEGBIStreamV1;

typedef struct GEGBINormalizationResultV1 {
    GEAbiHeaderV1 header;
    GEStatusV1 status;
    uint32_t reserved;
    uint32_t error_opcode;
    uint32_t error_offset;
    uint64_t packet_hash;
    uint64_t event_hash;
    GEFixturePacketV1 packet;
} GEGBINormalizationResultV1;

// All lifecycle calls are value-only.  The return records are immutable
// snapshots copied by the caller; C retains no caller-owned memory.
GEStatusV1 ge_native_initialize(GEInitRequestV1 request);
GEFrameResultV1 ge_native_step(GEInputSnapshotV1 input);
GEStatusV1 ge_native_shutdown(void);
GEFixtureResultV1 ge_native_fixture_packet(void);
GEGBIStreamV1 ge_native_gbi_fixture_stream(void);
GEGBINormalizationResultV1 ge_native_normalize_gbi(GEGBIStreamV1 stream);

#if defined(__cplusplus)
#define GE_NATIVE_STATIC_ASSERT(condition, message) static_assert((condition), message)
#else
#define GE_NATIVE_STATIC_ASSERT(condition, message) _Static_assert((condition), message)
#endif

GE_NATIVE_STATIC_ASSERT(sizeof(GEAbiHeaderV1) == 8u, "GEAbiHeaderV1 layout drift");
GE_NATIVE_STATIC_ASSERT(sizeof(GEInitRequestV1) == 16u, "GEInitRequestV1 layout drift");
GE_NATIVE_STATIC_ASSERT(sizeof(GEInputSnapshotV1) == 32u, "GEInputSnapshotV1 layout drift");
GE_NATIVE_STATIC_ASSERT(sizeof(GEVertexV1) == 20u, "GEVertexV1 layout drift");
GE_NATIVE_STATIC_ASSERT(sizeof(GECommandWordsV1) == 8u, "GECommandWordsV1 layout drift");
GE_NATIVE_STATIC_ASSERT(sizeof(GEFixturePacketV1) == 112u, "GEFixturePacketV1 layout drift");
GE_NATIVE_STATIC_ASSERT(sizeof(GEFixtureResultV1) == 128u, "GEFixtureResultV1 layout drift");
GE_NATIVE_STATIC_ASSERT(sizeof(GEFrameResultV1) == 56u, "GEFrameResultV1 layout drift");
GE_NATIVE_STATIC_ASSERT(sizeof(GEResourceHandleV1) == 16u, "GEResourceHandleV1 layout drift");
GE_NATIVE_STATIC_ASSERT(sizeof(GEGBIStreamV1) == 136u, "GEGBIStreamV1 layout drift");
GE_NATIVE_STATIC_ASSERT(sizeof(GEGBINormalizationResultV1) == 152u, "GEGBINormalizationResultV1 layout drift");

#undef GE_NATIVE_STATIC_ASSERT

#include "ge_classic_replay.h"
#include "ge_texture_replay.h"

#ifdef __cplusplus
}
#endif

#endif // GOLDENEYE_NATIVE_H
