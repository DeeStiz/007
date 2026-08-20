#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ASSET_ROOT="${1:-${GOLDENEYE_NATIVE_ASSET_ROOT:-${ROOT}/build/native/boot-assets}}"
BUILD_ROOT="${ROOT}/build/native/gunbarrel-v6"
SIDECAR_ROOT="${ROOT}/build/native/gunbarrel-v6-prepared"
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/goldeneye-gunbarrel-v6.XXXXXX")
trap 'rm -rf "${TEMP_ROOT}"' EXIT
mkdir -p "${BUILD_ROOT}"

python3 "${SCRIPT_DIR}/prepare_native_gunbarrel_v6.py" \
    --project-root "${ROOT}" \
    --output "${SIDECAR_ROOT}/gunbarrel.gbar" \
    | tee "${BUILD_ROOT}/prepare.log"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
SWIFTC=$(xcrun --sdk macosx --find swiftc)

# Extract the source-owned encrypted stream only for the sanitizer/decoder
# smoke. This is test input, not a runtime asset or application-bundle input.
python3 - "${ROOT}/src/game/blood_animation.c" "${TEMP_ROOT}/die_blood_image_1.raw" <<'PY'
import hashlib
import pathlib
import re
import sys

source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(r"u8 die_blood_image_1\[\] = \{(.*?)\};", source, re.S)
if not match:
    raise SystemExit("blood source array missing")
values = [int(value, 0) for value in re.findall(r"0x[0-9A-Fa-f]+|\b\d+\b", match.group(1))]
payload = bytes(values)
if len(payload) != 2524:
    raise SystemExit(f"blood source payload size {len(payload)}")
expected = "cc960835635ee32b1ef793e6c30f9ec8ed199cd416c5dd8d418db1307ed2dda2"
if hashlib.sha256(payload).hexdigest() != expected:
    raise SystemExit("blood source payload hash mismatch")
pathlib.Path(sys.argv[2]).write_bytes(payload)
PY

"${SWIFTC}" -swift-version 6 -warnings-as-errors -O -parse-as-library \
    -target arm64-apple-macosx27.0 -sdk "${SDKROOT}" \
    "${ROOT}/native/host/title_geometry_packet.swift" \
    "${ROOT}/native/host/goldeneye_source_model_v6.swift" \
    "${ROOT}/native/host/goldeneye_gunbarrel_v6.swift" \
    "${ROOT}/native/tests/goldeneye_gunbarrel_v6_smoke.swift" \
    -o "${BUILD_ROOT}/goldeneye_gunbarrel_v6_smoke"

"${BUILD_ROOT}/goldeneye_gunbarrel_v6_smoke" \
    "${ASSET_ROOT}" \
    "${TEMP_ROOT}/die_blood_image_1.raw" \
    "${BUILD_ROOT}/gunbarrel-manifest.txt" \
    "${SIDECAR_ROOT}/gunbarrel.gbar" \
    | tee "${BUILD_ROOT}/smoke.log"

grep -Fq 'goldeneye_gunbarrel_v6_smoke: PASS' "${BUILD_ROOT}/smoke.log"
grep -Fq 'gunbarrel_capture_ready=0' "${BUILD_ROOT}/smoke.log"
grep -Fq 'gunbarrel_dynamic_resolver=PASS' "${BUILD_ROOT}/smoke.log"
grep -Fq 'gunbarrel_pose_counts=body:16,head:16,weaponSynthetic:0' "${BUILD_ROOT}/smoke.log"
grep -Fq 'native_hz=120' "${BUILD_ROOT}/gunbarrel-manifest.txt"
grep -Fq 'model_substeps_per_reference_frame=2' "${BUILD_ROOT}/gunbarrel-manifest.txt"
grep -Fq 'hole_vertices=30' "${BUILD_ROOT}/gunbarrel-manifest.txt"
grep -Fq 'hole_triangles=28' "${BUILD_ROOT}/gunbarrel-manifest.txt"
grep -Fq 'capture_ready=false' "${BUILD_ROOT}/gunbarrel-manifest.txt"

"${SWIFTC}" -swift-version 6 -warnings-as-errors -O -parse-as-library \
    -target arm64-apple-macosx27.0 -sdk "${SDKROOT}" \
    "${ROOT}/native/host/title_geometry_packet.swift" \
    "${ROOT}/native/host/goldeneye_source_model_v6.swift" \
    "${ROOT}/native/host/goldeneye_gunbarrel_v6.swift" \
    "${ROOT}/native/tests/goldeneye_gunbarrel_dynamic_model_v6_smoke.swift" \
    -o "${BUILD_ROOT}/goldeneye_gunbarrel_dynamic_model_v6_smoke"

"${BUILD_ROOT}/goldeneye_gunbarrel_dynamic_model_v6_smoke" \
    "${ROOT}/build/native/source-frontend-v6" \
    "${SIDECAR_ROOT}/gunbarrel.gbar" \
    | tee "${BUILD_ROOT}/dynamic-model.log"
grep -Fq 'goldeneye_gunbarrel_dynamic_model_v6_smoke: PASS' "${BUILD_ROOT}/dynamic-model.log"
grep -Fq 'gunbarrel_dynamic_scene=headbrosnansuit:' "${BUILD_ROOT}/dynamic-model.log"
grep -Fq 'gunbarrel_dynamic_scene=suitbond:' "${BUILD_ROOT}/dynamic-model.log"
grep -Fq 'gunbarrel_dynamic_scene=chrwppk:' "${BUILD_ROOT}/dynamic-model.log"

python3 - "${SIDECAR_ROOT}/gunbarrel.gbar" "${TEMP_ROOT}/tampered.gbar" <<'PY'
import json
import pathlib
import sys

value = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
value["packet_sha256"] = "0" * 64
pathlib.Path(sys.argv[2]).write_text(
    json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n",
    encoding="utf-8",
)
PY
python3 - "${BUILD_ROOT}/goldeneye_gunbarrel_dynamic_model_v6_smoke" \
    "${ROOT}/build/native/source-frontend-v6" \
    "${TEMP_ROOT}/tampered.gbar" \
    "${BUILD_ROOT}/tampered.log" <<'PY'
import pathlib
import subprocess
import sys

result = subprocess.run(sys.argv[1:4], capture_output=True, text=True)
output = result.stdout + result.stderr
pathlib.Path(sys.argv[4]).write_text(output, encoding="utf-8")
if result.returncode == 0 or "Gunbarrel dynamic sidecar hash" not in output:
    raise SystemExit("tampered Gunbarrel sidecar was accepted")
PY
echo 'gunbarrel_sidecar_tamper_guard=PASS'

echo "test_gunbarrel_v6: PASS"
echo "evidence=${BUILD_ROOT}"
