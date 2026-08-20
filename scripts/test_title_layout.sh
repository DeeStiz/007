#!/bin/bash
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="${PROJECT_ROOT}/build/native/title-layout"
mkdir -p "${BUILD_DIR}"
swiftc -swift-version 6 -warnings-as-errors -target arm64-apple-macosx27.0 \
    "${PROJECT_ROOT}/native/host/goldeneye_title_layout.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_title_layout_smoke.swift" \
    -o "${BUILD_DIR}/goldeneye_title_layout_smoke"
"${BUILD_DIR}/goldeneye_title_layout_smoke" | tee "${BUILD_DIR}/title-layout.log"
grep -Fq 'goldeneye_title_layout_smoke: PASS' "${BUILD_DIR}/title-layout.log"
echo 'Title layout validation: PASS'
