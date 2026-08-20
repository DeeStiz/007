#!/bin/bash
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${1:-${GOLDENEYE_NATIVE_ASSET_ROOT:-${PROJECT_ROOT}/build/native/boot-assets}}"
BUILD_DIR="${PROJECT_ROOT}/build/native/title-sfx"
mkdir -p "${BUILD_DIR}"
CC=$(xcrun --sdk macosx --find clang)
SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CFLAGS=(-target arm64-apple-macosx27.0 -isysroot "${SDKROOT}" -std=c11 -Wall -Wextra -Werror -pedantic -O2 -I "${PROJECT_ROOT}/native/include")
"${CC}" "${CFLAGS[@]}" \
    "${PROJECT_ROOT}/native/src/ge_audio_engine_v5.c" \
    "${PROJECT_ROOT}/native/src/ge_audio_v5.c" \
    "${PROJECT_ROOT}/native/tests/goldeneye_title_sfx_smoke.c" \
    -o "${BUILD_DIR}/goldeneye_title_sfx_smoke"
"${BUILD_DIR}/goldeneye_title_sfx_smoke" "${ASSET_ROOT}/audio" | tee "${BUILD_DIR}/title-sfx.log"
grep -Fq 'goldeneye_title_sfx_smoke: PASS count=5' "${BUILD_DIR}/title-sfx.log"
echo 'Title SFX validation: PASS'
