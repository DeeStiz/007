#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="${PROJECT_ROOT}/build/native/title-raster-v5"
mkdir -p "${BUILD_DIR}"

python3 "${SCRIPT_DIR}/audit_title_raster_v5_sources.py" | tee "${BUILD_DIR}/source-audit.log"

if command -v xcrun >/dev/null 2>&1; then
    CC=$(xcrun --sdk macosx --find clang)
    SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
else
    CC=${CC:-clang}
    SDKROOT=""
fi

CFLAGS=(-std=c11 -Wall -Wextra -Werror -pedantic -O2
    -I "${PROJECT_ROOT}/native/include")
SAN_FLAGS=(-fsanitize=address,undefined -fno-omit-frame-pointer -O1 -g)
if [[ -n "${SDKROOT}" ]]; then
    CFLAGS+=(-target arm64-apple-macosx27.0 -isysroot "${SDKROOT}")
fi

"${CC}" "${CFLAGS[@]}" \
    "${PROJECT_ROOT}/native/src/ge_title_raster_v5.c" \
    "${PROJECT_ROOT}/native/tests/goldeneye_title_raster_v5_smoke.c" \
    -o "${BUILD_DIR}/goldeneye_title_raster_v5_smoke"

"${BUILD_DIR}/goldeneye_title_raster_v5_smoke" | tee "${BUILD_DIR}/strict.log"

"${CC}" "${CFLAGS[@]}" "${SAN_FLAGS[@]}" \
    "${PROJECT_ROOT}/native/src/ge_title_raster_v5.c" \
    "${PROJECT_ROOT}/native/tests/goldeneye_title_raster_v5_smoke.c" \
    -o "${BUILD_DIR}/goldeneye_title_raster_v5_sanitized"

ASAN_OPTIONS=halt_on_error=1 \
UBSAN_OPTIONS=halt_on_error=1 \
    "${BUILD_DIR}/goldeneye_title_raster_v5_sanitized" | tee "${BUILD_DIR}/sanitized.log"

git -C "${PROJECT_ROOT}" diff --check
echo "Title raster V5 validation: PASS"
