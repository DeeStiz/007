#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
STAGE_ROOT="${1:-${GOLDENEYE_NATIVE_STAGE_ASSET_ROOT:-${PROJECT_ROOT}/build/native/stage-assets-image-decoder-v6}}"
BOOT_ROOT="${2:-${GOLDENEYE_NATIVE_ASSET_ROOT:-${PROJECT_ROOT}/build/native/boot-assets}}"
VISIBLE_ROOT="${3:-${GOLDENEYE_NATIVE_RAMROM_VISIBLE_ROOT:-${PROJECT_ROOT}/build/native/ramrom-visible-dependencies-v6}}"
BUILD_DIR="${PROJECT_ROOT}/build/native/stage-gameplay-camera-reference-capture-v6"
OUTPUT_DIR="${GOLDENEYE_STAGE_GAMEPLAY_CAMERA_CAPTURE_OUTPUT:-${BUILD_DIR}/captures}"
MODULE_CACHE_DIR="${BUILD_DIR}/module-cache"
mkdir -p "${BUILD_DIR}" "${MODULE_CACHE_DIR}" "${OUTPUT_DIR}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
CC=$(xcrun --sdk macosx --find clang)
METAL=$(xcrun --sdk macosx --find metal)
METALLIB=$(dirname "${METAL}")/metallib
CFLAGS=(-target arm64-apple-macosx27.0 -isysroot "${SDKROOT}" -std=c11
    -Wall -Wextra -Werror -pedantic -O2
    -I "${PROJECT_ROOT}/native/include"
    -I "${PROJECT_ROOT}/native/source_port/gameplay_v6")
OBJECTS=()
for source in ge_ramrom_v5.c ge_ramrom_playback_v5.c ge_stage_v5.c ge_stage_background_v5.c; do
    object="${BUILD_DIR}/${source%.c}.o"
    "${CC}" "${CFLAGS[@]}" -c "${PROJECT_ROOT}/native/src/${source}" -o "${object}"
    OBJECTS+=("${object}")
done
for source in ge_source_scene_v6.c; do
    object="${BUILD_DIR}/${source%.c}.o"
    "${CC}" "${CFLAGS[@]}" -c "${PROJECT_ROOT}/native/src/${source}" -o "${object}"
    OBJECTS+=("${object}")
done
for source in ge_ramrom_gameplay_v6.c ge_player_camera_owner_v6.c ge_guard_door_owner_v6.c ge_weapon_effect_owner_v6.c; do
    object="${BUILD_DIR}/${source%.c}.o"
    "${CC}" "${CFLAGS[@]}" -c "${PROJECT_ROOT}/native/source_port/gameplay_v6/${source}" -o "${object}"
    OBJECTS+=("${object}")
done

if [[ ! -s "${BUILD_DIR}/GoldenEyeSourceSceneV6.metallib" \
      || "${PROJECT_ROOT}/native/shaders/GoldenEyeSourceSceneV6.metal" -nt "${BUILD_DIR}/GoldenEyeSourceSceneV6.metallib" ]]; then
    "${METAL}" -mmacosx-version-min=27.0 \
        -fmodules-cache-path="${MODULE_CACHE_DIR}" \
        -c "${PROJECT_ROOT}/native/shaders/GoldenEyeSourceSceneV6.metal" \
        -o "${BUILD_DIR}/GoldenEyeSourceSceneV6.air"
    "${METALLIB}" "${BUILD_DIR}/GoldenEyeSourceSceneV6.air" \
        -o "${BUILD_DIR}/GoldenEyeSourceSceneV6.metallib"
fi

SWIFT_FLAGS=(
    -swift-version 6 -warnings-as-errors -O -parse-as-library
    -target arm64-apple-macosx27.0 -sdk "${SDKROOT}"
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_stage_gameplay_camera_reference_capture_v6_bridging.h"
    -Xcc -I -Xcc "${PROJECT_ROOT}/native/include"
    -Xcc -I -Xcc "${PROJECT_ROOT}/native/source_port/gameplay_v6"
    -Xcc -include -Xcc "${PROJECT_ROOT}/native/include/goldeneye_native.h"
    -Xcc -include -Xcc "${PROJECT_ROOT}/native/include/ge_source_scene_v6.h"
    -framework Metal -framework QuartzCore -framework CoreGraphics -framework ImageIO
)
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${SWIFTC}" "${SWIFT_FLAGS[@]}" \
    "${PROJECT_ROOT}/native/host/goldeneye_fidelity_policy.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_projection_v10.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_attract_route.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_cast_title_hash.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_ramrom_playback_service.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_asset_catalog.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_setup_packet.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_scene_packet.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_background_draw_packet.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_material_lowering_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_texture_catalog_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_fog_lowering_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_source_scene_adapter_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_environment_camera_adapter_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_catalog_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_model_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_store_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_texture_binding_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_lighting_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_snapshot_v6.swift" \
    "${PROJECT_ROOT}/native/host/metal_device_state.swift" \
    "${PROJECT_ROOT}/native/host/metal_source_scene_pipeline_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_batching_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_reference_capture_codec_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_model_sidecar_catalog_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_setup_dependency_catalog_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_ramrom_visible_dependency_catalog_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_ramrom_gameplay_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_ramrom_non_model_visuals_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_ramrom_non_model_authority_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_player_camera_owner_v6.swift" \
    "${PROJECT_ROOT}/native/host/metal_source_scene_renderer_v6.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_stage_gameplay_camera_reference_capture_v6_smoke.swift" \
    "${OBJECTS[@]}" \
    -o "${BUILD_DIR}/smoke"

MTL_DEBUG_LAYER=1 MTL_SHADER_VALIDATION=1 MTL_SHADER_VALIDATION_REPORT_TO_STDERR=1 \
    "${BUILD_DIR}/smoke" "${STAGE_ROOT}" "${BOOT_ROOT}" "${VISIBLE_ROOT}" \
    "${BUILD_DIR}/GoldenEyeSourceSceneV6.metallib" "${OUTPUT_DIR}" \
    2>&1 | tee "${BUILD_DIR}/strict.log"
grep -Fq 'goldeneye_stage_gameplay_camera_reference_capture_v6_smoke: PASS demos=14 checkpoints=42' \
    "${BUILD_DIR}/strict.log"
python3 - "${OUTPUT_DIR}" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
records = sorted(root.glob("demo-*-start.json")) + \
    sorted(root.glob("demo-*-mid.json")) + sorted(root.glob("demo-*-end.json"))
if len(records) != 42:
    raise SystemExit(f"expected 42 gameplay-camera metadata records, found {len(records)}")
required = {
    "visibleRoomIndices", "roomCoordinateScaleQ16", "cameraWorldPositionQ16",
    "currentRoomTriangleCount", "depthMinQ16", "depthMaxQ16",
    "nonBlackPixelCount", "nonBlackPixelRatio", "texturedNonBlackPixelCount",
    "blackWithoutFade",
}
black = 0
for path in records:
    data = json.loads(path.read_text())
    missing = sorted(required.difference(data))
    if missing:
        raise SystemExit(f"{path.name} missing checkpoint metrics: {','.join(missing)}")
    if not data["visibleRoomIndices"]:
        raise SystemExit(f"{path.name} has no source portal-visible room set")
    if data["blackWithoutFade"]:
        black += 1
print(f"Gameplay-camera checkpoint metrics: PASS records={len(records)} black_without_fade={black}")
PY
echo 'Stage gameplay-camera all14 checkpoint capture validation: PASS'
