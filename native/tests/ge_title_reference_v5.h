#ifndef GE_TITLE_REFERENCE_V5_H
#define GE_TITLE_REFERENCE_V5_H

/*
 * Independent 60 Hz title reference used only by the parity smoke.  It is
 * deliberately a value-only test adapter: no Swift object, renderer state,
 * ROM address, or host pointer crosses this seam.
 */

#include <stdint.h>

#include "ge_native_runtime_v5.h"

#define GE_TITLE_REFERENCE_V5_CONTRACT_VERSION ((uint32_t)1u)
#define GE_TITLE_REFERENCE_V5_TRANSITION_FRAMES ((uint32_t)4u)
#define GE_TITLE_REFERENCE_V5_LEGAL_TICKS ((uint32_t)241u)
#define GE_TITLE_REFERENCE_V5_NINTENDO_TICKS ((uint32_t)501u)
#define GE_TITLE_REFERENCE_V5_RAREWARE_TICKS ((uint32_t)290u)
#define GE_TITLE_REFERENCE_V5_GOLDENEYE_TICKS ((uint32_t)180u)
#define GE_TITLE_REFERENCE_V5_GUNBARREL_TICKS ((uint32_t)682u)
#define GE_TITLE_REFERENCE_V5_FILE_SELECT_IDLE_TICKS ((uint32_t)1801u)
#define GE_TITLE_REFERENCE_V5_CAST_TICKS ((uint32_t)181u)

typedef struct GETitleReferenceStateV5 {
    GEAbiHeaderV1 header;
    uint32_t contract_version;
    uint64_t reference_tick;
    uint32_t screen;
    uint32_t timer;
    uint32_t pending_screen;
    uint32_t transition_remaining;
    uint32_t gunbarrel_mode;
    uint32_t first_boot;
    uint32_t legal_first_visit;
    int32_t title_x_q16;
    int32_t title_rotation_q16;
    int32_t title_scale_q16;
    int32_t alpha_q16;
    uint32_t selection;
    uint32_t demo_index;
    uint32_t source_threshold;
    uint32_t reserved0;
    uint64_t state_hash;
    uint64_t render_hash;
} GETitleReferenceStateV5;

GETitleReferenceStateV5 ge_title_reference_initial_v5(void);
GETitleReferenceStateV5 ge_title_reference_step_v5(GETitleReferenceStateV5 state);
GEStatusV1 ge_title_reference_validate_v5(const GETitleReferenceStateV5 *state);

#if defined(__cplusplus)
#define GE_TITLE_REFERENCE_STATIC_ASSERT(condition, message) static_assert((condition), message)
#else
#define GE_TITLE_REFERENCE_STATIC_ASSERT(condition, message) _Static_assert((condition), message)
#endif

GE_TITLE_REFERENCE_STATIC_ASSERT(sizeof(GETitleReferenceStateV5) == 104u,
                                 "GETitleReferenceStateV5 layout drift");

#undef GE_TITLE_REFERENCE_STATIC_ASSERT

#endif /* GE_TITLE_REFERENCE_V5_H */
