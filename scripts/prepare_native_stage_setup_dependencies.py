#!/usr/bin/env python3
"""Prepare source setup prop/guard model dependencies for the seven demos.

Setup object records store a direct ``obj`` model index for model-bearing
prop types.  Type 9 records are ``GuardRecord`` values: their model index is
the high half of the ``bodyAI`` word at record offset ``0x08``; the high half
of the preceding word is ``chrnum`` and is not a model index.  This helper
recovers those indices from the checked-in source include order, verifies the
corresponding external-ROM file-list rows, and copies only guarded model
payloads beneath ignored ``build/native`` output.  It does not claim a draw
lowerer; props/characters remain fail-closed until the runtime consumes this
manifest.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import struct
import subprocess
import sys
from pathlib import Path

ROM_SHA1 = "abe01e4aeb033b6c0836819f549c791b26cfde83"
PROP_MODEL_TYPES = {
    1, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 17, 20, 21, 36, 39, 40, 41, 42, 43, 45, 47,
}
OBJECT_SIZES = {
    0: 1, 1: 64, 2: 2, 3: 32, 4: 33, 5: 32, 6: 59, 7: 33, 8: 34, 9: 7,
    10: 64, 11: 149, 12: 32, 13: 54, 14: 3, 15: 1, 16: 1, 17: 32,
    18: 3, 19: 4, 20: 45, 21: 34, 22: 4, 23: 4, 24: 1, 25: 2, 26: 2,
    27: 2, 28: 2, 29: 2, 30: 4, 31: 1, 32: 4, 33: 5, 34: 4, 35: 4,
    36: 32, 37: 10, 38: 4, 39: 44, 40: 45, 41: 1, 42: 32, 43: 1,
    44: 1, 45: 56, 46: 7, 47: 37,
}


class PreparationError(RuntimeError):
    pass


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_be32(data: bytes, offset: int) -> int:
    if offset < 0 or offset + 4 > len(data):
        raise PreparationError(f"setup word at 0x{offset:x} exceeds payload")
    return struct.unpack_from(">I", data, offset)[0]


def parse_include_names(path: Path, pattern: str) -> list[str]:
    names = re.findall(pattern, path.read_text(encoding="utf-8"))
    if not names:
        raise PreparationError(f"model include table is empty: {path}")
    return names


def read_filelist(root: Path) -> dict[str, str]:
    return {
        line.split(",", 2)[2].split(",", 1)[0]: line
        for line in (root / "scripts/filelist.u.csv").read_text(encoding="utf-8").splitlines()
        if line.strip() and len(line.split(",")) >= 5
    }


def stage_setup_paths(stage_root: Path) -> dict[str, Path]:
    manifest = stage_root / "stage-assets-manifest.txt"
    if not manifest.is_file():
        raise PreparationError(f"stage manifest is missing: {manifest}")
    paths: dict[str, Path] = {}
    for line in manifest.read_text(encoding="utf-8").splitlines():
        if not re.match(r"resource_\d+=", line):
            continue
        fields = line.split("=", 1)[1].split("|")
        if len(fields) != 9 or fields[1] != "setup":
            continue
        stage, name = fields[0], fields[2]
        path = stage_root / "setup" / f"{stage.replace(' ', '_')}__setup__{name}.bin"
        if not path.is_file():
            raise PreparationError(f"prepared setup payload is missing: {path}")
        paths[stage] = path
    expected = {"Dam", "Facility", "Runway", "Bunker I", "Silo", "Frigate", "Train"}
    if set(paths) != expected:
        raise PreparationError(f"setup stage set mismatch: {sorted(paths)}")
    return paths


def object_dependencies(stage: str, data: bytes, props: int, chrs: int) -> list[dict[str, int | str]]:
    offsets = [read_be32(data, index * 4) for index in range(10)]
    start = offsets[3]
    if start == 0:
        return []
    ends = [value for value in offsets if value > start]
    end = min(ends) if ends else len(data)
    offset = start
    result: list[dict[str, int | str]] = []
    while offset + 4 <= end:
        first = read_be32(data, offset)
        object_type = first & 0xff
        if object_type == 48:
            break
        size_words = OBJECT_SIZES.get(object_type)
        if size_words is None:
            raise PreparationError(f"{stage} setup object type {object_type} has no bounded size")
        byte_count = size_words * 4
        if offset + byte_count > end:
            raise PreparationError(f"{stage} setup object at 0x{offset:x} is truncated")
        second = read_be32(data, offset + 4) if size_words > 1 else 0
        if object_type in PROP_MODEL_TYPES:
            model_index = (second >> 16) & 0xffff
            if model_index >= props:
                raise PreparationError(f"{stage} prop model index {model_index} >= {props}")
            result.append({
                "stage": stage, "kind": "prop", "object_index": len(result),
                "object_type": object_type, "model_index": model_index,
                "setup_offset": offset, "record_bytes": byte_count,
            })
        elif object_type == 9:
            # GuardRecord layout (src/bondtypes.h:3170-3189): word 1 is
            # chrnum/pad, while word 2 is bodyID/AIListID.  The existing
            # object summary intentionally keeps key0=chrnum for generic
            # object semantics; dependency preparation must use the source
            # bodyID instead.
            body_ai = read_be32(data, offset + 8)
            model_index = (body_ai >> 16) & 0xffff
            if model_index >= chrs:
                raise PreparationError(f"{stage} character model index {model_index} >= {chrs}")
            result.append({
                "stage": stage, "kind": "character", "object_index": len(result),
                "object_type": object_type, "model_index": model_index,
                "setup_offset": offset, "record_bytes": byte_count,
            })
        offset += byte_count
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--rom", type=Path, required=True)
    parser.add_argument("--stage-asset-root", type=Path, required=True)
    args = parser.parse_args()
    root = args.project_root.resolve()
    stage_root = args.stage_asset_root.resolve()
    rom = args.rom.resolve()
    if not rom.is_file() or rom.stat().st_size != 12_582_912 or hashlib.sha1(rom.read_bytes()).hexdigest() != ROM_SHA1:
        raise PreparationError("external ROM size/SHA-1 guard failed")
    prop_names = parse_include_names(
        root / "assets/obseg/prop/propItemModelFileRecord.inc.c",
        r"assets/obseg/prop/([^/]+)/propFileRecord\.inc\.c",
    )
    chr_names = parse_include_names(
        root / "assets/obseg/chr/chrModelFileRecords.inc.c",
        r"assets/obseg/chr/([^/]+)/chrModelFileRecord\.inc\.c",
    )
    rows = read_filelist(root)
    setup_paths = stage_setup_paths(stage_root)
    dependencies: list[dict[str, int | str]] = []
    for stage, path in setup_paths.items():
        dependencies.extend(object_dependencies(stage, path.read_bytes(), len(prop_names), len(chr_names)))
    output = stage_root / "setup-dependencies"
    (output / "prop").mkdir(parents=True, exist_ok=True)
    (output / "character").mkdir(parents=True, exist_ok=True)
    inflater = root / "tools/1172inflate.sh"
    manifest_lines = [
        "manifest_version=1",
        "asset_family=ramrom_stage_setup_model_dependencies",
        f"external_rom_sha1={ROM_SHA1}",
        f"prop_model_table_count={len(prop_names)}",
        f"character_model_table_count={len(chr_names)}",
        f"dependency_count={len(dependencies)}",
        "runtime_opens_rom=false",
        "runtime_consumes_prepared_payloads_only=true",
    ]
    seen: set[tuple[str, int]] = set()
    with rom.open("rb") as stream:
        for index, dependency in enumerate(dependencies):
            kind = str(dependency["kind"])
            model_index = int(dependency["model_index"])
            key = (kind, model_index)
            names = prop_names if kind == "prop" else chr_names
            name = names[model_index]
            prefix = "P" if kind == "prop" else "C"
            source_path = f"assets/obseg/{'prop' if kind == 'prop' else 'chr'}/{name}/Model.c"
            row_path = f"assets/obseg/{'prop' if kind == 'prop' else 'chr'}/{prefix}{name}Z.bin"
            row = rows.get(row_path)
            if row is None:
                raise PreparationError(f"missing file-list model row: {row_path}")
            fields = row.split(",")
            offset, size, compressed = int(fields[0]), int(fields[1]), int(fields[3])
            stream.seek(offset)
            raw = stream.read(size)
            if len(raw) != size:
                raise PreparationError(f"model row is truncated: {row_path}")
            safe = f"{kind}_{model_index:03d}_{name}"
            raw_path = output / kind / f"{safe}.rz" if compressed else output / kind / f"{safe}.bin"
            raw_path.write_bytes(raw)
            decoded_path = output / kind / f"{safe}.bin"
            if compressed:
                subprocess.run(
                    [str(inflater), str(raw_path), str(decoded_path)],
                    cwd=str(root), env={**os.environ, "GZ": "gzip"},
                    check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                )
            else:
                decoded_path = raw_path
            manifest_lines.append(
                "dependency_{}=".format(index)
                + "|".join((
                    f"stage:{dependency['stage']}", f"kind:{kind}",
                    f"object_index:{dependency['object_index']}",
                    f"object_type:{dependency['object_type']}",
                    f"setup_offset:{dependency['setup_offset']}",
                    f"model_index:{model_index}", f"model_name:{name}",
                    f"source_path:{source_path}", f"rom_row:{row_path}",
                    f"rom_offset:{offset}", f"rom_bytes:{size}",
                    f"compressed:{compressed}", f"source_sha256:{sha256(raw)}",
                    f"decoded_bytes:{decoded_path.stat().st_size}",
                    f"decoded_sha256:{sha256(decoded_path.read_bytes())}",
                    f"raw_file:{raw_path.relative_to(stage_root).as_posix()}",
                    f"decoded_file:{decoded_path.relative_to(stage_root).as_posix()}",
                ))
            )
            seen.add(key)
    manifest_lines += [
        f"unique_dependency_count={len(seen)}",
        "source_setup_status=PASS",
        "payload_status=PASS",
        "manifest_status=PASS",
    ]
    manifest = stage_root / "stage-setup-model-dependencies-manifest.txt"
    manifest.write_text("\n".join(manifest_lines) + "\n", encoding="utf-8")
    print(f"Native stage setup dependency preparation: PASS references={len(dependencies)} unique={len(seen)}")
    print(f"Manifest: {manifest}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PreparationError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
