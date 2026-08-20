#include "ge_stage_v5.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define REQUIRE(condition)                                                     \
    do {                                                                        \
        if (!(condition)) {                                                     \
            fprintf(stderr, "stage v5 requirement failed at %s:%d: %s\n",     \
                    __FILE__, __LINE__, #condition);                           \
            return 1;                                                           \
        }                                                                       \
    } while (0)

static GEStatusV1 copy_inflate(const uint8_t *compressed_bytes,
                               uint32_t compressed_byte_count,
                               uint8_t *decoded_bytes,
                               uint32_t decoded_capacity,
                               uint32_t *decoded_byte_count)
{
    if (compressed_bytes == NULL || decoded_bytes == NULL ||
        decoded_byte_count == NULL || decoded_capacity < compressed_byte_count) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    memcpy(decoded_bytes, compressed_bytes, compressed_byte_count);
    *decoded_byte_count = compressed_byte_count;
    return GE_STATUS_OK;
}

static int check_catalog(void)
{
    static const uint32_t expected_stage_ids[GE_STAGE_V5_STAGE_COUNT] = {
        33u, 34u, 35u, 9u, 20u, 26u, 25u,
    };
    static const char *const expected_names[GE_STAGE_V5_STAGE_COUNT] = {
        "Dam", "Facility", "Runway", "Bunker I", "Silo", "Frigate", "Train",
    };
    static const uint32_t expected_demo_masks[GE_STAGE_V5_STAGE_COUNT] = {
        UINT32_C(0x00000003), UINT32_C(0x0000001c), UINT32_C(0x00000060),
        UINT32_C(0x00000180), UINT32_C(0x00000600), UINT32_C(0x00001800),
        UINT32_C(0x00002000),
    };
    REQUIRE(ge_stage_v5_catalog_count() == GE_STAGE_V5_STAGE_COUNT);
    for (uint32_t index = 0u; index < GE_STAGE_V5_STAGE_COUNT; index++) {
        GEStageCatalogEntryV5 entry;
        REQUIRE(ge_stage_v5_catalog_entry(index, &entry) == GE_STATUS_OK);
        REQUIRE(ge_stage_v5_validate_entry(&entry) == GE_STATUS_OK);
        REQUIRE(entry.stage_id == expected_stage_ids[index]);
        REQUIRE(strcmp(entry.stage_name, expected_names[index]) == 0);
        REQUIRE(entry.demo_mask == expected_demo_masks[index]);
        REQUIRE(entry.background.resource_kind == GE_STAGE_V5_RESOURCE_BACKGROUND);
        REQUIRE(entry.stan.resource_kind == GE_STAGE_V5_RESOURCE_STAN);
        REQUIRE(entry.setup.resource_kind == GE_STAGE_V5_RESOURCE_SETUP);
        REQUIRE(entry.background.asset_handle ==
                ge_stage_v5_resource_handle(entry.stage_id,
                                             GE_STAGE_V5_RESOURCE_BACKGROUND));
        REQUIRE(entry.stan.asset_handle ==
                ge_stage_v5_resource_handle(entry.stage_id,
                                             GE_STAGE_V5_RESOURCE_STAN));
        REQUIRE(entry.setup.asset_handle ==
                ge_stage_v5_resource_handle(entry.stage_id,
                                             GE_STAGE_V5_RESOURCE_SETUP));
        for (uint32_t other = 0u; other < index; other++) {
            GEStageCatalogEntryV5 prior;
            REQUIRE(ge_stage_v5_catalog_entry(other, &prior) == GE_STATUS_OK);
            REQUIRE(prior.background.asset_handle != entry.background.asset_handle);
            REQUIRE(prior.stan.asset_handle != entry.stan.asset_handle);
            REQUIRE(prior.setup.asset_handle != entry.setup.asset_handle);
        }
    }

    GEStageCatalogEntryV5 found;
    REQUIRE(ge_stage_v5_find_stage(26u, &found) == GE_STATUS_OK);
    REQUIRE(strcmp(found.stage_name, "Frigate") == 0);
    REQUIRE(ge_stage_v5_find_stage(99u, &found) == GE_STATUS_RESOURCE_NOT_FOUND);
    REQUIRE(ge_stage_v5_catalog_entry(GE_STAGE_V5_STAGE_COUNT, &found) ==
            GE_STATUS_RESOURCE_NOT_FOUND);
    return 0;
}

static int check_1172_and_asset_view(void)
{
    GEStageCatalogEntryV5 entry;
    REQUIRE(ge_stage_v5_find_stage(33u, &entry) == GE_STATUS_OK);

    uint8_t compressed[5] = {GE_STAGE_V5_1172_MAGIC0,
                             GE_STAGE_V5_1172_MAGIC1,
                             0x10u,
                             0x20u,
                             0x30u};
    GEStageResourceV5 resource = entry.stan;
    resource.source_bytes = (uint32_t)sizeof(compressed);
    resource.decoded_bytes = 3u;

    GEStage1172InfoV5 info;
    REQUIRE(ge_stage_v5_read_1172(compressed,
                                  (uint32_t)sizeof(compressed),
                                  resource.decoded_bytes,
                                  &info) == GE_STATUS_OK);
    REQUIRE(info.prefix_bytes == GE_STAGE_V5_1172_PREFIX_BYTES);
    REQUIRE(info.compressed_payload_bytes == 3u);
    REQUIRE(info.expected_decoded_bytes == 3u);
    REQUIRE(info.source_hash != 0u);

    GEStageAssetViewV5 view;
    REQUIRE(ge_stage_v5_validate_asset(&resource,
                                       compressed,
                                       (uint32_t)sizeof(compressed),
                                       &view) == GE_STATUS_OK);
    REQUIRE(view.asset_handle == resource.asset_handle);
    REQUIRE(view.supplied_bytes == (uint32_t)sizeof(compressed));
    REQUIRE(view.decoded_bytes == 3u);

    uint8_t decoded[3] = {0u, 0u, 0u};
    uint32_t decoded_count = 0u;
    REQUIRE(ge_stage_v5_decompress_1172(&resource,
                                        compressed,
                                        (uint32_t)sizeof(compressed),
                                        decoded,
                                        (uint32_t)sizeof(decoded),
                                        &decoded_count,
                                        copy_inflate) == GE_STATUS_OK);
    REQUIRE(decoded_count == 3u);
    REQUIRE(decoded[0] == 0x10u && decoded[1] == 0x20u && decoded[2] == 0x30u);
    REQUIRE(ge_stage_v5_decompress_1172(&resource,
                                        compressed,
                                        (uint32_t)sizeof(compressed),
                                        decoded,
                                        2u,
                                        &decoded_count,
                                        copy_inflate) == GE_STATUS_INVALID_SIZE);
    REQUIRE(ge_stage_v5_read_1172(compressed + 1u,
                                  (uint32_t)sizeof(compressed) - 1u,
                                  3u,
                                  &info) == GE_STATUS_MALFORMED_STREAM);
    return 0;
}

static int check_resource_packets_and_views(void)
{
    REQUIRE(ge_stage_v5_resource_packet_count() ==
            GE_STAGE_V5_RESOURCE_PACKET_COUNT);

    GEStageResourcePacketV5 first;
    GEStageResourcePacketV5 repeat;
    REQUIRE(ge_stage_v5_resource_packet(0u, &first) == GE_STATUS_OK);
    REQUIRE(ge_stage_v5_resource_packet(0u, &repeat) == GE_STATUS_OK);
    REQUIRE(memcmp(&first, &repeat, sizeof(first)) == 0);
    REQUIRE(first.packet_index == 0u);
    REQUIRE(first.stage_id == 33u);
    REQUIRE(first.resource_kind == GE_STAGE_V5_RESOURCE_BACKGROUND);
    REQUIRE(first.flags == (GE_STAGE_V5_PACKET_FLAG_METADATA_ONLY |
                            GE_STAGE_V5_PACKET_FLAG_NO_PAYLOAD));
    REQUIRE(first.name_bytes == strlen(first.resource_name));
    REQUIRE(first.metadata_hash != 0u);

    GEStageResourcePacketV5 packets[GE_STAGE_V5_RESOURCE_PACKET_COUNT];
    uint32_t packet_count = 0u;
    GEStageDiagnosticV5 diagnostic;
    REQUIRE(ge_stage_v5_copy_resource_packets(
                0u, GE_STAGE_V5_RESOURCE_PACKET_COUNT, packets,
                &packet_count, &diagnostic) == GE_STATUS_OK);
    REQUIRE(packet_count == GE_STAGE_V5_RESOURCE_PACKET_COUNT);
    REQUIRE(diagnostic.code == GE_STAGE_V5_DIAG_NONE);
    for (uint32_t index = 0u; index < packet_count; index++) {
        REQUIRE(packets[index].packet_index == index);
        REQUIRE(packets[index].metadata_hash != 0u);
        if (index != 0u) {
            REQUIRE(packets[index].asset_handle != packets[index - 1u].asset_handle);
        }
    }

    GEStageResourcePacketV5 partial[2];
    packet_count = 0u;
    REQUIRE(ge_stage_v5_copy_resource_packets(
                0u, 2u, partial, &packet_count, &diagnostic) ==
            GE_STATUS_INVALID_SIZE);
    REQUIRE(packet_count == 2u);
    REQUIRE(diagnostic.code == GE_STAGE_V5_DIAG_COPY_OUT);
    REQUIRE(diagnostic.flags == GE_STAGE_V5_DIAG_FLAG_RECOVERABLE);
    REQUIRE(diagnostic.detail0 == GE_STAGE_V5_RESOURCE_PACKET_COUNT);
    REQUIRE(diagnostic.detail1 == 2u);

    packet_count = 0u;
    REQUIRE(ge_stage_v5_copy_resource_packets(
                GE_STAGE_V5_RESOURCE_PACKET_COUNT, 1u, partial,
                &packet_count, &diagnostic) == GE_STATUS_RESOURCE_NOT_FOUND);
    REQUIRE(packet_count == 0u);
    REQUIRE(diagnostic.code == GE_STAGE_V5_DIAG_RANGE);

    GEStageCatalogEntryV5 entry;
    REQUIRE(ge_stage_v5_find_stage(33u, &entry) == GE_STATUS_OK);
    GEStageResourceViewV5 view;
    REQUIRE(ge_stage_v5_make_resource_view(
                &entry.setup, 4096u, entry.setup.decoded_bytes + 16u,
                &view, &diagnostic) == GE_STATUS_OK);
    REQUIRE(view.decoded_base_offset == 4096u);
    REQUIRE(view.decoded_bytes == entry.setup.decoded_bytes);
    REQUIRE(view.metadata_hash != 0u);
    REQUIRE(ge_stage_v5_validate_resource_view(&view) == GE_STATUS_OK);

    REQUIRE(ge_stage_v5_make_resource_view(
                &entry.setup, 4096u, entry.setup.decoded_bytes - 1u,
                &view, &diagnostic) == GE_STATUS_INVALID_SIZE);
    REQUIRE(diagnostic.code == GE_STAGE_V5_DIAG_VIEW);
    REQUIRE(diagnostic.detail0 == entry.setup.decoded_bytes);
    REQUIRE(diagnostic.detail1 == entry.setup.decoded_bytes - 1u);
    return 0;
}

static int check_rebase(void)
{
    uint32_t global_offset = 0u;
    REQUIRE(ge_stage_v5_rebase_local_range(100u, 16u, 4u, 8u,
                                           &global_offset) == GE_STATUS_OK);
    REQUIRE(global_offset == 104u);
    REQUIRE(ge_stage_v5_rebase_local_range(100u, 16u, 12u, 5u,
                                           &global_offset) == GE_STATUS_INVALID_SIZE);
    REQUIRE(ge_stage_v5_rebase_local_range(UINT32_MAX, 1u, 0u, 0u,
                                           &global_offset) == GE_STATUS_INVALID_SIZE);

    GEStageCatalogEntryV5 entry;
    REQUIRE(ge_stage_v5_find_stage(33u, &entry) == GE_STATUS_OK);
    GEStageResourceV5 resource = entry.background;
    resource.source_offset = 1000u;
    resource.source_bytes = 32u;
    resource.decoded_bytes = 32u;
    REQUIRE(ge_stage_v5_rebase_resource_range(&resource, 8u, 4u,
                                              &global_offset) == GE_STATUS_OK);
    REQUIRE(global_offset == 1008u);
    REQUIRE(ge_stage_v5_rebase_resource_range(&entry.stan, 0u, 4u,
                                              &global_offset) ==
            GE_STATUS_UNSUPPORTED_COMMAND);

    const uint8_t words[] = {0x12u, 0x34u, 0x56u, 0x78u, 0x9au};
    uint16_t word16 = 0u;
    uint32_t word32 = 0u;
    REQUIRE(ge_stage_v5_read_be16(words, (uint32_t)sizeof(words), 0u,
                                  &word16) == GE_STATUS_OK);
    REQUIRE(word16 == UINT16_C(0x1234));
    REQUIRE(ge_stage_v5_read_be32(words, (uint32_t)sizeof(words), 1u,
                                  &word32) == GE_STATUS_OK);
    REQUIRE(word32 == UINT32_C(0x3456789a));
    REQUIRE(ge_stage_v5_read_be32(words, (uint32_t)sizeof(words), 2u,
                                  &word32) == GE_STATUS_INVALID_SIZE);
    return 0;
}

static int check_stubs(void)
{
    GEStageDiagnosticV5 diagnostic;
    const uint32_t milestones[] = {
        GE_STAGE_V5_STUB_M24, GE_STAGE_V5_STUB_M25, GE_STAGE_V5_STUB_M26,
        GE_STAGE_V5_STUB_M27,
    };
    const char *phrases[] = {
        "STUB(M24)", "STUB(M25)", "STUB(M26)", "STUB(M27)",
    };
    for (uint32_t index = 0u; index < 4u; index++) {
        REQUIRE(ge_stage_v5_stub_status(milestones[index],
                                        33u,
                                        GE_STAGE_V5_RESOURCE_SETUP,
                                        &diagnostic) ==
                GE_STATUS_UNSUPPORTED_COMMAND);
        REQUIRE(diagnostic.code == GE_STAGE_V5_DIAG_STUB);
        REQUIRE(diagnostic.flags == GE_STAGE_V5_DIAG_FLAG_STUB);
        REQUIRE(strstr(diagnostic.message, phrases[index]) != NULL);
    }
    REQUIRE(ge_stage_v5_stub_status(23u, 33u, 0u, &diagnostic) ==
            GE_STATUS_INVALID_ARGUMENT);
    REQUIRE(ge_stage_v5_stub_status(GE_STAGE_V5_STUB_M25,
                                    99u,
                                    0u,
                                    &diagnostic) == GE_STATUS_RESOURCE_NOT_FOUND);
    return 0;
}

int main(void)
{
    REQUIRE(sizeof(GEStageResourceV5) == 100u);
    REQUIRE(sizeof(GEStageCatalogEntryV5) == 348u);
    REQUIRE(sizeof(GEStage1172InfoV5) == 48u);
    REQUIRE(sizeof(GEStageAssetViewV5) == 64u);
    REQUIRE(check_catalog() == 0);
    REQUIRE(check_1172_and_asset_view() == 0);
    REQUIRE(check_resource_packets_and_views() == 0);
    REQUIRE(check_rebase() == 0);
    REQUIRE(check_stubs() == 0);
    printf("goldeneye_stage_v5_smoke: PASS stages=%u\n",
           GE_STAGE_V5_STAGE_COUNT);
    return 0;
}
