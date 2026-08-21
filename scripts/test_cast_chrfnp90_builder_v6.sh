#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${GOLDENEYE_NATIVE_CAST_ASSET_ROOT:-${ROOT}/build/native/cast-frontend-v6-image-decoder-v6-fullweapons}"
BUILD_ROOT="${GE_CAST_CHRFNP90_BUILD_ROOT:-${ROOT}/build/native/cast-chrfnp90-builder-v6}"
MODULE_CACHE="${BUILD_ROOT}/module-cache"
mkdir -p "${BUILD_ROOT}" "${MODULE_CACHE}"
export CLANG_MODULE_CACHE_PATH="${MODULE_CACHE}"

SANITIZER="${GE_CAST_CHRFNP90_SANITIZER:-}"
SWIFT_FLAGS=(-swift-version 6 -warnings-as-errors -O)
case "${SANITIZER}" in
    "") ;;
    address|undefined)
        SWIFT_FLAGS+=(-sanitize="${SANITIZER}")
        ;;
    *)
        echo "unsupported GE_CAST_CHRFNP90_SANITIZER=${SANITIZER}" >&2
        exit 2
        ;;
esac

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun --sdk macosx --find clang)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
CFLAGS=(
    -target arm64-apple-macosx27.0 -isysroot "${SDKROOT}" -std=c11
    -Wall -Wextra -Werror -Wno-c23-extensions -pedantic -O2
    -I "${ROOT}/native/include"
)
if [[ -n "${SANITIZER}" ]]; then
    CFLAGS+=("-fsanitize=${SANITIZER}")
fi
for source in ge_source_gbi_v6.c ge_source_scene_v6.c ge_source_frontend_runtime_v6.c \
    ge_source_texture_coordinates_v6.c ge_file_mode_v6.c; do
    extra=(-I "${ROOT}/native/source_port")
    "${CC}" "${CFLAGS[@]}" "${extra[@]}" -c "${ROOT}/native/src/${source}" \
        -o "${BUILD_ROOT}/${source%.c}.o"
done
"${CC}" "${CFLAGS[@]}" -I "${ROOT}/native/source_port" -c \
    "${ROOT}/native/source_port/ge_source_frontend_v6.c" \
    -o "${BUILD_ROOT}/ge_source_frontend_v6.o"

"${SWIFTC}" "${SWIFT_FLAGS[@]}" \
    -target arm64-apple-macosx27.0 -sdk "${SDKROOT}" \
    -import-objc-header "${ROOT}/native/tests/goldeneye_native_bridging.h" \
    -Xcc "-I${ROOT}/native/include" \
    -Xcc -include -Xcc "${ROOT}/native/include/ge_source_gbi_v6.h" \
    -Xcc -include -Xcc "${ROOT}/native/include/ge_source_scene_v6.h" \
    -Xcc -include -Xcc "${ROOT}/native/include/ge_source_texture_coordinates_v6.h" \
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
    "${ROOT}/native/host/goldeneye_gbi_scene_builder_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_node_transform_v6.swift" \
    "${ROOT}/native/tests/goldeneye_cast_chrfnp90_builder_v6_smoke.swift" \
    "${BUILD_ROOT}/ge_source_gbi_v6.o" "${BUILD_ROOT}/ge_source_scene_v6.o" \
    "${BUILD_ROOT}/ge_source_frontend_runtime_v6.o" "${BUILD_ROOT}/ge_source_texture_coordinates_v6.o" \
    "${BUILD_ROOT}/ge_file_mode_v6.o" "${BUILD_ROOT}/ge_source_frontend_v6.o" \
    -o "${BUILD_ROOT}/goldeneye_cast_chrfnp90_builder_v6_smoke"

"${BUILD_ROOT}/goldeneye_cast_chrfnp90_builder_v6_smoke" "${ASSET_ROOT}" \
    | tee "${BUILD_ROOT}/strict.log"
grep -Fq 'goldeneye_cast_chrfnp90_builder_v6_smoke: PASS' "${BUILD_ROOT}/strict.log"
echo "test_cast_chrfnp90_builder_v6: PASS evidence=${BUILD_ROOT}"
