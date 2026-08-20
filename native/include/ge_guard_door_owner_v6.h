#ifndef GE_GUARD_DOOR_OWNER_V6_H
#define GE_GUARD_DOOR_OWNER_V6_H

/*
 * Directly compiled source owner for RAMROM-reachable guards and doors.
 *
 * This is an additive, value-only seam.  The source page records are copied
 * for one call, and the owner retains only fixed-width values.  Pointers,
 * segmented addresses, ROM offsets, filesystem paths, model graphs, and
 * Metal objects never cross this boundary.  Autonomous decisions and RNG
 * consume work only on even (60 Hz source) ticks.  Odd ticks expose the
 * declared midpoint between the two source poses/door transforms and do no
 * source side effects.
 */

#include <stdint.h>

#include "ge_native_foundation.h"
#include "ge_source_scene_v6.h"

/* The concrete gameplay records are defined by ge_ramrom_gameplay_v6.h.
   Forward declarations keep this owner header independently includable and
   allow the gameplay header to expose the owner integration APIs without a
   recursive include. */
typedef struct GERamRomGameplayEntityV6 GERamRomGameplayEntityV6;
typedef struct GERamRomGameplayAttachmentV6 GERamRomGameplayAttachmentV6;

#ifdef __cplusplus
extern "C" {
#endif

#define GE_GUARD_DOOR_OWNER_V6_CONTRACT_VERSION ((uint32_t)6u)
#define GE_GUARD_DOOR_OWNER_V6_RECORD_VERSION ((uint32_t)1u)
#define GE_GUARD_DOOR_OWNER_V6_NATIVE_HZ ((uint32_t)120u)
#define GE_GUARD_DOOR_OWNER_V6_REFERENCE_HZ ((uint32_t)60u)

#define GE_GUARD_DOOR_OWNER_V6_MAX_GUARDS ((uint32_t)128u)
#define GE_GUARD_DOOR_OWNER_V6_MAX_DOORS ((uint32_t)128u)
#define GE_GUARD_DOOR_OWNER_V6_MAX_POSES_PER_GUARD ((uint32_t)64u)
#define GE_GUARD_DOOR_OWNER_V6_MAX_ATTACHMENTS_PER_GUARD ((uint32_t)8u)
#define GE_GUARD_DOOR_OWNER_V6_MAX_CHOICES ((uint32_t)32u)
#define GE_GUARD_DOOR_OWNER_V6_PAGE_ITEMS ((uint32_t)32u)
#define GE_GUARD_DOOR_OWNER_V6_UNKNOWN_U32 UINT32_MAX

#define GE_GUARD_DOOR_OWNER_V6_GUARD_FLAG_MALE ((uint32_t)1u << 0)
#define GE_GUARD_DOOR_OWNER_V6_GUARD_FLAG_CLONE ((uint32_t)1u << 1)
#define GE_GUARD_DOOR_OWNER_V6_GUARD_FLAG_INVINCIBLE ((uint32_t)1u << 2)
#define GE_GUARD_DOOR_OWNER_V6_GUARD_FLAG_LOOP_ANIMATION ((uint32_t)1u << 3)
#define GE_GUARD_DOOR_OWNER_V6_GUARD_FLAG_HIDDEN ((uint32_t)1u << 4)
#define GE_GUARD_DOOR_OWNER_V6_GUARD_FLAG_NO_TRANSLATION ((uint32_t)1u << 5)
#define GE_GUARD_DOOR_OWNER_V6_GUARD_FLAG_MASK ((uint32_t)0x3fu)

#define GE_GUARD_DOOR_OWNER_V6_DOOR_FLAG_OPEN_TO_FRONT ((uint32_t)1u << 0)
#define GE_GUARD_DOOR_OWNER_V6_DOOR_FLAG_TWO_WAY ((uint32_t)1u << 1)
#define GE_GUARD_DOOR_OWNER_V6_DOOR_FLAG_KEEP_OPEN ((uint32_t)1u << 2)
#define GE_GUARD_DOOR_OWNER_V6_DOOR_FLAG_FLIP ((uint32_t)1u << 3)
#define GE_GUARD_DOOR_OWNER_V6_DOOR_FLAG_WINDOWED ((uint32_t)1u << 4)
#define GE_GUARD_DOOR_OWNER_V6_DOOR_FLAG_CLIP_TO_BBOX ((uint32_t)1u << 5)
#define GE_GUARD_DOOR_OWNER_V6_DOOR_FLAG_MASK ((uint32_t)0x3fu)

#define GE_GUARD_DOOR_OWNER_V6_DOOR_STATE_STATIONARY ((uint32_t)0u)
#define GE_GUARD_DOOR_OWNER_V6_DOOR_STATE_OPENING ((uint32_t)1u)
#define GE_GUARD_DOOR_OWNER_V6_DOOR_STATE_CLOSING ((uint32_t)2u)
#define GE_GUARD_DOOR_OWNER_V6_DOOR_STATE_WAITING ((uint32_t)3u)

#define GE_GUARD_DOOR_OWNER_V6_DOOR_TYPE_SLIDING ((uint32_t)0u)
#define GE_GUARD_DOOR_OWNER_V6_DOOR_TYPE_FLEXI1 ((uint32_t)1u)
#define GE_GUARD_DOOR_OWNER_V6_DOOR_TYPE_FLEXI2 ((uint32_t)2u)
#define GE_GUARD_DOOR_OWNER_V6_DOOR_TYPE_FLEXI3 ((uint32_t)3u)
#define GE_GUARD_DOOR_OWNER_V6_DOOR_TYPE_VERTICAL ((uint32_t)4u)
#define GE_GUARD_DOOR_OWNER_V6_DOOR_TYPE_SWINGING ((uint32_t)5u)
#define GE_GUARD_DOOR_OWNER_V6_DOOR_TYPE_EYE ((uint32_t)6u)
#define GE_GUARD_DOOR_OWNER_V6_DOOR_TYPE_IRIS ((uint32_t)7u)
#define GE_GUARD_DOOR_OWNER_V6_DOOR_TYPE_FALLAWAY ((uint32_t)8u)
#define GE_GUARD_DOOR_OWNER_V6_DOOR_TYPE_AZTECCHAIR ((uint32_t)9u)
#define GE_GUARD_DOOR_OWNER_V6_DOOR_TYPE_MAX GE_GUARD_DOOR_OWNER_V6_DOOR_TYPE_AZTECCHAIR

#define GE_GUARD_DOOR_OWNER_V6_SETUP_FLAG_POSES ((uint32_t)1u << 0)
#define GE_GUARD_DOOR_OWNER_V6_SETUP_FLAG_AI ((uint32_t)1u << 1)
#define GE_GUARD_DOOR_OWNER_V6_SETUP_FLAG_BOUND_PAD_TRANSFORMS ((uint32_t)1u << 2)
#define GE_GUARD_DOOR_OWNER_V6_SETUP_FLAG_MODEL_DEPENDENCIES ((uint32_t)1u << 3)
#define GE_GUARD_DOOR_OWNER_V6_SETUP_FLAG_SOURCE_READY ((uint32_t)1u << 4)
#define GE_GUARD_DOOR_OWNER_V6_SETUP_FLAG_MASK ((uint32_t)0x1fu)

#define GE_GUARD_DOOR_OWNER_V6_ENTITY_FLAG_ACTIVE ((uint32_t)1u << 0)
#define GE_GUARD_DOOR_OWNER_V6_ENTITY_FLAG_VISIBLE ((uint32_t)1u << 1)
#define GE_GUARD_DOOR_OWNER_V6_ENTITY_FLAG_INTERPOLATED ((uint32_t)1u << 2)
#define GE_GUARD_DOOR_OWNER_V6_ENTITY_FLAG_SOURCE_ANCHOR ((uint32_t)1u << 3)
#define GE_GUARD_DOOR_OWNER_V6_ENTITY_FLAG_DEAD ((uint32_t)1u << 4)
#define GE_GUARD_DOOR_OWNER_V6_ENTITY_FLAG_ACTION ((uint32_t)1u << 5)
#define GE_GUARD_DOOR_OWNER_V6_ENTITY_FLAG_MASK ((uint32_t)0x3fu)

#define GE_GUARD_DOOR_OWNER_V6_EVENT_INSTALL ((uint32_t)1u)
#define GE_GUARD_DOOR_OWNER_V6_EVENT_SOURCE_ANCHOR ((uint32_t)2u)
#define GE_GUARD_DOOR_OWNER_V6_EVENT_INTERPOLATED ((uint32_t)3u)
#define GE_GUARD_DOOR_OWNER_V6_EVENT_ERROR ((uint32_t)4u)

typedef struct GEGuardDoorOwnerSetupV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t demo_id;
    uint32_t stage_id;
    uint32_t flags;
    uint32_t source_bytes;
    uint32_t guard_count;
    uint32_t door_count;
    uint32_t room_count;
    uint32_t portal_count;
    uint64_t source_hash;
    uint64_t packet_hash;
    uint64_t model_dependency_hash;
    uint64_t animation_source_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GEGuardDoorOwnerSetupV6;

typedef struct GEGuardDoorOwnerChoiceV6 {
    uint32_t source_id;
    uint32_t model_handle;
    uint32_t source_handle;
    uint32_t flags;
} GEGuardDoorOwnerChoiceV6;

typedef struct GEGuardDoorOwnerAttachmentV6 {
    uint32_t switch_handle;
    uint32_t parent_joint;
    uint32_t model_handle;
    uint32_t source_matrix_handle;
    uint32_t flags;
    int32_t transform_q16[16];
    uint64_t source_hash;
} GEGuardDoorOwnerAttachmentV6;

/* Source GuardRecord words plus prepared model/pose identity.  `body_id`,
   `head_id`, and `weapon_id` may be UINT32_MAX only when the corresponding
   bounded choice table is populated; no fallback identity is permitted. */
typedef struct GEGuardDoorOwnerGuardSourceV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t source_record_offset;
    uint32_t guard_id;
    uint32_t chr_num;
    uint32_t pad_id;
    uint32_t body_id;
    uint32_t head_id;
    uint32_t weapon_id;
    uint32_t ai_list_id;
    uint32_t preset;
    uint32_t chr_preset;
    uint32_t health;
    uint32_t reaction_time;
    uint32_t source_bitflags;
    uint32_t flags;
    uint32_t body_model_handle;
    uint32_t head_model_handle;
    uint32_t weapon_model_handle;
    uint32_t skeleton_handle;
    uint32_t animation_id;
    uint32_t animation_frame_count;
    int32_t animation_frame_q16;
    int32_t animation_next_frame_q16;
    int32_t animation_speed_q16;
    int32_t animation_merge_q16;
    uint32_t animation_flip_flags;
    uint32_t action_state;
    uint32_t death_state;
    uint32_t visibility_state;
    uint32_t ai_state;
    uint32_t render_flags;
    uint32_t zbuffer_mode;
    uint32_t environment_rgba;
    uint32_t fog_rgba;
    uint32_t raw_other_mode_h;
    uint32_t raw_other_mode_l;
    uint32_t raw_render_mode;
    uint32_t health_current;
    int32_t position_q16[3];
    int32_t next_position_q16[3];
    int32_t velocity_q16[3];
    int32_t rotation_q16[3];
    int32_t scale_q16[3];
    int32_t world_transform_q16[16];
    int32_t root_motion_q16[3];
    int32_t root_motion_next_q16[3];
    uint32_t pose_first;
    uint32_t pose_count;
    uint32_t pose_next_first;
    uint32_t pose_next_count;
    uint32_t attachment_first;
    uint32_t attachment_count;
    uint32_t body_choice_count;
    uint32_t head_choice_count;
    uint32_t weapon_choice_count;
    GEGuardDoorOwnerChoiceV6 body_choices[GE_GUARD_DOOR_OWNER_V6_MAX_CHOICES];
    GEGuardDoorOwnerChoiceV6 head_choices[GE_GUARD_DOOR_OWNER_V6_MAX_CHOICES];
    GEGuardDoorOwnerChoiceV6 weapon_choices[GE_GUARD_DOOR_OWNER_V6_MAX_CHOICES];
    uint64_t source_hash;
    uint64_t animation_hash;
    uint64_t pose_hash;
    uint64_t source_event_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GEGuardDoorOwnerGuardSourceV6;

/* Source DoorRecord values needed by doorInit/doorSetOpenState/
   updateDoorDisplacement/door7F0526EC.  Displacement and transforms are
   source-quantized Q16 values; serialized float words are decoded before this
   boundary and their source hash is retained for parity evidence. */
typedef struct GEGuardDoorOwnerDoorSourceV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t source_record_offset;
    uint32_t door_id;
    uint32_t object_id;
    uint32_t pad_id;
    uint32_t linked_door_id;
    uint32_t source_flags;
    uint32_t source_flags2;
    uint32_t door_flags;
    uint32_t door_type;
    uint32_t key_flags;
    uint32_t auto_close_frames;
    uint32_t portal_number;
    uint32_t open_state;
    uint32_t visibility_state;
    uint32_t model_handle;
    int32_t max_frac_q16;
    int32_t perim_frac_q16;
    int32_t accel_q16;
    int32_t decel_q16;
    int32_t max_speed_q16;
    int32_t frac_q16[3];
    int32_t runtime_position_q16[3];
    int32_t base_transform_q16[16];
    int32_t open_position_q16;
    int32_t next_open_position_q16;
    int32_t speed_q16;
    int32_t next_speed_q16;
    int32_t collision_bottom_q16;
    int32_t collision_top_q16;
    uint32_t portal_active;
    uint32_t source_hash;
    uint64_t source_hash64;
    uint64_t source_event_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GEGuardDoorOwnerDoorSourceV6;

typedef struct GEGuardDoorOwnerGuardStateV6 {
    GEGuardDoorOwnerGuardSourceV6 source;
    uint32_t selected_body_id;
    uint32_t selected_head_id;
    uint32_t selected_weapon_id;
    uint32_t selected_body_model_handle;
    uint32_t selected_head_model_handle;
    uint32_t selected_weapon_model_handle;
    uint32_t entity_flags;
    uint32_t interpolated;
    uint32_t source_anchor;
    uint32_t pose_count;
    uint32_t pose_next_count;
    GESourceAnimationPoseV6 poses[GE_GUARD_DOOR_OWNER_V6_MAX_POSES_PER_GUARD];
    GESourceAnimationPoseV6 next_poses[GE_GUARD_DOOR_OWNER_V6_MAX_POSES_PER_GUARD];
    GEGuardDoorOwnerAttachmentV6 attachments[GE_GUARD_DOOR_OWNER_V6_MAX_ATTACHMENTS_PER_GUARD];
} GEGuardDoorOwnerGuardStateV6;

typedef struct GEGuardDoorOwnerDoorStateV6 {
    GEGuardDoorOwnerDoorSourceV6 source;
    uint32_t entity_flags;
    uint32_t interpolated;
    uint32_t source_anchor;
    int32_t transform_q16[16];
    int32_t next_transform_q16[16];
} GEGuardDoorOwnerDoorStateV6;

typedef struct GEGuardDoorOwnerStateV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t demo_id;
    uint32_t stage_id;
    uint64_t native_tick;
    uint64_t reference_tick;
    uint32_t pair_phase;
    uint32_t source_anchor;
    uint32_t guard_count;
    uint32_t door_count;
    uint32_t attachment_count;
    uint32_t rng_seed;
    uint64_t rng_checkpoint_hash;
    uint64_t source_hash;
    uint64_t render_hash;
    uint64_t state_hash;
    uint64_t event_hash;
    GEGuardDoorOwnerSetupV6 setup;
    GEGuardDoorOwnerGuardStateV6 guards[GE_GUARD_DOOR_OWNER_V6_MAX_GUARDS];
    GEGuardDoorOwnerDoorStateV6 doors[GE_GUARD_DOOR_OWNER_V6_MAX_DOORS];
    uint32_t reserved0;
    uint32_t reserved1;
} GEGuardDoorOwnerStateV6;

typedef struct GEGuardDoorOwnerEventV6 {
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
    uint32_t guard_count;
    uint32_t door_count;
    uint32_t attachment_count;
    uint32_t rng_seed;
    uint64_t rng_checkpoint_hash;
    uint64_t source_hash;
    uint64_t state_hash;
    uint64_t render_hash;
    uint64_t event_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GEGuardDoorOwnerEventV6;

GEStatusV1 ge_guard_door_owner_v6_validate_setup(const GEGuardDoorOwnerSetupV6 *value);
GEStatusV1 ge_guard_door_owner_v6_validate_guard(
    const GEGuardDoorOwnerGuardSourceV6 *value);
GEStatusV1 ge_guard_door_owner_v6_validate_door(
    const GEGuardDoorOwnerDoorSourceV6 *value);
GEStatusV1 ge_guard_door_owner_v6_validate_pose(
    const GESourceAnimationPoseV6 *value);

GEStatusV1 ge_guard_door_owner_v6_begin(
    const GEGuardDoorOwnerSetupV6 *setup,
    const GEGuardDoorOwnerGuardSourceV6 *guards,
    uint32_t guard_count,
    const GEGuardDoorOwnerDoorSourceV6 *doors,
    uint32_t door_count,
    const GESourceAnimationPoseV6 *poses,
    uint32_t pose_count,
    const GEGuardDoorOwnerAttachmentV6 *attachments,
    uint32_t attachment_count,
    uint64_t rng_seed,
    GEGuardDoorOwnerStateV6 *out_state,
    GEGuardDoorOwnerEventV6 *out_event);

/* Even ticks are source anchors and require complete source rows.  Odd ticks
   pass NULL pages and expose the declared midpoint without consuming RNG or
   changing AI/door state. */
GEStatusV1 ge_guard_door_owner_v6_step(
    uint64_t native_tick,
    const GEGuardDoorOwnerGuardSourceV6 *guards,
    uint32_t guard_count,
    const GEGuardDoorOwnerDoorSourceV6 *doors,
    uint32_t door_count,
    const GESourceAnimationPoseV6 *poses,
    uint32_t pose_count,
    const GEGuardDoorOwnerAttachmentV6 *attachments,
    uint32_t attachment_count,
    GEGuardDoorOwnerStateV6 *inout_state,
    GEGuardDoorOwnerEventV6 *out_event);

/* Source-authority step for pages whose setup carries complete pose, AI,
   model, and bound-pad evidence.  It advances door acceleration/portal state
   and guard frame/root/action state only on even ticks; odd ticks publish the
   owner-declared interpolation.  Incomplete pages return unsupported rather
   than consuming guessed AI or animation data. */
GEStatusV1 ge_guard_door_owner_v6_step_source_authority(
    uint64_t native_tick,
    GEGuardDoorOwnerStateV6 *inout_state,
    GEGuardDoorOwnerEventV6 *out_event);

GEStatusV1 ge_guard_door_owner_v6_copy_guard_page(
    const GEGuardDoorOwnerStateV6 *state,
    uint32_t first_item,
    uint32_t capacity,
    GEGuardDoorOwnerGuardStateV6 *out_items,
    uint32_t *out_copied);

GEStatusV1 ge_guard_door_owner_v6_copy_door_page(
    const GEGuardDoorOwnerStateV6 *state,
    uint32_t first_item,
    uint32_t capacity,
    GEGuardDoorOwnerDoorStateV6 *out_items,
    uint32_t *out_copied);

/* Narrow adapter into the existing gameplay V6 pages.  Pose records remain
   available through copy_guard_page; this function only publishes entities,
   attachments, and source matrices to the existing bounded owner. */
GEStatusV1 ge_guard_door_owner_v6_copy_gameplay_pages(
    const GEGuardDoorOwnerStateV6 *state,
    uint32_t entity_capacity,
    GERamRomGameplayEntityV6 *out_entities,
    uint32_t attachment_capacity,
    GERamRomGameplayAttachmentV6 *out_attachments,
    uint32_t *out_entity_count,
    uint32_t *out_attachment_count);

uint64_t ge_guard_door_owner_v6_hash_state(const GEGuardDoorOwnerStateV6 *state);
uint64_t ge_guard_door_owner_v6_hash_event(const GEGuardDoorOwnerEventV6 *event);

#if defined(__cplusplus)
#define GE_GUARD_DOOR_OWNER_V6_STATIC_ASSERT(condition, message) static_assert((condition), message)
#else
#define GE_GUARD_DOOR_OWNER_V6_STATIC_ASSERT(condition, message) _Static_assert((condition), message)
#endif

GE_GUARD_DOOR_OWNER_V6_STATIC_ASSERT(sizeof(GEGuardDoorOwnerChoiceV6) == 16u,
                                     "guard/door choice layout drift");
GE_GUARD_DOOR_OWNER_V6_STATIC_ASSERT(sizeof(GEGuardDoorOwnerAttachmentV6) == 96u,
                                     "guard/door attachment layout drift");
GE_GUARD_DOOR_OWNER_V6_STATIC_ASSERT(sizeof(GEGuardDoorOwnerSetupV6) == 88u,
                                     "guard/door setup layout drift");
GE_GUARD_DOOR_OWNER_V6_STATIC_ASSERT(sizeof(GEGuardDoorOwnerGuardSourceV6) == 1920u,
                                     "guard source layout drift");
GE_GUARD_DOOR_OWNER_V6_STATIC_ASSERT(sizeof(GEGuardDoorOwnerDoorSourceV6) == 240u,
                                     "door source layout drift");
GE_GUARD_DOOR_OWNER_V6_STATIC_ASSERT(sizeof(GEGuardDoorOwnerGuardStateV6) == 15024u,
                                     "guard state layout drift");
GE_GUARD_DOOR_OWNER_V6_STATIC_ASSERT(sizeof(GEGuardDoorOwnerDoorStateV6) == 384u,
                                     "door state layout drift");
GE_GUARD_DOOR_OWNER_V6_STATIC_ASSERT(sizeof(GEGuardDoorOwnerStateV6) == 1972424u,
                                     "guard/door owner state layout drift");
GE_GUARD_DOOR_OWNER_V6_STATIC_ASSERT(sizeof(GEGuardDoorOwnerEventV6) == 120u,
                                     "guard/door event layout drift");

#undef GE_GUARD_DOOR_OWNER_V6_STATIC_ASSERT

#ifdef __cplusplus
}
#endif

#endif /* GE_GUARD_DOOR_OWNER_V6_H */
