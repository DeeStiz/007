#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
PREPARED_ROOT="${GOLDENEYE_NATIVE_ASSET_ROOT:-${PROJECT_ROOT}/build/native/boot-assets}"
TITLE_ROOT="${PREPARED_ROOT}/title"
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/goldeneye-title-textures.XXXXXX")
trap 'rm -rf "${TEMP_ROOT}"' EXIT

if [[ ! -f "${TITLE_ROOT}/legalpage.bin" || ! -f "${TITLE_ROOT}/walletbond.bin" ]]; then
    echo "native title texture smoke: prepared model blobs are missing at ${TITLE_ROOT}" >&2
    echo "run scripts/build_native_boot.sh /absolute/path/to/GoldenEye-007-US.z64 first" >&2
    exit 2
fi

# Re-emit into a private ignored test directory so the parser is exercised on
# a fresh packet and never mutates the caller's prepared artifacts.
mkdir -p "${TEMP_ROOT}/title"
cp -f "${TITLE_ROOT}"/*.bin "${TEMP_ROOT}/title/"
python3 "${SCRIPT_DIR}/prepare_native_title_textures.py" \
    --project-root "${PROJECT_ROOT}" \
    --output-root "${TEMP_ROOT}/title" \
    --report "${TEMP_ROOT}/title/native-title-texture-report.txt"

python3 - "${TEMP_ROOT}/title" <<'PY'
import hashlib
import pathlib
import struct
import sys

root = pathlib.Path(sys.argv[1])
header = struct.Struct("<4sIIIIIIIII32s32s6I")
record = struct.Struct("<" + "I" * 20 + "32s32s")
expected = {"legalpage": (4, 5), "nintendologo": (5, 1), "goldeneyelogo": (3, 2), "walletbond": (6, 84)}
total_records = 0
for name, (handle, count) in expected.items():
    data = (root / f"{name}.gett").read_bytes()
    if len(data) < header.size:
        raise SystemExit(f"{name}: header truncated")
    fields = header.unpack_from(data, 0)
    magic, version, abi, header_size, actual_handle, actual_count, stride, payload_bytes, source_bytes, packet_flags = fields[:10]
    source_hash, packet_hash = fields[10:12]
    reserved = fields[12:]
    if (magic, version, abi, header_size, actual_handle, actual_count, stride) != (b"GETT", 1, 1, 128, handle, count, 144):
        raise SystemExit(f"{name}: envelope mismatch")
    if payload_bytes <= 0 or source_bytes <= 0 or not source_hash.strip(b"\0"):
        raise SystemExit(f"{name}: source/payload evidence missing")
    if any(reserved) or packet_flags not in (1, 2):
        raise SystemExit(f"{name}: reserved/packet flags mismatch")
    expected_len = header.size + count * record.size + payload_bytes
    if len(data) != expected_len:
        raise SystemExit(f"{name}: packet length mismatch")
    canonical = bytearray(data)
    canonical[72:104] = b"\0" * 32
    if hashlib.sha256(canonical).digest() != packet_hash:
        raise SystemExit(f"{name}: packet hash mismatch")
    payload_base = header.size + count * record.size
    cursor = 0
    for index in range(count):
        values = record.unpack_from(data, header.size + index * record.size)
        if values[0:3] != (1, 144, 1) or values[19] != 0:
            raise SystemExit(f"{name}: record {index} ABI/reserved mismatch")
        width, height = values[4], values[5]
        decoded_count, payload_offset, flags, source_count = values[14], values[16], values[17], values[18]
        source_digest, decoded_digest = values[20], values[21]
        if width == 0 or height == 0 or decoded_count != width * height * 4:
            raise SystemExit(f"{name}: record {index} dimensions/decoded count")
        if payload_offset != cursor or source_count == 0 or not source_digest.strip(b"\0"):
            raise SystemExit(f"{name}: record {index} payload/source metadata")
        if not (flags & (1 << 2)) or ((flags & 1) == 0) == ((flags & 2) == 0):
            raise SystemExit(f"{name}: record {index} source flags")
        end = payload_offset + decoded_count
        pixels = data[payload_base + payload_offset : payload_base + end]
        if len(pixels) != decoded_count or hashlib.sha256(pixels).digest() != decoded_digest:
            raise SystemExit(f"{name}: record {index} decoded hash")
        cursor = end
    if cursor != payload_bytes:
        raise SystemExit(f"{name}: payload cursor mismatch")
    total_records += count
print(f"native title texture packet envelope/hash: PASS records={total_records}")
PY

swiftc -O -parse-as-library \
    "${PROJECT_ROOT}/native/host/goldeneye_title_texture_packet.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_title_texture_packet_smoke.swift" \
    -o "${TEMP_ROOT}/goldeneye_title_texture_packet_smoke"
"${TEMP_ROOT}/goldeneye_title_texture_packet_smoke" "${TEMP_ROOT}/title"

CLANG=$(xcrun --sdk macosx --find clang)
MACOS_SDK=$(xcrun --sdk macosx --show-sdk-path)
CLANG_FLAGS=(-isysroot "${MACOS_SDK}" -target arm64-apple-macosx27.0 -std=c11 -Wall -Wextra -Werror -I"${PROJECT_ROOT}/native/include")
"${CLANG}" "${CLANG_FLAGS[@]}" \
    "${PROJECT_ROOT}/native/tests/goldeneye_title_texture_packet_layout_smoke.c" \
    -o "${TEMP_ROOT}/goldeneye_title_texture_packet_layout_smoke"
"${TEMP_ROOT}/goldeneye_title_texture_packet_layout_smoke"

"${CLANG}" "${CLANG_FLAGS[@]}" \
    -fsanitize=address -fno-omit-frame-pointer \
    "${PROJECT_ROOT}/native/tests/goldeneye_title_texture_packet_layout_smoke.c" \
    -o "${TEMP_ROOT}/goldeneye_title_texture_packet_layout_smoke_asan"
ASAN_OPTIONS=halt_on_error=1 "${TEMP_ROOT}/goldeneye_title_texture_packet_layout_smoke_asan"

"${CLANG}" "${CLANG_FLAGS[@]}" \
    -fsanitize=undefined -fno-omit-frame-pointer \
    "${PROJECT_ROOT}/native/tests/goldeneye_title_texture_packet_layout_smoke.c" \
    -o "${TEMP_ROOT}/goldeneye_title_texture_packet_layout_smoke_ubsan"
UBSAN_OPTIONS=halt_on_error=1 "${TEMP_ROOT}/goldeneye_title_texture_packet_layout_smoke_ubsan"

printf '%s\n' 'native title texture smoke: PASS'
