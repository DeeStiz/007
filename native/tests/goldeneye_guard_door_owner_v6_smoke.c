#include "ge_ramrom_gameplay_v6.h"
#include "ge_guard_door_owner_v6.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint64_t fnv_bytes(const uint8_t *bytes, size_t count)
{
    uint64_t hash = UINT64_C(1469598103934665603);
    size_t index;
    for (index = 0u; index < count; index++) {
        hash = (hash ^ bytes[index]) * UINT64_C(1099511628211);
    }
    return hash;
}

static uint32_t read_u32(const uint8_t *bytes, size_t offset)
{
    return ((uint32_t)bytes[offset] << 24) |
           ((uint32_t)bytes[offset + 1u] << 16) |
           ((uint32_t)bytes[offset + 2u] << 8) |
           (uint32_t)bytes[offset + 3u];
}

static uint8_t *read_file(const char *path, size_t *out_size)
{
    FILE *file;
    long length;
    uint8_t *bytes;
    size_t read_count;
    if (path == NULL || out_size == NULL) return NULL;
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
    read_count = fread(bytes, 1u, (size_t)length, file);
    fclose(file);
    if (read_count != (size_t)length) {
        free(bytes);
        return NULL;
    }
    *out_size = read_count;
    return bytes;
}

static uint32_t model_handle(const uint8_t *bytes, size_t size)
{
    if (bytes == NULL || size < 12u || memcmp(bytes, "GESM", 4u) != 0) return 0u;
    return read_u32(bytes, 8u);
}

static int find_source_objects(const uint8_t *bytes, size_t size,
                               size_t *guard_offset, size_t *door_offset)
{
    static const uint32_t word_sizes[49] = {
        1u, 64u, 2u, 32u, 33u, 32u, 59u, 33u, 34u, 7u,
        64u, 149u, 32u, 54u, 3u, 1u, 1u, 32u, 3u, 4u,
        45u, 34u, 4u, 4u, 1u, 2u, 2u, 2u, 2u, 2u,
        4u, 1u, 4u, 5u, 4u, 4u, 32u, 10u, 4u, 44u,
        45u, 1u, 32u, 1u, 1u, 56u, 7u, 37u, 1u,
    };
    uint32_t offsets[10];
    uint32_t object_end;
    size_t offset;
    size_t index;
    int got_guard = 0;
    int got_door = 0;
    if (bytes == NULL || size < 40u || guard_offset == NULL || door_offset == NULL) return 0;
    for (index = 0u; index < 10u; index++) offsets[index] = read_u32(bytes, index * 4u);
    if (offsets[3] == 0u || offsets[3] >= size) return 0;
    object_end = (uint32_t)size;
    for (index = 0u; index < 10u; index++) {
        if (offsets[index] > offsets[3] && offsets[index] < object_end) object_end = offsets[index];
    }
    offset = offsets[3];
    while (offset + 4u <= object_end) {
        uint32_t first = read_u32(bytes, offset);
        uint32_t type = first & 0xffu;
        size_t record_bytes;
        if (type == 48u) break;
        if (type >= 49u) return 0;
        record_bytes = (size_t)word_sizes[type] * 4u;
        if (record_bytes == 0u || offset + record_bytes > object_end) return 0;
        if (type == 9u && !got_guard) {
            *guard_offset = offset;
            got_guard = 1;
        }
        if (type == 1u && !got_door) {
            *door_offset = offset;
            got_door = 1;
        }
        if (got_guard && got_door) return 1;
        offset += record_bytes;
    }
    return 0;
}

static void identity_q16(int32_t *matrix)
{
    memset(matrix, 0, 16u * sizeof(matrix[0]));
    matrix[0] = 65536;
    matrix[5] = 65536;
    matrix[10] = 65536;
    matrix[15] = 65536;
}

static void init_pose(GESourceAnimationPoseV6 *pose, uint32_t skeleton,
                      uint32_t node, uint32_t tick, uint64_t hash)
{
    memset(pose, 0, sizeof(*pose));
    pose->header.abi_version = GE_NATIVE_ABI_VERSION;
    pose->header.struct_size = (uint32_t)sizeof(*pose);
    pose->record_version = GE_SOURCE_SCENE_V6_RECORD_VERSION;
    pose->pose_handle = 0xd7000000u | node;
    pose->skeleton_handle = skeleton;
    pose->node_handle = node;
    pose->parent_handle = node == 1u ? 0u : 1u;
    pose->flags = GE_SOURCE_POSE_V6_FLAG_INTERPOLATABLE;
    pose->animation_tick = tick;
    pose->translation_q16[0] = (int32_t)(node * 1024u);
    pose->translation_q16[1] = node == 1u ? 8192 : 16384;
    pose->translation_q16[2] = (int32_t)(node * 512u);
    pose->rotation_q16[0] = 0;
    pose->rotation_q16[1] = (int32_t)(node * 2048u);
    pose->rotation_q16[2] = 0;
    pose->rotation_q16[3] = 65536;
    pose->scale_q16[0] = 65536;
    pose->scale_q16[1] = 65536;
    pose->scale_q16[2] = 65536;
    pose->pose_hash = hash ^ node ^ tick;
}

int main(int argc, char **argv)
{
    size_t setup_size;
    size_t animation_size;
    size_t body_size;
    size_t head_size;
    size_t weapon_size;
    size_t recording_size;
    uint8_t *setup_bytes;
    uint8_t *animation_bytes;
    uint8_t *body_bytes;
    uint8_t *head_bytes;
    uint8_t *weapon_bytes;
    uint8_t *recording_bytes;
    size_t guard_offset;
    size_t door_offset;
    uint32_t frame_count;
    uint64_t setup_hash;
    uint64_t animation_hash;
    GEGuardDoorOwnerSetupV6 setup;
    GEGuardDoorOwnerGuardSourceV6 guard;
    GEGuardDoorOwnerDoorSourceV6 door;
    GEGuardDoorOwnerChoiceV6 head_choice;
    GEGuardDoorOwnerChoiceV6 weapon_choice;
    GEGuardDoorOwnerAttachmentV6 attachment;
    GESourceAnimationPoseV6 poses[4];
    GEGuardDoorOwnerStateV6 state;
    GEGuardDoorOwnerEventV6 event;
    GERamRomGameplayEntityV6 entities[2];
    GERamRomGameplayAttachmentV6 gameplay_attachments[1];
    GERamRomGameplaySetupV6 gameplay_setup;
    GERamRomGameplayEntityV6 gameplay_player;
    GERamRomGameplayStateV6 gameplay_state;
    GERamRomGameplayEventV6 gameplay_event;
    GERamRomGameplayInputV6 gameplay_input;
    GEGuardDoorOwnerStateV6 owner_for_gameplay;
    uint32_t entity_count;
    uint32_t attachment_count;
    uint32_t status;

    if (argc != 7) {
        fprintf(stderr, "usage: guard_door_owner_smoke Dam.setup animationtable body.gesm head.gesm weapon.gesm ramrom.bin\n");
        return 2;
    }
    setup_bytes = read_file(argv[1], &setup_size);
    animation_bytes = read_file(argv[2], &animation_size);
    body_bytes = read_file(argv[3], &body_size);
    head_bytes = read_file(argv[4], &head_size);
    weapon_bytes = read_file(argv[5], &weapon_size);
    recording_bytes = read_file(argv[6], &recording_size);
    if (setup_bytes == NULL || animation_bytes == NULL || body_bytes == NULL ||
        head_bytes == NULL || weapon_bytes == NULL || recording_bytes == NULL ||
        !find_source_objects(setup_bytes, setup_size, &guard_offset, &door_offset) ||
        animation_size <= 0x4018u + 8u ||
        model_handle(body_bytes, body_size) == 0u || model_handle(head_bytes, head_size) == 0u ||
        model_handle(weapon_bytes, weapon_size) == 0u) {
        fprintf(stderr, "prepared source page inputs are incomplete\n");
        free(setup_bytes); free(animation_bytes); free(body_bytes); free(head_bytes); free(weapon_bytes); free(recording_bytes);
        return 1;
    }
    frame_count = ((uint32_t)animation_bytes[0x4018u + 4u] << 8) |
                  (uint32_t)animation_bytes[0x4018u + 5u];
    setup_hash = fnv_bytes(setup_bytes, setup_size);
    animation_hash = fnv_bytes(animation_bytes, animation_size);
    if (frame_count == 0u || animation_hash == 0u) return 1;

    memset(&setup, 0, sizeof(setup));
    setup.header.abi_version = GE_NATIVE_ABI_VERSION;
    setup.header.struct_size = (uint32_t)sizeof(setup);
    setup.record_version = GE_GUARD_DOOR_OWNER_V6_RECORD_VERSION;
    setup.demo_id = 1u;
    setup.stage_id = 33u;
    setup.source_bytes = (uint32_t)setup_size;
    setup.flags = GE_GUARD_DOOR_OWNER_V6_SETUP_FLAG_POSES |
                  GE_GUARD_DOOR_OWNER_V6_SETUP_FLAG_AI |
                  GE_GUARD_DOOR_OWNER_V6_SETUP_FLAG_BOUND_PAD_TRANSFORMS |
                  GE_GUARD_DOOR_OWNER_V6_SETUP_FLAG_MODEL_DEPENDENCIES |
                  GE_GUARD_DOOR_OWNER_V6_SETUP_FLAG_SOURCE_READY;
    setup.guard_count = 1u;
    setup.door_count = 1u;
    setup.room_count = 1u;
    setup.portal_count = 1u;
    setup.source_hash = setup_hash;
    setup.packet_hash = setup_hash ^ UINT64_C(0x51a7);
    setup.model_dependency_hash = (uint64_t)model_handle(body_bytes, body_size) ^ model_handle(weapon_bytes, weapon_size);
    setup.animation_source_hash = animation_hash;

    memset(&guard, 0, sizeof(guard));
    guard.header.abi_version = GE_NATIVE_ABI_VERSION;
    guard.header.struct_size = (uint32_t)sizeof(guard);
    guard.record_version = GE_GUARD_DOOR_OWNER_V6_RECORD_VERSION;
    guard.source_record_offset = (uint32_t)guard_offset;
    guard.guard_id = (read_u32(setup_bytes, guard_offset + 4u) >> 16) & 0xffffu;
    guard.chr_num = guard.guard_id;
    guard.pad_id = read_u32(setup_bytes, guard_offset + 4u) & 0xffffu;
    guard.body_id = read_u32(setup_bytes, guard_offset + 8u) >> 16;
    guard.head_id = GE_GUARD_DOOR_OWNER_V6_UNKNOWN_U32;
    guard.weapon_id = GE_GUARD_DOOR_OWNER_V6_UNKNOWN_U32;
    guard.ai_list_id = read_u32(setup_bytes, guard_offset + 8u) & 0xffffu;
    guard.preset = read_u32(setup_bytes, guard_offset + 12u) >> 16;
    guard.chr_preset = read_u32(setup_bytes, guard_offset + 12u) & 0xffffu;
    guard.health = 1000u;
    guard.health_current = 1000u;
    guard.reaction_time = 100u;
    guard.source_bitflags = read_u32(setup_bytes, guard_offset + 20u) >> 16;
    guard.body_model_handle = model_handle(body_bytes, body_size);
    guard.head_model_handle = model_handle(head_bytes, head_size);
    guard.weapon_model_handle = model_handle(weapon_bytes, weapon_size);
    guard.skeleton_handle = guard.body_model_handle ^ UINT32_C(0x10000000);
    guard.animation_id = 66u;
    guard.animation_frame_count = frame_count;
    guard.animation_frame_q16 = 0;
    guard.animation_next_frame_q16 = 32768;
    guard.animation_speed_q16 = 32768;
    guard.animation_merge_q16 = 65536;
    guard.animation_flip_flags = 0u;
    guard.action_state = 1u;
    guard.death_state = 0u;
    guard.visibility_state = 1u;
    guard.ai_state = 1u;
    guard.render_flags = 1u;
    guard.zbuffer_mode = 1u;
    guard.environment_rgba = 0x102030ffu;
    guard.fog_rgba = 0x405060ffu;
    guard.raw_other_mode_h = 0x00100000u;
    guard.raw_render_mode = 0xc4112078u;
    guard.scale_q16[0] = 65536; guard.scale_q16[1] = 65536; guard.scale_q16[2] = 65536;
    identity_q16(guard.world_transform_q16);
    guard.world_transform_q16[12] = 131072;
    guard.world_transform_q16[13] = 65536;
    guard.world_transform_q16[14] = -131072;
    memcpy(guard.position_q16, &guard.world_transform_q16[12], sizeof(guard.position_q16));
    guard.next_position_q16[0] = guard.position_q16[0] + 4096;
    guard.next_position_q16[1] = guard.position_q16[1];
    guard.next_position_q16[2] = guard.position_q16[2] + 4096;
    guard.root_motion_next_q16[0] = 4096;
    guard.root_motion_next_q16[2] = 4096;
    guard.pose_first = 0u; guard.pose_count = 2u;
    guard.pose_next_first = 2u; guard.pose_next_count = 2u;
    guard.attachment_first = 0u; guard.attachment_count = 1u;
    guard.head_choice_count = 1u; guard.weapon_choice_count = 1u;
    head_choice.source_id = 52u; head_choice.model_handle = guard.head_model_handle;
    head_choice.source_handle = guard.head_model_handle; guard.head_choices[0] = head_choice;
    weapon_choice.source_id = 90u; weapon_choice.model_handle = guard.weapon_model_handle;
    weapon_choice.source_handle = guard.weapon_model_handle; guard.weapon_choices[0] = weapon_choice;
    guard.source_hash = setup_hash ^ guard_offset;
    guard.animation_hash = animation_hash;
    guard.pose_hash = animation_hash ^ UINT64_C(0x3301);
    guard.source_event_hash = guard.pose_hash ^ guard.source_hash;

    memset(&attachment, 0, sizeof(attachment));
    attachment.switch_handle = 3u;
    attachment.parent_joint = 1u;
    attachment.model_handle = guard.weapon_model_handle;
    attachment.source_matrix_handle = guard.body_model_handle;
    attachment.flags = GE_SOURCE_POSE_V6_FLAG_WEAPON_ATTACHMENT;
    identity_q16(attachment.transform_q16);
    attachment.transform_q16[13] = 32768;
    attachment.source_hash = animation_hash ^ UINT64_C(0x44);

    init_pose(&poses[0], guard.skeleton_handle, 1u, 0u, guard.pose_hash);
    init_pose(&poses[1], guard.skeleton_handle, 2u, 0u, guard.pose_hash ^ 1u);
    init_pose(&poses[2], guard.skeleton_handle, 1u, 1u, guard.pose_hash ^ 2u);
    init_pose(&poses[3], guard.skeleton_handle, 2u, 1u, guard.pose_hash ^ 3u);

    memset(&door, 0, sizeof(door));
    door.header.abi_version = GE_NATIVE_ABI_VERSION;
    door.header.struct_size = (uint32_t)sizeof(door);
    door.record_version = GE_GUARD_DOOR_OWNER_V6_RECORD_VERSION;
    door.source_record_offset = (uint32_t)door_offset;
    door.door_id = 1u;
    door.object_id = read_u32(setup_bytes, door_offset + 4u) >> 16;
    door.pad_id = read_u32(setup_bytes, door_offset + 4u) & 0xffffu;
    door.source_flags = read_u32(setup_bytes, door_offset + 8u);
    door.source_flags2 = read_u32(setup_bytes, door_offset + 12u);
    door.door_flags = read_u32(setup_bytes, door_offset + 0x98u) >> 16;
    door.door_type = read_u32(setup_bytes, door_offset + 0x98u) & 0xffffu;
    door.max_frac_q16 = (int32_t)read_u32(setup_bytes, door_offset + 0x84u);
    door.perim_frac_q16 = (int32_t)read_u32(setup_bytes, door_offset + 0x88u);
    door.accel_q16 = (int32_t)read_u32(setup_bytes, door_offset + 0x8cu);
    door.decel_q16 = (int32_t)read_u32(setup_bytes, door_offset + 0x90u);
    door.max_speed_q16 = (int32_t)read_u32(setup_bytes, door_offset + 0x94u);
    door.key_flags = read_u32(setup_bytes, door_offset + 0x9cu);
    door.auto_close_frames = read_u32(setup_bytes, door_offset + 0xa0u);
    door.portal_number = read_u32(setup_bytes, door_offset + 0xf0u);
    door.open_state = GE_GUARD_DOOR_OWNER_V6_DOOR_STATE_STATIONARY;
    door.visibility_state = 1u;
    door.model_handle = model_handle(weapon_bytes, weapon_size);
    door.open_position_q16 = 0;
    door.next_open_position_q16 = 0;
    door.speed_q16 = 0;
    door.next_speed_q16 = 0;
    door.frac_q16[0] = 65536;
    door.runtime_position_q16[0] = 262144;
    door.runtime_position_q16[1] = 0;
    door.runtime_position_q16[2] = -262144;
    identity_q16(door.base_transform_q16);
    door.base_transform_q16[12] = door.runtime_position_q16[0];
    door.base_transform_q16[13] = door.runtime_position_q16[1];
    door.base_transform_q16[14] = door.runtime_position_q16[2];
    door.source_hash = setup_hash ^ (uint32_t)door_offset;
    door.source_hash64 = setup_hash ^ UINT64_C(0x5d0d);
    door.source_event_hash = door.source_hash64 ^ animation_hash;

    status = ge_guard_door_owner_v6_begin(
        &setup, &guard, 1u, &door, 1u, poses, 4u, &attachment, 1u,
        UINT64_C(0xab8d9f7781280783), &state, &event
    );
    if (status != GE_STATUS_OK || event.event_type != GE_GUARD_DOOR_OWNER_V6_EVENT_INSTALL ||
        state.guard_count != 1u || state.door_count != 1u || state.attachment_count != 1u) {
        fprintf(stderr, "guard/door begin failed: %u\n", status);
        return 1;
    }
    {
        GEGuardDoorOwnerStateV6 authority_state = state;
        GEGuardDoorOwnerEventV6 authority_event;
        authority_state.doors[0].source.open_state =
            GE_GUARD_DOOR_OWNER_V6_DOOR_STATE_OPENING;
        authority_state.doors[0].source.open_position_q16 = 0;
        authority_state.doors[0].source.speed_q16 = 0;
        status = ge_guard_door_owner_v6_step_source_authority(
            1u, &authority_state, &authority_event
        );
        if (status != GE_STATUS_OK || authority_event.event_type != GE_GUARD_DOOR_OWNER_V6_EVENT_INTERPOLATED) {
            fprintf(stderr, "source authority odd step failed: %u\n", status);
            return 1;
        }
        status = ge_guard_door_owner_v6_step_source_authority(
            2u, &authority_state, &authority_event
        );
        if (status != GE_STATUS_OK || authority_event.event_type != GE_GUARD_DOOR_OWNER_V6_EVENT_SOURCE_ANCHOR ||
            authority_state.state_hash == 0u || authority_state.doors[0].source.portal_active != 1u) {
            fprintf(stderr, "source authority anchor step failed: %u\n", status);
            return 1;
        }
    }
    owner_for_gameplay = state;
    memset(&gameplay_setup, 0, sizeof(gameplay_setup));
    gameplay_setup.header.abi_version = GE_NATIVE_ABI_VERSION;
    gameplay_setup.header.struct_size = (uint32_t)sizeof(gameplay_setup);
    gameplay_setup.record_version = GE_RAMROM_GAMEPLAY_V6_RECORD_VERSION;
    gameplay_setup.stage_id = 33u;
    gameplay_setup.flags = GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_SOURCE_DERIVED |
                           GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_ROOMS |
                           GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_STAN |
                           GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_OBJECTS |
                           GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_AI |
                           GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_PORTALS |
                           GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_MODEL_DEPENDENCIES;
    gameplay_setup.demo_mask = 1u;
    gameplay_setup.source_bytes = (uint32_t)setup_size;
    gameplay_setup.room_count = 1u;
    gameplay_setup.portal_count = 1u;
    gameplay_setup.stan_count = 1u;
    gameplay_setup.object_count = 2u;
    gameplay_setup.door_count = 1u;
    gameplay_setup.guard_count = 1u;
    gameplay_setup.initial_room = 0u;
    gameplay_setup.initial_pad = 0u;
    gameplay_setup.stan_source_bytes = 1u;
    gameplay_setup.initial_position_q16[0] = 0;
    gameplay_setup.initial_position_q16[1] = 65536;
    gameplay_setup.initial_position_q16[2] = 0;
    gameplay_setup.initial_forward_q16[2] = 65536;
    gameplay_setup.world_min_q16[0] = -65536;
    gameplay_setup.world_min_q16[1] = -65536;
    gameplay_setup.world_min_q16[2] = -65536;
    gameplay_setup.world_max_q16[0] = 65536;
    gameplay_setup.world_max_q16[1] = 65536;
    gameplay_setup.world_max_q16[2] = 65536;
    gameplay_setup.source_hash = setup_hash;
    gameplay_setup.packet_hash = setup_hash ^ UINT64_C(0x77a1);
    gameplay_setup.model_dependency_hash = setup.model_dependency_hash;
    gameplay_setup.stan_source_hash = setup_hash ^ UINT64_C(0x5a11);
    gameplay_setup.stan_bounds_hash = setup_hash ^ UINT64_C(0x5a12);
    gameplay_setup.spawn_hash = setup_hash ^ UINT64_C(0x5a13);
    memset(&gameplay_player, 0, sizeof(gameplay_player));
    gameplay_player.header.abi_version = GE_NATIVE_ABI_VERSION;
    gameplay_player.header.struct_size = (uint32_t)sizeof(gameplay_player);
    gameplay_player.record_version = GE_RAMROM_GAMEPLAY_V6_RECORD_VERSION;
    gameplay_player.entity_id = 1u;
    gameplay_player.entity_kind = GE_RAMROM_GAMEPLAY_V6_ENTITY_PLAYER;
    gameplay_player.flags = GE_RAMROM_GAMEPLAY_V6_ENTITY_ACTIVE;
    gameplay_player.room_id = 0u;
    gameplay_player.source_prop_type = GE_RAMROM_GAMEPLAY_V6_UNKNOWN_U32;
    gameplay_player.source_record_offset = GE_RAMROM_GAMEPLAY_V6_UNKNOWN_U32;
    gameplay_player.scale_q16[0] = 65536;
    gameplay_player.scale_q16[1] = 65536;
    gameplay_player.scale_q16[2] = 65536;
    gameplay_player.merge_weight_q16 = 65536;
    identity_q16(gameplay_player.source_transform_q16);
    gameplay_player.position_q16[1] = 65536;
    status = ge_ramrom_gameplay_v6_begin_with_source_pages_and_guard_door_owner(
        recording_bytes, (uint32_t)recording_size, 1u, &gameplay_setup,
        &gameplay_player, 1u, NULL, 0u, &owner_for_gameplay,
        &gameplay_state, &gameplay_event
    );
    if (status != GE_STATUS_OK ||
        (gameplay_state.flags & GE_RAMROM_GAMEPLAY_V6_STATE_FLAG_GUARD_DOOR_OWNER) == 0u ||
        gameplay_state.entity_count != 3u || gameplay_state.attachment_count != 1u) {
        fprintf(stderr, "gameplay owner install failed: %u entities=%u attachments=%u\n",
                status, gameplay_state.entity_count, gameplay_state.attachment_count);
        return 1;
    }
    memset(&gameplay_input, 0, sizeof(gameplay_input));
    gameplay_input.header.abi_version = GE_NATIVE_ABI_VERSION;
    gameplay_input.header.struct_size = (uint32_t)sizeof(gameplay_input);
    gameplay_input.record_version = GE_RAMROM_GAMEPLAY_V6_RECORD_VERSION;
    gameplay_input.flags = GE_RAMROM_GAMEPLAY_V6_INPUT_FOCUSED |
                           GE_RAMROM_GAMEPLAY_V6_INPUT_CONTROLLER;
    gameplay_input.controller_count = 1u;
    status = ge_ramrom_gameplay_v6_step_with_guard_door_owner(
        recording_bytes, (uint32_t)recording_size, 0u, gameplay_input,
        &owner_for_gameplay, &gameplay_state, &gameplay_event
    );
    if (status != GE_STATUS_OK || gameplay_event.detail0 != 1u ||
        gameplay_event.detail1 != 1u || gameplay_state.entity_count != 3u) {
        fprintf(stderr, "gameplay owner paired step failed: %u\n", status);
        return 1;
    }
    {
        GEGuardDoorOwnerGuardSourceV6 missing = guard;
        GEGuardDoorOwnerStateV6 failed_state;
        GEGuardDoorOwnerEventV6 failed_event;
        missing.pose_count = 0u;
        if (ge_guard_door_owner_v6_begin(
                &setup, &missing, 1u, &door, 1u, poses, 4u, &attachment, 1u,
                UINT64_C(0x1234), &failed_state, &failed_event
            ) == GE_STATUS_OK) {
            fprintf(stderr, "missing pose page did not fail closed\n");
            return 1;
        }
    }
    {
        uint64_t rng_before = state.rng_checkpoint_hash;
        status = ge_guard_door_owner_v6_step(
            1u, NULL, 1u, NULL, 1u, NULL, 0u, NULL, 0u, &state, &event
        );
        if (status != GE_STATUS_OK || event.event_type != GE_GUARD_DOOR_OWNER_V6_EVENT_INTERPOLATED ||
            state.rng_checkpoint_hash != rng_before || state.guards[0].interpolated == 0u) {
            fprintf(stderr, "odd interpolation failed: %u\n", status);
            return 1;
        }
    }
    door.open_state = GE_GUARD_DOOR_OWNER_V6_DOOR_STATE_OPENING;
    door.next_open_position_q16 = 16;
    door.next_speed_q16 = 16;
    status = ge_guard_door_owner_v6_step(
        2u, &guard, 1u, &door, 1u, poses, 4u, &attachment, 1u, &state, &event
    );
    if (status != GE_STATUS_OK || event.event_type != GE_GUARD_DOOR_OWNER_V6_EVENT_SOURCE_ANCHOR ||
        state.pair_phase != 0u || state.doors[0].source.open_position_q16 != 0) {
        fprintf(stderr, "source anchor failed: %u\n", status);
        return 1;
    }
    status = ge_guard_door_owner_v6_copy_gameplay_pages(
        &state, 2u, entities, 1u, gameplay_attachments, &entity_count, &attachment_count
    );
    if (status != GE_STATUS_OK || entity_count != 2u || attachment_count != 1u ||
        ge_ramrom_gameplay_v6_validate_entity(&entities[0]) != GE_STATUS_OK ||
        ge_ramrom_gameplay_v6_validate_attachment(&gameplay_attachments[0]) != GE_STATUS_OK) {
        fprintf(stderr, "gameplay adapter failed: %u\n", status);
        return 1;
    }
    printf("goldeneye_guard_door_owner_v6_smoke: PASS sourceObjects=2 guards=1 doors=1 poses=2 rng=1 interpolation=1 portalLifecycle=1 adapter=1 gameplayIntegration=1\n");
    free(setup_bytes); free(animation_bytes); free(body_bytes); free(head_bytes); free(weapon_bytes); free(recording_bytes);
    return 0;
}
