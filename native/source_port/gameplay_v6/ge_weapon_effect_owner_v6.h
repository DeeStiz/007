#ifndef GE_WEAPON_EFFECT_OWNER_V6_H
#define GE_WEAPON_EFFECT_OWNER_V6_H

/*
 * Source-owned weapon, HUD, watch, transient-effect and fade seam for the
 * RAMROM attract route.  This is deliberately separate from
 * ge_ramrom_gameplay_v6.h: the gameplay owner remains the authority for the
 * recording packet/checksum/RNG timeline, while this owner receives the
 * directly compiled source weapon/effect state for one source anchor.
 *
 * No input button is interpreted as a visual command here.  A source frame
 * must carry the action state, resource identity, transform, colour, alpha,
 * animation frame and source offsets emitted by gunfire.c, explosion.c,
 * glass.c, bondview2.c and the watch renderer.  The owner copies those values
 * and rejects incomplete frames.  Odd native ticks only interpolate declared
 * transform/frame fields; no RNG, SFX, ammo, one-shot or event state is
 * consumed on an odd tick.
 *
 * The source ordering is the same as lv.c's post-room passes:
 * gunfireRender/weaponRenderTracers -> bullet particles -> glassRenderShards
 * -> explosionRenderFlyingParticles -> bondviewRemoved/mp_watch_menu_display.
 * `source_sfx_id`, `envelope_q16`, and `source_event_id` stay in the copied
 * event row so the audio owner can preserve the exact source event identity.
 */

#include <stdint.h>

#include "ge_native_foundation.h"
#include "ge_ramrom_gameplay_v6.h"

#ifdef __cplusplus
extern "C" {
#endif

#define GE_WEAPON_EFFECT_OWNER_V6_CONTRACT_VERSION ((uint32_t)6u)
#define GE_WEAPON_EFFECT_OWNER_V6_RECORD_VERSION ((uint32_t)1u)
#define GE_WEAPON_EFFECT_OWNER_V6_NATIVE_HZ ((uint32_t)120u)
#define GE_WEAPON_EFFECT_OWNER_V6_REFERENCE_HZ ((uint32_t)60u)
#define GE_WEAPON_EFFECT_OWNER_V6_MAX_HANDS ((uint32_t)2u)
#define GE_WEAPON_EFFECT_OWNER_V6_MAX_EVENTS ((uint32_t)64u)
#define GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_U32 UINT32_MAX
#define GE_WEAPON_EFFECT_OWNER_V6_UNKNOWN_Q16 INT32_MIN

/* Source categories are stable IDs, not renderer classifications. */
#define GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_MUZZLE ((uint32_t)1u)
#define GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_PROJECTILE ((uint32_t)2u)
#define GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_PARTICLE ((uint32_t)3u)
#define GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_EXPLOSION ((uint32_t)4u)
#define GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_GLASS ((uint32_t)5u)
#define GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_FADE ((uint32_t)6u)
#define GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_WATCH ((uint32_t)7u)
#define GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_HUD ((uint32_t)8u)
#define GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_SIGHT ((uint32_t)9u)
#define GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_SFX ((uint32_t)10u)
#define GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_MAX GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_SFX

#define GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_BIT(category) ((uint32_t)1u << ((category) - 1u))
#define GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_MASK ((uint32_t)0x3ffu)

/* Every category has a source producer.  A source frame may explicitly mark
   a category inactive, but it may not silently omit it. */
#define GE_WEAPON_EFFECT_OWNER_V6_SOURCE_WEAPON_TABLE ((uint32_t)1u << 0)
#define GE_WEAPON_EFFECT_OWNER_V6_SOURCE_HAND_STATE ((uint32_t)1u << 1)
#define GE_WEAPON_EFFECT_OWNER_V6_SOURCE_AMMO ((uint32_t)1u << 2)
#define GE_WEAPON_EFFECT_OWNER_V6_SOURCE_HUD ((uint32_t)1u << 3)
#define GE_WEAPON_EFFECT_OWNER_V6_SOURCE_SIGHT ((uint32_t)1u << 4)
#define GE_WEAPON_EFFECT_OWNER_V6_SOURCE_WATCH ((uint32_t)1u << 5)
#define GE_WEAPON_EFFECT_OWNER_V6_SOURCE_MUZZLE ((uint32_t)1u << 6)
#define GE_WEAPON_EFFECT_OWNER_V6_SOURCE_PROJECTILES ((uint32_t)1u << 7)
#define GE_WEAPON_EFFECT_OWNER_V6_SOURCE_PARTICLES ((uint32_t)1u << 8)
#define GE_WEAPON_EFFECT_OWNER_V6_SOURCE_EXPLOSIONS ((uint32_t)1u << 9)
#define GE_WEAPON_EFFECT_OWNER_V6_SOURCE_GLASS ((uint32_t)1u << 10)
#define GE_WEAPON_EFFECT_OWNER_V6_SOURCE_FADE ((uint32_t)1u << 11)
#define GE_WEAPON_EFFECT_OWNER_V6_SOURCE_SFX ((uint32_t)1u << 12)
#define GE_WEAPON_EFFECT_OWNER_V6_SOURCE_MASK ((uint32_t)0x1fffu)

#define GE_WEAPON_EFFECT_OWNER_V6_FRAME_SOURCE_ANCHOR ((uint32_t)1u << 0)
#define GE_WEAPON_EFFECT_OWNER_V6_FRAME_INTERPOLATED ((uint32_t)1u << 1)
#define GE_WEAPON_EFFECT_OWNER_V6_FRAME_HAS_HUD ((uint32_t)1u << 2)
#define GE_WEAPON_EFFECT_OWNER_V6_FRAME_HAS_SIGHT ((uint32_t)1u << 3)
#define GE_WEAPON_EFFECT_OWNER_V6_FRAME_HAS_WATCH ((uint32_t)1u << 4)
#define GE_WEAPON_EFFECT_OWNER_V6_FRAME_HAS_FADE ((uint32_t)1u << 5)
#define GE_WEAPON_EFFECT_OWNER_V6_FRAME_MASK ((uint32_t)0x3fu)

#define GE_WEAPON_EFFECT_OWNER_V6_EVENT_CONTINUOUS ((uint32_t)1u << 0)
#define GE_WEAPON_EFFECT_OWNER_V6_EVENT_ONE_SHOT_FLAG ((uint32_t)1u << 1)
#define GE_WEAPON_EFFECT_OWNER_V6_EVENT_SOURCE_ANCHOR_FLAG ((uint32_t)1u << 2)
#define GE_WEAPON_EFFECT_OWNER_V6_EVENT_INTERPOLATED ((uint32_t)1u << 3)
#define GE_WEAPON_EFFECT_OWNER_V6_EVENT_SFX ((uint32_t)1u << 4)
#define GE_WEAPON_EFFECT_OWNER_V6_EVENT_MASK ((uint32_t)0x1fu)

#define GE_WEAPON_EFFECT_OWNER_V6_STATE_ACTIVE ((uint32_t)1u << 0)
#define GE_WEAPON_EFFECT_OWNER_V6_STATE_SOURCE_ANCHOR ((uint32_t)1u << 1)
#define GE_WEAPON_EFFECT_OWNER_V6_STATE_INTERPOLATED ((uint32_t)1u << 2)
#define GE_WEAPON_EFFECT_OWNER_V6_STATE_ABORTING ((uint32_t)1u << 3)
#define GE_WEAPON_EFFECT_OWNER_V6_STATE_RESTORE_READY ((uint32_t)1u << 4)
#define GE_WEAPON_EFFECT_OWNER_V6_STATE_MASK ((uint32_t)0x1fu)

#define GE_WEAPON_EFFECT_OWNER_V6_OWNER_LOADING ((uint32_t)0u)
#define GE_WEAPON_EFFECT_OWNER_V6_OWNER_RUNNING ((uint32_t)1u)
#define GE_WEAPON_EFFECT_OWNER_V6_OWNER_ABORTING ((uint32_t)2u)
#define GE_WEAPON_EFFECT_OWNER_V6_OWNER_RESTORE_READY ((uint32_t)3u)

#define GE_WEAPON_EFFECT_OWNER_V6_EVENT_NONE ((uint32_t)0u)
#define GE_WEAPON_EFFECT_OWNER_V6_EVENT_INSTALL ((uint32_t)1u)
#define GE_WEAPON_EFFECT_OWNER_V6_EVENT_SOURCE_ANCHOR ((uint32_t)2u)
#define GE_WEAPON_EFFECT_OWNER_V6_EVENT_INTERPOLANT ((uint32_t)3u)
#define GE_WEAPON_EFFECT_OWNER_V6_EVENT_ONE_SHOT ((uint32_t)4u)
#define GE_WEAPON_EFFECT_OWNER_V6_EVENT_ABORT ((uint32_t)5u)
#define GE_WEAPON_EFFECT_OWNER_V6_EVENT_ERROR ((uint32_t)6u)
#define GE_WEAPON_EFFECT_OWNER_V6_EVENT_MAX GE_WEAPON_EFFECT_OWNER_V6_EVENT_ERROR

/* Values copied from itemids.h/gun.c.  The owner never derives a weapon from
   a button; these IDs identify an already source-selected row. */
#define GE_WEAPON_EFFECT_OWNER_V6_ITEM_UNARMED ((uint32_t)0u)
#define GE_WEAPON_EFFECT_OWNER_V6_ITEM_KNIFE ((uint32_t)1u)
#define GE_WEAPON_EFFECT_OWNER_V6_ITEM_WPPK ((uint32_t)2u)
#define GE_WEAPON_EFFECT_OWNER_V6_ITEM_GRENADE ((uint32_t)9u)
#define GE_WEAPON_EFFECT_OWNER_V6_ITEM_ROCKETLAUNCH ((uint32_t)31u)
#define GE_WEAPON_EFFECT_OWNER_V6_ITEM_GOLDENGUN ((uint32_t)36u)
#define GE_WEAPON_EFFECT_OWNER_V6_ITEM_WATCHLASER ((uint32_t)47u)

typedef struct GERamRomWeaponEffectSetupV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t stage_id;
    uint32_t demo_mask;
    uint32_t flags;
    uint32_t weapon_table_count;
    uint32_t image_table_count;
    uint32_t sound_table_count;
    uint32_t source_bytes;
    uint32_t source_setup_offset;
    uint32_t weapon_table_offset;
    uint32_t image_table_offset;
    uint32_t sound_table_offset;
    uint32_t initial_weapon_id;
    uint32_t initial_weapon_model;
    uint32_t initial_ammo_type;
    uint32_t initial_magazine;
    uint32_t initial_reserve;
    uint32_t initial_health;
    uint64_t source_hash;
    uint64_t resource_hash;
    uint64_t weapon_table_hash;
    uint64_t image_table_hash;
    uint64_t sound_table_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GERamRomWeaponEffectSetupV6;

typedef struct GERamRomWeaponHandV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t hand_index;
    uint32_t flags;
    uint32_t weapon_id;
    uint32_t model_handle;
    uint32_t ammo_type;
    uint32_t magazine;
    uint32_t reserve;
    uint32_t magazine_capacity;
    uint32_t action_state;
    uint32_t firing_status;
    uint32_t animation_id;
    int32_t animation_frame_q16;
    int32_t animation_rate_q16;
    uint32_t source_weapon_offset;
    uint32_t source_stats_offset;
    uint32_t source_transform_offset;
    uint32_t source_matrix_handle;
    int32_t position_q16[3];
    int32_t rotation_q16[3];
    int32_t scale_q16[3];
    int32_t muzzle_offset_q16[3];
    uint64_t source_hash;
    uint64_t resource_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GERamRomWeaponHandV6;

typedef struct GERamRomWeaponEffectEventV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t category;
    uint32_t flags;
    uint32_t source_event_id;
    uint32_t resource_handle;
    uint32_t source_resource_id;
    uint32_t image_handle;
    uint32_t source_sfx_id;
    uint64_t source_reference_tick;
    uint32_t sequence;
    uint32_t source_offset;
    uint32_t frame_index;
    uint32_t frame_count;
    int32_t position_q16[3];
    int32_t velocity_q16[3];
    int32_t rotation_q16[3];
    int32_t scale_q16[3];
    int32_t gravity_q16;
    uint32_t colour_rgba;
    uint32_t alpha_q16;
    uint32_t lifetime_q16;
    uint32_t envelope_q16;
    uint64_t source_hash;
    uint64_t resource_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GERamRomWeaponEffectEventV6;

/* A complete source-owned frame.  All rows are copied by value. */
typedef struct GERamRomWeaponEffectFrameV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t flags;
    uint32_t demo_id;
    uint32_t stage_id;
    uint64_t native_tick;
    uint64_t reference_tick;
    uint32_t source_anchor;
    uint32_t source_frame;
    uint32_t source_present_mask;
    uint32_t source_inactive_mask;
    uint32_t one_shot_sequence;
    uint32_t hand_count;
    uint32_t event_count;
    uint32_t hud_visible;
    int32_t view_left_q16;
    int32_t view_top_q16;
    uint32_t view_width_q16;
    uint32_t view_height_q16;
    uint32_t right_hud_image_handle;
    uint32_t left_hud_image_handle;
    uint32_t right_hud_width;
    uint32_t right_hud_height;
    uint32_t left_hud_width;
    uint32_t left_hud_height;
    uint32_t right_ammo_type;
    uint32_t right_magazine;
    uint32_t right_reserve;
    uint32_t left_ammo_type;
    uint32_t left_magazine;
    uint32_t left_reserve;
    int32_t crosshair_x_q16;
    int32_t crosshair_y_q16;
    uint32_t crosshair_image_handle;
    uint32_t sight_visible;
    uint32_t watch_visible;
    uint32_t watch_model_handle;
    uint32_t watch_animate_buttons;
    uint32_t watch_controller_pad;
    int32_t watch_position_q16[3];
    int32_t watch_scale_q16;
    uint32_t watch_animation_frame;
    uint32_t fade_visible;
    uint32_t fade_colour_rgba;
    uint32_t fade_q16;
    uint32_t fade_elapsed_q16;
    uint32_t fade_duration_q16;
    uint64_t source_hash;
    uint64_t resource_hash;
    uint64_t frame_hash;
    uint32_t reserved0;
    uint32_t reserved1;
    GERamRomWeaponHandV6 hands[GE_WEAPON_EFFECT_OWNER_V6_MAX_HANDS];
    GERamRomWeaponEffectEventV6 events[GE_WEAPON_EFFECT_OWNER_V6_MAX_EVENTS];
} GERamRomWeaponEffectFrameV6;

typedef struct GERamRomWeaponEffectSnapshotV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t flags;
    uint32_t demo_id;
    uint32_t stage_id;
    uint64_t native_tick;
    uint64_t reference_tick;
    uint32_t pair_phase;
    uint32_t source_anchor;
    uint32_t source_frame;
    uint32_t one_shot_sequence;
    uint32_t hand_count;
    uint32_t event_count;
    uint32_t right_weapon_id;
    uint32_t right_model_handle;
    uint32_t right_ammo_type;
    uint32_t right_magazine;
    uint32_t right_reserve;
    uint32_t hud_visible;
    uint32_t sight_visible;
    int32_t crosshair_x_q16;
    int32_t crosshair_y_q16;
    uint32_t watch_visible;
    uint32_t watch_model_handle;
    uint32_t fade_visible;
    uint32_t fade_q16;
    uint64_t source_hash;
    uint64_t resource_hash;
    uint64_t state_hash;
    uint64_t render_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GERamRomWeaponEffectSnapshotV6;

typedef struct GERamRomWeaponEffectEventRecordV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t event_type;
    uint32_t flags;
    uint32_t diagnostic_code;
    uint64_t native_tick;
    uint64_t reference_tick;
    uint32_t pair_phase;
    uint32_t demo_id;
    uint32_t stage_id;
    uint32_t source_frame;
    uint32_t one_shot_sequence;
    uint32_t event_count;
    uint32_t first_event_id;
    uint32_t last_event_id;
    uint64_t source_hash;
    uint64_t state_hash;
    uint64_t event_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GERamRomWeaponEffectEventRecordV6;

typedef struct GERamRomWeaponEffectOwnerStateV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t flags;
    uint32_t owner_state;
    uint32_t error_code;
    uint32_t demo_id;
    uint32_t stage_id;
    uint64_t native_tick;
    uint64_t reference_tick;
    uint32_t pair_phase;
    uint32_t source_anchor_count;
    uint32_t one_shot_sequence;
    uint64_t source_hash;
    uint64_t setup_hash;
    uint64_t resource_hash;
    uint64_t state_hash;
    GERamRomWeaponEffectSetupV6 setup;
    GERamRomWeaponEffectFrameV6 previous_anchor;
    GERamRomWeaponEffectFrameV6 current_anchor;
    GERamRomWeaponEffectFrameV6 render_frame;
    GERamRomWeaponEffectSnapshotV6 snapshot;
} GERamRomWeaponEffectOwnerStateV6;

GEStatusV1 ge_ramrom_weapon_effect_v6_validate_setup(
    const GERamRomWeaponEffectSetupV6 *value);
GEStatusV1 ge_ramrom_weapon_effect_v6_validate_hand(
    const GERamRomWeaponHandV6 *value);
GEStatusV1 ge_ramrom_weapon_effect_v6_validate_event(
    const GERamRomWeaponEffectEventV6 *value);
GEStatusV1 ge_ramrom_weapon_effect_v6_validate_frame(
    const GERamRomWeaponEffectFrameV6 *value);
GEStatusV1 ge_ramrom_weapon_effect_v6_validate_snapshot(
    const GERamRomWeaponEffectSnapshotV6 *value);
GEStatusV1 ge_ramrom_weapon_effect_v6_validate_state(
    const GERamRomWeaponEffectOwnerStateV6 *value);

uint64_t ge_ramrom_weapon_effect_v6_hash_frame(
    const GERamRomWeaponEffectFrameV6 *value);
uint64_t ge_ramrom_weapon_effect_v6_hash_event(
    const GERamRomWeaponEffectEventRecordV6 *value);

GEStatusV1 ge_ramrom_weapon_effect_v6_begin(
    uint32_t demo_id,
    const GERamRomWeaponEffectSetupV6 *setup,
    const GERamRomWeaponEffectFrameV6 *initial_frame,
    GERamRomWeaponEffectOwnerStateV6 *out_state,
    GERamRomWeaponEffectEventRecordV6 *out_event);

/* `source_frame` is consumed only on an even native tick.  On odd ticks it
   may be NULL; the owner publishes the midpoint of the previous/current
   anchor without consuming any source row. */
GEStatusV1 ge_ramrom_weapon_effect_v6_step(
    uint64_t native_tick,
    GERamRomGameplayInputV6 input,
    const GERamRomWeaponEffectFrameV6 *source_frame,
    GERamRomWeaponEffectOwnerStateV6 *inout_state,
    GERamRomWeaponEffectEventRecordV6 *out_event);

GEStatusV1 ge_ramrom_weapon_effect_v6_copy_snapshot(
    const GERamRomWeaponEffectOwnerStateV6 *state,
    GERamRomWeaponEffectSnapshotV6 *out_snapshot);
GEStatusV1 ge_ramrom_weapon_effect_v6_copy_frame(
    const GERamRomWeaponEffectOwnerStateV6 *state,
    GERamRomWeaponEffectFrameV6 *out_frame);
GEStatusV1 ge_ramrom_weapon_effect_v6_copy_events(
    const GERamRomWeaponEffectOwnerStateV6 *state,
    uint32_t first_item,
    uint32_t capacity,
    GERamRomWeaponEffectEventV6 *out_items,
    uint32_t *out_copied);

#if defined(__cplusplus)
#define GE_WEAPON_EFFECT_OWNER_V6_STATIC_ASSERT(condition, message) static_assert((condition), message)
#else
#define GE_WEAPON_EFFECT_OWNER_V6_STATIC_ASSERT(condition, message) _Static_assert((condition), message)
#endif

GE_WEAPON_EFFECT_OWNER_V6_STATIC_ASSERT(sizeof(GERamRomWeaponEffectSetupV6) == 128u,
                                        "weapon/effect setup layout drift");
GE_WEAPON_EFFECT_OWNER_V6_STATIC_ASSERT(sizeof(GERamRomWeaponHandV6) == 152u,
                                        "weapon hand layout drift");
GE_WEAPON_EFFECT_OWNER_V6_STATIC_ASSERT(sizeof(GERamRomWeaponEffectEventV6) == 160u,
                                        "weapon/effect event layout drift");
GE_WEAPON_EFFECT_OWNER_V6_STATIC_ASSERT(sizeof(GERamRomWeaponEffectFrameV6) == 10784u,
                                        "weapon/effect frame layout drift");
GE_WEAPON_EFFECT_OWNER_V6_STATIC_ASSERT(sizeof(GERamRomWeaponEffectSnapshotV6) == 160u,
                                        "weapon/effect snapshot layout drift");
GE_WEAPON_EFFECT_OWNER_V6_STATIC_ASSERT(sizeof(GERamRomWeaponEffectEventRecordV6) == 104u,
                                        "weapon/effect event record layout drift");
GE_WEAPON_EFFECT_OWNER_V6_STATIC_ASSERT(sizeof(GERamRomWeaponEffectOwnerStateV6) == 32736u,
                                        "weapon/effect owner state layout drift");

#undef GE_WEAPON_EFFECT_OWNER_V6_STATIC_ASSERT

#ifdef __cplusplus
}
#endif

#endif /* GE_WEAPON_EFFECT_OWNER_V6_H */
