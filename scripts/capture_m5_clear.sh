#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
BUILD_DIR="${PROJECT_ROOT}/build/native/m5-clear.gputrace"
APP_DIR="${PROJECT_ROOT}/build/native/m2/GoldenEyeHost.app"
SOURCE_TRACE="/tmp/goldeneye-m5-clear.gputrace"

"${SCRIPT_DIR}/build_m2_app.sh"
rm -rf "${BUILD_DIR}" "${SOURCE_TRACE}"
rm -f /tmp/goldeneye-capture-status.log

open -n --env GOLDENEYE_M5_CAPTURE=1 --env MTL_CAPTURE_ENABLED=1 \
    --env MTL_DEBUG_LAYER=1 --env MTL_DEBUG_LAYER_ERROR_MODE=nslog \
    "${APP_DIR}"

for _ in $(seq 1 30); do
    if [ -d "${SOURCE_TRACE}" ]; then break; fi
    sleep 1
done
test -d "${SOURCE_TRACE}"
cp -R "${SOURCE_TRACE}" "${BUILD_DIR}"
killall GoldenEyeHost >/dev/null 2>&1 || true

echo "GPU trace: ${BUILD_DIR}"
du -sh "${BUILD_DIR}"
strings "${BUILD_DIR}"/* 2>/dev/null | rg -q 'GoldenEye.M5.Clear.Frame.0'
strings "${BUILD_DIR}"/* 2>/dev/null | rg -q 'GoldenEye.M5.Clear.RenderEncoder'
strings "${BUILD_DIR}"/* 2>/dev/null | rg -q 'mtl4-command-queue'
echo "Static trace inspection: labeled MTL4 queue, clear frame, and render encoder found"

if command -v gtimeout >/dev/null 2>&1; then
    set +e
    gtimeout 20 gpudebug --oneshot -q -t "${BUILD_DIR}" -c 'list' > "${PROJECT_ROOT}/build/native/m5-gpudebug.log" 2>&1
    gpustatus=$?
    set -e
    if [ "${gpustatus}" -eq 124 ]; then
        echo "gpudebug inspection timed out while the local replay service was unavailable; see build/native/m5-gpudebug.log"
    elif [ "${gpustatus}" -ne 0 ]; then
        echo "gpudebug inspection failed with status ${gpustatus}; see build/native/m5-gpudebug.log"
    else
        echo "gpudebug inspection completed; see build/native/m5-gpudebug.log"
    fi
fi
