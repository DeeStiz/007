#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="${ROOT}/build/native/source-audio-binding-v6"
mkdir -p "${BUILD_DIR}"

if command -v xcrun >/dev/null 2>&1; then
    SWIFTC=$(xcrun --sdk macosx --find swiftc)
    SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
else
    SWIFTC=${SWIFTC:-swiftc}
    SDKROOT=${SDKROOT:-}
fi

FLAGS=(-swift-version 6 -warnings-as-errors -O -target arm64-apple-macosx27.0)
if [[ -n "${SDKROOT}" ]]; then
    FLAGS+=(-sdk "${SDKROOT}")
fi

"${SWIFTC}" "${FLAGS[@]}" \
    "${ROOT}/native/host/goldeneye_source_audio_binding_v6.swift" \
    "${ROOT}/native/tests/goldeneye_source_audio_binding_v6_smoke.swift" \
    -o "${BUILD_DIR}/goldeneye_source_audio_binding_v6_smoke"

"${BUILD_DIR}/goldeneye_source_audio_binding_v6_smoke" \
    | tee "${BUILD_DIR}/source-audio-binding-v6.log"
grep -Fq 'goldeneye_source_audio_binding_v6_smoke: PASS' \
    "${BUILD_DIR}/source-audio-binding-v6.log"

echo 'source audio binding V6 validation: PASS'
