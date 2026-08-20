#ifndef GE_CLASSIC_COMBINER_H
#define GE_CLASSIC_COMBINER_H

/*
 * Bounded classic GE/F3D combiner and render-mode lowering contract.
 *
 * This is a sidecar to the frozen V1/V2/V3 replay records.  It deliberately
 * contains only fixed-width values and copied command words.  The lowerer
 * consumes the small source setup emitted by modelApplyRenderModeType4 and
 * the authored ammo-crate command stream; it is not a generic RDP emulator.
 */

#include <stdint.h>

#include "ge_classic_replay.h"

#define GE_CLASSIC_COMBINER_REPLAY_ABI_VERSION ((uint32_t)4u)
#define GE_CLASSIC_COMBINER_PACKET_VERSION ((uint32_t)1u)
#define GE_CLASSIC_COMBINER_SETUP_CAPACITY ((uint32_t)4u)
#define GE_CLASSIC_COMBINER_COMMAND_CAPACITY ((uint32_t)32u)
#define GE_CLASSIC_COMBINER_DRAW_CAPACITY ((uint32_t)4u)
#define GE_CLASSIC_COMBINER_CYCLE_CAPACITY ((uint32_t)2u)

#define GE_CLASSIC_COMBINER_TEXTURE_AMMOCRATE1 ((uint32_t)0x21u)
#define GE_CLASSIC_COMBINER_TEXTURE_AMMOTEXT765 ((uint32_t)0x27u)
#define GE_CLASSIC_COMBINER_TEXTURE_CRATEROPE ((uint32_t)0x25u)

/* Fixed-width wire command.  This is intentionally separate from host Gfx. */
typedef struct GEClassicCombinerCommandV4 {
    uint32_t w0;
    uint32_t w1;
} GEClassicCombinerCommandV4;

/*
 * One RDP color/alpha cycle.  The values are the encoded selector fields,
 * not host pointers or SDK enums.  RGB A/B/C/D fields retain their wire
 * widths (A/B/C are 4/4/5 where applicable; D is the 3-bit field).  Alpha
 * selectors are always the 3-bit wire values.
 */
typedef struct GEClassicCombinerCycleV4 {
    uint32_t rgb_a;
    uint32_t rgb_b;
    uint32_t rgb_c;
    uint32_t rgb_d;
    uint32_t alpha_a;
    uint32_t alpha_b;
    uint32_t alpha_c;
    uint32_t alpha_d;
} GEClassicCombinerCycleV4;

typedef struct GEClassicCombinerStateV4 {
    uint32_t raw_w0;
    uint32_t raw_w1;
    GEClassicCombinerCycleV4 cycles[GE_CLASSIC_COMBINER_CYCLE_CAPACITY];
    uint32_t selector_flags;
    uint32_t reserved;
} GEClassicCombinerStateV4;

/*
 * Decoded old-style SETOTHERMODE register state.  raw_h/raw_l remain the
 * authoritative copied registers; the named fields make the lowering key
 * auditable without requiring callers to reinterpret bit ranges.
 */
typedef struct GEClassicOtherModeV4 {
    uint32_t raw_h;
    uint32_t raw_l;
    uint32_t pipeline_mode;
    uint32_t cycle_type;
    uint32_t texture_perspective;
    uint32_t texture_detail;
    uint32_t texture_lod;
    uint32_t texture_lut;
    uint32_t texture_filter;
    uint32_t texture_convert;
    uint32_t combine_key;
    uint32_t color_dither;
    uint32_t alpha_dither;
    uint32_t alpha_compare;
    uint32_t depth_source;
    uint32_t render_mode;
} GEClassicOtherModeV4;

typedef struct GEClassicBlenderCycleV4 {
    uint32_t m1a;
    uint32_t m1b;
    uint32_t m2a;
    uint32_t m2b;
} GEClassicBlenderCycleV4;

/* Render-mode bits are recorded even where their functional lowering is
   deferred to the later depth/fog/alpha goal. TODO(depth-fog-alpha-goal):
   consume these fields with a real depth attachment and RDP coverage path. */
typedef struct GEClassicRenderModeV4 {
    uint32_t raw_mode;
    uint32_t aa_enable;
    uint32_t z_compare;
    uint32_t z_update;
    uint32_t image_read;
    uint32_t clear_on_coverage;
    uint32_t coverage_destination;
    uint32_t z_mode;
    uint32_t coverage_x_alpha;
    uint32_t alpha_coverage_select;
    uint32_t force_blend;
    GEClassicBlenderCycleV4 blender[GE_CLASSIC_COMBINER_CYCLE_CAPACITY];
    uint32_t deferred_flags;
} GEClassicRenderModeV4;

/* Source setup is copied into the result for an auditable provenance seam. */
typedef struct GEClassicCombinerSourceSetupV4 {
    GEAbiHeaderV1 header;
    uint32_t command_count;
    uint32_t reserved;
    GEClassicCombinerCommandV4 commands[GE_CLASSIC_COMBINER_SETUP_CAPACITY];
    GEClassicCombinerStateV4 combiner;
    GEClassicOtherModeV4 other_mode;
    GEClassicRenderModeV4 render_mode;
    uint64_t setup_hash;
} GEClassicCombinerSourceSetupV4;

/*
 * Fixed-width input used by the parser and negative tests.  The canonical
 * ammo-crate path fills this from the external 1488-byte prop blob.
 */
typedef struct GEClassicCombinerInputV4 {
    GEAbiHeaderV1 header;
    uint32_t setup_command_count;
    uint32_t command_count;
    uint32_t reserved0;
    uint32_t reserved1;
    GEClassicCombinerCommandV4 setup[GE_CLASSIC_COMBINER_SETUP_CAPACITY];
    GEClassicCombinerCommandV4 commands[GE_CLASSIC_COMBINER_COMMAND_CAPACITY];
} GEClassicCombinerInputV4;

/* One immutable lowering key corresponds to one V3 draw group. */
typedef struct GEClassicCombinerDrawKeyV4 {
    GEAbiHeaderV1 header;
    uint32_t packet_version;
    uint32_t source_command_offset;
    uint32_t texture_id;
    uint32_t triangle_group_count;
    uint32_t material_flags;
    uint32_t reserved;
    uint64_t key_hash;
    GEClassicCombinerStateV4 combiner;
    GEClassicOtherModeV4 other_mode;
    GEClassicRenderModeV4 render_mode;
} GEClassicCombinerDrawKeyV4;

typedef struct GEClassicCombinerLoweringResultV4 {
    GEAbiHeaderV1 header;
    GEStatusV1 status;
    uint32_t reserved;
    uint32_t error_opcode;
    uint32_t error_offset;
    uint32_t commands_processed;
    uint32_t setup_commands_processed;
    uint32_t draw_count;
    uint32_t reserved1;
    uint64_t setup_hash;
    uint64_t event_hash;
    uint64_t key_hash;
    GEClassicCombinerSourceSetupV4 source_setup;
    GEClassicCombinerDrawKeyV4 draws[GE_CLASSIC_COMBINER_DRAW_CAPACITY];
} GEClassicCombinerLoweringResultV4;

/* Material flags are descriptive; deferred fields must not silently render. */
#define GE_CLASSIC_COMBINER_FLAG_SOURCE_SETUP ((uint32_t)1u << 0)
#define GE_CLASSIC_COMBINER_FLAG_TEXEL0_SHADE ((uint32_t)1u << 1)
#define GE_CLASSIC_COMBINER_FLAG_TEXTURED ((uint32_t)1u << 2)
#define GE_CLASSIC_COMBINER_FLAG_OPAQUE_PRIMARY ((uint32_t)1u << 3)
#define GE_CLASSIC_COMBINER_FLAG_DEFERRED_DEPTH ((uint32_t)1u << 4)
#define GE_CLASSIC_COMBINER_FLAG_DEFERRED_FOG ((uint32_t)1u << 5)
#define GE_CLASSIC_COMBINER_FLAG_DEFERRED_ALPHA ((uint32_t)1u << 6)
#define GE_CLASSIC_COMBINER_FLAG_DEFERRED_COVERAGE ((uint32_t)1u << 7)

/* Render-mode lowering records, but does not implement, these fields. */
#define GE_CLASSIC_COMBINER_DEFERRED_DEPTH ((uint32_t)1u << 0)
#define GE_CLASSIC_COMBINER_DEFERRED_FOG ((uint32_t)1u << 1)
#define GE_CLASSIC_COMBINER_DEFERRED_ALPHA ((uint32_t)1u << 2)
#define GE_CLASSIC_COMBINER_DEFERRED_COVERAGE ((uint32_t)1u << 3)

GEClassicCombinerInputV4 ge_classic_ammo_crate_combiner_input_v4(
    GEClassicAssetBlobV2 blob);
GEClassicCombinerLoweringResultV4 ge_classic_lower_combiner_v4(
    GEClassicCombinerInputV4 input);
GEClassicCombinerLoweringResultV4 ge_classic_lower_ammo_crate_v4(
    GEClassicAssetBlobV2 blob);

#if defined(__cplusplus)
#define GE_CLASSIC_COMBINER_STATIC_ASSERT(condition, message) static_assert((condition), message)
#else
#define GE_CLASSIC_COMBINER_STATIC_ASSERT(condition, message) _Static_assert((condition), message)
#endif

GE_CLASSIC_COMBINER_STATIC_ASSERT(sizeof(GEClassicCombinerCommandV4) == 8u,
                                   "GEClassicCombinerCommandV4 layout drift");
GE_CLASSIC_COMBINER_STATIC_ASSERT(sizeof(GEClassicCombinerCycleV4) == 32u,
                                   "GEClassicCombinerCycleV4 layout drift");
GE_CLASSIC_COMBINER_STATIC_ASSERT(sizeof(GEClassicCombinerStateV4) == 80u,
                                   "GEClassicCombinerStateV4 layout drift");
GE_CLASSIC_COMBINER_STATIC_ASSERT(sizeof(GEClassicOtherModeV4) == 64u,
                                   "GEClassicOtherModeV4 layout drift");
GE_CLASSIC_COMBINER_STATIC_ASSERT(sizeof(GEClassicBlenderCycleV4) == 16u,
                                   "GEClassicBlenderCycleV4 layout drift");
GE_CLASSIC_COMBINER_STATIC_ASSERT(sizeof(GEClassicRenderModeV4) == 80u,
                                   "GEClassicRenderModeV4 layout drift");
GE_CLASSIC_COMBINER_STATIC_ASSERT(sizeof(GEClassicCombinerSourceSetupV4) == 280u,
                                   "GEClassicCombinerSourceSetupV4 layout drift");
GE_CLASSIC_COMBINER_STATIC_ASSERT(sizeof(GEClassicCombinerInputV4) == 312u,
                                   "GEClassicCombinerInputV4 layout drift");
GE_CLASSIC_COMBINER_STATIC_ASSERT(sizeof(GEClassicCombinerDrawKeyV4) == 264u,
                                   "GEClassicCombinerDrawKeyV4 layout drift");
GE_CLASSIC_COMBINER_STATIC_ASSERT(sizeof(GEClassicCombinerLoweringResultV4) == 1400u,
                                   "GEClassicCombinerLoweringResultV4 layout drift");

#undef GE_CLASSIC_COMBINER_STATIC_ASSERT

#endif /* GE_CLASSIC_COMBINER_H */
