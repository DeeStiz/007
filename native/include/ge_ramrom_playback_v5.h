#ifndef GE_RAMROM_PLAYBACK_V5_H
#define GE_RAMROM_PLAYBACK_V5_H

/*
 * Deterministic native RAMROM playback seam.
 *
 * This layer consumes the validated source recording through call-time byte
 * buffers.  No byte pointer is retained in a public record and no N64 stage,
 * MIPS scheduler, ROM runtime, or gameplay implementation is present here.
 * The controller advances one source input sample at each even 120 Hz tick;
 * odd ticks publish an immutable paired state without consuming a recording
 * packet.  A future stage/gameplay owner can consume the copied install and
 * sample/event records without changing this contract.
 */

#include <stdint.h>

#include "ge_ramrom_v5.h"

#ifdef __cplusplus
extern "C" {
#endif

#define GE_RAMROM_PLAYBACK_V5_CONTRACT_VERSION ((uint32_t)5u)
#define GE_RAMROM_PLAYBACK_V5_RECORD_VERSION ((uint32_t)1u)
#define GE_RAMROM_PLAYBACK_V5_NATIVE_HZ ((uint32_t)120u)
#define GE_RAMROM_PLAYBACK_V5_REFERENCE_HZ ((uint32_t)60u)

#define GE_RAMROM_PLAYBACK_INSTALL_SAVE ((uint32_t)1u << 0)
#define GE_RAMROM_PLAYBACK_INSTALL_RNG ((uint32_t)1u << 1)
#define GE_RAMROM_PLAYBACK_INSTALL_REGISTERS ((uint32_t)1u << 2)
#define GE_RAMROM_PLAYBACK_INSTALL_STAGE_DIAGNOSTIC ((uint32_t)1u << 3)
#define GE_RAMROM_PLAYBACK_INSTALL_RESTORED ((uint32_t)1u << 4)
#define GE_RAMROM_PLAYBACK_INSTALL_FLAG_MASK ((uint32_t)0x1fu)

#define GE_RAMROM_PLAYBACK_STATE_ACTIVE ((uint32_t)1u << 0)
#define GE_RAMROM_PLAYBACK_STATE_INITIALIZED ((uint32_t)1u << 1)
#define GE_RAMROM_PLAYBACK_STATE_STAGE_UNSUPPORTED ((uint32_t)1u << 2)
#define GE_RAMROM_PLAYBACK_STATE_ABORT_REQUESTED ((uint32_t)1u << 3)
#define GE_RAMROM_PLAYBACK_STATE_COMPLETE ((uint32_t)1u << 4)
#define GE_RAMROM_PLAYBACK_STATE_ERROR ((uint32_t)1u << 5)
#define GE_RAMROM_PLAYBACK_STATE_INSTALL_READY ((uint32_t)1u << 6)
#define GE_RAMROM_PLAYBACK_STATE_RESTORE_READY ((uint32_t)1u << 7)
#define GE_RAMROM_PLAYBACK_STATE_FLAG_MASK ((uint32_t)0xffu)

#define GE_RAMROM_PLAYBACK_INPUT_REAL ((uint32_t)1u << 0)
#define GE_RAMROM_PLAYBACK_INPUT_FOCUSED ((uint32_t)1u << 1)
#define GE_RAMROM_PLAYBACK_INPUT_CONTROLLER ((uint32_t)1u << 2)
#define GE_RAMROM_PLAYBACK_INPUT_FLAG_MASK ((uint32_t)0x07u)

#define GE_RAMROM_PLAYBACK_EVENT_NONE ((uint32_t)0u)
#define GE_RAMROM_PLAYBACK_EVENT_INSTALL_STATE ((uint32_t)1u)
#define GE_RAMROM_PLAYBACK_EVENT_SAMPLE ((uint32_t)2u)
#define GE_RAMROM_PLAYBACK_EVENT_PACKET_ADVANCE ((uint32_t)3u)
#define GE_RAMROM_PLAYBACK_EVENT_FADE_TO_TITLE ((uint32_t)4u)
#define GE_RAMROM_PLAYBACK_EVENT_RETURN_TO_TITLE ((uint32_t)5u)
#define GE_RAMROM_PLAYBACK_EVENT_STAGE_LOAD_UNSUPPORTED ((uint32_t)6u)
#define GE_RAMROM_PLAYBACK_EVENT_ERROR ((uint32_t)7u)
#define GE_RAMROM_PLAYBACK_EVENT_MAX GE_RAMROM_PLAYBACK_EVENT_ERROR

#define GE_RAMROM_PLAYBACK_EVENT_FLAG_SOURCE_ANCHOR ((uint32_t)1u << 0)
#define GE_RAMROM_PLAYBACK_EVENT_FLAG_ODD_PAIRED_TICK ((uint32_t)1u << 1)
#define GE_RAMROM_PLAYBACK_EVENT_FLAG_PACKET_ADVANCE ((uint32_t)1u << 2)
#define GE_RAMROM_PLAYBACK_EVENT_FLAG_RNG_CHECKPOINT ((uint32_t)1u << 3)
#define GE_RAMROM_PLAYBACK_EVENT_FLAG_ABORTED_INPUT ((uint32_t)1u << 4)
#define GE_RAMROM_PLAYBACK_EVENT_FLAG_END_OF_STREAM ((uint32_t)1u << 5)
#define GE_RAMROM_PLAYBACK_EVENT_FLAG_INSTALL ((uint32_t)1u << 6)
#define GE_RAMROM_PLAYBACK_EVENT_FLAG_RESTORE ((uint32_t)1u << 7)
#define GE_RAMROM_PLAYBACK_EVENT_FLAG_DIAGNOSTIC ((uint32_t)1u << 8)
#define GE_RAMROM_PLAYBACK_EVENT_FLAG_MASK ((uint32_t)0x01ffu)

#define GE_RAMROM_PLAYBACK_DIAGNOSTIC_NONE ((uint32_t)0u)
#define GE_RAMROM_PLAYBACK_DIAGNOSTIC_CHECKSUM ((uint32_t)1u)
#define GE_RAMROM_PLAYBACK_DIAGNOSTIC_RNG ((uint32_t)2u)
#define GE_RAMROM_PLAYBACK_DIAGNOSTIC_STAGE_UNSUPPORTED ((uint32_t)3u)
#define GE_RAMROM_PLAYBACK_DIAGNOSTIC_INPUT_ABORT ((uint32_t)4u)
#define GE_RAMROM_PLAYBACK_DIAGNOSTIC_PACKET ((uint32_t)5u)
#define GE_RAMROM_PLAYBACK_DIAGNOSTIC_TICK ((uint32_t)6u)

/* Copy of all source state needed by a future native stage owner. */
typedef struct GERamRomPlaybackInstallV5 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t flags;
    GERamRomHeaderV5 source_header;
    uint64_t register_hash;
    uint64_t save_hash;
    uint32_t save_byte_count;
    uint32_t reserved0;
    uint8_t save_data[GE_RAMROM_V5_SAVE_BYTES];
} GERamRomPlaybackInstallV5;

/* Real user input is intentionally separate from recorded samples. */
typedef struct GERamRomPlaybackInputV5 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t flags;
    uint32_t pressed_buttons;
    uint32_t held_buttons;
    uint32_t released_buttons;
    uint32_t source_mask;
    uint32_t controller_count;
    uint32_t reserved0;
} GERamRomPlaybackInputV5;

/* One immutable output event; samples are copied into fixed four-controller arrays. */
typedef struct GERamRomPlaybackEventV5 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t event_type;
    uint32_t flags;
    uint32_t diagnostic_code;
    uint64_t native_tick;
    uint64_t reference_tick;
    uint32_t pair_phase;
    uint32_t demo_id;
    uint32_t stage_id;
    uint32_t packet_index;
    uint32_t packet_count;
    uint32_t frame_index;
    uint32_t record_count;
    uint32_t controller_count;
    uint32_t speedframes;
    uint32_t rng_seed;
    uint32_t sample_count;
    uint32_t source_anchor;
    uint32_t source_frame;
    uint32_t abort_buttons;
    uint64_t sample_hash;
    uint64_t state_hash;
    uint64_t recording_hash;
    uint64_t rng_hash;
    int8_t stick_x[GE_RAMROM_V5_MAX_CONTROLLERS];
    int8_t stick_y[GE_RAMROM_V5_MAX_CONTROLLERS];
    uint8_t button_low[GE_RAMROM_V5_MAX_CONTROLLERS];
    uint8_t button_high[GE_RAMROM_V5_MAX_CONTROLLERS];
    uint32_t buttons[GE_RAMROM_V5_MAX_CONTROLLERS];
    uint32_t reserved0;
    uint32_t reserved1;
} GERamRomPlaybackEventV5;

/* Mutable owner-thread value state; no external pointer or SDK object is retained. */
typedef struct GERamRomPlaybackStateV5 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t flags;
    uint32_t replay_state;
    uint32_t error_code;
    uint32_t demo_id;
    uint32_t stage_id;
    uint64_t native_tick;
    uint64_t reference_tick;
    uint32_t pair_phase;
    uint32_t packet_index;
    uint32_t packet_count;
    uint32_t frame_index;
    uint32_t record_count;
    uint32_t sample_index;
    uint32_t source_anchor;
    uint32_t source_frame;
    uint32_t speedframes;
    uint32_t rng_index;
    uint32_t controller_count;
    uint32_t abort_buttons;
    uint32_t event_count;
    uint32_t total_samples;
    uint64_t recording_hash;
    uint64_t packet_hash;
    uint64_t input_hash;
    uint64_t rng_hash;
    uint64_t playback_hash;
    GERamRomPlaybackInstallV5 install;
    uint32_t reserved0;
    uint32_t reserved1;
} GERamRomPlaybackStateV5;

GEStatusV1 ge_ramrom_playback_v5_validate_install(
    const GERamRomPlaybackInstallV5 *value);
GEStatusV1 ge_ramrom_playback_v5_validate_input(
    const GERamRomPlaybackInputV5 *value);
GEStatusV1 ge_ramrom_playback_v5_validate_event(
    const GERamRomPlaybackEventV5 *value);
GEStatusV1 ge_ramrom_playback_v5_validate_state(
    const GERamRomPlaybackStateV5 *value);

uint64_t ge_ramrom_playback_v5_hash_event(
    const GERamRomPlaybackEventV5 *value);
uint64_t ge_ramrom_playback_v5_hash_state(
    const GERamRomPlaybackStateV5 *value);

GEStatusV1 ge_ramrom_playback_v5_begin(
    const uint8_t *bytes,
    uint32_t byte_count,
    uint32_t demo_id,
    GERamRomPlaybackStateV5 *out_state,
    GERamRomPlaybackEventV5 *out_event);

GEStatusV1 ge_ramrom_playback_v5_step(
    const uint8_t *bytes,
    uint32_t byte_count,
    uint64_t native_tick,
    GERamRomPlaybackInputV5 input,
    GERamRomPlaybackStateV5 *inout_state,
    GERamRomPlaybackEventV5 *out_event);

/* Explicit M28 diagnostic seam: stage loading is not silently substituted. */
GEStatusV1 ge_ramrom_playback_v5_load_stage(
    const GERamRomPlaybackStateV5 *state,
    GERamRomPlaybackEventV5 *out_event);

GEStatusV1 ge_ramrom_playback_v5_copy_install(
    const GERamRomPlaybackStateV5 *state,
    GERamRomPlaybackInstallV5 *out_install,
    uint32_t for_restore);

#if defined(__cplusplus)
#define GE_RAMROM_PLAYBACK_V5_STATIC_ASSERT(condition, message) static_assert((condition), message)
#else
#define GE_RAMROM_PLAYBACK_V5_STATIC_ASSERT(condition, message) _Static_assert((condition), message)
#endif

GE_RAMROM_PLAYBACK_V5_STATIC_ASSERT(sizeof(GERamRomPlaybackInstallV5) == 320u,
                                    "GERamRomPlaybackInstallV5 layout drift");
GE_RAMROM_PLAYBACK_V5_STATIC_ASSERT(sizeof(GERamRomPlaybackInputV5) == 40u,
                                    "GERamRomPlaybackInputV5 layout drift");
GE_RAMROM_PLAYBACK_V5_STATIC_ASSERT(sizeof(GERamRomPlaybackEventV5) == 168u,
                                    "GERamRomPlaybackEventV5 layout drift");
GE_RAMROM_PLAYBACK_V5_STATIC_ASSERT(sizeof(GERamRomPlaybackStateV5) == 472u,
                                    "GERamRomPlaybackStateV5 layout drift");

#undef GE_RAMROM_PLAYBACK_V5_STATIC_ASSERT

#ifdef __cplusplus
}
#endif

#endif /* GE_RAMROM_PLAYBACK_V5_H */
