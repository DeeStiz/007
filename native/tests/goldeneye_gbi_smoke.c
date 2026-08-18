#include "goldeneye_native.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

int main(void)
{
    GEGBIStreamV1 stream = ge_native_gbi_fixture_stream();
    GEGBINormalizationResultV1 first = ge_native_normalize_gbi(stream);
    GEGBINormalizationResultV1 second = ge_native_normalize_gbi(stream);

    assert(sizeof(GEGBIStreamV1) == 136u);
    assert(sizeof(GEGBINormalizationResultV1) == 152u);
    assert(first.status == GE_STATUS_OK);
    assert(first.packet.vertex_count == 3u);
    assert(first.packet.command_count == 2u);
    assert(first.packet.commands[0].w0 == UINT32_C(0xbf000000));
    assert(first.packet.commands[1].w0 == UINT32_C(0xb8000000));
    assert(first.packet_hash != 0u);
    assert(first.event_hash != 0u);
    assert(memcmp(&first.packet, &second.packet, sizeof(first.packet)) == 0);
    assert(first.packet_hash == second.packet_hash);
    assert(first.event_hash == second.event_hash);

    stream.header.abi_version++;
    assert(ge_native_normalize_gbi(stream).status == GE_STATUS_INVALID_VERSION);
    stream = ge_native_gbi_fixture_stream();
    stream.header.struct_size--;
    assert(ge_native_normalize_gbi(stream).status == GE_STATUS_INVALID_SIZE);
    stream = ge_native_gbi_fixture_stream();
    stream.reserved0[0] = 1u;
    assert(ge_native_normalize_gbi(stream).status == GE_STATUS_RESERVED_BITS);

    stream = ge_native_gbi_fixture_stream();
    stream.commands[1].w0 = UINT32_C(0x99000000);
    GEGBINormalizationResultV1 unsupported = ge_native_normalize_gbi(stream);
    assert(unsupported.status == GE_STATUS_UNSUPPORTED_COMMAND);
    assert(unsupported.error_opcode == UINT32_C(0x99));
    assert(unsupported.error_offset == 8u);

    stream = ge_native_gbi_fixture_stream();
    stream.commands[0].w1 = UINT32_C(0x00000200);
    GEGBINormalizationResultV1 missing_resource = ge_native_normalize_gbi(stream);
    assert(missing_resource.status == GE_STATUS_RESOURCE_NOT_FOUND);
    assert(missing_resource.error_opcode == UINT32_C(0x04));
    assert(missing_resource.error_offset == 0u);

    stream = ge_native_gbi_fixture_stream();
    stream.commands[1].w1 = UINT32_C(0x00010300);
    assert(ge_native_normalize_gbi(stream).status == GE_STATUS_VERTEX_OUT_OF_RANGE);

    stream = ge_native_gbi_fixture_stream();
    stream.commands[0] = stream.commands[1];
    assert(ge_native_normalize_gbi(stream).status == GE_STATUS_VERTEX_OUT_OF_RANGE);

    stream = ge_native_gbi_fixture_stream();
    stream.resources[0].first_vertex = UINT32_MAX;
    assert(ge_native_normalize_gbi(stream).status == GE_STATUS_MALFORMED_STREAM);

    stream = ge_native_gbi_fixture_stream();
    stream.commands[2] = stream.commands[1];
    assert(ge_native_normalize_gbi(stream).status == GE_STATUS_MALFORMED_STREAM);

    puts("goldeneye_gbi_smoke: PASS");
    return 0;
}
