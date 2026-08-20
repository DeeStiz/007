#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ROM_PATH="${1:-${GOLDENEYE_ROM_PATH:-}}"
BUILD_DIR="${PROJECT_ROOT}/build/native/boot-runtime"
# The source-faithful Release bundle is intentionally kept separate from the
# preserved diagnostic app and its historical captures.
APP_DIR="${GOLDENEYE_CADENCE_APP_DIR:-${BUILD_DIR}/source-faithful/GoldenEyeHost.app}"
APP_EXECUTABLE="${APP_DIR}/Contents/MacOS/GoldenEyeHost"
CAST_ASSET_ROOT="${GOLDENEYE_NATIVE_CAST_ASSET_ROOT:-${PROJECT_ROOT}/build/native/cast-frontend-v6-image-decoder-v6-fullweapons}"
GUNBARREL_SIDECAR="${GOLDENEYE_NATIVE_GUNBARREL_SIDECAR:-${PROJECT_ROOT}/build/native/gunbarrel-v6-prepared/gunbarrel.gbar}"
CADENCE_RUN_ID="${GOLDENEYE_CADENCE_RUN_ID:-}"
if [[ -n "${CADENCE_RUN_ID}" ]]; then
    if [[ ! "${CADENCE_RUN_ID}" =~ ^[A-Za-z0-9._-]+$ ]]; then
        echo "native cadence measurement: cadence run ID contains unsafe characters: ${CADENCE_RUN_ID}" >&2
        exit 1
    fi
    MEASURE_ROOT="${BUILD_DIR}/cadence/runs/${CADENCE_RUN_ID}"
else
    MEASURE_ROOT="${BUILD_DIR}/cadence"
fi
DURATION="${GOLDENEYE_CADENCE_DURATION:-6}"
WARMUP="${GOLDENEYE_CADENCE_WARMUP:-30}"
TRANSITION_GRACE="${GOLDENEYE_CADENCE_TRANSITION_GRACE:-20}"
REQUIRE_LONG="${GOLDENEYE_CADENCE_REQUIRE_LONG:-0}"
HUD_STATE="${GOLDENEYE_CADENCE_HUD_STATE:-unobserved}"
FRAME_RATE_MINIMUM="${GOLDENEYE_CADENCE_FRAME_RATE_MINIMUM:-60}"
FRAME_RATE_MAXIMUM="${GOLDENEYE_CADENCE_FRAME_RATE_MAXIMUM:-120}"
FRAME_RATE_PREFERRED="${GOLDENEYE_CADENCE_FRAME_RATE_PREFERRED:-120}"
FRAME_RATE_OVERRIDE_VERSION="${GOLDENEYE_CADENCE_FRAME_RATE_OVERRIDE_VERSION:-v1}"
DISPLAY_120="${GOLDENEYE_CADENCE_DISPLAY_120:-Color LCD}"
DISPLAY_60="${GOLDENEYE_CADENCE_DISPLAY_60:-DELL S3220DGF}"
NATIVE_DISPLAY_120="${GOLDENEYE_CADENCE_NATIVE_DISPLAY_120:-Built-in Retina Display}"
NATIVE_DISPLAY_60="${GOLDENEYE_CADENCE_NATIVE_DISPLAY_60:-${DISPLAY_60}}"
CADENCE_STRESS="${GOLDENEYE_CADENCE_STRESS:-1}"
CADENCE_WAKE_DISPLAY="${GOLDENEYE_CADENCE_WAKE_DISPLAY:-1}"
CADENCE_FULLSCREEN="${GOLDENEYE_CADENCE_FULLSCREEN:-1}"
CADENCE_ONLY_MODE="${GOLDENEYE_CADENCE_ONLY_MODE:-both}"
DISPLAY_STATE_PROBE="${GOLDENEYE_CADENCE_DISPLAY_STATE_PROBE:-${PROJECT_ROOT}/build/native/display-state-probe}"
FRONTMOST_PROBE="${GOLDENEYE_CADENCE_FRONTMOST_PROBE:-${PROJECT_ROOT}/build/native/frontmost-probe}"
WINDOW_PROBE="${GOLDENEYE_CADENCE_WINDOW_PROBE:-${PROJECT_ROOT}/build/native/window-visibility-probe}"

fail() {
    echo "native cadence measurement: $*" >&2
    exit 1
}

is_nonnegative_seconds() {
    awk -v value="$1" 'BEGIN { exit !(value ~ /^[0-9]+([.][0-9]+)?$/ && value >= 0) }'
}

is_positive_seconds() {
    awk -v value="$1" 'BEGIN { exit !(value ~ /^[0-9]+([.][0-9]+)?$/ && value > 0) }'
}

is_nonnegative_seconds "${WARMUP}" || fail "GOLDENEYE_CADENCE_WARMUP must be a non-negative number of seconds"
is_nonnegative_seconds "${TRANSITION_GRACE}" || fail "GOLDENEYE_CADENCE_TRANSITION_GRACE must be a non-negative number of seconds"
is_positive_seconds "${DURATION}" || fail "GOLDENEYE_CADENCE_DURATION must be a positive number of seconds"
is_positive_seconds "${FRAME_RATE_MINIMUM}" || fail "GOLDENEYE_CADENCE_FRAME_RATE_MINIMUM must be positive"
is_positive_seconds "${FRAME_RATE_MAXIMUM}" || fail "GOLDENEYE_CADENCE_FRAME_RATE_MAXIMUM must be positive"
is_positive_seconds "${FRAME_RATE_PREFERRED}" || fail "GOLDENEYE_CADENCE_FRAME_RATE_PREFERRED must be positive"
awk -v minimum="${FRAME_RATE_MINIMUM}" -v maximum="${FRAME_RATE_MAXIMUM}" -v preferred="${FRAME_RATE_PREFERRED}" \
    'BEGIN { exit !(maximum >= minimum && preferred >= minimum && preferred <= maximum) }' \
    || fail "cadence frame-rate range must satisfy minimum <= preferred <= maximum"
if [[ "${REQUIRE_LONG}" == "1" ]]; then
    awk -v duration="${DURATION}" 'BEGIN { exit !(duration >= 600) }' \
        || fail "long cadence evidence requires GOLDENEYE_CADENCE_DURATION >= 600 seconds"
fi
case "${HUD_STATE}" in
    unobserved|direct|composited) ;;
    *) fail "GOLDENEYE_CADENCE_HUD_STATE must be unobserved, direct, or composited" ;;
esac

if [[ "${GOLDENEYE_CADENCE_SKIP_BUILD:-0}" != "1" ]]; then
    [[ -n "${ROM_PATH}" ]] || fail "a ROM path is required for the preparation/build step"
    "${SCRIPT_DIR}/build_native_boot.sh" "${ROM_PATH}"
fi

[[ -x "${APP_EXECUTABLE}" ]] || fail "missing Release app: ${APP_EXECUTABLE}"
codesign --verify --deep --strict "${APP_DIR}" >/dev/null || fail "Release app signature verification failed"
if find "${APP_DIR}" -type f \( -name '*.z64' -o -name '*.n64' -o -name '*.bin' -o -name '*.rz' \) -print -quit | grep -q .; then
    fail "private ROM/payload file found in the application bundle"
fi

mkdir -p "${MEASURE_ROOT}"
system_profiler SPDisplaysDataType > "${MEASURE_ROOT}/display-profile.txt"
if [[ -x "${DISPLAY_STATE_PROBE}" ]]; then
    "${DISPLAY_STATE_PROBE}" > "${MEASURE_ROOT}/display-state-preflight.txt" || true
fi
if [[ -x "${FRONTMOST_PROBE}" ]]; then
    "${FRONTMOST_PROBE}" > "${MEASURE_ROOT}/frontmost-preflight.txt" || true
fi
rg -Fq "${DISPLAY_120}" "${MEASURE_ROOT}/display-profile.txt" || fail "120 Hz display '${DISPLAY_120}' was not found; set GOLDENEYE_CADENCE_DISPLAY_120"
rg -Fq "${DISPLAY_60}" "${MEASURE_ROOT}/display-profile.txt" || fail "fixed-60 display '${DISPLAY_60}' was not found; set GOLDENEYE_CADENCE_DISPLAY_60"

field() {
    local key="$1"
    local path="$2"
    tr ' ' '\n' < "${path}" | sed -n "s/^${key}=//p" | tail -n 1
}

display_sleep_state() {
    local display="$1"
    local profile="$2"
    awk -v target="${display}" '
        index($0, target ":") > 0 { inDisplay = 1; next }
        inDisplay && /Display Asleep:/ { print $NF; exit }
        inDisplay && /Online: Yes/ { print "No"; exit }
        inDisplay && /Online: No/ { print "Yes"; exit }
        inDisplay && /^[^[:space:]]/ { exit }
    ' "${profile}"
}

number_or_zero() {
    local value="${1:-}"
    [[ -n "${value}" ]] && printf '%s\n' "${value}" || printf '0\n'
}

in_range() {
    local value="$1"
    local low="$2"
    local high="$3"
    awk -v value="${value}" -v low="${low}" -v high="${high}" 'BEGIN { exit !(value >= low && value <= high) }'
}

at_least() {
    local value="$1"
    local low="$2"
    awk -v value="${value}" -v low="${low}" 'BEGIN { exit !(value >= low) }'
}

run_case() {
    local mode="$1"
    local display="$2"
    local expected_fps="$3"
    local native_display="${NATIVE_DISPLAY_60}"
    if [[ "${mode}" == "120" ]]; then
        native_display="${NATIVE_DISPLAY_120}"
    fi
    local case_root="${MEASURE_ROOT}/${mode}"
    local owner_log="${case_root}/owner.log"
    local app_log="${case_root}/app.log"
    local events_log="${case_root}/events.log"
    local resize_log="${case_root}/resize.log"
    local native_120_log="${case_root}/native-120.log"
    local source_owner_log="${case_root}/source-frontend-owner.log"
    local renderer_failure_log="${case_root}/source-product-renderer-failures.log"
    local renderer_log="${case_root}/source-product-renderer.log"
    local audio_pause_log="${case_root}/audio-pause.log"
    local wake_pid=""
    mkdir -p "${case_root}"
    : > /tmp/goldeneye-native-title-owner.log
    : > /tmp/goldeneye-native-120.log
    : > /tmp/goldeneye-cadence-events.log
    : > /tmp/goldeneye-m9-resize.log
    : > /tmp/goldeneye-m5-pause.log
    : > /tmp/goldeneye-source-frontend-owner.log
    : > /tmp/goldeneye-source-product-renderer-v6-failures.log
    : > /tmp/goldeneye-source-product-renderer-v6.log
    : > /tmp/goldeneye-native-audio-pause.log

    echo "Running ${mode}: display=${display} warmup=${WARMUP}s duration=${DURATION}s"
    local total_keep_awake_seconds
    total_keep_awake_seconds=$(awk -v warmup="${WARMUP}" -v grace="${TRANSITION_GRACE}" -v duration="${DURATION}" \
        'BEGIN { value = warmup + grace + duration + 25; printf "%d", value + 0.999 }')
    if [[ "${CADENCE_WAKE_DISPLAY}" == "1" ]] && command -v caffeinate >/dev/null 2>&1; then
        # A remote/locked session can leave an otherwise online display asleep;
        # keep the measurement surface awake without changing product code.
        # Prevent display/system idle sleep for the bounded evidence window;
        # -u alone only sends a transient user-activity pulse and does not
        # keep a named display awake long enough for presented-time samples.
        caffeinate -dimsu -t "${total_keep_awake_seconds}" >/dev/null 2>&1 &
        wake_pid=$!
    fi
    # Snapshot the display's awake/online state after the bounded wake request,
    # not only at script start. Keep both the global hardware profile and this
    # per-case state for the evidence handoff.
    system_profiler SPDisplaysDataType > "${case_root}/display-profile.txt"

    env \
        GOLDENEYE_NATIVE_TITLE=1 \
        GOLDENEYE_NATIVE_ASSET_ROOT="${PROJECT_ROOT}/build/native/boot-assets" \
        GOLDENEYE_NATIVE_STAGE_ASSET_ROOT="${PROJECT_ROOT}/build/native/stage-assets" \
        GOLDENEYE_NATIVE_SOURCE_FRONTEND_ROOT="${PROJECT_ROOT}/build/native/source-frontend-v6-image-decoder-v6" \
        GOLDENEYE_NATIVE_CAST_ASSET_ROOT="${CAST_ASSET_ROOT}" \
        GOLDENEYE_NATIVE_GUNBARREL_SIDECAR="${GUNBARREL_SIDECAR}" \
        GOLDENEYE_NATIVE_FULLSCREEN="${CADENCE_FULLSCREEN}" \
        GOLDENEYE_CADENCE_RENDERER="${GOLDENEYE_CADENCE_RENDERER:-}" \
        GOLDENEYE_NATIVE_DISPLAY="${native_display}" \
        GOLDENEYE_CADENCE_PROBE=1 \
        GOLDENEYE_CADENCE_STRESS="${CADENCE_STRESS}" \
        GOLDENEYE_CADENCE_DURATION="${DURATION}" \
        GOLDENEYE_CADENCE_WARMUP="${WARMUP}" \
        GOLDENEYE_CADENCE_TRANSITION_GRACE="${TRANSITION_GRACE}" \
        GOLDENEYE_CADENCE_HUD_STATE="${HUD_STATE}" \
        GOLDENEYE_CADENCE_FRAME_RATE_MINIMUM="${FRAME_RATE_MINIMUM}" \
        GOLDENEYE_CADENCE_FRAME_RATE_MAXIMUM="${FRAME_RATE_MAXIMUM}" \
        GOLDENEYE_CADENCE_FRAME_RATE_PREFERRED="${FRAME_RATE_PREFERRED}" \
        GOLDENEYE_CADENCE_FRAME_RATE_OVERRIDE_VERSION="${FRAME_RATE_OVERRIDE_VERSION}" \
        GOLDENEYE_M9_RESIZE=1 \
        GOLDENEYE_TITLE_SMOKE_INPUT=0 \
        "${APP_EXECUTABLE}" > "${app_log}" 2>&1 &
    local app_pid=$!

    local timeout_seconds
    timeout_seconds=$(awk -v warmup="${WARMUP}" -v grace="${TRANSITION_GRACE}" -v duration="${DURATION}" \
        'BEGIN { value = warmup + grace + duration + 30; printf "%d", value + 0.999 }')
    local deadline
    deadline=$(($(date +%s) + ${timeout_seconds%.*}))
    while [[ ! -s /tmp/goldeneye-native-title-owner.log ]] && kill -0 "${app_pid}" 2>/dev/null; do
        if (( $(date +%s) >= deadline )); then break; fi
        sleep 0.05
    done
    # The owner log is written at shutdown. Wait independently for the
    # AppKit lifecycle to publish a successful post-warmup epoch reset so a
    # short/early exit cannot be mistaken for measured steady state.
    while kill -0 "${app_pid}" 2>/dev/null \
          && ! rg -q 'event=measurementEpochReset=1' /tmp/goldeneye-cadence-events.log 2>/dev/null; do
        if (( $(date +%s) >= deadline )); then break; fi
        sleep 0.10
    done
    if [[ -x "${FRONTMOST_PROBE}" ]]; then
        "${FRONTMOST_PROBE}" > "${case_root}/frontmost-startup.txt" || true
    fi
    if [[ -x "${WINDOW_PROBE}" ]]; then
        "${WINDOW_PROBE}" > "${case_root}/window-visibility-startup.txt" || true
    fi
    while kill -0 "${app_pid}" 2>/dev/null; do
        if (( $(date +%s) >= deadline )); then break; fi
        sleep 0.10
    done
    if kill -0 "${app_pid}" 2>/dev/null; then
        /usr/bin/osascript -e 'tell application id "com.goldeneye.swift.host" to quit' >/dev/null 2>&1 || true
        sleep 2
    fi
    if kill -0 "${app_pid}" 2>/dev/null; then
        kill -TERM "${app_pid}" 2>/dev/null || true
    fi
    wait "${app_pid}" 2>/dev/null || true
    if [[ -n "${wake_pid}" ]]; then
        kill "${wake_pid}" 2>/dev/null || true
        wait "${wake_pid}" 2>/dev/null || true
    fi

    if [[ ! -s /tmp/goldeneye-native-title-owner.log ]]; then
        echo "native cadence measurement: ${mode} run produced no owner telemetry; app log follows:" >&2
        tail -40 "${app_log}" >&2 || true
        fail "${mode} run did not reach the owner epoch (see ${app_log})"
    fi
    cp -f /tmp/goldeneye-native-title-owner.log "${owner_log}"
    [[ -f /tmp/goldeneye-native-120.log ]] && cp -f /tmp/goldeneye-native-120.log "${native_120_log}"
    [[ -f /tmp/goldeneye-cadence-events.log ]] && cp -f /tmp/goldeneye-cadence-events.log "${events_log}"
    [[ -f /tmp/goldeneye-m9-resize.log ]] && cp -f /tmp/goldeneye-m9-resize.log "${resize_log}"
    [[ -f /tmp/goldeneye-source-frontend-owner.log ]] && cp -f /tmp/goldeneye-source-frontend-owner.log "${source_owner_log}"
    [[ -f /tmp/goldeneye-source-product-renderer-v6-failures.log ]] && cp -f /tmp/goldeneye-source-product-renderer-v6-failures.log "${renderer_failure_log}"
    [[ -f /tmp/goldeneye-source-product-renderer-v6.log ]] && cp -f /tmp/goldeneye-source-product-renderer-v6.log "${renderer_log}"
    [[ -f /tmp/goldeneye-native-audio-pause.log ]] && cp -f /tmp/goldeneye-native-audio-pause.log "${audio_pause_log}"

    local ticks callbacks logic_rate presented_samples presented_fps
    local target_median target_p95 presented_median presented_p95 presented_min presented_windows
    local dropped late catchup debt fatal resize pause resume rebase unexpected marshaled timeouts
    local marshal_drops stale_drops unhandled deferred_initial render_failures rejected_presented
    local audio_pause_count audio_resume_count audio_paused
    local scheduler_clock native_rate reference_rate catchup_limit debt_limit
    local presentation_path supplied_drawable compatibility_drawable layer_drawables layer_sync layer_framebuffer
    local display_sleep measurement_epoch_generation measurement_epoch_raw_ns
    local renderer_callback_count renderer_callback_median renderer_callback_p95 renderer_gpu_timing renderer_gpu_p95
    local measurement_reset_events active_gate_events fullscreen_ready_events
    local frame_rate_minimum frame_rate_maximum frame_rate_preferred frame_rate_override_version
    ticks=$(number_or_zero "$(field ticks "${owner_log}")")
    callbacks=$(number_or_zero "$(field callbacks "${owner_log}")")
    logic_rate=$(number_or_zero "$(field logicTickRateHz "${owner_log}")")
    presented_samples=$(number_or_zero "$(field presentedTimeSamples "${owner_log}")")
    presented_fps=$(number_or_zero "$(field presentedFPS "${owner_log}")")
    target_median=$(number_or_zero "$(field targetDeltaMedianMs "${owner_log}")")
    target_p95=$(number_or_zero "$(field targetDeltaP95Ms "${owner_log}")")
    presented_median=$(number_or_zero "$(field presentedDeltaMedianMs "${owner_log}")")
    presented_p95=$(number_or_zero "$(field presentedDeltaP95Ms "${owner_log}")")
    presented_min=$(number_or_zero "$(field presentedOneSecondMinFrames "${owner_log}")")
    presented_windows=$(number_or_zero "$(field presentedOneSecondWindows "${owner_log}")")
    dropped=$(number_or_zero "$(field droppedTicks "${owner_log}")")
    late=$(number_or_zero "$(field lateWakes "${owner_log}")")
    catchup=$(number_or_zero "$(field catchUpTicks "${owner_log}")")
    debt=$(number_or_zero "$(field maximumDebtTicks "${owner_log}")")
    fatal=$(number_or_zero "$(field fatalDebtTicks "${owner_log}")")
    resize=$(number_or_zero "$(field resizeApplies "${owner_log}")")
    pause=$(number_or_zero "$(field pauseCount "${owner_log}")")
    resume=$(number_or_zero "$(field resumeCount "${owner_log}")")
    rebase=$(number_or_zero "$(field rebaseCount "${owner_log}")")
    unexpected=$(number_or_zero "$(field unexpectedCallbacks "${owner_log}")")
    marshaled=$(number_or_zero "$(field marshaledCallbacks "${owner_log}")")
    timeouts=$(number_or_zero "$(field migrationMarshalTimeouts "${owner_log}")")
    marshal_drops=$(number_or_zero "$(field marshaledCallbackDrops "${owner_log}")")
    stale_drops=$(number_or_zero "$(field staleCallbackDrops "${owner_log}")")
    unhandled=$(number_or_zero "$(field unhandledUnexpectedCallbacks "${owner_log}")")
    deferred_initial=$(number_or_zero "$(field deferredInitialFrames "${owner_log}")")
    render_failures=$(number_or_zero "$(field renderFailures "${owner_log}")")
    rejected_presented=$(number_or_zero "$(field rejectedPresentedTimeSamples "${owner_log}")")
    audio_pause_count=$(number_or_zero "$(field audioPauseCount "${owner_log}")")
    audio_resume_count=$(number_or_zero "$(field audioResumeCount "${owner_log}")")
    audio_paused=$(number_or_zero "$(field audioPaused "${owner_log}")")
    scheduler_clock=$(field schedulerClock "${owner_log}")
    native_rate=$(field nativeRate "${owner_log}")
    reference_rate=$(field referenceRate "${owner_log}")
    catchup_limit=$(number_or_zero "$(field maxCatchUpTicks "${owner_log}")")
    debt_limit=$(number_or_zero "$(field maxDebtTicks "${owner_log}")")
    presentation_path=$(field presentationPath "${owner_log}")
    supplied_drawable=$(number_or_zero "$(field suppliedDrawable "${owner_log}")")
    compatibility_drawable=$(number_or_zero "$(field compatibilityDrawable "${owner_log}")")
    layer_drawables=$(number_or_zero "$(field layerMaximumDrawableCount "${owner_log}")")
    layer_sync=$(number_or_zero "$(field layerDisplaySync "${owner_log}")")
    layer_framebuffer=$(number_or_zero "$(field layerFramebufferOnly "${owner_log}")")
    measurement_epoch_generation=$(number_or_zero "$(field measurementEpochGeneration "${owner_log}")")
    measurement_epoch_raw_ns=$(number_or_zero "$(field measurementEpochRawNs "${owner_log}")")
    renderer_callback_count=$(number_or_zero "$(field rendererCallbackCount "${owner_log}")")
    renderer_callback_median=$(number_or_zero "$(field rendererCallbackMedianMs "${owner_log}")")
    renderer_callback_p95=$(number_or_zero "$(field rendererCallbackP95Ms "${owner_log}")")
    renderer_gpu_timing=$(field rendererGPUTiming "${owner_log}")
    renderer_gpu_p95=$(number_or_zero "$(field rendererGPUP95Ms "${owner_log}")")
    frame_rate_override_version=$(field frameRateRangeOverrideVersion "${owner_log}")
    local preferred_frame_rate_range
    preferred_frame_rate_range=$(field preferredFrameRateRange "${owner_log}")
    frame_rate_minimum=$(number_or_zero "$(printf '%s' "${preferred_frame_rate_range}" | sed -E 's/^([0-9.]+)-([0-9.]+)\/([0-9.]+)$/\1/')")
    frame_rate_maximum=$(number_or_zero "$(printf '%s' "${preferred_frame_rate_range}" | sed -E 's/^([0-9.]+)-([0-9.]+)\/([0-9.]+)$/\2/')")
    frame_rate_preferred=$(number_or_zero "$(printf '%s' "${preferred_frame_rate_range}" | sed -E 's/^([0-9.]+)-([0-9.]+)\/([0-9.]+)$/\3/')")
    measurement_reset_events=$(rg -c 'event=measurementEpochReset=1' "${events_log}" 2>/dev/null || true)
    active_gate_events=$(rg -c 'event=activeGateReady=1' "${events_log}" 2>/dev/null || true)
    fullscreen_ready_events=$(rg -c 'event=fullscreenEntryReady=1' "${events_log}" 2>/dev/null || true)
    display_sleep=$(display_sleep_state "${display}" "${case_root}/display-profile.txt")

    local pass=1
    at_least "${ticks}" 120 || pass=0
    at_least "${resize}" 1 || pass=0
    [[ "${dropped}" == "0" && "${fatal}" == "0" && "${timeouts}" == "0" && "${unhandled}" == "0" && "${render_failures}" == "0" ]] || pass=0
    [[ "${scheduler_clock}" == "CLOCK_MONOTONIC_RAW" && "${native_rate}" == "120/1" && "${reference_rate}" == "60/1" ]] || pass=0
    [[ "${catchup_limit}" == "4" && "${debt_limit}" == "240" ]] || pass=0
    [[ "${measurement_epoch_generation}" == "1" && "${measurement_epoch_raw_ns}" != "0" ]] || pass=0
    at_least "${measurement_reset_events}" 1 || pass=0
    at_least "${active_gate_events}" 1 || pass=0
    at_least "${renderer_callback_count}" 120 || pass=0
    awk -v callback_p95="${renderer_callback_p95}" 'BEGIN { exit !(callback_p95 > 0 && callback_p95 <= 8.33) }' || pass=0
    [[ "${frame_rate_override_version}" == "${FRAME_RATE_OVERRIDE_VERSION}" ]] || pass=0
    awk -v actual_min="${frame_rate_minimum}" -v actual_max="${frame_rate_maximum}" -v actual_preferred="${frame_rate_preferred}" \
        -v expected_min="${FRAME_RATE_MINIMUM}" -v expected_max="${FRAME_RATE_MAXIMUM}" -v expected_preferred="${FRAME_RATE_PREFERRED}" \
        'BEGIN { exit !(actual_min == expected_min && actual_max == expected_max && actual_preferred == expected_preferred) }' || pass=0
    if [[ "${CADENCE_FULLSCREEN}" == "1" ]]; then
        at_least "${fullscreen_ready_events}" 1 || pass=0
    fi
    [[ "${presentation_path}" == "suppliedDrawable" && "${supplied_drawable}" == "1" && "${compatibility_drawable}" == "0" ]] || pass=0
    [[ "${layer_drawables}" == "2" && "${layer_sync}" == "1" && "${layer_framebuffer}" == "1" ]] || pass=0
    # A missing state is not proof of an active display. Require an explicit
    # "No" before accepting presented-fps evidence.
    [[ "${display_sleep}" == "No" ]] || pass=0
    if [[ "${CADENCE_STRESS}" == "1" ]]; then
        # Focus/fullscreen/display migration is a lifecycle test. Pause time
        # must not be folded into steady-state rate acceptance.
        at_least "${pause}" 1 || pass=0
        at_least "${resume}" 1 || pass=0
        at_least "${rebase}" 1 || pass=0
        at_least "${audio_pause_count}" 1 || pass=0
        at_least "${audio_resume_count}" 1 || pass=0
        [[ "${audio_paused}" == "0" ]] || pass=0
    else
        in_range "${logic_rate}" 119 121 || pass=0
        [[ "${marshal_drops}" == "0" && "${rejected_presented}" == "0" ]] || pass=0
        if [[ "${mode}" == "120" ]]; then
            in_range "${presented_fps}" 119 121 || pass=0
            at_least "${presented_samples}" 120 || pass=0
            at_least "${presented_windows}" 1 || pass=0
            at_least "${presented_min}" 110 || pass=0
            awk -v median="${presented_median}" 'BEGIN { exit !(median >= 7.916 && median <= 8.750) }' || pass=0
            awk -v p95="${presented_p95}" 'BEGIN { exit !(p95 > 0 && p95 <= 10.0) }' || pass=0
        else
            in_range "${presented_fps}" 59 61 || pass=0
            at_least "${presented_samples}" 60 || pass=0
            at_least "${presented_windows}" 1 || pass=0
            at_least "${presented_min}" 59 || pass=0
        fi
    fi

    {
        printf 'mode=%s display=%s nativeDisplay=%s expectedDisplayHz=%s pass=%s\n' "${mode}" "${display}" "${native_display}" "${expected_fps}" "${pass}"
        printf 'warmupSeconds=%s measurementDurationSeconds=%s transitionGraceSeconds=%s measurementEpochGeneration=%s measurementEpochRawNs=%s measurementResetEvents=%s activeGateEvents=%s fullscreenEntryReadyEvents=%s\n' "${WARMUP}" "${DURATION}" "${TRANSITION_GRACE}" "${measurement_epoch_generation}" "${measurement_epoch_raw_ns}" "${measurement_reset_events}" "${active_gate_events}" "${fullscreen_ready_events}"
        printf 'ticks=%s callbacks=%s logicTickRateHz=%s droppedTicks=%s lateWakes=%s catchUpTicks=%s maximumDebtTicks=%s fatalDebtTicks=%s\n' "${ticks}" "${callbacks}" "${logic_rate}" "${dropped}" "${late}" "${catchup}" "${debt}" "${fatal}"
        printf 'targetDeltaMedianMs=%s targetDeltaP95Ms=%s presentedTimeSamples=%s presentedFPS=%s presentedDeltaMedianMs=%s presentedDeltaP95Ms=%s presentedOneSecondMinFrames=%s presentedOneSecondWindows=%s\n' "${target_median}" "${target_p95}" "${presented_samples}" "${presented_fps}" "${presented_median}" "${presented_p95}" "${presented_min}" "${presented_windows}"
        printf 'focusPause=%s focusResume=%s schedulerRebase=%s audioPauseCount=%s audioResumeCount=%s audioPaused=%s resizeApplies=%s unexpectedCallbacks=%s marshaledCallbacks=%s migrationMarshalTimeouts=%s marshaledCallbackDrops=%s staleCallbackDrops=%s unhandledUnexpectedCallbacks=%s deferredInitialFrames=%s renderFailures=%s rejectedPresentedTimeSamples=%s stress=%s wakeDisplay=%s fullscreen=%s displaySleep=%s\n' "${pause}" "${resume}" "${rebase}" "${audio_pause_count}" "${audio_resume_count}" "${audio_paused}" "${resize}" "${unexpected}" "${marshaled}" "${timeouts}" "${marshal_drops}" "${stale_drops}" "${unhandled}" "${deferred_initial}" "${render_failures}" "${rejected_presented}" "${CADENCE_STRESS}" "${CADENCE_WAKE_DISPLAY}" "${CADENCE_FULLSCREEN}" "${display_sleep:-unknown}"
        printf 'presentationContract=%s suppliedDrawable=%s compatibilityDrawable=%s layerMaximumDrawableCount=%s layerDisplaySync=%s layerFramebufferOnly=%s schedulerClock=%s nativeRate=%s referenceRate=%s maxCatchUpTicks=%s maxDebtTicks=%s preferredFrameRateRange=%s frameRateRangeOverrideVersion=%s\n' "${presentation_path}" "${supplied_drawable}" "${compatibility_drawable}" "${layer_drawables}" "${layer_sync}" "${layer_framebuffer}" "${scheduler_clock}" "${native_rate}" "${reference_rate}" "${catchup_limit}" "${debt_limit}" "${preferred_frame_rate_range}" "${frame_rate_override_version}"
        printf 'rendererCallbackCount=%s rendererCallbackMedianMs=%s rendererCallbackP95Ms=%s rendererGPUTiming=%s rendererGPUP95Ms=%s\n' "${renderer_callback_count}" "${renderer_callback_median}" "${renderer_callback_p95}" "${renderer_gpu_timing:-unavailable}" "${renderer_gpu_p95}"
        printf 'presentationMode=%s metalHUDState=%s directToDisplayEvidence=external-HUD-required\n' \
            "$([[ "${CADENCE_FULLSCREEN}" == "1" ]] && echo direct-eligible-unverified || echo composited-window)" "${HUD_STATE}"
        echo 'cpuP95=rendererCallbackP95Ms gpuP95=unavailable; Instruments/Metal HUD evidence remains required'
    } | tee "${case_root}/report.txt"
    if [[ "${pass}" == "1" ]]; then
        return 0
    fi
    return 1
}

overall=0
case "${CADENCE_ONLY_MODE}" in
    120)
        run_case 120 "${DISPLAY_120}" 120 || overall=1
        ;;
    60)
        run_case 60 "${DISPLAY_60}" 60 || overall=1
        ;;
    both)
        run_case 120 "${DISPLAY_120}" 120 || overall=1
        run_case 60 "${DISPLAY_60}" 60 || overall=1
        ;;
    *)
        fail "GOLDENEYE_CADENCE_ONLY_MODE must be 120, 60, or both"
        ;;
esac

cat > "${MEASURE_ROOT}/README.txt" <<EOF
Native Release cadence measurement
date=$(date -u +%Y-%m-%dT%H:%M:%SZ)
runID=${CADENCE_RUN_ID:-default}
durationSeconds=${DURATION}
warmupSeconds=${WARMUP}
transitionGraceSeconds=${TRANSITION_GRACE}
requireLong=${REQUIRE_LONG}
frameRateRangeOverrideVersion=${FRAME_RATE_OVERRIDE_VERSION}
frameRateMinimum=${FRAME_RATE_MINIMUM}
frameRateMaximum=${FRAME_RATE_MAXIMUM}
frameRatePreferred=${FRAME_RATE_PREFERRED}
stress=${CADENCE_STRESS}
wakeDisplay=${CADENCE_WAKE_DISPLAY}
fullscreen=${CADENCE_FULLSCREEN}
onlyMode=${CADENCE_ONLY_MODE}
display120=${DISPLAY_120}
display60=${DISPLAY_60}
nativeDisplay120=${NATIVE_DISPLAY_120}
nativeDisplay60=${NATIVE_DISPLAY_60}
app=${APP_DIR}
presentationContract=suppliedDrawable (no nextDrawable product path)
cpuGpuP95=not measured here; use Instruments and Metal HUD for acceptance evidence
measurementEpoch=owner-thread-reset-after-warmup
presentationModes=windowed-composited or fullscreen-direct-eligible-unverified; metalHUDState=${HUD_STATE}
hudState=${HUD_STATE}
EOF

if [[ "${overall}" == "0" ]]; then
    echo "native cadence measurement: PASS (logic/presentation/focus/migration/resize gates)"
else
    echo "native cadence measurement: FAIL or UNPROVEN; inspect ${MEASURE_ROOT}/120/report.txt and ${MEASURE_ROOT}/60/report.txt" >&2
    exit 1
fi
