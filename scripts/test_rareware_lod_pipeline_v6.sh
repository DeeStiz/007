#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="${PROJECT_ROOT}/build/native/rareware-frame-v6"
mkdir -p "${BUILD_DIR}"

GE_SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
GE_SWIFTC=$(xcrun --sdk macosx --find swiftc)

SWIFT_FLAGS=(
    -swift-version 6
    -warnings-as-errors
    -O
    -target arm64-apple-macosx27.0
    -sdk "${GE_SDKROOT}"
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_native_bridging.h"
    -Xcc -I -Xcc "${PROJECT_ROOT}/native/include"
    -Xcc -include -Xcc "${PROJECT_ROOT}/native/include/ge_source_scene_v6.h"
    -framework Metal
)

"${GE_SWIFTC}" "${SWIFT_FLAGS[@]}" \
    "${PROJECT_ROOT}/native/host/goldeneye_fidelity_policy.swift" \
    "${PROJECT_ROOT}/native/host/metal_source_scene_pipeline_v6.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_rareware_lod_pipeline_v6_smoke.swift" \
    -o "${BUILD_DIR}/lod-pipeline-smoke"
"${BUILD_DIR}/lod-pipeline-smoke" | tee "${BUILD_DIR}/lod-pipeline.log"
grep -Fq 'goldeneye_rareware_lod_pipeline_v6_smoke: PASS' "${BUILD_DIR}/lod-pipeline.log"

GE_METAL=$(xcrun --sdk macosx --find metal)
GE_METALLIB=$(dirname -- "${GE_METAL}")/metallib
"${GE_METAL}" -mmacosx-version-min=27.0 \
    -c "${PROJECT_ROOT}/native/shaders/GoldenEyeSourceSceneV6.metal" \
    -o "${BUILD_DIR}/GoldenEyeSourceSceneV6.rareware.air"
"${GE_METALLIB}" "${BUILD_DIR}/GoldenEyeSourceSceneV6.rareware.air" \
    -o "${BUILD_DIR}/GoldenEyeSourceSceneV6.rareware.metallib"
test -s "${BUILD_DIR}/GoldenEyeSourceSceneV6.rareware.metallib"

git -C "${PROJECT_ROOT}" diff --check -- \
    native/host/metal_source_scene_pipeline_v6.swift \
    native/shaders/GoldenEyeSourceSceneV6.metal \
    native/tests/goldeneye_rareware_lod_pipeline_v6_smoke.swift \
    scripts/test_rareware_lod_pipeline_v6.sh

echo 'Rareware LOD/FORCE_BLEND pipeline validation: PASS'
