#include "ge_source_gbi_v6.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

static uint32_t op(uint32_t opcode)
{
    return opcode << 24;
}

static void init_packet(GEGBISourcePacketV6 *packet)
{
    memset(packet, 0, sizeof(*packet));
    packet->header.abi_version = GE_NATIVE_ABI_VERSION;
    packet->header.struct_size = (uint32_t)sizeof(*packet);
    packet->packet_version = GE_SOURCE_GBI_V6_PACKET_VERSION;
    packet->dialect = GE_SOURCE_GBI_V6_DIALECT_F3DEX2;
    packet->root_list_handle = UINT32_C(0x1000);
    packet->list_count = 2u;
    packet->lists[0].handle = UINT32_C(0x1000);
    packet->lists[0].first_command = 0u;
    packet->lists[0].command_count = 2u;
    packet->lists[1].handle = UINT32_C(0x2000);
    packet->lists[1].first_command = 2u;
    packet->lists[1].command_count = 14u;

    packet->vertex_count = 3u;
    packet->vertices[0].x = -10;
    packet->vertices[0].y = -10;
    packet->vertices[0].r = 255u;
    packet->vertices[0].a = 255u;
    packet->vertices[1].x = 10;
    packet->vertices[1].y = -10;
    packet->vertices[1].g = 255u;
    packet->vertices[1].a = 255u;
    packet->vertices[2].x = 0;
    packet->vertices[2].y = 10;
    packet->vertices[2].b = 255u;
    packet->vertices[2].a = 255u;
    packet->vertex_resource_count = 1u;
    packet->vertex_resources[0].handle = UINT32_C(0x3000);
    packet->vertex_resources[0].vertex_count = 3u;

    packet->matrix_count = 1u;
    packet->matrices[0].handle = UINT32_C(0x4000);
    packet->matrices[0].values[0] = 65536;
    packet->matrices[0].values[5] = 65536;
    packet->matrices[0].values[10] = 65536;
    packet->matrices[0].values[15] = 65536;

    packet->viewport_count = 1u;
    packet->viewports[0].handle = UINT32_C(0x4100);
    packet->viewports[0].values[0] = 160;
    packet->viewports[0].values[1] = 120;
    packet->viewports[0].values[2] = 1;
    packet->viewports[0].values[4] = 160;
    packet->viewports[0].values[5] = 120;

    packet->image_count = 1u;
    packet->images[0].handle = UINT32_C(0x5000);
    packet->images[0].format = 0u;
    packet->images[0].size = 2u;
    packet->images[0].width = 2u;
    packet->images[0].height = 2u;
}

static GEGBISourcePacketV6 make_f3dex2_packet(void)
{
    GEGBISourcePacketV6 packet;
    init_packet(&packet);
    packet.command_count = 16u;

    /* Root: push child, then terminate. */
    packet.commands[0].w0 = op(GE_SOURCE_GBI_V6_OP_DL_2);
    packet.commands[0].w1 = UINT32_C(0x2000);
    packet.commands[1].w0 = op(GE_SOURCE_GBI_V6_OP_ENDDL_2);

    /* Child uses F3DEX2 encodings and exercises state plus one triangle. */
    packet.commands[2].w0 = op(GE_SOURCE_GBI_V6_OP_MTX_2) | 0x00000002u;
    packet.commands[2].w1 = UINT32_C(0x4000);
    packet.commands[3].w0 = op(GE_SOURCE_GBI_V6_OP_MOVEMEM_2) | 8u;
    packet.commands[3].w1 = UINT32_C(0x4100);
    packet.commands[4].w0 = op(GE_SOURCE_GBI_V6_OP_VTX_2) |
                            (3u << 12) | (3u << 1);
    packet.commands[4].w1 = UINT32_C(0x3000);
    packet.commands[5].w0 = op(GE_SOURCE_GBI_V6_OP_TRI1_2) | 0x00000204u;
    packet.commands[6].w0 = op(GE_SOURCE_GBI_V6_OP_SETTIMG) |
                            (2u << 19) | 1u;
    packet.commands[6].w1 = UINT32_C(0x5000);
    packet.commands[7].w0 = op(GE_SOURCE_GBI_V6_OP_SETTILE) |
                            (2u << 19) | (1u << 9);
    packet.commands[7].w1 = 0u;
    packet.commands[8].w0 = op(GE_SOURCE_GBI_V6_OP_LOADBLOCK) | (1u << 12);
    packet.commands[8].w1 = (7u << 12) | 1u;
    packet.commands[9].w0 = op(GE_SOURCE_GBI_V6_OP_TEXTURE_2) |
                            (1u << 11) | (1u << 8) | (1u << 1);
    packet.commands[9].w1 = (1u << 16) | 1u;
    packet.commands[10].w0 = op(GE_SOURCE_GBI_V6_OP_SETCOMBINE) | 0x00123456u;
    packet.commands[10].w1 = UINT32_C(0xabcdef01);
    packet.commands[11].w0 = op(GE_SOURCE_GBI_V6_OP_SETPRIMCOLOR);
    packet.commands[11].w1 = UINT32_C(0x102030ff);
    packet.commands[12].w0 = op(GE_SOURCE_GBI_V6_OP_SETSCISSOR) |
                             (1u << 12) | 2u;
    packet.commands[12].w1 = (3u << 12) | 4u;
    packet.commands[13].w0 = op(GE_SOURCE_GBI_V6_OP_TEXRECT) |
                             (20u << 12) | 10u;
    packet.commands[13].w1 = (1u << 24) | (2u << 12) | 3u;
    packet.commands[14].w0 = op(GE_SOURCE_GBI_V6_OP_RDPHALF_1);
    packet.commands[14].w1 = UINT32_C(0x00100020);
    packet.commands[15].w0 = op(GE_SOURCE_GBI_V6_OP_ENDDL_2);
    return packet;
}

static GEGBISourcePacketV6 make_old_f3d_packet(void)
{
    GEGBISourcePacketV6 packet;
    init_packet(&packet);
    packet.dialect = GE_SOURCE_GBI_V6_DIALECT_CLASSIC_GE_F3D;
    packet.list_count = 1u;
    packet.lists[0].command_count = 5u;
    packet.command_count = 5u;
    packet.commands[0].w0 = op(GE_SOURCE_GBI_V6_OP_MTX) | (2u << 16);
    packet.commands[0].w1 = UINT32_C(0x4000);
    packet.commands[1].w0 = op(GE_SOURCE_GBI_V6_OP_VTX) | 3u;
    packet.commands[1].w1 = UINT32_C(0x3000);
    packet.commands[2].w0 = op(GE_SOURCE_GBI_V6_OP_SETTEX) | 0x00010000u;
    packet.commands[2].w1 = UINT32_C(0x00000021);
    packet.commands[3].w0 = op(GE_SOURCE_GBI_V6_OP_TRI1);
    packet.commands[3].w1 = (10u << 16) | (20u << 8);
    packet.commands[4].w0 = op(GE_SOURCE_GBI_V6_OP_ENDDL);
    return packet;
}

static GEGBISourcePacketV6 make_overwrite_packet(void)
{
    GEGBISourcePacketV6 packet = make_f3dex2_packet();
    packet.command_count = 20u;
    packet.lists[1].command_count = 18u;
    packet.vertex_count = 6u;
    packet.vertex_resources[1].handle = UINT32_C(0x3010);
    packet.vertex_resources[1].first_vertex = 3u;
    packet.vertex_resources[1].vertex_count = 3u;
    packet.vertex_resource_count = 2u;
    packet.vertices[3] = packet.vertices[0];
    packet.vertices[3].x = -20;
    packet.vertices[4] = packet.vertices[1];
    packet.vertices[4].x = 20;
    packet.vertices[5] = packet.vertices[2];
    packet.vertices[5].y = 20;

    /* Reuse cache slots 0..2 after the first draw, then draw a new state. */
    packet.commands[15].w0 = op(GE_SOURCE_GBI_V6_OP_NOOP);
    packet.commands[15].w1 = 0u;
    packet.commands[16].w0 = op(GE_SOURCE_GBI_V6_OP_VTX_2) |
                             (3u << 12) | (3u << 1);
    packet.commands[16].w1 = UINT32_C(0x3010);
    packet.commands[17].w0 = op(GE_SOURCE_GBI_V6_OP_SETCOMBINE) | 0x0000fedcu;
    packet.commands[17].w1 = UINT32_C(0x13572468);
    packet.commands[18].w0 = op(GE_SOURCE_GBI_V6_OP_TRI1_2) | 0x00000204u;
    packet.commands[19].w0 = op(GE_SOURCE_GBI_V6_OP_ENDDL_2);
    return packet;
}

static GEGBISourcePacketV6 make_other_mode_packet(void)
{
    GEGBISourcePacketV6 packet;
    memset(&packet, 0, sizeof(packet));
    packet.header.abi_version = GE_NATIVE_ABI_VERSION;
    packet.header.struct_size = (uint32_t)sizeof(packet);
    packet.packet_version = GE_SOURCE_GBI_V6_PACKET_VERSION;
    packet.dialect = GE_SOURCE_GBI_V6_DIALECT_CLASSIC_GE_F3D;
    packet.command_count = 8u;
    packet.list_count = 1u;
    packet.root_list_handle = UINT32_C(0x7100);
    packet.lists[0].handle = packet.root_list_handle;
    packet.lists[0].command_count = packet.command_count;

    packet.commands[0].w0 = op(GE_SOURCE_GBI_V6_OP_SETOTHERMODE_H) |
                             (20u << 8) | 1u;
    packet.commands[0].w1 = UINT32_C(0x00100000);
    packet.commands[1].w0 = op(GE_SOURCE_GBI_V6_OP_SETOTHERMODE_H) |
                             (16u << 8) | 1u;
    packet.commands[1].w1 = UINT32_C(0x00010000);
    packet.commands[2].w0 = op(GE_SOURCE_GBI_V6_OP_SETOTHERMODE_H) |
                             (17u << 8) | 2u;
    packet.commands[2].w1 = 0u;
    packet.commands[3].w0 = op(GE_SOURCE_GBI_V6_OP_SETOTHERMODE_H) |
                             (12u << 8) | 2u;
    packet.commands[3].w1 = UINT32_C(0x00002000);
    packet.commands[4].w0 = op(GE_SOURCE_GBI_V6_OP_SETOTHERMODE_L) |
                             (0u << 8) | 2u;
    packet.commands[4].w1 = 3u;
    packet.commands[5].w0 = op(GE_SOURCE_GBI_V6_OP_SETOTHERMODE_L) |
                             (3u << 8) | 29u;
    packet.commands[5].w1 = UINT32_C(0xabcdeff8);
    packet.commands[6].w0 = op(GE_SOURCE_GBI_V6_OP_SETOTHERMODE_L) |
                             (0u << 8) | 2u;
    packet.commands[6].w1 = 1u;
    packet.commands[7].w0 = op(GE_SOURCE_GBI_V6_OP_ENDDL);
    return packet;
}

int main(void)
{
    assert(sizeof(GEGBISourceCommandV6) == 8u);
    assert(sizeof(GEGBISourceListV6) == 16u);
    assert(sizeof(GEGBISourceMatrixResourceV6) == 68u);
    assert(sizeof(GEGBISourcePacketV6) == 68536u);
    assert(sizeof(GEGBISourceVertexResourcePageV6) == 1080u);
    assert(sizeof(GEGBIEventV6) == 56u);
    assert(sizeof(GEGBIDrawV6) == 64u);
    assert(sizeof(GEGBIVertexLoadProvenanceV6) == 44u);
    assert(sizeof(GEGBIDiagnosticV6) == 32u);
    assert(sizeof(GEGBIResultV6) == 1020056u);

    static GEGBISourcePacketV6 packet;
    static GEGBIResultV6 first;
    static GEGBIResultV6 second;
    static GEGBIResultV6 old;
    static GEGBIResultV6 overwrite;
    static GEGBISourceVertexResourceV6 resource_items[68];
    static GEGBISourceVertexResourcePageV6 resource_pages[4];
    static uint32_t resource_page_count;
    static GEGBIStateV6 copied_states[2];
    static GEGBIDrawV6 copied_draws[2];
    static GEGBIEventV6 copied_events[4];
    static GEGBISourceImageResourceV6 copied_images[1];
    packet = make_f3dex2_packet();
    assert(ge_source_gbi_decode_v6_into(&packet, &first) == GE_STATUS_OK);
    assert(ge_source_gbi_decode_v6_into(&packet, &second) == GE_STATUS_OK);
    assert(first.status == GE_STATUS_OK);
    assert(first.list_enters == 1u);
    assert(first.list_returns == 2u);
    assert(first.draw_count == 1u);
    assert(first.vertex_count == 3u);
    assert(first.unsupported_count == 0u);
    assert(first.state.texture_image_handle == UINT32_C(0x5000));
    assert(first.event_hash != 0u);
    assert(first.state_hash != 0u);
    assert(first.event_hash == second.event_hash);
    assert(first.state_hash == second.state_hash);
    assert(memcmp(first.events, second.events, sizeof(first.events)) == 0);

    GEGBIVertexLoadProvenanceV6 provenance[64];
    uint32_t provenance_count = 0u;
    assert(ge_source_gbi_v6_build_vertex_load_provenance(
               &packet, NULL, 0u, provenance, 64u, &provenance_count)
           == GE_STATUS_OK);
    assert(provenance_count == 3u);
    assert(provenance[0].cache_slot == 0u);
    assert(provenance[0].source_vertex == 0u);
    assert(provenance[0].modelview_handle == UINT32_C(0x4000));
    assert((provenance[0].flags
            & GE_SOURCE_GBI_V6_VERTEX_LOAD_PROVENANCE_FLAG_SOURCE_ORDERED)
           != 0u);
    /* F3DEX2 fixture command 0x2 exercises the push form; it must not be
       mislabeled as a load-only modelview stream. */
    assert((provenance[0].flags
            & GE_SOURCE_GBI_V6_VERTEX_LOAD_PROVENANCE_FLAG_MATRIX_LOAD_ONLY)
           == 0u);
    assert(provenance[2].cache_slot == 2u);
    assert(provenance[2].source_vertex == 2u);

    packet = make_old_f3d_packet();
    assert(ge_source_gbi_decode_v6_into(&packet, &old) == GE_STATUS_OK);
    assert(old.status == GE_STATUS_OK);
    assert(old.draw_count == 1u);
    assert(old.state.texture_image_handle == UINT32_C(0x21));
    packet = make_old_f3d_packet();
    provenance_count = 0u;
    assert(ge_source_gbi_v6_build_vertex_load_provenance(
               &packet, NULL, 0u, provenance, 64u, &provenance_count)
           == GE_STATUS_OK);
    assert(provenance_count == 3u);
    assert((provenance[0].flags
            & GE_SOURCE_GBI_V6_VERTEX_LOAD_PROVENANCE_FLAG_MATRIX_LOAD_ONLY)
           != 0u);
    packet.commands[3].w1 = (2u << 16) | (4u << 8);
    assert(ge_source_gbi_decode_v6_into(&packet, &first) ==
           GE_STATUS_VERTEX_OUT_OF_RANGE);

    packet = make_f3dex2_packet();
    packet.dialect = 0u;
    assert(ge_source_gbi_decode_v6_into(&packet, &first) == GE_STATUS_INVALID_ARGUMENT);

    packet = make_overwrite_packet();
    assert(ge_source_gbi_decode_v6_into(&packet, &overwrite) == GE_STATUS_OK);
    assert(overwrite.status == GE_STATUS_OK);
    assert(overwrite.draw_count == 2u);
    assert(overwrite.state_count == 2u);
    assert(overwrite.draws[0].vertex_slot_a == 0u);
    assert(overwrite.draws[0].vertex_slot_b == 1u);
    assert(overwrite.draws[0].vertex_slot_c == 2u);
    assert(overwrite.draws[0].source_vertex_a == 0u);
    assert(overwrite.draws[0].source_vertex_b == 1u);
    assert(overwrite.draws[0].source_vertex_c == 2u);
    assert(overwrite.draws[1].vertex_slot_a == 0u);
    assert(overwrite.draws[1].vertex_slot_b == 1u);
    assert(overwrite.draws[1].vertex_slot_c == 2u);
    assert(overwrite.draws[1].source_vertex_a == 3u);
    assert(overwrite.draws[1].source_vertex_b == 4u);
    assert(overwrite.draws[1].source_vertex_c == 5u);

    provenance_count = 0u;
    assert(ge_source_gbi_v6_build_vertex_load_provenance(
               &packet, NULL, 0u,
               provenance, 64u, &provenance_count)
           == GE_STATUS_OK);
    assert(provenance_count == 6u);
    assert(provenance[3].source_vertex == 3u);
    assert(overwrite.draws[0].state_index != overwrite.draws[1].state_index);
    assert(overwrite.states[overwrite.draws[0].state_index].combine_w0 !=
           overwrite.states[overwrite.draws[1].state_index].combine_w0);
    assert(overwrite.states[overwrite.draws[0].state_index].state_hash ==
           overwrite.draws[0].state_hash);
    assert(overwrite.states[overwrite.draws[1].state_index].state_hash ==
           overwrite.draws[1].state_hash);
    assert(overwrite.vertices[0].source_index == 3u);
    assert(ge_source_gbi_v6_copy_states(
               &overwrite, 0u, 2u, copied_states, 2u) == GE_STATUS_OK);
    assert(copied_states[0].combine_w0 != copied_states[1].combine_w0);
    assert(ge_source_gbi_v6_copy_draws(
               &overwrite, 0u, 2u, copied_draws, 2u) == GE_STATUS_OK);
    assert(copied_draws[0].source_vertex_a == 0u);
    assert(copied_draws[1].source_vertex_a == 3u);
    assert(ge_source_gbi_v6_copy_events(
               &overwrite, 0u, 4u, copied_events, 4u) == GE_STATUS_OK);
    assert(ge_source_gbi_v6_copy_diagnostics(
               &overwrite, 0u, 0u, NULL, 0u) == GE_STATUS_OK);
    assert(ge_source_gbi_v6_copy_states(
               &overwrite, 0u, 2u, copied_states, 1u) == GE_STATUS_REPLAY_BUDGET);
    assert(ge_source_gbi_v6_copy_states(
               &overwrite, 3u, 1u, copied_states, 1u) == GE_STATUS_MALFORMED_STREAM);
    assert(ge_source_gbi_v6_copy_states(
               &overwrite, 0u, 1u, NULL, 1u) == GE_STATUS_INVALID_ARGUMENT);
    overwrite.state_count = GE_SOURCE_GBI_V6_MAX_STATES + 1u;
    assert(ge_source_gbi_v6_copy_states(
               &overwrite, 0u, 0u, NULL, 0u) == GE_STATUS_MALFORMED_STREAM);
    overwrite.state_count = 2u;
    overwrite.draws[0].state_index = GE_SOURCE_GBI_V6_MAX_STATES;
    assert(ge_source_gbi_v6_copy_draws(
               &overwrite, 0u, 2u, copied_draws, 2u) == GE_STATUS_ASSET_MISMATCH);
    overwrite.draws[0].state_index = 0u;

    packet = make_other_mode_packet();
    assert(ge_source_gbi_decode_v6_into(&packet, &first) == GE_STATUS_OK);
    assert(first.state.other_mode_h == UINT32_C(0x00112000));
    assert(first.state.other_mode_l == UINT32_C(0xabcdeff9));

    for (uint32_t index = 0u; index < 68u; index++) {
        resource_items[index].handle = UINT32_C(0x9000) + index;
        resource_items[index].first_vertex = index;
        resource_items[index].vertex_count = 1u;
    }
    assert(ge_source_gbi_v6_build_vertex_resource_pages(
               resource_items, 68u, resource_pages, 4u,
               &resource_page_count) == GE_STATUS_OK);
    assert(resource_page_count == 1u);
    assert(resource_pages[0].page_index == 0u);
    assert(resource_pages[0].first_item == 64u);
    assert(resource_pages[0].item_count == 4u);
    assert(ge_source_gbi_v6_validate_vertex_resource_page(&resource_pages[0]) ==
           GE_STATUS_OK);
    packet = make_other_mode_packet();
    packet.vertex_count = 68u;
    packet.vertex_resource_count = 64u;
    memcpy(packet.vertex_resources, resource_items,
           64u * sizeof(packet.vertex_resources[0]));
    assert(ge_source_gbi_decode_v6_into_with_vertex_pages(
               &packet, resource_pages, resource_page_count, &first) == GE_STATUS_OK);

    resource_pages[0].manifest_hash ^= 1u;
    assert(ge_source_gbi_decode_v6_into_with_vertex_pages(
               &packet, resource_pages, resource_page_count, &first) ==
           GE_STATUS_ASSET_MISMATCH);
    resource_pages[0].manifest_hash ^= 1u;
    resource_pages[0].page_index = 1u;
    assert(ge_source_gbi_decode_v6_into_with_vertex_pages(
               &packet, resource_pages, resource_page_count, &first) ==
           GE_STATUS_MALFORMED_STREAM);
    resource_pages[0].page_index = 0u;
    resource_pages[0].item_count = 3u;
    resource_pages[0].page_hash = ge_source_gbi_v6_hash_vertex_resource_manifest(
        resource_pages[0].items, resource_pages[0].item_count, NULL, 0u);
    resource_pages[0].manifest_hash =
        ge_source_gbi_v6_hash_vertex_resource_manifest(
            packet.vertex_resources, packet.vertex_resource_count,
            resource_pages, resource_page_count);
    assert(ge_source_gbi_decode_v6_into_with_vertex_pages(
               &packet, resource_pages, resource_page_count, &first) ==
           GE_STATUS_MALFORMED_STREAM);
    resource_pages[0].item_count = 4u;
    resource_pages[0].items[0].handle = resource_items[0].handle;
    resource_pages[0].page_hash = ge_source_gbi_v6_hash_vertex_resource_manifest(
        resource_pages[0].items, resource_pages[0].item_count, NULL, 0u);
    resource_pages[0].manifest_hash =
        ge_source_gbi_v6_hash_vertex_resource_manifest(
            packet.vertex_resources, packet.vertex_resource_count,
            resource_pages, resource_page_count);
    assert(ge_source_gbi_decode_v6_into_with_vertex_pages(
               &packet, resource_pages, resource_page_count, &first) ==
           GE_STATUS_MALFORMED_STREAM);
    resource_pages[0].items[0].handle = UINT32_C(0x9064);
    resource_pages[0].page_hash = ge_source_gbi_v6_hash_vertex_resource_manifest(
        resource_pages[0].items, resource_pages[0].item_count, NULL, 0u);
    resource_pages[0].manifest_hash =
        ge_source_gbi_v6_hash_vertex_resource_manifest(
            packet.vertex_resources, packet.vertex_resource_count,
            resource_pages, resource_page_count);
    resource_pages[0].items[0].first_vertex = 0u;
    resource_pages[0].page_hash = ge_source_gbi_v6_hash_vertex_resource_manifest(
        resource_pages[0].items, resource_pages[0].item_count, NULL, 0u);
    resource_pages[0].manifest_hash =
        ge_source_gbi_v6_hash_vertex_resource_manifest(
            packet.vertex_resources, packet.vertex_resource_count,
            resource_pages, resource_page_count);
    assert(ge_source_gbi_decode_v6_into_with_vertex_pages(
               &packet, resource_pages, resource_page_count, &first) ==
           GE_STATUS_OK);
    resource_pages[0].items[0].first_vertex = 64u;
    resource_pages[0].page_hash = ge_source_gbi_v6_hash_vertex_resource_manifest(
        resource_pages[0].items, resource_pages[0].item_count, NULL, 0u);
    resource_pages[0].manifest_hash =
        ge_source_gbi_v6_hash_vertex_resource_manifest(
            packet.vertex_resources, packet.vertex_resource_count,
            resource_pages, resource_page_count);
    resource_pages[0].reserved0 = 1u;
    assert(ge_source_gbi_decode_v6_into_with_vertex_pages(
               &packet, resource_pages, resource_page_count, &first) ==
           GE_STATUS_MALFORMED_STREAM);

    packet = make_f3dex2_packet();
    assert(ge_source_gbi_v6_copy_images(
               &packet, 0u, 1u, copied_images, 1u) == GE_STATUS_OK);
    assert(copied_images[0].handle == UINT32_C(0x5000));
    assert(ge_source_gbi_v6_copy_images(
               &packet, 0u, 1u, copied_images, 0u) == GE_STATUS_REPLAY_BUDGET);
    assert(ge_source_gbi_v6_copy_images(
               &packet, 0u, 1u, NULL, 1u) == GE_STATUS_INVALID_ARGUMENT);
    packet.images[0].reserved = 1u;
    assert(ge_source_gbi_v6_copy_images(
               &packet, 0u, 1u, copied_images, 1u) == GE_STATUS_ASSET_MISMATCH);

    packet = make_f3dex2_packet();
    packet.header.abi_version++;
    assert(ge_source_gbi_decode_v6_into(&packet, &first) == GE_STATUS_INVALID_VERSION);
    assert(first.status == GE_STATUS_INVALID_VERSION);
    packet = make_f3dex2_packet();
    packet.header.struct_size--;
    assert(ge_source_gbi_decode_v6_into(&packet, &first) == GE_STATUS_INVALID_SIZE);
    assert(first.status == GE_STATUS_INVALID_SIZE);
    packet = make_f3dex2_packet();
    packet.reserved0[0] = 1u;
    assert(ge_source_gbi_decode_v6_into(&packet, &first) == GE_STATUS_RESERVED_BITS);
    assert(first.status == GE_STATUS_RESERVED_BITS);

    packet = make_f3dex2_packet();
    packet.commands[2].w0 = op(0x99u);
    assert(ge_source_gbi_decode_v6_into(&packet, &first) == GE_STATUS_UNSUPPORTED_COMMAND);
    assert(first.status == GE_STATUS_UNSUPPORTED_COMMAND);
    assert(first.unsupported_count == 1u);
    assert(first.diagnostic_count != 0u);
    assert(first.diagnostics[0].code == GE_SOURCE_GBI_V6_DIAG_UNSUPPORTED);

    packet = make_f3dex2_packet();
    packet.commands[4].w1 = UINT32_C(0xdeadbeef);
    assert(ge_source_gbi_decode_v6_into(&packet, &first) == GE_STATUS_RESOURCE_NOT_FOUND);
    assert(first.status == GE_STATUS_RESOURCE_NOT_FOUND);

    packet = make_f3dex2_packet();
    packet.commands[0].w1 = packet.root_list_handle;
    assert(ge_source_gbi_decode_v6_into(&packet, &first) == GE_STATUS_REPLAY_CYCLE);
    assert(first.status == GE_STATUS_REPLAY_CYCLE);
    assert(first.diagnostics[0].code == GE_SOURCE_GBI_V6_DIAG_CYCLE);

    packet = make_f3dex2_packet();
    packet.lists[1].command_count--;
    assert(ge_source_gbi_decode_v6_into(&packet, &first) == GE_STATUS_MALFORMED_STREAM);
    assert(first.status == GE_STATUS_MALFORMED_STREAM);

    packet = make_f3dex2_packet();
    packet.commands[6].w0 = op(GE_SOURCE_GBI_V6_OP_NOOP);
    packet.commands[6].w1 = 0u;
    assert(ge_source_gbi_decode_v6_into(&packet, &first) == GE_STATUS_TEXTURE_OVERFLOW);
    assert(first.status == GE_STATUS_TEXTURE_OVERFLOW);

    puts("goldeneye_source_gbi_v6_smoke: PASS");
    return 0;
}
