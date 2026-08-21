#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BASE_BUILD_ROOT="${PROJECT_ROOT}/build/native/rareware-reference-capture-v6"
RUN_ID="${GE_RAREWARE_CAPTURE_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
BUILD_ROOT="${BASE_BUILD_ROOT}/${RUN_ID}"
SOURCE_ROOT="${BUILD_ROOT}/host-sources"
mkdir -p "${BUILD_ROOT}/module-cache" "${SOURCE_ROOT}"
# The shared checkout is intentionally busy with other source lanes. Snapshot
# the Swift inputs into this ignored run directory before compiling so a
# concurrent edit cannot invalidate the capture executable halfway through
# swiftc's module build.
cp -f "${PROJECT_ROOT}/native/host/"*.swift "${SOURCE_ROOT}/"
cp -f "${PROJECT_ROOT}/native/tests/goldeneye_native_bridging.h" "${BUILD_ROOT}/goldeneye_native_bridging.h"
cp -f "${PROJECT_ROOT}/native/tests/goldeneye_rareware_reference_capture_v6_smoke.swift" "${SOURCE_ROOT}/"
export CLANG_MODULE_CACHE_PATH="${BUILD_ROOT}/module-cache"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun --sdk macosx --find clang)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
METAL=$(xcrun --sdk macosx --find metal)
METALLIB_TOOL=$(dirname -- "${METAL}")/metallib
ASSET_ROOT="${1:-${PROJECT_ROOT}/build/native/source-frontend-v6}"
SCENE_METALLIB="${2:-${PROJECT_ROOT}/build/native/rareware-capture-v6/GoldenEyeSourceSceneV6.metallib}"

if [[ ! -s "${SCENE_METALLIB}" ]]; then
    mkdir -p "${PROJECT_ROOT}/build/native/rareware-capture-v6"
    "${METAL}" -mmacosx-version-min=27.0 \
        -c "${PROJECT_ROOT}/native/shaders/GoldenEyeSourceSceneV6.metal" \
        -o "${PROJECT_ROOT}/build/native/rareware-capture-v6/GoldenEyeSourceSceneV6.air"
    "${METALLIB_TOOL}" \
        "${PROJECT_ROOT}/build/native/rareware-capture-v6/GoldenEyeSourceSceneV6.air" \
        -o "${SCENE_METALLIB}"
fi

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
    -swift-version 6 -warnings-as-errors -O -g
    -target arm64-apple-macosx27.0 -sdk "${SDKROOT}"
    -import-objc-header "${BUILD_ROOT}/goldeneye_native_bridging.h"
    -Xcc "-I${PROJECT_ROOT}/native/include"
    -Xcc "-I${PROJECT_ROOT}/native/source_port"
    -framework Metal -framework QuartzCore -framework CoreGraphics -framework ImageIO
)
"${SWIFTC}" "${SWIFT_FLAGS[@]}" \
    "${SOURCE_ROOT}/goldeneye_fidelity_policy.swift" \
    "${SOURCE_ROOT}/goldeneye_source_lighting_v6.swift" \
    "${SOURCE_ROOT}/save_store.swift" \
    "${SOURCE_ROOT}/goldeneye_file_mode_authority_v6.swift" \
    "${SOURCE_ROOT}/goldeneye_source_frontend_authority_v6.swift" \
    "${SOURCE_ROOT}/goldeneye_source_frontend_matrices_v6.swift" \
    "${SOURCE_ROOT}/goldeneye_source_projection_binding_v6.swift" \
    "${SOURCE_ROOT}/goldeneye_source_product_contract_v6.swift" \
    "${SOURCE_ROOT}/goldeneye_source_frontend_catalog_v6.swift" \
    "${SOURCE_ROOT}/goldeneye_source_product_preparation_v6.swift" \
    "${SOURCE_ROOT}/goldeneye_source_product_provider_v6.swift" \
    "${SOURCE_ROOT}/goldeneye_source_model_v6.swift" \
    "${SOURCE_ROOT}/goldeneye_source_scene_snapshot_v6.swift" \
    "${SOURCE_ROOT}/goldeneye_stage_fog_lowering_v6.swift" \
    "${SOURCE_ROOT}/goldeneye_source_node_transform_v6.swift" \
    "${SOURCE_ROOT}/goldeneye_source_texture_coordinates_v6.swift" \
    "${SOURCE_ROOT}/goldeneye_source_texture_setup_v6.swift" \
    "${SOURCE_ROOT}/goldeneye_gbi_scene_builder_v6.swift" \
    "${SOURCE_ROOT}/goldeneye_source_texture_store_v6.swift" \
    "${SOURCE_ROOT}/goldeneye_reference_capture_codec_v6.swift" \
    "${SOURCE_ROOT}/metal_device_state.swift" \
    "${SOURCE_ROOT}/metal_source_scene_pipeline_v6.swift" \
    "${SOURCE_ROOT}/goldeneye_source_scene_texture_binding_v6.swift" \
    "${SOURCE_ROOT}/goldeneye_source_scene_batching_v6.swift" \
    "${SOURCE_ROOT}/metal_source_scene_renderer_v6.swift" \
    "${SOURCE_ROOT}/goldeneye_rareware_frame_v6.swift" \
    "${SOURCE_ROOT}/goldeneye_rareware_reference_capture_v6_smoke.swift" \
    "${BUILD_ROOT}/ge_source_frontend_runtime_v6.o" \
    "${BUILD_ROOT}/ge_source_frontend_v6.o" \
    "${BUILD_ROOT}/ge_source_scene_v6.o" \
    "${BUILD_ROOT}/ge_source_gbi_v6.o" \
    "${BUILD_ROOT}/ge_source_texture_coordinates_v6.o" \
    "${BUILD_ROOT}/ge_file_mode_v6.o" \
    -o "${BUILD_ROOT}/smoke"

MTL_DEBUG_LAYER=1 \
MTL_SHADER_VALIDATION=1 \
MTL_SHADER_VALIDATION_REPORT_TO_STDERR=1 \
    "${BUILD_ROOT}/smoke" "${ASSET_ROOT}" "${SCENE_METALLIB}" "${BUILD_ROOT}" \
    | tee "${BUILD_ROOT}/strict.log"
grep -Fq 'goldeneye_rareware_reference_capture_v6_smoke: PASS' "${BUILD_ROOT}/strict.log"

for artifact in \
    rareware-320x240-odd-t20.raw rareware-320x240-odd-t20.png \
    rareware-320x240-even-t70.raw rareware-320x240-even-t70.png \
    rareware-320x240-front-t200.raw rareware-320x240-front-t200.png \
    rareware-320x240-late-t260.raw rareware-320x240-late-t260.png \
    rareware-faithful-hd-odd-t20.raw rareware-faithful-hd-odd-t20.png \
    rareware-faithful-hd-even-t70.raw rareware-faithful-hd-even-t70.png \
    rareware-faithful-hd-front-t200.raw rareware-faithful-hd-front-t200.png \
    rareware-faithful-hd-late-t260.raw rareware-faithful-hd-late-t260.png \
    rareware-reference.json; do
    test -s "${BUILD_ROOT}/${artifact}"
done
for draw in 0 1 2 3 4 5; do
    test -s "${BUILD_ROOT}/rareware-isolated-draw${draw}-front-t200.raw"
    test -s "${BUILD_ROOT}/rareware-isolated-draw${draw}-front-t200.png"
done

python3 - "${BUILD_ROOT}/rareware-reference.json" <<'PY'
import json
import pathlib
import sys

data = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert data["screen"] == "Rareware"
assert data["frontFacing"] == "counterClockwise"
assert data["sourceDisplayListCount"] == 9
assert data["sourceCommandCount"] == 389
assert data["sourceVertexCount"] == 397
assert data["sourceTriangleCount"] == 268
assert data["sourceTextureCount"] == 6
assert data["sourceMipCount"] == 26
assert data["sourceMipChainCount"] == 4
assert data["sourceCommandHash"] == "ef6d7f7278f9f74a"
assert data["sourceSFXAssetID"] == 258
assert data["unsupportedVisibleCount"] == 0
assert data["projectionConsumptionComplete"] is True
assert data["faithfulHDWidth"] == 1280
assert data["faithfulHDHeight"] == 960
assert data["metalValidationRequested"] is True
phases = data["phases"]
assert [phase["name"] for phase in phases] == ["odd-t20", "even-t70", "front-t200", "late-t260"]
assert [phase["sourceTimer"] for phase in phases] == [20, 70, 200, 260]
assert phases[0]["pairPhase"] == 1
assert phases[1]["pairPhase"] == 0
assert phases[3]["fadeAlpha"] == 0
assert phases[2]["rotationDegreesQ16"] == 360 * 65536
assert phases[2]["fadeAlpha"] == 110
assert len({phase["rawSHA256"] for phase in phases}) == 4
assert all(phase["unsupportedVisibleCount"] == 0 for phase in phases)
assert all(phase["projectionConsumed"] == phase["projectionRequired"] for phase in phases)
isolated = data["isolatedFrontDraws"]
assert len(isolated) == 6
assert [item["drawIndex"] for item in isolated] == list(range(6))
assert all(item["drawCount"] == 1 and item["triangleCount"] > 0 for item in isolated)
assert all(item["nonBlackPixels"] > 0 and item["maxRGB"] > 0 for item in isolated)
assert all(item["drawIndex"] in (0, 5) or item["nonBlackPixels"] > 0 for item in isolated)
for item in isolated[1:5]:
    assert item["setupTile"] == 0
    assert item["setupMaxLOD"] == 5
    assert item["setupMipLevels"] == 6
    assert item["tileBoundsQ2"] == [2, 2, 126, 126]
    assert item["rawOtherModeH"] == 0x00192c00
assert len({item["rawSHA256"] for item in isolated}) >= 4
print("rareware-reference metadata: PASS")
PY

echo 'Rareware source-faithful captures: PASS (320x240 + Faithful HD; Metal validation enabled)'
echo "Artifact: ${BUILD_ROOT}/strict.log"
