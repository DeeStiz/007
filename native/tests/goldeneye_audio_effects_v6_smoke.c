#include "ge_audio_effects_v6.h"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct ByteFile {
    uint8_t *bytes;
    uint32_t count;
} ByteFile;

static ByteFile read_file(const char *path)
{
    ByteFile file = {0};
    FILE *handle = fopen(path, "rb");
    if (handle == NULL || fseek(handle, 0, SEEK_END) != 0) {
        fprintf(stderr, "audio effects smoke could not open/seek %s\n", path);
        abort();
    }
    long length = ftell(handle);
    if (length <= 0 || (unsigned long)length > UINT32_MAX ||
        fseek(handle, 0, SEEK_SET) != 0) {
        fprintf(stderr, "audio effects smoke has invalid asset length %s\n", path);
        fclose(handle);
        abort();
    }
    file.count = (uint32_t)length;
    file.bytes = (uint8_t *)malloc(file.count);
    if (file.bytes == NULL || fread(file.bytes, 1u, file.count, handle) != file.count ||
        fclose(handle) != 0) {
        fprintf(stderr, "audio effects smoke could not read %s\n", path);
        free(file.bytes);
        abort();
    }
    return file;
}

static void free_file(ByteFile *file)
{
    free(file->bytes);
    file->bytes = NULL;
    file->count = 0u;
}

static void require_ok(GEStatusV1 status, const GEAudioDiagnosticV5 *diagnostic)
{
    if (status != GE_STATUS_OK) {
        fprintf(stderr,
                "audio effects smoke failure status=%u code=%u flags=%u detail=%u/%u message=%s\n",
                status,
                diagnostic == NULL ? 0u : diagnostic->code,
                diagnostic == NULL ? 0u : diagnostic->flags,
                diagnostic == NULL ? 0u : diagnostic->detail0,
                diagnostic == NULL ? 0u : diagnostic->detail1,
                diagnostic == NULL ? "" : diagnostic->message);
        abort();
    }
}

static void path_join(char *path,
                      size_t path_capacity,
                      const char *root,
    const char *name)
{
    int written = snprintf(path, path_capacity, "%s/%s", root, name);
    if (written <= 0 || (size_t)written >= path_capacity) {
        fprintf(stderr, "audio effects smoke path is too long: %s/%s\n", root, name);
        abort();
    }
}

static int all_equal(const int16_t *first, const int16_t *second, size_t count)
{
    return memcmp(first, second, count * sizeof(*first)) == 0;
}

int main(int argc, char **argv)
{
    const char *root = argc > 1 ? argv[1] : "build/native/boot-assets/audio";
    char path[512];
    GEAudioDiagnosticV5 diagnostic;

    ByteFile sequence;
    ByteFile ctl;
    ByteFile tbl;
    path_join(path, sizeof(path), root, "Mnint_rare_logo.bin");
    sequence = read_file(path);
    path_join(path, sizeof(path), root, "instruments.ctl");
    ctl = read_file(path);
    path_join(path, sizeof(path), root, "instruments.tbl");
    tbl = read_file(path);

    /* The additive V6 target must not alter the frozen V5 boot vector. */
    int16_t boot_pcm[4096u * 2u];
    GEAudioRenderResultV5 boot_result;
    require_ok(ge_audio_render_sequence_v5(sequence.bytes,
                                            sequence.count,
                                            ctl.bytes,
                                            ctl.count,
                                            tbl.bytes,
                                            tbl.count,
                                            4096u,
                                            boot_pcm,
                                            4096u * 2u,
                                            &boot_result,
                                            &diagnostic),
                &diagnostic);
    assert(boot_result.pcm_hash == UINT64_C(7358868759095366475));

    GEAudioReverbConfigV6 small_config;
    require_ok(ge_audio_reverb_config_for_preset_v6(
                    GE_AUDIO_EFFECTS_V6_REVERB_PRESET_SMALL_ROOM,
                    GE_AUDIO_EFFECTS_V6_SAMPLE_RATE,
                    &small_config,
                    &diagnostic),
                &diagnostic);
    assert(small_config.section_count == 3u);
    assert(small_config.input_delay_frames[1] == 419u);
    assert(small_config.output_delay_frames[0] == 1191u);
    GEAudioReverbConfigV6 big_config;
    require_ok(ge_audio_reverb_config_for_preset_v6(
                    GE_AUDIO_EFFECTS_V6_REVERB_PRESET_BIG_ROOM,
                    GE_AUDIO_EFFECTS_V6_SAMPLE_RATE,
                    &big_config,
                    &diagnostic),
                &diagnostic);
    assert(big_config.section_count == 4u);
    assert(big_config.output_delay_frames[3] == 2073u);

    path_join(path, sizeof(path), root, "sfx.ctl");
    ByteFile sfx_ctl = read_file(path);
    path_join(path, sizeof(path), root, "sfx.tbl");
    ByteFile sfx_tbl = read_file(path);

    enum { source_count = 4, graph_frames = 1024, tail_frames = 2048 };
    const uint32_t sound_indices[source_count] = {0u, 1u, 100u, 260u};
    GEAudioSfxSourceV6 sources[source_count];
    GEAudioSfxGraphV6 graph;
    ge_audio_sfx_graph_init_v6(&graph, GE_AUDIO_EFFECTS_V6_SAMPLE_RATE);
    graph.source_count = source_count;
    for (uint32_t source = 0u; source < source_count; source++) {
        ge_audio_sfx_source_init_v6(&sources[source],
                                    source,
                                    sound_indices[source]);
    }
    for (uint32_t event_index = 0u; event_index < source_count; event_index++) {
        GEAudioSfxEventV6 event;
        ge_audio_sfx_event_init_v6(&event, event_index, event_index);
        event.start_frame = event_index * 16u;
        event.duration_frames = 768u;
        event.gain_q15 = 32768u - event_index * 4096u;
        event.pan_q15 = 8192u + event_index * 5461u;
        event.attack_frames = 8u + event_index;
        event.release_frames = 64u;
        require_ok(ge_audio_sfx_graph_append_event_v6(&graph,
                                                      event,
                                                      &diagnostic),
                    &diagnostic);
    }
    assert(graph.event_count == source_count);

    uint32_t decode_capacity = source_count * GE_AUDIO_ENGINE_V5_MAX_WAVE_SAMPLES;
    int16_t *decode_arena = (int16_t *)calloc(decode_capacity, sizeof(int16_t));
    assert(decode_arena != NULL);
    int16_t *graph_pcm = (int16_t *)calloc(graph_frames * 2u, sizeof(int16_t));
    int16_t *graph_pcm_again = (int16_t *)calloc(graph_frames * 2u, sizeof(int16_t));
    assert(graph_pcm != NULL && graph_pcm_again != NULL);
    GEAudioSfxGraphResultV6 graph_result;
    require_ok(ge_audio_sfx_graph_render_bank_v6(&graph,
                                                 sources,
                                                 source_count,
                                                 sfx_ctl.bytes,
                                                 sfx_ctl.count,
                                                 sfx_tbl.bytes,
                                                 sfx_tbl.count,
                                                 decode_arena,
                                                 decode_capacity,
                                                 graph_frames,
                                                 graph_pcm,
                                                 graph_frames * 2u,
                                                 &graph_result,
                                                 &diagnostic),
                &diagnostic);
    GEAudioSfxGraphResultV6 graph_result_again;
    require_ok(ge_audio_sfx_graph_render_bank_v6(&graph,
                                                 sources,
                                                 source_count,
                                                 sfx_ctl.bytes,
                                                 sfx_ctl.count,
                                                 sfx_tbl.bytes,
                                                 sfx_tbl.count,
                                                 decode_arena,
                                                 decode_capacity,
                                                 graph_frames,
                                                 graph_pcm_again,
                                                 graph_frames * 2u,
                                                 &graph_result_again,
                                                 &diagnostic),
                &diagnostic);
    assert(graph_result.frames_rendered == graph_frames);
    assert(graph_result.event_count == source_count);
    assert(graph_result.active_voice_count > 1u);
    assert((graph_result.flags & GE_AUDIO_EFFECTS_V6_RESULT_FLAG_NONZERO) != 0u);
    assert(graph_result.pcm_hash != 0u);
    assert(graph_result.event_hash == graph_result_again.event_hash);
    assert(graph_result.pcm_hash == graph_result_again.pcm_hash);
    if (!all_equal(graph_pcm, graph_pcm_again, graph_frames * 2u)) {
        fprintf(stderr, "audio effects smoke graph render was not deterministic\n");
        abort();
    }

    uint32_t total_frames = graph_frames + tail_frames;
    int16_t *all_input = (int16_t *)calloc(total_frames * 2u, sizeof(int16_t));
    int16_t *whole_output = (int16_t *)calloc(total_frames * 2u, sizeof(int16_t));
    int16_t *split_output = (int16_t *)calloc(total_frames * 2u, sizeof(int16_t));
    assert(all_input != NULL && whole_output != NULL && split_output != NULL);
    memcpy(all_input, graph_pcm, graph_frames * 2u * sizeof(int16_t));

    GEAudioReverbBusV6 *whole_bus =
        (GEAudioReverbBusV6 *)calloc(1u, sizeof(*whole_bus));
    GEAudioReverbBusV6 *split_bus =
        (GEAudioReverbBusV6 *)calloc(1u, sizeof(*split_bus));
    GEAudioReverbBusV6 *big_bus =
        (GEAudioReverbBusV6 *)calloc(1u, sizeof(*big_bus));
    assert(whole_bus != NULL && split_bus != NULL && big_bus != NULL);
    require_ok(ge_audio_reverb_bus_init_v6(whole_bus, &small_config, &diagnostic),
                &diagnostic);
    GEAudioReverbResultV6 whole_result;
    require_ok(ge_audio_reverb_bus_process_v6(whole_bus,
                                              all_input,
                                              total_frames,
                                              whole_output,
                                              total_frames * 2u,
                                              &whole_result,
                                              &diagnostic),
                &diagnostic);
    require_ok(ge_audio_reverb_bus_init_v6(split_bus, &small_config, &diagnostic),
                &diagnostic);
    GEAudioReverbResultV6 split_result;
    require_ok(ge_audio_reverb_bus_process_v6(split_bus,
                                              graph_pcm,
                                              graph_frames,
                                              split_output,
                                              total_frames * 2u,
                                              &split_result,
                                              &diagnostic),
                &diagnostic);
    require_ok(ge_audio_reverb_bus_process_v6(split_bus,
                                              all_input + graph_frames * 2u,
                                              tail_frames,
                                              split_output + graph_frames * 2u,
                                              tail_frames * 2u,
                                              &split_result,
                                              &diagnostic),
                &diagnostic);
    assert(whole_result.frames_processed == total_frames);
    assert(split_result.frames_processed == tail_frames);
    assert(whole_result.output_hash == split_result.output_hash);
    if (!all_equal(whole_output, split_output, total_frames * 2u)) {
        fprintf(stderr, "audio effects smoke reverb block split changed output\n");
        abort();
    }
    assert((split_result.flags & GE_AUDIO_EFFECTS_V6_RESULT_FLAG_REVERB_TAIL) != 0u);
    assert(whole_result.peak_abs > 0u);

    require_ok(ge_audio_reverb_bus_init_v6(big_bus, &big_config, &diagnostic),
                &diagnostic);
    GEAudioReverbResultV6 big_result;
    require_ok(ge_audio_reverb_bus_process_v6(big_bus,
                                              graph_pcm,
                                              graph_frames,
                                              split_output,
                                              graph_frames * 2u,
                                              &big_result,
                                              &diagnostic),
                &diagnostic);
    assert(big_result.frames_processed == graph_frames);
    assert(big_result.output_hash != 0u);

    assert(ge_audio_effects_feature_status_v6(
               GE_AUDIO_EFFECTS_V6_FEATURE_REVERB,
               &diagnostic) == GE_STATUS_OK);
    assert((diagnostic.flags & GE_AUDIO_ENGINE_V5_DIAG_FLAG_STUB_M13) == 0u);
    assert(ge_audio_effects_feature_status_v6(
               GE_AUDIO_EFFECTS_V6_FEATURE_COMPOSITE_SFX,
               &diagnostic) == GE_STATUS_OK);
    assert((diagnostic.flags & GE_AUDIO_ENGINE_V5_DIAG_FLAG_STUB_M13) == 0u);

    GEAudioSfxSourceV6 bad_source = sources[0];
    bad_source.sample_offset = decode_capacity;
    GEStatusV1 bad_status = ge_audio_sfx_graph_validate_v6(&graph,
                                                           &bad_source,
                                                           1u,
                                                           decode_capacity,
                                                           &diagnostic);
    if (bad_status == GE_STATUS_OK ||
        diagnostic.code != GE_AUDIO_ENGINE_V5_DIAG_ARGUMENT) {
        fprintf(stderr, "audio effects smoke accepted malformed source metadata\n");
        abort();
    }

    printf("audio-effects-v6 smoke: PASS boot_hash=%llu graph_hash=%llu reverb_hash=%llu active=%u\n",
           (unsigned long long)boot_result.pcm_hash,
           (unsigned long long)graph_result.pcm_hash,
           (unsigned long long)whole_result.output_hash,
           graph_result.active_voice_count);

    free(big_bus);
    free(split_bus);
    free(whole_bus);
    free(split_output);
    free(whole_output);
    free(all_input);
    free(graph_pcm_again);
    free(graph_pcm);
    free(decode_arena);
    free_file(&sfx_tbl);
    free_file(&sfx_ctl);
    free_file(&tbl);
    free_file(&ctl);
    free_file(&sequence);
    return 0;
}
