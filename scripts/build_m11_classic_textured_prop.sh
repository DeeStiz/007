#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="${PROJECT_ROOT}/build/native/m11"
APP_DIR="${PROJECT_ROOT}/build/native/m2/GoldenEyeHost.app"
MODULE_CACHE_DIR="${BUILD_DIR}/metal-module-cache"
AIR_FILE="${BUILD_DIR}/GoldenEyeClassicTexturedProp.air"
METALLIB_FILE="${BUILD_DIR}/GoldenEyeClassicTexturedProp.metallib"

"${SCRIPT_DIR}/build_m2_app.sh"
mkdir -p "${BUILD_DIR}" "${MODULE_CACHE_DIR}"
METAL=$(xcrun --find metal)
METAL_TOOLCHAIN_DIR=$(dirname "${METAL}")
xcrun metal -fmodules-cache-path="${MODULE_CACHE_DIR}" \
    -mmacosx-version-min=27.0 -c \
    "${PROJECT_ROOT}/native/shaders/GoldenEyeClassicTexturedProp.metal" \
    -o "${AIR_FILE}"
"${METAL_TOOLCHAIN_DIR}/metallib" "${AIR_FILE}" -o "${METALLIB_FILE}"
mkdir -p "${APP_DIR}/Contents/Resources"
cp "${METALLIB_FILE}" "${APP_DIR}/Contents/Resources/GoldenEyeClassicTexturedProp.metallib"
SIGNING_IDENTITY="${DEVELOPMENT_SIGNING_IDENTITY:-Apple Development: Derek Stiles (RWSPYS288D)}"
if [ "${SIGNING_IDENTITY}" = "-" ]; then
    echo "Refusing ad-hoc signing; set DEVELOPMENT_SIGNING_IDENTITY to a development certificate." >&2
    exit 1
fi
codesign --force --deep --sign "${SIGNING_IDENTITY}" --timestamp=none "${APP_DIR}"
codesign --verify --deep --strict "${APP_DIR}"
echo "M11 classic textured prop metallib: ${METALLIB_FILE}"
