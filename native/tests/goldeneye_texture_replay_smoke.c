#include "goldeneye_native.h"

#include <errno.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/*
 * This test intentionally consumes only ignored, ROM-derived split payloads.
 * The payload facts are the provenance boundary established by M0; the native
 * decoder must not discover or read the ROM itself.
 */
enum {
    TEXTURE_AMMOCRATE1 = 0x21,
    TEXTURE_CRATEROPE = 0x25,
    TEXTURE_AMMOTEXT765 = 0x27,
};

typedef struct TextureCase {
    const char *name;
    const char *path;
    uint32_t texture_id;
    uint32_t source_size;
    uint64_t source_hash;
    uint32_t format;
    uint32_t compression;
    uint32_t width;
    uint32_t height;
    uint32_t pixel_byte_count;
    uint32_t palette_count;
    const uint8_t *first_pixels;
    size_t first_pixel_count;
} TextureCase;

#define REQUIRE(condition)                                                       \
    do {                                                                          \
        if (!(condition)) {                                                       \
            fprintf(stderr, "texture replay requirement failed at %s:%d: %s\n", \
                    __FILE__, __LINE__, #condition);                             \
            return 1;                                                             \
        }                                                                         \
    } while (0)

static uint64_t hash_byte(uint64_t hash, uint8_t value)
{
    return (hash ^ (uint64_t)value) * UINT64_C(1099511628211);
}

static uint64_t hash_bytes(const uint8_t *bytes, size_t count)
{
    uint64_t hash = UINT64_C(1469598103934665603);
    for (size_t index = 0; index < count; index++) {
        hash = hash_byte(hash, bytes[index]);
    }
    return hash;
}

static int read_payload(const char *path,
                        GETextureSourceBlobV3 *blob,
                        size_t expected_size)
{
    FILE *file = fopen(path, "rb");
    if (file == NULL) {
        fprintf(stderr, "unable to open texture payload %s: %s\n",
                path, strerror(errno));
        return 0;
    }

    memset(blob, 0, sizeof(*blob));
    blob->header.abi_version = GE_TEXTURE_REPLAY_ABI_VERSION;
    blob->header.struct_size = (uint32_t)sizeof(*blob);
    size_t count = fread(blob->bytes, 1u, sizeof(blob->bytes), file);
    int read_error = ferror(file);
    int has_extra = fgetc(file) != EOF;
    fclose(file);

    if (read_error || has_extra || count != expected_size) {
        fprintf(stderr,
                "texture payload layout mismatch for %s: expected=%zu got=%zu extra=%d\n",
                path, expected_size, count, has_extra);
        return 0;
    }
    blob->byte_count = (uint32_t)count;
    return 1;
}

static int result_is_deterministic(const GETextureDecodeResultV3 *first,
                                   const GETextureDecodeResultV3 *second)
{
    if (first == NULL || second == NULL || first->status != GE_STATUS_OK ||
        second->status != GE_STATUS_OK) {
        return 0;
    }
    return memcmp(first, second, sizeof(*first)) == 0;
}

static int check_texture_case(const TextureCase *test_case)
{
    GETextureSourceBlobV3 blob;
    REQUIRE(read_payload(test_case->path, &blob, test_case->source_size));
    REQUIRE(blob.texture_id == 0u);

    blob.texture_id = test_case->texture_id;
    REQUIRE(hash_bytes(blob.bytes, blob.byte_count) == test_case->source_hash);

    GETextureDecodeResultV3 first = ge_texture_decode_v3(blob);
    GETextureDecodeResultV3 second = ge_texture_decode_v3(blob);
    REQUIRE(first.status == GE_STATUS_OK);
    REQUIRE(result_is_deterministic(&first, &second));
    REQUIRE(first.header.abi_version == GE_TEXTURE_REPLAY_ABI_VERSION);
    REQUIRE(first.header.struct_size == sizeof(first));
    REQUIRE(first.texture_id == test_case->texture_id);
    REQUIRE(first.source_format == test_case->format);
    REQUIRE(first.source_compression == test_case->compression);
    REQUIRE(first.width == test_case->width);
    REQUIRE(first.height == test_case->height);
    REQUIRE(first.mip_count == 1u);
    REQUIRE(first.pixel_byte_count == test_case->pixel_byte_count);
    REQUIRE(first.palette_count == test_case->palette_count);
    REQUIRE(first.source_hash == test_case->source_hash);
    REQUIRE(first.decoded_hash != 0u);
    REQUIRE(first.mip_offsets[0] == 0u);
    REQUIRE(first.mip_widths[0] == test_case->width);
    REQUIRE(first.mip_heights[0] == test_case->height);
    REQUIRE(memcmp(first.pixels, test_case->first_pixels,
                   test_case->first_pixel_count) == 0);

    printf("texture decode: PASS name=%s id=0x%02x format=%u compression=%u "
           "size=%ux%u pixels=%u palette=%u sourceHash=%016llx "
           "decodedHash=%016llx\n",
           test_case->name, test_case->texture_id, first.source_format,
           first.source_compression, first.width, first.height,
           first.pixel_byte_count, first.palette_count,
           (unsigned long long)first.source_hash,
           (unsigned long long)first.decoded_hash);
    return 0;
}

static int check_malformed(const TextureCase *test_case)
{
    GETextureSourceBlobV3 blob;
    REQUIRE(read_payload(test_case->path, &blob, test_case->source_size));
    blob.texture_id = test_case->texture_id;

    GETextureSourceBlobV3 malformed = blob;
    malformed.header.abi_version++;
    REQUIRE(ge_texture_decode_v3(malformed).status == GE_STATUS_INVALID_VERSION);

    malformed = blob;
    malformed.header.struct_size--;
    REQUIRE(ge_texture_decode_v3(malformed).status == GE_STATUS_INVALID_SIZE);

    malformed = blob;
    malformed.reserved = 1u;
    REQUIRE(ge_texture_decode_v3(malformed).status != GE_STATUS_OK);

    malformed = blob;
    malformed.byte_count = 0u;
    REQUIRE(ge_texture_decode_v3(malformed).status != GE_STATUS_OK);

    malformed = blob;
    malformed.byte_count = GE_TEXTURE_SOURCE_BLOB_CAPACITY + 1u;
    REQUIRE(ge_texture_decode_v3(malformed).status != GE_STATUS_OK);

    malformed = blob;
    /* Remove a material portion of the stream; legal trailing bit padding is
       allowed by the PD reader, so a one-byte cut is not necessarily a
       semantic truncation. */
    malformed.byte_count = 7u;
    REQUIRE(ge_texture_decode_v3(malformed).status != GE_STATUS_OK);

    malformed = blob;
    /* Force an unsupported PD header instead of relying on a payload checksum
       that the source container does not carry. */
    malformed.bytes[0] = 0xffu;
    REQUIRE(ge_texture_decode_v3(malformed).status != GE_STATUS_OK);

    printf("texture malformed: PASS name=%s\n", test_case->name);
    return 0;
}

static int read_prop_blob(const char *path, GEClassicAssetBlobV2 *blob)
{
    FILE *file = fopen(path, "rb");
    if (file == NULL) {
        fprintf(stderr, "unable to open prop payload %s: %s\n",
                path, strerror(errno));
        return 0;
    }

    memset(blob, 0, sizeof(*blob));
    blob->header.abi_version = GE_NATIVE_ABI_VERSION;
    blob->header.struct_size = (uint32_t)sizeof(*blob);
    size_t count = fread(blob->bytes, 1u, sizeof(blob->bytes), file);
    int read_error = ferror(file);
    int has_extra = fgetc(file) != EOF;
    fclose(file);
    if (read_error || has_extra || count != 1488u) {
        fprintf(stderr,
                "prop payload layout mismatch for %s: expected=1488 got=%zu extra=%d\n",
                path, count, has_extra);
        return 0;
    }
    blob->byte_count = (uint32_t)count;
    return 1;
}

static void fill_material_set(GETextureMaterialSetV3 *materials)
{
    memset(materials, 0, sizeof(*materials));
    materials->header.abi_version = GE_NATIVE_ABI_VERSION;
    materials->header.struct_size = (uint32_t)sizeof(*materials);
    materials->material_count = GE_TEXTURE_MATERIAL_CAPACITY;

    materials->materials[0] = (GETextureMaterialDescriptorV3){
        TEXTURE_AMMOCRATE1, 64u, 32u, 7u, GE_TEXTURE_FORMAT_I8,
        GE_TEXTURE_COMPRESSION_HUFFMAN_BLUR, 0u, 0u, 1610u,
        UINT64_C(0x96c331f295054786),
    };
    materials->materials[1] = (GETextureMaterialDescriptorV3){
        TEXTURE_AMMOTEXT765, 128u, 16u, 7u, GE_TEXTURE_FORMAT_IA4,
        GE_TEXTURE_COMPRESSION_HUFFMAN_LOOKUP, 2u, 2u, 551u,
        UINT64_C(0x0b91dd635318355a),
    };
    materials->materials[2] = (GETextureMaterialDescriptorV3){
        TEXTURE_CRATEROPE, 32u, 32u, 6u, GE_TEXTURE_FORMAT_RGBA16_CI8,
        0u, 2u, 2u, 1003u, UINT64_C(0xbc68a84830d902be),
    };
}

static int check_textured_replay(const char *path)
{
    GEClassicAssetBlobV2 prop_blob;
    REQUIRE(read_prop_blob(path, &prop_blob));

    GETextureMaterialSetV3 materials;
    fill_material_set(&materials);
    GETexturedReplayResultV3 first =
        ge_classic_replay_textured_prop_v3(prop_blob, materials);
    GETexturedReplayResultV3 second =
        ge_classic_replay_textured_prop_v3(prop_blob, materials);
    REQUIRE(first.status == GE_STATUS_OK);
    REQUIRE(first.header.abi_version == GE_NATIVE_ABI_VERSION);
    REQUIRE(first.header.struct_size == sizeof(first));
    REQUIRE(memcmp(&first, &second, sizeof(first)) == 0);
    REQUIRE(first.commands_processed == 24u);
    REQUIRE(first.draw_count == 4u);
    REQUIRE(first.vertex_count == 40u);
    REQUIRE(first.triangle_count == 20u);
    REQUIRE(first.packet_hash != 0u);
    REQUIRE(first.event_hash != 0u);
    REQUIRE(first.material_hash != 0u);

    uint32_t seen_texture_ids = 0u;
    int saw_nonzero_uv = 0;
    for (uint32_t draw_index = 0u; draw_index < first.draw_count; draw_index++) {
        const GETexturedDrawPacketV3 *draw = &first.draws[draw_index];
        REQUIRE(draw->header.abi_version == GE_NATIVE_ABI_VERSION);
        REQUIRE(draw->header.struct_size == sizeof(*draw));
        REQUIRE(draw->packet_version == GE_TEXTURE_REPLAY_PACKET_VERSION);
        REQUIRE(draw->vertex_count > 0u &&
                draw->vertex_count <= GE_CLASSIC_CACHE_CAPACITY);
        REQUIRE(draw->triangle_count > 0u &&
                draw->triangle_count <= GE_CLASSIC_TRIANGLE_CAPACITY);
        REQUIRE(draw->packet_hash != 0u);
        REQUIRE(draw->texture_id == draw->material.texture_id);
        REQUIRE((draw->material.material_flags & (1u << 0)) != 0u);
        REQUIRE((draw->material.material_flags & (1u << 1)) != 0u);
        REQUIRE((draw->material.material_flags & (1u << 3)) != 0u);
        REQUIRE(draw->material.state_hash != 0u);
        if (draw->texture_id == TEXTURE_AMMOCRATE1) {
            seen_texture_ids |= 1u << 0;
        } else if (draw->texture_id == TEXTURE_AMMOTEXT765) {
            seen_texture_ids |= 1u << 1;
        } else if (draw->texture_id == TEXTURE_CRATEROPE) {
            seen_texture_ids |= 1u << 2;
            REQUIRE((draw->material.material_flags & (1u << 2)) != 0u);
            REQUIRE((draw->material.material_flags & (1u << 4)) != 0u);
            REQUIRE(draw->material.tlut_count == GE_TEXTURE_PALETTE_ENTRY_CAPACITY);
        } else {
            REQUIRE(0);
        }
        for (uint32_t vertex_index = 0u; vertex_index < draw->vertex_count;
             vertex_index++) {
            const GETexturedVertexV3 *vertex = &draw->vertices[vertex_index];
            REQUIRE(vertex->source_vertex < GE_CLASSIC_CACHE_CAPACITY);
            REQUIRE(isfinite(vertex->x) && isfinite(vertex->y) &&
                    isfinite(vertex->z) && isfinite(vertex->w) &&
                    isfinite(vertex->s) && isfinite(vertex->t));
            saw_nonzero_uv |= vertex->s != 0.0f || vertex->t != 0.0f;
        }
        for (uint32_t triangle_index = 0u;
             triangle_index < draw->triangle_count; triangle_index++) {
            const GEClassicTriangleV2 *triangle = &draw->triangles[triangle_index];
            REQUIRE(triangle->a < draw->vertex_count &&
                    triangle->b < draw->vertex_count &&
                    triangle->c < draw->vertex_count);
        }
    }
    REQUIRE(seen_texture_ids == 0x7u);
    REQUIRE(saw_nonzero_uv);

    GETextureMaterialSetV3 malformed = materials;
    malformed.header.abi_version++;
    REQUIRE(ge_classic_replay_textured_prop_v3(prop_blob, malformed).status ==
            GE_STATUS_INVALID_VERSION);
    malformed = materials;
    malformed.materials[0].width++;
    REQUIRE(ge_classic_replay_textured_prop_v3(prop_blob, malformed).status ==
            GE_STATUS_ASSET_MISMATCH);
    malformed = materials;
    malformed.materials[1].texture_id = malformed.materials[0].texture_id;
    REQUIRE(ge_classic_replay_textured_prop_v3(prop_blob, malformed).status ==
            GE_STATUS_MALFORMED_STREAM);
    malformed = materials;
    malformed.materials[0].source_hash = 0u;
    REQUIRE(ge_classic_replay_textured_prop_v3(prop_blob, malformed).status ==
            GE_STATUS_MALFORMED_STREAM);

    GEClassicAssetBlobV2 malformed_prop = prop_blob;
    malformed_prop.byte_count--;
    REQUIRE(ge_classic_replay_textured_prop_v3(prop_blob, materials).status ==
            GE_STATUS_OK);
    REQUIRE(ge_classic_replay_textured_prop_v3(malformed_prop, materials).status !=
            GE_STATUS_OK);

    printf("textured replay: PASS path=%s commands=%u draws=%u vertices=%u "
           "triangles=%u packetHash=%llu eventHash=%llu materialHash=%llu\n",
           path, first.commands_processed, first.draw_count, first.vertex_count,
           first.triangle_count, (unsigned long long)first.packet_hash,
           (unsigned long long)first.event_hash,
           (unsigned long long)first.material_hash);
    return 0;
}

static int check_v1_v2_regressions(void)
{
    /* These are the frozen values from the completed native goals. */
    GEInitRequestV1 request = {
        {GE_NATIVE_ABI_VERSION, sizeof(GEInitRequestV1)}, 0u, 0u,
    };
    REQUIRE(ge_native_initialize(request) == GE_STATUS_OK);
    GEFixtureResultV1 fixture = ge_native_fixture_packet();
    REQUIRE(fixture.status == GE_STATUS_OK);
    REQUIRE(fixture.packet.packet_hash == UINT64_C(1522029846112142469));
    REQUIRE(ge_native_shutdown() == GE_STATUS_OK);

    GEClassicReplayFixtureV2 classic_fixture = ge_classic_nested_fixture();
    GEClassicReplayResultV2 classic = ge_classic_replay_fixture(classic_fixture);
    REQUIRE(classic.status == GE_STATUS_OK);
    REQUIRE(classic.packet_hash == UINT64_C(65363635960931316));
    REQUIRE(classic.event_hash == UINT64_C(905714786767796339));
    REQUIRE(classic.state_hash == UINT64_C(10439205544326414085));
    printf("V1/V2 regression hashes: PASS v1=%llu v2Packet=%llu v2Event=%llu v2State=%llu\n",
           (unsigned long long)fixture.packet.packet_hash,
           (unsigned long long)classic.packet_hash,
           (unsigned long long)classic.event_hash,
           (unsigned long long)classic.state_hash);
    return 0;
}

int main(int argc, char **argv)
{
    const char *root = argc > 1 ? argv[1] : "assets/images/split";
    const char *prop_path = argc > 2 ? argv[2] :
        "build/native/classic-prop/Pammo_crate1Z.bin";
    char paths[3][1024];
    (void)snprintf(paths[0], sizeof(paths[0]), "%s/AMMOCRATE1.bin", root);
    (void)snprintf(paths[1], sizeof(paths[1]), "%s/AMMOTEXT765.bin", root);
    (void)snprintf(paths[2], sizeof(paths[2]), "%s/CRATEROPE.bin", root);

    static const uint8_t ammo_first[] = {
        0x63, 0x63, 0x63, 0xff, 0x72, 0x72, 0x72, 0xff,
        0x6b, 0x6b, 0x6b, 0xff, 0x5e, 0x5e, 0x5e, 0xff,
    };
    static const uint8_t ammo_text_first[] = {
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x80, 0x80, 0x80, 0x00, 0xa0, 0xa0, 0xa0, 0xff,
    };
    static const uint8_t crate_rope_first[] = {
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    };
    const TextureCase cases[] = {
        {
            "AMMOCRATE1", paths[0], TEXTURE_AMMOCRATE1, 1610u,
            UINT64_C(0x96c331f295054786), GE_TEXTURE_FORMAT_I8,
            GE_TEXTURE_COMPRESSION_HUFFMAN_BLUR, 64u, 32u, 8192u, 0u,
            ammo_first, sizeof(ammo_first),
        },
        {
            "AMMOTEXT765", paths[1], TEXTURE_AMMOTEXT765, 551u,
            UINT64_C(0x0b91dd635318355a), GE_TEXTURE_FORMAT_IA4,
            GE_TEXTURE_COMPRESSION_HUFFMAN_LOOKUP, 128u, 16u, 8192u, 0u,
            ammo_text_first, sizeof(ammo_text_first),
        },
        {
            "CRATEROPE", paths[2], TEXTURE_CRATEROPE, 1003u,
            UINT64_C(0xbc68a84830d902be), GE_TEXTURE_FORMAT_RGBA16_CI8,
            0u, 32u, 32u, 4096u, 256u,
            crate_rope_first, sizeof(crate_rope_first),
        },
    };

    REQUIRE(check_v1_v2_regressions() == 0);
    REQUIRE(check_textured_replay(prop_path) == 0);
    for (size_t index = 0; index < sizeof(cases) / sizeof(cases[0]); index++) {
        REQUIRE(check_texture_case(&cases[index]) == 0);
        REQUIRE(check_malformed(&cases[index]) == 0);
    }
    puts("goldeneye_texture_replay_smoke: PASS");
    return 0;
}
