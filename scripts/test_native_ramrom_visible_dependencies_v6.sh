#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ROM_PATH="${1:-${GOLDENEYE_EXTERNAL_ROM:-/Users/derek/Documents/GoldenEye 007 (USA).z64}}"
STAGE_ROOT="${2:-${GOLDENEYE_NATIVE_STAGE_ASSET_ROOT:-${PROJECT_ROOT}/build/native/stage-assets-image-decoder-v6}}"
OUTPUT_ROOT="${3:-${PROJECT_ROOT}/build/native/ramrom-visible-dependencies-v6}"

python3 "${SCRIPT_DIR}/prepare_native_ramrom_visible_dependencies_v6.py" \
    --project-root "${PROJECT_ROOT}" \
    --rom "${ROM_PATH}" \
    --stage-asset-root "${STAGE_ROOT}" \
    --output-dir "${OUTPUT_ROOT}"

MANIFEST="${OUTPUT_ROOT}/ramrom-visible-dependencies-v6-manifest.txt"
python3 - "${MANIFEST}" "${OUTPUT_ROOT}" <<'PY'
from __future__ import annotations

import hashlib
import re
import sys
from collections import Counter
from pathlib import Path

manifest = Path(sys.argv[1])
root = Path(sys.argv[2])
lines = manifest.read_text(encoding="utf-8").splitlines()
values = dict(
    line.split("=", 1)
    for line in lines
    if "=" in line and not re.match(r"(?:dependency|demo)_\d+=", line)
)
expected = {
    "manifest_version": "6",
    "asset_family": "ramrom_visible_dependencies_v6",
    "manifest_status": "PASS",
    "coverage_status": "PASS",
    "payload_status": "PASS",
    "source_trace_status": "PASS",
    "external_rom_size": "12582912",
    "external_rom_sha1": "abe01e4aeb033b6c0836819f549c791b26cfde83",
    "runtime_opens_rom": "false",
    "runtime_consumes_prepared_payloads_only": "true",
    "emulation_used": "false",
    "demo_count": "14",
    "stage_count": "7",
}
for key, value in expected.items():
    if values.get(key) != value:
        raise SystemExit(f"manifest {key}={values.get(key)!r}, expected {value!r}")

required_categories = {
    "props", "doors", "guards", "heads", "weapons", "projectiles", "effects", "particles",
    "glass", "explosions", "hud", "watch", "sky", "fades", "textures", "audio",
}
if set(values.get("categories", "").split(",")) != required_categories:
    raise SystemExit(f"category set mismatch: {values.get('categories')!r}")

dependency_lines = [line for line in lines if re.match(r"dependency_\d+=", line)]
if len(dependency_lines) != int(values.get("dependency_count", "0")) or len(dependency_lines) < 16:
    raise SystemExit(f"dependency row count mismatch: {len(dependency_lines)}")
counts = Counter()
seen = set()
for line in dependency_lines:
    _, payload = line.split("=", 1)
    fields = dict(field.split(":", 1) for field in payload.split("|"))
    category = fields["category"]
    counts[category] += 1
    if fields["symbol"] in seen:
        raise SystemExit(f"duplicate dependency symbol: {fields['symbol']}")
    seen.add(fields["symbol"])
    if not fields.get("demo_ids") or not fields.get("stages"):
        raise SystemExit(f"dependency lacks route coverage: {fields['symbol']}")
    if fields.get("asset_type") == "semantic":
        if fields["rom_row"] != "none" or fields["raw_file"] != "none" or fields["decoded_file"] != "none":
            raise SystemExit(f"semantic dependency carries a payload path: {fields['symbol']}")
        continue
    raw = root / fields["raw_file"]
    decoded = root / fields["decoded_file"]
    if not raw.is_file() or not decoded.is_file():
        raise SystemExit(f"missing payload for {fields['symbol']}: {raw} / {decoded}")
    if raw.stat().st_size != int(fields["source_bytes"]):
        raise SystemExit(f"raw payload size mismatch: {fields['symbol']}")
    if decoded.stat().st_size != int(fields["decoded_bytes"]):
        raise SystemExit(f"decoded payload size mismatch: {fields['symbol']}")
    if hashlib.sha256(raw.read_bytes()).hexdigest() != fields["source_sha256"]:
        raise SystemExit(f"raw payload digest mismatch: {fields['symbol']}")
    if hashlib.sha256(decoded.read_bytes()).hexdigest() != fields["decoded_sha256"]:
        raise SystemExit(f"decoded payload digest mismatch: {fields['symbol']}")
    if fields["rom_row"] == "none" or fields["rom_offset"] == "none":
        raise SystemExit(f"payload dependency has no guarded ROM row: {fields['symbol']}")
    for key in ("mip_0_file", "mip_0_bytes", "mip_0_sha256"):
        if category == "textures" and key not in fields:
            raise SystemExit(f"texture lacks base mip linkage: {fields['symbol']}")
    if category == "textures":
        mip_levels = sorted(
            {key.split("_", 2)[1] for key in fields if key.startswith("mip_") and key.endswith("_file")},
            key=int,
        )
        for level in mip_levels:
            mip_file = root / fields[f"mip_{level}_file"]
            if not mip_file.is_file() or mip_file.stat().st_size != int(fields[f"mip_{level}_bytes"]):
                raise SystemExit(f"mip payload mismatch: {fields['symbol']} level {level}")
            if hashlib.sha256(mip_file.read_bytes()).hexdigest() != fields[f"mip_{level}_sha256"]:
                raise SystemExit(f"mip digest mismatch: {fields['symbol']} level {level}")
    if "tlut_raw_file" in fields:
        tlut_raw = root / fields["tlut_raw_file"]
        tlut_decoded = root / fields["tlut_decoded_file"]
        if not tlut_raw.is_file() or not tlut_decoded.is_file():
            raise SystemExit(f"missing TLUT payload: {fields['symbol']}")
        if hashlib.sha256(tlut_raw.read_bytes()).hexdigest() != fields["tlut_raw_sha256"]:
            raise SystemExit(f"TLUT raw digest mismatch: {fields['symbol']}")
        if hashlib.sha256(tlut_decoded.read_bytes()).hexdigest() != fields["tlut_decoded_sha256"]:
            raise SystemExit(f"TLUT decoded digest mismatch: {fields['symbol']}")

if set(counts) != required_categories or any(counts[key] == 0 for key in required_categories):
    raise SystemExit(f"category coverage incomplete: {counts}")
for index in range(1, 15):
    prefix = f"demo_{index}="
    if not any(line.startswith(prefix) for line in lines):
        raise SystemExit(f"missing route row: demo {index}")

for suffix in (".z64", ".n64", ".Z64", ".N64"):
    if any(root.rglob(f"*{suffix}")):
        raise SystemExit(f"ROM-like payload appeared under output: {suffix}")
print(
    "native_ramrom_visible_dependencies_v6: PASS "
    f"demos=14 stages=7 dependencies={len(dependency_lines)} categories={len(required_categories)} "
    f"textures={counts['textures']} audio={counts['audio']}"
)
PY

git -C "${PROJECT_ROOT}" diff --check
