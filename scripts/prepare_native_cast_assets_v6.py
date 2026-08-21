#!/usr/bin/env python3
"""Prepare the source-derived cast roster into a private GEFV/GESM root.

This driver reuses the guarded frontend preparer but gives it the complete
character and attract-weapon source set. The output is separate from the
frozen title/frontend packet so existing V1-V5 and title evidence remain
unchanged. The ROM is opened only by preparation and must remain external.
"""

from __future__ import annotations

import argparse
import importlib.util
import sys
from pathlib import Path
from types import ModuleType


def load_preparer(root: Path) -> ModuleType:
    path = root / "scripts/prepare_native_source_frontend_v6.py"
    spec = importlib.util.spec_from_file_location("goldeneye_source_frontend_v6", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load preparer: {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def filelist_lookup(root: Path) -> dict[str, str]:
    rows: dict[str, str] = {}
    for line in (root / "scripts/filelist.u.csv").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        fields = line.split(",")
        if len(fields) != 5:
            continue
        rows[fields[2]] = line
    return rows


def make_specs(root: Path, module: ModuleType) -> tuple[dict[str, str], tuple[dict[str, object], ...]]:
    row_by_path = filelist_lookup(root)
    specs: list[dict[str, object]] = []
    rows = dict(module.ROM_ROWS)
    handle = 0x100

    # Every character source packet is retained. This covers the source cast
    # table, fixed heads, deterministic random-head candidates, and the
    # alternate Bond/guard clothing selected by init_menu18_displaycast.
    # Exact body enum -> checked-in source directory mapping used by
    # c_item_entries.  Keep only the 30 intro rows plus the random/fixed head
    # candidates they can reach; unrelated MP-only/unused assets are not part
    # of the cast route and would add unexercised preparation failures.
    body_dirs = {
        "djbond", "boilerbond", "natalya", "spicebond", "boilertrev", "xenia", "orumov",
        "boris", "valentin", "greatguard", "oliveguard", "rusguard", "techman",
        "techwoman", "commguard", "armourguard", "navyguard", "snowguard", "pilot", "greyguard",
        "jeanwoman", "greyman", "blueman", "redman", "cardiman", "bluecamguard",
        "moonguard", "moonfemale", "mayday", "jaws", "oddjob", "baronsamedi",
    }
    head_dirs = {
        "headkarl", "headalan", "headpete", "headmartin", "headmark", "headduncan",
        "headshaun", "headdwayne", "headb", "headdave", "headgrant", "headdes",
        "headchris", "headlee", "headneil", "headjim", "headrobin", "headsteveh",
        "headjoel", "headscott", "headjoe", "headken", "headjoe2", "headstevee",
        "headgraham", "headsally", "headmarion", "headmandy", "headvivien",
        "headmishkin", "headbrosnanboiler", "headbrosnansuit", "headbrosnan",
    }
    character_dirs = sorted(body_dirs | head_dirs)
    for name in character_dirs:
        relative = f"assets/obseg/chr/{name}/Model.c"
        rom_path = f"assets/obseg/chr/C{name}Z.bin"
        row = row_by_path.get(rom_path)
        if row is None:
            raise RuntimeError(f"missing guarded file-list row: {rom_path}")
        rows[f"cast_{name}"] = row
        specs.append({
            "family": f"cast_{name}",
            "name": name,
            "path": relative,
            "rom": f"cast_{name}",
            "handle": handle,
        })
        handle += 1

    # Source intro weapon pools. Keep every unique prop model even when a
    # production save gate later replaces a weapon with PP7.
    weapon_names = [
        "chrwppk", "chrwppksil", "chrskorpion", "chruzi", "chrtt33",
        "chrruger", "chrlaser", "chrgolden", "chrkalash", "chrm16", "chrfnp90",
        "chrautoshot", "chrgrenadelaunch", "chrsniperrifle",
    ]
    for name in weapon_names:
        relative = f"assets/obseg/prop/{name}/Model.c"
        if not (root / relative).is_file():
            raise RuntimeError(f"missing source weapon listing: {relative}")
        rom_path = f"assets/obseg/prop/P{name}Z.bin"
        row = row_by_path.get(rom_path)
        if row is None:
            raise RuntimeError(f"missing guarded file-list row: {rom_path}")
        rows[f"cast_{name}"] = row
        specs.append({
            "family": f"cast_{name}",
            "name": name,
            "path": relative,
            "rom": f"cast_{name}",
            "handle": handle,
        })
        handle += 1
    return rows, tuple(specs)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--rom", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    args = parser.parse_args()
    root = args.project_root.resolve()
    module = load_preparer(root)
    rows, specs = make_specs(root, module)
    module.ROM_ROWS = rows
    module.MODEL_SPECS = specs
    prep_args = argparse.Namespace(
        project_root=root,
        rom=args.rom.resolve(),
        output_root=args.output_root.resolve(),
        verify=False,
        verify_sidecar=None,
    )
    packet, manifest = module.prepare(prep_args)
    print(f"cast_packet={packet}")
    print(f"cast_packet_sha256={manifest['packet_sha256']}")
    print(f"cast_sidecars={len(manifest['sidecars'])}")
    print(f"cast_models={len(specs)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
