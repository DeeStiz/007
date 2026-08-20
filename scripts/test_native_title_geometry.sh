#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/goldeneye-title-geometry.XXXXXX")
trap 'rm -rf "${TEMP_ROOT}"' EXIT

python3 "${SCRIPT_DIR}/prepare_native_title_geometry.py" \
    --project-root "${PROJECT_ROOT}" \
    --output-root "${TEMP_ROOT}/title" \
    --report "${TEMP_ROOT}/title/native-title-geometry-report.txt"

python3 - "${TEMP_ROOT}/title" <<'PY'
import hashlib
import pathlib
import struct
import sys

root = pathlib.Path(sys.argv[1])
expected = {
    "legalpage": (4, 24, 36, 37),
    "nintendologo": (5, 74, 192, 15),
    "goldeneyelogo": (3, 438, 1023, 21),
    "walletbond": (6, 8, 24, 11),
    # Gunbarrel's bounded source model lane: suit/body, head and attached
    # WPPK.  Character display lists use the source's dynamic 0x04 vertex
    # staging segment; the preparation report records that fact in flags.
    "headbrosnansuit": (7, 266, 645, 13),
    "suitbond": (8, 12, 48, 8),
    "chrwppk": (9, 46, 96, 11),
    "rarewarelogo": (1, 381, 804, 84),
}
header_format = "<4sIIIIIIIIiiiiii32s32sI"
header_size = struct.calcsize(header_format)
if header_size != 128:
    raise SystemExit(f"unexpected packet header size: {header_size}")

for name, (handle, vertex_count, index_count, unsupported_count) in expected.items():
    path = root / f"{name}.gepk"
    data = path.read_bytes()
    fields = struct.unpack_from(header_format, data, 0)
    magic, version, actual_handle, flags, source_length, command_count, actual_unsupported, actual_vertices, actual_indices = fields[:9]
    source_hash = fields[15]
    packet_hash = fields[16]
    if magic != b"GETP" or version != 1:
        raise SystemExit(f"{name}: packet envelope mismatch")
    if actual_handle != handle:
        raise SystemExit(f"{name}: handle {actual_handle} != {handle}")
    if (actual_vertices, actual_indices, actual_unsupported) != (vertex_count, index_count, unsupported_count):
        raise SystemExit(
            f"{name}: counts {(actual_vertices, actual_indices, actual_unsupported)} "
            f"!= {(vertex_count, index_count, unsupported_count)}"
        )
    if not (flags & 1) or not (flags & 4) or not (flags & 2):
        raise SystemExit(f"{name}: expected triangle, partial-source and unsupported flags")
    if len(data) != header_size + vertex_count * 16 + index_count * 4:
        raise SystemExit(f"{name}: payload length mismatch")
    canonical = bytearray(data)
    canonical[92:124] = b"\0" * 32
    if hashlib.sha256(canonical).digest() != packet_hash:
        raise SystemExit(f"{name}: packet hash mismatch")
    if fields[17] != 0:
        raise SystemExit(f"{name}: reserved field is nonzero")

    if name == "headbrosnansuit":
        required = (1 << 3) | (1 << 4) | (1 << 5) | (1 << 6) | (1 << 9)
    elif name == "suitbond":
        required = (1 << 3) | (1 << 4) | (1 << 5) | (1 << 7) | (1 << 9)
    elif name == "chrwppk":
        required = (1 << 3) | (1 << 4) | (1 << 8)
    else:
        required = 0
    if required and (flags & required) != required:
        raise SystemExit(f"{name}: source material/model flags missing: 0x{flags:x}")

texture = (root / "rarewarelogo.getx").read_bytes()
texture_header = struct.Struct("<4sIIII32s32s")
if len(texture) < texture_header.size:
    raise SystemExit("rareware texture packet is truncated")
magic, version, width, height, payload_length, source_hash, packet_hash = texture_header.unpack_from(texture, 0)
if (magic, version, width, height) != (b"GETX", 1, 64, 86):
    raise SystemExit("rareware texture packet envelope mismatch")
if payload_length != width * height * 4 or len(texture) != texture_header.size + payload_length:
    raise SystemExit("rareware texture packet payload mismatch")
canonical = bytearray(texture)
canonical[52:84] = b"\0" * 32
if hashlib.sha256(canonical).digest() != packet_hash:
    raise SystemExit("rareware texture packet hash mismatch")
if not source_hash:
    raise SystemExit("rareware texture source hash is missing")
    if not source_length or not command_count or not source_hash:
        raise SystemExit(f"{name}: source evidence is incomplete")

report = (root / "native-title-geometry-report.txt").read_text(encoding="utf-8")
if "status=PASS\n" not in report or "runtime_rom_access=false\n" not in report:
    raise SystemExit("report does not prove PASS/no-ROM preparation")
print("native title geometry smoke: PASS")
print("visual_parity=not-claimed")
print("runtime_rom_access=false")
PY

printf 'smoke_log=%s\n' "/tmp/goldeneye-m15-title-geometry-smoke.log"
printf '%s\n' 'native title geometry smoke: PASS' > /tmp/goldeneye-m15-title-geometry-smoke.log
