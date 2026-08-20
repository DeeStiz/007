#include "ge_audio_v5.h"

#include <stddef.h>
#include <string.h>

static GEStatusV1 ge_audio_validate_header(const GEAbiHeaderV1 *header,
                                           uint32_t expected_size)
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
    return GE_STATUS_OK;
}

static int ge_audio_hash_present(const uint8_t hash[32])
{
    uint8_t combined = 0u;
    for (size_t index = 0; index < 32u; index++) {
        combined |= hash[index];
    }
    return combined != 0u;
}

static int ge_audio_asset_kind_known(uint32_t kind)
{
    switch (kind) {
    case GE_AUDIO_V5_ASSET_MUSIC_SEQUENCE:
    case GE_AUDIO_V5_ASSET_INSTRUMENT_CTL:
    case GE_AUDIO_V5_ASSET_INSTRUMENT_TBL:
    case GE_AUDIO_V5_ASSET_SFX_CTL:
    case GE_AUDIO_V5_ASSET_SFX_TBL:
        return 1;
    default:
        return 0;
    }
}

static int ge_audio_event_kind_known(uint32_t kind)
{
    return kind <= GE_AUDIO_V5_EVENT_MARKER;
}

uint64_t ge_audio_sample_index_for_tick_v5(uint64_t native_tick)
{
    /* Divide before multiplying so ordinary values cannot overflow a
       64-bit intermediate.  Saturation is the explicit behavior for an
       impossible host run approaching UINT64_MAX ticks. */
    uint64_t whole_ticks = native_tick / GE_AUDIO_V5_SAMPLE_DENOMINATOR;
    uint64_t remainder = native_tick % GE_AUDIO_V5_SAMPLE_DENOMINATOR;
    if (whole_ticks > UINT64_MAX / GE_AUDIO_V5_SAMPLE_NUMERATOR) {
        return UINT64_MAX;
    }
    uint64_t base = whole_ticks * GE_AUDIO_V5_SAMPLE_NUMERATOR;
    uint64_t extra = (remainder * GE_AUDIO_V5_SAMPLE_NUMERATOR) /
        GE_AUDIO_V5_SAMPLE_DENOMINATOR;
    if (base > UINT64_MAX - extra) {
        return UINT64_MAX;
    }
    return base + extra;
}

uint32_t ge_audio_frame_count_for_tick_v5(uint64_t native_tick)
{
    /* floor((tick + 1) * 735 / 4) - floor(tick * 735 / 4). */
    return (uint32_t)(GE_AUDIO_V5_SAMPLE_NUMERATOR /
                      GE_AUDIO_V5_SAMPLE_DENOMINATOR) +
        (native_tick % GE_AUDIO_V5_SAMPLE_DENOMINATOR == 0u ? 0u : 1u);
}

GEAudioClockV5 ge_audio_clock_for_tick_v5(uint64_t native_tick)
{
    GEAudioClockV5 clock;
    memset(&clock, 0, sizeof(clock));
    clock.header.abi_version = GE_NATIVE_ABI_VERSION;
    clock.header.struct_size = (uint32_t)sizeof(clock);
    clock.contract_version = GE_AUDIO_V5_CONTRACT_VERSION;
    clock.native_tick = native_tick;
    clock.sample_index = ge_audio_sample_index_for_tick_v5(native_tick);
    clock.frame_count = ge_audio_frame_count_for_tick_v5(native_tick);
    clock.pair_phase = (uint32_t)(native_tick & 1u);
    return clock;
}

GEStatusV1 ge_audio_validate_asset_v5(GEAudioAssetV5 asset)
{
    GEStatusV1 status = ge_audio_validate_header(&asset.header,
                                                 (uint32_t)sizeof(asset));
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (asset.contract_version != GE_AUDIO_V5_CONTRACT_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    if (!ge_audio_asset_kind_known(asset.asset_kind) ||
        asset.asset_handle == GE_AUDIO_V5_HANDLE_NONE ||
        asset.catalog_id == 0u ||
        asset.source_byte_count == 0u ||
        asset.decoded_byte_count == 0u ||
        asset.reserved0 != 0u ||
        (asset.flags & ~GE_AUDIO_V5_ASSET_FLAG_MASK) != 0u ||
        !ge_audio_hash_present(asset.source_sha256) ||
        !ge_audio_hash_present(asset.decoded_sha256)) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    if ((asset.flags & GE_AUDIO_V5_ASSET_FLAG_DECODED) == 0u) {
        return GE_STATUS_RESOURCE_NOT_FOUND;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_audio_validate_event_v5(GEAudioEventV5 event)
{
    GEStatusV1 status = ge_audio_validate_header(&event.header,
                                                 (uint32_t)sizeof(event));
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (event.contract_version != GE_AUDIO_V5_CONTRACT_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    if (!ge_audio_event_kind_known(event.event_kind) ||
        (event.flags & ~GE_AUDIO_V5_EVENT_FLAG_MASK) != 0u ||
        event.reserved0 != 0u ||
        (event.voice_index != GE_AUDIO_V5_VOICE_NONE &&
         event.voice_index >= GE_AUDIO_V5_MAX_VOICES)) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    if (event.event_kind == GE_AUDIO_V5_EVENT_START_SEQUENCE &&
        event.asset_handle == GE_AUDIO_V5_HANDLE_NONE) {
        return GE_STATUS_RESOURCE_NOT_FOUND;
    }
    if (event.event_kind == GE_AUDIO_V5_EVENT_START_SFX &&
        event.asset_handle == GE_AUDIO_V5_HANDLE_NONE) {
        return GE_STATUS_RESOURCE_NOT_FOUND;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_audio_validate_pcm_block_v5(GEAudioPCMBlockV5 block)
{
    GEStatusV1 status = ge_audio_validate_header(&block.header,
                                                 (uint32_t)sizeof(block));
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (block.contract_version != GE_AUDIO_V5_CONTRACT_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    uint32_t bytes_per_sample = 0u;
    if (block.sample_format == GE_AUDIO_V5_PCM_FORMAT_S16) {
        bytes_per_sample = 2u;
    } else if (block.sample_format == GE_AUDIO_V5_PCM_FORMAT_F32) {
        bytes_per_sample = 4u;
    }
    if ((block.flags & ~GE_AUDIO_V5_PCM_FLAG_MASK) != 0u ||
        block.frame_count > GE_AUDIO_V5_PCM_MAX_FRAMES ||
        block.channel_count == 0u || block.channel_count > 2u ||
        block.sample_rate != GE_AUDIO_V5_SAMPLE_RATE ||
        bytes_per_sample == 0u ||
        block.bytes_per_frame != block.channel_count * bytes_per_sample ||
        block.frame_count > UINT32_MAX / block.bytes_per_frame ||
        block.byte_count != block.frame_count * block.bytes_per_frame ||
        block.reserved0 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_audio_validate_snapshot_v5(GEAudioSnapshotV5 snapshot)
{
    GEStatusV1 status = ge_audio_validate_header(&snapshot.header,
                                                 (uint32_t)sizeof(snapshot));
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (snapshot.contract_version != GE_AUDIO_V5_CONTRACT_VERSION ||
        snapshot.active_voice_count > GE_AUDIO_V5_MAX_VOICES ||
        snapshot.sample_rate != GE_AUDIO_V5_SAMPLE_RATE ||
        snapshot.music_slot_count > 3u ||
        snapshot.reserved0 != 0u || snapshot.reserved1 != 0u ||
        snapshot.reserved2 != 0u || snapshot.reserved3 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}
