#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${1:-${PROJECT_ROOT}/build/native/source-frontend-v6}"
BUILD_ROOT="${PROJECT_ROOT}/build/native/wallet-switch-text-v6"
mkdir -p "${BUILD_ROOT}" "${BUILD_ROOT}/module-cache"
export CLANG_MODULE_CACHE_PATH="${BUILD_ROOT}/module-cache"

if command -v xcrun >/dev/null 2>&1; then
    SWIFTC=$(xcrun --sdk macosx --find swiftc)
    SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
else
    SWIFTC=${SWIFTC:-swiftc}
    SDKROOT=${SDKROOT:-}
fi

SWIFT_FLAGS=(-swift-version 6 -warnings-as-errors -O)
if [[ -n "${SDKROOT}" ]]; then
    SWIFT_FLAGS+=(-target arm64-apple-macosx27.0 -sdk "${SDKROOT}")
fi

SOURCES=(
    "${PROJECT_ROOT}/native/host/goldeneye_source_model_v6.swift"
    "${PROJECT_ROOT}/native/host/goldeneye_wallet_switch_text_v6.swift"
    "${PROJECT_ROOT}/native/tests/goldeneye_wallet_switch_text_v6_smoke.swift"
)

STRICT="${BUILD_ROOT}/strict"
ASAN="${BUILD_ROOT}/asan"
LOG="${BUILD_ROOT}/wallet-switch-text-v6.log"

"${SWIFTC}" "${SWIFT_FLAGS[@]}" "${SOURCES[@]}" -o "${STRICT}"
"${STRICT}" "${ASSET_ROOT}" | tee "${LOG}"

"${SWIFTC}" "${SWIFT_FLAGS[@]}" -sanitize=address "${SOURCES[@]}" -o "${ASAN}"
"${ASAN}" "${ASSET_ROOT}" | tee -a "${LOG}"

grep -Fq 'wallet-switches=42 source-order=43 branch-manifest=PASS' "${LOG}"
grep -Fq 'goldeneye_wallet_switch_text_v6_smoke: PASS' "${LOG}"

echo 'Wallet source switch/text V6 validation: PASS (strict, ASan)'
echo "Artifact: ${LOG}"
