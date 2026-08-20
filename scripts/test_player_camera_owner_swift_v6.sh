#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
STAGE_ROOT="${1:-${GOLDENEYE_NATIVE_STAGE_ASSET_ROOT:-${ROOT}/build/native/stage-assets-image-decoder-v6}}"
BOOT_ROOT="${2:-${GOLDENEYE_NATIVE_ASSET_ROOT:-${ROOT}/build/native/boot-assets}}"
VISIBLE_ROOT="${3:-${GOLDENEYE_NATIVE_RAMROM_VISIBLE_ROOT:-${ROOT}/build/native/ramrom-visible-dependencies-v6}}"
BUILD_ROOT="${ROOT}/build/native/player-camera-owner-swift-v6"
MODULE_CACHE="${BUILD_ROOT}/module-cache"
mkdir -p "${BUILD_ROOT}" "${MODULE_CACHE}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun --sdk macosx --find clang)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
CFLAGS=(-target arm64-apple-macosx27.0 -isysroot "${SDKROOT}" -std=c11
    -Wall -Wextra -Werror -pedantic -O2 -I "${ROOT}/native/include"
    -I "${ROOT}/native/source_port/gameplay_v6")
SWIFT_ARGS=(-swift-version 6 -warnings-as-errors -target arm64-apple-macosx27.0 -sdk "${SDKROOT}")

build_and_run() {
    local label="$1"
    local sanitizer="$2"
    local suffix="${label}"
    local c_sanitizer_flag=""
    local swift_sanitizer_flag=""
    if [[ -n "${sanitizer}" ]]; then
        c_sanitizer_flag="-fsanitize=${sanitizer}"
        swift_sanitizer_flag="-sanitize=${sanitizer}"
    fi
    local object_root="${BUILD_ROOT}/${suffix}"
    local objects=()
    for source in ge_ramrom_v5.c ge_stage_v5.c ge_stage_background_v5.c; do
        local object="${object_root}-${source%.c}.o"
        "${CC}" "${CFLAGS[@]}" ${c_sanitizer_flag} -c "${ROOT}/native/src/${source}" -o "${object}"
        objects+=("${object}")
    done
    local source_scene_object="${object_root}-source-scene.o"
    "${CC}" "${CFLAGS[@]}" ${c_sanitizer_flag} -c \
        "${ROOT}/native/src/ge_source_scene_v6.c" -o "${source_scene_object}"
    objects+=("${source_scene_object}")
    local gameplay_object="${object_root}-gameplay.o"
    "${CC}" "${CFLAGS[@]}" ${c_sanitizer_flag} -c \
        "${ROOT}/native/source_port/gameplay_v6/ge_ramrom_gameplay_v6.c" \
        -o "${gameplay_object}"
    objects+=("${gameplay_object}")
    local owner_object="${object_root}-owner.o"
    "${CC}" "${CFLAGS[@]}" ${c_sanitizer_flag} -c \
        "${ROOT}/native/source_port/gameplay_v6/ge_player_camera_owner_v6.c" \
        -o "${owner_object}"
    objects+=("${owner_object}")
    local guard_door_object="${object_root}-guard-door.o"
    "${CC}" "${CFLAGS[@]}" ${c_sanitizer_flag} -c \
        "${ROOT}/native/source_port/gameplay_v6/ge_guard_door_owner_v6.c" \
        -o "${guard_door_object}"
    objects+=("${guard_door_object}")
    local weapon_effect_object="${object_root}-weapon-effect.o"
    "${CC}" "${CFLAGS[@]}" ${c_sanitizer_flag} -c \
        "${ROOT}/native/source_port/gameplay_v6/ge_weapon_effect_owner_v6.c" \
        -o "${weapon_effect_object}"
    objects+=("${weapon_effect_object}")

    local binary="${BUILD_ROOT}/goldeneye_player_camera_owner_v6_${suffix}"
    local sources=(
        "${ROOT}/native/host/goldeneye_stage_asset_catalog.swift"
        "${ROOT}/native/host/goldeneye_stage_setup_packet.swift"
        "${ROOT}/native/host/goldeneye_stage_scene_packet.swift"
        "${ROOT}/native/host/goldeneye_source_model_v6.swift"
        "${ROOT}/native/host/goldeneye_stage_model_sidecar_catalog_v6.swift"
        "${ROOT}/native/host/goldeneye_stage_setup_dependency_catalog_v6.swift"
        "${ROOT}/native/host/goldeneye_ramrom_visible_dependency_catalog_v6.swift"
        "${ROOT}/native/host/goldeneye_ramrom_gameplay_v6.swift"
        "${ROOT}/native/host/goldeneye_ramrom_non_model_visuals_v6.swift"
        "${ROOT}/native/host/goldeneye_ramrom_non_model_authority_v6.swift"
        "${ROOT}/native/host/goldeneye_player_camera_owner_v6.swift"
        "${ROOT}/native/tests/goldeneye_player_camera_owner_v6_smoke.swift"
    )
    CLANG_MODULE_CACHE_PATH="${MODULE_CACHE}" "${SWIFTC}" "${SWIFT_ARGS[@]}" \
        ${swift_sanitizer_flag} -import-objc-header \
        "${ROOT}/native/tests/goldeneye_player_camera_owner_v6_bridging.h" \
        -Xcc "-I${ROOT}/native/include" \
        -Xcc "-I${ROOT}/native/source_port/gameplay_v6" \
        "${sources[@]}" "${objects[@]}" -o "${binary}"

    local log="${binary}.log"
    if [[ "${label}" == "asan" ]]; then
        ASAN_OPTIONS=halt_on_error=1:detect_leaks=0 "${binary}" \
            "${STAGE_ROOT}" "${BOOT_ROOT}" "${VISIBLE_ROOT}" | tee "${log}"
    elif [[ "${label}" == "ubsan" ]]; then
        UBSAN_OPTIONS=halt_on_error=1 "${binary}" \
            "${STAGE_ROOT}" "${BOOT_ROOT}" "${VISIBLE_ROOT}" | tee "${log}"
    else
        "${binary}" "${STAGE_ROOT}" "${BOOT_ROOT}" "${VISIBLE_ROOT}" | tee "${log}"
    fi
    grep -Fq 'goldeneye_player_camera_owner_v6_smoke: PASS demos=14 runs=28' "${log}"
}

echo "Building Swift source-page/player-camera V6 Dam1/all14 owner smoke"
build_and_run strict ""
build_and_run asan address
build_and_run ubsan undefined
git -C "${ROOT}" diff --check
echo "Swift source-page/player-camera owner V6 validation: PASS"
