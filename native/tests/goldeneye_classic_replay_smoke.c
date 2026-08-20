#include "goldeneye_native.h"

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum {
    GE_CLASSIC_OP_MTX = 0x01,
    GE_CLASSIC_OP_VTX = 0x04,
    GE_CLASSIC_OP_DL = 0x06,
    GE_CLASSIC_OP_TRI1 = 0xbf,
    GE_CLASSIC_OP_TRI4 = 0xb1,
    GE_CLASSIC_OP_SETTEX = 0xc0,
    GE_CLASSIC_OP_POPMTX = 0xbd,
    GE_CLASSIC_OP_ENDDL = 0xb8,
};

#define REQUIRE(condition)                                                        \
    do {                                                                           \
        if (!(condition)) {                                                        \
            fprintf(stderr, "classic replay requirement failed at %s:%d: %s\n", \
                    __FILE__, __LINE__, #condition);                              \
            return 1;                                                              \
        }                                                                          \
    } while (0)

static uint32_t opcode(GEClassicCommandV2 command)
{
    return command.w0 >> 24;
}

static int find_opcode(const GEClassicReplayFixtureV2 *fixture,
                       uint32_t wanted,
                       uint32_t *command_index)
{
    if (fixture == NULL || command_index == NULL) {
        return 0;
    }
    for (uint32_t index = 0; index < fixture->command_count &&
                             index < GE_CLASSIC_COMMAND_CAPACITY; index++) {
        if (opcode(fixture->commands[index]) == wanted) {
            *command_index = index;
            return 1;
        }
    }
    return 0;
}

static uint32_t count_opcode(const GEClassicReplayFixtureV2 *fixture,
                             uint32_t wanted)
{
    uint32_t count = 0;
    for (uint32_t index = 0; index < fixture->command_count &&
                             index < GE_CLASSIC_COMMAND_CAPACITY; index++) {
        count += opcode(fixture->commands[index]) == wanted ? 1u : 0u;
    }
    return count;
}

static int find_list(const GEClassicReplayFixtureV2 *fixture,
                     uint32_t handle,
                     GEClassicListResourceV2 *list)
{
    if (fixture == NULL || list == NULL) {
        return 0;
    }
    for (uint32_t index = 0; index < fixture->list_count &&
                             index < GE_CLASSIC_LIST_CAPACITY; index++) {
        if (fixture->lists[index].handle == handle) {
            *list = fixture->lists[index];
            return 1;
        }
    }
    return 0;
}

static int find_matrix_for_mtx(const GEClassicReplayFixtureV2 *fixture,
                               uint32_t *command_index,
                               uint32_t *matrix_index)
{
    uint32_t command;
    if (!find_opcode(fixture, GE_CLASSIC_OP_MTX, &command)) {
        return 0;
    }
    for (uint32_t index = 0; index < fixture->matrix_count &&
                             index < GE_CLASSIC_MATRIX_CAPACITY; index++) {
        if (fixture->matrices[index].handle == fixture->commands[command].w1) {
            *command_index = command;
            *matrix_index = index;
            return 1;
        }
    }
    return 0;
}

static int result_is_deterministic(const GEClassicReplayResultV2 *first,
                                   const GEClassicReplayResultV2 *second)
{
    if (first == NULL || second == NULL || first->status != GE_STATUS_OK ||
        second->status != GE_STATUS_OK) {
        return 0;
    }
    if (first->packet_hash == 0u || first->event_hash == 0u ||
        first->state_hash == 0u || first->draw_count == 0u ||
        first->triangle_count == 0u) {
        return 0;
    }
    if (first->packet_hash != second->packet_hash ||
        first->event_hash != second->event_hash ||
        first->state_hash != second->state_hash ||
        first->commands_processed != second->commands_processed ||
        first->list_enters != second->list_enters ||
        first->list_returns != second->list_returns ||
        first->draw_count != second->draw_count ||
        first->vertex_count != second->vertex_count ||
        first->triangle_count != second->triangle_count) {
        return 0;
    }
    return memcmp(first->draws, second->draws, sizeof(first->draws)) == 0;
}

static int check_draw_packets(const GEClassicReplayResultV2 *result)
{
    for (uint32_t draw_index = 0; draw_index < result->draw_count &&
                                   draw_index < GE_CLASSIC_DRAW_CAPACITY;
         draw_index++) {
        const GEClassicDrawPacketV2 *draw = &result->draws[draw_index];
        if (draw->header.abi_version != GE_NATIVE_ABI_VERSION ||
            draw->header.struct_size != sizeof(*draw) ||
            draw->packet_version != GE_CLASSIC_REPLAY_PACKET_VERSION ||
            draw->vertex_count == 0u ||
            draw->vertex_count > GE_CLASSIC_CACHE_CAPACITY ||
            draw->triangle_count == 0u ||
            draw->triangle_count > GE_CLASSIC_TRIANGLE_CAPACITY ||
            draw->packet_hash == 0u ||
            (draw->material_flags & GE_CLASSIC_MATERIAL_VERTEX_COLOR) == 0u ||
            draw->state.state_hash == 0u ||
            draw->transform.transform_hash == 0u) {
            return 0;
        }
        for (uint32_t vertex_index = 0; vertex_index < draw->vertex_count;
             vertex_index++) {
            const GEClassicClipVertexV2 *vertex = &draw->vertices[vertex_index];
            if (vertex->source_vertex >= GE_CLASSIC_VERTEX_CAPACITY ||
                !isfinite(vertex->x) || !isfinite(vertex->y) ||
                !isfinite(vertex->z) || !isfinite(vertex->w)) {
                return 0;
            }
        }
        for (uint32_t triangle_index = 0; triangle_index < draw->triangle_count;
             triangle_index++) {
            const GEClassicTriangleV2 *triangle = &draw->triangles[triangle_index];
            if (triangle->a >= draw->vertex_count ||
                triangle->b >= draw->vertex_count ||
                triangle->c >= draw->vertex_count) {
                return 0;
            }
        }
    }
    return 1;
}

static GEClassicReplayFixtureV2 make_budget_fixture(const GEClassicReplayFixtureV2 *base)
{
    GEClassicReplayFixtureV2 fixture = *base;

    memset(fixture.commands, 0, sizeof(fixture.commands));
    memset(fixture.lists, 0, sizeof(fixture.lists));
    fixture.command_count = 66u;
    fixture.list_count = 2u;
    fixture.root_list_handle = UINT32_C(0x1000);
    fixture.lists[0].handle = UINT32_C(0x2000);
    fixture.lists[0].first_command = 0u;
    fixture.lists[0].command_count = 1u;
    fixture.lists[1].handle = fixture.root_list_handle;
    fixture.lists[1].first_command = 1u;
    fixture.lists[1].command_count = 65u;
    fixture.commands[0].w0 = (uint32_t)GE_CLASSIC_OP_ENDDL << 24;
    for (uint32_t index = 1; index < 65u; index++) {
        fixture.commands[index].w0 =
            ((uint32_t)GE_CLASSIC_OP_DL << 24) | UINT32_C(0x00000000);
        fixture.commands[index].w1 = fixture.lists[0].handle;
    }
    fixture.commands[65].w0 = (uint32_t)GE_CLASSIC_OP_ENDDL << 24;
    return fixture;
}

static GEClassicReplayFixtureV2 make_depth_fixture(const GEClassicReplayFixtureV2 *base)
{
    GEClassicReplayFixtureV2 fixture = *base;

    memset(fixture.commands, 0, sizeof(fixture.commands));
    memset(fixture.lists, 0, sizeof(fixture.lists));
    fixture.command_count = GE_CLASSIC_LIST_CAPACITY;
    fixture.list_count = GE_CLASSIC_LIST_CAPACITY;
    fixture.root_list_handle = UINT32_C(0x3000);
    for (uint32_t index = 0; index < GE_CLASSIC_LIST_CAPACITY; index++) {
        fixture.lists[index].handle = fixture.root_list_handle + index;
        fixture.lists[index].first_command = index;
        fixture.lists[index].command_count = 1u;
    }
    for (uint32_t index = 0; index < GE_CLASSIC_LIST_CAPACITY; index++) {
        if (index + 1u < GE_CLASSIC_LIST_CAPACITY) {
            fixture.commands[index].w0 = (uint32_t)GE_CLASSIC_OP_DL << 24;
            fixture.commands[index].w1 = fixture.lists[index + 1u].handle;
        } else {
            fixture.commands[index].w0 = (uint32_t)GE_CLASSIC_OP_ENDDL << 24;
        }
    }
    return fixture;
}

static int run_prop_blob_if_present(const char *path)
{
    FILE *file = fopen(path, "rb");
    if (file == NULL) {
        printf("classic replay prop blob: SKIP path=%s (asset unavailable)\n", path);
        return 0;
    }

    GEClassicAssetBlobV2 blob;
    memset(&blob, 0, sizeof(blob));
    blob.header.abi_version = GE_NATIVE_ABI_VERSION;
    blob.header.struct_size = (uint32_t)sizeof(blob);
    size_t bytes_read = fread(blob.bytes, 1u, sizeof(blob.bytes), file);
    int read_error = ferror(file);
    int has_extra = fgetc(file) != EOF;
    fclose(file);
    REQUIRE(!read_error);
    REQUIRE(!has_extra);
    REQUIRE(bytes_read == 1488u);
    blob.byte_count = (uint32_t)bytes_read;

    GEClassicReplayResultV2 result = ge_classic_replay_prop_blob(blob);
    REQUIRE(result.status == GE_STATUS_OK);
    REQUIRE(result.vertex_count == 40u);
    REQUIRE(result.triangle_count == 20u);
    REQUIRE(result.draw_count > 0u);
    REQUIRE(result.packet_hash != 0u);
    REQUIRE(result.event_hash != 0u);
    REQUIRE(result.state_hash != 0u);
    REQUIRE(check_draw_packets(&result));
    printf("classic replay prop blob: PASS path=%s vertices=%u triangles=%u packetHash=%llu eventHash=%llu stateHash=%llu\n",
           path, result.vertex_count, result.triangle_count,
           (unsigned long long)result.packet_hash,
           (unsigned long long)result.event_hash,
           (unsigned long long)result.state_hash);
    return 0;
}

int main(int argc, char **argv)
{
    const char *prop_path = argc > 1 ? argv[1] :
        "build/native/classic-prop/Pammo_crate1Z.bin";

    REQUIRE(sizeof(GEClassicCommandV2) == 8u);
    REQUIRE(sizeof(GEClassicListResourceV2) == 16u);
    REQUIRE(sizeof(GEClassicVertexResourceV2) == 16u);
    REQUIRE(sizeof(GEClassicMatrixResourceV2) == 68u);
    REQUIRE(sizeof(GEClassicSegmentResourceV2) == 16u);
    REQUIRE(sizeof(GEClassicViewportV2) == 32u);
    REQUIRE(sizeof(GEClassicAssetBlobV2) == 2064u);
    REQUIRE(sizeof(GEClassicStateSnapshotV2) == 56u);
    REQUIRE(sizeof(GEClassicTransformSnapshotV2) == 168u);
    REQUIRE(sizeof(GEClassicClipVertexV2) == 24u);
    REQUIRE(sizeof(GEClassicTriangleV2) == 8u);

    GEClassicReplayFixtureV2 fixture = ge_classic_nested_fixture();
    REQUIRE(fixture.header.abi_version == GE_NATIVE_ABI_VERSION);
    REQUIRE(fixture.header.struct_size == sizeof(fixture));
    REQUIRE(fixture.packet_version == GE_CLASSIC_REPLAY_PACKET_VERSION);
    REQUIRE(fixture.command_count > 0u &&
            fixture.command_count <= GE_CLASSIC_COMMAND_CAPACITY);
    REQUIRE(fixture.list_count > 0u && fixture.list_count <= GE_CLASSIC_LIST_CAPACITY);
    REQUIRE(fixture.root_list_handle != 0u);
    REQUIRE(count_opcode(&fixture, GE_CLASSIC_OP_DL) > 0u);
    REQUIRE(count_opcode(&fixture, GE_CLASSIC_OP_VTX) > 0u);
    REQUIRE(count_opcode(&fixture, GE_CLASSIC_OP_TRI4) > 0u);
    REQUIRE(count_opcode(&fixture, GE_CLASSIC_OP_ENDDL) > 0u);

    GEClassicReplayResultV2 first = ge_classic_replay_fixture(fixture);
    GEClassicReplayResultV2 second = ge_classic_replay_fixture(fixture);
    REQUIRE(first.header.abi_version == GE_NATIVE_ABI_VERSION);
    REQUIRE(first.header.struct_size == sizeof(first));
    REQUIRE(result_is_deterministic(&first, &second));
    REQUIRE(first.list_enters >= 2u);
    REQUIRE(first.list_returns >= 1u);
    REQUIRE(check_draw_packets(&first));

    printf("classic replay nested: PASS commands=%u enters=%u returns=%u draws=%u vertices=%u triangles=%u packetHash=%llu eventHash=%llu stateHash=%llu\n",
           first.commands_processed, first.list_enters, first.list_returns,
           first.draw_count, first.vertex_count, first.triangle_count,
           (unsigned long long)first.packet_hash,
           (unsigned long long)first.event_hash,
           (unsigned long long)first.state_hash);

    GEClassicReplayFixtureV2 malformed = fixture;
    malformed.header.abi_version++;
    REQUIRE(ge_classic_replay_fixture(malformed).status == GE_STATUS_INVALID_VERSION);
    malformed = fixture;
    malformed.header.struct_size--;
    REQUIRE(ge_classic_replay_fixture(malformed).status == GE_STATUS_INVALID_SIZE);
    malformed = fixture;
    malformed.reserved0 = 1u;
    REQUIRE(ge_classic_replay_fixture(malformed).status == GE_STATUS_RESERVED_BITS);
    malformed = fixture;
    malformed.command_count = 0u;
    REQUIRE(ge_classic_replay_fixture(malformed).status == GE_STATUS_MALFORMED_STREAM);
    malformed = fixture;
    malformed.command_count = GE_CLASSIC_COMMAND_CAPACITY + 1u;
    REQUIRE(ge_classic_replay_fixture(malformed).status == GE_STATUS_MALFORMED_STREAM);

    uint32_t command_index = 0;
    REQUIRE(find_opcode(&fixture, GE_CLASSIC_OP_DL, &command_index));
    malformed = fixture;
    malformed.commands[command_index].w1 = fixture.root_list_handle;
    REQUIRE(ge_classic_replay_fixture(malformed).status == GE_STATUS_REPLAY_CYCLE);

    malformed = fixture;
    malformed.commands[command_index].w1 = UINT32_C(0xdeadcafe);
    REQUIRE(ge_classic_replay_fixture(malformed).status == GE_STATUS_RESOURCE_NOT_FOUND);

    malformed = fixture;
    malformed.commands[command_index].w0 = UINT32_C(0xaa000000);
    REQUIRE(ge_classic_replay_fixture(malformed).status == GE_STATUS_UNSUPPORTED_COMMAND);

    malformed = fixture;
    REQUIRE(find_opcode(&fixture, GE_CLASSIC_OP_MTX, &command_index));
    malformed.commands[command_index].w1 = UINT32_C(0xbad00001);
    REQUIRE(ge_classic_replay_fixture(malformed).status == GE_STATUS_RESOURCE_NOT_FOUND);

    malformed = fixture;
    REQUIRE(find_opcode(&fixture, GE_CLASSIC_OP_POPMTX, &command_index) == 0);
    /* A POPMTX in the root list must reject an empty modelview stack. */
    GEClassicListResourceV2 root;
    REQUIRE(find_list(&fixture, fixture.root_list_handle, &root));
    malformed.commands[root.first_command].w0 = (uint32_t)GE_CLASSIC_OP_POPMTX << 24;
    malformed.commands[root.first_command].w1 = 1u;
    REQUIRE(ge_classic_replay_fixture(malformed).status == GE_STATUS_MATRIX_STACK);

    GEClassicReplayFixtureV2 depth_fixture = make_depth_fixture(&fixture);
    GEClassicReplayResultV2 depth_result = ge_classic_replay_fixture(depth_fixture);
    REQUIRE(depth_result.status == GE_STATUS_REPLAY_DEPTH);

    GEClassicReplayFixtureV2 budget_fixture = make_budget_fixture(&fixture);
    GEClassicReplayResultV2 budget_result = ge_classic_replay_fixture(budget_fixture);
    REQUIRE(budget_result.status == GE_STATUS_REPLAY_BUDGET);

    uint32_t matrix_command = 0;
    uint32_t matrix_index = 0;
    REQUIRE(find_matrix_for_mtx(&fixture, &matrix_command, &matrix_index));
    GEClassicReplayFixtureV2 translated = fixture;
    translated.matrices[matrix_index].values[12] += INT32_C(65536);
    GEClassicReplayResultV2 translated_result = ge_classic_replay_fixture(translated);
    REQUIRE(translated_result.status == GE_STATUS_OK);
    REQUIRE(translated_result.draw_count == first.draw_count);
    REQUIRE(translated_result.draws[0].transform.transform_hash !=
                first.draws[0].transform.transform_hash ||
            translated_result.packet_hash != first.packet_hash);
    REQUIRE(translated_result.packet_hash != first.packet_hash);
    (void)matrix_command;

    REQUIRE(run_prop_blob_if_present(prop_path) == 0);
    puts("goldeneye_classic_replay_smoke: PASS");
    return 0;
}
