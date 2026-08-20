#ifndef GE_SOURCE_FRONTEND_V6_H
#define GE_SOURCE_FRONTEND_V6_H

/*
 * Native frontend authority seam for the source title/menu route.
 *
 * This file is deliberately additive.  It does not replace front.c or title.c
 * yet; it makes the source-owned ordering and timing observable to a native
 * host while model, text, audio, save, and render work is moved behind
 * call-time callbacks.  Records contain only fixed-width values and
 * deterministic semantic identifiers.  Callback tables are transient call
 * interfaces and are never serialized or retained by the state record.
 *
 * Source anchors used by this contract (NTSC/US):
 *   front.c: interface_menu00_legalscreen       g_MenuTimer >= 241
 *   front.c: interface_menu01_nintendo           g_MenuTimer >= 501
 *   front.c: interface_menu04_goldeneyelogo     g_MenuTimer > 180 / > 90
 *   front.c: interface_menu05_fileselect         g_MenuTimer >= 1801
 *   front.c: interface_menu17_switchscreens      g_MenuTimer >= 4
 *   title.c: retrieve_display_rareware_logo      postincrement >=260, >=290
 *   title.c: renderGunbarrelEyeIntroSequence     mode-specific comparators
 *
 * The facade emits a diagnostic when a required source model operation has no
 * implementation.  That is intentional: a missing lowerer must be visible
 * to validation instead of silently becoming a procedural replacement.
 */

#include <stdint.h>

#include "ge_native_foundation.h"

#ifdef __cplusplus
extern "C" {
#endif

#define GE_SOURCE_FRONTEND_V6_CONTRACT_VERSION ((uint32_t)6u)
#define GE_SOURCE_FRONTEND_V6_RECORD_VERSION ((uint32_t)1u)

#define GE_SOURCE_FRONTEND_V6_NATIVE_HZ ((uint32_t)120u)
#define GE_SOURCE_FRONTEND_V6_REFERENCE_HZ ((uint32_t)60u)
#define GE_SOURCE_FRONTEND_V6_PAIR_NUMERATOR ((uint32_t)2u)
#define GE_SOURCE_FRONTEND_V6_PAIR_DENOMINATOR ((uint32_t)1u)

/* Screen values preserve the source MENU enum slots in src/bondconstants.h. */
#define GE_SOURCE_FRONTEND_V6_SCREEN_LEGAL ((uint32_t)0u)
#define GE_SOURCE_FRONTEND_V6_SCREEN_NINTENDO ((uint32_t)1u)
#define GE_SOURCE_FRONTEND_V6_SCREEN_RAREWARE ((uint32_t)2u)
#define GE_SOURCE_FRONTEND_V6_SCREEN_GUNBARREL ((uint32_t)3u)
#define GE_SOURCE_FRONTEND_V6_SCREEN_GOLDENEYE ((uint32_t)4u)
#define GE_SOURCE_FRONTEND_V6_SCREEN_FILE_SELECT ((uint32_t)5u)
#define GE_SOURCE_FRONTEND_V6_SCREEN_MODE_SELECT ((uint32_t)6u)
#define GE_SOURCE_FRONTEND_V6_SCREEN_CAST ((uint32_t)25u)
#define GE_SOURCE_FRONTEND_V6_SCREEN_NO_CONTROLLERS ((uint32_t)23u)
#define GE_SOURCE_FRONTEND_V6_SCREEN_SWITCH ((uint32_t)24u)
#define GE_SOURCE_FRONTEND_V6_SCREEN_MAX ((uint32_t)25u)

#define GE_SOURCE_FRONTEND_V6_SCREEN_INVALID UINT32_MAX

/* Input is the source's pressed-this-frame observation, not held state. */
#define GE_SOURCE_FRONTEND_V6_BUTTON_NONE ((uint32_t)0u)
#define GE_SOURCE_FRONTEND_V6_BUTTON_ANY ((uint32_t)1u << 0)
#define GE_SOURCE_FRONTEND_V6_BUTTON_CONFIRM ((uint32_t)1u << 1)
#define GE_SOURCE_FRONTEND_V6_BUTTON_CANCEL ((uint32_t)1u << 2)
#define GE_SOURCE_FRONTEND_V6_BUTTON_UP ((uint32_t)1u << 3)
#define GE_SOURCE_FRONTEND_V6_BUTTON_DOWN ((uint32_t)1u << 4)
#define GE_SOURCE_FRONTEND_V6_BUTTON_LEFT ((uint32_t)1u << 5)
#define GE_SOURCE_FRONTEND_V6_BUTTON_RIGHT ((uint32_t)1u << 6)
#define GE_SOURCE_FRONTEND_V6_BUTTON_MASK ((uint32_t)0x7fu)

#define GE_SOURCE_FRONTEND_V6_INPUT_FLAG_SOURCE_ANCHOR ((uint32_t)1u << 0)
#define GE_SOURCE_FRONTEND_V6_INPUT_FLAG_FOCUSED ((uint32_t)1u << 1)
#define GE_SOURCE_FRONTEND_V6_INPUT_FLAG_CONTROLLER_CONNECTED ((uint32_t)1u << 2)
#define GE_SOURCE_FRONTEND_V6_INPUT_FLAG_SYNTHETIC ((uint32_t)1u << 3)
#define GE_SOURCE_FRONTEND_V6_INPUT_FLAG_MASK ((uint32_t)0x0fu)

#define GE_SOURCE_FRONTEND_V6_STATE_FLAG_FIRST_BOOT ((uint32_t)1u << 0)
#define GE_SOURCE_FRONTEND_V6_STATE_FLAG_FIRST_MAIN_MENU ((uint32_t)1u << 1)
#define GE_SOURCE_FRONTEND_V6_STATE_FLAG_PREV_KEYPRESS ((uint32_t)1u << 2)
#define GE_SOURCE_FRONTEND_V6_STATE_FLAG_GE_LOGO_BOOL ((uint32_t)1u << 3)
#define GE_SOURCE_FRONTEND_V6_STATE_FLAG_TRANSITION_READY ((uint32_t)1u << 4)
#define GE_SOURCE_FRONTEND_V6_STATE_FLAG_UNSUPPORTED ((uint32_t)1u << 5)
#define GE_SOURCE_FRONTEND_V6_STATE_FLAG_MASK ((uint32_t)0x3fu)

#define GE_SOURCE_FRONTEND_V6_SNAPSHOT_FLAG_SOURCE_ANCHOR ((uint32_t)1u << 8)

#define GE_SOURCE_FRONTEND_V6_EVENT_SCREEN_ENTER ((uint32_t)1u)
#define GE_SOURCE_FRONTEND_V6_EVENT_SCREEN_EXIT ((uint32_t)2u)
#define GE_SOURCE_FRONTEND_V6_EVENT_TRANSITION ((uint32_t)3u)
#define GE_SOURCE_FRONTEND_V6_EVENT_MAX GE_SOURCE_FRONTEND_V6_EVENT_TRANSITION

#define GE_SOURCE_FRONTEND_V6_MODEL_NONE ((uint32_t)0u)
#define GE_SOURCE_FRONTEND_V6_MODEL_LEGALPAGE ((uint32_t)1u)
#define GE_SOURCE_FRONTEND_V6_MODEL_NINTENDOLOGO ((uint32_t)2u)
#define GE_SOURCE_FRONTEND_V6_MODEL_RAREWARELOGO ((uint32_t)3u)
#define GE_SOURCE_FRONTEND_V6_MODEL_GUNBARREL ((uint32_t)4u)
#define GE_SOURCE_FRONTEND_V6_MODEL_GOLDENEYELOGO ((uint32_t)5u)
#define GE_SOURCE_FRONTEND_V6_MODEL_WALLETBOND ((uint32_t)6u)

#define GE_SOURCE_FRONTEND_V6_MODEL_OP_LOAD ((uint32_t)1u)
#define GE_SOURCE_FRONTEND_V6_MODEL_OP_RELEASE ((uint32_t)2u)
#define GE_SOURCE_FRONTEND_V6_MODEL_OP_DRAW ((uint32_t)3u)
#define GE_SOURCE_FRONTEND_V6_MODEL_OP_BLOOD_TICK ((uint32_t)4u)
#define GE_SOURCE_FRONTEND_V6_MODEL_OP_MAX GE_SOURCE_FRONTEND_V6_MODEL_OP_BLOOD_TICK

#define GE_SOURCE_FRONTEND_V6_MODEL_RESULT_NONE ((uint32_t)0u)
#define GE_SOURCE_FRONTEND_V6_MODEL_RESULT_BLOOD_COMPLETE ((uint32_t)1u << 0)
#define GE_SOURCE_FRONTEND_V6_MODEL_RESULT_EXECUTED ((uint32_t)1u << 1)
#define GE_SOURCE_FRONTEND_V6_MODEL_RESULT_MASK ((uint32_t)0x03u)
#define GE_SOURCE_FRONTEND_V6_MODEL_FLAG_HALF_STEP ((uint32_t)1u << 8)
#define GE_SOURCE_FRONTEND_V6_MODEL_FLAG_GUNBARREL_TIMER_VALID ((uint32_t)1u << 9)
#define GE_SOURCE_FRONTEND_V6_MODEL_GUNBARREL_TIMER_SHIFT ((uint32_t)16u)
#define GE_SOURCE_FRONTEND_V6_MODEL_GUNBARREL_TIMER_MASK ((uint32_t)0xffff0000u)

#define GE_SOURCE_FRONTEND_V6_TEXT_LEGAL_TWYCROSS ((uint32_t)7u)
#define GE_SOURCE_FRONTEND_V6_TEXT_LEGAL_CERTIFY ((uint32_t)8u)
#define GE_SOURCE_FRONTEND_V6_TEXT_LEGAL_NINRARE ((uint32_t)9u)
#define GE_SOURCE_FRONTEND_V6_TEXT_LEGAL_DANJAQ ((uint32_t)10u)
#define GE_SOURCE_FRONTEND_V6_TEXT_LEGAL_UAC ((uint32_t)11u)
#define GE_SOURCE_FRONTEND_V6_TEXT_LEGAL_EON ((uint32_t)12u)
#define GE_SOURCE_FRONTEND_V6_TEXT_LEGAL_MACB ((uint32_t)13u)
#define GE_SOURCE_FRONTEND_V6_TEXT_LEGAL_PERSONS ((uint32_t)14u)
#define GE_SOURCE_FRONTEND_V6_TEXT_LEGAL_PRESIDENT ((uint32_t)15u)
#define GE_SOURCE_FRONTEND_V6_TEXT_LEGAL_VICE ((uint32_t)16u)
#define GE_SOURCE_FRONTEND_V6_TEXT_LEGAL_NORMAN ((uint32_t)17u)
#define GE_SOURCE_FRONTEND_V6_TEXT_LEGAL_EMI ((uint32_t)18u)

#define GE_SOURCE_FRONTEND_V6_TEXT_FLAG_SOURCE_FONT ((uint32_t)1u << 0)
#define GE_SOURCE_FRONTEND_V6_TEXT_FLAG_CENTERED ((uint32_t)1u << 1)
#define GE_SOURCE_FRONTEND_V6_TEXT_FLAG_MASK ((uint32_t)0x03u)

/* Source IDs from MUSIC_TRACKS/SFX_ID in src/bondconstants.h. */
#define GE_SOURCE_FRONTEND_V6_AUDIO_MUSIC_STOP ((uint32_t)0u)
#define GE_SOURCE_FRONTEND_V6_AUDIO_INTRO_SWOOSH ((uint32_t)44u)
#define GE_SOURCE_FRONTEND_V6_AUDIO_RAREWARE_SFX ((uint32_t)258u)
#define GE_SOURCE_FRONTEND_V6_AUDIO_INTRO ((uint32_t)2u)
#define GE_SOURCE_FRONTEND_V6_AUDIO_FOLDERS ((uint32_t)23u)
#define GE_SOURCE_FRONTEND_V6_AUDIO_GUN_RIFLE7BIG_1 ((uint32_t)111u)

#define GE_SOURCE_FRONTEND_V6_AUDIO_OP_STOP_MUSIC ((uint32_t)1u)
#define GE_SOURCE_FRONTEND_V6_AUDIO_OP_PLAY_MUSIC ((uint32_t)2u)
#define GE_SOURCE_FRONTEND_V6_AUDIO_OP_PLAY_SFX ((uint32_t)3u)

#define GE_SOURCE_FRONTEND_V6_SAVE_VALIDATE ((uint32_t)1u)
#define GE_SOURCE_FRONTEND_V6_SAVE_LOAD_WALLET ((uint32_t)2u)
#define GE_SOURCE_FRONTEND_V6_SAVE_UPDATE_BOND ((uint32_t)3u)

#define GE_SOURCE_FRONTEND_V6_RENDER_FRAME_BEGIN ((uint32_t)1u)
#define GE_SOURCE_FRONTEND_V6_RENDER_CLEAR_BLACK ((uint32_t)2u)
#define GE_SOURCE_FRONTEND_V6_RENDER_SOURCE_MODEL ((uint32_t)3u)
#define GE_SOURCE_FRONTEND_V6_RENDER_SOURCE_TEXT ((uint32_t)4u)
#define GE_SOURCE_FRONTEND_V6_RENDER_RAREWARE_PIPELINE ((uint32_t)5u)
#define GE_SOURCE_FRONTEND_V6_RENDER_GUNBARREL_PIPELINE ((uint32_t)6u)
#define GE_SOURCE_FRONTEND_V6_RENDER_UNSUPPORTED ((uint32_t)7u)
/*
 * Additive odd-half-step render metadata.  This is deliberately a render
 * request rather than a model draw: it carries the source-derived continuous
 * values which do not fit in the legacy two-value pipeline requests.  It is
 * emitted only on odd native ticks, so the even source-anchor event stream and
 * its hashes remain unchanged.
 */
#define GE_SOURCE_FRONTEND_V6_RENDER_CONTINUOUS_STATE ((uint32_t)8u)
#define GE_SOURCE_FRONTEND_V6_RENDER_CAST_PIPELINE ((uint32_t)9u)

#define GE_SOURCE_FRONTEND_V6_RENDER_FLAG_HALF_STEP ((uint32_t)1u << 8)
#define GE_SOURCE_FRONTEND_V6_RENDER_FLAG_Q16_VALUES ((uint32_t)1u << 9)
#define GE_SOURCE_FRONTEND_V6_RENDER_FLAG_MASK \
    (GE_SOURCE_FRONTEND_V6_RENDER_FLAG_HALF_STEP | \
     GE_SOURCE_FRONTEND_V6_RENDER_FLAG_Q16_VALUES)

/* Continuous-state subphases for RENDER_CONTINUOUS_STATE.  Values are Q16.16
 * unless a future additive flag says otherwise. */
#define GE_SOURCE_FRONTEND_V6_CONTINUOUS_NINTENDO_ROTATION_SCALE ((uint32_t)1u)
#define GE_SOURCE_FRONTEND_V6_CONTINUOUS_NINTENDO_AMBIENT ((uint32_t)2u)
#define GE_SOURCE_FRONTEND_V6_CONTINUOUS_RAREWARE_ROTATION_ALPHA ((uint32_t)3u)
#define GE_SOURCE_FRONTEND_V6_CONTINUOUS_GUNBARREL_TRANSLATION ((uint32_t)4u)
#define GE_SOURCE_FRONTEND_V6_CONTINUOUS_GUNBARREL_COUNTER_WORD ((uint32_t)5u)

#define GE_SOURCE_FRONTEND_V6_DIAG_UNSUPPORTED_MODEL ((uint32_t)1u)
#define GE_SOURCE_FRONTEND_V6_DIAG_UNSUPPORTED_TEXT ((uint32_t)2u)
#define GE_SOURCE_FRONTEND_V6_DIAG_UNSUPPORTED_RENDER ((uint32_t)3u)
#define GE_SOURCE_FRONTEND_V6_DIAG_INVALID_INPUT ((uint32_t)4u)
#define GE_SOURCE_FRONTEND_V6_DIAG_INVALID_STATE ((uint32_t)5u)
#define GE_SOURCE_FRONTEND_V6_DIAG_UNSUPPORTED_AUDIO ((uint32_t)6u)
#define GE_SOURCE_FRONTEND_V6_DIAG_UNSUPPORTED_SAVE ((uint32_t)7u)

#define GE_SOURCE_FRONTEND_V6_DIAG_SEVERITY_INFO ((uint32_t)0u)
#define GE_SOURCE_FRONTEND_V6_DIAG_SEVERITY_WARNING ((uint32_t)1u)
#define GE_SOURCE_FRONTEND_V6_DIAG_SEVERITY_ERROR ((uint32_t)2u)

/* Source comparator constants, retained as named contract facts. */
#define GE_SOURCE_FRONTEND_V6_LEGAL_TIMER_MAX ((uint32_t)241u)
#define GE_SOURCE_FRONTEND_V6_NINTENDO_TIMER_MAX ((uint32_t)501u)
#define GE_SOURCE_FRONTEND_V6_GOLDENEYE_TIMER_1 ((uint32_t)180u)
#define GE_SOURCE_FRONTEND_V6_GOLDENEYE_TIMER_2 ((uint32_t)90u)
#define GE_SOURCE_FRONTEND_V6_FILE_IDLE_TIMER_MAX ((uint32_t)1801u)
#define GE_SOURCE_FRONTEND_V6_SWITCH_TIMER_MAX ((uint32_t)4u)
#define GE_SOURCE_FRONTEND_V6_RAREWARE_EYE_COUNT_1 ((uint32_t)260u)
#define GE_SOURCE_FRONTEND_V6_RAREWARE_EYE_COUNT_2 ((uint32_t)290u)
#define GE_SOURCE_FRONTEND_V6_GUNBARREL_ANIM_START ((uint32_t)137u)
#define GE_SOURCE_FRONTEND_V6_GUNBARREL_SPEEDUP ((uint32_t)212u)
#define GE_SOURCE_FRONTEND_V6_GUNBARREL_FIRE_SHOT ((uint32_t)230u)
#define GE_SOURCE_FRONTEND_V6_GUNBARREL_CASE4_COUNTER ((uint32_t)108u)
#define GE_SOURCE_FRONTEND_V6_GUNBARREL_CASE5_ALPHA ((uint32_t)247u)
#define GE_SOURCE_FRONTEND_V6_GUNBARREL_CASE6_COUNTER ((uint32_t)30u)

#define GE_SOURCE_FRONTEND_V6_RAREWARE_MODE_INIT ((uint32_t)0u)
#define GE_SOURCE_FRONTEND_V6_RAREWARE_MODE_READY ((uint32_t)2u)
#define GE_SOURCE_FRONTEND_V6_GUNBARREL_MODE_INIT ((uint32_t)2u)
#define GE_SOURCE_FRONTEND_V6_GUNBARREL_MODE_GOLDENEYE ((uint32_t)9u)

typedef struct GEFrontendInputV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t flags;
    uint32_t buttons_pressed;
    uint32_t controller_count;
    uint64_t native_tick;
    uint64_t sequence;
    uint32_t reserved0;
    uint32_t reserved1;
} GEFrontendInputV6;

typedef struct GEFrontendScreenEventV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t event;
    uint32_t screen;
    uint32_t target_screen;
    uint64_t native_tick;
    uint32_t source_frame;
    uint32_t source_timer;
    uint32_t transition_timer;
    uint32_t flags;
    uint64_t sequence;
    uint32_t reserved0;
    uint32_t reserved1;
} GEFrontendScreenEventV6;

typedef struct GEFrontendModelEventV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t screen;
    uint32_t model;
    uint32_t operation;
    uint64_t native_tick;
    uint64_t reference_tick;
    uint32_t source_timer;
    uint32_t subphase;
    uint32_t flags;
    uint64_t sequence;
    uint32_t reserved0;
    uint32_t reserved1;
} GEFrontendModelEventV6;

typedef struct GEFrontendModelResultV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t flags;
    uint32_t value0;
    uint32_t value1;
    uint32_t reserved0;
    uint32_t reserved1;
} GEFrontendModelResultV6;

typedef struct GEFrontendTextEventV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t screen;
    uint32_t text_id;
    int32_t x;
    int32_t y;
    uint64_t native_tick;
    uint32_t source_timer;
    uint32_t flags;
    uint64_t sequence;
    uint32_t reserved0;
    uint32_t reserved1;
} GEFrontendTextEventV6;

typedef struct GEFrontendAudioEventV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t screen;
    uint32_t operation;
    uint32_t asset_id;
    uint64_t native_tick;
    uint64_t source_sample;
    uint32_t source_timer;
    uint32_t flags;
    uint64_t sequence;
    uint32_t reserved0;
    uint32_t reserved1;
} GEFrontendAudioEventV6;

typedef struct GEFrontendSaveEventV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t screen;
    uint32_t operation;
    uint32_t folder;
    uint64_t native_tick;
    uint64_t sequence;
    uint32_t reserved0;
    uint32_t reserved1;
} GEFrontendSaveEventV6;

typedef struct GEFrontendRenderEventV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t screen;
    uint32_t operation;
    uint32_t subphase;
    uint64_t native_tick;
    uint64_t reference_tick;
    uint32_t source_timer;
    int32_t value0;
    int32_t value1;
    uint32_t flags;
    uint64_t sequence;
    uint32_t reserved0;
    uint32_t reserved1;
} GEFrontendRenderEventV6;

typedef struct GEFrontendDiagnosticV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t screen;
    uint32_t code;
    uint32_t severity;
    uint32_t source_timer;
    uint64_t native_tick;
    uint64_t sequence;
    uint32_t detail0;
    uint32_t detail1;
    uint32_t reserved0;
    uint32_t reserved1;
} GEFrontendDiagnosticV6;

typedef struct GEFrontendSnapshotV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t flags;
    uint32_t screen;
    uint32_t subphase;
    uint64_t native_tick;
    uint64_t reference_tick;
    uint32_t source_frame;
    uint32_t source_timer;
    uint32_t source_threshold;
    uint32_t transition_timer;
    uint32_t selection;
    uint32_t unsupported_count;
    uint64_t state_hash;
    uint64_t render_hash;
    uint64_t audio_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GEFrontendSnapshotV6;

/* State is host-owned and contains no callback, pointer, path, or SDK value. */
typedef struct GEFrontendStateV6 {
    uint32_t initialized;
    uint32_t screen;
    uint32_t pending_reload;
    uint32_t pending_direct;
    uint32_t transition_timer;
    uint32_t source_timer;
    uint32_t source_frame;
    uint32_t flags;
    uint32_t controller_count;
    uint32_t rareware_mode;
    uint32_t rareware_counter;
    uint32_t gunbarrel_mode;
    uint32_t gunbarrel_counter;
    uint32_t gunbarrel_blood_state;
    uint32_t gunbarrel_word;
    int32_t gunbarrel_title_x_q16;
    int32_t gunbarrel_transition_x_q16;
    uint64_t native_tick;
    uint64_t event_sequence;
    uint32_t unsupported_count;
    uint32_t reserved0;
    uint32_t reserved1;
    uint32_t reserved2;
} GEFrontendStateV6;

typedef GEStatusV1 (*GEFrontendModelCallbackV6)(
    const GEFrontendModelEventV6 *event,
    GEFrontendModelResultV6 *result,
    void *context);
typedef GEStatusV1 (*GEFrontendScreenCallbackV6)(
    const GEFrontendScreenEventV6 *event,
    void *context);
typedef GEStatusV1 (*GEFrontendTextCallbackV6)(
    const GEFrontendTextEventV6 *event,
    void *context);
typedef GEStatusV1 (*GEFrontendAudioCallbackV6)(
    const GEFrontendAudioEventV6 *event,
    void *context);
typedef GEStatusV1 (*GEFrontendSaveCallbackV6)(
    const GEFrontendSaveEventV6 *event,
    void *context);
typedef GEStatusV1 (*GEFrontendRenderCallbackV6)(
    const GEFrontendRenderEventV6 *event,
    void *context);
typedef GEStatusV1 (*GEFrontendDiagnosticCallbackV6)(
    const GEFrontendDiagnosticV6 *event,
    void *context);

/* Transient callback table.  The facade does not retain this table. */
typedef struct GEFrontendCallbacksV6 {
    GEFrontendModelCallbackV6 model;
    GEFrontendScreenCallbackV6 screen;
    GEFrontendTextCallbackV6 text;
    GEFrontendAudioCallbackV6 audio;
    GEFrontendSaveCallbackV6 save;
    GEFrontendRenderCallbackV6 render;
    GEFrontendDiagnosticCallbackV6 diagnostic;
    void *context;
} GEFrontendCallbacksV6;

GEStatusV1 ge_frontend_v6_validate_input(const GEFrontendInputV6 *input);
GEStatusV1 ge_frontend_v6_validate_snapshot(const GEFrontendSnapshotV6 *snapshot);

GEStatusV1 ge_frontend_v6_init(
    GEFrontendStateV6 *state,
    const GEFrontendCallbacksV6 *callbacks);

GEStatusV1 ge_frontend_v6_step_native(
    GEFrontendStateV6 *state,
    const GEFrontendInputV6 *input,
    const GEFrontendCallbacksV6 *callbacks,
    GEFrontendSnapshotV6 *out_snapshot);

/* Source-ordered variant used by the production runtime seam.  When an
 * interface comparator requests a reload on an anchor, front.c enters the
 * switch screen in that same call before rendering.  The legacy entry point
 * above retains its delayed menu_init behavior for its historical smoke and
 * diagnostics; this additive entry point makes the source ordering explicit.
 */
GEStatusV1 ge_frontend_v6_step_native_source_ordered(
    GEFrontendStateV6 *state,
    const GEFrontendInputV6 *input,
    const GEFrontendCallbacksV6 *callbacks,
    GEFrontendSnapshotV6 *out_snapshot);

uint32_t ge_frontend_v6_source_threshold(uint32_t screen, uint32_t subphase);

#if defined(__cplusplus)
#define GE_SOURCE_FRONTEND_V6_STATIC_ASSERT(condition, message) static_assert((condition), message)
#else
#define GE_SOURCE_FRONTEND_V6_STATIC_ASSERT(condition, message) _Static_assert((condition), message)
#endif

GE_SOURCE_FRONTEND_V6_STATIC_ASSERT(sizeof(GEAbiHeaderV1) == 8u,
                                    "GEAbiHeaderV1 layout drift");
GE_SOURCE_FRONTEND_V6_STATIC_ASSERT(sizeof(GEFrontendInputV6) == 48u,
                                    "GEFrontendInputV6 layout drift");
GE_SOURCE_FRONTEND_V6_STATIC_ASSERT(sizeof(GEFrontendScreenEventV6) == 64u,
                                    "GEFrontendScreenEventV6 layout drift");
GE_SOURCE_FRONTEND_V6_STATIC_ASSERT(sizeof(GEFrontendModelEventV6) == 72u,
                                    "GEFrontendModelEventV6 layout drift");
GE_SOURCE_FRONTEND_V6_STATIC_ASSERT(sizeof(GEFrontendModelResultV6) == 32u,
                                    "GEFrontendModelResultV6 layout drift");
GE_SOURCE_FRONTEND_V6_STATIC_ASSERT(sizeof(GEFrontendTextEventV6) == 64u,
                                    "GEFrontendTextEventV6 layout drift");
GE_SOURCE_FRONTEND_V6_STATIC_ASSERT(sizeof(GEFrontendAudioEventV6) == 64u,
                                    "GEFrontendAudioEventV6 layout drift");
GE_SOURCE_FRONTEND_V6_STATIC_ASSERT(sizeof(GEFrontendSaveEventV6) == 48u,
                                    "GEFrontendSaveEventV6 layout drift");
GE_SOURCE_FRONTEND_V6_STATIC_ASSERT(sizeof(GEFrontendRenderEventV6) == 72u,
                                    "GEFrontendRenderEventV6 layout drift");
GE_SOURCE_FRONTEND_V6_STATIC_ASSERT(sizeof(GEFrontendDiagnosticV6) == 64u,
                                    "GEFrontendDiagnosticV6 layout drift");
GE_SOURCE_FRONTEND_V6_STATIC_ASSERT(sizeof(GEFrontendSnapshotV6) == 96u,
                                    "GEFrontendSnapshotV6 layout drift");
GE_SOURCE_FRONTEND_V6_STATIC_ASSERT(sizeof(GEFrontendStateV6) == 104u,
                                    "GEFrontendStateV6 layout drift");

#undef GE_SOURCE_FRONTEND_V6_STATIC_ASSERT

#ifdef __cplusplus
}
#endif

#endif /* GE_SOURCE_FRONTEND_V6_H */
