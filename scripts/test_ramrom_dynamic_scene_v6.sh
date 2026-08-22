#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_ROOT="${ROOT}/build/native/ramrom-dynamic-scene-v6"
MODULE_CACHE="${BUILD_ROOT}/module-cache"
mkdir -p "${BUILD_ROOT}" "${MODULE_CACHE}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun --sdk macosx --find clang)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
CFLAGS=(-target arm64-apple-macosx27.0 -isysroot "${SDKROOT}" -std=c11 -Wall -Wextra -Werror -pedantic -O2
    -I "${ROOT}/native/include" -I "${ROOT}/native/source_port/gameplay_v6")
SWIFT_ARGS=(-swift-version 6 -warnings-as-errors -target arm64-apple-macosx27.0 -sdk "${SDKROOT}")

OBJECTS=()
for source in ge_ramrom_v5.c ge_ramrom_playback_v5.c ge_stage_v5.c \
    ge_stage_background_v5.c ge_native_runtime_v5.c ge_audio_v5.c \
    ge_source_scene_v6.c ge_source_gbi_v6.c ge_source_texture_coordinates_v6.c; do
    object="${BUILD_ROOT}/${source%.c}.o"
    "${CC}" "${CFLAGS[@]}" -c "${ROOT}/native/src/${source}" -o "${object}"
    OBJECTS+=("${object}")
done
for source in ge_guard_door_owner_v6.c ge_player_camera_owner_v6.c ge_weapon_effect_owner_v6.c ge_ramrom_gameplay_v6.c; do
    object="${BUILD_ROOT}/${source%.c}.o"
    "${CC}" "${CFLAGS[@]}" -c "${ROOT}/native/source_port/gameplay_v6/${source}" -o "${object}"
    OBJECTS+=("${object}")
done

SOURCES=(
    "${ROOT}/native/host/goldeneye_attract_route.swift"
    "${ROOT}/native/host/goldeneye_ramrom_playback_service.swift"
    "${ROOT}/native/host/goldeneye_stage_asset_catalog.swift"
    "${ROOT}/native/host/goldeneye_stage_payload_store_v6.swift"
    "${ROOT}/native/host/goldeneye_stage_transfer_queue_v6.swift"
    "${ROOT}/native/host/goldeneye_stage_setup_packet.swift"
    "${ROOT}/native/host/goldeneye_stage_scene_packet.swift"
    "${ROOT}/native/host/goldeneye_stage_background_draw_packet.swift"
    "${ROOT}/native/host/goldeneye_stage_material_lowering_v6.swift"
    "${ROOT}/native/host/goldeneye_projection_v10.swift"
    "${ROOT}/native/host/goldeneye_source_model_v6.swift"
    "${ROOT}/native/host/goldeneye_stage_model_sidecar_catalog_v6.swift"
    "${ROOT}/native/host/goldeneye_stage_setup_dependency_catalog_v6.swift"
    "${ROOT}/native/host/goldeneye_ramrom_visible_dependency_catalog_v6.swift"
    "${ROOT}/native/host/goldeneye_source_frontend_catalog_v6.swift"
    "${ROOT}/native/host/goldeneye_source_product_preparation_v6.swift"
    "${ROOT}/native/host/goldeneye_source_product_contract_v6.swift"
    "${ROOT}/native/host/goldeneye_source_scene_snapshot_v6.swift"
    "${ROOT}/native/host/goldeneye_source_scene_composer_v6.swift"
    "${ROOT}/native/host/goldeneye_source_projection_binding_v6.swift"
    "${ROOT}/native/host/goldeneye_source_texture_setup_v6.swift"
    "${ROOT}/native/host/goldeneye_source_texture_coordinates_v6.swift"
    "${ROOT}/native/host/goldeneye_source_node_transform_v6.swift"
    "${ROOT}/native/host/goldeneye_gbi_scene_builder_v6.swift"
    "${ROOT}/native/host/goldeneye_cast_ramrom_scene_v6.swift"
    "${ROOT}/native/host/goldeneye_cast_title_hash.swift"
    "${ROOT}/native/host/goldeneye_cast_prepared_asset_catalog_v6.swift"
    "${ROOT}/native/host/goldeneye_cast_scene_composer_v6.swift"
    "${ROOT}/native/host/goldeneye_ramrom_dynamic_scene_v6.swift"
    "${ROOT}/native/tests/goldeneye_ramrom_dynamic_scene_v6_smoke.swift"
)

echo "Building strict RAMROM dynamic scene V6 smoke"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE}" "${SWIFTC}" "${SWIFT_ARGS[@]}" \
    -import-objc-header "${ROOT}/native/tests/goldeneye_ramrom_dynamic_scene_v6_bridging.h" \
    -Xcc "-I${ROOT}/native/include" -Xcc "-I${ROOT}/native/source_port/gameplay_v6" \
    -Xcc -include -Xcc "${ROOT}/native/include/ge_source_gbi_v6.h" \
    -Xcc -include -Xcc "${ROOT}/native/include/ge_source_texture_coordinates_v6.h" \
    -Xcc -include -Xcc "${ROOT}/native/include/ge_ramrom_playback_v5.h" \
    "${SOURCES[@]}" "${OBJECTS[@]}" -o "${BUILD_ROOT}/smoke"
"${BUILD_ROOT}/smoke" | tee "${BUILD_ROOT}/strict.log"
grep -Fq 'goldeneye_ramrom_dynamic_scene_v6_smoke: PASS routes=14' "${BUILD_ROOT}/strict.log"

echo "Building ASan RAMROM dynamic scene V6 smoke"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE}" "${SWIFTC}" "${SWIFT_ARGS[@]}" -sanitize=address \
    -import-objc-header "${ROOT}/native/tests/goldeneye_ramrom_dynamic_scene_v6_bridging.h" \
    -Xcc "-I${ROOT}/native/include" -Xcc "-I${ROOT}/native/source_port/gameplay_v6" \
    -Xcc -include -Xcc "${ROOT}/native/include/ge_source_gbi_v6.h" \
    -Xcc -include -Xcc "${ROOT}/native/include/ge_source_texture_coordinates_v6.h" \
    -Xcc -include -Xcc "${ROOT}/native/include/ge_ramrom_playback_v5.h" \
    "${SOURCES[@]}" "${OBJECTS[@]}" -o "${BUILD_ROOT}/smoke-asan"
ASAN_OPTIONS=halt_on_error=1:detect_leaks=0 "${BUILD_ROOT}/smoke-asan" \
    | tee "${BUILD_ROOT}/asan.log"
grep -Fq 'goldeneye_ramrom_dynamic_scene_v6_smoke: PASS routes=14' "${BUILD_ROOT}/asan.log"

echo "Building UBSan RAMROM dynamic scene V6 smoke"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE}" "${SWIFTC}" "${SWIFT_ARGS[@]}" -sanitize=undefined \
    -import-objc-header "${ROOT}/native/tests/goldeneye_ramrom_dynamic_scene_v6_bridging.h" \
    -Xcc "-I${ROOT}/native/include" -Xcc "-I${ROOT}/native/source_port/gameplay_v6" \
    -Xcc -include -Xcc "${ROOT}/native/include/ge_source_gbi_v6.h" \
    -Xcc -include -Xcc "${ROOT}/native/include/ge_source_texture_coordinates_v6.h" \
    -Xcc -include -Xcc "${ROOT}/native/include/ge_ramrom_playback_v5.h" \
    "${SOURCES[@]}" "${OBJECTS[@]}" -o "${BUILD_ROOT}/smoke-ubsan"
UBSAN_OPTIONS=halt_on_error=1 "${BUILD_ROOT}/smoke-ubsan" \
    | tee "${BUILD_ROOT}/ubsan.log"
grep -Fq 'goldeneye_ramrom_dynamic_scene_v6_smoke: PASS routes=14' "${BUILD_ROOT}/ubsan.log"

git -C "${ROOT}" diff --check
echo "Native RAMROM dynamic scene V6 validation: PASS"
