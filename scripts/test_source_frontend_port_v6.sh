#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="${PROJECT_ROOT}/build/native/source-frontend-v6"
SOURCE="${PROJECT_ROOT}/native/source_port/ge_source_frontend_v6.c"
SMOKE="${PROJECT_ROOT}/native/source_port/ge_source_frontend_v6_smoke.c"
INCLUDE_DIR="${PROJECT_ROOT}/native/include"
SOURCE_PORT_DIR="${PROJECT_ROOT}/native/source_port"

mkdir -p "${BUILD_DIR}"

if command -v xcrun >/dev/null 2>&1; then
    CC=$(xcrun --sdk macosx --find clang)
    SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
else
    CC=${CC:-clang}
    SDKROOT=${SDKROOT:-}
fi

COMMON_CFLAGS=(-std=c11 -Wall -Wextra -Werror -pedantic -O2)
if [ -n "${SDKROOT}" ]; then
    COMMON_CFLAGS+=(-target arm64-apple-macosx27.0 -isysroot "${SDKROOT}")
fi
COMMON_CFLAGS+=(-I "${INCLUDE_DIR}" -I "${SOURCE_PORT_DIR}")

"${CC}" "${COMMON_CFLAGS[@]}" -c "${SOURCE}" \
    -o "${BUILD_DIR}/ge_source_frontend_v6.o"
"${CC}" "${COMMON_CFLAGS[@]}" "${SOURCE}" "${SMOKE}" \
    -o "${BUILD_DIR}/ge_source_frontend_v6_smoke"

"${BUILD_DIR}/ge_source_frontend_v6_smoke" \
    | tee "${BUILD_DIR}/source-frontend-v6.log"
grep -Fq 'ge_source_frontend_v6_smoke: PASS' \
    "${BUILD_DIR}/source-frontend-v6.log"

"${CC}" "${COMMON_CFLAGS[@]}" \
    -fsanitize=address,undefined -fno-omit-frame-pointer \
    "${SOURCE}" "${SMOKE}" \
    -o "${BUILD_DIR}/ge_source_frontend_v6_smoke_sanitized"

ASAN_OPTIONS=halt_on_error=1 \
UBSAN_OPTIONS=halt_on_error=1 \
    "${BUILD_DIR}/ge_source_frontend_v6_smoke_sanitized" \
    | tee "${BUILD_DIR}/source-frontend-v6-sanitized.log"
grep -Fq 'ge_source_frontend_v6_smoke: PASS' \
    "${BUILD_DIR}/source-frontend-v6-sanitized.log"

echo 'Source frontend V6 strict/ASan/UBSan validation: PASS'
