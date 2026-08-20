#!/usr/bin/env python3
"""Lower frontend ModelNode trees into a bounded GETN value packet.

Preparation reads checked-in generated Model.c listings only.  The packet
contains source-local offsets and copied scalar metadata; it never carries a
pointer, Gfx word, segmented address, or model graph.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import struct
from pathlib import Path

MAGIC = b"GETN"
VERSION = 1
HEADER = struct.Struct("<4sIIIIIII32s32sI")
NODE = struct.Struct("<12I")
TEXTURE = struct.Struct("<8I")
assert HEADER.size == 100
assert NODE.size == 48
assert TEXTURE.size == 32

OPCODES = {
    "GROUP": 0, "DL": 2, "LOD": 6, "BSP": 7, "BBOX": 8,
    "SWITCH": 16, "GROUPSIMPLE": 19, "DLPRIMARY": 20,
    "HEAD": 21, "DLCOLLISION": 22,
}
SPECS = {
    "legalpage": (4, Path("assets/obseg/prop/legalpage/Model.c")),
    "nintendologo": (5, Path("assets/obseg/prop/nintendologo/Model.c")),
    "goldeneyelogo": (3, Path("assets/obseg/prop/goldeneyelogo/Model.c")),
    "walletbond": (6, Path("assets/obseg/prop/walletbond/Model.c")),
}


def integer(value: str) -> int:
    value = value.strip()
    value = re.sub(r"/\*.*?\*/", "", value, flags=re.S)
    value = re.sub(r"//[^\n]*", "", value).strip()
    value = re.sub(r"[uUlL]+$", "", value)
    try:
        return int(value, 16 if value.lower().startswith("0x") else 10)
    except ValueError:
        # Wallet texture rows use symbolic IMAGE_* IDs. Keep a deterministic
        # value-only token rather than carrying the source macro or pointer.
        token = value.encode("utf-8")
        hashed = 2166136261
        for byte in token:
            hashed = ((hashed ^ byte) * 16777619) & 0xFFFFFFFF
        return 0x80000000 | (hashed & 0x7FFFFFFF)


def ref(value: str) -> int:
    value = value.strip()
    if value == "NULL":
        return 0xFFFFFFFF
    match = re.search(r"ModelNode_0x([0-9a-fA-F]+)", value)
    return int(match.group(1), 16) if match else 0xFFFFFFFF


def record_offset(value: str) -> int:
    match = re.search(r"Record_0x([0-9a-fA-F]+)", value)
    return int(match.group(1), 16) if match else 0xFFFFFFFF


def parse(source: bytes, handle: int) -> bytes:
    text = source.decode("utf-8")
    nodes = []
    node_re = re.compile(
        r"ModelNode\s+ModelNode_0x([0-9a-fA-F]+)\s*=\s*\{"
        r"\s*MODELNODE_OPCODE_([A-Z0-9_]+)\s*,\s*([^,]+),"
        r"\s*([^,]+),\s*([^,]+),\s*([^,]+),\s*([^}]+)\s*\};",
        re.S,
    )
    for match in node_re.finditer(text):
        opcode_name = match.group(2)
        if opcode_name not in OPCODES:
            # Preserve unknown nodes as a stable opcode sentinel rather than
            # silently dropping the source hierarchy.
            opcode = 0x80000000 | (sum(ord(c) for c in opcode_name) & 0x7FFFFFFF)
        else:
            opcode = OPCODES[opcode_name]
        values = [
            int(match.group(1), 16), opcode, record_offset(match.group(3)),
            ref(match.group(4)), ref(match.group(5)), ref(match.group(6)),
            ref(match.group(7)),
        ]
        values.extend([0xFFFFFFFF] * 5)
        nodes.append((int(match.group(1), 16), values, opcode_name))
    if not nodes:
        raise ValueError("no ModelNode initializers")
    nodes.sort(key=lambda item: item[0])

    # Enrich DL records with source-local primary/secondary/vertex offsets.
    for node_offset, values, _ in nodes:
        record = values[2]
        if record == 0xFFFFFFFF:
            continue
        record_re = re.compile(
            rf"DisplayListRecord_0x{record:x}\s*=\s*\{{(.*?)\}};", re.S
        )
        match = record_re.search(text)
        if not match:
            continue
        body = match.group(1)
        primary = re.search(r"GFX_PRIMARY_0x([0-9a-fA-F]+)", body)
        secondary = re.search(r"GFX_SECONDARY_0x([0-9a-fA-F]+)", body)
        vertex = re.search(r"Vertex_0x([0-9a-fA-F]+)", body)
        nums = re.search(r"Vertex_0x[0-9a-fA-F]+\s*,\s*([^,]+)\s*,\s*([^,}]+)", body)
        values[7] = int(primary.group(1), 16) if primary else 0xFFFFFFFF
        values[8] = int(secondary.group(1), 16) if secondary else 0xFFFFFFFF
        values[9] = int(vertex.group(1), 16) if vertex else 0xFFFFFFFF
        values[10] = integer(nums.group(1)) if nums else 0
        values[11] = integer(nums.group(2)) & 0xFF if nums else 0

    textures = []
    tex_re = re.compile(r"ModelFileTextures\s+proptextures\[[^]]+\]\s*=\s*\{(.*?)\};", re.S)
    match = tex_re.search(text)
    if match:
        for row in re.finditer(r"\{([^{}]+)\}", match.group(1)):
            parts = [p.strip() for p in row.group(1).split(",") if p.strip()]
            if len(parts) != 8:
                raise ValueError("malformed ModelFileTextures row")
            values = [integer(p) for p in parts]
            values[0] &= 0x00FFFFFF  # retain a source-local model offset only
            textures.append(values)

    node_payload = b"".join(NODE.pack(*values) for _, values, _ in nodes)
    texture_payload = b"".join(TEXTURE.pack(*values) for values in textures)
    source_hash = hashlib.sha256(source).digest()
    header = HEADER.pack(
        MAGIC, VERSION, handle, len(nodes), len(textures), NODE.size,
        TEXTURE.size, len(source), source_hash, bytes(32), 0
    )
    packet_hash = hashlib.sha256(header + node_payload + texture_payload).digest()
    header = HEADER.pack(
        MAGIC, VERSION, handle, len(nodes), len(textures), NODE.size,
        TEXTURE.size, len(source), source_hash, packet_hash, 0
    )
    return header + node_payload + texture_payload


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output-root", type=Path, default=None)
    parser.add_argument("--report", type=Path, default=None)
    args = parser.parse_args()
    root = args.project_root.resolve()
    out = (args.output_root or root / "build/native/boot-assets/title").resolve()
    out.mkdir(parents=True, exist_ok=True)
    report = args.report or out / "native-title-node-report.txt"
    rows = []
    for name, (handle, relative) in SPECS.items():
        source_path = root / relative
        source = source_path.read_bytes()
        packet = parse(source, handle)
        path = out / f"{name}.getn"
        path.write_bytes(packet)
        fields = HEADER.unpack_from(packet, 0)
        # Report the embedded canonical packet hash (header field), not a
        # second hash of the complete packet file.
        rows.append((name, handle, fields[3], fields[4], fields[9].hex(), path))
    report.write_text(
        "\n".join([
            "report_version=1", "goal=native-boot-menu-attract-120",
            "runtime_rom_access=false", "status=PASS",
            *[f"{n}_handle={h}\n{n}_nodes={nc}\n{n}_textures={tc}\n{n}_packet_sha256={ph}\n{n}_path={p}"
              for n, h, nc, tc, ph, p in rows],
        ]) + "\n", encoding="utf-8"
    )
    print("native title nodes: PASS")
    for name, handle, node_count, texture_count, packet_hash, _ in rows:
        print(f"  {name}: handle={handle} nodes={node_count} textures={texture_count} packet={packet_hash}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
