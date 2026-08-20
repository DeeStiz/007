#include "ge_file_mode_v6.h"

#include <stddef.h>
#include <string.h>

#define GE_FILE_MODE_V6_HASH_OFFSET UINT64_C(1469598103934665603)
#define GE_FILE_MODE_V6_HASH_PRIME UINT64_C(1099511628211)
#define GE_FILE_MODE_V6_Q16_ONE INT32_C(65536)

static void ge_file_mode_v6_header(GEAbiHeaderV1 *header, uint32_t size)
{
    header->abi_version = GE_NATIVE_ABI_VERSION;
    header->struct_size = size;
}

static GEStatusV1 ge_file_mode_v6_validate_header(
    const GEAbiHeaderV1 *header,
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
    if (version != GE_FILE_MODE_V6_RECORD_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    return GE_STATUS_OK;
}

static uint64_t ge_file_mode_v6_hash_bytes(
    uint64_t hash,
    const void *bytes,
    size_t size)
{
    const uint8_t *cursor = (const uint8_t *)bytes;
    size_t index;

    for (index = 0u; index < size; index++) {
        hash ^= (uint64_t)cursor[index];
        hash *= GE_FILE_MODE_V6_HASH_PRIME;
    }
    return hash;
}

uint32_t ge_file_mode_v6_folder_is_reset(const GESaveFolderV1 *folder)
{
    if (folder == NULL) {
        return 1u;
    }
    return (folder->bytes[8] & UINT8_C(0x80)) != 0u ? 1u : 0u;
}

uint32_t ge_file_mode_v6_folder_has_completion(const GESaveFolderV1 *folder)
{
    size_t index;

    if (folder == NULL) {
        return 0u;
    }
    /* save_data.times starts at byte 18 and occupies 76 bytes. */
    for (index = 18u; index < 94u; index++) {
        if (folder->bytes[index] != 0u) {
            return 1u;
        }
    }
    return 0u;
}

static uint32_t ge_file_mode_v6_folder_number(const GESaveFolderV1 *folder)
{
    return folder == NULL ? GE_FILE_MODE_V6_INVALID_FOLDER :
        (uint32_t)(folder->bytes[8] & UINT8_C(0x07));
}

static uint32_t ge_file_mode_v6_folder_bond(const GESaveFolderV1 *folder)
{
    return folder == NULL ? GE_FILE_MODE_V6_INVALID_FOLDER :
        (uint32_t)((folder->bytes[8] & UINT8_C(0x60)) >> 5);
}

static uint32_t ge_file_mode_v6_folder_slot(const GESaveFolderV1 *folder)
{
    return folder == NULL ? GE_FILE_MODE_V6_INVALID_FOLDER :
        (uint32_t)((folder->bytes[8] & UINT8_C(0x18)) >> 3);
}

GEStatusV1 ge_file_mode_v6_validate_save(const GESaveSnapshotV1 *save)
{
    uint32_t index;

    if (save == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    {
        GEStatusV1 status = ge_file_mode_v6_validate_header(
            &save->header,
            (uint32_t)sizeof(*save),
            save->record_version);
        if (status != GE_STATUS_OK) {
            return status;
        }
    }
    if (save->flags != 0u || save->selected_folder >= GE_FILE_MODE_V6_FOLDER_COUNT ||
        save->selected_bond >= 4u || save->reserved0 != 0u || save->reserved1 != 0u ||
        save->reserved2 != 0u || save->reserved3 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    for (index = 0u; index < GE_FILE_MODE_V6_FOLDER_COUNT; index++) {
        const GESaveFolderV1 *folder = &save->folders[index];
        if (ge_file_mode_v6_folder_number(folder) >= GE_FILE_MODE_V6_FOLDER_COUNT ||
            ge_file_mode_v6_folder_slot(folder) >= 4u ||
            ge_file_mode_v6_folder_bond(folder) >= 4u ||
            folder->bytes[94] != 0u || folder->bytes[95] != 0u) {
            return GE_STATUS_MALFORMED_STREAM;
        }
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_file_mode_v6_validate_input(const GEFileModeInputV6 *input)
{
    GEStatusV1 status;

    if (input == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_file_mode_v6_validate_header(
        &input->header, (uint32_t)sizeof(*input), input->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if ((input->flags & ~GE_FILE_MODE_V6_INPUT_FLAG_MASK) != 0u ||
        (input->buttons_held & ~GE_FILE_MODE_V6_BUTTON_MASK) != 0u ||
        (input->buttons_pressed & ~GE_FILE_MODE_V6_BUTTON_MASK) != 0u ||
        (input->buttons_released & ~GE_FILE_MODE_V6_BUTTON_MASK) != 0u ||
        input->stick_x < -80 || input->stick_x > 80 ||
        input->stick_y < -80 || input->stick_y > 80 ||
        input->controller_count > 4u || input->clock_timer > 4u ||
        input->native_tick == 0u || input->sequence == 0u ||
        input->reference_tick != input->native_tick / 2u ||
        input->reserved0 != 0u || input->reserved1 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    if (((input->native_tick & 1u) == 0u) !=
        ((input->flags & GE_FILE_MODE_V6_INPUT_FLAG_SOURCE_ANCHOR) != 0u)) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

static uint32_t ge_file_mode_v6_screen_valid(uint32_t screen)
{
    return screen == GE_FILE_MODE_V6_SCREEN_LEGAL ||
        screen == GE_FILE_MODE_V6_SCREEN_FILE_SELECT ||
        screen == GE_FILE_MODE_V6_SCREEN_MODE_SELECT ||
        screen == GE_FILE_MODE_V6_SCREEN_SOLO_ROUTE ||
        screen == GE_FILE_MODE_V6_SCREEN_MULTI_ROUTE;
}

GEStatusV1 ge_file_mode_v6_validate_state(const GEFileModeStateV6 *state)
{
    GEStatusV1 status;

    if (state == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_file_mode_v6_validate_header(
        &state->header, (uint32_t)sizeof(*state), state->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (!ge_file_mode_v6_screen_valid(state->screen) ||
        (state->flags & ~GE_FILE_MODE_V6_STATE_FLAG_MASK) != 0u ||
        state->file_option > GE_FILE_MODE_V6_OPTION_ERASE ||
        state->erase_choice > GE_FILE_MODE_V6_ERASE_CANCEL ||
        state->selected_folder >= GE_FILE_MODE_V6_FOLDER_COUNT ||
        (state->hovered_folder >= GE_FILE_MODE_V6_FOLDER_COUNT &&
            state->hovered_folder != GE_FILE_MODE_V6_INVALID_FOLDER) ||
        state->mode_selection > 1u || state->controller_count > 4u ||
        state->cursor_x_q16 < GE_FILE_MODE_V6_CURSOR_MIN_X * GE_FILE_MODE_V6_Q16_ONE ||
        state->cursor_x_q16 > GE_FILE_MODE_V6_CURSOR_MAX_X * GE_FILE_MODE_V6_Q16_ONE ||
        state->cursor_y_q16 < GE_FILE_MODE_V6_CURSOR_MIN_Y * GE_FILE_MODE_V6_Q16_ONE ||
        state->cursor_y_q16 > GE_FILE_MODE_V6_CURSOR_MAX_Y * GE_FILE_MODE_V6_Q16_ONE ||
        state->route > GE_FILE_MODE_V6_SCREEN_MULTI_ROUTE ||
        state->reserved0 != 0u || state->reserved1 != 0u || state->reserved2 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    if ((state->flags & GE_FILE_MODE_V6_STATE_FLAG_ERASE_CONFIRM) != 0u &&
        state->screen != GE_FILE_MODE_V6_SCREEN_FILE_SELECT) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

static GEStatusV1 ge_file_mode_v6_validate_event(const GEFileModeEventV6 *event)
{
    GEStatusV1 status;

    if (event == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_file_mode_v6_validate_header(
        &event->header, (uint32_t)sizeof(*event), event->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (event->kind > GE_FILE_MODE_V6_EVENT_ROUTE ||
        event->screen > GE_FILE_MODE_V6_SCREEN_MULTI_ROUTE ||
        event->target_screen > GE_FILE_MODE_V6_SCREEN_MULTI_ROUTE ||
        (event->folder >= GE_FILE_MODE_V6_FOLDER_COUNT &&
            event->folder != GE_FILE_MODE_V6_INVALID_FOLDER) ||
        (event->destination_folder >= GE_FILE_MODE_V6_FOLDER_COUNT &&
            event->destination_folder != GE_FILE_MODE_V6_INVALID_FOLDER) ||
        event->reserved0 != 0u || event->reserved1 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_file_mode_v6_validate_frame(const GEFileModeFrameV6 *frame)
{
    uint32_t index;
    GEStatusV1 status;

    if (frame == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_file_mode_v6_validate_header(
        &frame->header, (uint32_t)sizeof(*frame), frame->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (frame->event_count > GE_FILE_MODE_V6_MAX_EVENTS ||
        frame->overflow_flags != 0u || frame->reserved0 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    status = ge_file_mode_v6_validate_state(&frame->state);
    if (status != GE_STATUS_OK) {
        return status;
    }
    for (index = 0u; index < frame->event_count; index++) {
        status = ge_file_mode_v6_validate_event(&frame->events[index]);
        if (status != GE_STATUS_OK) {
            return status;
        }
    }
    return GE_STATUS_OK;
}

static void ge_file_mode_v6_init_state(
    GEFileModeStateV6 *state,
    const GESaveSnapshotV1 *save)
{
    memset(state, 0, sizeof(*state));
    ge_file_mode_v6_header(&state->header, (uint32_t)sizeof(*state));
    state->record_version = GE_FILE_MODE_V6_RECORD_VERSION;
    state->screen = GE_FILE_MODE_V6_SCREEN_FILE_SELECT;
    state->file_option = GE_FILE_MODE_V6_OPTION_SELECT;
    state->erase_choice = GE_FILE_MODE_V6_ERASE_CANCEL;
    state->selected_folder = save->selected_folder;
    state->hovered_folder = save->selected_folder;
    state->controller_count = 1u;
    state->cursor_x_q16 = GE_FILE_MODE_V6_CURSOR_INITIAL_X * GE_FILE_MODE_V6_Q16_ONE;
    state->cursor_y_q16 = GE_FILE_MODE_V6_CURSOR_INITIAL_Y * GE_FILE_MODE_V6_Q16_ONE;
}

static void ge_file_mode_v6_init_frame(GEFileModeFrameV6 *frame)
{
    memset(frame, 0, sizeof(*frame));
    ge_file_mode_v6_header(&frame->header, (uint32_t)sizeof(*frame));
    frame->record_version = GE_FILE_MODE_V6_RECORD_VERSION;
    frame->state_hash = GE_FILE_MODE_V6_HASH_OFFSET;
    frame->event_hash = GE_FILE_MODE_V6_HASH_OFFSET;
}

static uint64_t ge_file_mode_v6_state_hash(const GEFileModeStateV6 *state)
{
    return ge_file_mode_v6_hash_bytes(
        GE_FILE_MODE_V6_HASH_OFFSET,
        state,
        sizeof(*state));
}

static void ge_file_mode_v6_finish_frame(
    GEFileModeFrameV6 *frame,
    const GEFileModeStateV6 *state)
{
    frame->state = *state;
    frame->state_hash = ge_file_mode_v6_state_hash(state);
    if (frame->event_count == 0u) {
        frame->event_hash = GE_FILE_MODE_V6_HASH_OFFSET;
    }
}

static GEStatusV1 ge_file_mode_v6_append_event(
    GEFileModeFrameV6 *frame,
    const GEFileModeStateV6 *state,
    uint32_t kind,
    uint32_t target_screen,
    uint32_t command,
    uint32_t folder,
    uint32_t destination_folder,
    uint32_t value0,
    uint32_t value1)
{
    GEFileModeEventV6 *event;

    if (frame->event_count >= GE_FILE_MODE_V6_MAX_EVENTS) {
        frame->overflow_flags |= 1u;
        return GE_STATUS_INTERNAL_ERROR;
    }
    event = &frame->events[frame->event_count++];
    memset(event, 0, sizeof(*event));
    ge_file_mode_v6_header(&event->header, (uint32_t)sizeof(*event));
    event->record_version = GE_FILE_MODE_V6_RECORD_VERSION;
    event->kind = kind;
    event->screen = state->screen;
    event->target_screen = target_screen;
    event->command = command;
    event->folder = folder;
    event->destination_folder = destination_folder;
    event->value0 = value0;
    event->value1 = value1;
    event->x_q16 = state->cursor_x_q16;
    event->y_q16 = state->cursor_y_q16;
    event->native_tick = state->native_tick;
    event->reference_tick = state->reference_tick;
    event->sequence = ++((GEFileModeStateV6 *)state)->event_sequence;
    if (frame->event_count == 1u) {
        frame->event_hash = GE_FILE_MODE_V6_HASH_OFFSET;
    }
    frame->event_hash = ge_file_mode_v6_hash_bytes(
        frame->event_hash, event, sizeof(*event));
    return GE_STATUS_OK;
}

static int32_t ge_file_mode_v6_adjust_stick(int16_t value)
{
    int32_t adjusted = (int32_t)value;

    if (adjusted < -5) {
        adjusted += 5;
    } else if (adjusted >= 6) {
        adjusted -= 5;
    } else {
        adjusted = 0;
    }
    if (adjusted > 70) {
        adjusted = 70;
    } else if (adjusted < -70) {
        adjusted = -70;
    }
    return adjusted;
}

static void ge_file_mode_v6_move_cursor(
    GEFileModeStateV6 *state,
    int16_t stick_x,
    int16_t stick_y,
    uint32_t delta)
{
    int32_t x = ge_file_mode_v6_adjust_stick(stick_x);
    int32_t y = ge_file_mode_v6_adjust_stick(stick_y);
    /* Native 120 Hz callers use clock_timer==0 for the odd paired preview.
     * Preserve the source endpoint on the following even anchor by applying
     * exactly half of one source cursor delta here.  The paired Swift
     * authority rebases the non-committed preview before that even step. */
    int64_t delta_q16 = delta == 0u
        ? (GE_FILE_MODE_V6_Q16_ONE / 2)
        : (int64_t)delta * GE_FILE_MODE_V6_Q16_ONE;

    if (x > 0) {
        state->cursor_x_q16 += (int32_t)((((int64_t)x * 3 * delta_q16) / 40) +
                                         (delta_q16 / 2));
    } else if (x < 0) {
        state->cursor_x_q16 += (int32_t)((((int64_t)x * 3 * delta_q16) / 40) -
                                         (delta_q16 / 2));
    }
    if (y > 0) {
        state->cursor_y_q16 += (int32_t)((((int64_t)y * 3 * delta_q16) / 40) +
                                         (delta_q16 / 2));
    } else if (y < 0) {
        state->cursor_y_q16 += (int32_t)((((int64_t)y * 3 * delta_q16) / 40) -
                                         (delta_q16 / 2));
    }
    if (state->cursor_x_q16 < GE_FILE_MODE_V6_CURSOR_MIN_X * GE_FILE_MODE_V6_Q16_ONE) {
        state->cursor_x_q16 = GE_FILE_MODE_V6_CURSOR_MIN_X * GE_FILE_MODE_V6_Q16_ONE;
    } else if (state->cursor_x_q16 > GE_FILE_MODE_V6_CURSOR_MAX_X * GE_FILE_MODE_V6_Q16_ONE) {
        state->cursor_x_q16 = GE_FILE_MODE_V6_CURSOR_MAX_X * GE_FILE_MODE_V6_Q16_ONE;
    }
    if (state->cursor_y_q16 < GE_FILE_MODE_V6_CURSOR_MIN_Y * GE_FILE_MODE_V6_Q16_ONE) {
        state->cursor_y_q16 = GE_FILE_MODE_V6_CURSOR_MIN_Y * GE_FILE_MODE_V6_Q16_ONE;
    } else if (state->cursor_y_q16 > GE_FILE_MODE_V6_CURSOR_MAX_Y * GE_FILE_MODE_V6_Q16_ONE) {
        state->cursor_y_q16 = GE_FILE_MODE_V6_CURSOR_MAX_Y * GE_FILE_MODE_V6_Q16_ONE;
    }
}

static uint32_t ge_file_mode_v6_cursor_integer(int32_t value_q16)
{
    return (uint32_t)((value_q16 + (GE_FILE_MODE_V6_Q16_ONE / 2)) /
                      GE_FILE_MODE_V6_Q16_ONE);
}

static uint32_t ge_file_mode_v6_hovered_folder(const GEFileModeStateV6 *state)
{
    uint32_t x = ge_file_mode_v6_cursor_integer(state->cursor_x_q16);
    uint32_t y = ge_file_mode_v6_cursor_integer(state->cursor_y_q16);

    /* These are the authored logical hit bounds shared by the native layout
     * and the source constructor: four 80x112 wallet regions in a 440x330
     * canvas.  The source model itself remains a renderer concern. */
    if (y < GE_FILE_MODE_V6_WALLET_MIN_Y || y > GE_FILE_MODE_V6_WALLET_MAX_Y) {
        return GE_FILE_MODE_V6_INVALID_FOLDER;
    }
    if (x >= GE_FILE_MODE_V6_WALLET0_MIN_X && x <= GE_FILE_MODE_V6_WALLET0_MAX_X) {
        return 0u;
    }
    if (x >= GE_FILE_MODE_V6_WALLET1_MIN_X && x <= GE_FILE_MODE_V6_WALLET1_MAX_X) {
        return 1u;
    }
    if (x >= GE_FILE_MODE_V6_WALLET2_MIN_X && x <= GE_FILE_MODE_V6_WALLET2_MAX_X) {
        return 2u;
    }
    if (x >= GE_FILE_MODE_V6_WALLET3_MIN_X && x <= GE_FILE_MODE_V6_WALLET3_MAX_X) {
        return 3u;
    }
    return GE_FILE_MODE_V6_INVALID_FOLDER;
}

static uint32_t ge_file_mode_v6_cursor_in_icon(
    const GEFileModeStateV6 *state,
    int32_t center_x)
{
    uint32_t x = ge_file_mode_v6_cursor_integer(state->cursor_x_q16);
    uint32_t y = ge_file_mode_v6_cursor_integer(state->cursor_y_q16);
    if (y < GE_FILE_MODE_V6_OPTION_MIN_Y || y > GE_FILE_MODE_V6_OPTION_MAX_Y) {
        return 0u;
    }
    if (center_x == GE_FILE_MODE_V6_COPY_ICON_X) {
        return x >= GE_FILE_MODE_V6_COPY_MIN_X && x <= GE_FILE_MODE_V6_COPY_MAX_X;
    }
    return x >= GE_FILE_MODE_V6_ERASE_MIN_X && x <= GE_FILE_MODE_V6_ERASE_MAX_X;
}

static void ge_file_mode_v6_create_folder(GESaveFolderV1 *folder, uint32_t index)
{
    memset(folder, 0, sizeof(*folder));
    folder->bytes[8] = (uint8_t)(index & 0x07u);
    folder->bytes[10] = UINT8_C(0xff);
    folder->bytes[11] = UINT8_C(0xff);
    folder->bytes[12] = 0u;
    folder->bytes[13] = UINT8_C(0x3a);
}

static void ge_file_mode_v6_set_folder_number(GESaveFolderV1 *folder, uint32_t index)
{
    folder->bytes[8] = (uint8_t)((folder->bytes[8] & UINT8_C(0xf8)) | (index & 0x07u));
}

static void ge_file_mode_v6_set_bond(GESaveFolderV1 *folder, uint32_t bond)
{
    folder->bytes[8] = (uint8_t)((folder->bytes[8] & UINT8_C(0x9f)) |
                                 ((bond << 5) & UINT8_C(0x60)));
}

static void ge_file_mode_v6_set_reset(GESaveFolderV1 *folder, uint32_t reset)
{
    if (reset != 0u) {
        folder->bytes[8] |= UINT8_C(0x80);
    } else {
        folder->bytes[8] &= UINT8_C(0x7f);
    }
}

static uint32_t ge_file_mode_v6_first_blank(
    const GESaveSnapshotV1 *save,
    uint32_t source)
{
    uint32_t index;

    for (index = 0u; index < GE_FILE_MODE_V6_FOLDER_COUNT; index++) {
        if (index == source) {
            continue;
        }
        if (ge_file_mode_v6_folder_is_reset(&save->folders[index]) != 0u ||
            ge_file_mode_v6_folder_has_completion(&save->folders[index]) == 0u) {
            return index;
        }
    }
    return GE_FILE_MODE_V6_INVALID_FOLDER;
}

static uint32_t ge_file_mode_v6_is_active_stick(const GEFileModeInputV6 *input)
{
    return input->stick_x < -5 || input->stick_x >= 6 ||
        input->stick_y < -5 || input->stick_y >= 6;
}

static void ge_file_mode_v6_update_mode_selection(GEFileModeStateV6 *state)
{
    uint32_t y = ge_file_mode_v6_cursor_integer(state->cursor_y_q16);
    state->mode_selection = (state->controller_count >= 2u && y >= 243u) ? 1u : 0u;
}

static GEStatusV1 ge_file_mode_v6_sfx(
    GEFileModeFrameV6 *frame,
    GEFileModeStateV6 *state,
    uint32_t sfx)
{
    return ge_file_mode_v6_append_event(
        frame, state, GE_FILE_MODE_V6_EVENT_SFX, state->screen, sfx,
        GE_FILE_MODE_V6_INVALID_FOLDER, GE_FILE_MODE_V6_INVALID_FOLDER, 0u, 0u);
}

static GEStatusV1 ge_file_mode_v6_save_event(
    GEFileModeFrameV6 *frame,
    GEFileModeStateV6 *state,
    uint32_t operation,
    uint32_t folder,
    uint32_t destination)
{
    return ge_file_mode_v6_append_event(
        frame, state, GE_FILE_MODE_V6_EVENT_SAVE, state->screen, operation,
        folder, destination, 0u, 0u);
}

static GEStatusV1 ge_file_mode_v6_screen_event(
    GEFileModeFrameV6 *frame,
    GEFileModeStateV6 *state,
    uint32_t target)
{
    return ge_file_mode_v6_append_event(
        frame, state, GE_FILE_MODE_V6_EVENT_SCREEN, target, 0u,
        GE_FILE_MODE_V6_INVALID_FOLDER, GE_FILE_MODE_V6_INVALID_FOLDER, 0u, 0u);
}

static GEStatusV1 ge_file_mode_v6_route_event(
    GEFileModeFrameV6 *frame,
    GEFileModeStateV6 *state,
    uint32_t target)
{
    return ge_file_mode_v6_append_event(
        frame, state, GE_FILE_MODE_V6_EVENT_ROUTE, target, target,
        GE_FILE_MODE_V6_INVALID_FOLDER, GE_FILE_MODE_V6_INVALID_FOLDER, 0u, 0u);
}

static GEStatusV1 ge_file_mode_v6_update_file(
    GEFileModeStateV6 *state,
    const GEFileModeInputV6 *input,
    GESaveSnapshotV1 *save,
    GEFileModeFrameV6 *frame)
{
    uint32_t confirm = (input->buttons_pressed & GE_FILE_MODE_V6_CONFIRM_MASK) != 0u;
    uint32_t cancel = (input->buttons_pressed & GE_FILE_MODE_V6_CANCEL_MASK) != 0u;

    if ((state->flags & GE_FILE_MODE_V6_STATE_FLAG_ERASE_CONFIRM) != 0u) {
        if ((input->buttons_pressed & (GE_FILE_MODE_V6_BUTTON_L |
                                       GE_FILE_MODE_V6_BUTTON_DPAD_LEFT |
                                       GE_FILE_MODE_V6_BUTTON_C_LEFT)) != 0u ||
            input->stick_x < -45) {
            state->erase_choice = GE_FILE_MODE_V6_ERASE_CANCEL;
            (void)ge_file_mode_v6_sfx(frame, state,
                                      GE_FILE_MODE_V6_SFX_OPTION_CLICK2);
        } else if ((input->buttons_pressed & (GE_FILE_MODE_V6_BUTTON_R |
                                              GE_FILE_MODE_V6_BUTTON_DPAD_RIGHT |
                                              GE_FILE_MODE_V6_BUTTON_C_RIGHT)) != 0u ||
                   input->stick_x >= 46) {
            state->erase_choice = GE_FILE_MODE_V6_ERASE_CONFIRM;
            (void)ge_file_mode_v6_sfx(frame, state,
                                      GE_FILE_MODE_V6_SFX_OPTION_CLICK2);
        }
        if (cancel) {
            state->flags &= ~GE_FILE_MODE_V6_STATE_FLAG_ERASE_CONFIRM;
            state->erase_choice = GE_FILE_MODE_V6_ERASE_CANCEL;
            (void)ge_file_mode_v6_sfx(frame, state,
                                      GE_FILE_MODE_V6_SFX_GUN_M60AMMGUN_3);
        } else if (confirm) {
            if (state->erase_choice == GE_FILE_MODE_V6_ERASE_CONFIRM) {
                ge_file_mode_v6_create_folder(
                    &save->folders[state->selected_folder], state->selected_folder);
                ge_file_mode_v6_set_reset(
                    &save->folders[state->selected_folder], 0u);
                ge_file_mode_v6_set_bond(
                    &save->folders[state->selected_folder], state->selected_folder);
                (void)ge_file_mode_v6_save_event(
                    frame, state, GE_FILE_MODE_V6_SAVE_ERASE,
                    state->selected_folder, GE_FILE_MODE_V6_INVALID_FOLDER);
            }
            state->flags &= ~GE_FILE_MODE_V6_STATE_FLAG_ERASE_CONFIRM;
            state->erase_choice = GE_FILE_MODE_V6_ERASE_CANCEL;
            state->file_option = GE_FILE_MODE_V6_OPTION_SELECT;
            (void)ge_file_mode_v6_sfx(frame, state,
                                      GE_FILE_MODE_V6_SFX_GUN_M60AMMGUN_3);
        }
        return GE_STATUS_OK;
    }

    ge_file_mode_v6_move_cursor(state, input->stick_x, input->stick_y, input->clock_timer);
    if (ge_file_mode_v6_is_active_stick(input) != 0u) {
        state->hovered_folder = ge_file_mode_v6_hovered_folder(state);
    }
    if (ge_file_mode_v6_is_active_stick(input) != 0u ||
        input->buttons_pressed != 0u) {
        state->idle_timer = 0u;
    } else if ((input->flags & GE_FILE_MODE_V6_INPUT_FLAG_SOURCE_ANCHOR) != 0u) {
        state->idle_timer += input->clock_timer;
    }

    if (confirm) {
        const uint32_t folder = state->hovered_folder;
        if (folder != GE_FILE_MODE_V6_INVALID_FOLDER &&
            state->file_option == GE_FILE_MODE_V6_OPTION_SELECT) {
            if (ge_file_mode_v6_folder_is_reset(&save->folders[folder]) != 0u) {
                ge_file_mode_v6_create_folder(&save->folders[folder], folder);
                ge_file_mode_v6_set_reset(&save->folders[folder], 0u);
                ge_file_mode_v6_set_bond(&save->folders[folder], folder);
                (void)ge_file_mode_v6_save_event(
                    frame, state, GE_FILE_MODE_V6_SAVE_CREATE,
                    folder, GE_FILE_MODE_V6_INVALID_FOLDER);
            }
            save->selected_folder = folder;
            save->selected_bond = ge_file_mode_v6_folder_bond(&save->folders[folder]);
            state->selected_folder = folder;
            state->file_option = GE_FILE_MODE_V6_OPTION_SELECT;
            (void)ge_file_mode_v6_save_event(
                frame, state, GE_FILE_MODE_V6_SAVE_SELECT,
                folder, GE_FILE_MODE_V6_INVALID_FOLDER);
            (void)ge_file_mode_v6_screen_event(
                frame, state, GE_FILE_MODE_V6_SCREEN_MODE_SELECT);
            state->screen = GE_FILE_MODE_V6_SCREEN_MODE_SELECT;
            state->cursor_x_q16 = GE_FILE_MODE_V6_MODE_CURSOR_X * GE_FILE_MODE_V6_Q16_ONE;
            state->cursor_y_q16 = GE_FILE_MODE_V6_MODE_CURSOR_SOLO_Y * GE_FILE_MODE_V6_Q16_ONE;
            state->idle_timer = 0u;
            (void)ge_file_mode_v6_sfx(frame, state,
                                      GE_FILE_MODE_V6_SFX_PAPER_TURN);
        } else if (folder != GE_FILE_MODE_V6_INVALID_FOLDER &&
                   state->file_option == GE_FILE_MODE_V6_OPTION_COPY) {
            uint32_t destination = GE_FILE_MODE_V6_INVALID_FOLDER;
            if (ge_file_mode_v6_folder_is_reset(&save->folders[folder]) == 0u &&
                ge_file_mode_v6_folder_has_completion(&save->folders[folder]) != 0u) {
                destination = ge_file_mode_v6_first_blank(save, folder);
            }
            if (destination != GE_FILE_MODE_V6_INVALID_FOLDER) {
                save->folders[destination] = save->folders[folder];
                ge_file_mode_v6_set_folder_number(&save->folders[destination], destination);
                ge_file_mode_v6_set_reset(&save->folders[destination], 0u);
                (void)ge_file_mode_v6_save_event(
                    frame, state, GE_FILE_MODE_V6_SAVE_COPY,
                    folder, destination);
            } else {
                (void)ge_file_mode_v6_save_event(
                    frame, state, GE_FILE_MODE_V6_SAVE_COPY_NOOP,
                    folder, GE_FILE_MODE_V6_INVALID_FOLDER);
            }
            state->file_option = GE_FILE_MODE_V6_OPTION_SELECT;
            (void)ge_file_mode_v6_sfx(frame, state,
                                      GE_FILE_MODE_V6_SFX_COPY_FILE);
        } else if (folder != GE_FILE_MODE_V6_INVALID_FOLDER &&
                   state->file_option == GE_FILE_MODE_V6_OPTION_ERASE) {
            if (ge_file_mode_v6_folder_has_completion(&save->folders[folder]) != 0u) {
                state->selected_folder = folder;
                state->flags |= GE_FILE_MODE_V6_STATE_FLAG_ERASE_CONFIRM;
                state->erase_choice = GE_FILE_MODE_V6_ERASE_CANCEL;
            } else {
                (void)ge_file_mode_v6_save_event(
                    frame, state, GE_FILE_MODE_V6_SAVE_ERASE_NOOP,
                    folder, GE_FILE_MODE_V6_INVALID_FOLDER);
                state->file_option = GE_FILE_MODE_V6_OPTION_SELECT;
            }
            (void)ge_file_mode_v6_sfx(frame, state,
                                      GE_FILE_MODE_V6_SFX_OPTION_CLICK2);
        } else if (state->file_option == GE_FILE_MODE_V6_OPTION_SELECT &&
                   ge_file_mode_v6_cursor_in_icon(
                       state, GE_FILE_MODE_V6_COPY_ICON_X) != 0u) {
            state->file_option = GE_FILE_MODE_V6_OPTION_COPY;
            (void)ge_file_mode_v6_sfx(frame, state,
                                      GE_FILE_MODE_V6_SFX_DOOR_LOCK);
        } else if (state->file_option == GE_FILE_MODE_V6_OPTION_SELECT &&
                   ge_file_mode_v6_cursor_in_icon(
                       state, GE_FILE_MODE_V6_ERASE_ICON_X) != 0u) {
            state->file_option = GE_FILE_MODE_V6_OPTION_ERASE;
            (void)ge_file_mode_v6_sfx(frame, state,
                                      GE_FILE_MODE_V6_SFX_DOOR_LOCK);
        } else if (state->file_option != GE_FILE_MODE_V6_OPTION_SELECT) {
            state->file_option = GE_FILE_MODE_V6_OPTION_SELECT;
            (void)ge_file_mode_v6_sfx(frame, state,
                                      GE_FILE_MODE_V6_SFX_GUN_M60AMMGUN_3);
        }
    } else if (cancel && state->file_option != GE_FILE_MODE_V6_OPTION_SELECT) {
        state->file_option = GE_FILE_MODE_V6_OPTION_SELECT;
        (void)ge_file_mode_v6_sfx(frame, state,
                                  GE_FILE_MODE_V6_SFX_GUN_M60AMMGUN_3);
    }

    if (state->idle_timer >= GE_FILE_MODE_V6_FILE_IDLE_THRESHOLD) {
        (void)ge_file_mode_v6_screen_event(
            frame, state, GE_FILE_MODE_V6_SCREEN_LEGAL);
        state->screen = GE_FILE_MODE_V6_SCREEN_LEGAL;
        state->idle_timer = 0u;
    }
    return GE_STATUS_OK;
}

static GEStatusV1 ge_file_mode_v6_update_mode(
    GEFileModeStateV6 *state,
    const GEFileModeInputV6 *input,
    GEFileModeFrameV6 *frame)
{
    uint32_t confirm = (input->buttons_pressed & GE_FILE_MODE_V6_CONFIRM_MASK) != 0u;
    uint32_t cancel = (input->buttons_pressed & GE_FILE_MODE_V6_CANCEL_MASK) != 0u;

    ge_file_mode_v6_move_cursor(state, input->stick_x, input->stick_y, input->clock_timer);
    state->controller_count = input->controller_count;
    state->flags = state->controller_count >= 2u ?
        state->flags | GE_FILE_MODE_V6_STATE_FLAG_MULTI_AVAILABLE :
        state->flags & ~GE_FILE_MODE_V6_STATE_FLAG_MULTI_AVAILABLE;
    ge_file_mode_v6_update_mode_selection(state);
    if (cancel) {
        (void)ge_file_mode_v6_screen_event(
            frame, state, GE_FILE_MODE_V6_SCREEN_FILE_SELECT);
        state->screen = GE_FILE_MODE_V6_SCREEN_FILE_SELECT;
        state->cursor_x_q16 = GE_FILE_MODE_V6_CURSOR_INITIAL_X * GE_FILE_MODE_V6_Q16_ONE;
        state->cursor_y_q16 = GE_FILE_MODE_V6_CURSOR_INITIAL_Y * GE_FILE_MODE_V6_Q16_ONE;
        (void)ge_file_mode_v6_sfx(frame, state,
                                  GE_FILE_MODE_V6_SFX_DOOR_METAL_CLOSE2);
    } else if (confirm) {
        uint32_t target = state->mode_selection != 0u && state->controller_count >= 2u ?
            GE_FILE_MODE_V6_SCREEN_MULTI_ROUTE : GE_FILE_MODE_V6_SCREEN_SOLO_ROUTE;
        state->route = target;
        state->flags |= GE_FILE_MODE_V6_STATE_FLAG_ROUTE_PENDING;
        (void)ge_file_mode_v6_route_event(frame, state, target);
        state->screen = target;
        (void)ge_file_mode_v6_sfx(frame, state,
                                  GE_FILE_MODE_V6_SFX_DOOR_METAL_CLOSE);
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_file_mode_v6_init(
    GEFileModeStateV6 *state,
    const GESaveSnapshotV1 *save,
    GEFileModeFrameV6 *out_frame)
{
    GEStatusV1 status;

    if (state == NULL || save == NULL || out_frame == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_file_mode_v6_validate_save(save);
    if (status != GE_STATUS_OK) {
        return status;
    }
    ge_file_mode_v6_init_state(state, save);
    ge_file_mode_v6_init_frame(out_frame);
    ge_file_mode_v6_finish_frame(out_frame, state);
    return ge_file_mode_v6_validate_frame(out_frame);
}

GEStatusV1 ge_file_mode_v6_step(
    GEFileModeStateV6 *state,
    const GEFileModeInputV6 *input,
    GESaveSnapshotV1 *save,
    GEFileModeFrameV6 *out_frame)
{
    GEStatusV1 status;

    if (state == NULL || input == NULL || save == NULL || out_frame == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_file_mode_v6_validate_state(state);
    if (status != GE_STATUS_OK) {
        return status;
    }
    status = ge_file_mode_v6_validate_input(input);
    if (status != GE_STATUS_OK) {
        return status;
    }
    status = ge_file_mode_v6_validate_save(save);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (input->native_tick != state->native_tick + 1u ||
        input->sequence <= state->last_input_sequence) {
        return GE_STATUS_INVALID_STATE;
    }

    ge_file_mode_v6_init_frame(out_frame);
    state->native_tick = input->native_tick;
    state->reference_tick = input->reference_tick;
    state->controller_count = input->controller_count;
    if ((input->flags & GE_FILE_MODE_V6_INPUT_FLAG_FOCUSED) == 0u) {
        state->flags |= GE_FILE_MODE_V6_STATE_FLAG_INPUT_SUPPRESSED;
        state->last_input_sequence = input->sequence;
        ge_file_mode_v6_finish_frame(out_frame, state);
        return ge_file_mode_v6_validate_frame(out_frame);
    }
    state->flags &= ~GE_FILE_MODE_V6_STATE_FLAG_INPUT_SUPPRESSED;
    state->last_input_sequence = input->sequence;
    state->flags = state->controller_count >= 2u ?
        state->flags | GE_FILE_MODE_V6_STATE_FLAG_MULTI_AVAILABLE :
        state->flags & ~GE_FILE_MODE_V6_STATE_FLAG_MULTI_AVAILABLE;

    if (state->screen == GE_FILE_MODE_V6_SCREEN_FILE_SELECT) {
        status = ge_file_mode_v6_update_file(state, input, save, out_frame);
    } else if (state->screen == GE_FILE_MODE_V6_SCREEN_MODE_SELECT) {
        status = ge_file_mode_v6_update_mode(state, input, out_frame);
    } else {
        status = GE_STATUS_OK;
    }
    if (status != GE_STATUS_OK) {
        return status;
    }
    ge_file_mode_v6_finish_frame(out_frame, state);
    return ge_file_mode_v6_validate_frame(out_frame);
}
