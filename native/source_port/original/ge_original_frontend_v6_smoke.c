#include "ge_original_frontend_v6.h"
#include "ge_original_host_compat.h"
#include <gbi_extension.h>

#include <assert.h>
#include <stdio.h>
#include <string.h>

#if defined(F3DEX_GBI_2)
#error "The source reference must use the classic GE/F3D command dialect"
#endif
_Static_assert(G_MTX == 1u, "classic G_MTX opcode drift");
_Static_assert(G_VTX == 4u, "classic G_VTX opcode drift");
_Static_assert(G_DL == 6u, "classic G_DL opcode drift");
_Static_assert(((uint32_t)(uint8_t)G_TRI4) == 0xb1u,
               "classic GE TRI4 opcode drift");

extern uint32_t ge_original_host_render_dialect_flags(void);
extern uint32_t ge_original_host_render_resource_word_safety(void);
extern void ge_original_host_reset_resource_handles_for_test(void);
extern u32 ge_original_host_virtual_to_physical(void *value);

static void input_for_tick(GEOriginalFrontendInputV6 *input, uint64_t tick,
                           uint32_t buttons)
{
    /* This smoke advances one 60 Hz source anchor per call. The product's
     * 120 Hz owner must pass outerNativeTick >> 1 at even anchors only. */
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
    input->native_tick = tick;
    input->sequence = tick;
}

static const GEOriginalFrontendEventV6 *find_event(
    const GEOriginalFrontendEventV6 *events, uint32_t count,
    uint32_t kind, uint32_t operation, uint32_t target)
{
    uint32_t index;

    for (index = 0u; index < count; index++) {
        if (events[index].kind == kind &&
            events[index].operation == operation &&
            (target == UINT32_MAX || events[index].target_screen == target)) {
            return &events[index];
        }
    }
    return NULL;
}

static uint32_t step_until_screen(
    GEOriginalFrontendStateV6 *state,
    uint32_t target,
    uint64_t *tick,
    uint32_t *saw_render,
    uint32_t *saw_audio,
    uint32_t *saw_model,
    uint32_t *saw_gap,
    uint32_t *classic_dialect_flags,
    uint32_t *transition_source_timer,
    uint32_t *transition_source_counter,
    GEOriginalFrontendEventV6 *last_events,
    uint32_t *last_count,
    GEOriginalFrontendFrameV6 *last_frame)
{
    GEOriginalFrontendInputV6 input;
    GEOriginalFrontendEventV6 events[128];
    uint32_t count;
    uint32_t index;
    const GEOriginalFrontendEventV6 *transition;

    while (state->screen != target) {
        assert(*tick < 2200u);
        (*tick)++;
        input_for_tick(&input, *tick, GE_ORIGINAL_FRONTEND_V6_BUTTON_NONE);
        assert(ge_original_frontend_v6_step(
                   state, &input, events, 128u, &count, last_frame) ==
               GE_STATUS_OK);
        assert(ge_original_frontend_v6_validate_frame(last_frame) ==
               GE_STATUS_OK);
        assert(ge_original_host_render_resource_word_safety() != 0u);
        *classic_dialect_flags |= ge_original_host_render_dialect_flags();
        transition = find_event(
            events, count, GE_ORIGINAL_FRONTEND_V6_EVENT_SCREEN,
            GE_ORIGINAL_FRONTEND_V6_OP_TRANSITION_REQUEST, UINT32_MAX);
        if (transition != NULL) {
            *transition_source_timer = transition->source_timer;
            *transition_source_counter = transition->source_counter;
        }
        for (index = 0u; index < count; index++) {
            assert(ge_original_frontend_v6_validate_event(&events[index]) ==
                   GE_STATUS_OK);
            if (events[index].kind == GE_ORIGINAL_FRONTEND_V6_EVENT_RENDER) {
                *saw_render = 1u;
            } else if (events[index].kind == GE_ORIGINAL_FRONTEND_V6_EVENT_AUDIO) {
                *saw_audio = 1u;
            } else if (events[index].kind == GE_ORIGINAL_FRONTEND_V6_EVENT_MODEL) {
                *saw_model = 1u;
            } else if (events[index].kind == GE_ORIGINAL_FRONTEND_V6_EVENT_SOURCE_GAP) {
                *saw_gap = 1u;
            }
        }
        memcpy(last_events, events, count * sizeof(*events));
        *last_count = count;
    }
    return state->screen;
}

int main(void)
{
    GEOriginalFrontendStateV6 state;
    GEOriginalFrontendInputV6 input;
    GEOriginalFrontendEventV6 events[128];
    GEOriginalFrontendEventV6 last_events[128];
    GEOriginalFrontendFrameV6 frame;
    uint32_t count;
    uint32_t last_count = 0u;
    uint32_t saw_render = 0u;
    uint32_t saw_audio = 0u;
    uint32_t saw_model = 0u;
    uint32_t saw_gap = 0u;
    uint32_t classic_dialect_flags = 0u;
    uint32_t transition_timer = 0u;
    uint32_t transition_counter = 0u;
    uint64_t tick = 0u;
    uint32_t index;
    uint32_t handle_a;
    uint32_t handle_b;
    uint32_t handle_a_repeat;
    uint32_t handle_b_repeat;
    uint8_t pointer_a = 0u;
    uint8_t pointer_b = 0u;

    assert(ge_original_frontend_v6_init(&state) == GE_STATUS_OK);
    assert(state.screen == GE_ORIGINAL_FRONTEND_V6_SCREEN_LEGAL);
    assert(state.source_timer == 0u);
    assert(state.unsupported_count == 0u);

    /* Resource words use deterministic bounded handles, never host pointer
     * bits.  The same call-time registry must be stable across a reset. */
    ge_original_host_reset_resource_handles_for_test();
    handle_a = ge_original_host_virtual_to_physical(&pointer_a);
    handle_b = ge_original_host_virtual_to_physical(&pointer_b);
    handle_a_repeat = ge_original_host_virtual_to_physical(&pointer_a);
    assert(handle_a != 0u && handle_b != 0u);
    assert(handle_a != handle_b);
    assert((handle_a & UINT32_C(0xff000000)) == UINT32_C(0xd1000000));
    assert((handle_b & UINT32_C(0xff000000)) == UINT32_C(0xd1000000));
    assert(handle_a == handle_a_repeat);
    ge_original_host_reset_resource_handles_for_test();
    handle_a_repeat = ge_original_host_virtual_to_physical(&pointer_a);
    handle_b_repeat = ge_original_host_virtual_to_physical(&pointer_b);
    assert(handle_a == handle_a_repeat);
    assert(handle_b == handle_b_repeat);

    /* The source's first-boot Legal comparator ignores the first input. */
    tick++;
    input_for_tick(&input, tick, GE_ORIGINAL_FRONTEND_V6_BUTTON_ANY);
    assert(ge_original_frontend_v6_step(
               &state, &input, events, 128u, &count, &frame) == GE_STATUS_OK);
    assert(state.screen == GE_ORIGINAL_FRONTEND_V6_SCREEN_LEGAL);
    assert(state.source_timer == 1u);

    step_until_screen(&state, GE_ORIGINAL_FRONTEND_V6_SCREEN_SWITCH, &tick,
                      &saw_render, &saw_audio, &saw_model, &saw_gap,
                      &classic_dialect_flags,
                      &transition_timer, &transition_counter, last_events,
                      &last_count, &frame);
    assert(transition_timer == 241u);
    assert(state.pending_screen == GE_ORIGINAL_FRONTEND_V6_SCREEN_NINTENDO);

    step_until_screen(&state, GE_ORIGINAL_FRONTEND_V6_SCREEN_NINTENDO, &tick,
                      &saw_render, &saw_audio, &saw_model, &saw_gap,
                      &classic_dialect_flags,
                      &transition_timer, &transition_counter, last_events,
                      &last_count, &frame);
    assert(tick == 245u);
    assert(frame.transition_timer == 4u || frame.source_timer == 0u);

    step_until_screen(&state, GE_ORIGINAL_FRONTEND_V6_SCREEN_SWITCH, &tick,
                      &saw_render, &saw_audio, &saw_model, &saw_gap,
                      &classic_dialect_flags,
                      &transition_timer, &transition_counter, last_events,
                      &last_count, &frame);
    assert(transition_timer == 501u);
    assert(state.pending_screen == GE_ORIGINAL_FRONTEND_V6_SCREEN_RAREWARE);

    step_until_screen(&state, GE_ORIGINAL_FRONTEND_V6_SCREEN_RAREWARE, &tick,
                      &saw_render, &saw_audio, &saw_model, &saw_gap,
                      &classic_dialect_flags,
                      &transition_timer, &transition_counter, last_events,
                      &last_count, &frame);
    assert(tick == 750u);
    assert(state.rareware_mode == 0u);

    step_until_screen(&state, GE_ORIGINAL_FRONTEND_V6_SCREEN_SWITCH, &tick,
                      &saw_render, &saw_audio, &saw_model, &saw_gap,
                      &classic_dialect_flags,
                      &transition_timer, &transition_counter, last_events,
                      &last_count, &frame);
    assert(transition_counter == 290u);
    assert(state.pending_screen == GE_ORIGINAL_FRONTEND_V6_SCREEN_GUNBARREL);

    step_until_screen(&state, GE_ORIGINAL_FRONTEND_V6_SCREEN_GUNBARREL, &tick,
                      &saw_render, &saw_audio, &saw_model, &saw_gap,
                      &classic_dialect_flags,
                      &transition_timer, &transition_counter, last_events,
                      &last_count, &frame);
    assert(tick == 1044u);
    assert(state.gunbarrel_mode == 2u);

    step_until_screen(&state, GE_ORIGINAL_FRONTEND_V6_SCREEN_SWITCH, &tick,
                      &saw_render, &saw_audio, &saw_model, &saw_gap,
                      &classic_dialect_flags,
                      &transition_timer, &transition_counter, last_events,
                      &last_count, &frame);
    assert(state.pending_screen == GE_ORIGINAL_FRONTEND_V6_SCREEN_GOLDENEYE);

    step_until_screen(&state, GE_ORIGINAL_FRONTEND_V6_SCREEN_GOLDENEYE, &tick,
                      &saw_render, &saw_audio, &saw_model, &saw_gap,
                      &classic_dialect_flags,
                      &transition_timer, &transition_counter, last_events,
                      &last_count, &frame);
    assert(state.gunbarrel_mode == 9u);
    assert(saw_render != 0u);
    assert((classic_dialect_flags & (1u << 0)) != 0u);
    assert((classic_dialect_flags & (1u << 1)) != 0u);
    assert(saw_audio != 0u);
    assert(saw_model != 0u);
    assert(saw_gap != 0u); /* explicit model/asset sink boundary */
    assert(last_count > 0u);
    for (index = 0u; index < last_count; index++) {
        assert(last_events[index].native_tick == tick);
    }

    memset(&input, 0, sizeof(input));
    input.header.abi_version = GE_NATIVE_ABI_VERSION;
    input.header.struct_size = (uint32_t)sizeof(input);
    input.record_version = GE_ORIGINAL_FRONTEND_V6_RECORD_VERSION;
    input.native_tick = tick + 1u;
    input.sequence = tick + 1u;
    input.reserved0 = 1u;
    assert(ge_original_frontend_v6_validate_input(&input) ==
           GE_STATUS_MALFORMED_STREAM);

    printf("ge_original_frontend_v6_smoke: PASS\n");
    printf("native_tick=%llu render=%u audio=%u model=%u gaps=%u\n",
           (unsigned long long)tick, saw_render, saw_audio, saw_model, saw_gap);
    return 0;
}
