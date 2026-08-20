#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="${PROJECT_ROOT}/build/native/source-product-preparation-v6"
mkdir -p "${BUILD_DIR}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
SWIFTC=$(xcrun --sdk macosx --find swiftc)
COMMON=(-swift-version 6 -warnings-as-errors -target arm64-apple-macosx27.0 -sdk "${SDKROOT}"
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_native_bridging.h"
    -Xcc "-I${PROJECT_ROOT}/native/include" -Xcc -include
    -Xcc "${PROJECT_ROOT}/native/include/ge_source_frontend_runtime_v6.h")

"${SWIFTC}" "${COMMON[@]}" -O \
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_catalog_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_model_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_product_contract_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_product_preparation_v6.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_source_product_preparation_v6_smoke.swift" \
    -o "${BUILD_DIR}/goldeneye_source_product_preparation_v6_smoke"

"${BUILD_DIR}/goldeneye_source_product_preparation_v6_smoke" \
    "${PROJECT_ROOT}/build/native/source-frontend-v6-image-decoder-v6" \
    | tee "${BUILD_DIR}/source-product-preparation-v6.log"
grep -Fq 'goldeneye_source_product_preparation_v6_smoke: PASS' \
    "${BUILD_DIR}/source-product-preparation-v6.log"

git -C "${PROJECT_ROOT}" diff --check -- \
    native/host/goldeneye_source_product_preparation_v6.swift \
    native/tests/goldeneye_source_product_preparation_v6_smoke.swift \
    scripts/test_source_product_preparation_v6.sh

echo 'Source product preparation V6 validation: PASS (strict catalog + GESM set)'
echo "Artifact: ${BUILD_DIR}/source-product-preparation-v6.log"
