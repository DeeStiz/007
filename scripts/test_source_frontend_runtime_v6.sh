#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_ROOT="${ROOT}/build/native/source-frontend-runtime-v6"
STRICT="${BUILD_ROOT}/strict"
SANITIZED="${BUILD_ROOT}/asan-ubsan"
mkdir -p "${STRICT}" "${SANITIZED}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CLANG=$(xcrun --sdk macosx --find clang)
SWIFTC=$(xcrun --sdk macosx --find swiftc)

COMMON_CFLAGS=(
    -std=c11
    -Wall -Wextra -Werror -pedantic
    -target arm64-apple-macosx27.0
    -isysroot "${SDKROOT}"
    -I "${ROOT}/native/include"
    -I "${ROOT}/native/source_port"
    -I "${ROOT}/native/source_port/original"
)

ORIGINAL_CFLAGS=(
    -std=gnu11
    -Wno-everything
    -I"${ROOT}"
    -I"${ROOT}/include"
    -I"${ROOT}/src"
    -I"${ROOT}/src/game"
    -I"${ROOT}/src/inflate"
    -I"${ROOT}/native/include"
    -I"${ROOT}/native/source_port"
    -I"${ROOT}/native/source_port/original"
    -isysroot "${SDKROOT}"
    -ffunction-sections
    -fdata-sections
)

ORIGINAL_DEFINES=(
    -D_LANGUAGE_C -DVERSION_US -DLANG_US -DREFRESH_NTSC
    -DLEFTOVERDEBUG -DLEFTOVERSPECTRUM -DBUGFIX_R0 -DBYTEMATCH
)

compile_runtime() {
    local output_root="$1"
    shift
    "${CLANG}" "${COMMON_CFLAGS[@]}" "$@" -O2 \
        -c "${ROOT}/native/src/ge_source_frontend_runtime_v6.c" \
        -o "${output_root}/runtime.o"
    "${CLANG}" "${COMMON_CFLAGS[@]}" "$@" -O2 \
        -c "${ROOT}/native/source_port/ge_source_frontend_v6.c" \
        -o "${output_root}/facade.o"
    "${CLANG}" "${COMMON_CFLAGS[@]}" "$@" -O2 \
        -c "${ROOT}/native/src/ge_file_mode_v6.c" \
        -o "${output_root}/file-mode.o"
    "${CLANG}" "${COMMON_CFLAGS[@]}" "$@" -O2 \
        -c "${ROOT}/native/tests/goldeneye_source_frontend_runtime_v6_smoke.c" \
        -o "${output_root}/smoke.o"
}

compile_original() {
    local output_root="$1"
    shift
    "${CLANG}" "${ORIGINAL_CFLAGS[@]}" "$@" -O0 \
        -c "${ROOT}/native/source_port/original/ge_original_front_c.c" \
        -o "${output_root}/front.o"
    "${CLANG}" "${ORIGINAL_CFLAGS[@]}" "$@" -O0 \
        -c "${ROOT}/native/source_port/original/ge_original_title_c.c" \
        -o "${output_root}/title.o"
    "${CLANG}" "${ORIGINAL_CFLAGS[@]}" "${ORIGINAL_DEFINES[@]}" "$@" -O0 \
        -c "${ROOT}/native/source_port/original/ge_original_frontend_v6.c" \
        -o "${output_root}/adapter.o"
    "${CLANG}" "${ORIGINAL_CFLAGS[@]}" "${ORIGINAL_DEFINES[@]}" "$@" -O0 \
        -c "${ROOT}/native/source_port/original/ge_original_host_stubs.c" \
        -o "${output_root}/stubs.o"
    "${CLANG}" "${ORIGINAL_CFLAGS[@]}" "${ORIGINAL_DEFINES[@]}" "$@" -O0 \
        -c "${ROOT}/native/source_port/original/ge_original_production_weak_stubs.c" \
        -o "${output_root}/weak-stubs.o"
}

link_c_smoke() {
    local output_root="$1"
    shift
    "${CLANG}" "${ORIGINAL_DEFINES[@]}" "${ORIGINAL_CFLAGS[@]}" "$@" \
        "${output_root}/runtime.o" "${output_root}/facade.o" \
        "${output_root}/smoke.o" "${output_root}/adapter.o" \
        "${output_root}/front.o" "${output_root}/title.o" "${output_root}/stubs.o" \
        "${output_root}/weak-stubs.o" \
        -Wl,-dead_strip -o "${output_root}/ge_source_frontend_runtime_v6_smoke"
}

compile_runtime "${STRICT}"
compile_original "${STRICT}"
link_c_smoke "${STRICT}"

"${STRICT}/ge_source_frontend_runtime_v6_smoke" \
    | tee "${STRICT}/runtime-value-only.log"
grep -Fq 'goldeneye_source_frontend_runtime_v6_smoke: PASS' \
    "${STRICT}/runtime-value-only.log"

set +e
"${STRICT}/ge_source_frontend_runtime_v6_smoke" --compare \
    > >(tee "${STRICT}/runtime-oracle-comparison.log") 2>&1
COMPARISON_STATUS=$?
set -e
if [[ "${COMPARISON_STATUS}" -eq 0 ]]; then
    echo 'source frontend V6 exact oracle comparison: PASS'
else
    grep -Fq 'source frontend V6 parity mismatch' \
        "${STRICT}/runtime-oracle-comparison.log"
    echo 'source frontend V6 exact oracle comparison: EXPLICIT GAP'
    echo 'The source facade and checked-in front.c/title.c oracle do not yet have identical even-anchor state.'
fi

compile_runtime "${SANITIZED}" -fsanitize=address,undefined -fno-omit-frame-pointer
compile_original "${SANITIZED}" -fsanitize=address,undefined -fno-omit-frame-pointer
link_c_smoke "${SANITIZED}" -fsanitize=address,undefined -fno-omit-frame-pointer
ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 \
    "${SANITIZED}/ge_source_frontend_runtime_v6_smoke" \
    | tee "${SANITIZED}/runtime-value-only.log"
grep -Fq 'goldeneye_source_frontend_runtime_v6_smoke: PASS' \
    "${SANITIZED}/runtime-value-only.log"

"${SWIFTC}" -sdk "${SDKROOT}" -target arm64-apple-macosx27.0 \
    -warnings-as-errors \
    -Xcc -I -Xcc "${ROOT}/native/include" \
    -Xcc -I -Xcc "${ROOT}/native/source_port" \
    -import-objc-header "${ROOT}/native/include/ge_source_frontend_runtime_v6.h" \
    "${ROOT}/native/host/save_store.swift" \
    "${ROOT}/native/host/goldeneye_file_mode_authority_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_frontend_authority_v6.swift" \
    "${ROOT}/native/tests/goldeneye_source_frontend_authority_v6_smoke.swift" \
    "${STRICT}/runtime.o" "${STRICT}/facade.o" "${STRICT}/file-mode.o" \
    -o "${STRICT}/goldeneye_source_frontend_authority_v6_smoke"
"${STRICT}/goldeneye_source_frontend_authority_v6_smoke" \
    | tee "${STRICT}/authority.log"
grep -Fq 'goldeneye_source_frontend_authority_v6_smoke: PASS' \
    "${STRICT}/authority.log"

if [[ "${COMPARISON_STATUS}" -ne 0 ]]; then
    echo 'Source frontend runtime V6 value-only and sanitizer validation: PASS'
    echo 'Source frontend runtime V6 oracle equality gate: BLOCKED (see runtime-oracle-comparison.log)'
    exit 1
fi

echo 'Source frontend runtime V6 strict/ASan/UBSan/Swift validation: PASS'
