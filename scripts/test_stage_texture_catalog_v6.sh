#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${1:-${GOLDENEYE_NATIVE_STAGE_ASSET_ROOT:-${PROJECT_ROOT}/build/native/stage-assets-image-decoder-v6}}"
BUILD_DIR="${PROJECT_ROOT}/build/native/stage-texture-catalog-v6"
MODULE_CACHE_DIR="${BUILD_DIR}/module-cache"
mkdir -p "${BUILD_DIR}" "${MODULE_CACHE_DIR}"

CC=$(xcrun --sdk macosx --find clang)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CFLAGS=(
    -target arm64-apple-macosx27.0 -isysroot "${SDKROOT}"
    -std=c11 -Wall -Wextra -Werror -pedantic -O2
    -I "${PROJECT_ROOT}/native/include"
)
SWIFT_ARGS=(
    -swift-version 6 -warnings-as-errors
    -target arm64-apple-macosx27.0 -sdk "${SDKROOT}"
)

OBJECTS=()
for source in \
    ge_stage_v5.c ge_stage_background_v5.c ge_ramrom_v5.c \
    ge_ramrom_playback_v5.c ge_native_runtime_v5.c ge_audio_v5.c \
    ge_source_scene_v6.c; do
    object="${BUILD_DIR}/${source%.c}.o"
    "${CC}" "${CFLAGS[@]}" -c "${PROJECT_ROOT}/native/src/${source}" -o "${object}"
    OBJECTS+=("${object}")
done

CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${SWIFTC}" \
    "${SWIFT_ARGS[@]}" \
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_native_bridging.h" \
    -Xcc "-I${PROJECT_ROOT}/native/include" \
    "${PROJECT_ROOT}/native/host/goldeneye_attract_route.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_cast_title_hash.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_ramrom_playback_service.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_asset_catalog.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_setup_packet.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_scene_packet.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_projection_v10.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_background_draw_packet.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_material_lowering_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_catalog_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_model_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_store_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_texture_catalog_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_setup_dependency_catalog_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_model_sidecar_catalog_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_model_placement_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_ramrom_visible_dependency_catalog_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_snapshot_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_source_scene_adapter_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_cast_ramrom_scene_v6.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_stage_texture_catalog_v6_smoke.swift" \
    "${OBJECTS[@]}" \
    -o "${BUILD_DIR}/goldeneye_stage_texture_catalog_v6_smoke"

"${BUILD_DIR}/goldeneye_stage_texture_catalog_v6_smoke" "${ASSET_ROOT}" \
    | tee "${BUILD_DIR}/stage-texture-catalog-v6.log"
grep -Fq 'goldeneye_stage_texture_catalog_v6_smoke: PASS textures=436 tluts=248' \
    "${BUILD_DIR}/stage-texture-catalog-v6.log"
echo 'Stage texture catalog V6 validation: PASS'
