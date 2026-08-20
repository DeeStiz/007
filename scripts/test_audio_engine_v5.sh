#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${1:-${GOLDENEYE_AUDIO_ASSET_ROOT:-${PROJECT_ROOT}/build/native/boot-assets/audio}}"
BUILD_DIR="${PROJECT_ROOT}/build/native/audio-engine-v5"
mkdir -p "${BUILD_DIR}"

CC="${CC:-clang}"
COMMON_FLAGS=(
    -std=c11 -Wall -Wextra -Werror -pedantic -O2
    -I "${PROJECT_ROOT}/native/include"
)
SOURCES=(
    "${PROJECT_ROOT}/native/src/ge_audio_engine_v5.c"
    "${PROJECT_ROOT}/native/src/ge_audio_v5.c"
    "${PROJECT_ROOT}/native/tests/goldeneye_audio_engine_v5_smoke.c"
)

echo "Building strict native audio V5 smoke"
"${CC}" "${COMMON_FLAGS[@]}" "${SOURCES[@]}" -lm -o "${BUILD_DIR}/audio-engine-v5-smoke"
echo "Rendering guarded boot tracks and SFX vectors"
"${BUILD_DIR}/audio-engine-v5-smoke" "${ASSET_ROOT}"

echo "Building ASan/UBSan native audio V5 smoke"
"${CC}" "${COMMON_FLAGS[@]}" -O1 -fno-omit-frame-pointer \
    -fsanitize=address,undefined "${SOURCES[@]}" -lm \
    -o "${BUILD_DIR}/audio-engine-v5-smoke-sanitized"
ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 \
    "${BUILD_DIR}/audio-engine-v5-smoke-sanitized" "${ASSET_ROOT}"

echo "Audio engine V5 validation: PASS"
