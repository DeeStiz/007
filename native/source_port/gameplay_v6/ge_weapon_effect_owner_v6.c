#include "ge_weapon_effect_owner_v6.h"

#include <limits.h>
#include <string.h>

#define GE_WEAPON_EFFECT_Q16_ONE ((int64_t)65536)
#define GE_WEAPON_EFFECT_Q16_HALF ((int64_t)32768)

static const uint64_t GE_WEAPON_EFFECT_FNV_OFFSET = UINT64_C(1469598103934665603);
static const uint64_t GE_WEAPON_EFFECT_FNV_PRIME = UINT64_C(1099511628211);
static const uint32_t GE_WEAPON_EFFECT_ALL_CATEGORIES =
    GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_MASK;
static const uint32_t GE_WEAPON_EFFECT_REQUIRED_SOURCE =
    GE_WEAPON_EFFECT_OWNER_V6_SOURCE_WEAPON_TABLE |
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

static uint64_t ge_weapon_effect_hash_byte(uint64_t hash, uint8_t value)
{
    return (hash ^ (uint64_t)value) * GE_WEAPON_EFFECT_FNV_PRIME;
}

static uint64_t ge_weapon_effect_hash_u32(uint64_t hash, uint32_t value)
{
    uint32_t shift;
    for (shift = 0u; shift < 32u; shift += 8u) {
        hash = ge_weapon_effect_hash_byte(hash, (uint8_t)(value >> shift));
    }
    return hash;
}

static uint64_t ge_weapon_effect_hash_u64(uint64_t hash, uint64_t value)
{
    uint32_t shift;
    for (shift = 0u; shift < 64u; shift += 8u) {
        hash = ge_weapon_effect_hash_byte(hash, (uint8_t)(value >> shift));
    }
    return hash;
}

static uint64_t ge_weapon_effect_hash_i32(uint64_t hash, int32_t value)
{
    return ge_weapon_effect_hash_u32(hash, (uint32_t)value);
}

static uint64_t ge_weapon_effect_hash_bytes(uint64_t hash,
                                            const uint8_t *bytes,
                                            size_t byte_count)
{
    size_t index;
    if (bytes == NULL && byte_count != 0u) {
        return 0u;
    }
    for (index = 0u; index < byte_count; index++) {
        hash = ge_weapon_effect_hash_byte(hash, bytes[index]);
    }
    return hash;
}

static void ge_weapon_effect_init_header(GEAbiHeaderV1 *header, uint32_t size)
{
    header->abi_version = GE_NATIVE_ABI_VERSION;
    header->struct_size = size;
}

static GEStatusV1 ge_weapon_effect_validate_common(const GEAbiHeaderV1 *header,
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
    if (record_version != GE_WEAPON_EFFECT_OWNER_V6_RECORD_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    return GE_STATUS_OK;
}

static uint32_t ge_weapon_effect_expected_stage(uint32_t demo_id)
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
    return demo_id == 0u || demo_id > (uint32_t)(sizeof(stages) / sizeof(stages[0]))
        ? GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_U32 : stages[demo_id - 1u];
}

static int ge_weapon_effect_q16_known(int32_t value)
{
    return value != GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_Q16;
}

static int ge_weapon_effect_vec3_known(const int32_t value[3])
{
    return ge_weapon_effect_q16_known(value[0]) &&
           ge_weapon_effect_q16_known(value[1]) &&
           ge_weapon_effect_q16_known(value[2]);
}

static int32_t ge_weapon_effect_clamp_i32(int64_t value)
{
    if (value > INT32_MAX) {
        return INT32_MAX;
    }
    if (value < (int64_t)INT32_MIN + 1) {
        return INT32_MIN + 1;
    }
    return (int32_t)value;
}

static int32_t ge_weapon_effect_lerp_i32(int32_t previous,
                                         int32_t current,
                                         int32_t weight_q16)
{
    int64_t delta = (int64_t)current - (int64_t)previous;
    return ge_weapon_effect_clamp_i32(
        (int64_t)previous +
        ((delta * (int64_t)weight_q16 + GE_WEAPON_EFFECT_Q16_HALF) /
         GE_WEAPON_EFFECT_Q16_ONE));
}

static int ge_weapon_effect_category_is_valid(uint32_t category)
{
    return category >= GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_MUZZLE &&
           category <= GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_MAX;
}

GEStatusV1 ge_ramrom_weapon_effect_v6_validate_setup(
    const GERamRomWeaponEffectSetupV6 *value)
{
    GEStatusV1 status;
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_weapon_effect_validate_common(&value->header,
                                              (uint32_t)sizeof(*value),
                                              value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->stage_id == 0u || value->demo_mask == 0u ||
        (value->flags & ~GE_WEAPON_EFFECT_REQUIRED_SOURCE) != 0u ||
        (value->flags & GE_WEAPON_EFFECT_REQUIRED_SOURCE) != GE_WEAPON_EFFECT_REQUIRED_SOURCE ||
        value->weapon_table_count == 0u || value->image_table_count == 0u ||
        value->sound_table_count == 0u || value->source_bytes == 0u ||
        value->source_setup_offset == GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_U32 ||
        value->weapon_table_offset == GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_U32 ||
        value->image_table_offset == GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_U32 ||
        value->sound_table_offset == GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_U32 ||
        value->initial_weapon_id == GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_U32 ||
        value->initial_weapon_model == GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_U32 ||
        value->initial_ammo_type == GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_U32 ||
        value->initial_magazine == GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_U32 ||
        value->initial_reserve == GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_U32 ||
        value->initial_health == GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_U32 ||
        value->source_hash == 0u || value->resource_hash == 0u ||
        value->weapon_table_hash == 0u || value->image_table_hash == 0u ||
        value->sound_table_hash == 0u || value->reserved0 != 0u ||
        value->reserved1 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_weapon_effect_v6_validate_hand(
    const GERamRomWeaponHandV6 *value)
{
    GEStatusV1 status;
    uint32_t index;
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_weapon_effect_validate_common(&value->header,
                                              (uint32_t)sizeof(*value),
                                              value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->hand_index >= GE_WEAPON_EFFECT_OWNER_V6_MAX_HANDS ||
        value->weapon_id == GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_U32 ||
        value->model_handle == GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_U32 ||
        value->ammo_type == GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_U32 ||
        value->action_state == GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_U32 ||
        value->firing_status > 1u || value->source_weapon_offset == GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_U32 ||
        value->source_stats_offset == GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_U32 ||
        value->source_transform_offset == GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_U32 ||
        value->source_matrix_handle == GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_U32 ||
        value->source_hash == 0u || value->resource_hash == 0u ||
        value->reserved0 != 0u || value->reserved1 != 0u ||
        !ge_weapon_effect_vec3_known(value->position_q16) ||
        !ge_weapon_effect_vec3_known(value->rotation_q16) ||
        !ge_weapon_effect_vec3_known(value->scale_q16) ||
        !ge_weapon_effect_vec3_known(value->muzzle_offset_q16)) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    for (index = 0u; index < 3u; index++) {
        if (value->scale_q16[index] <= 0) {
            return GE_STATUS_MALFORMED_STREAM;
        }
    }
    if (value->magazine_capacity != GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_U32 &&
        value->magazine > value->magazine_capacity) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_weapon_effect_v6_validate_event(
    const GERamRomWeaponEffectEventV6 *value)
{
    GEStatusV1 status;
    uint32_t index;
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_weapon_effect_validate_common(&value->header,
                                              (uint32_t)sizeof(*value),
                                              value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (!ge_weapon_effect_category_is_valid(value->category) ||
        (value->flags & ~GE_WEAPON_EFFECT_OWNER_V6_EVENT_MASK) != 0u ||
        value->source_event_id == 0u || value->source_reference_tick == UINT64_MAX ||
        value->source_offset == GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_U32 ||
        (value->frame_count == 0u && value->category != GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_SFX) ||
        (value->frame_count != 0u && value->frame_index >= value->frame_count) ||
        value->alpha_q16 > 65536u || value->lifetime_q16 == 0u ||
        value->source_hash == 0u || value->resource_hash == 0u ||
        value->reserved0 != 0u || value->reserved1 != 0u ||
        !ge_weapon_effect_vec3_known(value->position_q16) ||
        !ge_weapon_effect_vec3_known(value->velocity_q16) ||
        !ge_weapon_effect_vec3_known(value->rotation_q16) ||
        !ge_weapon_effect_vec3_known(value->scale_q16)) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    for (index = 0u; index < 3u; index++) {
        if (value->scale_q16[index] <= 0) {
            return GE_STATUS_MALFORMED_STREAM;
        }
    }
    if (value->resource_handle == 0u && value->category != GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_FADE &&
        value->category != GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_SFX) {
        return GE_STATUS_RESOURCE_NOT_FOUND;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_weapon_effect_v6_validate_frame(
    const GERamRomWeaponEffectFrameV6 *value)
{
    GEStatusV1 status;
    uint32_t index;
    uint32_t previous_sequence = 0u;
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_weapon_effect_validate_common(&value->header,
                                              (uint32_t)sizeof(*value),
                                              value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->demo_id == 0u || ge_weapon_effect_expected_stage(value->demo_id) != value->stage_id ||
        value->reference_tick != value->native_tick / 2u ||
        value->source_anchor > 1u || value->hand_count == 0u ||
        value->hand_count > GE_WEAPON_EFFECT_OWNER_V6_MAX_HANDS ||
        value->event_count > GE_WEAPON_EFFECT_OWNER_V6_MAX_EVENTS ||
        (value->flags & ~GE_WEAPON_EFFECT_OWNER_V6_FRAME_MASK) != 0u ||
        (value->source_present_mask | value->source_inactive_mask) != GE_WEAPON_EFFECT_ALL_CATEGORIES ||
        (value->source_present_mask & value->source_inactive_mask) != 0u ||
        value->source_hash == 0u || value->resource_hash == 0u ||
        value->reserved0 != 0u || value->reserved1 != 0u ||
        value->crosshair_x_q16 == GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_Q16 ||
        value->crosshair_y_q16 == GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_Q16) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    if (value->hud_visible != 0u) {
        if ((value->source_present_mask & GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_BIT(
                GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_HUD)) == 0u ||
            value->right_hud_image_handle == 0u) {
            return GE_STATUS_RESOURCE_NOT_FOUND;
        }
    }
    if (value->sight_visible != 0u &&
        (value->source_present_mask & GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_BIT(
            GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_SIGHT)) == 0u) {
        return GE_STATUS_RESOURCE_NOT_FOUND;
    }
    if (value->watch_visible != 0u &&
        (value->watch_model_handle == 0u || value->watch_scale_q16 <= 0 ||
         (value->source_present_mask & GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_BIT(
             GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_WATCH)) == 0u)) {
        return GE_STATUS_RESOURCE_NOT_FOUND;
    }
    if (value->fade_visible != 0u &&
        (value->fade_q16 > 65536u || value->fade_duration_q16 == 0u ||
         value->fade_elapsed_q16 > value->fade_duration_q16 ||
         (value->source_present_mask & GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_BIT(
             GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_FADE)) == 0u)) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    for (index = 0u; index < value->hand_count; index++) {
        if (ge_ramrom_weapon_effect_v6_validate_hand(&value->hands[index]) != GE_STATUS_OK ||
            value->hands[index].hand_index != index) {
            return GE_STATUS_MALFORMED_STREAM;
        }
    }
    for (index = 0u; index < value->event_count; index++) {
        const GERamRomWeaponEffectEventV6 *event = &value->events[index];
        if (ge_ramrom_weapon_effect_v6_validate_event(event) != GE_STATUS_OK ||
            event->source_reference_tick != value->reference_tick ||
            event->sequence < previous_sequence ||
            (value->source_present_mask & GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_BIT(event->category)) == 0u) {
            return GE_STATUS_MALFORMED_STREAM;
        }
        previous_sequence = event->sequence;
    }
    if (value->frame_hash != 0u && ge_ramrom_weapon_effect_v6_hash_frame(value) != value->frame_hash) {
        return GE_STATUS_ASSET_MISMATCH;
    }
    return GE_STATUS_OK;
}

uint64_t ge_ramrom_weapon_effect_v6_hash_frame(
    const GERamRomWeaponEffectFrameV6 *value)
{
    uint64_t hash = GE_WEAPON_EFFECT_FNV_OFFSET;
    uint32_t index;
    if (value == NULL) {
        return 0u;
    }
    hash = ge_weapon_effect_hash_u32(hash, value->flags);
    hash = ge_weapon_effect_hash_u32(hash, value->demo_id);
    hash = ge_weapon_effect_hash_u32(hash, value->stage_id);
    hash = ge_weapon_effect_hash_u64(hash, value->native_tick);
    hash = ge_weapon_effect_hash_u64(hash, value->reference_tick);
    hash = ge_weapon_effect_hash_u32(hash, value->source_anchor);
    hash = ge_weapon_effect_hash_u32(hash, value->source_frame);
    hash = ge_weapon_effect_hash_u32(hash, value->source_present_mask);
    hash = ge_weapon_effect_hash_u32(hash, value->source_inactive_mask);
    hash = ge_weapon_effect_hash_u32(hash, value->one_shot_sequence);
    hash = ge_weapon_effect_hash_u32(hash, value->hand_count);
    hash = ge_weapon_effect_hash_u32(hash, value->event_count);
    hash = ge_weapon_effect_hash_u32(hash, value->hud_visible);
    hash = ge_weapon_effect_hash_i32(hash, value->view_left_q16);
    hash = ge_weapon_effect_hash_i32(hash, value->view_top_q16);
    hash = ge_weapon_effect_hash_u32(hash, value->view_width_q16);
    hash = ge_weapon_effect_hash_u32(hash, value->view_height_q16);
    hash = ge_weapon_effect_hash_u32(hash, value->right_hud_image_handle);
    hash = ge_weapon_effect_hash_u32(hash, value->left_hud_image_handle);
    hash = ge_weapon_effect_hash_u32(hash, value->right_hud_width);
    hash = ge_weapon_effect_hash_u32(hash, value->right_hud_height);
    hash = ge_weapon_effect_hash_u32(hash, value->left_hud_width);
    hash = ge_weapon_effect_hash_u32(hash, value->left_hud_height);
    hash = ge_weapon_effect_hash_u32(hash, value->right_ammo_type);
    hash = ge_weapon_effect_hash_u32(hash, value->right_magazine);
    hash = ge_weapon_effect_hash_u32(hash, value->right_reserve);
    hash = ge_weapon_effect_hash_u32(hash, value->left_ammo_type);
    hash = ge_weapon_effect_hash_u32(hash, value->left_magazine);
    hash = ge_weapon_effect_hash_u32(hash, value->left_reserve);
    hash = ge_weapon_effect_hash_i32(hash, value->crosshair_x_q16);
    hash = ge_weapon_effect_hash_i32(hash, value->crosshair_y_q16);
    hash = ge_weapon_effect_hash_u32(hash, value->crosshair_image_handle);
    hash = ge_weapon_effect_hash_u32(hash, value->sight_visible);
    hash = ge_weapon_effect_hash_u32(hash, value->watch_visible);
    hash = ge_weapon_effect_hash_u32(hash, value->watch_model_handle);
    hash = ge_weapon_effect_hash_u32(hash, value->watch_animate_buttons);
    hash = ge_weapon_effect_hash_u32(hash, value->watch_controller_pad);
    hash = ge_weapon_effect_hash_bytes(hash, (const uint8_t *)value->watch_position_q16,
                                       sizeof(value->watch_position_q16));
    hash = ge_weapon_effect_hash_i32(hash, value->watch_scale_q16);
    hash = ge_weapon_effect_hash_u32(hash, value->watch_animation_frame);
    hash = ge_weapon_effect_hash_u32(hash, value->fade_visible);
    hash = ge_weapon_effect_hash_u32(hash, value->fade_colour_rgba);
    hash = ge_weapon_effect_hash_u32(hash, value->fade_q16);
    hash = ge_weapon_effect_hash_u32(hash, value->fade_elapsed_q16);
    hash = ge_weapon_effect_hash_u32(hash, value->fade_duration_q16);
    hash = ge_weapon_effect_hash_u64(hash, value->source_hash);
    hash = ge_weapon_effect_hash_u64(hash, value->resource_hash);
    for (index = 0u; index < value->hand_count; index++) {
        const GERamRomWeaponHandV6 *hand = &value->hands[index];
        hash = ge_weapon_effect_hash_u32(hash, hand->hand_index);
        hash = ge_weapon_effect_hash_u32(hash, hand->weapon_id);
        hash = ge_weapon_effect_hash_u32(hash, hand->model_handle);
        hash = ge_weapon_effect_hash_u32(hash, hand->ammo_type);
        hash = ge_weapon_effect_hash_u32(hash, hand->magazine);
        hash = ge_weapon_effect_hash_u32(hash, hand->reserve);
        hash = ge_weapon_effect_hash_u32(hash, hand->action_state);
        hash = ge_weapon_effect_hash_u32(hash, hand->firing_status);
        hash = ge_weapon_effect_hash_u32(hash, hand->animation_id);
        hash = ge_weapon_effect_hash_i32(hash, hand->animation_frame_q16);
        hash = ge_weapon_effect_hash_i32(hash, hand->animation_rate_q16);
        hash = ge_weapon_effect_hash_u32(hash, hand->source_weapon_offset);
        hash = ge_weapon_effect_hash_u32(hash, hand->source_stats_offset);
        hash = ge_weapon_effect_hash_u32(hash, hand->source_transform_offset);
        hash = ge_weapon_effect_hash_u32(hash, hand->source_matrix_handle);
        hash = ge_weapon_effect_hash_bytes(hash, (const uint8_t *)hand->position_q16,
                                           sizeof(hand->position_q16));
        hash = ge_weapon_effect_hash_bytes(hash, (const uint8_t *)hand->rotation_q16,
                                           sizeof(hand->rotation_q16));
        hash = ge_weapon_effect_hash_bytes(hash, (const uint8_t *)hand->scale_q16,
                                           sizeof(hand->scale_q16));
        hash = ge_weapon_effect_hash_bytes(hash, (const uint8_t *)hand->muzzle_offset_q16,
                                           sizeof(hand->muzzle_offset_q16));
        hash = ge_weapon_effect_hash_u64(hash, hand->source_hash);
        hash = ge_weapon_effect_hash_u64(hash, hand->resource_hash);
    }
    for (index = 0u; index < value->event_count; index++) {
        const GERamRomWeaponEffectEventV6 *event = &value->events[index];
        hash = ge_weapon_effect_hash_u32(hash, event->category);
        hash = ge_weapon_effect_hash_u32(hash, event->flags);
        hash = ge_weapon_effect_hash_u32(hash, event->source_event_id);
        hash = ge_weapon_effect_hash_u32(hash, event->resource_handle);
        hash = ge_weapon_effect_hash_u32(hash, event->source_resource_id);
        hash = ge_weapon_effect_hash_u32(hash, event->image_handle);
        hash = ge_weapon_effect_hash_u32(hash, event->source_sfx_id);
        hash = ge_weapon_effect_hash_u64(hash, event->source_reference_tick);
        hash = ge_weapon_effect_hash_u32(hash, event->sequence);
        hash = ge_weapon_effect_hash_u32(hash, event->source_offset);
        hash = ge_weapon_effect_hash_u32(hash, event->frame_index);
        hash = ge_weapon_effect_hash_u32(hash, event->frame_count);
        hash = ge_weapon_effect_hash_bytes(hash, (const uint8_t *)event->position_q16,
                                           sizeof(event->position_q16));
        hash = ge_weapon_effect_hash_bytes(hash, (const uint8_t *)event->velocity_q16,
                                           sizeof(event->velocity_q16));
        hash = ge_weapon_effect_hash_bytes(hash, (const uint8_t *)event->rotation_q16,
                                           sizeof(event->rotation_q16));
        hash = ge_weapon_effect_hash_bytes(hash, (const uint8_t *)event->scale_q16,
                                           sizeof(event->scale_q16));
        hash = ge_weapon_effect_hash_i32(hash, event->gravity_q16);
        hash = ge_weapon_effect_hash_u32(hash, event->colour_rgba);
        hash = ge_weapon_effect_hash_u32(hash, event->alpha_q16);
        hash = ge_weapon_effect_hash_u32(hash, event->lifetime_q16);
        hash = ge_weapon_effect_hash_u32(hash, event->envelope_q16);
        hash = ge_weapon_effect_hash_u64(hash, event->source_hash);
        hash = ge_weapon_effect_hash_u64(hash, event->resource_hash);
    }
    return hash;
}

GEStatusV1 ge_ramrom_weapon_effect_v6_validate_snapshot(
    const GERamRomWeaponEffectSnapshotV6 *value)
{
    GEStatusV1 status;
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_weapon_effect_validate_common(&value->header,
                                              (uint32_t)sizeof(*value),
                                              value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->pair_phase > 1u || value->source_anchor > 1u ||
        value->hand_count > GE_WEAPON_EFFECT_OWNER_V6_MAX_HANDS ||
        value->event_count > GE_WEAPON_EFFECT_OWNER_V6_MAX_EVENTS ||
        value->fade_q16 > 65536u || value->source_hash == 0u ||
        value->resource_hash == 0u || value->state_hash == 0u ||
        value->render_hash == 0u || value->reserved0 != 0u || value->reserved1 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_weapon_effect_v6_validate_state(
    const GERamRomWeaponEffectOwnerStateV6 *value)
{
    GEStatusV1 status;
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_weapon_effect_validate_common(&value->header,
                                              (uint32_t)sizeof(*value),
                                              value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if ((value->flags & ~GE_WEAPON_EFFECT_OWNER_V6_STATE_MASK) != 0u ||
        value->owner_state > GE_WEAPON_EFFECT_OWNER_V6_STATE_RESTORE_READY ||
        value->pair_phase > 1u || value->source_hash == 0u ||
        value->setup_hash == 0u || value->resource_hash == 0u ||
        value->state_hash == 0u ||
        ge_ramrom_weapon_effect_v6_validate_setup(&value->setup) != GE_STATUS_OK ||
        ge_ramrom_weapon_effect_v6_validate_frame(&value->previous_anchor) != GE_STATUS_OK ||
        ge_ramrom_weapon_effect_v6_validate_frame(&value->current_anchor) != GE_STATUS_OK ||
        ge_ramrom_weapon_effect_v6_validate_frame(&value->render_frame) != GE_STATUS_OK ||
        ge_ramrom_weapon_effect_v6_validate_snapshot(&value->snapshot) != GE_STATUS_OK) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

uint64_t ge_ramrom_weapon_effect_v6_hash_event(
    const GERamRomWeaponEffectEventRecordV6 *value)
{
    uint64_t hash = GE_WEAPON_EFFECT_FNV_OFFSET;
    if (value == NULL) {
        return 0u;
    }
    hash = ge_weapon_effect_hash_u32(hash, value->event_type);
    hash = ge_weapon_effect_hash_u32(hash, value->flags);
    hash = ge_weapon_effect_hash_u32(hash, value->diagnostic_code);
    hash = ge_weapon_effect_hash_u64(hash, value->native_tick);
    hash = ge_weapon_effect_hash_u64(hash, value->reference_tick);
    hash = ge_weapon_effect_hash_u32(hash, value->pair_phase);
    hash = ge_weapon_effect_hash_u32(hash, value->demo_id);
    hash = ge_weapon_effect_hash_u32(hash, value->stage_id);
    hash = ge_weapon_effect_hash_u32(hash, value->source_frame);
    hash = ge_weapon_effect_hash_u32(hash, value->one_shot_sequence);
    hash = ge_weapon_effect_hash_u32(hash, value->event_count);
    hash = ge_weapon_effect_hash_u32(hash, value->first_event_id);
    hash = ge_weapon_effect_hash_u32(hash, value->last_event_id);
    hash = ge_weapon_effect_hash_u64(hash, value->source_hash);
    hash = ge_weapon_effect_hash_u64(hash, value->state_hash);
    return hash;
}

static void ge_weapon_effect_refresh_snapshot(
    GERamRomWeaponEffectOwnerStateV6 *state)
{
    const GERamRomWeaponEffectFrameV6 *frame = &state->render_frame;
    GERamRomWeaponEffectSnapshotV6 *snapshot = &state->snapshot;
    memset(snapshot, 0, sizeof(*snapshot));
    ge_weapon_effect_init_header(&snapshot->header, (uint32_t)sizeof(*snapshot));
    snapshot->record_version = GE_WEAPON_EFFECT_OWNER_V6_RECORD_VERSION;
    snapshot->flags = state->flags;
    snapshot->demo_id = state->demo_id;
    snapshot->stage_id = state->stage_id;
    snapshot->native_tick = frame->native_tick;
    snapshot->reference_tick = frame->reference_tick;
    snapshot->pair_phase = frame->source_anchor == 0u ? 1u : 0u;
    snapshot->source_anchor = frame->source_anchor;
    snapshot->source_frame = frame->source_frame;
    snapshot->one_shot_sequence = frame->one_shot_sequence;
    snapshot->hand_count = frame->hand_count;
    snapshot->event_count = frame->event_count;
    snapshot->right_weapon_id = frame->hands[0].weapon_id;
    snapshot->right_model_handle = frame->hands[0].model_handle;
    snapshot->right_ammo_type = frame->right_ammo_type;
    snapshot->right_magazine = frame->right_magazine;
    snapshot->right_reserve = frame->right_reserve;
    snapshot->hud_visible = frame->hud_visible;
    snapshot->sight_visible = frame->sight_visible;
    snapshot->crosshair_x_q16 = frame->crosshair_x_q16;
    snapshot->crosshair_y_q16 = frame->crosshair_y_q16;
    snapshot->watch_visible = frame->watch_visible;
    snapshot->watch_model_handle = frame->watch_model_handle;
    snapshot->fade_visible = frame->fade_visible;
    snapshot->fade_q16 = frame->fade_q16;
    snapshot->source_hash = frame->source_hash;
    snapshot->resource_hash = frame->resource_hash;
    snapshot->state_hash = ge_ramrom_weapon_effect_v6_hash_frame(frame);
    snapshot->render_hash = snapshot->state_hash;
    state->state_hash = snapshot->state_hash;
    state->render_frame.frame_hash = snapshot->render_hash;
}

static void ge_weapon_effect_init_event(
    const GERamRomWeaponEffectOwnerStateV6 *state,
    uint32_t event_type,
    uint32_t flags,
    uint32_t diagnostic_code,
    GERamRomWeaponEffectEventRecordV6 *event)
{
    memset(event, 0, sizeof(*event));
    ge_weapon_effect_init_header(&event->header, (uint32_t)sizeof(*event));
    event->record_version = GE_WEAPON_EFFECT_OWNER_V6_RECORD_VERSION;
    event->event_type = event_type;
    event->flags = flags;
    event->diagnostic_code = diagnostic_code;
    event->native_tick = state->native_tick;
    event->reference_tick = state->reference_tick;
    event->pair_phase = state->pair_phase;
    event->demo_id = state->demo_id;
    event->stage_id = state->stage_id;
    event->source_frame = state->render_frame.source_frame;
    event->one_shot_sequence = state->one_shot_sequence;
    event->event_count = state->render_frame.event_count;
    if (state->render_frame.event_count != 0u) {
        event->first_event_id = state->render_frame.events[0].source_event_id;
        event->last_event_id = state->render_frame.events[state->render_frame.event_count - 1u].source_event_id;
    }
    event->source_hash = state->source_hash;
    event->state_hash = state->state_hash;
    event->event_hash = ge_ramrom_weapon_effect_v6_hash_event(event);
}

static void ge_weapon_effect_interpolate_frame(
    const GERamRomWeaponEffectFrameV6 *previous,
    const GERamRomWeaponEffectFrameV6 *current,
    uint64_t native_tick,
    GERamRomWeaponEffectFrameV6 *out)
{
    uint32_t index;
    *out = *current;
    out->flags = GE_WEAPON_EFFECT_OWNER_V6_FRAME_INTERPOLATED |
                 (current->hud_visible != 0u ? GE_WEAPON_EFFECT_OWNER_V6_FRAME_HAS_HUD : 0u) |
                 (current->sight_visible != 0u ? GE_WEAPON_EFFECT_OWNER_V6_FRAME_HAS_SIGHT : 0u) |
                 (current->watch_visible != 0u ? GE_WEAPON_EFFECT_OWNER_V6_FRAME_HAS_WATCH : 0u) |
                 (current->fade_visible != 0u ? GE_WEAPON_EFFECT_OWNER_V6_FRAME_HAS_FADE : 0u);
    out->native_tick = native_tick;
    out->reference_tick = native_tick / 2u;
    out->source_anchor = 0u;
    out->source_frame = current->source_frame;
    out->crosshair_x_q16 = ge_weapon_effect_lerp_i32(previous->crosshair_x_q16,
                                                      current->crosshair_x_q16, 32768);
    out->crosshair_y_q16 = ge_weapon_effect_lerp_i32(previous->crosshair_y_q16,
                                                      current->crosshair_y_q16, 32768);
    out->watch_scale_q16 = ge_weapon_effect_lerp_i32(previous->watch_scale_q16,
                                                      current->watch_scale_q16, 32768);
    out->fade_q16 = (uint32_t)ge_weapon_effect_lerp_i32((int32_t)previous->fade_q16,
                                                        (int32_t)current->fade_q16, 32768);
    out->fade_elapsed_q16 = (uint32_t)ge_weapon_effect_lerp_i32(
        (int32_t)previous->fade_elapsed_q16, (int32_t)current->fade_elapsed_q16, 32768);
    for (index = 0u; index < 3u; index++) {
        out->watch_position_q16[index] = ge_weapon_effect_lerp_i32(
            previous->watch_position_q16[index], current->watch_position_q16[index], 32768);
    }
    for (index = 0u; index < current->hand_count; index++) {
        uint32_t axis;
        const GERamRomWeaponHandV6 *a = &previous->hands[index];
        const GERamRomWeaponHandV6 *b = &current->hands[index];
        GERamRomWeaponHandV6 *v = &out->hands[index];
        v->animation_frame_q16 = ge_weapon_effect_lerp_i32(a->animation_frame_q16,
                                                            b->animation_frame_q16, 32768);
        for (axis = 0u; axis < 3u; axis++) {
            v->position_q16[axis] = ge_weapon_effect_lerp_i32(a->position_q16[axis], b->position_q16[axis], 32768);
            v->rotation_q16[axis] = ge_weapon_effect_lerp_i32(a->rotation_q16[axis], b->rotation_q16[axis], 32768);
            v->scale_q16[axis] = ge_weapon_effect_lerp_i32(a->scale_q16[axis], b->scale_q16[axis], 32768);
            v->muzzle_offset_q16[axis] = ge_weapon_effect_lerp_i32(a->muzzle_offset_q16[axis], b->muzzle_offset_q16[axis], 32768);
        }
    }
    for (index = 0u; index < current->event_count; index++) {
        uint32_t axis;
        const GERamRomWeaponEffectEventV6 *a = index < previous->event_count ? &previous->events[index] : &current->events[index];
        const GERamRomWeaponEffectEventV6 *b = &current->events[index];
        GERamRomWeaponEffectEventV6 *v = &out->events[index];
        v->flags &= ~GE_WEAPON_EFFECT_OWNER_V6_EVENT_SOURCE_ANCHOR_FLAG;
        v->flags |= GE_WEAPON_EFFECT_OWNER_V6_EVENT_INTERPOLATED;
        for (axis = 0u; axis < 3u; axis++) {
            v->position_q16[axis] = ge_weapon_effect_lerp_i32(a->position_q16[axis], b->position_q16[axis], 32768);
            v->velocity_q16[axis] = ge_weapon_effect_lerp_i32(a->velocity_q16[axis], b->velocity_q16[axis], 32768);
            v->rotation_q16[axis] = ge_weapon_effect_lerp_i32(a->rotation_q16[axis], b->rotation_q16[axis], 32768);
            v->scale_q16[axis] = ge_weapon_effect_lerp_i32(a->scale_q16[axis], b->scale_q16[axis], 32768);
        }
        v->alpha_q16 = (uint32_t)ge_weapon_effect_lerp_i32((int32_t)a->alpha_q16,
                                                            (int32_t)b->alpha_q16, 32768);
        v->envelope_q16 = (uint32_t)ge_weapon_effect_lerp_i32((int32_t)a->envelope_q16,
                                                               (int32_t)b->envelope_q16, 32768);
    }
    out->frame_hash = 0u;
    out->frame_hash = ge_ramrom_weapon_effect_v6_hash_frame(out);
}

GEStatusV1 ge_ramrom_weapon_effect_v6_begin(
    uint32_t demo_id,
    const GERamRomWeaponEffectSetupV6 *setup,
    const GERamRomWeaponEffectFrameV6 *initial_frame,
    GERamRomWeaponEffectOwnerStateV6 *out_state,
    GERamRomWeaponEffectEventRecordV6 *out_event)
{
    GEStatusV1 status;
    if (setup == NULL || initial_frame == NULL || out_state == NULL || out_event == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_ramrom_weapon_effect_v6_validate_setup(setup);
    if (status != GE_STATUS_OK) {
        return status;
    }
    status = ge_ramrom_weapon_effect_v6_validate_frame(initial_frame);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (demo_id == 0u || demo_id > GE_RAMROM_V5_DEMO_COUNT ||
        setup->stage_id != ge_weapon_effect_expected_stage(demo_id) ||
        initial_frame->demo_id != demo_id || initial_frame->stage_id != setup->stage_id ||
        (setup->demo_mask & (UINT32_C(1) << (demo_id - 1u))) == 0u ||
        initial_frame->native_tick != 0u || initial_frame->source_anchor == 0u) {
        return GE_STATUS_ASSET_MISMATCH;
    }
    memset(out_state, 0, sizeof(*out_state));
    ge_weapon_effect_init_header(&out_state->header, (uint32_t)sizeof(*out_state));
    out_state->record_version = GE_WEAPON_EFFECT_OWNER_V6_RECORD_VERSION;
    out_state->flags = GE_WEAPON_EFFECT_OWNER_V6_STATE_ACTIVE |
                       GE_WEAPON_EFFECT_OWNER_V6_STATE_SOURCE_ANCHOR;
    out_state->owner_state = GE_WEAPON_EFFECT_OWNER_V6_OWNER_RUNNING;
    out_state->demo_id = demo_id;
    out_state->stage_id = setup->stage_id;
    out_state->native_tick = 0u;
    out_state->reference_tick = 0u;
    out_state->pair_phase = 0u;
    out_state->source_anchor_count = 1u;
    out_state->one_shot_sequence = initial_frame->one_shot_sequence;
    out_state->source_hash = setup->source_hash;
    out_state->setup_hash = setup->source_hash;
    out_state->resource_hash = setup->resource_hash;
    out_state->setup = *setup;
    out_state->previous_anchor = *initial_frame;
    out_state->current_anchor = *initial_frame;
    out_state->render_frame = *initial_frame;
    ge_weapon_effect_refresh_snapshot(out_state);
    ge_weapon_effect_init_event(out_state, GE_WEAPON_EFFECT_OWNER_V6_EVENT_INSTALL,
                                GE_WEAPON_EFFECT_OWNER_V6_EVENT_SOURCE_ANCHOR_FLAG,
                                0u, out_event);
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_weapon_effect_v6_step(
    uint64_t native_tick,
    GERamRomGameplayInputV6 input,
    const GERamRomWeaponEffectFrameV6 *source_frame,
    GERamRomWeaponEffectOwnerStateV6 *inout_state,
    GERamRomWeaponEffectEventRecordV6 *out_event)
{
    GEStatusV1 status;
    uint64_t expected_tick;
    if (inout_state == NULL || out_event == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_ramrom_weapon_effect_v6_validate_state(inout_state);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (input.header.abi_version != GE_NATIVE_ABI_VERSION ||
        input.header.struct_size != sizeof(input) ||
        input.record_version != GE_RAMROM_GAMEPLAY_V6_RECORD_VERSION ||
        input.controller_count == 0u || input.controller_count > 4u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    expected_tick = inout_state->native_tick + 1u;
    if (native_tick != expected_tick) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    inout_state->native_tick = native_tick;
    inout_state->reference_tick = native_tick / 2u;
    inout_state->pair_phase = (uint32_t)(native_tick & 1u);
    if ((input.flags & GE_RAMROM_GAMEPLAY_V6_INPUT_REAL) != 0u &&
        (input.pressed_buttons != 0u || input.held_buttons != 0u || input.released_buttons != 0u)) {
        inout_state->flags &= ~GE_WEAPON_EFFECT_OWNER_V6_STATE_ACTIVE;
        inout_state->flags |= GE_WEAPON_EFFECT_OWNER_V6_STATE_ABORTING;
        inout_state->owner_state = GE_WEAPON_EFFECT_OWNER_V6_OWNER_ABORTING;
        ge_weapon_effect_init_event(inout_state, GE_WEAPON_EFFECT_OWNER_V6_EVENT_ABORT,
                                    GE_WEAPON_EFFECT_OWNER_V6_EVENT_SOURCE_ANCHOR_FLAG,
                                    input.pressed_buttons | input.held_buttons | input.released_buttons,
                                    out_event);
        return GE_STATUS_OK;
    }
    if (inout_state->pair_phase == 1u) {
        ge_weapon_effect_interpolate_frame(&inout_state->previous_anchor,
                                           &inout_state->current_anchor,
                                           native_tick, &inout_state->render_frame);
        inout_state->flags &= ~GE_WEAPON_EFFECT_OWNER_V6_STATE_SOURCE_ANCHOR;
        inout_state->flags |= GE_WEAPON_EFFECT_OWNER_V6_STATE_INTERPOLATED;
        ge_weapon_effect_refresh_snapshot(inout_state);
        ge_weapon_effect_init_event(inout_state, GE_WEAPON_EFFECT_OWNER_V6_EVENT_INTERPOLANT,
                                    GE_WEAPON_EFFECT_OWNER_V6_EVENT_INTERPOLATED,
                                    0u, out_event);
    } else {
        if (source_frame == NULL) {
            return GE_STATUS_UNSUPPORTED_COMMAND;
        }
        status = ge_ramrom_weapon_effect_v6_validate_frame(source_frame);
        if (status != GE_STATUS_OK) {
            return status;
        }
        if (source_frame->demo_id != inout_state->demo_id ||
            source_frame->stage_id != inout_state->stage_id ||
            source_frame->native_tick != native_tick || source_frame->source_anchor == 0u ||
            source_frame->one_shot_sequence < inout_state->one_shot_sequence) {
            return GE_STATUS_ASSET_MISMATCH;
        }
        inout_state->previous_anchor = inout_state->current_anchor;
        inout_state->current_anchor = *source_frame;
        inout_state->render_frame = *source_frame;
        inout_state->source_anchor_count++;
        inout_state->one_shot_sequence = source_frame->one_shot_sequence;
        inout_state->source_hash = source_frame->source_hash;
        inout_state->resource_hash = source_frame->resource_hash;
        inout_state->flags &= ~GE_WEAPON_EFFECT_OWNER_V6_STATE_INTERPOLATED;
        inout_state->flags |= GE_WEAPON_EFFECT_OWNER_V6_STATE_SOURCE_ANCHOR;
        ge_weapon_effect_refresh_snapshot(inout_state);
        {
            uint32_t index;
            uint32_t one_shot = 0u;
            for (index = 0u; index < source_frame->event_count; index++) {
                if ((source_frame->events[index].flags & GE_WEAPON_EFFECT_OWNER_V6_EVENT_ONE_SHOT_FLAG) != 0u) {
                    one_shot = 1u;
                    break;
                }
            }
            ge_weapon_effect_init_event(inout_state,
                                        one_shot != 0u ? GE_WEAPON_EFFECT_OWNER_V6_EVENT_ONE_SHOT :
                                            GE_WEAPON_EFFECT_OWNER_V6_EVENT_SOURCE_ANCHOR,
                                        GE_WEAPON_EFFECT_OWNER_V6_EVENT_SOURCE_ANCHOR_FLAG |
                                            (one_shot != 0u ? GE_WEAPON_EFFECT_OWNER_V6_EVENT_ONE_SHOT_FLAG : 0u),
                                        0u, out_event);
        }
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_weapon_effect_v6_copy_snapshot(
    const GERamRomWeaponEffectOwnerStateV6 *state,
    GERamRomWeaponEffectSnapshotV6 *out_snapshot)
{
    if (state == NULL || out_snapshot == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    *out_snapshot = state->snapshot;
    return ge_ramrom_weapon_effect_v6_validate_snapshot(out_snapshot);
}

GEStatusV1 ge_ramrom_weapon_effect_v6_copy_frame(
    const GERamRomWeaponEffectOwnerStateV6 *state,
    GERamRomWeaponEffectFrameV6 *out_frame)
{
    if (state == NULL || out_frame == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    *out_frame = state->render_frame;
    return ge_ramrom_weapon_effect_v6_validate_frame(out_frame);
}

GEStatusV1 ge_ramrom_weapon_effect_v6_copy_events(
    const GERamRomWeaponEffectOwnerStateV6 *state,
    uint32_t first_item,
    uint32_t capacity,
    GERamRomWeaponEffectEventV6 *out_items,
    uint32_t *out_copied)
{
    uint32_t count;
    if (state == NULL || out_copied == NULL ||
        (capacity != 0u && out_items == NULL) ||
        first_item > state->render_frame.event_count ||
        capacity > GE_WEAPON_EFFECT_OWNER_V6_MAX_EVENTS) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    count = state->render_frame.event_count - first_item;
    if (count > capacity) {
        count = capacity;
    }
    if (count != 0u) {
        memcpy(out_items, &state->render_frame.events[first_item],
               sizeof(*out_items) * (size_t)count);
    }
    *out_copied = count;
    return GE_STATUS_OK;
}
