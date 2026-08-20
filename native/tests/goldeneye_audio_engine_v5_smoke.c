#include "ge_audio_engine_v5.h"

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
    assert(handle != NULL);
    assert(fseek(handle, 0, SEEK_END) == 0);
    long length = ftell(handle);
    assert(length > 0 && (unsigned long)length <= UINT32_MAX);
    assert(fseek(handle, 0, SEEK_SET) == 0);
    file.count = (uint32_t)length;
    file.bytes = (uint8_t *)malloc(file.count);
    assert(file.bytes != NULL);
    assert(fread(file.bytes, 1u, file.count, handle) == file.count);
    assert(fclose(handle) == 0);
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
                "audio smoke failure status=%u code=%u flags=%u track=%u offset=%u opcode=%u detail=%u/%u message=%s\n",
                status,
                diagnostic == NULL ? 0u : diagnostic->code,
                diagnostic == NULL ? 0u : diagnostic->flags,
                diagnostic == NULL ? 0u : diagnostic->track,
                diagnostic == NULL ? 0u : diagnostic->byte_offset,
                diagnostic == NULL ? 0u : diagnostic->opcode,
                diagnostic == NULL ? 0u : diagnostic->detail0,
                diagnostic == NULL ? 0u : diagnostic->detail1,
                diagnostic == NULL ? "" : diagnostic->message);
        abort();
    }
}

int main(int argc, char **argv)
{
    const char *root = argc > 1 ? argv[1] : "build/native/boot-assets/audio";
    char path[512];
    ByteFile sequence = {0};
    ByteFile ctl = {0};
    ByteFile tbl = {0};
    GEAudioDiagnosticV5 diagnostic;
    GECSeqInfoV5 info;
    GECSeqStateV5 state;
    GEAudioSchedulerV5 scheduler;
    GECSeqEventV5 event;
    uint64_t sample_index = 0u;

    (void)snprintf(path, sizeof(path), "%s/Mnint_rare_logo.bin", root);
    sequence = read_file(path);
    (void)snprintf(path, sizeof(path), "%s/instruments.ctl", root);
    ctl = read_file(path);
    (void)snprintf(path, sizeof(path), "%s/instruments.tbl", root);
    tbl = read_file(path);

    require_ok(ge_cseq_validate_v5(sequence.bytes, sequence.count, &info, &diagnostic), &diagnostic);
    assert(info.division == 0x180u);
    assert(info.track_count > 0u && info.track_count <= 16u);
    uint32_t sequence_track_count = info.track_count;
    require_ok(ge_cseq_state_init_v5(sequence.bytes, sequence.count, &state, &diagnostic), &diagnostic);
    require_ok(ge_cseq_next_event_v5(sequence.bytes, sequence.count, &state, &event, &diagnostic), &diagnostic);
    assert(event.event_kind == GE_AUDIO_ENGINE_V5_EVENT_TEMPO);
    assert(event.tempo_microseconds == 0x075300u);
    require_ok(ge_audio_scheduler_init_v5(sequence.bytes, sequence.count, &scheduler, &diagnostic), &diagnostic);
    require_ok(ge_audio_scheduler_next_event_v5(sequence.bytes,
                                                sequence.count,
                                                &scheduler,
                                                &event,
                                                &sample_index,
                                                &diagnostic),
                &diagnostic);
    assert(sample_index == 0u);
    assert(event.event_kind == GE_AUDIO_ENGINE_V5_EVENT_TEMPO);

    GEAudioBankV5 bank;
    require_ok(ge_audio_bank_init_v5(ctl.bytes, ctl.count, tbl.bytes, tbl.count, &bank, &diagnostic), &diagnostic);
    GEAudioWaveV5 wave;
    require_ok(ge_audio_bank_lookup_v5(ctl.bytes, ctl.count, &bank, 0u, 60u, 100u, &wave, &diagnostic), &diagnostic);
    int16_t decoded[GE_AUDIO_ENGINE_V5_MAX_WAVE_SAMPLES];
    uint32_t decoded_count = 0u;
    require_ok(ge_audio_decode_wave_v5(ctl.bytes,
                                       ctl.count,
                                       tbl.bytes,
                                       tbl.count,
                                       &wave,
                                       decoded,
                                       GE_AUDIO_ENGINE_V5_MAX_WAVE_SAMPLES,
                                       &decoded_count,
                                       &diagnostic),
                &diagnostic);
    assert(decoded_count == wave.sample_count);
    assert(decoded_count > 16u);

    int found_raw16 = 0;
    for (uint32_t program = 0u; program < bank.instrument_count && found_raw16 == 0; program++) {
        for (uint32_t key = 0u; key < 128u; key++) {
            GEAudioWaveV5 raw_wave;
            GEStatusV1 lookup_status = ge_audio_bank_lookup_v5(ctl.bytes,
                                                               ctl.count,
                                                               &bank,
                                                               program,
                                                               key,
                                                               100u,
                                                               &raw_wave,
                                                               &diagnostic);
            if (lookup_status != GE_STATUS_OK || raw_wave.type != GE_AUDIO_ENGINE_V5_WAVE_RAW16) {
                continue;
            }
            uint32_t raw_count = 0u;
            require_ok(ge_audio_decode_wave_v5(ctl.bytes,
                                                ctl.count,
                                                tbl.bytes,
                                                tbl.count,
                                                &raw_wave,
                                                decoded,
                                                GE_AUDIO_ENGINE_V5_MAX_WAVE_SAMPLES,
                                                &raw_count,
                                                &diagnostic),
                        &diagnostic);
            assert(raw_count == raw_wave.sample_count);
            found_raw16 = 1;
            break;
        }
    }
    assert(found_raw16 != 0);

    int16_t stereo[4096u * 2u];
    GEAudioRenderResultV5 result;
    require_ok(ge_audio_render_sequence_v5(sequence.bytes,
                                            sequence.count,
                                            ctl.bytes,
                                            ctl.count,
                                            tbl.bytes,
                                            tbl.count,
                                            4096u,
                                            stereo,
                                            4096u * 2u,
                                            &result,
                                            &diagnostic),
                &diagnostic);
    assert(result.frames_requested == 4096u);
    assert(result.frames_rendered == 4096u);
    assert(result.event_count == 27u);
    assert(result.pcm_hash == UINT64_C(7358868759095366475));

    const char *sequence_names[] = {"Mintro_eye.bin", "Mfolders.bin"};
    for (size_t sequence_index = 0u;
         sequence_index < sizeof(sequence_names) / sizeof(sequence_names[0]);
         sequence_index++) {
        ByteFile other_sequence = {0};
        (void)snprintf(path, sizeof(path), "%s/%s", root, sequence_names[sequence_index]);
        other_sequence = read_file(path);
        GECSeqInfoV5 other_info;
        require_ok(ge_cseq_validate_v5(other_sequence.bytes,
                                       other_sequence.count,
                                       &other_info,
                                       &diagnostic),
                    &diagnostic);
        assert(other_info.division == 0x180u);
        GEAudioRenderResultV5 other_result;
        require_ok(ge_audio_render_sequence_v5(other_sequence.bytes,
                                                other_sequence.count,
                                                ctl.bytes,
                                                ctl.count,
                                                tbl.bytes,
                                                tbl.count,
                                                1024u,
                                                stereo,
                                                1024u * 2u,
                                                &other_result,
                                                &diagnostic),
                    &diagnostic);
        assert(other_result.frames_rendered == 1024u);
        assert(other_result.event_count > 0u);
        assert(other_result.pcm_hash != 0u);
        free_file(&other_sequence);
    }

    ByteFile sfx_ctl = {0};
    ByteFile sfx_tbl = {0};
    (void)snprintf(path, sizeof(path), "%s/sfx.ctl", root);
    sfx_ctl = read_file(path);
    (void)snprintf(path, sizeof(path), "%s/sfx.tbl", root);
    sfx_tbl = read_file(path);
    GEAudioBankV5 sfx_bank;
    require_ok(ge_audio_bank_init_v5(sfx_ctl.bytes,
                                     sfx_ctl.count,
                                     sfx_tbl.bytes,
                                     sfx_tbl.count,
                                     &sfx_bank,
                                     &diagnostic),
                &diagnostic);
    const uint32_t sfx_indices[] = {0u, 1u, 100u, 260u};
    for (size_t sfx_index = 0u;
         sfx_index < sizeof(sfx_indices) / sizeof(sfx_indices[0]);
         sfx_index++) {
        GEAudioWaveV5 sfx_wave;
        require_ok(ge_audio_bank_lookup_sfx_v5(sfx_ctl.bytes,
                                               sfx_ctl.count,
                                               &sfx_bank,
                                               sfx_indices[sfx_index],
                                               &sfx_wave,
                                               &diagnostic),
                    &diagnostic);
        uint32_t sfx_sample_count = 0u;
        require_ok(ge_audio_decode_wave_v5(sfx_ctl.bytes,
                                           sfx_ctl.count,
                                           sfx_tbl.bytes,
                                           sfx_tbl.count,
                                           &sfx_wave,
                                           decoded,
                                           GE_AUDIO_ENGINE_V5_MAX_WAVE_SAMPLES,
                                           &sfx_sample_count,
                                           &diagnostic),
                    &diagnostic);
        assert(sfx_sample_count == sfx_wave.sample_count);
    }
    GEAudioRenderResultV5 sfx_result;
    require_ok(ge_audio_render_sfx_v5(sfx_ctl.bytes,
                                      sfx_ctl.count,
                                      sfx_tbl.bytes,
                                      sfx_tbl.count,
                                      0u,
                                      1024u,
                                      stereo,
                                      1024u * 2u,
                                      &sfx_result,
                                      &diagnostic),
                &diagnostic);
    assert(sfx_result.frames_rendered == 1024u);
    assert(sfx_result.event_count == 1u);
    assert(sfx_result.pcm_hash != 0u);
    assert(ge_audio_feature_status_v5(GE_AUDIO_ENGINE_V5_STUB_FEATURE_REVERB,
                                      &diagnostic) == GE_STATUS_UNSUPPORTED_COMMAND);
    assert((diagnostic.flags & GE_AUDIO_ENGINE_V5_DIAG_FLAG_STUB_M13) != 0u);
    assert(strstr(diagnostic.message, "STUB(M13)") != NULL);
    assert(ge_audio_feature_status_v5(GE_AUDIO_ENGINE_V5_STUB_FEATURE_COMPOSITE_SFX,
                                      &diagnostic) == GE_STATUS_UNSUPPORTED_COMMAND);
    assert((diagnostic.flags & GE_AUDIO_ENGINE_V5_DIAG_FLAG_STUB_M13) != 0u);
    free_file(&sfx_ctl);
    free_file(&sfx_tbl);

    uint8_t malformed[68];
    memset(malformed, 0, sizeof(malformed));
    malformed[3] = 1u;
    malformed[66] = 0x01u;
    malformed[67] = 0x80u;
    assert(ge_cseq_validate_v5(malformed, sizeof(malformed), &info, &diagnostic) != GE_STATUS_OK);
    assert(diagnostic.code == GE_AUDIO_ENGINE_V5_DIAG_OFFSET);
    assert(diagnostic.byte_offset == 0u);

    printf("audio-engine-v5 smoke: PASS division=%u tracks=%u wave_samples=%u frames=%u events=%u pcm_hash=%llu\n",
           info.division,
           sequence_track_count,
           decoded_count,
           result.frames_rendered,
           result.event_count,
           (unsigned long long)result.pcm_hash);
    free_file(&sequence);
    free_file(&ctl);
    free_file(&tbl);
    return 0;
}
