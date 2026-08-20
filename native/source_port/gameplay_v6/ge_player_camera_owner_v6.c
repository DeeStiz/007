#include "ge_player_camera_owner_v6.h"

#include <math.h>
#include <stddef.h>
#include <string.h>

#define GE_PLAYER_CAMERA_Q16_ONE ((int64_t)65536)
#define GE_PLAYER_CAMERA_Q16_HALF ((int64_t)32768)
#define GE_PLAYER_CAMERA_DEADZONE ((int32_t)5)
#define GE_PLAYER_CAMERA_STICK_SCALE ((double)70.0)
#define GE_PLAYER_CAMERA_FOV_DEGREES ((double)60.0)
#define GE_PLAYER_CAMERA_TURN_FACTOR ((double)3.5)
#define GE_PLAYER_CAMERA_SPEED_FACTOR ((double)1.08)
#define GE_PLAYER_CAMERA_DEFAULT_SPEEDBOOST_Q16 ((int32_t)65536)
#define GE_PLAYER_CAMERA_MAX_SPEEDBOOST_Q16 ((int32_t)81920)
#define GE_PLAYER_CAMERA_SPEEDBOOST_STEP_Q16 ((int32_t)655)
#define GE_PLAYER_CAMERA_RUN_TICKS ((uint32_t)150u)
#define GE_PLAYER_CAMERA_PI ((double)3.14159265358979323846264338327950288)
#define GE_PLAYER_CAMERA_TAU (GE_PLAYER_CAMERA_PI * (double)2.0)

static const uint64_t GE_PLAYER_CAMERA_FNV_OFFSET = UINT64_C(1469598103934665603);
static const uint64_t GE_PLAYER_CAMERA_FNV_PRIME = UINT64_C(1099511628211);

static uint64_t ge_player_camera_hash_byte(uint64_t hash, uint8_t value)
{
    return (hash ^ (uint64_t)value) * GE_PLAYER_CAMERA_FNV_PRIME;
}

static uint64_t ge_player_camera_hash_u32(uint64_t hash, uint32_t value)
{
    uint32_t shift;
    for (shift = 0u; shift < 32u; shift += 8u) {
        hash = ge_player_camera_hash_byte(hash, (uint8_t)(value >> shift));
    }
    return hash;
}

static uint64_t ge_player_camera_hash_u64(uint64_t hash, uint64_t value)
{
    uint32_t shift;
    for (shift = 0u; shift < 64u; shift += 8u) {
        hash = ge_player_camera_hash_byte(hash, (uint8_t)(value >> shift));
    }
    return hash;
}

static void ge_player_camera_init_header(GEAbiHeaderV1 *header, uint32_t size)
{
    header->abi_version = GE_NATIVE_ABI_VERSION;
    header->struct_size = size;
}

static GEStatusV1 ge_player_camera_validate_common(const GEAbiHeaderV1 *header,
                                                   uint32_t size,
                                                   uint32_t version)
{
    if (header == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (header->abi_version != GE_NATIVE_ABI_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    if (header->struct_size != size) {
        return GE_STATUS_INVALID_SIZE;
    }
    if (version != GE_PLAYER_CAMERA_OWNER_V6_RECORD_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    return GE_STATUS_OK;
}

static int ge_player_camera_q16_is_unknown(int32_t value)
{
    return value == GE_PLAYER_CAMERA_OWNER_V6_UNKNOWN_Q16;
}

static int ge_player_camera_vec3_is_unknown(const int32_t value[3])
{
    return ge_player_camera_q16_is_unknown(value[0]) ||
           ge_player_camera_q16_is_unknown(value[1]) ||
           ge_player_camera_q16_is_unknown(value[2]);
}

static int32_t ge_player_camera_q16_from_double(double value)
{
    double scaled = value * (double)GE_PLAYER_CAMERA_Q16_ONE;
    if (scaled >= (double)INT32_MAX) {
        return INT32_MAX;
    }
    if (scaled <= (double)INT32_MIN + 1.0) {
        return INT32_MIN + 1;
    }
    return (int32_t)llround(scaled);
}

static double ge_player_camera_double_from_q16(int32_t value)
{
    return (double)value / (double)GE_PLAYER_CAMERA_Q16_ONE;
}

static int32_t ge_player_camera_clamp_i32(int64_t value)
{
    if (value > INT32_MAX) {
        return INT32_MAX;
    }
    if (value < INT32_MIN + 1) {
        return INT32_MIN + 1;
    }
    return (int32_t)value;
}

static int32_t ge_player_camera_q16_lerp(int32_t a, int32_t b, int32_t weight_q16)
{
    int64_t delta = (int64_t)b - (int64_t)a;
    return ge_player_camera_clamp_i32((int64_t)a +
                                      ((delta * (int64_t)weight_q16 + GE_PLAYER_CAMERA_Q16_HALF) /
                                       GE_PLAYER_CAMERA_Q16_ONE));
}

static int32_t ge_player_camera_angle_normalize(int32_t angle_q16)
{
    const int64_t full = INT64_C(360) * GE_PLAYER_CAMERA_Q16_ONE;
    int64_t value = angle_q16;
    while (value < 0) {
        value += full;
    }
    while (value >= full) {
        value -= full;
    }
    return (int32_t)value;
}

static int32_t ge_player_camera_pitch_clamp(int32_t pitch_q16)
{
    const int32_t min_pitch = -90 * (int32_t)GE_PLAYER_CAMERA_Q16_ONE;
    const int32_t max_pitch = 90 * (int32_t)GE_PLAYER_CAMERA_Q16_ONE;
    if (pitch_q16 < min_pitch) {
        return min_pitch;
    }
    if (pitch_q16 > max_pitch) {
        return max_pitch;
    }
    return pitch_q16;
}

static void ge_player_camera_normalize3(double vector[3])
{
    double length = sqrt((vector[0] * vector[0]) +
                         (vector[1] * vector[1]) +
                         (vector[2] * vector[2]));
    if (length <= 0.0) {
        vector[0] = 0.0;
        vector[1] = 0.0;
        vector[2] = 1.0;
        return;
    }
    vector[0] /= length;
    vector[1] /= length;
    vector[2] /= length;
}

static uint64_t ge_player_camera_hash_snapshot_fields(
    const GEPlayerCameraSnapshotV6 *snapshot)
{
    uint64_t hash = GE_PLAYER_CAMERA_FNV_OFFSET;
    uint32_t index;
    hash = ge_player_camera_hash_u32(hash, snapshot->flags);
    hash = ge_player_camera_hash_u32(hash, snapshot->demo_id);
    hash = ge_player_camera_hash_u32(hash, snapshot->stage_id);
    hash = ge_player_camera_hash_u64(hash, snapshot->native_tick);
    hash = ge_player_camera_hash_u64(hash, snapshot->reference_tick);
    hash = ge_player_camera_hash_u32(hash, snapshot->pair_phase);
    hash = ge_player_camera_hash_u32(hash, snapshot->source_anchor);
    hash = ge_player_camera_hash_u32(hash, snapshot->current_room);
    hash = ge_player_camera_hash_u32(hash, snapshot->current_pad);
    hash = ge_player_camera_hash_u32(hash, snapshot->weapon_model_handle);
    hash = ge_player_camera_hash_u32(hash, snapshot->weapon_action);
    hash = ge_player_camera_hash_u32(hash, snapshot->player_health);
    hash = ge_player_camera_hash_u32(hash, snapshot->hud_ammo);
    hash = ge_player_camera_hash_u32(hash, snapshot->player_animation);
    for (index = 0u; index < 3u; index++) {
        hash = ge_player_camera_hash_u32(hash, (uint32_t)snapshot->player_position_q16[index]);
        hash = ge_player_camera_hash_u32(hash, (uint32_t)snapshot->player_velocity_q16[index]);
        hash = ge_player_camera_hash_u32(hash, (uint32_t)snapshot->camera_position_q16[index]);
        hash = ge_player_camera_hash_u32(hash, (uint32_t)snapshot->camera_forward_q16[index]);
        hash = ge_player_camera_hash_u32(hash, (uint32_t)snapshot->camera_up_q16[index]);
    }
    hash = ge_player_camera_hash_u32(hash, (uint32_t)snapshot->yaw_q16);
    hash = ge_player_camera_hash_u32(hash, (uint32_t)snapshot->pitch_q16);
    hash = ge_player_camera_hash_u64(hash, snapshot->source_hash);
    return hash;
}

uint64_t ge_player_camera_owner_hash_snapshot(const GEPlayerCameraSnapshotV6 *value)
{
    if (value == NULL) {
        return 0u;
    }
    return ge_player_camera_hash_snapshot_fields(value);
}

uint64_t ge_player_camera_owner_hash_event(const GEPlayerCameraEventV6 *value)
{
    uint64_t hash;
    if (value == NULL) {
        return 0u;
    }
    hash = GE_PLAYER_CAMERA_FNV_OFFSET;
    hash = ge_player_camera_hash_u32(hash, value->event_type);
    hash = ge_player_camera_hash_u32(hash, value->flags);
    hash = ge_player_camera_hash_u32(hash, value->diagnostic_code);
    hash = ge_player_camera_hash_u64(hash, value->native_tick);
    hash = ge_player_camera_hash_u64(hash, value->reference_tick);
    hash = ge_player_camera_hash_u32(hash, value->pair_phase);
    hash = ge_player_camera_hash_u32(hash, value->demo_id);
    hash = ge_player_camera_hash_u32(hash, value->stage_id);
    hash = ge_player_camera_hash_u32(hash, value->current_room);
    hash = ge_player_camera_hash_u32(hash, value->current_pad);
    hash = ge_player_camera_hash_u32(hash, value->weapon_action);
    hash = ge_player_camera_hash_u32(hash, value->detail0);
    hash = ge_player_camera_hash_u32(hash, value->detail1);
    hash = ge_player_camera_hash_u64(hash, value->source_hash);
    hash = ge_player_camera_hash_u64(hash, value->state_hash);
    return hash;
}

GEStatusV1 ge_player_camera_owner_validate_source(const GEPlayerCameraSourceV6 *value)
{
    GEStatusV1 status;
    uint32_t required = GE_PLAYER_CAMERA_OWNER_V6_REQUIRED_SOURCE_MASK;
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_player_camera_validate_common(&value->header,
                                              (uint32_t)sizeof(*value),
                                              value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->stage_id == 0u || value->demo_mask == 0u ||
        (value->flags & ~GE_PLAYER_CAMERA_OWNER_V6_SOURCE_MASK) != 0u ||
        (value->flags & required) != required ||
        value->control_style > GE_PLAYER_CAMERA_OWNER_V6_CONTROL_MAX ||
        value->invert_look > 1u || value->collision_radius_q16 <= 0 ||
        value->collision_height_q16 <= 0 || value->floor_tolerance_q16 < 0 ||
        value->source_hash == 0u || value->setup_hash == 0u ||
        value->player_hash == 0u || value->initial_weapon ==
            GE_PLAYER_CAMERA_OWNER_V6_UNKNOWN_U32 ||
        value->initial_health == GE_PLAYER_CAMERA_OWNER_V6_UNKNOWN_U32 ||
        value->initial_ammo == GE_PLAYER_CAMERA_OWNER_V6_UNKNOWN_U32 ||
        value->initial_animation == GE_PLAYER_CAMERA_OWNER_V6_UNKNOWN_U32 ||
        ge_player_camera_q16_is_unknown(value->initial_pitch_q16) ||
        ge_player_camera_vec3_is_unknown(value->camera_offset_q16) ||
        ge_player_camera_vec3_is_unknown(value->head_offset_q16) ||
        value->reserved0 != 0u || value->reserved1 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_player_camera_owner_validate_tile(const GEPlayerCameraStanTileV6 *value)
{
    GEStatusV1 status;
    uint32_t index;
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_player_camera_validate_common(&value->header,
                                              (uint32_t)sizeof(*value),
                                              value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->tile_id == GE_PLAYER_CAMERA_OWNER_V6_UNKNOWN_U32 ||
        value->room_id == GE_PLAYER_CAMERA_OWNER_V6_UNKNOWN_U32 ||
        value->point_count < 3u || value->point_count > 10u ||
        (value->flags & ~GE_PLAYER_CAMERA_OWNER_V6_TILE_FLAG_MASK) != 0u ||
        (value->flags & GE_PLAYER_CAMERA_OWNER_V6_TILE_FLAG_SOURCE_DERIVED) == 0u ||
        (value->flags & GE_PLAYER_CAMERA_OWNER_V6_TILE_FLAG_FLOOR) == 0u ||
        value->source_hash == 0u || value->reserved0 != 0u || value->reserved1 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    for (index = value->point_count; index < 10u; index++) {
        if (value->points_q16[index][0] != 0 || value->points_q16[index][1] != 0 ||
            value->points_q16[index][2] != 0) {
            return GE_STATUS_MALFORMED_STREAM;
        }
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_player_camera_owner_validate_pad(const GEPlayerCameraPadV6 *value)
{
    GEStatusV1 status;
    uint32_t index;
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_player_camera_validate_common(&value->header,
                                              (uint32_t)sizeof(*value),
                                              value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->pad_id == GE_PLAYER_CAMERA_OWNER_V6_UNKNOWN_U32 ||
        value->room_id == GE_PLAYER_CAMERA_OWNER_V6_UNKNOWN_U32 ||
        (value->flags & ~GE_PLAYER_CAMERA_OWNER_V6_PAD_FLAG_MASK) != 0u ||
        (value->flags & GE_PLAYER_CAMERA_OWNER_V6_PAD_FLAG_SOURCE_DERIVED) == 0u ||
        value->source_offset == GE_PLAYER_CAMERA_OWNER_V6_UNKNOWN_U32 ||
        value->reserved0 != 0u || value->reserved1 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    for (index = 0u; index < 3u; index++) {
        if (ge_player_camera_q16_is_unknown(value->position_q16[index]) ||
            ge_player_camera_q16_is_unknown(value->forward_q16[index])) {
            return GE_STATUS_MALFORMED_STREAM;
        }
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_player_camera_owner_validate_snapshot(const GEPlayerCameraSnapshotV6 *value)
{
    GEStatusV1 status;
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_player_camera_validate_common(&value->header,
                                              (uint32_t)sizeof(*value),
                                              value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if ((value->flags & ~GE_PLAYER_CAMERA_OWNER_V6_STATE_MASK) != 0u ||
        value->pair_phase > 1u || value->source_hash == 0u ||
        value->reserved0 != 0u || value->reserved1 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_player_camera_owner_validate_event(const GEPlayerCameraEventV6 *value)
{
    GEStatusV1 status;
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_player_camera_validate_common(&value->header,
                                              (uint32_t)sizeof(*value),
                                              value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->event_type > GE_PLAYER_CAMERA_OWNER_V6_EVENT_MAX ||
        (value->flags & ~GE_PLAYER_CAMERA_OWNER_V6_EVENT_MASK) != 0u ||
        value->source_hash == 0u || value->state_hash == 0u ||
        value->reserved0 != 0u || value->reserved1 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_player_camera_owner_validate_state(const GEPlayerCameraOwnerStateV6 *value)
{
    GEStatusV1 status;
    uint32_t index;
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_player_camera_validate_common(&value->header,
                                              (uint32_t)sizeof(*value),
                                              value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if ((value->flags & ~GE_PLAYER_CAMERA_OWNER_V6_STATE_MASK) != 0u ||
        value->owner_state > GE_PLAYER_CAMERA_OWNER_V6_STATE_ERROR ||
        value->pair_phase > 1u || value->tile_count > GE_PLAYER_CAMERA_OWNER_V6_MAX_STAN_TILES ||
        value->pad_count > GE_PLAYER_CAMERA_OWNER_V6_MAX_PADS ||
        value->source_hash == 0u || value->setup_hash == 0u ||
        value->player_hash == 0u ||
        ge_ramrom_gameplay_v6_validate_setup(&value->setup) != GE_STATUS_OK ||
        value->setup.stage_id != value->stage_id ||
        value->source.stage_id != value->stage_id ||
        ge_player_camera_owner_validate_source(&value->source) != GE_STATUS_OK ||
        ge_player_camera_owner_validate_snapshot(&value->previous_anchor) != GE_STATUS_OK ||
        ge_player_camera_owner_validate_snapshot(&value->current_anchor) != GE_STATUS_OK ||
        ge_player_camera_owner_validate_snapshot(&value->render_snapshot) != GE_STATUS_OK) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    for (index = 0u; index < value->tile_count; index++) {
        if (ge_player_camera_owner_validate_tile(&value->stan[index]) != GE_STATUS_OK) {
            return GE_STATUS_MALFORMED_STREAM;
        }
    }
    for (index = 0u; index < value->pad_count; index++) {
        if (ge_player_camera_owner_validate_pad(&value->pads[index]) != GE_STATUS_OK) {
            return GE_STATUS_MALFORMED_STREAM;
        }
    }
    return GE_STATUS_OK;
}

static int ge_player_camera_point_inside_xz(const GEPlayerCameraStanTileV6 *tile,
                                            double x,
                                            double z)
{
    uint32_t index;
    int all_positive = 1;
    int all_negative = 1;
    for (index = 0u; index < tile->point_count; index++) {
        uint32_t next = (index + 1u) % tile->point_count;
        double ax = ge_player_camera_double_from_q16(tile->points_q16[index][0]);
        double az = ge_player_camera_double_from_q16(tile->points_q16[index][2]);
        double bx = ge_player_camera_double_from_q16(tile->points_q16[next][0]);
        double bz = ge_player_camera_double_from_q16(tile->points_q16[next][2]);
        double cross = ((bx - ax) * (z - az)) - ((bz - az) * (x - ax));
        if (cross < -0.001) {
            all_positive = 0;
        }
        if (cross > 0.001) {
            all_negative = 0;
        }
    }
    return all_positive || all_negative;
}

static double ge_player_camera_segment_distance_squared(double px, double pz,
                                                        double ax, double az,
                                                        double bx, double bz)
{
    double dx = bx - ax;
    double dz = bz - az;
    double length_squared = dx * dx + dz * dz;
    double t;
    double closest_x;
    double closest_z;
    if (length_squared <= 0.000001) {
        closest_x = ax;
        closest_z = az;
    } else {
        t = ((px - ax) * dx + (pz - az) * dz) / length_squared;
        if (t < 0.0) t = 0.0;
        if (t > 1.0) t = 1.0;
        closest_x = ax + t * dx;
        closest_z = az + t * dz;
    }
    dx = px - closest_x;
    dz = pz - closest_z;
    return dx * dx + dz * dz;
}

static int ge_player_camera_point_near_tile(const GEPlayerCameraStanTileV6 *tile,
                                            double x, double z, double radius)
{
    uint32_t index;
    double radius_squared = radius * radius;
    if (ge_player_camera_point_inside_xz(tile, x, z)) {
        return 1;
    }
    for (index = 0u; index < tile->point_count; index++) {
        uint32_t next = (index + 1u) % tile->point_count;
        double ax = ge_player_camera_double_from_q16(tile->points_q16[index][0]);
        double az = ge_player_camera_double_from_q16(tile->points_q16[index][2]);
        double bx = ge_player_camera_double_from_q16(tile->points_q16[next][0]);
        double bz = ge_player_camera_double_from_q16(tile->points_q16[next][2]);
        if (ge_player_camera_segment_distance_squared(x, z, ax, az, bx, bz) <= radius_squared) {
            return 1;
        }
    }
    return 0;
}

static double ge_player_camera_tile_plane_y(const GEPlayerCameraStanTileV6 *tile,
                                             double x,
                                             double z)
{
    double ax = ge_player_camera_double_from_q16(tile->points_q16[0][0]);
    double ay = ge_player_camera_double_from_q16(tile->points_q16[0][1]);
    double az = ge_player_camera_double_from_q16(tile->points_q16[0][2]);
    double ux = ge_player_camera_double_from_q16(tile->points_q16[1][0]) - ax;
    double uy = ge_player_camera_double_from_q16(tile->points_q16[1][1]) - ay;
    double uz = ge_player_camera_double_from_q16(tile->points_q16[1][2]) - az;
    double vx = ge_player_camera_double_from_q16(tile->points_q16[2][0]) - ax;
    double vy = ge_player_camera_double_from_q16(tile->points_q16[2][1]) - ay;
    double vz = ge_player_camera_double_from_q16(tile->points_q16[2][2]) - az;
    double normal_y = (uz * vx) - (ux * vz);
    double normal_x;
    double normal_z;
    if (fabs(normal_y) <= 0.000001) {
        return NAN;
    }
    normal_x = (uy * vz) - (uz * vy);
    normal_z = (ux * vy) - (uy * vx);
    return ay - ((normal_x * (x - ax)) + (normal_z * (z - az))) / normal_y;
}

static uint32_t ge_player_camera_room_for_position(
    const GEPlayerCameraOwnerStateV6 *state,
    const int32_t position_q16[3])
{
    double x = ge_player_camera_double_from_q16(position_q16[0]);
    double y = ge_player_camera_double_from_q16(position_q16[1]);
    double z = ge_player_camera_double_from_q16(position_q16[2]);
    double tolerance = ge_player_camera_double_from_q16(state->source.floor_tolerance_q16);
    double radius = ge_player_camera_double_from_q16(state->source.collision_radius_q16);
    uint32_t selected_room = GE_PLAYER_CAMERA_OWNER_V6_UNKNOWN_U32;
    double selected_y = -HUGE_VAL;
    uint32_t index;
    for (index = 0u; index < state->tile_count; index++) {
        const GEPlayerCameraStanTileV6 *tile = &state->stan[index];
        double floor_y;
        if (!ge_player_camera_point_near_tile(tile, x, z, radius)) {
            continue;
        }
        floor_y = ge_player_camera_tile_plane_y(tile, x, z);
        if (!isfinite(floor_y) || floor_y > y + tolerance || floor_y <= selected_y) {
            continue;
        }
        selected_room = tile->room_id;
        selected_y = floor_y;
    }
    return selected_room;
}

static int ge_player_camera_inside_world(const GERamRomGameplaySetupV6 *setup,
                                         const int32_t position_q16[3])
{
    uint32_t index;
    /* STAN world bounds are floor/model bounds; Bond's collision position is
       eyeheight above that floor and must not be rejected by the Y extent. */
    for (index = 0u; index < 3u; index += 2u) {
        if (position_q16[index] < setup->world_min_q16[index] ||
            position_q16[index] > setup->world_max_q16[index]) {
            return 0;
        }
    }
    return 1;
}

static void ge_player_camera_update_current_pad(GEPlayerCameraOwnerStateV6 *state,
                                                const int32_t position_q16[3])
{
    int64_t radius = state->source.pad_select_radius_q16;
    int64_t radius_squared;
    int64_t best_distance = INT64_MAX;
    uint32_t best_pad = GE_PLAYER_CAMERA_OWNER_V6_UNKNOWN_U32;
    uint32_t index;
    if ((state->source.flags & GE_PLAYER_CAMERA_OWNER_V6_SOURCE_PADS) == 0u ||
        state->pad_count == 0u || radius <= 0) {
        return;
    }
    radius_squared = radius * radius;
    for (index = 0u; index < state->pad_count; index++) {
        const GEPlayerCameraPadV6 *pad = &state->pads[index];
        int64_t dx;
        int64_t dz;
        int64_t distance;
        if (pad->room_id != state->current_room) {
            continue;
        }
        dx = (int64_t)position_q16[0] - (int64_t)pad->position_q16[0];
        dz = (int64_t)position_q16[2] - (int64_t)pad->position_q16[2];
        if (dx > INT32_MAX || dx < INT32_MIN || dz > INT32_MAX || dz < INT32_MIN) {
            continue;
        }
        distance = (dx * dx) + (dz * dz);
        if (distance <= radius_squared && distance < best_distance) {
            best_distance = distance;
            best_pad = pad->pad_id;
        }
    }
    if (best_pad != GE_PLAYER_CAMERA_OWNER_V6_UNKNOWN_U32) {
        state->current_pad = best_pad;
    }
}

static void ge_player_camera_update_basis(GEPlayerCameraSnapshotV6 *snapshot)
{
    double yaw = ge_player_camera_double_from_q16(snapshot->yaw_q16) * GE_PLAYER_CAMERA_PI / 180.0;
    double pitch = ge_player_camera_double_from_q16(snapshot->pitch_q16) * GE_PLAYER_CAMERA_PI / 180.0;
    double horizontal = cos(pitch);
    double forward[3];
    forward[0] = -sin(yaw) * horizontal;
    forward[1] = sin(pitch);
    forward[2] = cos(yaw) * horizontal;
    ge_player_camera_normalize3(forward);
    snapshot->camera_forward_q16[0] = ge_player_camera_q16_from_double(forward[0]);
    snapshot->camera_forward_q16[1] = ge_player_camera_q16_from_double(forward[1]);
    snapshot->camera_forward_q16[2] = ge_player_camera_q16_from_double(forward[2]);
    snapshot->camera_up_q16[0] = 0;
    snapshot->camera_up_q16[1] = (int32_t)GE_PLAYER_CAMERA_Q16_ONE;
    snapshot->camera_up_q16[2] = 0;
}

static void ge_player_camera_event_init(const GEPlayerCameraOwnerStateV6 *state,
                                        uint32_t event_type,
                                        uint32_t event_flags,
                                        uint32_t diagnostic,
                                        GEPlayerCameraEventV6 *event)
{
    memset(event, 0, sizeof(*event));
    ge_player_camera_init_header(&event->header, (uint32_t)sizeof(*event));
    event->record_version = GE_PLAYER_CAMERA_OWNER_V6_RECORD_VERSION;
    event->event_type = event_type;
    event->flags = event_flags;
    event->diagnostic_code = diagnostic;
    event->native_tick = state->native_tick;
    event->reference_tick = state->reference_tick;
    event->pair_phase = state->pair_phase;
    event->demo_id = state->demo_id;
    event->stage_id = state->stage_id;
    event->current_room = state->current_room;
    event->current_pad = state->current_pad;
    event->weapon_action = state->weapon_action;
    event->source_hash = state->source_hash;
    event->state_hash = state->render_snapshot.state_hash;
    event->event_hash = ge_player_camera_owner_hash_event(event);
}

static int32_t ge_player_camera_input_axis(int16_t axis)
{
    int32_t value = (int32_t)axis;
    if (value < -GE_PLAYER_CAMERA_DEADZONE) {
        return value + GE_PLAYER_CAMERA_DEADZONE;
    }
    if (value > GE_PLAYER_CAMERA_DEADZONE) {
        return value - GE_PLAYER_CAMERA_DEADZONE;
    }
    return 0;
}

static int32_t ge_player_camera_axis_speed_q16(int32_t axis)
{
    double normalized = (double)axis / GE_PLAYER_CAMERA_STICK_SCALE;
    double sign = normalized < 0.0 ? -1.0 : 1.0;
    double magnitude = fabs(normalized);
    if (magnitude > 1.0) {
        magnitude = 1.0;
    }
    return ge_player_camera_q16_from_double(sign * magnitude * magnitude);
}

static void ge_player_camera_anchor_copy_interpolated(GEPlayerCameraOwnerStateV6 *state,
                                                       uint64_t native_tick)
{
    GEPlayerCameraSnapshotV6 *out = &state->render_snapshot;
    const GEPlayerCameraSnapshotV6 *a = &state->previous_anchor;
    const GEPlayerCameraSnapshotV6 *b = &state->current_anchor;
    uint32_t index;
    GEPlayerCameraSnapshotV6 temp = *b;
    temp.flags = GE_PLAYER_CAMERA_OWNER_V6_STATE_INTERPOLATED;
    temp.native_tick = native_tick;
    temp.reference_tick = native_tick >> 1;
    temp.pair_phase = 1u;
    for (index = 0u; index < 3u; index++) {
        temp.player_position_q16[index] = ge_player_camera_q16_lerp(
            a->player_position_q16[index], b->player_position_q16[index], 32768);
        temp.player_velocity_q16[index] = ge_player_camera_q16_lerp(
            a->player_velocity_q16[index], b->player_velocity_q16[index], 32768);
        temp.camera_position_q16[index] = ge_player_camera_q16_lerp(
            a->camera_position_q16[index], b->camera_position_q16[index], 32768);
        temp.camera_forward_q16[index] = ge_player_camera_q16_lerp(
            a->camera_forward_q16[index], b->camera_forward_q16[index], 32768);
        temp.camera_up_q16[index] = ge_player_camera_q16_lerp(
            a->camera_up_q16[index], b->camera_up_q16[index], 32768);
    }
    temp.yaw_q16 = ge_player_camera_q16_lerp(a->yaw_q16, b->yaw_q16, 32768);
    temp.pitch_q16 = ge_player_camera_q16_lerp(a->pitch_q16, b->pitch_q16, 32768);
    temp.state_hash = ge_player_camera_hash_snapshot_fields(&temp);
    temp.render_hash = temp.state_hash;
    *out = temp;
}

static void ge_player_camera_update_source_anchor(GEPlayerCameraOwnerStateV6 *state,
                                                   GERamRomGameplayInputV6 input)
{
    GEPlayerCameraSnapshotV6 *snapshot = &state->current_anchor;
    int32_t x_axis = ge_player_camera_input_axis(input.stick_x);
    int32_t y_axis = ge_player_camera_input_axis(input.stick_y);
    int32_t yaw_speed = ge_player_camera_axis_speed_q16(x_axis);
    int32_t pitch_speed = ge_player_camera_axis_speed_q16(y_axis);
    double yaw_delta;
    double pitch_delta;
    int32_t movement_forward;
    double yaw;
    double theta_x;
    double theta_z;
    int32_t next_position[3];
    int32_t base_position[3];
    uint32_t next_room;
    uint32_t index;
    int accepted = 0;

    /* bondviewProcessInput: analog values are squared after the source
       five-unit deadzone, then scaled by FOV/60 and applied at 3.5 degrees
       per source timer. */
    yaw_delta = ge_player_camera_double_from_q16(yaw_speed) *
                (GE_PLAYER_CAMERA_FOV_DEGREES / 60.0) *
                GE_PLAYER_CAMERA_TURN_FACTOR;
    pitch_delta = -ge_player_camera_double_from_q16(pitch_speed) *
                  (GE_PLAYER_CAMERA_FOV_DEGREES / 60.0) *
                  GE_PLAYER_CAMERA_TURN_FACTOR;
    if (state->source.invert_look != 0u) {
        pitch_delta = -pitch_delta;
    }
    snapshot->yaw_q16 = ge_player_camera_angle_normalize(
        ge_player_camera_clamp_i32((int64_t)snapshot->yaw_q16 +
                                    (int64_t)ge_player_camera_q16_from_double(yaw_delta)));
    snapshot->pitch_q16 = ge_player_camera_pitch_clamp(
        ge_player_camera_clamp_i32((int64_t)snapshot->pitch_q16 +
                                   (int64_t)ge_player_camera_q16_from_double(pitch_delta)));

    /* Honey source movement: stick Y controls forward motion; stick X is
       natural turn.  Digital strafing is not synthesized from analog input. */
    movement_forward = ge_player_camera_q16_from_double(
        ge_player_camera_double_from_q16(ge_player_camera_axis_speed_q16(y_axis)) *
        GE_PLAYER_CAMERA_SPEED_FACTOR);
    if (movement_forward > GE_PLAYER_CAMERA_Q16_ONE) {
        movement_forward = GE_PLAYER_CAMERA_Q16_ONE;
    }
    if (movement_forward < -GE_PLAYER_CAMERA_Q16_ONE) {
        movement_forward = -GE_PLAYER_CAMERA_Q16_ONE;
    }
    yaw = ge_player_camera_double_from_q16(snapshot->yaw_q16) * GE_PLAYER_CAMERA_PI / 180.0;
    theta_x = -sin(yaw);
    theta_z = cos(yaw);
    /* MoveBond carries the source head/body animation offset through the
       same theta basis before applying the stick displacement. */
    {
        double head_x = ge_player_camera_double_from_q16(state->source.head_offset_q16[0]);
        double head_z = ge_player_camera_double_from_q16(state->source.head_offset_q16[2]);
        next_position[0] = ge_player_camera_clamp_i32(
            (int64_t)snapshot->player_position_q16[0] +
            (int64_t)llround(((head_z * theta_x) - (head_x * theta_z)) *
                              (double)GE_PLAYER_CAMERA_Q16_ONE));
        next_position[2] = ge_player_camera_clamp_i32(
            (int64_t)snapshot->player_position_q16[2] +
            (int64_t)llround(((head_z * theta_z) + (head_x * theta_x)) *
                              (double)GE_PLAYER_CAMERA_Q16_ONE));
    }
    next_position[0] = ge_player_camera_clamp_i32(
        (int64_t)next_position[0] +
        (int64_t)llround(theta_x * ge_player_camera_double_from_q16(movement_forward) *
                          (double)GE_PLAYER_CAMERA_Q16_ONE));
    next_position[1] = snapshot->player_position_q16[1];
    next_position[2] = ge_player_camera_clamp_i32(
        (int64_t)next_position[2] +
        (int64_t)llround(theta_z * ge_player_camera_double_from_q16(movement_forward) *
                          (double)GE_PLAYER_CAMERA_Q16_ONE));
    base_position[0] = snapshot->player_position_q16[0];
    base_position[1] = snapshot->player_position_q16[1];
    base_position[2] = snapshot->player_position_q16[2];

    /* The original collision owner first tests the candidate against STAN
       and only then updates Bond's current tile/position.  Keep the same
       fail-closed ordering; there is no broad host/world clamp here. */
    next_room = ge_player_camera_room_for_position(state, next_position);
    if (next_room != GE_PLAYER_CAMERA_OWNER_V6_UNKNOWN_U32 &&
        ge_player_camera_inside_world(&state->setup, next_position)) {
        accepted = 1;
    } else {
        /* bondviewCalcUpdatePlayerCollision first tries the complete offset,
           then permits a bounded edge/scoot component when a STAN edge blocks
           the diagonal candidate. This keeps source movement responsive
           without inventing a world clamp or bypassing STAN. */
        next_position[0] = base_position[0];
        next_position[2] = base_position[2];
        next_room = ge_player_camera_room_for_position(state, next_position);
        if (next_room != GE_PLAYER_CAMERA_OWNER_V6_UNKNOWN_U32) {
            next_position[0] = ge_player_camera_clamp_i32(
                (int64_t)base_position[0] +
                (int64_t)llround(theta_x * ge_player_camera_double_from_q16(movement_forward) *
                                  (double)GE_PLAYER_CAMERA_Q16_ONE));
            next_room = ge_player_camera_room_for_position(state, next_position);
            accepted = next_room != GE_PLAYER_CAMERA_OWNER_V6_UNKNOWN_U32 &&
                       ge_player_camera_inside_world(&state->setup, next_position);
        }
        if (!accepted) {
            next_position[0] = base_position[0];
            next_position[2] = ge_player_camera_clamp_i32(
                (int64_t)base_position[2] +
                (int64_t)llround(theta_z * ge_player_camera_double_from_q16(movement_forward) *
                                  (double)GE_PLAYER_CAMERA_Q16_ONE));
            next_room = ge_player_camera_room_for_position(state, next_position);
            accepted = next_room != GE_PLAYER_CAMERA_OWNER_V6_UNKNOWN_U32 &&
                       ge_player_camera_inside_world(&state->setup, next_position);
        }
    }
    if (accepted) {
        for (index = 0u; index < 3u; index++) {
            snapshot->player_velocity_q16[index] = next_position[index] -
                snapshot->player_position_q16[index];
            snapshot->player_position_q16[index] = next_position[index];
        }
        state->current_room = next_room;
        ge_player_camera_update_current_pad(state, snapshot->player_position_q16);
    } else {
        snapshot->player_velocity_q16[0] = 0;
        snapshot->player_velocity_q16[1] = 0;
        snapshot->player_velocity_q16[2] = 0;
    }

    snapshot->current_room = state->current_room;
    snapshot->current_pad = state->current_pad;
    snapshot->weapon_action = state->weapon_action;
    snapshot->source_anchor = state->source_anchor;
    snapshot->native_tick = state->native_tick;
    snapshot->reference_tick = state->reference_tick;
    snapshot->pair_phase = state->pair_phase;
    snapshot->flags = GE_PLAYER_CAMERA_OWNER_V6_STATE_SOURCE_ANCHOR;
    snapshot->camera_position_q16[0] = snapshot->player_position_q16[0] +
        state->source.camera_offset_q16[0];
    snapshot->camera_position_q16[1] = snapshot->player_position_q16[1] +
        state->source.camera_offset_q16[1];
    snapshot->camera_position_q16[2] = snapshot->player_position_q16[2] +
        state->source.camera_offset_q16[2];
    ge_player_camera_update_basis(snapshot);
    snapshot->state_hash = ge_player_camera_hash_snapshot_fields(snapshot);
    snapshot->render_hash = snapshot->state_hash;
}

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
    GEPlayerCameraEventV6 *out_event)
{
    GEStatusV1 status;
    uint32_t index;
    GEPlayerCameraSnapshotV6 initial;
    int32_t yaw_q16;
    int32_t pitch_q16;
    double fx;
    double fy;
    double fz;
    double horizontal;
    if (setup == NULL || entities == NULL || source == NULL || out_state == NULL ||
        out_event == NULL || entity_count == 0u || stan == NULL || stan_count == 0u ||
        stan_count > GE_PLAYER_CAMERA_OWNER_V6_MAX_STAN_TILES ||
        pad_count > GE_PLAYER_CAMERA_OWNER_V6_MAX_PADS ||
        (pad_count != 0u && pads == NULL)) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (demo_id == 0u || demo_id > GE_RAMROM_V5_DEMO_COUNT ||
        entity_count > GE_RAMROM_GAMEPLAY_V6_MAX_ENTITIES) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    status = ge_ramrom_gameplay_v6_validate_setup(setup);
    if (status != GE_STATUS_OK) {
        return status;
    }
    status = ge_player_camera_owner_validate_source(source);
    if (status != GE_STATUS_OK || source->stage_id != setup->stage_id ||
        (source->demo_mask & (UINT32_C(1) << (demo_id - 1u))) == 0u ||
        (setup->demo_mask & (UINT32_C(1) << (demo_id - 1u))) == 0u) {
        return status == GE_STATUS_OK ? GE_STATUS_ASSET_MISMATCH : status;
    }
    for (index = 0u; index < entity_count; index++) {
        status = ge_ramrom_gameplay_v6_validate_entity(&entities[index]);
        if (status != GE_STATUS_OK) {
            return status;
        }
    }
    if (entities[0].entity_kind != GE_RAMROM_GAMEPLAY_V6_ENTITY_PLAYER ||
        (entities[0].flags & GE_RAMROM_GAMEPLAY_V6_ENTITY_ACTIVE) == 0u ||
        memcmp(entities[0].position_q16, setup->initial_position_q16,
               sizeof(setup->initial_position_q16)) != 0 ||
        setup->initial_room == GE_PLAYER_CAMERA_OWNER_V6_UNKNOWN_U32 ||
        setup->initial_pad == GE_PLAYER_CAMERA_OWNER_V6_UNKNOWN_U32 ||
        ge_player_camera_vec3_is_unknown(setup->initial_position_q16) ||
        ge_player_camera_vec3_is_unknown(setup->initial_forward_q16) ||
        ge_player_camera_vec3_is_unknown(setup->world_min_q16) ||
        ge_player_camera_vec3_is_unknown(setup->world_max_q16)) {
        return GE_STATUS_UNSUPPORTED_COMMAND;
    }
    if (source->initial_weapon != entities[0].weapon_model_handle ||
        source->initial_health != entities[0].health ||
        source->initial_animation != entities[0].animation_id) {
        return GE_STATUS_ASSET_MISMATCH;
    }
    for (index = 0u; index < stan_count; index++) {
        status = ge_player_camera_owner_validate_tile(&stan[index]);
        if (status != GE_STATUS_OK || stan[index].room_id > setup->room_count + 1u) {
            return status == GE_STATUS_OK ? GE_STATUS_MALFORMED_STREAM : status;
        }
    }
    for (index = 0u; index < pad_count; index++) {
        status = ge_player_camera_owner_validate_pad(&pads[index]);
        if (status != GE_STATUS_OK) {
            return status;
        }
    }
    if ((pad_count != 0u) !=
        ((source->flags & GE_PLAYER_CAMERA_OWNER_V6_SOURCE_PADS) != 0u)) {
        return GE_STATUS_ASSET_MISMATCH;
    }
    if (pad_count != 0u) {
        int found_initial_pad = 0;
        for (index = 0u; index < pad_count; index++) {
            if (pads[index].pad_id == setup->initial_pad &&
                pads[index].room_id == setup->initial_room) {
                found_initial_pad = 1;
                break;
            }
        }
        if (!found_initial_pad) {
            return GE_STATUS_ASSET_MISMATCH;
        }
    }

    fx = ge_player_camera_double_from_q16(setup->initial_forward_q16[0]);
    fy = ge_player_camera_double_from_q16(setup->initial_forward_q16[1]);
    fz = ge_player_camera_double_from_q16(setup->initial_forward_q16[2]);
    horizontal = hypot(fx, fz);
    if (hypot(horizontal, fy) <= 0.0) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    yaw_q16 = ge_player_camera_q16_from_double(atan2(-fx, fz) * 180.0 / GE_PLAYER_CAMERA_PI);
    yaw_q16 = ge_player_camera_angle_normalize(yaw_q16);
    (void)fy;
    (void)horizontal;
    pitch_q16 = source->initial_pitch_q16;

    memset(out_state, 0, sizeof(*out_state));
    ge_player_camera_init_header(&out_state->header, (uint32_t)sizeof(*out_state));
    out_state->record_version = GE_PLAYER_CAMERA_OWNER_V6_RECORD_VERSION;
    out_state->flags = GE_PLAYER_CAMERA_OWNER_V6_STATE_ACTIVE;
    out_state->owner_state = GE_PLAYER_CAMERA_OWNER_V6_STATE_RUNNING;
    out_state->demo_id = demo_id;
    out_state->stage_id = setup->stage_id;
    out_state->native_tick = UINT64_MAX;
    out_state->reference_tick = UINT64_MAX;
    out_state->pair_phase = 0u;
    out_state->current_room = setup->initial_room;
    out_state->current_pad = setup->initial_pad;
    out_state->tile_count = stan_count;
    out_state->pad_count = pad_count;
    out_state->source_hash = source->source_hash;
    out_state->setup_hash = source->setup_hash;
    out_state->player_hash = source->player_hash;
    out_state->setup = *setup;
    out_state->source = *source;
    /* A value-only copy of setup is needed for exact source world-bound and
       room checks; this field is local to the owner state below. */
    memcpy(&out_state->previous_anchor, &out_state->current_anchor, sizeof(initial));
    for (index = 0u; index < stan_count; index++) {
        out_state->stan[index] = stan[index];
    }
    for (index = 0u; index < pad_count; index++) {
        out_state->pads[index] = pads[index];
    }
    if (ge_player_camera_room_for_position(out_state, setup->initial_position_q16) !=
        setup->initial_room) {
        memset(out_state, 0, sizeof(*out_state));
        return GE_STATUS_ASSET_MISMATCH;
    }
    initial = (GEPlayerCameraSnapshotV6){0};
    ge_player_camera_init_header(&initial.header, (uint32_t)sizeof(initial));
    initial.record_version = GE_PLAYER_CAMERA_OWNER_V6_RECORD_VERSION;
    initial.flags = GE_PLAYER_CAMERA_OWNER_V6_STATE_SOURCE_ANCHOR;
    initial.demo_id = demo_id;
    initial.stage_id = setup->stage_id;
    initial.native_tick = 0u;
    initial.reference_tick = 0u;
    initial.pair_phase = 0u;
    initial.source_anchor = 0u;
    initial.current_room = setup->initial_room;
    initial.current_pad = setup->initial_pad;
    initial.weapon_model_handle = source->initial_weapon;
    initial.player_health = source->initial_health;
    initial.hud_ammo = source->initial_ammo;
    initial.player_animation = source->initial_animation;
    memcpy(initial.player_position_q16, setup->initial_position_q16,
           sizeof(initial.player_position_q16));
    initial.player_velocity_q16[0] = 0;
    initial.player_velocity_q16[1] = 0;
    initial.player_velocity_q16[2] = 0;
    initial.yaw_q16 = yaw_q16;
    initial.pitch_q16 = ge_player_camera_pitch_clamp(pitch_q16);
    initial.camera_position_q16[0] = initial.player_position_q16[0] + source->camera_offset_q16[0];
    initial.camera_position_q16[1] = initial.player_position_q16[1] + source->camera_offset_q16[1];
    initial.camera_position_q16[2] = initial.player_position_q16[2] + source->camera_offset_q16[2];
    initial.source_hash = source->source_hash;
    ge_player_camera_update_basis(&initial);
    initial.state_hash = ge_player_camera_hash_snapshot_fields(&initial);
    initial.render_hash = initial.state_hash;
    out_state->previous_anchor = initial;
    out_state->current_anchor = initial;
    out_state->render_snapshot = initial;
    out_state->state_hash = initial.state_hash;
    ge_player_camera_event_init(out_state, GE_PLAYER_CAMERA_OWNER_V6_EVENT_INSTALL,
                                GE_PLAYER_CAMERA_OWNER_V6_EVENT_SOURCE_ANCHOR_FLAG,
                                0u, out_event);
    out_event->state_hash = initial.state_hash;
    out_event->event_hash = ge_player_camera_owner_hash_event(out_event);
    return GE_STATUS_OK;
}

GEStatusV1 ge_player_camera_owner_step(
    uint64_t native_tick,
    GERamRomGameplayInputV6 input,
    GEPlayerCameraOwnerStateV6 *inout_state,
    GEPlayerCameraEventV6 *out_event)
{
    GEStatusV1 status;
    uint64_t expected_tick;
    if (inout_state == NULL || out_event == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_player_camera_owner_validate_state(inout_state);
    if (status != GE_STATUS_OK) {
        return status;
    }
    status = ge_ramrom_gameplay_v6_validate_input(&input);
    if (status != GE_STATUS_OK) {
        return status;
    }
    expected_tick = inout_state->native_tick == UINT64_MAX ? 0u : inout_state->native_tick + 1u;
    if (native_tick != expected_tick) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    inout_state->native_tick = native_tick;
    inout_state->reference_tick = native_tick >> 1;
    inout_state->pair_phase = (uint32_t)(native_tick & 1u);

    if ((input.flags & GE_RAMROM_GAMEPLAY_V6_INPUT_REAL) != 0u &&
        (input.pressed_buttons != 0u || input.held_buttons != 0u ||
         input.released_buttons != 0u)) {
        inout_state->flags |= GE_PLAYER_CAMERA_OWNER_V6_STATE_REAL_ABORT;
        inout_state->owner_state = GE_PLAYER_CAMERA_OWNER_V6_STATE_ABORTING;
        inout_state->flags &= ~GE_PLAYER_CAMERA_OWNER_V6_STATE_ACTIVE;
        ge_player_camera_event_init(inout_state,
                                    GE_PLAYER_CAMERA_OWNER_V6_EVENT_ABORT,
                                    GE_PLAYER_CAMERA_OWNER_V6_EVENT_REAL_ABORT_FLAG,
                                    input.pressed_buttons | input.held_buttons |
                                        input.released_buttons,
                                    out_event);
        return GE_STATUS_OK;
    }

    if ((input.flags & GE_RAMROM_GAMEPLAY_V6_INPUT_FOCUSED) == 0u) {
        input.stick_x = 0;
        input.stick_y = 0;
        input.pressed_buttons = 0u;
        input.held_buttons = 0u;
        input.released_buttons = 0u;
    }

    if (inout_state->pair_phase == 0u) {
        inout_state->flags &= ~GE_PLAYER_CAMERA_OWNER_V6_STATE_INTERPOLATED;
        inout_state->flags |= GE_PLAYER_CAMERA_OWNER_V6_STATE_SOURCE_ANCHOR;
        inout_state->previous_anchor = inout_state->current_anchor;
        inout_state->source_anchor++;
        inout_state->weapon_action = 0u;
        if ((input.pressed_buttons & GE_PLAYER_CAMERA_OWNER_V6_BUTTON_Z) != 0u ||
            (input.held_buttons & GE_PLAYER_CAMERA_OWNER_V6_BUTTON_Z) != 0u) {
            inout_state->weapon_action = 1u;
            inout_state->weapon_sequence++;
            inout_state->flags |= GE_PLAYER_CAMERA_OWNER_V6_STATE_WEAPON_ACTION;
        }
        ge_player_camera_update_source_anchor(inout_state, input);
        inout_state->current_anchor.flags = GE_PLAYER_CAMERA_OWNER_V6_STATE_SOURCE_ANCHOR |
                                             (inout_state->weapon_action != 0u ?
                                              GE_PLAYER_CAMERA_OWNER_V6_STATE_WEAPON_ACTION : 0u);
        inout_state->state_hash = inout_state->current_anchor.state_hash;
        inout_state->render_snapshot = inout_state->current_anchor;
        ge_player_camera_event_init(inout_state,
                                    inout_state->weapon_action != 0u ?
                                        GE_PLAYER_CAMERA_OWNER_V6_EVENT_WEAPON :
                                        GE_PLAYER_CAMERA_OWNER_V6_EVENT_SOURCE_ANCHOR,
                                    GE_PLAYER_CAMERA_OWNER_V6_EVENT_SOURCE_ANCHOR_FLAG |
                                        (inout_state->weapon_action != 0u ?
                                         GE_PLAYER_CAMERA_OWNER_V6_EVENT_WEAPON_FLAG : 0u),
                                    0u, out_event);
        out_event->detail0 = inout_state->current_room;
        out_event->detail1 = inout_state->current_pad;
    } else {
        ge_player_camera_anchor_copy_interpolated(inout_state, native_tick);
        inout_state->flags &= ~GE_PLAYER_CAMERA_OWNER_V6_STATE_SOURCE_ANCHOR;
        inout_state->flags |= GE_PLAYER_CAMERA_OWNER_V6_STATE_INTERPOLATED;
        inout_state->state_hash = inout_state->render_snapshot.state_hash;
        ge_player_camera_event_init(inout_state,
                                    GE_PLAYER_CAMERA_OWNER_V6_EVENT_INTERPOLANT,
                                    GE_PLAYER_CAMERA_OWNER_V6_EVENT_INTERPOLATED_FLAG,
                                    0u, out_event);
    }
    out_event->state_hash = inout_state->render_snapshot.state_hash;
    out_event->event_hash = ge_player_camera_owner_hash_event(out_event);
    return GE_STATUS_OK;
}

GEStatusV1 ge_player_camera_owner_copy_snapshot(
    const GEPlayerCameraOwnerStateV6 *state,
    GEPlayerCameraSnapshotV6 *out_snapshot)
{
    GEStatusV1 status;
    if (state == NULL || out_snapshot == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_player_camera_owner_validate_state(state);
    if (status != GE_STATUS_OK) {
        return status;
    }
    *out_snapshot = state->render_snapshot;
    return GE_STATUS_OK;
}

GEStatusV1 ge_player_camera_owner_restore(
    GEPlayerCameraOwnerStateV6 *inout_state,
    const GEPlayerCameraSnapshotV6 *snapshot)
{
    GEStatusV1 status;
    if (inout_state == NULL || snapshot == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_player_camera_owner_validate_state(inout_state);
    if (status != GE_STATUS_OK) {
        return status;
    }
    status = ge_player_camera_owner_validate_snapshot(snapshot);
    if (status != GE_STATUS_OK || snapshot->demo_id != inout_state->demo_id ||
        snapshot->stage_id != inout_state->stage_id ||
        snapshot->source_hash != inout_state->source_hash) {
        return status == GE_STATUS_OK ? GE_STATUS_ASSET_MISMATCH : status;
    }
    inout_state->native_tick = snapshot->native_tick;
    inout_state->reference_tick = snapshot->reference_tick;
    inout_state->pair_phase = snapshot->pair_phase;
    inout_state->source_anchor = snapshot->source_anchor;
    inout_state->current_room = snapshot->current_room;
    inout_state->current_pad = snapshot->current_pad;
    inout_state->weapon_action = snapshot->weapon_action;
    inout_state->previous_anchor = *snapshot;
    inout_state->current_anchor = *snapshot;
    inout_state->render_snapshot = *snapshot;
    inout_state->state_hash = snapshot->state_hash;
    inout_state->owner_state = GE_PLAYER_CAMERA_OWNER_V6_STATE_RUNNING;
    inout_state->flags = GE_PLAYER_CAMERA_OWNER_V6_STATE_ACTIVE |
                         (snapshot->pair_phase == 0u ?
                          GE_PLAYER_CAMERA_OWNER_V6_STATE_SOURCE_ANCHOR :
                          GE_PLAYER_CAMERA_OWNER_V6_STATE_INTERPOLATED);
    return GE_STATUS_OK;
}
