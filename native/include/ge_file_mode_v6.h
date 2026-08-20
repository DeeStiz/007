#ifndef GE_FILE_MODE_V6_H
#define GE_FILE_MODE_V6_H

/*
 * Source-owned File Select and Mode Select seam.
 *
 * This is an additive value-only boundary.  The menu implementation accepts
 * copied input and a copied semantic save image; it never retains a pointer,
 * filesystem path, controller object, or renderer object.  The source save
 * representation is intentionally kept as four fixed 96-byte folder records
 * so Swift's SaveStore can remain the sole persistence owner while C keeps the
 * source menu decisions and command ordering authoritative.  This 432-byte
 * semantic projection is not the 596-byte GESWSAVE wire record: SaveStore's
 * 64-byte header, 4-byte payload selector, and per-folder reserved bytes
 * remain outside this ABI and are never rewritten here.
 */

#include <stdint.h>

#include "ge_native_foundation.h"

#ifdef __cplusplus
extern "C" {
#endif

#define GE_FILE_MODE_V6_CONTRACT_VERSION ((uint32_t)6u)
#define GE_FILE_MODE_V6_RECORD_VERSION ((uint32_t)1u)
#define GE_FILE_MODE_V6_FOLDER_COUNT ((uint32_t)4u)
#define GE_FILE_MODE_V6_FOLDER_BYTE_COUNT ((uint32_t)96u)
#define GE_FILE_MODE_V6_MAX_EVENTS ((uint32_t)32u)
#define GE_FILE_MODE_V6_INVALID_FOLDER UINT32_MAX

#define GE_FILE_MODE_V6_CANVAS_WIDTH ((int32_t)440)
#define GE_FILE_MODE_V6_CANVAS_HEIGHT ((int32_t)330)
#define GE_FILE_MODE_V6_CURSOR_MIN_X ((int32_t)20)
#define GE_FILE_MODE_V6_CURSOR_MAX_X ((int32_t)420)
#define GE_FILE_MODE_V6_CURSOR_MIN_Y ((int32_t)20)
#define GE_FILE_MODE_V6_CURSOR_MAX_Y ((int32_t)310)
#define GE_FILE_MODE_V6_CURSOR_INITIAL_X ((int32_t)220)
#define GE_FILE_MODE_V6_CURSOR_INITIAL_Y ((int32_t)165)
#define GE_FILE_MODE_V6_MODE_CURSOR_X ((int32_t)126)
#define GE_FILE_MODE_V6_MODE_CURSOR_SOLO_Y ((int32_t)226)
#define GE_FILE_MODE_V6_MODE_CURSOR_MULTI_Y ((int32_t)258)
#define GE_FILE_MODE_V6_COPY_ICON_X ((int32_t)225)
#define GE_FILE_MODE_V6_ERASE_ICON_X ((int32_t)335)
#define GE_FILE_MODE_V6_OPTION_ICON_Y ((int32_t)285)
#define GE_FILE_MODE_V6_WALLET_MIN_Y ((int32_t)112)
#define GE_FILE_MODE_V6_WALLET_MAX_Y ((int32_t)224)
#define GE_FILE_MODE_V6_WALLET0_MIN_X ((int32_t)36)
#define GE_FILE_MODE_V6_WALLET0_MAX_X ((int32_t)116)
#define GE_FILE_MODE_V6_WALLET1_MIN_X ((int32_t)132)
#define GE_FILE_MODE_V6_WALLET1_MAX_X ((int32_t)212)
#define GE_FILE_MODE_V6_WALLET2_MIN_X ((int32_t)228)
#define GE_FILE_MODE_V6_WALLET2_MAX_X ((int32_t)308)
#define GE_FILE_MODE_V6_WALLET3_MIN_X ((int32_t)324)
#define GE_FILE_MODE_V6_WALLET3_MAX_X ((int32_t)404)
#define GE_FILE_MODE_V6_SELECT_MIN_X ((int32_t)49)
#define GE_FILE_MODE_V6_SELECT_MAX_X ((int32_t)171)
#define GE_FILE_MODE_V6_OPTION_MIN_Y ((int32_t)271)
#define GE_FILE_MODE_V6_OPTION_MAX_Y ((int32_t)299)
#define GE_FILE_MODE_V6_COPY_MIN_X ((int32_t)209)
#define GE_FILE_MODE_V6_COPY_MAX_X ((int32_t)241)
#define GE_FILE_MODE_V6_ERASE_MIN_X ((int32_t)319)
#define GE_FILE_MODE_V6_ERASE_MAX_X ((int32_t)351)
#define GE_FILE_MODE_V6_TABS_LEFT_EDGE ((int32_t)390)
#define GE_FILE_MODE_V6_PREVIOUS_TAB_TOP ((int32_t)223)
#define GE_FILE_MODE_V6_FILE_IDLE_THRESHOLD ((uint32_t)1801u)

/* Source folder positions from front.c, retained as fixed Q16 world values. */
#define GE_FILE_MODE_V6_FOLDER0_WORLD_X_Q16 ((int32_t)-58982400)
#define GE_FILE_MODE_V6_FOLDER0_WORLD_Y_Q16 ((int32_t)52428800)
#define GE_FILE_MODE_V6_FOLDER1_WORLD_X_Q16 ((int32_t)117964800)
#define GE_FILE_MODE_V6_FOLDER1_WORLD_Y_Q16 ((int32_t)52428800)
#define GE_FILE_MODE_V6_FOLDER2_WORLD_X_Q16 ((int32_t)-117964800)
#define GE_FILE_MODE_V6_FOLDER2_WORLD_Y_Q16 ((int32_t)-13107200)
#define GE_FILE_MODE_V6_FOLDER3_WORLD_X_Q16 ((int32_t)58982400)
#define GE_FILE_MODE_V6_FOLDER3_WORLD_Y_Q16 ((int32_t)-13107200)

/* N64 buttons after platform-specific normalization. */
#define GE_FILE_MODE_V6_BUTTON_A ((uint32_t)1u << 0)
#define GE_FILE_MODE_V6_BUTTON_B ((uint32_t)1u << 1)
#define GE_FILE_MODE_V6_BUTTON_START ((uint32_t)1u << 2)
#define GE_FILE_MODE_V6_BUTTON_Z ((uint32_t)1u << 3)
#define GE_FILE_MODE_V6_BUTTON_L ((uint32_t)1u << 4)
#define GE_FILE_MODE_V6_BUTTON_R ((uint32_t)1u << 5)
#define GE_FILE_MODE_V6_BUTTON_DPAD_UP ((uint32_t)1u << 6)
#define GE_FILE_MODE_V6_BUTTON_DPAD_DOWN ((uint32_t)1u << 7)
#define GE_FILE_MODE_V6_BUTTON_DPAD_LEFT ((uint32_t)1u << 8)
#define GE_FILE_MODE_V6_BUTTON_DPAD_RIGHT ((uint32_t)1u << 9)
#define GE_FILE_MODE_V6_BUTTON_C_UP ((uint32_t)1u << 10)
#define GE_FILE_MODE_V6_BUTTON_C_DOWN ((uint32_t)1u << 11)
#define GE_FILE_MODE_V6_BUTTON_C_LEFT ((uint32_t)1u << 12)
#define GE_FILE_MODE_V6_BUTTON_C_RIGHT ((uint32_t)1u << 13)
#define GE_FILE_MODE_V6_BUTTON_MASK ((uint32_t)0x3fffu)
#define GE_FILE_MODE_V6_CONFIRM_MASK (GE_FILE_MODE_V6_BUTTON_A | \
                                      GE_FILE_MODE_V6_BUTTON_Z | \
                                      GE_FILE_MODE_V6_BUTTON_START)
#define GE_FILE_MODE_V6_CANCEL_MASK GE_FILE_MODE_V6_BUTTON_B

#define GE_FILE_MODE_V6_INPUT_FLAG_SOURCE_ANCHOR ((uint32_t)1u << 0)
#define GE_FILE_MODE_V6_INPUT_FLAG_FOCUSED ((uint32_t)1u << 1)
#define GE_FILE_MODE_V6_INPUT_FLAG_CONTROLLER_CONNECTED ((uint32_t)1u << 2)
#define GE_FILE_MODE_V6_INPUT_FLAG_SYNTHETIC ((uint32_t)1u << 3)
#define GE_FILE_MODE_V6_INPUT_FLAG_MASK ((uint32_t)0x0fu)

#define GE_FILE_MODE_V6_STATE_FLAG_ERASE_CONFIRM ((uint32_t)1u << 0)
#define GE_FILE_MODE_V6_STATE_FLAG_MULTI_AVAILABLE ((uint32_t)1u << 1)
#define GE_FILE_MODE_V6_STATE_FLAG_INPUT_SUPPRESSED ((uint32_t)1u << 2)
#define GE_FILE_MODE_V6_STATE_FLAG_ROUTE_PENDING ((uint32_t)1u << 3)
#define GE_FILE_MODE_V6_STATE_FLAG_MASK ((uint32_t)0x0fu)

enum GEFileModeV6Screen {
    GE_FILE_MODE_V6_SCREEN_LEGAL = 0u,
    GE_FILE_MODE_V6_SCREEN_FILE_SELECT = 5u,
    GE_FILE_MODE_V6_SCREEN_MODE_SELECT = 6u,
    GE_FILE_MODE_V6_SCREEN_SOLO_ROUTE = 7u,
    GE_FILE_MODE_V6_SCREEN_MULTI_ROUTE = 8u
};

enum GEFileModeV6FileOption {
    GE_FILE_MODE_V6_OPTION_SELECT = 0u,
    GE_FILE_MODE_V6_OPTION_COPY = 1u,
    GE_FILE_MODE_V6_OPTION_ERASE = 2u
};

enum GEFileModeV6EraseChoice {
    GE_FILE_MODE_V6_ERASE_CONFIRM = 0u,
    GE_FILE_MODE_V6_ERASE_CANCEL = 1u
};

enum GEFileModeV6SaveOperation {
    GE_FILE_MODE_V6_SAVE_CREATE = 1u,
    GE_FILE_MODE_V6_SAVE_SELECT = 2u,
    GE_FILE_MODE_V6_SAVE_COPY = 3u,
    GE_FILE_MODE_V6_SAVE_ERASE = 4u,
    GE_FILE_MODE_V6_SAVE_COPY_NOOP = 5u,
    GE_FILE_MODE_V6_SAVE_ERASE_NOOP = 6u
};

enum GEFileModeV6Sfx {
    GE_FILE_MODE_V6_SFX_OPTION_CLICK2 = 18u,
    GE_FILE_MODE_V6_SFX_PAPER_TURN = 77u,
    GE_FILE_MODE_V6_SFX_COPY_FILE = 79u,
    GE_FILE_MODE_V6_SFX_GUN_M60AMMGUN_3 = 118u,
    GE_FILE_MODE_V6_SFX_DOOR_METAL_CLOSE = 197u,
    GE_FILE_MODE_V6_SFX_DOOR_METAL_CLOSE2 = 199u,
    GE_FILE_MODE_V6_SFX_DOOR_LOCK = 222u
};

enum GEFileModeV6EventKind {
    GE_FILE_MODE_V6_EVENT_NONE = 0u,
    GE_FILE_MODE_V6_EVENT_SCREEN = 1u,
    GE_FILE_MODE_V6_EVENT_SAVE = 2u,
    GE_FILE_MODE_V6_EVENT_SFX = 3u,
    GE_FILE_MODE_V6_EVENT_CURSOR = 4u,
    GE_FILE_MODE_V6_EVENT_ROUTE = 5u
};

typedef struct GESaveFolderV1 {
    uint8_t bytes[GE_FILE_MODE_V6_FOLDER_BYTE_COUNT];
} GESaveFolderV1;

typedef struct GESaveSnapshotV1 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t flags;
    uint32_t selected_folder;
    uint32_t selected_bond;
    uint64_t generation;
    GESaveFolderV1 folders[GE_FILE_MODE_V6_FOLDER_COUNT];
    uint32_t reserved0;
    uint32_t reserved1;
    uint32_t reserved2;
    uint32_t reserved3;
} GESaveSnapshotV1;

typedef struct GEFileModeInputV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t flags;
    uint32_t buttons_held;
    uint32_t buttons_pressed;
    uint32_t buttons_released;
    int16_t stick_x;
    int16_t stick_y;
    uint32_t controller_count;
    uint32_t clock_timer;
    uint64_t native_tick;
    uint64_t reference_tick;
    uint64_t sequence;
    uint32_t reserved0;
    uint32_t reserved1;
} GEFileModeInputV6;

typedef struct GEFileModeStateV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t screen;
    uint32_t flags;
    uint32_t file_option;
    uint32_t erase_choice;
    uint32_t selected_folder;
    uint32_t hovered_folder;
    uint32_t mode_selection;
    uint32_t controller_count;
    uint32_t idle_timer;
    int32_t cursor_x_q16;
    int32_t cursor_y_q16;
    uint64_t native_tick;
    uint64_t reference_tick;
    uint64_t event_sequence;
    uint64_t last_input_sequence;
    uint32_t route;
    uint32_t reserved0;
    uint32_t reserved1;
    uint32_t reserved2;
} GEFileModeStateV6;

typedef struct GEFileModeEventV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t kind;
    uint32_t screen;
    uint32_t target_screen;
    uint32_t command;
    uint32_t folder;
    uint32_t destination_folder;
    uint32_t value0;
    uint32_t value1;
    int32_t x_q16;
    int32_t y_q16;
    uint64_t native_tick;
    uint64_t reference_tick;
    uint64_t sequence;
    uint32_t reserved0;
    uint32_t reserved1;
} GEFileModeEventV6;

typedef struct GEFileModeFrameV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t event_count;
    uint32_t overflow_flags;
    uint32_t reserved0;
    uint64_t state_hash;
    uint64_t event_hash;
    GEFileModeStateV6 state;
    GEFileModeEventV6 events[GE_FILE_MODE_V6_MAX_EVENTS];
} GEFileModeFrameV6;

GEStatusV1 ge_file_mode_v6_validate_save(const GESaveSnapshotV1 *save);
GEStatusV1 ge_file_mode_v6_validate_input(const GEFileModeInputV6 *input);
GEStatusV1 ge_file_mode_v6_validate_state(const GEFileModeStateV6 *state);
GEStatusV1 ge_file_mode_v6_validate_frame(const GEFileModeFrameV6 *frame);

GEStatusV1 ge_file_mode_v6_init(
    GEFileModeStateV6 *state,
    const GESaveSnapshotV1 *save,
    GEFileModeFrameV6 *out_frame);

GEStatusV1 ge_file_mode_v6_step(
    GEFileModeStateV6 *state,
    const GEFileModeInputV6 *input,
    GESaveSnapshotV1 *save,
    GEFileModeFrameV6 *out_frame);

uint32_t ge_file_mode_v6_folder_is_reset(const GESaveFolderV1 *folder);
uint32_t ge_file_mode_v6_folder_has_completion(const GESaveFolderV1 *folder);

#if defined(__cplusplus)
#define GE_FILE_MODE_V6_STATIC_ASSERT(condition, message) static_assert((condition), message)
#else
#define GE_FILE_MODE_V6_STATIC_ASSERT(condition, message) _Static_assert((condition), message)
#endif

GE_FILE_MODE_V6_STATIC_ASSERT(sizeof(GESaveFolderV1) == 96u, "save folder layout drift");
GE_FILE_MODE_V6_STATIC_ASSERT(sizeof(GESaveSnapshotV1) == 432u, "save snapshot layout drift");
GE_FILE_MODE_V6_STATIC_ASSERT(sizeof(GEFileModeInputV6) == 72u, "file/mode input layout drift");
GE_FILE_MODE_V6_STATIC_ASSERT(sizeof(GEFileModeStateV6) == 104u, "file/mode state layout drift");
GE_FILE_MODE_V6_STATIC_ASSERT(sizeof(GEFileModeEventV6) == 88u, "file/mode event layout drift");
GE_FILE_MODE_V6_STATIC_ASSERT(sizeof(GEFileModeFrameV6) == 2960u, "file/mode frame layout drift");

#undef GE_FILE_MODE_V6_STATIC_ASSERT

#ifdef __cplusplus
}
#endif

#endif /* GE_FILE_MODE_V6_H */
