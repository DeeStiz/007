#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${1:-${GOLDENEYE_AUDIO_ASSET_ROOT:-${PROJECT_ROOT}/build/native/boot-assets/audio}}"
BUILD_DIR="${PROJECT_ROOT}/build/native/audio-effects-v6"
mkdir -p "${BUILD_DIR}"

CC="${CC:-clang}"
COMMON_FLAGS=(
    -std=c11 -Wall -Wextra -Werror -pedantic
    -Wconversion -Wsign-conversion -Wshadow
    -I "${PROJECT_ROOT}/native/include"
)
SOURCES=(
    "${PROJECT_ROOT}/native/src/ge_audio_engine_v5.c"
    "${PROJECT_ROOT}/native/src/ge_audio_v5.c"
    "${PROJECT_ROOT}/native/src/ge_audio_effects_v6.c"
    "${PROJECT_ROOT}/native/tests/goldeneye_audio_effects_v6_smoke.c"
)

echo "Building strict native audio effects V6 smoke"
"${CC}" "${COMMON_FLAGS[@]}" -O2 "${SOURCES[@]}" -lm \
    -o "${BUILD_DIR}/audio-effects-v6-smoke"
"${BUILD_DIR}/audio-effects-v6-smoke" "${ASSET_ROOT}"

echo "Building ASan/UBSan native audio effects V6 smoke"
"${CC}" "${COMMON_FLAGS[@]}" -O1 -fno-omit-frame-pointer \
    -fsanitize=address,undefined "${SOURCES[@]}" -lm \
    -o "${BUILD_DIR}/audio-effects-v6-smoke-sanitized"
ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 \
    "${BUILD_DIR}/audio-effects-v6-smoke-sanitized" "${ASSET_ROOT}"

echo "Building Release native audio effects V6 smoke"
"${CC}" "${COMMON_FLAGS[@]}" -O3 -DNDEBUG "${SOURCES[@]}" -lm \
    -o "${BUILD_DIR}/audio-effects-v6-smoke-release"
"${BUILD_DIR}/audio-effects-v6-smoke-release" "${ASSET_ROOT}"

echo "Audio effects V6 validation: PASS"
