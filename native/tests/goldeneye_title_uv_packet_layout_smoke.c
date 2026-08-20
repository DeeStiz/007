#include <assert.h>
#include <stdint.h>
#include <string.h>

#include "ge_title_uv_v1.h"

int main(void) {
    GETitleUVPacketHeaderV1 header;
    GETitleUVRecordV1 record;
    memset(&header, 0, sizeof(header));
    memset(&record, 0, sizeof(record));
    header.header.abi_version = GE_NATIVE_ABI_VERSION;
    header.header.struct_size = (uint32_t)sizeof(header);
    header.packet_version = GE_TITLE_UV_V1_CONTRACT_VERSION;
    header.record_stride = GE_TITLE_UV_V1_RECORD_SIZE;
    record.header.abi_version = GE_NATIVE_ABI_VERSION;
    record.header.struct_size = (uint32_t)sizeof(record);
    record.record_version = GE_TITLE_UV_V1_CONTRACT_VERSION;
    record.s = -0x1000;
    record.t = 0x400;
    record.material_handle = UINT32_C(0x05000408);
    record.source_command_hash = UINT64_C(0x0123456789abcdef);
    record.source_vertex_hash = UINT64_C(0xfedcba9876543210);
    assert(sizeof(header) == 128u);
    assert(sizeof(record) == 64u);
    assert(record.s < 0 && record.t > 0);
    assert(record.material_handle != 0u);
    assert(record.source_command_hash != 0u && record.source_vertex_hash != 0u);
    return 0;
}
