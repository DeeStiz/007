#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
APP_DIR="${PROJECT_ROOT}/build/native/m2/GoldenEyeHost.app"
PROP_PATH="${PROJECT_ROOT}/build/native/classic-prop/Pammo_crate1Z.bin"
TEXTURE_ROOT="${PROJECT_ROOT}/build/native/classic-textures"
TRACE_PATH="${PROJECT_ROOT}/build/native/m11-classic-textured-prop.gputrace"
CAPTURE_TOOL="${PROJECT_ROOT}/build/native/m11-capture-window"

"${SCRIPT_DIR}/test_classic_texture_assets.sh"
"${SCRIPT_DIR}/test_classic_texture_replay.sh"
"${SCRIPT_DIR}/build_m11_classic_textured_prop.sh"

killall GoldenEyeHost >/dev/null 2>&1 || true
: > /tmp/goldeneye-classic-textured-prop.log
open -n \
    --env GOLDENEYE_M11_TEXTURED_PROP=1 \
    --env GOLDENEYE_CLASSIC_PROP_ASSET="${PROP_PATH}" \
    --env GOLDENEYE_CLASSIC_TEXTURE_ROOT="${TEXTURE_ROOT}" \
    --env MTL_DEBUG_LAYER=1 \
    --env MTL_DEBUG_LAYER_ERROR_MODE=nslog \
    --env MTL_SHADER_VALIDATION=1 \
    --env MTL_SHADER_VALIDATION_REPORT_TO_STDERR=1 \
    "${APP_DIR}"
for _ in $(seq 1 40); do
    if [ -s /tmp/goldeneye-classic-textured-prop.log ] && pgrep -x GoldenEyeHost >/dev/null 2>&1; then
        break
    fi
    sleep 1
done
test -s /tmp/goldeneye-classic-textured-prop.log
rg -q 'status=0 commands=24 drawPackets=4 vertices=40 triangles=20 .*frames=60 draws=240 uploadsPending=false lastSignal=60 resourceAllocations=6' /tmp/goldeneye-classic-textured-prop.log
cp /tmp/goldeneye-classic-textured-prop.log "${PROJECT_ROOT}/build/native/m11-runtime.log"

if [ ! -x "${CAPTURE_TOOL}" ]; then
    mkdir -p "${PROJECT_ROOT}/build/native/m11-module-cache"
    CLANG_MODULE_CACHE_PATH="${PROJECT_ROOT}/build/native/m11-module-cache" \
        swiftc -target arm64-apple-macosx14.0 \
        "${PROJECT_ROOT}/scripts/capture_macos_window.swift" \
        -o "${CAPTURE_TOOL}"
fi
pid=$(pgrep -x GoldenEyeHost | tail -n 1)
"${CAPTURE_TOOL}" "${pid}" "${PROJECT_ROOT}/build/native/m11-classic-textured-prop.png"
shasum -a 256 "${PROJECT_ROOT}/build/native/m11-classic-textured-prop.png" > \
    "${PROJECT_ROOT}/build/native/m11-pixel.sha256"

killall GoldenEyeHost >/dev/null 2>&1 || true
if [ -d /tmp/goldeneye-m11-classic-textured-prop.gputrace ]; then
    mv /tmp/goldeneye-m11-classic-textured-prop.gputrace \
        "/tmp/goldeneye-m11-classic-textured-prop.previous.$(date +%s).gputrace"
fi
: > /tmp/goldeneye-classic-textured-prop.log
: > /tmp/goldeneye-capture-status.log
open -n \
    --env MTL_CAPTURE_ENABLED=1 \
    --env GOLDENEYE_M11_TEXTURED_PROP=1 \
    --env GOLDENEYE_M11_CAPTURE=1 \
    --env GOLDENEYE_CLASSIC_PROP_ASSET="${PROP_PATH}" \
    --env GOLDENEYE_CLASSIC_TEXTURE_ROOT="${TEXTURE_ROOT}" \
    --env MTL_DEBUG_LAYER=1 \
    --env MTL_DEBUG_LAYER_ERROR_MODE=nslog \
    "${APP_DIR}"
for _ in $(seq 1 50); do
    if [ -s /tmp/goldeneye-classic-textured-prop.log ] && [ -d /tmp/goldeneye-m11-classic-textured-prop.gputrace ]; then
        break
    fi
    sleep 1
done
test -d /tmp/goldeneye-m11-classic-textured-prop.gputrace
mkdir -p "${TRACE_PATH}"
cp -R /tmp/goldeneye-m11-classic-textured-prop.gputrace/. "${TRACE_PATH}/"
test -s "${TRACE_PATH}/index"

GPUD_LOG="${PROJECT_ROOT}/build/native/m11-gpudebug.log"
gpudebug --oneshot -t "${TRACE_PATH}" \
    -c 'go commands/cb0/grp0' -c 'list --all' \
    -c 'go commands/cb0/grp0/re1' -c 'list --all' > "${GPUD_LOG}"
gpudebug --oneshot -t "${TRACE_PATH}" \
    -c 'go resources/textures' -c 'list --all' >> "${GPUD_LOG}"
gpudebug --oneshot -t "${TRACE_PATH}" \
    -c 'go commands/cb0/grp0/re1/grp0/draw0' -c 'info --all' >> "${GPUD_LOG}"
rg -q 'ce0.*3 blits' "${GPUD_LOG}"
rg -q 're1.*4 draws' "${GPUD_LOG}"
rg -q 'tex0.*64x32 RGBA8Unorm' "${GPUD_LOG}"
rg -q 'tex1.*128x16 RGBA8Unorm' "${GPUD_LOG}"
rg -q 'tex2.*32x32 RGBA8Unorm' "${GPUD_LOG}"
rg -q '1 texture, 1 sampler' "${GPUD_LOG}"

# Run the same textured renderer in a separate instrumented process for the
# lifecycle evidence that must not be conflated with the capture run.
killall GoldenEyeHost >/dev/null 2>&1 || true
: > /tmp/goldeneye-classic-textured-prop.log
: > /tmp/goldeneye-m9-resize.log
: > /tmp/goldeneye-m9-shutdown.log
open -n \
    --env GOLDENEYE_M11_TEXTURED_PROP=1 \
    --env GOLDENEYE_M9_RESIZE=1 \
    --env GOLDENEYE_CLASSIC_PROP_ASSET="${PROP_PATH}" \
    --env GOLDENEYE_CLASSIC_TEXTURE_ROOT="${TEXTURE_ROOT}" \
    --env MTL_DEBUG_LAYER=1 \
    --env MTL_DEBUG_LAYER_ERROR_MODE=nslog \
    --env MTL_SHADER_VALIDATION=1 \
    --env MTL_SHADER_VALIDATION_REPORT_TO_STDERR=1 \
    "${APP_DIR}"
for _ in $(seq 1 45); do
    if [ -s /tmp/goldeneye-classic-textured-prop.log ] && \
        [ -s /tmp/goldeneye-m9-resize.log ] && \
        pgrep -x GoldenEyeHost >/dev/null 2>&1; then
        break
    fi
    sleep 1
done
test -s /tmp/goldeneye-classic-textured-prop.log
test -s /tmp/goldeneye-m9-resize.log
cp /tmp/goldeneye-classic-textured-prop.log "${PROJECT_ROOT}/build/native/m11-runtime-resize.log"
cp /tmp/goldeneye-m9-resize.log "${PROJECT_ROOT}/build/native/m11-resize.log"
rg -q 'status=0 commands=24 drawPackets=4 vertices=40 triangles=20 .*frames=60 draws=240 uploadsPending=false lastSignal=60 resourceAllocations=6' \
    "${PROJECT_ROOT}/build/native/m11-runtime-resize.log"
rg -q 'resize=1 .*third=1024x576' "${PROJECT_ROOT}/build/native/m11-resize.log"

pid=$(pgrep -x GoldenEyeHost | tail -n 1)
if command -v gtimeout >/dev/null 2>&1; then
    set +e
    gtimeout 30 leaks --noContent --nostacks --quiet "${pid}" > \
        "${PROJECT_ROOT}/build/native/m11-leaks.log" 2>&1
    leak_status=$?
    set -e
else
    set +e
    leaks --noContent --nostacks --quiet "${pid}" > \
        "${PROJECT_ROOT}/build/native/m11-leaks.log" 2>&1
    leak_status=$?
    set -e
fi
if [ "${leak_status}" -eq 124 ]; then
    echo "leaks probe timed out; see build/native/m11-leaks.log" >&2
    exit 1
fi
rg -q '0 leaks for 0 total leaked bytes' "${PROJECT_ROOT}/build/native/m11-leaks.log"

osascript -e 'tell application id "com.goldeneye.swift.host" to quit' >/dev/null 2>&1 || true
for _ in $(seq 1 25); do
    if [ -s /tmp/goldeneye-m9-shutdown.log ]; then break; fi
    sleep 1
done
test -s /tmp/goldeneye-m9-shutdown.log
cp /tmp/goldeneye-m9-shutdown.log "${PROJECT_ROOT}/build/native/m11-shutdown.log"
rg -q '^shutdown=1$' "${PROJECT_ROOT}/build/native/m11-shutdown.log"

echo "M11 classic textured prop runtime: PASS"
echo "Runtime: ${PROJECT_ROOT}/build/native/m11-runtime.log"
echo "Pixel hash: ${PROJECT_ROOT}/build/native/m11-pixel.sha256"
echo "GPU trace: ${TRACE_PATH}"
echo "GPU inspection: ${GPUD_LOG}"
echo "Resize runtime: ${PROJECT_ROOT}/build/native/m11-runtime-resize.log"
echo "Resize: ${PROJECT_ROOT}/build/native/m11-resize.log"
echo "Leaks: ${PROJECT_ROOT}/build/native/m11-leaks.log"
echo "Shutdown: ${PROJECT_ROOT}/build/native/m11-shutdown.log"
