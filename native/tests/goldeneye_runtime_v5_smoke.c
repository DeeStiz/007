#include "goldeneye_native.h"

#include <stdio.h>
#include <string.h>

static void set_header(GEAbiHeaderV1 *header, size_t size)
{
    header->abi_version = GE_NATIVE_ABI_VERSION;
    header->struct_size = (uint32_t)size;
}

int main(void)
{
    const uint32_t expected_frames[4] = {183u, 184u, 184u, 184u};
    const uint64_t expected_samples[5] = {0u, 183u, 367u, 551u, 735u};
    for (uint64_t tick = 0; tick < 4u; tick++) {
        if (ge_audio_frame_count_for_tick_v5(tick) != expected_frames[tick] ||
            ge_audio_sample_index_for_tick_v5(tick) != expected_samples[tick]) {
            fprintf(stderr, "audio clock mismatch at tick %llu\n", (unsigned long long)tick);
            return 1;
        }
    }
    if (ge_audio_sample_index_for_tick_v5(4u) != expected_samples[4]) {
        return 1;
    }

    GETimebaseConfigV5 timebase;
    memset(&timebase, 0, sizeof(timebase));
    set_header(&timebase.header, sizeof(timebase));
    timebase.record_version = GE_RUNTIME_V5_RECORD_VERSION;
    timebase.native_hz = 120u;
    timebase.reference_hz = 60u;
    timebase.pair_numerator = 2u;
    timebase.pair_denominator = 1u;
    timebase.max_catch_up_ticks = 4u;
    timebase.max_tick_debt = 240u;
    timebase.policy_flags = GE_RUNTIME_V5_TIMEBASE_POLICY_MASK;
    timebase.audio_sample_rate = GE_AUDIO_V5_SAMPLE_RATE;
    if (ge_runtime_v5_validate_timebase(&timebase) != GE_STATUS_OK ||
        ge_runtime_v5_hash_timebase(&timebase) == 0u) {
        fprintf(stderr, "timebase validation failed\n");
        return 1;
    }

    uint32_t first = 0u;
    uint32_t count = 0u;
    if (ge_runtime_v5_scene_page_bounds(17u, 32u, 1u, 8u, &first, &count) != GE_STATUS_OK ||
        first != 8u || count != 8u) {
        fprintf(stderr, "scene page bounds failed\n");
        return 1;
    }

    printf("goldeneye_runtime_v5_smoke: PASS\n");
    return 0;
}
