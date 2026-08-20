#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BASE_BUILD_ROOT="${PROJECT_ROOT}/build/native/goldeneye-logo-reference-capture-v6"
RUN_ID="${GE_GOLDENEYE_CAPTURE_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
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
for source in ge_source_frontend_runtime_v6.c ge_source_scene_v6.c ge_source_gbi_v6.c \
    ge_source_texture_coordinates_v6.c ge_file_mode_v6.c; do
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
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_snapshot_v6.swift" \
   "${PROJECT_ROOT}/native/host/goldeneye_source_texture_coordinates_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_setup_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_gbi_scene_builder_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_node_transform_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_store_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_reference_capture_codec_v6.swift" \
    "${PROJECT_ROOT}/native/host/metal_device_state.swift" \
    "${PROJECT_ROOT}/native/host/metal_source_scene_pipeline_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_texture_binding_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_batching_v6.swift" \
    "${PROJECT_ROOT}/native/host/metal_source_scene_renderer_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_goldeneye_logo_frame_v6.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_goldeneye_logo_reference_capture_v6_smoke.swift" \
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

MTL_DEBUG_LAYER=1 \
MTL_SHADER_VALIDATION=1 \
MTL_SHADER_VALIDATION_REPORT_TO_STDERR=1 \
    "${BUILD_ROOT}/smoke" "${ASSET_ROOT}" "${SCENE_METALLIB}" "${BUILD_ROOT}" \
    | tee "${BUILD_ROOT}/strict.log"
grep -Fq 'goldeneye_goldeneye_logo_reference_capture_v6_smoke: PASS' "${BUILD_ROOT}/strict.log"

for artifact in \
    goldeneye-320x240-odd.raw goldeneye-320x240-odd.png goldeneye-320x240-odd.raw.json \
    goldeneye-320x240-even.raw goldeneye-320x240-even.png goldeneye-320x240-even.raw.json \
    goldeneye-faithful-hd.raw goldeneye-faithful-hd.png goldeneye-reference.json; do
    test -s "${BUILD_ROOT}/${artifact}"
done

python3 - "${BUILD_ROOT}/goldeneye-reference.json" <<'PY'
import json
import pathlib
import sys

data = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert data["screen"] == "GoldenEye"
assert data["frontFacing"] == "counterClockwise"
assert data["sourceNodeCount"] == 3
assert data["sourceDisplayListCount"] == 1
assert data["sourceCommandCount"] == 162
assert data["sourceVertexCount"] == 438
assert data["sourceTriangleCount"] == 339
assert data["sourceTriangleSlotCount"] == 341
assert data["sourceTextureCount"] == 2
assert data["sourceMipCount"] == 7
assert data["sourceTLUTCount"] == 0
assert data["packetCommandCount"] == 164
assert data["packetListCount"] == 2
assert data["packetVertexCount"] == 438
assert data["packetImageCount"] == 2
assert data["decoderDrawCount"] == 339
assert data["stateCount"] == 2
assert data["drawCount"] == 2
assert len(data["materialTextureHandles"]) == 2
assert data["textureSetupCount"] > 0
assert data["textureSetupResources"] == sorted(data["materialTextureHandles"])
assert [item["packetByteOffset"] for item in data["omittedDegenerateTriangles"]] == [0x290, 0x400]
assert [item["sourceCommandIndex"] for item in data["omittedDegenerateTriangles"]] == [80, 126]
assert all(item["sourceVertexIndices"] == [0, 0, 0] for item in data["omittedDegenerateTriangles"])
assert all(item["reason"] == "gsSP4Triangles zero sentinel (0,0,0)" for item in data["omittedDegenerateTriangles"])
assert data["projectionConsumptionComplete"] is True
assert data["unsupportedVisibleCount"] == 0
assert data["hasGoldPixels"] is True
assert data["hasRedPixels"] is True
assert data["hasGoldPixelsHD"] is True
assert data["hasRedPixelsHD"] is True
assert data["oddNativeTick"] % 2 == 1
assert data["evenNativeTick"] == data["oddNativeTick"] + 1
assert data["oddSourceTimer"] == 0
assert data["evenSourceTimer"] == 1
assert data["oddReferenceRawSHA256"] == data["evenReferenceRawSHA256"]
assert data["faithfulHDWidth"] == 1280
assert data["faithfulHDHeight"] == 960
print("goldeneye-reference metadata: PASS")
PY

echo 'GoldenEye logo source-faithful captures: PASS (320x240 + Faithful HD; Metal validation enabled)'
echo "Artifact: ${BUILD_ROOT}/strict.log"
