#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${1:-${GOLDENEYE_NATIVE_CAST_ASSET_ROOT:-${ROOT}/build/native/cast-frontend-v6-image-decoder-v6-fullweapons}}"
BUILD_ROOT="${ROOT}/build/native/cast-texture-setup-v6"
MODULE_CACHE="${BUILD_ROOT}/module-cache"
mkdir -p "${BUILD_ROOT}" "${MODULE_CACHE}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE}" "${SWIFTC}" \
    -swift-version 6 -warnings-as-errors -O \
    -target arm64-apple-macosx27.0 -sdk "${SDKROOT}" \
    "${ROOT}/native/host/goldeneye_source_frontend_catalog_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_model_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_texture_setup_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_2d_v6.swift" \
    "${ROOT}/native/host/goldeneye_file_mode_background_v6.swift" \
    "${ROOT}/native/tests/goldeneye_cast_texture_setup_v6_smoke.swift" \
    -o "${BUILD_ROOT}/goldeneye_cast_texture_setup_v6_smoke"

for model in oliveguard natalya; do
    "${BUILD_ROOT}/goldeneye_cast_texture_setup_v6_smoke" "${ASSET_ROOT}" "${model}"
done
echo 'test_cast_texture_setup_v6: PASS'
