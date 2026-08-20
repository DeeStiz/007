#include "ge_audio_effects_v6.h"

#include <limits.h>
#include <stddef.h>
#include <string.h>

#define GE_AUDIO_EFFECTS_V6_HASH_OFFSET UINT64_C(1469598103934665603)
#define GE_AUDIO_EFFECTS_V6_HASH_PRIME UINT64_C(1099511628211)
#define GE_AUDIO_EFFECTS_V6_Q15_ONE ((int32_t)32768)
#define GE_AUDIO_EFFECTS_V6_Q16_ONE ((uint32_t)65536u)
#define GE_AUDIO_EFFECTS_V6_SMALL_ROOM_SECTION_COUNT ((uint32_t)3u)
#define GE_AUDIO_EFFECTS_V6_BIG_ROOM_SECTION_COUNT ((uint32_t)4u)

static void ge_audio_effects_diagnostic_clear_v6(GEAudioDiagnosticV5 *diagnostic)
{
    if (diagnostic == NULL) {
        return;
    }
    memset(diagnostic, 0, sizeof(*diagnostic));
    diagnostic->version = GE_AUDIO_ENGINE_V5_VERSION;
}

static GEStatusV1 ge_audio_effects_diagnostic_set_v6(
    GEAudioDiagnosticV5 *diagnostic,
    uint32_t code,
    uint32_t flags,
    uint32_t detail0,
    uint32_t detail1,
    const char *message,
    GEStatusV1 status)
{
    ge_audio_effects_diagnostic_clear_v6(diagnostic);
    if (diagnostic != NULL) {
        diagnostic->code = code;
        diagnostic->flags = flags;
        diagnostic->detail0 = detail0;
        diagnostic->detail1 = detail1;
        if (message != NULL) {
            size_t index = 0u;
            while (message[index] != '\0' && index + 1u < sizeof(diagnostic->message)) {
                diagnostic->message[index] = message[index];
                index++;
            }
            diagnostic->message[index] = '\0';
        }
    }
    return status;
}

static int ge_audio_effects_header_valid_v6(const GEAbiHeaderV1 *header,
                                            uint32_t expected_size)
{
    return header != NULL &&
        header->abi_version == GE_NATIVE_ABI_VERSION &&
        header->struct_size == expected_size;
}

static uint32_t ge_audio_effects_ms_to_frames_v6(uint32_t milliseconds,
                                                uint32_t sample_rate)
{
    uint64_t numerator = (uint64_t)milliseconds * (uint64_t)sample_rate + 500u;
    uint64_t frames = numerator / 1000u;
    return frames > UINT32_MAX ? UINT32_MAX : (uint32_t)frames;
}

static int32_t ge_audio_effects_clamp_i32_v6(int64_t value)
{
    if (value > (int64_t)INT32_MAX) {
        return INT32_MAX;
    }
    if (value < (int64_t)INT32_MIN) {
        return INT32_MIN;
    }
    return (int32_t)value;
}

static int16_t ge_audio_effects_clamp_s16_v6(int64_t value)
{
    if (value > (int64_t)INT16_MAX) {
        return INT16_MAX;
    }
    if (value < (int64_t)INT16_MIN) {
        return INT16_MIN;
    }
    return (int16_t)value;
}

static int32_t ge_audio_effects_q15_mul_v6(int32_t first, int32_t second)
{
    return ge_audio_effects_clamp_i32_v6(
        ((int64_t)first * (int64_t)second) >> 15);
}

static uint64_t ge_audio_effects_hash_byte_v6(uint64_t hash, uint8_t byte)
{
    hash ^= (uint64_t)byte;
    return hash * GE_AUDIO_EFFECTS_V6_HASH_PRIME;
}

static uint64_t ge_audio_effects_hash_u32_v6(uint64_t hash, uint32_t value)
{
    for (uint32_t shift = 0u; shift < 32u; shift += 8u) {
        hash = ge_audio_effects_hash_byte_v6(hash,
                                             (uint8_t)((value >> shift) & 0xffu));
    }
    return hash;
}

static uint64_t ge_audio_effects_hash_s16_v6(uint64_t hash, int16_t value)
{
    return ge_audio_effects_hash_u32_v6(hash, (uint32_t)(uint16_t)value & 0xffffu);
}

static uint32_t ge_audio_effects_q15_from_u8_v6(uint32_t value)
{
    if (value >= 127u) {
        return (uint32_t)GE_AUDIO_EFFECTS_V6_Q15_ONE;
    }
    return (value * 32768u + 63u) / 127u;
}

static int32_t ge_audio_effects_q15_clamp_v6(int32_t value)
{
    if (value < 0) {
        return 0;
    }
    if (value > GE_AUDIO_EFFECTS_V6_Q15_ONE) {
        return GE_AUDIO_EFFECTS_V6_Q15_ONE;
    }
    return value;
}

static GEStatusV1 ge_audio_reverb_config_validate_v6(
    const GEAudioReverbConfigV6 *config,
    GEAudioDiagnosticV5 *diagnostic)
{
    if (config == NULL ||
        !ge_audio_effects_header_valid_v6(&config->header,
                                          (uint32_t)sizeof(*config)) ||
        config->contract_version != GE_AUDIO_EFFECTS_V6_CONTRACT_VERSION ||
        config->record_version != GE_AUDIO_EFFECTS_V6_RECORD_VERSION ||
        config->sample_rate != GE_AUDIO_EFFECTS_V6_SAMPLE_RATE ||
        config->flags != 0u ||
        config->section_count == 0u ||
        config->section_count > GE_AUDIO_EFFECTS_V6_MAX_REVERB_SECTIONS ||
        config->reserved0 != 0u) {
        return ge_audio_effects_diagnostic_set_v6(
            diagnostic,
            GE_AUDIO_ENGINE_V5_DIAG_ARGUMENT,
            0u,
            config == NULL ? 0u : config->section_count,
            GE_AUDIO_EFFECTS_V6_MAX_REVERB_SECTIONS,
            "V6 reverb configuration does not match the fixed source bus contract",
            GE_STATUS_INVALID_ARGUMENT);
    }
    for (uint32_t section = 0u;
         section < GE_AUDIO_EFFECTS_V6_MAX_REVERB_SECTIONS;
         section++) {
        if (config->input_delay_frames[section] >
                GE_AUDIO_EFFECTS_V6_MAX_REVERB_DELAY_FRAMES ||
            config->output_delay_frames[section] >
                GE_AUDIO_EFFECTS_V6_MAX_REVERB_DELAY_FRAMES ||
            config->feedback_q15[section] < -32768 ||
            config->feedback_q15[section] > 32767 ||
            config->feedforward_q15[section] < -32768 ||
            config->feedforward_q15[section] > 32767 ||
            config->gain_q15[section] < -32768 ||
            config->gain_q15[section] > 32767) {
            return ge_audio_effects_diagnostic_set_v6(
                diagnostic,
                GE_AUDIO_ENGINE_V5_DIAG_ARGUMENT,
                0u,
                section,
                GE_AUDIO_EFFECTS_V6_MAX_REVERB_DELAY_FRAMES,
                "V6 reverb section exceeds its bounded fixed-point range",
                GE_STATUS_INVALID_ARGUMENT);
        }
    }
    if (config->damping_q15 > 32768u || config->wet_q15 > 32768u ||
        config->dry_q15 > 32768u || config->crossfeed_q15 > 32768u) {
        return ge_audio_effects_diagnostic_set_v6(
            diagnostic,
            GE_AUDIO_ENGINE_V5_DIAG_ARGUMENT,
            0u,
            config->damping_q15,
            config->wet_q15,
            "V6 reverb mix parameters exceed Q15 unity",
            GE_STATUS_INVALID_ARGUMENT);
    }
    return GE_STATUS_OK;
}

static GEStatusV1 ge_audio_reverb_bus_validate_v6(
    const GEAudioReverbBusV6 *bus,
    GEAudioDiagnosticV5 *diagnostic)
{
    if (bus == NULL ||
        !ge_audio_effects_header_valid_v6(&bus->header, (uint32_t)sizeof(*bus)) ||
        bus->contract_version != GE_AUDIO_EFFECTS_V6_CONTRACT_VERSION ||
        bus->record_version != GE_AUDIO_EFFECTS_V6_RECORD_VERSION ||
        bus->write_index >= GE_AUDIO_EFFECTS_V6_MAX_REVERB_DELAY_FRAMES) {
        return ge_audio_effects_diagnostic_set_v6(
            diagnostic,
            GE_AUDIO_ENGINE_V5_DIAG_ARGUMENT,
            0u,
            bus == NULL ? 0u : bus->write_index,
            GE_AUDIO_EFFECTS_V6_MAX_REVERB_DELAY_FRAMES,
            "V6 reverb bus state is not initialized",
            GE_STATUS_INVALID_STATE);
    }
    return ge_audio_reverb_config_validate_v6(&bus->config, diagnostic);
}

GEStatusV1 ge_audio_reverb_config_for_preset_v6(
    uint32_t preset,
    uint32_t sample_rate,
    GEAudioReverbConfigV6 *config,
    GEAudioDiagnosticV5 *diagnostic)
{
    ge_audio_effects_diagnostic_clear_v6(diagnostic);
    if (config == NULL || sample_rate != GE_AUDIO_EFFECTS_V6_SAMPLE_RATE ||
        (preset != GE_AUDIO_EFFECTS_V6_REVERB_PRESET_SMALL_ROOM &&
         preset != GE_AUDIO_EFFECTS_V6_REVERB_PRESET_BIG_ROOM)) {
        return ge_audio_effects_diagnostic_set_v6(
            diagnostic,
            GE_AUDIO_ENGINE_V5_DIAG_ARGUMENT,
            0u,
            preset,
            sample_rate,
            "V6 reverb preset requires the fixed 22,050 Hz source route",
            GE_STATUS_INVALID_ARGUMENT);
    }

    memset(config, 0, sizeof(*config));
    config->header.abi_version = GE_NATIVE_ABI_VERSION;
    config->header.struct_size = (uint32_t)sizeof(*config);
    config->contract_version = GE_AUDIO_EFFECTS_V6_CONTRACT_VERSION;
    config->record_version = GE_AUDIO_EFFECTS_V6_RECORD_VERSION;
    config->sample_rate = sample_rate;
    config->damping_q15 = 0x5000u;
    config->wet_q15 = 16384u;
    config->dry_q15 = 32768u;
    config->crossfeed_q15 = 8192u;

    /* These values mirror SMALLROOM_PARAMS/BIGROOM_PARAMS in libultra. */
    static const uint32_t small_input_ms[GE_AUDIO_EFFECTS_V6_SMALL_ROOM_SECTION_COUNT] = {
        0u, 19u, 0u
    };
    static const uint32_t small_output_ms[GE_AUDIO_EFFECTS_V6_SMALL_ROOM_SECTION_COUNT] = {
        54u, 38u, 60u
    };
    static const int32_t small_feedback[GE_AUDIO_EFFECTS_V6_SMALL_ROOM_SECTION_COUNT] = {
        9830, 3276, 5000
    };
    static const int32_t small_feedforward[GE_AUDIO_EFFECTS_V6_SMALL_ROOM_SECTION_COUNT] = {
        -9830, -3276, 0
    };
    static const int32_t small_gain[GE_AUDIO_EFFECTS_V6_SMALL_ROOM_SECTION_COUNT] = {
        0, 0x3fff, 0
    };
    static const uint32_t big_input_ms[GE_AUDIO_EFFECTS_V6_BIG_ROOM_SECTION_COUNT] = {
        0u, 22u, 66u, 0u
    };
    static const uint32_t big_output_ms[GE_AUDIO_EFFECTS_V6_BIG_ROOM_SECTION_COUNT] = {
        66u, 54u, 91u, 94u
    };
    static const int32_t big_feedback[GE_AUDIO_EFFECTS_V6_BIG_ROOM_SECTION_COUNT] = {
        9830, 3276, 3276, 8000
    };
    static const int32_t big_feedforward[GE_AUDIO_EFFECTS_V6_BIG_ROOM_SECTION_COUNT] = {
        -9830, -3276, -3276, 0
    };
    static const int32_t big_gain[GE_AUDIO_EFFECTS_V6_BIG_ROOM_SECTION_COUNT] = {
        0, 0x3fff, 0x3fff, 0
    };
    const uint32_t *input_ms = small_input_ms;
    const uint32_t *output_ms = small_output_ms;
    const int32_t *feedback = small_feedback;
    const int32_t *feedforward = small_feedforward;
    const int32_t *gain = small_gain;
    config->section_count = GE_AUDIO_EFFECTS_V6_SMALL_ROOM_SECTION_COUNT;
    if (preset == GE_AUDIO_EFFECTS_V6_REVERB_PRESET_BIG_ROOM) {
        input_ms = big_input_ms;
        output_ms = big_output_ms;
        feedback = big_feedback;
        feedforward = big_feedforward;
        gain = big_gain;
        config->section_count = GE_AUDIO_EFFECTS_V6_BIG_ROOM_SECTION_COUNT;
    }
    for (uint32_t section = 0u;
         section < config->section_count;
         section++) {
        config->input_delay_frames[section] =
            ge_audio_effects_ms_to_frames_v6(input_ms[section], sample_rate);
        config->output_delay_frames[section] =
            ge_audio_effects_ms_to_frames_v6(output_ms[section], sample_rate);
        config->feedback_q15[section] = feedback[section];
        config->feedforward_q15[section] = feedforward[section];
        config->gain_q15[section] = gain[section];
    }
    return ge_audio_reverb_config_validate_v6(config, diagnostic);
}

GEStatusV1 ge_audio_reverb_bus_reset_v6(GEAudioReverbBusV6 *bus,
                                        GEAudioDiagnosticV5 *diagnostic)
{
    ge_audio_effects_diagnostic_clear_v6(diagnostic);
    GEStatusV1 status = ge_audio_reverb_bus_validate_v6(bus, diagnostic);
    if (status != GE_STATUS_OK) {
        return status;
    }
    bus->write_index = 0u;
    bus->reserved0 = 0u;
    bus->frame_cursor = 0u;
    bus->input_hash = GE_AUDIO_EFFECTS_V6_HASH_OFFSET;
    bus->output_hash = GE_AUDIO_EFFECTS_V6_HASH_OFFSET;
    for (uint32_t section = 0u;
         section < GE_AUDIO_EFFECTS_V6_MAX_REVERB_SECTIONS;
         section++) {
        bus->damping_state_l[section] = 0;
        bus->damping_state_r[section] = 0;
        memset(bus->delay_l[section], 0, sizeof(bus->delay_l[section]));
        memset(bus->delay_r[section], 0, sizeof(bus->delay_r[section]));
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_audio_reverb_bus_init_v6(GEAudioReverbBusV6 *bus,
                                       const GEAudioReverbConfigV6 *config,
                                       GEAudioDiagnosticV5 *diagnostic)
{
    ge_audio_effects_diagnostic_clear_v6(diagnostic);
    GEStatusV1 status = ge_audio_reverb_config_validate_v6(config, diagnostic);
    if (status != GE_STATUS_OK || bus == NULL) {
        if (status == GE_STATUS_OK) {
            return ge_audio_effects_diagnostic_set_v6(
                diagnostic,
                GE_AUDIO_ENGINE_V5_DIAG_ARGUMENT,
                0u,
                0u,
                0u,
                "V6 reverb bus destination is null",
                GE_STATUS_INVALID_ARGUMENT);
        }
        return status;
    }
    memset(bus, 0, sizeof(*bus));
    bus->header.abi_version = GE_NATIVE_ABI_VERSION;
    bus->header.struct_size = (uint32_t)sizeof(*bus);
    bus->contract_version = GE_AUDIO_EFFECTS_V6_CONTRACT_VERSION;
    bus->record_version = GE_AUDIO_EFFECTS_V6_RECORD_VERSION;
    bus->config = *config;
    return ge_audio_reverb_bus_reset_v6(bus, diagnostic);
}

GEStatusV1 ge_audio_reverb_bus_process_v6(
    GEAudioReverbBusV6 *bus,
    const int16_t *stereo_input,
    uint32_t frame_count,
    int16_t *stereo_output,
    uint32_t stereo_sample_capacity,
    GEAudioReverbResultV6 *result,
    GEAudioDiagnosticV5 *diagnostic)
{
    ge_audio_effects_diagnostic_clear_v6(diagnostic);
    if (result == NULL) {
        return ge_audio_effects_diagnostic_set_v6(
            diagnostic,
            GE_AUDIO_ENGINE_V5_DIAG_ARGUMENT,
            0u,
            0u,
            0u,
            "V6 reverb result destination is null",
            GE_STATUS_INVALID_ARGUMENT);
    }
    memset(result, 0, sizeof(*result));
    result->header.abi_version = GE_NATIVE_ABI_VERSION;
    result->header.struct_size = (uint32_t)sizeof(*result);
    result->contract_version = GE_AUDIO_EFFECTS_V6_CONTRACT_VERSION;
    result->record_version = GE_AUDIO_EFFECTS_V6_RECORD_VERSION;
    result->frames_requested = frame_count;
    GEStatusV1 status = ge_audio_reverb_bus_validate_v6(bus, diagnostic);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (stereo_input == NULL || stereo_output == NULL || frame_count == 0u ||
        frame_count > GE_AUDIO_EFFECTS_V6_MAX_RENDER_FRAMES ||
        stereo_sample_capacity < 2u ||
        frame_count > stereo_sample_capacity / 2u) {
        return ge_audio_effects_diagnostic_set_v6(
            diagnostic,
            GE_AUDIO_ENGINE_V5_DIAG_ARGUMENT,
            0u,
            frame_count,
            stereo_sample_capacity,
            "V6 reverb PCM buffers do not satisfy the bounded stereo frame contract",
            GE_STATUS_INVALID_ARGUMENT);
    }
    result->first_frame = bus->frame_cursor;
    uint32_t write_index = bus->write_index;
    uint32_t peak_abs = 0u;
    uint32_t result_flags = 0u;
    for (uint32_t frame = 0u; frame < frame_count; frame++) {
        int32_t input_l = (int32_t)stereo_input[frame * 2u];
        int32_t input_r = (int32_t)stereo_input[frame * 2u + 1u];
        bus->input_hash = ge_audio_effects_hash_s16_v6(bus->input_hash,
                                                       (int16_t)input_l);
        bus->input_hash = ge_audio_effects_hash_s16_v6(bus->input_hash,
                                                       (int16_t)input_r);

        int32_t stage_l = ge_audio_effects_clamp_i32_v6(
            ((int64_t)input_l * 23170 + (int64_t)input_r * 11585) >> 15);
        int32_t stage_r = ge_audio_effects_clamp_i32_v6(
            ((int64_t)input_r * 23170 + (int64_t)input_l * 11585) >> 15);
        int32_t wet_l = 0;
        int32_t wet_r = 0;
        for (uint32_t section = 0u;
             section < bus->config.section_count;
             section++) {
            uint32_t input_delay = bus->config.input_delay_frames[section];
            uint32_t output_delay = bus->config.output_delay_frames[section];
            uint32_t input_read_index = input_delay == 0u ?
                write_index :
                (write_index + GE_AUDIO_EFFECTS_V6_MAX_REVERB_DELAY_FRAMES -
                 input_delay) % GE_AUDIO_EFFECTS_V6_MAX_REVERB_DELAY_FRAMES;
            uint32_t read_index = output_delay == 0u ?
                write_index :
                (write_index + GE_AUDIO_EFFECTS_V6_MAX_REVERB_DELAY_FRAMES -
                 output_delay) % GE_AUDIO_EFFECTS_V6_MAX_REVERB_DELAY_FRAMES;
            int32_t input_tap_l = input_delay == 0u ?
                stage_l : (int32_t)bus->delay_l[section][input_read_index];
            int32_t input_tap_r = input_delay == 0u ?
                stage_r : (int32_t)bus->delay_r[section][input_read_index];
            int32_t delayed_l = (int32_t)bus->delay_l[section][read_index];
            int32_t delayed_r = (int32_t)bus->delay_r[section][read_index];
            int32_t damping = (int32_t)bus->config.damping_q15;
            int32_t inverse_damping = GE_AUDIO_EFFECTS_V6_Q15_ONE - damping;
            int32_t filtered_l = ge_audio_effects_q15_mul_v6(
                bus->damping_state_l[section], damping) +
                ge_audio_effects_q15_mul_v6(delayed_l, inverse_damping);
            int32_t filtered_r = ge_audio_effects_q15_mul_v6(
                bus->damping_state_r[section], damping) +
                ge_audio_effects_q15_mul_v6(delayed_r, inverse_damping);
            bus->damping_state_l[section] = ge_audio_effects_clamp_i32_v6(filtered_l);
            bus->damping_state_r[section] = ge_audio_effects_clamp_i32_v6(filtered_r);
            int32_t mixed_l = ge_audio_effects_clamp_i32_v6(
                (int64_t)delayed_l + ge_audio_effects_q15_mul_v6(
                    input_tap_l, bus->config.feedforward_q15[section]));
            int32_t mixed_r = ge_audio_effects_clamp_i32_v6(
                (int64_t)delayed_r + ge_audio_effects_q15_mul_v6(
                    input_tap_r, bus->config.feedforward_q15[section]));
            int32_t stored_l = ge_audio_effects_clamp_i32_v6(
                (int64_t)stage_l + ge_audio_effects_q15_mul_v6(
                    filtered_l, bus->config.feedback_q15[section]));
            int32_t stored_r = ge_audio_effects_clamp_i32_v6(
                (int64_t)stage_r + ge_audio_effects_q15_mul_v6(
                    filtered_r, bus->config.feedback_q15[section]));
            bus->delay_l[section][write_index] =
                ge_audio_effects_clamp_s16_v6(stored_l);
            bus->delay_r[section][write_index] =
                ge_audio_effects_clamp_s16_v6(stored_r);
            wet_l = ge_audio_effects_clamp_i32_v6(
                (int64_t)wet_l + ge_audio_effects_q15_mul_v6(
                    mixed_l, bus->config.gain_q15[section]));
            wet_r = ge_audio_effects_clamp_i32_v6(
                (int64_t)wet_r + ge_audio_effects_q15_mul_v6(
                    mixed_r, bus->config.gain_q15[section]));
            stage_l = mixed_l;
            stage_r = mixed_r;
        }
        int32_t cross_l = ge_audio_effects_clamp_i32_v6(
            (int64_t)wet_l + ge_audio_effects_q15_mul_v6(
                wet_r, (int32_t)bus->config.crossfeed_q15));
        int32_t cross_r = ge_audio_effects_clamp_i32_v6(
            (int64_t)wet_r + ge_audio_effects_q15_mul_v6(
                wet_l, (int32_t)bus->config.crossfeed_q15));
        int32_t output_l = ge_audio_effects_q15_mul_v6(
            input_l, (int32_t)bus->config.dry_q15) +
            ge_audio_effects_q15_mul_v6(cross_l, (int32_t)bus->config.wet_q15);
        int32_t output_r = ge_audio_effects_q15_mul_v6(
            input_r, (int32_t)bus->config.dry_q15) +
            ge_audio_effects_q15_mul_v6(cross_r, (int32_t)bus->config.wet_q15);
        int16_t output_left = ge_audio_effects_clamp_s16_v6(output_l);
        int16_t output_right = ge_audio_effects_clamp_s16_v6(output_r);
        stereo_output[frame * 2u] = output_left;
        stereo_output[frame * 2u + 1u] = output_right;
        bus->output_hash = ge_audio_effects_hash_s16_v6(bus->output_hash,
                                                        output_left);
        bus->output_hash = ge_audio_effects_hash_s16_v6(bus->output_hash,
                                                        output_right);
        uint32_t abs_left = output_left < 0 ?
            (uint32_t)(-(int32_t)output_left) : (uint32_t)output_left;
        uint32_t abs_right = output_right < 0 ?
            (uint32_t)(-(int32_t)output_right) : (uint32_t)output_right;
        if (abs_left > peak_abs) {
            peak_abs = abs_left;
        }
        if (abs_right > peak_abs) {
            peak_abs = abs_right;
        }
        if (output_left != 0 || output_right != 0) {
            result_flags |= GE_AUDIO_EFFECTS_V6_RESULT_FLAG_NONZERO;
            if (input_l == 0 && input_r == 0) {
                result_flags |= GE_AUDIO_EFFECTS_V6_RESULT_FLAG_REVERB_TAIL;
            }
        }
        write_index++;
        if (write_index == GE_AUDIO_EFFECTS_V6_MAX_REVERB_DELAY_FRAMES) {
            write_index = 0u;
        }
    }
    bus->write_index = write_index;
    bus->frame_cursor = UINT64_MAX - bus->frame_cursor < (uint64_t)frame_count ?
        UINT64_MAX : bus->frame_cursor + (uint64_t)frame_count;
    result->frames_processed = frame_count;
    result->input_hash = bus->input_hash;
    result->output_hash = bus->output_hash;
    result->peak_abs = peak_abs;
    result->flags = result_flags;
    return GE_STATUS_OK;
}

static GEStatusV1 ge_audio_sfx_source_validate_v6(
    const GEAudioSfxSourceV6 *source,
    uint32_t expected_index,
    uint32_t sample_rate,
    uint32_t arena_sample_count,
    GEAudioDiagnosticV5 *diagnostic)
{
    if (source == NULL ||
        !ge_audio_effects_header_valid_v6(&source->header, (uint32_t)sizeof(*source)) ||
        source->contract_version != GE_AUDIO_EFFECTS_V6_CONTRACT_VERSION ||
        source->record_version != GE_AUDIO_EFFECTS_V6_RECORD_VERSION ||
        source->source_index != expected_index ||
        (source->flags & ~GE_AUDIO_EFFECTS_V6_SOURCE_FLAG_MASK) != 0u ||
        source->sample_rate != sample_rate ||
        source->sample_count == 0u ||
        source->sample_offset > arena_sample_count ||
        source->sample_count > arena_sample_count - source->sample_offset ||
        source->loop_start > source->sample_count ||
        source->loop_end > source->sample_count ||
        (source->loop_end != 0u && source->loop_end <= source->loop_start) ||
        source->volume_q15 > 32768u || source->pan_q15 > 32768u ||
        source->reserved0 != 0u) {
        return ge_audio_effects_diagnostic_set_v6(
            diagnostic,
            GE_AUDIO_ENGINE_V5_DIAG_ARGUMENT,
            0u,
            expected_index,
            arena_sample_count,
            "V6 SFX source metadata is outside the bounded sample arena",
            GE_STATUS_INVALID_ARGUMENT);
    }
    return GE_STATUS_OK;
}

static GEStatusV1 ge_audio_sfx_event_validate_v6(
    const GEAudioSfxEventV6 *event,
    uint32_t source_count,
    GEAudioDiagnosticV5 *diagnostic)
{
    if (event == NULL ||
        !ge_audio_effects_header_valid_v6(&event->header, (uint32_t)sizeof(*event)) ||
        event->contract_version != GE_AUDIO_EFFECTS_V6_CONTRACT_VERSION ||
        event->record_version != GE_AUDIO_EFFECTS_V6_RECORD_VERSION ||
        event->source_index >= source_count ||
        (event->flags & ~GE_AUDIO_EFFECTS_V6_EVENT_FLAG_MASK) != 0u ||
        event->gain_q15 > 32768u || event->pan_q15 > 32768u ||
        event->step_q16 == 0u || event->reserved0 != 0u ||
        event->reserved1 != 0u) {
        return ge_audio_effects_diagnostic_set_v6(
            diagnostic,
            GE_AUDIO_ENGINE_V5_DIAG_ARGUMENT,
            0u,
            event == NULL ? 0u : event->event_id,
            source_count,
            "V6 composite SFX event is outside the fixed graph contract",
            GE_STATUS_INVALID_ARGUMENT);
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_audio_sfx_graph_validate_v6(
    const GEAudioSfxGraphV6 *graph,
    const GEAudioSfxSourceV6 *sources,
    uint32_t source_count,
    uint32_t arena_sample_count,
    GEAudioDiagnosticV5 *diagnostic)
{
    ge_audio_effects_diagnostic_clear_v6(diagnostic);
    if (graph == NULL ||
        !ge_audio_effects_header_valid_v6(&graph->header, (uint32_t)sizeof(*graph)) ||
        graph->contract_version != GE_AUDIO_EFFECTS_V6_CONTRACT_VERSION ||
        graph->record_version != GE_AUDIO_EFFECTS_V6_RECORD_VERSION ||
        graph->sample_rate != GE_AUDIO_EFFECTS_V6_SAMPLE_RATE ||
        graph->flags != 0u ||
        graph->event_count > GE_AUDIO_EFFECTS_V6_MAX_GRAPH_EVENTS ||
        graph->source_count != source_count ||
        source_count > GE_AUDIO_EFFECTS_V6_MAX_GRAPH_SOURCES ||
        graph->reserved0 != 0u ||
        (source_count != 0u && sources == NULL)) {
        return ge_audio_effects_diagnostic_set_v6(
            diagnostic,
            GE_AUDIO_ENGINE_V5_DIAG_ARGUMENT,
            0u,
            graph == NULL ? 0u : graph->event_count,
            source_count,
            "V6 composite SFX graph header or source count is invalid",
            GE_STATUS_INVALID_ARGUMENT);
    }
    for (uint32_t source = 0u; source < source_count; source++) {
        GEStatusV1 status = ge_audio_sfx_source_validate_v6(&sources[source],
                                                            source,
                                                            graph->sample_rate,
                                                            arena_sample_count,
                                                            diagnostic);
        if (status != GE_STATUS_OK) {
            return status;
        }
    }
    for (uint32_t event = 0u; event < graph->event_count; event++) {
        GEStatusV1 status = ge_audio_sfx_event_validate_v6(&graph->events[event],
                                                           source_count,
                                                           diagnostic);
        if (status != GE_STATUS_OK) {
            return status;
        }
    }
    return GE_STATUS_OK;
}

void ge_audio_sfx_graph_init_v6(GEAudioSfxGraphV6 *graph, uint32_t sample_rate)
{
    if (graph == NULL) {
        return;
    }
    memset(graph, 0, sizeof(*graph));
    graph->header.abi_version = GE_NATIVE_ABI_VERSION;
    graph->header.struct_size = (uint32_t)sizeof(*graph);
    graph->contract_version = GE_AUDIO_EFFECTS_V6_CONTRACT_VERSION;
    graph->record_version = GE_AUDIO_EFFECTS_V6_RECORD_VERSION;
    graph->sample_rate = sample_rate == 0u ? GE_AUDIO_EFFECTS_V6_SAMPLE_RATE : sample_rate;
}

void ge_audio_sfx_source_init_v6(GEAudioSfxSourceV6 *source,
                                 uint32_t source_index,
                                 uint32_t sound_index)
{
    if (source == NULL) {
        return;
    }
    memset(source, 0, sizeof(*source));
    source->header.abi_version = GE_NATIVE_ABI_VERSION;
    source->header.struct_size = (uint32_t)sizeof(*source);
    source->contract_version = GE_AUDIO_EFFECTS_V6_CONTRACT_VERSION;
    source->record_version = GE_AUDIO_EFFECTS_V6_RECORD_VERSION;
    source->source_index = source_index;
    source->sound_index = sound_index;
    source->sample_rate = GE_AUDIO_EFFECTS_V6_SAMPLE_RATE;
    source->volume_q15 = 32768u;
    source->pan_q15 = 16384u;
}

void ge_audio_sfx_event_init_v6(GEAudioSfxEventV6 *event,
                                uint32_t event_id,
                                uint32_t source_index)
{
    if (event == NULL) {
        return;
    }
    memset(event, 0, sizeof(*event));
    event->header.abi_version = GE_NATIVE_ABI_VERSION;
    event->header.struct_size = (uint32_t)sizeof(*event);
    event->contract_version = GE_AUDIO_EFFECTS_V6_CONTRACT_VERSION;
    event->record_version = GE_AUDIO_EFFECTS_V6_RECORD_VERSION;
    event->event_id = event_id;
    event->source_index = source_index;
    event->gain_q15 = 32768u;
    event->pan_q15 = 16384u;
    event->step_q16 = GE_AUDIO_EFFECTS_V6_Q16_ONE;
}

GEStatusV1 ge_audio_sfx_graph_append_event_v6(
    GEAudioSfxGraphV6 *graph,
    GEAudioSfxEventV6 event,
    GEAudioDiagnosticV5 *diagnostic)
{
    ge_audio_effects_diagnostic_clear_v6(diagnostic);
    if (graph == NULL ||
        !ge_audio_effects_header_valid_v6(&graph->header, (uint32_t)sizeof(*graph)) ||
        graph->contract_version != GE_AUDIO_EFFECTS_V6_CONTRACT_VERSION ||
        graph->record_version != GE_AUDIO_EFFECTS_V6_RECORD_VERSION) {
        return ge_audio_effects_diagnostic_set_v6(
            diagnostic,
            GE_AUDIO_ENGINE_V5_DIAG_ARGUMENT,
            0u,
            0u,
            0u,
            "V6 composite SFX graph destination is not initialized",
            GE_STATUS_INVALID_STATE);
    }
    if (graph->event_count >= GE_AUDIO_EFFECTS_V6_MAX_GRAPH_EVENTS) {
        return ge_audio_effects_diagnostic_set_v6(
            diagnostic,
            GE_AUDIO_ENGINE_V5_DIAG_CAPACITY,
            0u,
            graph->event_count,
            GE_AUDIO_EFFECTS_V6_MAX_GRAPH_EVENTS,
            "V6 composite SFX graph reached its fixed event budget",
            GE_STATUS_REPLAY_BUDGET);
    }
    GEStatusV1 status = ge_audio_sfx_event_validate_v6(&event,
                                                       graph->source_count,
                                                       diagnostic);
    if (status != GE_STATUS_OK) {
        return status;
    }
    graph->events[graph->event_count] = event;
    graph->event_count++;
    return GE_STATUS_OK;
}

static uint64_t ge_audio_sfx_source_hash_v6(uint64_t hash,
                                            const GEAudioSfxSourceV6 *source)
{
    hash = ge_audio_effects_hash_u32_v6(hash, source->source_index);
    hash = ge_audio_effects_hash_u32_v6(hash, source->sound_index);
    hash = ge_audio_effects_hash_u32_v6(hash, source->flags);
    hash = ge_audio_effects_hash_u32_v6(hash, source->sample_offset);
    hash = ge_audio_effects_hash_u32_v6(hash, source->sample_count);
    hash = ge_audio_effects_hash_u32_v6(hash, source->loop_start);
    hash = ge_audio_effects_hash_u32_v6(hash, source->loop_end);
    hash = ge_audio_effects_hash_u32_v6(hash, source->loop_count);
    hash = ge_audio_effects_hash_u32_v6(hash, source->sample_rate);
    hash = ge_audio_effects_hash_u32_v6(hash, source->volume_q15);
    return ge_audio_effects_hash_u32_v6(hash, source->pan_q15);
}

static uint64_t ge_audio_sfx_event_hash_v6(uint64_t hash,
                                           const GEAudioSfxEventV6 *event)
{
    hash = ge_audio_effects_hash_u32_v6(hash, event->event_id);
    hash = ge_audio_effects_hash_u32_v6(hash, event->source_index);
    hash = ge_audio_effects_hash_u32_v6(hash, event->flags);
    hash = ge_audio_effects_hash_u32_v6(hash, event->start_frame);
    hash = ge_audio_effects_hash_u32_v6(hash, event->duration_frames);
    hash = ge_audio_effects_hash_u32_v6(hash, event->gain_q15);
    hash = ge_audio_effects_hash_u32_v6(hash, event->pan_q15);
    hash = ge_audio_effects_hash_u32_v6(hash, event->step_q16);
    hash = ge_audio_effects_hash_u32_v6(hash, event->attack_frames);
    hash = ge_audio_effects_hash_u32_v6(hash, event->release_frames);
    hash = ge_audio_effects_hash_u32_v6(hash, event->reserved0);
    return ge_audio_effects_hash_u32_v6(hash, event->reserved1);
}

static int ge_audio_sfx_event_sample_v6(const GEAudioSfxSourceV6 *source,
                                        const GEAudioSfxEventV6 *event,
                                        uint32_t age,
                                        const int16_t *arena,
                                        int32_t *sample)
{
    uint64_t position_q16 = (uint64_t)age * (uint64_t)event->step_q16;
    uint64_t position = position_q16 >> 16;
    if (position >= (uint64_t)source->sample_count) {
        if ((event->flags & GE_AUDIO_EFFECTS_V6_EVENT_FLAG_LOOP) == 0u ||
            source->loop_end <= source->loop_start ||
            source->loop_end > source->sample_count) {
            return 0;
        }
        uint64_t loop_length = (uint64_t)source->loop_end -
            (uint64_t)source->loop_start;
        uint64_t loop_position = position - (uint64_t)source->loop_start;
        uint64_t loop_number = loop_position / loop_length;
        if (source->loop_count != UINT32_MAX &&
            loop_number >= (uint64_t)source->loop_count) {
            return 0;
        }
        position = (uint64_t)source->loop_start + (loop_position % loop_length);
    }
    uint32_t source_index = (uint32_t)position;
    uint32_t next_index = source_index + 1u;
    if (next_index >= source->sample_count) {
        next_index = source_index;
    }
    if ((event->flags & GE_AUDIO_EFFECTS_V6_EVENT_FLAG_LOOP) != 0u &&
        source->loop_end > source->loop_start &&
        next_index >= source->loop_end) {
        next_index = source->loop_start;
    }
    int32_t first = (int32_t)arena[source->sample_offset + source_index];
    int32_t second = (int32_t)arena[source->sample_offset + next_index];
    uint32_t fraction = (uint32_t)(position_q16 & 0xffffu);
    *sample = first + (int32_t)(((int64_t)(second - first) * fraction) >> 16);
    return 1;
}

GEStatusV1 ge_audio_sfx_graph_render_v6(
    const GEAudioSfxGraphV6 *graph,
    const GEAudioSfxSourceV6 *sources,
    uint32_t source_count,
    const int16_t *mono_sample_arena,
    uint32_t arena_sample_count,
    uint32_t frame_count,
    int16_t *stereo_samples,
    uint32_t stereo_sample_capacity,
    GEAudioSfxGraphResultV6 *result,
    GEAudioDiagnosticV5 *diagnostic)
{
    ge_audio_effects_diagnostic_clear_v6(diagnostic);
    if (result == NULL) {
        return ge_audio_effects_diagnostic_set_v6(
            diagnostic,
            GE_AUDIO_ENGINE_V5_DIAG_ARGUMENT,
            0u,
            0u,
            0u,
            "V6 composite SFX result destination is null",
            GE_STATUS_INVALID_ARGUMENT);
    }
    memset(result, 0, sizeof(*result));
    result->header.abi_version = GE_NATIVE_ABI_VERSION;
    result->header.struct_size = (uint32_t)sizeof(*result);
    result->contract_version = GE_AUDIO_EFFECTS_V6_CONTRACT_VERSION;
    result->record_version = GE_AUDIO_EFFECTS_V6_RECORD_VERSION;
    result->frames_requested = frame_count;
    GEStatusV1 status = ge_audio_sfx_graph_validate_v6(graph,
                                                       sources,
                                                       source_count,
                                                       arena_sample_count,
                                                       diagnostic);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (mono_sample_arena == NULL || stereo_samples == NULL || frame_count == 0u ||
        frame_count > GE_AUDIO_EFFECTS_V6_MAX_RENDER_FRAMES ||
        stereo_sample_capacity < 2u ||
        frame_count > stereo_sample_capacity / 2u) {
        return ge_audio_effects_diagnostic_set_v6(
            diagnostic,
            GE_AUDIO_ENGINE_V5_DIAG_ARGUMENT,
            0u,
            frame_count,
            stereo_sample_capacity,
            "V6 composite SFX buffers do not satisfy the bounded stereo frame contract",
            GE_STATUS_INVALID_ARGUMENT);
    }
    memset(stereo_samples, 0, (size_t)frame_count * 2u * sizeof(int16_t));
    result->event_count = graph->event_count;
    result->event_hash = GE_AUDIO_EFFECTS_V6_HASH_OFFSET;
    for (uint32_t source = 0u; source < source_count; source++) {
        result->event_hash = ge_audio_sfx_source_hash_v6(result->event_hash,
                                                         &sources[source]);
    }
    for (uint32_t event = 0u; event < graph->event_count; event++) {
        result->event_hash = ge_audio_sfx_event_hash_v6(result->event_hash,
                                                        &graph->events[event]);
    }
    result->pcm_hash = GE_AUDIO_EFFECTS_V6_HASH_OFFSET;
    uint32_t max_active = 0u;
    uint32_t result_flags = 0u;
    for (uint32_t frame = 0u; frame < frame_count; frame++) {
        int64_t left = 0;
        int64_t right = 0;
        uint32_t active = 0u;
        for (uint32_t event_index = 0u;
             event_index < graph->event_count;
             event_index++) {
            const GEAudioSfxEventV6 *event = &graph->events[event_index];
            if (frame < event->start_frame) {
                continue;
            }
            uint32_t age = frame - event->start_frame;
            if (event->duration_frames != 0u && age >= event->duration_frames) {
                continue;
            }
            const GEAudioSfxSourceV6 *source = &sources[event->source_index];
            int32_t sample = 0;
            if (!ge_audio_sfx_event_sample_v6(source,
                                              event,
                                              age,
                                              mono_sample_arena,
                                              &sample)) {
                continue;
            }
            int32_t gain = (int32_t)event->gain_q15;
            gain = ge_audio_effects_q15_mul_v6(gain,
                                               (int32_t)source->volume_q15);
            if (event->attack_frames != 0u && age < event->attack_frames) {
                gain = ge_audio_effects_clamp_i32_v6(
                    ((int64_t)gain * (int64_t)age) /
                    (int64_t)event->attack_frames);
            }
            if (event->duration_frames != 0u && event->release_frames != 0u &&
                age >= event->duration_frames -
                    (event->release_frames < event->duration_frames ?
                     event->release_frames : event->duration_frames)) {
                uint32_t remaining = event->duration_frames - age;
                gain = ge_audio_effects_clamp_i32_v6(
                    ((int64_t)gain * (int64_t)remaining) /
                    (int64_t)event->release_frames);
            }
            if (gain == 0) {
                continue;
            }
            int32_t effective_pan = (int32_t)event->pan_q15 +
                (int32_t)source->pan_q15 - 16384;
            effective_pan = ge_audio_effects_q15_clamp_v6(effective_pan);
            int32_t scaled = ge_audio_effects_q15_mul_v6(sample, gain);
            left += ((int64_t)scaled *
                     (int64_t)(GE_AUDIO_EFFECTS_V6_Q15_ONE - effective_pan)) >> 15;
            right += ((int64_t)scaled * (int64_t)effective_pan) >> 15;
            active++;
        }
        int16_t output_left = ge_audio_effects_clamp_s16_v6(left);
        int16_t output_right = ge_audio_effects_clamp_s16_v6(right);
        stereo_samples[frame * 2u] = output_left;
        stereo_samples[frame * 2u + 1u] = output_right;
        result->pcm_hash = ge_audio_effects_hash_s16_v6(result->pcm_hash,
                                                        output_left);
        result->pcm_hash = ge_audio_effects_hash_s16_v6(result->pcm_hash,
                                                        output_right);
        if (active > max_active) {
            max_active = active;
        }
        if (output_left != 0 || output_right != 0) {
            result_flags |= GE_AUDIO_EFFECTS_V6_RESULT_FLAG_NONZERO;
        }
    }
    result->frames_rendered = frame_count;
    result->active_voice_count = max_active;
    result->flags = result_flags;
    return GE_STATUS_OK;
}

GEStatusV1 ge_audio_sfx_graph_render_bank_v6(
    const GEAudioSfxGraphV6 *graph,
    const GEAudioSfxSourceV6 *sources,
    uint32_t source_count,
    const uint8_t *ctl_bytes,
    uint32_t ctl_byte_count,
    const uint8_t *tbl_bytes,
    uint32_t tbl_byte_count,
    int16_t *decode_arena,
    uint32_t decode_arena_capacity,
    uint32_t frame_count,
    int16_t *stereo_samples,
    uint32_t stereo_sample_capacity,
    GEAudioSfxGraphResultV6 *result,
    GEAudioDiagnosticV5 *diagnostic)
{
    ge_audio_effects_diagnostic_clear_v6(diagnostic);
    if (graph == NULL || sources == NULL || source_count == 0u ||
        source_count > GE_AUDIO_EFFECTS_V6_MAX_GRAPH_SOURCES ||
        decode_arena == NULL || decode_arena_capacity == 0u) {
        return ge_audio_effects_diagnostic_set_v6(
            diagnostic,
            GE_AUDIO_ENGINE_V5_DIAG_ARGUMENT,
            0u,
            source_count,
            decode_arena_capacity,
            "V6 bank-backed SFX graph requires a bounded caller-owned decode arena",
            GE_STATUS_INVALID_ARGUMENT);
    }
    GEAudioBankV5 bank;
    GEStatusV1 status = ge_audio_bank_init_v5(ctl_bytes,
                                              ctl_byte_count,
                                              tbl_bytes,
                                              tbl_byte_count,
                                              &bank,
                                              diagnostic);
    if (status != GE_STATUS_OK) {
        return status;
    }
    GEAudioSfxSourceV6 decoded_sources[GE_AUDIO_EFFECTS_V6_MAX_GRAPH_SOURCES];
    uint32_t arena_offset = 0u;
    for (uint32_t source_index = 0u;
         source_index < source_count;
         source_index++) {
        decoded_sources[source_index] = sources[source_index];
        GEAudioWaveV5 wave;
        status = ge_audio_bank_lookup_sfx_v5(ctl_bytes,
                                             ctl_byte_count,
                                             &bank,
                                             sources[source_index].sound_index,
                                             &wave,
                                             diagnostic);
        if (status != GE_STATUS_OK) {
            return status;
        }
        if (arena_offset > decode_arena_capacity || wave.sample_count == 0u ||
            wave.sample_count > decode_arena_capacity - arena_offset) {
            return ge_audio_effects_diagnostic_set_v6(
                diagnostic,
                GE_AUDIO_ENGINE_V5_DIAG_CAPACITY,
                0u,
                wave.sample_count,
                decode_arena_capacity - arena_offset,
                "V6 bank-backed SFX graph decode arena is too small",
                GE_STATUS_REPLAY_BUDGET);
        }
        uint32_t decoded_count = 0u;
        status = ge_audio_decode_wave_v5(ctl_bytes,
                                         ctl_byte_count,
                                         tbl_bytes,
                                         tbl_byte_count,
                                         &wave,
                                         decode_arena + arena_offset,
                                         decode_arena_capacity - arena_offset,
                                         &decoded_count,
                                         diagnostic);
        if (status != GE_STATUS_OK) {
            return status;
        }
        decoded_sources[source_index].source_index = source_index;
        decoded_sources[source_index].flags = wave.type == GE_AUDIO_ENGINE_V5_WAVE_ADPCM ?
            GE_AUDIO_EFFECTS_V6_SOURCE_FLAG_ADPCM : GE_AUDIO_EFFECTS_V6_SOURCE_FLAG_RAW16;
        decoded_sources[source_index].sample_offset = arena_offset;
        decoded_sources[source_index].sample_count = decoded_count;
        decoded_sources[source_index].loop_start = wave.loop_start;
        decoded_sources[source_index].loop_end = wave.loop_end;
        decoded_sources[source_index].loop_count = wave.loop_count;
        decoded_sources[source_index].sample_rate = bank.sample_rate;
        decoded_sources[source_index].volume_q15 = ge_audio_effects_q15_from_u8_v6(
            wave.sample_volume);
        decoded_sources[source_index].pan_q15 =
            ge_audio_effects_q15_from_u8_v6(wave.sample_pan);
        decoded_sources[source_index].reserved0 = 0u;
        arena_offset += decoded_count;
    }
    return ge_audio_sfx_graph_render_v6(graph,
                                        decoded_sources,
                                        source_count,
                                        decode_arena,
                                        arena_offset,
                                        frame_count,
                                        stereo_samples,
                                        stereo_sample_capacity,
                                        result,
                                        diagnostic);
}

GEStatusV1 ge_audio_effects_feature_status_v6(uint32_t feature,
                                             GEAudioDiagnosticV5 *diagnostic)
{
    ge_audio_effects_diagnostic_clear_v6(diagnostic);
    switch (feature) {
    case GE_AUDIO_EFFECTS_V6_FEATURE_REVERB:
        if (diagnostic != NULL) {
            const char *message = "V6 owner-side source reverb bus enabled";
            size_t index = 0u;
            while (message[index] != '\0' && index + 1u < sizeof(diagnostic->message)) {
                diagnostic->message[index] = message[index];
                index++;
            }
            diagnostic->message[index] = '\0';
        }
        return GE_STATUS_OK;
    case GE_AUDIO_EFFECTS_V6_FEATURE_COMPOSITE_SFX:
        if (diagnostic != NULL) {
            const char *message = "V6 bounded composite SFX graph enabled";
            size_t index = 0u;
            while (message[index] != '\0' && index + 1u < sizeof(diagnostic->message)) {
                diagnostic->message[index] = message[index];
                index++;
            }
            diagnostic->message[index] = '\0';
        }
        return GE_STATUS_OK;
    default:
        return ge_audio_effects_diagnostic_set_v6(
            diagnostic,
            GE_AUDIO_ENGINE_V5_DIAG_UNSUPPORTED,
            GE_AUDIO_ENGINE_V5_DIAG_FLAG_RECOVERABLE,
            feature,
            0u,
            "V6 audio effect feature is outside the bounded implementation",
            GE_STATUS_UNSUPPORTED_COMMAND);
    }
}
