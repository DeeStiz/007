#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_ROOT="${PROJECT_ROOT}/build/native/source-scene-texture-binding-v6"
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
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_texture_binding_v6.swift"
    "${PROJECT_ROOT}/native/tests/goldeneye_source_scene_texture_binding_v6_smoke.swift"
)

CLANG_MODULE_CACHE_PATH="${BUILD_ROOT}/module-cache" "${SWIFTC}" "${SWIFT_FLAGS[@]}" \
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_native_bridging.h" \
    -Xcc "-I${PROJECT_ROOT}/native/include" \
    "${SOURCES[@]}" \
    -framework Metal \
    -o "${BUILD_ROOT}/goldeneye_source_scene_texture_binding_v6_smoke"

"${BUILD_ROOT}/goldeneye_source_scene_texture_binding_v6_smoke" \
    | tee "${BUILD_ROOT}/strict.log"
grep -Fq 'goldeneye_source_scene_texture_binding_v6_smoke: PASS' \
    "${BUILD_ROOT}/strict.log"

CLANG_MODULE_CACHE_PATH="${BUILD_ROOT}/module-cache" "${SWIFTC}" "${SWIFT_FLAGS[@]}" -sanitize=address \
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_native_bridging.h" \
    -Xcc "-I${PROJECT_ROOT}/native/include" \
    "${SOURCES[@]}" \
    -framework Metal \
    -o "${BUILD_ROOT}/goldeneye_source_scene_texture_binding_v6_smoke_asan"
ASAN_OPTIONS=halt_on_error=1 \
    "${BUILD_ROOT}/goldeneye_source_scene_texture_binding_v6_smoke_asan" \
    | tee "${BUILD_ROOT}/asan.log"
grep -Fq 'goldeneye_source_scene_texture_binding_v6_smoke: PASS' \
    "${BUILD_ROOT}/asan.log"

git -C "${PROJECT_ROOT}" diff --check -- \
    native/host/goldeneye_source_scene_texture_binding_v6.swift \
    native/host/goldeneye_source_texture_store_v6.swift \
    native/tests/goldeneye_source_scene_texture_binding_v6_smoke.swift \
    scripts/test_source_scene_texture_binding_v6.sh

echo 'Source-scene texture binding V6 validation: PASS (strict, ASan)'
