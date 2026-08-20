#include "goldeneye_native.h"

#include <assert.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>

static GEInitRequestV1 valid_init_request(void)
{
    GEInitRequestV1 request = {{GE_NATIVE_ABI_VERSION, sizeof(GEInitRequestV1)}, 0u, 0u};
    return request;
}

static GEInputSnapshotV1 valid_input(uint64_t sequence)
{
    GEInputSnapshotV1 input = {
        {GE_NATIVE_ABI_VERSION, sizeof(GEInputSnapshotV1)},
        sequence,
        UINT32_C(0x10),
        UINT32_C(0x10),
        0u,
        0u,
    };
    return input;
}

typedef struct WrongThreadCall {
    GEInputSnapshotV1 input;
    GEStatusV1 step_status;
    GEStatusV1 shutdown_status;
} WrongThreadCall;

static void *wrong_thread_entry(void *opaque)
{
    WrongThreadCall *call = (WrongThreadCall *)opaque;
    call->step_status = ge_native_step(call->input).status;
    call->shutdown_status = ge_native_shutdown();
    return NULL;
}

int main(void)
{
    GEInitRequestV1 request = valid_init_request();
    GEFixtureResultV1 cold_packet;
    GEFixtureResultV1 first_packet;
    GEFixtureResultV1 second_packet;
    GEFixtureResultV1 repeated_packet;
    GEFrameResultV1 frame;
    GEInputSnapshotV1 input;
    WrongThreadCall wrong_thread;
    pthread_t thread;

    assert(sizeof(GEAbiHeaderV1) == 8u);
    assert(sizeof(GEInitRequestV1) == 16u);
    assert(sizeof(GEInputSnapshotV1) == 32u);
    assert(sizeof(GEVertexV1) == 20u);
    assert(sizeof(GECommandWordsV1) == 8u);
    assert(sizeof(GEFixturePacketV1) == 112u);
    assert(sizeof(GEFixtureResultV1) == 128u);
    assert(sizeof(GEFrameResultV1) == 56u);

    cold_packet = ge_native_fixture_packet();
    assert(cold_packet.status == GE_STATUS_INVALID_STATE);

    request.header.abi_version++;
    assert(ge_native_initialize(request) == GE_STATUS_INVALID_VERSION);
    request = valid_init_request();
    request.header.struct_size--;
    assert(ge_native_initialize(request) == GE_STATUS_INVALID_SIZE);
    request = valid_init_request();
    request.reserved = 1u;
    assert(ge_native_initialize(request) == GE_STATUS_RESERVED_BITS);
    request = valid_init_request();
    assert(ge_native_initialize(request) == GE_STATUS_OK);
    assert(ge_native_initialize(request) == GE_STATUS_INVALID_STATE);

    first_packet = ge_native_fixture_packet();
    second_packet = ge_native_fixture_packet();
    assert(first_packet.status == GE_STATUS_OK);
    assert(first_packet.packet.packet_hash != 0u);
    assert(memcmp(&first_packet.packet, &second_packet.packet, sizeof(first_packet.packet)) == 0);
    assert(first_packet.packet.commands[0].w0 == UINT32_C(0xbf000000));
    assert(first_packet.packet.commands[1].w0 == UINT32_C(0xb8000000));

    input = valid_input(1u);
    frame = ge_native_step(input);
    assert(frame.status == GE_STATUS_OK);
    assert(frame.tick == 1u);
    assert(frame.packet_hash == first_packet.packet.packet_hash);
    assert(frame.event_hash != 0u);

    input.header.abi_version++;
    assert(ge_native_step(input).status == GE_STATUS_INVALID_VERSION);
    input = valid_input(2u);
    input.header.struct_size--;
    assert(ge_native_step(input).status == GE_STATUS_INVALID_SIZE);
    input = valid_input(2u);
    input.reserved = 1u;
    assert(ge_native_step(input).status == GE_STATUS_RESERVED_BITS);

    wrong_thread.input = valid_input(3u);
    wrong_thread.step_status = GE_STATUS_INTERNAL_ERROR;
    wrong_thread.shutdown_status = GE_STATUS_INTERNAL_ERROR;
    assert(pthread_create(&thread, NULL, wrong_thread_entry, &wrong_thread) == 0);
    assert(pthread_join(thread, NULL) == 0);
    assert(wrong_thread.step_status == GE_STATUS_WRONG_OWNER_THREAD);
    assert(wrong_thread.shutdown_status == GE_STATUS_WRONG_OWNER_THREAD);

    input = valid_input(4u);
    frame = ge_native_step(input);
    assert(frame.status == GE_STATUS_OK);
    assert(frame.tick == 2u);
    second_packet = ge_native_fixture_packet();
    assert(memcmp(&first_packet.packet, &second_packet.packet, sizeof(first_packet.packet)) == 0);

    assert(ge_native_shutdown() == GE_STATUS_OK);
    assert(ge_native_shutdown() == GE_STATUS_INVALID_STATE);

    assert(ge_native_initialize(valid_init_request()) == GE_STATUS_OK);
    repeated_packet = ge_native_fixture_packet();
    assert(repeated_packet.status == GE_STATUS_OK);
    assert(repeated_packet.packet.packet_hash == first_packet.packet.packet_hash);
    frame = ge_native_step(valid_input(1u));
    assert(frame.status == GE_STATUS_OK);
    assert(frame.tick == 1u);
    assert(frame.packet_hash == repeated_packet.packet.packet_hash);
    assert(ge_native_shutdown() == GE_STATUS_OK);

    puts("goldeneye_native_c_smoke: PASS");
    return 0;
}
