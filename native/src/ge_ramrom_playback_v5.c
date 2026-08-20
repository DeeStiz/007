#include "ge_ramrom_playback_v5.h"

#include <string.h>

static const uint64_t GE_RAMROM_PLAYBACK_V5_FNV_OFFSET =
    UINT64_C(1469598103934665603);
static const uint64_t GE_RAMROM_PLAYBACK_V5_FNV_PRIME =
    UINT64_C(1099511628211);

static uint64_t ge_playback_hash_byte(uint64_t hash, uint8_t value)
{
    hash ^= (uint64_t)value;
    return hash * GE_RAMROM_PLAYBACK_V5_FNV_PRIME;
}

static uint64_t ge_playback_hash_u32(uint64_t hash, uint32_t value)
{
    for (uint32_t shift = 0u; shift < 32u; shift += 8u) {
        hash = ge_playback_hash_byte(hash, (uint8_t)(value >> shift));
    }
    return hash;
}

static uint64_t ge_playback_hash_u64(uint64_t hash, uint64_t value)
{
    for (uint32_t shift = 0u; shift < 64u; shift += 8u) {
        hash = ge_playback_hash_byte(hash, (uint8_t)(value >> shift));
    }
    return hash;
}

static GEStatusV1 ge_playback_validate_common(const GEAbiHeaderV1 *header,
                                              uint32_t expected_size,
                                              uint32_t record_version)
{
    if (header == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (header->abi_version != GE_NATIVE_ABI_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    if (header->struct_size != expected_size) {
        return GE_STATUS_INVALID_SIZE;
    }
    if (record_version != GE_RAMROM_PLAYBACK_V5_RECORD_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    return GE_STATUS_OK;
}

static uint64_t ge_playback_hash_registers(const GERamRomHeaderV5 *header)
{
    uint64_t hash = GE_RAMROM_PLAYBACK_V5_FNV_OFFSET;
    hash = ge_playback_hash_u64(hash, header->random_seed);
    hash = ge_playback_hash_u64(hash, header->randomizer_seed);
    hash = ge_playback_hash_u32(hash, header->stage_id);
    hash = ge_playback_hash_u32(hash, header->difficulty);
    hash = ge_playback_hash_u32(hash, header->controller_count);
    hash = ge_playback_hash_u32(hash, header->total_time_ms);
    hash = ge_playback_hash_u32(hash, header->mode);
    hash = ge_playback_hash_u32(hash, header->slot_number);
    hash = ge_playback_hash_u32(hash, header->player_count);
    hash = ge_playback_hash_u32(hash, header->scenario);
    hash = ge_playback_hash_u32(hash, header->multiplayer_stage);
    hash = ge_playback_hash_u32(hash, header->game_length);
    hash = ge_playback_hash_u32(hash, header->weapon_set);
    hash = ge_playback_hash_u32(hash, header->aim_option);
    for (uint32_t index = 0u; index < 4u; index++) {
        hash = ge_playback_hash_u32(hash, header->character_ids[index]);
        hash = ge_playback_hash_u32(hash, header->handicaps[index]);
        hash = ge_playback_hash_u32(hash, header->controller_styles[index]);
        hash = ge_playback_hash_u32(hash, header->player_flags[index]);
    }
    return hash;
}

GEStatusV1 ge_ramrom_playback_v5_validate_install(
    const GERamRomPlaybackInstallV5 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_playback_validate_common(
        &value->header,
        (uint32_t)sizeof(*value),
        value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    status = ge_ramrom_v5_validate_header(&value->source_header);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if ((value->flags & ~GE_RAMROM_PLAYBACK_INSTALL_FLAG_MASK) != 0u ||
        (value->flags & (GE_RAMROM_PLAYBACK_INSTALL_SAVE |
                         GE_RAMROM_PLAYBACK_INSTALL_RNG |
                         GE_RAMROM_PLAYBACK_INSTALL_REGISTERS)) !=
            (GE_RAMROM_PLAYBACK_INSTALL_SAVE |
             GE_RAMROM_PLAYBACK_INSTALL_RNG |
             GE_RAMROM_PLAYBACK_INSTALL_REGISTERS) ||
        value->save_byte_count != GE_RAMROM_V5_SAVE_BYTES ||
        value->save_hash != value->source_header.save_hash ||
        value->register_hash == 0u ||
        value->save_hash == 0u ||
        value->reserved0 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    if (ge_ramrom_v5_hash_bytes(value->save_data,
                                GE_RAMROM_V5_SAVE_BYTES) != value->save_hash) {
        return GE_STATUS_ASSET_MISMATCH;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_playback_v5_validate_input(
    const GERamRomPlaybackInputV5 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_playback_validate_common(
        &value->header,
        (uint32_t)sizeof(*value),
        value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if ((value->flags & ~GE_RAMROM_PLAYBACK_INPUT_FLAG_MASK) != 0u ||
        value->controller_count > GE_RAMROM_V5_MAX_CONTROLLERS ||
        value->reserved0 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_playback_v5_validate_event(
    const GERamRomPlaybackEventV5 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_playback_validate_common(
        &value->header,
        (uint32_t)sizeof(*value),
        value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->event_type > GE_RAMROM_PLAYBACK_EVENT_MAX ||
        (value->flags & ~GE_RAMROM_PLAYBACK_EVENT_FLAG_MASK) != 0u ||
        value->pair_phase > 1u ||
        value->controller_count > GE_RAMROM_V5_MAX_CONTROLLERS ||
        value->sample_count > value->controller_count ||
        value->reserved0 != 0u ||
        value->reserved1 != 0u ||
        value->recording_hash == 0u ||
        value->rng_hash == 0u ||
        value->state_hash == 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    if (value->event_type == GE_RAMROM_PLAYBACK_EVENT_SAMPLE &&
        value->sample_hash == 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_playback_v5_validate_state(
    const GERamRomPlaybackStateV5 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_playback_validate_common(
        &value->header,
        (uint32_t)sizeof(*value),
        value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if ((value->flags & ~GE_RAMROM_PLAYBACK_STATE_FLAG_MASK) != 0u ||
        value->replay_state > GE_RAMROM_STATE_MAX ||
        value->pair_phase > 1u ||
        value->packet_count > GE_RAMROM_V5_MAX_PACKETS ||
        value->packet_index > value->packet_count ||
        value->controller_count == 0u ||
        value->controller_count > GE_RAMROM_V5_MAX_CONTROLLERS ||
        value->reserved0 != 0u ||
        value->reserved1 != 0u ||
        value->recording_hash == 0u ||
        value->packet_hash == 0u ||
        value->input_hash == 0u ||
        value->rng_hash == 0u ||
        value->playback_hash == 0u ||
        ge_ramrom_playback_v5_validate_install(&value->install) !=
            GE_STATUS_OK) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

uint64_t ge_ramrom_playback_v5_hash_event(
    const GERamRomPlaybackEventV5 *value)
{
    if (value == NULL) {
        return 0u;
    }
    uint64_t hash = GE_RAMROM_PLAYBACK_V5_FNV_OFFSET;
    hash = ge_playback_hash_u32(hash, value->event_type);
    hash = ge_playback_hash_u32(hash, value->flags);
    hash = ge_playback_hash_u32(hash, value->diagnostic_code);
    hash = ge_playback_hash_u64(hash, value->native_tick);
    hash = ge_playback_hash_u64(hash, value->reference_tick);
    hash = ge_playback_hash_u32(hash, value->pair_phase);
    hash = ge_playback_hash_u32(hash, value->demo_id);
    hash = ge_playback_hash_u32(hash, value->stage_id);
    hash = ge_playback_hash_u32(hash, value->packet_index);
    hash = ge_playback_hash_u32(hash, value->packet_count);
    hash = ge_playback_hash_u32(hash, value->frame_index);
    hash = ge_playback_hash_u32(hash, value->record_count);
    hash = ge_playback_hash_u32(hash, value->controller_count);
    hash = ge_playback_hash_u32(hash, value->speedframes);
    hash = ge_playback_hash_u32(hash, value->rng_seed);
    hash = ge_playback_hash_u32(hash, value->sample_count);
    hash = ge_playback_hash_u32(hash, value->source_anchor);
    hash = ge_playback_hash_u32(hash, value->source_frame);
    hash = ge_playback_hash_u32(hash, value->abort_buttons);
    hash = ge_playback_hash_u64(hash, value->sample_hash);
    hash = ge_playback_hash_u64(hash, value->recording_hash);
    hash = ge_playback_hash_u64(hash, value->rng_hash);
    for (uint32_t index = 0u; index < GE_RAMROM_V5_MAX_CONTROLLERS; index++) {
        hash = ge_playback_hash_byte(hash, (uint8_t)value->stick_x[index]);
        hash = ge_playback_hash_byte(hash, (uint8_t)value->stick_y[index]);
        hash = ge_playback_hash_byte(hash, value->button_low[index]);
        hash = ge_playback_hash_byte(hash, value->button_high[index]);
        hash = ge_playback_hash_u32(hash, value->buttons[index]);
    }
    return hash;
}

uint64_t ge_ramrom_playback_v5_hash_state(
    const GERamRomPlaybackStateV5 *value)
{
    if (value == NULL) {
        return 0u;
    }
    uint64_t hash = GE_RAMROM_PLAYBACK_V5_FNV_OFFSET;
    hash = ge_playback_hash_u32(hash, value->flags);
    hash = ge_playback_hash_u32(hash, value->replay_state);
    hash = ge_playback_hash_u32(hash, value->error_code);
    hash = ge_playback_hash_u32(hash, value->demo_id);
    hash = ge_playback_hash_u32(hash, value->stage_id);
    hash = ge_playback_hash_u64(hash, value->native_tick);
    hash = ge_playback_hash_u64(hash, value->reference_tick);
    hash = ge_playback_hash_u32(hash, value->pair_phase);
    hash = ge_playback_hash_u32(hash, value->packet_index);
    hash = ge_playback_hash_u32(hash, value->packet_count);
    hash = ge_playback_hash_u32(hash, value->frame_index);
    hash = ge_playback_hash_u32(hash, value->record_count);
    hash = ge_playback_hash_u32(hash, value->sample_index);
    hash = ge_playback_hash_u32(hash, value->source_anchor);
    hash = ge_playback_hash_u32(hash, value->source_frame);
    hash = ge_playback_hash_u32(hash, value->speedframes);
    hash = ge_playback_hash_u32(hash, value->rng_index);
    hash = ge_playback_hash_u32(hash, value->controller_count);
    hash = ge_playback_hash_u32(hash, value->abort_buttons);
    hash = ge_playback_hash_u32(hash, value->total_samples);
    hash = ge_playback_hash_u64(hash, value->recording_hash);
    hash = ge_playback_hash_u64(hash, value->packet_hash);
    hash = ge_playback_hash_u64(hash, value->input_hash);
    hash = ge_playback_hash_u64(hash, value->rng_hash);
    hash = ge_playback_hash_u64(hash, value->install.register_hash);
    hash = ge_playback_hash_u64(hash, value->install.save_hash);
    return hash;
}

static void ge_playback_init_event(const GERamRomPlaybackStateV5 *state,
                                   uint32_t event_type,
                                   uint32_t flags,
                                   uint32_t diagnostic_code,
                                   GERamRomPlaybackEventV5 *event)
{
    memset(event, 0, sizeof(*event));
    event->header.abi_version = GE_NATIVE_ABI_VERSION;
    event->header.struct_size = (uint32_t)sizeof(*event);
    event->record_version = GE_RAMROM_PLAYBACK_V5_RECORD_VERSION;
    event->event_type = event_type;
    event->flags = flags;
    event->diagnostic_code = diagnostic_code;
    event->native_tick = state->native_tick == UINT64_MAX ? 0u :
                         state->native_tick;
    event->reference_tick = state->reference_tick;
    event->pair_phase = state->pair_phase;
    event->demo_id = state->demo_id;
    event->stage_id = state->stage_id;
    event->packet_index = state->packet_index;
    event->packet_count = state->packet_count;
    event->frame_index = state->frame_index;
    event->controller_count = state->controller_count;
    event->source_anchor = state->source_anchor;
    event->source_frame = state->source_frame;
    event->recording_hash = state->recording_hash;
    event->rng_hash = state->rng_hash;
    event->state_hash = ge_ramrom_playback_v5_hash_state(state);
}

static void ge_playback_finalize_event(const GERamRomPlaybackStateV5 *state,
                                       GERamRomPlaybackEventV5 *event)
{
    event->state_hash = ge_ramrom_playback_v5_hash_state(state);
    (void)ge_ramrom_playback_v5_hash_event(event);
}

static GEStatusV1 ge_playback_catalog_guard(const uint8_t *bytes,
                                            uint32_t byte_count,
                                            uint32_t demo_id,
                                            const GERamRomHeaderV5 *header,
                                            const GERamRomParseSummaryV5 *summary)
{
    if (demo_id == 0u || demo_id > GE_RAMROM_V5_DEMO_COUNT) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GERamRomCatalogEntryV5 catalog;
    GEStatusV1 status = ge_ramrom_v5_catalog_entry(demo_id - 1u, &catalog);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (byte_count != catalog.asset_file_bytes ||
        header->stage_id != catalog.stage_id ||
        header->controller_count != catalog.controller_count ||
        header->declared_file_bytes != catalog.declared_file_bytes ||
        summary->recording_hash != catalog.recording_hash ||
        ge_ramrom_v5_hash_bytes(bytes, header->declared_file_bytes) !=
            catalog.recording_hash) {
        return GE_STATUS_ASSET_MISMATCH;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_playback_v5_begin(
    const uint8_t *bytes,
    uint32_t byte_count,
    uint32_t demo_id,
    GERamRomPlaybackStateV5 *out_state,
    GERamRomPlaybackEventV5 *out_event)
{
    if (bytes == NULL || out_state == NULL || out_event == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GERamRomHeaderV5 header;
    GEStatusV1 status = ge_ramrom_v5_read_header(bytes, byte_count, &header);
    if (status != GE_STATUS_OK) {
        return status;
    }
    GERamRomParseSummaryV5 summary;
    status = ge_ramrom_v5_parse(bytes, byte_count, &summary);
    if (status != GE_STATUS_OK) {
        return status;
    }
    status = ge_playback_catalog_guard(bytes,
                                       byte_count,
                                       demo_id,
                                       &header,
                                       &summary);
    if (status != GE_STATUS_OK) {
        return status;
    }

    memset(out_state, 0, sizeof(*out_state));
    out_state->header.abi_version = GE_NATIVE_ABI_VERSION;
    out_state->header.struct_size = (uint32_t)sizeof(*out_state);
    out_state->record_version = GE_RAMROM_PLAYBACK_V5_RECORD_VERSION;
    out_state->flags = GE_RAMROM_PLAYBACK_STATE_ACTIVE |
                       GE_RAMROM_PLAYBACK_STATE_INITIALIZED |
                       GE_RAMROM_PLAYBACK_STATE_STAGE_UNSUPPORTED |
                       GE_RAMROM_PLAYBACK_STATE_INSTALL_READY;
    out_state->replay_state = GE_RAMROM_STATE_PLAYING;
    out_state->demo_id = demo_id;
    out_state->stage_id = header.stage_id;
    out_state->native_tick = UINT64_MAX;
    out_state->reference_tick = 0u;
    out_state->pair_phase = 0u;
    out_state->packet_count = summary.packet_count;
    out_state->record_count = summary.record_count;
    out_state->total_samples = summary.record_count * header.controller_count;
    out_state->controller_count = header.controller_count;
    out_state->recording_hash = summary.recording_hash;
    out_state->packet_hash = summary.packet_hash;
    out_state->input_hash = summary.input_hash;
    out_state->rng_hash = summary.rng_hash;

    GERamRomPlaybackInstallV5 *install = &out_state->install;
    memset(install, 0, sizeof(*install));
    install->header.abi_version = GE_NATIVE_ABI_VERSION;
    install->header.struct_size = (uint32_t)sizeof(*install);
    install->record_version = GE_RAMROM_PLAYBACK_V5_RECORD_VERSION;
    install->flags = GE_RAMROM_PLAYBACK_INSTALL_SAVE |
                     GE_RAMROM_PLAYBACK_INSTALL_RNG |
                     GE_RAMROM_PLAYBACK_INSTALL_REGISTERS |
                     GE_RAMROM_PLAYBACK_INSTALL_STAGE_DIAGNOSTIC;
    install->source_header = header;
    install->register_hash = ge_playback_hash_registers(&header);
    install->save_hash = header.save_hash;
    install->save_byte_count = GE_RAMROM_V5_SAVE_BYTES;
    status = ge_ramrom_v5_copy_save(bytes,
                                    byte_count,
                                    install->save_data,
                                    sizeof(install->save_data));
    if (status != GE_STATUS_OK ||
        ge_ramrom_playback_v5_validate_install(install) != GE_STATUS_OK) {
        memset(out_state, 0, sizeof(*out_state));
        return status == GE_STATUS_OK ? GE_STATUS_ASSET_MISMATCH : status;
    }
    out_state->playback_hash = ge_ramrom_playback_v5_hash_state(out_state);

    ge_playback_init_event(out_state,
                           GE_RAMROM_PLAYBACK_EVENT_STAGE_LOAD_UNSUPPORTED,
                           GE_RAMROM_PLAYBACK_EVENT_FLAG_INSTALL |
                           GE_RAMROM_PLAYBACK_EVENT_FLAG_DIAGNOSTIC,
                           GE_RAMROM_PLAYBACK_DIAGNOSTIC_STAGE_UNSUPPORTED,
                           out_event);
    out_event->flags |= GE_RAMROM_PLAYBACK_EVENT_FLAG_SOURCE_ANCHOR;
    ge_playback_finalize_event(out_state, out_event);
    out_state->event_count = 1u;
    out_state->playback_hash = ge_ramrom_playback_v5_hash_state(out_state);
    return GE_STATUS_OK;
}

static void ge_playback_fail(GERamRomPlaybackStateV5 *state,
                             uint32_t error_code,
                             GERamRomPlaybackEventV5 *event)
{
    state->replay_state = GE_RAMROM_STATE_ERROR;
    state->flags |= GE_RAMROM_PLAYBACK_STATE_ERROR;
    state->error_code = error_code;
    ge_playback_init_event(state,
                           GE_RAMROM_PLAYBACK_EVENT_ERROR,
                           GE_RAMROM_PLAYBACK_EVENT_FLAG_DIAGNOSTIC,
                           error_code,
                           event);
    ge_playback_finalize_event(state, event);
    state->event_count++;
    state->playback_hash = ge_ramrom_playback_v5_hash_state(state);
}

GEStatusV1 ge_ramrom_playback_v5_step(
    const uint8_t *bytes,
    uint32_t byte_count,
    uint64_t native_tick,
    GERamRomPlaybackInputV5 input,
    GERamRomPlaybackStateV5 *inout_state,
    GERamRomPlaybackEventV5 *out_event)
{
    if (bytes == NULL || inout_state == NULL || out_event == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_ramrom_playback_v5_validate_state(inout_state);
    if (status != GE_STATUS_OK) {
        return status;
    }
    status = ge_ramrom_playback_v5_validate_input(&input);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if ((inout_state->flags & GE_RAMROM_PLAYBACK_STATE_ACTIVE) == 0u ||
        (inout_state->flags & GE_RAMROM_PLAYBACK_STATE_INITIALIZED) == 0u ||
        inout_state->replay_state == GE_RAMROM_STATE_ERROR ||
        inout_state->replay_state == GE_RAMROM_STATE_COMPLETE) {
        return GE_STATUS_INVALID_STATE;
    }
    uint64_t expected_tick = inout_state->native_tick == UINT64_MAX ?
        0u : inout_state->native_tick + 1u;
    if (native_tick != expected_tick) {
        ge_playback_fail(inout_state,
                         GE_RAMROM_PLAYBACK_DIAGNOSTIC_TICK,
                         out_event);
        return GE_STATUS_INVALID_ARGUMENT;
    }
    inout_state->native_tick = native_tick;
    inout_state->reference_tick = native_tick / 2u;
    inout_state->pair_phase = (uint32_t)(native_tick & 1u);

    /* An abort is accepted on either paired phase and never consumes replay input. */
    if ((input.flags & GE_RAMROM_PLAYBACK_INPUT_REAL) != 0u &&
        (input.pressed_buttons != 0u || input.held_buttons != 0u ||
         input.released_buttons != 0u)) {
        inout_state->flags |= GE_RAMROM_PLAYBACK_STATE_ABORT_REQUESTED;
        inout_state->abort_buttons = input.pressed_buttons |
                                     input.held_buttons |
                                     input.released_buttons;
        inout_state->replay_state = GE_RAMROM_STATE_ABORTING;
        inout_state->error_code = GE_RAMROM_PLAYBACK_DIAGNOSTIC_INPUT_ABORT;
        ge_playback_init_event(inout_state,
                               GE_RAMROM_PLAYBACK_EVENT_FADE_TO_TITLE,
                               GE_RAMROM_PLAYBACK_EVENT_FLAG_ABORTED_INPUT |
                               GE_RAMROM_PLAYBACK_EVENT_FLAG_RESTORE,
                               GE_RAMROM_PLAYBACK_DIAGNOSTIC_INPUT_ABORT,
                               out_event);
        out_event->abort_buttons = inout_state->abort_buttons;
        ge_playback_finalize_event(inout_state, out_event);
        inout_state->event_count++;
        inout_state->playback_hash = ge_ramrom_playback_v5_hash_state(
            inout_state);
        return GE_STATUS_OK;
    }

    /* An earlier fade is completed by a deterministic return event. */
    if (inout_state->replay_state == GE_RAMROM_STATE_ABORTING) {
        if ((inout_state->flags & GE_RAMROM_PLAYBACK_STATE_ABORT_REQUESTED) ==
            0u) {
            inout_state->flags |= GE_RAMROM_PLAYBACK_STATE_ABORT_REQUESTED;
            ge_playback_init_event(inout_state,
                                   GE_RAMROM_PLAYBACK_EVENT_FADE_TO_TITLE,
                                   GE_RAMROM_PLAYBACK_EVENT_FLAG_END_OF_STREAM,
                                   GE_RAMROM_PLAYBACK_DIAGNOSTIC_NONE,
                                   out_event);
            ge_playback_finalize_event(inout_state, out_event);
            inout_state->event_count++;
            inout_state->playback_hash = ge_ramrom_playback_v5_hash_state(
                inout_state);
            return GE_STATUS_OK;
        }
        inout_state->replay_state = GE_RAMROM_STATE_COMPLETE;
        inout_state->flags |= GE_RAMROM_PLAYBACK_STATE_COMPLETE |
                              GE_RAMROM_PLAYBACK_STATE_RESTORE_READY;
        ge_playback_init_event(inout_state,
                               GE_RAMROM_PLAYBACK_EVENT_RETURN_TO_TITLE,
                               GE_RAMROM_PLAYBACK_EVENT_FLAG_RESTORE,
                               GE_RAMROM_PLAYBACK_DIAGNOSTIC_NONE,
                               out_event);
        out_event->flags |= GE_RAMROM_PLAYBACK_EVENT_FLAG_SOURCE_ANCHOR;
        ge_playback_finalize_event(inout_state, out_event);
        inout_state->event_count++;
        inout_state->playback_hash = ge_ramrom_playback_v5_hash_state(
            inout_state);
        return GE_STATUS_OK;
    }

    if (inout_state->pair_phase != 0u) {
        ge_playback_init_event(inout_state,
                               GE_RAMROM_PLAYBACK_EVENT_NONE,
                               GE_RAMROM_PLAYBACK_EVENT_FLAG_ODD_PAIRED_TICK,
                               GE_RAMROM_PLAYBACK_DIAGNOSTIC_NONE,
                               out_event);
        ge_playback_finalize_event(inout_state, out_event);
        inout_state->event_count++;
        inout_state->playback_hash = ge_ramrom_playback_v5_hash_state(
            inout_state);
        return GE_STATUS_OK;
    }

    if (inout_state->packet_index >= inout_state->packet_count) {
        inout_state->replay_state = GE_RAMROM_STATE_ABORTING;
        ge_playback_init_event(inout_state,
                               GE_RAMROM_PLAYBACK_EVENT_FADE_TO_TITLE,
                               GE_RAMROM_PLAYBACK_EVENT_FLAG_END_OF_STREAM,
                               GE_RAMROM_PLAYBACK_DIAGNOSTIC_NONE,
                               out_event);
        ge_playback_finalize_event(inout_state, out_event);
        inout_state->event_count++;
        inout_state->playback_hash = ge_ramrom_playback_v5_hash_state(
            inout_state);
        return GE_STATUS_OK;
    }

    GERamRomPacketV5 packet;
    status = ge_ramrom_v5_read_packet(bytes,
                                      byte_count,
                                      inout_state->packet_index,
                                      &packet);
    if (status != GE_STATUS_OK) {
        ge_playback_fail(inout_state,
                         status == GE_STATUS_ASSET_MISMATCH ?
                             GE_RAMROM_PLAYBACK_DIAGNOSTIC_CHECKSUM :
                             GE_RAMROM_PLAYBACK_DIAGNOSTIC_PACKET,
                         out_event);
        return status;
    }
    if ((packet.flags & GE_RAMROM_V5_PACKET_FLAG_CHECKSUM_VALID) == 0u ||
        (packet.flags & GE_RAMROM_V5_PACKET_FLAG_SPEEDFRAMES_VALID) == 0u ||
        inout_state->frame_index >= packet.record_count) {
        ge_playback_fail(inout_state,
                         GE_RAMROM_PLAYBACK_DIAGNOSTIC_CHECKSUM,
                         out_event);
        return GE_STATUS_ASSET_MISMATCH;
    }

    uint32_t packet_index = inout_state->packet_index;
    uint32_t frame_index = inout_state->frame_index;
    uint32_t event_flags = GE_RAMROM_PLAYBACK_EVENT_FLAG_SOURCE_ANCHOR;
    if (frame_index == 0u) {
        inout_state->speedframes = packet.speedframes;
        inout_state->rng_index = packet.rng_seed;
        inout_state->source_frame += packet.speedframes;
        if ((packet.flags & GE_RAMROM_V5_PACKET_FLAG_RNG_CHECKPOINT) != 0u) {
            event_flags |= GE_RAMROM_PLAYBACK_EVENT_FLAG_RNG_CHECKPOINT;
        }
    }

    ge_playback_init_event(inout_state,
                           GE_RAMROM_PLAYBACK_EVENT_SAMPLE,
                           event_flags,
                           GE_RAMROM_PLAYBACK_DIAGNOSTIC_NONE,
                           out_event);
    out_event->packet_index = packet_index;
    out_event->frame_index = frame_index;
    out_event->record_count = packet.record_count;
    out_event->controller_count = packet.controller_count;
    out_event->speedframes = packet.speedframes;
    out_event->rng_seed = packet.rng_seed;
    out_event->sample_count = packet.controller_count;
    uint64_t sample_hash = GE_RAMROM_PLAYBACK_V5_FNV_OFFSET;
    for (uint32_t controller = 0u;
         controller < packet.controller_count;
         controller++) {
        GERamRomSampleV5 sample;
        status = ge_ramrom_v5_copy_sample(bytes,
                                          byte_count,
                                          packet_index,
                                          frame_index,
                                          controller,
                                          &sample);
        if (status != GE_STATUS_OK) {
            ge_playback_fail(inout_state,
                             GE_RAMROM_PLAYBACK_DIAGNOSTIC_PACKET,
                             out_event);
            return status;
        }
        out_event->stick_x[controller] = sample.stick_x;
        out_event->stick_y[controller] = sample.stick_y;
        out_event->button_low[controller] = sample.button_low;
        out_event->button_high[controller] = sample.button_high;
        out_event->buttons[controller] = sample.buttons;
        sample_hash = ge_playback_hash_byte(sample_hash,
                                            (uint8_t)sample.stick_x);
        sample_hash = ge_playback_hash_byte(sample_hash,
                                            (uint8_t)sample.stick_y);
        sample_hash = ge_playback_hash_byte(sample_hash,
                                            sample.button_low);
        sample_hash = ge_playback_hash_byte(sample_hash,
                                            sample.button_high);
    }
    out_event->sample_hash = sample_hash;
    inout_state->sample_index++;
    inout_state->source_anchor++;
    inout_state->frame_index++;
    if (inout_state->frame_index >= packet.record_count) {
        inout_state->packet_index++;
        inout_state->frame_index = 0u;
        out_event->flags |= GE_RAMROM_PLAYBACK_EVENT_FLAG_PACKET_ADVANCE;
        if (inout_state->packet_index >= inout_state->packet_count) {
            inout_state->replay_state = GE_RAMROM_STATE_ABORTING;
            out_event->flags |= GE_RAMROM_PLAYBACK_EVENT_FLAG_END_OF_STREAM;
        }
    }
    ge_playback_finalize_event(inout_state, out_event);
    inout_state->event_count++;
    inout_state->playback_hash = ge_ramrom_playback_v5_hash_state(
        inout_state);
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_playback_v5_load_stage(
    const GERamRomPlaybackStateV5 *state,
    GERamRomPlaybackEventV5 *out_event)
{
    if (state == NULL || out_event == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_ramrom_playback_v5_validate_state(state);
    if (status != GE_STATUS_OK) {
        return status;
    }
    ge_playback_init_event(state,
                           GE_RAMROM_PLAYBACK_EVENT_STAGE_LOAD_UNSUPPORTED,
                           GE_RAMROM_PLAYBACK_EVENT_FLAG_DIAGNOSTIC,
                           GE_RAMROM_PLAYBACK_DIAGNOSTIC_STAGE_UNSUPPORTED,
                           out_event);
    ge_playback_finalize_event(state, out_event);
    return GE_STATUS_UNSUPPORTED_COMMAND;
}

GEStatusV1 ge_ramrom_playback_v5_copy_install(
    const GERamRomPlaybackStateV5 *state,
    GERamRomPlaybackInstallV5 *out_install,
    uint32_t for_restore)
{
    if (state == NULL || out_install == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_ramrom_playback_v5_validate_state(state);
    if (status != GE_STATUS_OK) {
        return status;
    }
    *out_install = state->install;
    if (for_restore != 0u) {
        out_install->flags |= GE_RAMROM_PLAYBACK_INSTALL_RESTORED;
    }
    return ge_ramrom_playback_v5_validate_install(out_install);
}
