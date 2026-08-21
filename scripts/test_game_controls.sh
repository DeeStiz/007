#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)

rg -q 'Reset Game' "${PROJECT_ROOT}/native/host/main.swift"
rg -q '#selector\(resetGame\(_:\)\)' "${PROJECT_ROOT}/native/host/main.swift"
rg -q 'func resetGame\(timeout:' "${PROJECT_ROOT}/native/host/engine_owner.swift"
rg -q 'scheduler\.resetGame' "${PROJECT_ROOT}/native/host/engine_owner.swift"
rg -q 'resetGameState\(\)' "${PROJECT_ROOT}/native/host/native_title_owner.swift"
rg -q 'Show Performance Overlay' "${PROJECT_ROOT}/native/host/main.swift"
rg -q 'GOLDENEYE_PERFORMANCE_OVERLAY' "${PROJECT_ROOT}/native/host/main.swift"
rg -q 'NSApp\.dockTile\.badgeLabel' "${PROJECT_ROOT}/native/host/main.swift"
rg -q 'callbackDurationP95' "${PROJECT_ROOT}/native/host/main.swift"
rg -q 'final class GoldenEyePerformanceOverlay' "${PROJECT_ROOT}/native/host/performance_overlay.swift"

echo "GoldenEye game reset/performance taskbar controls: PASS"
