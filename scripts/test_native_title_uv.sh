#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/goldeneye-title-uv.XXXXXX")
trap 'rm -rf "${TEMP_ROOT}"' EXIT

python3 "${SCRIPT_DIR}/prepare_native_title_uv.py" \
    --project-root "${PROJECT_ROOT}" \
    --output-root "${TEMP_ROOT}/title" \
    --report "${TEMP_ROOT}/title/native-title-uv-report.txt"

python3 - "${TEMP_ROOT}/title" <<'PY'
import hashlib
import pathlib
import struct
import sys

root = pathlib.Path(sys.argv[1])
header = struct.Struct("<4s11I32s32s4I")
record = struct.Struct("<4I5iIQQII")
expected = {
    "legalpage": (4, 36, 36, 46),
    "nintendologo": (5, 192, 192, 39),
    "goldeneyelogo": (3, 1023, 1023, 145),
}
total_records = 0
for name, (handle, record_count, index_count, command_count) in expected.items():
    data = (root / f"{name}.getu").read_bytes()
    if len(data) < header.size:
        raise SystemExit(f"{name}: header truncated")
    fields = header.unpack_from(data, 0)
    (magic, version, abi, header_size, actual_handle, actual_records, stride,
     actual_indices, flags, actual_commands, unsupported, source_bytes,
     source_hash, packet_hash, *reserved) = fields
    if (magic, version, abi, header_size, actual_handle, actual_records,
        stride, actual_indices, actual_commands) != (
            b"GETU", 1, 1, 128, handle, record_count, 64, index_count, command_count
    ):
        raise SystemExit(f"{name}: envelope mismatch")
    if flags & ~0x7f or not (flags & 1) or not (flags & 4) or not (flags & 0x10) or not (flags & 0x20) or not (flags & 0x40):
        raise SystemExit(f"{name}: flags mismatch: 0x{flags:x}")
    if unsupported == 0 or source_bytes == 0 or not source_hash.strip(b"\0"):
        raise SystemExit(f"{name}: source evidence missing")
    if any(reserved) or len(data) != header.size + record_count * record.size + index_count * 4:
        raise SystemExit(f"{name}: layout/reserved mismatch")
    canonical = bytearray(data)
    canonical[80:112] = b"\0" * 32
    if hashlib.sha256(canonical).digest() != packet_hash:
        raise SystemExit(f"{name}: packet hash mismatch")
    for index in range(record_count):
        values = record.unpack_from(data, header.size + index * record.size)
        if values[0:3] != (1, 64, 1) or values[3] != index or values[12] != flags or values[13] != 0:
            raise SystemExit(f"{name}: record {index} ABI/index/flags mismatch")
        if values[10] == 0 or values[11] == 0:
            raise SystemExit(f"{name}: record {index} hash missing")
    index_base = header.size + record_count * record.size
    for index in range(index_count):
        actual = struct.unpack_from("<I", data, index_base + index * 4)[0]
        if actual != index:
            raise SystemExit(f"{name}: index {index} != {actual}")
    total_records += record_count
report = (root / "native-title-uv-report.txt").read_text(encoding="utf-8")
if "status=PASS\n" not in report or "runtime_rom_access=false\n" not in report:
    raise SystemExit("GETU report does not prove PASS/no-ROM preparation")
print(f"native title UV packet envelope/hash: PASS records={total_records}")
PY

swiftc -O -parse-as-library \
    "${PROJECT_ROOT}/native/host/goldeneye_title_uv_packet.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_title_uv_packet_smoke.swift" \
    -o "${TEMP_ROOT}/goldeneye_title_uv_packet_smoke"
"${TEMP_ROOT}/goldeneye_title_uv_packet_smoke" "${TEMP_ROOT}/title"

CLANG=$(xcrun --sdk macosx --find clang)
MACOS_SDK=$(xcrun --sdk macosx --show-sdk-path)
CLANG_FLAGS=(-isysroot "${MACOS_SDK}" -target arm64-apple-macosx27.0 -std=c11 -Wall -Wextra -Werror -I"${PROJECT_ROOT}/native/include")
"${CLANG}" "${CLANG_FLAGS[@]}" \
    "${PROJECT_ROOT}/native/tests/goldeneye_title_uv_packet_layout_smoke.c" \
    -o "${TEMP_ROOT}/goldeneye_title_uv_packet_layout_smoke"
"${TEMP_ROOT}/goldeneye_title_uv_packet_layout_smoke"

"${CLANG}" "${CLANG_FLAGS[@]}" -fsanitize=address -fno-omit-frame-pointer \
    "${PROJECT_ROOT}/native/tests/goldeneye_title_uv_packet_layout_smoke.c" \
    -o "${TEMP_ROOT}/goldeneye_title_uv_packet_layout_smoke_asan"
ASAN_OPTIONS=halt_on_error=1 "${TEMP_ROOT}/goldeneye_title_uv_packet_layout_smoke_asan"

"${CLANG}" "${CLANG_FLAGS[@]}" -fsanitize=undefined -fno-omit-frame-pointer \
    "${PROJECT_ROOT}/native/tests/goldeneye_title_uv_packet_layout_smoke.c" \
    -o "${TEMP_ROOT}/goldeneye_title_uv_packet_layout_smoke_ubsan"
UBSAN_OPTIONS=halt_on_error=1 "${TEMP_ROOT}/goldeneye_title_uv_packet_layout_smoke_ubsan"

printf '%s\n' 'native title UV smoke: PASS'
