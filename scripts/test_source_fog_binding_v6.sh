#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="${ROOT}/build/native/source-fog-binding-v6"
MODULE_CACHE_DIR="${BUILD_DIR}/module-cache"
mkdir -p "${BUILD_DIR}" "${MODULE_CACHE_DIR}"

# The lowerer smoke is compiled three ways by the focused stage-fog script;
# keep that strict/ASan/UBSan evidence coupled to this exact shader binding
# gate so a successful metallib compile cannot hide a stale CPU contract.
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" \
    bash "${ROOT}/scripts/test_stage_fog_lowering_v6.sh"

METAL=$(xcrun --sdk macosx --find metal)
METALLIB=$(dirname -- "${METAL}")/metallib
"${METAL}" -mmacosx-version-min=27.0 \
    -fmodules-cache-path="${MODULE_CACHE_DIR}" \
    -c "${ROOT}/native/shaders/GoldenEyeSourceSceneV6.metal" \
    -o "${BUILD_DIR}/GoldenEyeSourceSceneV6.air"
"${METALLIB}" "${BUILD_DIR}/GoldenEyeSourceSceneV6.air" \
    -o "${BUILD_DIR}/GoldenEyeSourceSceneV6.metallib"
test -s "${BUILD_DIR}/GoldenEyeSourceSceneV6.metallib"

# These checks are deliberately source-contract checks, not a substitute for
# a GPU capture.  They ensure the exact signed fm/fo payload, clip-Z/clip-W
# lane, and fail-closed mode are present in the compiled source path.
grep -Fq 'uint4 fogInfo' "${ROOT}/native/shaders/GoldenEyeSourceSceneV6.metal"
grep -Fq 'float fogCoordinate [[center_no_perspective]]' \
    "${ROOT}/native/shaders/GoldenEyeSourceSceneV6.metal"
grep -Fq 'as_type<int>(fogInfo.y)' "${ROOT}/native/shaders/GoldenEyeSourceSceneV6.metal"
grep -Fq 'as_type<int>(fogInfo.z)' "${ROOT}/native/shaders/GoldenEyeSourceSceneV6.metal"
grep -Fq 'output.fogCoordinate = sourceVertex.texcoord.w' \
    "${ROOT}/native/shaders/GoldenEyeSourceSceneV6.metal"
grep -Fq 'fogCoordinateQ16.map(Self.q16) ?? 1' \
    "${ROOT}/native/host/goldeneye_source_scene_snapshot_v6.swift"
grep -Fq 'MemoryLayout<GPUUniforms>.stride == 480' \
    "${ROOT}/native/host/metal_source_scene_renderer_v6.swift"
grep -Fq 'MemoryLayout<GoldenEyeSourceSceneGPUVertexV6>.stride == 64' \
    "${ROOT}/native/host/metal_source_scene_renderer_v6.swift"
grep -Fq 'missingFogCoordinate' \
    "${ROOT}/native/host/metal_source_scene_renderer_v6.swift"

echo 'Source fog binding V6 strict/ASan/UBSan and Metal shader-contract validation: PASS'
