#ifndef GE_ORIGINAL_FRONTEND_V6_H
#define GE_ORIGINAL_FRONTEND_V6_H

/*
 * Dynamic source-oracle contract for the native frontend port.
 *
 * The implementation in ge_original_frontend_v6.c includes the checked-in
 * src/game/front.c and src/game/title.c translation units.  This public seam
 * is deliberately value-only: no Gfx pointer, source address, model graph,
 * ROM path, or host object is retained in a record.  The call-time event
 * buffer is owned by the caller and is copied out before the call returns.
 */

#include <stdint.h>

#include "../../include/ge_native_foundation.h"

#ifdef __cplusplus
extern "C" {
#endif

#define GE_ORIGINAL_FRONTEND_V6_CONTRACT_VERSION ((uint32_t)6u)
#define GE_ORIGINAL_FRONTEND_V6_RECORD_VERSION ((uint32_t)1u)
#define GE_ORIGINAL_FRONTEND_V6_NATIVE_HZ ((uint32_t)120u)
#define GE_ORIGINAL_FRONTEND_V6_REFERENCE_HZ ((uint32_t)60u)

enum {
    GE_ORIGINAL_FRONTEND_V6_SCREEN_LEGAL = 0u,
    GE_ORIGINAL_FRONTEND_V6_SCREEN_NINTENDO = 1u,
    GE_ORIGINAL_FRONTEND_V6_SCREEN_RAREWARE = 2u,
    GE_ORIGINAL_FRONTEND_V6_SCREEN_GUNBARREL = 3u,
    GE_ORIGINAL_FRONTEND_V6_SCREEN_GOLDENEYE = 4u,
    GE_ORIGINAL_FRONTEND_V6_SCREEN_FILE_SELECT = 5u,
    GE_ORIGINAL_FRONTEND_V6_SCREEN_MODE_SELECT = 6u,
    GE_ORIGINAL_FRONTEND_V6_SCREEN_SWITCH = 24u,
    GE_ORIGINAL_FRONTEND_V6_SCREEN_CAST = 25u,
};

enum {
    GE_ORIGINAL_FRONTEND_V6_BUTTON_NONE = 0u,
    GE_ORIGINAL_FRONTEND_V6_BUTTON_ANY = 1u << 0,
};

enum {
    GE_ORIGINAL_FRONTEND_V6_INPUT_CAPTURE_RENDER = 1u << 0,
    GE_ORIGINAL_FRONTEND_V6_INPUT_CONNECTED = 1u << 1,
    GE_ORIGINAL_FRONTEND_V6_INPUT_SYNTHETIC = 1u << 2,
};

enum {
    GE_ORIGINAL_FRONTEND_V6_EVENT_SCREEN = 1u,
    GE_ORIGINAL_FRONTEND_V6_EVENT_RENDER = 2u,
    GE_ORIGINAL_FRONTEND_V6_EVENT_AUDIO = 3u,
    GE_ORIGINAL_FRONTEND_V6_EVENT_MODEL = 4u,
    GE_ORIGINAL_FRONTEND_V6_EVENT_SOURCE_GAP = 5u,
};

enum {
    GE_ORIGINAL_FRONTEND_V6_OP_SCREEN_ENTER = 1u,
    GE_ORIGINAL_FRONTEND_V6_OP_SCREEN_EXIT = 2u,
    GE_ORIGINAL_FRONTEND_V6_OP_TRANSITION_REQUEST = 3u,
    GE_ORIGINAL_FRONTEND_V6_OP_RENDER_BEGIN = 4u,
    GE_ORIGINAL_FRONTEND_V6_OP_RENDER_END = 5u,
    GE_ORIGINAL_FRONTEND_V6_OP_AUDIO_STOP = 6u,
    GE_ORIGINAL_FRONTEND_V6_OP_AUDIO_MUSIC = 7u,
    GE_ORIGINAL_FRONTEND_V6_OP_AUDIO_SFX = 8u,
    GE_ORIGINAL_FRONTEND_V6_OP_MODEL_LOAD = 9u,
    GE_ORIGINAL_FRONTEND_V6_OP_MODEL_DRAW = 10u,
    GE_ORIGINAL_FRONTEND_V6_OP_MODEL_RELEASE = 11u,
};

typedef struct GEOriginalFrontendInputV6 {
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
} GEOriginalFrontendInputV6;

typedef struct GEOriginalFrontendEventV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t kind;
    uint32_t operation;
    uint32_t screen;
    uint32_t target_screen;
    uint32_t source_timer;
    uint32_t source_counter;
    uint64_t native_tick;
    uint64_t source_frame;
    uint64_t semantic_hash;
    uint32_t value0;
    uint32_t value1;
    uint32_t reserved0;
    uint32_t reserved1;
} GEOriginalFrontendEventV6;

typedef struct GEOriginalFrontendStateV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t screen;
    uint32_t pending_screen;
    uint32_t source_timer;
    uint32_t transition_timer;
    uint32_t rareware_mode;
    uint32_t rareware_counter;
    uint32_t gunbarrel_mode;
    uint32_t gunbarrel_counter;
    uint32_t flags;
    uint32_t unsupported_count;
    uint64_t native_tick;
    uint64_t source_frame;
    uint64_t event_sequence;
    uint64_t render_hash;
    uint64_t audio_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GEOriginalFrontendStateV6;

typedef struct GEOriginalFrontendFrameV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t screen;
    uint32_t pending_screen;
    uint32_t source_timer;
    uint32_t transition_timer;
    uint32_t rareware_mode;
    uint32_t rareware_counter;
    uint32_t gunbarrel_mode;
    uint32_t gunbarrel_counter;
    uint32_t event_count;
    uint32_t flags;
    uint64_t native_tick;
    uint64_t source_frame;
    uint64_t render_hash;
    uint64_t audio_hash;
    uint64_t state_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GEOriginalFrontendFrameV6;

GEStatusV1 ge_original_frontend_v6_validate_input(
    const GEOriginalFrontendInputV6 *input);
GEStatusV1 ge_original_frontend_v6_validate_event(
    const GEOriginalFrontendEventV6 *event);
GEStatusV1 ge_original_frontend_v6_validate_state(
    const GEOriginalFrontendStateV6 *state);
GEStatusV1 ge_original_frontend_v6_validate_frame(
    const GEOriginalFrontendFrameV6 *frame);

GEStatusV1 ge_original_frontend_v6_init(GEOriginalFrontendStateV6 *state);
GEStatusV1 ge_original_frontend_v6_step(
    GEOriginalFrontendStateV6 *state,
    const GEOriginalFrontendInputV6 *input,
    GEOriginalFrontendEventV6 *events,
    uint32_t capacity,
    uint32_t *out_count,
    GEOriginalFrontendFrameV6 *out_frame);

/* A constructor capture is explicitly opt-in and reports source GBI output
 * metadata only.  It never returns a source pointer or executes N64 code. */
GEStatusV1 ge_original_frontend_v6_capture_constructor(
    GEOriginalFrontendStateV6 *state,
    uint32_t screen,
    uint64_t native_tick,
    GEOriginalFrontendEventV6 *events,
    uint32_t capacity,
    uint32_t *out_count);

#ifdef __cplusplus
}
#endif

#if defined(__cplusplus)
static_assert(sizeof(GEOriginalFrontendInputV6) == 56u,
              "GEOriginalFrontendInputV6 layout drift");
static_assert(sizeof(GEOriginalFrontendEventV6) == 80u,
              "GEOriginalFrontendEventV6 layout drift");
static_assert(sizeof(GEOriginalFrontendStateV6) == 104u,
              "GEOriginalFrontendStateV6 layout drift");
static_assert(sizeof(GEOriginalFrontendFrameV6) == 104u,
              "GEOriginalFrontendFrameV6 layout drift");
#else
_Static_assert(sizeof(GEOriginalFrontendInputV6) == 56u,
               "GEOriginalFrontendInputV6 layout drift");
_Static_assert(sizeof(GEOriginalFrontendEventV6) == 80u,
               "GEOriginalFrontendEventV6 layout drift");
_Static_assert(sizeof(GEOriginalFrontendStateV6) == 104u,
               "GEOriginalFrontendStateV6 layout drift");
_Static_assert(sizeof(GEOriginalFrontendFrameV6) == 104u,
               "GEOriginalFrontendFrameV6 layout drift");
#endif

#endif /* GE_ORIGINAL_FRONTEND_V6_H */
