#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${1:-${PROJECT_ROOT}/build/native/source-frontend-v6}"
BUILD_ROOT="${PROJECT_ROOT}/build/native/file-mode-background-v6"
mkdir -p "${BUILD_ROOT}/module-cache"
export CLANG_MODULE_CACHE_PATH="${BUILD_ROOT}/module-cache"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
"${SWIFTC}" -swift-version 6 -warnings-as-errors -O -parse-as-library \
    -target arm64-apple-macosx27.0 -sdk "${SDKROOT}" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_catalog_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_file_mode_background_v6.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_file_mode_background_v6_smoke.swift" \
    -o "${BUILD_ROOT}/smoke"

"${BUILD_ROOT}/smoke" "${ASSET_ROOT}" | tee "${BUILD_ROOT}/strict.log"
grep -Fq 'goldeneye_file_mode_background_v6_smoke: PASS' "${BUILD_ROOT}/strict.log"
echo 'Source File/Mode background contract validation: PASS'
