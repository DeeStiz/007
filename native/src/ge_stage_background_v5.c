#include "ge_stage_v5.h"

#include <stddef.h>
#include <string.h>

/*
 * The background asset is a source-owned, big-endian byte stream.  This file
 * deliberately keeps the parser stateless: every public operation reparses
 * the caller-owned bytes and copies only fixed-width values into its result.
 * No segmented address is converted to a host pointer.
 */

static const uint64_t GE_STAGE_BG_V5_FNV_OFFSET =
    UINT64_C(1469598103934665603);
static const uint64_t GE_STAGE_BG_V5_FNV_PRIME = UINT64_C(1099511628211);

typedef struct GEStageBackgroundScanV5 {
    uint32_t source_bytes;
    uint32_t header_word0;
    uint32_t room_table_segmented_offset;
    uint32_t portal_table_segmented_offset;
    uint32_t visibility_segmented_offset;
    uint32_t header_word4;
    uint32_t room_table_offset;
    uint32_t portal_table_offset;
    uint32_t visibility_offset;
    uint32_t room_table_end;
    uint32_t sentinel_record_offset;
    uint32_t first_payload_offset;
    uint32_t room_count;
    uint32_t offset_count[3];
    uint32_t flags;
    uint64_t source_hash;
    uint64_t room_table_hash;
} GEStageBackgroundScanV5;

static uint64_t ge_stage_bg_v5_hash_bytes(uint64_t hash,
                                          const uint8_t *bytes,
                                          uint32_t byte_count)
{
    if (bytes == NULL && byte_count != 0u) {
        return 0u;
    }
    for (uint32_t index = 0u; index < byte_count; index++) {
        hash ^= (uint64_t)bytes[index];
        hash *= GE_STAGE_BG_V5_FNV_PRIME;
    }
    return hash;
}

static uint64_t ge_stage_bg_v5_hash_u32(uint64_t hash, uint32_t value)
{
    const uint8_t bytes[4] = {
        (uint8_t)(value & UINT32_C(0xff)),
        (uint8_t)((value >> 8) & UINT32_C(0xff)),
        (uint8_t)((value >> 16) & UINT32_C(0xff)),
        (uint8_t)(value >> 24),
    };
    return ge_stage_bg_v5_hash_bytes(hash, bytes, (uint32_t)sizeof(bytes));
}

static uint64_t ge_stage_bg_v5_hash_u64(uint64_t hash, uint64_t value)
{
    hash = ge_stage_bg_v5_hash_u32(hash, (uint32_t)value);
    return ge_stage_bg_v5_hash_u32(hash, (uint32_t)(value >> 32));
}

static uint64_t ge_stage_bg_v5_hash_source(const uint8_t *bytes,
                                           uint32_t byte_count)
{
    return ge_stage_bg_v5_hash_bytes(GE_STAGE_BG_V5_FNV_OFFSET,
                                     bytes,
                                     byte_count);
}

static int ge_stage_bg_v5_add_overflow(uint32_t left,
                                       uint32_t right,
                                       uint32_t *out_value)
{
    if (out_value == NULL || left > UINT32_MAX - right) {
        return 1;
    }
    *out_value = left + right;
    return 0;
}

static void ge_stage_bg_v5_copy_message(char *destination,
                                        uint32_t destination_capacity,
                                        const char *source)
{
    if (destination == NULL || destination_capacity == 0u) {
        return;
    }
    uint32_t index = 0u;
    if (source != NULL) {
        while (index + 1u < destination_capacity && source[index] != '\0') {
            destination[index] = source[index];
            index++;
        }
    }
    destination[index] = '\0';
    for (index++; index < destination_capacity; index++) {
        destination[index] = '\0';
    }
}

static GEStatusV1 ge_stage_bg_v5_diagnostic(
    GEStageDiagnosticV5 *diagnostic,
    uint32_t code,
    uint32_t flags,
    uint32_t stage_id,
    uint32_t byte_offset,
    uint32_t detail0,
    uint32_t detail1,
    const char *message,
    GEStatusV1 status)
{
    if (diagnostic != NULL) {
        memset(diagnostic, 0, sizeof(*diagnostic));
        diagnostic->version = GE_STAGE_V5_CONTRACT_VERSION;
        diagnostic->code = code;
        diagnostic->flags = flags;
        diagnostic->stage_id = stage_id;
        diagnostic->resource_kind = GE_STAGE_V5_RESOURCE_BACKGROUND;
        diagnostic->byte_offset = byte_offset;
        diagnostic->detail0 = detail0;
        diagnostic->detail1 = detail1;
        ge_stage_bg_v5_copy_message(diagnostic->message,
                                     (uint32_t)sizeof(diagnostic->message),
                                     message);
    }
    return status;
}

static GEStatusV1 ge_stage_bg_v5_read_be32(const uint8_t *bytes,
                                           uint32_t byte_count,
                                           uint32_t offset,
                                           uint32_t *out_value)
{
    if (bytes == NULL || out_value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (offset > byte_count || byte_count - offset < 4u) {
        return GE_STATUS_INVALID_SIZE;
    }
    *out_value = ((uint32_t)bytes[offset] << 24) |
                 ((uint32_t)bytes[offset + 1u] << 16) |
                 ((uint32_t)bytes[offset + 2u] << 8) |
                 (uint32_t)bytes[offset + 3u];
    return GE_STATUS_OK;
}

static int ge_stage_bg_v5_zero_record(const uint32_t words[6])
{
    return words[0] == 0u && words[1] == 0u && words[2] == 0u &&
           words[3] == 0u && words[4] == 0u && words[5] == 0u;
}

static GEStatusV1 ge_stage_bg_v5_segmented_local(uint32_t segmented_offset,
                                                  uint32_t byte_count,
                                                  uint32_t *out_local)
{
    if (out_local == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (segmented_offset == 0u ||
        (segmented_offset & GE_STAGE_V5_BG_SEGMENT_MASK) !=
            GE_STAGE_V5_BG_SEGMENT_TAG) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    uint32_t local_offset = segmented_offset & GE_STAGE_V5_BG_LOCAL_MASK;
    if ((local_offset & 3u) != 0u || local_offset >= byte_count) {
        return GE_STATUS_INVALID_SIZE;
    }
    *out_local = local_offset;
    return GE_STATUS_OK;
}

static GEStatusV1 ge_stage_bg_v5_validate_resource(
    const GEStageResourceV5 *resource,
    uint32_t asset_byte_count,
    uint32_t *out_stage_id,
    GEStageDiagnosticV5 *out_diagnostic)
{
    if (resource == NULL) {
        return ge_stage_bg_v5_diagnostic(
            out_diagnostic,
            GE_STAGE_V5_DIAG_ARGUMENT,
            GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
            0u,
            0u,
            0u,
            0u,
            "background parser requires a resource",
            GE_STATUS_INVALID_ARGUMENT);
    }
    GEStatusV1 status = ge_stage_v5_validate_resource(resource);
    if (status != GE_STATUS_OK) {
        return ge_stage_bg_v5_diagnostic(
            out_diagnostic,
            GE_STAGE_V5_DIAG_BACKGROUND,
            GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
            resource->stage_id,
            0u,
            status,
            0u,
            "background resource metadata failed validation",
            status);
    }
    if (resource->resource_kind != GE_STAGE_V5_RESOURCE_BACKGROUND ||
        resource->compression != GE_STAGE_V5_COMPRESSION_NONE) {
        return ge_stage_bg_v5_diagnostic(
            out_diagnostic,
            GE_STAGE_V5_DIAG_BACKGROUND,
            GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
            resource->stage_id,
            0u,
            resource->resource_kind,
            resource->compression,
            "background parser requires an uncompressed background resource",
            GE_STATUS_UNSUPPORTED_COMMAND);
    }
    if (asset_byte_count != resource->source_bytes ||
        asset_byte_count != resource->decoded_bytes) {
        return ge_stage_bg_v5_diagnostic(
            out_diagnostic,
            GE_STAGE_V5_DIAG_RANGE,
            GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
            resource->stage_id,
            0u,
            resource->source_bytes,
            asset_byte_count,
            "background byte count does not match prepared resource",
            GE_STATUS_ASSET_MISMATCH);
    }
    if (out_stage_id != NULL) {
        *out_stage_id = resource->stage_id;
    }
    return GE_STATUS_OK;
}

static GEStatusV1 ge_stage_bg_v5_read_room(const uint8_t *bytes,
                                           uint32_t byte_count,
                                           uint32_t offset,
                                           uint32_t words[6])
{
    if (bytes == NULL || words == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (offset > byte_count || byte_count - offset <
            GE_STAGE_V5_BG_ROOM_RECORD_BYTES) {
        return GE_STATUS_INVALID_SIZE;
    }
    for (uint32_t index = 0u; index < 6u; index++) {
        GEStatusV1 status = ge_stage_bg_v5_read_be32(
            bytes,
            byte_count,
            offset + index * 4u,
            &words[index]);
        if (status != GE_STATUS_OK) {
            return status;
        }
    }
    return GE_STATUS_OK;
}

static GEStatusV1 ge_stage_bg_v5_scan(
    const GEStageResourceV5 *resource,
    const uint8_t *asset_bytes,
    uint32_t asset_byte_count,
    GEStageBackgroundScanV5 *out_scan,
    GEStageDiagnosticV5 *out_diagnostic)
{
    if (asset_bytes == NULL || out_scan == NULL) {
        return ge_stage_bg_v5_diagnostic(
            out_diagnostic,
            GE_STAGE_V5_DIAG_ARGUMENT,
            GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
            resource == NULL ? 0u : resource->stage_id,
            0u,
            0u,
            0u,
            "background parser requires bytes and output",
            GE_STATUS_INVALID_ARGUMENT);
    }

    uint32_t stage_id = 0u;
    GEStatusV1 status = ge_stage_bg_v5_validate_resource(
        resource,
        asset_byte_count,
        &stage_id,
        out_diagnostic);
    if (status != GE_STATUS_OK) {
        return status;
    }

    memset(out_scan, 0, sizeof(*out_scan));
    out_scan->source_bytes = asset_byte_count;
    uint32_t header_words[5];
    for (uint32_t index = 0u; index < 5u; index++) {
        status = ge_stage_bg_v5_read_be32(asset_bytes,
                                          asset_byte_count,
                                          index * 4u,
                                          &header_words[index]);
        if (status != GE_STATUS_OK) {
            return ge_stage_bg_v5_diagnostic(
                out_diagnostic,
                GE_STAGE_V5_DIAG_BACKGROUND,
                GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
                stage_id,
                index * 4u,
                GE_STAGE_V5_BG_HEADER_BYTES,
                asset_byte_count,
                "background header is truncated",
                status);
        }
    }

    uint32_t room_table_offset = 0u;
    uint32_t portal_table_offset = 0u;
    uint32_t visibility_offset = 0u;
    status = ge_stage_bg_v5_segmented_local(header_words[1],
                                            asset_byte_count,
                                            &room_table_offset);
    if (status == GE_STATUS_OK) {
        status = ge_stage_bg_v5_segmented_local(header_words[2],
                                                asset_byte_count,
                                                &portal_table_offset);
    }
    if (status == GE_STATUS_OK) {
        status = ge_stage_bg_v5_segmented_local(header_words[3],
                                                asset_byte_count,
                                                &visibility_offset);
    }
    if (status != GE_STATUS_OK || header_words[0] != 0u ||
        header_words[4] != 0u || room_table_offset <
            GE_STAGE_V5_BG_HEADER_BYTES) {
        return ge_stage_bg_v5_diagnostic(
            out_diagnostic,
            GE_STAGE_V5_DIAG_BACKGROUND,
            GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
            stage_id,
            0u,
            header_words[0],
            header_words[4],
            "background header has invalid reserved or segmented fields",
            status == GE_STATUS_OK ? GE_STATUS_MALFORMED_STREAM : status);
    }

    uint32_t first_words[6];
    status = ge_stage_bg_v5_read_room(asset_bytes,
                                      asset_byte_count,
                                      room_table_offset,
                                      first_words);
    if (status != GE_STATUS_OK) {
        return ge_stage_bg_v5_diagnostic(
            out_diagnostic,
            GE_STAGE_V5_DIAG_ROOM,
            GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
            stage_id,
            room_table_offset,
            GE_STAGE_V5_BG_ROOM_RECORD_BYTES,
            asset_byte_count,
            "background room table has no first record",
            status);
    }
    if (!ge_stage_bg_v5_zero_record(first_words)) {
        return ge_stage_bg_v5_diagnostic(
            out_diagnostic,
            GE_STAGE_V5_DIAG_ROOM,
            GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
            stage_id,
            room_table_offset,
            0u,
            0u,
            "background room table is missing its leading null record",
            GE_STATUS_MALFORMED_STREAM);
    }

    uint32_t previous_offsets[3] = {0u, 0u, 0u};
    uint32_t seen_offsets[3] = {0u, 0u, 0u};
    uint32_t offset = 0u;
    if (ge_stage_bg_v5_add_overflow(room_table_offset,
                                    GE_STAGE_V5_BG_ROOM_RECORD_BYTES,
                                    &offset)) {
        return ge_stage_bg_v5_diagnostic(
            out_diagnostic,
            GE_STAGE_V5_DIAG_ROOM,
            GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
            stage_id,
            room_table_offset,
            GE_STAGE_V5_BG_ROOM_RECORD_BYTES,
            asset_byte_count,
            "background room table start overflowed",
            GE_STATUS_INVALID_SIZE);
    }
    uint32_t first_payload_offset = UINT32_MAX;
    uint32_t room_count = 0u;
    uint32_t sentinel_record_offset = 0u;
    uint32_t flags = 0u;

    for (;;) {
        uint32_t words[6];
        status = ge_stage_bg_v5_read_room(asset_bytes,
                                          asset_byte_count,
                                          offset,
                                          words);
        if (status != GE_STATUS_OK) {
            return ge_stage_bg_v5_diagnostic(
                out_diagnostic,
                GE_STAGE_V5_DIAG_ROOM,
                GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
                stage_id,
                offset,
                room_count,
                GE_STAGE_V5_BG_MAX_ROOMS,
                "background room table is truncated before its sentinel",
                status);
        }
        if (ge_stage_bg_v5_zero_record(words)) {
            sentinel_record_offset = offset;
            flags |= GE_STAGE_V5_BG_FLAG_ROOM_SENTINEL;
            break;
        }
        if (room_count >= GE_STAGE_V5_BG_MAX_ROOMS) {
            return ge_stage_bg_v5_diagnostic(
                out_diagnostic,
                GE_STAGE_V5_DIAG_ROOM,
                GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
                stage_id,
                offset,
                room_count,
                GE_STAGE_V5_BG_MAX_ROOMS,
                "background room count exceeds its bounded maximum",
                GE_STATUS_INVALID_SIZE);
        }

        for (uint32_t kind = 0u; kind < 3u; kind++) {
            uint32_t segmented_offset = words[kind];
            if (segmented_offset == 0u) {
                continue;
            }
            uint32_t local_offset = 0u;
            status = ge_stage_bg_v5_segmented_local(segmented_offset,
                                                    asset_byte_count,
                                                    &local_offset);
            if (status != GE_STATUS_OK) {
                return ge_stage_bg_v5_diagnostic(
                    out_diagnostic,
                    GE_STAGE_V5_DIAG_OFFSET,
                    GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
                    stage_id,
                    offset + kind * 4u,
                    segmented_offset,
                    asset_byte_count,
                    "background room contains an invalid segmented offset",
                    status);
            }
            if (seen_offsets[kind] != 0u &&
                local_offset < previous_offsets[kind]) {
                return ge_stage_bg_v5_diagnostic(
                    out_diagnostic,
                    GE_STAGE_V5_DIAG_OFFSET,
                    GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
                    stage_id,
                    offset + kind * 4u,
                    previous_offsets[kind],
                    local_offset,
                    "background room offsets are not monotonic",
                    GE_STATUS_MALFORMED_STREAM);
            }
            previous_offsets[kind] = local_offset;
            seen_offsets[kind] = 1u;
            out_scan->offset_count[kind]++;
            if (local_offset < first_payload_offset) {
                first_payload_offset = local_offset;
            }
        }

        room_count++;
        if (ge_stage_bg_v5_add_overflow(
                offset,
                GE_STAGE_V5_BG_ROOM_RECORD_BYTES,
                &offset)) {
            return ge_stage_bg_v5_diagnostic(
                out_diagnostic,
                GE_STAGE_V5_DIAG_ROOM,
                GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
                stage_id,
                offset,
                0u,
                0u,
                "background room table offset overflowed",
                GE_STATUS_INVALID_SIZE);
        }
    }

    if (room_count == 0u) {
        return ge_stage_bg_v5_diagnostic(
            out_diagnostic,
            GE_STAGE_V5_DIAG_ROOM,
            GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
            stage_id,
            sentinel_record_offset,
            0u,
            0u,
            "background room table contains no rooms",
            GE_STATUS_MALFORMED_STREAM);
    }
    uint32_t room_table_end = 0u;
    if (ge_stage_bg_v5_add_overflow(
            sentinel_record_offset,
            GE_STAGE_V5_BG_ROOM_RECORD_BYTES,
            &room_table_end) || room_table_end > asset_byte_count ||
        portal_table_offset < room_table_end ||
        visibility_offset < room_table_end ||
        first_payload_offset == UINT32_MAX ||
        first_payload_offset < room_table_end) {
        return ge_stage_bg_v5_diagnostic(
            out_diagnostic,
            GE_STAGE_V5_DIAG_OFFSET,
            GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
            stage_id,
            room_table_end,
            room_table_end,
            first_payload_offset,
            "background table or payload range is outside the asset",
            GE_STATUS_INVALID_SIZE);
    }

    /* Recheck every pointer after the sentinel is known, so no room can point
       into the header or room table itself. */
    offset = room_table_offset + GE_STAGE_V5_BG_ROOM_RECORD_BYTES;
    for (uint32_t room_index = 0u; room_index < room_count; room_index++) {
        uint32_t words[6];
        status = ge_stage_bg_v5_read_room(asset_bytes,
                                          asset_byte_count,
                                          offset,
                                          words);
        if (status != GE_STATUS_OK) {
            return ge_stage_bg_v5_diagnostic(
                out_diagnostic,
                GE_STAGE_V5_DIAG_ROOM,
                GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
                stage_id,
                offset,
                room_index,
                0u,
                "background room recheck is truncated",
                status);
        }
        for (uint32_t kind = 0u; kind < 3u; kind++) {
            if (words[kind] == 0u) {
                continue;
            }
            uint32_t local_offset = words[kind] & GE_STAGE_V5_BG_LOCAL_MASK;
            if (local_offset < room_table_end) {
                return ge_stage_bg_v5_diagnostic(
                    out_diagnostic,
                    GE_STAGE_V5_DIAG_OFFSET,
                    GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
                    stage_id,
                    offset + kind * 4u,
                    room_table_end,
                    local_offset,
                    "background room payload points into its metadata table",
                    GE_STATUS_MALFORMED_STREAM);
            }
        }
        offset += GE_STAGE_V5_BG_ROOM_RECORD_BYTES;
    }

    if (portal_table_offset != 0u) {
        flags |= GE_STAGE_V5_BG_FLAG_PORTAL_OFFSET;
    }
    if (visibility_offset != 0u) {
        flags |= GE_STAGE_V5_BG_FLAG_VISIBILITY_OFFSET;
    }
    if (first_payload_offset != UINT32_MAX) {
        flags |= GE_STAGE_V5_BG_FLAG_FIRST_PAYLOAD;
    }
    /* Every non-zero room offset was checked against the prior offset for
       its source column.  A source column may be absent, so monotonicity is
       a property of the columns that are present rather than a requirement
       that all three columns exist. */
    flags |= GE_STAGE_V5_BG_FLAG_OFFSETS_MONOTONIC;

    out_scan->header_word0 = header_words[0];
    out_scan->room_table_segmented_offset = header_words[1];
    out_scan->portal_table_segmented_offset = header_words[2];
    out_scan->visibility_segmented_offset = header_words[3];
    out_scan->header_word4 = header_words[4];
    out_scan->room_table_offset = room_table_offset;
    out_scan->portal_table_offset = portal_table_offset;
    out_scan->visibility_offset = visibility_offset;
    out_scan->room_table_end = room_table_end;
    out_scan->sentinel_record_offset = sentinel_record_offset;
    out_scan->first_payload_offset = first_payload_offset;
    out_scan->room_count = room_count;
    out_scan->flags = flags;
    out_scan->source_hash = ge_stage_bg_v5_hash_source(asset_bytes,
                                                       asset_byte_count);
    out_scan->room_table_hash = ge_stage_bg_v5_hash_source(
        asset_bytes + room_table_offset,
        room_table_end - room_table_offset);
    return GE_STATUS_OK;
}

static uint64_t ge_stage_bg_v5_background_metadata_hash(
    uint32_t stage_id,
    const GEStageBackgroundScanV5 *scan)
{
    uint64_t hash = GE_STAGE_BG_V5_FNV_OFFSET;
    hash = ge_stage_bg_v5_hash_u32(hash, stage_id);
    hash = ge_stage_bg_v5_hash_u32(hash, scan->source_bytes);
    hash = ge_stage_bg_v5_hash_u32(hash, scan->header_word0);
    hash = ge_stage_bg_v5_hash_u32(hash, scan->room_table_segmented_offset);
    hash = ge_stage_bg_v5_hash_u32(hash, scan->portal_table_segmented_offset);
    hash = ge_stage_bg_v5_hash_u32(hash, scan->visibility_segmented_offset);
    hash = ge_stage_bg_v5_hash_u32(hash, scan->header_word4);
    hash = ge_stage_bg_v5_hash_u32(hash, scan->room_table_offset);
    hash = ge_stage_bg_v5_hash_u32(hash, scan->room_table_end -
                                        scan->room_table_offset);
    hash = ge_stage_bg_v5_hash_u32(hash, scan->room_count);
    hash = ge_stage_bg_v5_hash_u32(hash, scan->sentinel_record_offset);
    hash = ge_stage_bg_v5_hash_u32(hash, scan->first_payload_offset);
    hash = ge_stage_bg_v5_hash_u32(hash, scan->offset_count[0]);
    hash = ge_stage_bg_v5_hash_u32(hash, scan->offset_count[1]);
    hash = ge_stage_bg_v5_hash_u32(hash, scan->offset_count[2]);
    hash = ge_stage_bg_v5_hash_u32(hash, scan->flags);
    hash = ge_stage_bg_v5_hash_u64(hash, scan->source_hash);
    return ge_stage_bg_v5_hash_u64(hash, scan->room_table_hash);
}

static void ge_stage_bg_v5_fill_background(
    uint32_t stage_id,
    const GEStageBackgroundScanV5 *scan,
    GEStageBackgroundV5 *out_background)
{
    memset(out_background, 0, sizeof(*out_background));
    out_background->header.abi_version = GE_NATIVE_ABI_VERSION;
    out_background->header.struct_size = (uint32_t)sizeof(*out_background);
    out_background->record_version = GE_STAGE_V5_RECORD_VERSION;
    out_background->stage_id = stage_id;
    out_background->source_bytes = scan->source_bytes;
    out_background->header_word0 = scan->header_word0;
    out_background->room_table_segmented_offset =
        scan->room_table_segmented_offset;
    out_background->portal_table_segmented_offset =
        scan->portal_table_segmented_offset;
    out_background->visibility_segmented_offset =
        scan->visibility_segmented_offset;
    out_background->header_word4 = scan->header_word4;
    out_background->room_table_offset = scan->room_table_offset;
    out_background->room_record_bytes = GE_STAGE_V5_BG_ROOM_RECORD_BYTES;
    out_background->room_count = scan->room_count;
    out_background->sentinel_record_offset = scan->sentinel_record_offset;
    out_background->first_payload_offset = scan->first_payload_offset;
    out_background->point_offset_count = scan->offset_count[0];
    out_background->primary_offset_count = scan->offset_count[1];
    out_background->secondary_offset_count = scan->offset_count[2];
    out_background->flags = scan->flags;
    out_background->source_hash = scan->source_hash;
    out_background->room_table_hash = scan->room_table_hash;
    out_background->metadata_hash = ge_stage_bg_v5_background_metadata_hash(
        stage_id,
        scan);
}

static GEStatusV1 ge_stage_bg_v5_next_offset(
    const uint8_t *asset_bytes,
    uint32_t asset_byte_count,
    uint32_t room_table_offset,
    uint32_t room_count,
    uint32_t target_offset,
    uint32_t kind,
    uint32_t *out_byte_count)
{
    if (asset_bytes == NULL || out_byte_count == NULL || kind >= 3u ||
        target_offset == 0u) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    uint32_t next_offset = asset_byte_count;
    uint32_t offset = room_table_offset + GE_STAGE_V5_BG_ROOM_RECORD_BYTES;
    for (uint32_t room_index = 0u; room_index < room_count; room_index++) {
        uint32_t words[6];
        GEStatusV1 status = ge_stage_bg_v5_read_room(asset_bytes,
                                                     asset_byte_count,
                                                     offset,
                                                     words);
        if (status != GE_STATUS_OK) {
            return status;
        }
        uint32_t segmented_offset = words[kind];
        if (segmented_offset != 0u) {
            uint32_t local_offset = segmented_offset &
                                    GE_STAGE_V5_BG_LOCAL_MASK;
            if (local_offset > target_offset && local_offset < next_offset) {
                next_offset = local_offset;
            }
        }
        offset += GE_STAGE_V5_BG_ROOM_RECORD_BYTES;
    }
    if (target_offset >= asset_byte_count || next_offset <= target_offset) {
        return GE_STATUS_INVALID_SIZE;
    }
    *out_byte_count = next_offset - target_offset;
    return GE_STATUS_OK;
}

static uint64_t ge_stage_bg_v5_room_metadata_hash(
    const GEStageBackgroundRoomV5 *room)
{
    uint64_t hash = GE_STAGE_BG_V5_FNV_OFFSET;
    hash = ge_stage_bg_v5_hash_u32(hash, room->stage_id);
    hash = ge_stage_bg_v5_hash_u32(hash, room->room_index);
    hash = ge_stage_bg_v5_hash_u32(hash, room->source_record_offset);
    hash = ge_stage_bg_v5_hash_u32(hash, room->point_segmented_offset);
    hash = ge_stage_bg_v5_hash_u32(hash, room->primary_segmented_offset);
    hash = ge_stage_bg_v5_hash_u32(hash, room->secondary_segmented_offset);
    hash = ge_stage_bg_v5_hash_u32(hash, room->point_offset);
    hash = ge_stage_bg_v5_hash_u32(hash, room->point_bytes);
    hash = ge_stage_bg_v5_hash_u32(hash, room->primary_offset);
    hash = ge_stage_bg_v5_hash_u32(hash, room->primary_bytes);
    hash = ge_stage_bg_v5_hash_u32(hash, room->secondary_offset);
    hash = ge_stage_bg_v5_hash_u32(hash, room->secondary_bytes);
    hash = ge_stage_bg_v5_hash_u32(hash, room->position_x_bits);
    hash = ge_stage_bg_v5_hash_u32(hash, room->position_y_bits);
    hash = ge_stage_bg_v5_hash_u32(hash, room->position_z_bits);
    return ge_stage_bg_v5_hash_u32(hash, room->flags);
}

static GEStatusV1 ge_stage_bg_v5_fill_room(
    uint32_t stage_id,
    const uint8_t *asset_bytes,
    uint32_t asset_byte_count,
    const GEStageBackgroundScanV5 *scan,
    uint32_t room_index,
    GEStageBackgroundRoomV5 *out_room,
    GEStageDiagnosticV5 *out_diagnostic)
{
    if (room_index >= scan->room_count) {
        return ge_stage_bg_v5_diagnostic(
            out_diagnostic,
            GE_STAGE_V5_DIAG_ROOM,
            GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
            stage_id,
            scan->sentinel_record_offset,
            room_index,
            scan->room_count,
            "background room index is outside the room table",
            GE_STATUS_RESOURCE_NOT_FOUND);
    }
    uint32_t source_record_offset = scan->room_table_offset +
                                    GE_STAGE_V5_BG_ROOM_RECORD_BYTES +
                                    room_index *
                                        GE_STAGE_V5_BG_ROOM_RECORD_BYTES;
    uint32_t words[6];
    GEStatusV1 status = ge_stage_bg_v5_read_room(asset_bytes,
                                                 asset_byte_count,
                                                 source_record_offset,
                                                 words);
    if (status != GE_STATUS_OK) {
        return ge_stage_bg_v5_diagnostic(
            out_diagnostic,
            GE_STAGE_V5_DIAG_ROOM,
            GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
            stage_id,
            source_record_offset,
            room_index,
            0u,
            "background room record is truncated",
            status);
    }

    memset(out_room, 0, sizeof(*out_room));
    out_room->header.abi_version = GE_NATIVE_ABI_VERSION;
    out_room->header.struct_size = (uint32_t)sizeof(*out_room);
    out_room->record_version = GE_STAGE_V5_RECORD_VERSION;
    out_room->stage_id = stage_id;
    out_room->room_index = room_index;
    out_room->source_record_offset = source_record_offset;
    out_room->point_segmented_offset = words[0];
    out_room->primary_segmented_offset = words[1];
    out_room->secondary_segmented_offset = words[2];
    out_room->position_x_bits = words[3];
    out_room->position_y_bits = words[4];
    out_room->position_z_bits = words[5];

    const uint32_t segmented_offsets[3] = {words[0], words[1], words[2]};
    uint32_t *local_offsets[3] = {
        &out_room->point_offset,
        &out_room->primary_offset,
        &out_room->secondary_offset,
    };
    uint32_t *byte_counts[3] = {
        &out_room->point_bytes,
        &out_room->primary_bytes,
        &out_room->secondary_bytes,
    };
    for (uint32_t kind = 0u; kind < 3u; kind++) {
        if (segmented_offsets[kind] == 0u) {
            continue;
        }
        status = ge_stage_bg_v5_segmented_local(segmented_offsets[kind],
                                                asset_byte_count,
                                                local_offsets[kind]);
        if (status != GE_STATUS_OK || *local_offsets[kind] <
                scan->room_table_end) {
            return ge_stage_bg_v5_diagnostic(
                out_diagnostic,
                GE_STAGE_V5_DIAG_OFFSET,
                GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
                stage_id,
                source_record_offset + kind * 4u,
                scan->room_table_end,
                *local_offsets[kind],
                "background room payload range is invalid",
                status == GE_STATUS_OK ? GE_STATUS_MALFORMED_STREAM : status);
        }
        status = ge_stage_bg_v5_next_offset(asset_bytes,
                                            asset_byte_count,
                                            scan->room_table_offset,
                                            scan->room_count,
                                            *local_offsets[kind],
                                            kind,
                                            byte_counts[kind]);
        if (status != GE_STATUS_OK) {
            return ge_stage_bg_v5_diagnostic(
                out_diagnostic,
                GE_STAGE_V5_DIAG_OFFSET,
                GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
                stage_id,
                source_record_offset + kind * 4u,
                *local_offsets[kind],
                asset_byte_count,
                "background room payload range is not bounded",
                status);
        }
    }
    if (words[0] != 0u) {
        out_room->flags |= GE_STAGE_V5_BG_ROOM_FLAG_POINT;
    }
    if (words[1] != 0u) {
        out_room->flags |= GE_STAGE_V5_BG_ROOM_FLAG_PRIMARY;
    }
    if (words[2] != 0u) {
        out_room->flags |= GE_STAGE_V5_BG_ROOM_FLAG_SECONDARY;
    }
    out_room->metadata_hash = ge_stage_bg_v5_room_metadata_hash(out_room);
    status = ge_stage_v5_validate_background_room(out_room);
    if (status != GE_STATUS_OK) {
        return ge_stage_bg_v5_diagnostic(
            out_diagnostic,
            GE_STAGE_V5_DIAG_ROOM,
            GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
            stage_id,
            source_record_offset,
            status,
            0u,
            "background room copy-out failed validation",
            status);
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_stage_v5_parse_background(
    const GEStageResourceV5 *resource,
    const uint8_t *asset_bytes,
    uint32_t asset_byte_count,
    GEStageBackgroundV5 *out_background,
    GEStageDiagnosticV5 *out_diagnostic)
{
    if (resource == NULL || asset_bytes == NULL || out_background == NULL) {
        return ge_stage_bg_v5_diagnostic(
            out_diagnostic,
            GE_STAGE_V5_DIAG_ARGUMENT,
            GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
            resource == NULL ? 0u : resource->stage_id,
            0u,
            0u,
            0u,
            "background parse requires resource, bytes, and output",
            GE_STATUS_INVALID_ARGUMENT);
    }
    GEStageBackgroundScanV5 scan;
    GEStatusV1 status = ge_stage_bg_v5_scan(resource,
                                            asset_bytes,
                                            asset_byte_count,
                                            &scan,
                                            out_diagnostic);
    if (status != GE_STATUS_OK) {
        return status;
    }
    ge_stage_bg_v5_fill_background(resource->stage_id,
                                   &scan,
                                   out_background);
    out_background->source_bytes = asset_byte_count;
    status = ge_stage_v5_validate_background(out_background);
    if (status != GE_STATUS_OK) {
        return ge_stage_bg_v5_diagnostic(
            out_diagnostic,
            GE_STAGE_V5_DIAG_BACKGROUND,
            GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
            resource->stage_id,
            0u,
            status,
            0u,
            "background summary failed validation",
            status);
    }
    if (out_diagnostic != NULL) {
        memset(out_diagnostic, 0, sizeof(*out_diagnostic));
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_stage_v5_validate_background(
    const GEStageBackgroundV5 *background)
{
    if (background == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (background->source_bytes < GE_STAGE_V5_BG_ROOM_RECORD_BYTES ||
        background->room_table_offset > GE_STAGE_V5_BG_LOCAL_MASK ||
        background->sentinel_record_offset > GE_STAGE_V5_BG_LOCAL_MASK) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    uint32_t portal_table_offset = 0u;
    uint32_t visibility_offset = 0u;
    if (ge_stage_bg_v5_segmented_local(
            background->portal_table_segmented_offset,
            background->source_bytes,
            &portal_table_offset) != GE_STATUS_OK ||
        ge_stage_bg_v5_segmented_local(
            background->visibility_segmented_offset,
            background->source_bytes,
            &visibility_offset) != GE_STATUS_OK) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    if (background->header.abi_version != GE_NATIVE_ABI_VERSION ||
        background->header.struct_size != sizeof(*background) ||
        background->record_version != GE_STAGE_V5_RECORD_VERSION ||
        background->stage_id == 0u || background->source_bytes == 0u ||
        background->header_word0 != 0u || background->header_word4 != 0u ||
        background->room_record_bytes != GE_STAGE_V5_BG_ROOM_RECORD_BYTES ||
        background->room_count == 0u ||
        background->room_count > GE_STAGE_V5_BG_MAX_ROOMS ||
        (background->flags & ~GE_STAGE_V5_BG_FLAG_MASK) != 0u ||
        (background->flags & GE_STAGE_V5_BG_FLAG_PORTAL_OFFSET) == 0u ||
        (background->flags & GE_STAGE_V5_BG_FLAG_VISIBILITY_OFFSET) == 0u ||
        (background->flags & GE_STAGE_V5_BG_FLAG_FIRST_PAYLOAD) == 0u ||
        (background->flags & GE_STAGE_V5_BG_FLAG_ROOM_SENTINEL) == 0u ||
        (background->flags & GE_STAGE_V5_BG_FLAG_OFFSETS_MONOTONIC) == 0u ||
        background->room_table_segmented_offset !=
            (GE_STAGE_V5_BG_SEGMENT_TAG | background->room_table_offset) ||
        background->room_table_offset < GE_STAGE_V5_BG_HEADER_BYTES ||
        background->room_table_offset > background->source_bytes -
            GE_STAGE_V5_BG_ROOM_RECORD_BYTES ||
        background->sentinel_record_offset < background->room_table_offset ||
        background->sentinel_record_offset > background->source_bytes -
            GE_STAGE_V5_BG_ROOM_RECORD_BYTES ||
        background->first_payload_offset >= background->source_bytes ||
        background->first_payload_offset < background->room_table_offset ||
        background->point_offset_count > background->room_count ||
        background->primary_offset_count > background->room_count ||
        background->secondary_offset_count > background->room_count ||
        background->source_hash == 0u || background->room_table_hash == 0u ||
        background->metadata_hash == 0u || background->reserved0 != 0u ||
        background->reserved1 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    uint32_t expected_sentinel =
        background->room_table_offset + GE_STAGE_V5_BG_ROOM_RECORD_BYTES;
    if (background->room_count >
            (UINT32_MAX - expected_sentinel) /
                GE_STAGE_V5_BG_ROOM_RECORD_BYTES ||
        expected_sentinel + background->room_count *
                GE_STAGE_V5_BG_ROOM_RECORD_BYTES !=
            background->sentinel_record_offset) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    uint32_t room_table_end = background->sentinel_record_offset +
                              GE_STAGE_V5_BG_ROOM_RECORD_BYTES;
    if (room_table_end < background->sentinel_record_offset ||
        background->portal_table_segmented_offset ==
            background->room_table_segmented_offset ||
        background->visibility_segmented_offset ==
            background->room_table_segmented_offset ||
        portal_table_offset < room_table_end ||
        visibility_offset < room_table_end ||
        background->first_payload_offset < room_table_end) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_stage_v5_background_room(
    const GEStageResourceV5 *resource,
    const uint8_t *asset_bytes,
    uint32_t asset_byte_count,
    uint32_t room_index,
    GEStageBackgroundRoomV5 *out_room,
    GEStageDiagnosticV5 *out_diagnostic)
{
    if (resource == NULL || asset_bytes == NULL || out_room == NULL) {
        return ge_stage_bg_v5_diagnostic(
            out_diagnostic,
            GE_STAGE_V5_DIAG_ARGUMENT,
            GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
            resource == NULL ? 0u : resource->stage_id,
            0u,
            room_index,
            0u,
            "background room requires resource, bytes, and output",
            GE_STATUS_INVALID_ARGUMENT);
    }
    GEStageBackgroundScanV5 scan;
    GEStatusV1 status = ge_stage_bg_v5_scan(resource,
                                            asset_bytes,
                                            asset_byte_count,
                                            &scan,
                                            out_diagnostic);
    if (status != GE_STATUS_OK) {
        return status;
    }
    status = ge_stage_bg_v5_fill_room(resource->stage_id,
                                      asset_bytes,
                                      asset_byte_count,
                                      &scan,
                                      room_index,
                                      out_room,
                                      out_diagnostic);
    if (status == GE_STATUS_OK && out_diagnostic != NULL) {
        memset(out_diagnostic, 0, sizeof(*out_diagnostic));
    }
    return status;
}

GEStatusV1 ge_stage_v5_validate_background_room(
    const GEStageBackgroundRoomV5 *room)
{
    if (room == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (room->header.abi_version != GE_NATIVE_ABI_VERSION ||
        room->header.struct_size != sizeof(*room) ||
        room->record_version != GE_STAGE_V5_RECORD_VERSION ||
        room->stage_id == 0u ||
        (room->flags & ~GE_STAGE_V5_BG_ROOM_FLAG_MASK) != 0u ||
        room->source_record_offset == 0u ||
        (room->source_record_offset & 3u) != 0u ||
        room->point_segmented_offset !=
            (room->point_offset == 0u ? 0u :
             GE_STAGE_V5_BG_SEGMENT_TAG | room->point_offset) ||
        room->primary_segmented_offset !=
            (room->primary_offset == 0u ? 0u :
             GE_STAGE_V5_BG_SEGMENT_TAG | room->primary_offset) ||
        room->secondary_segmented_offset !=
            (room->secondary_offset == 0u ? 0u :
             GE_STAGE_V5_BG_SEGMENT_TAG | room->secondary_offset) ||
        (room->point_offset == 0u && room->point_bytes != 0u) ||
        (room->primary_offset == 0u && room->primary_bytes != 0u) ||
        (room->secondary_offset == 0u && room->secondary_bytes != 0u) ||
        (room->point_offset != 0u && room->point_bytes == 0u) ||
        (room->primary_offset != 0u && room->primary_bytes == 0u) ||
        (room->secondary_offset != 0u && room->secondary_bytes == 0u) ||
        room->point_offset > UINT32_MAX - room->point_bytes ||
        room->primary_offset > UINT32_MAX - room->primary_bytes ||
        room->secondary_offset > UINT32_MAX - room->secondary_bytes ||
        ((room->point_segmented_offset != 0u) &&
         (room->flags & GE_STAGE_V5_BG_ROOM_FLAG_POINT) == 0u) ||
        ((room->primary_segmented_offset != 0u) &&
         (room->flags & GE_STAGE_V5_BG_ROOM_FLAG_PRIMARY) == 0u) ||
        ((room->secondary_segmented_offset != 0u) &&
         (room->flags & GE_STAGE_V5_BG_ROOM_FLAG_SECONDARY) == 0u) ||
        ((room->point_segmented_offset == 0u) &&
         (room->flags & GE_STAGE_V5_BG_ROOM_FLAG_POINT) != 0u) ||
        ((room->primary_segmented_offset == 0u) &&
         (room->flags & GE_STAGE_V5_BG_ROOM_FLAG_PRIMARY) != 0u) ||
        ((room->secondary_segmented_offset == 0u) &&
         (room->flags & GE_STAGE_V5_BG_ROOM_FLAG_SECONDARY) != 0u) ||
        room->metadata_hash == 0u || room->reserved0 != 0u ||
        room->reserved1 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_stage_v5_copy_background_rooms(
    const GEStageResourceV5 *resource,
    const uint8_t *asset_bytes,
    uint32_t asset_byte_count,
    uint32_t first_room,
    uint32_t room_capacity,
    GEStageBackgroundRoomV5 *out_rooms,
    uint32_t *out_room_count,
    GEStageBackgroundV5 *out_background,
    GEStageDiagnosticV5 *out_diagnostic)
{
    if (out_room_count == NULL) {
        return ge_stage_bg_v5_diagnostic(
            out_diagnostic,
            GE_STAGE_V5_DIAG_ARGUMENT,
            GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
            resource == NULL ? 0u : resource->stage_id,
            0u,
            0u,
            0u,
            "background room copy-out requires an output count",
            GE_STATUS_INVALID_ARGUMENT);
    }
    *out_room_count = 0u;
    if (out_rooms == NULL || room_capacity == 0u) {
        return ge_stage_bg_v5_diagnostic(
            out_diagnostic,
            GE_STAGE_V5_DIAG_COPY_OUT,
            GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
            resource == NULL ? 0u : resource->stage_id,
            first_room,
            0u,
            room_capacity,
            "background room copy-out capacity is zero",
            GE_STATUS_INVALID_SIZE);
    }

    GEStageBackgroundScanV5 scan;
    GEStatusV1 status = ge_stage_bg_v5_scan(resource,
                                            asset_bytes,
                                            asset_byte_count,
                                            &scan,
                                            out_diagnostic);
    if (status != GE_STATUS_OK) {
        return status;
    }
    GEStageBackgroundV5 background;
    ge_stage_bg_v5_fill_background(resource->stage_id, &scan, &background);
    background.source_bytes = asset_byte_count;
    if (out_background != NULL) {
        *out_background = background;
    }
    if (first_room >= scan.room_count) {
        return ge_stage_bg_v5_diagnostic(
            out_diagnostic,
            GE_STAGE_V5_DIAG_RANGE,
            GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
            resource->stage_id,
            scan.sentinel_record_offset,
            first_room,
            scan.room_count,
            "background room copy-out start is outside the room table",
            GE_STATUS_RESOURCE_NOT_FOUND);
    }

    uint32_t available = scan.room_count - first_room;
    uint32_t copy_count = room_capacity < available ? room_capacity : available;
    for (uint32_t index = 0u; index < copy_count; index++) {
        status = ge_stage_bg_v5_fill_room(resource->stage_id,
                                          asset_bytes,
                                          asset_byte_count,
                                          &scan,
                                          first_room + index,
                                          &out_rooms[index],
                                          out_diagnostic);
        if (status != GE_STATUS_OK) {
            *out_room_count = index;
            return status;
        }
    }
    *out_room_count = copy_count;
    if (copy_count != available) {
        return ge_stage_bg_v5_diagnostic(
            out_diagnostic,
            GE_STAGE_V5_DIAG_COPY_OUT,
            GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
            resource->stage_id,
            first_room,
            available,
            room_capacity,
            "background room copy-out capacity truncated the room table",
            GE_STATUS_INVALID_SIZE);
    }
    if (out_diagnostic != NULL) {
        memset(out_diagnostic, 0, sizeof(*out_diagnostic));
    }
    return GE_STATUS_OK;
}
