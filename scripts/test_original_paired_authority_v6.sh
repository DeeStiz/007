#!/usr/bin/env bash
set -euo pipefail

# Build and run the isolated Swift value-only paired authority.  The test
# target is deliberately not part of GoldenEyeHost: it imports the same
# GoldenEyeNative C module and the linked GoldenEyeOriginalFrontend target,
# while leaving the owner/main lane untouched.

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_ROOT="${ROOT}/build/native/original-source-v6/paired-authority-v6"
mkdir -p "${BUILD_ROOT}"

SWIFT_BUILD_ARGS=()
if [[ "${GOLDENEYE_SWIFT_BUILD_DISABLE_SANDBOX:-0}" == "1" ]]; then
    SWIFT_BUILD_ARGS+=(--disable-sandbox)
fi

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
SWIFTC=$(xcrun --sdk macosx --find swiftc)

if [[ "${#SWIFT_BUILD_ARGS[@]}" -gt 0 ]]; then
    swift build "${SWIFT_BUILD_ARGS[@]}" --target GoldenEyeNative -c debug
    swift build "${SWIFT_BUILD_ARGS[@]}" --target GoldenEyeOriginalFrontend -c debug
else
    swift build --target GoldenEyeNative -c debug
    swift build --target GoldenEyeOriginalFrontend -c debug
fi

PRODUCTS="${ROOT}/.build/out/Products/Debug"
INTERMEDIATES="${ROOT}/.build/out/Intermediates.noindex/GoldenEyeSwift.build/Debug"
NATIVE_MODULEMAP="${INTERMEDIATES}/GoldenEyeNative-t.build/GoldenEyeNative.modulemap"
ORIGINAL_MODULEMAP="${INTERMEDIATES}/GoldenEyeOriginalFrontend-t.build/GoldenEyeOriginalFrontend.modulemap"
NATIVE_OBJECT="${PRODUCTS}/GoldenEyeNative.o"
ORIGINAL_OBJECT="${PRODUCTS}/GoldenEyeOriginalFrontend.o"

for required in \
    "${NATIVE_MODULEMAP}" "${ORIGINAL_MODULEMAP}" \
    "${NATIVE_OBJECT}" "${ORIGINAL_OBJECT}"; do
    if [[ ! -f "${required}" ]]; then
        echo "paired authority build artifact missing: ${required}" >&2
        exit 1
    fi
done

OUTPUT="${BUILD_ROOT}/goldeneye_original_paired_authority_v6_smoke"
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
    "${ROOT}/native/tests/goldeneye_original_paired_authority_v6_smoke.swift" \
    "${NATIVE_OBJECT}" \
    "${ORIGINAL_OBJECT}" \
    -o "${OUTPUT}"

"${OUTPUT}" | tee "${BUILD_ROOT}/strict.log"
grep -Fq 'goldeneye_original_paired_authority_v6_smoke: PASS' \
    "${BUILD_ROOT}/strict.log"

echo "test_original_paired_authority_v6: PASS"
echo "evidence=${BUILD_ROOT}"
