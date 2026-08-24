#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
MAIN="${PROJECT_ROOT}/native/host/main.swift"
RUNNER="${SCRIPT_DIR}/run_native_boot.sh"
MEASURE="${SCRIPT_DIR}/measure_native_runtime.sh"

grep -Fq 'GOLDENEYE_NATIVE_BACKGROUND' "${MAIN}"
grep -Fq 'if !backgroundRuntimeEnabled' "${MAIN}"
grep -Fq 'GOLDENEYE_NATIVE_BACKGROUND="${GOLDENEYE_NATIVE_BACKGROUND:-1}"' "${RUNNER}"
grep -Fq 'open -n' "${RUNNER}"
grep -Fq 'GOLDENEYE_NATIVE_BACKGROUND="${GOLDENEYE_NATIVE_BACKGROUND:-0}"' "${MEASURE}"

echo "native background launch policy: PASS owner-independent background mode=1 foreground cadence default=0"
