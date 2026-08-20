#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="${PROJECT_ROOT}/build/native/source-lighting-v6"
mkdir -p "${BUILD_DIR}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
SWIFT_FLAGS=(
    -swift-version 6
    -warnings-as-errors
    -O
    -parse-as-library
    -target arm64-apple-macosx27.0
    -sdk "${SDKROOT}"
    -framework Foundation
    -framework CoreGraphics
)
SOURCES=(
    "${PROJECT_ROOT}/native/host/goldeneye_source_lighting_v6.swift"
    "${PROJECT_ROOT}/native/tests/goldeneye_source_lighting_v6_smoke.swift"
)

echo "Building strict source lighting/texgen fixture"
"${SWIFTC}" "${SWIFT_FLAGS[@]}" "${SOURCES[@]}" \
    -o "${BUILD_DIR}/goldeneye_source_lighting_v6_smoke"
"${BUILD_DIR}/goldeneye_source_lighting_v6_smoke" \
    | tee "${BUILD_DIR}/strict.log"
grep -Fq 'goldeneye_source_lighting_v6_smoke: PASS' "${BUILD_DIR}/strict.log"

echo "Building ASan source lighting/texgen fixture"
"${SWIFTC}" "${SWIFT_FLAGS[@]}" -sanitize=address "${SOURCES[@]}" \
    -o "${BUILD_DIR}/goldeneye_source_lighting_v6_smoke_asan"
ASAN_OPTIONS=halt_on_error=1 \
    "${BUILD_DIR}/goldeneye_source_lighting_v6_smoke_asan" \
    | tee "${BUILD_DIR}/asan.log"
grep -Fq 'goldeneye_source_lighting_v6_smoke: PASS' "${BUILD_DIR}/asan.log"

echo 'Source lighting/texgen V6 validation: PASS (strict, ASan)'
