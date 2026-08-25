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
CAPTURE_MODE="${GE_CAST_PRODUCTION_MODE:-validation}"
ALLOW_FOREGROUND_CAPTURE="${GOLDENEYE_ALLOW_FOREGROUND_CAPTURE:-0}"
WAIT_SECONDS="${GE_CAST_PRODUCTION_WAIT_SECONDS:-300}"
CADENCE_WARMUP_SECONDS="${GE_CAST_PRODUCTION_CADENCE_WARMUP:-0}"
CADENCE_PROBE="${GE_CAST_PRODUCTION_CADENCE_PROBE:-0}"
BACKGROUND_OVERRIDE="${GE_CAST_PRODUCTION_BACKGROUND:-}"
BUILD_CONFIGURATION="${GE_CAST_PRODUCTION_BUILD_CONFIGURATION:-debug}"
[[ "${WAIT_SECONDS}" =~ ^[0-9]+$ && "${WAIT_SECONDS}" -gt 0 ]] || {
    echo "Cast production route V6: GE_CAST_PRODUCTION_WAIT_SECONDS must be a positive integer" >&2
    exit 2
}
[[ "${CADENCE_WARMUP_SECONDS}" =~ ^[0-9]+([.][0-9]+)?$ ]] || {
    echo "Cast production route V6: GE_CAST_PRODUCTION_CADENCE_WARMUP must be a non-negative number" >&2
    exit 2
}
[[ "${CADENCE_PROBE}" == 0 || "${CADENCE_PROBE}" == 1 ]] || {
    echo "Cast production route V6: GE_CAST_PRODUCTION_CADENCE_PROBE must be 0 or 1" >&2
    exit 2
}
[[ "${ALLOW_FOREGROUND_CAPTURE}" == 0 || "${ALLOW_FOREGROUND_CAPTURE}" == 1 ]] || {
    echo "Cast production route V6: GOLDENEYE_ALLOW_FOREGROUND_CAPTURE must be 0 or 1" >&2
    exit 2
}
[[ -z "${BACKGROUND_OVERRIDE}" || "${BACKGROUND_OVERRIDE}" == 0 || "${BACKGROUND_OVERRIDE}" == 1 ]] || {
    echo "Cast production route V6: GE_CAST_PRODUCTION_BACKGROUND must be 0 or 1" >&2
    exit 2
}
[[ "${BUILD_CONFIGURATION}" == debug || "${BUILD_CONFIGURATION}" == release ]] || {
    echo "Cast production route V6: GE_CAST_PRODUCTION_BUILD_CONFIGURATION must be debug or release" >&2
    exit 2
}
case "${CAPTURE_MODE}" in
    validation)
        SHADER_VALIDATION=1
        CAPTURE_ENABLED=0
        ;;
    capture)
        [[ "${ALLOW_FOREGROUND_CAPTURE}" == "1" ]] || {
            echo "Cast production route V6: capture is a visible foreground test; set GOLDENEYE_ALLOW_FOREGROUND_CAPTURE=1 explicitly" >&2
            exit 2
        }
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

NATIVE_BACKGROUND=1
if [[ "${CAPTURE_MODE}" == "capture" ]]; then
    NATIVE_BACKGROUND=0
elif [[ -n "${BACKGROUND_OVERRIDE}" ]]; then
    NATIVE_BACKGROUND="${BACKGROUND_OVERRIDE}"
fi

fail() {
    echo "Cast production route V6: $*" >&2
    exit 1
}

require_dir() { [[ -d "$1" ]] || fail "missing directory $1"; }
require_file() { [[ -s "$1" ]] || fail "missing or empty file $1"; }

APP_PID=""
DID_LAUNCH=0
RUNTIME_LOCK_FILE="${TMPDIR:-/tmp}/goldeneye-native-runtime.lock"
RUNTIME_LOCK_HELD=0
stop_app() {
    if [[ -n "${APP_PID}" ]] && kill -0 "${APP_PID}" 2>/dev/null; then
        kill -TERM "${APP_PID}" 2>/dev/null || true
        wait "${APP_PID}" 2>/dev/null || true
    fi
    APP_PID=""
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

BUILD_LOG="${BUILD_ROOT}/${BUILD_CONFIGURATION}-build.log"
if ! swift build --configuration "${BUILD_CONFIGURATION}" \
    --scratch-path "${SWIFT_BUILD_ROOT}" \
    --product GoldenEyeHost >"${BUILD_LOG}" 2>&1; then
    tail -80 "${BUILD_LOG}" >&2
    fail "${BUILD_CONFIGURATION} production-route build failed"
fi
BIN_PATH=$(swift build --configuration "${BUILD_CONFIGURATION}" \
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
ENGINE_FAILURE_LOG="${BUILD_ROOT}/engine-owner-failure.log"
OWNER_TELEMETRY_LOG="${BUILD_ROOT}/native-title-owner.log"
CRASH_MARKER="${BUILD_ROOT}/crash-marker"
for log in "${CAST_LOG}" "${OWNER_LOG}" "${FRAME_LOG}" "${AUTHORITY_LOG}"; do : > "${log}"; done

cleanup() {
    stop_app
    if [[ "${DID_LAUNCH}" == "1" ]]; then
        cp -f /tmp/goldeneye-source-product-renderer-v6-cast.log "${CAST_LOG}" 2>/dev/null || true
        cp -f /tmp/goldeneye-source-product-renderer-v6-cast-prewarm.log "${PREWARM_LOG}" 2>/dev/null || true
        cp -f /tmp/goldeneye-source-product-renderer-v6-cast-builder-prewarm.log "${BUILDER_PREWARM_LOG}" 2>/dev/null || true
        cp -f /tmp/goldeneye-source-frontend-owner.log "${OWNER_LOG}" 2>/dev/null || true
        cp -f /tmp/goldeneye-source-product-renderer-v6-frames.log "${FRAME_LOG}" 2>/dev/null || true
        cp -f /tmp/goldeneye-source-frontend-authority.log "${AUTHORITY_LOG}" 2>/dev/null || true
        cp -f /tmp/goldeneye-engine-owner-failure.log "${ENGINE_FAILURE_LOG}" 2>/dev/null || true
        cp -f /tmp/goldeneye-native-title-owner.log "${OWNER_TELEMETRY_LOG}" 2>/dev/null || true
    fi
    if [[ "${RUNTIME_LOCK_HELD}" == "1" ]]; then
        /bin/unlink "${RUNTIME_LOCK_FILE}" 2>/dev/null || true
        RUNTIME_LOCK_HELD=0
    fi
}
trap cleanup EXIT
command -v shlock >/dev/null 2>&1 || fail "shlock is required for runtime serialization"
shlock -f "${RUNTIME_LOCK_FILE}" -p "$$" \
    || fail "another GoldenEye runtime harness owns ${RUNTIME_LOCK_FILE}"
RUNTIME_LOCK_HELD=1

if pgrep -x GoldenEyeHost >/dev/null 2>&1; then
    fail "refusing to overlap another GoldenEyeHost; wait for the existing background run to finish"
fi
touch "${CRASH_MARKER}"
: > /tmp/goldeneye-source-product-renderer-v6-cast.log
: > /tmp/goldeneye-source-frontend-owner.log
: > /tmp/goldeneye-source-product-renderer-v6-frames.log
: > /tmp/goldeneye-source-frontend-authority.log
: > /tmp/goldeneye-engine-owner-failure.log
: > /tmp/goldeneye-native-title-owner.log

APP_LAUNCH_LOG="${BUILD_ROOT}/app-launch.log"
(
    cd "${APP_DIR}/Contents/MacOS"
    exec env \
        GOLDENEYE_NATIVE_TITLE=1 \
        GOLDENEYE_NATIVE_ASSET_ROOT="${ASSET_ROOT}" \
        GOLDENEYE_NATIVE_STAGE_ASSET_ROOT="${STAGE_ROOT}" \
        GOLDENEYE_NATIVE_VISIBLE_DEPENDENCY_ROOT="${VISIBLE_ROOT}" \
        GOLDENEYE_NATIVE_SOURCE_FRONTEND_ROOT="${SOURCE_ROOT}" \
        GOLDENEYE_NATIVE_CAST_ASSET_ROOT="${CAST_ROOT}" \
        GOLDENEYE_NATIVE_GUNBARREL_SIDECAR="${GUNBARREL_SIDECAR}" \
        GOLDENEYE_NATIVE_CAST_SOURCE_INDEX="${GE_CAST_SOURCE_INDEX:-}" \
        GOLDENEYE_NATIVE_CAST_RANDOM_WORD="${GE_CAST_RANDOM_WORD:-}" \
        GOLDENEYE_NATIVE_BACKGROUND="${NATIVE_BACKGROUND}" \
        GOLDENEYE_NATIVE_FULLSCREEN=0 \
        GOLDENEYE_CADENCE_FULLSCREEN="${GOLDENEYE_CADENCE_FULLSCREEN:-0}" \
        GOLDENEYE_CADENCE_STRESS="${GOLDENEYE_CADENCE_STRESS:-0}" \
        GOLDENEYE_TITLE_RANDOM_SEED="${SEED}" \
        GOLDENEYE_CADENCE_PROBE="${CADENCE_PROBE}" \
        GOLDENEYE_CADENCE_WARMUP="${CADENCE_WARMUP_SECONDS}" \
        GOLDENEYE_CADENCE_DURATION="${WAIT_SECONDS}" \
        MTL_DEBUG_LAYER=1 \
        MTL_DEBUG_LAYER_ERROR_MODE=nslog \
        MTL_SHADER_VALIDATION="${SHADER_VALIDATION}" \
        MTL_SHADER_VALIDATION_REPORT_TO_STDERR=1 \
        MTL_CAPTURE_ENABLED="${CAPTURE_ENABLED}" \
        ./GoldenEyeHost
) >"${APP_LAUNCH_LOG}" 2>&1 &
APP_PID=$!
PID="${APP_PID}"
DID_LAUNCH=1
for _ in $(seq 1 20); do
    kill -0 "${PID}" 2>/dev/null && break
    sleep 1
done
kill -0 "${PID}" 2>/dev/null || fail "production Cast app did not start"
printf 'pid=%s\nseed=%s\nmode=%s\nbuildConfiguration=%s\nshaderValidation=%s\ncaptureEnabled=%s\nnativeBackground=%s\ncadenceProbe=%s\nwaitSeconds=%s\ncastRoot=%s\n' \
    "${PID}" "${SEED}" "${CAPTURE_MODE}" "${BUILD_CONFIGURATION}" "${SHADER_VALIDATION}" \
    "${CAPTURE_ENABLED}" "${NATIVE_BACKGROUND}" "${CADENCE_PROBE}" "${WAIT_SECONDS}" "${CAST_ROOT}" > "${BUILD_ROOT}/launch.txt"

cast_seen=0
owner_cast_seen=0
for _ in $(seq 1 "${WAIT_SECONDS}"); do
    if rg -q 'castSubmit=1' /tmp/goldeneye-source-product-renderer-v6-cast.log 2>/dev/null; then
        cast_seen=1
        break
    fi
    if rg -q 'castSceneSubmit=1' /tmp/goldeneye-source-frontend-owner.log 2>/dev/null; then
        owner_cast_seen=1
        if [[ "${CAPTURE_MODE}" == "validation" ]]; then break; fi
    fi
    if [[ -s /tmp/goldeneye-engine-owner-failure.log ]]; then
        break
    fi
    if ! kill -0 "${PID}" 2>/dev/null; then break; fi
    sleep 1
done

if [[ "${cast_seen}" != 1 && "${owner_cast_seen}" != 1 ]]; then
    # CrashReporter writes the IPS asynchronously after the process exits.
    sleep 5
    latest_crash=$(find "${HOME}/Library/Logs/DiagnosticReports" -maxdepth 1 \
        -type f -name 'GoldenEyeHost-*.ips' -newer "${CRASH_MARKER}" \
        -print 2>/dev/null | sort | tail -1)
    process_alive=0
    kill -0 "${PID}" 2>/dev/null && process_alive=1
    last_owner_line=$(tail -1 /tmp/goldeneye-source-frontend-owner.log 2>/dev/null || true)
    last_frame_line=$(tail -1 /tmp/goldeneye-source-product-renderer-v6-frames.log 2>/dev/null || true)
    {
        echo "castSubmit=0"
        echo "latestCrash=${latest_crash:-none}"
        echo "waitSeconds=${WAIT_SECONDS}"
        echo "cadenceWarmupSeconds=${CADENCE_WARMUP_SECONDS}"
        echo "processAlive=${process_alive}"
        if [[ -s /tmp/goldeneye-engine-owner-failure.log ]]; then
            echo "deadlineReason=owner-failed"
            echo "engineOwnerFailure=$(tr '\n' ' ' < /tmp/goldeneye-engine-owner-failure.log)"
        else
            echo "deadlineReason=$([[ "${process_alive}" == 1 ]] && echo timeout || echo process-exited)"
        fi
        echo "lastOwnerLine=${last_owner_line}"
        echo "lastFrameLine=${last_frame_line}"
        if [[ -n "${latest_crash}" && -s "${latest_crash}" ]]; then
            rg -n 'Thread stack size exceeded|goldeneye_gbi_scene_builder_v6.swift|GoldenEyeSourceProductRendererV6' \
                "${latest_crash}" || true
        fi
    } > "${BLOCKER_LOG}"
    fail "production Cast route did not reach castSubmit=1; see ${BLOCKER_LOG}"
fi

if [[ "${CAPTURE_MODE}" == "validation" ]]; then
    {
        echo "castSubmit=${cast_seen}"
        echo "ownerCastSceneSubmit=${owner_cast_seen}"
        echo "shaderValidation=1"
        echo "presentation=background-unverified"
        echo "capture=explicit-foreground-run-required"
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
