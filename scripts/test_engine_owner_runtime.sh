#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="${PROJECT_ROOT}/build/native/owner-runtime"
mkdir -p "${BUILD_DIR}"

SWIFTC=$(xcrun --sdk macosx --find swiftc)
SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
"${SWIFTC}" \
    -target arm64-apple-macosx27.0 \
    -sdk "${SDKROOT}" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_timeline_v6.swift" \
    "${PROJECT_ROOT}/native/host/display_link_runtime.swift" \
    "${PROJECT_ROOT}/native/host/engine_owner.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_engine_owner_smoke.swift" \
    -o "${BUILD_DIR}/goldeneye_engine_owner_smoke"

"${BUILD_DIR}/goldeneye_engine_owner_smoke"

rg -q 'clock_gettime_nsec_np\(CLOCK_MONOTONIC_RAW\)' \
    "${PROJECT_ROOT}/native/host/engine_owner.swift"
rg -q 'maxCatchUpTicks: 4' "${PROJECT_ROOT}/native/host/engine_owner.swift"
rg -q 'maxDebtTicks: 240' "${PROJECT_ROOT}/native/host/engine_owner.swift"
rg -q 'resetMeasurementTelemetry' "${PROJECT_ROOT}/native/host/engine_owner.swift"
rg -q 'resetMeasurementEpoch' "${PROJECT_ROOT}/native/host/engine_owner.swift"
rg -q 'measurementEpochGeneration' "${PROJECT_ROOT}/native/host/engine_owner.swift"
if rg -n 'nextDrawable' "${PROJECT_ROOT}/native/host/display_link_runtime.swift"; then
    echo "display-link runtime must consume the callback-supplied drawable" >&2
    exit 1
fi
rg -q 'Native title product requires supplied-drawable renderer ownership' \
    "${PROJECT_ROOT}/native/host/native_title_owner.swift"
rg -q 'presentationPath=.*suppliedDrawable' \
    "${PROJECT_ROOT}/native/host/native_title_owner.swift"
rg -q 'layer\.maximumDrawableCount = 2' \
    "${PROJECT_ROOT}/native/host/display_link_runtime.swift"
rg -q 'layer\.displaySyncEnabled = true' \
    "${PROJECT_ROOT}/native/host/display_link_runtime.swift"
rg -q 'CAFrameRateRange\(minimum: 60, maximum: 120, preferred: 120\)' \
    "${PROJECT_ROOT}/native/host/display_link_runtime.swift"
rg -q 'let drawable = update\.drawable' \
    "${PROJECT_ROOT}/native/host/display_link_runtime.swift"
rg -q 'applyPendingCommands\(afterPresent: true\)' \
    "${PROJECT_ROOT}/native/host/display_link_runtime.swift"
rg -q 'timing\.callbackSequence <= 2' \
    "${PROJECT_ROOT}/native/host/display_link_runtime.swift"
rg -q 'resetMeasurementTelemetry' \
    "${PROJECT_ROOT}/native/host/display_link_runtime.swift"
rg -q 'measurementEpochGeneration' \
    "${PROJECT_ROOT}/native/host/display_link_runtime.swift"
rg -q 'GOLDENEYE_CADENCE_FRAME_RATE_MINIMUM' \
    "${PROJECT_ROOT}/native/host/display_link_runtime.swift"
rg -q 'frameRateRangeOverrideVersion' \
    "${PROJECT_ROOT}/native/host/display_link_runtime.swift"
rg -q 'state\.queue\.waitForDrawable\(drawable\)' \
    "${PROJECT_ROOT}/native/host/metal_source_scene_renderer_v6.swift"
rg -q 'state\.queue\.signalDrawable\(drawable\)' \
    "${PROJECT_ROOT}/native/host/metal_source_scene_renderer_v6.swift"
rg -q 'drawable\.present\(\)' \
    "${PROJECT_ROOT}/native/host/metal_source_scene_renderer_v6.swift"
rg -q 'transitionScreenEvent' \
    "${PROJECT_ROOT}/native/host/goldeneye_source_product_renderer_v6.swift"
if rg -n '\\.nextDrawable' \
    "${PROJECT_ROOT}/native/host/goldeneye_source_product_renderer_v6.swift" \
    "${PROJECT_ROOT}/native/host/metal_source_scene_renderer_v6.swift" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_2d_renderer_v6.swift" \
    "${PROJECT_ROOT}/native/host/native_title_owner.swift"; then
    echo "source-faithful product path must not acquire a drawable" >&2
    exit 1
fi
rg -q 'for index in 0..<2' \
    "${PROJECT_ROOT}/native/host/metal_device_state.swift"
rg -q 'BUILD_DIR}/source-faithful/GoldenEyeHost.app' \
    "${PROJECT_ROOT}/scripts/measure_native_runtime.sh"
rg -q 'GOLDENEYE_NATIVE_SOURCE_FRONTEND_ROOT=' \
    "${PROJECT_ROOT}/scripts/measure_native_runtime.sh"
rg -q 'audioService\?\.setPaused\(paused\)' \
    "${PROJECT_ROOT}/native/host/native_title_owner.swift"
rg -q 'event=focusLost reset=1 paused=0' \
    "${PROJECT_ROOT}/native/host/main.swift"
if sed -n '/private func setFocusState/,/^    }/p' \
    "${PROJECT_ROOT}/native/host/main.swift" | rg -n 'setPaused|requestPaused'; then
    echo "focus transitions must reset input without pausing the owner/audio" >&2
    exit 1
fi
rg -q 'func setPaused\(_ paused: Bool\)' \
    "${PROJECT_ROOT}/native/host/native_audio_service.swift"
rg -q 'engine\.pause\(\)' \
    "${PROJECT_ROOT}/native/host/native_audio_service.swift"
rg -q 'audioPauseCount=' \
    "${PROJECT_ROOT}/native/host/native_title_owner.swift"
rg -q 'authorityStartAudioHash=' \
    "${PROJECT_ROOT}/native/host/native_title_owner.swift"
rg -q 'rendererCallbackP95Ms=' \
    "${PROJECT_ROOT}/native/host/native_title_owner.swift"
rg -q 'frameRateRangeOverrideVersion=' \
    "${PROJECT_ROOT}/native/host/native_title_owner.swift"
rg -q 'GOLDENEYE_CADENCE_WARMUP' \
    "${PROJECT_ROOT}/scripts/measure_native_runtime.sh"
rg -q 'event=measurementEpochReset=1' \
    "${PROJECT_ROOT}/native/host/main.swift"
rg -q 'windowDidEnterFullScreen' "${PROJECT_ROOT}/native/host/main.swift"
rg -Fq 'presentationMode=\(mode)' "${PROJECT_ROOT}/native/host/main.swift"
rg -q 'measurementEpochReset=1' \
    "${PROJECT_ROOT}/scripts/measure_native_runtime.sh"
echo "goldeneye_engine_owner_route_guard: PASS supplied-drawable contract"
