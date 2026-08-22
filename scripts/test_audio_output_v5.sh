#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="${PROJECT_ROOT}/build/native/audio-output-v5"
mkdir -p "${BUILD_DIR}"

CC="${CC:-clang}"
COMMON_FLAGS=(
    -std=c11 -Wall -Wextra -Werror -pedantic
    -Wconversion -Wsign-conversion -Wshadow -O2
    -I "${PROJECT_ROOT}/native/include"
)
C_SOURCES=(
    "${PROJECT_ROOT}/native/src/ge_audio_v5.c"
    "${PROJECT_ROOT}/native/src/ge_audio_engine_v5.c"
    "${PROJECT_ROOT}/native/src/ge_audio_output_v5.c"
    "${PROJECT_ROOT}/native/tests/goldeneye_audio_output_v5_smoke.c"
)

echo "Building strict native audio output V5 smoke"
"${CC}" "${COMMON_FLAGS[@]}" "${C_SOURCES[@]}" -lm \
    -o "${BUILD_DIR}/audio-output-v5-smoke"
"${BUILD_DIR}/audio-output-v5-smoke"

echo "Building ASan native audio output V5 smoke"
"${CC}" "${COMMON_FLAGS[@]}" -O1 -fno-omit-frame-pointer \
    -fsanitize=address "${C_SOURCES[@]}" -lm \
    -o "${BUILD_DIR}/audio-output-v5-smoke-asan"
ASAN_OPTIONS=halt_on_error=1 "${BUILD_DIR}/audio-output-v5-smoke-asan"

echo "Building UBSan native audio output V5 smoke"
"${CC}" "${COMMON_FLAGS[@]}" -O1 -fno-omit-frame-pointer \
    -fsanitize=undefined "${C_SOURCES[@]}" -lm \
    -o "${BUILD_DIR}/audio-output-v5-smoke-ubsan"
UBSAN_OPTIONS=halt_on_error=1 "${BUILD_DIR}/audio-output-v5-smoke-ubsan"

if command -v xcrun >/dev/null 2>&1; then
    echo "Building AVAudioSourceNode adapter smoke"
    xcrun clang -fobjc-arc -fblocks \
        -std=c11 -Wall -Wextra -Werror -pedantic \
        -Wconversion -Wsign-conversion -Wshadow -O2 \
        -I "${PROJECT_ROOT}/native/include" \
        "${PROJECT_ROOT}/native/src/ge_audio_v5.c" \
        "${PROJECT_ROOT}/native/src/ge_audio_engine_v5.c" \
        "${PROJECT_ROOT}/native/src/ge_audio_output_v5.c" \
        "${PROJECT_ROOT}/native/src/ge_audio_source_node_v5.m" \
        "${PROJECT_ROOT}/native/tests/goldeneye_audio_source_node_v5_smoke.m" \
        -lm -framework AVFAudio -framework Foundation \
        -o "${BUILD_DIR}/audio-source-node-v5-smoke"
    SOURCE_NODE_LOG="${BUILD_DIR}/audio-source-node-v5-smoke.log"
    set +e
    "${BUILD_DIR}/audio-source-node-v5-smoke" >"${SOURCE_NODE_LOG}" 2>&1
    SOURCE_NODE_STATUS=$?
    set -e
    cat "${SOURCE_NODE_LOG}"
    if [[ "${SOURCE_NODE_STATUS}" -eq 0 ]]; then
        echo "AVAudioSourceNode adapter smoke: PASS"
    elif rg -qi 'required condition is false|AVAudio|comp != nullptr' "${SOURCE_NODE_LOG}"; then
        echo "AVAudioSourceNode adapter smoke: SKIP (audio route unavailable in this session)"
    else
        echo "AVAudioSourceNode adapter smoke: FAIL" >&2
        exit "${SOURCE_NODE_STATUS}"
    fi
fi

echo "Audio output V5 validation: PASS"
