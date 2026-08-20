#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${1:-${PROJECT_ROOT}/build/native/source-frontend-v6}"
BUILD_ROOT="${PROJECT_ROOT}/build/native/file-mode-reference-capture-v6"
mkdir -p "${BUILD_ROOT}/module-cache"
export CLANG_MODULE_CACHE_PATH="${BUILD_ROOT}/module-cache"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun --sdk macosx --find clang)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
CFLAGS=(
    -std=c11 -Wall -Wextra -Werror -Wno-c23-extensions -pedantic
    -target arm64-apple-macosx27.0 -isysroot "${SDKROOT}"
    -I "${PROJECT_ROOT}/native/include" -I "${PROJECT_ROOT}/native/source_port"
)
"${CC}" "${CFLAGS[@]}" -O2 -c \
    "${PROJECT_ROOT}/native/src/ge_file_mode_v6.c" \
    -o "${BUILD_ROOT}/ge_file_mode_v6.o"

"${SWIFTC}" -swift-version 6 -warnings-as-errors -Onone -parse-as-library \
    -target arm64-apple-macosx27.0 -sdk "${SDKROOT}" \
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_native_bridging.h" \
    -Xcc -I -Xcc "${PROJECT_ROOT}/native/include" \
    "${PROJECT_ROOT}/native/host/goldeneye_fidelity_policy.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_catalog_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_model_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_setup_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_wallet_switch_text_v6.swift" \
    "${PROJECT_ROOT}/native/host/save_store.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_file_mode_authority_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_2d_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_2d_file_mode_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_file_mode_background_v6.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_file_mode_reference_capture_v6_smoke.swift" \
    "${BUILD_ROOT}/ge_file_mode_v6.o" \
    -o "${BUILD_ROOT}/smoke"

"${BUILD_ROOT}/smoke" "${ASSET_ROOT}" | tee "${BUILD_ROOT}/strict.log"
grep -Fq 'goldeneye_file_mode_reference_capture_v6_smoke: PASS' "${BUILD_ROOT}/strict.log"
grep -Fq 'unsupported=0' "${BUILD_ROOT}/strict.log"

echo 'Source File/Mode visual-frame and route coverage validation: PASS (GPU capture remains an explicit Metal4 follow-up)'
echo "Artifact: ${BUILD_ROOT}/strict.log"
