#ifndef GE_AUDIO_EFFECTS_V6_H
#define GE_AUDIO_EFFECTS_V6_H

/*
 * Additive native audio effects for the V5 fixed C synth.
 *
 * The V5 sequence/SFX renderer and its boot PCM vectors are deliberately
 * unchanged.  This sidecar is the versioned M13 effects boundary: callers
 * render V5 PCM first, then explicitly opt into the source-shaped reverb bus
 * or the bounded composite SFX graph.  All records are fixed-width and
 * pointer-free.  PCM and decoded-bank storage are supplied to call-time
 * functions by the owner thread; no realtime callback enters these APIs.
 *
 * The reverb defaults are derived from libultra's SMALLROOM parameters in
 * src/libultrare/audio/drvrNew.c.  They are a deterministic fixed-point
 * lowering of that source bus, not a claim of cycle-exact N64 audio DSP.
 */

#include <stdint.h>

#include "ge_audio_engine_v5.h"

#ifdef __cplusplus
extern "C" {
#endif

#define GE_AUDIO_EFFECTS_V6_CONTRACT_VERSION ((uint32_t)6u)
#define GE_AUDIO_EFFECTS_V6_RECORD_VERSION ((uint32_t)1u)

#define GE_AUDIO_EFFECTS_V6_SAMPLE_RATE GE_AUDIO_V5_SAMPLE_RATE
#define GE_AUDIO_EFFECTS_V6_MAX_REVERB_SECTIONS ((uint32_t)4u)
#define GE_AUDIO_EFFECTS_V6_MAX_REVERB_DELAY_FRAMES ((uint32_t)8192u)
#define GE_AUDIO_EFFECTS_V6_MAX_RENDER_FRAMES GE_AUDIO_ENGINE_V5_MAX_RENDER_FRAMES
#define GE_AUDIO_EFFECTS_V6_MAX_GRAPH_EVENTS ((uint32_t)32u)
#define GE_AUDIO_EFFECTS_V6_MAX_GRAPH_SOURCES ((uint32_t)32u)

#define GE_AUDIO_EFFECTS_V6_REVERB_PRESET_SMALL_ROOM ((uint32_t)1u)
#define GE_AUDIO_EFFECTS_V6_REVERB_PRESET_BIG_ROOM ((uint32_t)2u)

#define GE_AUDIO_EFFECTS_V6_RESULT_FLAG_NONZERO ((uint32_t)1u << 0)
#define GE_AUDIO_EFFECTS_V6_RESULT_FLAG_REVERB_TAIL ((uint32_t)1u << 1)
#define GE_AUDIO_EFFECTS_V6_RESULT_FLAG_MASK ((uint32_t)0x03u)

#define GE_AUDIO_EFFECTS_V6_SOURCE_FLAG_NONE ((uint32_t)0u)
#define GE_AUDIO_EFFECTS_V6_SOURCE_FLAG_ADPCM ((uint32_t)1u << 0)
#define GE_AUDIO_EFFECTS_V6_SOURCE_FLAG_RAW16 ((uint32_t)1u << 1)
#define GE_AUDIO_EFFECTS_V6_SOURCE_FLAG_MASK ((uint32_t)0x03u)

#define GE_AUDIO_EFFECTS_V6_EVENT_FLAG_NONE ((uint32_t)0u)
#define GE_AUDIO_EFFECTS_V6_EVENT_FLAG_LOOP ((uint32_t)1u << 0)
#define GE_AUDIO_EFFECTS_V6_EVENT_FLAG_RETRIGGER ((uint32_t)1u << 1)
#define GE_AUDIO_EFFECTS_V6_EVENT_FLAG_MASK ((uint32_t)0x03u)

#define GE_AUDIO_EFFECTS_V6_FEATURE_REVERB ((uint32_t)1u)
#define GE_AUDIO_EFFECTS_V6_FEATURE_COMPOSITE_SFX ((uint32_t)2u)

typedef struct GEAudioReverbConfigV6 {
    GEAbiHeaderV1 header;
    uint32_t contract_version;
    uint32_t record_version;
    uint32_t sample_rate;
    uint32_t flags;
    uint32_t section_count;
    uint32_t input_delay_frames[GE_AUDIO_EFFECTS_V6_MAX_REVERB_SECTIONS];
    uint32_t output_delay_frames[GE_AUDIO_EFFECTS_V6_MAX_REVERB_SECTIONS];
    int32_t feedback_q15[GE_AUDIO_EFFECTS_V6_MAX_REVERB_SECTIONS];
    int32_t feedforward_q15[GE_AUDIO_EFFECTS_V6_MAX_REVERB_SECTIONS];
    int32_t gain_q15[GE_AUDIO_EFFECTS_V6_MAX_REVERB_SECTIONS];
    uint32_t damping_q15;
    uint32_t wet_q15;
    uint32_t dry_q15;
    uint32_t crossfeed_q15;
    uint32_t reserved0;
} GEAudioReverbConfigV6;

typedef struct GEAudioReverbBusV6 {
    GEAbiHeaderV1 header;
    uint32_t contract_version;
    uint32_t record_version;
    GEAudioReverbConfigV6 config;
    uint32_t write_index;
    uint32_t reserved0;
    uint64_t frame_cursor;
    uint64_t input_hash;
    uint64_t output_hash;
    int32_t damping_state_l[GE_AUDIO_EFFECTS_V6_MAX_REVERB_SECTIONS];
    int32_t damping_state_r[GE_AUDIO_EFFECTS_V6_MAX_REVERB_SECTIONS];
    int16_t delay_l[GE_AUDIO_EFFECTS_V6_MAX_REVERB_SECTIONS]
                   [GE_AUDIO_EFFECTS_V6_MAX_REVERB_DELAY_FRAMES];
    int16_t delay_r[GE_AUDIO_EFFECTS_V6_MAX_REVERB_SECTIONS]
                   [GE_AUDIO_EFFECTS_V6_MAX_REVERB_DELAY_FRAMES];
} GEAudioReverbBusV6;

typedef struct GEAudioReverbResultV6 {
    GEAbiHeaderV1 header;
    uint32_t contract_version;
    uint32_t record_version;
    uint32_t frames_requested;
    uint32_t frames_processed;
    uint64_t first_frame;
    uint64_t input_hash;
    uint64_t output_hash;
    uint32_t peak_abs;
    uint32_t flags;
    uint32_t reserved0;
    uint32_t reserved1;
} GEAudioReverbResultV6;

/* `sample_offset` is measured in mono s16 samples in the call-time arena. */
typedef struct GEAudioSfxSourceV6 {
    GEAbiHeaderV1 header;
    uint32_t contract_version;
    uint32_t record_version;
    uint32_t source_index;
    uint32_t sound_index;
    uint32_t flags;
    uint32_t sample_offset;
    uint32_t sample_count;
    uint32_t loop_start;
    uint32_t loop_end;
    uint32_t loop_count;
    uint32_t sample_rate;
    uint32_t volume_q15;
    uint32_t pan_q15;
    uint32_t reserved0;
} GEAudioSfxSourceV6;

typedef struct GEAudioSfxEventV6 {
    GEAbiHeaderV1 header;
    uint32_t contract_version;
    uint32_t record_version;
    uint32_t event_id;
    uint32_t source_index;
    uint32_t flags;
    uint32_t start_frame;
    uint32_t duration_frames;
    uint32_t gain_q15;
    uint32_t pan_q15;
    uint32_t step_q16;
    uint32_t attack_frames;
    uint32_t release_frames;
    uint32_t reserved0;
    uint32_t reserved1;
} GEAudioSfxEventV6;

typedef struct GEAudioSfxGraphV6 {
    GEAbiHeaderV1 header;
    uint32_t contract_version;
    uint32_t record_version;
    uint32_t sample_rate;
    uint32_t flags;
    uint32_t event_count;
    uint32_t source_count;
    uint32_t reserved0;
    GEAudioSfxEventV6 events[GE_AUDIO_EFFECTS_V6_MAX_GRAPH_EVENTS];
} GEAudioSfxGraphV6;

typedef struct GEAudioSfxGraphResultV6 {
    GEAbiHeaderV1 header;
    uint32_t contract_version;
    uint32_t record_version;
    uint32_t frames_requested;
    uint32_t frames_rendered;
    uint32_t event_count;
    uint32_t active_voice_count;
    uint32_t dropped_event_count;
    uint32_t flags;
    uint64_t event_hash;
    uint64_t pcm_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GEAudioSfxGraphResultV6;

/* Reverb configuration/state.  All mutating calls are owner-side. */
GEStatusV1 ge_audio_reverb_config_for_preset_v6(
    uint32_t preset,
    uint32_t sample_rate,
    GEAudioReverbConfigV6 *config,
    GEAudioDiagnosticV5 *diagnostic);
GEStatusV1 ge_audio_reverb_bus_init_v6(
    GEAudioReverbBusV6 *bus,
    const GEAudioReverbConfigV6 *config,
    GEAudioDiagnosticV5 *diagnostic);
GEStatusV1 ge_audio_reverb_bus_reset_v6(
    GEAudioReverbBusV6 *bus,
    GEAudioDiagnosticV5 *diagnostic);
GEStatusV1 ge_audio_reverb_bus_process_v6(
    GEAudioReverbBusV6 *bus,
    const int16_t *stereo_input,
    uint32_t frame_count,
    int16_t *stereo_output,
    uint32_t stereo_sample_capacity,
    GEAudioReverbResultV6 *result,
    GEAudioDiagnosticV5 *diagnostic);

/* Composite SFX graph.  The graph/source records are immutable during render. */
void ge_audio_sfx_graph_init_v6(GEAudioSfxGraphV6 *graph, uint32_t sample_rate);
void ge_audio_sfx_source_init_v6(GEAudioSfxSourceV6 *source,
                                 uint32_t source_index,
                                 uint32_t sound_index);
void ge_audio_sfx_event_init_v6(GEAudioSfxEventV6 *event,
                                uint32_t event_id,
                                uint32_t source_index);
GEStatusV1 ge_audio_sfx_graph_append_event_v6(
    GEAudioSfxGraphV6 *graph,
    GEAudioSfxEventV6 event,
    GEAudioDiagnosticV5 *diagnostic);
GEStatusV1 ge_audio_sfx_graph_validate_v6(
    const GEAudioSfxGraphV6 *graph,
    const GEAudioSfxSourceV6 *sources,
    uint32_t source_count,
    uint32_t arena_sample_count,
    GEAudioDiagnosticV5 *diagnostic);
GEStatusV1 ge_audio_sfx_graph_render_v6(
    const GEAudioSfxGraphV6 *graph,
    const GEAudioSfxSourceV6 *sources,
    uint32_t source_count,
    const int16_t *mono_sample_arena,
    uint32_t arena_sample_count,
    uint32_t frame_count,
    int16_t *stereo_samples,
    uint32_t stereo_sample_capacity,
    GEAudioSfxGraphResultV6 *result,
    GEAudioDiagnosticV5 *diagnostic);

/* Owner-side convenience path that decodes the graph's Rareware SFX IDs from
   the existing V5 AL bank contract into caller-provided storage, then lowers
   the immutable graph.  It never allocates and is not a realtime callback API. */
GEStatusV1 ge_audio_sfx_graph_render_bank_v6(
    const GEAudioSfxGraphV6 *graph,
    const GEAudioSfxSourceV6 *sources,
    uint32_t source_count,
    const uint8_t *ctl_bytes,
    uint32_t ctl_byte_count,
    const uint8_t *tbl_bytes,
    uint32_t tbl_byte_count,
    int16_t *decode_arena,
    uint32_t decode_arena_capacity,
    uint32_t frame_count,
    int16_t *stereo_samples,
    uint32_t stereo_sample_capacity,
    GEAudioSfxGraphResultV6 *result,
    GEAudioDiagnosticV5 *diagnostic);

GEStatusV1 ge_audio_effects_feature_status_v6(uint32_t feature,
                                             GEAudioDiagnosticV5 *diagnostic);

#if defined(__cplusplus)
#define GE_AUDIO_EFFECTS_V6_STATIC_ASSERT(condition, message) static_assert((condition), message)
#else
#define GE_AUDIO_EFFECTS_V6_STATIC_ASSERT(condition, message) _Static_assert((condition), message)
#endif

GE_AUDIO_EFFECTS_V6_STATIC_ASSERT(sizeof(GEAudioReverbConfigV6) == 128u,
                                  "GEAudioReverbConfigV6 layout drift");
GE_AUDIO_EFFECTS_V6_STATIC_ASSERT(sizeof(GEAudioReverbResultV6) == 64u,
                                  "GEAudioReverbResultV6 layout drift");
GE_AUDIO_EFFECTS_V6_STATIC_ASSERT(sizeof(GEAudioSfxSourceV6) == 64u,
                                  "GEAudioSfxSourceV6 layout drift");
GE_AUDIO_EFFECTS_V6_STATIC_ASSERT(sizeof(GEAudioSfxEventV6) == 64u,
                                  "GEAudioSfxEventV6 layout drift");
GE_AUDIO_EFFECTS_V6_STATIC_ASSERT(sizeof(GEAudioSfxGraphResultV6) == 64u,
                                  "GEAudioSfxGraphResultV6 layout drift");

#undef GE_AUDIO_EFFECTS_V6_STATIC_ASSERT

#ifdef __cplusplus
}
#endif

#endif /* GE_AUDIO_EFFECTS_V6_H */
