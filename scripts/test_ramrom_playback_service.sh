#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${1:-${GOLDENEYE_NATIVE_ASSET_ROOT:-${PROJECT_ROOT}/assets}}"
BUILD_DIR="${PROJECT_ROOT}/build/native/ramrom-playback-service-v5"
MODULE_CACHE_DIR="${BUILD_DIR}/module-cache"
mkdir -p "${BUILD_DIR}" "${MODULE_CACHE_DIR}"

if command -v xcrun >/dev/null 2>&1; then
    SERVICE_CC=$(xcrun --sdk macosx --find clang)
    SERVICE_SWIFTC=$(xcrun --sdk macosx --find swiftc)
    SERVICE_SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
else
    SERVICE_CC=${SERVICE_CC:-clang}
    SERVICE_SWIFTC=${SERVICE_SWIFTC:-swiftc}
    SERVICE_SDKROOT=""
fi

COMMON_CFLAGS=(
    -std=c11 -Wall -Wextra -Werror -pedantic -O2
    -I "${PROJECT_ROOT}/native/include"
)
SWIFT_ARGS=(-swift-version 6)
if [[ -n "${SERVICE_SDKROOT}" ]]; then
    COMMON_CFLAGS+=(
        -target arm64-apple-macosx27.0
        -isysroot "${SERVICE_SDKROOT}"
    )
    SWIFT_ARGS+=(
        -target arm64-apple-macosx27.0
        -sdk "${SERVICE_SDKROOT}"
    )
fi

C_SOURCES=(
    "${PROJECT_ROOT}/native/src/ge_ramrom_v5.c"
    "${PROJECT_ROOT}/native/src/ge_ramrom_playback_v5.c"
    "${PROJECT_ROOT}/native/src/ge_native_runtime_v5.c"
    "${PROJECT_ROOT}/native/src/ge_audio_v5.c"
)
OBJECTS=()
for source in "${C_SOURCES[@]}"; do
    object="${BUILD_DIR}/$(basename "${source}" .c).o"
    "${SERVICE_CC}" "${COMMON_CFLAGS[@]}" -c "${source}" -o "${object}"
    OBJECTS+=("${object}")
done
ar rcs "${BUILD_DIR}/libgoldeneye_ramrom_playback_service.a" "${OBJECTS[@]}"

echo "Building Swift RAMROM playback owner-service smoke"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${SERVICE_SWIFTC}" \
    "${SWIFT_ARGS[@]}" \
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_ramrom_playback_service_bridging.h" \
    -Xcc "-I${PROJECT_ROOT}/native/include" \
    "${PROJECT_ROOT}/native/host/goldeneye_attract_route.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_cast_title_hash.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_ramrom_playback_service.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_ramrom_playback_service_hash.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_ramrom_playback_service_smoke.swift" \
    "${BUILD_DIR}/libgoldeneye_ramrom_playback_service.a" \
    -o "${BUILD_DIR}/goldeneye_ramrom_playback_service_smoke"

"${BUILD_DIR}/goldeneye_ramrom_playback_service_smoke" "${ASSET_ROOT}"
git -C "${PROJECT_ROOT}" diff --check
echo "RAMROM playback Swift owner-service validation: PASS"
