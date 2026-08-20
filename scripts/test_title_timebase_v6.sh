#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_ROOT="${ROOT}/build/native/title-timebase-v6"
STRICT="${BUILD_ROOT}/strict"
SANITIZED="${BUILD_ROOT}/asan-ubsan"
mkdir -p "${STRICT}" "${SANITIZED}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CLANG=$(xcrun --sdk macosx --find clang)
SWIFTC=$(xcrun --sdk macosx --find swiftc)

CFLAGS=(
    -std=c11 -Wall -Wextra -Werror -pedantic
    -target arm64-apple-macosx27.0 -isysroot "${SDKROOT}"
    -I "${ROOT}/native/include"
    -I "${ROOT}/native/source_port"
)

build_c() {
    local output_root="$1"
    shift
    "${CLANG}" "${CFLAGS[@]}" "$@" -O2 \
        -c "${ROOT}/native/source_port/ge_source_frontend_v6.c" \
        -o "${output_root}/facade.o"
    "${CLANG}" "${CFLAGS[@]}" "$@" -O2 \
        -c "${ROOT}/native/src/ge_file_mode_v6.c" \
        -o "${output_root}/file-mode.o"
    "${CLANG}" "${CFLAGS[@]}" "$@" -O2 \
        -c "${ROOT}/native/tests/goldeneye_title_timebase_v6_smoke.c" \
        -o "${output_root}/smoke.o"
    "${CLANG}" "${CFLAGS[@]}" "$@" \
        "${output_root}/facade.o" "${output_root}/smoke.o" \
        -o "${output_root}/goldeneye_title_timebase_v6_smoke"
}

build_c "${STRICT}"
"${STRICT}/goldeneye_title_timebase_v6_smoke" | tee "${STRICT}/c.log"
grep -Fq 'goldeneye_title_timebase_v6_smoke: PASS' "${STRICT}/c.log"

build_c "${SANITIZED}" -fsanitize=address,undefined -fno-omit-frame-pointer
ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 \
    "${SANITIZED}/goldeneye_title_timebase_v6_smoke" | tee "${SANITIZED}/c.log"
grep -Fq 'goldeneye_title_timebase_v6_smoke: PASS' "${SANITIZED}/c.log"

    "${CLANG}" "${CFLAGS[@]}" -O2 \
        -c "${ROOT}/native/src/ge_source_frontend_runtime_v6.c" \
        -o "${STRICT}/runtime.o"
"${CLANG}" "${CFLAGS[@]}" -O2 \
    -c "${ROOT}/native/src/ge_file_mode_v6.c" \
    -o "${STRICT}/file-mode.o"
"${SWIFTC}" -sdk "${SDKROOT}" -target arm64-apple-macosx27.0 \
    -warnings-as-errors \
    -Xcc -I -Xcc "${ROOT}/native/include" \
    -Xcc -I -Xcc "${ROOT}/native/source_port" \
    -import-objc-header "${ROOT}/native/include/ge_source_frontend_runtime_v6.h" \
    "${ROOT}/native/host/save_store.swift" \
    "${ROOT}/native/host/goldeneye_file_mode_authority_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_frontend_authority_v6.swift" \
    "${ROOT}/native/tests/goldeneye_title_timebase_v6_smoke.swift" \
    "${STRICT}/runtime.o" "${STRICT}/facade.o" "${STRICT}/file-mode.o" \
    -o "${STRICT}/goldeneye_title_timebase_v6_swift_smoke"
"${STRICT}/goldeneye_title_timebase_v6_swift_smoke" | tee "${STRICT}/swift.log"
grep -Fq 'goldeneye_title_timebase_v6_swift_smoke: PASS' "${STRICT}/swift.log"

FIXTURE="${ROOT}/tests/fixtures/goldeneye_title_timebase.tsv"
[[ -s "${FIXTURE}" ]]
grep -Fq 'nintendo_rotation' "${FIXTURE}"
grep -Fq 'gunbarrel_model_substeps' "${FIXTURE}"
grep -Fq $'menu_cursor\tfront.c:interface_menu05_fileselect\tpaired midpoint on odd render' "${FIXTURE}"
grep -Fq $'mode_cursor\tfront.c:interface_menu06_modeselect\tpaired midpoint on odd render' "${FIXTURE}"
grep -Fq $'file_idle_timer\tfront.c:interface_menu05_fileselect\tanchor-only' "${FIXTURE}"

echo 'test_title_timebase_v6: PASS'
echo "evidence=${BUILD_ROOT}"
