#include "ge_ramrom_weapon_source_pages_v6.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

static void init_header(GEAbiHeaderV1 *header, uint32_t size)
{
    header->abi_version = GE_NATIVE_ABI_VERSION;
    header->struct_size = size;
}

static uint32_t stage_for_demo(uint32_t demo_id)
{
    static const uint32_t stages[] = {
        33u, 33u, 34u, 34u, 34u, 35u, 35u,
        9u, 9u, 20u, 20u, 26u, 26u, 25u
    };
    return stages[demo_id - 1u];
}

static void fill_map(GERamRomWeaponSourceMapRowV6 *map)
{
    memset(map, 0, sizeof(*map));
    init_header(&map->header, (uint32_t)sizeof(*map));
    map->record_version = GE_RAMROM_WEAPON_SOURCE_PAGES_V6_RECORD_VERSION;
    map->item_id = 4u;
    map->prop_model_id = 191u;
    map->model_handle = UINT32_C(0x90000090);
    map->ammo_type = 1u;
    map->magazine_capacity = 7u;
    map->source_weapon_offset = 0x100u;
    map->source_stats_offset = 0x200u;
    map->source_transform_offset = 0x300u;
    map->source_matrix_handle = UINT32_C(0x91000000);
    map->resource_handle = UINT32_C(0xa0000090);
    map->image_handle = UINT32_C(0xb0002231);
    map->source_sfx_id = 42u;
    map->source_hash = UINT64_C(0x8100000000000001);
    map->resource_hash = UINT64_C(0x8100000000000002);
}

static void fill_page(GERamRomWeaponSourcePageV6 *page, uint32_t frame)
{
    memset(page, 0, sizeof(*page));
    init_header(&page->header, (uint32_t)sizeof(*page));
    page->record_version = GE_RAMROM_WEAPON_SOURCE_PAGES_V6_RECORD_VERSION;
    page->item_id = 4u;
    page->flags = 0u;
    page->action_state = 0u;
    page->firing_status = frame != 0u;
    page->animation_id = 2u;
    page->animation_frame_q16 = (int32_t)(2u + frame) * 65536;
    page->animation_rate_q16 = 65536;
    page->magazine = frame == 0u ? 7u : 6u;
    page->reserve = 35u;
    page->scale_q16[0] = 65536;
    page->scale_q16[1] = 65536;
    page->scale_q16[2] = 65536;
    page->muzzle_offset_q16[2] = 65536;
    page->source_weapon_offset = 0x100u;
    page->source_stats_offset = 0x200u;
    page->source_transform_offset = 0x300u;
    page->source_matrix_handle = UINT32_C(0x91000000);
    page->source_hash = UINT64_C(0x8200000000000000) | frame;
    page->source_frame = frame + 1u;
}

static void fill_template(uint32_t demo_id, uint32_t stage_id, uint64_t tick,
                          GERamRomWeaponEffectFrameV6 *frame)
{
    memset(frame, 0, sizeof(*frame));
    init_header(&frame->header, (uint32_t)sizeof(*frame));
    frame->record_version = GE_WEAPON_EFFECT_OWNER_V6_RECORD_VERSION;
    frame->flags = GE_WEAPON_EFFECT_OWNER_V6_FRAME_SOURCE_ANCHOR;
    frame->demo_id = demo_id;
    frame->stage_id = stage_id;
    frame->native_tick = tick;
    frame->reference_tick = tick / 2u;
    frame->source_anchor = 1u;
    frame->source_frame = (uint32_t)(tick / 2u) + 1u;
    frame->source_present_mask = GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_MASK;
    frame->source_inactive_mask = 0u;
    frame->crosshair_x_q16 = 220;
    frame->crosshair_y_q16 = 165;
    frame->source_hash = UINT64_C(0x8300000000000000) | demo_id;
    frame->resource_hash = UINT64_C(0x8400000000000000) | demo_id;
}

static void fill_projectile(uint64_t reference_tick,
                            GERamRomWeaponEffectEventV6 *event)
{
    uint32_t axis;
    memset(event, 0, sizeof(*event));
    init_header(&event->header, (uint32_t)sizeof(*event));
    event->record_version = GE_WEAPON_EFFECT_OWNER_V6_RECORD_VERSION;
    event->category = GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_PROJECTILE;
    event->flags = GE_WEAPON_EFFECT_OWNER_V6_EVENT_CONTINUOUS |
                   GE_WEAPON_EFFECT_OWNER_V6_EVENT_SOURCE_ANCHOR;
    event->source_event_id = 1002u;
    event->resource_handle = UINT32_C(0x90000090);
    event->source_resource_id = 4u;
    event->source_reference_tick = reference_tick;
    event->sequence = 1u;
    event->source_offset = 0x800u;
    event->frame_count = 1u;
    event->lifetime_q16 = 65536u;
    event->envelope_q16 = 65536u;
    event->alpha_q16 = 65536u;
    event->colour_rgba = UINT32_C(0xffffffff);
    event->source_hash = UINT64_C(0x8500000000000001);
    event->resource_hash = UINT64_C(0x8500000000000002);
    for (axis = 0u; axis < 3u; axis++) {
        event->scale_q16[axis] = 65536;
    }
}

int main(void)
{
    GERamRomWeaponSourceMapRowV6 map;
    GERamRomWeaponSourcePageV6 page;
    GERamRomWeaponEffectFrameV6 templ;
    GERamRomWeaponEffectFrameV6 outputA;
    GERamRomWeaponEffectFrameV6 outputB;
    GERamRomWeaponEffectEventV6 projectile;
    uint32_t demo;
    fill_map(&map);
    for (demo = 1u; demo <= 14u; demo++) {
        fill_page(&page, 0u);
        fill_template(demo, stage_for_demo(demo), 2u, &templ);
        assert(ge_ramrom_weapon_source_pages_v6_build_frame(
                   demo, stage_for_demo(demo), 2u, &map, 1u, &page, 1u,
                   NULL, 0u, &templ, &outputA) == GE_STATUS_OK);
        assert(ge_ramrom_weapon_source_pages_v6_build_frame(
                   demo, stage_for_demo(demo), 2u, &map, 1u, &page, 1u,
                   NULL, 0u, &templ, &outputB) == GE_STATUS_OK);
        assert(outputA.frame_hash == outputB.frame_hash);
        assert(outputA.hands[0].model_handle == map.model_handle);
    }
    fill_page(&page, 1u);
    fill_template(1u, 33u, 2u, &templ);
    fill_projectile(1u, &projectile);
    assert(ge_ramrom_weapon_source_pages_v6_build_frame(
               1u, 33u, 2u, &map, 1u, &page, 1u, &projectile, 1u,
               &templ, &outputA) == GE_STATUS_OK);
    assert(outputA.events[0].resource_handle == map.model_handle);
    assert(ge_ramrom_weapon_source_pages_v6_build_frame(
               1u, 33u, 2u, NULL, 0u, &page, 1u, NULL, 0u,
               &templ, &outputB) == GE_STATUS_INVALID_ARGUMENT);
    puts("ge_ramrom_weapon_source_pages_v6_smoke: PASS demos=14 deterministic=1 projectile-link=1 missing-map=fail-closed");
    return 0;
}
