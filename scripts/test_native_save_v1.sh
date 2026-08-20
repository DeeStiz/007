#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_ROOT="${ROOT}/build/native/save-v1"
mkdir -p "${BUILD_ROOT}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
SWIFT_FLAGS=(
    -swift-version 6
    -warnings-as-errors
    -target arm64-apple-macosx27.0
    -sdk "${SDKROOT}"
)

"${SWIFTC}" "${SWIFT_FLAGS[@]}" \
    "${ROOT}/native/host/save_store.swift" \
    "${ROOT}/native/tests/goldeneye_save_store_smoke.swift" \
    -o "${BUILD_ROOT}/save-store-smoke"
"${BUILD_ROOT}/save-store-smoke" | tee "${BUILD_ROOT}/save-store.log"
grep -Fq 'goldeneye_save_store_smoke: PASS' "${BUILD_ROOT}/save-store.log"

"${SWIFTC}" "${SWIFT_FLAGS[@]}" \
    "${ROOT}/native/host/save_store.swift" \
    "${ROOT}/native/host/native_save_runtime.swift" \
    "${ROOT}/native/tests/goldeneye_save_runtime_smoke.swift" \
    -o "${BUILD_ROOT}/save-runtime-smoke"
"${BUILD_ROOT}/save-runtime-smoke" | tee "${BUILD_ROOT}/save-runtime.log"
grep -Fq 'goldeneye_save_runtime_smoke: PASS' "${BUILD_ROOT}/save-runtime.log"

echo 'Native GESWSAVE V1 store/runtime validation: PASS'
