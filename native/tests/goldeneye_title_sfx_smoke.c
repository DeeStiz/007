#include "ge_audio_engine_v5.h"

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static uint8_t *read_file(const char *path, uint32_t *count)
{
    FILE *file = fopen(path, "rb");
    assert(file != NULL);
    assert(fseek(file, 0, SEEK_END) == 0);
    long length = ftell(file);
    assert(length > 0 && (unsigned long)length <= UINT32_MAX);
    assert(fseek(file, 0, SEEK_SET) == 0);
    uint8_t *bytes = (uint8_t *)malloc((size_t)length);
    assert(bytes != NULL);
    assert(fread(bytes, 1u, (size_t)length, file) == (size_t)length);
    assert(fclose(file) == 0);
    *count = (uint32_t)length;
    return bytes;
}

int main(int argc, char **argv)
{
    const char *root = argc > 1 ? argv[1] : "build/native/boot-assets/audio";
    char ctl_path[512];
    char tbl_path[512];
    (void)snprintf(ctl_path, sizeof(ctl_path), "%s/sfx.ctl", root);
    (void)snprintf(tbl_path, sizeof(tbl_path), "%s/sfx.tbl", root);
    uint32_t ctl_count = 0;
    uint32_t tbl_count = 0;
    uint8_t *ctl = read_file(ctl_path, &ctl_count);
    uint8_t *tbl = read_file(tbl_path, &tbl_count);

    const uint32_t title_sfx[] = {18u, 77u, 79u, 111u, 258u};
    int16_t stereo[2048u * 2u];
    uint64_t combined_hash = UINT64_C(1469598103934665603);
    for (size_t index = 0; index < sizeof(title_sfx) / sizeof(title_sfx[0]); index++) {
        GEAudioRenderResultV5 result;
        GEAudioDiagnosticV5 diagnostic;
        GEStatusV1 status = ge_audio_render_sfx_v5(
            ctl, ctl_count, tbl, tbl_count, title_sfx[index], 2048u,
            stereo, 2048u * 2u, &result, &diagnostic);
        if (status != GE_STATUS_OK) {
            fprintf(stderr, "title SFX %u failed status=%u code=%u message=%s\n",
                    title_sfx[index], status, diagnostic.code, diagnostic.message);
            return 1;
        }
        assert(result.frames_rendered == 2048u);
        assert(result.event_count == 1u);
        assert(result.pcm_hash != 0u);
        combined_hash ^= result.pcm_hash;
        combined_hash *= UINT64_C(1099511628211);
        printf("sfx=%u hash=%llu\n", title_sfx[index],
               (unsigned long long)result.pcm_hash);
    }
    free(ctl);
    free(tbl);
    printf("goldeneye_title_sfx_smoke: PASS count=5 combined_hash=%llu\n",
           (unsigned long long)combined_hash);
    return 0;
}
