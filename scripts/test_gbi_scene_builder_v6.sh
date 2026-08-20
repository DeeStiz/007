#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="${GOLDENEYE_GBI_SCENE_BUILDER_BUILD_DIR:-${PROJECT_ROOT}/build/native/gbi-scene-builder-v6}"
STRICT_DIR="${BUILD_DIR}/strict"
SANITIZER_DIR="${BUILD_DIR}/sanitizers"
mkdir -p "${STRICT_DIR}" "${SANITIZER_DIR}"

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

build_c() {
    local out="$1"
    local flags=()
    shift
    if [[ "${1:-}" == "sanitizer" ]]; then
        flags=(-fsanitize=address,undefined -fno-omit-frame-pointer)
        shift
    fi
    if ((${#flags[@]})); then
        "${CC}" "${COMMON_CFLAGS[@]}" "${flags[@]}" -O2 -c \
            "${PROJECT_ROOT}/native/src/ge_source_gbi_v6.c" \
            -o "${out}/ge_source_gbi_v6.o"
        "${CC}" "${COMMON_CFLAGS[@]}" "${flags[@]}" -O2 -c \
            "${PROJECT_ROOT}/native/src/ge_source_scene_v6.c" \
            -o "${out}/ge_source_scene_v6.o"
        "${CC}" "${COMMON_CFLAGS[@]}" "${flags[@]}" -I "${PROJECT_ROOT}/native/source_port" -O2 -c \
            "${PROJECT_ROOT}/native/src/ge_source_frontend_runtime_v6.c" \
            -o "${out}/ge_source_frontend_runtime_v6.o"
        "${CC}" "${COMMON_CFLAGS[@]}" "${flags[@]}" -I "${PROJECT_ROOT}/native/source_port" -O2 -c \
            "${PROJECT_ROOT}/native/source_port/ge_source_frontend_v6.c" \
            -o "${out}/ge_source_frontend_v6.o"
        "${CC}" "${COMMON_CFLAGS[@]}" "${flags[@]}" -O2 -c \
            "${PROJECT_ROOT}/native/src/ge_file_mode_v6.c" \
            -o "${out}/ge_file_mode_v6.o"
        "${CC}" "${COMMON_CFLAGS[@]}" "${flags[@]}" -O2 -c \
            "${PROJECT_ROOT}/native/src/ge_source_texture_coordinates_v6.c" \
            -o "${out}/ge_source_texture_coordinates_v6.o"
    else
        "${CC}" "${COMMON_CFLAGS[@]}" -O2 -c \
            "${PROJECT_ROOT}/native/src/ge_source_gbi_v6.c" \
            -o "${out}/ge_source_gbi_v6.o"
        "${CC}" "${COMMON_CFLAGS[@]}" -O2 -c \
            "${PROJECT_ROOT}/native/src/ge_source_scene_v6.c" \
            -o "${out}/ge_source_scene_v6.o"
        "${CC}" "${COMMON_CFLAGS[@]}" -I "${PROJECT_ROOT}/native/source_port" -O2 -c \
            "${PROJECT_ROOT}/native/src/ge_source_frontend_runtime_v6.c" \
            -o "${out}/ge_source_frontend_runtime_v6.o"
        "${CC}" "${COMMON_CFLAGS[@]}" -I "${PROJECT_ROOT}/native/source_port" -O2 -c \
            "${PROJECT_ROOT}/native/source_port/ge_source_frontend_v6.c" \
            -o "${out}/ge_source_frontend_v6.o"
        "${CC}" "${COMMON_CFLAGS[@]}" -O2 -c \
            "${PROJECT_ROOT}/native/src/ge_file_mode_v6.c" \
            -o "${out}/ge_file_mode_v6.o"
        "${CC}" "${COMMON_CFLAGS[@]}" -O2 -c \
            "${PROJECT_ROOT}/native/src/ge_source_texture_coordinates_v6.c" \
            -o "${out}/ge_source_texture_coordinates_v6.o"
    fi
}

build_c "${STRICT_DIR}"
"${SWIFTC}" "${SWIFT_COMMON[@]}" -Onone \
    "${PROJECT_ROOT}/native/host/goldeneye_source_model_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_catalog_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_authority_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_file_mode_authority_v6.swift" \
    "${PROJECT_ROOT}/native/host/save_store.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_product_contract_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_snapshot_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_projection_binding_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_coordinates_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_store_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_texture_binding_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_setup_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_gbi_scene_builder_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_node_transform_v6.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_gbi_scene_builder_v6_smoke.swift" \
    "${STRICT_DIR}/ge_source_gbi_v6.o" "${STRICT_DIR}/ge_source_scene_v6.o" \
    "${STRICT_DIR}/ge_source_frontend_runtime_v6.o" "${STRICT_DIR}/ge_source_frontend_v6.o" \
    "${STRICT_DIR}/ge_file_mode_v6.o" \
    "${STRICT_DIR}/ge_source_texture_coordinates_v6.o" \
    -o "${STRICT_DIR}/goldeneye_gbi_scene_builder_v6_smoke"

"${STRICT_DIR}/goldeneye_gbi_scene_builder_v6_smoke" \
    "${PROJECT_ROOT}/build/native/source-frontend-v6" \
    | tee "${STRICT_DIR}/gbi-scene-builder-v6.log"
grep -Fq 'goldeneye_gbi_scene_builder_v6_smoke: PASS' \
    "${STRICT_DIR}/gbi-scene-builder-v6.log"

build_c "${SANITIZER_DIR}" sanitizer
"${SWIFTC}" "${SWIFT_COMMON[@]}" -Onone -sanitize=address,undefined \
    "${PROJECT_ROOT}/native/host/goldeneye_source_model_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_catalog_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_authority_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_file_mode_authority_v6.swift" \
    "${PROJECT_ROOT}/native/host/save_store.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_product_contract_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_snapshot_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_projection_binding_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_coordinates_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_store_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_texture_binding_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_setup_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_gbi_scene_builder_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_node_transform_v6.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_gbi_scene_builder_v6_smoke.swift" \
    "${SANITIZER_DIR}/ge_source_gbi_v6.o" "${SANITIZER_DIR}/ge_source_scene_v6.o" \
    "${SANITIZER_DIR}/ge_source_frontend_runtime_v6.o" "${SANITIZER_DIR}/ge_source_frontend_v6.o" \
    "${SANITIZER_DIR}/ge_file_mode_v6.o" \
    "${SANITIZER_DIR}/ge_source_texture_coordinates_v6.o" \
    -o "${SANITIZER_DIR}/goldeneye_gbi_scene_builder_v6_smoke"

ASAN_OPTIONS=halt_on_error=1 \
    "${SANITIZER_DIR}/goldeneye_gbi_scene_builder_v6_smoke" \
    "${PROJECT_ROOT}/build/native/source-frontend-v6" \
    | tee "${SANITIZER_DIR}/gbi-scene-builder-v6.log"
grep -Fq 'goldeneye_gbi_scene_builder_v6_smoke: PASS' \
    "${SANITIZER_DIR}/gbi-scene-builder-v6.log"

git -C "${PROJECT_ROOT}" diff --check -- \
    native/host/goldeneye_gbi_scene_builder_v6.swift \
    native/host/goldeneye_source_projection_binding_v6.swift \
    native/tests/goldeneye_gbi_scene_builder_v6_smoke.swift \
    scripts/test_gbi_scene_builder_v6.sh

echo 'GBI scene builder V6 validation: PASS (strict, ASan, UBSan)'
echo "Artifact: ${STRICT_DIR}/gbi-scene-builder-v6.log"
