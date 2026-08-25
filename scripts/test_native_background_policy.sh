#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
MAIN="${PROJECT_ROOT}/native/host/main.swift"
RUNNER="${SCRIPT_DIR}/run_native_boot.sh"
MEASURE="${SCRIPT_DIR}/measure_native_runtime.sh"
POLICY="${PROJECT_ROOT}/native/host/native_window_policy.swift"
POLICY_SMOKE="${PROJECT_ROOT}/native/tests/goldeneye_native_window_policy_smoke.swift"
BUILD_DIR="${PROJECT_ROOT}/build/native/window-policy"

mkdir -p "${BUILD_DIR}"
SWIFTC=$(xcrun --sdk macosx --find swiftc)
SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
"${SWIFTC}" \
    -target arm64-apple-macosx27.0 \
    -sdk "${SDKROOT}" \
    "${POLICY}" \
    "${POLICY_SMOKE}" \
    -o "${BUILD_DIR}/goldeneye_native_window_policy_smoke"
"${BUILD_DIR}/goldeneye_native_window_policy_smoke"

grep -Fq 'GOLDENEYE_NATIVE_BACKGROUND' "${MAIN}"
grep -Fq 'if !backgroundRuntimeEnabled' "${MAIN}"
grep -Fq 'NATIVE_BACKGROUND="${GOLDENEYE_NATIVE_BACKGROUND:-1}"' "${RUNNER}"
grep -Fq 'export GOLDENEYE_NATIVE_BACKGROUND="${NATIVE_BACKGROUND}"' "${RUNNER}"
grep -Fq 'open -g -n' "${RUNNER}"
grep -Fq 'export GOLDENEYE_NATIVE_FULLSCREEN=0' "${RUNNER}"
grep -Fq 'GOLDENEYE_NATIVE_BACKGROUND="${GOLDENEYE_NATIVE_BACKGROUND:-1}"' "${MEASURE}"
grep -Fq 'window.ignoresMouseEvents = true' "${MAIN}"
grep -Fq 'window.acceptsMouseMovedEvents = false' "${MAIN}"
grep -Fq 'window.orderBack(nil)' "${MAIN}"
grep -Fq 'orderOut(nil)' "${MAIN}"
grep -Fq 'window.alphaValue = 0' "${MAIN}"
grep -Fq 'usesPassiveNativeBackgroundRuntime' "${MAIN}"
grep -Fq 'app.setActivationPolicy(' "${MAIN}"
grep -Fq 'usesPassiveNativeBackgroundRuntime() ? .accessory : .regular' "${MAIN}"
! grep -Fq 'window.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]' "${MAIN}"
# Explicit cadence/interactive probes may request foreground activation so a
# direct executable launch can establish the measured active gate. The call
# must remain behind the non-background cadence branch; passive launches are
# still forbidden from activating or taking input focus.
grep -Fq 'if cadenceProbeEnabled' "${MAIN}"
grep -Fq 'NSApp.activate(ignoringOtherApps: true)' "${MAIN}"
! grep -Fq 'window.level = .floating' "${MAIN}"
! grep -Fq 'window.orderFrontRegardless()' "${MAIN}"
! grep -Fq 'scheduleCadenceKeepAlive' "${MAIN}"
grep -Fq 'source: "initial"' "${MAIN}"
grep -Fq 'applicationShouldHandleReopen' "${MAIN}"
grep -Fq 'deferred=1 reason=fullscreenTransition' "${MAIN}"
grep -Fq 'windowDidFailToEnterFullScreen' "${MAIN}"
grep -Fq 'windowDidFailToExitFullScreen' "${MAIN}"
grep -Fq 'Another GoldenEyeHost harness is running' "${RUNNER}"

echo "native background launch policy: PASS passive-by-default click-through cadence-activation-explicit-interactive-only"
