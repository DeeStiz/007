#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="${PROJECT_ROOT}/build/native/source-scene-pipeline-corpus-v6"
mkdir -p "${BUILD_DIR}/module-cache"

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
    -Xcc "${PROJECT_ROOT}/native/include/ge_source_scene_v6.h")
GE_METAL=$(xcrun --sdk macosx --find metal)
GE_METALLIB=$(dirname -- "${GE_METAL}")/metallib

"${SWIFTC}" "${SWIFT_COMMON[@]}" -O \
    "${PROJECT_ROOT}/native/host/goldeneye_fidelity_policy.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_snapshot_v6.swift" \
    "${PROJECT_ROOT}/native/host/metal_source_scene_pipeline_v6.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_source_scene_pipeline_corpus_v6_smoke.swift" \
    -framework Metal -o "${BUILD_DIR}/goldeneye_source_scene_pipeline_corpus_v6_smoke"
"${BUILD_DIR}/goldeneye_source_scene_pipeline_corpus_v6_smoke" \
    "${PROJECT_ROOT}/build/native/source-frontend-v6" \
    | tee "${BUILD_DIR}/strict.log"
grep -Fq 'goldeneye_source_scene_pipeline_corpus_v6_smoke: PASS' "${BUILD_DIR}/strict.log"

"${SWIFTC}" "${SWIFT_COMMON[@]}" -O -sanitize=address \
    "${PROJECT_ROOT}/native/host/goldeneye_fidelity_policy.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_snapshot_v6.swift" \
    "${PROJECT_ROOT}/native/host/metal_source_scene_pipeline_v6.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_source_scene_pipeline_corpus_v6_smoke.swift" \
    -framework Metal -o "${BUILD_DIR}/goldeneye_source_scene_pipeline_corpus_v6_smoke_asan"
ASAN_OPTIONS=halt_on_error=1 \
    "${BUILD_DIR}/goldeneye_source_scene_pipeline_corpus_v6_smoke_asan" \
    "${PROJECT_ROOT}/build/native/source-frontend-v6" \
    | tee "${BUILD_DIR}/asan.log"
grep -Fq 'goldeneye_source_scene_pipeline_corpus_v6_smoke: PASS' "${BUILD_DIR}/asan.log"

"${GE_METAL}" -Xclang "-fmodules-cache-path=${BUILD_DIR}/module-cache" \
    -mmacosx-version-min=27.0 \
    -c "${PROJECT_ROOT}/native/shaders/GoldenEyeSourceSceneV6.metal" \
    -o "${BUILD_DIR}/GoldenEyeSourceSceneV6.air"
"${GE_METALLIB}" "${BUILD_DIR}/GoldenEyeSourceSceneV6.air" \
    -o "${BUILD_DIR}/GoldenEyeSourceSceneV6.metallib"
test -s "${BUILD_DIR}/GoldenEyeSourceSceneV6.metallib"
echo 'V6 source-scene pipeline corpus validation: PASS'
