#include "ge_texture_replay.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

/*
 * This file intentionally contains a bounded copy of the PD texture reader.
 * The command-line reader in tools/mktex predates the native ABI and uses
 * process globals, unbounded input, and zlib's 0x2000-byte input window.  The
 * native path keeps all state in automatic, value-only records instead.  The
 * source formats below are the three formats used by the ammo-crate prop.
 */

enum {
    GE_TEXTURE_MAX_HUFFMAN_SYMBOLS = 256u,
    GE_TEXTURE_MAX_HUFFMAN_NODES = GE_TEXTURE_MAX_HUFFMAN_SYMBOLS * 2u,
    GE_TEXTURE_MAX_IMAGE_PIXELS = GE_TEXTURE_DECODED_BYTE_CAPACITY / 4u,
    GE_DEFLATE_MAX_LIT_CODES = 288u,
    GE_DEFLATE_MAX_DIST_CODES = 32u,
    GE_DEFLATE_MAX_CODE_CODES = 19u,
    GE_DEFLATE_MAX_CODES = GE_DEFLATE_MAX_LIT_CODES + GE_DEFLATE_MAX_DIST_CODES,
};

typedef struct GETextureBitReader {
    const uint8_t *bytes;
    size_t byte_count;
    size_t byte_offset;
    uint32_t buffer;
    uint32_t bit_count;
    int failed;
} GETextureBitReader;

typedef struct GETextureHuffman {
    uint32_t symbol_count;
    uint32_t frequency[GE_TEXTURE_MAX_HUFFMAN_SYMBOLS];
    int16_t nodes[GE_TEXTURE_MAX_HUFFMAN_NODES][2];
    int32_t root;
    int failed;
} GETextureHuffman;

typedef struct GEDeflateBitReader {
    const uint8_t *bytes;
    size_t byte_count;
    size_t byte_offset;
    uint32_t buffer;
    uint32_t bit_count;
    int failed;
} GEDeflateBitReader;

typedef struct GEDeflateCodes {
    uint16_t code[GE_DEFLATE_MAX_CODES];
    uint8_t length[GE_DEFLATE_MAX_CODES];
    uint32_t count;
} GEDeflateCodes;

static uint64_t ge_texture_hash_byte(uint64_t hash, uint8_t value)
{
    return (hash ^ (uint64_t)value) * UINT64_C(1099511628211);
}

static uint64_t ge_texture_hash_bytes(const uint8_t *bytes, size_t count)
{
    uint64_t hash = UINT64_C(1469598103934665603);
    for (size_t index = 0u; index < count; index++) {
        hash = ge_texture_hash_byte(hash, bytes[index]);
    }
    return hash;
}

static void ge_texture_reader_init(GETextureBitReader *reader,
                                   const uint8_t *bytes,
                                   size_t byte_count)
{
    memset(reader, 0, sizeof(*reader));
    reader->bytes = bytes;
    reader->byte_count = byte_count;
}

/* The PD stream is MSB-first.  Keep at most 24 pending bits. */
static uint32_t ge_texture_read_bits(GETextureBitReader *reader, uint32_t count)
{
    uint32_t value;

    if (count == 0u) {
        return 0u;
    }
    if (count > 24u || reader->failed) {
        reader->failed = 1;
        return 0u;
    }
    while (reader->bit_count < count) {
        if (reader->byte_offset >= reader->byte_count) {
            reader->failed = 1;
            return 0u;
        }
        reader->buffer = (reader->buffer << 8u) | reader->bytes[reader->byte_offset++];
        reader->bit_count += 8u;
    }
    value = (reader->buffer >> (reader->bit_count - count));
    if (count < 32u) {
        value &= (UINT32_C(1) << count) - 1u;
    }
    reader->bit_count -= count;
    if (reader->bit_count == 0u) {
        reader->buffer = 0u;
    } else {
        reader->buffer &= (UINT32_C(1) << reader->bit_count) - 1u;
    }
    return value;
}

static uint32_t ge_texture_bitreader_aligned_offset(const GETextureBitReader *reader)
{
    if (reader->failed || reader->bit_count != 0u || reader->byte_offset > UINT32_MAX) {
        return UINT32_MAX;
    }
    return (uint32_t)reader->byte_offset;
}

static void ge_texture_huffman_init(GETextureHuffman *tree, uint32_t symbol_count)
{
    memset(tree, 0, sizeof(*tree));
    tree->symbol_count = symbol_count;
    tree->root = -1;
    for (uint32_t index = 0u; index < GE_TEXTURE_MAX_HUFFMAN_NODES; index++) {
        tree->nodes[index][0] = -1;
        tree->nodes[index][1] = -1;
    }
}

/* This selection order mirrors texInflateHuffman, including strict ties. */
static void ge_texture_huffman_select(const GETextureHuffman *tree,
                                      uint32_t *first,
                                      uint32_t *second,
                                      uint32_t *first_frequency,
                                      uint32_t *second_frequency)
{
    uint32_t minimum_one = 9999u;
    uint32_t minimum_two = 9999u;
    uint32_t minimum_one_index = 0u;
    uint32_t minimum_two_index = 0u;

    for (uint32_t index = 0u; index < tree->symbol_count; index++) {
        uint32_t frequency = tree->frequency[index];
        if (frequency < minimum_one) {
            if (minimum_two < minimum_one) {
                minimum_one = frequency;
                minimum_one_index = index;
            } else {
                minimum_two = frequency;
                minimum_two_index = index;
            }
        } else if (frequency < minimum_two) {
            minimum_two = frequency;
            minimum_two_index = index;
        }
    }
    *first = minimum_one_index;
    *second = minimum_two_index;
    *first_frequency = minimum_one;
    *second_frequency = minimum_two;
}

static int ge_texture_huffman_build(GETextureHuffman *tree)
{
    uint32_t first;
    uint32_t second;
    uint32_t first_frequency;
    uint32_t second_frequency;

    if (tree->symbol_count == 0u || tree->symbol_count > GE_TEXTURE_MAX_HUFFMAN_SYMBOLS) {
        tree->failed = 1;
        return 0;
    }
    if (tree->symbol_count == 1u) {
        tree->nodes[0][0] = (int16_t)(10000u);
        tree->root = 0;
        return 1;
    }

    ge_texture_huffman_select(tree, &first, &second, &first_frequency, &second_frequency);
    while (first_frequency != 9999u && second_frequency != 9999u) {
        uint32_t sum = first_frequency + second_frequency;
        uint32_t root_index;

        if (sum == 0u) {
            sum = 1u;
        }
        tree->frequency[first] = 9999u;
        tree->frequency[second] = 9999u;

        if (tree->nodes[first][0] < 0 && tree->nodes[first][1] < 0) {
            tree->nodes[first][0] = (int16_t)(first + 10000u);
            tree->root = (int32_t)first;
            tree->frequency[first] = sum;
            if (tree->nodes[second][0] < 0 && tree->nodes[second][1] < 0) {
                tree->nodes[first][1] = (int16_t)(second + 10000u);
            } else {
                tree->nodes[first][1] = (int16_t)second;
            }
        } else if (tree->nodes[second][0] < 0 && tree->nodes[second][1] < 0) {
            tree->nodes[second][0] = (int16_t)(second + 10000u);
            tree->root = (int32_t)second;
            tree->frequency[second] = sum;
            if (tree->nodes[first][0] < 0 && tree->nodes[first][1] < 0) {
                tree->nodes[second][1] = (int16_t)(first + 10000u);
            } else {
                tree->nodes[second][1] = (int16_t)first;
            }
        } else {
            for (root_index = 0u; root_index < tree->symbol_count; root_index++) {
                if (tree->nodes[root_index][0] < 0 &&
                    tree->nodes[root_index][1] < 0 &&
                    tree->frequency[root_index] >= 9999u) {
                    break;
                }
            }
            if (root_index >= tree->symbol_count) {
                tree->failed = 1;
                return 0;
            }
            tree->frequency[root_index] = sum;
            tree->nodes[root_index][0] = (int16_t)first;
            tree->nodes[root_index][1] = (int16_t)second;
            tree->root = (int32_t)root_index;
        }
        ge_texture_huffman_select(tree, &first, &second, &first_frequency, &second_frequency);
    }
    if (tree->root < 0 || tree->root >= (int32_t)tree->symbol_count) {
        tree->failed = 1;
        return 0;
    }
    return 1;
}

static int ge_texture_huffman_read(GETextureBitReader *reader,
                                   GETextureHuffman *tree,
                                   uint8_t *destination,
                                   uint32_t count)
{
    if (tree->failed || tree->root < 0) {
        return 0;
    }
    for (uint32_t output = 0u; output < count; output++) {
        int32_t index_or_value = tree->root;
        uint32_t depth = 0u;
        while (index_or_value < 10000) {
            uint32_t branch;
            if (index_or_value < 0 || index_or_value >= (int32_t)tree->symbol_count || depth++ >= tree->symbol_count) {
                return 0;
            }
            branch = ge_texture_read_bits(reader, 1u);
            if (reader->failed) {
                return 0;
            }
            index_or_value = tree->nodes[index_or_value][branch];
        }
        if (index_or_value < 10000 || index_or_value >= 10000 + (int32_t)tree->symbol_count) {
            return 0;
        }
        destination[output] = (uint8_t)(index_or_value - 10000);
    }
    return 1;
}

static int ge_texture_huffman_read_symbols(GETextureBitReader *reader,
                                           uint32_t symbol_count,
                                           uint8_t *destination,
                                           uint32_t count)
{
    GETextureHuffman tree;
    ge_texture_huffman_init(&tree, symbol_count);
    for (uint32_t index = 0u; index < symbol_count; index++) {
        tree.frequency[index] = ge_texture_read_bits(reader, 8u);
    }
    if (reader->failed || !ge_texture_huffman_build(&tree)) {
        return 0;
    }
    return ge_texture_huffman_read(reader, &tree, destination, count);
}

static void ge_texture_blur(uint8_t *pixels,
                            uint32_t width,
                            uint32_t height,
                            uint32_t method,
                            uint32_t channel_size)
{
    for (uint32_t y = 0u; y < height; y++) {
        for (uint32_t x = 0u; x < width; x++) {
            int32_t current = (int32_t)pixels[y * width + x] + (int32_t)(channel_size * 2u);
            int32_t left = x > 0u ? pixels[y * width + x - 1u] : 0;
            int32_t above = y > 0u ? pixels[(y - 1u) * width + x] : 0;
            int32_t above_left = x > 0u && y > 0u ? pixels[(y - 1u) * width + x - 1u] : 0;
            int32_t value;

            switch (method) {
                case 0u:
                    value = current + left;
                    break;
                case 1u:
                    value = current + above;
                    break;
                case 2u:
                    value = current + above_left;
                    break;
                case 3u:
                    value = current + left + above - above_left;
                    break;
                case 4u:
                    value = current + (above - above_left) / 2 + left;
                    break;
                case 5u:
                    value = current + (left - above_left) / 2 + above;
                    break;
                case 6u:
                    value = current + (left + above) / 2;
                    break;
                default:
                    value = 0;
                    break;
            }
            value %= (int32_t)channel_size;
            if (value < 0) {
                value += (int32_t)channel_size;
            }
            pixels[y * width + x] = (uint8_t)value;
        }
    }
}

static uint8_t ge_texture_scale_3bit(uint8_t value)
{
    return (uint8_t)((value & 7u) * 32u);
}

static void ge_texture_write_i8(uint8_t *destination, const uint8_t *source, uint32_t pixels)
{
    for (uint32_t index = 0u; index < pixels; index++) {
        uint8_t value = source[index];
        destination[index * 4u + 0u] = value;
        destination[index * 4u + 1u] = value;
        destination[index * 4u + 2u] = value;
        destination[index * 4u + 3u] = 255u;
    }
}

static void ge_texture_write_ia4_values(uint8_t *destination,
                                        const uint8_t *source,
                                        uint32_t pixels)
{
    for (uint32_t index = 0u; index < pixels; index++) {
        uint8_t value = source[index];
        destination[index * 4u + 0u] = ge_texture_scale_3bit((uint8_t)(value >> 1u));
        destination[index * 4u + 1u] = ge_texture_scale_3bit((uint8_t)(value >> 1u));
        destination[index * 4u + 2u] = ge_texture_scale_3bit((uint8_t)(value >> 1u));
        destination[index * 4u + 3u] = (value & 1u) != 0u ? 255u : 0u;
    }
}

static uint32_t ge_texture_reverse_bits(uint32_t value, uint32_t count)
{
    uint32_t result = 0u;
    for (uint32_t index = 0u; index < count; index++) {
        result = (result << 1u) | (value & 1u);
        value >>= 1u;
    }
    return result;
}

static void ge_deflate_reader_init(GEDeflateBitReader *reader,
                                   const uint8_t *bytes,
                                   size_t byte_count)
{
    memset(reader, 0, sizeof(*reader));
    reader->bytes = bytes;
    reader->byte_count = byte_count;
}

static uint32_t ge_deflate_read_bits(GEDeflateBitReader *reader, uint32_t count)
{
    uint32_t value;
    if (count == 0u) {
        return 0u;
    }
    if (count > 16u || reader->failed) {
        reader->failed = 1;
        return 0u;
    }
    while (reader->bit_count < count) {
        if (reader->byte_offset >= reader->byte_count) {
            reader->failed = 1;
            return 0u;
        }
        reader->buffer |= (uint32_t)reader->bytes[reader->byte_offset++] << reader->bit_count;
        reader->bit_count += 8u;
    }
    value = reader->buffer & ((UINT32_C(1) << count) - 1u);
    reader->buffer >>= count;
    reader->bit_count -= count;
    return value;
}

static void ge_deflate_align(GEDeflateBitReader *reader)
{
    uint32_t discard = reader->bit_count & 7u;
    (void)ge_deflate_read_bits(reader, discard);
}

static int ge_deflate_build_codes(const uint8_t *lengths,
                                  uint32_t count,
                                  GEDeflateCodes *codes)
{
    uint16_t counts[16] = {0};
    uint16_t next_code[16] = {0};
    uint32_t code = 0u;

    if (count == 0u || count > GE_DEFLATE_MAX_CODES) {
        return 0;
    }
    memset(codes, 0, sizeof(*codes));
    codes->count = count;
    for (uint32_t index = 0u; index < count; index++) {
        if (lengths[index] > 15u) {
            return 0;
        }
        if (lengths[index] != 0u) {
            counts[lengths[index]]++;
        }
    }
    for (uint32_t bits = 1u; bits <= 15u; bits++) {
        code = (code + counts[bits - 1u]) << 1u;
        next_code[bits] = (uint16_t)code;
        if (code + counts[bits] > (UINT32_C(1) << bits)) {
            return 0;
        }
    }
    for (uint32_t index = 0u; index < count; index++) {
        uint32_t length = lengths[index];
        if (length != 0u) {
            uint32_t canonical = next_code[length]++;
            codes->length[index] = (uint8_t)length;
            codes->code[index] = (uint16_t)ge_texture_reverse_bits(canonical, length);
        }
    }
    return 1;
}

static int ge_deflate_decode_symbol(GEDeflateBitReader *reader,
                                    const GEDeflateCodes *codes)
{
    uint32_t code = 0u;
    for (uint32_t length = 1u; length <= 15u; length++) {
        code |= ge_deflate_read_bits(reader, 1u) << (length - 1u);
        if (reader->failed) {
            return -1;
        }
        for (uint32_t symbol = 0u; symbol < codes->count; symbol++) {
            if (codes->length[symbol] == length && codes->code[symbol] == code) {
                return (int)symbol;
            }
        }
    }
    reader->failed = 1;
    return -1;
}

static int ge_deflate_fixed_codes(GEDeflateCodes *literal, GEDeflateCodes *distance)
{
    uint8_t literal_lengths[GE_DEFLATE_MAX_LIT_CODES] = {0};
    uint8_t distance_lengths[GE_DEFLATE_MAX_DIST_CODES] = {0};
    for (uint32_t index = 0u; index <= 143u; index++) {
        literal_lengths[index] = 8u;
    }
    for (uint32_t index = 144u; index <= 255u; index++) {
        literal_lengths[index] = 9u;
    }
    for (uint32_t index = 256u; index <= 279u; index++) {
        literal_lengths[index] = 7u;
    }
    for (uint32_t index = 280u; index < GE_DEFLATE_MAX_LIT_CODES; index++) {
        literal_lengths[index] = 8u;
    }
    for (uint32_t index = 0u; index < GE_DEFLATE_MAX_DIST_CODES; index++) {
        distance_lengths[index] = 5u;
    }
    return ge_deflate_build_codes(literal_lengths, GE_DEFLATE_MAX_LIT_CODES, literal) &&
           ge_deflate_build_codes(distance_lengths, GE_DEFLATE_MAX_DIST_CODES, distance);
}

static int ge_deflate_dynamic_codes(GEDeflateBitReader *reader,
                                    GEDeflateCodes *literal,
                                    GEDeflateCodes *distance)
{
    static const uint8_t order[GE_DEFLATE_MAX_CODE_CODES] = {
        16u, 17u, 18u, 0u, 8u, 7u, 9u, 6u, 10u, 5u,
        11u, 4u, 12u, 3u, 13u, 2u, 14u, 1u, 15u,
    };
    static const uint32_t max_lengths[3] = {0u, 0u, 0u};
    uint8_t code_lengths[GE_DEFLATE_MAX_CODE_CODES] = {0};
    uint8_t lengths[GE_DEFLATE_MAX_CODES] = {0};
    GEDeflateCodes code_length_codes;
    uint32_t literal_count = ge_deflate_read_bits(reader, 5u) + 257u;
    uint32_t distance_count = ge_deflate_read_bits(reader, 5u) + 1u;
    uint32_t code_length_count = ge_deflate_read_bits(reader, 4u) + 4u;
    uint32_t total;
    uint32_t cursor = 0u;

    (void)max_lengths;
    if (reader->failed || literal_count > GE_DEFLATE_MAX_LIT_CODES ||
        distance_count > GE_DEFLATE_MAX_DIST_CODES || code_length_count > GE_DEFLATE_MAX_CODE_CODES) {
        return 0;
    }
    for (uint32_t index = 0u; index < code_length_count; index++) {
        code_lengths[order[index]] = (uint8_t)ge_deflate_read_bits(reader, 3u);
    }
    if (reader->failed || !ge_deflate_build_codes(code_lengths, GE_DEFLATE_MAX_CODE_CODES, &code_length_codes)) {
        return 0;
    }
    total = literal_count + distance_count;
    while (cursor < total) {
        int symbol = ge_deflate_decode_symbol(reader, &code_length_codes);
        if (symbol < 0) {
            return 0;
        }
        if (symbol <= 15) {
            lengths[cursor++] = (uint8_t)symbol;
        } else if (symbol == 16) {
            uint32_t repeat;
            uint8_t previous;
            if (cursor == 0u) {
                return 0;
            }
            repeat = ge_deflate_read_bits(reader, 2u) + 3u;
            previous = lengths[cursor - 1u];
            if (reader->failed || repeat > total - cursor) {
                return 0;
            }
            for (uint32_t index = 0u; index < repeat; index++) {
                lengths[cursor++] = previous;
            }
        } else if (symbol == 17) {
            uint32_t repeat = ge_deflate_read_bits(reader, 3u) + 3u;
            if (reader->failed || repeat > total - cursor) {
                return 0;
            }
            cursor += repeat;
        } else if (symbol == 18) {
            uint32_t repeat = ge_deflate_read_bits(reader, 7u) + 11u;
            if (reader->failed || repeat > total - cursor) {
                return 0;
            }
            cursor += repeat;
        } else {
            return 0;
        }
    }
    return ge_deflate_build_codes(lengths, literal_count, literal) &&
           ge_deflate_build_codes(&lengths[literal_count], distance_count, distance);
}

static int ge_deflate_inflate_raw(const uint8_t *source,
                                  size_t source_count,
                                  uint8_t *destination,
                                  uint32_t destination_capacity,
                                  uint32_t *destination_count)
{
    static const uint16_t length_base[29] = {
        3u, 4u, 5u, 6u, 7u, 8u, 9u, 10u, 11u, 13u,
        15u, 17u, 19u, 23u, 27u, 31u, 35u, 43u, 51u, 59u,
        67u, 83u, 99u, 115u, 131u, 163u, 195u, 227u, 258u,
    };
    static const uint8_t length_extra[29] = {
        0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 1u, 1u,
        1u, 1u, 2u, 2u, 2u, 2u, 3u, 3u, 3u, 3u,
        4u, 4u, 4u, 4u, 5u, 5u, 5u, 5u, 0u,
    };
    static const uint16_t distance_base[30] = {
        1u, 2u, 3u, 4u, 5u, 7u, 9u, 13u, 17u, 25u,
        33u, 49u, 65u, 97u, 129u, 193u, 257u, 385u, 513u, 769u,
        1025u, 1537u, 2049u, 3073u, 4097u, 6145u, 8193u, 12289u, 16385u, 24577u,
    };
    static const uint8_t distance_extra[30] = {
        0u, 0u, 0u, 0u, 1u, 1u, 2u, 2u, 3u, 3u,
        4u, 4u, 5u, 5u, 6u, 6u, 7u, 7u, 8u, 8u,
        9u, 9u, 10u, 10u, 11u, 11u, 12u, 12u, 13u, 13u,
    };
    GEDeflateBitReader reader;
    uint32_t output = 0u;
    int final = 0;

    ge_deflate_reader_init(&reader, source, source_count);
    while (!final) {
        uint32_t type;
        final = (int)ge_deflate_read_bits(&reader, 1u);
        type = ge_deflate_read_bits(&reader, 2u);
        if (reader.failed) {
            return 0;
        }
        if (type == 0u) {
            uint32_t length;
            uint32_t inverse;
            ge_deflate_align(&reader);
            length = ge_deflate_read_bits(&reader, 16u);
            inverse = ge_deflate_read_bits(&reader, 16u);
            if (reader.failed || ((length ^ inverse) & 0xffffu) != 0xffffu ||
                length > destination_capacity - output) {
                return 0;
            }
            for (uint32_t index = 0u; index < length; index++) {
                destination[output++] = (uint8_t)ge_deflate_read_bits(&reader, 8u);
            }
            if (reader.failed) {
                return 0;
            }
        } else if (type == 1u || type == 2u) {
            GEDeflateCodes literal;
            GEDeflateCodes distance;
            int codes_ok = type == 1u ? ge_deflate_fixed_codes(&literal, &distance) :
                                       ge_deflate_dynamic_codes(&reader, &literal, &distance);
            if (!codes_ok) {
                return 0;
            }
            for (;;) {
                int symbol = ge_deflate_decode_symbol(&reader, &literal);
                if (symbol < 0) {
                    return 0;
                }
                if (symbol < 256) {
                    if (output >= destination_capacity) {
                        return 0;
                    }
                    destination[output++] = (uint8_t)symbol;
                } else if (symbol == 256) {
                    break;
                } else if (symbol <= 285) {
                    uint32_t length_index = (uint32_t)symbol - 257u;
                    uint32_t length = length_base[length_index] +
                                      ge_deflate_read_bits(&reader, length_extra[length_index]);
                    int distance_symbol = ge_deflate_decode_symbol(&reader, &distance);
                    uint32_t distance_value;
                    if (distance_symbol < 0 || distance_symbol >= 30) {
                        return 0;
                    }
                    distance_value = distance_base[distance_symbol] +
                                     ge_deflate_read_bits(&reader, distance_extra[distance_symbol]);
                    if (reader.failed || distance_value == 0u || distance_value > output ||
                        length > destination_capacity - output) {
                        return 0;
                    }
                    for (uint32_t index = 0u; index < length; index++) {
                        destination[output] = destination[output - distance_value];
                        output++;
                    }
                } else {
                    return 0;
                }
            }
        } else {
            return 0;
        }
    }
    if (reader.failed) {
        return 0;
    }
    *destination_count = output;
    return 1;
}

static int ge_texture_decode_rzip(const uint8_t *source,
                                  uint32_t source_count,
                                  uint8_t *destination,
                                  uint32_t expected_count)
{
    uint32_t header_size;
    uint32_t actual_count = 0u;

    if (source_count < 2u || source[0] != 0x11u || (source[1] != 0x72u && source[1] != 0x73u)) {
        return 0;
    }
    header_size = source[1] == 0x72u ? 2u : 5u;
    if (source_count <= header_size ||
        !ge_deflate_inflate_raw(source + header_size,
                                 (size_t)source_count - header_size,
                                 destination,
                                 expected_count,
                                 &actual_count)) {
        return 0;
    }
    return actual_count == expected_count;
}

static uint8_t ge_texture_palette_channel(uint16_t value, uint32_t shift)
{
    return (uint8_t)(((value >> shift) & 0x1fu) * 8u);
}

static GEStatusV1 ge_texture_validate_dimensions(uint32_t width,
                                                 uint32_t height,
                                                 uint32_t *pixel_count)
{
    if (width == 0u || height == 0u) {
        return GE_STATUS_INVALID_ARGUMENT;
    }
    if (width > UINT32_MAX / height) {
        return GE_STATUS_TEXTURE_OVERFLOW;
    }
    *pixel_count = width * height;
    if (*pixel_count > GE_TEXTURE_MAX_IMAGE_PIXELS) {
        return GE_STATUS_TEXTURE_OVERFLOW;
    }
    return GE_STATUS_OK;
}

static GEStatusV1 ge_texture_decode_non_zlib_image(GETextureBitReader *reader,
                                                   GETextureDecodeResultV3 *result,
                                                   uint32_t mip,
                                                   uint32_t *pixel_offset)
{
    uint32_t format = ge_texture_read_bits(reader, 4u);
    uint32_t width = ge_texture_read_bits(reader, 8u);
    uint32_t height = ge_texture_read_bits(reader, 8u);
    uint32_t compression = ge_texture_read_bits(reader, 4u);
    uint32_t pixels;
    uint8_t scratch[GE_TEXTURE_MAX_IMAGE_PIXELS];
    GEStatusV1 status;

    if (reader->failed) {
        return GE_STATUS_MALFORMED_STREAM;
    }
    status = ge_texture_validate_dimensions(width, height, &pixels);
    if (status != GE_STATUS_OK) {
        return status;
    }
    if ((uint64_t)(*pixel_offset) + (uint64_t)pixels * 4u > GE_TEXTURE_DECODED_BYTE_CAPACITY) {
        return GE_STATUS_TEXTURE_OVERFLOW;
    }
    result->mip_offsets[mip] = *pixel_offset;
    result->mip_widths[mip] = width;
    result->mip_heights[mip] = height;
    if (mip == 0u) {
        result->source_format = format;
        result->source_compression = compression;
        result->width = width;
        result->height = height;
    }
    if (format == GE_TEXTURE_FORMAT_I8 && compression == GE_TEXTURE_COMPRESSION_HUFFMAN_BLUR) {
        uint32_t blur_method = ge_texture_read_bits(reader, 3u);
        if (reader->failed || blur_method > 6u ||
            !ge_texture_huffman_read_symbols(reader, GE_TEXTURE_MAX_HUFFMAN_SYMBOLS, scratch, pixels)) {
            return GE_STATUS_TEXTURE_COMPRESSION;
        }
        ge_texture_blur(scratch, width, height, blur_method, GE_TEXTURE_MAX_HUFFMAN_SYMBOLS);
        ge_texture_write_i8(&result->pixels[*pixel_offset], scratch, pixels);
    } else if (format == GE_TEXTURE_FORMAT_IA4 && compression == GE_TEXTURE_COMPRESSION_HUFFMAN_LOOKUP) {
        uint32_t colours = ge_texture_read_bits(reader, 11u);
        uint8_t lookup[GE_TEXTURE_MAX_HUFFMAN_SYMBOLS];
        if (reader->failed || colours == 0u || colours > GE_TEXTURE_MAX_HUFFMAN_SYMBOLS) {
            return GE_STATUS_TEXTURE_COMPRESSION;
        }
        for (uint32_t index = 0u; index < colours; index++) {
            lookup[index] = (uint8_t)ge_texture_read_bits(reader, 4u);
        }
        if (reader->failed ||
            !ge_texture_huffman_read_symbols(reader, colours, scratch, pixels)) {
            return GE_STATUS_TEXTURE_COMPRESSION;
        }
        for (uint32_t index = 0u; index < pixels; index++) {
            if (scratch[index] >= colours || lookup[scratch[index]] > 0x0fu) {
                return GE_STATUS_TEXTURE_COMPRESSION;
            }
            scratch[index] = lookup[scratch[index]];
        }
        /* Convert the mapped IA4 values directly to RGBA8. */
        ge_texture_write_ia4_values(&result->pixels[*pixel_offset], scratch, pixels);
    } else {
        if (format != GE_TEXTURE_FORMAT_I8 && format != GE_TEXTURE_FORMAT_IA4) {
            return GE_STATUS_TEXTURE_FORMAT;
        }
        return GE_STATUS_TEXTURE_COMPRESSION;
    }
    *pixel_offset += pixels * 4u;
    return GE_STATUS_OK;
}

static GEStatusV1 ge_texture_decode_zlib_texture(GETextureBitReader *reader,
                                                 GETextureDecodeResultV3 *result,
                                                 uint32_t image_count,
                                                 uint32_t *pixel_offset)
{
    uint32_t format = ge_texture_read_bits(reader, 8u);
    uint32_t palette_count = ge_texture_read_bits(reader, 8u) + 1u;
    uint16_t palette[GE_TEXTURE_PALETTE_ENTRY_CAPACITY];
    GEStatusV1 status;

    if (reader->failed || format != GE_TEXTURE_FORMAT_RGBA16_CI8 || palette_count == 0u ||
        palette_count > GE_TEXTURE_PALETTE_ENTRY_CAPACITY) {
        return reader->failed ? GE_STATUS_MALFORMED_STREAM : GE_STATUS_TEXTURE_FORMAT;
    }
    memset(palette, 0, sizeof(palette));
    memset(result->palette_rgba, 0, sizeof(result->palette_rgba));
    for (uint32_t index = 0u; index < palette_count; index++) {
        uint16_t value = (uint16_t)ge_texture_read_bits(reader, 16u);
        palette[index] = value;
        result->palette_rgba[index * 4u + 0u] = ge_texture_palette_channel(value, 11u);
        result->palette_rgba[index * 4u + 1u] = ge_texture_palette_channel(value, 6u);
        result->palette_rgba[index * 4u + 2u] = ge_texture_palette_channel(value, 1u);
        result->palette_rgba[index * 4u + 3u] = (value & 1u) != 0u ? 255u : 0u;
    }
    result->palette_count = palette_count;
    for (uint32_t mip = 0u; mip < image_count; mip++) {
        uint32_t width = ge_texture_read_bits(reader, 8u);
        uint32_t height = ge_texture_read_bits(reader, 8u);
        uint32_t pixels;
        uint8_t indices[GE_TEXTURE_MAX_IMAGE_PIXELS];
        uint32_t compressed_offset;

        if (reader->failed) {
            return GE_STATUS_MALFORMED_STREAM;
        }
        status = ge_texture_validate_dimensions(width, height, &pixels);
        if (status != GE_STATUS_OK) {
            return status;
        }
        if ((uint64_t)(*pixel_offset) + (uint64_t)pixels * 4u > GE_TEXTURE_DECODED_BYTE_CAPACITY) {
            return GE_STATUS_TEXTURE_OVERFLOW;
        }
        compressed_offset = ge_texture_bitreader_aligned_offset(reader);
        if (compressed_offset == UINT32_MAX || compressed_offset > reader->byte_count ||
            !ge_texture_decode_rzip(reader->bytes + compressed_offset,
                                     (uint32_t)(reader->byte_count - compressed_offset),
                                     indices,
                                     pixels)) {
            return GE_STATUS_TEXTURE_COMPRESSION;
        }
        result->mip_offsets[mip] = *pixel_offset;
        result->mip_widths[mip] = width;
        result->mip_heights[mip] = height;
        if (mip == 0u) {
            result->source_format = format;
            result->source_compression = 0u;
            result->width = width;
            result->height = height;
        }
        for (uint32_t index = 0u; index < pixels; index++) {
            uint32_t palette_index = indices[index];
            if (palette_index >= palette_count) {
                return GE_STATUS_TEXTURE_COMPRESSION;
            }
            memcpy(&result->pixels[*pixel_offset + index * 4u],
                   &result->palette_rgba[palette_index * 4u],
                   4u);
        }
        *pixel_offset += pixels * 4u;
        /* The source zlib path currently has one image.  A second image would
         * begin immediately after the previous raw stream's unused bytes;
         * keeping it bounded requires an explicit stream-end offset, so reject
         * multi-image RZIP containers rather than guessing. */
        if (mip + 1u < image_count) {
            return GE_STATUS_TEXTURE_COMPRESSION;
        }
    }
    (void)palette;
    return GE_STATUS_OK;
}

GETextureDecodeResultV3 ge_texture_decode_v3(GETextureSourceBlobV3 blob)
{
    GETextureDecodeResultV3 result;
    GETextureBitReader reader;
    GEStatusV1 status;
    uint32_t explicit_lods;
    uint32_t is_zlib;
    uint32_t encoded_lods;
    uint32_t lod_count;
    uint32_t pixel_offset = 0u;

    memset(&result, 0, sizeof(result));
    result.header.abi_version = GE_TEXTURE_REPLAY_ABI_VERSION;
    result.header.struct_size = (uint32_t)sizeof(result);
    result.status = GE_STATUS_OK;
    result.texture_id = blob.texture_id;

    if (blob.header.abi_version != GE_TEXTURE_REPLAY_ABI_VERSION) {
        result.status = GE_STATUS_INVALID_VERSION;
        return result;
    }
    if (blob.header.struct_size != sizeof(blob)) {
        result.status = GE_STATUS_INVALID_SIZE;
        return result;
    }
    if (blob.reserved != 0u || blob.byte_count == 0u) {
        result.status = GE_STATUS_INVALID_ARGUMENT;
        return result;
    }
    if (blob.byte_count > GE_TEXTURE_SOURCE_BLOB_CAPACITY) {
        result.status = GE_STATUS_TEXTURE_OVERFLOW;
        return result;
    }
    result.source_hash = ge_texture_hash_bytes(blob.bytes, blob.byte_count);
    ge_texture_reader_init(&reader, blob.bytes, blob.byte_count);
    explicit_lods = ge_texture_read_bits(&reader, 1u);
    is_zlib = ge_texture_read_bits(&reader, 1u);
    encoded_lods = ge_texture_read_bits(&reader, 6u);
    if (reader.failed) {
        result.status = GE_STATUS_MALFORMED_STREAM;
        return result;
    }
    if (is_zlib != 0u) {
        lod_count = explicit_lods != 0u ? encoded_lods : 1u;
        if (reader.failed || lod_count == 0u || lod_count > GE_TEXTURE_MIP_CAPACITY) {
            result.status = GE_STATUS_MALFORMED_STREAM;
            return result;
        }
        status = ge_texture_decode_zlib_texture(&reader, &result, lod_count, &pixel_offset);
    } else {
        lod_count = explicit_lods != 0u ? encoded_lods : 1u;
        if (reader.failed || lod_count == 0u || lod_count > GE_TEXTURE_MIP_CAPACITY) {
            result.status = GE_STATUS_MALFORMED_STREAM;
            return result;
        }
        for (uint32_t mip = 0u; mip < lod_count; mip++) {
            status = ge_texture_decode_non_zlib_image(&reader, &result, mip, &pixel_offset);
            if (status != GE_STATUS_OK) {
                result.status = status;
                return result;
            }
        }
    }
    if (status != GE_STATUS_OK || reader.failed || result.width == 0u || result.height == 0u) {
        result.status = status != GE_STATUS_OK ? status : GE_STATUS_MALFORMED_STREAM;
        return result;
    }
    result.mip_count = lod_count;
    result.pixel_byte_count = pixel_offset;
    result.decoded_hash = ge_texture_hash_bytes(result.pixels, pixel_offset);
    return result;
}
