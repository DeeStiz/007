#include "ge_native_runtime_v5.h"

#include <stddef.h>

#define GE_RUNTIME_V5_HASH_OFFSET UINT64_C(1469598103934665603)

static uint64_t ge_runtime_v5_hash_byte(uint64_t hash, uint8_t value)
{
    return (hash ^ (uint64_t)value) * UINT64_C(1099511628211);
}

static uint64_t ge_runtime_v5_hash_u32_step(uint64_t hash, uint32_t value)
{
    hash = ge_runtime_v5_hash_byte(hash, (uint8_t)(value & UINT32_C(0xff)));
    hash = ge_runtime_v5_hash_byte(hash, (uint8_t)((value >> 8) & UINT32_C(0xff)));
    hash = ge_runtime_v5_hash_byte(hash, (uint8_t)((value >> 16) & UINT32_C(0xff)));
    return ge_runtime_v5_hash_byte(hash, (uint8_t)(value >> 24));
}

static uint64_t ge_runtime_v5_hash_i32_step(uint64_t hash, int32_t value)
{
    return ge_runtime_v5_hash_u32_step(hash, (uint32_t)value);
}

static uint64_t ge_runtime_v5_hash_u64_step(uint64_t hash, uint64_t value)
{
    hash = ge_runtime_v5_hash_u32_step(hash, (uint32_t)value);
    return ge_runtime_v5_hash_u32_step(hash, (uint32_t)(value >> 32));
}

static uint64_t ge_runtime_v5_hash_header(uint64_t hash, const GEAbiHeaderV1 *header)
{
    hash = ge_runtime_v5_hash_u32_step(hash, header->abi_version);
    return ge_runtime_v5_hash_u32_step(hash, header->struct_size);
}

static uint64_t ge_runtime_v5_hash_i32_array(uint64_t hash,
                                             const int32_t *values,
                                             uint32_t count)
{
    for (uint32_t index = 0u; index < count; index++) {
        hash = ge_runtime_v5_hash_i32_step(hash, values[index]);
    }
    return hash;
}

uint64_t ge_runtime_v5_hash_bytes(const uint8_t *bytes, uint32_t byte_count)
{
    if (bytes == NULL && byte_count != 0u) {
        return 0u;
    }

    uint64_t hash = (uint64_t)GE_RUNTIME_V5_HASH_OFFSET;
    for (uint32_t index = 0u; index < byte_count; index++) {
        hash = ge_runtime_v5_hash_byte(hash, bytes[index]);
    }
    return hash;
}

static GEStatusV1 ge_runtime_v5_validate_common(const GEAbiHeaderV1 *header,
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
    if (record_version != GE_RUNTIME_V5_RECORD_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    return GE_STATUS_OK;
}

static int ge_runtime_v5_axis_valid(int32_t value)
{
    return value >= GE_RUNTIME_V5_AXIS_MIN_Q16 && value <= GE_RUNTIME_V5_AXIS_MAX_Q16;
}

static int ge_runtime_v5_source_valid(uint32_t source)
{
    return source != 0u && (source & ~GE_INPUT_SOURCE_MASK) == 0u;
}

GEStatusV1 ge_runtime_v5_validate_timebase(const GETimebaseConfigV5 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_runtime_v5_validate_common(
        &value->header, (uint32_t)sizeof(*value), value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->reserved0 != 0u || value->reserved1 != 0u || value->reserved2 != 0u) {
        return GE_STATUS_RESERVED_BITS;
    }
    if (value->native_hz == 0u || value->reference_hz == 0u ||
        value->pair_numerator == 0u || value->pair_denominator == 0u ||
        value->audio_sample_rate == 0u || value->max_catch_up_ticks == 0u ||
        value->max_tick_debt < value->max_catch_up_ticks ||
        (value->policy_flags & ~GE_RUNTIME_V5_TIMEBASE_POLICY_MASK) != 0u) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_runtime_v5_validate_input_event(const GEInputEventV5 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_runtime_v5_validate_common(
        &value->header, (uint32_t)sizeof(*value), value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->reserved0 != 0u) {
        return GE_STATUS_RESERVED_BITS;
    }
    if (value->event_type > GE_INPUT_EVENT_MAX || !ge_runtime_v5_source_valid(value->source) ||
        (value->flags & ~GE_INPUT_FLAG_MASK) != 0u ||
        !ge_runtime_v5_axis_valid(value->axis_x_q16) ||
        !ge_runtime_v5_axis_valid(value->axis_y_q16) ||
        !ge_runtime_v5_axis_valid(value->trigger_l_q16) ||
        !ge_runtime_v5_axis_valid(value->trigger_r_q16)) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_runtime_v5_validate_input_snapshot(const GEInputSnapshotV5 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_runtime_v5_validate_common(
        &value->header, (uint32_t)sizeof(*value), value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->reserved0 != 0u || value->reserved1 != 0u || value->reserved2 != 0u) {
        return GE_STATUS_RESERVED_BITS;
    }
    if ((value->flags & ~GE_INPUT_FLAG_MASK) != 0u ||
        (value->source_mask & ~GE_INPUT_SOURCE_MASK) != 0u ||
        value->controller_count > 4u ||
        !ge_runtime_v5_axis_valid(value->axis_x_q16) ||
        !ge_runtime_v5_axis_valid(value->axis_y_q16) ||
        !ge_runtime_v5_axis_valid(value->trigger_l_q16) ||
        !ge_runtime_v5_axis_valid(value->trigger_r_q16)) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_runtime_v5_validate_title(const GETitleParitySnapshotV5 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_runtime_v5_validate_common(
        &value->header, (uint32_t)sizeof(*value), value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->reserved0 != 0u || value->reserved1 != 0u) {
        return GE_STATUS_RESERVED_BITS;
    }
    if ((value->flags & ~GE_TITLE_FLAG_MASK) != 0u ||
        value->pair_phase > 1u || value->screen > GE_TITLE_SCREEN_MAX) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_runtime_v5_validate_scene_frame(const GESceneFrameV5 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_runtime_v5_validate_common(
        &value->header, (uint32_t)sizeof(*value), value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->reserved0 != 0u || value->reserved1 != 0u) {
        return GE_STATUS_RESERVED_BITS;
    }
    if ((value->flags & ~GE_SCENE_FRAME_FLAG_MASK) != 0u ||
        value->pair_phase > 1u ||
        ((value->page_count != 0u) && value->page_size == 0u)) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_runtime_v5_validate_scene_page(const GEScenePageV5 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_runtime_v5_validate_common(
        &value->header, (uint32_t)sizeof(*value), value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->reserved0 != 0u || value->reserved1 != 0u) {
        return GE_STATUS_RESERVED_BITS;
    }
    if (value->page_kind == 0u || value->page_kind > GE_SCENE_PAGE_MAX ||
        value->item_size == 0u || value->first_item > value->total_items ||
        value->item_count > value->total_items - value->first_item) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_runtime_v5_validate_audio_command(const GEAudioCommandV5 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_runtime_v5_validate_common(
        &value->header, (uint32_t)sizeof(*value), value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->reserved0 != 0u) {
        return GE_STATUS_RESERVED_BITS;
    }
    if (value->command_type > GE_AUDIO_COMMAND_MAX ||
        value->slot >= GE_AUDIO_SFX_SLOT_CAPACITY ||
        value->voice >= GE_AUDIO_VOICE_CAPACITY ||
        (value->flags & ~GE_AUDIO_COMMAND_FLAG_MASK) != 0u ||
        !ge_runtime_v5_axis_valid(value->pan_q16) ||
        value->loop_end < value->loop_begin) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_runtime_v5_validate_audio_pcm_block(const GEAudioPCMBlockV5 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    return ge_audio_validate_pcm_block_v5(*value);
}

GEStatusV1 ge_runtime_v5_validate_audio_snapshot(const GEAudioSnapshotV5 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    return ge_audio_validate_snapshot_v5(*value);
}

GEStatusV1 ge_runtime_v5_validate_ramrom(const GERamRomSnapshotV5 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_runtime_v5_validate_common(
        &value->header, (uint32_t)sizeof(*value), value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->reserved0 != 0u || value->reserved1 != 0u || value->reserved2 != 0u) {
        return GE_STATUS_RESERVED_BITS;
    }
    if ((value->flags & ~GE_RAMROM_FLAG_MASK) != 0u ||
        value->replay_state > GE_RAMROM_STATE_MAX ||
        (value->packet_count != 0u && value->packet_index > value->packet_count)) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_runtime_v5_scene_page_bounds(uint32_t total_items,
                                           uint32_t item_size,
                                           uint32_t page_index,
                                           uint32_t page_capacity,
                                           uint32_t *first_item,
                                           uint32_t *item_count)
{
    if (first_item == NULL || item_count == NULL || item_size == 0u || page_capacity == 0u) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (page_index > UINT32_MAX / page_capacity) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    uint32_t first = page_index * page_capacity;
    if (first > total_items) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    uint32_t remaining = total_items - first;
    *first_item = first;
    *item_count = remaining < page_capacity ? remaining : page_capacity;
    return GE_STATUS_OK;
}

GEStatusV1 ge_runtime_v5_validate_audio_pcm_payload(const GEAudioPCMBlockV5 *block,
                                                    const uint8_t *pcm_bytes,
                                                    uint32_t pcm_byte_count)
{
    GEStatusV1 status = ge_runtime_v5_validate_audio_pcm_block(block);
    if (status != GE_STATUS_OK) {
        return status;
    }
    uint32_t bytes_per_sample = block->sample_format == GE_AUDIO_V5_PCM_FORMAT_S16 ? 2u : 4u;
    if (block->frame_count > UINT32_MAX / block->channel_count ||
        block->frame_count * block->channel_count > UINT32_MAX / bytes_per_sample ||
        pcm_byte_count != block->byte_count ||
        pcm_byte_count != block->frame_count * block->channel_count * bytes_per_sample ||
        (pcm_bytes == NULL && pcm_byte_count != 0u) ||
        ge_runtime_v5_hash_bytes(pcm_bytes, pcm_byte_count) != block->content_hash) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    return GE_STATUS_OK;
}

uint64_t ge_runtime_v5_hash_timebase(const GETimebaseConfigV5 *value)
{
    if (ge_runtime_v5_validate_timebase(value) != GE_STATUS_OK) {
        return 0u;
    }
    uint64_t hash = (uint64_t)GE_RUNTIME_V5_HASH_OFFSET;
    hash = ge_runtime_v5_hash_header(hash, &value->header);
    hash = ge_runtime_v5_hash_u32_step(hash, value->record_version);
    hash = ge_runtime_v5_hash_u32_step(hash, value->native_hz);
    hash = ge_runtime_v5_hash_u32_step(hash, value->reference_hz);
    hash = ge_runtime_v5_hash_u32_step(hash, value->pair_numerator);
    hash = ge_runtime_v5_hash_u32_step(hash, value->pair_denominator);
    hash = ge_runtime_v5_hash_u32_step(hash, value->max_catch_up_ticks);
    hash = ge_runtime_v5_hash_u32_step(hash, value->max_tick_debt);
    hash = ge_runtime_v5_hash_u32_step(hash, value->policy_flags);
    return ge_runtime_v5_hash_u32_step(hash, value->audio_sample_rate);
}

uint64_t ge_runtime_v5_hash_input_event(const GEInputEventV5 *value)
{
    if (ge_runtime_v5_validate_input_event(value) != GE_STATUS_OK) {
        return 0u;
    }
    uint64_t hash = (uint64_t)GE_RUNTIME_V5_HASH_OFFSET;
    hash = ge_runtime_v5_hash_header(hash, &value->header);
    hash = ge_runtime_v5_hash_u32_step(hash, value->record_version);
    hash = ge_runtime_v5_hash_u32_step(hash, value->event_type);
    hash = ge_runtime_v5_hash_u32_step(hash, value->source);
    hash = ge_runtime_v5_hash_u32_step(hash, value->flags);
    hash = ge_runtime_v5_hash_u32_step(hash, value->buttons);
    hash = ge_runtime_v5_hash_i32_step(hash, value->axis_x_q16);
    hash = ge_runtime_v5_hash_i32_step(hash, value->axis_y_q16);
    hash = ge_runtime_v5_hash_i32_step(hash, value->trigger_l_q16);
    hash = ge_runtime_v5_hash_i32_step(hash, value->trigger_r_q16);
    hash = ge_runtime_v5_hash_u64_step(hash, value->timestamp_ns);
    return ge_runtime_v5_hash_u64_step(hash, value->sequence);
}

uint64_t ge_runtime_v5_hash_input_snapshot(const GEInputSnapshotV5 *value)
{
    if (ge_runtime_v5_validate_input_snapshot(value) != GE_STATUS_OK) {
        return 0u;
    }
    uint64_t hash = (uint64_t)GE_RUNTIME_V5_HASH_OFFSET;
    hash = ge_runtime_v5_hash_header(hash, &value->header);
    hash = ge_runtime_v5_hash_u32_step(hash, value->record_version);
    hash = ge_runtime_v5_hash_u32_step(hash, value->flags);
    hash = ge_runtime_v5_hash_u64_step(hash, value->sequence);
    hash = ge_runtime_v5_hash_u64_step(hash, value->timestamp_ns);
    hash = ge_runtime_v5_hash_u64_step(hash, value->native_tick);
    hash = ge_runtime_v5_hash_u32_step(hash, value->held);
    hash = ge_runtime_v5_hash_u32_step(hash, value->pressed);
    hash = ge_runtime_v5_hash_u32_step(hash, value->released);
    hash = ge_runtime_v5_hash_u32_step(hash, value->source_mask);
    hash = ge_runtime_v5_hash_u32_step(hash, value->controller_count);
    hash = ge_runtime_v5_hash_i32_step(hash, value->axis_x_q16);
    hash = ge_runtime_v5_hash_i32_step(hash, value->axis_y_q16);
    hash = ge_runtime_v5_hash_i32_step(hash, value->trigger_l_q16);
    return ge_runtime_v5_hash_i32_step(hash, value->trigger_r_q16);
}

uint64_t ge_runtime_v5_hash_title(const GETitleParitySnapshotV5 *value)
{
    if (ge_runtime_v5_validate_title(value) != GE_STATUS_OK) {
        return 0u;
    }
    uint64_t hash = (uint64_t)GE_RUNTIME_V5_HASH_OFFSET;
    hash = ge_runtime_v5_hash_header(hash, &value->header);
    hash = ge_runtime_v5_hash_u32_step(hash, value->record_version);
    hash = ge_runtime_v5_hash_u32_step(hash, value->flags);
    hash = ge_runtime_v5_hash_u64_step(hash, value->native_tick);
    hash = ge_runtime_v5_hash_u64_step(hash, value->reference_tick);
    hash = ge_runtime_v5_hash_u32_step(hash, value->pair_phase);
    hash = ge_runtime_v5_hash_u32_step(hash, value->screen);
    hash = ge_runtime_v5_hash_u32_step(hash, value->subphase);
    hash = ge_runtime_v5_hash_u32_step(hash, value->source_timer);
    hash = ge_runtime_v5_hash_u32_step(hash, value->source_threshold);
    hash = ge_runtime_v5_hash_u32_step(hash, value->source_frame);
    hash = ge_runtime_v5_hash_u32_step(hash, value->transition);
    hash = ge_runtime_v5_hash_u32_step(hash, value->selection);
    hash = ge_runtime_v5_hash_u32_step(hash, value->cursor);
    hash = ge_runtime_v5_hash_i32_array(hash, value->transform_q16, 8u);
    hash = ge_runtime_v5_hash_u64_step(hash, value->state_hash);
    hash = ge_runtime_v5_hash_u64_step(hash, value->render_hash);
    return ge_runtime_v5_hash_u64_step(hash, value->audio_hash);
}

uint64_t ge_runtime_v5_hash_scene_frame(const GESceneFrameV5 *value)
{
    if (ge_runtime_v5_validate_scene_frame(value) != GE_STATUS_OK) {
        return 0u;
    }
    uint64_t hash = (uint64_t)GE_RUNTIME_V5_HASH_OFFSET;
    hash = ge_runtime_v5_hash_header(hash, &value->header);
    hash = ge_runtime_v5_hash_u32_step(hash, value->record_version);
    hash = ge_runtime_v5_hash_u32_step(hash, value->flags);
    hash = ge_runtime_v5_hash_u64_step(hash, value->native_tick);
    hash = ge_runtime_v5_hash_u64_step(hash, value->reference_tick);
    hash = ge_runtime_v5_hash_u32_step(hash, value->pair_phase);
    hash = ge_runtime_v5_hash_u32_step(hash, value->frame_slot);
    hash = ge_runtime_v5_hash_u32_step(hash, value->viewport_width);
    hash = ge_runtime_v5_hash_u32_step(hash, value->viewport_height);
    hash = ge_runtime_v5_hash_u32_step(hash, value->logical_width);
    hash = ge_runtime_v5_hash_u32_step(hash, value->logical_height);
    hash = ge_runtime_v5_hash_u32_step(hash, value->transform_count);
    hash = ge_runtime_v5_hash_u32_step(hash, value->resource_count);
    hash = ge_runtime_v5_hash_u32_step(hash, value->draw_count);
    hash = ge_runtime_v5_hash_u32_step(hash, value->ui_packet_count);
    hash = ge_runtime_v5_hash_u32_step(hash, value->diagnostic_count);
    hash = ge_runtime_v5_hash_u32_step(hash, value->page_size);
    hash = ge_runtime_v5_hash_u32_step(hash, value->page_count);
    hash = ge_runtime_v5_hash_u64_step(hash, value->scene_hash);
    hash = ge_runtime_v5_hash_u64_step(hash, value->render_hash);
    return ge_runtime_v5_hash_u64_step(hash, value->audio_cursor);
}

uint64_t ge_runtime_v5_hash_scene_page(const GEScenePageV5 *value)
{
    if (ge_runtime_v5_validate_scene_page(value) != GE_STATUS_OK) {
        return 0u;
    }
    uint64_t hash = (uint64_t)GE_RUNTIME_V5_HASH_OFFSET;
    hash = ge_runtime_v5_hash_header(hash, &value->header);
    hash = ge_runtime_v5_hash_u32_step(hash, value->record_version);
    hash = ge_runtime_v5_hash_u32_step(hash, value->page_kind);
    hash = ge_runtime_v5_hash_u32_step(hash, value->page_index);
    hash = ge_runtime_v5_hash_u32_step(hash, value->item_size);
    hash = ge_runtime_v5_hash_u32_step(hash, value->first_item);
    hash = ge_runtime_v5_hash_u32_step(hash, value->item_count);
    hash = ge_runtime_v5_hash_u32_step(hash, value->total_items);
    return ge_runtime_v5_hash_u64_step(hash, value->page_hash);
}

uint64_t ge_runtime_v5_hash_audio_command(const GEAudioCommandV5 *value)
{
    if (ge_runtime_v5_validate_audio_command(value) != GE_STATUS_OK) {
        return 0u;
    }
    uint64_t hash = (uint64_t)GE_RUNTIME_V5_HASH_OFFSET;
    hash = ge_runtime_v5_hash_header(hash, &value->header);
    hash = ge_runtime_v5_hash_u32_step(hash, value->record_version);
    hash = ge_runtime_v5_hash_u32_step(hash, value->command_type);
    hash = ge_runtime_v5_hash_u32_step(hash, value->slot);
    hash = ge_runtime_v5_hash_u32_step(hash, value->voice);
    hash = ge_runtime_v5_hash_u32_step(hash, value->flags);
    hash = ge_runtime_v5_hash_u32_step(hash, value->asset_handle);
    hash = ge_runtime_v5_hash_u32_step(hash, value->note);
    hash = ge_runtime_v5_hash_u32_step(hash, value->velocity);
    hash = ge_runtime_v5_hash_i32_step(hash, value->pitch_q16);
    hash = ge_runtime_v5_hash_i32_step(hash, value->pan_q16);
    hash = ge_runtime_v5_hash_i32_step(hash, value->gain_q16);
    hash = ge_runtime_v5_hash_u64_step(hash, value->sample_index);
    hash = ge_runtime_v5_hash_u32_step(hash, value->duration_frames);
    hash = ge_runtime_v5_hash_u32_step(hash, value->loop_begin);
    hash = ge_runtime_v5_hash_u32_step(hash, value->loop_end);
    return ge_runtime_v5_hash_u64_step(hash, value->payload_hash);
}

uint64_t ge_runtime_v5_hash_audio_pcm_block(const GEAudioPCMBlockV5 *value)
{
    if (ge_runtime_v5_validate_audio_pcm_block(value) != GE_STATUS_OK) {
        return 0u;
    }
    uint64_t hash = (uint64_t)GE_RUNTIME_V5_HASH_OFFSET;
    hash = ge_runtime_v5_hash_header(hash, &value->header);
    hash = ge_runtime_v5_hash_u32_step(hash, value->contract_version);
    hash = ge_runtime_v5_hash_u32_step(hash, value->flags);
    hash = ge_runtime_v5_hash_u64_step(hash, value->first_sample_index);
    hash = ge_runtime_v5_hash_u32_step(hash, value->frame_count);
    hash = ge_runtime_v5_hash_u32_step(hash, value->channel_count);
    hash = ge_runtime_v5_hash_u32_step(hash, value->sample_format);
    hash = ge_runtime_v5_hash_u32_step(hash, value->sample_rate);
    hash = ge_runtime_v5_hash_u64_step(hash, value->content_hash);
    hash = ge_runtime_v5_hash_u32_step(hash, value->underrun_count);
    hash = ge_runtime_v5_hash_u32_step(hash, value->bytes_per_frame);
    return ge_runtime_v5_hash_u32_step(hash, value->byte_count);
}

uint64_t ge_runtime_v5_hash_audio_snapshot(const GEAudioSnapshotV5 *value)
{
    if (ge_runtime_v5_validate_audio_snapshot(value) != GE_STATUS_OK) {
        return 0u;
    }
    uint64_t hash = (uint64_t)GE_RUNTIME_V5_HASH_OFFSET;
    hash = ge_runtime_v5_hash_header(hash, &value->header);
    hash = ge_runtime_v5_hash_u32_step(hash, value->contract_version);
    hash = ge_runtime_v5_hash_u32_step(hash, value->flags);
    hash = ge_runtime_v5_hash_u64_step(hash, value->native_tick);
    hash = ge_runtime_v5_hash_u64_step(hash, value->sample_cursor);
    hash = ge_runtime_v5_hash_u64_step(hash, value->event_hash);
    hash = ge_runtime_v5_hash_u64_step(hash, value->pcm_hash);
    hash = ge_runtime_v5_hash_u32_step(hash, value->active_voice_count);
    hash = ge_runtime_v5_hash_u32_step(hash, value->underrun_count);
    hash = ge_runtime_v5_hash_u32_step(hash, value->dropped_event_count);
    hash = ge_runtime_v5_hash_u32_step(hash, value->sample_rate);
    hash = ge_runtime_v5_hash_u32_step(hash, value->frames_generated);
    return ge_runtime_v5_hash_u32_step(hash, value->music_slot_count);
}

uint64_t ge_runtime_v5_hash_ramrom(const GERamRomSnapshotV5 *value)
{
    if (ge_runtime_v5_validate_ramrom(value) != GE_STATUS_OK) {
        return 0u;
    }
    uint64_t hash = (uint64_t)GE_RUNTIME_V5_HASH_OFFSET;
    hash = ge_runtime_v5_hash_header(hash, &value->header);
    hash = ge_runtime_v5_hash_u32_step(hash, value->record_version);
    hash = ge_runtime_v5_hash_u32_step(hash, value->flags);
    hash = ge_runtime_v5_hash_u64_step(hash, value->native_tick);
    hash = ge_runtime_v5_hash_u64_step(hash, value->reference_tick);
    hash = ge_runtime_v5_hash_u32_step(hash, value->demo_id);
    hash = ge_runtime_v5_hash_u32_step(hash, value->stage_id);
    hash = ge_runtime_v5_hash_u32_step(hash, value->replay_state);
    hash = ge_runtime_v5_hash_u32_step(hash, value->packet_index);
    hash = ge_runtime_v5_hash_u32_step(hash, value->packet_count);
    hash = ge_runtime_v5_hash_u32_step(hash, value->speedframes);
    hash = ge_runtime_v5_hash_u32_step(hash, value->rng_index);
    hash = ge_runtime_v5_hash_u32_step(hash, value->input_buttons);
    hash = ge_runtime_v5_hash_u64_step(hash, value->recording_hash);
    hash = ge_runtime_v5_hash_u64_step(hash, value->rng_hash);
    hash = ge_runtime_v5_hash_u64_step(hash, value->state_hash);
    hash = ge_runtime_v5_hash_u64_step(hash, value->render_hash);
    hash = ge_runtime_v5_hash_u64_step(hash, value->audio_hash);
    return ge_runtime_v5_hash_u64_step(hash, value->save_generation);
}
