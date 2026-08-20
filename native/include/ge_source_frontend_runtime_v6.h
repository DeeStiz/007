#ifndef GE_SOURCE_FRONTEND_RUNTIME_V6_H
#define GE_SOURCE_FRONTEND_RUNTIME_V6_H

/*
 * Value-only host seam for ge_source_frontend_v6.c.
 *
 * The source facade has a transient callback table because its implementation
 * is still being closed over the native scene lowerer.  This header is the
 * production boundary: it exposes only copied fixed-width records.  Callback
 * function pointers and their context live in the C implementation and are
 * never retained in a state or frame record.
 */

#include <stdint.h>

#include "ge_native_foundation.h"
#include "ge_file_mode_v6.h"

#ifdef __cplusplus
extern "C" {
#endif

#define GE_SOURCE_FRONTEND_RUNTIME_V6_CONTRACT_VERSION ((uint32_t)6u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_RECORD_VERSION ((uint32_t)1u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_MAX_EVENTS ((uint32_t)32u)

#define GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_LEGAL ((uint32_t)0u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_NINTENDO ((uint32_t)1u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_RAREWARE ((uint32_t)2u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL ((uint32_t)3u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GOLDENEYE ((uint32_t)4u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_FILE_SELECT ((uint32_t)5u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_MODE_SELECT ((uint32_t)6u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_SWITCH ((uint32_t)24u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_CAST ((uint32_t)25u)

#define GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_NONE ((uint32_t)0u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_ANY ((uint32_t)1u << 0)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_CONFIRM ((uint32_t)1u << 1)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_CANCEL ((uint32_t)1u << 2)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_UP ((uint32_t)1u << 3)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_DOWN ((uint32_t)1u << 4)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_LEFT ((uint32_t)1u << 5)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_RIGHT ((uint32_t)1u << 6)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_MASK ((uint32_t)0x7fu)

#define GE_SOURCE_FRONTEND_RUNTIME_V6_INPUT_FLAG_SOURCE_ANCHOR ((uint32_t)1u << 0)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_INPUT_FLAG_FOCUSED ((uint32_t)1u << 1)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_INPUT_FLAG_CONTROLLER_CONNECTED ((uint32_t)1u << 2)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_INPUT_FLAG_SYNTHETIC ((uint32_t)1u << 3)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_INPUT_FLAG_PAIRED_ORACLE ((uint32_t)1u << 4)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_INPUT_FLAG_MASK ((uint32_t)0x1fu)

#define GE_SOURCE_FRONTEND_RUNTIME_V6_STATE_FLAG_FIRST_BOOT ((uint32_t)1u << 0)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_STATE_FLAG_FIRST_MAIN_MENU ((uint32_t)1u << 1)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_STATE_FLAG_PREV_KEYPRESS ((uint32_t)1u << 2)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_STATE_FLAG_GE_LOGO_BOOL ((uint32_t)1u << 3)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_STATE_FLAG_TRANSITION_READY ((uint32_t)1u << 4)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_STATE_FLAG_UNSUPPORTED ((uint32_t)1u << 5)

#define GE_SOURCE_FRONTEND_RUNTIME_V6_EVENT_SCREEN_ENTER ((uint32_t)1u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_EVENT_SCREEN_EXIT ((uint32_t)2u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_EVENT_TRANSITION ((uint32_t)3u)

#define GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_NONE ((uint32_t)0u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_LEGALPAGE ((uint32_t)1u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_NINTENDOLOGO ((uint32_t)2u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RAREWARELOGO ((uint32_t)3u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GUNBARREL ((uint32_t)4u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GOLDENEYELOGO ((uint32_t)5u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_WALLETBOND ((uint32_t)6u)

#define GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_LOAD ((uint32_t)1u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_RELEASE ((uint32_t)2u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_DRAW ((uint32_t)3u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_BLOOD_TICK ((uint32_t)4u)

#define GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_NONE ((uint32_t)0u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_BLOOD_COMPLETE ((uint32_t)1u << 0)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_EXECUTED ((uint32_t)1u << 1)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_FLAG_HALF_STEP ((uint32_t)1u << 8)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_FLAG_GUNBARREL_TIMER_VALID ((uint32_t)1u << 9)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GUNBARREL_TIMER_SHIFT ((uint32_t)16u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GUNBARREL_TIMER_MASK ((uint32_t)0xffff0000u)

#define GE_SOURCE_FRONTEND_RUNTIME_V6_AUDIO_OP_STOP_MUSIC ((uint32_t)1u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_AUDIO_OP_PLAY_MUSIC ((uint32_t)2u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_AUDIO_OP_PLAY_SFX ((uint32_t)3u)

#define GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_FRAME_BEGIN ((uint32_t)1u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_CLEAR_BLACK ((uint32_t)2u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_SOURCE_MODEL ((uint32_t)3u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_SOURCE_TEXT ((uint32_t)4u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_RAREWARE_PIPELINE ((uint32_t)5u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_GUNBARREL_PIPELINE ((uint32_t)6u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_UNSUPPORTED ((uint32_t)7u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_CONTINUOUS_STATE ((uint32_t)8u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_CAST_PIPELINE ((uint32_t)9u)

#define GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_FLAG_HALF_STEP ((uint32_t)1u << 8)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_FLAG_Q16_VALUES ((uint32_t)1u << 9)

#define GE_SOURCE_FRONTEND_RUNTIME_V6_CONTINUOUS_NINTENDO_ROTATION_SCALE ((uint32_t)1u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_CONTINUOUS_NINTENDO_AMBIENT ((uint32_t)2u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_CONTINUOUS_RAREWARE_ROTATION_ALPHA ((uint32_t)3u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_CONTINUOUS_GUNBARREL_TRANSLATION ((uint32_t)4u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_CONTINUOUS_GUNBARREL_COUNTER_WORD ((uint32_t)5u)

#define GE_SOURCE_FRONTEND_RUNTIME_V6_DIAG_UNSUPPORTED_MODEL ((uint32_t)1u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_DIAG_UNSUPPORTED_TEXT ((uint32_t)2u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_DIAG_UNSUPPORTED_RENDER ((uint32_t)3u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_DIAG_INVALID_INPUT ((uint32_t)4u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_DIAG_INVALID_STATE ((uint32_t)5u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_DIAG_UNSUPPORTED_AUDIO ((uint32_t)6u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_DIAG_UNSUPPORTED_SAVE ((uint32_t)7u)

#define GE_SOURCE_FRONTEND_RUNTIME_V6_DIAG_SEVERITY_INFO ((uint32_t)0u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_DIAG_SEVERITY_WARNING ((uint32_t)1u)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_DIAG_SEVERITY_ERROR ((uint32_t)2u)

typedef struct GEFrontendRuntimeV6Input {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t flags;
    uint32_t buttons_pressed;
    uint32_t controller_count;
    uint32_t clock_timer;
    uint64_t native_tick;
    uint64_t sequence;
    uint32_t reserved0;
    uint32_t reserved1;
    /* Optional positive result supplied by a complete scene adapter.  All
     * zero fields mean that the corresponding model operation is unsupported.
     * The record carries values only; no callback or scene object crosses the
     * boundary. */
    uint32_t model_result_model;
    uint32_t model_result_operation;
    uint32_t model_result_flags;
    uint32_t model_result_value0;
    uint32_t model_result_value1;
} GEFrontendRuntimeV6Input;

/* The fields after the envelope mirror the source state by value. */
typedef struct GEFrontendRuntimeV6State {
    GEAbiHeaderV1 header;
    uint32_t record_version;
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
} GEFrontendRuntimeV6State;

typedef struct GEFrontendRuntimeV6ScreenEvent {
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
} GEFrontendRuntimeV6ScreenEvent;

typedef struct GEFrontendRuntimeV6ModelEvent {
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
    uint32_t result_flags;
    uint32_t result_value0;
    uint32_t result_value1;
    uint32_t reserved0;
    uint32_t reserved1;
} GEFrontendRuntimeV6ModelEvent;

typedef struct GEFrontendRuntimeV6TextEvent {
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
} GEFrontendRuntimeV6TextEvent;

typedef struct GEFrontendRuntimeV6AudioEvent {
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
} GEFrontendRuntimeV6AudioEvent;

typedef struct GEFrontendRuntimeV6SaveEvent {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t screen;
    uint32_t operation;
    uint32_t folder;
    uint64_t native_tick;
    uint64_t sequence;
    uint32_t reserved0;
    uint32_t reserved1;
} GEFrontendRuntimeV6SaveEvent;

typedef struct GEFrontendRuntimeV6RenderEvent {
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
} GEFrontendRuntimeV6RenderEvent;

typedef struct GEFrontendRuntimeV6DiagnosticEvent {
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
} GEFrontendRuntimeV6DiagnosticEvent;

typedef struct GEFrontendRuntimeV6EventBatch {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t screen_count;
    uint32_t model_count;
    uint32_t text_count;
    uint32_t audio_count;
    uint32_t save_count;
    uint32_t render_count;
    uint32_t diagnostic_count;
    uint64_t screen_hash;
    uint64_t model_hash;
    uint64_t text_hash;
    uint64_t audio_hash;
    uint64_t save_hash;
    uint64_t render_hash;
    uint64_t diagnostic_hash;
    uint32_t overflow_flags;
    uint32_t reserved0;
    GEFrontendRuntimeV6ScreenEvent screens[GE_SOURCE_FRONTEND_RUNTIME_V6_MAX_EVENTS];
    GEFrontendRuntimeV6ModelEvent models[GE_SOURCE_FRONTEND_RUNTIME_V6_MAX_EVENTS];
    GEFrontendRuntimeV6TextEvent texts[GE_SOURCE_FRONTEND_RUNTIME_V6_MAX_EVENTS];
    GEFrontendRuntimeV6AudioEvent audio[GE_SOURCE_FRONTEND_RUNTIME_V6_MAX_EVENTS];
    GEFrontendRuntimeV6SaveEvent saves[GE_SOURCE_FRONTEND_RUNTIME_V6_MAX_EVENTS];
    GEFrontendRuntimeV6RenderEvent renders[GE_SOURCE_FRONTEND_RUNTIME_V6_MAX_EVENTS];
    GEFrontendRuntimeV6DiagnosticEvent diagnostics[GE_SOURCE_FRONTEND_RUNTIME_V6_MAX_EVENTS];
} GEFrontendRuntimeV6EventBatch;

typedef struct GEFrontendRuntimeV6Snapshot {
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
    uint64_t screen_hash;
    uint64_t model_hash;
    uint64_t text_hash;
    uint64_t audio_event_hash;
    uint64_t save_hash;
    uint64_t render_event_hash;
    uint64_t diagnostic_hash;
    uint32_t screen_count;
    uint32_t model_count;
    uint32_t text_count;
    uint32_t audio_count;
    uint32_t save_count;
    uint32_t render_count;
    uint32_t diagnostic_count;
    uint32_t reserved0;
    uint32_t reserved1;
} GEFrontendRuntimeV6Snapshot;

typedef struct GEFrontendRuntimeV6Frame {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t reserved0;
    GEFrontendRuntimeV6Snapshot snapshot;
    GEFrontendRuntimeV6EventBatch events;
} GEFrontendRuntimeV6Frame;

GEStatusV1 ge_frontend_runtime_v6_validate_input(
    const GEFrontendRuntimeV6Input *input);
GEStatusV1 ge_frontend_runtime_v6_validate_state(
    const GEFrontendRuntimeV6State *state);
GEStatusV1 ge_frontend_runtime_v6_validate_snapshot(
    const GEFrontendRuntimeV6Snapshot *snapshot);
GEStatusV1 ge_frontend_runtime_v6_validate_frame(
    const GEFrontendRuntimeV6Frame *frame);

GEStatusV1 ge_frontend_runtime_v6_init(
    GEFrontendRuntimeV6State *state,
    GEFrontendRuntimeV6Frame *out_frame);

GEStatusV1 ge_frontend_runtime_v6_step(
    GEFrontendRuntimeV6State *state,
    const GEFrontendRuntimeV6Input *input,
    GEFrontendRuntimeV6Frame *out_frame);

#if defined(__cplusplus)
#define GE_SOURCE_FRONTEND_RUNTIME_V6_STATIC_ASSERT(condition, message) \
    static_assert((condition), message)
#else
#define GE_SOURCE_FRONTEND_RUNTIME_V6_STATIC_ASSERT(condition, message) \
    _Static_assert((condition), message)
#endif

GE_SOURCE_FRONTEND_RUNTIME_V6_STATIC_ASSERT(sizeof(GEFrontendRuntimeV6Input) == 80u,
                                             "runtime input layout drift");
GE_SOURCE_FRONTEND_RUNTIME_V6_STATIC_ASSERT(sizeof(GEFrontendRuntimeV6State) == 112u,
                                             "runtime state layout drift");
GE_SOURCE_FRONTEND_RUNTIME_V6_STATIC_ASSERT(sizeof(GEFrontendRuntimeV6ScreenEvent) == 64u,
                                             "runtime screen event layout drift");
GE_SOURCE_FRONTEND_RUNTIME_V6_STATIC_ASSERT(sizeof(GEFrontendRuntimeV6ModelEvent) == 88u,
                                             "runtime model event layout drift");
GE_SOURCE_FRONTEND_RUNTIME_V6_STATIC_ASSERT(sizeof(GEFrontendRuntimeV6TextEvent) == 64u,
                                             "runtime text event layout drift");
GE_SOURCE_FRONTEND_RUNTIME_V6_STATIC_ASSERT(sizeof(GEFrontendRuntimeV6AudioEvent) == 64u,
                                             "runtime audio event layout drift");
GE_SOURCE_FRONTEND_RUNTIME_V6_STATIC_ASSERT(sizeof(GEFrontendRuntimeV6SaveEvent) == 48u,
                                             "runtime save event layout drift");
GE_SOURCE_FRONTEND_RUNTIME_V6_STATIC_ASSERT(sizeof(GEFrontendRuntimeV6RenderEvent) == 72u,
                                             "runtime render event layout drift");
GE_SOURCE_FRONTEND_RUNTIME_V6_STATIC_ASSERT(sizeof(GEFrontendRuntimeV6DiagnosticEvent) == 64u,
                                             "runtime diagnostic layout drift");
GE_SOURCE_FRONTEND_RUNTIME_V6_STATIC_ASSERT(sizeof(GEFrontendRuntimeV6Snapshot) == 184u,
                                             "runtime snapshot layout drift");
GE_SOURCE_FRONTEND_RUNTIME_V6_STATIC_ASSERT(sizeof(GEFrontendRuntimeV6EventBatch) == 14952u,
                                             "runtime event batch layout drift");
GE_SOURCE_FRONTEND_RUNTIME_V6_STATIC_ASSERT(sizeof(GEFrontendRuntimeV6Frame) == 15152u,
                                             "runtime frame layout drift");

#undef GE_SOURCE_FRONTEND_RUNTIME_V6_STATIC_ASSERT

#ifdef __cplusplus
}
#endif

#endif /* GE_SOURCE_FRONTEND_RUNTIME_V6_H */
