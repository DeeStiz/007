#include "ge_audio_output_v5.h"

#include <stddef.h>
#include <string.h>

static void ge_audio_output_diagnostic_clear(GEAudioDiagnosticV5 *diagnostic)
{
    if (diagnostic == NULL) {
        return;
    }
    memset(diagnostic, 0, sizeof(*diagnostic));
    diagnostic->version = GE_AUDIO_ENGINE_V5_VERSION;
}

static GEStatusV1 ge_audio_output_diagnostic_set(GEAudioDiagnosticV5 *diagnostic,
                                                 uint32_t code,
                                                 uint32_t flags,
                                                 uint32_t detail0,
                                                 uint32_t detail1,
                                                 const char *message,
                                                 GEStatusV1 status)
{
    ge_audio_output_diagnostic_clear(diagnostic);
    if (diagnostic != NULL) {
        diagnostic->code = code;
        diagnostic->flags = flags;
        diagnostic->detail0 = detail0;
        diagnostic->detail1 = detail1;
        if (message != NULL) {
            size_t index = 0u;
            while (message[index] != '\0' && index + 1u < sizeof(diagnostic->message)) {
                diagnostic->message[index] = message[index];
                index++;
            }
            diagnostic->message[index] = '\0';
        }
    }
    return status;
}

static uint32_t ge_audio_pcm_source_available(const GEAudioPCMSourceV5 *source)
{
    uint32_t read_index = atomic_load_explicit(&source->read_index,
                                               memory_order_acquire);
    uint32_t write_index = atomic_load_explicit(&source->write_index,
                                                memory_order_acquire);
    uint32_t available = write_index - read_index;
    if (available > source->capacity_frames) {
        return source->capacity_frames;
    }
    return available;
}

static uint32_t ge_audio_pcm_source_write_frames(GEAudioPCMSourceV5 *source,
                                                 const int16_t *stereo_samples,
                                                 uint32_t frame_count)
{
    uint32_t read_index = atomic_load_explicit(&source->read_index,
                                               memory_order_acquire);
    uint32_t write_index = atomic_load_explicit(&source->write_index,
                                                memory_order_relaxed);
    uint32_t used = write_index - read_index;
    if (used > source->capacity_frames) {
        used = source->capacity_frames;
    }
    uint32_t free_frames = source->capacity_frames - used;
    uint32_t write_count = frame_count < free_frames ? frame_count : free_frames;
    for (uint32_t frame = 0u; frame < write_count; frame++) {
        uint32_t ring_frame = (write_index + frame) & GE_AUDIO_OUTPUT_V5_RING_MASK;
        source->samples[ring_frame * GE_AUDIO_OUTPUT_V5_CHANNELS] =
            stereo_samples[frame * GE_AUDIO_OUTPUT_V5_CHANNELS];
        source->samples[ring_frame * GE_AUDIO_OUTPUT_V5_CHANNELS + 1u] =
            stereo_samples[frame * GE_AUDIO_OUTPUT_V5_CHANNELS + 1u];
    }
    if (write_count != 0u) {
        atomic_store_explicit(&source->write_index,
                              write_index + write_count,
                              memory_order_release);
    }
    uint32_t dropped = frame_count - write_count;
    if (dropped != 0u) {
        (void)atomic_fetch_add_explicit(&source->dropped_frame_count,
                                        dropped,
                                        memory_order_relaxed);
    }
    return write_count;
}

GEStatusV1 ge_audio_pcm_source_init_v5(
    GEAudioPCMSourceV5 *source,
    uint32_t preroll_target_frames,
    uint32_t target_fill_frames)
{
    if (source == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (preroll_target_frames == 0u) {
        preroll_target_frames = GE_AUDIO_OUTPUT_V5_DEFAULT_PREROLL_FRAMES;
    }
    if (target_fill_frames == 0u) {
        target_fill_frames = GE_AUDIO_OUTPUT_V5_DEFAULT_TARGET_FILL_FRAMES;
    }
    if (preroll_target_frames > GE_AUDIO_OUTPUT_V5_RING_CAPACITY_FRAMES ||
        target_fill_frames > GE_AUDIO_OUTPUT_V5_RING_CAPACITY_FRAMES ||
        target_fill_frames < preroll_target_frames) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    memset(source, 0, sizeof(*source));
    source->version = GE_AUDIO_OUTPUT_V5_VERSION;
    source->sample_rate = GE_AUDIO_OUTPUT_V5_SAMPLE_RATE;
    source->channel_count = GE_AUDIO_OUTPUT_V5_CHANNELS;
    source->capacity_frames = GE_AUDIO_OUTPUT_V5_RING_CAPACITY_FRAMES;
    source->preroll_target_frames = preroll_target_frames;
    source->target_fill_frames = target_fill_frames;
    atomic_init(&source->read_index, 0u);
    atomic_init(&source->write_index, 0u);
    atomic_init(&source->flags, GE_AUDIO_OUTPUT_V5_FLAG_PREROLL_REQUIRED);
    atomic_init(&source->route_generation, 0u);
    atomic_init(&source->underrun_count, 0u);
    atomic_init(&source->dropped_frame_count, 0u);
    atomic_init(&source->callback_error, 0u);
    atomic_init(&source->producer_native_tick, 0u);
    atomic_init(&source->producer_sample_cursor, 0u);
    atomic_init(&source->consumer_sample_cursor, 0u);
    return GE_STATUS_OK;
}

GEStatusV1 ge_audio_pcm_source_begin_route_recovery_v5(
    GEAudioPCMSourceV5 *source,
    uint32_t sample_rate,
    uint32_t channel_count,
    uint32_t route_generation)
{
    if (source == NULL || sample_rate != GE_AUDIO_OUTPUT_V5_SAMPLE_RATE ||
        channel_count != GE_AUDIO_OUTPUT_V5_CHANNELS) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    /* The route owner stops/reconnects the source node before calling this
       function.  Atomic indices make the callback's concurrent observation
       safe while it transitions to silence/preroll. */
    atomic_store_explicit(&source->flags,
                          GE_AUDIO_OUTPUT_V5_FLAG_PREROLL_REQUIRED |
                              GE_AUDIO_OUTPUT_V5_FLAG_ROUTE_RECOVERING,
                          memory_order_release);
    atomic_store_explicit(&source->route_generation,
                          route_generation,
                          memory_order_release);
    atomic_store_explicit(&source->read_index, 0u, memory_order_release);
    atomic_store_explicit(&source->write_index, 0u, memory_order_release);
    atomic_store_explicit(&source->callback_error, 0u, memory_order_release);
    atomic_store_explicit(&source->producer_native_tick, 0u, memory_order_release);
    atomic_store_explicit(&source->producer_sample_cursor, 0u, memory_order_release);
    atomic_store_explicit(&source->consumer_sample_cursor, 0u, memory_order_release);
    return GE_STATUS_OK;
}

GEStatusV1 ge_audio_pcm_source_mark_running_v5(GEAudioPCMSourceV5 *source)
{
    if (source == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    uint32_t flags = atomic_load_explicit(&source->flags, memory_order_acquire);
    if ((flags & GE_AUDIO_OUTPUT_V5_FLAG_PREROLL_READY) == 0u) {
        return GE_STATUS_INVALID_STATE;
    }
    flags &= ~(GE_AUDIO_OUTPUT_V5_FLAG_PREROLL_REQUIRED |
               GE_AUDIO_OUTPUT_V5_FLAG_ROUTE_RECOVERING);
    flags |= GE_AUDIO_OUTPUT_V5_FLAG_RUNNING;
    atomic_store_explicit(&source->flags, flags, memory_order_release);
    return GE_STATUS_OK;
}

uint32_t ge_audio_pcm_source_frame_count_for_tick_v5(uint64_t native_tick)
{
    return ge_audio_frame_count_for_tick_v5(native_tick);
}

uint64_t ge_audio_pcm_source_sample_index_for_tick_v5(uint64_t native_tick)
{
    return ge_audio_sample_index_for_tick_v5(native_tick);
}

GEStatusV1 ge_audio_pcm_source_refill_tick_v5(
    GEAudioPCMSourceV5 *source,
    uint64_t native_tick,
    uint64_t first_sample_index,
    const int16_t *stereo_samples,
    uint32_t frame_count,
    GEAudioPCMRefillResultV5 *result,
    GEAudioDiagnosticV5 *diagnostic)
{
    ge_audio_output_diagnostic_clear(diagnostic);
    if (source == NULL || stereo_samples == NULL || result == NULL ||
        source->version != GE_AUDIO_OUTPUT_V5_VERSION ||
        source->sample_rate != GE_AUDIO_OUTPUT_V5_SAMPLE_RATE ||
        source->channel_count != GE_AUDIO_OUTPUT_V5_CHANNELS) {
        return ge_audio_output_diagnostic_set(diagnostic,
                                              GE_AUDIO_ENGINE_V5_DIAG_ARGUMENT,
                                              0u,
                                              0u,
                                              0u,
                                              "PCM source refill arguments do not describe the fixed 22,050 Hz stereo route",
                                              GE_STATUS_INVALID_ARGUMENT);
    }
    memset(result, 0, sizeof(*result));
    result->version = GE_AUDIO_OUTPUT_V5_VERSION;
    result->native_tick_frame_count = ge_audio_pcm_source_frame_count_for_tick_v5(native_tick);
    result->requested_frame_count = frame_count;
    result->first_sample_index = first_sample_index;
    result->route_generation = atomic_load_explicit(&source->route_generation,
                                                    memory_order_acquire);
    if (frame_count != result->native_tick_frame_count ||
        first_sample_index != ge_audio_pcm_source_sample_index_for_tick_v5(native_tick)) {
        return ge_audio_output_diagnostic_set(diagnostic,
                                              GE_AUDIO_ENGINE_V5_DIAG_ARGUMENT,
                                              GE_AUDIO_ENGINE_V5_DIAG_FLAG_RECOVERABLE,
                                              result->native_tick_frame_count,
                                              frame_count,
                                              "PCM refill does not match the exact 735/4 source clock",
                                              GE_STATUS_INVALID_ARGUMENT);
    }
    uint32_t written = ge_audio_pcm_source_write_frames(source,
                                                        stereo_samples,
                                                        frame_count);
    result->written_frame_count = written;
    result->available_frame_count = ge_audio_pcm_source_available(source);
    result->producer_sample_cursor = first_sample_index + written;
    atomic_store_explicit(&source->producer_native_tick, native_tick, memory_order_release);
    atomic_store_explicit(&source->producer_sample_cursor,
                          result->producer_sample_cursor,
                          memory_order_release);
    result->underrun_count = atomic_load_explicit(&source->underrun_count,
                                                  memory_order_relaxed);
    result->dropped_frame_count = atomic_load_explicit(&source->dropped_frame_count,
                                                       memory_order_relaxed);
    if (written != frame_count) {
        result->flags = atomic_load_explicit(&source->flags, memory_order_acquire);
        return ge_audio_output_diagnostic_set(diagnostic,
                                              GE_AUDIO_ENGINE_V5_DIAG_CAPACITY,
                                              GE_AUDIO_ENGINE_V5_DIAG_FLAG_RECOVERABLE,
                                              written,
                                              frame_count,
                                              "PCM source ring is full; refill was bounded without overwriting unread audio",
                                              GE_STATUS_INVALID_STATE);
    }
    uint32_t flags = atomic_load_explicit(&source->flags, memory_order_acquire);
    if ((flags & GE_AUDIO_OUTPUT_V5_FLAG_PREROLL_REQUIRED) != 0u &&
        result->available_frame_count >= source->preroll_target_frames) {
        flags |= GE_AUDIO_OUTPUT_V5_FLAG_PREROLL_READY;
        atomic_store_explicit(&source->flags, flags, memory_order_release);
    }
    result->flags = flags;
    return GE_STATUS_OK;
}

uint32_t ge_audio_pcm_source_read_frame_v5(
    GEAudioPCMSourceV5 *source,
    int16_t *left,
    int16_t *right)
{
    if (left == NULL || right == NULL) {
        return 0u;
    }
    *left = 0;
    *right = 0;
    if (source == NULL) {
        return 0u;
    }
    uint32_t flags = atomic_load_explicit(&source->flags, memory_order_acquire);
    if ((flags & GE_AUDIO_OUTPUT_V5_FLAG_RUNNING) == 0u) {
        return 0u;
    }
    uint32_t read_index = atomic_load_explicit(&source->read_index,
                                               memory_order_relaxed);
    uint32_t write_index = atomic_load_explicit(&source->write_index,
                                                memory_order_acquire);
    if (write_index == read_index) {
        (void)atomic_fetch_add_explicit(&source->underrun_count,
                                        1u,
                                        memory_order_relaxed);
        return 0u;
    }
    uint32_t ring_frame = read_index & GE_AUDIO_OUTPUT_V5_RING_MASK;
    *left = source->samples[ring_frame * GE_AUDIO_OUTPUT_V5_CHANNELS];
    *right = source->samples[ring_frame * GE_AUDIO_OUTPUT_V5_CHANNELS + 1u];
    atomic_store_explicit(&source->read_index, read_index + 1u, memory_order_release);
    (void)atomic_fetch_add_explicit(&source->consumer_sample_cursor,
                                    1u,
                                    memory_order_relaxed);
    return 1u;
}

GEStatusV1 ge_audio_pcm_source_read_s16_v5(
    GEAudioPCMSourceV5 *source,
    int16_t *stereo_samples,
    uint32_t frame_count,
    GEAudioPCMReadResultV5 *result)
{
    if (source == NULL || stereo_samples == NULL || result == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    memset(result, 0, sizeof(*result));
    result->version = GE_AUDIO_OUTPUT_V5_VERSION;
    result->requested_frame_count = frame_count;
    result->first_sample_index = atomic_load_explicit(&source->consumer_sample_cursor,
                                                      memory_order_acquire);
    for (uint32_t frame = 0u; frame < frame_count; frame++) {
        int16_t left = 0;
        int16_t right = 0;
        if (ge_audio_pcm_source_read_frame_v5(source, &left, &right) != 0u) {
            result->consumed_frame_count++;
        } else {
            result->zero_filled_frame_count++;
        }
        stereo_samples[frame * GE_AUDIO_OUTPUT_V5_CHANNELS] = left;
        stereo_samples[frame * GE_AUDIO_OUTPUT_V5_CHANNELS + 1u] = right;
    }
    result->available_frame_count = ge_audio_pcm_source_available(source);
    result->flags = atomic_load_explicit(&source->flags, memory_order_acquire);
    result->route_generation = atomic_load_explicit(&source->route_generation,
                                                    memory_order_acquire);
    result->underrun_count = atomic_load_explicit(&source->underrun_count,
                                                  memory_order_relaxed);
    result->callback_error = atomic_load_explicit(&source->callback_error,
                                                  memory_order_relaxed);
    result->consumer_sample_cursor = atomic_load_explicit(&source->consumer_sample_cursor,
                                                          memory_order_acquire);
    return GE_STATUS_OK;
}

void ge_audio_pcm_source_snapshot_v5(
    const GEAudioPCMSourceV5 *source,
    GEAudioPCMSourceSnapshotV5 *snapshot)
{
    if (snapshot == NULL) {
        return;
    }
    memset(snapshot, 0, sizeof(*snapshot));
    snapshot->version = GE_AUDIO_OUTPUT_V5_VERSION;
    if (source == NULL) {
        return;
    }
    snapshot->flags = atomic_load_explicit(&source->flags, memory_order_acquire);
    snapshot->sample_rate = source->sample_rate;
    snapshot->channel_count = source->channel_count;
    snapshot->capacity_frames = source->capacity_frames;
    snapshot->available_frames = ge_audio_pcm_source_available(source);
    snapshot->preroll_target_frames = source->preroll_target_frames;
    snapshot->target_fill_frames = source->target_fill_frames;
    snapshot->route_generation = atomic_load_explicit(&source->route_generation,
                                                      memory_order_acquire);
    snapshot->underrun_count = atomic_load_explicit(&source->underrun_count,
                                                    memory_order_relaxed);
    snapshot->dropped_frame_count = atomic_load_explicit(&source->dropped_frame_count,
                                                         memory_order_relaxed);
    snapshot->callback_error = atomic_load_explicit(&source->callback_error,
                                                    memory_order_relaxed);
    snapshot->producer_native_tick = atomic_load_explicit(&source->producer_native_tick,
                                                          memory_order_acquire);
    snapshot->producer_sample_cursor = atomic_load_explicit(&source->producer_sample_cursor,
                                                            memory_order_acquire);
    snapshot->consumer_sample_cursor = atomic_load_explicit(&source->consumer_sample_cursor,
                                                            memory_order_acquire);
}

void ge_audio_pcm_source_note_callback_error_v5(
    GEAudioPCMSourceV5 *source,
    uint32_t error_code)
{
    if (source == NULL) {
        return;
    }
    atomic_store_explicit(&source->callback_error,
                          error_code,
                          memory_order_relaxed);
    (void)atomic_fetch_or_explicit(&source->flags,
                                   GE_AUDIO_OUTPUT_V5_FLAG_CALLBACK_ERROR,
                                   memory_order_relaxed);
}
