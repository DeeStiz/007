#include "ge_weapon_effect_owner_v6.h"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void init_header(GEAbiHeaderV1 *header, uint32_t size)
{
    header->abi_version = GE_NATIVE_ABI_VERSION;
    header->struct_size = size;
}

static uint32_t stage_for_demo(uint32_t demo_id)
{
    static const uint32_t stages[] = {
        GE_RAMROM_V5_STAGE_DAM, GE_RAMROM_V5_STAGE_DAM,
        GE_RAMROM_V5_STAGE_FACILITY, GE_RAMROM_V5_STAGE_FACILITY,
        GE_RAMROM_V5_STAGE_FACILITY, GE_RAMROM_V5_STAGE_RUNWAY,
        GE_RAMROM_V5_STAGE_RUNWAY, GE_RAMROM_V5_STAGE_BUNKER_I,
        GE_RAMROM_V5_STAGE_BUNKER_I, GE_RAMROM_V5_STAGE_SILO,
        GE_RAMROM_V5_STAGE_SILO, GE_RAMROM_V5_STAGE_FRIGATE,
        GE_RAMROM_V5_STAGE_FRIGATE, GE_RAMROM_V5_STAGE_TRAIN
    };
    return stages[demo_id - 1u];
}

static uint32_t source_flags(void)
{
    return GE_WEAPON_EFFECT_OWNER_V6_SOURCE_WEAPON_TABLE |
           GE_WEAPON_EFFECT_OWNER_V6_SOURCE_HAND_STATE |
           GE_WEAPON_EFFECT_OWNER_V6_SOURCE_AMMO |
           GE_WEAPON_EFFECT_OWNER_V6_SOURCE_HUD |
           GE_WEAPON_EFFECT_OWNER_V6_SOURCE_SIGHT |
           GE_WEAPON_EFFECT_OWNER_V6_SOURCE_WATCH |
           GE_WEAPON_EFFECT_OWNER_V6_SOURCE_MUZZLE |
           GE_WEAPON_EFFECT_OWNER_V6_SOURCE_PROJECTILES |
           GE_WEAPON_EFFECT_OWNER_V6_SOURCE_PARTICLES |
           GE_WEAPON_EFFECT_OWNER_V6_SOURCE_EXPLOSIONS |
           GE_WEAPON_EFFECT_OWNER_V6_SOURCE_GLASS |
           GE_WEAPON_EFFECT_OWNER_V6_SOURCE_FADE |
           GE_WEAPON_EFFECT_OWNER_V6_SOURCE_SFX;
}

static void fill_setup(uint32_t demo_id, GERamRomWeaponEffectSetupV6 *setup)
{
    memset(setup, 0, sizeof(*setup));
    init_header(&setup->header, (uint32_t)sizeof(*setup));
    setup->record_version = GE_WEAPON_EFFECT_OWNER_V6_RECORD_VERSION;
    setup->stage_id = stage_for_demo(demo_id);
    setup->demo_mask = UINT32_C(1) << (demo_id - 1u);
    setup->flags = source_flags();
    setup->weapon_table_count = 92u;
    setup->image_table_count = 81u;
    setup->sound_table_count = 24u;
    setup->source_bytes = 0x1000u + demo_id;
    setup->source_setup_offset = 0x200u;
    setup->weapon_table_offset = 0x400u;
    setup->image_table_offset = 0x600u;
    setup->sound_table_offset = 0x800u;
    setup->initial_weapon_id = GE_WEAPON_EFFECT_OWNER_V6_ITEM_WPPK;
    setup->initial_weapon_model = UINT32_C(0x90000090);
    setup->initial_ammo_type = 1u;
    setup->initial_magazine = 7u;
    setup->initial_reserve = 35u;
    setup->initial_health = 100u;
    setup->source_hash = UINT64_C(0x5a00000000000000) | demo_id;
    setup->resource_hash = UINT64_C(0x5b00000000000000) | demo_id;
    setup->weapon_table_hash = UINT64_C(0x5c00000000000000) | demo_id;
    setup->image_table_hash = UINT64_C(0x5d00000000000000) | demo_id;
    setup->sound_table_hash = UINT64_C(0x5e00000000000000) | demo_id;
}

static void fill_hand(uint32_t demo_id, uint32_t hand_index,
                      GERamRomWeaponHandV6 *hand)
{
    uint32_t axis;
    memset(hand, 0, sizeof(*hand));
    init_header(&hand->header, (uint32_t)sizeof(*hand));
    hand->record_version = GE_WEAPON_EFFECT_OWNER_V6_RECORD_VERSION;
    hand->hand_index = hand_index;
    hand->flags = 1u;
    hand->weapon_id = hand_index == 0u ? GE_WEAPON_EFFECT_OWNER_V6_ITEM_WPPK :
                                        GE_WEAPON_EFFECT_OWNER_V6_ITEM_UNARMED;
    hand->model_handle = hand_index == 0u ? UINT32_C(0x90000090) : 0u;
    hand->ammo_type = hand_index == 0u ? 1u : 0u;
    hand->magazine = hand_index == 0u ? 7u : 0u;
    hand->reserve = hand_index == 0u ? 35u : 0u;
    hand->magazine_capacity = hand_index == 0u ? 7u : 0u;
    hand->action_state = 0u;
    hand->firing_status = 0u;
    hand->animation_id = 2u;
    hand->animation_frame_q16 = 2 * 65536;
    hand->animation_rate_q16 = 65536;
    hand->source_weapon_offset = 0x100u + hand_index * 0x20u;
    hand->source_stats_offset = 0x300u + hand_index * 0x20u;
    hand->source_transform_offset = 0x500u + hand_index * 0x20u;
    hand->source_matrix_handle = UINT32_C(0x91000000) | hand_index;
    hand->position_q16[0] = hand_index == 0u ? 0 : -65536;
    hand->position_q16[1] = -65536;
    hand->position_q16[2] = 0;
    hand->rotation_q16[0] = 0;
    hand->rotation_q16[1] = 0;
    hand->rotation_q16[2] = 0;
    for (axis = 0u; axis < 3u; axis++) {
        hand->scale_q16[axis] = 65536;
        hand->muzzle_offset_q16[axis] = 0;
    }
    hand->muzzle_offset_q16[2] = 65536;
    hand->source_hash = UINT64_C(0x6000000000000000) | ((uint64_t)demo_id << 8) | hand_index;
    hand->resource_hash = UINT64_C(0x6100000000000000) | ((uint64_t)demo_id << 8) | hand_index;
}

static void fill_event(uint32_t demo_id, uint32_t category,
                       uint64_t reference_tick, uint32_t sequence,
                       GERamRomWeaponEffectEventV6 *event)
{
    uint32_t axis;
    memset(event, 0, sizeof(*event));
    init_header(&event->header, (uint32_t)sizeof(*event));
    event->record_version = GE_WEAPON_EFFECT_OWNER_V6_RECORD_VERSION;
    event->category = category;
    event->flags = GE_WEAPON_EFFECT_OWNER_V6_EVENT_CONTINUOUS |
                   GE_WEAPON_EFFECT_OWNER_V6_EVENT_SOURCE_ANCHOR;
    if (category == GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_MUZZLE ||
        category == GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_SFX) {
        event->flags |= GE_WEAPON_EFFECT_OWNER_V6_EVENT_ONE_SHOT_FLAG;
    }
    event->source_event_id = category * 100u + demo_id;
    event->resource_handle = UINT32_C(0xa0000000) | (category << 12) | demo_id;
    event->source_resource_id = 2000u + category;
    event->image_handle = UINT32_C(0xb0000000) | (category << 12) | demo_id;
    event->source_sfx_id = 300u + category;
    event->source_reference_tick = reference_tick;
    event->sequence = sequence;
    event->source_offset = 0x1000u + category * 0x40u;
    event->frame_index = 0u;
    event->frame_count = category == GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_SFX ? 1u : 6u;
    event->position_q16[0] = (int32_t)(category * 2u * 65536u);
    event->position_q16[1] = 65536;
    event->position_q16[2] = (int32_t)(category * 3u * 65536u);
    event->velocity_q16[0] = 0;
    event->velocity_q16[1] = category == GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_PARTICLE ? 65536 : 0;
    event->velocity_q16[2] = 0;
    for (axis = 0u; axis < 3u; axis++) {
        event->rotation_q16[axis] = 0;
        event->scale_q16[axis] = 65536;
    }
    event->gravity_q16 = category == GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_PARTICLE ? -13107 : 0;
    event->colour_rgba = category == GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_GLASS ?
        UINT32_C(0x80ffffff) : UINT32_C(0xffffffff);
    event->alpha_q16 = category == GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_GLASS ? 32768u : 65536u;
    event->lifetime_q16 = category == GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_SFX ? 65536u : 12u * 65536u;
    event->envelope_q16 = category == GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_MUZZLE ? 65536u : 32768u;
    event->source_hash = UINT64_C(0x6200000000000000) | ((uint64_t)demo_id << 16) | category;
    event->resource_hash = UINT64_C(0x6300000000000000) | ((uint64_t)demo_id << 16) | category;
}

static void fill_frame(uint32_t demo_id, uint64_t native_tick,
                       GERamRomWeaponEffectFrameV6 *frame)
{
    uint32_t category;
    memset(frame, 0, sizeof(*frame));
    init_header(&frame->header, (uint32_t)sizeof(*frame));
    frame->record_version = GE_WEAPON_EFFECT_OWNER_V6_RECORD_VERSION;
    frame->flags = GE_WEAPON_EFFECT_OWNER_V6_FRAME_SOURCE_ANCHOR |
                   GE_WEAPON_EFFECT_OWNER_V6_FRAME_HAS_HUD |
                   GE_WEAPON_EFFECT_OWNER_V6_FRAME_HAS_SIGHT |
                   GE_WEAPON_EFFECT_OWNER_V6_FRAME_HAS_WATCH |
                   GE_WEAPON_EFFECT_OWNER_V6_FRAME_HAS_FADE;
    frame->demo_id = demo_id;
    frame->stage_id = stage_for_demo(demo_id);
    frame->native_tick = native_tick;
    frame->reference_tick = native_tick / 2u;
    frame->source_anchor = 1u;
    frame->source_frame = (uint32_t)(native_tick / 2u) + 1u;
    frame->source_present_mask = GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_MASK;
    frame->source_inactive_mask = 0u;
    frame->one_shot_sequence = native_tick == 0u ? 0u : 1u;
    frame->hand_count = 2u;
    frame->event_count = GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_MAX;
    frame->hud_visible = 1u;
    frame->view_left_q16 = 0;
    frame->view_top_q16 = 0;
    frame->view_width_q16 = 440u;
    frame->view_height_q16 = 330u;
    frame->right_hud_image_handle = UINT32_C(0xb0002231);
    frame->left_hud_image_handle = UINT32_C(0xb0002231);
    frame->right_hud_width = 5u;
    frame->right_hud_height = 12u;
    frame->left_hud_width = 5u;
    frame->left_hud_height = 12u;
    frame->right_ammo_type = 1u;
    frame->right_magazine = native_tick == 0u ? 7u : 6u;
    frame->right_reserve = 35u;
    frame->left_ammo_type = 0u;
    frame->left_magazine = 0u;
    frame->left_reserve = 0u;
    frame->crosshair_x_q16 = 160 * 65536;
    frame->crosshair_y_q16 = 120 * 65536;
    frame->crosshair_image_handle = UINT32_C(0xb0002236);
    frame->sight_visible = 1u;
    frame->watch_visible = 1u;
    frame->watch_model_handle = UINT32_C(0x90000052);
    frame->watch_animate_buttons = 1u;
    frame->watch_controller_pad = 0u;
    frame->watch_position_q16[0] = 0;
    frame->watch_position_q16[1] = 0;
    frame->watch_position_q16[2] = 0;
    frame->watch_scale_q16 = 65536;
    frame->watch_animation_frame = (uint32_t)(native_tick / 2u);
    frame->fade_visible = 1u;
    frame->fade_colour_rgba = UINT32_C(0x000000ff);
    frame->fade_q16 = 0u;
    frame->fade_elapsed_q16 = 0u;
    frame->fade_duration_q16 = 65536u;
    frame->source_hash = UINT64_C(0x6400000000000000) | ((uint64_t)demo_id << 8) | native_tick;
    frame->resource_hash = UINT64_C(0x6500000000000000) | ((uint64_t)demo_id << 8) | native_tick;
    fill_hand(demo_id, 0u, &frame->hands[0]);
    fill_hand(demo_id, 1u, &frame->hands[1]);
    frame->hands[0].animation_frame_q16 = (int32_t)(2 + native_tick / 2u) * 65536;
    for (category = 1u; category <= GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_MAX; category++) {
        fill_event(demo_id, category, frame->reference_tick, category - 1u,
                   &frame->events[category - 1u]);
    }
    frame->frame_hash = ge_ramrom_weapon_effect_v6_hash_frame(frame);
}

static GERamRomGameplayInputV6 neutral_input(void)
{
    GERamRomGameplayInputV6 input;
    memset(&input, 0, sizeof(input));
    init_header(&input.header, (uint32_t)sizeof(input));
    input.record_version = GE_RAMROM_GAMEPLAY_V6_RECORD_VERSION;
    input.flags = GE_RAMROM_GAMEPLAY_V6_INPUT_RECORDED |
                  GE_RAMROM_GAMEPLAY_V6_INPUT_FOCUSED |
                  GE_RAMROM_GAMEPLAY_V6_INPUT_CONTROLLER;
    input.controller_count = 1u;
    input.controller_index = 0u;
    return input;
}

static void test_demo(uint32_t demo_id)
{
    GERamRomWeaponEffectSetupV6 setup;
    GERamRomWeaponEffectFrameV6 initial;
    GERamRomWeaponEffectFrameV6 next;
    GERamRomWeaponEffectOwnerStateV6 *state = calloc(1u, sizeof(*state));
    GERamRomWeaponEffectEventRecordV6 event;
    GERamRomGameplayInputV6 input = neutral_input();
    GERamRomWeaponEffectSnapshotV6 snapshot;
    GERamRomWeaponEffectEventV6 events[GE_WEAPON_EFFECT_OWNER_V6_MAX_EVENTS];
    uint32_t copied = 0u;
    assert(state != NULL);
    fill_setup(demo_id, &setup);
    fill_frame(demo_id, 0u, &initial);
    fill_frame(demo_id, 2u, &next);
    assert(ge_ramrom_weapon_effect_v6_begin(demo_id, &setup, &initial, state, &event) == GE_STATUS_OK);
    assert(event.event_type == GE_WEAPON_EFFECT_OWNER_V6_EVENT_INSTALL);
    assert(ge_ramrom_weapon_effect_v6_step(1u, input, NULL, state, &event) == GE_STATUS_OK);
    assert(event.event_type == GE_WEAPON_EFFECT_OWNER_V6_EVENT_INTERPOLANT);
    assert(state->render_frame.source_anchor == 0u);
    assert(ge_ramrom_weapon_effect_v6_step(2u, input, &next, state, &event) == GE_STATUS_OK);
    assert(event.event_type == GE_WEAPON_EFFECT_OWNER_V6_EVENT_ONE_SHOT);
    assert(state->current_anchor.right_magazine == 6u);
    assert(ge_ramrom_weapon_effect_v6_copy_snapshot(state, &snapshot) == GE_STATUS_OK);
    assert(snapshot.right_ammo_type == 1u && snapshot.sight_visible == 1u);
    assert(ge_ramrom_weapon_effect_v6_copy_events(state, 0u,
                                                   GE_WEAPON_EFFECT_OWNER_V6_MAX_EVENTS,
                                                   events, &copied) == GE_STATUS_OK);
    assert(copied == GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_MAX);
    assert(events[0].category == GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_MUZZLE);
    input.flags |= GE_RAMROM_GAMEPLAY_V6_INPUT_REAL;
    input.pressed_buttons = UINT32_C(0x00008000);
    assert(ge_ramrom_weapon_effect_v6_step(3u, input, NULL, state, &event) == GE_STATUS_OK);
    assert(event.event_type == GE_WEAPON_EFFECT_OWNER_V6_EVENT_ABORT);
    assert((state->flags & GE_WEAPON_EFFECT_OWNER_V6_STATE_ABORTING) != 0u);
    free(state);
}

int main(void)
{
    uint32_t demo_id;
    for (demo_id = 1u; demo_id <= GE_RAMROM_V5_DEMO_COUNT; demo_id++) {
        test_demo(demo_id);
    }
    puts("ge_weapon_effect_owner_v6_smoke: PASS demos=14 odd-interpolant=1 one-shot=1 categories=10");
    return 0;
}
