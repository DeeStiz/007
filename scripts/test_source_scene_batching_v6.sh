#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="${PROJECT_ROOT}/build/native/source-scene-batching-v6"
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
)

SWIFT_SOURCES=(
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_batching_v6.swift"
    "${PROJECT_ROOT}/native/tests/goldeneye_source_scene_batching_v6_smoke.swift"
)

echo "Building strict V6 source-scene batching smoke"
"${GE_SWIFTC}" "${SWIFT_FLAGS[@]}" "${SWIFT_SOURCES[@]}" \
    -o "${BUILD_DIR}/goldeneye_source_scene_batching_v6_smoke"
"${BUILD_DIR}/goldeneye_source_scene_batching_v6_smoke" | tee "${BUILD_DIR}/strict.log"
grep -Fq 'goldeneye_source_scene_batching_v6_smoke: PASS' "${BUILD_DIR}/strict.log"

echo "Building ASan V6 source-scene batching smoke"
"${GE_SWIFTC}" "${SWIFT_FLAGS[@]}" -sanitize=address -o \
    "${BUILD_DIR}/goldeneye_source_scene_batching_v6_smoke_asan" \
    "${SWIFT_SOURCES[@]}"
ASAN_OPTIONS=halt_on_error=1 \
    "${BUILD_DIR}/goldeneye_source_scene_batching_v6_smoke_asan" \
    | tee "${BUILD_DIR}/asan.log"
grep -Fq 'goldeneye_source_scene_batching_v6_smoke: PASS' "${BUILD_DIR}/asan.log"

echo 'V6 source-scene batching validation: PASS (strict, ASan)'
