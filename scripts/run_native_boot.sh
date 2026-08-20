#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ROM_PATH="${1:-${GOLDENEYE_ROM_PATH:-}}"

if [[ -z "${ROM_PATH}" ]]; then
    echo "Usage: $0 /absolute/path/to/GoldenEye-007-US.z64" >&2
    exit 2
fi

"${SCRIPT_DIR}/build_native_boot.sh" "${ROM_PATH}"
APP_EXECUTABLE="${PROJECT_ROOT}/build/native/boot-runtime/source-faithful/GoldenEyeHost.app/Contents/MacOS/GoldenEyeHost"
ASSET_ROOT="${PROJECT_ROOT}/build/native/boot-assets"
STAGE_ASSET_ROOT="${PROJECT_ROOT}/build/native/stage-assets-image-decoder-v6"
SOURCE_FRONTEND_ROOT="${PROJECT_ROOT}/build/native/source-frontend-v6-image-decoder-v6"
VISIBLE_DEPENDENCY_ROOT="${PROJECT_ROOT}/build/native/ramrom-visible-dependencies-v6"
CAST_ASSET_ROOT="${GOLDENEYE_NATIVE_CAST_ASSET_ROOT:-${PROJECT_ROOT}/build/native/cast-frontend-v6-image-decoder-v6-fullweapons}"
GUNBARREL_SIDECAR="${GOLDENEYE_NATIVE_GUNBARREL_SIDECAR:-${PROJECT_ROOT}/build/native/gunbarrel-v6-prepared/gunbarrel.gbar}"

# The launch environment is intentionally source-only.  Do not inherit old
# milestone probes or diagnostic shader selectors from the caller's shell.
unset \
    GOLDENEYE_NATIVE_TITLE \
    GOLDENEYE_NATIVE_STAGE_ASSET_ROOT \
    GOLDENEYE_M3_EVENT_PROBE \
    GOLDENEYE_M5_PAUSE_PROBE \
    GOLDENEYE_CADENCE_PROBE \
    GOLDENEYE_CADENCE_STRESS \
    GOLDENEYE_CADENCE_DURATION \
    GOLDENEYE_CADENCE_RENDERER \
    GOLDENEYE_M6_PIPELINE \
    GOLDENEYE_M8_TRIANGLE \
    GOLDENEYE_M10_PROP \
    GOLDENEYE_M11_TEXTURED_PROP \
    GOLDENEYE_M12_CLASSIC_COMBINER \
    GOLDENEYE_M27_STAGE_OVERLAY \
    GOLDENEYE_M27_STAGE_ID \
    GOLDENEYE_TITLE_PARTIAL_GEOMETRY \
    GOLDENEYE_CAPTURE_MODE \
    GOLDENEYE_GBI_DIAGNOSTIC \
    GOLDENEYE_DIAGNOSTIC_RENDERER
export GOLDENEYE_NATIVE_ASSET_ROOT="${ASSET_ROOT}"
export GOLDENEYE_NATIVE_STAGE_ASSET_ROOT="${STAGE_ASSET_ROOT}"
export GOLDENEYE_NATIVE_VISIBLE_DEPENDENCY_ROOT="${VISIBLE_DEPENDENCY_ROOT}"
export GOLDENEYE_NATIVE_SOURCE_FRONTEND_ROOT="${SOURCE_FRONTEND_ROOT}"
export GOLDENEYE_NATIVE_CAST_ASSET_ROOT="${CAST_ASSET_ROOT}"
export GOLDENEYE_NATIVE_GUNBARREL_SIDECAR="${GUNBARREL_SIDECAR}"
export GOLDENEYE_NATIVE_FULLSCREEN="${GOLDENEYE_NATIVE_FULLSCREEN:-1}"
[[ -x "${APP_EXECUTABLE}" ]] || {
    echo "source-faithful GoldenEyeHost executable is missing: ${APP_EXECUTABLE}" >&2
    exit 1
}
[[ -f "${SOURCE_FRONTEND_ROOT}/source-frontend-v6.gefv" ]] || {
    echo "source frontend V6 catalog is missing: ${SOURCE_FRONTEND_ROOT}" >&2
    exit 1
}
[[ -f "${CAST_ASSET_ROOT}/source-frontend-v6.gefv" ]] || {
    echo "full Cast source catalog is missing: ${CAST_ASSET_ROOT}" >&2
    exit 1
}
[[ -s "${GUNBARREL_SIDECAR}" ]] || {
    echo "prepared Gunbarrel sidecar is missing: ${GUNBARREL_SIDECAR}" >&2
    exit 1
}
exec "${APP_EXECUTABLE}"
