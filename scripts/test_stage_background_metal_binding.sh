#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ROM_PATH="${1:-${GOLDENEYE_ROM_PATH:-/Users/derek/Documents/GoldenEye 007 (USA).z64}}"
ASSET_ROOT="${GOLDENEYE_NATIVE_STAGE_ASSET_ROOT:-${PROJECT_ROOT}/build/native/stage-assets-image-decoder-v6}"
BUILD_DIR="${PROJECT_ROOT}/build/native/m27-stage-background"
APP_DIR="${BUILD_DIR}/GoldenEyeHost.app"
SWIFT_BUILD_DIR="${BUILD_DIR}/swiftpm"
STAGE_METALLIB="${PROJECT_ROOT}/build/native/stage-background-draw-packet/GoldenEyeStageBackground.metallib"
TRACE_PATH="${BUILD_DIR}/goldeneye-m27-stage-background.gputrace"
RUNTIME_LOG="${BUILD_DIR}/stage-background-runtime.log"
VALIDATION_LOG="${BUILD_DIR}/stage-background-validation.log"
SHUTDOWN_LOG="${BUILD_DIR}/stage-background-shutdown.log"

fail() {
    echo "M27 stage background Metal binding validation: $*" >&2
    exit 1
}

require_nonempty() {
    [[ -s "$1" ]] || fail "missing or empty artifact $1"
}

stop_runtime_app() {
    osascript -e 'tell application id "com.goldeneye.swift.host" to quit' \
        >/dev/null 2>&1 || true
    for _ in $(seq 1 30); do
        if ! pgrep -x GoldenEyeHost >/dev/null 2>&1; then
            # AppKit termination callbacks finish asynchronously after the
            # process disappears; allow their renderer evidence writes to
            # land before the next run truncates the shared probe files.
            sleep 2
            return 0
        fi
        sleep 1
    done
    # A stale process must not contaminate the next capture. This fallback is
    # only reached after the graceful AppKit termination window expires.
    killall GoldenEyeHost >/dev/null 2>&1 || true
}

wait_for_runtime_log() {
    local marker="$1"
    local attempts=0
    while [[ "${attempts}" -lt 120 ]]; do
        if [[ -s /tmp/goldeneye-m27-stage-background.log \
              && /tmp/goldeneye-m27-stage-background.log -nt "${marker}" ]]; then
            cp -f /tmp/goldeneye-m27-stage-background.log "${RUNTIME_LOG}"
            return 0
        fi
        attempts=$((attempts + 1))
        sleep 1
    done
    return 1
}

mkdir -p "${BUILD_DIR}"
"${SCRIPT_DIR}/test_stage_background_draw_packet.sh" "${ASSET_ROOT}"
swift build \
    --configuration debug \
    --scratch-path "${SWIFT_BUILD_DIR}" \
    --product GoldenEyeHost
DEBUG_BIN_PATH=$(swift build \
    --configuration debug \
    --scratch-path "${SWIFT_BUILD_DIR}" \
    --product GoldenEyeHost \
    --show-bin-path)
DEBUG_EXECUTABLE="${DEBUG_BIN_PATH}/GoldenEyeHost"
[[ -x "${DEBUG_EXECUTABLE}" ]] || fail "debug stage evidence executable is missing"
[[ -s "${STAGE_METALLIB}" ]] || fail "stage background metallib is missing"
if [[ -d "${APP_DIR}" ]]; then
    mv "${APP_DIR}" "${APP_DIR}.previous.$(date +%s)"
fi
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp -f "${DEBUG_EXECUTABLE}" "${APP_DIR}/Contents/MacOS/GoldenEyeHost"
cp -f "${PROJECT_ROOT}/native/host/NativeBootInfo.plist" "${APP_DIR}/Contents/Info.plist"
cp -f "${STAGE_METALLIB}" "${APP_DIR}/Contents/Resources/GoldenEyeStageBackground.metallib"
codesign --force --deep --sign - --timestamp=none "${APP_DIR}"
codesign --verify --deep --strict "${APP_DIR}"

stop_runtime_app
: > /tmp/goldeneye-m27-stage-background.log
: > /tmp/goldeneye-native-title-owner.log
RUNTIME_MARKER=$(mktemp /tmp/goldeneye-m27-stage-runtime-marker.XXXXXX)
open -g -n \
    --env GOLDENEYE_NATIVE_BACKGROUND=1 \
    --env GOLDENEYE_NATIVE_FULLSCREEN=0 \
    --env GOLDENEYE_M27_STAGE_OVERLAY=1 \
    --env GOLDENEYE_M27_STAGE_ID=33 \
    --env GOLDENEYE_NATIVE_STAGE_ASSET_ROOT="${ASSET_ROOT}" \
    --env GOLDENEYE_CADENCE_PROBE=1 \
    --env GOLDENEYE_CADENCE_DURATION=3 \
    --env MTL_DEBUG_LAYER=1 \
    --env MTL_DEBUG_LAYER_ERROR_MODE=nslog \
    --env MTL_SHADER_VALIDATION=1 \
    --env MTL_SHADER_VALIDATION_REPORT_TO_STDERR=1 \
    "${APP_DIR}"
wait_for_runtime_log "${RUNTIME_MARKER}" ||
    fail "stage background runtime evidence did not appear"
require_nonempty "${RUNTIME_LOG}"
rg -q 'status=0' "${RUNTIME_LOG}" || fail "stage renderer reported an error"
rg -q 'stage=33' "${RUNTIME_LOG}" || fail "stage ID evidence missing"
rg -q 'rooms=137' "${RUNTIME_LOG}" || fail "Dam room count evidence missing"
rg -q 'portals=194' "${RUNTIME_LOG}" || fail "Dam portal count evidence missing"
rg -q 'commands=331' "${RUNTIME_LOG}" || fail "Dam draw command count evidence missing"
rg -q 'vertices=1210' "${RUNTIME_LOG}" || fail "Dam vertex count evidence missing"
rg -q 'unsupportedMask=63' "${RUNTIME_LOG}" || fail "unsupported source geometry mask missing"
rg -q 'privateVertex=1' "${RUNTIME_LOG}" || fail "private vertex resource evidence missing"
rg -q 'uploadComplete=1' "${RUNTIME_LOG}" || fail "private vertex upload evidence missing"
rg -q 'privateVertexLabel=GoldenEye\.M27\.StageBackground\.Vertices\.Private' "${RUNTIME_LOG}" ||
    fail "private vertex allocation label readback missing"
rg -q 'privateVertexStoragePrivate=1' "${RUNTIME_LOG}" ||
    fail "private vertex storage-mode readback missing"
rg -q 'frames=[1-9][0-9]*' "${RUNTIME_LOG}" || fail "no stage frames rendered"
rg -q 'draws=[1-9][0-9]*' "${RUNTIME_LOG}" || fail "no stage line draws submitted"

# The display-link route is the required supplied-drawable path.  This is
# checked separately from the renderer's own frame/draw evidence.
OWNER_LOG="/tmp/goldeneye-native-title-owner.log"
require_nonempty "${OWNER_LOG}"
rg -q 'presentationPath=suppliedDrawable.*suppliedDrawable=1' "${OWNER_LOG}" ||
    fail "stage route did not use the supplied drawable path"

stop_runtime_app
if [[ -d "/tmp/goldeneye-m27-stage-background.gputrace" ]]; then
    mv "/tmp/goldeneye-m27-stage-background.gputrace" \
        "/tmp/goldeneye-m27-stage-background.previous.$(date +%s).gputrace"
fi
if [[ -d "${TRACE_PATH}" ]]; then
    mv "${TRACE_PATH}" "${TRACE_PATH}.previous.$(date +%s)"
fi
: > /tmp/goldeneye-m27-stage-background.log
: > /tmp/goldeneye-native-title-owner.log
open -g -n \
    --env GOLDENEYE_NATIVE_BACKGROUND=1 \
    --env GOLDENEYE_NATIVE_FULLSCREEN=0 \
    --env GOLDENEYE_M27_STAGE_OVERLAY=1 \
    --env GOLDENEYE_M27_STAGE_ID=33 \
    --env GOLDENEYE_NATIVE_STAGE_ASSET_ROOT="${ASSET_ROOT}" \
    --env GOLDENEYE_CADENCE_PROBE=1 \
    --env GOLDENEYE_CADENCE_DURATION=2 \
    --env GOLDENEYE_M27_CAPTURE=1 \
    --env MTL_CAPTURE_ENABLED=1 \
    "${APP_DIR}"
for _ in $(seq 1 60); do
    [[ -d "/tmp/goldeneye-m27-stage-background.gputrace" ]] && break
    sleep 1
done
[[ -d "/tmp/goldeneye-m27-stage-background.gputrace" ]] ||
    fail "stage background GPU trace was not captured"
mkdir -p "${TRACE_PATH}"
cp -R "/tmp/goldeneye-m27-stage-background.gputrace/." "${TRACE_PATH}/"
require_nonempty "${TRACE_PATH}/index"

GPUD_LOG="${BUILD_DIR}/stage-background-gpudebug.log"
gpudebug --oneshot -t "${TRACE_PATH}" \
    -c 'go commands/cb0/grp0' -c 'list --all' \
    -c 'go commands/cb0/grp0/re1' -c 'list --all' \
    -c 'go commands/cb0/grp0/re1/grp0/draw0' -c 'info --all' \
    -c 'go resources/buffers' -c 'list --all' \
    -c 'info buf0' -c 'info buf1' \
    > "${GPUD_LOG}"
require_nonempty "${GPUD_LOG}"
rg -q -i 'goldeneye_stage_background_vertex' "${GPUD_LOG}" ||
    fail "stage background vertex function missing from GPU inspection"
rg -q -i 'GoldenEye.M27.StageBackground.Vertices.Private' "${GPUD_LOG}" ||
    fail "private vertex resource label missing from GPU inspection"
rg -q -i 'storageMode:[[:space:]]+Private' "${GPUD_LOG}" ||
    fail "private vertex storage mode missing from GPU inspection"
rg -q -i 'draws' "${GPUD_LOG}" || fail "stage render encoder draw evidence missing"

stop_runtime_app
VALIDATION_LOG="${BUILD_DIR}/stage-background-validation.log"
{
    echo 'MTL_DEBUG_LAYER=1'
    echo 'MTL_SHADER_VALIDATION=1'
    echo 'MTL_SHADER_VALIDATION_REPORT_TO_STDERR=1'
    log show --last 5m --style compact \
        --predicate 'process == "GoldenEyeHost" AND (eventMessage CONTAINS[c] "Metal")' \
        2>/dev/null || true
} > "${VALIDATION_LOG}"
require_nonempty "${VALIDATION_LOG}"
rg -q 'Metal API Validation Enabled' "${VALIDATION_LOG}" ||
    fail "Metal API validation evidence missing"
rg -q 'Metal GPU Validation Enabled' "${VALIDATION_LOG}" ||
    fail "Metal GPU validation evidence missing"
if rg -q -i 'GPU fault|Metal (API|GPU) Validation.*(error|fault)|validation failed' "${VALIDATION_LOG}"; then
    fail "Metal validation reported an error"
fi

for _ in $(seq 1 30); do
    if rg -q 'shutdown=1' /tmp/goldeneye-m27-stage-background.log 2>/dev/null; then
        break
    fi
    sleep 1
done
require_nonempty /tmp/goldeneye-m27-stage-background.log
rg -q 'shutdown=1' /tmp/goldeneye-m27-stage-background.log ||
    fail "stage renderer shutdown evidence did not appear"
cp -f /tmp/goldeneye-m27-stage-background.log "${SHUTDOWN_LOG}"

echo 'M27 stage background Metal binding validation: PASS'
echo "Runtime: ${RUNTIME_LOG}"
echo "GPU trace: ${TRACE_PATH}"
echo "GPU inspection: ${GPUD_LOG}"
echo "Validation: ${VALIDATION_LOG}"
