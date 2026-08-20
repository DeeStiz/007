#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/goldeneye-title-text.XXXXXX")
trap 'rm -rf "${BUILD_DIR}"' EXIT

swiftc -O -parse-as-library \
    "${PROJECT_ROOT}/native/host/goldeneye_title_text_catalog.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_title_text_catalog_smoke.swift" \
    -o "${BUILD_DIR}/goldeneye_title_text_catalog_smoke"

"${BUILD_DIR}/goldeneye_title_text_catalog_smoke" \
    "${PROJECT_ROOT}/build/native/boot-assets"

echo "Title text catalog validation: PASS"
