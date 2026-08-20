#ifndef GE_NATIVE_RUNTIME_V5_H
#define GE_NATIVE_RUNTIME_V5_H

/*
 * Native title/scene/audio runtime sidecar for the first playable port.
 *
 * This is intentionally separate from the frozen V1/V2/V3/V4 contracts.  All
 * records are copied, fixed-width values.  No record contains a pointer,
 * host address, SDK object, Gfx word, segmented address, or file path.  The
 * GEAbiHeaderV1 envelope is retained so Swift and C can validate every value
 * at the boundary; GE_RUNTIME_V5_RECORD_VERSION identifies this sidecar's
 * record schema.
 */

#include <stdint.h>

#include "ge_native_foundation.h"
#include "ge_audio_v5.h"

#ifdef __cplusplus
extern "C" {
#endif

#define GE_RUNTIME_V5_ABI_VERSION ((uint32_t)5u)
#define GE_RUNTIME_V5_RECORD_VERSION ((uint32_t)1u)

#define GE_RUNTIME_V5_TIMEBASE_POLICY_PAIRED_TICKS ((uint32_t)1u << 0)
#define GE_RUNTIME_V5_TIMEBASE_POLICY_EVEN_ANCHOR ((uint32_t)1u << 1)
#define GE_RUNTIME_V5_TIMEBASE_POLICY_CONTINUOUS_ODD ((uint32_t)1u << 2)
#define GE_RUNTIME_V5_TIMEBASE_POLICY_AUDIO_RATIONAL ((uint32_t)1u << 3)
#define GE_RUNTIME_V5_TIMEBASE_POLICY_MASK ((uint32_t)0x0fu)

#define GE_INPUT_EVENT_NONE ((uint32_t)0u)
#define GE_INPUT_EVENT_BUTTON_DOWN ((uint32_t)1u)
#define GE_INPUT_EVENT_BUTTON_UP ((uint32_t)2u)
#define GE_INPUT_EVENT_AXIS ((uint32_t)3u)
#define GE_INPUT_EVENT_FOCUS_LOST ((uint32_t)4u)
#define GE_INPUT_EVENT_FOCUS_GAINED ((uint32_t)5u)
#define GE_INPUT_EVENT_CONTROLLER_CONNECTED ((uint32_t)6u)
#define GE_INPUT_EVENT_CONTROLLER_DISCONNECTED ((uint32_t)7u)
#define GE_INPUT_EVENT_SNAPSHOT ((uint32_t)8u)
#define GE_INPUT_EVENT_MAX GE_INPUT_EVENT_SNAPSHOT

#define GE_INPUT_SOURCE_KEYBOARD ((uint32_t)1u << 0)
#define GE_INPUT_SOURCE_CONTROLLER ((uint32_t)1u << 1)
#define GE_INPUT_SOURCE_SYSTEM ((uint32_t)1u << 2)
#define GE_INPUT_SOURCE_MASK ((uint32_t)0x07u)

#define GE_INPUT_FLAG_FOCUSED ((uint32_t)1u << 0)
#define GE_INPUT_FLAG_ANALOG ((uint32_t)1u << 1)
#define GE_INPUT_FLAG_SYNTHETIC ((uint32_t)1u << 2)
#define GE_INPUT_FLAG_DROPPED ((uint32_t)1u << 3)
#define GE_INPUT_FLAG_SUPPRESS_EDGES ((uint32_t)1u << 4)
#define GE_INPUT_FLAG_MASK ((uint32_t)0x1fu)

#define GE_TITLE_SCREEN_LEGAL ((uint32_t)0u)
#define GE_TITLE_SCREEN_NINTENDO ((uint32_t)1u)
#define GE_TITLE_SCREEN_RAREWARE ((uint32_t)2u)
#define GE_TITLE_SCREEN_GUNBARREL ((uint32_t)3u)
#define GE_TITLE_SCREEN_GOLDENEYE ((uint32_t)4u)
#define GE_TITLE_SCREEN_FILE_SELECT ((uint32_t)5u)
#define GE_TITLE_SCREEN_MODE_SELECT ((uint32_t)6u)
#define GE_TITLE_SCREEN_CAST ((uint32_t)7u)
#define GE_TITLE_SCREEN_RAMROM ((uint32_t)8u)
#define GE_TITLE_SCREEN_MAX GE_TITLE_SCREEN_RAMROM

#define GE_TITLE_FLAG_FIRST_BOOT ((uint32_t)1u << 0)
#define GE_TITLE_FLAG_INPUT_ALLOWED ((uint32_t)1u << 1)
#define GE_TITLE_FLAG_SKIP_ALLOWED ((uint32_t)1u << 2)
#define GE_TITLE_FLAG_SOURCE_ANCHOR ((uint32_t)1u << 3)
#define GE_TITLE_FLAG_TRANSITIONING ((uint32_t)1u << 4)
#define GE_TITLE_FLAG_MASK ((uint32_t)0x1fu)

#define GE_SCENE_FRAME_FLAG_PRESENTABLE ((uint32_t)1u << 0)
#define GE_SCENE_FRAME_FLAG_CATCHING_UP ((uint32_t)1u << 1)
#define GE_SCENE_FRAME_FLAG_HAS_UI ((uint32_t)1u << 2)
#define GE_SCENE_FRAME_FLAG_HAS_AUDIO ((uint32_t)1u << 3)
#define GE_SCENE_FRAME_FLAG_RESIZE_PENDING ((uint32_t)1u << 4)
#define GE_SCENE_FRAME_FLAG_MASK ((uint32_t)0x1fu)

#define GE_SCENE_PAGE_TRANSFORMS ((uint32_t)1u)
#define GE_SCENE_PAGE_RESOURCES ((uint32_t)2u)
#define GE_SCENE_PAGE_DRAWS ((uint32_t)3u)
#define GE_SCENE_PAGE_UI ((uint32_t)4u)
#define GE_SCENE_PAGE_DIAGNOSTICS ((uint32_t)5u)
#define GE_SCENE_PAGE_MAX GE_SCENE_PAGE_DIAGNOSTICS

#define GE_AUDIO_COMMAND_NONE ((uint32_t)0u)
#define GE_AUDIO_COMMAND_NOTE_ON ((uint32_t)1u)
#define GE_AUDIO_COMMAND_NOTE_OFF ((uint32_t)2u)
#define GE_AUDIO_COMMAND_SFX ((uint32_t)3u)
#define GE_AUDIO_COMMAND_MUSIC_START ((uint32_t)4u)
#define GE_AUDIO_COMMAND_MUSIC_STOP ((uint32_t)5u)
#define GE_AUDIO_COMMAND_SET_PARAM ((uint32_t)6u)
#define GE_AUDIO_COMMAND_MAX GE_AUDIO_COMMAND_SET_PARAM

#define GE_AUDIO_COMMAND_FLAG_LOOP ((uint32_t)1u << 0)
#define GE_AUDIO_COMMAND_FLAG_RETRIGGER ((uint32_t)1u << 1)
#define GE_AUDIO_COMMAND_FLAG_COMPOSITE ((uint32_t)1u << 2)
#define GE_AUDIO_COMMAND_FLAG_MASK ((uint32_t)0x07u)

#define GE_AUDIO_SAMPLE_FORMAT_S16_INTERLEAVED ((uint32_t)1u)
#define GE_AUDIO_SAMPLE_FORMAT_F32_INTERLEAVED ((uint32_t)2u)

#define GE_AUDIO_SFX_SLOT_CAPACITY ((uint32_t)8u)
#define GE_AUDIO_MUSIC_SLOT_CAPACITY ((uint32_t)3u)
#define GE_AUDIO_VOICE_CAPACITY ((uint32_t)24u)

#define GE_AUDIO_SNAPSHOT_FLAG_RUNNING ((uint32_t)1u << 0)
#define GE_AUDIO_SNAPSHOT_FLAG_UNDERRUN ((uint32_t)1u << 1)
#define GE_AUDIO_SNAPSHOT_FLAG_DROPPED ((uint32_t)1u << 2)
#define GE_AUDIO_SNAPSHOT_FLAG_MASK ((uint32_t)0x07u)

#define GE_RAMROM_STATE_IDLE ((uint32_t)0u)
#define GE_RAMROM_STATE_LOADING ((uint32_t)1u)
#define GE_RAMROM_STATE_PLAYING ((uint32_t)2u)
#define GE_RAMROM_STATE_ABORTING ((uint32_t)3u)
#define GE_RAMROM_STATE_COMPLETE ((uint32_t)4u)
#define GE_RAMROM_STATE_ERROR ((uint32_t)5u)
#define GE_RAMROM_STATE_MAX GE_RAMROM_STATE_ERROR

#define GE_RAMROM_FLAG_SOURCE_ANCHOR ((uint32_t)1u << 0)
#define GE_RAMROM_FLAG_INPUT_ABORT ((uint32_t)1u << 1)
#define GE_RAMROM_FLAG_CHECKSUM_VALID ((uint32_t)1u << 2)
#define GE_RAMROM_FLAG_RNG_CHECKPOINT ((uint32_t)1u << 3)
#define GE_RAMROM_FLAG_MASK ((uint32_t)0x0fu)

/* All Q16.16 axes are normalized to [-1, +1]. */
#define GE_RUNTIME_V5_AXIS_MIN_Q16 ((int32_t)-65536)
#define GE_RUNTIME_V5_AXIS_MAX_Q16 ((int32_t)65536)

typedef struct GETimebaseConfigV5 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t native_hz;
    uint32_t reference_hz;
    uint32_t pair_numerator;
    uint32_t pair_denominator;
    uint32_t max_catch_up_ticks;
    uint32_t max_tick_debt;
    uint32_t policy_flags;
    uint32_t audio_sample_rate;
    uint32_t reserved0;
    uint32_t reserved1;
    uint32_t reserved2;
} GETimebaseConfigV5;

typedef struct GEInputEventV5 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t event_type;
    uint32_t source;
    uint32_t flags;
    uint32_t buttons;
    int32_t axis_x_q16;
    int32_t axis_y_q16;
    int32_t trigger_l_q16;
    int32_t trigger_r_q16;
    uint32_t reserved0;
    uint64_t timestamp_ns;
    uint64_t sequence;
} GEInputEventV5;

typedef struct GEInputSnapshotV5 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t flags;
    uint64_t sequence;
    uint64_t timestamp_ns;
    uint64_t native_tick;
    uint32_t held;
    uint32_t pressed;
    uint32_t released;
    uint32_t source_mask;
    uint32_t controller_count;
    int32_t axis_x_q16;
    int32_t axis_y_q16;
    int32_t trigger_l_q16;
    int32_t trigger_r_q16;
    uint32_t reserved0;
    uint32_t reserved1;
    uint32_t reserved2;
} GEInputSnapshotV5;

typedef struct GETitleParitySnapshotV5 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t flags;
    uint64_t native_tick;
    uint64_t reference_tick;
    uint32_t pair_phase;
    uint32_t screen;
    uint32_t subphase;
    uint32_t source_timer;
    uint32_t source_threshold;
    uint32_t source_frame;
    uint32_t transition;
    uint32_t selection;
    uint32_t cursor;
    int32_t transform_q16[8];
    uint64_t state_hash;
    uint64_t render_hash;
    uint64_t audio_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GETitleParitySnapshotV5;

typedef struct GESceneFrameV5 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t flags;
    uint64_t native_tick;
    uint64_t reference_tick;
    uint32_t pair_phase;
    uint32_t frame_slot;
    uint32_t viewport_width;
    uint32_t viewport_height;
    uint32_t logical_width;
    uint32_t logical_height;
    uint32_t transform_count;
    uint32_t resource_count;
    uint32_t draw_count;
    uint32_t ui_packet_count;
    uint32_t diagnostic_count;
    uint32_t page_size;
    uint32_t page_count;
    uint64_t scene_hash;
    uint64_t render_hash;
    uint64_t audio_cursor;
    uint32_t reserved0;
    uint32_t reserved1;
} GESceneFrameV5;

/* Metadata for one bounded copy-out page.  The payload itself is supplied to
   a call-time copy-out function and is never embedded as a pointer here. */
typedef struct GEScenePageV5 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t page_kind;
    uint32_t page_index;
    uint32_t item_size;
    uint32_t first_item;
    uint32_t item_count;
    uint32_t total_items;
    uint64_t page_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GEScenePageV5;

typedef struct GEAudioCommandV5 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t command_type;
    uint32_t slot;
    uint32_t voice;
    uint32_t flags;
    uint32_t asset_handle;
    uint32_t note;
    uint32_t velocity;
    int32_t pitch_q16;
    int32_t pan_q16;
    int32_t gain_q16;
    uint64_t sample_index;
    uint32_t duration_frames;
    uint32_t loop_begin;
    uint32_t loop_end;
    uint32_t reserved0;
    uint64_t payload_hash;
} GEAudioCommandV5;

typedef struct GERamRomSnapshotV5 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t flags;
    uint64_t native_tick;
    uint64_t reference_tick;
    uint32_t demo_id;
    uint32_t stage_id;
    uint32_t replay_state;
    uint32_t packet_index;
    uint32_t packet_count;
    uint32_t speedframes;
    uint32_t rng_index;
    uint32_t input_buttons;
    uint32_t reserved0;
    uint64_t recording_hash;
    uint64_t rng_hash;
    uint64_t state_hash;
    uint64_t render_hash;
    uint64_t audio_hash;
    uint64_t save_generation;
    uint32_t reserved1;
    uint32_t reserved2;
} GERamRomSnapshotV5;

/* Deterministic FNV-1a helpers use explicit little-endian words. */
uint64_t ge_runtime_v5_hash_bytes(const uint8_t *bytes, uint32_t byte_count);
uint64_t ge_runtime_v5_hash_timebase(const GETimebaseConfigV5 *value);
uint64_t ge_runtime_v5_hash_input_event(const GEInputEventV5 *value);
uint64_t ge_runtime_v5_hash_input_snapshot(const GEInputSnapshotV5 *value);
uint64_t ge_runtime_v5_hash_title(const GETitleParitySnapshotV5 *value);
uint64_t ge_runtime_v5_hash_scene_frame(const GESceneFrameV5 *value);
uint64_t ge_runtime_v5_hash_scene_page(const GEScenePageV5 *value);
uint64_t ge_runtime_v5_hash_audio_command(const GEAudioCommandV5 *value);
uint64_t ge_runtime_v5_hash_audio_pcm_block(const GEAudioPCMBlockV5 *value);
uint64_t ge_runtime_v5_hash_audio_snapshot(const GEAudioSnapshotV5 *value);
uint64_t ge_runtime_v5_hash_ramrom(const GERamRomSnapshotV5 *value);

/* Every validator checks the envelope, schema version, enum/range fields and
   that all reserved fields are zero. */
GEStatusV1 ge_runtime_v5_validate_timebase(const GETimebaseConfigV5 *value);
GEStatusV1 ge_runtime_v5_validate_input_event(const GEInputEventV5 *value);
GEStatusV1 ge_runtime_v5_validate_input_snapshot(const GEInputSnapshotV5 *value);
GEStatusV1 ge_runtime_v5_validate_title(const GETitleParitySnapshotV5 *value);
GEStatusV1 ge_runtime_v5_validate_scene_frame(const GESceneFrameV5 *value);
GEStatusV1 ge_runtime_v5_validate_scene_page(const GEScenePageV5 *value);
GEStatusV1 ge_runtime_v5_validate_audio_command(const GEAudioCommandV5 *value);
GEStatusV1 ge_runtime_v5_validate_audio_pcm_block(const GEAudioPCMBlockV5 *value);
GEStatusV1 ge_runtime_v5_validate_audio_snapshot(const GEAudioSnapshotV5 *value);
GEStatusV1 ge_runtime_v5_validate_ramrom(const GERamRomSnapshotV5 *value);

/* A bounded page calculation used by Swift copy-out adapters. */
GEStatusV1 ge_runtime_v5_scene_page_bounds(
    uint32_t total_items,
    uint32_t item_size,
    uint32_t page_index,
    uint32_t page_capacity,
    uint32_t *first_item,
    uint32_t *item_count);

/* Validate a PCM block and its call-time payload without retaining the bytes. */
GEStatusV1 ge_runtime_v5_validate_audio_pcm_payload(
    const GEAudioPCMBlockV5 *block,
    const uint8_t *pcm_bytes,
    uint32_t pcm_byte_count);

#if defined(__cplusplus)
#define GE_RUNTIME_V5_STATIC_ASSERT(condition, message) static_assert((condition), message)
#else
#define GE_RUNTIME_V5_STATIC_ASSERT(condition, message) _Static_assert((condition), message)
#endif

GE_RUNTIME_V5_STATIC_ASSERT(sizeof(GEAbiHeaderV1) == 8u, "GEAbiHeaderV1 layout drift");
GE_RUNTIME_V5_STATIC_ASSERT(sizeof(GETimebaseConfigV5) == 56u, "GETimebaseConfigV5 layout drift");
GE_RUNTIME_V5_STATIC_ASSERT(sizeof(GEInputEventV5) == 64u, "GEInputEventV5 layout drift");
GE_RUNTIME_V5_STATIC_ASSERT(sizeof(GEInputSnapshotV5) == 88u, "GEInputSnapshotV5 layout drift");
GE_RUNTIME_V5_STATIC_ASSERT(sizeof(GETitleParitySnapshotV5) == 136u, "GETitleParitySnapshotV5 layout drift");
GE_RUNTIME_V5_STATIC_ASSERT(sizeof(GESceneFrameV5) == 120u, "GESceneFrameV5 layout drift");
GE_RUNTIME_V5_STATIC_ASSERT(sizeof(GEScenePageV5) == 56u, "GEScenePageV5 layout drift");
GE_RUNTIME_V5_STATIC_ASSERT(sizeof(GEAudioCommandV5) == 88u, "GEAudioCommandV5 layout drift");
GE_RUNTIME_V5_STATIC_ASSERT(sizeof(GEAudioPCMBlockV5) == 64u, "GEAudioPCMBlockV5 layout drift");
GE_RUNTIME_V5_STATIC_ASSERT(sizeof(GEAudioSnapshotV5) == 88u, "GEAudioSnapshotV5 layout drift");
GE_RUNTIME_V5_STATIC_ASSERT(sizeof(GERamRomSnapshotV5) == 128u, "GERamRomSnapshotV5 layout drift");

#undef GE_RUNTIME_V5_STATIC_ASSERT

#ifdef __cplusplus
}
#endif

#endif /* GE_NATIVE_RUNTIME_V5_H */
