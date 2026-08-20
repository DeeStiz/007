#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${PROJECT_ROOT}/build/native/stage-assets/background"
BUILD_DIR="${PROJECT_ROOT}/build/native/stage-background-v5"

mkdir -p "${BUILD_DIR}"
if command -v xcrun >/dev/null 2>&1; then
    STAGE_CC=$(xcrun --sdk macosx --find clang)
    STAGE_SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
else
    STAGE_CC=${STAGE_CC:-clang}
    STAGE_SDKROOT=""
fi

COMMON_FLAGS=(
    -std=c11 -Wall -Wextra -Werror -pedantic -O2
    -I "${PROJECT_ROOT}/native/include"
)
if [[ -n "${STAGE_SDKROOT}" ]]; then
    COMMON_FLAGS+=(
        -target arm64-apple-macosx27.0
        -isysroot "${STAGE_SDKROOT}"
    )
fi

ASSETS=(
    "${ASSET_ROOT}/Dam__background__bg_dam_all_p.bin"
    "${ASSET_ROOT}/Facility__background__bg_ark_all_p.bin"
    "${ASSET_ROOT}/Runway__background__bg_run_all_p.bin"
    "${ASSET_ROOT}/Bunker_I__background__bg_sev_all_p.bin"
    "${ASSET_ROOT}/Silo__background__bg_silo_all_p.bin"
    "${ASSET_ROOT}/Frigate__background__bg_dest_all_p.bin"
    "${ASSET_ROOT}/Train__background__bg_tra_all_p.bin"
)
for asset in "${ASSETS[@]}"; do
    [[ -f "${asset}" ]] || {
        echo "missing prepared background asset: ${asset}" >&2
        exit 1
    }
done

SOURCES=(
    "${PROJECT_ROOT}/native/src/ge_stage_v5.c"
    "${PROJECT_ROOT}/native/src/ge_stage_background_v5.c"
    "${PROJECT_ROOT}/native/tests/goldeneye_stage_background_v5_smoke.c"
)
SMOKE="${BUILD_DIR}/goldeneye_stage_background_v5_smoke"
SANITIZED="${BUILD_DIR}/goldeneye_stage_background_v5_smoke_sanitized"

echo "Building strict C stage background V5 smoke"
"${STAGE_CC}" "${COMMON_FLAGS[@]}" "${SOURCES[@]}" -o "${SMOKE}"
"${SMOKE}" "${ASSETS[@]}"

echo "Building ASan/UBSan stage background V5 smoke"
"${STAGE_CC}" "${COMMON_FLAGS[@]}" -O1 -fno-omit-frame-pointer \
    -fsanitize=address,undefined "${SOURCES[@]}" -o "${SANITIZED}"
ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 \
    "${SANITIZED}" "${ASSETS[@]}"

echo "Stage background V5 validation: PASS"
