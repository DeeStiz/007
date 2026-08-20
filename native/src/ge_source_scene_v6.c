#include "ge_source_scene_v6.h"

#include <string.h>

#define GE_SOURCE_SCENE_V6_HASH_OFFSET UINT64_C(1469598103934665603)
#define GE_SOURCE_SCENE_V6_HASH_PRIME UINT64_C(1099511628211)

static uint64_t ge_source_scene_v6_hash_byte(uint64_t hash, uint8_t value)
{
    return (hash ^ (uint64_t)value) * GE_SOURCE_SCENE_V6_HASH_PRIME;
}

static uint64_t ge_source_scene_v6_hash_u32_step(uint64_t hash, uint32_t value)
{
    hash = ge_source_scene_v6_hash_byte(hash, (uint8_t)(value & UINT32_C(0xff)));
    hash = ge_source_scene_v6_hash_byte(hash,
                                        (uint8_t)((value >> 8) & UINT32_C(0xff)));
    hash = ge_source_scene_v6_hash_byte(hash,
                                        (uint8_t)((value >> 16) & UINT32_C(0xff)));
    return ge_source_scene_v6_hash_byte(hash, (uint8_t)(value >> 24));
}

static uint64_t ge_source_scene_v6_hash_i32_step(uint64_t hash, int32_t value)
{
    return ge_source_scene_v6_hash_u32_step(hash, (uint32_t)value);
}

static uint64_t ge_source_scene_v6_hash_u64_step(uint64_t hash, uint64_t value)
{
    hash = ge_source_scene_v6_hash_u32_step(hash, (uint32_t)value);
    return ge_source_scene_v6_hash_u32_step(hash, (uint32_t)(value >> 32));
}

static uint64_t ge_source_scene_v6_hash_header(uint64_t hash,
                                               const GEAbiHeaderV1 *header)
{
    hash = ge_source_scene_v6_hash_u32_step(hash, header->abi_version);
    return ge_source_scene_v6_hash_u32_step(hash, header->struct_size);
}

static uint64_t ge_source_scene_v6_hash_i32_array(uint64_t hash,
                                                  const int32_t *values,
                                                  uint32_t count)
{
    for (uint32_t index = 0u; index < count; index++) {
        hash = ge_source_scene_v6_hash_i32_step(hash, values[index]);
    }
    return hash;
}

uint64_t ge_source_scene_v6_hash_bytes(const uint8_t *bytes, uint32_t byte_count)
{
    if (bytes == NULL && byte_count != 0u) {
        return 0u;
    }

    uint64_t hash = GE_SOURCE_SCENE_V6_HASH_OFFSET;
    for (uint32_t index = 0u; index < byte_count; index++) {
        hash = ge_source_scene_v6_hash_byte(hash, bytes[index]);
    }
    return hash;
}

uint64_t ge_source_scene_v6_hash_resource(const GESourceResourceV6 *value)
{
    if (value == NULL) {
        return 0u;
    }
    uint64_t hash = ge_source_scene_v6_hash_header(
        GE_SOURCE_SCENE_V6_HASH_OFFSET, &value->header);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->record_version);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->resource_kind);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->flags);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->handle);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->source_id);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->format);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->width);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->height);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->depth);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->mip_count);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->level_count);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->byte_size);
    hash = ge_source_scene_v6_hash_u64_step(hash, value->content_hash);
    hash = ge_source_scene_v6_hash_u64_step(hash, value->provenance_hash);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->reserved0);
    return ge_source_scene_v6_hash_u32_step(hash, value->reserved1);
}

uint64_t ge_source_scene_v6_hash_transform(const GESourceTransformV6 *value)
{
    if (value == NULL) {
        return 0u;
    }
    uint64_t hash = ge_source_scene_v6_hash_header(
        GE_SOURCE_SCENE_V6_HASH_OFFSET, &value->header);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->record_version);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->transform_kind);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->flags);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->handle);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->parent_handle);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->source_node);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->viewport_id);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->reserved0);
    hash = ge_source_scene_v6_hash_i32_array(hash, value->matrix_q16, 16u);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->reserved1);
    return ge_source_scene_v6_hash_u32_step(hash, value->reserved2);
}

uint64_t ge_source_scene_v6_hash_animation_pose(const GESourceAnimationPoseV6 *value)
{
    if (value == NULL) {
        return 0u;
    }
    uint64_t hash = ge_source_scene_v6_hash_header(
        GE_SOURCE_SCENE_V6_HASH_OFFSET, &value->header);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->record_version);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->pose_handle);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->skeleton_handle);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->node_handle);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->parent_handle);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->flags);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->animation_tick);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->reserved0);
    hash = ge_source_scene_v6_hash_i32_array(hash, value->translation_q16, 3u);
    hash = ge_source_scene_v6_hash_i32_array(hash, value->rotation_q16, 4u);
    hash = ge_source_scene_v6_hash_i32_array(hash, value->scale_q16, 3u);
    hash = ge_source_scene_v6_hash_u64_step(hash, value->pose_hash);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->reserved1);
    return ge_source_scene_v6_hash_u32_step(hash, value->reserved2);
}

uint64_t ge_source_scene_v6_hash_vertex(const GESourceVertexV6 *value)
{
    if (value == NULL) {
        return 0u;
    }
    uint64_t hash = ge_source_scene_v6_hash_header(
        GE_SOURCE_SCENE_V6_HASH_OFFSET, &value->header);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->record_version);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->handle);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->flags);
    hash = ge_source_scene_v6_hash_i32_array(hash, value->position_q16, 3u);
    hash = ge_source_scene_v6_hash_i32_array(hash, value->texcoord_q16, 2u);
    hash = ge_source_scene_v6_hash_i32_array(hash, value->normal_q16, 3u);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->color_rgba);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->source_index);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->reserved0);
    return ge_source_scene_v6_hash_u32_step(hash, value->reserved1);
}

uint64_t ge_source_scene_v6_hash_index(const GESourceIndexV6 *value)
{
    if (value == NULL) {
        return 0u;
    }
    uint64_t hash = ge_source_scene_v6_hash_header(
        GE_SOURCE_SCENE_V6_HASH_OFFSET, &value->header);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->record_version);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->handle);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->flags);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->vertex0);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->vertex1);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->vertex2);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->source_index);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->reserved0);
    return ge_source_scene_v6_hash_u32_step(hash, value->reserved1);
}

uint64_t ge_source_scene_v6_hash_render_state(const GESourceRenderStateV6 *value)
{
    if (value == NULL) {
        return 0u;
    }
    uint64_t hash = ge_source_scene_v6_hash_header(
        GE_SOURCE_SCENE_V6_HASH_OFFSET, &value->header);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->record_version);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->state_handle);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->flags);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->material_handle);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->combiner_cycle_count);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->cycle0_color_a);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->cycle0_color_b);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->cycle0_color_c);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->cycle0_color_d);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->cycle0_alpha_a);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->cycle0_alpha_b);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->cycle0_alpha_c);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->cycle0_alpha_d);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->cycle1_color_a);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->cycle1_color_b);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->cycle1_color_c);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->cycle1_color_d);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->cycle1_alpha_a);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->cycle1_alpha_b);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->cycle1_alpha_c);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->cycle1_alpha_d);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->primitive_rgba);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->environment_rgba);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->fog_rgba);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->blend_rgba);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->depth_mode);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->alpha_mode);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->coverage_mode);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->cull_mode);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->filter_mode);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->wrap_s);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->wrap_t);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->lod_min_q16);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->lod_max_q16);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->raw_othermode_h);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->raw_othermode_l);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->raw_render_mode);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->raw_blender_a);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->raw_blender_b);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->raw_blender_c);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->raw_blender_d);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->reserved0);
    return ge_source_scene_v6_hash_u32_step(hash, value->reserved1);
}

uint64_t ge_source_scene_v6_hash_draw_command(const GESourceDrawCommandV6 *value)
{
    if (value == NULL) {
        return 0u;
    }
    uint64_t hash = ge_source_scene_v6_hash_header(
        GE_SOURCE_SCENE_V6_HASH_OFFSET, &value->header);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->record_version);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->command_kind);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->flags);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->draw_handle);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->transform_handle);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->resource_handle);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->render_state_handle);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->first_vertex);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->vertex_count);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->first_index);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->index_count);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->instance_count);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->text_handle);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->sort_key);
    hash = ge_source_scene_v6_hash_i32_step(hash, value->depth_q16);
    hash = ge_source_scene_v6_hash_i32_step(hash, value->scissor_x);
    hash = ge_source_scene_v6_hash_i32_step(hash, value->scissor_y);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->scissor_width);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->scissor_height);
    hash = ge_source_scene_v6_hash_u64_step(hash, value->draw_hash);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->reserved0);
    return ge_source_scene_v6_hash_u32_step(hash, value->reserved1);
}

uint64_t ge_source_scene_v6_hash_text_event(const GESourceTextEventV6 *value)
{
    if (value == NULL) {
        return 0u;
    }
    uint64_t hash = ge_source_scene_v6_hash_header(
        GE_SOURCE_SCENE_V6_HASH_OFFSET, &value->header);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->record_version);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->event_kind);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->flags);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->text_handle);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->glyph_run_handle);
    hash = ge_source_scene_v6_hash_i32_step(hash, value->x_q16);
    hash = ge_source_scene_v6_hash_i32_step(hash, value->y_q16);
    hash = ge_source_scene_v6_hash_i32_step(hash, value->scale_x_q16);
    hash = ge_source_scene_v6_hash_i32_step(hash, value->scale_y_q16);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->color_rgba);
    hash = ge_source_scene_v6_hash_i32_step(hash, value->scissor_x);
    hash = ge_source_scene_v6_hash_i32_step(hash, value->scissor_y);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->scissor_width);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->scissor_height);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->glyph_count);
    hash = ge_source_scene_v6_hash_u64_step(hash, value->string_hash);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->reserved0);
    return ge_source_scene_v6_hash_u32_step(hash, value->reserved1);
}

uint64_t ge_source_scene_v6_hash_audio_event(const GESourceAudioEventV6 *value)
{
    if (value == NULL) {
        return 0u;
    }
    uint64_t hash = ge_source_scene_v6_hash_header(
        GE_SOURCE_SCENE_V6_HASH_OFFSET, &value->header);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->record_version);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->event_kind);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->flags);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->event_handle);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->asset_handle);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->slot);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->voice);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->note);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->velocity);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->reserved0);
    hash = ge_source_scene_v6_hash_i32_step(hash, value->pitch_q16);
    hash = ge_source_scene_v6_hash_i32_step(hash, value->pan_q16);
    hash = ge_source_scene_v6_hash_i32_step(hash, value->gain_q16);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->reserved1);
    hash = ge_source_scene_v6_hash_u64_step(hash, value->sample_index);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->duration_frames);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->loop_begin);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->loop_end);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->reserved2);
    hash = ge_source_scene_v6_hash_u64_step(hash, value->event_hash);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->reserved3);
    return ge_source_scene_v6_hash_u32_step(hash, value->reserved4);
}

uint64_t ge_source_scene_v6_hash_frame_summary(const GESourceFrameSummaryV6 *value)
{
    if (value == NULL) {
        return 0u;
    }
    uint64_t hash = ge_source_scene_v6_hash_header(
        GE_SOURCE_SCENE_V6_HASH_OFFSET, &value->header);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->record_version);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->flags);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->screen);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->subphase);
    hash = ge_source_scene_v6_hash_u64_step(hash, value->native_tick);
    hash = ge_source_scene_v6_hash_u64_step(hash, value->reference_tick);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->pair_phase);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->viewport_width);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->viewport_height);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->logical_width);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->logical_height);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->transform_count);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->resource_count);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->pose_count);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->vertex_count);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->index_count);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->draw_count);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->render_state_count);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->text_count);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->audio_count);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->diagnostic_count);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->unsupported_visible_count);
    hash = ge_source_scene_v6_hash_u64_step(hash, value->scene_hash);
    hash = ge_source_scene_v6_hash_u64_step(hash, value->render_hash);
    hash = ge_source_scene_v6_hash_u64_step(hash, value->state_hash);
    hash = ge_source_scene_v6_hash_u64_step(hash, value->audio_hash);
    hash = ge_source_scene_v6_hash_u64_step(hash, value->frame_hash);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->reserved0);
    return ge_source_scene_v6_hash_u32_step(hash, value->reserved1);
}

uint64_t ge_source_scene_v6_hash_diagnostic(const GESourceDiagnosticV6 *value)
{
    if (value == NULL) {
        return 0u;
    }
    uint64_t hash = ge_source_scene_v6_hash_header(
        GE_SOURCE_SCENE_V6_HASH_OFFSET, &value->header);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->record_version);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->diagnostic_kind);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->flags);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->severity);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->code);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->source_id);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->command_id);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->first_bad_index);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->item_count);
    hash = ge_source_scene_v6_hash_u64_step(hash, value->detail_hash);
    hash = ge_source_scene_v6_hash_u32_step(hash, value->reserved0);
    return ge_source_scene_v6_hash_u32_step(hash, value->reserved1);
}

static GEStatusV1 ge_source_scene_v6_validate_common(const GEAbiHeaderV1 *header,
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
    if (record_version != GE_SOURCE_SCENE_V6_RECORD_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    return GE_STATUS_OK;
}

static int ge_source_scene_v6_valid_handle(uint32_t handle)
{
    return handle != GE_SOURCE_SCENE_V6_HANDLE_INVALID;
}

static int ge_source_scene_v6_valid_q16(int32_t value)
{
    return value >= INT32_MIN && value <= INT32_MAX;
}

static int ge_source_scene_v6_valid_combiner_key(uint32_t key)
{
    return key <= GE_SOURCE_COMBINER_V6_KEY_MAX &&
           (key & ~GE_SOURCE_COMBINER_V6_KEY_MASK) == 0u;
}

GEStatusV1 ge_source_scene_v6_validate_resource(const GESourceResourceV6 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_source_scene_v6_validate_common(
        &value->header, (uint32_t)sizeof(*value), value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->reserved0 != 0u || value->reserved1 != 0u) {
        return GE_STATUS_RESERVED_BITS;
    }
    if (value->resource_kind == 0u ||
        value->resource_kind > GE_SOURCE_RESOURCE_V6_KIND_MAX ||
        (value->flags & ~GE_SOURCE_RESOURCE_V6_FLAG_MASK) != 0u ||
        !ge_source_scene_v6_valid_handle(value->handle) ||
        value->format > GE_SOURCE_RESOURCE_V6_FORMAT_MAX ||
        value->mip_count == 0u || value->mip_count > 32u ||
        value->level_count == 0u || value->level_count > 32u ||
        value->byte_size == 0u) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (value->resource_kind == GE_SOURCE_RESOURCE_V6_TEXTURE &&
        (value->format == GE_SOURCE_RESOURCE_V6_FORMAT_NONE || value->width == 0u ||
         value->height == 0u || value->depth == 0u)) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_source_scene_v6_validate_transform(const GESourceTransformV6 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_source_scene_v6_validate_common(
        &value->header, (uint32_t)sizeof(*value), value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->reserved0 != 0u || value->reserved1 != 0u || value->reserved2 != 0u) {
        return GE_STATUS_RESERVED_BITS;
    }
    if (value->transform_kind == 0u ||
        value->transform_kind > GE_SOURCE_TRANSFORM_V6_KIND_MAX ||
        (value->flags & ~GE_SOURCE_TRANSFORM_V6_FLAG_MASK) != 0u ||
        !ge_source_scene_v6_valid_handle(value->handle)) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    /* A clip-composite is the only transform that may carry the additive
       clip flag.  Its source handles identify the exact modelview,
       projection, and viewport inputs used to produce matrix_q16; keeping
       these in existing fields preserves the V6 record size. */
    if (value->transform_kind == GE_SOURCE_TRANSFORM_V6_CLIP_COMPOSITE) {
        if ((value->flags & GE_SOURCE_TRANSFORM_V6_FLAG_SOURCE_QUANTIZED) == 0u ||
            (value->flags & GE_SOURCE_TRANSFORM_V6_FLAG_CLIP_COMPOSITE) == 0u ||
            !ge_source_scene_v6_valid_handle(value->parent_handle) ||
            !ge_source_scene_v6_valid_handle(value->source_node) ||
            !ge_source_scene_v6_valid_handle(value->viewport_id)) {
            return GE_STATUS_INVALID_ARGUMENT;
        }
    } else if ((value->flags & GE_SOURCE_TRANSFORM_V6_FLAG_CLIP_COMPOSITE) != 0u) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    for (uint32_t index = 0u; index < 16u; index++) {
        if (!ge_source_scene_v6_valid_q16(value->matrix_q16[index])) {
            return GE_STATUS_INVALID_ARGUMENT;
        }
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_source_scene_v6_validate_animation_pose(
    const GESourceAnimationPoseV6 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_source_scene_v6_validate_common(
        &value->header, (uint32_t)sizeof(*value), value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->reserved0 != 0u || value->reserved1 != 0u || value->reserved2 != 0u) {
        return GE_STATUS_RESERVED_BITS;
    }
    if ((value->flags & ~GE_SOURCE_POSE_V6_FLAG_MASK) != 0u ||
        !ge_source_scene_v6_valid_handle(value->pose_handle) ||
        !ge_source_scene_v6_valid_handle(value->skeleton_handle) ||
        !ge_source_scene_v6_valid_handle(value->node_handle)) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_source_scene_v6_validate_vertex(const GESourceVertexV6 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_source_scene_v6_validate_common(
        &value->header, (uint32_t)sizeof(*value), value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->reserved0 != 0u || value->reserved1 != 0u) {
        return GE_STATUS_RESERVED_BITS;
    }
    if (!ge_source_scene_v6_valid_handle(value->handle) ||
        (value->flags & ~GE_SOURCE_VERTEX_V6_FLAG_MASK) != 0u) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_source_scene_v6_validate_index(const GESourceIndexV6 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_source_scene_v6_validate_common(
        &value->header, (uint32_t)sizeof(*value), value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->reserved0 != 0u || value->reserved1 != 0u) {
        return GE_STATUS_RESERVED_BITS;
    }
    if (!ge_source_scene_v6_valid_handle(value->handle) ||
        (value->flags & ~GE_SOURCE_INDEX_V6_FLAG_MASK) != 0u) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_source_scene_v6_validate_render_state(
    const GESourceRenderStateV6 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_source_scene_v6_validate_common(
        &value->header, (uint32_t)sizeof(*value), value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->reserved0 != 0u || value->reserved1 != 0u) {
        return GE_STATUS_RESERVED_BITS;
    }
    if (!ge_source_scene_v6_valid_handle(value->state_handle) ||
        !ge_source_scene_v6_valid_handle(value->material_handle) ||
        (value->flags & ~GE_SOURCE_RENDER_STATE_V6_FLAG_MASK) != 0u ||
        value->combiner_cycle_count < 1u || value->combiner_cycle_count > 2u ||
        value->depth_mode > GE_SOURCE_DEPTH_V6_MAX ||
        value->alpha_mode > GE_SOURCE_ALPHA_V6_MAX ||
        value->coverage_mode > GE_SOURCE_COVERAGE_V6_MAX ||
        value->cull_mode > GE_SOURCE_CULL_V6_MAX ||
        value->filter_mode > GE_SOURCE_FILTER_V6_MAX ||
        value->wrap_s > GE_SOURCE_WRAP_V6_MAX || value->wrap_t > GE_SOURCE_WRAP_V6_MAX ||
        value->lod_max_q16 < value->lod_min_q16) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    const uint32_t selectors[16] = {
        value->cycle0_color_a,
        value->cycle0_color_b,
        value->cycle0_color_c,
        value->cycle0_color_d,
        value->cycle0_alpha_a,
        value->cycle0_alpha_b,
        value->cycle0_alpha_c,
        value->cycle0_alpha_d,
        value->cycle1_color_a,
        value->cycle1_color_b,
        value->cycle1_color_c,
        value->cycle1_color_d,
        value->cycle1_alpha_a,
        value->cycle1_alpha_b,
        value->cycle1_alpha_c,
        value->cycle1_alpha_d,
    };
    for (uint32_t index = 0u; index < 16u; index++) {
        if (!ge_source_scene_v6_valid_combiner_key(selectors[index])) {
            return GE_STATUS_INVALID_ARGUMENT;
        }
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_source_scene_v6_validate_draw_command(
    const GESourceDrawCommandV6 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_source_scene_v6_validate_common(
        &value->header, (uint32_t)sizeof(*value), value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->reserved0 != 0u || value->reserved1 != 0u) {
        return GE_STATUS_RESERVED_BITS;
    }
    if (value->command_kind == 0u || value->command_kind > GE_SOURCE_DRAW_V6_KIND_MAX ||
        (value->flags & ~GE_SOURCE_DRAW_V6_FLAG_MASK) != 0u ||
        !ge_source_scene_v6_valid_handle(value->draw_handle) ||
        value->instance_count == 0u ||
        value->vertex_count > UINT32_MAX - value->first_vertex ||
        value->index_count > UINT32_MAX - value->first_index ||
        value->scissor_width == 0u || value->scissor_height == 0u) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_source_scene_v6_validate_text_event(const GESourceTextEventV6 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_source_scene_v6_validate_common(
        &value->header, (uint32_t)sizeof(*value), value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->reserved0 != 0u || value->reserved1 != 0u) {
        return GE_STATUS_RESERVED_BITS;
    }
    if (value->event_kind == 0u || value->event_kind > GE_SOURCE_TEXT_V6_KIND_MAX ||
        (value->flags & ~GE_SOURCE_TEXT_V6_FLAG_MASK) != 0u ||
        !ge_source_scene_v6_valid_handle(value->text_handle) ||
        !ge_source_scene_v6_valid_handle(value->glyph_run_handle) ||
        value->scissor_width == 0u || value->scissor_height == 0u ||
        value->glyph_count > UINT32_C(65535)) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_source_scene_v6_validate_audio_event(const GESourceAudioEventV6 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_source_scene_v6_validate_common(
        &value->header, (uint32_t)sizeof(*value), value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->reserved0 != 0u || value->reserved1 != 0u || value->reserved2 != 0u ||
        value->reserved3 != 0u || value->reserved4 != 0u) {
        return GE_STATUS_RESERVED_BITS;
    }
    if (value->event_kind == 0u || value->event_kind > GE_SOURCE_AUDIO_V6_KIND_MAX ||
        (value->flags & ~GE_SOURCE_AUDIO_V6_FLAG_MASK) != 0u ||
        !ge_source_scene_v6_valid_handle(value->event_handle) ||
        !ge_source_scene_v6_valid_handle(value->asset_handle) ||
        value->slot > 10u || value->voice >= 24u || value->note > 127u ||
        value->velocity > 127u || value->loop_end < value->loop_begin) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_source_scene_v6_validate_frame_summary(
    const GESourceFrameSummaryV6 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_source_scene_v6_validate_common(
        &value->header, (uint32_t)sizeof(*value), value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->reserved0 != 0u || value->reserved1 != 0u) {
        return GE_STATUS_RESERVED_BITS;
    }
    if ((value->flags & ~GE_SOURCE_FRAME_V6_FLAG_MASK) != 0u ||
        value->screen > GE_SOURCE_FRAME_V6_SCREEN_MAX || value->pair_phase > 1u ||
        value->viewport_width == 0u || value->viewport_height == 0u ||
        value->logical_width == 0u || value->logical_height == 0u) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_source_scene_v6_validate_diagnostic(const GESourceDiagnosticV6 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_source_scene_v6_validate_common(
        &value->header, (uint32_t)sizeof(*value), value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->reserved0 != 0u || value->reserved1 != 0u) {
        return GE_STATUS_RESERVED_BITS;
    }
    if (value->diagnostic_kind == 0u ||
        value->diagnostic_kind > GE_SOURCE_DIAGNOSTIC_V6_KIND_MAX ||
        value->severity > GE_SOURCE_DIAGNOSTIC_V6_SEVERITY_MAX) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_source_scene_v6_page_bounds(uint32_t total_items,
                                          uint32_t item_size,
                                          uint32_t page_index,
                                          uint32_t page_capacity,
                                          uint32_t *first_item,
                                          uint32_t *item_count)
{
    if (first_item == NULL || item_count == NULL || item_size == 0u ||
        page_capacity == 0u || total_items > UINT32_MAX / item_size ||
        page_index > UINT32_MAX / page_capacity) {
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

GEStatusV1 ge_source_scene_v6_validate_page(const GESourceScenePageV6 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_source_scene_v6_validate_common(
        &value->header, (uint32_t)sizeof(*value), value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->reserved0 != 0u || value->reserved1 != 0u || value->reserved2 != 0u) {
        return GE_STATUS_RESERVED_BITS;
    }
    if (value->page_kind == 0u || value->page_kind > GE_SOURCE_PAGE_V6_MAX ||
        value->item_size == 0u || value->page_capacity == 0u ||
        value->first_item > value->total_items ||
        value->item_count > value->total_items - value->first_item ||
        (value->item_count != 0u && value->page_hash == 0u)) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    return GE_STATUS_OK;
}

/*
 * The macro keeps the nine typed copy-out entry points identical.  It also
 * validates the selected source page before writing either output buffer, so
 * malformed records cannot produce a partially valid page.
 */
#define GE_SOURCE_SCENE_V6_DEFINE_COPY_PAGE(NAME, TYPE, VALIDATE, HASH, KIND) \
GEStatusV1 NAME(const TYPE *items, uint32_t total_items, uint32_t page_index, \
               uint32_t page_capacity, TYPE *out_items, uint32_t out_capacity, \
               GESourceScenePageV6 *out_page) \
{ \
    if (out_page == NULL) { \
        return GE_STATUS_INVALID_ARGUMENT; \
    } \
    uint32_t first_item = 0u; \
    uint32_t item_count = 0u; \
    GEStatusV1 status = ge_source_scene_v6_page_bounds( \
        total_items, (uint32_t)sizeof(TYPE), page_index, page_capacity, \
        &first_item, &item_count); \
    if (status != GE_STATUS_OK || \
        (total_items != 0u && items == NULL) || out_capacity < item_count || \
        (item_count != 0u && out_items == NULL)) { \
        return status == GE_STATUS_OK ? GE_STATUS_INVALID_ARGUMENT : status; \
    } \
    for (uint32_t index = 0u; index < item_count; index++) { \
        status = VALIDATE(&items[first_item + index]); \
        if (status != GE_STATUS_OK) { \
            return status; \
        } \
    } \
    GESourceScenePageV6 page = {0}; \
    page.header.abi_version = GE_NATIVE_ABI_VERSION; \
    page.header.struct_size = (uint32_t)sizeof(page); \
    page.record_version = GE_SOURCE_SCENE_V6_RECORD_VERSION; \
    page.page_kind = (KIND); \
    page.page_index = page_index; \
    page.item_size = (uint32_t)sizeof(TYPE); \
    page.first_item = first_item; \
    page.item_count = item_count; \
    page.total_items = total_items; \
    page.page_capacity = page_capacity; \
    page.page_hash = GE_SOURCE_SCENE_V6_HASH_OFFSET; \
    for (uint32_t index = 0u; index < item_count; index++) { \
        page.page_hash = ge_source_scene_v6_hash_u64_step( \
            page.page_hash, HASH(&items[first_item + index])); \
    } \
    if (item_count != 0u) { \
        memmove(out_items, &items[first_item], \
                (size_t)item_count * sizeof(TYPE)); \
    } \
    *out_page = page; \
    return ge_source_scene_v6_validate_page(out_page); \
}

GE_SOURCE_SCENE_V6_DEFINE_COPY_PAGE(ge_source_scene_v6_copy_resource_page,
                                    GESourceResourceV6,
                                    ge_source_scene_v6_validate_resource,
                                    ge_source_scene_v6_hash_resource,
                                    GE_SOURCE_PAGE_V6_RESOURCES)
GE_SOURCE_SCENE_V6_DEFINE_COPY_PAGE(ge_source_scene_v6_copy_transform_page,
                                    GESourceTransformV6,
                                    ge_source_scene_v6_validate_transform,
                                    ge_source_scene_v6_hash_transform,
                                    GE_SOURCE_PAGE_V6_TRANSFORMS)
GE_SOURCE_SCENE_V6_DEFINE_COPY_PAGE(ge_source_scene_v6_copy_animation_pose_page,
                                    GESourceAnimationPoseV6,
                                    ge_source_scene_v6_validate_animation_pose,
                                    ge_source_scene_v6_hash_animation_pose,
                                    GE_SOURCE_PAGE_V6_ANIMATION_POSES)
GE_SOURCE_SCENE_V6_DEFINE_COPY_PAGE(ge_source_scene_v6_copy_vertex_page,
                                    GESourceVertexV6,
                                    ge_source_scene_v6_validate_vertex,
                                    ge_source_scene_v6_hash_vertex,
                                    GE_SOURCE_PAGE_V6_VERTICES)
GE_SOURCE_SCENE_V6_DEFINE_COPY_PAGE(ge_source_scene_v6_copy_index_page,
                                    GESourceIndexV6,
                                    ge_source_scene_v6_validate_index,
                                    ge_source_scene_v6_hash_index,
                                    GE_SOURCE_PAGE_V6_INDICES)
GE_SOURCE_SCENE_V6_DEFINE_COPY_PAGE(ge_source_scene_v6_copy_render_state_page,
                                    GESourceRenderStateV6,
                                    ge_source_scene_v6_validate_render_state,
                                    ge_source_scene_v6_hash_render_state,
                                    GE_SOURCE_PAGE_V6_RENDER_STATES)
GE_SOURCE_SCENE_V6_DEFINE_COPY_PAGE(ge_source_scene_v6_copy_draw_command_page,
                                    GESourceDrawCommandV6,
                                    ge_source_scene_v6_validate_draw_command,
                                    ge_source_scene_v6_hash_draw_command,
                                    GE_SOURCE_PAGE_V6_DRAW_COMMANDS)
GE_SOURCE_SCENE_V6_DEFINE_COPY_PAGE(ge_source_scene_v6_copy_text_event_page,
                                    GESourceTextEventV6,
                                    ge_source_scene_v6_validate_text_event,
                                    ge_source_scene_v6_hash_text_event,
                                    GE_SOURCE_PAGE_V6_TEXT_EVENTS)
GE_SOURCE_SCENE_V6_DEFINE_COPY_PAGE(ge_source_scene_v6_copy_audio_event_page,
                                    GESourceAudioEventV6,
                                    ge_source_scene_v6_validate_audio_event,
                                    ge_source_scene_v6_hash_audio_event,
                                    GE_SOURCE_PAGE_V6_AUDIO_EVENTS)
GE_SOURCE_SCENE_V6_DEFINE_COPY_PAGE(ge_source_scene_v6_copy_frame_summary_page,
                                    GESourceFrameSummaryV6,
                                    ge_source_scene_v6_validate_frame_summary,
                                    ge_source_scene_v6_hash_frame_summary,
                                    GE_SOURCE_PAGE_V6_FRAME_SUMMARIES)
GE_SOURCE_SCENE_V6_DEFINE_COPY_PAGE(ge_source_scene_v6_copy_diagnostic_page,
                                    GESourceDiagnosticV6,
                                    ge_source_scene_v6_validate_diagnostic,
                                    ge_source_scene_v6_hash_diagnostic,
                                    GE_SOURCE_PAGE_V6_DIAGNOSTICS)

#undef GE_SOURCE_SCENE_V6_DEFINE_COPY_PAGE
