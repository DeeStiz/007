#ifndef GE_AUDIO_V5_H
#define GE_AUDIO_V5_H

/*
 * Additive native audio contract for the boot/menu port.
 *
 * These records describe guarded, ROM-derived audio assets and immutable
 * audio observations.  They deliberately contain no pointers, host paths,
 * ROM addresses, libaudio objects, or realtime callback state.  The shared
 * ABI envelope remains GE_NATIVE_ABI_VERSION; contract_version identifies
 * this sidecar as V5.
 */

#include <stdint.h>

#include "ge_native_foundation.h"

#define GE_AUDIO_V5_CONTRACT_VERSION ((uint32_t)5u)

#define GE_AUDIO_V5_SAMPLE_RATE ((uint32_t)22050u)
#define GE_AUDIO_V5_NATIVE_TICK_RATE ((uint32_t)120u)
#define GE_AUDIO_V5_SAMPLE_NUMERATOR ((uint32_t)735u)
#define GE_AUDIO_V5_SAMPLE_DENOMINATOR ((uint32_t)4u)
#define GE_AUDIO_V5_MAX_VOICES ((uint32_t)24u)
#define GE_AUDIO_V5_PCM_MAX_FRAMES ((uint32_t)8192u)

#define GE_AUDIO_V5_HANDLE_NONE ((uint32_t)0u)
#define GE_AUDIO_V5_VOICE_NONE ((uint32_t)UINT32_MAX)

/* Asset kinds are intentionally broad; individual bank/sequence names are
   catalog data, not ABI schema. */
#define GE_AUDIO_V5_ASSET_MUSIC_SEQUENCE ((uint32_t)1u)
#define GE_AUDIO_V5_ASSET_INSTRUMENT_CTL ((uint32_t)2u)
#define GE_AUDIO_V5_ASSET_INSTRUMENT_TBL ((uint32_t)3u)
#define GE_AUDIO_V5_ASSET_SFX_CTL ((uint32_t)4u)
#define GE_AUDIO_V5_ASSET_SFX_TBL ((uint32_t)5u)

#define GE_AUDIO_V5_ASSET_FLAG_COMPRESSED ((uint32_t)1u << 0)
#define GE_AUDIO_V5_ASSET_FLAG_DECODED ((uint32_t)1u << 1)
#define GE_AUDIO_V5_ASSET_FLAG_BOOT_REQUIRED ((uint32_t)1u << 2)
#define GE_AUDIO_V5_ASSET_FLAG_RUNTIME_REQUIRED ((uint32_t)1u << 3)
#define GE_AUDIO_V5_ASSET_FLAG_MASK ((uint32_t)0x0fu)

typedef struct GEAudioAssetV5 {
    GEAbiHeaderV1 header;
    uint32_t contract_version;
    uint32_t asset_kind;
    uint32_t asset_handle;
    uint32_t flags;
    uint32_t catalog_id;
    uint32_t source_byte_count;
    uint32_t decoded_byte_count;
    uint32_t reserved0;
    uint8_t source_sha256[32];
    uint8_t decoded_sha256[32];
} GEAudioAssetV5;

#define GE_AUDIO_V5_EVENT_NOP ((uint32_t)0u)
#define GE_AUDIO_V5_EVENT_START_SEQUENCE ((uint32_t)1u)
#define GE_AUDIO_V5_EVENT_STOP_SEQUENCE ((uint32_t)2u)
#define GE_AUDIO_V5_EVENT_START_SFX ((uint32_t)3u)
#define GE_AUDIO_V5_EVENT_STOP_VOICE ((uint32_t)4u)
#define GE_AUDIO_V5_EVENT_SET_PARAMETER ((uint32_t)5u)
#define GE_AUDIO_V5_EVENT_MARKER ((uint32_t)6u)

#define GE_AUDIO_V5_EVENT_FLAG_RETRIGGER ((uint32_t)1u << 0)
#define GE_AUDIO_V5_EVENT_FLAG_LOOP ((uint32_t)1u << 1)
#define GE_AUDIO_V5_EVENT_FLAG_MASK ((uint32_t)0x03u)

/* Event values are Q16.16 where a parameter needs a fractional value. */
typedef struct GEAudioEventV5 {
    GEAbiHeaderV1 header;
    uint32_t contract_version;
    uint32_t event_kind;
    uint32_t flags;
    uint32_t voice_index;
    uint64_t sample_index;
    uint32_t asset_handle;
    int32_t value0_q16;
    int32_t value1_q16;
    int32_t value2_q16;
    uint32_t reserved0;
} GEAudioEventV5;

#define GE_AUDIO_V5_PCM_FORMAT_S16 ((uint32_t)1u)
#define GE_AUDIO_V5_PCM_FORMAT_F32 ((uint32_t)2u)
#define GE_AUDIO_V5_PCM_FLAG_PREROLL ((uint32_t)1u << 0)
#define GE_AUDIO_V5_PCM_FLAG_SILENCE ((uint32_t)1u << 1)
#define GE_AUDIO_V5_PCM_FLAG_MASK ((uint32_t)0x03u)

/* Metadata for a bounded immutable block; PCM samples themselves stay in the
   owner-side ring and never cross this fixed-width control ABI. */
typedef struct GEAudioPCMBlockV5 {
    GEAbiHeaderV1 header;
    uint32_t contract_version;
    uint32_t flags;
    uint64_t first_sample_index;
    uint32_t frame_count;
    uint32_t channel_count;
    uint32_t sample_format;
    uint32_t sample_rate;
    uint64_t content_hash;
    uint32_t underrun_count;
    uint32_t reserved0;
    uint32_t bytes_per_frame;
    uint32_t byte_count;
} GEAudioPCMBlockV5;

typedef struct GEAudioSnapshotV5 {
    GEAbiHeaderV1 header;
    uint32_t contract_version;
    uint32_t flags;
    uint64_t native_tick;
    uint64_t sample_cursor;
    uint64_t event_hash;
    uint64_t pcm_hash;
    uint32_t active_voice_count;
    uint32_t underrun_count;
    uint32_t dropped_event_count;
    uint32_t reserved0;
    uint32_t sample_rate;
    uint32_t frames_generated;
    uint32_t music_slot_count;
    uint32_t reserved1;
    uint32_t reserved2;
    uint32_t reserved3;
} GEAudioSnapshotV5;

typedef struct GEAudioClockV5 {
    GEAbiHeaderV1 header;
    uint64_t native_tick;
    uint64_t sample_index;
    uint32_t contract_version;
    uint32_t frame_count;
    uint32_t pair_phase;
    uint32_t reserved0;
} GEAudioClockV5;

/* Exact source-rate clock conversion.  sample_index is
   floor(native_tick * 735 / 4), and frame_count is the difference between
   consecutive sample indices. */
uint64_t ge_audio_sample_index_for_tick_v5(uint64_t native_tick);
uint32_t ge_audio_frame_count_for_tick_v5(uint64_t native_tick);
GEAudioClockV5 ge_audio_clock_for_tick_v5(uint64_t native_tick);

GEStatusV1 ge_audio_validate_asset_v5(GEAudioAssetV5 asset);
GEStatusV1 ge_audio_validate_event_v5(GEAudioEventV5 event);
GEStatusV1 ge_audio_validate_pcm_block_v5(GEAudioPCMBlockV5 block);
GEStatusV1 ge_audio_validate_snapshot_v5(GEAudioSnapshotV5 snapshot);

#if defined(__cplusplus)
#define GE_AUDIO_V5_STATIC_ASSERT(condition, message) static_assert((condition), message)
#else
#define GE_AUDIO_V5_STATIC_ASSERT(condition, message) _Static_assert((condition), message)
#endif

GE_AUDIO_V5_STATIC_ASSERT(sizeof(GEAudioAssetV5) == 104u, "GEAudioAssetV5 layout drift");
GE_AUDIO_V5_STATIC_ASSERT(sizeof(GEAudioEventV5) == 56u, "GEAudioEventV5 layout drift");
GE_AUDIO_V5_STATIC_ASSERT(sizeof(GEAudioPCMBlockV5) == 64u, "GEAudioPCMBlockV5 layout drift");
GE_AUDIO_V5_STATIC_ASSERT(sizeof(GEAudioSnapshotV5) == 88u, "GEAudioSnapshotV5 layout drift");
GE_AUDIO_V5_STATIC_ASSERT(sizeof(GEAudioClockV5) == 40u, "GEAudioClockV5 layout drift");

#undef GE_AUDIO_V5_STATIC_ASSERT

#endif /* GE_AUDIO_V5_H */
