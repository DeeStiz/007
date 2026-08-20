#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="${PROJECT_ROOT}/build/native/source-texture-coordinates-v6"
STRICT_DIR="${BUILD_DIR}/strict"
SANITIZER_DIR="${BUILD_DIR}/sanitizers"
mkdir -p "${STRICT_DIR}" "${SANITIZER_DIR}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun --sdk macosx --find clang)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
COMMON_CFLAGS=(-target arm64-apple-macosx27.0 -isysroot "${SDKROOT}" -std=c11
    -Wall -Wextra -Werror -pedantic -I "${PROJECT_ROOT}/native/include")

"${CC}" "${COMMON_CFLAGS[@]}" -O2 -c \
    "${PROJECT_ROOT}/native/src/ge_source_texture_coordinates_v6.c" \
    -o "${STRICT_DIR}/ge_source_texture_coordinates_v6.o"
"${CC}" "${COMMON_CFLAGS[@]}" -O2 \
    "${PROJECT_ROOT}/native/tests/goldeneye_source_texture_coordinates_v6_smoke.c" \
    "${STRICT_DIR}/ge_source_texture_coordinates_v6.o" \
    -o "${STRICT_DIR}/goldeneye_source_texture_coordinates_v6_smoke"
"${STRICT_DIR}/goldeneye_source_texture_coordinates_v6_smoke" \
    | tee "${STRICT_DIR}/source-texture-coordinates-v6.log"
grep -Fq 'goldeneye_source_texture_coordinates_v6_smoke: PASS' \
    "${STRICT_DIR}/source-texture-coordinates-v6.log"

CLANG_MODULE_CACHE_PATH="${BUILD_DIR}/module-cache" \
    "${SWIFTC}" -swift-version 6 -warnings-as-errors \
    -target arm64-apple-macosx27.0 -sdk "${SDKROOT}" -typecheck \
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_source_texture_coordinates_v6_bridging.h" \
    -Xcc "-I${PROJECT_ROOT}/native/include" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_coordinates_v6.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_source_texture_coordinates_v6_swift_smoke.swift"

"${SWIFTC}" -swift-version 6 -warnings-as-errors \
    -target arm64-apple-macosx27.0 -sdk "${SDKROOT}" \
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_source_texture_coordinates_v6_bridging.h" \
    -Xcc "-I${PROJECT_ROOT}/native/include" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_coordinates_v6.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_source_texture_coordinates_v6_swift_smoke.swift" \
    "${STRICT_DIR}/ge_source_texture_coordinates_v6.o" \
    -o "${STRICT_DIR}/goldeneye_source_texture_coordinates_v6_swift_smoke"
"${STRICT_DIR}/goldeneye_source_texture_coordinates_v6_swift_smoke" \
    | tee "${STRICT_DIR}/source-texture-coordinates-v6-swift.log"
grep -Fq 'goldeneye_source_texture_coordinates_v6_swift_smoke: PASS' \
    "${STRICT_DIR}/source-texture-coordinates-v6-swift.log"

SANITIZER_FLAGS=(-fsanitize=address,undefined -fno-omit-frame-pointer)
"${CC}" "${COMMON_CFLAGS[@]}" "${SANITIZER_FLAGS[@]}" -O1 -g -c \
    "${PROJECT_ROOT}/native/src/ge_source_texture_coordinates_v6.c" \
    -o "${SANITIZER_DIR}/ge_source_texture_coordinates_v6.o"
"${CC}" "${COMMON_CFLAGS[@]}" "${SANITIZER_FLAGS[@]}" -O1 -g \
    "${PROJECT_ROOT}/native/tests/goldeneye_source_texture_coordinates_v6_smoke.c" \
    "${SANITIZER_DIR}/ge_source_texture_coordinates_v6.o" \
    -o "${SANITIZER_DIR}/goldeneye_source_texture_coordinates_v6_smoke"
"${SANITIZER_DIR}/goldeneye_source_texture_coordinates_v6_smoke" \
    | tee "${SANITIZER_DIR}/source-texture-coordinates-v6.log"
grep -Fq 'goldeneye_source_texture_coordinates_v6_smoke: PASS' \
    "${SANITIZER_DIR}/source-texture-coordinates-v6.log"

echo 'Source texture-coordinate V6 validation: PASS (strict, Swift 6, ASan, UBSan)'
