#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
STAGE_ROOT="${1:-${GOLDENEYE_NATIVE_STAGE_ASSET_ROOT:-${PROJECT_ROOT}/build/native/stage-assets-image-decoder-v6}}"
VISIBLE_ROOT="${2:-${GOLDENEYE_NATIVE_VISIBLE_DEPENDENCY_ROOT:-${PROJECT_ROOT}/build/native/ramrom-visible-dependencies-v6}}"
BUILD_DIR="${GOLDENEYE_STAGE_GAMEPLAY_CAMERA_PACKET_BUILD_DIR:-${PROJECT_ROOT}/build/native/stage-gameplay-camera-packet-v7}"
MODULE_CACHE_DIR="${BUILD_DIR}/module-cache"
mkdir -p "${BUILD_DIR}" "${MODULE_CACHE_DIR}"

MANIFEST="${STAGE_ROOT}/stage-assets-manifest.txt"
if [[ "${GOLDENEYE_STAGE_GAMEPLAY_CAMERA_PACKET_SKIP_MANIFEST_GUARD:-0}" != "1" ]] \
    && { [[ ! -f "${MANIFEST}" ]] || ! grep -Fxq 'resource_count=21' "${MANIFEST}" \
        || ! grep -Fxq 'manifest_status=PASS' "${MANIFEST}"; }; then
    echo "Stage gameplay-camera packet V7: FAIL (stage manifest must report resource_count=21 and manifest_status=PASS)" >&2
    exit 2
fi

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun --sdk macosx --find clang)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
COMMON_CFLAGS=(-target arm64-apple-macosx27.0 -isysroot "${SDKROOT}" -std=c11
    -Wall -Wextra -Werror -Wno-c23-extensions -pedantic
    -I "${PROJECT_ROOT}/native/include")
SWIFT_COMMON=(-swift-version 6 -warnings-as-errors -target arm64-apple-macosx27.0
    -sdk "${SDKROOT}" -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_native_bridging.h"
    -Xcc "-I${PROJECT_ROOT}/native/include" -Xcc -include
    -Xcc "${PROJECT_ROOT}/native/include/ge_source_gbi_v6.h" -Xcc -include
    -Xcc "${PROJECT_ROOT}/native/include/ge_source_scene_v6.h" -Xcc -include
    -Xcc "${PROJECT_ROOT}/native/include/ge_source_texture_coordinates_v6.h")

C_SOURCES=(
    "${PROJECT_ROOT}/native/src/ge_source_gbi_v6.c"
    "${PROJECT_ROOT}/native/src/ge_source_scene_v6.c"
    "${PROJECT_ROOT}/native/src/ge_source_frontend_runtime_v6.c"
    "${PROJECT_ROOT}/native/source_port/ge_source_frontend_v6.c"
    "${PROJECT_ROOT}/native/src/ge_file_mode_v6.c"
    "${PROJECT_ROOT}/native/src/ge_source_texture_coordinates_v6.c"
    "${PROJECT_ROOT}/native/src/ge_stage_v5.c"
    "${PROJECT_ROOT}/native/src/ge_stage_background_v5.c"
    "${PROJECT_ROOT}/native/src/ge_ramrom_v5.c"
    "${PROJECT_ROOT}/native/src/ge_native_runtime_v5.c"
    "${PROJECT_ROOT}/native/src/ge_audio_v5.c"
    "${PROJECT_ROOT}/native/src/ge_ramrom_playback_v5.c"
)

build_c_objects() {
    local output_dir="$1"
    local sanitizer="${2:-}"
    mkdir -p "${output_dir}"
    local flags=()
    if [[ -n "${sanitizer}" ]]; then
        flags=(-fsanitize="${sanitizer}" -fno-omit-frame-pointer)
    fi
    local index=0
    for source in "${C_SOURCES[@]}"; do
        local object="${output_dir}/$(basename "${source}" .c).o"
        local include_flags=()
        if [[ "${source}" == *ge_source_frontend_v6.c || "${source}" == *ge_source_frontend_runtime_v6.c ]]; then
            include_flags=(-I "${PROJECT_ROOT}/native/source_port")
        fi
        "${CC}" "${COMMON_CFLAGS[@]}" "${flags[@]-}" "${include_flags[@]-}" -O2 \
            -c "${source}" -o "${object}"
        C_OBJECTS[${index}]="${object}"
        index=$((index + 1))
    done
}

SWIFT_SOURCES=(
    "${PROJECT_ROOT}/native/host/goldeneye_attract_route.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_cast_title_hash.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_ramrom_playback_service.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_ramrom_visible_dependency_catalog_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_stage_asset_catalog.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_stage_payload_store_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_stage_transfer_queue_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_stage_setup_packet.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_stage_scene_packet.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_stage_background_draw_packet.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_stage_material_lowering_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_stage_texture_catalog_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_stage_fog_lowering_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_stage_source_scene_adapter_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_stage_environment_camera_adapter_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_stage_setup_dependency_catalog_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_stage_model_sidecar_catalog_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_stage_model_placement_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_stage_model_scene_composer_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_projection_v10.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_source_model_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_catalog_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_authority_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_source_product_provider_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_source_product_preparation_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_file_mode_authority_v6.swift"
    "${PROJECT_ROOT}/native/host/save_store.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_source_product_contract_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_matrices_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_source_projection_binding_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_snapshot_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_composer_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_coordinates_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_store_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_setup_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_source_node_transform_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_gbi_scene_builder_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_stage_gameplay_camera_packet_v7.swift"
    "${PROJECT_ROOT}/native/tests/goldeneye_stage_gameplay_camera_packet_v7_smoke.swift"
)

build_variant() {
    local name="$1"
    local swift_sanitizer="${2:-}"
    local c_sanitizer="${3:-}"
    local variant_dir="${BUILD_DIR}/${name}"
    mkdir -p "${variant_dir}"
    C_OBJECTS=()
    build_c_objects "${variant_dir}/c" "${c_sanitizer}"
    local swift_flags=("${SWIFT_COMMON[@]}" -Onone)
    if [[ -n "${swift_sanitizer}" ]]; then
        swift_flags+=("-sanitize=${swift_sanitizer}")
    fi
    CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${SWIFTC}" \
        "${swift_flags[@]}" "${SWIFT_SOURCES[@]}" "${C_OBJECTS[@]}" \
        -o "${variant_dir}/goldeneye_stage_gameplay_camera_packet_v7_smoke"
    "${variant_dir}/goldeneye_stage_gameplay_camera_packet_v7_smoke" "${STAGE_ROOT}" "${VISIBLE_ROOT}" \
        2>&1 | tee "${BUILD_DIR}/${name}.log"
    grep -Fq 'goldeneye_stage_gameplay_camera_packet_v7_smoke: PASS' "${BUILD_DIR}/${name}.log"
}

build_variant strict
build_variant asan address address
build_variant ubsan undefined undefined
echo 'Stage gameplay-camera packet V7 strict/ASan/UBSan validation: PASS'
