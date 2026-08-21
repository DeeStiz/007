#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
STAGE_ROOT="${1:-${GOLDENEYE_NATIVE_STAGE_ASSET_ROOT:-${PROJECT_ROOT}/build/native/stage-assets-image-decoder-v6}}"
VISIBLE_ROOT="${2:-${GOLDENEYE_NATIVE_VISIBLE_DEPENDENCY_ROOT:-${PROJECT_ROOT}/build/native/ramrom-visible-dependencies-v6}}"
BUILD_DIR="${PROJECT_ROOT}/build/native/stage-model-scene-composer-v6"
MODULE_CACHE_DIR="${BUILD_DIR}/module-cache"
mkdir -p "${BUILD_DIR}" "${MODULE_CACHE_DIR}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun --sdk macosx --find clang)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
COMMON_CFLAGS=(-target arm64-apple-macosx27.0 -isysroot "${SDKROOT}" -std=c11
    -Wall -Wextra -Werror -Wno-c23-extensions -pedantic
    -I "${PROJECT_ROOT}/native/include")
SWIFT_COMMON=(-swift-version 6 -warnings-as-errors -target arm64-apple-macosx27.0
    -sdk "${SDKROOT}" -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_native_bridging.h"
    -Xcc "-I${PROJECT_ROOT}/native/include" -Xcc -include
    -Xcc "${PROJECT_ROOT}/native/include/ge_source_gbi_v6.h" -Xcc -include
    -Xcc "${PROJECT_ROOT}/native/include/ge_source_scene_v6.h" -Xcc -include
    -Xcc "${PROJECT_ROOT}/native/include/ge_source_texture_coordinates_v6.h")

OBJECTS=()
for source in ge_source_gbi_v6.c ge_source_scene_v6.c ge_source_frontend_runtime_v6.c ge_source_frontend_v6.c ge_file_mode_v6.c ge_source_texture_coordinates_v6.c ge_stage_v5.c ge_stage_background_v5.c ge_ramrom_v5.c ge_native_runtime_v5.c ge_audio_v5.c ge_ramrom_playback_v5.c; do
    object="${BUILD_DIR}/${source%.c}.o"
    extra=()
    source_path="${PROJECT_ROOT}/native/src/${source}"
    if [[ "${source}" == "ge_source_frontend_v6.c" || "${source}" == "ge_source_frontend_runtime_v6.c" ]]; then
        extra=(-I "${PROJECT_ROOT}/native/source_port")
    fi
    if [[ "${source}" == "ge_source_frontend_v6.c" ]]; then
        source_path="${PROJECT_ROOT}/native/source_port/${source}"
    fi
    "${CC}" "${COMMON_CFLAGS[@]}" "${extra[@]-}" -O2 -c "${source_path}" -o "${object}"
    OBJECTS+=("${object}")
done

CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${SWIFTC}" "${SWIFT_COMMON[@]}" -Onone \
    "${PROJECT_ROOT}/native/host/goldeneye_attract_route.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_cast_title_hash.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_ramrom_playback_service.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_ramrom_visible_dependency_catalog_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_asset_catalog.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_setup_packet.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_scene_packet.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_background_draw_packet.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_material_lowering_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_texture_catalog_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_fog_lowering_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_setup_dependency_catalog_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_model_sidecar_catalog_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_model_placement_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_model_scene_composer_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_projection_v10.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_model_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_catalog_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_authority_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_product_provider_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_product_preparation_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_file_mode_authority_v6.swift" \
    "${PROJECT_ROOT}/native/host/save_store.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_product_contract_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_matrices_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_projection_binding_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_snapshot_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_composer_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_coordinates_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_store_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_setup_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_node_transform_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_gbi_scene_builder_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_source_scene_adapter_v6.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_stage_model_scene_composer_v6_smoke.swift" \
    "${OBJECTS[@]}" -o "${BUILD_DIR}/goldeneye_stage_model_scene_composer_v6_smoke"

LOG_PATH="${BUILD_DIR}/stage-model-scene-composer-v6.log"
: > "${LOG_PATH}"
for stage_id in 33 34 35 9 20 26 25; do
    "${BUILD_DIR}/goldeneye_stage_model_scene_composer_v6_smoke" "${STAGE_ROOT}" "${VISIBLE_ROOT}" "${stage_id}" \
        | tee -a "${LOG_PATH}"
done
grep -Fq 'goldeneye_stage_model_scene_composer_v6_smoke: PASS stage=33' "${LOG_PATH}"
grep -Fq 'goldeneye_stage_model_scene_composer_v6_smoke: PASS stage=25' "${LOG_PATH}"
echo 'Stage model scene composer V6 validation: PASS'
