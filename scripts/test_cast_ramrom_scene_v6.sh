#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${1:-${GOLDENEYE_NATIVE_ASSET_ROOT:-${PROJECT_ROOT}/build/native/boot-assets}}"
STAGE_ROOT="${2:-${GOLDENEYE_NATIVE_STAGE_ASSET_ROOT:-${PROJECT_ROOT}/build/native/stage-assets-image-decoder-v6}}"
BUILD_DIR="${PROJECT_ROOT}/build/native/cast-ramrom-scene-v6"
MODULE_CACHE_DIR="${BUILD_DIR}/module-cache"
mkdir -p "${BUILD_DIR}" "${MODULE_CACHE_DIR}"

CC=$(xcrun --sdk macosx --find clang)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
SDKROOT=$(xcrun --sdk macosx --show-sdk-path)

COMMON_CFLAGS=(
    -target arm64-apple-macosx27.0 -isysroot "${SDKROOT}"
    -std=c11 -Wall -Wextra -Werror -pedantic -O2
    -I "${PROJECT_ROOT}/native/include"
)
SWIFT_ARGS=(
    -swift-version 6 -warnings-as-errors
    -target arm64-apple-macosx27.0 -sdk "${SDKROOT}"
)

C_SOURCES=(
    "${PROJECT_ROOT}/native/src/ge_stage_v5.c"
    "${PROJECT_ROOT}/native/src/ge_stage_background_v5.c"
    "${PROJECT_ROOT}/native/src/ge_ramrom_v5.c"
    "${PROJECT_ROOT}/native/src/ge_ramrom_playback_v5.c"
    "${PROJECT_ROOT}/native/src/ge_native_runtime_v5.c"
    "${PROJECT_ROOT}/native/src/ge_audio_v5.c"
)
OBJECTS=()
for source in "${C_SOURCES[@]}"; do
    object="${BUILD_DIR}/$(basename "${source}" .c).o"
    "${CC}" "${COMMON_CFLAGS[@]}" -c "${source}" -o "${object}"
    OBJECTS+=("${object}")
done

echo "Building Cast/RAMROM source-scene authority smoke"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${SWIFTC}" \
    "${SWIFT_ARGS[@]}" \
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_stage_gameplay_runtime_bridging.h" \
    -Xcc "-I${PROJECT_ROOT}/native/include" \
    "${PROJECT_ROOT}/native/host/goldeneye_attract_route.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_cast_title_hash.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_ramrom_playback_service.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_asset_catalog.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_setup_packet.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_scene_packet.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_projection_v10.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_background_draw_packet.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_material_lowering_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_cast_ramrom_scene_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_cast_source_scene_v6.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_cast_ramrom_scene_v6_smoke.swift" \
    "${OBJECTS[@]}" \
    -o "${BUILD_DIR}/goldeneye_cast_ramrom_scene_v6_smoke"

SMOKE_ARGS=("${ASSET_ROOT}")
if [[ -d "${STAGE_ROOT}" ]]; then
    SMOKE_ARGS+=("${STAGE_ROOT}")
fi
"${BUILD_DIR}/goldeneye_cast_ramrom_scene_v6_smoke" "${SMOKE_ARGS[@]}" \
    | tee "${BUILD_DIR}/cast-ramrom-scene-v6.log"
grep -Fq 'goldeneye_cast_ramrom_scene_v6_smoke: PASS castIdentity=30 animations=22 demos=14 runs=28 manifest=14 stageVisual=FAIL_CLOSED' \
    "${BUILD_DIR}/cast-ramrom-scene-v6.log"

echo "Cast/RAMROM source-scene authority validation: PASS"
