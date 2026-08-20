#ifndef GE_AUDIO_ENGINE_V5_H
#define GE_AUDIO_ENGINE_V5_H

/*
 * Bounded native audio implementation for the first GoldenEye title slice.
 *
 * This is a source-derived compact-MIDI and AL bank reader.  It accepts
 * prepared bytes only at call time; no record below stores a ROM address, a
 * host path, a pointer, or a libaudio object.  The caller owns the guarded
 * byte buffers for the duration of each call.
 *
 * The implementation intentionally has explicit limits.  A malformed or
 * unsupported stream returns a diagnostic with its byte offset, track and
 * opcode rather than silently manufacturing audio.  The current renderer is
 * a deterministic native subset: MIDI/tempo/loop/CC/pitch events, the two
 * N64 wave formats used by the prepared banks, fixed voice/envelope handling,
 * and a bounded stereo mixer.  Reverb and composite SFX remain STUB(M13)
 * paths and are reported as such by the diagnostic API.
 */

#include <stdint.h>

#include "ge_audio_v5.h"

#ifdef __cplusplus
extern "C" {
#endif

#define GE_AUDIO_ENGINE_V5_VERSION ((uint32_t)1u)

#define GE_AUDIO_ENGINE_V5_MAX_TRACKS ((uint32_t)16u)
#define GE_AUDIO_ENGINE_V5_MAX_LOOPS_PER_TRACK ((uint32_t)16u)
#define GE_AUDIO_ENGINE_V5_MAX_EVENTS ((uint32_t)65536u)
#define GE_AUDIO_ENGINE_V5_MAX_READ_BYTES ((uint32_t)4096u)
#define GE_AUDIO_ENGINE_V5_MAX_SEQUENCE_BYTES ((uint32_t)(16u * 1024u * 1024u))
#define GE_AUDIO_ENGINE_V5_MAX_CTL_BYTES ((uint32_t)(2u * 1024u * 1024u))
#define GE_AUDIO_ENGINE_V5_MAX_TBL_BYTES ((uint32_t)(8u * 1024u * 1024u))
#define GE_AUDIO_ENGINE_V5_MAX_WAVE_SAMPLES ((uint32_t)65536u)
#define GE_AUDIO_ENGINE_V5_MAX_RENDER_FRAMES ((uint32_t)131072u)
#define GE_AUDIO_ENGINE_V5_MAX_INSTRUMENTS ((uint32_t)128u)
#define GE_AUDIO_ENGINE_V5_MAX_SOUNDS_PER_INSTRUMENT ((uint32_t)512u)

#define GE_AUDIO_ENGINE_V5_SEQUENCE_MNINT_RARE_LOGO ((uint32_t)1u)
#define GE_AUDIO_ENGINE_V5_SEQUENCE_MINTRO_EYE ((uint32_t)2u)
#define GE_AUDIO_ENGINE_V5_SEQUENCE_MFOLDERS ((uint32_t)3u)

#define GE_AUDIO_ENGINE_V5_STUB_FEATURE_REVERB ((uint32_t)1u)
#define GE_AUDIO_ENGINE_V5_STUB_FEATURE_COMPOSITE_SFX ((uint32_t)2u)

#define GE_AUDIO_ENGINE_V5_WAVE_ADPCM ((uint32_t)0u)
#define GE_AUDIO_ENGINE_V5_WAVE_RAW16 ((uint32_t)1u)

#define GE_AUDIO_ENGINE_V5_EVENT_MIDI ((uint32_t)1u)
#define GE_AUDIO_ENGINE_V5_EVENT_TEMPO ((uint32_t)2u)
#define GE_AUDIO_ENGINE_V5_EVENT_TRACK_END ((uint32_t)3u)
#define GE_AUDIO_ENGINE_V5_EVENT_SEQUENCE_END ((uint32_t)4u)
#define GE_AUDIO_ENGINE_V5_EVENT_LOOP_START ((uint32_t)5u)
#define GE_AUDIO_ENGINE_V5_EVENT_LOOP_END ((uint32_t)6u)

#define GE_AUDIO_ENGINE_V5_DIAG_NONE ((uint32_t)0u)
#define GE_AUDIO_ENGINE_V5_DIAG_ARGUMENT ((uint32_t)1u)
#define GE_AUDIO_ENGINE_V5_DIAG_HEADER ((uint32_t)2u)
#define GE_AUDIO_ENGINE_V5_DIAG_OFFSET ((uint32_t)3u)
#define GE_AUDIO_ENGINE_V5_DIAG_TRUNCATED ((uint32_t)4u)
#define GE_AUDIO_ENGINE_V5_DIAG_VARLEN ((uint32_t)5u)
#define GE_AUDIO_ENGINE_V5_DIAG_RUNNING_STATUS ((uint32_t)6u)
#define GE_AUDIO_ENGINE_V5_DIAG_META ((uint32_t)7u)
#define GE_AUDIO_ENGINE_V5_DIAG_BLOCK ((uint32_t)8u)
#define GE_AUDIO_ENGINE_V5_DIAG_LOOP ((uint32_t)9u)
#define GE_AUDIO_ENGINE_V5_DIAG_EVENT_BUDGET ((uint32_t)10u)
#define GE_AUDIO_ENGINE_V5_DIAG_BANK ((uint32_t)11u)
#define GE_AUDIO_ENGINE_V5_DIAG_WAVE ((uint32_t)12u)
#define GE_AUDIO_ENGINE_V5_DIAG_BOOK ((uint32_t)13u)
#define GE_AUDIO_ENGINE_V5_DIAG_UNSUPPORTED ((uint32_t)14u)
#define GE_AUDIO_ENGINE_V5_DIAG_CAPACITY ((uint32_t)15u)

#define GE_AUDIO_ENGINE_V5_DIAG_FLAG_STUB_M13 ((uint32_t)1u << 0)
#define GE_AUDIO_ENGINE_V5_DIAG_FLAG_RECOVERABLE ((uint32_t)1u << 1)
#define GE_AUDIO_ENGINE_V5_DIAG_FLAG_MASK ((uint32_t)0x03u)

typedef struct GEAudioDiagnosticV5 {
    uint32_t version;
    uint32_t code;
    uint32_t flags;
    uint32_t track;
    uint32_t byte_offset;
    uint32_t opcode;
    uint32_t detail0;
    uint32_t detail1;
    char message[96];
} GEAudioDiagnosticV5;

typedef struct GECSeqInfoV5 {
    uint32_t version;
    uint32_t byte_count;
    uint32_t division;
    uint32_t valid_track_mask;
    uint32_t track_count;
    uint32_t first_data_offset;
    uint32_t reserved0;
    uint32_t reserved1;
} GECSeqInfoV5;

/* This state is intentionally made entirely from fixed-width values. */
typedef struct GECSeqLoopStateV5 {
    uint32_t event_offset;
    uint32_t jump_offset;
    uint8_t loop_count;
    uint8_t current_count;
    uint8_t initialized;
    uint8_t reserved0;
} GECSeqLoopStateV5;

typedef struct GECSeqStateV5 {
    uint32_t version;
    uint32_t byte_count;
    uint32_t division;
    uint32_t valid_track_mask;
    uint32_t last_ticks;
    uint32_t last_delta_ticks;
    uint32_t delta_flag;
    uint32_t event_count;
    uint32_t current_track;
    uint32_t current_byte_offset;
    uint32_t cur_loc[GE_AUDIO_ENGINE_V5_MAX_TRACKS];
    uint32_t backup_loc[GE_AUDIO_ENGINE_V5_MAX_TRACKS];
    uint32_t evt_delta_ticks[GE_AUDIO_ENGINE_V5_MAX_TRACKS];
    uint8_t backup_len[GE_AUDIO_ENGINE_V5_MAX_TRACKS];
    uint8_t last_status[GE_AUDIO_ENGINE_V5_MAX_TRACKS];
    uint8_t reserved0[2];
    GECSeqLoopStateV5 loops[GE_AUDIO_ENGINE_V5_MAX_TRACKS]
        [GE_AUDIO_ENGINE_V5_MAX_LOOPS_PER_TRACK];
} GECSeqStateV5;

typedef struct GECSeqEventV5 {
    uint32_t version;
    uint32_t event_kind;
    uint32_t track;
    uint32_t byte_offset;
    uint32_t delta_ticks;
    uint32_t absolute_ticks;
    uint32_t duration_ticks;
    uint32_t tempo_microseconds;
    uint32_t loop_count;
    uint32_t loop_current;
    uint32_t loop_jump_offset;
    uint8_t status;
    uint8_t data1;
    uint8_t data2;
    uint8_t meta_type;
    uint32_t reserved0;
    uint32_t reserved1;
} GECSeqEventV5;

typedef struct GEAudioSchedulerV5 {
    uint32_t version;
    uint32_t sequence_active;
    uint32_t division;
    uint32_t tempo_microseconds;
    uint32_t event_count;
    uint32_t source_tick;
    uint32_t reserved0;
    uint64_t sample_cursor;
    uint64_t sample_remainder;
    GECSeqStateV5 sequence;
} GEAudioSchedulerV5;

typedef struct GEAudioWaveV5 {
    uint32_t version;
    uint32_t type;
    uint32_t table_offset;
    uint32_t byte_length;
    uint32_t sample_count;
    uint32_t loop_start;
    uint32_t loop_end;
    uint32_t loop_count;
    uint32_t book_offset;
    uint32_t book_order;
    uint32_t book_predictors;
    uint32_t envelope_offset;
    uint32_t keymap_offset;
    uint32_t key_base;
    uint32_t sample_pan;
    uint32_t sample_volume;
    int32_t detune_cents;
    uint32_t reserved0;
    uint32_t reserved1;
} GEAudioWaveV5;

typedef struct GEAudioBankV5 {
    uint32_t version;
    uint32_t ctl_byte_count;
    uint32_t tbl_byte_count;
    uint32_t bank_offset;
    uint32_t instrument_count;
    uint32_t sample_rate;
    uint32_t percussion_offset;
    uint32_t reserved0;
    uint32_t reserved1;
} GEAudioBankV5;

typedef struct GEAudioVoiceV5 {
    uint32_t active;
    uint32_t channel;
    uint32_t program;
    uint32_t note;
    uint32_t velocity;
    uint32_t sample_count;
    uint32_t sample_position_q16;
    uint32_t sample_step_q16;
    uint32_t loop_start;
    uint32_t loop_end;
    uint32_t loop_count;
    uint32_t age;
    uint32_t release_requested;
    uint32_t attack_frames;
    uint32_t decay_frames;
    uint32_t release_frames;
    uint32_t lifetime_frames;
    uint32_t release_frame;
    int32_t gain_q16;
    int32_t pan_q16;
    int32_t attack_gain_q16;
    int32_t sustain_gain_q16;
    uint32_t source_wave_index;
    int16_t samples[GE_AUDIO_ENGINE_V5_MAX_WAVE_SAMPLES];
} GEAudioVoiceV5;

typedef struct GEAudioSynthV5 {
    uint32_t version;
    uint32_t sample_rate;
    uint32_t active_voice_count;
    uint32_t rendered_frames;
    uint32_t dropped_voice_count;
    uint32_t unsupported_count;
    uint64_t pcm_hash;
    uint64_t event_hash;
    uint32_t channel_program[16];
    uint8_t channel_volume[16];
    uint8_t channel_pan[16];
    uint8_t channel_sustain[16];
    uint16_t channel_pitch_bend[16];
    GEAudioVoiceV5 voices[GE_AUDIO_V5_MAX_VOICES];
} GEAudioSynthV5;

typedef struct GEAudioRenderResultV5 {
    uint32_t version;
    uint32_t frames_requested;
    uint32_t frames_rendered;
    uint32_t event_count;
    uint32_t active_voice_count;
    uint32_t diagnostic_code;
    uint32_t diagnostic_flags;
    uint64_t first_sample_index;
    uint64_t sample_cursor;
    uint64_t event_hash;
    uint64_t pcm_hash;
    uint32_t reserved0;
    uint32_t reserved1;
    uint32_t reserved2;
} GEAudioRenderResultV5;

/* Compact sequence validation and event iteration. */
GEStatusV1 ge_cseq_validate_v5(const uint8_t *bytes,
                               uint32_t byte_count,
                               GECSeqInfoV5 *info,
                               GEAudioDiagnosticV5 *diagnostic);
GEStatusV1 ge_cseq_state_init_v5(const uint8_t *bytes,
                                 uint32_t byte_count,
                                 GECSeqStateV5 *state,
                                 GEAudioDiagnosticV5 *diagnostic);
GEStatusV1 ge_cseq_next_event_v5(const uint8_t *bytes,
                                uint32_t byte_count,
                                GECSeqStateV5 *state,
                                GECSeqEventV5 *event,
                                GEAudioDiagnosticV5 *diagnostic);

/* Source-rate scheduler: tempo is microseconds per quarter note. */
GEStatusV1 ge_audio_scheduler_init_v5(const uint8_t *bytes,
                                      uint32_t byte_count,
                                      GEAudioSchedulerV5 *scheduler,
                                      GEAudioDiagnosticV5 *diagnostic);
GEStatusV1 ge_audio_scheduler_next_event_v5(const uint8_t *bytes,
                                            uint32_t byte_count,
                                            GEAudioSchedulerV5 *scheduler,
                                            GECSeqEventV5 *event,
                                            uint64_t *sample_index,
                                            GEAudioDiagnosticV5 *diagnostic);

/* N64 AL bank reader and bounded waveform decoder. */
GEStatusV1 ge_audio_bank_init_v5(const uint8_t *ctl_bytes,
                                 uint32_t ctl_byte_count,
                                 const uint8_t *tbl_bytes,
                                 uint32_t tbl_byte_count,
                                 GEAudioBankV5 *bank,
                                 GEAudioDiagnosticV5 *diagnostic);
GEStatusV1 ge_audio_bank_lookup_v5(const uint8_t *ctl_bytes,
                                   uint32_t ctl_byte_count,
                                   const GEAudioBankV5 *bank,
                                   uint32_t program,
                                   uint32_t key,
                                   uint32_t velocity,
                                   GEAudioWaveV5 *wave,
                                   GEAudioDiagnosticV5 *diagnostic);
GEStatusV1 ge_audio_bank_lookup_sfx_v5(const uint8_t *ctl_bytes,
                                       uint32_t ctl_byte_count,
                                       const GEAudioBankV5 *bank,
                                       uint32_t sound_index,
                                       GEAudioWaveV5 *wave,
                                       GEAudioDiagnosticV5 *diagnostic);
GEStatusV1 ge_audio_decode_wave_v5(const uint8_t *ctl_bytes,
                                   uint32_t ctl_byte_count,
                                   const uint8_t *tbl_bytes,
                                   uint32_t tbl_byte_count,
                                   const GEAudioWaveV5 *wave,
                                   int16_t *samples,
                                   uint32_t sample_capacity,
                                   uint32_t *sample_count,
                                   GEAudioDiagnosticV5 *diagnostic);

/* Explicitly report bounded features that remain deferred to M13. */
GEStatusV1 ge_audio_feature_status_v5(uint32_t feature,
                                      GEAudioDiagnosticV5 *diagnostic);

/* Deterministic native stereo renderer for one bounded compact sequence. */
void ge_audio_synth_init_v5(GEAudioSynthV5 *synth, uint32_t sample_rate);
GEStatusV1 ge_audio_render_sequence_v5(
    const uint8_t *sequence_bytes,
    uint32_t sequence_byte_count,
    const uint8_t *ctl_bytes,
    uint32_t ctl_byte_count,
    const uint8_t *tbl_bytes,
    uint32_t tbl_byte_count,
    uint32_t frame_count,
    int16_t *stereo_samples,
    uint32_t stereo_sample_capacity,
    GEAudioRenderResultV5 *result,
    GEAudioDiagnosticV5 *diagnostic);

GEStatusV1 ge_audio_render_sfx_v5(
    const uint8_t *ctl_bytes,
    uint32_t ctl_byte_count,
    const uint8_t *tbl_bytes,
    uint32_t tbl_byte_count,
    uint32_t sound_index,
    uint32_t frame_count,
    int16_t *stereo_samples,
    uint32_t stereo_sample_capacity,
    GEAudioRenderResultV5 *result,
    GEAudioDiagnosticV5 *diagnostic);

/* Fixed source-rate helper shared by the host's 120 Hz owner loop. */
uint64_t ge_audio_engine_sample_index_v5(uint64_t native_tick);
uint32_t ge_audio_engine_frame_count_v5(uint64_t native_tick);

#if defined(__cplusplus)
#define GE_AUDIO_ENGINE_V5_STATIC_ASSERT(condition, message) static_assert((condition), message)
#else
#define GE_AUDIO_ENGINE_V5_STATIC_ASSERT(condition, message) _Static_assert((condition), message)
#endif

GE_AUDIO_ENGINE_V5_STATIC_ASSERT(sizeof(GEAudioDiagnosticV5) == 128u,
                                 "GEAudioDiagnosticV5 layout drift");
GE_AUDIO_ENGINE_V5_STATIC_ASSERT(sizeof(GECSeqInfoV5) == 32u,
                                 "GECSeqInfoV5 layout drift");
GE_AUDIO_ENGINE_V5_STATIC_ASSERT(sizeof(GECSeqEventV5) == 56u,
                                 "GECSeqEventV5 layout drift");
GE_AUDIO_ENGINE_V5_STATIC_ASSERT(sizeof(GEAudioWaveV5) == 76u,
                                 "GEAudioWaveV5 layout drift");
GE_AUDIO_ENGINE_V5_STATIC_ASSERT(sizeof(GEAudioBankV5) == 36u,
                                 "GEAudioBankV5 layout drift");
GE_AUDIO_ENGINE_V5_STATIC_ASSERT(sizeof(GEAudioRenderResultV5) == 80u,
                                 "GEAudioRenderResultV5 layout drift");

#undef GE_AUDIO_ENGINE_V5_STATIC_ASSERT

#ifdef __cplusplus
}
#endif

#endif /* GE_AUDIO_ENGINE_V5_H */
