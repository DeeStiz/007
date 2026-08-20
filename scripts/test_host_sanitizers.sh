#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
BUILD_DIR="${PROJECT_ROOT}/build/native/m9-host-sanitizers"
MODULE_CACHE_DIR="${BUILD_DIR}/module-cache"
SANITIZER_ROOT=$(mktemp -d /tmp/goldeneye-host-sanitizers.XXXXXX)

mkdir -p "${BUILD_DIR}" "${MODULE_CACHE_DIR}"
if ! command -v gtimeout >/dev/null 2>&1; then
    echo "gtimeout is required for the bounded AppKit sanitizer run" >&2
    exit 1
fi

run_sanitized_host() {
    local name="$1"
    local sanitizer="$2"
    local runtime_options="$3"
    local log_file="${BUILD_DIR}/${name}.log"
    local scratch="${SANITIZER_ROOT}/${name}"
    local binary="${scratch}/swiftpm/out/Products/Debug/GoldenEyeHost"

    mkdir -p "${scratch}/module-cache"
    CLANG_MODULE_CACHE_PATH="${scratch}/module-cache" \
    SWIFTPM_MODULECACHE_OVERRIDE="${scratch}/module-cache" \
        swift build --disable-sandbox --configuration debug \
        --scratch-path "${scratch}/swiftpm" --product GoldenEyeHost \
        -Xswiftc "-sanitize=${sanitizer}" \
        -Xcc "-fsanitize=${sanitizer}" -Xcc -fno-omit-frame-pointer \
        > "${BUILD_DIR}/${name}-build.log" 2>&1

    test -x "${binary}"
    rm -f /tmp/goldeneye-m2-owner-loop.log
    set +e
    env "${runtime_options}" MTL_DEBUG_LAYER=1 \
        MTL_DEBUG_LAYER_ERROR_MODE=nslog \
        gtimeout -k 3 15 "${binary}" > "${log_file}" 2>&1
    local run_status=$?
    set -e
    if [ "${run_status}" -ne 124 ]; then
        echo "${name} host did not reach the expected bounded timeout (status ${run_status})" >&2
        cat "${log_file}" >&2
        exit 1
    fi
    rg -q 'initialized=1 ticks=60 shutdown=0' /tmp/goldeneye-m2-owner-loop.log
    if rg -n 'AddressSanitizer|UndefinedBehaviorSanitizer|runtime error|ERROR:|SUMMARY:' "${log_file}"; then
        echo "${name} sanitizer reported a runtime diagnostic" >&2
        exit 1
    fi
    echo "${name}=pass status=bounded-timeout owner=60 sanitizer=clean"
}

run_sanitized_host asan address 'ASAN_OPTIONS=halt_on_error=1:abort_on_error=1'
run_sanitized_host ubsan undefined 'UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1'
echo "M9 host ASan/UBSan validation: PASS"
