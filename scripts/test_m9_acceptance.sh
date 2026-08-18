#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
APP_DIR="${PROJECT_ROOT}/build/native/m2/GoldenEyeHost.app"
M9_LOG="${PROJECT_ROOT}/build/native/m9-hud.log"

echo "M9 deterministic C/Swift replay"
"${SCRIPT_DIR}/test_native_m1.sh"
"${SCRIPT_DIR}/test_m7_gbi.sh"
"${SCRIPT_DIR}/test_m3_input.sh"
"${SCRIPT_DIR}/test_host_sanitizers.sh"

"${SCRIPT_DIR}/build_m6_pipeline.sh"
rm -f /tmp/goldeneye-m8-triangle.log /tmp/goldeneye-m9-resize.log /tmp/goldeneye-m9-shutdown.log
open -n --env GOLDENEYE_M8_TRIANGLE=1 --env GOLDENEYE_M9_RESIZE=1 \
    --env MTL_HUD_ENABLED=1 --env MTL_HUD_LOG_ENABLED=1 \
    --env MTL_DEBUG_LAYER=1 --env MTL_DEBUG_LAYER_ERROR_MODE=nslog \
    --env MTL_SHADER_VALIDATION=1 --env MTL_SHADER_VALIDATION_REPORT_TO_STDERR=1 \
    "${APP_DIR}"

for _ in $(seq 1 30); do
    if [ -f /tmp/goldeneye-m8-triangle.log ] && [ -f /tmp/goldeneye-m9-resize.log ] && \
        pgrep -x GoldenEyeHost >/dev/null 2>&1; then
        break
    fi
    sleep 1
done
test -f /tmp/goldeneye-m8-triangle.log
test -f /tmp/goldeneye-m9-resize.log
rg -q 'frames=60 draws=60 .*lastSignal=60 resourceAllocations=1' /tmp/goldeneye-m8-triangle.log
rg -q 'resize=1 .*third=1024x576' /tmp/goldeneye-m9-resize.log
cat /tmp/goldeneye-m8-triangle.log /tmp/goldeneye-m9-resize.log

hud_pid=$(pgrep -x GoldenEyeHost | tail -n 1)
osascript -e 'tell application id "com.goldeneye.swift.host" to quit' >/dev/null 2>&1 || true
for _ in $(seq 1 20); do
    if ! kill -0 "${hud_pid}" >/dev/null 2>&1; then break; fi
    sleep 1
done
if kill -0 "${hud_pid}" >/dev/null 2>&1; then
    kill -TERM "${hud_pid}" >/dev/null 2>&1 || true
fi

echo "Launching separate normal non-HUD process for leak probe"
open -n --env GOLDENEYE_M8_TRIANGLE=1 "${APP_DIR}"
for _ in $(seq 1 30); do
    pid=$(pgrep -x GoldenEyeHost | tail -n 1 || true)
    if [ -n "${pid}" ] && [ -f /tmp/goldeneye-m8-triangle.log ]; then break; fi
    sleep 1
done
test -n "${pid}"
echo "Running normal non-HUD leak probe for PID ${pid}"
leak_blocked=0
if command -v gtimeout >/dev/null 2>&1; then
    set +e
    gtimeout 30 leaks --noContent --nostacks --quiet "${pid}" > "${PROJECT_ROOT}/build/native/m9-leaks.log" 2>&1
    leak_status=$?
    set -e
else
    set +e
    leaks --noContent --nostacks --quiet "${pid}" > "${PROJECT_ROOT}/build/native/m9-leaks.log" 2>&1
    leak_status=$?
    set -e
fi
if [ "${leak_status}" -eq 124 ]; then
    echo "leaks probe timed out; see build/native/m9-leaks.log" >&2
    leak_blocked=1
fi
if [ "${leak_blocked}" -eq 0 ] && ! rg -n 'leaks for|total leaked bytes' "${PROJECT_ROOT}/build/native/m9-leaks.log"; then
    echo "leaks output did not contain its summary" >&2
    leak_blocked=1
fi
if [ "${leak_blocked}" -eq 0 ] && ! rg -q '0 leaks for 0 total leaked bytes' "${PROJECT_ROOT}/build/native/m9-leaks.log"; then
    echo "normal non-HUD process reported a nonzero leak count" >&2
    exit 1
fi

log show --last 2m --style compact --predicate 'process == "GoldenEyeHost" OR eventMessage CONTAINS[c] "Metal HUD" OR eventMessage CONTAINS[c] "Metal validation"' > "${M9_LOG}" 2>/dev/null || true
if rg -n 'GPU fault|Metal validation error|assertion failed' "${M9_LOG}"; then
    echo "Metal/HUD log contains a fault" >&2
    exit 1
fi

osascript -e 'tell application id "com.goldeneye.swift.host" to quit' >/dev/null 2>&1 || true
for _ in $(seq 1 20); do
    if [ -f /tmp/goldeneye-m9-shutdown.log ]; then break; fi
    sleep 1
done
test -f /tmp/goldeneye-m9-shutdown.log
cat /tmp/goldeneye-m9-shutdown.log

test -f "${PROJECT_ROOT}/build/native/m8-pixel.sha256"
test -f "${PROJECT_ROOT}/build/native/m8-triangle.gputrace/index"
strings "${PROJECT_ROOT}/build/native/m8-triangle.gputrace"/* 2>/dev/null | rg -q 'GoldenEye.M8.Triangle.Draw.0'
if [ "${leak_blocked}" -eq 1 ]; then
    echo "M9 runtime/HUD/resize/shutdown checks: PASS"
    echo "M9 acceptance remains incomplete: global leaks summary unavailable (see build/native/m9-leaks.log)" >&2
    exit 2
fi
echo "M9 acceptance checks (static gpudebug inspection; resource fetch is separate): PASS"
