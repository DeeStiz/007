#include "goldeneye_native.h"

#include <math.h>
#include <stddef.h>
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
    GE_CLASSIC_OP_MOVEMEM = 0xdc,
    GE_CLASSIC_OP_MOVEWORD = 0xbc,
    GE_CLASSIC_OP_SETOTHERMODE_H = 0xba,
    GE_CLASSIC_OP_SETOTHERMODE_L = 0xb9,
    GE_CLASSIC_OP_TEXTURE = 0xbb,
    GE_CLASSIC_OP_SETGEOMETRYMODE = 0xb7,
    GE_CLASSIC_OP_CLEARGEOMETRYMODE = 0xb6,
    GE_CLASSIC_OP_PIPE_SYNC = 0xe7,
    GE_CLASSIC_OP_LOAD_SYNC = 0xe6,
    GE_CLASSIC_OP_TILE_SYNC = 0xe8,
    GE_CLASSIC_OP_FULL_SYNC = 0xe9,
    GE_CLASSIC_OP_SETCOMBINE = 0xfc,
    GE_CLASSIC_OP_SETOTHERMODE_H_ALT = 0xe3,
    GE_CLASSIC_OP_SETOTHERMODE_L_ALT = 0xe2,
    /* Keep replay bounded well below the fixed command-array capacity. */
    GE_CLASSIC_COMMAND_BUDGET = 64u,
    GE_CLASSIC_PROP_SIZE = 1488u,
    GE_CLASSIC_PROP_VERTEX_OFFSET = 0x0a8u,
    GE_CLASSIC_PROP_COMMAND_OFFSET = 0x518u,
    GE_CLASSIC_PROP_COMMAND_COUNT = 22u,
};

typedef struct GEClassicListFrame {
    uint32_t handle;
    uint32_t next_command;
    uint32_t end_command;
} GEClassicListFrame;

typedef struct GEClassicReplayEngine {
    GEClassicReplayFixtureV2 fixture;
    GEClassicReplayResultV2 result;
    GEClassicListFrame frames[GE_CLASSIC_STACK_CAPACITY];
    uint32_t frame_depth;
    uint32_t active_handles[GE_CLASSIC_STACK_CAPACITY];
    GEVertexV1 vertex_cache[GE_CLASSIC_CACHE_CAPACITY];
    uint8_t vertex_valid[GE_CLASSIC_CACHE_CAPACITY];
    float modelview[GE_CLASSIC_STACK_CAPACITY][16];
    float projection[GE_CLASSIC_STACK_CAPACITY][16];
    uint32_t modelview_depth;
    uint32_t projection_depth;
    GEClassicViewportV2 viewport;
    GEClassicStateSnapshotV2 state;
    uint32_t state_dirty;
    uint32_t current_draw_index;
    uint32_t has_current_draw;
    uint32_t current_draw_epoch;
    uint32_t draw_epoch;
    uint32_t current_command_offset;
    uint32_t current_list_handle;
    uint32_t current_list_depth;
    uint32_t last_valid_vertex;
    uint64_t event_hash;
    uint64_t state_hash;
    uint64_t packet_hash;
} GEClassicReplayEngine;

static uint16_t ge_classic_be16(const uint8_t *bytes)
{
    return (uint16_t)(((uint16_t)bytes[0] << 8) | bytes[1]);
}

static int16_t ge_classic_be16s(const uint8_t *bytes)
{
    return (int16_t)ge_classic_be16(bytes);
}

static uint32_t ge_classic_be32(const uint8_t *bytes)
{
    return ((uint32_t)bytes[0] << 24) |
           ((uint32_t)bytes[1] << 16) |
           ((uint32_t)bytes[2] << 8) |
           (uint32_t)bytes[3];
}

static uint64_t ge_classic_hash_byte(uint64_t hash, uint8_t value)
{
    return (hash ^ (uint64_t)value) * UINT64_C(1099511628211);
}

static uint64_t ge_classic_hash_u32(uint64_t hash, uint32_t value)
{
    hash = ge_classic_hash_byte(hash, (uint8_t)(value & 0xffu));
    hash = ge_classic_hash_byte(hash, (uint8_t)((value >> 8) & 0xffu));
    hash = ge_classic_hash_byte(hash, (uint8_t)((value >> 16) & 0xffu));
    return ge_classic_hash_byte(hash, (uint8_t)(value >> 24));
}

static uint64_t ge_classic_hash_u64(uint64_t hash, uint64_t value)
{
    hash = ge_classic_hash_u32(hash, (uint32_t)value);
    return ge_classic_hash_u32(hash, (uint32_t)(value >> 32));
}

static uint64_t ge_classic_hash_bytes(uint64_t hash, const void *data, size_t size)
{
    const uint8_t *bytes = (const uint8_t *)data;
    for (size_t index = 0; index < size; index++) {
        hash = ge_classic_hash_byte(hash, bytes[index]);
    }
    return hash;
}

static float ge_classic_q16(int32_t value)
{
    return (float)value / 65536.0f;
}

static void ge_classic_identity(float matrix[16])
{
    memset(matrix, 0, sizeof(float) * 16u);
    matrix[0] = 1.0f;
    matrix[5] = 1.0f;
    matrix[10] = 1.0f;
    matrix[15] = 1.0f;
}

static void ge_classic_prop_projection(float matrix[16])
{
    /* The host fixture uses a deterministic diagnostic camera for the prop. */
    ge_classic_identity(matrix);
    matrix[0] = 1.0f / 800.0f;
    matrix[5] = 1.0f / 300.0f;
    matrix[10] = 1.0f / 600.0f;
}

static void ge_classic_matrix_from_resource(const GEClassicMatrixResourceV2 *resource,
                                            float matrix[16])
{
    for (uint32_t index = 0; index < 16u; index++) {
        matrix[index] = ge_classic_q16(resource->values[index]);
    }
}

static void ge_classic_matrix_copy(float destination[16], const float source[16])
{
    memcpy(destination, source, sizeof(float) * 16u);
}

static void ge_classic_matrix_mul(const float left[16], const float right[16], float result[16])
{
    float temporary[16];
    for (uint32_t row = 0; row < 4u; row++) {
        for (uint32_t column = 0; column < 4u; column++) {
            float value = 0.0f;
            for (uint32_t element = 0; element < 4u; element++) {
                value += left[row * 4u + element] * right[element * 4u + column];
            }
            temporary[row * 4u + column] = value;
        }
    }
    ge_classic_matrix_copy(result, temporary);
}

static void ge_classic_matrix_vec4(const float matrix[16],
                                   float x,
                                   float y,
                                   float z,
                                   float w,
                                   float result[4])
{
    for (uint32_t row = 0; row < 4u; row++) {
        result[row] = matrix[row * 4u + 0u] * x +
                      matrix[row * 4u + 1u] * y +
                      matrix[row * 4u + 2u] * z +
                      matrix[row * 4u + 3u] * w;
    }
}

static GEClassicStateSnapshotV2 ge_classic_zero_state(void)
{
    GEClassicStateSnapshotV2 state;
    memset(&state, 0, sizeof(state));
    state.material_flags = GE_CLASSIC_MATERIAL_VERTEX_COLOR |
                           GE_CLASSIC_MATERIAL_TEXTURE_STATE_DEFERRED;
    return state;
}

static uint64_t ge_classic_state_hash(const GEClassicStateSnapshotV2 *state)
{
    uint64_t hash = UINT64_C(1469598103934665603);
    hash = ge_classic_hash_u32(hash, state->geometry_mode);
    hash = ge_classic_hash_u32(hash, state->other_mode_h);
    hash = ge_classic_hash_u32(hash, state->other_mode_l);
    hash = ge_classic_hash_u32(hash, state->combine_w0);
    hash = ge_classic_hash_u32(hash, state->combine_w1);
    hash = ge_classic_hash_u32(hash, state->texture_id);
    hash = ge_classic_hash_u32(hash, state->texture_state);
    hash = ge_classic_hash_u32(hash, state->matrix_handle);
    hash = ge_classic_hash_u32(hash, state->material_flags);
    return hash;
}

static void ge_classic_set_error(GEClassicReplayEngine *engine,
                                 GEStatusV1 status,
                                 uint32_t opcode,
                                 uint32_t offset)
{
    engine->result.status = status;
    engine->result.error_opcode = opcode;
    engine->result.error_offset = offset;
    engine->result.error_list_handle = engine->current_list_handle;
    engine->result.error_list_depth = engine->current_list_depth;
}

static const GEClassicListResourceV2 *ge_classic_find_list(const GEClassicReplayFixtureV2 *fixture,
                                                            uint32_t handle)
{
    for (uint32_t index = 0; index < fixture->list_count; index++) {
        if (fixture->lists[index].handle == handle) {
            return &fixture->lists[index];
        }
    }
    return NULL;
}

static const GEClassicVertexResourceV2 *ge_classic_find_vertex_resource(const GEClassicReplayFixtureV2 *fixture,
                                                                          uint32_t handle)
{
    for (uint32_t index = 0; index < fixture->vertex_resource_count; index++) {
        if (fixture->vertex_resources[index].handle == handle) {
            return &fixture->vertex_resources[index];
        }
    }
    return NULL;
}

static const GEClassicMatrixResourceV2 *ge_classic_find_matrix(const GEClassicReplayFixtureV2 *fixture,
                                                                uint32_t handle)
{
    for (uint32_t index = 0; index < fixture->matrix_count; index++) {
        if (fixture->matrices[index].handle == handle) {
            return &fixture->matrices[index];
        }
    }
    return NULL;
}

static uint32_t ge_classic_resolve_segment_handle(const GEClassicReplayEngine *engine,
                                                  uint32_t raw_handle)
{
    uint32_t segment_number = (raw_handle >> 24) & 0xffu;
    uint32_t segment_offset = raw_handle & UINT32_C(0x00ffffff);
    for (uint32_t index = 0; index < engine->fixture.segment_count; index++) {
        const GEClassicSegmentResourceV2 *segment = &engine->fixture.segments[index];
        if (segment->segment == segment_number) {
            return segment->resource_handle + segment->byte_offset + segment_offset;
        }
    }
    return raw_handle;
}

static int ge_classic_active_handle(const GEClassicReplayEngine *engine, uint32_t handle)
{
    for (uint32_t index = 0; index < engine->frame_depth; index++) {
        if (engine->active_handles[index] == handle) {
            return 1;
        }
    }
    return 0;
}

static uint64_t ge_classic_transform_hash(const GEClassicReplayEngine *engine)
{
    uint64_t hash = UINT64_C(1469598103934665603);
    hash = ge_classic_hash_bytes(hash, engine->modelview[engine->modelview_depth - 1u], sizeof(float) * 16u);
    hash = ge_classic_hash_bytes(hash, engine->projection[engine->projection_depth - 1u], sizeof(float) * 16u);
    hash = ge_classic_hash_bytes(hash, &engine->viewport, sizeof(engine->viewport));
    return hash;
}

static void ge_classic_fill_transform(const GEClassicReplayEngine *engine,
                                      GEClassicTransformSnapshotV2 *snapshot)
{
    memset(snapshot, 0, sizeof(*snapshot));
    ge_classic_matrix_copy(snapshot->modelview,
                           engine->modelview[engine->modelview_depth - 1u]);
    ge_classic_matrix_copy(snapshot->projection,
                           engine->projection[engine->projection_depth - 1u]);
    snapshot->viewport[0] = ge_classic_q16(engine->viewport.scale_x);
    snapshot->viewport[1] = ge_classic_q16(engine->viewport.scale_y);
    snapshot->viewport[2] = ge_classic_q16(engine->viewport.scale_z);
    snapshot->viewport[3] = ge_classic_q16(engine->viewport.translate_x);
    snapshot->viewport[4] = ge_classic_q16(engine->viewport.translate_y);
    snapshot->viewport[5] = ge_classic_q16(engine->viewport.translate_z);
    snapshot->viewport[6] = (float)engine->viewport.width;
    snapshot->viewport[7] = (float)engine->viewport.height;
    snapshot->transform_hash = ge_classic_transform_hash(engine);
}

static void ge_classic_transform_vertex(const GEClassicReplayEngine *engine,
                                        const GEVertexV1 *source,
                                        GEClassicClipVertexV2 *destination,
                                        uint32_t source_index)
{
    float model[4];
    float clip[4];
    const float *modelview = engine->modelview[engine->modelview_depth - 1u];
    const float *projection = engine->projection[engine->projection_depth - 1u];
    ge_classic_matrix_vec4(modelview,
                           (float)source->x,
                           (float)source->y,
                           (float)source->z,
                           1.0f,
                           model);
    ge_classic_matrix_vec4(projection, model[0], model[1], model[2], model[3], clip);
    float w = fabsf(clip[3]) < 0.000001f ? 1.0f : clip[3];
    float ndc_x = clip[0] / w;
    float ndc_y = clip[1] / w;
    float ndc_z = clip[2] / w;
    float viewport_x = ndc_x * ge_classic_q16(engine->viewport.scale_x) +
                       ge_classic_q16(engine->viewport.translate_x);
    float viewport_y = ndc_y * ge_classic_q16(engine->viewport.scale_y) +
                       ge_classic_q16(engine->viewport.translate_y);
    float viewport_z = ndc_z * ge_classic_q16(engine->viewport.scale_z) +
                       ge_classic_q16(engine->viewport.translate_z);
    float width = engine->viewport.width == 0u ? 1.0f : (float)engine->viewport.width;
    float height = engine->viewport.height == 0u ? 1.0f : (float)engine->viewport.height;

    destination->x = viewport_x * 2.0f / width - 1.0f;
    destination->y = 1.0f - viewport_y * 2.0f / height;
    destination->z = viewport_z;
    destination->w = 1.0f;
    destination->r = source->r;
    destination->g = source->g;
    destination->b = source->b;
    destination->a = source->a;
    destination->source_vertex = source_index;
}

static void ge_classic_mark_state_dirty(GEClassicReplayEngine *engine)
{
    engine->state_dirty = 1u;
    engine->draw_epoch++;
}

static GEStatusV1 ge_classic_begin_draw(GEClassicReplayEngine *engine)
{
    if (engine->has_current_draw && !engine->state_dirty) {
        return GE_STATUS_OK;
    }
    if (engine->result.draw_count >= GE_CLASSIC_DRAW_CAPACITY) {
        return GE_STATUS_REPLAY_BUDGET;
    }

    GEClassicDrawPacketV2 *draw = &engine->result.draws[engine->result.draw_count];
    memset(draw, 0, sizeof(*draw));
    draw->header.abi_version = GE_NATIVE_ABI_VERSION;
    draw->header.struct_size = (uint32_t)sizeof(*draw);
    draw->packet_version = GE_CLASSIC_REPLAY_PACKET_VERSION;
    draw->source_list_handle = engine->current_list_handle;
    draw->source_command_offset = engine->current_command_offset;
    draw->list_depth = engine->current_list_depth;
    draw->material_flags = engine->state.material_flags;
    draw->state = engine->state;
    draw->state.list_handle = engine->current_list_handle;
    draw->state.command_offset = engine->current_command_offset;
    draw->state.list_depth = engine->current_list_depth;
    draw->state.state_hash = ge_classic_state_hash(&draw->state);
    ge_classic_fill_transform(engine, &draw->transform);

    uint32_t highest_vertex = 0u;
    for (uint32_t index = 0; index < GE_CLASSIC_CACHE_CAPACITY; index++) {
        if (engine->vertex_valid[index]) {
            ge_classic_transform_vertex(engine,
                                         &engine->vertex_cache[index],
                                         &draw->vertices[index],
                                         index);
            highest_vertex = index + 1u;
        }
    }
    draw->vertex_count = highest_vertex;
    engine->current_draw_index = engine->result.draw_count;
    engine->result.draw_count++;
    engine->has_current_draw = 1u;
    engine->current_draw_epoch = engine->draw_epoch;
    engine->state_dirty = 0u;
    engine->state_hash = ge_classic_hash_u64(engine->state_hash,
                                             draw->state.state_hash);
    return GE_STATUS_OK;
}

static GEStatusV1 ge_classic_emit_triangle(GEClassicReplayEngine *engine,
                                           uint32_t a,
                                           uint32_t b,
                                           uint32_t c,
                                           uint32_t opcode)
{
    if (a >= GE_CLASSIC_CACHE_CAPACITY || b >= GE_CLASSIC_CACHE_CAPACITY ||
        c >= GE_CLASSIC_CACHE_CAPACITY || !engine->vertex_valid[a] ||
        !engine->vertex_valid[b] || !engine->vertex_valid[c]) {
        return GE_STATUS_VERTEX_OUT_OF_RANGE;
    }
    GEStatusV1 status = ge_classic_begin_draw(engine);
    if (status != GE_STATUS_OK) {
        return status;
    }
    GEClassicDrawPacketV2 *draw = &engine->result.draws[engine->current_draw_index];
    if (draw->triangle_count >= GE_CLASSIC_TRIANGLE_CAPACITY) {
        return GE_STATUS_REPLAY_BUDGET;
    }
    GEClassicTriangleV2 *triangle = &draw->triangles[draw->triangle_count++];
    triangle->a = (uint16_t)a;
    triangle->b = (uint16_t)b;
    triangle->c = (uint16_t)c;
    triangle->reserved = 0u;
    if (draw->vertex_count <= a) draw->vertex_count = a + 1u;
    if (draw->vertex_count <= b) draw->vertex_count = b + 1u;
    if (draw->vertex_count <= c) draw->vertex_count = c + 1u;
    engine->result.triangle_count++;
    engine->event_hash = ge_classic_hash_u32(engine->event_hash, opcode);
    engine->event_hash = ge_classic_hash_u32(engine->event_hash, a);
    engine->event_hash = ge_classic_hash_u32(engine->event_hash, b);
    engine->event_hash = ge_classic_hash_u32(engine->event_hash, c);
    return GE_STATUS_OK;
}

static void ge_classic_finalize_draws(GEClassicReplayEngine *engine)
{
    uint64_t packet_hash = UINT64_C(1469598103934665603);
    for (uint32_t draw_index = 0; draw_index < engine->result.draw_count; draw_index++) {
        GEClassicDrawPacketV2 *draw = &engine->result.draws[draw_index];
        uint64_t hash = UINT64_C(1469598103934665603);
        hash = ge_classic_hash_u32(hash, draw->source_list_handle);
        hash = ge_classic_hash_u32(hash, draw->source_command_offset);
        hash = ge_classic_hash_u32(hash, draw->list_depth);
        hash = ge_classic_hash_u32(hash, draw->material_flags);
        hash = ge_classic_hash_u32(hash, draw->vertex_count);
        hash = ge_classic_hash_u32(hash, draw->triangle_count);
        hash = ge_classic_hash_u64(hash, draw->state.state_hash);
        hash = ge_classic_hash_u64(hash, draw->transform.transform_hash);
        hash = ge_classic_hash_bytes(hash, draw->vertices,
                                     sizeof(GEClassicClipVertexV2) * draw->vertex_count);
        hash = ge_classic_hash_bytes(hash, draw->triangles,
                                     sizeof(GEClassicTriangleV2) * draw->triangle_count);
        draw->packet_hash = hash;
        packet_hash = ge_classic_hash_u64(packet_hash, hash);
        packet_hash = ge_classic_hash_u32(packet_hash, draw->triangle_count);
    }
    engine->result.packet_hash = packet_hash;
    engine->result.event_hash = engine->event_hash;
    engine->result.state_hash = engine->state_hash;
}

static void ge_classic_init_result(GEClassicReplayEngine *engine)
{
    memset(&engine->result, 0, sizeof(engine->result));
    engine->result.header.abi_version = GE_NATIVE_ABI_VERSION;
    engine->result.header.struct_size = (uint32_t)sizeof(engine->result);
    engine->result.status = GE_STATUS_OK;
    engine->event_hash = UINT64_C(1469598103934665603);
    engine->state_hash = UINT64_C(1469598103934665603);
}

static GEStatusV1 ge_classic_validate_fixture(const GEClassicReplayFixtureV2 *fixture)
{
    if (fixture->header.abi_version != GE_NATIVE_ABI_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    if (fixture->header.struct_size != sizeof(*fixture)) {
        return GE_STATUS_INVALID_SIZE;
    }
    if (fixture->packet_version != GE_CLASSIC_REPLAY_PACKET_VERSION ||
        fixture->reserved0 != 0u) {
        return GE_STATUS_RESERVED_BITS;
    }
    if (fixture->command_count == 0u || fixture->command_count > GE_CLASSIC_COMMAND_CAPACITY ||
        fixture->list_count == 0u || fixture->list_count > GE_CLASSIC_LIST_CAPACITY ||
        fixture->vertex_count > GE_CLASSIC_VERTEX_CAPACITY ||
        fixture->vertex_resource_count > GE_CLASSIC_VERTEX_RESOURCE_CAPACITY ||
        fixture->matrix_count > GE_CLASSIC_MATRIX_CAPACITY ||
        fixture->segment_count > GE_CLASSIC_SEGMENT_CAPACITY ||
        fixture->root_list_handle == 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    for (uint32_t index = 0; index < fixture->list_count; index++) {
        const GEClassicListResourceV2 *list = &fixture->lists[index];
        if (list->handle == 0u || list->command_count == 0u ||
            list->first_command > fixture->command_count ||
            list->command_count > fixture->command_count - list->first_command) {
            return GE_STATUS_MALFORMED_STREAM;
        }
    }
    for (uint32_t index = 0; index < fixture->vertex_resource_count; index++) {
        const GEClassicVertexResourceV2 *resource = &fixture->vertex_resources[index];
        if (resource->handle == 0u || resource->reserved != 0u ||
            resource->first_vertex > fixture->vertex_count ||
            resource->vertex_count > fixture->vertex_count - resource->first_vertex) {
            return GE_STATUS_MALFORMED_STREAM;
        }
    }
    for (uint32_t index = 0; index < fixture->segment_count; index++) {
        if (fixture->segments[index].reserved != 0u || fixture->segments[index].segment >= 16u) {
            return GE_STATUS_MALFORMED_STREAM;
        }
    }
    return GE_STATUS_OK;
}

static void ge_classic_init_engine(GEClassicReplayEngine *engine,
                                   const GEClassicReplayFixtureV2 *fixture)
{
    memset(engine, 0, sizeof(*engine));
    engine->fixture = *fixture;
    ge_classic_init_result(engine);
    engine->state = ge_classic_zero_state();
    engine->viewport = fixture->viewport;
    if (engine->viewport.width == 0u) engine->viewport.width = 960u;
    if (engine->viewport.height == 0u) engine->viewport.height = 540u;
    if (engine->viewport.scale_x == 0) engine->viewport.scale_x = 480 * 65536;
    if (engine->viewport.scale_y == 0) engine->viewport.scale_y = 270 * 65536;
    if (engine->viewport.scale_z == 0) engine->viewport.scale_z = 65536;
    if (engine->viewport.translate_x == 0) engine->viewport.translate_x = 480 * 65536;
    if (engine->viewport.translate_y == 0) engine->viewport.translate_y = 270 * 65536;
    ge_classic_identity(engine->modelview[0]);
    ge_classic_prop_projection(engine->projection[0]);
    engine->modelview_depth = 1u;
    engine->projection_depth = 1u;
    engine->state_dirty = 1u;
    engine->current_draw_index = 0u;
}

static GEStatusV1 ge_classic_push_list(GEClassicReplayEngine *engine,
                                       uint32_t handle,
                                       uint32_t opcode,
                                       uint32_t offset)
{
    const GEClassicListResourceV2 *list = ge_classic_find_list(&engine->fixture, handle);
    if (list == NULL) {
        ge_classic_set_error(engine, GE_STATUS_RESOURCE_NOT_FOUND, opcode, offset);
        return GE_STATUS_RESOURCE_NOT_FOUND;
    }
    if (ge_classic_active_handle(engine, handle)) {
        ge_classic_set_error(engine, GE_STATUS_REPLAY_CYCLE, opcode, offset);
        return GE_STATUS_REPLAY_CYCLE;
    }
    /* Keep one frame slot reserved for the root so an adversarial chain
       cannot consume every diagnostic frame before the overflow is reported. */
    if (engine->frame_depth >= GE_CLASSIC_STACK_CAPACITY - 1u) {
        ge_classic_set_error(engine, GE_STATUS_REPLAY_DEPTH, opcode, offset);
        return GE_STATUS_REPLAY_DEPTH;
    }
    GEClassicListFrame *frame = &engine->frames[engine->frame_depth];
    frame->handle = handle;
    frame->next_command = list->first_command;
    frame->end_command = list->first_command + list->command_count;
    engine->active_handles[engine->frame_depth] = handle;
    engine->frame_depth++;
    engine->result.list_enters++;
    engine->event_hash = ge_classic_hash_u32(engine->event_hash, UINT32_C(0x454e5445));
    engine->event_hash = ge_classic_hash_u32(engine->event_hash, handle);
    return GE_STATUS_OK;
}

static GEStatusV1 ge_classic_branch_list(GEClassicReplayEngine *engine,
                                         uint32_t handle,
                                         uint32_t opcode,
                                         uint32_t offset)
{
    const GEClassicListResourceV2 *list = ge_classic_find_list(&engine->fixture, handle);
    if (list == NULL) {
        ge_classic_set_error(engine, GE_STATUS_RESOURCE_NOT_FOUND, opcode, offset);
        return GE_STATUS_RESOURCE_NOT_FOUND;
    }
    if (ge_classic_active_handle(engine, handle)) {
        ge_classic_set_error(engine, GE_STATUS_REPLAY_CYCLE, opcode, offset);
        return GE_STATUS_REPLAY_CYCLE;
    }
    if (engine->frame_depth == 0u) {
        ge_classic_set_error(engine, GE_STATUS_INVALID_STATE, opcode, offset);
        return GE_STATUS_INVALID_STATE;
    }
    GEClassicListFrame *frame = &engine->frames[engine->frame_depth - 1u];
    frame->handle = handle;
    frame->next_command = list->first_command;
    frame->end_command = list->first_command + list->command_count;
    engine->active_handles[engine->frame_depth - 1u] = handle;
    engine->result.list_enters++;
    engine->event_hash = ge_classic_hash_u32(engine->event_hash, UINT32_C(0x4252414e));
    engine->event_hash = ge_classic_hash_u32(engine->event_hash, handle);
    return GE_STATUS_OK;
}

static GEStatusV1 ge_classic_matrix_command(GEClassicReplayEngine *engine,
                                            GEClassicCommandV2 command,
                                            uint32_t opcode,
                                            uint32_t offset)
{
    uint32_t resolved_handle = ge_classic_resolve_segment_handle(engine, command.w1);
    const GEClassicMatrixResourceV2 *resource = ge_classic_find_matrix(&engine->fixture, resolved_handle);
    if (resource == NULL && resolved_handle != command.w1) {
        resource = ge_classic_find_matrix(&engine->fixture, command.w1);
    }
    if (resource == NULL) {
        ge_classic_set_error(engine, GE_STATUS_RESOURCE_NOT_FOUND, opcode, offset);
        return GE_STATUS_RESOURCE_NOT_FOUND;
    }
    uint32_t flags = (command.w0 >> 16) & 0xffu;
    uint32_t projection = flags & 0x01u;
    uint32_t load = flags & 0x02u;
    uint32_t push = flags & 0x04u;
    float matrix[16];
    ge_classic_matrix_from_resource(resource, matrix);
    float (*stack)[16] = projection ? engine->projection : engine->modelview;
    uint32_t *depth = projection ? &engine->projection_depth : &engine->modelview_depth;
    if (push) {
        if (*depth >= GE_CLASSIC_STACK_CAPACITY) {
            ge_classic_set_error(engine, GE_STATUS_MATRIX_STACK, opcode, offset);
            return GE_STATUS_MATRIX_STACK;
        }
        ge_classic_matrix_copy(stack[*depth], stack[*depth - 1u]);
        (*depth)++;
    }
    if (load) {
        ge_classic_matrix_copy(stack[*depth - 1u], matrix);
    } else {
        float multiplied[16];
        ge_classic_matrix_mul(stack[*depth - 1u], matrix, multiplied);
        ge_classic_matrix_copy(stack[*depth - 1u], multiplied);
    }
    engine->state.matrix_handle = command.w1;
    ge_classic_mark_state_dirty(engine);
    return GE_STATUS_OK;
}

static GEStatusV1 ge_classic_pop_matrix(GEClassicReplayEngine *engine,
                                        GEClassicCommandV2 command,
                                        uint32_t opcode,
                                        uint32_t offset)
{
    uint32_t count = command.w1;
    if (count == 0u || count >= engine->modelview_depth) {
        ge_classic_set_error(engine, GE_STATUS_MATRIX_STACK, opcode, offset);
        return GE_STATUS_MATRIX_STACK;
    }
    engine->modelview_depth -= count;
    ge_classic_mark_state_dirty(engine);
    return GE_STATUS_OK;
}

static GEStatusV1 ge_classic_vertex_load(GEClassicReplayEngine *engine,
                                         GEClassicCommandV2 command,
                                         uint32_t opcode,
                                         uint32_t offset)
{
    uint32_t encoded = (command.w0 >> 16) & 0xffu;
    uint32_t count = (encoded >> 4) + 1u;
    uint32_t destination = encoded & 0x0fu;
    uint32_t length = command.w0 & 0xffffu;
    uint32_t resolved_handle = ge_classic_resolve_segment_handle(engine, command.w1);
    const GEClassicVertexResourceV2 *resource = ge_classic_find_vertex_resource(&engine->fixture, resolved_handle);
    if (resource == NULL && resolved_handle != command.w1) {
        resource = ge_classic_find_vertex_resource(&engine->fixture, command.w1);
    }
    if (resource == NULL) {
        ge_classic_set_error(engine, GE_STATUS_RESOURCE_NOT_FOUND, opcode, offset);
        return GE_STATUS_RESOURCE_NOT_FOUND;
    }
    if (length != count * 16u || destination + count > GE_CLASSIC_CACHE_CAPACITY ||
        resource->vertex_count < count) {
        ge_classic_set_error(engine, GE_STATUS_MALFORMED_STREAM, opcode, offset);
        return GE_STATUS_MALFORMED_STREAM;
    }
    if (resource->first_vertex > engine->fixture.vertex_count ||
        count > engine->fixture.vertex_count - resource->first_vertex) {
        ge_classic_set_error(engine, GE_STATUS_VERTEX_OUT_OF_RANGE, opcode, offset);
        return GE_STATUS_VERTEX_OUT_OF_RANGE;
    }
    for (uint32_t index = 0; index < count; index++) {
        engine->vertex_cache[destination + index] = engine->fixture.vertices[resource->first_vertex + index];
        engine->vertex_valid[destination + index] = 1u;
        if (destination + index >= engine->last_valid_vertex) {
            engine->last_valid_vertex = destination + index + 1u;
        }
    }
    engine->result.vertex_count += count;
    ge_classic_mark_state_dirty(engine);
    return GE_STATUS_OK;
}

static GEStatusV1 ge_classic_move_word(GEClassicReplayEngine *engine,
                                       GEClassicCommandV2 command,
                                       uint32_t opcode,
                                       uint32_t offset)
{
    uint32_t index = command.w0 & 0xffu;
    uint32_t move_offset = (command.w0 >> 8) & 0xffffu;
    if (index != 0x06u || (move_offset & 3u) != 0u || move_offset / 4u >= 16u) {
        ge_classic_set_error(engine, GE_STATUS_UNSUPPORTED_COMMAND, opcode, offset);
        return GE_STATUS_UNSUPPORTED_COMMAND;
    }
    GEClassicSegmentResourceV2 *segment = NULL;
    for (uint32_t segment_index = 0; segment_index < engine->fixture.segment_count; segment_index++) {
        if (engine->fixture.segments[segment_index].segment == move_offset / 4u) {
            segment = &engine->fixture.segments[segment_index];
            break;
        }
    }
    if (segment == NULL) {
        if (engine->fixture.segment_count >= GE_CLASSIC_SEGMENT_CAPACITY) {
            ge_classic_set_error(engine, GE_STATUS_REPLAY_BUDGET, opcode, offset);
            return GE_STATUS_REPLAY_BUDGET;
        }
        segment = &engine->fixture.segments[engine->fixture.segment_count++];
        memset(segment, 0, sizeof(*segment));
        segment->segment = move_offset / 4u;
    }
    segment->resource_handle = command.w1;
    segment->byte_offset = 0u;
    engine->event_hash = ge_classic_hash_u32(engine->event_hash, segment->segment);
    engine->event_hash = ge_classic_hash_u32(engine->event_hash, segment->resource_handle);
    ge_classic_mark_state_dirty(engine);
    return GE_STATUS_OK;
}

static GEStatusV1 ge_classic_execute(GEClassicReplayEngine *engine)
{
    GEStatusV1 status = ge_classic_push_list(engine,
                                             engine->fixture.root_list_handle,
                                             GE_CLASSIC_OP_DL,
                                             0u);
    if (status != GE_STATUS_OK) {
        return status;
    }

    while (engine->frame_depth > 0u) {
        if (engine->result.commands_processed >= GE_CLASSIC_COMMAND_BUDGET) {
            ge_classic_set_error(engine, GE_STATUS_REPLAY_BUDGET, 0u,
                                 engine->current_command_offset);
            return GE_STATUS_REPLAY_BUDGET;
        }
        GEClassicListFrame *frame = &engine->frames[engine->frame_depth - 1u];
        engine->current_list_handle = frame->handle;
        engine->current_list_depth = engine->frame_depth - 1u;
        if (frame->next_command >= frame->end_command) {
            if (engine->frame_depth == 1u) {
                ge_classic_set_error(engine, GE_STATUS_MALFORMED_STREAM, GE_CLASSIC_OP_ENDDL,
                                     frame->next_command * 8u);
                return GE_STATUS_MALFORMED_STREAM;
            }
            engine->frame_depth--;
            engine->result.list_returns++;
            engine->event_hash = ge_classic_hash_u32(engine->event_hash, UINT32_C(0x52455455));
            continue;
        }

        uint32_t command_index = frame->next_command++;
        GEClassicCommandV2 command = engine->fixture.commands[command_index];
        uint32_t offset = command_index * (uint32_t)sizeof(GEClassicCommandV2);
        uint32_t opcode = command.w0 >> 24;
        engine->current_command_offset = offset;
        engine->result.commands_processed++;
        engine->event_hash = ge_classic_hash_u32(engine->event_hash, command.w0);
        engine->event_hash = ge_classic_hash_u32(engine->event_hash, command.w1);

        switch (opcode) {
        case GE_CLASSIC_OP_DL:
            status = (command.w0 & 0xffu) == 0u
                ? ge_classic_push_list(engine, command.w1, opcode, offset)
                : ge_classic_branch_list(engine, command.w1, opcode, offset);
            break;
        case GE_CLASSIC_OP_ENDDL:
            engine->result.list_returns++;
            engine->event_hash = ge_classic_hash_u32(engine->event_hash, UINT32_C(0x52455455));
            engine->frame_depth--;
            break;
        case GE_CLASSIC_OP_MTX:
            status = ge_classic_matrix_command(engine, command, opcode, offset);
            break;
        case GE_CLASSIC_OP_POPMTX:
            status = ge_classic_pop_matrix(engine, command, opcode, offset);
            break;
        case GE_CLASSIC_OP_VTX:
            status = ge_classic_vertex_load(engine, command, opcode, offset);
            break;
        case GE_CLASSIC_OP_TRI1: {
            uint32_t a_raw = (command.w1 >> 16) & 0xffu;
            uint32_t b_raw = (command.w1 >> 8) & 0xffu;
            uint32_t c_raw = command.w1 & 0xffu;
            if (a_raw % 10u != 0u || b_raw % 10u != 0u || c_raw % 10u != 0u) {
                status = GE_STATUS_MALFORMED_STREAM;
                ge_classic_set_error(engine, status, opcode, offset);
            } else {
                status = ge_classic_emit_triangle(engine, a_raw / 10u, b_raw / 10u,
                                                  c_raw / 10u, opcode);
            }
            break;
        }
        case GE_CLASSIC_OP_TRI4: {
            uint32_t z[4] = {
                command.w0 & 0x0fu,
                (command.w0 >> 4) & 0x0fu,
                (command.w0 >> 8) & 0x0fu,
                (command.w0 >> 12) & 0x0fu,
            };
            uint32_t x[4] = {
                command.w1 & 0x0fu,
                (command.w1 >> 8) & 0x0fu,
                (command.w1 >> 16) & 0x0fu,
                (command.w1 >> 24) & 0x0fu,
            };
            uint32_t y[4] = {
                (command.w1 >> 4) & 0x0fu,
                (command.w1 >> 12) & 0x0fu,
                (command.w1 >> 20) & 0x0fu,
                (command.w1 >> 28) & 0x0fu,
            };
            for (uint32_t triangle = 0; triangle < 4u; triangle++) {
                if (x[triangle] == 0u && y[triangle] == 0u && z[triangle] == 0u) {
                    continue;
                }
                status = ge_classic_emit_triangle(engine, x[triangle], y[triangle],
                                                  z[triangle], opcode);
                if (status != GE_STATUS_OK) {
                    break;
                }
            }
            break;
        }
        case GE_CLASSIC_OP_SETTEX:
            engine->state.texture_id = command.w1 & 0xfffu;
            engine->state.texture_state = command.w0;
            ge_classic_mark_state_dirty(engine);
            break;
        case GE_CLASSIC_OP_TEXTURE:
            engine->state.texture_state = command.w0 ^ command.w1;
            ge_classic_mark_state_dirty(engine);
            break;
        case GE_CLASSIC_OP_SETOTHERMODE_H:
        case GE_CLASSIC_OP_SETOTHERMODE_H_ALT:
            engine->state.other_mode_h = command.w1;
            ge_classic_mark_state_dirty(engine);
            break;
        case GE_CLASSIC_OP_SETOTHERMODE_L:
        case GE_CLASSIC_OP_SETOTHERMODE_L_ALT:
            engine->state.other_mode_l = command.w1;
            ge_classic_mark_state_dirty(engine);
            break;
        case GE_CLASSIC_OP_SETCOMBINE:
            engine->state.combine_w0 = command.w0;
            engine->state.combine_w1 = command.w1;
            ge_classic_mark_state_dirty(engine);
            break;
        case GE_CLASSIC_OP_SETGEOMETRYMODE:
            engine->state.geometry_mode |= command.w1;
            ge_classic_mark_state_dirty(engine);
            break;
        case GE_CLASSIC_OP_CLEARGEOMETRYMODE:
            engine->state.geometry_mode &= ~command.w1;
            ge_classic_mark_state_dirty(engine);
            break;
        case GE_CLASSIC_OP_MOVEWORD:
            status = ge_classic_move_word(engine, command, opcode, offset);
            break;
        case GE_CLASSIC_OP_PIPE_SYNC:
        case GE_CLASSIC_OP_LOAD_SYNC:
        case GE_CLASSIC_OP_TILE_SYNC:
        case GE_CLASSIC_OP_FULL_SYNC:
            /* Sync is semantic state/order evidence; it does not split a Metal pass. */
            engine->event_hash = ge_classic_hash_u32(engine->event_hash, opcode);
            break;
        default:
            status = GE_STATUS_UNSUPPORTED_COMMAND;
            ge_classic_set_error(engine, status, opcode, offset);
            break;
        }

        if (status != GE_STATUS_OK) {
            return status;
        }
    }

    if (engine->result.draw_count == 0u || engine->result.triangle_count == 0u) {
        ge_classic_set_error(engine, GE_STATUS_MALFORMED_STREAM, 0u, 0u);
        return GE_STATUS_MALFORMED_STREAM;
    }
    ge_classic_finalize_draws(engine);
    return GE_STATUS_OK;
}

static void ge_classic_set_identity_resource(GEClassicMatrixResourceV2 *matrix,
                                             uint32_t handle)
{
    memset(matrix, 0, sizeof(*matrix));
    matrix->handle = handle;
    matrix->values[0] = 65536;
    matrix->values[5] = 65536;
    matrix->values[10] = 65536;
    matrix->values[15] = 65536;
}

static void ge_classic_set_vertex(GEVertexV1 *vertex,
                                  int16_t x,
                                  int16_t y,
                                  int16_t z,
                                  uint8_t r,
                                  uint8_t g,
                                  uint8_t b)
{
    memset(vertex, 0, sizeof(*vertex));
    vertex->x = x;
    vertex->y = y;
    vertex->z = z;
    vertex->r = r;
    vertex->g = g;
    vertex->b = b;
    vertex->a = 255u;
}

static GEClassicCommandV2 ge_classic_command(uint32_t opcode, uint32_t w1)
{
    GEClassicCommandV2 command;
    command.w0 = opcode << 24;
    command.w1 = w1;
    return command;
}

GEClassicReplayFixtureV2 ge_classic_nested_fixture(void)
{
    GEClassicReplayFixtureV2 fixture;
    memset(&fixture, 0, sizeof(fixture));
    fixture.header.abi_version = GE_NATIVE_ABI_VERSION;
    fixture.header.struct_size = (uint32_t)sizeof(fixture);
    fixture.packet_version = GE_CLASSIC_REPLAY_PACKET_VERSION;
    fixture.command_count = 8u;
    fixture.list_count = 2u;
    fixture.vertex_count = 3u;
    fixture.vertex_resource_count = 1u;
    fixture.matrix_count = 1u;
    fixture.segment_count = 1u;
    fixture.root_list_handle = UINT32_C(0x1000);
    fixture.lists[0].handle = UINT32_C(0x1000);
    fixture.lists[0].first_command = 0u;
    fixture.lists[0].command_count = 2u;
    fixture.lists[1].handle = UINT32_C(0x2000);
    fixture.lists[1].first_command = 2u;
    fixture.lists[1].command_count = 6u;
    fixture.commands[0] = ge_classic_command(GE_CLASSIC_OP_DL, UINT32_C(0x2000));
    fixture.commands[1] = ge_classic_command(GE_CLASSIC_OP_ENDDL, 0u);
    fixture.commands[2].w0 = UINT32_C(0x01020040);
    fixture.commands[2].w1 = UINT32_C(0x03000000);
    fixture.commands[3].w0 = ((uint32_t)GE_CLASSIC_OP_MOVEWORD << 24) |
                              (UINT32_C(0x10) << 8) | UINT32_C(0x06);
    fixture.commands[3].w1 = UINT32_C(0x90000000);
    fixture.commands[4].w0 = UINT32_C(0x04200030);
    fixture.commands[4].w1 = UINT32_C(0x04000000);
    fixture.commands[5].w0 = ((uint32_t)GE_CLASSIC_OP_TRI4 << 24) | 0x00000002u;
    fixture.commands[5].w1 = UINT32_C(0x00000120);
    fixture.commands[6].w0 = (uint32_t)GE_CLASSIC_OP_TRI1 << 24;
    fixture.commands[6].w1 = UINT32_C(0x00000a14);
    fixture.commands[7] = ge_classic_command(GE_CLASSIC_OP_ENDDL, 0u);
    ge_classic_set_vertex(&fixture.vertices[0], -100, -100, 0, 220, 80, 80);
    ge_classic_set_vertex(&fixture.vertices[1], 100, -100, 0, 80, 220, 100);
    ge_classic_set_vertex(&fixture.vertices[2], 0, 100, 0, 80, 100, 240);
    fixture.vertex_resources[0].handle = UINT32_C(0x90000000);
    fixture.vertex_resources[0].first_vertex = 0u;
    fixture.vertex_resources[0].vertex_count = 3u;
    fixture.segments[0].segment = 4u;
    fixture.segments[0].resource_handle = UINT32_C(0x90000000);
    ge_classic_set_identity_resource(&fixture.matrices[0], UINT32_C(0x03000000));
    fixture.viewport.scale_x = 480 * 65536;
    fixture.viewport.scale_y = 270 * 65536;
    fixture.viewport.scale_z = 65536;
    fixture.viewport.translate_x = 480 * 65536;
    fixture.viewport.translate_y = 270 * 65536;
    fixture.viewport.width = 960u;
    fixture.viewport.height = 540u;
    return fixture;
}

GEClassicReplayResultV2 ge_classic_replay_fixture(GEClassicReplayFixtureV2 fixture)
{
    GEClassicReplayEngine engine;
    ge_classic_init_engine(&engine, &fixture);
    GEStatusV1 status = ge_classic_validate_fixture(&fixture);
    if (status != GE_STATUS_OK) {
        engine.result.status = status;
        return engine.result;
    }
    status = ge_classic_execute(&engine);
    engine.result.status = status;
    return engine.result;
}

static GEStatusV1 ge_classic_prop_fixture_from_blob(const GEClassicAssetBlobV2 *blob,
                                                    GEClassicReplayFixtureV2 *fixture)
{
    if (blob->header.abi_version != GE_NATIVE_ABI_VERSION ||
        blob->header.struct_size != sizeof(*blob) || blob->reserved != 0u ||
        blob->byte_count != GE_CLASSIC_PROP_SIZE ||
        blob->byte_count > GE_CLASSIC_ASSET_BLOB_CAPACITY) {
        return GE_STATUS_ASSET_MISMATCH;
    }
    memset(fixture, 0, sizeof(*fixture));
    fixture->header.abi_version = GE_NATIVE_ABI_VERSION;
    fixture->header.struct_size = (uint32_t)sizeof(*fixture);
    fixture->packet_version = GE_CLASSIC_REPLAY_PACKET_VERSION;
    fixture->command_count = 2u + GE_CLASSIC_PROP_COMMAND_COUNT;
    fixture->list_count = 2u;
    fixture->vertex_count = 40u;
    fixture->vertex_resource_count = 3u;
    fixture->matrix_count = 1u;
    fixture->root_list_handle = UINT32_C(0x1000);
    fixture->lists[0].handle = UINT32_C(0x1000);
    fixture->lists[0].first_command = 0u;
    fixture->lists[0].command_count = 2u;
    fixture->lists[1].handle = UINT32_C(0x2000);
    fixture->lists[1].first_command = 2u;
    fixture->lists[1].command_count = GE_CLASSIC_PROP_COMMAND_COUNT;
    fixture->commands[0] = ge_classic_command(GE_CLASSIC_OP_DL, UINT32_C(0x2000));
    fixture->commands[1] = ge_classic_command(GE_CLASSIC_OP_ENDDL, 0u);
    for (uint32_t index = 0; index < GE_CLASSIC_PROP_COMMAND_COUNT; index++) {
        uint32_t offset = GE_CLASSIC_PROP_COMMAND_OFFSET + index * 8u;
        fixture->commands[2u + index].w0 = ge_classic_be32(&blob->bytes[offset]);
        fixture->commands[2u + index].w1 = ge_classic_be32(&blob->bytes[offset + 4u]);
    }
    for (uint32_t index = 0; index < 40u; index++) {
        uint32_t offset = GE_CLASSIC_PROP_VERTEX_OFFSET + index * 16u;
        GEVertexV1 *vertex = &fixture->vertices[index];
        memset(vertex, 0, sizeof(*vertex));
        vertex->x = ge_classic_be16s(&blob->bytes[offset]);
        vertex->y = ge_classic_be16s(&blob->bytes[offset + 2u]);
        vertex->z = ge_classic_be16s(&blob->bytes[offset + 4u]);
        vertex->reserved0 = ge_classic_be16(&blob->bytes[offset + 6u]);
        vertex->s = ge_classic_be16s(&blob->bytes[offset + 8u]);
        vertex->t = ge_classic_be16s(&blob->bytes[offset + 10u]);
        vertex->r = blob->bytes[offset + 12u];
        vertex->g = blob->bytes[offset + 13u];
        vertex->b = blob->bytes[offset + 14u];
        vertex->a = blob->bytes[offset + 15u];
    }
    fixture->vertex_resources[0].handle = UINT32_C(0x04000000);
    fixture->vertex_resources[0].first_vertex = 0u;
    fixture->vertex_resources[0].vertex_count = 16u;
    fixture->vertex_resources[1].handle = UINT32_C(0x04000100);
    fixture->vertex_resources[1].first_vertex = 16u;
    fixture->vertex_resources[1].vertex_count = 16u;
    fixture->vertex_resources[2].handle = UINT32_C(0x04000200);
    fixture->vertex_resources[2].first_vertex = 32u;
    fixture->vertex_resources[2].vertex_count = 8u;
    ge_classic_set_identity_resource(&fixture->matrices[0], UINT32_C(0x03000000));
    fixture->viewport.scale_x = 480 * 65536;
    fixture->viewport.scale_y = 270 * 65536;
    fixture->viewport.scale_z = 65536;
    fixture->viewport.translate_x = 480 * 65536;
    fixture->viewport.translate_y = 270 * 65536;
    fixture->viewport.width = 960u;
    fixture->viewport.height = 540u;
    return GE_STATUS_OK;
}

GEClassicReplayResultV2 ge_classic_replay_prop_blob(GEClassicAssetBlobV2 blob)
{
    GEClassicReplayFixtureV2 fixture;
    GEClassicReplayResultV2 result;
    memset(&result, 0, sizeof(result));
    result.header.abi_version = GE_NATIVE_ABI_VERSION;
    result.header.struct_size = (uint32_t)sizeof(result);
    GEStatusV1 status = ge_classic_prop_fixture_from_blob(&blob, &fixture);
    if (status != GE_STATUS_OK) {
        result.status = status;
        result.error_opcode = 0u;
        result.error_offset = 0u;
        return result;
    }
    result = ge_classic_replay_fixture(fixture);
    return result;
}
