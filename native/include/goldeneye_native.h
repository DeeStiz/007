#ifndef GOLDENEYE_NATIVE_H
#define GOLDENEYE_NATIVE_H

// M1 deliberately exposes only copied, fixed-width values.  No public record
// contains a pointer, host address, function pointer, Gfx object, or N64 ABI
// type.  The owner thread is captured internally by the C implementation.

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define GE_NATIVE_ABI_VERSION ((uint32_t)1u)
#define GE_NATIVE_PACKET_VERSION ((uint32_t)1u)
#define GE_NATIVE_VERTEX_CAPACITY ((uint32_t)3u)
#define GE_NATIVE_COMMAND_CAPACITY ((uint32_t)2u)

typedef uint32_t GEStatusV1;

#define GE_STATUS_OK ((GEStatusV1)0u)
#define GE_STATUS_INVALID_VERSION ((GEStatusV1)1u)
#define GE_STATUS_INVALID_SIZE ((GEStatusV1)2u)
#define GE_STATUS_INVALID_ARGUMENT ((GEStatusV1)3u)
#define GE_STATUS_INVALID_STATE ((GEStatusV1)4u)
#define GE_STATUS_WRONG_OWNER_THREAD ((GEStatusV1)5u)
#define GE_STATUS_THREAD_ID_UNAVAILABLE ((GEStatusV1)6u)
#define GE_STATUS_RESERVED_BITS ((GEStatusV1)7u)
#define GE_STATUS_INTERNAL_ERROR ((GEStatusV1)8u)
#define GE_STATUS_UNSUPPORTED_COMMAND ((GEStatusV1)9u)
#define GE_STATUS_MALFORMED_STREAM ((GEStatusV1)10u)
#define GE_STATUS_RESOURCE_NOT_FOUND ((GEStatusV1)11u)
#define GE_STATUS_VERTEX_OUT_OF_RANGE ((GEStatusV1)12u)
#define GE_STATUS_REPLAY_DEPTH ((GEStatusV1)13u)
#define GE_STATUS_REPLAY_BUDGET ((GEStatusV1)14u)
#define GE_STATUS_REPLAY_CYCLE ((GEStatusV1)15u)
#define GE_STATUS_ASSET_MISMATCH ((GEStatusV1)16u)
#define GE_STATUS_MATRIX_STACK ((GEStatusV1)17u)

typedef struct GEAbiHeaderV1 {
    uint32_t abi_version;
    uint32_t struct_size;
} GEAbiHeaderV1;

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

typedef struct GEVertexV1 {
    int16_t x;
    int16_t y;
    int16_t z;
    uint16_t reserved0;
    int16_t s;
    int16_t t;
    uint8_t r;
    uint8_t g;
    uint8_t b;
    uint8_t a;
    uint32_t reserved1;
} GEVertexV1;

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

#ifdef __cplusplus
}
#endif

#endif // GOLDENEYE_NATIVE_H
