#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
BUILD_DIR="${PROJECT_ROOT}/build/native/classic-replay"
PROP_DIR="${PROJECT_ROOT}/build/native/classic-prop"
PROP_PATH="${PROP_DIR}/Pammo_crate1Z.bin"
mkdir -p "${BUILD_DIR}" "${PROP_DIR}"

PREPARE_SCRIPT="${PROJECT_ROOT}/scripts/prepare_classic_prop_asset.sh"
if [[ -f "${PREPARE_SCRIPT}" ]]; then
    echo "Preparing optional ROM-derived classic prop asset"
    bash "${PREPARE_SCRIPT}"
else
    echo "Classic prop preparation: SKIP (scripts/prepare_classic_prop_asset.sh unavailable)"
fi

if command -v xcrun >/dev/null 2>&1; then
    CC=$(xcrun --sdk macosx --find clang)
    SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
else
    CC=${CC:-clang}
    SDKROOT=${SDKROOT:-}
fi

COMMON_CFLAGS=(-std=c11 -Wall -Wextra -Werror -O2 -I "${PROJECT_ROOT}/native/include")
if [[ -n "${SDKROOT}" ]]; then
    COMMON_CFLAGS+=(-target arm64-apple-macosx27.0 -isysroot "${SDKROOT}")
fi

SMOKE="${BUILD_DIR}/goldeneye_classic_replay_smoke"
SANITIZED="${BUILD_DIR}/goldeneye_classic_replay_smoke_sanitized"
SMOKE_LOG="${BUILD_DIR}/classic-replay-smoke.log"
SANITIZED_LOG="${BUILD_DIR}/classic-replay-sanitized.log"

echo "Building C classic replay smoke"
"${CC}" "${COMMON_CFLAGS[@]}" \
    "${PROJECT_ROOT}/native/src/goldeneye_native.c" \
    "${PROJECT_ROOT}/native/src/ge_classic_replay.c" \
    "${PROJECT_ROOT}/native/tests/goldeneye_classic_replay_smoke.c" \
    -lpthread -o "${SMOKE}"

echo "Running deterministic C classic replay smoke"
"${SMOKE}" "${PROP_PATH}" | tee "${SMOKE_LOG}"

echo "Building C classic replay smoke with ASan/UBSan"
"${CC}" "${COMMON_CFLAGS[@]}" -O1 -fno-omit-frame-pointer \
    -fsanitize=address,undefined \
    "${PROJECT_ROOT}/native/src/goldeneye_native.c" \
    "${PROJECT_ROOT}/native/src/ge_classic_replay.c" \
    "${PROJECT_ROOT}/native/tests/goldeneye_classic_replay_smoke.c" \
    -lpthread -o "${SANITIZED}"

echo "Running ASan/UBSan classic replay smoke"
ASAN_OPTIONS=halt_on_error=1 \
    UBSAN_OPTIONS=halt_on_error=1 \
    "${SANITIZED}" "${PROP_PATH}" | tee "${SANITIZED_LOG}"

if command -v swiftc >/dev/null 2>&1; then
    SWIFTC=$(command -v swiftc)
    if command -v xcrun >/dev/null 2>&1; then
        SWIFTC=$(xcrun --sdk macosx --find swiftc)
    fi
    SWIFT_BUILD_DIR="${BUILD_DIR}/swift"
    mkdir -p "${SWIFT_BUILD_DIR}/module-cache"
    NATIVE_OBJECTS=()
    for source in goldeneye_native ge_classic_replay; do
        object="${SWIFT_BUILD_DIR}/${source}.o"
        "${CC}" "${COMMON_CFLAGS[@]}" -c \
            "${PROJECT_ROOT}/native/src/${source}.c" -o "${object}"
        NATIVE_OBJECTS+=("${object}")
    done
    ar rcs "${SWIFT_BUILD_DIR}/libgoldeneye_native.a" "${NATIVE_OBJECTS[@]}"
    cp "${PROJECT_ROOT}/native/tests/goldeneye_classic_replay_swift_smoke.swift" \
        "${SWIFT_BUILD_DIR}/main.swift"
    SWIFT_ARGS=(-O)
    if [[ -n "${SDKROOT}" ]]; then
        SWIFT_ARGS+=(-target arm64-apple-macosx27.0 -sdk "${SDKROOT}")
    fi
    echo "Building Swift public-module classic replay smoke"
    CLANG_MODULE_CACHE_PATH="${SWIFT_BUILD_DIR}/module-cache" \
        "${SWIFTC}" "${SWIFT_ARGS[@]}" \
        -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_native_bridging.h" \
        -Xcc "-I${PROJECT_ROOT}/native/include" \
        "${SWIFT_BUILD_DIR}/libgoldeneye_native.a" \
        "${SWIFT_BUILD_DIR}/main.swift" -Xlinker -lpthread \
        -o "${SWIFT_BUILD_DIR}/goldeneye_classic_replay_swift_smoke"
    "${SWIFT_BUILD_DIR}/goldeneye_classic_replay_swift_smoke" | \
        tee "${BUILD_DIR}/classic-replay-swift-smoke.log"
else
    echo "Swift classic replay smoke: SKIP (swiftc unavailable)"
fi

REFERENCE_EVIDENCE="${PROJECT_ROOT}/.porting/m0-provenance.md"
if [[ -f "${REFERENCE_EVIDENCE}" ]] && \
   rg -q 'make -j8 IDO_RECOMP=NO VERSION=US COMPARE=1 VERBOSE=1' "${REFERENCE_EVIDENCE}" && \
   rg -q 'sha1sum -c ge007.u.sha1' "${REFERENCE_EVIDENCE}" && \
   rg -q 'abe01e4aeb033b6c0836819f549c791b26cfde83' "${REFERENCE_EVIDENCE}"; then
    echo "Linux reference-build evidence: present at ${REFERENCE_EVIDENCE}"
else
    echo "Linux reference-build evidence: WARNING missing exact command in ${REFERENCE_EVIDENCE}" >&2
fi

ROM_PATH="/Users/derek/Documents/GoldenEye 007 (USA).z64"
if [[ -f "${ROM_PATH}" ]]; then
    ROM_SHA1=$(shasum -a 1 "${ROM_PATH}" | awk '{print $1}')
    echo "External ROM SHA-1: ${ROM_SHA1} (not bundled)"
    if [[ "${ROM_SHA1}" != "abe01e4aeb033b6c0836819f549c791b26cfde83" ]]; then
        echo "external ROM SHA-1 mismatch" >&2
        exit 1
    fi
else
    echo "External ROM SHA-1: SKIP (ROM unavailable outside repository)"
fi

if git -C "${PROJECT_ROOT}" ls-files -- '*.z64' '*.Z64' '*.n64' '*.N64' | \
    rg -q .; then
    echo "external ROM boundary violated by tracked ROM" >&2
    exit 1
fi

if [[ -f "${PROP_PATH}" ]]; then
    PROP_SHA256=$(shasum -a 256 "${PROP_PATH}" | awk '{print $1}')
    PROP_SIZE=$(wc -c < "${PROP_PATH}" | tr -d '[:space:]')
    echo "Prop artifact: ${PROP_PATH} size=${PROP_SIZE} sha256=${PROP_SHA256}"
else
    echo "Prop artifact: SKIP (${PROP_PATH} unavailable)"
fi

git -C "${PROJECT_ROOT}" diff --check -- \
    native/tests/goldeneye_classic_replay_smoke.c \
    native/tests/goldeneye_classic_replay_swift_smoke.swift \
    scripts/test_classic_gbi.sh

echo "Classic GBI replay validation: PASS"
echo "Artifacts: ${SMOKE_LOG} ${SANITIZED_LOG}"
if [[ -f "${BUILD_DIR}/classic-replay-swift-smoke.log" ]]; then
    echo "Artifacts: ${BUILD_DIR}/classic-replay-swift-smoke.log"
fi
