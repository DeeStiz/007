#!/bin/bash
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${1:-${GOLDENEYE_NATIVE_STAGE_ASSET_ROOT:-${PROJECT_ROOT}/build/native/stage-assets-image-decoder-v6}}"
BUILD_DIR="${PROJECT_ROOT}/build/native/stage-setup-packet"
MODULE_CACHE_DIR="${BUILD_DIR}/module-cache"
mkdir -p "${BUILD_DIR}" "${MODULE_CACHE_DIR}"
SWIFTC=$(xcrun --sdk macosx --find swiftc)
SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
SWIFT_ARGS=(-swift-version 6 -warnings-as-errors -target arm64-apple-macosx27.0 -sdk "${SDKROOT}")
SMOKE="${BUILD_DIR}/goldeneye_stage_setup_packet_smoke"
SANITIZED="${BUILD_DIR}/goldeneye_stage_setup_packet_smoke_asan"
UBSAN="${BUILD_DIR}/goldeneye_stage_setup_packet_smoke_ubsan"

echo "Building strict Swift setup/portal packet smoke"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${SWIFTC}" "${SWIFT_ARGS[@]}" \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_setup_packet.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_stage_setup_semantics_smoke.swift" \
    -o "${SMOKE}"
"${SMOKE}" "${ASSET_ROOT}" | tee "${BUILD_DIR}/stage-setup-packet.log"
grep -Fq 'goldeneye_stage_setup_semantics_smoke: PASS stages=7' "${BUILD_DIR}/stage-setup-packet.log"

echo "Building ASan Swift setup/portal packet smoke"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${SWIFTC}" "${SWIFT_ARGS[@]}" \
    -sanitize=address \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_setup_packet.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_stage_setup_packet_smoke.swift" \
    -o "${SANITIZED}"
ASAN_OPTIONS=halt_on_error=1:detect_leaks=0 "${SANITIZED}" "${ASSET_ROOT}" \
    | tee "${BUILD_DIR}/stage-setup-packet-asan.log"
grep -Fq 'goldeneye_stage_setup_packet_smoke: PASS stages=7' \
    "${BUILD_DIR}/stage-setup-packet-asan.log"

echo "Building UBSan Swift setup/portal packet smoke"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${SWIFTC}" "${SWIFT_ARGS[@]}" \
    -sanitize=undefined \
    "${PROJECT_ROOT}/native/host/goldeneye_stage_setup_packet.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_stage_setup_packet_smoke.swift" \
    -o "${UBSAN}"
UBSAN_OPTIONS=halt_on_error=1 "${UBSAN}" "${ASSET_ROOT}" \
    | tee "${BUILD_DIR}/stage-setup-packet-ubsan.log"
grep -Fq 'goldeneye_stage_setup_packet_smoke: PASS stages=7' \
    "${BUILD_DIR}/stage-setup-packet-ubsan.log"

echo 'Stage setup packet validation: PASS'
