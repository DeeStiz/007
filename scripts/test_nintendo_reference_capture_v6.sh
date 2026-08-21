#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BASE_BUILD_ROOT="${PROJECT_ROOT}/build/native/nintendo-reference-capture-v6"
RUN_ID="${GE_NINTENDO_CAPTURE_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
BUILD_ROOT="${BASE_BUILD_ROOT}/${RUN_ID}"
mkdir -p "${BUILD_ROOT}/module-cache"
export CLANG_MODULE_CACHE_PATH="${BUILD_ROOT}/module-cache"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun --sdk macosx --find clang)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
METAL=$(xcrun --sdk macosx --find metal)
METALLIB_TOOL=$(dirname -- "${METAL}")/metallib
ASSET_ROOT="${1:-${PROJECT_ROOT}/build/native/source-frontend-v6}"

CFLAGS=(
    -std=c11 -Wall -Wextra -Werror -Wno-c23-extensions -pedantic
    -target arm64-apple-macosx27.0 -isysroot "${SDKROOT}"
    -I "${PROJECT_ROOT}/native/include"
    -I "${PROJECT_ROOT}/native/source_port"
)
for source in ge_source_frontend_runtime_v6.c ge_source_scene_v6.c ge_source_gbi_v6.c ge_source_texture_coordinates_v6.c ge_file_mode_v6.c; do
    "${CC}" "${CFLAGS[@]}" -O2 -c "${PROJECT_ROOT}/native/src/${source}" \
        -o "${BUILD_ROOT}/${source%.c}.o"
done
"${CC}" "${CFLAGS[@]}" -O2 -c \
    "${PROJECT_ROOT}/native/source_port/ge_source_frontend_v6.c" \
    -o "${BUILD_ROOT}/ge_source_frontend_v6.o"

SWIFT_FLAGS=(
    -swift-version 6 -warnings-as-errors -O
    -target arm64-apple-macosx27.0 -sdk "${SDKROOT}"
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_native_bridging.h"
    -Xcc "-I${PROJECT_ROOT}/native/include"
    -Xcc "-I${PROJECT_ROOT}/native/source_port"
    -framework Metal -framework QuartzCore -framework CoreGraphics -framework ImageIO
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
    "${PROJECT_ROOT}/native/host/goldeneye_stage_fog_lowering_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_snapshot_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_gbi_scene_builder_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_node_transform_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_store_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_setup_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_texture_binding_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_coordinates_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_reference_capture_codec_v6.swift" \
    "${PROJECT_ROOT}/native/host/metal_device_state.swift" \
    "${PROJECT_ROOT}/native/host/metal_source_scene_pipeline_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_batching_v6.swift" \
    "${PROJECT_ROOT}/native/host/metal_source_scene_renderer_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_nintendo_frame_v6.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_nintendo_reference_capture_v6_smoke.swift" \
    "${BUILD_ROOT}/ge_source_frontend_runtime_v6.o" \
    "${BUILD_ROOT}/ge_source_frontend_v6.o" \
    "${BUILD_ROOT}/ge_source_scene_v6.o" \
    "${BUILD_ROOT}/ge_source_gbi_v6.o" \
    "${BUILD_ROOT}/ge_source_texture_coordinates_v6.o" \
    "${BUILD_ROOT}/ge_file_mode_v6.o" \
    -o "${BUILD_ROOT}/smoke"

SCENE_METALLIB="${PROJECT_ROOT}/build/native/source-scene-renderer-v6/GoldenEyeSourceSceneV6.metallib"
if [[ ! -s "${SCENE_METALLIB}" ]]; then
    scripts/test_metal_source_scene_v6.sh >/dev/null
fi

if [[ "${GOLDENEYE_M15_CAPTURE:-0}" == "1" ]]; then
    # Metal GPU capture and shader validation cannot be enabled together on
    # this runtime.  The normal lane below remains shader/API validated;
    # capture is a separate evidence run as required by Metal tooling.
    MTL_DEBUG_LAYER=1 \
    MTL_CAPTURE_ENABLED=1 \
        "${BUILD_ROOT}/smoke" "${ASSET_ROOT}" "${SCENE_METALLIB}" "${BUILD_ROOT}" \
        | tee "${BUILD_ROOT}/strict.log"
else
    MTL_DEBUG_LAYER=1 \
    MTL_SHADER_VALIDATION=1 \
    MTL_SHADER_VALIDATION_REPORT_TO_STDERR=1 \
        "${BUILD_ROOT}/smoke" "${ASSET_ROOT}" "${SCENE_METALLIB}" "${BUILD_ROOT}" \
        | tee "${BUILD_ROOT}/strict.log"
fi
grep -Fq 'goldeneye_nintendo_reference_capture_v6_smoke: PASS' "${BUILD_ROOT}/strict.log" \
    || grep -Fq 'goldeneye_nintendo_reference_capture_v6_smoke: SKIP' "${BUILD_ROOT}/strict.log"

if grep -Fq 'goldeneye_nintendo_reference_capture_v6_smoke: PASS' "${BUILD_ROOT}/strict.log"; then
    test -s "${BUILD_ROOT}/nintendo-320x240-even.raw"
    test -s "${BUILD_ROOT}/nintendo-320x240-even.png"
    test -s "${BUILD_ROOT}/nintendo-320x240-even.raw.json"
    test -s "${BUILD_ROOT}/nintendo-320x240-odd.raw"
    test -s "${BUILD_ROOT}/nintendo-320x240-odd.png"
    test -s "${BUILD_ROOT}/nintendo-320x240-odd.raw.json"
    test -s "${BUILD_ROOT}/nintendo-winding-clockwise.raw"
    test -s "${BUILD_ROOT}/nintendo-winding-clockwise.png"
    test -s "${BUILD_ROOT}/nintendo-winding-clockwise.raw.json"
    test -s "${BUILD_ROOT}/nintendo-reference.json"
    python3 - "${BUILD_ROOT}/nintendo-reference.json" <<'PY'
import json
import pathlib
import sys

data = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert data["screen"] == "Nintendo"
assert data["sourceNodeCount"] == 42
assert data["sourceDisplayListCount"] == 23
assert data["sourceCommandCount"] == 821
assert data["sourceVertexCount"] == 1363
assert data["sourceTriangleCount"] == 1021
assert data["renderedTriangleCount"] == 1018
assert data["suppressedDegenerateCount"] == 3
assert data["suppressedDegenerate"] == [
    {"sourceCommandIndex": 740, "packetByteOffset": 6112, "sourceLine": 2937,
     "semantic": "gsSP4Triangles(7,8,9,10,11,12,10,12,13,0,0,0)", "visible": False},
    {"sourceCommandIndex": 766, "packetByteOffset": 6320, "sourceLine": 2963,
     "semantic": "gsSP4Triangles(9,6,10,10,11,9,12,10,13,0,0,0)", "visible": False},
    {"sourceCommandIndex": 784, "packetByteOffset": 6464, "sourceLine": 2981,
     "semantic": "gsSP4Triangles(7,8,9,10,11,12,13,10,12,0,0,0)", "visible": False},
]
assert data["sourceTextureCount"] == 1
assert data["textureWidth"] == 32
assert data["textureHeight"] == 32
assert data["textureDepth"] == 1
assert data["textureMipCount"] == 1
assert data["sourceOrderHash"] == "9cc62b913ce52e5b"
assert data["commandOrderCount"] == 821
assert len(data["commandOrder"]) == 821
assert data["commandOrder"][0]["index"] == 0
assert data["commandOrder"][-1]["index"] == 820
assert data["packetCommandCount"] == 845
assert data["packetListCount"] == 24
assert data["packetVertexCount"] == 1363
assert data["packetImageCount"] == 1
assert data["textureResourceFormat"] == 6
assert data["textureResourceWidth"] == 32
assert data["textureResourceHeight"] == 32
assert data["textureResourceMipLevels"] == 1
assert data["boundTextureHandles"] == [data["textureResourceHandle"]]
assert data["decoderDrawCount"] == 1018
assert data["visibleNodeIDs"] == list(range(42))
assert data["displayListIDs"] == list(range(23))
assert len(data["perDrawCoverage"]) == 3
assert all(row["triangleCount"] > 0 for row in data["perDrawCoverage"])
assert all(row["nonBlackPixelCount"] > 0 for row in data["perDrawCoverage"])
assert all(row["frontClockwiseCount"] + row["backCounterClockwiseCount"] + row["degenerateCount"] == row["triangleCount"]
           for row in data["perDrawCoverage"])
assert all(row["bbox"][0] <= row["bbox"][2] and row["bbox"][1] <= row["bbox"][3]
           for row in data["perDrawCoverage"])
assert data["evenNativeTick"] % 2 == 0
assert data["oddNativeTick"] == data["evenNativeTick"] + 1
assert data["evenRawSHA256"] != data["oddRawSHA256"]
assert data["windingClockwiseRawSHA256"] != data["evenRawSHA256"]
assert data["productionFrontFacing"] == "counterClockwise"
assert data["debugWindingFrontFacing"] == "clockwise"
assert data["productionCullMode"] == "back"
assert 0 <= data["ambientClampedByte"] <= 255
assert data["directionalColor"] == [0.0, 0.0, 0.0, 1.0]
assert data["reflectionRight"] == [1.0, 0.0, 0.0, 0.0]
assert data["reflectionUp"] == [0.0, 1.0, 0.0, 0.0]
print("nintendo-reference metadata: PASS")
PY
fi

echo 'Nintendo source-faithful reference capture validation: PASS (Metal validation enabled; unavailable Metal is explicit SKIP)'
echo "Artifact: ${BUILD_ROOT}/strict.log"
