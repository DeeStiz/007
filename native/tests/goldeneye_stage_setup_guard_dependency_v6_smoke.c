#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint32_t be32(const uint8_t *bytes, size_t length, size_t offset, int *ok)
{
    if (bytes == NULL || ok == NULL || offset > length || length - offset < 4u) {
        if (ok != NULL) *ok = 0;
        return 0u;
    }
    return ((uint32_t)bytes[offset] << 24) |
           ((uint32_t)bytes[offset + 1u] << 16) |
           ((uint32_t)bytes[offset + 2u] << 8) |
           (uint32_t)bytes[offset + 3u];
}

static int guard_body_ai(const uint8_t *bytes, size_t length, size_t offset,
                         uint32_t *out_body, uint32_t *out_ai)
{
    int ok = 1;
    uint32_t body_ai;
    if (bytes == NULL || out_body == NULL || out_ai == NULL ||
        offset > length || length - offset < 12u) {
        return 0;
    }
    body_ai = be32(bytes, length, offset + 8u, &ok);
    if (!ok) return 0;
    *out_body = body_ai >> 16;
    *out_ai = body_ai & 0xffffu;
    return 1;
}

static size_t object_words(uint32_t type)
{
    static const uint8_t sizes[48] = {
        1u, 64u, 2u, 32u, 33u, 32u, 59u, 33u, 34u, 7u,
        64u, 149u, 32u, 54u, 3u, 1u, 1u, 32u, 3u, 4u,
        45u, 34u, 4u, 4u, 1u, 2u, 2u, 2u, 2u, 1u,
        4u, 1u, 4u, 5u, 4u, 4u, 32u, 10u, 4u, 44u,
        45u, 1u, 32u, 1u, 1u, 56u, 7u, 37u,
    };
    return type < 48u ? sizes[type] : 0u;
}

static int find_first_guard(const uint8_t *bytes, size_t length,
                            size_t *out_offset, uint32_t *out_chrnum,
                            uint32_t *out_body, uint32_t *out_ai)
{
    int ok = 1;
    uint32_t offsets[10];
    uint32_t first_offset;
    size_t start;
    size_t end;
    size_t offset;
    size_t index;

    if (bytes == NULL || out_offset == NULL || out_chrnum == NULL ||
        out_body == NULL || out_ai == NULL || length < 40u) {
        return -1;
    }
    for (index = 0u; index < 10u; index++) {
        offsets[index] = be32(bytes, length, index * 4u, &ok);
        if (!ok) return -1;
    }
    first_offset = offsets[3];
    start = (size_t)first_offset;
    if (start == 0u || start >= length) return -1;
    end = length;
    for (index = 0u; index < 10u; index++) {
        if (offsets[index] > first_offset && (size_t)offsets[index] < end) {
            end = (size_t)offsets[index];
        }
    }
    if (end <= start) return -1;

    offset = start;
    while (offset <= end && end - offset >= 4u) {
        uint32_t first = be32(bytes, length, offset, &ok);
        uint32_t type;
        size_t bytes_in_record;
        uint32_t second;
        if (!ok) return -1;
        type = first & 0xffu;
        if (type == 48u) return 0;
        if (object_words(type) == 0u) return -1;
        bytes_in_record = object_words(type) * 4u;
        if (bytes_in_record > end - offset) return -1;
        if (type == 9u) {
            second = be32(bytes, length, offset + 4u, &ok);
            if (!ok || !guard_body_ai(bytes, length, offset, out_body, out_ai)) {
                return -1;
            }
            *out_offset = offset;
            *out_chrnum = second >> 16;
            return 1;
        }
        offset += bytes_in_record;
    }
    return -1;
}

static uint8_t *read_file(const char *path, size_t *out_length)
{
    FILE *file;
    long length;
    uint8_t *bytes;
    size_t read_length;

    if (path == NULL || out_length == NULL) return NULL;
    file = fopen(path, "rb");
    if (file == NULL || fseek(file, 0, SEEK_END) != 0) {
        if (file != NULL) fclose(file);
        return NULL;
    }
    length = ftell(file);
    if (length <= 0 || fseek(file, 0, SEEK_SET) != 0) {
        fclose(file);
        return NULL;
    }
    bytes = (uint8_t *)malloc((size_t)length);
    if (bytes == NULL) {
        fclose(file);
        return NULL;
    }
    read_length = fread(bytes, 1u, (size_t)length, file);
    fclose(file);
    if (read_length != (size_t)length) {
        free(bytes);
        return NULL;
    }
    *out_length = read_length;
    return bytes;
}

int main(int argc, char **argv)
{
    uint8_t *setup;
    size_t setup_length;
    size_t guard_offset;
    uint32_t chrnum;
    uint32_t body;
    uint32_t ai;
    char line[4096];
    FILE *manifest;
    int found_manifest_row = 0;
    uint8_t truncated[11] = {0};
    uint32_t ignored_body;
    uint32_t ignored_ai;
    int result;

    if (argc != 3) {
        fprintf(stderr, "usage: guard_dependency_smoke Dam.setup manifest\n");
        return 2;
    }
    setup = read_file(argv[1], &setup_length);
    if (setup == NULL) {
        fprintf(stderr, "setup payload could not be read\n");
        return 1;
    }
    result = find_first_guard(setup, setup_length, &guard_offset, &chrnum,
                              &body, &ai);
    if (result != 1 || guard_offset != 23000u || chrnum != 0u || body != 37u || ai != 1037u) {
        fprintf(stderr, "Dam GuardRecord mismatch result=%d offset=%zu chrnum=%u body=%u ai=%u\n",
                result, guard_offset, chrnum, body, ai);
        free(setup);
        return 1;
    }
    if (guard_body_ai(truncated, sizeof(truncated), 0u, &ignored_body, &ignored_ai) != 0 ||
        guard_body_ai(setup, setup_length, setup_length - 11u, &ignored_body, &ignored_ai) != 0) {
        fprintf(stderr, "truncated GuardRecord was not rejected\n");
        free(setup);
        return 1;
    }

    manifest = fopen(argv[2], "r");
    if (manifest == NULL) {
        fprintf(stderr, "dependency manifest could not be read\n");
        free(setup);
        return 1;
    }
    while (fgets(line, sizeof(line), manifest) != NULL) {
        if (strstr(line,
                   "stage:Dam|kind:character|object_index:0|object_type:9|"
                   "setup_offset:23000|model_index:37|model_name:greatguard2|") != NULL) {
            found_manifest_row = 1;
            break;
        }
    }
    fclose(manifest);
    free(setup);
    if (!found_manifest_row) {
        fprintf(stderr, "corrected Dam dependency row was not found\n");
        return 1;
    }
    printf("goldeneye_stage_setup_guard_dependency_v6_smoke: PASS "
           "stage=Dam guardOffset=23000 chrnum=0 bodyID=37 aiListID=1037 "
           "model=greatguard2 malformed=failClosed\n");
    return 0;
}
