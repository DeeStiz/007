#ifndef GE_ORIGINAL_FRONTEND_V6_MODULE_H
#define GE_ORIGINAL_FRONTEND_V6_MODULE_H

/*
 * Standalone SwiftPM module surface.
 *
 * This header intentionally does not include GoldenEyeNative or any native
 * implementation header. The private source-port contract has the same
 * byte-level records, but the public module uses prefixed ABI/status types so
 * importing both C modules in one Swift translation unit cannot form a module
 * cycle or merge unrelated typedefs.
 */

#include <stdint.h>

typedef struct GEOriginalAbiHeaderV1 {
    uint32_t abi_version;
    uint32_t struct_size;
} GEOriginalAbiHeaderV1;

typedef uint32_t GEOriginalStatusV1;

#define GE_ORIGINAL_STATUS_OK ((uint32_t)0u)
#define GE_ORIGINAL_FRONTEND_V6_RECORD_VERSION ((uint32_t)1u)

#define GE_ORIGINAL_FRONTEND_V6_SCREEN_LEGAL ((uint32_t)0u)
#define GE_ORIGINAL_FRONTEND_V6_SCREEN_NINTENDO ((uint32_t)1u)
#define GE_ORIGINAL_FRONTEND_V6_SCREEN_RAREWARE ((uint32_t)2u)
#define GE_ORIGINAL_FRONTEND_V6_SCREEN_GUNBARREL ((uint32_t)3u)
#define GE_ORIGINAL_FRONTEND_V6_SCREEN_GOLDENEYE ((uint32_t)4u)
#define GE_ORIGINAL_FRONTEND_V6_SCREEN_FILE_SELECT ((uint32_t)5u)
#define GE_ORIGINAL_FRONTEND_V6_SCREEN_MODE_SELECT ((uint32_t)6u)
#define GE_ORIGINAL_FRONTEND_V6_SCREEN_SWITCH ((uint32_t)24u)
#define GE_ORIGINAL_FRONTEND_V6_SCREEN_CAST ((uint32_t)25u)

#define GE_ORIGINAL_FRONTEND_V6_BUTTON_NONE ((uint32_t)0u)
#define GE_ORIGINAL_FRONTEND_V6_BUTTON_ANY ((uint32_t)1u)

#define GE_ORIGINAL_FRONTEND_V6_INPUT_CAPTURE_RENDER ((uint32_t)1u << 0)
#define GE_ORIGINAL_FRONTEND_V6_INPUT_CONNECTED ((uint32_t)1u << 1)
#define GE_ORIGINAL_FRONTEND_V6_INPUT_SYNTHETIC ((uint32_t)1u << 2)

#define GE_ORIGINAL_FRONTEND_V6_EVENT_SCREEN ((uint32_t)1u)
#define GE_ORIGINAL_FRONTEND_V6_EVENT_RENDER ((uint32_t)2u)
#define GE_ORIGINAL_FRONTEND_V6_EVENT_AUDIO ((uint32_t)3u)
#define GE_ORIGINAL_FRONTEND_V6_EVENT_MODEL ((uint32_t)4u)
#define GE_ORIGINAL_FRONTEND_V6_EVENT_SOURCE_GAP ((uint32_t)5u)

typedef struct GEOriginalFrontendInputV6 {
    GEOriginalAbiHeaderV1 header;
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
    GEOriginalAbiHeaderV1 header;
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
    GEOriginalAbiHeaderV1 header;
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
    GEOriginalAbiHeaderV1 header;
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

#ifdef __cplusplus
extern "C" {
#endif

uint32_t ge_original_frontend_v6_validate_input(
    const GEOriginalFrontendInputV6 *input);
uint32_t ge_original_frontend_v6_validate_event(
    const GEOriginalFrontendEventV6 *event);
uint32_t ge_original_frontend_v6_validate_state(
    const GEOriginalFrontendStateV6 *state);
uint32_t ge_original_frontend_v6_validate_frame(
    const GEOriginalFrontendFrameV6 *frame);

uint32_t ge_original_frontend_v6_init(GEOriginalFrontendStateV6 *state);
uint32_t ge_original_frontend_v6_step(
    GEOriginalFrontendStateV6 *state,
    const GEOriginalFrontendInputV6 *input,
    GEOriginalFrontendEventV6 *events,
    uint32_t capacity,
    uint32_t *out_count,
    GEOriginalFrontendFrameV6 *out_frame);

uint32_t ge_original_frontend_v6_capture_constructor(
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
static_assert(sizeof(GEOriginalAbiHeaderV1) == 8u,
              "GEOriginalAbiHeaderV1 layout drift");
static_assert(sizeof(GEOriginalFrontendInputV6) == 56u,
              "GEOriginalFrontendInputV6 layout drift");
static_assert(sizeof(GEOriginalFrontendEventV6) == 80u,
              "GEOriginalFrontendEventV6 layout drift");
static_assert(sizeof(GEOriginalFrontendStateV6) == 104u,
              "GEOriginalFrontendStateV6 layout drift");
static_assert(sizeof(GEOriginalFrontendFrameV6) == 104u,
              "GEOriginalFrontendFrameV6 layout drift");
#else
_Static_assert(sizeof(GEOriginalAbiHeaderV1) == 8u,
               "GEOriginalAbiHeaderV1 layout drift");
_Static_assert(sizeof(GEOriginalFrontendInputV6) == 56u,
               "GEOriginalFrontendInputV6 layout drift");
_Static_assert(sizeof(GEOriginalFrontendEventV6) == 80u,
               "GEOriginalFrontendEventV6 layout drift");
_Static_assert(sizeof(GEOriginalFrontendStateV6) == 104u,
               "GEOriginalFrontendStateV6 layout drift");
_Static_assert(sizeof(GEOriginalFrontendFrameV6) == 104u,
               "GEOriginalFrontendFrameV6 layout drift");
#endif

#endif /* GE_ORIGINAL_FRONTEND_V6_MODULE_H */
