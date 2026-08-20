#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="${PROJECT_ROOT}/build/native/source-projection-binding-v6"
STRICT_DIR="${BUILD_DIR}/strict"
SANITIZER_DIR="${BUILD_DIR}/sanitizers"
mkdir -p "${STRICT_DIR}" "${SANITIZER_DIR}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun --sdk macosx --find clang)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
CFLAGS=(-target arm64-apple-macosx27.0 -isysroot "${SDKROOT}" -std=c11
    -Wall -Wextra -Werror -Wno-c23-extensions -pedantic
    -I "${PROJECT_ROOT}/native/include")
SWIFTFLAGS=(-swift-version 6 -warnings-as-errors -target arm64-apple-macosx27.0
    -sdk "${SDKROOT}" -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_native_bridging.h"
    -Xcc "-I${PROJECT_ROOT}/native/include" -Xcc -include
    -Xcc "${PROJECT_ROOT}/native/include/ge_source_scene_v6.h")

"${CC}" "${CFLAGS[@]}" -O2 -c \
    "${PROJECT_ROOT}/native/src/ge_source_scene_v6.c" \
    -o "${STRICT_DIR}/ge_source_scene_v6.o"
"${SWIFTC}" "${SWIFTFLAGS[@]}" -Onone \
    "${PROJECT_ROOT}/native/host/goldeneye_source_projection_binding_v6.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_source_projection_binding_v6_smoke.swift" \
    "${STRICT_DIR}/ge_source_scene_v6.o" \
    -o "${STRICT_DIR}/goldeneye_source_projection_binding_v6_smoke"
"${STRICT_DIR}/goldeneye_source_projection_binding_v6_smoke" \
    | tee "${STRICT_DIR}/source-projection-binding-v6.log"
grep -Fq 'goldeneye_source_projection_binding_v6_smoke: PASS' \
    "${STRICT_DIR}/source-projection-binding-v6.log"

"${CC}" "${CFLAGS[@]}" -fsanitize=address,undefined -fno-omit-frame-pointer -O2 -c \
    "${PROJECT_ROOT}/native/src/ge_source_scene_v6.c" \
    -o "${SANITIZER_DIR}/ge_source_scene_v6.o"
"${SWIFTC}" "${SWIFTFLAGS[@]}" -Onone -sanitize=address,undefined \
    "${PROJECT_ROOT}/native/host/goldeneye_source_projection_binding_v6.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_source_projection_binding_v6_smoke.swift" \
    "${SANITIZER_DIR}/ge_source_scene_v6.o" \
    -o "${SANITIZER_DIR}/goldeneye_source_projection_binding_v6_smoke"
ASAN_OPTIONS=halt_on_error=1 \
    "${SANITIZER_DIR}/goldeneye_source_projection_binding_v6_smoke" \
    | tee "${SANITIZER_DIR}/source-projection-binding-v6.log"
grep -Fq 'goldeneye_source_projection_binding_v6_smoke: PASS' \
    "${SANITIZER_DIR}/source-projection-binding-v6.log"

git -C "${PROJECT_ROOT}" diff --check -- \
    native/include/ge_source_scene_v6.h \
    native/src/ge_source_scene_v6.c \
    native/host/goldeneye_source_projection_binding_v6.swift \
    native/tests/goldeneye_source_projection_binding_v6_smoke.swift \
    scripts/test_source_projection_binding_v6.sh

echo 'Source projection binding V6 validation: PASS (strict, ASan, UBSan)'
echo "Artifact: ${STRICT_DIR}/source-projection-binding-v6.log"
