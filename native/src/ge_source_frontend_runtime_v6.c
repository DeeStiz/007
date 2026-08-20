#include "ge_source_frontend_runtime_v6.h"

#include <stddef.h>
#include <string.h>

#include "../source_port/ge_source_frontend_v6.h"

/*
 * Keep the callback table private to this translation unit.  The public
 * runtime record is deliberately a copy-out boundary and cannot retain a
 * function pointer or an opaque host context.
 */
typedef struct GEFrontendRuntimeV6CallbackContext {
    GEFrontendRuntimeV6EventBatch *batch;
    uint32_t allow_paired_lifecycle_results;
    uint32_t model_result_model;
    uint32_t model_result_operation;
    uint32_t model_result_flags;
    uint32_t model_result_value0;
    uint32_t model_result_value1;
} GEFrontendRuntimeV6CallbackContext;

#if defined(__cplusplus)
static_assert(sizeof(GEFrontendRuntimeV6State) == 112u,
              "runtime state must retain the value-only envelope");
#else
_Static_assert(sizeof(GEFrontendRuntimeV6State) == 112u,
               "runtime state must retain the value-only envelope");
#endif

#define GE_RUNTIME_HASH_OFFSET UINT64_C(1469598103934665603)

static void ge_runtime_header(GEAbiHeaderV1 *header, uint32_t size)
{
    header->abi_version = GE_NATIVE_ABI_VERSION;
    header->struct_size = size;
}

static GEStatusV1 ge_runtime_validate_header(
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
    if (version != GE_SOURCE_FRONTEND_RUNTIME_V6_RECORD_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    return GE_STATUS_OK;
}

static uint64_t ge_runtime_hash_bytes(uint64_t hash, const void *bytes, size_t size)
{
    const uint8_t *cursor = (const uint8_t *)bytes;
    size_t index;

    for (index = 0u; index < size; index++) {
        hash ^= (uint64_t)cursor[index];
        hash *= UINT64_C(1099511628211);
    }
    return hash;
}

static void ge_runtime_batch_init(GEFrontendRuntimeV6EventBatch *batch)
{
    memset(batch, 0, sizeof(*batch));
    ge_runtime_header(&batch->header, (uint32_t)sizeof(*batch));
    batch->record_version = GE_SOURCE_FRONTEND_RUNTIME_V6_RECORD_VERSION;
    batch->screen_hash = GE_RUNTIME_HASH_OFFSET;
    batch->model_hash = GE_RUNTIME_HASH_OFFSET;
    batch->text_hash = GE_RUNTIME_HASH_OFFSET;
    batch->audio_hash = GE_RUNTIME_HASH_OFFSET;
    batch->save_hash = GE_RUNTIME_HASH_OFFSET;
    batch->render_hash = GE_RUNTIME_HASH_OFFSET;
    batch->diagnostic_hash = GE_RUNTIME_HASH_OFFSET;
}

static GEStatusV1 ge_runtime_append_screen(
    GEFrontendRuntimeV6CallbackContext *context,
    const GEFrontendScreenEventV6 *event)
{
    GEFrontendRuntimeV6ScreenEvent *copy;

    if (context == NULL || context->batch == NULL || event == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (context->batch->screen_count >= GE_SOURCE_FRONTEND_RUNTIME_V6_MAX_EVENTS) {
        context->batch->overflow_flags |= 1u << 0;
        return GE_STATUS_INTERNAL_ERROR;
    }
    copy = &context->batch->screens[context->batch->screen_count++];
    memset(copy, 0, sizeof(*copy));
    ge_runtime_header(&copy->header, (uint32_t)sizeof(*copy));
    copy->record_version = GE_SOURCE_FRONTEND_RUNTIME_V6_RECORD_VERSION;
    copy->event = event->event;
    copy->screen = event->screen;
    copy->target_screen = event->target_screen;
    copy->native_tick = event->native_tick;
    copy->source_frame = event->source_frame;
    copy->source_timer = event->source_timer;
    copy->transition_timer = event->transition_timer;
    copy->flags = event->flags;
    copy->sequence = event->sequence;
    context->batch->screen_hash = ge_runtime_hash_bytes(
        context->batch->screen_hash, copy, sizeof(*copy));
    return GE_STATUS_OK;
}

static GEStatusV1 ge_runtime_append_model(
    GEFrontendRuntimeV6CallbackContext *context,
    const GEFrontendModelEventV6 *event,
    const GEFrontendModelResultV6 *result)
{
    GEFrontendRuntimeV6ModelEvent *copy;

    if (context == NULL || context->batch == NULL || event == NULL || result == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (context->batch->model_count >= GE_SOURCE_FRONTEND_RUNTIME_V6_MAX_EVENTS) {
        context->batch->overflow_flags |= 1u << 1;
        return GE_STATUS_INTERNAL_ERROR;
    }
    copy = &context->batch->models[context->batch->model_count++];
    memset(copy, 0, sizeof(*copy));
    ge_runtime_header(&copy->header, (uint32_t)sizeof(*copy));
    copy->record_version = GE_SOURCE_FRONTEND_RUNTIME_V6_RECORD_VERSION;
    copy->screen = event->screen;
    copy->model = event->model;
    copy->operation = event->operation;
    copy->native_tick = event->native_tick;
    copy->reference_tick = event->reference_tick;
    copy->source_timer = event->source_timer;
    copy->subphase = event->subphase;
    copy->flags = event->flags;
    copy->sequence = event->sequence;
    copy->result_flags = result->flags;
    copy->result_value0 = result->value0;
    copy->result_value1 = result->value1;
    context->batch->model_hash = ge_runtime_hash_bytes(
        context->batch->model_hash, copy, sizeof(*copy));
    return GE_STATUS_OK;
}

static GEStatusV1 ge_runtime_append_text(
    GEFrontendRuntimeV6CallbackContext *context,
    const GEFrontendTextEventV6 *event)
{
    GEFrontendRuntimeV6TextEvent *copy;

    if (context == NULL || context->batch == NULL || event == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (context->batch->text_count >= GE_SOURCE_FRONTEND_RUNTIME_V6_MAX_EVENTS) {
        context->batch->overflow_flags |= 1u << 2;
        return GE_STATUS_INTERNAL_ERROR;
    }
    copy = &context->batch->texts[context->batch->text_count++];
    memset(copy, 0, sizeof(*copy));
    ge_runtime_header(&copy->header, (uint32_t)sizeof(*copy));
    copy->record_version = GE_SOURCE_FRONTEND_RUNTIME_V6_RECORD_VERSION;
    copy->screen = event->screen;
    copy->text_id = event->text_id;
    copy->x = event->x;
    copy->y = event->y;
    copy->native_tick = event->native_tick;
    copy->source_timer = event->source_timer;
    copy->flags = event->flags;
    copy->sequence = event->sequence;
    context->batch->text_hash = ge_runtime_hash_bytes(
        context->batch->text_hash, copy, sizeof(*copy));
    return GE_STATUS_OK;
}

static GEStatusV1 ge_runtime_append_audio(
    GEFrontendRuntimeV6CallbackContext *context,
    const GEFrontendAudioEventV6 *event)
{
    GEFrontendRuntimeV6AudioEvent *copy;

    if (context == NULL || context->batch == NULL || event == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (context->batch->audio_count >= GE_SOURCE_FRONTEND_RUNTIME_V6_MAX_EVENTS) {
        context->batch->overflow_flags |= 1u << 3;
        return GE_STATUS_INTERNAL_ERROR;
    }
    copy = &context->batch->audio[context->batch->audio_count++];
    memset(copy, 0, sizeof(*copy));
    ge_runtime_header(&copy->header, (uint32_t)sizeof(*copy));
    copy->record_version = GE_SOURCE_FRONTEND_RUNTIME_V6_RECORD_VERSION;
    copy->screen = event->screen;
    copy->operation = event->operation;
    copy->asset_id = event->asset_id;
    copy->native_tick = event->native_tick;
    copy->source_sample = event->source_sample;
    copy->source_timer = event->source_timer;
    copy->flags = event->flags;
    copy->sequence = event->sequence;
    context->batch->audio_hash = ge_runtime_hash_bytes(
        context->batch->audio_hash, copy, sizeof(*copy));
    return GE_STATUS_OK;
}

static GEStatusV1 ge_runtime_append_save(
    GEFrontendRuntimeV6CallbackContext *context,
    const GEFrontendSaveEventV6 *event)
{
    GEFrontendRuntimeV6SaveEvent *copy;

    if (context == NULL || context->batch == NULL || event == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (context->batch->save_count >= GE_SOURCE_FRONTEND_RUNTIME_V6_MAX_EVENTS) {
        context->batch->overflow_flags |= 1u << 4;
        return GE_STATUS_INTERNAL_ERROR;
    }
    copy = &context->batch->saves[context->batch->save_count++];
    memset(copy, 0, sizeof(*copy));
    ge_runtime_header(&copy->header, (uint32_t)sizeof(*copy));
    copy->record_version = GE_SOURCE_FRONTEND_RUNTIME_V6_RECORD_VERSION;
    copy->screen = event->screen;
    copy->operation = event->operation;
    copy->folder = event->folder;
    copy->native_tick = event->native_tick;
    copy->sequence = event->sequence;
    context->batch->save_hash = ge_runtime_hash_bytes(
        context->batch->save_hash, copy, sizeof(*copy));
    return GE_STATUS_OK;
}

static GEStatusV1 ge_runtime_append_render(
    GEFrontendRuntimeV6CallbackContext *context,
    const GEFrontendRenderEventV6 *event)
{
    GEFrontendRuntimeV6RenderEvent *copy;

    if (context == NULL || context->batch == NULL || event == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (context->batch->render_count >= GE_SOURCE_FRONTEND_RUNTIME_V6_MAX_EVENTS) {
        context->batch->overflow_flags |= 1u << 5;
        return GE_STATUS_INTERNAL_ERROR;
    }
    copy = &context->batch->renders[context->batch->render_count++];
    memset(copy, 0, sizeof(*copy));
    ge_runtime_header(&copy->header, (uint32_t)sizeof(*copy));
    copy->record_version = GE_SOURCE_FRONTEND_RUNTIME_V6_RECORD_VERSION;
    copy->screen = event->screen;
    copy->operation = event->operation;
    copy->subphase = event->subphase;
    copy->native_tick = event->native_tick;
    copy->reference_tick = event->reference_tick;
    copy->source_timer = event->source_timer;
    copy->value0 = event->value0;
    copy->value1 = event->value1;
    copy->flags = event->flags;
    copy->sequence = event->sequence;
    context->batch->render_hash = ge_runtime_hash_bytes(
        context->batch->render_hash, copy, sizeof(*copy));
    return GE_STATUS_OK;
}

static GEStatusV1 ge_runtime_append_diagnostic(
    GEFrontendRuntimeV6CallbackContext *context,
    uint32_t screen,
    uint32_t code,
    uint32_t severity,
    uint32_t source_timer,
    uint64_t native_tick,
    uint64_t sequence,
    uint32_t detail0,
    uint32_t detail1)
{
    GEFrontendRuntimeV6DiagnosticEvent *copy;

    if (context == NULL || context->batch == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (context->batch->diagnostic_count >= GE_SOURCE_FRONTEND_RUNTIME_V6_MAX_EVENTS) {
        context->batch->overflow_flags |= 1u << 6;
        return GE_STATUS_INTERNAL_ERROR;
    }
    copy = &context->batch->diagnostics[context->batch->diagnostic_count++];
    memset(copy, 0, sizeof(*copy));
    ge_runtime_header(&copy->header, (uint32_t)sizeof(*copy));
    copy->record_version = GE_SOURCE_FRONTEND_RUNTIME_V6_RECORD_VERSION;
    copy->screen = screen;
    copy->code = code;
    copy->severity = severity;
    copy->source_timer = source_timer;
    copy->native_tick = native_tick;
    copy->sequence = sequence;
    copy->detail0 = detail0;
    copy->detail1 = detail1;
    context->batch->diagnostic_hash = ge_runtime_hash_bytes(
        context->batch->diagnostic_hash, copy, sizeof(*copy));
    return GE_STATUS_OK;
}

static GEStatusV1 ge_runtime_model_callback(
    const GEFrontendModelEventV6 *event,
    GEFrontendModelResultV6 *result,
    void *opaque)
{
    GEFrontendRuntimeV6CallbackContext *context =
        (GEFrontendRuntimeV6CallbackContext *)opaque;
    uint32_t has_result;
    uint32_t key_matches;

    if (event == NULL || result == NULL || context == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    /* A complete scene adapter may supply one copied result for this call.
     * Production sends zeroes, so the default remains fail-closed. */
    memset(result, 0, sizeof(*result));
    ge_runtime_header(&result->header, (uint32_t)sizeof(*result));
    result->record_version = GE_SOURCE_FRONTEND_V6_RECORD_VERSION;
    if (context->allow_paired_lifecycle_results &&
        (event->operation == GE_SOURCE_FRONTEND_V6_MODEL_OP_LOAD ||
         event->operation == GE_SOURCE_FRONTEND_V6_MODEL_OP_RELEASE)) {
        result->flags = GE_SOURCE_FRONTEND_V6_MODEL_RESULT_EXECUTED;
        (void)ge_runtime_append_model(context, event, result);
        return GE_STATUS_OK;
    }
    if (context->allow_paired_lifecycle_results &&
        event->model == GE_SOURCE_FRONTEND_V6_MODEL_GUNBARREL &&
        event->operation == GE_SOURCE_FRONTEND_V6_MODEL_OP_DRAW &&
        context->model_result_operation == GE_SOURCE_FRONTEND_V6_MODEL_OP_BLOOD_TICK &&
        (context->model_result_flags & GE_SOURCE_FRONTEND_V6_MODEL_RESULT_BLOOD_COMPLETE) != 0u) {
        result->flags = GE_SOURCE_FRONTEND_V6_MODEL_RESULT_EXECUTED;
        (void)ge_runtime_append_model(context, event, result);
        return GE_STATUS_OK;
    }
    has_result = context->model_result_model != 0u ||
        context->model_result_operation != 0u ||
        context->model_result_flags != 0u ||
        context->model_result_value0 != 0u ||
        context->model_result_value1 != 0u;
    key_matches = context->model_result_model == event->model &&
        context->model_result_operation == event->operation &&
        context->model_result_model != GE_SOURCE_FRONTEND_V6_MODEL_NONE &&
        context->model_result_operation != 0u;
    if (has_result == 0u) {
        /* No acknowledgement yet: retain a pending request without poisoning
         * the source state.  The owner may consume it and answer on a later
         * input record. */
        (void)ge_runtime_append_model(context, event, result);
        return GE_STATUS_OK;
    }
    if (key_matches != 0u) {
        result->flags = context->model_result_flags;
        result->value0 = context->model_result_value0;
        result->value1 = context->model_result_value1;
        if ((result->flags & GE_SOURCE_FRONTEND_V6_MODEL_RESULT_EXECUTED) != 0u) {
            (void)ge_runtime_append_model(context, event, result);
            return GE_STATUS_OK;
        }
    }
    (void)ge_runtime_append_model(context, event, result);
    if (key_matches == 0u) {
        /* A supplied result for another request is an explicit producer
         * mismatch, not an absent result. */
        (void)ge_runtime_append_diagnostic(
            context,
            event->screen,
            GE_SOURCE_FRONTEND_RUNTIME_V6_DIAG_INVALID_STATE,
            GE_SOURCE_FRONTEND_RUNTIME_V6_DIAG_SEVERITY_ERROR,
            event->source_timer,
            event->native_tick,
            event->sequence,
            event->model,
            event->operation);
        return GE_STATUS_OK;
    }
    /* A matching zero/negative result is an explicit unsupported response. */
    return GE_STATUS_UNSUPPORTED_COMMAND;
}

static GEStatusV1 ge_runtime_screen_callback(
    const GEFrontendScreenEventV6 *event,
    void *opaque)
{
    return ge_runtime_append_screen(
        (GEFrontendRuntimeV6CallbackContext *)opaque, event);
}

static GEStatusV1 ge_runtime_text_callback(
    const GEFrontendTextEventV6 *event,
    void *opaque)
{
    return ge_runtime_append_text(
        (GEFrontendRuntimeV6CallbackContext *)opaque, event);
}

static GEStatusV1 ge_runtime_audio_callback(
    const GEFrontendAudioEventV6 *event,
    void *opaque)
{
    return ge_runtime_append_audio(
        (GEFrontendRuntimeV6CallbackContext *)opaque, event);
}

static GEStatusV1 ge_runtime_save_callback(
    const GEFrontendSaveEventV6 *event,
    void *opaque)
{
    return ge_runtime_append_save(
        (GEFrontendRuntimeV6CallbackContext *)opaque, event);
}

static GEStatusV1 ge_runtime_render_callback(
    const GEFrontendRenderEventV6 *event,
    void *opaque)
{
    GEFrontendRuntimeV6CallbackContext *context =
        (GEFrontendRuntimeV6CallbackContext *)opaque;
    GEStatusV1 status;

    status = ge_runtime_append_render(context, event);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (event->operation == GE_SOURCE_FRONTEND_V6_RENDER_UNSUPPORTED) {
        /* This is an explicit source gap (Cast/no-controller route).  The
         * normal render operations are copied as requests and must remain
         * available to the host renderer before any handling result exists. */
        (void)ge_runtime_append_diagnostic(
            context,
            event->screen,
            GE_SOURCE_FRONTEND_RUNTIME_V6_DIAG_UNSUPPORTED_RENDER,
            GE_SOURCE_FRONTEND_RUNTIME_V6_DIAG_SEVERITY_WARNING,
            event->source_timer,
            event->native_tick,
            event->sequence,
            event->operation,
            event->subphase);
        return GE_STATUS_UNSUPPORTED_COMMAND;
    }
    /* Copy-only request: no execution result is fabricated at this seam. */
    return GE_STATUS_OK;
}

static GEStatusV1 ge_runtime_diagnostic_callback(
    const GEFrontendDiagnosticV6 *event,
    void *opaque)
{
    GEFrontendRuntimeV6CallbackContext *context =
        (GEFrontendRuntimeV6CallbackContext *)opaque;

    if (event == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    return ge_runtime_append_diagnostic(
        context,
        event->screen,
        event->code,
        event->severity,
        event->source_timer,
        event->native_tick,
        event->sequence,
        event->detail0,
        event->detail1);
}

static GEFrontendCallbacksV6 ge_runtime_callbacks(
    GEFrontendRuntimeV6CallbackContext *context)
{
    GEFrontendCallbacksV6 callbacks;

    memset(&callbacks, 0, sizeof(callbacks));
    callbacks.model = ge_runtime_model_callback;
    callbacks.screen = ge_runtime_screen_callback;
    callbacks.text = ge_runtime_text_callback;
    callbacks.audio = ge_runtime_audio_callback;
    callbacks.save = ge_runtime_save_callback;
    callbacks.render = ge_runtime_render_callback;
    callbacks.diagnostic = ge_runtime_diagnostic_callback;
    callbacks.context = context;
    return callbacks;
}

static void ge_runtime_copy_state_from_source(
    GEFrontendRuntimeV6State *runtime,
    const GEFrontendStateV6 *source)
{
    memset(runtime, 0, sizeof(*runtime));
    ge_runtime_header(&runtime->header, (uint32_t)sizeof(*runtime));
    runtime->record_version = GE_SOURCE_FRONTEND_RUNTIME_V6_RECORD_VERSION;
    runtime->initialized = source->initialized;
    runtime->screen = source->screen;
    runtime->pending_reload = source->pending_reload;
    runtime->pending_direct = source->pending_direct;
    runtime->transition_timer = source->transition_timer;
    runtime->source_timer = source->source_timer;
    runtime->source_frame = source->source_frame;
    runtime->flags = source->flags;
    runtime->controller_count = source->controller_count;
    runtime->rareware_mode = source->rareware_mode;
    runtime->rareware_counter = source->rareware_counter;
    runtime->gunbarrel_mode = source->gunbarrel_mode;
    runtime->gunbarrel_counter = source->gunbarrel_counter;
    runtime->gunbarrel_blood_state = source->gunbarrel_blood_state;
    runtime->gunbarrel_word = source->gunbarrel_word;
    runtime->gunbarrel_title_x_q16 = source->gunbarrel_title_x_q16;
    runtime->gunbarrel_transition_x_q16 = source->gunbarrel_transition_x_q16;
    runtime->native_tick = source->native_tick;
    runtime->event_sequence = source->event_sequence;
    runtime->unsupported_count = source->unsupported_count;
}

static void ge_runtime_copy_state_to_source(
    GEFrontendStateV6 *source,
    const GEFrontendRuntimeV6State *runtime)
{
    memset(source, 0, sizeof(*source));
    source->initialized = runtime->initialized;
    source->screen = runtime->screen;
    source->pending_reload = runtime->pending_reload;
    source->pending_direct = runtime->pending_direct;
    source->transition_timer = runtime->transition_timer;
    source->source_timer = runtime->source_timer;
    source->source_frame = runtime->source_frame;
    source->flags = runtime->flags;
    source->controller_count = runtime->controller_count;
    source->rareware_mode = runtime->rareware_mode;
    source->rareware_counter = runtime->rareware_counter;
    source->gunbarrel_mode = runtime->gunbarrel_mode;
    source->gunbarrel_counter = runtime->gunbarrel_counter;
    source->gunbarrel_blood_state = runtime->gunbarrel_blood_state;
    source->gunbarrel_word = runtime->gunbarrel_word;
    source->gunbarrel_title_x_q16 = runtime->gunbarrel_title_x_q16;
    source->gunbarrel_transition_x_q16 = runtime->gunbarrel_transition_x_q16;
    source->native_tick = runtime->native_tick;
    source->event_sequence = runtime->event_sequence;
    source->unsupported_count = runtime->unsupported_count;
}

static void ge_runtime_init_snapshot(
    GEFrontendRuntimeV6Snapshot *snapshot,
    const GEFrontendStateV6 *state,
    const GEFrontendSnapshotV6 *source_snapshot,
    const GEFrontendRuntimeV6EventBatch *batch)
{
    memset(snapshot, 0, sizeof(*snapshot));
    ge_runtime_header(&snapshot->header, (uint32_t)sizeof(*snapshot));
    snapshot->record_version = GE_SOURCE_FRONTEND_RUNTIME_V6_RECORD_VERSION;
    if (source_snapshot != NULL) {
        snapshot->flags = source_snapshot->flags;
        snapshot->screen = source_snapshot->screen;
        snapshot->subphase = source_snapshot->subphase;
        snapshot->native_tick = source_snapshot->native_tick;
        snapshot->reference_tick = source_snapshot->reference_tick;
        snapshot->source_frame = source_snapshot->source_frame;
        snapshot->source_timer = source_snapshot->source_timer;
        snapshot->source_threshold = source_snapshot->source_threshold;
        snapshot->transition_timer = source_snapshot->transition_timer;
        snapshot->selection = source_snapshot->selection;
        snapshot->unsupported_count = source_snapshot->unsupported_count;
        snapshot->state_hash = source_snapshot->state_hash;
        snapshot->render_hash = source_snapshot->render_hash;
        snapshot->audio_hash = source_snapshot->audio_hash;
    } else {
        snapshot->flags = state->flags;
        snapshot->screen = state->screen;
        snapshot->subphase = state->screen == GE_SOURCE_FRONTEND_V6_SCREEN_RAREWARE ?
            state->rareware_mode : state->gunbarrel_mode;
        snapshot->native_tick = state->native_tick;
        snapshot->reference_tick = state->native_tick / 2u;
        snapshot->source_frame = state->source_frame;
        snapshot->source_timer = state->source_timer;
        snapshot->source_threshold = ge_frontend_v6_source_threshold(
            state->screen, snapshot->subphase);
        snapshot->transition_timer = state->transition_timer;
        snapshot->unsupported_count = state->unsupported_count;
    }
    if (batch != NULL) {
        snapshot->screen_hash = batch->screen_hash;
        snapshot->model_hash = batch->model_hash;
        snapshot->text_hash = batch->text_hash;
        snapshot->audio_event_hash = batch->audio_hash;
        snapshot->save_hash = batch->save_hash;
        snapshot->render_event_hash = batch->render_hash;
        snapshot->diagnostic_hash = batch->diagnostic_hash;
        snapshot->screen_count = batch->screen_count;
        snapshot->model_count = batch->model_count;
        snapshot->text_count = batch->text_count;
        snapshot->audio_count = batch->audio_count;
        snapshot->save_count = batch->save_count;
        snapshot->render_count = batch->render_count;
        snapshot->diagnostic_count = batch->diagnostic_count;
        if (batch->diagnostic_count != 0u) {
            snapshot->flags |= GE_SOURCE_FRONTEND_V6_STATE_FLAG_UNSUPPORTED;
        }
    }
}

static void ge_runtime_init_frame(GEFrontendRuntimeV6Frame *frame)
{
    memset(frame, 0, sizeof(*frame));
    ge_runtime_header(&frame->header, (uint32_t)sizeof(*frame));
    frame->record_version = GE_SOURCE_FRONTEND_RUNTIME_V6_RECORD_VERSION;
    ge_runtime_batch_init(&frame->events);
}

GEStatusV1 ge_frontend_runtime_v6_validate_input(
    const GEFrontendRuntimeV6Input *input)
{
    GEStatusV1 status;

    if (input == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_runtime_validate_header(
        &input->header, (uint32_t)sizeof(*input), input->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if ((input->flags & ~GE_SOURCE_FRONTEND_RUNTIME_V6_INPUT_FLAG_MASK) != 0u ||
        (input->buttons_pressed & ~GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_MASK) != 0u ||
        input->controller_count > 4u || input->clock_timer > 4u ||
        input->native_tick == 0u || input->reserved0 != 0u ||
        input->reserved1 != 0u ||
        input->model_result_operation > GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_BLOOD_TICK ||
        (input->model_result_flags & ~UINT32_C(0x03)) != 0u ||
        (input->model_result_operation == 0u &&
         (input->model_result_model != 0u || input->model_result_flags != 0u ||
          input->model_result_value0 != 0u || input->model_result_value1 != 0u))) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    if (((input->native_tick & 1u) == 0u) !=
        ((input->flags & GE_SOURCE_FRONTEND_RUNTIME_V6_INPUT_FLAG_SOURCE_ANCHOR) != 0u)) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_frontend_runtime_v6_validate_state(
    const GEFrontendRuntimeV6State *state)
{
    GEStatusV1 status;

    if (state == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_runtime_validate_header(
        &state->header, (uint32_t)sizeof(*state), state->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (state->initialized == 0u || state->screen > GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_CAST ||
        (state->flags & ~UINT32_C(0x3f)) != 0u || state->controller_count > 4u ||
        (state->pending_reload > GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_CAST &&
            state->pending_reload != UINT32_MAX) ||
        (state->pending_direct > GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_CAST &&
            state->pending_direct != UINT32_MAX) || state->reserved0 != 0u ||
        state->reserved1 != 0u || state->reserved2 != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_frontend_runtime_v6_validate_snapshot(
    const GEFrontendRuntimeV6Snapshot *snapshot)
{
    GEStatusV1 status;

    if (snapshot == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_runtime_validate_header(
        &snapshot->header, (uint32_t)sizeof(*snapshot), snapshot->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (snapshot->screen > GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_CAST ||
        (snapshot->flags & ~UINT32_C(0x13f)) != 0u ||
        snapshot->reserved0 != 0u || snapshot->reserved1 != 0u ||
        snapshot->screen_count > GE_SOURCE_FRONTEND_RUNTIME_V6_MAX_EVENTS ||
        snapshot->model_count > GE_SOURCE_FRONTEND_RUNTIME_V6_MAX_EVENTS ||
        snapshot->text_count > GE_SOURCE_FRONTEND_RUNTIME_V6_MAX_EVENTS ||
        snapshot->audio_count > GE_SOURCE_FRONTEND_RUNTIME_V6_MAX_EVENTS ||
        snapshot->save_count > GE_SOURCE_FRONTEND_RUNTIME_V6_MAX_EVENTS ||
        snapshot->render_count > GE_SOURCE_FRONTEND_RUNTIME_V6_MAX_EVENTS ||
        snapshot->diagnostic_count > GE_SOURCE_FRONTEND_RUNTIME_V6_MAX_EVENTS) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_frontend_runtime_v6_validate_frame(
    const GEFrontendRuntimeV6Frame *frame)
{
    GEStatusV1 status;

    if (frame == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_runtime_validate_header(
        &frame->header, (uint32_t)sizeof(*frame), frame->record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    status = ge_runtime_validate_header(
        &frame->events.header,
        (uint32_t)sizeof(frame->events),
        frame->events.record_version);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (frame->reserved0 != 0u || frame->events.reserved0 != 0u ||
        frame->events.overflow_flags != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    status = ge_frontend_runtime_v6_validate_snapshot(&frame->snapshot);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (frame->snapshot.screen_count != frame->events.screen_count ||
        frame->snapshot.model_count != frame->events.model_count ||
        frame->snapshot.text_count != frame->events.text_count ||
        frame->snapshot.audio_count != frame->events.audio_count ||
        frame->snapshot.save_count != frame->events.save_count ||
        frame->snapshot.render_count != frame->events.render_count ||
        frame->snapshot.diagnostic_count != frame->events.diagnostic_count ||
        frame->snapshot.screen_hash != frame->events.screen_hash ||
        frame->snapshot.model_hash != frame->events.model_hash ||
        frame->snapshot.text_hash != frame->events.text_hash ||
        frame->snapshot.audio_event_hash != frame->events.audio_hash ||
        frame->snapshot.save_hash != frame->events.save_hash ||
        frame->snapshot.render_event_hash != frame->events.render_hash ||
        frame->snapshot.diagnostic_hash != frame->events.diagnostic_hash) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_frontend_runtime_v6_init(
    GEFrontendRuntimeV6State *state,
    GEFrontendRuntimeV6Frame *out_frame)
{
    GEFrontendStateV6 source_state;
    GEFrontendRuntimeV6CallbackContext context;
    GEFrontendCallbacksV6 callbacks;
    GEStatusV1 status;

    if (state == NULL || out_frame == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    memset(&context, 0, sizeof(context));
    ge_runtime_init_frame(out_frame);
    context.batch = &out_frame->events;
    callbacks = ge_runtime_callbacks(&context);
    status = ge_frontend_v6_init(&source_state, &callbacks);
    if (status != GE_STATUS_OK) {
        return status;
    }
    ge_runtime_copy_state_from_source(state, &source_state);
    ge_runtime_init_snapshot(
        &out_frame->snapshot, &source_state, NULL, &out_frame->events);
    return ge_frontend_runtime_v6_validate_frame(out_frame);
}

GEStatusV1 ge_frontend_runtime_v6_step(
    GEFrontendRuntimeV6State *state,
    const GEFrontendRuntimeV6Input *input,
    GEFrontendRuntimeV6Frame *out_frame)
{
    GEFrontendStateV6 source_state;
    GEFrontendInputV6 source_input;
    GEFrontendSnapshotV6 source_snapshot;
    GEFrontendRuntimeV6CallbackContext context;
    GEFrontendCallbacksV6 callbacks;
    GEStatusV1 status;

    if (state == NULL || input == NULL || out_frame == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    status = ge_frontend_runtime_v6_validate_state(state);
    if (status != GE_STATUS_OK) {
        return status;
    }
    status = ge_frontend_runtime_v6_validate_input(input);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (input->native_tick != state->native_tick + 1u) {
        return GE_STATUS_INVALID_STATE;
    }

    ge_runtime_copy_state_to_source(&source_state, state);
    memset(&source_input, 0, sizeof(source_input));
    ge_runtime_header(&source_input.header, (uint32_t)sizeof(source_input));
    source_input.record_version = GE_SOURCE_FRONTEND_V6_RECORD_VERSION;
    source_input.flags = 0u;
    if ((input->flags & GE_SOURCE_FRONTEND_RUNTIME_V6_INPUT_FLAG_SOURCE_ANCHOR) != 0u) {
        source_input.flags |= GE_SOURCE_FRONTEND_V6_INPUT_FLAG_SOURCE_ANCHOR;
    }
    if ((input->flags & GE_SOURCE_FRONTEND_RUNTIME_V6_INPUT_FLAG_FOCUSED) != 0u) {
        source_input.flags |= GE_SOURCE_FRONTEND_V6_INPUT_FLAG_FOCUSED;
    }
    if ((input->flags & GE_SOURCE_FRONTEND_RUNTIME_V6_INPUT_FLAG_CONTROLLER_CONNECTED) != 0u) {
        source_input.flags |= GE_SOURCE_FRONTEND_V6_INPUT_FLAG_CONTROLLER_CONNECTED;
    }
    if ((input->flags & GE_SOURCE_FRONTEND_RUNTIME_V6_INPUT_FLAG_SYNTHETIC) != 0u) {
        source_input.flags |= GE_SOURCE_FRONTEND_V6_INPUT_FLAG_SYNTHETIC;
    }
    source_input.buttons_pressed = input->buttons_pressed;
    source_input.controller_count = input->controller_count;
    source_input.native_tick = input->native_tick;
    source_input.sequence = input->sequence;

    memset(&context, 0, sizeof(context));
    context.model_result_model = input->model_result_model;
    context.model_result_operation = input->model_result_operation;
    context.model_result_flags = input->model_result_flags;
    context.model_result_value0 = input->model_result_value0;
    context.model_result_value1 = input->model_result_value1;
    context.allow_paired_lifecycle_results =
        (input->flags & GE_SOURCE_FRONTEND_RUNTIME_V6_INPUT_FLAG_PAIRED_ORACLE) != 0u;
    ge_runtime_init_frame(out_frame);
    context.batch = &out_frame->events;
    callbacks = ge_runtime_callbacks(&context);
    status = ge_frontend_v6_step_native_source_ordered(
        &source_state, &source_input, &callbacks, &source_snapshot);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if (context.batch->overflow_flags != 0u) {
        return GE_STATUS_INTERNAL_ERROR;
    }
    ge_runtime_copy_state_from_source(state, &source_state);
    ge_runtime_init_snapshot(
        &out_frame->snapshot, &source_state, &source_snapshot, &out_frame->events);
    return ge_frontend_runtime_v6_validate_frame(out_frame);
}
