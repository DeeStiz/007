#ifndef GE_SOURCE_REFERENCE_V6_H
#define GE_SOURCE_REFERENCE_V6_H

/*
 * Additive static source-reference manifest for the native frontend port.
 *
 * The records in this contract are semantic facts copied from the checked-in
 * source listings and generated model resources.  They intentionally do not
 * contain Gfx words, segmented addresses, pointers, paths, ROM addresses,
 * model graphs, or Metal objects.  This contract audits static source counts
 * and command families; it is not a dynamic source oracle, does not execute
 * the original frontend producers, and does not enumerate per-frame draw
 * order.  A caller can page the records through the copy-out functions below
 * without giving the runtime ownership of mutable storage.
 */

#include <stdint.h>

#include "ge_native_foundation.h"

#ifdef __cplusplus
extern "C" {
#endif

#define GE_SOURCE_REFERENCE_V6_ABI_VERSION ((uint32_t)6u)
#define GE_SOURCE_REFERENCE_V6_RECORD_VERSION ((uint32_t)1u)

#define GE_SOURCE_REFERENCE_V6_SCREEN_LEGAL ((uint32_t)0u)
#define GE_SOURCE_REFERENCE_V6_SCREEN_NINTENDO ((uint32_t)1u)
#define GE_SOURCE_REFERENCE_V6_SCREEN_GOLDENEYE ((uint32_t)2u)
#define GE_SOURCE_REFERENCE_V6_SCREEN_RAREWARE ((uint32_t)3u)
#define GE_SOURCE_REFERENCE_V6_SCREEN_WALLET ((uint32_t)4u)
#define GE_SOURCE_REFERENCE_V6_SCREEN_COUNT ((uint32_t)5u)

#define GE_SOURCE_REFERENCE_V6_MODEL_NONE ((uint32_t)0u)
#define GE_SOURCE_REFERENCE_V6_MODEL_LEGALPAGE ((uint32_t)4u)
#define GE_SOURCE_REFERENCE_V6_MODEL_NINTENDOLOGO ((uint32_t)5u)
#define GE_SOURCE_REFERENCE_V6_MODEL_GOLDENEYELOGO ((uint32_t)3u)
#define GE_SOURCE_REFERENCE_V6_MODEL_RAREWARELOGO ((uint32_t)1u)
#define GE_SOURCE_REFERENCE_V6_MODEL_WALLETBOND ((uint32_t)6u)

/* Screen flags describe what the manifest proves, not renderer readiness. */
#define GE_SOURCE_REFERENCE_V6_SCREEN_HAS_MODEL ((uint32_t)1u << 0)
#define GE_SOURCE_REFERENCE_V6_SCREEN_HAS_SOURCE_TEXT ((uint32_t)1u << 1)
#define GE_SOURCE_REFERENCE_V6_SCREEN_HAS_TEXTURES ((uint32_t)1u << 2)
#define GE_SOURCE_REFERENCE_V6_SCREEN_HAS_MIP_CHAINS ((uint32_t)1u << 3)
#define GE_SOURCE_REFERENCE_V6_SCREEN_HAS_SWITCHES ((uint32_t)1u << 4)
#define GE_SOURCE_REFERENCE_V6_SCREEN_HAS_SOURCE_TIMING ((uint32_t)1u << 5)
#define GE_SOURCE_REFERENCE_V6_SCREEN_EXACT_COUNTS ((uint32_t)1u << 6)
#define GE_SOURCE_REFERENCE_V6_SCREEN_SOURCE_HASHED ((uint32_t)1u << 7)
#define GE_SOURCE_REFERENCE_V6_SCREEN_COMMAND_COUNTS_COMPLETE ((uint32_t)1u << 8)
#define GE_SOURCE_REFERENCE_V6_SCREEN_STATIC_SOURCE_AUDIT_COMPLETE ((uint32_t)1u << 9)
#define GE_SOURCE_REFERENCE_V6_SCREEN_FLAG_MASK ((uint32_t)0x03ffu)

#define GE_SOURCE_REFERENCE_V6_MANIFEST_SOURCE_FACTS ((uint32_t)1u << 0)
#define GE_SOURCE_REFERENCE_V6_MANIFEST_SOURCE_HASHES ((uint32_t)1u << 1)
#define GE_SOURCE_REFERENCE_V6_MANIFEST_COMMAND_COUNTS_COMPLETE ((uint32_t)1u << 2)
#define GE_SOURCE_REFERENCE_V6_MANIFEST_RESOURCES_COMPLETE ((uint32_t)1u << 3)
#define GE_SOURCE_REFERENCE_V6_MANIFEST_HAS_DIAGNOSTICS ((uint32_t)1u << 4)
#define GE_SOURCE_REFERENCE_V6_MANIFEST_FLAG_MASK ((uint32_t)0x001fu)

/* A V6 manifest is static evidence, never a dynamic frame/draw-order oracle. */
#define GE_SOURCE_REFERENCE_V6_REFERENCE_KIND_STATIC_SOURCE_COUNTS ((uint32_t)1u)
#define GE_SOURCE_REFERENCE_V6_REFERENCE_KIND_DYNAMIC_FRAME ((uint32_t)2u)
#define GE_SOURCE_REFERENCE_V6_REFERENCE_KIND_DYNAMIC_DRAW_ORDER ((uint32_t)3u)
#define GE_SOURCE_REFERENCE_V6_REFERENCE_KIND_MASK ((uint32_t)0x0003u)

/* Resource kinds are semantic categories; no source pointer is retained. */
#define GE_SOURCE_REFERENCE_V6_RESOURCE_MODEL ((uint32_t)1u)
#define GE_SOURCE_REFERENCE_V6_RESOURCE_TEXTURES ((uint32_t)2u)
#define GE_SOURCE_REFERENCE_V6_RESOURCE_MIP_CHAIN ((uint32_t)3u)
#define GE_SOURCE_REFERENCE_V6_RESOURCE_SOURCE_TEXT ((uint32_t)4u)
#define GE_SOURCE_REFERENCE_V6_RESOURCE_SOURCE_FUNCTION ((uint32_t)5u)
#define GE_SOURCE_REFERENCE_V6_RESOURCE_UI_ICONS ((uint32_t)6u)
#define GE_SOURCE_REFERENCE_V6_RESOURCE_RENDER_DATA ((uint32_t)7u)
#define GE_SOURCE_REFERENCE_V6_RESOURCE_FLAG_MASK ((uint32_t)0x007fu)

#define GE_SOURCE_REFERENCE_V6_RESOURCE_FORMAT_UNKNOWN ((uint32_t)0u)
#define GE_SOURCE_REFERENCE_V6_RESOURCE_FORMAT_I8 ((uint32_t)1u)
#define GE_SOURCE_REFERENCE_V6_RESOURCE_FORMAT_RGBA16 ((uint32_t)2u)
#define GE_SOURCE_REFERENCE_V6_RESOURCE_FORMAT_RGBA32 ((uint32_t)3u)
#define GE_SOURCE_REFERENCE_V6_RESOURCE_FORMAT_MIXED ((uint32_t)4u)

/* Command families are normalized static counts from declared Gfx bodies,
 * including source raw {w0,w1} initializers. They never expose raw GBI words.
 * The screen command_order_hash preserves source order without claiming a
 * dynamic per-frame draw-order oracle. */
#define GE_SOURCE_REFERENCE_V6_COMMAND_MODEL_NODE ((uint32_t)1u)
#define GE_SOURCE_REFERENCE_V6_COMMAND_DISPLAY_LIST ((uint32_t)2u)
#define GE_SOURCE_REFERENCE_V6_COMMAND_VERTEX_LOAD ((uint32_t)3u)
#define GE_SOURCE_REFERENCE_V6_COMMAND_TRIANGLE ((uint32_t)4u)
#define GE_SOURCE_REFERENCE_V6_COMMAND_TEXTURE_IMAGE ((uint32_t)5u)
#define GE_SOURCE_REFERENCE_V6_COMMAND_TEXTURE_TILE ((uint32_t)6u)
#define GE_SOURCE_REFERENCE_V6_COMMAND_TEXTURE_LOAD ((uint32_t)7u)
#define GE_SOURCE_REFERENCE_V6_COMMAND_COMBINER ((uint32_t)8u)
#define GE_SOURCE_REFERENCE_V6_COMMAND_MATRIX ((uint32_t)9u)
#define GE_SOURCE_REFERENCE_V6_COMMAND_GEOMETRY ((uint32_t)10u)
#define GE_SOURCE_REFERENCE_V6_COMMAND_PIPELINE ((uint32_t)11u)
#define GE_SOURCE_REFERENCE_V6_COMMAND_SWITCH ((uint32_t)12u)
#define GE_SOURCE_REFERENCE_V6_COMMAND_TEXT ((uint32_t)13u)
#define GE_SOURCE_REFERENCE_V6_COMMAND_SOURCE_TIMING ((uint32_t)14u)
#define GE_SOURCE_REFERENCE_V6_COMMAND_RAW_INITIALIZER ((uint32_t)15u)
#define GE_SOURCE_REFERENCE_V6_COMMAND_KIND_MASK ((uint32_t)0x3fffu)

#define GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_EXPANDED ((uint32_t)1u << 0)
#define GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SOURCE_ORDERED ((uint32_t)1u << 1)
#define GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_DYNAMIC ((uint32_t)1u << 2)
#define GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC ((uint32_t)1u << 3)
#define GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_RAW_INITIALIZER ((uint32_t)1u << 4)
#define GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_MASK ((uint32_t)0x001fu)

#define GE_SOURCE_REFERENCE_V6_ISSUE_NONE ((uint32_t)0u)
#define GE_SOURCE_REFERENCE_V6_ISSUE_COUNT_MISMATCH ((uint32_t)1u)
#define GE_SOURCE_REFERENCE_V6_ISSUE_SOURCE_HASH_MISMATCH ((uint32_t)2u)
#define GE_SOURCE_REFERENCE_V6_ISSUE_UNKNOWN_COMMAND ((uint32_t)3u)
#define GE_SOURCE_REFERENCE_V6_ISSUE_MISSING_RESOURCE ((uint32_t)4u)
#define GE_SOURCE_REFERENCE_V6_ISSUE_RESERVED_NONZERO ((uint32_t)5u)
#define GE_SOURCE_REFERENCE_V6_ISSUE_INVALID_RECORD ((uint32_t)6u)
#define GE_SOURCE_REFERENCE_V6_ISSUE_FLAG_MASK ((uint32_t)0x000fu)

#define GE_SOURCE_REFERENCE_V6_ISSUE_INFO ((uint32_t)0u)
#define GE_SOURCE_REFERENCE_V6_ISSUE_WARNING ((uint32_t)1u)
#define GE_SOURCE_REFERENCE_V6_ISSUE_ERROR ((uint32_t)2u)

#define GE_SOURCE_REFERENCE_V6_MAX_RESOURCES ((uint32_t)32u)
#define GE_SOURCE_REFERENCE_V6_MAX_COMMANDS ((uint32_t)96u)
#define GE_SOURCE_REFERENCE_V6_MAX_ISSUES ((uint32_t)16u)

typedef struct GESourceReferenceManifestV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    GEStatusV1 status;
    uint32_t flags;
    uint32_t screen_count;
    uint32_t resource_count;
    uint32_t command_count;
    uint32_t issue_count;
    uint32_t reference_kind;
    uint64_t source_generation;
    uint64_t aggregate_hash;
    uint32_t reserved0;
} GESourceReferenceManifestV6;

typedef struct GESourceReferenceScreenV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t screen_id;
    uint32_t flags;
    uint32_t model_handle;
    uint32_t source_line_first;
    uint32_t source_line_last;
    uint32_t node_count;
    uint32_t display_list_count;
    uint32_t vertex_count;
    uint32_t triangle_count;
    uint32_t texture_count;
    uint32_t mip_chain_count;
    uint32_t text_entry_count;
    uint32_t switch_count;
    uint32_t command_count;
    uint32_t unknown_command_count;
    uint32_t resource_count;
    uint32_t source_switch_node_count;
    uint32_t source_display_list_count;
    uint32_t source_auxiliary_count;
    uint32_t reserved0;
    uint64_t command_order_hash;
    uint64_t semantic_hash;
    uint8_t source_sha256[32];
} GESourceReferenceScreenV6;

typedef struct GESourceReferenceResourceV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t screen_id;
    uint32_t resource_kind;
    uint32_t flags;
    uint32_t handle;
    uint32_t quantity;
    uint32_t width;
    uint32_t height;
    uint32_t level_count;
    uint32_t format;
    uint32_t source_line;
    uint32_t source_token_hash;
    uint32_t reserved0;
    uint64_t semantic_hash;
} GESourceReferenceResourceV6;

typedef struct GESourceReferenceCommandV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t screen_id;
    uint32_t command_kind;
    uint32_t flags;
    uint32_t ordinal;
    uint32_t count;
    uint32_t source_line_first;
    uint32_t source_line_last;
    uint32_t reserved0;
    uint64_t semantic_hash;
} GESourceReferenceCommandV6;

typedef struct GESourceReferenceIssueV6 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t screen_id;
    uint32_t severity;
    uint32_t code;
    uint32_t subject_kind;
    uint32_t expected;
    uint32_t observed;
    uint32_t source_line;
    uint32_t reserved0;
    uint64_t detail_hash;
} GESourceReferenceIssueV6;

GESourceReferenceManifestV6 ge_source_reference_v6_manifest(void);
GEStatusV1 ge_source_reference_v6_validate_manifest(
    const GESourceReferenceManifestV6 *manifest);
GEStatusV1 ge_source_reference_v6_validate_screen(
    const GESourceReferenceScreenV6 *screen);
GEStatusV1 ge_source_reference_v6_validate_resource(
    const GESourceReferenceResourceV6 *resource);
GEStatusV1 ge_source_reference_v6_validate_command(
    const GESourceReferenceCommandV6 *command);

uint32_t ge_source_reference_v6_screen_count(void);
uint32_t ge_source_reference_v6_resource_count(void);
uint32_t ge_source_reference_v6_command_count(void);
uint32_t ge_source_reference_v6_issue_count(void);

GEStatusV1 ge_source_reference_v6_get_screen(
    uint32_t index, GESourceReferenceScreenV6 *out_screen);
GEStatusV1 ge_source_reference_v6_get_resource(
    uint32_t index, GESourceReferenceResourceV6 *out_resource);
GEStatusV1 ge_source_reference_v6_get_command(
    uint32_t index, GESourceReferenceCommandV6 *out_command);
GEStatusV1 ge_source_reference_v6_get_issue(
    uint32_t index, GESourceReferenceIssueV6 *out_issue);

GEStatusV1 ge_source_reference_v6_copy_screens(
    uint32_t first, uint32_t capacity, GESourceReferenceScreenV6 *out,
    uint32_t *out_count);
GEStatusV1 ge_source_reference_v6_copy_resources(
    uint32_t first, uint32_t capacity, GESourceReferenceResourceV6 *out,
    uint32_t *out_count);
GEStatusV1 ge_source_reference_v6_copy_commands(
    uint32_t first, uint32_t capacity, GESourceReferenceCommandV6 *out,
    uint32_t *out_count);
GEStatusV1 ge_source_reference_v6_copy_issues(
    uint32_t first, uint32_t capacity, GESourceReferenceIssueV6 *out,
    uint32_t *out_count);

#if defined(__cplusplus)
#define GE_SOURCE_REFERENCE_V6_STATIC_ASSERT(condition, message) static_assert((condition), message)
#else
#define GE_SOURCE_REFERENCE_V6_STATIC_ASSERT(condition, message) _Static_assert((condition), message)
#endif

GE_SOURCE_REFERENCE_V6_STATIC_ASSERT(sizeof(GESourceReferenceManifestV6) == 64u,
                                     "GESourceReferenceManifestV6 layout drift");
GE_SOURCE_REFERENCE_V6_STATIC_ASSERT(sizeof(GESourceReferenceScreenV6) == 144u,
                                     "GESourceReferenceScreenV6 layout drift");
GE_SOURCE_REFERENCE_V6_STATIC_ASSERT(sizeof(GESourceReferenceResourceV6) == 72u,
                                     "GESourceReferenceResourceV6 layout drift");
GE_SOURCE_REFERENCE_V6_STATIC_ASSERT(sizeof(GESourceReferenceCommandV6) == 56u,
                                     "GESourceReferenceCommandV6 layout drift");
GE_SOURCE_REFERENCE_V6_STATIC_ASSERT(sizeof(GESourceReferenceIssueV6) == 56u,
                                     "GESourceReferenceIssueV6 layout drift");

#undef GE_SOURCE_REFERENCE_V6_STATIC_ASSERT

#ifdef __cplusplus
}
#endif

#endif /* GE_SOURCE_REFERENCE_V6_H */
