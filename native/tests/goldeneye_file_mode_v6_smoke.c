#include "ge_file_mode_v6.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void fail(const char *message)
{
    fprintf(stderr, "goldeneye_file_mode_v6_smoke: %s\n", message);
    exit(1);
}

static GESaveSnapshotV1 blank_save(void)
{
    GESaveSnapshotV1 save;
    uint32_t index;

    memset(&save, 0, sizeof(save));
    save.header.abi_version = GE_NATIVE_ABI_VERSION;
    save.header.struct_size = (uint32_t)sizeof(save);
    save.record_version = GE_FILE_MODE_V6_RECORD_VERSION;
    for (index = 0u; index < GE_FILE_MODE_V6_FOLDER_COUNT; index++) {
        memset(&save.folders[index], 0, sizeof(save.folders[index]));
        save.folders[index].bytes[8] = (uint8_t)(0x80u | index);
        save.folders[index].bytes[10] = 0xffu;
        save.folders[index].bytes[11] = 0xffu;
        save.folders[index].bytes[13] = 0x3au;
    }
    return save;
}

static GEFileModeInputV6 input(
    uint64_t tick,
    uint64_t sequence,
    uint32_t pressed,
    uint32_t controllers,
    int16_t stick_x,
    int16_t stick_y,
    uint32_t focused)
{
    GEFileModeInputV6 value;

    memset(&value, 0, sizeof(value));
    value.header.abi_version = GE_NATIVE_ABI_VERSION;
    value.header.struct_size = (uint32_t)sizeof(value);
    value.record_version = GE_FILE_MODE_V6_RECORD_VERSION;
    value.flags = GE_FILE_MODE_V6_INPUT_FLAG_CONTROLLER_CONNECTED |
        GE_FILE_MODE_V6_INPUT_FLAG_SYNTHETIC;
    if (focused != 0u) {
        value.flags |= GE_FILE_MODE_V6_INPUT_FLAG_FOCUSED;
    }
    if ((tick & 1u) == 0u) {
        value.flags |= GE_FILE_MODE_V6_INPUT_FLAG_SOURCE_ANCHOR;
    }
    value.buttons_pressed = pressed;
    value.controller_count = controllers;
    value.stick_x = stick_x;
    value.stick_y = stick_y;
    value.clock_timer = 1u;
    value.native_tick = tick;
    value.reference_tick = tick / 2u;
    value.sequence = sequence;
    return value;
}

static void step(
    GEFileModeStateV6 *state,
    GESaveSnapshotV1 *save,
    GEFileModeFrameV6 *frame,
    uint64_t tick,
    uint32_t pressed,
    uint32_t controllers,
    int16_t stick_x,
    int16_t stick_y)
{
    GEFileModeInputV6 value = input(
        tick, tick, pressed, controllers, stick_x, stick_y, 1u);
    GEStatusV1 status = ge_file_mode_v6_step(state, &value, save, frame);
    if (status != GE_STATUS_OK) {
        fprintf(stderr, "goldeneye_file_mode_v6_smoke: step tick %llu status %u\n",
                (unsigned long long)tick, (unsigned)status);
        exit(1);
    }
}

static int has_event(
    const GEFileModeFrameV6 *frame,
    uint32_t kind,
    uint32_t command)
{
    uint32_t index;
    for (index = 0u; index < frame->event_count; index++) {
        if (frame->events[index].kind == kind &&
            ((kind == GE_FILE_MODE_V6_EVENT_SCREEN &&
              frame->events[index].target_screen == command) ||
             (kind != GE_FILE_MODE_V6_EVENT_SCREEN &&
              frame->events[index].command == command))) {
            return 1;
        }
    }
    return 0;
}

static void test_selection_and_mode(void)
{
    GESaveSnapshotV1 save = blank_save();
    GEFileModeStateV6 state;
    GEFileModeFrameV6 frame;

    if (ge_file_mode_v6_init(&state, &save, &frame) != GE_STATUS_OK ||
        state.screen != GE_FILE_MODE_V6_SCREEN_FILE_SELECT ||
        state.cursor_x_q16 != 220 * 65536 || state.cursor_y_q16 != 165 * 65536 ||
        frame.event_count != 0u) {
        fail("init did not preserve source File Select coordinates");
    }
    /* A short confirm press is consumed once and creates the selected blank
     * folder before entering Mode Select. */
    step(&state, &save, &frame, 1u, GE_FILE_MODE_V6_BUTTON_A, 1u, 0, 0);
    if (state.screen != GE_FILE_MODE_V6_SCREEN_MODE_SELECT ||
        ge_file_mode_v6_folder_is_reset(&save.folders[0]) != 0u ||
        !has_event(&frame, GE_FILE_MODE_V6_EVENT_SAVE,
                   GE_FILE_MODE_V6_SAVE_CREATE) ||
        !has_event(&frame, GE_FILE_MODE_V6_EVENT_SCREEN,
                   GE_FILE_MODE_V6_SCREEN_MODE_SELECT)) {
        fail("source select/create route mismatch");
    }
    /* B is the source previous-tab/back action. */
    step(&state, &save, &frame, 2u, GE_FILE_MODE_V6_BUTTON_B, 1u, 0, 0);
    if (state.screen != GE_FILE_MODE_V6_SCREEN_FILE_SELECT ||
        !has_event(&frame, GE_FILE_MODE_V6_EVENT_SCREEN,
                   GE_FILE_MODE_V6_SCREEN_FILE_SELECT)) {
        fail("Mode Select back route mismatch");
    }
    /* Select the same folder again, then expose the two-controller MP row. */
    step(&state, &save, &frame, 3u, GE_FILE_MODE_V6_BUTTON_A, 1u, 0, 0);
    step(&state, &save, &frame, 4u, 0u, 2u, 0, 75);
    step(&state, &save, &frame, 5u, 0u, 2u, 0, 75);
    step(&state, &save, &frame, 6u, 0u, 2u, 0, 75);
    step(&state, &save, &frame, 7u, 0u, 2u, 0, 75);
    if (state.screen != GE_FILE_MODE_V6_SCREEN_MODE_SELECT ||
        state.mode_selection != 1u ||
        (state.flags & GE_FILE_MODE_V6_STATE_FLAG_MULTI_AVAILABLE) == 0u) {
        fail("two-controller Mode Select availability mismatch");
    }
    step(&state, &save, &frame, 8u, GE_FILE_MODE_V6_BUTTON_START, 2u, 0, 0);
    if (state.screen != GE_FILE_MODE_V6_SCREEN_MULTI_ROUTE ||
        !has_event(&frame, GE_FILE_MODE_V6_EVENT_ROUTE,
                   GE_FILE_MODE_V6_SCREEN_MULTI_ROUTE)) {
        fail("multiplayer route mismatch");
    }
}

static void test_copy_and_erase(void)
{
    GESaveSnapshotV1 save = blank_save();
    GEFileModeStateV6 state;
    GEFileModeFrameV6 frame;

    save.folders[0].bytes[18] = 1u;
    save.folders[0].bytes[8] &= 0x7fu;
    if (ge_file_mode_v6_init(&state, &save, &frame) != GE_STATUS_OK) {
        fail("copy/erase init failed");
    }
    state.file_option = GE_FILE_MODE_V6_OPTION_COPY;
    state.hovered_folder = 0u;
    step(&state, &save, &frame, 1u, GE_FILE_MODE_V6_BUTTON_A, 1u, 0, 0);
    if (!has_event(&frame, GE_FILE_MODE_V6_EVENT_SAVE, GE_FILE_MODE_V6_SAVE_COPY) ||
        ge_file_mode_v6_folder_is_reset(&save.folders[1]) != 0u ||
        save.folders[1].bytes[18] != 1u) {
        fail("copy-to-first-blank mismatch");
    }

    /* A full set of completed folders is a source no-op, but still emits the
     * source copy sound and a deterministic no-op save command. */
    save.folders[2].bytes[18] = 1u;
    save.folders[3].bytes[18] = 1u;
    save.folders[2].bytes[8] &= 0x7fu;
    save.folders[3].bytes[8] &= 0x7fu;
    state.file_option = GE_FILE_MODE_V6_OPTION_COPY;
    state.hovered_folder = 0u;
    step(&state, &save, &frame, 2u, GE_FILE_MODE_V6_BUTTON_A, 1u, 0, 0);
    if (!has_event(&frame, GE_FILE_MODE_V6_EVENT_SAVE,
                   GE_FILE_MODE_V6_SAVE_COPY_NOOP)) {
        fail("full-folder copy no-op mismatch");
    }

    state.file_option = GE_FILE_MODE_V6_OPTION_ERASE;
    state.hovered_folder = 0u;
    step(&state, &save, &frame, 3u, GE_FILE_MODE_V6_BUTTON_A, 1u, 0, 0);
    if ((state.flags & GE_FILE_MODE_V6_STATE_FLAG_ERASE_CONFIRM) == 0u ||
        state.erase_choice != GE_FILE_MODE_V6_ERASE_CANCEL) {
        fail("erase confirmation default is not Cancel");
    }
    step(&state, &save, &frame, 4u, GE_FILE_MODE_V6_BUTTON_A, 1u, 0, 0);
    if (save.folders[0].bytes[18] == 0u ||
        (state.flags & GE_FILE_MODE_V6_STATE_FLAG_ERASE_CONFIRM) != 0u) {
        fail("default erase Cancel was not honored");
    }
    state.file_option = GE_FILE_MODE_V6_OPTION_ERASE;
    state.hovered_folder = 0u;
    step(&state, &save, &frame, 5u, GE_FILE_MODE_V6_BUTTON_A, 1u, 0, 0);
    step(&state, &save, &frame, 6u, GE_FILE_MODE_V6_BUTTON_R, 1u, 0, 0);
    step(&state, &save, &frame, 7u, GE_FILE_MODE_V6_BUTTON_A, 1u, 0, 0);
    if (save.folders[0].bytes[18] != 0u ||
        !has_event(&frame, GE_FILE_MODE_V6_EVENT_SAVE, GE_FILE_MODE_V6_SAVE_ERASE)) {
        fail("erase confirmation route mismatch");
    }
}

static void test_all_wallet_hit_regions(void)
{
    const int32_t centers[4] = {76, 172, 268, 364};
    uint32_t folder;

    for (folder = 0u; folder < GE_FILE_MODE_V6_FOLDER_COUNT; folder++) {
        GESaveSnapshotV1 save = blank_save();
        GEFileModeStateV6 state;
        GEFileModeFrameV6 frame;
        if (ge_file_mode_v6_init(&state, &save, &frame) != GE_STATUS_OK) {
            fail("wallet hit-test init failed");
        }
        state.cursor_x_q16 = centers[folder] * 65536;
        state.cursor_y_q16 = 168 * 65536;
        state.hovered_folder = GE_FILE_MODE_V6_INVALID_FOLDER;
        step(&state, &save, &frame, 1u, 0u, 1u, 6, 0);
        step(&state, &save, &frame, 2u, GE_FILE_MODE_V6_BUTTON_A, 1u, 0, 0);
        if (state.selected_folder != folder ||
            ge_file_mode_v6_folder_is_reset(&save.folders[folder]) != 0u) {
            fail("one of the four source wallet hit regions did not select");
        }
    }
}

static void test_icon_and_idle_routes(void)
{
    GESaveSnapshotV1 save = blank_save();
    GEFileModeStateV6 state;
    GEFileModeFrameV6 frame;
    uint64_t tick;

    if (ge_file_mode_v6_init(&state, &save, &frame) != GE_STATUS_OK) {
        fail("icon/idle init failed");
    }
    state.cursor_x_q16 = GE_FILE_MODE_V6_COPY_ICON_X * 65536;
    state.cursor_y_q16 = GE_FILE_MODE_V6_OPTION_ICON_Y * 65536;
    state.hovered_folder = GE_FILE_MODE_V6_INVALID_FOLDER;
    step(&state, &save, &frame, 1u, GE_FILE_MODE_V6_BUTTON_A, 1u, 0, 0);
    if (state.file_option != GE_FILE_MODE_V6_OPTION_COPY ||
        !has_event(&frame, GE_FILE_MODE_V6_EVENT_SFX,
                   GE_FILE_MODE_V6_SFX_DOOR_LOCK)) {
        fail("Copy icon hit-test mismatch");
    }
    if (ge_file_mode_v6_init(&state, &save, &frame) != GE_STATUS_OK) {
        fail("idle re-init failed");
    }
    for (tick = 1u; tick <= GE_FILE_MODE_V6_FILE_IDLE_THRESHOLD * 2u; tick++) {
        step(&state, &save, &frame, tick, 0u, 1u, 0, 0);
    }
    if (state.screen != GE_FILE_MODE_V6_SCREEN_LEGAL ||
        !has_event(&frame, GE_FILE_MODE_V6_EVENT_SCREEN,
                   GE_FILE_MODE_V6_SCREEN_LEGAL)) {
        fail("File Select idle route mismatch");
    }
}

static void test_odd_cursor_half_step(void)
{
    GESaveSnapshotV1 save = blank_save();
    GEFileModeStateV6 state;
    GEFileModeFrameV6 frame;

    if (ge_file_mode_v6_init(&state, &save, &frame) != GE_STATUS_OK) {
        fail("odd half-step init failed");
    }
    {
        GEFileModeInputV6 odd = input(1u, 1u, 0u, 1u, 0, 75, 1u);
        odd.clock_timer = 0u;
        if (ge_file_mode_v6_step(&state, &odd, &save, &frame) != GE_STATUS_OK) {
            fail("odd half-step call failed");
        }
    }
    /* adjust_stick(75)=70; the source cursor delta is exactly half of the
     * one-source-frame Q16 movement when clock_timer is zero. */
    if (state.cursor_y_q16 != 165 * 65536 + 188416) {
        fail("clock_timer zero did not produce the exact Q16 half-step");
    }
}

int main(void)
{
    if (sizeof(GESaveSnapshotV1) != 432u || sizeof(GEFileModeInputV6) != 72u ||
        sizeof(GEFileModeStateV6) != 104u || sizeof(GEFileModeEventV6) != 88u ||
        sizeof(GEFileModeFrameV6) != 2960u) {
        fail("C layout mismatch");
    }
    test_selection_and_mode();
    test_copy_and_erase();
    test_all_wallet_hit_regions();
    test_icon_and_idle_routes();
    test_odd_cursor_half_step();
    puts("goldeneye_file_mode_v6_smoke: PASS");
    return 0;
}
