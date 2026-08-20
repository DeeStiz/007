#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
BUILD_DIR="${PROJECT_ROOT}/build/native/m1"
SAN_DIR="${BUILD_DIR}/sanitize"

"${SCRIPT_DIR}/build_native_m1.sh"

echo "Running C smoke"
"${BUILD_DIR}/goldeneye_native_c_smoke"
echo "Running Swift smoke"
"${BUILD_DIR}/goldeneye_native_swift_smoke"

mkdir -p "${SAN_DIR}"
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
COMMON_CFLAGS+=(
    -std=c11 -Wall -Wextra -Werror -O1 -fno-omit-frame-pointer
    -I "${PROJECT_ROOT}/native/include"
    -fsanitize=address,undefined
)

echo "Running C smoke with ASan/UBSan"
"${CC}" "${COMMON_CFLAGS[@]}" \
    "${PROJECT_ROOT}/native/src/goldeneye_native.c" \
    "${PROJECT_ROOT}/native/tests/goldeneye_native_c_smoke.c" -lpthread \
    -o "${SAN_DIR}/goldeneye_native_c_smoke_sanitized"
ASAN_OPTIONS=halt_on_error=1 \
    UBSAN_OPTIONS=halt_on_error=1 \
    "${SAN_DIR}/goldeneye_native_c_smoke_sanitized"

echo "Checking source/ABI boundaries"
if sed '/^[[:space:]]*\/\//d' "${PROJECT_ROOT}/native/include/goldeneye_native.h" | \
    rg -n 'uintptr_t|void[[:space:]]*\*|Gfx|OSTask|MIPS|N64'; then
    echo "forbidden raw/N64 type found in the public native ABI" >&2
    exit 1
fi
git -C "${PROJECT_ROOT}" diff --check
echo "native M1 validation: PASS"
