#include "ge_title_route_v5.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define REQUIRE(condition)                                                       \
    do {                                                                         \
        if (!(condition)) {                                                      \
            fprintf(stderr,                                                      \
                    "title route v5 requirement failed at %s:%d: %s\n",       \
                    __FILE__, __LINE__, #condition);                             \
            return 1;                                                            \
        }                                                                        \
    } while (0)

static GETitleRouteCastInputV5 cast_input(uint32_t mode,
                                          uint32_t current,
                                          uint32_t progress,
                                          uint32_t word)
{
    GETitleRouteCastInputV5 value;
    memset(&value, 0, sizeof(value));
    value.header.abi_version = GE_NATIVE_ABI_VERSION;
    value.header.struct_size = (uint32_t)sizeof(value);
    value.record_version = GE_TITLE_ROUTE_V5_RECORD_VERSION;
    value.cast_mode = mode;
    value.current_source_index = current;
    value.progress_flags = progress;
    value.random_word_count = 4u;
    for (uint32_t index = 0u; index < 4u; index++) {
        value.random_words[index] = word;
    }
    return value;
}

int main(void)
{
    REQUIRE(sizeof(GETitleRouteCastEntryV5) == 32u);
    REQUIRE(sizeof(GETitleRouteCastInputV5) == 52u);
    REQUIRE(sizeof(GETitleRouteCastDecisionV5) == 40u);
    REQUIRE(sizeof(GETitleRouteDemoSelectionV5) == 80u);
    REQUIRE(sizeof(GETitleRouteRestorePointV5) == 48u);
    REQUIRE(ge_title_route_v5_cast_count() == 34u);

    for (uint32_t index = 0u; index < ge_title_route_v5_cast_count(); index++) {
        GETitleRouteCastEntryV5 entry;
        REQUIRE(ge_title_route_v5_cast_entry(index, &entry) == GE_STATUS_OK);
        REQUIRE(entry.source_index == index);
    }

    GETitleRouteCastDecisionV5 decision;
    REQUIRE(ge_title_route_v5_begin_cast(
                GE_TITLE_ROUTE_V5_CAST_MODE_ATTRACT, &decision) == GE_STATUS_OK);
    REQUIRE(decision.action == GE_TITLE_ROUTE_V5_ACTION_SHOW_CAST);
    REQUIRE(decision.source_index == 1u);

    GETitleRouteCastInputV5 input = cast_input(
        GE_TITLE_ROUTE_V5_CAST_MODE_ATTRACT, 1u, 0u, 1u);
    REQUIRE(ge_title_route_v5_advance_cast(input, &decision) == GE_STATUS_OK);
    REQUIRE(decision.source_index == 2u);

    /* Normal attract skips entries 9-29 and all four locked rare guests. */
    input = cast_input(GE_TITLE_ROUTE_V5_CAST_MODE_ATTRACT, 8u, 0u, 1u);
    REQUIRE(ge_title_route_v5_advance_cast(input, &decision) == GE_STATUS_OK);
    REQUIRE(decision.action == GE_TITLE_ROUTE_V5_ACTION_SELECT_RAMROM);
    REQUIRE(decision.random_words_consumed == 4u);
    REQUIRE(decision.flags & GE_TITLE_ROUTE_V5_DECISION_END_OF_CAST);

    /* A zero random word preserves the source one-in-10,000 guest path. */
    input = cast_input(GE_TITLE_ROUTE_V5_CAST_MODE_ATTRACT, 8u, 0u, 0u);
    REQUIRE(ge_title_route_v5_advance_cast(input, &decision) == GE_STATUS_OK);
    REQUIRE(decision.action == GE_TITLE_ROUTE_V5_ACTION_SHOW_CAST);
    REQUIRE(decision.source_index == 30u);
    REQUIRE(decision.flags & GE_TITLE_ROUTE_V5_DECISION_RARE_GUEST);

    input = cast_input(
        GE_TITLE_ROUTE_V5_CAST_MODE_ATTRACT,
        8u,
        GE_TITLE_ROUTE_V5_PROGRESS_AZTEC_SECRET_00,
        1u);
    REQUIRE(ge_title_route_v5_advance_cast(input, &decision) == GE_STATUS_OK);
    REQUIRE(decision.source_index == 30u);
    REQUIRE(decision.random_words_consumed == 0u);

    REQUIRE(ge_title_route_v5_begin_cast(
                GE_TITLE_ROUTE_V5_CAST_MODE_EXTENDED, &decision) == GE_STATUS_OK);
    REQUIRE(decision.source_index == 0u);
    input = cast_input(GE_TITLE_ROUTE_V5_CAST_MODE_EXTENDED, 33u,
                       GE_TITLE_ROUTE_V5_PROGRESS_FLAG_MASK, 1u);
    REQUIRE(ge_title_route_v5_advance_cast(input, &decision) == GE_STATUS_OK);
    REQUIRE(decision.action == GE_TITLE_ROUTE_V5_ACTION_MISSION_SELECT);

    for (uint32_t index = 0u; index < GE_RAMROM_V5_DEMO_COUNT; index++) {
        GETitleRouteDemoSelectionV5 selection;
        REQUIRE(ge_title_route_v5_select_demo(
                    0x12345678u, index, &selection) == GE_STATUS_OK);
        REQUIRE(selection.catalog_index == index);
        REQUIRE(selection.catalog.demo_id == index + 1u);
        REQUIRE(selection.flags & GE_TITLE_ROUTE_V5_DEMO_EXPLICIT);
    }

    GETitleRouteDemoSelectionV5 random_selection;
    REQUIRE(ge_title_route_v5_select_demo(
                15u,
                GE_TITLE_ROUTE_V5_RANDOM_CATALOG_INDEX,
                &random_selection) == GE_STATUS_OK);
    REQUIRE(random_selection.catalog_index == 1u);
    REQUIRE(random_selection.catalog.demo_id == GE_RAMROM_V5_DEMO_DAM_2);
    REQUIRE(random_selection.flags & GE_TITLE_ROUTE_V5_DEMO_SOURCE_RANDOM);

    GETitleRouteRestorePointV5 restore;
    REQUIRE(ge_title_route_v5_make_restore_point(
                7u, 2, 1u, 3u, UINT64_C(0x1122334455667788), &restore) ==
            GE_STATUS_OK);
    REQUIRE(restore.selection == 2);
    REQUIRE(restore.file_option == 1u);
    REQUIRE(restore.selected_folder == 3u);

    printf("goldeneye_title_route_v5_smoke: PASS cast=%u demos=%u\n",
           ge_title_route_v5_cast_count(), ge_ramrom_v5_catalog_count());
    return 0;
}
