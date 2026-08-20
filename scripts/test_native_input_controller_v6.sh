#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_ROOT="${PROJECT_ROOT}/build/native/input-controller-v6"
MODULE_CACHE="${BUILD_ROOT}/module-cache"
mkdir -p "${MODULE_CACHE}"

if command -v xcrun >/dev/null 2>&1; then
    SWIFTC=$(xcrun --sdk macosx --find swiftc)
    SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
    SWIFT_PLATFORM=(-target arm64-apple-macosx27.0 -sdk "${SDKROOT}")
else
    SWIFTC=${SWIFTC:-swiftc}
    SWIFT_PLATFORM=()
fi

export CLANG_MODULE_CACHE_PATH="${MODULE_CACHE}"
MAILBOX="${PROJECT_ROOT}/native/host/native_input_mailbox.swift"
SMOKE="${PROJECT_ROOT}/native/tests/goldeneye_native_input_controller_v6_smoke.swift"

build_and_run() {
    local suffix="$1"
    shift
    local output="${BUILD_ROOT}/goldeneye_native_input_controller_v6_smoke${suffix}"
    "${SWIFTC}" -swift-version 6 -warnings-as-errors -O -parse-as-library \
        "${SWIFT_PLATFORM[@]}" "${MAILBOX}" "${SMOKE}" "$@" \
        -o "${output}"
    "${output}" | tee "${BUILD_ROOT}/input-controller-v6${suffix}.log"
    grep -Fq 'goldeneye_native_input_controller_v6_smoke: PASS' \
        "${BUILD_ROOT}/input-controller-v6${suffix}.log"
}

build_and_run ""
build_and_run "_asan" -sanitize=address
ASAN_OPTIONS=halt_on_error=1 "${BUILD_ROOT}/goldeneye_native_input_controller_v6_smoke_asan" \
    | tee "${BUILD_ROOT}/input-controller-v6_asan-rerun.log"
grep -Fq 'goldeneye_native_input_controller_v6_smoke: PASS' \
    "${BUILD_ROOT}/input-controller-v6_asan-rerun.log"

build_and_run "_ubsan" -sanitize=undefined
UBSAN_OPTIONS=halt_on_error=1 "${BUILD_ROOT}/goldeneye_native_input_controller_v6_smoke_ubsan" \
    | tee "${BUILD_ROOT}/input-controller-v6_ubsan-rerun.log"
grep -Fq 'goldeneye_native_input_controller_v6_smoke: PASS' \
    "${BUILD_ROOT}/input-controller-v6_ubsan-rerun.log"

# Keep the existing mailbox smoke in the same strict lane, including its
# timestamp gating, overflow and keyboard-repeat coverage.
LEGACY="${BUILD_ROOT}/goldeneye_native_input_mailbox_smoke"
"${SWIFTC}" -swift-version 6 -warnings-as-errors -O -parse-as-library \
    "${SWIFT_PLATFORM[@]}" "${MAILBOX}" \
    "${PROJECT_ROOT}/native/tests/goldeneye_native_input_mailbox_smoke.swift" \
    -o "${LEGACY}"
"${LEGACY}" | tee "${BUILD_ROOT}/input-mailbox-legacy.log"
grep -Fq 'goldeneye_native_input_mailbox_smoke: PASS' \
    "${BUILD_ROOT}/input-mailbox-legacy.log"

# These are source-level guardrails for the Apple path. The headless smoke
# cannot manufacture a physical GCController, so runtime device proof remains
# a separate acceptance artifact.
grep -Fq 'inputStateQueueDepth = 20' "${MAILBOX}"
grep -Fq 'nextInputState()' "${MAILBOX}"
grep -Fq 'state.dpads[.directionPad]' "${MAILBOX}"
grep -Fq 'dpad.up.isPressed' "${MAILBOX}"

echo "Native input controller V6 strict/ASan/UBSan validation: PASS"
