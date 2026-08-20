#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="${PROJECT_ROOT}/build/native/fidelity-policy"
mkdir -p "${BUILD_DIR}"

SWIFTC=""
if command -v xcrun >/dev/null 2>&1; then
    SWIFTC=$(xcrun --sdk macosx --find swiftc 2>/dev/null || true)
fi
if [[ -z "${SWIFTC}" ]]; then
    SWIFTC=$(command -v swiftc || true)
fi
if [[ -z "${SWIFTC}" ]]; then
    echo "fidelity policy validation: swiftc unavailable" >&2
    exit 1
fi

SDKROOT=""
if command -v xcrun >/dev/null 2>&1; then
    SDKROOT=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)
fi

SWIFT_ARGS=(
    -swift-version 6
    -warnings-as-errors
    -target arm64-apple-macosx27.0
    "${PROJECT_ROOT}/native/host/goldeneye_fidelity_policy.swift"
    "${PROJECT_ROOT}/native/tests/goldeneye_fidelity_policy_smoke.swift"
    -o "${BUILD_DIR}/goldeneye_fidelity_policy_smoke"
)
if [[ -n "${SDKROOT}" ]]; then
    SWIFT_ARGS+=( -sdk "${SDKROOT}" )
fi

"${SWIFTC}" "${SWIFT_ARGS[@]}"
"${BUILD_DIR}/goldeneye_fidelity_policy_smoke" | tee "${BUILD_DIR}/fidelity-policy.log"
grep -Fq 'goldeneye_fidelity_policy_smoke: PASS' "${BUILD_DIR}/fidelity-policy.log"
echo 'Fidelity policy validation: PASS'
