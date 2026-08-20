#include "ge_stage_v5.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define REQUIRE(condition)                                                     \
    do {                                                                        \
        if (!(condition)) {                                                     \
            fprintf(stderr, "stage background v5 requirement failed at "      \
                    "%s:%d: %s\n",                                            \
                    __FILE__, __LINE__, #condition);                           \
            return 1;                                                           \
        }                                                                       \
    } while (0)

static int read_file(const char *path, uint8_t **out_bytes, uint32_t *out_count)
{
    if (path == NULL || out_bytes == NULL || out_count == NULL) {
        return 1;
    }
    *out_bytes = NULL;
    *out_count = 0u;
    FILE *file = fopen(path, "rb");
    if (file == NULL || fseek(file, 0L, SEEK_END) != 0) {
        if (file != NULL) {
            fclose(file);
        }
        return 1;
    }
    long file_size = ftell(file);
    if (file_size <= 0L || (uint64_t)file_size > UINT32_MAX ||
        fseek(file, 0L, SEEK_SET) != 0) {
        fclose(file);
        return 1;
    }
    uint8_t *bytes = (uint8_t *)malloc((size_t)file_size);
    if (bytes == NULL ||
        fread(bytes, 1u, (size_t)file_size, file) != (size_t)file_size) {
        free(bytes);
        fclose(file);
        return 1;
    }
    fclose(file);
    *out_bytes = bytes;
    *out_count = (uint32_t)file_size;
    return 0;
}

static int check_stage(const char *path,
                       uint32_t expected_stage_id,
                       uint32_t expected_room_count,
                       uint64_t expected_source_hash,
                       uint64_t expected_room_table_hash,
                       uint64_t expected_metadata_hash)
{
    uint8_t *bytes = NULL;
    uint32_t byte_count = 0u;
    REQUIRE(read_file(path, &bytes, &byte_count) == 0);

    GEStageCatalogEntryV5 entry;
    REQUIRE(ge_stage_v5_find_stage(expected_stage_id, &entry) == GE_STATUS_OK);
    GEStageBackgroundV5 background;
    GEStageDiagnosticV5 diagnostic;
    REQUIRE(ge_stage_v5_parse_background(&entry.background,
                                         bytes,
                                         byte_count,
                                         &background,
                                         &diagnostic) == GE_STATUS_OK);
    REQUIRE(diagnostic.code == GE_STAGE_V5_DIAG_NONE);
    REQUIRE(ge_stage_v5_validate_background(&background) == GE_STATUS_OK);
    REQUIRE(background.stage_id == expected_stage_id);
    REQUIRE(background.source_bytes == byte_count);
    REQUIRE(background.room_count == expected_room_count);
    REQUIRE(background.room_record_bytes == GE_STAGE_V5_BG_ROOM_RECORD_BYTES);
    REQUIRE(background.room_table_offset == GE_STAGE_V5_BG_HEADER_BYTES);
    REQUIRE(background.sentinel_record_offset ==
            background.room_table_offset +
                (expected_room_count + 1u) *
                    GE_STAGE_V5_BG_ROOM_RECORD_BYTES);
    REQUIRE(background.first_payload_offset > background.sentinel_record_offset);
    REQUIRE(background.flags == GE_STAGE_V5_BG_FLAG_MASK);
    REQUIRE(background.source_hash != 0u);
    REQUIRE(background.room_table_hash != 0u);
    REQUIRE(background.metadata_hash != 0u);
    REQUIRE(background.source_hash == expected_source_hash);
    REQUIRE(background.room_table_hash == expected_room_table_hash);
    REQUIRE(background.metadata_hash == expected_metadata_hash);

    GEStageBackgroundV5 repeat_background;
    REQUIRE(ge_stage_v5_parse_background(&entry.background,
                                         bytes,
                                         byte_count,
                                         &repeat_background,
                                         NULL) == GE_STATUS_OK);
    REQUIRE(memcmp(&background, &repeat_background, sizeof(background)) == 0);

    GEStageBackgroundRoomV5 *rooms = (GEStageBackgroundRoomV5 *)calloc(
        expected_room_count,
        sizeof(*rooms));
    REQUIRE(rooms != NULL);
    uint32_t room_count = 0u;
    REQUIRE(ge_stage_v5_copy_background_rooms(&entry.background,
                                              bytes,
                                              byte_count,
                                              0u,
                                              expected_room_count,
                                              rooms,
                                              &room_count,
                                              &repeat_background,
                                              &diagnostic) == GE_STATUS_OK);
    REQUIRE(room_count == expected_room_count);
    REQUIRE(memcmp(&background, &repeat_background, sizeof(background)) == 0);
    for (uint32_t index = 0u; index < room_count; index++) {
        REQUIRE(ge_stage_v5_validate_background_room(&rooms[index]) ==
                GE_STATUS_OK);
        REQUIRE(rooms[index].stage_id == expected_stage_id);
        REQUIRE(rooms[index].room_index == index);
        REQUIRE(rooms[index].source_record_offset ==
                background.room_table_offset +
                    (index + 1u) * GE_STAGE_V5_BG_ROOM_RECORD_BYTES);
        if (rooms[index].point_offset != 0u) {
            REQUIRE(rooms[index].point_bytes != 0u);
            REQUIRE(rooms[index].point_offset + rooms[index].point_bytes <=
                    byte_count);
        }
        if (rooms[index].primary_offset != 0u) {
            REQUIRE(rooms[index].primary_bytes != 0u);
            REQUIRE(rooms[index].primary_offset + rooms[index].primary_bytes <=
                    byte_count);
        }
        if (rooms[index].secondary_offset != 0u) {
            REQUIRE(rooms[index].secondary_bytes != 0u);
            REQUIRE(rooms[index].secondary_offset +
                        rooms[index].secondary_bytes <= byte_count);
        }
        REQUIRE(rooms[index].metadata_hash != 0u);
    }

    GEStageBackgroundRoomV5 first_room;
    REQUIRE(ge_stage_v5_background_room(&entry.background,
                                        bytes,
                                        byte_count,
                                        0u,
                                        &first_room,
                                        &diagnostic) == GE_STATUS_OK);
    REQUIRE(memcmp(&first_room, &rooms[0], sizeof(first_room)) == 0);
    REQUIRE(ge_stage_v5_background_room(&entry.background,
                                        bytes,
                                        byte_count,
                                        expected_room_count,
                                        &first_room,
                                        &diagnostic) ==
            GE_STATUS_RESOURCE_NOT_FOUND);
    REQUIRE(diagnostic.code == GE_STAGE_V5_DIAG_ROOM);

    GEStageBackgroundRoomV5 partial[2];
    room_count = 0u;
    REQUIRE(ge_stage_v5_copy_background_rooms(&entry.background,
                                              bytes,
                                              byte_count,
                                              0u,
                                              2u,
                                              partial,
                                              &room_count,
                                              NULL,
                                              &diagnostic) == GE_STATUS_INVALID_SIZE);
    REQUIRE(room_count == 2u);
    REQUIRE(diagnostic.code == GE_STAGE_V5_DIAG_COPY_OUT);
    REQUIRE(diagnostic.detail0 == expected_room_count);
    REQUIRE(diagnostic.detail1 == 2u);

    uint8_t *mutated = (uint8_t *)malloc(byte_count);
    REQUIRE(mutated != NULL);
    memcpy(mutated, bytes, byte_count);
    mutated[4] = 0x0eu;
    REQUIRE(ge_stage_v5_parse_background(&entry.background,
                                         mutated,
                                         byte_count,
                                         &background,
                                         &diagnostic) ==
            GE_STATUS_MALFORMED_STREAM);
    REQUIRE(diagnostic.code == GE_STAGE_V5_DIAG_BACKGROUND);
    memcpy(mutated, bytes, byte_count);
    mutated[background.room_table_offset + GE_STAGE_V5_BG_ROOM_RECORD_BYTES] =
        0x0fu;
    mutated[background.room_table_offset + GE_STAGE_V5_BG_ROOM_RECORD_BYTES +
            1u] = 0xffu;
    mutated[background.room_table_offset + GE_STAGE_V5_BG_ROOM_RECORD_BYTES +
            2u] = 0xffu;
    mutated[background.room_table_offset + GE_STAGE_V5_BG_ROOM_RECORD_BYTES +
            3u] = 0xffu;
    REQUIRE(ge_stage_v5_parse_background(&entry.background,
                                         mutated,
                                         byte_count,
                                         &background,
                                         &diagnostic) == GE_STATUS_INVALID_SIZE);
    REQUIRE(diagnostic.code == GE_STAGE_V5_DIAG_OFFSET);
    free(mutated);
    free(rooms);
    free(bytes);
    return 0;
}

int main(int argc, char **argv)
{
    static const uint32_t expected_stage_ids[GE_STAGE_V5_STAGE_COUNT] = {
        33u, 34u, 35u, 9u, 20u, 26u, 25u,
    };
    static const uint32_t expected_room_counts[GE_STAGE_V5_STAGE_COUNT] = {
        137u, 78u, 18u, 31u, 87u, 59u, 58u,
    };
    static const uint64_t expected_source_hashes[GE_STAGE_V5_STAGE_COUNT] = {
        UINT64_C(13772388262779706778), UINT64_C(18393440616049035519),
        UINT64_C(147778045433520219), UINT64_C(3489476540625005442),
        UINT64_C(11028776210882489426), UINT64_C(12545021338253015276),
        UINT64_C(8700154666190650892),
    };
    static const uint64_t expected_room_table_hashes[GE_STAGE_V5_STAGE_COUNT] = {
        UINT64_C(5799064904142064500), UINT64_C(13787477641701496500),
        UINT64_C(15131005210215780144), UINT64_C(496135811106645242),
        UINT64_C(12493403947411408999), UINT64_C(9563445360389526671),
        UINT64_C(1363952796435995410),
    };
    static const uint64_t expected_metadata_hashes[GE_STAGE_V5_STAGE_COUNT] = {
        UINT64_C(1564857419577113517), UINT64_C(18390320103922053748),
        UINT64_C(15084202602732909489), UINT64_C(17234933945300004813),
        UINT64_C(5057484777161593133), UINT64_C(11972225530125446063),
        UINT64_C(14698640648992205561),
    };
    REQUIRE(argc == (int)GE_STAGE_V5_STAGE_COUNT + 1);
    for (uint32_t index = 0u; index < GE_STAGE_V5_STAGE_COUNT; index++) {
        REQUIRE(check_stage(argv[index + 1u],
                            expected_stage_ids[index],
                            expected_room_counts[index],
                            expected_source_hashes[index],
                            expected_room_table_hashes[index],
                            expected_metadata_hashes[index]) == 0);
    }
    printf("goldeneye_stage_background_v5_smoke: PASS stages=%u\n",
           GE_STAGE_V5_STAGE_COUNT);
    return 0;
}
