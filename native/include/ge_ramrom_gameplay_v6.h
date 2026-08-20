#ifndef GE_RAMROM_GAMEPLAY_V6_H
#define GE_RAMROM_GAMEPLAY_V6_H

/*
 * Native, value-only gameplay owner for the source RAMROM attract route.
 *
 * This contract is deliberately additive to the frozen V1-V5 records.  The
 * owner consumes a borrowed RAMROM byte buffer for one call at a time and
 * copies all mutable gameplay values into fixed-width records.  It never
 * retains that buffer, a ROM address, a segmented address, a source pointer,
 * a model graph, or a platform object.  Swift receives immutable snapshots
 * and bounded pages for the entity/attachment tables.
 *
 * Source ordering retained by this owner:
 *   setup/install -> input/camera -> player movement/collision -> room/portal
 *   selection -> props/doors -> character/AI -> weapons/effects -> objective
 *   counters -> source-anchor hash/event publication.
 *
 * The implementation is a portable C slice of the original semantics.  N64
 * DMA, message queues, libultra, RSP/RDP and the ROM are replaced by bounded
 * call-time host seams.  The public records are intentionally independent of
 * the existing V1-V5 playback records so neither layout nor hash can drift.
 */

#include <stdint.h>

#include "ge_native_foundation.h"
#include "ge_ramrom_v5.h"

/* Forward declarations for the additive weapon/effect owner.  The concrete
   records live beside the source-port owner and are included by callers that
   use the integration APIs below; keeping only incomplete types here avoids a
   V6 header cycle and does not alter any existing record layout. */
typedef struct GERamRomWeaponEffectSetupV6 GERamRomWeaponEffectSetupV6;
typedef struct GERamRomWeaponEffectFrameV6 GERamRomWeaponEffectFrameV6;
typedef struct GERamRomWeaponEffectEventRecordV6 GERamRomWeaponEffectEventRecordV6;
typedef struct GERamRomWeaponEffectOwnerStateV6 GERamRomWeaponEffectOwnerStateV6;
#include "ge_guard_door_owner_v6.h"

#ifdef __cplusplus
extern "C" {
#endif

#define GE_RAMROM_GAMEPLAY_V6_CONTRACT_VERSION ((uint32_t)6u)
#define GE_RAMROM_GAMEPLAY_V6_RECORD_VERSION ((uint32_t)1u)
#define GE_RAMROM_GAMEPLAY_V6_NATIVE_HZ ((uint32_t)120u)
#define GE_RAMROM_GAMEPLAY_V6_REFERENCE_HZ ((uint32_t)60u)

#define GE_RAMROM_GAMEPLAY_V6_MAX_ENTITIES ((uint32_t)512u)
#define GE_RAMROM_GAMEPLAY_V6_MAX_ATTACHMENTS ((uint32_t)1024u)
/* Total storage is bounded separately from one copy-out page. */
#define GE_RAMROM_GAMEPLAY_V6_MAX_PAGED_ITEMS ((uint32_t)64u)
#define GE_RAMROM_GAMEPLAY_V6_UNKNOWN_U32 UINT32_MAX

#define GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_SOURCE_DERIVED ((uint32_t)1u << 0)
#define GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_ROOMS ((uint32_t)1u << 1)
#define GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_STAN ((uint32_t)1u << 2)
#define GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_OBJECTS ((uint32_t)1u << 3)
#define GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_AI ((uint32_t)1u << 4)
#define GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_PORTALS ((uint32_t)1u << 5)
#define GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_MODEL_DEPENDENCIES ((uint32_t)1u << 6)
#define GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_MASK ((uint32_t)0x7fu)

#define GE_RAMROM_GAMEPLAY_V6_STATE_LOADING ((uint32_t)0u)
#define GE_RAMROM_GAMEPLAY_V6_STATE_RUNNING ((uint32_t)1u)
#define GE_RAMROM_GAMEPLAY_V6_STATE_ABORTING ((uint32_t)2u)
#define GE_RAMROM_GAMEPLAY_V6_STATE_COMPLETE ((uint32_t)3u)
#define GE_RAMROM_GAMEPLAY_V6_STATE_ERROR ((uint32_t)4u)

#define GE_RAMROM_GAMEPLAY_V6_STATE_FLAG_ACTIVE ((uint32_t)1u << 0)
#define GE_RAMROM_GAMEPLAY_V6_STATE_FLAG_INITIALIZED ((uint32_t)1u << 1)
#define GE_RAMROM_GAMEPLAY_V6_STATE_FLAG_SOURCE_ANCHOR ((uint32_t)1u << 2)
#define GE_RAMROM_GAMEPLAY_V6_STATE_FLAG_RNG_CHECKPOINT ((uint32_t)1u << 3)
#define GE_RAMROM_GAMEPLAY_V6_STATE_FLAG_CHECKSUM ((uint32_t)1u << 4)
#define GE_RAMROM_GAMEPLAY_V6_STATE_FLAG_REAL_ABORT ((uint32_t)1u << 5)
#define GE_RAMROM_GAMEPLAY_V6_STATE_FLAG_RESTORE_READY ((uint32_t)1u << 6)
#define GE_RAMROM_GAMEPLAY_V6_STATE_FLAG_GUARD_DOOR_OWNER ((uint32_t)1u << 7)
#define GE_RAMROM_GAMEPLAY_V6_STATE_FLAG_MASK ((uint32_t)0xffu)

#define GE_RAMROM_GAMEPLAY_V6_INPUT_RECORDED ((uint32_t)1u << 0)
#define GE_RAMROM_GAMEPLAY_V6_INPUT_REAL ((uint32_t)1u << 1)
#define GE_RAMROM_GAMEPLAY_V6_INPUT_FOCUSED ((uint32_t)1u << 2)
#define GE_RAMROM_GAMEPLAY_V6_INPUT_CONTROLLER ((uint32_t)1u << 3)
#define GE_RAMROM_GAMEPLAY_V6_INPUT_SUPPRESS_EDGES ((uint32_t)1u << 4)
#define GE_RAMROM_GAMEPLAY_V6_INPUT_FLAG_MASK ((uint32_t)0x1fu)

#define GE_RAMROM_GAMEPLAY_V6_EVENT_NONE ((uint32_t)0u)
#define GE_RAMROM_GAMEPLAY_V6_EVENT_INSTALL ((uint32_t)1u)
#define GE_RAMROM_GAMEPLAY_V6_EVENT_SOURCE_INPUT ((uint32_t)2u)
#define GE_RAMROM_GAMEPLAY_V6_EVENT_PACKET_ADVANCE ((uint32_t)3u)
#define GE_RAMROM_GAMEPLAY_V6_EVENT_STATE ((uint32_t)4u)
#define GE_RAMROM_GAMEPLAY_V6_EVENT_OBJECTIVE ((uint32_t)5u)
#define GE_RAMROM_GAMEPLAY_V6_EVENT_WEAPON ((uint32_t)6u)
#define GE_RAMROM_GAMEPLAY_V6_EVENT_EFFECT ((uint32_t)7u)
#define GE_RAMROM_GAMEPLAY_V6_EVENT_FADE ((uint32_t)8u)
#define GE_RAMROM_GAMEPLAY_V6_EVENT_RESTORE ((uint32_t)9u)
#define GE_RAMROM_GAMEPLAY_V6_EVENT_ERROR ((uint32_t)10u)
#define GE_RAMROM_GAMEPLAY_V6_EVENT_MAX GE_RAMROM_GAMEPLAY_V6_EVENT_ERROR

#define GE_RAMROM_GAMEPLAY_V6_EVENT_SOURCE_ANCHOR ((uint32_t)1u << 0)
#define GE_RAMROM_GAMEPLAY_V6_EVENT_ODD_PAIRED_TICK ((uint32_t)1u << 1)
#define GE_RAMROM_GAMEPLAY_V6_EVENT_PACKET_ADVANCE_FLAG ((uint32_t)1u << 2)
#define GE_RAMROM_GAMEPLAY_V6_EVENT_RNG_CHECKPOINT ((uint32_t)1u << 3)
#define GE_RAMROM_GAMEPLAY_V6_EVENT_CHECKSUM ((uint32_t)1u << 4)
#define GE_RAMROM_GAMEPLAY_V6_EVENT_ABORTED_INPUT ((uint32_t)1u << 5)
#define GE_RAMROM_GAMEPLAY_V6_EVENT_END_OF_STREAM ((uint32_t)1u << 6)
#define GE_RAMROM_GAMEPLAY_V6_EVENT_CONTINUOUS ((uint32_t)1u << 7)
#define GE_RAMROM_GAMEPLAY_V6_EVENT_ONE_SHOT ((uint32_t)1u << 8)
#define GE_RAMROM_GAMEPLAY_V6_EVENT_MASK ((uint32_t)0x1ffu)

#define GE_RAMROM_GAMEPLAY_V6_PAGE_ENTITIES ((uint32_t)1u)
#define GE_RAMROM_GAMEPLAY_V6_PAGE_ATTACHMENTS ((uint32_t)2u)
#define GE_RAMROM_GAMEPLAY_V6_PAGE_MAX GE_RAMROM_GAMEPLAY_V6_PAGE_ATTACHMENTS

#define GE_RAMROM_GAMEPLAY_V6_ENTITY_PLAYER ((uint32_t)1u)
#define GE_RAMROM_GAMEPLAY_V6_ENTITY_DOOR ((uint32_t)2u)
#define GE_RAMROM_GAMEPLAY_V6_ENTITY_PROP ((uint32_t)3u)
#define GE_RAMROM_GAMEPLAY_V6_ENTITY_GUARD ((uint32_t)4u)
#define GE_RAMROM_GAMEPLAY_V6_ENTITY_OBJECTIVE ((uint32_t)5u)
#define GE_RAMROM_GAMEPLAY_V6_ENTITY_PROJECTILE ((uint32_t)6u)
#define GE_RAMROM_GAMEPLAY_V6_ENTITY_EFFECT ((uint32_t)7u)
#define GE_RAMROM_GAMEPLAY_V6_ENTITY_GLASS ((uint32_t)8u)
#define GE_RAMROM_GAMEPLAY_V6_ENTITY_SKY ((uint32_t)9u)
#define GE_RAMROM_GAMEPLAY_V6_ENTITY_MAX GE_RAMROM_GAMEPLAY_V6_ENTITY_SKY

#define GE_RAMROM_GAMEPLAY_V6_ENTITY_ACTIVE ((uint32_t)1u << 0)
#define GE_RAMROM_GAMEPLAY_V6_ENTITY_VISIBLE ((uint32_t)1u << 1)
#define GE_RAMROM_GAMEPLAY_V6_ENTITY_DEAD ((uint32_t)1u << 2)
#define GE_RAMROM_GAMEPLAY_V6_ENTITY_ACTION ((uint32_t)1u << 3)
#define GE_RAMROM_GAMEPLAY_V6_ENTITY_SOURCE_ANCHOR ((uint32_t)1u << 4)
#define GE_RAMROM_GAMEPLAY_V6_ENTITY_INTERPOLATED ((uint32_t)1u << 5)
#define GE_RAMROM_GAMEPLAY_V6_ENTITY_ATTACHMENT ((uint32_t)1u << 6)
#define GE_RAMROM_GAMEPLAY_V6_ENTITY_FLAG_MASK ((uint32_t)0x7fu)

#define GE_RAMROM_GAMEPLAY_V6_CONTINUOUS_PLAYER ((uint32_t)1u << 0)
#define GE_RAMROM_GAMEPLAY_V6_CONTINUOUS_CAMERA ((uint32_t)1u << 1)
#define GE_RAMROM_GAMEPLAY_V6_CONTINUOUS_ANIMATION ((uint32_t)1u << 2)
#define GE_RAMROM_GAMEPLAY_V6_CONTINUOUS_ROOT_MOTION ((uint32_t)1u << 3)
#define GE_RAMROM_GAMEPLAY_V6_CONTINUOUS_EFFECTS ((uint32_t)1u << 4)
#define GE_RAMROM_GAMEPLAY_V6_DISCRETE_AI ((uint32_t)1u << 0)
#define GE_RAMROM_GAMEPLAY_V6_DISCRETE_RNG ((uint32_t)1u << 1)
#define GE_RAMROM_GAMEPLAY_V6_DISCRETE_OBJECTIVES ((uint32_t)1u << 2)
#define GE_RAMROM_GAMEPLAY_V6_DISCRETE_WEAPONS ((uint32_t)1u << 3)
#define GE_RAMROM_GAMEPLAY_V6_DISCRETE_DOORS ((uint32_t)1u << 4)
#define GE_RAMROM_GAMEPLAY_V6_DISCRETE_ONE_SHOTS ((uint32_t)1u << 5)

typedef struct GERamRomGameplaySetupV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t stage_id;
    uint32_t flags;
    uint32_t demo_mask;
    uint32_t source_bytes;
    uint32_t room_count;
    uint32_t portal_count;
    uint32_t stan_count;
    uint32_t object_count;
    uint32_t door_count;
    uint32_t guard_count;
    uint32_t objective_count;
    uint32_t prop_count;
    uint32_t waypoint_count;
    uint32_t patrol_path_count;
    uint32_t ai_list_count;
    uint32_t tinted_glass_count;
    uint32_t initial_room;
    uint32_t initial_pad;
    uint32_t stan_source_bytes;
    int32_t initial_position_q16[3];
    int32_t initial_forward_q16[3];
    int32_t world_min_q16[3];
    int32_t world_max_q16[3];
    uint64_t source_hash;
    uint64_t packet_hash;
    uint64_t model_dependency_hash;
    uint64_t stan_source_hash;
    uint64_t stan_bounds_hash;
    uint64_t spawn_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GERamRomGameplaySetupV6;

typedef struct GERamRomGameplayInputV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t flags;
    uint32_t pressed_buttons;
    uint32_t held_buttons;
    uint32_t released_buttons;
    int16_t stick_x;
    int16_t stick_y;
    uint16_t controller_index;
    uint16_t controller_count;
    uint32_t source_mask;
    uint64_t timestamp_ns;
    uint64_t sequence;
    uint32_t reserved0;
    uint32_t reserved1;
} GERamRomGameplayInputV6;

/* One character/prop/effect value row.  Body/head/weapon and source render
   state stay together so the character and non-model consumers cannot infer
   missing mutable data from a setup record. */
typedef struct GERamRomGameplayEntityV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t entity_id;
    uint32_t entity_kind;
    uint32_t flags;
    uint32_t body_model_handle;
    uint32_t head_model_handle;
    uint32_t weapon_model_handle;
    uint32_t head_table_index;
    uint32_t skeleton_handle;
    uint32_t animation_id;
    uint32_t attachment_first;
    uint32_t attachment_count;
    uint32_t room_id;
    uint32_t state;
    uint32_t action_state;
    uint32_t death_state;
    uint32_t target_id;
    uint32_t source_prop_type;
    uint32_t source_record_offset;
    uint32_t source_aux0;
    uint32_t source_aux1;
    uint32_t visibility_mask;
    uint32_t render_flags;
    uint32_t zbuffer_mode;
    uint32_t environment_rgba;
    uint32_t fog_rgba;
    uint32_t raw_other_mode_h;
    uint32_t raw_other_mode_l;
    uint32_t raw_render_mode;
    uint32_t health;
    uint32_t max_health;
    int32_t position_q16[3];
    int32_t velocity_q16[3];
    int32_t rotation_q16[3];
    int32_t scale_q16[3];
    int32_t previous_frame_q16;
    int32_t current_frame_q16;
    int32_t merge_weight_q16;
    int32_t root_motion_q16[3];
    /* Exact source model/object basis when supplied by the setup owner. */
    int32_t source_transform_q16[16];
    uint32_t reserved0;
    uint32_t reserved1;
} GERamRomGameplayEntityV6;

typedef struct GERamRomGameplayAttachmentV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t attachment_id;
    uint32_t entity_id;
    uint32_t kind;
    uint32_t switch_handle;
    uint32_t parent_joint;
    uint32_t model_handle;
    uint32_t source_matrix_handle;
    uint32_t flags;
    int32_t transform_q16[16];
    uint32_t reserved0;
    uint32_t reserved1;
} GERamRomGameplayAttachmentV6;

typedef struct GERamRomGameplaySnapshotV6 {
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
    uint32_t continuous_mask;
    uint32_t discrete_mask;
    uint32_t packet_index;
    uint32_t packet_count;
    uint32_t frame_index;
    uint32_t record_count;
    uint32_t speedframes;
    uint32_t rng_seed;
    uint32_t checksum;
    uint32_t computed_checksum;
    uint32_t controller_count;
    uint32_t entity_count;
    uint32_t attachment_count;
    uint32_t current_room;
    uint32_t current_pad;
    uint32_t door_count;
    uint32_t guard_count;
    uint32_t objective_count;
    uint32_t prop_count;
    uint32_t effect_count;
    uint32_t projectile_count;
    uint32_t player_health;
    uint32_t player_weapon;
    uint32_t player_animation;
    int32_t player_position_q16[3];
    int32_t player_velocity_q16[3];
    int32_t camera_position_q16[3];
    int32_t camera_forward_q16[3];
    int32_t camera_up_q16[3];
    uint32_t hud_health;
    uint32_t hud_ammo;
    uint32_t watch_state;
    uint32_t fade_q16;
    uint32_t sky_mode;
    uint32_t input_flags;
    uint32_t input_source_mask;
    uint32_t input_buttons;
    int16_t input_stick_x;
    int16_t input_stick_y;
    uint32_t one_shot_sequence;
    uint64_t source_hash;
    uint64_t packet_hash;
    uint64_t rng_checkpoint_hash;
    uint64_t state_hash;
    uint64_t render_hash;
    uint64_t audio_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GERamRomGameplaySnapshotV6;

typedef struct GERamRomGameplayEventV6 {
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
    uint32_t packet_index;
    uint32_t packet_count;
    uint32_t frame_index;
    uint32_t record_count;
    uint32_t source_anchor;
    uint32_t source_frame;
    uint32_t speedframes;
    uint32_t rng_seed;
    uint32_t checksum;
    uint32_t computed_checksum;
    uint32_t controller_count;
    uint32_t entity_count;
    uint32_t attachment_count;
    uint32_t one_shot_sequence;
    uint32_t detail0;
    uint32_t detail1;
    int16_t stick_x;
    int16_t stick_y;
    uint32_t buttons;
    uint64_t sample_hash;
    uint64_t source_hash;
    uint64_t packet_hash;
    uint64_t rng_checkpoint_hash;
    uint64_t state_hash;
    uint64_t event_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GERamRomGameplayEventV6;

typedef struct GERamRomGameplayPageV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t page_kind;
    uint32_t page_index;
    uint32_t item_size;
    uint32_t first_item;
    uint32_t item_count;
    uint32_t total_items;
    uint64_t page_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GERamRomGameplayPageV6;

typedef struct GERamRomGameplayStateV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t flags;
    uint32_t replay_state;
    uint32_t error_code;
    uint32_t demo_id;
    uint32_t stage_id;
    uint64_t native_tick;
    uint64_t reference_tick;
    uint32_t pair_phase;
    uint32_t source_anchor;
    uint32_t source_anchor_count;
    uint32_t packet_index;
    uint32_t packet_count;
    uint32_t frame_index;
    uint32_t record_count;
    uint32_t controller_count;
    uint32_t speedframes;
    uint32_t rng_seed;
    uint32_t rng_checkpoint_count;
    uint32_t checksum_count;
    uint32_t entity_count;
    uint32_t attachment_count;
    uint32_t one_shot_sequence;
    uint32_t last_buttons;
    uint64_t recording_hash;
    uint64_t packet_hash;
    uint64_t input_hash;
    uint64_t rng_hash;
    uint64_t rng_checkpoint_hash;
    uint64_t gameplay_hash;
    GERamRomGameplaySetupV6 setup;
    GERamRomGameplaySnapshotV6 snapshot;
    GERamRomGameplayInputV6 last_input;
    GERamRomGameplayEntityV6 entities[GE_RAMROM_GAMEPLAY_V6_MAX_ENTITIES];
    GERamRomGameplayAttachmentV6 attachments[GE_RAMROM_GAMEPLAY_V6_MAX_ATTACHMENTS];
} GERamRomGameplayStateV6;

GEStatusV1 ge_ramrom_gameplay_v6_validate_setup(const GERamRomGameplaySetupV6 *value);
GEStatusV1 ge_ramrom_gameplay_v6_validate_input(const GERamRomGameplayInputV6 *value);
GEStatusV1 ge_ramrom_gameplay_v6_validate_entity(const GERamRomGameplayEntityV6 *value);
GEStatusV1 ge_ramrom_gameplay_v6_validate_attachment(const GERamRomGameplayAttachmentV6 *value);
GEStatusV1 ge_ramrom_gameplay_v6_validate_snapshot(const GERamRomGameplaySnapshotV6 *value);
GEStatusV1 ge_ramrom_gameplay_v6_validate_event(const GERamRomGameplayEventV6 *value);
GEStatusV1 ge_ramrom_gameplay_v6_validate_page(const GERamRomGameplayPageV6 *value);
GEStatusV1 ge_ramrom_gameplay_v6_validate_state(const GERamRomGameplayStateV6 *value);

uint64_t ge_ramrom_gameplay_v6_hash_snapshot(const GERamRomGameplaySnapshotV6 *value);
uint64_t ge_ramrom_gameplay_v6_hash_event(const GERamRomGameplayEventV6 *value);

/* Exact source `randomGetNextFrom` transition from src/random.s. The seed is
   caller-owned and borrowed for this call; no global or host RNG is used. */
uint32_t ge_ramrom_gameplay_v6_source_random_next(uint64_t *inout_seed);

/* Exact source `check_ramrom_flags` semantics from src/game/ramromreplay.c:
   the active recording slot is returned only while playback/recording is
   enabled; otherwise zero selects the ordinary setup branch. */
uint32_t ge_ramrom_gameplay_v6_source_check_ramrom_flags(
    uint32_t is_ramrom_flag,
    uint32_t recording_ramrom_flag,
    uint32_t slot_number);

GEStatusV1 ge_ramrom_gameplay_v6_begin(
    const uint8_t *bytes,
    uint32_t byte_count,
    uint32_t demo_id,
    const GERamRomGameplaySetupV6 *setup,
    GERamRomGameplayStateV6 *out_state,
    GERamRomGameplayEventV6 *out_event);

/* Production setup path. Entity and attachment arrays are borrowed only for
   this call. The owner copies them into bounded storage and fails closed when
   the source setup/dependency pages are absent; it never manufactures a
   player, guard, model handle, pose, or attachment. */
GEStatusV1 ge_ramrom_gameplay_v6_begin_with_source_pages(
    const uint8_t *bytes,
    uint32_t byte_count,
    uint32_t demo_id,
    const GERamRomGameplaySetupV6 *setup,
    const GERamRomGameplayEntityV6 *entities,
    uint32_t entity_count,
    const GERamRomGameplayAttachmentV6 *attachments,
    uint32_t attachment_count,
    GERamRomGameplayStateV6 *out_state,
    GERamRomGameplayEventV6 *out_event);

/* Install a validated directly compiled guard/door owner page alongside the
   source player/object pages.  The owner state is borrowed for this call;
   gameplay copies only bounded entity/attachment values and hashes.  Missing
   pose/AI/bound-pad/model evidence remains a fail-closed unsupported result. */
GEStatusV1 ge_ramrom_gameplay_v6_begin_with_source_pages_and_guard_door_owner(
    const uint8_t *bytes,
    uint32_t byte_count,
    uint32_t demo_id,
    const GERamRomGameplaySetupV6 *setup,
    const GERamRomGameplayEntityV6 *entities,
    uint32_t entity_count,
    const GERamRomGameplayAttachmentV6 *attachments,
    uint32_t attachment_count,
    const GEGuardDoorOwnerStateV6 *guard_door_owner,
    GERamRomGameplayStateV6 *out_state,
    GERamRomGameplayEventV6 *out_event);

GEStatusV1 ge_ramrom_gameplay_v6_step(
    const uint8_t *bytes,
    uint32_t byte_count,
    uint64_t native_tick,
    GERamRomGameplayInputV6 input,
    GERamRomGameplayStateV6 *inout_state,
    GERamRomGameplayEventV6 *out_event);

/* Paired owner update.  The owner page must have the same native tick as the
   gameplay step.  Even ticks publish source-anchor side effects; odd ticks
   publish only the owner-declared interpolated page. */
GEStatusV1 ge_ramrom_gameplay_v6_step_with_guard_door_owner(
    const uint8_t *bytes,
    uint32_t byte_count,
    uint64_t native_tick,
    GERamRomGameplayInputV6 input,
    const GEGuardDoorOwnerStateV6 *guard_door_owner,
    GERamRomGameplayStateV6 *inout_state,
    GERamRomGameplayEventV6 *out_event);

GEStatusV1 ge_ramrom_gameplay_v6_seed_entity(
    GERamRomGameplayStateV6 *inout_state,
    const GERamRomGameplayEntityV6 *seed);

GEStatusV1 ge_ramrom_gameplay_v6_seed_attachment(
    GERamRomGameplayStateV6 *inout_state,
    const GERamRomGameplayAttachmentV6 *seed);

GEStatusV1 ge_ramrom_gameplay_v6_copy_snapshot(
    const GERamRomGameplayStateV6 *state,
    GERamRomGameplaySnapshotV6 *out_snapshot);

GEStatusV1 ge_ramrom_gameplay_v6_copy_page(
    const GERamRomGameplayStateV6 *state,
    uint32_t page_kind,
    uint32_t page_index,
    GERamRomGameplayPageV6 *out_page);

GEStatusV1 ge_ramrom_gameplay_v6_copy_entities(
    const GERamRomGameplayStateV6 *state,
    uint32_t first_item,
    uint32_t capacity,
    GERamRomGameplayEntityV6 *out_items,
    uint32_t *out_copied);

GEStatusV1 ge_ramrom_gameplay_v6_copy_attachments(
    const GERamRomGameplayStateV6 *state,
    uint32_t first_item,
    uint32_t capacity,
    GERamRomGameplayAttachmentV6 *out_items,
    uint32_t *out_copied);

GEStatusV1 ge_ramrom_gameplay_v6_restore(
    GERamRomGameplayStateV6 *inout_state,
    const GERamRomGameplaySnapshotV6 *snapshot);

/* Additive source-owner join.  The weapon/effect state remains caller-owned;
   gameplay retains only copied entity rows, hashes, counts, and event
   metadata.  No pointer is stored in GERamRomGameplayStateV6. */
GEStatusV1 ge_ramrom_gameplay_v6_install_weapon_effect(
    GERamRomGameplayStateV6 *inout_state,
    const GERamRomWeaponEffectSetupV6 *setup,
    const GERamRomWeaponEffectFrameV6 *initial_frame,
    GERamRomWeaponEffectOwnerStateV6 *inout_weapon_effect_state,
    GERamRomGameplayEventV6 *out_event);

GEStatusV1 ge_ramrom_gameplay_v6_step_with_weapon_effect(
    const uint8_t *bytes,
    uint32_t byte_count,
    uint64_t native_tick,
    GERamRomGameplayInputV6 input,
    const GERamRomWeaponEffectFrameV6 *source_frame,
    GERamRomWeaponEffectOwnerStateV6 *inout_weapon_effect_state,
    GERamRomGameplayStateV6 *inout_state,
    GERamRomGameplayEventV6 *out_gameplay_event,
    GERamRomWeaponEffectEventRecordV6 *out_weapon_effect_event);

/* Returns one only when a fully validated source owner is installed and
   active.  A null/malformed/missing owner returns zero; callers must keep
   sourceReady false and retain the existing fail-closed route. */
uint32_t ge_ramrom_gameplay_v6_weapon_effect_source_ready(
    const GERamRomWeaponEffectOwnerStateV6 *weapon_effect_state);

#if defined(__cplusplus)
#define GE_RAMROM_GAMEPLAY_V6_STATIC_ASSERT(condition, message) static_assert((condition), message)
#else
#define GE_RAMROM_GAMEPLAY_V6_STATIC_ASSERT(condition, message) _Static_assert((condition), message)
#endif

GE_RAMROM_GAMEPLAY_V6_STATIC_ASSERT(sizeof(GERamRomGameplaySetupV6) == 192u,
                                    "RAMROM gameplay setup layout drift");
GE_RAMROM_GAMEPLAY_V6_STATIC_ASSERT(sizeof(GERamRomGameplayInputV6) == 64u,
                                    "RAMROM gameplay input layout drift");
GE_RAMROM_GAMEPLAY_V6_STATIC_ASSERT(sizeof(GERamRomGameplayEntityV6) == 276u,
                                    "RAMROM gameplay entity layout drift");
GE_RAMROM_GAMEPLAY_V6_STATIC_ASSERT(sizeof(GERamRomGameplayAttachmentV6) == 116u,
                                    "RAMROM gameplay attachment layout drift");
GE_RAMROM_GAMEPLAY_V6_STATIC_ASSERT(sizeof(GERamRomGameplaySnapshotV6) == 304u,
                                    "RAMROM gameplay snapshot layout drift");
GE_RAMROM_GAMEPLAY_V6_STATIC_ASSERT(sizeof(GERamRomGameplayEventV6) == 184u,
                                    "RAMROM gameplay event layout drift");
GE_RAMROM_GAMEPLAY_V6_STATIC_ASSERT(sizeof(GERamRomGameplayPageV6) == 56u,
                                    "RAMROM gameplay page layout drift");
GE_RAMROM_GAMEPLAY_V6_STATIC_ASSERT(sizeof(GERamRomGameplayStateV6) == 260816u,
                                    "RAMROM gameplay state layout drift");

#undef GE_RAMROM_GAMEPLAY_V6_STATIC_ASSERT

#ifdef __cplusplus
}
#endif

#endif /* GE_RAMROM_GAMEPLAY_V6_H */
