#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
MODULE_CACHE="${PROJECT_ROOT}/build/native/source-product-2d-integration-v6/module-cache"
mkdir -p "${MODULE_CACHE}"
export CLANG_MODULE_CACHE_PATH="${MODULE_CACHE}"

PRODUCT_RENDERER="${PROJECT_ROOT}/native/host/goldeneye_source_product_renderer_v6.swift"
SCENE_RENDERER="${PROJECT_ROOT}/native/host/metal_source_scene_renderer_v6.swift"
TEXTURE_BINDING_ADAPTER="${PROJECT_ROOT}/native/host/goldeneye_source_scene_texture_binding_v6.swift"
SOURCE_2D_RENDERER="${PROJECT_ROOT}/native/host/goldeneye_source_2d_renderer_v6.swift"
BUILD_SCRIPT="${SCRIPT_DIR}/build_native_boot.sh"
VERIFY_SCRIPT="${SCRIPT_DIR}/verify_native_boot_release.sh"

for path in "${PRODUCT_RENDERER}" "${SCENE_RENDERER}" "${TEXTURE_BINDING_ADAPTER}" "${SOURCE_2D_RENDERER}" "${BUILD_SCRIPT}" "${VERIFY_SCRIPT}"; do
    [[ -f "${path}" ]] || {
        echo "missing source-2d integration input: ${path}" >&2
        exit 1
    }
done

grep -Fq 'GoldenEyeSource2DAssetsV6(catalog: preparation.catalog)' "${PRODUCT_RENDERER}"
grep -Fq 'GoldenEyeSource2DFileModeViewV6' "${PRODUCT_RENDERER}"
grep -Fq 'fileModeSaveState' "${PRODUCT_RENDERER}"
grep -Fq 'source2DRenderer.encodeOverlay' "${PRODUCT_RENDERER}"
grep -Fq 'textureBindingAdapter' "${PRODUCT_RENDERER}"
grep -Fq 'GoldenEyeSourceSceneTextureBindingAdapterV6' "${SCENE_RENDERER}"
grep -Fq 'source2DLibraryURL' "${PRODUCT_RENDERER}"
grep -Fq 'overlay: ((any MTL4RenderCommandEncoder, Int) throws -> Void)? = nil' "${SCENE_RENDERER}"
grep -Fq 'try overlay?(encoder, slotIndex)' "${SCENE_RENDERER}"
grep -Fq 'func encodeOverlay' "${SOURCE_2D_RENDERER}"
grep -Fq 'GoldenEyeSource2DV6.metal' "${BUILD_SCRIPT}"
grep -Fq 'GoldenEyeSource2DV6.metallib' "${BUILD_SCRIPT}"
grep -Fq 'GoldenEyeSource2DV6.metallib' "${VERIFY_SCRIPT}"

if rg -n -q 'GoldenEyeTitle\.metal|GoldenEyeStageBackground\.metal' "${BUILD_SCRIPT}"; then
    echo "procedural shader path remains in source-faithful build" >&2
    exit 1
fi

bash -n "${BUILD_SCRIPT}" "${VERIFY_SCRIPT}"
swift build --configuration debug

echo "Source product 3D+2D single-pass integration and Release resource policy: PASS"
