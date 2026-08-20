#!/usr/bin/env python3
"""Verify the source-authored title raster/combiner vector.

This audit reads only tracked generated source.  It does not open the ROM and
does not inspect or rewrite GETP/V1--V4 artifacts.  Model.c uses direct
SETOTHERMODE/SETCOMBINE words; Rareware's display list uses the equivalent
named GBI macros, whose fixed wire values are recorded below.
"""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODEL_SOURCES = {
    "legalpage": ROOT / "assets/obseg/prop/legalpage/Model.c",
    "nintendologo": ROOT / "assets/obseg/prop/nintendologo/Model.c",
    "goldeneyelogo": ROOT / "assets/obseg/prop/goldeneyelogo/Model.c",
    "walletbond": ROOT / "assets/obseg/prop/walletbond/Model.c",
}
RAREWARE_SOURCE = ROOT / "assets/rarewarelogo.c"

SOURCE_MASK = {
    "legalpage": 1 << 0,
    "nintendologo": 1 << 1,
    "goldeneyelogo": 1 << 2,
    "walletbond": 1 << 3,
    "rareware": 1 << 4,
}


def model_tuples(path: Path) -> set[tuple[int, int, int, int]]:
    current_h = current_l = None
    tuples: set[tuple[int, int, int, int]] = set()
    for line in path.read_text().splitlines():
        match = re.search(
            r"gsSPSetOtherMode\(G_SETOTHERMODE_H,\s*20,\s*2,\s*0x([0-9A-Fa-f]+)",
            line,
        )
        if match:
            current_h = int(match.group(1), 16)
        match = re.search(
            r"gsSPSetOtherMode\(G_SETOTHERMODE_L,\s*3,\s*29,\s*0x([0-9A-Fa-f]+)",
            line,
        )
        if match:
            current_l = int(match.group(1), 16)
        match = re.search(
            r"gsDPSetCombine\(0x([0-9A-Fa-f]+),\s*0x([0-9A-Fa-f]+)",
            line,
        )
        if match:
            if current_h is None or current_l is None:
                raise SystemExit(f"combine before other-mode setup: {path}")
            tuples.add(
                (current_h, current_l, int(match.group(1), 16), int(match.group(2), 16))
            )
    return tuples


MODEL_EXPECTED = {
    "legalpage": {
        (0x00000000, 0x00502048, 0x00121824, 0xFF33FFFF),
        (0x00000000, 0x00502048, 0x00127E24, 0xFFFFF9FC),
        (0x00000000, 0x00502048, 0x00FFFFFF, 0xFFFE793C),
    },
    "nintendologo": {
        (0x00000000, 0x00502048, 0x00127E24, 0xFFFFF9FC),
        (0x00000000, 0x00502048, 0x00FFFFFF, 0xFFFE793C),
    },
    "goldeneyelogo": {
        (0x00100000, 0x0C182048, 0x0026A004, 0x1F1093FF),
    },
    "walletbond": {
        (0x00000000, 0x00502048, 0x00127E24, 0xFFFFF9FC),
        (0x00000000, 0x00502048, 0x00FFFFFF, 0xFFFE793C),
        (0x00100000, 0x0C182048, 0x0026A004, 0x1FFC93FC),
        (0x00100000, 0x0C184340, 0x0026A004, 0x1F1093FF),
    },
}

RAREWARE_EXPECTED = {
    # G_RM_AA_OPA_SURF | G_RM_AA_OPA_SURF2 and the first SETCOMBINE LERP.
    (0x00000000, 0x00552048, 0x00119623, 0x002C0000),
    # G_RM_PASS | G_RM_OPA_SURF2 and the LOD/primitive two-cycle LERP.
    (0x00100000, 0x0F0A4000, 0x00169A03, 0x100C9200),
}


def main() -> int:
    all_tuples: set[tuple[int, int, int, int]] = set()
    for name, path in MODEL_SOURCES.items():
        actual = model_tuples(path)
        if actual != MODEL_EXPECTED[name]:
            raise SystemExit(
                f"{name}: source tuple drift\n"
                f"  missing={sorted(MODEL_EXPECTED[name] - actual)}\n"
                f"  unexpected={sorted(actual - MODEL_EXPECTED[name])}"
            )
        all_tuples |= actual

    rareware = RAREWARE_SOURCE.read_text()
    required_markers = (
        "gsDPSetRenderMode(G_RM_AA_OPA_SURF, G_RM_AA_OPA_SURF2)",
        "gsDPSetCombineLERP(TEXEL0, 0, PRIMITIVE, 0",
        "gsDPSetCycleType(G_CYC_2CYCLE)",
        "gsDPSetCombineLERP(TEXEL0, TEXEL0, LOD_FRACTION, TEXEL0",
        "gsDPSetRenderMode(G_RM_PASS, G_RM_OPA_SURF2)",
    )
    for marker in required_markers:
        if marker not in rareware:
            raise SystemExit(f"Rareware source marker missing: {marker}")
    all_tuples |= RAREWARE_EXPECTED

    print(
        "title-raster-source-audit: PASS "
        f"models={len(MODEL_SOURCES)} rareware=1 uniqueTuples={len(all_tuples)}"
    )
    for name, expected in MODEL_EXPECTED.items():
        print(f"  {name}: uniqueTuples={len(expected)} sourceMask=0x{SOURCE_MASK[name]:x}")
    print(f"  rareware: uniqueTuples={len(RAREWARE_EXPECTED)} sourceMask=0x{SOURCE_MASK['rareware']:x}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
