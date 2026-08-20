#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${1:-${GOLDENEYE_NATIVE_SOURCE_FRONTEND_ROOT:-${PROJECT_ROOT}/build/native/source-frontend-v6}}"
BUILD_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/goldeneye-source-texture-setup-v6.XXXXXX")
trap 'rm -rf "${BUILD_ROOT}"' EXIT
mkdir -p "${BUILD_ROOT}/module-cache"
export CLANG_MODULE_CACHE_PATH="${BUILD_ROOT}/module-cache"

if command -v xcrun >/dev/null 2>&1; then
    SWIFTC=$(xcrun --sdk macosx --find swiftc)
    SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
    SWIFT_PLATFORM=(-target arm64-apple-macosx27.0 -sdk "${SDKROOT}")
else
    SWIFTC=${SWIFTC:-swiftc}
    SWIFT_PLATFORM=()
fi

SMOKE="${BUILD_ROOT}/goldeneye_source_texture_setup_v6_smoke"
LOG="${BUILD_ROOT}/source-texture-setup-v6.log"
SOURCES=(
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_catalog_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_source_model_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_setup_v6.swift"
    "${PROJECT_ROOT}/native/tests/goldeneye_source_texture_setup_v6_smoke.swift"
)

"${SWIFTC}" -swift-version 6 -warnings-as-errors -O -parse-as-library \
    "${SWIFT_PLATFORM[@]}" \
    "${SOURCES[@]}" \
    -o "${SMOKE}"

"${SMOKE}" "${ASSET_ROOT}" | tee "${LOG}"
grep -Fq 'goldeneye_source_texture_setup_v6_smoke: PASS' "${LOG}"

"${SWIFTC}" -swift-version 6 -warnings-as-errors -O -sanitize=address -parse-as-library \
    "${SWIFT_PLATFORM[@]}" "${SOURCES[@]}" \
    -o "${BUILD_ROOT}/goldeneye_source_texture_setup_v6_smoke_asan"
ASAN_OPTIONS=halt_on_error=1 \
    "${BUILD_ROOT}/goldeneye_source_texture_setup_v6_smoke_asan" "${ASSET_ROOT}" \
    | tee "${BUILD_ROOT}/source-texture-setup-v6-asan.log"
grep -Fq 'goldeneye_source_texture_setup_v6_smoke: PASS' "${BUILD_ROOT}/source-texture-setup-v6-asan.log"

"${SWIFTC}" -swift-version 6 -warnings-as-errors -O -sanitize=undefined -parse-as-library \
    "${SWIFT_PLATFORM[@]}" "${SOURCES[@]}" \
    -o "${BUILD_ROOT}/goldeneye_source_texture_setup_v6_smoke_ubsan"
UBSAN_OPTIONS=halt_on_error=1 \
    "${BUILD_ROOT}/goldeneye_source_texture_setup_v6_smoke_ubsan" "${ASSET_ROOT}" \
    | tee "${BUILD_ROOT}/source-texture-setup-v6-ubsan.log"
grep -Fq 'goldeneye_source_texture_setup_v6_smoke: PASS' "${BUILD_ROOT}/source-texture-setup-v6-ubsan.log"

echo "Source texture setup V6 strict/Swift validation: PASS"
echo "Artifact: ${LOG}"
