#include "ge_source_scene_v6.h"

#include <assert.h>
#include <inttypes.h>
#include <stdio.h>
#include <string.h>

static void ge_source_scene_v6_init_header(GEAbiHeaderV1 *header,
                                           uint32_t struct_size)
{
    header->abi_version = GE_NATIVE_ABI_VERSION;
    header->struct_size = struct_size;
}

static void ge_source_scene_v6_fill_matrix(int32_t matrix_q16[16])
{
    for (uint32_t index = 0u; index < 16u; index++) {
        matrix_q16[index] = (index % 5u) == 0u ? INT32_C(65536) : 0;
    }
}

static GESourceResourceV6 ge_source_scene_v6_make_resource(uint32_t handle)
{
    GESourceResourceV6 value = {0};
    ge_source_scene_v6_init_header(&value.header, (uint32_t)sizeof(value));
    value.record_version = GE_SOURCE_SCENE_V6_RECORD_VERSION;
    value.resource_kind = GE_SOURCE_RESOURCE_V6_TEXTURE;
    value.flags = GE_SOURCE_RESOURCE_V6_FLAG_RESIDENT |
                  GE_SOURCE_RESOURCE_V6_FLAG_MIP_CHAIN;
    value.handle = handle;
    value.source_id = UINT32_C(0x1000) + handle;
    value.format = GE_SOURCE_RESOURCE_V6_FORMAT_RGBA16;
    value.width = 64u;
    value.height = 32u;
    value.depth = 1u;
    value.mip_count = 3u;
    value.level_count = 3u;
    value.byte_size = 2730u;
    value.content_hash = UINT64_C(0x0123456789abcdef) + handle;
    value.provenance_hash = UINT64_C(0xfedcba9876543210) - handle;
    return value;
}

static GESourceTransformV6 ge_source_scene_v6_make_transform(void)
{
    GESourceTransformV6 value = {0};
    ge_source_scene_v6_init_header(&value.header, (uint32_t)sizeof(value));
    value.record_version = GE_SOURCE_SCENE_V6_RECORD_VERSION;
    value.transform_kind = GE_SOURCE_TRANSFORM_V6_MODELVIEW;
    value.flags = GE_SOURCE_TRANSFORM_V6_FLAG_SOURCE_QUANTIZED |
                  GE_SOURCE_TRANSFORM_V6_FLAG_INTERPOLATABLE;
    value.handle = 11u;
    value.parent_handle = 10u;
    value.source_node = 0x42u;
    value.viewport_id = 1u;
    ge_source_scene_v6_fill_matrix(value.matrix_q16);
    return value;
}

static GESourceAnimationPoseV6 ge_source_scene_v6_make_pose(void)
{
    GESourceAnimationPoseV6 value = {0};
    ge_source_scene_v6_init_header(&value.header, (uint32_t)sizeof(value));
    value.record_version = GE_SOURCE_SCENE_V6_RECORD_VERSION;
    value.pose_handle = 21u;
    value.skeleton_handle = 22u;
    value.node_handle = 23u;
    value.parent_handle = 24u;
    value.flags = GE_SOURCE_POSE_V6_FLAG_INTERPOLATABLE;
    value.animation_tick = 180u;
    value.translation_q16[0] = 65536;
    value.translation_q16[1] = -32768;
    value.translation_q16[2] = 0;
    value.rotation_q16[3] = 65536;
    value.scale_q16[0] = 65536;
    value.scale_q16[1] = 65536;
    value.scale_q16[2] = 65536;
    value.pose_hash = UINT64_C(0x1111222233334444);
    return value;
}

static GESourceVertexV6 ge_source_scene_v6_make_vertex(uint32_t handle)
{
    GESourceVertexV6 value = {0};
    ge_source_scene_v6_init_header(&value.header, (uint32_t)sizeof(value));
    value.record_version = GE_SOURCE_SCENE_V6_RECORD_VERSION;
    value.handle = handle;
    value.flags = GE_SOURCE_VERTEX_V6_FLAG_SOURCE_QUANTIZED;
    value.position_q16[0] = (int32_t)handle << 16;
    value.position_q16[1] = -32768;
    value.position_q16[2] = 131072;
    value.texcoord_q16[0] = 65536;
    value.texcoord_q16[1] = 32768;
    value.normal_q16[2] = 65536;
    value.color_rgba = 0xffc080ffu;
    value.source_index = handle - 1u;
    return value;
}

static GESourceIndexV6 ge_source_scene_v6_make_index(void)
{
    GESourceIndexV6 value = {0};
    ge_source_scene_v6_init_header(&value.header, (uint32_t)sizeof(value));
    value.record_version = GE_SOURCE_SCENE_V6_RECORD_VERSION;
    value.handle = 71u;
    value.flags = GE_SOURCE_INDEX_V6_FLAG_SOURCE_ORDERED;
    value.vertex0 = 0u;
    value.vertex1 = 1u;
    value.vertex2 = 2u;
    value.source_index = 13u;
    return value;
}

static GESourceRenderStateV6 ge_source_scene_v6_make_render_state(void)
{
    GESourceRenderStateV6 value = {0};
    ge_source_scene_v6_init_header(&value.header, (uint32_t)sizeof(value));
    value.record_version = GE_SOURCE_SCENE_V6_RECORD_VERSION;
    value.state_handle = 31u;
    value.flags = GE_SOURCE_RENDER_STATE_V6_FLAG_DEPTH_TEST |
                  GE_SOURCE_RENDER_STATE_V6_FLAG_DEPTH_WRITE |
                  GE_SOURCE_RENDER_STATE_V6_FLAG_FOG;
    value.material_handle = 32u;
    value.combiner_cycle_count = 2u;
    value.cycle0_color_a = GE_SOURCE_COMBINER_V6_KEY_TEXEL0;
    value.cycle0_color_b = GE_SOURCE_COMBINER_V6_KEY_TEXEL1;
    value.cycle0_color_c = GE_SOURCE_COMBINER_V6_KEY_PRIMITIVE;
    value.cycle0_color_d = GE_SOURCE_COMBINER_V6_KEY_SHADE;
    value.cycle0_alpha_a = GE_SOURCE_COMBINER_V6_KEY_TEXEL0;
    value.cycle0_alpha_b = GE_SOURCE_COMBINER_V6_KEY_ENVIRONMENT;
    value.cycle0_alpha_c = GE_SOURCE_COMBINER_V6_KEY_ONE;
    value.cycle0_alpha_d = GE_SOURCE_COMBINER_V6_KEY_ZERO;
    value.cycle1_color_a = GE_SOURCE_COMBINER_V6_KEY_COMBINED;
    value.cycle1_color_b = GE_SOURCE_COMBINER_V6_KEY_PRIMITIVE;
    value.cycle1_color_c = GE_SOURCE_COMBINER_V6_KEY_ENVIRONMENT;
    value.cycle1_color_d = GE_SOURCE_COMBINER_V6_KEY_ONE;
    value.cycle1_alpha_a = GE_SOURCE_COMBINER_V6_KEY_LOD_FRACTION;
    value.cycle1_alpha_b = GE_SOURCE_COMBINER_V6_KEY_PRIMITIVE_LOD_FRACTION;
    value.cycle1_alpha_c = GE_SOURCE_COMBINER_V6_KEY_NOISE;
    value.cycle1_alpha_d = GE_SOURCE_COMBINER_V6_KEY_COMBINED_ALPHA;
    value.primitive_rgba = 0xffffffffu;
    value.environment_rgba = 0x10203040u;
    value.fog_rgba = 0x50607080u;
    value.blend_rgba = 0x90a0b0c0u;
    value.depth_mode = GE_SOURCE_DEPTH_V6_LEQUAL;
    value.alpha_mode = GE_SOURCE_ALPHA_V6_THRESHOLD;
    value.coverage_mode = GE_SOURCE_COVERAGE_V6_CLAMP;
    value.cull_mode = GE_SOURCE_CULL_V6_BACK;
    value.filter_mode = GE_SOURCE_FILTER_V6_BILINEAR;
    value.wrap_s = GE_SOURCE_WRAP_V6_REPEAT;
    value.wrap_t = GE_SOURCE_WRAP_V6_MIRROR;
    value.lod_min_q16 = 0u;
    value.lod_max_q16 = 2u << 16;
    value.raw_othermode_h = 0x12345678u;
    value.raw_othermode_l = 0x9abcdef0u;
    value.raw_render_mode = 0x00abcdefu;
    value.raw_blender_a = 1u;
    value.raw_blender_b = 2u;
    value.raw_blender_c = 3u;
    value.raw_blender_d = 4u;
    return value;
}

static GESourceDrawCommandV6 ge_source_scene_v6_make_draw(void)
{
    GESourceDrawCommandV6 value = {0};
    ge_source_scene_v6_init_header(&value.header, (uint32_t)sizeof(value));
    value.record_version = GE_SOURCE_SCENE_V6_RECORD_VERSION;
    value.command_kind = GE_SOURCE_DRAW_V6_TRIANGLES;
    value.flags = GE_SOURCE_DRAW_V6_FLAG_OPAQUE |
                  GE_SOURCE_DRAW_V6_FLAG_SOURCE_ORDERED;
    value.draw_handle = 41u;
    value.transform_handle = 11u;
    value.resource_handle = 1u;
    value.render_state_handle = 31u;
    value.first_vertex = 4u;
    value.vertex_count = 12u;
    value.first_index = 2u;
    value.index_count = 30u;
    value.instance_count = 1u;
    value.sort_key = 0x80000001u;
    value.depth_q16 = 65536;
    value.scissor_width = 320u;
    value.scissor_height = 240u;
    value.draw_hash = UINT64_C(0xabcdef0123456789);
    return value;
}

static GESourceTextEventV6 ge_source_scene_v6_make_text(void)
{
    GESourceTextEventV6 value = {0};
    ge_source_scene_v6_init_header(&value.header, (uint32_t)sizeof(value));
    value.record_version = GE_SOURCE_SCENE_V6_RECORD_VERSION;
    value.event_kind = GE_SOURCE_TEXT_V6_GLYPH_RUN;
    value.flags = GE_SOURCE_TEXT_V6_FLAG_SOURCE_FONT |
                  GE_SOURCE_TEXT_V6_FLAG_SHADOW;
    value.text_handle = 51u;
    value.glyph_run_handle = 52u;
    value.x_q16 = 10 << 16;
    value.y_q16 = 20 << 16;
    value.scale_x_q16 = 65536;
    value.scale_y_q16 = 65536;
    value.color_rgba = 0xffffffffu;
    value.scissor_width = 320u;
    value.scissor_height = 240u;
    value.glyph_count = 12u;
    value.string_hash = UINT64_C(0x9988776655443322);
    return value;
}

static GESourceAudioEventV6 ge_source_scene_v6_make_audio(void)
{
    GESourceAudioEventV6 value = {0};
    ge_source_scene_v6_init_header(&value.header, (uint32_t)sizeof(value));
    value.record_version = GE_SOURCE_SCENE_V6_RECORD_VERSION;
    value.event_kind = GE_SOURCE_AUDIO_V6_SFX;
    value.flags = GE_SOURCE_AUDIO_V6_FLAG_SOURCE_ANCHOR;
    value.event_handle = 61u;
    value.asset_handle = 62u;
    value.slot = 1u;
    value.voice = 2u;
    value.note = 60u;
    value.velocity = 100u;
    value.pitch_q16 = 65536;
    value.pan_q16 = -16384;
    value.gain_q16 = 65536;
    value.sample_index = 735u;
    value.duration_frames = 2205u;
    value.loop_begin = 0u;
    value.loop_end = 0u;
    value.event_hash = UINT64_C(0x1234567890abcdef);
    return value;
}

static GESourceFrameSummaryV6 ge_source_scene_v6_make_frame(void)
{
    GESourceFrameSummaryV6 value = {0};
    ge_source_scene_v6_init_header(&value.header, (uint32_t)sizeof(value));
    value.record_version = GE_SOURCE_SCENE_V6_RECORD_VERSION;
    value.flags = GE_SOURCE_FRAME_V6_FLAG_PRESENTABLE |
                  GE_SOURCE_FRAME_V6_FLAG_SOURCE_ANCHOR |
                  GE_SOURCE_FRAME_V6_FLAG_HAS_UI;
    value.screen = GE_SOURCE_FRAME_V6_SCREEN_GOLDENEYE;
    value.subphase = 2u;
    value.native_tick = 241u;
    value.reference_tick = 120u;
    value.pair_phase = 1u;
    value.viewport_width = 1280u;
    value.viewport_height = 960u;
    value.logical_width = 440u;
    value.logical_height = 330u;
    value.transform_count = 2u;
    value.resource_count = 4u;
    value.pose_count = 1u;
    value.vertex_count = 24u;
    value.index_count = 12u;
    value.draw_count = 8u;
    value.render_state_count = 3u;
    value.text_count = 1u;
    value.audio_count = 1u;
    value.diagnostic_count = 0u;
    value.unsupported_visible_count = 0u;
    value.scene_hash = UINT64_C(0x1111111111111111);
    value.render_hash = UINT64_C(0x2222222222222222);
    value.state_hash = UINT64_C(0x3333333333333333);
    value.audio_hash = UINT64_C(0x4444444444444444);
    value.frame_hash = UINT64_C(0x5555555555555555);
    return value;
}

static GESourceDiagnosticV6 ge_source_scene_v6_make_diagnostic(void)
{
    GESourceDiagnosticV6 value = {0};
    ge_source_scene_v6_init_header(&value.header, (uint32_t)sizeof(value));
    value.record_version = GE_SOURCE_SCENE_V6_RECORD_VERSION;
    value.diagnostic_kind = GE_SOURCE_DIAGNOSTIC_V6_UNSUPPORTED_COMMAND;
    value.severity = GE_SOURCE_DIAGNOSTIC_V6_SEVERITY_WARNING;
    value.code = 0xdeadbeefu;
    value.source_id = 0x1234u;
    value.command_id = 0x5678u;
    value.first_bad_index = 9u;
    value.item_count = 2u;
    value.detail_hash = UINT64_C(0x0badf00d0badf00d);
    return value;
}

static void ge_source_scene_v6_expect_valid_records(void)
{
    GESourceResourceV6 resource = ge_source_scene_v6_make_resource(1u);
    GESourceTransformV6 transform = ge_source_scene_v6_make_transform();
    GESourceAnimationPoseV6 pose = ge_source_scene_v6_make_pose();
    GESourceVertexV6 vertex = ge_source_scene_v6_make_vertex(81u);
    GESourceIndexV6 index = ge_source_scene_v6_make_index();
    GESourceRenderStateV6 state = ge_source_scene_v6_make_render_state();
    GESourceDrawCommandV6 draw = ge_source_scene_v6_make_draw();
    GESourceTextEventV6 text = ge_source_scene_v6_make_text();
    GESourceAudioEventV6 audio = ge_source_scene_v6_make_audio();
    GESourceFrameSummaryV6 frame = ge_source_scene_v6_make_frame();
    GESourceDiagnosticV6 diagnostic = ge_source_scene_v6_make_diagnostic();

    assert(ge_source_scene_v6_validate_resource(&resource) == GE_STATUS_OK);
    assert(ge_source_scene_v6_validate_transform(&transform) == GE_STATUS_OK);
    assert(ge_source_scene_v6_validate_animation_pose(&pose) == GE_STATUS_OK);
    assert(ge_source_scene_v6_validate_vertex(&vertex) == GE_STATUS_OK);
    assert(ge_source_scene_v6_validate_index(&index) == GE_STATUS_OK);
    assert(ge_source_scene_v6_validate_render_state(&state) == GE_STATUS_OK);
    assert(ge_source_scene_v6_validate_draw_command(&draw) == GE_STATUS_OK);
    assert(ge_source_scene_v6_validate_text_event(&text) == GE_STATUS_OK);
    assert(ge_source_scene_v6_validate_audio_event(&audio) == GE_STATUS_OK);
    assert(ge_source_scene_v6_validate_frame_summary(&frame) == GE_STATUS_OK);
    assert(ge_source_scene_v6_validate_diagnostic(&diagnostic) == GE_STATUS_OK);

    assert(ge_source_scene_v6_hash_resource(&resource) == UINT64_C(0xa9e70f2c9b432c9));
    assert(ge_source_scene_v6_hash_transform(&transform) == UINT64_C(0x2b7a4629ed8feff3));
    assert(ge_source_scene_v6_hash_animation_pose(&pose) == UINT64_C(0x03aa63a6a7e8c8c6));
    assert(ge_source_scene_v6_hash_vertex(&vertex) == UINT64_C(0x22e0dcf3ca3d409f));
    assert(ge_source_scene_v6_hash_index(&index) == UINT64_C(0x38ce5a3848cb2527));
    assert(ge_source_scene_v6_hash_render_state(&state) == UINT64_C(0x5dfb0b93f9e0864a));
    assert(ge_source_scene_v6_hash_draw_command(&draw) == UINT64_C(0xa3a7ce59eb90d46d));
    assert(ge_source_scene_v6_hash_text_event(&text) == UINT64_C(0x304b0d9938c5b849));
    assert(ge_source_scene_v6_hash_audio_event(&audio) == UINT64_C(0x544ed5ca59f02d55));
    assert(ge_source_scene_v6_hash_frame_summary(&frame) == UINT64_C(0xaf0ac751f8de4002));
    assert(ge_source_scene_v6_hash_diagnostic(&diagnostic) == UINT64_C(0xd1ba824013d2175e));

    printf("resource_hash=%" PRIx64 "\n", ge_source_scene_v6_hash_resource(&resource));
    printf("transform_hash=%" PRIx64 "\n", ge_source_scene_v6_hash_transform(&transform));
    printf("pose_hash=%" PRIx64 "\n", ge_source_scene_v6_hash_animation_pose(&pose));
    printf("vertex_hash=%" PRIx64 "\n", ge_source_scene_v6_hash_vertex(&vertex));
    printf("index_hash=%" PRIx64 "\n", ge_source_scene_v6_hash_index(&index));
    printf("render_state_hash=%" PRIx64 "\n", ge_source_scene_v6_hash_render_state(&state));
    printf("draw_hash=%" PRIx64 "\n", ge_source_scene_v6_hash_draw_command(&draw));
    printf("text_hash=%" PRIx64 "\n", ge_source_scene_v6_hash_text_event(&text));
    printf("audio_hash=%" PRIx64 "\n", ge_source_scene_v6_hash_audio_event(&audio));
    printf("frame_hash=%" PRIx64 "\n", ge_source_scene_v6_hash_frame_summary(&frame));
    printf("diagnostic_hash=%" PRIx64 "\n", ge_source_scene_v6_hash_diagnostic(&diagnostic));
}

static void ge_source_scene_v6_expect_page_copy(void)
{
    GESourceResourceV6 source[3] = {
        ge_source_scene_v6_make_resource(1u),
        ge_source_scene_v6_make_resource(2u),
        ge_source_scene_v6_make_resource(3u),
    };
    GESourceResourceV6 output[2] = {{0}, {0}};
    GESourceScenePageV6 page = {0};
    GEStatusV1 status = ge_source_scene_v6_copy_resource_page(
        source, 3u, 1u, 2u, output, 2u, &page);
    assert(status == GE_STATUS_OK);
    assert(page.page_kind == GE_SOURCE_PAGE_V6_RESOURCES);
    assert(page.page_index == 1u && page.first_item == 2u && page.item_count == 1u);
    assert(output[0].handle == 3u);
    assert(ge_source_scene_v6_validate_page(&page) == GE_STATUS_OK);

    output[0].handle = 0xfeedu;
    status = ge_source_scene_v6_copy_resource_page(
        source, 3u, 0u, 2u, output, 1u, &page);
    assert(status == GE_STATUS_INVALID_ARGUMENT);
    assert(output[0].handle == 0xfeedu);

    GESourceScenePageV6 untouched = page;
    source[1].reserved0 = 1u;
    status = ge_source_scene_v6_copy_resource_page(
        source, 3u, 0u, 2u, output, 2u, &page);
    assert(status == GE_STATUS_RESERVED_BITS);
    assert(memcmp(&page, &untouched, sizeof(page)) == 0);

    assert(ge_source_scene_v6_page_bounds(1u, 0u, 0u, 1u, NULL, NULL) ==
           GE_STATUS_INVALID_ARGUMENT);
    assert(ge_source_scene_v6_page_bounds(UINT32_MAX, 2u, 0u, 1u, NULL, NULL) ==
           GE_STATUS_INVALID_ARGUMENT);
    uint32_t first = 0u;
    uint32_t count = 0u;
    assert(ge_source_scene_v6_page_bounds(8u, 80u, 2u, 4u, &first, &count) ==
           GE_STATUS_OK);
    assert(first == 8u && count == 0u);
    assert(ge_source_scene_v6_copy_resource_page(
               NULL, 0u, 0u, 4u, NULL, 0u, &page) == GE_STATUS_OK);
    assert(page.item_count == 0u);
}

static void ge_source_scene_v6_expect_all_page_types(void)
{
    GESourceTransformV6 transform = ge_source_scene_v6_make_transform();
    GESourceAnimationPoseV6 pose = ge_source_scene_v6_make_pose();
    GESourceVertexV6 vertex = ge_source_scene_v6_make_vertex(81u);
    GESourceIndexV6 index = ge_source_scene_v6_make_index();
    GESourceRenderStateV6 state = ge_source_scene_v6_make_render_state();
    GESourceDrawCommandV6 draw = ge_source_scene_v6_make_draw();
    GESourceTextEventV6 text = ge_source_scene_v6_make_text();
    GESourceAudioEventV6 audio = ge_source_scene_v6_make_audio();
    GESourceFrameSummaryV6 frame = ge_source_scene_v6_make_frame();
    GESourceDiagnosticV6 diagnostic = ge_source_scene_v6_make_diagnostic();
    GESourceScenePageV6 page = {0};

    assert(ge_source_scene_v6_copy_transform_page(
               &transform, 1u, 0u, 1u, &transform, 1u, &page) == GE_STATUS_OK);
    assert(page.page_kind == GE_SOURCE_PAGE_V6_TRANSFORMS);
    assert(ge_source_scene_v6_copy_animation_pose_page(
               &pose, 1u, 0u, 1u, &pose, 1u, &page) == GE_STATUS_OK);
    assert(page.page_kind == GE_SOURCE_PAGE_V6_ANIMATION_POSES);
    assert(ge_source_scene_v6_copy_vertex_page(
               &vertex, 1u, 0u, 1u, &vertex, 1u, &page) == GE_STATUS_OK);
    assert(page.page_kind == GE_SOURCE_PAGE_V6_VERTICES);
    assert(ge_source_scene_v6_copy_index_page(
               &index, 1u, 0u, 1u, &index, 1u, &page) == GE_STATUS_OK);
    assert(page.page_kind == GE_SOURCE_PAGE_V6_INDICES);
    assert(ge_source_scene_v6_copy_render_state_page(
               &state, 1u, 0u, 1u, &state, 1u, &page) == GE_STATUS_OK);
    assert(page.page_kind == GE_SOURCE_PAGE_V6_RENDER_STATES);
    assert(ge_source_scene_v6_copy_draw_command_page(
               &draw, 1u, 0u, 1u, &draw, 1u, &page) == GE_STATUS_OK);
    assert(page.page_kind == GE_SOURCE_PAGE_V6_DRAW_COMMANDS);
    assert(ge_source_scene_v6_copy_text_event_page(
               &text, 1u, 0u, 1u, &text, 1u, &page) == GE_STATUS_OK);
    assert(page.page_kind == GE_SOURCE_PAGE_V6_TEXT_EVENTS);
    assert(ge_source_scene_v6_copy_audio_event_page(
               &audio, 1u, 0u, 1u, &audio, 1u, &page) == GE_STATUS_OK);
    assert(page.page_kind == GE_SOURCE_PAGE_V6_AUDIO_EVENTS);
    assert(ge_source_scene_v6_copy_frame_summary_page(
               &frame, 1u, 0u, 1u, &frame, 1u, &page) == GE_STATUS_OK);
    assert(page.page_kind == GE_SOURCE_PAGE_V6_FRAME_SUMMARIES);
    assert(ge_source_scene_v6_copy_diagnostic_page(
               &diagnostic, 1u, 0u, 1u, &diagnostic, 1u, &page) == GE_STATUS_OK);
    assert(page.page_kind == GE_SOURCE_PAGE_V6_DIAGNOSTICS);
}

static void ge_source_scene_v6_expect_malformed_records(void)
{
    GESourceResourceV6 resource = ge_source_scene_v6_make_resource(1u);
    resource.header.abi_version = 0u;
    assert(ge_source_scene_v6_validate_resource(&resource) == GE_STATUS_INVALID_VERSION);
    resource = ge_source_scene_v6_make_resource(1u);
    resource.header.struct_size = 1u;
    assert(ge_source_scene_v6_validate_resource(&resource) == GE_STATUS_INVALID_SIZE);
    resource = ge_source_scene_v6_make_resource(1u);
    resource.record_version = 99u;
    assert(ge_source_scene_v6_validate_resource(&resource) == GE_STATUS_INVALID_VERSION);
    resource = ge_source_scene_v6_make_resource(1u);
    resource.reserved1 = 1u;
    assert(ge_source_scene_v6_validate_resource(&resource) == GE_STATUS_RESERVED_BITS);
    resource = ge_source_scene_v6_make_resource(0u);
    assert(ge_source_scene_v6_validate_resource(&resource) == GE_STATUS_INVALID_ARGUMENT);
    assert(ge_source_scene_v6_validate_resource(NULL) == GE_STATUS_INVALID_ARGUMENT);

    GESourceDrawCommandV6 draw = ge_source_scene_v6_make_draw();
    draw.vertex_count = UINT32_MAX;
    draw.first_vertex = 1u;
    assert(ge_source_scene_v6_validate_draw_command(&draw) == GE_STATUS_INVALID_ARGUMENT);
    draw = ge_source_scene_v6_make_draw();
    draw.scissor_width = 0u;
    assert(ge_source_scene_v6_validate_draw_command(&draw) == GE_STATUS_INVALID_ARGUMENT);

    GESourceRenderStateV6 state = ge_source_scene_v6_make_render_state();
    state.lod_min_q16 = 4u;
    state.lod_max_q16 = 3u;
    assert(ge_source_scene_v6_validate_render_state(&state) == GE_STATUS_INVALID_ARGUMENT);
    state = ge_source_scene_v6_make_render_state();
    state.cycle1_alpha_d = GE_SOURCE_COMBINER_V6_KEY_MAX + 1u;
    assert(ge_source_scene_v6_validate_render_state(&state) == GE_STATUS_INVALID_ARGUMENT);

    GESourceAudioEventV6 audio = ge_source_scene_v6_make_audio();
    audio.voice = 24u;
    assert(ge_source_scene_v6_validate_audio_event(&audio) == GE_STATUS_INVALID_ARGUMENT);

    GESourceVertexV6 vertex = ge_source_scene_v6_make_vertex(81u);
    vertex.reserved0 = 1u;
    assert(ge_source_scene_v6_validate_vertex(&vertex) == GE_STATUS_RESERVED_BITS);
    GESourceIndexV6 index = ge_source_scene_v6_make_index();
    index.flags = 0x80u;
    assert(ge_source_scene_v6_validate_index(&index) == GE_STATUS_INVALID_ARGUMENT);

    GESourceFrameSummaryV6 frame = ge_source_scene_v6_make_frame();
    frame.pair_phase = 2u;
    assert(ge_source_scene_v6_validate_frame_summary(&frame) == GE_STATUS_INVALID_ARGUMENT);
}

int main(void)
{
    ge_source_scene_v6_expect_valid_records();
    ge_source_scene_v6_expect_page_copy();
    ge_source_scene_v6_expect_all_page_types();
    ge_source_scene_v6_expect_malformed_records();
    printf("goldeneye_source_scene_v6_smoke: PASS\n");
    return 0;
}
