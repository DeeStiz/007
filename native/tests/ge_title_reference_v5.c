#include "ge_title_reference_v5.h"

#include <stddef.h>
#include <string.h>

static uint64_t ge_title_reference_hash_byte(uint64_t hash, uint8_t value)
{
    return (hash ^ (uint64_t)value) * UINT64_C(1099511628211);
}

static uint64_t ge_title_reference_hash_u64(uint64_t hash, uint64_t value)
{
    for (uint32_t index = 0u; index < 8u; index++) {
        hash = ge_title_reference_hash_byte(hash, (uint8_t)(value >> (index * 8u)));
    }
    return hash;
}

static uint64_t ge_title_reference_hash_state(const GETitleReferenceStateV5 *state)
{
    uint64_t hash = UINT64_C(1469598103934665603);
    const uint64_t words[] = {
        state->reference_tick,
        state->screen,
        state->timer,
        state->gunbarrel_mode,
        (uint64_t)(uint32_t)state->title_x_q16,
        (uint64_t)(uint32_t)state->title_rotation_q16,
        (uint64_t)(uint32_t)state->title_scale_q16,
        (uint64_t)(uint32_t)state->alpha_q16,
        state->selection,
        state->demo_index,
    };
    for (uint32_t index = 0u; index < sizeof(words) / sizeof(words[0]); index++) {
        hash = ge_title_reference_hash_u64(hash, words[index]);
    }
    return hash;
}

static uint64_t ge_title_reference_hash_render(const GETitleReferenceStateV5 *state)
{
    uint64_t hash = UINT64_C(1469598103934665603);
    const uint64_t words[] = {
        state->screen,
        state->gunbarrel_mode,
        (uint64_t)(uint32_t)state->title_x_q16,
        (uint64_t)(uint32_t)state->title_rotation_q16,
        (uint64_t)(uint32_t)state->title_scale_q16,
        (uint64_t)(uint32_t)state->alpha_q16,
        state->selection,
    };
    for (uint32_t index = 0u; index < sizeof(words) / sizeof(words[0]); index++) {
        hash = ge_title_reference_hash_u64(hash, words[index]);
    }
    return hash;
}

static void ge_title_reference_refresh_hashes(GETitleReferenceStateV5 *state)
{
    state->state_hash = ge_title_reference_hash_state(state);
    state->render_hash = ge_title_reference_hash_render(state);
}

static uint32_t ge_title_reference_threshold(uint32_t screen)
{
    switch (screen) {
    case GE_TITLE_SCREEN_LEGAL:
        return GE_TITLE_REFERENCE_V5_LEGAL_TICKS;
    case GE_TITLE_SCREEN_NINTENDO:
        return GE_TITLE_REFERENCE_V5_NINTENDO_TICKS;
    case GE_TITLE_SCREEN_RAREWARE:
        return GE_TITLE_REFERENCE_V5_RAREWARE_TICKS;
    case GE_TITLE_SCREEN_GOLDENEYE:
        return GE_TITLE_REFERENCE_V5_GOLDENEYE_TICKS;
    case GE_TITLE_SCREEN_FILE_SELECT:
        return GE_TITLE_REFERENCE_V5_FILE_SELECT_IDLE_TICKS;
    case GE_TITLE_SCREEN_CAST:
        return GE_TITLE_REFERENCE_V5_CAST_TICKS;
    default:
        return 0u;
    }
}

static void ge_title_reference_enter(GETitleReferenceStateV5 *state,
                                     uint32_t screen)
{
    const uint32_t prior_screen = state->screen;
    state->screen = screen;
    state->timer = 0u;
    state->pending_screen = UINT32_MAX;
    state->transition_remaining = 0u;
    state->source_threshold = ge_title_reference_threshold(screen);
    state->title_rotation_q16 = 0;
    state->title_scale_q16 = 0x00010000;
    state->alpha_q16 = 0x00010000;
    if (screen == GE_TITLE_SCREEN_GUNBARREL) {
        state->gunbarrel_mode = 2u;
        state->title_x_q16 = -30 * 0x00010000;
    } else if (screen == GE_TITLE_SCREEN_CAST) {
        state->gunbarrel_mode = 0u;
        /* The native attract owner starts the normal reel at source entry 1
           and advances through the eight non-extended entries available with
           the default progress flags before selecting a RAMROM demo.  The
           reference keeps that source index in the value-only selection
           field; no cast model data crosses this adapter. */
        if (prior_screen != GE_TITLE_SCREEN_CAST || state->selection == 0u) {
            state->selection = 1u;
        }
    }
}

static void ge_title_reference_schedule(GETitleReferenceStateV5 *state,
                                        uint32_t screen)
{
    state->pending_screen = screen;
    state->transition_remaining = GE_TITLE_REFERENCE_V5_TRANSITION_FRAMES;
}

GETitleReferenceStateV5 ge_title_reference_initial_v5(void)
{
    GETitleReferenceStateV5 state;
    memset(&state, 0, sizeof(state));
    state.header.abi_version = GE_NATIVE_ABI_VERSION;
    state.header.struct_size = (uint32_t)sizeof(state);
    state.contract_version = GE_TITLE_REFERENCE_V5_CONTRACT_VERSION;
    state.pending_screen = UINT32_MAX;
    state.first_boot = 1u;
    state.legal_first_visit = 1u;
    state.title_scale_q16 = 0x00010000;
    state.alpha_q16 = 0x00010000;
    state.source_threshold = GE_TITLE_REFERENCE_V5_LEGAL_TICKS;
    ge_title_reference_refresh_hashes(&state);
    return state;
}

GETitleReferenceStateV5 ge_title_reference_step_v5(GETitleReferenceStateV5 state)
{
    if (ge_title_reference_validate_v5(&state) != GE_STATUS_OK) {
        return state;
    }

    state.reference_tick += 1u;
    if (state.transition_remaining != 0u) {
        state.transition_remaining -= 1u;
        if (state.transition_remaining == 0u) {
            ge_title_reference_enter(&state, state.pending_screen);
        }
        ge_title_reference_refresh_hashes(&state);
        return state;
    }

    state.timer += 1u;
    switch (state.screen) {
    case GE_TITLE_SCREEN_LEGAL:
        if (state.timer >= GE_TITLE_REFERENCE_V5_LEGAL_TICKS) {
            state.legal_first_visit = 0u;
            ge_title_reference_schedule(&state, GE_TITLE_SCREEN_NINTENDO);
        }
        break;
    case GE_TITLE_SCREEN_NINTENDO:
        if (state.timer >= GE_TITLE_REFERENCE_V5_NINTENDO_TICKS) {
            ge_title_reference_schedule(&state, GE_TITLE_SCREEN_RAREWARE);
        }
        break;
    case GE_TITLE_SCREEN_RAREWARE:
        if (state.timer >= GE_TITLE_REFERENCE_V5_RAREWARE_TICKS) {
            ge_title_reference_schedule(&state, GE_TITLE_SCREEN_GUNBARREL);
        }
        break;
    case GE_TITLE_SCREEN_GUNBARREL:
        /* The visual submodes are exercised by the native renderer.  The
           reference adapter keeps the source screen transition auditable by
           using the source-authored mode durations as one bounded total. */
        state.gunbarrel_mode = 9u;
        if (state.timer >= GE_TITLE_REFERENCE_V5_GUNBARREL_TICKS) {
            ge_title_reference_schedule(&state, GE_TITLE_SCREEN_GOLDENEYE);
        }
        break;
    case GE_TITLE_SCREEN_GOLDENEYE:
        /* The source fixture records the strict `>` comparator.  The native
           paired projection reaches this anchor with one odd half-step
           already elapsed, so the independent reference enters on the
           corresponding >= source-frame boundary. */
        if (state.timer >= GE_TITLE_REFERENCE_V5_GOLDENEYE_TICKS) {
            state.first_boot = 0u;
            ge_title_reference_schedule(&state, GE_TITLE_SCREEN_CAST);
        }
        break;
    case GE_TITLE_SCREEN_CAST:
        if (state.timer >= GE_TITLE_REFERENCE_V5_CAST_TICKS) {
            if (state.selection < 8u) {
                state.selection += 1u;
                ge_title_reference_schedule(&state, GE_TITLE_SCREEN_CAST);
            } else {
                /* The Swift smoke requests catalog index zero explicitly so
                   RAMROM identity stays deterministic without private data. */
                state.demo_index = 0u;
                ge_title_reference_schedule(&state, GE_TITLE_SCREEN_RAMROM);
            }
        }
        break;
    case GE_TITLE_SCREEN_FILE_SELECT:
        if (state.timer >= GE_TITLE_REFERENCE_V5_FILE_SELECT_IDLE_TICKS) {
            ge_title_reference_schedule(&state, GE_TITLE_SCREEN_LEGAL);
        }
        break;
    default:
        break;
    }
    ge_title_reference_refresh_hashes(&state);
    return state;
}

GEStatusV1 ge_title_reference_validate_v5(const GETitleReferenceStateV5 *state)
{
    if (state == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (state->header.abi_version != GE_NATIVE_ABI_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    if (state->header.struct_size != sizeof(*state) ||
        state->contract_version != GE_TITLE_REFERENCE_V5_CONTRACT_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    if (state->screen > GE_TITLE_SCREEN_MAX ||
        (state->pending_screen != UINT32_MAX && state->pending_screen > GE_TITLE_SCREEN_MAX) ||
        state->first_boot > 1u || state->legal_first_visit > 1u ||
        state->reserved0 != 0u) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    return GE_STATUS_OK;
}
