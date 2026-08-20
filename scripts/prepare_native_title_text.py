#!/usr/bin/env python3
"""Lower the source Zurich Bold title font into a fixed-width GETF packet.

This is a preparation-time source step.  It reads only the checked-in
``assets/font/fontZurichBold.c`` listing and emits an ignored packet for the
native title host.  The packet contains copied glyph metrics, the source
kerning table, and a fixed 16x16 cell atlas; it contains no ROM address,
pointer, display-list word, or runtime source path.
"""

from __future__ import annotations

import argparse
import ast
import hashlib
import re
import struct
from pathlib import Path


MAGIC = b"GETF"
VERSION = 1
GLYPH_COUNT = 94
CELL_WIDTH = 16
CELL_HEIGHT = 16
ATLAS_COLUMNS = 16
ATLAS_ROWS = 6
ATLAS_WIDTH = CELL_WIDTH * ATLAS_COLUMNS
ATLAS_HEIGHT = CELL_HEIGHT * ATLAS_ROWS
FONT_BASE_OFFSET = 0xB80
PIXEL_HEADER_BYTES = 12
HEADER = struct.Struct("<4sIIIIIIIIII32s32sI")
METRIC = struct.Struct("<IiIIi")
KERNING_COUNT = 13 * 13
assert HEADER.size == 112
assert METRIC.size == 20


def parse_words(source: str) -> tuple[list[int], list[int], list[int]]:
    kerning_match = re.search(
        r"u32\s+fontZurichBold_kerning\s*\[[^]]+\]\s*=\s*\{(.*?)\};",
        source,
        flags=re.S,
    )
    chart_match = re.search(
        r"u32\s+fontZurichBold_fontchartable\s*\[\]\s*=\s*\{(.*?)\};",
        source,
        flags=re.S,
    )
    bytes_match = re.search(
        r"u32\s+fontZurichBold_fontbytes\s*\[\]\s*=\s*\{(.*?)\};",
        source,
        flags=re.S,
    )
    if not kerning_match or not chart_match or not bytes_match:
        raise ValueError("font Zurich Bold arrays are incomplete")

    def words(body: str) -> list[int]:
        return [int(value, 16) for value in re.findall(r"0x([0-9A-Fa-f]+)", body)]

    return words(kerning_match.group(1)), words(chart_match.group(1)), words(bytes_match.group(1))


def signed32(value: int) -> int:
    return value - 0x1_0000_0000 if value & 0x8000_0000 else value


def lower(source_path: Path, output_path: Path) -> tuple[str, str]:
    source = source_path.read_text(encoding="utf-8")
    kerning_words, chart, font_words = parse_words(source)
    if len(kerning_words) != KERNING_COUNT:
        raise ValueError(f"kerning count {len(kerning_words)} != {KERNING_COUNT}")
    if len(chart) != GLYPH_COUNT * 6:
        raise ValueError(f"font chart count {len(chart)} != {GLYPH_COUNT * 6}")
    if chart[5] != FONT_BASE_OFFSET:
        raise ValueError(f"font base offset 0x{chart[5]:x} != 0x{FONT_BASE_OFFSET:x}")

    font_bytes = b"".join(struct.pack(">I", value) for value in font_words)
    source_hash = hashlib.sha256(source_path.read_bytes()).digest()
    metrics: list[tuple[int, int, int, int, int]] = []
    atlas = bytearray(ATLAS_WIDTH * ATLAS_HEIGHT)

    for glyph in range(GLYPH_COUNT):
        index, baseline, height, width, kerning_index, offset = chart[glyph * 6 : glyph * 6 + 6]
        if index != glyph:
            raise ValueError(f"glyph {glyph} index is {index}")
        baseline = signed32(baseline)
        if not (0 < width <= CELL_WIDTH and 0 < height <= CELL_HEIGHT):
            raise ValueError(f"glyph {glyph} dimensions {width}x{height}")
        if not (0 <= kerning_index < 13):
            raise ValueError(f"glyph {glyph} kerning index {kerning_index}")

        # Every source glyph has a 12-byte display-list/texture header before
        # its padded I8 pixels.  The chart offsets point at that header.
        pixel_offset = offset - FONT_BASE_OFFSET + PIXEL_HEADER_BYTES
        row_stride = (width + 7) & 0xF8
        pixel_end = pixel_offset + row_stride * height
        if pixel_offset < 0 or pixel_end > len(font_bytes):
            raise ValueError(f"glyph {glyph} pixels exceed font bytes")
        cell_x = (glyph % ATLAS_COLUMNS) * CELL_WIDTH
        cell_y = (glyph // ATLAS_COLUMNS) * CELL_HEIGHT
        for row in range(height):
            source_row = pixel_offset + row * row_stride
            atlas_row = (cell_y + row) * ATLAS_WIDTH + cell_x
            atlas[atlas_row : atlas_row + width] = font_bytes[source_row : source_row + width]
        metrics.append((index, baseline, height, width, kerning_index))

    metric_bytes = b"".join(METRIC.pack(*metric) for metric in metrics)
    kerning_bytes = b"".join(struct.pack("<i", signed32(value)) for value in kerning_words)
    header_without_hash = HEADER.pack(
        MAGIC,
        VERSION,
        GLYPH_COUNT,
        CELL_WIDTH,
        CELL_HEIGHT,
        ATLAS_COLUMNS,
        ATLAS_ROWS,
        len(source.encode("utf-8")),
        len(metric_bytes),
        len(kerning_bytes),
        len(atlas),
        source_hash,
        bytes(32),
        0,
    )
    canonical = header_without_hash + metric_bytes + kerning_bytes + bytes(atlas)
    packet_hash = hashlib.sha256(canonical).digest()
    header = HEADER.pack(
        MAGIC,
        VERSION,
        GLYPH_COUNT,
        CELL_WIDTH,
        CELL_HEIGHT,
        ATLAS_COLUMNS,
        ATLAS_ROWS,
        len(source.encode("utf-8")),
        len(metric_bytes),
        len(kerning_bytes),
        len(atlas),
        source_hash,
        packet_hash,
        0,
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(header + metric_bytes + kerning_bytes + bytes(atlas))
    return source_hash.hex(), packet_hash.hex()


def lower_catalog(source_path: Path, output_path: Path) -> tuple[str, str, int]:
    source = source_path.read_text(encoding="utf-8")
    match = re.search(r"\bchar\s*\*\s*LtitleE\s*\[\]\s*=\s*\{(.*?)\n\};", source, re.S)
    if not match:
        raise ValueError("LtitleE catalog declaration is missing")
    strings = [ast.literal_eval(value) for value in re.findall(r'"(?:\\.|[^"\\])*"', match.group(1))]
    required = ("START\n", "NEXT\n", "PREVIOUS\n", "TWYCROSS BOARD OF GAME CLASSIFICATION\n", "Copy\n", "Erase\n", "SELECT MISSION\n", "MULTIPLAYER\n")
    for value in required:
        if value not in strings:
            raise ValueError(f"required LtitleE string missing: {value!r}")
    header = struct.Struct("<4sIIIII32s32sI")
    header_size = header.size
    payload = bytearray()
    offsets = []
    payload_base = header_size + len(strings) * 4
    for value in strings:
        offsets.append(payload_base + len(payload))
        payload.extend(value.encode("utf-8"))
        payload.append(0)
    body = b"".join(struct.pack("<I", offset) for offset in offsets) + bytes(payload)
    source_hash = hashlib.sha256(source_path.read_bytes()).digest()
    zero_header = header.pack(b"GETC", VERSION, len(strings), len(body), len(source.encode("utf-8")), 0, source_hash, bytes(32), 0)
    packet_hash = hashlib.sha256(zero_header + body).digest()
    packet_header = header.pack(b"GETC", VERSION, len(strings), len(body), len(source.encode("utf-8")), 0, source_hash, packet_hash, 0)
    output_path.write_bytes(packet_header + body)
    return source_hash.hex(), packet_hash.hex(), len(strings)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()

    source_path = args.project_root / "assets/font/fontZurichBold.c"
    if not source_path.is_file():
        raise SystemExit(f"required source font is missing: {source_path}")
    output_path = args.output_root / "title-font.getf"
    catalog_source_path = args.project_root / "assets/obseg/text/LtitleE.c"
    catalog_output_path = args.output_root / "LtitleE.gecat"
    try:
        source_hash, packet_hash = lower(source_path, output_path)
        catalog_source_hash, catalog_packet_hash, catalog_count = lower_catalog(catalog_source_path, catalog_output_path)
    except (OSError, ValueError) as error:
        raise SystemExit(f"title font lowering failed: {error}") from error

    report_lines = [
        "status=PASS",
        "packet=title-font.getf",
        f"source={source_path}",
        f"source_sha256={source_hash}",
        f"packet_sha256={packet_hash}",
        f"glyph_count={GLYPH_COUNT}",
        f"cell={CELL_WIDTH}x{CELL_HEIGHT}",
        f"atlas={ATLAS_WIDTH}x{ATLAS_HEIGHT}",
        f"catalog_packet=LtitleE.gecat",
        f"catalog_source_sha256={catalog_source_hash}",
        f"catalog_packet_sha256={catalog_packet_hash}",
        f"catalog_string_count={catalog_count}",
        "runtime_rom_access=false",
        "visual_parity=not-claimed",
    ]
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text("\n".join(report_lines) + "\n", encoding="utf-8")
    print("native title text lowering: PASS")
    print(f"packet={output_path}")
    print(f"source_sha256={source_hash}")
    print(f"packet_sha256={packet_hash}")
    print(f"catalog_packet={catalog_output_path}")


if __name__ == "__main__":
    main()
