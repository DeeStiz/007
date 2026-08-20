#include "ge_audio_engine_v5.h"

#include <limits.h>
#include <math.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

/*
 * The source compact-sequence reader uses non-aligned big-endian fields and
 * temporarily reads from an earlier byte range for FE backup blocks.  This
 * implementation keeps the same observable stream behavior while making all
 * reads bounded and leaving the prepared bytes immutable.
 */

#define GE_AUDIO_ENGINE_V5_DEFAULT_TEMPO ((uint32_t)500000u)
#define GE_AUDIO_ENGINE_V5_HASH_OFFSET UINT64_C(1469598103934665603)
#define GE_AUDIO_ENGINE_V5_HASH_PRIME UINT64_C(1099511628211)
#define GE_AUDIO_ENGINE_V5_MAX_VARLEN_BYTES ((uint32_t)5u)
#define GE_AUDIO_ENGINE_V5_MAX_ADPCM_ORDER ((uint32_t)8u)
#define GE_AUDIO_ENGINE_V5_MAX_ADPCM_PREDICTORS ((uint32_t)16u)

static uint16_t ge_audio_be16(const uint8_t *bytes)
{
    return (uint16_t)(((uint16_t)bytes[0] << 8) | (uint16_t)bytes[1]);
}

static uint32_t ge_audio_be32(const uint8_t *bytes)
{
    return ((uint32_t)bytes[0] << 24) |
        ((uint32_t)bytes[1] << 16) |
        ((uint32_t)bytes[2] << 8) |
        (uint32_t)bytes[3];
}

static int ge_audio_range_valid(uint32_t offset,
                                uint32_t length,
                                uint32_t byte_count)
{
    return offset <= byte_count && length <= byte_count - offset;
}

static void ge_audio_diagnostic_clear(GEAudioDiagnosticV5 *diagnostic)
{
    if (diagnostic == NULL) {
        return;
    }
    memset(diagnostic, 0, sizeof(*diagnostic));
    diagnostic->version = GE_AUDIO_ENGINE_V5_VERSION;
}

static GEStatusV1 ge_audio_diagnostic_set(GEAudioDiagnosticV5 *diagnostic,
                                          uint32_t code,
                                          uint32_t flags,
                                          uint32_t track,
                                          uint32_t byte_offset,
                                          uint32_t opcode,
                                          uint32_t detail0,
                                          uint32_t detail1,
                                          const char *message,
                                          GEStatusV1 status)
{
    if (diagnostic != NULL) {
        size_t length = 0u;
        ge_audio_diagnostic_clear(diagnostic);
        diagnostic->code = code;
        diagnostic->flags = flags;
        diagnostic->track = track;
        diagnostic->byte_offset = byte_offset;
        diagnostic->opcode = opcode;
        diagnostic->detail0 = detail0;
        diagnostic->detail1 = detail1;
        if (message != NULL) {
            while (message[length] != '\0' && length + 1u < sizeof(diagnostic->message)) {
                diagnostic->message[length] = message[length];
                length++;
            }
            diagnostic->message[length] = '\0';
        }
    }
    return status;
}

static uint64_t ge_audio_hash_bytes_seed(uint64_t hash,
                                         const uint8_t *bytes,
                                         uint32_t byte_count)
{
    if (bytes == NULL && byte_count != 0u) {
        return 0u;
    }
    for (uint32_t index = 0u; index < byte_count; index++) {
        hash ^= (uint64_t)bytes[index];
        hash *= GE_AUDIO_ENGINE_V5_HASH_PRIME;
    }
    return hash;
}

static uint64_t ge_audio_hash_s16(uint64_t hash, int16_t sample)
{
    uint16_t value = (uint16_t)sample;
    hash ^= (uint64_t)(value & 0xffu);
    hash *= GE_AUDIO_ENGINE_V5_HASH_PRIME;
    hash ^= (uint64_t)((value >> 8) & 0xffu);
    hash *= GE_AUDIO_ENGINE_V5_HASH_PRIME;
    return hash;
}

static GEStatusV1 ge_cseq_read_byte(const uint8_t *bytes,
                                    uint32_t byte_count,
                                    GECSeqStateV5 *state,
                                    uint32_t track,
                                    uint8_t *value,
                                    uint32_t *read_budget,
                                    GEAudioDiagnosticV5 *diagnostic)
{
    if (bytes == NULL || state == NULL || value == NULL || read_budget == NULL ||
        track >= GE_AUDIO_ENGINE_V5_MAX_TRACKS) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_ARGUMENT,
                                       0u,
                                       track,
                                       0u,
                                       0u,
                                       0u,
                                       0u,
                                       "STUB(M13): invalid compact-sequence read argument",
                                       GE_STATUS_INVALID_ARGUMENT);
    }
    if (*read_budget == 0u) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_BLOCK,
                                       GE_AUDIO_ENGINE_V5_DIAG_FLAG_RECOVERABLE,
                                       track,
                                       state->cur_loc[track],
                                       0xfeu,
                                       GE_AUDIO_ENGINE_V5_MAX_READ_BYTES,
                                       0u,
                                       "compact-sequence backup expansion exceeds bounded read budget",
                                       GE_STATUS_MALFORMED_STREAM);
    }
    *read_budget -= 1u;

    if (state->backup_len[track] != 0u) {
        uint32_t offset = state->backup_loc[track];
        if (!ge_audio_range_valid(offset, 1u, byte_count)) {
            return ge_audio_diagnostic_set(diagnostic,
                                           GE_AUDIO_ENGINE_V5_DIAG_BLOCK,
                                           0u,
                                           track,
                                           offset,
                                           0xfeu,
                                           state->backup_len[track],
                                           0u,
                                           "compact-sequence backup pointer is outside the stream",
                                           GE_STATUS_MALFORMED_STREAM);
        }
        *value = bytes[offset];
        state->backup_loc[track] = offset + 1u;
        state->backup_len[track] = (uint8_t)(state->backup_len[track] - 1u);
        return GE_STATUS_OK;
    }

    uint32_t offset = state->cur_loc[track];
    if (!ge_audio_range_valid(offset, 1u, byte_count)) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_TRUNCATED,
                                       0u,
                                       track,
                                       offset,
                                       0u,
                                       1u,
                                       byte_count,
                                       "compact-sequence track read reaches the bounded stream end",
                                       GE_STATUS_MALFORMED_STREAM);
    }
    uint8_t first = bytes[offset];
    state->cur_loc[track] = offset + 1u;
    if (first != 0xfeu) {
        *value = first;
        return GE_STATUS_OK;
    }

    /* A doubled FE is an escaped literal FE in the source reader. */
    if (!ge_audio_range_valid(state->cur_loc[track], 1u, byte_count)) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_BLOCK,
                                       0u,
                                       track,
                                       offset,
                                       0xfeu,
                                       1u,
                                       0u,
                                       "compact-sequence FE block marker is truncated",
                                       GE_STATUS_MALFORMED_STREAM);
    }
    uint8_t high_or_escape = bytes[state->cur_loc[track]++];
    if (high_or_escape == 0xfeu) {
        *value = 0xfeu;
        return GE_STATUS_OK;
    }
    if (!ge_audio_range_valid(state->cur_loc[track], 2u, byte_count)) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_BLOCK,
                                       0u,
                                       track,
                                       offset,
                                       0xfeu,
                                       3u,
                                       0u,
                                       "compact-sequence FE backup header is truncated",
                                       GE_STATUS_MALFORMED_STREAM);
    }
    uint8_t low = bytes[state->cur_loc[track]++];
    uint8_t length = bytes[state->cur_loc[track]++];
    uint32_t backup = ((uint32_t)high_or_escape << 8) | (uint32_t)low;
    uint32_t after_header = state->cur_loc[track];
    if (length == 0u || backup > after_header ||
        after_header - backup < 4u) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_BLOCK,
                                       0u,
                                       track,
                                       offset,
                                       0xfeu,
                                       backup,
                                       length,
                                       "compact-sequence FE backup range is before the current track",
                                       GE_STATUS_MALFORMED_STREAM);
    }
    uint32_t begin = after_header - backup - 4u;
    if (!ge_audio_range_valid(begin, length, byte_count) || begin >= after_header) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_BLOCK,
                                       0u,
                                       track,
                                       offset,
                                       0xfeu,
                                       begin,
                                       length,
                                       "compact-sequence FE backup range is outside the stream",
                                       GE_STATUS_MALFORMED_STREAM);
    }
    state->backup_loc[track] = begin;
    state->backup_len[track] = length;
    *value = bytes[begin];
    state->backup_loc[track] = begin + 1u;
    state->backup_len[track] = (uint8_t)(length - 1u);
    return GE_STATUS_OK;
}

static GEStatusV1 ge_cseq_read_varlen(const uint8_t *bytes,
                                      uint32_t byte_count,
                                      GECSeqStateV5 *state,
                                      uint32_t track,
                                      uint32_t *value,
                                      uint32_t *read_budget,
                                      GEAudioDiagnosticV5 *diagnostic)
{
    if (value == NULL) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_ARGUMENT,
                                       0u,
                                       track,
                                       0u,
                                       0u,
                                       0u,
                                       0u,
                                       "compact-sequence varlen destination is null",
                                       GE_STATUS_INVALID_ARGUMENT);
    }
    uint32_t result = 0u;
    for (uint32_t count = 0u; count < GE_AUDIO_ENGINE_V5_MAX_VARLEN_BYTES; count++) {
        uint8_t byte = 0u;
        GEStatusV1 status = ge_cseq_read_byte(bytes,
                                              byte_count,
                                              state,
                                              track,
                                              &byte,
                                              read_budget,
                                              diagnostic);
        if (status != GE_STATUS_OK) {
            return status;
        }
        if (result > 0x1fffffffu) {
            return ge_audio_diagnostic_set(diagnostic,
                                           GE_AUDIO_ENGINE_V5_DIAG_VARLEN,
                                           0u,
                                           track,
                                           state->cur_loc[track],
                                           byte,
                                           result,
                                           count,
                                           "compact-sequence variable length value overflows bounded u32",
                                           GE_STATUS_MALFORMED_STREAM);
        }
        result = (result << 7) | (uint32_t)(byte & 0x7fu);
        if ((byte & 0x80u) == 0u) {
            *value = result;
            return GE_STATUS_OK;
        }
    }
    return ge_audio_diagnostic_set(diagnostic,
                                   GE_AUDIO_ENGINE_V5_DIAG_VARLEN,
                                   0u,
                                   track,
                                   state->cur_loc[track],
                                   0u,
                                   GE_AUDIO_ENGINE_V5_MAX_VARLEN_BYTES,
                                   0u,
                                   "compact-sequence variable length value exceeds five bytes",
                                   GE_STATUS_MALFORMED_STREAM);
}

static int ge_cseq_find_loop(GECSeqStateV5 *state,
                             uint32_t track,
                             uint32_t event_offset,
                             uint32_t jump_offset,
                             uint32_t *index)
{
    for (uint32_t loop = 0u; loop < GE_AUDIO_ENGINE_V5_MAX_LOOPS_PER_TRACK; loop++) {
        GECSeqLoopStateV5 *entry = &state->loops[track][loop];
        if (entry->initialized != 0u && entry->event_offset == event_offset) {
            if (index != NULL) {
                *index = loop;
            }
            return 1;
        }
    }
    if (index == NULL) {
        return 0;
    }
    for (uint32_t loop = 0u; loop < GE_AUDIO_ENGINE_V5_MAX_LOOPS_PER_TRACK; loop++) {
        GECSeqLoopStateV5 *entry = &state->loops[track][loop];
        if (entry->initialized == 0u) {
            entry->initialized = 1u;
            entry->event_offset = event_offset;
            entry->jump_offset = jump_offset;
            *index = loop;
            return 1;
        }
    }
    return 0;
}

static GEStatusV1 ge_cseq_validate_header(const uint8_t *bytes,
                                          uint32_t byte_count,
                                          GECSeqInfoV5 *info,
                                          GEAudioDiagnosticV5 *diagnostic)
{
    ge_audio_diagnostic_clear(diagnostic);
    if (bytes == NULL || info == NULL || byte_count < 68u) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_HEADER,
                                       0u,
                                       UINT32_MAX,
                                       0u,
                                       0u,
                                       byte_count,
                                       68u,
                                       "compact-sequence header is null or shorter than 16 offsets plus division",
                                       GE_STATUS_MALFORMED_STREAM);
    }
    if (byte_count > GE_AUDIO_ENGINE_V5_MAX_SEQUENCE_BYTES) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_CAPACITY,
                                       GE_AUDIO_ENGINE_V5_DIAG_FLAG_RECOVERABLE,
                                       UINT32_MAX,
                                       0u,
                                       0u,
                                       byte_count,
                                       GE_AUDIO_ENGINE_V5_MAX_SEQUENCE_BYTES,
                                       "compact-sequence byte count exceeds bounded native audio capacity",
                                       GE_STATUS_MALFORMED_STREAM);
    }
    uint32_t division = ge_audio_be32(bytes + 64u);
    if (division == 0u || division > 0xffffu) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_HEADER,
                                       0u,
                                       UINT32_MAX,
                                       64u,
                                       0u,
                                       division,
                                       0xffffu,
                                       "compact-sequence division is zero or outside the source u16 range",
                                       GE_STATUS_MALFORMED_STREAM);
    }
    memset(info, 0, sizeof(*info));
    info->version = GE_AUDIO_ENGINE_V5_VERSION;
    info->byte_count = byte_count;
    info->division = division;
    uint32_t first = UINT32_MAX;
    for (uint32_t track = 0u; track < GE_AUDIO_ENGINE_V5_MAX_TRACKS; track++) {
        uint32_t offset = ge_audio_be32(bytes + (track * 4u));
        if (offset == 0u) {
            continue;
        }
        if (offset < 68u || offset >= byte_count) {
            return ge_audio_diagnostic_set(diagnostic,
                                           GE_AUDIO_ENGINE_V5_DIAG_OFFSET,
                                           0u,
                                           track,
                                           track * 4u,
                                           0u,
                                           offset,
                                           byte_count,
                                           "compact-sequence track offset is outside the immutable sequence bytes",
                                           GE_STATUS_MALFORMED_STREAM);
        }
        info->valid_track_mask |= (uint32_t)1u << track;
        info->track_count++;
        if (offset < first) {
            first = offset;
        }
    }
    if (info->valid_track_mask == 0u) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_HEADER,
                                       0u,
                                       UINT32_MAX,
                                       0u,
                                       0u,
                                       0u,
                                       0u,
                                       "compact-sequence contains no valid tracks",
                                       GE_STATUS_MALFORMED_STREAM);
    }
    info->first_data_offset = first;
    return GE_STATUS_OK;
}

GEStatusV1 ge_cseq_validate_v5(const uint8_t *bytes,
                               uint32_t byte_count,
                               GECSeqInfoV5 *info,
                               GEAudioDiagnosticV5 *diagnostic)
{
    return ge_cseq_validate_header(bytes, byte_count, info, diagnostic);
}

GEStatusV1 ge_cseq_state_init_v5(const uint8_t *bytes,
                                 uint32_t byte_count,
                                 GECSeqStateV5 *state,
                                 GEAudioDiagnosticV5 *diagnostic)
{
    if (state == NULL) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_ARGUMENT,
                                       0u,
                                       UINT32_MAX,
                                       0u,
                                       0u,
                                       0u,
                                       0u,
                                       "compact-sequence state destination is null",
                                       GE_STATUS_INVALID_ARGUMENT);
    }
    GECSeqInfoV5 info;
    GEStatusV1 status = ge_cseq_validate_header(bytes, byte_count, &info, diagnostic);
    if (status != GE_STATUS_OK) {
        return status;
    }
    memset(state, 0, sizeof(*state));
    state->version = GE_AUDIO_ENGINE_V5_VERSION;
    state->byte_count = byte_count;
    state->division = info.division;
    state->valid_track_mask = info.valid_track_mask;
    state->delta_flag = 1u;
    for (uint32_t track = 0u; track < GE_AUDIO_ENGINE_V5_MAX_TRACKS; track++) {
        uint32_t offset = ge_audio_be32(bytes + track * 4u);
        if (offset == 0u) {
            continue;
        }
        state->cur_loc[track] = offset;
        uint32_t budget = GE_AUDIO_ENGINE_V5_MAX_READ_BYTES;
        status = ge_cseq_read_varlen(bytes,
                                     byte_count,
                                     state,
                                     track,
                                     &state->evt_delta_ticks[track],
                                     &budget,
                                     diagnostic);
        if (status != GE_STATUS_OK) {
            return status;
        }
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_cseq_next_event_v5(const uint8_t *bytes,
                                uint32_t byte_count,
                                GECSeqStateV5 *state,
                                GECSeqEventV5 *event,
                                GEAudioDiagnosticV5 *diagnostic)
{
    if (bytes == NULL || state == NULL || event == NULL ||
        state->byte_count != byte_count) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_ARGUMENT,
                                       0u,
                                       UINT32_MAX,
                                       0u,
                                       0u,
                                       byte_count,
                                       state == NULL ? 0u : state->byte_count,
                                       "compact-sequence next-event arguments do not describe one immutable stream",
                                       GE_STATUS_INVALID_ARGUMENT);
    }
    if (state->event_count >= GE_AUDIO_ENGINE_V5_MAX_EVENTS) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_EVENT_BUDGET,
                                       GE_AUDIO_ENGINE_V5_DIAG_FLAG_RECOVERABLE,
                                       UINT32_MAX,
                                       0u,
                                       0u,
                                       state->event_count,
                                       GE_AUDIO_ENGINE_V5_MAX_EVENTS,
                                       "compact-sequence event budget exhausted; likely unbounded source loop",
                                       GE_STATUS_MALFORMED_STREAM);
    }
    memset(event, 0, sizeof(*event));
    event->version = GE_AUDIO_ENGINE_V5_VERSION;
    if (state->valid_track_mask == 0u) {
        event->event_kind = GE_AUDIO_ENGINE_V5_EVENT_SEQUENCE_END;
        event->track = UINT32_MAX;
        event->absolute_ticks = state->last_ticks;
        return GE_STATUS_OK;
    }

    uint32_t first_time = UINT32_MAX;
    uint32_t first_track = UINT32_MAX;
    for (uint32_t track = 0u; track < GE_AUDIO_ENGINE_V5_MAX_TRACKS; track++) {
        if ((state->valid_track_mask & ((uint32_t)1u << track)) == 0u) {
            continue;
        }
        if (state->delta_flag != 0u) {
            if (state->evt_delta_ticks[track] < state->last_delta_ticks) {
                return ge_audio_diagnostic_set(diagnostic,
                                               GE_AUDIO_ENGINE_V5_DIAG_VARLEN,
                                               0u,
                                               track,
                                               state->cur_loc[track],
                                               0u,
                                               state->evt_delta_ticks[track],
                                               state->last_delta_ticks,
                                               "compact-sequence track delta underflows source merged timeline",
                                               GE_STATUS_MALFORMED_STREAM);
            }
            state->evt_delta_ticks[track] -= state->last_delta_ticks;
        }
        if (state->evt_delta_ticks[track] < first_time) {
            first_time = state->evt_delta_ticks[track];
            first_track = track;
        }
    }
    state->delta_flag = 1u;
    if (first_track == UINT32_MAX) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_HEADER,
                                       0u,
                                       UINT32_MAX,
                                       0u,
                                       0u,
                                       state->valid_track_mask,
                                       0u,
                                       "compact-sequence valid-track mask has no selectable track",
                                       GE_STATUS_MALFORMED_STREAM);
    }

    uint32_t event_offset = state->backup_len[first_track] != 0u ?
        state->backup_loc[first_track] : state->cur_loc[first_track];
    event->track = first_track;
    event->byte_offset = event_offset;
    event->delta_ticks = first_time;
    state->last_ticks += first_time;
    state->last_delta_ticks = first_time;
    event->absolute_ticks = state->last_ticks;
    state->current_track = first_track;
    state->current_byte_offset = event_offset;

    uint32_t budget = GE_AUDIO_ENGINE_V5_MAX_READ_BYTES;
    uint8_t status_byte = 0u;
    GEStatusV1 status = ge_cseq_read_byte(bytes,
                                          byte_count,
                                          state,
                                          first_track,
                                          &status_byte,
                                          &budget,
                                          diagnostic);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (status_byte == 0xffu) {
        uint8_t meta_type = 0u;
        status = ge_cseq_read_byte(bytes, byte_count, state, first_track,
                                   &meta_type, &budget, diagnostic);
        if (status != GE_STATUS_OK) {
            return status;
        }
        event->meta_type = meta_type;
        switch (meta_type) {
        case 0x51u: {
            uint8_t tempo[3];
            for (uint32_t index = 0u; index < 3u; index++) {
                status = ge_cseq_read_byte(bytes, byte_count, state, first_track,
                                           &tempo[index], &budget, diagnostic);
                if (status != GE_STATUS_OK) {
                    return status;
                }
            }
            event->event_kind = GE_AUDIO_ENGINE_V5_EVENT_TEMPO;
            event->tempo_microseconds = ((uint32_t)tempo[0] << 16) |
                ((uint32_t)tempo[1] << 8) | (uint32_t)tempo[2];
            if (event->tempo_microseconds == 0u) {
                return ge_audio_diagnostic_set(diagnostic,
                                               GE_AUDIO_ENGINE_V5_DIAG_META,
                                               0u,
                                               first_track,
                                               event_offset,
                                               status_byte,
                                               meta_type,
                                               0u,
                                               "compact-sequence tempo meta event has zero microseconds per quarter note",
                                               GE_STATUS_MALFORMED_STREAM);
            }
            state->last_status[first_track] = 0u;
            break;
        }
        case 0x2fu:
            state->valid_track_mask &= ~((uint32_t)1u << first_track);
            event->event_kind = state->valid_track_mask == 0u ?
                GE_AUDIO_ENGINE_V5_EVENT_SEQUENCE_END : GE_AUDIO_ENGINE_V5_EVENT_TRACK_END;
            state->last_status[first_track] = 0u;
            break;
        case 0x2eu: {
            uint8_t ignored = 0u;
            status = ge_cseq_read_byte(bytes, byte_count, state, first_track,
                                       &ignored, &budget, diagnostic);
            if (status != GE_STATUS_OK) {
                return status;
            }
            status = ge_cseq_read_byte(bytes, byte_count, state, first_track,
                                       &ignored, &budget, diagnostic);
            if (status != GE_STATUS_OK) {
                return status;
            }
            event->event_kind = GE_AUDIO_ENGINE_V5_EVENT_LOOP_START;
            state->last_status[first_track] = 0u;
            break;
        }
        case 0x2du: {
            uint8_t loop_count = 0u;
            uint8_t loop_current = 0u;
            uint8_t offset_bytes[4];
            status = ge_cseq_read_byte(bytes, byte_count, state, first_track,
                                       &loop_count, &budget, diagnostic);
            if (status != GE_STATUS_OK) {
                return status;
            }
            status = ge_cseq_read_byte(bytes, byte_count, state, first_track,
                                       &loop_current, &budget, diagnostic);
            if (status != GE_STATUS_OK) {
                return status;
            }
            for (uint32_t index = 0u; index < 4u; index++) {
                status = ge_cseq_read_byte(bytes, byte_count, state, first_track,
                                           &offset_bytes[index], &budget, diagnostic);
                if (status != GE_STATUS_OK) {
                    return status;
                }
            }
            uint32_t jump = ((uint32_t)offset_bytes[0] << 24) |
                ((uint32_t)offset_bytes[1] << 16) |
                ((uint32_t)offset_bytes[2] << 8) | (uint32_t)offset_bytes[3];
            uint32_t after_event = state->backup_len[first_track] != 0u ?
                state->backup_loc[first_track] : state->cur_loc[first_track];
            if (jump > after_event || after_event - jump < 68u) {
                return ge_audio_diagnostic_set(diagnostic,
                                               GE_AUDIO_ENGINE_V5_DIAG_LOOP,
                                               0u,
                                               first_track,
                                               event_offset,
                                               status_byte,
                                               jump,
                                               after_event,
                                               "compact-sequence loop jump exits the bounded track stream",
                                               GE_STATUS_MALFORMED_STREAM);
            }
            uint32_t loop_index = 0u;
            if (!ge_cseq_find_loop(state, first_track, event_offset, jump, &loop_index)) {
                return ge_audio_diagnostic_set(diagnostic,
                                               GE_AUDIO_ENGINE_V5_DIAG_LOOP,
                                               GE_AUDIO_ENGINE_V5_DIAG_FLAG_RECOVERABLE,
                                               first_track,
                                               event_offset,
                                               status_byte,
                                               GE_AUDIO_ENGINE_V5_MAX_LOOPS_PER_TRACK,
                                               0u,
                                               "compact-sequence loop table capacity exhausted",
                                               GE_STATUS_MALFORMED_STREAM);
            }
            GECSeqLoopStateV5 *loop = &state->loops[first_track][loop_index];
            if (loop->jump_offset != jump) {
                return ge_audio_diagnostic_set(diagnostic,
                                               GE_AUDIO_ENGINE_V5_DIAG_LOOP,
                                               0u,
                                               first_track,
                                               event_offset,
                                               status_byte,
                                               loop->jump_offset,
                                               jump,
                                               "compact-sequence loop event changes its jump target",
                                               GE_STATUS_MALFORMED_STREAM);
            }
            if (loop->initialized != 0u && loop->loop_count == 0u &&
                loop->current_count == 0u) {
                loop->loop_count = loop_count;
                loop->current_count = loop_current;
            } else if (loop->loop_count == 0u && loop->current_count == 0u) {
                loop->loop_count = loop_count;
                loop->current_count = loop_current;
            }
            uint8_t effective_current = loop->current_count;
            if (effective_current == 0u) {
                loop->current_count = loop->loop_count;
                state->cur_loc[first_track] = after_event;
                state->backup_len[first_track] = 0u;
            } else {
                if (effective_current != 0xffu) {
                    loop->current_count = (uint8_t)(effective_current - 1u);
                }
                state->cur_loc[first_track] = jump;
                state->backup_len[first_track] = 0u;
                state->backup_loc[first_track] = 0u;
            }
            event->event_kind = GE_AUDIO_ENGINE_V5_EVENT_LOOP_END;
            event->loop_count = loop->loop_count;
            event->loop_current = effective_current;
            event->loop_jump_offset = jump;
            state->last_status[first_track] = 0u;
            break;
        }
        default:
            return ge_audio_diagnostic_set(diagnostic,
                                           GE_AUDIO_ENGINE_V5_DIAG_META,
                                           0u,
                                           first_track,
                                           event_offset,
                                           status_byte,
                                           meta_type,
                                           0u,
                                           "compact-sequence meta opcode is outside the bounded source subset",
                                           GE_STATUS_UNSUPPORTED_COMMAND);
        }
    } else {
        uint8_t data1 = 0u;
        uint8_t data2 = 0u;
        uint8_t actual_status = status_byte;
        if ((status_byte & 0x80u) != 0u) {
            state->last_status[first_track] = status_byte;
            status = ge_cseq_read_byte(bytes, byte_count, state, first_track,
                                       &data1, &budget, diagnostic);
            if (status != GE_STATUS_OK) {
                return status;
            }
        } else {
            if (state->last_status[first_track] == 0u) {
                return ge_audio_diagnostic_set(diagnostic,
                                               GE_AUDIO_ENGINE_V5_DIAG_RUNNING_STATUS,
                                               0u,
                                               first_track,
                                               event_offset,
                                               status_byte,
                                               0u,
                                               0u,
                                               "compact-sequence data byte appears before a running MIDI status",
                                               GE_STATUS_MALFORMED_STREAM);
            }
            actual_status = state->last_status[first_track];
            data1 = status_byte;
        }
        uint8_t high = (uint8_t)(actual_status & 0xf0u);
        if (high >= 0xf0u || high == 0x00u) {
            return ge_audio_diagnostic_set(diagnostic,
                                           GE_AUDIO_ENGINE_V5_DIAG_UNSUPPORTED,
                                           GE_AUDIO_ENGINE_V5_DIAG_FLAG_STUB_M13,
                                           first_track,
                                           event_offset,
                                           actual_status,
                                           0u,
                                           0u,
                                           "STUB(M13): compact-sequence system MIDI event is not part of the bounded source subset",
                                           GE_STATUS_UNSUPPORTED_COMMAND);
        }
        if (high != 0xc0u && high != 0xd0u) {
            status = ge_cseq_read_byte(bytes, byte_count, state, first_track,
                                       &data2, &budget, diagnostic);
            if (status != GE_STATUS_OK) {
                return status;
            }
        }
        event->event_kind = GE_AUDIO_ENGINE_V5_EVENT_MIDI;
        event->status = actual_status;
        event->data1 = data1;
        event->data2 = data2;
        if (high == 0x90u) {
            status = ge_cseq_read_varlen(bytes, byte_count, state, first_track,
                                         &event->duration_ticks, &budget, diagnostic);
            if (status != GE_STATUS_OK) {
                return status;
            }
        }
    }

    if (event->event_kind == GE_AUDIO_ENGINE_V5_EVENT_MIDI ||
        event->event_kind == GE_AUDIO_ENGINE_V5_EVENT_TEMPO ||
        event->event_kind == GE_AUDIO_ENGINE_V5_EVENT_TRACK_END ||
        event->event_kind == GE_AUDIO_ENGINE_V5_EVENT_LOOP_START ||
        event->event_kind == GE_AUDIO_ENGINE_V5_EVENT_LOOP_END) {
        if (event->event_kind != GE_AUDIO_ENGINE_V5_EVENT_TRACK_END &&
            event->event_kind != GE_AUDIO_ENGINE_V5_EVENT_SEQUENCE_END) {
            uint32_t budget2 = GE_AUDIO_ENGINE_V5_MAX_READ_BYTES;
            uint32_t delta = 0u;
            status = ge_cseq_read_varlen(bytes, byte_count, state, first_track,
                                         &delta, &budget2, diagnostic);
            if (status != GE_STATUS_OK) {
                return status;
            }
            state->evt_delta_ticks[first_track] += delta;
        }
    }
    state->event_count++;
    return GE_STATUS_OK;
}

/* ------------------------------------------------------------------------- */
/* Source-rate event scheduler                                               */

uint64_t ge_audio_engine_sample_index_v5(uint64_t native_tick)
{
    return ge_audio_sample_index_for_tick_v5(native_tick);
}

uint32_t ge_audio_engine_frame_count_v5(uint64_t native_tick)
{
    return ge_audio_frame_count_for_tick_v5(native_tick);
}

static uint64_t ge_audio_scheduler_sample_delta(uint32_t ticks,
                                                uint32_t tempo_microseconds,
                                                uint32_t division,
                                                uint64_t *remainder)
{
    /*
     * The source converter is floor(ticks * sampleRate * tempo / (division *
     * 1e6)).  Keeping the numerator remainder between events avoids a drift
     * when a sequence contains many short deltas or tempo changes.
     */
    const uint64_t denominator = (uint64_t)division * UINT64_C(1000000);
    const uint64_t numerator_per_tick = (uint64_t)GE_AUDIO_V5_SAMPLE_RATE *
        (uint64_t)tempo_microseconds;
    if (division == 0u || tempo_microseconds == 0u || remainder == NULL) {
        return 0u;
    }
    if (ticks != 0u && numerator_per_tick > UINT64_MAX / ticks) {
        return UINT64_MAX;
    }
    uint64_t numerator = numerator_per_tick * (uint64_t)ticks;
    if (*remainder > UINT64_MAX - numerator) {
        return UINT64_MAX;
    }
    numerator += *remainder;
    *remainder = numerator % denominator;
    return numerator / denominator;
}

GEStatusV1 ge_audio_scheduler_init_v5(const uint8_t *bytes,
                                      uint32_t byte_count,
                                      GEAudioSchedulerV5 *scheduler,
                                      GEAudioDiagnosticV5 *diagnostic)
{
    if (scheduler == NULL) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_ARGUMENT,
                                       0u,
                                       UINT32_MAX,
                                       0u,
                                       0u,
                                       0u,
                                       0u,
                                       "audio scheduler destination is null",
                                       GE_STATUS_INVALID_ARGUMENT);
    }
    memset(scheduler, 0, sizeof(*scheduler));
    scheduler->version = GE_AUDIO_ENGINE_V5_VERSION;
    scheduler->tempo_microseconds = GE_AUDIO_ENGINE_V5_DEFAULT_TEMPO;
    GEStatusV1 status = ge_cseq_state_init_v5(bytes,
                                              byte_count,
                                              &scheduler->sequence,
                                              diagnostic);
    if (status != GE_STATUS_OK) {
        return status;
    }
    scheduler->division = scheduler->sequence.division;
    scheduler->sequence_active = 1u;
    scheduler->sample_cursor = 0u;
    scheduler->sample_remainder = 0u;
    return GE_STATUS_OK;
}

GEStatusV1 ge_audio_scheduler_next_event_v5(const uint8_t *bytes,
                                            uint32_t byte_count,
                                            GEAudioSchedulerV5 *scheduler,
                                            GECSeqEventV5 *event,
                                            uint64_t *sample_index,
                                            GEAudioDiagnosticV5 *diagnostic)
{
    if (scheduler == NULL || event == NULL || sample_index == NULL) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_ARGUMENT,
                                       0u,
                                       UINT32_MAX,
                                       0u,
                                       0u,
                                       0u,
                                       0u,
                                       "audio scheduler event destination is null",
                                       GE_STATUS_INVALID_ARGUMENT);
    }
    if (scheduler->sequence_active == 0u) {
        memset(event, 0, sizeof(*event));
        event->version = GE_AUDIO_ENGINE_V5_VERSION;
        event->event_kind = GE_AUDIO_ENGINE_V5_EVENT_SEQUENCE_END;
        *sample_index = scheduler->sample_cursor;
        return GE_STATUS_OK;
    }
    GEStatusV1 status = ge_cseq_next_event_v5(bytes,
                                              byte_count,
                                              &scheduler->sequence,
                                              event,
                                              diagnostic);
    if (status != GE_STATUS_OK) {
        return status;
    }
    uint64_t delta_samples = ge_audio_scheduler_sample_delta(event->delta_ticks,
                                                              scheduler->tempo_microseconds,
                                                              scheduler->division,
                                                              &scheduler->sample_remainder);
    if (delta_samples == UINT64_MAX ||
        scheduler->sample_cursor > UINT64_MAX - delta_samples) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_CAPACITY,
                                       0u,
                                       event->track,
                                       event->byte_offset,
                                       event->status,
                                       event->delta_ticks,
                                       scheduler->tempo_microseconds,
                                       "audio scheduler sample cursor overflowed the bounded source-rate clock",
                                       GE_STATUS_MALFORMED_STREAM);
    }
    scheduler->sample_cursor += delta_samples;
    scheduler->source_tick = event->absolute_ticks;
    scheduler->event_count++;
    *sample_index = scheduler->sample_cursor;
    if (event->event_kind == GE_AUDIO_ENGINE_V5_EVENT_TEMPO) {
        scheduler->tempo_microseconds = event->tempo_microseconds;
    } else if (event->event_kind == GE_AUDIO_ENGINE_V5_EVENT_SEQUENCE_END) {
        scheduler->sequence_active = 0u;
    }
    return GE_STATUS_OK;
}

/* ------------------------------------------------------------------------- */
/* AL bank and wave-table reader                                             */

static GEStatusV1 ge_audio_bank_diag(GEAudioDiagnosticV5 *diagnostic,
                                     uint32_t code,
                                     uint32_t offset,
                                     uint32_t detail0,
                                     uint32_t detail1,
                                     const char *message)
{
    return ge_audio_diagnostic_set(diagnostic,
                                   code,
                                   0u,
                                   UINT32_MAX,
                                   offset,
                                   0u,
                                   detail0,
                                   detail1,
                                   message,
                                   GE_STATUS_MALFORMED_STREAM);
}

static GEStatusV1 ge_audio_ctl_offset(const uint8_t *ctl_bytes,
                                      uint32_t ctl_byte_count,
                                      uint32_t offset,
                                      uint32_t length,
                                      GEAudioDiagnosticV5 *diagnostic)
{
    if (!ge_audio_range_valid(offset, length, ctl_byte_count)) {
        return ge_audio_bank_diag(diagnostic,
                                  GE_AUDIO_ENGINE_V5_DIAG_BANK,
                                  offset,
                                  length,
                                  ctl_byte_count,
                                  "AL control-bank pointer or record is outside the bounded control bytes");
    }
    (void)ctl_bytes;
    return GE_STATUS_OK;
}

GEStatusV1 ge_audio_bank_init_v5(const uint8_t *ctl_bytes,
                                 uint32_t ctl_byte_count,
                                 const uint8_t *tbl_bytes,
                                 uint32_t tbl_byte_count,
                                 GEAudioBankV5 *bank,
                                 GEAudioDiagnosticV5 *diagnostic)
{
    ge_audio_diagnostic_clear(diagnostic);
    if (ctl_bytes == NULL || tbl_bytes == NULL || bank == NULL ||
        ctl_byte_count > GE_AUDIO_ENGINE_V5_MAX_CTL_BYTES ||
        tbl_byte_count > GE_AUDIO_ENGINE_V5_MAX_TBL_BYTES) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_ARGUMENT,
                                       0u,
                                       UINT32_MAX,
                                       0u,
                                       0u,
                                       ctl_byte_count,
                                       tbl_byte_count,
                                       "AL bank input is null or exceeds the bounded native audio capacity",
                                       GE_STATUS_INVALID_ARGUMENT);
    }
    if (ctl_byte_count < 8u || tbl_byte_count == 0u ||
        ge_audio_be16(ctl_bytes) != 0x4231u) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_BANK,
                                       0u,
                                       UINT32_MAX,
                                       0u,
                                       0u,
                                       ctl_byte_count < 2u ? 0u : ge_audio_be16(ctl_bytes),
                                       0x4231u,
                                       "AL control bank revision is not the source B1 format",
                                       GE_STATUS_MALFORMED_STREAM);
    }
    uint32_t bank_count = ge_audio_be16(ctl_bytes + 2u);
    if (bank_count == 0u || bank_count > 16u || !ge_audio_range_valid(4u, bank_count * 4u, ctl_byte_count)) {
        return ge_audio_bank_diag(diagnostic,
                                  GE_AUDIO_ENGINE_V5_DIAG_BANK,
                                  2u,
                                  bank_count,
                                  16u,
                                  "AL control bank count is empty or outside the bounded pointer array");
    }
    uint32_t bank_offset = ge_audio_be32(ctl_bytes + 4u);
    if (bank_offset == 0u || ge_audio_ctl_offset(ctl_bytes, ctl_byte_count, bank_offset, 12u, diagnostic) != GE_STATUS_OK) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    uint32_t instrument_count = ge_audio_be16(ctl_bytes + bank_offset);
    uint32_t sample_rate = ge_audio_be32(ctl_bytes + bank_offset + 4u);
    if (instrument_count == 0u || instrument_count > GE_AUDIO_ENGINE_V5_MAX_INSTRUMENTS ||
        sample_rate == 0u || ge_audio_ctl_offset(ctl_bytes,
                                                  ctl_byte_count,
                                                  bank_offset + 12u,
                                                  instrument_count * 4u,
                                                  diagnostic) != GE_STATUS_OK) {
        return ge_audio_bank_diag(diagnostic,
                                  GE_AUDIO_ENGINE_V5_DIAG_BANK,
                                  bank_offset,
                                  instrument_count,
                                  sample_rate,
                                  "AL bank header or instrument pointer array is malformed");
    }
    memset(bank, 0, sizeof(*bank));
    bank->version = GE_AUDIO_ENGINE_V5_VERSION;
    bank->ctl_byte_count = ctl_byte_count;
    bank->tbl_byte_count = tbl_byte_count;
    bank->bank_offset = bank_offset;
    bank->instrument_count = instrument_count;
    bank->sample_rate = sample_rate;
    bank->percussion_offset = ge_audio_be32(ctl_bytes + bank_offset + 8u);
    return GE_STATUS_OK;
}

static int ge_audio_keymap_matches(const uint8_t *ctl_bytes,
                                   uint32_t keymap_offset,
                                   uint32_t key,
                                   uint32_t velocity)
{
    uint32_t velocity_min = ctl_bytes[keymap_offset];
    uint32_t velocity_max = ctl_bytes[keymap_offset + 1u];
    uint32_t key_min = ctl_bytes[keymap_offset + 2u];
    uint32_t key_max = ctl_bytes[keymap_offset + 3u];
    return velocity >= velocity_min && velocity <= velocity_max &&
        key >= key_min && key <= key_max;
}

GEStatusV1 ge_audio_bank_lookup_v5(const uint8_t *ctl_bytes,
                                   uint32_t ctl_byte_count,
                                   const GEAudioBankV5 *bank,
                                   uint32_t program,
                                   uint32_t key,
                                   uint32_t velocity,
                                   GEAudioWaveV5 *wave,
                                   GEAudioDiagnosticV5 *diagnostic)
{
    ge_audio_diagnostic_clear(diagnostic);
    if (ctl_bytes == NULL || bank == NULL || wave == NULL ||
        bank->version != GE_AUDIO_ENGINE_V5_VERSION ||
        bank->ctl_byte_count != ctl_byte_count || program > 127u ||
        key > 127u || velocity > 127u) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_ARGUMENT,
                                       0u,
                                       UINT32_MAX,
                                       0u,
                                       0u,
                                       program,
                                       key,
                                       "AL bank lookup arguments are outside the fixed source ranges",
                                       GE_STATUS_INVALID_ARGUMENT);
    }
    if (program >= bank->instrument_count) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_BANK,
                                       0u,
                                       UINT32_MAX,
                                       bank->bank_offset,
                                       0u,
                                       program,
                                       bank->instrument_count,
                                       "AL program is outside the guarded instrument bank",
                                       GE_STATUS_RESOURCE_NOT_FOUND);
    }
    uint32_t instrument_ptr_offset = bank->bank_offset + 12u + program * 4u;
    if (!ge_audio_range_valid(instrument_ptr_offset, 4u, ctl_byte_count)) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_BANK,
                                       0u,
                                       UINT32_MAX,
                                       instrument_ptr_offset,
                                       0u,
                                       program,
                                       4u,
                                       "AL program pointer is outside the control-bank bytes",
                                       GE_STATUS_MALFORMED_STREAM);
    }
    uint32_t instrument_offset = ge_audio_be32(ctl_bytes + instrument_ptr_offset);
    if (instrument_offset == 0u) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_BANK,
                                       0u,
                                       UINT32_MAX,
                                       instrument_ptr_offset,
                                       0u,
                                       program,
                                       0u,
                                       "AL program has no instrument in the guarded source bank",
                                       GE_STATUS_RESOURCE_NOT_FOUND);
    }
    if (!ge_audio_range_valid(instrument_offset, 16u, ctl_byte_count)) {
        return ge_audio_bank_diag(diagnostic,
                                  GE_AUDIO_ENGINE_V5_DIAG_BANK,
                                  instrument_offset,
                                  16u,
                                  ctl_byte_count,
                                  "AL instrument record is outside the control-bank bytes");
    }
    uint32_t sound_count = ge_audio_be16(ctl_bytes + instrument_offset + 14u);
    if (sound_count == 0u || sound_count > GE_AUDIO_ENGINE_V5_MAX_SOUNDS_PER_INSTRUMENT ||
        !ge_audio_range_valid(instrument_offset + 16u, sound_count * 4u, ctl_byte_count)) {
        return ge_audio_bank_diag(diagnostic,
                                  GE_AUDIO_ENGINE_V5_DIAG_BANK,
                                  instrument_offset + 14u,
                                  sound_count,
                                  GE_AUDIO_ENGINE_V5_MAX_SOUNDS_PER_INSTRUMENT,
                                  "AL instrument sound pointer array is malformed");
    }
    uint32_t fallback_sound = 0u;
    for (uint32_t sound_index = 0u; sound_index < sound_count; sound_index++) {
        uint32_t sound_ptr_offset = instrument_offset + 16u + sound_index * 4u;
        uint32_t sound_offset = ge_audio_be32(ctl_bytes + sound_ptr_offset);
        if (sound_offset == 0u || !ge_audio_range_valid(sound_offset, 16u, ctl_byte_count)) {
            continue;
        }
        uint32_t keymap_offset = ge_audio_be32(ctl_bytes + sound_offset + 4u);
        if (!ge_audio_range_valid(keymap_offset, 6u, ctl_byte_count)) {
            continue;
        }
        if (fallback_sound == 0u) {
            fallback_sound = sound_offset;
        }
        if (ge_audio_keymap_matches(ctl_bytes, keymap_offset, key, velocity)) {
            fallback_sound = sound_offset;
            break;
        }
    }
    if (fallback_sound == 0u) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_BANK,
                                       0u,
                                       UINT32_MAX,
                                       instrument_offset,
                                       0u,
                                       key,
                                       velocity,
                                       "AL instrument contains no usable sound for the requested key and velocity",
                                       GE_STATUS_RESOURCE_NOT_FOUND);
    }
    uint32_t wave_offset = ge_audio_be32(ctl_bytes + fallback_sound + 8u);
    if (!ge_audio_range_valid(wave_offset, 20u, ctl_byte_count)) {
        return ge_audio_bank_diag(diagnostic,
                                  GE_AUDIO_ENGINE_V5_DIAG_WAVE,
                                  wave_offset,
                                  20u,
                                  ctl_byte_count,
                                  "AL wavetable record is outside the control-bank bytes");
    }
    uint32_t wave_type = ctl_bytes[wave_offset + 8u];
    if (wave_type != GE_AUDIO_ENGINE_V5_WAVE_ADPCM && wave_type != GE_AUDIO_ENGINE_V5_WAVE_RAW16) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_WAVE,
                                       0u,
                                       UINT32_MAX,
                                       wave_offset + 8u,
                                       wave_type,
                                       wave_type,
                                       1u,
                                       "AL wavetable type is outside the bounded ADPCM/raw16 subset",
                                       GE_STATUS_UNSUPPORTED_COMMAND);
    }
    uint32_t table_offset = ge_audio_be32(ctl_bytes + wave_offset);
    uint32_t byte_length = ge_audio_be32(ctl_bytes + wave_offset + 4u);
    uint32_t keymap_offset = ge_audio_be32(ctl_bytes + fallback_sound + 4u);
    uint32_t envelope_offset = ge_audio_be32(ctl_bytes + fallback_sound);
    if (!ge_audio_range_valid(keymap_offset, 6u, ctl_byte_count) ||
        !ge_audio_range_valid(envelope_offset, 14u, ctl_byte_count) ||
        byte_length == 0u) {
        return ge_audio_bank_diag(diagnostic,
                                  GE_AUDIO_ENGINE_V5_DIAG_WAVE,
                                  wave_offset,
                                  keymap_offset,
                                  envelope_offset,
                                  "AL sound envelope/keymap/wavetable record is malformed");
    }
    memset(wave, 0, sizeof(*wave));
    wave->version = GE_AUDIO_ENGINE_V5_VERSION;
    wave->type = wave_type;
    wave->table_offset = table_offset;
    wave->byte_length = byte_length;
    wave->envelope_offset = envelope_offset;
    wave->keymap_offset = keymap_offset;
    wave->key_base = ctl_bytes[keymap_offset + 4u];
    wave->sample_pan = ctl_bytes[fallback_sound + 12u];
    wave->sample_volume = ctl_bytes[fallback_sound + 13u];
    wave->detune_cents = (int8_t)ctl_bytes[keymap_offset + 5u];
    if (wave_type == GE_AUDIO_ENGINE_V5_WAVE_RAW16) {
        wave->sample_count = byte_length / 2u;
        uint32_t loop_offset = ge_audio_be32(ctl_bytes + wave_offset + 12u);
        if (loop_offset != 0u && ge_audio_range_valid(loop_offset, 12u, ctl_byte_count)) {
            wave->loop_start = ge_audio_be32(ctl_bytes + loop_offset);
            wave->loop_end = ge_audio_be32(ctl_bytes + loop_offset + 4u);
            wave->loop_count = ge_audio_be32(ctl_bytes + loop_offset + 8u);
        }
    } else {
        wave->sample_count = (byte_length / 9u) * 16u;
        uint32_t loop_offset = ge_audio_be32(ctl_bytes + wave_offset + 12u);
        wave->book_offset = ge_audio_be32(ctl_bytes + wave_offset + 16u);
        if (loop_offset != 0u && ge_audio_range_valid(loop_offset, 52u, ctl_byte_count)) {
            wave->loop_start = ge_audio_be32(ctl_bytes + loop_offset);
            wave->loop_end = ge_audio_be32(ctl_bytes + loop_offset + 4u);
            wave->loop_count = ge_audio_be32(ctl_bytes + loop_offset + 8u);
        }
        if (!ge_audio_range_valid(wave->book_offset, 8u, ctl_byte_count)) {
            return ge_audio_bank_diag(diagnostic,
                                      GE_AUDIO_ENGINE_V5_DIAG_BOOK,
                                      wave->book_offset,
                                      8u,
                                      ctl_byte_count,
                                      "AL ADPCM book pointer is outside the control-bank bytes");
        }
        wave->book_order = ge_audio_be32(ctl_bytes + wave->book_offset);
        wave->book_predictors = ge_audio_be32(ctl_bytes + wave->book_offset + 4u);
        if (wave->book_order == 0u || wave->book_order > GE_AUDIO_ENGINE_V5_MAX_ADPCM_ORDER ||
            wave->book_predictors == 0u || wave->book_predictors > GE_AUDIO_ENGINE_V5_MAX_ADPCM_PREDICTORS) {
            return ge_audio_bank_diag(diagnostic,
                                      GE_AUDIO_ENGINE_V5_DIAG_BOOK,
                                      wave->book_offset,
                                      wave->book_order,
                                      wave->book_predictors,
                                      "AL ADPCM book dimensions exceed the bounded source subset");
        }
        uint64_t coefficient_bytes = (uint64_t)wave->book_order *
            (uint64_t)wave->book_predictors * 8u * 2u;
        if (coefficient_bytes > UINT32_MAX ||
            !ge_audio_range_valid(wave->book_offset + 8u,
                                  (uint32_t)coefficient_bytes,
                                  ctl_byte_count)) {
            return ge_audio_bank_diag(diagnostic,
                                      GE_AUDIO_ENGINE_V5_DIAG_BOOK,
                                      wave->book_offset + 8u,
                                      (uint32_t)coefficient_bytes,
                                      ctl_byte_count,
                                      "AL ADPCM coefficient book is truncated");
        }
    }
    if (wave->sample_count == 0u) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_WAVE,
                                       0u,
                                       UINT32_MAX,
                                       wave_offset,
                                       wave_type,
                                       byte_length,
                                       0u,
                                       "AL wavetable has no complete source samples",
                                       GE_STATUS_MALFORMED_STREAM);
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_audio_bank_lookup_sfx_v5(const uint8_t *ctl_bytes,
                                       uint32_t ctl_byte_count,
                                       const GEAudioBankV5 *bank,
                                       uint32_t sound_index,
                                       GEAudioWaveV5 *wave,
                                       GEAudioDiagnosticV5 *diagnostic)
{
    ge_audio_diagnostic_clear(diagnostic);
    if (ctl_bytes == NULL || bank == NULL || wave == NULL ||
        bank->version != GE_AUDIO_ENGINE_V5_VERSION ||
        bank->ctl_byte_count != ctl_byte_count) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_ARGUMENT,
                                       0u,
                                       UINT32_MAX,
                                       0u,
                                       0u,
                                       sound_index,
                                       0u,
                                       "SFX bank lookup arguments are outside the fixed native contract",
                                       GE_STATUS_INVALID_ARGUMENT);
    }
    if (bank->instrument_count == 0u ||
        !ge_audio_range_valid(bank->bank_offset + 12u, 4u, ctl_byte_count)) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_BANK,
                                       0u,
                                       UINT32_MAX,
                                       bank->bank_offset,
                                       0u,
                                       bank->instrument_count,
                                       0u,
                                       "SFX bank has no bounded program zero instrument",
                                       GE_STATUS_RESOURCE_NOT_FOUND);
    }
    uint32_t instrument_offset = ge_audio_be32(ctl_bytes + bank->bank_offset + 12u);
    if (!ge_audio_range_valid(instrument_offset, 16u, ctl_byte_count)) {
        return ge_audio_bank_diag(diagnostic,
                                  GE_AUDIO_ENGINE_V5_DIAG_BANK,
                                  instrument_offset,
                                  16u,
                                  ctl_byte_count,
                                  "SFX instrument record is outside the control-bank bytes");
    }
    uint32_t sound_count = ge_audio_be16(ctl_bytes + instrument_offset + 14u);
    if (sound_index >= sound_count || sound_count > GE_AUDIO_ENGINE_V5_MAX_SOUNDS_PER_INSTRUMENT ||
        !ge_audio_range_valid(instrument_offset + 16u, sound_count * 4u, ctl_byte_count)) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_BANK,
                                       0u,
                                       UINT32_MAX,
                                       instrument_offset + 14u,
                                       0u,
                                       0u,
                                       sound_index,
                                       "SFX sound index is outside the guarded source sound array",
                                       GE_STATUS_RESOURCE_NOT_FOUND);
    }
    uint32_t sound_offset = ge_audio_be32(ctl_bytes + instrument_offset + 16u + sound_index * 4u);
    if (!ge_audio_range_valid(sound_offset, 16u, ctl_byte_count)) {
        return ge_audio_bank_diag(diagnostic,
                                  GE_AUDIO_ENGINE_V5_DIAG_BANK,
                                  sound_offset,
                                  16u,
                                  ctl_byte_count,
                                  "SFX sound record is outside the control-bank bytes");
    }
    uint32_t envelope_offset = ge_audio_be32(ctl_bytes + sound_offset);
    uint32_t keymap_offset = ge_audio_be32(ctl_bytes + sound_offset + 4u);
    uint32_t wave_offset = ge_audio_be32(ctl_bytes + sound_offset + 8u);
    if (!ge_audio_range_valid(envelope_offset, 14u, ctl_byte_count) ||
        !ge_audio_range_valid(keymap_offset, 6u, ctl_byte_count) ||
        !ge_audio_range_valid(wave_offset, 20u, ctl_byte_count)) {
        return ge_audio_bank_diag(diagnostic,
                                  GE_AUDIO_ENGINE_V5_DIAG_WAVE,
                                  wave_offset,
                                  envelope_offset,
                                  keymap_offset,
                                  "SFX sound envelope/keymap/wavetable graph is malformed");
    }
    uint32_t wave_type = ctl_bytes[wave_offset + 8u];
    uint32_t table_offset = ge_audio_be32(ctl_bytes + wave_offset);
    uint32_t byte_length = ge_audio_be32(ctl_bytes + wave_offset + 4u);
    if (wave_type != GE_AUDIO_ENGINE_V5_WAVE_ADPCM && wave_type != GE_AUDIO_ENGINE_V5_WAVE_RAW16) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_WAVE,
                                       GE_AUDIO_ENGINE_V5_DIAG_FLAG_STUB_M13,
                                       UINT32_MAX,
                                       wave_offset + 8u,
                                       wave_type,
                                       wave_type,
                                       1u,
                                       "STUB(M13): SFX wavetable format is outside ADPCM/raw16",
                                       GE_STATUS_UNSUPPORTED_COMMAND);
    }
    memset(wave, 0, sizeof(*wave));
    wave->version = GE_AUDIO_ENGINE_V5_VERSION;
    wave->type = wave_type;
    wave->table_offset = table_offset;
    wave->byte_length = byte_length;
    wave->envelope_offset = envelope_offset;
    wave->keymap_offset = keymap_offset;
    wave->key_base = ctl_bytes[keymap_offset + 4u];
    wave->sample_pan = ctl_bytes[sound_offset + 12u];
    wave->sample_volume = ctl_bytes[sound_offset + 13u];
    wave->detune_cents = (int8_t)ctl_bytes[keymap_offset + 5u];
    if (wave_type == GE_AUDIO_ENGINE_V5_WAVE_RAW16) {
        wave->sample_count = byte_length / 2u;
        uint32_t loop_offset = ge_audio_be32(ctl_bytes + wave_offset + 12u);
        if (loop_offset != 0u && ge_audio_range_valid(loop_offset, 12u, ctl_byte_count)) {
            wave->loop_start = ge_audio_be32(ctl_bytes + loop_offset);
            wave->loop_end = ge_audio_be32(ctl_bytes + loop_offset + 4u);
            wave->loop_count = ge_audio_be32(ctl_bytes + loop_offset + 8u);
        }
    } else {
        wave->sample_count = (byte_length / 9u) * 16u;
        wave->book_offset = ge_audio_be32(ctl_bytes + wave_offset + 16u);
        uint32_t loop_offset = ge_audio_be32(ctl_bytes + wave_offset + 12u);
        if (loop_offset != 0u && ge_audio_range_valid(loop_offset, 52u, ctl_byte_count)) {
            wave->loop_start = ge_audio_be32(ctl_bytes + loop_offset);
            wave->loop_end = ge_audio_be32(ctl_bytes + loop_offset + 4u);
            wave->loop_count = ge_audio_be32(ctl_bytes + loop_offset + 8u);
        }
        if (!ge_audio_range_valid(wave->book_offset, 8u, ctl_byte_count)) {
            return ge_audio_bank_diag(diagnostic,
                                      GE_AUDIO_ENGINE_V5_DIAG_BOOK,
                                      wave->book_offset,
                                      8u,
                                      ctl_byte_count,
                                      "SFX ADPCM book pointer is outside the control-bank bytes");
        }
        wave->book_order = ge_audio_be32(ctl_bytes + wave->book_offset);
        wave->book_predictors = ge_audio_be32(ctl_bytes + wave->book_offset + 4u);
        uint64_t coefficient_bytes = (uint64_t)wave->book_order *
            (uint64_t)wave->book_predictors * 8u * 2u;
        if (wave->book_order == 0u || wave->book_order > GE_AUDIO_ENGINE_V5_MAX_ADPCM_ORDER ||
            wave->book_predictors == 0u || wave->book_predictors > GE_AUDIO_ENGINE_V5_MAX_ADPCM_PREDICTORS ||
            coefficient_bytes > UINT32_MAX ||
            !ge_audio_range_valid(wave->book_offset + 8u,
                                  (uint32_t)coefficient_bytes,
                                  ctl_byte_count)) {
            return ge_audio_bank_diag(diagnostic,
                                      GE_AUDIO_ENGINE_V5_DIAG_BOOK,
                                      wave->book_offset,
                                      wave->book_order,
                                      wave->book_predictors,
                                      "SFX ADPCM book dimensions or coefficients are malformed");
        }
    }
    if (wave->sample_count == 0u) {
        return ge_audio_bank_diag(diagnostic,
                                  GE_AUDIO_ENGINE_V5_DIAG_WAVE,
                                  wave_offset,
                                  byte_length,
                                  0u,
                                  "SFX wavetable has no complete samples");
    }
    return GE_STATUS_OK;
}

static int16_t ge_audio_clamp_s16(int64_t value)
{
    if (value > INT16_MAX) {
        return INT16_MAX;
    }
    if (value < INT16_MIN) {
        return INT16_MIN;
    }
    return (int16_t)value;
}

GEStatusV1 ge_audio_decode_wave_v5(const uint8_t *ctl_bytes,
                                   uint32_t ctl_byte_count,
                                   const uint8_t *tbl_bytes,
                                   uint32_t tbl_byte_count,
                                   const GEAudioWaveV5 *wave,
                                   int16_t *samples,
                                   uint32_t sample_capacity,
                                   uint32_t *sample_count,
                                   GEAudioDiagnosticV5 *diagnostic)
{
    ge_audio_diagnostic_clear(diagnostic);
    if (ctl_bytes == NULL || tbl_bytes == NULL || wave == NULL || samples == NULL ||
        sample_count == NULL || wave->version != GE_AUDIO_ENGINE_V5_VERSION ||
        ctl_byte_count == 0u || tbl_byte_count == 0u) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_ARGUMENT,
                                       0u,
                                       UINT32_MAX,
                                       0u,
                                       0u,
                                       0u,
                                       0u,
                                       "AL wave decode arguments are null or carry no guarded bytes",
                                       GE_STATUS_INVALID_ARGUMENT);
    }
    if (wave->sample_count == 0u || wave->sample_count > GE_AUDIO_ENGINE_V5_MAX_WAVE_SAMPLES ||
        wave->sample_count > sample_capacity ||
        !ge_audio_range_valid(wave->table_offset, wave->byte_length, tbl_byte_count)) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_WAVE,
                                       0u,
                                       UINT32_MAX,
                                       wave->table_offset,
                                       wave->type,
                                       wave->byte_length,
                                       tbl_byte_count,
                                       "AL wave data is outside the table or exceeds the bounded decode buffer",
                                       GE_STATUS_MALFORMED_STREAM);
    }
    if (wave->type == GE_AUDIO_ENGINE_V5_WAVE_RAW16) {
        if ((wave->byte_length & 1u) != 0u || wave->sample_count != wave->byte_length / 2u) {
            return ge_audio_diagnostic_set(diagnostic,
                                           GE_AUDIO_ENGINE_V5_DIAG_WAVE,
                                           0u,
                                           UINT32_MAX,
                                           wave->table_offset,
                                           wave->type,
                                           wave->byte_length,
                                           2u,
                                           "raw16 wavetable length is not an integral number of big-endian samples",
                                           GE_STATUS_MALFORMED_STREAM);
        }
        for (uint32_t index = 0u; index < wave->sample_count; index++) {
            samples[index] = (int16_t)ge_audio_be16(tbl_bytes + wave->table_offset + index * 2u);
        }
        *sample_count = wave->sample_count;
        return GE_STATUS_OK;
    }
    if (wave->type != GE_AUDIO_ENGINE_V5_WAVE_ADPCM ||
        wave->byte_length < 9u ||
        wave->book_order == 0u || wave->book_predictors == 0u ||
        wave->book_order > GE_AUDIO_ENGINE_V5_MAX_ADPCM_ORDER ||
        wave->book_predictors > GE_AUDIO_ENGINE_V5_MAX_ADPCM_PREDICTORS) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_WAVE,
                                       0u,
                                       UINT32_MAX,
                                       wave->table_offset,
                                       wave->type,
                                       wave->byte_length,
                                       wave->book_order,
                                       "ADPCM wavetable is shorter than one complete source 9-byte frame",
                                       GE_STATUS_MALFORMED_STREAM);
    }
    uint64_t coefficient_bytes = (uint64_t)wave->book_order *
        (uint64_t)wave->book_predictors * 8u * 2u;
    if (coefficient_bytes > UINT32_MAX ||
        !ge_audio_range_valid(wave->book_offset + 8u,
                              (uint32_t)coefficient_bytes,
                              ctl_byte_count)) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_BOOK,
                                       0u,
                                       UINT32_MAX,
                                       wave->book_offset,
                                       0u,
                                       (uint32_t)coefficient_bytes,
                                       ctl_byte_count,
                                       "ADPCM coefficient book is not fully available to the decoder",
                                       GE_STATUS_MALFORMED_STREAM);
    }
    uint32_t frame_count = wave->byte_length / 9u;
    if (frame_count > UINT32_MAX / 16u || frame_count * 16u != wave->sample_count) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_WAVE,
                                       0u,
                                       UINT32_MAX,
                                       wave->table_offset,
                                       0u,
                                       frame_count,
                                       wave->sample_count,
                                       "ADPCM wavetable sample count does not match its complete frame count",
                                       GE_STATUS_MALFORMED_STREAM);
    }

    int32_t history[16];
    memset(history, 0, sizeof(history));
    for (uint32_t frame = 0u; frame < frame_count; frame++) {
        uint32_t frame_offset = wave->table_offset + frame * 9u;
        uint8_t frame_header = tbl_bytes[frame_offset];
        /* N64 compact ADPCM stores the four-bit shift in the high nibble and
           the predictor index in the low nibble. */
        uint32_t scale = (uint32_t)(frame_header >> 4);
        uint32_t predictor = (uint32_t)(frame_header & 0x0fu);
        if (predictor >= wave->book_predictors) {
            return ge_audio_diagnostic_set(diagnostic,
                                           GE_AUDIO_ENGINE_V5_DIAG_BOOK,
                                           0u,
                                           UINT32_MAX,
                                           frame_offset,
                                           frame_header,
                                           predictor,
                                           wave->book_predictors,
                                           "ADPCM frame selects a predictor outside its source book",
                                           GE_STATUS_MALFORMED_STREAM);
        }
        for (uint32_t sample_in_frame = 0u; sample_in_frame < 16u; sample_in_frame++) {
            uint8_t packed = tbl_bytes[frame_offset + 1u + sample_in_frame / 2u];
            uint32_t nibble = (sample_in_frame & 1u) == 0u ?
                (uint32_t)(packed >> 4) : (uint32_t)(packed & 0x0fu);
            int32_t signed_nibble = nibble < 8u ? (int32_t)nibble : (int32_t)nibble - 16;
            int64_t accum = (int64_t)signed_nibble * (INT64_C(1) << scale) * INT64_C(2048);
            for (uint32_t tap = 0u; tap < wave->book_order; tap++) {
                uint32_t coefficient_index = predictor * wave->book_order * 8u +
                    tap * 8u + sample_in_frame;
                uint32_t coefficient_offset = wave->book_offset + 8u +
                    coefficient_index * 2u;
                int16_t coefficient = (int16_t)ge_audio_be16(ctl_bytes + coefficient_offset);
                uint32_t history_index = 15u - tap;
                accum += (int64_t)coefficient * (int64_t)history[history_index];
            }
            int64_t decoded = accum >> 11;
            int16_t sample = ge_audio_clamp_s16(decoded);
            uint32_t output_index = frame * 16u + sample_in_frame;
            samples[output_index] = sample;
            for (uint32_t history_index = 0u; history_index < 15u; history_index++) {
                history[history_index] = history[history_index + 1u];
            }
            history[15] = sample;
        }
    }
    *sample_count = wave->sample_count;
    return GE_STATUS_OK;
}

GEStatusV1 ge_audio_feature_status_v5(uint32_t feature,
                                      GEAudioDiagnosticV5 *diagnostic)
{
    switch (feature) {
    case GE_AUDIO_ENGINE_V5_STUB_FEATURE_REVERB:
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_UNSUPPORTED,
                                       GE_AUDIO_ENGINE_V5_DIAG_FLAG_STUB_M13,
                                       UINT32_MAX,
                                       0u,
                                       0u,
                                       feature,
                                       0u,
                                       "STUB(M13): source reverb bus is not yet lowered by the native mixer",
                                       GE_STATUS_UNSUPPORTED_COMMAND);
    case GE_AUDIO_ENGINE_V5_STUB_FEATURE_COMPOSITE_SFX:
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_UNSUPPORTED,
                                       GE_AUDIO_ENGINE_V5_DIAG_FLAG_STUB_M13,
                                       UINT32_MAX,
                                       0u,
                                       0u,
                                       feature,
                                       0u,
                                       "STUB(M13): composite Rareware SFX event graph is not yet lowered by the native mixer",
                                       GE_STATUS_UNSUPPORTED_COMMAND);
    default:
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_UNSUPPORTED,
                                       GE_AUDIO_ENGINE_V5_DIAG_FLAG_RECOVERABLE,
                                       UINT32_MAX,
                                       0u,
                                       0u,
                                       feature,
                                       0u,
                                       "audio feature is outside the bounded native implementation",
                                       GE_STATUS_UNSUPPORTED_COMMAND);
    }
}

/* ------------------------------------------------------------------------- */
/* Deterministic native subset renderer                                      */

static uint32_t ge_audio_frames_from_microseconds(uint32_t microseconds,
                                                  uint32_t sample_rate)
{
    if (microseconds == 0u || sample_rate == 0u) {
        return 0u;
    }
    uint64_t numerator = (uint64_t)microseconds * (uint64_t)sample_rate;
    uint64_t frames = (numerator + UINT64_C(999999)) / UINT64_C(1000000);
    return frames > UINT32_MAX ? UINT32_MAX : (uint32_t)frames;
}

static int32_t ge_audio_q16_from_u8(uint32_t value)
{
    if (value >= 127u) {
        return 65536;
    }
    return (int32_t)((value * 65536u + 63u) / 127u);
}

static int32_t ge_audio_q16_mul(int32_t first, int32_t second)
{
    int64_t value = (int64_t)first * (int64_t)second;
    if (value > INT32_MAX * INT64_C(65536)) {
        return INT32_MAX;
    }
    if (value < INT32_MIN * INT64_C(65536)) {
        return INT32_MIN;
    }
    return (int32_t)(value >> 16);
}

static uint32_t ge_audio_pitch_step_q16(uint32_t note,
                                        const GEAudioWaveV5 *wave,
                                        uint32_t source_rate,
                                        uint32_t output_rate)
{
    int32_t cents = ((int32_t)note - (int32_t)wave->key_base) * 100 + wave->detune_cents;
    double ratio = pow(2.0, (double)cents / 1200.0);
    double step = ratio * (double)source_rate / (double)output_rate * 65536.0;
    if (step < 1.0) {
        return 1u;
    }
    if (step > 4294967295.0) {
        return UINT32_MAX;
    }
    return (uint32_t)(step + 0.5);
}

static GEAudioVoiceV5 *ge_audio_find_voice(GEAudioSynthV5 *synth,
                                           uint32_t channel,
                                           uint32_t note)
{
    for (uint32_t index = 0u; index < GE_AUDIO_V5_MAX_VOICES; index++) {
        GEAudioVoiceV5 *voice = &synth->voices[index];
        if (voice->active != 0u && voice->channel == channel && voice->note == note) {
            return voice;
        }
    }
    return NULL;
}

static GEAudioVoiceV5 *ge_audio_allocate_voice(GEAudioSynthV5 *synth)
{
    GEAudioVoiceV5 *oldest = &synth->voices[0];
    for (uint32_t index = 0u; index < GE_AUDIO_V5_MAX_VOICES; index++) {
        GEAudioVoiceV5 *voice = &synth->voices[index];
        if (voice->active == 0u) {
            return voice;
        }
        if (voice->age > oldest->age) {
            oldest = voice;
        }
    }
    synth->dropped_voice_count++;
    return oldest;
}

void ge_audio_synth_init_v5(GEAudioSynthV5 *synth, uint32_t sample_rate)
{
    if (synth == NULL) {
        return;
    }
    memset(synth, 0, sizeof(*synth));
    synth->version = GE_AUDIO_ENGINE_V5_VERSION;
    synth->sample_rate = sample_rate == 0u ? GE_AUDIO_V5_SAMPLE_RATE : sample_rate;
    synth->pcm_hash = GE_AUDIO_ENGINE_V5_HASH_OFFSET;
    synth->event_hash = GE_AUDIO_ENGINE_V5_HASH_OFFSET;
    for (uint32_t channel = 0u; channel < 16u; channel++) {
        synth->channel_volume[channel] = 127u;
        synth->channel_pan[channel] = 64u;
        synth->channel_pitch_bend[channel] = 8192u;
    }
    for (uint32_t index = 0u; index < GE_AUDIO_V5_MAX_VOICES; index++) {
        synth->voices[index].age = UINT32_MAX;
    }
}

static void ge_audio_stop_voice(GEAudioSynthV5 *synth,
                                uint32_t channel,
                                uint32_t note,
                                uint32_t release_frame)
{
    GEAudioVoiceV5 *voice = ge_audio_find_voice(synth, channel, note);
    if (voice == NULL) {
        return;
    }
    voice->release_requested = 1u;
    voice->release_frame = release_frame;
}

static GEStatusV1 ge_audio_start_voice(const uint8_t *ctl_bytes,
                                       uint32_t ctl_byte_count,
                                       const uint8_t *tbl_bytes,
                                       uint32_t tbl_byte_count,
                                       const GEAudioBankV5 *bank,
                                       GEAudioSynthV5 *synth,
                                       uint32_t channel,
                                       uint32_t note,
                                       uint32_t velocity,
                                       uint32_t frame,
                                       GEAudioDiagnosticV5 *diagnostic)
{
    uint32_t program = synth->channel_program[channel];
    GEAudioWaveV5 wave;
    GEStatusV1 status = ge_audio_bank_lookup_v5(ctl_bytes,
                                                ctl_byte_count,
                                                bank,
                                                program,
                                                note,
                                                velocity,
                                                &wave,
                                                diagnostic);
    if (status != GE_STATUS_OK) {
        return status;
    }
    GEAudioVoiceV5 *voice = ge_audio_allocate_voice(synth);
    uint32_t decoded_count = 0u;
    status = ge_audio_decode_wave_v5(ctl_bytes,
                                     ctl_byte_count,
                                     tbl_bytes,
                                     tbl_byte_count,
                                     &wave,
                                     voice->samples,
                                     GE_AUDIO_ENGINE_V5_MAX_WAVE_SAMPLES,
                                     &decoded_count,
                                     diagnostic);
    if (status != GE_STATUS_OK) {
        return status;
    }
    uint32_t envelope = wave.envelope_offset;
    uint32_t attack_us = ge_audio_be32(ctl_bytes + envelope);
    uint32_t decay_us = ge_audio_be32(ctl_bytes + envelope + 4u);
    uint32_t release_us = ge_audio_be32(ctl_bytes + envelope + 8u);
    uint32_t attack_frames = ge_audio_frames_from_microseconds(attack_us, synth->sample_rate);
    uint32_t decay_frames = ge_audio_frames_from_microseconds(decay_us, synth->sample_rate);
    uint32_t release_frames = ge_audio_frames_from_microseconds(release_us, synth->sample_rate);
    memset(voice, 0, offsetof(GEAudioVoiceV5, samples));
    voice->active = 1u;
    voice->channel = channel;
    voice->program = program;
    voice->note = note;
    voice->velocity = velocity;
    voice->sample_count = decoded_count;
    voice->sample_step_q16 = ge_audio_pitch_step_q16(note,
                                                     &wave,
                                                     bank->sample_rate,
                                                     synth->sample_rate);
    voice->loop_start = wave.loop_start;
    voice->loop_end = wave.loop_end > wave.loop_start && wave.loop_end <= decoded_count ?
        wave.loop_end : 0u;
    voice->loop_count = wave.loop_count;
    voice->age = frame;
    voice->attack_frames = attack_frames;
    voice->decay_frames = decay_frames;
    voice->release_frames = release_frames;
    voice->gain_q16 = 0;
    int32_t channel_pan = (int32_t)synth->channel_pan[channel] * 65536 / 127;
    int32_t sample_pan = (int32_t)wave.sample_pan * 65536 / 127;
    voice->pan_q16 = (channel_pan + sample_pan) / 2;
    int32_t source_gain = ge_audio_q16_from_u8(wave.sample_volume);
    int32_t attack_gain = ge_audio_q16_from_u8(ctl_bytes[envelope + 12u]);
    int32_t sustain_gain = ge_audio_q16_from_u8(ctl_bytes[envelope + 13u]);
    voice->attack_gain_q16 = ge_audio_q16_mul(source_gain, attack_gain);
    voice->sustain_gain_q16 = ge_audio_q16_mul(source_gain, sustain_gain);
    voice->gain_q16 = attack_frames == 0u ? voice->sustain_gain_q16 : 0;
    /* Source envelope values are stored immediately after release time. */
    voice->lifetime_frames = 0u;
    return GE_STATUS_OK;
}

static int32_t ge_audio_voice_envelope_gain(const GEAudioVoiceV5 *voice)
{
    uint32_t lifetime = voice->lifetime_frames;
    int32_t gain = voice->sustain_gain_q16;
    if (voice->attack_frames != 0u && lifetime < voice->attack_frames) {
        gain = (int32_t)(((int64_t)voice->attack_gain_q16 * lifetime) /
                         (int64_t)voice->attack_frames);
    } else if (voice->decay_frames != 0u &&
               lifetime < voice->attack_frames + voice->decay_frames) {
        uint32_t elapsed = lifetime - voice->attack_frames;
        int64_t difference = (int64_t)voice->sustain_gain_q16 -
            (int64_t)voice->attack_gain_q16;
        gain = voice->attack_gain_q16 +
            (int32_t)((difference * elapsed) / (int64_t)voice->decay_frames);
    }
    if (voice->release_requested != 0u) {
        if (voice->release_frames == 0u || lifetime >= voice->release_frame + voice->release_frames) {
            return 0;
        }
        if (lifetime >= voice->release_frame) {
            uint32_t elapsed = lifetime - voice->release_frame;
            uint32_t remaining = voice->release_frames - elapsed;
            gain = (int32_t)(((int64_t)gain * remaining) /
                             (int64_t)voice->release_frames);
        }
    }
    return gain < 0 ? 0 : gain;
}

static int ge_audio_voice_advance_sample(GEAudioVoiceV5 *voice)
{
    if (voice->sample_count == 0u) {
        voice->active = 0u;
        return 0;
    }
    uint32_t position = voice->sample_position_q16 >> 16;
    while (position >= voice->sample_count) {
        if (voice->loop_end > voice->loop_start && voice->loop_end <= voice->sample_count &&
            (voice->loop_count == UINT32_MAX || voice->loop_count != 0u)) {
            uint32_t overshoot = position - voice->loop_end;
            position = voice->loop_start + overshoot;
            voice->sample_position_q16 = (position << 16) |
                (voice->sample_position_q16 & 0xffffu);
            if (voice->loop_count != UINT32_MAX) {
                voice->loop_count -= 1u;
            }
        } else {
            voice->active = 0u;
            return 0;
        }
    }
    voice->sample_position_q16 += voice->sample_step_q16;
    voice->lifetime_frames += 1u;
    return 1;
}

static void ge_audio_synth_mix_frame(GEAudioSynthV5 *synth,
                                     int16_t *stereo_samples,
                                     uint32_t frame,
                                     uint32_t output_rate)
{
    int64_t left = 0;
    int64_t right = 0;
    uint32_t active = 0u;
    for (uint32_t index = 0u; index < GE_AUDIO_V5_MAX_VOICES; index++) {
        GEAudioVoiceV5 *voice = &synth->voices[index];
        if (voice->active == 0u) {
            continue;
        }
        int32_t envelope_gain = ge_audio_voice_envelope_gain(voice);
        if (envelope_gain == 0 && voice->release_requested != 0u &&
            voice->lifetime_frames >= voice->release_frame + voice->release_frames) {
            voice->active = 0u;
            continue;
        }
        uint32_t source_index = voice->sample_position_q16 >> 16;
        uint32_t fraction = voice->sample_position_q16 & 0xffffu;
        if (source_index >= voice->sample_count) {
            if (!ge_audio_voice_advance_sample(voice)) {
                continue;
            }
            source_index = voice->sample_position_q16 >> 16;
            fraction = voice->sample_position_q16 & 0xffffu;
            if (source_index >= voice->sample_count) {
                continue;
            }
        }
        uint32_t next_index = source_index + 1u;
        if (next_index >= voice->sample_count) {
            next_index = source_index;
        }
        int32_t first = voice->samples[source_index];
        int32_t second = voice->samples[next_index];
        int32_t sample = first + (int32_t)(((int64_t)(second - first) * fraction) >> 16);
        int32_t velocity_gain = ge_audio_q16_from_u8(voice->velocity);
        int32_t channel_gain = ge_audio_q16_from_u8(synth->channel_volume[voice->channel]);
        int32_t gain = ge_audio_q16_mul(envelope_gain, velocity_gain);
        gain = ge_audio_q16_mul(gain, channel_gain);
        int32_t scaled = (int32_t)(((int64_t)sample * gain) >> 16);
        int32_t pan = voice->pan_q16;
        if (pan < 0) {
            pan = 0;
        }
        if (pan > 65536) {
            pan = 65536;
        }
        left += ((int64_t)scaled * (65536 - pan)) >> 16;
        right += ((int64_t)scaled * pan) >> 16;
        active++;
        (void)output_rate;
        (void)ge_audio_voice_advance_sample(voice);
    }
    if (left > INT16_MAX) {
        left = INT16_MAX;
    } else if (left < INT16_MIN) {
        left = INT16_MIN;
    }
    if (right > INT16_MAX) {
        right = INT16_MAX;
    } else if (right < INT16_MIN) {
        right = INT16_MIN;
    }
    stereo_samples[frame * 2u] = (int16_t)left;
    stereo_samples[frame * 2u + 1u] = (int16_t)right;
    synth->active_voice_count = active;
    synth->pcm_hash = ge_audio_hash_s16(synth->pcm_hash, (int16_t)left);
    synth->pcm_hash = ge_audio_hash_s16(synth->pcm_hash, (int16_t)right);
    synth->rendered_frames++;
}

static GEStatusV1 ge_audio_handle_event(const uint8_t *ctl_bytes,
                                        uint32_t ctl_byte_count,
                                        const uint8_t *tbl_bytes,
                                        uint32_t tbl_byte_count,
                                        const GEAudioBankV5 *bank,
                                        GEAudioSynthV5 *synth,
                                        const GECSeqEventV5 *event,
                                        uint32_t frame,
                                        uint32_t duration_frames,
                                        GEAudioDiagnosticV5 *diagnostic)
{
    if (event == NULL || synth == NULL) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_ARGUMENT,
                                       0u,
                                       UINT32_MAX,
                                       0u,
                                       0u,
                                       0u,
                                       0u,
                                       "audio event handler received a null event or synth",
                                       GE_STATUS_INVALID_ARGUMENT);
    }
    synth->event_hash = ge_audio_hash_bytes_seed(synth->event_hash,
                                                (const uint8_t *)event,
                                                (uint32_t)sizeof(*event));
    if (event->event_kind != GE_AUDIO_ENGINE_V5_EVENT_MIDI) {
        return GE_STATUS_OK;
    }
    uint32_t channel = event->status & 0x0fu;
    uint32_t status = event->status & 0xf0u;
    if (channel >= 16u) {
        return GE_STATUS_OK;
    }
    switch (status) {
    case 0x80u:
        ge_audio_stop_voice(synth, channel, event->data1, frame);
        break;
    case 0x90u:
        if (event->data2 == 0u) {
            ge_audio_stop_voice(synth, channel, event->data1, frame);
        } else {
            GEStatusV1 start_status = ge_audio_start_voice(ctl_bytes,
                                                           ctl_byte_count,
                                                           tbl_bytes,
                                                           tbl_byte_count,
                                                           bank,
                                                           synth,
                                                           channel,
                                                           event->data1,
                                                           event->data2,
                                                           frame,
                                                           diagnostic);
            if (start_status != GE_STATUS_OK) {
                return start_status;
            }
            GEAudioVoiceV5 *voice = ge_audio_find_voice(synth, channel, event->data1);
            if (voice != NULL && duration_frames != 0u) {
                voice->release_requested = 1u;
                voice->release_frame = frame + duration_frames;
            }
        }
        break;
    case 0xb0u:
        switch (event->data1) {
        case 0x07u:
            synth->channel_volume[channel] = event->data2;
            break;
        case 0x0au:
            synth->channel_pan[channel] = event->data2;
            break;
        case 0x40u:
            synth->channel_sustain[channel] = event->data2;
            break;
        default:
            break;
        }
        break;
    case 0xc0u:
        synth->channel_program[channel] = event->data1;
        break;
    case 0xe0u:
        synth->channel_pitch_bend[channel] = (uint16_t)(((uint16_t)event->data2 << 7) |
                                                        event->data1);
        break;
    case 0xa0u:
    case 0xd0u:
        /* Source aftertouch is accepted by the CSeq parser but is not needed
           by the three boot sequences. */
        break;
    default:
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_UNSUPPORTED,
                                       GE_AUDIO_ENGINE_V5_DIAG_FLAG_STUB_M13,
                                       event->track,
                                       event->byte_offset,
                                       event->status,
                                       0u,
                                       0u,
                                       "STUB(M13): MIDI status is outside the bounded native mixer subset",
                                       GE_STATUS_UNSUPPORTED_COMMAND);
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_audio_render_sequence_v5(
    const uint8_t *sequence_bytes,
    uint32_t sequence_byte_count,
    const uint8_t *ctl_bytes,
    uint32_t ctl_byte_count,
    const uint8_t *tbl_bytes,
    uint32_t tbl_byte_count,
    uint32_t frame_count,
    int16_t *stereo_samples,
    uint32_t stereo_sample_capacity,
    GEAudioRenderResultV5 *result,
    GEAudioDiagnosticV5 *diagnostic)
{
    ge_audio_diagnostic_clear(diagnostic);
    if (result == NULL || stereo_samples == NULL || frame_count == 0u ||
        frame_count > GE_AUDIO_ENGINE_V5_MAX_RENDER_FRAMES ||
        stereo_sample_capacity < frame_count * 2u) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_ARGUMENT,
                                       0u,
                                       UINT32_MAX,
                                       0u,
                                       0u,
                                       frame_count,
                                       stereo_sample_capacity,
                                       "audio render destination is null or smaller than its bounded stereo frame count",
                                       GE_STATUS_INVALID_ARGUMENT);
    }
    memset(result, 0, sizeof(*result));
    result->version = GE_AUDIO_ENGINE_V5_VERSION;
    result->frames_requested = frame_count;
    memset(stereo_samples, 0, frame_count * 2u * sizeof(int16_t));
    GEAudioBankV5 bank;
    GEStatusV1 status = ge_audio_bank_init_v5(ctl_bytes,
                                              ctl_byte_count,
                                              tbl_bytes,
                                              tbl_byte_count,
                                              &bank,
                                              diagnostic);
    if (status != GE_STATUS_OK) {
        result->diagnostic_code = diagnostic == NULL ? 0u : diagnostic->code;
        result->diagnostic_flags = diagnostic == NULL ? 0u : diagnostic->flags;
        return status;
    }
    GEAudioSchedulerV5 scheduler;
    status = ge_audio_scheduler_init_v5(sequence_bytes,
                                        sequence_byte_count,
                                        &scheduler,
                                        diagnostic);
    if (status != GE_STATUS_OK) {
        result->diagnostic_code = diagnostic == NULL ? 0u : diagnostic->code;
        result->diagnostic_flags = diagnostic == NULL ? 0u : diagnostic->flags;
        return status;
    }
    /* A synth owns up to 24 decoded 64K-sample voices. Allocate that
       owner-side state once per offline render instead of putting several
       megabytes on the owner thread's stack. */
    GEAudioSynthV5 *synth = (GEAudioSynthV5 *)calloc(1u, sizeof(*synth));
    if (synth == NULL) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_CAPACITY,
                                       GE_AUDIO_ENGINE_V5_DIAG_FLAG_RECOVERABLE,
                                       UINT32_MAX,
                                       0u,
                                       0u,
                                       (uint32_t)sizeof(GEAudioSynthV5),
                                       0u,
                                       "native audio synth allocation failed before bounded sequence rendering",
                                       GE_STATUS_INTERNAL_ERROR);
    }
    ge_audio_synth_init_v5(synth, GE_AUDIO_V5_SAMPLE_RATE);
    uint32_t frame = 0u;
    while (frame < frame_count) {
        GECSeqEventV5 event;
        uint64_t event_sample = 0u;
        status = ge_audio_scheduler_next_event_v5(sequence_bytes,
                                                  sequence_byte_count,
                                                  &scheduler,
                                                  &event,
                                                  &event_sample,
                                                  diagnostic);
        if (status != GE_STATUS_OK) {
            free(synth);
            result->diagnostic_code = diagnostic == NULL ? 0u : diagnostic->code;
            result->diagnostic_flags = diagnostic == NULL ? 0u : diagnostic->flags;
            return status;
        }
        if (event_sample > frame_count || event.event_kind == GE_AUDIO_ENGINE_V5_EVENT_SEQUENCE_END) {
            while (frame < frame_count) {
                ge_audio_synth_mix_frame(synth, stereo_samples, frame, GE_AUDIO_V5_SAMPLE_RATE);
                frame++;
            }
            break;
        }
        uint32_t event_frame = (uint32_t)event_sample;
        while (frame < event_frame) {
            ge_audio_synth_mix_frame(synth, stereo_samples, frame, GE_AUDIO_V5_SAMPLE_RATE);
            frame++;
        }
        uint64_t duration_remainder = 0u;
        uint64_t duration_samples = ge_audio_scheduler_sample_delta(
            event.duration_ticks,
            scheduler.tempo_microseconds,
            scheduler.division,
            &duration_remainder);
        uint32_t duration_frames = duration_samples > UINT32_MAX ?
            UINT32_MAX : (uint32_t)duration_samples;
        status = ge_audio_handle_event(ctl_bytes,
                                       ctl_byte_count,
                                       tbl_bytes,
                                       tbl_byte_count,
                                       &bank,
                                       synth,
                                       &event,
                                       frame,
                                       duration_frames,
                                       diagnostic);
        result->event_count++;
        if (status != GE_STATUS_OK) {
            free(synth);
            result->diagnostic_code = diagnostic == NULL ? 0u : diagnostic->code;
            result->diagnostic_flags = diagnostic == NULL ? 0u : diagnostic->flags;
            return status;
        }
        if (event.event_kind == GE_AUDIO_ENGINE_V5_EVENT_SEQUENCE_END) {
            while (frame < frame_count) {
                ge_audio_synth_mix_frame(synth, stereo_samples, frame, GE_AUDIO_V5_SAMPLE_RATE);
                frame++;
            }
            break;
        }
    }
    result->frames_rendered = synth->rendered_frames;
    result->active_voice_count = synth->active_voice_count;
    result->sample_cursor = scheduler.sample_cursor;
    result->event_hash = synth->event_hash;
    result->pcm_hash = synth->pcm_hash;
    result->first_sample_index = 0u;
    free(synth);
    return GE_STATUS_OK;
}

GEStatusV1 ge_audio_render_sfx_v5(
    const uint8_t *ctl_bytes,
    uint32_t ctl_byte_count,
    const uint8_t *tbl_bytes,
    uint32_t tbl_byte_count,
    uint32_t sound_index,
    uint32_t frame_count,
    int16_t *stereo_samples,
    uint32_t stereo_sample_capacity,
    GEAudioRenderResultV5 *result,
    GEAudioDiagnosticV5 *diagnostic)
{
    ge_audio_diagnostic_clear(diagnostic);
    if (result == NULL || stereo_samples == NULL || frame_count == 0u ||
        frame_count > GE_AUDIO_ENGINE_V5_MAX_RENDER_FRAMES ||
        stereo_sample_capacity < frame_count * 2u) {
        return ge_audio_diagnostic_set(diagnostic,
                                       GE_AUDIO_ENGINE_V5_DIAG_ARGUMENT,
                                       0u,
                                       UINT32_MAX,
                                       0u,
                                       0u,
                                       frame_count,
                                       stereo_sample_capacity,
                                       "SFX render destination is null or smaller than its bounded stereo frame count",
                                       GE_STATUS_INVALID_ARGUMENT);
    }
    memset(result, 0, sizeof(*result));
    result->version = GE_AUDIO_ENGINE_V5_VERSION;
    result->frames_requested = frame_count;
    memset(stereo_samples, 0, frame_count * 2u * sizeof(int16_t));

    GEAudioBankV5 bank;
    GEStatusV1 status = ge_audio_bank_init_v5(ctl_bytes,
                                              ctl_byte_count,
                                              tbl_bytes,
                                              tbl_byte_count,
                                              &bank,
                                              diagnostic);
    if (status != GE_STATUS_OK) {
        result->diagnostic_code = diagnostic == NULL ? 0u : diagnostic->code;
        result->diagnostic_flags = diagnostic == NULL ? 0u : diagnostic->flags;
        return status;
    }
    GEAudioWaveV5 wave;
    status = ge_audio_bank_lookup_sfx_v5(ctl_bytes,
                                         ctl_byte_count,
                                         &bank,
                                         sound_index,
                                         &wave,
                                         diagnostic);
    if (status != GE_STATUS_OK) {
        result->diagnostic_code = diagnostic == NULL ? 0u : diagnostic->code;
        result->diagnostic_flags = diagnostic == NULL ? 0u : diagnostic->flags;
        return status;
    }
    /* This bounded offline helper is used to pre-render a menu SFX into the
       owner-side event queue.  The realtime callback never calls it. */
    int16_t decoded[GE_AUDIO_ENGINE_V5_MAX_WAVE_SAMPLES];
    uint32_t decoded_count = 0u;
    status = ge_audio_decode_wave_v5(ctl_bytes,
                                     ctl_byte_count,
                                     tbl_bytes,
                                     tbl_byte_count,
                                     &wave,
                                     decoded,
                                     GE_AUDIO_ENGINE_V5_MAX_WAVE_SAMPLES,
                                     &decoded_count,
                                     diagnostic);
    if (status != GE_STATUS_OK) {
        result->diagnostic_code = diagnostic == NULL ? 0u : diagnostic->code;
        result->diagnostic_flags = diagnostic == NULL ? 0u : diagnostic->flags;
        return status;
    }
    int32_t source_gain = ge_audio_q16_from_u8(wave.sample_volume);
    int32_t pan = (int32_t)wave.sample_pan * 65536 / 127;
    result->event_count = 1u;
    result->event_hash = GE_AUDIO_ENGINE_V5_HASH_OFFSET;
    result->event_hash = ge_audio_hash_bytes_seed(result->event_hash,
                                                  (const uint8_t *)&sound_index,
                                                  (uint32_t)sizeof(sound_index));
    result->pcm_hash = GE_AUDIO_ENGINE_V5_HASH_OFFSET;
    uint32_t loop_count = wave.loop_count;
    uint32_t source_index = 0u;
    for (uint32_t frame = 0u; frame < frame_count; frame++) {
        if (source_index >= decoded_count) {
            if (wave.loop_end > wave.loop_start && wave.loop_end <= decoded_count &&
                (loop_count == UINT32_MAX || loop_count != 0u)) {
                source_index = wave.loop_start;
                if (loop_count != UINT32_MAX) {
                    loop_count--;
                }
            } else {
                source_index = decoded_count - 1u;
            }
        }
        int32_t sample = (int32_t)(((int64_t)decoded[source_index] * source_gain) >> 16);
        int64_t left = ((int64_t)sample * (65536 - pan)) >> 16;
        int64_t right = ((int64_t)sample * pan) >> 16;
        stereo_samples[frame * 2u] = ge_audio_clamp_s16(left);
        stereo_samples[frame * 2u + 1u] = ge_audio_clamp_s16(right);
        result->pcm_hash = ge_audio_hash_s16(result->pcm_hash, stereo_samples[frame * 2u]);
        result->pcm_hash = ge_audio_hash_s16(result->pcm_hash, stereo_samples[frame * 2u + 1u]);
        source_index++;
    }
    result->frames_rendered = frame_count;
    result->active_voice_count = frame_count < decoded_count ? 1u : 0u;
    result->sample_cursor = frame_count;
    return GE_STATUS_OK;
}
