#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${1:-${GOLDENEYE_NATIVE_SOURCE_FRONTEND_ROOT:-${PROJECT_ROOT}/build/native/source-frontend-v6}}"
BUILD_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/goldeneye-source-2d-v6.XXXXXX")
trap 'if [[ "${GOLDENEYE_KEEP_TEST_BUILD:-0}" != 1 ]]; then rm -rf "${BUILD_ROOT}"; fi' EXIT

if command -v xcrun >/dev/null 2>&1; then
    SWIFTC=$(xcrun --sdk macosx --find swiftc)
    CC=$(xcrun --sdk macosx --find clang)
    SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
    SWIFT_PLATFORM=(-target arm64-apple-macosx27.0 -sdk "${SDKROOT}")
else
    SWIFTC=${SWIFTC:-swiftc}
    CC=${CC:-cc}
    SWIFT_PLATFORM=()
fi

"${CC}" -std=c11 -Wall -Wextra -Werror -Wno-c23-extensions -pedantic \
    -target arm64-apple-macosx27.0 -isysroot "${SDKROOT:-}" \
    -I "${PROJECT_ROOT}/native/include" -I "${PROJECT_ROOT}/native/source_port" \
    -c "${PROJECT_ROOT}/native/src/ge_file_mode_v6.c" \
    -o "${BUILD_ROOT}/ge_file_mode_v6.o"

"${SWIFTC}" -swift-version 6 -warnings-as-errors -Onone -parse-as-library \
    "${SWIFT_PLATFORM[@]}" \
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_native_bridging.h" \
    -Xcc -I -Xcc "${PROJECT_ROOT}/native/include" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_catalog_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_model_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_2d_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_file_mode_background_v6.swift" \
    "${PROJECT_ROOT}/native/host/save_store.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_file_mode_authority_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_wallet_switch_text_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_2d_file_mode_v6.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_source_2d_v6_smoke.swift" \
    "${BUILD_ROOT}/ge_file_mode_v6.o" \
    -o "${BUILD_ROOT}/goldeneye_source_2d_v6_smoke"

"${BUILD_ROOT}/goldeneye_source_2d_v6_smoke" "${ASSET_ROOT}" | tee "${BUILD_ROOT}/valid.log"
grep -Fq 'goldeneye_source_2d_v6_smoke: PASS' "${BUILD_ROOT}/valid.log"
grep -Fq 'preparation_gap=none' "${BUILD_ROOT}/valid.log"
grep -Fq 'file=SELECTFILE_payload_nonzero=true' "${BUILD_ROOT}/valid.log"

echo "Source frontend V6 2D/text payload, layout, icon, font and fail-closed validation: PASS"
