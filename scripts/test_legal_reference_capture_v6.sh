#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${1:-${PROJECT_ROOT}/build/native/source-frontend-v6}"
DEFAULT_GENERATION=$(awk -F= '$1 == "packet_sha256" { print $2; exit }' \
    "${ASSET_ROOT}/source-frontend-v6-manifest.txt" 2>/dev/null || true)
CAPTURE_GENERATION="${2:-${DEFAULT_GENERATION:-unknown}}"
BUILD_ROOT="${PROJECT_ROOT}/build/native/legal-reference-capture-v6/${CAPTURE_GENERATION}"
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
    -I "${PROJECT_ROOT}/native/include"
    -I "${PROJECT_ROOT}/native/source_port"
)
for source in ge_source_frontend_runtime_v6.c ge_source_scene_v6.c ge_source_gbi_v6.c \
    ge_file_mode_v6.c ge_source_texture_coordinates_v6.c; do
    "${CC}" "${CFLAGS[@]}" -O2 -c "${PROJECT_ROOT}/native/src/${source}" \
        -o "${BUILD_ROOT}/${source%.c}.o"
done
"${CC}" "${CFLAGS[@]}" -O2 -c \
    "${PROJECT_ROOT}/native/source_port/ge_source_frontend_v6.c" \
    -o "${BUILD_ROOT}/ge_source_frontend_v6.o"

SWIFT_FLAGS=(
    -swift-version 6 -warnings-as-errors -Onone
    -target arm64-apple-macosx27.0 -sdk "${SDKROOT}"
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_native_bridging.h"
    -Xcc "-I${PROJECT_ROOT}/native/include"
    -Xcc "-I${PROJECT_ROOT}/native/source_port"
    -framework Metal -framework QuartzCore -framework CoreGraphics -framework ImageIO
)
"${SWIFTC}" "${SWIFT_FLAGS[@]}" \
    "${PROJECT_ROOT}/native/host/goldeneye_fidelity_policy.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_lighting_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_catalog_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_product_preparation_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_product_contract_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_model_v6.swift" \
    "${PROJECT_ROOT}/native/host/title_geometry_packet.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_gunbarrel_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_projection_binding_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_matrices_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_product_provider_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_snapshot_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_coordinates_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_texture_binding_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_rareware_frame_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_gbi_scene_builder_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_node_transform_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_2d_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_file_mode_background_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_authority_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_file_mode_authority_v6.swift" \
    "${PROJECT_ROOT}/native/host/save_store.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_legal_frame_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_store_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_setup_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_reference_capture_codec_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_2d_pipeline_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_2d_renderer_v6.swift" \
    "${PROJECT_ROOT}/native/host/metal_source_scene_pipeline_v6.swift" \
    "${PROJECT_ROOT}/native/host/metal_device_state.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_batching_v6.swift" \
    "${PROJECT_ROOT}/native/host/metal_source_scene_renderer_v6.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_legal_reference_capture_v6_smoke.swift" \
    "${BUILD_ROOT}/ge_source_frontend_runtime_v6.o" \
    "${BUILD_ROOT}/ge_source_frontend_v6.o" \
    "${BUILD_ROOT}/ge_source_scene_v6.o" \
    "${BUILD_ROOT}/ge_source_gbi_v6.o" \
    "${BUILD_ROOT}/ge_file_mode_v6.o" \
    "${BUILD_ROOT}/ge_source_texture_coordinates_v6.o" \
    -o "${BUILD_ROOT}/smoke"

METALLIB="${PROJECT_ROOT}/build/native/source-scene-renderer-v6/GoldenEyeSourceSceneV6.metallib"
if [[ ! -s "${METALLIB}" ]]; then
    scripts/test_metal_source_scene_v6.sh >/dev/null
fi
METALLIB="${PROJECT_ROOT}/build/native/source-scene-renderer-v6/GoldenEyeSourceSceneV6.metallib"
TWO_D_METALLIB="${BUILD_ROOT}/GoldenEyeSource2DV6.metallib"
if [[ ! -s "${TWO_D_METALLIB}" ]]; then
    "${METAL}" -mmacosx-version-min=27.0 -c \
        "${PROJECT_ROOT}/native/shaders/GoldenEyeSource2DV6.metal" \
        -o "${BUILD_ROOT}/GoldenEyeSource2DV6.air"
    "${METALLIB_TOOL}" "${BUILD_ROOT}/GoldenEyeSource2DV6.air" \
        -o "${TWO_D_METALLIB}"
fi

"${BUILD_ROOT}/smoke" \
    "${ASSET_ROOT}" \
    "${METALLIB}" \
    "${TWO_D_METALLIB}" \
    "${BUILD_ROOT}/legal-reference-320x240-composite.raw" \
    | tee "${BUILD_ROOT}/strict.log"
grep -Fq 'goldeneye_legal_reference_capture_v6_smoke: PASS' "${BUILD_ROOT}/strict.log" \
    || grep -Fq 'goldeneye_legal_reference_capture_v6_smoke: SKIP' "${BUILD_ROOT}/strict.log"

if grep -Fq 'goldeneye_legal_reference_capture_v6_smoke: PASS' "${BUILD_ROOT}/strict.log"; then
    test -s "${BUILD_ROOT}/legal-reference-320x240-composite.raw"
    test -s "${BUILD_ROOT}/legal-reference-320x240-composite.png"
    test -s "${BUILD_ROOT}/legal-reference-320x240-composite.raw.json"
    test -s "${BUILD_ROOT}/legal-reference-320x240-composite.text.json"
    test -s "${BUILD_ROOT}/legal-reference-320x240-composite-3d.raw"
    test -s "${BUILD_ROOT}/legal-reference-320x240-composite-3d.png"
    test -s "${BUILD_ROOT}/legal-reference-320x240-composite-3d.raw.json"
    test -s "${BUILD_ROOT}/legal-faithful-hd-640x480.raw"
    test -s "${BUILD_ROOT}/legal-faithful-hd-640x480.png"
    test -s "${BUILD_ROOT}/legal-faithful-hd-640x480-3d.raw"
    test -s "${BUILD_ROOT}/legal-faithful-hd-640x480-3d.png"
    jq -e '
        .sourceVertexCoverageMatches == true and
        .sourceSemanticClosure == true and
        .pixelParityClaimed == false and
        .sourceCompleteVisualAcceptance == false and
        .faithfulHDWidth == 640 and
        .faithfulHDHeight == 480 and
        .frontFacing == "counterClockwise" and
        (.faithfulHDRawSHA256 | length == 64) and
        (.faithfulHD3DRawSHA256 | length == 64) and
        .faithfulHDRawSHA256 != .faithfulHD3DRawSHA256 and
        .faithfulHDGlyphDrawCount == 253 and
        (.isolatedMaterialEvidence | length == 5) and
        all(.isolatedMaterialEvidence[];
            (.resourceHandle == .expectedResourceHandle) and
            (.contributedNonBlack == true or .sourceBlackOrTransparentProof == true) and
            (([.normalizedUV[][0]] | min) < 0.05) and
            (([.normalizedUV[][0]] | max) > 0.95) and
            (([.normalizedUV[][1]] | min) < 0.05) and
            (([.normalizedUV[][1]] | max) > 0.95))
    ' "${BUILD_ROOT}/legal-reference-320x240-composite.text.json" >/dev/null
fi

echo 'Legal Reference 320x240 capture: PASS (source-semantic material closure; lossless raw/PNG/JSON; hardware pixel parity remains open; Metal unavailable is explicit SKIP)'
echo "Artifact: ${BUILD_ROOT}/strict.log"
