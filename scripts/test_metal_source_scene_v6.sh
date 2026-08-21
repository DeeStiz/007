#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="${PROJECT_ROOT}/build/native/source-scene-renderer-v6"
mkdir -p "${BUILD_DIR}/module-cache"
export CLANG_MODULE_CACHE_PATH="${BUILD_DIR}/module-cache"

GE_SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
GE_SWIFTC=$(xcrun --sdk macosx --find swiftc)
GE_METAL=$(xcrun --sdk macosx --find metal)
GE_METALLIB=$(dirname -- "${GE_METAL}")/metallib

SWIFT_FLAGS=(
    -swift-version 6
    -warnings-as-errors
    -O
    -parse-as-library
    -target arm64-apple-macosx27.0
    -sdk "${GE_SDKROOT}"
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_native_bridging.h"
    -Xcc -I -Xcc "${PROJECT_ROOT}/native/include"
    -Xcc -include -Xcc "${PROJECT_ROOT}/native/include/ge_source_scene_v6.h"
    -framework Metal
    -framework QuartzCore
    -framework CoreGraphics
    -framework ImageIO
)

SWIFT_SOURCES=(
    "${PROJECT_ROOT}/native/host/goldeneye_fidelity_policy.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_catalog_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_source_model_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_store_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_source_lighting_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_stage_fog_lowering_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_snapshot_v6.swift"
    "${PROJECT_ROOT}/native/host/metal_source_scene_pipeline_v6.swift"
    "${PROJECT_ROOT}/native/host/metal_device_state.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_reference_capture_codec_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_texture_binding_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_batching_v6.swift"
    "${PROJECT_ROOT}/native/host/metal_source_scene_renderer_v6.swift"
    "${PROJECT_ROOT}/native/tests/goldeneye_source_scene_renderer_v6_smoke.swift"
)

echo "Building strict V6 source-scene snapshot/pipeline smoke"
"${GE_SWIFTC}" "${SWIFT_FLAGS[@]}" "${SWIFT_SOURCES[@]}" \
    -o "${BUILD_DIR}/goldeneye_source_scene_renderer_v6_smoke"
"${BUILD_DIR}/goldeneye_source_scene_renderer_v6_smoke" \
    | tee "${BUILD_DIR}/strict.log"
grep -Fq 'goldeneye_source_scene_renderer_v6_smoke: PASS' "${BUILD_DIR}/strict.log"

echo "Building ASan V6 source-scene snapshot/pipeline smoke"
"${GE_SWIFTC}" "${SWIFT_FLAGS[@]}" -sanitize=address -o \
    "${BUILD_DIR}/goldeneye_source_scene_renderer_v6_smoke_asan" \
    "${SWIFT_SOURCES[@]}"
ASAN_OPTIONS=halt_on_error=1 \
    "${BUILD_DIR}/goldeneye_source_scene_renderer_v6_smoke_asan" \
    | tee "${BUILD_DIR}/asan.log"
grep -Fq 'goldeneye_source_scene_renderer_v6_smoke: PASS' "${BUILD_DIR}/asan.log"

echo "Compiling direct Metal 4 V6 source-scene shader"
"${GE_METAL}" -mmacosx-version-min=27.0 \
    -fmodules-cache-path="${BUILD_DIR}/module-cache" \
    -c "${PROJECT_ROOT}/native/shaders/GoldenEyeSourceSceneV6.metal" \
    -o "${BUILD_DIR}/GoldenEyeSourceSceneV6.air"
"${GE_METALLIB}" "${BUILD_DIR}/GoldenEyeSourceSceneV6.air" \
    -o "${BUILD_DIR}/GoldenEyeSourceSceneV6.metallib"
test -s "${BUILD_DIR}/GoldenEyeSourceSceneV6.metallib"
rg -q 'min\(1\.0f, maxLOD\)' \
    "${PROJECT_ROOT}/native/shaders/GoldenEyeSourceSceneV6.metal"

echo 'Metal source-scene V6 validation: PASS (strict, ASan, Metal 4 metallib)'
