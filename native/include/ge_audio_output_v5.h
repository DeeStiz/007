#ifndef GE_AUDIO_OUTPUT_V5_H
#define GE_AUDIO_OUTPUT_V5_H

/*
 * Realtime output sidecar for the bounded native audio renderer.
 *
 * The producer is the owner thread and the consumer is the Core Audio render
 * callback.  The ring is a fixed-size, single-producer/single-consumer queue
 * of interleaved signed 16-bit stereo frames.  It uses C11 atomics only: no
 * mutex, allocation, logging, Objective-C message, Swift call, or diagnostic
 * formatting is performed by the callback path.
 *
 * The Objective-C AVAudioSourceNode adapter is implemented separately in
 * ge_audio_source_node_v5.m and uses the C functions below.  This header is
 * C-only so the ring can be unit-tested and used by the native owner without
 * importing AVFAudio into the C target.
 */

#include <stdatomic.h>
#include <stdint.h>

#include "ge_audio_engine_v5.h"

#ifdef __cplusplus
extern "C" {
#endif

#if !defined(__cplusplus)
_Static_assert(ATOMIC_INT_LOCK_FREE == 2,
               "GEAudioPCMSourceV5 requires lock-free 32-bit atomics");
_Static_assert(ATOMIC_LLONG_LOCK_FREE == 2,
               "GEAudioPCMSourceV5 requires lock-free 64-bit atomics");
#endif

#define GE_AUDIO_OUTPUT_V5_VERSION ((uint32_t)1u)
#define GE_AUDIO_OUTPUT_V5_CHANNELS ((uint32_t)2u)
#define GE_AUDIO_OUTPUT_V5_SAMPLE_RATE ((uint32_t)22050u)
#define GE_AUDIO_OUTPUT_V5_RING_CAPACITY_FRAMES ((uint32_t)8192u)
#define GE_AUDIO_OUTPUT_V5_RING_MASK \
    (GE_AUDIO_OUTPUT_V5_RING_CAPACITY_FRAMES - (uint32_t)1u)
#define GE_AUDIO_OUTPUT_V5_DEFAULT_PREROLL_FRAMES ((uint32_t)2048u)
#define GE_AUDIO_OUTPUT_V5_DEFAULT_TARGET_FILL_FRAMES ((uint32_t)4096u)

#define GE_AUDIO_OUTPUT_V5_FLAG_NONE ((uint32_t)0u)
#define GE_AUDIO_OUTPUT_V5_FLAG_PREROLL_REQUIRED ((uint32_t)1u << 0)
#define GE_AUDIO_OUTPUT_V5_FLAG_PREROLL_READY ((uint32_t)1u << 1)
#define GE_AUDIO_OUTPUT_V5_FLAG_RUNNING ((uint32_t)1u << 2)
#define GE_AUDIO_OUTPUT_V5_FLAG_ROUTE_RECOVERING ((uint32_t)1u << 3)
#define GE_AUDIO_OUTPUT_V5_FLAG_CALLBACK_ERROR ((uint32_t)1u << 4)
#define GE_AUDIO_OUTPUT_V5_FLAG_MASK ((uint32_t)0x1fu)

typedef struct GEAudioPCMSourceSnapshotV5 {
    uint32_t version;
    uint32_t flags;
    uint32_t sample_rate;
    uint32_t channel_count;
    uint32_t capacity_frames;
    uint32_t available_frames;
    uint32_t preroll_target_frames;
    uint32_t target_fill_frames;
    uint32_t route_generation;
    uint32_t underrun_count;
    uint32_t dropped_frame_count;
    uint32_t callback_error;
    uint64_t producer_native_tick;
    uint64_t producer_sample_cursor;
    uint64_t consumer_sample_cursor;
} GEAudioPCMSourceSnapshotV5;

/* Owner-side state.  It contains no host pointer, path, SDK object, or ROM
   address.  The ring storage is embedded so initialization is deterministic
   and the realtime callback never allocates. */
typedef struct GEAudioPCMSourceV5 {
    uint32_t version;
    uint32_t sample_rate;
    uint32_t channel_count;
    uint32_t capacity_frames;
    _Atomic uint32_t read_index;
    _Atomic uint32_t write_index;
    _Atomic uint32_t flags;
    _Atomic uint32_t route_generation;
    _Atomic uint32_t underrun_count;
    _Atomic uint32_t dropped_frame_count;
    _Atomic uint32_t callback_error;
    uint32_t preroll_target_frames;
    uint32_t target_fill_frames;
    _Atomic(uint64_t) producer_native_tick;
    _Atomic(uint64_t) producer_sample_cursor;
    _Atomic(uint64_t) consumer_sample_cursor;
    int16_t samples[GE_AUDIO_OUTPUT_V5_RING_CAPACITY_FRAMES *
                    GE_AUDIO_OUTPUT_V5_CHANNELS];
} GEAudioPCMSourceV5;

typedef struct GEAudioPCMRefillResultV5 {
    uint32_t version;
    uint32_t native_tick_frame_count;
    uint32_t requested_frame_count;
    uint32_t written_frame_count;
    uint32_t available_frame_count;
    uint32_t flags;
    uint32_t route_generation;
    uint32_t underrun_count;
    uint32_t dropped_frame_count;
    uint64_t first_sample_index;
    uint64_t producer_sample_cursor;
    uint32_t reserved0;
    uint32_t reserved1;
} GEAudioPCMRefillResultV5;

typedef struct GEAudioPCMReadResultV5 {
    uint32_t version;
    uint32_t requested_frame_count;
    uint32_t consumed_frame_count;
    uint32_t zero_filled_frame_count;
    uint32_t available_frame_count;
    uint32_t flags;
    uint32_t route_generation;
    uint32_t underrun_count;
    uint32_t callback_error;
    uint64_t first_sample_index;
    uint64_t consumer_sample_cursor;
    uint32_t reserved0;
    uint32_t reserved1;
} GEAudioPCMReadResultV5;

GEStatusV1 ge_audio_pcm_source_init_v5(
    GEAudioPCMSourceV5 *source,
    uint32_t preroll_target_frames,
    uint32_t target_fill_frames);

GEStatusV1 ge_audio_pcm_source_begin_route_recovery_v5(
    GEAudioPCMSourceV5 *source,
    uint32_t sample_rate,
    uint32_t channel_count,
    uint32_t route_generation);

GEStatusV1 ge_audio_pcm_source_mark_running_v5(GEAudioPCMSourceV5 *source);

/* Exact native clock conversion.  The expected sequence is 183,184,184,184. */
uint32_t ge_audio_pcm_source_frame_count_for_tick_v5(uint64_t native_tick);
uint64_t ge_audio_pcm_source_sample_index_for_tick_v5(uint64_t native_tick);

/* Refill validates the native tick's exact source frame count and sample
   index before writing.  It is producer/owner-thread only. */
GEStatusV1 ge_audio_pcm_source_refill_tick_v5(
    GEAudioPCMSourceV5 *source,
    uint64_t native_tick,
    uint64_t first_sample_index,
    const int16_t *stereo_samples,
    uint32_t frame_count,
    GEAudioPCMRefillResultV5 *result,
    GEAudioDiagnosticV5 *diagnostic);

/* Realtime consumer functions.  The frame form is used by the AVAudioSource
   node callback so it can write directly into Core Audio's supplied buffers. */
uint32_t ge_audio_pcm_source_read_frame_v5(
    GEAudioPCMSourceV5 *source,
    int16_t *left,
    int16_t *right);

GEStatusV1 ge_audio_pcm_source_read_s16_v5(
    GEAudioPCMSourceV5 *source,
    int16_t *stereo_samples,
    uint32_t frame_count,
    GEAudioPCMReadResultV5 *result);

void ge_audio_pcm_source_snapshot_v5(
    const GEAudioPCMSourceV5 *source,
    GEAudioPCMSourceSnapshotV5 *snapshot);

/* This function is deliberately callback-safe and writes only an atomic error
   code.  The Objective-C adapter calls it when an unexpected Core Audio
   buffer layout is supplied. */
void ge_audio_pcm_source_note_callback_error_v5(
    GEAudioPCMSourceV5 *source,
    uint32_t error_code);

#if defined(__cplusplus)
#define GE_AUDIO_OUTPUT_V5_STATIC_ASSERT(condition, message) static_assert((condition), message)
#else
#define GE_AUDIO_OUTPUT_V5_STATIC_ASSERT(condition, message) _Static_assert((condition), message)
#endif

GE_AUDIO_OUTPUT_V5_STATIC_ASSERT(
    GE_AUDIO_OUTPUT_V5_RING_CAPACITY_FRAMES > 0u &&
        (GE_AUDIO_OUTPUT_V5_RING_CAPACITY_FRAMES & GE_AUDIO_OUTPUT_V5_RING_MASK) == 0u,
    "GEAudioPCMSourceV5 ring capacity must be a power of two");
GE_AUDIO_OUTPUT_V5_STATIC_ASSERT(sizeof(GEAudioPCMSourceSnapshotV5) == 72u,
                                 "GEAudioPCMSourceSnapshotV5 layout drift");
GE_AUDIO_OUTPUT_V5_STATIC_ASSERT(sizeof(GEAudioPCMRefillResultV5) == 64u,
                                 "GEAudioPCMRefillResultV5 layout drift");
GE_AUDIO_OUTPUT_V5_STATIC_ASSERT(sizeof(GEAudioPCMReadResultV5) == 64u,
                                 "GEAudioPCMReadResultV5 layout drift");

#undef GE_AUDIO_OUTPUT_V5_STATIC_ASSERT

#ifdef __cplusplus
}
#endif

#endif /* GE_AUDIO_OUTPUT_V5_H */
