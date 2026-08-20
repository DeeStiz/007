#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="${PROJECT_ROOT}/build/native/source-projection-consumption-v6"
STRICT_DIR="${BUILD_DIR}/strict"
mkdir -p "${STRICT_DIR}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun --sdk macosx --find clang)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
CFLAGS=(-target arm64-apple-macosx27.0 -isysroot "${SDKROOT}" -std=c11
    -Wall -Wextra -Werror -Wno-c23-extensions -pedantic
    -I "${PROJECT_ROOT}/native/include")
SWIFTFLAGS=(-swift-version 6 -warnings-as-errors -target arm64-apple-macosx27.0
    -sdk "${SDKROOT}" -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_native_bridging.h"
    -Xcc "-I${PROJECT_ROOT}/native/include" -Xcc -include
    -Xcc "${PROJECT_ROOT}/native/include/ge_source_scene_v6.h")
SWIFTFLAGS+=(
    -Xcc -include
    -Xcc "${PROJECT_ROOT}/native/include/ge_source_texture_coordinates_v6.h"
)

"${CC}" "${CFLAGS[@]}" -O2 -c \
    "${PROJECT_ROOT}/native/src/ge_source_scene_v6.c" \
    -o "${STRICT_DIR}/ge_source_scene_v6.o"
"${CC}" "${CFLAGS[@]}" -O2 -c \
    "${PROJECT_ROOT}/native/src/ge_source_gbi_v6.c" \
    -o "${STRICT_DIR}/ge_source_gbi_v6.o"
"${CC}" "${CFLAGS[@]}" -O2 -c \
    "${PROJECT_ROOT}/native/src/ge_source_frontend_runtime_v6.c" \
    -o "${STRICT_DIR}/ge_source_frontend_runtime_v6.o"
"${CC}" "${CFLAGS[@]}" -O2 -c \
    "${PROJECT_ROOT}/native/source_port/ge_source_frontend_v6.c" \
    -o "${STRICT_DIR}/ge_source_frontend_v6.o"
"${CC}" "${CFLAGS[@]}" -O2 -c \
    "${PROJECT_ROOT}/native/src/ge_file_mode_v6.c" \
    -o "${STRICT_DIR}/ge_file_mode_v6.o"
"${CC}" "${CFLAGS[@]}" -O2 -c \
    "${PROJECT_ROOT}/native/src/ge_source_texture_coordinates_v6.c" \
    -o "${STRICT_DIR}/ge_source_texture_coordinates_v6.o"

"${SWIFTC}" "${SWIFTFLAGS[@]}" -O \
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_catalog_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_model_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_product_contract_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_product_preparation_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_product_provider_v6.swift" \
    "${PROJECT_ROOT}/native/host/save_store.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_file_mode_authority_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_authority_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_matrices_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_snapshot_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_projection_binding_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_coordinates_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_store_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_scene_texture_binding_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_setup_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_gbi_scene_builder_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_node_transform_v6.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_source_projection_consumption_v6_smoke.swift" \
    "${STRICT_DIR}/ge_source_scene_v6.o" \
    "${STRICT_DIR}/ge_source_gbi_v6.o" \
    "${STRICT_DIR}/ge_source_frontend_runtime_v6.o" \
    "${STRICT_DIR}/ge_source_frontend_v6.o" \
    "${STRICT_DIR}/ge_file_mode_v6.o" \
    "${STRICT_DIR}/ge_source_texture_coordinates_v6.o" \
    -o "${STRICT_DIR}/goldeneye_source_projection_consumption_v6_smoke"

"${STRICT_DIR}/goldeneye_source_projection_consumption_v6_smoke" \
    "${PROJECT_ROOT}/build/native/source-frontend-v6" \
    | tee "${STRICT_DIR}/source-projection-consumption-v6.log"
grep -Fq 'goldeneye_source_projection_consumption_v6_smoke: PASS' \
    "${STRICT_DIR}/source-projection-consumption-v6.log"

git -C "${PROJECT_ROOT}" diff --check -- \
    native/host/goldeneye_gbi_scene_builder_v6.swift \
    native/host/goldeneye_source_projection_binding_v6.swift \
    native/host/goldeneye_source_product_contract_v6.swift \
    native/host/goldeneye_source_product_renderer_v6.swift \
    native/tests/goldeneye_source_projection_consumption_v6_smoke.swift \
    scripts/test_source_projection_consumption_v6.sh

echo 'Source projection-consumption V6 validation: PASS (explicit roles and per-draw clip binding)'
echo "Artifact: ${STRICT_DIR}/source-projection-consumption-v6.log"
