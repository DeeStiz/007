#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

#include "goldeneye_native.h"

int main(void) {
    assert(sizeof(GEAbiHeaderV1) == 8u);
    assert(sizeof(GETitleTexturePacketHeaderV8) == 128u);
    assert(sizeof(GETitleTextureRecordV8) == 144u);
    assert(offsetof(GETitleTexturePacketHeaderV8, header) == 8u);
    assert(offsetof(GETitleTexturePacketHeaderV8, packet_sha256) == 72u);
    assert(offsetof(GETitleTextureRecordV8, header) == 0u);
    assert(offsetof(GETitleTextureRecordV8, resource_id) == 12u);
    assert(offsetof(GETitleTextureRecordV8, decoded_sha256) == 112u);
    puts("goldeneye_title_texture_packet_layout_smoke: PASS");
    return 0;
}
