#include "ge_ramrom_playback_v5.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define REQUIRE(condition)                                                       \
    do {                                                                          \
        if (!(condition)) {                                                       \
            fprintf(stderr, "ramrom playback requirement failed at %s:%d: %s\n", \
                    __FILE__, __LINE__, #condition);                             \
            return 1;                                                             \
        }                                                                         \
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
    uint8_t *bytes = (uint8_t *)malloc(count);
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
    return input;
}

static int test_start_and_stage_diagnostic(const uint8_t *bytes,
                                           uint32_t byte_count,
                                           GERamRomPlaybackStateV5 *state)
{
    GERamRomPlaybackEventV5 event;
    REQUIRE(ge_ramrom_playback_v5_begin(bytes,
                                        byte_count,
                                        GE_RAMROM_V5_DEMO_DAM_1,
                                        state,
                                        &event) == GE_STATUS_OK);
    REQUIRE(event.event_type == GE_RAMROM_PLAYBACK_EVENT_STAGE_LOAD_UNSUPPORTED);
    REQUIRE((event.flags & GE_RAMROM_PLAYBACK_EVENT_FLAG_INSTALL) != 0u);
    REQUIRE((event.flags & GE_RAMROM_PLAYBACK_EVENT_FLAG_DIAGNOSTIC) != 0u);
    REQUIRE(event.diagnostic_code ==
            GE_RAMROM_PLAYBACK_DIAGNOSTIC_STAGE_UNSUPPORTED);
    REQUIRE((state->flags & GE_RAMROM_PLAYBACK_STATE_STAGE_UNSUPPORTED) != 0u);
    REQUIRE((state->flags & GE_RAMROM_PLAYBACK_STATE_INSTALL_READY) != 0u);
    REQUIRE(state->install.save_byte_count == GE_RAMROM_V5_SAVE_BYTES);
    REQUIRE(state->install.save_hash == state->install.source_header.save_hash);
    REQUIRE(ge_ramrom_playback_v5_validate_state(state) == GE_STATUS_OK);

    GERamRomPlaybackEventV5 stage_event;
    REQUIRE(ge_ramrom_playback_v5_load_stage(state, &stage_event) ==
            GE_STATUS_UNSUPPORTED_COMMAND);
    REQUIRE(stage_event.event_type == GE_RAMROM_PLAYBACK_EVENT_STAGE_LOAD_UNSUPPORTED);
    REQUIRE(stage_event.diagnostic_code ==
            GE_RAMROM_PLAYBACK_DIAGNOSTIC_STAGE_UNSUPPORTED);
    return 0;
}

static int test_paired_playback(const uint8_t *bytes,
                                uint32_t byte_count,
                                const GERamRomPlaybackStateV5 *initial)
{
    GERamRomPlaybackStateV5 state = *initial;
    GERamRomPlaybackInputV5 input = no_input();
    GERamRomPlaybackEventV5 event;
    uint32_t sample_events = 0u;
    uint32_t odd_events = 0u;
    uint32_t packet_advance_events = 0u;
    uint64_t previous_state_hash = 0u;

    for (uint64_t tick = 0u; tick < 128u; tick++) {
        REQUIRE(ge_ramrom_playback_v5_step(bytes,
                                           byte_count,
                                           tick,
                                           input,
                                           &state,
                                           &event) == GE_STATUS_OK);
        REQUIRE(event.native_tick == tick);
        REQUIRE(event.reference_tick == tick / 2u);
        REQUIRE(event.pair_phase == (uint32_t)(tick & 1u));
        REQUIRE(event.state_hash != 0u);
        REQUIRE(event.state_hash == state.playback_hash);
        if ((tick & 1u) != 0u) {
            odd_events++;
            REQUIRE(event.event_type == GE_RAMROM_PLAYBACK_EVENT_NONE);
            REQUIRE((event.flags & GE_RAMROM_PLAYBACK_EVENT_FLAG_ODD_PAIRED_TICK) !=
                    0u);
            REQUIRE(state.sample_index == sample_events);
        } else {
            REQUIRE(event.event_type == GE_RAMROM_PLAYBACK_EVENT_SAMPLE);
            sample_events++;
            if ((event.flags & GE_RAMROM_PLAYBACK_EVENT_FLAG_PACKET_ADVANCE) != 0u) {
                packet_advance_events++;
            }
        }
        REQUIRE(previous_state_hash != event.state_hash || tick == 0u);
        previous_state_hash = event.state_hash;
    }
    REQUIRE(sample_events == 64u);
    REQUIRE(odd_events == 64u);
    REQUIRE(packet_advance_events >= 1u);
    REQUIRE(state.packet_index != 0u);
    REQUIRE(state.source_anchor == sample_events);
    REQUIRE(state.replay_state == GE_RAMROM_STATE_PLAYING);
    return 0;
}

static int test_complete_and_restore(const uint8_t *bytes,
                                     uint32_t byte_count,
                                     const GERamRomPlaybackStateV5 *initial)
{
    GERamRomPlaybackStateV5 state = *initial;
    GERamRomPlaybackInputV5 input = no_input();
    GERamRomPlaybackEventV5 event;
    uint64_t tick = 0u;
    uint32_t sample_count = 0u;
    int saw_fade = 0;
    int saw_return = 0;
    for (;;) {
        REQUIRE(ge_ramrom_playback_v5_step(bytes,
                                           byte_count,
                                           tick,
                                           input,
                                           &state,
                                           &event) == GE_STATUS_OK);
        if (event.event_type == GE_RAMROM_PLAYBACK_EVENT_SAMPLE) {
            sample_count++;
        }
        if (event.event_type == GE_RAMROM_PLAYBACK_EVENT_FADE_TO_TITLE) {
            saw_fade = 1;
        }
        if (event.event_type == GE_RAMROM_PLAYBACK_EVENT_RETURN_TO_TITLE) {
            saw_return = 1;
            break;
        }
        tick++;
        REQUIRE(tick < 5000u);
    }
    REQUIRE(sample_count == initial->record_count);
    REQUIRE(saw_fade);
    REQUIRE(saw_return);
    REQUIRE(state.replay_state == GE_RAMROM_STATE_COMPLETE);
    REQUIRE((state.flags & GE_RAMROM_PLAYBACK_STATE_RESTORE_READY) != 0u);

    GERamRomPlaybackInstallV5 restore;
    REQUIRE(ge_ramrom_playback_v5_copy_install(&state, &restore, 1u) ==
            GE_STATUS_OK);
    REQUIRE((restore.flags & GE_RAMROM_PLAYBACK_INSTALL_RESTORED) != 0u);
    REQUIRE(restore.save_hash == initial->install.save_hash);
    REQUIRE(restore.register_hash == initial->install.register_hash);
    REQUIRE(memcmp(restore.save_data,
                   initial->install.save_data,
                   GE_RAMROM_V5_SAVE_BYTES) == 0);
    return 0;
}

static int test_abort_and_corruption(const uint8_t *bytes,
                                     uint32_t byte_count,
                                     const GERamRomPlaybackStateV5 *initial)
{
    GERamRomPlaybackStateV5 state = *initial;
    GERamRomPlaybackInputV5 input = no_input();
    input.flags |= GE_RAMROM_PLAYBACK_INPUT_REAL;
    input.pressed_buttons = 0x00008000u;
    GERamRomPlaybackEventV5 event;
    REQUIRE(ge_ramrom_playback_v5_step(bytes,
                                       byte_count,
                                       0u,
                                       input,
                                       &state,
                                       &event) == GE_STATUS_OK);
    REQUIRE(state.replay_state == GE_RAMROM_STATE_ABORTING);
    REQUIRE(event.event_type == GE_RAMROM_PLAYBACK_EVENT_FADE_TO_TITLE);
    REQUIRE((event.flags & GE_RAMROM_PLAYBACK_EVENT_FLAG_ABORTED_INPUT) != 0u);
    REQUIRE(event.abort_buttons == input.pressed_buttons);
    input = no_input();
    REQUIRE(ge_ramrom_playback_v5_step(bytes,
                                       byte_count,
                                       1u,
                                       input,
                                       &state,
                                       &event) == GE_STATUS_OK);
    REQUIRE(state.replay_state == GE_RAMROM_STATE_COMPLETE);
    REQUIRE(event.event_type == GE_RAMROM_PLAYBACK_EVENT_RETURN_TO_TITLE);

    uint8_t *mutated = (uint8_t *)malloc(byte_count);
    REQUIRE(mutated != NULL);
    memcpy(mutated, bytes, byte_count);
    mutated[GE_RAMROM_V5_HEADER_BYTES + 3u] ^= 1u;
    GERamRomPlaybackStateV5 rejected_state;
    REQUIRE(ge_ramrom_playback_v5_begin(mutated,
                                        byte_count,
                                        GE_RAMROM_V5_DEMO_DAM_1,
                                        &rejected_state,
                                        &event) == GE_STATUS_ASSET_MISMATCH);
    free(mutated);
    return 0;
}

int main(int argc, char **argv)
{
    const char *path = argc > 1 ? argv[1] : "assets/ramrom/ramrom_Dam_1.bin";
    uint8_t *bytes = NULL;
    uint32_t byte_count = 0u;
    REQUIRE(read_file(path, &bytes, &byte_count));

    GERamRomPlaybackStateV5 initial;
    REQUIRE(test_start_and_stage_diagnostic(bytes, byte_count, &initial) == 0);
    REQUIRE(test_paired_playback(bytes, byte_count, &initial) == 0);
    REQUIRE(test_complete_and_restore(bytes, byte_count, &initial) == 0);
    REQUIRE(test_abort_and_corruption(bytes, byte_count, &initial) == 0);

    free(bytes);
    printf("goldeneye_ramrom_playback_v5_smoke: PASS\n");
    return 0;
}
