#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${GOLDENEYE_NATIVE_CAST_ASSET_ROOT:-${ROOT}/build/native/cast-frontend-v6-image-decoder-v6-fullweapons}"
SIDECAR="${GOLDENEYE_NATIVE_GUNBARREL_SIDECAR:-${ROOT}/build/native/gunbarrel-v6-prepared/gunbarrel.gbar}"
BUILD_ROOT="${GE_CAST_ATTACHMENT_BUILD_ROOT:-${ROOT}/build/native/cast-attachment-v6}"
MODULE_CACHE="${BUILD_ROOT}/module-cache"
mkdir -p "${BUILD_ROOT}" "${MODULE_CACHE}"
export CLANG_MODULE_CACHE_PATH="${MODULE_CACHE}"

SANITIZER="${GE_CAST_ATTACHMENT_SANITIZER:-}"
SWIFT_FLAGS=(-swift-version 6 -warnings-as-errors -O)
case "${SANITIZER}" in
    "") ;;
    address|undefined)
        SWIFT_FLAGS+=(-sanitize="${SANITIZER}")
        ;;
    *)
        echo "unsupported GE_CAST_ATTACHMENT_SANITIZER=${SANITIZER}" >&2
        exit 2
        ;;
esac

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun --sdk macosx --find clang)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
CFLAGS=(
    -target arm64-apple-macosx27.0 -isysroot "${SDKROOT}"
    -std=c11 -Wall -Wextra -Werror -Wno-c23-extensions -pedantic -O2
    -I "${ROOT}/native/include"
)

if [[ -n "${SANITIZER}" ]]; then
    CFLAGS+=("-fsanitize=${SANITIZER}")
fi

"${CC}" "${CFLAGS[@]}" -c "${ROOT}/native/src/ge_source_scene_v6.c" \
    -o "${BUILD_ROOT}/ge_source_scene_v6.o"

"${SWIFTC}" "${SWIFT_FLAGS[@]}" \
    -target arm64-apple-macosx27.0 -sdk "${SDKROOT}" \
    -import-objc-header "${ROOT}/native/tests/goldeneye_native_bridging.h" \
    -Xcc "-I${ROOT}/native/include" \
    -Xcc -include -Xcc "${ROOT}/native/include/ge_source_scene_v6.h" \
    "${ROOT}/native/host/goldeneye_source_model_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_product_contract_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_projection_binding_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_frontend_catalog_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_texture_setup_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_node_transform_v6.swift" \
    "${ROOT}/native/host/goldeneye_cast_skeleton_transform_v6.swift" \
    "${ROOT}/native/host/title_geometry_packet.swift" \
    "${ROOT}/native/host/goldeneye_gunbarrel_v6.swift" \
    "${ROOT}/native/tests/goldeneye_cast_attachment_v6_smoke.swift" \
    "${BUILD_ROOT}/ge_source_scene_v6.o" \
    -o "${BUILD_ROOT}/goldeneye_cast_attachment_v6_smoke"

"${BUILD_ROOT}/goldeneye_cast_attachment_v6_smoke" "${ASSET_ROOT}" "${SIDECAR}" \
    | tee "${BUILD_ROOT}/strict.log"
grep -Fq 'goldeneye_cast_attachment_v6_smoke: PASS' "${BUILD_ROOT}/strict.log"
echo "test_cast_attachment_v6: PASS evidence=${BUILD_ROOT}"
