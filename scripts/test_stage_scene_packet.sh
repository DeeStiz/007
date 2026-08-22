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

build_and_run() {
    local suffix="$1"
    local sanitizer="$2"
    local stage_object="${BUILD_DIR}/ge_stage_v5${suffix}.o"
    local background_object="${BUILD_DIR}/ge_stage_background_v5${suffix}.o"
    local binary="${BUILD_DIR}/goldeneye_stage_scene_packet_smoke${suffix}"
    local log="${BUILD_DIR}/stage-scene-packet${suffix}.log"
    local -a cflags=("${COMMON_CFLAGS[@]}")
    local -a swift=("${SWIFT_ARGS[@]}")
    local -a run_env=()
    if [[ -n "${sanitizer}" ]]; then
        cflags+=("-fsanitize=${sanitizer}" -O1 -fno-omit-frame-pointer)
        swift+=("-sanitize=${sanitizer}")
        if [[ "${sanitizer}" == "address" ]]; then
            run_env+=("ASAN_OPTIONS=halt_on_error=1:detect_leaks=0")
        else
            run_env+=("UBSAN_OPTIONS=halt_on_error=1")
        fi
    fi
    "${CC}" "${cflags[@]}" -c "${PROJECT_ROOT}/native/src/ge_stage_v5.c" -o "${stage_object}"
    "${CC}" "${cflags[@]}" -c "${PROJECT_ROOT}/native/src/ge_stage_background_v5.c" -o "${background_object}"
    CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${SWIFTC}" "${swift[@]}" \
        -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_native_bridging.h" \
        -Xcc "-I${PROJECT_ROOT}/native/include" \
        "${PROJECT_ROOT}/native/host/goldeneye_stage_asset_catalog.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_stage_payload_store_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_stage_transfer_queue_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_stage_setup_packet.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_stage_scene_packet.swift" \
        "${PROJECT_ROOT}/native/tests/goldeneye_stage_scene_packet_smoke.swift" \
        "${stage_object}" "${background_object}" \
        -o "${binary}"
    if [[ -n "${sanitizer}" ]]; then
        env "${run_env[@]}" "${binary}" "${ASSET_ROOT}" | tee "${log}"
    else
        "${binary}" "${ASSET_ROOT}" | tee "${log}"
    fi
    grep -Fq 'goldeneye_stage_scene_packet_smoke: PASS stages=7' "${log}"
    grep -Fq 'chunked=1' "${log}"
}

build_and_run "" ""
build_and_run "-asan" "address"
build_and_run "-ubsan" "undefined"
echo 'Stage scene packet strict/ASan/UBSan validation: PASS'
