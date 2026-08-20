#include "ge_ramrom_v5.h"

#include <stddef.h>
#include <string.h>

enum {
    GE_RAMROM_V5_OFFSET_RANDOM_SEED = 0x00,
    GE_RAMROM_V5_OFFSET_RANDOMIZER_SEED = 0x08,
    GE_RAMROM_V5_OFFSET_STAGE = 0x10,
    GE_RAMROM_V5_OFFSET_DIFFICULTY = 0x14,
    GE_RAMROM_V5_OFFSET_CONTROLLERS = 0x18,
    GE_RAMROM_V5_OFFSET_SAVE = 0x1c,
    GE_RAMROM_V5_OFFSET_TOTAL_TIME = 0x7c,
    GE_RAMROM_V5_OFFSET_FILESIZE = 0x80,
    GE_RAMROM_V5_OFFSET_MODE = 0x84,
    GE_RAMROM_V5_OFFSET_SLOT = 0x88,
    GE_RAMROM_V5_OFFSET_PLAYERS = 0x8c,
    GE_RAMROM_V5_OFFSET_SCENARIO = 0x90,
    GE_RAMROM_V5_OFFSET_MP_STAGE = 0x94,
    GE_RAMROM_V5_OFFSET_GAME_LENGTH = 0x98,
    GE_RAMROM_V5_OFFSET_WEAPON_SET = 0x9c,
    GE_RAMROM_V5_OFFSET_CHARACTERS = 0xa0,
    GE_RAMROM_V5_OFFSET_HANDICAPS = 0xb0,
    GE_RAMROM_V5_OFFSET_CONTROLLER_STYLES = 0xc0,
    GE_RAMROM_V5_OFFSET_AIM_OPTION = 0xd0,
    GE_RAMROM_V5_OFFSET_PLAYER_FLAGS = 0xd4,
    GE_RAMROM_V5_OFFSET_TAIL_PADDING = 0xe4,
};

static const uint64_t GE_RAMROM_V5_FNV_OFFSET = UINT64_C(1469598103934665603);
static const uint64_t GE_RAMROM_V5_FNV_PRIME = UINT64_C(1099511628211);

static uint32_t ge_ramrom_v5_be32(const uint8_t *bytes)
{
    return ((uint32_t)bytes[0] << 24) |
           ((uint32_t)bytes[1] << 16) |
           ((uint32_t)bytes[2] << 8) |
           (uint32_t)bytes[3];
}

static uint64_t ge_ramrom_v5_be64(const uint8_t *bytes)
{
    uint64_t value = 0u;
    for (uint32_t index = 0u; index < 8u; index++) {
        value = (value << 8) | (uint64_t)bytes[index];
    }
    return value;
}

static uint64_t ge_ramrom_v5_hash_update(uint64_t hash,
                                         const uint8_t *bytes,
                                         uint32_t byte_count)
{
    if (bytes == NULL && byte_count != 0u) {
        return 0u;
    }
    for (uint32_t index = 0u; index < byte_count; index++) {
        hash ^= (uint64_t)bytes[index];
        hash *= GE_RAMROM_V5_FNV_PRIME;
    }
    return hash;
}

uint64_t ge_ramrom_v5_hash_bytes(const uint8_t *bytes, uint32_t byte_count)
{
    if (bytes == NULL && byte_count != 0u) {
        return 0u;
    }
    return ge_ramrom_v5_hash_update(GE_RAMROM_V5_FNV_OFFSET,
                                    bytes,
                                    byte_count);
}

static int ge_ramrom_v5_all_zero(const uint8_t *bytes, uint32_t byte_count)
{
    for (uint32_t index = 0u; index < byte_count; index++) {
        if (bytes[index] != 0u) {
            return 0;
        }
    }
    return 1;
}

static GEStatusV1 ge_ramrom_v5_validate_common(const GEAbiHeaderV1 *header,
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
    if (record_version != GE_RAMROM_V5_RECORD_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_v5_validate_header(const GERamRomHeaderV5 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_ramrom_v5_validate_common(
        &value->header,
        (uint32_t)sizeof(*value),
        value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->source_header_bytes != GE_RAMROM_V5_HEADER_BYTES ||
        value->controller_count == 0u ||
        value->controller_count > GE_RAMROM_V5_MAX_CONTROLLERS ||
        value->declared_file_bytes < GE_RAMROM_V5_HEADER_BYTES +
                                      GE_RAMROM_V5_TERMINAL_BYTES ||
        value->stage_id > 63u ||
        value->difficulty > 3u ||
        value->reserved0 != 0u ||
        value->reserved1 != 0u ||
        value->save_hash == 0u ||
        value->header_hash == 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_v5_validate_packet(const GERamRomPacketV5 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_ramrom_v5_validate_common(
        &value->header,
        (uint32_t)sizeof(*value),
        value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->record_count == 0u ||
        value->record_count > GE_RAMROM_V5_MAX_PACKET_RECORDS ||
        value->controller_count == 0u ||
        value->controller_count > GE_RAMROM_V5_MAX_CONTROLLERS ||
        value->speedframes == 0u ||
        value->checksum > UINT8_MAX ||
        value->computed_checksum > UINT8_MAX ||
        value->checksum != value->computed_checksum ||
        value->payload_bytes != value->record_count *
            value->controller_count * GE_RAMROM_V5_SAMPLE_BYTES ||
        (value->flags & ~GE_RAMROM_V5_PACKET_FLAG_MASK) != 0u ||
        (value->flags & GE_RAMROM_V5_PACKET_FLAG_CHECKSUM_VALID) == 0u ||
        (value->flags & GE_RAMROM_V5_PACKET_FLAG_SPEEDFRAMES_VALID) == 0u ||
        value->packet_hash == 0u ||
        value->payload_hash == 0u ||
        value->reserved0 != 0u ||
        value->reserved1 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_v5_validate_sample(const GERamRomSampleV5 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_ramrom_v5_validate_common(
        &value->header,
        (uint32_t)sizeof(*value),
        value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->buttons != ((uint32_t)value->button_low |
                           ((uint32_t)value->button_high << 8)) ||
        value->reserved0 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_v5_validate_summary(const GERamRomParseSummaryV5 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_ramrom_v5_validate_common(
        &value->header,
        (uint32_t)sizeof(*value),
        value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if ((value->flags & ~GE_RAMROM_V5_PARSE_FLAG_MASK) != 0u ||
        value->packet_count > GE_RAMROM_V5_MAX_PACKETS ||
        value->checksum_valid_count > value->packet_count ||
        value->rng_checkpoint_count > value->packet_count ||
        value->terminal_bytes != GE_RAMROM_V5_TERMINAL_BYTES ||
        value->parsed_bytes < value->terminal_offset + value->terminal_bytes ||
        value->first_invalid_packet != UINT32_MAX ||
        (value->flags & GE_RAMROM_V5_PARSE_FLAG_HEADER_VALID) == 0u ||
        (value->flags & GE_RAMROM_V5_PARSE_FLAG_TERMINAL_VALID) == 0u ||
        (value->flags & GE_RAMROM_V5_PARSE_FLAG_CHECKSUMS_VALID) == 0u ||
        value->header_hash == 0u ||
        value->recording_hash == 0u ||
        value->packet_hash == 0u ||
        value->input_hash == 0u ||
        value->reserved0 != 0u ||
        value->reserved1 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_v5_validate_catalog_entry(const GERamRomCatalogEntryV5 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_ramrom_v5_validate_common(
        &value->header,
        (uint32_t)sizeof(*value),
        value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->demo_id == 0u || value->demo_id > GE_RAMROM_V5_DEMO_COUNT ||
        value->controller_count == 0u ||
        value->controller_count > GE_RAMROM_V5_MAX_CONTROLLERS ||
        value->declared_file_bytes < GE_RAMROM_V5_HEADER_BYTES +
                                      GE_RAMROM_V5_TERMINAL_BYTES ||
        value->asset_file_bytes < value->declared_file_bytes ||
        value->asset_file_bytes - value->declared_file_bytes >
            GE_RAMROM_V5_MAX_TRAILING_BYTES ||
        value->recording_hash == 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_ramrom_v5_read_header(const uint8_t *bytes,
                                    uint32_t byte_count,
                                    GERamRomHeaderV5 *out_header)
{
    if (bytes == NULL || out_header == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (byte_count < GE_RAMROM_V5_HEADER_BYTES) {
        return GE_STATUS_MALFORMED_STREAM;
    }

    uint32_t declared_file_bytes = ge_ramrom_v5_be32(
        bytes + GE_RAMROM_V5_OFFSET_FILESIZE);
    if (declared_file_bytes < GE_RAMROM_V5_HEADER_BYTES +
                                  GE_RAMROM_V5_TERMINAL_BYTES ||
        declared_file_bytes > byte_count ||
        byte_count - declared_file_bytes > GE_RAMROM_V5_MAX_TRAILING_BYTES ||
        !ge_ramrom_v5_all_zero(bytes + declared_file_bytes,
                               byte_count - declared_file_bytes) ||
        !ge_ramrom_v5_all_zero(bytes + GE_RAMROM_V5_OFFSET_TAIL_PADDING,
                               GE_RAMROM_V5_HEADER_BYTES -
                               GE_RAMROM_V5_OFFSET_TAIL_PADDING)) {
        return GE_STATUS_MALFORMED_STREAM;
    }

    memset(out_header, 0, sizeof(*out_header));
    out_header->header.abi_version = GE_NATIVE_ABI_VERSION;
    out_header->header.struct_size = (uint32_t)sizeof(*out_header);
    out_header->record_version = GE_RAMROM_V5_RECORD_VERSION;
    out_header->source_header_bytes = GE_RAMROM_V5_HEADER_BYTES;
    out_header->random_seed = ge_ramrom_v5_be64(
        bytes + GE_RAMROM_V5_OFFSET_RANDOM_SEED);
    out_header->randomizer_seed = ge_ramrom_v5_be64(
        bytes + GE_RAMROM_V5_OFFSET_RANDOMIZER_SEED);
    out_header->stage_id = ge_ramrom_v5_be32(bytes + GE_RAMROM_V5_OFFSET_STAGE);
    out_header->difficulty = ge_ramrom_v5_be32(
        bytes + GE_RAMROM_V5_OFFSET_DIFFICULTY);
    out_header->controller_count = ge_ramrom_v5_be32(
        bytes + GE_RAMROM_V5_OFFSET_CONTROLLERS);
    out_header->total_time_ms = ge_ramrom_v5_be32(
        bytes + GE_RAMROM_V5_OFFSET_TOTAL_TIME);
    out_header->declared_file_bytes = declared_file_bytes;
    out_header->mode = ge_ramrom_v5_be32(bytes + GE_RAMROM_V5_OFFSET_MODE);
    out_header->slot_number = ge_ramrom_v5_be32(bytes + GE_RAMROM_V5_OFFSET_SLOT);
    out_header->player_count = ge_ramrom_v5_be32(
        bytes + GE_RAMROM_V5_OFFSET_PLAYERS);
    out_header->scenario = ge_ramrom_v5_be32(
        bytes + GE_RAMROM_V5_OFFSET_SCENARIO);
    out_header->multiplayer_stage = ge_ramrom_v5_be32(
        bytes + GE_RAMROM_V5_OFFSET_MP_STAGE);
    out_header->game_length = ge_ramrom_v5_be32(
        bytes + GE_RAMROM_V5_OFFSET_GAME_LENGTH);
    out_header->weapon_set = ge_ramrom_v5_be32(
        bytes + GE_RAMROM_V5_OFFSET_WEAPON_SET);
    out_header->aim_option = ge_ramrom_v5_be32(
        bytes + GE_RAMROM_V5_OFFSET_AIM_OPTION);
    for (uint32_t index = 0u; index < 4u; index++) {
        out_header->character_ids[index] = ge_ramrom_v5_be32(
            bytes + GE_RAMROM_V5_OFFSET_CHARACTERS + index * 4u);
        out_header->handicaps[index] = ge_ramrom_v5_be32(
            bytes + GE_RAMROM_V5_OFFSET_HANDICAPS + index * 4u);
        out_header->controller_styles[index] = ge_ramrom_v5_be32(
            bytes + GE_RAMROM_V5_OFFSET_CONTROLLER_STYLES + index * 4u);
        out_header->player_flags[index] = ge_ramrom_v5_be32(
            bytes + GE_RAMROM_V5_OFFSET_PLAYER_FLAGS + index * 4u);
    }
    out_header->save_checksum1 = ge_ramrom_v5_be32(
        bytes + GE_RAMROM_V5_OFFSET_SAVE);
    out_header->save_checksum2 = ge_ramrom_v5_be32(
        bytes + GE_RAMROM_V5_OFFSET_SAVE + 4u);
    out_header->save_hash = ge_ramrom_v5_hash_bytes(
        bytes + GE_RAMROM_V5_OFFSET_SAVE,
        GE_RAMROM_V5_SAVE_BYTES);
    out_header->header_hash = ge_ramrom_v5_hash_bytes(
        bytes,
        GE_RAMROM_V5_HEADER_BYTES);
    return ge_ramrom_v5_validate_header(out_header);
}

GEStatusV1 ge_ramrom_v5_copy_save(const uint8_t *bytes,
                                  uint32_t byte_count,
                                  uint8_t *out_save,
                                  uint32_t out_save_capacity)
{
    GERamRomHeaderV5 header;
    GEStatusV1 status = ge_ramrom_v5_read_header(bytes, byte_count, &header);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (out_save == NULL || out_save_capacity < GE_RAMROM_V5_SAVE_BYTES) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    memcpy(out_save, bytes + GE_RAMROM_V5_OFFSET_SAVE,
           GE_RAMROM_V5_SAVE_BYTES);
    return GE_STATUS_OK;
}

static uint8_t ge_ramrom_v5_packet_checksum(const uint8_t *packet,
                                            uint32_t payload_bytes)
{
    uint32_t checksum = (uint32_t)packet[0] +
                        (uint32_t)packet[1] +
                        (uint32_t)packet[2];
    for (uint32_t index = 0u; index < payload_bytes; index++) {
        checksum += (uint32_t)packet[GE_RAMROM_V5_PACKET_HEADER_BYTES + index];
    }
    return (uint8_t)checksum;
}

static void ge_ramrom_v5_fill_packet(const uint8_t *bytes,
                                     uint32_t packet_index,
                                     uint32_t byte_offset,
                                     uint32_t controller_count,
                                     GERamRomPacketV5 *out_packet)
{
    const uint8_t *packet = bytes + byte_offset;
    uint32_t record_count = (uint32_t)packet[1];
    uint32_t payload_bytes = record_count * controller_count *
                             GE_RAMROM_V5_SAMPLE_BYTES;
    uint8_t computed_checksum = ge_ramrom_v5_packet_checksum(
        packet, payload_bytes);

    memset(out_packet, 0, sizeof(*out_packet));
    out_packet->header.abi_version = GE_NATIVE_ABI_VERSION;
    out_packet->header.struct_size = (uint32_t)sizeof(*out_packet);
    out_packet->record_version = GE_RAMROM_V5_RECORD_VERSION;
    out_packet->packet_index = packet_index;
    out_packet->byte_offset = byte_offset;
    out_packet->record_count = record_count;
    out_packet->controller_count = controller_count;
    out_packet->speedframes = packet[0];
    out_packet->rng_seed = packet[2];
    out_packet->checksum = packet[3];
    out_packet->computed_checksum = computed_checksum;
    out_packet->payload_bytes = payload_bytes;
    out_packet->flags = GE_RAMROM_V5_PACKET_FLAG_SPEEDFRAMES_VALID;
    if (computed_checksum == packet[3]) {
        out_packet->flags |= GE_RAMROM_V5_PACKET_FLAG_CHECKSUM_VALID;
    }
    if (packet[2] != 0u) {
        out_packet->flags |= GE_RAMROM_V5_PACKET_FLAG_RNG_CHECKPOINT;
    }
    out_packet->packet_hash = ge_ramrom_v5_hash_bytes(
        packet,
        GE_RAMROM_V5_PACKET_HEADER_BYTES + payload_bytes);
    out_packet->payload_hash = ge_ramrom_v5_hash_bytes(
        packet + GE_RAMROM_V5_PACKET_HEADER_BYTES,
        payload_bytes);
}

static GEStatusV1 ge_ramrom_v5_scan(const uint8_t *bytes,
                                    uint32_t byte_count,
                                    const GERamRomHeaderV5 *header,
                                    GERamRomParseSummaryV5 *out_summary,
                                    uint32_t wanted_packet,
                                    GERamRomPacketV5 *out_packet)
{
    uint32_t offset = GE_RAMROM_V5_HEADER_BYTES;
    uint32_t packet_count = 0u;
    uint32_t record_count = 0u;
    uint32_t checksum_valid_count = 0u;
    uint32_t rng_checkpoint_count = 0u;
    uint32_t first_invalid_packet = UINT32_MAX;
    uint64_t packet_hash = GE_RAMROM_V5_FNV_OFFSET;
    uint64_t rng_hash = GE_RAMROM_V5_FNV_OFFSET;
    uint64_t input_hash = GE_RAMROM_V5_FNV_OFFSET;
    GEStatusV1 result = GE_STATUS_OK;
    int terminal_seen = 0;

    while (offset + GE_RAMROM_V5_PACKET_HEADER_BYTES <=
           header->declared_file_bytes) {
        const uint8_t *packet = bytes + offset;
        if (ge_ramrom_v5_all_zero(packet,
                                   GE_RAMROM_V5_PACKET_HEADER_BYTES)) {
            terminal_seen = 1;
            if (offset + GE_RAMROM_V5_TERMINAL_BYTES !=
                header->declared_file_bytes) {
                result = GE_STATUS_MALFORMED_STREAM;
            }
            offset += GE_RAMROM_V5_TERMINAL_BYTES;
            break;
        }

        uint32_t packet_records = (uint32_t)packet[1];
        if (packet[0] == 0u || packet_records == 0u) {
            result = GE_STATUS_MALFORMED_STREAM;
            break;
        }
        if (packet_count >= GE_RAMROM_V5_MAX_PACKETS ||
            record_count > UINT32_MAX - packet_records) {
            result = GE_STATUS_REPLAY_BUDGET;
            break;
        }
        uint32_t payload_bytes = packet_records *
                                 header->controller_count *
                                 GE_RAMROM_V5_SAMPLE_BYTES;
        if (offset > header->declared_file_bytes -
                     GE_RAMROM_V5_PACKET_HEADER_BYTES ||
            payload_bytes > header->declared_file_bytes -
                     offset - GE_RAMROM_V5_PACKET_HEADER_BYTES) {
            result = GE_STATUS_MALFORMED_STREAM;
            break;
        }

        GERamRomPacketV5 packet_value;
        ge_ramrom_v5_fill_packet(bytes,
                                 packet_count,
                                 offset,
                                 header->controller_count,
                                 &packet_value);
        if (packet_value.computed_checksum == packet_value.checksum) {
            checksum_valid_count++;
        } else if (first_invalid_packet == UINT32_MAX) {
            first_invalid_packet = packet_count;
            result = GE_STATUS_ASSET_MISMATCH;
        }
        if (packet_value.rng_seed != 0u) {
            rng_checkpoint_count++;
        }
        packet_hash = ge_ramrom_v5_hash_update(
            packet_hash,
            packet,
            GE_RAMROM_V5_PACKET_HEADER_BYTES + payload_bytes);
        rng_hash = ge_ramrom_v5_hash_update(rng_hash, packet, 4u);
        input_hash = ge_ramrom_v5_hash_update(
            input_hash,
            packet + GE_RAMROM_V5_PACKET_HEADER_BYTES,
            payload_bytes);
        if (out_packet != NULL && packet_count == wanted_packet) {
            *out_packet = packet_value;
        }
        packet_count++;
        record_count += packet_records;
        offset += GE_RAMROM_V5_PACKET_HEADER_BYTES + payload_bytes;
    }

    if (!terminal_seen && result == GE_STATUS_OK) {
        result = GE_STATUS_MALFORMED_STREAM;
    }
    if (out_summary != NULL) {
        memset(out_summary, 0, sizeof(*out_summary));
        out_summary->header.abi_version = GE_NATIVE_ABI_VERSION;
        out_summary->header.struct_size = (uint32_t)sizeof(*out_summary);
        out_summary->record_version = GE_RAMROM_V5_RECORD_VERSION;
        out_summary->flags = GE_RAMROM_V5_PARSE_FLAG_HEADER_VALID;
        if (terminal_seen && offset == header->declared_file_bytes) {
            out_summary->flags |= GE_RAMROM_V5_PARSE_FLAG_TERMINAL_VALID;
        }
        if (first_invalid_packet == UINT32_MAX && terminal_seen &&
            result == GE_STATUS_OK) {
            out_summary->flags |= GE_RAMROM_V5_PARSE_FLAG_CHECKSUMS_VALID;
        }
        if (rng_checkpoint_count != 0u) {
            out_summary->flags |= GE_RAMROM_V5_PARSE_FLAG_RNG_CHECKPOINTS;
        }
        if (packet_count != 0u && result != GE_STATUS_REPLAY_BUDGET) {
            out_summary->flags |= GE_RAMROM_V5_PARSE_FLAG_SPEEDFRAMES_VALID;
        }
        out_summary->packet_count = packet_count;
        out_summary->record_count = record_count;
        out_summary->checksum_valid_count = checksum_valid_count;
        out_summary->rng_checkpoint_count = rng_checkpoint_count;
        out_summary->terminal_offset = terminal_seen ?
            offset - GE_RAMROM_V5_TERMINAL_BYTES : 0u;
        out_summary->terminal_bytes = terminal_seen ?
            GE_RAMROM_V5_TERMINAL_BYTES : 0u;
        out_summary->parsed_bytes = offset;
        out_summary->trailing_bytes = byte_count - header->declared_file_bytes;
        out_summary->first_invalid_packet = first_invalid_packet;
        out_summary->header_hash = header->header_hash;
        out_summary->recording_hash = ge_ramrom_v5_hash_bytes(
            bytes, header->declared_file_bytes);
        out_summary->packet_hash = packet_hash;
        out_summary->rng_hash = rng_hash;
        out_summary->input_hash = input_hash;
    }
    return result;
}

GEStatusV1 ge_ramrom_v5_read_packet(const uint8_t *bytes,
                                    uint32_t byte_count,
                                    uint32_t packet_index,
                                    GERamRomPacketV5 *out_packet)
{
    if (bytes == NULL || out_packet == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GERamRomHeaderV5 header;
    GEStatusV1 status = ge_ramrom_v5_read_header(bytes, byte_count, &header);
    if (status != GE_STATUS_OK) {
        return status;
    }
    GERamRomParseSummaryV5 summary;
    status = ge_ramrom_v5_scan(bytes,
                               byte_count,
                               &header,
                               &summary,
                               packet_index,
                               out_packet);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (packet_index >= summary.packet_count) {
        return GE_STATUS_RESOURCE_NOT_FOUND;
    }
    return ge_ramrom_v5_validate_packet(out_packet);
}

GEStatusV1 ge_ramrom_v5_copy_sample(const uint8_t *bytes,
                                    uint32_t byte_count,
                                    uint32_t packet_index,
                                    uint32_t frame_index,
                                    uint32_t controller_index,
                                    GERamRomSampleV5 *out_sample)
{
    if (bytes == NULL || out_sample == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GERamRomPacketV5 packet;
    GEStatusV1 status = ge_ramrom_v5_read_packet(bytes,
                                                byte_count,
                                                packet_index,
                                                &packet);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (frame_index >= packet.record_count ||
        controller_index >= packet.controller_count) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    uint32_t sample_index = frame_index * packet.controller_count +
                            controller_index;
    uint32_t byte_offset = packet.byte_offset +
        GE_RAMROM_V5_PACKET_HEADER_BYTES +
        sample_index * GE_RAMROM_V5_SAMPLE_BYTES;
    if (byte_offset > byte_count - GE_RAMROM_V5_SAMPLE_BYTES) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    const uint8_t *source = bytes + byte_offset;
    memset(out_sample, 0, sizeof(*out_sample));
    out_sample->header.abi_version = GE_NATIVE_ABI_VERSION;
    out_sample->header.struct_size = (uint32_t)sizeof(*out_sample);
    out_sample->record_version = GE_RAMROM_V5_RECORD_VERSION;
    out_sample->packet_index = packet_index;
    out_sample->frame_index = frame_index;
    out_sample->controller_index = controller_index;
    out_sample->stick_x = (int8_t)source[0];
    out_sample->stick_y = (int8_t)source[1];
    out_sample->button_low = source[2];
    out_sample->button_high = source[3];
    out_sample->buttons = (uint32_t)source[2] |
                          ((uint32_t)source[3] << 8);
    return ge_ramrom_v5_validate_sample(out_sample);
}

GEStatusV1 ge_ramrom_v5_parse(const uint8_t *bytes,
                              uint32_t byte_count,
                              GERamRomParseSummaryV5 *out_summary)
{
    if (bytes == NULL || out_summary == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GERamRomHeaderV5 header;
    GEStatusV1 status = ge_ramrom_v5_read_header(bytes, byte_count, &header);
    if (status != GE_STATUS_OK) {
        memset(out_summary, 0, sizeof(*out_summary));
        return status;
    }
    status = ge_ramrom_v5_scan(bytes,
                               byte_count,
                               &header,
                               out_summary,
                               UINT32_MAX,
                               NULL);
    if (status != GE_STATUS_OK) {
        return status;
    }
    return ge_ramrom_v5_validate_summary(out_summary);
}

GEStatusV1 ge_ramrom_v5_m28_prepare_snapshot(
    const GERamRomParseSummaryV5 *summary,
    const GERamRomHeaderV5 *header,
    uint32_t demo_id,
    GERamRomSnapshotV5 *out_snapshot)
{
    if (summary == NULL || header == NULL || out_snapshot == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (ge_ramrom_v5_validate_summary(summary) != GE_STATUS_OK ||
        ge_ramrom_v5_validate_header(header) != GE_STATUS_OK ||
        demo_id == 0u || demo_id > GE_RAMROM_V5_DEMO_COUNT) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    memset(out_snapshot, 0, sizeof(*out_snapshot));
    out_snapshot->header.abi_version = GE_NATIVE_ABI_VERSION;
    out_snapshot->header.struct_size = (uint32_t)sizeof(*out_snapshot);
    out_snapshot->record_version = GE_RUNTIME_V5_RECORD_VERSION;
    out_snapshot->flags = GE_RAMROM_FLAG_SOURCE_ANCHOR |
                          GE_RAMROM_FLAG_CHECKSUM_VALID;
    if (summary->rng_checkpoint_count != 0u) {
        out_snapshot->flags |= GE_RAMROM_FLAG_RNG_CHECKPOINT;
    }
    out_snapshot->replay_state = GE_RAMROM_STATE_LOADING;
    out_snapshot->demo_id = demo_id;
    out_snapshot->stage_id = header->stage_id;
    out_snapshot->packet_count = summary->packet_count;
    out_snapshot->recording_hash = summary->recording_hash;
    out_snapshot->rng_hash = summary->rng_hash;
    out_snapshot->state_hash = summary->packet_hash;
    return GE_STATUS_OK;
}

static const GERamRomCatalogEntryV5 GE_RAMROM_V5_CATALOG[
    GE_RAMROM_V5_DEMO_COUNT] = {
    { {GE_NATIVE_ABI_VERSION, sizeof(GERamRomCatalogEntryV5)},
      GE_RAMROM_V5_RECORD_VERSION, GE_RAMROM_V5_DEMO_DAM_1,
      GE_RAMROM_V5_STAGE_DAM, 1u, 3u, 20988u, 20992u, 1466u,
      UINT64_C(0x2928def94f3e83de) },
    { {GE_NATIVE_ABI_VERSION, sizeof(GERamRomCatalogEntryV5)},
      GE_RAMROM_V5_RECORD_VERSION, GE_RAMROM_V5_DEMO_DAM_2,
      GE_RAMROM_V5_STAGE_DAM, 2u, 1u, 8136u, 8144u, 1496u,
      UINT64_C(0x2eabdfda9685ef06) },
    { {GE_NATIVE_ABI_VERSION, sizeof(GERamRomCatalogEntryV5)},
      GE_RAMROM_V5_RECORD_VERSION, GE_RAMROM_V5_DEMO_FACILITY_1,
      GE_RAMROM_V5_STAGE_FACILITY, 1u, 1u, 6828u, 6832u, 1210u,
      UINT64_C(0x41021bcbf0818874) },
    { {GE_NATIVE_ABI_VERSION, sizeof(GERamRomCatalogEntryV5)},
      GE_RAMROM_V5_RECORD_VERSION, GE_RAMROM_V5_DEMO_FACILITY_2,
      GE_RAMROM_V5_STAGE_FACILITY, 2u, 1u, 9180u, 9184u, 1660u,
      UINT64_C(0x28a75f5882dc4527) },
    { {GE_NATIVE_ABI_VERSION, sizeof(GERamRomCatalogEntryV5)},
      GE_RAMROM_V5_RECORD_VERSION, GE_RAMROM_V5_DEMO_FACILITY_3,
      GE_RAMROM_V5_STAGE_FACILITY, 3u, 1u, 7268u, 7280u, 1352u,
      UINT64_C(0xa72bf01e7cd01a06) },
    { {GE_NATIVE_ABI_VERSION, sizeof(GERamRomCatalogEntryV5)},
      GE_RAMROM_V5_RECORD_VERSION, GE_RAMROM_V5_DEMO_RUNWAY_1,
      GE_RAMROM_V5_STAGE_RUNWAY, 1u, 2u, 10056u, 10064u, 1013u,
      UINT64_C(0x652861025f90d929) },
    { {GE_NATIVE_ABI_VERSION, sizeof(GERamRomCatalogEntryV5)},
      GE_RAMROM_V5_RECORD_VERSION, GE_RAMROM_V5_DEMO_RUNWAY_2,
      GE_RAMROM_V5_STAGE_RUNWAY, 2u, 2u, 10512u, 10512u, 1059u,
      UINT64_C(0xd71529ad6aca88da) },
    { {GE_NATIVE_ABI_VERSION, sizeof(GERamRomCatalogEntryV5)},
      GE_RAMROM_V5_RECORD_VERSION, GE_RAMROM_V5_DEMO_BUNKER_I_1,
      GE_RAMROM_V5_STAGE_BUNKER_I, 1u, 2u, 13196u, 13200u, 1349u,
      UINT64_C(0x12ce306461fbc135) },
    { {GE_NATIVE_ABI_VERSION, sizeof(GERamRomCatalogEntryV5)},
      GE_RAMROM_V5_RECORD_VERSION, GE_RAMROM_V5_DEMO_BUNKER_I_2,
      GE_RAMROM_V5_STAGE_BUNKER_I, 2u, 2u, 21112u, 21120u, 1761u,
      UINT64_C(0xc0fcd490c46d7123) },
    { {GE_NATIVE_ABI_VERSION, sizeof(GERamRomCatalogEntryV5)},
      GE_RAMROM_V5_RECORD_VERSION, GE_RAMROM_V5_DEMO_SILO_1,
      GE_RAMROM_V5_STAGE_SILO, 1u, 1u, 8592u, 8592u, 1563u,
      UINT64_C(0x72dc5c008a8fc153) },
    { {GE_NATIVE_ABI_VERSION, sizeof(GERamRomCatalogEntryV5)},
      GE_RAMROM_V5_RECORD_VERSION, GE_RAMROM_V5_DEMO_SILO_2,
      GE_RAMROM_V5_STAGE_SILO, 2u, 1u, 8136u, 8144u, 1289u,
      UINT64_C(0x23833bf624097c3b) },
    { {GE_NATIVE_ABI_VERSION, sizeof(GERamRomCatalogEntryV5)},
      GE_RAMROM_V5_RECORD_VERSION, GE_RAMROM_V5_DEMO_FRIGATE_1,
      GE_RAMROM_V5_STAGE_FRIGATE, 1u, 1u, 6576u, 6576u, 1250u,
      UINT64_C(0x09712449fee2a976) },
    { {GE_NATIVE_ABI_VERSION, sizeof(GERamRomCatalogEntryV5)},
      GE_RAMROM_V5_RECORD_VERSION, GE_RAMROM_V5_DEMO_FRIGATE_2,
      GE_RAMROM_V5_STAGE_FRIGATE, 2u, 2u, 13532u, 13536u, 1454u,
      UINT64_C(0xd1bdc81fc9d6031b) },
    { {GE_NATIVE_ABI_VERSION, sizeof(GERamRomCatalogEntryV5)},
      GE_RAMROM_V5_RECORD_VERSION, GE_RAMROM_V5_DEMO_TRAIN,
      GE_RAMROM_V5_STAGE_TRAIN, 1u, 2u, 15848u, 15856u, 1738u,
      UINT64_C(0x4a6ea00902f40139) },
};

uint32_t ge_ramrom_v5_catalog_count(void)
{
    return GE_RAMROM_V5_DEMO_COUNT;
}

GEStatusV1 ge_ramrom_v5_catalog_entry(uint32_t index,
                                      GERamRomCatalogEntryV5 *out_entry)
{
    if (out_entry == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (index >= GE_RAMROM_V5_DEMO_COUNT) {
        return GE_STATUS_RESOURCE_NOT_FOUND;
    }
    *out_entry = GE_RAMROM_V5_CATALOG[index];
    return ge_ramrom_v5_validate_catalog_entry(out_entry);
}
