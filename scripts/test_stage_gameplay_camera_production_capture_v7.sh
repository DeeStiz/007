#!/bin/bash
set -eo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$BASH_SOURCE")" && pwd -P)
PROJECT_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd -P)
if [[ $# -ge 1 ]]; then
    STAGE_ROOT="$1"
elif [[ -n "$GOLDENEYE_NATIVE_STAGE_ASSET_ROOT" ]]; then
    STAGE_ROOT="$GOLDENEYE_NATIVE_STAGE_ASSET_ROOT"
else
    STAGE_ROOT="$PROJECT_ROOT/build/native/stage-assets-image-decoder-v6"
fi
if [[ $# -ge 2 ]]; then
    VISIBLE_ROOT="$2"
elif [[ -n "$GOLDENEYE_NATIVE_RAMROM_VISIBLE_ROOT" ]]; then
    VISIBLE_ROOT="$GOLDENEYE_NATIVE_RAMROM_VISIBLE_ROOT"
else
    VISIBLE_ROOT="$PROJECT_ROOT/build/native/ramrom-visible-dependencies-v6"
fi
BUILD_DIR="$PROJECT_ROOT/build/native/stage-gameplay-camera-production-capture-v7"
MODULE_CACHE_DIR="$BUILD_DIR/module-cache"
if [[ -n "$GOLDENEYE_STAGE_GAMEPLAY_CAMERA_PRODUCTION_OUTPUT" ]]; then
    OUTPUT_DIR="$GOLDENEYE_STAGE_GAMEPLAY_CAMERA_PRODUCTION_OUTPUT"
else
    OUTPUT_DIR="$BUILD_DIR/captures"
fi
mkdir -p "$BUILD_DIR" "$MODULE_CACHE_DIR" "$OUTPUT_DIR"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
CC=$(xcrun --sdk macosx --find clang)
METALLIB=$(xcrun --sdk macosx --find metallib)
METAL_CRYPTEX=$(dirname "$METALLIB")/metal
if [[ -x "$METAL_CRYPTEX" ]]; then
    METAL="$METAL_CRYPTEX"
else
    METAL=$(xcrun --sdk macosx --find metal)
fi

compile_c() {
    source="$1"
    source_path="$PROJECT_ROOT/native/src/$source"
    source_no_ext=$(basename "$source" .c)
    object="$BUILD_DIR/$source_no_ext.o"
    if [[ "$source" == "ge_source_frontend_v6.c" ]]; then
        source_path="$PROJECT_ROOT/native/source_port/$source"
        "$CC" -target arm64-apple-macosx27.0 -isysroot "$SDKROOT" \
            -std=c11 -Wall -Wextra -Werror -Wno-c23-extensions -pedantic -O2 \
            -I "$PROJECT_ROOT/native/include" -I "$PROJECT_ROOT/native/source_port" \
            -c "$source_path" -o "$object"
    elif [[ "$source" == "ge_source_frontend_runtime_v6.c" ]]; then
        "$CC" -target arm64-apple-macosx27.0 -isysroot "$SDKROOT" \
            -std=c11 -Wall -Wextra -Werror -Wno-c23-extensions -pedantic -O2 \
            -I "$PROJECT_ROOT/native/include" -I "$PROJECT_ROOT/native/source_port" \
            -c "$source_path" -o "$object"
    else
        "$CC" -target arm64-apple-macosx27.0 -isysroot "$SDKROOT" \
            -std=c11 -Wall -Wextra -Werror -Wno-c23-extensions -pedantic -O2 \
            -I "$PROJECT_ROOT/native/include" -c "$source_path" -o "$object"
    fi
}

for source in \
    ge_source_gbi_v6.c ge_source_scene_v6.c ge_source_frontend_runtime_v6.c \
    ge_source_frontend_v6.c ge_file_mode_v6.c ge_source_texture_coordinates_v6.c \
    ge_stage_v5.c ge_stage_background_v5.c ge_ramrom_v5.c ge_native_runtime_v5.c \
    ge_audio_v5.c ge_ramrom_playback_v5.c; do
    compile_c "$source"
done

if [[ ! -s "$BUILD_DIR/GoldenEyeSourceSceneV6.metallib" \
      || "$PROJECT_ROOT/native/shaders/GoldenEyeSourceSceneV6.metal" -nt "$BUILD_DIR/GoldenEyeSourceSceneV6.metallib" ]]; then
    "$METAL" -mmacosx-version-min=27.0 \
        -fmodules-cache-path="$MODULE_CACHE_DIR" \
        -c "$PROJECT_ROOT/native/shaders/GoldenEyeSourceSceneV6.metal" \
        -o "$BUILD_DIR/GoldenEyeSourceSceneV6.air"
    "$METALLIB" "$BUILD_DIR/GoldenEyeSourceSceneV6.air" \
        -o "$BUILD_DIR/GoldenEyeSourceSceneV6.metallib"
fi

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" "$SWIFTC" \
    -swift-version 6 -warnings-as-errors -O -parse-as-library \
    -target arm64-apple-macosx27.0 -sdk "$SDKROOT" \
    -import-objc-header "$PROJECT_ROOT/native/tests/goldeneye_native_bridging.h" \
    -Xcc -I -Xcc "$PROJECT_ROOT/native/include" \
    -Xcc -include -Xcc "$PROJECT_ROOT/native/include/ge_source_gbi_v6.h" \
    -Xcc -include -Xcc "$PROJECT_ROOT/native/include/ge_source_scene_v6.h" \
    -Xcc -include -Xcc "$PROJECT_ROOT/native/include/ge_source_texture_coordinates_v6.h" \
    -framework Metal -framework QuartzCore -framework CoreGraphics -framework ImageIO \
    "$PROJECT_ROOT/native/host/goldeneye_fidelity_policy.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_projection_v10.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_attract_route.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_cast_title_hash.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_ramrom_playback_service.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_ramrom_visible_dependency_catalog_v6.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_stage_asset_catalog.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_stage_payload_store_v6.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_stage_transfer_queue_v6.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_stage_setup_packet.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_stage_scene_packet.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_stage_background_draw_packet.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_stage_material_lowering_v6.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_stage_texture_catalog_v6.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_stage_fog_lowering_v6.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_stage_setup_dependency_catalog_v6.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_stage_model_sidecar_catalog_v6.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_stage_model_placement_v6.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_stage_model_scene_composer_v6.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_stage_environment_camera_adapter_v6.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_stage_gameplay_camera_packet_v7.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_source_frontend_catalog_v6.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_source_frontend_authority_v6.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_source_product_provider_v6.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_source_product_preparation_v6.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_file_mode_authority_v6.swift" \
    "$PROJECT_ROOT/native/host/save_store.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_source_product_contract_v6.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_source_frontend_matrices_v6.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_source_projection_binding_v6.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_source_model_v6.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_source_scene_snapshot_v6.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_source_scene_composer_v6.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_source_texture_coordinates_v6.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_source_texture_store_v6.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_source_texture_setup_v6.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_source_node_transform_v6.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_gbi_scene_builder_v6.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_stage_source_scene_adapter_v6.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_source_scene_texture_binding_v6.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_source_lighting_v6.swift" \
    "$PROJECT_ROOT/native/host/metal_device_state.swift" \
    "$PROJECT_ROOT/native/host/metal_source_scene_pipeline_v6.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_source_scene_batching_v6.swift" \
    "$PROJECT_ROOT/native/host/goldeneye_reference_capture_codec_v6.swift" \
    "$PROJECT_ROOT/native/host/metal_source_scene_renderer_v6.swift" \
    "$PROJECT_ROOT/native/tests/goldeneye_stage_gameplay_camera_production_capture_v7_smoke.swift" \
    "$BUILD_DIR/ge_source_gbi_v6.o" "$BUILD_DIR/ge_source_scene_v6.o" \
    "$BUILD_DIR/ge_source_frontend_runtime_v6.o" "$BUILD_DIR/ge_source_frontend_v6.o" \
    "$BUILD_DIR/ge_file_mode_v6.o" "$BUILD_DIR/ge_source_texture_coordinates_v6.o" \
    "$BUILD_DIR/ge_stage_v5.o" "$BUILD_DIR/ge_stage_background_v5.o" \
    "$BUILD_DIR/ge_ramrom_v5.o" "$BUILD_DIR/ge_native_runtime_v5.o" \
    "$BUILD_DIR/ge_audio_v5.o" "$BUILD_DIR/ge_ramrom_playback_v5.o" \
    -o "$BUILD_DIR/goldeneye_stage_gameplay_camera_production_capture_v7_smoke"

MTL_DEBUG_LAYER=1 MTL_SHADER_VALIDATION=1 MTL_SHADER_VALIDATION_REPORT_TO_STDERR=1 \
    "$BUILD_DIR/goldeneye_stage_gameplay_camera_production_capture_v7_smoke" \
    "$STAGE_ROOT" "$VISIBLE_ROOT" "$BUILD_DIR/GoldenEyeSourceSceneV6.metallib" \
    "$OUTPUT_DIR" 2>&1 | tee "$BUILD_DIR/strict.log"

if grep -Fq 'goldeneye_stage_gameplay_camera_production_capture_v7_smoke: SKIP' \
    "$BUILD_DIR/strict.log"; then
    echo 'Stage gameplay-camera production supplied-drawable capture: SKIP (Metal 4 unavailable)'
    exit 0
fi
grep -Fq \
    'goldeneye_stage_gameplay_camera_production_capture_v7_smoke: PASS demo=0 stages=33,34,35,9,20,26,25 suppliedDrawable=1 roomProps=1 deterministic=1' \
    "$BUILD_DIR/strict.log"

python3 - "$OUTPUT_DIR" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
records = [root / f"stage-{stage}-demo-00-gameplay-camera.json"
           for stage in (33, 34, 35, 9, 20, 26, 25)]
for path in records:
    if not path.is_file():
        raise SystemExit(f"missing production capture metadata: {path}")
    data = json.loads(path.read_text())
    if data["unsupportedMask"] != 0 or data["fullSceneUnsupportedMask"] != 0x38:
        raise SystemExit(f"unexpected scoped/full mask in {path.name}")
    if data["drawableStaticPropPlacements"] != data["staticPropPlacements"]:
        raise SystemExit(f"undrawn static prop placement in {path.name}")
    if data["sceneDraws"] <= 0 or data["drawableStaticPropPlacements"] <= 0:
        raise SystemExit(f"scene did not retain static-prop draws in {path.name}")
    if len(data["rawSHA256"]) != 64:
        raise SystemExit(f"missing supplied-drawable pixel hash in {path.name}")
print("Stage gameplay-camera production supplied-drawable metadata: PASS stages=33,34,35,9,20,26,25")
PY
echo 'Stage gameplay-camera production supplied-drawable capture: PASS'
