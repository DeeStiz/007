#include "ge_source_reference_v6.h"

#include <stddef.h>
#include <string.h>

typedef struct GESourceReferenceFactV6 {
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
    uint64_t command_order_hash;
    const uint8_t *source_sha256;
} GESourceReferenceFactV6;

typedef struct GESourceReferenceResourceFactV6 {
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
    const char *token;
} GESourceReferenceResourceFactV6;

typedef struct GESourceReferenceCommandFactV6 {
    uint32_t screen_id;
    uint32_t command_kind;
    uint32_t flags;
    uint32_t ordinal;
    uint32_t count;
    uint32_t source_line_first;
    uint32_t source_line_last;
} GESourceReferenceCommandFactV6;

static const uint8_t kLegalSourceSHA256[32] = {
    0x5a, 0xf3, 0x6d, 0x12, 0x55, 0x19, 0x3d, 0x60,
    0x32, 0x82, 0x42, 0xa5, 0xdd, 0x80, 0xcc, 0xd4,
    0x73, 0xbc, 0x2d, 0x7f, 0xc6, 0x63, 0x16, 0x15,
    0xda, 0xe0, 0x8d, 0x0e, 0x9b, 0x59, 0x33, 0x7f,
};

static const uint8_t kNintendoSourceSHA256[32] = {
    0x8e, 0x0e, 0x40, 0x94, 0x67, 0x13, 0x03, 0xf1,
    0xdb, 0xc3, 0xda, 0x53, 0x16, 0x7a, 0x86, 0x65,
    0x8a, 0xaa, 0x2a, 0xa1, 0x0e, 0xb0, 0x0a, 0xe8,
    0x9d, 0x64, 0xaa, 0x52, 0xae, 0xdc, 0x35, 0xd9,
};

static const uint8_t kGoldenEyeSourceSHA256[32] = {
    0xc9, 0x8d, 0xa3, 0x8e, 0x9b, 0x27, 0xfb, 0x6a,
    0x5f, 0x02, 0xe1, 0xff, 0x1d, 0xc2, 0x89, 0x64,
    0x3a, 0x84, 0xcd, 0x38, 0x7c, 0x32, 0x5a, 0xf1,
    0x7b, 0x18, 0x04, 0x62, 0x5b, 0x22, 0xa5, 0x4c,
};

static const uint8_t kRarewareSourceSHA256[32] = {
    0xee, 0x03, 0xf5, 0x65, 0x2d, 0x18, 0xb4, 0x9e,
    0x70, 0x0a, 0x74, 0x64, 0x76, 0x52, 0x56, 0x86,
    0xff, 0xb7, 0xbb, 0x65, 0x0c, 0x10, 0x96, 0x18,
    0xea, 0x6d, 0x02, 0x43, 0xa3, 0xca, 0xe1, 0xb5,
};

static const uint8_t kWalletSourceSHA256[32] = {
    0xfe, 0xed, 0x20, 0x6e, 0x27, 0xe5, 0x8e, 0x9c,
    0xd4, 0xde, 0x67, 0xa2, 0x99, 0x63, 0x47, 0x43,
    0xea, 0x97, 0x06, 0xf2, 0x41, 0xb4, 0xbf, 0xa6,
    0x1d, 0x6a, 0xdb, 0x57, 0xce, 0xe1, 0xdf, 0x7f,
};

#define GE_SOURCE_REFERENCE_SCREEN(                                               \
    id, screen_flags, model, first_line, last_line, nodes, dls, vertices,         \
    triangles, textures, mips, text, switches, commands, unknown, resources,      \
    switch_nodes, source_dls, auxiliary, order_hash, digest)                       \
    {                                                                               \
        (id), (screen_flags), (model), (first_line), (last_line), (nodes),         \
        (dls), (vertices), (triangles), (textures), (mips), (text), (switches),    \
        (commands), (unknown), (resources), (switch_nodes), (source_dls),          \
        (auxiliary), (order_hash), (digest)                                         \
    }

static const GESourceReferenceFactV6 kScreens[GE_SOURCE_REFERENCE_V6_SCREEN_COUNT] = {
    GE_SOURCE_REFERENCE_SCREEN(
        GE_SOURCE_REFERENCE_V6_SCREEN_LEGAL,
        GE_SOURCE_REFERENCE_V6_SCREEN_HAS_MODEL |
            GE_SOURCE_REFERENCE_V6_SCREEN_HAS_SOURCE_TEXT |
            GE_SOURCE_REFERENCE_V6_SCREEN_HAS_TEXTURES |
            GE_SOURCE_REFERENCE_V6_SCREEN_HAS_SOURCE_TIMING |
            GE_SOURCE_REFERENCE_V6_SCREEN_EXACT_COUNTS |
            GE_SOURCE_REFERENCE_V6_SCREEN_SOURCE_HASHED |
            GE_SOURCE_REFERENCE_V6_SCREEN_COMMAND_COUNTS_COMPLETE |
            GE_SOURCE_REFERENCE_V6_SCREEN_STATIC_SOURCE_AUDIT_COMPLETE,
        GE_SOURCE_REFERENCE_V6_MODEL_LEGALPAGE, 1405u, 1553u,
        3u, 1u, 24u, 12u, 5u, 0u, 12u, 0u, 58u, 0u, 4u, 0u, 1u, 0u,
        UINT64_C(0x8e915a7f4044c593),
        kLegalSourceSHA256),
    GE_SOURCE_REFERENCE_SCREEN(
        GE_SOURCE_REFERENCE_V6_SCREEN_NINTENDO,
        GE_SOURCE_REFERENCE_V6_SCREEN_HAS_MODEL |
            GE_SOURCE_REFERENCE_V6_SCREEN_HAS_TEXTURES |
            GE_SOURCE_REFERENCE_V6_SCREEN_HAS_SOURCE_TIMING |
            GE_SOURCE_REFERENCE_V6_SCREEN_EXACT_COUNTS |
            GE_SOURCE_REFERENCE_V6_SCREEN_SOURCE_HASHED |
            GE_SOURCE_REFERENCE_V6_SCREEN_COMMAND_COUNTS_COMPLETE |
            GE_SOURCE_REFERENCE_V6_SCREEN_STATIC_SOURCE_AUDIT_COMPLETE,
        GE_SOURCE_REFERENCE_V6_MODEL_NINTENDOLOGO, 1598u, 1763u,
        42u, 23u, 1363u, 1021u, 1u, 0u, 0u, 0u, 821u, 0u, 3u, 0u, 23u, 0u,
        UINT64_C(0x9cc62b913ce52e5b),
        kNintendoSourceSHA256),
    GE_SOURCE_REFERENCE_SCREEN(
        GE_SOURCE_REFERENCE_V6_SCREEN_GOLDENEYE,
        GE_SOURCE_REFERENCE_V6_SCREEN_HAS_MODEL |
            GE_SOURCE_REFERENCE_V6_SCREEN_HAS_TEXTURES |
            GE_SOURCE_REFERENCE_V6_SCREEN_HAS_MIP_CHAINS |
            GE_SOURCE_REFERENCE_V6_SCREEN_HAS_SOURCE_TIMING |
            GE_SOURCE_REFERENCE_V6_SCREEN_EXACT_COUNTS |
            GE_SOURCE_REFERENCE_V6_SCREEN_SOURCE_HASHED |
            GE_SOURCE_REFERENCE_V6_SCREEN_COMMAND_COUNTS_COMPLETE |
            GE_SOURCE_REFERENCE_V6_SCREEN_STATIC_SOURCE_AUDIT_COMPLETE,
        GE_SOURCE_REFERENCE_V6_MODEL_GOLDENEYELOGO, 1869u, 2060u,
        3u, 1u, 438u, 341u, 2u, 1u, 0u, 0u, 162u, 0u, 4u, 0u, 1u, 0u,
        UINT64_C(0xbe5c050badae9682),
        kGoldenEyeSourceSHA256),
    GE_SOURCE_REFERENCE_SCREEN(
        GE_SOURCE_REFERENCE_V6_SCREEN_RAREWARE,
        GE_SOURCE_REFERENCE_V6_SCREEN_HAS_MODEL |
            GE_SOURCE_REFERENCE_V6_SCREEN_HAS_TEXTURES |
            GE_SOURCE_REFERENCE_V6_SCREEN_HAS_MIP_CHAINS |
            GE_SOURCE_REFERENCE_V6_SCREEN_HAS_SOURCE_TIMING |
            GE_SOURCE_REFERENCE_V6_SCREEN_EXACT_COUNTS |
            GE_SOURCE_REFERENCE_V6_SCREEN_SOURCE_HASHED |
            GE_SOURCE_REFERENCE_V6_SCREEN_COMMAND_COUNTS_COMPLETE |
            GE_SOURCE_REFERENCE_V6_SCREEN_STATIC_SOURCE_AUDIT_COMPLETE,
        GE_SOURCE_REFERENCE_V6_MODEL_RAREWARELOGO, 384u, 429u,
        0u, 9u, 381u, 268u, 6u, 4u, 0u, 0u, 389u, 0u, 5u, 0u, 9u, 397u,
        UINT64_C(0xaf862a5762d1f654),
        kRarewareSourceSHA256),
    GE_SOURCE_REFERENCE_SCREEN(
        GE_SOURCE_REFERENCE_V6_SCREEN_WALLET,
        GE_SOURCE_REFERENCE_V6_SCREEN_HAS_MODEL |
            GE_SOURCE_REFERENCE_V6_SCREEN_HAS_TEXTURES |
            GE_SOURCE_REFERENCE_V6_SCREEN_HAS_SWITCHES |
            GE_SOURCE_REFERENCE_V6_SCREEN_HAS_SOURCE_TIMING |
            GE_SOURCE_REFERENCE_V6_SCREEN_EXACT_COUNTS |
            GE_SOURCE_REFERENCE_V6_SCREEN_SOURCE_HASHED |
            GE_SOURCE_REFERENCE_V6_SCREEN_COMMAND_COUNTS_COMPLETE |
            GE_SOURCE_REFERENCE_V6_SCREEN_STATIC_SOURCE_AUDIT_COMPLETE,
        GE_SOURCE_REFERENCE_V6_MODEL_WALLETBOND, 2063u, 2713u,
        90u, 46u, 765u, 440u, 84u, 0u, 0u, 43u, 982u, 0u, 4u, 42u, 46u, 0u,
        UINT64_C(0x2bf6d0230e7ae7a1),
        kWalletSourceSHA256),
};

#undef GE_SOURCE_REFERENCE_SCREEN

#define GE_SOURCE_REFERENCE_RESOURCE(screen, kind, resource_flags, handle, quantity, width, height, levels, format, line, token) \
    { (screen), (kind), (resource_flags), (handle), (quantity), (width), (height), (levels), (format), (line), (token) }

static const GESourceReferenceResourceFactV6 kResources[] = {
    GE_SOURCE_REFERENCE_RESOURCE(GE_SOURCE_REFERENCE_V6_SCREEN_LEGAL, GE_SOURCE_REFERENCE_V6_RESOURCE_MODEL, 0u, 4u, 1u, 0u, 0u, 0u, GE_SOURCE_REFERENCE_V6_RESOURCE_FORMAT_MIXED, 1414u, "legalpage"),
    GE_SOURCE_REFERENCE_RESOURCE(GE_SOURCE_REFERENCE_V6_SCREEN_LEGAL, GE_SOURCE_REFERENCE_V6_RESOURCE_TEXTURES, GE_SOURCE_REFERENCE_V6_SCREEN_HAS_TEXTURES, 4u, 5u, 128u, 64u, 1u, GE_SOURCE_REFERENCE_V6_RESOURCE_FORMAT_MIXED, 21u, "legalpage.proptextures"),
    GE_SOURCE_REFERENCE_RESOURCE(GE_SOURCE_REFERENCE_V6_SCREEN_LEGAL, GE_SOURCE_REFERENCE_V6_RESOURCE_SOURCE_TEXT, GE_SOURCE_REFERENCE_V6_SCREEN_HAS_SOURCE_TEXT, 0u, 12u, 0u, 0u, 0u, GE_SOURCE_REFERENCE_V6_RESOURCE_FORMAT_UNKNOWN, 342u, "legalpage_text_array"),
    GE_SOURCE_REFERENCE_RESOURCE(GE_SOURCE_REFERENCE_V6_SCREEN_LEGAL, GE_SOURCE_REFERENCE_V6_RESOURCE_RENDER_DATA, 0u, 4u, 1u, 0u, 0u, 0u, GE_SOURCE_REFERENCE_V6_RESOURCE_FORMAT_UNKNOWN, 1500u, "constructor_menu00_legalscreen"),

    GE_SOURCE_REFERENCE_RESOURCE(GE_SOURCE_REFERENCE_V6_SCREEN_NINTENDO, GE_SOURCE_REFERENCE_V6_RESOURCE_MODEL, 0u, 5u, 1u, 0u, 0u, 0u, GE_SOURCE_REFERENCE_V6_RESOURCE_FORMAT_MIXED, 1604u, "nintendologo"),
    GE_SOURCE_REFERENCE_RESOURCE(GE_SOURCE_REFERENCE_V6_SCREEN_NINTENDO, GE_SOURCE_REFERENCE_V6_RESOURCE_TEXTURES, GE_SOURCE_REFERENCE_V6_SCREEN_HAS_TEXTURES, 5u, 1u, 719u, 16u, 1u, GE_SOURCE_REFERENCE_V6_RESOURCE_FORMAT_I8, 21u, "nintendologo.proptextures"),
    GE_SOURCE_REFERENCE_RESOURCE(GE_SOURCE_REFERENCE_V6_SCREEN_NINTENDO, GE_SOURCE_REFERENCE_V6_RESOURCE_RENDER_DATA, 0u, 5u, 1u, 0u, 0u, 0u, GE_SOURCE_REFERENCE_V6_RESOURCE_FORMAT_UNKNOWN, 1662u, "constructor_menu01_nintendo"),

    GE_SOURCE_REFERENCE_RESOURCE(GE_SOURCE_REFERENCE_V6_SCREEN_GOLDENEYE, GE_SOURCE_REFERENCE_V6_RESOURCE_MODEL, 0u, 3u, 1u, 0u, 0u, 0u, GE_SOURCE_REFERENCE_V6_RESOURCE_FORMAT_MIXED, 1875u, "goldeneyelogo"),
    GE_SOURCE_REFERENCE_RESOURCE(GE_SOURCE_REFERENCE_V6_SCREEN_GOLDENEYE, GE_SOURCE_REFERENCE_V6_RESOURCE_TEXTURES, GE_SOURCE_REFERENCE_V6_SCREEN_HAS_TEXTURES, 3u, 2u, 32u, 32u, 1u, GE_SOURCE_REFERENCE_V6_RESOURCE_FORMAT_MIXED, 21u, "goldeneyelogo.proptextures"),
    GE_SOURCE_REFERENCE_RESOURCE(GE_SOURCE_REFERENCE_V6_SCREEN_GOLDENEYE, GE_SOURCE_REFERENCE_V6_RESOURCE_MIP_CHAIN, GE_SOURCE_REFERENCE_V6_SCREEN_HAS_MIP_CHAINS, 3u, 1u, 32u, 32u, 6u, GE_SOURCE_REFERENCE_V6_RESOURCE_FORMAT_RGBA16, 21u, "goldeneyelogo.mip-chain"),
    GE_SOURCE_REFERENCE_RESOURCE(GE_SOURCE_REFERENCE_V6_SCREEN_GOLDENEYE, GE_SOURCE_REFERENCE_V6_RESOURCE_RENDER_DATA, 0u, 3u, 1u, 0u, 0u, 0u, GE_SOURCE_REFERENCE_V6_RESOURCE_FORMAT_UNKNOWN, 1936u, "constructor_menu04_goldeneyelogo"),

    GE_SOURCE_REFERENCE_RESOURCE(GE_SOURCE_REFERENCE_V6_SCREEN_RAREWARE, GE_SOURCE_REFERENCE_V6_RESOURCE_MODEL, 0u, 1u, 1u, 0u, 0u, 0u, GE_SOURCE_REFERENCE_V6_RESOURCE_FORMAT_MIXED, 10u, "rarewarelogo"),
    GE_SOURCE_REFERENCE_RESOURCE(GE_SOURCE_REFERENCE_V6_SCREEN_RAREWARE, GE_SOURCE_REFERENCE_V6_RESOURCE_TEXTURES, GE_SOURCE_REFERENCE_V6_SCREEN_HAS_TEXTURES, 1u, 6u, 64u, 86u, 1u, GE_SOURCE_REFERENCE_V6_RESOURCE_FORMAT_RGBA16, 14u, "rarewarelogo.images"),
    GE_SOURCE_REFERENCE_RESOURCE(GE_SOURCE_REFERENCE_V6_SCREEN_RAREWARE, GE_SOURCE_REFERENCE_V6_RESOURCE_MIP_CHAIN, GE_SOURCE_REFERENCE_V6_SCREEN_HAS_MIP_CHAINS, 1u, 4u, 64u, 86u, 4u, GE_SOURCE_REFERENCE_V6_RESOURCE_FORMAT_RGBA16, 14u, "rarewarelogo.mip-chains"),
    GE_SOURCE_REFERENCE_RESOURCE(GE_SOURCE_REFERENCE_V6_SCREEN_RAREWARE, GE_SOURCE_REFERENCE_V6_RESOURCE_SOURCE_FUNCTION, GE_SOURCE_REFERENCE_V6_SCREEN_HAS_SOURCE_TIMING, 1u, 1u, 0u, 0u, 0u, GE_SOURCE_REFERENCE_V6_RESOURCE_FORMAT_UNKNOWN, 384u, "retrieve_display_rareware_logo"),
    GE_SOURCE_REFERENCE_RESOURCE(GE_SOURCE_REFERENCE_V6_SCREEN_RAREWARE, GE_SOURCE_REFERENCE_V6_RESOURCE_RENDER_DATA, 0u, 1u, 9u, 0u, 0u, 0u, GE_SOURCE_REFERENCE_V6_RESOURCE_FORMAT_UNKNOWN, 10u, "rarewarelogo.display-lists"),

    GE_SOURCE_REFERENCE_RESOURCE(GE_SOURCE_REFERENCE_V6_SCREEN_WALLET, GE_SOURCE_REFERENCE_V6_RESOURCE_MODEL, 0u, 6u, 1u, 0u, 0u, 0u, GE_SOURCE_REFERENCE_V6_RESOURCE_FORMAT_MIXED, 2063u, "walletbond"),
    GE_SOURCE_REFERENCE_RESOURCE(GE_SOURCE_REFERENCE_V6_SCREEN_WALLET, GE_SOURCE_REFERENCE_V6_RESOURCE_TEXTURES, GE_SOURCE_REFERENCE_V6_SCREEN_HAS_TEXTURES, 6u, 84u, 219u, 219u, 1u, GE_SOURCE_REFERENCE_V6_RESOURCE_FORMAT_MIXED, 6u, "walletbond.proptextures"),
    GE_SOURCE_REFERENCE_RESOURCE(GE_SOURCE_REFERENCE_V6_SCREEN_WALLET, GE_SOURCE_REFERENCE_V6_RESOURCE_UI_ICONS, 0u, 6u, 3u, 0u, 0u, 0u, GE_SOURCE_REFERENCE_V6_RESOURCE_FORMAT_MIXED, 2677u, "mainfolderimages"),
    GE_SOURCE_REFERENCE_RESOURCE(GE_SOURCE_REFERENCE_V6_SCREEN_WALLET, GE_SOURCE_REFERENCE_V6_RESOURCE_RENDER_DATA, GE_SOURCE_REFERENCE_V6_SCREEN_HAS_SWITCHES, 6u, 46u, 0u, 0u, 0u, GE_SOURCE_REFERENCE_V6_RESOURCE_FORMAT_UNKNOWN, 2451u, "constructor_menu05_fileselect"),
};

#undef GE_SOURCE_REFERENCE_RESOURCE

#define GE_SOURCE_REFERENCE_COMMAND(screen, kind, command_flags, ordinal_value, count_value, first_line, last_line) \
    { (screen), (kind), (command_flags), (ordinal_value), (count_value), (first_line), (last_line) }

static const GESourceReferenceCommandFactV6 kCommands[] = {
    /* Counts below match GESM V6 command records, after comment removal. */
    GE_SOURCE_REFERENCE_COMMAND(0u, GE_SOURCE_REFERENCE_V6_COMMAND_VERTEX_LOAD, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 0u, 2u, 94u, 154u),
    GE_SOURCE_REFERENCE_COMMAND(0u, GE_SOURCE_REFERENCE_V6_COMMAND_TRIANGLE, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_EXPANDED | GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 1u, 6u, 94u, 154u),
    GE_SOURCE_REFERENCE_COMMAND(0u, GE_SOURCE_REFERENCE_V6_COMMAND_TEXTURE_IMAGE, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 2u, 5u, 94u, 154u),
    GE_SOURCE_REFERENCE_COMMAND(0u, GE_SOURCE_REFERENCE_V6_COMMAND_TEXTURE_TILE, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 3u, 3u, 94u, 154u),
    GE_SOURCE_REFERENCE_COMMAND(0u, GE_SOURCE_REFERENCE_V6_COMMAND_TEXTURE_LOAD, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 4u, 10u, 94u, 154u),
    GE_SOURCE_REFERENCE_COMMAND(0u, GE_SOURCE_REFERENCE_V6_COMMAND_COMBINER, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 5u, 3u, 94u, 154u),
    GE_SOURCE_REFERENCE_COMMAND(0u, GE_SOURCE_REFERENCE_V6_COMMAND_MATRIX, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 6u, 1u, 94u, 154u),
    GE_SOURCE_REFERENCE_COMMAND(0u, GE_SOURCE_REFERENCE_V6_COMMAND_GEOMETRY, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 7u, 1u, 94u, 154u),
    GE_SOURCE_REFERENCE_COMMAND(0u, GE_SOURCE_REFERENCE_V6_COMMAND_PIPELINE, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 8u, 15u, 94u, 154u),
    GE_SOURCE_REFERENCE_COMMAND(0u, GE_SOURCE_REFERENCE_V6_COMMAND_RAW_INITIALIZER, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_RAW_INITIALIZER | GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 9u, 12u, 94u, 154u),

    GE_SOURCE_REFERENCE_COMMAND(1u, GE_SOURCE_REFERENCE_V6_COMMAND_VERTEX_LOAD, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 0u, 93u, 2107u, 3018u),
    GE_SOURCE_REFERENCE_COMMAND(1u, GE_SOURCE_REFERENCE_V6_COMMAND_TRIANGLE, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_EXPANDED | GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 1u, 288u, 2107u, 3018u),
    GE_SOURCE_REFERENCE_COMMAND(1u, GE_SOURCE_REFERENCE_V6_COMMAND_TEXTURE_IMAGE, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 2u, 23u, 2107u, 3018u),
    GE_SOURCE_REFERENCE_COMMAND(1u, GE_SOURCE_REFERENCE_V6_COMMAND_TEXTURE_TILE, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 3u, 69u, 2107u, 3018u),
    GE_SOURCE_REFERENCE_COMMAND(1u, GE_SOURCE_REFERENCE_V6_COMMAND_TEXTURE_LOAD, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 4u, 46u, 2107u, 3018u),
    GE_SOURCE_REFERENCE_COMMAND(1u, GE_SOURCE_REFERENCE_V6_COMMAND_COMBINER, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 5u, 24u, 2107u, 3018u),
    GE_SOURCE_REFERENCE_COMMAND(1u, GE_SOURCE_REFERENCE_V6_COMMAND_MATRIX, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 6u, 23u, 2107u, 3018u),
    GE_SOURCE_REFERENCE_COMMAND(1u, GE_SOURCE_REFERENCE_V6_COMMAND_GEOMETRY, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 7u, 46u, 2107u, 3018u),
    GE_SOURCE_REFERENCE_COMMAND(1u, GE_SOURCE_REFERENCE_V6_COMMAND_PIPELINE, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 8u, 140u, 2107u, 3018u),
    GE_SOURCE_REFERENCE_COMMAND(1u, GE_SOURCE_REFERENCE_V6_COMMAND_RAW_INITIALIZER, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_RAW_INITIALIZER | GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 9u, 69u, 2107u, 3018u),

    GE_SOURCE_REFERENCE_COMMAND(2u, GE_SOURCE_REFERENCE_V6_COMMAND_VERTEX_LOAD, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 0u, 29u, 505u, 669u),
    GE_SOURCE_REFERENCE_COMMAND(2u, GE_SOURCE_REFERENCE_V6_COMMAND_TRIANGLE, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_EXPANDED | GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 1u, 94u, 505u, 669u),
    GE_SOURCE_REFERENCE_COMMAND(2u, GE_SOURCE_REFERENCE_V6_COMMAND_TEXTURE_IMAGE, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 2u, 2u, 505u, 669u),
    GE_SOURCE_REFERENCE_COMMAND(2u, GE_SOURCE_REFERENCE_V6_COMMAND_TEXTURE_TILE, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 3u, 3u, 505u, 669u),
    GE_SOURCE_REFERENCE_COMMAND(2u, GE_SOURCE_REFERENCE_V6_COMMAND_TEXTURE_LOAD, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 4u, 4u, 505u, 669u),
    GE_SOURCE_REFERENCE_COMMAND(2u, GE_SOURCE_REFERENCE_V6_COMMAND_COMBINER, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 5u, 1u, 505u, 669u),
    GE_SOURCE_REFERENCE_COMMAND(2u, GE_SOURCE_REFERENCE_V6_COMMAND_MATRIX, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 6u, 1u, 505u, 669u),
    GE_SOURCE_REFERENCE_COMMAND(2u, GE_SOURCE_REFERENCE_V6_COMMAND_GEOMETRY, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 7u, 2u, 505u, 669u),
    GE_SOURCE_REFERENCE_COMMAND(2u, GE_SOURCE_REFERENCE_V6_COMMAND_PIPELINE, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 8u, 9u, 505u, 669u),
    GE_SOURCE_REFERENCE_COMMAND(2u, GE_SOURCE_REFERENCE_V6_COMMAND_RAW_INITIALIZER, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_RAW_INITIALIZER | GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 9u, 17u, 505u, 669u),

    GE_SOURCE_REFERENCE_COMMAND(3u, GE_SOURCE_REFERENCE_V6_COMMAND_VERTEX_LOAD, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 0u, 28u, 10u, 1969u),
    GE_SOURCE_REFERENCE_COMMAND(3u, GE_SOURCE_REFERENCE_V6_COMMAND_TRIANGLE, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_EXPANDED | GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 1u, 268u, 10u, 1969u),
    GE_SOURCE_REFERENCE_COMMAND(3u, GE_SOURCE_REFERENCE_V6_COMMAND_TEXTURE_IMAGE, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 2u, 4u, 10u, 1969u),
    GE_SOURCE_REFERENCE_COMMAND(3u, GE_SOURCE_REFERENCE_V6_COMMAND_TEXTURE_TILE, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 3u, 54u, 10u, 1969u),
    GE_SOURCE_REFERENCE_COMMAND(3u, GE_SOURCE_REFERENCE_V6_COMMAND_TEXTURE_LOAD, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 4u, 8u, 10u, 1969u),
    GE_SOURCE_REFERENCE_COMMAND(3u, GE_SOURCE_REFERENCE_V6_COMMAND_COMBINER, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 5u, 3u, 10u, 1969u),
    GE_SOURCE_REFERENCE_COMMAND(3u, GE_SOURCE_REFERENCE_V6_COMMAND_GEOMETRY, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 6u, 3u, 10u, 1969u),
    GE_SOURCE_REFERENCE_COMMAND(3u, GE_SOURCE_REFERENCE_V6_COMMAND_PIPELINE, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 7u, 21u, 10u, 1969u),

    GE_SOURCE_REFERENCE_COMMAND(4u, GE_SOURCE_REFERENCE_V6_COMMAND_VERTEX_LOAD, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 0u, 68u, 2440u, 3588u),
    GE_SOURCE_REFERENCE_COMMAND(4u, GE_SOURCE_REFERENCE_V6_COMMAND_TRIANGLE, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_EXPANDED | GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 1u, 182u, 2440u, 3588u),
    GE_SOURCE_REFERENCE_COMMAND(4u, GE_SOURCE_REFERENCE_V6_COMMAND_TEXTURE_TILE, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 2u, 146u, 2440u, 3588u),
    GE_SOURCE_REFERENCE_COMMAND(4u, GE_SOURCE_REFERENCE_V6_COMMAND_COMBINER, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 3u, 69u, 2440u, 3588u),
    GE_SOURCE_REFERENCE_COMMAND(4u, GE_SOURCE_REFERENCE_V6_COMMAND_MATRIX, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 4u, 46u, 2440u, 3588u),
    GE_SOURCE_REFERENCE_COMMAND(4u, GE_SOURCE_REFERENCE_V6_COMMAND_GEOMETRY, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 5u, 47u, 2440u, 3588u),
    GE_SOURCE_REFERENCE_COMMAND(4u, GE_SOURCE_REFERENCE_V6_COMMAND_PIPELINE, GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SEMANTIC, 6u, 424u, 2440u, 3588u),
};

#undef GE_SOURCE_REFERENCE_COMMAND

static const uint32_t kResourceCount =
    (uint32_t)(sizeof(kResources) / sizeof(kResources[0]));
static const uint32_t kCommandCount =
    (uint32_t)(sizeof(kCommands) / sizeof(kCommands[0]));

static uint64_t ge_source_reference_hash_byte(uint64_t hash, uint8_t value)
{
    return (hash ^ (uint64_t)value) * UINT64_C(1099511628211);
}

static uint64_t ge_source_reference_hash_u32(uint64_t hash, uint32_t value)
{
    hash = ge_source_reference_hash_byte(hash, (uint8_t)(value & 0xffu));
    hash = ge_source_reference_hash_byte(hash, (uint8_t)((value >> 8) & 0xffu));
    hash = ge_source_reference_hash_byte(hash, (uint8_t)((value >> 16) & 0xffu));
    return ge_source_reference_hash_byte(hash, (uint8_t)(value >> 24));
}

static uint64_t ge_source_reference_hash_u64(uint64_t hash, uint64_t value)
{
    hash = ge_source_reference_hash_u32(hash, (uint32_t)value);
    return ge_source_reference_hash_u32(hash, (uint32_t)(value >> 32));
}

static uint64_t ge_source_reference_hash_bytes(uint64_t hash,
                                               const uint8_t *bytes,
                                               size_t count)
{
    size_t i;
    for (i = 0u; i < count; ++i) {
        hash = ge_source_reference_hash_byte(hash, bytes[i]);
    }
    return hash;
}

static uint64_t ge_source_reference_hash_string(const char *value)
{
    uint64_t hash = UINT64_C(1469598103934665603);
    if (value != NULL) {
        const unsigned char *cursor = (const unsigned char *)value;
        while (*cursor != 0u) {
            hash = ge_source_reference_hash_byte(hash, *cursor);
            ++cursor;
        }
    }
    return hash;
}

static uint64_t ge_source_reference_screen_hash(
    const GESourceReferenceScreenV6 *screen)
{
    uint64_t hash = UINT64_C(1469598103934665603);
    const uint32_t *values = &screen->record_version;
    size_t i;
    for (i = 0u; i < 21u; ++i) {
        hash = ge_source_reference_hash_u32(hash, values[i]);
    }
    hash = ge_source_reference_hash_u64(hash, screen->command_order_hash);
    hash = ge_source_reference_hash_bytes(hash, screen->source_sha256, 32u);
    return hash;
}

static uint64_t ge_source_reference_resource_hash(
    const GESourceReferenceResourceV6 *resource)
{
    uint64_t hash = UINT64_C(1469598103934665603);
    const uint32_t *values = &resource->record_version;
    size_t i;
    for (i = 0u; i < 13u; ++i) {
        hash = ge_source_reference_hash_u32(hash, values[i]);
    }
    return hash;
}

static uint64_t ge_source_reference_command_hash(
    const GESourceReferenceCommandV6 *command)
{
    uint64_t hash = UINT64_C(1469598103934665603);
    const uint32_t *values = &command->record_version;
    size_t i;
    for (i = 0u; i < 9u; ++i) {
        hash = ge_source_reference_hash_u32(hash, values[i]);
    }
    return hash;
}

static void ge_source_reference_fill_screen(uint32_t index,
                                            GESourceReferenceScreenV6 *out)
{
    const GESourceReferenceFactV6 *fact = &kScreens[index];
    memset(out, 0, sizeof(*out));
    out->header.abi_version = GE_NATIVE_ABI_VERSION;
    out->header.struct_size = (uint32_t)sizeof(*out);
    out->record_version = GE_SOURCE_REFERENCE_V6_RECORD_VERSION;
    out->screen_id = fact->screen_id;
    out->flags = fact->flags;
    out->model_handle = fact->model_handle;
    out->source_line_first = fact->source_line_first;
    out->source_line_last = fact->source_line_last;
    out->node_count = fact->node_count;
    out->display_list_count = fact->display_list_count;
    out->vertex_count = fact->vertex_count;
    out->triangle_count = fact->triangle_count;
    out->texture_count = fact->texture_count;
    out->mip_chain_count = fact->mip_chain_count;
    out->text_entry_count = fact->text_entry_count;
    out->switch_count = fact->switch_count;
    out->command_count = fact->command_count;
    out->unknown_command_count = fact->unknown_command_count;
    out->resource_count = fact->resource_count;
    out->source_switch_node_count = fact->source_switch_node_count;
    out->source_display_list_count = fact->source_display_list_count;
    out->source_auxiliary_count = fact->source_auxiliary_count;
    out->command_order_hash = fact->command_order_hash;
    memcpy(out->source_sha256, fact->source_sha256, sizeof(out->source_sha256));
    out->semantic_hash = ge_source_reference_screen_hash(out);
}

static void ge_source_reference_fill_resource(
    uint32_t index, GESourceReferenceResourceV6 *out)
{
    const GESourceReferenceResourceFactV6 *fact = &kResources[index];
    memset(out, 0, sizeof(*out));
    out->header.abi_version = GE_NATIVE_ABI_VERSION;
    out->header.struct_size = (uint32_t)sizeof(*out);
    out->record_version = GE_SOURCE_REFERENCE_V6_RECORD_VERSION;
    out->screen_id = fact->screen_id;
    out->resource_kind = fact->resource_kind;
    out->flags = fact->flags;
    out->handle = fact->handle;
    out->quantity = fact->quantity;
    out->width = fact->width;
    out->height = fact->height;
    out->level_count = fact->level_count;
    out->format = fact->format;
    out->source_line = fact->source_line;
    out->source_token_hash = (uint32_t)ge_source_reference_hash_string(fact->token);
    out->semantic_hash = ge_source_reference_resource_hash(out);
}

static void ge_source_reference_fill_command(
    uint32_t index, GESourceReferenceCommandV6 *out)
{
    const GESourceReferenceCommandFactV6 *fact = &kCommands[index];
    memset(out, 0, sizeof(*out));
    out->header.abi_version = GE_NATIVE_ABI_VERSION;
    out->header.struct_size = (uint32_t)sizeof(*out);
    out->record_version = GE_SOURCE_REFERENCE_V6_RECORD_VERSION;
    out->screen_id = fact->screen_id;
    out->command_kind = fact->command_kind;
    out->flags = fact->flags;
    out->ordinal = fact->ordinal;
    out->count = fact->count;
    out->source_line_first = fact->source_line_first;
    out->source_line_last = fact->source_line_last;
    out->semantic_hash = ge_source_reference_command_hash(out);
}

static uint64_t ge_source_reference_aggregate_hash(void)
{
    uint64_t hash = UINT64_C(1469598103934665603);
    uint32_t i;
    GESourceReferenceScreenV6 screen;
    GESourceReferenceResourceV6 resource;
    GESourceReferenceCommandV6 command;

    hash = ge_source_reference_hash_u32(
        hash, GE_SOURCE_REFERENCE_V6_REFERENCE_KIND_STATIC_SOURCE_COUNTS);
    hash = ge_source_reference_hash_u64(hash, UINT64_C(0x0006000100000001));

    for (i = 0u; i < GE_SOURCE_REFERENCE_V6_SCREEN_COUNT; ++i) {
        ge_source_reference_fill_screen(i, &screen);
        hash = ge_source_reference_hash_u64(hash, screen.semantic_hash);
    }
    for (i = 0u; i < kResourceCount; ++i) {
        ge_source_reference_fill_resource(i, &resource);
        hash = ge_source_reference_hash_u64(hash, resource.semantic_hash);
    }
    for (i = 0u; i < kCommandCount; ++i) {
        ge_source_reference_fill_command(i, &command);
        hash = ge_source_reference_hash_u64(hash, command.semantic_hash);
    }
    return hash;
}

GESourceReferenceManifestV6 ge_source_reference_v6_manifest(void)
{
    GESourceReferenceManifestV6 manifest;
    memset(&manifest, 0, sizeof(manifest));
    manifest.header.abi_version = GE_NATIVE_ABI_VERSION;
    manifest.header.struct_size = (uint32_t)sizeof(manifest);
    manifest.record_version = GE_SOURCE_REFERENCE_V6_RECORD_VERSION;
    manifest.status = GE_STATUS_OK;
    manifest.flags = GE_SOURCE_REFERENCE_V6_MANIFEST_SOURCE_FACTS |
                     GE_SOURCE_REFERENCE_V6_MANIFEST_SOURCE_HASHES |
                     GE_SOURCE_REFERENCE_V6_MANIFEST_COMMAND_COUNTS_COMPLETE |
                     GE_SOURCE_REFERENCE_V6_MANIFEST_RESOURCES_COMPLETE;
    manifest.screen_count = GE_SOURCE_REFERENCE_V6_SCREEN_COUNT;
    manifest.resource_count = kResourceCount;
    manifest.command_count = kCommandCount;
    manifest.issue_count = 0u;
    manifest.reference_kind = GE_SOURCE_REFERENCE_V6_REFERENCE_KIND_STATIC_SOURCE_COUNTS;
    manifest.source_generation = UINT64_C(0x0006000100000001);
    manifest.aggregate_hash = ge_source_reference_aggregate_hash();
    return manifest;
}

GEStatusV1 ge_source_reference_v6_validate_screen(
    const GESourceReferenceScreenV6 *screen)
{
    GESourceReferenceScreenV6 expected;
    uint32_t index;
    if (screen == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (screen->header.abi_version != GE_NATIVE_ABI_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    if (screen->header.struct_size != sizeof(*screen)) {
        return GE_STATUS_INVALID_SIZE;
    }
    if (screen->record_version != GE_SOURCE_REFERENCE_V6_RECORD_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    if ((screen->flags & ~GE_SOURCE_REFERENCE_V6_SCREEN_FLAG_MASK) != 0u) {
        return GE_STATUS_RESERVED_BITS;
    }
    if (screen->screen_id >= GE_SOURCE_REFERENCE_V6_SCREEN_COUNT) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    index = screen->screen_id;
    ge_source_reference_fill_screen(index, &expected);
    if (memcmp(screen, &expected, sizeof(expected)) != 0) {
        return GE_STATUS_ASSET_MISMATCH;
    }
    return GE_STATUS_OK;
}

GEStatusV1 ge_source_reference_v6_validate_resource(
    const GESourceReferenceResourceV6 *resource)
{
    GESourceReferenceResourceV6 expected;
    uint32_t index;
    if (resource == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (resource->header.abi_version != GE_NATIVE_ABI_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    if (resource->header.struct_size != sizeof(*resource)) {
        return GE_STATUS_INVALID_SIZE;
    }
    if (resource->record_version != GE_SOURCE_REFERENCE_V6_RECORD_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    if ((resource->flags & ~GE_SOURCE_REFERENCE_V6_RESOURCE_FLAG_MASK) != 0u ||
        resource->reserved0 != 0u) {
        return GE_STATUS_RESERVED_BITS;
    }
    if (resource->screen_id >= GE_SOURCE_REFERENCE_V6_SCREEN_COUNT ||
        resource->resource_kind == 0u ||
        resource->resource_kind > GE_SOURCE_REFERENCE_V6_RESOURCE_RENDER_DATA) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    for (index = 0u; index < kResourceCount; ++index) {
        ge_source_reference_fill_resource(index, &expected);
        if (expected.semantic_hash == resource->semantic_hash &&
            expected.screen_id == resource->screen_id) {
            if (memcmp(resource, &expected, sizeof(expected)) == 0) {
                return GE_STATUS_OK;
            }
            return GE_STATUS_ASSET_MISMATCH;
        }
    }
    return GE_STATUS_ASSET_MISMATCH;
}

GEStatusV1 ge_source_reference_v6_validate_command(
    const GESourceReferenceCommandV6 *command)
{
    GESourceReferenceCommandV6 expected;
    uint64_t hash;
    if (command == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (command->header.abi_version != GE_NATIVE_ABI_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    if (command->header.struct_size != sizeof(*command)) {
        return GE_STATUS_INVALID_SIZE;
    }
    if (command->record_version != GE_SOURCE_REFERENCE_V6_RECORD_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    if ((command->flags & ~GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_MASK) != 0u ||
        command->reserved0 != 0u) {
        return GE_STATUS_RESERVED_BITS;
    }
    if (command->screen_id >= GE_SOURCE_REFERENCE_V6_SCREEN_COUNT ||
        command->command_kind == 0u ||
        command->command_kind > GE_SOURCE_REFERENCE_V6_COMMAND_RAW_INITIALIZER) {
        return GE_STATUS_UNSUPPORTED_COMMAND;
    }
    if ((command->flags & GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_SOURCE_ORDERED) != 0u ||
        ((command->command_kind == GE_SOURCE_REFERENCE_V6_COMMAND_RAW_INITIALIZER) !=
         ((command->flags & GE_SOURCE_REFERENCE_V6_COMMAND_FLAG_RAW_INITIALIZER) != 0u))) {
        return GE_STATUS_INVALID_STATE;
    }
    hash = ge_source_reference_command_hash(command);
    if (hash != command->semantic_hash) {
        return GE_STATUS_ASSET_MISMATCH;
    }
    /* A semantic hash is not sufficient to establish source membership. */
    for (uint32_t index = 0u; index < kCommandCount; ++index) {
        ge_source_reference_fill_command(index, &expected);
        if (memcmp(command, &expected, sizeof(expected)) == 0) {
            return GE_STATUS_OK;
        }
    }
    return GE_STATUS_ASSET_MISMATCH;
}

GEStatusV1 ge_source_reference_v6_validate_manifest(
    const GESourceReferenceManifestV6 *manifest)
{
    GESourceReferenceManifestV6 expected;
    if (manifest == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (manifest->header.abi_version != GE_NATIVE_ABI_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    if (manifest->header.struct_size != sizeof(*manifest)) {
        return GE_STATUS_INVALID_SIZE;
    }
    if (manifest->record_version != GE_SOURCE_REFERENCE_V6_RECORD_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    if ((manifest->flags & ~GE_SOURCE_REFERENCE_V6_MANIFEST_FLAG_MASK) != 0u) {
        return GE_STATUS_RESERVED_BITS;
    }
    if ((manifest->reference_kind & ~GE_SOURCE_REFERENCE_V6_REFERENCE_KIND_MASK) != 0u ||
        manifest->reference_kind != GE_SOURCE_REFERENCE_V6_REFERENCE_KIND_STATIC_SOURCE_COUNTS ||
        manifest->reserved0 != 0u) {
        return GE_STATUS_RESERVED_BITS;
    }
    expected = ge_source_reference_v6_manifest();
    if (memcmp(manifest, &expected, sizeof(expected)) != 0) {
        return GE_STATUS_ASSET_MISMATCH;
    }
    return GE_STATUS_OK;
}

uint32_t ge_source_reference_v6_screen_count(void)
{
    return GE_SOURCE_REFERENCE_V6_SCREEN_COUNT;
}

uint32_t ge_source_reference_v6_resource_count(void)
{
    return kResourceCount;
}

uint32_t ge_source_reference_v6_command_count(void)
{
    return kCommandCount;
}

uint32_t ge_source_reference_v6_issue_count(void)
{
    return 0u;
}

GEStatusV1 ge_source_reference_v6_get_screen(
    uint32_t index, GESourceReferenceScreenV6 *out_screen)
{
    if (out_screen == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (index >= GE_SOURCE_REFERENCE_V6_SCREEN_COUNT) {
        return GE_STATUS_RESOURCE_NOT_FOUND;
    }
    ge_source_reference_fill_screen(index, out_screen);
    return GE_STATUS_OK;
}

GEStatusV1 ge_source_reference_v6_get_resource(
    uint32_t index, GESourceReferenceResourceV6 *out_resource)
{
    if (out_resource == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (index >= kResourceCount) {
        return GE_STATUS_RESOURCE_NOT_FOUND;
    }
    ge_source_reference_fill_resource(index, out_resource);
    return GE_STATUS_OK;
}

GEStatusV1 ge_source_reference_v6_get_command(
    uint32_t index, GESourceReferenceCommandV6 *out_command)
{
    if (out_command == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (index >= kCommandCount) {
        return GE_STATUS_RESOURCE_NOT_FOUND;
    }
    ge_source_reference_fill_command(index, out_command);
    return GE_STATUS_OK;
}

GEStatusV1 ge_source_reference_v6_get_issue(
    uint32_t index, GESourceReferenceIssueV6 *out_issue)
{
    if (out_issue == NULL) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    (void)index;
    return GE_STATUS_RESOURCE_NOT_FOUND;
}

GEStatusV1 ge_source_reference_v6_copy_screens(
    uint32_t first, uint32_t capacity, GESourceReferenceScreenV6 *out,
    uint32_t *out_count)
{
    uint32_t count;
    uint32_t i;
    if (out_count == NULL || (capacity != 0u && out == NULL)) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (first > GE_SOURCE_REFERENCE_V6_SCREEN_COUNT) {
        return GE_STATUS_RESOURCE_NOT_FOUND;
    }
    count = GE_SOURCE_REFERENCE_V6_SCREEN_COUNT - first;
    if (count > capacity) {
        count = capacity;
    }
    for (i = 0u; i < count; ++i) {
        ge_source_reference_fill_screen(first + i, &out[i]);
    }
    *out_count = count;
    return GE_STATUS_OK;
}

GEStatusV1 ge_source_reference_v6_copy_resources(
    uint32_t first, uint32_t capacity, GESourceReferenceResourceV6 *out,
    uint32_t *out_count)
{
    uint32_t count;
    uint32_t i;
    if (out_count == NULL || (capacity != 0u && out == NULL)) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (first > kResourceCount) {
        return GE_STATUS_RESOURCE_NOT_FOUND;
    }
    count = kResourceCount - first;
    if (count > capacity) {
        count = capacity;
    }
    for (i = 0u; i < count; ++i) {
        ge_source_reference_fill_resource(first + i, &out[i]);
    }
    *out_count = count;
    return GE_STATUS_OK;
}

GEStatusV1 ge_source_reference_v6_copy_commands(
    uint32_t first, uint32_t capacity, GESourceReferenceCommandV6 *out,
    uint32_t *out_count)
{
    uint32_t count;
    uint32_t i;
    if (out_count == NULL || (capacity != 0u && out == NULL)) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (first > kCommandCount) {
        return GE_STATUS_RESOURCE_NOT_FOUND;
    }
    count = kCommandCount - first;
    if (count > capacity) {
        count = capacity;
    }
    for (i = 0u; i < count; ++i) {
        ge_source_reference_fill_command(first + i, &out[i]);
    }
    *out_count = count;
    return GE_STATUS_OK;
}

GEStatusV1 ge_source_reference_v6_copy_issues(
    uint32_t first, uint32_t capacity, GESourceReferenceIssueV6 *out,
    uint32_t *out_count)
{
    if (out_count == NULL || (capacity != 0u && out == NULL)) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (first != 0u) {
        return GE_STATUS_RESOURCE_NOT_FOUND;
    }
    (void)out;
    *out_count = 0u;
    return GE_STATUS_OK;
}
