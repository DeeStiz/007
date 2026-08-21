#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
BUILD_DIR="${PROJECT_ROOT}/build/native/title-reference-v5"
FIXTURE="${PROJECT_ROOT}/tests/fixtures/goldeneye_title_timebase.tsv"

mkdir -p "${BUILD_DIR}"

if ! rg -q $'^field\tsource_owner\tnative_policy\tsource_comparator\tendpoint_or_quantization$' "${FIXTURE}"; then
    echo "title timebase fixture has an unexpected schema" >&2
    exit 1
fi
for required in \
    $'menu_timer\tfront.c:g_MenuTimer\tanchor-only' \
    $'switch_timer\tfront.c:interface_menu17_switchscreens\tanchor-only' \
    $'nintendo_rotation\tfront.c:constructor_menu01_nintendo:ninLogoRotRate\tmidpoint on odd render' \
    $'rareware_counter\ttitle.c:retrieve_display_rareware_logo:intro_eye_counter\tanchor-only' \
    $'gunbarrel_title_x\ttitle.c:renderGunbarrelEyeIntroSequence:g_TitleX\tmidpoint on odd render' \
    $'goldeneye_logo\tfront.c:interface_menu04_goldeneyelogo\tstatic/exempt' \
    $'mode_cursor\tfront.c:interface_menu06_modeselect\tpaired midpoint on odd render' \
    $'file_idle_timer\tfront.c:interface_menu05_fileselect\tanchor-only'; do
    if ! grep -Fq "${required}" "${FIXTURE}"; then
        echo "missing title timebase fixture row: ${required}" >&2
        exit 1
    fi
done

if command -v xcrun >/dev/null 2>&1; then
    CC=$(xcrun --sdk macosx --find clang)
    SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
else
    CC=${CC:-clang}
    SDKROOT=${SDKROOT:-}
fi

COMMON_CFLAGS=(-target arm64-apple-macosx27.0)
if [ -n "${SDKROOT}" ]; then
    COMMON_CFLAGS+=(-isysroot "${SDKROOT}")
fi
COMMON_CFLAGS+=(-std=c11 -Wall -Wextra -Werror -pedantic)

"${CC}" "${COMMON_CFLAGS[@]}" \
    -I "${PROJECT_ROOT}/native/include" \
    -I "${PROJECT_ROOT}/native/tests" \
    -c "${PROJECT_ROOT}/native/tests/ge_title_reference_v5.c" \
    -o "${BUILD_DIR}/ge_title_reference_v5.o"

"${CC}" "${COMMON_CFLAGS[@]}" \
    -I "${PROJECT_ROOT}/native/include" \
    -c "${PROJECT_ROOT}/native/src/ge_ramrom_v5.c" \
    -o "${BUILD_DIR}/ge_ramrom_v5.o"

"${CC}" "${COMMON_CFLAGS[@]}" \
    -I "${PROJECT_ROOT}/native/include" \
    -I "${PROJECT_ROOT}/native/tests" \
    "${PROJECT_ROOT}/native/tests/ge_title_reference_v5.c" \
    "${PROJECT_ROOT}/native/tests/goldeneye_title_timebase_v5_smoke.c" \
    -o "${BUILD_DIR}/goldeneye_title_timebase_v5_smoke"

"${BUILD_DIR}/goldeneye_title_timebase_v5_smoke" \
    | tee "${BUILD_DIR}/title-timebase-v5.log"

"${CC}" "${COMMON_CFLAGS[@]}" \
    -fsanitize=address,undefined -fno-omit-frame-pointer \
    -I "${PROJECT_ROOT}/native/include" \
    -I "${PROJECT_ROOT}/native/tests" \
    "${PROJECT_ROOT}/native/tests/ge_title_reference_v5.c" \
    "${PROJECT_ROOT}/native/tests/goldeneye_title_timebase_v5_smoke.c" \
    -o "${BUILD_DIR}/goldeneye_title_timebase_v5_smoke_sanitized"

ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 \
    "${BUILD_DIR}/goldeneye_title_timebase_v5_smoke_sanitized" \
    | tee "${BUILD_DIR}/title-timebase-v5-sanitized.log"

swiftc -O \
    -Xcc -I -Xcc "${PROJECT_ROOT}/native/include" \
    -Xcc -I -Xcc "${PROJECT_ROOT}/native/tests" \
    -import-objc-header "${PROJECT_ROOT}/native/tests/ge_title_reference_v5_bridging.h" \
    "${PROJECT_ROOT}/native/host/save_store.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_timeline_v6.swift" \
    "${PROJECT_ROOT}/native/host/display_link_runtime.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_attract_route.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_cast_title_hash.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_boot_flow.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_title_reference_v5_smoke.swift" \
    "${BUILD_DIR}/ge_title_reference_v5.o" \
    "${BUILD_DIR}/ge_ramrom_v5.o" \
    -o "${BUILD_DIR}/goldeneye_title_reference_v5_smoke"

"${BUILD_DIR}/goldeneye_title_reference_v5_smoke" \
    | tee "${BUILD_DIR}/title-reference-v5.log"

echo "title reference V5 validation: PASS"
