#ifndef GE_RAMROM_WEAPON_SOURCE_PAGES_V6_H
#define GE_RAMROM_WEAPON_SOURCE_PAGES_V6_H

/*
 * Additive source-page builder for ITEM_IDS/gitem_structs.  The page rows are
 * caller-supplied values emitted by the directly compiled source owner.  This
 * builder only joins an exact source item row to a guarded prepared model
 * handle and copies the result into the existing weapon/effect V6 frame.
 * It never chooses a model from an item number, consumes a button, advances
 * RNG, reads the ROM, or synthesizes an effect.
 */

#include <stdint.h>

#include "ge_weapon_effect_owner_v6.h"

#ifdef __cplusplus
extern "C" {
#endif

#define GE_RAMROM_WEAPON_SOURCE_PAGES_V6_RECORD_VERSION ((uint32_t)1u)
#define GE_RAMROM_WEAPON_SOURCE_PAGES_V6_MAX_HANDS ((uint32_t)2u)
#define GE_RAMROM_WEAPON_SOURCE_PAGES_V6_SOURCE_MASK ((uint32_t)0x0fu)

typedef struct GERamRomWeaponSourceMapRowV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t item_id;
    uint32_t prop_model_id;
    uint32_t model_handle;
    uint32_t ammo_type;
    uint32_t magazine_capacity;
    uint32_t source_weapon_offset;
    uint32_t source_stats_offset;
    uint32_t source_transform_offset;
    uint32_t source_matrix_handle;
    uint32_t resource_handle;
    uint32_t image_handle;
    uint32_t source_sfx_id;
    uint64_t source_hash;
    uint64_t resource_hash;
    uint32_t flags;
    uint32_t reserved0;
    uint32_t reserved1;
} GERamRomWeaponSourceMapRowV6;

typedef struct GERamRomWeaponSourcePageV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t item_id;
    uint32_t flags;
    uint32_t action_state;
    uint32_t firing_status;
    uint32_t animation_id;
    int32_t animation_frame_q16;
    int32_t animation_rate_q16;
    uint32_t magazine;
    uint32_t reserve;
    int32_t position_q16[3];
    int32_t rotation_q16[3];
    int32_t scale_q16[3];
    int32_t muzzle_offset_q16[3];
    uint32_t source_weapon_offset;
    uint32_t source_stats_offset;
    uint32_t source_transform_offset;
    uint32_t source_matrix_handle;
    uint64_t source_hash;
    uint32_t source_frame;
    uint32_t reserved0;
    uint32_t reserved1;
} GERamRomWeaponSourcePageV6;

GEStatusV1 ge_ramrom_weapon_source_pages_v6_validate_map(
    const GERamRomWeaponSourceMapRowV6 *value);
GEStatusV1 ge_ramrom_weapon_source_pages_v6_validate_page(
    const GERamRomWeaponSourcePageV6 *value);

GEStatusV1 ge_ramrom_weapon_source_pages_v6_build_hand(
    const GERamRomWeaponSourceMapRowV6 *map_row,
    const GERamRomWeaponSourcePageV6 *source_page,
    GERamRomWeaponHandV6 *out_hand);

/* `visual_template` supplies exact HUD/watch/fade/source-present masks from
   the source frontend producer.  `events` supplies exact source event rows;
   no row is manufactured here. */
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
    GERamRomWeaponEffectFrameV6 *out_frame);

#if defined(__cplusplus)
#define GE_RAMROM_WEAPON_SOURCE_PAGES_V6_STATIC_ASSERT(condition, message) static_assert((condition), message)
#else
#define GE_RAMROM_WEAPON_SOURCE_PAGES_V6_STATIC_ASSERT(condition, message) _Static_assert((condition), message)
#endif

GE_RAMROM_WEAPON_SOURCE_PAGES_V6_STATIC_ASSERT(sizeof(GERamRomWeaponSourceMapRowV6) == 96u,
                                               "weapon source map layout drift");
GE_RAMROM_WEAPON_SOURCE_PAGES_V6_STATIC_ASSERT(sizeof(GERamRomWeaponSourcePageV6) == 136u,
                                               "weapon source page layout drift");

#undef GE_RAMROM_WEAPON_SOURCE_PAGES_V6_STATIC_ASSERT

#ifdef __cplusplus
}
#endif

#endif /* GE_RAMROM_WEAPON_SOURCE_PAGES_V6_H */
