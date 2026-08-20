#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_ROOT="${ROOT}/build/native/ramrom-weapon-source-pages-v6"
MODULE_CACHE="${BUILD_ROOT}/module-cache"
mkdir -p "${BUILD_ROOT}" "${MODULE_CACHE}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun --sdk macosx --find clang)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
CFLAGS=(-target arm64-apple-macosx27.0 -isysroot "${SDKROOT}" -std=c11 -Wall -Wextra -Werror -pedantic -O2
    -I "${ROOT}/native/include" -I "${ROOT}/native/source_port/gameplay_v6")
SWIFT_ARGS=(-swift-version 6 -warnings-as-errors -target arm64-apple-macosx27.0 -sdk "${SDKROOT}")
OWNER="${ROOT}/native/source_port/gameplay_v6/ge_weapon_effect_owner_v6.c"
PAGES="${ROOT}/native/source_port/gameplay_v6/ge_ramrom_weapon_source_pages_v6.c"
SMOKE="${ROOT}/native/tests/ge_ramrom_weapon_source_pages_v6_smoke.c"
"${CC}" "${CFLAGS[@]}" -c "${OWNER}" -o "${BUILD_ROOT}/ge_weapon_effect_owner_v6.o"
"${CC}" "${CFLAGS[@]}" -c "${PAGES}" -o "${BUILD_ROOT}/ge_ramrom_weapon_source_pages_v6.o"

echo "Building strict source weapon mapping/page owner smoke"
"${CC}" "${CFLAGS[@]}" "${OWNER}" "${PAGES}" "${SMOKE}" -o "${BUILD_ROOT}/c-smoke"
"${BUILD_ROOT}/c-smoke" | tee "${BUILD_ROOT}/c-strict.log"
grep -Fq 'ge_ramrom_weapon_source_pages_v6_smoke: PASS demos=14' "${BUILD_ROOT}/c-strict.log"

echo "Building ASan source weapon mapping/page owner smoke"
"${CC}" "${CFLAGS[@]}" -fsanitize=address "${OWNER}" "${PAGES}" "${SMOKE}" \
    -o "${BUILD_ROOT}/c-smoke-asan"
ASAN_OPTIONS=halt_on_error=1:detect_leaks=0 "${BUILD_ROOT}/c-smoke-asan" \
    | tee "${BUILD_ROOT}/c-asan.log"
grep -Fq 'ge_ramrom_weapon_source_pages_v6_smoke: PASS demos=14' "${BUILD_ROOT}/c-asan.log"

echo "Building UBSan source weapon mapping/page owner smoke"
"${CC}" "${CFLAGS[@]}" -fsanitize=undefined "${OWNER}" "${PAGES}" "${SMOKE}" \
    -o "${BUILD_ROOT}/c-smoke-ubsan"
UBSAN_OPTIONS=halt_on_error=1 "${BUILD_ROOT}/c-smoke-ubsan" \
    | tee "${BUILD_ROOT}/c-ubsan.log"
grep -Fq 'ge_ramrom_weapon_source_pages_v6_smoke: PASS demos=14' "${BUILD_ROOT}/c-ubsan.log"

echo "Building strict Swift source table/page adapter smoke"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE}" "${SWIFTC}" "${SWIFT_ARGS[@]}" \
    -import-objc-header "${ROOT}/native/tests/goldeneye_ramrom_weapon_source_pages_v6_bridging.h" \
    -Xcc "-I${ROOT}/native/include" -Xcc "-I${ROOT}/native/source_port/gameplay_v6" \
    "${ROOT}/native/host/goldeneye_ramrom_visible_dependency_catalog_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_model_v6.swift" \
    "${ROOT}/native/host/goldeneye_ramrom_weapon_asset_catalog_v6.swift" \
    "${ROOT}/native/host/goldeneye_ramrom_source_weapon_mapping_v6.swift" \
    "${ROOT}/native/host/goldeneye_ramrom_weapon_source_pages_v6.swift" \
    "${ROOT}/native/tests/goldeneye_ramrom_weapon_source_pages_v6_smoke.swift" \
    "${BUILD_ROOT}/ge_weapon_effect_owner_v6.o" "${BUILD_ROOT}/ge_ramrom_weapon_source_pages_v6.o" \
    -o "${BUILD_ROOT}/swift-smoke"
"${BUILD_ROOT}/swift-smoke" | tee "${BUILD_ROOT}/swift.log"
grep -Fq 'goldeneye_ramrom_weapon_source_pages_v6_smoke: PASS table=89' "${BUILD_ROOT}/swift.log"

git -C "${ROOT}" diff --check
echo "Native RAMROM weapon source mapping/page validation: PASS"
