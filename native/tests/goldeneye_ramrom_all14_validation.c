#include "ge_ramrom_playback_v5.h"

#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/*
 * Bounded M28 validation for the complete source-order RAMROM catalog.
 *
 * This test deliberately exercises the value-only parser and paired playback
 * controller, not the N64 runtime.  It runs every guarded recording twice,
 * checks that the two runs consume the same packets/samples/RNG checkpoints,
 * and verifies the source install can be copied for title restoration.  Stage
 * scene preparation is performed by the companion Swift harness in
 * scripts/test_ramrom_all14.sh; this C lane records the explicit unsupported
 * gameplay boundary rather than silently substituting a stage implementation.
 */

#define DEMO_COUNT 14u

static const char *const k_demo_names[DEMO_COUNT] = {
    "ramrom_Dam_1.bin",
    "ramrom_Dam_2.bin",
    "ramrom_Facility_1.bin",
    "ramrom_Facility_2.bin",
    "ramrom_Facility_3.bin",
    "ramrom_Runway_1.bin",
    "ramrom_Runway_2.bin",
    "ramrom_BunkerI_1.bin",
    "ramrom_BunkerI_2.bin",
    "ramrom_Silo_1.bin",
    "ramrom_Silo_2.bin",
    "ramrom_Frigate_1.bin",
    "ramrom_Frigate_2.bin",
    "ramrom_Train.bin",
};

typedef struct RunResult {
    uint64_t recording_hash;
    uint64_t packet_hash;
    uint64_t input_hash;
    uint64_t rng_hash;
    uint64_t final_playback_hash;
    uint64_t final_state_hash;
    uint64_t final_event_hash;
    uint64_t restore_register_hash;
    uint64_t restore_save_hash;
    uint32_t packet_count;
    uint32_t record_count;
    uint32_t sample_events;
    uint32_t packet_advance_events;
    uint32_t event_count;
    uint64_t terminal_tick;
} RunResult;

static int fail_at(uint32_t demo_id, const char *detail)
{
    fprintf(stderr, "RAMROM validation failed demo=%u: %s\n", demo_id, detail);
    return 0;
}

#define REQUIRE_DEMO(demo_id, condition, detail) \
    do { \
        if (!(condition)) { \
            return fail_at((demo_id), (detail)); \
        } \
    } while (0)

static int read_file(const char *path, uint8_t **out_bytes, uint32_t *out_count)
{
    FILE *file = fopen(path, "rb");
    if (file == NULL || fseek(file, 0L, SEEK_END) != 0) {
        if (file != NULL) {
            fclose(file);
        }
        return 0;
    }
    long length = ftell(file);
    if (length < 0L || (uint64_t)length > UINT32_MAX ||
        fseek(file, 0L, SEEK_SET) != 0) {
        fclose(file);
        return 0;
    }
    uint32_t count = (uint32_t)length;
    uint8_t *bytes = (uint8_t *)malloc(count == 0u ? 1u : count);
    if (bytes == NULL) {
        fclose(file);
        return 0;
    }
    size_t read_count = fread(bytes, 1u, count, file);
    int read_error = ferror(file);
    int has_extra = fgetc(file) != EOF;
    fclose(file);
    if (read_error || has_extra || read_count != count) {
        free(bytes);
        return 0;
    }
    *out_bytes = bytes;
    *out_count = count;
    return 1;
}

static GERamRomPlaybackInputV5 no_input(void)
{
    GERamRomPlaybackInputV5 input;
    memset(&input, 0, sizeof(input));
    input.header.abi_version = GE_NATIVE_ABI_VERSION;
    input.header.struct_size = (uint32_t)sizeof(input);
    input.record_version = GE_RAMROM_PLAYBACK_V5_RECORD_VERSION;
    input.flags = GE_RAMROM_PLAYBACK_INPUT_FOCUSED;
    input.controller_count = 0u;
    return input;
}

static GERamRomPlaybackInputV5 abort_input(void)
{
    GERamRomPlaybackInputV5 input = no_input();
    input.flags |= GE_RAMROM_PLAYBACK_INPUT_REAL;
    input.pressed_buttons = UINT32_C(0x00008000);
    input.controller_count = 1u;
    return input;
}

static int check_catalog_and_parser(const uint8_t *bytes,
                                    uint32_t byte_count,
                                    uint32_t demo_id,
                                    GERamRomHeaderV5 *out_header,
                                    GERamRomParseSummaryV5 *out_summary)
{
    GERamRomHeaderV5 header;
    GERamRomParseSummaryV5 summary;
    GERamRomCatalogEntryV5 catalog;
    REQUIRE_DEMO(demo_id,
                  ge_ramrom_v5_read_header(bytes, byte_count, &header) ==
                      GE_STATUS_OK,
                  "header parse");
    REQUIRE_DEMO(demo_id,
                  ge_ramrom_v5_parse(bytes, byte_count, &summary) ==
                      GE_STATUS_OK,
                  "recording parse");
    REQUIRE_DEMO(demo_id,
                  ge_ramrom_v5_catalog_entry(demo_id - 1u, &catalog) ==
                      GE_STATUS_OK,
                  "catalog lookup");
    REQUIRE_DEMO(demo_id,
                  ge_ramrom_v5_validate_header(&header) == GE_STATUS_OK,
                  "header validation");
    REQUIRE_DEMO(demo_id,
                  ge_ramrom_v5_validate_summary(&summary) == GE_STATUS_OK,
                  "summary validation");
    REQUIRE_DEMO(demo_id,
                  header.stage_id == catalog.stage_id &&
                      header.controller_count == catalog.controller_count &&
                      header.declared_file_bytes == catalog.declared_file_bytes &&
                      byte_count == catalog.asset_file_bytes,
                  "catalog/header byte metadata mismatch");
    REQUIRE_DEMO(demo_id,
                  summary.recording_hash == catalog.recording_hash &&
                      summary.recording_hash != 0u &&
                      ge_ramrom_v5_hash_bytes(bytes, header.declared_file_bytes) ==
                          summary.recording_hash,
                  "recording hash mismatch");
    REQUIRE_DEMO(demo_id,
                  summary.packet_count != 0u && summary.record_count != 0u &&
                      summary.checksum_valid_count == summary.packet_count &&
                      summary.parsed_bytes == header.declared_file_bytes &&
                      summary.terminal_bytes == GE_RAMROM_V5_TERMINAL_BYTES,
                  "recording summary boundary mismatch");
    REQUIRE_DEMO(demo_id,
                  (summary.flags & GE_RAMROM_V5_PARSE_FLAG_CHECKSUMS_VALID) !=
                      0u &&
                      (summary.flags & GE_RAMROM_V5_PARSE_FLAG_SPEEDFRAMES_VALID) !=
                      0u,
                  "recording summary validity flags missing");
    *out_header = header;
    *out_summary = summary;
    return 1;
}

static int compare_run_results(uint32_t demo_id,
                               const RunResult *first,
                               const RunResult *second)
{
    REQUIRE_DEMO(demo_id, first->recording_hash == second->recording_hash,
                  "recording hash changed between runs");
    REQUIRE_DEMO(demo_id, first->packet_hash == second->packet_hash,
                  "packet hash changed between runs");
    REQUIRE_DEMO(demo_id, first->input_hash == second->input_hash,
                  "input hash changed between runs");
    REQUIRE_DEMO(demo_id, first->rng_hash == second->rng_hash,
                  "RNG hash changed between runs");
    REQUIRE_DEMO(demo_id,
                  first->final_playback_hash == second->final_playback_hash,
                  "final playback hash changed between runs");
    REQUIRE_DEMO(demo_id, first->final_state_hash == second->final_state_hash,
                  "final state hash changed between runs");
    REQUIRE_DEMO(demo_id, first->final_event_hash == second->final_event_hash,
                  "terminal event hash changed between runs");
    REQUIRE_DEMO(demo_id,
                  first->restore_register_hash == second->restore_register_hash &&
                      first->restore_save_hash == second->restore_save_hash,
                  "restore hashes changed between runs");
    REQUIRE_DEMO(demo_id,
                  first->packet_count == second->packet_count &&
                      first->record_count == second->record_count &&
                      first->sample_events == second->sample_events &&
                      first->packet_advance_events == second->packet_advance_events &&
                      first->event_count == second->event_count &&
                      first->terminal_tick == second->terminal_tick,
                  "playback counters changed between runs");
    return 1;
}

static int run_complete(const uint8_t *bytes,
                        uint32_t byte_count,
                        uint32_t demo_id,
                        const GERamRomHeaderV5 *header,
                        const GERamRomParseSummaryV5 *summary,
                        RunResult *out_result)
{
    GERamRomPlaybackStateV5 state;
    GERamRomPlaybackEventV5 event;
    memset(out_result, 0, sizeof(*out_result));
    REQUIRE_DEMO(demo_id,
                  ge_ramrom_playback_v5_begin(bytes, byte_count, demo_id,
                                               &state, &event) == GE_STATUS_OK,
                  "playback begin");
    REQUIRE_DEMO(demo_id,
                  event.event_type == GE_RAMROM_PLAYBACK_EVENT_STAGE_LOAD_UNSUPPORTED &&
                      event.diagnostic_code ==
                          GE_RAMROM_PLAYBACK_DIAGNOSTIC_STAGE_UNSUPPORTED &&
                      (event.flags & GE_RAMROM_PLAYBACK_EVENT_FLAG_INSTALL) != 0u,
                  "stage boundary diagnostic missing");
    REQUIRE_DEMO(demo_id,
                  state.stage_id == header->stage_id &&
                      state.record_count == summary->record_count &&
                      state.packet_count == summary->packet_count &&
                      (state.flags & GE_RAMROM_PLAYBACK_STATE_STAGE_UNSUPPORTED) != 0u,
                  "playback state does not match parsed recording");
    GERamRomPlaybackEventV5 stage_event;
    REQUIRE_DEMO(demo_id,
                  ge_ramrom_playback_v5_load_stage(&state, &stage_event) ==
                      GE_STATUS_UNSUPPORTED_COMMAND &&
                      stage_event.event_type ==
                          GE_RAMROM_PLAYBACK_EVENT_STAGE_LOAD_UNSUPPORTED,
                  "stage loader boundary changed unexpectedly");

    GERamRomPlaybackInputV5 input = no_input();
    uint32_t sample_events = 0u;
    uint32_t packet_advance_events = 0u;
    uint64_t terminal_tick = 0u;
    int saw_fade = 0;
    int saw_return = 0;
    uint64_t max_ticks = (uint64_t)summary->record_count * 2u + 16u;
    for (uint64_t tick = 0u; tick < max_ticks; tick++) {
        GEStatusV1 status = ge_ramrom_playback_v5_step(
            bytes, byte_count, tick, input, &state, &event);
        REQUIRE_DEMO(demo_id, status == GE_STATUS_OK, "playback step");
        REQUIRE_DEMO(demo_id,
                      event.native_tick == tick &&
                          event.reference_tick == tick / 2u &&
                          event.pair_phase == (uint32_t)(tick & 1u) &&
                          event.state_hash != 0u &&
                          ge_ramrom_playback_v5_validate_event(&event) ==
                              GE_STATUS_OK &&
                          ge_ramrom_playback_v5_validate_state(&state) ==
                              GE_STATUS_OK,
                      "paired event/state validation");
        if (event.event_type == GE_RAMROM_PLAYBACK_EVENT_SAMPLE) {
            sample_events++;
        }
        if ((event.flags & GE_RAMROM_PLAYBACK_EVENT_FLAG_PACKET_ADVANCE) != 0u) {
            packet_advance_events++;
        }
        if (event.event_type == GE_RAMROM_PLAYBACK_EVENT_FADE_TO_TITLE) {
            saw_fade = 1;
        }
        if (event.event_type == GE_RAMROM_PLAYBACK_EVENT_RETURN_TO_TITLE) {
            saw_return = 1;
            terminal_tick = tick;
            break;
        }
        REQUIRE_DEMO(demo_id,
                      event.event_type != GE_RAMROM_PLAYBACK_EVENT_ERROR,
                      "playback emitted error event");
    }
    REQUIRE_DEMO(demo_id, saw_fade && saw_return,
                  "playback did not reach fade and return events");
    REQUIRE_DEMO(demo_id,
                  sample_events == summary->record_count &&
                      state.sample_index == summary->record_count &&
                      state.packet_index == summary->packet_count &&
                      state.source_anchor == summary->record_count &&
                      state.replay_state == GE_RAMROM_STATE_COMPLETE &&
                      (state.flags & GE_RAMROM_PLAYBACK_STATE_RESTORE_READY) != 0u,
                  "playback did not consume the complete recording");
    REQUIRE_DEMO(demo_id,
                  state.recording_hash == summary->recording_hash &&
                      state.packet_hash == summary->packet_hash &&
                      state.input_hash == summary->input_hash &&
                      state.rng_hash == summary->rng_hash,
                  "playback state hash metadata mismatch");

    GERamRomPlaybackInstallV5 restore;
    REQUIRE_DEMO(demo_id,
                  ge_ramrom_playback_v5_copy_install(&state, &restore, 1u) ==
                      GE_STATUS_OK &&
                      (restore.flags & GE_RAMROM_PLAYBACK_INSTALL_RESTORED) != 0u &&
                      restore.source_header.stage_id == header->stage_id &&
                      restore.save_hash == header->save_hash &&
                      restore.register_hash != 0u &&
                      ge_ramrom_playback_v5_validate_install(&restore) ==
                          GE_STATUS_OK,
                  "restore install validation");

    out_result->recording_hash = state.recording_hash;
    out_result->packet_hash = state.packet_hash;
    out_result->input_hash = state.input_hash;
    out_result->rng_hash = state.rng_hash;
    out_result->final_playback_hash = state.playback_hash;
    out_result->final_state_hash = ge_ramrom_playback_v5_hash_state(&state);
    out_result->final_event_hash = ge_ramrom_playback_v5_hash_event(&event);
    out_result->restore_register_hash = restore.register_hash;
    out_result->restore_save_hash = restore.save_hash;
    out_result->packet_count = state.packet_count;
    out_result->record_count = state.record_count;
    out_result->sample_events = sample_events;
    out_result->packet_advance_events = packet_advance_events;
    out_result->event_count = state.event_count;
    out_result->terminal_tick = terminal_tick;
    return 1;
}

static int run_abort_restore(const uint8_t *bytes,
                             uint32_t byte_count,
                             uint32_t demo_id,
                             const GERamRomHeaderV5 *header)
{
    GERamRomPlaybackStateV5 state;
    GERamRomPlaybackEventV5 event;
    REQUIRE_DEMO(demo_id,
                  ge_ramrom_playback_v5_begin(bytes, byte_count, demo_id,
                                               &state, &event) == GE_STATUS_OK,
                  "abort begin");
    GERamRomPlaybackInputV5 input = abort_input();
    REQUIRE_DEMO(demo_id,
                  ge_ramrom_playback_v5_step(bytes, byte_count, 0u, input,
                                              &state, &event) == GE_STATUS_OK &&
                      event.event_type == GE_RAMROM_PLAYBACK_EVENT_FADE_TO_TITLE &&
                      (event.flags & GE_RAMROM_PLAYBACK_EVENT_FLAG_ABORTED_INPUT) != 0u,
                  "real-input abort event");
    input = no_input();
    REQUIRE_DEMO(demo_id,
                  ge_ramrom_playback_v5_step(bytes, byte_count, 1u, input,
                                              &state, &event) == GE_STATUS_OK &&
                      event.event_type == GE_RAMROM_PLAYBACK_EVENT_RETURN_TO_TITLE &&
                      state.replay_state == GE_RAMROM_STATE_COMPLETE &&
                      (state.flags & GE_RAMROM_PLAYBACK_STATE_RESTORE_READY) != 0u,
                  "abort return event");
    GERamRomPlaybackInstallV5 restore;
    REQUIRE_DEMO(demo_id,
                  ge_ramrom_playback_v5_copy_install(&state, &restore, 1u) ==
                      GE_STATUS_OK && restore.source_header.stage_id == header->stage_id &&
                      restore.save_hash == header->save_hash,
                  "abort restore install");
    return 1;
}

static int run_corruption_guard(const uint8_t *bytes,
                                uint32_t byte_count,
                                uint32_t demo_id)
{
    uint8_t *mutated = (uint8_t *)malloc(byte_count);
    REQUIRE_DEMO(demo_id, mutated != NULL, "corruption buffer allocation");
    memcpy(mutated, bytes, byte_count);
    /* The packet checksum byte is inside the first packet header. */
    REQUIRE_DEMO(demo_id,
                  byte_count > GE_RAMROM_V5_HEADER_BYTES + 3u,
                  "recording too short for checksum guard");
    mutated[GE_RAMROM_V5_HEADER_BYTES + 3u] ^= 1u;
    GERamRomPlaybackStateV5 state;
    GERamRomPlaybackEventV5 event;
    GEStatusV1 status = ge_ramrom_playback_v5_begin(
        mutated, byte_count, demo_id, &state, &event);
    free(mutated);
    REQUIRE_DEMO(demo_id, status == GE_STATUS_ASSET_MISMATCH,
                  "corrupted recording was accepted");
    return 1;
}

int main(int argc, char **argv)
{
    const char *asset_root = argc > 1 ? argv[1] : "build/native/boot-assets/ramrom";
    uint32_t completed_runs = 0u;
    uint32_t abort_runs = 0u;
    uint32_t stage_count = 0u;
    uint32_t seen_stages[DEMO_COUNT];
    memset(seen_stages, 0, sizeof(seen_stages));

    for (uint32_t index = 0u; index < DEMO_COUNT; index++) {
        uint32_t demo_id = index + 1u;
        char path[1024];
        int path_length = snprintf(path, sizeof(path), "%s/%s", asset_root,
                                   k_demo_names[index]);
        if (path_length < 0 || (size_t)path_length >= sizeof(path)) {
            fprintf(stderr, "RAMROM validation path is too long for demo=%u\n",
                    demo_id);
            return 1;
        }
        uint8_t *bytes = NULL;
        uint32_t byte_count = 0u;
        if (!read_file(path, &bytes, &byte_count)) {
            fprintf(stderr, "RAMROM validation could not read demo=%u path=%s\n",
                    demo_id, path);
            return 1;
        }
        GERamRomHeaderV5 header;
        GERamRomParseSummaryV5 summary;
        int ok = check_catalog_and_parser(bytes, byte_count, demo_id, &header,
                                          &summary);
        if (ok) {
            uint32_t already_seen = 0u;
            for (uint32_t previous = 0u; previous < stage_count; previous++) {
                if (seen_stages[previous] == header.stage_id) {
                    already_seen = 1u;
                    break;
                }
            }
            if (!already_seen) {
                seen_stages[stage_count++] = header.stage_id;
            }
            RunResult first;
            RunResult second;
            ok = run_complete(bytes, byte_count, demo_id, &header, &summary,
                              &first);
            if (ok) {
                ok = run_complete(bytes, byte_count, demo_id, &header, &summary,
                                  &second);
            }
            if (ok) {
                ok = compare_run_results(demo_id, &first, &second);
            }
            if (ok) {
                ok = run_abort_restore(bytes, byte_count, demo_id, &header);
            }
            if (ok && demo_id == GE_RAMROM_V5_DEMO_DAM_1) {
                ok = run_corruption_guard(bytes, byte_count, demo_id);
            }
            if (ok) {
                completed_runs += 2u;
                abort_runs++;
                printf("demo=%02u asset=%s stage=%" PRIu32
                       " packets=%" PRIu32 " records=%" PRIu32
                       " runs=2 terminal_tick=%" PRIu64
                       " recording_hash=%" PRIu64 " rng_hash=%" PRIu64
                       " final_playback_hash=%" PRIu64
                       " restore_save_hash=%" PRIu64 " gameplay=STUB(M26)\n",
                       demo_id, k_demo_names[index], header.stage_id,
                       summary.packet_count, summary.record_count,
                       first.terminal_tick, first.recording_hash,
                       first.rng_hash, first.final_playback_hash,
                       first.restore_save_hash);
            }
        }
        free(bytes);
        if (!ok) {
            return 1;
        }
    }

    printf("goldeneye_ramrom_all14_validation: PASS demos=%u runs=%u abort_restore=%u unique_stages=%u parser=PASS playback=PASS checksum=PASS rng=PASS gameplay_boundary=STUB(M26) renderer_boundary=STUB(M27)\n",
           DEMO_COUNT, completed_runs, abort_runs, stage_count);
    return 0;
}
