#!/usr/bin/env python3
"""Lower the source title/frontend images into a guarded GETI packet.

The checked-in ``assets/images/split`` files are PD texture streams.  This
preparation step uses the repository's source ``tex2png`` reader (never the
external ROM) and copies only decoded RGBA8 pixels plus fixed-width source
metadata into the ignored native title asset directory.  The packet is
pointer-free and carries per-row source/decoded SHA-256 evidence so runtime
cannot silently accept a changed icon.
"""

from __future__ import annotations

import argparse
import hashlib
import math
import os
import struct
import subprocess
import tempfile
import zlib
from pathlib import Path


MAGIC = b"GETI"
VERSION = 1
HEADER = struct.Struct("<4sIIIIII32s32sI")
RECORD = struct.Struct("<IIIIIIIIIII32s32s")
assert HEADER.size == 96
assert RECORD.size == 108

# Source order is the six requested frontend rows plus X, the actual cursor
# image used by front.c's main-folder image table.  Keeping X as a distinct
# row avoids substituting CROSSHAIR1 (the gameplay sight) for the menu cursor.
ICONS = (
    ("COPYICON", 32, 28, 0, 7, 1, 0),
    ("DELICON", 32, 28, 0, 8, 1, 0),
    ("SELECTFILE", 122, 18, 5, 6, 0, 0),
    ("CROSSHAIR1", 32, 32, 0, 4, 1, 1),
    # Zlib/CI rows retain their PD stream format IDs (11/12); the N64 image
    # table's IA/I presentation format is a separate runtime tile contract.
    ("CHECK", 20, 20, 11, 0, 1, 1),
    ("DOT", 16, 16, 12, 0, 2, 2),
    ("X", 15, 15, 11, 0, 0, 0),
)

# These are the checked-in source rows.  Guard them independently of the
# packet hash: a regenerated packet with a changed source row must fail.
EXPECTED_SOURCE_SHA256 = {
    "COPYICON": "e2129e877befe82fb6b6299edde3dc23b059ce6d281b800ddbbbb2fb794b6119",
    "DELICON": "d13f7ce02d63af243fce76659b91467741c3aa02469ff82bf636d9540f95efae",
    "SELECTFILE": "7f0bf6431a2406d5edceabe7722204c374618f72df41119794a939d24d76f09d",
    "CROSSHAIR1": "c43dea8d08ce9094aa445587788a6ef77dff95f6fdc38c83cbe6313363d42417",
    "CHECK": "276d188622d5a029a3f20606e2500bc4ef7e8a42673319efb019c66f22618fd1",
    "DOT": "b9924290b5d71aa709a97082e3c09b6f357329e5bc20427b2f6c8f18794c919f",
    "X": "dff183a6438a54153f518c026350120f7d8a8cb12385d401a542c1797103ff29",
}


class PacketError(ValueError):
    pass


def paeth(a: int, b: int, c: int) -> int:
    estimate = a + b - c
    pa = abs(estimate - a)
    pb = abs(estimate - b)
    pc = abs(estimate - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def decode_png(data: bytes) -> tuple[int, int, bytes]:
    """Decode the small non-interlaced PNGs emitted by tex2png to RGBA8."""
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise PacketError("PNG signature is missing")
    offset = 8
    width = height = bit_depth = color_type = None
    interlace = None
    palette = b""
    transparency = b""
    compressed = bytearray()
    while offset + 12 <= len(data):
        length = struct.unpack_from(">I", data, offset)[0]
        offset += 4
        kind = data[offset : offset + 4]
        offset += 4
        end = offset + length
        if end + 4 > len(data):
            raise PacketError("PNG chunk exceeds file")
        body = data[offset:end]
        offset = end
        expected_crc = struct.unpack_from(">I", data, offset)[0]
        offset += 4
        actual_crc = zlib.crc32(kind + body) & 0xFFFF_FFFF
        if actual_crc != expected_crc:
            raise PacketError(f"PNG {kind!r} CRC mismatch")
        if kind == b"IHDR":
            if length != 13:
                raise PacketError("PNG IHDR size")
            width, height, bit_depth, color_type, compression, filter_method, interlace = struct.unpack(">IIBBBBB", body)
            if compression != 0 or filter_method != 0 or interlace != 0:
                raise PacketError("PNG compression/filter/interlace unsupported")
        elif kind == b"PLTE":
            palette = body
        elif kind == b"tRNS":
            transparency = body
        elif kind == b"IDAT":
            compressed.extend(body)
        elif kind == b"IEND":
            break
    if width is None or height is None or not compressed:
        raise PacketError("PNG payload is incomplete")
    if width == 0 or height == 0 or width > 512 or height > 512:
        raise PacketError(f"PNG dimensions {width}x{height} are outside the guard")
    if bit_depth not in (1, 2, 4, 8):
        raise PacketError(f"PNG bit depth {bit_depth} is unsupported")
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}.get(color_type)
    if channels is None:
        raise PacketError(f"PNG color type {color_type} is unsupported")
    if bit_depth != 8 and color_type != 3:
        raise PacketError("sub-byte non-indexed PNG is unsupported")
    bits_per_pixel = channels * bit_depth
    row_bytes = (width * bits_per_pixel + 7) // 8
    filter_bpp = max(1, (bits_per_pixel + 7) // 8)
    inflated = zlib.decompress(bytes(compressed))
    expected = height * (row_bytes + 1)
    if len(inflated) != expected:
        raise PacketError(f"PNG scanline size {len(inflated)} != {expected}")

    rows: list[bytes] = []
    cursor = 0
    prior = bytes(row_bytes)
    for _ in range(height):
        filter_type = inflated[cursor]
        cursor += 1
        encoded = inflated[cursor : cursor + row_bytes]
        cursor += row_bytes
        row = bytearray(row_bytes)
        for index, value in enumerate(encoded):
            left = row[index - filter_bpp] if index >= filter_bpp else 0
            above = prior[index]
            upper_left = prior[index - filter_bpp] if index >= filter_bpp else 0
            if filter_type == 0:
                result = value
            elif filter_type == 1:
                result = value + left
            elif filter_type == 2:
                result = value + above
            elif filter_type == 3:
                result = value + ((left + above) // 2)
            elif filter_type == 4:
                result = value + paeth(left, above, upper_left)
            else:
                raise PacketError(f"PNG filter {filter_type} is unsupported")
            row[index] = result & 0xFF
        rows.append(bytes(row))
        prior = bytes(row)

    def sample(row: bytes, index: int) -> int:
        if bit_depth == 8:
            return row[index]
        per_byte = 8 // bit_depth
        byte = row[index // per_byte]
        shift = (per_byte - 1 - (index % per_byte)) * bit_depth
        return (byte >> shift) & ((1 << bit_depth) - 1)

    output = bytearray()
    for row in rows:
        for x in range(width):
            if color_type == 6:
                base = x * 4
                rgba = row[base : base + 4]
            elif color_type == 2:
                base = x * 3
                rgba = row[base : base + 3] + b"\xff"
            elif color_type == 4:
                base = x * 2
                gray, alpha = row[base : base + 2]
                rgba = bytes((gray, gray, gray, alpha))
            elif color_type == 0:
                value = sample(row, x)
                scale = 255 // ((1 << bit_depth) - 1)
                gray = value * scale
                alpha = 255
                if len(transparency) == 2 and value == struct.unpack(">H", transparency)[0]:
                    alpha = 0
                rgba = bytes((gray, gray, gray, alpha))
            else:  # indexed color
                palette_index = sample(row, x)
                base = palette_index * 3
                if base + 3 > len(palette):
                    raise PacketError("PNG palette index exceeds PLTE")
                alpha = transparency[palette_index] if palette_index < len(transparency) else 255
                rgba = palette[base : base + 3] + bytes((alpha,))
            output.extend(rgba)
    if len(output) != width * height * 4:
        raise PacketError("decoded RGBA size mismatch")
    return width, height, bytes(output)


def find_tex2png(project_root: Path) -> Path:
    candidates = []
    if os.environ.get("GOLDENEYE_TEX2PNG"):
        candidates.append(Path(os.environ["GOLDENEYE_TEX2PNG"]))
    candidates.extend(
        [
            project_root / "build/native/classic-textures/tex2png",
            project_root / "tools/mktex/build/tex2png",
        ]
    )
    for candidate in candidates:
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate
    try:
        subprocess.run(["make", "-C", str(project_root / "tools/mktex"), "tex2png"], check=True)
    except (OSError, subprocess.CalledProcessError) as error:
        raise PacketError(f"source tex2png tool is unavailable: {error}") from error
    candidate = project_root / "tools/mktex/build/tex2png"
    if not candidate.is_file() or not os.access(candidate, os.X_OK):
        raise PacketError("make did not produce tools/mktex/build/tex2png")
    return candidate


def stream_format_and_compression(source: bytes) -> tuple[int, int]:
    if len(source) < 2:
        raise PacketError("icon stream header is truncated")
    is_zlib = (source[0] >> 6) & 1
    if is_zlib:
        return source[1], 0
    # explicit_lods/is_zlib/lod occupy the first byte, followed by the
    # four-bit format, eight-bit width, eight-bit height, and compression.
    if len(source) < 4:
        raise PacketError("icon non-zlib header is truncated")
    bits = "".join(f"{value:08b}" for value in source[:5])
    return int(bits[8:12], 2), int(bits[28:32], 2)


def lower(project_root: Path, output_root: Path, report_path: Path) -> tuple[str, int]:
    source_root = project_root / "assets/images/split"
    tex2png = find_tex2png(project_root)
    decoded_records: list[tuple[bytes, tuple[int, ...], bytes, bytes, bytes]] = []
    source_concat = bytearray()
    report_lines = ["status=PASS", "packet=title-icons.geti", "runtime_rom_access=false", "visual_parity=not-claimed"]

    with tempfile.TemporaryDirectory(prefix="goldeneye-title-icons-") as temporary:
        temp_root = Path(temporary)
        for icon_id, (name, expected_width, expected_height, source_format, compression, s_flags, t_flags) in enumerate(ICONS):
            source_path = source_root / f"{name}.bin"
            if not source_path.is_file():
                raise PacketError(f"source icon row is missing: {source_path}")
            source = source_path.read_bytes()
            source_hash = hashlib.sha256(source).digest()
            if source_hash.hex() != EXPECTED_SOURCE_SHA256[name]:
                raise PacketError(f"{name} source SHA-256 mismatch")
            stream_format, stream_compression = stream_format_and_compression(source)
            if (stream_format, stream_compression) != (source_format, compression):
                raise PacketError(
                    f"{name} stream format/compression {(stream_format, stream_compression)} "
                    f"!= guarded {(source_format, compression)}"
                )
            source_concat.extend(source)
            output_dir = temp_root / str(icon_id)
            output_dir.mkdir()
            subprocess.run([str(tex2png), str(source_path), str(output_dir)], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            png_path = output_dir / f"{name}-0.png"
            if not png_path.is_file():
                raise PacketError(f"tex2png did not emit {png_path}")
            width, height, pixels = decode_png(png_path.read_bytes())
            if (width, height) != (expected_width, expected_height):
                raise PacketError(f"{name} dimensions {width}x{height} != {expected_width}x{expected_height}")
            decoded_hash = hashlib.sha256(pixels).digest()
            record_fields = (
                icon_id,
                width,
                height,
                source_format,
                compression,
                s_flags,
                t_flags,
                len(source),
                len(pixels),
                0,  # payload offset is filled after all rows are decoded
                0,
            )
            decoded_records.append((pixels, record_fields, source_hash, decoded_hash, source_path.read_bytes()))
            report_lines.append(
                f"icon_{name}=id:{icon_id},source_row:assets/images/split/{name}.bin,"
                f"source_bytes:{len(source)},source_sha256:{source_hash.hex()},"
                f"decoded_bytes:{len(pixels)},decoded_sha256:{decoded_hash.hex()},"
                f"dimensions:{width}x{height},format:{source_format},compression:{compression},"
                f"s_flags:{s_flags},t_flags:{t_flags}"
            )

    source_hash = hashlib.sha256(bytes(source_concat)).digest()
    payload = bytearray()
    records = bytearray()
    for pixels, fields, source_digest, decoded_digest, _ in decoded_records:
        mutable = list(fields)
        mutable[9] = len(payload)
        payload.extend(pixels)
        records.extend(RECORD.pack(*mutable, source_digest, decoded_digest))
    zero_header = HEADER.pack(
        MAGIC,
        VERSION,
        len(ICONS),
        RECORD.size * len(ICONS),
        len(payload),
        len(source_concat),
        0,
        source_hash,
        bytes(32),
        0,
    )
    canonical = zero_header + bytes(records) + bytes(payload)
    packet_hash = hashlib.sha256(canonical).digest()
    header = HEADER.pack(
        MAGIC,
        VERSION,
        len(ICONS),
        RECORD.size * len(ICONS),
        len(payload),
        len(source_concat),
        0,
        source_hash,
        packet_hash,
        0,
    )
    packet = header + bytes(records) + bytes(payload)
    output_root.mkdir(parents=True, exist_ok=True)
    output_path = output_root / "title-icons.geti"
    output_path.write_bytes(packet)
    report_lines.extend(
        [
            f"source_concat_bytes={len(source_concat)}",
            f"source_concat_sha256={source_hash.hex()}",
            f"packet_sha256={packet_hash.hex()}",
            f"icon_count={len(ICONS)}",
            f"payload_bytes={len(payload)}",
        ]
    )
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text("\n".join(report_lines) + "\n", encoding="utf-8")
    return packet_hash.hex(), len(payload)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    try:
        packet_hash, payload_bytes = lower(args.project_root, args.output_root, args.report)
    except (OSError, PacketError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"native title icon lowering failed: {error}") from error
    print("native title icon lowering: PASS")
    print(f"packet={args.output_root / 'title-icons.geti'}")
    print(f"packet_sha256={packet_hash}")
    print(f"payload_bytes={payload_bytes}")


if __name__ == "__main__":
    main()
