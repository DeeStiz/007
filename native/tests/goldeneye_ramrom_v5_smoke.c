#include "ge_ramrom_v5.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define REQUIRE(condition)                                                       \
    do {                                                                          \
        if (!(condition)) {                                                       \
            fprintf(stderr, "ramrom v5 requirement failed at %s:%d: %s\n",      \
                    __FILE__, __LINE__, #condition);                             \
            return 1;                                                             \
        }                                                                         \
    } while (0)

typedef struct ExpectedDemo {
    const char *name;
    uint32_t packet_count;
    uint32_t record_count;
    uint32_t rng_checkpoint_count;
} ExpectedDemo;

static const ExpectedDemo EXPECTED[GE_RAMROM_V5_DEMO_COUNT] = {
    {"ramrom_Dam_1.bin", 454u, 1578u, 453u},
    {"ramrom_Dam_2.bin", 467u, 1508u, 466u},
    {"ramrom_Facility_1.bin", 421u, 1227u, 420u},
    {"ramrom_Facility_2.bin", 559u, 1677u, 558u},
    {"ramrom_Facility_3.bin", 400u, 1358u, 398u},
    {"ramrom_Runway_1.bin", 411u, 1022u, 411u},
    {"ramrom_Runway_2.bin", 419u, 1075u, 415u},
    {"ramrom_BunkerI_1.bin", 500u, 1370u, 498u},
    {"ramrom_BunkerI_2.bin", 797u, 2211u, 795u},
    {"ramrom_Silo_1.bin", 517u, 1572u, 515u},
    {"ramrom_Silo_2.bin", 519u, 1456u, 518u},
    {"ramrom_Frigate_1.bin", 344u, 1241u, 342u},
    {"ramrom_Frigate_2.bin", 402u, 1461u, 400u},
    {"ramrom_Train.bin", 485u, 1709u, 485u},
};

static int read_file(const char *path, uint8_t **out_bytes, uint32_t *out_count)
{
    FILE *file = fopen(path, "rb");
    if (file == NULL) {
        return 0;
    }
    if (fseek(file, 0L, SEEK_END) != 0) {
        fclose(file);
        return 0;
    }
    long file_length = ftell(file);
    if (file_length < 0L || (uint64_t)file_length > UINT32_MAX ||
        fseek(file, 0L, SEEK_SET) != 0) {
        fclose(file);
        return 0;
    }
    uint32_t byte_count = (uint32_t)file_length;
    uint8_t *bytes = (uint8_t *)malloc(byte_count == 0u ? 1u : byte_count);
    if (bytes == NULL) {
        fclose(file);
        return 0;
    }
    size_t read_count = fread(bytes, 1u, byte_count, file);
    int read_error = ferror(file);
    int has_extra = fgetc(file) != EOF;
    fclose(file);
    if (read_error || has_extra || read_count != byte_count) {
        free(bytes);
        return 0;
    }
    *out_bytes = bytes;
    *out_count = byte_count;
    return 1;
}

static int check_one_demo(const char *root, uint32_t index)
{
    GERamRomCatalogEntryV5 catalog;
    REQUIRE(ge_ramrom_v5_catalog_entry(index, &catalog) == GE_STATUS_OK);
    REQUIRE(catalog.demo_id == index + 1u);

    char path[512];
    int path_length = snprintf(path, sizeof(path), "%s/%s", root,
                               EXPECTED[index].name);
    REQUIRE(path_length > 0 && (size_t)path_length < sizeof(path));

    uint8_t *bytes = NULL;
    uint32_t byte_count = 0u;
    REQUIRE(read_file(path, &bytes, &byte_count));
    REQUIRE(byte_count == catalog.asset_file_bytes);

    GERamRomHeaderV5 header;
    REQUIRE(ge_ramrom_v5_read_header(bytes, byte_count, &header) ==
            GE_STATUS_OK);
    REQUIRE(header.stage_id == catalog.stage_id);
    REQUIRE(header.controller_count == catalog.controller_count);
    REQUIRE(header.declared_file_bytes == catalog.declared_file_bytes);
    REQUIRE(header.total_time_ms == catalog.total_time_ms);

    GERamRomParseSummaryV5 summary;
    REQUIRE(ge_ramrom_v5_parse(bytes, byte_count, &summary) == GE_STATUS_OK);
    REQUIRE(summary.flags == GE_RAMROM_V5_PARSE_FLAG_MASK);
    REQUIRE(summary.packet_count == EXPECTED[index].packet_count);
    REQUIRE(summary.record_count == EXPECTED[index].record_count);
    REQUIRE(summary.checksum_valid_count == summary.packet_count);
    REQUIRE(summary.rng_checkpoint_count == EXPECTED[index].rng_checkpoint_count);
    REQUIRE(summary.terminal_offset + GE_RAMROM_V5_TERMINAL_BYTES ==
            header.declared_file_bytes);
    REQUIRE(summary.parsed_bytes == header.declared_file_bytes);
    REQUIRE(summary.trailing_bytes == byte_count - header.declared_file_bytes);
    REQUIRE(summary.first_invalid_packet == UINT32_MAX);
    REQUIRE(summary.recording_hash == catalog.recording_hash);

    GERamRomParseSummaryV5 second_summary;
    REQUIRE(ge_ramrom_v5_parse(bytes, byte_count, &second_summary) ==
            GE_STATUS_OK);
    REQUIRE(memcmp(&summary, &second_summary, sizeof(summary)) == 0);

    uint32_t packet_indices[3] = {
        0u,
        summary.packet_count / 2u,
        summary.packet_count - 1u,
    };
    for (uint32_t packet_index = 0u; packet_index < 3u; packet_index++) {
        GERamRomPacketV5 packet;
        REQUIRE(ge_ramrom_v5_read_packet(bytes,
                                         byte_count,
                                         packet_indices[packet_index],
                                         &packet) == GE_STATUS_OK);
        REQUIRE(packet.packet_index == packet_indices[packet_index]);
        REQUIRE(packet.flags & GE_RAMROM_V5_PACKET_FLAG_CHECKSUM_VALID);
        REQUIRE(packet.flags & GE_RAMROM_V5_PACKET_FLAG_SPEEDFRAMES_VALID);
        REQUIRE(packet.speedframes != 0u);
        REQUIRE(packet.payload_bytes != 0u);

        GERamRomSampleV5 sample;
        REQUIRE(ge_ramrom_v5_copy_sample(bytes,
                                         byte_count,
                                         packet.packet_index,
                                         0u,
                                         0u,
                                         &sample) == GE_STATUS_OK);
        REQUIRE(sample.packet_index == packet.packet_index);
        REQUIRE(ge_ramrom_v5_validate_sample(&sample) == GE_STATUS_OK);
    }

    GERamRomSnapshotV5 snapshot;
    REQUIRE(ge_ramrom_v5_m28_prepare_snapshot(&summary,
                                              &header,
                                              catalog.demo_id,
                                              &snapshot) == GE_STATUS_OK);
    REQUIRE(snapshot.demo_id == catalog.demo_id);
    REQUIRE(snapshot.stage_id == header.stage_id);
    REQUIRE(snapshot.packet_count == summary.packet_count);
    REQUIRE(snapshot.recording_hash == summary.recording_hash);
    REQUIRE(ge_runtime_v5_validate_ramrom(&snapshot) == GE_STATUS_OK);

    free(bytes);
    return 0;
}

static int check_malformed(const char *root)
{
    char path[512];
    int path_length = snprintf(path, sizeof(path), "%s/%s", root,
                               EXPECTED[0].name);
    REQUIRE(path_length > 0 && (size_t)path_length < sizeof(path));

    uint8_t *bytes = NULL;
    uint32_t byte_count = 0u;
    REQUIRE(read_file(path, &bytes, &byte_count));

    GERamRomParseSummaryV5 summary;
    uint8_t *mutated = (uint8_t *)malloc(byte_count);
    REQUIRE(mutated != NULL);

    /* Checksum corruption is an asset mismatch, not a silent replay. */
    memcpy(mutated, bytes, byte_count);
    mutated[GE_RAMROM_V5_HEADER_BYTES + 3u] ^= 1u;
    REQUIRE(ge_ramrom_v5_parse(mutated, byte_count, &summary) ==
            GE_STATUS_ASSET_MISMATCH);
    REQUIRE(summary.first_invalid_packet == 0u);

    /* A missing terminal marker is malformed even if all packets are valid. */
    memcpy(mutated, bytes, byte_count);
    GERamRomHeaderV5 header;
    REQUIRE(ge_ramrom_v5_read_header(bytes, byte_count, &header) ==
            GE_STATUS_OK);
    mutated[header.declared_file_bytes - 1u] = 1u;
    REQUIRE(ge_ramrom_v5_parse(mutated, byte_count, &summary) ==
            GE_STATUS_MALFORMED_STREAM);

    /* Header-declared bytes may not exceed the supplied external asset. */
    memcpy(mutated, bytes, byte_count);
    mutated[0x80u] = 0xffu;
    mutated[0x81u] = 0xffu;
    mutated[0x82u] = 0xffu;
    mutated[0x83u] = 0xffu;
    REQUIRE(ge_ramrom_v5_parse(mutated, byte_count, &summary) ==
            GE_STATUS_MALFORMED_STREAM);

    /* Source speedframes is nonzero for every data packet. */
    memcpy(mutated, bytes, byte_count);
    mutated[GE_RAMROM_V5_HEADER_BYTES] = 0u;
    REQUIRE(ge_ramrom_v5_parse(mutated, byte_count, &summary) ==
            GE_STATUS_MALFORMED_STREAM);

    /* Alignment bytes are part of the guarded asset and must remain zero. */
    memcpy(mutated, bytes, byte_count);
    mutated[header.declared_file_bytes] = 1u;
    REQUIRE(ge_ramrom_v5_read_header(mutated, byte_count, &header) ==
            GE_STATUS_MALFORMED_STREAM);

    /* A truncated declared payload cannot be accepted by the boundary. */
    REQUIRE(ge_ramrom_v5_parse(bytes,
                               header.declared_file_bytes - 1u,
                               &summary) == GE_STATUS_MALFORMED_STREAM);

    free(mutated);
    free(bytes);
    return 0;
}

int main(int argc, char **argv)
{
    const char *root = argc > 1 ? argv[1] : "assets/ramrom";
    REQUIRE(sizeof(GERamRomHeaderV5) == 184u);
    REQUIRE(sizeof(GERamRomPacketV5) == 80u);
    REQUIRE(sizeof(GERamRomSampleV5) == 36u);
    REQUIRE(sizeof(GERamRomParseSummaryV5) == 104u);
    REQUIRE(ge_ramrom_v5_catalog_count() == GE_RAMROM_V5_DEMO_COUNT);

    for (uint32_t index = 0u; index < GE_RAMROM_V5_DEMO_COUNT; index++) {
        REQUIRE(check_one_demo(root, index) == 0);
    }
    REQUIRE(check_malformed(root) == 0);
    printf("goldeneye_ramrom_v5_smoke: PASS demos=%u\n",
           GE_RAMROM_V5_DEMO_COUNT);
    return 0;
}
