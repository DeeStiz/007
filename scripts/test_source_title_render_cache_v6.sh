#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="${PROJECT_ROOT}/build/native/source-title-render-cache-v6"
STRICT_DIR="${BUILD_DIR}/strict"
SANITIZER_DIR="${BUILD_DIR}/sanitizers"
mkdir -p "${STRICT_DIR}" "${SANITIZER_DIR}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun --sdk macosx --find clang)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
ASSET_ROOT="${1:-${PROJECT_ROOT}/build/native/source-frontend-v6}"

CFLAGS=(-target arm64-apple-macosx27.0 -isysroot "${SDKROOT}" -std=c11
    -Wall -Wextra -Werror -Wno-c23-extensions -pedantic
    -I "${PROJECT_ROOT}/native/include" -I "${PROJECT_ROOT}/native/source_port")
SWIFT_FLAGS=(-swift-version 6 -warnings-as-errors -target arm64-apple-macosx27.0
    -sdk "${SDKROOT}" -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_native_bridging.h"
    -Xcc "-I${PROJECT_ROOT}/native/include" -Xcc -include
    -Xcc "${PROJECT_ROOT}/native/include/ge_source_gbi_v6.h" -Xcc -include
    -Xcc "${PROJECT_ROOT}/native/include/ge_source_scene_v6.h" -Xcc -include
    -Xcc "${PROJECT_ROOT}/native/include/ge_source_texture_coordinates_v6.h")

build_c() {
    local out="$1"
    local mode="${2:-strict}"
    local sanitizer=()
    if [[ "${mode}" == sanitizer ]]; then
        sanitizer=(-fsanitize=address,undefined -fno-omit-frame-pointer)
    fi
    for source in ge_source_gbi_v6.c ge_source_scene_v6.c \
        ge_source_frontend_runtime_v6.c ge_source_texture_coordinates_v6.c \
        ge_file_mode_v6.c; do
        "${CC}" "${CFLAGS[@]}" "${sanitizer[@]-}" -O2 -c \
            "${PROJECT_ROOT}/native/src/${source}" -o "${out}/${source%.c}.o"
    done
    "${CC}" "${CFLAGS[@]}" "${sanitizer[@]-}" -O2 -c \
        "${PROJECT_ROOT}/native/source_port/ge_source_frontend_v6.c" \
        -o "${out}/ge_source_frontend_v6.o"
}

build_swift() {
    local out="$1"
    local mode="${2:-strict}"
    local sanitizer=()
    if [[ "${mode}" == sanitizer ]]; then sanitizer=(-sanitize=address,undefined); fi
    local optimization="-O"
    if [[ "${mode}" == sanitizer ]]; then optimization="-Onone"; fi
    "${SWIFTC}" "${SWIFT_FLAGS[@]}" "${optimization}" "${sanitizer[@]-}" \
        "${PROJECT_ROOT}/native/host/goldeneye_source_model_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_authority_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_file_mode_authority_v6.swift" \
        "${PROJECT_ROOT}/native/host/save_store.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_matrices_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_presentation_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_catalog_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_source_product_contract_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_source_product_preparation_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_source_product_provider_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_source_scene_snapshot_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_source_projection_binding_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_source_texture_coordinates_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_source_texture_setup_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_source_node_transform_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_gbi_scene_builder_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_source_scene_composer_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_goldeneye_logo_frame_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_source_title_render_cache_v6.swift" \
        "${PROJECT_ROOT}/native/tests/goldeneye_source_title_render_cache_v6_smoke.swift" \
        "${out}/ge_source_gbi_v6.o" "${out}/ge_source_scene_v6.o" \
        "${out}/ge_source_frontend_runtime_v6.o" "${out}/ge_source_texture_coordinates_v6.o" \
        "${out}/ge_file_mode_v6.o" "${out}/ge_source_frontend_v6.o" \
        -o "${out}/goldeneye_source_title_render_cache_v6_smoke"
}

build_c "${STRICT_DIR}"
build_swift "${STRICT_DIR}"
GE_CACHE_PERF_CHECK=1 "${STRICT_DIR}/goldeneye_source_title_render_cache_v6_smoke" "${ASSET_ROOT}" \
    | tee "${STRICT_DIR}/source-title-render-cache-v6.log"
grep -Fq 'goldeneye-source-title-render-cache-v6:' "${STRICT_DIR}/source-title-render-cache-v6.log"

build_c "${SANITIZER_DIR}" sanitizer
build_swift "${SANITIZER_DIR}" sanitizer
ASAN_OPTIONS=halt_on_error=1 "${SANITIZER_DIR}/goldeneye_source_title_render_cache_v6_smoke" "${ASSET_ROOT}" \
    | tee "${SANITIZER_DIR}/source-title-render-cache-v6.log"
grep -Fq 'goldeneye-source-title-render-cache-v6:' "${SANITIZER_DIR}/source-title-render-cache-v6.log"

git -C "${PROJECT_ROOT}" diff --check -- \
    native/host/goldeneye_source_product_renderer_v6.swift \
    native/host/goldeneye_source_title_render_cache_v6.swift \
    native/tests/goldeneye_source_title_render_cache_v6_smoke.swift \
    scripts/test_source_title_render_cache_v6.sh

echo 'Source title render cache V6 validation: PASS (strict, ASan, UBSan)'
echo "Artifact: ${STRICT_DIR}/source-title-render-cache-v6.log"
