#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
STAGE_ROOT="${1:-${GOLDENEYE_NATIVE_STAGE_ASSET_ROOT:-${ROOT}/build/native/stage-assets-image-decoder-v6}}"
VISIBLE_ROOT="${2:-${GOLDENEYE_NATIVE_RAMROM_VISIBLE_ROOT:-${ROOT}/build/native/ramrom-visible-dependencies-v6}}"
BUILD_ROOT="${ROOT}/build/native/ramrom-guard-door-pages-v6"
MODULE_CACHE="${BUILD_ROOT}/module-cache"
mkdir -p "${BUILD_ROOT}" "${MODULE_CACHE}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun --sdk macosx --find clang)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
CFLAGS=(-target arm64-apple-macosx27.0 -isysroot "${SDKROOT}" -std=c11 -Wall -Wextra -Werror -pedantic -O2 -I "${ROOT}/native/include")
SWIFT_ARGS=(-swift-version 6 -warnings-as-errors -target arm64-apple-macosx27.0 -sdk "${SDKROOT}")

build_and_run() {
    local label="$1"
    local sanitizer="$2"
    local c_sanitize=()
    local swift_sanitize=()
    if [[ -n "${sanitizer}" ]]; then
        c_sanitize=(-fsanitize="${sanitizer}")
        swift_sanitize=(-sanitize="${sanitizer}")
    fi
    local prefix="${BUILD_ROOT}/${label}"
    local objects=()
    for source in ge_ramrom_v5.c ge_stage_v5.c ge_stage_background_v5.c ge_source_scene_v6.c; do
        local object="${prefix}-$(basename "${source}" .c).o"
        if [[ -n "${sanitizer}" ]]; then
            "${CC}" "${CFLAGS[@]}" "${c_sanitize[@]}" -c "${ROOT}/native/src/${source}" -o "${object}"
        else
            "${CC}" "${CFLAGS[@]}" -c "${ROOT}/native/src/${source}" -o "${object}"
        fi
        objects+=("${object}")
    done
    for source in ge_guard_door_owner_v6.c ge_weapon_effect_owner_v6.c ge_ramrom_gameplay_v6.c; do
        local object="${prefix}-$(basename "${source}" .c).o"
        if [[ -n "${sanitizer}" ]]; then
            "${CC}" "${CFLAGS[@]}" "${c_sanitize[@]}" -c "${ROOT}/native/source_port/gameplay_v6/${source}" -o "${object}"
        else
            "${CC}" "${CFLAGS[@]}" -c "${ROOT}/native/source_port/gameplay_v6/${source}" -o "${object}"
        fi
        objects+=("${object}")
    done
    local binary="${BUILD_ROOT}/goldeneye_ramrom_guard_door_pages_v6_smoke_${label}"
    if [[ -n "${sanitizer}" ]]; then
        CLANG_MODULE_CACHE_PATH="${MODULE_CACHE}" "${SWIFTC}" "${SWIFT_ARGS[@]}" "${swift_sanitize[@]}" \
            -import-objc-header "${ROOT}/native/tests/goldeneye_ramrom_gameplay_v6_bridging.h" \
            -Xcc "-I${ROOT}/native/include" \
            "${ROOT}/native/host/goldeneye_stage_asset_catalog.swift" \
            "${ROOT}/native/host/goldeneye_stage_setup_packet.swift" \
            "${ROOT}/native/host/goldeneye_stage_scene_packet.swift" \
            "${ROOT}/native/host/goldeneye_source_model_v6.swift" \
            "${ROOT}/native/host/goldeneye_stage_model_sidecar_catalog_v6.swift" \
            "${ROOT}/native/host/goldeneye_stage_setup_dependency_catalog_v6.swift" \
            "${ROOT}/native/host/goldeneye_ramrom_visible_dependency_catalog_v6.swift" \
            "${ROOT}/native/host/goldeneye_ramrom_guard_ai_source_v6.swift" \
            "${ROOT}/native/host/goldeneye_ramrom_guard_pose_source_v6.swift" \
            "${ROOT}/native/host/goldeneye_ramrom_guard_door_pages_v6.swift" \
            "${ROOT}/native/tests/goldeneye_ramrom_guard_door_pages_v6_smoke.swift" \
            "${objects[@]}" -o "${binary}"
    else
        CLANG_MODULE_CACHE_PATH="${MODULE_CACHE}" "${SWIFTC}" "${SWIFT_ARGS[@]}" \
        -import-objc-header "${ROOT}/native/tests/goldeneye_ramrom_gameplay_v6_bridging.h" \
        -Xcc "-I${ROOT}/native/include" \
        "${ROOT}/native/host/goldeneye_stage_asset_catalog.swift" \
        "${ROOT}/native/host/goldeneye_stage_setup_packet.swift" \
        "${ROOT}/native/host/goldeneye_stage_scene_packet.swift" \
        "${ROOT}/native/host/goldeneye_source_model_v6.swift" \
        "${ROOT}/native/host/goldeneye_stage_model_sidecar_catalog_v6.swift" \
        "${ROOT}/native/host/goldeneye_stage_setup_dependency_catalog_v6.swift" \
        "${ROOT}/native/host/goldeneye_ramrom_visible_dependency_catalog_v6.swift" \
        "${ROOT}/native/host/goldeneye_ramrom_guard_ai_source_v6.swift" \
        "${ROOT}/native/host/goldeneye_ramrom_guard_pose_source_v6.swift" \
        "${ROOT}/native/host/goldeneye_ramrom_guard_door_pages_v6.swift" \
        "${ROOT}/native/tests/goldeneye_ramrom_guard_door_pages_v6_smoke.swift" \
        "${objects[@]}" -o "${binary}"
    fi
    local log="${binary}.log"
    if [[ "${label}" == "asan" ]]; then
        ASAN_OPTIONS=halt_on_error=1:detect_leaks=0 "${binary}" "${STAGE_ROOT}" "${VISIBLE_ROOT}" | tee "${log}"
    elif [[ "${label}" == "ubsan" ]]; then
        UBSAN_OPTIONS=halt_on_error=1 "${binary}" "${STAGE_ROOT}" "${VISIBLE_ROOT}" | tee "${log}"
    else
        "${binary}" "${STAGE_ROOT}" "${VISIBLE_ROOT}" | tee "${log}"
    fi
    grep -Fq 'goldeneye_ramrom_guard_door_pages_v6_smoke: PASS demos=14 runs=2 stages=7' "${log}"
}

echo 'Building RAMROM guard/door source-page V6 strict/ASan/UBSan smoke'
build_and_run strict ''
build_and_run asan address
build_and_run ubsan undefined
git -C "${ROOT}" diff --check
echo 'RAMROM guard/door source-page V6 validation: PASS'
