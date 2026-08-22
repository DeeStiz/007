#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${1:-${GOLDENEYE_NATIVE_SOURCE_FRONTEND_ROOT:-${PROJECT_ROOT}/build/native/source-frontend-v6}}"
BUILD_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/goldeneye-source-texture-store-v6.XXXXXX")
trap 'rm -rf "${BUILD_ROOT}"' EXIT
mkdir -p "${BUILD_ROOT}/module-cache" "${BUILD_ROOT}/asan" "${BUILD_ROOT}/ubsan"
export CLANG_MODULE_CACHE_PATH="${BUILD_ROOT}/module-cache"

if command -v xcrun >/dev/null 2>&1; then
    SWIFTC=$(xcrun --sdk macosx --find swiftc)
    SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
    SWIFT_PLATFORM=(-target arm64-apple-macosx27.0 -sdk "${SDKROOT}")
else
    SWIFTC=${SWIFTC:-swiftc}
    SWIFT_PLATFORM=()
fi

if [[ ! -d "${ASSET_ROOT}" ]]; then
    echo "source texture store V6: missing prepared asset root: ${ASSET_ROOT}" >&2
    exit 1
fi

SMOKE="${BUILD_ROOT}/goldeneye_source_texture_store_v6_smoke"
LOG="${BUILD_ROOT}/source-texture-store-v6-smoke.log"

echo "Building strict Swift 6 source texture store V6 smoke"
"${SWIFTC}" -swift-version 6 -warnings-as-errors -O -parse-as-library \
    "${SWIFT_PLATFORM[@]}" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_catalog_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_model_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_texture_store_v6.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_source_texture_store_v6_smoke.swift" \
    -o "${SMOKE}"

if [[ "${GOLDENEYE_SOURCE_TEXTURE_FIXTURES_ONLY:-0}" == "1" ]]; then
    "${SMOKE}" --fixtures-only | tee "${LOG}"
else
    "${SMOKE}" "${ASSET_ROOT}" | tee "${LOG}"
fi
grep -Fq 'source-texture-store-v6 pure upload plans: PASS models=5' "${LOG}"
grep -Fq 'goldeneye_source_texture_store_v6_smoke: PASS' "${LOG}"
if grep -Fq 'source-texture-store-v6 Metal upload smoke: PASS' "${LOG}"; then
    grep -Fq 'gpu_palettes=0' "${LOG}"
else
    grep -Fq 'source-texture-store-v6 Metal upload smoke: SKIP' "${LOG}"
fi
if [[ "${GOLDENEYE_SOURCE_TEXTURE_FIXTURES_ONLY:-0}" != "1" ]]; then
    grep -Fq 'source-texture-store-v6 source plan: PASS' "${LOG}"
    grep -Fq 'textures=122 levels=322 validated_palettes=25 unique_handles=122' "${LOG}"
    grep -Fq 'validated_palettes=' "${LOG}"
fi

for variant in asan ubsan; do
    SANITIZER="address"
    if [[ "${variant}" == "ubsan" ]]; then SANITIZER="undefined"; fi
    SANITIZER_BIN="${BUILD_ROOT}/${variant}/goldeneye_source_texture_store_v6_smoke"
    SANITIZER_LOG="${BUILD_ROOT}/${variant}.log"
    echo "Building ${variant} Swift 6 source texture store V6 smoke"
    "${SWIFTC}" -swift-version 6 -warnings-as-errors -Onone \
        -sanitize="${SANITIZER}" -parse-as-library \
        "${SWIFT_PLATFORM[@]}" \
        "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_catalog_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_source_model_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_source_texture_store_v6.swift" \
        "${PROJECT_ROOT}/native/tests/goldeneye_source_texture_store_v6_smoke.swift" \
        -o "${SANITIZER_BIN}"
    if [[ "${variant}" == "asan" ]]; then
        ASAN_OPTIONS=halt_on_error=1:detect_leaks=0 \
            GOLDENEYE_SKIP_METAL_UPLOAD_SMOKE=1 \
            "${SANITIZER_BIN}" "${ASSET_ROOT}" | tee "${SANITIZER_LOG}"
    else
        UBSAN_OPTIONS=halt_on_error=1 \
            GOLDENEYE_SKIP_METAL_UPLOAD_SMOKE=1 \
            "${SANITIZER_BIN}" "${ASSET_ROOT}" | tee "${SANITIZER_LOG}"
    fi
    grep -Fq 'source-texture-store-v6 source plan: PASS' "${SANITIZER_LOG}"
    grep -Fq 'goldeneye_source_texture_store_v6_smoke: PASS' "${SANITIZER_LOG}"
done

git -C "${PROJECT_ROOT}" diff --check -- \
    native/host/goldeneye_source_texture_store_v6.swift \
    native/tests/goldeneye_source_texture_store_v6_smoke.swift \
    scripts/test_source_texture_store_v6.sh

echo "Source texture store V6 validation: PASS"
echo "Artifact: ${LOG}"
