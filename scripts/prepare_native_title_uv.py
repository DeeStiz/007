#!/usr/bin/env python3
"""Lower a bounded source-derived title UV/material corner stream.

The extractor reads generated ``assets/obseg/prop/*/Model.c`` listings only.
It never opens the external ROM.  GETU intentionally supports one small,
auditable command subset: texture-image selection, vertex windows, triangle
commands, and display-list termination.  Every other source command is
counted as unsupported evidence.  Triangle corners are expanded so a source
vertex reused across material changes cannot silently inherit the wrong
texture or UV state.

The packet is additive to GETP/GETT.  Records contain source coordinates,
signed s/t, the active source-local texture handle, and deterministic 64-bit
hashes of the source command and source vertex values.  It is a preparation
artifact under ignored build/native paths; runtime consumes only this copied
value stream.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import struct
from dataclasses import dataclass
from pathlib import Path


MAGIC = b"GETU"
VERSION = 1
ABI_VERSION = 1
HEADER = struct.Struct("<4s11I32s32s4I")
RECORD = struct.Struct("<4I5iIQQII")
assert HEADER.size == 128
assert RECORD.size == 64

FLAG_HAS_TRIANGLES = 1 << 0
FLAG_HAS_UNSUPPORTED = 1 << 1
FLAG_PARTIAL_SOURCE = 1 << 2
FLAG_HAS_TEXTURE_HANDLES = 1 << 3
FLAG_SIGNED_ST = 1 << 4
FLAG_COMMAND_HASHES = 1 << 5
FLAG_CORNER_EXPANSION = 1 << 6
FLAG_MASK = (1 << 7) - 1

BASE_ADDRESS = 0x05000000
MODEL_SPECS = (
    ("legalpage", 4, "assets/obseg/prop/legalpage/Model.c"),
    ("nintendologo", 5, "assets/obseg/prop/nintendologo/Model.c"),
    ("goldeneyelogo", 3, "assets/obseg/prop/goldeneyelogo/Model.c"),
)


class PacketError(ValueError):
    pass


@dataclass(frozen=True)
class SourceVertex:
    x: int
    y: int
    z: int
    s: int
    t: int


def parse_int(value: str) -> int:
    value = re.sub(r"/\*.*?\*/", "", value, flags=re.S)
    value = re.sub(r"//[^\n]*", "", value).strip()
    value = re.sub(r"[uUlL]+$", "", value)
    sign = -1 if value.startswith("-") else 1
    if value[:1] in {"-", "+"}:
        value = value[1:]
    return sign * int(value, 16 if value.lower().startswith("0x") else 10)


def strip_comments(source: str) -> str:
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    return re.sub(r"//[^\n]*", "", source)


def fnv64(value: str) -> int:
    result = 0xCBF29CE484222325
    for byte in value.encode("utf-8"):
        result ^= byte
        result = (result * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return result


def parse_vertices(source: str) -> dict[int, list[SourceVertex]]:
    arrays: dict[int, list[SourceVertex]] = {}
    array_pattern = re.compile(
        r"\bVertex\s+Vertex_0x([0-9a-fA-F]+)\s*\[[^\]]+\]\s*=\s*\{(.*?)\n\};",
        re.S,
    )
    # { { x, y, z }, index, s, t, r, g, b, a }
    vertex_pattern = re.compile(
        r"\{\s*\{\s*([^,]+),\s*([^,]+),\s*([^}]+)\}\s*,"
        r"\s*([^,]+),\s*([^,]+),\s*([^,]+),\s*([^,]+),\s*([^,]+),\s*([^,]+),\s*([^}]+)\s*\}"
    )
    for match in array_pattern.finditer(source):
        offset = int(match.group(1), 16)
        values: list[SourceVertex] = []
        for vertex in vertex_pattern.finditer(match.group(2)):
            values.append(
                SourceVertex(
                    x=parse_int(vertex.group(1)),
                    y=parse_int(vertex.group(2)),
                    z=parse_int(vertex.group(3)),
                    s=parse_int(vertex.group(5)),
                    t=parse_int(vertex.group(6)),
                )
            )
        if not values:
            raise PacketError(f"vertex array at 0x{offset:x} has no parseable records")
        arrays[offset] = values
    if not arrays:
        raise PacketError("no Vertex arrays found")
    return arrays


def first_primary_body(source: str) -> str:
    match = re.search(
        r"\bGfx\s+GFX_PRIMARY_0x[0-9a-fA-F]+\s*\[\]\s*=\s*\{(.*?)\n\};",
        source,
        re.S,
    )
    if not match:
        raise PacketError("no primary display list found")
    return match.group(1)


def command_tokens(body: str):
    command = re.compile(r"\b(gs[A-Za-z0-9_]+)\s*\(([^;]*?)\)", re.S)
    return ((match.group(1), match.group(2)) for match in command.finditer(body))


def split_args(args_text: str) -> list[str]:
    return [part.strip() for part in args_text.replace("\n", " ").split(",") if part.strip()]


def resolve_vertex(
    address: int,
    count: int,
    v0: int,
    arrays: dict[int, list[SourceVertex]],
) -> tuple[int, int, int, int]:
    offset = address - BASE_ADDRESS
    containing = [
        start
        for start, values in arrays.items()
        if start <= offset < start + len(values) * 16 and (offset - start) % 16 == 0
    ]
    if len(containing) != 1:
        raise PacketError(f"gsSPVertex references unknown source array 0x{offset:x}")
    array_start = containing[0]
    source_index = (offset - array_start) // 16
    if count <= 0 or source_index + count > len(arrays[array_start]) or v0 < 0 or v0 + count > 32:
        raise PacketError(f"gsSPVertex window out of range: 0x{offset:x} count={count} v0={v0}")
    return array_start, source_index, count, v0


def source_command_hash(name: str, args: list[str], material_handle: int, ordinal: int) -> int:
    canonical = f"{ordinal}:{name}({','.join(args)}):material=0x{material_handle:08x}"
    return fnv64(canonical)


def source_vertex_hash(vertex: SourceVertex, material_handle: int) -> int:
    return fnv64(
        f"{vertex.x},{vertex.y},{vertex.z},{vertex.s},{vertex.t},0x{material_handle:08x}"
    )


def make_packet(name: str, handle: int, source: bytes) -> tuple[bytes, dict[str, int | str]]:
    cleaned = strip_comments(source.decode("utf-8"))
    arrays = parse_vertices(cleaned)
    body = first_primary_body(cleaned)

    loaded: tuple[int, int, int, int] | None = None
    material_handle = 0
    records: list[tuple[int, int, int, int, int, int, int, int, int]] = []
    indices: list[int] = []
    command_count = 0
    unsupported_count = 0
    saw_texture = False

    for name_token, args_text in command_tokens(body):
        command_count += 1
        args = split_args(args_text)
        if name_token == "gsDPSetTextureImage":
            if len(args) != 4:
                raise PacketError(f"malformed gsDPSetTextureImage: {args_text!r}")
            try:
                material_handle = parse_int(args[3]) & 0xFFFFFFFF
            except ValueError as error:
                raise PacketError(f"non-numeric source texture handle: {args[3]!r}") from error
            saw_texture = True
            continue
        if name_token == "gsSPVertex":
            if len(args) != 3:
                raise PacketError(f"malformed gsSPVertex: {args_text!r}")
            loaded = resolve_vertex(parse_int(args[0]), parse_int(args[1]), parse_int(args[2]), arrays)
            continue
        if name_token == "gsSPEndDisplayList":
            continue
        if name_token not in {"gsSP1Triangle", "gsSP2Triangles", "gsSP4Triangles"}:
            unsupported_count += 1
            continue
        if loaded is None:
            raise PacketError(f"{name_token} appears before gsSPVertex")
        width = int(name_token[4])
        if len(args) == width * 4:
            stride = 4
        elif len(args) == width * 3:
            stride = 3
        else:
            raise PacketError(f"malformed {name_token}: {args_text!r}")
        array_start, source_index, count, v0 = loaded
        command_hash = source_command_hash(name_token, args, material_handle, command_count)
        for triangle_index in range(width):
            raw = [parse_int(value) for value in args[triangle_index * stride : triangle_index * stride + 3]]
            for index in raw:
                if index < v0 or index >= v0 + count:
                    raise PacketError(
                        f"{name_token} index {index} outside loaded window {v0}..{v0 + count - 1}"
                    )
                vertex = arrays[array_start][source_index + index - v0]
                records.append(
                    (
                        len(records),
                        vertex.x,
                        vertex.y,
                        vertex.z,
                        vertex.s,
                        vertex.t,
                        material_handle,
                        command_hash,
                        source_vertex_hash(vertex, material_handle),
                    )
                )
                indices.append(len(records) - 1)

    if not records or len(records) % 3 != 0:
        raise PacketError("source primary list produced no triangle corners")
    flags = (
        FLAG_HAS_TRIANGLES
        | FLAG_PARTIAL_SOURCE
        | FLAG_SIGNED_ST
        | FLAG_COMMAND_HASHES
        | FLAG_CORNER_EXPANSION
    )
    if unsupported_count:
        flags |= FLAG_HAS_UNSUPPORTED
    if saw_texture:
        flags |= FLAG_HAS_TEXTURE_HANDLES

    header_without_hash = HEADER.pack(
        MAGIC,
        VERSION,
        ABI_VERSION,
        HEADER.size,
        handle,
        len(records),
        RECORD.size,
        len(indices),
        flags,
        command_count,
        unsupported_count,
        len(source),
        hashlib.sha256(source).digest(),
        bytes(32),
        0,
        0,
        0,
        0,
    )
    body_bytes = b"".join(
        RECORD.pack(
            ABI_VERSION,
            RECORD.size,
            VERSION,
            record[0],
            record[1],
            record[2],
            record[3],
            record[4],
            record[5],
            record[6],
            record[7],
            record[8],
            flags,
            0,
        )
        for record in records
    ) + b"".join(struct.pack("<I", index) for index in indices)
    packet_hash = hashlib.sha256(header_without_hash + body_bytes).digest()
    header = HEADER.pack(
        MAGIC,
        VERSION,
        ABI_VERSION,
        HEADER.size,
        handle,
        len(records),
        RECORD.size,
        len(indices),
        flags,
        command_count,
        unsupported_count,
        len(source),
        hashlib.sha256(source).digest(),
        packet_hash,
        0,
        0,
        0,
        0,
    )
    packet = header + body_bytes
    return packet, {
        "name": name,
        "handle": handle,
        "records": len(records),
        "indices": len(indices),
        "commands": command_count,
        "unsupported": unsupported_count,
        "textured": int(saw_texture),
        "packet_sha256": hashlib.sha256(packet).hexdigest(),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    root = args.project_root.resolve()
    output = args.output_root.resolve()
    output.mkdir(parents=True, exist_ok=True)
    details: list[dict[str, int | str]] = []
    try:
        for name, handle, relative in MODEL_SPECS:
            source_path = root / relative
            if not source_path.is_file():
                raise PacketError(f"required source listing is missing: {source_path}")
            packet, detail = make_packet(name, handle, source_path.read_bytes())
            (output / f"{name}.getu").write_bytes(packet)
            detail["path"] = str(output / f"{name}.getu")
            details.append(detail)
    except (OSError, UnicodeError, ValueError, struct.error) as error:
        print(f"native title UV: ERROR: {error}")
        return 1

    lines = [
        "report_version=1",
        "goal=native-boot-menu-attract-120",
        "runtime_rom_access=false",
        "visual_parity=not-claimed",
        "lowered_commands=gsDPSetTextureImage,gsSPVertex,gsSP1Triangle,gsSP2Triangles,gsSP4Triangles,gsSPEndDisplayList",
        "unsupported_commands=recorded_not_interpreted",
    ]
    for detail in details:
        for key, value in detail.items():
            lines.append(f"{detail['name']}_{key}={value}")
    lines.append("status=PASS")
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("native title UV: PASS")
    for detail in details:
        print(
            f"  {detail['name']}: records={detail['records']} indices={detail['indices']} "
            f"commands={detail['commands']} unsupported={detail['unsupported']} "
            f"packet={detail['packet_sha256']}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
