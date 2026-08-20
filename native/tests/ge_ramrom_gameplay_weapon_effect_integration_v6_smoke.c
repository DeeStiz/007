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

static void fill_gameplay_setup(GERamRomGameplaySetupV6 *setup)
{
    memset(setup, 0, sizeof(*setup));
    init_header(&setup->header, (uint32_t)sizeof(*setup));
    setup->record_version = GE_RAMROM_GAMEPLAY_V6_RECORD_VERSION;
    setup->stage_id = GE_RAMROM_V5_STAGE_DAM;
    setup->flags = GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_SOURCE_DERIVED |
                   GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_ROOMS |
                   GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_STAN |
                   GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_OBJECTS |
                   GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_AI |
                   GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_MODEL_DEPENDENCIES;
    setup->demo_mask = 1u;
    setup->source_bytes = 1u;
    setup->room_count = 1u;
    setup->portal_count = 1u;
    setup->stan_count = 1u;
    setup->object_count = 1u;
    setup->initial_room = 0u;
    setup->initial_pad = 7u;
    setup->stan_source_bytes = 1u;
    setup->initial_forward_q16[2] = 65536;
    setup->world_min_q16[0] = -655360;
    setup->world_min_q16[1] = -655360;
    setup->world_min_q16[2] = -655360;
    setup->world_max_q16[0] = 655360;
    setup->world_max_q16[1] = 655360;
    setup->world_max_q16[2] = 655360;
    setup->source_hash = UINT64_C(0x7100000000000001);
    setup->packet_hash = UINT64_C(0x7100000000000002);
    setup->model_dependency_hash = UINT64_C(0x7100000000000003);
    setup->stan_source_hash = UINT64_C(0x7100000000000004);
    setup->stan_bounds_hash = UINT64_C(0x7100000000000005);
    setup->spawn_hash = UINT64_C(0x7100000000000006);
}

static void fill_player(GERamRomGameplayEntityV6 *player)
{
    memset(player, 0, sizeof(*player));
    init_header(&player->header, (uint32_t)sizeof(*player));
    player->record_version = GE_RAMROM_GAMEPLAY_V6_RECORD_VERSION;
    player->entity_id = 1u;
    player->entity_kind = GE_RAMROM_GAMEPLAY_V6_ENTITY_PLAYER;
    player->flags = GE_RAMROM_GAMEPLAY_V6_ENTITY_ACTIVE |
                    GE_RAMROM_GAMEPLAY_V6_ENTITY_VISIBLE;
    player->body_model_handle = UINT32_C(0x1001);
    player->weapon_model_handle = UINT32_C(0x90000090);
    player->animation_id = 2u;
    player->room_id = 0u;
    player->health = 100u;
    player->max_health = 100u;
    player->scale_q16[0] = 65536;
    player->scale_q16[1] = 65536;
    player->scale_q16[2] = 65536;
    player->merge_weight_q16 = 65536;
}

static uint32_t weapon_source_flags(void)
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

static void fill_weapon_setup(GERamRomWeaponEffectSetupV6 *setup)
{
    memset(setup, 0, sizeof(*setup));
    init_header(&setup->header, (uint32_t)sizeof(*setup));
    setup->record_version = GE_WEAPON_EFFECT_OWNER_V6_RECORD_VERSION;
    setup->stage_id = GE_RAMROM_V5_STAGE_DAM;
    setup->demo_mask = 1u;
    setup->flags = weapon_source_flags();
    setup->weapon_table_count = 92u;
    setup->image_table_count = 81u;
    setup->sound_table_count = 24u;
    setup->source_bytes = 1u;
    setup->source_setup_offset = 0x100u;
    setup->weapon_table_offset = 0x200u;
    setup->image_table_offset = 0x300u;
    setup->sound_table_offset = 0x400u;
    setup->initial_weapon_id = GE_WEAPON_EFFECT_OWNER_V6_ITEM_WPPK;
    setup->initial_weapon_model = UINT32_C(0x90000090);
    setup->initial_ammo_type = 1u;
    setup->initial_magazine = 7u;
    setup->initial_reserve = 35u;
    setup->initial_health = 100u;
    setup->source_hash = UINT64_C(0x7200000000000001);
    setup->resource_hash = UINT64_C(0x7200000000000002);
    setup->weapon_table_hash = UINT64_C(0x7200000000000003);
    setup->image_table_hash = UINT64_C(0x7200000000000004);
    setup->sound_table_hash = UINT64_C(0x7200000000000005);
}

static void fill_hand(GERamRomWeaponHandV6 *hand)
{
    memset(hand, 0, sizeof(*hand));
    init_header(&hand->header, (uint32_t)sizeof(*hand));
    hand->record_version = GE_WEAPON_EFFECT_OWNER_V6_RECORD_VERSION;
    hand->hand_index = 0u;
    hand->flags = 1u;
    hand->weapon_id = GE_WEAPON_EFFECT_OWNER_V6_ITEM_WPPK;
    hand->model_handle = UINT32_C(0x90000090);
    hand->ammo_type = 1u;
    hand->magazine = 7u;
    hand->reserve = 35u;
    hand->magazine_capacity = 7u;
    hand->action_state = 0u;
    hand->animation_id = 2u;
    hand->animation_frame_q16 = 2 * 65536;
    hand->animation_rate_q16 = 65536;
    hand->source_weapon_offset = 0x100u;
    hand->source_stats_offset = 0x200u;
    hand->source_transform_offset = 0x300u;
    hand->source_matrix_handle = UINT32_C(0x91000000);
    hand->scale_q16[0] = 65536;
    hand->scale_q16[1] = 65536;
    hand->scale_q16[2] = 65536;
    hand->muzzle_offset_q16[2] = 65536;
    hand->source_hash = UINT64_C(0x7300000000000001);
    hand->resource_hash = UINT64_C(0x7300000000000002);
}

static void fill_event(uint32_t category, uint32_t id, uint64_t reference_tick,
                       GERamRomWeaponEffectEventV6 *event)
{
    memset(event, 0, sizeof(*event));
    init_header(&event->header, (uint32_t)sizeof(*event));
    event->record_version = GE_WEAPON_EFFECT_OWNER_V6_RECORD_VERSION;
    event->category = category;
    event->flags = GE_WEAPON_EFFECT_OWNER_V6_EVENT_CONTINUOUS |
                   GE_WEAPON_EFFECT_OWNER_V6_EVENT_SOURCE_ANCHOR;
    if (category == GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_MUZZLE) {
        event->flags |= GE_WEAPON_EFFECT_OWNER_V6_EVENT_ONE_SHOT_FLAG;
    }
    event->source_event_id = id;
    event->resource_handle = UINT32_C(0xa0000000) | category;
    event->source_resource_id = category;
    event->image_handle = UINT32_C(0xb0000000) | category;
    event->source_sfx_id = category + 300u;
    event->source_reference_tick = reference_tick;
    event->sequence = category;
    event->source_offset = 0x1000u + category * 0x10u;
    event->frame_index = 0u;
    event->frame_count = 1u;
    event->scale_q16[0] = 65536;
    event->scale_q16[1] = 65536;
    event->scale_q16[2] = 65536;
    event->alpha_q16 = 65536u;
    event->lifetime_q16 = 65536u;
    event->envelope_q16 = 65536u;
    event->colour_rgba = UINT32_C(0xffffffff);
    event->source_hash = UINT64_C(0x7400000000000000) | category;
    event->resource_hash = UINT64_C(0x7500000000000000) | category;
}

static void fill_frame(uint64_t native_tick, uint32_t magazine,
                       GERamRomWeaponEffectFrameV6 *frame)
{
    memset(frame, 0, sizeof(*frame));
    init_header(&frame->header, (uint32_t)sizeof(*frame));
    frame->record_version = GE_WEAPON_EFFECT_OWNER_V6_RECORD_VERSION;
    frame->flags = GE_WEAPON_EFFECT_OWNER_V6_FRAME_SOURCE_ANCHOR;
    frame->demo_id = 1u;
    frame->stage_id = GE_RAMROM_V5_STAGE_DAM;
    frame->native_tick = native_tick;
    frame->reference_tick = native_tick / 2u;
    frame->source_anchor = 1u;
    frame->source_frame = (uint32_t)(native_tick / 2u) + 1u;
    frame->source_present_mask =
        GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_BIT(GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_MUZZLE) |
        GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_BIT(GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_PROJECTILE) |
        GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_BIT(GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_HUD) |
        GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_BIT(GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_SIGHT) |
        GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_BIT(GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_WATCH) |
        GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_BIT(GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_FADE);
    frame->source_inactive_mask = GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_MASK &
                                  ~frame->source_present_mask;
    frame->one_shot_sequence = native_tick == 0u ? 0u : 1u;
    frame->hand_count = 1u;
    frame->event_count = 2u;
    frame->hud_visible = 1u;
    frame->view_width_q16 = 440u;
    frame->view_height_q16 = 330u;
    frame->right_hud_image_handle = UINT32_C(0xb0002231);
    frame->right_hud_width = 5u;
    frame->right_hud_height = 12u;
    frame->right_ammo_type = 1u;
    frame->right_magazine = magazine;
    frame->right_reserve = 35u;
    frame->crosshair_x_q16 = 220;
    frame->crosshair_y_q16 = 165;
    frame->crosshair_image_handle = UINT32_C(0xb0002236);
    frame->sight_visible = 1u;
    frame->watch_visible = 0u;
    frame->fade_visible = 0u;
    frame->source_hash = UINT64_C(0x7600000000000000) | native_tick;
    frame->resource_hash = UINT64_C(0x7700000000000000) | native_tick;
    fill_hand(&frame->hands[0]);
    frame->hands[0].magazine = magazine;
    fill_event(GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_MUZZLE, 1001u,
               frame->reference_tick, &frame->events[0]);
    fill_event(GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_PROJECTILE, 1002u,
               frame->reference_tick, &frame->events[1]);
    frame->frame_hash = ge_ramrom_weapon_effect_v6_hash_frame(frame);
}

static uint8_t *read_file(const char *path, uint32_t *out_size)
{
    FILE *file = fopen(path, "rb");
    long size;
    uint8_t *bytes;
    if (file == NULL || fseek(file, 0, SEEK_END) != 0) {
        return NULL;
    }
    size = ftell(file);
    if (size <= 0 || size > UINT32_MAX || fseek(file, 0, SEEK_SET) != 0) {
        fclose(file);
        return NULL;
    }
    bytes = (uint8_t *)malloc((size_t)size);
    if (bytes == NULL || fread(bytes, 1u, (size_t)size, file) != (size_t)size) {
        free(bytes);
        fclose(file);
        return NULL;
    }
    fclose(file);
    *out_size = (uint32_t)size;
    return bytes;
}

static GERamRomGameplayInputV6 neutral_input(void)
{
    GERamRomGameplayInputV6 input;
    memset(&input, 0, sizeof(input));
    init_header(&input.header, (uint32_t)sizeof(input));
    input.record_version = GE_RAMROM_GAMEPLAY_V6_RECORD_VERSION;
    input.flags = GE_RAMROM_GAMEPLAY_V6_INPUT_FOCUSED |
                  GE_RAMROM_GAMEPLAY_V6_INPUT_CONTROLLER;
    input.controller_count = 1u;
    input.controller_index = 0u;
    return input;
}

int main(int argc, char **argv)
{
    GERamRomGameplaySetupV6 gameplay_setup;
    GERamRomGameplayEntityV6 player;
    GERamRomWeaponEffectSetupV6 weapon_setup;
    GERamRomWeaponEffectFrameV6 frame0;
    GERamRomWeaponEffectFrameV6 frame2;
    GERamRomGameplayStateV6 *state = calloc(1u, sizeof(*state));
    GERamRomWeaponEffectOwnerStateV6 *weapon_state = calloc(1u, sizeof(*weapon_state));
    GERamRomGameplayEventV6 gameplay_event;
    GERamRomWeaponEffectEventRecordV6 weapon_event;
    GERamRomGameplayInputV6 input = neutral_input();
    uint32_t byte_count = 0u;
    uint8_t *bytes;
    GEStatusV1 status;
    assert(argc == 2);
    assert(state != NULL && weapon_state != NULL);
    bytes = read_file(argv[1], &byte_count);
    assert(bytes != NULL);
    fill_gameplay_setup(&gameplay_setup);
    fill_player(&player);
    status = ge_ramrom_gameplay_v6_begin_with_source_pages(
        bytes, byte_count, 1u, &gameplay_setup, &player, 1u, NULL, 0u,
        state, &gameplay_event);
    assert(status == GE_STATUS_OK);
    fill_weapon_setup(&weapon_setup);
    fill_frame(0u, 7u, &frame0);
    fill_frame(2u, 6u, &frame2);
    status = ge_ramrom_gameplay_v6_install_weapon_effect(
        state, &weapon_setup, &frame0, weapon_state, &gameplay_event);
    assert(status == GE_STATUS_OK);
    assert(ge_ramrom_gameplay_v6_weapon_effect_source_ready(weapon_state) == 1u);
    assert(state->snapshot.effect_count == 1u && state->snapshot.projectile_count == 1u);
    assert(state->entity_count == 3u);

    status = ge_ramrom_gameplay_v6_step_with_weapon_effect(
        bytes, byte_count, 0u, input, NULL, weapon_state, state,
        &gameplay_event, &weapon_event);
    assert(status == GE_STATUS_OK);
    assert(gameplay_event.native_tick == 0u);
    status = ge_ramrom_gameplay_v6_step_with_weapon_effect(
        bytes, byte_count, 1u, input, NULL, weapon_state, state,
        &gameplay_event, &weapon_event);
    assert(status == GE_STATUS_OK);
    assert((gameplay_event.flags & GE_RAMROM_GAMEPLAY_V6_EVENT_ODD_PAIRED_TICK) != 0u);
    status = ge_ramrom_gameplay_v6_step_with_weapon_effect(
        bytes, byte_count, 2u, input, &frame2, weapon_state, state,
        &gameplay_event, &weapon_event);
    assert(status == GE_STATUS_OK);
    assert(gameplay_event.event_type == GE_RAMROM_GAMEPLAY_V6_EVENT_WEAPON);
    assert(state->snapshot.hud_ammo == 6u);
    assert(state->snapshot.render_hash != 0u && state->snapshot.audio_hash != 0u);

    {
        GERamRomGameplayStateV6 *missing_state = calloc(1u, sizeof(*missing_state));
        GERamRomWeaponEffectOwnerStateV6 *missing_weapon = calloc(1u, sizeof(*missing_weapon));
        assert(missing_state != NULL && missing_weapon != NULL);
        status = ge_ramrom_gameplay_v6_step_with_weapon_effect(
            bytes, byte_count, 0u, input, NULL, missing_weapon, missing_state,
            &gameplay_event, &weapon_event);
        assert(status == GE_STATUS_UNSUPPORTED_COMMAND);
        assert(ge_ramrom_gameplay_v6_weapon_effect_source_ready(missing_weapon) == 0u);
        free(missing_state);
        free(missing_weapon);
    }

    free(bytes);
    free(state);
    free(weapon_state);
    puts("ge_ramrom_gameplay_weapon_effect_integration_v6_smoke: PASS install=1 paired=1 entities=3 missing=fail-closed");
    return 0;
}
