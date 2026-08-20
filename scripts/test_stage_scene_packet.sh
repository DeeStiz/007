#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${1:-${GOLDENEYE_NATIVE_STAGE_ASSET_ROOT:-${PROJECT_ROOT}/build/native/stage-assets-image-decoder-v6}}"
BUILD_DIR="${PROJECT_ROOT}/build/native/stage-scene-packet"
MODULE_CACHE_DIR="${BUILD_DIR}/module-cache"
mkdir -p "${BUILD_DIR}" "${MODULE_CACHE_DIR}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun --sdk macosx --find clang)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
COMMON_CFLAGS=(-target arm64-apple-macosx27.0 -isysroot "${SDKROOT}" -std=c11 -Wall -Wextra -Werror -pedantic -O2 -I "${PROJECT_ROOT}/native/include")
SWIFT_ARGS=(-swift-version 6 -warnings-as-errors -target arm64-apple-macosx27.0 -sdk "${SDKROOT}")

"${CC}" "${COMMON_CFLAGS[@]}" -c "${PROJECT_ROOT}/native/src/ge_stage_v5.c" -o "${BUILD_DIR}/ge_stage_v5.o"
"${CC}" "${COMMON_CFLAGS[@]}" -c "${PROJECT_ROOT}/native/src/ge_stage_background_v5.c" -o "${BUILD_DIR}/ge_stage_background_v5.o"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${SWIFTC}" "${SWIFT_ARGS[@]}" \
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_native_bridging.h" \
    -Xcc "-I${PROJECT_ROOT}/native/include" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_asset_catalog.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_setup_packet.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_scene_packet.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_stage_scene_packet_smoke.swift" \
    "${BUILD_DIR}/ge_stage_v5.o" "${BUILD_DIR}/ge_stage_background_v5.o" \
    -o "${BUILD_DIR}/goldeneye_stage_scene_packet_smoke"

"${BUILD_DIR}/goldeneye_stage_scene_packet_smoke" "${ASSET_ROOT}" | tee "${BUILD_DIR}/stage-scene-packet.log"
grep -Fq 'goldeneye_stage_scene_packet_smoke: PASS stages=7' "${BUILD_DIR}/stage-scene-packet.log"
echo 'Stage scene packet validation: PASS'
