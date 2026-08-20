#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${GE_GUNBARREL_ASSET_ROOT:-${ROOT}/build/native/source-frontend-v6-image-decoder-v6}"
SIDECAR="${GE_GUNBARREL_SIDECAR:-${ROOT}/build/native/gunbarrel-v6-prepared/gunbarrel.gbar}"
BUILD_ROOT="${GE_GUNBARREL_BUILD_ROOT:-${ROOT}/build/native/gunbarrel-metal-reference-capture-v6}"
mkdir -p "${BUILD_ROOT}/c"

python3 "${SCRIPT_DIR}/prepare_native_gunbarrel_v6.py" \
    --project-root "${ROOT}" \
    --output "${SIDECAR}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
CC=$(xcrun --sdk macosx --find clang)
METAL=$(xcrun --sdk macosx --find metal)
METALLIB=$(dirname -- "${METAL}")/metallib

CFLAGS=(-target arm64-apple-macosx27.0 -isysroot "${SDKROOT}" -std=c11
    -Wall -Wextra -Werror -Wno-c23-extensions -pedantic
    -I "${ROOT}/native/include")
for source in ge_source_gbi_v6.c ge_source_scene_v6.c ge_source_frontend_runtime_v6.c ge_file_mode_v6.c ge_source_texture_coordinates_v6.c; do
    "${CC}" "${CFLAGS[@]}" -O2 -c "${ROOT}/native/src/${source}" \
        -o "${BUILD_ROOT}/c/${source%.c}.o"
done
"${CC}" "${CFLAGS[@]}" -I "${ROOT}/native/source_port" -O2 -c \
    "${ROOT}/native/source_port/ge_source_frontend_v6.c" \
    -o "${BUILD_ROOT}/c/ge_source_frontend_v6.o"

if [[ "${GE_GUNBARREL_SKIP_METAL_BUILD:-0}" != "1" ]]; then
    "${METAL}" -mmacosx-version-min=27.0 -isysroot "${SDKROOT}" \
        -c "${ROOT}/native/shaders/GoldenEyeSourceSceneV6.metal" \
        -o "${BUILD_ROOT}/GoldenEyeSourceSceneV6.air"
    "${METALLIB}" "${BUILD_ROOT}/GoldenEyeSourceSceneV6.air" \
        -o "${BUILD_ROOT}/GoldenEyeSourceSceneV6.metallib"
else
    test -s "${BUILD_ROOT}/GoldenEyeSourceSceneV6.metallib"
fi

SWIFT_FLAGS=(-swift-version 6 -warnings-as-errors -O -parse-as-library -D GE_SOURCE_MATRIX_STANDALONE
    -target arm64-apple-macosx27.0 -sdk "${SDKROOT}"
    -import-objc-header "${ROOT}/native/tests/goldeneye_native_bridging.h"
    -Xcc "-I${ROOT}/native/include" -Xcc "-I${ROOT}/native/source_port"
    -framework Metal -framework QuartzCore -framework CoreGraphics -framework ImageIO)
"${SWIFTC}" "${SWIFT_FLAGS[@]}" \
    "${ROOT}/native/host/goldeneye_fidelity_policy.swift" \
    "${ROOT}/native/host/title_geometry_packet.swift" \
    "${ROOT}/native/host/goldeneye_source_model_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_frontend_catalog_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_frontend_matrices_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_scene_snapshot_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_scene_composer_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_node_transform_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_projection_binding_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_texture_coordinates_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_texture_setup_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_texture_store_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_scene_texture_binding_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_lighting_v6.swift" \
    "${ROOT}/native/host/goldeneye_reference_capture_codec_v6.swift" \
    "${ROOT}/native/host/metal_device_state.swift" \
    "${ROOT}/native/host/metal_source_scene_pipeline_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_scene_batching_v6.swift" \
    "${ROOT}/native/host/metal_source_scene_renderer_v6.swift" \
    "${ROOT}/native/host/goldeneye_gunbarrel_v6.swift" \
    "${ROOT}/native/host/goldeneye_cast_skeleton_transform_v6.swift" \
    "${ROOT}/native/host/metal_gunbarrel_pass_renderer_v6.swift" \
    "${ROOT}/native/host/goldeneye_gbi_scene_builder_v6.swift" \
    "${ROOT}/native/tests/goldeneye_gunbarrel_metal_reference_capture_v6_smoke.swift" \
    "${BUILD_ROOT}/c/"*.o \
    -o "${BUILD_ROOT}/goldeneye_gunbarrel_metal_reference_capture_v6_smoke"

"${BUILD_ROOT}/goldeneye_gunbarrel_metal_reference_capture_v6_smoke" \
    "${ASSET_ROOT}" \
    "${BUILD_ROOT}/GoldenEyeSourceSceneV6.metallib" \
    "${SIDECAR}" \
    "${BUILD_ROOT}/captures" \
    | tee "${BUILD_ROOT}/capture.log"
grep -Fq 'goldeneye_gunbarrel_metal_reference_capture_v6_smoke: PASS' "${BUILD_ROOT}/capture.log"
for mode in 2 3 4 5 6 7 8 9; do
    test -s "${BUILD_ROOT}/captures/gunbarrel-mode-${mode}-320x240.raw"
    test -s "${BUILD_ROOT}/captures/gunbarrel-mode-${mode}-1280x960.raw"
    test -s "${BUILD_ROOT}/captures/gunbarrel-mode-${mode}-1280x960.png"
done
if [[ "${GE_GUNBARREL_TEMPORAL_SWEEP:-0}" == "1" ]]; then
    for timer in 40 50 100 136 137 152 168 169 212 230 348 400; do
        test -s "${BUILD_ROOT}/captures/gunbarrel-timer-${timer}-320x240.raw"
        test -s "${BUILD_ROOT}/captures/gunbarrel-timer-${timer}-320x240.png"
    done
fi
echo "test_gunbarrel_metal_reference_capture_v6: PASS"
