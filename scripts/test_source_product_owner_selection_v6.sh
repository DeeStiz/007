#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
MAIN="${ROOT}/native/host/main.swift"
OWNER="${ROOT}/native/host/native_title_owner.swift"
PRODUCT="${ROOT}/native/host/goldeneye_source_product_renderer_v6.swift"
PROTOCOL="${ROOT}/native/host/goldeneye_source_frontend_presentation_v6.swift"

grep -Fq 'GoldenEyeSourceProductRendererV6' "${MAIN}"
grep -Fq 'GoldenEyeSourceSceneV6' "${MAIN}"
grep -Fq 'GOLDENEYE_NATIVE_SOURCE_FRONTEND_ROOT' "${MAIN}"
grep -Fq 'GoldenEyeSourceFrontendMatrixProviderV6' "${MAIN}"
grep -Fq 'frameResourceProvider: matrixProvider' "${MAIN}"
grep -Fq 'UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_RAREWARE): "rarewarelogo"' "${PRODUCT}"
grep -Fq 'UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RAREWARELOGO): "rarewarelogo"' "${PRODUCT}"
grep -Fq 'modelName == "rarewarelogo"' "${PRODUCT}"
grep -Fq 'Self.modelForScreen[request.screen] == modelName' "${PRODUCT}"
grep -Fq 'wantsDiagnosticTitle' "${MAIN}"
grep -Fq 'GoldenEyeTitlePipeline' "${MAIN}"
grep -Fq 'GOLDENEYE_DIAGNOSTIC_TITLE_FLOW' "${MAIN}"

# Release source frames must use the throwing copied-frame seam.  The owner
# may not silently submit a synthesized legacy snapshot or ignore a typed
# matrix/resource failure.
grep -Fq 'try sourceRenderer.submit(sourceFrontendFrame: frame)' "${OWNER}"
grep -Fq 'GoldenEyeSourceFrontendOwnerError.rendererDoesNotAcceptSourceFrames' "${OWNER}"
grep -Fq 'serviceSourceInitializationEvents' "${OWNER}"
grep -Fq 'sourceModelHandshake.takeForAuthority' "${OWNER}"
grep -Fq 'takeModelExecutionResult' "${OWNER}"
if rg -n -q 'sourcePresentation|titleSnapshot\(from: presentation' "${OWNER}"; then
    echo 'source owner still submits a legacy snapshot after a source frame' >&2
    exit 1
fi
grep -Fq 'func submit(sourceFrontendFrame: GoldenEyeSourceFrontendFrameV6) throws' "${PROTOCOL}"
grep -Fq 'frameResourceProvider != nil' "${PRODUCT}"
grep -Fq 'GoldenEyeSourceProductRendererV6Error.missingFrameResources' "${PRODUCT}"
grep -Fq 'GoldenEyeSourceSceneTextureBindingAdapterV6' "${PRODUCT}"
grep -Fq 'GoldenEyeCastSourceSceneFrameRendererV6' "${PRODUCT}"
grep -Fq 'submit(castSceneRequest' "${PRODUCT}"
grep -Fq 'serviceSourceCast' "${OWNER}"
grep -Fq 'textureBindingAdapter: textureBindingAdapter' "${PRODUCT}"
grep -Fq 'V7 gameplay-camera route did not submit a scoped frame' "${OWNER}"
grep -Fq 'if gameplayCameraSubmissionEnabled {' "${OWNER}"
grep -Fq 'if !gameplayCameraSubmissionEnabled, let environmentPacket' "${OWNER}"

SWIFTC=$(xcrun --sdk macosx --find swiftc)
SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
"${SWIFTC}" -frontend -parse -sdk "${SDKROOT}" \
    "${MAIN}" "${OWNER}" "${PROTOCOL}" "${PRODUCT}"

echo 'source product owner Release selection/fail-closed guard: PASS'
