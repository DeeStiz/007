#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${1:-${GOLDENEYE_RAMROM_ASSET_ROOT:-${PROJECT_ROOT}/build/native/boot-assets/ramrom}}"
BUILD_DIR="${PROJECT_ROOT}/build/native/ramrom-v5"

mkdir -p "${BUILD_DIR}"

if command -v xcrun >/dev/null 2>&1; then
    RAMROM_CC=$(xcrun --sdk macosx --find clang)
    RAMROM_SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
else
    RAMROM_CC=${RAMROM_CC:-clang}
    RAMROM_SDKROOT=""
fi

COMMON_FLAGS=(
    -std=c11 -Wall -Wextra -Werror -pedantic -O2
    -I "${PROJECT_ROOT}/native/include"
)
if [[ -n "${RAMROM_SDKROOT}" ]]; then
    COMMON_FLAGS+=(
        -target arm64-apple-macosx27.0
        -isysroot "${RAMROM_SDKROOT}"
    )
fi
SOURCES=(
    "${PROJECT_ROOT}/native/src/ge_ramrom_v5.c"
    "${PROJECT_ROOT}/native/src/ge_native_runtime_v5.c"
    "${PROJECT_ROOT}/native/src/ge_audio_v5.c"
    "${PROJECT_ROOT}/native/tests/goldeneye_ramrom_v5_smoke.c"
)
SMOKE="${BUILD_DIR}/goldeneye_ramrom_v5_smoke"
SANITIZED="${BUILD_DIR}/goldeneye_ramrom_v5_smoke_sanitized"

echo "Building strict C RAMROM V5 smoke"
"${RAMROM_CC}" "${COMMON_FLAGS[@]}" "${SOURCES[@]}" -o "${SMOKE}"
echo "Running 14-demo deterministic parser smoke"
"${SMOKE}" "${ASSET_ROOT}"

echo "Building ASan/UBSan RAMROM V5 smoke"
"${RAMROM_CC}" "${COMMON_FLAGS[@]}" -O1 -fno-omit-frame-pointer \
    -fsanitize=address,undefined "${SOURCES[@]}" -o "${SANITIZED}"
echo "Running ASan/UBSan malformed-stream smoke"
ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 \
    "${SANITIZED}" "${ASSET_ROOT}"

echo "RAMROM V5 validation: PASS"
