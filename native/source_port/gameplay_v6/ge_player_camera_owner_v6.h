#ifndef GE_PLAYER_CAMERA_OWNER_V6_H
#define GE_PLAYER_CAMERA_OWNER_V6_H

/*
 * Directly compiled source player/camera owner for the RAMROM route.
 *
 * This is an additive seam beside ge_ramrom_gameplay_v6.c.  It consumes the
 * existing gameplay setup/entity pages and call-time copies of source STAN
 * and pad rows.  No source pointer, ROM address, path, model object, or
 * platform object is retained.  The owner deliberately rejects incomplete
 * stage-init evidence instead of inventing a spawn, camera offset, collision
 * radius, world bound, or weapon state.
 *
 * Source formulas are taken from:
 *   src/game/bondview2.c
 *     bondviewProcessInput       (deadzone, Honey movement, pitch/yaw)
 *     bondviewApplyVertaTheta    (angle normalization and theta basis)
 *     bondviewTryMoveToStan      (STAN acceptance boundary)
 *     bondviewUpdateCurrentRoomPosition (room ownership)
 *     bondviewUpdatePlayerCollisionPositionFields (camera/eye relation)
 *   src/game/stan.c / native Swift STAN decoder (floor/room selection)
 *
 * The source authority advances on even native ticks (60 Hz).  Odd ticks
 * publish a declared midpoint interpolant and do not consume a recording
 * sample, RNG checkpoint, or one-shot event.
 */

#include <stdint.h>

#include "ge_native_foundation.h"
#include "ge_ramrom_gameplay_v6.h"

#ifdef __cplusplus
extern "C" {
#endif

#define GE_PLAYER_CAMERA_OWNER_V6_CONTRACT_VERSION ((uint32_t)6u)
#define GE_PLAYER_CAMERA_OWNER_V6_RECORD_VERSION ((uint32_t)1u)
#define GE_PLAYER_CAMERA_OWNER_V6_NATIVE_HZ ((uint32_t)120u)
#define GE_PLAYER_CAMERA_OWNER_V6_REFERENCE_HZ ((uint32_t)60u)

#define GE_PLAYER_CAMERA_OWNER_V6_MAX_STAN_TILES ((uint32_t)4096u)
#define GE_PLAYER_CAMERA_OWNER_V6_MAX_PADS ((uint32_t)2048u)
#define GE_PLAYER_CAMERA_OWNER_V6_UNKNOWN_U32 UINT32_MAX
#define GE_PLAYER_CAMERA_OWNER_V6_UNKNOWN_Q16 INT32_MIN

/* These are source option/style values from bondconstants.h. */
#define GE_PLAYER_CAMERA_OWNER_V6_CONTROL_HONEY ((uint32_t)0u)
#define GE_PLAYER_CAMERA_OWNER_V6_CONTROL_SOLITAIRE ((uint32_t)1u)
#define GE_PLAYER_CAMERA_OWNER_V6_CONTROL_KISSY ((uint32_t)2u)
#define GE_PLAYER_CAMERA_OWNER_V6_CONTROL_GOODNIGHT ((uint32_t)3u)
#define GE_PLAYER_CAMERA_OWNER_V6_CONTROL_MAX GE_PLAYER_CAMERA_OWNER_V6_CONTROL_GOODNIGHT

#define GE_PLAYER_CAMERA_OWNER_V6_SOURCE_SPAWN ((uint32_t)1u << 0)
#define GE_PLAYER_CAMERA_OWNER_V6_SOURCE_CAMERA ((uint32_t)1u << 1)
#define GE_PLAYER_CAMERA_OWNER_V6_SOURCE_COLLISION ((uint32_t)1u << 2)
#define GE_PLAYER_CAMERA_OWNER_V6_SOURCE_STAN ((uint32_t)1u << 3)
#define GE_PLAYER_CAMERA_OWNER_V6_SOURCE_WEAPON ((uint32_t)1u << 4)
#define GE_PLAYER_CAMERA_OWNER_V6_SOURCE_HUD ((uint32_t)1u << 5)
#define GE_PLAYER_CAMERA_OWNER_V6_SOURCE_CONTROL ((uint32_t)1u << 6)
#define GE_PLAYER_CAMERA_OWNER_V6_SOURCE_PADS ((uint32_t)1u << 7)
#define GE_PLAYER_CAMERA_OWNER_V6_SOURCE_MASK ((uint32_t)0xffu)

#define GE_PLAYER_CAMERA_OWNER_V6_REQUIRED_SOURCE_MASK \
    (GE_PLAYER_CAMERA_OWNER_V6_SOURCE_SPAWN | \
     GE_PLAYER_CAMERA_OWNER_V6_SOURCE_CAMERA | \
     GE_PLAYER_CAMERA_OWNER_V6_SOURCE_COLLISION | \
     GE_PLAYER_CAMERA_OWNER_V6_SOURCE_STAN | \
     GE_PLAYER_CAMERA_OWNER_V6_SOURCE_WEAPON | \
     GE_PLAYER_CAMERA_OWNER_V6_SOURCE_HUD | \
     GE_PLAYER_CAMERA_OWNER_V6_SOURCE_CONTROL)

#define GE_PLAYER_CAMERA_OWNER_V6_TILE_FLAG_SOURCE_DERIVED ((uint32_t)1u << 0)
#define GE_PLAYER_CAMERA_OWNER_V6_TILE_FLAG_FLOOR ((uint32_t)1u << 1)
#define GE_PLAYER_CAMERA_OWNER_V6_TILE_FLAG_PORTAL ((uint32_t)1u << 2)
#define GE_PLAYER_CAMERA_OWNER_V6_TILE_FLAG_MASK ((uint32_t)0x07u)

#define GE_PLAYER_CAMERA_OWNER_V6_PAD_FLAG_SOURCE_DERIVED ((uint32_t)1u << 0)
#define GE_PLAYER_CAMERA_OWNER_V6_PAD_FLAG_SPAWN ((uint32_t)1u << 1)
#define GE_PLAYER_CAMERA_OWNER_V6_PAD_FLAG_MASK ((uint32_t)0x03u)

#define GE_PLAYER_CAMERA_OWNER_V6_STATE_LOADING ((uint32_t)0u)
#define GE_PLAYER_CAMERA_OWNER_V6_STATE_RUNNING ((uint32_t)1u)
#define GE_PLAYER_CAMERA_OWNER_V6_STATE_ABORTING ((uint32_t)2u)
#define GE_PLAYER_CAMERA_OWNER_V6_STATE_ERROR ((uint32_t)3u)

#define GE_PLAYER_CAMERA_OWNER_V6_STATE_ACTIVE ((uint32_t)1u << 0)
#define GE_PLAYER_CAMERA_OWNER_V6_STATE_SOURCE_ANCHOR ((uint32_t)1u << 1)
#define GE_PLAYER_CAMERA_OWNER_V6_STATE_INTERPOLATED ((uint32_t)1u << 2)
#define GE_PLAYER_CAMERA_OWNER_V6_STATE_REAL_ABORT ((uint32_t)1u << 3)
#define GE_PLAYER_CAMERA_OWNER_V6_STATE_WEAPON_ACTION ((uint32_t)1u << 4)
#define GE_PLAYER_CAMERA_OWNER_V6_STATE_MASK ((uint32_t)0x1fu)

#define GE_PLAYER_CAMERA_OWNER_V6_EVENT_NONE ((uint32_t)0u)
#define GE_PLAYER_CAMERA_OWNER_V6_EVENT_INSTALL ((uint32_t)1u)
#define GE_PLAYER_CAMERA_OWNER_V6_EVENT_SOURCE_ANCHOR ((uint32_t)2u)
#define GE_PLAYER_CAMERA_OWNER_V6_EVENT_INTERPOLANT ((uint32_t)3u)
#define GE_PLAYER_CAMERA_OWNER_V6_EVENT_WEAPON ((uint32_t)4u)
#define GE_PLAYER_CAMERA_OWNER_V6_EVENT_ABORT ((uint32_t)5u)
#define GE_PLAYER_CAMERA_OWNER_V6_EVENT_ERROR ((uint32_t)6u)
#define GE_PLAYER_CAMERA_OWNER_V6_EVENT_MAX GE_PLAYER_CAMERA_OWNER_V6_EVENT_ERROR

#define GE_PLAYER_CAMERA_OWNER_V6_EVENT_SOURCE_ANCHOR_FLAG ((uint32_t)1u << 0)
#define GE_PLAYER_CAMERA_OWNER_V6_EVENT_INTERPOLATED_FLAG ((uint32_t)1u << 1)
#define GE_PLAYER_CAMERA_OWNER_V6_EVENT_WEAPON_FLAG ((uint32_t)1u << 2)
#define GE_PLAYER_CAMERA_OWNER_V6_EVENT_REAL_ABORT_FLAG ((uint32_t)1u << 3)
#define GE_PLAYER_CAMERA_OWNER_V6_EVENT_MASK ((uint32_t)0x0fu)

/* Raw N64 controller values are retained; no host remapping is performed. */
#define GE_PLAYER_CAMERA_OWNER_V6_BUTTON_A ((uint32_t)0x8000u)
#define GE_PLAYER_CAMERA_OWNER_V6_BUTTON_B ((uint32_t)0x4000u)
#define GE_PLAYER_CAMERA_OWNER_V6_BUTTON_Z ((uint32_t)0x2000u)
#define GE_PLAYER_CAMERA_OWNER_V6_BUTTON_START ((uint32_t)0x1000u)
#define GE_PLAYER_CAMERA_OWNER_V6_BUTTON_UP ((uint32_t)0x0800u)
#define GE_PLAYER_CAMERA_OWNER_V6_BUTTON_DOWN ((uint32_t)0x0400u)
#define GE_PLAYER_CAMERA_OWNER_V6_BUTTON_LEFT ((uint32_t)0x0200u)
#define GE_PLAYER_CAMERA_OWNER_V6_BUTTON_RIGHT ((uint32_t)0x0100u)
#define GE_PLAYER_CAMERA_OWNER_V6_BUTTON_L ((uint32_t)0x0020u)
#define GE_PLAYER_CAMERA_OWNER_V6_BUTTON_R ((uint32_t)0x0010u)

typedef struct GEPlayerCameraSourceV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t stage_id;
    uint32_t demo_mask;
    uint32_t flags;
    uint32_t control_style;
    uint32_t invert_look;
    uint32_t source_spawn_offset;
    uint32_t source_camera_offset;
    uint32_t source_collision_offset;
    int32_t initial_pitch_q16;
    int32_t camera_offset_q16[3];
    int32_t head_offset_q16[3];
    int32_t collision_radius_q16;
    int32_t collision_height_q16;
    int32_t floor_tolerance_q16;
    int32_t pad_select_radius_q16;
    uint32_t initial_weapon;
    uint32_t initial_ammo;
    uint32_t initial_health;
    uint32_t initial_animation;
    uint64_t source_hash;
    uint64_t setup_hash;
    uint64_t player_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GEPlayerCameraSourceV6;

typedef struct GEPlayerCameraStanTileV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t tile_id;
    uint32_t room_id;
    uint32_t flags;
    uint32_t point_count;
    int32_t points_q16[10][3];
    uint64_t source_hash;
    uint32_t source_offset;
    uint32_t reserved0;
    uint32_t reserved1;
} GEPlayerCameraStanTileV6;

typedef struct GEPlayerCameraPadV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t pad_id;
    uint32_t room_id;
    uint32_t flags;
    int32_t position_q16[3];
    int32_t forward_q16[3];
    uint32_t source_offset;
    uint32_t reserved0;
    uint32_t reserved1;
} GEPlayerCameraPadV6;

typedef struct GEPlayerCameraSnapshotV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t flags;
    uint32_t demo_id;
    uint32_t stage_id;
    uint64_t native_tick;
    uint64_t reference_tick;
    uint32_t pair_phase;
    uint32_t source_anchor;
    uint32_t current_room;
    uint32_t current_pad;
    uint32_t weapon_model_handle;
    uint32_t weapon_action;
    uint32_t player_health;
    uint32_t hud_ammo;
    uint32_t player_animation;
    int32_t player_position_q16[3];
    int32_t player_velocity_q16[3];
    int32_t camera_position_q16[3];
    int32_t camera_forward_q16[3];
    int32_t camera_up_q16[3];
    int32_t yaw_q16;
    int32_t pitch_q16;
    uint64_t source_hash;
    uint64_t state_hash;
    uint64_t render_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GEPlayerCameraSnapshotV6;

typedef struct GEPlayerCameraEventV6 {
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
    uint32_t current_room;
    uint32_t current_pad;
    uint32_t weapon_action;
    uint32_t detail0;
    uint32_t detail1;
    uint64_t source_hash;
    uint64_t state_hash;
    uint64_t event_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GEPlayerCameraEventV6;

typedef struct GEPlayerCameraOwnerStateV6 {
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
    uint32_t source_anchor;
    uint32_t current_room;
    uint32_t current_pad;
    uint32_t weapon_action;
    uint32_t weapon_sequence;
    uint32_t tile_count;
    uint32_t pad_count;
    uint64_t source_hash;
    uint64_t setup_hash;
    uint64_t player_hash;
    uint64_t state_hash;
    GERamRomGameplaySetupV6 setup;
    GEPlayerCameraSourceV6 source;
    GEPlayerCameraSnapshotV6 previous_anchor;
    GEPlayerCameraSnapshotV6 current_anchor;
    GEPlayerCameraSnapshotV6 render_snapshot;
    GEPlayerCameraStanTileV6 stan[GE_PLAYER_CAMERA_OWNER_V6_MAX_STAN_TILES];
    GEPlayerCameraPadV6 pads[GE_PLAYER_CAMERA_OWNER_V6_MAX_PADS];
} GEPlayerCameraOwnerStateV6;

GEStatusV1 ge_player_camera_owner_validate_source(const GEPlayerCameraSourceV6 *value);
GEStatusV1 ge_player_camera_owner_validate_tile(const GEPlayerCameraStanTileV6 *value);
GEStatusV1 ge_player_camera_owner_validate_pad(const GEPlayerCameraPadV6 *value);
GEStatusV1 ge_player_camera_owner_validate_snapshot(const GEPlayerCameraSnapshotV6 *value);
GEStatusV1 ge_player_camera_owner_validate_event(const GEPlayerCameraEventV6 *value);
GEStatusV1 ge_player_camera_owner_validate_state(const GEPlayerCameraOwnerStateV6 *value);

uint64_t ge_player_camera_owner_hash_snapshot(const GEPlayerCameraSnapshotV6 *value);
uint64_t ge_player_camera_owner_hash_event(const GEPlayerCameraEventV6 *value);

/* The setup/entity arrays and source pages are borrowed for this call only. */
GEStatusV1 ge_player_camera_owner_begin_from_gameplay_pages(
    uint32_t demo_id,
    const GERamRomGameplaySetupV6 *setup,
    const GERamRomGameplayEntityV6 *entities,
    uint32_t entity_count,
    const GEPlayerCameraSourceV6 *source,
    const GEPlayerCameraStanTileV6 *stan,
    uint32_t stan_count,
    const GEPlayerCameraPadV6 *pads,
    uint32_t pad_count,
    GEPlayerCameraOwnerStateV6 *out_state,
    GEPlayerCameraEventV6 *out_event);

/* Source input is taken from GERamRomGameplayInputV6.  Only source anchors
   mutate the owner; odd native ticks copy an interpolated snapshot. */
GEStatusV1 ge_player_camera_owner_step(
    uint64_t native_tick,
    GERamRomGameplayInputV6 input,
    GEPlayerCameraOwnerStateV6 *inout_state,
    GEPlayerCameraEventV6 *out_event);

GEStatusV1 ge_player_camera_owner_copy_snapshot(
    const GEPlayerCameraOwnerStateV6 *state,
    GEPlayerCameraSnapshotV6 *out_snapshot);

GEStatusV1 ge_player_camera_owner_restore(
    GEPlayerCameraOwnerStateV6 *inout_state,
    const GEPlayerCameraSnapshotV6 *snapshot);

#if defined(__cplusplus)
#define GE_PLAYER_CAMERA_OWNER_V6_STATIC_ASSERT(condition, message) static_assert((condition), message)
#else
#define GE_PLAYER_CAMERA_OWNER_V6_STATIC_ASSERT(condition, message) _Static_assert((condition), message)
#endif

GE_PLAYER_CAMERA_OWNER_V6_STATIC_ASSERT(sizeof(GEPlayerCameraSourceV6) == 136u,
                                         "player camera source layout drift");
GE_PLAYER_CAMERA_OWNER_V6_STATIC_ASSERT(sizeof(GEPlayerCameraStanTileV6) == 176u,
                                         "player camera STAN tile layout drift");
GE_PLAYER_CAMERA_OWNER_V6_STATIC_ASSERT(sizeof(GEPlayerCameraPadV6) == 60u,
                                         "player camera pad layout drift");
GE_PLAYER_CAMERA_OWNER_V6_STATIC_ASSERT(sizeof(GEPlayerCameraSnapshotV6) == 176u,
                                         "player camera snapshot layout drift");
GE_PLAYER_CAMERA_OWNER_V6_STATIC_ASSERT(sizeof(GEPlayerCameraEventV6) == 104u,
                                         "player camera event layout drift");

#undef GE_PLAYER_CAMERA_OWNER_V6_STATIC_ASSERT

#ifdef __cplusplus
}
#endif

#endif /* GE_PLAYER_CAMERA_OWNER_V6_H */
