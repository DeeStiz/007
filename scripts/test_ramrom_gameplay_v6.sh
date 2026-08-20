#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
STAGE_ROOT="${1:-${GOLDENEYE_NATIVE_STAGE_ASSET_ROOT:-${ROOT}/build/native/stage-assets-image-decoder-v6}}"
BOOT_ROOT="${2:-${GOLDENEYE_NATIVE_ASSET_ROOT:-${ROOT}/build/native/boot-assets}}"
VISIBLE_ROOT="${3:-${GOLDENEYE_NATIVE_RAMROM_VISIBLE_ROOT:-${ROOT}/build/native/ramrom-visible-dependencies-v6}}"
BUILD_ROOT="${ROOT}/build/native/ramrom-gameplay-v6"
MODULE_CACHE="${BUILD_ROOT}/module-cache"
mkdir -p "${BUILD_ROOT}" "${MODULE_CACHE}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun --sdk macosx --find clang)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
CFLAGS=(-target arm64-apple-macosx27.0 -isysroot "${SDKROOT}" -std=c11 -Wall -Wextra -Werror -pedantic -O2 -I "${ROOT}/native/include")
SWIFT_ARGS=(-swift-version 6 -warnings-as-errors -target arm64-apple-macosx27.0 -sdk "${SDKROOT}")

OBJECTS=()
for source in ge_ramrom_v5.c ge_stage_v5.c ge_stage_background_v5.c ge_source_scene_v6.c; do
    object="${BUILD_ROOT}/${source%.c}.o"
    "${CC}" "${CFLAGS[@]}" -c "${ROOT}/native/src/${source}" -o "${object}"
    OBJECTS+=("${object}")
done
GUARD_DOOR_OWNER_OBJECT="${BUILD_ROOT}/ge_guard_door_owner_v6.o"
"${CC}" "${CFLAGS[@]}" -c "${ROOT}/native/source_port/gameplay_v6/ge_guard_door_owner_v6.c" -o "${GUARD_DOOR_OWNER_OBJECT}"
OBJECTS+=("${GUARD_DOOR_OWNER_OBJECT}")
WEAPON_EFFECT_OWNER_OBJECT="${BUILD_ROOT}/ge_weapon_effect_owner_v6.o"
"${CC}" "${CFLAGS[@]}" -c "${ROOT}/native/source_port/gameplay_v6/ge_weapon_effect_owner_v6.c" -o "${WEAPON_EFFECT_OWNER_OBJECT}"
OBJECTS+=("${WEAPON_EFFECT_OWNER_OBJECT}")
GAMEPLAY_OBJECT="${BUILD_ROOT}/ge_ramrom_gameplay_v6.o"
"${CC}" "${CFLAGS[@]}" -c "${ROOT}/native/source_port/gameplay_v6/ge_ramrom_gameplay_v6.c" -o "${GAMEPLAY_OBJECT}"
OBJECTS+=("${GAMEPLAY_OBJECT}")

SOURCES=(
    "${ROOT}/native/host/goldeneye_stage_asset_catalog.swift"
    "${ROOT}/native/host/goldeneye_stage_setup_packet.swift"
    "${ROOT}/native/host/goldeneye_stage_scene_packet.swift"
    "${ROOT}/native/host/goldeneye_source_model_v6.swift"
    "${ROOT}/native/host/goldeneye_stage_model_sidecar_catalog_v6.swift"
    "${ROOT}/native/host/goldeneye_stage_setup_dependency_catalog_v6.swift"
    "${ROOT}/native/host/goldeneye_ramrom_visible_dependency_catalog_v6.swift"
    "${ROOT}/native/host/goldeneye_ramrom_gameplay_v6.swift"
    "${ROOT}/native/tests/goldeneye_ramrom_gameplay_v6_smoke.swift"
)

echo "Building strict source-page/gameplay V6 smoke"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE}" "${SWIFTC}" "${SWIFT_ARGS[@]}" \
    -import-objc-header "${ROOT}/native/tests/goldeneye_ramrom_gameplay_v6_bridging.h" \
    -Xcc "-I${ROOT}/native/include" "${SOURCES[@]}" "${OBJECTS[@]}" \
    -o "${BUILD_ROOT}/goldeneye_ramrom_gameplay_v6_smoke"

"${BUILD_ROOT}/goldeneye_ramrom_gameplay_v6_smoke" "${STAGE_ROOT}" "${BOOT_ROOT}" "${VISIBLE_ROOT}" \
    | tee "${BUILD_ROOT}/ramrom-gameplay-v6.log"
grep -Fq 'goldeneye_ramrom_gameplay_v6_smoke: PASS stages=7' "${BUILD_ROOT}/ramrom-gameplay-v6.log"

echo "Building ASan source-page/gameplay V6 smoke"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE}" "${SWIFTC}" "${SWIFT_ARGS[@]}" -sanitize=address \
    -import-objc-header "${ROOT}/native/tests/goldeneye_ramrom_gameplay_v6_bridging.h" \
    -Xcc "-I${ROOT}/native/include" "${SOURCES[@]}" "${OBJECTS[@]}" \
    -o "${BUILD_ROOT}/goldeneye_ramrom_gameplay_v6_smoke_asan"
ASAN_OPTIONS=halt_on_error=1:detect_leaks=0 \
    "${BUILD_ROOT}/goldeneye_ramrom_gameplay_v6_smoke_asan" "${STAGE_ROOT}" "${BOOT_ROOT}" "${VISIBLE_ROOT}" \
    | tee "${BUILD_ROOT}/ramrom-gameplay-v6-asan.log"
grep -Fq 'goldeneye_ramrom_gameplay_v6_smoke: PASS stages=7' "${BUILD_ROOT}/ramrom-gameplay-v6-asan.log"

echo "Building UBSan source-page/gameplay V6 smoke"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE}" "${SWIFTC}" "${SWIFT_ARGS[@]}" -sanitize=undefined \
    -import-objc-header "${ROOT}/native/tests/goldeneye_ramrom_gameplay_v6_bridging.h" \
    -Xcc "-I${ROOT}/native/include" "${SOURCES[@]}" "${OBJECTS[@]}" \
    -o "${BUILD_ROOT}/goldeneye_ramrom_gameplay_v6_smoke_ubsan"
UBSAN_OPTIONS=halt_on_error=1 \
    "${BUILD_ROOT}/goldeneye_ramrom_gameplay_v6_smoke_ubsan" "${STAGE_ROOT}" "${BOOT_ROOT}" "${VISIBLE_ROOT}" \
    | tee "${BUILD_ROOT}/ramrom-gameplay-v6-ubsan.log"
grep -Fq 'goldeneye_ramrom_gameplay_v6_smoke: PASS stages=7' "${BUILD_ROOT}/ramrom-gameplay-v6-ubsan.log"

if rg -n 'ge_gameplay_seed_defaults|1311|0x10000001|0x40000000' \
    "${ROOT}/native/source_port/gameplay_v6/ge_ramrom_gameplay_v6.c"; then
    echo "synthetic gameplay path leaked into production source" >&2
    exit 1
fi
git -C "${ROOT}" diff --check
echo "Native RAMROM gameplay V6 source-page validation: PASS"
