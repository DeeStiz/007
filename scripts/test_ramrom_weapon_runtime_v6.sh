#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
STAGE_ROOT="${1:-${GOLDENEYE_NATIVE_STAGE_ASSET_ROOT:-${ROOT}/build/native/stage-assets-image-decoder-v6}}"
VISIBLE_ROOT="${2:-${GOLDENEYE_NATIVE_RAMROM_VISIBLE_ROOT:-${ROOT}/build/native/ramrom-visible-dependencies-v6}}"
BUILD_ROOT="${ROOT}/build/native/ramrom-weapon-runtime-v6"
MODULE_CACHE="${BUILD_ROOT}/module-cache"
mkdir -p "${BUILD_ROOT}" "${MODULE_CACHE}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun --sdk macosx --find clang)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
CFLAGS=(-target arm64-apple-macosx27.0 -isysroot "${SDKROOT}" -std=c11 -Wall -Wextra -Werror -pedantic -O2
    -I "${ROOT}/native/include" -I "${ROOT}/native/source_port/gameplay_v6")
SWIFT_ARGS=(-swift-version 6 -warnings-as-errors -target arm64-apple-macosx27.0 -sdk "${SDKROOT}")

OBJECTS=()
for source in ge_stage_v5.c ge_stage_background_v5.c ge_ramrom_v5.c ge_source_scene_v6.c; do
    object="${BUILD_ROOT}/${source%.c}.o"
    "${CC}" "${CFLAGS[@]}" -c "${ROOT}/native/src/${source}" -o "${object}"
    OBJECTS+=("${object}")
done
for source in ge_guard_door_owner_v6.c ge_weapon_effect_owner_v6.c ge_ramrom_weapon_source_pages_v6.c ge_ramrom_gameplay_v6.c; do
    object="${BUILD_ROOT}/${source%.c}.o"
    "${CC}" "${CFLAGS[@]}" -c "${ROOT}/native/source_port/gameplay_v6/${source}" -o "${object}"
    OBJECTS+=("${object}")
done

SOURCES=(
    "${ROOT}/native/host/goldeneye_stage_asset_catalog.swift"
    "${ROOT}/native/host/goldeneye_stage_setup_packet.swift"
    "${ROOT}/native/host/goldeneye_stage_scene_packet.swift"
    "${ROOT}/native/host/goldeneye_source_model_v6.swift"
    "${ROOT}/native/host/goldeneye_stage_model_sidecar_catalog_v6.swift"
    "${ROOT}/native/host/goldeneye_ramrom_visible_dependency_catalog_v6.swift"
    "${ROOT}/native/host/goldeneye_ramrom_weapon_asset_catalog_v6.swift"
    "${ROOT}/native/host/goldeneye_ramrom_source_weapon_mapping_v6.swift"
    "${ROOT}/native/host/goldeneye_ramrom_weapon_source_pages_v6.swift"
    "${ROOT}/native/host/goldeneye_ramrom_weapon_runtime_v6.swift"
    "${ROOT}/native/tests/goldeneye_ramrom_weapon_runtime_v6_smoke.swift"
)

echo "Building strict RAMROM weapon runtime V6 smoke"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE}" "${SWIFTC}" "${SWIFT_ARGS[@]}" \
    -import-objc-header "${ROOT}/native/tests/goldeneye_ramrom_weapon_runtime_v6_bridging.h" \
    -Xcc "-I${ROOT}/native/include" -Xcc "-I${ROOT}/native/source_port/gameplay_v6" \
    "${SOURCES[@]}" "${OBJECTS[@]}" -o "${BUILD_ROOT}/smoke"
"${BUILD_ROOT}/smoke" "${STAGE_ROOT}" "${VISIBLE_ROOT}" | tee "${BUILD_ROOT}/strict.log"
grep -Fq 'goldeneye_ramrom_weapon_runtime_v6_smoke: PASS routes=14 parse-twice=14 readiness-matrix=14' "${BUILD_ROOT}/strict.log"

echo "Building ASan RAMROM weapon runtime V6 smoke"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE}" "${SWIFTC}" "${SWIFT_ARGS[@]}" -sanitize=address \
    -import-objc-header "${ROOT}/native/tests/goldeneye_ramrom_weapon_runtime_v6_bridging.h" \
    -Xcc "-I${ROOT}/native/include" -Xcc "-I${ROOT}/native/source_port/gameplay_v6" \
    "${SOURCES[@]}" "${OBJECTS[@]}" -o "${BUILD_ROOT}/smoke-asan"
ASAN_OPTIONS=halt_on_error=1:detect_leaks=0 "${BUILD_ROOT}/smoke-asan" "${STAGE_ROOT}" "${VISIBLE_ROOT}" \
    | tee "${BUILD_ROOT}/asan.log"
grep -Fq 'goldeneye_ramrom_weapon_runtime_v6_smoke: PASS routes=14 parse-twice=14 readiness-matrix=14' "${BUILD_ROOT}/asan.log"

echo "Building UBSan RAMROM weapon runtime V6 smoke"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE}" "${SWIFTC}" "${SWIFT_ARGS[@]}" -sanitize=undefined \
    -import-objc-header "${ROOT}/native/tests/goldeneye_ramrom_weapon_runtime_v6_bridging.h" \
    -Xcc "-I${ROOT}/native/include" -Xcc "-I${ROOT}/native/source_port/gameplay_v6" \
    "${SOURCES[@]}" "${OBJECTS[@]}" -o "${BUILD_ROOT}/smoke-ubsan"
UBSAN_OPTIONS=halt_on_error=1 "${BUILD_ROOT}/smoke-ubsan" "${STAGE_ROOT}" "${VISIBLE_ROOT}" \
    | tee "${BUILD_ROOT}/ubsan.log"
grep -Fq 'goldeneye_ramrom_weapon_runtime_v6_smoke: PASS routes=14 parse-twice=14 readiness-matrix=14' "${BUILD_ROOT}/ubsan.log"

git -C "${ROOT}" diff --check
echo "Native RAMROM weapon runtime V6 validation: PASS"
