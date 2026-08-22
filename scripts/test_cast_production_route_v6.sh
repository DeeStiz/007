#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
RUN_ID="${GE_CAST_PRODUCTION_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
BUILD_ROOT="${ROOT}/build/native/cast-production-route-v6/${RUN_ID}"
SWIFT_BUILD_ROOT="${BUILD_ROOT}/swiftpm"
APP_DIR="${BUILD_ROOT}/GoldenEyeCastProduction.app"
TRACE_PATH="${BUILD_ROOT}/cast-production.gputrace"
CAST_ROOT="${GOLDENEYE_NATIVE_CAST_ASSET_ROOT:-${ROOT}/build/native/cast-frontend-v6-image-decoder-v6-fullweapons}"
GUNBARREL_SIDECAR="${GOLDENEYE_NATIVE_GUNBARREL_SIDECAR:-${ROOT}/build/native/gunbarrel-v6-prepared/gunbarrel.gbar}"
SOURCE_ROOT="${GOLDENEYE_NATIVE_SOURCE_FRONTEND_ROOT:-${ROOT}/build/native/source-frontend-v6-image-decoder-v6}"
ASSET_ROOT="${GOLDENEYE_NATIVE_ASSET_ROOT:-${ROOT}/build/native/boot-assets}"
STAGE_ROOT="${GOLDENEYE_NATIVE_STAGE_ASSET_ROOT:-${ROOT}/build/native/stage-assets-image-decoder-v6}"
VISIBLE_ROOT="${GOLDENEYE_NATIVE_VISIBLE_DEPENDENCY_ROOT:-${ROOT}/build/native/ramrom-visible-dependencies-v6}"
ROM_PATH="${1:-${GOLDENEYE_ROM_PATH:-/Users/derek/Documents/GoldenEye 007 (USA).z64}}"
SEED="${GE_CAST_PRODUCTION_SEED:-0x12345678}"
CAPTURE_MODE="${GE_CAST_PRODUCTION_MODE:-capture}"
case "${CAPTURE_MODE}" in
    validation)
        SHADER_VALIDATION=1
        CAPTURE_ENABLED=0
        ;;
    capture)
        # gpucapture refuses a process launched with MTL_SHADER_VALIDATION=1.
        # Validation and trace evidence are therefore deliberately separate
        # runs over the same debuggable production-shaped app.
        SHADER_VALIDATION=0
        CAPTURE_ENABLED=1
        ;;
    *)
        echo "Cast production route V6: GE_CAST_PRODUCTION_MODE must be validation or capture" >&2
        exit 2
        ;;
esac

fail() {
    echo "Cast production route V6: $*" >&2
    exit 1
}

require_dir() { [[ -d "$1" ]] || fail "missing directory $1"; }
require_file() { [[ -s "$1" ]] || fail "missing or empty file $1"; }

stop_app() {
    osascript -e 'tell application id "com.goldeneye.swift.host" to quit' \
        >/dev/null 2>&1 || true
    for _ in $(seq 1 30); do
        if ! pgrep -x GoldenEyeHost >/dev/null 2>&1; then
            sleep 2
            return 0
        fi
        sleep 1
    done
    killall GoldenEyeHost >/dev/null 2>&1 || true
}

mkdir -p "${BUILD_ROOT}"
require_dir "${CAST_ROOT}"
require_file "${CAST_ROOT}/source-frontend-v6.gefv"
require_dir "${SOURCE_ROOT}"
require_file "${SOURCE_ROOT}/source-frontend-v6.gefv"
require_dir "${ASSET_ROOT}"
require_dir "${STAGE_ROOT}"
require_dir "${VISIBLE_ROOT}"
require_file "${GUNBARREL_SIDECAR}"
[[ -f "${ROM_PATH}" ]] || fail "external verified ROM is missing: ${ROM_PATH}"
ROM_SHA1=$(shasum -a 1 "${ROM_PATH}" | awk '{print tolower($1)}')
[[ "${ROM_SHA1}" == "abe01e4aeb033b6c0836819f549c791b26cfde83" ]] ||
    fail "external ROM SHA-1 mismatch: ${ROM_SHA1}"

BUILD_LOG="${BUILD_ROOT}/debug-build.log"
if ! swift build --configuration debug \
    --scratch-path "${SWIFT_BUILD_ROOT}" \
    --product GoldenEyeHost >"${BUILD_LOG}" 2>&1; then
    tail -80 "${BUILD_LOG}" >&2
    fail "debug production-route build failed"
fi
BIN_PATH=$(swift build --configuration debug \
    --scratch-path "${SWIFT_BUILD_ROOT}" \
    --product GoldenEyeHost --show-bin-path)
DEBUG_EXECUTABLE="${BIN_PATH}/GoldenEyeHost"
require_file "${DEBUG_EXECUTABLE}"

SOURCE_METALLIB="${ROOT}/build/native/boot-runtime/source-faithful/GoldenEyeSourceSceneV6.metallib"
SOURCE_2D_METALLIB="${ROOT}/build/native/boot-runtime/source-faithful/GoldenEyeSource2DV6.metallib"
require_file "${SOURCE_METALLIB}"
require_file "${SOURCE_2D_METALLIB}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp -f "${DEBUG_EXECUTABLE}" "${APP_DIR}/Contents/MacOS/GoldenEyeHost"
cp -f "${ROOT}/native/host/NativeBootInfo.plist" "${APP_DIR}/Contents/Info.plist"
cp -f "${SOURCE_METALLIB}" "${APP_DIR}/Contents/Resources/GoldenEyeSourceSceneV6.metallib"
cp -f "${SOURCE_2D_METALLIB}" "${APP_DIR}/Contents/Resources/GoldenEyeSource2DV6.metallib"
codesign --force --deep --options runtime \
    --entitlements "${ROOT}/scripts/fixtures/cast-production-capture.entitlements" \
    --sign "${DEVELOPMENT_SIGNING_IDENTITY:-Apple Development: Derek Stiles (RWSPYS288D)}" \
    --timestamp=none "${APP_DIR}"
codesign --verify --deep --strict "${APP_DIR}"
codesign -d --entitlements :- "${APP_DIR}" 2>/dev/null \
    | rg -q 'com.apple.security.get-task-allow' \
    || fail "Cast capture app is not debuggable"

CAST_LOG="${BUILD_ROOT}/cast-renderer.log"
PREWARM_LOG="${BUILD_ROOT}/cast-prewarm.log"
BUILDER_PREWARM_LOG="${BUILD_ROOT}/cast-builder-prewarm.log"
OWNER_LOG="${BUILD_ROOT}/source-frontend-owner.log"
FRAME_LOG="${BUILD_ROOT}/source-renderer-frames.log"
AUTHORITY_LOG="${BUILD_ROOT}/source-frontend-authority.log"
BOUNDARY_LOG="${BUILD_ROOT}/gpu-boundaries.log"
GPUD_LOG="${BUILD_ROOT}/gpudebug.log"
BLOCKER_LOG="${BUILD_ROOT}/blocker.txt"
CRASH_MARKER="${BUILD_ROOT}/crash-marker"
for log in "${CAST_LOG}" "${OWNER_LOG}" "${FRAME_LOG}" "${AUTHORITY_LOG}"; do : > "${log}"; done

cleanup() {
    stop_app
    cp -f /tmp/goldeneye-source-product-renderer-v6-cast.log "${CAST_LOG}" 2>/dev/null || true
    cp -f /tmp/goldeneye-source-product-renderer-v6-cast-prewarm.log "${PREWARM_LOG}" 2>/dev/null || true
    cp -f /tmp/goldeneye-source-product-renderer-v6-cast-builder-prewarm.log "${BUILDER_PREWARM_LOG}" 2>/dev/null || true
    cp -f /tmp/goldeneye-source-frontend-owner.log "${OWNER_LOG}" 2>/dev/null || true
    cp -f /tmp/goldeneye-source-product-renderer-v6-frames.log "${FRAME_LOG}" 2>/dev/null || true
    cp -f /tmp/goldeneye-source-frontend-authority.log "${AUTHORITY_LOG}" 2>/dev/null || true
}
trap cleanup EXIT

stop_app
touch "${CRASH_MARKER}"
: > /tmp/goldeneye-source-product-renderer-v6-cast.log
: > /tmp/goldeneye-source-frontend-owner.log
: > /tmp/goldeneye-source-product-renderer-v6-frames.log
: > /tmp/goldeneye-source-frontend-authority.log

open -n \
    --env GOLDENEYE_NATIVE_TITLE=1 \
    --env GOLDENEYE_NATIVE_ASSET_ROOT="${ASSET_ROOT}" \
    --env GOLDENEYE_NATIVE_STAGE_ASSET_ROOT="${STAGE_ROOT}" \
    --env GOLDENEYE_NATIVE_VISIBLE_DEPENDENCY_ROOT="${VISIBLE_ROOT}" \
    --env GOLDENEYE_NATIVE_SOURCE_FRONTEND_ROOT="${SOURCE_ROOT}" \
    --env GOLDENEYE_NATIVE_CAST_ASSET_ROOT="${CAST_ROOT}" \
    --env GOLDENEYE_NATIVE_GUNBARREL_SIDECAR="${GUNBARREL_SIDECAR}" \
    --env GOLDENEYE_NATIVE_CAST_SOURCE_INDEX="${GE_CAST_SOURCE_INDEX:-}" \
    --env GOLDENEYE_NATIVE_CAST_RANDOM_WORD="${GE_CAST_RANDOM_WORD:-}" \
    --env GOLDENEYE_NATIVE_FULLSCREEN="${GOLDENEYE_NATIVE_FULLSCREEN:-0}" \
    --env GOLDENEYE_CADENCE_FULLSCREEN="${GOLDENEYE_CADENCE_FULLSCREEN:-0}" \
    --env GOLDENEYE_CADENCE_STRESS="${GOLDENEYE_CADENCE_STRESS:-0}" \
    --env GOLDENEYE_TITLE_RANDOM_SEED="${SEED}" \
    --env GOLDENEYE_CADENCE_PROBE=1 \
    --env GOLDENEYE_CADENCE_DURATION=120 \
    --env MTL_DEBUG_LAYER=1 \
    --env MTL_DEBUG_LAYER_ERROR_MODE=nslog \
    --env MTL_SHADER_VALIDATION="${SHADER_VALIDATION}" \
    --env MTL_SHADER_VALIDATION_REPORT_TO_STDERR=1 \
    --env MTL_CAPTURE_ENABLED="${CAPTURE_ENABLED}" \
    "${APP_DIR}"

PID=""
for _ in $(seq 1 20); do
    PID=$(pgrep -n -x GoldenEyeHost || true)
    [[ -n "${PID}" ]] && break
    sleep 1
done
[[ -n "${PID}" ]] || fail "production Cast app did not start"
printf 'pid=%s\nseed=%s\nmode=%s\nshaderValidation=%s\ncaptureEnabled=%s\ncastRoot=%s\n' \
    "${PID}" "${SEED}" "${CAPTURE_MODE}" "${SHADER_VALIDATION}" \
    "${CAPTURE_ENABLED}" "${CAST_ROOT}" > "${BUILD_ROOT}/launch.txt"

cast_seen=0
for _ in $(seq 1 120); do
    if rg -q 'castSubmit=1' /tmp/goldeneye-source-product-renderer-v6-cast.log 2>/dev/null; then
        cast_seen=1
        break
    fi
    if ! pgrep -x GoldenEyeHost >/dev/null 2>&1; then break; fi
    sleep 1
done

if [[ "${cast_seen}" != 1 ]]; then
    # CrashReporter writes the IPS asynchronously after the process exits.
    sleep 5
    latest_crash=$(find "${HOME}/Library/Logs/DiagnosticReports" -maxdepth 1 \
        -type f -name 'GoldenEyeHost-*.ips' -newer "${CRASH_MARKER}" \
        -print 2>/dev/null | sort | tail -1)
    {
        echo "castSubmit=0"
        echo "latestCrash=${latest_crash:-none}"
        if [[ -n "${latest_crash}" && -s "${latest_crash}" ]]; then
            rg -n 'Thread stack size exceeded|goldeneye_gbi_scene_builder_v6.swift|GoldenEyeSourceProductRendererV6' \
                "${latest_crash}" || true
        fi
    } > "${BLOCKER_LOG}"
    fail "production Cast route did not reach castSubmit=1; see ${BLOCKER_LOG}"
fi

if [[ "${CAPTURE_MODE}" == "validation" ]]; then
    {
        echo "castSubmit=1"
        echo "shaderValidation=1"
        echo "capture=separate-run-required"
    } > "${BUILD_ROOT}/validation.txt"
    echo "Cast production route V6 validation: PASS evidence=${BUILD_ROOT}"
    exit 0
fi

BOUNDARIES=$(gpucapture boundaries --pid "${PID}" | tee "${BOUNDARY_LOG}")
LAYER_ID=$(printf '%s\n' "${BOUNDARIES}" | awk '$2 == "Layer" { print $1; exit }')
[[ -n "${LAYER_ID}" ]] || fail "no CAMetalLayer capture boundary for Cast route"
gpucapture start --pid "${PID}" --boundary "${LAYER_ID}" --count 1 --output "${TRACE_PATH}"
[[ -d "${TRACE_PATH}" ]] || fail "Cast GPU trace was not produced"
gpudebug --oneshot -t "${TRACE_PATH}" \
    -c 'find GoldenEye.V6.SourceScene' \
    -c 'go commands/cb0' -c 'list --all' \
    > "${GPUD_LOG}"
[[ -s "${GPUD_LOG}" ]] || fail "Cast GPU inspection log is empty"

echo "Cast production route V6: PASS evidence=${BUILD_ROOT} prewarm=${PREWARM_LOG}"
