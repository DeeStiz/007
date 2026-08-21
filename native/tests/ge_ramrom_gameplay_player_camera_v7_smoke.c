#include "ge_ramrom_gameplay_v6.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

static void init_header(GEAbiHeaderV1 *header, uint32_t size)
{
    header->abi_version = GE_NATIVE_ABI_VERSION;
    header->struct_size = size;
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
    player->body_model_handle = 0x1001u;
    player->weapon_model_handle = 0x2001u;
    player->animation_id = 3u;
    player->room_id = 1u;
    player->health = 100u;
    player->max_health = 100u;
    player->scale_q16[0] = 65536;
    player->scale_q16[1] = 65536;
    player->scale_q16[2] = 65536;
    player->merge_weight_q16 = 65536;
}

static void fill_prop(GERamRomGameplayEntityV6 *prop)
{
    memset(prop, 0, sizeof(*prop));
    init_header(&prop->header, (uint32_t)sizeof(*prop));
    prop->record_version = GE_RAMROM_GAMEPLAY_V6_RECORD_VERSION;
    prop->entity_id = 2u;
    prop->entity_kind = GE_RAMROM_GAMEPLAY_V6_ENTITY_PROP;
    prop->flags = GE_RAMROM_GAMEPLAY_V6_ENTITY_VISIBLE;
    prop->source_prop_type = 0x55u;
    prop->room_id = 9u;
    prop->scale_q16[0] = 65536;
    prop->scale_q16[1] = 65536;
    prop->scale_q16[2] = 65536;
    prop->merge_weight_q16 = 65536;
}

static void fill_state(GERamRomGameplayStateV6 *state)
{
    memset(state, 0, sizeof(*state));
    init_header(&state->header, (uint32_t)sizeof(*state));
    state->record_version = GE_RAMROM_GAMEPLAY_V6_RECORD_VERSION;
    state->flags = GE_RAMROM_GAMEPLAY_V6_STATE_FLAG_ACTIVE;
    state->replay_state = GE_RAMROM_GAMEPLAY_V6_STATE_RUNNING;
    state->demo_id = 1u;
    state->stage_id = GE_RAMROM_V5_STAGE_DAM;
    state->native_tick = 0u;
    state->reference_tick = 0u;
    state->pair_phase = 0u;
    state->source_anchor = 1u;
    state->controller_count = 1u;
    state->recording_hash = 0x1001u;
    state->packet_hash = 0x1002u;
    state->input_hash = 0x1003u;
    state->rng_hash = 0x1004u;
    state->setup.source_hash = 0xa001u;
    state->setup.packet_hash = 0xa002u;
    state->entities[0].entity_id = 1u;
    fill_player(&state->entities[0]);
    fill_prop(&state->entities[1]);
    state->entity_count = 2u;
    init_header(&state->snapshot.header, (uint32_t)sizeof(state->snapshot));
    state->snapshot.record_version = GE_RAMROM_GAMEPLAY_V6_RECORD_VERSION;
    state->snapshot.flags = state->flags;
    state->snapshot.demo_id = state->demo_id;
    state->snapshot.stage_id = state->stage_id;
    state->snapshot.native_tick = state->native_tick;
    state->snapshot.reference_tick = state->reference_tick;
    state->snapshot.pair_phase = state->pair_phase;
    state->snapshot.source_anchor = state->source_anchor;
    state->snapshot.continuous_mask = GE_RAMROM_GAMEPLAY_V6_CONTINUOUS_PLAYER |
                                      GE_RAMROM_GAMEPLAY_V6_CONTINUOUS_CAMERA;
    state->snapshot.discrete_mask = GE_RAMROM_GAMEPLAY_V6_DISCRETE_RNG;
    state->snapshot.controller_count = 1u;
    state->snapshot.source_hash = state->setup.source_hash;
    state->snapshot.packet_hash = state->setup.packet_hash;
    state->snapshot.rng_checkpoint_hash = 0x1005u;
    state->snapshot.state_hash = 1u;
    state->snapshot.render_hash = 1u;
    state->snapshot.audio_hash = 1u;
}

static void fill_camera(
    GERamRomGameplayPlayerCameraSnapshotV7 *camera,
    uint64_t native_tick,
    uint32_t pair_phase)
{
    memset(camera, 0, sizeof(*camera));
    init_header(&camera->header, (uint32_t)sizeof(*camera));
    camera->record_version = GE_RAMROM_GAMEPLAY_PLAYER_CAMERA_V7_RECORD_VERSION;
    camera->flags = pair_phase == 0u ? 2u : 4u;
    camera->demo_id = 1u;
    camera->stage_id = GE_RAMROM_V5_STAGE_DAM;
    camera->native_tick = native_tick;
    camera->reference_tick = native_tick >> 1;
    camera->pair_phase = pair_phase;
    camera->source_anchor = 7u;
    camera->current_room = pair_phase == 0u ? 4u : 5u;
    camera->current_pad = 11u;
    camera->weapon_model_handle = 0x3001u;
    camera->weapon_action = pair_phase == 0u ? 1u : 0u;
    camera->player_health = 87u;
    camera->hud_ammo = 17u;
    camera->player_animation = 9u;
    camera->player_position_q16[0] = 10 * 65536 + (int32_t)native_tick;
    camera->player_position_q16[1] = 20 * 65536;
    camera->player_position_q16[2] = 30 * 65536;
    camera->player_velocity_q16[0] = 2 * 65536;
    camera->camera_position_q16[0] = 11 * 65536 + (int32_t)native_tick;
    camera->camera_position_q16[1] = 21 * 65536;
    camera->camera_position_q16[2] = 31 * 65536;
    camera->camera_forward_q16[2] = 65536;
    camera->camera_up_q16[1] = 65536;
    camera->source_hash = 0xb001u;
    camera->state_hash = 0xb002u;
    camera->render_hash = 0xb003u;
}

static void fill_event(GERamRomGameplayEventV6 *event)
{
    memset(event, 0, sizeof(*event));
    init_header(&event->header, (uint32_t)sizeof(*event));
    event->record_version = GE_RAMROM_GAMEPLAY_V6_RECORD_VERSION;
    event->event_type = GE_RAMROM_GAMEPLAY_V6_EVENT_STATE;
    event->flags = GE_RAMROM_GAMEPLAY_V6_EVENT_ODD_PAIRED_TICK;
    event->native_tick = 0u;
    event->reference_tick = 0u;
    event->pair_phase = 0u;
    event->demo_id = 1u;
    event->stage_id = GE_RAMROM_V5_STAGE_DAM;
    event->source_hash = 0xc001u;
    event->packet_hash = 0xc002u;
    event->state_hash = 1u;
    event->event_hash = 1u;
}

int main(void)
{
    static GERamRomGameplayStateV6 state;
    GERamRomGameplayPlayerCameraSnapshotV7 camera;
    GERamRomGameplayEventV6 event;
    uint32_t prop_room;
    uint64_t setup_hash;

    assert(sizeof(GERamRomGameplayPlayerCameraSnapshotV7) == 176u);
    fill_state(&state);
    setup_hash = state.setup.source_hash;
    prop_room = state.entities[1].room_id;
    fill_camera(&camera, 0u, 0u);
    fill_event(&event);
    assert(ge_ramrom_gameplay_v6_validate_player_camera_snapshot_v7(&camera) == GE_STATUS_OK);
    assert(ge_ramrom_gameplay_v6_hash_player_camera_snapshot_v7(&camera) != 0u);
    assert(ge_ramrom_gameplay_v6_validate_event(&event) == GE_STATUS_OK);
    assert(ge_ramrom_gameplay_v6_apply_player_camera_snapshot_v7(
               &state, &camera, &event) == GE_STATUS_OK);
    assert(state.entities[0].room_id == camera.current_room);
    assert(state.entities[0].weapon_model_handle == camera.weapon_model_handle);
    assert(state.entities[0].action_state == camera.weapon_action);
    assert(state.entities[0].animation_id == camera.player_animation);
    assert(state.entities[0].health == camera.player_health);
    assert(memcmp(state.entities[0].position_q16, camera.player_position_q16,
                  sizeof(camera.player_position_q16)) == 0);
    assert(state.snapshot.current_room == camera.current_room);
    assert(state.snapshot.current_pad == camera.current_pad);
    assert(memcmp(state.snapshot.camera_position_q16, camera.camera_position_q16,
                  sizeof(camera.camera_position_q16)) == 0);
    assert(state.snapshot.source_frame == camera.source_anchor);
    assert(state.snapshot.state_hash != 0u);
    assert(state.snapshot.render_hash != 0u);
    assert(state.snapshot.audio_hash != 0u);
    assert(event.state_hash == state.snapshot.state_hash);
    assert(event.event_hash == ge_ramrom_gameplay_v6_hash_event(&event));
    assert(state.setup.source_hash == setup_hash);
    assert(state.entities[1].room_id == prop_room);

    state.native_tick = 1u;
    state.pair_phase = 1u;
    state.source_anchor = 0u;
    fill_camera(&camera, 1u, 1u);
    assert(ge_ramrom_gameplay_v6_apply_player_camera_snapshot_v7(
               &state, &camera, NULL) == GE_STATUS_OK);
    assert(state.snapshot.source_anchor == 0u);
    assert(state.snapshot.source_frame == camera.source_anchor);
    assert(state.snapshot.current_room == camera.current_room);
    assert(state.snapshot.audio_hash != 0u);
    assert(ge_ramrom_gameplay_v6_validate_snapshot(&state.snapshot) == GE_STATUS_OK);

    puts("ge_ramrom_gameplay_player_camera_v7_smoke: PASS layout=176 direct=2 eventHash=1");
    return 0;
}
