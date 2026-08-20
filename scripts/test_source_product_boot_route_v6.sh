#!/usr/bin/env bash
set -euo pipefail

# Interim R3/R5 host-route smoke.  The hands-off case deliberately stops at
# the explicit Cast source boundary until the cast scene/RAMROM providers
# close; it must not be used as the final Release acceptance gate.

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_ROOT="${ROOT}/build/native/source-product-boot-route-v6"
MODULE_CACHE="${BUILD_ROOT}/module-cache"
mkdir -p "${BUILD_ROOT}" "${MODULE_CACHE}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CLANG=$(xcrun --sdk macosx --find clang)
SWIFTC=$(xcrun --sdk macosx --find swiftc)

COMMON_CFLAGS=(
    -std=c11 -Wall -Wextra -Werror -pedantic -target arm64-apple-macosx27.0
    -isysroot "${SDKROOT}" -I "${ROOT}/native/include"
    -I "${ROOT}/native/source_port"
)

build_and_run() {
    local suffix="$1"
    local sanitizer_flags=()
    local swift_flags=(-swift-version 6 -target arm64-apple-macosx27.0 -sdk "${SDKROOT}" -warnings-as-errors)
    if [[ "${suffix}" == sanitized ]]; then
        sanitizer_flags=(-O1 -fno-omit-frame-pointer -fsanitize=address,undefined)
        swift_flags+=(-sanitize=address)
    else
        sanitizer_flags=(-O2)
    fi

    local runtime_object="${BUILD_ROOT}/runtime-${suffix}.o"
    local facade_object="${BUILD_ROOT}/facade-${suffix}.o"
    local file_mode_object="${BUILD_ROOT}/file-mode-${suffix}.o"
    local executable="${BUILD_ROOT}/goldeneye_source_product_boot_route_v6_smoke-${suffix}"
    local log="${BUILD_ROOT}/${suffix}.log"

    "${CLANG}" "${COMMON_CFLAGS[@]}" "${sanitizer_flags[@]}" -c \
        "${ROOT}/native/src/ge_source_frontend_runtime_v6.c" -o "${runtime_object}"
    "${CLANG}" "${COMMON_CFLAGS[@]}" "${sanitizer_flags[@]}" -c \
        "${ROOT}/native/source_port/ge_source_frontend_v6.c" -o "${facade_object}"
    "${CLANG}" "${COMMON_CFLAGS[@]}" "${sanitizer_flags[@]}" -c \
        "${ROOT}/native/src/ge_file_mode_v6.c" -o "${file_mode_object}"

    CLANG_MODULE_CACHE_PATH="${MODULE_CACHE}" "${SWIFTC}" \
        "${swift_flags[@]}" \
        -Xcc -I -Xcc "${ROOT}/native/include" \
        -Xcc -I -Xcc "${ROOT}/native/source_port" \
        -import-objc-header "${ROOT}/native/include/ge_source_frontend_runtime_v6.h" \
        "${ROOT}/native/host/save_store.swift" \
        "${ROOT}/native/host/goldeneye_file_mode_authority_v6.swift" \
        "${ROOT}/native/host/goldeneye_source_product_contract_v6.swift" \
        "${ROOT}/native/host/goldeneye_source_frontend_authority_v6.swift" \
        "${ROOT}/native/host/goldeneye_source_frontend_presentation_v6.swift" \
        "${ROOT}/native/host/goldeneye_source_frontend_screen_selection_v6.swift" \
        "${ROOT}/native/tests/goldeneye_source_product_boot_route_v6_smoke.swift" \
        "${runtime_object}" "${facade_object}" "${file_mode_object}" \
        -o "${executable}"
    "${executable}" | tee "${log}"
    grep -Fq 'route=permitted-skip' "${log}"
    grep -Fq 'route=hands-off' "${log}"
    grep -Fq 'cast-handoff=1' "${log}"
    grep -Fq 'mode=1' "${log}"
}

build_and_run strict
build_and_run sanitized
echo 'source product boot-route submission/selection interim smoke: PASS'
