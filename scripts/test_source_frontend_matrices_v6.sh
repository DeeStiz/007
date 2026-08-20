#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="${PROJECT_ROOT}/build/native/source-frontend-matrices-v6"
STRICT_DIR="${BUILD_DIR}/strict"
SANITIZER_DIR="${BUILD_DIR}/sanitizers"
mkdir -p "${STRICT_DIR}" "${SANITIZER_DIR}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
SOURCES=(
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_matrices_v6.swift"
    "${PROJECT_ROOT}/native/tests/goldeneye_source_frontend_matrices_v6_smoke.swift"
)
ARGS=(-D GE_SOURCE_MATRIX_STANDALONE -swift-version 6 -warnings-as-errors
    -target arm64-apple-macosx27.0 -sdk "${SDKROOT}")

"${SWIFTC}" "${ARGS[@]}" -O "${SOURCES[@]}" \
    -o "${STRICT_DIR}/goldeneye_source_frontend_matrices_v6_smoke"
"${STRICT_DIR}/goldeneye_source_frontend_matrices_v6_smoke" \
    | tee "${STRICT_DIR}/matrices-v6.log"
grep -Fq 'goldeneye_source_frontend_matrices_v6_smoke: PASS' \
    "${STRICT_DIR}/matrices-v6.log"

"${SWIFTC}" "${ARGS[@]}" -sanitize=address -O "${SOURCES[@]}" \
    -o "${SANITIZER_DIR}/goldeneye_source_frontend_matrices_v6_smoke"
ASAN_OPTIONS=halt_on_error=1 \
    "${SANITIZER_DIR}/goldeneye_source_frontend_matrices_v6_smoke" \
    | tee "${SANITIZER_DIR}/matrices-v6.log"
grep -Fq 'goldeneye_source_frontend_matrices_v6_smoke: PASS' \
    "${SANITIZER_DIR}/matrices-v6.log"

git -C "${PROJECT_ROOT}" diff --check -- \
    native/host/goldeneye_source_frontend_matrices_v6.swift \
    native/tests/goldeneye_source_frontend_matrices_v6_smoke.swift \
    scripts/test_source_frontend_matrices_v6.sh

echo 'Source frontend matrix V6 validation: PASS (strict, ASan)'
echo "Artifact: ${STRICT_DIR}/matrices-v6.log"
