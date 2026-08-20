#include "ge_player_camera_owner_v6.h"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void init_header(GEAbiHeaderV1 *header, uint32_t size)
{
    header->abi_version = GE_NATIVE_ABI_VERSION;
    header->struct_size = size;
}

static void fill_setup(GERamRomGameplaySetupV6 *setup)
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
    setup->demo_mask = UINT32_C(1);
    setup->source_bytes = UINT32_C(1);
    setup->room_count = UINT32_C(1);
    setup->stan_count = UINT32_C(1);
    setup->object_count = UINT32_C(1);
    setup->initial_room = 0u;
    setup->initial_pad = 7u;
    setup->stan_source_bytes = 1u;
    setup->initial_position_q16[0] = 0;
    setup->initial_position_q16[1] = 0;
    setup->initial_position_q16[2] = 0;
    setup->initial_forward_q16[0] = 0;
    setup->initial_forward_q16[1] = 0;
    setup->initial_forward_q16[2] = 65536;
    setup->world_min_q16[0] = -655360;
    setup->world_min_q16[1] = -655360;
    setup->world_min_q16[2] = -655360;
    setup->world_max_q16[0] = 655360;
    setup->world_max_q16[1] = 655360;
    setup->world_max_q16[2] = 655360;
    setup->source_hash = UINT64_C(0x3300000000000001);
    setup->packet_hash = UINT64_C(0x3300000000000002);
    setup->model_dependency_hash = UINT64_C(0x3300000000000003);
    setup->stan_source_hash = UINT64_C(0x3300000000000004);
    setup->stan_bounds_hash = UINT64_C(0x3300000000000005);
    setup->spawn_hash = UINT64_C(0x3300000000000006);
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
    player->weapon_model_handle = UINT32_C(0x2001);
    player->animation_id = 2u;
    player->room_id = 0u;
    player->health = 100u;
    player->max_health = 100u;
    player->position_q16[0] = 0;
    player->position_q16[1] = 0;
    player->position_q16[2] = 0;
    player->scale_q16[0] = 65536;
    player->scale_q16[1] = 65536;
    player->scale_q16[2] = 65536;
    player->merge_weight_q16 = 65536;
}

static void fill_source(GEPlayerCameraSourceV6 *source)
{
    memset(source, 0, sizeof(*source));
    init_header(&source->header, (uint32_t)sizeof(*source));
    source->record_version = GE_PLAYER_CAMERA_OWNER_V6_RECORD_VERSION;
    source->stage_id = GE_RAMROM_V5_STAGE_DAM;
    source->demo_mask = UINT32_C(1);
    source->flags = GE_PLAYER_CAMERA_OWNER_V6_REQUIRED_SOURCE_MASK |
                    GE_PLAYER_CAMERA_OWNER_V6_SOURCE_PADS;
    source->control_style = GE_PLAYER_CAMERA_OWNER_V6_CONTROL_HONEY;
    source->invert_look = 0u;
    source->source_spawn_offset = UINT32_C(0x20);
    source->source_camera_offset = UINT32_C(0x40);
    source->source_collision_offset = UINT32_C(0x60);
    source->initial_pitch_q16 = -262144;
    source->camera_offset_q16[0] = 0;
    source->camera_offset_q16[1] = 65536;
    source->camera_offset_q16[2] = 0;
    source->head_offset_q16[0] = 0;
    source->head_offset_q16[1] = 0;
    source->head_offset_q16[2] = 0;
    source->collision_radius_q16 = 65536;
    source->collision_height_q16 = 196608;
    source->floor_tolerance_q16 = 65536;
    source->pad_select_radius_q16 = 65536;
    source->initial_weapon = UINT32_C(0x2001);
    source->initial_ammo = 12u;
    source->initial_health = 100u;
    source->initial_animation = 2u;
    source->source_hash = UINT64_C(0x3300000000000011);
    source->setup_hash = UINT64_C(0x3300000000000012);
    source->player_hash = UINT64_C(0x3300000000000013);
}

static void fill_tile(GEPlayerCameraStanTileV6 *tile)
{
    memset(tile, 0, sizeof(*tile));
    init_header(&tile->header, (uint32_t)sizeof(*tile));
    tile->record_version = GE_PLAYER_CAMERA_OWNER_V6_RECORD_VERSION;
    tile->tile_id = 1u;
    tile->room_id = 0u;
    tile->flags = GE_PLAYER_CAMERA_OWNER_V6_TILE_FLAG_SOURCE_DERIVED |
                  GE_PLAYER_CAMERA_OWNER_V6_TILE_FLAG_FLOOR;
    tile->point_count = 4u;
    tile->points_q16[0][0] = -655360;
    tile->points_q16[0][1] = 0;
    tile->points_q16[0][2] = -655360;
    tile->points_q16[1][0] = 655360;
    tile->points_q16[1][1] = 0;
    tile->points_q16[1][2] = -655360;
    tile->points_q16[2][0] = 655360;
    tile->points_q16[2][1] = 0;
    tile->points_q16[2][2] = 655360;
    tile->points_q16[3][0] = -655360;
    tile->points_q16[3][1] = 0;
    tile->points_q16[3][2] = 655360;
    tile->source_hash = UINT64_C(0x3300000000000021);
    tile->source_offset = UINT32_C(0x100);
}

static void fill_pad(GEPlayerCameraPadV6 *pad)
{
    memset(pad, 0, sizeof(*pad));
    init_header(&pad->header, (uint32_t)sizeof(*pad));
    pad->record_version = GE_PLAYER_CAMERA_OWNER_V6_RECORD_VERSION;
    pad->pad_id = 7u;
    pad->room_id = 0u;
    pad->flags = GE_PLAYER_CAMERA_OWNER_V6_PAD_FLAG_SOURCE_DERIVED |
                 GE_PLAYER_CAMERA_OWNER_V6_PAD_FLAG_SPAWN;
    pad->forward_q16[2] = 65536;
    pad->source_offset = UINT32_C(0x200);
}

static GERamRomGameplayInputV6 input_value(int16_t x, int16_t y, uint32_t buttons)
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
    input.stick_x = x;
    input.stick_y = y;
    input.pressed_buttons = buttons;
    input.held_buttons = buttons;
    input.source_mask = GE_RAMROM_GAMEPLAY_V6_INPUT_CONTROLLER;
    return input;
}

static uint32_t load_dam_demo_sample(const char *path, GERamRomSampleV5 *out_sample)
{
    FILE *file;
    long file_size;
    uint8_t *bytes;
    GERamRomHeaderV5 header;
    GERamRomParseSummaryV5 summary;
    GERamRomPacketV5 packet;
    GEStatusV1 status;
    if (path == NULL || out_sample == NULL) {
        return 0u;
    }
    file = fopen(path, "rb");
    if (file == NULL || fseek(file, 0L, SEEK_END) != 0) {
        if (file != NULL) { fclose(file); }
        return 0u;
    }
    file_size = ftell(file);
    if (file_size <= 0L || file_size > 16L * 1024L * 1024L ||
        fseek(file, 0L, SEEK_SET) != 0) {
        fclose(file);
        return 0u;
    }
    bytes = malloc((size_t)file_size);
    if (bytes == NULL || fread(bytes, 1u, (size_t)file_size, file) != (size_t)file_size) {
        free(bytes);
        fclose(file);
        return 0u;
    }
    fclose(file);
    status = ge_ramrom_v5_read_header(bytes, (uint32_t)file_size, &header);
    assert(status == GE_STATUS_OK);
    status = ge_ramrom_v5_parse(bytes, (uint32_t)file_size, &summary);
    assert(status == GE_STATUS_OK);
    assert(header.stage_id == GE_RAMROM_V5_STAGE_DAM);
    assert(summary.checksum_valid_count == summary.packet_count);
    assert(summary.rng_checkpoint_count != 0u);
    status = ge_ramrom_v5_read_packet(bytes, (uint32_t)file_size, 0u, &packet);
    assert(status == GE_STATUS_OK);
    assert(packet.checksum == packet.computed_checksum);
    status = ge_ramrom_v5_copy_sample(bytes, (uint32_t)file_size, 0u, 0u, 0u, out_sample);
    assert(status == GE_STATUS_OK);
    assert(ge_ramrom_v5_validate_sample(out_sample) == GE_STATUS_OK);
    printf("dam1-recording hash=%llu packets=%u rng-checkpoints=%u first-input=(%d,%d,0x%08x)\n",
           (unsigned long long)summary.recording_hash,
           summary.packet_count,
           summary.rng_checkpoint_count,
           out_sample->stick_x, out_sample->stick_y, out_sample->buttons);
    free(bytes);
    return 1u;
}

static void test_owner_route(const char *recording_path)
{
    GERamRomGameplaySetupV6 setup;
    GERamRomGameplayEntityV6 player;
    GEPlayerCameraSourceV6 source;
    GEPlayerCameraStanTileV6 tile;
    GEPlayerCameraPadV6 pad;
    GEPlayerCameraEventV6 event;
    GEPlayerCameraOwnerStateV6 *state = calloc(1u, sizeof(*state));
    GEPlayerCameraSnapshotV6 snapshot;
    GERamRomSampleV5 dam_sample;
    uint32_t has_dam_sample;
    GEStatusV1 status;
    uint64_t first_position_hash;
    assert(state != NULL);
    fill_setup(&setup);
    fill_player(&player);
    fill_source(&source);
    fill_tile(&tile);
    fill_pad(&pad);
    has_dam_sample = load_dam_demo_sample(recording_path, &dam_sample);

    status = ge_player_camera_owner_begin_from_gameplay_pages(
        1u, &setup, &player, 1u, &source, &tile, 1u, &pad, 1u, state, &event);
    assert(status == GE_STATUS_OK);
    assert(event.event_type == GE_PLAYER_CAMERA_OWNER_V6_EVENT_INSTALL);
    assert(ge_player_camera_owner_validate_state(state) == GE_STATUS_OK);

    status = ge_player_camera_owner_step(
        0u,
        has_dam_sample ? input_value(dam_sample.stick_x, dam_sample.stick_y,
                                     dam_sample.buttons) : input_value(0, 70, 0u),
        state, &event);
    assert(status == GE_STATUS_OK);
    assert(event.event_type == GE_PLAYER_CAMERA_OWNER_V6_EVENT_SOURCE_ANCHOR);
    if (has_dam_sample == 0u) {
        assert(state->current_anchor.player_position_q16[2] > 0);
    }
    assert(state->current_room == 0u);
    first_position_hash = state->current_anchor.state_hash;

    status = ge_player_camera_owner_step(1u, input_value(0, 0, 0u), state, &event);
    assert(status == GE_STATUS_OK);
    assert(event.event_type == GE_PLAYER_CAMERA_OWNER_V6_EVENT_INTERPOLANT);
    assert((state->render_snapshot.flags & GE_PLAYER_CAMERA_OWNER_V6_STATE_INTERPOLATED) != 0u);
    if (state->current_anchor.player_position_q16[2] > 0) {
        assert(state->render_snapshot.player_position_q16[2] > 0);
        assert(state->render_snapshot.player_position_q16[2] <
               state->current_anchor.player_position_q16[2]);
    } else {
        assert(state->render_snapshot.player_position_q16[2] == 0);
    }

    status = ge_player_camera_owner_step(2u, input_value(70, 0, 0u), state, &event);
    assert(status == GE_STATUS_OK);
    assert(state->current_anchor.yaw_q16 != state->previous_anchor.yaw_q16);
    assert(state->current_anchor.state_hash != first_position_hash);

    status = ge_player_camera_owner_step(3u, input_value(0, 0, 0u), state, &event);
    assert(status == GE_STATUS_OK);
    status = ge_player_camera_owner_copy_snapshot(state, &snapshot);
    assert(status == GE_STATUS_OK);
    assert(snapshot.native_tick == 3u && snapshot.pair_phase == 1u);
    assert(snapshot.camera_position_q16[1] == snapshot.player_position_q16[1] + 65536);

    status = ge_player_camera_owner_step(
        4u, input_value(0, 0, GE_PLAYER_CAMERA_OWNER_V6_BUTTON_Z), state, &event);
    assert(status == GE_STATUS_OK);
    assert(event.event_type == GE_PLAYER_CAMERA_OWNER_V6_EVENT_WEAPON);
    assert(state->weapon_sequence == 1u);
    assert(state->current_anchor.weapon_action == 1u);

    {
        GERamRomGameplayInputV6 real_input = input_value(0, 0, GE_PLAYER_CAMERA_OWNER_V6_BUTTON_A);
        real_input.flags |= GE_RAMROM_GAMEPLAY_V6_INPUT_REAL;
        status = ge_player_camera_owner_step(5u, real_input, state, &event);
        assert(status == GE_STATUS_OK);
        assert(event.event_type == GE_PLAYER_CAMERA_OWNER_V6_EVENT_ABORT);
        assert(state->owner_state == GE_PLAYER_CAMERA_OWNER_V6_STATE_ABORTING);
    }

    source.flags &= ~GE_PLAYER_CAMERA_OWNER_V6_SOURCE_CAMERA;
    status = ge_player_camera_owner_begin_from_gameplay_pages(
        1u, &setup, &player, 1u, &source, &tile, 1u, &pad, 1u, state, &event);
    assert(status == GE_STATUS_MALFORMED_STREAM);
    free(state);
}

int main(int argc, char **argv)
{
    const char *recording_path = argc > 1 ? argv[1] : NULL;
    test_owner_route(recording_path);
    puts("ge_player_camera_owner_v6_smoke: PASS source=Dam1 ticks=6 interpolant=1 weapon=1 abort=1");
    return 0;
}
