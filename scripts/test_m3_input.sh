#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
BUILD_DIR="${PROJECT_ROOT}/build/native/m3"
MODULE_CACHE_DIR="${BUILD_DIR}/module-cache"
mkdir -p "${BUILD_DIR}" "${MODULE_CACHE_DIR}"

if command -v xcrun >/dev/null 2>&1; then
    SWIFTC=$(xcrun --sdk macosx --find swiftc)
    SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
else
    SWIFTC=${SWIFTC:-swiftc}
    SDKROOT=${SDKROOT:-}
fi

SWIFT_ARGS=(-target arm64-apple-macosx27.0)
if [ -n "${SDKROOT}" ]; then
    SWIFT_ARGS+=(-sdk "${SDKROOT}")
fi

cp "${PROJECT_ROOT}/native/tests/keyboard_input_smoke.swift" "${BUILD_DIR}/main.swift"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${SWIFTC}" \
    "${SWIFT_ARGS[@]}" \
    "${PROJECT_ROOT}/native/host/keyboard_input_state.swift" \
    "${BUILD_DIR}/main.swift" \
    -o "${BUILD_DIR}/keyboard_input_smoke"

"${BUILD_DIR}/keyboard_input_smoke"
echo "M3 keyboard input validation: PASS"
