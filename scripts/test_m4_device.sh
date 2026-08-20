#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
APP_DIR="${PROJECT_ROOT}/build/native/m2/GoldenEyeHost.app"

"${SCRIPT_DIR}/build_m2_app.sh"
rm -f /tmp/goldeneye-m4-device.log

if rg -n 'nextDrawable|\.present\(' "${PROJECT_ROOT}/native/host/metal_device_state.swift"; then
    echo "M4 device state must not acquire or present a drawable" >&2
    exit 1
fi

echo "Launching M4 device setup with Metal API validation"
open -n "${APP_DIR}" \
    --env MTL_DEBUG_LAYER=1 \
    --env MTL_DEBUG_LAYER_ERROR_MODE=nslog

for _ in $(seq 1 30); do
    if [ -f /tmp/goldeneye-m4-device.log ] && \
        rg -q 'metal4=1 .*slots=2 .*sceneResidencyDescriptor=GoldenEye\.M4\.SceneResidency .*layerResidency=1' /tmp/goldeneye-m4-device.log && \
        pgrep -x GoldenEyeHost >/dev/null 2>&1; then
        cat /tmp/goldeneye-m4-device.log
        killall GoldenEyeHost >/dev/null 2>&1 || true
        echo "M4 Metal device validation: PASS"
        exit 0
    fi
    sleep 1
done
echo "Metal 4 device evidence was not produced" >&2
exit 1
