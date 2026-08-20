#include "ge_source_frontend_v6.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

typedef struct FrontendProbe {
    uint32_t screen_events;
    uint32_t enter_events;
    uint32_t exit_events;
    uint32_t transition_events;
    uint32_t model_loads;
    uint32_t model_releases;
    uint32_t model_draws;
    uint32_t rareware_model_draws;
    uint32_t rareware_half_step_draws;
    uint32_t blood_ticks;
    uint32_t text_events;
    uint32_t audio_events;
    uint32_t save_events;
    uint32_t render_events;
    uint32_t diagnostics;
    uint32_t last_diagnostic_code;
    uint32_t last_diagnostic_detail0;
    uint32_t last_diagnostic_detail1;
    uint32_t saw_switch_timer_four;
    uint32_t first_blood_complete;
    uint32_t gunbarrel_timer_events;
    uint32_t gunbarrel_last_timer;
    uint32_t gunbarrel_timer_seen_mask;
    uint32_t gunbarrel_first_timer[6];
    uint32_t gunbarrel_last_timer_by_subphase[6];
    uint32_t gunbarrel_first_low_state[6];
    uint32_t gunbarrel_max_low_state[6];
} FrontendProbe;

static void assert_header(const GEAbiHeaderV1 *header, uint32_t size)
{
    assert(header->abi_version == GE_NATIVE_ABI_VERSION);
    assert(header->struct_size == size);
}

static GEStatusV1 probe_screen(
    const GEFrontendScreenEventV6 *event,
    void *context)
{
    FrontendProbe *probe = (FrontendProbe *)context;

    assert_header(&event->header, (uint32_t)sizeof(*event));
    assert(event->record_version == GE_SOURCE_FRONTEND_V6_RECORD_VERSION);
    assert(event->reserved0 == 0u);
    assert(event->reserved1 == 0u);
    probe->screen_events++;
    if (event->event == GE_SOURCE_FRONTEND_V6_EVENT_SCREEN_ENTER) {
        probe->enter_events++;
    } else if (event->event == GE_SOURCE_FRONTEND_V6_EVENT_SCREEN_EXIT) {
        probe->exit_events++;
    } else if (event->event == GE_SOURCE_FRONTEND_V6_EVENT_TRANSITION) {
        probe->transition_events++;
    }
    return GE_STATUS_OK;
}

static GEStatusV1 probe_model(
    const GEFrontendModelEventV6 *event,
    GEFrontendModelResultV6 *result,
    void *context)
{
    FrontendProbe *probe = (FrontendProbe *)context;

    assert_header(&event->header, (uint32_t)sizeof(*event));
    assert_header(&result->header, (uint32_t)sizeof(*result));
    assert(event->record_version == GE_SOURCE_FRONTEND_V6_RECORD_VERSION);
    assert(result->record_version == GE_SOURCE_FRONTEND_V6_RECORD_VERSION);
    assert(event->reserved0 == 0u);
    assert(event->reserved1 == 0u);
    probe->model_draws += event->operation == GE_SOURCE_FRONTEND_V6_MODEL_OP_DRAW;
    if (event->screen == GE_SOURCE_FRONTEND_V6_SCREEN_GUNBARREL &&
        event->model == GE_SOURCE_FRONTEND_V6_MODEL_GUNBARREL &&
        event->operation == GE_SOURCE_FRONTEND_V6_MODEL_OP_DRAW &&
        event->subphase >= 1u && event->subphase <= 5u) {
        assert((event->flags & GE_SOURCE_FRONTEND_V6_MODEL_FLAG_GUNBARREL_TIMER_VALID) != 0u);
        assert(((event->flags & GE_SOURCE_FRONTEND_V6_MODEL_GUNBARREL_TIMER_MASK) >>
                GE_SOURCE_FRONTEND_V6_MODEL_GUNBARREL_TIMER_SHIFT) <= 0xffffu);
        uint32_t timer =
            (event->flags & GE_SOURCE_FRONTEND_V6_MODEL_GUNBARREL_TIMER_MASK) >>
            GE_SOURCE_FRONTEND_V6_MODEL_GUNBARREL_TIMER_SHIFT;
        uint32_t low_state = event->flags & UINT32_C(0xff);
        assert(event->subphase >= 1u && event->subphase <= 5u);
        if ((probe->gunbarrel_timer_seen_mask & (UINT32_C(1) << event->subphase)) == 0u) {
            probe->gunbarrel_first_timer[event->subphase] = timer;
            probe->gunbarrel_first_low_state[event->subphase] = low_state;
            probe->gunbarrel_timer_seen_mask |= UINT32_C(1) << event->subphase;
        }
        probe->gunbarrel_last_timer_by_subphase[event->subphase] = timer;
        if (low_state > probe->gunbarrel_max_low_state[event->subphase]) {
            probe->gunbarrel_max_low_state[event->subphase] = low_state;
        }
        probe->gunbarrel_last_timer = timer;
        probe->gunbarrel_timer_events++;
    }
    if (event->screen == GE_SOURCE_FRONTEND_V6_SCREEN_RAREWARE &&
        event->operation == GE_SOURCE_FRONTEND_V6_MODEL_OP_DRAW) {
        assert(event->model == GE_SOURCE_FRONTEND_V6_MODEL_RAREWARELOGO);
        assert(event->subphase <= GE_SOURCE_FRONTEND_V6_RAREWARE_MODE_READY);
        probe->rareware_model_draws++;
        if ((event->native_tick & 1u) != 0u) {
            assert((event->flags & GE_SOURCE_FRONTEND_V6_MODEL_FLAG_HALF_STEP) != 0u);
            probe->rareware_half_step_draws++;
        } else {
            assert((event->flags & GE_SOURCE_FRONTEND_V6_MODEL_FLAG_HALF_STEP) == 0u);
        }
    }
    probe->model_loads += event->operation == GE_SOURCE_FRONTEND_V6_MODEL_OP_LOAD;
    probe->model_releases += event->operation == GE_SOURCE_FRONTEND_V6_MODEL_OP_RELEASE;
    if (event->operation == GE_SOURCE_FRONTEND_V6_MODEL_OP_BLOOD_TICK) {
        probe->blood_ticks++;
        if (probe->first_blood_complete == 0u) {
            result->flags = GE_SOURCE_FRONTEND_V6_MODEL_RESULT_BLOOD_COMPLETE |
                GE_SOURCE_FRONTEND_V6_MODEL_RESULT_EXECUTED;
            probe->first_blood_complete = 1u;
        }
    } else {
        result->flags = GE_SOURCE_FRONTEND_V6_MODEL_RESULT_EXECUTED;
    }
    return GE_STATUS_OK;
}

static GEStatusV1 probe_text(
    const GEFrontendTextEventV6 *event,
    void *context)
{
    FrontendProbe *probe = (FrontendProbe *)context;

    assert_header(&event->header, (uint32_t)sizeof(*event));
    assert(event->record_version == GE_SOURCE_FRONTEND_V6_RECORD_VERSION);
    assert(event->reserved0 == 0u);
    assert(event->reserved1 == 0u);
    probe->text_events++;
    return GE_STATUS_OK;
}

static GEStatusV1 probe_audio(
    const GEFrontendAudioEventV6 *event,
    void *context)
{
    FrontendProbe *probe = (FrontendProbe *)context;

    assert_header(&event->header, (uint32_t)sizeof(*event));
    assert(event->record_version == GE_SOURCE_FRONTEND_V6_RECORD_VERSION);
    assert(event->reserved0 == 0u);
    assert(event->reserved1 == 0u);
    probe->audio_events++;
    return GE_STATUS_OK;
}

static GEStatusV1 probe_save(
    const GEFrontendSaveEventV6 *event,
    void *context)
{
    FrontendProbe *probe = (FrontendProbe *)context;

    assert_header(&event->header, (uint32_t)sizeof(*event));
    assert(event->record_version == GE_SOURCE_FRONTEND_V6_RECORD_VERSION);
    assert(event->reserved0 == 0u);
    assert(event->reserved1 == 0u);
    probe->save_events++;
    return GE_STATUS_OK;
}

static GEStatusV1 probe_render(
    const GEFrontendRenderEventV6 *event,
    void *context)
{
    FrontendProbe *probe = (FrontendProbe *)context;

    assert_header(&event->header, (uint32_t)sizeof(*event));
    assert(event->record_version == GE_SOURCE_FRONTEND_V6_RECORD_VERSION);
    assert(event->reserved0 == 0u);
    assert(event->reserved1 == 0u);
    probe->render_events++;
    if (event->screen == GE_SOURCE_FRONTEND_V6_SCREEN_SWITCH &&
        event->source_timer == GE_SOURCE_FRONTEND_V6_SWITCH_TIMER_MAX) {
        probe->saw_switch_timer_four = 1u;
    }
    return GE_STATUS_OK;
}

static GEStatusV1 probe_diagnostic(
    const GEFrontendDiagnosticV6 *event,
    void *context)
{
    FrontendProbe *probe = (FrontendProbe *)context;

    assert_header(&event->header, (uint32_t)sizeof(*event));
    assert(event->record_version == GE_SOURCE_FRONTEND_V6_RECORD_VERSION);
    assert(event->reserved0 == 0u);
    assert(event->reserved1 == 0u);
    probe->diagnostics++;
    probe->last_diagnostic_code = event->code;
    probe->last_diagnostic_detail0 = event->detail0;
    probe->last_diagnostic_detail1 = event->detail1;
    return GE_STATUS_OK;
}

static GEFrontendCallbacksV6 callbacks_for(FrontendProbe *probe)
{
    GEFrontendCallbacksV6 callbacks;

    memset(&callbacks, 0, sizeof(callbacks));
    callbacks.model = probe_model;
    callbacks.screen = probe_screen;
    callbacks.text = probe_text;
    callbacks.audio = probe_audio;
    callbacks.save = probe_save;
    callbacks.render = probe_render;
    callbacks.diagnostic = probe_diagnostic;
    callbacks.context = probe;
    return callbacks;
}

static void step_once(
    GEFrontendStateV6 *state,
    const GEFrontendCallbacksV6 *callbacks,
    uint32_t buttons,
    uint32_t controller_count,
    GEFrontendSnapshotV6 *snapshot)
{
    GEFrontendInputV6 input;

    memset(&input, 0, sizeof(input));
    input.header.abi_version = GE_NATIVE_ABI_VERSION;
    input.header.struct_size = (uint32_t)sizeof(input);
    input.record_version = GE_SOURCE_FRONTEND_V6_RECORD_VERSION;
    input.flags = ((state->native_tick + 1u) & 1u) == 0u ?
        GE_SOURCE_FRONTEND_V6_INPUT_FLAG_SOURCE_ANCHOR : 0u;
    input.buttons_pressed = buttons;
    input.controller_count = controller_count;
    input.native_tick = state->native_tick + 1u;
    input.sequence = input.native_tick;
    assert(ge_frontend_v6_validate_input(&input) == GE_STATUS_OK);
    assert(ge_frontend_v6_step_native(state, &input, callbacks, snapshot) == GE_STATUS_OK);
    assert(ge_frontend_v6_validate_snapshot(snapshot) == GE_STATUS_OK);
}

static void run_until_screen(
    GEFrontendStateV6 *state,
    const GEFrontendCallbacksV6 *callbacks,
    uint32_t target,
    uint32_t controller_count,
    GEFrontendSnapshotV6 *snapshot,
    uint64_t max_native_ticks)
{
    uint64_t start = state->native_tick;

    while (state->screen != target) {
        assert(state->native_tick - start < max_native_ticks);
        step_once(state, callbacks, GE_SOURCE_FRONTEND_V6_BUTTON_NONE,
                  controller_count, snapshot);
    }
}

int main(void)
{
    FrontendProbe probe;
    GEFrontendCallbacksV6 callbacks;
    GEFrontendStateV6 state;
    GEFrontendSnapshotV6 snapshot;
    GEFrontendInputV6 malformed;
    GEFrontendCallbacksV6 no_callbacks;
    GEFrontendStateV6 diagnostic_state;
    uint64_t tick_before_nintendo;
    uint64_t tick_before_rareware;

    memset(&probe, 0, sizeof(probe));
    callbacks = callbacks_for(&probe);
    assert(ge_frontend_v6_init(&state, &callbacks) == GE_STATUS_OK);
    assert(state.screen == GE_SOURCE_FRONTEND_V6_SCREEN_LEGAL);
    assert(state.source_timer == 0u);
    assert(probe.enter_events == 1u);
    assert(probe.text_events == 0u);

    /* First-boot Legal ignores input until update_menu00 clears the flag. */
    step_once(&state, &callbacks, GE_SOURCE_FRONTEND_V6_BUTTON_ANY, 1u, &snapshot);
    assert(state.screen == GE_SOURCE_FRONTEND_V6_SCREEN_LEGAL);
    assert(state.source_timer == 0u);

    /* g_MenuTimer >=241 is inclusive; the reload begins on the next menu_init. */
    while (state.source_timer < GE_SOURCE_FRONTEND_V6_LEGAL_TIMER_MAX) {
        step_once(&state, &callbacks, GE_SOURCE_FRONTEND_V6_BUTTON_NONE, 1u, &snapshot);
    }
    assert(state.screen == GE_SOURCE_FRONTEND_V6_SCREEN_LEGAL);
    assert(state.pending_reload == GE_SOURCE_FRONTEND_V6_SCREEN_NINTENDO);
    tick_before_nintendo = state.native_tick;

    /* Four source frames of black switch screen, then Nintendo enters. */
    run_until_screen(&state, &callbacks, GE_SOURCE_FRONTEND_V6_SCREEN_NINTENDO,
                     1u, &snapshot, 32u);
    assert(state.native_tick - tick_before_nintendo == 9u);
    assert(probe.saw_switch_timer_four != 0u);
    assert((state.flags & GE_SOURCE_FRONTEND_V6_STATE_FLAG_FIRST_BOOT) == 0u);

    while (state.source_timer < GE_SOURCE_FRONTEND_V6_NINTENDO_TIMER_MAX) {
        step_once(&state, &callbacks, GE_SOURCE_FRONTEND_V6_BUTTON_NONE, 1u, &snapshot);
    }
    assert(state.pending_reload == GE_SOURCE_FRONTEND_V6_SCREEN_RAREWARE);
    tick_before_rareware = state.native_tick;
    run_until_screen(&state, &callbacks, GE_SOURCE_FRONTEND_V6_SCREEN_RAREWARE,
                     1u, &snapshot, 32u);
    assert(state.native_tick - tick_before_rareware == 9u);
    assert(state.rareware_mode == GE_SOURCE_FRONTEND_V6_RAREWARE_MODE_INIT);
    assert(state.rareware_counter == 0u);

    /* Rareware's postincrement threshold is checked by render, then routed one
     * interface frame later.  The facade must not consume it at 120 Hz twice. */
    while (state.rareware_mode != GE_SOURCE_FRONTEND_V6_RAREWARE_MODE_READY) {
        step_once(&state, &callbacks, GE_SOURCE_FRONTEND_V6_BUTTON_NONE, 1u, &snapshot);
    }
    assert(state.rareware_counter == 0u);
    run_until_screen(&state, &callbacks, GE_SOURCE_FRONTEND_V6_SCREEN_GUNBARREL,
                     1u, &snapshot, 640u);
    assert(state.gunbarrel_mode == GE_SOURCE_FRONTEND_V6_GUNBARREL_MODE_INIT);
    assert(probe.rareware_model_draws > 0u);
    assert(probe.rareware_half_step_draws > 0u);

    /* The model callback completes blood at the first source blood tick; the
     * remaining mode comparators are then exercised before GoldenEye routing. */
    run_until_screen(&state, &callbacks, GE_SOURCE_FRONTEND_V6_SCREEN_GOLDENEYE,
                     1u, &snapshot, 3000u);
    assert(state.screen == GE_SOURCE_FRONTEND_V6_SCREEN_GOLDENEYE);
    assert((state.flags & GE_SOURCE_FRONTEND_V6_STATE_FLAG_FIRST_MAIN_MENU) != 0u);
    assert(probe.blood_ticks >= 1u);
    assert(probe.model_loads >= 5u);
    assert(probe.model_releases >= 3u);
    assert(probe.gunbarrel_timer_events > 0u);
    assert(probe.gunbarrel_last_timer >= GE_SOURCE_FRONTEND_V6_GUNBARREL_FIRE_SHOT);
    assert((probe.gunbarrel_timer_seen_mask & UINT32_C(0x3e)) == UINT32_C(0x3e));
    assert(probe.gunbarrel_first_timer[1] <= probe.gunbarrel_last_timer_by_subphase[1]);
    assert(probe.gunbarrel_first_timer[2] > probe.gunbarrel_last_timer_by_subphase[1]);
    assert(probe.gunbarrel_first_timer[3] > probe.gunbarrel_last_timer_by_subphase[2]);
    assert(probe.gunbarrel_first_timer[4] > probe.gunbarrel_last_timer_by_subphase[3]);
    assert(probe.gunbarrel_first_timer[5] > probe.gunbarrel_last_timer_by_subphase[4]);
    assert(probe.gunbarrel_first_low_state[2] == 0u);
    assert(probe.gunbarrel_first_low_state[3] == 0u);
    assert(probe.gunbarrel_max_low_state[3] == 1u);
    assert(probe.text_events >= 12u);
    assert(probe.audio_events >= 4u);
    assert(probe.save_events >= 1u);
    assert(probe.render_events > 0u);
    if (probe.diagnostics != 0u) {
        fprintf(stderr, "unexpected diagnostics: %u code=%u detail=%u/%u\n",
                probe.diagnostics, probe.last_diagnostic_code,
                probe.last_diagnostic_detail0, probe.last_diagnostic_detail1);
    }
    assert(probe.diagnostics == 0u);

    malformed = (GEFrontendInputV6){0};
    malformed.header.abi_version = GE_NATIVE_ABI_VERSION;
    malformed.header.struct_size = (uint32_t)sizeof(malformed);
    malformed.record_version = GE_SOURCE_FRONTEND_V6_RECORD_VERSION;
    malformed.native_tick = 1u;
    malformed.flags = UINT32_C(0x80000000);
    assert(ge_frontend_v6_validate_input(&malformed) == GE_STATUS_MALFORMED_STREAM);

    /* The production host must see explicit gaps instead of a fake screen
     * when source model/text/render adapters have not been installed. */
    memset(&no_callbacks, 0, sizeof(no_callbacks));
    assert(ge_frontend_v6_init(&diagnostic_state, &no_callbacks) == GE_STATUS_OK);
    step_once(&diagnostic_state, &no_callbacks, GE_SOURCE_FRONTEND_V6_BUTTON_NONE,
              1u, &snapshot);
    assert(diagnostic_state.unsupported_count > 0u);
    assert((diagnostic_state.flags & GE_SOURCE_FRONTEND_V6_STATE_FLAG_UNSUPPORTED) != 0u);

    printf("ge_source_frontend_v6_smoke: PASS\n");
    printf("native_ticks=%llu screens=%u transitions=%u blood=%u rareware_draws=%u rareware_half_steps=%u diagnostics=%u\n",
           (unsigned long long)state.native_tick,
           probe.screen_events,
           probe.transition_events,
           probe.blood_ticks,
           probe.rareware_model_draws,
           probe.rareware_half_step_draws,
           probe.diagnostics);
    return 0;
}
