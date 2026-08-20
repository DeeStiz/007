#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="${PROJECT_ROOT}/build/native/projection-v10"
mkdir -p "${BUILD_DIR}"

if command -v xcrun >/dev/null 2>&1; then
    SWIFTC=$(xcrun --sdk macosx --find swiftc)
    SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
else
    SWIFTC=${SWIFTC:-swiftc}
    SDKROOT=""
fi

SWIFT_SOURCES=(
    "${PROJECT_ROOT}/native/host/goldeneye_projection_v10.swift"
    "${PROJECT_ROOT}/native/tests/goldeneye_projection_v10_smoke.swift"
)

STRICT_ARGS=(-swift-version 6 -warnings-as-errors -O)
SANITIZED_ARGS=(-swift-version 6 -warnings-as-errors -O -sanitize=address)
if [[ -n "${SDKROOT}" ]]; then
    STRICT_ARGS+=(-target arm64-apple-macosx27.0 -sdk "${SDKROOT}")
    SANITIZED_ARGS+=(-target arm64-apple-macosx27.0 -sdk "${SDKROOT}")
fi

"${SWIFTC}" "${STRICT_ARGS[@]}" "${SWIFT_SOURCES[@]}" \
    -o "${BUILD_DIR}/goldeneye_projection_v10_smoke"
"${BUILD_DIR}/goldeneye_projection_v10_smoke" | tee "${BUILD_DIR}/strict.log"
grep -Fq 'goldeneye_projection_v10_smoke: PASS' "${BUILD_DIR}/strict.log"

"${SWIFTC}" "${SANITIZED_ARGS[@]}" "${SWIFT_SOURCES[@]}" \
    -o "${BUILD_DIR}/goldeneye_projection_v10_smoke_asan"
ASAN_OPTIONS=halt_on_error=1 \
    "${BUILD_DIR}/goldeneye_projection_v10_smoke_asan" | tee "${BUILD_DIR}/asan.log"
grep -Fq 'goldeneye_projection_v10_smoke: PASS' "${BUILD_DIR}/asan.log"

git -C "${PROJECT_ROOT}" diff --check
echo 'Native M10 projection validation: PASS'
