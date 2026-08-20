#include "ge_source_reference_v6.h"

#include <stdio.h>
#include <string.h>

static int check(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "source-reference-v6 smoke: FAIL: %s\n", message);
        return 0;
    }
    return 1;
}

int main(void)
{
    static const uint32_t expected_nodes[GE_SOURCE_REFERENCE_V6_SCREEN_COUNT] =
        {3u, 42u, 3u, 0u, 90u};
    static const uint32_t expected_display_lists[GE_SOURCE_REFERENCE_V6_SCREEN_COUNT] =
        {1u, 23u, 1u, 9u, 46u};
    static const uint32_t expected_vertices[GE_SOURCE_REFERENCE_V6_SCREEN_COUNT] =
        {24u, 1363u, 438u, 381u, 765u};
    static const uint32_t expected_triangles[GE_SOURCE_REFERENCE_V6_SCREEN_COUNT] =
        {12u, 1021u, 341u, 268u, 440u};
    static const uint32_t expected_textures[GE_SOURCE_REFERENCE_V6_SCREEN_COUNT] =
        {5u, 1u, 2u, 6u, 84u};
    static const uint32_t expected_mips[GE_SOURCE_REFERENCE_V6_SCREEN_COUNT] =
        {0u, 0u, 1u, 4u, 0u};
    static const uint32_t expected_text[GE_SOURCE_REFERENCE_V6_SCREEN_COUNT] =
        {12u, 0u, 0u, 0u, 0u};
    static const uint32_t expected_switches[GE_SOURCE_REFERENCE_V6_SCREEN_COUNT] =
        {0u, 0u, 0u, 0u, 43u};
    static const uint32_t expected_commands[GE_SOURCE_REFERENCE_V6_SCREEN_COUNT] =
        {58u, 821u, 162u, 389u, 982u};
    static const uint32_t expected_raw_initializers[GE_SOURCE_REFERENCE_V6_SCREEN_COUNT] =
        {12u, 69u, 17u, 0u, 0u};
    static const uint32_t expected_resources[GE_SOURCE_REFERENCE_V6_SCREEN_COUNT] =
        {4u, 3u, 4u, 5u, 4u};
    static const uint64_t expected_command_order_hash[GE_SOURCE_REFERENCE_V6_SCREEN_COUNT] = {
        UINT64_C(0x8e915a7f4044c593), UINT64_C(0x9cc62b913ce52e5b),
        UINT64_C(0xbe5c050badae9682), UINT64_C(0xaf862a5762d1f654),
        UINT64_C(0x2bf6d0230e7ae7a1),
    };
    GESourceReferenceManifestV6 manifest;
    GESourceReferenceScreenV6 screen;
    GESourceReferenceScreenV6 page[2];
    GESourceReferenceResourceV6 resource;
    GESourceReferenceCommandV6 command;
    uint32_t page_count = 0u;
    uint32_t i;
    uint32_t command_totals[GE_SOURCE_REFERENCE_V6_SCREEN_COUNT] = {0u};
    uint32_t raw_initializer_totals[GE_SOURCE_REFERENCE_V6_SCREEN_COUNT] = {0u};
    uint32_t resource_totals[GE_SOURCE_REFERENCE_V6_SCREEN_COUNT] = {0u};
    int ok = 1;

    manifest = ge_source_reference_v6_manifest();
    ok &= check(manifest.status == GE_STATUS_OK, "manifest status");
    ok &= check(manifest.screen_count == GE_SOURCE_REFERENCE_V6_SCREEN_COUNT,
                "manifest screen count");
    ok &= check(manifest.resource_count == 20u, "manifest resource count");
    ok &= check(manifest.command_count == 45u, "manifest command-family count");
    ok &= check(manifest.issue_count == 0u, "manifest issue count");
    ok &= check(manifest.reference_kind ==
                    GE_SOURCE_REFERENCE_V6_REFERENCE_KIND_STATIC_SOURCE_COUNTS,
                "manifest static-reference kind");
    ok &= check(ge_source_reference_v6_validate_manifest(&manifest) == GE_STATUS_OK,
                "manifest validation");

    for (i = 0u; i < GE_SOURCE_REFERENCE_V6_SCREEN_COUNT; ++i) {
        ok &= check(ge_source_reference_v6_get_screen(i, &screen) == GE_STATUS_OK,
                    "screen copy-out");
        ok &= check(ge_source_reference_v6_validate_screen(&screen) == GE_STATUS_OK,
                    "screen validation");
        ok &= check(screen.screen_id == i, "screen order");
        ok &= check(screen.node_count == expected_nodes[i], "source node count");
        ok &= check(screen.display_list_count == expected_display_lists[i],
                    "source display-list count");
        ok &= check(screen.vertex_count == expected_vertices[i],
                    "source vertex count");
        ok &= check(screen.triangle_count == expected_triangles[i],
                    "expanded triangle count");
        ok &= check(screen.texture_count == expected_textures[i],
                    "source texture count");
        ok &= check(screen.mip_chain_count == expected_mips[i],
                    "source mip-chain count");
        ok &= check(screen.text_entry_count == expected_text[i],
                    "source text count");
        ok &= check(screen.switch_count == expected_switches[i],
                    "source switch count");
        ok &= check(screen.command_count == expected_commands[i],
                    "reachable Gfx command count");
        ok &= check(screen.resource_count == expected_resources[i],
                    "screen resource count");
        ok &= check(screen.command_order_hash == expected_command_order_hash[i],
                    "source command order hash");
        ok &= check(screen.unknown_command_count == 0u,
                    "unknown command diagnostic");
        printf("screen=%u nodes=%u display_lists=%u vertices=%u triangles=%u textures=%u mips=%u text=%u switches=%u commands=%u resources=%u order_hash=%016llx semantic_hash=%016llx\n",
               screen.screen_id, screen.node_count, screen.display_list_count,
               screen.vertex_count, screen.triangle_count, screen.texture_count,
               screen.mip_chain_count, screen.text_entry_count, screen.switch_count,
               screen.command_count, screen.resource_count,
               (unsigned long long)screen.command_order_hash,
               (unsigned long long)screen.semantic_hash);
    }

    for (i = 0u; i < ge_source_reference_v6_resource_count(); ++i) {
        ok &= check(ge_source_reference_v6_get_resource(i, &resource) == GE_STATUS_OK,
                    "resource copy-out");
        ok &= check(ge_source_reference_v6_validate_resource(&resource) == GE_STATUS_OK,
                    "resource validation");
        ok &= check(resource.screen_id < GE_SOURCE_REFERENCE_V6_SCREEN_COUNT,
                    "resource screen id");
        resource_totals[resource.screen_id] += 1u;
    }
    for (i = 0u; i < GE_SOURCE_REFERENCE_V6_SCREEN_COUNT; ++i) {
        ok &= check(resource_totals[i] == expected_resources[i],
                    "resource page coverage");
    }

    for (i = 0u; i < ge_source_reference_v6_command_count(); ++i) {
        ok &= check(ge_source_reference_v6_get_command(i, &command) == GE_STATUS_OK,
                    "command copy-out");
        ok &= check(ge_source_reference_v6_validate_command(&command) == GE_STATUS_OK,
                    "command validation");
        ok &= check(command.screen_id < GE_SOURCE_REFERENCE_V6_SCREEN_COUNT,
                    "command screen id");
        ok &= check(command.count != 0u, "command count nonzero");
        ok &= check((command.flags & GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SOURCE_ORDERED) == 0u,
                    "command records do not claim source draw order");
        if (command.command_kind == GE_SOURCE_REFERENCE_V6_COMMAND_RAW_INITIALIZER) {
            ok &= check((command.flags & GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_RAW_INITIALIZER) != 0u,
                        "raw initializer command flag");
            raw_initializer_totals[command.screen_id] += command.count;
        } else {
            ok &= check((command.flags & GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_RAW_INITIALIZER) == 0u,
                        "ordinary command raw flag");
        }
        command_totals[command.screen_id] += command.count;
    }
    for (i = 0u; i < GE_SOURCE_REFERENCE_V6_SCREEN_COUNT; ++i) {
        ok &= check(command_totals[i] == expected_commands[i],
                    "command family coverage");
        ok &= check(raw_initializer_totals[i] == expected_raw_initializers[i],
                    "raw initializer coverage");
    }

    ok &= check(ge_source_reference_v6_copy_screens(0u, 2u, page, &page_count) == GE_STATUS_OK,
                "screen page copy");
    ok &= check(page_count == 2u && page[0].screen_id == 0u && page[1].screen_id == 1u,
                "screen page bounds");
    ok &= check(ge_source_reference_v6_copy_screens(5u, 2u, page, &page_count) == GE_STATUS_OK &&
                    page_count == 0u,
                "empty screen page");
    ok &= check(ge_source_reference_v6_copy_commands(0u, 0u, NULL, &page_count) == GE_STATUS_OK &&
                    page_count == 0u,
                "zero-capacity command page");
    ok &= check(ge_source_reference_v6_copy_commands(0u, 1u, NULL, &page_count) == GE_STATUS_INVALID_ARGUMENT,
                "null command page rejection");

    screen = page[0];
    screen.flags |= UINT32_C(0x80000000);
    ok &= check(ge_source_reference_v6_validate_screen(&screen) == GE_STATUS_RESERVED_BITS,
                "screen reserved-bit rejection");
    ok &= check(ge_source_reference_v6_get_screen(0u, &screen) == GE_STATUS_OK,
                "screen restore");
    screen.node_count += 1u;
    ok &= check(ge_source_reference_v6_validate_screen(&screen) == GE_STATUS_ASSET_MISMATCH,
                "screen count mismatch diagnostic");
    manifest = ge_source_reference_v6_manifest();
    manifest.reference_kind = GE_SOURCE_REFERENCE_V6_REFERENCE_KIND_DYNAMIC_FRAME;
    ok &= check(ge_source_reference_v6_validate_manifest(&manifest) == GE_STATUS_RESERVED_BITS,
                "dynamic-reference kind rejection");
    manifest = ge_source_reference_v6_manifest();
    manifest.reserved0 = 1u;
    ok &= check(ge_source_reference_v6_validate_manifest(&manifest) == GE_STATUS_RESERVED_BITS,
                "manifest reserved-field rejection");

    printf("manifest_status=%u\n", ge_source_reference_v6_manifest().status);
    printf("manifest_source_generation=%016llx\n",
           (unsigned long long)ge_source_reference_v6_manifest().source_generation);
    printf("manifest_aggregate_hash=%016llx\n",
           (unsigned long long)ge_source_reference_v6_manifest().aggregate_hash);
    printf("source_reference_v6_smoke=%s\n", ok ? "PASS" : "FAIL");
    return ok ? 0 : 1;
}
