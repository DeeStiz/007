#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${1:-${GOLDENEYE_NATIVE_STAGE_ASSET_ROOT:-${PROJECT_ROOT}/build/native/stage-assets-image-decoder-v6}}"
BUILD_DIR="${PROJECT_ROOT}/build/native/stage-source-environment-v6"
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
    "${PROJECT_ROOT}/native/src/ge_source_scene_v6.c"
)
OBJECTS=()
for source in "${C_SOURCES[@]}"; do
    object="${BUILD_DIR}/$(basename "${source}" .c).o"
    "${CC}" "${COMMON_CFLAGS[@]}" -c "${source}" -o "${object}"
    OBJECTS+=("${object}")
done

ASAN_OBJECTS=()
UBSAN_OBJECTS=()
for source in "${C_SOURCES[@]}"; do
    stem=$(basename "${source}" .c)
    asan_object="${BUILD_DIR}/${stem}.asan.o"
    ubsan_object="${BUILD_DIR}/${stem}.ubsan.o"
    "${CC}" "${COMMON_CFLAGS[@]}" -fsanitize=address -c "${source}" -o "${asan_object}"
    "${CC}" "${COMMON_CFLAGS[@]}" -fsanitize=undefined -c "${source}" -o "${ubsan_object}"
    ASAN_OBJECTS+=("${asan_object}")
    UBSAN_OBJECTS+=("${ubsan_object}")
done

echo "Building source portal-environment packet smoke"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${SWIFTC}" \
    "${SWIFT_ARGS[@]}" \
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_stage_source_environment_v6_bridging.h" \
    -Xcc "-I${PROJECT_ROOT}/native/include" \
    "${PROJECT_ROOT}/native/host/goldeneye_projection_v10.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_attract_route.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_cast_title_hash.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_ramrom_playback_service.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_asset_catalog.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_payload_store_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_transfer_queue_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_setup_packet.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_scene_packet.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_background_draw_packet.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_cast_ramrom_scene_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_catalog_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_model_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_store_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_material_lowering_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_texture_catalog_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_fog_lowering_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_source_scene_adapter_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_environment_camera_adapter_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_snapshot_v6.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_stage_source_environment_v6_smoke.swift" \
    "${OBJECTS[@]}" \
    -o "${BUILD_DIR}/goldeneye_stage_source_environment_v6_smoke"

"${BUILD_DIR}/goldeneye_stage_source_environment_v6_smoke" "${ASSET_ROOT}" \
    | tee "${BUILD_DIR}/stage-source-environment-v6.log"
grep -Fq 'goldeneye_stage_source_environment_v6_smoke: PASS stages=7' \
    "${BUILD_DIR}/stage-source-environment-v6.log"

echo "Building ASan source room-environment packet smoke"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${SWIFTC}" \
    "${SWIFT_ARGS[@]}" -sanitize=address \
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_stage_source_environment_v6_bridging.h" \
    -Xcc "-I${PROJECT_ROOT}/native/include" \
    "${PROJECT_ROOT}/native/host/goldeneye_projection_v10.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_attract_route.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_cast_title_hash.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_ramrom_playback_service.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_asset_catalog.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_payload_store_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_transfer_queue_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_setup_packet.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_scene_packet.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_background_draw_packet.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_cast_ramrom_scene_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_catalog_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_model_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_store_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_material_lowering_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_texture_catalog_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_fog_lowering_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_source_scene_adapter_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_environment_camera_adapter_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_snapshot_v6.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_stage_source_environment_v6_smoke.swift" \
    "${ASAN_OBJECTS[@]}" \
    -o "${BUILD_DIR}/goldeneye_stage_source_environment_v6_smoke_asan"
ASAN_OPTIONS=halt_on_error=1:detect_leaks=0 \
    "${BUILD_DIR}/goldeneye_stage_source_environment_v6_smoke_asan" "${ASSET_ROOT}" \
    | tee "${BUILD_DIR}/stage-source-environment-v6-asan.log"
grep -Fq 'goldeneye_stage_source_environment_v6_smoke: PASS stages=7' \
    "${BUILD_DIR}/stage-source-environment-v6-asan.log"

echo "Building UBSan source room-environment packet smoke"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${SWIFTC}" \
    "${SWIFT_ARGS[@]}" -sanitize=undefined \
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_stage_source_environment_v6_bridging.h" \
    -Xcc "-I${PROJECT_ROOT}/native/include" \
    "${PROJECT_ROOT}/native/host/goldeneye_projection_v10.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_attract_route.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_cast_title_hash.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_ramrom_playback_service.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_asset_catalog.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_payload_store_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_transfer_queue_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_setup_packet.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_scene_packet.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_background_draw_packet.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_cast_ramrom_scene_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_catalog_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_model_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_store_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_material_lowering_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_texture_catalog_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_fog_lowering_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_source_scene_adapter_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_environment_camera_adapter_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_snapshot_v6.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_stage_source_environment_v6_smoke.swift" \
    "${UBSAN_OBJECTS[@]}" \
    -o "${BUILD_DIR}/goldeneye_stage_source_environment_v6_smoke_ubsan"
UBSAN_OPTIONS=halt_on_error=1 \
    "${BUILD_DIR}/goldeneye_stage_source_environment_v6_smoke_ubsan" "${ASSET_ROOT}" \
    | tee "${BUILD_DIR}/stage-source-environment-v6-ubsan.log"
grep -Fq 'goldeneye_stage_source_environment_v6_smoke: PASS stages=7' \
    "${BUILD_DIR}/stage-source-environment-v6-ubsan.log"

echo "Source portal-environment packet validation: PASS"
