#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_ROOT="${ROOT}/build/native/guard-door-owner-v6"
MODULE_CACHE="${BUILD_ROOT}/module-cache"
mkdir -p "${BUILD_ROOT}" "${MODULE_CACHE}"

STAGE_ROOT="${1:-${GOLDENEYE_NATIVE_STAGE_ASSET_ROOT:-${ROOT}/build/native/stage-assets}}"
VISIBLE_ROOT="${2:-${GOLDENEYE_NATIVE_RAMROM_VISIBLE_ROOT:-${ROOT}/build/native/ramrom-visible-dependencies-v6}}"
BOOT_ROOT="${3:-${GOLDENEYE_NATIVE_ASSET_ROOT:-${ROOT}/build/native/boot-assets}}"
SETUP="${STAGE_ROOT}/setup/Dam__setup__UsetupdamZ.bin"
ANIMATION="${VISIBLE_ROOT}/payload/decoded/00946_watch_shared_animationtable_data.bin"
BODY="${STAGE_ROOT}/model-sidecars/stage_character_037_greatguard2.gesm"
HEAD="${STAGE_ROOT}/model-sidecars/stage_character_052_headgrant.gesm"
WEAPON="${STAGE_ROOT}/model-sidecars/stage_prop_191_chrwppk.gesm"
RAMROM="${BOOT_ROOT}/ramrom/ramrom_Dam_1.bin"

for required in "${SETUP}" "${ANIMATION}" "${BODY}" "${HEAD}" "${WEAPON}" "${RAMROM}"; do
    test -f "${required}" || { echo "missing prepared source input: ${required}" >&2; exit 1; }
done

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun --sdk macosx --find clang)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
CFLAGS=(-target arm64-apple-macosx27.0 -isysroot "${SDKROOT}" -std=c11 -Wall -Wextra -Werror -pedantic -O2 -I "${ROOT}/native/include")
LDFLAGS=(-target arm64-apple-macosx27.0 -isysroot "${SDKROOT}" -O2)

compile_c() {
    local source="$1"
    local object="$2"
    "${CC}" "${CFLAGS[@]}" -c "${ROOT}/${source}" -o "${BUILD_ROOT}/${object}"
}

compile_c native/src/ge_source_scene_v6.c ge_source_scene_v6.o
compile_c native/source_port/gameplay_v6/ge_ramrom_gameplay_v6.c ge_ramrom_gameplay_v6.o
compile_c native/src/ge_ramrom_v5.c ge_ramrom_v5.o
compile_c native/source_port/gameplay_v6/ge_guard_door_owner_v6.c ge_guard_door_owner_v6.o
compile_c native/source_port/gameplay_v6/ge_weapon_effect_owner_v6.c ge_weapon_effect_owner_v6.o
compile_c native/tests/goldeneye_guard_door_owner_v6_smoke.c goldeneye_guard_door_owner_v6_smoke.o

"${CC}" "${LDFLAGS[@]}" \
    "${BUILD_ROOT}/goldeneye_guard_door_owner_v6_smoke.o" \
    "${BUILD_ROOT}/ge_guard_door_owner_v6.o" \
    "${BUILD_ROOT}/ge_source_scene_v6.o" \
    "${BUILD_ROOT}/ge_ramrom_gameplay_v6.o" \
    "${BUILD_ROOT}/ge_ramrom_v5.o" \
    "${BUILD_ROOT}/ge_weapon_effect_owner_v6.o" \
    -o "${BUILD_ROOT}/goldeneye_guard_door_owner_v6_smoke"

"${BUILD_ROOT}/goldeneye_guard_door_owner_v6_smoke" \
    "${SETUP}" "${ANIMATION}" "${BODY}" "${HEAD}" "${WEAPON}" "${RAMROM}" \
    | tee "${BUILD_ROOT}/strict.log"
grep -Fq 'goldeneye_guard_door_owner_v6_smoke: PASS sourceObjects=2' "${BUILD_ROOT}/strict.log"

echo "Building ASan guard/door owner V6 smoke"
ASAN_CFLAGS=("${CFLAGS[@]}" -fsanitize=address)
ASAN_LDFLAGS=("${LDFLAGS[@]}" -fsanitize=address)
for source_object in ge_source_scene_v6 ge_ramrom_gameplay_v6 ge_ramrom_v5 ge_guard_door_owner_v6 ge_weapon_effect_owner_v6 goldeneye_guard_door_owner_v6_smoke; do
    source_path="native/src/${source_object}.c"
    if [[ "${source_object}" == ge_ramrom_gameplay_v6 || "${source_object}" == ge_guard_door_owner_v6 || "${source_object}" == ge_weapon_effect_owner_v6 ]]; then
        source_path="native/source_port/gameplay_v6/${source_object}.c"
    elif [[ "${source_object}" == goldeneye_guard_door_owner_v6_smoke ]]; then
        source_path="native/tests/${source_object}.c"
    fi
    "${CC}" "${ASAN_CFLAGS[@]}" -c "${ROOT}/${source_path}" -o "${BUILD_ROOT}/${source_object}.asan.o"
done
"${CC}" "${ASAN_LDFLAGS[@]}" \
    "${BUILD_ROOT}/goldeneye_guard_door_owner_v6_smoke.asan.o" \
    "${BUILD_ROOT}/ge_guard_door_owner_v6.asan.o" \
    "${BUILD_ROOT}/ge_source_scene_v6.asan.o" \
    "${BUILD_ROOT}/ge_ramrom_gameplay_v6.asan.o" \
    "${BUILD_ROOT}/ge_ramrom_v5.asan.o" \
    "${BUILD_ROOT}/ge_weapon_effect_owner_v6.asan.o" \
    -o "${BUILD_ROOT}/goldeneye_guard_door_owner_v6_smoke_asan"
ASAN_OPTIONS=halt_on_error=1:detect_leaks=0 \
    "${BUILD_ROOT}/goldeneye_guard_door_owner_v6_smoke_asan" \
    "${SETUP}" "${ANIMATION}" "${BODY}" "${HEAD}" "${WEAPON}" "${RAMROM}" \
    | tee "${BUILD_ROOT}/asan.log"
grep -Fq 'goldeneye_guard_door_owner_v6_smoke: PASS sourceObjects=2' "${BUILD_ROOT}/asan.log"

echo "Building UBSan guard/door owner V6 smoke"
UBSAN_CFLAGS=("${CFLAGS[@]}" -fsanitize=undefined)
UBSAN_LDFLAGS=("${LDFLAGS[@]}" -fsanitize=undefined)
for source_object in ge_source_scene_v6 ge_ramrom_gameplay_v6 ge_ramrom_v5 ge_guard_door_owner_v6 ge_weapon_effect_owner_v6 goldeneye_guard_door_owner_v6_smoke; do
    source_path="native/src/${source_object}.c"
    if [[ "${source_object}" == ge_ramrom_gameplay_v6 || "${source_object}" == ge_guard_door_owner_v6 || "${source_object}" == ge_weapon_effect_owner_v6 ]]; then
        source_path="native/source_port/gameplay_v6/${source_object}.c"
    elif [[ "${source_object}" == goldeneye_guard_door_owner_v6_smoke ]]; then
        source_path="native/tests/${source_object}.c"
    fi
    "${CC}" "${UBSAN_CFLAGS[@]}" -c "${ROOT}/${source_path}" -o "${BUILD_ROOT}/${source_object}.ubsan.o"
done
"${CC}" "${UBSAN_LDFLAGS[@]}" \
    "${BUILD_ROOT}/goldeneye_guard_door_owner_v6_smoke.ubsan.o" \
    "${BUILD_ROOT}/ge_guard_door_owner_v6.ubsan.o" \
    "${BUILD_ROOT}/ge_source_scene_v6.ubsan.o" \
    "${BUILD_ROOT}/ge_ramrom_gameplay_v6.ubsan.o" \
    "${BUILD_ROOT}/ge_ramrom_v5.ubsan.o" \
    "${BUILD_ROOT}/ge_weapon_effect_owner_v6.ubsan.o" \
    -o "${BUILD_ROOT}/goldeneye_guard_door_owner_v6_smoke_ubsan"
UBSAN_OPTIONS=halt_on_error=1 \
    "${BUILD_ROOT}/goldeneye_guard_door_owner_v6_smoke_ubsan" \
    "${SETUP}" "${ANIMATION}" "${BODY}" "${HEAD}" "${WEAPON}" "${RAMROM}" \
    | tee "${BUILD_ROOT}/ubsan.log"
grep -Fq 'goldeneye_guard_door_owner_v6_smoke: PASS sourceObjects=2' "${BUILD_ROOT}/ubsan.log"

SWIFT_ARGS=(-swift-version 6 -warnings-as-errors -target arm64-apple-macosx27.0 -sdk "${SDKROOT}")
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE}" "${SWIFTC}" "${SWIFT_ARGS[@]}" \
    -import-objc-header "${ROOT}/native/tests/goldeneye_guard_door_owner_v6_bridging.h" \
    -Xcc "-I${ROOT}/native/include" \
    "${ROOT}/native/host/goldeneye_guard_door_owner_v6.swift" \
    "${ROOT}/native/tests/goldeneye_guard_door_owner_v6_adapter_smoke.swift" \
    "${BUILD_ROOT}/ge_guard_door_owner_v6.o" \
    "${BUILD_ROOT}/ge_source_scene_v6.o" \
    "${BUILD_ROOT}/ge_ramrom_gameplay_v6.o" \
    "${BUILD_ROOT}/ge_ramrom_v5.o" \
    "${BUILD_ROOT}/ge_weapon_effect_owner_v6.o" \
    -o "${BUILD_ROOT}/goldeneye_guard_door_owner_v6_adapter_smoke"
"${BUILD_ROOT}/goldeneye_guard_door_owner_v6_adapter_smoke" "${ANIMATION}" \
    | tee "${BUILD_ROOT}/adapter.log"
grep -Fq 'goldeneye_guard_door_owner_v6_adapter_smoke: PASS' "${BUILD_ROOT}/adapter.log"

git -C "${ROOT}" diff --check
echo 'Guard/door source owner V6 strict/ASan/UBSan/Swift adapter validation: PASS'
