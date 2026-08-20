#include "ge_audio_output_v5.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

static void fill_frames(int16_t *samples, uint32_t frame_count, int16_t base)
{
    for (uint32_t frame = 0u; frame < frame_count; frame++) {
        samples[frame * 2u] = (int16_t)(base + (int16_t)frame);
        samples[frame * 2u + 1u] = (int16_t)(-base - (int16_t)frame);
    }
}

static void require_status(GEStatusV1 status)
{
    assert(status == GE_STATUS_OK);
}

int main(void)
{
    const uint32_t expected_frames[] = {183u, 184u, 184u, 184u,
                                        183u, 184u, 184u, 184u};
    const uint64_t expected_samples[] = {0u, 183u, 367u, 551u,
                                         735u, 918u, 1102u, 1286u};
    for (uint64_t tick = 0u; tick < 8u; tick++) {
        assert(ge_audio_pcm_source_frame_count_for_tick_v5(tick) == expected_frames[tick]);
        assert(ge_audio_pcm_source_sample_index_for_tick_v5(tick) == expected_samples[tick]);
    }

    GEAudioPCMSourceV5 source;
    require_status(ge_audio_pcm_source_init_v5(&source, 366u, 732u));
    assert(atomic_load_explicit(&source.flags, memory_order_acquire) ==
           GE_AUDIO_OUTPUT_V5_FLAG_PREROLL_REQUIRED);

    int16_t tick_samples[184u * 2u];
    GEAudioPCMRefillResultV5 refill;
    GEAudioDiagnosticV5 diagnostic;
    fill_frames(tick_samples, 183u, 100);
    require_status(ge_audio_pcm_source_refill_tick_v5(&source,
                                                      0u,
                                                      0u,
                                                      tick_samples,
                                                      183u,
                                                      &refill,
                                                      &diagnostic));
    assert(refill.native_tick_frame_count == 183u);
    assert(refill.written_frame_count == 183u);
    assert(refill.available_frame_count == 183u);
    assert((refill.flags & GE_AUDIO_OUTPUT_V5_FLAG_PREROLL_READY) == 0u);

    fill_frames(tick_samples, 184u, 400);
    require_status(ge_audio_pcm_source_refill_tick_v5(&source,
                                                      1u,
                                                      183u,
                                                      tick_samples,
                                                      184u,
                                                      &refill,
                                                      &diagnostic));
    assert(refill.written_frame_count == 184u);
    assert(refill.available_frame_count == 367u);
    assert((refill.flags & GE_AUDIO_OUTPUT_V5_FLAG_PREROLL_READY) != 0u);
    require_status(ge_audio_pcm_source_mark_running_v5(&source));

    int16_t output[370u * 2u];
    GEAudioPCMReadResultV5 read_result;
    require_status(ge_audio_pcm_source_read_s16_v5(&source,
                                                   output,
                                                   370u,
                                                   &read_result));
    assert(read_result.consumed_frame_count == 367u);
    assert(read_result.zero_filled_frame_count == 3u);
    assert(read_result.first_sample_index == 0u);
    assert(read_result.consumer_sample_cursor == 367u);
    assert(output[0] == 100 && output[1] == -100);
    assert(output[366u * 2u] == 400 + 183 && output[366u * 2u + 1u] == -400 - 183);
    assert(output[367u * 2u] == 0 && output[367u * 2u + 1u] == 0);
    assert(read_result.underrun_count == 3u);

    require_status(ge_audio_pcm_source_begin_route_recovery_v5(&source,
                                                                GE_AUDIO_OUTPUT_V5_SAMPLE_RATE,
                                                                GE_AUDIO_OUTPUT_V5_CHANNELS,
                                                                7u));
    GEAudioPCMSourceSnapshotV5 snapshot;
    ge_audio_pcm_source_snapshot_v5(&source, &snapshot);
    assert(snapshot.route_generation == 7u);
    assert((snapshot.flags & GE_AUDIO_OUTPUT_V5_FLAG_ROUTE_RECOVERING) != 0u);
    int16_t left = 1;
    int16_t right = 1;
    assert(ge_audio_pcm_source_read_frame_v5(&source, &left, &right) == 0u);
    assert(left == 0 && right == 0);

    fill_frames(tick_samples, 183u, 900);
    require_status(ge_audio_pcm_source_refill_tick_v5(&source,
                                                      0u,
                                                      0u,
                                                      tick_samples,
                                                      183u,
                                                      &refill,
                                                      &diagnostic));
    fill_frames(tick_samples, 184u, 1100);
    require_status(ge_audio_pcm_source_refill_tick_v5(&source,
                                                      1u,
                                                      183u,
                                                      tick_samples,
                                                      184u,
                                                      &refill,
                                                      &diagnostic));
    require_status(ge_audio_pcm_source_mark_running_v5(&source));
    assert(ge_audio_pcm_source_read_frame_v5(&source, &left, &right) == 1u);
    assert(left == 900 && right == -900);

    GEAudioPCMSourceV5 overrun;
    require_status(ge_audio_pcm_source_init_v5(&overrun, 1u, 1u));
    int saw_overrun = 0;
    uint64_t sample_cursor = 0u;
    for (uint64_t tick = 0u; tick < 60u; tick++) {
        uint32_t frames = ge_audio_pcm_source_frame_count_for_tick_v5(tick);
        fill_frames(tick_samples, frames, (int16_t)tick);
        GEStatusV1 status = ge_audio_pcm_source_refill_tick_v5(&overrun,
                                                               tick,
                                                               sample_cursor,
                                                               tick_samples,
                                                               frames,
                                                               &refill,
                                                               &diagnostic);
        if (status != GE_STATUS_OK) {
            saw_overrun = 1;
            assert(diagnostic.code == GE_AUDIO_ENGINE_V5_DIAG_CAPACITY);
            break;
        }
        sample_cursor += frames;
    }
    assert(saw_overrun != 0);
    ge_audio_pcm_source_note_callback_error_v5(&overrun, 123u);
    ge_audio_pcm_source_snapshot_v5(&overrun, &snapshot);
    assert(snapshot.callback_error == 123u);
    assert((snapshot.flags & GE_AUDIO_OUTPUT_V5_FLAG_CALLBACK_ERROR) != 0u);

    printf("audio-output-v5 smoke: PASS ticks=8 preroll=367 overrun=1 route_generation=%u underruns=%u\n",
           snapshot.route_generation,
           snapshot.underrun_count);
    return 0;
}
