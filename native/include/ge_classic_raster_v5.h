#ifndef GE_CLASSIC_RASTER_V5_H
#define GE_CLASSIC_RASTER_V5_H

/*
 * Additive M9 raster policy for the canonical ModelType-4 ammo-crate setup.
 * This sidecar deliberately does not modify the frozen V4 combiner records or
 * their hashes. It translates the source SETOTHERMODE_L render words into
 * explicit, value-only depth/alpha/fog/coverage policies for the native
 * renderer. It is not a generic RDP rasterizer.
 */

#include <stdint.h>

#include "ge_native_foundation.h"

#define GE_CLASSIC_RASTER_CONTRACT_VERSION ((uint32_t)5u)
/* Every additive sidecar keeps the common GEAbiHeaderV1 envelope. */
#define GE_CLASSIC_RASTER_ABI_VERSION GE_NATIVE_ABI_VERSION
#define GE_CLASSIC_RASTER_MODE_CAPACITY ((uint32_t)2u)

#define GE_CLASSIC_RASTER_MODE_OPAQUE ((uint32_t)0xC4112078u)
#define GE_CLASSIC_RASTER_MODE_AUTHORED ((uint32_t)0xC4104DD8u)

enum {
    GE_CLASSIC_RASTER_ALPHA_NONE = 0u,
    GE_CLASSIC_RASTER_ALPHA_THRESHOLD = 1u,
    GE_CLASSIC_RASTER_ALPHA_DITHER = 3u,
};

enum {
    GE_CLASSIC_RASTER_DEPTH_ALWAYS = 0u,
    GE_CLASSIC_RASTER_DEPTH_LESS_EQUAL = 1u,
};

enum {
    GE_CLASSIC_RASTER_ZMODE_OPA = 0u,
    GE_CLASSIC_RASTER_ZMODE_INTER = 1u,
    GE_CLASSIC_RASTER_ZMODE_XLU = 2u,
    GE_CLASSIC_RASTER_ZMODE_DECAL = 3u,
};

enum {
    GE_CLASSIC_RASTER_POLICY_NATIVE = 0u,
    GE_CLASSIC_RASTER_POLICY_EXPLICIT_APPROXIMATION = 1u,
};

/*
 * The two blender cycles are packed as four 2-bit wire selectors each:
 * m1a | (m1b << 2) | (m2a << 4) | (m2b << 6).
 */
typedef struct GEClassicRasterStateV5 {
    GEAbiHeaderV1 header;
    uint32_t raw_render_mode;
    uint32_t raw_other_mode_l;
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
    uint32_t alpha_compare;
    uint32_t alpha_policy;
    uint32_t alpha_threshold_q8;
    uint32_t depth_compare_policy;
    uint32_t depth_write;
    uint32_t fog_enable;
    uint32_t fog_color_rgba8;
    uint32_t fog_alpha_q8;
    uint32_t blend_cycle0;
    uint32_t blend_cycle1;
    uint64_t state_hash;
} GEClassicRasterStateV5;

typedef struct GEClassicRasterInputV5 {
    GEAbiHeaderV1 header;
    uint32_t mode_count;
    uint32_t raw_modes[GE_CLASSIC_RASTER_MODE_CAPACITY];
    uint32_t raw_other_mode_l;
    uint32_t reserved;
} GEClassicRasterInputV5;

typedef struct GEClassicRasterResultV5 {
    GEAbiHeaderV1 header;
    GEStatusV1 status;
    uint32_t reserved;
    uint32_t state_count;
    uint32_t reserved1;
    GEClassicRasterStateV5 states[GE_CLASSIC_RASTER_MODE_CAPACITY];
    uint64_t aggregate_hash;
} GEClassicRasterResultV5;

GEClassicRasterResultV5 ge_classic_lower_raster_v5(
    GEClassicRasterInputV5 input);
GEClassicRasterResultV5 ge_classic_lower_ammo_crate_raster_v5(void);

#if defined(__cplusplus)
#define GE_CLASSIC_RASTER_STATIC_ASSERT(condition, message) static_assert((condition), message)
#else
#define GE_CLASSIC_RASTER_STATIC_ASSERT(condition, message) _Static_assert((condition), message)
#endif

GE_CLASSIC_RASTER_STATIC_ASSERT(sizeof(GEClassicRasterStateV5) == 104u,
                                "GEClassicRasterStateV5 layout drift");
GE_CLASSIC_RASTER_STATIC_ASSERT(sizeof(GEClassicRasterInputV5) == 28u,
                                "GEClassicRasterInputV5 layout drift");
GE_CLASSIC_RASTER_STATIC_ASSERT(sizeof(GEClassicRasterResultV5) == 240u,
                                "GEClassicRasterResultV5 layout drift");

#undef GE_CLASSIC_RASTER_STATIC_ASSERT

#endif /* GE_CLASSIC_RASTER_V5_H */
