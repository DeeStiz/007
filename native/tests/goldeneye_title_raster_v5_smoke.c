#include "ge_title_raster_v5.h"

#include <inttypes.h>
#include <stdio.h>

static int expect(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "title-raster-v5 failure: %s\n", message);
        return 0;
    }
    return 1;
}

int main(void)
{
    const GETitleRasterResultV5 first = ge_title_lower_source_raster_v5();
    const GETitleRasterResultV5 second = ge_title_lower_source_raster_v5();
    if (!expect(first.status == GE_STATUS_OK, "canonical status") ||
        !expect(first.header.struct_size == sizeof(first), "result size") ||
        !expect(first.state_count == GE_TITLE_RASTER_V5_STATE_CAPACITY,
                "canonical state count") ||
        !expect(first.aggregate_hash == UINT64_C(11519430422207814888),
                "canonical aggregate hash") ||
        !expect(first.aggregate_hash == second.aggregate_hash,
                "deterministic aggregate hash")) {
        return 1;
    }

    const GETitleRasterStateV5 *one_cycle = &first.states[0];
    const GETitleRasterStateV5 *two_cycle = &first.states[3];
    const GETitleRasterStateV5 *forced_blend = &first.states[5];
    const GETitleRasterStateV5 *rareware_one_cycle = &first.states[6];
    const GETitleRasterStateV5 *rareware_two_cycle = &first.states[7];
    if (!expect(one_cycle->raw_other_mode_h == GE_TITLE_RASTER_V5_H_ONE_CYCLE &&
                    one_cycle->raw_other_mode_l == GE_TITLE_RASTER_V5_L_ONE_CYCLE,
                "one-cycle source modes") ||
        !expect(one_cycle->state_hash == UINT64_C(4529100210060394967),
                "one-cycle state hash") ||
        !expect(one_cycle->cycle_type == 0u && one_cycle->z_compare == 0u &&
                    one_cycle->z_update == 0u && one_cycle->alpha_compare == 0u,
                "one-cycle no-Z/alpha policy") ||
        !expect(one_cycle->raw_combine_w0 == UINT32_C(0x00ffffff) &&
                    one_cycle->raw_combine_w1 == UINT32_C(0xfffe793c),
                "one-cycle combiner words") ||
        !expect(two_cycle->cycle_type == 1u && two_cycle->texture_lod == 0u &&
                    two_cycle->raw_render_mode == GE_TITLE_RASTER_V5_L_TWO_CYCLE,
                "two-cycle render mode") ||
        !expect(two_cycle->raw_combine_w0 == UINT32_C(0x0026a004) &&
                    two_cycle->raw_combine_w1 == UINT32_C(0x1f1093ff),
                "two-cycle combiner words") ||
        !expect(two_cycle->state_hash == UINT64_C(14325430380512944885),
                "two-cycle state hash") ||
        !expect(forced_blend->force_blend == 1u &&
                    (forced_blend->lowering_flags &
                     GE_TITLE_RASTER_V5_DEFERRED_FORCE_BLEND) != 0u,
                "forced blend remains explicit/deferred") ||
        !expect((one_cycle->lowering_flags & GE_TITLE_RASTER_V5_DEFERRED_COVERAGE) != 0u,
                "coverage remains explicit/deferred") ||
        !expect(rareware_one_cycle->source_model_mask ==
                    GE_TITLE_RASTER_V5_SOURCE_RAREWARE &&
                    rareware_one_cycle->raw_render_mode ==
                    GE_TITLE_RASTER_V5_L_RAREWARE_ONE_CYCLE,
                "Rareware one-cycle render mode") ||
        !expect(rareware_one_cycle->raw_combine_w0 == UINT32_C(0x00119623) &&
                    rareware_one_cycle->raw_combine_w1 == UINT32_C(0x002c0000),
                "Rareware one-cycle combiner words") ||
        !expect(rareware_two_cycle->cycle_type == 1u &&
                    rareware_two_cycle->raw_render_mode ==
                    GE_TITLE_RASTER_V5_L_RAREWARE_TWO_CYCLE &&
                    rareware_two_cycle->force_blend == 1u,
                "Rareware two-cycle pass/opaque mode") ||
        !expect(rareware_one_cycle->state_hash == UINT64_C(4869127886211691057) &&
                    rareware_two_cycle->state_hash == UINT64_C(7104847914507670581),
                "Rareware state hashes")) {
        return 1;
    }

    printf("title-raster-v5: PASS states=%" PRIu32 " aggregate=%" PRIu64
           " oneCycleHash=%" PRIu64 " twoCycleHash=%" PRIu64
           " forcedBlendHash=%" PRIu64 "\n",
           first.state_count,
           first.aggregate_hash,
           one_cycle->state_hash,
           two_cycle->state_hash,
           forced_blend->state_hash);

    GETitleRasterInputV5 malformed = ge_title_raster_source_vector_v5();
    malformed.header.abi_version = GE_NATIVE_ABI_VERSION + 1u;
    if (!expect(ge_title_lower_raster_v5(malformed).status == GE_STATUS_INVALID_VERSION,
                "version rejection")) {
        return 1;
    }
    malformed.header.abi_version = GE_NATIVE_ABI_VERSION;
    malformed.states[0].reserved = 1u;
    if (!expect(ge_title_lower_raster_v5(malformed).status == GE_STATUS_RESERVED_BITS,
                "state reserved rejection")) {
        return 1;
    }
    malformed.states[0].reserved = 0u;
    malformed.states[1].raw_combine_w1 = UINT32_C(0xdeadbeef);
    if (!expect(ge_title_lower_raster_v5(malformed).status == GE_STATUS_UNSUPPORTED_COMMAND,
                "unsupported tuple rejection")) {
        return 1;
    }
    malformed.states[1].raw_combine_w1 = UINT32_C(0xff33ffff);
    malformed.reserved = 1u;
    if (!expect(ge_title_lower_raster_v5(malformed).status == GE_STATUS_RESERVED_BITS,
                "input reserved rejection")) {
        return 1;
    }
    malformed.reserved = 0u;
    malformed.states[3].source_model_mask = GE_TITLE_RASTER_V5_SOURCE_WALLET;
    if (!expect(ge_title_lower_raster_v5(malformed).status == GE_STATUS_INVALID_ARGUMENT,
                "source mask mismatch rejection")) {
        return 1;
    }
    return 0;
}
