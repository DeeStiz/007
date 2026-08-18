#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
BUILD_DIR="${PROJECT_ROOT}/build/native/m7"
mkdir -p "${BUILD_DIR}"

if command -v xcrun >/dev/null 2>&1; then
    CC=$(xcrun --sdk macosx --find clang)
    SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
else
    CC=${CC:-clang}
    SDKROOT=${SDKROOT:-}
fi

COMMON_CFLAGS=(-target arm64-apple-macosx27.0)
if [ -n "${SDKROOT}" ]; then
    COMMON_CFLAGS+=(-isysroot "${SDKROOT}")
fi
COMMON_CFLAGS+=(-std=c11 -Wall -Wextra -Werror -O2 -I "${PROJECT_ROOT}/native/include")

"${CC}" "${COMMON_CFLAGS[@]}" \
    "${PROJECT_ROOT}/native/src/goldeneye_native.c" \
    "${PROJECT_ROOT}/native/tests/goldeneye_gbi_smoke.c" \
    -o "${BUILD_DIR}/goldeneye_gbi_smoke"
"${BUILD_DIR}/goldeneye_gbi_smoke"

if command -v xcrun >/dev/null 2>&1; then
    SWIFTC=$(xcrun --sdk macosx --find swiftc)
else
    SWIFTC=${SWIFTC:-swiftc}
fi
cp "${PROJECT_ROOT}/native/tests/goldeneye_gbi_swift_smoke.swift" "${BUILD_DIR}/main.swift"
mkdir -p "${BUILD_DIR}/module-cache"
"${CC}" "${COMMON_CFLAGS[@]}" -c \
    "${PROJECT_ROOT}/native/src/goldeneye_native.c" \
    -o "${BUILD_DIR}/goldeneye_native.o"
ar rcs "${BUILD_DIR}/libgoldeneye_native.a" "${BUILD_DIR}/goldeneye_native.o"
SWIFT_ARGS=(-target arm64-apple-macosx27.0)
if [ -n "${SDKROOT}" ]; then
    SWIFT_ARGS+=(-sdk "${SDKROOT}")
fi
CLANG_MODULE_CACHE_PATH="${BUILD_DIR}/module-cache" "${SWIFTC}" \
    "${SWIFT_ARGS[@]}" -O \
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_native_bridging.h" \
    -Xcc "-I${PROJECT_ROOT}/native/include" \
    "${BUILD_DIR}/libgoldeneye_native.a" \
    "${BUILD_DIR}/main.swift" \
    -o "${BUILD_DIR}/goldeneye_gbi_swift_smoke"
"${BUILD_DIR}/goldeneye_gbi_swift_smoke"

SANITIZED="${BUILD_DIR}/goldeneye_gbi_smoke_sanitized"
"${CC}" "${COMMON_CFLAGS[@]}" -O1 -fno-omit-frame-pointer \
    -fsanitize=address,undefined \
    "${PROJECT_ROOT}/native/src/goldeneye_native.c" \
    "${PROJECT_ROOT}/native/tests/goldeneye_gbi_smoke.c" \
    -o "${SANITIZED}"
ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 "${SANITIZED}"
git -C "${PROJECT_ROOT}" diff --check
echo "M7 GBI normalization validation: PASS"
