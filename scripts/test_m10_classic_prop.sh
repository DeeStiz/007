#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
APP_DIR="${PROJECT_ROOT}/build/native/m2/GoldenEyeHost.app"
PROP_PATH="${PROJECT_ROOT}/build/native/classic-prop/Pammo_crate1Z.bin"
TRACE_PATH="${PROJECT_ROOT}/build/native/m10-classic-prop.gputrace"
CAPTURE_TOOL="${PROJECT_ROOT}/build/native/m10-capture-window"

"${SCRIPT_DIR}/test_classic_prop_asset.sh"
"${SCRIPT_DIR}/test_classic_gbi.sh"
"${SCRIPT_DIR}/build_m10_classic_prop.sh"

killall GoldenEyeHost >/dev/null 2>&1 || true
: > /tmp/goldeneye-classic-prop.log
open -n \
    --env GOLDENEYE_M10_PROP=1 \
    --env GOLDENEYE_CLASSIC_PROP_ASSET="${PROP_PATH}" \
    --env MTL_DEBUG_LAYER=1 \
    --env MTL_DEBUG_LAYER_ERROR_MODE=nslog \
    --env MTL_SHADER_VALIDATION=1 \
    --env MTL_SHADER_VALIDATION_REPORT_TO_STDERR=1 \
    "${APP_DIR}"
for _ in $(seq 1 40); do
    if [ -s /tmp/goldeneye-classic-prop.log ] && pgrep -x GoldenEyeHost >/dev/null 2>&1; then
        break
    fi
    sleep 1
done
test -s /tmp/goldeneye-classic-prop.log
rg -q 'status=0 commands=24 enters=2 returns=2 drawPackets=4 vertices=40 triangles=20 .*frames=60 draws=240 lastSignal=60 resourceAllocations=3' /tmp/goldeneye-classic-prop.log
cp /tmp/goldeneye-classic-prop.log "${PROJECT_ROOT}/build/native/m10-runtime.log"

if [ ! -x "${CAPTURE_TOOL}" ]; then
    mkdir -p "${PROJECT_ROOT}/build/native/m10-module-cache"
    CLANG_MODULE_CACHE_PATH="${PROJECT_ROOT}/build/native/m10-module-cache" \
        swiftc -target arm64-apple-macosx14.0 \
        "${PROJECT_ROOT}/scripts/capture_macos_window.swift" \
        -o "${CAPTURE_TOOL}"
fi
pid=$(pgrep -x GoldenEyeHost | tail -n 1)
"${CAPTURE_TOOL}" "${pid}" "${PROJECT_ROOT}/build/native/m10-classic-prop.png"
shasum -a 256 "${PROJECT_ROOT}/build/native/m10-classic-prop.png" > \
    "${PROJECT_ROOT}/build/native/m10-pixel.sha256"

# Capture one command buffer through the app's programmatic MTLCapture path.
# Shader validation is intentionally disabled for this separate capture run;
# Metal rejects simultaneous GPU capture and shader validation.
killall GoldenEyeHost >/dev/null 2>&1 || true
: > /tmp/goldeneye-classic-prop.log
: > /tmp/goldeneye-capture-status.log
if [ -e /tmp/goldeneye-m10-classic-prop.gputrace ]; then
    mv /tmp/goldeneye-m10-classic-prop.gputrace \
        "/tmp/goldeneye-m10-classic-prop.previous.$(date +%s).gputrace"
fi
open -n \
    --env MTL_CAPTURE_ENABLED=1 \
    --env GOLDENEYE_M10_PROP=1 \
    --env GOLDENEYE_M10_CAPTURE=1 \
    --env GOLDENEYE_CLASSIC_PROP_ASSET="${PROP_PATH}" \
    --env MTL_DEBUG_LAYER=1 \
    --env MTL_DEBUG_LAYER_ERROR_MODE=nslog \
    "${APP_DIR}"
for _ in $(seq 1 50); do
    if [ -s /tmp/goldeneye-classic-prop.log ] && [ -d /tmp/goldeneye-m10-classic-prop.gputrace ]; then
        break
    fi
    sleep 1
done
test -d /tmp/goldeneye-m10-classic-prop.gputrace
mkdir -p "${TRACE_PATH}"
cp -R /tmp/goldeneye-m10-classic-prop.gputrace/. "${TRACE_PATH}/"
test -s "${TRACE_PATH}/index"
gpudebug --oneshot -t "${TRACE_PATH}" \
    -c 'go commands/cb0/grp0/re0' \
    -c 'list --all' \
    -c 'go commands/cb0/grp0/re0/grp0/draw0' \
    -c 'info --all' > "${PROJECT_ROOT}/build/native/m10-gpudebug.log"
rg -q 'grp0' "${PROJECT_ROOT}/build/native/m10-gpudebug.log"
rg -q 'grp3' "${PROJECT_ROOT}/build/native/m10-gpudebug.log"
rg -q 'GoldenEye.M5.ClassicProp.IndexBuffer' "${PROJECT_ROOT}/build/native/m10-gpudebug.log"
rg -q 'indexCount: *24' "${PROJECT_ROOT}/build/native/m10-gpudebug.log"

echo "M10 classic prop runtime: PASS"
echo "Runtime: ${PROJECT_ROOT}/build/native/m10-runtime.log"
echo "Pixel hash: ${PROJECT_ROOT}/build/native/m10-pixel.sha256"
echo "GPU trace: ${TRACE_PATH}"
echo "GPU inspection: ${PROJECT_ROOT}/build/native/m10-gpudebug.log"
