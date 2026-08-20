#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${1:-${GOLDENEYE_NATIVE_RAMROM_VISIBLE_ROOT:-${PROJECT_ROOT}/build/native/ramrom-visible-dependencies-v6}}"
BUILD_ROOT="${PROJECT_ROOT}/build/native/ramrom-non-model-visuals-v6"
MODULE_CACHE_DIR="${BUILD_ROOT}/module-cache"
mkdir -p "${BUILD_ROOT}" "${MODULE_CACHE_DIR}"

if command -v xcrun >/dev/null 2>&1; then
    SWIFTC=$(xcrun --sdk macosx --find swiftc)
    SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
    SWIFT_PLATFORM=(-target arm64-apple-macosx27.0 -sdk "${SDKROOT}")
else
    SWIFTC=${SWIFTC:-swiftc}
    SWIFT_PLATFORM=()
fi

SOURCES=(
    "${PROJECT_ROOT}/native/host/goldeneye_ramrom_non_model_visuals_v6.swift"
    "${PROJECT_ROOT}/native/tests/goldeneye_ramrom_non_model_visuals_v6_smoke.swift"
)
SMOKE="${BUILD_ROOT}/goldeneye_ramrom_non_model_visuals_v6_smoke"
LOG="${BUILD_ROOT}/ramrom-non-model-visuals-v6.log"

CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${SWIFTC}" \
    -swift-version 6 -warnings-as-errors -O -parse-as-library \
    "${SWIFT_PLATFORM[@]}" "${SOURCES[@]}" -o "${SMOKE}"
"${SMOKE}" "${ASSET_ROOT}" | tee "${LOG}"
grep -Fq 'goldeneye_ramrom_non_model_visuals_v6_smoke: PASS' "${LOG}"

CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${SWIFTC}" \
    -swift-version 6 -warnings-as-errors -O -sanitize=address -parse-as-library \
    "${SWIFT_PLATFORM[@]}" "${SOURCES[@]}" \
    -o "${BUILD_ROOT}/goldeneye_ramrom_non_model_visuals_v6_smoke_asan"
ASAN_OPTIONS=halt_on_error=1 \
    "${BUILD_ROOT}/goldeneye_ramrom_non_model_visuals_v6_smoke_asan" "${ASSET_ROOT}" \
    | tee "${BUILD_ROOT}/ramrom-non-model-visuals-v6-asan.log"
grep -Fq 'goldeneye_ramrom_non_model_visuals_v6_smoke: PASS' "${BUILD_ROOT}/ramrom-non-model-visuals-v6-asan.log"

CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${SWIFTC}" \
    -swift-version 6 -warnings-as-errors -O -sanitize=undefined -parse-as-library \
    "${SWIFT_PLATFORM[@]}" "${SOURCES[@]}" \
    -o "${BUILD_ROOT}/goldeneye_ramrom_non_model_visuals_v6_smoke_ubsan"
UBSAN_OPTIONS=halt_on_error=1 \
    "${BUILD_ROOT}/goldeneye_ramrom_non_model_visuals_v6_smoke_ubsan" "${ASSET_ROOT}" \
    | tee "${BUILD_ROOT}/ramrom-non-model-visuals-v6-ubsan.log"
grep -Fq 'goldeneye_ramrom_non_model_visuals_v6_smoke: PASS' "${BUILD_ROOT}/ramrom-non-model-visuals-v6-ubsan.log"

echo "RAMROM non-model visual V6 strict/ASan/UBSan validation: PASS"
echo "Artifact: ${LOG}"
