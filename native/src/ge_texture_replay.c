#include "ge_texture_replay.h"

#include <math.h>
#include <stddef.h>
#include <string.h>

/*
 * This file is deliberately a small V3 adapter around the frozen V2 classic
 * replay.  It does not change ge_classic_replay.c (and, in particular, does
 * not change any V1/V2 hashes).  The source prop contains custom G_SETTEX
 * commands only; the texture table below is the bounded native equivalent of
 * the source runtime's ModelFileTextures expansion.  There are intentionally
 * no synthetic G_SETTIMG/G_LOADBLOCK/G_LOADTLUT commands here.
 */

enum {
    GE_TEXTURE_OP_MTX = 0x01,
    GE_TEXTURE_OP_VTX = 0x04,
    GE_TEXTURE_OP_TRI4 = 0xb1,
    GE_TEXTURE_OP_ENDDL = 0xb8,
    GE_TEXTURE_OP_SETOTHERMODE_L = 0xb9,
    GE_TEXTURE_OP_SETOTHERMODE_H = 0xba,
    GE_TEXTURE_OP_TEXTURE = 0xbb,
    GE_TEXTURE_OP_SETTEX = 0xc0,
    GE_TEXTURE_OP_PIPE_SYNC = 0xe7,
    GE_TEXTURE_PROP_SIZE = 1488u,
    GE_TEXTURE_PROP_VERTEX_OFFSET = 0x0a8u,
    GE_TEXTURE_PROP_VERTEX_COUNT = 40u,
    GE_TEXTURE_PROP_COMMAND_OFFSET = 0x518u,
    GE_TEXTURE_PROP_COMMAND_COUNT = 22u,
    GE_TEXTURE_TMEM_BYTES = 4096u,
    GE_TEXTURE_TLUT_BASE = 0x100u,
};

enum {
    /* Explicit source-runtime material expansion bits in material_flags. */
    GE_TEXTURE_MATERIAL_SOURCE_EXPANSION = 1u << 0,
    GE_TEXTURE_MATERIAL_TMEM_PLAN = 1u << 1,
    GE_TEXTURE_MATERIAL_TLUT_PLAN = 1u << 2,
    GE_TEXTURE_MATERIAL_TEXEL0_SHADE = 1u << 3,
    GE_TEXTURE_MATERIAL_CI8 = 1u << 4,
    GE_TEXTURE_MATERIAL_MIPMAP = 1u << 5,
};

enum {
    GE_TEXTURE_ID_AMMOCRATE1 = 0x21u,
    GE_TEXTURE_ID_CRATEROPE = 0x25u,
    GE_TEXTURE_ID_AMMOTEXT765 = 0x27u,
};

typedef struct GETextureDrawContext {
    uint32_t command_offset;
    GETextureMaterialStateV3 material;
    uint32_t cache_source[GE_CLASSIC_CACHE_CAPACITY];
    uint8_t cache_valid[GE_CLASSIC_CACHE_CAPACITY];
} GETextureDrawContext;

static uint16_t ge_texture_be16(const uint8_t *bytes)
{
    return (uint16_t)(((uint16_t)bytes[0] << 8) | bytes[1]);
}

static int16_t ge_texture_be16s(const uint8_t *bytes)
{
    return (int16_t)ge_texture_be16(bytes);
}

static uint32_t ge_texture_be32(const uint8_t *bytes)
{
    return ((uint32_t)bytes[0] << 24) |
           ((uint32_t)bytes[1] << 16) |
           ((uint32_t)bytes[2] << 8) |
           (uint32_t)bytes[3];
}

static uint64_t ge_texture_hash_byte(uint64_t hash, uint8_t value)
{
    return (hash ^ (uint64_t)value) * UINT64_C(1099511628211);
}

static uint64_t ge_texture_hash_u32(uint64_t hash, uint32_t value)
{
    hash = ge_texture_hash_byte(hash, (uint8_t)(value & 0xffu));
    hash = ge_texture_hash_byte(hash, (uint8_t)((value >> 8) & 0xffu));
    hash = ge_texture_hash_byte(hash, (uint8_t)((value >> 16) & 0xffu));
    return ge_texture_hash_byte(hash, (uint8_t)(value >> 24));
}

static uint64_t ge_texture_hash_u64(uint64_t hash, uint64_t value)
{
    hash = ge_texture_hash_u32(hash, (uint32_t)value);
    return ge_texture_hash_u32(hash, (uint32_t)(value >> 32));
}

static uint64_t ge_texture_hash_bytes(uint64_t hash, const void *data, size_t size)
{
    const uint8_t *bytes = (const uint8_t *)data;
    for (size_t index = 0; index < size; index++) {
        hash = ge_texture_hash_byte(hash, bytes[index]);
    }
    return hash;
}

static uint64_t ge_texture_hash_init(void)
{
    return UINT64_C(1469598103934665603);
}

static void ge_texture_init_result(GETexturedReplayResultV3 *result)
{
    memset(result, 0, sizeof(*result));
    result->header.abi_version = GE_NATIVE_ABI_VERSION;
    result->header.struct_size = (uint32_t)sizeof(*result);
    result->status = GE_STATUS_OK;
}

static void ge_texture_set_error(GETexturedReplayResultV3 *result,
                                 GEStatusV1 status,
                                 uint32_t opcode,
                                 uint32_t offset,
                                 uint32_t list_handle,
                                 uint32_t list_depth)
{
    result->status = status;
    result->error_opcode = opcode;
    result->error_offset = offset;
    result->error_list_handle = list_handle;
    result->error_list_depth = list_depth;
}

static int ge_texture_is_known_id(uint32_t texture_id)
{
    return texture_id == GE_TEXTURE_ID_AMMOCRATE1 ||
           texture_id == GE_TEXTURE_ID_CRATEROPE ||
           texture_id == GE_TEXTURE_ID_AMMOTEXT765;
}

static const GETextureMaterialDescriptorV3 *ge_texture_find_descriptor(
    const GETextureMaterialSetV3 *materials,
    uint32_t texture_id)
{
    for (uint32_t index = 0; index < materials->material_count; index++) {
        if (materials->materials[index].texture_id == texture_id) {
            return &materials->materials[index];
        }
    }
    return NULL;
}

static uint32_t ge_texture_expected_width(uint32_t texture_id)
{
    switch (texture_id) {
    case GE_TEXTURE_ID_AMMOCRATE1: return 64u;
    case GE_TEXTURE_ID_AMMOTEXT765: return 128u;
    case GE_TEXTURE_ID_CRATEROPE: return 32u;
    default: return 0u;
    }
}

static uint32_t ge_texture_expected_height(uint32_t texture_id)
{
    switch (texture_id) {
    case GE_TEXTURE_ID_AMMOCRATE1: return 32u;
    case GE_TEXTURE_ID_AMMOTEXT765: return 16u;
    case GE_TEXTURE_ID_CRATEROPE: return 32u;
    default: return 0u;
    }
}

static uint32_t ge_texture_expected_format(uint32_t texture_id)
{
    switch (texture_id) {
    case GE_TEXTURE_ID_AMMOCRATE1: return GE_TEXTURE_FORMAT_I8;
    case GE_TEXTURE_ID_AMMOTEXT765: return GE_TEXTURE_FORMAT_IA4;
    case GE_TEXTURE_ID_CRATEROPE: return GE_TEXTURE_FORMAT_RGBA16_CI8;
    default: return UINT32_MAX;
    }
}

static uint32_t ge_texture_expected_mip_tiles(uint32_t texture_id)
{
    switch (texture_id) {
    case GE_TEXTURE_ID_CRATEROPE: return 6u;
    case GE_TEXTURE_ID_AMMOCRATE1:
    case GE_TEXTURE_ID_AMMOTEXT765: return 7u;
    default: return 0u;
    }
}

static uint32_t ge_texture_bits_per_texel(uint32_t format)
{
    switch (format) {
    case GE_TEXTURE_FORMAT_IA4: return 4u;
    case GE_TEXTURE_FORMAT_I8: return 8u;
    case GE_TEXTURE_FORMAT_RGBA16_CI8: return 8u;
    default: return 0u;
    }
}

static int ge_texture_compression_supported(uint32_t texture_id, uint32_t compression)
{
    /* The two non-zlib source records expose their compression nibble.  The
       CI8 rope uses the zlib container, which has no per-image compression
       nibble and is represented by zero in this ABI. */
    if (texture_id == GE_TEXTURE_ID_AMMOCRATE1) {
        return compression == GE_TEXTURE_COMPRESSION_HUFFMAN_BLUR;
    }
    if (texture_id == GE_TEXTURE_ID_AMMOTEXT765) {
        return compression == GE_TEXTURE_COMPRESSION_HUFFMAN_LOOKUP;
    }
    if (texture_id == GE_TEXTURE_ID_CRATEROPE) {
        return compression == 0u;
    }
    return 0;
}

static GEStatusV1 ge_texture_validate_material_set(
    const GETextureMaterialSetV3 *materials)
{
    if (materials->header.abi_version != GE_NATIVE_ABI_VERSION) {
        return GE_STATUS_INVALID_VERSION;
    }
    if (materials->header.struct_size != sizeof(*materials)) {
        return GE_STATUS_INVALID_SIZE;
    }
    if (materials->reserved != 0u) {
        return GE_STATUS_RESERVED_BITS;
    }
    if (materials->material_count > GE_TEXTURE_MATERIAL_CAPACITY) {
        return GE_STATUS_TEXTURE_OVERFLOW;
    }
    if (materials->material_count != GE_TEXTURE_MATERIAL_CAPACITY) {
        return GE_STATUS_RESOURCE_NOT_FOUND;
    }

    for (uint32_t index = 0; index < materials->material_count; index++) {
        const GETextureMaterialDescriptorV3 *descriptor = &materials->materials[index];
        if (!ge_texture_is_known_id(descriptor->texture_id)) {
            return GE_STATUS_TEXTURE_FORMAT;
        }
        for (uint32_t other = 0; other < index; other++) {
            if (materials->materials[other].texture_id == descriptor->texture_id) {
                return GE_STATUS_MALFORMED_STREAM;
            }
        }
        if (descriptor->width != ge_texture_expected_width(descriptor->texture_id) ||
            descriptor->height != ge_texture_expected_height(descriptor->texture_id) ||
            descriptor->mipmap_tiles != ge_texture_expected_mip_tiles(descriptor->texture_id)) {
            return GE_STATUS_ASSET_MISMATCH;
        }
        if (ge_texture_bits_per_texel(descriptor->format) == 0u ||
            descriptor->format != ge_texture_expected_format(descriptor->texture_id)) {
            return GE_STATUS_TEXTURE_FORMAT;
        }
        if (!ge_texture_compression_supported(descriptor->texture_id,
                                              descriptor->compression)) {
            return GE_STATUS_TEXTURE_COMPRESSION;
        }
        if (descriptor->source_byte_count == 0u ||
            descriptor->source_byte_count > GE_TEXTURE_SOURCE_BLOB_CAPACITY ||
            descriptor->source_hash == 0u || descriptor->s_flags > 3u ||
            descriptor->t_flags > 3u) {
            return GE_STATUS_MALFORMED_STREAM;
        }
    }

    if (ge_texture_find_descriptor(materials, GE_TEXTURE_ID_AMMOCRATE1) == NULL ||
        ge_texture_find_descriptor(materials, GE_TEXTURE_ID_AMMOTEXT765) == NULL ||
        ge_texture_find_descriptor(materials, GE_TEXTURE_ID_CRATEROPE) == NULL) {
        return GE_STATUS_RESOURCE_NOT_FOUND;
    }
    return GE_STATUS_OK;
}

static uint32_t ge_texture_level_bytes(uint32_t width,
                                       uint32_t height,
                                       uint32_t bits_per_texel)
{
    uint64_t row_bits = (uint64_t)width * bits_per_texel;
    uint64_t row_bytes = (row_bits + 7u) / 8u;
    /* RDP lines are allocated in complete 64-bit words. */
    row_bytes = (row_bytes + 7u) & ~UINT64_C(7);
    uint64_t bytes = row_bytes * height;
    return bytes > UINT32_MAX ? UINT32_MAX : (uint32_t)bytes;
}

static GEStatusV1 ge_texture_build_material_state(
    const GETextureMaterialDescriptorV3 *descriptor,
    uint32_t command_w0,
    uint32_t command_w1,
    GETextureMaterialStateV3 *state)
{
    uint32_t bits_per_texel = ge_texture_bits_per_texel(descriptor->format);
    if (bits_per_texel == 0u) {
        return GE_STATUS_TEXTURE_FORMAT;
    }

    uint64_t total_bytes = 0u;
    uint32_t width = descriptor->width;
    uint32_t height = descriptor->height;
    for (uint32_t level = 0; level < descriptor->mipmap_tiles; level++) {
        uint32_t level_bytes = ge_texture_level_bytes(width, height, bits_per_texel);
        if (level_bytes == UINT32_MAX ||
            total_bytes > GE_TEXTURE_TMEM_BYTES - level_bytes) {
            return GE_STATUS_TMEM_OVERFLOW;
        }
        total_bytes += level_bytes;
        if (width > 1u) width >>= 1;
        if (height > 1u) height >>= 1;
    }

    uint32_t min_level = (command_w1 >> 24) & 0xffu;
    uint32_t texture_type = command_w0 & 0x7u;
    uint32_t tile = (command_w0 >> 18) & 0x3u;
    if (texture_type > 4u || min_level >= descriptor->mipmap_tiles) {
        return GE_STATUS_MALFORMED_STREAM;
    }

    memset(state, 0, sizeof(*state));
    state->texture_id = descriptor->texture_id;
    state->tile = tile;
    state->texture_state = command_w0;
    state->format = descriptor->format;
    state->size = bits_per_texel;
    state->mip_level = min_level;
    state->s_flags = descriptor->s_flags;
    state->t_flags = descriptor->t_flags;
    /* Each source runtime material is loaded into TMEM at zero before its
       tile records are expanded.  The plan is per-material, not a claim that
       all three textures coexist in the 4 KiB RDP TMEM at once. */
    state->tmem_offset = 0u;
    if (descriptor->format == GE_TEXTURE_FORMAT_RGBA16_CI8) {
        state->tlut_base = GE_TEXTURE_TLUT_BASE;
        state->tlut_count = GE_TEXTURE_PALETTE_ENTRY_CAPACITY;
    }
    state->material_flags = GE_TEXTURE_MATERIAL_SOURCE_EXPANSION |
                            GE_TEXTURE_MATERIAL_TMEM_PLAN |
                            GE_TEXTURE_MATERIAL_TEXEL0_SHADE;
    if (descriptor->format == GE_TEXTURE_FORMAT_RGBA16_CI8) {
        state->material_flags |= GE_TEXTURE_MATERIAL_TLUT_PLAN |
                                 GE_TEXTURE_MATERIAL_CI8;
    }
    if (descriptor->mipmap_tiles > 1u) {
        state->material_flags |= GE_TEXTURE_MATERIAL_MIPMAP;
    }

    uint64_t hash = ge_texture_hash_init();
    hash = ge_texture_hash_u32(hash, state->texture_id);
    hash = ge_texture_hash_u32(hash, state->tile);
    hash = ge_texture_hash_u32(hash, state->texture_state);
    hash = ge_texture_hash_u32(hash, state->format);
    hash = ge_texture_hash_u32(hash, state->size);
    hash = ge_texture_hash_u32(hash, state->mip_level);
    hash = ge_texture_hash_u32(hash, state->s_flags);
    hash = ge_texture_hash_u32(hash, state->t_flags);
    hash = ge_texture_hash_u32(hash, state->tmem_offset);
    hash = ge_texture_hash_u32(hash, state->tlut_base);
    hash = ge_texture_hash_u32(hash, state->tlut_count);
    hash = ge_texture_hash_u32(hash, state->material_flags);
    hash = ge_texture_hash_u32(hash, descriptor->width);
    hash = ge_texture_hash_u32(hash, descriptor->height);
    hash = ge_texture_hash_u32(hash, descriptor->mipmap_tiles);
    hash = ge_texture_hash_u32(hash, descriptor->compression);
    hash = ge_texture_hash_u32(hash, descriptor->source_byte_count);
    state->state_hash = ge_texture_hash_u64(hash, descriptor->source_hash);
    return GE_STATUS_OK;
}

static int ge_texture_validate_settex_command(uint32_t texture_id,
                                              uint32_t command_w0,
                                              uint32_t command_w1)
{
    uint32_t expected_mode = texture_id == GE_TEXTURE_ID_AMMOCRATE1 ? 0u : 1u;
    uint32_t cms = (command_w0 >> 22) & 0x3u;
    uint32_t cmt = (command_w0 >> 20) & 0x3u;
    uint32_t tile = (command_w0 >> 18) & 0x3u;
    uint32_t shifts = (command_w0 >> 14) & 0xfu;
    uint32_t shiftt = (command_w0 >> 10) & 0xfu;
    uint32_t type = command_w0 & 0x7u;
    uint32_t min_level = (command_w1 >> 24) & 0xffu;
    uint32_t detail_id = (command_w1 >> 12) & 0xfffu;
    return cms == expected_mode && cmt == expected_mode && tile == 2u &&
           shifts == 0u && shiftt == 0u && type == 2u && min_level == 0u &&
           detail_id == 0u;
}

static uint64_t ge_texture_rehash_material_state(
    const GETextureMaterialDescriptorV3 *descriptor,
    const GETextureMaterialStateV3 *state)
{
    uint64_t hash = ge_texture_hash_init();
    hash = ge_texture_hash_u32(hash, state->texture_id);
    hash = ge_texture_hash_u32(hash, state->tile);
    hash = ge_texture_hash_u32(hash, state->texture_state);
    hash = ge_texture_hash_u32(hash, state->format);
    hash = ge_texture_hash_u32(hash, state->size);
    hash = ge_texture_hash_u32(hash, state->mip_level);
    hash = ge_texture_hash_u32(hash, state->s_flags);
    hash = ge_texture_hash_u32(hash, state->t_flags);
    hash = ge_texture_hash_u32(hash, state->tmem_offset);
    hash = ge_texture_hash_u32(hash, state->tlut_base);
    hash = ge_texture_hash_u32(hash, state->tlut_count);
    hash = ge_texture_hash_u32(hash, state->material_flags);
    hash = ge_texture_hash_u32(hash, descriptor->width);
    hash = ge_texture_hash_u32(hash, descriptor->height);
    hash = ge_texture_hash_u32(hash, descriptor->mipmap_tiles);
    hash = ge_texture_hash_u32(hash, descriptor->compression);
    hash = ge_texture_hash_u32(hash, descriptor->source_byte_count);
    return ge_texture_hash_u64(hash, descriptor->source_hash);
}

static int ge_texture_expected_opcode(uint32_t index, uint32_t opcode)
{
    static const uint8_t expected[GE_TEXTURE_PROP_COMMAND_COUNT] = {
        GE_TEXTURE_OP_PIPE_SYNC,
        GE_TEXTURE_OP_SETOTHERMODE_H,
        GE_TEXTURE_OP_TEXTURE,
        GE_TEXTURE_OP_SETTEX,
        GE_TEXTURE_OP_SETOTHERMODE_H,
        GE_TEXTURE_OP_SETOTHERMODE_H,
        GE_TEXTURE_OP_MTX,
        GE_TEXTURE_OP_VTX,
        GE_TEXTURE_OP_TRI4,
        GE_TEXTURE_OP_TRI4,
        GE_TEXTURE_OP_VTX,
        GE_TEXTURE_OP_TRI4,
        GE_TEXTURE_OP_PIPE_SYNC,
        GE_TEXTURE_OP_SETOTHERMODE_L,
        GE_TEXTURE_OP_TEXTURE,
        GE_TEXTURE_OP_SETTEX,
        GE_TEXTURE_OP_TRI4,
        GE_TEXTURE_OP_TEXTURE,
        GE_TEXTURE_OP_SETTEX,
        GE_TEXTURE_OP_VTX,
        GE_TEXTURE_OP_TRI4,
        GE_TEXTURE_OP_ENDDL,
    };
    return index < GE_TEXTURE_PROP_COMMAND_COUNT && expected[index] == opcode;
}

static GEStatusV1 ge_texture_read_prop(
    const GEClassicAssetBlobV2 *blob,
    GEClassicCommandV2 commands[GE_TEXTURE_PROP_COMMAND_COUNT],
    GEVertexV1 vertices[GE_TEXTURE_PROP_VERTEX_COUNT])
{
    if (blob->header.abi_version != GE_NATIVE_ABI_VERSION ||
        blob->header.struct_size != sizeof(*blob) || blob->reserved != 0u ||
        blob->byte_count != GE_TEXTURE_PROP_SIZE ||
        blob->byte_count > GE_CLASSIC_ASSET_BLOB_CAPACITY) {
        return GE_STATUS_ASSET_MISMATCH;
    }
    for (uint32_t index = 0; index < GE_TEXTURE_PROP_VERTEX_COUNT; index++) {
        uint32_t offset = GE_TEXTURE_PROP_VERTEX_OFFSET + index * 16u;
        GEVertexV1 *vertex = &vertices[index];
        memset(vertex, 0, sizeof(*vertex));
        vertex->x = ge_texture_be16s(&blob->bytes[offset]);
        vertex->y = ge_texture_be16s(&blob->bytes[offset + 2u]);
        vertex->z = ge_texture_be16s(&blob->bytes[offset + 4u]);
        vertex->reserved0 = ge_texture_be16(&blob->bytes[offset + 6u]);
        vertex->s = ge_texture_be16s(&blob->bytes[offset + 8u]);
        vertex->t = ge_texture_be16s(&blob->bytes[offset + 10u]);
        vertex->r = blob->bytes[offset + 12u];
        vertex->g = blob->bytes[offset + 13u];
        vertex->b = blob->bytes[offset + 14u];
        vertex->a = blob->bytes[offset + 15u];
        if (vertex->reserved0 != 0u) {
            return GE_STATUS_MALFORMED_STREAM;
        }
    }
    for (uint32_t index = 0; index < GE_TEXTURE_PROP_COMMAND_COUNT; index++) {
        uint32_t offset = GE_TEXTURE_PROP_COMMAND_OFFSET + index * 8u;
        commands[index].w0 = ge_texture_be32(&blob->bytes[offset]);
        commands[index].w1 = ge_texture_be32(&blob->bytes[offset + 4u]);
        if (!ge_texture_expected_opcode(index, commands[index].w0 >> 24)) {
            return GE_STATUS_UNSUPPORTED_COMMAND;
        }
    }
    return GE_STATUS_OK;
}

static int ge_texture_find_context(const GETextureDrawContext *contexts,
                                   uint32_t context_count,
                                   uint32_t command_offset)
{
    for (uint32_t index = 0; index < context_count; index++) {
        if (contexts[index].command_offset == command_offset) {
            return (int)index;
        }
    }
    return -1;
}

static uint64_t ge_texture_material_hash(
    const GETextureMaterialSetV3 *materials,
    const GETextureMaterialStateV3 states[GE_TEXTURE_MATERIAL_CAPACITY],
    const uint8_t state_valid[GE_TEXTURE_MATERIAL_CAPACITY])
{
    static const uint32_t order[GE_TEXTURE_MATERIAL_CAPACITY] = {
        GE_TEXTURE_ID_AMMOCRATE1,
        GE_TEXTURE_ID_AMMOTEXT765,
        GE_TEXTURE_ID_CRATEROPE,
    };
    uint64_t hash = ge_texture_hash_init();
    for (uint32_t order_index = 0; order_index < GE_TEXTURE_MATERIAL_CAPACITY; order_index++) {
        uint32_t texture_id = order[order_index];
        const GETextureMaterialDescriptorV3 *descriptor =
            ge_texture_find_descriptor(materials, texture_id);
        hash = ge_texture_hash_u32(hash, texture_id);
        hash = ge_texture_hash_u32(hash, descriptor->width);
        hash = ge_texture_hash_u32(hash, descriptor->height);
        hash = ge_texture_hash_u32(hash, descriptor->mipmap_tiles);
        hash = ge_texture_hash_u32(hash, descriptor->format);
        hash = ge_texture_hash_u32(hash, descriptor->compression);
        hash = ge_texture_hash_u32(hash, descriptor->s_flags);
        hash = ge_texture_hash_u32(hash, descriptor->t_flags);
        hash = ge_texture_hash_u32(hash, descriptor->source_byte_count);
        hash = ge_texture_hash_u64(hash, descriptor->source_hash);
        hash = ge_texture_hash_byte(hash, state_valid[order_index]);
        if (state_valid[order_index]) {
            hash = ge_texture_hash_u64(hash, states[order_index].state_hash);
        }
    }
    return hash;
}

static int ge_texture_material_index(uint32_t texture_id)
{
    switch (texture_id) {
    case GE_TEXTURE_ID_AMMOCRATE1: return 0;
    case GE_TEXTURE_ID_AMMOTEXT765: return 1;
    case GE_TEXTURE_ID_CRATEROPE: return 2;
    default: return -1;
    }
}

GETexturedReplayResultV3 ge_classic_replay_textured_prop_v3(
    GEClassicAssetBlobV2 prop_blob,
    GETextureMaterialSetV3 materials)
{
    GETexturedReplayResultV3 result;
    ge_texture_init_result(&result);

    /* V2 remains the authority for list traversal, transforms, vertex loads,
       and triangle order.  This call is read-only with respect to both input
       values and leaves all V1/V2 replay hashes untouched. */
    GEClassicReplayResultV2 classic = ge_classic_replay_prop_blob(prop_blob);
    result.commands_processed = classic.commands_processed;
    result.vertex_count = classic.vertex_count;
    result.triangle_count = classic.triangle_count;
    if (classic.status != GE_STATUS_OK) {
        ge_texture_set_error(&result,
                             classic.status,
                             classic.error_opcode,
                             classic.error_offset,
                             classic.error_list_handle,
                             classic.error_list_depth);
        return result;
    }

    GEStatusV1 status = ge_texture_validate_material_set(&materials);
    if (status != GE_STATUS_OK) {
        ge_texture_set_error(&result, status, 0u, 0u, 0u, 0u);
        return result;
    }

    GEClassicCommandV2 commands[GE_TEXTURE_PROP_COMMAND_COUNT];
    GEVertexV1 source_vertices[GE_TEXTURE_PROP_VERTEX_COUNT];
    status = ge_texture_read_prop(&prop_blob, commands, source_vertices);
    if (status != GE_STATUS_OK) {
        ge_texture_set_error(&result, status, 0u, 0u, UINT32_C(0x2000), 1u);
        return result;
    }

    GETextureMaterialStateV3 states[GE_TEXTURE_MATERIAL_CAPACITY];
    uint8_t state_valid[GE_TEXTURE_MATERIAL_CAPACITY];
    memset(states, 0, sizeof(states));
    memset(state_valid, 0, sizeof(state_valid));
    GETextureDrawContext contexts[GE_TEXTURE_DRAW_CAPACITY];
    uint32_t context_count = 0u;
    uint32_t cache_source[GE_CLASSIC_CACHE_CAPACITY];
    uint8_t cache_valid[GE_CLASSIC_CACHE_CAPACITY];
    memset(cache_source, 0, sizeof(cache_source));
    memset(cache_valid, 0, sizeof(cache_valid));

    const GETextureMaterialDescriptorV3 *current_descriptor = NULL;
    GETextureMaterialStateV3 current_state;
    memset(&current_state, 0, sizeof(current_state));
    uint32_t texture_sequence[GE_TEXTURE_MATERIAL_CAPACITY];
    uint32_t texture_sequence_count = 0u;
    uint64_t event_hash = ge_texture_hash_u64(ge_texture_hash_init(), classic.event_hash);

    for (uint32_t index = 0; index < GE_TEXTURE_PROP_COMMAND_COUNT; index++) {
        GEClassicCommandV2 command = commands[index];
        uint32_t opcode = command.w0 >> 24;
        uint32_t command_offset = (2u + index) * (uint32_t)sizeof(GEClassicCommandV2);
        event_hash = ge_texture_hash_u32(event_hash, command.w0);
        event_hash = ge_texture_hash_u32(event_hash, command.w1);

        switch (opcode) {
        case GE_TEXTURE_OP_SETTEX: {
            uint32_t texture_id = command.w1 & 0xfffu;
            if (!ge_texture_is_known_id(texture_id) ||
                !ge_texture_validate_settex_command(texture_id, command.w0,
                                                     command.w1) ||
                texture_sequence_count >= GE_TEXTURE_MATERIAL_CAPACITY) {
                ge_texture_set_error(&result, GE_STATUS_TEXTURE_FORMAT, opcode,
                                     command_offset, UINT32_C(0x2000), 1u);
                return result;
            }
            if (texture_sequence_count > 0u &&
                texture_id == texture_sequence[texture_sequence_count - 1u]) {
                ge_texture_set_error(&result, GE_STATUS_MALFORMED_STREAM, opcode,
                                     command_offset, UINT32_C(0x2000), 1u);
                return result;
            }
            texture_sequence[texture_sequence_count++] = texture_id;
            current_descriptor = ge_texture_find_descriptor(&materials, texture_id);
            if (current_descriptor == NULL) {
                ge_texture_set_error(&result, GE_STATUS_RESOURCE_NOT_FOUND, opcode,
                                     command_offset, UINT32_C(0x2000), 1u);
                return result;
            }
            status = ge_texture_build_material_state(current_descriptor,
                                                     command.w0,
                                                     command.w1,
                                                     &current_state);
            if (status != GE_STATUS_OK) {
                ge_texture_set_error(&result, status, opcode, command_offset,
                                     UINT32_C(0x2000), 1u);
                return result;
            }
            int material_index = ge_texture_material_index(texture_id);
            if (material_index < 0 || state_valid[material_index]) {
                ge_texture_set_error(&result, GE_STATUS_MALFORMED_STREAM, opcode,
                                     command_offset, UINT32_C(0x2000), 1u);
                return result;
            }
            states[material_index] = current_state;
            state_valid[material_index] = 1u;
            event_hash = ge_texture_hash_u32(event_hash, UINT32_C(0x54455853));
            event_hash = ge_texture_hash_u32(event_hash, texture_id);
            event_hash = ge_texture_hash_u64(event_hash, current_state.state_hash);
            break;
        }
        case GE_TEXTURE_OP_TEXTURE:
            if (command.w1 != UINT32_MAX) {
                ge_texture_set_error(&result, GE_STATUS_MALFORMED_STREAM, opcode,
                                     command_offset, UINT32_C(0x2000), 1u);
                return result;
            }
            if ((index == 2u && command.w0 != UINT32_C(0xbb003001)) ||
                (index == 14u && command.w0 != UINT32_C(0xbb083001)) ||
                (index == 17u && command.w0 != UINT32_C(0xbb082801))) {
                ge_texture_set_error(&result, GE_STATUS_MALFORMED_STREAM, opcode,
                                     command_offset, UINT32_C(0x2000), 1u);
                return result;
            }
            if (current_descriptor == NULL) {
                /* The leading gsSPTexture call configures the RSP texture
                   scale before the first custom G_SETTEX selection.  It has
                   no material descriptor to update. */
                event_hash = ge_texture_hash_u32(event_hash, UINT32_C(0x54455854));
                event_hash = ge_texture_hash_u32(event_hash, command.w0);
                break;
            }
            /* G_TEXTURE changes the runtime texture state but does not select
               a new source descriptor. */
            current_state.texture_state = command.w0 ^ command.w1;
            current_state.state_hash = ge_texture_rehash_material_state(current_descriptor,
                                                                         &current_state);
            int material_index = ge_texture_material_index(current_state.texture_id);
            if (material_index < 0) {
                ge_texture_set_error(&result, GE_STATUS_INVALID_STATE, opcode,
                                     command_offset, UINT32_C(0x2000), 1u);
                return result;
            }
            states[material_index] = current_state;
            event_hash = ge_texture_hash_u32(event_hash, UINT32_C(0x54455854));
            event_hash = ge_texture_hash_u32(event_hash, current_state.texture_id);
            event_hash = ge_texture_hash_u32(event_hash, current_state.texture_state);
            break;
        case GE_TEXTURE_OP_VTX: {
            uint32_t encoded = (command.w0 >> 16) & 0xffu;
            uint32_t count = (encoded >> 4) + 1u;
            uint32_t destination = encoded & 0xfu;
            uint32_t source_base;
            if (index == 7u) {
                source_base = 0u;
            } else if (index == 10u) {
                source_base = 16u;
            } else if (index == 19u) {
                source_base = 32u;
            } else {
                source_base = UINT32_MAX;
            }
            if (source_base == UINT32_MAX || destination + count > GE_CLASSIC_CACHE_CAPACITY ||
                source_base + count > GE_TEXTURE_PROP_VERTEX_COUNT ||
                (command.w0 & 0xffffu) != count * 16u) {
                ge_texture_set_error(&result, GE_STATUS_MALFORMED_STREAM, opcode,
                                     command_offset, UINT32_C(0x2000), 1u);
                return result;
            }
            for (uint32_t vertex = 0; vertex < count; vertex++) {
                cache_source[destination + vertex] = source_base + vertex;
                cache_valid[destination + vertex] = 1u;
            }
            break;
        }
        case GE_TEXTURE_OP_TRI4:
            if (current_descriptor == NULL || context_count >= GE_TEXTURE_DRAW_CAPACITY) {
                ge_texture_set_error(&result, GE_STATUS_INVALID_STATE, opcode,
                                     command_offset, UINT32_C(0x2000), 1u);
                return result;
            }
            contexts[context_count].command_offset = command_offset;
            contexts[context_count].material = current_state;
            memcpy(contexts[context_count].cache_source, cache_source,
                   sizeof(cache_source));
            memcpy(contexts[context_count].cache_valid, cache_valid,
                   sizeof(cache_valid));
            context_count++;
            break;
        case GE_TEXTURE_OP_PIPE_SYNC:
        case GE_TEXTURE_OP_MTX:
        case GE_TEXTURE_OP_SETOTHERMODE_H:
        case GE_TEXTURE_OP_SETOTHERMODE_L:
        case GE_TEXTURE_OP_ENDDL:
            break;
        default:
            /* In particular, generic G_SETTIMG/G_LOADBLOCK/G_LOADTLUT
               opcodes are not authored by this prop and are not synthesized
               here. */
            ge_texture_set_error(&result, GE_STATUS_UNSUPPORTED_COMMAND,
                                 opcode, command_offset, UINT32_C(0x2000), 1u);
            return result;
        }
    }

    if (texture_sequence_count != GE_TEXTURE_MATERIAL_CAPACITY ||
        texture_sequence[0] != GE_TEXTURE_ID_AMMOCRATE1 ||
        texture_sequence[1] != GE_TEXTURE_ID_AMMOTEXT765 ||
        texture_sequence[2] != GE_TEXTURE_ID_CRATEROPE ||
        context_count == 0u) {
        ge_texture_set_error(&result, GE_STATUS_MALFORMED_STREAM, GE_TEXTURE_OP_SETTEX,
                             GE_TEXTURE_PROP_COMMAND_OFFSET, UINT32_C(0x2000), 1u);
        return result;
    }
    for (uint32_t index = 0; index < GE_TEXTURE_MATERIAL_CAPACITY; index++) {
        if (!state_valid[index]) {
            ge_texture_set_error(&result, GE_STATUS_RESOURCE_NOT_FOUND,
                                 GE_TEXTURE_OP_SETTEX,
                                 GE_TEXTURE_PROP_COMMAND_OFFSET,
                                 UINT32_C(0x2000), 1u);
            return result;
        }
    }

    if (classic.draw_count == 0u || classic.draw_count > GE_TEXTURE_DRAW_CAPACITY ||
        classic.draw_count > context_count) {
        ge_texture_set_error(&result, GE_STATUS_REPLAY_BUDGET, 0u, 0u,
                             UINT32_C(0x2000), 1u);
        return result;
    }

    result.draw_count = classic.draw_count;
    result.material_hash = ge_texture_material_hash(&materials, states, state_valid);
    for (uint32_t draw_index = 0; draw_index < classic.draw_count; draw_index++) {
        const GEClassicDrawPacketV2 *source_draw = &classic.draws[draw_index];
        int context_index = ge_texture_find_context(contexts, context_count,
                                                    source_draw->source_command_offset);
        if (context_index < 0) {
            ge_texture_set_error(&result, GE_STATUS_INVALID_STATE, GE_TEXTURE_OP_TRI4,
                                 source_draw->source_command_offset,
                                 source_draw->source_list_handle,
                                 source_draw->list_depth);
            result.draw_count = 0u;
            return result;
        }
        const GETextureDrawContext *context = &contexts[context_index];
        GETexturedDrawPacketV3 *draw = &result.draws[draw_index];
        memset(draw, 0, sizeof(*draw));
        draw->header.abi_version = GE_NATIVE_ABI_VERSION;
        draw->header.struct_size = (uint32_t)sizeof(*draw);
        draw->packet_version = GE_TEXTURE_REPLAY_PACKET_VERSION;
        draw->source_list_handle = source_draw->source_list_handle;
        draw->source_command_offset = source_draw->source_command_offset;
        draw->list_depth = source_draw->list_depth;
        draw->material_flags = context->material.material_flags;
        draw->texture_id = context->material.texture_id;
        draw->vertex_count = source_draw->vertex_count;
        draw->triangle_count = source_draw->triangle_count;
        draw->material = context->material;
        draw->transform = source_draw->transform;
        if (draw->vertex_count > GE_CLASSIC_CACHE_CAPACITY ||
            draw->triangle_count > GE_CLASSIC_TRIANGLE_CAPACITY) {
            ge_texture_set_error(&result, GE_STATUS_REPLAY_BUDGET, GE_TEXTURE_OP_TRI4,
                                 draw->source_command_offset, draw->source_list_handle,
                                 draw->list_depth);
            result.draw_count = 0u;
            return result;
        }
        for (uint32_t vertex_index = 0; vertex_index < draw->vertex_count; vertex_index++) {
            const GEClassicClipVertexV2 *source_vertex = &source_draw->vertices[vertex_index];
            uint32_t cache_index = source_vertex->source_vertex;
            if (cache_index >= GE_CLASSIC_CACHE_CAPACITY ||
                !context->cache_valid[cache_index]) {
                ge_texture_set_error(&result, GE_STATUS_VERTEX_OUT_OF_RANGE,
                                     GE_TEXTURE_OP_TRI4,
                                     draw->source_command_offset,
                                     draw->source_list_handle,
                                     draw->list_depth);
                result.draw_count = 0u;
                return result;
            }
            uint32_t source_index = context->cache_source[cache_index];
            if (source_index >= GE_TEXTURE_PROP_VERTEX_COUNT) {
                ge_texture_set_error(&result, GE_STATUS_VERTEX_OUT_OF_RANGE,
                                     GE_TEXTURE_OP_TRI4,
                                     draw->source_command_offset,
                                     draw->source_list_handle,
                                     draw->list_depth);
                result.draw_count = 0u;
                return result;
            }
            const GEVertexV1 *raw = &source_vertices[source_index];
            GETexturedVertexV3 *destination = &draw->vertices[vertex_index];
            destination->x = source_vertex->x;
            destination->y = source_vertex->y;
            destination->z = source_vertex->z;
            destination->w = source_vertex->w;
            /* GE Vtx texture coordinates are signed s10.5 texel units. The
               Metal sampler consumes normalized coordinates, so normalize
               against the active source material dimensions. */
            uint32_t uv_width = ge_texture_expected_width(context->material.texture_id);
            uint32_t uv_height = ge_texture_expected_height(context->material.texture_id);
            if (uv_width == 0u || uv_height == 0u) {
                ge_texture_set_error(&result, GE_STATUS_TEXTURE_FORMAT,
                                     GE_TEXTURE_OP_SETTEX,
                                     draw->source_command_offset,
                                     draw->source_list_handle,
                                     draw->list_depth);
                result.draw_count = 0u;
                return result;
            }
            destination->s = ((float)raw->s / 32.0f) / (float)uv_width;
            destination->t = ((float)raw->t / 32.0f) / (float)uv_height;
            destination->r = source_vertex->r;
            destination->g = source_vertex->g;
            destination->b = source_vertex->b;
            destination->a = source_vertex->a;
            destination->source_vertex = cache_index;
            if (!isfinite(destination->x) || !isfinite(destination->y) ||
                !isfinite(destination->z) || !isfinite(destination->w) ||
                !isfinite(destination->s) || !isfinite(destination->t)) {
                ge_texture_set_error(&result, GE_STATUS_MALFORMED_STREAM,
                                     GE_TEXTURE_OP_TRI4,
                                     draw->source_command_offset,
                                     draw->source_list_handle,
                                     draw->list_depth);
                result.draw_count = 0u;
                return result;
            }
        }
        memcpy(draw->triangles, source_draw->triangles, sizeof(draw->triangles));

        uint64_t packet_hash = ge_texture_hash_init();
        packet_hash = ge_texture_hash_u32(packet_hash, draw->source_list_handle);
        packet_hash = ge_texture_hash_u32(packet_hash, draw->source_command_offset);
        packet_hash = ge_texture_hash_u32(packet_hash, draw->list_depth);
        packet_hash = ge_texture_hash_u32(packet_hash, draw->material_flags);
        packet_hash = ge_texture_hash_u32(packet_hash, draw->texture_id);
        packet_hash = ge_texture_hash_u32(packet_hash, draw->vertex_count);
        packet_hash = ge_texture_hash_u32(packet_hash, draw->triangle_count);
        packet_hash = ge_texture_hash_u64(packet_hash, draw->material.state_hash);
        packet_hash = ge_texture_hash_u64(packet_hash, draw->transform.transform_hash);
        packet_hash = ge_texture_hash_bytes(packet_hash, draw->vertices,
                                            sizeof(GETexturedVertexV3) * draw->vertex_count);
        packet_hash = ge_texture_hash_bytes(packet_hash, draw->triangles,
                                            sizeof(GEClassicTriangleV2) * draw->triangle_count);
        draw->packet_hash = packet_hash;
        result.packet_hash = ge_texture_hash_u64(result.packet_hash, packet_hash);
        result.packet_hash = ge_texture_hash_u32(result.packet_hash, draw->triangle_count);
    }
    result.event_hash = event_hash;
    result.status = GE_STATUS_OK;
    return result;
}
