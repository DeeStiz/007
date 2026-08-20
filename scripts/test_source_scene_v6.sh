#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="${PROJECT_ROOT}/build/native/source-scene-v6"
STRICT_DIR="${BUILD_DIR}/strict"
SANITIZER_DIR="${BUILD_DIR}/sanitizers"
mkdir -p "${STRICT_DIR}" "${SANITIZER_DIR}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun --sdk macosx --find clang)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
COMMON_CFLAGS=(-target arm64-apple-macosx27.0 -isysroot "${SDKROOT}" -std=c11
    -Wall -Wextra -Werror -pedantic -I "${PROJECT_ROOT}/native/include")

"${CC}" "${COMMON_CFLAGS[@]}" -O2 -c \
    "${PROJECT_ROOT}/native/src/ge_source_scene_v6.c" \
    -o "${STRICT_DIR}/ge_source_scene_v6.o"
"${CC}" "${COMMON_CFLAGS[@]}" -O2 \
    "${PROJECT_ROOT}/native/tests/goldeneye_source_scene_v6_smoke.c" \
    "${STRICT_DIR}/ge_source_scene_v6.o" \
    -o "${STRICT_DIR}/goldeneye_source_scene_v6_smoke"

"${STRICT_DIR}/goldeneye_source_scene_v6_smoke" \
    | tee "${STRICT_DIR}/source-scene-v6.log"
grep -Fq 'goldeneye_source_scene_v6_smoke: PASS' \
    "${STRICT_DIR}/source-scene-v6.log"

CLANG_MODULE_CACHE_PATH="${BUILD_DIR}/module-cache" \
    "${SWIFTC}" -swift-version 6 -warnings-as-errors \
    -target arm64-apple-macosx27.0 -sdk "${SDKROOT}" -typecheck \
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_native_bridging.h" \
    -Xcc "-I${PROJECT_ROOT}/native/include" \
    -Xcc -include -Xcc "${PROJECT_ROOT}/native/include/ge_source_scene_v6.h" \
    "${PROJECT_ROOT}/native/tests/goldeneye_native_swift_smoke.swift"

SANITIZER_FLAGS=(-fsanitize=address,undefined -fno-omit-frame-pointer)
"${CC}" "${COMMON_CFLAGS[@]}" "${SANITIZER_FLAGS[@]}" -O1 -g -c \
    "${PROJECT_ROOT}/native/src/ge_source_scene_v6.c" \
    -o "${SANITIZER_DIR}/ge_source_scene_v6.o"
"${CC}" "${COMMON_CFLAGS[@]}" "${SANITIZER_FLAGS[@]}" -O1 -g \
    "${PROJECT_ROOT}/native/tests/goldeneye_source_scene_v6_smoke.c" \
    "${SANITIZER_DIR}/ge_source_scene_v6.o" \
    -o "${SANITIZER_DIR}/goldeneye_source_scene_v6_smoke"

"${SANITIZER_DIR}/goldeneye_source_scene_v6_smoke" \
    | tee "${SANITIZER_DIR}/source-scene-v6.log"
grep -Fq 'goldeneye_source_scene_v6_smoke: PASS' \
    "${SANITIZER_DIR}/source-scene-v6.log"

echo 'Source scene V6 ABI validation: PASS (strict, ASan, UBSan)'
