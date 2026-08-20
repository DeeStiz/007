#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
DEFAULT_ASSET_ROOT="${ROOT}/build/native/cast-frontend-v6-image-decoder-v6-fullweapons"
if [[ ! -d "${DEFAULT_ASSET_ROOT}" ]]; then
    DEFAULT_ASSET_ROOT="${ROOT}/build/native/cast-frontend-v6-image-decoder-v6"
fi
ASSET_ROOT="${1:-${GOLDENEYE_NATIVE_SOURCE_FRONTEND_ROOT:-${DEFAULT_ASSET_ROOT}}}"
SIDECAR="${2:-${GOLDENEYE_NATIVE_GUNBARREL_SIDECAR:-${ROOT}/build/native/gunbarrel-v6-prepared/gunbarrel.gbar}}"
SCENE_METALLIB="${3:-${ROOT}/build/native/source-scene-renderer-v6/GoldenEyeSourceSceneV6.metallib}"
RUN_ID="${GE_CAST_CAPTURE_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
BUILD_ROOT="${ROOT}/build/native/cast-reference-capture-v6/${RUN_ID}"
MODULE_CACHE="${BUILD_ROOT}/module-cache"
mkdir -p "${BUILD_ROOT}" "${MODULE_CACHE}"
export CLANG_MODULE_CACHE_PATH="${MODULE_CACHE}"

STRICT_REGRESSION="${GE_CAST_STRICT_REGRESSION:-0}"
if [[ "${STRICT_REGRESSION}" == "1" ]]; then
    if [[ -n "${GE_CAST_ISOLATE_MODEL:-}${GE_CAST_DRAW_INDEX:-}${GE_CAST_DRAW_LIMIT:-}${GE_CAST_LEGACY_TEXTURES:-}${GE_CAST_MODELS:-}${GE_CAST_WINDING:-}" ]]; then
        echo "strict Cast regression forbids capture-only environment overrides" >&2
        exit 2
    fi
    export GE_CAST_SOURCE_INDEX=1
    export GE_CAST_RANDOM_SEED=93e5
    export GE_CAST_FLIP=false
    export GE_CAST_MODEL_ORDER=body,head,weapon
    export GE_CAST_CAMERA_MODE=source-rng
fi

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun --sdk macosx --find clang)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
CFLAGS=(
    -target arm64-apple-macosx27.0 -isysroot "${SDKROOT}"
    -std=c11 -Wall -Wextra -Werror -Wno-c23-extensions -pedantic
    -I "${ROOT}/native/include" -I "${ROOT}/native/source_port"
)
for source in ge_source_scene_v6.c ge_source_gbi_v6.c ge_source_texture_coordinates_v6.c \
    ge_stage_v5.c ge_stage_background_v5.c ge_ramrom_v5.c \
    ge_ramrom_playback_v5.c ge_native_runtime_v5.c ge_audio_v5.c; do
    "${CC}" "${CFLAGS[@]}" -O2 -c "${ROOT}/native/src/${source}" \
        -o "${BUILD_ROOT}/${source%.c}.o"
done
if [[ ! -s "${SCENE_METALLIB}" ]]; then
    scripts/test_metal_source_scene_v6.sh >/dev/null
fi

"${SWIFTC}" -swift-version 6 -warnings-as-errors -O \
    -target arm64-apple-macosx27.0 -sdk "${SDKROOT}" \
    -import-objc-header "${ROOT}/native/tests/goldeneye_native_bridging.h" \
    -Xcc "-I${ROOT}/native/include" -Xcc "-I${ROOT}/native/source_port" \
    -Xcc -include -Xcc "${ROOT}/native/include/ge_source_scene_v6.h" \
    -Xcc -include -Xcc "${ROOT}/native/include/ge_source_gbi_v6.h" \
    -Xcc -include -Xcc "${ROOT}/native/include/ge_source_texture_coordinates_v6.h" \
    -framework Metal -framework QuartzCore -framework CoreGraphics -framework ImageIO \
    "${ROOT}/native/host/goldeneye_fidelity_policy.swift" \
    "${ROOT}/native/host/title_geometry_packet.swift" \
    "${ROOT}/native/host/goldeneye_source_model_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_frontend_catalog_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_product_preparation_v6.swift" \
    "${ROOT}/native/host/goldeneye_cast_prepared_asset_catalog_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_product_contract_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_lighting_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_projection_binding_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_texture_coordinates_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_texture_setup_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_scene_snapshot_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_scene_composer_v6.swift" \
    "${ROOT}/native/host/goldeneye_gbi_scene_builder_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_node_transform_v6.swift" \
    "${ROOT}/native/host/goldeneye_attract_route.swift" \
    "${ROOT}/native/host/goldeneye_ramrom_playback_service.swift" \
    "${ROOT}/native/host/goldeneye_stage_asset_catalog.swift" \
    "${ROOT}/native/host/goldeneye_stage_setup_packet.swift" \
    "${ROOT}/native/host/goldeneye_stage_scene_packet.swift" \
    "${ROOT}/native/host/goldeneye_projection_v10.swift" \
    "${ROOT}/native/host/goldeneye_stage_background_draw_packet.swift" \
    "${ROOT}/native/host/goldeneye_stage_material_lowering_v6.swift" \
    "${ROOT}/native/host/goldeneye_cast_ramrom_scene_v6.swift" \
    "${ROOT}/native/host/goldeneye_cast_title_hash.swift" \
    "${ROOT}/native/host/goldeneye_cast_scene_composer_v6.swift" \
    "${ROOT}/native/host/goldeneye_gunbarrel_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_texture_store_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_scene_texture_binding_v6.swift" \
    "${ROOT}/native/host/metal_device_state.swift" \
    "${ROOT}/native/host/metal_source_scene_pipeline_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_scene_batching_v6.swift" \
    "${ROOT}/native/host/metal_source_scene_renderer_v6.swift" \
    "${ROOT}/native/host/goldeneye_reference_capture_codec_v6.swift" \
    "${ROOT}/native/tests/goldeneye_cast_reference_capture_v6_smoke.swift" \
    "${BUILD_ROOT}"/*.o \
    -o "${BUILD_ROOT}/goldeneye_cast_reference_capture_v6_smoke"

MTL_DEBUG_LAYER=1 MTL_SHADER_VALIDATION=1 MTL_SHADER_VALIDATION_REPORT_TO_STDERR=1 \
    "${BUILD_ROOT}/goldeneye_cast_reference_capture_v6_smoke" \
    "${ASSET_ROOT}" "${SIDECAR}" "${SCENE_METALLIB}" "${BUILD_ROOT}" \
    | tee "${BUILD_ROOT}/strict.log"
EXPECTED_IDENTITY="${GE_CAST_SOURCE_INDEX:-1}"
grep -Fq "goldeneye_cast_reference_capture_v6_smoke: PASS capturedIdentity=${EXPECTED_IDENTITY} missingPrepared=0" \
    "${BUILD_ROOT}/strict.log"
for artifact in cast-bond-320x240.raw cast-bond-320x240.png cast-bond-320x240.raw.json \
    cast-bond-faithful-hd.raw cast-bond-faithful-hd.png cast-reference.json; do
    test -s "${BUILD_ROOT}/${artifact}"
done
if [[ "${STRICT_REGRESSION}" == "1" ]]; then
    if rg -n -i 'cast_draw_isolation|capture[-_ ]only|GE_CAST_(ISOLATE|DRAW|MODELS|LEGACY|WINDING)' \
        "${BUILD_ROOT}/strict.log"; then
        echo "strict Cast regression emitted capture-only diagnostics" >&2
        exit 1
    fi
    grep -Fq '"strictRegression" : true' "${BUILD_ROOT}/cast-reference.json"
    grep -Eq '"bodyVertexLoadCount" : [1-9][0-9]*' "${BUILD_ROOT}/cast-reference.json"
    grep -Eq '"bodyAddressVertexLoadCount" : [1-9][0-9]*' "${BUILD_ROOT}/cast-reference.json"
    grep -Eq '"bodyMixedVertexLoadTriangleCount" : [1-9][0-9]*' "${BUILD_ROOT}/cast-reference.json"
    grep -Fq '"diagnosticCount" : 0' "${BUILD_ROOT}/cast-reference.json"

    REPEAT_ROOT="${BUILD_ROOT}/repeat"
    mkdir -p "${REPEAT_ROOT}"
    MTL_DEBUG_LAYER=1 MTL_SHADER_VALIDATION=1 MTL_SHADER_VALIDATION_REPORT_TO_STDERR=1 \
        "${BUILD_ROOT}/goldeneye_cast_reference_capture_v6_smoke" \
        "${ASSET_ROOT}" "${SIDECAR}" "${SCENE_METALLIB}" "${REPEAT_ROOT}" \
        | tee "${REPEAT_ROOT}/strict.log"
    grep -Fq "goldeneye_cast_reference_capture_v6_smoke: PASS capturedIdentity=1 missingPrepared=0" \
        "${REPEAT_ROOT}/strict.log"
    if rg -n -i 'cast_draw_isolation|capture[-_ ]only|GE_CAST_(ISOLATE|DRAW|MODELS|LEGACY|WINDING)' \
        "${REPEAT_ROOT}/strict.log"; then
        echo "strict Cast regression repeat emitted capture-only diagnostics" >&2
        exit 1
    fi
    for artifact in cast-bond-320x240.raw cast-bond-faithful-hd.raw cast-reference.json; do
        test -s "${REPEAT_ROOT}/${artifact}"
        cmp -s "${BUILD_ROOT}/${artifact}" "${REPEAT_ROOT}/${artifact}"
    done
    REFERENCE_SHA256=$(shasum -a 256 "${BUILD_ROOT}/cast-bond-320x240.raw" | awk '{print $1}')
    HD_SHA256=$(shasum -a 256 "${BUILD_ROOT}/cast-bond-faithful-hd.raw" | awk '{print $1}')
    REPEAT_REFERENCE_SHA256=$(shasum -a 256 "${REPEAT_ROOT}/cast-bond-320x240.raw" | awk '{print $1}')
    REPEAT_HD_SHA256=$(shasum -a 256 "${REPEAT_ROOT}/cast-bond-faithful-hd.raw" | awk '{print $1}')
    [[ "${REFERENCE_SHA256}" == "${REPEAT_REFERENCE_SHA256}" ]]
    [[ "${HD_SHA256}" == "${REPEAT_HD_SHA256}" ]]
    echo "test_cast_reference_capture_v6: PASS strict-regression referenceRawSHA256=${REFERENCE_SHA256} faithfulHDRawSHA256=${HD_SHA256} repeat=identical evidence=${BUILD_ROOT}"
    exit 0
fi
echo "test_cast_reference_capture_v6: PASS evidence=${BUILD_ROOT}"
