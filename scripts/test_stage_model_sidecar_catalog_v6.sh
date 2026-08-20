#!/bin/bash
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${1:-${GOLDENEYE_NATIVE_STAGE_ASSET_ROOT:-${ROOT}/build/native/stage-assets-image-decoder-v6}}"
BUILD_ROOT="${ROOT}/build/native/stage-model-sidecar-catalog-v6"
mkdir -p "${BUILD_ROOT}"
SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
"${SWIFTC}" -swift-version 6 -warnings-as-errors -target arm64-apple-macosx27.0 -sdk "${SDKROOT}" \
    "${ROOT}/native/host/goldeneye_source_model_v6.swift" \
    "${ROOT}/native/host/goldeneye_stage_model_sidecar_catalog_v6.swift" \
    "${ROOT}/native/host/goldeneye_ramrom_visible_dependency_catalog_v6.swift" \
    "${ROOT}/native/tests/goldeneye_stage_model_sidecar_catalog_v6_smoke.swift" \
    -o "${BUILD_ROOT}/smoke"
"${BUILD_ROOT}/smoke" "${ASSET_ROOT}" | tee "${BUILD_ROOT}/log.txt"
grep -Fq 'goldeneye_stage_model_sidecar_catalog_v6_smoke: PASS sidecars=179 complete=1 payloads=' "${BUILD_ROOT}/log.txt"
