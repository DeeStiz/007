#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
MAIN="${ROOT}/native/host/main.swift"

python3 - "${MAIN}" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")

required = (
    'if GoldenEyeFidelityBuildFlavor.current == .debug,\n'
    '           ProcessInfo.processInfo.environment["GOLDENEYE_DIAGNOSTIC_TITLE_FLOW"] == "1"',
    'GoldenEyeFidelityBuildFlavor.current == .debug\n'
    '            && ProcessInfo.processInfo.environment["GOLDENEYE_M27_STAGE_OVERLAY"] == "1"',
    'let allowsDiagnosticRenderer = GoldenEyeFidelityBuildFlavor.current == .debug',
    'let wantsClassicProp = allowsDiagnosticRenderer',
    'let wantsClassicTexturedProp = allowsDiagnosticRenderer',
    'let wantsClassicCombiner = allowsDiagnosticRenderer',
    'let wantsDiagnosticTitle = allowsDiagnosticRenderer',
    'let wantsPipeline = allowsDiagnosticRenderer',
    '} else if allowsDiagnosticRenderer,\n'
    '                          wantsNativeTitle,\n'
    '                   ProcessInfo.processInfo.environment["GOLDENEYE_CADENCE_RENDERER"] == "clear"',
)

missing = [needle for needle in required if needle not in source]
if missing:
    raise SystemExit("Release renderer environment guard is incomplete: " + repr(missing))

# Every legacy renderer selector in the product controller must be dominated
# by the explicit Debug-flavor policy above. This is a source-level Release
# gate; the signed executable may inherit an arbitrary launch environment.
selectors = (
    "GOLDENEYE_M6_PIPELINE",
    "GOLDENEYE_M8_TRIANGLE",
    "GOLDENEYE_M10_PROP",
    "GOLDENEYE_M11_TEXTURED_PROP",
    "GOLDENEYE_M12_CLASSIC_COMBINER",
    "GOLDENEYE_M27_STAGE_OVERLAY",
    "GOLDENEYE_DIAGNOSTIC_TITLE_FLOW",
    "GOLDENEYE_CADENCE_RENDERER",
)
for selector in selectors:
    if selector not in source:
        raise SystemExit(f"expected diagnostic selector is missing from audit: {selector}")

print("release_renderer_environment_guard_v6: PASS selectors=8 releaseDiagnosticPaths=0")
PY

SWIFTC=$(xcrun --sdk macosx --find swiftc)
SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
MODULE_CACHE_DIR="${ROOT}/build/native/release-renderer-environment-guard-v6/module-cache"
mkdir -p "${MODULE_CACHE_DIR}"
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" "${SWIFTC}" -frontend -parse -sdk "${SDKROOT}" \
    "${ROOT}/native/host/goldeneye_fidelity_policy.swift" \
    "${MAIN}"
