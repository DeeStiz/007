#ifndef GE_SOURCE_GBI_V6_H
#define GE_SOURCE_GBI_V6_H

/*
 * Additive, value-only source GBI contract for native GoldenEye lowering.
 *
 * The command words intentionally retain the two 32-bit words emitted by
 * the source F3D/F3DEX display-list producers.  Every value which would be
 * a segmented address or a host pointer in the original code is represented
 * here by a caller-assigned deterministic handle.  This contract describes
 * GBI semantics; it is not an RSP/RDP or ROM emulator.
 */

#include <stdint.h>

#include "ge_native_foundation.h"

#define GE_SOURCE_GBI_V6_CONTRACT_VERSION ((uint32_t)6u)
#define GE_SOURCE_GBI_V6_PACKET_VERSION ((uint32_t)1u)

/* Production GoldenEye packets select classic GE/F3D.  F3DEX2 is an
   additive fixture dialect for independent decoder coverage only. */
#define GE_SOURCE_GBI_V6_DIALECT_CLASSIC_GE_F3D ((uint32_t)1u)
#define GE_SOURCE_GBI_V6_DIALECT_F3DEX2 ((uint32_t)2u)

#define GE_SOURCE_GBI_V6_MAX_COMMANDS ((uint32_t)2048u)
#define GE_SOURCE_GBI_V6_MAX_LISTS ((uint32_t)64u)
#define GE_SOURCE_GBI_V6_MAX_VERTICES ((uint32_t)2048u)
#define GE_SOURCE_GBI_V6_MAX_VERTEX_RESOURCES ((uint32_t)64u)
#define GE_SOURCE_GBI_V6_VERTEX_RESOURCE_PAGE_CAPACITY ((uint32_t)64u)
#define GE_SOURCE_GBI_V6_MAX_VERTEX_RESOURCE_TOTAL ((uint32_t)256u)
#define GE_SOURCE_GBI_V6_MAX_VERTEX_RESOURCE_PAGES ((uint32_t)4u)
#define GE_SOURCE_GBI_V6_MAX_MATRICES ((uint32_t)64u)
#define GE_SOURCE_GBI_V6_MAX_VIEWPORTS ((uint32_t)16u)
#define GE_SOURCE_GBI_V6_MAX_IMAGES ((uint32_t)128u)
#define GE_SOURCE_GBI_V6_MAX_TILES ((uint32_t)8u)
#define GE_SOURCE_GBI_V6_MAX_VERTEX_CACHE ((uint32_t)64u)
#define GE_SOURCE_GBI_V6_MAX_MATRIX_STACK ((uint32_t)32u)
#define GE_SOURCE_GBI_V6_MAX_LIST_STACK ((uint32_t)32u)
#define GE_SOURCE_GBI_V6_MAX_EVENTS ((uint32_t)4096u)
#define GE_SOURCE_GBI_V6_MAX_DRAWS ((uint32_t)2048u)
#define GE_SOURCE_GBI_V6_MAX_STATES ((uint32_t)2048u)
#define GE_SOURCE_GBI_V6_MAX_VERTEX_LOAD_PROVENANCE ((uint32_t)2048u)
#define GE_SOURCE_GBI_V6_MAX_DIAGNOSTICS ((uint32_t)64u)

/* A repeated source vertex window may deliberately alias the same copied
   vertex range under a distinct packet handle. The flag is required for the
   additive exact-range alias rule; ordinary overlapping resources still
   fail closed. */
#define GE_SOURCE_GBI_V6_VERTEX_RESOURCE_FLAG_EXACT_ALIAS ((uint32_t)1u)
#define GE_SOURCE_GBI_V6_VERTEX_RESOURCE_FLAG_MASK ((uint32_t)1u)
#define GE_SOURCE_GBI_V6_VERTEX_LOAD_PROVENANCE_FLAG_SOURCE_ORDERED ((uint32_t)1u)
#define GE_SOURCE_GBI_V6_VERTEX_LOAD_PROVENANCE_FLAG_MATRIX_LOAD_ONLY ((uint32_t)1u << 1)

/* F3D/F3DEX (old GE) opcodes. */
#define GE_SOURCE_GBI_V6_OP_NOOP ((uint32_t)0x00u)
#define GE_SOURCE_GBI_V6_OP_MTX ((uint32_t)0x01u)
#define GE_SOURCE_GBI_V6_OP_MOVEMEM ((uint32_t)0x03u)
#define GE_SOURCE_GBI_V6_OP_VTX ((uint32_t)0x04u)
#define GE_SOURCE_GBI_V6_OP_DL ((uint32_t)0x06u)
#define GE_SOURCE_GBI_V6_OP_TRI1 ((uint32_t)0xbfu)
#define GE_SOURCE_GBI_V6_OP_TRI4 ((uint32_t)0xb1u)
#define GE_SOURCE_GBI_V6_OP_TEXTURE ((uint32_t)0xbbu)
#define GE_SOURCE_GBI_V6_OP_SETOTHERMODE_L ((uint32_t)0xb9u)
#define GE_SOURCE_GBI_V6_OP_SETOTHERMODE_H ((uint32_t)0xbau)
#define GE_SOURCE_GBI_V6_OP_MOVEWORD ((uint32_t)0xbcu)
#define GE_SOURCE_GBI_V6_OP_POPMTX ((uint32_t)0xbdu)
#define GE_SOURCE_GBI_V6_OP_SETTEX ((uint32_t)0xc0u)
#define GE_SOURCE_GBI_V6_OP_CLEARGEOMETRYMODE ((uint32_t)0xb6u)
#define GE_SOURCE_GBI_V6_OP_SETGEOMETRYMODE ((uint32_t)0xb7u)
#define GE_SOURCE_GBI_V6_OP_ENDDL ((uint32_t)0xb8u)

/* F3DEX2 aliases used by newer source display-list producers. */
#define GE_SOURCE_GBI_V6_OP_MTX_2 ((uint32_t)0xdau)
#define GE_SOURCE_GBI_V6_OP_MOVEMEM_2 ((uint32_t)0xdcu)
#define GE_SOURCE_GBI_V6_OP_VTX_2 ((uint32_t)0x01u)
#define GE_SOURCE_GBI_V6_OP_DL_2 ((uint32_t)0xdeu)
#define GE_SOURCE_GBI_V6_OP_TRI1_2 ((uint32_t)0x05u)
#define GE_SOURCE_GBI_V6_OP_TEXTURE_2 ((uint32_t)0xd7u)
#define GE_SOURCE_GBI_V6_OP_SETOTHERMODE_L_2 ((uint32_t)0xe2u)
#define GE_SOURCE_GBI_V6_OP_SETOTHERMODE_H_2 ((uint32_t)0xe3u)
#define GE_SOURCE_GBI_V6_OP_MOVEWORD_2 ((uint32_t)0xdbu)
#define GE_SOURCE_GBI_V6_OP_POPMTX_2 ((uint32_t)0xd8u)
#define GE_SOURCE_GBI_V6_OP_GEOMETRYMODE_2 ((uint32_t)0xd9u)
#define GE_SOURCE_GBI_V6_OP_ENDDL_2 ((uint32_t)0xdfu)

/* RDP commands common to F3D and F3DEX2. */
#define GE_SOURCE_GBI_V6_OP_SETCIMG ((uint32_t)0xffu)
#define GE_SOURCE_GBI_V6_OP_SETZIMG ((uint32_t)0xfeu)
#define GE_SOURCE_GBI_V6_OP_SETTIMG ((uint32_t)0xfdu)
#define GE_SOURCE_GBI_V6_OP_SETCOMBINE ((uint32_t)0xfcu)
#define GE_SOURCE_GBI_V6_OP_SETENVCOLOR ((uint32_t)0xfbu)
#define GE_SOURCE_GBI_V6_OP_SETPRIMCOLOR ((uint32_t)0xfau)
#define GE_SOURCE_GBI_V6_OP_SETBLENDCOLOR ((uint32_t)0xf9u)
#define GE_SOURCE_GBI_V6_OP_SETFOGCOLOR ((uint32_t)0xf8u)
#define GE_SOURCE_GBI_V6_OP_SETFILLCOLOR ((uint32_t)0xf7u)
#define GE_SOURCE_GBI_V6_OP_FILLRECT ((uint32_t)0xf6u)
#define GE_SOURCE_GBI_V6_OP_SETTILE ((uint32_t)0xf5u)
#define GE_SOURCE_GBI_V6_OP_LOADTILE ((uint32_t)0xf4u)
#define GE_SOURCE_GBI_V6_OP_LOADBLOCK ((uint32_t)0xf3u)
#define GE_SOURCE_GBI_V6_OP_SETTILESIZE ((uint32_t)0xf2u)
#define GE_SOURCE_GBI_V6_OP_LOADTLUT ((uint32_t)0xf0u)
#define GE_SOURCE_GBI_V6_OP_RDPSETOTHERMODE ((uint32_t)0xefu)
#define GE_SOURCE_GBI_V6_OP_SETSCISSOR ((uint32_t)0xedu)
#define GE_SOURCE_GBI_V6_OP_RDPHALF_1 ((uint32_t)0xe1u)
#define GE_SOURCE_GBI_V6_OP_RDPHALF_2 ((uint32_t)0xf1u)
#define GE_SOURCE_GBI_V6_OP_RDPHALF_CONT ((uint32_t)0xe2u)
#define GE_SOURCE_GBI_V6_OP_RDPFULLSYNC ((uint32_t)0xe9u)
#define GE_SOURCE_GBI_V6_OP_RDPTILESYNC ((uint32_t)0xe8u)
#define GE_SOURCE_GBI_V6_OP_RDPPIPESYNC ((uint32_t)0xe7u)
#define GE_SOURCE_GBI_V6_OP_RDPLOADSYNC ((uint32_t)0xe6u)
#define GE_SOURCE_GBI_V6_OP_TEXRECTFLIP ((uint32_t)0xe5u)
#define GE_SOURCE_GBI_V6_OP_TEXRECT ((uint32_t)0xe4u)

/* Compact GE extensions from gbi_extension.h. */
#define GE_SOURCE_GBI_V6_OP_G_SETTEX ((uint32_t)0xc0u)

typedef struct GEGBISourceCommandV6 {
    uint32_t w0;
    uint32_t w1;
} GEGBISourceCommandV6;

typedef struct GEGBISourceListV6 {
    uint32_t handle;
    uint32_t first_command;
    uint32_t command_count;
    uint32_t flags;
} GEGBISourceListV6;

typedef struct GEGBISourceVertexResourceV6 {
    uint32_t handle;
    uint32_t first_vertex;
    uint32_t vertex_count;
    uint32_t flags;
} GEGBISourceVertexResourceV6;

/*
 * Additive vertex-resource continuation page.  The packet's existing
 * vertex_resources[64] remains the base page and is never resized.  A page
 * contains copied descriptors only; page pointers are accepted by the
 * decoder at call time and are never retained.
 */
typedef struct GEGBISourceVertexResourcePageV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t page_index;
    uint32_t item_count;
    uint32_t total_items;
    uint32_t page_capacity;
    uint32_t first_item;
    uint32_t reserved0;
    uint32_t reserved1;
    uint64_t page_hash;
    uint64_t manifest_hash;
    GEGBISourceVertexResourceV6 items[GE_SOURCE_GBI_V6_VERTEX_RESOURCE_PAGE_CAPACITY];
} GEGBISourceVertexResourcePageV6;

typedef struct GEGBISourceMatrixResourceV6 {
    uint32_t handle;
    int32_t values[16]; /* signed s15.16 source values */
} GEGBISourceMatrixResourceV6;

typedef struct GEGBISourceViewportResourceV6 {
    uint32_t handle;
    int32_t values[8]; /* scale xyz,w then translate xyz,w in source units */
    uint32_t flags;
} GEGBISourceViewportResourceV6;

typedef struct GEGBISourceImageResourceV6 {
    uint32_t handle;
    uint32_t byte_length;
    uint32_t format;
    uint32_t size;
    uint32_t width;
    uint32_t height;
    uint32_t flags;
    uint32_t reserved;
} GEGBISourceImageResourceV6;

typedef struct GEGBISourcePacketV6 {
    GEAbiHeaderV1 header;
    uint32_t packet_version;
    uint32_t dialect;
    uint32_t command_count;
    uint32_t list_count;
    uint32_t vertex_count;
    uint32_t vertex_resource_count;
    uint32_t matrix_count;
    uint32_t viewport_count;
    uint32_t image_count;
    uint32_t root_list_handle;
    uint32_t reserved0[2];
    GEGBISourceCommandV6 commands[GE_SOURCE_GBI_V6_MAX_COMMANDS];
    GEGBISourceListV6 lists[GE_SOURCE_GBI_V6_MAX_LISTS];
    GEVertexV1 vertices[GE_SOURCE_GBI_V6_MAX_VERTICES];
    GEGBISourceVertexResourceV6 vertex_resources[GE_SOURCE_GBI_V6_MAX_VERTEX_RESOURCES];
    GEGBISourceMatrixResourceV6 matrices[GE_SOURCE_GBI_V6_MAX_MATRICES];
    GEGBISourceViewportResourceV6 viewports[GE_SOURCE_GBI_V6_MAX_VIEWPORTS];
    GEGBISourceImageResourceV6 images[GE_SOURCE_GBI_V6_MAX_IMAGES];
} GEGBISourcePacketV6;

typedef struct GEGBITileStateV6 {
    uint32_t format_size_line_tmem;
    uint32_t tile_palette_cmt_maskt_shiftt;
    uint32_t cms_masks_shifts;
    uint32_t uls_ult_lrs_lrt;
    uint32_t image_handle;
    uint32_t loaded;
} GEGBITileStateV6;

typedef struct GEGBIStateV6 {
    uint32_t geometry_mode;
    uint32_t other_mode_h;
    uint32_t other_mode_l;
    uint32_t combine_w0;
    uint32_t combine_w1;
    uint32_t prim_color;
    uint32_t env_color;
    uint32_t blend_color;
    uint32_t fog_color;
    uint32_t fill_color;
    uint32_t texture_state;
    uint32_t texture_image_handle;
    uint32_t texture_image_format_size_width;
    uint32_t texture_enabled_level_tile;
    uint32_t texture_scale_s;
    uint32_t texture_scale_t;
    uint32_t viewport_handle;
    uint32_t modelview_handle;
    uint32_t projection_handle;
    uint32_t modelview_depth;
    uint32_t projection_depth;
    uint32_t scissor_ulx_uly;
    uint32_t scissor_lrx_lry;
    uint32_t scissor_mode;
    uint32_t move_word_index_offset;
    uint32_t move_word_value;
    uint32_t rdp_half_1;
    uint32_t rdp_half_2;
    uint32_t state_generation;
    GEGBITileStateV6 tiles[GE_SOURCE_GBI_V6_MAX_TILES];
    uint64_t state_hash;
} GEGBIStateV6;

typedef struct GEGBIVertexSnapshotV6 {
    GEVertexV1 value;
    uint32_t slot;
    uint32_t source_index;
} GEGBIVertexSnapshotV6;

/*
 * Additive source vertex-load provenance.  The decoder records the exact
 * modelview handle active when each cache slot was loaded; triangles may mix
 * slots from different loads, so a final triangle-state modelview is not
 * sufficient to lower their positions.  This record is copied out through a
 * bounded call-time window and does not alter GEGBIDrawV6.
 */
typedef struct GEGBIVertexLoadProvenanceV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t flags;
    uint32_t command_offset;
    uint32_t cache_slot;
    uint32_t source_vertex;
    uint32_t modelview_handle;
    uint32_t modelview_depth;
    uint32_t reserved0;
    uint32_t reserved1;
} GEGBIVertexLoadProvenanceV6;

enum {
    GE_SOURCE_GBI_V6_EVENT_COMMAND = 1u,
    GE_SOURCE_GBI_V6_EVENT_LIST_ENTER = 2u,
    GE_SOURCE_GBI_V6_EVENT_LIST_RETURN = 3u,
    GE_SOURCE_GBI_V6_EVENT_STATE = 4u,
    GE_SOURCE_GBI_V6_EVENT_VERTEX_LOAD = 5u,
    GE_SOURCE_GBI_V6_EVENT_TRIANGLE = 6u,
    GE_SOURCE_GBI_V6_EVENT_TEXTURE = 7u,
    GE_SOURCE_GBI_V6_EVENT_RASTER = 8u,
    GE_SOURCE_GBI_V6_EVENT_SYNC = 9u,
    GE_SOURCE_GBI_V6_EVENT_UNSUPPORTED = 10u,
};

typedef struct GEGBIEventV6 {
    uint32_t kind;
    uint32_t opcode;
    uint32_t flags;
    uint32_t command_offset;
    uint32_t list_handle;
    uint32_t list_depth;
    uint32_t a;
    uint32_t b;
    uint32_t c;
    uint32_t d;
    uint32_t e;
    uint32_t f;
    uint32_t g;
    uint32_t h;
} GEGBIEventV6;

typedef struct GEGBIDrawV6 {
    uint32_t event_index;
    uint32_t source_command_offset;
    uint32_t source_list_handle;
    uint32_t source_list_depth;
    uint32_t vertex_slot_a;
    uint32_t vertex_slot_b;
    uint32_t vertex_slot_c;
    uint32_t source_vertex_a;
    uint32_t source_vertex_b;
    uint32_t source_vertex_c;
    uint32_t tile;
    uint32_t texture_handle;
    uint32_t flags;
    uint32_t state_index;
    uint64_t state_hash;
} GEGBIDrawV6;

enum {
    GE_SOURCE_GBI_V6_DIAG_NONE = 0u,
    GE_SOURCE_GBI_V6_DIAG_ARGUMENT = 1u,
    GE_SOURCE_GBI_V6_DIAG_HEADER = 2u,
    GE_SOURCE_GBI_V6_DIAG_RESERVED = 3u,
    GE_SOURCE_GBI_V6_DIAG_TRUNCATED = 4u,
    GE_SOURCE_GBI_V6_DIAG_UNSUPPORTED = 5u,
    GE_SOURCE_GBI_V6_DIAG_CAPACITY = 6u,
    GE_SOURCE_GBI_V6_DIAG_RESOURCE = 7u,
    GE_SOURCE_GBI_V6_DIAG_CYCLE = 8u,
    GE_SOURCE_GBI_V6_DIAG_STACK = 9u,
    GE_SOURCE_GBI_V6_DIAG_VERTEX = 10u,
    GE_SOURCE_GBI_V6_DIAG_TEXTURE = 11u,
    GE_SOURCE_GBI_V6_DIAG_MALFORMED = 12u,
};

typedef struct GEGBIDiagnosticV6 {
    uint32_t code;
    uint32_t opcode;
    uint32_t command_offset;
    uint32_t list_handle;
    uint32_t list_depth;
    uint32_t detail0;
    uint32_t detail1;
    uint32_t reserved;
} GEGBIDiagnosticV6;

typedef struct GEGBIResultV6 {
    GEAbiHeaderV1 header;
    GEStatusV1 status;
    uint32_t packet_version;
    uint32_t error_opcode;
    uint32_t error_offset;
    uint32_t error_list_handle;
    uint32_t error_list_depth;
    uint32_t commands_processed;
    uint32_t list_enters;
    uint32_t list_returns;
    uint32_t event_count;
    uint32_t draw_count;
    uint32_t vertex_count;
    uint32_t unsupported_count;
    uint32_t diagnostic_count;
    uint32_t max_list_depth;
    uint32_t state_count;
    uint64_t event_hash;
    uint64_t state_hash;
    GEGBIStateV6 state;
    GEGBIStateV6 states[GE_SOURCE_GBI_V6_MAX_STATES];
    GEGBIVertexSnapshotV6 vertices[GE_SOURCE_GBI_V6_MAX_VERTEX_CACHE];
    GEGBIEventV6 events[GE_SOURCE_GBI_V6_MAX_EVENTS];
    GEGBIDrawV6 draws[GE_SOURCE_GBI_V6_MAX_DRAWS];
    GEGBIDiagnosticV6 diagnostics[GE_SOURCE_GBI_V6_MAX_DIAGNOSTICS];
} GEGBIResultV6;

GEGBIResultV6 ge_source_gbi_decode_v6(GEGBISourcePacketV6 packet);
GEStatusV1 ge_source_gbi_decode_v6_into(const GEGBISourcePacketV6 *packet,
                                        GEGBIResultV6 *result);
GEStatusV1 ge_source_gbi_decode_v6_into_with_vertex_pages(
    const GEGBISourcePacketV6 *packet,
    const GEGBISourceVertexResourcePageV6 *pages,
    uint32_t page_count,
    GEGBIResultV6 *result);
GEStatusV1 ge_source_gbi_decode_v6_into_with_vertex_pages_and_provenance(
    const GEGBISourcePacketV6 *packet,
    const GEGBISourceVertexResourcePageV6 *pages,
    uint32_t page_count,
    GEGBIResultV6 *result,
    GEGBIVertexLoadProvenanceV6 *out_values,
    uint32_t out_capacity,
    uint32_t *out_count);

GEStatusV1 ge_source_gbi_v6_validate_vertex_resource_page(
    const GEGBISourceVertexResourcePageV6 *page);
uint64_t ge_source_gbi_v6_hash_vertex_resource_manifest(
    const GEGBISourceVertexResourceV6 *base_items,
    uint32_t base_count,
    const GEGBISourceVertexResourcePageV6 *pages,
    uint32_t page_count);
/*
 * Builds continuation pages for a complete ordered resource list.  The first
 * 64 descriptors are the packet base; output page first_item values therefore
 * begin at 64 for lists larger than the frozen base capacity.
 */
GEStatusV1 ge_source_gbi_v6_build_vertex_resource_pages(
    const GEGBISourceVertexResourceV6 *items,
    uint32_t total_items,
    GEGBISourceVertexResourcePageV6 *out_pages,
    uint32_t out_page_capacity,
    uint32_t *out_page_count);

/*
 * Bounded copy-out windows for Swift and other hosts.  first/count are
 * element indices, out_capacity is element capacity, and no output pointer
 * is retained.  A zero-count request may pass a NULL output pointer.
 */
GEStatusV1 ge_source_gbi_v6_copy_states(
    const GEGBIResultV6 *result,
    uint32_t first,
    uint32_t count,
    GEGBIStateV6 *out_values,
    uint32_t out_capacity);
GEStatusV1 ge_source_gbi_v6_copy_draws(
    const GEGBIResultV6 *result,
    uint32_t first,
    uint32_t count,
    GEGBIDrawV6 *out_values,
    uint32_t out_capacity);
GEStatusV1 ge_source_gbi_v6_copy_events(
    const GEGBIResultV6 *result,
    uint32_t first,
    uint32_t count,
    GEGBIEventV6 *out_values,
    uint32_t out_capacity);
GEStatusV1 ge_source_gbi_v6_build_vertex_load_provenance(
    const GEGBISourcePacketV6 *packet,
    const GEGBISourceVertexResourcePageV6 *pages,
    uint32_t page_count,
    GEGBIVertexLoadProvenanceV6 *out_values,
    uint32_t out_capacity,
    uint32_t *out_count);
GEStatusV1 ge_source_gbi_v6_copy_diagnostics(
    const GEGBIResultV6 *result,
    uint32_t first,
    uint32_t count,
    GEGBIDiagnosticV6 *out_values,
    uint32_t out_capacity);
GEStatusV1 ge_source_gbi_v6_copy_images(
    const GEGBISourcePacketV6 *packet,
    uint32_t first,
    uint32_t count,
    GEGBISourceImageResourceV6 *out_values,
    uint32_t out_capacity);

#if defined(__cplusplus)
#define GE_SOURCE_GBI_V6_STATIC_ASSERT(condition, message) static_assert((condition), message)
#else
#define GE_SOURCE_GBI_V6_STATIC_ASSERT(condition, message) _Static_assert((condition), message)
#endif

GE_SOURCE_GBI_V6_STATIC_ASSERT(sizeof(GEGBISourceCommandV6) == 8u,
                               "GEGBISourceCommandV6 layout drift");
GE_SOURCE_GBI_V6_STATIC_ASSERT(sizeof(GEGBISourceListV6) == 16u,
                               "GEGBISourceListV6 layout drift");
GE_SOURCE_GBI_V6_STATIC_ASSERT(sizeof(GEGBISourceVertexResourceV6) == 16u,
                               "GEGBISourceVertexResourceV6 layout drift");
GE_SOURCE_GBI_V6_STATIC_ASSERT(sizeof(GEGBISourceVertexResourcePageV6) == 1080u,
                               "GEGBISourceVertexResourcePageV6 layout drift");
GE_SOURCE_GBI_V6_STATIC_ASSERT(sizeof(GEGBISourceMatrixResourceV6) == 68u,
                               "GEGBISourceMatrixResourceV6 layout drift");
GE_SOURCE_GBI_V6_STATIC_ASSERT(sizeof(GEGBISourceViewportResourceV6) == 40u,
                               "GEGBISourceViewportResourceV6 layout drift");
GE_SOURCE_GBI_V6_STATIC_ASSERT(sizeof(GEGBISourceImageResourceV6) == 32u,
                               "GEGBISourceImageResourceV6 layout drift");
GE_SOURCE_GBI_V6_STATIC_ASSERT(sizeof(GEGBITileStateV6) == 24u,
                               "GEGBITileStateV6 layout drift");
GE_SOURCE_GBI_V6_STATIC_ASSERT(sizeof(GEGBIStateV6) == 320u,
                               "GEGBIStateV6 layout drift");
GE_SOURCE_GBI_V6_STATIC_ASSERT(sizeof(GEGBIEventV6) == 56u,
                               "GEGBIEventV6 layout drift");
GE_SOURCE_GBI_V6_STATIC_ASSERT(sizeof(GEGBIVertexLoadProvenanceV6) == 44u,
                               "GEGBIVertexLoadProvenanceV6 layout drift");
GE_SOURCE_GBI_V6_STATIC_ASSERT(sizeof(GEGBIDrawV6) == 64u,
                               "GEGBIDrawV6 layout drift");
GE_SOURCE_GBI_V6_STATIC_ASSERT(sizeof(GEGBIDiagnosticV6) == 32u,
                               "GEGBIDiagnosticV6 layout drift");

#undef GE_SOURCE_GBI_V6_STATIC_ASSERT

#endif /* GE_SOURCE_GBI_V6_H */
