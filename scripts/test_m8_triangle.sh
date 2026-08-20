#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
APP_DIR="${PROJECT_ROOT}/build/native/m2/GoldenEyeHost.app"
SCREENSHOT_A="${PROJECT_ROOT}/build/native/m8-triangle-a.png"
SCREENSHOT_B="${PROJECT_ROOT}/build/native/m8-triangle-b.png"
WINDOW_CAPTURE="${PROJECT_ROOT}/build/native/m8-capture-window"

"${SCRIPT_DIR}/build_m6_pipeline.sh"
rm -f /tmp/goldeneye-m8-triangle.log "${SCREENSHOT_A}" "${SCREENSHOT_B}"
open -n --env GOLDENEYE_M8_TRIANGLE=1 --env MTL_DEBUG_LAYER=1 \
    --env MTL_DEBUG_LAYER_ERROR_MODE=nslog --env MTL_SHADER_VALIDATION=1 \
    --env MTL_SHADER_VALIDATION_REPORT_TO_STDERR=1 "${APP_DIR}"

for _ in $(seq 1 30); do
    if [ -f /tmp/goldeneye-m8-triangle.log ] && \
        rg -q 'frames=60 draws=60 packetHash=[0-9]+ lastSignal=60' /tmp/goldeneye-m8-triangle.log && \
        pgrep -x GoldenEyeHost >/dev/null 2>&1; then
        break
    fi
    sleep 1
done
test -f /tmp/goldeneye-m8-triangle.log
cat /tmp/goldeneye-m8-triangle.log
pid=$(pgrep -x GoldenEyeHost | tail -n 1)
mkdir -p "${PROJECT_ROOT}/build/native/m8-module-cache"
CLANG_MODULE_CACHE_PATH="${PROJECT_ROOT}/build/native/m8-module-cache" \
    swiftc -target arm64-apple-macosx14.0 \
    "${PROJECT_ROOT}/scripts/capture_macos_window.swift" \
    -o "${WINDOW_CAPTURE}"
"${WINDOW_CAPTURE}" "${pid}" "${SCREENSHOT_A}"
sleep 1
"${WINDOW_CAPTURE}" "${pid}" "${SCREENSHOT_B}"
cmp "${SCREENSHOT_A}" "${SCREENSHOT_B}"
pixel_hash=$(shasum -a 256 "${SCREENSHOT_A}" | awk '{print $1}')
printf '%s\n' "${pixel_hash}" > "${PROJECT_ROOT}/build/native/m8-pixel.sha256"
echo "M8 screenshot pixel hash: ${pixel_hash}"
killall GoldenEyeHost >/dev/null 2>&1 || true
echo "M8 triangle validation: PASS"
