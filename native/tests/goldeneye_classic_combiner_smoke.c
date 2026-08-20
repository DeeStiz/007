#include "ge_classic_combiner.h"

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define REQUIRE(condition)                                                       \
    do {                                                                          \
        if (!(condition)) {                                                       \
            fprintf(stderr, "classic combiner requirement failed at %s:%d: %s\n", \
                    __FILE__, __LINE__, #condition);                             \
            return 1;                                                             \
        }                                                                         \
    } while (0)

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

static int check_draw_keys(const GEClassicCombinerLoweringResultV4 *result)
{
    static const uint32_t offsets[] = { 0x50u, 0x68u, 0x90u, 0xb0u };
    static const uint32_t texture_ids[] = { 0x21u, 0x21u, 0x27u, 0x25u };
    static const uint32_t triangle_counts[] = { 8u, 4u, 4u, 4u };
    static const uint32_t render_modes[] = {
        UINT32_C(0xc4112078), UINT32_C(0xc4112078),
        UINT32_C(0xc4104dd8), UINT32_C(0xc4104dd8),
    };

    for (uint32_t index = 0; index < GE_CLASSIC_COMBINER_DRAW_CAPACITY; index++) {
        const GEClassicCombinerDrawKeyV4 *draw = &result->draws[index];
        REQUIRE(draw->header.abi_version == GE_NATIVE_ABI_VERSION);
        REQUIRE(draw->header.struct_size == sizeof(*draw));
        REQUIRE(draw->packet_version == GE_CLASSIC_COMBINER_PACKET_VERSION);
        REQUIRE(draw->source_command_offset == offsets[index]);
        REQUIRE(draw->texture_id == texture_ids[index]);
        REQUIRE(draw->triangle_group_count == triangle_counts[index]);
        REQUIRE(draw->key_hash != 0u);
        REQUIRE(draw->combiner.raw_w0 == UINT32_C(0xfc26a004));
        REQUIRE(draw->combiner.raw_w1 == UINT32_C(0x1f1093ff));
        REQUIRE(draw->other_mode.raw_h == UINT32_C(0x00112000));
        REQUIRE(draw->other_mode.cycle_type == 1u);
        REQUIRE(draw->other_mode.texture_lod == 1u);
        REQUIRE(draw->other_mode.texture_filter == 2u);
        REQUIRE(draw->render_mode.raw_mode == render_modes[index]);
        REQUIRE(draw->render_mode.blender[0].m1a == 3u);
        REQUIRE(draw->render_mode.blender[0].m1b == 1u);
        REQUIRE(draw->render_mode.blender[0].m2a == 0u);
        REQUIRE(draw->render_mode.blender[0].m2b == 0u);
        REQUIRE(draw->render_mode.blender[1].m1a == 0u);
        REQUIRE(draw->render_mode.blender[1].m1b == 0u);
        REQUIRE(draw->render_mode.blender[1].m2a == 1u);
        REQUIRE(draw->render_mode.blender[1].m2b == (index < 2u ? 1u : 0u));
        REQUIRE((draw->material_flags & GE_CLASSIC_COMBINER_FLAG_SOURCE_SETUP) != 0u);
        REQUIRE((draw->material_flags & GE_CLASSIC_COMBINER_FLAG_TEXEL0_SHADE) != 0u);
        REQUIRE((draw->material_flags & GE_CLASSIC_COMBINER_FLAG_TEXTURED) != 0u);
        REQUIRE((draw->material_flags & GE_CLASSIC_COMBINER_FLAG_DEFERRED_DEPTH) != 0u);
        REQUIRE((draw->material_flags & GE_CLASSIC_COMBINER_FLAG_DEFERRED_FOG) != 0u);
        REQUIRE((draw->material_flags & GE_CLASSIC_COMBINER_FLAG_DEFERRED_ALPHA) != 0u);
        REQUIRE((draw->material_flags & GE_CLASSIC_COMBINER_FLAG_DEFERRED_COVERAGE) != 0u);
        if (index < 2u) {
            REQUIRE((draw->material_flags & GE_CLASSIC_COMBINER_FLAG_OPAQUE_PRIMARY) != 0u);
            REQUIRE(draw->render_mode.z_compare == 1u);
            REQUIRE(draw->render_mode.z_update == 1u);
            REQUIRE(draw->render_mode.z_mode == 0u);
        } else {
            REQUIRE((draw->material_flags & GE_CLASSIC_COMBINER_FLAG_OPAQUE_PRIMARY) == 0u);
            REQUIRE(draw->render_mode.z_compare == 1u);
            REQUIRE(draw->render_mode.z_update == 0u);
            REQUIRE(draw->render_mode.z_mode == 3u);
        }
    }
    return 0;
}

static int check_selector_fields(const GEClassicCombinerStateV4 *combiner)
{
    const GEClassicCombinerCycleV4 *cycle0 = &combiner->cycles[0];
    const GEClassicCombinerCycleV4 *cycle1 = &combiner->cycles[1];
    REQUIRE(cycle0->rgb_a == 2u);
    REQUIRE(cycle0->rgb_b == 1u);
    REQUIRE(cycle0->rgb_c == 13u);
    REQUIRE(cycle0->rgb_d == 1u);
    REQUIRE(cycle0->alpha_a == 2u);
    REQUIRE(cycle0->alpha_b == 1u);
    REQUIRE(cycle0->alpha_c == 0u);
    REQUIRE(cycle0->alpha_d == 1u);
    REQUIRE(cycle1->rgb_a == 0u);
    REQUIRE(cycle1->rgb_b == 15u);
    REQUIRE(cycle1->rgb_c == 4u);
    REQUIRE(cycle1->rgb_d == 7u);
    REQUIRE(cycle1->alpha_a == 0u);
    REQUIRE(cycle1->alpha_b == 7u);
    REQUIRE(cycle1->alpha_c == 4u);
    REQUIRE(cycle1->alpha_d == 7u);
    return 0;
}

static int check_malformed(const GEClassicCombinerInputV4 *input)
{
    GEClassicCombinerInputV4 malformed = *input;
    malformed.header.abi_version++;
    REQUIRE(ge_classic_lower_combiner_v4(malformed).status ==
            GE_STATUS_INVALID_VERSION);

    malformed = *input;
    malformed.reserved0 = 1u;
    REQUIRE(ge_classic_lower_combiner_v4(malformed).status ==
            GE_STATUS_RESERVED_BITS);

    malformed = *input;
    malformed.setup[0].w0 = UINT32_C(0xba001400);
    REQUIRE(ge_classic_lower_combiner_v4(malformed).status ==
            GE_STATUS_ASSET_MISMATCH);

    malformed = *input;
    malformed.commands[1].w0 = UINT32_C(0xba001000);
    REQUIRE(ge_classic_lower_combiner_v4(malformed).status ==
            GE_STATUS_MALFORMED_STREAM);

    malformed = *input;
    malformed.commands[13].w1 |= 1u;
    REQUIRE(ge_classic_lower_combiner_v4(malformed).status ==
            GE_STATUS_MALFORMED_STREAM);

    malformed = *input;
    malformed.commands[15].w0 = UINT32_C(0xfc000000);
    malformed.commands[15].w1 = 0u;
    REQUIRE(ge_classic_lower_combiner_v4(malformed).status ==
            GE_STATUS_UNSUPPORTED_COMMAND);

    malformed = *input;
    malformed.commands[21].w1 = 1u;
    REQUIRE(ge_classic_lower_combiner_v4(malformed).status ==
            GE_STATUS_MALFORMED_STREAM);

    return 0;
}

int main(int argc, char **argv)
{
    const char *path = argc > 1 ? argv[1] :
        "build/native/classic-prop/Pammo_crate1Z.bin";
    GEClassicAssetBlobV2 blob;
    REQUIRE(read_prop_blob(path, &blob));

    GEClassicCombinerInputV4 input =
        ge_classic_ammo_crate_combiner_input_v4(blob);
    REQUIRE(input.header.abi_version == GE_CLASSIC_COMBINER_REPLAY_ABI_VERSION);
    REQUIRE(input.header.struct_size == sizeof(input));
    REQUIRE(input.setup_command_count == 3u);
    REQUIRE(input.command_count == 22u);
    REQUIRE(input.setup[0].w0 == UINT32_C(0xba001402));
    REQUIRE(input.setup[1].w0 == UINT32_C(0xfc26a004));
    REQUIRE(input.setup[2].w0 == UINT32_C(0xb900031d));

    GEClassicCombinerLoweringResultV4 first =
        ge_classic_lower_combiner_v4(input);
    GEClassicCombinerLoweringResultV4 second =
        ge_classic_lower_ammo_crate_v4(blob);
    REQUIRE(first.status == GE_STATUS_OK);
    REQUIRE(second.status == GE_STATUS_OK);
    REQUIRE(memcmp(&first, &second, sizeof(first)) == 0);
    REQUIRE(first.header.abi_version == GE_NATIVE_ABI_VERSION);
    REQUIRE(first.header.struct_size == sizeof(first));
    REQUIRE(first.commands_processed == 22u);
    REQUIRE(first.setup_commands_processed == 3u);
    REQUIRE(first.draw_count == GE_CLASSIC_COMBINER_DRAW_CAPACITY);
    REQUIRE(first.setup_hash != 0u);
    REQUIRE(first.event_hash != 0u);
    REQUIRE(first.key_hash != 0u);
    REQUIRE(first.source_setup.setup_hash == first.setup_hash);
    REQUIRE(first.source_setup.header.abi_version == GE_NATIVE_ABI_VERSION);
    REQUIRE(first.source_setup.header.struct_size == sizeof(first.source_setup));
    REQUIRE(first.source_setup.combiner.raw_w0 == UINT32_C(0xfc26a004));
    REQUIRE(first.source_setup.combiner.raw_w1 == UINT32_C(0x1f1093ff));
    REQUIRE(first.source_setup.other_mode.raw_h == UINT32_C(0x00100000));
    REQUIRE(first.source_setup.other_mode.raw_l == UINT32_C(0xc4112078));
    REQUIRE(check_selector_fields(&first.source_setup.combiner) == 0);
    REQUIRE(check_draw_keys(&first) == 0);
    REQUIRE(check_malformed(&input) == 0);

    GEClassicAssetBlobV2 malformed_blob = blob;
    malformed_blob.header.abi_version++;
    REQUIRE(ge_classic_lower_ammo_crate_v4(malformed_blob).status ==
            GE_STATUS_INVALID_VERSION);

    malformed_blob = blob;
    malformed_blob.byte_count--;
    REQUIRE(ge_classic_lower_ammo_crate_v4(malformed_blob).status ==
            GE_STATUS_ASSET_MISMATCH);

    printf("classic combiner: PASS commands=%u setup=%u draws=%u "
           "setupHash=%llu eventHash=%llu keyHash=%llu\n",
           first.commands_processed, first.setup_commands_processed,
           first.draw_count, (unsigned long long)first.setup_hash,
           (unsigned long long)first.event_hash,
           (unsigned long long)first.key_hash);
    for (uint32_t index = 0; index < first.draw_count; index++) {
        const GEClassicCombinerDrawKeyV4 *draw = &first.draws[index];
        printf("draw[%u]: offset=0x%02x texture=0x%02x triangles=%u "
               "mode=0x%08x hash=%llu\n",
               index, draw->source_command_offset, draw->texture_id,
               draw->triangle_group_count, draw->render_mode.raw_mode,
               (unsigned long long)draw->key_hash);
    }
    puts("goldeneye_classic_combiner_smoke: PASS");
    return 0;
}
