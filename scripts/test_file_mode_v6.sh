#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_ROOT="${ROOT}/build/native/file-mode-v6"
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
)

compile_c() {
    local output_root="$1"
    shift
    "${CLANG}" "${COMMON_CFLAGS[@]}" "$@" -O2 \
        -c "${ROOT}/native/src/ge_file_mode_v6.c" \
        -o "${output_root}/ge_file_mode_v6.o"
    "${CLANG}" "${COMMON_CFLAGS[@]}" "$@" -O2 \
        -c "${ROOT}/native/tests/goldeneye_file_mode_v6_smoke.c" \
        -o "${output_root}/goldeneye_file_mode_v6_smoke.o"
    "${CLANG}" "${COMMON_CFLAGS[@]}" "$@" \
        "${output_root}/ge_file_mode_v6.o" \
        "${output_root}/goldeneye_file_mode_v6_smoke.o" \
        -o "${output_root}/goldeneye_file_mode_v6_smoke"
}

compile_c "${STRICT}"
"${STRICT}/goldeneye_file_mode_v6_smoke" \
    | tee "${STRICT}/c.log"
grep -Fq 'goldeneye_file_mode_v6_smoke: PASS' "${STRICT}/c.log"

compile_c "${SANITIZED}" -fsanitize=address,undefined -fno-omit-frame-pointer
ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 \
    "${SANITIZED}/goldeneye_file_mode_v6_smoke" \
    | tee "${SANITIZED}/c.log"
grep -Fq 'goldeneye_file_mode_v6_smoke: PASS' "${SANITIZED}/c.log"

"${SWIFTC}" -sdk "${SDKROOT}" -target arm64-apple-macosx27.0 \
    -warnings-as-errors \
    -Xcc -I -Xcc "${ROOT}/native/include" \
    -import-objc-header "${ROOT}/native/include/ge_file_mode_v6.h" \
    "${ROOT}/native/host/save_store.swift" \
    "${ROOT}/native/host/goldeneye_file_mode_authority_v6.swift" \
    "${ROOT}/native/tests/goldeneye_file_mode_authority_v6_smoke.swift" \
    "${STRICT}/ge_file_mode_v6.o" \
    -o "${STRICT}/goldeneye_file_mode_authority_v6_smoke"
"${STRICT}/goldeneye_file_mode_authority_v6_smoke" \
    | tee "${STRICT}/swift.log"
grep -Fq 'goldeneye_file_mode_authority_v6_smoke: PASS' "${STRICT}/swift.log"

"${SWIFTC}" -sdk "${SDKROOT}" -target arm64-apple-macosx27.0 \
    -warnings-as-errors \
    -Xcc -I -Xcc "${ROOT}/native/include" \
    -import-objc-header "${ROOT}/native/include/ge_file_mode_v6.h" \
    "${ROOT}/native/host/save_store.swift" \
    "${ROOT}/native/host/goldeneye_file_mode_authority_v6.swift" \
    "${ROOT}/native/tests/goldeneye_file_mode_paired_v6_smoke.swift" \
    "${STRICT}/ge_file_mode_v6.o" \
    -o "${STRICT}/goldeneye_file_mode_paired_v6_smoke"
"${STRICT}/goldeneye_file_mode_paired_v6_smoke" \
    | tee "${STRICT}/paired.log"
grep -Fq 'goldeneye_file_mode_paired_v6_smoke: PASS' "${STRICT}/paired.log"

echo 'File/Mode V6 strict/ASan/UBSan/Swift validation: PASS'
