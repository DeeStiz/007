#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${1:-${GOLDENEYE_AUDIO_ASSET_ROOT:-${PROJECT_ROOT}/build/native/boot-assets/audio}}"
BUILD_DIR="${PROJECT_ROOT}/build/native/audio-long-soak-v5"
mkdir -p "${BUILD_DIR}"

CC="${CC:-clang}"
COMMON_FLAGS=(
    -std=c11 -Wall -Wextra -Werror -pedantic
    -Wconversion -Wsign-conversion -Wshadow -O2
    -I "${PROJECT_ROOT}/native/include"
)
SOURCES=(
    "${PROJECT_ROOT}/native/src/ge_audio_v5.c"
    "${PROJECT_ROOT}/native/src/ge_audio_output_v5.c"
    "${PROJECT_ROOT}/native/src/ge_audio_engine_v5.c"
    "${PROJECT_ROOT}/native/tests/goldeneye_audio_long_soak_v5_smoke.c"
)

echo "Building strict 10-minute-equivalent native audio soak"
"${CC}" "${COMMON_FLAGS[@]}" "${SOURCES[@]}" -lm \
    -o "${BUILD_DIR}/audio-long-soak-v5-smoke"
"${BUILD_DIR}/audio-long-soak-v5-smoke" "${ASSET_ROOT}" | tee "${BUILD_DIR}/audio-long-soak-v5.log"

echo "Building ASan/UBSan 10-minute-equivalent native audio soak"
"${CC}" "${COMMON_FLAGS[@]}" -O1 -fno-omit-frame-pointer \
    -fsanitize=address,undefined "${SOURCES[@]}" -lm \
    -o "${BUILD_DIR}/audio-long-soak-v5-smoke-sanitized"
ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 \
    "${BUILD_DIR}/audio-long-soak-v5-smoke-sanitized" "${ASSET_ROOT}" \
    | tee "${BUILD_DIR}/audio-long-soak-v5-sanitized.log"

grep -Fq 'goldeneye_audio_long_soak_v5_smoke: PASS seconds=600 ticks=72000 frames=13230000' \
    "${BUILD_DIR}/audio-long-soak-v5.log"
grep -Fq 'goldeneye_audio_long_soak_v5_smoke: PASS seconds=600 ticks=72000 frames=13230000' \
    "${BUILD_DIR}/audio-long-soak-v5-sanitized.log"
echo "Audio long-soak V5 validation: PASS"
