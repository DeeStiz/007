#!/usr/bin/env python3
"""Extract a bounded, source-derived title geometry packet.

This is a preparation-time tool.  It reads the generated source listings in
assets/obseg/prop/*/Model.c, never a ROM, and writes little-endian packets to
the ignored native boot asset directory.  The runtime packet contains only
fixed-width vertices/indices and hashes; it does not contain C pointers,
segmented addresses, Gfx words, or a model graph.

The extractor deliberately lowers only gsSPVertex plus gsSP1/2/4Triangles.
Texture, combiner, matrix, BSP and other commands are counted as unsupported
evidence instead of being silently interpreted.  Source vertex colors are
preserved, while the Metal title lane applies a bounded 2D normalization to
the source model bounds.  This is useful first-frame geometry evidence, not
N64 display-list or pixel parity.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import struct
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

BASE_ADDRESS = 0x05000000
MAGIC = b"GETP"
VERSION = 1
HEADER_FORMAT = "<4sIIIIIIIIiiiiii32s32sI"
HEADER_SIZE = struct.calcsize(HEADER_FORMAT)
assert HEADER_SIZE == 128
VERTEX_FORMAT = "<iii4B"
VERTEX_SIZE = struct.calcsize(VERTEX_FORMAT)
assert VERTEX_SIZE == 16

FLAG_HAS_TRIANGLES = 1 << 0
FLAG_HAS_UNSUPPORTED = 1 << 1
FLAG_PARTIAL_SOURCE = 1 << 2
# Additive source-material/model evidence bits.  These live in the existing
# fixed-width GETP flags word; they do not add pointers, segmented addresses,
# or Gfx words to the runtime packet.  The older title packets deliberately
# leave these bits clear, so their bytes/hashes remain unchanged.
FLAG_MATERIAL_TEXTURED = 1 << 3
FLAG_MATERIAL_VERTEX_COLOR = 1 << 4
FLAG_MATERIAL_LIT = 1 << 5
FLAG_MODEL_HEAD = 1 << 6
FLAG_MODEL_BODY = 1 << 7
FLAG_MODEL_WEAPON = 1 << 8
FLAG_DYNAMIC_VERTEX_SEGMENT = 1 << 9

MODEL_SPECS = {
    "legalpage": (4, Path("assets/obseg/prop/legalpage/Model.c"), 0),
    "nintendologo": (5, Path("assets/obseg/prop/nintendologo/Model.c"), 0),
    "goldeneyelogo": (3, Path("assets/obseg/prop/goldeneyelogo/Model.c"), 0),
    "walletbond": (6, Path("assets/obseg/prop/walletbond/Model.c"), 0),
    # Gunbarrel source uses model-owned 0x04 vertex staging addresses.  The
    # extractor resolves those addresses against the first declared vertex
    # array and records the dynamic-segment/material evidence in flags.
    "headbrosnansuit": (
        7,
        Path("assets/obseg/chr/headbrosnansuit/Model.c"),
        FLAG_MATERIAL_TEXTURED | FLAG_MATERIAL_VERTEX_COLOR | FLAG_MATERIAL_LIT
        | FLAG_MODEL_HEAD | FLAG_DYNAMIC_VERTEX_SEGMENT,
    ),
    "suitbond": (
        8,
        Path("assets/obseg/chr/suitbond/Model.c"),
        FLAG_MATERIAL_TEXTURED | FLAG_MATERIAL_VERTEX_COLOR | FLAG_MATERIAL_LIT
        | FLAG_MODEL_BODY | FLAG_DYNAMIC_VERTEX_SEGMENT,
    ),
    "chrwppk": (
        9,
        Path("assets/obseg/prop/chrwppk/Model.c"),
        FLAG_MATERIAL_TEXTURED | FLAG_MATERIAL_VERTEX_COLOR | FLAG_MODEL_WEAPON,
    ),
}

RAREWARE_HANDLE = 1


@dataclass(frozen=True)
class SourceVertex:
    x: int
    y: int
    z: int
    r: int
    g: int
    b: int
    a: int


@dataclass(frozen=True)
class Triangle:
    a: int
    b: int
    c: int


def parse_int(value: str) -> int:
    value = value.strip()
    if value.lower().startswith("0x"):
        return int(value, 16)
    value = re.sub(r"[uUlL]+$", "", value)
    return int(value, 10)


def strip_comments(source: str) -> str:
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    return re.sub(r"//[^\n]*", "", source)


def parse_vertices(source: str) -> dict[int, list[SourceVertex]]:
    arrays: dict[int, list[SourceVertex]] = {}
    pattern = re.compile(
        r"\bVertex\s+Vertex_0x([0-9a-fA-F]+)\s*\[[^\]]+\]\s*=\s*\{(.*?)\n\};",
        re.S,
    )
    vertex_pattern = re.compile(
        r"\{\s*\{\s*([^,]+),\s*([^,]+),\s*([^}]+)\}\s*,"
        r"\s*[^,]+,\s*[^,]+,\s*[^,]+,\s*([^,]+),\s*([^,]+),\s*([^,]+),\s*([^}]+)\s*\}"
    )
    for match in pattern.finditer(source):
        offset = int(match.group(1), 16)
        values: list[SourceVertex] = []
        for vertex in vertex_pattern.finditer(match.group(2)):
            values.append(
                SourceVertex(
                    x=parse_int(vertex.group(1)),
                    y=parse_int(vertex.group(2)),
                    z=parse_int(vertex.group(3)),
                    r=parse_int(vertex.group(4)) & 0xFF,
                    g=parse_int(vertex.group(5)) & 0xFF,
                    b=parse_int(vertex.group(6)) & 0xFF,
                    a=parse_int(vertex.group(7)) & 0xFF,
                )
            )
        if not values:
            raise ValueError(f"vertex array at 0x{offset:x} has no parseable records")
        arrays[offset] = values
    if not arrays:
        raise ValueError("no Vertex arrays found")
    return arrays


def first_primary_body(source: str) -> str:
    match = re.search(
        r"\bGfx\s+GFX_PRIMARY_0x[0-9a-fA-F]+\s*\[\]\s*=\s*\{(.*?)\n\};",
        source,
        re.S,
    )
    if not match:
        raise ValueError("no primary display list found")
    return match.group(1)


def command_tokens(body: str) -> Iterable[tuple[str, str]]:
    command = re.compile(r"\b(gs[A-Za-z0-9_]+)\s*\(([^;]*?)\)", re.S)
    return ((match.group(1), match.group(2)) for match in command.finditer(body))


def parse_triangles(
    body: str,
    vertices: dict[int, list[SourceVertex]],
) -> tuple[list[SourceVertex], list[Triangle], int, int, int]:
    loaded: tuple[int, int, int, int] | None = None
    flattened: list[SourceVertex] = []
    flattened_lookup: dict[tuple[int, int], int] = {}
    triangles: list[Triangle] = []
    command_count = 0
    unsupported_count = 0
    max_source_offset = 0

    # Character display lists stage vertices through segment 0x04.  Unlike
    # prop packets, those commands intentionally use addresses beginning at
    # 0x04000000 rather than the source listing's 0x05000000 model-file
    # offsets.  The generated listing's first Vertex array is the staging
    # source for the bounded primary display list selected below.
    dynamic_base = 0x04000000
    dynamic_array_start = next(iter(vertices))
    dynamic_values = vertices[dynamic_array_start]

    for name, args_text in command_tokens(body):
        command_count += 1
        args = [part.strip() for part in args_text.replace("\n", " ").split(",") if part.strip()]
        if name == "gsSPVertex":
            if len(args) != 3:
                raise ValueError(f"malformed gsSPVertex: {args_text!r}")
            address = parse_int(args[0])
            count = parse_int(args[1])
            v0 = parse_int(args[2])
            is_dynamic = dynamic_base <= address < dynamic_base + len(dynamic_values) * 16
            if is_dynamic:
                offset = address - dynamic_base
                containing = [dynamic_array_start]
            else:
                offset = address - BASE_ADDRESS
                containing = [
                    start
                    for start, values in vertices.items()
                    if start <= offset < start + len(values) * 16
                    and (offset - start) % 16 == 0
                ]
            if len(containing) != 1:
                raise ValueError(f"gsSPVertex references unknown source array 0x{offset:x}")
            array_start = containing[0]
            source_index = offset // 16 if is_dynamic else (offset - array_start) // 16
            if count <= 0 or source_index + count > len(vertices[array_start]) or v0 < 0 or v0 + count > 32:
                raise ValueError(f"gsSPVertex window out of range: 0x{offset:x} count={count} v0={v0}")
            loaded = (array_start, source_index, count, v0)
            max_source_offset = max(max_source_offset, offset + count * 16)
            continue

        if name not in {"gsSP1Triangle", "gsSP2Triangles", "gsSP4Triangles", "gsSPEndDisplayList"}:
            unsupported_count += 1
            continue
        if name == "gsSPEndDisplayList":
            continue
        if loaded is None:
            raise ValueError(f"{name} appears before gsSPVertex")
        width = int(name[4])
        if len(args) == width * 4:
            stride = 4
        elif len(args) == width * 3:
            # The generated model listings use both the SDK macros with a
            # per-triangle flag and compact hand-authored forms without it.
            stride = 3
        else:
            raise ValueError(f"malformed {name}: expected {width * 3} or {width * 4} args, got {len(args)}")
        for triangle_index in range(width):
            raw = [parse_int(value) for value in args[triangle_index * stride : triangle_index * stride + 3]]
            array_offset, source_index, count, v0 = loaded
            for index in raw:
                if index < v0 or index >= v0 + count:
                    raise ValueError(f"{name} index {index} outside loaded window {v0}..{v0 + count - 1}")
            global_indices: list[int] = []
            for index in raw:
                key = (array_offset, source_index + index - v0)
                if key not in flattened_lookup:
                    flattened_lookup[key] = len(flattened)
                    flattened.append(vertices[array_offset][source_index + index - v0])
                global_indices.append(flattened_lookup[key])
            triangles.append(Triangle(*global_indices))

    return flattened, triangles, command_count, unsupported_count, max_source_offset


def packet_bytes(
    model_handle: int,
    source: bytes,
    vertices: list[SourceVertex],
    triangles: list[Triangle],
    command_count: int,
    unsupported_count: int,
    model_flags: int = 0,
) -> bytes:
    if not vertices or not triangles:
        raise ValueError("source primary list produced no geometry")
    xs = [vertex.x for vertex in vertices]
    ys = [vertex.y for vertex in vertices]
    zs = [vertex.z for vertex in vertices]
    flags = FLAG_HAS_TRIANGLES
    if unsupported_count:
        flags |= FLAG_HAS_UNSUPPORTED
    # The extractor intentionally consumes only the first primary list.  This
    # is a bounded source slice, not a claim that all BSP/display-list paths
    # have been lowered.
    flags |= FLAG_PARTIAL_SOURCE
    flags |= model_flags
    source_hash = hashlib.sha256(source).digest()
    header_without_packet_hash = struct.pack(
        HEADER_FORMAT,
        MAGIC,
        VERSION,
        model_handle,
        flags,
        len(source),
        command_count,
        unsupported_count,
        len(vertices),
        len(triangles) * 3,
        min(xs),
        min(ys),
        min(zs),
        max(xs),
        max(ys),
        max(zs),
        source_hash,
        bytes(32),
        0,
    )
    body = b"".join(
        struct.pack(VERTEX_FORMAT, vertex.x, vertex.y, vertex.z, vertex.r, vertex.g, vertex.b, vertex.a)
        for vertex in vertices
    )
    body += b"".join(
        struct.pack("<I", index)
        for triangle in triangles
        for index in (triangle.a, triangle.b, triangle.c)
    )
    packet_hash = hashlib.sha256(header_without_packet_hash + body).digest()
    header = struct.pack(
        HEADER_FORMAT,
        MAGIC,
        VERSION,
        model_handle,
        flags,
        len(source),
        command_count,
        unsupported_count,
        len(vertices),
        len(triangles) * 3,
        min(xs),
        min(ys),
        min(zs),
        max(xs),
        max(ys),
        max(zs),
        source_hash,
        packet_hash,
        0,
    )
    return header + body


def parse_s16(value: str) -> int:
    raw = parse_int(value) & 0xFFFF
    return raw - 0x10000 if raw & 0x8000 else raw


def parse_rareware_vertices(source: str) -> dict[str, list[SourceVertex]]:
    arrays: dict[str, list[SourceVertex]] = {}
    pattern = re.compile(
        r"\bVtx\s+(verts[0-9a-fA-F]+)\s*\[\]\s*=\s*\{(.*?)\n\};",
        re.S,
    )
    vertex_pattern = re.compile(
        r"\{\s*([^,]+),\s*([^,]+),\s*([^,]+),\s*[^,]+,\s*[^,]+,\s*[^,]+,"
        r"\s*([^,]+),\s*([^,]+),\s*([^,]+),\s*([^}]+)\s*\}"
    )
    for match in pattern.finditer(source):
        values: list[SourceVertex] = []
        for vertex in vertex_pattern.finditer(match.group(2)):
            alpha = parse_int(vertex.group(7)) & 0xFF
            values.append(
                SourceVertex(
                    x=parse_s16(vertex.group(1)),
                    y=parse_s16(vertex.group(2)),
                    z=parse_s16(vertex.group(3)),
                    r=parse_int(vertex.group(4)) & 0xFF,
                    g=parse_int(vertex.group(5)) & 0xFF,
                    b=parse_int(vertex.group(6)) & 0xFF,
                    # Rareware's source display lists set primitive color and
                    # leave Vtx alpha at zero; make the lowered geometry
                    # visible while retaining the source RGB values.
                    a=alpha if alpha != 0 else 0xFF,
                )
            )
        if not values:
            raise ValueError(f"rareware vertex array {match.group(1)} is empty")
        arrays[match.group(1)] = values
    if len(arrays) != 26:
        raise ValueError(f"rareware vertex array count {len(arrays)} != 26")
    return arrays


def parse_rareware_triangles(
    source: str,
    vertices: dict[str, list[SourceVertex]],
) -> tuple[list[SourceVertex], list[Triangle], int, int]:
    bodies: list[str] = []
    for name in ("D_020043E8", "DL_RAREWARETEXT", "D_02004758"):
        match = re.search(
            rf"\bGfx\s+{name}\s*\[\]\s*=\s*\{{(.*?)\n\}};",
            source,
            re.S,
        )
        if not match:
            raise ValueError(f"rareware display list {name} is missing")
        bodies.append(match.group(1))

    flattened: list[SourceVertex] = []
    flattened_lookup: dict[tuple[str, int], int] = {}
    triangles: list[Triangle] = []
    command_count = 0
    unsupported_count = 0
    for body in bodies:
        loaded: tuple[str, int, int] | None = None
        for name, args_text in command_tokens(body):
            command_count += 1
            args = [part.strip() for part in args_text.replace("\n", " ").split(",") if part.strip()]
            if name == "gsSPVertex":
                if len(args) != 3:
                    raise ValueError(f"malformed rareware gsSPVertex: {args_text!r}")
                symbol = args[0]
                count = parse_int(args[1])
                v0 = parse_int(args[2])
                if symbol not in vertices or count <= 0 or count > len(vertices[symbol]) or v0 < 0 or v0 + count > 32:
                    raise ValueError(f"rareware vertex window out of range: {symbol} count={count} v0={v0}")
                loaded = (symbol, count, v0)
                continue
            if name == "gsSPEndDisplayList":
                continue
            if name not in {"gsSP1Triangle", "gsSP2Triangles", "gsSP4Triangles"}:
                unsupported_count += 1
                continue
            if loaded is None:
                raise ValueError(f"rareware {name} appears before gsSPVertex")
            width = int(name[4])
            if len(args) == width * 4:
                stride = 4
            elif len(args) == width * 3:
                stride = 3
            else:
                raise ValueError(f"malformed rareware {name}: {args_text!r}")
            symbol, count, v0 = loaded
            for triangle_index in range(width):
                raw = [parse_int(value) for value in args[triangle_index * stride : triangle_index * stride + 3]]
                for index in raw:
                    if index < v0 or index >= v0 + count:
                        raise ValueError(f"rareware {name} index {index} outside {symbol} window")
                global_indices: list[int] = []
                for index in raw:
                    key = (symbol, index - v0)
                    if key not in flattened_lookup:
                        flattened_lookup[key] = len(flattened)
                        flattened.append(vertices[symbol][index - v0])
                    global_indices.append(flattened_lookup[key])
                triangles.append(Triangle(*global_indices))
    return flattened, triangles, command_count, unsupported_count


def rareware_texture_packet(source: bytes, source_text: str) -> bytes:
    names = ("imgRAre_0x0020", "img_raRE_0x0AE0", "imgWAre_0x15A0", "imgwaRE_0x2060")
    images: list[list[int]] = []
    for name in names:
        match = re.search(rf"\bu32\s+{name}\s*\[\]\s*=\s*\{{(.*?)\n\}};", source_text, re.S)
        if not match:
            raise ValueError(f"rareware texture array {name} is missing")
        words = [int(token, 16) for token in re.findall(r"0x([0-9A-Fa-f]+)", match.group(1))]
        if len(words) != 686:
            raise ValueError(f"rareware texture array {name} word count {len(words)} != 686")
        images.append(words)

    # Pack the four tracked 32x43 RGBA5551 images into a 64x86 atlas.  The
    # title geometry lane does not claim source UV/TMEM parity, but the atlas
    # gives the renderer an actual prepared Rareware texture payload.
    rgba = bytearray()
    for row in range(86):
        image_row = row // 43
        local_y = row % 43
        for column in range(64):
            image_column = column // 32
            local_x = column % 32
            word_index = local_y * 16 + local_x // 2
            word = images[image_row * 2 + image_column][word_index] if word_index < 686 else 0
            pixel = (word >> 16) & 0xFFFF if (local_x & 1) == 0 else word & 0xFFFF
            rgba.extend(
                (
                    ((pixel >> 11) & 0x1F) * 255 // 31,
                    ((pixel >> 6) & 0x1F) * 255 // 31,
                    ((pixel >> 1) & 0x1F) * 255 // 31,
                    255 if pixel & 1 else 0,
                )
            )
    header = struct.pack("<4sIIII32s32s", b"GETX", 1, 64, 86, len(rgba), hashlib.sha256(source).digest(), bytes(32))
    packet_hash = hashlib.sha256(header + rgba).digest()
    header = struct.pack("<4sIIII32s32s", b"GETX", 1, 64, 86, len(rgba), hashlib.sha256(source).digest(), packet_hash)
    return header + rgba


def extract_one(
    project_root: Path,
    output_root: Path,
    name: str,
    handle: int,
    source_path: Path,
    model_flags: int = 0,
) -> dict[str, int | str]:
    path = project_root / source_path
    if not path.is_file():
        raise FileNotFoundError(f"required source-derived title listing is missing: {path}")
    source = path.read_bytes()
    cleaned = strip_comments(source.decode("utf-8"))
    vertices = parse_vertices(cleaned)
    body = first_primary_body(cleaned)
    flattened, triangles, command_count, unsupported_count, _ = parse_triangles(body, vertices)
    packet = packet_bytes(
        handle,
        source,
        flattened,
        triangles,
        command_count,
        unsupported_count,
        model_flags,
    )
    output_root.mkdir(parents=True, exist_ok=True)
    output_path = output_root / f"{name}.gepk"
    output_path.write_bytes(packet)
    return {
        "name": name,
        "handle": handle,
        "source_sha256": hashlib.sha256(source).hexdigest(),
        "packet_sha256": hashlib.sha256(packet).hexdigest(),
        "commands": command_count,
        "unsupported": unsupported_count,
        "vertices": len(flattened),
        "indices": len(triangles) * 3,
        "path": str(output_path),
    }


def extract_rareware(project_root: Path, output_root: Path) -> dict[str, int | str]:
    path = project_root / "assets/rarewarelogo.c"
    if not path.is_file():
        raise FileNotFoundError(f"required tracked Rareware source is missing: {path}")
    source = path.read_bytes()
    cleaned = strip_comments(source.decode("utf-8"))
    vertices = parse_rareware_vertices(cleaned)
    flattened, triangles, command_count, unsupported_count = parse_rareware_triangles(cleaned, vertices)
    packet = packet_bytes(RAREWARE_HANDLE, source, flattened, triangles, command_count, unsupported_count)
    output_root.mkdir(parents=True, exist_ok=True)
    packet_path = output_root / "rarewarelogo.gepk"
    packet_path.write_bytes(packet)
    texture = rareware_texture_packet(source, cleaned)
    texture_path = output_root / "rarewarelogo.getx"
    texture_path.write_bytes(texture)
    return {
        "name": "rarewarelogo",
        "handle": RAREWARE_HANDLE,
        "source_sha256": hashlib.sha256(source).hexdigest(),
        "packet_sha256": hashlib.sha256(packet).hexdigest(),
        "texture_sha256": hashlib.sha256(texture).hexdigest(),
        "commands": command_count,
        "unsupported": unsupported_count,
        "vertices": len(flattened),
        "indices": len(triangles) * 3,
        "texture_width": 64,
        "texture_height": 86,
        "path": str(packet_path),
        "texture_path": str(texture_path),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output-root", type=Path, default=None)
    parser.add_argument("--report", type=Path, default=None)
    args = parser.parse_args()
    project_root = args.project_root.resolve()
    output_root = (args.output_root or project_root / "build/native/boot-assets/title").resolve()
    report_path = args.report or output_root / "native-title-geometry-report.txt"

    records: list[dict[str, int | str]] = []
    try:
        for name, (handle, source_path, model_flags) in MODEL_SPECS.items():
            records.append(
                extract_one(project_root, output_root, name, handle, source_path, model_flags)
            )
        records.append(extract_rareware(project_root, output_root))
    except (OSError, ValueError, struct.error) as error:
        print(f"native title geometry: ERROR: {error}", file=sys.stderr)
        return 1

    report_path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "report_version=1",
        "goal=native-boot-menu-attract-120",
        "runtime_rom_access=false",
        "lowered_commands=gsSPVertex,gsSP1Triangle,gsSP2Triangles,gsSP4Triangles",
        "unsupported_commands=recorded_not_interpreted",
        "visual_parity=not-claimed",
    ]
    for record in records:
        for key, value in record.items():
            lines.append(f"{record['name']}_{key}={value}")
    lines.append("status=PASS")
    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("native title geometry: PASS")
    for record in records:
        print(
            f"  {record['name']}: vertices={record['vertices']} indices={record['indices']} "
            f"commands={record['commands']} unsupported={record['unsupported']}"
        )
    print(f"  report={report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
