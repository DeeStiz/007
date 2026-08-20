#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/goldeneye-title-nodes.XXXXXX")
trap 'rm -rf "${TEMP_ROOT}"' EXIT

python3 "${SCRIPT_DIR}/prepare_native_title_nodes.py" \
    --project-root "${PROJECT_ROOT}" \
    --output-root "${TEMP_ROOT}/title" \
    --report "${TEMP_ROOT}/title/native-title-node-report.txt"

if command -v xcrun >/dev/null 2>&1; then
    SWIFTC=$(xcrun --sdk macosx --find swiftc)
    SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
else
    SWIFTC=${SWIFTC:-swiftc}
    SDKROOT=""
fi
ARGS=(-swift-version 6)
if [[ -n "${SDKROOT}" ]]; then ARGS+=(-target arm64-apple-macosx27.0 -sdk "${SDKROOT}"); fi
"${SWIFTC}" "${ARGS[@]}" \
    "${PROJECT_ROOT}/native/host/goldeneye_title_node_packet.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_title_node_packet_smoke.swift" \
    -o "${TEMP_ROOT}/goldeneye_title_node_packet_smoke"
"${TEMP_ROOT}/goldeneye_title_node_packet_smoke" "${TEMP_ROOT}/title"
git -C "${PROJECT_ROOT}" diff --check
echo "Native title node validation: PASS"
