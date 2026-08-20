#define GE_ORIGINAL_UNIT_PREFIX ge_adapter_
#include "ge_original_host_compat.h"
#include "ge_original_frontend_v6.h"

#include <front.h>
#include <model.h>
#include <music.h>
#include <title.h>

#include <stddef.h>
#include <string.h>

/* These globals are call-time host inputs consumed by the platform stubs. */
uint32_t ge_original_host_buttons_pressed;
uint32_t ge_original_host_controller_count;
uint32_t ge_original_host_source_tick;

typedef struct GEOriginalCallContextV6 {
    GEOriginalFrontendStateV6 *state;
    GEOriginalFrontendEventV6 *events;
    uint32_t capacity;
    uint32_t count;
    uint64_t native_tick;
    uint64_t render_hash;
    uint64_t audio_hash;
} GEOriginalCallContextV6;

static GEOriginalCallContextV6 *s_call_context;

extern void ge_original_host_prepare_fake_assets(void);
extern void ge_original_host_set_current_screen(uint32_t screen);
extern void ge_original_host_record_platform_event(
    uint32_t kind, uint32_t operation, uint32_t value0, uint32_t value1,
    uint64_t semantic_hash);

extern uint32_t ge_original_host_render_words[4096];
extern uint32_t ge_original_host_render_word_count;
extern uint32_t ge_original_host_render_command_count;
extern void ge_original_sanitize_render_words(void);
extern uint64_t ge_original_host_render_command_hash(void);

extern Gfx *ge_original_host_render_buffer(void);

extern s32 g_MenuTimer;
extern s32 g_ClockTimer;
extern s32 is_first_time_on_legal_screen;
extern s32 is_first_time_on_main_menu;
extern s32 prev_keypresses;
extern s32 ge_logo_bool;
extern MENU current_menu;
extern MENU menu_update;
extern MENU maybe_prev_menu;

extern u8 gunbarrel_mode;
extern s32 intro_eye_counter;
extern f32 g_TitleX;
extern f32 g_TitleY;
extern f32 titleTransitionX;
extern f32 titleTransitionY;
extern s16 word_CODE_bss_80069584;
extern s32 gunbarrelTimer;
extern Gfx *constructor_menu03_eye(Gfx *gdl);

extern void update_menu00_legalscreen(void);
extern void update_menu01_nintendo(void);
extern void update_menu02_rareware(void);
extern void update_menu_03_gunbarrel(void);
extern void update_menu04_goldeneye(void);
extern void update_menu18_displaycast(void);
extern void init_menu00_legalscreen(void);
extern void init_menu01_nintendo(void);
extern void init_menu02_rarelogo(void);
extern void init_menu05_fileselect(void);
extern void init_menu06_modeselect(void);
extern void init_menu18_displaycast(void);
extern void init_menu04_goldeneyelogo(void);
extern void interface_menu00_legalscreen(void);
extern void interface_menu01_nintendo(void);
extern void interface_menu02_rareware(void);
extern void interface_menu03_eye(void);
extern void interface_menu04_goldeneyelogo(void);
extern s32 interface_menu05_fileselect(void);
extern void interface_menu06_modesel(void);
extern void interface_menu17_switchscreens(void);
extern void interface_menu18_displaycast(void);
extern Gfx *constructor_menu17_switchscreens(Gfx *gdl);
extern Gfx *constructor_menu01_nintendo(Gfx *gdl);
extern Gfx *constructor_menu02_rareware(Gfx *gdl);
extern Gfx *constructor_menu04_goldeneyelogo(Gfx *gdl);
extern Gfx *constructor_menu05_fileselect(Gfx *gdl);
extern Gfx *constructor_menu06_modesel(Gfx *gdl);
extern Gfx *constructor_menu18_displaycast(Gfx *gdl);

static uint64_t ge_original_hash_mix(uint64_t hash, uint64_t value)
{
    uint32_t index;

    for (index = 0u; index < 8u; index++) {
        hash ^= (value >> (index * 8u)) & UINT64_C(0xff);
        hash *= UINT64_C(1099511628211);
    }
    return hash;
}

static uint64_t ge_original_hash_state(
    const GEOriginalFrontendStateV6 *state)
{
    uint64_t hash = UINT64_C(1469598103934665603);

    hash = ge_original_hash_mix(hash, state->screen);
    hash = ge_original_hash_mix(hash, state->pending_screen);
    hash = ge_original_hash_mix(hash, state->source_timer);
    hash = ge_original_hash_mix(hash, state->transition_timer);
    hash = ge_original_hash_mix(hash, state->rareware_mode);
    hash = ge_original_hash_mix(hash, state->rareware_counter);
    hash = ge_original_hash_mix(hash, state->gunbarrel_mode);
    hash = ge_original_hash_mix(hash, state->gunbarrel_counter);
    hash = ge_original_hash_mix(hash, state->flags);
    hash = ge_original_hash_mix(hash, state->native_tick);
    hash = ge_original_hash_mix(hash, state->source_frame);
    return hash;
}

static void ge_original_header(GEAbiHeaderV1 *header, uint32_t size)
{
    header->abi_version = GE_NATIVE_ABI_VERSION;
    header->struct_size = size;
}

static uint32_t ge_original_screen_from_menu(MENU menu)
{
    switch (menu) {
    case MENU_LEGAL_SCREEN: return GE_ORIGINAL_FRONTEND_V6_SCREEN_LEGAL;
    case MENU_NINTENDO_LOGO: return GE_ORIGINAL_FRONTEND_V6_SCREEN_NINTENDO;
    case MENU_RAREWARE_LOGO: return GE_ORIGINAL_FRONTEND_V6_SCREEN_RAREWARE;
    case MENU_EYE_INTRO: return GE_ORIGINAL_FRONTEND_V6_SCREEN_GUNBARREL;
    case MENU_GOLDENEYE_LOGO: return GE_ORIGINAL_FRONTEND_V6_SCREEN_GOLDENEYE;
    case MENU_FILE_SELECT: return GE_ORIGINAL_FRONTEND_V6_SCREEN_FILE_SELECT;
    case MENU_MODE_SELECT: return GE_ORIGINAL_FRONTEND_V6_SCREEN_MODE_SELECT;
    case MENU_SWITCH_SCREENS: return GE_ORIGINAL_FRONTEND_V6_SCREEN_SWITCH;
    case MENU_DISPLAY_CAST: return GE_ORIGINAL_FRONTEND_V6_SCREEN_CAST;
    default: return UINT32_MAX;
    }
}

static MENU ge_original_menu_from_screen(uint32_t screen)
{
    switch (screen) {
    case GE_ORIGINAL_FRONTEND_V6_SCREEN_LEGAL: return MENU_LEGAL_SCREEN;
    case GE_ORIGINAL_FRONTEND_V6_SCREEN_NINTENDO: return MENU_NINTENDO_LOGO;
    case GE_ORIGINAL_FRONTEND_V6_SCREEN_RAREWARE: return MENU_RAREWARE_LOGO;
    case GE_ORIGINAL_FRONTEND_V6_SCREEN_GUNBARREL: return MENU_EYE_INTRO;
    case GE_ORIGINAL_FRONTEND_V6_SCREEN_GOLDENEYE: return MENU_GOLDENEYE_LOGO;
    case GE_ORIGINAL_FRONTEND_V6_SCREEN_FILE_SELECT: return MENU_FILE_SELECT;
    case GE_ORIGINAL_FRONTEND_V6_SCREEN_MODE_SELECT: return MENU_MODE_SELECT;
    case GE_ORIGINAL_FRONTEND_V6_SCREEN_SWITCH: return MENU_SWITCH_SCREENS;
    case GE_ORIGINAL_FRONTEND_V6_SCREEN_CAST: return MENU_DISPLAY_CAST;
    default: return MENU_INVALID;
    }
}

static uint32_t ge_original_source_counter(void)
{
    if (current_menu == MENU_RAREWARE_LOGO) {
        return (uint32_t)intro_eye_counter;
    }
    if (current_menu == MENU_EYE_INTRO) {
        return (uint32_t)intro_eye_counter;
    }
    return 0u;
}

static GEStatusV1 ge_original_emit(
    GEOriginalCallContextV6 *context,
    uint32_t kind,
    uint32_t operation,
    uint32_t screen,
    uint32_t target,
    uint32_t value0,
    uint32_t value1,
    uint64_t semantic_hash)
{
    GEOriginalFrontendEventV6 *event;

    if (context == NULL) {
        return GE_STATUS_OK;
    }
    if (context->count >= context->capacity || context->events == NULL) {
        if (context->state != NULL) {
            context->state->unsupported_count++;
        }
        return GE_STATUS_INTERNAL_ERROR;
    }

    event = &context->events[context->count++];
    memset(event, 0, sizeof(*event));
    ge_original_header(&event->header, (uint32_t)sizeof(*event));
    event->record_version = GE_ORIGINAL_FRONTEND_V6_RECORD_VERSION;
    event->kind = kind;
    event->operation = operation;
    event->screen = screen;
    event->target_screen = target;
    event->source_timer = (uint32_t)g_MenuTimer;
    event->source_counter = ge_original_source_counter();
    event->native_tick = context->native_tick;
    event->source_frame = context->state == NULL ? 0u : context->state->source_frame;
    event->semantic_hash = semantic_hash;
    event->value0 = value0;
    event->value1 = value1;
    event->reserved0 = 0u;
    event->reserved1 = 0u;
    return GE_STATUS_OK;
}

void ge_original_host_record_platform_event(
    uint32_t kind, uint32_t operation, uint32_t value0, uint32_t value1,
    uint64_t semantic_hash)
{
    uint32_t screen = current_menu < MENU_MAX ?
        ge_original_screen_from_menu(current_menu) : UINT32_MAX;

    (void)ge_original_emit(
        s_call_context, kind, operation, screen, UINT32_MAX, value0, value1,
        semantic_hash);
    if (s_call_context != NULL) {
        if (kind == GE_ORIGINAL_FRONTEND_V6_EVENT_RENDER) {
            s_call_context->render_hash = ge_original_hash_mix(
                s_call_context->render_hash, semantic_hash);
        } else if (kind == GE_ORIGINAL_FRONTEND_V6_EVENT_AUDIO) {
            s_call_context->audio_hash = ge_original_hash_mix(
                s_call_context->audio_hash, semantic_hash);
        }
    }
}

static GEStatusV1 ge_original_validate_header(
    const GEAbiHeaderV1 *header, uint32_t size, uint32_t version)
{
    if (header == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (header->abi_version != GE_NATIVE_ABI_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    if (header->struct_size != size) {
        return GE_STATUS_INVALID_SIZE;
    }
    if (version != GE_ORIGINAL_FRONTEND_V6_RECORD_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_original_frontend_v6_validate_input(
    const GEOriginalFrontendInputV6 *input)
{
    GEStatusV1 status;

    if (input == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_original_validate_header(
        &input->header, (uint32_t)sizeof(*input), input->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if ((input->flags & ~(GE_ORIGINAL_FRONTEND_V6_INPUT_CAPTURE_RENDER |
                          GE_ORIGINAL_FRONTEND_V6_INPUT_CONNECTED |
                          GE_ORIGINAL_FRONTEND_V6_INPUT_SYNTHETIC)) != 0u ||
        input->buttons_pressed > GE_ORIGINAL_FRONTEND_V6_BUTTON_ANY ||
        input->controller_count > 4u || input->clock_timer > 4u ||
        input->native_tick == 0u || input->reserved0 != 0u ||
        input->reserved1 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_original_frontend_v6_validate_event(
    const GEOriginalFrontendEventV6 *event)
{
    GEStatusV1 status;

    if (event == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_original_validate_header(
        &event->header, (uint32_t)sizeof(*event), event->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (event->reserved0 != 0u || event->reserved1 != 0u ||
        event->kind < GE_ORIGINAL_FRONTEND_V6_EVENT_SCREEN ||
        event->kind > GE_ORIGINAL_FRONTEND_V6_EVENT_SOURCE_GAP) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_original_frontend_v6_validate_state(
    const GEOriginalFrontendStateV6 *state)
{
    GEStatusV1 status;

    if (state == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_original_validate_header(
        &state->header, (uint32_t)sizeof(*state), state->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (state->reserved0 != 0u || state->reserved1 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_original_frontend_v6_validate_frame(
    const GEOriginalFrontendFrameV6 *frame)
{
    GEStatusV1 status;

    if (frame == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_original_validate_header(
        &frame->header, (uint32_t)sizeof(*frame), frame->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (frame->reserved0 != 0u || frame->reserved1 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

static void ge_original_sync_state(GEOriginalFrontendStateV6 *state)
{
    state->screen = ge_original_screen_from_menu(current_menu);
    state->pending_screen = ge_original_screen_from_menu(menu_update);
    state->source_timer = (uint32_t)g_MenuTimer;
    state->transition_timer = current_menu == MENU_SWITCH_SCREENS ?
        (uint32_t)g_MenuTimer : 0u;
    state->rareware_mode = (uint32_t)gunbarrel_mode;
    state->rareware_counter = current_menu == MENU_RAREWARE_LOGO ?
        (uint32_t)intro_eye_counter : 0u;
    state->gunbarrel_mode = (uint32_t)gunbarrel_mode;
    state->gunbarrel_counter = current_menu == MENU_EYE_INTRO ?
        (uint32_t)intro_eye_counter : 0u;
    state->flags = (is_first_time_on_legal_screen ? 1u : 0u) |
        (is_first_time_on_main_menu ? 2u : 0u) |
        (prev_keypresses ? 4u : 0u) |
        (ge_logo_bool ? 8u : 0u);
}

static void ge_original_call_update(MENU menu)
{
    switch (menu) {
    case MENU_LEGAL_SCREEN: update_menu00_legalscreen(); break;
    case MENU_NINTENDO_LOGO: update_menu01_nintendo(); break;
    case MENU_RAREWARE_LOGO: update_menu02_rareware(); break;
    case MENU_EYE_INTRO: update_menu_03_gunbarrel(); break;
    case MENU_GOLDENEYE_LOGO: update_menu04_goldeneye(); break;
    case MENU_DISPLAY_CAST: update_menu18_displaycast(); break;
    default: break;
    }
}

static void ge_original_call_init(MENU menu)
{
    switch (menu) {
    case MENU_LEGAL_SCREEN: init_menu00_legalscreen(); break;
    case MENU_NINTENDO_LOGO: init_menu01_nintendo(); break;
    case MENU_RAREWARE_LOGO: init_menu02_rarelogo(); break;
    case MENU_EYE_INTRO:
        /* The render-capture host supplies value-only model/matrix fixtures;
         * retain the source initializer's observable scalar state here while
         * keeping all private model pointers inside the wrapper translation
         * unit. */
        gunbarrel_mode = 2u;
        intro_eye_counter = 0;
        g_TitleX = -30.0f;
        g_TitleY = 482.0f;
        titleTransitionX = -100.0f;
        titleTransitionY = 482.0f;
        word_CODE_bss_80069584 = 0x42;
        gunbarrelTimer = 0;
        musicTrack1Play(M_INTRO);
        break;
    case MENU_GOLDENEYE_LOGO: init_menu04_goldeneyelogo(); break;
    case MENU_FILE_SELECT: init_menu05_fileselect(); break;
    case MENU_MODE_SELECT: init_menu06_modeselect(); break;
    case MENU_DISPLAY_CAST: init_menu18_displaycast(); break;
    default: break;
    }
}

static void ge_original_call_interface(MENU menu)
{
    switch (menu) {
    case MENU_LEGAL_SCREEN: interface_menu00_legalscreen(); break;
    case MENU_NINTENDO_LOGO: interface_menu01_nintendo(); break;
    case MENU_RAREWARE_LOGO: interface_menu02_rareware(); break;
    case MENU_EYE_INTRO: interface_menu03_eye(); break;
    case MENU_GOLDENEYE_LOGO: interface_menu04_goldeneyelogo(); break;
    case MENU_FILE_SELECT: (void)interface_menu05_fileselect(); break;
    case MENU_MODE_SELECT: interface_menu06_modesel(); break;
    case MENU_SWITCH_SCREENS: interface_menu17_switchscreens(); break;
    case MENU_DISPLAY_CAST: interface_menu18_displaycast(); break;
    default: break;
    }
}

GEStatusV1 ge_original_frontend_v6_init(GEOriginalFrontendStateV6 *state)
{
    GEOriginalCallContextV6 context;
    GEOriginalFrontendEventV6 init_events[64];

    if (state == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    memset(state, 0, sizeof(*state));
    ge_original_header(&state->header, (uint32_t)sizeof(*state));
    state->record_version = GE_ORIGINAL_FRONTEND_V6_RECORD_VERSION;

    ge_original_host_prepare_fake_assets();
    current_menu = MENU_LEGAL_SCREEN;
    menu_update = MENU_INVALID;
    maybe_prev_menu = MENU_INVALID;
    g_MenuTimer = 0;
    g_ClockTimer = 1;
    is_first_time_on_legal_screen = TRUE;
    is_first_time_on_main_menu = TRUE;
    prev_keypresses = FALSE;
    ge_logo_bool = FALSE;

    memset(&context, 0, sizeof(context));
    context.state = state;
    context.events = init_events;
    context.capacity = 64u;
    context.native_tick = 0u;
    context.render_hash = UINT64_C(1469598103934665603);
    context.audio_hash = UINT64_C(1469598103934665603);
    s_call_context = &context;
    ge_original_host_set_current_screen(
        GE_ORIGINAL_FRONTEND_V6_SCREEN_LEGAL);
    ge_original_call_init(MENU_LEGAL_SCREEN);
    s_call_context = NULL;

    ge_original_sync_state(state);
    state->native_tick = 0u;
    state->source_frame = 0u;
    state->render_hash = context.render_hash;
    state->audio_hash = context.audio_hash;
    state->event_sequence = context.count;
    return ge_original_frontend_v6_validate_state(state);
}

static GEStatusV1 ge_original_finish_step(
    GEOriginalFrontendStateV6 *state,
    GEOriginalCallContextV6 *context,
    GEOriginalFrontendEventV6 *events,
    uint32_t capacity,
    uint32_t *out_count,
    GEOriginalFrontendFrameV6 *out_frame)
{
    GEOriginalFrontendFrameV6 frame;
    uint32_t index;

    if (context->count > capacity || (context->count != 0u && events == NULL)) {
        return GE_STATUS_INTERNAL_ERROR;
    }
    if (out_count != NULL) {
        *out_count = context->count;
    }
    ge_original_sync_state(state);
    state->render_hash = context->render_hash;
    state->audio_hash = context->audio_hash;
    state->event_sequence += context->count;

    memset(&frame, 0, sizeof(frame));
    ge_original_header(&frame.header, (uint32_t)sizeof(frame));
    frame.record_version = GE_ORIGINAL_FRONTEND_V6_RECORD_VERSION;
    frame.screen = state->screen;
    frame.pending_screen = state->pending_screen;
    frame.source_timer = state->source_timer;
    frame.transition_timer = state->transition_timer;
    frame.rareware_mode = state->rareware_mode;
    frame.rareware_counter = state->rareware_counter;
    frame.gunbarrel_mode = state->gunbarrel_mode;
    frame.gunbarrel_counter = state->gunbarrel_counter;
    frame.event_count = context->count;
    frame.flags = state->flags;
    frame.native_tick = state->native_tick;
    frame.source_frame = state->source_frame;
    frame.render_hash = state->render_hash;
    frame.audio_hash = state->audio_hash;
    frame.state_hash = ge_original_hash_state(state);
    if (out_frame != NULL) {
        *out_frame = frame;
    }
    for (index = 0u; index < context->count; index++) {
        if (ge_original_frontend_v6_validate_event(&events[index]) != GE_STATUS_OK) {
            return GE_STATUS_MALFORMED_STREAM;
        }
    }
    return ge_original_frontend_v6_validate_frame(&frame);
}

GEStatusV1 ge_original_frontend_v6_step(
    GEOriginalFrontendStateV6 *state,
    const GEOriginalFrontendInputV6 *input,
    GEOriginalFrontendEventV6 *events,
    uint32_t capacity,
    uint32_t *out_count,
    GEOriginalFrontendFrameV6 *out_frame)
{
    GEOriginalCallContextV6 context;
    MENU before;
    MENU target;

    if (state == NULL || input == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (ge_original_frontend_v6_validate_state(state) != GE_STATUS_OK ||
        ge_original_frontend_v6_validate_input(input) != GE_STATUS_OK ||
        input->native_tick <= state->native_tick) {
        return GE_STATUS_INVALID_STATE;
    }

    memset(&context, 0, sizeof(context));
    context.state = state;
    context.events = events;
    context.capacity = capacity;
    context.native_tick = input->native_tick;
    context.render_hash = state->render_hash == 0u ?
        UINT64_C(1469598103934665603) : state->render_hash;
    context.audio_hash = state->audio_hash == 0u ?
        UINT64_C(1469598103934665603) : state->audio_hash;
    ge_original_host_buttons_pressed = input->buttons_pressed;
    ge_original_host_controller_count = input->controller_count;
    ge_original_host_source_tick = (uint32_t)(input->native_tick >> 1u);
    g_ClockTimer = (s32)(input->clock_timer == 0u ? 1u : input->clock_timer);
    s_call_context = &context;

    current_menu = ge_original_menu_from_screen(state->screen);
    if (current_menu == MENU_INVALID) {
        s_call_context = NULL;
        return GE_STATUS_INVALID_STATE;
    }
    before = current_menu;
    if (current_menu == MENU_SWITCH_SCREENS) {
        ge_original_call_interface(MENU_SWITCH_SCREENS);
        if (maybe_prev_menu > MENU_INVALID) {
            target = maybe_prev_menu;
            maybe_prev_menu = MENU_INVALID;
            menu_update = MENU_INVALID;
            current_menu = target;
            ge_original_emit(&context,
                GE_ORIGINAL_FRONTEND_V6_EVENT_SCREEN,
                GE_ORIGINAL_FRONTEND_V6_OP_SCREEN_ENTER,
                ge_original_screen_from_menu(target), UINT32_MAX, 0u,
                (uint32_t)g_MenuTimer, UINT64_C(0x656e746572));
            ge_original_call_init(target);
            /* The title source's Rareware and gunbarrel interfaces mutate
             * their render-coupled counters on the same anchor that commits
             * the switch.  Nintendo and GoldenEye constructors initialize an
             * exact zero source timer here, so their interface work remains
             * on the following source frame.  This wrapper hook keeps that
             * ordering explicit without editing front.c/title.c. */
            if (target == MENU_RAREWARE_LOGO || target == MENU_EYE_INTRO) {
                ge_original_call_interface(target);
            }
        }
    } else {
        ge_original_call_interface(current_menu);
        if (menu_update > MENU_INVALID) {
            target = menu_update;
            ge_original_emit(&context,
                GE_ORIGINAL_FRONTEND_V6_EVENT_SCREEN,
                GE_ORIGINAL_FRONTEND_V6_OP_TRANSITION_REQUEST,
                ge_original_screen_from_menu(before),
                ge_original_screen_from_menu(target),
                (uint32_t)g_MenuTimer, 0u,
                UINT64_C(0x7472616e736974));
            ge_original_call_update(before);
            current_menu = MENU_SWITCH_SCREENS;
            menu_update = target;
            maybe_prev_menu = MENU_INVALID;
            g_MenuTimer = 0;
            ge_original_emit(&context,
                GE_ORIGINAL_FRONTEND_V6_EVENT_SCREEN,
                GE_ORIGINAL_FRONTEND_V6_OP_SCREEN_EXIT,
                ge_original_screen_from_menu(before),
                GE_ORIGINAL_FRONTEND_V6_SCREEN_SWITCH,
                0u, 0u, UINT64_C(0x65786974));
        }
    }
    state->native_tick = input->native_tick;
    state->source_frame = input->native_tick >> 1u;
    if ((input->flags & GE_ORIGINAL_FRONTEND_V6_INPUT_CAPTURE_RENDER) != 0u) {
        uint32_t render_screen = ge_original_screen_from_menu(current_menu);
        uint32_t render_count = 0u;
        GEOriginalFrontendEventV6 scratch[16];
        GEOriginalFrontendEventV6 *render_events = scratch;
        uint32_t render_capacity = 16u;

        if (context.count >= capacity || events == NULL) {
            s_call_context = NULL;
            return GE_STATUS_INTERNAL_ERROR;
        }
        render_events = events + context.count;
        render_capacity = capacity - context.count;
        if (render_screen == GE_ORIGINAL_FRONTEND_V6_SCREEN_NINTENDO ||
            render_screen == GE_ORIGINAL_FRONTEND_V6_SCREEN_RAREWARE ||
            render_screen == GE_ORIGINAL_FRONTEND_V6_SCREEN_GUNBARREL ||
            render_screen == GE_ORIGINAL_FRONTEND_V6_SCREEN_GOLDENEYE ||
            render_screen == GE_ORIGINAL_FRONTEND_V6_SCREEN_CAST ||
            render_screen == GE_ORIGINAL_FRONTEND_V6_SCREEN_SWITCH ||
            render_screen == GE_ORIGINAL_FRONTEND_V6_SCREEN_FILE_SELECT ||
            render_screen == GE_ORIGINAL_FRONTEND_V6_SCREEN_MODE_SELECT) {
            if (ge_original_frontend_v6_capture_constructor(
                    state, render_screen, input->native_tick, render_events,
                    render_capacity, &render_count) != GE_STATUS_OK) {
                s_call_context = NULL;
                return GE_STATUS_INTERNAL_ERROR;
            }
            context.count += render_count;
            context.render_hash = state->render_hash;
        }
    }

    s_call_context = NULL;
    return ge_original_finish_step(
        state, &context, events, capacity, out_count, out_frame);
}

GEStatusV1 ge_original_frontend_v6_capture_constructor(
    GEOriginalFrontendStateV6 *state,
    uint32_t screen,
    uint64_t native_tick,
    GEOriginalFrontendEventV6 *events,
    uint32_t capacity,
    uint32_t *out_count)
{
    Gfx *begin;
    Gfx *end;
    MENU previous_menu;
    GEOriginalCallContextV6 local;

    if (state == NULL || events == NULL || out_count == NULL ||
        capacity == 0u || native_tick == 0u) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    memset(&local, 0, sizeof(local));
    local.state = state;
    local.events = events;
    local.capacity = capacity;
    local.native_tick = native_tick;
    local.render_hash = UINT64_C(1469598103934665603);
    local.audio_hash = state->audio_hash;
    s_call_context = &local;
    ge_original_emit(&local, GE_ORIGINAL_FRONTEND_V6_EVENT_RENDER,
        GE_ORIGINAL_FRONTEND_V6_OP_RENDER_BEGIN, screen, UINT32_MAX,
        0u, 0u, UINT64_C(0x72656e6465726267));

    previous_menu = current_menu;
    current_menu = ge_original_menu_from_screen(screen);
    ge_original_host_set_current_screen(screen);
    if (screen == GE_ORIGINAL_FRONTEND_V6_SCREEN_SWITCH) {
        begin = ge_original_host_render_buffer();
        end = constructor_menu17_switchscreens(begin);
    } else if (screen == GE_ORIGINAL_FRONTEND_V6_SCREEN_NINTENDO) {
        begin = ge_original_host_render_buffer();
        end = constructor_menu01_nintendo(begin);
    } else if (screen == GE_ORIGINAL_FRONTEND_V6_SCREEN_RAREWARE) {
        begin = ge_original_host_render_buffer();
        end = constructor_menu02_rareware(begin);
    } else if (screen == GE_ORIGINAL_FRONTEND_V6_SCREEN_GUNBARREL) {
        begin = ge_original_host_render_buffer();
        end = constructor_menu03_eye(begin);
    } else if (screen == GE_ORIGINAL_FRONTEND_V6_SCREEN_GOLDENEYE) {
        begin = ge_original_host_render_buffer();
        end = constructor_menu04_goldeneyelogo(begin);
    } else if (screen == GE_ORIGINAL_FRONTEND_V6_SCREEN_CAST) {
        begin = ge_original_host_render_buffer();
        end = constructor_menu18_displaycast(begin);
    } else if (screen == GE_ORIGINAL_FRONTEND_V6_SCREEN_FILE_SELECT) {
        begin = ge_original_host_render_buffer();
        end = constructor_menu05_fileselect(begin);
    } else if (screen == GE_ORIGINAL_FRONTEND_V6_SCREEN_MODE_SELECT) {
        begin = ge_original_host_render_buffer();
        end = constructor_menu06_modesel(begin);
    } else {
        ge_original_emit(&local, GE_ORIGINAL_FRONTEND_V6_EVENT_SOURCE_GAP,
            0x200u, screen, UINT32_MAX, 0u, 0u,
            UINT64_C(0x736f757263656761));
        end = begin = NULL;
    }

    if (begin != NULL && end != NULL) {
        uint32_t words = (uint32_t)(end - begin) * 2u;
        ge_original_host_render_command_count = (uint32_t)(end - begin);
        ge_original_host_render_word_count = words;
        ge_original_sanitize_render_words();
        local.render_hash = ge_original_hash_mix(
            local.render_hash, ge_original_host_render_command_hash());
        ge_original_emit(&local, GE_ORIGINAL_FRONTEND_V6_EVENT_RENDER,
            GE_ORIGINAL_FRONTEND_V6_OP_RENDER_END, screen, UINT32_MAX,
            words, ge_original_host_render_word_count,
            local.render_hash);
    }
    current_menu = previous_menu;
    s_call_context = NULL;
    *out_count = local.count;
    state->render_hash = local.render_hash;
    return local.count <= capacity ? GE_STATUS_OK : GE_STATUS_INTERNAL_ERROR;
}
