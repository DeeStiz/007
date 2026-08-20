#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="${PROJECT_ROOT}/build/native/m12"
SCRATCH_DIR="${BUILD_DIR}/swiftpm"
MODULE_CACHE_DIR="${BUILD_DIR}/module-cache"
METAL_MODULE_CACHE_DIR="${BUILD_DIR}/metal-module-cache"
APP_DIR="${BUILD_DIR}/GoldenEyeHost.app"
EXECUTABLE="${APP_DIR}/Contents/MacOS/GoldenEyeHost"

mkdir -p "${BUILD_DIR}" "${MODULE_CACHE_DIR}" "${METAL_MODULE_CACHE_DIR}"
exec > >(tee "${BUILD_DIR}/build.log") 2>&1

echo "M12 classic combiner build: root=${PROJECT_ROOT}"

if ! command -v swift >/dev/null 2>&1; then
    echo "M12 classic combiner build: swift is unavailable" >&2
    exit 1
fi
if ! command -v xcrun >/dev/null 2>&1; then
    echo "M12 classic combiner build: xcrun is unavailable" >&2
    exit 1
fi

CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" \
SWIFTPM_MODULECACHE_OVERRIDE="${MODULE_CACHE_DIR}" \
    swift build --disable-sandbox --configuration debug \
    --scratch-path "${SCRATCH_DIR}" --product GoldenEyeHost

mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp -f "${SCRATCH_DIR}/out/Products/Debug/GoldenEyeHost" "${EXECUTABLE}"

# Keep this bundle isolated from the completed M2/M10/M11 bundles.  The
# bundle is an ignored M12 build artifact; no source or private ROM input is
# copied into it.
cat > "${APP_DIR}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>GoldenEyeHost</string>
	<key>CFBundleIdentifier</key>
	<string>com.goldeneye.swift.host</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>GoldenEye Swift</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.games</string>
	<key>LSMinimumSystemVersion</key>
	<string>27.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
PLIST

SHADER_SOURCE="${GOLDENEYE_M12_SHADER_SOURCE:-${PROJECT_ROOT}/native/shaders/GoldenEyeClassicCombinerProp.metal}"
LIBRARY_NAME="${GOLDENEYE_M12_LIBRARY_NAME:-GoldenEyeClassicCombinerProp}"
AIR_FILE="${BUILD_DIR}/${LIBRARY_NAME}.air"
METALLIB_FILE="${BUILD_DIR}/${LIBRARY_NAME}.metallib"

if [[ ! -f "${SHADER_SOURCE}" ]]; then
    echo "M12 classic combiner build: missing V4 shader ${SHADER_SOURCE}" >&2
    exit 1
fi

METAL=$(xcrun --find metal)
METAL_TOOLCHAIN_DIR=$(dirname -- "${METAL}")
xcrun metal -fmodules-cache-path="${METAL_MODULE_CACHE_DIR}" \
    -mmacosx-version-min=27.0 -c "${SHADER_SOURCE}" -o "${AIR_FILE}"
"${METAL_TOOLCHAIN_DIR}/metallib" "${AIR_FILE}" -o "${METALLIB_FILE}"
cp -f "${METALLIB_FILE}" \
    "${APP_DIR}/Contents/Resources/${LIBRARY_NAME}.metallib"

SIGNING_IDENTITY="${DEVELOPMENT_SIGNING_IDENTITY:-Apple Development: Derek Stiles (RWSPYS288D)}"
if [[ "${SIGNING_IDENTITY}" == "-" ]]; then
    echo "M12 classic combiner build: refusing ad-hoc signing" >&2
    exit 1
fi
codesign --force --deep --sign "${SIGNING_IDENTITY}" --timestamp=none "${APP_DIR}"
codesign --verify --deep --strict --verbose=2 "${APP_DIR}"
codesign -dvvv "${APP_DIR}" 2>&1 |
    sed -n '/^Executable=/p;/^Identifier=/p;/^TeamIdentifier=/p;/^Authority=/p'

echo "M12 classic combiner build: PASS"
echo "App: ${APP_DIR}"
echo "Shader: ${SHADER_SOURCE}"
echo "AIR: ${AIR_FILE}"
echo "Metallib: ${METALLIB_FILE}"
