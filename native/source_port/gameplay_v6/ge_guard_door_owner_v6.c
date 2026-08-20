#include "ge_guard_door_owner_v6.h"
#include "ge_ramrom_gameplay_v6.h"

#include <limits.h>
#include <stddef.h>
#include <string.h>

/* The source randomGetNextFrom transition is exported by the gameplay V6
   owner.  Keeping the call here makes selection use exactly the same source
   RNG as RAMROM playback while avoiding a second host RNG implementation. */

static const uint64_t GE_GD_FNV_OFFSET = UINT64_C(1469598103934665603);
static const uint64_t GE_GD_FNV_PRIME = UINT64_C(1099511628211);

static uint64_t gd_hash_byte(uint64_t hash, uint8_t byte)
{
    return (hash ^ (uint64_t)byte) * GE_GD_FNV_PRIME;
}

static uint64_t gd_hash_u32(uint64_t hash, uint32_t value)
{
    uint32_t shift;
    for (shift = 0u; shift < 32u; shift += 8u) {
        hash = gd_hash_byte(hash, (uint8_t)(value >> shift));
    }
    return hash;
}

static uint64_t gd_hash_i32(uint64_t hash, int32_t value)
{
    return gd_hash_u32(hash, (uint32_t)value);
}

static uint64_t gd_hash_u64(uint64_t hash, uint64_t value)
{
    uint32_t shift;
    for (shift = 0u; shift < 64u; shift += 8u) {
        hash = gd_hash_byte(hash, (uint8_t)(value >> shift));
    }
    return hash;
}

static uint64_t gd_hash_i32s(uint64_t hash, const int32_t *values, size_t count)
{
    size_t index;
    if (values == NULL && count != 0u) {
        return 0u;
    }
    for (index = 0u; index < count; index++) {
        hash = gd_hash_i32(hash, values[index]);
    }
    return hash;
}

static int32_t gd_q16_mul(int32_t lhs, int32_t rhs)
{
    int64_t value = (int64_t)lhs * (int64_t)rhs;
    value >>= 16;
    if (value > INT32_MAX) {
        return INT32_MAX;
    }
    if (value < INT32_MIN) {
        return INT32_MIN;
    }
    return (int32_t)value;
}

static int32_t gd_q16_mid(int32_t lhs, int32_t rhs)
{
    int64_t value = (int64_t)lhs + (int64_t)rhs;
    if (value >= 0) {
        value = (value + 1) / 2;
    } else {
        value = (value - 1) / 2;
    }
    if (value > INT32_MAX) {
        return INT32_MAX;
    }
    if (value < INT32_MIN) {
        return INT32_MIN;
    }
    return (int32_t)value;
}

static int gd_route(uint32_t demo_id, uint32_t stage_id)
{
    static const uint32_t stages[14] = {
        33u, 33u, 34u, 34u, 34u, 35u, 35u,
        9u, 9u, 20u, 20u, 26u, 26u, 25u,
    };
    return demo_id >= 1u && demo_id <= 14u && stages[demo_id - 1u] == stage_id;
}

static GEStatusV1 gd_validate_common(const GEAbiHeaderV1 *header,
                                     uint32_t expected_size,
                                     uint32_t record_version)
{
    if (header == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (header->abi_version != GE_NATIVE_ABI_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    if (header->struct_size != expected_size) {
        return GE_STATUS_INVALID_SIZE;
    }
    if (record_version != GE_GUARD_DOOR_OWNER_V6_RECORD_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    return GE_STATUS_OK;
}

static void gd_set_header(GEAbiHeaderV1 *header, uint32_t size)
{
    header->abi_version = GE_NATIVE_ABI_VERSION;
    header->struct_size = size;
}

static int gd_has_nonzero_i32(const int32_t *values, size_t count)
{
    size_t index;
    for (index = 0u; index < count; index++) {
        if (values[index] != 0) {
            return 1;
        }
    }
    return 0;
}

GEStatusV1 ge_guard_door_owner_v6_validate_setup(const GEGuardDoorOwnerSetupV6 *value)
{
    GEStatusV1 status;
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = gd_validate_common(&value->header, (uint32_t)sizeof(*value), value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (!gd_route(value->demo_id, value->stage_id) ||
        (value->flags & ~GE_GUARD_DOOR_OWNER_V6_SETUP_FLAG_MASK) != 0u ||
        value->source_bytes == 0u || value->guard_count > GE_GUARD_DOOR_OWNER_V6_MAX_GUARDS ||
        value->door_count > GE_GUARD_DOOR_OWNER_V6_MAX_DOORS || value->source_hash == 0u ||
        value->packet_hash == 0u || value->model_dependency_hash == 0u ||
        value->animation_source_hash == 0u || value->reserved0 != 0u || value->reserved1 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

static GEStatusV1 gd_validate_choice(const GEGuardDoorOwnerChoiceV6 *choice)
{
    if (choice == NULL || choice->source_id == GE_GUARD_DOOR_OWNER_V6_UNKNOWN_U32 ||
        choice->model_handle == 0u || choice->source_handle == 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

static int gd_choice_index(uint64_t *rng, const GEGuardDoorOwnerChoiceV6 *choices,
                           uint32_t count, GEGuardDoorOwnerChoiceV6 *out)
{
    uint32_t random_value;
    uint32_t index;
    if (rng == NULL || choices == NULL || out == NULL || count == 0u ||
        count > GE_GUARD_DOOR_OWNER_V6_MAX_CHOICES) {
        return 0;
    }
    random_value = ge_ramrom_gameplay_v6_source_random_next(rng);
    index = random_value % count;
    *out = choices[index];
    return 1;
}

static GEStatusV1 gd_validate_pose(const GESourceAnimationPoseV6 *value,
                                   uint32_t skeleton_handle,
                                   uint32_t frame_count)
{
    GEStatusV1 status = ge_source_scene_v6_validate_animation_pose(value);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->skeleton_handle != skeleton_handle || value->node_handle == 0u ||
        value->pose_hash == 0u || value->animation_tick >= frame_count ||
        (value->flags & ~GE_SOURCE_POSE_V6_FLAG_MASK) != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_guard_door_owner_v6_validate_pose(const GESourceAnimationPoseV6 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    return ge_source_scene_v6_validate_animation_pose(value);
}

GEStatusV1 ge_guard_door_owner_v6_validate_guard(
    const GEGuardDoorOwnerGuardSourceV6 *value)
{
    GEStatusV1 status;
    uint32_t index;
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = gd_validate_common(&value->header, (uint32_t)sizeof(*value), value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->source_record_offset == 0u || value->animation_id == 0u ||
        value->animation_frame_count == 0u || value->animation_frame_count > 4096u ||
        value->animation_frame_q16 < 0 ||
        value->animation_frame_q16 >= (int32_t)(value->animation_frame_count << 16) ||
        value->animation_next_frame_q16 < 0 ||
        value->animation_next_frame_q16 >= (int32_t)(value->animation_frame_count << 16) ||
        value->animation_speed_q16 <= 0 || value->animation_merge_q16 < 0 ||
        value->animation_merge_q16 > 65536 || value->skeleton_handle == 0u ||
        value->body_model_handle == 0u || value->health_current > value->health ||
        value->pose_count == 0u || value->pose_count > GE_GUARD_DOOR_OWNER_V6_MAX_POSES_PER_GUARD ||
        value->pose_next_count != value->pose_count ||
        value->attachment_count > GE_GUARD_DOOR_OWNER_V6_MAX_ATTACHMENTS_PER_GUARD ||
        value->body_choice_count > GE_GUARD_DOOR_OWNER_V6_MAX_CHOICES ||
        value->head_choice_count > GE_GUARD_DOOR_OWNER_V6_MAX_CHOICES ||
        value->weapon_choice_count > GE_GUARD_DOOR_OWNER_V6_MAX_CHOICES ||
        (value->flags & ~GE_GUARD_DOOR_OWNER_V6_GUARD_FLAG_MASK) != 0u ||
        value->source_hash == 0u || value->animation_hash == 0u || value->pose_hash == 0u ||
        value->source_event_hash == 0u || value->reserved0 != 0u || value->reserved1 != 0u ||
        !gd_has_nonzero_i32(value->world_transform_q16, 16u)) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    if (value->head_id == GE_GUARD_DOOR_OWNER_V6_UNKNOWN_U32 && value->head_choice_count == 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    if (value->body_id == GE_GUARD_DOOR_OWNER_V6_UNKNOWN_U32 && value->body_choice_count == 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    if (value->weapon_id == GE_GUARD_DOOR_OWNER_V6_UNKNOWN_U32 && value->weapon_choice_count == 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    for (index = 0u; index < value->body_choice_count; index++) {
        status = gd_validate_choice(&value->body_choices[index]);
        if (status != GE_STATUS_OK) return status;
    }
    for (index = 0u; index < value->head_choice_count; index++) {
        status = gd_validate_choice(&value->head_choices[index]);
        if (status != GE_STATUS_OK) return status;
    }
    for (index = 0u; index < value->weapon_choice_count; index++) {
        status = gd_validate_choice(&value->weapon_choices[index]);
        if (status != GE_STATUS_OK) return status;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_guard_door_owner_v6_validate_door(
    const GEGuardDoorOwnerDoorSourceV6 *value)
{
    GEStatusV1 status;
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = gd_validate_common(&value->header, (uint32_t)sizeof(*value), value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->source_record_offset == 0u || value->door_id == 0u || value->model_handle == 0u ||
        value->max_frac_q16 <= 0 || value->perim_frac_q16 < 0 ||
        value->accel_q16 <= 0 ||
        value->decel_q16 <= 0 || value->max_speed_q16 <= 0 ||
        value->open_state > GE_GUARD_DOOR_OWNER_V6_DOOR_STATE_WAITING ||
        value->door_flags & ~GE_GUARD_DOOR_OWNER_V6_DOOR_FLAG_MASK ||
        value->door_type > GE_GUARD_DOOR_OWNER_V6_DOOR_TYPE_MAX ||
        value->open_position_q16 < 0 || value->open_position_q16 > value->max_frac_q16 ||
        value->speed_q16 < 0 || value->source_hash64 == 0u || value->source_event_hash == 0u ||
        value->reserved0 != 0u || value->reserved1 != 0u ||
        !gd_has_nonzero_i32(value->base_transform_q16, 16u)) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

static int gd_update_speed(int32_t *position, int32_t target, int32_t *speed,
                           int32_t accel, int32_t decel, int32_t max_speed)
{
    int32_t speed_value;
    int32_t distance;
    int64_t speed_squared;
    int64_t limit;
    if (position == NULL || speed == NULL) return 0;
    speed_value = *speed;
    distance = target - *position;
    speed_squared = (int64_t)speed_value * (int64_t)speed_value;
    limit = (speed_squared >> 16) / (2 * (int64_t)decel);

    if (distance > 0) {
        if (speed_value > 0 && (int64_t)distance <= limit) {
            speed_value -= decel;
            if (speed_value < decel) speed_value = decel;
        } else if (speed_value < max_speed) {
            if (speed_value < 0) speed_value += decel;
            else speed_value += accel;
            if (speed_value > max_speed) speed_value = max_speed;
        }
        if (speed_value >= distance) {
            *position = target;
        } else {
            *position += speed_value;
        }
    } else {
        int32_t remaining = -distance;
        if (speed_value < 0 && (int64_t)remaining <= limit) {
            speed_value += decel;
            if (speed_value > -decel) speed_value = -decel;
        } else if (speed_value > -max_speed) {
            if (speed_value > 0) speed_value -= decel;
            else speed_value -= accel;
            if (speed_value < -max_speed) speed_value = -max_speed;
        }
        if (speed_value <= distance) {
            *position = target;
        } else {
            *position += speed_value;
        }
    }
    *speed = speed_value;
    return 1;
}

static void gd_door_transform(const GEGuardDoorOwnerDoorSourceV6 *source,
                              int32_t open_position, int32_t *out_matrix)
{
    uint32_t index;
    int32_t displacement[3];
    if (source == NULL || out_matrix == NULL) return;
    memcpy(out_matrix, source->base_transform_q16, sizeof(source->base_transform_q16));
    /* Sliding, flexi, vertical, and fallaway doors use the serialized source
       displacement vector exactly as door7F0526EC does.  Eye/iris/swinging
       doors receive their already lowered source matrix unchanged; the
       source page carries those matrices because their bound-pad basis and
       joint rotation are not inferable from an ObjectRecord alone. */
    if (source->door_type <= GE_GUARD_DOOR_OWNER_V6_DOOR_TYPE_FALLAWAY) {
        for (index = 0u; index < 3u; index++) {
            displacement[index] = gd_q16_mul(source->frac_q16[index], open_position);
            out_matrix[12u + index] = source->runtime_position_q16[index] + displacement[index];
        }
    } else if (source->door_type == GE_GUARD_DOOR_OWNER_V6_DOOR_TYPE_EYE ||
               source->door_type == GE_GUARD_DOOR_OWNER_V6_DOOR_TYPE_IRIS) {
        out_matrix[12] = source->runtime_position_q16[0];
        out_matrix[13] = source->runtime_position_q16[1];
        out_matrix[14] = source->runtime_position_q16[2];
    }
}

static GEStatusV1 gd_copy_poses(const GEGuardDoorOwnerGuardSourceV6 *source,
                                const GESourceAnimationPoseV6 *poses, uint32_t pose_count,
                                GEGuardDoorOwnerGuardStateV6 *state)
{
    uint32_t index;
    if (source == NULL || state == NULL || poses == NULL ||
        source->pose_first > pose_count || source->pose_count > pose_count - source->pose_first ||
        source->pose_next_first > pose_count || source->pose_next_count > pose_count - source->pose_next_first) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    state->pose_count = source->pose_count;
    state->pose_next_count = source->pose_next_count;
    for (index = 0u; index < source->pose_count; index++) {
        GEStatusV1 status = gd_validate_pose(
            &poses[source->pose_first + index], source->skeleton_handle,
            source->animation_frame_count
        );
        if (status != GE_STATUS_OK) return status;
        status = gd_validate_pose(
            &poses[source->pose_next_first + index], source->skeleton_handle,
            source->animation_frame_count
        );
        if (status != GE_STATUS_OK) return status;
        state->poses[index] = poses[source->pose_first + index];
        state->next_poses[index] = poses[source->pose_next_first + index];
    }
    return GE_STATUS_OK;
}

static GEStatusV1 gd_copy_attachments(const GEGuardDoorOwnerGuardSourceV6 *source,
                                      const GEGuardDoorOwnerAttachmentV6 *attachments,
                                      uint32_t attachment_count,
                                      GEGuardDoorOwnerGuardStateV6 *state)
{
    if (source == NULL || state == NULL ||
        source->attachment_first > attachment_count ||
        source->attachment_count > attachment_count - source->attachment_first ||
        (source->attachment_count != 0u && attachments == NULL)) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    if (source->attachment_count != 0u) {
        memcpy(state->attachments, &attachments[source->attachment_first],
               source->attachment_count * sizeof(state->attachments[0]));
    }
    return GE_STATUS_OK;
}

static GEStatusV1 gd_fill_guard(const GEGuardDoorOwnerGuardSourceV6 *source,
                                const GESourceAnimationPoseV6 *poses, uint32_t pose_count,
                                const GEGuardDoorOwnerAttachmentV6 *attachments,
                                uint32_t attachment_count, uint64_t *rng,
                                GEGuardDoorOwnerGuardStateV6 *out)
{
    GEStatusV1 status;
    GEGuardDoorOwnerChoiceV6 choice;
    memset(out, 0, sizeof(*out));
    status = ge_guard_door_owner_v6_validate_guard(source);
    if (status != GE_STATUS_OK) return status;
    out->source = *source;

    if (source->body_id == GE_GUARD_DOOR_OWNER_V6_UNKNOWN_U32) {
        if (!gd_choice_index(rng, source->body_choices, source->body_choice_count, &choice)) {
            return GE_STATUS_MALFORMED_STREAM;
        }
        out->selected_body_id = choice.source_id;
        out->selected_body_model_handle = choice.model_handle;
    } else {
        out->selected_body_id = source->body_id;
        out->selected_body_model_handle = source->body_model_handle;
    }
    if (source->head_id == GE_GUARD_DOOR_OWNER_V6_UNKNOWN_U32) {
        if (!gd_choice_index(rng, source->head_choices, source->head_choice_count, &choice)) {
            return GE_STATUS_MALFORMED_STREAM;
        }
        out->selected_head_id = choice.source_id;
        out->selected_head_model_handle = choice.model_handle;
    } else {
        out->selected_head_id = source->head_id;
        out->selected_head_model_handle = source->head_model_handle;
    }
    if (source->weapon_id == GE_GUARD_DOOR_OWNER_V6_UNKNOWN_U32) {
        if (!gd_choice_index(rng, source->weapon_choices, source->weapon_choice_count, &choice)) {
            return GE_STATUS_MALFORMED_STREAM;
        }
        out->selected_weapon_id = choice.source_id;
        out->selected_weapon_model_handle = choice.model_handle;
    } else {
        out->selected_weapon_id = source->weapon_id;
        out->selected_weapon_model_handle = source->weapon_model_handle;
    }
    if (out->selected_body_model_handle == 0u || out->selected_head_model_handle == 0u ||
        out->selected_weapon_model_handle == 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    status = gd_copy_poses(source, poses, pose_count, out);
    if (status != GE_STATUS_OK) return status;
    status = gd_copy_attachments(source, attachments, attachment_count, out);
    if (status != GE_STATUS_OK) return status;
    out->entity_flags = GE_GUARD_DOOR_OWNER_V6_ENTITY_FLAG_ACTIVE |
        GE_GUARD_DOOR_OWNER_V6_ENTITY_FLAG_VISIBLE |
        GE_GUARD_DOOR_OWNER_V6_ENTITY_FLAG_SOURCE_ANCHOR;
    if (source->death_state != 0u) out->entity_flags |= GE_GUARD_DOOR_OWNER_V6_ENTITY_FLAG_DEAD;
    if (source->action_state != 0u) out->entity_flags |= GE_GUARD_DOOR_OWNER_V6_ENTITY_FLAG_ACTION;
    out->source_anchor = 1u;
    return GE_STATUS_OK;
}

static GEStatusV1 gd_fill_door(const GEGuardDoorOwnerDoorSourceV6 *source,
                               GEGuardDoorOwnerDoorStateV6 *out)
{
    GEStatusV1 status;
    memset(out, 0, sizeof(*out));
    status = ge_guard_door_owner_v6_validate_door(source);
    if (status != GE_STATUS_OK) return status;
    out->source = *source;
    out->entity_flags = GE_GUARD_DOOR_OWNER_V6_ENTITY_FLAG_ACTIVE |
        GE_GUARD_DOOR_OWNER_V6_ENTITY_FLAG_VISIBLE |
        GE_GUARD_DOOR_OWNER_V6_ENTITY_FLAG_SOURCE_ANCHOR;
    out->source_anchor = 1u;
    gd_door_transform(source, source->open_position_q16, out->transform_q16);
    memcpy(out->next_transform_q16, out->transform_q16, sizeof(out->transform_q16));
    return GE_STATUS_OK;
}

static void gd_interpolate_pose(GESourceAnimationPoseV6 *out,
                                const GESourceAnimationPoseV6 *next)
{
    uint32_t index;
    if (out == NULL || next == NULL) return;
    out->animation_tick = next->animation_tick;
    for (index = 0u; index < 3u; index++) {
        out->translation_q16[index] = gd_q16_mid(out->translation_q16[index], next->translation_q16[index]);
        out->scale_q16[index] = gd_q16_mid(out->scale_q16[index], next->scale_q16[index]);
    }
    for (index = 0u; index < 4u; index++) {
        out->rotation_q16[index] = gd_q16_mid(out->rotation_q16[index], next->rotation_q16[index]);
    }
    out->flags |= GE_SOURCE_POSE_V6_FLAG_INTERPOLATABLE;
    out->pose_hash = gd_hash_u64(out->pose_hash, next->pose_hash);
}

static void gd_interpolate_guard(GEGuardDoorOwnerGuardStateV6 *guard)
{
    uint32_t index;
    if (guard == NULL) return;
    for (index = 0u; index < guard->pose_count; index++) {
        gd_interpolate_pose(&guard->poses[index], &guard->next_poses[index]);
    }
    for (index = 0u; index < 3u; index++) {
        guard->source.position_q16[index] = gd_q16_mid(
            guard->source.position_q16[index], guard->source.next_position_q16[index]
        );
        guard->source.root_motion_q16[index] = gd_q16_mid(
            guard->source.root_motion_q16[index], guard->source.root_motion_next_q16[index]
        );
    }
    guard->source.animation_frame_q16 = gd_q16_mid(
        guard->source.animation_frame_q16, guard->source.animation_next_frame_q16
    );
    guard->source.animation_merge_q16 = gd_q16_mid(guard->source.animation_merge_q16, 65536);
    guard->entity_flags &= ~GE_GUARD_DOOR_OWNER_V6_ENTITY_FLAG_SOURCE_ANCHOR;
    guard->entity_flags |= GE_GUARD_DOOR_OWNER_V6_ENTITY_FLAG_INTERPOLATED;
    guard->interpolated = 1u;
    guard->source_anchor = 0u;
}

static void gd_interpolate_door(GEGuardDoorOwnerDoorStateV6 *door)
{
    uint32_t index;
    if (door == NULL) return;
    door->source.open_position_q16 = gd_q16_mid(
        door->source.open_position_q16, door->source.next_open_position_q16
    );
    door->source.speed_q16 = gd_q16_mid(door->source.speed_q16, door->source.next_speed_q16);
    for (index = 0u; index < 16u; index++) {
        door->transform_q16[index] = gd_q16_mid(door->transform_q16[index], door->next_transform_q16[index]);
    }
    door->entity_flags &= ~GE_GUARD_DOOR_OWNER_V6_ENTITY_FLAG_SOURCE_ANCHOR;
    door->entity_flags |= GE_GUARD_DOOR_OWNER_V6_ENTITY_FLAG_INTERPOLATED;
    door->interpolated = 1u;
    door->source_anchor = 0u;
}

static void gd_hash_guard(uint64_t *hash, const GEGuardDoorOwnerGuardStateV6 *guard)
{
    uint32_t index;
    if (hash == NULL || guard == NULL) return;
    *hash = gd_hash_u32(*hash, guard->source.guard_id);
    *hash = gd_hash_u32(*hash, guard->selected_body_id);
    *hash = gd_hash_u32(*hash, guard->selected_head_id);
    *hash = gd_hash_u32(*hash, guard->selected_weapon_id);
    *hash = gd_hash_u32(*hash, guard->source.animation_id);
    *hash = gd_hash_i32(*hash, guard->source.animation_frame_q16);
    *hash = gd_hash_i32s(*hash, guard->source.position_q16, 3u);
    *hash = gd_hash_u64(*hash, guard->source.source_hash);
    *hash = gd_hash_u64(*hash, guard->source.pose_hash);
    for (index = 0u; index < guard->pose_count; index++) {
        *hash = gd_hash_u32(*hash, guard->poses[index].node_handle);
        *hash = gd_hash_u64(*hash, guard->poses[index].pose_hash);
    }
    for (index = 0u; index < guard->source.attachment_count; index++) {
        *hash = gd_hash_u32(*hash, guard->attachments[index].model_handle);
        *hash = gd_hash_u64(*hash, guard->attachments[index].source_hash);
    }
}

static void gd_hash_door(uint64_t *hash, const GEGuardDoorOwnerDoorStateV6 *door)
{
    if (hash == NULL || door == NULL) return;
    *hash = gd_hash_u32(*hash, door->source.door_id);
    *hash = gd_hash_u32(*hash, door->source.open_state);
    *hash = gd_hash_i32(*hash, door->source.open_position_q16);
    *hash = gd_hash_i32s(*hash, door->transform_q16, 16u);
    *hash = gd_hash_u64(*hash, door->source.source_hash64);
}

uint64_t ge_guard_door_owner_v6_hash_state(const GEGuardDoorOwnerStateV6 *state)
{
    uint64_t hash = GE_GD_FNV_OFFSET;
    uint32_t index;
    if (state == NULL) return 0u;
    hash = gd_hash_u32(hash, state->demo_id);
    hash = gd_hash_u32(hash, state->stage_id);
    hash = gd_hash_u64(hash, state->native_tick);
    hash = gd_hash_u32(hash, state->pair_phase);
    hash = gd_hash_u32(hash, state->guard_count);
    hash = gd_hash_u32(hash, state->door_count);
    for (index = 0u; index < state->guard_count; index++) gd_hash_guard(&hash, &state->guards[index]);
    for (index = 0u; index < state->door_count; index++) gd_hash_door(&hash, &state->doors[index]);
    return hash;
}

uint64_t ge_guard_door_owner_v6_hash_event(const GEGuardDoorOwnerEventV6 *event)
{
    uint64_t hash = GE_GD_FNV_OFFSET;
    if (event == NULL) return 0u;
    hash = gd_hash_u32(hash, event->event_type);
    hash = gd_hash_u32(hash, event->flags);
    hash = gd_hash_u64(hash, event->native_tick);
    hash = gd_hash_u64(hash, event->source_hash);
    hash = gd_hash_u64(hash, event->state_hash);
    return hash;
}

static void gd_fill_event(const GEGuardDoorOwnerStateV6 *state, uint32_t event_type,
                          uint32_t diagnostic, GEGuardDoorOwnerEventV6 *event)
{
    memset(event, 0, sizeof(*event));
    gd_set_header(&event->header, (uint32_t)sizeof(*event));
    event->record_version = GE_GUARD_DOOR_OWNER_V6_RECORD_VERSION;
    event->event_type = event_type;
    event->diagnostic_code = diagnostic;
    event->native_tick = state->native_tick;
    event->reference_tick = state->reference_tick;
    event->pair_phase = state->pair_phase;
    event->demo_id = state->demo_id;
    event->stage_id = state->stage_id;
    event->guard_count = state->guard_count;
    event->door_count = state->door_count;
    event->attachment_count = state->attachment_count;
    event->rng_seed = state->rng_seed;
    event->rng_checkpoint_hash = state->rng_checkpoint_hash;
    event->source_hash = state->source_hash;
    event->state_hash = state->state_hash;
    event->render_hash = state->render_hash;
    event->event_hash = ge_guard_door_owner_v6_hash_event(event);
}

GEStatusV1 ge_guard_door_owner_v6_begin(
    const GEGuardDoorOwnerSetupV6 *setup,
    const GEGuardDoorOwnerGuardSourceV6 *guards,
    uint32_t guard_count,
    const GEGuardDoorOwnerDoorSourceV6 *doors,
    uint32_t door_count,
    const GESourceAnimationPoseV6 *poses,
    uint32_t pose_count,
    const GEGuardDoorOwnerAttachmentV6 *attachments,
    uint32_t attachment_count,
    uint64_t rng_seed,
    GEGuardDoorOwnerStateV6 *out_state,
    GEGuardDoorOwnerEventV6 *out_event)
{
    GEStatusV1 status;
    uint32_t index;
    uint64_t rng = rng_seed;
    if (out_state == NULL || out_event == NULL || setup == NULL ||
        (guard_count != 0u && guards == NULL) || (door_count != 0u && doors == NULL) ||
        (pose_count != 0u && poses == NULL) || (attachment_count != 0u && attachments == NULL) ||
        guard_count > GE_GUARD_DOOR_OWNER_V6_MAX_GUARDS || door_count > GE_GUARD_DOOR_OWNER_V6_MAX_DOORS ||
        rng_seed == 0u) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_guard_door_owner_v6_validate_setup(setup);
    if (status != GE_STATUS_OK || setup->guard_count != guard_count || setup->door_count != door_count) {
        return status == GE_STATUS_OK ? GE_STATUS_MALFORMED_STREAM : status;
    }
    memset(out_state, 0, sizeof(*out_state));
    gd_set_header(&out_state->header, (uint32_t)sizeof(*out_state));
    out_state->record_version = GE_GUARD_DOOR_OWNER_V6_RECORD_VERSION;
    out_state->demo_id = setup->demo_id;
    out_state->stage_id = setup->stage_id;
    out_state->native_tick = 0u;
    out_state->reference_tick = 0u;
    out_state->pair_phase = 0u;
    out_state->source_anchor = 1u;
    out_state->guard_count = guard_count;
    out_state->door_count = door_count;
    out_state->setup = *setup;
    out_state->rng_seed = (uint32_t)rng;
    out_state->source_hash = setup->source_hash;
    for (index = 0u; index < guard_count; index++) {
        status = gd_fill_guard(&guards[index], poses, pose_count, attachments, attachment_count,
                               &rng, &out_state->guards[index]);
        if (status != GE_STATUS_OK) return status;
        out_state->attachment_count += out_state->guards[index].source.attachment_count;
    }
    for (index = 0u; index < door_count; index++) {
        status = gd_fill_door(&doors[index], &out_state->doors[index]);
        if (status != GE_STATUS_OK) return status;
    }
    if (out_state->attachment_count > GE_GUARD_DOOR_OWNER_V6_MAX_GUARDS *
        GE_GUARD_DOOR_OWNER_V6_MAX_ATTACHMENTS_PER_GUARD) {
        return GE_STATUS_REPLAY_BUDGET;
    }
    out_state->rng_seed = (uint32_t)rng;
    out_state->rng_checkpoint_hash = gd_hash_u64(GE_GD_FNV_OFFSET, rng);
    out_state->state_hash = ge_guard_door_owner_v6_hash_state(out_state);
    out_state->render_hash = gd_hash_u64(out_state->state_hash, out_state->source_hash);
    gd_fill_event(out_state, GE_GUARD_DOOR_OWNER_V6_EVENT_INSTALL, 0u, out_event);
    return GE_STATUS_OK;
}

GEStatusV1 ge_guard_door_owner_v6_step(
    uint64_t native_tick,
    const GEGuardDoorOwnerGuardSourceV6 *guards,
    uint32_t guard_count,
    const GEGuardDoorOwnerDoorSourceV6 *doors,
    uint32_t door_count,
    const GESourceAnimationPoseV6 *poses,
    uint32_t pose_count,
    const GEGuardDoorOwnerAttachmentV6 *attachments,
    uint32_t attachment_count,
    GEGuardDoorOwnerStateV6 *inout_state,
    GEGuardDoorOwnerEventV6 *out_event)
{
    GEStatusV1 status;
    uint32_t index;
    if (inout_state == NULL || out_event == NULL || native_tick == 0u ||
        native_tick != inout_state->native_tick + 1u || guard_count != inout_state->guard_count ||
        door_count != inout_state->door_count) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    inout_state->native_tick = native_tick;
    inout_state->reference_tick = native_tick >> 1;
    inout_state->pair_phase = (uint32_t)(native_tick & 1u);
    inout_state->source_anchor = inout_state->pair_phase == 0u ? 1u : 0u;

    if (inout_state->pair_phase == 0u) {
        if ((guard_count != 0u && guards == NULL) || (door_count != 0u && doors == NULL) ||
            (pose_count != 0u && poses == NULL) || (attachment_count != 0u && attachments == NULL)) {
            return GE_STATUS_INVALID_ARGUMENT;
        }
        {
            uint64_t rng = (uint64_t)inout_state->rng_seed;
            for (index = 0u; index < guard_count; index++) {
            GEGuardDoorOwnerGuardStateV6 next_guard;
            GEGuardDoorOwnerGuardSourceV6 resolved = guards[index];
            if (resolved.body_id == GE_GUARD_DOOR_OWNER_V6_UNKNOWN_U32) {
                resolved.body_id = inout_state->guards[index].selected_body_id;
                resolved.body_model_handle = inout_state->guards[index].selected_body_model_handle;
            }
            if (resolved.head_id == GE_GUARD_DOOR_OWNER_V6_UNKNOWN_U32) {
                resolved.head_id = inout_state->guards[index].selected_head_id;
                resolved.head_model_handle = inout_state->guards[index].selected_head_model_handle;
            }
            if (resolved.weapon_id == GE_GUARD_DOOR_OWNER_V6_UNKNOWN_U32) {
                resolved.weapon_id = inout_state->guards[index].selected_weapon_id;
                resolved.weapon_model_handle = inout_state->guards[index].selected_weapon_model_handle;
            }
            status = gd_fill_guard(&resolved, poses, pose_count, attachments, attachment_count,
                                   &rng, &next_guard);
            if (status != GE_STATUS_OK) return status;
            inout_state->guards[index] = next_guard;
            inout_state->guards[index].source_anchor = 1u;
            }
            inout_state->rng_seed = (uint32_t)rng;
        }
        for (index = 0u; index < door_count; index++) {
            GEGuardDoorOwnerDoorStateV6 next_door;
            status = gd_fill_door(&doors[index], &next_door);
            if (status != GE_STATUS_OK) return status;
            if (doors[index].open_position_q16 != doors[index].next_open_position_q16) {
                int32_t expected_position = doors[index].open_position_q16;
                int32_t expected_speed = doors[index].speed_q16;
                if (doors[index].open_state == GE_GUARD_DOOR_OWNER_V6_DOOR_STATE_OPENING) {
                    (void)gd_update_speed(&expected_position, doors[index].max_frac_q16,
                                          &expected_speed, doors[index].accel_q16,
                                          doors[index].decel_q16, doors[index].max_speed_q16);
                } else if (doors[index].open_state == GE_GUARD_DOOR_OWNER_V6_DOOR_STATE_CLOSING) {
                    (void)gd_update_speed(&expected_position, 0, &expected_speed,
                                          doors[index].accel_q16, doors[index].decel_q16,
                                          doors[index].max_speed_q16);
                }
                if (expected_position != doors[index].next_open_position_q16 ||
                    expected_speed != doors[index].next_speed_q16) {
                    return GE_STATUS_MALFORMED_STREAM;
                }
            }
            inout_state->doors[index] = next_door;
            inout_state->doors[index].source.next_open_position_q16 = doors[index].next_open_position_q16;
            inout_state->doors[index].source.next_speed_q16 = doors[index].next_speed_q16;
            gd_door_transform(doors + index, doors[index].next_open_position_q16,
                              inout_state->doors[index].next_transform_q16);
            inout_state->doors[index].source_anchor = 1u;
        }
        inout_state->rng_checkpoint_hash = gd_hash_u64(GE_GD_FNV_OFFSET, inout_state->rng_seed);
        inout_state->state_hash = ge_guard_door_owner_v6_hash_state(inout_state);
        inout_state->render_hash = gd_hash_u64(inout_state->state_hash, inout_state->source_hash);
        gd_fill_event(inout_state, GE_GUARD_DOOR_OWNER_V6_EVENT_SOURCE_ANCHOR, 0u, out_event);
    } else {
        if (guards != NULL || doors != NULL || poses != NULL || attachments != NULL ||
            pose_count != 0u || attachment_count != 0u) {
            return GE_STATUS_MALFORMED_STREAM;
        }
        for (index = 0u; index < guard_count; index++) gd_interpolate_guard(&inout_state->guards[index]);
        for (index = 0u; index < door_count; index++) gd_interpolate_door(&inout_state->doors[index]);
        inout_state->state_hash = ge_guard_door_owner_v6_hash_state(inout_state);
        inout_state->render_hash = gd_hash_u64(inout_state->state_hash, inout_state->source_hash);
        gd_fill_event(inout_state, GE_GUARD_DOOR_OWNER_V6_EVENT_INTERPOLATED, 0u, out_event);
    }
    return GE_STATUS_OK;
}

static int32_t gd_source_frame_next(const GEGuardDoorOwnerGuardSourceV6 *source)
{
    int64_t next;
    int64_t limit;
    if (source == NULL || source->animation_frame_count == 0u) return 0;
    next = (int64_t)source->animation_frame_q16 + (int64_t)source->animation_speed_q16;
    limit = (int64_t)source->animation_frame_count << 16;
    if (next >= limit) {
        if ((source->flags & GE_GUARD_DOOR_OWNER_V6_GUARD_FLAG_LOOP_ANIMATION) != 0u) {
            next %= limit;
        } else {
            next = limit - 1;
        }
    }
    if (next < 0) next = 0;
    return (int32_t)next;
}

GEStatusV1 ge_guard_door_owner_v6_step_source_authority(
    uint64_t native_tick,
    GEGuardDoorOwnerStateV6 *inout_state,
    GEGuardDoorOwnerEventV6 *out_event)
{
    uint32_t index;
    uint32_t required = GE_GUARD_DOOR_OWNER_V6_SETUP_FLAG_POSES |
                        GE_GUARD_DOOR_OWNER_V6_SETUP_FLAG_AI |
                        GE_GUARD_DOOR_OWNER_V6_SETUP_FLAG_BOUND_PAD_TRANSFORMS |
                        GE_GUARD_DOOR_OWNER_V6_SETUP_FLAG_MODEL_DEPENDENCIES |
                        GE_GUARD_DOOR_OWNER_V6_SETUP_FLAG_SOURCE_READY;
    uint64_t hash;
    if (inout_state == NULL || out_event == NULL || native_tick == 0u ||
        native_tick != inout_state->native_tick + 1u) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if ((inout_state->setup.flags & required) != required) {
        return GE_STATUS_UNSUPPORTED_COMMAND;
    }
    if ((native_tick & 1u) != 0u) {
        return ge_guard_door_owner_v6_step(
            native_tick, NULL, inout_state->guard_count,
            NULL, inout_state->door_count, NULL, 0u,
            NULL, 0u, inout_state, out_event
        );
    }
    inout_state->native_tick = native_tick;
    inout_state->reference_tick = native_tick >> 1;
    inout_state->pair_phase = 0u;
    inout_state->source_anchor = 1u;
    for (index = 0u; index < inout_state->guard_count; index++) {
        GEGuardDoorOwnerGuardStateV6 *guard = &inout_state->guards[index];
        if (ge_guard_door_owner_v6_validate_guard(&guard->source) != GE_STATUS_OK ||
            guard->source.ai_state == GE_GUARD_DOOR_OWNER_V6_UNKNOWN_U32 ||
            guard->pose_count == 0u || guard->pose_next_count != guard->pose_count) {
            return GE_STATUS_UNSUPPORTED_COMMAND;
        }
        guard->source.animation_frame_q16 = gd_source_frame_next(&guard->source);
        guard->source.animation_next_frame_q16 = gd_source_frame_next(&guard->source);
        for (uint32_t axis = 0u; axis < 3u; axis++) {
            guard->source.position_q16[axis] += guard->source.root_motion_q16[axis];
            guard->source.next_position_q16[axis] = guard->source.position_q16[axis];
        }
        guard->source.root_motion_q16[0] = guard->source.root_motion_next_q16[0];
        guard->source.root_motion_q16[1] = guard->source.root_motion_next_q16[1];
        guard->source.root_motion_q16[2] = guard->source.root_motion_next_q16[2];
        guard->source_anchor = 1u;
        guard->interpolated = 0u;
        guard->entity_flags &= ~GE_GUARD_DOOR_OWNER_V6_ENTITY_FLAG_INTERPOLATED;
        guard->entity_flags |= GE_GUARD_DOOR_OWNER_V6_ENTITY_FLAG_SOURCE_ANCHOR;
    }
    for (index = 0u; index < inout_state->door_count; index++) {
        GEGuardDoorOwnerDoorStateV6 *door = &inout_state->doors[index];
        int32_t target = 0;
        if (door->source.open_state == GE_GUARD_DOOR_OWNER_V6_DOOR_STATE_OPENING) {
            target = door->source.max_frac_q16;
        }
        if (door->source.open_state == GE_GUARD_DOOR_OWNER_V6_DOOR_STATE_OPENING ||
            door->source.open_state == GE_GUARD_DOOR_OWNER_V6_DOOR_STATE_CLOSING) {
            (void)gd_update_speed(
                &door->source.open_position_q16, target, &door->source.speed_q16,
                door->source.accel_q16, door->source.decel_q16, door->source.max_speed_q16
            );
            if ((door->source.open_state == GE_GUARD_DOOR_OWNER_V6_DOOR_STATE_OPENING &&
                 door->source.open_position_q16 >= door->source.max_frac_q16) ||
                (door->source.open_state == GE_GUARD_DOOR_OWNER_V6_DOOR_STATE_CLOSING &&
                 door->source.open_position_q16 <= 0)) {
                door->source.open_position_q16 = target;
                door->source.open_state = GE_GUARD_DOOR_OWNER_V6_DOOR_STATE_STATIONARY;
                door->source.speed_q16 = 0;
            }
        }
        door->source.next_open_position_q16 = door->source.open_position_q16;
        door->source.next_speed_q16 = door->source.speed_q16;
        door->source.portal_active = door->source.open_position_q16 > 0 ? 1u : 0u;
        gd_door_transform(&door->source, door->source.open_position_q16, door->transform_q16);
        memcpy(door->next_transform_q16, door->transform_q16, sizeof(door->transform_q16));
        door->source_anchor = 1u;
        door->interpolated = 0u;
        door->entity_flags &= ~GE_GUARD_DOOR_OWNER_V6_ENTITY_FLAG_INTERPOLATED;
        door->entity_flags |= GE_GUARD_DOOR_OWNER_V6_ENTITY_FLAG_SOURCE_ANCHOR;
    }
    hash = ge_guard_door_owner_v6_hash_state(inout_state);
    inout_state->state_hash = hash;
    inout_state->render_hash = gd_hash_u64(hash, inout_state->source_hash);
    gd_fill_event(inout_state, GE_GUARD_DOOR_OWNER_V6_EVENT_SOURCE_ANCHOR, 0u, out_event);
    return GE_STATUS_OK;
}

GEStatusV1 ge_guard_door_owner_v6_copy_guard_page(
    const GEGuardDoorOwnerStateV6 *state, uint32_t first_item, uint32_t capacity,
    GEGuardDoorOwnerGuardStateV6 *out_items, uint32_t *out_copied)
{
    uint32_t copied;
    if (state == NULL || out_copied == NULL || (capacity != 0u && out_items == NULL) ||
        first_item > state->guard_count || capacity > GE_GUARD_DOOR_OWNER_V6_PAGE_ITEMS) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    copied = state->guard_count - first_item;
    if (copied > capacity) copied = capacity;
    if (copied != 0u) memcpy(out_items, &state->guards[first_item], copied * sizeof(out_items[0]));
    *out_copied = copied;
    return GE_STATUS_OK;
}

GEStatusV1 ge_guard_door_owner_v6_copy_door_page(
    const GEGuardDoorOwnerStateV6 *state, uint32_t first_item, uint32_t capacity,
    GEGuardDoorOwnerDoorStateV6 *out_items, uint32_t *out_copied)
{
    uint32_t copied;
    if (state == NULL || out_copied == NULL || (capacity != 0u && out_items == NULL) ||
        first_item > state->door_count || capacity > GE_GUARD_DOOR_OWNER_V6_PAGE_ITEMS) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    copied = state->door_count - first_item;
    if (copied > capacity) copied = capacity;
    if (copied != 0u) memcpy(out_items, &state->doors[first_item], copied * sizeof(out_items[0]));
    *out_copied = copied;
    return GE_STATUS_OK;
}

static void gd_fill_gameplay_entity(const GEGuardDoorOwnerStateV6 *state,
                                    const GEGuardDoorOwnerGuardStateV6 *guard,
                                    uint32_t attachment_first,
                                    GERamRomGameplayEntityV6 *entity)
{
    memset(entity, 0, sizeof(*entity));
    gd_set_header(&entity->header, (uint32_t)sizeof(*entity));
    entity->record_version = GE_RAMROM_GAMEPLAY_V6_RECORD_VERSION;
    entity->entity_id = guard->source.guard_id + 2u;
    entity->entity_kind = GE_RAMROM_GAMEPLAY_V6_ENTITY_GUARD;
    entity->flags = GE_RAMROM_GAMEPLAY_V6_ENTITY_ACTIVE | GE_RAMROM_GAMEPLAY_V6_ENTITY_VISIBLE;
    if (guard->interpolated) entity->flags |= GE_RAMROM_GAMEPLAY_V6_ENTITY_INTERPOLATED;
    else entity->flags |= GE_RAMROM_GAMEPLAY_V6_ENTITY_SOURCE_ANCHOR;
    if (guard->source.death_state != 0u) entity->flags |= GE_RAMROM_GAMEPLAY_V6_ENTITY_DEAD;
    if (guard->source.action_state != 0u) entity->flags |= GE_RAMROM_GAMEPLAY_V6_ENTITY_ACTION;
    entity->body_model_handle = guard->selected_body_model_handle;
    entity->head_model_handle = guard->selected_head_model_handle;
    entity->weapon_model_handle = guard->selected_weapon_model_handle;
    entity->head_table_index = guard->selected_head_id;
    entity->skeleton_handle = guard->source.skeleton_handle;
    entity->animation_id = guard->source.animation_id;
    entity->attachment_first = attachment_first;
    entity->attachment_count = guard->source.attachment_count;
    entity->room_id = GE_RAMROM_GAMEPLAY_V6_UNKNOWN_U32;
    entity->state = guard->source.ai_state;
    entity->action_state = guard->source.action_state;
    entity->death_state = guard->source.death_state;
    entity->target_id = GE_RAMROM_GAMEPLAY_V6_UNKNOWN_U32;
    entity->source_prop_type = 9u;
    entity->source_record_offset = guard->source.source_record_offset;
    entity->source_aux0 = guard->source.ai_list_id;
    entity->source_aux1 = guard->source.pad_id;
    entity->visibility_mask = guard->source.visibility_state;
    entity->render_flags = guard->source.render_flags;
    entity->zbuffer_mode = guard->source.zbuffer_mode;
    entity->environment_rgba = guard->source.environment_rgba;
    entity->fog_rgba = guard->source.fog_rgba;
    entity->raw_other_mode_h = guard->source.raw_other_mode_h;
    entity->raw_other_mode_l = guard->source.raw_other_mode_l;
    entity->raw_render_mode = guard->source.raw_render_mode;
    entity->health = guard->source.health_current;
    entity->max_health = guard->source.health;
    memcpy(entity->position_q16, guard->source.position_q16, sizeof(entity->position_q16));
    memcpy(entity->velocity_q16, guard->source.velocity_q16, sizeof(entity->velocity_q16));
    memcpy(entity->rotation_q16, guard->source.rotation_q16, sizeof(entity->rotation_q16));
    memcpy(entity->scale_q16, guard->source.scale_q16, sizeof(entity->scale_q16));
    entity->previous_frame_q16 = guard->source.animation_frame_q16;
    entity->current_frame_q16 = guard->source.animation_frame_q16;
    entity->merge_weight_q16 = guard->source.animation_merge_q16;
    memcpy(entity->root_motion_q16, guard->source.root_motion_q16, sizeof(entity->root_motion_q16));
    memcpy(entity->source_transform_q16, guard->source.world_transform_q16,
           sizeof(entity->source_transform_q16));
    (void)state;
}

static void gd_fill_gameplay_door(const GEGuardDoorOwnerDoorStateV6 *door,
                                  GERamRomGameplayEntityV6 *entity)
{
    uint32_t index;
    memset(entity, 0, sizeof(*entity));
    gd_set_header(&entity->header, (uint32_t)sizeof(*entity));
    entity->record_version = GE_RAMROM_GAMEPLAY_V6_RECORD_VERSION;
    entity->entity_id = UINT32_C(0x80000000) | door->source.door_id;
    entity->entity_kind = GE_RAMROM_GAMEPLAY_V6_ENTITY_DOOR;
    entity->flags = GE_RAMROM_GAMEPLAY_V6_ENTITY_ACTIVE | GE_RAMROM_GAMEPLAY_V6_ENTITY_VISIBLE;
    if (door->interpolated) entity->flags |= GE_RAMROM_GAMEPLAY_V6_ENTITY_INTERPOLATED;
    else entity->flags |= GE_RAMROM_GAMEPLAY_V6_ENTITY_SOURCE_ANCHOR;
    entity->body_model_handle = door->source.model_handle;
    entity->room_id = GE_RAMROM_GAMEPLAY_V6_UNKNOWN_U32;
    entity->state = door->source.open_state;
    entity->action_state = door->source.open_state;
    entity->death_state = 0u;
    entity->target_id = GE_RAMROM_GAMEPLAY_V6_UNKNOWN_U32;
    entity->source_prop_type = 1u;
    entity->source_record_offset = door->source.source_record_offset;
    entity->source_aux0 = door->source.portal_number;
    entity->source_aux1 = door->source.pad_id;
    entity->visibility_mask = door->source.visibility_state;
    entity->render_flags = door->source.source_flags;
    entity->zbuffer_mode = GE_RAMROM_GAMEPLAY_V6_UNKNOWN_U32;
    entity->environment_rgba = GE_RAMROM_GAMEPLAY_V6_UNKNOWN_U32;
    entity->fog_rgba = GE_RAMROM_GAMEPLAY_V6_UNKNOWN_U32;
    entity->raw_other_mode_h = GE_RAMROM_GAMEPLAY_V6_UNKNOWN_U32;
    entity->raw_other_mode_l = GE_RAMROM_GAMEPLAY_V6_UNKNOWN_U32;
    entity->raw_render_mode = GE_RAMROM_GAMEPLAY_V6_UNKNOWN_U32;
    entity->health = GE_RAMROM_GAMEPLAY_V6_UNKNOWN_U32;
    entity->max_health = GE_RAMROM_GAMEPLAY_V6_UNKNOWN_U32;
    memcpy(entity->source_transform_q16, door->transform_q16, sizeof(entity->source_transform_q16));
    for (index = 0u; index < 3u; index++) {
        entity->position_q16[index] = door->transform_q16[12u + index];
        entity->scale_q16[index] = 65536;
    }
    entity->previous_frame_q16 = door->source.open_position_q16;
    entity->current_frame_q16 = door->source.open_position_q16;
    entity->merge_weight_q16 = door->source.open_position_q16;
}

GEStatusV1 ge_guard_door_owner_v6_copy_gameplay_pages(
    const GEGuardDoorOwnerStateV6 *state, uint32_t entity_capacity,
    GERamRomGameplayEntityV6 *out_entities, uint32_t attachment_capacity,
    GERamRomGameplayAttachmentV6 *out_attachments, uint32_t *out_entity_count,
    uint32_t *out_attachment_count)
{
    uint32_t index;
    uint32_t attachment_index = 0u;
    if (state == NULL || out_entity_count == NULL || out_attachment_count == NULL ||
        (entity_capacity != 0u && out_entities == NULL) ||
        (attachment_capacity != 0u && out_attachments == NULL) ||
        entity_capacity < state->guard_count + state->door_count) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    for (index = 0u; index < state->guard_count; index++) {
        uint32_t attachment_first = attachment_index;
        gd_fill_gameplay_entity(state, &state->guards[index], attachment_first, &out_entities[index]);
        if (attachment_index + state->guards[index].source.attachment_count > attachment_capacity) {
            return GE_STATUS_REPLAY_BUDGET;
        }
        for (uint32_t attachment = 0u; attachment < state->guards[index].source.attachment_count; attachment++) {
            const GEGuardDoorOwnerAttachmentV6 *source = &state->guards[index].attachments[attachment];
            GERamRomGameplayAttachmentV6 *target = &out_attachments[attachment_index++];
            memset(target, 0, sizeof(*target));
            gd_set_header(&target->header, (uint32_t)sizeof(*target));
            target->record_version = GE_RAMROM_GAMEPLAY_V6_RECORD_VERSION;
            target->attachment_id = attachment_index;
            target->entity_id = state->guards[index].source.guard_id + 2u;
            target->kind = source->flags;
            target->switch_handle = source->switch_handle;
            target->parent_joint = source->parent_joint;
            target->model_handle = source->model_handle;
            target->source_matrix_handle = source->source_matrix_handle;
            target->flags = source->flags;
            memcpy(target->transform_q16, source->transform_q16, sizeof(target->transform_q16));
        }
    }
    for (index = 0u; index < state->door_count; index++) {
        gd_fill_gameplay_door(&state->doors[index], &out_entities[state->guard_count + index]);
    }
    *out_entity_count = state->guard_count + state->door_count;
    *out_attachment_count = attachment_index;
    return GE_STATUS_OK;
}
