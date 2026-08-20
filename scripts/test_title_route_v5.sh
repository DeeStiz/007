#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${1:-${GOLDENEYE_NATIVE_ASSET_ROOT:-${PROJECT_ROOT}/build/native/boot-assets}}"
BUILD_DIR="${PROJECT_ROOT}/build/native/title-route-v5"
MODULE_CACHE_DIR="${BUILD_DIR}/module-cache"

mkdir -p "${BUILD_DIR}" "${MODULE_CACHE_DIR}"

if command -v xcrun >/dev/null 2>&1; then
    ROUTE_CC=$(xcrun --sdk macosx --find clang)
    ROUTE_SWIFTC=$(xcrun --sdk macosx --find swiftc)
    ROUTE_SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
else
    ROUTE_CC=${ROUTE_CC:-clang}
    ROUTE_SWIFTC=${ROUTE_SWIFTC:-swiftc}
    ROUTE_SDKROOT=""
fi

COMMON_CFLAGS=(
    -std=c11 -Wall -Wextra -Werror -pedantic -O2
    -I "${PROJECT_ROOT}/native/include"
)
SWIFT_ARGS=(-swift-version 6)
if [[ -n "${ROUTE_SDKROOT}" ]]; then
    COMMON_CFLAGS+=(
        -target arm64-apple-macosx27.0
        -isysroot "${ROUTE_SDKROOT}"
    )
    SWIFT_ARGS+=(
        -target arm64-apple-macosx27.0
        -sdk "${ROUTE_SDKROOT}"
    )
fi

C_SOURCES=(
    "${PROJECT_ROOT}/native/src/ge_title_route_v5.c"
    "${PROJECT_ROOT}/native/src/ge_ramrom_v5.c"
    "${PROJECT_ROOT}/native/src/ge_native_runtime_v5.c"
    "${PROJECT_ROOT}/native/src/ge_audio_v5.c"
)
C_SMOKE="${BUILD_DIR}/goldeneye_title_route_v5_smoke"
C_SANITIZED="${BUILD_DIR}/goldeneye_title_route_v5_smoke_sanitized"

echo "Building strict C title-route V5 smoke"
"${ROUTE_CC}" "${COMMON_CFLAGS[@]}" "${C_SOURCES[@]}" \
    "${PROJECT_ROOT}/native/tests/goldeneye_title_route_v5_smoke.c" \
    -o "${C_SMOKE}"
"${C_SMOKE}"

echo "Building ASan/UBSan title-route V5 smoke"
"${ROUTE_CC}" "${COMMON_CFLAGS[@]}" -O1 -fno-omit-frame-pointer \
    -fsanitize=address,undefined "${C_SOURCES[@]}" \
    "${PROJECT_ROOT}/native/tests/goldeneye_title_route_v5_smoke.c" \
    -o "${C_SANITIZED}"
ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 "${C_SANITIZED}"

if [[ ! -d "${ASSET_ROOT}/ramrom" ]]; then
    echo "RAMROM asset root is missing: ${ASSET_ROOT}/ramrom" >&2
    exit 1
fi

echo "Building Swift cast/RAMROM integration smoke"
OBJECTS=()
for source in "${C_SOURCES[@]}"; do
    object="${BUILD_DIR}/$(basename "${source}" .c).o"
    "${ROUTE_CC}" "${COMMON_CFLAGS[@]}" -c "${source}" -o "${object}"
    OBJECTS+=("${object}")
done
ar rcs "${BUILD_DIR}/libgoldeneye_title_route_v5.a" "${OBJECTS[@]}"

CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${ROUTE_SWIFTC}" \
    "${SWIFT_ARGS[@]}" \
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_title_route_v5_bridging.h" \
    -Xcc "-I${PROJECT_ROOT}/native/include" \
    "${PROJECT_ROOT}/native/host/save_store.swift" \
    "${PROJECT_ROOT}/native/host/display_link_runtime.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_attract_route.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_cast_title_hash.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_boot_flow.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_attract_route_smoke.swift" \
    "${BUILD_DIR}/libgoldeneye_title_route_v5.a" \
    -o "${BUILD_DIR}/goldeneye_attract_route_smoke"
"${BUILD_DIR}/goldeneye_attract_route_smoke" "${ASSET_ROOT}"

CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${ROUTE_SWIFTC}" \
    "${SWIFT_ARGS[@]}" \
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_title_route_v5_bridging.h" \
    -Xcc "-I${PROJECT_ROOT}/native/include" \
    "${PROJECT_ROOT}/native/host/save_store.swift" \
    "${PROJECT_ROOT}/native/host/display_link_runtime.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_attract_route.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_cast_title_hash.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_boot_flow.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_boot_flow_smoke.swift" \
    "${BUILD_DIR}/libgoldeneye_title_route_v5.a" \
    -o "${BUILD_DIR}/goldeneye_boot_flow_smoke"
"${BUILD_DIR}/goldeneye_boot_flow_smoke"

git -C "${PROJECT_ROOT}" diff --check
echo "Title route V5 validation: PASS"
