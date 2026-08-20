#include "ge_title_route_v5.h"

#include <stddef.h>
#include <string.h>

#define GE_TITLE_ROUTE_ENTRY(index, entry_flags, gate)                         \
    {                                                                          \
        {GE_NATIVE_ABI_VERSION, sizeof(GETitleRouteCastEntryV5)},              \
        GE_TITLE_ROUTE_V5_RECORD_VERSION, (index), (entry_flags), (gate),      \
        0u, 0u                                                                 \
    }

/* Source indices are the exact order of intro_char_table in front.c. */
static const GETitleRouteCastEntryV5 GE_TITLE_ROUTE_CAST[
    GE_TITLE_ROUTE_V5_CAST_ENTRY_COUNT] = {
    GE_TITLE_ROUTE_ENTRY(0u, GE_TITLE_ROUTE_V5_CAST_ENTRY_EXTENDED_ONLY,
                         GE_TITLE_ROUTE_V5_UNLOCK_NONE),
    GE_TITLE_ROUTE_ENTRY(1u, 0u, GE_TITLE_ROUTE_V5_UNLOCK_NONE),
    GE_TITLE_ROUTE_ENTRY(2u, 0u, GE_TITLE_ROUTE_V5_UNLOCK_NONE),
    GE_TITLE_ROUTE_ENTRY(3u, 0u, GE_TITLE_ROUTE_V5_UNLOCK_NONE),
    GE_TITLE_ROUTE_ENTRY(4u, 0u, GE_TITLE_ROUTE_V5_UNLOCK_NONE),
    GE_TITLE_ROUTE_ENTRY(5u, 0u, GE_TITLE_ROUTE_V5_UNLOCK_NONE),
    GE_TITLE_ROUTE_ENTRY(6u, 0u, GE_TITLE_ROUTE_V5_UNLOCK_NONE),
    GE_TITLE_ROUTE_ENTRY(7u, 0u, GE_TITLE_ROUTE_V5_UNLOCK_NONE),
    GE_TITLE_ROUTE_ENTRY(8u, 0u, GE_TITLE_ROUTE_V5_UNLOCK_NONE),
    GE_TITLE_ROUTE_ENTRY(9u, GE_TITLE_ROUTE_V5_CAST_ENTRY_EXTENDED_ONLY,
                         GE_TITLE_ROUTE_V5_UNLOCK_NONE),
    GE_TITLE_ROUTE_ENTRY(10u, GE_TITLE_ROUTE_V5_CAST_ENTRY_EXTENDED_ONLY,
                         GE_TITLE_ROUTE_V5_UNLOCK_NONE),
    GE_TITLE_ROUTE_ENTRY(11u, GE_TITLE_ROUTE_V5_CAST_ENTRY_EXTENDED_ONLY,
                         GE_TITLE_ROUTE_V5_UNLOCK_NONE),
    GE_TITLE_ROUTE_ENTRY(12u, GE_TITLE_ROUTE_V5_CAST_ENTRY_EXTENDED_ONLY,
                         GE_TITLE_ROUTE_V5_UNLOCK_NONE),
    GE_TITLE_ROUTE_ENTRY(13u, GE_TITLE_ROUTE_V5_CAST_ENTRY_EXTENDED_ONLY,
                         GE_TITLE_ROUTE_V5_UNLOCK_NONE),
    GE_TITLE_ROUTE_ENTRY(14u, GE_TITLE_ROUTE_V5_CAST_ENTRY_EXTENDED_ONLY,
                         GE_TITLE_ROUTE_V5_UNLOCK_NONE),
    GE_TITLE_ROUTE_ENTRY(15u, GE_TITLE_ROUTE_V5_CAST_ENTRY_EXTENDED_ONLY,
                         GE_TITLE_ROUTE_V5_UNLOCK_NONE),
    GE_TITLE_ROUTE_ENTRY(16u, GE_TITLE_ROUTE_V5_CAST_ENTRY_EXTENDED_ONLY,
                         GE_TITLE_ROUTE_V5_UNLOCK_NONE),
    GE_TITLE_ROUTE_ENTRY(17u, GE_TITLE_ROUTE_V5_CAST_ENTRY_EXTENDED_ONLY,
                         GE_TITLE_ROUTE_V5_UNLOCK_NONE),
    GE_TITLE_ROUTE_ENTRY(18u, GE_TITLE_ROUTE_V5_CAST_ENTRY_EXTENDED_ONLY,
                         GE_TITLE_ROUTE_V5_UNLOCK_NONE),
    GE_TITLE_ROUTE_ENTRY(19u, GE_TITLE_ROUTE_V5_CAST_ENTRY_EXTENDED_ONLY,
                         GE_TITLE_ROUTE_V5_UNLOCK_NONE),
    GE_TITLE_ROUTE_ENTRY(20u, GE_TITLE_ROUTE_V5_CAST_ENTRY_EXTENDED_ONLY,
                         GE_TITLE_ROUTE_V5_UNLOCK_NONE),
    GE_TITLE_ROUTE_ENTRY(21u, GE_TITLE_ROUTE_V5_CAST_ENTRY_EXTENDED_ONLY,
                         GE_TITLE_ROUTE_V5_UNLOCK_NONE),
    GE_TITLE_ROUTE_ENTRY(22u, GE_TITLE_ROUTE_V5_CAST_ENTRY_EXTENDED_ONLY,
                         GE_TITLE_ROUTE_V5_UNLOCK_NONE),
    GE_TITLE_ROUTE_ENTRY(23u, GE_TITLE_ROUTE_V5_CAST_ENTRY_EXTENDED_ONLY,
                         GE_TITLE_ROUTE_V5_UNLOCK_NONE),
    GE_TITLE_ROUTE_ENTRY(24u, GE_TITLE_ROUTE_V5_CAST_ENTRY_EXTENDED_ONLY,
                         GE_TITLE_ROUTE_V5_UNLOCK_NONE),
    GE_TITLE_ROUTE_ENTRY(25u, GE_TITLE_ROUTE_V5_CAST_ENTRY_EXTENDED_ONLY,
                         GE_TITLE_ROUTE_V5_UNLOCK_NONE),
    GE_TITLE_ROUTE_ENTRY(26u, GE_TITLE_ROUTE_V5_CAST_ENTRY_EXTENDED_ONLY,
                         GE_TITLE_ROUTE_V5_UNLOCK_NONE),
    GE_TITLE_ROUTE_ENTRY(27u, GE_TITLE_ROUTE_V5_CAST_ENTRY_EXTENDED_ONLY,
                         GE_TITLE_ROUTE_V5_UNLOCK_NONE),
    GE_TITLE_ROUTE_ENTRY(28u, GE_TITLE_ROUTE_V5_CAST_ENTRY_EXTENDED_ONLY,
                         GE_TITLE_ROUTE_V5_UNLOCK_AZTEC_REQUIRED),
    GE_TITLE_ROUTE_ENTRY(29u, GE_TITLE_ROUTE_V5_CAST_ENTRY_EXTENDED_ONLY,
                         GE_TITLE_ROUTE_V5_UNLOCK_AZTEC_REQUIRED),
    GE_TITLE_ROUTE_ENTRY(30u, GE_TITLE_ROUTE_V5_CAST_ENTRY_GUEST,
                         GE_TITLE_ROUTE_V5_UNLOCK_AZTEC_OR_RARE),
    GE_TITLE_ROUTE_ENTRY(31u, GE_TITLE_ROUTE_V5_CAST_ENTRY_GUEST,
                         GE_TITLE_ROUTE_V5_UNLOCK_AZTEC_OR_RARE),
    GE_TITLE_ROUTE_ENTRY(32u, GE_TITLE_ROUTE_V5_CAST_ENTRY_GUEST,
                         GE_TITLE_ROUTE_V5_UNLOCK_EGYPT_OR_RARE),
    GE_TITLE_ROUTE_ENTRY(33u, GE_TITLE_ROUTE_V5_CAST_ENTRY_GUEST,
                         GE_TITLE_ROUTE_V5_UNLOCK_EGYPT_OR_RARE),
};

#undef GE_TITLE_ROUTE_ENTRY

static GEStatusV1 ge_title_route_v5_validate_common(
    const GEAbiHeaderV1 *header,
    uint32_t expected_size,
    uint32_t record_version)
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
    if (record_version != GE_TITLE_ROUTE_V5_RECORD_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_title_route_v5_validate_cast_entry(
    const GETitleRouteCastEntryV5 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_title_route_v5_validate_common(
        &value->header, (uint32_t)sizeof(*value), value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->source_index >= GE_TITLE_ROUTE_V5_CAST_ENTRY_COUNT ||
        (value->flags & ~GE_TITLE_ROUTE_V5_CAST_ENTRY_FLAG_MASK) != 0u ||
        value->unlock_gate > GE_TITLE_ROUTE_V5_UNLOCK_MAX ||
        value->reserved0 != 0u || value->reserved1 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_title_route_v5_validate_cast_input(
    const GETitleRouteCastInputV5 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_title_route_v5_validate_common(
        &value->header, (uint32_t)sizeof(*value), value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->cast_mode > GE_TITLE_ROUTE_V5_CAST_MODE_MAX ||
        value->current_source_index >= GE_TITLE_ROUTE_V5_CAST_ENTRY_COUNT ||
        (value->progress_flags & ~GE_TITLE_ROUTE_V5_PROGRESS_FLAG_MASK) != 0u ||
        value->random_word_count > 4u || value->reserved0 != 0u ||
        value->reserved1 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_title_route_v5_validate_cast_decision(
    const GETitleRouteCastDecisionV5 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_title_route_v5_validate_common(
        &value->header, (uint32_t)sizeof(*value), value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (value->action < GE_TITLE_ROUTE_V5_ACTION_SHOW_CAST ||
        value->action > GE_TITLE_ROUTE_V5_ACTION_MAX ||
        value->source_index >= GE_TITLE_ROUTE_V5_CAST_ENTRY_COUNT ||
        value->cast_mode > GE_TITLE_ROUTE_V5_CAST_MODE_MAX ||
        value->random_words_consumed > 4u ||
        (value->flags & ~GE_TITLE_ROUTE_V5_DECISION_FLAG_MASK) != 0u ||
        value->reserved0 != 0u || value->reserved1 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_title_route_v5_validate_demo_selection(
    const GETitleRouteDemoSelectionV5 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_title_route_v5_validate_common(
        &value->header, (uint32_t)sizeof(*value), value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if ((value->flags & ~GE_TITLE_ROUTE_V5_DEMO_FLAG_MASK) != 0u ||
        (value->flags & GE_TITLE_ROUTE_V5_DEMO_CATALOG_VALID) == 0u ||
        ((value->flags & GE_TITLE_ROUTE_V5_DEMO_EXPLICIT) != 0u) ==
            ((value->flags & GE_TITLE_ROUTE_V5_DEMO_SOURCE_RANDOM) != 0u) ||
        value->catalog_index >= GE_RAMROM_V5_DEMO_COUNT ||
        value->reserved0 != 0u || value->reserved1 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    status = ge_ramrom_v5_validate_catalog_entry(&value->catalog);
    if (status != GE_STATUS_OK ||
        value->catalog.demo_id != value->catalog_index + 1u) {
        return status == GE_STATUS_OK ? GE_STATUS_MALFORMED_STREAM : status;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_title_route_v5_validate_restore_point(
    const GETitleRouteRestorePointV5 *value)
{
    if (value == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_title_route_v5_validate_common(
        &value->header, (uint32_t)sizeof(*value), value->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if ((value->flags & ~GE_TITLE_ROUTE_V5_RESTORE_FLAG_MASK) != 0u ||
        (value->flags & GE_TITLE_ROUTE_V5_RESTORE_VALID) == 0u ||
        value->previous_screen > GE_TITLE_ROUTE_V5_SCREEN_MAX ||
        value->selection < 0 || value->selection > 3 ||
        value->file_option > 2u || value->selected_folder > 3u ||
        value->reserved0 != 0u || value->reserved1 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

uint32_t ge_title_route_v5_cast_count(void)
{
    return GE_TITLE_ROUTE_V5_CAST_ENTRY_COUNT;
}

GEStatusV1 ge_title_route_v5_cast_entry(
    uint32_t source_index,
    GETitleRouteCastEntryV5 *out_entry)
{
    if (out_entry == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (source_index >= GE_TITLE_ROUTE_V5_CAST_ENTRY_COUNT) {
        return GE_STATUS_RESOURCE_NOT_FOUND;
    }
    *out_entry = GE_TITLE_ROUTE_CAST[source_index];
    return ge_title_route_v5_validate_cast_entry(out_entry);
}

static void ge_title_route_v5_fill_decision(
    uint32_t action,
    uint32_t source_index,
    uint32_t cast_mode,
    uint32_t consumed,
    uint32_t flags,
    GETitleRouteCastDecisionV5 *out_decision)
{
    memset(out_decision, 0, sizeof(*out_decision));
    out_decision->header.abi_version = GE_NATIVE_ABI_VERSION;
    out_decision->header.struct_size = (uint32_t)sizeof(*out_decision);
    out_decision->record_version = GE_TITLE_ROUTE_V5_RECORD_VERSION;
    out_decision->action = action;
    out_decision->source_index = source_index;
    out_decision->cast_mode = cast_mode;
    out_decision->random_words_consumed = consumed;
    out_decision->flags = flags;
}

GEStatusV1 ge_title_route_v5_begin_cast(
    uint32_t cast_mode,
    GETitleRouteCastDecisionV5 *out_decision)
{
    if (out_decision == NULL || cast_mode > GE_TITLE_ROUTE_V5_CAST_MODE_MAX) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    uint32_t source_index = cast_mode == GE_TITLE_ROUTE_V5_CAST_MODE_ATTRACT ?
        GE_TITLE_ROUTE_V5_CAST_FIRST_ATTRACT :
        GE_TITLE_ROUTE_V5_CAST_FIRST_EXTENDED;
    ge_title_route_v5_fill_decision(
        GE_TITLE_ROUTE_V5_ACTION_SHOW_CAST,
        source_index,
        cast_mode,
        0u,
        GE_TITLE_ROUTE_V5_DECISION_SOURCE_ORDER,
        out_decision);
    return ge_title_route_v5_validate_cast_decision(out_decision);
}

static int ge_title_route_v5_entry_is_eligible(
    const GETitleRouteCastEntryV5 *entry,
    const GETitleRouteCastInputV5 *input,
    uint32_t *inout_random_index,
    uint32_t *inout_decision_flags,
    GEStatusV1 *out_status)
{
    if (input->cast_mode == GE_TITLE_ROUTE_V5_CAST_MODE_ATTRACT &&
        (entry->flags & GE_TITLE_ROUTE_V5_CAST_ENTRY_EXTENDED_ONLY) != 0u) {
        return 0;
    }
    switch (entry->unlock_gate) {
    case GE_TITLE_ROUTE_V5_UNLOCK_NONE:
        return 1;
    case GE_TITLE_ROUTE_V5_UNLOCK_AZTEC_REQUIRED:
        return (input->progress_flags &
                GE_TITLE_ROUTE_V5_PROGRESS_AZTEC_SECRET_00) != 0u;
    case GE_TITLE_ROUTE_V5_UNLOCK_EGYPT_REQUIRED:
        return (input->progress_flags &
                GE_TITLE_ROUTE_V5_PROGRESS_EGYPT_00) != 0u;
    case GE_TITLE_ROUTE_V5_UNLOCK_AZTEC_OR_RARE:
        if ((input->progress_flags &
             GE_TITLE_ROUTE_V5_PROGRESS_AZTEC_SECRET_00) != 0u) {
            return 1;
        }
        break;
    case GE_TITLE_ROUTE_V5_UNLOCK_EGYPT_OR_RARE:
        if ((input->progress_flags &
             GE_TITLE_ROUTE_V5_PROGRESS_EGYPT_00) != 0u) {
            return 1;
        }
        break;
    default:
        *out_status = GE_STATUS_MALFORMED_STREAM;
        return 0;
    }
    if (*inout_random_index >= input->random_word_count) {
        *out_status = GE_STATUS_REPLAY_BUDGET;
        return 0;
    }
    uint32_t random_word = input->random_words[*inout_random_index];
    (*inout_random_index)++;
    if (random_word % 10000u == 0u) {
        *inout_decision_flags |= GE_TITLE_ROUTE_V5_DECISION_RARE_GUEST;
        return 1;
    }
    return 0;
}

GEStatusV1 ge_title_route_v5_advance_cast(
    GETitleRouteCastInputV5 input,
    GETitleRouteCastDecisionV5 *out_decision)
{
    if (out_decision == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEStatusV1 status = ge_title_route_v5_validate_cast_input(&input);
    if (status != GE_STATUS_OK) {
        return status;
    }
    uint32_t random_index = 0u;
    uint32_t decision_flags = GE_TITLE_ROUTE_V5_DECISION_SOURCE_ORDER;
    for (uint32_t candidate = input.current_source_index + 1u;
         candidate < GE_TITLE_ROUTE_V5_CAST_ENTRY_COUNT;
         candidate++) {
        if (ge_title_route_v5_entry_is_eligible(
                &GE_TITLE_ROUTE_CAST[candidate],
                &input,
                &random_index,
                &decision_flags,
                &status)) {
            ge_title_route_v5_fill_decision(
                GE_TITLE_ROUTE_V5_ACTION_SHOW_CAST,
                candidate,
                input.cast_mode,
                random_index,
                decision_flags,
                out_decision);
            return ge_title_route_v5_validate_cast_decision(out_decision);
        }
        if (status != GE_STATUS_OK) {
            return status;
        }
    }

    uint32_t action = input.cast_mode == GE_TITLE_ROUTE_V5_CAST_MODE_ATTRACT ?
        GE_TITLE_ROUTE_V5_ACTION_SELECT_RAMROM :
        GE_TITLE_ROUTE_V5_ACTION_MISSION_SELECT;
    ge_title_route_v5_fill_decision(
        action,
        0u,
        input.cast_mode,
        random_index,
        decision_flags | GE_TITLE_ROUTE_V5_DECISION_END_OF_CAST,
        out_decision);
    return ge_title_route_v5_validate_cast_decision(out_decision);
}

GEStatusV1 ge_title_route_v5_select_demo(
    uint32_t selection_word,
    uint32_t explicit_catalog_index,
    GETitleRouteDemoSelectionV5 *out_selection)
{
    if (out_selection == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    uint32_t catalog_count = ge_ramrom_v5_catalog_count();
    if (catalog_count != GE_RAMROM_V5_DEMO_COUNT || catalog_count == 0u) {
        return GE_STATUS_ASSET_MISMATCH;
    }
    uint32_t index;
    uint32_t flags = GE_TITLE_ROUTE_V5_DEMO_CATALOG_VALID;
    if (explicit_catalog_index == GE_TITLE_ROUTE_V5_RANDOM_CATALOG_INDEX) {
        index = selection_word % catalog_count;
        flags |= GE_TITLE_ROUTE_V5_DEMO_SOURCE_RANDOM;
    } else {
        if (explicit_catalog_index >= catalog_count) {
            return GE_STATUS_INVALID_ARGUMENT;
        }
        index = explicit_catalog_index;
        flags |= GE_TITLE_ROUTE_V5_DEMO_EXPLICIT;
    }

    memset(out_selection, 0, sizeof(*out_selection));
    out_selection->header.abi_version = GE_NATIVE_ABI_VERSION;
    out_selection->header.struct_size = (uint32_t)sizeof(*out_selection);
    out_selection->record_version = GE_TITLE_ROUTE_V5_RECORD_VERSION;
    out_selection->flags = flags;
    out_selection->catalog_index = index;
    out_selection->selection_word = selection_word;
    GEStatusV1 status = ge_ramrom_v5_catalog_entry(index,
                                                   &out_selection->catalog);
    if (status != GE_STATUS_OK) {
        return status;
    }
    return ge_title_route_v5_validate_demo_selection(out_selection);
}

GEStatusV1 ge_title_route_v5_make_restore_point(
    uint32_t previous_screen,
    int32_t selection,
    uint32_t file_option,
    uint32_t selected_folder,
    uint64_t state_hash,
    GETitleRouteRestorePointV5 *out_restore)
{
    if (out_restore == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    memset(out_restore, 0, sizeof(*out_restore));
    out_restore->header.abi_version = GE_NATIVE_ABI_VERSION;
    out_restore->header.struct_size = (uint32_t)sizeof(*out_restore);
    out_restore->record_version = GE_TITLE_ROUTE_V5_RECORD_VERSION;
    out_restore->flags = GE_TITLE_ROUTE_V5_RESTORE_VALID;
    out_restore->previous_screen = previous_screen;
    out_restore->selection = selection;
    out_restore->file_option = file_option;
    out_restore->selected_folder = selected_folder;
    out_restore->state_hash = state_hash;
    return ge_title_route_v5_validate_restore_point(out_restore);
}
