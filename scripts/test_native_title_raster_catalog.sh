#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="${PROJECT_ROOT}/build/native/title-raster-catalog"
MODULE_CACHE_DIR="${BUILD_DIR}/module-cache"
mkdir -p "${BUILD_DIR}" "${MODULE_CACHE_DIR}"
CC=$(xcrun --sdk macosx --find clang)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CFLAGS=(-target arm64-apple-macosx27.0 -isysroot "${SDKROOT}" -std=c11 -Wall -Wextra -Werror -pedantic -O2 -I "${PROJECT_ROOT}/native/include")
SWIFT_ARGS=(-swift-version 6 -warnings-as-errors -target arm64-apple-macosx27.0 -sdk "${SDKROOT}")
BRIDGING="${PROJECT_ROOT}/native/tests/goldeneye_native_bridging.h"
SOURCES=(
    "${PROJECT_ROOT}/native/host/goldeneye_title_raster_catalog.swift"
    "${PROJECT_ROOT}/native/tests/goldeneye_title_raster_catalog_smoke.swift"
)

"${CC}" "${CFLAGS[@]}" -c "${PROJECT_ROOT}/native/src/ge_title_raster_v5.c" -o "${BUILD_DIR}/ge_title_raster_v5.o"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${SWIFTC}" "${SWIFT_ARGS[@]}" \
    -import-objc-header "${BRIDGING}" -Xcc "-I${PROJECT_ROOT}/native/include" \
    "${SOURCES[@]}" "${BUILD_DIR}/ge_title_raster_v5.o" -o "${BUILD_DIR}/smoke"
"${BUILD_DIR}/smoke" | tee "${BUILD_DIR}/strict.log"

"${CC}" "${CFLAGS[@]}" -O1 -fsanitize=address,undefined -fno-omit-frame-pointer \
    -c "${PROJECT_ROOT}/native/src/ge_title_raster_v5.c" -o "${BUILD_DIR}/ge_title_raster_v5_sanitized.o"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${SWIFTC}" "${SWIFT_ARGS[@]}" \
    -sanitize=address,undefined -import-objc-header "${BRIDGING}" \
    -Xcc "-I${PROJECT_ROOT}/native/include" "${SOURCES[@]}" \
    "${BUILD_DIR}/ge_title_raster_v5_sanitized.o" -o "${BUILD_DIR}/smoke-sanitized"
ASAN_OPTIONS=halt_on_error=1:detect_leaks=0 UBSAN_OPTIONS=halt_on_error=1 \
    "${BUILD_DIR}/smoke-sanitized" | tee "${BUILD_DIR}/sanitized.log"

git -C "${PROJECT_ROOT}" diff --check
echo 'Native title raster catalog validation: PASS'
