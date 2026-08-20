#!/usr/bin/env python3
"""Bounded source-faithful decoder for Rare/PD global image streams.

The checked-in ``src/game/image.c`` reader is a bit-oriented container reader.
It is intentionally not a PNG reader: a stream may contain packed I/IA
pixels, N64 5551 palettes, Huffman/RLE channels, lookup tables, and optional
RZIP-compressed palette indices.  This module keeps that distinction explicit
and is preparation-only.  It never opens a ROM or depends on a filesystem
path at runtime.

``decode_stream`` returns both the source packed representation and a
canonical, top-left-origin RGBA8 view.  ``storage`` is the representation
after the source alternate-row byte swap (when the stream has explicit LODs),
which is useful to a texture uploader.  ``pixels`` is the logical packed
representation before that swap.  No source pointer, address, or Metal object
is represented by the API.

The implementation mirrors the checked-in portable decoder and the PD reader
in ``tools/mktex/src/libpdtex/reader.c``.  Bounds are stricter than the N64
runtime: malformed streams raise ``PDDecodeError`` instead of reading past a
buffer or hanging in a default compression branch.
"""

from __future__ import annotations

import hashlib
import math
import struct
import zlib
from dataclasses import dataclass
from enum import IntEnum
from typing import Iterable, Sequence


MAX_IMAGES = 7
MAX_DIMENSION = 255
MAX_PIXELS = 0x2000
MAX_HUFFMAN_SYMBOLS = 2048
MAX_HUFFMAN_NODES = 2048
MAX_RZIP_OUTPUT = 0x2000


class PDDecodeError(ValueError):
    """A malformed or unsupported PD stream."""


class PDFormat(IntEnum):
    RGBA32 = 0
    RGBA16 = 1
    RGB24 = 2
    RGB15 = 3
    IA16 = 4
    IA8 = 5
    IA4 = 6
    I8 = 7
    I4 = 8
    RGBA16_CI8 = 9
    RGBA16_CI4 = 10
    IA16_CI8 = 11
    IA16_CI4 = 12


class PDCompression(IntEnum):
    # 0 and 1 are both source uncompressed variants.
    UNCOMPRESSED0 = 0
    UNCOMPRESSED1 = 1
    HUFFMAN = 2
    HUFFMAN_PER_CHANNEL = 3
    RLE = 4
    LOOKUP = 5
    HUFFMAN_LOOKUP = 6
    RLE_LOOKUP = 7
    HUFFMAN_BLUR = 8
    RLE_BLUR = 9


# These tables are copied from src/game/image.c.  Keep them public so a
# preparation caller can validate a source row without duplicating IDs.
FORMAT_CHANNELS = (4, 3, 3, 3, 2, 2, 1, 1, 1, 1, 1, 1, 1)
FORMAT_HAS_1BIT_ALPHA = (False, True, False, False, False, False, True, False, False, False, False, False, False)
FORMAT_CHANNEL_SIZE = (256, 32, 256, 32, 256, 16, 8, 256, 16, 256, 16, 256, 16)
FORMAT_BITS_PER_PIXEL = (32, 16, 24, 15, 16, 8, 4, 8, 4, 16, 16, 16, 16)


@dataclass(frozen=True)
class PDImage:
    level: int
    format: PDFormat
    compression: int
    width: int
    height: int
    # ``pixels`` is tightly logical packed source pixels (with row padding
    # matching image.c, but before the explicit-LOD alternate-row swap).
    pixels: bytes
    # ``storage`` is what image.c leaves in its destination after the source
    # swap.  It has the same row stride as ``pixels``.
    storage: bytes
    # Correctly decoded visual pixels, vertically flipped like pdtex_flip().
    rgba8: bytes
    # Per-image lookup values used by lookup compression, in source bit form.
    lookup: tuple[int, ...] = ()
    # For CI streams, this is the exact raw palette (big-endian 16-bit words)
    # and its RGBA8/GA8-expanded form.  Non-CI images leave both empty.
    palette_raw: bytes = b""
    palette_rgba8: bytes = b""

    @property
    def pixel_count(self) -> int:
        return self.width * self.height

    @property
    def row_stride(self) -> int:
        return _row_stride(self.width, self.format)


@dataclass(frozen=True)
class PDTexture:
    explicit_lods: bool
    is_zlib: bool
    encoded_lods: int
    images: tuple[PDImage, ...]
    palette_raw: bytes
    palette_rgba8: bytes
    source_sha256: str
    consumed_bytes: int

    @property
    def width(self) -> int:
        return self.images[0].width if self.images else 0

    @property
    def height(self) -> int:
        return self.images[0].height if self.images else 0

    @property
    def format(self) -> PDFormat:
        return self.images[0].format

    @property
    def mip_count(self) -> int:
        return len(self.images)


class _BitReader:
    """MSB-first reader matching texReadBits, with strict source bounds."""

    __slots__ = ("data", "offset", "buffer", "bits")

    def __init__(self, data: bytes, offset: int = 0):
        self.data = data
        self.offset = offset
        self.buffer = 0
        self.bits = 0

    def read(self, count: int) -> int:
        if count < 0 or count > 32:
            raise PDDecodeError(f"bit count {count} is outside the bounded reader")
        if count == 0:
            return 0
        while self.bits < count:
            if self.offset >= len(self.data):
                raise PDDecodeError("PD bitstream ended while reading a field")
            self.buffer = (self.buffer << 8) | self.data[self.offset]
            self.offset += 1
            self.bits += 8
        value = (self.buffer >> (self.bits - count)) & ((1 << count) - 1)
        self.bits -= count
        self.buffer &= (1 << self.bits) - 1 if self.bits else 0
        return value

    def require_aligned(self) -> int:
        if self.bits:
            raise PDDecodeError("PD compressed payload is not byte aligned")
        return self.offset

    def reset(self, offset: int) -> None:
        if offset < 0 or offset > len(self.data):
            raise PDDecodeError("PD stream reset is outside source bounds")
        self.offset = offset
        self.buffer = 0
        self.bits = 0


def _dimensions(width: int, height: int) -> int:
    if not (1 <= width <= MAX_DIMENSION and 1 <= height <= MAX_DIMENSION):
        raise PDDecodeError(f"PD dimensions {width}x{height} are outside the source guard")
    pixels = width * height
    if pixels > MAX_PIXELS:
        raise PDDecodeError(f"PD image has {pixels} pixels; source cap is {MAX_PIXELS}")
    return pixels


def _align(value: int, alignment: int) -> int:
    return (value + alignment - 1) & ~(alignment - 1)


def _row_stride(width: int, fmt: PDFormat) -> int:
    if fmt in (PDFormat.RGBA32, PDFormat.RGB24):
        return _align(width, 4) * 4
    if fmt in (PDFormat.RGBA16, PDFormat.RGB15, PDFormat.IA16):
        return _align(width, 4) * 2
    if fmt in (PDFormat.IA8, PDFormat.I8, PDFormat.RGBA16_CI8, PDFormat.IA16_CI8):
        return _align(width, 8)
    if fmt in (PDFormat.IA4, PDFormat.I4, PDFormat.RGBA16_CI4, PDFormat.IA16_CI4):
        return _align(width, 16) // 2
    raise PDDecodeError(f"unsupported PD format {fmt}")


def _packed_row_stride(width: int, fmt: PDFormat) -> int:
    """Logical row stride used by the PD command-line reader."""
    if fmt in (PDFormat.RGBA32,):
        return width * 4
    if fmt in (PDFormat.RGB24,):
        return width * 3
    if fmt in (PDFormat.RGBA16, PDFormat.RGB15, PDFormat.IA16):
        return width * 2
    if fmt in (PDFormat.IA8, PDFormat.I8, PDFormat.RGBA16_CI8, PDFormat.IA16_CI8):
        return width
    if fmt in (PDFormat.IA4, PDFormat.I4, PDFormat.RGBA16_CI4, PDFormat.IA16_CI4):
        return (width + 1) // 2
    raise PDDecodeError(f"unsupported PD format {fmt}")


def _format_value(value: int) -> PDFormat:
    try:
        return PDFormat(value)
    except ValueError as error:
        raise PDDecodeError(f"PD format {value} is unsupported") from error


def _read_u16_be(data: bytes, offset: int) -> int:
    if offset + 2 > len(data):
        raise PDDecodeError("PD 16-bit value exceeds stream bounds")
    return (data[offset] << 8) | data[offset + 1]


def _huffman_decode(reader: _BitReader, frequencies: Sequence[int], count: int) -> list[int]:
    if not (1 <= len(frequencies) <= MAX_HUFFMAN_SYMBOLS):
        raise PDDecodeError("PD Huffman symbol count is outside the source guard")
    if count < 0 or count > MAX_PIXELS * 4:
        raise PDDecodeError("PD Huffman output count is outside the source guard")
    # This intentionally follows the source's list-of-frequencies tree build,
    # including its strict < tie behavior.  Do not replace with heapq: equal
    # frequencies affect the bitstream's tree shape.
    freq = list(frequencies) + [9999] * (MAX_HUFFMAN_NODES - len(frequencies))
    nodes = [[-1, -1] for _ in range(MAX_HUFFMAN_NODES)]
    symbols = len(frequencies)

    def select() -> tuple[int, int, int, int]:
        first_freq = second_freq = 9999
        first_index = second_index = 0
        for index in range(symbols):
            value = freq[index]
            if value < first_freq:
                if second_freq < first_freq:
                    first_freq, first_index = value, index
                else:
                    second_freq, second_index = value, index
            elif value < second_freq:
                second_freq, second_index = value, index
        return first_index, second_index, first_freq, second_freq

    first, second, first_freq, second_freq = select()
    root = -1
    while first_freq != 9999 and second_freq != 9999:
        total = first_freq + second_freq
        if total == 0:
            total = 1
        freq[first] = 9999
        freq[second] = 9999
        if nodes[first][0] < 0 and nodes[first][1] < 0:
            nodes[first][0] = first + 10000
            root = first
            freq[first] = total
            nodes[first][1] = second + 10000 if nodes[second][0] < 0 and nodes[second][1] < 0 else second
        elif nodes[second][0] < 0 and nodes[second][1] < 0:
            nodes[second][0] = second + 10000
            root = second
            freq[second] = total
            nodes[second][1] = first + 10000 if nodes[first][0] < 0 and nodes[first][1] < 0 else first
        else:
            root = next((candidate for candidate in range(MAX_HUFFMAN_NODES)
                         if nodes[candidate][0] < 0 and nodes[candidate][1] < 0 and freq[candidate] >= 9999), -1)
            if root < 0:
                raise PDDecodeError("PD Huffman tree exceeded node capacity")
            freq[root] = total
            nodes[root][0], nodes[root][1] = first, second
        first, second, first_freq, second_freq = select()
    if root < 0:
        # The source does not special-case a one-symbol tree.  Accepting it is
        # safe and makes malformed-but-unambiguous fixtures deterministic.
        if symbols == 1:
            return [0] * count
        raise PDDecodeError("PD Huffman tree has no root")

    output: list[int] = []
    for _ in range(count):
        index = root
        depth = 0
        while index < 10000:
            if index < 0 or index >= MAX_HUFFMAN_NODES or depth >= MAX_HUFFMAN_NODES:
                raise PDDecodeError("PD Huffman traversal exceeded bounds")
            index = nodes[index][reader.read(1)]
            depth += 1
        if not (10000 <= index < 10000 + symbols):
            raise PDDecodeError("PD Huffman leaf is outside the source alphabet")
        output.append(index - 10000)
    return output


def _rle_decode(reader: _BitReader, count: int) -> list[int]:
    bt_size = reader.read(3)
    run_size = reader.read(3)
    block_size = reader.read(4)
    if block_size == 0 or block_size > 16:
        raise PDDecodeError(f"PD RLE block size {block_size} is invalid")
    cost = bt_size + run_size + block_size + 1
    fudge = 0
    while cost > 0:
        cost -= block_size + 1
        fudge += 1
    output: list[int] = []
    while len(output) < count:
        if reader.read(1) == 0:
            output.append(reader.read(block_size))
            continue
        start = len(output) - reader.read(bt_size) - 1
        run_count = reader.read(run_size) + fudge
        if start < 0 or run_count <= 0:
            raise PDDecodeError("PD RLE backreference is outside decoded output")
        for index in range(start, start + run_count):
            # Source RLE permits self-referential runs: after copying the
            # first block, the newly appended block may be copied again.
            if index < 0 or index >= len(output) or len(output) >= count:
                raise PDDecodeError("PD RLE run exceeds requested output")
            output.append(output[index])
        # Source encoding requires a literal after every run.
        if len(output) < count:
            output.append(reader.read(block_size))
    return output


def _lookup_bits(num_colours: int) -> int:
    if num_colours <= 0 or num_colours > MAX_HUFFMAN_SYMBOLS:
        raise PDDecodeError("PD lookup colour count is outside the source guard")
    decimal = num_colours - 1
    count = 0
    while decimal > 0:
        decimal >>= 1
        count += 1
    return count


def _read_lookup(reader: _BitReader, bits_per_pixel: int) -> tuple[int, ...]:
    count = reader.read(11)
    if count <= 0 or count > MAX_HUFFMAN_SYMBOLS:
        raise PDDecodeError("PD lookup table count is outside the source guard")
    return tuple(reader.read(bits_per_pixel) for _ in range(count))


def _blur(values: list[int], width: int, height: int, method: int, channel_size: int) -> None:
    if method > 6:
        raise PDDecodeError(f"PD blur method {method} is unsupported")
    for y in range(height):
        for x in range(width):
            current = values[y * width + x] + channel_size * 2
            left = values[y * width + x - 1] if x else 0
            above = values[(y - 1) * width + x] if y else 0
            above_left = values[(y - 1) * width + x - 1] if x and y else 0
            if method == 0:
                value = current + left
            elif method == 1:
                value = current + above
            elif method == 2:
                value = current + above_left
            elif method == 3:
                value = current + left + above - above_left
            elif method == 4:
                value = current + ((above - above_left) // 2) + left
            elif method == 5:
                value = current + ((left - above_left) // 2) + above
            else:
                value = current + ((left + above) // 2)
            values[y * width + x] = value % channel_size


def _read_uncompressed(reader: _BitReader, width: int, height: int, fmt: PDFormat) -> bytes:
    stride = _row_stride(width, fmt)
    output = bytearray(stride * height)
    if fmt in (PDFormat.RGBA32, PDFormat.RGB24):
        for y in range(height):
            row = y * stride
            for x in range(width):
                if fmt == PDFormat.RGBA32:
                    value = (reader.read(16) << 16) | reader.read(16)
                    output[row + x * 4 : row + x * 4 + 4] = value.to_bytes(4, "big")
                else:
                    value = reader.read(24)
                    output[row + x * 4 : row + x * 4 + 4] = value.to_bytes(3, "big") + b"\xff"
    elif fmt in (PDFormat.RGBA16, PDFormat.IA16):
        for y in range(height):
            row = y * stride
            for x in range(width):
                output[row + x * 2 : row + x * 2 + 2] = reader.read(16).to_bytes(2, "big")
    elif fmt == PDFormat.RGB15:
        for y in range(height):
            row = y * stride
            for x in range(width):
                output[row + x * 2 : row + x * 2 + 2] = ((reader.read(15) << 1) | 1).to_bytes(2, "big")
    elif fmt in (PDFormat.IA8, PDFormat.I8):
        for y in range(height):
            row = y * stride
            for x in range(width):
                output[row + x] = reader.read(8)
    elif fmt in (PDFormat.IA4, PDFormat.I4):
        for y in range(height):
            row = y * stride
            for x in range(0, width, 2):
                output[row + x // 2] = reader.read(8)
    else:
        raise PDDecodeError(f"uncompressed lookup format {fmt} is invalid")
    return bytes(output)


def _channels_to_native(channels: Sequence[int], width: int, height: int, fmt: PDFormat) -> bytes:
    stride = _row_stride(width, fmt)
    output = bytearray(stride * height)
    pixels = width * height
    if fmt in (PDFormat.RGBA32, PDFormat.RGB24):
        for y in range(height):
            row = y * stride
            for x in range(width):
                pos = y * width + x
                if fmt == PDFormat.RGBA32:
                    values = channels[pos], channels[pos + pixels], channels[pos + pixels * 2], channels[pos + pixels * 3]
                    output[row + x * 4 : row + x * 4 + 4] = bytes(values)
                else:
                    output[row + x * 4 : row + x * 4 + 4] = bytes((channels[pos], channels[pos + pixels], channels[pos + pixels * 2], 255))
    elif fmt == PDFormat.RGBA16:
        alpha_base = pixels * 3
        for y in range(height):
            row = y * stride
            for x in range(width):
                pos = y * width + x
                value = ((channels[pos] & 31) << 11) | ((channels[pos + pixels] & 31) << 6) | ((channels[pos + pixels * 2] & 31) << 1) | (channels[alpha_base + pos] & 1)
                output[row + x * 2 : row + x * 2 + 2] = value.to_bytes(2, "big")
    elif fmt == PDFormat.RGB15:
        for y in range(height):
            row = y * stride
            for x in range(width):
                pos = y * width + x
                value = ((channels[pos] & 31) << 11) | ((channels[pos + pixels] & 31) << 6) | ((channels[pos + pixels * 2] & 31) << 1) | 1
                output[row + x * 2 : row + x * 2 + 2] = value.to_bytes(2, "big")
    elif fmt == PDFormat.IA16:
        for y in range(height):
            row = y * stride
            for x in range(width):
                pos = y * width + x
                output[row + x * 2 : row + x * 2 + 2] = bytes((channels[pos], channels[pos + pixels]))
    elif fmt == PDFormat.IA8:
        for y in range(height):
            row = y * stride
            for x in range(width):
                pos = y * width + x
                output[row + x] = ((channels[pos] & 15) << 4) | (channels[pos + pixels] & 15)
    elif fmt == PDFormat.I8:
        for y in range(height):
            row = y * stride
            output[row : row + width] = bytes(channels[y * width : (y + 1) * width])
    elif fmt == PDFormat.IA4:
        alpha_base = pixels * 3
        for y in range(height):
            row = y * stride
            for x in range(0, width, 2):
                p0 = y * width + x
                p1 = min(p0 + 1, y * width + width - 1)
                first = ((channels[p0] & 7) << 5) | ((channels[alpha_base + p0] & 1) << 4)
                second = ((channels[p1] & 7) << 1) | (channels[alpha_base + p1] & 1)
                output[row + x // 2] = first | second
    elif fmt == PDFormat.I4:
        for y in range(height):
            row = y * stride
            for x in range(0, width, 2):
                p0 = y * width + x
                p1 = min(p0 + 1, y * width + width - 1)
                output[row + x // 2] = ((channels[p0] & 15) << 4) | (channels[p1] & 15)
    else:
        raise PDDecodeError(f"channel format {fmt} cannot be packed")
    return bytes(output)


def _lookup_to_native(indices: Sequence[int], lookup: Sequence[int], width: int, height: int, fmt: PDFormat) -> bytes:
    count = len(lookup)
    if not count:
        raise PDDecodeError("PD lookup table is empty")
    if any(index < 0 or index >= count for index in indices):
        raise PDDecodeError("PD lookup index exceeds table bounds")
    stride = _row_stride(width, fmt)
    output = bytearray(stride * height)
    for y in range(height):
        row = y * stride
        for x in range(width):
            value = lookup[indices[y * width + x]]
            if fmt in (PDFormat.RGBA32,):
                output[row + x * 4 : row + x * 4 + 4] = value.to_bytes(4, "big")
            elif fmt == PDFormat.RGB24:
                output[row + x * 4 : row + x * 4 + 4] = (value & 0xFFFFFF).to_bytes(3, "big") + b"\xff"
            elif fmt in (PDFormat.RGBA16, PDFormat.IA16, PDFormat.RGB15):
                if fmt == PDFormat.RGB15:
                    value = (value << 1) | 1
                output[row + x * 2 : row + x * 2 + 2] = value.to_bytes(2, "big")
            elif fmt in (PDFormat.RGBA16_CI8, PDFormat.IA16_CI8):
                output[row + x] = value & 0xFF
            elif fmt in (PDFormat.RGBA16_CI4, PDFormat.IA16_CI4):
                if x % 2 == 0:
                    output[row + x // 2] = (value & 0xF) << 4
                else:
                    output[row + x // 2] |= value & 0xF
            elif fmt in (PDFormat.IA8, PDFormat.I8):
                output[row + x] = value & 0xFF
            elif fmt in (PDFormat.IA4, PDFormat.I4):
                if x % 2 == 0:
                    output[row + x // 2] = (value & 0xF) << 4
                else:
                    output[row + x // 2] |= value & 0xF
            else:
                raise PDDecodeError(f"lookup format {fmt} cannot be packed")
    return bytes(output)


def _swap_alt_rows(data: bytes, width: int, height: int, fmt: PDFormat) -> bytes:
    """Mirror texSwapAltRowBytes, including its 16-byte/8-byte groups."""
    output = bytearray(data)
    stride = _row_stride(width, fmt)
    if fmt in (PDFormat.RGBA32, PDFormat.RGB24):
        group = 16
        half = 8
    else:
        group = 8
        half = 4
    for y in range(1, height, 2):
        start = y * stride
        end = start + stride
        for offset in range(start, end, group):
            if offset + group <= end:
                output[offset : offset + half], output[offset + half : offset + group] = output[offset + half : offset + group], output[offset : offset + half]
    return bytes(output)


def _rgba8_from_native(data: bytes, width: int, height: int, fmt: PDFormat, palette: Sequence[int] = ()) -> bytes:
    stride = _row_stride(width, fmt)
    output = bytearray(width * height * 4)
    for y in range(height):
        row = y * stride
        for x in range(width):
            dst = (y * width + x) * 4
            if fmt == PDFormat.RGBA32:
                output[dst : dst + 4] = data[row + x * 4 : row + x * 4 + 4]
            elif fmt == PDFormat.RGB24:
                output[dst : dst + 4] = data[row + x * 4 : row + x * 4 + 3] + b"\xff"
            elif fmt == PDFormat.RGBA16:
                value = _read_u16_be(data, row + x * 2)
                output[dst : dst + 4] = bytes((((value >> 11) & 31) * 8, ((value >> 6) & 31) * 8, ((value >> 1) & 31) * 8, 255 if value & 1 else 0))
            elif fmt == PDFormat.RGB15:
                value = _read_u16_be(data, row + x * 2)
                output[dst : dst + 4] = bytes((((value >> 11) & 31) * 8, ((value >> 6) & 31) * 8, ((value >> 1) & 31) * 8, 255))
            elif fmt == PDFormat.IA16:
                intensity, alpha = data[row + x * 2 : row + x * 2 + 2]
                output[dst : dst + 4] = bytes((intensity, intensity, intensity, alpha))
            elif fmt == PDFormat.IA8:
                value = data[row + x]
                intensity, alpha = (value >> 4) * 16, (value & 15) * 16
                output[dst : dst + 4] = bytes((intensity, intensity, intensity, alpha))
            elif fmt == PDFormat.I8:
                value = data[row + x]
                output[dst : dst + 4] = bytes((value, value, value, 255))
            elif fmt == PDFormat.IA4:
                value = (data[row + x // 2] >> 4) if x % 2 == 0 else (data[row + x // 2] & 15)
                output[dst : dst + 4] = bytes((((value >> 1) & 7) * 32,) * 3 + (255 if value & 1 else 0,))
            elif fmt == PDFormat.I4:
                value = (data[row + x // 2] >> 4) if x % 2 == 0 else (data[row + x // 2] & 15)
                intensity = value * 16
                output[dst : dst + 4] = bytes((intensity, intensity, intensity, 255))
            elif fmt in (PDFormat.RGBA16_CI8, PDFormat.IA16_CI8):
                index = data[row + x]
                if index >= len(palette):
                    raise PDDecodeError("PD CI8 index exceeds palette")
                output[dst : dst + 4] = _palette_rgba(palette[index], fmt)
            elif fmt in (PDFormat.RGBA16_CI4, PDFormat.IA16_CI4):
                index = (data[row + x // 2] >> 4) if x % 2 == 0 else (data[row + x // 2] & 15)
                if index >= len(palette):
                    raise PDDecodeError("PD CI4 index exceeds palette")
                output[dst : dst + 4] = _palette_rgba(palette[index], fmt)
            else:
                raise PDDecodeError(f"format {fmt} has no RGBA8 conversion")
    return bytes(output)


def _palette_rgba(value: int, fmt: PDFormat) -> bytes:
    if fmt in (PDFormat.RGBA16_CI8, PDFormat.RGBA16_CI4):
        return bytes((((value >> 11) & 31) * 8, ((value >> 6) & 31) * 8, ((value >> 1) & 31) * 8, 255 if value & 1 else 0))
    intensity, alpha = (value >> 8) & 0xFF, value & 0xFF
    return bytes((intensity, intensity, intensity, alpha))


def _vertical_flip(rgba8: bytes, width: int, height: int) -> bytes:
    row = width * 4
    return b"".join(rgba8[y * row : (y + 1) * row] for y in range(height - 1, -1, -1))


def _shrink_i4(data: bytes, width: int, height: int, fmt: PDFormat) -> tuple[int, int, bytes]:
    """Port the packed I4/IA4 branches of texShrinkNonPaletted exactly."""
    next_width = max(1, (width + 1) // 2)
    next_height = max(1, (height + 1) // 2)
    source_aligned = _align(width, 16)
    destination_aligned = _align(next_width, 16)
    source_stride = source_aligned // 2
    destination_stride = destination_aligned // 2
    output = bytearray(destination_stride * next_height)
    for i in range(0, height, 2):
        next_row = i + 1
        top_base = i * source_stride
        bottom_base = next_row * source_stride if next_row < height else 0
        out_base = (i // 2) * destination_stride
        for j in range(0, source_aligned, 4):
            source_offset = j // 2
            if source_offset + 1 >= source_stride:
                continue
            tl = data[top_base + source_offset]
            tr = data[bottom_base + source_offset]
            bl = data[top_base + source_offset + 1]
            br = data[bottom_base + source_offset + 1]
            if fmt == PDFormat.IA4:
                colour = ((((tl >> 5) & 7) + ((tl >> 1) & 7) + ((tr >> 5) & 7) + ((tr >> 1) & 7)) << 3) & 0xE0
                colour |= (((((bl >> 5) & 7) + ((bl >> 1) & 7) + ((br >> 5) & 7) + ((br >> 1) & 7)) >> 1) & 0x0E)
                alpha = (((((tl >> 4) & 1) + (tl & 1) + ((tr >> 4) & 1) + (tr & 1) + 1) << 2) & 0x10)
                alpha |= (((((bl >> 4) & 1) + (bl & 1) + ((br >> 4) & 1) + (br & 1) + 1) >> 2) & 1)
            else:
                colour = ((((tl >> 4) & 15) + (tl & 15) + ((tr >> 4) & 15) + (tr & 15)) << 2) & 0xF0
                alpha = ((((bl >> 4) & 15) + (bl & 15) + ((br >> 4) & 15) + (br & 15)) >> 2) & 15
            output[out_base + (j // 4)] = colour | alpha
    return next_width, next_height, bytes(output)


def _native_components(data: bytes, width: int, height: int, fmt: PDFormat) -> list[tuple[int, ...]]:
    stride = _row_stride(width, fmt)
    components: list[tuple[int, ...]] = []
    for y in range(height):
        row = y * stride
        for x in range(width):
            if fmt == PDFormat.RGBA32:
                components.append(tuple(data[row + x * 4 : row + x * 4 + 4]))
            elif fmt == PDFormat.RGB24:
                components.append(tuple(data[row + x * 4 : row + x * 4 + 3]))
            elif fmt in (PDFormat.RGBA16, PDFormat.RGB15):
                value = _read_u16_be(data, row + x * 2)
                components.append(((value >> 11) & 31, (value >> 6) & 31, (value >> 1) & 31, value & 1))
            elif fmt == PDFormat.IA16:
                components.append(tuple(data[row + x * 2 : row + x * 2 + 2]))
            elif fmt == PDFormat.IA8:
                value = data[row + x]
                components.append(((value >> 4) & 15, value & 15))
            elif fmt == PDFormat.I8:
                components.append((data[row + x],))
            elif fmt in (PDFormat.IA4, PDFormat.I4):
                value = (data[row + x // 2] >> 4) if x % 2 == 0 else data[row + x // 2] & 15
                components.append(((value >> 1) & 7, value & 1) if fmt == PDFormat.IA4 else (value,))
            else:
                raise PDDecodeError(f"native component conversion does not support {fmt}")
    return components


def _encode_components(components: Sequence[tuple[int, ...]], width: int, height: int, fmt: PDFormat) -> bytes:
    if fmt in (PDFormat.IA4, PDFormat.I4):
        raise PDDecodeError("packed IA4/I4 components require the exact packed shrink path")
    stride = _row_stride(width, fmt)
    output = bytearray(stride * height)
    for y in range(height):
        row = y * stride
        for x in range(width):
            value = components[y * width + x]
            if fmt == PDFormat.RGBA32:
                output[row + x * 4 : row + x * 4 + 4] = bytes(value)
            elif fmt == PDFormat.RGB24:
                output[row + x * 4 : row + x * 4 + 4] = bytes(value[:3]) + b"\xff"
            elif fmt == PDFormat.RGBA16:
                packed = ((value[0] & 31) << 11) | ((value[1] & 31) << 6) | ((value[2] & 31) << 1) | (value[3] & 1)
                output[row + x * 2 : row + x * 2 + 2] = packed.to_bytes(2, "big")
            elif fmt == PDFormat.RGB15:
                packed = ((value[0] & 31) << 11) | ((value[1] & 31) << 6) | ((value[2] & 31) << 1) | 1
                output[row + x * 2 : row + x * 2 + 2] = packed.to_bytes(2, "big")
            elif fmt == PDFormat.IA16:
                output[row + x * 2 : row + x * 2 + 2] = bytes(value)
            elif fmt == PDFormat.IA8:
                output[row + x] = ((value[0] & 15) << 4) | (value[1] & 15)
            elif fmt == PDFormat.I8:
                output[row + x] = value[0] & 0xFF
    return bytes(output)


def _shrink_nonpaletted(data: bytes, width: int, height: int, fmt: PDFormat) -> tuple[int, int, bytes]:
    if fmt in (PDFormat.IA4, PDFormat.I4):
        return _shrink_i4(data, width, height, fmt)
    next_width = max(1, (width + 1) // 2)
    next_height = max(1, (height + 1) // 2)
    source = _native_components(data, width, height, fmt)
    reduced: list[tuple[int, ...]] = []
    for y in range(next_height):
        for x in range(next_width):
            coords = ((min(height - 1, y * 2), min(width - 1, x * 2)),
                      (min(height - 1, y * 2), min(width - 1, x * 2 + 1)),
                      (min(height - 1, y * 2 + 1), min(width - 1, x * 2)),
                      (min(height - 1, y * 2 + 1), min(width - 1, x * 2 + 1)))
            samples = [source[sy * width + sx] for sy, sx in coords]
            if fmt in (PDFormat.RGBA32, PDFormat.RGB24):
                values = tuple(sum(sample[channel] for sample in samples) >> 2 for channel in range(3))
                alpha = (sum(sample[3] for sample in samples) + 1) >> 2 if fmt == PDFormat.RGBA32 else 255
                reduced.append(values + (alpha,))
            elif fmt in (PDFormat.RGBA16, PDFormat.RGB15):
                values = tuple(sum(sample[channel] for sample in samples) >> 2 for channel in range(3))
                alpha = (sum(sample[3] for sample in samples) + 2) >> 2 if fmt == PDFormat.RGBA16 else 1
                reduced.append(values + (alpha & 1,))
            elif fmt == PDFormat.IA16:
                reduced.append(((sum(sample[0] for sample in samples)) >> 2, (sum(sample[1] for sample in samples) + 1) >> 2))
            elif fmt == PDFormat.IA8:
                reduced.append(((sum(sample[0] for sample in samples) >> 2) & 15, (sum(sample[1] for sample in samples) + 1) >> 2 & 15))
            elif fmt == PDFormat.I8:
                reduced.append(((sum(sample[0] for sample in samples) + 1) >> 2,))
    return next_width, next_height, _encode_components(reduced, next_width, next_height, fmt)


def _closest_palette_rgba(palette: Sequence[int], red: int, green: int, blue: int, alpha: int) -> int:
    target = ((red & 31) << 11) | ((green & 31) << 6) | ((blue & 31) << 1) | (alpha & 1)
    for index, value in enumerate(palette):
        if value == target:
            return index
    target_magnitude = red * red + green * green + blue * blue + alpha * 961
    low, high = 0, len(palette) - 1
    while high - low >= 2:
        middle = (high + low) >> 1
        value = palette[middle]
        magnitude = ((value >> 11) & 31) ** 2 + ((value >> 6) & 31) ** 2 + ((value >> 1) & 31) ** 2 + (value & 1) * 961
        if magnitude < target_magnitude:
            low = middle
        elif target_magnitude < magnitude:
            high = middle
        else:
            low = high = middle
    low = max(0, high - 4)
    high = min(len(palette) - 1, high + 4)
    best_index, best_value = 0, 999999
    for index in range(low, high + 1):
        value = palette[index]
        distance = (((value >> 11) & 31) - red) ** 2 + (((value >> 6) & 31) - green) ** 2 + (((value >> 1) & 31) - blue) ** 2
        if (value & 1) != alpha:
            distance += 961
        if distance < best_value:
            best_index, best_value = index, distance
    return best_index


def _closest_palette_ia(palette: Sequence[int], intensity: int, alpha: int) -> int:
    target = ((intensity & 0xFF) << 8) | (alpha & 0xFF)
    for index, value in enumerate(palette):
        if value == target:
            return index
    target_magnitude = intensity * intensity + alpha * alpha
    low, high = 0, len(palette) - 1
    while high - low >= 2:
        middle = (high + low) >> 1
        value = palette[middle]
        magnitude = ((value >> 8) & 0xFF) ** 2 + (value & 0xFF) ** 2
        if magnitude < target_magnitude:
            low = middle
        elif target_magnitude < magnitude:
            high = middle
        else:
            low = high = middle
    low = max(0, high - 4)
    high = min(len(palette) - 1, high + 4)
    best_index, best_value = 0, 999999
    for index in range(low, high + 1):
        value = palette[index]
        distance = (((value >> 8) & 0xFF) - intensity) ** 2 + ((value & 0xFF) - alpha) ** 2
        if distance < best_value:
            best_index, best_value = index, distance
    return best_index


def _shrink_paletted(data: bytes, width: int, height: int, fmt: PDFormat, palette: Sequence[int]) -> tuple[int, int, bytes]:
    if not palette:
        raise PDDecodeError("palette-aware source mip generation has no palette")
    next_width, next_height = max(1, (width + 1) // 2), max(1, (height + 1) // 2)
    stride = _row_stride(width, fmt)
    out_stride = _row_stride(next_width, fmt)
    output = bytearray(out_stride * next_height)

    def index_at(x: int, y: int) -> int:
        x = min(width - 1, x)
        y = min(height - 1, y)
        row = y * stride
        if fmt in (PDFormat.RGBA16_CI8, PDFormat.IA16_CI8):
            return data[row + x]
        value = data[row + x // 2]
        return (value >> 4) & 15 if x % 2 == 0 else value & 15

    for y in range(next_height):
        for x in range(next_width):
            source_indices = [index_at(x * 2 + dx, y * 2 + dy) for dy in (0, 1) for dx in (0, 1)]
            colours = [palette[index] if index < len(palette) else 0 for index in source_indices]
            if fmt in (PDFormat.RGBA16_CI8, PDFormat.RGBA16_CI4):
                red = sum((value >> 11) & 31 for value in colours) >> 2
                green = sum((value >> 6) & 31 for value in colours) >> 2
                blue = sum((value >> 1) & 31 for value in colours) >> 2
                alpha = (sum(value & 1 for value in colours) + 2) >> 2
                mapped = _closest_palette_rgba(palette, red, green, blue, alpha)
            else:
                intensity = sum((value >> 8) & 0xFF for value in colours) >> 2
                alpha = (sum(value & 0xFF for value in colours) + 1) >> 2
                mapped = _closest_palette_ia(palette, intensity, alpha)
            if fmt in (PDFormat.RGBA16_CI8, PDFormat.IA16_CI8):
                output[y * out_stride + x] = mapped
            elif x % 2 == 0:
                output[y * out_stride + x // 2] = (mapped & 15) << 4
            else:
                output[y * out_stride + x // 2] |= mapped & 15
    return next_width, next_height, bytes(output)


def generate_source_mips(source: bytes, count: int, *, flip: bool = True) -> tuple[PDImage, ...]:
    """Return source-generated LODs for an implicit-lod stream.

    Explicit streams are returned verbatim and cannot be silently expanded.
    Implicit streams use the checked-in image.c quantization/edge rules for
    non-paletted formats and the palette requantization/edge rules for CI
    formats; no untyped RGBA average is used.
    """
    if count < 1 or count > MAX_IMAGES:
        raise PDDecodeError("source-generated mip count is outside bounds")
    texture = decode_stream(source, flip=False)
    if texture.explicit_lods:
        if count != texture.mip_count:
            raise PDDecodeError("explicit source mip count cannot be regenerated")
        return tuple(_apply_image_views(image, True, flip) for image in texture.images)
    base = texture.images[0]
    images = [base]
    current = base
    for level in range(1, count):
        if current.format in (PDFormat.RGBA16_CI8, PDFormat.RGBA16_CI4, PDFormat.IA16_CI8, PDFormat.IA16_CI4):
            width, height, storage = _shrink_paletted(current.pixels, current.width, current.height, current.format, current.lookup)
        else:
            width, height, storage = _shrink_nonpaletted(current.pixels, current.width, current.height, current.format)
        rgba = _rgba8_from_native(storage, width, height, current.format, current.lookup)
        if flip:
            rgba = _vertical_flip(rgba, width, height)
        current = PDImage(level, current.format, current.compression, width, height, storage, storage, rgba, current.lookup, current.palette_raw, current.palette_rgba8)
        images.append(current)
    if flip:
        images[0] = _apply_image_views(images[0], False, True)
    return tuple(images)


def _decode_non_zlib_image(reader: _BitReader, level: int) -> tuple[PDImage, int]:
    fmt = _format_value(reader.read(4))
    width = reader.read(8)
    height = reader.read(8)
    compression = reader.read(4)
    pixels = _dimensions(width, height)
    lookup: tuple[int, ...] = ()
    if compression in (PDCompression.UNCOMPRESSED0, PDCompression.UNCOMPRESSED1):
        logical = _read_uncompressed(reader, width, height, fmt)
    elif compression in (PDCompression.HUFFMAN, PDCompression.HUFFMAN_PER_CHANNEL, PDCompression.RLE,
                         PDCompression.HUFFMAN_BLUR, PDCompression.RLE_BLUR):
        method = compression
        blur_method = reader.read(3) if compression in (PDCompression.HUFFMAN_BLUR, PDCompression.RLE_BLUR) else None
        channels_count = FORMAT_CHANNELS[fmt]
        if compression in (PDCompression.HUFFMAN, PDCompression.HUFFMAN_BLUR):
            values = _huffman_decode(reader, [reader.read(8) for _ in range(FORMAT_CHANNEL_SIZE[fmt])], channels_count * pixels)
        elif compression == PDCompression.HUFFMAN_PER_CHANNEL:
            values = []
            for channel in range(channels_count):
                values.extend(_huffman_decode(reader, [reader.read(8) for _ in range(FORMAT_CHANNEL_SIZE[fmt])], pixels))
        elif compression in (PDCompression.RLE, PDCompression.RLE_BLUR):
            values = _rle_decode(reader, channels_count * pixels)
        else:
            values = []
        if FORMAT_HAS_1BIT_ALPHA[fmt]:
            # image.c deliberately reads alpha at channel offset 3*pixel_count
            # for both RGBA16 and IA4.  Retain that source layout exactly.
            values.extend([0] * max(0, 3 * pixels - len(values)))
            values.extend(reader.read(1) for _ in range(pixels))
        if blur_method is not None:
            _blur(values, width, FORMAT_CHANNELS[fmt] * height, blur_method, FORMAT_CHANNEL_SIZE[fmt])
        logical = _channels_to_native(values, width, height, fmt)
    elif compression in (PDCompression.LOOKUP, PDCompression.HUFFMAN_LOOKUP, PDCompression.RLE_LOOKUP):
        lookup = _read_lookup(reader, FORMAT_BITS_PER_PIXEL[fmt])
        if compression == PDCompression.LOOKUP:
            indices = [reader.read(_lookup_bits(len(lookup))) for _ in range(pixels)]
        elif compression == PDCompression.HUFFMAN_LOOKUP:
            indices = _huffman_decode(reader, [reader.read(8) for _ in range(len(lookup))], pixels)
        else:
            indices = _rle_decode(reader, pixels)
        logical = _lookup_to_native(indices, lookup, width, height, fmt)
    else:
        raise PDDecodeError(f"PD compression {compression} is unsupported")
    storage = logical
    # Source texInflateNonZlib swaps each explicit image when the stream's
    # header requested explicit LODs.  The caller applies this after parsing.
    return PDImage(level, fmt, int(compression), width, height, logical, storage, b"", lookup), reader.offset


def _rzip_decode(data: bytes, offset: int, expected: int) -> tuple[bytes, int]:
    if offset + 2 > len(data) or data[offset : offset + 2] != b"\x11\x72" and data[offset : offset + 2] != b"\x11\x73":
        raise PDDecodeError("PD RZIP header is missing")
    prefix = 2 if data[offset + 1] == 0x72 else 5
    compressed_start = offset + prefix
    if compressed_start >= len(data):
        raise PDDecodeError("PD RZIP payload is truncated")
    decoder = zlib.decompressobj(-15)
    try:
        output = decoder.decompress(data[compressed_start:], MAX_RZIP_OUTPUT + 1)
        if len(output) > MAX_RZIP_OUTPUT or len(output) != expected or not decoder.eof:
            raise PDDecodeError("PD RZIP output length or terminator is invalid")
    except zlib.error as error:
        raise PDDecodeError("PD RZIP DEFLATE payload is malformed") from error
    consumed = len(data[compressed_start:]) - len(decoder.unused_data)
    return output, compressed_start + consumed


def _decode_zlib_images(data: bytes, reader: _BitReader, explicit: bool, lod: int) -> tuple[list[PDImage], bytes, bytes]:
    format_id = reader.read(8)
    fmt = _format_value(format_id)
    if fmt not in (PDFormat.RGBA16_CI8, PDFormat.RGBA16_CI4, PDFormat.IA16_CI8, PDFormat.IA16_CI4):
        raise PDDecodeError(f"PD zlib format {fmt} is not a palette format")
    colour_count = reader.read(8) + 1
    if colour_count > 256:
        raise PDDecodeError("PD zlib palette exceeds 256 entries")
    palette_values = [reader.read(16) for _ in range(colour_count)]
    palette_raw = b"".join(value.to_bytes(2, "big") for value in palette_values)
    palette_rgba = b"".join(_palette_rgba(value, fmt) for value in palette_values)
    count = lod if explicit and lod else 1
    images: list[PDImage] = []
    for level in range(count):
        width = reader.read(8)
        height = reader.read(8)
        pixels = _dimensions(width, height)
        compressed_offset = reader.require_aligned()
        indices, next_offset = _rzip_decode(data, compressed_offset, pixels if fmt in (PDFormat.RGBA16_CI8, PDFormat.IA16_CI8) else (width + 1) // 2 * height)
        identity = tuple(range(colour_count))
        if fmt in (PDFormat.RGBA16_CI4, PDFormat.IA16_CI4):
            expanded = bytearray(width * height)
            for index in range(width * height):
                value = indices[index // 2]
                expanded[index] = (value >> 4) & 15 if index % 2 == 0 else value & 15
            logical = _lookup_to_native(expanded, identity, width, height, fmt)
        else:
            logical = _lookup_to_native(indices, identity, width, height, fmt)
        storage = logical
        rgba = _vertical_flip(_rgba8_from_native(logical, width, height, fmt, palette_values), width, height)
        images.append(PDImage(level, fmt, 0, width, height, logical, storage, rgba, tuple(palette_values), palette_raw, palette_rgba))
        reader.reset(next_offset)
    return images, palette_raw, palette_rgba


def _apply_image_views(image: PDImage, explicit: bool, flip: bool) -> PDImage:
    storage = _swap_alt_rows(image.pixels, image.width, image.height, image.format) if explicit else image.pixels
    # Convert from logical bytes, not swapped DMA storage.  This gives the
    # caller a stable visual view while preserving the exact upload bytes.
    rgba = _rgba8_from_native(image.pixels, image.width, image.height, image.format, image.lookup)
    if flip:
        rgba = _vertical_flip(rgba, image.width, image.height)
    return PDImage(image.level, image.format, image.compression, image.width, image.height,
                   image.pixels, storage, rgba, image.lookup, image.palette_raw, image.palette_rgba8)


def decode_stream(data: bytes, *, flip: bool = True) -> PDTexture:
    """Decode one source global image stream.

    ``flip`` controls only the canonical RGBA8 view.  Packed source bytes and
    storage bytes remain source ordered.  All malformed streams raise
    :class:`PDDecodeError` and never return a partial image list.
    """
    if not isinstance(data, (bytes, bytearray, memoryview)):
        raise PDDecodeError("PD stream must be bytes-like")
    data = bytes(data)
    if not data or len(data) > 1 << 20:
        raise PDDecodeError("PD stream is empty or exceeds preparation bounds")
    reader = _BitReader(data)
    explicit = bool(reader.read(1))
    is_zlib = bool(reader.read(1))
    lod = reader.read(6)
    if lod > MAX_IMAGES:
        raise PDDecodeError(f"PD LOD count {lod} exceeds {MAX_IMAGES}")
    if is_zlib:
        images, palette_raw, palette_rgba = _decode_zlib_images(data, reader, explicit, lod)
    else:
        count = lod if explicit and lod else 1
        images = []
        for level in range(count):
            image, _ = _decode_non_zlib_image(reader, level)
            # Source finishes each explicit image at the next byte boundary;
            # if the reader exactly consumed its prefetched byte, image.c's
            # pointer increment skips the one-byte pad in the stream.
            if explicit:
                if reader.bits == 0:
                    if reader.offset >= len(data):
                        raise PDDecodeError("PD explicit LOD padding byte is missing")
                    reader.offset += 1
                else:
                    reader.bits = 0
                    reader.buffer = 0
            images.append(image)
        palette_raw = palette_rgba = b""
    if not images:
        raise PDDecodeError("PD stream contains no image levels")
    images = [_apply_image_views(image, explicit, flip) for image in images]
    return PDTexture(explicit, is_zlib, lod, tuple(images), palette_raw, palette_rgba,
                     hashlib.sha256(data).hexdigest(), reader.offset)


def extract_palette(data: bytes) -> tuple[bytes, bytes, int] | None:
    """Return ``(raw_big_endian, rgba8, format_id)`` for an embedded CI TLUT."""
    texture = decode_stream(data, flip=False)
    if not texture.palette_raw:
        return None
    return texture.palette_raw, texture.palette_rgba8, int(texture.format)


__all__ = [
    "PDCompression", "PDDecodeError", "PDFormat", "PDImage", "PDTexture",
    "decode_stream", "extract_palette", "generate_source_mips", "FORMAT_BITS_PER_PIXEL", "FORMAT_CHANNELS",
]


if __name__ == "__main__":
    import argparse
    from pathlib import Path

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stream", type=Path)
    args = parser.parse_args()
    decoded = decode_stream(args.stream.read_bytes())
    print(f"format={int(decoded.format)} dimensions={decoded.width}x{decoded.height} mips={decoded.mip_count} zlib={decoded.is_zlib} explicit={decoded.explicit_lods}")
    for image in decoded.images:
        print(f"level={image.level} {image.width}x{image.height} format={int(image.format)} compression={image.compression} rgba8_sha256={hashlib.sha256(image.rgba8).hexdigest()} nonzero={any(image.rgba8)}")
