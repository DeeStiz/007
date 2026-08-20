#include "ge_title_reference_v5.h"

#include <assert.h>
#include <stdio.h>

static void advance_reference(GETitleReferenceStateV5 *state, uint32_t frames)
{
    for (uint32_t frame = 0u; frame < frames; frame++) {
        *state = ge_title_reference_step_v5(*state);
        assert(ge_title_reference_validate_v5(state) == GE_STATUS_OK);
    }
}

int main(void)
{
    const uint32_t source_ticks[] = {241u, 501u, 290u, 180u, 90u, 1801u, 181u};
    const uint32_t native_ticks[] = {482u, 1002u, 580u, 360u, 180u, 3602u, 362u};
    for (uint32_t index = 0u; index < sizeof(source_ticks) / sizeof(source_ticks[0]); index++) {
        assert(source_ticks[index] <= UINT32_MAX / 2u);
        assert(source_ticks[index] * 2u == native_ticks[index]);
    }

    const uint64_t audio_samples[] = {0u, 183u, 367u, 551u, 735u, 918u, 1102u, 1286u, 1470u};
    for (uint64_t tick = 0u; tick < sizeof(audio_samples) / sizeof(audio_samples[0]); tick++) {
        assert((tick * 735u) / 4u == audio_samples[tick]);
    }

    GETitleReferenceStateV5 state = ge_title_reference_initial_v5();
    GETitleReferenceStateV5 repeat = ge_title_reference_initial_v5();
    assert(ge_title_reference_validate_v5(&state) == GE_STATUS_OK);
    assert(state.state_hash == repeat.state_hash && state.render_hash == repeat.render_hash);

    advance_reference(&state, GE_TITLE_REFERENCE_V5_LEGAL_TICKS + GE_TITLE_REFERENCE_V5_TRANSITION_FRAMES);
    assert(state.screen == GE_TITLE_SCREEN_NINTENDO && state.timer == 0u);
    advance_reference(&state, GE_TITLE_REFERENCE_V5_NINTENDO_TICKS + GE_TITLE_REFERENCE_V5_TRANSITION_FRAMES);
    assert(state.screen == GE_TITLE_SCREEN_RAREWARE && state.timer == 0u);
    advance_reference(&state, GE_TITLE_REFERENCE_V5_RAREWARE_TICKS + GE_TITLE_REFERENCE_V5_TRANSITION_FRAMES);
    assert(state.screen == GE_TITLE_SCREEN_GUNBARREL && state.timer == 0u);

    puts("goldeneye_title_timebase_v5_smoke: PASS");
    return 0;
}
