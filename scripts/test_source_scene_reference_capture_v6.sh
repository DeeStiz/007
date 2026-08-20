#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="${PROJECT_ROOT}/build/native/source-scene-reference-capture-v6"
mkdir -p "${BUILD_DIR}/module-cache"
export CLANG_MODULE_CACHE_PATH="${BUILD_DIR}/module-cache"

GE_SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
GE_SWIFTC=$(xcrun --sdk macosx --find swiftc)

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

"${GE_SWIFTC}" "${SWIFT_FLAGS[@]}" \
    "${PROJECT_ROOT}/native/host/goldeneye_fidelity_policy.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_catalog_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_model_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_store_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_texture_binding_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_lighting_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_snapshot_v6.swift" \
    "${PROJECT_ROOT}/native/host/metal_source_scene_pipeline_v6.swift" \
    "${PROJECT_ROOT}/native/host/metal_device_state.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_reference_capture_codec_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_batching_v6.swift" \
    "${PROJECT_ROOT}/native/host/metal_source_scene_renderer_v6.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_source_scene_reference_capture_v6_smoke.swift" \
    -o "${BUILD_DIR}/smoke"
"${BUILD_DIR}/smoke" | tee "${BUILD_DIR}/strict.log"
grep -Fq 'goldeneye_source_scene_reference_capture_v6_smoke: PASS' "${BUILD_DIR}/strict.log"

rg -q 'targetDescriptor\.storageMode = \.private' \
    "${PROJECT_ROOT}/native/host/metal_source_scene_renderer_v6.swift"
rg -q 'copy\(' "${PROJECT_ROOT}/native/host/metal_source_scene_renderer_v6.swift"
rg -q 'build.*native' "${PROJECT_ROOT}/native/host/metal_source_scene_renderer_v6.swift"
rg -q 'encodePNG' "${PROJECT_ROOT}/native/host/goldeneye_reference_capture_codec_v6.swift"
rg -q 'decodePNG' "${PROJECT_ROOT}/native/host/goldeneye_reference_capture_codec_v6.swift"

echo 'Source-scene compositor-independent Reference 320x240 validation: PASS'
