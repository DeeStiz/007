#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${1:-${GOLDENEYE_NATIVE_SOURCE_FRONTEND_ROOT:-${PROJECT_ROOT}/build/native/source-frontend-v6}}"
BUILD_ROOT="${PROJECT_ROOT}/build/native/source-title-material-contract-v6"

mkdir -p "${BUILD_ROOT}/strict" "${BUILD_ROOT}/asan" "${BUILD_ROOT}/ubsan" "${BUILD_ROOT}/module-cache"
export CLANG_MODULE_CACHE_PATH="${BUILD_ROOT}/module-cache"

if [[ ! -d "${ASSET_ROOT}" ]]; then
    echo "source-title material contract: missing prepared asset root: ${ASSET_ROOT}" >&2
    exit 1
fi

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
SWIFT_FLAGS=(
    -swift-version 6
    -warnings-as-errors
    -target arm64-apple-macosx27.0
    -sdk "${SDKROOT}"
    -framework Metal
)
SOURCES=(
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_catalog_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_source_model_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_store_v6.swift"
    "${PROJECT_ROOT}/native/tests/goldeneye_source_title_material_contract_v6_smoke.swift"
)

echo "Building strict source-title GESM material contract smoke"
"${SWIFTC}" "${SWIFT_FLAGS[@]}" -O -parse-as-library \
    "${SOURCES[@]}" -o "${BUILD_ROOT}/strict/smoke"
"${BUILD_ROOT}/strict/smoke" "${ASSET_ROOT}" \
    | tee "${BUILD_ROOT}/strict.log"
grep -Fq 'goldeneye_source_title_material_contract_v6_smoke: PASS' \
    "${BUILD_ROOT}/strict.log"

echo "Building ASan source-title GESM material contract smoke"
"${SWIFTC}" "${SWIFT_FLAGS[@]}" -Onone -sanitize=address -parse-as-library \
    "${SOURCES[@]}" -o "${BUILD_ROOT}/asan/smoke"
ASAN_OPTIONS=halt_on_error=1 \
    "${BUILD_ROOT}/asan/smoke" "${ASSET_ROOT}" \
    | tee "${BUILD_ROOT}/asan.log"
grep -Fq 'goldeneye_source_title_material_contract_v6_smoke: PASS' \
    "${BUILD_ROOT}/asan.log"

echo "Building UBSan source-title GESM material contract smoke"
"${SWIFTC}" "${SWIFT_FLAGS[@]}" -Onone -sanitize=undefined -parse-as-library \
    "${SOURCES[@]}" -o "${BUILD_ROOT}/ubsan/smoke"
UBSAN_OPTIONS=halt_on_error=1 \
    "${BUILD_ROOT}/ubsan/smoke" "${ASSET_ROOT}" \
    | tee "${BUILD_ROOT}/ubsan.log"
grep -Fq 'goldeneye_source_title_material_contract_v6_smoke: PASS' \
    "${BUILD_ROOT}/ubsan.log"

git -C "${PROJECT_ROOT}" diff --check -- \
    native/tests/goldeneye_source_title_material_contract_v6_smoke.swift \
    scripts/test_source_title_material_contract_v6.sh

echo 'Source-title GESM material contract validation: PASS (strict, ASan, UBSan; GPU TLUT consumption not claimed)'
echo "Artifacts: ${BUILD_ROOT}"
