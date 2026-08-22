#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${1:-${GOLDENEYE_NATIVE_STAGE_ASSET_ROOT:-${PROJECT_ROOT}/build/native/stage-assets-image-decoder-v6}}"
BUILD_DIR="${PROJECT_ROOT}/build/native/stage-environment-metal-reference-capture-v6"
MODULE_CACHE_DIR="${BUILD_DIR}/module-cache"
CAPTURE_OUTPUT_DIR="${GOLDENEYE_STAGE_CAPTURE_OUTPUT:-${BUILD_DIR}/captures-ztranslated}"
mkdir -p "${BUILD_DIR}" "${MODULE_CACHE_DIR}" "${CAPTURE_OUTPUT_DIR}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
CC=$(xcrun --sdk macosx --find clang)
METAL=$(xcrun --sdk macosx --find metal)
METALLIB=$(dirname "${METAL}")/metallib

CFLAGS=(
    -target arm64-apple-macosx27.0 -isysroot "${SDKROOT}"
    -std=c11 -Wall -Wextra -Werror -pedantic -O2
    -I "${PROJECT_ROOT}/native/include"
)
OBJECTS=()
for source in \
    "${PROJECT_ROOT}/native/src/ge_stage_v5.c" \
    "${PROJECT_ROOT}/native/src/ge_stage_background_v5.c" \
    "${PROJECT_ROOT}/native/src/ge_ramrom_v5.c" \
    "${PROJECT_ROOT}/native/src/ge_ramrom_playback_v5.c" \
    "${PROJECT_ROOT}/native/src/ge_native_runtime_v5.c" \
    "${PROJECT_ROOT}/native/src/ge_audio_v5.c" \
    "${PROJECT_ROOT}/native/src/ge_source_scene_v6.c"; do
    object="${BUILD_DIR}/$(basename "${source}" .c).o"
    "${CC}" "${CFLAGS[@]}" -c "${source}" -o "${object}"
    OBJECTS+=("${object}")
done

if [[ ! -s "${BUILD_DIR}/GoldenEyeSourceSceneV6.metallib" \
      || "${PROJECT_ROOT}/native/shaders/GoldenEyeSourceSceneV6.metal" -nt "${BUILD_DIR}/GoldenEyeSourceSceneV6.metallib" ]]; then
    "${METAL}" -mmacosx-version-min=27.0 \
        -fmodules-cache-path="${MODULE_CACHE_DIR}" \
        -c "${PROJECT_ROOT}/native/shaders/GoldenEyeSourceSceneV6.metal" \
        -o "${BUILD_DIR}/GoldenEyeSourceSceneV6.air"
    "${METALLIB}" "${BUILD_DIR}/GoldenEyeSourceSceneV6.air" \
        -o "${BUILD_DIR}/GoldenEyeSourceSceneV6.metallib"
fi

SWIFT_FLAGS=(
    -swift-version 6 -warnings-as-errors -O -parse-as-library
    -target arm64-apple-macosx27.0 -sdk "${SDKROOT}"
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_native_bridging.h"
    -Xcc -I -Xcc "${PROJECT_ROOT}/native/include"
    -Xcc -include -Xcc "${PROJECT_ROOT}/native/include/ge_source_scene_v6.h"
    -framework Metal -framework QuartzCore -framework CoreGraphics -framework ImageIO
)
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${SWIFTC}" "${SWIFT_FLAGS[@]}" \
    "${PROJECT_ROOT}/native/host/goldeneye_projection_v10.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_attract_route.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_cast_title_hash.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_ramrom_playback_service.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_asset_catalog.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_payload_store_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_transfer_queue_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_setup_packet.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_scene_packet.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_background_draw_packet.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_material_lowering_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_texture_catalog_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_fog_lowering_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_source_scene_adapter_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_environment_camera_adapter_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_catalog_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_fidelity_policy.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_model_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_store_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_texture_binding_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_lighting_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_snapshot_v6.swift" \
    "${PROJECT_ROOT}/native/host/metal_device_state.swift" \
    "${PROJECT_ROOT}/native/host/metal_source_scene_pipeline_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_batching_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_reference_capture_codec_v6.swift" \
    "${PROJECT_ROOT}/native/host/metal_source_scene_renderer_v6.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_stage_environment_metal_reference_capture_v6_smoke.swift" \
    "${OBJECTS[@]}" \
    -o "${BUILD_DIR}/smoke"

STAGES=(33 34 35 9 20 26 25)
: > "${BUILD_DIR}/strict.log"
for stage_id in "${STAGES[@]}"; do
    MTL_DEBUG_LAYER=1 MTL_SHADER_VALIDATION=1 MTL_SHADER_VALIDATION_REPORT_TO_STDERR=1 \
        "${BUILD_DIR}/smoke" "${ASSET_ROOT}" \
        "${BUILD_DIR}/GoldenEyeSourceSceneV6.metallib" "${CAPTURE_OUTPUT_DIR}" "${stage_id}" \
        | tee -a "${BUILD_DIR}/strict.log"
done
PASS_COUNT=$(rg -c 'goldeneye_stage_environment_metal_reference_capture_v6_smoke: PASS' \
    "${BUILD_DIR}/strict.log" || true)
SKIP_COUNT=$(rg -c 'goldeneye_stage_environment_metal_reference_capture_v6_smoke: SKIP' \
    "${BUILD_DIR}/strict.log" || true)
if [[ "${PASS_COUNT}" -eq 0 && "${SKIP_COUNT}" -eq "${#STAGES[@]}" ]]; then
    echo 'Stage environment Metal 4 compositor-independent capture validation: SKIP (Metal 4 unavailable)'
    exit 0
fi
[[ "${PASS_COUNT}" -eq "${#STAGES[@]}" ]]
echo 'Stage environment Metal 4 compositor-independent capture validation: PASS'
