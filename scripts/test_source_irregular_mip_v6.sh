#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_ROOT="${PROJECT_ROOT}/build/native/source-irregular-mip-v6"
mkdir -p "${BUILD_ROOT}/module-cache"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
SWIFT_FLAGS=(
    -swift-version 6
    -warnings-as-errors
    -O
    -parse-as-library
    -target arm64-apple-macosx27.0
    -sdk "${SDKROOT}"
)
SOURCES=(
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_catalog_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_source_model_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_store_v6.swift"
    "${PROJECT_ROOT}/native/tests/goldeneye_source_irregular_mip_v6_smoke.swift"
)

CLANG_MODULE_CACHE_PATH="${BUILD_ROOT}/module-cache" "${SWIFTC}" "${SWIFT_FLAGS[@]}" \
    "${SOURCES[@]}" -framework Metal \
    -o "${BUILD_ROOT}/goldeneye_source_irregular_mip_v6_smoke"

"${BUILD_ROOT}/goldeneye_source_irregular_mip_v6_smoke" \
    | tee "${BUILD_ROOT}/strict.log"
grep -Fq 'goldeneye_source_irregular_mip_v6_smoke: PASS dimensions=65,33,17,9,5,3,1' "${BUILD_ROOT}/strict.log"

CLANG_MODULE_CACHE_PATH="${BUILD_ROOT}/module-cache" "${SWIFTC}" "${SWIFT_FLAGS[@]}" \
    -sanitize=address "${SOURCES[@]}" -framework Metal \
    -o "${BUILD_ROOT}/goldeneye_source_irregular_mip_v6_smoke_asan"
ASAN_OPTIONS=halt_on_error=1 \
    "${BUILD_ROOT}/goldeneye_source_irregular_mip_v6_smoke_asan" \
    | tee "${BUILD_ROOT}/asan.log"
grep -Fq 'goldeneye_source_irregular_mip_v6_smoke: PASS dimensions=65,33,17,9,5,3,1' "${BUILD_ROOT}/asan.log"

GE_METAL=$(xcrun --sdk macosx --find metal)
GE_METALLIB=$(xcrun --sdk macosx --find metallib)
"${GE_METAL}" -mmacosx-version-min=27.0 \
    -fmodules-cache-path="${BUILD_ROOT}/module-cache" \
    -I "${PROJECT_ROOT}/native/include" \
    -c "${PROJECT_ROOT}/native/shaders/GoldenEyeSourceSceneV6.metal" \
    -o "${BUILD_ROOT}/GoldenEyeSourceSceneV6.air"
"${GE_METALLIB}" "${BUILD_ROOT}/GoldenEyeSourceSceneV6.air" \
    -o "${BUILD_ROOT}/GoldenEyeSourceSceneV6.metallib"
test -s "${BUILD_ROOT}/GoldenEyeSourceSceneV6.metallib"
rg -q 'textureLevel[0-6]' "${PROJECT_ROOT}/native/shaders/GoldenEyeSourceSceneV6.metal"
rg -q 'texture2d_array<float>' "${PROJECT_ROOT}/native/shaders/GoldenEyeSourceSceneV6.metal"

git -C "${PROJECT_ROOT}" diff --check -- \
    native/host/goldeneye_source_texture_store_v6.swift \
    native/host/goldeneye_source_scene_texture_binding_v6.swift \
    native/host/metal_source_scene_pipeline_v6.swift \
    native/host/goldeneye_source_scene_batching_v6.swift \
    native/host/metal_source_scene_renderer_v6.swift \
    native/shaders/GoldenEyeSourceSceneV6.metal \
    native/tests/goldeneye_source_irregular_mip_v6_smoke.swift \
    scripts/test_source_irregular_mip_v6.sh

echo 'Source irregular mip V6 validation: PASS (strict, ASan, Metal 4 metallib)'
