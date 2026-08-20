#include "ge_classic_raster_v5.h"

#include <inttypes.h>
#include <stdio.h>
#include <string.h>

static int expect(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "raster-v5 failure: %s\n", message);
        return 0;
    }
    return 1;
}

int main(void)
{
    GEClassicRasterResultV5 result = ge_classic_lower_ammo_crate_raster_v5();
    if (!expect(result.status == GE_STATUS_OK, "canonical status") ||
        !expect(result.state_count == 2u, "canonical state count") ||
        !expect(result.header.struct_size == sizeof(result), "result size") ||
        !expect(result.states[0].raw_render_mode == GE_CLASSIC_RASTER_MODE_OPAQUE,
                "opaque mode") ||
        !expect(result.states[1].raw_render_mode == GE_CLASSIC_RASTER_MODE_AUTHORED,
                "authored mode") ||
        !expect(result.states[0].z_compare == 1u && result.states[0].z_update == 1u,
                "opaque depth compare/update") ||
        !expect(result.states[0].depth_compare_policy == GE_CLASSIC_RASTER_DEPTH_LESS_EQUAL,
                "opaque depth policy") ||
        !expect(result.states[0].depth_write == 1u,
                "opaque depth write") ||
        !expect(result.states[0].z_mode == GE_CLASSIC_RASTER_ZMODE_OPA,
                "opaque z mode") ||
        !expect(result.states[0].alpha_coverage_select == 1u,
                "opaque alpha coverage select") ||
        !expect(result.states[0].fog_enable == 1u &&
                    result.states[0].fog_color_rgba8 == UINT32_C(0x00000026) &&
                    result.states[0].fog_alpha_q8 == 38u,
                "source fog policy") ||
        !expect(result.states[1].z_update == 0u &&
                    result.states[1].z_mode == GE_CLASSIC_RASTER_ZMODE_DECAL &&
                    result.states[1].force_blend == 1u,
                "authored decal policy") ||
        !expect(result.states[1].clear_on_coverage == 1u &&
                    result.states[1].coverage_destination == 1u,
                "authored coverage policy")) {
        return 1;
    }

    printf("raster-v5: PASS states=%" PRIu32 " aggregate=%" PRIu64
           " opaqueHash=%" PRIu64 " authoredHash=%" PRIu64
           " opaqueBlend=0x%08" PRIx32 " authoredBlend=0x%08" PRIx32 "\n",
           result.state_count,
           result.aggregate_hash,
           result.states[0].state_hash,
           result.states[1].state_hash,
           result.states[0].blend_cycle0,
           result.states[1].blend_cycle0);

    GEClassicRasterInputV5 malformed = {0};
    malformed.header.abi_version = GE_CLASSIC_RASTER_ABI_VERSION + 1u;
    malformed.header.struct_size = sizeof(malformed);
    malformed.mode_count = 2u;
    malformed.raw_modes[0] = GE_CLASSIC_RASTER_MODE_OPAQUE;
    malformed.raw_modes[1] = GE_CLASSIC_RASTER_MODE_AUTHORED;
    if (!expect(ge_classic_lower_raster_v5(malformed).status == GE_STATUS_INVALID_VERSION,
                "version rejection")) {
        return 1;
    }
    malformed.header.abi_version = GE_CLASSIC_RASTER_ABI_VERSION;
    malformed.reserved = 1u;
    if (!expect(ge_classic_lower_raster_v5(malformed).status == GE_STATUS_RESERVED_BITS,
                "reserved rejection")) {
        return 1;
    }
    malformed.reserved = 0u;
    malformed.raw_modes[1] = UINT32_C(0xdeadbeef);
    if (!expect(ge_classic_lower_raster_v5(malformed).status == GE_STATUS_UNSUPPORTED_COMMAND,
                "unsupported mode rejection")) {
        return 1;
    }
    malformed.raw_modes[1] = GE_CLASSIC_RASTER_MODE_AUTHORED;
    malformed.raw_other_mode_l = 4u;
    if (!expect(ge_classic_lower_raster_v5(malformed).status == GE_STATUS_MALFORMED_STREAM,
                "alpha mode rejection")) {
        return 1;
    }
    return 0;
}
