#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_ROOT="${ROOT}/build/native/source-frontend-presentation-v6"
mkdir -p "${BUILD_ROOT}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CLANG=$(xcrun --sdk macosx --find clang)
SWIFTC=$(xcrun --sdk macosx --find swiftc)

COMMON_CFLAGS=(
    -std=c11 -Wall -Wextra -Werror -pedantic
    -target arm64-apple-macosx27.0 -isysroot "${SDKROOT}"
    -I "${ROOT}/native/include" -I "${ROOT}/native/source_port"
)

"${CLANG}" "${COMMON_CFLAGS[@]}" -O2 -c \
    "${ROOT}/native/src/ge_source_frontend_runtime_v6.c" \
    -o "${BUILD_ROOT}/runtime.o"
"${CLANG}" "${COMMON_CFLAGS[@]}" -O2 -c \
    "${ROOT}/native/source_port/ge_source_frontend_v6.c" \
    -o "${BUILD_ROOT}/facade.o"
"${CLANG}" "${COMMON_CFLAGS[@]}" -O2 -c \
    "${ROOT}/native/src/ge_file_mode_v6.c" \
    -o "${BUILD_ROOT}/file-mode.o"

"${SWIFTC}" -sdk "${SDKROOT}" -target arm64-apple-macosx27.0 \
    -warnings-as-errors \
    -Xcc -I -Xcc "${ROOT}/native/include" \
    -Xcc -I -Xcc "${ROOT}/native/source_port" \
    -import-objc-header "${ROOT}/native/include/ge_source_frontend_runtime_v6.h" \
    "${ROOT}/native/host/save_store.swift" \
    "${ROOT}/native/host/goldeneye_file_mode_authority_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_product_contract_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_frontend_authority_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_frontend_presentation_v6.swift" \
    "${ROOT}/native/tests/goldeneye_source_frontend_presentation_v6_smoke.swift" \
    "${BUILD_ROOT}/runtime.o" "${BUILD_ROOT}/facade.o" "${BUILD_ROOT}/file-mode.o" \
    -o "${BUILD_ROOT}/goldeneye_source_frontend_presentation_v6_smoke"

"${BUILD_ROOT}/goldeneye_source_frontend_presentation_v6_smoke"
