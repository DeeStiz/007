#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
APP_DIR="${PROJECT_ROOT}/build/native/m2/GoldenEyeHost.app"

"${SCRIPT_DIR}/build_m2_app.sh"
rm -f /tmp/goldeneye-m5-clear.log /tmp/goldeneye-m5-pause.log

for required in nextDrawable waitForDrawable signalDrawable present; do
    rg -q "${required}" "${PROJECT_ROOT}/native/host/metal_clear_renderer.swift"
done
if rg -n 'presentDrawable|MTLCommandQueue|MTLCommandBuffer' "${PROJECT_ROOT}/native/host/metal_clear_renderer.swift"; then
    echo "M5 must use the Metal 4 queue-level presentation path" >&2
    exit 1
fi

echo "Launching M5 clear with Metal API validation"
open -n "${APP_DIR}" \
    --env GOLDENEYE_M5_PAUSE_PROBE=1 \
    --env MTL_DEBUG_LAYER=1 \
    --env MTL_DEBUG_LAYER_ERROR_MODE=nslog \
    --env MTL_DEBUG_LAYER_VALIDATE_LOAD_ACTIONS=1 \
    --env MTL_DEBUG_LAYER_VALIDATE_STORE_ACTIONS=1

for _ in $(seq 1 30); do
    if [ -f /tmp/goldeneye-m5-clear.log ] && \
        rg -q 'frames=60 lastSignal=60' /tmp/goldeneye-m5-clear.log && \
        pgrep -x GoldenEyeHost >/dev/null 2>&1; then
        cat /tmp/goldeneye-m5-clear.log
        test -f /tmp/goldeneye-m5-pause.log
        rg -q 'event=syntheticWillResignActive source=NotificationCenter' /tmp/goldeneye-m5-pause.log
        rg -q 'event=focusLost reset=1 paused=1' /tmp/goldeneye-m5-pause.log
        rg -q 'event=syntheticDidBecomeActive source=NotificationCenter' /tmp/goldeneye-m5-pause.log
        rg -q 'event=focusGained paused=0' /tmp/goldeneye-m5-pause.log
        cat /tmp/goldeneye-m5-pause.log
        killall GoldenEyeHost >/dev/null 2>&1 || true
        echo "M5 first-clear validation: PASS"
        exit 0
    fi
    sleep 1
done
echo "M5 clear evidence was not produced" >&2
exit 1
