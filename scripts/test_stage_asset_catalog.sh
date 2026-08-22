#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${1:-${GOLDENEYE_NATIVE_STAGE_ASSET_ROOT:-${PROJECT_ROOT}/build/native/stage-assets-image-decoder-v6}}"
BUILD_DIR="${PROJECT_ROOT}/build/native/stage-asset-catalog"
MODULE_CACHE_DIR="${BUILD_DIR}/module-cache"
mkdir -p "${BUILD_DIR}" "${MODULE_CACHE_DIR}"

if command -v xcrun >/dev/null 2>&1; then
    STAGE_CC=$(xcrun --sdk macosx --find clang)
    STAGE_SWIFTC=$(xcrun --sdk macosx --find swiftc)
    STAGE_SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
else
    STAGE_CC=${STAGE_CC:-clang}
    STAGE_SWIFTC=${STAGE_SWIFTC:-swiftc}
    STAGE_SDKROOT=""
fi

COMMON_CFLAGS=(
    -std=c11 -Wall -Wextra -Werror -pedantic -O2
    -I "${PROJECT_ROOT}/native/include"
)
SWIFT_ARGS=(-swift-version 6 -warnings-as-errors)
if [[ -n "${STAGE_SDKROOT}" ]]; then
    COMMON_CFLAGS+=(
        -target arm64-apple-macosx27.0
        -isysroot "${STAGE_SDKROOT}"
    )
    SWIFT_ARGS+=(
        -target arm64-apple-macosx27.0
        -sdk "${STAGE_SDKROOT}"
    )
fi

STAGE_OBJECT="${BUILD_DIR}/ge_stage_v5.o"
STAGE_OBJECT_ASAN="${BUILD_DIR}/ge_stage_v5_asan.o"
STAGE_OBJECT_UBSAN="${BUILD_DIR}/ge_stage_v5_ubsan.o"
SMOKE="${BUILD_DIR}/goldeneye_stage_asset_catalog_smoke"
SMOKE_ASAN="${BUILD_DIR}/goldeneye_stage_asset_catalog_smoke_asan"
SMOKE_UBSAN="${BUILD_DIR}/goldeneye_stage_asset_catalog_smoke_ubsan"

echo "Building strict C stage V5 object"
"${STAGE_CC}" "${COMMON_CFLAGS[@]}" \
    -c "${PROJECT_ROOT}/native/src/ge_stage_v5.c" -o "${STAGE_OBJECT}"

echo "Building Swift stage catalog bootstrap smoke"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${STAGE_SWIFTC}" \
    "${SWIFT_ARGS[@]}" \
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_native_bridging.h" \
    -Xcc "-I${PROJECT_ROOT}/native/include" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_asset_catalog.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_stage_asset_catalog_smoke.swift" \
    "${STAGE_OBJECT}" \
    -o "${SMOKE}"

echo "Running prepared 21-resource stage bootstrap"
"${SMOKE}" "${ASSET_ROOT}" | tee "${BUILD_DIR}/stage-asset-catalog.log"
grep -Fq 'goldeneye_stage_asset_catalog_smoke: PASS stages=7 resources=21' \
    "${BUILD_DIR}/stage-asset-catalog.log"
grep -Fq 'STUB(M26)=9 STUB(M27)=9' "${BUILD_DIR}/stage-asset-catalog.log"

echo "Building ASan Swift stage catalog bootstrap smoke"
"${STAGE_CC}" "${COMMON_CFLAGS[@]}" -O1 -fno-omit-frame-pointer \
    -fsanitize=address -c "${PROJECT_ROOT}/native/src/ge_stage_v5.c" \
    -o "${STAGE_OBJECT_ASAN}"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${STAGE_SWIFTC}" \
    "${SWIFT_ARGS[@]}" -sanitize=address \
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_native_bridging.h" \
    -Xcc "-I${PROJECT_ROOT}/native/include" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_asset_catalog.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_stage_asset_catalog_smoke.swift" \
    "${STAGE_OBJECT_ASAN}" \
    -o "${SMOKE_ASAN}"
ASAN_OPTIONS=halt_on_error=1 "${SMOKE_ASAN}" "${ASSET_ROOT}" \
    | tee "${BUILD_DIR}/stage-asset-catalog-asan.log"

echo "Building UBSan Swift stage catalog bootstrap smoke"
"${STAGE_CC}" "${COMMON_CFLAGS[@]}" -O1 -fno-omit-frame-pointer \
    -fsanitize=undefined -c "${PROJECT_ROOT}/native/src/ge_stage_v5.c" \
    -o "${STAGE_OBJECT_UBSAN}"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${STAGE_SWIFTC}" \
    "${SWIFT_ARGS[@]}" -sanitize=undefined \
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_native_bridging.h" \
    -Xcc "-I${PROJECT_ROOT}/native/include" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_asset_catalog.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_stage_asset_catalog_smoke.swift" \
    "${STAGE_OBJECT_UBSAN}" \
    -o "${SMOKE_UBSAN}"
UBSAN_OPTIONS=halt_on_error=1 "${SMOKE_UBSAN}" "${ASSET_ROOT}" \
    | tee "${BUILD_DIR}/stage-asset-catalog-ubsan.log"

echo "Checking malformed-manifest guard"
MALFORMED_ROOT="${BUILD_DIR}/malformed-manifest"
mkdir -p "${MALFORMED_ROOT}/background" "${MALFORMED_ROOT}/stan" "${MALFORMED_ROOT}/setup"
cp -f "${ASSET_ROOT}/stage-assets-manifest.txt" \
    "${MALFORMED_ROOT}/stage-assets-manifest.txt"
sed 's/^manifest_status=PASS$/manifest_status=FAIL/' \
    "${MALFORMED_ROOT}/stage-assets-manifest.txt" \
    > "${MALFORMED_ROOT}/stage-assets-manifest.invalid.txt"
mv -f "${MALFORMED_ROOT}/stage-assets-manifest.invalid.txt" \
    "${MALFORMED_ROOT}/stage-assets-manifest.txt"
"${SMOKE}" "${MALFORMED_ROOT}" --expect-malformed \
    | tee "${BUILD_DIR}/stage-asset-catalog-malformed.log"
grep -Fq 'PASS malformed_manifest_guard' \
    "${BUILD_DIR}/stage-asset-catalog-malformed.log"

echo "Stage asset catalog validation: PASS"
