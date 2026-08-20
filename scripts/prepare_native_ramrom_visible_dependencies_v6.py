#!/usr/bin/env python3
"""Prepare source-selected non-room dependencies for the RAMROM demos.

This preparation pass follows the source tables that feed the seven stages
used by the fourteen RAMROM recordings.  It copies only bounded model, held
weapon, image, animation, font, music, and sound-bank rows beneath ignored
``build/native`` output.  The external ROM is an input to this command only;
the generated manifest contains file-list ranges and digests, never a ROM
path or address that a runtime may open.

The existing stage background/room and setup sidecars are inputs to the trace,
not replaced by this script.  Setup references select props and character
bodies; the source character table selects all head records because guard
head selection is source-randomized; the source gun table supplies the held
weapon/prop pool used by the recording headers and gameplay branches.  Room
texture rows are taken from the already verified ``texLoadFromGdl`` sidecar.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable


ROM_SHA1 = "abe01e4aeb033b6c0836819f549c791b26cfde83"
ROM_BYTES = 12_582_912
REFERENCE_COMMAND = "make -j8 IDO_RECOMP=NO VERSION=US COMPARE=1 VERBOSE=1"
REFERENCE_HASH_COMMAND = "sha1sum -c ge007.u.sha1"
STAGES = ("Dam", "Facility", "Runway", "Bunker I", "Silo", "Frigate", "Train")
STAGE_IDS = {"Bunker I": 9, "Silo": 20, "Train": 25, "Frigate": 26,
             "Dam": 33, "Facility": 34, "Runway": 35}
DEMO_FILES = (
    "ramrom_Dam_1.bin", "ramrom_Dam_2.bin",
    "ramrom_Facility_1.bin", "ramrom_Facility_2.bin", "ramrom_Facility_3.bin",
    "ramrom_Runway_1.bin", "ramrom_Runway_2.bin",
    "ramrom_BunkerI_1.bin", "ramrom_BunkerI_2.bin",
    "ramrom_Silo_1.bin", "ramrom_Silo_2.bin",
    "ramrom_Frigate_1.bin", "ramrom_Frigate_2.bin", "ramrom_Train.bin",
)

# These are the source producers whose ordering and table meanings are part
# of the preparation contract.  A changed producer must be reviewed before a
# new private payload is accepted.
SOURCE_HASH_GUARDS = {
    "src/game/ramromreplay.c": "93d5d40633c9b9d71bdaf7bb0e36a3319e1865bc44b3e9b5bec6897cdf2ccffd",
    "src/game/prop.c": "b739665d313ecf61687a65dc840a13414d0c4941f172e299e1dd33fe87122c7b",
    "src/game/chr.c": "d92a2770348ec2f8bff7216467556bd8b80648d602e7388d75d610814e4060b4",
    "src/game/gun.c": "a4d4310941ae5794703068960f8561ca0230d25184aa7f1fd299210774c8de9c",
    "src/game/gunfire.c": "801b77b16bb9ad96c8b8d694f567e30d063476d998aa8774c025471b4c7c357a",
    "src/game/explosion.c": "5a82a40fad1d38c6a74f77a5ab9a2f65f11c273afdac58015984623513fc394a",
    "src/game/sky.c": "43444f877722dd0254a2c29dddab68a7a2636f7b1ee6375bbd9d65b8bee20a07",
    "src/game/bg.c": "b7207454d5ffb1c0ae45b267949d691a519bb28325f083f825108103ff7d042a",
    "src/game/mp_weapon.c": "36484545e93faf33a1fa55b78877e168b0e58ea518cd93a4374d002d886ca1a6",
    "src/game/bondview2.c": "ca0563015f88e238f8732580e6e2ccbd413c29b8c93d8ba4f8940eb6ade0d543",
    "assets/obseg/file_resource_table.inc.c": "0991f97aacc48ac51e9fbd5f6c7967b767b99bae9f2f57ed44e0867d2b1eb064",
    "assets/obseg/chr/chrModelFileRecords.inc.c": "d7137fd2151ab8964cc21c51d6a58dfbb797226d2a92171e8d12c90732539af9",
    "assets/obseg/Makefile.filelist": "76fc88bec7cb1802afbe9ad146bc4b5ab9c6435c29030a4be41df83937341261",
    "assets/images.def": "01fde9bf2934b82460eaefc55ed7e8c2d706290489eeef8b3f9bbb243973ea09",
    "imagelist.u.csv": "0192d653c34d459ad98a5e671dbccaf97277a536824a5414c7e0ba80a4aba8ff",
    "scripts/filelist.u.csv": "b33fae98f0f72745171eae666638477cd730118c228211310db3ba32ad96834f",
    "scripts/prepare_native_stage_texture_assets.py": "53b021fdf0801ede184bb49e3843db64655341f067a1a33edac45fd6653985c2",
    "scripts/prepare_native_title_icons.py": "e565ec2d38c4bacdb5a3f8b7b3144f390990041f0fab1b112def16904ad7e57e",
    "scripts/prepare_native_source_frontend_v6.py": "2d6472a7131ccf42238edbc1a55ad7d63cfdb19e1fe09562bc68c16f745445c5",
    "tools/1172inflate.sh": "947b82bd3aeabb3155d34aa5ffb6df13c400e871d8c0bf72c5e6ef3a3bd6e389",
}


class PreparationError(RuntimeError):
    pass


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def require_file(path: Path, label: str | None = None) -> None:
    if not path.is_file():
        raise PreparationError(f"required {label or 'file'} is missing: {path}")


def safe(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", value).strip("_") or "asset"


def verify_output(root: Path, output: Path) -> None:
    allowed = (root / "build/native").resolve()
    resolved = output.resolve()
    if resolved == root.resolve() or allowed not in resolved.parents:
        raise PreparationError(f"output must remain below build/native: {resolved}")
    try:
        subprocess.run(["git", "-C", str(root), "check-ignore", "-q", str(resolved)], check=True)
    except (OSError, subprocess.CalledProcessError) as error:
        raise PreparationError(f"output is not ignored: {resolved}") from error


def verify_rom(root: Path, path: Path) -> Path:
    if not path.is_absolute():
        raise PreparationError("external ROM path must be absolute")
    require_file(path, "external ROM")
    rom = path.resolve()
    project = root.resolve()
    if rom == project or project in rom.parents:
        raise PreparationError("the ROM must remain outside the checkout")
    if rom.stat().st_size != ROM_BYTES:
        raise PreparationError(f"external ROM size mismatch: {rom.stat().st_size}")
    digest = hashlib.sha1(rom.read_bytes()).hexdigest()
    if digest != ROM_SHA1:
        raise PreparationError(f"external ROM SHA-1 mismatch: {digest}")
    evidence = root / ".porting/m0-provenance.md"
    require_file(evidence, "Linux provenance evidence")
    text = evidence.read_text(encoding="utf-8")
    for required in (REFERENCE_COMMAND, REFERENCE_HASH_COMMAND, ROM_SHA1):
        if required not in text:
            raise PreparationError(f"Linux provenance evidence is missing: {required}")
    return rom


def verify_source_guards(root: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for relative, expected in SOURCE_HASH_GUARDS.items():
        path = root / relative
        require_file(path, relative)
        actual = sha256(path.read_bytes())
        if actual != expected:
            raise PreparationError(f"source hash mismatch for {relative}: {actual}")
        result[relative] = actual
    return result


@dataclass(frozen=True)
class FileRow:
    offset: int
    bytes: int
    path: str
    compressed: bool
    line: str


def parse_filelist(root: Path) -> dict[str, FileRow]:
    rows: dict[str, FileRow] = {}
    for line in (root / "scripts/filelist.u.csv").read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        fields = line.split(",")
        if len(fields) < 5:
            raise PreparationError(f"malformed file-list row: {line}")
        try:
            offset, count, compressed = int(fields[0]), int(fields[1]), int(fields[3])
        except ValueError as error:
            raise PreparationError(f"invalid file-list range: {line}") from error
        # A few source linker sentinels intentionally carry a zero-byte row;
        # retain them in the table while rejecting negative ranges.  No
        # visible dependency is allowed to select one of those rows.
        if offset < 0 or count < 0 or compressed not in (0, 1):
            raise PreparationError(f"invalid file-list values: {line}")
        path = fields[2]
        if path in rows:
            raise PreparationError(f"duplicate file-list path: {path}")
        rows[path] = FileRow(offset, count, path, bool(compressed), line)
    return rows


def parse_named_table(text: str, start: str, end: str) -> list[str]:
    match = re.search(rf"{start}\s*=\s*(.*?)(?=\n{end}\s*=)", text, re.S)
    if not match:
        raise PreparationError(f"source table {start} is missing")
    names = re.findall(r"(?m)^\s*([A-Za-z0-9_]+)\s*\\?$", match.group(1))
    if not names:
        raise PreparationError(f"source table {start} is empty")
    return names


def parse_chr_table(root: Path) -> list[str]:
    path = root / "assets/obseg/chr/chrModelFileRecords.inc.c"
    names = re.findall(r"assets/obseg/chr/([^/]+)/chrModelFileRecord\.inc\.c", path.read_text())
    if not names:
        raise PreparationError("character source table is empty")
    return names


@dataclass(frozen=True)
class Route:
    demo_id: int
    stage: str
    stage_id: int
    variant: int
    controller_count: int
    total_time_ms: int
    declared_bytes: int
    asset_bytes: int
    packet_count: int
    record_count: int
    recording_sha256: str
    source_path: str


def parse_ramrom_file(path: Path, demo_id: int) -> Route:
    data = path.read_bytes()
    if len(data) < 236:
        raise PreparationError(f"RAMROM recording is truncated: {path.name}")
    stage_id = struct.unpack_from(">I", data, 0x10)[0]
    controllers = struct.unpack_from(">I", data, 0x18)[0]
    total_time, declared = struct.unpack_from(">II", data, 0x7C)
    if declared < 236 or declared > len(data) or any(data[declared:]):
        raise PreparationError(f"RAMROM declared boundary is invalid: {path.name}")
    expected_stage = next((stage for stage, value in STAGE_IDS.items() if value == stage_id), None)
    if expected_stage is None or controllers == 0 or controllers > 4:
        raise PreparationError(f"RAMROM header stage/controller is invalid: {path.name}")
    stem = path.stem.removeprefix("ramrom_")
    if "_" in stem:
        stage_token, variant_text = stem.rsplit("_", 1)
        variant = int(variant_text)
    else:
        stage_token, variant = stem, 1
    stage = "Bunker I" if stage_token == "BunkerI" else stage_token
    if stage != expected_stage:
        raise PreparationError(f"RAMROM stage name/header mismatch: {path.name}")
    offset, packets, records = 232, 0, 0
    while offset + 4 <= declared:
        speed, count, _rng, checksum = data[offset:offset + 4]
        if speed == count == _rng == checksum == 0:
            if offset + 4 != declared:
                raise PreparationError(f"RAMROM terminal packet is not final: {path.name}")
            break
        if speed == 0 or count == 0:
            raise PreparationError(f"RAMROM packet has invalid speed/count: {path.name}")
        payload_bytes = count * controllers * 4
        end = offset + 4 + payload_bytes
        if end > declared:
            raise PreparationError(f"RAMROM packet exceeds declared boundary: {path.name}")
        computed = (speed + count + _rng + sum(data[offset + 4:end])) & 0xFF
        if computed != checksum:
            raise PreparationError(f"RAMROM packet checksum mismatch: {path.name}")
        packets += 1
        records += count
        offset = end
    else:
        raise PreparationError(f"RAMROM terminal packet is missing: {path.name}")
    return Route(
        demo_id=demo_id, stage=stage, stage_id=stage_id, variant=variant,
        controller_count=controllers, total_time_ms=total_time,
        declared_bytes=declared, asset_bytes=len(data), packet_count=packets,
        record_count=records, recording_sha256=sha256(data), source_path=str(path),
    )


def parse_routes(root: Path) -> list[Route]:
    routes = []
    ramrom_root = root / "assets/ramrom"
    for index, name in enumerate(DEMO_FILES, 1):
        path = ramrom_root / name
        require_file(path, f"RAMROM source recording {name}")
        routes.append(parse_ramrom_file(path, index))
    return routes


def parse_dependency_manifest(stage_root: Path) -> list[dict[str, str]]:
    path = stage_root / "stage-setup-model-dependencies-manifest.txt"
    require_file(path, "stage setup dependency manifest")
    lines = path.read_text(encoding="utf-8").splitlines()
    values = dict(line.split("=", 1) for line in lines if "=" in line and not re.match(r"dependency_\d+=", line))
    if values.get("manifest_status") != "PASS" or values.get("runtime_opens_rom") != "false":
        raise PreparationError("stage setup dependency manifest failed its provenance guard")
    rows = []
    for line in lines:
        if not re.match(r"dependency_\d+=", line):
            continue
        _, payload = line.split("=", 1)
        fields = dict(field.split(":", 1) for field in payload.split("|") if ":" in field)
        required = ("stage", "kind", "object_index", "object_type", "setup_offset", "model_index",
                    "model_name", "source_path", "rom_row", "rom_offset", "rom_bytes", "compressed")
        if any(key not in fields for key in required):
            raise PreparationError(f"malformed stage setup dependency row: {line}")
        rows.append(fields)
    if not rows or {row["stage"] for row in rows} != set(STAGES):
        raise PreparationError("stage setup manifest does not cover all seven RAMROM stages")
    return rows


def parse_stage_texture_manifest(stage_root: Path) -> list[dict[str, object]]:
    path = stage_root / "stage-texture-dependencies-manifest.txt"
    require_file(path, "stage texture dependency manifest")
    rows: list[dict[str, object]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not re.match(r"image_\d+=", line):
            continue
        _, payload = line.split("=", 1)
        fields: dict[str, str] = {}
        for field_value in payload.split("|"):
            if ":" in field_value:
                key, value = field_value.split(":", 1)
                fields[key] = value
        needed = ("index", "name", "rom_offset", "rom_bytes", "source_sha256", "source_row", "raw_file", "levels", "tlut")
        if any(key not in fields for key in needed):
            raise PreparationError("stage texture image row is missing required fields")
        levels: list[dict[str, str]] = []
        for token in fields["levels"].split(";"):
            parts = token.split(":")
            if len(parts) != 8:
                raise PreparationError(f"malformed texture level metadata for {fields['name']}")
            level, width, height, count, source_digest, decoded_file, _inspection_digest, _inspection_file = parts
            levels.append({"level": level, "width": width, "height": height, "bytes": count,
                           "sha256": source_digest, "decoded_file": decoded_file})
        try:
            palette = json.loads(fields["tlut"])
        except json.JSONDecodeError as error:
            raise PreparationError(f"malformed TLUT metadata for {fields['name']}") from error
        rows.append({"fields": fields, "levels": levels, "palette": palette})
    if not rows:
        raise PreparationError("stage texture dependency manifest has no image rows")
    return rows


def parse_image_list(root: Path) -> dict[str, tuple[int, int, str]]:
    """Return the guarded global IMAGE row map used by stage texture traces."""
    result: dict[str, tuple[int, int, str]] = {}
    for line in (root / "imagelist.u.csv").read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        fields = line.split(",")
        if len(fields) != 5:
            raise PreparationError(f"malformed imagelist row: {line}")
        try:
            offset, count = int(fields[0]), int(fields[1])
        except ValueError as error:
            raise PreparationError(f"invalid imagelist range: {line}") from error
        result[fields[2]] = (offset, count, line)
    return result


@dataclass
class Dependency:
    category: str
    symbol: str
    source_path: str
    rom_row: str
    rom_offset: int | None
    source_bytes: int
    compressed: bool
    source_sha256: str
    decoded_bytes: int
    decoded_sha256: str
    raw_file: str
    decoded_file: str
    demo_ids: set[int] = field(default_factory=set)
    stages: set[str] = field(default_factory=set)
    fields: dict[str, str] = field(default_factory=dict)


class PayloadWriter:
    def __init__(self, root: Path, output: Path, rom: Path, rows: dict[str, FileRow]) -> None:
        self.root, self.output, self.rom, self.rows = root, output, rom, rows
        self.raw_root = output / "payload/raw"
        self.decoded_root = output / "payload/decoded"
        self.raw_root.mkdir(parents=True, exist_ok=True)
        self.decoded_root.mkdir(parents=True, exist_ok=True)
        self.inflater = root / "tools/1172inflate.sh"
        require_file(self.inflater, "1172 inflater")
        self.index = 0

    def file_row(self, path: str) -> FileRow:
        try:
            return self.rows[path]
        except KeyError as error:
            raise PreparationError(f"source row is absent from scripts/filelist.u.csv: {path}") from error

    def add_file(
        self, category: str, symbol: str, path: str, routes: Iterable[Route],
        stages: Iterable[str], fields: dict[str, str] | None = None,
    ) -> Dependency:
        row = self.file_row(path)
        payload_id = f"{self.index:05d}_{safe(category)}_{safe(symbol)}"
        raw_path = self.raw_root / f"{payload_id}.bin"
        decoded_path = self.decoded_root / f"{payload_id}.bin"
        with self.rom.open("rb") as stream:
            stream.seek(row.offset)
            raw = stream.read(row.bytes)
        if len(raw) != row.bytes:
            raise PreparationError(f"ROM row is truncated: {path}")
        raw_path.write_bytes(raw)
        if row.compressed:
            env = {**os.environ, "GZ": "gzip"}
            try:
                subprocess.run([str(self.inflater), str(raw_path), str(decoded_path)], cwd=str(self.root),
                               env=env, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            except (OSError, subprocess.CalledProcessError) as error:
                raise PreparationError(f"1172 decode failed: {path}") from error
        else:
            shutil.copyfile(raw_path, decoded_path)
        decoded = decoded_path.read_bytes()
        dependency = Dependency(
            category=category, symbol=symbol, source_path=fields.get("source_path", path) if fields else path,
            rom_row=path, rom_offset=row.offset, source_bytes=len(raw), compressed=row.compressed,
            source_sha256=sha256(raw), decoded_bytes=len(decoded), decoded_sha256=sha256(decoded),
            raw_file=raw_path.relative_to(self.output).as_posix(),
            decoded_file=decoded_path.relative_to(self.output).as_posix(),
            demo_ids={route.demo_id for route in routes}, stages=set(stages),
            fields={key: value for key, value in (fields or {}).items() if key != "source_path"},
        )
        self.index += 1
        return dependency

    def add_copy(
        self, category: str, symbol: str, source_path: str, raw_source: Path, decoded_source: Path,
        routes: Iterable[Route], stages: Iterable[str], fields: dict[str, str],
    ) -> Dependency:
        if not raw_source.is_file() or not decoded_source.is_file():
            raise PreparationError(f"prepared texture payload is missing for {symbol}")
        payload_id = f"{self.index:05d}_{safe(category)}_{safe(symbol)}"
        raw_path = self.raw_root / f"{payload_id}.bin"
        decoded_path = self.decoded_root / f"{payload_id}.bin"
        shutil.copyfile(raw_source, raw_path)
        shutil.copyfile(decoded_source, decoded_path)
        raw, decoded = raw_path.read_bytes(), decoded_path.read_bytes()
        self.index += 1
        return Dependency(
            category=category, symbol=symbol, source_path=source_path,
            rom_row=fields.get("source_row", "imagelist.u.csv"), rom_offset=int(fields["rom_offset"]),
            source_bytes=len(raw), compressed=False, source_sha256=sha256(raw), decoded_bytes=len(decoded),
            decoded_sha256=sha256(decoded), raw_file=raw_path.relative_to(self.output).as_posix(),
            decoded_file=decoded_path.relative_to(self.output).as_posix(),
            demo_ids={route.demo_id for route in routes}, stages=set(stages),
            fields={key: value for key, value in fields.items() if key not in ("source_row", "rom_offset")},
        )


def classify_prop(name: str) -> str:
    lower = name.lower()
    if any(token in lower for token in ("door", "gate", "hatch", "roller", "lock")):
        return "doors"
    if any(token in lower for token in ("glass", "window")):
        return "glass"
    if any(token in lower for token in ("explosion", "bomb", "flare", "smoke", "spark")):
        return "effects"
    return "props"


def classify_gun(name: str) -> str:
    lower = name.lower()
    if "watch" in lower:
        return "watch"
    if any(token in lower for token in ("grenade", "rocket", "mine", "dart", "flare", "taser", "knife", "laser", "bomb")):
        return "projectiles"
    return "weapons"


def classify_image(name: str) -> str:
    upper = name.upper()
    if "CLOUD" in upper:
        return "sky"
    if any(token in upper for token in ("GLASS", "WINDOW")):
        return "glass"
    if any(token in upper for token in ("SMOKE", "FIRE", "SPARK")):
        return "particles"
    if any(token in upper for token in ("IMPACT", "EXPLOSION", "BLOOD")):
        return "explosions"
    if any(token in upper for token in ("MONITOR", "CROSSHAIR", "AMMO", "GUNFRAME", "TARGET")):
        return "hud"
    if "WATCH" in upper:
        return "watch"
    return "textures"


def parse_stage_texture_copy(root: Path, stage_root: Path, writer: PayloadWriter,
                             routes: list[Route]) -> list[Dependency]:
    records = parse_stage_texture_manifest(stage_root)
    image_rows = parse_image_list(root)
    texture_root = stage_root / "textures"
    dependencies: list[Dependency] = []
    stages = STAGES
    for record in records:
        fields = record["fields"]  # type: ignore[assignment]
        levels = record["levels"]  # type: ignore[assignment]
        name = str(fields["name"])
        image_path = f"assets/images/split/image{fields['index']}.bin"
        image_row = image_rows.get(image_path)
        if image_row is None:
            raise PreparationError(f"stage image row is absent from imagelist.u.csv: {image_path}")
        if image_row[0] != int(fields["rom_offset"]) or image_row[1] != int(fields["rom_bytes"]):
            raise PreparationError(f"stage image range differs from imagelist row: {name}")
        if image_row[2] != fields["source_row"]:
            raise PreparationError(f"stage image source row differs from imagelist: {name}")
        category = classify_image(name)
        raw_source = texture_root / str(fields["raw_file"])
        decoded_source = texture_root / str(levels[0]["decoded_file"])
        if not raw_source.is_file() or sha256(raw_source.read_bytes()) != fields["source_sha256"]:
            raise PreparationError(f"stage image raw digest mismatch for {name}")
        for level in levels:
            level_path = texture_root / str(level["decoded_file"])
            if not level_path.is_file() or sha256(level_path.read_bytes()) != level["sha256"]:
                raise PreparationError(f"stage image decoded digest mismatch for {name} level {level['level']}")
        dependency = writer.add_copy(
            category, f"IMAGE_{fields['index']}_{name}", "assets/images.def",
            raw_source, decoded_source, routes, stages,
            {"index": fields["index"], "name": name, "rom_offset": fields["rom_offset"],
             "rom_bytes": fields["rom_bytes"], "source_row": fields["source_row"],
             "stream_format": fields.get("stream_format", "0"),
             "source_level_count": fields.get("source_level_count", "1")},
        )
        if dependency.source_sha256 != fields["source_sha256"]:
            raise PreparationError(f"stage image copied raw digest mismatch for {name}")
        payload_id = Path(dependency.raw_file).stem
        for level in levels:
            level_path = texture_root / str(level["decoded_file"])
            if int(level["level"]) == 0:
                copied_level = Path(dependency.decoded_file)
            else:
                copied_level = Path("payload/decoded") / f"{payload_id}.mip{level['level']}.bin"
                target = writer.output / copied_level
                shutil.copyfile(level_path, target)
            level_bytes = (writer.output / copied_level).read_bytes()
            dependency.fields[f"mip_{level['level']}_file"] = copied_level.as_posix()
            dependency.fields[f"mip_{level['level']}_bytes"] = str(len(level_bytes))
            dependency.fields[f"mip_{level['level']}_sha256"] = sha256(level_bytes)
        palette = record["palette"]
        if isinstance(palette, dict):
            raw_palette = texture_root / str(palette["raw_file"])
            decoded_palette = texture_root / str(palette["decoded_file"])
            if not raw_palette.is_file() or not decoded_palette.is_file():
                raise PreparationError(f"TLUT payload is missing for image {name}")
            if sha256(raw_palette.read_bytes()) != str(palette["raw_sha256"]):
                raise PreparationError(f"TLUT raw digest mismatch for image {name}")
            if sha256(decoded_palette.read_bytes()) != str(palette["decoded_sha256"]):
                raise PreparationError(f"TLUT decoded digest mismatch for image {name}")
            copied_raw_palette = Path("payload/raw") / f"{payload_id}.tlut.bin"
            copied_decoded_palette = Path("payload/decoded") / f"{payload_id}.tlut.bin"
            shutil.copyfile(raw_palette, writer.output / copied_raw_palette)
            shutil.copyfile(decoded_palette, writer.output / copied_decoded_palette)
            dependency.fields.update({
                "tlut_raw_file": copied_raw_palette.as_posix(),
                "tlut_decoded_file": copied_decoded_palette.as_posix(),
                "tlut_raw_sha256": sha256((writer.output / copied_raw_palette).read_bytes()),
                "tlut_decoded_sha256": sha256((writer.output / copied_decoded_palette).read_bytes()),
                "tlut_entries": str(palette.get("entries", "0")),
            })
        dependencies.append(dependency)
    return dependencies


def parse_named_image_dependencies(root: Path, writer: PayloadWriter, routes: list[Route],
                                   existing: list[Dependency]) -> list[Dependency]:
    """Decode named global IMAGE rows for non-room effects/HUD/sky assets.

    ``assets/images/split`` is a checked-in source mirror, but the ROM remains
    the authority here: each selected named row is copied from its guarded
    ``imagelist.u.csv`` range and decoded by the same checked-in ``tex2png``
    semantics used by the stage texture preparation.
    """
    try:
        sys.path.insert(0, str(root / "scripts"))
        from prepare_native_stage_texture_assets import decode_levels
        from prepare_native_source_frontend_v6 import _extract_pd_palette
    except ImportError as error:
        raise PreparationError("source image decoder/palette decoder is unavailable") from error
    image_rows = parse_image_list(root)
    image_defs: list[tuple[int, str, int]] = []
    for index, line in enumerate((root / "assets/images.def").read_text(encoding="utf-8").splitlines()):
        stripped = line.strip()
        if not stripped.startswith("IMAGE(") or not stripped.endswith(")"):
            continue
        parts = [part.strip() for part in stripped[6:-1].split(",")]
        if len(parts) != 8:
            raise PreparationError(f"malformed IMAGE definition at source index {index}")
        name = parts[0]
        try:
            declared_bytes = int(parts[1], 0)
        except ValueError as error:
            raise PreparationError(f"invalid IMAGE size for {name}") from error
        image_defs.append((index, name, declared_bytes))
    existing_symbols = {dependency.symbol for dependency in existing}
    selected: list[Dependency] = []
    import tempfile

    for index, name, declared_bytes in image_defs:
        # Numeric/anonymous rows are already represented by the room trace;
        # named rows make the non-room category boundary reviewable.
        if not name or name.isdigit():
            continue
        category = classify_image(name)
        if category == "textures":
            continue
        symbol = f"IMAGE_{index}_{name}"
        if symbol in existing_symbols:
            continue
        image_path = f"assets/images/split/image{index}.bin"
        image_row = image_rows.get(image_path)
        if image_row is None or image_row[1] != declared_bytes:
            raise PreparationError(f"named IMAGE row differs from imagelist: {name}")
        with writer.rom.open("rb") as stream:
            stream.seek(image_row[0])
            source = stream.read(image_row[1])
        if len(source) != image_row[1]:
            raise PreparationError(f"named IMAGE ROM row is truncated: {name}")
        with tempfile.TemporaryDirectory(prefix="goldeneye-ramrom-visible-image-") as temporary:
            temporary_root = Path(temporary)
            base = temporary_root / name
            levels, stream_format, stream_compression, visibility = decode_levels(root, name, source, base)
            decoded_source = base.with_suffix(".decoded")
            dependency = writer.add_copy(
                category, symbol, "assets/images.def", base.with_suffix(".raw"), decoded_source,
                routes, STAGES,
                {"index": str(index), "name": name, "rom_offset": str(image_row[0]),
                 "rom_bytes": str(image_row[1]), "source_row": image_row[2],
                 "stream_format": str(stream_format), "stream_compression": str(stream_compression),
                 "visibility": visibility, "source_level_count": str(len(levels))},
            )
            if dependency.source_sha256 != sha256(source):
                raise PreparationError(f"named IMAGE copied raw digest mismatch: {name}")
            payload_id = Path(dependency.raw_file).stem
            for level, _width, _height, _count, level_digest, filename, _inspection_digest, _inspection_file in levels:
                level_path = base.parent / filename
                if level == 0:
                    copied_level = Path(dependency.decoded_file)
                else:
                    copied_level = Path("payload/decoded") / f"{payload_id}.mip{level}.bin"
                    shutil.copyfile(level_path, writer.output / copied_level)
                copied = writer.output / copied_level
                if sha256(copied.read_bytes()) != level_digest:
                    raise PreparationError(f"named IMAGE decoded digest mismatch: {name} level {level}")
                dependency.fields[f"mip_{level}_file"] = copied_level.as_posix()
                dependency.fields[f"mip_{level}_bytes"] = str(copied.stat().st_size)
                dependency.fields[f"mip_{level}_sha256"] = sha256(copied.read_bytes())
            palette = _extract_pd_palette(source)
            if palette is not None:
                palette_raw, palette_decoded, metadata = palette
                raw_palette = Path("payload/raw") / f"{payload_id}.tlut.bin"
                decoded_palette = Path("payload/decoded") / f"{payload_id}.tlut.bin"
                (writer.output / raw_palette).write_bytes(palette_raw)
                (writer.output / decoded_palette).write_bytes(palette_decoded)
                dependency.fields.update({
                    "tlut_raw_file": raw_palette.as_posix(), "tlut_decoded_file": decoded_palette.as_posix(),
                    "tlut_raw_sha256": sha256(palette_raw),
                    "tlut_decoded_sha256": sha256(palette_decoded),
                    "tlut_entries": str(metadata["entries"]),
                })
            selected.append(dependency)
            existing_symbols.add(symbol)
    return selected


def add_semantic(dependencies: list[Dependency], category: str, symbol: str, source: Path,
                 source_digest: str, routes: list[Route], fields: dict[str, str]) -> None:
    source_display = source.as_posix()
    for marker in ("src/", "assets/"):
        if marker in source_display:
            source_display = source_display[source_display.index(marker):]
            break
    dependencies.append(Dependency(
        category=category, symbol=symbol, source_path=source_display, rom_row="none", rom_offset=None,
        source_bytes=0, compressed=False, source_sha256=source_digest, decoded_bytes=0,
        decoded_sha256=source_digest, raw_file="none", decoded_file="none",
        demo_ids={route.demo_id for route in routes}, stages=set(STAGES), fields={"asset_type": "semantic", **fields},
    ))


def write_manifest(output: Path, routes: list[Route], dependencies: list[Dependency],
                   source_digests: dict[str, str], output_rom_sha1: str) -> Path:
    categories = sorted({dep.category for dep in dependencies})
    lines = [
        "manifest_version=6", "asset_family=ramrom_visible_dependencies_v6",
        "trace_contract=source-setup+chr-table+gun-table+stage-texture+ramrom-header",
        f"external_rom_size={ROM_BYTES}", f"external_rom_sha1={output_rom_sha1}",
        "rom_copied_into_checkout=false", "rom_copied_into_bundle=false",
        "runtime_opens_rom=false", "runtime_consumes_prepared_payloads_only=true",
        "emulation_used=false", f"demo_count={len(routes)}", f"stage_count={len(STAGES)}",
        f"dependency_count={len(dependencies)}", f"category_count={len(categories)}",
        f"categories={','.join(categories)}",
    ]
    for relative, digest in sorted(source_digests.items()):
        lines.append(f"source_sha256_{safe(relative)}={digest}")
    for route in routes:
        lines.append(
            f"demo_{route.demo_id}=stage:{route.stage}|stage_id:{route.stage_id}|variant:{route.variant}|"
            f"controller_count:{route.controller_count}|total_time_ms:{route.total_time_ms}|"
            f"declared_bytes:{route.declared_bytes}|asset_bytes:{route.asset_bytes}|"
            f"packet_count:{route.packet_count}|record_count:{route.record_count}|"
            f"recording_sha256:{route.recording_sha256}|source_asset:{Path(route.source_path).name}"
        )
    for index, dep in enumerate(dependencies):
        fields = [
            f"category:{dep.category}", f"symbol:{dep.symbol}", f"source_path:{dep.source_path}",
            f"rom_row:{dep.rom_row}", f"rom_offset:{'none' if dep.rom_offset is None else dep.rom_offset}",
            f"source_bytes:{dep.source_bytes}", f"compressed:{int(dep.compressed)}",
            f"decoded_bytes:{dep.decoded_bytes}", f"source_sha256:{dep.source_sha256}",
            f"decoded_sha256:{dep.decoded_sha256}", f"raw_file:{dep.raw_file}",
            f"decoded_file:{dep.decoded_file}",
            f"demo_ids:{','.join(str(value) for value in sorted(dep.demo_ids))}",
            f"stages:{','.join(sorted(dep.stages, key=STAGES.index))}",
        ] + [f"{key}:{value}" for key, value in sorted(dep.fields.items())]
        lines.append(f"dependency_{index}=" + "|".join(fields))
    lines += [
        "coverage_status=PASS", "payload_status=PASS", "source_trace_status=PASS",
        "manifest_status=PASS",
    ]
    path = output / "ramrom-visible-dependencies-v6-manifest.txt"
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--rom", type=Path, required=True)
    parser.add_argument("--stage-asset-root", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, default=None)
    args = parser.parse_args()
    root = args.project_root.resolve()
    output = (args.output_dir or root / "build/native/ramrom-visible-dependencies-v6").resolve()
    stage_root = args.stage_asset_root.resolve()
    verify_output(root, output)
    rom = verify_rom(root, args.rom.resolve())
    source_digests = verify_source_guards(root)
    rows = parse_filelist(root)
    routes = parse_routes(root)
    setup_rows = parse_dependency_manifest(stage_root)
    output.mkdir(parents=True, exist_ok=True)
    writer = PayloadWriter(root, output, rom, rows)
    dependencies: list[Dependency] = []

    # Setup-derived props and body characters, collapsed by source model index
    # while retaining every stage/demo reachability set in the row.
    unique: dict[tuple[str, str], dict[str, object]] = {}
    for row in setup_rows:
        key = (row["kind"], row["model_name"])
        entry = unique.setdefault(key, {"row": row, "stages": set()})
        entry["stages"].add(row["stage"])  # type: ignore[union-attr]
    route_by_stage = {stage: [route for route in routes if route.stage == stage] for stage in STAGES}
    for (kind, model_name), entry in sorted(unique.items()):
        row = entry["row"]  # type: ignore[assignment]
        stages = sorted(entry["stages"], key=STAGES.index)  # type: ignore[arg-type]
        stage_routes = [route for stage in stages for route in route_by_stage[stage]]
        category = "guards" if kind == "character" else classify_prop(model_name)
        path = str(row["rom_row"])
        dep = writer.add_file(category, f"{kind}_{row['model_index']}_{model_name}", path,
                              stage_routes, stages,
                              {"source_path": str(row["source_path"]), "model_index": str(row["model_index"]),
                               "object_type": str(row["object_type"]), "setup_offset": str(row["setup_offset"]),
                               "dependency_kind": kind})
        dependencies.append(dep)

    # Source-randomized character head selection is not represented in setup
    # object records.  The complete bounded head table is the deterministic
    # source candidate set; it is not a copy of unrelated character assets.
    chr_names = parse_chr_table(root)
    for table_index, name in enumerate(chr_names):
        if not name.lower().startswith("head"):
            continue
        path = f"assets/obseg/chr/C{name}Z.bin"
        if path not in rows:
            raise PreparationError(f"head table row is absent: {path}")
        dependencies.append(writer.add_file(
            "heads", f"chr_{table_index}_{name}", path, routes, STAGES,
            {"source_path": f"assets/obseg/chr/{name}/Model.c", "table_index": str(table_index),
             "dependency_kind": "source-randomized-head"},
        ))

    # The source gun table is the held-object pool selected by the RAMROM
    # header weapon_set and stage gameplay.  Keep its table order in metadata.
    filelist_text = (root / "assets/obseg/Makefile.filelist").read_text(encoding="utf-8")
    gun_names = parse_named_table(filelist_text, "GUNNAMELIST", "PROPNAMELIST")
    for table_index, name in enumerate(gun_names):
        path = f"assets/obseg/gun/G{name}Z.bin"
        if path not in rows:
            raise PreparationError(f"gun table row is absent: {path}")
        dependencies.append(writer.add_file(
            classify_gun(name), f"gun_{table_index}_{name}", path, routes, STAGES,
            {"source_path": f"assets/obseg/gun/{name}/Model.c", "table_index": str(table_index),
             "dependency_kind": "source-gun-table"},
        ))

    # Room-selected image payloads are already losslessly decoded by the
    # source texture preparation contract.  Copy their raw and RGBA8 level-0
    # bytes into this independent sidecar; TLUT hashes remain attached to the
    # row and therefore cannot be silently dropped by a later loader.
    dependencies.extend(parse_stage_texture_copy(root, stage_root, writer, routes))
    dependencies.extend(parse_named_image_dependencies(root, writer, routes, dependencies))

    # Sky vertices and gradients are carried by the seven source background
    # segments.  Keep one guarded row per attract stage as the explicit sky
    # dependency; room traversal remains owned by the separate stage packet.
    background_names = {
        "Dam": "bg_dam_all_p", "Facility": "bg_ark_all_p", "Runway": "bg_run_all_p",
        "Bunker I": "bg_sev_all_p", "Silo": "bg_silo_all_p", "Frigate": "bg_dest_all_p",
        "Train": "bg_tra_all_p",
    }
    for stage, name in background_names.items():
        path = f"assets/obseg/bg/{name}.bin"
        dependencies.append(writer.add_file(
            "sky", f"background_{stage}", path,
            route_by_stage[stage], (stage,),
            {"source_path": f"assets/obseg/bg/{name}.c", "asset_role": "source-sky-segment"},
        ))

    # Frontend/gameplay support assets whose draw commands are semantic rather
    # than a ROM row (solid fades and source sky state).  Keep source code
    # provenance explicit instead of inventing payload bytes.
    add_semantic(dependencies, "fades", "screen_fade_to_black/from_black", root / "src/game/bondview2.c",
                 source_digests["src/game/bondview2.c"], routes,
                 {"source_symbol": "currentPlayerAdjustFade", "render_dependency": "source-color-fade"})
    add_semantic(dependencies, "effects", "gunfire_effect_dispatch", root / "src/game/gunfire.c",
                 source_digests["src/game/gunfire.c"], routes,
                 {"source_symbol": "gunfireRender", "render_dependency": "muzzle-flash/projectile"})
    add_semantic(dependencies, "particles", "particle_effect_dispatch", root / "src/game/explosion.c",
                 source_digests["src/game/explosion.c"], routes,
                 {"source_symbol": "explosionRender", "render_dependency": "source-particle-state"})
    add_semantic(dependencies, "explosions", "explosion_render_dispatch", root / "src/game/explosion.c",
                 source_digests["src/game/explosion.c"], routes,
                 {"source_symbol": "explosionRender", "render_dependency": "source-explosion-state"})
    add_semantic(dependencies, "sky", "stage_sky_state", root / "src/game/sky.c",
                 source_digests["src/game/sky.c"], routes,
                 {"source_symbol": "skyRender", "render_dependency": "stage-background-sky"})

    # Audio banks and stage/frontend sequences are source-indexed rows.  The
    # music selection is deliberately stage-scoped; the complete SFX and
    # instrument banks are shared by every recording.
    audio_paths = {
        path for path in rows
        if path in {
            "assets/music/sfx.ctl", "assets/music/sfx.tbl", "assets/music/instruments.ctl",
            "assets/music/instruments.tbl", "assets/music/music.sbk",
        }
    }
    stage_audio_tokens = {
        "dam": ("dam",), "facility": ("facility",), "runway": ("runway",),
        "bunker i": ("bunker1", "bunker2"), "silo": ("silo",),
        "frigate": ("frigate",), "train": ("train",),
    }
    frontend_tracks = {"mintro_eye.bin", "mnint_rare_logo.bin", "mcontrol.bin", "mcontrolx.bin",
                       "mfolders.bin", "mno_music.bin"}
    for path in rows:
        if not path.startswith("assets/music/M") or not path.endswith(".bin"):
            continue
        lower = Path(path).name.lower()
        if lower in frontend_tracks or any(
            token in lower for tokens in stage_audio_tokens.values() for token in tokens
        ):
            audio_paths.add(path)
    for table_index, path in enumerate(sorted(audio_paths)):
        dependencies.append(writer.add_file(
            "audio", f"audio_{table_index}_{Path(path).stem}", path, routes, STAGES,
            {"source_path": path, "audio_dependency": "CSeq/SFX source bank"},
        ))
    for path in ("assets/font/fontBankGothic_kerning.bin", "assets/font/fontBankGothic_fontchartable.bin",
                 "assets/font/fontZurichBold_kerning.bin", "assets/font/fontZurichBold_fontchartable.bin",
                 "assets/animationtable_entries.bin", "assets/animationtable_data.bin",
                 "assets/ge007.u.29D160.Globalimagetable.bin"):
        if path not in rows:
            raise PreparationError(f"shared visible dependency row is absent: {path}")
        dependencies.append(writer.add_file(
            "hud" if "font" in path or "Globalimage" in path else "watch",
            f"shared_{Path(path).stem}", path, routes, STAGES,
            {"source_path": path, "dependency_kind": "shared-source-table"},
        ))

    # Required category presence is a hard preparation guard.  Semantic rows
    # are intentional for effects/fades/sky where source state is not a byte
    # payload; every other category has copied source bytes.
    required_categories = {"props", "doors", "guards", "heads", "weapons", "projectiles",
                           "effects", "particles", "glass", "explosions", "hud", "watch",
                           "sky", "fades", "textures", "audio"}
    present = {dep.category for dep in dependencies}
    missing = sorted(required_categories - present)
    if missing:
        raise PreparationError(f"visible dependency categories are missing: {','.join(missing)}")
    manifest = write_manifest(output, routes, dependencies, source_digests, ROM_SHA1)
    print("Native RAMROM visible dependency preparation: PASS "
          f"demos={len(routes)} stages={len(STAGES)} dependencies={len(dependencies)} "
          f"categories={len(present)}")
    print(f"Manifest: {manifest}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PreparationError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
