#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
TEX2PNG="${GOLDENEYE_TEX2PNG:-${ROOT}/tools/mktex/build/tex2png}"
[[ -x "${TEX2PNG}" ]] || {
    echo "corrected tex2png is missing: ${TEX2PNG}" >&2
    exit 1
}

python3 - "${ROOT}" "${TEX2PNG}" <<'PY'
from __future__ import annotations
import hashlib
import subprocess
import sys
import tempfile
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]) / "scripts"))
from prepare_native_title_icons import decode_png

root = Path(sys.argv[1])
tex2png = sys.argv[2]
rows = ["FOLDERTEX", "PAPERTEX", "MI6", "MI6_UL", "MI6_UR", "MI6_LL", "MI6_LR"]
with tempfile.TemporaryDirectory(prefix="goldeneye-pd-decoder-") as temp:
    temp_root = Path(temp)
    for name in rows:
        source = root / "assets/images/split" / f"{name}.bin"
        if not source.is_file():
            raise SystemExit(f"missing source row {source}")
        no_flip_dir = temp_root / f"{name}-source"
        inspection_dir = temp_root / f"{name}-inspection"
        no_flip_dir.mkdir(); inspection_dir.mkdir()
        subprocess.run([tex2png, str(source), str(no_flip_dir), "--no-flip"], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        subprocess.run([tex2png, str(source), str(inspection_dir)], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        source_png = no_flip_dir / f"{name}-0.png"
        inspection_png = inspection_dir / f"{name}-0.png"
        width, height, source_pixels = decode_png(source_png.read_bytes())
        iw, ih, inspection_pixels = decode_png(inspection_png.read_bytes())
        if (width, height) != (iw, ih):
            raise SystemExit(f"dimension mismatch for {name}")
        if not any(source_pixels[index] or source_pixels[index + 1] or source_pixels[index + 2] for index in range(0, len(source_pixels), 4)):
            raise SystemExit(f"corrected decoder still has no RGB payload for {name}")
        row_bytes = width * 4
        flipped = b"".join(source_pixels[row * row_bytes:(row + 1) * row_bytes] for row in range(height - 1, -1, -1))
        if hashlib.sha256(flipped).hexdigest() != hashlib.sha256(inspection_pixels).hexdigest():
            raise SystemExit(f"flip contract mismatch for {name}")
        print(f"row={name} dimensions={width}x{height} sourceRGB=1 sourceSHA256={hashlib.sha256(source_pixels).hexdigest()} inspectionSHA256={hashlib.sha256(inspection_pixels).hexdigest()}")
print("native_pd_texture_decoder: PASS rows=7 flip=explicit source=unflipped inspection=vertical_flip")
PY
