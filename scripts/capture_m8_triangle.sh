#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
BUILD_DIR="${PROJECT_ROOT}/build/native/m8-triangle.gputrace"
SOURCE_TRACE="/tmp/goldeneye-m8-triangle.gputrace"
APP_DIR="${PROJECT_ROOT}/build/native/m2/GoldenEyeHost.app"

"${SCRIPT_DIR}/build_m6_pipeline.sh"
rm -rf "${BUILD_DIR}" "${SOURCE_TRACE}"
open -n --env GOLDENEYE_M8_TRIANGLE=1 --env GOLDENEYE_M8_CAPTURE=1 \
    --env MTL_CAPTURE_ENABLED=1 --env MTL_DEBUG_LAYER=1 \
    --env MTL_DEBUG_LAYER_ERROR_MODE=nslog "${APP_DIR}"

for _ in $(seq 1 30); do
    if [ -d "${SOURCE_TRACE}" ]; then break; fi
    sleep 1
done
test -d "${SOURCE_TRACE}"
cp -R "${SOURCE_TRACE}" "${BUILD_DIR}"
killall GoldenEyeHost >/dev/null 2>&1 || true
echo "GPU trace: ${BUILD_DIR}"
du -sh "${BUILD_DIR}"
strings "${BUILD_DIR}"/* 2>/dev/null | rg -q 'GoldenEye.M8.Triangle.Frame.0'
strings "${BUILD_DIR}"/* 2>/dev/null | rg -q 'GoldenEye.M8.Triangle.RenderEncoder'
strings "${BUILD_DIR}"/* 2>/dev/null | rg -q 'GoldenEye.M8.Triangle.Draw.0'
strings "${BUILD_DIR}"/* 2>/dev/null | rg -q 'mtl4-command-queue'
echo "Static trace inspection: labeled MTL4 triangle frame, draw, encoder, and queue found"

if command -v gtimeout >/dev/null 2>&1; then
    set +e
    gtimeout 20 gpudebug --oneshot -q -t "${BUILD_DIR}" -c 'list' > "${PROJECT_ROOT}/build/native/m8-gpudebug.log" 2>&1
    gpustatus=$?
    set -e
    if [ "${gpustatus}" -eq 124 ]; then
        echo "gpudebug inspection timed out; see build/native/m8-gpudebug.log"
    elif [ "${gpustatus}" -ne 0 ]; then
        echo "gpudebug inspection failed with status ${gpustatus}; see build/native/m8-gpudebug.log"
    else
        echo "gpudebug inspection completed; see build/native/m8-gpudebug.log"
    fi
fi
