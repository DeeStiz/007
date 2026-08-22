#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
STAGE_ROOT="${1:-${GOLDENEYE_NATIVE_STAGE_ASSET_ROOT:-${ROOT}/build/native/stage-assets}}"
BOOT_ROOT="${2:-${GOLDENEYE_NATIVE_ASSET_ROOT:-${ROOT}/build/native/boot-assets}}"
VISIBLE_ROOT="${3:-${GOLDENEYE_NATIVE_RAMROM_VISIBLE_ROOT:-${ROOT}/build/native/ramrom-visible-dependencies-v6}}"
BUILD_ROOT="${ROOT}/build/native/ramrom-gameplay-orchestrator-v6"
MODULE_CACHE="${BUILD_ROOT}/module-cache-player-owner-v2"
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
    local c_sanitizer=""
    local swift_sanitizer=""
    if [[ -n "${sanitizer}" ]]; then
        c_sanitizer="-fsanitize=${sanitizer}"
        swift_sanitizer="-sanitize=${sanitizer}"
    fi
    local prefix="${BUILD_ROOT}/${label}"
    local objects=()
    for source in ge_ramrom_v5.c ge_ramrom_playback_v5.c ge_stage_v5.c ge_stage_background_v5.c ge_source_scene_v6.c; do
        local object="${prefix}-$(basename "${source}" .c).o"
        "${CC}" "${CFLAGS[@]}" ${c_sanitizer} -c "${ROOT}/native/src/${source}" -o "${object}"
        objects+=("${object}")
    done
    for source in ge_guard_door_owner_v6.c ge_weapon_effect_owner_v6.c ge_ramrom_weapon_source_pages_v6.c ge_ramrom_gameplay_v6.c ge_player_camera_owner_v6.c; do
        local object="${prefix}-$(basename "${source}" .c).o"
        "${CC}" "${CFLAGS[@]}" ${c_sanitizer} -c \
            "${ROOT}/native/source_port/gameplay_v6/${source}" -o "${object}"
        objects+=("${object}")
    done
    local binary="${BUILD_ROOT}/goldeneye_ramrom_gameplay_orchestrator_v6_${label}"
    local sources=(
        "${ROOT}/native/host/goldeneye_cast_title_hash.swift"
        "${ROOT}/native/host/goldeneye_attract_route.swift"
        "${ROOT}/native/host/goldeneye_ramrom_playback_service.swift"
        "${ROOT}/native/host/goldeneye_stage_asset_catalog.swift"
        "${ROOT}/native/host/goldeneye_stage_payload_store_v6.swift"
        "${ROOT}/native/host/goldeneye_stage_transfer_queue_v6.swift"
        "${ROOT}/native/host/goldeneye_stage_setup_packet.swift"
        "${ROOT}/native/host/goldeneye_stage_scene_packet.swift"
        "${ROOT}/native/host/goldeneye_source_model_v6.swift"
        "${ROOT}/native/host/goldeneye_stage_model_sidecar_catalog_v6.swift"
        "${ROOT}/native/host/goldeneye_stage_setup_dependency_catalog_v6.swift"
        "${ROOT}/native/host/goldeneye_ramrom_visible_dependency_catalog_v6.swift"
        "${ROOT}/native/host/goldeneye_ramrom_gameplay_v6.swift"
        "${ROOT}/native/host/goldeneye_ramrom_non_model_visuals_v6.swift"
        "${ROOT}/native/host/goldeneye_ramrom_non_model_authority_v6.swift"
        "${ROOT}/native/host/goldeneye_guard_door_owner_v6.swift"
        "${ROOT}/native/host/goldeneye_stage_portal_geometry_v7.swift"
        "${ROOT}/native/host/goldeneye_ramrom_guard_door_pages_v6.swift"
        "${ROOT}/native/host/goldeneye_ramrom_guard_ai_source_v6.swift"
        "${ROOT}/native/host/goldeneye_ramrom_guard_pose_source_v6.swift"
        "${ROOT}/native/host/goldeneye_ramrom_weapon_effect_owner_v6.swift"
        "${ROOT}/native/host/goldeneye_ramrom_weapon_asset_catalog_v6.swift"
        "${ROOT}/native/host/goldeneye_ramrom_source_weapon_mapping_v6.swift"
        "${ROOT}/native/host/goldeneye_ramrom_weapon_source_pages_v6.swift"
        "${ROOT}/native/host/goldeneye_player_camera_owner_v6.swift"
        "${ROOT}/native/host/goldeneye_ramrom_gameplay_orchestrator_v6.swift"
        "${ROOT}/native/tests/goldeneye_ramrom_gameplay_orchestrator_v6_smoke.swift"
    )
    CLANG_MODULE_CACHE_PATH="${MODULE_CACHE}" "${SWIFTC}" "${SWIFT_ARGS[@]}" \
        ${swift_sanitizer} -import-objc-header \
        "${ROOT}/native/tests/goldeneye_player_camera_owner_v6_bridging.h" \
        -Xcc "-I${ROOT}/native/include" \
        -Xcc "-I${ROOT}/native/source_port/gameplay_v6" \
        "${sources[@]}" "${objects[@]}" -o "${binary}"
    local log="${binary}.log"
    if [[ "${label}" == "asan" ]]; then
        ASAN_OPTIONS=halt_on_error=1:detect_leaks=0 \
            GOLDENEYE_NATIVE_ASSET_ROOT="${BOOT_ROOT}" \
            GOLDENEYE_NATIVE_STAGE_ASSET_ROOT="${STAGE_ROOT}" \
            GOLDENEYE_NATIVE_RAMROM_VISIBLE_ROOT="${VISIBLE_ROOT}" \
            "${binary}" "${BOOT_ROOT}" "${VISIBLE_ROOT}" | tee "${log}"
    elif [[ "${label}" == "ubsan" ]]; then
        UBSAN_OPTIONS=halt_on_error=1 \
            GOLDENEYE_NATIVE_ASSET_ROOT="${BOOT_ROOT}" \
            GOLDENEYE_NATIVE_STAGE_ASSET_ROOT="${STAGE_ROOT}" \
            GOLDENEYE_NATIVE_RAMROM_VISIBLE_ROOT="${VISIBLE_ROOT}" \
            "${binary}" "${BOOT_ROOT}" "${VISIBLE_ROOT}" | tee "${log}"
    else
        GOLDENEYE_NATIVE_ASSET_ROOT="${BOOT_ROOT}" \
            GOLDENEYE_NATIVE_STAGE_ASSET_ROOT="${STAGE_ROOT}" \
            GOLDENEYE_NATIVE_RAMROM_VISIBLE_ROOT="${VISIBLE_ROOT}" \
            "${binary}" "${BOOT_ROOT}" "${VISIBLE_ROOT}" | tee "${log}"
    fi
    grep -Fq 'goldeneye_ramrom_gameplay_orchestrator_v6_smoke: PASS demos=14 runs=28' "${log}"
}

echo "Building RAMROM gameplay orchestrator V6 strict/ASan/UBSan smoke"
build_and_run strict ""
build_and_run asan address
build_and_run ubsan undefined
git -C "${ROOT}" diff --check
echo "RAMROM gameplay orchestrator V6 validation: PASS"
