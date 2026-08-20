#include "ge_stage_v5.h"

#include <stddef.h>
#include <string.h>

static const uint64_t GE_STAGE_V5_FNV_OFFSET = UINT64_C(1469598103934665603);
static const uint64_t GE_STAGE_V5_FNV_PRIME = UINT64_C(1099511628211);

static uint64_t ge_stage_v5_hash_update(uint64_t hash,
                                        const uint8_t *bytes,
                                        uint32_t byte_count)
{
    if (bytes == NULL && byte_count != 0u) {
        return 0u;
    }
    for (uint32_t index = 0u; index < byte_count; index++) {
        hash ^= (uint64_t)bytes[index];
        hash *= GE_STAGE_V5_FNV_PRIME;
    }
    return hash;
}

static uint64_t ge_stage_v5_hash_bytes(const uint8_t *bytes,
                                       uint32_t byte_count)
{
    return ge_stage_v5_hash_update(GE_STAGE_V5_FNV_OFFSET, bytes, byte_count);
}

static uint64_t ge_stage_v5_hash_u32(uint64_t hash, uint32_t value)
{
    const uint8_t bytes[4] = {
        (uint8_t)(value & UINT32_C(0xff)),
        (uint8_t)((value >> 8) & UINT32_C(0xff)),
        (uint8_t)((value >> 16) & UINT32_C(0xff)),
        (uint8_t)(value >> 24),
    };
    return ge_stage_v5_hash_update(hash, bytes, (uint32_t)sizeof(bytes));
}

static uint32_t ge_stage_v5_name_bytes(const char *name)
{
    if (name == NULL) {
        return 0u;
    }
    for (uint32_t index = 0u; index < GE_STAGE_V5_RESOURCE_NAME_BYTES; index++) {
        if (name[index] == '\0') {
            return index;
        }
    }
    return GE_STAGE_V5_RESOURCE_NAME_BYTES;
}

static uint64_t ge_stage_v5_resource_metadata_hash(
    const GEStageResourceV5 *resource)
{
    uint64_t hash = GE_STAGE_V5_FNV_OFFSET;
    hash = ge_stage_v5_hash_u32(hash, resource->stage_id);
    hash = ge_stage_v5_hash_u32(hash, resource->resource_kind);
    hash = ge_stage_v5_hash_u32(hash, resource->compression);
    hash = ge_stage_v5_hash_u32(hash, resource->flags);
    hash = ge_stage_v5_hash_u32(hash, resource->asset_handle);
    hash = ge_stage_v5_hash_u32(hash, resource->source_offset);
    hash = ge_stage_v5_hash_u32(hash, resource->source_bytes);
    hash = ge_stage_v5_hash_u32(hash, resource->decoded_bytes);
    return ge_stage_v5_hash_update(
        hash,
        (const uint8_t *)resource->resource_name,
        ge_stage_v5_name_bytes(resource->resource_name));
}

static int ge_stage_v5_text_valid(const char *text, uint32_t capacity)
{
    if (text == NULL || capacity == 0u) {
        return 0;
    }
    for (uint32_t index = 0u; index < capacity; index++) {
        if (text[index] == '\0') {
            return 1;
        }
    }
    return 0;
}

static void ge_stage_v5_copy_message(char *destination,
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

uint32_t ge_stage_v5_resource_handle(uint32_t stage_id,
                                     uint32_t resource_kind)
{
    if (stage_id == 0u || stage_id > UINT32_C(0xff) ||
        resource_kind < GE_STAGE_V5_RESOURCE_BACKGROUND ||
        resource_kind > GE_STAGE_V5_RESOURCE_MAX) {
        return 0u;
    }
    return GE_STAGE_V5_HANDLE(stage_id, resource_kind);
}

#define GE_STAGE_V5_RESOURCE_INIT(stage, kind, compression_value, offset, \
                                   source_size, decoded_size, resource_text) \
    {                                                                       \
        {GE_NATIVE_ABI_VERSION, (uint32_t)sizeof(GEStageResourceV5)},       \
        GE_STAGE_V5_RECORD_VERSION,                                         \
        (stage),                                                            \
        (kind),                                                             \
        (compression_value),                                                \
        GE_STAGE_V5_RESOURCE_FLAG_EXTERNAL |                                \
            GE_STAGE_V5_RESOURCE_FLAG_SOURCE_SIZE |                         \
            GE_STAGE_V5_RESOURCE_FLAG_DECODED_SIZE |                        \
            GE_STAGE_V5_RESOURCE_FLAG_NO_RUNTIME_ROM,                       \
        GE_STAGE_V5_HANDLE((stage), (kind)),                                \
        (offset),                                                           \
        (source_size),                                                      \
        (decoded_size),                                                      \
        (resource_text),                                                     \
        0u,                                                                 \
        0u                                                                  \
    }

#define GE_STAGE_V5_ENTRY_INIT(stage, stage_text, demos, background_value, \
                               stan_value, setup_value)                     \
    {                                                                       \
        {GE_NATIVE_ABI_VERSION, (uint32_t)sizeof(GEStageCatalogEntryV5)},   \
        GE_STAGE_V5_RECORD_VERSION,                                         \
        (stage),                                                            \
        GE_STAGE_V5_ENTRY_FLAG_RAMROM_REQUIRED |                             \
            GE_STAGE_V5_ENTRY_FLAG_NATIVE_LOADER_PENDING |                   \
            GE_STAGE_V5_ENTRY_FLAG_GAMEPLAY_PENDING,                        \
        (demos),                                                            \
        (stage_text),                                                       \
        background_value,                                                     \
        stan_value,                                                           \
        setup_value                                                            \
    }

/* Source order is deliberately the RAMROM attract grouping.  The source
   LEVELID values are retained as values, not used as addresses. */
static const GEStageCatalogEntryV5 GE_STAGE_V5_CATALOG[GE_STAGE_V5_STAGE_COUNT] = {
    GE_STAGE_V5_ENTRY_INIT(
        33u, "Dam", UINT32_C(0x00000003),
        GE_STAGE_V5_RESOURCE_INIT(33u, GE_STAGE_V5_RESOURCE_BACKGROUND, 0u,
                                  6290512u, 197024u, 197024u, "bg_dam_all_p"),
        GE_STAGE_V5_RESOURCE_INIT(33u, GE_STAGE_V5_RESOURCE_STAN, 1u,
                                  8720304u, 41952u, 89040u,
                                  "Tbg_dam_all_p_stanZ"),
        GE_STAGE_V5_RESOURCE_INIT(33u, GE_STAGE_V5_RESOURCE_SETUP, 1u,
                                  9179344u, 17104u, 81808u, "UsetupdamZ")),
    GE_STAGE_V5_ENTRY_INIT(
        34u, "Facility", UINT32_C(0x0000001c),
        GE_STAGE_V5_RESOURCE_INIT(34u, GE_STAGE_V5_RESOURCE_BACKGROUND, 0u,
                                  6487536u, 200576u, 200576u,
                                  "bg_ark_all_p"),
        GE_STAGE_V5_RESOURCE_INIT(34u, GE_STAGE_V5_RESOURCE_STAN, 1u,
                                  8602016u, 36800u, 84112u,
                                  "Tbg_ark_all_p_stanZ"),
        GE_STAGE_V5_RESOURCE_INIT(34u, GE_STAGE_V5_RESOURCE_SETUP, 1u,
                                  9107488u, 15248u, 96160u, "UsetuparkZ")),
    GE_STAGE_V5_ENTRY_INIT(
        35u, "Runway", UINT32_C(0x00000060),
        GE_STAGE_V5_RESOURCE_INIT(35u, GE_STAGE_V5_RESOURCE_BACKGROUND, 0u,
                                  6688112u, 41936u, 41936u, "bg_run_all_p"),
        GE_STAGE_V5_RESOURCE_INIT(35u, GE_STAGE_V5_RESOURCE_STAN, 1u,
                                  8890736u, 6784u, 16112u,
                                  "Tbg_run_all_p_stanZ"),
        GE_STAGE_V5_RESOURCE_INIT(35u, GE_STAGE_V5_RESOURCE_SETUP, 1u,
                                  9245392u, 6240u, 31072u, "UsetuprunZ")),
    GE_STAGE_V5_ENTRY_INIT(
        9u, "Bunker I", UINT32_C(0x00000180),
        GE_STAGE_V5_RESOURCE_INIT(9u, GE_STAGE_V5_RESOURCE_BACKGROUND, 0u,
                                  4425312u, 69104u, 69104u, "bg_sev_all_p"),
        GE_STAGE_V5_RESOURCE_INIT(9u, GE_STAGE_V5_RESOURCE_STAN, 1u,
                                  8897520u, 15824u, 35328u,
                                  "Tbg_sev_all_p_stanZ"),
        GE_STAGE_V5_RESOURCE_INIT(9u, GE_STAGE_V5_RESOURCE_SETUP, 1u,
                                  9261456u, 6704u, 41056u,
                                  "UsetupsevbunkerZ")),
    GE_STAGE_V5_ENTRY_INIT(
        20u, "Silo", UINT32_C(0x00000600),
        GE_STAGE_V5_RESOURCE_INIT(20u, GE_STAGE_V5_RESOURCE_BACKGROUND, 0u,
                                  4494416u, 331584u, 331584u, "bg_silo_all_p"),
        GE_STAGE_V5_RESOURCE_INIT(20u, GE_STAGE_V5_RESOURCE_STAN, 1u,
                                  8971312u, 37024u, 83504u,
                                  "Tbg_silo_all_p_stanZ"),
        GE_STAGE_V5_RESOURCE_INIT(20u, GE_STAGE_V5_RESOURCE_SETUP, 1u,
                                  9301952u, 10832u, 75136u, "UsetupsiloZ")),
    GE_STAGE_V5_ENTRY_INIT(
        26u, "Frigate", UINT32_C(0x00001800),
        GE_STAGE_V5_RESOURCE_INIT(26u, GE_STAGE_V5_RESOURCE_BACKGROUND, 0u,
                                  5441600u, 186816u, 186816u,
                                  "bg_dest_all_p"),
        GE_STAGE_V5_RESOURCE_INIT(26u, GE_STAGE_V5_RESOURCE_STAN, 1u,
                                  8790736u, 26864u, 61040u,
                                  "Tbg_dest_all_p_stanZ"),
        GE_STAGE_V5_RESOURCE_INIT(26u, GE_STAGE_V5_RESOURCE_SETUP, 1u,
                                  9208624u, 9040u, 58624u,
                                  "UsetupdestZ")),
    GE_STAGE_V5_ENTRY_INIT(
        25u, "Train", UINT32_C(0x00002000),
        GE_STAGE_V5_RESOURCE_INIT(25u, GE_STAGE_V5_RESOURCE_BACKGROUND, 0u,
                                  5309136u, 132464u, 132464u, "bg_tra_all_p"),
        GE_STAGE_V5_RESOURCE_INIT(25u, GE_STAGE_V5_RESOURCE_STAN, 1u,
                                  9028496u, 9168u, 22336u,
                                  "Tbg_tra_all_p_stanZ"),
        GE_STAGE_V5_RESOURCE_INIT(25u, GE_STAGE_V5_RESOURCE_SETUP, 1u,
                                  9322976u, 12848u, 82032u, "UsetuptraZ")),
};

#undef GE_STAGE_V5_ENTRY_INIT
#undef GE_STAGE_V5_RESOURCE_INIT

static GEStatusV1 ge_stage_v5_validate_common(const GEAbiHeaderV1 *header,
                                              uint32_t expected_size,
                                              uint32_t record_version)
{
    if (header == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (header->abi_version != GE_NATIVE_ABI_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    if (header->struct_size != expected_size) {
        return GE_STATUS_INVALID_SIZE;
    }
    if (record_version != GE_STAGE_V5_RECORD_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_stage_v5_validate_resource(const GEStageResourceV5 *resource)
{
    if (resource == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_stage_v5_validate_common(
        &resource->header, (uint32_t)sizeof(*resource), resource->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (resource->stage_id == 0u ||
        resource->resource_kind < GE_STAGE_V5_RESOURCE_BACKGROUND ||
        resource->resource_kind > GE_STAGE_V5_RESOURCE_MAX ||
        resource->compression > GE_STAGE_V5_COMPRESSION_MAX ||
        resource->flags != (GE_STAGE_V5_RESOURCE_FLAG_EXTERNAL |
                            GE_STAGE_V5_RESOURCE_FLAG_SOURCE_SIZE |
                            GE_STAGE_V5_RESOURCE_FLAG_DECODED_SIZE |
                            GE_STAGE_V5_RESOURCE_FLAG_NO_RUNTIME_ROM) ||
        resource->asset_handle != ge_stage_v5_resource_handle(
            resource->stage_id, resource->resource_kind) ||
        resource->source_bytes == 0u || resource->decoded_bytes == 0u ||
        resource->reserved0 != 0u || resource->reserved1 != 0u ||
        !ge_stage_v5_text_valid(resource->resource_name,
                                GE_STAGE_V5_RESOURCE_NAME_BYTES)) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    if (resource->compression == GE_STAGE_V5_COMPRESSION_NONE &&
        resource->source_bytes != resource->decoded_bytes) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    if (resource->source_offset > UINT32_MAX - resource->source_bytes) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_stage_v5_validate_entry(const GEStageCatalogEntryV5 *entry)
{
    if (entry == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_stage_v5_validate_common(
        &entry->header, (uint32_t)sizeof(*entry), entry->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (entry->stage_id == 0u || entry->demo_mask == 0u ||
        (entry->flags & ~GE_STAGE_V5_ENTRY_FLAG_MASK) != 0u ||
        !ge_stage_v5_text_valid(entry->stage_name,
                                GE_STAGE_V5_STAGE_NAME_BYTES)) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    const GEStageResourceV5 *resources[GE_STAGE_V5_RESOURCE_COUNT] = {
        &entry->background,
        &entry->stan,
        &entry->setup,
    };
    for (uint32_t index = 0u; index < GE_STAGE_V5_RESOURCE_COUNT; index++) {
        status = ge_stage_v5_validate_resource(resources[index]);
        if (status != GE_STATUS_OK || resources[index]->stage_id != entry->stage_id ||
            resources[index]->resource_kind != index + 1u) {
            return status == GE_STATUS_OK ? GE_STATUS_MALFORMED_STREAM : status;
        }
    }
    return GE_STATUS_OK;
}

uint32_t ge_stage_v5_catalog_count(void)
{
    return GE_STAGE_V5_STAGE_COUNT;
}

GEStatusV1 ge_stage_v5_catalog_entry(uint32_t index,
                                     GEStageCatalogEntryV5 *out_entry)
{
    if (out_entry == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (index >= GE_STAGE_V5_STAGE_COUNT) {
        return GE_STATUS_RESOURCE_NOT_FOUND;
    }
    *out_entry = GE_STAGE_V5_CATALOG[index];
    return ge_stage_v5_validate_entry(out_entry);
}

GEStatusV1 ge_stage_v5_find_stage(uint32_t stage_id,
                                  GEStageCatalogEntryV5 *out_entry)
{
    if (out_entry == NULL || stage_id == 0u) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    for (uint32_t index = 0u; index < GE_STAGE_V5_STAGE_COUNT; index++) {
        if (GE_STAGE_V5_CATALOG[index].stage_id == stage_id) {
            *out_entry = GE_STAGE_V5_CATALOG[index];
            return ge_stage_v5_validate_entry(out_entry);
        }
    }
    return GE_STATUS_RESOURCE_NOT_FOUND;
}

static GEStatusV1 ge_stage_v5_set_diagnostic(
    GEStageDiagnosticV5 *diagnostic,
    uint32_t code,
    uint32_t flags,
    uint32_t stage_id,
    uint32_t resource_kind,
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
        diagnostic->resource_kind = resource_kind;
        diagnostic->byte_offset = byte_offset;
        diagnostic->detail0 = detail0;
        diagnostic->detail1 = detail1;
        ge_stage_v5_copy_message(diagnostic->message,
                                 (uint32_t)sizeof(diagnostic->message),
                                 message);
    }
    return status;
}

static void ge_stage_v5_fill_packet(uint32_t packet_index,
                                    const GEStageResourceV5 *resource,
                                    GEStageResourcePacketV5 *out_packet)
{
    memset(out_packet, 0, sizeof(*out_packet));
    out_packet->header.abi_version = GE_NATIVE_ABI_VERSION;
    out_packet->header.struct_size = (uint32_t)sizeof(*out_packet);
    out_packet->record_version = GE_STAGE_V5_RECORD_VERSION;
    out_packet->packet_index = packet_index;
    out_packet->stage_id = resource->stage_id;
    out_packet->resource_kind = resource->resource_kind;
    out_packet->asset_handle = resource->asset_handle;
    out_packet->compression = resource->compression;
    out_packet->flags = GE_STAGE_V5_PACKET_FLAG_METADATA_ONLY |
                        GE_STAGE_V5_PACKET_FLAG_NO_PAYLOAD;
    out_packet->source_offset = resource->source_offset;
    out_packet->source_bytes = resource->source_bytes;
    out_packet->decoded_bytes = resource->decoded_bytes;
    out_packet->name_bytes = ge_stage_v5_name_bytes(resource->resource_name);
    memcpy(out_packet->resource_name,
           resource->resource_name,
           sizeof(out_packet->resource_name));
    out_packet->metadata_hash = ge_stage_v5_resource_metadata_hash(resource);
}

uint32_t ge_stage_v5_resource_packet_count(void)
{
    return GE_STAGE_V5_RESOURCE_PACKET_COUNT;
}

GEStatusV1 ge_stage_v5_resource_packet(uint32_t packet_index,
                                       GEStageResourcePacketV5 *out_packet)
{
    if (out_packet == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (packet_index >= GE_STAGE_V5_RESOURCE_PACKET_COUNT) {
        return GE_STATUS_RESOURCE_NOT_FOUND;
    }
    uint32_t stage_index = packet_index / GE_STAGE_V5_RESOURCE_COUNT;
    uint32_t resource_index = packet_index % GE_STAGE_V5_RESOURCE_COUNT;
    GEStageCatalogEntryV5 entry;
    GEStatusV1 status = ge_stage_v5_catalog_entry(stage_index, &entry);
    if (status != GE_STATUS_OK) {
        return status;
    }
    const GEStageResourceV5 *resources[GE_STAGE_V5_RESOURCE_COUNT] = {
        &entry.background,
        &entry.stan,
        &entry.setup,
    };
    ge_stage_v5_fill_packet(packet_index,
                            resources[resource_index],
                            out_packet);
    return GE_STATUS_OK;
}

GEStatusV1 ge_stage_v5_copy_resource_packets(
    uint32_t first_packet,
    uint32_t packet_capacity,
    GEStageResourcePacketV5 *out_packets,
    uint32_t *out_packet_count,
    GEStageDiagnosticV5 *out_diagnostic)
{
    if (out_packet_count == NULL) {
        return ge_stage_v5_set_diagnostic(
            out_diagnostic,
            GE_STAGE_V5_DIAG_ARGUMENT,
            GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
            0u,
            0u,
            0u,
            0u,
            0u,
            "stage packet copy-out requires an output count",
            GE_STATUS_INVALID_ARGUMENT);
    }
    *out_packet_count = 0u;
    if (out_packets == NULL || packet_capacity == 0u) {
        return ge_stage_v5_set_diagnostic(
            out_diagnostic,
            GE_STAGE_V5_DIAG_COPY_OUT,
            GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
            0u,
            0u,
            first_packet,
            GE_STAGE_V5_RESOURCE_PACKET_COUNT,
            packet_capacity,
            "stage packet copy-out capacity is zero",
            GE_STATUS_INVALID_SIZE);
    }
    if (first_packet >= GE_STAGE_V5_RESOURCE_PACKET_COUNT) {
        return ge_stage_v5_set_diagnostic(
            out_diagnostic,
            GE_STAGE_V5_DIAG_RANGE,
            GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
            0u,
            0u,
            first_packet,
            GE_STAGE_V5_RESOURCE_PACKET_COUNT,
            packet_capacity,
            "stage packet copy-out start is outside the catalog",
            GE_STATUS_RESOURCE_NOT_FOUND);
    }
    uint32_t available = GE_STAGE_V5_RESOURCE_PACKET_COUNT - first_packet;
    uint32_t copy_count = packet_capacity < available ? packet_capacity : available;
    for (uint32_t index = 0u; index < copy_count; index++) {
        GEStatusV1 status = ge_stage_v5_resource_packet(
            first_packet + index,
            &out_packets[index]);
        if (status != GE_STATUS_OK) {
            *out_packet_count = index;
            return ge_stage_v5_set_diagnostic(
                out_diagnostic,
                GE_STAGE_V5_DIAG_COPY_OUT,
                GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
                0u,
                0u,
                first_packet + index,
                available,
                packet_capacity,
                "stage packet copy-out catalog read failed",
                status);
        }
    }
    *out_packet_count = copy_count;
    if (copy_count != available) {
        return ge_stage_v5_set_diagnostic(
            out_diagnostic,
            GE_STAGE_V5_DIAG_COPY_OUT,
            GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
            out_packets[0].stage_id,
            out_packets[0].resource_kind,
            first_packet,
            available,
            packet_capacity,
            "stage packet copy-out capacity truncated the catalog",
            GE_STATUS_INVALID_SIZE);
    }
    if (out_diagnostic != NULL) {
        memset(out_diagnostic, 0, sizeof(*out_diagnostic));
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_stage_v5_validate_resource_view(
    const GEStageResourceViewV5 *view)
{
    if (view == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_stage_v5_validate_common(
        &view->header, (uint32_t)sizeof(*view), view->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (view->stage_id == 0u ||
        view->resource_kind < GE_STAGE_V5_RESOURCE_BACKGROUND ||
        view->resource_kind > GE_STAGE_V5_RESOURCE_MAX ||
        view->compression > GE_STAGE_V5_COMPRESSION_MAX ||
        view->asset_handle != ge_stage_v5_resource_handle(
            view->stage_id, view->resource_kind) ||
        (view->flags & ~GE_STAGE_V5_RESOURCE_FLAG_MASK) != 0u ||
        view->decoded_bytes == 0u || view->source_bytes == 0u ||
        view->source_offset > UINT32_MAX - view->source_bytes ||
        view->decoded_base_offset > UINT32_MAX - view->decoded_bytes ||
        view->metadata_hash == 0u || view->reserved0 != 0u ||
        view->reserved1 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_stage_v5_make_resource_view(
    const GEStageResourceV5 *resource,
    uint32_t decoded_base_offset,
    uint32_t decoded_arena_bytes,
    GEStageResourceViewV5 *out_view,
    GEStageDiagnosticV5 *out_diagnostic)
{
    if (resource == NULL || out_view == NULL) {
        return ge_stage_v5_set_diagnostic(
            out_diagnostic,
            GE_STAGE_V5_DIAG_ARGUMENT,
            GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
            0u,
            0u,
            0u,
            0u,
            0u,
            "stage resource view requires resource and output",
            GE_STATUS_INVALID_ARGUMENT);
    }
    GEStatusV1 status = ge_stage_v5_validate_resource(resource);
    if (status != GE_STATUS_OK) {
        return ge_stage_v5_set_diagnostic(
            out_diagnostic,
            GE_STAGE_V5_DIAG_VIEW,
            GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
            resource->stage_id,
            resource->resource_kind,
            0u,
            status,
            0u,
            "stage resource metadata failed validation",
            status);
    }
    uint32_t checked_base = 0u;
    status = ge_stage_v5_rebase_local_range(decoded_base_offset,
                                            decoded_arena_bytes,
                                            0u,
                                            resource->decoded_bytes,
                                            &checked_base);
    if (status != GE_STATUS_OK) {
        return ge_stage_v5_set_diagnostic(
            out_diagnostic,
            GE_STAGE_V5_DIAG_VIEW,
            GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
            resource->stage_id,
            resource->resource_kind,
            decoded_base_offset,
            resource->decoded_bytes,
            decoded_arena_bytes,
            "decoded arena is too small for stage resource",
            status);
    }
    memset(out_view, 0, sizeof(*out_view));
    out_view->header.abi_version = GE_NATIVE_ABI_VERSION;
    out_view->header.struct_size = (uint32_t)sizeof(*out_view);
    out_view->record_version = GE_STAGE_V5_RECORD_VERSION;
    out_view->stage_id = resource->stage_id;
    out_view->resource_kind = resource->resource_kind;
    out_view->asset_handle = resource->asset_handle;
    out_view->compression = resource->compression;
    out_view->flags = resource->flags;
    out_view->decoded_base_offset = checked_base;
    out_view->decoded_bytes = resource->decoded_bytes;
    out_view->source_offset = resource->source_offset;
    out_view->source_bytes = resource->source_bytes;
    out_view->metadata_hash = ge_stage_v5_resource_metadata_hash(resource);
    status = ge_stage_v5_validate_resource_view(out_view);
    if (status != GE_STATUS_OK) {
        return ge_stage_v5_set_diagnostic(
            out_diagnostic,
            GE_STAGE_V5_DIAG_VIEW,
            GE_STAGE_V5_DIAG_FLAG_RECOVERABLE,
            resource->stage_id,
            resource->resource_kind,
            decoded_base_offset,
            status,
            0u,
            "stage resource view failed validation",
            status);
    }
    if (out_diagnostic != NULL) {
        memset(out_diagnostic, 0, sizeof(*out_diagnostic));
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_stage_v5_read_1172(const uint8_t *asset_bytes,
                                 uint32_t asset_byte_count,
                                 uint32_t expected_decoded_bytes,
                                 GEStage1172InfoV5 *out_info)
{
    if (asset_bytes == NULL || out_info == NULL || expected_decoded_bytes == 0u) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (asset_byte_count < GE_STAGE_V5_1172_PREFIX_BYTES ||
        asset_bytes[0] != GE_STAGE_V5_1172_MAGIC0 ||
        asset_bytes[1] != GE_STAGE_V5_1172_MAGIC1) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    memset(out_info, 0, sizeof(*out_info));
    out_info->header.abi_version = GE_NATIVE_ABI_VERSION;
    out_info->header.struct_size = (uint32_t)sizeof(*out_info);
    out_info->record_version = GE_STAGE_V5_RECORD_VERSION;
    out_info->source_bytes = asset_byte_count;
    out_info->prefix_bytes = GE_STAGE_V5_1172_PREFIX_BYTES;
    out_info->compressed_payload_bytes = asset_byte_count -
                                         GE_STAGE_V5_1172_PREFIX_BYTES;
    out_info->expected_decoded_bytes = expected_decoded_bytes;
    out_info->source_hash = ge_stage_v5_hash_bytes(asset_bytes, asset_byte_count);
    return GE_STATUS_OK;
}

GEStatusV1 ge_stage_v5_validate_asset(const GEStageResourceV5 *resource,
                                      const uint8_t *asset_bytes,
                                      uint32_t asset_byte_count,
                                      GEStageAssetViewV5 *out_view)
{
    if (resource == NULL || asset_bytes == NULL || out_view == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_stage_v5_validate_resource(resource);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (asset_byte_count != resource->source_bytes) {
        return GE_STATUS_ASSET_MISMATCH;
    }
    uint64_t source_hash = ge_stage_v5_hash_bytes(asset_bytes, asset_byte_count);
    if (resource->compression == GE_STAGE_V5_COMPRESSION_1172) {
        GEStage1172InfoV5 info;
        status = ge_stage_v5_read_1172(asset_bytes,
                                       asset_byte_count,
                                       resource->decoded_bytes,
                                       &info);
        if (status != GE_STATUS_OK) {
            return status;
        }
    }
    memset(out_view, 0, sizeof(*out_view));
    out_view->header.abi_version = GE_NATIVE_ABI_VERSION;
    out_view->header.struct_size = (uint32_t)sizeof(*out_view);
    out_view->record_version = GE_STAGE_V5_RECORD_VERSION;
    out_view->stage_id = resource->stage_id;
    out_view->resource_kind = resource->resource_kind;
    out_view->compression = resource->compression;
    out_view->asset_handle = resource->asset_handle;
    out_view->source_bytes = resource->source_bytes;
    out_view->decoded_bytes = resource->decoded_bytes;
    out_view->supplied_bytes = asset_byte_count;
    out_view->flags = resource->flags;
    out_view->source_hash = source_hash;
    return GE_STATUS_OK;
}

GEStatusV1 ge_stage_v5_decompress_1172(const GEStageResourceV5 *resource,
                                       const uint8_t *asset_bytes,
                                       uint32_t asset_byte_count,
                                       uint8_t *decoded_bytes,
                                       uint32_t decoded_capacity,
                                       uint32_t *decoded_byte_count,
                                       GEStageInflateV5 inflate)
{
    if (resource == NULL || asset_bytes == NULL || decoded_bytes == NULL ||
        decoded_byte_count == NULL || inflate == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    *decoded_byte_count = 0u;
    GEStatusV1 status = ge_stage_v5_validate_resource(resource);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (resource->compression != GE_STAGE_V5_COMPRESSION_1172) {
        return GE_STATUS_UNSUPPORTED_COMMAND;
    }
    GEStage1172InfoV5 info;
    status = ge_stage_v5_read_1172(asset_bytes,
                                   asset_byte_count,
                                   resource->decoded_bytes,
                                   &info);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (decoded_capacity < info.expected_decoded_bytes) {
        return GE_STATUS_INVALID_SIZE;
    }
    uint32_t inflated_count = 0u;
    status = inflate(asset_bytes + info.prefix_bytes,
                     info.compressed_payload_bytes,
                     decoded_bytes,
                     decoded_capacity,
                     &inflated_count);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (inflated_count != info.expected_decoded_bytes) {
        return GE_STATUS_ASSET_MISMATCH;
    }
    *decoded_byte_count = inflated_count;
    return GE_STATUS_OK;
}

GEStatusV1 ge_stage_v5_rebase_local_range(uint32_t file_base_offset,
                                          uint32_t file_byte_count,
                                          uint32_t local_offset,
                                          uint32_t local_byte_count,
                                          uint32_t *out_global_offset)
{
    if (out_global_offset == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (file_base_offset > UINT32_MAX - file_byte_count ||
        local_offset > file_byte_count ||
        local_byte_count > file_byte_count - local_offset ||
        file_base_offset > UINT32_MAX - local_offset ||
        file_base_offset + local_offset >
            UINT32_MAX - local_byte_count) {
        return GE_STATUS_INVALID_SIZE;
    }
    *out_global_offset = file_base_offset + local_offset;
    return GE_STATUS_OK;
}

GEStatusV1 ge_stage_v5_rebase_resource_range(const GEStageResourceV5 *resource,
                                             uint32_t local_offset,
                                             uint32_t local_byte_count,
                                             uint32_t *out_source_offset)
{
    if (resource == NULL || out_source_offset == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_stage_v5_validate_resource(resource);
    if (status != GE_STATUS_OK) {
        return status;
    }
    /* A 1172 compressed stream has no one-to-one source/decoded offset map.
       Callers must inflate first and use ge_stage_v5_rebase_local_range on
       their decoded arena; silently treating compressed offsets as decoded
       offsets would corrupt stage pointers. */
    if (resource->compression != GE_STAGE_V5_COMPRESSION_NONE) {
        return GE_STATUS_UNSUPPORTED_COMMAND;
    }
    return ge_stage_v5_rebase_local_range(resource->source_offset,
                                          resource->source_bytes,
                                          local_offset,
                                          local_byte_count,
                                          out_source_offset);
}

GEStatusV1 ge_stage_v5_read_be16(const uint8_t *bytes,
                                 uint32_t byte_count,
                                 uint32_t local_offset,
                                 uint16_t *out_value)
{
    if (bytes == NULL || out_value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (local_offset > byte_count || byte_count - local_offset < 2u) {
        return GE_STATUS_INVALID_SIZE;
    }
    *out_value = (uint16_t)(((uint16_t)bytes[local_offset] << 8) |
                            (uint16_t)bytes[local_offset + 1u]);
    return GE_STATUS_OK;
}

GEStatusV1 ge_stage_v5_read_be32(const uint8_t *bytes,
                                 uint32_t byte_count,
                                 uint32_t local_offset,
                                 uint32_t *out_value)
{
    if (bytes == NULL || out_value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (local_offset > byte_count || byte_count - local_offset < 4u) {
        return GE_STATUS_INVALID_SIZE;
    }
    *out_value = ((uint32_t)bytes[local_offset] << 24) |
                 ((uint32_t)bytes[local_offset + 1u] << 16) |
                 ((uint32_t)bytes[local_offset + 2u] << 8) |
                 (uint32_t)bytes[local_offset + 3u];
    return GE_STATUS_OK;
}

GEStatusV1 ge_stage_v5_stub_status(uint32_t milestone,
                                   uint32_t stage_id,
                                   uint32_t resource_kind,
                                   GEStageDiagnosticV5 *out_diagnostic)
{
    if (out_diagnostic == NULL || stage_id == 0u) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (milestone != GE_STAGE_V5_STUB_M24 &&
        milestone != GE_STAGE_V5_STUB_M25 &&
        milestone != GE_STAGE_V5_STUB_M26 &&
        milestone != GE_STAGE_V5_STUB_M27) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStageCatalogEntryV5 entry;
    GEStatusV1 status = ge_stage_v5_find_stage(stage_id, &entry);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (resource_kind > GE_STAGE_V5_RESOURCE_MAX) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    memset(out_diagnostic, 0, sizeof(*out_diagnostic));
    out_diagnostic->version = GE_STAGE_V5_CONTRACT_VERSION;
    out_diagnostic->code = GE_STAGE_V5_DIAG_STUB;
    out_diagnostic->flags = GE_STAGE_V5_DIAG_FLAG_STUB;
    out_diagnostic->milestone = milestone;
    out_diagnostic->stage_id = stage_id;
    out_diagnostic->resource_kind = resource_kind;
    switch (milestone) {
    case GE_STAGE_V5_STUB_M24:
        ge_stage_v5_copy_message(
            out_diagnostic->message,
            (uint32_t)sizeof(out_diagnostic->message),
            "STUB(M24): native stage platform services are not yet ported");
        break;
    case GE_STAGE_V5_STUB_M25:
        ge_stage_v5_copy_message(
            out_diagnostic->message,
            (uint32_t)sizeof(out_diagnostic->message),
            "STUB(M25): stage background/setup loader is not yet ported");
        break;
    case GE_STAGE_V5_STUB_M26:
        ge_stage_v5_copy_message(
            out_diagnostic->message,
            (uint32_t)sizeof(out_diagnostic->message),
            "STUB(M26): demo gameplay systems are not yet ported");
        break;
    case GE_STAGE_V5_STUB_M27:
        ge_stage_v5_copy_message(
            out_diagnostic->message,
            (uint32_t)sizeof(out_diagnostic->message),
            "STUB(M27): stage renderer is not yet ported");
        break;
    default:
        return GE_STATUS_INVALID_ARGUMENT;
    }
    return GE_STATUS_UNSUPPORTED_COMMAND;
}
