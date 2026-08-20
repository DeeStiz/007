#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ROM_PATH="${1:-${GOLDENEYE_EXTERNAL_ROM:-/Users/derek/Documents/GoldenEye 007 (USA).z64}}"
STAGE_ROOT="${2:-${GOLDENEYE_NATIVE_STAGE_ASSET_ROOT:-${PROJECT_ROOT}/build/native/stage-assets-image-decoder-v6}}"

python3 "${SCRIPT_DIR}/prepare_native_stage_texture_assets.py" \
    --project-root "${PROJECT_ROOT}" \
    --rom "${ROM_PATH}" \
    --stage-asset-root "${STAGE_ROOT}"

MANIFEST="${STAGE_ROOT}/stage-texture-dependencies-manifest.txt"
TEXTURE_ROOT="${STAGE_ROOT}/textures"
python3 - "${MANIFEST}" "${TEXTURE_ROOT}" <<'PY'
from __future__ import annotations

import hashlib
import json
import re
import sys
from collections import Counter
from pathlib import Path

manifest = Path(sys.argv[1])
payload_root = Path(sys.argv[2])
lines = manifest.read_text(encoding="utf-8").splitlines()
values = dict(line.split("=", 1) for line in lines if "=" in line and not re.match(r"(?:image|command)_\d+=", line))
expected = {
    "manifest_status": "PASS",
    "source_trace_status": "PASS",
    "payload_status": "PASS",
    "stage_count": "7",
    "stream_count": "758",
    "binding_count": "3575",
    "unique_texture_count": "436",
    "unique_tlut_count": "248",
    "external_rom_sha1": "abe01e4aeb033b6c0836819f549c791b26cfde83",
    "decoder_contract": "goldeneye_pd_image_decoder_v6",
    "source_level_semantics": "explicit_levels_authored_implicit_level0_only",
}
for key, value in expected.items():
    if values.get(key) != value:
        raise SystemExit(f"manifest {key}={values.get(key)!r}, expected {value!r}")

image_lines = [line for line in lines if re.match(r"image_\d+=", line)]
command_lines = [line for line in lines if re.match(r"command_\d+=", line)]
if len(image_lines) != 436 or len(command_lines) != 3575:
    raise SystemExit(f"manifest rows images={len(image_lines)} commands={len(command_lines)}")

images: dict[int, dict[str, str]] = {}
visibility = Counter()
for line in image_lines:
    key, payload = line.split("=", 1)
    texture_id = int(key.removeprefix("image_"))
    prefix, _, tlut_json = payload.partition("|tlut:")
    fields = {}
    for field in prefix.split("|"):
        name, value = field.split(":", 1)
        fields[name] = value
    fields["tlut"] = tlut_json
    images[texture_id] = fields
    visibility[fields["visibility"]] += 1
    if fields.get("upload_row_order") != "source" or fields.get("inspection_row_order") != "vertical_flip":
        raise SystemExit(f"image {texture_id} source orientation contract changed")
    if fields.get("source_explicit_lods") not in {"true", "false"}:
        raise SystemExit(f"image {texture_id} source LOD provenance is missing")
    raw = payload_root / fields["raw_file"]
    if not raw.is_file():
        raise SystemExit(f"missing raw payload {raw}")
    if hashlib.sha256(raw.read_bytes()).hexdigest() != fields["source_sha256"]:
        raise SystemExit(f"raw payload digest mismatch for texture {texture_id}")
    level = fields["levels"].split(";", 1)[0].split(":")
    if int(fields["source_level_count"]) != len(fields["levels"].split(";")):
        raise SystemExit(f"source level count mismatch for texture {texture_id}")
    decoded = payload_root / level[5]
    if not decoded.is_file() or decoded.stat().st_size != int(level[3]):
        raise SystemExit(f"base decoded payload mismatch for texture {texture_id}")
    if hashlib.sha256(decoded.read_bytes()).hexdigest() != level[4]:
        raise SystemExit(f"base decoded digest mismatch for texture {texture_id}")
    inspection = payload_root / level[7]
    if not inspection.is_file() or hashlib.sha256(inspection.read_bytes()).hexdigest() != level[6]:
        raise SystemExit(f"canonical inspection digest mismatch for texture {texture_id}")
    tlut = json.loads(fields["tlut"])
    if tlut is not None:
        raw_tlut = payload_root / tlut["raw_file"]
        decoded_tlut = payload_root / tlut["decoded_file"]
        if not raw_tlut.is_file() or not decoded_tlut.is_file():
            raise SystemExit(f"missing TLUT payload for texture {texture_id}")
        if hashlib.sha256(raw_tlut.read_bytes()).hexdigest() != tlut["raw_sha256"]:
            raise SystemExit(f"TLUT raw digest mismatch for texture {texture_id}")
        if hashlib.sha256(decoded_tlut.read_bytes()).hexdigest() != tlut["decoded_sha256"]:
            raise SystemExit(f"TLUT decoded digest mismatch for texture {texture_id}")

stages = set()
for line in command_lines:
    _, payload = line.split("=", 1)
    fields = dict(field.split(":", 1) for field in payload.split("|"))
    texture_id = int(fields["texture_id"])
    if texture_id not in images:
        raise SystemExit(f"command references missing image row {texture_id}")
    if fields["image_source_sha256"] != images[texture_id]["source_sha256"]:
        raise SystemExit(f"command/image digest linkage mismatch for texture {texture_id}")
    if fields.get("upload_row_order") != "source" or fields.get("inspection_row_order") != "vertical_flip":
        raise SystemExit(f"command texture orientation contract changed for texture {texture_id}")
    stages.add(fields["stage"])
if stages != {"Dam", "Facility", "Runway", "Bunker I", "Silo", "Frigate", "Train"}:
    raise SystemExit(f"command stage set mismatch: {sorted(stages)}")
if visibility != Counter({"colored": 433, "source-monochrome-black": 3}):
    raise SystemExit(f"source visibility classification changed: {visibility}")

for path in payload_root.rglob("*.z64"):
    raise SystemExit(f"ROM-like payload appeared under stage texture root: {path}")
for path in payload_root.rglob("*.n64"):
    raise SystemExit(f"ROM-like payload appeared under stage texture root: {path}")
print("native_stage_texture_dependencies: PASS stages=7 streams=758 bindings=3575 textures=436 tluts=248")
PY
