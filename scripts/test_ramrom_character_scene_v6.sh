#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
STAGE_ROOT="${1:-${GOLDENEYE_NATIVE_STAGE_ASSET_ROOT:-${PROJECT_ROOT}/build/native/stage-assets-image-decoder-v6}}"
VISIBLE_ROOT="${2:-${GOLDENEYE_NATIVE_VISIBLE_DEPENDENCY_ROOT:-${PROJECT_ROOT}/build/native/ramrom-visible-dependencies-v6}}"
BUILD_DIR="${PROJECT_ROOT}/build/native/ramrom-character-scene-v6"
MODULE_CACHE_DIR="${BUILD_DIR}/module-cache"
mkdir -p "${BUILD_DIR}" "${MODULE_CACHE_DIR}"

SWIFTC=$(xcrun --sdk macosx --find swiftc)
SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
SWIFT_ARGS=(-swift-version 6 -warnings-as-errors -target arm64-apple-macosx27.0 -sdk "${SDKROOT}")
SOURCES=(
    "${PROJECT_ROOT}/native/host/goldeneye_stage_setup_packet.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_source_model_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_ramrom_visible_dependency_catalog_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_stage_model_sidecar_catalog_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_stage_setup_dependency_catalog_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_ramrom_character_scene_v6.swift"
    "${PROJECT_ROOT}/native/tests/goldeneye_ramrom_character_scene_v6_smoke.swift"
)

SMOKE="${BUILD_DIR}/goldeneye_ramrom_character_scene_v6_smoke"
ASAN="${BUILD_DIR}/goldeneye_ramrom_character_scene_v6_smoke_asan"
UBSAN="${BUILD_DIR}/goldeneye_ramrom_character_scene_v6_smoke_ubsan"

CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${SWIFTC}" "${SWIFT_ARGS[@]}" \
    "${SOURCES[@]}" -o "${SMOKE}"
"${SMOKE}" "${STAGE_ROOT}" "${VISIBLE_ROOT}" | tee "${BUILD_DIR}/strict.log"
grep -Fq 'goldeneye_ramrom_character_scene_v6_smoke: PASS demos=14 stages=7' "${BUILD_DIR}/strict.log"

CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${SWIFTC}" "${SWIFT_ARGS[@]}" \
    -sanitize=address "${SOURCES[@]}" -o "${ASAN}"
ASAN_OPTIONS=halt_on_error=1:detect_leaks=0 "${ASAN}" "${STAGE_ROOT}" "${VISIBLE_ROOT}" \
    | tee "${BUILD_DIR}/asan.log"
grep -Fq 'goldeneye_ramrom_character_scene_v6_smoke: PASS demos=14 stages=7' "${BUILD_DIR}/asan.log"

CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${SWIFTC}" "${SWIFT_ARGS[@]}" \
    -sanitize=undefined "${SOURCES[@]}" -o "${UBSAN}"
UBSAN_OPTIONS=halt_on_error=1 "${UBSAN}" "${STAGE_ROOT}" "${VISIBLE_ROOT}" \
    | tee "${BUILD_DIR}/ubsan.log"
grep -Fq 'goldeneye_ramrom_character_scene_v6_smoke: PASS demos=14 stages=7' "${BUILD_DIR}/ubsan.log"

echo 'RAMROM character scene V6 validation: PASS'
