#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_ROOT="${PROJECT_ROOT}/build/native/legal-frame-v6"
STRICT="${BUILD_ROOT}/strict"
SANITIZED="${BUILD_ROOT}/sanitizers"
mkdir -p "${STRICT}" "${SANITIZED}"
ASSET_ROOT="${1:-${PROJECT_ROOT}/build/native/source-frontend-v6}"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun --sdk macosx --find clang)
SWIFTC=$(xcrun --sdk macosx --find swiftc)

CFLAGS=(
    -std=c11 -Wall -Wextra -Werror -Wno-c23-extensions -pedantic
    -target arm64-apple-macosx27.0 -isysroot "${SDKROOT}"
    -I "${PROJECT_ROOT}/native/include"
    -I "${PROJECT_ROOT}/native/source_port"
)
SWIFT_FLAGS=(
    -swift-version 6 -warnings-as-errors -Onone
    -target arm64-apple-macosx27.0 -sdk "${SDKROOT}"
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_native_bridging.h"
    -Xcc "-I${PROJECT_ROOT}/native/include"
    -Xcc "-I${PROJECT_ROOT}/native/source_port"
)

compile_c() {
    local out="$1"
    shift
    "${CC}" "${CFLAGS[@]}" "$@" -O2 -c \
        "${PROJECT_ROOT}/native/src/ge_source_frontend_runtime_v6.c" \
        -o "${out}/ge_source_frontend_runtime_v6.o"
    "${CC}" "${CFLAGS[@]}" "$@" -O2 -c \
        "${PROJECT_ROOT}/native/source_port/ge_source_frontend_v6.c" \
        -o "${out}/ge_source_frontend_v6.o"
    "${CC}" "${CFLAGS[@]}" "$@" -O2 -c \
        "${PROJECT_ROOT}/native/src/ge_source_scene_v6.c" \
        -o "${out}/ge_source_scene_v6.o"
    "${CC}" "${CFLAGS[@]}" "$@" -O2 -c \
        "${PROJECT_ROOT}/native/src/ge_source_gbi_v6.c" \
        -o "${out}/ge_source_gbi_v6.o"
    "${CC}" "${CFLAGS[@]}" "$@" -O2 -c \
        "${PROJECT_ROOT}/native/src/ge_file_mode_v6.c" \
        -o "${out}/ge_file_mode_v6.o"
    "${CC}" "${CFLAGS[@]}" "$@" -O2 -c \
        "${PROJECT_ROOT}/native/src/ge_source_texture_coordinates_v6.c" \
        -o "${out}/ge_source_texture_coordinates_v6.o"
}

compile_swift() {
    local out="$1"
    shift
    "${SWIFTC}" "${SWIFT_FLAGS[@]}" "$@" \
        "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_catalog_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_source_product_preparation_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_source_product_contract_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_source_model_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_source_scene_snapshot_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_source_projection_binding_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_matrices_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_source_product_provider_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_source_lighting_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_source_texture_coordinates_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_source_texture_store_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_source_scene_texture_binding_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_source_texture_setup_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_gbi_scene_builder_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_source_node_transform_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_source_2d_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_file_mode_background_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_source_frontend_authority_v6.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_file_mode_authority_v6.swift" \
        "${PROJECT_ROOT}/native/host/save_store.swift" \
        "${PROJECT_ROOT}/native/host/goldeneye_legal_frame_v6.swift" \
        "${PROJECT_ROOT}/native/tests/goldeneye_legal_frame_v6_smoke.swift" \
        "${out}/ge_source_frontend_runtime_v6.o" \
        "${out}/ge_source_frontend_v6.o" \
        "${out}/ge_source_scene_v6.o" \
        "${out}/ge_source_gbi_v6.o" \
        "${out}/ge_file_mode_v6.o" \
        "${out}/ge_source_texture_coordinates_v6.o" \
        -o "${out}/goldeneye_legal_frame_v6_smoke"
}

compile_c "${STRICT}"
compile_swift "${STRICT}"
"${STRICT}/goldeneye_legal_frame_v6_smoke" \
    "${ASSET_ROOT}" \
    "${STRICT}/legal-frame-manifest.txt" \
    | tee "${STRICT}/legal-frame-v6.log"
grep -Fq 'goldeneye_legal_frame_v6_smoke: PASS' "${STRICT}/legal-frame-v6.log"
grep -Fq 'source_gbi_commands=58' "${STRICT}/legal-frame-manifest.txt"
grep -Fq 'source_triangles=12' "${STRICT}/legal-frame-manifest.txt"
grep -Fq 'source_text_order=7,8,9,10,11,12,13,14,15,16,17,18' "${STRICT}/legal-frame-manifest.txt"
grep -Fq 'unsupported_visible_commands=0' "${STRICT}/legal-frame-manifest.txt"
grep -Fq 'unsupported_decoder_commands=0' "${STRICT}/legal-frame-manifest.txt"

SAN_FLAGS=(-fsanitize=address,undefined -fno-omit-frame-pointer)
compile_c "${SANITIZED}" "${SAN_FLAGS[@]}"
SWIFT_SAN_FLAGS=(-sanitize=address,undefined)
compile_swift "${SANITIZED}" "${SWIFT_SAN_FLAGS[@]}"
ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 \
    "${SANITIZED}/goldeneye_legal_frame_v6_smoke" \
    "${ASSET_ROOT}" \
    "${SANITIZED}/legal-frame-manifest.txt" \
    | tee "${SANITIZED}/legal-frame-v6.log"
grep -Fq 'goldeneye_legal_frame_v6_smoke: PASS' "${SANITIZED}/legal-frame-v6.log"

git -C "${PROJECT_ROOT}" diff --check -- \
    native/host/goldeneye_legal_frame_v6.swift \
    native/tests/goldeneye_legal_frame_v6_smoke.swift \
    scripts/test_legal_frame_v6.sh

echo 'Legal source frame V6 validation: PASS (strict, ASan, UBSan)'
echo "Artifact: ${STRICT}/legal-frame-v6.log"
