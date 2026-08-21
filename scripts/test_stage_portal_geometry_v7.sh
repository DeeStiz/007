#!/bin/bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
STAGE_ROOT="${1:-${GOLDENEYE_NATIVE_STAGE_ASSET_ROOT:-${ROOT}/build/native/stage-assets-image-decoder-v6}}"
BUILD_ROOT="${ROOT}/build/native/stage-portal-geometry-v7"
MODULE_CACHE="${BUILD_ROOT}/module-cache"
mkdir -p "${BUILD_ROOT}" "${MODULE_CACHE}"
SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
ARGS=(-swift-version 6 -warnings-as-errors -target arm64-apple-macosx27.0 -sdk "${SDKROOT}")
SOURCES=(
  "${ROOT}/native/host/goldeneye_stage_setup_packet.swift"
  "${ROOT}/native/host/goldeneye_stage_portal_geometry_v7.swift"
  "${ROOT}/native/tests/goldeneye_stage_portal_geometry_v7_smoke.swift"
)
build_run() {
  local label="$1"
  shift
  local binary="${BUILD_ROOT}/goldeneye_stage_portal_geometry_v7_smoke_${label}"
  CLANG_MODULE_CACHE_PATH="${MODULE_CACHE}" "${SWIFTC}" "${ARGS[@]}" "$@" "${SOURCES[@]}" -o "${binary}"
  if [[ "${label}" == asan ]]; then
    ASAN_OPTIONS=halt_on_error=1:detect_leaks=0 "${binary}" "${STAGE_ROOT}" | tee "${BUILD_ROOT}/${label}.log"
  elif [[ "${label}" == ubsan ]]; then
    UBSAN_OPTIONS=halt_on_error=1 "${binary}" "${STAGE_ROOT}" | tee "${BUILD_ROOT}/${label}.log"
  else
    "${binary}" "${STAGE_ROOT}" | tee "${BUILD_ROOT}/${label}.log"
  fi
  grep -Fq 'goldeneye_stage_portal_geometry_v7_smoke: PASS stages=7 portals=612 deterministic=1 failClosed=1' "${BUILD_ROOT}/${label}.log"
}
build_run strict
build_run asan -sanitize=address
build_run ubsan -sanitize=undefined
git -C "${ROOT}" diff --check
echo 'Stage portal geometry V7 strict/ASan/UBSan validation: PASS'
