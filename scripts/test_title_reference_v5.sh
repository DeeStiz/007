#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
BUILD_DIR="${PROJECT_ROOT}/build/native/title-reference-v5"
FIXTURE="${PROJECT_ROOT}/tests/fixtures/goldeneye_title_timebase.tsv"

mkdir -p "${BUILD_DIR}"

if ! rg -q '^fixture_version\t2$' "${FIXTURE}"; then
    echo "title timebase fixture version is not 2" >&2
    exit 1
fi
for required in \
    $'timebase\tnative_hz\t120' \
    $'timebase\treference_hz\t60' \
    $'timebase\tpair_numerator\t2' \
    $'timebase\tpair_denominator\t1' \
    $'timebase\taudio_sample_rate\t22050' \
    $'threshold\tlegal\tg_MenuTimer\t0\t+1\t>=\t241\t482' \
    $'threshold\tnintendo\tg_MenuTimer\t0\t+1\t>=\t501\t1002' \
    $'threshold\trareware\tintro_eye_counter\t0\t+1 postincrement\t>=260 then >=290\t260/290\t520/580' \
    $'threshold\tgunbarrel_route\tsource_mode_total\t0\tmode-derived\t>=\t682\t1364' \
    $'threshold\tgoldeneye_logo_cast\tg_MenuTimer\t0\t+1\t>\t180\t361' \
    $'threshold\tgoldeneye_logo_secondary\tg_MenuTimer\t0\t+1\t>\t90\t181' \
    $'threshold\tfile_select_idle\tg_MenuTimer\t0\t+1\t>=\t1801\t3602' \
    $'threshold\tcast\tg_MenuTimer\t0\t+1\t>=\t181\t362' \
    $'audio\t1\tfloor(native_tick*735/4)\t183\t1' \
    $'audio\t2\tfloor(native_tick*735/4)\t367\t0' \
    $'audio\t3\tfloor(native_tick*735/4)\t551\t1' \
    $'audio\t4\tfloor(native_tick*735/4)\t735\t0'; do
    if ! rg -Fq "${required}" "${FIXTURE}"; then
        echo "missing title timebase fixture row: ${required}" >&2
        exit 1
    fi
done

if ! rg -q '^transition\ttitle_screen\towner_delay\t\+4 reference frames\t\+8 native ticks\tpending screen enters after the owner delay$' "${FIXTURE}"; then
    echo "missing owner transition delay fixture row" >&2
    exit 1
fi

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
