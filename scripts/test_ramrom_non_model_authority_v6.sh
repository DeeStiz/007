#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BOOT_ROOT="${1:-${GOLDENEYE_NATIVE_RAMROM_ASSET_ROOT:-${PROJECT_ROOT}/build/native/boot-assets}}"
VISIBLE_ROOT="${2:-${GOLDENEYE_NATIVE_RAMROM_VISIBLE_ROOT:-${PROJECT_ROOT}/build/native/ramrom-visible-dependencies-v6}}"
BUILD_ROOT="${PROJECT_ROOT}/build/native/ramrom-non-model-authority-v6"
MODULE_CACHE_DIR="${BUILD_ROOT}/module-cache"
mkdir -p "${BUILD_ROOT}" "${MODULE_CACHE_DIR}"

if command -v xcrun >/dev/null 2>&1; then
    CC=$(xcrun --sdk macosx --find clang)
    SWIFTC=$(xcrun --sdk macosx --find swiftc)
    SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
    TARGET=(-target arm64-apple-macosx27.0)
    SYSROOT=(-isysroot "${SDKROOT}")
    SWIFT_PLATFORM=(-target arm64-apple-macosx27.0 -sdk "${SDKROOT}")
else
    CC=${CC:-clang}; SWIFTC=${SWIFTC:-swiftc}
    TARGET=(); SYSROOT=(); SWIFT_PLATFORM=()
fi

CFLAGS=(-std=c11 -Wall -Wextra -Werror -pedantic -O2 -I "${PROJECT_ROOT}/native/include" "${TARGET[@]}" "${SYSROOT[@]}")
OBJECTS=()
for source in ge_ramrom_v5.c ge_ramrom_playback_v5.c ge_native_runtime_v5.c ge_audio_v5.c; do
    object="${BUILD_ROOT}/${source%.c}.o"
    "${CC}" "${CFLAGS[@]}" -c "${PROJECT_ROOT}/native/src/${source}" -o "${object}"
    OBJECTS+=("${object}")
done
ar rcs "${BUILD_ROOT}/libgoldeneye_ramrom_non_model_authority_v6.a" "${OBJECTS[@]}"

SOURCES=(
    "${PROJECT_ROOT}/native/host/goldeneye_cast_title_hash.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_attract_route.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_ramrom_non_model_visuals_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_ramrom_non_model_authority_v6.swift"
    "${PROJECT_ROOT}/native/tests/goldeneye_ramrom_non_model_authority_v6_smoke.swift"
)
SMOKE="${BUILD_ROOT}/goldeneye_ramrom_non_model_authority_v6_smoke"
LOG="${BUILD_ROOT}/ramrom-non-model-authority-v6.log"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${SWIFTC}" \
    -swift-version 6 -warnings-as-errors -O -parse-as-library \
    "${SWIFT_PLATFORM[@]}" \
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_ramrom_playback_service_bridging.h" \
    -Xcc "-I${PROJECT_ROOT}/native/include" "${SOURCES[@]}" \
    "${BUILD_ROOT}/libgoldeneye_ramrom_non_model_authority_v6.a" \
    -o "${SMOKE}"
"${SMOKE}" "${BOOT_ROOT}" "${VISIBLE_ROOT}" | tee "${LOG}"
grep -Fq 'goldeneye_ramrom_non_model_authority_v6_smoke: PASS demos=14 runs=28' "${LOG}"

SAN_BUILD_ROOT="${BUILD_ROOT}/sanitized"
mkdir -p "${SAN_BUILD_ROOT}"
SAN_OBJECTS=()
for source in ge_ramrom_v5.c ge_ramrom_playback_v5.c ge_native_runtime_v5.c ge_audio_v5.c; do
    object="${SAN_BUILD_ROOT}/${source%.c}.o"
    "${CC}" "${CFLAGS[@]}" -O1 -fno-omit-frame-pointer -fsanitize=address,undefined \
        -c "${PROJECT_ROOT}/native/src/${source}" -o "${object}"
    SAN_OBJECTS+=("${object}")
done
ar rcs "${SAN_BUILD_ROOT}/libgoldeneye_ramrom_non_model_authority_v6.a" "${SAN_OBJECTS[@]}"
SAN_SMOKE="${SAN_BUILD_ROOT}/goldeneye_ramrom_non_model_authority_v6_smoke_asan"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${SWIFTC}" \
    -swift-version 6 -warnings-as-errors -O -sanitize=address -parse-as-library \
    "${SWIFT_PLATFORM[@]}" \
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_ramrom_playback_service_bridging.h" \
    -Xcc "-I${PROJECT_ROOT}/native/include" "${SOURCES[@]}" \
    "${SAN_BUILD_ROOT}/libgoldeneye_ramrom_non_model_authority_v6.a" \
    -o "${SAN_SMOKE}"
ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 \
    "${SAN_SMOKE}" "${BOOT_ROOT}" "${VISIBLE_ROOT}" \
    | tee "${BUILD_ROOT}/ramrom-non-model-authority-v6-asan.log"
grep -Fq 'goldeneye_ramrom_non_model_authority_v6_smoke: PASS demos=14 runs=28' \
    "${BUILD_ROOT}/ramrom-non-model-authority-v6-asan.log"

UBSAN_BUILD_ROOT="${BUILD_ROOT}/ubsan"
mkdir -p "${UBSAN_BUILD_ROOT}"
UBSAN_OBJECTS=()
for source in ge_ramrom_v5.c ge_ramrom_playback_v5.c ge_native_runtime_v5.c ge_audio_v5.c; do
    object="${UBSAN_BUILD_ROOT}/${source%.c}.o"
    "${CC}" "${CFLAGS[@]}" -O1 -fno-omit-frame-pointer -fsanitize=undefined \
        -c "${PROJECT_ROOT}/native/src/${source}" -o "${object}"
    UBSAN_OBJECTS+=("${object}")
done
ar rcs "${UBSAN_BUILD_ROOT}/libgoldeneye_ramrom_non_model_authority_v6.a" "${UBSAN_OBJECTS[@]}"
UBSAN_SMOKE="${UBSAN_BUILD_ROOT}/goldeneye_ramrom_non_model_authority_v6_smoke_ubsan"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${SWIFTC}" \
    -swift-version 6 -warnings-as-errors -O -sanitize=undefined -parse-as-library \
    "${SWIFT_PLATFORM[@]}" \
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_ramrom_playback_service_bridging.h" \
    -Xcc "-I${PROJECT_ROOT}/native/include" "${SOURCES[@]}" \
    "${UBSAN_BUILD_ROOT}/libgoldeneye_ramrom_non_model_authority_v6.a" \
    -o "${UBSAN_SMOKE}"
UBSAN_OPTIONS=halt_on_error=1 \
    "${UBSAN_SMOKE}" "${BOOT_ROOT}" "${VISIBLE_ROOT}" \
    | tee "${BUILD_ROOT}/ramrom-non-model-authority-v6-ubsan.log"
grep -Fq 'goldeneye_ramrom_non_model_authority_v6_smoke: PASS demos=14 runs=28' \
    "${BUILD_ROOT}/ramrom-non-model-authority-v6-ubsan.log"

echo "RAMROM non-model authority V6 all-14 validation: PASS"
echo "Artifact: ${LOG}"
