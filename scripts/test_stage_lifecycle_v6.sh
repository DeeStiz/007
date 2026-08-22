#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${1:-${GOLDENEYE_NATIVE_STAGE_ASSET_ROOT:-${ROOT}/build/native/stage-assets-image-decoder-v6}}"
BUILD_ROOT="${ROOT}/build/native/stage-lifecycle-v6"
MODULE_CACHE="${BUILD_ROOT}/module-cache"
mkdir -p "${BUILD_ROOT}" "${MODULE_CACHE}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun --sdk macosx --find clang)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
CFLAGS=(
    -target arm64-apple-macosx27.0 -isysroot "${SDKROOT}"
    -std=c11 -Wall -Wextra -Werror -pedantic -O2
    -I "${ROOT}/native/include"
)
SWIFT_ARGS=(
    -swift-version 6 -warnings-as-errors
    -target arm64-apple-macosx27.0 -sdk "${SDKROOT}"
)

build_and_run() {
    local suffix="$1"
    shift
    local sanitizer="$1"
    shift
    local object="${BUILD_ROOT}/ge_stage_v5${suffix}.o"
    local binary="${BUILD_ROOT}/goldeneye_stage_lifecycle_v6_smoke${suffix}"
    local log="${BUILD_ROOT}/lifecycle${suffix}.log"
    local -a extra_cflags=()
    local -a extra_swift=()
    local -a run_env=()
    if [[ -n "${sanitizer}" ]]; then
        extra_cflags+=("-fsanitize=${sanitizer}" -O1 -fno-omit-frame-pointer)
        extra_swift+=("-sanitize=${sanitizer}")
        if [[ "${sanitizer}" == "address" ]]; then
            run_env+=("ASAN_OPTIONS=halt_on_error=1:detect_leaks=0")
        else
            run_env+=("UBSAN_OPTIONS=halt_on_error=1")
        fi
    fi
    "${CC}" "${CFLAGS[@]}" "${extra_cflags[@]-}" -c \
        "${ROOT}/native/src/ge_stage_v5.c" -o "${object}"
    CLANG_MODULE_CACHE_PATH="${MODULE_CACHE}" "${SWIFTC}" \
        "${SWIFT_ARGS[@]}" "${extra_swift[@]-}" \
        -import-objc-header "${ROOT}/native/tests/goldeneye_native_bridging.h" \
        -Xcc "-I${ROOT}/native/include" \
        "${ROOT}/native/host/goldeneye_stage_asset_catalog.swift" \
        "${ROOT}/native/host/goldeneye_stage_resource_loader.swift" \
        "${ROOT}/native/host/goldeneye_stage_lifecycle_v6.swift" \
        "${ROOT}/native/tests/goldeneye_stage_lifecycle_v6_smoke.swift" \
        "${object}" -o "${binary}"
    if [[ -n "${sanitizer}" ]]; then
        env "${run_env[@]}" "${binary}" "${ASSET_ROOT}" | tee "${log}"
    else
        "${binary}" "${ASSET_ROOT}" | tee "${log}"
    fi
    grep -Fq 'goldeneye_stage_lifecycle_v6_smoke: PASS stages=7' "${log}"
}

build_and_run "" ""
build_and_run "-asan" "address"
build_and_run "-ubsan" "undefined"
echo "Stage lifecycle V6 strict/ASan/UBSan validation: PASS"
