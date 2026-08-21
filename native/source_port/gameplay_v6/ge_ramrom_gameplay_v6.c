#include "ge_ramrom_gameplay_v6.h"
#include "ge_weapon_effect_owner_v6.h"

#include <limits.h>
#include <stddef.h>
#include <string.h>

/* Source randomGetNextFrom from src/random.s, expressed in fixed-width C.
   The RAMROM seed is 64-bit even though the recording checkpoint stores its
   low byte.  Keeping this helper here lets the gameplay owner use the same
   deterministic transition when a future AI/weapon slice requests a random
   value; it does not call an N64 or host random API. */
uint32_t ge_ramrom_gameplay_v6_source_random_next(uint64_t *seed)
{
    uint64_t value;
    uint64_t shifted;
    uint64_t next;

    if (seed == NULL) {
        return 0u;
    }
    value = *seed;
    shifted = ((value & UINT64_C(1)) << 32) | ((value >> 1) & UINT64_C(0x7fffffff));
    shifted ^= value << 12;
    next = shifted ^ ((shifted >> 20) & UINT64_C(0xfff));
    *seed = next;
    return (uint32_t)next;
}

uint32_t ge_ramrom_gameplay_v6_source_check_ramrom_flags(
    uint32_t is_ramrom_flag,
    uint32_t recording_ramrom_flag,
    uint32_t slot_number)
{
    return (is_ramrom_flag != 0u || recording_ramrom_flag != 0u) ? slot_number : 0u;
}

static const uint64_t GE_GAMEPLAY_FNV_OFFSET = UINT64_C(1469598103934665603);
static const uint64_t GE_GAMEPLAY_FNV_PRIME = UINT64_C(1099511628211);

/* Owner-thread scratch for the bounded guard/door merge.  The arrays are
   thread-local rather than stack-local so sanitizer stacks and the native
   owner thread do not inherit a 200 KiB temporary frame.  They are call-time
   scratch only and never enter a public record. */
static _Thread_local GERamRomGameplayEntityV6 ge_guard_door_owner_entities[
    GE_GUARD_DOOR_OWNER_V6_MAX_GUARDS + GE_GUARD_DOOR_OWNER_V6_MAX_DOORS];
static _Thread_local GERamRomGameplayAttachmentV6 ge_guard_door_owner_attachments[
    GE_GUARD_DOOR_OWNER_V6_MAX_GUARDS * GE_GUARD_DOOR_OWNER_V6_MAX_ATTACHMENTS_PER_GUARD];
static _Thread_local GERamRomGameplayEntityV6 ge_guard_door_merged_entities[
    GE_RAMROM_GAMEPLAY_V6_MAX_ENTITIES];
static _Thread_local GERamRomGameplayAttachmentV6 ge_guard_door_merged_attachments[
    GE_RAMROM_GAMEPLAY_V6_MAX_ATTACHMENTS];

static uint64_t ge_gameplay_hash_byte(uint64_t hash, uint8_t value)
{
    return (hash ^ (uint64_t)value) * GE_GAMEPLAY_FNV_PRIME;
}

static uint64_t ge_gameplay_hash_u32(uint64_t hash, uint32_t value)
{
    for (uint32_t shift = 0u; shift < 32u; shift += 8u) {
        hash = ge_gameplay_hash_byte(hash, (uint8_t)(value >> shift));
    }
    return hash;
}

static uint64_t ge_gameplay_hash_u64(uint64_t hash, uint64_t value)
{
    for (uint32_t shift = 0u; shift < 64u; shift += 8u) {
        hash = ge_gameplay_hash_byte(hash, (uint8_t)(value >> shift));
    }
    return hash;
}

static uint64_t ge_gameplay_hash_bytes(uint64_t hash,
                                       const uint8_t *bytes,
                                       size_t byte_count)
{
    if (bytes == NULL && byte_count != 0u) {
        return 0u;
    }
    for (size_t index = 0u; index < byte_count; index++) {
        hash = ge_gameplay_hash_byte(hash, bytes[index]);
    }
    return hash;
}

static GEStatusV1 ge_gameplay_validate_common(const GEAbiHeaderV1 *header,
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
    if (record_version != GE_RAMROM_GAMEPLAY_V6_RECORD_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    return GE_STATUS_OK;
}

static int ge_gameplay_is_route(uint32_t demo_id, uint32_t stage_id)
{
    static const uint32_t stages[GE_RAMROM_V5_DEMO_COUNT] = {
        GE_RAMROM_V5_STAGE_DAM, GE_RAMROM_V5_STAGE_DAM,
        GE_RAMROM_V5_STAGE_FACILITY, GE_RAMROM_V5_STAGE_FACILITY,
        GE_RAMROM_V5_STAGE_FACILITY, GE_RAMROM_V5_STAGE_RUNWAY,
        GE_RAMROM_V5_STAGE_RUNWAY, GE_RAMROM_V5_STAGE_BUNKER_I,
        GE_RAMROM_V5_STAGE_BUNKER_I, GE_RAMROM_V5_STAGE_SILO,
        GE_RAMROM_V5_STAGE_SILO, GE_RAMROM_V5_STAGE_FRIGATE,
        GE_RAMROM_V5_STAGE_FRIGATE, GE_RAMROM_V5_STAGE_TRAIN,
    };
    return demo_id != 0u && demo_id <= GE_RAMROM_V5_DEMO_COUNT &&
           stages[demo_id - 1u] == stage_id;
}

GEStatusV1 ge_ramrom_gameplay_v6_validate_setup(
    const GERamRomGameplaySetupV6 *value)
{
    GEStatusV1 status;
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_gameplay_validate_common(&value->header,
                                         (uint32_t)sizeof(*value),
                                         value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (!ge_gameplay_is_route(1u, value->stage_id) &&
        value->stage_id != GE_RAMROM_V5_STAGE_DAM &&
        value->stage_id != GE_RAMROM_V5_STAGE_FACILITY &&
        value->stage_id != GE_RAMROM_V5_STAGE_RUNWAY &&
        value->stage_id != GE_RAMROM_V5_STAGE_BUNKER_I &&
        value->stage_id != GE_RAMROM_V5_STAGE_SILO &&
        value->stage_id != GE_RAMROM_V5_STAGE_FRIGATE &&
        value->stage_id != GE_RAMROM_V5_STAGE_TRAIN) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    if ((value->flags & ~GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_MASK) != 0u ||
        value->demo_mask == 0u ||
        value->source_bytes == 0u || value->room_count > UINT16_MAX ||
        value->portal_count > UINT16_MAX ||
        value->stan_count > UINT32_C(1 << 24) ||
        value->object_count > GE_RAMROM_GAMEPLAY_V6_MAX_ENTITIES * 4u ||
        value->door_count > value->object_count ||
        value->guard_count > value->object_count ||
        value->objective_count > value->object_count ||
        value->prop_count > value->object_count ||
        value->initial_room == GE_RAMROM_GAMEPLAY_V6_UNKNOWN_U32 ||
        value->initial_pad == GE_RAMROM_GAMEPLAY_V6_UNKNOWN_U32 ||
        value->initial_room > value->room_count + 1u ||
        (value->world_min_q16[0] == 0 && value->world_min_q16[1] == 0 &&
         value->world_min_q16[2] == 0 && value->world_max_q16[0] == 0 &&
         value->world_max_q16[1] == 0 && value->world_max_q16[2] == 0) ||
        value->reserved0 != 0u || value->reserved1 != 0u ||
        value->source_hash == 0u || value->packet_hash == 0u ||
        value->model_dependency_hash == 0u ||
        ((value->flags & GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_STAN) != 0u &&
         (value->stan_source_bytes == 0u || value->stan_source_hash == 0u ||
          value->stan_bounds_hash == 0u)) ||
        (value->initial_pad != GE_RAMROM_GAMEPLAY_V6_UNKNOWN_U32 &&
         value->spawn_hash == 0u)) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_gameplay_v6_validate_input(
    const GERamRomGameplayInputV6 *value)
{
    GEStatusV1 status;
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_gameplay_validate_common(&value->header,
                                         (uint32_t)sizeof(*value),
                                         value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if ((value->flags & ~GE_RAMROM_GAMEPLAY_V6_INPUT_FLAG_MASK) != 0u ||
        value->controller_count == 0u || value->controller_count > 4u ||
        value->controller_index >= value->controller_count ||
        value->reserved0 != 0u || value->reserved1 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_gameplay_v6_validate_entity(
    const GERamRomGameplayEntityV6 *value)
{
    GEStatusV1 status;
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_gameplay_validate_common(&value->header,
                                         (uint32_t)sizeof(*value),
                                         value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->entity_id == 0u || value->entity_kind == 0u ||
        value->entity_kind > GE_RAMROM_GAMEPLAY_V6_ENTITY_MAX ||
        (value->flags & ~GE_RAMROM_GAMEPLAY_V6_ENTITY_FLAG_MASK) != 0u ||
        value->merge_weight_q16 < 0 || value->merge_weight_q16 > 65536 ||
        value->scale_q16[0] < 0 || value->scale_q16[1] < 0 ||
        value->scale_q16[2] < 0 || value->reserved0 != 0u ||
        value->reserved1 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_gameplay_v6_validate_attachment(
    const GERamRomGameplayAttachmentV6 *value)
{
    GEStatusV1 status;
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_gameplay_validate_common(&value->header,
                                         (uint32_t)sizeof(*value),
                                         value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->attachment_id == 0u || value->entity_id == 0u ||
        value->kind == 0u || value->model_handle == 0u ||
        value->reserved0 != 0u || value->reserved1 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_gameplay_v6_validate_snapshot(
    const GERamRomGameplaySnapshotV6 *value)
{
    GEStatusV1 status;
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_gameplay_validate_common(&value->header,
                                         (uint32_t)sizeof(*value),
                                         value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->pair_phase > 1u || value->source_anchor > 1u ||
        value->continuous_mask == 0u ||
        value->discrete_mask == 0u || value->controller_count == 0u ||
        value->controller_count > 4u ||
        value->entity_count > GE_RAMROM_GAMEPLAY_V6_MAX_ENTITIES ||
        value->attachment_count > GE_RAMROM_GAMEPLAY_V6_MAX_ATTACHMENTS ||
        value->input_stick_x < INT8_MIN || value->input_stick_x > INT8_MAX ||
        value->input_stick_y < INT8_MIN || value->input_stick_y > INT8_MAX ||
        value->source_hash == 0u || value->packet_hash == 0u ||
        value->state_hash == 0u || value->render_hash == 0u ||
        value->audio_hash == 0u || value->reserved0 != 0u ||
        value->reserved1 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_gameplay_v6_validate_player_camera_snapshot_v7(
    const GERamRomGameplayPlayerCameraSnapshotV7 *value)
{
    GEStatusV1 status;
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_gameplay_validate_common(&value->header,
                                         (uint32_t)sizeof(*value),
                                         value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if ((value->flags & ~GE_RAMROM_GAMEPLAY_PLAYER_CAMERA_V7_STATE_FLAG_MASK) != 0u ||
        value->demo_id == 0u || value->stage_id == 0u ||
        value->pair_phase > 1u ||
        value->source_hash == 0u || value->state_hash == 0u ||
        value->render_hash == 0u || value->reserved0 != 0u ||
        value->reserved1 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_gameplay_v6_validate_event(
    const GERamRomGameplayEventV6 *value)
{
    GEStatusV1 status;
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_gameplay_validate_common(&value->header,
                                         (uint32_t)sizeof(*value),
                                         value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->event_type > GE_RAMROM_GAMEPLAY_V6_EVENT_MAX ||
        (value->flags & ~GE_RAMROM_GAMEPLAY_V6_EVENT_MASK) != 0u ||
        value->pair_phase > 1u || value->source_anchor > 1u ||
        value->controller_count > 4u ||
        value->entity_count > GE_RAMROM_GAMEPLAY_V6_MAX_ENTITIES ||
        value->attachment_count > GE_RAMROM_GAMEPLAY_V6_MAX_ATTACHMENTS ||
        value->source_hash == 0u || value->packet_hash == 0u ||
        value->state_hash == 0u || value->event_hash == 0u ||
        value->reserved0 != 0u || value->reserved1 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_gameplay_v6_validate_page(
    const GERamRomGameplayPageV6 *value)
{
    GEStatusV1 status;
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_gameplay_validate_common(&value->header,
                                         (uint32_t)sizeof(*value),
                                         value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->page_kind == 0u || value->page_kind > GE_RAMROM_GAMEPLAY_V6_PAGE_MAX ||
        value->item_size == 0u || value->item_count == 0u ||
        value->item_count > GE_RAMROM_GAMEPLAY_V6_MAX_PAGED_ITEMS ||
        value->first_item + value->item_count > value->total_items ||
        value->reserved0 != 0u || value->reserved1 != 0u ||
        value->page_hash == 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

uint64_t ge_ramrom_gameplay_v6_hash_snapshot(
    const GERamRomGameplaySnapshotV6 *value)
{
    if (value == NULL) {
        return 0u;
    }
    uint64_t hash = GE_GAMEPLAY_FNV_OFFSET;
    hash = ge_gameplay_hash_u32(hash, value->flags);
    hash = ge_gameplay_hash_u32(hash, value->demo_id);
    hash = ge_gameplay_hash_u32(hash, value->stage_id);
    hash = ge_gameplay_hash_u64(hash, value->native_tick);
    hash = ge_gameplay_hash_u64(hash, value->reference_tick);
    hash = ge_gameplay_hash_u32(hash, value->pair_phase);
    hash = ge_gameplay_hash_u32(hash, value->source_anchor);
    hash = ge_gameplay_hash_u32(hash, value->source_frame);
    hash = ge_gameplay_hash_u32(hash, value->continuous_mask);
    hash = ge_gameplay_hash_u32(hash, value->discrete_mask);
    hash = ge_gameplay_hash_u32(hash, value->packet_index);
    hash = ge_gameplay_hash_u32(hash, value->frame_index);
    hash = ge_gameplay_hash_u32(hash, value->speedframes);
    hash = ge_gameplay_hash_u32(hash, value->rng_seed);
    hash = ge_gameplay_hash_u32(hash, value->checksum);
    hash = ge_gameplay_hash_u32(hash, value->computed_checksum);
    hash = ge_gameplay_hash_u32(hash, value->current_room);
    hash = ge_gameplay_hash_u32(hash, value->current_pad);
    hash = ge_gameplay_hash_u32(hash, value->player_health);
    hash = ge_gameplay_hash_u32(hash, value->player_weapon);
    hash = ge_gameplay_hash_u32(hash, value->player_animation);
    hash = ge_gameplay_hash_bytes(hash,
                                  (const uint8_t *)value->player_position_q16,
                                  sizeof(value->player_position_q16));
    hash = ge_gameplay_hash_bytes(hash,
                                  (const uint8_t *)value->camera_position_q16,
                                  sizeof(value->camera_position_q16));
    hash = ge_gameplay_hash_u32(hash, value->hud_health);
    hash = ge_gameplay_hash_u32(hash, value->hud_ammo);
    hash = ge_gameplay_hash_u32(hash, value->watch_state);
    hash = ge_gameplay_hash_u32(hash, value->fade_q16);
    hash = ge_gameplay_hash_u32(hash, value->sky_mode);
    hash = ge_gameplay_hash_u32(hash, value->input_buttons);
    hash = ge_gameplay_hash_byte(hash, (uint8_t)value->input_stick_x);
    hash = ge_gameplay_hash_byte(hash, (uint8_t)value->input_stick_y);
    hash = ge_gameplay_hash_u32(hash, value->one_shot_sequence);
    hash = ge_gameplay_hash_u64(hash, value->source_hash);
    hash = ge_gameplay_hash_u64(hash, value->packet_hash);
    hash = ge_gameplay_hash_u64(hash, value->rng_checkpoint_hash);
    return hash;
}

uint64_t ge_ramrom_gameplay_v6_hash_player_camera_snapshot_v7(
    const GERamRomGameplayPlayerCameraSnapshotV7 *value)
{
    uint64_t hash;
    uint32_t index;
    if (value == NULL) {
        return 0u;
    }
    hash = GE_GAMEPLAY_FNV_OFFSET;
    hash = ge_gameplay_hash_u32(hash, value->flags);
    hash = ge_gameplay_hash_u32(hash, value->demo_id);
    hash = ge_gameplay_hash_u32(hash, value->stage_id);
    hash = ge_gameplay_hash_u64(hash, value->native_tick);
    hash = ge_gameplay_hash_u64(hash, value->reference_tick);
    hash = ge_gameplay_hash_u32(hash, value->pair_phase);
    hash = ge_gameplay_hash_u32(hash, value->source_anchor);
    hash = ge_gameplay_hash_u32(hash, value->current_room);
    hash = ge_gameplay_hash_u32(hash, value->current_pad);
    hash = ge_gameplay_hash_u32(hash, value->weapon_model_handle);
    hash = ge_gameplay_hash_u32(hash, value->weapon_action);
    hash = ge_gameplay_hash_u32(hash, value->player_health);
    hash = ge_gameplay_hash_u32(hash, value->hud_ammo);
    hash = ge_gameplay_hash_u32(hash, value->player_animation);
    for (index = 0u; index < 3u; index++) {
        hash = ge_gameplay_hash_u32(hash, (uint32_t)value->player_position_q16[index]);
        hash = ge_gameplay_hash_u32(hash, (uint32_t)value->player_velocity_q16[index]);
        hash = ge_gameplay_hash_u32(hash, (uint32_t)value->camera_position_q16[index]);
        hash = ge_gameplay_hash_u32(hash, (uint32_t)value->camera_forward_q16[index]);
        hash = ge_gameplay_hash_u32(hash, (uint32_t)value->camera_up_q16[index]);
    }
    hash = ge_gameplay_hash_u32(hash, (uint32_t)value->yaw_q16);
    hash = ge_gameplay_hash_u32(hash, (uint32_t)value->pitch_q16);
    hash = ge_gameplay_hash_u64(hash, value->source_hash);
    hash = ge_gameplay_hash_u64(hash, value->state_hash);
    hash = ge_gameplay_hash_u64(hash, value->render_hash);
    return hash;
}

uint64_t ge_ramrom_gameplay_v6_hash_event(
    const GERamRomGameplayEventV6 *value)
{
    if (value == NULL) {
        return 0u;
    }
    uint64_t hash = GE_GAMEPLAY_FNV_OFFSET;
    hash = ge_gameplay_hash_u32(hash, value->event_type);
    hash = ge_gameplay_hash_u32(hash, value->flags);
    hash = ge_gameplay_hash_u32(hash, value->diagnostic_code);
    hash = ge_gameplay_hash_u64(hash, value->native_tick);
    hash = ge_gameplay_hash_u64(hash, value->reference_tick);
    hash = ge_gameplay_hash_u32(hash, value->pair_phase);
    hash = ge_gameplay_hash_u32(hash, value->demo_id);
    hash = ge_gameplay_hash_u32(hash, value->stage_id);
    hash = ge_gameplay_hash_u32(hash, value->packet_index);
    hash = ge_gameplay_hash_u32(hash, value->frame_index);
    hash = ge_gameplay_hash_u32(hash, value->source_anchor);
    hash = ge_gameplay_hash_u32(hash, value->source_frame);
    hash = ge_gameplay_hash_u32(hash, value->speedframes);
    hash = ge_gameplay_hash_u32(hash, value->rng_seed);
    hash = ge_gameplay_hash_u32(hash, value->checksum);
    hash = ge_gameplay_hash_u64(hash, value->sample_hash);
    hash = ge_gameplay_hash_u64(hash, value->source_hash);
    hash = ge_gameplay_hash_u64(hash, value->packet_hash);
    hash = ge_gameplay_hash_u64(hash, value->rng_checkpoint_hash);
    hash = ge_gameplay_hash_u64(hash, value->state_hash);
    return hash;
}

static void ge_gameplay_init_header(GEAbiHeaderV1 *header, uint32_t size)
{
    header->abi_version = GE_NATIVE_ABI_VERSION;
    header->struct_size = size;
}

static const GERamRomGameplayEntityV6 *ge_gameplay_const_player(
    const GERamRomGameplayStateV6 *state)
{
    return state->entity_count == 0u ? NULL : &state->entities[0];
}

static uint64_t ge_gameplay_entity_hash(const GERamRomGameplayStateV6 *state)
{
    uint64_t hash = GE_GAMEPLAY_FNV_OFFSET;
    for (uint32_t index = 0u; index < state->entity_count; index++) {
        const GERamRomGameplayEntityV6 *entity = &state->entities[index];
        hash = ge_gameplay_hash_u32(hash, entity->entity_id);
        hash = ge_gameplay_hash_u32(hash, entity->entity_kind);
        hash = ge_gameplay_hash_u32(hash, entity->flags);
        hash = ge_gameplay_hash_u32(hash, entity->animation_id);
        hash = ge_gameplay_hash_bytes(hash,
                                      (const uint8_t *)entity->position_q16,
                                      sizeof(entity->position_q16));
        hash = ge_gameplay_hash_bytes(hash,
                                      (const uint8_t *)entity->source_transform_q16,
                                      sizeof(entity->source_transform_q16));
        hash = ge_gameplay_hash_u32(hash, entity->state);
    }
    for (uint32_t index = 0u; index < state->attachment_count; index++) {
        const GERamRomGameplayAttachmentV6 *attachment = &state->attachments[index];
        hash = ge_gameplay_hash_u32(hash, attachment->attachment_id);
        hash = ge_gameplay_hash_u32(hash, attachment->entity_id);
        hash = ge_gameplay_hash_u32(hash, attachment->model_handle);
        hash = ge_gameplay_hash_bytes(hash,
                                      (const uint8_t *)attachment->transform_q16,
                                      sizeof(attachment->transform_q16));
    }
    return hash;
}

static void ge_gameplay_refresh_snapshot(GERamRomGameplayStateV6 *state)
{
    const GERamRomGameplayEntityV6 *player = ge_gameplay_const_player(state);
    GERamRomGameplaySnapshotV6 *snapshot = &state->snapshot;
    snapshot->flags = state->flags;
    snapshot->demo_id = state->demo_id;
    snapshot->stage_id = state->stage_id;
    snapshot->native_tick = state->native_tick;
    snapshot->reference_tick = state->reference_tick;
    snapshot->pair_phase = state->pair_phase;
    snapshot->source_anchor = state->pair_phase == 0u ? 1u : 0u;
    snapshot->source_frame = state->source_anchor_count;
    snapshot->packet_index = state->packet_index;
    snapshot->packet_count = state->packet_count;
    snapshot->frame_index = state->frame_index;
    snapshot->record_count = state->record_count;
    snapshot->speedframes = state->speedframes;
    snapshot->rng_seed = state->rng_seed;
    snapshot->controller_count = state->controller_count;
    snapshot->entity_count = state->entity_count;
    snapshot->attachment_count = state->attachment_count;
    snapshot->current_room = player == NULL ? state->setup.initial_room : player->room_id;
    snapshot->current_pad = state->setup.initial_pad;
    snapshot->door_count = state->setup.door_count;
    snapshot->guard_count = state->setup.guard_count;
    snapshot->objective_count = state->setup.objective_count;
    snapshot->prop_count = state->setup.prop_count;
    snapshot->effect_count = 0u;
    snapshot->projectile_count = 0u;
    snapshot->continuous_mask = GE_RAMROM_GAMEPLAY_V6_CONTINUOUS_PLAYER |
                                GE_RAMROM_GAMEPLAY_V6_CONTINUOUS_CAMERA |
                                GE_RAMROM_GAMEPLAY_V6_CONTINUOUS_ANIMATION |
                                GE_RAMROM_GAMEPLAY_V6_CONTINUOUS_ROOT_MOTION;
    snapshot->discrete_mask = GE_RAMROM_GAMEPLAY_V6_DISCRETE_AI |
                              GE_RAMROM_GAMEPLAY_V6_DISCRETE_RNG |
                              GE_RAMROM_GAMEPLAY_V6_DISCRETE_OBJECTIVES |
                              GE_RAMROM_GAMEPLAY_V6_DISCRETE_WEAPONS |
                              GE_RAMROM_GAMEPLAY_V6_DISCRETE_DOORS |
                              GE_RAMROM_GAMEPLAY_V6_DISCRETE_ONE_SHOTS;
    snapshot->source_hash = state->setup.source_hash;
    snapshot->packet_hash = state->packet_hash;
    snapshot->rng_checkpoint_hash = state->rng_checkpoint_hash;
    snapshot->input_flags = state->last_input.flags;
    snapshot->input_source_mask = state->last_input.source_mask;
    snapshot->input_buttons = state->last_buttons;
    snapshot->input_stick_x = state->last_input.stick_x;
    snapshot->input_stick_y = state->last_input.stick_y;
    snapshot->one_shot_sequence = state->one_shot_sequence;
    snapshot->player_health = player == NULL ? 0u : player->health;
    snapshot->player_weapon = player == NULL ? 0u : player->weapon_model_handle;
    snapshot->player_animation = player == NULL ? 0u : player->animation_id;
    snapshot->hud_health = snapshot->player_health;
    snapshot->hud_ammo = 0u;
    snapshot->watch_state = 0u;
    snapshot->fade_q16 = state->replay_state == GE_RAMROM_GAMEPLAY_V6_STATE_ABORTING ? 65536u : 0u;
    snapshot->sky_mode = state->stage_id;
    if (player != NULL) {
        memcpy(snapshot->player_position_q16, player->position_q16,
               sizeof(snapshot->player_position_q16));
        memcpy(snapshot->player_velocity_q16, player->velocity_q16,
               sizeof(snapshot->player_velocity_q16));
    } else {
        memcpy(snapshot->player_position_q16, state->setup.initial_position_q16,
               sizeof(snapshot->player_position_q16));
        memset(snapshot->player_velocity_q16, 0,
               sizeof(snapshot->player_velocity_q16));
    }
    /* Camera state is source setup data until the directly compiled source
       camera owner publishes a per-tick update. No host offset or guessed
       follow distance is introduced at this boundary. */
    memcpy(snapshot->camera_position_q16, state->setup.initial_position_q16,
           sizeof(snapshot->camera_position_q16));
    memcpy(snapshot->camera_forward_q16, state->setup.initial_forward_q16,
           sizeof(snapshot->camera_forward_q16));
    snapshot->camera_up_q16[1] = 65536;
    snapshot->state_hash = ge_ramrom_gameplay_v6_hash_snapshot(snapshot);
    snapshot->render_hash = ge_gameplay_entity_hash(state) ^ snapshot->state_hash;
    snapshot->audio_hash = state->input_hash ^ state->rng_checkpoint_hash;
}

static void ge_gameplay_init_event(const GERamRomGameplayStateV6 *state,
                                   uint32_t event_type,
                                   uint32_t flags,
                                   uint32_t diagnostic,
                                   GERamRomGameplayEventV6 *event)
{
    memset(event, 0, sizeof(*event));
    ge_gameplay_init_header(&event->header, (uint32_t)sizeof(*event));
    event->record_version = GE_RAMROM_GAMEPLAY_V6_RECORD_VERSION;
    event->event_type = event_type;
    event->flags = flags;
    event->diagnostic_code = diagnostic;
    event->native_tick = state->native_tick;
    event->reference_tick = state->reference_tick;
    event->pair_phase = state->pair_phase;
    event->demo_id = state->demo_id;
    event->stage_id = state->stage_id;
    event->packet_index = state->packet_index;
    event->packet_count = state->packet_count;
    event->frame_index = state->frame_index;
    event->record_count = state->record_count;
    event->source_anchor = state->source_anchor;
    event->source_frame = state->source_anchor_count;
    event->speedframes = state->speedframes;
    event->rng_seed = state->rng_seed;
    event->controller_count = state->controller_count;
    event->entity_count = state->entity_count;
    event->attachment_count = state->attachment_count;
    event->one_shot_sequence = state->one_shot_sequence;
    event->source_hash = state->setup.source_hash;
    event->packet_hash = state->packet_hash;
    event->rng_checkpoint_hash = state->rng_checkpoint_hash;
    event->state_hash = state->snapshot.state_hash;
    event->event_hash = ge_ramrom_gameplay_v6_hash_event(event);
}

static GEStatusV1 ge_gameplay_catalog_guard(const uint8_t *bytes,
                                            uint32_t byte_count,
                                            uint32_t demo_id,
                                            const GERamRomHeaderV5 *header,
                                            const GERamRomParseSummaryV5 *summary)
{
    GERamRomCatalogEntryV5 catalog;
    GEStatusV1 status;
    if (bytes == NULL || header == NULL || summary == NULL || demo_id == 0u ||
        demo_id > GE_RAMROM_V5_DEMO_COUNT) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_ramrom_v5_catalog_entry(demo_id - 1u, &catalog);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (byte_count != catalog.asset_file_bytes ||
        header->stage_id != catalog.stage_id ||
        header->controller_count != catalog.controller_count ||
        summary->recording_hash != catalog.recording_hash ||
        ge_ramrom_v5_hash_bytes(bytes, header->declared_file_bytes) !=
            catalog.recording_hash) {
        return GE_STATUS_ASSET_MISMATCH;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_gameplay_v6_begin_with_source_pages(
    const uint8_t *bytes,
    uint32_t byte_count,
    uint32_t demo_id,
    const GERamRomGameplaySetupV6 *setup,
    const GERamRomGameplayEntityV6 *entities,
    uint32_t entity_count,
    const GERamRomGameplayAttachmentV6 *attachments,
    uint32_t attachment_count,
    GERamRomGameplayStateV6 *out_state,
    GERamRomGameplayEventV6 *out_event)
{
    GERamRomHeaderV5 header;
    GERamRomParseSummaryV5 summary;
    GEStatusV1 status;
    if (bytes == NULL || setup == NULL || out_state == NULL || out_event == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (entities == NULL || entity_count == 0u ||
        entity_count > GE_RAMROM_GAMEPLAY_V6_MAX_ENTITIES ||
        (attachment_count != 0u && attachments == NULL) ||
        attachment_count > GE_RAMROM_GAMEPLAY_V6_MAX_ATTACHMENTS) {
        return GE_STATUS_UNSUPPORTED_COMMAND;
    }
    status = ge_ramrom_gameplay_v6_validate_setup(setup);
    if (status != GE_STATUS_OK) {
        return status;
    }
    status = ge_ramrom_v5_read_header(bytes, byte_count, &header);
    if (status != GE_STATUS_OK) {
        return status;
    }
    status = ge_ramrom_v5_parse(bytes, byte_count, &summary);
    if (status != GE_STATUS_OK) {
        return status;
    }
    status = ge_gameplay_catalog_guard(bytes, byte_count, demo_id, &header, &summary);
    if (status != GE_STATUS_OK || setup->stage_id != header.stage_id ||
        (setup->demo_mask & (UINT32_C(1) << (demo_id - 1u))) == 0u) {
        return status == GE_STATUS_OK ? GE_STATUS_ASSET_MISMATCH : status;
    }
    if ((setup->flags & (GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_SOURCE_DERIVED |
                         GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_ROOMS |
                         GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_STAN |
                         GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_OBJECTS |
                         GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_AI |
                         GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_MODEL_DEPENDENCIES)) !=
        (GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_SOURCE_DERIVED |
         GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_ROOMS |
         GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_STAN |
         GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_OBJECTS |
         GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_AI |
         GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_MODEL_DEPENDENCIES)) {
        return GE_STATUS_UNSUPPORTED_COMMAND;
    }

    memset(out_state, 0, sizeof(*out_state));
    ge_gameplay_init_header(&out_state->header, (uint32_t)sizeof(*out_state));
    out_state->record_version = GE_RAMROM_GAMEPLAY_V6_RECORD_VERSION;
    out_state->flags = GE_RAMROM_GAMEPLAY_V6_STATE_FLAG_ACTIVE |
                       GE_RAMROM_GAMEPLAY_V6_STATE_FLAG_INITIALIZED |
                       GE_RAMROM_GAMEPLAY_V6_STATE_FLAG_CHECKSUM;
    out_state->replay_state = GE_RAMROM_GAMEPLAY_V6_STATE_RUNNING;
    out_state->demo_id = demo_id;
    out_state->stage_id = header.stage_id;
    out_state->native_tick = UINT64_MAX;
    out_state->packet_count = summary.packet_count;
    out_state->record_count = summary.record_count;
    out_state->controller_count = header.controller_count;
    out_state->recording_hash = summary.recording_hash;
    out_state->packet_hash = summary.packet_hash;
    out_state->input_hash = summary.input_hash;
    out_state->rng_hash = summary.rng_hash;
    out_state->setup = *setup;
    ge_gameplay_init_header(&out_state->snapshot.header, (uint32_t)sizeof(out_state->snapshot));
    out_state->snapshot.record_version = GE_RAMROM_GAMEPLAY_V6_RECORD_VERSION;
    ge_gameplay_init_header(&out_state->last_input.header, (uint32_t)sizeof(out_state->last_input));
    out_state->last_input.record_version = GE_RAMROM_GAMEPLAY_V6_RECORD_VERSION;
    out_state->last_input.flags = GE_RAMROM_GAMEPLAY_V6_INPUT_RECORDED |
                                  GE_RAMROM_GAMEPLAY_V6_INPUT_FOCUSED |
                                  GE_RAMROM_GAMEPLAY_V6_INPUT_CONTROLLER;
    out_state->last_input.controller_count = (uint16_t)header.controller_count;
    for (uint32_t index = 0u; index < entity_count; index++) {
        status = ge_ramrom_gameplay_v6_validate_entity(&entities[index]);
        if (status != GE_STATUS_OK) {
            memset(out_state, 0, sizeof(*out_state));
            return status;
        }
        out_state->entities[index] = entities[index];
    }
    for (uint32_t index = 0u; index < attachment_count; index++) {
        status = ge_ramrom_gameplay_v6_validate_attachment(&attachments[index]);
        if (status != GE_STATUS_OK) {
            memset(out_state, 0, sizeof(*out_state));
            return status;
        }
        out_state->attachments[index] = attachments[index];
    }
    if (out_state->entities[0].entity_kind != GE_RAMROM_GAMEPLAY_V6_ENTITY_PLAYER) {
        memset(out_state, 0, sizeof(*out_state));
        return GE_STATUS_ASSET_MISMATCH;
    }
    out_state->entity_count = entity_count;
    out_state->attachment_count = attachment_count;
    ge_gameplay_refresh_snapshot(out_state);
    ge_gameplay_init_event(out_state, GE_RAMROM_GAMEPLAY_V6_EVENT_INSTALL,
                           GE_RAMROM_GAMEPLAY_V6_EVENT_SOURCE_ANCHOR |
                               GE_RAMROM_GAMEPLAY_V6_EVENT_CHECKSUM,
                           0u, out_event);
    out_state->gameplay_hash = ge_ramrom_gameplay_v6_hash_snapshot(&out_state->snapshot);
    out_event->state_hash = out_state->snapshot.state_hash;
    out_event->event_hash = ge_ramrom_gameplay_v6_hash_event(out_event);
    return GE_STATUS_OK;
}

static int ge_gameplay_owner_entity_id_matches(
    uint32_t entity_id,
    const GERamRomGameplayEntityV6 *owner_entities,
    uint32_t owner_entity_count)
{
    uint32_t index;
    for (index = 0u; index < owner_entity_count; index++) {
        if (owner_entities[index].entity_id == entity_id) {
            return 1;
        }
    }
    return 0;
}

static GEStatusV1 ge_gameplay_validate_guard_door_owner(
    const GEGuardDoorOwnerStateV6 *owner,
    const GERamRomGameplaySetupV6 *setup)
{
    uint32_t index;
    uint32_t required = GE_GUARD_DOOR_OWNER_V6_SETUP_FLAG_POSES |
                        GE_GUARD_DOOR_OWNER_V6_SETUP_FLAG_AI |
                        GE_GUARD_DOOR_OWNER_V6_SETUP_FLAG_BOUND_PAD_TRANSFORMS |
                        GE_GUARD_DOOR_OWNER_V6_SETUP_FLAG_MODEL_DEPENDENCIES |
                        GE_GUARD_DOOR_OWNER_V6_SETUP_FLAG_SOURCE_READY;
    if (owner == NULL || setup == NULL ||
        owner->header.abi_version != GE_NATIVE_ABI_VERSION ||
        owner->header.struct_size != sizeof(*owner) ||
        owner->record_version != GE_GUARD_DOOR_OWNER_V6_RECORD_VERSION ||
        owner->setup.stage_id != setup->stage_id ||
        owner->guard_count != setup->guard_count ||
        owner->door_count != setup->door_count ||
        (owner->setup.flags & required) != required ||
        owner->source_hash == 0u || owner->state_hash == 0u ||
        owner->render_hash == 0u) {
        return GE_STATUS_UNSUPPORTED_COMMAND;
    }
    if (ge_guard_door_owner_v6_validate_setup(&owner->setup) != GE_STATUS_OK) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    for (index = 0u; index < owner->guard_count; index++) {
        const GEGuardDoorOwnerGuardStateV6 *guard = &owner->guards[index];
        if (guard->selected_body_model_handle == 0u ||
            guard->selected_head_model_handle == 0u ||
            guard->selected_weapon_model_handle == 0u ||
            guard->source.skeleton_handle == 0u ||
            guard->source.animation_id == 0u ||
            guard->source.pose_count == 0u ||
            guard->pose_next_count != guard->pose_count ||
            guard->source.ai_state == GE_GUARD_DOOR_OWNER_V6_UNKNOWN_U32 ||
            guard->source.source_event_hash == 0u ||
            ge_guard_door_owner_v6_validate_guard(&guard->source) != GE_STATUS_OK) {
            return GE_STATUS_UNSUPPORTED_COMMAND;
        }
    }
    for (index = 0u; index < owner->door_count; index++) {
        const GEGuardDoorOwnerDoorStateV6 *door = &owner->doors[index];
        if (door->source.model_handle == 0u ||
            door->source.source_event_hash == 0u ||
            door->source.base_transform_q16[0] == 0 ||
            ge_guard_door_owner_v6_validate_door(&door->source) != GE_STATUS_OK) {
            return GE_STATUS_UNSUPPORTED_COMMAND;
        }
    }
    return GE_STATUS_OK;
}

/* Replace only guard/door rows while preserving the player and any other
   source-owned objective/prop rows.  The owner page is borrowed for this
   call; all values are copied into the bounded gameplay state. */
static GEStatusV1 ge_gameplay_apply_guard_door_owner(
    GERamRomGameplayStateV6 *state,
    const GEGuardDoorOwnerStateV6 *owner,
    int initial_install)
{
    GERamRomGameplayEntityV6 *owner_entities = ge_guard_door_owner_entities;
    GERamRomGameplayAttachmentV6 *owner_attachments = ge_guard_door_owner_attachments;
    GERamRomGameplayEntityV6 *merged_entities = ge_guard_door_merged_entities;
    GERamRomGameplayAttachmentV6 *merged_attachments = ge_guard_door_merged_attachments;
    uint32_t owner_entity_count = 0u;
    uint32_t owner_attachment_count = 0u;
    uint32_t merged_entity_count = 0u;
    uint32_t merged_attachment_count = 0u;
    uint32_t index;
    uint32_t attachment_id = 1u;
    GEStatusV1 status;

    if (state == NULL || owner == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_gameplay_validate_guard_door_owner(owner, &state->setup);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (!initial_install &&
        (owner->native_tick != state->native_tick ||
         owner->pair_phase != state->pair_phase ||
         owner->source_anchor != state->source_anchor)) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_guard_door_owner_v6_copy_gameplay_pages(
        owner,
        (uint32_t)(GE_GUARD_DOOR_OWNER_V6_MAX_GUARDS + GE_GUARD_DOOR_OWNER_V6_MAX_DOORS),
        owner_entities,
        GE_GUARD_DOOR_OWNER_V6_MAX_GUARDS * GE_GUARD_DOOR_OWNER_V6_MAX_ATTACHMENTS_PER_GUARD,
        owner_attachments,
        &owner_entity_count,
        &owner_attachment_count);
    if (status != GE_STATUS_OK || owner_entity_count == 0u) {
        return status == GE_STATUS_OK ? GE_STATUS_UNSUPPORTED_COMMAND : status;
    }
    for (index = 0u; index < state->entity_count; index++) {
        const GERamRomGameplayEntityV6 *entity = &state->entities[index];
        if (entity->entity_kind == GE_RAMROM_GAMEPLAY_V6_ENTITY_GUARD ||
            entity->entity_kind == GE_RAMROM_GAMEPLAY_V6_ENTITY_DOOR) {
            continue;
        }
        if (merged_entity_count >= GE_RAMROM_GAMEPLAY_V6_MAX_ENTITIES) {
            return GE_STATUS_REPLAY_BUDGET;
        }
        merged_entities[merged_entity_count++] = *entity;
    }
    for (index = 0u; index < state->attachment_count; index++) {
        const GERamRomGameplayAttachmentV6 *attachment = &state->attachments[index];
        if (ge_gameplay_owner_entity_id_matches(
                attachment->entity_id, owner_entities, owner_entity_count)) {
            continue;
        }
        if (merged_attachment_count >= GE_RAMROM_GAMEPLAY_V6_MAX_ATTACHMENTS) {
            return GE_STATUS_REPLAY_BUDGET;
        }
        merged_attachments[merged_attachment_count++] = *attachment;
        if (merged_attachments[merged_attachment_count - 1u].attachment_id >= attachment_id) {
            attachment_id = merged_attachments[merged_attachment_count - 1u].attachment_id + 1u;
        }
    }
    for (index = 0u; index < owner_entity_count; index++) {
        GERamRomGameplayEntityV6 entity = owner_entities[index];
        if (ge_gameplay_owner_entity_id_matches(
                entity.entity_id, owner_entities, index)) {
            return GE_STATUS_ASSET_MISMATCH;
        }
        if (ge_gameplay_owner_entity_id_matches(
                entity.entity_id, merged_entities, merged_entity_count)) {
            return GE_STATUS_ASSET_MISMATCH;
        }
        if (entity.attachment_first > owner_attachment_count ||
            entity.attachment_count > owner_attachment_count - entity.attachment_first ||
            merged_entity_count >= GE_RAMROM_GAMEPLAY_V6_MAX_ENTITIES) {
            return GE_STATUS_MALFORMED_STREAM;
        }
        entity.attachment_first = merged_attachment_count + entity.attachment_first;
        merged_entities[merged_entity_count++] = entity;
    }
    if (merged_attachment_count + owner_attachment_count > GE_RAMROM_GAMEPLAY_V6_MAX_ATTACHMENTS) {
        return GE_STATUS_REPLAY_BUDGET;
    }
    for (index = 0u; index < owner_attachment_count; index++) {
        GERamRomGameplayAttachmentV6 attachment = owner_attachments[index];
        attachment.attachment_id = attachment_id++;
        merged_attachments[merged_attachment_count++] = attachment;
    }
    memcpy(state->entities, merged_entities, merged_entity_count * sizeof(state->entities[0]));
    memcpy(state->attachments, merged_attachments, merged_attachment_count * sizeof(state->attachments[0]));
    state->entity_count = merged_entity_count;
    state->attachment_count = merged_attachment_count;
    state->flags |= GE_RAMROM_GAMEPLAY_V6_STATE_FLAG_GUARD_DOOR_OWNER;
    state->rng_checkpoint_hash = ge_gameplay_hash_u64(
        state->rng_checkpoint_hash == 0u ? GE_GAMEPLAY_FNV_OFFSET : state->rng_checkpoint_hash,
        owner->state_hash);
    ge_gameplay_refresh_snapshot(state);
    state->gameplay_hash = ge_gameplay_hash_u64(state->snapshot.state_hash, owner->state_hash);
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_gameplay_v6_begin_with_source_pages_and_guard_door_owner(
    const uint8_t *bytes,
    uint32_t byte_count,
    uint32_t demo_id,
    const GERamRomGameplaySetupV6 *setup,
    const GERamRomGameplayEntityV6 *entities,
    uint32_t entity_count,
    const GERamRomGameplayAttachmentV6 *attachments,
    uint32_t attachment_count,
    const GEGuardDoorOwnerStateV6 *guard_door_owner,
    GERamRomGameplayStateV6 *out_state,
    GERamRomGameplayEventV6 *out_event)
{
    GEStatusV1 status;
    status = ge_ramrom_gameplay_v6_begin_with_source_pages(
        bytes, byte_count, demo_id, setup, entities, entity_count,
        attachments, attachment_count, out_state, out_event);
    if (status != GE_STATUS_OK) {
        return status;
    }
    status = ge_gameplay_apply_guard_door_owner(out_state, guard_door_owner, 1);
    if (status != GE_STATUS_OK) {
        memset(out_state, 0, sizeof(*out_state));
        return status;
    }
    ge_gameplay_init_event(out_state, GE_RAMROM_GAMEPLAY_V6_EVENT_INSTALL,
                           GE_RAMROM_GAMEPLAY_V6_EVENT_SOURCE_ANCHOR |
                               GE_RAMROM_GAMEPLAY_V6_EVENT_CHECKSUM,
                           0u, out_event);
    out_event->detail0 = guard_door_owner->guard_count;
    out_event->detail1 = guard_door_owner->door_count;
    out_event->state_hash = out_state->snapshot.state_hash;
    out_event->event_hash = ge_ramrom_gameplay_v6_hash_event(out_event);
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_gameplay_v6_begin(
    const uint8_t *bytes,
    uint32_t byte_count,
    uint32_t demo_id,
    const GERamRomGameplaySetupV6 *setup,
    GERamRomGameplayStateV6 *out_state,
    GERamRomGameplayEventV6 *out_event)
{
    (void)bytes;
    (void)byte_count;
    (void)demo_id;
    (void)setup;
    (void)out_state;
    (void)out_event;
    /* A production caller must provide the source setup/model pages. This
       wrapper is retained as an explicit fail-closed seam so no guessed
       entities can silently enter the renderer. */
    return GE_STATUS_UNSUPPORTED_COMMAND;
}

static void ge_gameplay_input_from_sample(const GERamRomSampleV5 *sample,
                                          uint32_t controller_count,
                                          GERamRomGameplayInputV6 *out_input)
{
    memset(out_input, 0, sizeof(*out_input));
    ge_gameplay_init_header(&out_input->header, (uint32_t)sizeof(*out_input));
    out_input->record_version = GE_RAMROM_GAMEPLAY_V6_RECORD_VERSION;
    out_input->flags = GE_RAMROM_GAMEPLAY_V6_INPUT_RECORDED |
                       GE_RAMROM_GAMEPLAY_V6_INPUT_FOCUSED |
                       GE_RAMROM_GAMEPLAY_V6_INPUT_CONTROLLER;
    out_input->pressed_buttons = sample->buttons;
    out_input->held_buttons = sample->buttons;
    out_input->stick_x = sample->stick_x;
    out_input->stick_y = sample->stick_y;
    out_input->controller_count = (uint16_t)controller_count;
    out_input->source_mask = GE_RAMROM_GAMEPLAY_V6_INPUT_CONTROLLER;
}

GEStatusV1 ge_ramrom_gameplay_v6_step(
    const uint8_t *bytes,
    uint32_t byte_count,
    uint64_t native_tick,
    GERamRomGameplayInputV6 input,
    GERamRomGameplayStateV6 *inout_state,
    GERamRomGameplayEventV6 *out_event)
{
    GEStatusV1 status;
    uint64_t expected_tick;
    GERamRomPacketV5 packet;
    GERamRomSampleV5 sample;
    GERamRomGameplayInputV6 source_input;
    if (bytes == NULL || inout_state == NULL || out_event == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_ramrom_gameplay_v6_validate_input(&input);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (inout_state->header.abi_version != GE_NATIVE_ABI_VERSION ||
        inout_state->header.struct_size != sizeof(*inout_state) ||
        inout_state->record_version != GE_RAMROM_GAMEPLAY_V6_RECORD_VERSION) {
        return GE_STATUS_INVALID_STATE;
    }
    if ((inout_state->flags & GE_RAMROM_GAMEPLAY_V6_STATE_FLAG_ACTIVE) == 0u) {
        return GE_STATUS_INVALID_STATE;
    }
    expected_tick = inout_state->native_tick == UINT64_MAX ? 0u : inout_state->native_tick + 1u;
    if (native_tick != expected_tick) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    inout_state->native_tick = native_tick;
    inout_state->reference_tick = native_tick >> 1;
    inout_state->pair_phase = (uint32_t)(native_tick & 1u);
    inout_state->source_anchor = inout_state->pair_phase == 0u ? 1u : 0u;

    if (inout_state->replay_state == GE_RAMROM_GAMEPLAY_V6_STATE_ABORTING) {
        inout_state->replay_state = GE_RAMROM_GAMEPLAY_V6_STATE_COMPLETE;
        inout_state->flags &= ~GE_RAMROM_GAMEPLAY_V6_STATE_FLAG_ACTIVE;
        inout_state->flags |= GE_RAMROM_GAMEPLAY_V6_STATE_FLAG_RESTORE_READY;
        ge_gameplay_refresh_snapshot(inout_state);
        ge_gameplay_init_event(inout_state,
                               GE_RAMROM_GAMEPLAY_V6_EVENT_RESTORE,
                               GE_RAMROM_GAMEPLAY_V6_EVENT_END_OF_STREAM,
                               0u, out_event);
        out_event->state_hash = inout_state->snapshot.state_hash;
        out_event->event_hash = ge_ramrom_gameplay_v6_hash_event(out_event);
        return GE_STATUS_OK;
    }

    if ((input.flags & GE_RAMROM_GAMEPLAY_V6_INPUT_REAL) != 0u &&
        (input.pressed_buttons != 0u || input.held_buttons != 0u ||
         input.released_buttons != 0u)) {
        inout_state->flags |= GE_RAMROM_GAMEPLAY_V6_STATE_FLAG_REAL_ABORT;
        inout_state->replay_state = GE_RAMROM_GAMEPLAY_V6_STATE_ABORTING;
        inout_state->last_input = input;
        ge_gameplay_refresh_snapshot(inout_state);
        ge_gameplay_init_event(inout_state,
                               GE_RAMROM_GAMEPLAY_V6_EVENT_FADE,
                               GE_RAMROM_GAMEPLAY_V6_EVENT_ABORTED_INPUT,
                               1u, out_event);
        out_event->detail0 = input.pressed_buttons | input.held_buttons |
                             input.released_buttons;
        out_event->state_hash = inout_state->snapshot.state_hash;
        out_event->event_hash = ge_ramrom_gameplay_v6_hash_event(out_event);
        return GE_STATUS_OK;
    }

    if ((input.flags & GE_RAMROM_GAMEPLAY_V6_INPUT_FOCUSED) == 0u) {
        input.stick_x = 0;
        input.stick_y = 0;
        input.pressed_buttons = 0u;
        input.held_buttons = 0u;
        input.released_buttons = 0u;
        input.flags |= GE_RAMROM_GAMEPLAY_V6_INPUT_SUPPRESS_EDGES;
    }
    source_input = inout_state->last_input;
    if (inout_state->pair_phase == 0u) {
        if (inout_state->packet_index >= inout_state->packet_count) {
            inout_state->replay_state = GE_RAMROM_GAMEPLAY_V6_STATE_ABORTING;
            ge_gameplay_refresh_snapshot(inout_state);
            ge_gameplay_init_event(inout_state,
                                   GE_RAMROM_GAMEPLAY_V6_EVENT_FADE,
                                   GE_RAMROM_GAMEPLAY_V6_EVENT_END_OF_STREAM,
                                   0u, out_event);
            out_event->state_hash = inout_state->snapshot.state_hash;
            out_event->event_hash = ge_ramrom_gameplay_v6_hash_event(out_event);
            return GE_STATUS_OK;
        }
        status = ge_ramrom_v5_read_packet(bytes, byte_count,
                                          inout_state->packet_index, &packet);
        if (status != GE_STATUS_OK) {
            return status;
        }
        status = ge_ramrom_v5_copy_sample(bytes, byte_count,
                                          inout_state->packet_index,
                                          inout_state->frame_index, 0u, &sample);
        if (status != GE_STATUS_OK) {
            return status;
        }
        ge_gameplay_input_from_sample(&sample, inout_state->controller_count,
                                      &source_input);
        source_input.pressed_buttons = sample.buttons & ~inout_state->last_buttons;
        source_input.released_buttons = inout_state->last_buttons & ~sample.buttons;
        inout_state->last_input = source_input;
        inout_state->source_anchor = 1u;
        inout_state->source_anchor_count++;
        inout_state->frame_index++;
        if (inout_state->frame_index >= packet.record_count) {
            inout_state->packet_index++;
            inout_state->frame_index = 0u;
            if (inout_state->packet_index >= inout_state->packet_count) {
                /* The next source anchor emits the source-ordered fade. */
                inout_state->replay_state = GE_RAMROM_GAMEPLAY_V6_STATE_RUNNING;
            }
        }
        if (packet.flags & GE_RAMROM_V5_PACKET_FLAG_RNG_CHECKPOINT) {
            inout_state->rng_checkpoint_count++;
            inout_state->rng_seed = packet.rng_seed;
            inout_state->rng_checkpoint_hash = ge_gameplay_hash_u32(
                inout_state->rng_checkpoint_hash == 0u ? GE_GAMEPLAY_FNV_OFFSET :
                    inout_state->rng_checkpoint_hash, packet.rng_seed);
            inout_state->flags |= GE_RAMROM_GAMEPLAY_V6_STATE_FLAG_RNG_CHECKPOINT;
        }
        inout_state->checksum_count++;
        inout_state->flags |= GE_RAMROM_GAMEPLAY_V6_STATE_FLAG_SOURCE_ANCHOR |
                              GE_RAMROM_GAMEPLAY_V6_STATE_FLAG_CHECKSUM;
        inout_state->last_buttons = sample.buttons;
        inout_state->speedframes = packet.speedframes;
        inout_state->rng_seed = packet.rng_seed;
        inout_state->snapshot.speedframes = packet.speedframes;
        inout_state->snapshot.rng_seed = packet.rng_seed;
        inout_state->snapshot.checksum = packet.checksum;
        inout_state->snapshot.computed_checksum = packet.computed_checksum;
        inout_state->snapshot.input_buttons = sample.buttons;
        inout_state->snapshot.input_stick_x = sample.stick_x;
        inout_state->snapshot.input_stick_y = sample.stick_y;
        ge_gameplay_refresh_snapshot(inout_state);
        ge_gameplay_init_event(inout_state,
                               GE_RAMROM_GAMEPLAY_V6_EVENT_SOURCE_INPUT,
                               GE_RAMROM_GAMEPLAY_V6_EVENT_SOURCE_ANCHOR |
                                   GE_RAMROM_GAMEPLAY_V6_EVENT_CHECKSUM |
                                   ((packet.flags & GE_RAMROM_V5_PACKET_FLAG_RNG_CHECKPOINT) != 0u ?
                                       GE_RAMROM_GAMEPLAY_V6_EVENT_RNG_CHECKPOINT : 0u),
                               0u, out_event);
        out_event->packet_index = packet.packet_index;
        out_event->frame_index = sample.frame_index;
        out_event->speedframes = packet.speedframes;
        out_event->rng_seed = packet.rng_seed;
        out_event->checksum = packet.checksum;
        out_event->computed_checksum = packet.computed_checksum;
        out_event->stick_x = sample.stick_x;
        out_event->stick_y = sample.stick_y;
        out_event->buttons = sample.buttons;
        out_event->sample_hash = ge_ramrom_v5_hash_bytes(
            (const uint8_t *)&sample.stick_x, 4u);
        out_event->state_hash = inout_state->snapshot.state_hash;
        out_event->event_hash = ge_ramrom_gameplay_v6_hash_event(out_event);
    } else {
        /* Odd ticks publish a paired snapshot only.  Player/camera/AI,
           animation, objective, weapon, effect and RNG owners advance only
           when the directly compiled source adapter supplies that update. */
        ge_gameplay_refresh_snapshot(inout_state);
        ge_gameplay_init_event(inout_state,
                               GE_RAMROM_GAMEPLAY_V6_EVENT_STATE,
                               GE_RAMROM_GAMEPLAY_V6_EVENT_ODD_PAIRED_TICK,
                               0u, out_event);
        out_event->state_hash = inout_state->snapshot.state_hash;
        out_event->event_hash = ge_ramrom_gameplay_v6_hash_event(out_event);
    }
    inout_state->input_hash = ge_gameplay_hash_u32(inout_state->input_hash == 0u ?
                                                       GE_GAMEPLAY_FNV_OFFSET : inout_state->input_hash,
                                                   inout_state->last_buttons);
    inout_state->gameplay_hash = inout_state->snapshot.state_hash;
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_gameplay_v6_step_with_guard_door_owner(
    const uint8_t *bytes,
    uint32_t byte_count,
    uint64_t native_tick,
    GERamRomGameplayInputV6 input,
    const GEGuardDoorOwnerStateV6 *guard_door_owner,
    GERamRomGameplayStateV6 *inout_state,
    GERamRomGameplayEventV6 *out_event)
{
    GEStatusV1 status;
    if (inout_state == NULL || guard_door_owner == NULL || out_event == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if ((inout_state->flags & GE_RAMROM_GAMEPLAY_V6_STATE_FLAG_GUARD_DOOR_OWNER) == 0u) {
        return GE_STATUS_INVALID_STATE;
    }
    status = ge_ramrom_gameplay_v6_step(
        bytes, byte_count, native_tick, input, inout_state, out_event
    );
    if (status != GE_STATUS_OK) {
        return status;
    }
    status = ge_gameplay_apply_guard_door_owner(inout_state, guard_door_owner, 0);
    if (status != GE_STATUS_OK) {
        return status;
    }
    out_event->detail0 = guard_door_owner->guard_count;
    out_event->detail1 = guard_door_owner->door_count;
    out_event->state_hash = inout_state->snapshot.state_hash;
    out_event->event_hash = ge_ramrom_gameplay_v6_hash_event(out_event);
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_gameplay_v6_validate_state(
    const GERamRomGameplayStateV6 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (value->header.abi_version != GE_NATIVE_ABI_VERSION ||
        value->header.struct_size != sizeof(*value) ||
        value->record_version != GE_RAMROM_GAMEPLAY_V6_RECORD_VERSION ||
        value->replay_state > GE_RAMROM_GAMEPLAY_V6_STATE_ERROR ||
        value->pair_phase > 1u || value->entity_count > GE_RAMROM_GAMEPLAY_V6_MAX_ENTITIES ||
        value->attachment_count > GE_RAMROM_GAMEPLAY_V6_MAX_ATTACHMENTS ||
        value->controller_count == 0u || value->controller_count > 4u ||
        value->recording_hash == 0u || value->packet_hash == 0u ||
        value->input_hash == 0u || value->rng_hash == 0u ||
        ge_ramrom_gameplay_v6_validate_setup(&value->setup) != GE_STATUS_OK) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_gameplay_v6_seed_entity(
    GERamRomGameplayStateV6 *inout_state,
    const GERamRomGameplayEntityV6 *seed)
{
    if (inout_state == NULL || seed == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (inout_state->entity_count >= GE_RAMROM_GAMEPLAY_V6_MAX_ENTITIES) {
        return GE_STATUS_TEXTURE_OVERFLOW;
    }
    GEStatusV1 status = ge_ramrom_gameplay_v6_validate_entity(seed);
    if (status != GE_STATUS_OK) {
        return status;
    }
    inout_state->entities[inout_state->entity_count++] = *seed;
    ge_gameplay_refresh_snapshot(inout_state);
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_gameplay_v6_seed_attachment(
    GERamRomGameplayStateV6 *inout_state,
    const GERamRomGameplayAttachmentV6 *seed)
{
    if (inout_state == NULL || seed == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (inout_state->attachment_count >= GE_RAMROM_GAMEPLAY_V6_MAX_ATTACHMENTS) {
        return GE_STATUS_TEXTURE_OVERFLOW;
    }
    GEStatusV1 status = ge_ramrom_gameplay_v6_validate_attachment(seed);
    if (status != GE_STATUS_OK) {
        return status;
    }
    inout_state->attachments[inout_state->attachment_count++] = *seed;
    ge_gameplay_refresh_snapshot(inout_state);
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_gameplay_v6_copy_snapshot(
    const GERamRomGameplayStateV6 *state,
    GERamRomGameplaySnapshotV6 *out_snapshot)
{
    if (state == NULL || out_snapshot == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    *out_snapshot = state->snapshot;
    return ge_ramrom_gameplay_v6_validate_snapshot(out_snapshot);
}

GEStatusV1 ge_ramrom_gameplay_v6_apply_player_camera_snapshot_v7(
    GERamRomGameplayStateV6 *inout_state,
    const GERamRomGameplayPlayerCameraSnapshotV7 *player_camera,
    GERamRomGameplayEventV6 *optional_event)
{
    GERamRomGameplayEntityV6 *player;
    GERamRomGameplaySnapshotV6 previous_snapshot;
    GERamRomGameplayEntityV6 previous_player;
    uint64_t audio_hash;
    uint64_t render_hash;
    GEStatusV1 status;

    if (inout_state == NULL || player_camera == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_ramrom_gameplay_v6_validate_player_camera_snapshot_v7(player_camera);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (inout_state->header.abi_version != GE_NATIVE_ABI_VERSION ||
        inout_state->header.struct_size != sizeof(*inout_state) ||
        inout_state->record_version != GE_RAMROM_GAMEPLAY_V6_RECORD_VERSION ||
        (inout_state->flags & GE_RAMROM_GAMEPLAY_V6_STATE_FLAG_ACTIVE) == 0u ||
        inout_state->demo_id != player_camera->demo_id ||
        inout_state->stage_id != player_camera->stage_id ||
        inout_state->entity_count == 0u) {
        return GE_STATUS_INVALID_STATE;
    }
    /* The C playback step and the source player/camera owner must publish the
       same native cadence. UINT64_MAX is the pre-step sentinel and is only
       accepted for a caller that explicitly applies an initial publication. */
    if (inout_state->native_tick != UINT64_MAX &&
        (inout_state->native_tick != player_camera->native_tick ||
         inout_state->pair_phase != player_camera->pair_phase)) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    player = &inout_state->entities[0];
    if (player->entity_kind != GE_RAMROM_GAMEPLAY_V6_ENTITY_PLAYER) {
        return GE_STATUS_ASSET_MISMATCH;
    }
    if (optional_event != NULL) {
        status = ge_ramrom_gameplay_v6_validate_event(optional_event);
        if (status != GE_STATUS_OK) {
            return status;
        }
    }

    previous_snapshot = inout_state->snapshot;
    previous_player = *player;

    /* Only the player row's mutable source publication is joined here.  Do
       not copy camera state into setup, object rows, or unsupported owner
       categories; those remain owned by their respective source seams. */
    memcpy(player->position_q16, player_camera->player_position_q16,
           sizeof(player->position_q16));
    memcpy(player->velocity_q16, player_camera->player_velocity_q16,
           sizeof(player->velocity_q16));
    player->room_id = player_camera->current_room;
    player->weapon_model_handle = player_camera->weapon_model_handle;
    player->action_state = player_camera->weapon_action;
    player->animation_id = player_camera->player_animation;
    player->health = player_camera->player_health;

    inout_state->snapshot.native_tick = player_camera->native_tick;
    inout_state->snapshot.reference_tick = player_camera->reference_tick;
    inout_state->snapshot.pair_phase = player_camera->pair_phase;
    /* The player owner publishes a monotonically increasing source-frame
       count; the gameplay record retains its existing boolean anchor bit and
       carries that count in source_frame. */
    inout_state->snapshot.source_anchor = player_camera->pair_phase == 0u ? 1u : 0u;
    inout_state->snapshot.source_frame = player_camera->source_anchor;
    inout_state->snapshot.current_room = player_camera->current_room;
    inout_state->snapshot.current_pad = player_camera->current_pad;
    inout_state->snapshot.player_health = player_camera->player_health;
    inout_state->snapshot.player_weapon = player_camera->weapon_model_handle;
    inout_state->snapshot.player_animation = player_camera->player_animation;
    inout_state->snapshot.hud_health = player_camera->player_health;
    inout_state->snapshot.hud_ammo = player_camera->hud_ammo;
    memcpy(inout_state->snapshot.player_position_q16,
           player_camera->player_position_q16,
           sizeof(inout_state->snapshot.player_position_q16));
    memcpy(inout_state->snapshot.player_velocity_q16,
           player_camera->player_velocity_q16,
           sizeof(inout_state->snapshot.player_velocity_q16));
    memcpy(inout_state->snapshot.camera_position_q16,
           player_camera->camera_position_q16,
           sizeof(inout_state->snapshot.camera_position_q16));
    memcpy(inout_state->snapshot.camera_forward_q16,
           player_camera->camera_forward_q16,
           sizeof(inout_state->snapshot.camera_forward_q16));
    memcpy(inout_state->snapshot.camera_up_q16,
           player_camera->camera_up_q16,
           sizeof(inout_state->snapshot.camera_up_q16));

    inout_state->snapshot.state_hash =
        ge_ramrom_gameplay_v6_hash_snapshot(&inout_state->snapshot);
    if (inout_state->snapshot.state_hash == 0u) {
        inout_state->snapshot.state_hash = GE_GAMEPLAY_FNV_OFFSET;
    }
    render_hash = ge_gameplay_entity_hash(inout_state) ^
                  inout_state->snapshot.state_hash;
    inout_state->snapshot.render_hash = render_hash == 0u ?
        GE_GAMEPLAY_FNV_OFFSET : render_hash;
    audio_hash = inout_state->input_hash ^ inout_state->rng_checkpoint_hash;
    inout_state->snapshot.audio_hash = audio_hash == 0u ?
        ge_gameplay_hash_u64(GE_GAMEPLAY_FNV_OFFSET,
                             player_camera->source_hash) : audio_hash;
    inout_state->gameplay_hash = inout_state->snapshot.state_hash;

    status = ge_ramrom_gameplay_v6_validate_snapshot(&inout_state->snapshot);
    if (status != GE_STATUS_OK) {
        inout_state->snapshot = previous_snapshot;
        *player = previous_player;
        return status;
    }
    if (optional_event != NULL) {
        optional_event->state_hash = inout_state->snapshot.state_hash;
        optional_event->event_hash = ge_ramrom_gameplay_v6_hash_event(optional_event);
        status = ge_ramrom_gameplay_v6_validate_event(optional_event);
        if (status != GE_STATUS_OK) {
            inout_state->snapshot = previous_snapshot;
            *player = previous_player;
            return status;
        }
    }
    return GE_STATUS_OK;
}

static GEStatusV1 ge_gameplay_copy_page_items(
    const GERamRomGameplayStateV6 *state,
    uint32_t page_kind,
    uint32_t first_item,
    uint32_t item_count,
    uint32_t item_size,
    GERamRomGameplayPageV6 *out_page)
{
    uint32_t total = page_kind == GE_RAMROM_GAMEPLAY_V6_PAGE_ENTITIES ?
        state->entity_count : state->attachment_count;
    uint64_t hash = GE_GAMEPLAY_FNV_OFFSET;
    if (first_item >= total || item_count == 0u) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (page_kind == GE_RAMROM_GAMEPLAY_V6_PAGE_ENTITIES) {
        hash = ge_gameplay_hash_bytes(hash,
            (const uint8_t *)&state->entities[first_item],
            (size_t)item_count * sizeof(state->entities[0]));
    } else {
        hash = ge_gameplay_hash_bytes(hash,
            (const uint8_t *)&state->attachments[first_item],
            (size_t)item_count * sizeof(state->attachments[0]));
    }
    memset(out_page, 0, sizeof(*out_page));
    ge_gameplay_init_header(&out_page->header, (uint32_t)sizeof(*out_page));
    out_page->record_version = GE_RAMROM_GAMEPLAY_V6_RECORD_VERSION;
    out_page->page_kind = page_kind;
    out_page->page_index = first_item / GE_RAMROM_GAMEPLAY_V6_MAX_PAGED_ITEMS;
    out_page->item_size = item_size;
    out_page->first_item = first_item;
    out_page->item_count = item_count;
    out_page->total_items = total;
    out_page->page_hash = hash;
    return ge_ramrom_gameplay_v6_validate_page(out_page);
}

GEStatusV1 ge_ramrom_gameplay_v6_copy_page(
    const GERamRomGameplayStateV6 *state,
    uint32_t page_kind,
    uint32_t page_index,
    GERamRomGameplayPageV6 *out_page)
{
    uint32_t first_item;
    uint32_t total;
    uint32_t count;
    if (state == NULL || out_page == NULL ||
        (page_kind != GE_RAMROM_GAMEPLAY_V6_PAGE_ENTITIES &&
         page_kind != GE_RAMROM_GAMEPLAY_V6_PAGE_ATTACHMENTS)) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    total = page_kind == GE_RAMROM_GAMEPLAY_V6_PAGE_ENTITIES ?
        state->entity_count : state->attachment_count;
    first_item = page_index * GE_RAMROM_GAMEPLAY_V6_MAX_PAGED_ITEMS;
    if (page_index > UINT32_MAX / GE_RAMROM_GAMEPLAY_V6_MAX_PAGED_ITEMS ||
        first_item >= total) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    count = total - first_item;
    if (count > GE_RAMROM_GAMEPLAY_V6_MAX_PAGED_ITEMS) {
        count = GE_RAMROM_GAMEPLAY_V6_MAX_PAGED_ITEMS;
    }
    return ge_gameplay_copy_page_items(
        state, page_kind, first_item, count,
        page_kind == GE_RAMROM_GAMEPLAY_V6_PAGE_ENTITIES ?
            (uint32_t)sizeof(state->entities[0]) : (uint32_t)sizeof(state->attachments[0]),
        out_page);
}

GEStatusV1 ge_ramrom_gameplay_v6_copy_entities(
    const GERamRomGameplayStateV6 *state,
    uint32_t first_item,
    uint32_t capacity,
    GERamRomGameplayEntityV6 *out_items,
    uint32_t *out_copied)
{
    if (state == NULL || out_copied == NULL ||
        (capacity != 0u && out_items == NULL) || first_item > state->entity_count ||
        capacity > GE_RAMROM_GAMEPLAY_V6_MAX_PAGED_ITEMS) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    uint32_t count = state->entity_count - first_item;
    if (count > capacity) {
        count = capacity;
    }
    if (count != 0u) {
        memcpy(out_items, &state->entities[first_item], count * sizeof(*out_items));
    }
    *out_copied = count;
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_gameplay_v6_copy_attachments(
    const GERamRomGameplayStateV6 *state,
    uint32_t first_item,
    uint32_t capacity,
    GERamRomGameplayAttachmentV6 *out_items,
    uint32_t *out_copied)
{
    if (state == NULL || out_copied == NULL ||
        (capacity != 0u && out_items == NULL) || first_item > state->attachment_count ||
        capacity > GE_RAMROM_GAMEPLAY_V6_MAX_PAGED_ITEMS) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    uint32_t count = state->attachment_count - first_item;
    if (count > capacity) {
        count = capacity;
    }
    if (count != 0u) {
        memcpy(out_items, &state->attachments[first_item], count * sizeof(*out_items));
    }
    *out_copied = count;
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_gameplay_v6_restore(
    GERamRomGameplayStateV6 *inout_state,
    const GERamRomGameplaySnapshotV6 *snapshot)
{
    if (inout_state == NULL || snapshot == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (ge_ramrom_gameplay_v6_validate_snapshot(snapshot) != GE_STATUS_OK ||
        snapshot->demo_id != inout_state->demo_id ||
        snapshot->stage_id != inout_state->stage_id) {
        return GE_STATUS_ASSET_MISMATCH;
    }
    inout_state->snapshot = *snapshot;
    inout_state->native_tick = snapshot->native_tick;
    inout_state->reference_tick = snapshot->reference_tick;
    inout_state->pair_phase = snapshot->pair_phase;
    inout_state->source_anchor = snapshot->source_anchor;
    inout_state->source_anchor_count = snapshot->source_frame;
    inout_state->packet_index = snapshot->packet_index;
    inout_state->frame_index = snapshot->frame_index;
    inout_state->speedframes = snapshot->speedframes;
    inout_state->rng_seed = snapshot->rng_seed;
    inout_state->last_buttons = snapshot->input_buttons;
    inout_state->one_shot_sequence = snapshot->one_shot_sequence;
    inout_state->replay_state = GE_RAMROM_GAMEPLAY_V6_STATE_RUNNING;
    inout_state->flags |= GE_RAMROM_GAMEPLAY_V6_STATE_FLAG_ACTIVE |
                          GE_RAMROM_GAMEPLAY_V6_STATE_FLAG_RESTORE_READY;
    inout_state->flags &= ~GE_RAMROM_GAMEPLAY_V6_STATE_FLAG_REAL_ABORT;
    return GE_STATUS_OK;
}

/* ------------------------------------------------------------------------- */
/* Additive source weapon/effect join.                                      */

static int ge_gameplay_weapon_entity_kind(uint32_t category,
                                          uint32_t *out_kind)
{
    if (out_kind == NULL) {
        return 0;
    }
    if (category == GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_PROJECTILE) {
        *out_kind = GE_RAMROM_GAMEPLAY_V6_ENTITY_PROJECTILE;
        return 1;
    }
    if (category == GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_GLASS) {
        *out_kind = GE_RAMROM_GAMEPLAY_V6_ENTITY_GLASS;
        return 1;
    }
    if (category == GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_MUZZLE ||
        category == GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_PARTICLE ||
        category == GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_EXPLOSION) {
        *out_kind = GE_RAMROM_GAMEPLAY_V6_ENTITY_EFFECT;
        return 1;
    }
    return 0;
}

static int ge_gameplay_weapon_entity_id_exists(
    const GERamRomGameplayStateV6 *state,
    uint32_t entity_id)
{
    uint32_t index;
    for (index = 0u; index < state->entity_count; index++) {
        if (state->entities[index].entity_id == entity_id) {
            return 1;
        }
    }
    return 0;
}

static void ge_gameplay_weapon_update_player(
    GERamRomGameplayStateV6 *state,
    const GERamRomWeaponEffectFrameV6 *frame)
{
    uint32_t index;
    if (frame->hand_count == 0u) {
        return;
    }
    for (index = 0u; index < state->entity_count; index++) {
        GERamRomGameplayEntityV6 *entity = &state->entities[index];
        if (entity->entity_kind == GE_RAMROM_GAMEPLAY_V6_ENTITY_PLAYER) {
            entity->weapon_model_handle = frame->hands[0].model_handle;
            entity->source_prop_type = frame->hands[0].weapon_id;
            entity->action_state = frame->hands[0].action_state;
            entity->current_frame_q16 = frame->hands[0].animation_frame_q16;
            entity->previous_frame_q16 = frame->hands[0].animation_frame_q16;
            entity->merge_weight_q16 = frame->hands[0].animation_rate_q16;
            entity->source_aux0 = frame->right_ammo_type;
            entity->source_aux1 = frame->right_magazine;
            return;
        }
    }
}

static GEStatusV1 ge_gameplay_publish_weapon_entities(
    GERamRomGameplayStateV6 *state,
    const GERamRomWeaponEffectOwnerStateV6 *weapon_state)
{
    const GERamRomWeaponEffectFrameV6 *frame;
    uint32_t index;
    uint32_t base_count = 0u;
    uint32_t effect_count = 0u;
    uint32_t projectile_count = 0u;

    if (state == NULL || weapon_state == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    frame = &weapon_state->render_frame;
    if (ge_ramrom_weapon_effect_v6_validate_frame(frame) != GE_STATUS_OK) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    /* Validate IDs and capacity before changing the caller-owned gameplay
       state.  Source event IDs are the stable entity IDs at this seam. */
    for (index = 0u; index < frame->event_count; index++) {
        uint32_t kind;
        uint32_t prior;
        const GERamRomWeaponEffectEventV6 *event = &frame->events[index];
        if (!ge_gameplay_weapon_entity_kind(event->category, &kind)) {
            continue;
        }
        (void)kind;
        for (prior = 0u; prior < index; prior++) {
            if (frame->events[prior].source_event_id == event->source_event_id &&
                ge_gameplay_weapon_entity_kind(frame->events[prior].category, &kind)) {
                return GE_STATUS_ASSET_MISMATCH;
            }
        }
        if (event->source_event_id == 0u ||
            ge_gameplay_weapon_entity_id_exists(state, event->source_event_id)) {
            /* An existing transient row is replaced below; collisions with a
               non-transient source entity are not representable safely. */
            uint32_t prior;
            int transient_collision = 0;
            for (prior = 0u; prior < state->entity_count; prior++) {
                uint32_t prior_kind = state->entities[prior].entity_kind;
                if (state->entities[prior].entity_id == event->source_event_id &&
                    (prior_kind == GE_RAMROM_GAMEPLAY_V6_ENTITY_PROJECTILE ||
                     prior_kind == GE_RAMROM_GAMEPLAY_V6_ENTITY_EFFECT ||
                     prior_kind == GE_RAMROM_GAMEPLAY_V6_ENTITY_GLASS)) {
                    transient_collision = 1;
                    break;
                }
            }
            if (!transient_collision) {
                return GE_STATUS_ASSET_MISMATCH;
            }
        }
        if (event->category == GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_PROJECTILE) {
            projectile_count++;
        } else {
            effect_count++;
        }
    }
    for (index = 0u; index < state->entity_count; index++) {
        uint32_t kind = state->entities[index].entity_kind;
        if (kind != GE_RAMROM_GAMEPLAY_V6_ENTITY_PROJECTILE &&
            kind != GE_RAMROM_GAMEPLAY_V6_ENTITY_EFFECT &&
            kind != GE_RAMROM_GAMEPLAY_V6_ENTITY_GLASS) {
            base_count++;
        }
    }
    if (base_count > GE_RAMROM_GAMEPLAY_V6_MAX_ENTITIES - frame->event_count) {
        return GE_STATUS_TEXTURE_OVERFLOW;
    }

    {
        uint32_t write_index = 0u;
        for (index = 0u; index < state->entity_count; index++) {
            uint32_t kind = state->entities[index].entity_kind;
            if (kind != GE_RAMROM_GAMEPLAY_V6_ENTITY_PROJECTILE &&
                kind != GE_RAMROM_GAMEPLAY_V6_ENTITY_EFFECT &&
                kind != GE_RAMROM_GAMEPLAY_V6_ENTITY_GLASS) {
                if (write_index != index) {
                    state->entities[write_index] = state->entities[index];
                }
                write_index++;
            }
        }
        state->entity_count = write_index;
    }
    ge_gameplay_weapon_update_player(state, frame);
    for (index = 0u; index < frame->event_count; index++) {
        uint32_t kind;
        GERamRomGameplayEntityV6 *entity;
        const GERamRomWeaponEffectEventV6 *event = &frame->events[index];
        if (!ge_gameplay_weapon_entity_kind(event->category, &kind)) {
            continue;
        }
        entity = &state->entities[state->entity_count++];
        memset(entity, 0, sizeof(*entity));
        ge_gameplay_init_header(&entity->header, (uint32_t)sizeof(*entity));
        entity->record_version = GE_RAMROM_GAMEPLAY_V6_RECORD_VERSION;
        entity->entity_id = event->source_event_id;
        entity->entity_kind = kind;
        entity->flags = GE_RAMROM_GAMEPLAY_V6_ENTITY_ACTIVE |
                        GE_RAMROM_GAMEPLAY_V6_ENTITY_VISIBLE |
                        (frame->source_anchor != 0u ?
                            GE_RAMROM_GAMEPLAY_V6_ENTITY_SOURCE_ANCHOR :
                            GE_RAMROM_GAMEPLAY_V6_ENTITY_INTERPOLATED);
        if ((event->flags & GE_WEAPON_EFFECT_OWNER_V6_EVENT_ONE_SHOT_FLAG) != 0u) {
            entity->flags |= GE_RAMROM_GAMEPLAY_V6_ENTITY_ACTION;
        }
        entity->body_model_handle = event->resource_handle;
        entity->source_prop_type = event->category;
        entity->source_record_offset = event->source_offset;
        entity->source_aux0 = event->frame_index;
        entity->source_aux1 = event->source_sfx_id;
        entity->room_id = state->snapshot.current_room;
        entity->state = event->sequence;
        entity->action_state = event->flags;
        entity->visibility_mask = event->image_handle;
        entity->environment_rgba = event->colour_rgba;
        entity->fog_rgba = event->alpha_q16;
        entity->health = event->lifetime_q16;
        entity->max_health = event->envelope_q16;
        memcpy(entity->position_q16, event->position_q16, sizeof(entity->position_q16));
        memcpy(entity->velocity_q16, event->velocity_q16, sizeof(entity->velocity_q16));
        memcpy(entity->rotation_q16, event->rotation_q16, sizeof(entity->rotation_q16));
        memcpy(entity->scale_q16, event->scale_q16, sizeof(entity->scale_q16));
    }
    state->snapshot.entity_count = state->entity_count;
    state->snapshot.effect_count = effect_count;
    state->snapshot.projectile_count = projectile_count;
    state->snapshot.player_weapon = frame->hands[0].model_handle;
    state->snapshot.player_animation = frame->hands[0].animation_id;
    state->snapshot.hud_ammo = frame->right_magazine;
    state->snapshot.watch_state = frame->watch_visible != 0u ? frame->watch_model_handle : 0u;
    state->snapshot.fade_q16 = frame->fade_visible != 0u ? frame->fade_q16 : 0u;
    return GE_STATUS_OK;
}

static void ge_gameplay_mix_weapon_hashes(
    GERamRomGameplayStateV6 *state,
    const GERamRomWeaponEffectOwnerStateV6 *weapon_state,
    const GERamRomWeaponEffectEventRecordV6 *weapon_event)
{
    state->snapshot.render_hash ^= weapon_state->snapshot.render_hash;
    state->snapshot.audio_hash ^= weapon_event->event_hash;
    state->snapshot.state_hash = ge_ramrom_gameplay_v6_hash_snapshot(&state->snapshot) ^
                                 weapon_state->snapshot.state_hash ^
                                 weapon_event->event_hash;
    state->gameplay_hash = state->snapshot.state_hash;
}

static void ge_gameplay_weapon_mark_not_ready(
    GERamRomWeaponEffectOwnerStateV6 *weapon_state)
{
    weapon_state->flags &= ~GE_WEAPON_EFFECT_OWNER_V6_STATE_ACTIVE;
    weapon_state->flags |= GE_WEAPON_EFFECT_OWNER_V6_STATE_RESTORE_READY;
    weapon_state->owner_state = GE_WEAPON_EFFECT_OWNER_V6_OWNER_RESTORE_READY;
}

static void ge_gameplay_weapon_event_from_owner(
    const GERamRomGameplayStateV6 *state,
    const GERamRomWeaponEffectOwnerStateV6 *weapon_state,
    uint32_t owner_event_type,
    uint32_t owner_event_flags,
    GERamRomGameplayEventV6 *out_event)
{
    uint32_t flags = 0u;
    uint32_t event_type = GE_RAMROM_GAMEPLAY_V6_EVENT_STATE;
    if (owner_event_type == GE_WEAPON_EFFECT_OWNER_V6_EVENT_ABORT) {
        event_type = GE_RAMROM_GAMEPLAY_V6_EVENT_FADE;
        flags |= GE_RAMROM_GAMEPLAY_V6_EVENT_ABORTED_INPUT;
    } else if (owner_event_type == GE_WEAPON_EFFECT_OWNER_V6_EVENT_INSTALL) {
        event_type = GE_RAMROM_GAMEPLAY_V6_EVENT_INSTALL;
    } else if ((owner_event_flags & GE_WEAPON_EFFECT_OWNER_V6_EVENT_SOURCE_ANCHOR_FLAG) != 0u) {
        flags |= GE_RAMROM_GAMEPLAY_V6_EVENT_SOURCE_ANCHOR;
    }
    if ((owner_event_flags & GE_WEAPON_EFFECT_OWNER_V6_EVENT_INTERPOLATED) != 0u) {
        flags |= GE_RAMROM_GAMEPLAY_V6_EVENT_ODD_PAIRED_TICK;
    }
    if (owner_event_type == GE_WEAPON_EFFECT_OWNER_V6_EVENT_ONE_SHOT ||
        (owner_event_flags & GE_WEAPON_EFFECT_OWNER_V6_EVENT_ONE_SHOT_FLAG) != 0u) {
        flags |= GE_RAMROM_GAMEPLAY_V6_EVENT_ONE_SHOT;
        event_type = GE_RAMROM_GAMEPLAY_V6_EVENT_WEAPON;
    } else if (owner_event_type != GE_WEAPON_EFFECT_OWNER_V6_EVENT_ABORT &&
               owner_event_type != GE_WEAPON_EFFECT_OWNER_V6_EVENT_INSTALL &&
               weapon_state->render_frame.event_count != 0u) {
        event_type = GE_RAMROM_GAMEPLAY_V6_EVENT_EFFECT;
        flags |= GE_RAMROM_GAMEPLAY_V6_EVENT_CONTINUOUS;
    }
    ge_gameplay_init_event(state, event_type, flags, 0u, out_event);
    out_event->detail0 = weapon_state->render_frame.event_count;
    out_event->detail1 = owner_event_type;
    out_event->one_shot_sequence = weapon_state->one_shot_sequence;
    out_event->entity_count = state->entity_count;
    out_event->state_hash = state->snapshot.state_hash;
    out_event->event_hash = ge_ramrom_gameplay_v6_hash_event(out_event);
}

uint32_t ge_ramrom_gameplay_v6_weapon_effect_source_ready(
    const GERamRomWeaponEffectOwnerStateV6 *weapon_effect_state)
{
    if (weapon_effect_state == NULL ||
        ge_ramrom_weapon_effect_v6_validate_state(weapon_effect_state) != GE_STATUS_OK ||
        (weapon_effect_state->flags & GE_WEAPON_EFFECT_OWNER_V6_STATE_ACTIVE) == 0u ||
        weapon_effect_state->owner_state != GE_WEAPON_EFFECT_OWNER_V6_OWNER_RUNNING) {
        return 0u;
    }
    return 1u;
}

GEStatusV1 ge_ramrom_gameplay_v6_install_weapon_effect(
    GERamRomGameplayStateV6 *inout_state,
    const GERamRomWeaponEffectSetupV6 *setup,
    const GERamRomWeaponEffectFrameV6 *initial_frame,
    GERamRomWeaponEffectOwnerStateV6 *inout_weapon_effect_state,
    GERamRomGameplayEventV6 *out_event)
{
    GERamRomWeaponEffectEventRecordV6 owner_event;
    GEStatusV1 status;
    if (inout_state == NULL || setup == NULL || initial_frame == NULL ||
        inout_weapon_effect_state == NULL || out_event == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (ge_ramrom_gameplay_v6_validate_state(inout_state) != GE_STATUS_OK) {
        return GE_STATUS_INVALID_STATE;
    }
    if (inout_state->stage_id != setup->stage_id ||
        inout_state->demo_id == 0u ||
        (setup->demo_mask & (UINT32_C(1) << (inout_state->demo_id - 1u))) == 0u) {
        return GE_STATUS_ASSET_MISMATCH;
    }
    status = ge_ramrom_weapon_effect_v6_begin(
        inout_state->demo_id, setup, initial_frame,
        inout_weapon_effect_state, &owner_event);
    if (status != GE_STATUS_OK) {
        return status;
    }
    status = ge_gameplay_publish_weapon_entities(inout_state, inout_weapon_effect_state);
    if (status != GE_STATUS_OK) {
        ge_gameplay_weapon_mark_not_ready(inout_weapon_effect_state);
        return status;
    }
    ge_gameplay_mix_weapon_hashes(inout_state, inout_weapon_effect_state, &owner_event);
    ge_gameplay_weapon_event_from_owner(
        inout_state, inout_weapon_effect_state, owner_event.event_type,
        owner_event.flags, out_event);
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_gameplay_v6_step_with_weapon_effect(
    const uint8_t *bytes,
    uint32_t byte_count,
    uint64_t native_tick,
    GERamRomGameplayInputV6 input,
    const GERamRomWeaponEffectFrameV6 *source_frame,
    GERamRomWeaponEffectOwnerStateV6 *inout_weapon_effect_state,
    GERamRomGameplayStateV6 *inout_state,
    GERamRomGameplayEventV6 *out_gameplay_event,
    GERamRomWeaponEffectEventRecordV6 *out_weapon_effect_event)
{
    GEStatusV1 status;
    GERamRomWeaponEffectEventRecordV6 owner_event;
    int first_gameplay_tick;
    if (inout_state == NULL || inout_weapon_effect_state == NULL ||
        out_gameplay_event == NULL || out_weapon_effect_event == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (ge_ramrom_gameplay_v6_weapon_effect_source_ready(inout_weapon_effect_state) == 0u) {
        return GE_STATUS_UNSUPPORTED_COMMAND;
    }
    first_gameplay_tick = inout_state->native_tick == UINT64_MAX;
    if ((native_tick & 1u) == 0u && !first_gameplay_tick && source_frame == NULL) {
        return GE_STATUS_UNSUPPORTED_COMMAND;
    }
    if ((native_tick & 1u) == 0u && source_frame != NULL &&
        ge_ramrom_weapon_effect_v6_validate_frame(source_frame) != GE_STATUS_OK) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    status = ge_ramrom_gameplay_v6_step(
        bytes, byte_count, native_tick, input, inout_state, out_gameplay_event);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (first_gameplay_tick) {
        /* The owner was installed at source tick zero.  Do not consume the
           initial source frame twice; publish its already-copied anchor. */
        memset(&owner_event, 0, sizeof(owner_event));
        ge_gameplay_init_header(&owner_event.header, (uint32_t)sizeof(owner_event));
        owner_event.record_version = GE_WEAPON_EFFECT_OWNER_V6_RECORD_VERSION;
        owner_event.event_type = GE_WEAPON_EFFECT_OWNER_V6_EVENT_SOURCE_ANCHOR;
        owner_event.flags = GE_WEAPON_EFFECT_OWNER_V6_EVENT_SOURCE_ANCHOR_FLAG;
        owner_event.native_tick = 0u;
        owner_event.reference_tick = 0u;
        owner_event.pair_phase = 0u;
        owner_event.demo_id = inout_weapon_effect_state->demo_id;
        owner_event.stage_id = inout_weapon_effect_state->stage_id;
        owner_event.source_frame = inout_weapon_effect_state->render_frame.source_frame;
        owner_event.one_shot_sequence = inout_weapon_effect_state->one_shot_sequence;
        owner_event.event_count = inout_weapon_effect_state->render_frame.event_count;
        owner_event.source_hash = inout_weapon_effect_state->source_hash;
        owner_event.state_hash = inout_weapon_effect_state->snapshot.state_hash;
        owner_event.event_hash = ge_ramrom_weapon_effect_v6_hash_event(&owner_event);
    } else {
        status = ge_ramrom_weapon_effect_v6_step(
            native_tick, input, source_frame, inout_weapon_effect_state, &owner_event);
        if (status != GE_STATUS_OK) {
            return status;
        }
    }
    status = ge_gameplay_publish_weapon_entities(inout_state, inout_weapon_effect_state);
    if (status != GE_STATUS_OK) {
        ge_gameplay_weapon_mark_not_ready(inout_weapon_effect_state);
        return status;
    }
    ge_gameplay_mix_weapon_hashes(inout_state, inout_weapon_effect_state, &owner_event);
    *out_weapon_effect_event = owner_event;
    ge_gameplay_weapon_event_from_owner(
        inout_state, inout_weapon_effect_state, owner_event.event_type,
        owner_event.flags, out_gameplay_event);
    return GE_STATUS_OK;
}
