#ifndef GE_TITLE_ROUTE_V5_H
#define GE_TITLE_ROUTE_V5_H

/*
 * Source-derived title attract-route contract.
 *
 * This sidecar owns only the ordering decisions between the cast reel and the
 * RAMROM catalog.  It does not load a cast model, run a stage, advance
 * gameplay, or claim visual parity.  Every public value is fixed width and no
 * path, pointer, ROM address, or mutable object crosses the boundary.
 */

#include <stdint.h>

#include "ge_ramrom_v5.h"

#ifdef __cplusplus
extern "C" {
#endif

#define GE_TITLE_ROUTE_V5_CONTRACT_VERSION ((uint32_t)5u)
#define GE_TITLE_ROUTE_V5_RECORD_VERSION ((uint32_t)1u)

#define GE_TITLE_ROUTE_V5_CAST_ENTRY_COUNT ((uint32_t)34u)
#define GE_TITLE_ROUTE_V5_CAST_FIRST_ATTRACT ((uint32_t)1u)
#define GE_TITLE_ROUTE_V5_CAST_FIRST_EXTENDED ((uint32_t)0u)
#define GE_TITLE_ROUTE_V5_CAST_TICKS_60 ((uint32_t)181u)

#define GE_TITLE_ROUTE_V5_CAST_MODE_ATTRACT ((uint32_t)0u)
#define GE_TITLE_ROUTE_V5_CAST_MODE_EXTENDED ((uint32_t)1u)
#define GE_TITLE_ROUTE_V5_CAST_MODE_MAX GE_TITLE_ROUTE_V5_CAST_MODE_EXTENDED

#define GE_TITLE_ROUTE_V5_CAST_ENTRY_EXTENDED_ONLY ((uint32_t)1u << 0)
#define GE_TITLE_ROUTE_V5_CAST_ENTRY_GUEST ((uint32_t)1u << 1)
#define GE_TITLE_ROUTE_V5_CAST_ENTRY_FLAG_MASK ((uint32_t)0x03u)

#define GE_TITLE_ROUTE_V5_UNLOCK_NONE ((uint32_t)0u)
#define GE_TITLE_ROUTE_V5_UNLOCK_AZTEC_REQUIRED ((uint32_t)1u)
#define GE_TITLE_ROUTE_V5_UNLOCK_EGYPT_REQUIRED ((uint32_t)2u)
#define GE_TITLE_ROUTE_V5_UNLOCK_AZTEC_OR_RARE ((uint32_t)3u)
#define GE_TITLE_ROUTE_V5_UNLOCK_EGYPT_OR_RARE ((uint32_t)4u)
#define GE_TITLE_ROUTE_V5_UNLOCK_MAX GE_TITLE_ROUTE_V5_UNLOCK_EGYPT_OR_RARE

#define GE_TITLE_ROUTE_V5_PROGRESS_AZTEC_SECRET_00 ((uint32_t)1u << 0)
#define GE_TITLE_ROUTE_V5_PROGRESS_EGYPT_00 ((uint32_t)1u << 1)
#define GE_TITLE_ROUTE_V5_PROGRESS_FLAG_MASK ((uint32_t)0x03u)

#define GE_TITLE_ROUTE_V5_ACTION_SHOW_CAST ((uint32_t)1u)
#define GE_TITLE_ROUTE_V5_ACTION_SELECT_RAMROM ((uint32_t)2u)
#define GE_TITLE_ROUTE_V5_ACTION_MISSION_SELECT ((uint32_t)3u)
#define GE_TITLE_ROUTE_V5_ACTION_MAX GE_TITLE_ROUTE_V5_ACTION_MISSION_SELECT

#define GE_TITLE_ROUTE_V5_DECISION_SOURCE_ORDER ((uint32_t)1u << 0)
#define GE_TITLE_ROUTE_V5_DECISION_RARE_GUEST ((uint32_t)1u << 1)
#define GE_TITLE_ROUTE_V5_DECISION_END_OF_CAST ((uint32_t)1u << 2)
#define GE_TITLE_ROUTE_V5_DECISION_FLAG_MASK ((uint32_t)0x07u)

#define GE_TITLE_ROUTE_V5_DEMO_EXPLICIT ((uint32_t)1u << 0)
#define GE_TITLE_ROUTE_V5_DEMO_SOURCE_RANDOM ((uint32_t)1u << 1)
#define GE_TITLE_ROUTE_V5_DEMO_CATALOG_VALID ((uint32_t)1u << 2)
#define GE_TITLE_ROUTE_V5_DEMO_FLAG_MASK ((uint32_t)0x07u)
#define GE_TITLE_ROUTE_V5_RANDOM_CATALOG_INDEX UINT32_MAX
#define GE_TITLE_ROUTE_V5_SCREEN_MAX ((uint32_t)8u)

#define GE_TITLE_ROUTE_V5_RESTORE_VALID ((uint32_t)1u << 0)
#define GE_TITLE_ROUTE_V5_RESTORE_REAL_INPUT_ABORT ((uint32_t)1u << 1)
#define GE_TITLE_ROUTE_V5_RESTORE_COMPLETE ((uint32_t)1u << 2)
#define GE_TITLE_ROUTE_V5_RESTORE_FAILED ((uint32_t)1u << 3)
#define GE_TITLE_ROUTE_V5_RESTORE_FLAG_MASK ((uint32_t)0x0fu)

typedef struct GETitleRouteCastEntryV5 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t source_index;
    uint32_t flags;
    uint32_t unlock_gate;
    uint32_t reserved0;
    uint32_t reserved1;
} GETitleRouteCastEntryV5;

typedef struct GETitleRouteCastInputV5 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t cast_mode;
    uint32_t current_source_index;
    uint32_t progress_flags;
    uint32_t random_word_count;
    uint32_t random_words[4];
    uint32_t reserved0;
    uint32_t reserved1;
} GETitleRouteCastInputV5;

typedef struct GETitleRouteCastDecisionV5 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t action;
    uint32_t source_index;
    uint32_t cast_mode;
    uint32_t random_words_consumed;
    uint32_t flags;
    uint32_t reserved0;
    uint32_t reserved1;
} GETitleRouteCastDecisionV5;

typedef struct GETitleRouteDemoSelectionV5 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t flags;
    uint32_t catalog_index;
    uint32_t selection_word;
    GERamRomCatalogEntryV5 catalog;
    uint32_t reserved0;
    uint32_t reserved1;
} GETitleRouteDemoSelectionV5;

typedef struct GETitleRouteRestorePointV5 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t flags;
    uint32_t previous_screen;
    int32_t selection;
    uint32_t file_option;
    uint32_t selected_folder;
    uint64_t state_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GETitleRouteRestorePointV5;

GEStatusV1 ge_title_route_v5_validate_cast_entry(
    const GETitleRouteCastEntryV5 *value);
GEStatusV1 ge_title_route_v5_validate_cast_input(
    const GETitleRouteCastInputV5 *value);
GEStatusV1 ge_title_route_v5_validate_cast_decision(
    const GETitleRouteCastDecisionV5 *value);
GEStatusV1 ge_title_route_v5_validate_demo_selection(
    const GETitleRouteDemoSelectionV5 *value);
GEStatusV1 ge_title_route_v5_validate_restore_point(
    const GETitleRouteRestorePointV5 *value);

uint32_t ge_title_route_v5_cast_count(void);
GEStatusV1 ge_title_route_v5_cast_entry(
    uint32_t source_index,
    GETitleRouteCastEntryV5 *out_entry);
GEStatusV1 ge_title_route_v5_begin_cast(
    uint32_t cast_mode,
    GETitleRouteCastDecisionV5 *out_decision);
GEStatusV1 ge_title_route_v5_advance_cast(
    GETitleRouteCastInputV5 input,
    GETitleRouteCastDecisionV5 *out_decision);
GEStatusV1 ge_title_route_v5_select_demo(
    uint32_t selection_word,
    uint32_t explicit_catalog_index,
    GETitleRouteDemoSelectionV5 *out_selection);
GEStatusV1 ge_title_route_v5_make_restore_point(
    uint32_t previous_screen,
    int32_t selection,
    uint32_t file_option,
    uint32_t selected_folder,
    uint64_t state_hash,
    GETitleRouteRestorePointV5 *out_restore);

#if defined(__cplusplus)
#define GE_TITLE_ROUTE_V5_STATIC_ASSERT(condition, message) static_assert((condition), message)
#else
#define GE_TITLE_ROUTE_V5_STATIC_ASSERT(condition, message) _Static_assert((condition), message)
#endif

GE_TITLE_ROUTE_V5_STATIC_ASSERT(sizeof(GETitleRouteCastEntryV5) == 32u,
                                "GETitleRouteCastEntryV5 layout drift");
GE_TITLE_ROUTE_V5_STATIC_ASSERT(sizeof(GETitleRouteCastInputV5) == 52u,
                                "GETitleRouteCastInputV5 layout drift");
GE_TITLE_ROUTE_V5_STATIC_ASSERT(sizeof(GETitleRouteCastDecisionV5) == 40u,
                                "GETitleRouteCastDecisionV5 layout drift");
GE_TITLE_ROUTE_V5_STATIC_ASSERT(sizeof(GETitleRouteDemoSelectionV5) == 80u,
                                "GETitleRouteDemoSelectionV5 layout drift");
GE_TITLE_ROUTE_V5_STATIC_ASSERT(sizeof(GETitleRouteRestorePointV5) == 48u,
                                "GETitleRouteRestorePointV5 layout drift");

#undef GE_TITLE_ROUTE_V5_STATIC_ASSERT

#ifdef __cplusplus
}
#endif

#endif /* GE_TITLE_ROUTE_V5_H */
