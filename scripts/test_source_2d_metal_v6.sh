#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${1:-${GOLDENEYE_NATIVE_SOURCE_FRONTEND_ROOT:-${PROJECT_ROOT}/build/native/source-frontend-v6}}"
BUILD_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/goldeneye-source-2d-metal-v6.XXXXXX")

if command -v xcrun >/dev/null 2>&1; then
    GE_SWIFTC=$(xcrun --sdk macosx --find swiftc)
    GE_METAL=$(xcrun --sdk macosx --find metal)
    GE_METALLIB=$(dirname -- "${GE_METAL}")/metallib
    SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
    SWIFT_FLAGS=(-swift-version 6 -warnings-as-errors -O -parse-as-library -target arm64-apple-macosx27.0 -sdk "${SDKROOT}")
else
    GE_SWIFTC=${SWIFTC:-swiftc}
    GE_METAL=${METAL:-metal}
    GE_METALLIB=${METALLIB:-metallib}
    SWIFT_FLAGS=(-swift-version 6 -warnings-as-errors -O -parse-as-library)
fi

SWIFT_SOURCES=(
    "${PROJECT_ROOT}/native/host/goldeneye_fidelity_policy.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_catalog_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_source_2d_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_file_mode_background_v6.swift"
    "${PROJECT_ROOT}/native/host/metal_device_state.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_source_2d_pipeline_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_source_2d_renderer_v6.swift"
    "${PROJECT_ROOT}/native/tests/goldeneye_source_2d_metal_v6_smoke.swift"
)

"${GE_SWIFTC}" "${SWIFT_FLAGS[@]}" "${SWIFT_SOURCES[@]}" \
    -o "${BUILD_ROOT}/goldeneye_source_2d_metal_v6_smoke"

"${BUILD_ROOT}/goldeneye_source_2d_metal_v6_smoke" "${ASSET_ROOT}" \
    | tee "${BUILD_ROOT}/strict.log"
grep -Fq 'goldeneye_source_2d_metal_v6_smoke: PASS' "${BUILD_ROOT}/strict.log"
grep -Fq 'renderer_fallback=false' "${BUILD_ROOT}/strict.log"

"${GE_METAL}" -mmacosx-version-min=27.0 -c \
    "${PROJECT_ROOT}/native/shaders/GoldenEyeSource2DV6.metal" \
    -o "${BUILD_ROOT}/GoldenEyeSource2DV6.air"
"${GE_METALLIB}" "${BUILD_ROOT}/GoldenEyeSource2DV6.air" \
    -o "${BUILD_ROOT}/GoldenEyeSource2DV6.metallib"
test -s "${BUILD_ROOT}/GoldenEyeSource2DV6.metallib"

if rg -n 'set(Vertex|Fragment|Compute)Bytes|nextDrawable' \
    "${PROJECT_ROOT}/native/host/goldeneye_source_2d_renderer_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_2d_pipeline_v6.swift"; then
    echo 'forbidden transient binding or drawable acquisition in source 2D renderer' >&2
    exit 1
fi

echo 'Source 2D V6 Metal 4 batch/pipeline/resource validation: PASS'
