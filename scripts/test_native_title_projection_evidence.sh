#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/goldeneye-title-projection-evidence.XXXXXX")
trap 'rm -rf "${TEMP_ROOT}"' EXIT

python3 "${SCRIPT_DIR}/prepare_native_title_geometry.py" \
    --project-root "${PROJECT_ROOT}" \
    --output-root "${TEMP_ROOT}/title" \
    --report "${TEMP_ROOT}/title/native-title-geometry-report.txt" >/dev/null

SWIFTC=$(xcrun --sdk macosx --find swiftc)
SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
SOURCES=(
    "${PROJECT_ROOT}/native/host/goldeneye_projection_v10.swift"
    "${PROJECT_ROOT}/native/host/title_geometry_packet.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_title_projection_evidence.swift"
    "${PROJECT_ROOT}/native/tests/goldeneye_title_projection_evidence_smoke.swift"
)
ARGS=(-swift-version 6 -warnings-as-errors -target arm64-apple-macosx27.0 -sdk "${SDKROOT}")
"${SWIFTC}" "${ARGS[@]}" "${SOURCES[@]}" -o "${TEMP_ROOT}/smoke"
"${TEMP_ROOT}/smoke" "${TEMP_ROOT}/title"
"${SWIFTC}" "${ARGS[@]}" -sanitize=address "${SOURCES[@]}" -o "${TEMP_ROOT}/smoke-asan"
ASAN_OPTIONS=halt_on_error=1 "${TEMP_ROOT}/smoke-asan" "${TEMP_ROOT}/title"

git -C "${PROJECT_ROOT}" diff --check
echo 'Native M10 title projection evidence validation: PASS'
