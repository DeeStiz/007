#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${ROOT}/build/native/source-frontend-v6"
SIDECAR="${ROOT}/build/native/gunbarrel-v6-prepared/gunbarrel.gbar"
BUILD_ROOT="${ROOT}/build/native/gunbarrel-dynamic-builder-v6"
mkdir -p "${BUILD_ROOT}"

python3 "${SCRIPT_DIR}/prepare_native_gunbarrel_v6.py" \
    --project-root "${ROOT}" \
    --output "${SIDECAR}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
CC=$(xcrun --sdk macosx --find clang)
STRICT_DIR="${BUILD_ROOT}/c"
mkdir -p "${STRICT_DIR}"
COMMON_CFLAGS=(-target arm64-apple-macosx27.0 -isysroot "${SDKROOT}" -std=c11
    -Wall -Wextra -Werror -Wno-c23-extensions -pedantic
    -I "${ROOT}/native/include")
"${CC}" "${COMMON_CFLAGS[@]}" -O2 -c "${ROOT}/native/src/ge_source_gbi_v6.c" -o "${STRICT_DIR}/ge_source_gbi_v6.o"
"${CC}" "${COMMON_CFLAGS[@]}" -O2 -c "${ROOT}/native/src/ge_source_scene_v6.c" -o "${STRICT_DIR}/ge_source_scene_v6.o"
"${CC}" "${COMMON_CFLAGS[@]}" -I "${ROOT}/native/source_port" -O2 -c "${ROOT}/native/src/ge_source_frontend_runtime_v6.c" -o "${STRICT_DIR}/ge_source_frontend_runtime_v6.o"
"${CC}" "${COMMON_CFLAGS[@]}" -I "${ROOT}/native/source_port" -O2 -c "${ROOT}/native/source_port/ge_source_frontend_v6.c" -o "${STRICT_DIR}/ge_source_frontend_v6.o"
"${CC}" "${COMMON_CFLAGS[@]}" -O2 -c "${ROOT}/native/src/ge_file_mode_v6.c" -o "${STRICT_DIR}/ge_file_mode_v6.o"
"${CC}" "${COMMON_CFLAGS[@]}" -O2 -c "${ROOT}/native/src/ge_source_texture_coordinates_v6.c" -o "${STRICT_DIR}/ge_source_texture_coordinates_v6.o"
SWIFT_COMMON=(
    -swift-version 6 -warnings-as-errors -target arm64-apple-macosx27.0
    -sdk "${SDKROOT}" -import-objc-header "${ROOT}/native/tests/goldeneye_native_bridging.h"
    -Xcc "-I${ROOT}/native/include" -Xcc -include -Xcc "${ROOT}/native/include/ge_source_gbi_v6.h"
    -Xcc -include -Xcc "${ROOT}/native/include/ge_source_scene_v6.h"
    -Xcc -include -Xcc "${ROOT}/native/include/ge_source_texture_coordinates_v6.h"
)

"${SWIFTC}" "${SWIFT_COMMON[@]}" -Onone \
    "${ROOT}/native/host/title_geometry_packet.swift" \
    "${ROOT}/native/host/goldeneye_source_model_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_product_contract_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_frontend_catalog_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_scene_snapshot_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_projection_binding_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_texture_coordinates_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_texture_store_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_scene_texture_binding_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_texture_setup_v6.swift" \
    "${ROOT}/native/host/goldeneye_gunbarrel_v6.swift" \
    "${ROOT}/native/host/goldeneye_gbi_scene_builder_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_node_transform_v6.swift" \
    "${ROOT}/native/tests/goldeneye_gunbarrel_dynamic_builder_v6_smoke.swift" \
    "${STRICT_DIR}/ge_source_gbi_v6.o" "${STRICT_DIR}/ge_source_scene_v6.o" \
    "${STRICT_DIR}/ge_source_frontend_runtime_v6.o" "${STRICT_DIR}/ge_source_frontend_v6.o" \
    "${STRICT_DIR}/ge_file_mode_v6.o" "${STRICT_DIR}/ge_source_texture_coordinates_v6.o" \
    -o "${BUILD_ROOT}/goldeneye_gunbarrel_dynamic_builder_v6_smoke"

"${BUILD_ROOT}/goldeneye_gunbarrel_dynamic_builder_v6_smoke" \
    "${ASSET_ROOT}" "${SIDECAR}" \
    | tee "${BUILD_ROOT}/dynamic-builder.log"
grep -Fq 'goldeneye_gunbarrel_dynamic_builder_v6_smoke: PASS' "${BUILD_ROOT}/dynamic-builder.log"
grep -Fq 'gunbarrel_builder_scene=suitbond:' "${BUILD_ROOT}/dynamic-builder.log"
grep -Fq 'gunbarrel_builder_scene=headbrosnansuit:' "${BUILD_ROOT}/dynamic-builder.log"
grep -Fq 'gunbarrel_builder_scene=chrwppk:' "${BUILD_ROOT}/dynamic-builder.log"

echo "test_gunbarrel_dynamic_builder_v6: PASS"
echo "evidence=${BUILD_ROOT}"
