#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/goldeneye-title-icons.XXXXXX")
trap 'rm -rf "${TEMP_ROOT}"' EXIT

python3 "${SCRIPT_DIR}/prepare_native_title_icons.py" \
    --project-root "${PROJECT_ROOT}" \
    --output-root "${TEMP_ROOT}" \
    --report "${TEMP_ROOT}/native-title-icons-report.txt"

python3 - "${TEMP_ROOT}/title-icons.geti" "${TEMP_ROOT}/native-title-icons-report.txt" <<'PY'
import hashlib
import pathlib
import struct
import sys

packet_path = pathlib.Path(sys.argv[1])
report_path = pathlib.Path(sys.argv[2])
data = packet_path.read_bytes()
header = struct.Struct("<4sIIIIII32s32sI")
record = struct.Struct("<IIIIIIIIIII32s32s")
if len(data) < header.size:
    raise SystemExit("icon packet is truncated")
magic, version, count, record_bytes, payload_bytes, source_bytes, reserved, source_hash, packet_hash, reserved_tail = header.unpack_from(data)
if (magic, version, count, record_bytes, reserved, reserved_tail) != (b"GETI", 1, 7, 7 * record.size, 0, 0):
    raise SystemExit("icon packet envelope mismatch")
if len(data) != header.size + record_bytes + payload_bytes:
    raise SystemExit("icon packet length mismatch")
canonical = bytearray(data)
canonical[60:92] = b"\0" * 32
if hashlib.sha256(canonical).digest() != packet_hash:
    raise SystemExit("icon packet hash mismatch")
names = ["COPYICON", "DELICON", "SELECTFILE", "CROSSHAIR1", "CHECK", "DOT", "X"]
dims = [(32, 28), (32, 28), (122, 18), (32, 32), (20, 20), (16, 16), (15, 15)]
payload_base = header.size + record_bytes
cursor = 0
for index, name in enumerate(names):
    fields = record.unpack_from(data, header.size + index * record.size)
    icon, width, height, fmt, compression, s_flags, t_flags, source_size, decoded_size, payload_offset, reserved_record = fields[:11]
    source_digest, decoded_digest = fields[11:]
    if icon != index or (width, height) != dims[index] or reserved_record != 0:
        raise SystemExit(f"{name}: metadata mismatch")
    if payload_offset != cursor or decoded_size != width * height * 4:
        raise SystemExit(f"{name}: payload bounds mismatch")
    pixel = data[payload_base + payload_offset : payload_base + payload_offset + decoded_size]
    if hashlib.sha256(pixel).digest() != decoded_digest:
        raise SystemExit(f"{name}: decoded hash mismatch")
    cursor += decoded_size
if cursor != payload_bytes or source_bytes != 6984 or not source_hash.strip(b"\0"):
    raise SystemExit("icon payload/source evidence mismatch")
report = report_path.read_text(encoding="utf-8")
if "status=PASS\n" not in report or "runtime_rom_access=false\n" not in report or "visual_parity=not-claimed\n" not in report:
    raise SystemExit("icon report is incomplete")
print("icon packet envelope/hash/layout: PASS")
PY

swiftc -O -parse-as-library \
    "${PROJECT_ROOT}/native/host/goldeneye_title_icon_packet.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_title_icon_packet_smoke.swift" \
    -o "${TEMP_ROOT}/goldeneye_title_icon_packet_smoke"
"${TEMP_ROOT}/goldeneye_title_icon_packet_smoke" "${TEMP_ROOT}"

printf '%s\n' 'native title icon smoke: PASS'
