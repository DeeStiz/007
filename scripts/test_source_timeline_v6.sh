#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
BUILD_DIR="${PROJECT_ROOT}/build/native/source-timeline-v6"
mkdir -p "${BUILD_DIR}"

if command -v xcrun >/dev/null 2>&1; then
    SWIFTC=$(xcrun --sdk macosx --find swiftc)
    SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
else
    SWIFTC=${SWIFTC:-swiftc}
    SDKROOT=${SDKROOT:-}
fi

SWIFT_FLAGS=(-O -target arm64-apple-macosx27.0)
if [ -n "${SDKROOT}" ]; then
    SWIFT_FLAGS+=(-sdk "${SDKROOT}")
fi

echo "Building strict source timeline V6 smoke"
"${SWIFTC}" "${SWIFT_FLAGS[@]}" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_timeline_v6.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_source_timeline_v6_smoke.swift" \
    -o "${BUILD_DIR}/goldeneye_source_timeline_v6_smoke"

"${BUILD_DIR}/goldeneye_source_timeline_v6_smoke" \
    | tee "${BUILD_DIR}/source-timeline-v6.log"

echo "source timeline V6 validation: PASS"
