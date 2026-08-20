#!/bin/bash
set -euo pipefail
shopt -s nullglob

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
APP_DIR="${PROJECT_ROOT}/build/native/m12/GoldenEyeHost.app"
PROP_PATH="${PROJECT_ROOT}/build/native/classic-prop/Pammo_crate1Z.bin"
TEXTURE_ROOT="${PROJECT_ROOT}/build/native/classic-textures"
BUILD_DIR="${PROJECT_ROOT}/build/native"
TRACE_PATH="${BUILD_DIR}/m12-classic-combiner.gputrace"
CAPTURE_TOOL="${BUILD_DIR}/m12-capture-window"

fail() {
    echo "M12 classic combiner runtime validation: $*" >&2
    exit 1
}

require_nonempty() {
    [[ -s "$1" ]] || fail "missing or empty artifact $1"
}

wait_for_process_log() {
    local marker="$1"
    local destination="$2"
    local attempts=0
    while [[ "${attempts}" -lt 50 ]]; do
        local candidates=(/tmp/*classic*combiner*.log /tmp/*m12*combiner*.log)
        local candidate
        for candidate in "${candidates[@]}"; do
            [[ -f "${candidate}" && -s "${candidate}" ]] || continue
            [[ "${candidate}" -nt "${marker}" ]] || continue
            cp -f "${candidate}" "${destination}"
            echo "${candidate}"
            return 0
        done
        attempts=$((attempts + 1))
        sleep 1
    done
    return 1
}

wait_for_file() {
    local path="$1"
    local attempts=0
    while [[ "${attempts}" -lt 60 ]]; do
        if [[ -d "${path}" || -s "${path}" ]]; then
            return 0
        fi
        attempts=$((attempts + 1))
        sleep 1
    done
    return 1
}

require_runtime_shape() {
    local path="$1"
    require_nonempty "${path}"
    rg -q 'status=0' "${path}" || fail "runtime status is not zero"
    rg -q 'commands=24' "${path}" || fail "runtime command count is not 24"
    rg -q '(drawPackets=4|draw_count=4|draws=4)' "${path}" ||
        fail "runtime draw count is not four"
    rg -q 'frames=60' "${path}" || fail "runtime frame count is not 60"
    rg -q 'draws=240' "${path}" || fail "runtime draw total is not 240"
    rg -q -i 'v4|combiner|render.?mode|lower' "${path}" ||
        fail "runtime contains no V4 lowering evidence"
}

"${SCRIPT_DIR}/test_classic_combiner_replay.sh"
"${SCRIPT_DIR}/build_m12_classic_combiner.sh"

[[ -d "${APP_DIR}" ]] || fail "M12 app bundle was not built"
[[ -f "${APP_DIR}/Contents/Resources/GoldenEyeClassicCombinerProp.metallib" ]] ||
    fail "M12 V4 metallib is missing from the bundle"
codesign --verify --deep --strict "${APP_DIR}"

for input in "${PROP_PATH}" \
    "${TEXTURE_ROOT}/AMMOCRATE1.bin" \
    "${TEXTURE_ROOT}/AMMOTEXT765.bin" \
    "${TEXTURE_ROOT}/CRATEROPE.bin"; do
    require_nonempty "${input}"
done

killall GoldenEyeHost >/dev/null 2>&1 || true
RUNTIME_MARKER=$(mktemp /tmp/goldeneye-m12-runtime-marker.XXXXXX)
sleep 1
: > /tmp/goldeneye-m12-capture-status.log
open -n \
    --env GOLDENEYE_M12_CLASSIC_COMBINER=1 \
    --env GOLDENEYE_CLASSIC_PROP_ASSET="${PROP_PATH}" \
    --env GOLDENEYE_CLASSIC_TEXTURE_ROOT="${TEXTURE_ROOT}" \
    --env MTL_DEBUG_LAYER=1 \
    --env MTL_DEBUG_LAYER_ERROR_MODE=nslog \
    --env MTL_SHADER_VALIDATION=1 \
    --env MTL_SHADER_VALIDATION_REPORT_TO_STDERR=1 \
    "${APP_DIR}"
RUNTIME_LOG="${BUILD_DIR}/m12-runtime.log"
wait_for_process_log "${RUNTIME_MARKER}" "${RUNTIME_LOG}" ||
    fail "M12 runtime evidence log did not appear"
require_runtime_shape "${RUNTIME_LOG}"

if [[ ! -x "${CAPTURE_TOOL}" ]]; then
    mkdir -p "${BUILD_DIR}/m12-capture-module-cache"
    CLANG_MODULE_CACHE_PATH="${BUILD_DIR}/m12-capture-module-cache" \
        swiftc -target arm64-apple-macosx14.0 \
        "${PROJECT_ROOT}/scripts/capture_macos_window.swift" \
        -o "${CAPTURE_TOOL}"
fi
PID=$(pgrep -x GoldenEyeHost | tail -n 1)
"${CAPTURE_TOOL}" "${PID}" "${BUILD_DIR}/m12-classic-combiner.png"
shasum -a 256 "${BUILD_DIR}/m12-classic-combiner.png" > \
    "${BUILD_DIR}/m12-pixel.sha256"
require_nonempty "${BUILD_DIR}/m12-classic-combiner.png"
require_nonempty "${BUILD_DIR}/m12-pixel.sha256"

# Capture and shader validation are separate runs because Metal rejects their
# simultaneous use.  Preserve any prior trace by moving it to an ignored M12
# sibling instead of deleting it.
killall GoldenEyeHost >/dev/null 2>&1 || true
if [[ -d "/tmp/goldeneye-m12-classic-combiner.gputrace" ]]; then
    mv "/tmp/goldeneye-m12-classic-combiner.gputrace" \
        "/tmp/goldeneye-m12-classic-combiner.previous.$(date +%s).gputrace"
fi
if [[ -d "${TRACE_PATH}" ]]; then
    mv "${TRACE_PATH}" "${TRACE_PATH}.previous.$(date +%s)"
fi
CAPTURE_MARKER=$(mktemp /tmp/goldeneye-m12-capture-marker.XXXXXX)
open -n \
    --env MTL_CAPTURE_ENABLED=1 \
    --env GOLDENEYE_M12_CLASSIC_COMBINER=1 \
    --env GOLDENEYE_M12_CAPTURE=1 \
    --env GOLDENEYE_CLASSIC_PROP_ASSET="${PROP_PATH}" \
    --env GOLDENEYE_CLASSIC_TEXTURE_ROOT="${TEXTURE_ROOT}" \
    --env MTL_DEBUG_LAYER=1 \
    --env MTL_DEBUG_LAYER_ERROR_MODE=nslog \
    "${APP_DIR}"
wait_for_file "/tmp/goldeneye-m12-classic-combiner.gputrace" ||
    fail "M12 GPU trace was not captured"
mkdir -p "${TRACE_PATH}"
cp -R "/tmp/goldeneye-m12-classic-combiner.gputrace/." "${TRACE_PATH}/"
require_nonempty "${TRACE_PATH}/index"

GPUD_LOG="${BUILD_DIR}/m12-gpudebug.log"
gpudebug --oneshot -t "${TRACE_PATH}" \
    -c 'go commands/cb0/grp0' -c 'list --all' \
    -c 'go commands/cb0/grp0/re1' -c 'list --all' > "${GPUD_LOG}"
gpudebug --oneshot -t "${TRACE_PATH}" \
    -c 'go resources/textures' -c 'list --all' >> "${GPUD_LOG}"
gpudebug --oneshot -t "${TRACE_PATH}" \
    -c 'go commands/cb0/grp0/re1/grp0/draw0' -c 'info --all' >> "${GPUD_LOG}"
require_nonempty "${GPUD_LOG}"
rg -q 'ce0.*3 blits' "${GPUD_LOG}" || fail "texture upload encoder missing"
rg -q 're1.*4 draws' "${GPUD_LOG}" || fail "four-draw render encoder missing"
rg -q '1 texture, 1 sampler' "${GPUD_LOG}" || fail "argument-table bindings missing"
rg -q -i 'combiner|render.?mode|lower|v4' "${GPUD_LOG}" ||
    fail "V4 state labels missing from GPU inspection"
rg -q 'goldeneye_classic_combiner_prop_frag' "${GPUD_LOG}" ||
    fail "V4 fragment function missing from GPU inspection"

# The capture run is intentionally not reused for lifecycle probes.
killall GoldenEyeHost >/dev/null 2>&1 || true
RESIZE_MARKER=$(mktemp /tmp/goldeneye-m12-resize-marker.XXXXXX)
sleep 1
open -n \
    --env GOLDENEYE_M12_CLASSIC_COMBINER=1 \
    --env GOLDENEYE_M12_RESIZE=1 \
    --env GOLDENEYE_CLASSIC_PROP_ASSET="${PROP_PATH}" \
    --env GOLDENEYE_CLASSIC_TEXTURE_ROOT="${TEXTURE_ROOT}" \
    --env MTL_DEBUG_LAYER=1 \
    --env MTL_DEBUG_LAYER_ERROR_MODE=nslog \
    --env MTL_SHADER_VALIDATION=1 \
    --env MTL_SHADER_VALIDATION_REPORT_TO_STDERR=1 \
    "${APP_DIR}"
RESIZE_RUNTIME_LOG="${BUILD_DIR}/m12-runtime-resize.log"
wait_for_process_log "${RESIZE_MARKER}" "${RESIZE_RUNTIME_LOG}" ||
    fail "M12 resize runtime evidence log did not appear"
require_runtime_shape "${RESIZE_RUNTIME_LOG}"

RESIZE_LOG="${BUILD_DIR}/m12-resize.log"
RESIZE_SOURCE=""
for candidate in /tmp/*m12*resize*.log /tmp/*m9-resize*.log; do
    [[ -f "${candidate}" && -s "${candidate}" ]] || continue
    [[ "${candidate}" -nt "${RESIZE_MARKER}" ]] || continue
    RESIZE_SOURCE="${candidate}"
done
if [[ -n "${RESIZE_SOURCE}" ]]; then
    cp -f "${RESIZE_SOURCE}" "${RESIZE_LOG}"
else
    fail "M12 resize probe log did not appear"
fi
require_nonempty "${RESIZE_LOG}"
rg -q 'resize=1' "${RESIZE_LOG}" || fail "resize probe did not run"
rg -q 'third=1024x576' "${RESIZE_LOG}" || fail "resize dimensions are incomplete"

PID=$(pgrep -x GoldenEyeHost | tail -n 1)
LEAK_LOG="${BUILD_DIR}/m12-leaks.log"
set +e
if command -v gtimeout >/dev/null 2>&1; then
    gtimeout 30 leaks --noContent --nostacks --quiet "${PID}" > "${LEAK_LOG}" 2>&1
    LEAK_STATUS=$?
else
    leaks --noContent --nostacks --quiet "${PID}" > "${LEAK_LOG}" 2>&1
    LEAK_STATUS=$?
fi
set -e
[[ "${LEAK_STATUS}" -ne 124 ]] || fail "leaks probe timed out"
rg -q '0 leaks for 0 total leaked bytes' "${LEAK_LOG}" ||
    fail "M12 leaks probe reported leaks"

osascript -e 'tell application id "com.goldeneye.swift.host" to quit' >/dev/null 2>&1 || true
SHUTDOWN_LOG="${BUILD_DIR}/m12-shutdown.log"
SHUTDOWN_SOURCE=""
for _ in $(seq 1 30); do
    for candidate in /tmp/*m12*shutdown*.log /tmp/*m9-shutdown*.log; do
        [[ -f "${candidate}" && -s "${candidate}" ]] || continue
        [[ "${candidate}" -nt "${RESIZE_MARKER}" ]] || continue
        SHUTDOWN_SOURCE="${candidate}"
    done
    [[ -n "${SHUTDOWN_SOURCE}" ]] && break
    sleep 1
done
[[ -n "${SHUTDOWN_SOURCE}" ]] || fail "shutdown evidence did not appear"
cp -f "${SHUTDOWN_SOURCE}" "${SHUTDOWN_LOG}"
require_nonempty "${SHUTDOWN_LOG}"
rg -q '^shutdown=1$' "${SHUTDOWN_LOG}" || fail "shutdown probe failed"

# Preserve an explicit launch record with validation configuration.  The
# renderer log and Metal-system log remain separate evidence streams.
VALIDATION_LOG="${BUILD_DIR}/m12-validation.log"
{
    echo 'MTL_DEBUG_LAYER=1'
    echo 'MTL_SHADER_VALIDATION=1'
    echo 'MTL_SHADER_VALIDATION_REPORT_TO_STDERR=1'
    log show --last 5m --style compact \
        --predicate 'process == "GoldenEyeHost" AND (eventMessage CONTAINS[c] "Metal")' \
        2>/dev/null || true
} > "${VALIDATION_LOG}"
require_nonempty "${VALIDATION_LOG}"
rg -q 'MTL_DEBUG_LAYER=1' "${VALIDATION_LOG}" || fail "validation launch record missing"
rg -q 'Metal API Validation Enabled' "${VALIDATION_LOG}" ||
    fail "Metal API validation evidence missing"
rg -q 'Metal GPU Validation Enabled' "${VALIDATION_LOG}" ||
    fail "Metal GPU validation evidence missing"

echo "M12 classic combiner runtime validation: PASS"
echo "Runtime: ${RUNTIME_LOG}"
echo "Resize runtime: ${RESIZE_RUNTIME_LOG}"
echo "Screenshot: ${BUILD_DIR}/m12-classic-combiner.png"
echo "GPU trace: ${TRACE_PATH}"
echo "GPU inspection: ${GPUD_LOG}"
echo "Validation: ${VALIDATION_LOG}"
echo "Leaks: ${LEAK_LOG}"
echo "Shutdown: ${SHUTDOWN_LOG}"
