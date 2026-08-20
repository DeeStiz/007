#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
RUN_ID="${GE_GUNBARREL_TRANSITION_RUN_ID:-latest}"
BUILD_ROOT="${ROOT}/build/native/gunbarrel-transition-projection-v6/${RUN_ID}"
mkdir -p "${BUILD_ROOT}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
SWIFTC=$(xcrun --sdk macosx --find swiftc)

swift build --target GoldenEyeNative -c debug
swift build --target GoldenEyeOriginalFrontend -c debug

PRODUCTS="${ROOT}/.build/out/Products/Debug"
INTERMEDIATES="${ROOT}/.build/out/Intermediates.noindex/GoldenEyeSwift.build/Debug"
NATIVE_MODULEMAP="${INTERMEDIATES}/GoldenEyeNative-t.build/GoldenEyeNative.modulemap"
ORIGINAL_MODULEMAP="${INTERMEDIATES}/GoldenEyeOriginalFrontend-t.build/GoldenEyeOriginalFrontend.modulemap"
NATIVE_OBJECT="${PRODUCTS}/GoldenEyeNative.o"
ORIGINAL_OBJECT="${PRODUCTS}/GoldenEyeOriginalFrontend.o"
for required in \
    "${NATIVE_MODULEMAP}" "${ORIGINAL_MODULEMAP}" \
    "${NATIVE_OBJECT}" "${ORIGINAL_OBJECT}"; do
    test -f "${required}"
done

OUTPUT="${BUILD_ROOT}/goldeneye_gunbarrel_transition_projection_v6_smoke"
"${SWIFTC}" \
    -sdk "${SDKROOT}" \
    -target arm64-apple-macosx27.0 \
    -warnings-as-errors \
    -Xcc -DSWIFT_PACKAGE \
    -Xcc -fmodule-map-file="${NATIVE_MODULEMAP}" \
    -Xcc -fmodule-map-file="${ORIGINAL_MODULEMAP}" \
    -Xcc -I -Xcc "${ROOT}/native/include" \
    -Xcc -I -Xcc "${ROOT}/native/source_port/original/public" \
    "${ROOT}/native/host/save_store.swift" \
    "${ROOT}/native/host/goldeneye_file_mode_authority_v6.swift" \
    "${ROOT}/native/host/goldeneye_source_frontend_authority_v6.swift" \
    "${ROOT}/native/host/goldeneye_original_paired_authority_v6.swift" \
    "${ROOT}/native/tests/goldeneye_gunbarrel_transition_projection_v6_smoke.swift" \
    "${NATIVE_OBJECT}" \
    "${ORIGINAL_OBJECT}" \
    -o "${OUTPUT}"

TRACE="${BUILD_ROOT}/transition.tsv"
"${OUTPUT}" "${TRACE}" | tee "${BUILD_ROOT}/strict.log"
grep -Fq 'goldeneye_gunbarrel_transition_projection_v6_smoke: PASS' \
    "${BUILD_ROOT}/strict.log"
grep -Fq $'handoff=source-authority-complete' "${TRACE}"
grep -Fq $'observedModes=2,3,4,5,6,7,8,9' "${TRACE}"
echo "test_gunbarrel_transition_projection_v6: PASS"
echo "evidence=${BUILD_ROOT}"
