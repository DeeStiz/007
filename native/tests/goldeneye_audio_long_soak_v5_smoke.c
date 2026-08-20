#include "ge_audio_output_v5.h"

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/*
 * M13 owner-side audio soak.
 *
 * The source stream is deliberately generated from its absolute source
 * sample index.  This keeps the test bounded (at most one native tick of
 * samples is resident) while exercising the exact 120 Hz -> 22,050 Hz
 * clock for ten source minutes.  Two different read granularities must
 * produce the same PCM hash through the real SPSC ring.
 */
#define GE_AUDIO_SOAK_SECONDS ((uint32_t)600u)
#define GE_AUDIO_SOAK_TICKS \
    ((uint64_t)GE_AUDIO_SOAK_SECONDS * (uint64_t)GE_AUDIO_V5_NATIVE_TICK_RATE)
#define GE_AUDIO_SOAK_PREROLL_TICKS ((uint64_t)16u)
#define GE_AUDIO_SOAK_MAX_TICK_FRAMES ((uint32_t)184u)
#define GE_AUDIO_SOAK_READ_PATTERN_COUNT ((size_t)7u)

typedef struct ByteFile {
    uint8_t *bytes;
    uint32_t count;
} ByteFile;

typedef struct RingSoakResult {
    uint64_t pcm_hash;
    uint64_t frames;
    uint64_t sample_cursor;
    uint64_t producer_tick;
    uint32_t underrun_count;
    uint32_t dropped_frame_count;
    uint32_t callback_error;
} RingSoakResult;

static void require_status(GEStatusV1 status,
                           const GEAudioDiagnosticV5 *diagnostic,
                           const char *operation)
{
    if (status == GE_STATUS_OK) {
        return;
    }
    fprintf(stderr,
            "%s failed status=%u code=%u flags=%u detail=%u/%u message=%s\n",
            operation,
            status,
            diagnostic == NULL ? 0u : diagnostic->code,
            diagnostic == NULL ? 0u : diagnostic->flags,
            diagnostic == NULL ? 0u : diagnostic->detail0,
            diagnostic == NULL ? 0u : diagnostic->detail1,
            diagnostic == NULL ? "" : diagnostic->message);
    abort();
}

static ByteFile read_file(const char *path)
{
    ByteFile file = {0};
    FILE *handle = fopen(path, "rb");
    assert(handle != NULL);
    assert(fseek(handle, 0, SEEK_END) == 0);
    long length = ftell(handle);
    assert(length > 0 && (unsigned long)length <= UINT32_MAX);
    assert(fseek(handle, 0, SEEK_SET) == 0);
    file.count = (uint32_t)length;
    file.bytes = (uint8_t *)malloc((size_t)file.count);
    assert(file.bytes != NULL);
    assert(fread(file.bytes, 1u, (size_t)file.count, handle) == (size_t)file.count);
    assert(fclose(handle) == 0);
    return file;
}

static void free_file(ByteFile *file)
{
    free(file->bytes);
    file->bytes = NULL;
    file->count = 0u;
}

static uint64_t hash_byte(uint64_t hash, uint8_t byte)
{
    return (hash ^ (uint64_t)byte) * UINT64_C(1099511628211);
}

static uint64_t hash_s16_stereo(uint64_t hash, int16_t sample)
{
    uint16_t value = (uint16_t)sample;
    hash = hash_byte(hash, (uint8_t)(value & UINT16_C(0xff)));
    return hash_byte(hash, (uint8_t)(value >> 8));
}

static uint64_t title_sfx_event_hash(uint32_t sound_index)
{
    uint64_t hash = UINT64_C(1469598103934665603);
    for (uint32_t byte = 0u; byte < sizeof(sound_index); byte++) {
        hash = hash_byte(hash, (uint8_t)(sound_index >> (byte * 8u)));
    }
    return hash;
}

static int16_t generated_sample(uint64_t sample_index, uint32_t channel)
{
    /* SplitMix-style fixed-width sequence: no floating point or wall clock. */
    uint64_t value = sample_index +
        (channel == 0u ? UINT64_C(0x9e3779b97f4a7c15) :
                         UINT64_C(0xd1b54a32d192ed03));
    value = (value ^ (value >> 30)) * UINT64_C(0xbf58476d1ce4e5b9);
    value = (value ^ (value >> 27)) * UINT64_C(0x94d049bb133111eb);
    value ^= value >> 31;
    return (int16_t)(value >> 48);
}

static void fill_samples(uint64_t first_sample_index,
                         uint32_t frame_count,
                         int16_t *samples)
{
    for (uint32_t frame = 0u; frame < frame_count; frame++) {
        uint64_t sample_index = first_sample_index + (uint64_t)frame;
        samples[frame * 2u] = generated_sample(sample_index, 0u);
        samples[frame * 2u + 1u] = generated_sample(sample_index, 1u);
    }
}

static void assert_read_result(const GEAudioPCMReadResultV5 *result,
                               uint64_t expected_sample_index,
                               uint32_t expected_frames)
{
    assert(result->requested_frame_count == expected_frames);
    assert(result->consumed_frame_count == expected_frames);
    assert(result->zero_filled_frame_count == 0u);
    assert(result->first_sample_index == expected_sample_index);
    assert(result->consumer_sample_cursor ==
           expected_sample_index + (uint64_t)expected_frames);
    assert(result->underrun_count == 0u);
    assert(result->callback_error == 0u);
}

static RingSoakResult run_ring_soak(uint32_t read_mode)
{
    GEAudioPCMSourceV5 *source =
        (GEAudioPCMSourceV5 *)calloc(1u, sizeof(*source));
    assert(source != NULL);
    GEAudioDiagnosticV5 diagnostic = {0};
    require_status(ge_audio_pcm_source_init_v5(source,
                                               GE_AUDIO_SOAK_MAX_TICK_FRAMES,
                                               GE_AUDIO_OUTPUT_V5_DEFAULT_TARGET_FILL_FRAMES),
                   &diagnostic,
                   "PCM source init");
    require_status(ge_audio_pcm_source_begin_route_recovery_v5(
                       source,
                       GE_AUDIO_OUTPUT_V5_SAMPLE_RATE,
                       GE_AUDIO_OUTPUT_V5_CHANNELS,
                       1u),
                   &diagnostic,
                   "PCM route recovery");

    int16_t tick_samples[GE_AUDIO_SOAK_MAX_TICK_FRAMES * 2u];
    int16_t read_samples[GE_AUDIO_SOAK_MAX_TICK_FRAMES * 2u];
    GEAudioPCMRefillResultV5 refill;

    /* Build a bounded preroll before exposing the source to the consumer. */
    for (uint64_t tick = 0u; tick < GE_AUDIO_SOAK_PREROLL_TICKS; tick++) {
        uint32_t frame_count = ge_audio_pcm_source_frame_count_for_tick_v5(tick);
        uint64_t sample_index = ge_audio_pcm_source_sample_index_for_tick_v5(tick);
        assert(frame_count <= GE_AUDIO_SOAK_MAX_TICK_FRAMES);
        fill_samples(sample_index, frame_count, tick_samples);
        require_status(ge_audio_pcm_source_refill_tick_v5(source,
                                                          tick,
                                                          sample_index,
                                                          tick_samples,
                                                          frame_count,
                                                          &refill,
                                                          &diagnostic),
                       &diagnostic,
                       "PCM preroll refill");
        assert(refill.written_frame_count == frame_count);
        assert(refill.dropped_frame_count == 0u);
    }
    require_status(ge_audio_pcm_source_mark_running_v5(source),
                   &diagnostic,
                   "PCM source mark running");

    const uint32_t read_pattern[GE_AUDIO_SOAK_READ_PATTERN_COUNT] =
        {1u, 64u, 183u, 184u, 37u, 7u, 16u};
    size_t pattern_index = 0u;
    uint64_t hash = UINT64_C(1469598103934665603);
    uint64_t frames_read = 0u;

    for (uint64_t tick = 0u; tick < GE_AUDIO_SOAK_TICKS; tick++) {
        if (tick >= GE_AUDIO_SOAK_PREROLL_TICKS) {
            uint32_t frame_count = ge_audio_pcm_source_frame_count_for_tick_v5(tick);
            uint64_t sample_index = ge_audio_pcm_source_sample_index_for_tick_v5(tick);
            assert(frame_count <= GE_AUDIO_SOAK_MAX_TICK_FRAMES);
            fill_samples(sample_index, frame_count, tick_samples);
            require_status(ge_audio_pcm_source_refill_tick_v5(source,
                                                              tick,
                                                              sample_index,
                                                              tick_samples,
                                                              frame_count,
                                                              &refill,
                                                              &diagnostic),
                           &diagnostic,
                           "PCM soak refill");
            assert(refill.written_frame_count == frame_count);
            assert(refill.dropped_frame_count == 0u);
        }

        uint32_t remaining = ge_audio_pcm_source_frame_count_for_tick_v5(tick);
        uint64_t expected_sample_index =
            ge_audio_pcm_source_sample_index_for_tick_v5(tick);
        uint32_t consumed = 0u;
        while (remaining != 0u) {
            uint32_t block = remaining;
            if (read_mode != 0u) {
                uint32_t pattern_block =
                    read_pattern[pattern_index % GE_AUDIO_SOAK_READ_PATTERN_COUNT];
                pattern_index++;
                if (pattern_block < block) {
                    block = pattern_block;
                }
            }
            GEAudioPCMReadResultV5 read_result;
            require_status(ge_audio_pcm_source_read_s16_v5(source,
                                                           read_samples,
                                                           block,
                                                           &read_result),
                           &diagnostic,
                           "PCM soak read");
            assert_read_result(&read_result,
                               expected_sample_index + (uint64_t)consumed,
                               block);
            for (uint32_t frame = 0u; frame < block; frame++) {
                hash = hash_s16_stereo(hash, read_samples[frame * 2u]);
                hash = hash_s16_stereo(hash, read_samples[frame * 2u + 1u]);
            }
            consumed += block;
            remaining -= block;
        }
        frames_read += (uint64_t)consumed;
    }

    GEAudioPCMSourceSnapshotV5 snapshot;
    ge_audio_pcm_source_snapshot_v5(source, &snapshot);
    assert(frames_read ==
           GE_AUDIO_SOAK_TICKS * (uint64_t)GE_AUDIO_V5_SAMPLE_NUMERATOR /
               (uint64_t)GE_AUDIO_V5_SAMPLE_DENOMINATOR);
    assert(snapshot.available_frames == 0u);
    assert(snapshot.underrun_count == 0u);
    assert(snapshot.dropped_frame_count == 0u);
    assert(snapshot.callback_error == 0u);
    assert(snapshot.producer_sample_cursor == frames_read);
    assert(snapshot.consumer_sample_cursor == frames_read);
    assert(snapshot.producer_native_tick == GE_AUDIO_SOAK_TICKS - 1u);

    RingSoakResult result = {
        hash,
        frames_read,
        snapshot.consumer_sample_cursor,
        snapshot.producer_native_tick,
        snapshot.underrun_count,
        snapshot.dropped_frame_count,
        snapshot.callback_error
    };
    free(source);
    return result;
}

static void validate_title_sfx(const char *root)
{
    char path[512];
    (void)snprintf(path, sizeof(path), "%s/sfx.ctl", root);
    ByteFile ctl = read_file(path);
    (void)snprintf(path, sizeof(path), "%s/sfx.tbl", root);
    ByteFile tbl = read_file(path);

    struct TitleSfxExpectation {
        uint32_t sound_index;
        uint64_t pcm_hash;
    };
    const struct TitleSfxExpectation expected[] = {
        {18u, UINT64_C(14206689231160394853)},
        {77u, UINT64_C(16796028275532771185)},
        {79u, UINT64_C(6952274567016645574)},
        {111u, UINT64_C(8229142411872933376)},
        {258u, UINT64_C(1464652981265774583)}
    };
    int16_t stereo[2048u * 2u];
    uint64_t combined_hash = UINT64_C(1469598103934665603);
    for (size_t index = 0u; index < sizeof(expected) / sizeof(expected[0]); index++) {
        GEAudioRenderResultV5 result;
        GEAudioDiagnosticV5 diagnostic;
        require_status(ge_audio_render_sfx_v5(ctl.bytes,
                                               ctl.count,
                                               tbl.bytes,
                                               tbl.count,
                                               expected[index].sound_index,
                                               2048u,
                                               stereo,
                                               2048u * 2u,
                                               &result,
                                               &diagnostic),
                       &diagnostic,
                       "title SFX render");
        assert(result.frames_rendered == 2048u);
        assert(result.event_count == 1u);
        assert(result.event_hash == title_sfx_event_hash(expected[index].sound_index));
        assert(result.pcm_hash == expected[index].pcm_hash);
        combined_hash = hash_byte(combined_hash,
                                  (uint8_t)(expected[index].sound_index & 0xffu));
        combined_hash = hash_byte(combined_hash,
                                  (uint8_t)(expected[index].sound_index >> 8));
        for (uint32_t byte = 0u; byte < sizeof(result.pcm_hash); byte++) {
            combined_hash = hash_byte(combined_hash,
                                      (uint8_t)(result.pcm_hash >> (byte * 8u)));
        }
    }
    if (combined_hash != UINT64_C(5781274823313348663)) {
        fprintf(stderr, "unexpected title SFX combined hash=%llu\n",
                (unsigned long long)combined_hash);
        abort();
    }
    printf("title_sfx events=18,77,79,111,258 combined_hash=%llu\n",
           (unsigned long long)combined_hash);
    free_file(&tbl);
    free_file(&ctl);
}

int main(int argc, char **argv)
{
    const char *root = argc > 1 ? argv[1] : "build/native/boot-assets/audio";

    uint64_t accumulated_frames = 0u;
    for (uint64_t tick = 0u; tick < GE_AUDIO_SOAK_TICKS; tick++) {
        uint32_t frame_count = ge_audio_frame_count_for_tick_v5(tick);
        assert(frame_count == (tick % 4u == 0u ? 183u : 184u));
        assert(ge_audio_sample_index_for_tick_v5(tick) == accumulated_frames);
        accumulated_frames += (uint64_t)frame_count;
    }
    assert(accumulated_frames == UINT64_C(13230000));
    assert(ge_audio_sample_index_for_tick_v5(GE_AUDIO_SOAK_TICKS) ==
           accumulated_frames);
    assert(accumulated_frames ==
           (uint64_t)GE_AUDIO_SOAK_SECONDS * (uint64_t)GE_AUDIO_V5_SAMPLE_RATE);

    RingSoakResult whole_tick = run_ring_soak(0u);
    RingSoakResult varied_blocks = run_ring_soak(1u);
    assert(whole_tick.frames == accumulated_frames);
    assert(varied_blocks.frames == accumulated_frames);
    assert(whole_tick.pcm_hash == varied_blocks.pcm_hash);
    assert(whole_tick.sample_cursor == accumulated_frames);
    assert(varied_blocks.sample_cursor == accumulated_frames);
    assert(whole_tick.underrun_count == 0u && varied_blocks.underrun_count == 0u);
    assert(whole_tick.dropped_frame_count == 0u &&
           varied_blocks.dropped_frame_count == 0u);
    assert(whole_tick.callback_error == 0u && varied_blocks.callback_error == 0u);

    validate_title_sfx(root);
    printf("goldeneye_audio_long_soak_v5_smoke: PASS seconds=%u ticks=%llu frames=%llu hash=%llu producer_tick=%llu underruns=0 drops=0\n",
           GE_AUDIO_SOAK_SECONDS,
           (unsigned long long)GE_AUDIO_SOAK_TICKS,
           (unsigned long long)accumulated_frames,
           (unsigned long long)whole_tick.pcm_hash,
           (unsigned long long)whole_tick.producer_tick);
    return 0;
}
