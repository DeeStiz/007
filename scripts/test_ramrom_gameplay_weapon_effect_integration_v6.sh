#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BOOT_ROOT="${1:-${GOLDENEYE_NATIVE_ASSET_ROOT:-${ROOT}/build/native/boot-assets}}"
RECORDING="${BOOT_ROOT}/ramrom/ramrom_Dam_1.bin"
BUILD_ROOT="${ROOT}/build/native/ramrom-gameplay-weapon-effect-integration-v6"
mkdir -p "${BUILD_ROOT}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun --sdk macosx --find clang)
CFLAGS=(-target arm64-apple-macosx27.0 -isysroot "${SDKROOT}" -std=c11 -Wall -Wextra -Werror -pedantic -O2
    -I "${ROOT}/native/include" -I "${ROOT}/native/source_port/gameplay_v6")

COMMON_SOURCES=(
    "${ROOT}/native/src/ge_ramrom_v5.c"
    "${ROOT}/native/src/ge_source_scene_v6.c"
    "${ROOT}/native/source_port/gameplay_v6/ge_guard_door_owner_v6.c"
    "${ROOT}/native/source_port/gameplay_v6/ge_weapon_effect_owner_v6.c"
    "${ROOT}/native/source_port/gameplay_v6/ge_ramrom_gameplay_v6.c"
)
SMOKE="${ROOT}/native/tests/ge_ramrom_gameplay_weapon_effect_integration_v6_smoke.c"

echo "Building strict gameplay/weapon-effect integration smoke"
"${CC}" "${CFLAGS[@]}" "${COMMON_SOURCES[@]}" "${SMOKE}" \
    -o "${BUILD_ROOT}/smoke"
"${BUILD_ROOT}/smoke" "${RECORDING}" | tee "${BUILD_ROOT}/strict.log"
grep -Fq 'ge_ramrom_gameplay_weapon_effect_integration_v6_smoke: PASS install=1' "${BUILD_ROOT}/strict.log"

echo "Building ASan gameplay/weapon-effect integration smoke"
"${CC}" "${CFLAGS[@]}" -fsanitize=address "${COMMON_SOURCES[@]}" "${SMOKE}" \
    -o "${BUILD_ROOT}/smoke-asan"
ASAN_OPTIONS=halt_on_error=1:detect_leaks=0 \
    "${BUILD_ROOT}/smoke-asan" "${RECORDING}" | tee "${BUILD_ROOT}/asan.log"
grep -Fq 'ge_ramrom_gameplay_weapon_effect_integration_v6_smoke: PASS install=1' "${BUILD_ROOT}/asan.log"

echo "Building UBSan gameplay/weapon-effect integration smoke"
"${CC}" "${CFLAGS[@]}" -fsanitize=undefined "${COMMON_SOURCES[@]}" "${SMOKE}" \
    -o "${BUILD_ROOT}/smoke-ubsan"
UBSAN_OPTIONS=halt_on_error=1 \
    "${BUILD_ROOT}/smoke-ubsan" "${RECORDING}" | tee "${BUILD_ROOT}/ubsan.log"
grep -Fq 'ge_ramrom_gameplay_weapon_effect_integration_v6_smoke: PASS install=1' "${BUILD_ROOT}/ubsan.log"

git -C "${ROOT}" diff --check
echo "Native RAMROM gameplay/weapon-effect integration V6 validation: PASS"
