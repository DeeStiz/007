#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
APP_DIR="${PROJECT_ROOT}/build/native/m2/GoldenEyeHost.app"

"${SCRIPT_DIR}/build_m6_pipeline.sh"
rm -f /tmp/goldeneye-m6-pipeline.log
open -n --env GOLDENEYE_M6_PIPELINE=1 --env MTL_DEBUG_LAYER=1 \
    --env MTL_DEBUG_LAYER_ERROR_MODE=nslog "${APP_DIR}"

for _ in $(seq 1 30); do
    if [ -f /tmp/goldeneye-m6-pipeline.log ] && \
        rg -q 'pipeline=1 label=GoldenEye\.M6\.BaselinePipeline draws=0' /tmp/goldeneye-m6-pipeline.log && \
        pgrep -x GoldenEyeHost >/dev/null 2>&1; then
        cat /tmp/goldeneye-m6-pipeline.log
        killall GoldenEyeHost >/dev/null 2>&1 || true
        echo "M6 baseline pipeline validation: PASS"
        exit 0
    fi
    sleep 1
done
echo "M6 pipeline evidence was not produced" >&2
exit 1
