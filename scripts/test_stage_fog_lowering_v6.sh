#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="${ROOT}/build/native/stage-fog-lowering-v6"
MODULE_CACHE_DIR="${BUILD_DIR}/module-cache"
mkdir -p "${BUILD_DIR}" "${MODULE_CACHE_DIR}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
SWIFT_ARGS=(-swift-version 6 -warnings-as-errors -target arm64-apple-macosx27.0 -sdk "${SDKROOT}")

build_and_run() {
    local label="$1"
    local sanitizer="$2"
    local binary="${BUILD_DIR}/fog-lowering-${label}"
    if [[ -n "${sanitizer}" ]]; then
        CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${SWIFTC}" \
            "${SWIFT_ARGS[@]}" -sanitize="${sanitizer}" \
            "${ROOT}/native/host/goldeneye_stage_fog_lowering_v6.swift" \
            "${ROOT}/native/tests/goldeneye_stage_fog_lowering_v6_smoke.swift" \
            -o "${binary}"
    else
        CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${SWIFTC}" \
            "${SWIFT_ARGS[@]}" \
            "${ROOT}/native/host/goldeneye_stage_fog_lowering_v6.swift" \
            "${ROOT}/native/tests/goldeneye_stage_fog_lowering_v6_smoke.swift" \
            -o "${binary}"
    fi
    if [[ "${label}" == "asan" ]]; then
        ASAN_OPTIONS=halt_on_error=1:detect_leaks=0 "${binary}" | tee "${binary}.log"
    elif [[ "${label}" == "ubsan" ]]; then
        UBSAN_OPTIONS=halt_on_error=1 "${binary}" | tee "${binary}.log"
    else
        "${binary}" | tee "${binary}.log"
    fi
    grep -Fq 'goldeneye_stage_fog_lowering_v6_smoke: PASS stages=7 enabled=4' "${binary}.log"
}

build_and_run strict ""
build_and_run asan address
build_and_run ubsan undefined
echo 'Stage source fog lowering strict/ASan/UBSan validation: PASS'
