#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
BUILD_DIR="${PROJECT_ROOT}/build/native/m2"
SCRATCH_DIR="${BUILD_DIR}/swiftpm"
MODULE_CACHE_DIR="${BUILD_DIR}/module-cache"
APP_DIR="${BUILD_DIR}/GoldenEyeHost.app"
EXECUTABLE="${APP_DIR}/Contents/MacOS/GoldenEyeHost"

mkdir -p "${BUILD_DIR}" "${MODULE_CACHE_DIR}"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" \
SWIFTPM_MODULECACHE_OVERRIDE="${MODULE_CACHE_DIR}" \
    swift build --disable-sandbox --configuration debug \
    --scratch-path "${SCRATCH_DIR}" --product GoldenEyeHost

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${SCRATCH_DIR}/out/Products/Debug/GoldenEyeHost" "${EXECUTABLE}"

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

SIGNING_IDENTITY="${DEVELOPMENT_SIGNING_IDENTITY:-Apple Development: Derek Stiles (RWSPYS288D)}"
if [ "${SIGNING_IDENTITY}" = "-" ]; then
    echo "Refusing ad-hoc signing; set DEVELOPMENT_SIGNING_IDENTITY to a development certificate." >&2
    exit 1
fi
codesign --force --deep --sign "${SIGNING_IDENTITY}" --timestamp=none "${APP_DIR}"
codesign --verify --deep --strict --verbose=2 "${APP_DIR}"
codesign -dvvv "${APP_DIR}" 2>&1 | sed -n '/^Executable=/p;/^Identifier=/p;/^TeamIdentifier=/p;/^Authority=/p'
echo "M2 app: ${APP_DIR}"
