#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=1
    shift
fi
ROM_PATH="${1:-${GOLDENEYE_ROM_PATH:-}}"

if [[ -z "${ROM_PATH}" ]]; then
    echo "Usage: $0 [--dry-run] /absolute/path/to/GoldenEye-007-US.z64" >&2
    exit 2
fi

BUILD_DIR="${PROJECT_ROOT}/build/native/boot-runtime"
SCRATCH_DIR="${BUILD_DIR}/swiftpm"
MODULE_CACHE_DIR="${BUILD_DIR}/module-cache"
# Keep the former diagnostic app and its captures intact.  The source-faithful
# product has a separate stable bundle path and contains only the V6 source
# scene and source-2D libraries, so a stale diagnostic resource cannot leak
# into Release.
FAITHFUL_DIR="${BUILD_DIR}/source-faithful"
APP_DIR="${FAITHFUL_DIR}/GoldenEyeHost.app"
EXECUTABLE="${APP_DIR}/Contents/MacOS/GoldenEyeHost"
BOOT_ASSET_ROOT="${PROJECT_ROOT}/build/native/boot-assets"
STAGE_ASSET_ROOT="${PROJECT_ROOT}/build/native/stage-assets-image-decoder-v6"
# Release consumes the source-order decoder generation.  Keep the former
# b924 catalog at build/native/source-frontend-v6 as preserved evidence; do
# not let a preparation run overwrite or silently select it.
SOURCE_FRONTEND_ROOT="${PROJECT_ROOT}/build/native/source-frontend-v6-image-decoder-v6"
SOURCE_SHADER="${PROJECT_ROOT}/native/shaders/GoldenEyeSourceSceneV6.metal"
SOURCE_AIR="${FAITHFUL_DIR}/GoldenEyeSourceSceneV6.air"
SOURCE_METALLIB="${FAITHFUL_DIR}/GoldenEyeSourceSceneV6.metallib"
SOURCE_2D_SHADER="${PROJECT_ROOT}/native/shaders/GoldenEyeSource2DV6.metal"
SOURCE_2D_AIR="${FAITHFUL_DIR}/GoldenEyeSource2DV6.air"
SOURCE_2D_METALLIB="${FAITHFUL_DIR}/GoldenEyeSource2DV6.metallib"
CAST_ASSET_ROOT="${GOLDENEYE_NATIVE_CAST_ASSET_ROOT:-${PROJECT_ROOT}/build/native/cast-frontend-v6-image-decoder-v6-fullweapons}"
GUNBARREL_SIDECAR="${GOLDENEYE_NATIVE_GUNBARREL_SIDECAR:-${PROJECT_ROOT}/build/native/gunbarrel-v6-prepared/gunbarrel.gbar}"

if [[ "${DRY_RUN}" == 1 ]]; then
    GOLDENEYE_NATIVE_BOOT_ASSET_ROOT="${BOOT_ASSET_ROOT}" \
    GOLDENEYE_NATIVE_STAGE_ASSET_ROOT="${STAGE_ASSET_ROOT}" \
    GOLDENEYE_NATIVE_SOURCE_FRONTEND_ROOT="${SOURCE_FRONTEND_ROOT}" \
        "${SCRIPT_DIR}/verify_native_boot_release.sh" --dry-run "${ROM_PATH}"
    exit 0
fi

"${SCRIPT_DIR}/prepare_native_boot_assets.sh" "${ROM_PATH}"
GOLDENEYE_STAGE_ASSET_OUTPUT_ROOT="${STAGE_ASSET_ROOT}" \
    "${SCRIPT_DIR}/prepare_native_stage_assets.sh" "${ROM_PATH}"

# Preparation is not complete until the final GEFV and all eight GESM
# sidecars pass their independent envelope/hash/path checks.  This gate also
# repeats the external ROM and exact Linux reference-build evidence checks.
GOLDENEYE_NATIVE_BOOT_ASSET_ROOT="${BOOT_ASSET_ROOT}" \
GOLDENEYE_NATIVE_STAGE_ASSET_ROOT="${STAGE_ASSET_ROOT}" \
GOLDENEYE_NATIVE_SOURCE_FRONTEND_ROOT="${SOURCE_FRONTEND_ROOT}" \
    "${SCRIPT_DIR}/verify_native_boot_release.sh" --prepared "${ROM_PATH}"

mkdir -p "${BUILD_DIR}" "${MODULE_CACHE_DIR}" "${FAITHFUL_DIR}"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" \
SWIFTPM_MODULECACHE_OVERRIDE="${MODULE_CACHE_DIR}" \
    swift build --disable-sandbox --configuration release \
    --scratch-path "${SCRATCH_DIR}" --product GoldenEyeHost

[[ -f "${SOURCE_SHADER}" ]] || {
    echo "SourceScene V6 shader is missing: ${SOURCE_SHADER}" >&2
    exit 1
}
[[ -f "${SOURCE_2D_SHADER}" ]] || {
    echo "Source2D V6 shader is missing: ${SOURCE_2D_SHADER}" >&2
    exit 1
}
if ! command -v xcrun >/dev/null 2>&1; then
    echo "xcrun is required to compile the Metal 4 source-scene/source-2d libraries" >&2
    exit 1
fi
METALLIB=$(xcrun --sdk macosx --find metallib)
METAL_CRYPTEX=$(dirname -- "${METALLIB}")/metal
if [[ -x "${METAL_CRYPTEX}" ]]; then
    METAL="${METAL_CRYPTEX}"
else
    METAL=$(xcrun --sdk macosx --find metal)
fi
[[ -x "${METAL}" ]] || {
    echo "Metal compiler is unavailable: ${METAL}" >&2
    exit 1
}
[[ -x "${METALLIB}" ]] || {
    echo "metallib linker is unavailable: ${METALLIB}" >&2
    exit 1
}
"${METAL}" -mmacosx-version-min=27.0 \
    -c "${SOURCE_SHADER}" \
    -o "${SOURCE_AIR}"
"${METALLIB}" "${SOURCE_AIR}" -o "${SOURCE_METALLIB}"
[[ -s "${SOURCE_METALLIB}" ]] || {
    echo "SourceScene V6 metallib was not produced" >&2
    exit 1
}
"${METAL}" -mmacosx-version-min=27.0 \
    -c "${SOURCE_2D_SHADER}" \
    -o "${SOURCE_2D_AIR}"
"${METALLIB}" "${SOURCE_2D_AIR}" -o "${SOURCE_2D_METALLIB}"
[[ -s "${SOURCE_2D_METALLIB}" ]] || {
    echo "Source2D V6 metallib was not produced" >&2
    exit 1
}
[[ -f "${CAST_ASSET_ROOT}/source-frontend-v6.gefv" ]] || {
    echo "Full Cast source catalog is missing: ${CAST_ASSET_ROOT}" >&2
    exit 1
}
[[ -s "${GUNBARREL_SIDECAR}" ]] || {
    echo "Prepared Gunbarrel sidecar is missing: ${GUNBARREL_SIDECAR}" >&2
    exit 1
}

mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp -f "${SCRATCH_DIR}/out/Products/Release/GoldenEyeHost" "${EXECUTABLE}"
cp -f "${PROJECT_ROOT}/native/host/NativeBootInfo.plist" "${APP_DIR}/Contents/Info.plist"
cp -f "${SOURCE_METALLIB}" \
    "${APP_DIR}/Contents/Resources/GoldenEyeSourceSceneV6.metallib"
cp -f "${SOURCE_2D_METALLIB}" \
    "${APP_DIR}/Contents/Resources/GoldenEyeSource2DV6.metallib"

SIGNING_IDENTITY="${DEVELOPMENT_SIGNING_IDENTITY:-Apple Development: Derek Stiles (RWSPYS288D)}"
if [[ -z "${SIGNING_IDENTITY}" || "${SIGNING_IDENTITY}" == "-" ]]; then
    echo "Refusing ad-hoc signing for the native boot product" >&2
    exit 1
fi
command -v codesign >/dev/null 2>&1 || {
    echo "codesign is required for the signed native boot product" >&2
    exit 1
}
codesign --force --deep --options runtime \
    --sign "${SIGNING_IDENTITY}" --timestamp=none "${APP_DIR}"
codesign --verify --deep --strict --verbose=2 "${APP_DIR}"

# Do not let a valid signature mask a stale/diagnostic resource.  The bundle
# gate also rejects ROM/private payloads and verifies the final GEFV/GESM
# catalog again at the exact launch boundary.
GOLDENEYE_NATIVE_BOOT_ASSET_ROOT="${BOOT_ASSET_ROOT}" \
GOLDENEYE_NATIVE_STAGE_ASSET_ROOT="${STAGE_ASSET_ROOT}" \
GOLDENEYE_NATIVE_SOURCE_FRONTEND_ROOT="${SOURCE_FRONTEND_ROOT}" \
    "${SCRIPT_DIR}/verify_native_boot_release.sh" \
    --bundle "${APP_DIR}" "${ROM_PATH}"

echo "Native boot source-faithful Release build: PASS"
echo "App: ${APP_DIR}"
echo "Assets: ${BOOT_ASSET_ROOT}"
echo "Source catalog: ${SOURCE_FRONTEND_ROOT}"
