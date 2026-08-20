#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${1:-${GOLDENEYE_NATIVE_RAMROM_ASSET_ROOT:-${PROJECT_ROOT}/build/native/boot-assets/ramrom}}"
STAGE_ROOT="${2:-${GOLDENEYE_NATIVE_STAGE_ASSET_ROOT:-${PROJECT_ROOT}/build/native/stage-assets-image-decoder-v6}}"
BUILD_DIR="${PROJECT_ROOT}/build/native/ramrom-all14-validation"
MODULE_CACHE_DIR="${BUILD_DIR}/module-cache"
mkdir -p "${BUILD_DIR}" "${MODULE_CACHE_DIR}"

if command -v xcrun >/dev/null 2>&1; then
    RAMROM_ALL14_CC=$(xcrun --sdk macosx --find clang)
    RAMROM_ALL14_SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
else
    RAMROM_ALL14_CC=${RAMROM_ALL14_CC:-clang}
    RAMROM_ALL14_SDKROOT=""
fi

COMMON_FLAGS=(
    -std=c11 -Wall -Wextra -Werror -pedantic -O2
    -I "${PROJECT_ROOT}/native/include"
)
TARGET_FLAGS=()
if [[ -n "${RAMROM_ALL14_SDKROOT}" ]]; then
    TARGET_FLAGS=(
        -target arm64-apple-macosx27.0
        -isysroot "${RAMROM_ALL14_SDKROOT}"
    )
fi

SOURCES=(
    "${PROJECT_ROOT}/native/src/ge_ramrom_v5.c"
    "${PROJECT_ROOT}/native/src/ge_ramrom_playback_v5.c"
    "${PROJECT_ROOT}/native/src/ge_native_runtime_v5.c"
    "${PROJECT_ROOT}/native/src/ge_audio_v5.c"
    "${PROJECT_ROOT}/native/tests/goldeneye_ramrom_all14_validation.c"
)
SMOKE="${BUILD_DIR}/goldeneye_ramrom_all14_validation"
SANITIZED="${BUILD_DIR}/goldeneye_ramrom_all14_validation_sanitized"
LOG="${BUILD_DIR}/ramrom-all14.log"
ASAN_LOG="${BUILD_DIR}/ramrom-all14-asan.log"

echo "Building strict all-14 RAMROM parser/playback validation"
"${RAMROM_ALL14_CC}" "${TARGET_FLAGS[@]}" "${COMMON_FLAGS[@]}" \
    "${SOURCES[@]}" -o "${SMOKE}"
"${SMOKE}" "${ASSET_ROOT}" | tee "${LOG}"
grep -Fq 'goldeneye_ramrom_all14_validation: PASS demos=14 runs=28 abort_restore=14 unique_stages=7 parser=PASS playback=PASS checksum=PASS rng=PASS gameplay_boundary=STUB(M26) renderer_boundary=STUB(M27)' "${LOG}"

echo "Building ASan/UBSan all-14 RAMROM validation"
"${RAMROM_ALL14_CC}" "${TARGET_FLAGS[@]}" "${COMMON_FLAGS[@]}" \
    -O1 -fno-omit-frame-pointer -fsanitize=address,undefined \
    "${SOURCES[@]}" -o "${SANITIZED}"
ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 \
    "${SANITIZED}" "${ASSET_ROOT}" | tee "${ASAN_LOG}"
grep -Fq 'goldeneye_ramrom_all14_validation: PASS demos=14 runs=28 abort_restore=14 unique_stages=7 parser=PASS playback=PASS checksum=PASS rng=PASS gameplay_boundary=STUB(M26) renderer_boundary=STUB(M27)' "${ASAN_LOG}"

if command -v xcrun >/dev/null 2>&1; then
    RAMROM_ALL14_SWIFTC=$(xcrun --sdk macosx --find swiftc)
else
    RAMROM_ALL14_SWIFTC=${RAMROM_ALL14_SWIFTC:-swiftc}
fi
SERVICE_SWIFT_ARGS=(-swift-version 6 -warnings-as-errors)
if [[ -n "${RAMROM_ALL14_SDKROOT}" ]]; then
    SERVICE_SWIFT_ARGS+=(
        -target arm64-apple-macosx27.0
        -sdk "${RAMROM_ALL14_SDKROOT}"
    )
fi
SERVICE_OBJECTS=()
for source in \
    "${PROJECT_ROOT}/native/src/ge_ramrom_v5.c" \
    "${PROJECT_ROOT}/native/src/ge_ramrom_playback_v5.c" \
    "${PROJECT_ROOT}/native/src/ge_native_runtime_v5.c" \
    "${PROJECT_ROOT}/native/src/ge_audio_v5.c"; do
    object="${BUILD_DIR}/service-$(basename "${source}" .c).o"
    "${RAMROM_ALL14_CC}" "${TARGET_FLAGS[@]}" "${COMMON_FLAGS[@]}" \
        -c "${source}" -o "${object}"
    SERVICE_OBJECTS+=("${object}")
done
SERVICE_ARCHIVE="${BUILD_DIR}/libgoldeneye_ramrom_all14_service.a"
ar rcs "${SERVICE_ARCHIVE}" "${SERVICE_OBJECTS[@]}"
SERVICE_SMOKE="${BUILD_DIR}/goldeneye_ramrom_all14_service_smoke"
echo "Building Swift all-14 owner-service validation"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${RAMROM_ALL14_SWIFTC}" \
    "${SERVICE_SWIFT_ARGS[@]}" \
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_ramrom_playback_service_bridging.h" \
    -Xcc "-I${PROJECT_ROOT}/native/include" \
    "${PROJECT_ROOT}/native/host/goldeneye_attract_route.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_cast_title_hash.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_ramrom_playback_service.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_ramrom_playback_service_hash.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_ramrom_all14_service_smoke.swift" \
    "${SERVICE_ARCHIVE}" -o "${SERVICE_SMOKE}"
SERVICE_LOG="${BUILD_DIR}/ramrom-all14-service.log"
SERVICE_ASSET_ROOT="${ASSET_ROOT}"
if [[ "$(basename -- "${SERVICE_ASSET_ROOT}")" == "ramrom" ]]; then
    SERVICE_ASSET_ROOT="$(dirname -- "${SERVICE_ASSET_ROOT}")"
fi
"${SERVICE_SMOKE}" "${SERVICE_ASSET_ROOT}" \
    | tee "${SERVICE_LOG}"
grep -Fq 'goldeneye_ramrom_all14_service_smoke: PASS demos=14 runs=28 abort_restore=14' \
    "${SERVICE_LOG}"

if [[ ! -d "${STAGE_ROOT}" ]]; then
    echo "Stage scene preparation requires the guarded stage asset root: ${STAGE_ROOT}" >&2
    exit 1
fi

echo "Preparing all seven native stage scene packets"
"${SCRIPT_DIR}/test_stage_scene_packet.sh" "${STAGE_ROOT}" \
    | tee "${BUILD_DIR}/stage-scene-packet.log"
grep -Fq 'goldeneye_stage_scene_packet_smoke: PASS stages=7' \
    "${BUILD_DIR}/stage-scene-packet.log"

git -C "${PROJECT_ROOT}" diff --check
echo "RAMROM all-14 parser/playback/stage-scene validation: PASS"
