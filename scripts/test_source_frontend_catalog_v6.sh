#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${1:-${GOLDENEYE_NATIVE_SOURCE_FRONTEND_ROOT:-${PROJECT_ROOT}/build/native/source-frontend-v6}}"
BUILD_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/goldeneye-source-frontend-v6.XXXXXX")
trap 'rm -rf "${BUILD_ROOT}"' EXIT

if command -v xcrun >/dev/null 2>&1; then
    SWIFTC=$(xcrun --sdk macosx --find swiftc)
    SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
    SWIFT_PLATFORM=(-target arm64-apple-macosx27.0 -sdk "${SDKROOT}")
else
    SWIFTC=${SWIFTC:-swiftc}
    SWIFT_PLATFORM=()
fi

"${SWIFTC}" -swift-version 6 -warnings-as-errors -O -parse-as-library \
    "${SWIFT_PLATFORM[@]}" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_catalog_v6.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_source_frontend_catalog_v6_smoke.swift" \
    -o "${BUILD_ROOT}/goldeneye_source_frontend_catalog_v6_smoke"

"${BUILD_ROOT}/goldeneye_source_frontend_catalog_v6_smoke" "${ASSET_ROOT}" \
    | tee "${BUILD_ROOT}/valid.log"
grep -Fq 'goldeneye_source_frontend_catalog_v6_smoke: PASS records=' \
    "${BUILD_ROOT}/valid.log"

python3 - "${ASSET_ROOT}/source-frontend-v6.gefv" "${BUILD_ROOT}" <<'PY'
import hashlib
import json
import pathlib
import struct
import sys

packet_path = pathlib.Path(sys.argv[1])
out_root = pathlib.Path(sys.argv[2])
header = struct.Struct("<4sIIIIII32s32sI")
data = packet_path.read_bytes()
magic, version, record_count, manifest_size, payload_size, source_size, flags, source_hash, packet_hash, reserved = header.unpack_from(data, 0)
manifest_start = header.size
manifest_end = manifest_start + manifest_size
manifest = json.loads(data[manifest_start:manifest_end].decode("utf-8"))
payload = data[manifest_end:]

def emit(name, mutate):
    value = json.loads(json.dumps(manifest))
    mutate(value)
    encoded = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    zero = header.pack(magic, version, record_count, len(encoded), len(payload), source_size, flags, source_hash, bytes(32), reserved)
    digest = hashlib.sha256(zero + encoded + payload).digest()
    output = header.pack(magic, version, record_count, len(encoded), len(payload), source_size, flags, source_hash, digest, reserved) + encoded + payload
    packet = out_root / name / "source-frontend-v6.gefv"
    packet.parent.mkdir(parents=True, exist_ok=True)
    packet.write_bytes(output)

emit("path", lambda value: value["records"][0].__setitem__("source_path", "/private/rom/GoldenEye.z64"))
emit("bounds", lambda value: value["records"][0].__setitem__("raw_payload_offset", payload_size + 1))
emit("unknown", lambda value: value["records"][0].__setitem__("untrusted_field", 1))

tampered = bytearray(data)
tampered[-1] ^= 1
tampered_packet = out_root / "tampered" / "source-frontend-v6.gefv"
tampered_packet.parent.mkdir(parents=True, exist_ok=True)
tampered_packet.write_bytes(tampered)
truncated_packet = out_root / "truncated" / "source-frontend-v6.gefv"
truncated_packet.parent.mkdir(parents=True, exist_ok=True)
truncated_packet.write_bytes(data[:-1])
PY

for variant in path bounds unknown tampered truncated; do
    cp "${ASSET_ROOT}"/*.gesm "${BUILD_ROOT}/${variant}/"
done

run_expected() {
    local root="$1"
    local needle="$2"
    "${BUILD_ROOT}/goldeneye_source_frontend_catalog_v6_smoke" "${root}" "${needle}" \
        | tee "${BUILD_ROOT}/$(basename "${root}").log"
}

run_expected "${BUILD_ROOT}/tampered" 'packet SHA-256 mismatch'
run_expected "${BUILD_ROOT}/truncated" 'manifest/payload bounds'
run_expected "${BUILD_ROOT}/path" 'source_path'
run_expected "${BUILD_ROOT}/bounds" 'payload bounds'
run_expected "${BUILD_ROOT}/unknown" 'unknown field'

echo "Source frontend V6 runtime catalog strict/tamper/path/bounds validation: PASS"
