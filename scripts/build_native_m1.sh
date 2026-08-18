#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
BUILD_DIR="${PROJECT_ROOT}/build/native/m1"
CLANG_MODULE_CACHE="${BUILD_DIR}/clang-module-cache"

mkdir -p "${BUILD_DIR}" "${CLANG_MODULE_CACHE}"

if command -v xcrun >/dev/null 2>&1; then
    CC=$(xcrun --sdk macosx --find clang)
    SWIFTC=$(xcrun --sdk macosx --find swiftc)
    AR=$(xcrun --sdk macosx --find ar)
    SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
else
    CC=${CC:-clang}
    SWIFTC=${SWIFTC:-swiftc}
    AR=${AR:-ar}
    SDKROOT=${SDKROOT:-}
fi

COMMON_CFLAGS=(-target arm64-apple-macosx27.0)
if [ -n "${SDKROOT}" ]; then
    COMMON_CFLAGS+=(-isysroot "${SDKROOT}")
fi
COMMON_CFLAGS+=(
    -std=c11 -Wall -Wextra -Werror -O2 -fno-common
    -I "${PROJECT_ROOT}/native/include"
)

echo "Building native M1 archive in ${BUILD_DIR}"
"${CC}" "${COMMON_CFLAGS[@]}" -c \
    "${PROJECT_ROOT}/native/src/goldeneye_native.c" \
    -o "${BUILD_DIR}/goldeneye_native.o"
"${AR}" rcs "${BUILD_DIR}/libgoldeneye_native.a" "${BUILD_DIR}/goldeneye_native.o"

"${CC}" "${COMMON_CFLAGS[@]}" \
    "${PROJECT_ROOT}/native/tests/goldeneye_native_c_smoke.c" \
    "${BUILD_DIR}/libgoldeneye_native.a" -lpthread \
    -o "${BUILD_DIR}/goldeneye_native_c_smoke"

CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE}" "${SWIFTC}" \
    -sdk "${SDKROOT}" -target arm64-apple-macosx27.0 -O \
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_native_bridging.h" \
    -Xcc -I -Xcc "${PROJECT_ROOT}/native/include" \
    "${PROJECT_ROOT}/native/tests/goldeneye_native_swift_smoke.swift" \
    "${BUILD_DIR}/libgoldeneye_native.a" \
    -o "${BUILD_DIR}/goldeneye_native_swift_smoke"

if nm -gU "${BUILD_DIR}/libgoldeneye_native.a" | grep -E '(_main|MIPS|N64|osInitialize|osCreateThread|Gfx)' >/dev/null; then
    echo "native archive contains a forbidden process/N64 symbol" >&2
    exit 1
fi

echo "native M1 archive: ${BUILD_DIR}/libgoldeneye_native.a"
echo "native M1 smoke binaries: ${BUILD_DIR}/goldeneye_native_{c,swift}_smoke"
