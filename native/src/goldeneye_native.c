#include "goldeneye_native.h"

#include <pthread.h>
#include <string.h>

enum {
    GE_NATIVE_STATE_COLD = 0u,
    GE_NATIVE_STATE_READY = 1u,
};

typedef struct GENativeState {
    uint32_t lifecycle;
    uint64_t owner_thread;
    uint64_t tick;
    GEFixturePacketV1 packet;
} GENativeState;

static GENativeState g_state;

static GEStatusV1 ge_current_thread(uint64_t *thread_id)
{
    if (thread_id == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }

#if defined(__APPLE__)
    if (pthread_threadid_np(NULL, thread_id) != 0) {
        return GE_STATUS_THREAD_ID_UNAVAILABLE;
    }
#else
    *thread_id = (uint64_t)(uintptr_t)pthread_self();
#endif
    return GE_STATUS_OK;
}

static GEStatusV1 ge_validate_header(GEAbiHeaderV1 header, uint32_t expected_size)
{
    if (header.abi_version != GE_NATIVE_ABI_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    if (header.struct_size != expected_size) {
        return GE_STATUS_INVALID_SIZE;
    }
    return GE_STATUS_OK;
}

static uint64_t ge_hash_byte(uint64_t hash, uint8_t byte)
{
    return (hash ^ (uint64_t)byte) * UINT64_C(1099511628211);
}

static uint64_t ge_hash_u16(uint64_t hash, uint16_t value)
{
    hash = ge_hash_byte(hash, (uint8_t)(value & UINT16_C(0xff)));
    return ge_hash_byte(hash, (uint8_t)(value >> 8));
}

static uint64_t ge_hash_u32(uint64_t hash, uint32_t value)
{
    hash = ge_hash_byte(hash, (uint8_t)(value & UINT32_C(0xff)));
    hash = ge_hash_byte(hash, (uint8_t)((value >> 8) & UINT32_C(0xff)));
    hash = ge_hash_byte(hash, (uint8_t)((value >> 16) & UINT32_C(0xff)));
    return ge_hash_byte(hash, (uint8_t)(value >> 24));
}

static uint64_t ge_hash_u64(uint64_t hash, uint64_t value)
{
    hash = ge_hash_u32(hash, (uint32_t)(value & UINT64_C(0xffffffff)));
    return ge_hash_u32(hash, (uint32_t)(value >> 32));
}

static uint64_t ge_packet_hash(const GEFixturePacketV1 *packet)
{
    uint64_t hash = UINT64_C(1469598103934665603);

    hash = ge_hash_u32(hash, packet->packet_version);
    hash = ge_hash_u32(hash, packet->vertex_count);
    hash = ge_hash_u32(hash, packet->command_count);
    hash = ge_hash_u32(hash, packet->reserved0);
    for (uint32_t index = 0; index < GE_NATIVE_VERTEX_CAPACITY; index++) {
        const GEVertexV1 *vertex = &packet->vertices[index];
        hash = ge_hash_u16(hash, (uint16_t)vertex->x);
        hash = ge_hash_u16(hash, (uint16_t)vertex->y);
        hash = ge_hash_u16(hash, (uint16_t)vertex->z);
        hash = ge_hash_u16(hash, vertex->reserved0);
        hash = ge_hash_u16(hash, (uint16_t)vertex->s);
        hash = ge_hash_u16(hash, (uint16_t)vertex->t);
        hash = ge_hash_byte(hash, vertex->r);
        hash = ge_hash_byte(hash, vertex->g);
        hash = ge_hash_byte(hash, vertex->b);
        hash = ge_hash_byte(hash, vertex->a);
        hash = ge_hash_u32(hash, vertex->reserved1);
    }
    for (uint32_t index = 0; index < GE_NATIVE_COMMAND_CAPACITY; index++) {
        hash = ge_hash_u32(hash, packet->commands[index].w0);
        hash = ge_hash_u32(hash, packet->commands[index].w1);
    }
    return ge_hash_u64(hash, packet->reserved1);
}

static void ge_build_fixture_packet(GEFixturePacketV1 *packet)
{
    memset(packet, 0, sizeof(*packet));
    packet->header.abi_version = GE_NATIVE_ABI_VERSION;
    packet->header.struct_size = (uint32_t)sizeof(*packet);
    packet->packet_version = GE_NATIVE_PACKET_VERSION;
    packet->vertex_count = GE_NATIVE_VERTEX_CAPACITY;
    packet->command_count = GE_NATIVE_COMMAND_CAPACITY;

    packet->vertices[0].x = -220;
    packet->vertices[0].y = -180;
    packet->vertices[0].r = 230;
    packet->vertices[0].g = 70;
    packet->vertices[0].b = 60;
    packet->vertices[0].a = 255;

    packet->vertices[1].x = 220;
    packet->vertices[1].y = -180;
    packet->vertices[1].r = 60;
    packet->vertices[1].g = 210;
    packet->vertices[1].b = 100;
    packet->vertices[1].a = 255;

    packet->vertices[2].x = 0;
    packet->vertices[2].y = 220;
    packet->vertices[2].r = 70;
    packet->vertices[2].g = 120;
    packet->vertices[2].b = 240;
    packet->vertices[2].a = 255;

    // Classic GoldenEye/F3D-style fixture markers.  M7 will validate these
    // words through the real GBI normalization path; M1 only proves ABI and
    // deterministic packet ownership.
    packet->commands[0].w0 = UINT32_C(0xbf000000);
    packet->commands[0].w1 = UINT32_C(0x00010200);
    packet->commands[1].w0 = UINT32_C(0xb8000000);
    packet->commands[1].w1 = 0;
    packet->packet_hash = ge_packet_hash(packet);
}

static void ge_init_result_header(GEAbiHeaderV1 *header, uint32_t size)
{
    header->abi_version = GE_NATIVE_ABI_VERSION;
    header->struct_size = size;
}

GEStatusV1 ge_native_initialize(GEInitRequestV1 request)
{
    GEStatusV1 status = ge_validate_header(request.header, (uint32_t)sizeof(request));
    uint64_t thread_id = 0;

    if (status != GE_STATUS_OK) {
        return status;
    }
    if (request.flags != 0u || request.reserved != 0u) {
        return GE_STATUS_RESERVED_BITS;
    }
    if (g_state.lifecycle != GE_NATIVE_STATE_COLD) {
        return GE_STATUS_INVALID_STATE;
    }
    status = ge_current_thread(&thread_id);
    if (status != GE_STATUS_OK) {
        return status;
    }

    memset(&g_state, 0, sizeof(g_state));
    g_state.lifecycle = GE_NATIVE_STATE_READY;
    g_state.owner_thread = thread_id;
    ge_build_fixture_packet(&g_state.packet);
    return GE_STATUS_OK;
}

GEFrameResultV1 ge_native_step(GEInputSnapshotV1 input)
{
    GEFrameResultV1 result;
    GEStatusV1 status;
    uint64_t thread_id = 0;
    uint64_t hash;

    memset(&result, 0, sizeof(result));
    ge_init_result_header(&result.header, (uint32_t)sizeof(result));
    status = ge_validate_header(input.header, (uint32_t)sizeof(input));
    if (status != GE_STATUS_OK) {
        result.status = status;
        return result;
    }
    if (input.reserved != 0u) {
        result.status = GE_STATUS_RESERVED_BITS;
        return result;
    }
    if (g_state.lifecycle != GE_NATIVE_STATE_READY) {
        result.status = GE_STATUS_INVALID_STATE;
        return result;
    }
    status = ge_current_thread(&thread_id);
    if (status != GE_STATUS_OK) {
        result.status = status;
        return result;
    }
    if (thread_id != g_state.owner_thread) {
        result.status = GE_STATUS_WRONG_OWNER_THREAD;
        return result;
    }

    g_state.tick++;
    result.status = GE_STATUS_OK;
    result.tick = g_state.tick;
    result.held = input.held;
    result.pressed = input.pressed;
    result.released = input.released;
    result.packet_hash = g_state.packet.packet_hash;

    hash = UINT64_C(1469598103934665603);
    hash = ge_hash_u64(hash, input.sequence);
    hash = ge_hash_u64(hash, g_state.tick);
    hash = ge_hash_u32(hash, input.held);
    hash = ge_hash_u32(hash, input.pressed);
    hash = ge_hash_u32(hash, input.released);
    result.event_hash = hash;
    return result;
}

GEStatusV1 ge_native_shutdown(void)
{
    GEStatusV1 status;
    uint64_t thread_id = 0;

    if (g_state.lifecycle != GE_NATIVE_STATE_READY) {
        return GE_STATUS_INVALID_STATE;
    }
    status = ge_current_thread(&thread_id);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (thread_id != g_state.owner_thread) {
        return GE_STATUS_WRONG_OWNER_THREAD;
    }
    memset(&g_state, 0, sizeof(g_state));
    return GE_STATUS_OK;
}

GEFixtureResultV1 ge_native_fixture_packet(void)
{
    GEFixtureResultV1 result;

    memset(&result, 0, sizeof(result));
    ge_init_result_header(&result.header, (uint32_t)sizeof(result));
    if (g_state.lifecycle != GE_NATIVE_STATE_READY) {
        result.status = GE_STATUS_INVALID_STATE;
        return result;
    }
    result.status = GE_STATUS_OK;
    result.packet = g_state.packet;
    return result;
}

static void ge_init_gbi_result_header(GEGBINormalizationResultV1 *result)
{
    memset(result, 0, sizeof(*result));
    result->header.abi_version = GE_NATIVE_ABI_VERSION;
    result->header.struct_size = (uint32_t)sizeof(*result);
}

GEGBIStreamV1 ge_native_gbi_fixture_stream(void)
{
    GEGBIStreamV1 stream;
    GEFixturePacketV1 packet;

    memset(&stream, 0, sizeof(stream));
    stream.header.abi_version = GE_NATIVE_ABI_VERSION;
    stream.header.struct_size = (uint32_t)sizeof(stream);
    stream.command_count = 3;
    stream.resource_count = 1;
    stream.commands[0].w0 = UINT32_C(0x04000003);
    stream.commands[0].w1 = UINT32_C(0x00000100);
    stream.commands[1].w0 = UINT32_C(0xbf000000);
    stream.commands[1].w1 = UINT32_C(0x00010200);
    stream.commands[2].w0 = UINT32_C(0xb8000000);
    stream.commands[2].w1 = 0;
    ge_build_fixture_packet(&packet);
    memcpy(stream.vertices, packet.vertices, sizeof(stream.vertices));
    stream.resources[0].handle = UINT32_C(0x00000100);
    stream.resources[0].first_vertex = 0;
    stream.resources[0].vertex_count = GE_NATIVE_VERTEX_CAPACITY;
    return stream;
}

GEGBINormalizationResultV1 ge_native_normalize_gbi(GEGBIStreamV1 stream)
{
    GEGBINormalizationResultV1 result;
    GEStatusV1 status;
    uint64_t event_hash = UINT64_C(1469598103934665603);
    uint32_t loaded_first = 0;
    uint32_t loaded_count = 0;
    int loaded = 0;
    int saw_triangle = 0;
    int saw_end = 0;

    ge_init_gbi_result_header(&result);
    status = ge_validate_header(stream.header, (uint32_t)sizeof(stream));
    if (status != GE_STATUS_OK) {
        result.status = status;
        return result;
    }
    if (stream.reserved0[0] != 0u || stream.reserved0[1] != 0u || stream.reserved1 != 0u) {
        result.status = GE_STATUS_RESERVED_BITS;
        return result;
    }
    if (stream.command_count == 0u || stream.command_count > GE_NATIVE_GBI_COMMAND_CAPACITY ||
        stream.resource_count > GE_NATIVE_GBI_RESOURCE_CAPACITY) {
        result.status = GE_STATUS_MALFORMED_STREAM;
        return result;
    }

    for (uint32_t index = 0; index < stream.command_count; index++) {
        const GECommandWordsV1 command = stream.commands[index];
        const uint32_t opcode = command.w0 >> 24;
        const uint32_t byte_offset = index * (uint32_t)sizeof(GECommandWordsV1);
        event_hash = ge_hash_u32(event_hash, command.w0);
        event_hash = ge_hash_u32(event_hash, command.w1);
        result.error_opcode = opcode;
        result.error_offset = byte_offset;

        if (opcode == UINT32_C(0x04)) { // GoldenEye G_VTX
            const uint32_t requested_count = command.w0 & UINT32_C(0xff);
            const uint32_t handle = command.w1;
            const GEResourceHandleV1 *resource = NULL;
            if (loaded || requested_count != GE_NATIVE_VERTEX_CAPACITY) {
                result.status = GE_STATUS_MALFORMED_STREAM;
                return result;
            }
            for (uint32_t resource_index = 0; resource_index < stream.resource_count; resource_index++) {
                if (stream.resources[resource_index].handle == handle) {
                    resource = &stream.resources[resource_index];
                    break;
                }
            }
            if (resource == NULL) {
                result.status = GE_STATUS_RESOURCE_NOT_FOUND;
                return result;
            }
            if (resource->reserved != 0u || resource->vertex_count != requested_count ||
                resource->first_vertex > GE_NATIVE_VERTEX_CAPACITY ||
                resource->vertex_count > GE_NATIVE_VERTEX_CAPACITY - resource->first_vertex) {
                result.status = GE_STATUS_MALFORMED_STREAM;
                return result;
            }
            loaded_first = resource->first_vertex;
            loaded_count = resource->vertex_count;
            memcpy(result.packet.vertices, &stream.vertices[loaded_first], loaded_count * sizeof(GEVertexV1));
            loaded = 1;
        } else if (opcode == UINT32_C(0xbf)) { // GoldenEye G_TRI1
            const uint32_t vertex0 = (command.w1 >> 16) & UINT32_C(0xff);
            const uint32_t vertex1 = (command.w1 >> 8) & UINT32_C(0xff);
            const uint32_t vertex2 = command.w1 & UINT32_C(0xff);
            if (!loaded || saw_triangle || vertex0 >= loaded_count || vertex1 >= loaded_count ||
                vertex2 >= loaded_count) {
                result.status = (!loaded || vertex0 >= loaded_count || vertex1 >= loaded_count || vertex2 >= loaded_count)
                    ? GE_STATUS_VERTEX_OUT_OF_RANGE : GE_STATUS_MALFORMED_STREAM;
                return result;
            }
            (void)loaded_first;
            result.packet.commands[0] = command;
            saw_triangle = 1;
        } else if (opcode == UINT32_C(0xb8)) { // GoldenEye G_ENDDL
            if (!saw_triangle || index + 1u != stream.command_count) {
                result.status = GE_STATUS_MALFORMED_STREAM;
                return result;
            }
            result.packet.commands[1] = command;
            saw_end = 1;
        } else {
            result.status = GE_STATUS_UNSUPPORTED_COMMAND;
            return result;
        }
    }

    if (!saw_triangle || !saw_end || !loaded) {
        result.status = GE_STATUS_MALFORMED_STREAM;
        return result;
    }
    result.packet.header.abi_version = GE_NATIVE_ABI_VERSION;
    result.packet.header.struct_size = (uint32_t)sizeof(result.packet);
    result.packet.packet_version = GE_NATIVE_PACKET_VERSION;
    result.packet.vertex_count = loaded_count;
    result.packet.command_count = 2;
    result.packet.packet_hash = ge_packet_hash(&result.packet);
    result.status = GE_STATUS_OK;
    result.packet_hash = result.packet.packet_hash;
    result.event_hash = event_hash;
    return result;
}
