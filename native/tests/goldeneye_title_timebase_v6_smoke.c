#include "ge_source_frontend_v6.h"

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef struct TimebaseProbe {
    GEFrontendRenderEventV6 events[32];
    uint32_t count;
    uint32_t half_step_models;
} TimebaseProbe;

static uint64_t hash_mix(uint64_t hash, uint64_t value)
{
    uint32_t index;

    for (index = 0u; index < 8u; index++) {
        hash ^= (value >> (index * 8u)) & 0xffu;
        hash *= UINT64_C(1099511628211);
    }
    return hash;
}

static GEStatusV1 probe_render(
    const GEFrontendRenderEventV6 *event,
    void *opaque)
{
    TimebaseProbe *probe = (TimebaseProbe *)opaque;

    assert(event != NULL);
    assert(probe != NULL);
    assert(event->header.abi_version == GE_NATIVE_ABI_VERSION);
    assert(event->header.struct_size == sizeof(*event));
    assert(event->record_version == GE_SOURCE_FRONTEND_V6_RECORD_VERSION);
    assert(event->reserved0 == 0u);
    assert(event->reserved1 == 0u);
    assert(probe->count < 32u);
    probe->events[probe->count++] = *event;
    return GE_STATUS_OK;
}

static GEStatusV1 probe_model(
    const GEFrontendModelEventV6 *event,
    GEFrontendModelResultV6 *result,
    void *opaque)
{
    TimebaseProbe *probe = (TimebaseProbe *)opaque;

    assert(event != NULL);
    assert(result != NULL);
    if (probe != NULL && event != NULL &&
        (event->flags & GE_SOURCE_FRONTEND_V6_MODEL_FLAG_HALF_STEP) != 0u) {
        probe->half_step_models++;
    }
    result->flags = GE_SOURCE_FRONTEND_V6_MODEL_RESULT_EXECUTED;
    return GE_STATUS_OK;
}

static GEFrontendCallbacksV6 callbacks_for(TimebaseProbe *probe)
{
    GEFrontendCallbacksV6 callbacks;

    memset(&callbacks, 0, sizeof(callbacks));
    callbacks.model = probe_model;
    callbacks.render = probe_render;
    callbacks.context = probe;
    return callbacks;
}

static void input_for(GEFrontendStateV6 *state, GEFrontendInputV6 *input)
{
    memset(input, 0, sizeof(*input));
    input->header.abi_version = GE_NATIVE_ABI_VERSION;
    input->header.struct_size = sizeof(*input);
    input->record_version = GE_SOURCE_FRONTEND_V6_RECORD_VERSION;
    input->controller_count = 1u;
    input->native_tick = state->native_tick + 1u;
    input->sequence = input->native_tick;
    if ((input->native_tick & 1u) == 0u) {
        input->flags |= GE_SOURCE_FRONTEND_V6_INPUT_FLAG_SOURCE_ANCHOR;
    }
}

static const GEFrontendRenderEventV6 *find_continuous(
    const TimebaseProbe *probe,
    uint32_t subphase)
{
    uint32_t index;

    for (index = 0u; index < probe->count; index++) {
        const GEFrontendRenderEventV6 *event = &probe->events[index];
        if (event->operation == GE_SOURCE_FRONTEND_V6_RENDER_CONTINUOUS_STATE &&
            event->subphase == subphase) {
            return event;
        }
    }
    return NULL;
}

static const GEFrontendRenderEventV6 *find_pipeline(
    const TimebaseProbe *probe,
    uint32_t operation)
{
    uint32_t index;

    for (index = 0u; index < probe->count; index++) {
        if (probe->events[index].operation == operation) {
            return &probe->events[index];
        }
    }
    return NULL;
}

static void reset_state_for_screen(
    GEFrontendStateV6 *state,
    uint32_t screen)
{
    state->screen = screen;
    state->pending_reload = GE_SOURCE_FRONTEND_V6_SCREEN_INVALID;
    state->pending_direct = GE_SOURCE_FRONTEND_V6_SCREEN_INVALID;
    state->flags = 0u;
    state->native_tick = 2u;
    state->source_timer = screen == GE_SOURCE_FRONTEND_V6_SCREEN_RAREWARE ? 4u : 1u;
    state->rareware_mode = GE_SOURCE_FRONTEND_V6_RAREWARE_MODE_INIT;
    state->rareware_counter = 1u;
    state->gunbarrel_mode = GE_SOURCE_FRONTEND_V6_GUNBARREL_MODE_INIT;
    state->gunbarrel_counter = 4u;
    state->gunbarrel_title_x_q16 = -1000;
    state->gunbarrel_transition_x_q16 = -2000;
    state->gunbarrel_word = 0x42u;
    state->event_sequence = 0u;
}

static void test_nintendo_half_step(
    GEFrontendStateV6 *state,
    const GEFrontendCallbacksV6 *callbacks)
{
    GEFrontendInputV6 input;
    GEFrontendSnapshotV6 snapshot;
    TimebaseProbe *probe = (TimebaseProbe *)callbacks->context;
    const GEFrontendRenderEventV6 *rotation_scale;
    const GEFrontendRenderEventV6 *ambient;

    memset(probe, 0, sizeof(*probe));
    reset_state_for_screen(state, GE_SOURCE_FRONTEND_V6_SCREEN_NINTENDO);
    input_for(state, &input);
    assert(input.native_tick == 3u);
    assert(ge_frontend_v6_step_native_source_ordered(
               state, &input, callbacks, &snapshot) == GE_STATUS_OK);
    rotation_scale = find_continuous(
        probe, GE_SOURCE_FRONTEND_V6_CONTINUOUS_NINTENDO_ROTATION_SCALE);
    ambient = find_continuous(
        probe, GE_SOURCE_FRONTEND_V6_CONTINUOUS_NINTENDO_AMBIENT);
    assert(rotation_scale != NULL);
    assert(ambient != NULL);
    assert((rotation_scale->flags & GE_SOURCE_FRONTEND_V6_RENDER_FLAG_HALF_STEP) != 0u);
    assert((rotation_scale->flags & GE_SOURCE_FRONTEND_V6_RENDER_FLAG_Q16_VALUES) != 0u);
    /* front.c increments rotation before matrix construction: timer=1 uses
     * -79 degrees and the next source render uses -78. */
    assert(rotation_scale->value0 == -5144576);
    /* The shared matrix-provider convention counts one committed scale
     * multiplier at timer=1: 1298 -> 1402, midpoint 1350. */
    assert(rotation_scale->value1 == 1350);
    assert(ambient->value0 == 255 * 65536);
    assert(snapshot.render_hash != hash_mix(
        UINT64_C(1469598103934665603),
        ((uint64_t)GE_SOURCE_FRONTEND_V6_SCREEN_NINTENDO << 32u) | 2u));
    assert(state->event_sequence == 0u);
}

static void test_rareware_half_step(
    GEFrontendStateV6 *state,
    const GEFrontendCallbacksV6 *callbacks)
{
    GEFrontendInputV6 input;
    GEFrontendSnapshotV6 snapshot;
    TimebaseProbe *probe = (TimebaseProbe *)callbacks->context;
    const GEFrontendRenderEventV6 *event;

    memset(probe, 0, sizeof(*probe));
    reset_state_for_screen(state, GE_SOURCE_FRONTEND_V6_SCREEN_RAREWARE);
    input_for(state, &input);
    assert(ge_frontend_v6_step_native_source_ordered(
               state, &input, callbacks, &snapshot) == GE_STATUS_OK);
    event = find_continuous(
        probe, GE_SOURCE_FRONTEND_V6_CONTINUOUS_RAREWARE_ROTATION_ALPHA);
    assert(event != NULL);
    /* Counter=1: visual rotation endpoints are 2 and 4 degrees. */
    assert(event->value0 == 196608);
    assert(event->value1 >= 0);
    assert(event->value1 < 255 * 65536);
    assert(state->rareware_counter == 1u);
    assert(state->event_sequence == 0u);
}

static void test_gunbarrel_half_step(
    GEFrontendStateV6 *state,
    const GEFrontendCallbacksV6 *callbacks)
{
    GEFrontendInputV6 input;
    GEFrontendSnapshotV6 snapshot;
    TimebaseProbe *probe = (TimebaseProbe *)callbacks->context;
    const GEFrontendRenderEventV6 *pipeline;
    const GEFrontendRenderEventV6 *translation;
    const GEFrontendRenderEventV6 *counter_word;

    memset(probe, 0, sizeof(*probe));
    reset_state_for_screen(state, GE_SOURCE_FRONTEND_V6_SCREEN_GUNBARREL);
    input_for(state, &input);
    assert(ge_frontend_v6_step_native_source_ordered(
               state, &input, callbacks, &snapshot) == GE_STATUS_OK);
    pipeline = find_pipeline(
        probe, GE_SOURCE_FRONTEND_V6_RENDER_GUNBARREL_PIPELINE);
    translation = find_continuous(
        probe, GE_SOURCE_FRONTEND_V6_CONTINUOUS_GUNBARREL_TRANSLATION);
    counter_word = find_continuous(
        probe, GE_SOURCE_FRONTEND_V6_CONTINUOUS_GUNBARREL_COUNTER_WORD);
    assert(pipeline != NULL);
    assert(translation != NULL);
    assert(counter_word != NULL);
    assert(probe->half_step_models == 1u);
    assert((pipeline->flags & GE_SOURCE_FRONTEND_V6_RENDER_FLAG_HALF_STEP) != 0u);
    /* XINC is six source units, so the odd projection is three units. */
    assert(pipeline->value0 == state->gunbarrel_title_x_q16 + 196608);
    assert(state->gunbarrel_title_x_q16 == -1000);
    assert(counter_word->value1 < (int32_t)(0x42u << 16));
    assert(state->event_sequence == 0u);
}

static void test_odd_input_edge(
    GEFrontendStateV6 *state,
    const GEFrontendCallbacksV6 *callbacks)
{
    GEFrontendInputV6 input;
    GEFrontendSnapshotV6 snapshot;
    TimebaseProbe *probe = (TimebaseProbe *)callbacks->context;

    memset(probe, 0, sizeof(*probe));
    reset_state_for_screen(state, GE_SOURCE_FRONTEND_V6_SCREEN_NINTENDO);
    state->flags = 0u; /* source has already visited the main menu */
    input_for(state, &input);
    input.buttons_pressed = GE_SOURCE_FRONTEND_V6_BUTTON_ANY;
    assert((input.native_tick & 1u) != 0u);
    assert(ge_frontend_v6_step_native_source_ordered(
               state, &input, callbacks, &snapshot) == GE_STATUS_OK);
    /* The odd press is visible immediately as a source-owned pending action;
     * the switch-screen autonomous commit remains on the next even anchor. */
    assert(state->pending_reload == GE_SOURCE_FRONTEND_V6_SCREEN_FILE_SELECT);
    assert(state->screen == GE_SOURCE_FRONTEND_V6_SCREEN_NINTENDO);
}

static void test_odd_threshold_does_not_branch(
    GEFrontendStateV6 *state,
    const GEFrontendCallbacksV6 *callbacks)
{
    GEFrontendInputV6 input;
    GEFrontendSnapshotV6 snapshot;
    TimebaseProbe *probe = (TimebaseProbe *)callbacks->context;

    memset(probe, 0, sizeof(*probe));
    reset_state_for_screen(state, GE_SOURCE_FRONTEND_V6_SCREEN_NINTENDO);
    state->source_timer = GE_SOURCE_FRONTEND_V6_NINTENDO_TIMER_MAX - 1u;
    input_for(state, &input);
    assert((input.native_tick & 1u) != 0u);
    assert(ge_frontend_v6_step_native_source_ordered(
               state, &input, callbacks, &snapshot) == GE_STATUS_OK);
    assert(state->source_timer == GE_SOURCE_FRONTEND_V6_NINTENDO_TIMER_MAX - 1u);
    assert(state->pending_reload == GE_SOURCE_FRONTEND_V6_SCREEN_INVALID);
    assert(state->screen == GE_SOURCE_FRONTEND_V6_SCREEN_NINTENDO);

    input_for(state, &input);
    assert((input.native_tick & 1u) == 0u);
    assert(ge_frontend_v6_step_native_source_ordered(
               state, &input, callbacks, &snapshot) == GE_STATUS_OK);
    assert(state->screen == GE_SOURCE_FRONTEND_V6_SCREEN_SWITCH);
    assert(state->pending_reload == GE_SOURCE_FRONTEND_V6_SCREEN_RAREWARE);
    assert(state->transition_timer == 0u);
}

int main(void)
{
    GEFrontendStateV6 state;
    GEFrontendCallbacksV6 callbacks;
    TimebaseProbe probe;

    memset(&probe, 0, sizeof(probe));
    callbacks = callbacks_for(&probe);
    assert(ge_frontend_v6_init(&state, &callbacks) == GE_STATUS_OK);
    test_nintendo_half_step(&state, &callbacks);
    test_rareware_half_step(&state, &callbacks);
    test_gunbarrel_half_step(&state, &callbacks);
    test_odd_input_edge(&state, &callbacks);
    test_odd_threshold_does_not_branch(&state, &callbacks);
    printf("goldeneye_title_timebase_v6_smoke: PASS\n");
    return 0;
}
