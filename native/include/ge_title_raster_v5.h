#ifndef GE_TITLE_RASTER_V5_H
#define GE_TITLE_RASTER_V5_H

/*
 * Additive M9 title combiner/render-mode vector.
 *
 * The generated title model display lists use a small, source-authored set of
 * SETOTHERMODE and SETCOMBINE values.  This sidecar copies those values into
 * fixed-width records so a native renderer can consume them without retaining
 * Gfx pointers, segmented addresses, paths, or ROM offsets.  It is separate
 * from the frozen V1--V4 contracts and deliberately does not claim to be a
 * generic RDP combiner or coverage implementation.
 *
 * The source title model tables currently exercise exactly these tuples:
 *   H=0,        L=0x00502048 (one-cycle opaque/no-Z)
 *   H=0x00100000, L=0x0C182048 (two-cycle opaque/no-Z)
 *   H=0x00100000, L=0x0C184340 (two-cycle forced-blend/coverage-save)
 * Rareware's authored logo display list additionally exercises:
 *   H=0,        L=0x00552048 (AA opaque)
 *   H=0x00100000, L=0x0F0A4000 (PASS/opaque forced blend)
 * with the eight SETCOMBINE word pairs recorded by the canonical vector in
 * ge_title_raster_source_vector_v5().  Texture image/tile state is intentionally
 * owned by the independent GETT texture contract.
 */

#include <stdint.h>

#include "ge_native_foundation.h"

#ifdef __cplusplus
extern "C" {
#endif

#define GE_TITLE_RASTER_V5_CONTRACT_VERSION ((uint32_t)1u)
#define GE_TITLE_RASTER_V5_STATE_CAPACITY ((uint32_t)8u)

#define GE_TITLE_RASTER_V5_SOURCE_LEGAL ((uint32_t)1u << 0)
#define GE_TITLE_RASTER_V5_SOURCE_NINTENDO ((uint32_t)1u << 1)
#define GE_TITLE_RASTER_V5_SOURCE_GOLDENEYE ((uint32_t)1u << 2)
#define GE_TITLE_RASTER_V5_SOURCE_WALLET ((uint32_t)1u << 3)
#define GE_TITLE_RASTER_V5_SOURCE_RAREWARE ((uint32_t)1u << 4)
#define GE_TITLE_RASTER_V5_SOURCE_MASK ((uint32_t)0x1fu)

#define GE_TITLE_RASTER_V5_H_ONE_CYCLE ((uint32_t)0x00000000u)
#define GE_TITLE_RASTER_V5_H_TWO_CYCLE ((uint32_t)0x00100000u)

#define GE_TITLE_RASTER_V5_L_ONE_CYCLE ((uint32_t)0x00502048u)
#define GE_TITLE_RASTER_V5_L_TWO_CYCLE ((uint32_t)0x0c182048u)
#define GE_TITLE_RASTER_V5_L_TWO_CYCLE_FORCE_BLEND ((uint32_t)0x0c184340u)
#define GE_TITLE_RASTER_V5_L_RAREWARE_ONE_CYCLE ((uint32_t)0x00552048u)
#define GE_TITLE_RASTER_V5_L_RAREWARE_TWO_CYCLE ((uint32_t)0x0f0a4000u)

/* The packed blender fields use m1a | m1b<<2 | m2a<<4 | m2b<<6. */
#define GE_TITLE_RASTER_V5_LOWER_NO_DEPTH ((uint32_t)1u << 0)
#define GE_TITLE_RASTER_V5_LOWER_ALPHA_NONE ((uint32_t)1u << 1)
#define GE_TITLE_RASTER_V5_DEFERRED_COVERAGE ((uint32_t)1u << 2)
#define GE_TITLE_RASTER_V5_DEFERRED_FORCE_BLEND ((uint32_t)1u << 3)

typedef struct GETitleRasterSourceStateV5 {
    uint32_t source_model_mask;
    uint32_t raw_other_mode_h;
    uint32_t raw_other_mode_l;
    uint32_t raw_combine_w0;
    uint32_t raw_combine_w1;
    uint32_t reserved;
} GETitleRasterSourceStateV5;

typedef struct GETitleRasterStateV5 {
    GEAbiHeaderV1 header;
    uint32_t source_model_mask;
    uint32_t raw_other_mode_h;
    uint32_t raw_other_mode_l;
    uint32_t raw_render_mode;
    uint32_t raw_combine_w0;
    uint32_t raw_combine_w1;
    uint32_t cycle_type;
    uint32_t texture_lod;
    uint32_t alpha_compare;
    uint32_t depth_source;
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
    uint32_t blend_cycle0;
    uint32_t blend_cycle1;
    uint32_t lowering_flags;
    uint32_t reserved;
    uint64_t state_hash;
} GETitleRasterStateV5;

typedef struct GETitleRasterInputV5 {
    GEAbiHeaderV1 header;
    uint32_t state_count;
    uint32_t reserved;
    GETitleRasterSourceStateV5 states[GE_TITLE_RASTER_V5_STATE_CAPACITY];
} GETitleRasterInputV5;

typedef struct GETitleRasterResultV5 {
    GEAbiHeaderV1 header;
    GEStatusV1 status;
    uint32_t reserved;
    uint32_t state_count;
    uint32_t reserved1;
    GETitleRasterStateV5 states[GE_TITLE_RASTER_V5_STATE_CAPACITY];
    uint64_t aggregate_hash;
} GETitleRasterResultV5;

GETitleRasterInputV5 ge_title_raster_source_vector_v5(void);
GETitleRasterResultV5 ge_title_lower_raster_v5(GETitleRasterInputV5 input);
GETitleRasterResultV5 ge_title_lower_source_raster_v5(void);

#if defined(__cplusplus)
#define GE_TITLE_RASTER_V5_STATIC_ASSERT(condition, message) static_assert((condition), message)
#else
#define GE_TITLE_RASTER_V5_STATIC_ASSERT(condition, message) _Static_assert((condition), message)
#endif

GE_TITLE_RASTER_V5_STATIC_ASSERT(sizeof(GETitleRasterSourceStateV5) == 24u,
                                 "GETitleRasterSourceStateV5 layout drift");
GE_TITLE_RASTER_V5_STATIC_ASSERT(sizeof(GETitleRasterStateV5) == 112u,
                                 "GETitleRasterStateV5 layout drift");
GE_TITLE_RASTER_V5_STATIC_ASSERT(sizeof(GETitleRasterInputV5) == 208u,
                                 "GETitleRasterInputV5 layout drift");
GE_TITLE_RASTER_V5_STATIC_ASSERT(sizeof(GETitleRasterResultV5) == 928u,
                                 "GETitleRasterResultV5 layout drift");

#undef GE_TITLE_RASTER_V5_STATIC_ASSERT

#ifdef __cplusplus
}
#endif

#endif /* GE_TITLE_RASTER_V5_H */
