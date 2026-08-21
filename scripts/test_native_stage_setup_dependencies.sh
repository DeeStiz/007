#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ROM_PATH="${1:-${GOLDENEYE_EXTERNAL_ROM:-/Users/derek/Documents/GoldenEye 007 (USA).z64}}"
STAGE_ROOT="${2:-${GOLDENEYE_NATIVE_STAGE_ASSET_ROOT:-${PROJECT_ROOT}/build/native/stage-assets-image-decoder-v6}}"

python3 "${SCRIPT_DIR}/prepare_native_stage_setup_dependencies.py" \
    --project-root "${PROJECT_ROOT}" \
    --rom "${ROM_PATH}" \
    --stage-asset-root "${STAGE_ROOT}"

MANIFEST="${STAGE_ROOT}/stage-setup-model-dependencies-manifest.txt"
python3 - "${MANIFEST}" "${STAGE_ROOT}" <<'PY'
from __future__ import annotations

import hashlib
import re
import sys
from collections import Counter
from pathlib import Path

manifest = Path(sys.argv[1])
root = Path(sys.argv[2])
lines = manifest.read_text(encoding="utf-8").splitlines()
values = dict(line.split("=", 1) for line in lines if "=" in line and not re.match(r"dependency_\d+=", line))
expected = {
    "manifest_status": "PASS",
    "source_setup_status": "PASS",
    "payload_status": "PASS",
    "dependency_count": "1783",
    "unique_dependency_count": "141",
    "prop_model_table_count": "340",
    "character_model_table_count": "80",
}
for key, value in expected.items():
    if values.get(key) != value:
        raise SystemExit(f"manifest {key}={values.get(key)!r}, expected {value!r}")

rows = [line for line in lines if re.match(r"dependency_\d+=", line)]
if len(rows) != 1783:
    raise SystemExit(f"dependency rows={len(rows)}")
counts = Counter()
for line in rows:
    fields = dict(item.split(":", 1) for item in line.split("=", 1)[1].split("|"))
    counts[(fields["stage"], fields["kind"])] += 1
    decoded = root / fields["decoded_file"]
    raw = root / fields["raw_file"]
    if not raw.is_file() or not decoded.is_file():
        raise SystemExit(f"missing dependency payload: {raw} / {decoded}")
    if hashlib.sha256(raw.read_bytes()).hexdigest() != fields["source_sha256"]:
        raise SystemExit(f"raw dependency digest mismatch: {raw}")
    if hashlib.sha256(decoded.read_bytes()).hexdigest() != fields["decoded_sha256"]:
        raise SystemExit(f"decoded dependency digest mismatch: {decoded}")
if not all(counts[(stage, kind)] > 0 for stage in ("Dam", "Facility", "Runway", "Bunker I", "Silo", "Frigate", "Train") for kind in ("prop", "character")):
    raise SystemExit(f"stage dependency coverage incomplete: {counts}")
print("native_stage_setup_dependencies: PASS references=1783 unique=141 stages=7 props=1484 characters=299")
PY
