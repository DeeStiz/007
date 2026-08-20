#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "ge_source_frontend_runtime_v6.h"
#include "ge_original_frontend_v6.h"

static void runtime_input(
    GEFrontendRuntimeV6Input *input,
    uint64_t native_tick,
    uint32_t buttons)
{
    memset(input, 0, sizeof(*input));
    input->header.abi_version = GE_NATIVE_ABI_VERSION;
    input->header.struct_size = (uint32_t)sizeof(*input);
    input->record_version = GE_SOURCE_FRONTEND_RUNTIME_V6_RECORD_VERSION;
    input->flags = GE_SOURCE_FRONTEND_RUNTIME_V6_INPUT_FLAG_FOCUSED |
        GE_SOURCE_FRONTEND_RUNTIME_V6_INPUT_FLAG_CONTROLLER_CONNECTED |
        GE_SOURCE_FRONTEND_RUNTIME_V6_INPUT_FLAG_SYNTHETIC;
    if ((native_tick & 1u) == 0u) {
        input->flags |= GE_SOURCE_FRONTEND_RUNTIME_V6_INPUT_FLAG_SOURCE_ANCHOR;
    }
    input->buttons_pressed = buttons;
    input->controller_count = 1u;
    input->clock_timer = 1u;
    input->native_tick = native_tick;
    input->sequence = native_tick;
}

static void original_input(
    GEOriginalFrontendInputV6 *input,
    uint64_t native_tick,
    uint32_t buttons)
{
    memset(input, 0, sizeof(*input));
    input->header.abi_version = GE_NATIVE_ABI_VERSION;
    input->header.struct_size = (uint32_t)sizeof(*input);
    input->record_version = GE_ORIGINAL_FRONTEND_V6_RECORD_VERSION;
    input->flags = GE_ORIGINAL_FRONTEND_V6_INPUT_CAPTURE_RENDER |
        GE_ORIGINAL_FRONTEND_V6_INPUT_CONNECTED |
        GE_ORIGINAL_FRONTEND_V6_INPUT_SYNTHETIC;
    input->buttons_pressed = buttons;
    input->controller_count = 1u;
    input->clock_timer = 1u;
    input->native_tick = native_tick;
    input->sequence = native_tick;
}

static const GEFrontendRuntimeV6AudioEvent *find_runtime_audio(
    const GEFrontendRuntimeV6Frame *frame,
    uint32_t operation)
{
    uint32_t index;

    for (index = 0u; index < frame->events.audio_count; index++) {
        if (frame->events.audio[index].operation == operation) {
            return &frame->events.audio[index];
        }
    }
    return NULL;
}

static uint32_t runtime_transition_count(
    const GEFrontendRuntimeV6Frame *frame,
    uint32_t *target,
    uint32_t *source_timer)
{
    uint32_t count = 0u;
    uint32_t index;

    *target = UINT32_MAX;
    *source_timer = 0u;
    for (index = 0u; index < frame->events.screen_count; index++) {
        const GEFrontendRuntimeV6ScreenEvent *event = &frame->events.screens[index];
        if (event->event == GE_SOURCE_FRONTEND_RUNTIME_V6_EVENT_TRANSITION) {
            count++;
            *target = event->target_screen;
            *source_timer = event->source_timer;
        }
    }
    return count;
}

static uint32_t original_transition_count(
    const GEOriginalFrontendEventV6 *events,
    uint32_t count,
    uint32_t *target,
    uint32_t *source_timer)
{
    uint32_t result = 0u;
    uint32_t index;

    *target = UINT32_MAX;
    *source_timer = 0u;
    for (index = 0u; index < count; index++) {
        if (events[index].kind == GE_ORIGINAL_FRONTEND_V6_EVENT_SCREEN &&
            events[index].operation ==
                GE_ORIGINAL_FRONTEND_V6_OP_TRANSITION_REQUEST) {
            result++;
            *target = events[index].target_screen;
            *source_timer = events[index].source_timer;
        }
    }
    return result;
}

static uint32_t runtime_audio_count(
    const GEFrontendRuntimeV6Frame *frame,
    uint32_t *operations,
    uint32_t *assets)
{
    uint32_t index;

    for (index = 0u; index < frame->events.audio_count; index++) {
        const GEFrontendRuntimeV6AudioEvent *event = &frame->events.audio[index];
        switch (event->operation) {
        case GE_SOURCE_FRONTEND_RUNTIME_V6_AUDIO_OP_STOP_MUSIC:
            operations[index] = GE_ORIGINAL_FRONTEND_V6_OP_AUDIO_STOP;
            break;
        case GE_SOURCE_FRONTEND_RUNTIME_V6_AUDIO_OP_PLAY_MUSIC:
            operations[index] = GE_ORIGINAL_FRONTEND_V6_OP_AUDIO_MUSIC;
            break;
        case GE_SOURCE_FRONTEND_RUNTIME_V6_AUDIO_OP_PLAY_SFX:
            operations[index] = GE_ORIGINAL_FRONTEND_V6_OP_AUDIO_SFX;
            break;
        default:
            operations[index] = UINT32_MAX;
            break;
        }
        assets[index] = event->asset_id;
    }
    return frame->events.audio_count;
}

static uint32_t original_audio_count(
    const GEOriginalFrontendEventV6 *events,
    uint32_t count,
    uint32_t *operations,
    uint32_t *assets)
{
    uint32_t result = 0u;
    uint32_t index;

    for (index = 0u; index < count; index++) {
        if (events[index].kind == GE_ORIGINAL_FRONTEND_V6_EVENT_AUDIO) {
            operations[result] = events[index].operation;
            assets[result] = events[index].value0;
            result++;
        }
    }
    return result;
}

static void compare_even_anchor(
    const GEFrontendRuntimeV6Frame *runtime_frame,
    const GEFrontendRuntimeV6State *runtime_state,
    const GEOriginalFrontendFrameV6 *original_frame,
    const GEOriginalFrontendEventV6 *original_events,
    uint32_t original_event_count)
{
    uint32_t runtime_target;
    uint32_t runtime_timer;
    uint32_t original_target;
    uint32_t original_timer;
    uint32_t runtime_transition;
    uint32_t original_transition;
    uint32_t runtime_operations[GE_SOURCE_FRONTEND_RUNTIME_V6_MAX_EVENTS];
    uint32_t runtime_assets[GE_SOURCE_FRONTEND_RUNTIME_V6_MAX_EVENTS];
    uint32_t original_operations[GE_SOURCE_FRONTEND_RUNTIME_V6_MAX_EVENTS];
    uint32_t original_assets[GE_SOURCE_FRONTEND_RUNTIME_V6_MAX_EVENTS];
    uint32_t runtime_audio;
    uint32_t original_audio;
    uint32_t index;

    if ((runtime_frame->snapshot.screen == GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_RAREWARE &&
         (runtime_state->rareware_mode != original_frame->rareware_mode ||
          runtime_state->rareware_counter != original_frame->rareware_counter)) ||
        (runtime_frame->snapshot.screen == GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL &&
         (runtime_state->gunbarrel_mode != original_frame->gunbarrel_mode ||
          runtime_state->gunbarrel_counter != original_frame->gunbarrel_counter))) {
        fprintf(stderr,
                "source frontend V6 mode mismatch: tick=%llu "
                "rare %u/%u counter %u/%u gun %u/%u counter %u/%u\n",
                (unsigned long long)runtime_frame->snapshot.native_tick,
                runtime_state->rareware_mode, original_frame->rareware_mode,
                runtime_state->rareware_counter, original_frame->rareware_counter,
                runtime_state->gunbarrel_mode, original_frame->gunbarrel_mode,
                runtime_state->gunbarrel_counter, original_frame->gunbarrel_counter);
        assert(0 && "mode/counter parity mismatch");
    }

    /* This is intentionally exact.  A mismatch is a source-fidelity gap, not
     * a reason to hide the difference behind a translated timer. */
    if (runtime_frame->snapshot.screen != original_frame->screen ||
        runtime_frame->snapshot.source_timer != original_frame->source_timer ||
        runtime_frame->snapshot.transition_timer != original_frame->transition_timer) {
        fprintf(stderr,
                "source frontend V6 parity mismatch: tick=%llu "
                "screen %u/%u timer %u/%u transition %u/%u\n",
                (unsigned long long)runtime_frame->snapshot.native_tick,
                runtime_frame->snapshot.screen, original_frame->screen,
                runtime_frame->snapshot.source_timer, original_frame->source_timer,
                runtime_frame->snapshot.transition_timer, original_frame->transition_timer);
        assert(0 && "screen/timer/transition parity mismatch");
    }

    runtime_transition = runtime_transition_count(
        runtime_frame, &runtime_target, &runtime_timer);
    original_transition = original_transition_count(
        original_events, original_event_count, &original_target, &original_timer);
    if (runtime_transition != original_transition ||
        (runtime_transition != 0u &&
         (runtime_target != original_target || runtime_timer != original_timer))) {
        fprintf(stderr,
                "source frontend V6 transition mismatch: tick=%llu "
                "count %u/%u target %u/%u timer %u/%u\n",
                (unsigned long long)runtime_frame->snapshot.native_tick,
                runtime_transition, original_transition,
                runtime_target, original_target, runtime_timer, original_timer);
        assert(0 && "transition parity mismatch");
    }

    runtime_audio = runtime_audio_count(
        runtime_frame, runtime_operations, runtime_assets);
    original_audio = original_audio_count(
        original_events, original_event_count, original_operations, original_assets);
    if (runtime_audio != original_audio) {
        fprintf(stderr,
                "source frontend V6 audio count mismatch: tick=%llu %u/%u\n",
                (unsigned long long)runtime_frame->snapshot.native_tick,
                runtime_audio, original_audio);
        assert(0 && "audio event count mismatch");
    }
    for (index = 0u; index < runtime_audio; index++) {
        if (runtime_operations[index] != original_operations[index] ||
            runtime_assets[index] != original_assets[index]) {
            fprintf(stderr,
                    "source frontend V6 audio mismatch: tick=%llu index=%u "
                    "op %u/%u asset %u/%u\n",
                    (unsigned long long)runtime_frame->snapshot.native_tick,
                    index, runtime_operations[index], original_operations[index],
                    runtime_assets[index], original_assets[index]);
            assert(0 && "audio event mismatch");
        }
    }
}

static void test_value_only_runtime(void)
{
    GEFrontendRuntimeV6State state;
    GEFrontendRuntimeV6Frame frame;
    GEFrontendRuntimeV6Input input;
    GEFrontendRuntimeV6State malformed_state;

    assert(ge_frontend_runtime_v6_init(&state, &frame) == GE_STATUS_OK);
    assert(ge_frontend_runtime_v6_validate_state(&state) == GE_STATUS_OK);
    assert(ge_frontend_runtime_v6_validate_frame(&frame) == GE_STATUS_OK);
    assert(state.screen == GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_LEGAL);
    assert(state.native_tick == 0u);
    assert(frame.events.model_count != 0u);
    assert(state.unsupported_count == 0u);
    assert(frame.events.diagnostic_count == 0u);
    assert(frame.events.models[0].result_flags ==
           GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_NONE);
    {
        uint32_t index;
        for (index = 0u; index < frame.events.diagnostic_count; index++) {
            assert(frame.events.diagnostics[index].code !=
                   GE_SOURCE_FRONTEND_RUNTIME_V6_DIAG_UNSUPPORTED_RENDER);
        }
    }

    runtime_input(&input, 1u, GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_NONE);
    assert(ge_frontend_runtime_v6_step(&state, &input, &frame) == GE_STATUS_OK);
    assert(state.source_timer == 0u);
    assert(state.unsupported_count == 0u);
    assert(frame.events.model_count != 0u);
    assert(frame.events.models[0].result_flags ==
           GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_NONE);
    assert(frame.snapshot.diagnostic_count == 0u);
    runtime_input(&input, 2u, GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_NONE);
    input.model_result_model = GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_LEGALPAGE;
    input.model_result_operation = GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_DRAW;
    input.model_result_flags = GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_EXECUTED;
    assert(ge_frontend_runtime_v6_step(&state, &input, &frame) == GE_STATUS_OK);
    assert(state.source_timer == 1u);
    assert(state.unsupported_count == 0u);
    assert(frame.snapshot.diagnostic_count == 0u);
    assert(frame.events.model_count != 0u);
    assert(frame.events.models[0].result_flags ==
           GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_EXECUTED);

    malformed_state = state;
    malformed_state.reserved0 = 1u;
    assert(ge_frontend_runtime_v6_validate_state(&malformed_state) ==
           GE_STATUS_MALFORMED_STREAM);
    runtime_input(&input, 4u, GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_NONE);
    assert(ge_frontend_runtime_v6_step(&state, &input, &frame) ==
           GE_STATUS_INVALID_STATE);
}

static void test_audio_source_samples(void)
{
    uint64_t tick;

    for (tick = 1u; tick <= 8u; tick++) {
        GEFrontendRuntimeV6State state;
        GEFrontendRuntimeV6Frame frame;
        GEFrontendRuntimeV6Input input;
        const GEFrontendRuntimeV6AudioEvent *audio;

        assert(ge_frontend_runtime_v6_init(&state, &frame) == GE_STATUS_OK);
        state.native_tick = tick - 1u;
        state.pending_direct = GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_NINTENDO;
        runtime_input(&input, tick, GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_NONE);
        assert(ge_frontend_runtime_v6_step(&state, &input, &frame) == GE_STATUS_OK);
        audio = find_runtime_audio(
            &frame, GE_SOURCE_FRONTEND_RUNTIME_V6_AUDIO_OP_PLAY_MUSIC);
        assert(audio != NULL);
        assert(audio->native_tick == tick);
        assert(audio->source_sample == (tick * 735u) / 4u);
        if ((tick & 1u) != 0u) {
            /* Odd input-triggered cues must not reuse the paired 60 Hz
             * expression; ticks one and three are explicit regressions. */
            assert(audio->source_sample == (tick * 735u) / 4u);
        }
    }
}

static void test_exact_oracle_comparison(void)
{
    GEFrontendRuntimeV6State runtime_state;
    GEFrontendRuntimeV6Frame runtime_frame;
    GEFrontendRuntimeV6Input runtime_tick_input;
    GEOriginalFrontendStateV6 oracle_state;
    GEOriginalFrontendInputV6 oracle_input;
    GEOriginalFrontendEventV6 oracle_events[128];
    GEOriginalFrontendFrameV6 oracle_frame;
    uint32_t oracle_count;
    uint64_t native_tick = 0u;
    uint32_t previous_screen;
    uint32_t reached_goldeneye = 0u;
    uint32_t buttons = GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_NONE;

    assert(ge_frontend_runtime_v6_init(&runtime_state, &runtime_frame) == GE_STATUS_OK);
    assert(ge_original_frontend_v6_init(&oracle_state) == GE_STATUS_OK);
    while (reached_goldeneye == 0u) {
        assert(native_tick < 4000u);
        previous_screen = runtime_state.screen;

        native_tick++;
        runtime_input(&runtime_tick_input, native_tick,
                      GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_NONE);
        assert(ge_frontend_runtime_v6_step(
                   &runtime_state, &runtime_tick_input, &runtime_frame) ==
               GE_STATUS_OK);

        assert((native_tick & 1u) != 0u);
        native_tick++;
        runtime_input(&runtime_tick_input, native_tick, buttons);
        runtime_tick_input.model_result_model =
            GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GUNBARREL;
        runtime_tick_input.model_result_operation =
            GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_BLOOD_TICK;
        runtime_tick_input.model_result_flags =
            GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_BLOOD_COMPLETE |
            GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_EXECUTED;
        assert(ge_frontend_runtime_v6_step(
                   &runtime_state, &runtime_tick_input, &runtime_frame) ==
               GE_STATUS_OK);

        original_input(&oracle_input, native_tick, buttons);
        assert(ge_original_frontend_v6_step(
                   &oracle_state, &oracle_input, oracle_events, 128u,
                   &oracle_count, &oracle_frame) == GE_STATUS_OK);
        compare_even_anchor(
            &runtime_frame, &runtime_state, &oracle_frame,
            oracle_events, oracle_count);

        if (runtime_state.screen != previous_screen) {
            printf("source frontend V6 compared screen=%u at tick=%llu\n",
                   runtime_state.screen, (unsigned long long)native_tick);
        }
        if (runtime_state.screen == GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GOLDENEYE) {
            reached_goldeneye = 1u;
        }
    }
    assert(runtime_state.screen == GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GOLDENEYE);
    assert(oracle_state.screen == GE_ORIGINAL_FRONTEND_V6_SCREEN_GOLDENEYE);
    printf("source frontend V6 exact even-anchor oracle comparison: PASS\n");
}

int main(int argc, char **argv)
{
    test_value_only_runtime();
    test_audio_source_samples();
    if (argc > 1 && strcmp(argv[1], "--compare") == 0) {
        test_exact_oracle_comparison();
    }
    printf("goldeneye_source_frontend_runtime_v6_smoke: PASS\n");
    return 0;
}
