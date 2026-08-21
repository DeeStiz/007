#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${1:-${PROJECT_ROOT}/build/native/source-frontend-v6}"
SCENE_LIB_OVERRIDE="${2:-}"
TWO_D_LIB_OVERRIDE="${3:-}"
RUN_ID="${GE_FILE_MODE_CAPTURE_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
BUILD_ROOT="${PROJECT_ROOT}/build/native/file-mode-metal-reference-capture-v6/${RUN_ID}"
mkdir -p "${BUILD_ROOT}/module-cache"
export CLANG_MODULE_CACHE_PATH="${BUILD_ROOT}/module-cache"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun --sdk macosx --find clang)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
METAL=$(xcrun --sdk macosx --find metal)
METALLIB_TOOL=$(dirname -- "${METAL}")/metallib
CFLAGS=(
    -std=c11 -Wall -Wextra -Werror -Wno-c23-extensions -pedantic
    -target arm64-apple-macosx27.0 -isysroot "${SDKROOT}"
    -I "${PROJECT_ROOT}/native/include" -I "${PROJECT_ROOT}/native/source_port"
)
for source in ge_source_frontend_runtime_v6.c ge_source_scene_v6.c ge_source_gbi_v6.c ge_source_texture_coordinates_v6.c ge_file_mode_v6.c; do
    "${CC}" "${CFLAGS[@]}" -O2 -c "${PROJECT_ROOT}/native/src/${source}" -o "${BUILD_ROOT}/${source%.c}.o"
done
"${CC}" "${CFLAGS[@]}" -O2 -c "${PROJECT_ROOT}/native/source_port/ge_source_frontend_v6.c" -o "${BUILD_ROOT}/ge_source_frontend_v6.o"

SCENE_LIB="${SCENE_LIB_OVERRIDE:-${PROJECT_ROOT}/build/native/source-scene-renderer-v6/GoldenEyeSourceSceneV6.metallib}"
if [[ ! -s "${SCENE_LIB}" ]]; then scripts/test_metal_source_scene_v6.sh >/dev/null; fi
TWO_D_AIR="${BUILD_ROOT}/GoldenEyeSource2DV6.air"
TWO_D_LIB="${TWO_D_LIB_OVERRIDE:-${BUILD_ROOT}/GoldenEyeSource2DV6.metallib}"
"${METAL}" -mmacosx-version-min=27.0 -c "${PROJECT_ROOT}/native/shaders/GoldenEyeSource2DV6.metal" -o "${TWO_D_AIR}"
"${METALLIB_TOOL}" "${TWO_D_AIR}" -o "${TWO_D_LIB}"

SWIFT_FLAGS=(
    -swift-version 6 -warnings-as-errors -O
    -target arm64-apple-macosx27.0 -sdk "${SDKROOT}"
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_native_bridging.h"
    -Xcc "-I${PROJECT_ROOT}/native/include" -Xcc "-I${PROJECT_ROOT}/native/source_port"
    -framework AppKit -framework Metal -framework QuartzCore -framework CoreGraphics -framework ImageIO
)
"${SWIFTC}" "${SWIFT_FLAGS[@]}" \
    "${PROJECT_ROOT}/native/host/goldeneye_fidelity_policy.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_lighting_v6.swift" \
    "${PROJECT_ROOT}/native/host/save_store.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_file_mode_authority_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_authority_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_matrices_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_projection_binding_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_product_contract_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_catalog_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_product_preparation_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_product_provider_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_model_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_snapshot_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_fog_lowering_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_coordinates_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_texture_binding_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_store_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_setup_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_wallet_switch_text_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_gbi_scene_builder_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_composer_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_node_transform_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_2d_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_2d_file_mode_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_file_mode_background_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_2d_pipeline_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_2d_renderer_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_reference_capture_codec_v6.swift" \
    "${PROJECT_ROOT}/native/host/metal_device_state.swift" \
    "${PROJECT_ROOT}/native/host/metal_source_scene_pipeline_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_batching_v6.swift" \
    "${PROJECT_ROOT}/native/host/metal_source_scene_renderer_v6.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_file_mode_metal_reference_capture_v6_smoke.swift" \
    "${BUILD_ROOT}/ge_source_frontend_runtime_v6.o" \
    "${BUILD_ROOT}/ge_source_frontend_v6.o" \
    "${BUILD_ROOT}/ge_source_scene_v6.o" \
    "${BUILD_ROOT}/ge_source_gbi_v6.o" \
    "${BUILD_ROOT}/ge_source_texture_coordinates_v6.o" \
    "${BUILD_ROOT}/ge_file_mode_v6.o" \
    -o "${BUILD_ROOT}/smoke"

MTL_DEBUG_LAYER=1 MTL_SHADER_VALIDATION=1 MTL_SHADER_VALIDATION_REPORT_TO_STDERR=1 \
    "${BUILD_ROOT}/smoke" "${ASSET_ROOT}" "${SCENE_LIB}" "${TWO_D_LIB}" "${BUILD_ROOT}" \
    2>&1 | tee "${BUILD_ROOT}/strict.log"
grep -Fq 'goldeneye_file_mode_metal_reference_capture_v6_smoke: PASS' "${BUILD_ROOT}/strict.log" \
    || grep -Fq 'goldeneye_file_mode_metal_reference_capture_v6_smoke: SKIP' "${BUILD_ROOT}/strict.log"
if grep -Fq 'goldeneye_file_mode_metal_reference_capture_v6_smoke: PASS' "${BUILD_ROOT}/strict.log"; then
    find "${BUILD_ROOT}" -maxdepth 1 -name '*.png' -size +0c -print | grep -q .
    jq -e ' .frontFacing == "counterClockwise" ' "${BUILD_ROOT}/file-fresh-faithful-hd.json" >/dev/null
    jq -e ' .frontFacing == "counterClockwise" ' "${BUILD_ROOT}/mode-solo-previous-faithful-hd.json" >/dev/null
fi
echo "Artifact: ${BUILD_ROOT}/strict.log"
