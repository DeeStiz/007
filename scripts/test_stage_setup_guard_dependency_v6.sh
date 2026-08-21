#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ROM_PATH="${1:-${GOLDENEYE_EXTERNAL_ROM:-/Users/derek/Documents/GoldenEye 007 (USA).z64}}"
STAGE_ROOT="${2:-${GOLDENEYE_NATIVE_STAGE_ASSET_ROOT:-${ROOT}/build/native/stage-assets-image-decoder-v6}}"
BUILD_ROOT="${ROOT}/build/native/stage-setup-guard-dependency-v6"
mkdir -p "${BUILD_ROOT}"

python3 "${SCRIPT_DIR}/prepare_native_stage_setup_dependencies.py" \
    --project-root "${ROOT}" \
    --rom "${ROM_PATH}" \
    --stage-asset-root "${STAGE_ROOT}"

MANIFEST="${STAGE_ROOT}/stage-setup-model-dependencies-manifest.txt"
SETUP="${STAGE_ROOT}/setup/Dam__setup__UsetupdamZ.bin"

python3 - "${ROOT}" "${SETUP}" "${MANIFEST}" <<'PY'
from __future__ import annotations

import importlib.util
import struct
import sys
from pathlib import Path

root = Path(sys.argv[1])
setup_path = Path(sys.argv[2])
manifest_path = Path(sys.argv[3])
spec = importlib.util.spec_from_file_location(
    "prepare_native_stage_setup_dependencies",
    root / "scripts/prepare_native_stage_setup_dependencies.py",
)
if spec is None or spec.loader is None:
    raise SystemExit("preparer module could not be loaded")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

setup = setup_path.read_bytes()
rows = module.object_dependencies("Dam", setup, props=340, chrs=80)
dam = next(
    row for row in rows
    if row["setup_offset"] == 23000 and row["kind"] == "character"
)
if dam["model_index"] != 37:
    raise SystemExit(f"Dam body index={dam['model_index']}, expected 37")
if dam["object_index"] != 0:
    raise SystemExit(f"Dam object index={dam['object_index']}, expected 0")

def synthetic(end: int, body_id: int = 37) -> bytearray:
    data = bytearray(max(end, 68))
    struct.pack_into(">I", data, 12, 40)  # setup object section
    struct.pack_into(">I", data, 16, end)  # next section/end boundary
    struct.pack_into(">I", data, 40, 9)   # GuardRecord, size = 7 words
    struct.pack_into(">I", data, 44, 0x00000001)  # chrnum=0, pad=1
    struct.pack_into(">I", data, 48, (body_id << 16) | 1037)
    return data

for label, data, expected in (
    ("truncated-record", synthetic(67), "truncated"),
    ("body-index-overflow", synthetic(68, 80), "character model index"),
):
    try:
        module.object_dependencies("Dam", bytes(data), props=340, chrs=80)
    except module.PreparationError as error:
        if expected not in str(error):
            raise SystemExit(f"{label} error={error!s}, expected {expected!r}")
    else:
        raise SystemExit(f"{label} was accepted")

manifest_text = manifest_path.read_text(encoding="utf-8")
needle = (
    "stage:Dam|kind:character|object_index:0|object_type:9|"
    "setup_offset:23000|model_index:37|model_name:greatguard2|"
)
if needle not in manifest_text:
    raise SystemExit("corrected Dam dependency row is absent")
print(
    "stage_setup_guard_dependency_python: PASS "
    "DamOffset=23000 chrnum=0 bodyID=37 aiListID=1037 "
    "malformed=failClosed"
)
PY

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun --sdk macosx --find clang)
CFLAGS=(-target arm64-apple-macosx27.0 -isysroot "${SDKROOT}" -std=c11 \
    -Wall -Wextra -Werror -pedantic -O2)
SOURCE="${ROOT}/native/tests/goldeneye_stage_setup_guard_dependency_v6_smoke.c"

"${CC}" "${CFLAGS[@]}" "${SOURCE}" -o "${BUILD_ROOT}/smoke-strict"
"${BUILD_ROOT}/smoke-strict" "${SETUP}" "${MANIFEST}" \
    | tee "${BUILD_ROOT}/strict.log"
grep -Fq 'goldeneye_stage_setup_guard_dependency_v6_smoke: PASS' "${BUILD_ROOT}/strict.log"

"${CC}" "${CFLAGS[@]}" -fsanitize=address "${SOURCE}" \
    -o "${BUILD_ROOT}/smoke-asan"
ASAN_OPTIONS=halt_on_error=1:detect_leaks=0 \
    "${BUILD_ROOT}/smoke-asan" "${SETUP}" "${MANIFEST}" \
    | tee "${BUILD_ROOT}/asan.log"
grep -Fq 'goldeneye_stage_setup_guard_dependency_v6_smoke: PASS' "${BUILD_ROOT}/asan.log"

"${CC}" "${CFLAGS[@]}" -fsanitize=undefined "${SOURCE}" \
    -o "${BUILD_ROOT}/smoke-ubsan"
UBSAN_OPTIONS=halt_on_error=1 \
    "${BUILD_ROOT}/smoke-ubsan" "${SETUP}" "${MANIFEST}" \
    | tee "${BUILD_ROOT}/ubsan.log"
grep -Fq 'goldeneye_stage_setup_guard_dependency_v6_smoke: PASS' "${BUILD_ROOT}/ubsan.log"

git -C "${ROOT}" diff --check
echo 'Stage setup GuardRecord body dependency V6 strict/ASan/UBSan validation: PASS'
