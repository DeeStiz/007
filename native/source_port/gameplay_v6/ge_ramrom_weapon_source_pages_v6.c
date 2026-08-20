#include "ge_ramrom_weapon_source_pages_v6.h"

#include <string.h>

static void ge_weapon_source_init_header(GEAbiHeaderV1 *header, uint32_t size)
{
    header->abi_version = GE_NATIVE_ABI_VERSION;
    header->struct_size = size;
}

GEStatusV1 ge_ramrom_weapon_source_pages_v6_validate_map(
    const GERamRomWeaponSourceMapRowV6 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (value->header.abi_version != GE_NATIVE_ABI_VERSION ||
        value->header.struct_size != sizeof(*value) ||
        value->record_version != GE_RAMROM_WEAPON_SOURCE_PAGES_V6_RECORD_VERSION ||
        value->item_id == GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_U32 ||
        value->model_handle == 0u || value->resource_handle == 0u ||
        value->source_weapon_offset == GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_U32 ||
        value->source_stats_offset == GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_U32 ||
        value->source_transform_offset == GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_U32 ||
        value->source_matrix_handle == GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_U32 ||
        value->source_hash == 0u || value->resource_hash == 0u ||
        value->reserved0 != 0u || value->reserved1 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_weapon_source_pages_v6_validate_page(
    const GERamRomWeaponSourcePageV6 *value)
{
    uint32_t axis;
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (value->header.abi_version != GE_NATIVE_ABI_VERSION ||
        value->header.struct_size != sizeof(*value) ||
        value->record_version != GE_RAMROM_WEAPON_SOURCE_PAGES_V6_RECORD_VERSION ||
        value->item_id == GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_U32 ||
        value->firing_status > 1u ||
        value->source_weapon_offset == GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_U32 ||
        value->source_stats_offset == GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_U32 ||
        value->source_transform_offset == GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_U32 ||
        value->source_matrix_handle == GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_U32 ||
        value->source_hash == 0u || value->reserved0 != 0u || value->reserved1 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    for (axis = 0u; axis < 3u; axis++) {
        if (value->scale_q16[axis] <= 0) {
            return GE_STATUS_MALFORMED_STREAM;
        }
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_weapon_source_pages_v6_build_hand(
    const GERamRomWeaponSourceMapRowV6 *map_row,
    const GERamRomWeaponSourcePageV6 *source_page,
    GERamRomWeaponHandV6 *out_hand)
{
    GEStatusV1 status;
    if (map_row == NULL || source_page == NULL || out_hand == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_ramrom_weapon_source_pages_v6_validate_map(map_row);
    if (status != GE_STATUS_OK) {
        return status;
    }
    status = ge_ramrom_weapon_source_pages_v6_validate_page(source_page);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (map_row->item_id != source_page->item_id ||
        map_row->source_weapon_offset != source_page->source_weapon_offset ||
        map_row->source_stats_offset != source_page->source_stats_offset ||
        map_row->source_transform_offset != source_page->source_transform_offset ||
        map_row->source_matrix_handle != source_page->source_matrix_handle) {
        return GE_STATUS_ASSET_MISMATCH;
    }
    memset(out_hand, 0, sizeof(*out_hand));
    ge_weapon_source_init_header(&out_hand->header, (uint32_t)sizeof(*out_hand));
    out_hand->record_version = GE_WEAPON_EFFECT_OWNER_V6_RECORD_VERSION;
    out_hand->hand_index = source_page->flags & 1u;
    out_hand->flags = source_page->flags;
    out_hand->weapon_id = source_page->item_id;
    out_hand->model_handle = map_row->model_handle;
    out_hand->ammo_type = map_row->ammo_type;
    out_hand->magazine = source_page->magazine;
    out_hand->reserve = source_page->reserve;
    out_hand->magazine_capacity = map_row->magazine_capacity;
    out_hand->action_state = source_page->action_state;
    out_hand->firing_status = source_page->firing_status;
    out_hand->animation_id = source_page->animation_id;
    out_hand->animation_frame_q16 = source_page->animation_frame_q16;
    out_hand->animation_rate_q16 = source_page->animation_rate_q16;
    out_hand->source_weapon_offset = source_page->source_weapon_offset;
    out_hand->source_stats_offset = source_page->source_stats_offset;
    out_hand->source_transform_offset = source_page->source_transform_offset;
    out_hand->source_matrix_handle = source_page->source_matrix_handle;
    memcpy(out_hand->position_q16, source_page->position_q16, sizeof(out_hand->position_q16));
    memcpy(out_hand->rotation_q16, source_page->rotation_q16, sizeof(out_hand->rotation_q16));
    memcpy(out_hand->scale_q16, source_page->scale_q16, sizeof(out_hand->scale_q16));
    memcpy(out_hand->muzzle_offset_q16, source_page->muzzle_offset_q16, sizeof(out_hand->muzzle_offset_q16));
    out_hand->source_hash = source_page->source_hash;
    out_hand->resource_hash = map_row->resource_hash;
    return ge_ramrom_weapon_effect_v6_validate_hand(out_hand);
}

static const GERamRomWeaponSourceMapRowV6 *ge_weapon_source_find_map(
    const GERamRomWeaponSourceMapRowV6 *rows,
    uint32_t count,
    uint32_t item_id)
{
    uint32_t index;
    for (index = 0u; index < count; index++) {
        if (rows[index].item_id == item_id) {
            return &rows[index];
        }
    }
    return NULL;
}

GEStatusV1 ge_ramrom_weapon_source_pages_v6_build_frame(
    uint32_t demo_id,
    uint32_t stage_id,
    uint64_t native_tick,
    const GERamRomWeaponSourceMapRowV6 *map_rows,
    uint32_t map_count,
    const GERamRomWeaponSourcePageV6 *source_pages,
    uint32_t source_page_count,
    const GERamRomWeaponEffectEventV6 *events,
    uint32_t event_count,
    const GERamRomWeaponEffectFrameV6 *visual_template,
    GERamRomWeaponEffectFrameV6 *out_frame)
{
    GEStatusV1 status;
    uint32_t index;
    if (map_rows == NULL || source_pages == NULL || visual_template == NULL ||
        out_frame == NULL || map_count == 0u || map_count > GE_RAMROM_WEAPON_SOURCE_PAGES_V6_MAX_HANDS ||
        source_page_count != map_count || event_count > GE_WEAPON_EFFECT_OWNER_V6_MAX_EVENTS ||
        (event_count != 0u && events == NULL)) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (demo_id == 0u || stage_id == 0u || native_tick == UINT64_MAX ||
        (native_tick & 1u) != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    for (index = 0u; index < map_count; index++) {
        uint32_t prior;
        status = ge_ramrom_weapon_source_pages_v6_validate_map(&map_rows[index]);
        if (status != GE_STATUS_OK) {
            return status;
        }
        for (prior = 0u; prior < index; prior++) {
            if (map_rows[prior].item_id == map_rows[index].item_id ||
                map_rows[prior].model_handle == map_rows[index].model_handle) {
                return GE_STATUS_ASSET_MISMATCH;
            }
        }
    }
    *out_frame = *visual_template;
    out_frame->demo_id = demo_id;
    out_frame->stage_id = stage_id;
    out_frame->native_tick = native_tick;
    out_frame->reference_tick = native_tick / 2u;
    out_frame->source_anchor = (uint32_t)((native_tick & 1u) == 0u);
    out_frame->source_frame = visual_template->source_frame;
    out_frame->hand_count = source_page_count;
    out_frame->event_count = event_count;
    for (index = 0u; index < source_page_count; index++) {
        status = ge_ramrom_weapon_source_pages_v6_build_hand(
            &map_rows[index], &source_pages[index], &out_frame->hands[index]);
        if (status != GE_STATUS_OK) {
            return status;
        }
        if (out_frame->hands[index].hand_index != index) {
            return GE_STATUS_ASSET_MISMATCH;
        }
    }
    if (event_count != 0u) {
        memcpy(out_frame->events, events, sizeof(events[0]) * (size_t)event_count);
    }
    for (index = 0u; index < event_count; index++) {
        GERamRomWeaponEffectEventV6 *event = &out_frame->events[index];
        status = ge_ramrom_weapon_effect_v6_validate_event(event);
        if (status != GE_STATUS_OK) {
            return status;
        }
        if (event->source_reference_tick != out_frame->reference_tick) {
            return GE_STATUS_ASSET_MISMATCH;
        }
        if (event->category == GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_PROJECTILE &&
            event->source_resource_id != 0u) {
            const GERamRomWeaponSourceMapRowV6 *map = ge_weapon_source_find_map(
                map_rows, map_count, event->source_resource_id);
            if (map == NULL || event->resource_handle != map->model_handle) {
                return GE_STATUS_ASSET_MISMATCH;
            }
        }
    }
    out_frame->flags |= GE_WEAPON_EFFECT_OWNER_V6_FRAME_SOURCE_ANCHOR;
    out_frame->frame_hash = 0u;
    out_frame->frame_hash = ge_ramrom_weapon_effect_v6_hash_frame(out_frame);
    return ge_ramrom_weapon_effect_v6_validate_frame(out_frame);
}
