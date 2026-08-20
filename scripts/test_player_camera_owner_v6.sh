#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_ROOT="${ROOT}/build/native/player-camera-owner-v6"
MODULE_CACHE="${BUILD_ROOT}/module-cache"
RECORDING_PATH="${GOLDENEYE_RAMROM_DAM1:-${ROOT}/build/native/boot-assets/ramrom/ramrom_Dam_1.bin}"
if [[ ! -f "${RECORDING_PATH}" ]]; then
    RECORDING_PATH=""
fi
mkdir -p "${BUILD_ROOT}" "${MODULE_CACHE}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun --sdk macosx --find clang)
CFLAGS=(-target arm64-apple-macosx27.0 -isysroot "${SDKROOT}" -std=c11
    -Wall -Wextra -Werror -pedantic -O2 -I "${ROOT}/native/include"
    -I "${ROOT}/native/source_port/gameplay_v6")

build_and_run() {
    local label="$1"
    local sanitizer="$2"
    local suffix="${label}"
    local sanitizer_flag=""
    if [[ -n "${sanitizer}" ]]; then
        sanitizer_flag="-fsanitize=${sanitizer}"
    fi

    local prefix="${BUILD_ROOT}/ge_player_camera_owner_v6_${suffix}"
    "${CC}" "${CFLAGS[@]}" ${sanitizer_flag} -c \
        "${ROOT}/native/src/ge_ramrom_v5.c" -o "${prefix}_ramrom.o"
    "${CC}" "${CFLAGS[@]}" ${sanitizer_flag} -c \
        "${ROOT}/native/src/ge_source_scene_v6.c" -o "${prefix}_source_scene.o"
    "${CC}" "${CFLAGS[@]}" ${sanitizer_flag} -c \
        "${ROOT}/native/source_port/gameplay_v6/ge_guard_door_owner_v6.c" \
        -o "${prefix}_guard_door.o"
    "${CC}" "${CFLAGS[@]}" ${sanitizer_flag} -c \
        "${ROOT}/native/source_port/gameplay_v6/ge_weapon_effect_owner_v6.c" \
        -o "${prefix}_weapon_effect.o"
    "${CC}" "${CFLAGS[@]}" ${sanitizer_flag} -c \
        "${ROOT}/native/source_port/gameplay_v6/ge_ramrom_gameplay_v6.c" \
        -o "${prefix}_gameplay.o"
    "${CC}" "${CFLAGS[@]}" ${sanitizer_flag} -c \
        "${ROOT}/native/source_port/gameplay_v6/ge_player_camera_owner_v6.c" \
        -o "${prefix}_owner.o"
    "${CC}" "${CFLAGS[@]}" ${sanitizer_flag} \
        "${ROOT}/native/tests/ge_player_camera_owner_v6_smoke.c" \
        "${prefix}_ramrom.o" "${prefix}_source_scene.o" "${prefix}_guard_door.o" \
        "${prefix}_weapon_effect.o" "${prefix}_gameplay.o" "${prefix}_owner.o" \
        ${sanitizer_flag} -o "${prefix}"

    if [[ "${label}" == "asan" ]]; then
        if [[ -n "${RECORDING_PATH}" ]]; then
            ASAN_OPTIONS=halt_on_error=1:detect_leaks=0 "${prefix}" "${RECORDING_PATH}" \
                | tee "${prefix}.log"
        else
            ASAN_OPTIONS=halt_on_error=1:detect_leaks=0 "${prefix}" \
            | tee "${prefix}.log"
        fi
    elif [[ "${label}" == "ubsan" ]]; then
        if [[ -n "${RECORDING_PATH}" ]]; then
            UBSAN_OPTIONS=halt_on_error=1 "${prefix}" "${RECORDING_PATH}" \
                | tee "${prefix}.log"
        else
            UBSAN_OPTIONS=halt_on_error=1 "${prefix}" \
                | tee "${prefix}.log"
        fi
    else
        if [[ -n "${RECORDING_PATH}" ]]; then
            "${prefix}" "${RECORDING_PATH}" | tee "${prefix}.log"
        else
            "${prefix}" | tee "${prefix}.log"
        fi
    fi
    grep -Fq 'ge_player_camera_owner_v6_smoke: PASS source=Dam1' "${prefix}.log"
}

echo "Building directly compiled source player/camera owner V6 smoke"
build_and_run strict ""
build_and_run asan address
build_and_run ubsan undefined

if rg -n 'ge_player_camera_source_setup|g_CurrentPlayer|nextDrawable|MIPS|libultra|Gfx' \
    "${ROOT}/native/source_port/gameplay_v6/ge_player_camera_owner_v6.c"; then
    echo "player/camera owner contains a forbidden runtime/source pointer seam" >&2
    exit 1
fi

git -C "${ROOT}" diff --check
echo "Native source player/camera owner V6 validation: PASS"
