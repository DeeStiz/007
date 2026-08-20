#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="${PROJECT_ROOT}/build/native/rareware-frame-v6"
mkdir -p "${BUILD_DIR}"

GE_SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
GE_SWIFTC=$(xcrun --sdk macosx --find swiftc)

"${GE_SWIFTC}" \
    -swift-version 6 \
    -warnings-as-errors \
    -O \
    -target arm64-apple-macosx27.0 \
    -sdk "${GE_SDKROOT}" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_model_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_rareware_frame_v6.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_rareware_frame_v6_smoke.swift" \
    -o "${BUILD_DIR}/smoke"

"${BUILD_DIR}/smoke" "${PROJECT_ROOT}/build/native/source-frontend-v6" | tee "${BUILD_DIR}/strict.log"
grep -Fq 'goldeneye_rareware_frame_v6_smoke: PASS' "${BUILD_DIR}/strict.log"

"${GE_SWIFTC}" \
    -swift-version 6 \
    -warnings-as-errors \
    -O \
    -sanitize=address \
    -target arm64-apple-macosx27.0 \
    -sdk "${GE_SDKROOT}" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_model_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_rareware_frame_v6.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_rareware_frame_v6_smoke.swift" \
    -o "${BUILD_DIR}/smoke-asan"
ASAN_OPTIONS=halt_on_error=1 \
    "${BUILD_DIR}/smoke-asan" "${PROJECT_ROOT}/build/native/source-frontend-v6" \
    | tee "${BUILD_DIR}/asan.log"
grep -Fq 'goldeneye_rareware_frame_v6_smoke: PASS' "${BUILD_DIR}/asan.log"

# The source-specific contract must remain visibly distinct from the graph
# compiler's historical dynamic diagnostic.  These checks keep the capture
# lane honest if a later refactor tries to route Rareware through a fallback.
grep -Fq 'expectedCommandCount = 389' "${PROJECT_ROOT}/native/host/goldeneye_rareware_frame_v6.swift"
grep -Fq 'expectedMipChainCount = 4' "${PROJECT_ROOT}/native/host/goldeneye_rareware_frame_v6.swift"
grep -Fq 'hasLODGradient' "${PROJECT_ROOT}/native/host/goldeneye_rareware_frame_v6.swift"
grep -Fq 'rarewareSFXAssetID' "${PROJECT_ROOT}/native/host/goldeneye_rareware_frame_v6.swift"

git -C "${PROJECT_ROOT}" diff --check -- \
    native/host/goldeneye_rareware_frame_v6.swift \
    native/tests/goldeneye_rareware_frame_v6_smoke.swift \
    scripts/test_rareware_frame_v6.sh

echo 'Rareware source frame V6 validation: PASS'
echo "Artifact: ${BUILD_DIR}/strict.log"
