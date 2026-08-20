#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/goldeneye-title-text.XXXXXX")

mkdir -p "${TEMP_ROOT}/title"
python3 "${SCRIPT_DIR}/prepare_native_title_text.py" \
    --project-root "${PROJECT_ROOT}" \
    --output-root "${TEMP_ROOT}/title" \
    --report "${TEMP_ROOT}/title/native-title-text-report.txt"

swiftc -O -parse-as-library \
    "${PROJECT_ROOT}/native/host/title_font_packet.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_title_text_catalog.swift" \
    "${PROJECT_ROOT}/native/host/title_geometry_packet.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_title_ui_bounds.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_title_text_packet.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_title_text_packet_smoke.swift" \
    -o "${TEMP_ROOT}/goldeneye_title_text_packet_smoke"

"${TEMP_ROOT}/goldeneye_title_text_packet_smoke" "${TEMP_ROOT}"
printf '%s\n' 'native title text smoke: PASS'
