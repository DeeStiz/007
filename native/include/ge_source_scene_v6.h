#ifndef GE_SOURCE_SCENE_V6_H
#define GE_SOURCE_SCENE_V6_H

/*
 * Additive source-scene contract for the native renderer.
 *
 * The records in this header deliberately describe source semantics rather
 * than N64 implementation objects.  They contain fixed-width values and
 * deterministic handles only.  Pointers are accepted solely by the
 * call-time copy/validation APIs below and are never retained in a record.
 *
 * This contract is independent from, and does not modify, the frozen V1-V5
 * contracts.  GEAbiHeaderV1 remains the common boundary envelope.
 */

#include <stdint.h>

#include "ge_native_foundation.h"

#ifdef __cplusplus
extern "C" {
#endif

#define GE_SOURCE_SCENE_V6_ABI_VERSION ((uint32_t)6u)
#define GE_SOURCE_SCENE_V6_RECORD_VERSION ((uint32_t)1u)

#define GE_SOURCE_SCENE_V6_HANDLE_INVALID ((uint32_t)0u)

/* Resource descriptor kinds. */
#define GE_SOURCE_RESOURCE_V6_TEXTURE ((uint32_t)1u)
#define GE_SOURCE_RESOURCE_V6_MODEL ((uint32_t)2u)
#define GE_SOURCE_RESOURCE_V6_FONT ((uint32_t)3u)
#define GE_SOURCE_RESOURCE_V6_ICON ((uint32_t)4u)
#define GE_SOURCE_RESOURCE_V6_AUDIO ((uint32_t)5u)
#define GE_SOURCE_RESOURCE_V6_ANIMATION ((uint32_t)6u)
#define GE_SOURCE_RESOURCE_V6_BACKGROUND ((uint32_t)7u)
#define GE_SOURCE_RESOURCE_V6_PALETTE ((uint32_t)8u)
#define GE_SOURCE_RESOURCE_V6_KIND_MAX GE_SOURCE_RESOURCE_V6_PALETTE

#define GE_SOURCE_RESOURCE_V6_FLAG_RESIDENT ((uint32_t)1u << 0)
#define GE_SOURCE_RESOURCE_V6_FLAG_MIP_CHAIN ((uint32_t)1u << 1)
#define GE_SOURCE_RESOURCE_V6_FLAG_PALETTE ((uint32_t)1u << 2)
#define GE_SOURCE_RESOURCE_V6_FLAG_SOURCE_ORDERED ((uint32_t)1u << 3)
#define GE_SOURCE_RESOURCE_V6_FLAG_PRIVATE_ASSET ((uint32_t)1u << 4)
#define GE_SOURCE_RESOURCE_V6_FLAG_MASK ((uint32_t)0x1fu)

/* Decoded source formats; these are not host pixel-format identifiers. */
#define GE_SOURCE_RESOURCE_V6_FORMAT_NONE ((uint32_t)0u)
#define GE_SOURCE_RESOURCE_V6_FORMAT_RGBA16 ((uint32_t)1u)
#define GE_SOURCE_RESOURCE_V6_FORMAT_RGBA32 ((uint32_t)2u)
#define GE_SOURCE_RESOURCE_V6_FORMAT_CI8 ((uint32_t)3u)
#define GE_SOURCE_RESOURCE_V6_FORMAT_CI4 ((uint32_t)4u)
#define GE_SOURCE_RESOURCE_V6_FORMAT_IA8 ((uint32_t)5u)
#define GE_SOURCE_RESOURCE_V6_FORMAT_I8 ((uint32_t)6u)
#define GE_SOURCE_RESOURCE_V6_FORMAT_I4 ((uint32_t)7u)
#define GE_SOURCE_RESOURCE_V6_FORMAT_IA4 ((uint32_t)8u)
#define GE_SOURCE_RESOURCE_V6_FORMAT_IA16 ((uint32_t)9u)
#define GE_SOURCE_RESOURCE_V6_FORMAT_MAX GE_SOURCE_RESOURCE_V6_FORMAT_IA16

/* Transform descriptor kinds. */
#define GE_SOURCE_TRANSFORM_V6_MODELVIEW ((uint32_t)1u)
#define GE_SOURCE_TRANSFORM_V6_PROJECTION ((uint32_t)2u)
#define GE_SOURCE_TRANSFORM_V6_VIEWPORT ((uint32_t)3u)
#define GE_SOURCE_TRANSFORM_V6_BONE ((uint32_t)4u)
#define GE_SOURCE_TRANSFORM_V6_CLIP_COMPOSITE ((uint32_t)5u)
#define GE_SOURCE_TRANSFORM_V6_KIND_MAX GE_SOURCE_TRANSFORM_V6_CLIP_COMPOSITE

#define GE_SOURCE_TRANSFORM_V6_FLAG_SOURCE_QUANTIZED ((uint32_t)1u << 0)
#define GE_SOURCE_TRANSFORM_V6_FLAG_INTERPOLATABLE ((uint32_t)1u << 1)
#define GE_SOURCE_TRANSFORM_V6_FLAG_REFLECTION_TEXGEN ((uint32_t)1u << 2)
#define GE_SOURCE_TRANSFORM_V6_FLAG_CLIP_COMPOSITE ((uint32_t)1u << 3)
#define GE_SOURCE_TRANSFORM_V6_FLAG_MASK ((uint32_t)0x0fu)

/* Animation pose flags. */
#define GE_SOURCE_POSE_V6_FLAG_ROOT ((uint32_t)1u << 0)
#define GE_SOURCE_POSE_V6_FLAG_INTERPOLATABLE ((uint32_t)1u << 1)
#define GE_SOURCE_POSE_V6_FLAG_WEAPON_ATTACHMENT ((uint32_t)1u << 2)
#define GE_SOURCE_POSE_V6_FLAG_MASK ((uint32_t)0x07u)

/* Render-state flags and decoded raster selectors. */
#define GE_SOURCE_RENDER_STATE_V6_FLAG_DEPTH_TEST ((uint32_t)1u << 0)
#define GE_SOURCE_RENDER_STATE_V6_FLAG_DEPTH_WRITE ((uint32_t)1u << 1)
#define GE_SOURCE_RENDER_STATE_V6_FLAG_ALPHA_COMPARE ((uint32_t)1u << 2)
#define GE_SOURCE_RENDER_STATE_V6_FLAG_FOG ((uint32_t)1u << 3)
#define GE_SOURCE_RENDER_STATE_V6_FLAG_COVERAGE ((uint32_t)1u << 4)
#define GE_SOURCE_RENDER_STATE_V6_FLAG_ANTIALIAS ((uint32_t)1u << 5)
#define GE_SOURCE_RENDER_STATE_V6_FLAG_COVERAGE_SAVE ((uint32_t)1u << 6)
#define GE_SOURCE_RENDER_STATE_V6_FLAG_MASK ((uint32_t)0x7fu)

/*
 * Normalized combiner selectors.  These keys have identical meaning in every
 * color and alpha A/B/C/D slot; they are deliberately not raw N64 mux
 * encodings.  A color slot consumes the source color and an alpha slot
 * consumes the source alpha (scalar keys are broadcast when used by color).
 * Raw othermode/combiner evidence remains in the source lowerer's private
 * records and is not substituted into these normalized fields.
 */
#define GE_SOURCE_COMBINER_V6_KEY_COMBINED ((uint32_t)0u)
#define GE_SOURCE_COMBINER_V6_KEY_TEXEL0 ((uint32_t)1u)
#define GE_SOURCE_COMBINER_V6_KEY_TEXEL1 ((uint32_t)2u)
#define GE_SOURCE_COMBINER_V6_KEY_PRIMITIVE ((uint32_t)3u)
#define GE_SOURCE_COMBINER_V6_KEY_SHADE ((uint32_t)4u)
#define GE_SOURCE_COMBINER_V6_KEY_ENVIRONMENT ((uint32_t)5u)
#define GE_SOURCE_COMBINER_V6_KEY_ONE ((uint32_t)6u)
#define GE_SOURCE_COMBINER_V6_KEY_ZERO ((uint32_t)7u)
#define GE_SOURCE_COMBINER_V6_KEY_NOISE ((uint32_t)8u)
#define GE_SOURCE_COMBINER_V6_KEY_LOD_FRACTION ((uint32_t)9u)
#define GE_SOURCE_COMBINER_V6_KEY_PRIMITIVE_LOD_FRACTION ((uint32_t)10u)
#define GE_SOURCE_COMBINER_V6_KEY_K4 ((uint32_t)11u)
#define GE_SOURCE_COMBINER_V6_KEY_K5 ((uint32_t)12u)
#define GE_SOURCE_COMBINER_V6_KEY_CENTER ((uint32_t)13u)
#define GE_SOURCE_COMBINER_V6_KEY_SCALE ((uint32_t)14u)
#define GE_SOURCE_COMBINER_V6_KEY_COMBINED_ALPHA ((uint32_t)15u)
#define GE_SOURCE_COMBINER_V6_KEY_MAX GE_SOURCE_COMBINER_V6_KEY_COMBINED_ALPHA
#define GE_SOURCE_COMBINER_V6_KEY_MASK ((uint32_t)0x0fu)

#define GE_SOURCE_DEPTH_V6_DISABLED ((uint32_t)0u)
#define GE_SOURCE_DEPTH_V6_LESS ((uint32_t)1u)
#define GE_SOURCE_DEPTH_V6_LEQUAL ((uint32_t)2u)
#define GE_SOURCE_DEPTH_V6_EQUAL ((uint32_t)3u)
#define GE_SOURCE_DEPTH_V6_ALWAYS ((uint32_t)4u)
#define GE_SOURCE_DEPTH_V6_MAX GE_SOURCE_DEPTH_V6_ALWAYS

#define GE_SOURCE_ALPHA_V6_DISABLED ((uint32_t)0u)
#define GE_SOURCE_ALPHA_V6_THRESHOLD ((uint32_t)1u)
#define GE_SOURCE_ALPHA_V6_DITHER ((uint32_t)2u)
#define GE_SOURCE_ALPHA_V6_MAX GE_SOURCE_ALPHA_V6_DITHER

#define GE_SOURCE_COVERAGE_V6_CLAMP ((uint32_t)0u)
#define GE_SOURCE_COVERAGE_V6_WRAP ((uint32_t)1u)
#define GE_SOURCE_COVERAGE_V6_ZAP ((uint32_t)2u)
#define GE_SOURCE_COVERAGE_V6_SAVE ((uint32_t)3u)
#define GE_SOURCE_COVERAGE_V6_MAX GE_SOURCE_COVERAGE_V6_SAVE

#define GE_SOURCE_CULL_V6_NONE ((uint32_t)0u)
#define GE_SOURCE_CULL_V6_FRONT ((uint32_t)1u)
#define GE_SOURCE_CULL_V6_BACK ((uint32_t)2u)
#define GE_SOURCE_CULL_V6_BOTH ((uint32_t)3u)
#define GE_SOURCE_CULL_V6_MAX GE_SOURCE_CULL_V6_BOTH

#define GE_SOURCE_FILTER_V6_POINT ((uint32_t)0u)
#define GE_SOURCE_FILTER_V6_BILINEAR ((uint32_t)1u)
#define GE_SOURCE_FILTER_V6_TRILINEAR ((uint32_t)2u)
#define GE_SOURCE_FILTER_V6_MAX GE_SOURCE_FILTER_V6_TRILINEAR

#define GE_SOURCE_WRAP_V6_CLAMP ((uint32_t)0u)
#define GE_SOURCE_WRAP_V6_REPEAT ((uint32_t)1u)
#define GE_SOURCE_WRAP_V6_MIRROR ((uint32_t)2u)
#define GE_SOURCE_WRAP_V6_MAX GE_SOURCE_WRAP_V6_MIRROR

/* Draw command kinds and flags. */
#define GE_SOURCE_DRAW_V6_TRIANGLES ((uint32_t)1u)
#define GE_SOURCE_DRAW_V6_TRIANGLE_STRIP ((uint32_t)2u)
#define GE_SOURCE_DRAW_V6_TEXTURE_RECT ((uint32_t)3u)
#define GE_SOURCE_DRAW_V6_FILL_RECT ((uint32_t)4u)
#define GE_SOURCE_DRAW_V6_TEXT ((uint32_t)5u)
#define GE_SOURCE_DRAW_V6_PARTICLE ((uint32_t)6u)
#define GE_SOURCE_DRAW_V6_LINE ((uint32_t)7u)
#define GE_SOURCE_DRAW_V6_MASK ((uint32_t)8u)
#define GE_SOURCE_DRAW_V6_KIND_MAX GE_SOURCE_DRAW_V6_MASK

#define GE_SOURCE_DRAW_V6_FLAG_OPAQUE ((uint32_t)1u << 0)
#define GE_SOURCE_DRAW_V6_FLAG_DECAL ((uint32_t)1u << 1)
#define GE_SOURCE_DRAW_V6_FLAG_TRANSLUCENT ((uint32_t)1u << 2)
#define GE_SOURCE_DRAW_V6_FLAG_SOURCE_ORDERED ((uint32_t)1u << 3)
#define GE_SOURCE_DRAW_V6_FLAG_INTERPOLATED ((uint32_t)1u << 4)
#define GE_SOURCE_DRAW_V6_FLAG_MASK ((uint32_t)0x1fu)

/* Text event kinds and flags. */
#define GE_SOURCE_TEXT_V6_GLYPH_RUN ((uint32_t)1u)
#define GE_SOURCE_TEXT_V6_ICON ((uint32_t)2u)
#define GE_SOURCE_TEXT_V6_LITERAL ((uint32_t)3u)
#define GE_SOURCE_TEXT_V6_KIND_MAX GE_SOURCE_TEXT_V6_LITERAL

#define GE_SOURCE_TEXT_V6_FLAG_SOURCE_FONT ((uint32_t)1u << 0)
#define GE_SOURCE_TEXT_V6_FLAG_CENTERED ((uint32_t)1u << 1)
#define GE_SOURCE_TEXT_V6_FLAG_SHADOW ((uint32_t)1u << 2)
#define GE_SOURCE_TEXT_V6_FLAG_MASK ((uint32_t)0x07u)

/* Audio event kinds and flags. */
#define GE_SOURCE_AUDIO_V6_NOTE_ON ((uint32_t)1u)
#define GE_SOURCE_AUDIO_V6_NOTE_OFF ((uint32_t)2u)
#define GE_SOURCE_AUDIO_V6_SFX ((uint32_t)3u)
#define GE_SOURCE_AUDIO_V6_MUSIC_START ((uint32_t)4u)
#define GE_SOURCE_AUDIO_V6_MUSIC_STOP ((uint32_t)5u)
#define GE_SOURCE_AUDIO_V6_SET_PARAMETER ((uint32_t)6u)
#define GE_SOURCE_AUDIO_V6_COMPOSITE_SFX ((uint32_t)7u)
#define GE_SOURCE_AUDIO_V6_KIND_MAX GE_SOURCE_AUDIO_V6_COMPOSITE_SFX

#define GE_SOURCE_AUDIO_V6_FLAG_LOOP ((uint32_t)1u << 0)
#define GE_SOURCE_AUDIO_V6_FLAG_RETRIGGER ((uint32_t)1u << 1)
#define GE_SOURCE_AUDIO_V6_FLAG_SOURCE_ANCHOR ((uint32_t)1u << 2)
#define GE_SOURCE_AUDIO_V6_FLAG_MASK ((uint32_t)0x07u)

/* Immutable frame screens match the existing title screen numbering. */
#define GE_SOURCE_FRAME_V6_SCREEN_LEGAL ((uint32_t)0u)
#define GE_SOURCE_FRAME_V6_SCREEN_NINTENDO ((uint32_t)1u)
#define GE_SOURCE_FRAME_V6_SCREEN_RAREWARE ((uint32_t)2u)
#define GE_SOURCE_FRAME_V6_SCREEN_GUNBARREL ((uint32_t)3u)
#define GE_SOURCE_FRAME_V6_SCREEN_GOLDENEYE ((uint32_t)4u)
#define GE_SOURCE_FRAME_V6_SCREEN_FILE_SELECT ((uint32_t)5u)
#define GE_SOURCE_FRAME_V6_SCREEN_MODE_SELECT ((uint32_t)6u)
#define GE_SOURCE_FRAME_V6_SCREEN_CAST ((uint32_t)7u)
#define GE_SOURCE_FRAME_V6_SCREEN_RAMROM ((uint32_t)8u)
#define GE_SOURCE_FRAME_V6_SCREEN_MAX GE_SOURCE_FRAME_V6_SCREEN_RAMROM

#define GE_SOURCE_FRAME_V6_FLAG_PRESENTABLE ((uint32_t)1u << 0)
#define GE_SOURCE_FRAME_V6_FLAG_SOURCE_ANCHOR ((uint32_t)1u << 1)
#define GE_SOURCE_FRAME_V6_FLAG_INTERPOLATED ((uint32_t)1u << 2)
#define GE_SOURCE_FRAME_V6_FLAG_HAS_UI ((uint32_t)1u << 3)
#define GE_SOURCE_FRAME_V6_FLAG_HAS_AUDIO ((uint32_t)1u << 4)
#define GE_SOURCE_FRAME_V6_FLAG_MASK ((uint32_t)0x1fu)

/* Diagnostics identify unsupported/malformed source work without storing it. */
#define GE_SOURCE_DIAGNOSTIC_V6_UNSUPPORTED_COMMAND ((uint32_t)1u)
#define GE_SOURCE_DIAGNOSTIC_V6_MISSING_RESOURCE ((uint32_t)2u)
#define GE_SOURCE_DIAGNOSTIC_V6_MALFORMED_ASSET ((uint32_t)3u)
#define GE_SOURCE_DIAGNOSTIC_V6_OVERFLOW ((uint32_t)4u)
#define GE_SOURCE_DIAGNOSTIC_V6_STATE_MISMATCH ((uint32_t)5u)
#define GE_SOURCE_DIAGNOSTIC_V6_CADENCE ((uint32_t)6u)
#define GE_SOURCE_DIAGNOSTIC_V6_AUDIO ((uint32_t)7u)
#define GE_SOURCE_DIAGNOSTIC_V6_PRESENTATION ((uint32_t)8u)
#define GE_SOURCE_DIAGNOSTIC_V6_KIND_MAX GE_SOURCE_DIAGNOSTIC_V6_PRESENTATION

#define GE_SOURCE_DIAGNOSTIC_V6_SEVERITY_INFO ((uint32_t)0u)
#define GE_SOURCE_DIAGNOSTIC_V6_SEVERITY_WARNING ((uint32_t)1u)
#define GE_SOURCE_DIAGNOSTIC_V6_SEVERITY_ERROR ((uint32_t)2u)
#define GE_SOURCE_DIAGNOSTIC_V6_SEVERITY_FATAL ((uint32_t)3u)
#define GE_SOURCE_DIAGNOSTIC_V6_SEVERITY_MAX GE_SOURCE_DIAGNOSTIC_V6_SEVERITY_FATAL

/* Page kinds are stable identifiers for the bounded copy-out APIs. */
#define GE_SOURCE_PAGE_V6_RESOURCES ((uint32_t)1u)
#define GE_SOURCE_PAGE_V6_TRANSFORMS ((uint32_t)2u)
#define GE_SOURCE_PAGE_V6_ANIMATION_POSES ((uint32_t)3u)
#define GE_SOURCE_PAGE_V6_RENDER_STATES ((uint32_t)4u)
#define GE_SOURCE_PAGE_V6_DRAW_COMMANDS ((uint32_t)5u)
#define GE_SOURCE_PAGE_V6_TEXT_EVENTS ((uint32_t)6u)
#define GE_SOURCE_PAGE_V6_AUDIO_EVENTS ((uint32_t)7u)
#define GE_SOURCE_PAGE_V6_FRAME_SUMMARIES ((uint32_t)8u)
#define GE_SOURCE_PAGE_V6_DIAGNOSTICS ((uint32_t)9u)
#define GE_SOURCE_PAGE_V6_VERTICES ((uint32_t)10u)
#define GE_SOURCE_PAGE_V6_INDICES ((uint32_t)11u)
#define GE_SOURCE_PAGE_V6_MAX GE_SOURCE_PAGE_V6_INDICES

typedef struct GESourceResourceV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t resource_kind;
    uint32_t flags;
    uint32_t handle;
    uint32_t source_id;
    uint32_t format;
    uint32_t width;
    uint32_t height;
    uint32_t depth;
    uint32_t mip_count;
    uint32_t level_count;
    uint32_t byte_size;
    uint64_t content_hash;
    uint64_t provenance_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GESourceResourceV6;

typedef struct GESourceTransformV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t transform_kind;
    uint32_t flags;
    uint32_t handle;
    uint32_t parent_handle;
    uint32_t source_node;
    uint32_t viewport_id;
    uint32_t reserved0;
    int32_t matrix_q16[16];
    uint32_t reserved1;
    uint32_t reserved2;
} GESourceTransformV6;

/* For GE_SOURCE_TRANSFORM_V6_CLIP_COMPOSITE, parent_handle carries the raw
   modelview handle, source_node carries the raw projection handle, and
   viewport_id carries the raw viewport handle.  matrix_q16 is the exact
   source-quantized column-major Metal clip matrix.  These fields reuse the
   existing record and therefore do not change its fixed 112-byte layout. */

typedef struct GESourceAnimationPoseV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t pose_handle;
    uint32_t skeleton_handle;
    uint32_t node_handle;
    uint32_t parent_handle;
    uint32_t flags;
    uint32_t animation_tick;
    uint32_t reserved0;
    int32_t translation_q16[3];
    int32_t rotation_q16[4];
    int32_t scale_q16[3];
    uint64_t pose_hash;
    uint32_t reserved1;
    uint32_t reserved2;
} GESourceAnimationPoseV6;

/* Dynamic source geometry is copied by value, never retained as a pointer. */
#define GE_SOURCE_VERTEX_V6_FLAG_INTERPOLATABLE ((uint32_t)1u << 0)
#define GE_SOURCE_VERTEX_V6_FLAG_SOURCE_QUANTIZED ((uint32_t)1u << 1)
#define GE_SOURCE_VERTEX_V6_FLAG_SKINNED ((uint32_t)1u << 2)
#define GE_SOURCE_VERTEX_V6_FLAG_MASK ((uint32_t)0x07u)

#define GE_SOURCE_INDEX_V6_FLAG_SOURCE_ORDERED ((uint32_t)1u << 0)
#define GE_SOURCE_INDEX_V6_FLAG_RESTART ((uint32_t)1u << 1)
#define GE_SOURCE_INDEX_V6_FLAG_MASK ((uint32_t)0x03u)

typedef struct GESourceVertexV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t handle;
    uint32_t flags;
    int32_t position_q16[3];
    int32_t texcoord_q16[2];
    int32_t normal_q16[3];
    uint32_t color_rgba;
    uint32_t source_index;
    uint32_t reserved0;
    uint32_t reserved1;
} GESourceVertexV6;

typedef struct GESourceIndexV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t handle;
    uint32_t flags;
    uint32_t vertex0;
    uint32_t vertex1;
    uint32_t vertex2;
    uint32_t source_index;
    uint32_t reserved0;
    uint32_t reserved1;
} GESourceIndexV6;

typedef struct GESourceRenderStateV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t state_handle;
    uint32_t flags;
    uint32_t material_handle;
    uint32_t combiner_cycle_count;
    uint32_t cycle0_color_a;
    uint32_t cycle0_color_b;
    uint32_t cycle0_color_c;
    uint32_t cycle0_color_d;
    uint32_t cycle0_alpha_a;
    uint32_t cycle0_alpha_b;
    uint32_t cycle0_alpha_c;
    uint32_t cycle0_alpha_d;
    uint32_t cycle1_color_a;
    uint32_t cycle1_color_b;
    uint32_t cycle1_color_c;
    uint32_t cycle1_color_d;
    uint32_t cycle1_alpha_a;
    uint32_t cycle1_alpha_b;
    uint32_t cycle1_alpha_c;
    uint32_t cycle1_alpha_d;
    uint32_t primitive_rgba;
    uint32_t environment_rgba;
    uint32_t fog_rgba;
    uint32_t blend_rgba;
    uint32_t depth_mode;
    uint32_t alpha_mode;
    uint32_t coverage_mode;
    uint32_t cull_mode;
    uint32_t filter_mode;
    uint32_t wrap_s;
    uint32_t wrap_t;
    uint32_t lod_min_q16;
    uint32_t lod_max_q16;
    uint32_t raw_othermode_h;
    uint32_t raw_othermode_l;
    uint32_t raw_render_mode;
    uint32_t raw_blender_a;
    uint32_t raw_blender_b;
    uint32_t raw_blender_c;
    uint32_t raw_blender_d;
    uint32_t reserved0;
    uint32_t reserved1;
} GESourceRenderStateV6;

typedef struct GESourceDrawCommandV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t command_kind;
    uint32_t flags;
    uint32_t draw_handle;
    uint32_t transform_handle;
    uint32_t resource_handle;
    uint32_t render_state_handle;
    uint32_t first_vertex;
    uint32_t vertex_count;
    uint32_t first_index;
    uint32_t index_count;
    uint32_t instance_count;
    uint32_t text_handle;
    uint32_t sort_key;
    int32_t depth_q16;
    int32_t scissor_x;
    int32_t scissor_y;
    uint32_t scissor_width;
    uint32_t scissor_height;
    uint64_t draw_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GESourceDrawCommandV6;

typedef struct GESourceTextEventV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t event_kind;
    uint32_t flags;
    uint32_t text_handle;
    uint32_t glyph_run_handle;
    int32_t x_q16;
    int32_t y_q16;
    int32_t scale_x_q16;
    int32_t scale_y_q16;
    uint32_t color_rgba;
    int32_t scissor_x;
    int32_t scissor_y;
    uint32_t scissor_width;
    uint32_t scissor_height;
    uint32_t glyph_count;
    uint64_t string_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GESourceTextEventV6;

typedef struct GESourceAudioEventV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t event_kind;
    uint32_t flags;
    uint32_t event_handle;
    uint32_t asset_handle;
    uint32_t slot;
    uint32_t voice;
    uint32_t note;
    uint32_t velocity;
    uint32_t reserved0;
    int32_t pitch_q16;
    int32_t pan_q16;
    int32_t gain_q16;
    uint32_t reserved1;
    uint64_t sample_index;
    uint32_t duration_frames;
    uint32_t loop_begin;
    uint32_t loop_end;
    uint32_t reserved2;
    uint64_t event_hash;
    uint32_t reserved3;
    uint32_t reserved4;
} GESourceAudioEventV6;

typedef struct GESourceFrameSummaryV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t flags;
    uint32_t screen;
    uint32_t subphase;
    uint64_t native_tick;
    uint64_t reference_tick;
    uint32_t pair_phase;
    uint32_t viewport_width;
    uint32_t viewport_height;
    uint32_t logical_width;
    uint32_t logical_height;
    uint32_t transform_count;
    uint32_t resource_count;
    uint32_t pose_count;
    uint32_t vertex_count;
    uint32_t index_count;
    uint32_t draw_count;
    uint32_t render_state_count;
    uint32_t text_count;
    uint32_t audio_count;
    uint32_t diagnostic_count;
    uint32_t unsupported_visible_count;
    uint64_t scene_hash;
    uint64_t render_hash;
    uint64_t state_hash;
    uint64_t audio_hash;
    uint64_t frame_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GESourceFrameSummaryV6;

typedef struct GESourceDiagnosticV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t diagnostic_kind;
    uint32_t flags;
    uint32_t severity;
    uint32_t code;
    uint32_t source_id;
    uint32_t command_id;
    uint32_t first_bad_index;
    uint32_t item_count;
    uint64_t detail_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GESourceDiagnosticV6;

typedef struct GESourceScenePageV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t page_kind;
    uint32_t page_index;
    uint32_t item_size;
    uint32_t first_item;
    uint32_t item_count;
    uint32_t total_items;
    uint32_t page_capacity;
    uint32_t reserved0;
    uint64_t page_hash;
    uint32_t reserved1;
    uint32_t reserved2;
} GESourceScenePageV6;

/* Deterministic hashes serialize every integer in little-endian order. */
uint64_t ge_source_scene_v6_hash_bytes(const uint8_t *bytes, uint32_t byte_count);
uint64_t ge_source_scene_v6_hash_resource(const GESourceResourceV6 *value);
uint64_t ge_source_scene_v6_hash_transform(const GESourceTransformV6 *value);
uint64_t ge_source_scene_v6_hash_animation_pose(const GESourceAnimationPoseV6 *value);
uint64_t ge_source_scene_v6_hash_vertex(const GESourceVertexV6 *value);
uint64_t ge_source_scene_v6_hash_index(const GESourceIndexV6 *value);
uint64_t ge_source_scene_v6_hash_render_state(const GESourceRenderStateV6 *value);
uint64_t ge_source_scene_v6_hash_draw_command(const GESourceDrawCommandV6 *value);
uint64_t ge_source_scene_v6_hash_text_event(const GESourceTextEventV6 *value);
uint64_t ge_source_scene_v6_hash_audio_event(const GESourceAudioEventV6 *value);
uint64_t ge_source_scene_v6_hash_frame_summary(const GESourceFrameSummaryV6 *value);
uint64_t ge_source_scene_v6_hash_diagnostic(const GESourceDiagnosticV6 *value);

/* All validators reject bad envelopes, schema versions, flags/ranges, and
   non-zero reserved fields. */
GEStatusV1 ge_source_scene_v6_validate_resource(const GESourceResourceV6 *value);
GEStatusV1 ge_source_scene_v6_validate_transform(const GESourceTransformV6 *value);
GEStatusV1 ge_source_scene_v6_validate_animation_pose(
    const GESourceAnimationPoseV6 *value);
GEStatusV1 ge_source_scene_v6_validate_vertex(const GESourceVertexV6 *value);
GEStatusV1 ge_source_scene_v6_validate_index(const GESourceIndexV6 *value);
GEStatusV1 ge_source_scene_v6_validate_render_state(
    const GESourceRenderStateV6 *value);
GEStatusV1 ge_source_scene_v6_validate_draw_command(
    const GESourceDrawCommandV6 *value);
GEStatusV1 ge_source_scene_v6_validate_text_event(const GESourceTextEventV6 *value);
GEStatusV1 ge_source_scene_v6_validate_audio_event(const GESourceAudioEventV6 *value);
GEStatusV1 ge_source_scene_v6_validate_frame_summary(
    const GESourceFrameSummaryV6 *value);
GEStatusV1 ge_source_scene_v6_validate_diagnostic(const GESourceDiagnosticV6 *value);
GEStatusV1 ge_source_scene_v6_validate_page(const GESourceScenePageV6 *value);

/* Calculate a page without multiplying an untrusted count or index blindly. */
GEStatusV1 ge_source_scene_v6_page_bounds(uint32_t total_items,
                                          uint32_t item_size,
                                          uint32_t page_index,
                                          uint32_t page_capacity,
                                          uint32_t *first_item,
                                          uint32_t *item_count);

/* Typed, bounded copy-out.  The source and output buffers are call-time only;
   the API never retains them.  A malformed source item prevents any output
   copy and leaves the page descriptor untouched. */
GEStatusV1 ge_source_scene_v6_copy_resource_page(
    const GESourceResourceV6 *items,
    uint32_t total_items,
    uint32_t page_index,
    uint32_t page_capacity,
    GESourceResourceV6 *out_items,
    uint32_t out_capacity,
    GESourceScenePageV6 *out_page);
GEStatusV1 ge_source_scene_v6_copy_transform_page(
    const GESourceTransformV6 *items,
    uint32_t total_items,
    uint32_t page_index,
    uint32_t page_capacity,
    GESourceTransformV6 *out_items,
    uint32_t out_capacity,
    GESourceScenePageV6 *out_page);
GEStatusV1 ge_source_scene_v6_copy_animation_pose_page(
    const GESourceAnimationPoseV6 *items,
    uint32_t total_items,
    uint32_t page_index,
    uint32_t page_capacity,
    GESourceAnimationPoseV6 *out_items,
    uint32_t out_capacity,
    GESourceScenePageV6 *out_page);
GEStatusV1 ge_source_scene_v6_copy_vertex_page(
    const GESourceVertexV6 *items,
    uint32_t total_items,
    uint32_t page_index,
    uint32_t page_capacity,
    GESourceVertexV6 *out_items,
    uint32_t out_capacity,
    GESourceScenePageV6 *out_page);
GEStatusV1 ge_source_scene_v6_copy_index_page(
    const GESourceIndexV6 *items,
    uint32_t total_items,
    uint32_t page_index,
    uint32_t page_capacity,
    GESourceIndexV6 *out_items,
    uint32_t out_capacity,
    GESourceScenePageV6 *out_page);
GEStatusV1 ge_source_scene_v6_copy_render_state_page(
    const GESourceRenderStateV6 *items,
    uint32_t total_items,
    uint32_t page_index,
    uint32_t page_capacity,
    GESourceRenderStateV6 *out_items,
    uint32_t out_capacity,
    GESourceScenePageV6 *out_page);
GEStatusV1 ge_source_scene_v6_copy_draw_command_page(
    const GESourceDrawCommandV6 *items,
    uint32_t total_items,
    uint32_t page_index,
    uint32_t page_capacity,
    GESourceDrawCommandV6 *out_items,
    uint32_t out_capacity,
    GESourceScenePageV6 *out_page);
GEStatusV1 ge_source_scene_v6_copy_text_event_page(
    const GESourceTextEventV6 *items,
    uint32_t total_items,
    uint32_t page_index,
    uint32_t page_capacity,
    GESourceTextEventV6 *out_items,
    uint32_t out_capacity,
    GESourceScenePageV6 *out_page);
GEStatusV1 ge_source_scene_v6_copy_audio_event_page(
    const GESourceAudioEventV6 *items,
    uint32_t total_items,
    uint32_t page_index,
    uint32_t page_capacity,
    GESourceAudioEventV6 *out_items,
    uint32_t out_capacity,
    GESourceScenePageV6 *out_page);
GEStatusV1 ge_source_scene_v6_copy_frame_summary_page(
    const GESourceFrameSummaryV6 *items,
    uint32_t total_items,
    uint32_t page_index,
    uint32_t page_capacity,
    GESourceFrameSummaryV6 *out_items,
    uint32_t out_capacity,
    GESourceScenePageV6 *out_page);
GEStatusV1 ge_source_scene_v6_copy_diagnostic_page(
    const GESourceDiagnosticV6 *items,
    uint32_t total_items,
    uint32_t page_index,
    uint32_t page_capacity,
    GESourceDiagnosticV6 *out_items,
    uint32_t out_capacity,
    GESourceScenePageV6 *out_page);

#if defined(__cplusplus)
#define GE_SOURCE_SCENE_V6_STATIC_ASSERT(condition, message) static_assert((condition), message)
#else
#define GE_SOURCE_SCENE_V6_STATIC_ASSERT(condition, message) _Static_assert((condition), message)
#endif

GE_SOURCE_SCENE_V6_STATIC_ASSERT(sizeof(GEAbiHeaderV1) == 8u,
                                 "GEAbiHeaderV1 layout drift");
GE_SOURCE_SCENE_V6_STATIC_ASSERT(sizeof(GESourceResourceV6) == 80u,
                                 "GESourceResourceV6 layout drift");
GE_SOURCE_SCENE_V6_STATIC_ASSERT(sizeof(GESourceTransformV6) == 112u,
                                 "GESourceTransformV6 layout drift");
GE_SOURCE_SCENE_V6_STATIC_ASSERT(sizeof(GESourceAnimationPoseV6) == 96u,
                                 "GESourceAnimationPoseV6 layout drift");
GE_SOURCE_SCENE_V6_STATIC_ASSERT(sizeof(GESourceVertexV6) == 68u,
                                 "GESourceVertexV6 layout drift");
GE_SOURCE_SCENE_V6_STATIC_ASSERT(sizeof(GESourceIndexV6) == 44u,
                                 "GESourceIndexV6 layout drift");
GE_SOURCE_SCENE_V6_STATIC_ASSERT(sizeof(GESourceRenderStateV6) == 180u,
                                 "GESourceRenderStateV6 layout drift");
GE_SOURCE_SCENE_V6_STATIC_ASSERT(sizeof(GESourceDrawCommandV6) == 104u,
                                 "GESourceDrawCommandV6 layout drift");
GE_SOURCE_SCENE_V6_STATIC_ASSERT(sizeof(GESourceTextEventV6) == 88u,
                                 "GESourceTextEventV6 layout drift");
GE_SOURCE_SCENE_V6_STATIC_ASSERT(sizeof(GESourceAudioEventV6) == 104u,
                                 "GESourceAudioEventV6 layout drift");
GE_SOURCE_SCENE_V6_STATIC_ASSERT(sizeof(GESourceFrameSummaryV6) == 152u,
                                 "GESourceFrameSummaryV6 layout drift");
GE_SOURCE_SCENE_V6_STATIC_ASSERT(sizeof(GESourceDiagnosticV6) == 64u,
                                 "GESourceDiagnosticV6 layout drift");
GE_SOURCE_SCENE_V6_STATIC_ASSERT(sizeof(GESourceScenePageV6) == 64u,
                                 "GESourceScenePageV6 layout drift");

#undef GE_SOURCE_SCENE_V6_STATIC_ASSERT

#ifdef __cplusplus
}
#endif

#endif /* GE_SOURCE_SCENE_V6_H */
