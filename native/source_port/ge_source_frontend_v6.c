#include "ge_source_frontend_v6.h"

#include <limits.h>
#include <stddef.h>
#include <string.h>

/* Values are the NTSC constants in title.c, represented for diagnostics. */
#define GE_GUNBARREL_X_START_Q16 ((int32_t)-1966080)
#define GE_GUNBARREL_X_TRANSITION_Q16 ((int32_t)-6553600)
#define GE_GUNBARREL_X_RESET_Q16 ((int32_t)83623936)
#define GE_GUNBARREL_X_INC_Q16 ((int32_t)393216)
#define GE_GUNBARREL_X_DEC_Q16 ((int32_t)381310)
#define GE_GUNBARREL_X_LIMIT_Q16 ((int32_t)91095040)
#define GE_GUNBARREL_X_EXIT_Q16 ((int32_t)-5242880)
#define GE_GUNBARREL_INCVAL ((uint32_t)0x38eu)

/* Nintendo's US/NTSC constructor constants.  The source keeps these as
 * floating-point values, but the native frame seam is quantized to Q16.16 so
 * an odd render can be compared without platform-dependent float state. */
#define GE_NINTENDO_ROTATION_START_Q16 ((int32_t)-5242880) /* -80 degrees */
#define GE_NINTENDO_ROTATION_STEP_Q16 ((int32_t)65536)     /* +1 degree */
#define GE_NINTENDO_SCALE_START_Q16 ((uint32_t)1202u)     /* 0.0183333326 */
#define GE_NINTENDO_SCALE_LIMIT_Q16 ((uint32_t)72090u)     /* 1.1 */
#define GE_NINTENDO_SCALE_MULTIPLIER_Q16 ((uint32_t)70763u) /* 1.07977 */

static int32_t ge_frontend_q16_midpoint(int32_t current, int32_t next)
{
    int64_t sum = (int64_t)current + (int64_t)next;

    /* C division truncates toward zero, which is also the source's integer
     * quantization direction for the signed matrix/light fields. */
    return (int32_t)(sum / 2);
}

static uint32_t ge_frontend_nintendo_scale_for_render_index(uint32_t index)
{
    uint64_t scale = GE_NINTENDO_SCALE_START_Q16;

    while (index != 0u && scale < GE_NINTENDO_SCALE_LIMIT_Q16) {
        scale = (scale * GE_NINTENDO_SCALE_MULTIPLIER_Q16 + 32768u) >> 16u;
        if (scale > GE_NINTENDO_SCALE_LIMIT_Q16) {
            scale = GE_NINTENDO_SCALE_LIMIT_Q16;
        }
        index--;
    }
    return (uint32_t)scale;
}

static int32_t ge_frontend_nintendo_ambient_for_timer(uint32_t timer)
{
    int64_t numerator = (int64_t)timer * 255 - 94350;
    int64_t ambient = 255 - (numerator / 100);

    if (ambient > 255) {
        ambient = 255;
    }
    if (ambient < 0) {
        ambient = 0;
    }
    return (int32_t)ambient;
}

static int32_t ge_frontend_nintendo_rotation_for_render_index(uint32_t index)
{
    int64_t value = (int64_t)GE_NINTENDO_ROTATION_START_Q16 +
        (int64_t)index * GE_NINTENDO_ROTATION_STEP_Q16;

    if (value > INT32_MAX) {
        return INT32_MAX;
    }
    if (value < INT32_MIN) {
        return INT32_MIN;
    }
    return (int32_t)value;
}

static uint32_t ge_frontend_render_index_for_timer(uint32_t timer)
{
    /* Keep the Q16 projection on the same sourceTimer convention as the
     * shared Swift matrix provider: timer zero is the initial scale and each
     * subsequent source timer includes one committed scale multiplier. */
    return timer;
}

static int32_t ge_frontend_rareware_alpha_for_counter(uint32_t counter)
{
    int32_t var1 = (int32_t)(((uint64_t)counter * 255u) / 70u);
    int64_t numerator = (int64_t)counter * 255 - 40800;
    int32_t var2 = 255 - (int32_t)(numerator / 70);

    if (var1 > 255) {
        var1 = 255;
    }
    if (var1 < 0) {
        var1 = 0;
    }
    if (var2 > 255) {
        var2 = 255;
    }
    if (var2 < 0) {
        var2 = 0;
    }
    return (var1 * var2) / 255;
}

static int32_t ge_frontend_gunbarrel_next_title_x(
    const GEFrontendStateV6 *state)
{
    int64_t next;

    if (state == NULL) {
        return 0;
    }
    if (state->gunbarrel_mode == 2u) {
        next = (int64_t)state->gunbarrel_title_x_q16 + GE_GUNBARREL_X_INC_Q16;
        /* The source renders the current X, then commits the mode/reset.  The
         * next render therefore still uses the current X at this boundary;
         * the discrete mode change is never previewed on an odd tick. */
        return next > GE_GUNBARREL_X_LIMIT_Q16 ?
            state->gunbarrel_title_x_q16 : (int32_t)next;
    }
    if (state->gunbarrel_mode == 3u) {
        next = (int64_t)state->gunbarrel_title_x_q16 - GE_GUNBARREL_X_DEC_Q16;
        return next < INT32_MIN ? INT32_MIN : (int32_t)next;
    }
    return state->gunbarrel_title_x_q16;
}

static int32_t ge_frontend_gunbarrel_next_counter_q16(
    const GEFrontendStateV6 *state)
{
    int64_t current;
    int64_t next;

    if (state == NULL) {
        return 0;
    }
    current = (int64_t)state->gunbarrel_counter << 16u;
    switch (state->gunbarrel_mode) {
    case 2u:
    case 3u:
        return (int32_t)current;
    case 4u:
    case 5u:
        next = current - 65536;
        return next < INT32_MIN ? INT32_MIN : (int32_t)next;
    case 6u:
        next = current + 65536;
        return next > INT32_MAX ? INT32_MAX : (int32_t)next;
    case 7u:
        next = current + (8ll << 16u);
        return next > INT32_MAX ? INT32_MAX : (int32_t)next;
    case 8u:
        next = current + 65536;
        return next > INT32_MAX ? INT32_MAX : (int32_t)next;
    default:
        return (int32_t)current;
    }
}

static int32_t ge_frontend_gunbarrel_next_word_q16(
    const GEFrontendStateV6 *state)
{
    int64_t word;
    int64_t next;

    if (state == NULL) {
        return 0;
    }
    word = (int64_t)(uint16_t)state->gunbarrel_word << 16u;
    if (state->gunbarrel_mode == 2u) {
        /* The source tests the signed word before subtracting six.  The
         * branch itself remains even-anchor-only; odd rendering previews only
         * the linear delta when no wrap is required. */
        if ((int16_t)(uint16_t)state->gunbarrel_word < 0) {
            return (int32_t)word;
        }
        next = word - (6ll << 16u);
    } else if (state->gunbarrel_mode == 6u || state->gunbarrel_mode == 7u) {
        next = word + ((int64_t)GE_GUNBARREL_INCVAL << 16u);
    } else {
        return (int32_t)word;
    }
    if (next > INT32_MAX) {
        return INT32_MAX;
    }
    if (next < INT32_MIN) {
        return INT32_MIN;
    }
    return (int32_t)next;
}

static void ge_frontend_header(GEAbiHeaderV1 *header, uint32_t size)
{
    header->abi_version = GE_NATIVE_ABI_VERSION;
    header->struct_size = size;
}

/* The frozen state record keeps the historical blood-state field. During the
 * Gunbarrel route, its high half is the reset-on-entry source gunbarrelTimer
 * and its low half remains the blood/completion state. */
static uint32_t ge_frontend_gunbarrel_timer(const GEFrontendStateV6 *state)
{
    return state == NULL ? 0u : state->gunbarrel_blood_state >> 16u;
}

static uint32_t ge_frontend_gunbarrel_blood_state(const GEFrontendStateV6 *state)
{
    return state == NULL ? 0u : state->gunbarrel_blood_state & UINT32_C(0xffff);
}

static void ge_frontend_set_gunbarrel_blood_state(
    GEFrontendStateV6 *state,
    uint32_t value)
{
    state->gunbarrel_blood_state =
        (state->gunbarrel_blood_state & UINT32_C(0xffff0000)) |
        (value & UINT32_C(0xffff));
}

static void ge_frontend_advance_gunbarrel_timer(GEFrontendStateV6 *state)
{
    uint32_t timer = ge_frontend_gunbarrel_timer(state);
    if (timer < UINT32_C(0xffff)) {
        timer++;
    }
    state->gunbarrel_blood_state =
        (timer << 16u) | ge_frontend_gunbarrel_blood_state(state);
}

static GEStatusV1 ge_frontend_validate_header(
    const GEAbiHeaderV1 *header,
    uint32_t size,
    uint32_t record_version)
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
    if (record_version != GE_SOURCE_FRONTEND_V6_RECORD_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_frontend_v6_validate_input(const GEFrontendInputV6 *input)
{
    GEStatusV1 status;

    if (input == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_frontend_validate_header(
        &input->header, (uint32_t)sizeof(*input), input->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if ((input->flags & ~GE_SOURCE_FRONTEND_V6_INPUT_FLAG_MASK) != 0u ||
        (input->buttons_pressed & ~GE_SOURCE_FRONTEND_V6_BUTTON_MASK) != 0u ||
        input->controller_count > 4u || input->native_tick == 0u ||
        input->reserved0 != 0u || input->reserved1 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_frontend_v6_validate_snapshot(
    const GEFrontendSnapshotV6 *snapshot)
{
    GEStatusV1 status;

    if (snapshot == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_frontend_validate_header(
        &snapshot->header,
        (uint32_t)sizeof(*snapshot),
        snapshot->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (snapshot->screen > GE_SOURCE_FRONTEND_V6_SCREEN_MAX ||
        snapshot->reserved0 != 0u || snapshot->reserved1 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

static uint64_t ge_frontend_hash_mix(uint64_t hash, uint64_t value)
{
    uint32_t i;

    for (i = 0u; i < 8u; i++) {
        hash ^= (value >> (i * 8u)) & UINT64_C(0xff);
        hash *= UINT64_C(1099511628211);
    }
    return hash;
}

static uint64_t ge_frontend_audio_sample_for_tick(uint64_t native_tick)
{
    uint64_t whole_ticks = native_tick / 4u;
    uint64_t remainder = native_tick % 4u;
    uint64_t whole_samples;
    uint64_t remainder_samples = (remainder * 735u) / 4u;

    /* The public field is uint64_t.  Keep the multiplication checked so a
     * malformed far-future tick cannot wrap the audio cursor.  All runtime
     * ticks are well inside this representable range; saturation is the
     * deterministic fail-safe for an unrepresentable caller value. */
    if (whole_ticks > UINT64_MAX / 735u) {
        return UINT64_MAX;
    }
    whole_samples = whole_ticks * 735u;
    if (whole_samples > UINT64_MAX - remainder_samples) {
        return UINT64_MAX;
    }
    return whole_samples + remainder_samples;
}

static uint64_t ge_frontend_state_hash(const GEFrontendStateV6 *state)
{
    uint64_t hash = UINT64_C(1469598103934665603);

    hash = ge_frontend_hash_mix(hash, state->screen);
    hash = ge_frontend_hash_mix(hash, state->pending_reload);
    hash = ge_frontend_hash_mix(hash, state->pending_direct);
    hash = ge_frontend_hash_mix(hash, state->transition_timer);
    hash = ge_frontend_hash_mix(hash, state->source_timer);
    hash = ge_frontend_hash_mix(hash, state->source_frame);
    hash = ge_frontend_hash_mix(hash, state->flags);
    hash = ge_frontend_hash_mix(hash, state->rareware_mode);
    hash = ge_frontend_hash_mix(hash, state->rareware_counter);
    hash = ge_frontend_hash_mix(hash, state->gunbarrel_mode);
    hash = ge_frontend_hash_mix(hash, state->gunbarrel_counter);
    hash = ge_frontend_hash_mix(hash, state->gunbarrel_blood_state);
    hash = ge_frontend_hash_mix(hash, state->gunbarrel_word);
    hash = ge_frontend_hash_mix(hash, (uint32_t)state->gunbarrel_title_x_q16);
    hash = ge_frontend_hash_mix(hash, (uint32_t)state->gunbarrel_transition_x_q16);
    hash = ge_frontend_hash_mix(hash, state->native_tick);
    hash = ge_frontend_hash_mix(hash, state->event_sequence);
    return hash;
}

static uint64_t ge_frontend_continuous_hash(const GEFrontendStateV6 *state)
{
    uint64_t hash = UINT64_C(1469598103934665603);

    hash = ge_frontend_hash_mix(hash, state->screen);
    hash = ge_frontend_hash_mix(hash, state->source_timer);
    if (state->screen == GE_SOURCE_FRONTEND_V6_SCREEN_NINTENDO) {
        uint32_t index = ge_frontend_render_index_for_timer(state->source_timer);
        uint32_t next_index = index == UINT32_MAX ? UINT32_MAX : index + 1u;
        /* ninLogoRotRate is incremented before the source matrix is built;
         * unlike scale, its visual endpoint is the post-increment value. */
        hash = ge_frontend_hash_mix(
            hash,
            (uint32_t)ge_frontend_q16_midpoint(
                ge_frontend_nintendo_rotation_for_render_index(
                    state->source_timer),
                ge_frontend_nintendo_rotation_for_render_index(
                    state->source_timer == UINT32_MAX ? UINT32_MAX :
                        state->source_timer + 1u)));
        hash = ge_frontend_hash_mix(
            hash,
            ge_frontend_q16_midpoint(
                (int32_t)ge_frontend_nintendo_scale_for_render_index(index),
                (int32_t)ge_frontend_nintendo_scale_for_render_index(next_index)));
        hash = ge_frontend_hash_mix(
            hash,
            (uint32_t)ge_frontend_q16_midpoint(
                ge_frontend_nintendo_ambient_for_timer(state->source_timer) * 65536,
                ge_frontend_nintendo_ambient_for_timer(
                    state->source_timer == UINT32_MAX ? UINT32_MAX :
                        state->source_timer + 1u) * 65536));
    } else if (state->screen == GE_SOURCE_FRONTEND_V6_SCREEN_RAREWARE) {
        uint32_t next_counter = state->rareware_counter == UINT32_MAX ?
            UINT32_MAX : state->rareware_counter + 1u;
        hash = ge_frontend_hash_mix(
            hash,
            (uint32_t)ge_frontend_q16_midpoint(
                (int32_t)((uint64_t)state->rareware_counter * 2u * 65536u),
                (int32_t)((uint64_t)next_counter * 2u * 65536u)));
        hash = ge_frontend_hash_mix(
            hash,
            (uint32_t)ge_frontend_q16_midpoint(
                ge_frontend_rareware_alpha_for_counter(state->rareware_counter) * 65536,
                ge_frontend_rareware_alpha_for_counter(next_counter) * 65536));
    } else if (state->screen == GE_SOURCE_FRONTEND_V6_SCREEN_GUNBARREL) {
        hash = ge_frontend_hash_mix(
            hash,
            (uint32_t)ge_frontend_q16_midpoint(
                state->gunbarrel_title_x_q16,
                ge_frontend_gunbarrel_next_title_x(state)));
        hash = ge_frontend_hash_mix(
            hash,
            (uint32_t)ge_frontend_gunbarrel_next_counter_q16(state));
        hash = ge_frontend_hash_mix(
            hash,
            (uint32_t)ge_frontend_gunbarrel_next_word_q16(state));
    }
    return hash;
}

static GEStatusV1 ge_frontend_emit_diagnostic(
    GEFrontendStateV6 *state,
    const GEFrontendCallbacksV6 *callbacks,
    uint32_t code,
    uint32_t severity,
    uint32_t detail0,
    uint32_t detail1)
{
    GEFrontendDiagnosticV6 event;
    GEStatusV1 status = GE_STATUS_OK;

    state->unsupported_count++;
    state->flags |= GE_SOURCE_FRONTEND_V6_STATE_FLAG_UNSUPPORTED;

    if (callbacks == NULL || callbacks->diagnostic == NULL) {
        return GE_STATUS_OK;
    }

    memset(&event, 0, sizeof(event));
    ge_frontend_header(&event.header, (uint32_t)sizeof(event));
    event.record_version = GE_SOURCE_FRONTEND_V6_RECORD_VERSION;
    event.screen = state->screen;
    event.code = code;
    event.severity = severity;
    event.source_timer = state->source_timer;
    event.native_tick = state->native_tick;
    event.sequence = ++state->event_sequence;
    event.detail0 = detail0;
    event.detail1 = detail1;
    status = callbacks->diagnostic(&event, callbacks->context);
    return status == GE_STATUS_OK ? GE_STATUS_OK : status;
}

static GEStatusV1 ge_frontend_emit_screen(
    GEFrontendStateV6 *state,
    const GEFrontendCallbacksV6 *callbacks,
    uint32_t event_kind,
    uint32_t target)
{
    GEFrontendScreenEventV6 event;

    if (callbacks == NULL || callbacks->screen == NULL) {
        return GE_STATUS_OK;
    }

    memset(&event, 0, sizeof(event));
    ge_frontend_header(&event.header, (uint32_t)sizeof(event));
    event.record_version = GE_SOURCE_FRONTEND_V6_RECORD_VERSION;
    event.event = event_kind;
    event.screen = state->screen;
    event.target_screen = target;
    event.native_tick = state->native_tick;
    event.source_frame = state->source_frame;
    event.source_timer = state->source_timer;
    event.transition_timer = state->transition_timer;
    event.flags = state->flags;
    event.sequence = ++state->event_sequence;
    return callbacks->screen(&event, callbacks->context);
}

static GEStatusV1 ge_frontend_emit_render(
    GEFrontendStateV6 *state,
    const GEFrontendCallbacksV6 *callbacks,
    uint32_t operation,
    uint32_t subphase,
    int32_t value0,
    int32_t value1,
    uint32_t flags)
{
    GEFrontendRenderEventV6 event;
    GEStatusV1 status;

    if (callbacks == NULL || callbacks->render == NULL) {
        if (operation != GE_SOURCE_FRONTEND_V6_RENDER_FRAME_BEGIN) {
            return ge_frontend_emit_diagnostic(
                state,
                callbacks,
                GE_SOURCE_FRONTEND_V6_DIAG_UNSUPPORTED_RENDER,
                GE_SOURCE_FRONTEND_V6_DIAG_SEVERITY_WARNING,
                operation,
                subphase);
        }
        return GE_STATUS_OK;
    }

    memset(&event, 0, sizeof(event));
    ge_frontend_header(&event.header, (uint32_t)sizeof(event));
    event.record_version = GE_SOURCE_FRONTEND_V6_RECORD_VERSION;
    event.screen = state->screen;
    event.operation = operation;
    event.subphase = subphase;
    event.native_tick = state->native_tick;
    event.reference_tick = state->native_tick / 2u;
    event.source_timer = state->source_timer;
    event.value0 = value0;
    event.value1 = value1;
    event.flags = flags;
    if ((state->native_tick & 1u) != 0u) {
        /* All odd render work is an additive view of the current source
         * frame.  Keep it out of the source event sequence so the following
         * even anchor retains the exact oracle sequence/hash.  The high-bit
         * namespace still makes each emitted operation/subphase unambiguous
         * to a value-only consumer. */
        event.sequence = (UINT64_C(1) << 63) |
            (state->native_tick << 16u) |
            ((uint64_t)(operation & 0xffu) << 8u) |
            (uint64_t)(subphase & 0xffu);
    } else {
        event.sequence = ++state->event_sequence;
    }
    status = callbacks->render(&event, callbacks->context);
    return status == GE_STATUS_OK ? GE_STATUS_OK : status;
}

static GEStatusV1 ge_frontend_emit_continuous_state(
    GEFrontendStateV6 *state,
    const GEFrontendCallbacksV6 *callbacks,
    uint32_t subphase,
    int32_t value0,
    int32_t value1)
{
    return ge_frontend_emit_render(
        state,
        callbacks,
        GE_SOURCE_FRONTEND_V6_RENDER_CONTINUOUS_STATE,
        subphase,
        value0,
        value1,
        GE_SOURCE_FRONTEND_V6_RENDER_FLAG_HALF_STEP |
            GE_SOURCE_FRONTEND_V6_RENDER_FLAG_Q16_VALUES);
}

static GEStatusV1 ge_frontend_emit_model(
    GEFrontendStateV6 *state,
    const GEFrontendCallbacksV6 *callbacks,
    uint32_t model,
    uint32_t operation,
    uint32_t subphase,
    uint32_t flags,
    GEFrontendModelResultV6 *out_result)
{
    GEFrontendModelEventV6 event;
    GEFrontendModelResultV6 result;
    GEStatusV1 status;

    memset(&result, 0, sizeof(result));
    ge_frontend_header(&result.header, (uint32_t)sizeof(result));
    result.record_version = GE_SOURCE_FRONTEND_V6_RECORD_VERSION;
    result.flags = GE_SOURCE_FRONTEND_V6_MODEL_RESULT_NONE;

    if (callbacks == NULL || callbacks->model == NULL) {
        (void)ge_frontend_emit_diagnostic(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_DIAG_UNSUPPORTED_MODEL,
            GE_SOURCE_FRONTEND_V6_DIAG_SEVERITY_WARNING,
            model,
            operation);
        if (out_result != NULL) {
            *out_result = result;
        }
        return GE_STATUS_OK;
    }

    memset(&event, 0, sizeof(event));
    ge_frontend_header(&event.header, (uint32_t)sizeof(event));
    event.record_version = GE_SOURCE_FRONTEND_V6_RECORD_VERSION;
    event.screen = state->screen;
    event.model = model;
    event.operation = operation;
    event.native_tick = state->native_tick;
    event.reference_tick = state->native_tick / 2u;
    event.source_timer = state->source_timer;
    event.subphase = subphase;
    event.flags = flags;
    if (state->screen == GE_SOURCE_FRONTEND_V6_SCREEN_GUNBARREL &&
        model == GE_SOURCE_FRONTEND_V6_MODEL_GUNBARREL &&
        operation == GE_SOURCE_FRONTEND_V6_MODEL_OP_DRAW) {
        /* Gunbarrel's model timer is reset on route entry and advances once
         * per native model substep. Keep inherited g_MenuTimer in
         * event.source_timer; this additive flag carries the independent
         * title.c gunbarrelTimer without changing the 72-byte record. */
        event.flags = (event.flags &
            ~GE_SOURCE_FRONTEND_V6_MODEL_GUNBARREL_TIMER_MASK) |
            GE_SOURCE_FRONTEND_V6_MODEL_FLAG_GUNBARREL_TIMER_VALID |
            ((ge_frontend_gunbarrel_timer(state) & UINT32_C(0xffff)) <<
             GE_SOURCE_FRONTEND_V6_MODEL_GUNBARREL_TIMER_SHIFT);
    }
    if ((state->native_tick & 1u) != 0u &&
        operation == GE_SOURCE_FRONTEND_V6_MODEL_OP_DRAW) {
        /* Model draws on an odd tick are render-only paired extensions. */
        event.sequence = (UINT64_C(1) << 63) |
            (state->native_tick << 16u) |
            ((uint64_t)(operation & 0xffu) << 8u) |
            (uint64_t)(subphase & 0xffu);
    } else {
        event.sequence = ++state->event_sequence;
    }

    status = callbacks->model(&event, &result, callbacks->context);
    if (status != GE_STATUS_OK) {
        (void)ge_frontend_emit_diagnostic(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_DIAG_UNSUPPORTED_MODEL,
            GE_SOURCE_FRONTEND_V6_DIAG_SEVERITY_WARNING,
            model,
            operation);
        memset(&result, 0, sizeof(result));
        ge_frontend_header(&result.header, (uint32_t)sizeof(result));
        result.record_version = GE_SOURCE_FRONTEND_V6_RECORD_VERSION;
    }
    if ((result.flags & ~GE_SOURCE_FRONTEND_V6_MODEL_RESULT_MASK) != 0u) {
        (void)ge_frontend_emit_diagnostic(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_DIAG_INVALID_STATE,
            GE_SOURCE_FRONTEND_V6_DIAG_SEVERITY_ERROR,
            model,
            result.flags);
        result.flags &= GE_SOURCE_FRONTEND_V6_MODEL_RESULT_MASK;
    }
    if (out_result != NULL) {
        *out_result = result;
    }
    return GE_STATUS_OK;
}

static GEStatusV1 ge_frontend_emit_text(
    GEFrontendStateV6 *state,
    const GEFrontendCallbacksV6 *callbacks,
    uint32_t text_id,
    int32_t x,
    int32_t y,
    uint32_t flags)
{
    GEFrontendTextEventV6 event;
    GEStatusV1 status;

    if (callbacks == NULL || callbacks->text == NULL) {
        return ge_frontend_emit_diagnostic(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_DIAG_UNSUPPORTED_TEXT,
            GE_SOURCE_FRONTEND_V6_DIAG_SEVERITY_WARNING,
            text_id,
            0u);
    }

    memset(&event, 0, sizeof(event));
    ge_frontend_header(&event.header, (uint32_t)sizeof(event));
    event.record_version = GE_SOURCE_FRONTEND_V6_RECORD_VERSION;
    event.screen = state->screen;
    event.text_id = text_id;
    event.x = x;
    event.y = y;
    event.native_tick = state->native_tick;
    event.source_timer = state->source_timer;
    event.flags = flags;
    if ((state->native_tick & 1u) != 0u) {
        /* Text packets are render-only on odd ticks; do not perturb the
         * source event sequence used by the next even anchor. */
        event.sequence = (UINT64_C(1) << 63) |
            (state->native_tick << 16u) |
            ((uint64_t)GE_SOURCE_FRONTEND_V6_RENDER_SOURCE_TEXT << 8u) |
            (uint64_t)(text_id & 0xffu);
    } else {
        event.sequence = ++state->event_sequence;
    }
    status = callbacks->text(&event, callbacks->context);
    if (status != GE_STATUS_OK) {
        (void)ge_frontend_emit_diagnostic(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_DIAG_UNSUPPORTED_TEXT,
            GE_SOURCE_FRONTEND_V6_DIAG_SEVERITY_WARNING,
            text_id,
            status);
    }
    return GE_STATUS_OK;
}

static GEStatusV1 ge_frontend_emit_audio(
    GEFrontendStateV6 *state,
    const GEFrontendCallbacksV6 *callbacks,
    uint32_t operation,
    uint32_t asset_id)
{
    GEFrontendAudioEventV6 event;
    GEStatusV1 status;

    if (callbacks == NULL || callbacks->audio == NULL) {
        return ge_frontend_emit_diagnostic(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_DIAG_UNSUPPORTED_AUDIO,
            GE_SOURCE_FRONTEND_V6_DIAG_SEVERITY_WARNING,
            operation,
            asset_id);
    }

    memset(&event, 0, sizeof(event));
    ge_frontend_header(&event.header, (uint32_t)sizeof(event));
    event.record_version = GE_SOURCE_FRONTEND_V6_RECORD_VERSION;
    event.screen = state->screen;
    event.operation = operation;
    event.asset_id = asset_id;
    event.native_tick = state->native_tick;
    event.source_sample = ge_frontend_audio_sample_for_tick(state->native_tick);
    event.source_timer = state->source_timer;
    event.flags = (state->native_tick & 1u) == 0u ?
        GE_SOURCE_FRONTEND_V6_INPUT_FLAG_SOURCE_ANCHOR : 0u;
    event.sequence = ++state->event_sequence;
    status = callbacks->audio(&event, callbacks->context);
    if (status != GE_STATUS_OK) {
        (void)ge_frontend_emit_diagnostic(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_DIAG_UNSUPPORTED_AUDIO,
            GE_SOURCE_FRONTEND_V6_DIAG_SEVERITY_WARNING,
            operation,
            asset_id);
    }
    return GE_STATUS_OK;
}

static GEStatusV1 ge_frontend_emit_save(
    GEFrontendStateV6 *state,
    const GEFrontendCallbacksV6 *callbacks,
    uint32_t operation,
    uint32_t folder)
{
    GEFrontendSaveEventV6 event;
    GEStatusV1 status;

    if (callbacks == NULL || callbacks->save == NULL) {
        return ge_frontend_emit_diagnostic(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_DIAG_UNSUPPORTED_SAVE,
            GE_SOURCE_FRONTEND_V6_DIAG_SEVERITY_WARNING,
            operation,
            folder);
    }

    memset(&event, 0, sizeof(event));
    ge_frontend_header(&event.header, (uint32_t)sizeof(event));
    event.record_version = GE_SOURCE_FRONTEND_V6_RECORD_VERSION;
    event.screen = state->screen;
    event.operation = operation;
    event.folder = folder;
    event.native_tick = state->native_tick;
    event.sequence = ++state->event_sequence;
    status = callbacks->save(&event, callbacks->context);
    if (status != GE_STATUS_OK) {
        (void)ge_frontend_emit_diagnostic(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_DIAG_UNSUPPORTED_SAVE,
            GE_SOURCE_FRONTEND_V6_DIAG_SEVERITY_WARNING,
            operation,
            folder);
    }
    return GE_STATUS_OK;
}

static uint32_t ge_frontend_model_for_screen(uint32_t screen)
{
    switch (screen) {
    case GE_SOURCE_FRONTEND_V6_SCREEN_LEGAL:
        return GE_SOURCE_FRONTEND_V6_MODEL_LEGALPAGE;
    case GE_SOURCE_FRONTEND_V6_SCREEN_NINTENDO:
        return GE_SOURCE_FRONTEND_V6_MODEL_NINTENDOLOGO;
    case GE_SOURCE_FRONTEND_V6_SCREEN_RAREWARE:
        return GE_SOURCE_FRONTEND_V6_MODEL_RAREWARELOGO;
    case GE_SOURCE_FRONTEND_V6_SCREEN_GUNBARREL:
        return GE_SOURCE_FRONTEND_V6_MODEL_GUNBARREL;
    case GE_SOURCE_FRONTEND_V6_SCREEN_GOLDENEYE:
        return GE_SOURCE_FRONTEND_V6_MODEL_GOLDENEYELOGO;
    case GE_SOURCE_FRONTEND_V6_SCREEN_FILE_SELECT:
    case GE_SOURCE_FRONTEND_V6_SCREEN_MODE_SELECT:
        return GE_SOURCE_FRONTEND_V6_MODEL_WALLETBOND;
    default:
        return GE_SOURCE_FRONTEND_V6_MODEL_NONE;
    }
}

static GEStatusV1 ge_frontend_emit_enter(
    GEFrontendStateV6 *state,
    const GEFrontendCallbacksV6 *callbacks)
{
    uint32_t model;

    (void)ge_frontend_emit_screen(
        state,
        callbacks,
        GE_SOURCE_FRONTEND_V6_EVENT_SCREEN_ENTER,
        GE_SOURCE_FRONTEND_V6_SCREEN_INVALID);

    switch (state->screen) {
    case GE_SOURCE_FRONTEND_V6_SCREEN_LEGAL:
        (void)ge_frontend_emit_audio(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_AUDIO_OP_STOP_MUSIC,
            GE_SOURCE_FRONTEND_V6_AUDIO_MUSIC_STOP);
        (void)ge_frontend_emit_save(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_SAVE_VALIDATE,
            UINT32_MAX);
        break;
    case GE_SOURCE_FRONTEND_V6_SCREEN_NINTENDO:
        (void)ge_frontend_emit_audio(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_AUDIO_OP_PLAY_MUSIC,
            GE_SOURCE_FRONTEND_V6_AUDIO_INTRO_SWOOSH);
        break;
    case GE_SOURCE_FRONTEND_V6_SCREEN_RAREWARE:
        (void)ge_frontend_emit_audio(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_AUDIO_OP_PLAY_SFX,
            GE_SOURCE_FRONTEND_V6_AUDIO_RAREWARE_SFX);
        break;
    case GE_SOURCE_FRONTEND_V6_SCREEN_GUNBARREL:
        (void)ge_frontend_emit_audio(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_AUDIO_OP_PLAY_MUSIC,
            GE_SOURCE_FRONTEND_V6_AUDIO_INTRO);
        break;
    case GE_SOURCE_FRONTEND_V6_SCREEN_GOLDENEYE:
        /* constructor_menu04_goldeneyelogo owns the model; no enter-side cue. */
        break;
    case GE_SOURCE_FRONTEND_V6_SCREEN_FILE_SELECT:
        (void)ge_frontend_emit_audio(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_AUDIO_OP_PLAY_MUSIC,
            GE_SOURCE_FRONTEND_V6_AUDIO_FOLDERS);
        (void)ge_frontend_emit_save(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_SAVE_LOAD_WALLET,
            0u);
        break;
    case GE_SOURCE_FRONTEND_V6_SCREEN_MODE_SELECT:
        (void)ge_frontend_emit_save(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_SAVE_LOAD_WALLET,
            0u);
        (void)ge_frontend_emit_save(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_SAVE_UPDATE_BOND,
            0u);
        break;
    case GE_SOURCE_FRONTEND_V6_SCREEN_CAST:
        /* Cast model/animation selection is consumed by the owner-side
         * source Cast request; entering the screen itself has no additional
         * save/audio cue in the normal attract route. */
        break;
    case GE_SOURCE_FRONTEND_V6_SCREEN_SWITCH:
        break;
    default:
        (void)ge_frontend_emit_diagnostic(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_DIAG_UNSUPPORTED_RENDER,
            GE_SOURCE_FRONTEND_V6_DIAG_SEVERITY_WARNING,
            state->screen,
            0u);
        break;
    }

    model = ge_frontend_model_for_screen(state->screen);
    if (model != GE_SOURCE_FRONTEND_V6_MODEL_NONE) {
        (void)ge_frontend_emit_model(
            state,
            callbacks,
            model,
            GE_SOURCE_FRONTEND_V6_MODEL_OP_LOAD,
            0u,
            0u,
            NULL);
    }
    return GE_STATUS_OK;
}

static GEStatusV1 ge_frontend_emit_exit(
    GEFrontendStateV6 *state,
    const GEFrontendCallbacksV6 *callbacks,
    uint32_t target)
{
    uint32_t model = ge_frontend_model_for_screen(state->screen);

    (void)ge_frontend_emit_screen(
        state,
        callbacks,
        GE_SOURCE_FRONTEND_V6_EVENT_SCREEN_EXIT,
        target);

    if (model != GE_SOURCE_FRONTEND_V6_MODEL_NONE &&
        state->screen != GE_SOURCE_FRONTEND_V6_SCREEN_RAREWARE) {
        (void)ge_frontend_emit_model(
            state,
            callbacks,
            model,
            GE_SOURCE_FRONTEND_V6_MODEL_OP_RELEASE,
            0u,
            0u,
            NULL);
    }
    return GE_STATUS_OK;
}

static GEStatusV1 ge_frontend_request_reload(
    GEFrontendStateV6 *state,
    const GEFrontendCallbacksV6 *callbacks,
    uint32_t target)
{
    if (target > GE_SOURCE_FRONTEND_V6_SCREEN_MAX ||
        target == GE_SOURCE_FRONTEND_V6_SCREEN_SWITCH) {
        return ge_frontend_emit_diagnostic(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_DIAG_INVALID_STATE,
            GE_SOURCE_FRONTEND_V6_DIAG_SEVERITY_ERROR,
            target,
            GE_SOURCE_FRONTEND_V6_SCREEN_SWITCH);
    }
    if (state->pending_reload != GE_SOURCE_FRONTEND_V6_SCREEN_INVALID) {
        return GE_STATUS_INVALID_STATE;
    }
    state->pending_reload = target;
    (void)ge_frontend_emit_screen(
        state,
        callbacks,
        GE_SOURCE_FRONTEND_V6_EVENT_TRANSITION,
        target);
    return GE_STATUS_OK;
}

static void ge_frontend_reset_screen_values(GEFrontendStateV6 *state)
{
    state->source_timer = 0u;
    state->transition_timer = 0u;
    state->rareware_mode = GE_SOURCE_FRONTEND_V6_RAREWARE_MODE_INIT;
    state->rareware_counter = 0u;
    state->gunbarrel_mode = GE_SOURCE_FRONTEND_V6_GUNBARREL_MODE_INIT;
    state->gunbarrel_counter = 0u;
    state->gunbarrel_blood_state = 0u;
    state->gunbarrel_word = UINT32_C(0x42);
    state->gunbarrel_title_x_q16 = GE_GUNBARREL_X_START_Q16;
    state->gunbarrel_transition_x_q16 = GE_GUNBARREL_X_TRANSITION_Q16;
}

static GEStatusV1 ge_frontend_enter_screen(
    GEFrontendStateV6 *state,
    const GEFrontendCallbacksV6 *callbacks,
    uint32_t target)
{
    state->screen = target;
    state->pending_direct = GE_SOURCE_FRONTEND_V6_SCREEN_INVALID;
    state->pending_reload = GE_SOURCE_FRONTEND_V6_SCREEN_INVALID;
    ge_frontend_reset_screen_values(state);
    return ge_frontend_emit_enter(state, callbacks);
}

static GEStatusV1 ge_frontend_start_switch(
    GEFrontendStateV6 *state,
    const GEFrontendCallbacksV6 *callbacks)
{
    uint32_t target = state->pending_reload;

    /* update_menu00_legalscreen/update_menu04_goldeneye run here, before the
     * source enters MENU_SWITCH_SCREENS. */
    if (state->screen == GE_SOURCE_FRONTEND_V6_SCREEN_LEGAL) {
        state->flags &= ~GE_SOURCE_FRONTEND_V6_STATE_FLAG_FIRST_BOOT;
    }
    if (state->screen == GE_SOURCE_FRONTEND_V6_SCREEN_GOLDENEYE) {
        state->flags &= ~GE_SOURCE_FRONTEND_V6_STATE_FLAG_FIRST_MAIN_MENU;
    }
    (void)ge_frontend_emit_exit(state, callbacks, target);
    state->screen = GE_SOURCE_FRONTEND_V6_SCREEN_SWITCH;
    state->source_timer = 0u;
    state->transition_timer = 0u;
    state->flags &= ~GE_SOURCE_FRONTEND_V6_STATE_FLAG_TRANSITION_READY;
    return GE_STATUS_OK;
}

static GEStatusV1 ge_frontend_menu_init(
    GEFrontendStateV6 *state,
    const GEFrontendCallbacksV6 *callbacks)
{
    GEStatusV1 status = GE_STATUS_OK;

    if (state->screen == GE_SOURCE_FRONTEND_V6_SCREEN_SWITCH) {
        if ((state->flags & GE_SOURCE_FRONTEND_V6_STATE_FLAG_TRANSITION_READY) != 0u) {
            uint32_t target = state->pending_reload;
            state->flags &= ~GE_SOURCE_FRONTEND_V6_STATE_FLAG_TRANSITION_READY;
            status = ge_frontend_enter_screen(state, callbacks, target);
        }
        return status;
    }

    if (state->pending_reload != GE_SOURCE_FRONTEND_V6_SCREEN_INVALID) {
        status = ge_frontend_start_switch(state, callbacks);
        if (status != GE_STATUS_OK) {
            return status;
        }
        return GE_STATUS_OK;
    }

    if (state->pending_direct != GE_SOURCE_FRONTEND_V6_SCREEN_INVALID) {
        status = ge_frontend_enter_screen(
            state, callbacks, state->pending_direct);
    }
    return status;
}

static uint32_t ge_frontend_input_pressed(const GEFrontendInputV6 *input)
{
    return input->buttons_pressed != GE_SOURCE_FRONTEND_V6_BUTTON_NONE;
}

static GEStatusV1 ge_frontend_step_interface(
    GEFrontendStateV6 *state,
    const GEFrontendInputV6 *input,
    const GEFrontendCallbacksV6 *callbacks,
    uint32_t source_anchor,
    uint32_t source_ordered)
{
    uint32_t pressed = ge_frontend_input_pressed(input);

    /* Retained for the legacy/source-ordered entry-point ABI.  Autonomous
     * branches are now anchor-only in both paths; the distinction is applied
     * by the caller's transition-ordering phase below. */
    (void)source_ordered;
    state->controller_count = input->controller_count;

    if (state->screen == GE_SOURCE_FRONTEND_V6_SCREEN_SWITCH) {
        if (source_anchor && state->transition_timer < GE_SOURCE_FRONTEND_V6_SWITCH_TIMER_MAX) {
            state->transition_timer++;
            state->source_timer = state->transition_timer;
            if (state->transition_timer >= GE_SOURCE_FRONTEND_V6_SWITCH_TIMER_MAX) {
                state->flags |= GE_SOURCE_FRONTEND_V6_STATE_FLAG_TRANSITION_READY;
            }
        }
        return GE_STATUS_OK;
    }

    switch (state->screen) {
    case GE_SOURCE_FRONTEND_V6_SCREEN_LEGAL:
        if (source_anchor) {
            state->source_timer++;
        }
        if (source_anchor != 0u &&
            state->source_timer >= GE_SOURCE_FRONTEND_V6_LEGAL_TIMER_MAX) {
            if (state->controller_count < 1u &&
                (state->flags & GE_SOURCE_FRONTEND_V6_STATE_FLAG_FIRST_BOOT) != 0u) {
                (void)ge_frontend_request_reload(
                    state, callbacks, GE_SOURCE_FRONTEND_V6_SCREEN_NO_CONTROLLERS);
            } else {
                (void)ge_frontend_request_reload(
                    state, callbacks, GE_SOURCE_FRONTEND_V6_SCREEN_NINTENDO);
            }
        } else if (pressed &&
                   (state->flags & GE_SOURCE_FRONTEND_V6_STATE_FLAG_FIRST_BOOT) == 0u) {
            if ((state->flags & GE_SOURCE_FRONTEND_V6_STATE_FLAG_FIRST_MAIN_MENU) == 0u) {
                (void)ge_frontend_request_reload(
                    state, callbacks, GE_SOURCE_FRONTEND_V6_SCREEN_FILE_SELECT);
            } else {
                (void)ge_frontend_request_reload(
                    state, callbacks, GE_SOURCE_FRONTEND_V6_SCREEN_NINTENDO);
            }
        }
        break;

    case GE_SOURCE_FRONTEND_V6_SCREEN_NINTENDO:
        if (source_anchor) {
            state->source_timer++;
        }
        if (source_anchor != 0u &&
            state->source_timer >= GE_SOURCE_FRONTEND_V6_NINTENDO_TIMER_MAX) {
            (void)ge_frontend_request_reload(
                state, callbacks, GE_SOURCE_FRONTEND_V6_SCREEN_RAREWARE);
        } else if (pressed) {
            if ((state->flags & GE_SOURCE_FRONTEND_V6_STATE_FLAG_FIRST_MAIN_MENU) == 0u) {
                (void)ge_frontend_request_reload(
                    state, callbacks, GE_SOURCE_FRONTEND_V6_SCREEN_FILE_SELECT);
            } else {
                state->flags |= GE_SOURCE_FRONTEND_V6_STATE_FLAG_PREV_KEYPRESS;
                (void)ge_frontend_request_reload(
                    state, callbacks, GE_SOURCE_FRONTEND_V6_SCREEN_RAREWARE);
            }
        }
        break;

    case GE_SOURCE_FRONTEND_V6_SCREEN_RAREWARE:
        if (state->rareware_mode == GE_SOURCE_FRONTEND_V6_RAREWARE_MODE_READY &&
            source_anchor != 0u) {
            (void)ge_frontend_request_reload(
                state, callbacks, GE_SOURCE_FRONTEND_V6_SCREEN_GUNBARREL);
        } else if (pressed) {
            if ((state->flags & GE_SOURCE_FRONTEND_V6_STATE_FLAG_FIRST_MAIN_MENU) == 0u) {
                (void)ge_frontend_request_reload(
                    state, callbacks, GE_SOURCE_FRONTEND_V6_SCREEN_FILE_SELECT);
            } else {
                state->flags |= GE_SOURCE_FRONTEND_V6_STATE_FLAG_PREV_KEYPRESS;
                (void)ge_frontend_request_reload(
                    state, callbacks, GE_SOURCE_FRONTEND_V6_SCREEN_GUNBARREL);
            }
        }
        break;

    case GE_SOURCE_FRONTEND_V6_SCREEN_GUNBARREL:
        if (state->gunbarrel_mode == GE_SOURCE_FRONTEND_V6_GUNBARREL_MODE_GOLDENEYE &&
            source_anchor != 0u) {
            (void)ge_frontend_request_reload(
                state, callbacks, GE_SOURCE_FRONTEND_V6_SCREEN_GOLDENEYE);
        } else if (pressed) {
            if ((state->flags & GE_SOURCE_FRONTEND_V6_STATE_FLAG_FIRST_MAIN_MENU) == 0u) {
                (void)ge_frontend_request_reload(
                    state, callbacks, GE_SOURCE_FRONTEND_V6_SCREEN_FILE_SELECT);
            } else {
                state->flags |= GE_SOURCE_FRONTEND_V6_STATE_FLAG_PREV_KEYPRESS;
                (void)ge_frontend_request_reload(
                    state, callbacks, GE_SOURCE_FRONTEND_V6_SCREEN_GOLDENEYE);
            }
        }
        break;

    case GE_SOURCE_FRONTEND_V6_SCREEN_GOLDENEYE:
        if (source_anchor) {
            state->source_timer++;
        }
        if ((source_anchor != 0u) &&
            (((state->flags & GE_SOURCE_FRONTEND_V6_STATE_FLAG_FIRST_MAIN_MENU) == 0u) ||
             (state->source_timer > GE_SOURCE_FRONTEND_V6_GOLDENEYE_TIMER_1) ||
             (((state->flags & GE_SOURCE_FRONTEND_V6_STATE_FLAG_GE_LOGO_BOOL) != 0u) &&
              (state->source_timer > GE_SOURCE_FRONTEND_V6_GOLDENEYE_TIMER_2)))) {
            if (state->source_timer > GE_SOURCE_FRONTEND_V6_GOLDENEYE_TIMER_1) {
                if ((state->flags & GE_SOURCE_FRONTEND_V6_STATE_FLAG_PREV_KEYPRESS) != 0u) {
                    (void)ge_frontend_request_reload(
                        state, callbacks, GE_SOURCE_FRONTEND_V6_SCREEN_FILE_SELECT);
                } else {
                    (void)ge_frontend_request_reload(
                        state, callbacks, GE_SOURCE_FRONTEND_V6_SCREEN_CAST);
                }
            } else if (pressed ||
                       (((state->flags & GE_SOURCE_FRONTEND_V6_STATE_FLAG_FIRST_MAIN_MENU) != 0u) &&
                        ((state->flags & GE_SOURCE_FRONTEND_V6_STATE_FLAG_GE_LOGO_BOOL) != 0u))) {
                (void)ge_frontend_request_reload(
                    state, callbacks, GE_SOURCE_FRONTEND_V6_SCREEN_FILE_SELECT);
            }
        } else if (pressed) {
            /* Input edges are allowed on either native phase.  They must not
             * inherit the autonomous timer branch above, so a short odd-tick
             * press still changes authority within one native tick. */
            if ((state->flags & GE_SOURCE_FRONTEND_V6_STATE_FLAG_FIRST_MAIN_MENU) == 0u) {
                (void)ge_frontend_request_reload(
                    state, callbacks, GE_SOURCE_FRONTEND_V6_SCREEN_FILE_SELECT);
            } else {
                state->flags |= GE_SOURCE_FRONTEND_V6_STATE_FLAG_GE_LOGO_BOOL;
            }
        }
        break;

    case GE_SOURCE_FRONTEND_V6_SCREEN_FILE_SELECT:
        if (source_anchor) {
            if (pressed) {
                state->source_timer = 0u;
            } else {
                state->source_timer++;
            }
        }
        if (source_anchor != 0u &&
            state->source_timer >= GE_SOURCE_FRONTEND_V6_FILE_IDLE_TIMER_MAX) {
            (void)ge_frontend_request_reload(
                state, callbacks, GE_SOURCE_FRONTEND_V6_SCREEN_LEGAL);
        }
        break;

    case GE_SOURCE_FRONTEND_V6_SCREEN_MODE_SELECT:
        /* The source mode screen has no autonomous timer. */
        break;

    case GE_SOURCE_FRONTEND_V6_SCREEN_CAST:
        if (source_anchor) {
            state->source_timer++;
            /* front.c's interface_menu18_displaycast advances the source
             * roster at timer 181 by requesting the next Cast transition.
             * Keep this source-owned switch explicit so the paired original
             * authority observes the same transition/exit events instead of
             * leaving native Cast latched on screen 25. */
            if (state->source_timer >= 181u) {
                (void)ge_frontend_request_reload(
                    state, callbacks, GE_SOURCE_FRONTEND_V6_SCREEN_CAST);
            }
        }
        if (pressed) {
            (void)ge_frontend_request_reload(
                state, callbacks, GE_SOURCE_FRONTEND_V6_SCREEN_FILE_SELECT);
        }
        break;

    case GE_SOURCE_FRONTEND_V6_SCREEN_NO_CONTROLLERS:
        (void)ge_frontend_emit_diagnostic(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_DIAG_UNSUPPORTED_RENDER,
            GE_SOURCE_FRONTEND_V6_DIAG_SEVERITY_WARNING,
            GE_SOURCE_FRONTEND_V6_SCREEN_NO_CONTROLLERS,
            0u);
        break;

    default:
        (void)ge_frontend_emit_diagnostic(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_DIAG_INVALID_STATE,
            GE_SOURCE_FRONTEND_V6_DIAG_SEVERITY_ERROR,
            state->screen,
            0u);
        return GE_STATUS_INVALID_STATE;
    }

    return GE_STATUS_OK;
}

static GEStatusV1 ge_frontend_render_rareware(
    GEFrontendStateV6 *state,
    const GEFrontendCallbacksV6 *callbacks,
    uint32_t source_anchor)
{
    uint32_t old_counter = state->rareware_counter;
    int32_t var1;
    int32_t var2;
    int32_t alpha;

    var1 = (int32_t)((old_counter * 255u) / 70u);
    if (var1 > 255) {
        var1 = 255;
    }
    var2 = 255 - (int32_t)(((int64_t)old_counter * 255 - 40800) / 70);
    if (var2 > 255) {
        var2 = 255;
    }
    if (var1 < 0) {
        var1 = 0;
    }
    if (var2 < 0) {
        var2 = 0;
    }
    alpha = (var1 * var2) / 255;
    /* The dedicated Rareware segment is entered through a source model
     * request just like Nintendo/GoldenEye.  Keep the draw event paired with
     * the render pipeline: even anchors carry the source mode, while odd
     * native renders carry the explicit half-step flag and sequence namespace
     * from ge_frontend_emit_model.  The LOAD/RELEASE lifecycle remains owned
     * by ge_frontend_emit_enter/ge_frontend_emit_exit. */
    (void)ge_frontend_emit_model(
        state,
        callbacks,
        GE_SOURCE_FRONTEND_V6_MODEL_RAREWARELOGO,
        GE_SOURCE_FRONTEND_V6_MODEL_OP_DRAW,
        state->rareware_mode,
        source_anchor == 0u ? GE_SOURCE_FRONTEND_V6_MODEL_FLAG_HALF_STEP : 0u,
        NULL);
    (void)ge_frontend_emit_render(
        state,
        callbacks,
        GE_SOURCE_FRONTEND_V6_RENDER_RAREWARE_PIPELINE,
        state->rareware_mode,
        (int32_t)alpha,
        (int32_t)old_counter,
        0u);

    if (source_anchor == 0u &&
        (state->rareware_mode == GE_SOURCE_FRONTEND_V6_RAREWARE_MODE_INIT ||
         state->rareware_mode == 1u)) {
        uint32_t next_counter = old_counter == UINT32_MAX ?
            UINT32_MAX : old_counter + 1u;
        int32_t current_rotation = (int32_t)((uint64_t)old_counter * 2u * 65536u);
        int32_t next_rotation = (int32_t)((uint64_t)next_counter * 2u * 65536u);
        int32_t next_alpha = ge_frontend_rareware_alpha_for_counter(next_counter);

        /* title.c advances D_8002A89C by two degrees and intro_eye_counter
         * after the source render.  The odd frame is exactly their midpoint;
         * mode/threshold changes remain deferred to the even anchor. */
        (void)ge_frontend_emit_continuous_state(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_CONTINUOUS_RAREWARE_ROTATION_ALPHA,
            ge_frontend_q16_midpoint(current_rotation, next_rotation),
            ge_frontend_q16_midpoint(alpha * 65536, next_alpha * 65536));
    }

    if (source_anchor != 0u &&
        (state->rareware_mode == 0u || state->rareware_mode == 1u)) {
        state->rareware_counter = old_counter + 1u;
        /* Exact source order: postincrement comparison, then >=290 test. */
        if (old_counter >= GE_SOURCE_FRONTEND_V6_RAREWARE_EYE_COUNT_1 &&
            state->rareware_counter >= GE_SOURCE_FRONTEND_V6_RAREWARE_EYE_COUNT_2) {
            state->rareware_counter = 0u;
            state->rareware_mode = GE_SOURCE_FRONTEND_V6_RAREWARE_MODE_READY;
        }
    }
    return GE_STATUS_OK;
}

static void ge_frontend_emit_gunbarrel_half_step_model(
    GEFrontendStateV6 *state,
    const GEFrontendCallbacksV6 *callbacks)
{
    uint32_t subphase;

    if (state == NULL || callbacks == NULL || callbacks->model == NULL) {
        return;
    }
    if (state->gunbarrel_mode < GE_SOURCE_FRONTEND_V6_GUNBARREL_MODE_INIT ||
        state->gunbarrel_mode >= 8u) {
        return;
    }
    subphase = state->gunbarrel_mode - GE_SOURCE_FRONTEND_V6_GUNBARREL_MODE_INIT;
    (void)ge_frontend_emit_model(
        state,
        callbacks,
        GE_SOURCE_FRONTEND_V6_MODEL_GUNBARREL,
        GE_SOURCE_FRONTEND_V6_MODEL_OP_DRAW,
        subphase,
        ge_frontend_gunbarrel_blood_state(state) |
            GE_SOURCE_FRONTEND_V6_MODEL_FLAG_HALF_STEP,
        NULL);
}

static GEStatusV1 ge_frontend_render_gunbarrel(
    GEFrontendStateV6 *state,
    const GEFrontendCallbacksV6 *callbacks,
    uint32_t source_anchor)
{
    GEFrontendModelResultV6 result;
    uint32_t mode = state->gunbarrel_mode;
    int32_t old_x = state->gunbarrel_title_x_q16;
    int32_t render_x = old_x;
    int32_t render_counter = (int32_t)state->gunbarrel_counter;

    if (mode >= 3u && mode <= 7u &&
        (mode != 3u || old_x < (600 * 65536))) {
        /* Both native halves execute one source modelTickAnim substep. The
         * timer persists through modes 3..7; only its low blood half is reset
         * when the route changes semantic phase. */
        ge_frontend_advance_gunbarrel_timer(state);
    }

    memset(&result, 0, sizeof(result));
    ge_frontend_header(&result.header, (uint32_t)sizeof(result));
    result.record_version = GE_SOURCE_FRONTEND_V6_RECORD_VERSION;

    if (source_anchor == 0u) {
        int32_t next_x = ge_frontend_gunbarrel_next_title_x(state);
        int32_t next_counter_q16 = ge_frontend_gunbarrel_next_counter_q16(state);

        render_x = ge_frontend_q16_midpoint(old_x, next_x);
        render_counter = ge_frontend_q16_midpoint(
            (int32_t)((uint64_t)state->gunbarrel_counter << 16u),
            next_counter_q16);
    }

    (void)ge_frontend_emit_render(
        state,
        callbacks,
        GE_SOURCE_FRONTEND_V6_RENDER_GUNBARREL_PIPELINE,
        mode - GE_SOURCE_FRONTEND_V6_GUNBARREL_MODE_INIT,
        render_x,
        render_counter,
        source_anchor == 0u ?
            (GE_SOURCE_FRONTEND_V6_RENDER_FLAG_HALF_STEP |
             GE_SOURCE_FRONTEND_V6_RENDER_FLAG_Q16_VALUES) : 0u);

    if (source_anchor == 0u) {
        int32_t next_transition = state->gunbarrel_transition_x_q16;
        int32_t next_word_q16 = ge_frontend_gunbarrel_next_word_q16(state);
        int32_t current_word_q16 =
            (int32_t)((uint64_t)(uint16_t)state->gunbarrel_word << 16u);

        /* The source's title/transition coordinates and word/fade counters are
         * separate animation domains.  Keep both explicit so the owner can
         * lower them without inferring a half-rate update from a model draw. */
        (void)ge_frontend_emit_continuous_state(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_CONTINUOUS_GUNBARREL_TRANSLATION,
            render_x,
            ge_frontend_q16_midpoint(
                state->gunbarrel_transition_x_q16, next_transition));
        (void)ge_frontend_emit_continuous_state(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_CONTINUOUS_GUNBARREL_COUNTER_WORD,
            render_counter,
            ge_frontend_q16_midpoint(current_word_q16, next_word_q16));
        ge_frontend_emit_gunbarrel_half_step_model(state, callbacks);
    }

    if (source_anchor == 0u) {
        return GE_STATUS_OK;
    }

    if (mode == 2u) {
        (void)ge_frontend_emit_model(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_MODEL_GUNBARREL,
            GE_SOURCE_FRONTEND_V6_MODEL_OP_DRAW,
            0u,
            0u,
            NULL);
        state->gunbarrel_title_x_q16 += GE_GUNBARREL_X_INC_Q16;
        if ((int16_t)(uint16_t)state->gunbarrel_word < 0) {
            state->gunbarrel_word = 200u;
            state->gunbarrel_transition_x_q16 =
                state->gunbarrel_title_x_q16 - (12 * 65536);
        } else {
            state->gunbarrel_word =
                (uint32_t)((uint16_t)(state->gunbarrel_word - 6u));
        }
        if (state->gunbarrel_title_x_q16 > GE_GUNBARREL_X_LIMIT_Q16) {
            state->gunbarrel_mode++;
            state->gunbarrel_title_x_q16 = GE_GUNBARREL_X_RESET_Q16;
        }
    } else if (mode == 3u) {
        (void)ge_frontend_emit_model(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_MODEL_GUNBARREL,
            GE_SOURCE_FRONTEND_V6_MODEL_OP_DRAW,
            1u,
            0u,
            NULL);
        /* The typed model flag carries gunbarrelTimer. Emit the rifle cue on
         * the even source anchor at the exact post-increment value 230. */
        if (ge_frontend_gunbarrel_timer(state) == GE_SOURCE_FRONTEND_V6_GUNBARREL_FIRE_SHOT) {
            (void)ge_frontend_emit_audio(
                state,
                callbacks,
                GE_SOURCE_FRONTEND_V6_AUDIO_OP_PLAY_SFX,
                GE_SOURCE_FRONTEND_V6_AUDIO_GUN_RIFLE7BIG_1);
        }
        state->gunbarrel_title_x_q16 -= GE_GUNBARREL_X_DEC_Q16;
        if (state->gunbarrel_title_x_q16 <= GE_GUNBARREL_X_EXIT_Q16) {
            state->gunbarrel_mode++;
            ge_frontend_set_gunbarrel_blood_state(state, 0u);
            state->gunbarrel_counter = 20u;
        }
    } else if (mode == 4u) {
        (void)ge_frontend_emit_model(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_MODEL_GUNBARREL,
            GE_SOURCE_FRONTEND_V6_MODEL_OP_DRAW,
            2u,
            0u,
            NULL);
        state->gunbarrel_counter--;
        if ((int32_t)state->gunbarrel_counter < 0) {
            state->gunbarrel_mode++;
            ge_frontend_set_gunbarrel_blood_state(state, 0u);
            state->gunbarrel_counter = 1u;
        }
    } else if (mode == 5u) {
        state->gunbarrel_counter--;
        if (state->gunbarrel_counter == 0u) {
            (void)ge_frontend_emit_model(
                state,
                callbacks,
                GE_SOURCE_FRONTEND_V6_MODEL_GUNBARREL,
                GE_SOURCE_FRONTEND_V6_MODEL_OP_BLOOD_TICK,
                3u,
                0u,
                &result);
            if ((result.flags & GE_SOURCE_FRONTEND_V6_MODEL_RESULT_BLOOD_COMPLETE) != 0u) {
                ge_frontend_set_gunbarrel_blood_state(state, 1u);
            }
            state->gunbarrel_counter = 2u;
        }
        (void)ge_frontend_emit_model(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_MODEL_GUNBARREL,
            GE_SOURCE_FRONTEND_V6_MODEL_OP_DRAW,
            3u,
            ge_frontend_gunbarrel_blood_state(state),
            NULL);
        if (ge_frontend_gunbarrel_blood_state(state) != 0u) {
            state->gunbarrel_mode++;
            state->gunbarrel_word = 0u;
            state->gunbarrel_transition_x_q16 = state->gunbarrel_title_x_q16;
            state->gunbarrel_counter = 0u;
        }
    } else if (mode == 6u) {
        (void)ge_frontend_emit_model(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_MODEL_GUNBARREL,
            GE_SOURCE_FRONTEND_V6_MODEL_OP_DRAW,
            4u,
            0u,
            NULL);
        state->gunbarrel_word =
            (uint32_t)((uint16_t)(state->gunbarrel_word + GE_GUNBARREL_INCVAL));
        state->gunbarrel_counter++;
        if (state->gunbarrel_counter >= GE_SOURCE_FRONTEND_V6_GUNBARREL_CASE4_COUNTER) {
            state->gunbarrel_counter = 0u;
            state->gunbarrel_mode++;
        }
    } else if (mode == 7u) {
        (void)ge_frontend_emit_model(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_MODEL_GUNBARREL,
            GE_SOURCE_FRONTEND_V6_MODEL_OP_DRAW,
            5u,
            (int32_t)state->gunbarrel_counter,
            NULL);
        state->gunbarrel_word =
            (uint32_t)((uint16_t)(state->gunbarrel_word + GE_GUNBARREL_INCVAL));
        state->gunbarrel_counter += 8u;
        if (state->gunbarrel_counter >= GE_SOURCE_FRONTEND_V6_GUNBARREL_CASE5_ALPHA) {
            state->gunbarrel_counter = 0u;
            state->gunbarrel_mode++;
        }
    } else if (mode == 8u) {
        (void)ge_frontend_emit_render(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_RENDER_CLEAR_BLACK,
            6u,
            0,
            0,
            0u);
        state->gunbarrel_counter++;
        if (state->gunbarrel_counter > GE_SOURCE_FRONTEND_V6_GUNBARREL_CASE6_COUNTER) {
            state->gunbarrel_counter = 0u;
            state->gunbarrel_mode++;
        }
    }
    return GE_STATUS_OK;
}

static GEStatusV1 ge_frontend_render_nintendo_continuous(
    GEFrontendStateV6 *state,
    const GEFrontendCallbacksV6 *callbacks,
    uint32_t source_anchor)
{
    uint32_t current_index;
    uint32_t next_index;
    int32_t current_rotation;
    int32_t next_rotation;
    uint32_t current_scale;
    uint32_t next_scale;
    int32_t current_ambient;
    int32_t next_ambient;

    if (source_anchor != 0u) {
        return GE_STATUS_OK;
    }

    current_index = ge_frontend_render_index_for_timer(state->source_timer);
    next_index = current_index == UINT32_MAX ? UINT32_MAX : current_index + 1u;
    /* front.c increments ninLogoRotRate before matrix construction.  The
     * source timer therefore directly indexes the current visible rotation;
     * the scale projection follows the shared Swift matrix-provider timer
     * convention as well. */
    current_rotation = ge_frontend_nintendo_rotation_for_render_index(
        state->source_timer);
    next_rotation = ge_frontend_nintendo_rotation_for_render_index(
        state->source_timer == UINT32_MAX ? UINT32_MAX : state->source_timer + 1u);
    current_scale = ge_frontend_nintendo_scale_for_render_index(current_index);
    next_scale = ge_frontend_nintendo_scale_for_render_index(next_index);
    current_ambient = ge_frontend_nintendo_ambient_for_timer(state->source_timer);
    next_ambient = ge_frontend_nintendo_ambient_for_timer(
        state->source_timer == UINT32_MAX ? UINT32_MAX : state->source_timer + 1u);

    /* constructor_menu01_nintendo advances rotation and scale after drawing,
     * while the light is derived from the current source timer.  Emit the
     * midpoint only on the odd native half-step; autonomous timer thresholds
     * still belong exclusively to the even source anchor. */
    (void)ge_frontend_emit_continuous_state(
        state,
        callbacks,
        GE_SOURCE_FRONTEND_V6_CONTINUOUS_NINTENDO_ROTATION_SCALE,
        ge_frontend_q16_midpoint(current_rotation, next_rotation),
        ge_frontend_q16_midpoint((int32_t)current_scale, (int32_t)next_scale));
    (void)ge_frontend_emit_continuous_state(
        state,
        callbacks,
        GE_SOURCE_FRONTEND_V6_CONTINUOUS_NINTENDO_AMBIENT,
        ge_frontend_q16_midpoint(current_ambient * 65536, next_ambient * 65536),
        0);
    return GE_STATUS_OK;
}

static GEStatusV1 ge_frontend_render_frame(
    GEFrontendStateV6 *state,
    const GEFrontendCallbacksV6 *callbacks,
    uint32_t source_anchor)
{
    uint32_t model;
    uint32_t i;
    static const uint32_t legal_text_ids[12] = {
        GE_SOURCE_FRONTEND_V6_TEXT_LEGAL_TWYCROSS,
        GE_SOURCE_FRONTEND_V6_TEXT_LEGAL_CERTIFY,
        GE_SOURCE_FRONTEND_V6_TEXT_LEGAL_NINRARE,
        GE_SOURCE_FRONTEND_V6_TEXT_LEGAL_DANJAQ,
        GE_SOURCE_FRONTEND_V6_TEXT_LEGAL_UAC,
        GE_SOURCE_FRONTEND_V6_TEXT_LEGAL_EON,
        GE_SOURCE_FRONTEND_V6_TEXT_LEGAL_MACB,
        GE_SOURCE_FRONTEND_V6_TEXT_LEGAL_PERSONS,
        GE_SOURCE_FRONTEND_V6_TEXT_LEGAL_PRESIDENT,
        GE_SOURCE_FRONTEND_V6_TEXT_LEGAL_VICE,
        GE_SOURCE_FRONTEND_V6_TEXT_LEGAL_NORMAN,
        GE_SOURCE_FRONTEND_V6_TEXT_LEGAL_EMI
    };
    static const int32_t legal_x[12] = {
        220, 34, 226, 226, 226, 226, 227, 219, 60, 60, 99, 80
    };
    static const int32_t legal_y[12] = {
        30, 83, 84, 97, 110, 122, 134, 211, 169, 201, 266, 280
    };

    (void)ge_frontend_emit_render(
        state,
        callbacks,
        GE_SOURCE_FRONTEND_V6_RENDER_FRAME_BEGIN,
        0u,
        0,
        0,
        0u);

    switch (state->screen) {
    case GE_SOURCE_FRONTEND_V6_SCREEN_LEGAL:
        (void)ge_frontend_emit_render(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_RENDER_CLEAR_BLACK,
            0u,
            0,
            0,
            0u);
        model = GE_SOURCE_FRONTEND_V6_MODEL_LEGALPAGE;
        (void)ge_frontend_emit_model(
            state,
            callbacks,
            model,
            GE_SOURCE_FRONTEND_V6_MODEL_OP_DRAW,
            0u,
            0u,
            NULL);
        (void)ge_frontend_emit_render(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_RENDER_SOURCE_TEXT,
            0u,
            12,
            0,
            GE_SOURCE_FRONTEND_V6_TEXT_FLAG_SOURCE_FONT);
        for (i = 0u; i < 12u; i++) {
            (void)ge_frontend_emit_text(
                state,
                callbacks,
                legal_text_ids[i],
                legal_x[i],
                legal_y[i],
                GE_SOURCE_FRONTEND_V6_TEXT_FLAG_SOURCE_FONT |
                    ((i == 0u) ? GE_SOURCE_FRONTEND_V6_TEXT_FLAG_CENTERED : 0u));
        }
        break;

    case GE_SOURCE_FRONTEND_V6_SCREEN_NINTENDO:
        (void)ge_frontend_emit_render(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_RENDER_CLEAR_BLACK,
            0u,
            0,
            0,
            0u);
        (void)ge_frontend_emit_model(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_MODEL_NINTENDOLOGO,
            GE_SOURCE_FRONTEND_V6_MODEL_OP_DRAW,
            0u,
            0u,
            NULL);
        (void)ge_frontend_render_nintendo_continuous(
            state, callbacks, source_anchor);
        break;

    case GE_SOURCE_FRONTEND_V6_SCREEN_RAREWARE:
        (void)ge_frontend_render_rareware(state, callbacks, source_anchor);
        break;

    case GE_SOURCE_FRONTEND_V6_SCREEN_GUNBARREL:
        (void)ge_frontend_render_gunbarrel(state, callbacks, source_anchor);
        break;

    case GE_SOURCE_FRONTEND_V6_SCREEN_GOLDENEYE:
        (void)ge_frontend_emit_render(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_RENDER_CLEAR_BLACK,
            0u,
            0,
            0,
            0u);
        (void)ge_frontend_emit_model(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_MODEL_GOLDENEYELOGO,
            GE_SOURCE_FRONTEND_V6_MODEL_OP_DRAW,
            0u,
            0u,
            NULL);
        break;

    case GE_SOURCE_FRONTEND_V6_SCREEN_FILE_SELECT:
    case GE_SOURCE_FRONTEND_V6_SCREEN_MODE_SELECT:
        (void)ge_frontend_emit_render(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_RENDER_SOURCE_MODEL,
            state->screen,
            4,
            0,
            0u);
        (void)ge_frontend_emit_model(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_MODEL_WALLETBOND,
            GE_SOURCE_FRONTEND_V6_MODEL_OP_DRAW,
            state->screen,
            0u,
            NULL);
        break;

    case GE_SOURCE_FRONTEND_V6_SCREEN_SWITCH:
        (void)ge_frontend_emit_render(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_RENDER_CLEAR_BLACK,
            0u,
            0,
            0,
            0u);
        break;

    case GE_SOURCE_FRONTEND_V6_SCREEN_CAST:
        (void)ge_frontend_emit_render(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_RENDER_CAST_PIPELINE,
            state->screen,
            state->source_timer,
            0,
            0u);
        break;

    case GE_SOURCE_FRONTEND_V6_SCREEN_NO_CONTROLLERS:
        (void)ge_frontend_emit_render(
            state,
            callbacks,
            GE_SOURCE_FRONTEND_V6_RENDER_UNSUPPORTED,
            state->screen,
            0,
            0,
            GE_SOURCE_FRONTEND_V6_STATE_FLAG_UNSUPPORTED);
        break;

    default:
        return GE_STATUS_INVALID_STATE;
    }
    return GE_STATUS_OK;
}

uint32_t ge_frontend_v6_source_threshold(uint32_t screen, uint32_t subphase)
{
    switch (screen) {
    case GE_SOURCE_FRONTEND_V6_SCREEN_LEGAL:
        return GE_SOURCE_FRONTEND_V6_LEGAL_TIMER_MAX;
    case GE_SOURCE_FRONTEND_V6_SCREEN_NINTENDO:
        return GE_SOURCE_FRONTEND_V6_NINTENDO_TIMER_MAX;
    case GE_SOURCE_FRONTEND_V6_SCREEN_RAREWARE:
        return subphase == GE_SOURCE_FRONTEND_V6_RAREWARE_MODE_READY ? 0u :
            GE_SOURCE_FRONTEND_V6_RAREWARE_EYE_COUNT_2;
    case GE_SOURCE_FRONTEND_V6_SCREEN_GOLDENEYE:
        return GE_SOURCE_FRONTEND_V6_GOLDENEYE_TIMER_1;
    case GE_SOURCE_FRONTEND_V6_SCREEN_FILE_SELECT:
        return GE_SOURCE_FRONTEND_V6_FILE_IDLE_TIMER_MAX;
    case GE_SOURCE_FRONTEND_V6_SCREEN_CAST:
        return 181u;
    case GE_SOURCE_FRONTEND_V6_SCREEN_SWITCH:
        return GE_SOURCE_FRONTEND_V6_SWITCH_TIMER_MAX;
    default:
        return 0u;
    }
}

GEStatusV1 ge_frontend_v6_init(
    GEFrontendStateV6 *state,
    const GEFrontendCallbacksV6 *callbacks)
{
    if (state == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    memset(state, 0, sizeof(*state));
    state->initialized = 1u;
    state->screen = GE_SOURCE_FRONTEND_V6_SCREEN_LEGAL;
    state->pending_reload = GE_SOURCE_FRONTEND_V6_SCREEN_INVALID;
    state->pending_direct = GE_SOURCE_FRONTEND_V6_SCREEN_INVALID;
    state->flags = GE_SOURCE_FRONTEND_V6_STATE_FLAG_FIRST_BOOT |
        GE_SOURCE_FRONTEND_V6_STATE_FLAG_FIRST_MAIN_MENU;
    ge_frontend_reset_screen_values(state);
    return ge_frontend_emit_enter(state, callbacks);
}

static GEStatusV1 ge_frontend_v6_step_native_internal(
    GEFrontendStateV6 *state,
    const GEFrontendInputV6 *input,
    const GEFrontendCallbacksV6 *callbacks,
    GEFrontendSnapshotV6 *out_snapshot,
    uint32_t source_ordered)
{
    GEStatusV1 status;
    uint32_t source_anchor;

    if (state == NULL || input == NULL || out_snapshot == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_frontend_v6_validate_input(input);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (state->initialized == 0u || input->native_tick != state->native_tick + 1u) {
        return GE_STATUS_INVALID_STATE;
    }

    source_anchor = (input->native_tick & 1u) == 0u ? 1u : 0u;
    if (((input->flags & GE_SOURCE_FRONTEND_V6_INPUT_FLAG_SOURCE_ANCHOR) != 0u) !=
        (source_anchor != 0u)) {
        return GE_STATUS_MALFORMED_STREAM;
    }

    state->native_tick = input->native_tick;
    state->source_frame += source_anchor;

    status = ge_frontend_menu_init(state, callbacks);
    if (status != GE_STATUS_OK) {
        return status;
    }
    status = ge_frontend_step_interface(
        state, input, callbacks, source_anchor, source_ordered);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (source_ordered != 0u && source_anchor != 0u &&
        state->screen != GE_SOURCE_FRONTEND_V6_SCREEN_SWITCH &&
        state->pending_reload != GE_SOURCE_FRONTEND_V6_SCREEN_INVALID) {
        /* front.c's interface function calls frontChangeMenu, and the menu
         * dispatcher enters MENU_SWITCH_SCREENS before the same frame is
         * rendered.  Preserve that source ordering at an even anchor. */
        status = ge_frontend_start_switch(state, callbacks);
        if (status != GE_STATUS_OK) {
            return status;
        }
    }
    if (source_ordered != 0u && source_anchor != 0u &&
        state->screen == GE_SOURCE_FRONTEND_V6_SCREEN_SWITCH &&
        (state->flags & GE_SOURCE_FRONTEND_V6_STATE_FLAG_TRANSITION_READY) != 0u &&
        state->pending_reload != GE_SOURCE_FRONTEND_V6_SCREEN_INVALID) {
        /* The source switch-screen interface commits its target on the fourth
         * anchor, before that anchor's frame is rendered. */
        {
            uint32_t target = state->pending_reload;
            state->flags &= ~GE_SOURCE_FRONTEND_V6_STATE_FLAG_TRANSITION_READY;
            status = ge_frontend_enter_screen(state, callbacks, target);
            if (status != GE_STATUS_OK) {
                return status;
            }
            /* Source constructors do not all reset g_MenuTimer.  Nintendo and
             * GoldenEye do; Rareware and gunbarrel inherit the switch value of
             * four.  Preserve those target-specific timer origins. */
            state->source_timer =
                (target == GE_SOURCE_FRONTEND_V6_SCREEN_RAREWARE ||
                 target == GE_SOURCE_FRONTEND_V6_SCREEN_GUNBARREL) ?
                GE_SOURCE_FRONTEND_V6_SWITCH_TIMER_MAX : 0u;
        }
    }
    status = ge_frontend_render_frame(state, callbacks, source_anchor);
    if (status != GE_STATUS_OK) {
        return status;
    }

    memset(out_snapshot, 0, sizeof(*out_snapshot));
    ge_frontend_header(&out_snapshot->header, (uint32_t)sizeof(*out_snapshot));
    out_snapshot->record_version = GE_SOURCE_FRONTEND_V6_RECORD_VERSION;
    out_snapshot->flags = state->flags |
        (((input->native_tick & 1u) == 0u) ?
             GE_SOURCE_FRONTEND_V6_SNAPSHOT_FLAG_SOURCE_ANCHOR : 0u);
    out_snapshot->screen = state->screen;
    out_snapshot->subphase = state->screen == GE_SOURCE_FRONTEND_V6_SCREEN_RAREWARE ?
        state->rareware_mode : state->gunbarrel_mode;
    out_snapshot->native_tick = state->native_tick;
    out_snapshot->reference_tick = state->native_tick / 2u;
    out_snapshot->source_frame = state->source_frame;
    out_snapshot->source_timer = state->source_timer;
    out_snapshot->source_threshold = ge_frontend_v6_source_threshold(
        state->screen, out_snapshot->subphase);
    out_snapshot->transition_timer = state->transition_timer;
    out_snapshot->selection = 0u;
    out_snapshot->unsupported_count = state->unsupported_count;
    out_snapshot->state_hash = ge_frontend_state_hash(state);
    out_snapshot->render_hash = ge_frontend_hash_mix(
        UINT64_C(1469598103934665603),
        ((uint64_t)state->screen << 32u) | out_snapshot->subphase);
    if ((state->native_tick & 1u) != 0u) {
        /* Odd frames are paired render extensions.  Keep source-anchor render
         * hashes identical to the original projection while making each
         * eligible half-step observable and hash-stable. */
        out_snapshot->render_hash = ge_frontend_hash_mix(
            out_snapshot->render_hash,
            ge_frontend_continuous_hash(state));
    }
    out_snapshot->audio_hash = ge_frontend_hash_mix(
        UINT64_C(1469598103934665603), state->event_sequence);
    return ge_frontend_v6_validate_snapshot(out_snapshot);
}

GEStatusV1 ge_frontend_v6_step_native(
    GEFrontendStateV6 *state,
    const GEFrontendInputV6 *input,
    const GEFrontendCallbacksV6 *callbacks,
    GEFrontendSnapshotV6 *out_snapshot)
{
    return ge_frontend_v6_step_native_internal(
        state, input, callbacks, out_snapshot, 0u);
}

GEStatusV1 ge_frontend_v6_step_native_source_ordered(
    GEFrontendStateV6 *state,
    const GEFrontendInputV6 *input,
    const GEFrontendCallbacksV6 *callbacks,
    GEFrontendSnapshotV6 *out_snapshot)
{
    return ge_frontend_v6_step_native_internal(
        state, input, callbacks, out_snapshot, 1u);
}
