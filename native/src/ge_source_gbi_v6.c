#include "ge_source_gbi_v6.h"

#include <stddef.h>
#include <stdlib.h>
#include <string.h>

typedef struct GEGBIFrameV6 {
    uint32_t handle;
    uint32_t next_command;
    uint32_t end_command;
    uint32_t returns_to_parent;
} GEGBIFrameV6;

typedef struct GEGBIEngineV6 {
    const GEGBISourcePacketV6 *packet;
    const GEGBISourceVertexResourcePageV6 *vertex_pages;
    uint32_t vertex_page_count;
    GEGBIVertexLoadProvenanceV6 *vertex_load_provenance;
    uint32_t vertex_load_provenance_capacity;
    uint32_t vertex_load_provenance_count;
    GEGBIResultV6 result;
    GEGBIFrameV6 frames[GE_SOURCE_GBI_V6_MAX_LIST_STACK];
    uint32_t frame_depth;
    uint32_t active_handles[GE_SOURCE_GBI_V6_MAX_LIST_STACK];
    uint8_t root_ended;
    uint8_t pending_texrect_halves;
    uint8_t vertex_valid[GE_SOURCE_GBI_V6_MAX_VERTEX_CACHE];
    GEVertexV1 vertex_cache[GE_SOURCE_GBI_V6_MAX_VERTEX_CACHE];
    uint32_t vertex_sources[GE_SOURCE_GBI_V6_MAX_VERTEX_CACHE];
    uint32_t modelview_handles[GE_SOURCE_GBI_V6_MAX_MATRIX_STACK];
    uint32_t projection_handles[GE_SOURCE_GBI_V6_MAX_MATRIX_STACK];
    uint32_t modelview_depth;
    uint32_t projection_depth;
    uint32_t modelview_provenance_flags;
    uint64_t event_hash;
    uint8_t saw_unsupported;
} GEGBIEngineV6;

/* The public result is returned by value; keep the copy-out buffer off the
   owner thread's stack while retaining a reentrant-per-thread contract. */
static _Thread_local GEGBIResultV6 ge_gbi_return_buffer;

enum {
    GEGBI_V6_TRI_INDEX_MAX = GE_SOURCE_GBI_V6_MAX_VERTEX_CACHE - 1u,
};

#define GEGBI_V6_DEFAULT_HASH UINT64_C(14695981039346656037)

typedef enum GEGBICommandKindV6 {
    GEGBI_KIND_UNKNOWN = 0,
    GEGBI_KIND_NOOP,
    GEGBI_KIND_MTX,
    GEGBI_KIND_MOVEMEM,
    GEGBI_KIND_VTX,
    GEGBI_KIND_DL,
    GEGBI_KIND_TRI1,
    GEGBI_KIND_TRI4,
    GEGBI_KIND_TEXTURE,
    GEGBI_KIND_SETOTHERMODE_L,
    GEGBI_KIND_SETOTHERMODE_H,
    GEGBI_KIND_MOVEWORD,
    GEGBI_KIND_POPMTX,
    GEGBI_KIND_SETTEX,
    GEGBI_KIND_CLEARGEOMETRYMODE,
    GEGBI_KIND_SETGEOMETRYMODE,
    GEGBI_KIND_GEOMETRYMODE,
    GEGBI_KIND_ENDDL,
    GEGBI_KIND_SETTIMG,
    GEGBI_KIND_SETCOMBINE,
    GEGBI_KIND_SETENVCOLOR,
    GEGBI_KIND_SETPRIMCOLOR,
    GEGBI_KIND_SETBLENDCOLOR,
    GEGBI_KIND_SETFOGCOLOR,
    GEGBI_KIND_SETFILLCOLOR,
    GEGBI_KIND_FILLRECT,
    GEGBI_KIND_SETTILE,
    GEGBI_KIND_LOADTILE,
    GEGBI_KIND_LOADBLOCK,
    GEGBI_KIND_SETTILESIZE,
    GEGBI_KIND_LOADTLUT,
    GEGBI_KIND_RDPSETOTHERMODE,
    GEGBI_KIND_SETSCISSOR,
    GEGBI_KIND_RDPHALF_1,
    GEGBI_KIND_RDPHALF_2,
    GEGBI_KIND_RDPHALF_CONT,
    GEGBI_KIND_RDPFULLSYNC,
    GEGBI_KIND_RDPTILESYNC,
    GEGBI_KIND_RDPPIPESYNC,
    GEGBI_KIND_RDPLOADSYNC,
    GEGBI_KIND_TEXRECTFLIP,
    GEGBI_KIND_TEXRECT,
    GEGBI_KIND_SETCIMG,
    GEGBI_KIND_SETZIMG,
} GEGBICommandKindV6;

static uint64_t ge_gbi_hash_byte(uint64_t hash, uint8_t value)
{
    return (hash ^ (uint64_t)value) * UINT64_C(1099511628211);
}

static uint64_t ge_gbi_hash_u32(uint64_t hash, uint32_t value)
{
    hash = ge_gbi_hash_byte(hash, (uint8_t)(value & 0xffu));
    hash = ge_gbi_hash_byte(hash, (uint8_t)((value >> 8) & 0xffu));
    hash = ge_gbi_hash_byte(hash, (uint8_t)((value >> 16) & 0xffu));
    return ge_gbi_hash_byte(hash, (uint8_t)(value >> 24));
}

static uint64_t ge_gbi_hash_bytes(uint64_t hash, const void *bytes, size_t count)
{
    const uint8_t *source = (const uint8_t *)bytes;
    for (size_t index = 0; index < count; index++) {
        hash = ge_gbi_hash_byte(hash, source[index]);
    }
    return hash;
}

static uint64_t ge_gbi_hash_vertex_resources(
    const GEGBISourceVertexResourceV6 *items,
    uint32_t count)
{
    uint64_t hash = GEGBI_V6_DEFAULT_HASH;
    for (uint32_t index = 0u; index < count; index++) {
        const GEGBISourceVertexResourceV6 *item = &items[index];
        hash = ge_gbi_hash_u32(hash, item->handle);
        hash = ge_gbi_hash_u32(hash, item->first_vertex);
        hash = ge_gbi_hash_u32(hash, item->vertex_count);
        hash = ge_gbi_hash_u32(hash, item->flags);
    }
    return hash;
}

static GEStatusV1 ge_gbi_validate_vertex_resource_value(
    const GEGBISourceVertexResourceV6 *item)
{
    if (item == NULL || item->handle == 0u ||
        (item->flags & ~GE_SOURCE_GBI_V6_VERTEX_RESOURCE_FLAG_MASK) != 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_source_gbi_v6_validate_vertex_resource_page(
    const GEGBISourceVertexResourcePageV6 *page)
{
    if (page == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (page->header.abi_version != GE_NATIVE_ABI_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    if (page->header.struct_size != (uint32_t)sizeof(*page) ||
        page->record_version != GE_SOURCE_GBI_V6_PACKET_VERSION) {
        return GE_STATUS_INVALID_SIZE;
    }
    if (page->page_index >= GE_SOURCE_GBI_V6_MAX_VERTEX_RESOURCE_PAGES ||
        page->item_count == 0u ||
        page->item_count > GE_SOURCE_GBI_V6_VERTEX_RESOURCE_PAGE_CAPACITY ||
        page->total_items == 0u ||
        page->total_items > GE_SOURCE_GBI_V6_MAX_VERTEX_RESOURCE_TOTAL ||
        page->page_capacity != GE_SOURCE_GBI_V6_VERTEX_RESOURCE_PAGE_CAPACITY ||
        page->first_item > page->total_items ||
        page->item_count > page->total_items - page->first_item ||
        page->reserved0 != 0u || page->reserved1 != 0u ||
        page->page_hash == 0u || page->manifest_hash == 0u) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    if (ge_gbi_hash_vertex_resources(page->items, page->item_count) !=
        page->page_hash) {
        return GE_STATUS_ASSET_MISMATCH;
    }
    for (uint32_t index = 0u; index < page->item_count; index++) {
        GEStatusV1 status = ge_gbi_validate_vertex_resource_value(&page->items[index]);
        if (status != GE_STATUS_OK) {
            return status;
        }
        for (uint32_t other = 0u; other < index; other++) {
            if (page->items[other].handle == page->items[index].handle) {
                return GE_STATUS_MALFORMED_STREAM;
            }
        }
    }
    return GE_STATUS_OK;
}

uint64_t ge_source_gbi_v6_hash_vertex_resource_manifest(
    const GEGBISourceVertexResourceV6 *base_items,
    uint32_t base_count,
    const GEGBISourceVertexResourcePageV6 *pages,
    uint32_t page_count)
{
    if (base_count > GE_SOURCE_GBI_V6_MAX_VERTEX_RESOURCES ||
        page_count > GE_SOURCE_GBI_V6_MAX_VERTEX_RESOURCE_PAGES ||
        (base_count != 0u && base_items == NULL) ||
        (page_count != 0u && pages == NULL)) {
        return 0u;
    }
    uint64_t hash = GEGBI_V6_DEFAULT_HASH;
    for (uint32_t index = 0u; index < base_count; index++) {
        const GEGBISourceVertexResourceV6 *item = &base_items[index];
        hash = ge_gbi_hash_u32(hash, item->handle);
        hash = ge_gbi_hash_u32(hash, item->first_vertex);
        hash = ge_gbi_hash_u32(hash, item->vertex_count);
        hash = ge_gbi_hash_u32(hash, item->flags);
    }
    for (uint32_t page = 0u; page < page_count; page++) {
        if (pages[page].item_count == 0u ||
            pages[page].item_count > GE_SOURCE_GBI_V6_VERTEX_RESOURCE_PAGE_CAPACITY) {
            return 0u;
        }
        for (uint32_t index = 0u; index < pages[page].item_count; index++) {
            const GEGBISourceVertexResourceV6 *item = &pages[page].items[index];
            hash = ge_gbi_hash_u32(hash, item->handle);
            hash = ge_gbi_hash_u32(hash, item->first_vertex);
            hash = ge_gbi_hash_u32(hash, item->vertex_count);
            hash = ge_gbi_hash_u32(hash, item->flags);
        }
    }
    return hash;
}

GEStatusV1 ge_source_gbi_v6_build_vertex_resource_pages(
    const GEGBISourceVertexResourceV6 *items,
    uint32_t total_items,
    GEGBISourceVertexResourcePageV6 *out_pages,
    uint32_t out_page_capacity,
    uint32_t *out_page_count)
{
    if (out_page_count == NULL ||
        (total_items != 0u && (items == NULL || out_pages == NULL)) ||
        total_items > GE_SOURCE_GBI_V6_MAX_VERTEX_RESOURCE_TOTAL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    uint32_t base_count = total_items > GE_SOURCE_GBI_V6_MAX_VERTEX_RESOURCES
        ? GE_SOURCE_GBI_V6_MAX_VERTEX_RESOURCES : total_items;
    uint32_t sidecar_items = total_items - base_count;
    uint32_t expected_pages =
        (sidecar_items + GE_SOURCE_GBI_V6_VERTEX_RESOURCE_PAGE_CAPACITY - 1u) /
        GE_SOURCE_GBI_V6_VERTEX_RESOURCE_PAGE_CAPACITY;
    if (out_page_capacity < expected_pages) {
        return GE_STATUS_REPLAY_BUDGET;
    }
    for (uint32_t index = 0u; index < total_items; index++) {
        GEStatusV1 status = ge_gbi_validate_vertex_resource_value(&items[index]);
        if (status != GE_STATUS_OK) {
            return status;
        }
        if (items[index].first_vertex > UINT32_MAX - items[index].vertex_count) {
            return GE_STATUS_MALFORMED_STREAM;
        }
        for (uint32_t other = 0u; other < index; other++) {
            /* Distinct source vertex-load handles may name overlapping
             * windows.  The source display lists deliberately reload
             * overlapping cache ranges; handle identity selects the load. */
            if (items[other].handle == items[index].handle) {
                return GE_STATUS_MALFORMED_STREAM;
            }
        }
    }
    uint64_t manifest_hash = ge_gbi_hash_vertex_resources(items, total_items);
    for (uint32_t page_index = 0u; page_index < expected_pages; page_index++) {
        GEGBISourceVertexResourcePageV6 *page = &out_pages[page_index];
        memset(page, 0, sizeof(*page));
        page->header.abi_version = GE_NATIVE_ABI_VERSION;
        page->header.struct_size = (uint32_t)sizeof(*page);
        page->record_version = GE_SOURCE_GBI_V6_PACKET_VERSION;
        page->page_index = page_index;
        page->total_items = total_items;
        page->page_capacity = GE_SOURCE_GBI_V6_VERTEX_RESOURCE_PAGE_CAPACITY;
        page->first_item = base_count +
            page_index * GE_SOURCE_GBI_V6_VERTEX_RESOURCE_PAGE_CAPACITY;
        uint32_t remaining = total_items - page->first_item;
        page->item_count = remaining > GE_SOURCE_GBI_V6_VERTEX_RESOURCE_PAGE_CAPACITY
            ? GE_SOURCE_GBI_V6_VERTEX_RESOURCE_PAGE_CAPACITY : remaining;
        memcpy(page->items, &items[page->first_item],
               (size_t)page->item_count * sizeof(page->items[0]));
        page->page_hash = ge_gbi_hash_vertex_resources(page->items, page->item_count);
        page->manifest_hash = manifest_hash;
    }
    *out_page_count = expected_pages;
    return GE_STATUS_OK;
}

static GEStatusV1 ge_gbi_validate_result_envelope(const GEGBIResultV6 *result)
{
    if (result == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (result->header.abi_version != GE_NATIVE_ABI_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    if (result->header.struct_size != (uint32_t)sizeof(*result) ||
        result->packet_version != GE_SOURCE_GBI_V6_PACKET_VERSION) {
        return GE_STATUS_INVALID_SIZE;
    }
    if (result->state_count > GE_SOURCE_GBI_V6_MAX_STATES ||
        result->draw_count > GE_SOURCE_GBI_V6_MAX_DRAWS ||
        result->event_count > GE_SOURCE_GBI_V6_MAX_EVENTS ||
        result->diagnostic_count > GE_SOURCE_GBI_V6_MAX_DIAGNOSTICS) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    return GE_STATUS_OK;
}

static GEStatusV1 ge_gbi_copy_window(const void *source,
                                     uint32_t available,
                                     uint32_t first,
                                     uint32_t count,
                                     void *destination,
                                     uint32_t out_capacity,
                                     size_t item_size)
{
    if (first > available || count > available - first) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    if (count > out_capacity) {
        return GE_STATUS_REPLAY_BUDGET;
    }
    if (count != 0u && destination == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (count != 0u) {
        const uint8_t *source_bytes = (const uint8_t *)source;
        uint8_t *destination_bytes = (uint8_t *)destination;
        memmove(destination_bytes,
                source_bytes + (size_t)first * item_size,
                (size_t)count * item_size);
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_source_gbi_v6_copy_states(
    const GEGBIResultV6 *result,
    uint32_t first,
    uint32_t count,
    GEGBIStateV6 *out_values,
    uint32_t out_capacity)
{
    GEStatusV1 status = ge_gbi_validate_result_envelope(result);
    if (status != GE_STATUS_OK) {
        return status;
    }
    status = ge_gbi_copy_window(result->states, result->state_count,
                                first, count, out_values, out_capacity,
                                sizeof(GEGBIStateV6));
    if (status != GE_STATUS_OK) {
        return status;
    }
    for (uint32_t index = 0u; index < count; index++) {
        if (out_values[index].state_hash == 0u) {
            return GE_STATUS_ASSET_MISMATCH;
        }
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_source_gbi_v6_copy_draws(
    const GEGBIResultV6 *result,
    uint32_t first,
    uint32_t count,
    GEGBIDrawV6 *out_values,
    uint32_t out_capacity)
{
    GEStatusV1 status = ge_gbi_validate_result_envelope(result);
    if (status != GE_STATUS_OK) {
        return status;
    }
    status = ge_gbi_copy_window(result->draws, result->draw_count,
                                first, count, out_values, out_capacity,
                                sizeof(GEGBIDrawV6));
    if (status != GE_STATUS_OK) {
        return status;
    }
    for (uint32_t index = 0u; index < count; index++) {
        const GEGBIDrawV6 *draw = &out_values[index];
        if (draw->event_index >= result->event_count ||
            draw->state_index >= result->state_count ||
            draw->vertex_slot_a >= GE_SOURCE_GBI_V6_MAX_VERTEX_CACHE ||
            draw->vertex_slot_b >= GE_SOURCE_GBI_V6_MAX_VERTEX_CACHE ||
            draw->vertex_slot_c >= GE_SOURCE_GBI_V6_MAX_VERTEX_CACHE ||
            draw->source_vertex_a >= GE_SOURCE_GBI_V6_MAX_VERTICES ||
            draw->source_vertex_b >= GE_SOURCE_GBI_V6_MAX_VERTICES ||
            draw->source_vertex_c >= GE_SOURCE_GBI_V6_MAX_VERTICES ||
            draw->state_hash == 0u) {
            return GE_STATUS_ASSET_MISMATCH;
        }
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_source_gbi_v6_copy_events(
    const GEGBIResultV6 *result,
    uint32_t first,
    uint32_t count,
    GEGBIEventV6 *out_values,
    uint32_t out_capacity)
{
    GEStatusV1 status = ge_gbi_validate_result_envelope(result);
    if (status != GE_STATUS_OK) {
        return status;
    }
    status = ge_gbi_copy_window(result->events, result->event_count,
                                first, count, out_values, out_capacity,
                                sizeof(GEGBIEventV6));
    if (status != GE_STATUS_OK) {
        return status;
    }
    for (uint32_t index = 0u; index < count; index++) {
        if (out_values[index].kind < GE_SOURCE_GBI_V6_EVENT_COMMAND ||
            out_values[index].kind > GE_SOURCE_GBI_V6_EVENT_UNSUPPORTED) {
            return GE_STATUS_ASSET_MISMATCH;
        }
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_source_gbi_v6_copy_diagnostics(
    const GEGBIResultV6 *result,
    uint32_t first,
    uint32_t count,
    GEGBIDiagnosticV6 *out_values,
    uint32_t out_capacity)
{
    GEStatusV1 status = ge_gbi_validate_result_envelope(result);
    if (status != GE_STATUS_OK) {
        return status;
    }
    status = ge_gbi_copy_window(result->diagnostics, result->diagnostic_count,
                                first, count, out_values, out_capacity,
                                sizeof(GEGBIDiagnosticV6));
    if (status != GE_STATUS_OK) {
        return status;
    }
    for (uint32_t index = 0u; index < count; index++) {
        const GEGBIDiagnosticV6 *diagnostic = &out_values[index];
        if (diagnostic->code > GE_SOURCE_GBI_V6_DIAG_MALFORMED ||
            diagnostic->reserved != 0u) {
            return GE_STATUS_ASSET_MISMATCH;
        }
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_source_gbi_v6_copy_images(
    const GEGBISourcePacketV6 *packet,
    uint32_t first,
    uint32_t count,
    GEGBISourceImageResourceV6 *out_values,
    uint32_t out_capacity)
{
    if (packet == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (packet->header.abi_version != GE_NATIVE_ABI_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    if (packet->header.struct_size != (uint32_t)sizeof(*packet) ||
        packet->packet_version != GE_SOURCE_GBI_V6_PACKET_VERSION) {
        return GE_STATUS_INVALID_SIZE;
    }
    if (packet->image_count > GE_SOURCE_GBI_V6_MAX_IMAGES) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    GEStatusV1 status = ge_gbi_copy_window(packet->images, packet->image_count,
                                           first, count, out_values, out_capacity,
                                           sizeof(GEGBISourceImageResourceV6));
    if (status != GE_STATUS_OK) {
        return status;
    }
    for (uint32_t index = 0u; index < count; index++) {
        if (out_values[index].handle == 0u || out_values[index].reserved != 0u) {
            return GE_STATUS_ASSET_MISMATCH;
        }
    }
    return GE_STATUS_OK;
}

static void ge_gbi_init_result(GEGBIResultV6 *result)
{
    memset(result, 0, sizeof(*result));
    result->header.abi_version = GE_NATIVE_ABI_VERSION;
    result->header.struct_size = (uint32_t)sizeof(*result);
    result->packet_version = GE_SOURCE_GBI_V6_PACKET_VERSION;
    result->status = GE_STATUS_OK;
}

static void ge_gbi_first_error(GEGBIEngineV6 *engine,
                               GEStatusV1 status,
                               uint32_t opcode,
                               uint32_t offset)
{
    if (engine->result.status == GE_STATUS_OK ||
        engine->result.status == GE_STATUS_UNSUPPORTED_COMMAND) {
        engine->result.status = status;
        engine->result.error_opcode = opcode;
        engine->result.error_offset = offset;
        if (engine->frame_depth != 0u) {
            engine->result.error_list_handle =
                engine->frames[engine->frame_depth - 1u].handle;
            engine->result.error_list_depth = engine->frame_depth - 1u;
        }
    }
}

static void ge_gbi_add_diagnostic(GEGBIEngineV6 *engine,
                                  uint32_t code,
                                  uint32_t opcode,
                                  uint32_t offset,
                                  uint32_t detail0,
                                  uint32_t detail1)
{
    if (engine->result.diagnostic_count >= GE_SOURCE_GBI_V6_MAX_DIAGNOSTICS) {
        ge_gbi_first_error(engine, GE_STATUS_REPLAY_BUDGET, opcode, offset);
        return;
    }
    GEGBIDiagnosticV6 *diagnostic =
        &engine->result.diagnostics[engine->result.diagnostic_count++];
    diagnostic->code = code;
    diagnostic->opcode = opcode;
    diagnostic->command_offset = offset;
    diagnostic->list_handle = engine->frame_depth == 0u
        ? 0u : engine->frames[engine->frame_depth - 1u].handle;
    diagnostic->list_depth = engine->frame_depth == 0u
        ? 0u : engine->frame_depth - 1u;
    diagnostic->detail0 = detail0;
    diagnostic->detail1 = detail1;
}

static GEStatusV1 ge_gbi_fail(GEGBIEngineV6 *engine,
                              GEStatusV1 status,
                              uint32_t diagnostic,
                              uint32_t opcode,
                              uint32_t offset,
                              uint32_t detail0,
                              uint32_t detail1)
{
    ge_gbi_add_diagnostic(engine, diagnostic, opcode, offset, detail0, detail1);
    ge_gbi_first_error(engine, status, opcode, offset);
    return status;
}

static void ge_gbi_unsupported(GEGBIEngineV6 *engine,
                               uint32_t opcode,
                               uint32_t offset,
                               uint32_t w0,
                               uint32_t w1)
{
    engine->result.unsupported_count++;
    engine->saw_unsupported = 1u;
    ge_gbi_add_diagnostic(engine, GE_SOURCE_GBI_V6_DIAG_UNSUPPORTED,
                          opcode, offset, w0, w1);
    if (engine->result.status == GE_STATUS_OK) {
        ge_gbi_first_error(engine, GE_STATUS_UNSUPPORTED_COMMAND, opcode, offset);
    }
}

static const GEGBISourceListV6 *ge_gbi_find_list(const GEGBIEngineV6 *engine,
                                                  uint32_t handle)
{
    for (uint32_t index = 0; index < engine->packet->list_count; index++) {
        if (engine->packet->lists[index].handle == handle) {
            return &engine->packet->lists[index];
        }
    }
    return NULL;
}

static const GEGBISourceVertexResourceV6 *ge_gbi_find_vertex_resource(
    const GEGBIEngineV6 *engine,
    uint32_t handle)
{
    for (uint32_t index = 0; index < engine->packet->vertex_resource_count; index++) {
        if (engine->packet->vertex_resources[index].handle == handle) {
            return &engine->packet->vertex_resources[index];
        }
    }
    for (uint32_t page_index = 0u;
         page_index < engine->vertex_page_count; page_index++) {
        const GEGBISourceVertexResourcePageV6 *page =
            &engine->vertex_pages[page_index];
        for (uint32_t index = 0u; index < page->item_count; index++) {
            if (page->items[index].handle == handle) {
                return &page->items[index];
            }
        }
    }
    return NULL;
}

static const GEGBISourceMatrixResourceV6 *ge_gbi_find_matrix(
    const GEGBIEngineV6 *engine,
    uint32_t handle)
{
    for (uint32_t index = 0; index < engine->packet->matrix_count; index++) {
        if (engine->packet->matrices[index].handle == handle) {
            return &engine->packet->matrices[index];
        }
    }
    return NULL;
}

static const GEGBISourceViewportResourceV6 *ge_gbi_find_viewport(
    const GEGBIEngineV6 *engine,
    uint32_t handle)
{
    for (uint32_t index = 0; index < engine->packet->viewport_count; index++) {
        if (engine->packet->viewports[index].handle == handle) {
            return &engine->packet->viewports[index];
        }
    }
    return NULL;
}

static const GEGBISourceImageResourceV6 *ge_gbi_find_image(
    const GEGBIEngineV6 *engine,
    uint32_t handle)
{
    for (uint32_t index = 0; index < engine->packet->image_count; index++) {
        if (engine->packet->images[index].handle == handle) {
            return &engine->packet->images[index];
        }
    }
    return NULL;
}

static int ge_gbi_active_handle(const GEGBIEngineV6 *engine, uint32_t handle)
{
    for (uint32_t index = 0; index < engine->frame_depth; index++) {
        if (engine->active_handles[index] == handle) {
            return 1;
        }
    }
    return 0;
}

static uint64_t ge_gbi_state_hash(const GEGBIStateV6 *state)
{
    uint64_t hash = GEGBI_V6_DEFAULT_HASH;
    hash = ge_gbi_hash_bytes(hash, &state->geometry_mode, sizeof(uint32_t) * 28u);
    hash = ge_gbi_hash_bytes(hash, state->tiles, sizeof(state->tiles));
    return hash;
}

static void ge_gbi_touch_state(GEGBIEngineV6 *engine)
{
    engine->result.state.state_generation++;
    engine->result.state.state_hash = ge_gbi_state_hash(&engine->result.state);
}

static GEStatusV1 ge_gbi_snapshot_state(GEGBIEngineV6 *engine,
                                        uint32_t opcode,
                                        uint32_t offset,
                                        uint32_t *state_index)
{
    GEGBIStateV6 snapshot = engine->result.state;
    /* Generation is a mutable diagnostic counter, not render semantics. */
    snapshot.state_generation = 0u;
    snapshot.state_hash = ge_gbi_state_hash(&snapshot);
    for (uint32_t index = 0; index < engine->result.state_count; index++) {
        if (memcmp(&engine->result.states[index], &snapshot, sizeof(snapshot)) == 0) {
            *state_index = index;
            return GE_STATUS_OK;
        }
    }
    if (engine->result.state_count >= GE_SOURCE_GBI_V6_MAX_STATES) {
        return ge_gbi_fail(engine, GE_STATUS_REPLAY_BUDGET,
                           GE_SOURCE_GBI_V6_DIAG_CAPACITY,
                           opcode, offset,
                           GE_SOURCE_GBI_V6_MAX_STATES, 0u);
    }
    *state_index = engine->result.state_count;
    engine->result.states[engine->result.state_count++] = snapshot;
    return GE_STATUS_OK;
}

static int ge_gbi_emit_event(GEGBIEngineV6 *engine,
                             uint32_t kind,
                             uint32_t opcode,
                             uint32_t flags,
                             uint32_t offset,
                             const uint32_t args[8])
{
    if (engine->result.event_count >= GE_SOURCE_GBI_V6_MAX_EVENTS) {
        (void)ge_gbi_fail(engine, GE_STATUS_REPLAY_BUDGET,
                          GE_SOURCE_GBI_V6_DIAG_CAPACITY,
                          opcode, offset, GE_SOURCE_GBI_V6_MAX_EVENTS, 0u);
        return 0;
    }
    GEGBIEventV6 *event = &engine->result.events[engine->result.event_count++];
    memset(event, 0, sizeof(*event));
    event->kind = kind;
    event->opcode = opcode;
    event->flags = flags;
    event->command_offset = offset;
    if (engine->frame_depth != 0u) {
        event->list_handle = engine->frames[engine->frame_depth - 1u].handle;
        event->list_depth = engine->frame_depth - 1u;
    }
    event->a = args[0];
    event->b = args[1];
    event->c = args[2];
    event->d = args[3];
    event->e = args[4];
    event->f = args[5];
    event->g = args[6];
    event->h = args[7];

    engine->event_hash = ge_gbi_hash_u32(engine->event_hash, event->kind);
    engine->event_hash = ge_gbi_hash_u32(engine->event_hash, event->opcode);
    engine->event_hash = ge_gbi_hash_u32(engine->event_hash, event->flags);
    engine->event_hash = ge_gbi_hash_u32(engine->event_hash, event->command_offset);
    engine->event_hash = ge_gbi_hash_u32(engine->event_hash, event->list_handle);
    engine->event_hash = ge_gbi_hash_u32(engine->event_hash, event->list_depth);
    for (uint32_t index = 0; index < 8u; index++) {
        engine->event_hash = ge_gbi_hash_u32(engine->event_hash, args[index]);
    }
    return 1;
}

static GEStatusV1 ge_gbi_emit_draw(GEGBIEngineV6 *engine,
                                   uint32_t offset,
                                   uint32_t opcode,
                                   uint32_t a,
                                   uint32_t b,
                                   uint32_t c,
                                   uint32_t tile)
{
    if (engine->result.draw_count >= GE_SOURCE_GBI_V6_MAX_DRAWS) {
        return ge_gbi_fail(engine, GE_STATUS_REPLAY_BUDGET,
                           GE_SOURCE_GBI_V6_DIAG_CAPACITY,
                           opcode, offset, GE_SOURCE_GBI_V6_MAX_DRAWS, 0u);
    }
    uint32_t state_index = 0u;
    GEStatusV1 snapshot_status = ge_gbi_snapshot_state(engine, opcode, offset,
                                                       &state_index);
    if (snapshot_status != GE_STATUS_OK) {
        return snapshot_status;
    }
    uint32_t args[8] = { a, b, c, tile, engine->result.state.texture_image_handle,
                         state_index, engine->result.state.state_generation, 0u };
    if (!ge_gbi_emit_event(engine, GE_SOURCE_GBI_V6_EVENT_TRIANGLE,
                           opcode, 0u, offset, args)) {
        return GE_STATUS_REPLAY_BUDGET;
    }
    GEGBIDrawV6 *draw = &engine->result.draws[engine->result.draw_count];
    memset(draw, 0, sizeof(*draw));
    draw->event_index = engine->result.event_count - 1u;
    draw->source_command_offset = offset;
    if (engine->frame_depth != 0u) {
        draw->source_list_handle = engine->frames[engine->frame_depth - 1u].handle;
        draw->source_list_depth = engine->frame_depth - 1u;
    }
    draw->vertex_slot_a = a;
    draw->vertex_slot_b = b;
    draw->vertex_slot_c = c;
    draw->source_vertex_a = engine->vertex_sources[a];
    draw->source_vertex_b = engine->vertex_sources[b];
    draw->source_vertex_c = engine->vertex_sources[c];
    draw->tile = tile;
    draw->texture_handle = engine->result.state.texture_image_handle;
    draw->flags = engine->result.state.texture_enabled_level_tile;
    draw->state_index = state_index;
    draw->state_hash = engine->result.state.state_hash;
    engine->result.draw_count++;
    return GE_STATUS_OK;
}

static int ge_gbi_decode_tri_index(uint32_t raw, uint32_t scale, uint32_t *index)
{
    if (scale != 0u && raw % scale != 0u) {
        return 0;
    }
    if (scale != 0u) {
        raw /= scale;
    }
    if (raw > GEGBI_V6_TRI_INDEX_MAX) {
        return 0;
    }
    *index = raw;
    return 1;
}

static int ge_gbi_decode_old_tri_index(uint32_t raw, uint32_t *index)
{
    /* Classic GE/F3D is deliberately strict: source G_TRI1 stores *10. */
    if ((raw % 10u) != 0u || raw / 10u > GEGBI_V6_TRI_INDEX_MAX) {
        return 0;
    }
    *index = raw / 10u;
    return 1;
}

static GEStatusV1 ge_gbi_validate_triangle(const GEGBIEngineV6 *engine,
                                           uint32_t opcode,
                                           uint32_t offset,
                                           uint32_t a,
                                           uint32_t b,
                                           uint32_t c)
{
    if (a >= GE_SOURCE_GBI_V6_MAX_VERTEX_CACHE ||
        b >= GE_SOURCE_GBI_V6_MAX_VERTEX_CACHE ||
        c >= GE_SOURCE_GBI_V6_MAX_VERTEX_CACHE ||
        !engine->vertex_valid[a] || !engine->vertex_valid[b] ||
        !engine->vertex_valid[c]) {
        return GE_STATUS_VERTEX_OUT_OF_RANGE;
    }
    (void)opcode;
    (void)offset;
    return GE_STATUS_OK;
}

static GEStatusV1 ge_gbi_record_vertex_load_provenance(
    GEGBIEngineV6 *engine,
    uint32_t command_offset,
    uint32_t destination,
    uint32_t source_index,
    uint32_t count)
{
    if (engine->vertex_load_provenance == NULL || count == 0u) {
        return GE_STATUS_OK;
    }
    if (count > engine->vertex_load_provenance_capacity -
                    engine->vertex_load_provenance_count) {
        return ge_gbi_fail(engine, GE_STATUS_REPLAY_BUDGET,
                           GE_SOURCE_GBI_V6_DIAG_CAPACITY,
                           GE_SOURCE_GBI_V6_OP_VTX, command_offset,
                           count, engine->vertex_load_provenance_capacity);
    }
    for (uint32_t index = 0u; index < count; index++) {
        GEGBIVertexLoadProvenanceV6 *value =
            &engine->vertex_load_provenance[
                engine->vertex_load_provenance_count++];
        memset(value, 0, sizeof(*value));
        value->header.abi_version = GE_NATIVE_ABI_VERSION;
        value->header.struct_size = (uint32_t)sizeof(*value);
        value->record_version = GE_SOURCE_GBI_V6_CONTRACT_VERSION;
        value->flags = GE_SOURCE_GBI_V6_VERTEX_LOAD_PROVENANCE_FLAG_SOURCE_ORDERED
            | engine->modelview_provenance_flags;
        value->command_offset = command_offset;
        value->cache_slot = destination + index;
        value->source_vertex = source_index + index;
        value->modelview_handle = engine->result.state.modelview_handle;
        value->modelview_depth = engine->result.state.modelview_depth;
    }
    return GE_STATUS_OK;
}

static GEStatusV1 ge_gbi_vertex_load(GEGBIEngineV6 *engine,
                                     uint32_t f3dex2,
                                     uint32_t opcode,
                                     uint32_t offset,
                                     uint32_t w0,
                                     uint32_t w1)
{
    uint32_t encoded = (w0 >> 16) & 0xffu;
    uint32_t count;
    uint32_t destination;
    if (f3dex2 != 0u) {
        count = (w0 >> 12) & 0xffu;
        uint32_t end = (w0 >> 1) & 0x7fu;
        if (count == 0u || end < count) {
            return ge_gbi_fail(engine, GE_STATUS_MALFORMED_STREAM,
                               GE_SOURCE_GBI_V6_DIAG_VERTEX,
                               opcode, offset, count, end);
        }
        destination = end - count;
    } else {
        uint32_t packed = w0 & 0xffffu;
        count = (encoded >> 4) + 1u;
        destination = encoded & 0x0fu;
        /* A small GE fixture form carries the count directly in the low byte. */
        /* The strict source encoder stores the byte span (count * 16) in
         * the low word even when count == 1, while the compact smoke fixture
         * uses a non-multiple direct count. Do not reinterpret a valid 16-byte
         * source load as sixteen vertices. */
        if (encoded == 0u && packed > 0u && packed <= GE_SOURCE_GBI_V6_MAX_VERTEX_CACHE &&
            (packed & 0x0fu) != 0u) {
            count = packed;
            destination = 0u;
        }
    }
    const GEGBISourceVertexResourceV6 *resource =
        ge_gbi_find_vertex_resource(engine, w1);
    if (resource == NULL) {
        return ge_gbi_fail(engine, GE_STATUS_RESOURCE_NOT_FOUND,
                           GE_SOURCE_GBI_V6_DIAG_RESOURCE,
                           opcode, offset, w1, 0u);
    }
    if (count == 0u || count > GE_SOURCE_GBI_V6_MAX_VERTEX_CACHE ||
        destination > GE_SOURCE_GBI_V6_MAX_VERTEX_CACHE - count ||
        resource->vertex_count < count ||
        resource->first_vertex > engine->packet->vertex_count ||
        count > engine->packet->vertex_count - resource->first_vertex) {
        return ge_gbi_fail(engine, GE_STATUS_VERTEX_OUT_OF_RANGE,
                           GE_SOURCE_GBI_V6_DIAG_VERTEX,
                           opcode, offset, destination, count);
    }
    for (uint32_t index = 0; index < count; index++) {
        uint32_t slot = destination + index;
        uint32_t source_index = resource->first_vertex + index;
        engine->vertex_cache[slot] = engine->packet->vertices[source_index];
        engine->vertex_sources[slot] = source_index;
        engine->vertex_valid[slot] = 1u;
        engine->result.vertices[slot].value = engine->vertex_cache[slot];
        engine->result.vertices[slot].slot = slot;
        engine->result.vertices[slot].source_index = source_index;
    }
    engine->result.vertex_count += count;
    ge_gbi_touch_state(engine);
    uint32_t args[8] = { w1, count, destination, resource->first_vertex,
                         engine->result.state.state_generation, 0u, 0u, 0u };
    if (!ge_gbi_emit_event(engine, GE_SOURCE_GBI_V6_EVENT_VERTEX_LOAD,
                           opcode, 0u, offset, args)) {
        return GE_STATUS_REPLAY_BUDGET;
    }
    return ge_gbi_record_vertex_load_provenance(
        engine, offset, destination, resource->first_vertex, count);
}

static GEStatusV1 ge_gbi_emit_tri1(GEGBIEngineV6 *engine,
                                   uint32_t f3dex2,
                                   uint32_t opcode,
                                   uint32_t offset,
                                   uint32_t w0,
                                   uint32_t w1)
{
    uint32_t a;
    uint32_t b;
    uint32_t c;
    if (f3dex2 != 0u) {
        if (!ge_gbi_decode_tri_index((w0 >> 16) & 0xffu, 2u, &a) ||
            !ge_gbi_decode_tri_index((w0 >> 8) & 0xffu, 2u, &b) ||
            !ge_gbi_decode_tri_index(w0 & 0xffu, 2u, &c)) {
            return ge_gbi_fail(engine, GE_STATUS_VERTEX_OUT_OF_RANGE,
                               GE_SOURCE_GBI_V6_DIAG_VERTEX,
                               opcode, offset, w0, 0u);
        }
    } else if (!ge_gbi_decode_old_tri_index((w1 >> 16) & 0xffu, &a) ||
               !ge_gbi_decode_old_tri_index((w1 >> 8) & 0xffu, &b) ||
               !ge_gbi_decode_old_tri_index(w1 & 0xffu, &c)) {
        return ge_gbi_fail(engine, GE_STATUS_VERTEX_OUT_OF_RANGE,
                           GE_SOURCE_GBI_V6_DIAG_VERTEX,
                           opcode, offset, w1, 0u);
    }
    GEStatusV1 status = ge_gbi_validate_triangle(engine, opcode, offset, a, b, c);
    if (status != GE_STATUS_OK) {
        return ge_gbi_fail(engine, status, GE_SOURCE_GBI_V6_DIAG_VERTEX,
                           opcode, offset, a, b);
    }
    return ge_gbi_emit_draw(engine, offset, opcode, a, b, c,
                            (engine->result.state.texture_enabled_level_tile >> 8) & 7u);
}

static GEStatusV1 ge_gbi_emit_tri4(GEGBIEngineV6 *engine,
                                   uint32_t opcode,
                                   uint32_t offset,
                                   uint32_t w0,
                                   uint32_t w1)
{
    uint32_t z[4] = {
        w0 & 0xfu, (w0 >> 4) & 0xfu, (w0 >> 8) & 0xfu, (w0 >> 12) & 0xfu,
    };
    uint32_t x[4] = {
        w1 & 0xfu, (w1 >> 8) & 0xfu, (w1 >> 16) & 0xfu, (w1 >> 24) & 0xfu,
    };
    uint32_t y[4] = {
        (w1 >> 4) & 0xfu, (w1 >> 12) & 0xfu,
        (w1 >> 20) & 0xfu, (w1 >> 28) & 0xfu,
    };
    for (uint32_t triangle = 0; triangle < 4u; triangle++) {
        if (x[triangle] == 0u && y[triangle] == 0u && z[triangle] == 0u) {
            continue;
        }
        GEStatusV1 status = ge_gbi_validate_triangle(engine, opcode, offset,
                                                      x[triangle], y[triangle], z[triangle]);
        if (status != GE_STATUS_OK) {
            return ge_gbi_fail(engine, status, GE_SOURCE_GBI_V6_DIAG_VERTEX,
                               opcode, offset, x[triangle], y[triangle]);
        }
        status = ge_gbi_emit_draw(engine, offset, opcode,
                                  x[triangle], y[triangle], z[triangle],
                                  (engine->result.state.texture_enabled_level_tile >> 8) & 7u);
        if (status != GE_STATUS_OK) {
            return status;
        }
    }
    return GE_STATUS_OK;
}

static GEStatusV1 ge_gbi_matrix(GEGBIEngineV6 *engine,
                                uint32_t f3dex2,
                                uint32_t opcode,
                                uint32_t offset,
                                uint32_t w0,
                                uint32_t w1)
{
    if (ge_gbi_find_matrix(engine, w1) == NULL) {
        return ge_gbi_fail(engine, GE_STATUS_RESOURCE_NOT_FOUND,
                           GE_SOURCE_GBI_V6_DIAG_RESOURCE,
                           opcode, offset, w1, 0u);
    }
    uint32_t params;
    uint32_t projection;
    uint32_t push;
    uint32_t load;
    if (f3dex2 != 0u) {
        params = (w0 & 0xffu) ^ 0x01u;
        projection = (params & 0x04u) != 0u;
        push = params & 0x01u;
    } else {
        params = (w0 >> 16) & 0xffu;
        projection = (params & 0x01u) != 0u;
        push = (params & 0x04u) != 0u;
    }
    load = (params & 0x02u) != 0u;
    if (projection == 0u && (load == 0u || push != 0u)) {
        engine->modelview_provenance_flags = 0u;
    }
    uint32_t *stack = projection ? engine->projection_handles : engine->modelview_handles;
    uint32_t *depth = projection ? &engine->projection_depth : &engine->modelview_depth;
    if (push) {
        if (*depth >= GE_SOURCE_GBI_V6_MAX_MATRIX_STACK) {
            return ge_gbi_fail(engine, GE_STATUS_MATRIX_STACK,
                               GE_SOURCE_GBI_V6_DIAG_STACK,
                               opcode, offset, *depth, 0u);
        }
        stack[*depth] = stack[*depth - 1u];
        (*depth)++;
    }
    stack[*depth - 1u] = w1;
    if (projection) {
        engine->result.state.projection_handle = w1;
        engine->result.state.projection_depth = *depth;
    } else {
        engine->result.state.modelview_handle = w1;
        engine->result.state.modelview_depth = *depth;
    }
    ge_gbi_touch_state(engine);
    uint32_t args[8] = { w1, projection, load, push, *depth,
                         engine->result.state.state_generation, 0u, 0u };
    return ge_gbi_emit_event(engine, GE_SOURCE_GBI_V6_EVENT_STATE,
                             opcode, 0u, offset, args)
        ? GE_STATUS_OK : GE_STATUS_REPLAY_BUDGET;
}

static GEStatusV1 ge_gbi_pop_matrix(GEGBIEngineV6 *engine,
                                     uint32_t f3dex2,
                                     uint32_t opcode,
                                     uint32_t offset,
                                     uint32_t w0,
                                     uint32_t w1)
{
    uint32_t projection = 0u;
    uint32_t count = 1u;
    if (f3dex2 != 0u) {
        count = w1 / 64u;
        if (count == 0u) {
            count = 1u;
        }
        (void)w0;
    } else {
        projection = (w1 & 1u) != 0u;
    }
    uint32_t *stack = projection ? engine->projection_handles : engine->modelview_handles;
    uint32_t *depth = projection ? &engine->projection_depth : &engine->modelview_depth;
    if (projection == 0u) {
        engine->modelview_provenance_flags = 0u;
    }
    if (count == 0u || *depth <= count) {
        return ge_gbi_fail(engine, GE_STATUS_MATRIX_STACK,
                           GE_SOURCE_GBI_V6_DIAG_STACK,
                           opcode, offset, *depth, count);
    }
    *depth -= count;
    if (projection) {
        engine->result.state.projection_handle = stack[*depth - 1u];
        engine->result.state.projection_depth = *depth;
    } else {
        engine->result.state.modelview_handle = stack[*depth - 1u];
        engine->result.state.modelview_depth = *depth;
    }
    ge_gbi_touch_state(engine);
    uint32_t args[8] = { projection, count, *depth,
                         projection ? engine->result.state.projection_handle
                                    : engine->result.state.modelview_handle,
                         engine->result.state.state_generation, 0u, 0u, 0u };
    return ge_gbi_emit_event(engine, GE_SOURCE_GBI_V6_EVENT_STATE,
                             opcode, 0u, offset, args)
        ? GE_STATUS_OK : GE_STATUS_REPLAY_BUDGET;
}

static GEStatusV1 ge_gbi_viewport(GEGBIEngineV6 *engine,
                                  uint32_t f3dex2,
                                  uint32_t opcode,
                                  uint32_t offset,
                                  uint32_t w0,
                                  uint32_t w1)
{
    uint32_t index = f3dex2 != 0u
        ? w0 & 0xffu : (w0 >> 16) & 0xffu;
    if (index != 8u && index != 0u) {
        return ge_gbi_fail(engine, GE_STATUS_MALFORMED_STREAM,
                           GE_SOURCE_GBI_V6_DIAG_ARGUMENT,
                           opcode, offset, index, 8u);
    }
    const GEGBISourceViewportResourceV6 *resource = ge_gbi_find_viewport(engine, w1);
    if (resource == NULL) {
        return ge_gbi_fail(engine, GE_STATUS_RESOURCE_NOT_FOUND,
                           GE_SOURCE_GBI_V6_DIAG_RESOURCE,
                           opcode, offset, w1, 0u);
    }
    engine->result.state.viewport_handle = resource->handle;
    ge_gbi_touch_state(engine);
    uint32_t args[8] = { resource->handle, index, (uint32_t)resource->values[0],
                         (uint32_t)resource->values[1], (uint32_t)resource->values[2],
                         (uint32_t)resource->values[4], (uint32_t)resource->values[5],
                         engine->result.state.state_generation };
    return ge_gbi_emit_event(engine, GE_SOURCE_GBI_V6_EVENT_STATE,
                             opcode, 0u, offset, args)
        ? GE_STATUS_OK : GE_STATUS_REPLAY_BUDGET;
}

static GEStatusV1 ge_gbi_settimg(GEGBIEngineV6 *engine,
                                 uint32_t opcode,
                                 uint32_t offset,
                                 uint32_t w0,
                                 uint32_t w1)
{
    if (engine->packet->image_count != 0u && ge_gbi_find_image(engine, w1) == NULL) {
        return ge_gbi_fail(engine, GE_STATUS_RESOURCE_NOT_FOUND,
                           GE_SOURCE_GBI_V6_DIAG_TEXTURE,
                           opcode, offset, w1, 0u);
    }
    uint32_t format = (w0 >> 21) & 7u;
    uint32_t size = (w0 >> 19) & 3u;
    uint32_t width = (w0 & 0xfffu) + 1u;
    engine->result.state.texture_image_handle = w1;
    engine->result.state.texture_image_format_size_width =
        (format << 29) | (size << 27) | (width & 0x07ffffffu);
    ge_gbi_touch_state(engine);
    uint32_t args[8] = { w1, format, size, width,
                         engine->result.state.state_generation, 0u, 0u, 0u };
    return ge_gbi_emit_event(engine, GE_SOURCE_GBI_V6_EVENT_TEXTURE,
                             opcode, 0u, offset, args)
        ? GE_STATUS_OK : GE_STATUS_REPLAY_BUDGET;
}

static GEStatusV1 ge_gbi_texture(GEGBIEngineV6 *engine,
                                 uint32_t f3dex2,
                                 uint32_t opcode,
                                 uint32_t offset,
                                 uint32_t w0,
                                 uint32_t w1)
{
    uint32_t tile = (w0 >> 8) & 7u;
    uint32_t level = (w0 >> 11) & 7u;
    uint32_t enabled = f3dex2 != 0u
        ? (w0 >> 1) & 0x7fu : w0 & 0xffu;
    engine->result.state.texture_state = w0;
    engine->result.state.texture_enabled_level_tile =
        ((enabled != 0u) ? 1u : 0u) | (level << 4) | (tile << 8);
    engine->result.state.texture_scale_s = w1 >> 16;
    engine->result.state.texture_scale_t = w1 & 0xffffu;
    ge_gbi_touch_state(engine);
    uint32_t args[8] = { enabled, level, tile, w1 >> 16, w1 & 0xffffu,
                         engine->result.state.state_generation, 0u, 0u };
    return ge_gbi_emit_event(engine, GE_SOURCE_GBI_V6_EVENT_TEXTURE,
                             opcode, 0u, offset, args)
        ? GE_STATUS_OK : GE_STATUS_REPLAY_BUDGET;
}

static GEStatusV1 ge_gbi_settile(GEGBIEngineV6 *engine,
                                 uint32_t opcode,
                                 uint32_t offset,
                                 uint32_t w0,
                                 uint32_t w1)
{
    uint32_t tile = (w1 >> 24) & 7u;
    if (tile >= GE_SOURCE_GBI_V6_MAX_TILES) {
        return ge_gbi_fail(engine, GE_STATUS_TEXTURE_FORMAT,
                           GE_SOURCE_GBI_V6_DIAG_TEXTURE,
                           opcode, offset, tile, GE_SOURCE_GBI_V6_MAX_TILES);
    }
    GEGBITileStateV6 *state = &engine->result.state.tiles[tile];
    state->format_size_line_tmem = w0 & 0x00ffffffu;
    state->tile_palette_cmt_maskt_shiftt = w1 & 0x00fff000u;
    state->cms_masks_shifts = w1 & 0x00000fffu;
    ge_gbi_touch_state(engine);
    uint32_t args[8] = { tile, state->format_size_line_tmem,
                         state->tile_palette_cmt_maskt_shiftt,
                         state->cms_masks_shifts, engine->result.state.state_generation,
                         0u, 0u, 0u };
    return ge_gbi_emit_event(engine, GE_SOURCE_GBI_V6_EVENT_TEXTURE,
                             opcode, 0u, offset, args)
        ? GE_STATUS_OK : GE_STATUS_REPLAY_BUDGET;
}

static GEStatusV1 ge_gbi_tile_load(GEGBIEngineV6 *engine,
                                   uint32_t opcode,
                                   uint32_t offset,
                                   uint32_t w0,
                                   uint32_t w1,
                                   uint32_t require_image)
{
    uint32_t tile = (w1 >> 24) & 7u;
    if (tile >= GE_SOURCE_GBI_V6_MAX_TILES ||
        (require_image != 0u && engine->result.state.texture_image_handle == 0u)) {
        return ge_gbi_fail(engine, GE_STATUS_TEXTURE_OVERFLOW,
                           GE_SOURCE_GBI_V6_DIAG_TEXTURE,
                           opcode, offset, tile,
                           engine->result.state.texture_image_handle);
    }
    GEGBITileStateV6 *state = &engine->result.state.tiles[tile];
    state->uls_ult_lrs_lrt = ((w0 & 0x00ffffffu) << 8) | ((w1 >> 12) & 0xfffu);
    if (require_image != 0u) {
        state->image_handle = engine->result.state.texture_image_handle;
        state->loaded = 1u;
    }
    ge_gbi_touch_state(engine);
    uint32_t args[8] = { tile, state->uls_ult_lrs_lrt,
                         state->image_handle, opcode,
                         engine->result.state.state_generation, 0u, 0u, 0u };
    return ge_gbi_emit_event(engine, GE_SOURCE_GBI_V6_EVENT_TEXTURE,
                             opcode, 0u, offset, args)
        ? GE_STATUS_OK : GE_STATUS_REPLAY_BUDGET;
}

static GEStatusV1 ge_gbi_load_tlut(GEGBIEngineV6 *engine,
                                   uint32_t opcode,
                                   uint32_t offset,
                                   uint32_t w1)
{
    uint32_t tile = (w1 >> 24) & 7u;
    uint32_t count = (w1 >> 14) & 0x3ffu;
    if (tile >= GE_SOURCE_GBI_V6_MAX_TILES ||
        engine->result.state.texture_image_handle == 0u) {
        return ge_gbi_fail(engine, GE_STATUS_TLUT_OVERFLOW,
                           GE_SOURCE_GBI_V6_DIAG_TEXTURE,
                           opcode, offset, tile,
                           engine->result.state.texture_image_handle);
    }
    engine->result.state.tiles[tile].image_handle =
        engine->result.state.texture_image_handle;
    engine->result.state.tiles[tile].loaded = 1u;
    ge_gbi_touch_state(engine);
    uint32_t args[8] = { tile, count, engine->result.state.texture_image_handle,
                         engine->result.state.state_generation, 0u, 0u, 0u, 0u };
    return ge_gbi_emit_event(engine, GE_SOURCE_GBI_V6_EVENT_TEXTURE,
                             opcode, 0u, offset, args)
        ? GE_STATUS_OK : GE_STATUS_REPLAY_BUDGET;
}

static GEStatusV1 ge_gbi_scissor(GEGBIEngineV6 *engine,
                                  uint32_t opcode,
                                  uint32_t offset,
                                  uint32_t w0,
                                  uint32_t w1)
{
    engine->result.state.scissor_ulx_uly = w0 & 0x00ffffffu;
    engine->result.state.scissor_lrx_lry = w1 & 0x00ffffffu;
    engine->result.state.scissor_mode = (w1 >> 24) & 3u;
    ge_gbi_touch_state(engine);
    uint32_t args[8] = { engine->result.state.scissor_ulx_uly,
                         engine->result.state.scissor_lrx_lry,
                         engine->result.state.scissor_mode,
                         engine->result.state.state_generation, 0u, 0u, 0u, 0u };
    return ge_gbi_emit_event(engine, GE_SOURCE_GBI_V6_EVENT_RASTER,
                             opcode, 0u, offset, args)
        ? GE_STATUS_OK : GE_STATUS_REPLAY_BUDGET;
}

static GEStatusV1 ge_gbi_texrect(GEGBIEngineV6 *engine,
                                 uint32_t opcode,
                                 uint32_t offset,
                                 uint32_t w0,
                                 uint32_t w1)
{
    uint32_t tile = (w1 >> 24) & 7u;
    if (tile >= GE_SOURCE_GBI_V6_MAX_TILES) {
        return ge_gbi_fail(engine, GE_STATUS_TEXTURE_FORMAT,
                           GE_SOURCE_GBI_V6_DIAG_TEXTURE,
                           opcode, offset, tile, 0u);
    }
    engine->pending_texrect_halves = 2u;
    uint32_t args[8] = { (w0 >> 12) & 0xfffu, w0 & 0xfffu,
                         (w1 >> 12) & 0xfffu, w1 & 0xfffu,
                         tile, opcode == GE_SOURCE_GBI_V6_OP_TEXRECTFLIP,
                         engine->result.state.texture_image_handle, 0u };
    return ge_gbi_emit_event(engine, GE_SOURCE_GBI_V6_EVENT_RASTER,
                             opcode, 0u, offset, args)
        ? GE_STATUS_OK : GE_STATUS_REPLAY_BUDGET;
}

static GEGBICommandKindV6 ge_gbi_command_kind(const GEGBIEngineV6 *engine,
                                               uint32_t opcode)
{
    if (engine->packet->dialect == GE_SOURCE_GBI_V6_DIALECT_F3DEX2) {
        switch (opcode) {
        case GE_SOURCE_GBI_V6_OP_NOOP: return GEGBI_KIND_NOOP;
        case GE_SOURCE_GBI_V6_OP_MTX_2: return GEGBI_KIND_MTX;
        case GE_SOURCE_GBI_V6_OP_MOVEMEM_2: return GEGBI_KIND_MOVEMEM;
        case GE_SOURCE_GBI_V6_OP_VTX_2: return GEGBI_KIND_VTX;
        case GE_SOURCE_GBI_V6_OP_DL_2: return GEGBI_KIND_DL;
        case GE_SOURCE_GBI_V6_OP_TRI1_2: return GEGBI_KIND_TRI1;
        case GE_SOURCE_GBI_V6_OP_TEXTURE_2: return GEGBI_KIND_TEXTURE;
        case GE_SOURCE_GBI_V6_OP_SETOTHERMODE_L_2: return GEGBI_KIND_SETOTHERMODE_L;
        case GE_SOURCE_GBI_V6_OP_SETOTHERMODE_H_2: return GEGBI_KIND_SETOTHERMODE_H;
        case GE_SOURCE_GBI_V6_OP_MOVEWORD_2: return GEGBI_KIND_MOVEWORD;
        case GE_SOURCE_GBI_V6_OP_POPMTX_2: return GEGBI_KIND_POPMTX;
        case GE_SOURCE_GBI_V6_OP_GEOMETRYMODE_2: return GEGBI_KIND_GEOMETRYMODE;
        case GE_SOURCE_GBI_V6_OP_ENDDL_2: return GEGBI_KIND_ENDDL;
        default: break;
        }
    } else {
        switch (opcode) {
        case GE_SOURCE_GBI_V6_OP_NOOP: return GEGBI_KIND_NOOP;
        case GE_SOURCE_GBI_V6_OP_MTX: return GEGBI_KIND_MTX;
        case GE_SOURCE_GBI_V6_OP_MOVEMEM: return GEGBI_KIND_MOVEMEM;
        case GE_SOURCE_GBI_V6_OP_VTX: return GEGBI_KIND_VTX;
        case GE_SOURCE_GBI_V6_OP_DL: return GEGBI_KIND_DL;
        case GE_SOURCE_GBI_V6_OP_TRI1: return GEGBI_KIND_TRI1;
        case GE_SOURCE_GBI_V6_OP_TRI4: return GEGBI_KIND_TRI4;
        case GE_SOURCE_GBI_V6_OP_TEXTURE: return GEGBI_KIND_TEXTURE;
        case GE_SOURCE_GBI_V6_OP_SETOTHERMODE_L: return GEGBI_KIND_SETOTHERMODE_L;
        case GE_SOURCE_GBI_V6_OP_SETOTHERMODE_H: return GEGBI_KIND_SETOTHERMODE_H;
        case GE_SOURCE_GBI_V6_OP_MOVEWORD: return GEGBI_KIND_MOVEWORD;
        case GE_SOURCE_GBI_V6_OP_POPMTX: return GEGBI_KIND_POPMTX;
        case GE_SOURCE_GBI_V6_OP_CLEARGEOMETRYMODE: return GEGBI_KIND_CLEARGEOMETRYMODE;
        case GE_SOURCE_GBI_V6_OP_SETGEOMETRYMODE: return GEGBI_KIND_SETGEOMETRYMODE;
        case GE_SOURCE_GBI_V6_OP_ENDDL: return GEGBI_KIND_ENDDL;
        default: break;
        }
    }
    switch (opcode) {
    case GE_SOURCE_GBI_V6_OP_SETTEX: return GEGBI_KIND_SETTEX;
    case GE_SOURCE_GBI_V6_OP_SETTIMG: return GEGBI_KIND_SETTIMG;
    case GE_SOURCE_GBI_V6_OP_SETCOMBINE: return GEGBI_KIND_SETCOMBINE;
    case GE_SOURCE_GBI_V6_OP_SETENVCOLOR: return GEGBI_KIND_SETENVCOLOR;
    case GE_SOURCE_GBI_V6_OP_SETPRIMCOLOR: return GEGBI_KIND_SETPRIMCOLOR;
    case GE_SOURCE_GBI_V6_OP_SETBLENDCOLOR: return GEGBI_KIND_SETBLENDCOLOR;
    case GE_SOURCE_GBI_V6_OP_SETFOGCOLOR: return GEGBI_KIND_SETFOGCOLOR;
    case GE_SOURCE_GBI_V6_OP_SETFILLCOLOR: return GEGBI_KIND_SETFILLCOLOR;
    case GE_SOURCE_GBI_V6_OP_FILLRECT: return GEGBI_KIND_FILLRECT;
    case GE_SOURCE_GBI_V6_OP_SETTILE: return GEGBI_KIND_SETTILE;
    case GE_SOURCE_GBI_V6_OP_LOADTILE: return GEGBI_KIND_LOADTILE;
    case GE_SOURCE_GBI_V6_OP_LOADBLOCK: return GEGBI_KIND_LOADBLOCK;
    case GE_SOURCE_GBI_V6_OP_SETTILESIZE: return GEGBI_KIND_SETTILESIZE;
    case GE_SOURCE_GBI_V6_OP_LOADTLUT: return GEGBI_KIND_LOADTLUT;
    case GE_SOURCE_GBI_V6_OP_RDPSETOTHERMODE: return GEGBI_KIND_RDPSETOTHERMODE;
    case GE_SOURCE_GBI_V6_OP_SETSCISSOR: return GEGBI_KIND_SETSCISSOR;
    case GE_SOURCE_GBI_V6_OP_RDPHALF_1: return GEGBI_KIND_RDPHALF_1;
    case GE_SOURCE_GBI_V6_OP_RDPHALF_2: return GEGBI_KIND_RDPHALF_2;
    case GE_SOURCE_GBI_V6_OP_RDPHALF_CONT:
        return engine->packet->dialect == GE_SOURCE_GBI_V6_DIALECT_CLASSIC_GE_F3D
            ? GEGBI_KIND_RDPHALF_CONT : GEGBI_KIND_SETOTHERMODE_L;
    case GE_SOURCE_GBI_V6_OP_RDPFULLSYNC: return GEGBI_KIND_RDPFULLSYNC;
    case GE_SOURCE_GBI_V6_OP_RDPTILESYNC: return GEGBI_KIND_RDPTILESYNC;
    case GE_SOURCE_GBI_V6_OP_RDPPIPESYNC: return GEGBI_KIND_RDPPIPESYNC;
    case GE_SOURCE_GBI_V6_OP_RDPLOADSYNC: return GEGBI_KIND_RDPLOADSYNC;
    case GE_SOURCE_GBI_V6_OP_TEXRECTFLIP: return GEGBI_KIND_TEXRECTFLIP;
    case GE_SOURCE_GBI_V6_OP_TEXRECT: return GEGBI_KIND_TEXRECT;
    case GE_SOURCE_GBI_V6_OP_SETCIMG: return GEGBI_KIND_SETCIMG;
    case GE_SOURCE_GBI_V6_OP_SETZIMG: return GEGBI_KIND_SETZIMG;
    default: return GEGBI_KIND_UNKNOWN;
    }
}

static GEStatusV1 ge_gbi_move_word(GEGBIEngineV6 *engine,
                                   uint32_t f3dex2,
                                   uint32_t opcode,
                                   uint32_t offset,
                                   uint32_t w0,
                                   uint32_t w1)
{
    uint32_t index = f3dex2 != 0u
        ? (w0 >> 16) & 0xffu : w0 & 0xffu;
    uint32_t word_offset = f3dex2 != 0u
        ? (w0 >> 8) & 0xffu : (w0 >> 8) & 0xffu;
    engine->result.state.move_word_index_offset = (index << 8) | word_offset;
    engine->result.state.move_word_value = w1;
    ge_gbi_touch_state(engine);
    uint32_t args[8] = { index, word_offset, w1,
                         engine->result.state.state_generation, 0u, 0u, 0u, 0u };
    return ge_gbi_emit_event(engine, GE_SOURCE_GBI_V6_EVENT_STATE,
                             opcode, 0u, offset, args)
        ? GE_STATUS_OK : GE_STATUS_REPLAY_BUDGET;
}

static GEStatusV1 ge_gbi_set_other_mode(GEGBIEngineV6 *engine,
                                        uint32_t f3dex2,
                                        uint32_t high,
                                        uint32_t opcode,
                                        uint32_t offset,
                                        uint32_t w0,
                                        uint32_t w1)
{
    uint32_t shift_field = (w0 >> 8) & 0xffu;
    uint32_t length_field = w0 & 0xffu;
    uint32_t shift;
    uint32_t length;
    if (f3dex2 != 0u) {
        if (length_field >= 32u || shift_field > 32u - (length_field + 1u)) {
            return ge_gbi_fail(engine, GE_STATUS_MALFORMED_STREAM,
                               GE_SOURCE_GBI_V6_DIAG_ARGUMENT,
                               opcode, offset, shift_field, length_field);
        }
        length = length_field + 1u;
        shift = 32u - shift_field - length;
    } else {
        shift = shift_field;
        length = length_field;
        if (length == 0u || length > 32u || shift >= 32u ||
            length > 32u - shift) {
            return ge_gbi_fail(engine, GE_STATUS_MALFORMED_STREAM,
                               GE_SOURCE_GBI_V6_DIAG_ARGUMENT,
                               opcode, offset, shift, length);
        }
    }
    uint32_t mask = length == 32u
        ? UINT32_MAX : ((UINT32_C(1) << length) - UINT32_C(1)) << shift;
    uint32_t *shadow = high ? &engine->result.state.other_mode_h
                            : &engine->result.state.other_mode_l;
    uint32_t old_value = *shadow;
    *shadow = (old_value & ~mask) | (w1 & mask);
    ge_gbi_touch_state(engine);
    uint32_t args[8] = { high, shift, length, mask, old_value, *shadow,
                         engine->result.state.state_generation, 0u };
    return ge_gbi_emit_event(engine, GE_SOURCE_GBI_V6_EVENT_STATE,
                             opcode, 0u, offset, args)
        ? GE_STATUS_OK : GE_STATUS_REPLAY_BUDGET;
}

static GEStatusV1 ge_gbi_process_command(GEGBIEngineV6 *engine,
                                         GEGBICommandKindV6 kind,
                                         uint32_t opcode,
                                         uint32_t offset,
                                         uint32_t w0,
                                         uint32_t w1)
{
    uint32_t args[8] = { w0, w1, engine->result.state.state_generation,
                         0u, 0u, 0u, 0u, 0u };
    switch (kind) {
    case GEGBI_KIND_NOOP:
        return ge_gbi_emit_event(engine, GE_SOURCE_GBI_V6_EVENT_COMMAND,
                                 opcode, 0u, offset, args)
            ? GE_STATUS_OK : GE_STATUS_REPLAY_BUDGET;
    case GEGBI_KIND_MTX:
        return ge_gbi_matrix(engine,
                             engine->packet->dialect == GE_SOURCE_GBI_V6_DIALECT_F3DEX2,
                             opcode, offset, w0, w1);
    case GEGBI_KIND_POPMTX:
        return ge_gbi_pop_matrix(engine,
                                 engine->packet->dialect == GE_SOURCE_GBI_V6_DIALECT_F3DEX2,
                                 opcode, offset, w0, w1);
    case GEGBI_KIND_MOVEMEM:
        return ge_gbi_viewport(engine,
                               engine->packet->dialect == GE_SOURCE_GBI_V6_DIALECT_F3DEX2,
                               opcode, offset, w0, w1);
    case GEGBI_KIND_VTX:
        return ge_gbi_vertex_load(engine,
                                  engine->packet->dialect == GE_SOURCE_GBI_V6_DIALECT_F3DEX2,
                                  opcode, offset, w0, w1);
    case GEGBI_KIND_TRI1:
        return ge_gbi_emit_tri1(engine,
                                engine->packet->dialect == GE_SOURCE_GBI_V6_DIALECT_F3DEX2,
                                opcode, offset, w0, w1);
    case GEGBI_KIND_TRI4:
        return ge_gbi_emit_tri4(engine, opcode, offset, w0, w1);
    case GEGBI_KIND_SETTEX:
        engine->result.state.texture_state = w0;
        engine->result.state.texture_image_handle = w1 & 0xfffu;
        ge_gbi_touch_state(engine);
        args[2] = engine->result.state.state_generation;
        return ge_gbi_emit_event(engine, GE_SOURCE_GBI_V6_EVENT_TEXTURE,
                                 opcode, 0u, offset, args)
            ? GE_STATUS_OK : GE_STATUS_REPLAY_BUDGET;
    case GEGBI_KIND_TEXTURE:
        return ge_gbi_texture(engine,
                              engine->packet->dialect == GE_SOURCE_GBI_V6_DIALECT_F3DEX2,
                              opcode, offset, w0, w1);
    case GEGBI_KIND_SETTIMG:
        return ge_gbi_settimg(engine, opcode, offset, w0, w1);
    case GEGBI_KIND_SETTILE:
        return ge_gbi_settile(engine, opcode, offset, w0, w1);
    case GEGBI_KIND_LOADBLOCK:
    case GEGBI_KIND_LOADTILE:
        return ge_gbi_tile_load(engine, opcode, offset, w0, w1, 1u);
    case GEGBI_KIND_SETTILESIZE:
        return ge_gbi_tile_load(engine, opcode, offset, w0, w1, 0u);
    case GEGBI_KIND_LOADTLUT:
        return ge_gbi_load_tlut(engine, opcode, offset, w1);
    case GEGBI_KIND_SETCOMBINE:
        engine->result.state.combine_w0 = w0;
        engine->result.state.combine_w1 = w1;
        ge_gbi_touch_state(engine);
        args[2] = engine->result.state.state_generation;
        return ge_gbi_emit_event(engine, GE_SOURCE_GBI_V6_EVENT_STATE,
                                 opcode, 0u, offset, args)
            ? GE_STATUS_OK : GE_STATUS_REPLAY_BUDGET;
    case GEGBI_KIND_SETOTHERMODE_H:
        return ge_gbi_set_other_mode(
            engine,
            engine->packet->dialect == GE_SOURCE_GBI_V6_DIALECT_F3DEX2,
            1u, opcode, offset, w0, w1);
    case GEGBI_KIND_SETOTHERMODE_L:
        return ge_gbi_set_other_mode(
            engine,
            engine->packet->dialect == GE_SOURCE_GBI_V6_DIALECT_F3DEX2,
            0u, opcode, offset, w0, w1);
    case GEGBI_KIND_RDPSETOTHERMODE:
        engine->result.state.other_mode_h = w0 & 0x00ffffffu;
        engine->result.state.other_mode_l = w1;
        ge_gbi_touch_state(engine);
        args[2] = engine->result.state.state_generation;
        return ge_gbi_emit_event(engine, GE_SOURCE_GBI_V6_EVENT_STATE,
                                 opcode, 0u, offset, args)
            ? GE_STATUS_OK : GE_STATUS_REPLAY_BUDGET;
    case GEGBI_KIND_SETGEOMETRYMODE:
        engine->result.state.geometry_mode |= w1;
        ge_gbi_touch_state(engine);
        args[2] = engine->result.state.state_generation;
        return ge_gbi_emit_event(engine, GE_SOURCE_GBI_V6_EVENT_STATE,
                                 opcode, 0u, offset, args)
            ? GE_STATUS_OK : GE_STATUS_REPLAY_BUDGET;
    case GEGBI_KIND_CLEARGEOMETRYMODE:
        engine->result.state.geometry_mode &= ~w1;
        ge_gbi_touch_state(engine);
        args[2] = engine->result.state.state_generation;
        return ge_gbi_emit_event(engine, GE_SOURCE_GBI_V6_EVENT_STATE,
                                 opcode, 0u, offset, args)
            ? GE_STATUS_OK : GE_STATUS_REPLAY_BUDGET;
    case GEGBI_KIND_GEOMETRYMODE:
        engine->result.state.geometry_mode &= ~(~w0 & 0x00ffffffu);
        engine->result.state.geometry_mode |= w1;
        ge_gbi_touch_state(engine);
        args[2] = engine->result.state.state_generation;
        return ge_gbi_emit_event(engine, GE_SOURCE_GBI_V6_EVENT_STATE,
                                 opcode, 0u, offset, args)
            ? GE_STATUS_OK : GE_STATUS_REPLAY_BUDGET;
    case GEGBI_KIND_MOVEWORD:
        return ge_gbi_move_word(engine,
                                engine->packet->dialect == GE_SOURCE_GBI_V6_DIALECT_F3DEX2,
                                opcode, offset, w0, w1);
    case GEGBI_KIND_SETPRIMCOLOR:
        engine->result.state.prim_color = w1;
        ge_gbi_touch_state(engine);
        args[2] = engine->result.state.state_generation;
        return ge_gbi_emit_event(engine, GE_SOURCE_GBI_V6_EVENT_STATE,
                                 opcode, 0u, offset, args)
            ? GE_STATUS_OK : GE_STATUS_REPLAY_BUDGET;
    case GEGBI_KIND_SETENVCOLOR:
        engine->result.state.env_color = w1;
        ge_gbi_touch_state(engine);
        args[2] = engine->result.state.state_generation;
        return ge_gbi_emit_event(engine, GE_SOURCE_GBI_V6_EVENT_STATE,
                                 opcode, 0u, offset, args)
            ? GE_STATUS_OK : GE_STATUS_REPLAY_BUDGET;
    case GEGBI_KIND_SETBLENDCOLOR:
        engine->result.state.blend_color = w1;
        ge_gbi_touch_state(engine);
        args[2] = engine->result.state.state_generation;
        return ge_gbi_emit_event(engine, GE_SOURCE_GBI_V6_EVENT_STATE,
                                 opcode, 0u, offset, args)
            ? GE_STATUS_OK : GE_STATUS_REPLAY_BUDGET;
    case GEGBI_KIND_SETFOGCOLOR:
        engine->result.state.fog_color = w1;
        ge_gbi_touch_state(engine);
        args[2] = engine->result.state.state_generation;
        return ge_gbi_emit_event(engine, GE_SOURCE_GBI_V6_EVENT_STATE,
                                 opcode, 0u, offset, args)
            ? GE_STATUS_OK : GE_STATUS_REPLAY_BUDGET;
    case GEGBI_KIND_SETFILLCOLOR:
        engine->result.state.fill_color = w1;
        ge_gbi_touch_state(engine);
        args[2] = engine->result.state.state_generation;
        return ge_gbi_emit_event(engine, GE_SOURCE_GBI_V6_EVENT_STATE,
                                 opcode, 0u, offset, args)
            ? GE_STATUS_OK : GE_STATUS_REPLAY_BUDGET;
    case GEGBI_KIND_SETSCISSOR:
        return ge_gbi_scissor(engine, opcode, offset, w0, w1);
    case GEGBI_KIND_FILLRECT:
        return ge_gbi_emit_event(engine, GE_SOURCE_GBI_V6_EVENT_RASTER,
                                 opcode, 0u, offset, args)
            ? GE_STATUS_OK : GE_STATUS_REPLAY_BUDGET;
    case GEGBI_KIND_TEXRECT:
    case GEGBI_KIND_TEXRECTFLIP:
        return ge_gbi_texrect(engine, opcode, offset, w0, w1);
    case GEGBI_KIND_RDPHALF_1:
    case GEGBI_KIND_RDPHALF_2:
        engine->result.state.rdp_half_1 = w1;
        if (engine->pending_texrect_halves != 0u) {
            engine->pending_texrect_halves--;
        }
        return ge_gbi_emit_event(engine, GE_SOURCE_GBI_V6_EVENT_RASTER,
                                 opcode, 0u, offset, args)
            ? GE_STATUS_OK : GE_STATUS_REPLAY_BUDGET;
    case GEGBI_KIND_RDPPIPESYNC:
    case GEGBI_KIND_RDPLOADSYNC:
    case GEGBI_KIND_RDPTILESYNC:
    case GEGBI_KIND_RDPFULLSYNC:
        return ge_gbi_emit_event(engine, GE_SOURCE_GBI_V6_EVENT_SYNC,
                                 opcode, 0u, offset, args)
            ? GE_STATUS_OK : GE_STATUS_REPLAY_BUDGET;
    case GEGBI_KIND_SETCIMG:
    case GEGBI_KIND_SETZIMG:
        return ge_gbi_emit_event(engine, GE_SOURCE_GBI_V6_EVENT_TEXTURE,
                                 opcode, 0u, offset, args)
            ? GE_STATUS_OK : GE_STATUS_REPLAY_BUDGET;
    default:
        ge_gbi_unsupported(engine, opcode, offset, w0, w1);
        return GE_STATUS_UNSUPPORTED_COMMAND;
    }
}

static GEStatusV1 ge_gbi_enter_list(GEGBIEngineV6 *engine,
                                    uint32_t opcode,
                                    uint32_t offset,
                                    uint32_t handle,
                                    uint32_t push)
{
    const GEGBISourceListV6 *list = ge_gbi_find_list(engine, handle);
    if (list == NULL) {
        return ge_gbi_fail(engine, GE_STATUS_RESOURCE_NOT_FOUND,
                           GE_SOURCE_GBI_V6_DIAG_RESOURCE,
                           opcode, offset, handle, 0u);
    }
    if (ge_gbi_active_handle(engine, handle)) {
        return ge_gbi_fail(engine, GE_STATUS_REPLAY_CYCLE,
                           GE_SOURCE_GBI_V6_DIAG_CYCLE,
                           opcode, offset, handle, 0u);
    }
    if (list->first_command > engine->packet->command_count ||
        list->command_count > engine->packet->command_count - list->first_command) {
        return ge_gbi_fail(engine, GE_STATUS_MALFORMED_STREAM,
                           GE_SOURCE_GBI_V6_DIAG_TRUNCATED,
                           opcode, offset, list->first_command, list->command_count);
    }
    if (push != 0u) {
        if (engine->frame_depth >= GE_SOURCE_GBI_V6_MAX_LIST_STACK) {
            return ge_gbi_fail(engine, GE_STATUS_REPLAY_DEPTH,
                               GE_SOURCE_GBI_V6_DIAG_STACK,
                               opcode, offset, engine->frame_depth, 0u);
        }
        GEGBIFrameV6 *frame = &engine->frames[engine->frame_depth];
        frame->returns_to_parent = 1u;
        engine->frame_depth++;
        engine->active_handles[engine->frame_depth - 1u] = handle;
        frame->handle = handle;
        frame->next_command = list->first_command;
        frame->end_command = list->first_command + list->command_count;
    } else {
        if (engine->frame_depth == 0u) {
            return ge_gbi_fail(engine, GE_STATUS_INVALID_STATE,
                               GE_SOURCE_GBI_V6_DIAG_STACK,
                               opcode, offset, handle, 0u);
        }
        GEGBIFrameV6 *frame = &engine->frames[engine->frame_depth - 1u];
        frame->handle = handle;
        frame->next_command = list->first_command;
        frame->end_command = list->first_command + list->command_count;
        engine->active_handles[engine->frame_depth - 1u] = handle;
    }
    engine->result.list_enters++;
    uint32_t args[8] = { handle, push, list->first_command, list->command_count,
                         engine->frame_depth, 0u, 0u, 0u };
    if (!ge_gbi_emit_event(engine, GE_SOURCE_GBI_V6_EVENT_LIST_ENTER,
                           opcode, push, offset, args)) {
        return GE_STATUS_REPLAY_BUDGET;
    }
    if (engine->frame_depth > engine->result.max_list_depth) {
        engine->result.max_list_depth = engine->frame_depth;
    }
    return GE_STATUS_OK;
}

static GEStatusV1 ge_gbi_validate_packet(const GEGBISourcePacketV6 *packet,
                                         GEGBIResultV6 *result)
{
    if (packet->header.abi_version != GE_NATIVE_ABI_VERSION) {
        result->status = GE_STATUS_INVALID_VERSION;
        return result->status;
    }
    if (packet->header.struct_size != (uint32_t)sizeof(*packet)) {
        result->status = GE_STATUS_INVALID_SIZE;
        return result->status;
    }
    if (packet->packet_version != GE_SOURCE_GBI_V6_PACKET_VERSION) {
        result->status = GE_STATUS_INVALID_VERSION;
        return result->status;
    }
    if (packet->dialect != GE_SOURCE_GBI_V6_DIALECT_CLASSIC_GE_F3D &&
        packet->dialect != GE_SOURCE_GBI_V6_DIALECT_F3DEX2) {
        result->status = GE_STATUS_INVALID_ARGUMENT;
        return result->status;
    }
    if (packet->reserved0[0] != 0u || packet->reserved0[1] != 0u) {
        result->status = GE_STATUS_RESERVED_BITS;
        return result->status;
    }
    if (packet->command_count == 0u || packet->command_count > GE_SOURCE_GBI_V6_MAX_COMMANDS ||
        packet->list_count == 0u || packet->list_count > GE_SOURCE_GBI_V6_MAX_LISTS ||
        packet->vertex_count > GE_SOURCE_GBI_V6_MAX_VERTICES ||
        packet->vertex_resource_count > GE_SOURCE_GBI_V6_MAX_VERTEX_RESOURCES ||
        packet->matrix_count > GE_SOURCE_GBI_V6_MAX_MATRICES ||
        packet->viewport_count > GE_SOURCE_GBI_V6_MAX_VIEWPORTS ||
        packet->image_count > GE_SOURCE_GBI_V6_MAX_IMAGES) {
        result->status = GE_STATUS_MALFORMED_STREAM;
        return result->status;
    }
    for (uint32_t index = 0; index < packet->list_count; index++) {
        const GEGBISourceListV6 *list = &packet->lists[index];
        if (list->handle == 0u || list->flags != 0u ||
            list->first_command > packet->command_count ||
            list->command_count > packet->command_count - list->first_command) {
            result->status = GE_STATUS_MALFORMED_STREAM;
            return result->status;
        }
        for (uint32_t other = 0; other < index; other++) {
            if (packet->lists[other].handle == list->handle) {
                result->status = GE_STATUS_MALFORMED_STREAM;
                return result->status;
            }
        }
    }
    for (uint32_t index = 0; index < packet->vertex_resource_count; index++) {
        const GEGBISourceVertexResourceV6 *resource = &packet->vertex_resources[index];
        if (resource->handle == 0u ||
            (resource->flags & ~GE_SOURCE_GBI_V6_VERTEX_RESOURCE_FLAG_MASK) != 0u ||
            resource->first_vertex > packet->vertex_count ||
            resource->vertex_count > packet->vertex_count - resource->first_vertex) {
            result->status = GE_STATUS_MALFORMED_STREAM;
            return result->status;
        }
        for (uint32_t other = 0; other < index; other++) {
            if (packet->vertex_resources[other].handle == resource->handle) {
                result->status = GE_STATUS_MALFORMED_STREAM;
                return result->status;
            }
        }
    }
    for (uint32_t index = 0; index < packet->matrix_count; index++) {
        if (packet->matrices[index].handle == 0u) {
            result->status = GE_STATUS_MALFORMED_STREAM;
            return result->status;
        }
        for (uint32_t other = 0; other < index; other++) {
            if (packet->matrices[other].handle == packet->matrices[index].handle) {
                result->status = GE_STATUS_MALFORMED_STREAM;
                return result->status;
            }
        }
    }
    for (uint32_t index = 0; index < packet->viewport_count; index++) {
        if (packet->viewports[index].handle == 0u || packet->viewports[index].flags != 0u) {
            result->status = GE_STATUS_MALFORMED_STREAM;
            return result->status;
        }
    }
    for (uint32_t index = 0; index < packet->image_count; index++) {
        if (packet->images[index].handle == 0u || packet->images[index].reserved != 0u) {
            result->status = GE_STATUS_MALFORMED_STREAM;
            return result->status;
        }
    }
    return GE_STATUS_OK;
}

static GEStatusV1 ge_gbi_validate_vertex_resource_table(
    const GEGBIEngineV6 *engine)
{
    const GEGBISourcePacketV6 *packet = engine->packet;
    uint32_t base_count = packet->vertex_resource_count;
    uint32_t total_count = base_count;
    if (engine->vertex_page_count != 0u) {
        if (engine->vertex_pages == NULL ||
            engine->vertex_page_count > GE_SOURCE_GBI_V6_MAX_VERTEX_RESOURCE_PAGES) {
            return GE_STATUS_INVALID_ARGUMENT;
        }
        total_count = engine->vertex_pages[0].total_items;
        if (total_count < base_count ||
            total_count > GE_SOURCE_GBI_V6_MAX_VERTEX_RESOURCE_TOTAL) {
            return GE_STATUS_MALFORMED_STREAM;
        }
        uint32_t sidecar_items = total_count - base_count;
        uint32_t expected_pages =
            (sidecar_items + GE_SOURCE_GBI_V6_VERTEX_RESOURCE_PAGE_CAPACITY - 1u) /
            GE_SOURCE_GBI_V6_VERTEX_RESOURCE_PAGE_CAPACITY;
        if (expected_pages != engine->vertex_page_count) {
            return GE_STATUS_MALFORMED_STREAM;
        }
        for (uint32_t page_index = 0u;
             page_index < engine->vertex_page_count; page_index++) {
            const GEGBISourceVertexResourcePageV6 *page =
                &engine->vertex_pages[page_index];
            GEStatusV1 status = ge_source_gbi_v6_validate_vertex_resource_page(page);
            if (status != GE_STATUS_OK) {
                return status;
            }
            uint32_t expected_first = base_count +
                page_index * GE_SOURCE_GBI_V6_VERTEX_RESOURCE_PAGE_CAPACITY;
            uint32_t expected_count = total_count - expected_first;
            if (expected_count > GE_SOURCE_GBI_V6_VERTEX_RESOURCE_PAGE_CAPACITY) {
                expected_count = GE_SOURCE_GBI_V6_VERTEX_RESOURCE_PAGE_CAPACITY;
            }
            if (page->page_index != page_index ||
                page->first_item != expected_first ||
                page->item_count != expected_count ||
                page->total_items != total_count) {
                return GE_STATUS_MALFORMED_STREAM;
            }
            if (page_index != 0u &&
                page->manifest_hash != engine->vertex_pages[0].manifest_hash) {
                return GE_STATUS_ASSET_MISMATCH;
            }
        }
        uint64_t manifest = ge_source_gbi_v6_hash_vertex_resource_manifest(
            packet->vertex_resources, base_count,
            engine->vertex_pages, engine->vertex_page_count);
        if (manifest == 0u ||
            manifest != engine->vertex_pages[0].manifest_hash) {
            return GE_STATUS_ASSET_MISMATCH;
        }
    }
    if (total_count > GE_SOURCE_GBI_V6_MAX_VERTEX_RESOURCE_TOTAL) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    for (uint32_t index = 0u; index < base_count; index++) {
        const GEGBISourceVertexResourceV6 *item = &packet->vertex_resources[index];
        if (ge_gbi_validate_vertex_resource_value(item) != GE_STATUS_OK ||
            item->first_vertex > packet->vertex_count ||
            item->vertex_count > packet->vertex_count - item->first_vertex) {
            return GE_STATUS_VERTEX_OUT_OF_RANGE;
        }
        for (uint32_t other = 0u; other < index; other++) {
            const GEGBISourceVertexResourceV6 *prior =
                &packet->vertex_resources[other];
            if (prior->handle == item->handle) {
                return GE_STATUS_MALFORMED_STREAM;
            }
        }
    }
    for (uint32_t page_index = 0u;
         page_index < engine->vertex_page_count; page_index++) {
        const GEGBISourceVertexResourcePageV6 *page =
            &engine->vertex_pages[page_index];
        for (uint32_t index = 0u; index < page->item_count; index++) {
            const GEGBISourceVertexResourceV6 *item = &page->items[index];
            if (item->first_vertex > packet->vertex_count ||
                item->vertex_count > packet->vertex_count - item->first_vertex) {
                return GE_STATUS_VERTEX_OUT_OF_RANGE;
            }
            for (uint32_t other = 0u; other < base_count; other++) {
                const GEGBISourceVertexResourceV6 *prior =
                    &packet->vertex_resources[other];
                if (prior->handle == item->handle) {
                    return GE_STATUS_MALFORMED_STREAM;
                }
            }
            for (uint32_t prior_page = 0u; prior_page <= page_index; prior_page++) {
                const GEGBISourceVertexResourcePageV6 *prior =
                    &engine->vertex_pages[prior_page];
                uint32_t prior_count = prior_page == page_index ? index : prior->item_count;
                for (uint32_t prior_index = 0u; prior_index < prior_count; prior_index++) {
                    const GEGBISourceVertexResourceV6 *other =
                        &prior->items[prior_index];
                    if (other->handle == item->handle) {
                        return GE_STATUS_MALFORMED_STREAM;
                    }
                }
            }
        }
    }
    return GE_STATUS_OK;
}

static GEStatusV1 ge_source_gbi_decode_v6_core(const GEGBISourcePacketV6 *packet,
                                               const GEGBISourceVertexResourcePageV6 *pages,
                                               uint32_t page_count,
                                               GEGBIResultV6 *output,
                                               GEGBIVertexLoadProvenanceV6 *vertex_load_provenance,
                                               uint32_t vertex_load_provenance_capacity,
                                               uint32_t *vertex_load_provenance_count)
{
    if (packet == NULL || output == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    GEGBIEngineV6 *engine = (GEGBIEngineV6 *)calloc(1u, sizeof(*engine));
    if (engine == NULL) {
        ge_gbi_init_result(output);
        output->status = GE_STATUS_INTERNAL_ERROR;
        return output->status;
    }
    ge_gbi_init_result(&engine->result);
    engine->packet = packet;
    engine->vertex_pages = pages;
    engine->vertex_page_count = page_count;
    engine->vertex_load_provenance = vertex_load_provenance;
    engine->vertex_load_provenance_capacity = vertex_load_provenance_capacity;
    engine->vertex_load_provenance_count = 0u;
    engine->modelview_provenance_flags =
        GE_SOURCE_GBI_V6_VERTEX_LOAD_PROVENANCE_FLAG_MATRIX_LOAD_ONLY;
    if (vertex_load_provenance_count != NULL) {
        *vertex_load_provenance_count = 0u;
    }
    GEStatusV1 status = ge_gbi_validate_packet(packet, &engine->result);
    if (status != GE_STATUS_OK) {
        *output = engine->result;
        free(engine);
        return status;
    }
    status = ge_gbi_validate_vertex_resource_table(engine);
    if (status != GE_STATUS_OK) {
        engine->result.status = status;
        *output = engine->result;
        free(engine);
        return status;
    }
    const GEGBISourceListV6 *root = ge_gbi_find_list(engine, packet->root_list_handle);
    if (root == NULL) {
        engine->result.status = GE_STATUS_RESOURCE_NOT_FOUND;
        engine->result.error_opcode = GE_SOURCE_GBI_V6_OP_DL;
        status = engine->result.status;
        *output = engine->result;
        free(engine);
        return status;
    }
    if (root->first_command > packet->command_count ||
        root->command_count > packet->command_count - root->first_command) {
        engine->result.status = GE_STATUS_MALFORMED_STREAM;
        status = engine->result.status;
        *output = engine->result;
        free(engine);
        return status;
    }
    engine->frames[0].handle = root->handle;
    engine->frames[0].next_command = root->first_command;
    engine->frames[0].end_command = root->first_command + root->command_count;
    engine->frames[0].returns_to_parent = 0u;
    engine->active_handles[0] = root->handle;
    engine->frame_depth = 1u;
    engine->result.max_list_depth = 1u;
    engine->modelview_depth = 1u;
    engine->projection_depth = 1u;
    engine->event_hash = GEGBI_V6_DEFAULT_HASH;
    engine->result.state.state_hash = ge_gbi_state_hash(&engine->result.state);

    while (engine->frame_depth != 0u) {
        GEGBIFrameV6 *frame = &engine->frames[engine->frame_depth - 1u];
        if (frame->next_command >= frame->end_command) {
            /* Every source list must explicitly terminate with ENDDL. */
            ge_gbi_fail(engine, GE_STATUS_MALFORMED_STREAM,
                        GE_SOURCE_GBI_V6_DIAG_TRUNCATED, 0u,
                        frame->next_command * 8u, frame->handle, frame->end_command);
            break;
        }
        uint32_t command_index = frame->next_command++;
        const GEGBISourceCommandV6 command = packet->commands[command_index];
        uint32_t offset = command_index * (uint32_t)sizeof(command);
        uint32_t opcode = command.w0 >> 24;
        GEGBICommandKindV6 kind = ge_gbi_command_kind(engine, opcode);
        engine->result.commands_processed++;
        engine->event_hash = ge_gbi_hash_u32(engine->event_hash, command.w0);
        engine->event_hash = ge_gbi_hash_u32(engine->event_hash, command.w1);

        if (kind == GEGBI_KIND_DL) {
            /* G_DL_PUSH is encoded as zero; G_DL_NOPUSH as one. */
            uint32_t mode = (command.w0 >> 16) & 0xffu;
            if (packet->dialect == GE_SOURCE_GBI_V6_DIALECT_F3DEX2 && mode == 0u) {
                mode = command.w0 & 1u;
            }
            status = ge_gbi_enter_list(engine, opcode, offset,
                                       command.w1, mode == 0u ? 1u : 0u);
        } else if (kind == GEGBI_KIND_ENDDL) {
            uint32_t args[8] = { frame->handle, frame->returns_to_parent,
                                 engine->frame_depth, 0u, 0u, 0u, 0u, 0u };
            if (!ge_gbi_emit_event(engine, GE_SOURCE_GBI_V6_EVENT_LIST_RETURN,
                                   opcode, 0u, offset, args)) {
                status = GE_STATUS_REPLAY_BUDGET;
                break;
            }
            engine->result.list_returns++;
            if (frame->returns_to_parent != 0u) {
                engine->frame_depth--;
            } else {
                engine->root_ended = 1u;
                engine->frame_depth = 0u;
            }
            status = GE_STATUS_OK;
        } else if (kind == GEGBI_KIND_RDPHALF_CONT &&
                   engine->pending_texrect_halves != 0u) {
            engine->result.state.rdp_half_2 = command.w1;
            engine->pending_texrect_halves--;
            uint32_t args[8] = { command.w0, command.w1,
                                 engine->result.state.state_generation,
                                 0u, 0u, 0u, 0u, 0u };
            status = ge_gbi_emit_event(engine, GE_SOURCE_GBI_V6_EVENT_RASTER,
                                       opcode, 0u, offset, args)
                ? GE_STATUS_OK : GE_STATUS_REPLAY_BUDGET;
        } else {
            status = ge_gbi_process_command(engine, kind, opcode, offset,
                                            command.w0, command.w1);
        }
        if (status != GE_STATUS_OK && status != GE_STATUS_UNSUPPORTED_COMMAND) {
            break;
        }
    }
    if (!engine->root_ended && engine->result.status == GE_STATUS_OK) {
        ge_gbi_first_error(engine, GE_STATUS_MALFORMED_STREAM,
                           GE_SOURCE_GBI_V6_OP_ENDDL,
                           engine->result.commands_processed * 8u);
    }
    if (engine->saw_unsupported && engine->result.status == GE_STATUS_OK) {
        ge_gbi_first_error(engine, GE_STATUS_UNSUPPORTED_COMMAND,
                           0u, 0u);
    }
    engine->result.event_hash = engine->event_hash;
    engine->result.state_hash = engine->result.state.state_hash;
    *output = engine->result;
    if (vertex_load_provenance_count != NULL) {
        *vertex_load_provenance_count = engine->vertex_load_provenance_count;
    }
    status = engine->result.status;
    free(engine);
    return status;
}

GEGBIResultV6 ge_source_gbi_decode_v6(GEGBISourcePacketV6 packet)
{
    (void)ge_source_gbi_decode_v6_core(
        &packet, NULL, 0u, &ge_gbi_return_buffer, NULL, 0u, NULL);
    return ge_gbi_return_buffer;
}

GEStatusV1 ge_source_gbi_decode_v6_into(const GEGBISourcePacketV6 *packet,
                                        GEGBIResultV6 *result)
{
    return ge_source_gbi_decode_v6_core(
        packet, NULL, 0u, result, NULL, 0u, NULL);
}

GEStatusV1 ge_source_gbi_decode_v6_into_with_vertex_pages(
    const GEGBISourcePacketV6 *packet,
    const GEGBISourceVertexResourcePageV6 *pages,
    uint32_t page_count,
    GEGBIResultV6 *result)
{
    return ge_source_gbi_decode_v6_core(
        packet, pages, page_count, result, NULL, 0u, NULL);
}

GEStatusV1 ge_source_gbi_decode_v6_into_with_vertex_pages_and_provenance(
    const GEGBISourcePacketV6 *packet,
    const GEGBISourceVertexResourcePageV6 *pages,
    uint32_t page_count,
    GEGBIResultV6 *result,
    GEGBIVertexLoadProvenanceV6 *out_values,
    uint32_t out_capacity,
    uint32_t *out_count)
{
    if (out_count == NULL || (out_capacity != 0u && out_values == NULL)) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    return ge_source_gbi_decode_v6_core(
        packet, pages, page_count, result,
        out_values, out_capacity, out_count);
}

GEStatusV1 ge_source_gbi_v6_build_vertex_load_provenance(
    const GEGBISourcePacketV6 *packet,
    const GEGBISourceVertexResourcePageV6 *pages,
    uint32_t page_count,
    GEGBIVertexLoadProvenanceV6 *out_values,
    uint32_t out_capacity,
    uint32_t *out_count)
{
    if (out_count == NULL || (out_capacity != 0u && out_values == NULL)) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    *out_count = 0u;
    GEGBIResultV6 result;
    GEStatusV1 status = ge_source_gbi_decode_v6_core(
        packet, pages, page_count, &result,
        out_values, out_capacity, out_count);
    return status;
}
