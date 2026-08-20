#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="${PROJECT_ROOT}/build/native/stage-v5"

mkdir -p "${BUILD_DIR}"
if command -v xcrun >/dev/null 2>&1; then
    STAGE_CC=$(xcrun --sdk macosx --find clang)
    STAGE_SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
else
    STAGE_CC=${STAGE_CC:-clang}
    STAGE_SDKROOT=""
fi

COMMON_FLAGS=(
    -std=c11 -Wall -Wextra -Werror -pedantic -O2
    -I "${PROJECT_ROOT}/native/include"
)
if [[ -n "${STAGE_SDKROOT}" ]]; then
    COMMON_FLAGS+=(
        -target arm64-apple-macosx27.0
        -isysroot "${STAGE_SDKROOT}"
    )
fi

SOURCES=(
    "${PROJECT_ROOT}/native/src/ge_stage_v5.c"
    "${PROJECT_ROOT}/native/tests/goldeneye_stage_v5_smoke.c"
)
SMOKE="${BUILD_DIR}/goldeneye_stage_v5_smoke"
SANITIZED="${BUILD_DIR}/goldeneye_stage_v5_smoke_sanitized"

echo "Building strict C stage V5 smoke"
"${STAGE_CC}" "${COMMON_FLAGS[@]}" "${SOURCES[@]}" -o "${SMOKE}"
"${SMOKE}"

echo "Building ASan/UBSan stage V5 smoke"
"${STAGE_CC}" "${COMMON_FLAGS[@]}" -O1 -fno-omit-frame-pointer \
    -fsanitize=address,undefined "${SOURCES[@]}" -o "${SANITIZED}"
ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 \
    "${SANITIZED}"

echo "Stage V5 validation: PASS"
