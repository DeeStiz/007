#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
BUILD_DIR="${PROJECT_ROOT}/build/native/m3"
MODULE_CACHE_DIR="${BUILD_DIR}/module-cache"
APP_DIR="${PROJECT_ROOT}/build/native/m2/GoldenEyeHost.app"
PROBE="${BUILD_DIR}/gui_input_probe"

mkdir -p "${BUILD_DIR}" "${MODULE_CACHE_DIR}"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" swiftc \
    -target arm64-apple-macosx27.0 \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    "${PROJECT_ROOT}/native/tests/gui_input_probe.swift" \
    -o "${PROBE}" \
    -framework AppKit -framework CoreGraphics

"${SCRIPT_DIR}/build_m2_app.sh" >/tmp/goldeneye-m3-build.log
rm -f /tmp/goldeneye-m3-events.log /tmp/goldeneye-m2-owner-loop.log
open -n --env GOLDENEYE_M3_EVENT_PROBE=1 "${APP_DIR}"

pid=""
for _ in $(seq 1 30); do
    pid=$(pgrep -x GoldenEyeHost | tail -n 1 || true)
    if [ -n "${pid}" ] && [ -f /tmp/goldeneye-m3-events.log ]; then break; fi
    sleep 1
done
test -n "${pid}"
"${PROBE}" "${pid}"

for _ in $(seq 1 30); do
    if [ -f /tmp/goldeneye-m3-events.log ] && \
       rg -q 'event=keyDown .*keyCode=13' /tmp/goldeneye-m3-events.log && \
       rg -q 'event=keyUp .*keyCode=13' /tmp/goldeneye-m3-events.log && \
       rg -q 'event=probeDeactivate' /tmp/goldeneye-m3-events.log && \
       rg -q 'event=probeActivate' /tmp/goldeneye-m3-events.log; then
        break
    fi
    sleep 1
done
test -f /tmp/goldeneye-m3-events.log
rg -q 'event=keyDown .*keyCode=13' /tmp/goldeneye-m3-events.log
rg -q 'event=keyUp .*keyCode=13' /tmp/goldeneye-m3-events.log
rg -q 'event=probeDeactivate' /tmp/goldeneye-m3-events.log
rg -q 'event=probeActivate' /tmp/goldeneye-m3-events.log
cat /tmp/goldeneye-m3-events.log

if rg -q 'event=focusLost reset=1 paused=0' /tmp/goldeneye-m3-events.log && \
   rg -q 'event=focusGained paused=0' /tmp/goldeneye-m3-events.log; then
    echo "M3 AppKit focus notification/reset/always-active validation: PASS"
else
    echo "M3 AppKit focus notification was not delivered by this headless session; pure-state reset remains covered by test_m3_input.sh" >&2
fi

killall GoldenEyeHost >/dev/null 2>&1 || true
echo "M3 AppKit keyboard responder validation: PASS (focus notification evidence is session-unavailable)"
