#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_ROOT="${ROOT}/build/native/ramrom-gameplay-player-camera-v7"
mkdir -p "${BUILD_ROOT}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun --sdk macosx --find clang)
CFLAGS=(-target arm64-apple-macosx27.0 -isysroot "${SDKROOT}" -std=c11
    -Wall -Wextra -Werror -pedantic -O2 -I "${ROOT}/native/include"
    -I "${ROOT}/native/source_port/gameplay_v6")

build_and_run() {
    local label="$1"
    local sanitizer="$2"
    local prefix="${BUILD_ROOT}/${label}"
    local objects=()
    local c_sanitizer=""
    if [[ -n "${sanitizer}" ]]; then
        c_sanitizer="-fsanitize=${sanitizer}"
    fi
    for source in ge_ramrom_v5.c ge_ramrom_playback_v5.c ge_stage_v5.c \
        ge_stage_background_v5.c ge_source_scene_v6.c; do
        local object="${prefix}-$(basename "${source}" .c).o"
        "${CC}" "${CFLAGS[@]}" ${c_sanitizer} -c \
            "${ROOT}/native/src/${source}" -o "${object}"
        objects+=("${object}")
    done
    for source in ge_guard_door_owner_v6.c ge_weapon_effect_owner_v6.c \
        ge_ramrom_weapon_source_pages_v6.c ge_ramrom_gameplay_v6.c; do
        local object="${prefix}-$(basename "${source}" .c).o"
        "${CC}" "${CFLAGS[@]}" ${c_sanitizer} -c \
            "${ROOT}/native/source_port/gameplay_v6/${source}" -o "${object}"
        objects+=("${object}")
    done
    local binary="${BUILD_ROOT}/ge_ramrom_gameplay_player_camera_v7_${label}"
    "${CC}" "${CFLAGS[@]}" ${c_sanitizer} \
        "${ROOT}/native/tests/ge_ramrom_gameplay_player_camera_v7_smoke.c" \
        "${objects[@]}" -o "${binary}"
    local log="${binary}.log"
    if [[ "${label}" == "asan" ]]; then
        ASAN_OPTIONS=halt_on_error=1:detect_leaks=0 "${binary}" | tee "${log}"
    elif [[ "${label}" == "ubsan" ]]; then
        UBSAN_OPTIONS=halt_on_error=1 "${binary}" | tee "${log}"
    else
        "${binary}" | tee "${log}"
    fi
    grep -Fq 'ge_ramrom_gameplay_player_camera_v7_smoke: PASS layout=176 direct=2 eventHash=1' "${log}"
}

echo "Building RAMROM gameplay/player-camera V7 direct C strict/ASan/UBSan smoke"
build_and_run strict ""
build_and_run asan address
build_and_run ubsan undefined
git -C "${ROOT}" diff --check
echo "RAMROM gameplay/player-camera V7 direct C validation: PASS"
