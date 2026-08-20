#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
BUILD_DIR="${PROJECT_ROOT}/build/native/m2"
APP_DIR="${BUILD_DIR}/GoldenEyeHost.app"

"${SCRIPT_DIR}/build_m2_app.sh"

test -x "${APP_DIR}/Contents/MacOS/GoldenEyeHost"
plutil -extract CFBundlePackageType raw -o - "${APP_DIR}/Contents/Info.plist" | grep -qx APPL
plutil -extract CFBundleExecutable raw -o - "${APP_DIR}/Contents/Info.plist" | grep -qx GoldenEyeHost
plutil -extract LSMinimumSystemVersion raw -o - "${APP_DIR}/Contents/Info.plist" | grep -qx 27.0
codesign --verify --deep --strict "${APP_DIR}"
signature_details=$(codesign -dvvv "${APP_DIR}" 2>&1)
printf '%s\n' "${signature_details}" | rg -q '^Authority=Apple Development:'
printf '%s\n' "${signature_details}" | rg -q '^TeamIdentifier=KV5KQJ3LLD$'
printf '%s\n' "${signature_details}" | rg -q -v '^Authority=adhoc$'
minos=$(otool -l "${APP_DIR}/Contents/MacOS/GoldenEyeHost" | awk '/LC_BUILD_VERSION/{found=1; next} found && /minos/{print $2; exit}')
test "${minos}" = 27.0

echo "Launching M2 app bundle"
rm -f /tmp/goldeneye-m2-owner-loop.log
open -n "${APP_DIR}"
for _ in $(seq 1 30); do
    if [ -f /tmp/goldeneye-m2-owner-loop.log ] && \
        rg -q 'initialized=1 ticks=60 shutdown=0' /tmp/goldeneye-m2-owner-loop.log && \
        pgrep -x GoldenEyeHost >/dev/null 2>&1; then
        cat /tmp/goldeneye-m2-owner-loop.log
        echo "GoldenEyeHost process observed"
        killall GoldenEyeHost >/dev/null 2>&1 || true
        echo "M2 AppKit bundle validation: PASS"
        exit 0
    fi
    sleep 1
done
echo "GoldenEyeHost did not appear after launch" >&2
exit 1
