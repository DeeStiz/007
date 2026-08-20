#ifndef GE_STAGE_V5_H
#define GE_STAGE_V5_H

/*
 * Native stage catalog and bounded asset-boundary primitives.
 *
 * This is a preparation seam for the source-derived RAMROM stage route.  The
 * catalog contains source identities and byte ranges only; it never contains
 * a host path, a ROM pointer, an N64 address, or a retained byte buffer.  All
 * input bytes are borrowed for the duration of one call.  Stage execution,
 * streaming, and gameplay remain explicit STUB(M24/M25/M26) boundaries until
 * their native owners are implemented.
 */

#include <stdint.h>

#include "ge_native_foundation.h"

#ifdef __cplusplus
extern "C" {
#endif

#define GE_STAGE_V5_CONTRACT_VERSION ((uint32_t)5u)
#define GE_STAGE_V5_RECORD_VERSION ((uint32_t)1u)

#define GE_STAGE_V5_STAGE_COUNT ((uint32_t)7u)
#define GE_STAGE_V5_RESOURCE_COUNT ((uint32_t)3u)
#define GE_STAGE_V5_RESOURCE_PACKET_COUNT \
    (GE_STAGE_V5_STAGE_COUNT * GE_STAGE_V5_RESOURCE_COUNT)

#define GE_STAGE_V5_STAGE_NAME_BYTES ((uint32_t)24u)
#define GE_STAGE_V5_RESOURCE_NAME_BYTES ((uint32_t)48u)

#define GE_STAGE_V5_RESOURCE_BACKGROUND ((uint32_t)1u)
#define GE_STAGE_V5_RESOURCE_STAN ((uint32_t)2u)
#define GE_STAGE_V5_RESOURCE_SETUP ((uint32_t)3u)
#define GE_STAGE_V5_RESOURCE_MAX GE_STAGE_V5_RESOURCE_SETUP

#define GE_STAGE_V5_COMPRESSION_NONE ((uint32_t)0u)
#define GE_STAGE_V5_COMPRESSION_1172 ((uint32_t)1u)
#define GE_STAGE_V5_COMPRESSION_MAX GE_STAGE_V5_COMPRESSION_1172

#define GE_STAGE_V5_RESOURCE_FLAG_EXTERNAL ((uint32_t)1u << 0)
#define GE_STAGE_V5_RESOURCE_FLAG_SOURCE_SIZE ((uint32_t)1u << 1)
#define GE_STAGE_V5_RESOURCE_FLAG_DECODED_SIZE ((uint32_t)1u << 2)
#define GE_STAGE_V5_RESOURCE_FLAG_NO_RUNTIME_ROM ((uint32_t)1u << 3)
#define GE_STAGE_V5_RESOURCE_FLAG_MASK ((uint32_t)0x0fu)

#define GE_STAGE_V5_ENTRY_FLAG_RAMROM_REQUIRED ((uint32_t)1u << 0)
#define GE_STAGE_V5_ENTRY_FLAG_NATIVE_LOADER_PENDING ((uint32_t)1u << 1)
#define GE_STAGE_V5_ENTRY_FLAG_GAMEPLAY_PENDING ((uint32_t)1u << 2)
#define GE_STAGE_V5_ENTRY_FLAG_MASK ((uint32_t)0x07u)

#define GE_STAGE_V5_1172_PREFIX_BYTES ((uint32_t)2u)
#define GE_STAGE_V5_1172_MAGIC0 ((uint8_t)0x11u)
#define GE_STAGE_V5_1172_MAGIC1 ((uint8_t)0x72u)

#define GE_STAGE_V5_DIAG_NONE ((uint32_t)0u)
#define GE_STAGE_V5_DIAG_ARGUMENT ((uint32_t)1u)
#define GE_STAGE_V5_DIAG_1172 ((uint32_t)2u)
#define GE_STAGE_V5_DIAG_RANGE ((uint32_t)3u)
#define GE_STAGE_V5_DIAG_STUB ((uint32_t)4u)
#define GE_STAGE_V5_DIAG_COPY_OUT ((uint32_t)5u)
#define GE_STAGE_V5_DIAG_VIEW ((uint32_t)6u)
#define GE_STAGE_V5_DIAG_BACKGROUND ((uint32_t)7u)
#define GE_STAGE_V5_DIAG_ROOM ((uint32_t)8u)
#define GE_STAGE_V5_DIAG_OFFSET ((uint32_t)9u)

#define GE_STAGE_V5_DIAG_FLAG_STUB ((uint32_t)1u << 0)
#define GE_STAGE_V5_DIAG_FLAG_RECOVERABLE ((uint32_t)1u << 1)
#define GE_STAGE_V5_DIAG_FLAG_MASK ((uint32_t)0x03u)

#define GE_STAGE_V5_PACKET_FLAG_METADATA_ONLY ((uint32_t)1u << 0)
#define GE_STAGE_V5_PACKET_FLAG_NO_PAYLOAD ((uint32_t)1u << 1)
#define GE_STAGE_V5_PACKET_FLAG_MASK ((uint32_t)0x03u)

#define GE_STAGE_V5_STUB_M24 ((uint32_t)24u)
#define GE_STAGE_V5_STUB_M25 ((uint32_t)25u)
#define GE_STAGE_V5_STUB_M26 ((uint32_t)26u)
#define GE_STAGE_V5_STUB_M27 ((uint32_t)27u)

/* The source bg_all_p linker output is a big-endian segment-0x0f byte
   stream.  These constants describe only the value layout; no host pointer
   or N64 address is exposed by the native ABI. */
#define GE_STAGE_V5_BG_HEADER_BYTES ((uint32_t)20u)
#define GE_STAGE_V5_BG_ROOM_RECORD_BYTES ((uint32_t)24u)
#define GE_STAGE_V5_BG_SEGMENT_TAG ((uint32_t)0x0f000000u)
#define GE_STAGE_V5_BG_SEGMENT_MASK ((uint32_t)0xff000000u)
#define GE_STAGE_V5_BG_LOCAL_MASK ((uint32_t)0x00ffffffu)
#define GE_STAGE_V5_BG_MAX_ROOMS ((uint32_t)4096u)

#define GE_STAGE_V5_BG_FLAG_PORTAL_OFFSET ((uint32_t)1u << 0)
#define GE_STAGE_V5_BG_FLAG_VISIBILITY_OFFSET ((uint32_t)1u << 1)
#define GE_STAGE_V5_BG_FLAG_FIRST_PAYLOAD ((uint32_t)1u << 2)
#define GE_STAGE_V5_BG_FLAG_ROOM_SENTINEL ((uint32_t)1u << 3)
#define GE_STAGE_V5_BG_FLAG_OFFSETS_MONOTONIC ((uint32_t)1u << 4)
#define GE_STAGE_V5_BG_FLAG_MASK ((uint32_t)0x1fu)

#define GE_STAGE_V5_BG_ROOM_FLAG_POINT ((uint32_t)1u << 0)
#define GE_STAGE_V5_BG_ROOM_FLAG_PRIMARY ((uint32_t)1u << 1)
#define GE_STAGE_V5_BG_ROOM_FLAG_SECONDARY ((uint32_t)1u << 2)
#define GE_STAGE_V5_BG_ROOM_FLAG_MASK ((uint32_t)0x07u)

#define GE_STAGE_V5_HANDLE(stage_id, resource_kind) \
    ((((uint32_t)(stage_id) & UINT32_C(0xff)) << 24) | \
     (((uint32_t)(resource_kind) & UINT32_C(0xff)) << 16) | UINT32_C(1))

typedef struct GEStageDiagnosticV5 {
    uint32_t version;
    uint32_t code;
    uint32_t flags;
    uint32_t milestone;
    uint32_t stage_id;
    uint32_t resource_kind;
    uint32_t byte_offset;
    uint32_t detail0;
    uint32_t detail1;
    char message[96];
} GEStageDiagnosticV5;

typedef struct GEStageResourceV5 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t stage_id;
    uint32_t resource_kind;
    uint32_t compression;
    uint32_t flags;
    uint32_t asset_handle;
    uint32_t source_offset;
    uint32_t source_bytes;
    uint32_t decoded_bytes;
    char resource_name[GE_STAGE_V5_RESOURCE_NAME_BYTES];
    uint32_t reserved0;
    uint32_t reserved1;
} GEStageResourceV5;

typedef struct GEStageCatalogEntryV5 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t stage_id;
    uint32_t flags;
    uint32_t demo_mask;
    char stage_name[GE_STAGE_V5_STAGE_NAME_BYTES];
    GEStageResourceV5 background;
    GEStageResourceV5 stan;
    GEStageResourceV5 setup;
} GEStageCatalogEntryV5;

typedef struct GEStage1172InfoV5 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t source_bytes;
    uint32_t prefix_bytes;
    uint32_t compressed_payload_bytes;
    uint32_t expected_decoded_bytes;
    uint32_t reserved0;
    uint32_t reserved1;
    uint64_t source_hash;
} GEStage1172InfoV5;

typedef struct GEStageAssetViewV5 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t stage_id;
    uint32_t resource_kind;
    uint32_t compression;
    uint32_t asset_handle;
    uint32_t source_bytes;
    uint32_t decoded_bytes;
    uint32_t supplied_bytes;
    uint32_t flags;
    uint64_t source_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GEStageAssetViewV5;

/* A deterministic copy-out record.  The record carries metadata and the
   logical source name only; payload bytes remain caller-owned and are never
   embedded in or retained by this ABI. */
typedef struct GEStageResourcePacketV5 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t packet_index;
    uint32_t stage_id;
    uint32_t resource_kind;
    uint32_t asset_handle;
    uint32_t compression;
    uint32_t flags;
    uint32_t source_offset;
    uint32_t source_bytes;
    uint32_t decoded_bytes;
    uint32_t name_bytes;
    char resource_name[GE_STAGE_V5_RESOURCE_NAME_BYTES];
    uint64_t metadata_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GEStageResourcePacketV5;

/* Metadata view after a caller has assigned a decoded arena range.  The
   arena is identified by fixed-width offsets only; this record stores no
   pointer and does not claim that stage execution or rendering exists. */
typedef struct GEStageResourceViewV5 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t stage_id;
    uint32_t resource_kind;
    uint32_t asset_handle;
    uint32_t compression;
    uint32_t flags;
    uint32_t decoded_base_offset;
    uint32_t decoded_bytes;
    uint32_t source_offset;
    uint32_t source_bytes;
    uint64_t metadata_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GEStageResourceViewV5;

/* Source-derived background header/table summary.  The five source header
   words and all segmented offsets are retained as uint32_t values.  The
   local offsets are bounded file offsets, not pointers. */
typedef struct GEStageBackgroundV5 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t stage_id;
    uint32_t source_bytes;
    uint32_t header_word0;
    uint32_t room_table_segmented_offset;
    uint32_t portal_table_segmented_offset;
    uint32_t visibility_segmented_offset;
    uint32_t header_word4;
    uint32_t room_table_offset;
    uint32_t room_record_bytes;
    uint32_t room_count;
    uint32_t sentinel_record_offset;
    uint32_t first_payload_offset;
    uint32_t point_offset_count;
    uint32_t primary_offset_count;
    uint32_t secondary_offset_count;
    uint32_t flags;
    uint64_t source_hash;
    uint64_t room_table_hash;
    uint64_t metadata_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GEStageBackgroundV5;

/* One room-table row copied out as fixed-width values.  Position words are
   intentionally kept as their source bit patterns rather than host floats.
   A zero offset means that source resource is absent for this room. */
typedef struct GEStageBackgroundRoomV5 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t stage_id;
    uint32_t room_index;
    uint32_t source_record_offset;
    uint32_t point_segmented_offset;
    uint32_t primary_segmented_offset;
    uint32_t secondary_segmented_offset;
    uint32_t point_offset;
    uint32_t point_bytes;
    uint32_t primary_offset;
    uint32_t primary_bytes;
    uint32_t secondary_offset;
    uint32_t secondary_bytes;
    uint32_t position_x_bits;
    uint32_t position_y_bits;
    uint32_t position_z_bits;
    uint32_t flags;
    uint64_t metadata_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GEStageBackgroundRoomV5;

/* Descriptive aliases for callers that want to emphasize the source header
   or room-record role.  They remain the same fixed-width records. */
typedef GEStageBackgroundV5 GEStageBackgroundHeaderV5;
typedef GEStageBackgroundRoomV5 GEStageRoomV5;

/* The callback is a local decompressor seam, not a stored ABI value.  It
   receives the bytes after the two-byte 1172 marker and must report exactly
   the expected decoded count.  The callback may be backed by Apple's
   Compression framework or another host-owned implementation. */
typedef GEStatusV1 (*GEStageInflateV5)(const uint8_t *compressed_bytes,
                                       uint32_t compressed_byte_count,
                                       uint8_t *decoded_bytes,
                                       uint32_t decoded_capacity,
                                       uint32_t *decoded_byte_count);

uint32_t ge_stage_v5_catalog_count(void);
GEStatusV1 ge_stage_v5_catalog_entry(uint32_t index,
                                     GEStageCatalogEntryV5 *out_entry);
GEStatusV1 ge_stage_v5_find_stage(uint32_t stage_id,
                                  GEStageCatalogEntryV5 *out_entry);

uint32_t ge_stage_v5_resource_handle(uint32_t stage_id,
                                     uint32_t resource_kind);
GEStatusV1 ge_stage_v5_validate_resource(const GEStageResourceV5 *resource);
GEStatusV1 ge_stage_v5_validate_entry(const GEStageCatalogEntryV5 *entry);

uint32_t ge_stage_v5_resource_packet_count(void);
GEStatusV1 ge_stage_v5_resource_packet(uint32_t packet_index,
                                       GEStageResourcePacketV5 *out_packet);
GEStatusV1 ge_stage_v5_copy_resource_packets(
    uint32_t first_packet,
    uint32_t packet_capacity,
    GEStageResourcePacketV5 *out_packets,
    uint32_t *out_packet_count,
    GEStageDiagnosticV5 *out_diagnostic);

GEStatusV1 ge_stage_v5_validate_resource_view(
    const GEStageResourceViewV5 *view);
GEStatusV1 ge_stage_v5_make_resource_view(
    const GEStageResourceV5 *resource,
    uint32_t decoded_base_offset,
    uint32_t decoded_arena_bytes,
    GEStageResourceViewV5 *out_view,
    GEStageDiagnosticV5 *out_diagnostic);

GEStatusV1 ge_stage_v5_validate_asset(const GEStageResourceV5 *resource,
                                      const uint8_t *asset_bytes,
                                      uint32_t asset_byte_count,
                                      GEStageAssetViewV5 *out_view);

GEStatusV1 ge_stage_v5_read_1172(const uint8_t *asset_bytes,
                                 uint32_t asset_byte_count,
                                 uint32_t expected_decoded_bytes,
                                 GEStage1172InfoV5 *out_info);

GEStatusV1 ge_stage_v5_decompress_1172(const GEStageResourceV5 *resource,
                                       const uint8_t *asset_bytes,
                                       uint32_t asset_byte_count,
                                       uint8_t *decoded_bytes,
                                       uint32_t decoded_capacity,
                                       uint32_t *decoded_byte_count,
                                       GEStageInflateV5 inflate);

/* Rebase a checked file-local range into an enclosing bounded byte stream. */
GEStatusV1 ge_stage_v5_rebase_local_range(uint32_t file_base_offset,
                                          uint32_t file_byte_count,
                                          uint32_t local_offset,
                                          uint32_t local_byte_count,
                                          uint32_t *out_global_offset);

GEStatusV1 ge_stage_v5_rebase_resource_range(const GEStageResourceV5 *resource,
                                             uint32_t local_offset,
                                             uint32_t local_byte_count,
                                             uint32_t *out_source_offset);

/* Source stage files are big-endian.  These bounded reads operate only on a
   caller-owned prepared asset buffer and never retain its address. */
GEStatusV1 ge_stage_v5_read_be16(const uint8_t *bytes,
                                 uint32_t byte_count,
                                 uint32_t local_offset,
                                 uint16_t *out_value);
GEStatusV1 ge_stage_v5_read_be32(const uint8_t *bytes,
                                 uint32_t byte_count,
                                 uint32_t local_offset,
                                 uint32_t *out_value);

/* Explicitly report the native systems that are not implemented by this
   foundation lane.  Stage assets remain usable as prepared external input,
   but no call here silently pretends to execute a stage or demo. */
GEStatusV1 ge_stage_v5_stub_status(uint32_t milestone,
                                   uint32_t stage_id,
                                   uint32_t resource_kind,
                                   GEStageDiagnosticV5 *out_diagnostic);

/* Parse one prepared, uncompressed bg_all_p asset.  The parser validates the
   source header, room-table sentinel and bounds, segment tags, monotonic
   point/primary/secondary offsets, and raw position words without retaining
   the caller's byte-buffer address. */
GEStatusV1 ge_stage_v5_parse_background(
    const GEStageResourceV5 *resource,
    const uint8_t *asset_bytes,
    uint32_t asset_byte_count,
    GEStageBackgroundV5 *out_background,
    GEStageDiagnosticV5 *out_diagnostic);

GEStatusV1 ge_stage_v5_validate_background(
    const GEStageBackgroundV5 *background);

/* Copy one validated room row, including source-shaped bounded byte ranges.
   This is a pure reparse/copy-out operation; no parser state or input pointer
   is retained between calls. */
GEStatusV1 ge_stage_v5_background_room(
    const GEStageResourceV5 *resource,
    const uint8_t *asset_bytes,
    uint32_t asset_byte_count,
    uint32_t room_index,
    GEStageBackgroundRoomV5 *out_room,
    GEStageDiagnosticV5 *out_diagnostic);

GEStatusV1 ge_stage_v5_validate_background_room(
    const GEStageBackgroundRoomV5 *room);

/* Copy a bounded contiguous room range.  A short destination returns
   GE_STATUS_INVALID_SIZE and reports the copied count for deterministic
   caller-side retry handling. */
GEStatusV1 ge_stage_v5_copy_background_rooms(
    const GEStageResourceV5 *resource,
    const uint8_t *asset_bytes,
    uint32_t asset_byte_count,
    uint32_t first_room,
    uint32_t room_capacity,
    GEStageBackgroundRoomV5 *out_rooms,
    uint32_t *out_room_count,
    GEStageBackgroundV5 *out_background,
    GEStageDiagnosticV5 *out_diagnostic);

#if defined(__cplusplus)
#define GE_STAGE_V5_STATIC_ASSERT(condition, message) \
    static_assert((condition), message)
#else
#define GE_STAGE_V5_STATIC_ASSERT(condition, message) \
    _Static_assert((condition), message)
#endif

GE_STAGE_V5_STATIC_ASSERT(sizeof(GEStageResourceV5) == 100u,
                          "GEStageResourceV5 layout drift");
GE_STAGE_V5_STATIC_ASSERT(sizeof(GEStageCatalogEntryV5) == 348u,
                          "GEStageCatalogEntryV5 layout drift");
GE_STAGE_V5_STATIC_ASSERT(sizeof(GEStage1172InfoV5) == 48u,
                          "GEStage1172InfoV5 layout drift");
GE_STAGE_V5_STATIC_ASSERT(sizeof(GEStageAssetViewV5) == 64u,
                          "GEStageAssetViewV5 layout drift");
GE_STAGE_V5_STATIC_ASSERT(sizeof(GEStageResourcePacketV5) == 120u,
                          "GEStageResourcePacketV5 layout drift");
GE_STAGE_V5_STATIC_ASSERT(sizeof(GEStageResourceViewV5) == 64u,
                          "GEStageResourceViewV5 layout drift");
GE_STAGE_V5_STATIC_ASSERT(sizeof(GEStageBackgroundV5) == 112u,
                          "GEStageBackgroundV5 layout drift");
GE_STAGE_V5_STATIC_ASSERT(sizeof(GEStageBackgroundRoomV5) == 96u,
                          "GEStageBackgroundRoomV5 layout drift");

#undef GE_STAGE_V5_STATIC_ASSERT

#ifdef __cplusplus
}
#endif

#endif /* GE_STAGE_V5_H */
