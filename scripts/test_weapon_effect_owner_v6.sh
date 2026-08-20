#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
VISIBLE_ROOT="${1:-${GOLDENEYE_NATIVE_RAMROM_VISIBLE_ROOT:-${ROOT}/build/native/ramrom-visible-dependencies-v6}}"
BUILD_ROOT="${ROOT}/build/native/weapon-effect-owner-v6"
MODULE_CACHE="${BUILD_ROOT}/module-cache"
mkdir -p "${BUILD_ROOT}" "${MODULE_CACHE}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun --sdk macosx --find clang)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
CFLAGS=(-target arm64-apple-macosx27.0 -isysroot "${SDKROOT}" -std=c11 -Wall -Wextra -Werror -pedantic -O2
    -I "${ROOT}/native/include" -I "${ROOT}/native/source_port/gameplay_v6")
SWIFT_ARGS=(-swift-version 6 -warnings-as-errors -target arm64-apple-macosx27.0 -sdk "${SDKROOT}")

OWNER_SOURCE="${ROOT}/native/source_port/gameplay_v6/ge_weapon_effect_owner_v6.c"
OWNER_SMOKE="${ROOT}/native/tests/ge_weapon_effect_owner_v6_smoke.c"
OWNER_OBJECT="${BUILD_ROOT}/ge_weapon_effect_owner_v6.o"

echo "Building strict source weapon/effect owner V6 smoke"
"${CC}" "${CFLAGS[@]}" -c "${OWNER_SOURCE}" -o "${OWNER_OBJECT}"
"${CC}" "${CFLAGS[@]}" "${OWNER_SOURCE}" "${OWNER_SMOKE}" -o "${BUILD_ROOT}/ge_weapon_effect_owner_v6_smoke"
"${BUILD_ROOT}/ge_weapon_effect_owner_v6_smoke" | tee "${BUILD_ROOT}/c-strict.log"
grep -Fq 'ge_weapon_effect_owner_v6_smoke: PASS demos=14' "${BUILD_ROOT}/c-strict.log"

echo "Building ASan source weapon/effect owner V6 smoke"
"${CC}" "${CFLAGS[@]}" -fsanitize=address "${OWNER_SOURCE}" "${OWNER_SMOKE}" \
    -o "${BUILD_ROOT}/ge_weapon_effect_owner_v6_smoke_asan"
ASAN_OPTIONS=halt_on_error=1:detect_leaks=0 \
    "${BUILD_ROOT}/ge_weapon_effect_owner_v6_smoke_asan" | tee "${BUILD_ROOT}/c-asan.log"
grep -Fq 'ge_weapon_effect_owner_v6_smoke: PASS demos=14' "${BUILD_ROOT}/c-asan.log"

echo "Building UBSan source weapon/effect owner V6 smoke"
"${CC}" "${CFLAGS[@]}" -fsanitize=undefined "${OWNER_SOURCE}" "${OWNER_SMOKE}" \
    -o "${BUILD_ROOT}/ge_weapon_effect_owner_v6_smoke_ubsan"
UBSAN_OPTIONS=halt_on_error=1 \
    "${BUILD_ROOT}/ge_weapon_effect_owner_v6_smoke_ubsan" | tee "${BUILD_ROOT}/c-ubsan.log"
grep -Fq 'ge_weapon_effect_owner_v6_smoke: PASS demos=14' "${BUILD_ROOT}/c-ubsan.log"

echo "Building strict Swift value-only adapter smoke"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE}" "${SWIFTC}" "${SWIFT_ARGS[@]}" \
    -import-objc-header "${ROOT}/native/tests/goldeneye_weapon_effect_owner_v6_bridging.h" \
    -Xcc "-I${ROOT}/native/include" -Xcc "-I${ROOT}/native/source_port/gameplay_v6" \
    "${ROOT}/native/host/goldeneye_ramrom_non_model_visuals_v6.swift" \
    "${ROOT}/native/host/goldeneye_ramrom_weapon_effect_owner_v6.swift" \
    "${ROOT}/native/tests/goldeneye_ramrom_weapon_effect_owner_v6_smoke.swift" \
    "${OWNER_OBJECT}" -o "${BUILD_ROOT}/goldeneye_ramrom_weapon_effect_owner_v6_smoke"
"${BUILD_ROOT}/goldeneye_ramrom_weapon_effect_owner_v6_smoke" "${VISIBLE_ROOT}" \
    | tee "${BUILD_ROOT}/swift.log"
grep -Fq 'goldeneye_ramrom_weapon_effect_owner_v6_smoke: PASS adapter=1' "${BUILD_ROOT}/swift.log"

git -C "${ROOT}" diff --check
echo "Native weapon/effect/HUD source owner V6 validation: PASS"
