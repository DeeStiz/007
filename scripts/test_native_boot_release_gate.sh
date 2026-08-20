#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ROM_PATH="${1:-${GOLDENEYE_ROM_PATH:-/Users/derek/Documents/GoldenEye 007 (USA).z64}}"

[[ -f "${ROM_PATH}" ]] || {
    echo "external verified ROM is required: ${ROM_PATH}" >&2
    exit 2
}

echo "Checking signed-product renderer selection cannot be diverted by the environment"
"${SCRIPT_DIR}/test_release_renderer_environment_guard_v6.sh"
"${SCRIPT_DIR}/test_fidelity_policy.sh"

TEST_LOG_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/goldeneye-release-gate-logs.XXXXXX")
DRY_RUN_LOG="${TEST_LOG_ROOT}/prepared-dry-run.log"
BUILD_DRY_RUN_LOG="${TEST_LOG_ROOT}/build-dry-run.log"

echo "Checking read-only prepared-catalog dry run"
"${SCRIPT_DIR}/verify_native_boot_release.sh" --dry-run "${ROM_PATH}" \
    | tee "${DRY_RUN_LOG}"
grep -Fq 'native boot release gate: PASS' \
    "${DRY_RUN_LOG}"
grep -Fq 'package_plan=source-scene-and-source-2d-no-procedural-shaders' \
    "${DRY_RUN_LOG}"

echo "Checking one-command build dry run"
"${SCRIPT_DIR}/build_native_boot.sh" --dry-run "${ROM_PATH}" \
    | tee "${BUILD_DRY_RUN_LOG}"
grep -Fq 'dry_run=true' \
    "${BUILD_DRY_RUN_LOG}"

echo "Checking Release script shader/resource policy"
if rg -n -q 'GoldenEyeTitle\.metal|GoldenEyeStageBackground\.metal' \
    "${SCRIPT_DIR}/build_native_boot.sh"; then
    echo "procedural title/stage shader is still referenced by Release build" >&2
    exit 1
fi
grep -Fq 'GoldenEyeSourceSceneV6.metal' "${SCRIPT_DIR}/build_native_boot.sh"
grep -Fq 'GoldenEyeSourceSceneV6.metallib' "${SCRIPT_DIR}/build_native_boot.sh"
grep -Fq 'GoldenEyeSource2DV6.metal' "${SCRIPT_DIR}/build_native_boot.sh"
grep -Fq 'GoldenEyeSource2DV6.metallib' "${SCRIPT_DIR}/build_native_boot.sh"
grep -Fq 'GOLDENEYE_NATIVE_SOURCE_FRONTEND_ROOT' "${SCRIPT_DIR}/run_native_boot.sh"
grep -Fq 'source-faithful/GoldenEyeHost.app' "${SCRIPT_DIR}/run_native_boot.sh"
grep -Fq 'source-frontend-v6-image-decoder-v6' "${SCRIPT_DIR}/build_native_boot.sh"
grep -Fq 'source-frontend-v6-image-decoder-v6' "${SCRIPT_DIR}/prepare_native_boot_assets.sh"
grep -Fq 'source-frontend-v6-image-decoder-v6' "${SCRIPT_DIR}/measure_native_runtime.sh"

TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/goldeneye-release-gate.XXXXXX")
BAD_APP="${TEMP_ROOT}/GoldenEyeHost.app"
mkdir -p "${BAD_APP}/Contents/MacOS" "${BAD_APP}/Contents/Resources"
cp -f /usr/bin/true "${BAD_APP}/Contents/MacOS/GoldenEyeHost"
printf '%s\n' '<plist version="1.0"><dict/></plist>' > "${BAD_APP}/Contents/Info.plist"
printf 'fixture\n' > "${BAD_APP}/Contents/Resources/GoldenEyeSourceSceneV6.metallib"
printf 'fixture\n' > "${BAD_APP}/Contents/Resources/GoldenEyeSource2DV6.metallib"
: > "${BAD_APP}/Contents/Resources/GoldenEyeTitle.metallib"

echo "Checking the preserved b924 catalog cannot be selected by the Release gate"
OLD_ROOT_LOG="${TEMP_ROOT}/old-source-root.log"
if GOLDENEYE_NATIVE_SOURCE_FRONTEND_ROOT="${PROJECT_ROOT}/build/native/source-frontend-v6" \
    "${SCRIPT_DIR}/verify_native_boot_release.sh" --dry-run "${ROM_PATH}" \
    > "${OLD_ROOT_LOG}" 2>&1; then
    echo "preserved b924 source catalog unexpectedly passed as Release input" >&2
    exit 1
fi
grep -Fq 'versioned corrected source catalog' "${OLD_ROOT_LOG}"

echo "Checking forbidden diagnostic resource rejection"
if "${SCRIPT_DIR}/verify_native_boot_release.sh" \
    --bundle "${BAD_APP}" "${ROM_PATH}" > "${TEMP_ROOT}/forbidden.log" 2>&1; then
    echo "bundle with procedural title shader unexpectedly passed" >&2
    exit 1
fi
grep -Fq 'unexpected resource in source-faithful bundle' "${TEMP_ROOT}/forbidden.log"

echo "Checking old diagnostic bundle rejection"
OLD_APP="${PROJECT_ROOT}/build/native/boot-runtime/GoldenEyeHost.app"
if [[ -d "${OLD_APP}" ]] && "${SCRIPT_DIR}/verify_native_boot_release.sh" \
    --bundle "${OLD_APP}" "${ROM_PATH}" > "${TEMP_ROOT}/old.log" 2>&1; then
    echo "old diagnostic bundle unexpectedly passed Release gate" >&2
    exit 1
fi

echo "Native boot Release gate: PASS"
