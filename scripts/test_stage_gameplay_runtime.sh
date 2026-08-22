#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${1:-${GOLDENEYE_NATIVE_STAGE_ASSET_ROOT:-${PROJECT_ROOT}/build/native/stage-assets-image-decoder-v6}}"
BOOT_ASSET_ROOT="${GOLDENEYE_NATIVE_ASSET_ROOT:-${PROJECT_ROOT}/build/native/boot-assets}"
BUILD_DIR="${PROJECT_ROOT}/build/native/stage-gameplay-runtime"
MODULE_CACHE_DIR="${BUILD_DIR}/module-cache"
mkdir -p "${BUILD_DIR}" "${MODULE_CACHE_DIR}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun --sdk macosx --find clang)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
COMMON_CFLAGS=(
    -target arm64-apple-macosx27.0 -isysroot "${SDKROOT}"
    -std=c11 -Wall -Wextra -Werror -pedantic -O2
    -I "${PROJECT_ROOT}/native/include"
)
SWIFT_ARGS=(
    -swift-version 6 -warnings-as-errors
    -target arm64-apple-macosx27.0 -sdk "${SDKROOT}"
)

C_SOURCES=(
    "${PROJECT_ROOT}/native/src/ge_stage_v5.c"
    "${PROJECT_ROOT}/native/src/ge_stage_background_v5.c"
    "${PROJECT_ROOT}/native/src/ge_ramrom_v5.c"
    "${PROJECT_ROOT}/native/src/ge_ramrom_playback_v5.c"
    "${PROJECT_ROOT}/native/src/ge_native_runtime_v5.c"
    "${PROJECT_ROOT}/native/src/ge_audio_v5.c"
)
OBJECTS=()
for source in "${C_SOURCES[@]}"; do
    object="${BUILD_DIR}/$(basename "${source}" .c).o"
    "${CC}" "${COMMON_CFLAGS[@]}" -c "${source}" -o "${object}"
    OBJECTS+=("${object}")
done

echo "Building strict bounded native stage gameplay runtime smoke"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${SWIFTC}" "${SWIFT_ARGS[@]}" \
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_stage_gameplay_runtime_bridging.h" \
    -Xcc "-I${PROJECT_ROOT}/native/include" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_asset_catalog.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_payload_store_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_transfer_queue_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_setup_packet.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_scene_packet.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_gameplay_runtime.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_attract_route.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_cast_title_hash.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_ramrom_playback_service.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_ramrom_playback_service_hash.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_stage_gameplay_runtime_smoke.swift" \
    "${OBJECTS[@]}" \
    -o "${BUILD_DIR}/goldeneye_stage_gameplay_runtime_smoke"

"${BUILD_DIR}/goldeneye_stage_gameplay_runtime_smoke" "${ASSET_ROOT}" "${BOOT_ASSET_ROOT}" \
    | tee "${BUILD_DIR}/stage-gameplay-runtime.log"
grep -Fq 'goldeneye_stage_gameplay_runtime_smoke: PASS stages=7 trace=1' \
    "${BUILD_DIR}/stage-gameplay-runtime.log"

echo "Building ASan bounded native stage gameplay runtime smoke"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${SWIFTC}" "${SWIFT_ARGS[@]}" \
    -sanitize=address \
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_stage_gameplay_runtime_bridging.h" \
    -Xcc "-I${PROJECT_ROOT}/native/include" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_asset_catalog.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_payload_store_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_transfer_queue_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_setup_packet.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_scene_packet.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_gameplay_runtime.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_attract_route.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_cast_title_hash.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_ramrom_playback_service.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_ramrom_playback_service_hash.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_stage_gameplay_runtime_smoke.swift" \
    "${OBJECTS[@]}" \
    -o "${BUILD_DIR}/goldeneye_stage_gameplay_runtime_smoke_asan"
ASAN_OPTIONS=halt_on_error=1:detect_leaks=0 \
    "${BUILD_DIR}/goldeneye_stage_gameplay_runtime_smoke_asan" "${ASSET_ROOT}" "${BOOT_ASSET_ROOT}" \
    | tee "${BUILD_DIR}/stage-gameplay-runtime-asan.log"
grep -Fq 'goldeneye_stage_gameplay_runtime_smoke: PASS stages=7 trace=1' \
    "${BUILD_DIR}/stage-gameplay-runtime-asan.log"

echo "Building UBSan bounded native stage gameplay runtime smoke"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${SWIFTC}" "${SWIFT_ARGS[@]}" \
    -sanitize=undefined \
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_stage_gameplay_runtime_bridging.h" \
    -Xcc "-I${PROJECT_ROOT}/native/include" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_asset_catalog.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_payload_store_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_transfer_queue_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_setup_packet.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_scene_packet.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_gameplay_runtime.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_attract_route.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_cast_title_hash.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_ramrom_playback_service.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_ramrom_playback_service_hash.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_stage_gameplay_runtime_smoke.swift" \
    "${OBJECTS[@]}" \
    -o "${BUILD_DIR}/goldeneye_stage_gameplay_runtime_smoke_ubsan"
UBSAN_OPTIONS=halt_on_error=1 \
    "${BUILD_DIR}/goldeneye_stage_gameplay_runtime_smoke_ubsan" "${ASSET_ROOT}" "${BOOT_ASSET_ROOT}" \
    | tee "${BUILD_DIR}/stage-gameplay-runtime-ubsan.log"
grep -Fq 'goldeneye_stage_gameplay_runtime_smoke: PASS stages=7 trace=1' \
    "${BUILD_DIR}/stage-gameplay-runtime-ubsan.log"

git -C "${PROJECT_ROOT}" diff --check
echo "Native stage gameplay runtime validation: PASS"
