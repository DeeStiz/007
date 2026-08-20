#!/usr/bin/env python3
"""Pure parser fixtures for the additive source-frontend V6 preparation lane."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/prepare_native_source_frontend_v6.py"
spec = importlib.util.spec_from_file_location("prepare_native_source_frontend_v6", SCRIPT)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)


def main() -> None:
    fixture = (Path(__file__).with_name("minimal_model.c")).read_bytes()
    parsed = module.parse_model_listing(fixture, "fixture")
    assert parsed["node_count"] == 2
    assert parsed["display_list_count"] == 1
    assert parsed["vertex_total"] == 3
    assert parsed["texture_count"] == 1
    assert parsed["textures"][0]["mip_tiles"] == 2
    assert parsed["image_tokens"] == []
    assert parsed["switch_nodes"] == 0
    # Null pointer spellings are canonicalized before any generic numeric
    # handling.  Non-null casts remain typed deterministic handles.
    assert module._canonicalize_token("fixture", "(void*)0x00000000") == "@null"
    assert module._canonicalize_token("fixture", "(void *)0") == "@null"
    assert module._canonicalize_token("fixture", "(void*)(0x00000000)") == "@null"
    assert module._canonicalize_token("fixture", "(void*)0x00000123").startswith("@address:")
    print("source frontend V6 parser fixture: PASS")


if __name__ == "__main__":
    main()
