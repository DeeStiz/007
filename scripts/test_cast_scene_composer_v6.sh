#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${1:-${GOLDENEYE_NATIVE_CAST_ASSET_ROOT:-${ROOT}/build/native/cast-frontend-v6}}"
BUILD_ROOT="${ROOT}/build/native/cast-scene-composer-v6"
MODULE_CACHE="${BUILD_ROOT}/module-cache"
mkdir -p "${BUILD_ROOT}" "${MODULE_CACHE}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
CC=$(xcrun --sdk macosx --find clang)
CFLAGS=(
    -target arm64-apple-macosx27.0 -isysroot "${SDKROOT}"
    -std=c11 -Wall -Wextra -Werror -pedantic
    -I "${ROOT}/native/include" -I "${ROOT}/native/source_port"
)
for source in ge_source_scene_v6.c ge_source_gbi_v6.c ge_source_texture_coordinates_v6.c \
    ge_stage_v5.c ge_stage_background_v5.c ge_ramrom_v5.c \
    ge_ramrom_playback_v5.c ge_native_runtime_v5.c ge_audio_v5.c; do
    "${CC}" "${CFLAGS[@]}" -O2 -c "${ROOT}/native/src/${source}" \
        -o "${BUILD_ROOT}/${source%.c}.o"
done

CLANG_MODULE_CACHE_PATH="${MODULE_CACHE}" "${SWIFTC}" \
    -swift-version 6 -warnings-as-errors -O \
    -target arm64-apple-macosx27.0 -sdk "${SDKROOT}" \
    -import-objc-header "${ROOT}/native/tests/goldeneye_native_bridging.h" \
    -Xcc "-I${ROOT}/native/include" -Xcc "-I${ROOT}/native/source_port" \
    -Xcc -include -Xcc "${ROOT}/native/include/ge_source_scene_v6.h" \
    -Xcc -include -Xcc "${ROOT}/native/include/ge_source_gbi_v6.h" \
    -Xcc -include -Xcc "${ROOT}/native/include/ge_source_texture_coordinates_v6.h" \
    "${ROOT}/native/host/title_geometry_packet.swift" \
    "${ROOT}/native/host/goldeneye_source_model_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_product_contract_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_projection_binding_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_scene_snapshot_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_texture_coordinates_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_scene_composer_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_frontend_catalog_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_texture_setup_v6.swift" \
    "${ROOT}/native/host/goldeneye_gbi_scene_builder_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_node_transform_v6.swift" \
    "${ROOT}/native/host/goldeneye_attract_route.swift" \
    "${ROOT}/native/host/goldeneye_ramrom_playback_service.swift" \
    "${ROOT}/native/host/goldeneye_stage_asset_catalog.swift" \
    "${ROOT}/native/host/goldeneye_stage_setup_packet.swift" \
    "${ROOT}/native/host/goldeneye_stage_scene_packet.swift" \
    "${ROOT}/native/host/goldeneye_projection_v10.swift" \
    "${ROOT}/native/host/goldeneye_stage_background_draw_packet.swift" \
    "${ROOT}/native/host/goldeneye_stage_material_lowering_v6.swift" \
    "${ROOT}/native/host/goldeneye_cast_ramrom_scene_v6.swift" \
    "${ROOT}/native/host/goldeneye_cast_title_hash.swift" \
    "${ROOT}/native/host/goldeneye_cast_skeleton_transform_v6.swift" \
    "${ROOT}/native/host/goldeneye_cast_scene_composer_v6.swift" \
    "${ROOT}/native/tests/goldeneye_cast_scene_composer_v6_smoke.swift" \
    "${BUILD_ROOT}"/*.o \
    -o "${BUILD_ROOT}/goldeneye_cast_scene_composer_v6_smoke"

"${BUILD_ROOT}/goldeneye_cast_scene_composer_v6_smoke" "${ASSET_ROOT}" \
    | tee "${BUILD_ROOT}/cast-scene-composer-v6.log"
grep -Fq 'goldeneye_cast_scene_composer_v6_smoke: PASS identities=30 animations=22 preparedModelCombinations=30 missingClosed=0 castTextFade=PASS' \
    "${BUILD_ROOT}/cast-scene-composer-v6.log"
echo 'test_cast_scene_composer_v6: PASS'
