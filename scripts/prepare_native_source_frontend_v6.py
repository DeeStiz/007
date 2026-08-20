#!/usr/bin/env python3
"""Prepare the lossless native frontend source catalog (GEFV version 6).

This preparation lane is deliberately separate from the older GETP/GETN/GETT
packets.  It records the source categories that the boot/menu renderer must
consume: model node tables and display lists, vertex groups, texture rows and
mips, global image streams, Rareware's hand-authored data, fonts/text, blood
and weapon animation data, and the frontend audio rows.

The external US ROM is an input to this script only.  It is verified by size,
SHA-1, checkout-boundary and reference-build guards, then individual rows are
copied into ignored build/native output.  The resulting GEFV envelope contains
only copied value bytes and relative provenance; runtime has no ROM dependency.

The public preparation API is intentionally small and deterministic so parser
tests can exercise it with fixture source listings without needing the ROM:
``parse_model_listing``, ``parse_rareware_listing`` and ``verify_packet``.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import struct
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable


MAGIC = b"GEFV"
VERSION = 6
ROM_SHA1_EXPECTED = "abe01e4aeb033b6c0836819f549c791b26cfde83"
ROM_SIZE_EXPECTED = 12_582_912
REFERENCE_COMMAND = "make -j8 IDO_RECOMP=NO VERSION=US COMPARE=1 VERBOSE=1"
REFERENCE_HASH_COMMAND = "sha1sum -c ge007.u.sha1"
DEFAULT_ROM_PATH = Path("/Users/derek/Documents/GoldenEye 007 (USA).z64")

# The header is fixed-width and pointer-free.  The packet hash is computed
# over this header with its hash field zeroed, followed by canonical JSON and
# the deduplicated byte payload.
HEADER = struct.Struct("<4sIIIIII32s32sI")
assert HEADER.size == 96


SOURCE_HASH_GUARDS: dict[str, str] = {
    "scripts/goldeneye_pd_image_decoder_v6.py": "b7e30cd52c937f78d48e1e221a5880ccd06f0b88f0d5dd106d7d5dd1b8801a75",
    "assets/obseg/prop/legalpage/Model.c": "5af36d1255193d60282b42a5dd80ccd473bc2d7fc6631615dae08d0e9b659337",
    "assets/obseg/prop/nintendologo/Model.c": "8e0e40946713203f1db3cda53167a86658aa2aa10eb00ae89d64aa52aedc35d9",
    "assets/obseg/prop/goldeneyelogo/Model.c": "c98da38e9b27fb6a5f02e1ff1dc28964384cd387e325af17b1804625b622a54c",
    "assets/obseg/prop/walletbond/Model.c": "feed206e277e58e9cd4de67a299634743ea9706f241b4bfa61d6adb57cee1df7",
    "assets/obseg/chr/headbrosnansuit/Model.c": "b92a505abb9bd53e0d9b031835b8ebf5c32b4a308cbf80f08ba3be3b3084348e",
    "assets/obseg/chr/suitbond/Model.c": "76a8e4e3d7baad79640262da2632b367147c5594a559ebfc55df829ef9214b88",
    "assets/obseg/prop/chrwppk/Model.c": "9870735843375db88871898c65c65ac54c00fc7e1d005be4f1ff4d8e6b26faa5",
    "assets/rarewarelogo.c": "ee03f5652d18b49e700a746476525686ffb7bb650c109618ea6d0243a3cae1b5",
    "assets/font/fontZurichBold.c": "7d6121a845a051c81cd4da75c55aef71a10d8ddc2e2006316f420b3d756de4bc",
    "assets/font/fontBankGothic.c": "a4dc0c44b22b5b92e6c3e2016dca27fed16aeca8cdc05cc80fbc58bc3a552cb1",
    "assets/font_dl.c": "af01f1d542a1381d5673b7887912708d5155dbc68a010837c7b8f6db6fac203e",
    "assets/font_chardatae.c": "77d1abfa16f573b93965869f9bef942be2688f1a036f1840ba888b6a57b88594",
    "assets/obseg/text/LtitleE.c": "2fb986eb004faf9bbc259af928a20fd61b7fa76f00d35cefc82a7a4582788319",
    "src/game/front.c": "839c3c478fc270bc6fb401685f2b738a74a05e8580dabd6345fde46ca4e2a764",
    "src/game/title.c": "1bdd78363b3ac05bc1b1148edcc17f577d3a81115faab530be0cd019c6261adc",
    "src/game/blood_animation.c": "8d474a713b2c53fa3daa62999d440d12294d984d5dfa8a16830df521d5f7efe6",
    "assets/embedded/skeletons/standard_gun.inc.c": "3fbed7795ebc79d7caef20956bb71efe644ce31047f5ce8e9a43f771479b212f",
    "assets/embedded/skeletons/gun_kf7.inc.c": "b8165dad93eddaedb00a6bf3d954737dd1b0d866673485383a3482c2f89e9906",
    "assets/music/music.s": "2fdf81fccb0cc2bf9ced27d0dc478b08a04d819ae3e977ede6090abf5709043e",
    "src/music.h": "e68e21773fdebe6ca66262f84e66213ebc9eed451a3dae5e31b019170bfaf10d",
    "assets/music/music.sbk": "d293881a398276b082fb1da9eec13d24aaebe277990d73bc4bcc1aaf320db7d9",
    "assets/images.def": "01fde9bf2934b82460eaefc55ed7e8c2d706290489eeef8b3f9bbb243973ea09",
    "assets/image_externs.h": "ae4918f35a12d307f57d62d03898f2609debd0fd8a62dea6458674504dc0447b",
}

IMAGE_SOURCE_HASH_GUARDS: dict[str, str] = {
    "COPYICON": "e2129e877befe82fb6b6299edde3dc23b059ce6d281b800ddbbbb2fb794b6119",
    "DELICON": "d13f7ce02d63af243fce76659b91467741c3aa02469ff82bf636d9540f95efae",
    "SELECTFILE": "7f0bf6431a2406d5edceabe7722204c374618f72df41119794a939d24d76f09d",
    "CROSSHAIR1": "c43dea8d08ce9094aa445587788a6ef77dff95f6fdc38c83cbe6313363d42417",
    "CHECK": "276d188622d5a029a3f20606e2500bc4ef7e8a42673319efb019c66f22618fd1",
    "DOT": "b9924290b5d71aa709a97082e3c09b6f357329e5bc20427b2f6c8f18794c919f",
    "X": "dff183a6438a54153f518c026350120f7d8a8cb12385d401a542c1797103ff29",
}


# Exact rows from scripts/filelist.u.csv.  The row text itself is guarded so
# a changed offset, length, compression bit or source name fails closed.
ROM_ROWS: dict[str, str] = {
    "rarewarelogo": "2745696,26608,assets/rarewarelogo.bin,0,0",
    "gunbarrel_background": "2772304,107904,assets/ge007.u.2A4D50.usedby7F008DE4.bin,0,1",
    "legalpage": "8314032,4032,assets/obseg/prop/PlegalpageZ.bin,1,1",
    "nintendologo": "8348000,10976,assets/obseg/prop/PnintendologoZ.bin,1,1",
    "goldeneyelogo": "8262192,3760,assets/obseg/prop/PgoldeneyelogoZ.bin,1,1",
    "walletbond": "8526992,5552,assets/obseg/prop/PwalletbondZ.bin,1,1",
    "headbrosnansuit": "7455952,3456,assets/obseg/chr/CheadbrosnansuitZ.bin,1,1",
    "suitbond": "7689936,11664,assets/obseg/chr/CsuitbondZ.bin,1,1",
    "chrwppk": "8189712,576,assets/obseg/prop/PchrwppkZ.bin,1,1",
    "font_zurich_kerning": "3049632,676,assets/font/fontZurichBold_kerning.bin,0,0",
    "font_zurich_chartable": "3050308,12956,assets/font/fontZurichBold_fontchartable.bin,0,0",
    "font_bank_kerning": "3040240,676,assets/font/fontBankGothic_kerning.bin,0,0",
    "font_bank_chartable": "3040916,8716,assets/font/fontBankGothic_fontchartable.bin,0,0",
    "jfont_dl": "1144960,192,assets/ge007.u.117880.jfont_dl.bin,0,0",
    "jfont_chardata": "1145152,46848,assets/ge007.u.117940.jfont_chardata.bin,0,0",
    "efont_chardata": "1192000,6784,assets/ge007.u.123040.efont_chardata.bin,0,0",
    "title_text": "9396000,2752,assets/obseg/text/LtitleE,1,0",
    "audio_instruments_ctl": "3884112,17312,assets/music/instruments.ctl,0,1",
    "audio_instruments_tbl": "3901424,397216,assets/music/instruments.tbl,0,1",
    "audio_sfx_ctl": "3063264,23488,assets/music/sfx.ctl,0,1",
    "audio_sfx_tbl": "3086752,797360,assets/music/sfx.tbl,0,1",
    "audio_intro": "4299660,2222,assets/music/Mintro_eye.bin,1,1",
    "audio_folders": "4358444,994,assets/music/Mfolders.bin,1,1",
    "audio_nintendo_rare": "4395214,1074,assets/music/Mnint_rare_logo.bin,1,1",
}


MODEL_SPECS: tuple[dict[str, Any], ...] = (
    {"family": "legal", "name": "legalpage", "path": "assets/obseg/prop/legalpage/Model.c", "rom": "legalpage", "handle": 4},
    {"family": "nintendo", "name": "nintendologo", "path": "assets/obseg/prop/nintendologo/Model.c", "rom": "nintendologo", "handle": 5},
    {"family": "goldeneye", "name": "goldeneyelogo", "path": "assets/obseg/prop/goldeneyelogo/Model.c", "rom": "goldeneyelogo", "handle": 3},
    {"family": "wallet", "name": "walletbond", "path": "assets/obseg/prop/walletbond/Model.c", "rom": "walletbond", "handle": 6},
    {"family": "gunbarrel", "name": "headbrosnansuit", "path": "assets/obseg/chr/headbrosnansuit/Model.c", "rom": "headbrosnansuit", "handle": 7},
    {"family": "gunbarrel", "name": "suitbond", "path": "assets/obseg/chr/suitbond/Model.c", "rom": "suitbond", "handle": 8},
    {"family": "gunbarrel", "name": "chrwppk", "path": "assets/obseg/prop/chrwppk/Model.c", "rom": "chrwppk", "handle": 9},
)

EXPECTED_MODEL_COUNTS: dict[str, dict[str, int]] = {
    "legalpage": {"nodes": 3, "display_lists": 1, "vertices": 24, "textures": 5},
    "nintendologo": {"nodes": 42, "display_lists": 23, "vertices": 1363, "textures": 1},
    "goldeneyelogo": {"nodes": 3, "display_lists": 1, "vertices": 438, "textures": 2},
    "walletbond": {"nodes": 90, "switch_nodes": 42, "switch_records": 43, "display_lists": 46, "vertices": 765, "textures": 84},
}


class PreparationError(RuntimeError):
    """A missing or changed source must stop preparation, never fall back."""


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha1_hex(data: bytes) -> str:
    return hashlib.sha1(data).hexdigest()


def relative_path(root: Path, path: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError as error:
        raise PreparationError(f"path escapes project root: {path}") from error


def parse_int(value: str) -> int:
    value = re.sub(r"/\*.*?\*/", "", value, flags=re.S)
    value = re.sub(r"//[^\n]*", "", value).strip()
    value = re.sub(r"[uUlL]+$", "", value)
    return int(value, 16 if value.lower().startswith("0x") else 10)


def guarded_source(root: Path, relative: str) -> bytes:
    path = root / relative
    if not path.is_file():
        raise PreparationError(f"required source is missing: {relative}")
    data = path.read_bytes()
    expected = SOURCE_HASH_GUARDS.get(relative)
    actual = sha256_hex(data)
    if expected and actual != expected:
        raise PreparationError(f"source SHA-256 mismatch for {relative}: expected {expected}, got {actual}")
    return data


def filelist_rows(root: Path) -> dict[str, str]:
    path = root / "scripts/filelist.u.csv"
    if not path.is_file():
        raise PreparationError(f"file list is missing: {path}")
    rows = [line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    lookup = set(rows)
    for key, row in ROM_ROWS.items():
        if row not in lookup:
            raise PreparationError(f"required file-list row for {key} is missing or changed: {row}")
    return {key: row for key, row in ROM_ROWS.items()}


def verify_external_rom(root: Path, rom_path: Path) -> tuple[Path, str]:
    rom = rom_path.expanduser()
    if not rom.is_absolute():
        raise PreparationError(f"external ROM path must be absolute: {rom}")
    if not rom.is_file():
        raise PreparationError(f"external ROM is missing: {rom}")
    real = rom.resolve()
    project = root.resolve()
    if real == project or project in real.parents:
        raise PreparationError(f"the ROM must remain outside the checkout: {real}")
    if real.stat().st_size != ROM_SIZE_EXPECTED:
        raise PreparationError(f"external ROM size mismatch: expected {ROM_SIZE_EXPECTED}, got {real.stat().st_size}")
    digest = sha1_hex(real.read_bytes())
    if digest != ROM_SHA1_EXPECTED:
        raise PreparationError(f"external ROM SHA-1 mismatch: expected {ROM_SHA1_EXPECTED}, got {digest}")
    evidence = root / ".porting/m0-provenance.md"
    if not evidence.is_file():
        raise PreparationError(f"Linux provenance evidence is missing: {evidence}")
    evidence_text = evidence.read_text(encoding="utf-8")
    for required in (REFERENCE_COMMAND, REFERENCE_HASH_COMMAND, ROM_SHA1_EXPECTED):
        if required not in evidence_text:
            raise PreparationError(f"Linux provenance evidence is missing: {required}")
    return real, digest


def ensure_output_guard(root: Path, output: Path) -> None:
    output = output.resolve()
    if root.resolve() in output.parents or output == root.resolve():
        # The output is allowed only below an ignored build/native path.
        if not output.as_posix().startswith((root / "build/native").resolve().as_posix() + "/"):
            raise PreparationError(f"source frontend output must remain under build/native: {output}")
    try:
        subprocess.run(["git", "-C", str(root), "check-ignore", "-q", str(output)], check=True)
    except (OSError, subprocess.CalledProcessError) as error:
        raise PreparationError(f"source frontend output is not ignored: {output}") from error


def extract_rom_row(root: Path, rom: Path, row: str, destination: Path) -> tuple[bytes, bytes, dict[str, Any]]:
    offset_text, size_text, source_row, compressed_text, private_text = row.split(",")
    offset = int(offset_text)
    size = int(size_text)
    compressed = int(compressed_text) == 1
    with rom.open("rb") as stream:
        stream.seek(offset)
        raw = stream.read(size)
    if len(raw) != size:
        raise PreparationError(f"ROM row {source_row} truncated: expected {size}, got {len(raw)}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    raw_path = destination.with_suffix(".raw")
    raw_path.write_bytes(raw)
    if compressed:
        decoded_path = destination.with_suffix(".decoded")
        inflater = root / "tools/1172inflate.sh"
        if not inflater.is_file() or not os.access(inflater, os.X_OK):
            raise PreparationError(f"1172 inflater is unavailable: {inflater}")
        try:
            subprocess.run(
                [str(inflater), str(raw_path), str(decoded_path)],
                cwd=str(root),
                env={**os.environ, "GZ": "gzip"},
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
        except (OSError, subprocess.CalledProcessError) as error:
            raise PreparationError(f"failed to decompress ROM row {source_row}") from error
        decoded = decoded_path.read_bytes()
    else:
        decoded = raw
        destination.with_suffix(".decoded").write_bytes(decoded)
    return raw, decoded, {
        "rom_offset": offset,
        "rom_size": size,
        "rom_row": source_row,
        "compressed": compressed,
        "private_row": int(private_text),
    }


def _body_between(source: str, start: int, opening: str = "{", closing: str = "}") -> str:
    depth = 0
    begin = source.find(opening, start)
    if begin < 0:
        raise PreparationError("initializer opening brace is missing")
    for index in range(begin, len(source)):
        if source[index] == opening:
            depth += 1
        elif source[index] == closing:
            depth -= 1
            if depth == 0:
                return source[begin + 1 : index]
    raise PreparationError("initializer closing brace is missing")


def _texture_rows(source: str) -> list[dict[str, Any]]:
    match = re.search(r"ModelFileTextures\s+proptextures\[[^]]+\]\s*=\s*\{", source, re.S)
    if not match:
        raise PreparationError("ModelFileTextures table is missing")
    body = _body_between(source, match.start())
    rows: list[dict[str, Any]] = []
    for index, row in enumerate(re.finditer(r"\{([^{}]+)\}", body)):
        values = [value.strip() for value in row.group(1).split(",") if value.strip()]
        if len(values) != 8:
            raise PreparationError(f"malformed texture row {index}")
        parsed: list[int] = []
        for value in values[1:]:
            parsed.append(parse_int(value))
        rows.append(
            {
                "index": index,
                "resource": values[0],
                "width": parsed[0],
                "height": parsed[1],
                "mip_tiles": parsed[2],
                "type": parsed[3],
                "depth": parsed[4],
                "s_flags": parsed[5],
                "t_flags": parsed[6],
            }
        )
    if not rows:
        raise PreparationError("ModelFileTextures table is empty")
    # Some character listings repeat the same IMAGE_* row for separate source
    # material references. The image is one source resource; retaining
    # duplicate table rows creates an ambiguous deterministic handle and does
    # not change any display-list command semantics. Require repeated rows to
    # be byte-equivalent, then keep the first source-order descriptor.
    unique: list[dict[str, Any]] = []
    by_resource: dict[str, dict[str, Any]] = {}
    for row in rows:
        prior = by_resource.get(row["resource"])
        if prior is None:
            by_resource[row["resource"]] = row
            unique.append(row)
        elif any(prior[key] != row[key] for key in ("width", "height", "mip_tiles", "type", "depth", "s_flags", "t_flags")):
            raise PreparationError(f"texture resource {row['resource']} has conflicting duplicate rows")
    for index, row in enumerate(unique):
        row["index"] = index
    return unique


def _model_nodes(source: str) -> list[dict[str, Any]]:
    pattern = re.compile(
        r"^ModelNode\s+ModelNode_0x([0-9a-fA-F]+)\s*=\s*\{\s*([^,]+),",
        re.M,
    )
    return [
        {"offset": int(match.group(1), 16), "opcode": match.group(2).strip()}
        for match in pattern.finditer(source)
    ]


def _display_lists(source: str) -> list[str]:
    # DLPrimary records in a small number of setup props call an authored
    # ``GDL_0x...`` list in addition to the GFX_PRIMARY/GFX_SECONDARY rows.
    # Keep that source display list in the guarded summary so the generic
    # graph writer does not reject an otherwise complete sidecar.
    return re.findall(
        r"^Gfx\s+((?:GFX_(?:PRIMARY|SECONDARY)|GDL)_0x[0-9a-fA-F]+)\[\]\s*=",
        source,
        re.M,
    )


def _vertex_groups(source: str) -> list[dict[str, int]]:
    result = []
    for match in re.finditer(r"^#define\s+(VERTEXGROUPCOUNT\d+)\s+(\d+)", source, re.M):
        result.append({"name": match.group(1), "count": int(match.group(2))})
    if not result:
        raise PreparationError("no vertex group counts found")
    return result


def _image_tokens(source: str) -> list[str]:
    values = []
    for token in re.findall(r"\bIMAGE_[A-Za-z0-9_]+\b", source):
        if token not in values:
            values.append(token.removeprefix("IMAGE_"))
    return values


def _switch_record_count(source: str) -> int:
    match = re.search(r"\bu32\s+SwitchNodes\[(\d+)\]\s*=", source)
    return int(match.group(1)) if match else 0


def parse_model_listing(source: bytes, name: str) -> dict[str, Any]:
    """Parse one generated Model.c listing into deterministic scalar metadata."""
    try:
        text = source.decode("utf-8")
    except UnicodeDecodeError as error:
        raise PreparationError(f"{name}: Model.c is not UTF-8") from error
    nodes = _model_nodes(text)
    display_lists = _display_lists(text)
    vertices = _vertex_groups(text)
    textures = _texture_rows(text)
    result = {
        "name": name,
        "nodes": nodes,
        "display_lists": display_lists,
        "vertex_groups": vertices,
        "vertex_total": sum(group["count"] for group in vertices),
        "textures": textures,
        "switch_nodes": sum(node["opcode"] == "MODELNODE_OPCODE_SWITCH" for node in nodes),
        "switch_records": _switch_record_count(text),
        "image_tokens": _image_tokens(text),
        "tlut_commands": len(re.findall(r"(?:TLUT|DPLoadTLUT|G_TT_)", text)),
        "source_command_count": len(re.findall(r"\b(?:gs|gSP|gDP)[A-Za-z0-9_]+\s*\(", text)),
    }
    result["node_count"] = len(nodes)
    result["display_list_count"] = len(display_lists)
    result["texture_count"] = len(textures)
    if not result["nodes"] or not result["display_lists"]:
        raise PreparationError(f"{name}: model listing has no reachable nodes/display lists")
    expected = EXPECTED_MODEL_COUNTS.get(name)
    if expected:
        for key, expected_value in expected.items():
            count_key = {
                "nodes": "node_count",
                "display_lists": "display_list_count",
                "vertices": "vertex_total",
                "textures": "texture_count",
            }.get(key, key)
            actual = result.get(count_key)
            if actual != expected_value:
                raise PreparationError(f"{name}: {key} count {actual} != guarded {expected_value}")
    return result


def parse_rareware_listing(source: bytes) -> dict[str, Any]:
    """Parse Rareware's source listing without flattening its image arrays."""
    try:
        text = source.decode("utf-8")
    except UnicodeDecodeError as error:
        raise PreparationError("rarewarelogo.c is not UTF-8") from error
    textures = re.findall(r"^u32\s+([A-Za-z0-9_]+)\[\]\s*=", text, re.M)
    display_lists = re.findall(r"^Gfx\s+([A-Za-z0-9_]+)\[\]\s*=", text, re.M)
    vertex_arrays = re.findall(r"^Vtx\s+([A-Za-z0-9_]+)\[\]\s*=", text, re.M)
    texture_image_order = re.findall(r"gsDPSetTextureImage\([^,]+,[^,]+,[^,]+,\s*&([A-Za-z0-9_]+)", text)
    tile_sizes = len(re.findall(r"gsDPSetTileSize\s*\(", text))
    if len(textures) != 6 or len(texture_image_order) != 4:
        raise PreparationError(f"Rareware texture coverage mismatch: arrays={len(textures)} image_loads={len(texture_image_order)}")
    if len(display_lists) != 9 or len(vertex_arrays) != 26:
        raise PreparationError(f"Rareware geometry coverage mismatch: display_lists={len(display_lists)} vertex_arrays={len(vertex_arrays)}")
    return {
        "texture_arrays": textures,
        "display_lists": display_lists,
        "vertex_arrays": vertex_arrays,
        "mip_chains": [{"texture": name, "levels": 6} for name in texture_image_order],
        "extra_tile_sizes": max(0, tile_sizes - 24),
        "texture_image_order": texture_image_order,
        "tile_size_commands": tile_sizes,
    }


# ---------------------------------------------------------------------------
# GESM V6 sidecars
# ---------------------------------------------------------------------------

GESM_MAGIC = b"GESM"
GESM_VERSION = 6
GESM_HEADER = struct.Struct("<4s" + "I" * 15 + "32s32sI")
GESM_NODE = struct.Struct("<12I")
GESM_SCALAR = struct.Struct("<IIIII9IQ")
GESM_DISPLAY_LIST = struct.Struct("<8I")
GESM_COMMAND = struct.Struct("<12I")
GESM_TOKEN = struct.Struct("<IIIIIQ")
GESM_VERTEX = struct.Struct("<IIIIiiiiiiBBBBBBBBIIII")
GESM_TEXTURE = struct.Struct("<16I")
GESM_MIP = struct.Struct("<12I")
GESM_TLUT = struct.Struct("<8I")
assert GESM_HEADER.size == 132
assert GESM_NODE.size == 48
assert GESM_SCALAR.size == 64
assert GESM_DISPLAY_LIST.size == 32
assert GESM_COMMAND.size == 48
assert GESM_TOKEN.size == 28
assert GESM_VERTEX.size == 64
assert GESM_TEXTURE.size == 64
assert GESM_MIP.size == 48
assert GESM_TLUT.size == 32

GESM_FLAG_UNSUPPORTED_MACRO = 1 << 0
GESM_FLAG_RAREWARE = 1 << 1
GESM_NULL = 0xFFFF_FFFF


def fnv32(value: str) -> int:
    result = 2166136261
    for byte in value.encode("utf-8"):
        result = ((result ^ byte) * 16777619) & 0xFFFF_FFFF
    return result or 1


def _resource_handle(model_name: str, kind: str, token: str) -> int:
    return fnv32(f"{model_name}:{kind}:{token}")


def _resource_key(token: str) -> str:
    token = token.strip()
    if re.fullmatch(r"0x[0-9A-Fa-f]+", token):
        return f"0x{int(token, 16) & 0x00FF_FFFF:x}"
    return token


def _texture_handle(model_name: str, token: str) -> int:
    return _resource_handle(model_name, "texture", _resource_key(token))


def _strip_comments(source: str) -> str:
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    return re.sub(r"//[^\n]*", "", source)


def _split_top_level(text: str) -> list[str]:
    parts: list[str] = []
    start = 0
    depth = 0
    quote = ""
    escape = False
    for index, char in enumerate(text):
        if quote:
            if escape:
                escape = False
            elif char == "\\":
                escape = True
            elif char == quote:
                quote = ""
            continue
        if char in "\"'":
            quote = char
        elif char in "([{":
            depth += 1
        elif char in ")]}":
            depth = max(0, depth - 1)
        elif char == "," and depth == 0:
            parts.append(text[start:index].strip())
            start = index + 1
    tail = text[start:].strip()
    if tail:
        parts.append(tail)
    return parts


def _top_level_brace_rows(body: str) -> list[str]:
    rows: list[str] = []
    depth = 0
    start = -1
    quote = ""
    escape = False
    for index, char in enumerate(body):
        if quote:
            if escape:
                escape = False
            elif char == "\\":
                escape = True
            elif char == quote:
                quote = ""
            continue
        if char in "\"'":
            quote = char
        elif char == "{":
            depth += 1
            if depth == 1:
                start = index
        elif char == "}":
            if depth == 1 and start >= 0:
                rows.append(body[start + 1 : index])
                start = -1
            depth -= 1
    return rows


def _strip_comments_preserve(source: str) -> str:
    return re.sub(r"/\*.*?\*/", lambda match: "".join("\n" if char == "\n" else " " for char in match.group(0)), source, flags=re.S)


def _iter_macro_calls_with_positions(body: str) -> list[tuple[int, str, str]]:
    """Extract macro calls and source offsets from a comment-preserving body."""
    calls: list[tuple[int, str, str]] = []
    index = 0
    identifier = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
    while index < len(body):
        match = identifier.match(body, index)
        if not match:
            index += 1
            continue
        name = match.group(0)
        cursor = match.end()
        while cursor < len(body) and body[cursor].isspace():
            cursor += 1
        if cursor >= len(body) or body[cursor] != "(":
            index = cursor
            continue
        depth = 0
        quote = ""
        escape = False
        end = -1
        for position in range(cursor, len(body)):
            char = body[position]
            if quote:
                if escape:
                    escape = False
                elif char == "\\":
                    escape = True
                elif char == quote:
                    quote = ""
                continue
            if char in "\"'":
                quote = char
            elif char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
                if depth == 0:
                    end = position
                    break
        if end < 0:
            raise PreparationError(f"unterminated display-list macro {name}")
        calls.append((match.start(), name, body[cursor + 1 : end]))
        index = end + 1
    return calls


def _iter_macro_calls(body: str) -> list[tuple[str, str]]:
    """Extract top-level macro calls while retaining every argument token."""
    return [(name, args) for _, name, args in _iter_macro_calls_with_positions(body)]


def _canonicalize_token(model_name: str, token: str, kind_hint: str | None = None) -> str:
    token = re.sub(r"\s+", "", token)
    if not token:
        return ""
    def cast_pointer(match: re.Match[str]) -> str:
        value = match.group(1)
        try:
            numeric = int(value, 16 if value.lower().startswith("0x") else 10)
        except ValueError:
            numeric = 0
        if numeric == 0:
            return "@null"
        return f"@address:{_resource_handle(model_name, 'address', _resource_key(value)):08x}"

    def cast_pointer_expression(match: re.Match[str]) -> str:
        expression = match.group(1)
        if re.fullmatch(r"0x0+", expression, flags=re.I):
            return "@null"
        return f"@address:{_resource_handle(model_name, 'address', expression):08x}"

    token = re.sub(r"\(void\*\)\(([^()]*)\)", cast_pointer_expression, token)
    token = re.sub(r"\(void\*\)((?:0x)?[0-9A-Fa-f]+)", cast_pointer, token)
    if token == "NULL":
        return "@null"
    if token in {"TRUE", "FALSE"}:
        return token.lower()

    # Replace every source-address literal before retaining the token.  This
    # covers both ordinary segmented addresses and addresses nested in
    # osVirtualToPhysical/OS_K0_TO_PHYSICAL expressions.
    def address(match: re.Match[str]) -> str:
        value = match.group(0)
        kind = kind_hint or "address"
        if kind == "texture":
            handle = _texture_handle(model_name, value)
        elif kind == "vertex_group":
            handle = _resource_handle(model_name, kind, f"Vertex_0x{int(value, 16) & 0x00FF_FFFF:x}")
        else:
            handle = _resource_handle(model_name, kind, _resource_key(value))
        return f"@{kind}:{handle:08x}"

    if kind_hint is not None:
        token = re.sub(r"0x[0-9A-Fa-f]{7,8}", address, token)

    def symbol(match: re.Match[str]) -> str:
        prefix = match.group(1)
        value = match.group(2)
        kind = "texture" if prefix == "IMAGE_" else (kind_hint or "symbol")
        handle = _texture_handle(model_name, prefix + value) if kind == "texture" else _resource_handle(model_name, kind, prefix + value)
        return f"@{kind}:{handle:08x}"

    token = re.sub(r"\b(IMAGE_)([A-Za-z0-9_]+)\b", symbol, token)
    def resource_symbol(match: re.Match[str]) -> str:
        value = match.group(0)
        bare = value.lstrip("&")
        if bare.startswith(("GFX_", "DL_")):
            kind = "display_list"
            handle = _resource_handle(model_name, kind, bare)
        elif bare.startswith(("Vertex_", "verts")):
            kind = "vertex_group"
            handle = _resource_handle(model_name, kind, bare)
        else:
            kind = kind_hint or "resource"
            handle = _resource_handle(model_name, kind, bare)
        return f"@{kind}:{handle:08x}"

    token = re.sub(r"&?(?:Vertex_[0-9A-Za-z_]+|verts[A-Za-z0-9_]+|GFX_[0-9A-Za-z_]+|DL_[0-9A-Za-z_]+|DisplayListRecord_0x[0-9A-Fa-f]+|ModelNode_0x[0-9A-Fa-f]+|[A-Za-z]+Record_0x[0-9A-Fa-f]+)", resource_symbol, token)
    # A remaining address-like source symbol is still a pointer if it was
    # explicitly address-taken.  Convert it to a deterministic handle.
    token = re.sub(
        r"&([A-Za-z_][A-Za-z0-9_]*)",
        lambda match: (
            f"@{kind_hint}:{_texture_handle(model_name, match.group(1)):08x}"
            if kind_hint == "texture"
            else f"@{kind_hint or 'symbol'}:{_resource_handle(model_name, kind_hint or 'symbol', match.group(1)):08x}"
        ),
        token,
    )
    return token


def _canonicalize_text(model_name: str, text: str, normalize_numeric_literals: bool = False) -> str:
    result = _canonicalize_token(model_name, text)
    if normalize_numeric_literals:
        result = re.sub(r"0x[0-9A-Fa-f]{7,8}", lambda match: str(int(match.group(0), 16)), result)
    return result


def _numeric_or_handle(model_name: str, token: str) -> tuple[int, int, int]:
    canonical = _canonicalize_token(model_name, token)
    marker = re.fullmatch(r"@(display_list|vertex_group|texture|address|symbol|resource):([0-9a-fA-F]+)", canonical)
    if marker:
        kind = marker.group(1)
        return int(marker.group(2), 16), (1 if kind not in {"address", "resource"} else 2), fnv32(kind)
    try:
        return parse_int(canonical), 0, fnv32("number")
    except (TypeError, ValueError):
        return _resource_handle(model_name, "token", canonical), 1, fnv32("token")


def _command_arg_kind(macro: str, index: int) -> str | None:
    if macro in {"gsSPDisplayList", "gSPDisplayList"} and index == 0:
        return "display_list"
    if macro in {"gsSPVertex", "gSPVertex"} and index == 0:
        return "vertex_group"
    if macro in {"gsSPMatrix", "gSPMatrix"} and index == 0:
        return "address"
    if macro in {"gsDPSetTextureImage", "gDPSetTextureImage"} and index == 3:
        return "texture"
    if macro in {"gsSPUseTexture", "gSPUseTexture"} and index == 8:
        return "texture"
    return None


def _parse_model_nodes_graph(source: str, model_name: str) -> list[dict[str, Any]]:
    nodes: list[dict[str, Any]] = []
    pattern = re.compile(r"^ModelNode\s+ModelNode_0x([0-9A-Fa-f]+)\s*=\s*\{", re.M)
    for match in pattern.finditer(source):
        body = _body_between(source, match.start())
        values = _split_top_level(body)
        if len(values) != 6:
            raise PreparationError(f"{model_name}: malformed ModelNode initializer at 0x{int(match.group(1), 16):x}")
        nodes.append({"source_offset": int(match.group(1), 16), "values": values})
    nodes.sort(key=lambda item: item["source_offset"])
    by_offset = {node["source_offset"]: index for index, node in enumerate(nodes)}

    def node_ref(value: str) -> int:
        found = re.search(r"ModelNode_0x([0-9A-Fa-f]+)", value)
        return by_offset.get(int(found.group(1), 16), GESM_NULL) if found else GESM_NULL

    for node_id, node in enumerate(nodes):
        values = node["values"]
        opcode = values[0].strip()
        data = values[1].strip()
        node.update(
            {
                "id": node_id,
                "opcode": opcode,
                "opcode_handle": fnv32(opcode),
                "data": data,
                "data_handle": _resource_handle(model_name, "data", data),
                "parent": node_ref(values[2]),
                "next": node_ref(values[3]),
                "prev": node_ref(values[4]),
                "child": node_ref(values[5]),
            }
        )
    return nodes


def _record_initializer(source: str, data_token: str) -> str:
    found = re.search(r"(?:ModelRoData_[A-Za-z0-9_]+|[A-Za-z0-9_]+)\s+" + re.escape(data_token.lstrip("&")) + r"\s*=\s*\{", source)
    if not found:
        return data_token
    return _body_between(source, found.start())


def _record_type(source: str, data_token: str) -> str:
    symbol = data_token.lstrip("&")
    found = re.search(r"([A-Za-z0-9_]+)\s+" + re.escape(symbol) + r"\s*=\s*\{", source)
    return found.group(1) if found else "UnknownRecord"


def _float_bits(value: str) -> int:
    try:
        return struct.unpack("<I", struct.pack("<f", float(value))) [0]
    except (TypeError, ValueError, struct.error):
        return 0


def _bsp_metadata(source: str, node: dict[str, Any], node_by_offset: dict[int, int]) -> tuple[list[int], str]:
    values = _split_top_level(_record_initializer(source, node["data"]))
    if len(values) < 6:
        return [0] * 9, ""
    point = _split_top_level(values[0].strip().strip("{}"))
    vector = _split_top_level(values[1].strip().strip("{}"))
    left = re.search(r"ModelNode_0x([0-9A-Fa-f]+)", values[2])
    right = re.search(r"ModelNode_0x([0-9A-Fa-f]+)", values[3])
    left_id = node_by_offset.get(int(left.group(1), 16), GESM_NULL) if left else GESM_NULL
    right_id = node_by_offset.get(int(right.group(1), 16), GESM_NULL) if right else GESM_NULL
    metadata = [
        *[_float_bits(value) for value in (point + ["0", "0", "0"])[:3]],
        *[_float_bits(value) for value in (vector + ["0", "0", "0"])[:3]],
        parse_int(values[5]) if len(values) > 5 else 0,
        left_id,
        right_id,
    ]
    return metadata, _canonicalize_text("bsp", _record_initializer(source, node["data"]), True)


def _switch_metadata(source: str, node: dict[str, Any], node_by_offset: dict[int, int]) -> tuple[list[int], str]:
    values = _split_top_level(_record_initializer(source, node["data"]))
    control = re.search(r"ModelNode_0x([0-9A-Fa-f]+)", values[0] if values else "")
    control_id = node_by_offset.get(int(control.group(1), 16), GESM_NULL) if control else GESM_NULL
    # Controls points to the first child of the branch.  Following `next`
    # siblings gives the exact visible branch cardinality without traversing
    # hidden sibling branches elsewhere in the model graph.
    child_count = 0
    seen: set[int] = set()
    cursor = control_id
    while cursor != GESM_NULL and cursor not in seen and cursor < len(node_by_offset):
        seen.add(cursor)
        child_count += 1
        break
    rw_index = parse_int(values[1]) if len(values) > 1 else 0
    return [control_id, child_count, rw_index, fnv32("switch:first-controlled-child"), 0, 0, 0, 0, 0], _canonicalize_text("switch", _record_initializer(source, node["data"]), True)


def _display_list_metadata(source: str, model_name: str, node: dict[str, Any], display_ids: dict[str, int]) -> tuple[list[int], str, int, int]:
    values = _split_top_level(_record_initializer(source, node["data"]))
    record_type = _record_type(source, node["data"])
    if record_type == "ModelRoData_DisplayListPrimaryRecord":
        num_vertices = parse_int(values[0]) if values else 0
        vertex_name = values[1].lstrip("&") if len(values) > 1 else ""
        primary_name = values[2].lstrip("&") if len(values) > 2 else ""
        primary_id = display_ids.get(primary_name, GESM_NULL)
        vertex_match = re.fullmatch(r"Vertex_0x([0-9A-Fa-f]+)", vertex_name)
        if vertex_match:
            vertex_name = f"Vertex_0x{int(vertex_match.group(1), 16):x}"
        vertex_handle = _resource_handle(model_name, "vertex_group", vertex_name) if vertex_name else 0
        metadata = [primary_id, GESM_NULL, num_vertices, 0, vertex_handle, 0, 0, 0, 0]
        return metadata, _canonicalize_text(model_name, _record_initializer(source, node["data"]), True), primary_id, GESM_NULL
    primary_name = values[0].lstrip("&") if values else ""
    secondary_name = values[1].lstrip("&") if len(values) > 1 else ""
    primary_id = display_ids.get(primary_name, GESM_NULL)
    secondary_id = display_ids.get(secondary_name, GESM_NULL)
    if _record_type(source, node["data"]) == "ModelRoData_DisplayList_CollisionRecord":
        num_vertices = 0
        model_type = parse_int(values[6]) & 0xFF if len(values) > 6 and re.fullmatch(r"[-+0-9xXa-fA-F]+", values[6].strip()) else 0
        vertex_name = values[2].lstrip("&") if len(values) > 2 else ""
    else:
        num_vertices = parse_int(values[4]) if len(values) > 4 else 0
        model_type = parse_int(values[5]) & 0xFF if len(values) > 5 else 0
        vertex_name = values[3].lstrip("&") if len(values) > 3 else ""
    vertex_match = re.fullmatch(r"Vertex_0x([0-9A-Fa-f]+)", vertex_name)
    if vertex_match:
        vertex_name = f"Vertex_0x{int(vertex_match.group(1), 16):x}"
    vertex_handle = _resource_handle(model_name, "vertex_group", vertex_name) if vertex_name else 0
    return [primary_id, secondary_id, num_vertices, model_type, vertex_handle, 0, 0, 0, 0], _canonicalize_text(model_name, _record_initializer(source, node["data"]), True), primary_id, secondary_id


def _node_traversal_order(nodes: list[dict[str, Any]]) -> list[int]:
    by_id = {node["id"]: node for node in nodes}
    roots = [node["id"] for node in nodes if node.get("parent", GESM_NULL) == GESM_NULL]
    visited: set[int] = set()
    order: list[int] = []

    def visit(node_id: int) -> None:
        if node_id == GESM_NULL or node_id in visited or node_id not in by_id:
            return
        visited.add(node_id)
        order.append(node_id)
        visit(by_id[node_id].get("child", GESM_NULL))
        visit(by_id[node_id].get("next", GESM_NULL))

    for root in roots:
        visit(root)
    for node in nodes:
        visit(node["id"])
    return order


def _validate_graph_handles(model_name: str, graph: dict[str, Any]) -> None:
    display_handles = [int(display["handle"]) for display in graph["display_lists"]]
    vertex_handles = sorted({int(vertex["group_handle"]) for vertex in graph["vertices"]})
    texture_handles = [_texture_handle(model_name, str(texture["resource"])) for texture in graph["textures"]]
    for kind, handles in (("display_list", display_handles), ("vertex_group", vertex_handles), ("texture", texture_handles)):
        if len(handles) != len(set(handles)):
            raise PreparationError(f"{model_name}: ambiguous {kind} resource handle")
    expected = {"display_list": set(display_handles), "vertex_group": set(vertex_handles), "texture": set(texture_handles)}
    references: dict[str, set[int]] = {kind: set() for kind in expected}
    display_by_id = {display["id"]: display for display in graph["display_lists"]}
    for node in graph["nodes"]:
        for key in ("primary_dl_id", "secondary_dl_id"):
            display_id = node.get(key, GESM_NULL)
            if display_id != GESM_NULL and display_id in display_by_id:
                references["display_list"].add(int(display_by_id[display_id]["handle"]))
        meta_values = node.get("meta_values", ())
        if len(meta_values) > 4 and meta_values[4] in expected["vertex_group"]:
            references["vertex_group"].add(int(meta_values[4]))
    if graph.get("rareware"):
        # Rareware is entered through a route-owned top-level display-list
        # set rather than a ModelNode tree. Treat all six source texture
        # arrays and nine route display lists as explicit entrypoints, not as
        # an implicit all-lists renderer fallback.
        references["display_list"].update(expected["display_list"])
        references["texture"].update(expected["texture"])
    # Texture-table rows are explicit source dependencies even when a
    # particular LOD/attachment display list does not issue a texture macro
    # for that row in this static listing.
    references["texture"].update(expected["texture"])
    for display in graph["display_lists"]:
        for command in display["commands"]:
            for arg in command["args"]:
                marker = re.fullmatch(r"@(display_list|vertex_group|texture):([0-9a-fA-F]+)", arg)
                if marker:
                    kind, encoded = marker.groups()
                    handle = int(encoded, 16)
                    if handle not in expected[kind]:
                        raise PreparationError(f"{model_name}: {kind} command handle does not resolve: {arg}")
                    references[kind].add(handle)
    graph["handle_audit"] = {kind: {"declared": len(values), "referenced": len(references[kind]), "unused": len(values - references[kind])} for kind, values in expected.items()}


def _parse_model_vertices(source: str, model_name: str) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    pattern = re.compile(r"^Vertex\s+Vertex_0x([0-9A-Fa-f]+)\s*\[[^]]+\]\s*=\s*\{", re.M)
    for group_id, match in enumerate(pattern.finditer(source)):
        body = _body_between(source, match.start())
        rows = _top_level_brace_rows(body)
        for local_id, row in enumerate(rows):
            nested = _top_level_brace_rows(row)
            if len(nested) != 1:
                raise PreparationError(f"{model_name}: malformed Vertex row in Vertex_0x{int(match.group(1), 16):x}")
            xyz = _split_top_level(nested[0])
            tail = [value for value in _split_top_level(row[row.find("}") + 1 :]) if value]
            if len(xyz) != 3 or len(tail) < 7:
                raise PreparationError(f"{model_name}: incomplete Vertex row in Vertex_0x{int(match.group(1), 16):x}")
            values = [parse_int(item) for item in (*xyz, *tail[:7])]
            result.append(
                {
                    "group_id": group_id,
                    "group_handle": _resource_handle(model_name, "vertex_group", f"Vertex_0x{int(match.group(1), 16):x}"),
                    "local_id": local_id,
                    "x": values[0], "y": values[1], "z": values[2],
                    "index": values[3], "s": values[4], "t": values[5],
                    "r": values[6] & 0xFF, "g": values[7] & 0xFF, "b": values[8] & 0xFF, "a": values[9] & 0xFF,
                    # Vertex's fourth byte is a color/normal union.  Preserve
                    # the raw four bytes in both views and mark the union as
                    # unresolved rather than inventing a normal.
                    "nx": values[6] & 0xFF, "ny": values[7] & 0xFF, "nz": values[8] & 0xFF, "nflag": values[9] & 0xFF,
                    "attribute_flags": 0,
                }
            )
    if not result:
        raise PreparationError(f"{model_name}: no Vertex arrays found")
    return result


def _append_dlprimary_dynamic_vertices(
    source: str,
    model_name: str,
    vertices: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    """Preserve the source vtxallocator tail used by DLPRIMARY/dorottex.

    The portable renderer allocates ``numVertices * 4`` vertices for a
    DisplayListPrimaryRecord, while the authored Vertex array declares only
    the first corner rows. The adjacent PADDING_0x... words are contiguous
    Vertex bytes in the source object and are consumed by dorottex before the
    GDL is called. Keep those words as explicit source-order vertices rather
    than allowing the native decoder to read past the sidecar group.
    """
    record_pattern = re.compile(
        r"ModelRoData_DisplayListPrimaryRecord\s+[A-Za-z0-9_]+\s*=\s*\{",
        re.M,
    )
    for record_match in record_pattern.finditer(source):
        values = _split_top_level(_body_between(source, record_match.start()))
        if len(values) < 3:
            raise PreparationError(f"{model_name}: malformed DisplayListPrimaryRecord")
        num_vertices = parse_int(values[0])
        vertex_name = values[1].lstrip("&")
        group_handle = _resource_handle(model_name, "vertex_group", vertex_name)
        existing = [vertex for vertex in vertices if vertex["group_handle"] == group_handle]
        required = max(0, num_vertices * 4 - len(existing))
        if required == 0:
            continue
        array_match = re.search(
            rf"^Vertex\s+{re.escape(vertex_name)}\s*\[[^]]+\]\s*=\s*\{{",
            source,
            re.M,
        )
        if array_match is None:
            raise PreparationError(f"{model_name}: DLPRIMARY vertex array is missing: {vertex_name}")
        array_end = array_match.end() + len(_body_between(source, array_match.start()))
        padding_match = re.search(
            r"^u32\s+PADDING_0x[0-9A-Fa-f]+\s*\[\s*(\d+)\s*\]\s*=\s*\{",
            source[array_end:],
            re.M,
        )
        if padding_match is None:
            raise PreparationError(f"{model_name}: DLPRIMARY vertex tail padding is missing")
        padding_start = array_end + padding_match.start()
        padding_words = _split_top_level(_body_between(source, padding_start))
        raw_words = [parse_int(word) & 0xFFFF_FFFF for word in padding_words]
        required_words = required * 4
        if len(raw_words) < required_words:
            raise PreparationError(
                f"{model_name}: DLPRIMARY vertex tail has {len(raw_words)} words, expected {required_words}"
            )
        group_id = existing[0]["group_id"] if existing else max((v["group_id"] for v in vertices), default=-1) + 1
        next_local = len(existing)
        tail_vertices: list[dict[str, Any]] = []
        for index in range(required):
            blob = b"".join(word.to_bytes(4, "big") for word in raw_words[index * 4 : index * 4 + 4])
            def signed(offset: int) -> int:
                return int.from_bytes(blob[offset : offset + 2], "big", signed=True)
            tail_vertices.append({
                "group_id": group_id,
                "group_handle": group_handle,
                "local_id": next_local + index,
                "x": signed(0), "y": signed(2), "z": signed(4), "index": signed(6),
                "s": signed(8), "t": signed(10),
                "r": blob[12], "g": blob[13], "b": blob[14], "a": blob[15],
                "nx": blob[12], "ny": blob[13], "nz": blob[14], "nflag": blob[15],
                "attribute_flags": 0,
            })
        insert_at = max(
            (index for index, vertex in enumerate(vertices) if vertex["group_handle"] == group_handle),
            default=len(vertices) - 1,
        ) + 1
        vertices[insert_at:insert_at] = tail_vertices
    return vertices


def _parse_rareware_vertices(source: str, model_name: str) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    pattern = re.compile(r"^Vtx\s+([A-Za-z0-9_]+)\s*\[\]\s*=\s*\{", re.M)
    for group_id, match in enumerate(pattern.finditer(source)):
        body = _body_between(source, match.start())
        rows = _top_level_brace_rows(body)
        for local_id, row in enumerate(rows):
            values = [parse_int(item) for item in _split_top_level(row)]
            if len(values) < 10:
                raise PreparationError(f"{model_name}: malformed Vtx row in {match.group(1)}")
            result.append(
                {
                    "group_id": group_id,
                    "group_handle": _resource_handle(model_name, "vertex_group", match.group(1)),
                    "local_id": local_id,
                    "x": values[0], "y": values[1], "z": values[2],
                    "index": values[3], "s": values[4], "t": values[5],
                    "r": values[6] & 0xFF, "g": values[7] & 0xFF, "b": values[8] & 0xFF, "a": values[9] & 0xFF,
                    "nx": values[6] & 0xFF, "ny": values[7] & 0xFF, "nz": values[8] & 0xFF, "nflag": values[9] & 0xFF,
                    "attribute_flags": 0,
                }
            )
    if not result:
        raise PreparationError(f"{model_name}: no Vtx arrays found")
    return result


def _parse_display_lists(source: str, model_name: str) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    vertex_ranges: list[tuple[int, int]] = []
    vertex_counts = {match.group(1): int(match.group(2)) for match in re.finditer(r"^#define\s+(VERTEXGROUPCOUNT\d+)\s+(\d+)", source, re.M)}
    for match in re.finditer(r"^Vertex\s+Vertex_0x([0-9A-Fa-f]+)\s*\[([^]]+)\]", source, re.M):
        vertex_ranges.append((int(match.group(1), 16), vertex_counts.get(match.group(2).strip(), 0)))
    pattern = re.compile(r"^Gfx\s+([A-Za-z0-9_]+)\s*\[\]\s*=\s*\{", re.M)
    for dl_id, match in enumerate(pattern.finditer(source)):
        name = match.group(1)
        body = _body_between(source, match.start())
        commands: list[dict[str, Any]] = []
        cleaned = _strip_comments_preserve(body)
        events: list[tuple[int, str, str, bool]] = [(position, macro, args, False) for position, macro, args in _iter_macro_calls_with_positions(cleaned)]
        for match in re.finditer(r"\{\s*\{\s*([^,{}]+)\s*,\s*([^{}]+)\s*\}\s*\}", cleaned):
            context = body[max(0, match.start() - 120) : match.end() + 180]
            try:
                raw_w0 = parse_int(match.group(1))
            except ValueError as error:
                raise PreparationError(f"{model_name}: rawGfx w0 is not numeric") from error
            if (raw_w0 >> 24) not in (0xF5, 0xF2):
                raise PreparationError(f"{model_name}: rawGfx opcode family is not SETTILE/SETTILESIZE")
            if "gsDPSetTile" not in context and "gsDPSetTileSize" not in context:
                raise PreparationError(f"{model_name}: rawGfx initializer is outside the guarded tile families")
            events.append((match.start(), "rawGfx", f"{match.group(1)},{match.group(2)}", True))
        events.sort(key=lambda event: event[0])
        for ordinal, (_, macro, args_text, is_raw_gfx) in enumerate(events):
            args = []
            for index, value in enumerate(_split_top_level(args_text)):
                kind_hint = None if is_raw_gfx else _command_arg_kind(macro, index)
                if kind_hint == "vertex_group" and not re.search(r"(?:^|&)(?:Vertex_[0-9A-Za-z_]+|verts[A-Za-z0-9_]+)$", value.strip()):
                    # Character display lists stage vertices through the
                    # dynamic 0x04 segment. Preserve that as an address token;
                    # static Vertex_*/verts* symbols use joinable group handles.
                    try:
                        numeric_address = parse_int(value.strip()) & 0x00FF_FFFF
                    except ValueError:
                        numeric_address = -1
                    containing_vertex = next((base for base, count in vertex_ranges if base <= numeric_address < base + count * 16), None)
                    if containing_vertex is not None:
                        value = f"Vertex_0x{containing_vertex:x}"
                    else:
                        kind_hint = "address"
                args.append(_canonicalize_token(model_name, value, kind_hint))
            semantic = f"{macro}({','.join(args)})"
            original = f"{macro}({_canonicalize_text(model_name, args_text)})"
            commands.append(
                {
                    "dl_id": dl_id,
                    "ordinal": ordinal,
                    "macro": macro,
                    "macro_handle": fnv32(macro),
                    "args": args,
                    "semantic": semantic,
                    "source_hash": hashlib.sha256(original.encode("utf-8")).digest(),
                }
            )
        if not commands:
            raise PreparationError(f"{model_name}: display list {name} contains no commands")
        result.append({"id": dl_id, "name": name, "handle": _resource_handle(model_name, "display_list", name), "commands": commands})
    if not result:
        raise PreparationError(f"{model_name}: no display lists found")
    return result


def build_model_graph(source: bytes, model_name: str, parsed: dict[str, Any], payload_specs: dict[int, dict[str, Any]] | None = None, tlut_specs: dict[str, dict[str, Any]] | None = None) -> dict[str, Any]:
    raw_text = source.decode("utf-8")
    text = _strip_comments(raw_text)
    nodes = _parse_model_nodes_graph(text, model_name)
    display_lists = _parse_display_lists(raw_text, model_name)
    vertices = _append_dlprimary_dynamic_vertices(
        text, model_name, _parse_model_vertices(text, model_name)
    )
    has_dlprimary = "ModelRoData_DisplayListPrimaryRecord" in text
    if len(nodes) != parsed["node_count"] or len(display_lists) != parsed["display_list_count"] or (not has_dlprimary and len(vertices) != parsed["vertex_total"]):
        raise PreparationError(f"{model_name}: graph counts do not match source summary")
    node_by_offset = {node["source_offset"]: node["id"] for node in nodes}
    display_ids_source = {display_list["name"]: display_list["id"] for display_list in display_lists}
    for node in nodes:
        record_type = _record_type(text, node["data"])
        node["record_type"] = record_type
        node["record_semantic"] = _canonicalize_text(model_name, _record_initializer(text, node["data"]), True)
        node["primary_dl_id"] = GESM_NULL
        node["secondary_dl_id"] = GESM_NULL
        if record_type in {
            "ModelRoData_DisplayListRecord",
            "ModelRoData_DisplayList_CollisionRecord",
            "ModelRoData_DisplayListPrimaryRecord",
        }:
            metadata, semantic, primary_id, secondary_id = _display_list_metadata(text, model_name, node, display_ids_source)
            node["meta_values"] = metadata
            node["record_semantic"] = semantic
            node["primary_dl_id"] = primary_id
            node["secondary_dl_id"] = secondary_id
        elif record_type == "ModelRoData_SwitchRecord":
            metadata, semantic = _switch_metadata(text, node, node_by_offset)
            node["meta_values"] = metadata
            node["record_semantic"] = semantic
        elif record_type == "ModelRoData_BSPRecord":
            metadata, semantic = _bsp_metadata(text, node, node_by_offset)
            node["meta_values"] = metadata
            node["record_semantic"] = semantic
        else:
            node["meta_values"] = [0] * 9

    # Reassign display-list IDs in source traversal order.  The compiler can
    # then walk Nintendo's BSP/child chain without falling back to all lists.
    traversal_nodes = _node_traversal_order(nodes)
    traversal_dl_names: list[str] = []
    for node_id in traversal_nodes:
        node = nodes[node_id]
        if node["primary_dl_id"] != GESM_NULL:
            name = display_lists[node["primary_dl_id"]]["name"]
            if name not in traversal_dl_names:
                traversal_dl_names.append(name)
    for display_list in display_lists:
        if display_list["name"] not in traversal_dl_names:
            traversal_dl_names.append(display_list["name"])
    new_id_by_name = {name: index for index, name in enumerate(traversal_dl_names)}
    display_lists = [next(display for display in display_lists if display["name"] == name) for name in traversal_dl_names]
    for display_id, display_list in enumerate(display_lists):
        display_list["id"] = display_id
        for command in display_list["commands"]:
            command["dl_id"] = display_id
    for node in nodes:
        if node["primary_dl_id"] != GESM_NULL:
            old_name = next(display["name"] for display in _parse_display_lists(raw_text, model_name) if display["id"] == node["primary_dl_id"])
            node["primary_dl_id"] = new_id_by_name[old_name]
        if node["secondary_dl_id"] != GESM_NULL:
            old_name = next(display["name"] for display in _parse_display_lists(raw_text, model_name) if display["id"] == node["secondary_dl_id"])
            node["secondary_dl_id"] = new_id_by_name[old_name]
        if node.get("record_type") in {
            "ModelRoData_DisplayListRecord",
            "ModelRoData_DisplayList_CollisionRecord",
            "ModelRoData_DisplayListPrimaryRecord",
        }:
            node["meta_values"][0] = node["primary_dl_id"]
            node["meta_values"][1] = node["secondary_dl_id"]
    graph = {"nodes": nodes, "display_lists": display_lists, "vertices": vertices, "textures": parsed["textures"], "rareware": False, "unsupported_macros": [], "payload_specs": payload_specs or {}, "tlut_specs": tlut_specs or {}}
    _validate_graph_handles(model_name, graph)
    return graph


def build_rareware_graph(source: bytes, payload_specs: dict[int, dict[str, Any]] | None = None, model_name: str = "rarewarelogo") -> dict[str, Any]:
    raw_text = source.decode("utf-8")
    text = _strip_comments(raw_text)
    display_lists = _parse_display_lists(raw_text, model_name)
    vertices = _parse_rareware_vertices(text, model_name)
    textures = [{"index": index, "resource": name, "width": 32, "height": 32, "mip_tiles": 6 if name in {"imgRAre_0x0020", "img_raRE_0x0AE0", "imgWAre_0x15A0", "imgwaRE_0x2060"} else 1, "type": 0, "depth": 2, "s_flags": 0, "t_flags": 0} for index, name in enumerate(re.findall(r"^u32\s+([A-Za-z0-9_]+)\[\]\s*=", text, re.M))]
    graph = {"nodes": [], "display_lists": display_lists, "vertices": vertices, "textures": textures, "rareware": True, "unsupported_macros": [], "payload_specs": payload_specs or {}}
    _validate_graph_handles(model_name, graph)
    return graph


def _catalog_record_id(catalog: "Catalog", category: str, name: str) -> int:
    for record in catalog.records:
        if record["category"] == category and record["name"] == name:
            return int(record["id"])
    raise PreparationError(f"GESM payload record is missing: {category}/{name}")


def _sidecar_string(strings: bytearray, string_map: dict[bytes, tuple[int, int]], value: str) -> tuple[int, int]:
    data = value.encode("utf-8")
    existing = string_map.get(data)
    if existing is not None:
        return existing
    offset = len(strings)
    strings.extend(data)
    result = (offset, len(data))
    string_map[data] = result
    return result


def _u64_halves(digest: bytes) -> tuple[int, int]:
    return int.from_bytes(digest[:4], "little"), int.from_bytes(digest[4:8], "little")


def _build_sidecar_sections(catalog: "Catalog", model_name: str, family: str, source: bytes, graph: dict[str, Any]) -> tuple[bytes, dict[str, Any]]:
    strings = bytearray()
    string_map: dict[bytes, tuple[int, int]] = {}
    nodes = bytearray()
    scalars = bytearray()
    display_lists = bytearray()
    commands = bytearray()
    tokens = bytearray()
    vertices = bytearray()
    textures = bytearray()
    mips = bytearray()
    tluts = bytearray()
    sidecar_model = model_name

    node_count = len(graph["nodes"])
    node_by_source = {node["source_offset"]: node["id"] for node in graph["nodes"]}

    def add_scalar(owner_id: int, kind: str, semantic: str, flags: int = 0, meta_values: Iterable[int] = ()) -> int:
        text_offset, text_size = _sidecar_string(strings, string_map, semantic)
        digest = hashlib.sha256(semantic.encode("utf-8")).digest()
        hash_lo, hash_hi = _u64_halves(digest)
        index = len(scalars) // GESM_SCALAR.size
        meta = list(meta_values)[:9]
        meta.extend([0] * (9 - len(meta)))
        scalars.extend(GESM_SCALAR.pack(owner_id, fnv32(kind), flags, text_offset, text_size, *[value & 0xFFFF_FFFF for value in meta], hash_lo | (hash_hi << 32)))
        return index

    for node in graph["nodes"]:
        scalar_index = add_scalar(node["id"], node.get("record_type", "node_record"), node.get("record_semantic", node.get("data", "")), meta_values=node.get("meta_values", ()))
        nodes.extend(
            GESM_NODE.pack(
                node["id"], node["opcode_handle"], node["data_handle"],
                node.get("parent", GESM_NULL), node.get("next", GESM_NULL),
                node.get("prev", GESM_NULL), node.get("child", GESM_NULL),
                scalar_index, 1, node.get("primary_dl_id", GESM_NULL), node.get("secondary_dl_id", GESM_NULL), fnv32(f"{sidecar_model}:node-meta:{node['id']}:{node.get('record_type', 'node_record')}"),
            )
        )

    for display_list in graph["display_lists"]:
        command_index = len(commands) // GESM_COMMAND.size
        name_offset, name_size = _sidecar_string(strings, string_map, _canonicalize_token(sidecar_model, display_list["name"]))
        for command in display_list["commands"]:
            token_index = len(tokens) // GESM_TOKEN.size
            for arg in command["args"]:
                value, token_flag, token_kind = _numeric_or_handle(sidecar_model, arg)
                arg_offset, arg_size = _sidecar_string(strings, string_map, arg)
                digest = hashlib.sha256(arg.encode("utf-8")).digest()
                hash_lo, hash_hi = _u64_halves(digest)
                tokens.extend(GESM_TOKEN.pack(token_kind, value & 0xFFFF_FFFF, token_flag, arg_offset, arg_size, hash_lo | (hash_hi << 32)))
            semantic_offset, semantic_size = _sidecar_string(strings, string_map, command["semantic"])
            source_lo, source_hi = _u64_halves(command["source_hash"])
            commands.extend(
                GESM_COMMAND.pack(
                    display_list["id"], command["ordinal"], command["macro_handle"],
                    token_index, len(command["args"]), semantic_offset, semantic_size,
                    0, source_lo, source_hi, 0, 0,
                )
            )
        display_lists.extend(
            GESM_DISPLAY_LIST.pack(
                display_list["id"], display_list["handle"], command_index,
                len(display_list["commands"]), name_offset, name_size, 0, 0,
            )
        )

    for vertex_id, vertex in enumerate(graph["vertices"]):
        vertices.extend(
            GESM_VERTEX.pack(
                vertex["group_id"], vertex_id, vertex["group_handle"], vertex.get("attribute_flags", 0),
                vertex["x"], vertex["y"], vertex["z"], vertex["s"], vertex["t"], vertex["index"],
                vertex["r"], vertex["g"], vertex["b"], vertex["a"],
                vertex["nx"], vertex["ny"], vertex["nz"], vertex["nflag"],
                vertex_id, 0, 0, 0,
            )
        )

    for texture in graph["textures"]:
        texture_index = int(texture["index"])
        resource = str(texture["resource"])
        resource_handle = _texture_handle(model_name, resource)
        payload_spec = graph.get("payload_specs", {}).get(texture_index)
        if payload_spec:
            payload_record_id = _catalog_record_id(catalog, "texture_payload", payload_spec["texture_payload_name"])
            source_offset = int(payload_spec.get("source_offset", 0))
            source_span = int(payload_spec.get("source_span", 0))
            source_row_handle = int(payload_spec.get("source_row_handle", _resource_handle(model_name, "texture_row", resource)))
            mip_levels = int(payload_spec.get("mip_levels", max(1, int(texture.get("mip_tiles", 1)))) )
        else:
            # Symbolic IMAGE_* rows point to the exact decoded global image
            # stream, never to the source Model.c listing.
            image_name = resource.removeprefix("IMAGE_") if resource.startswith("IMAGE_") else resource
            payload_record_id = _catalog_record_id(catalog, "texture_payload", f"{image_name}.payload")
            image_record_id = _catalog_record_id(catalog, "image_stream", image_name)
            image_record = next(record for record in catalog.records if record["id"] == image_record_id)
            source_offset = int(image_record.get("metadata", {}).get("source_offset", 0))
            source_span = int(image_record["raw_size"])
            source_row_handle = _resource_handle(model_name, "texture_row", image_name)
            mip_levels = max(1, int(texture.get("mip_tiles", 1)))
        mip_index = len(mips) // GESM_MIP.size
        tlut_index = len(tluts) // GESM_TLUT.size
        for level in range(mip_levels):
            if payload_spec:
                level_spec = payload_spec["levels"][level]
                mip_payload = int(level_spec["record_id"])
                level_width = int(level_spec["width"])
                level_height = int(level_spec["height"])
                level_offset = int(level_spec["source_offset"])
                level_record = next(record for record in catalog.records if record["id"] == mip_payload)
            else:
                image_name = resource.removeprefix("IMAGE_") if resource.startswith("IMAGE_") else resource
                mip_payload = payload_record_id if level == 0 else _catalog_record_id(catalog, "mip_payload", f"{image_name}.mip.{level}")
                level_record = next(record for record in catalog.records if record["id"] == mip_payload)
                level_width = int(level_record.get("metadata", {}).get("width", max(1, int(texture["width"]) >> level)))
                level_height = int(level_record.get("metadata", {}).get("height", max(1, int(texture["height"]) >> level)))
                level_offset = 0
            mips.extend(GESM_MIP.pack(texture_index, level, level_width, level_height, resource_handle, mip_payload, payload_record_id, level_offset, source_row_handle, int(level_record["raw_size"]), int(level_record["decoded_size"]), 0))
        tlut_payload = 0
        tlut_spec = None
        if not payload_spec and resource.startswith("IMAGE_"):
            tlut_spec = graph.get("tlut_specs", {}).get(resource.removeprefix("IMAGE_"))
        if tlut_spec:
            tlut_payload = _catalog_record_id(catalog, "tlut_payload", tlut_spec["name"])
            tlut_record = next(record for record in catalog.records if record["id"] == tlut_payload)
            tluts.extend(GESM_TLUT.pack(texture_index, resource_handle, tlut_payload, payload_record_id, source_offset, source_row_handle, int(tlut_record["raw_size"]), 0))
        textures.extend(
            GESM_TEXTURE.pack(
                texture_index, resource_handle, texture["width"], texture["height"], mip_levels,
                texture.get("type", 0), texture.get("depth", 0), texture.get("s_flags", 0), texture.get("t_flags", 0),
                payload_record_id, mip_index, mip_levels, tlut_index if tlut_payload else GESM_NULL,
                source_offset, source_row_handle, source_span,
            )
        )

    section_records = [nodes, scalars, display_lists, commands, tokens, vertices, textures, mips, tluts]
    counts = [
        len(graph["nodes"]), len(scalars) // GESM_SCALAR.size, len(graph["display_lists"]),
        len(commands) // GESM_COMMAND.size, len(tokens) // GESM_TOKEN.size, len(graph["vertices"]),
        len(graph["textures"]), len(mips) // GESM_MIP.size, len(tluts) // GESM_TLUT.size,
    ]
    record_count = sum(counts)
    flags = GESM_FLAG_RAREWARE if graph["rareware"] else 0
    source_digest = hashlib.sha256(source).digest()
    strings_bytes = bytes(strings)
    total_bytes = GESM_HEADER.size + sum(len(section) for section in section_records) + len(strings_bytes)
    zero_header = GESM_HEADER.pack(
        GESM_MAGIC, GESM_VERSION, fnv32(f"model:{model_name}"), flags, total_bytes, record_count,
        counts[0], counts[1], counts[2], counts[3], counts[4], counts[5], counts[6], counts[7], counts[8], len(strings_bytes),
        source_digest, bytes(32), 0,
    )
    body = b"".join(bytes(section) for section in section_records) + strings_bytes
    packet_digest = hashlib.sha256(zero_header + body).digest()
    header = GESM_HEADER.pack(
        GESM_MAGIC, GESM_VERSION, fnv32(f"model:{model_name}"), flags, total_bytes, record_count,
        counts[0], counts[1], counts[2], counts[3], counts[4], counts[5], counts[6], counts[7], counts[8], len(strings_bytes),
        source_digest, packet_digest, 0,
    )
    metadata = {
        "name": model_name,
        "family": family,
        "path": f"{model_name}.gesm",
        "packet_sha256": packet_digest.hex(),
        "source_sha256": source_digest.hex(),
        "bytes": total_bytes,
        "record_count": record_count,
        "nodes": counts[0], "scalars": counts[1], "display_lists": counts[2], "commands": counts[3],
        "tokens": counts[4], "vertices": counts[5], "textures": counts[6], "mips": counts[7], "tluts": counts[8],
        "raw_gfx": sum(1 for display in graph["display_lists"] for command in display["commands"] if command["macro"] == "rawGfx"),
        "unsupported_macros": graph.get("unsupported_macros", []),
        "handle_audit": graph.get("handle_audit", {}),
    }
    return header + body, metadata


def verify_sidecar(sidecar_path: Path) -> dict[str, Any]:
    data = sidecar_path.read_bytes()
    if len(data) < GESM_HEADER.size:
        raise PreparationError(f"GESM sidecar is truncated: {sidecar_path}")
    fields = GESM_HEADER.unpack_from(data, 0)
    magic, version, model_handle, flags, total_bytes, record_count, node_count, scalar_count, display_list_count, command_count, token_count, vertex_count, texture_count, mip_count, tlut_count, string_bytes, source_digest, packet_digest, reserved = fields
    if magic != GESM_MAGIC or version != GESM_VERSION or reserved != 0:
        raise PreparationError(f"GESM header identity/reserved mismatch: {sidecar_path}")
    expected_size = GESM_HEADER.size + node_count * GESM_NODE.size + scalar_count * GESM_SCALAR.size + display_list_count * GESM_DISPLAY_LIST.size + command_count * GESM_COMMAND.size + token_count * GESM_TOKEN.size + vertex_count * GESM_VERTEX.size + texture_count * GESM_TEXTURE.size + mip_count * GESM_MIP.size + tlut_count * GESM_TLUT.size + string_bytes
    if total_bytes != expected_size or len(data) != total_bytes:
        raise PreparationError(f"GESM bounds mismatch: {sidecar_path}")
    body_offset = GESM_HEADER.size
    canonical_header = GESM_HEADER.pack(*fields[:17], bytes(32), reserved)
    if hashlib.sha256(canonical_header + data[GESM_HEADER.size:]).digest() != packet_digest:
        raise PreparationError(f"GESM packet SHA-256 mismatch: {sidecar_path}")
    if record_count != node_count + scalar_count + display_list_count + command_count + token_count + vertex_count + texture_count + mip_count + tlut_count:
        raise PreparationError(f"GESM record count mismatch: {sidecar_path}")
    sections: dict[str, tuple[int, int]] = {}
    for name, count, record_size in (
        ("nodes", node_count, GESM_NODE.size), ("scalars", scalar_count, GESM_SCALAR.size),
        ("display_lists", display_list_count, GESM_DISPLAY_LIST.size), ("commands", command_count, GESM_COMMAND.size),
        ("tokens", token_count, GESM_TOKEN.size), ("vertices", vertex_count, GESM_VERTEX.size),
        ("textures", texture_count, GESM_TEXTURE.size), ("mips", mip_count, GESM_MIP.size),
        ("tluts", tlut_count, GESM_TLUT.size),
    ):
        size = count * record_size
        sections[name] = (body_offset, size)
        body_offset += size
    string_offset = body_offset
    strings = data[string_offset : string_offset + string_bytes]
    if len(strings) != string_bytes:
        raise PreparationError(f"GESM string bounds mismatch: {sidecar_path}")
    try:
        string_text = strings.decode("utf-8")
    except UnicodeDecodeError as error:
        raise PreparationError(f"GESM semantic string table is not UTF-8: {sidecar_path}") from error
    if re.search(r"(?:^|[,(])&[A-Za-z_]", string_text):
        raise PreparationError(f"GESM semantic string table contains an unlowered address/pointer: {sidecar_path}")

    def string_bounds(offset: int, size: int) -> None:
        if offset + size > len(strings):
            raise PreparationError(f"GESM string reference exceeds bounds: {sidecar_path}")

    node_data = data[sections["nodes"][0] : sections["nodes"][0] + sections["nodes"][1]]
    node_values = [GESM_NODE.unpack_from(node_data, index * GESM_NODE.size) for index in range(node_count)]
    for values in node_values:
        for ref in values[3:7]:
            if ref != GESM_NULL and ref >= node_count:
                raise PreparationError(f"GESM node relationship out of bounds: {sidecar_path}")
        if values[7] + values[8] > scalar_count:
            raise PreparationError(f"GESM node scalar range out of bounds: {sidecar_path}")
        for display_ref in values[9:11]:
            if display_ref != GESM_NULL and display_ref >= display_list_count:
                raise PreparationError(f"GESM node display-list ownership is out of bounds: {sidecar_path}")
        if values[11] == 0:
            raise PreparationError(f"GESM node metadata handle is missing: {sidecar_path}")
    scalar_data = data[sections["scalars"][0] : sections["scalars"][0] + sections["scalars"][1]]
    for index in range(scalar_count):
        values = GESM_SCALAR.unpack_from(scalar_data, index * GESM_SCALAR.size)
        string_bounds(values[3], values[4])
    dl_data = data[sections["display_lists"][0] : sections["display_lists"][0] + sections["display_lists"][1]]
    for index in range(display_list_count):
        values = GESM_DISPLAY_LIST.unpack_from(dl_data, index * GESM_DISPLAY_LIST.size)
        if values[2] + values[3] > command_count:
            raise PreparationError(f"GESM display-list command range out of bounds: {sidecar_path}")
        string_bounds(values[4], values[5])
    command_data = data[sections["commands"][0] : sections["commands"][0] + sections["commands"][1]]
    for index in range(command_count):
        values = GESM_COMMAND.unpack_from(command_data, index * GESM_COMMAND.size)
        if values[0] >= display_list_count or values[3] + values[4] > token_count:
            raise PreparationError(f"GESM command/token range out of bounds: {sidecar_path}")
        string_bounds(values[5], values[6])
    token_data = data[sections["tokens"][0] : sections["tokens"][0] + sections["tokens"][1]]
    display_handles = {GESM_DISPLAY_LIST.unpack_from(dl_data, index * GESM_DISPLAY_LIST.size)[1] for index in range(display_list_count)}
    texture_data = data[sections["textures"][0] : sections["textures"][0] + sections["textures"][1]]
    texture_handles = {GESM_TEXTURE.unpack_from(texture_data, index * GESM_TEXTURE.size)[1] for index in range(texture_count)}
    vertex_data = data[sections["vertices"][0] : sections["vertices"][0] + sections["vertices"][1]]
    vertex_handles = {GESM_VERTEX.unpack_from(vertex_data, index * GESM_VERTEX.size)[2] for index in range(vertex_count)}
    address_handles: set[int] = set()
    token_handle_sets = {fnv32("display_list"): display_handles, fnv32("texture"): texture_handles, fnv32("vertex_group"): vertex_handles, fnv32("address"): address_handles}
    for index in range(token_count):
        values = GESM_TOKEN.unpack_from(token_data, index * GESM_TOKEN.size)
        string_bounds(values[3], values[4])
        if values[0] == fnv32("address"):
            address_handles.add(values[1])
        if values[0] in token_handle_sets and values[1] not in token_handle_sets[values[0]]:
            raise PreparationError(f"GESM typed command handle does not resolve: {sidecar_path}")
    for index in range(texture_count):
        values = GESM_TEXTURE.unpack_from(texture_data, index * GESM_TEXTURE.size)
        if values[9] == 0 or values[10] + values[11] > mip_count:
            raise PreparationError(f"GESM texture payload/mip range is invalid: {sidecar_path}")
    return {
        "packet_sha256": packet_digest.hex(), "source_sha256": source_digest.hex(), "model_handle": model_handle,
        "record_count": record_count, "nodes": node_count, "scalars": scalar_count, "display_lists": display_list_count,
        "commands": command_count, "tokens": token_count, "vertices": vertex_count, "textures": texture_count,
        "mips": mip_count, "tluts": tlut_count, "flags": flags,
    }


def write_sidecar(catalog: "Catalog", model_name: str, family: str, source: bytes, graph: dict[str, Any]) -> dict[str, Any]:
    packet, metadata = _build_sidecar_sections(catalog, model_name, family, source, graph)
    output_path = catalog.output / f"{model_name}.gesm"
    output_path.write_bytes(packet)
    verified = verify_sidecar(output_path)
    metadata.update(verified)
    metadata["path"] = output_path.name
    raw_gfx_count = int(metadata.pop("raw_gfx", 0))
    catalog.sidecar_raw_gfx[model_name] = raw_gfx_count
    if not hasattr(catalog, "sidecars"):
        catalog.sidecars = []
    catalog.sidecars.append(metadata)
    return metadata


def parse_legal_text_count(source: bytes) -> int:
    text = source.decode("utf-8")
    match = re.search(r"legalpage_text_array\[\]\s*=\s*\{(.*?)\n\};", text, re.S)
    if not match:
        raise PreparationError("legalpage_text_array is missing from front.c")
    count = len(re.findall(r"\{\s*[-+0-9]+\s*,\s*[-+0-9]+\s*,", match.group(1)))
    if count != 12:
        raise PreparationError(f"legal source string count {count} != guarded 12")
    return count


def parse_image_stream_format(source: bytes) -> tuple[int, int]:
    """Return the source stream format/compression IDs used by image packets."""
    header = source[:4]
    if len(header) < 4:
        raise PreparationError("image stream is truncated")
    # The PD stream format IDs are the same values used by the existing GETI
    # packet.  Keep this small parser independent of runtime code.
    return header[0], header[1]


def _flip_rgba8_source_order(pixels: bytes, width: int, height: int) -> bytes:
    row_bytes = width * 4
    if len(pixels) != row_bytes * height:
        raise PreparationError("PD decoded RGBA8 payload size does not match dimensions")
    return b"".join(pixels[row * row_bytes : (row + 1) * row_bytes] for row in range(height - 1, -1, -1))


def decode_image_stream(root: Path, source_path: Path, source: bytes, destination: Path) -> tuple[bytes, dict[str, Any], list[dict[str, Any]]]:
    """Decode a PD stream with the bounded source decoder.

    The returned level list is source ordered and contains every authored
    explicit level.  The inspection bytes are retained separately so callers
    can inspect a conventional top-left image without changing upload bytes.
    ``root`` remains an explicit argument to keep the preparation API stable;
    the decoder itself consumes only copied stream bytes.
    """
    del root
    try:
        from goldeneye_pd_image_decoder_v6 import PDDecodeError, decode_stream
    except ImportError as error:
        raise PreparationError("source PD image decoder is unavailable") from error
    try:
        decoded = decode_stream(source, flip=False)
        inspection = decode_stream(source, flip=True)
    except PDDecodeError as error:
        raise PreparationError(f"source PD decoder rejected {source_path}") from error
    if len(decoded.images) != len(inspection.images):
        raise PreparationError(f"source/inspection level count mismatch for {source_path}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.with_suffix(".raw").write_bytes(source)
    levels: list[dict[str, Any]] = []
    for image, inspected in zip(decoded.images, inspection.images):
        if (image.width, image.height) != (inspected.width, inspected.height):
            raise PreparationError(f"source/inspection dimensions mismatch for {source_path} level {image.level}")
        output_path = destination.with_suffix(".decoded" if image.level == 0 else f".mip{image.level}.decoded")
        inspection_path = destination.with_suffix(".inspection.decoded" if image.level == 0 else f".mip{image.level}.inspection.decoded")
        output_path.write_bytes(image.rgba8)
        inspection_path.write_bytes(inspected.rgba8)
        levels.append({
            "level": image.level,
            "width": image.width,
            "height": image.height,
            "decoded": image.rgba8,
            "inspection": inspected.rgba8,
            "storage": image.storage,
            "decoded_path": output_path.name,
            "inspection_path": inspection_path.name,
            "source_explicit": decoded.explicit_lods,
        })
    if not levels:
        raise PreparationError(f"source PD decoder emitted no levels for {source_path}")
    metadata = {
        "stream_format": int(decoded.format),
        "stream_compression": int(decoded.images[0].compression),
        "width": decoded.width,
        "height": decoded.height,
        "explicit_lods": bool(decoded.explicit_lods),
        "encoded_lods": int(decoded.encoded_lods),
        "source_level_count": len(levels),
        "source_order": "source",
        "inspection_order": "vertical_flip",
        "source_sha256": decoded.source_sha256,
    }
    return levels[0]["decoded"], metadata, levels


class _PDBitReader:
    def __init__(self, data: bytes):
        self.data = data
        self.offset = 0
        self.buffer = 0
        self.bits = 0

    def read(self, count: int) -> int:
        if count < 0 or count > 24:
            raise PreparationError("PD bit count is outside the bounded decoder")
        while self.bits < count:
            if self.offset >= len(self.data):
                raise PreparationError("PD bitstream ended during SELECTFILE decode")
            self.buffer = (self.buffer << 8) | self.data[self.offset]
            self.offset += 1
            self.bits += 8
        value = (self.buffer >> (self.bits - count)) & ((1 << count) - 1 if count else 0)
        self.bits -= count
        self.buffer &= (1 << self.bits) - 1 if self.bits else 0
        return value


def _pd_huffman_decode(reader: _PDBitReader, frequencies: list[int], count: int) -> list[int]:
    nodes = [[-1, -1] for _ in range(2048)]
    freq = list(frequencies) + [9999] * (2048 - len(frequencies))
    symbol_count = len(frequencies)
    minfreq1 = minfreq2 = 9999
    minindex1 = minindex2 = 0
    for index in range(symbol_count):
        if freq[index] < minfreq1:
            if minfreq2 < minfreq1:
                minfreq1, minindex1 = freq[index], index
            else:
                minfreq2, minindex2 = freq[index], index
        elif freq[index] < minfreq2:
            minfreq2, minindex2 = freq[index], index
    root_index = -1
    while minfreq1 != 9999 and minfreq2 != 9999:
        total = minfreq1 + minfreq2
        if total == 0:
            total = 1
        freq[minindex1] = 9999
        freq[minindex2] = 9999
        if nodes[minindex1][0] < 0 and nodes[minindex1][1] < 0:
            nodes[minindex1][0] = minindex1 + 10000
            root_index = minindex1
            freq[minindex1] = total
            nodes[minindex1][1] = minindex2 + 10000 if nodes[minindex2][0] < 0 and nodes[minindex2][1] < 0 else minindex2
        elif nodes[minindex2][0] < 0 and nodes[minindex2][1] < 0:
            nodes[minindex2][0] = minindex2 + 10000
            root_index = minindex2
            freq[minindex2] = total
            nodes[minindex2][1] = minindex1 + 10000 if nodes[minindex1][0] < 0 and nodes[minindex1][1] < 0 else minindex1
        else:
            root_index = next((candidate for candidate in range(2048) if nodes[candidate][0] < 0 and nodes[candidate][1] < 0 and freq[candidate] >= 9999), -1)
            if root_index < 0:
                raise PreparationError("PD Huffman tree exceeded bounded node capacity")
            freq[root_index] = total
            nodes[root_index][0] = minindex1
            nodes[root_index][1] = minindex2
        minfreq1 = minfreq2 = 9999
        for index in range(symbol_count):
            if freq[index] < minfreq1:
                if minfreq1 > minfreq2:
                    minfreq1, minindex1 = freq[index], index
                else:
                    minfreq2, minindex2 = freq[index], index
            elif freq[index] < minfreq2:
                minfreq2, minindex2 = freq[index], index
    if root_index < 0:
        raise PreparationError("PD Huffman tree has no root")
    output: list[int] = []
    for _ in range(count):
        index = root_index
        depth = 0
        while index < 10000:
            if index < 0 or index >= len(nodes) or depth >= 2048:
                raise PreparationError("PD Huffman symbol traversal exceeded bounds")
            index = nodes[index][reader.read(1)]
            depth += 1
        if index < 10000 or index >= 10000 + symbol_count:
            raise PreparationError("PD Huffman leaf is outside the lookup table")
        output.append(index - 10000)
    return output


def _decode_pd_ia8_huffman_lookup(source: bytes, width: int, height: int) -> bytes:
    """Decode the source IA8/Huffman-lookup SELECTFILE stream.

    The existing tex2png utility returns an all-zero image for this verified
    row.  This bounded implementation follows the source texInflateHuffman,
    texBuildLookup and texInflateLookupFromBuffer semantics directly.
    """
    reader = _PDBitReader(source)
    explicit_lods = reader.read(1)
    is_zlib = reader.read(1)
    lod = reader.read(6)
    if explicit_lods or is_zlib or lod != 0:
        raise PreparationError("SELECTFILE PD stream is not the guarded non-zlib single-image form")
    format_id = reader.read(4)
    decoded_width = reader.read(8)
    decoded_height = reader.read(8)
    compression = reader.read(4)
    if (format_id, compression, decoded_width, decoded_height) != (5, 6, width, height):
        raise PreparationError("SELECTFILE PD format/compression/dimensions changed")
    colour_count = reader.read(11)
    if colour_count <= 0 or colour_count > 2048:
        raise PreparationError("SELECTFILE lookup table count is outside the guard")
    lookup = [reader.read(8) for _ in range(colour_count)]
    frequencies = [reader.read(8) for _ in range(colour_count)]
    symbols = _pd_huffman_decode(reader, frequencies, width * height)
    values = [lookup[symbol] for symbol in symbols]
    pixels = bytearray()
    for value in values:
        intensity = (value >> 4) * 17
        alpha = (value & 0x0F) * 17
        pixels.extend((intensity, intensity, intensity, alpha))
    if not any(pixels):
        raise PreparationError("SELECTFILE source decoder still produced an all-zero image")
    return bytes(pixels)


def _extract_pd_palette(source: bytes) -> tuple[bytes, bytes, dict[str, Any]] | None:
    """Extract the exact embedded TLUT from a zlib PD CI stream."""
    try:
        from goldeneye_pd_image_decoder_v6 import PDDecodeError, extract_palette
    except ImportError as error:
        raise PreparationError("source PD image decoder is unavailable") from error
    try:
        palette = extract_palette(source)
    except PDDecodeError as error:
        raise PreparationError("source PD palette extraction failed") from error
    if palette is None:
        return None
    raw, decoded, format_id = palette
    return raw, decoded, {
        "format": int(format_id),
        "entries": len(raw) // 2,
        "source_offset": 3,
    }


@dataclass
class Catalog:
    root: Path
    output: Path
    records: list[dict[str, Any]] = field(default_factory=list)
    blobs: list[bytes] = field(default_factory=list)
    blob_offsets: dict[str, tuple[int, int]] = field(default_factory=dict)
    sidecars: list[dict[str, Any]] = field(default_factory=list)
    sidecar_raw_gfx: dict[str, int] = field(default_factory=dict)

    def blob(self, data: bytes) -> tuple[int, int]:
        digest = sha256_hex(data)
        existing = self.blob_offsets.get(digest)
        if existing is not None:
            return existing
        offset = sum(len(item) for item in self.blobs)
        self.blobs.append(data)
        self.blob_offsets[digest] = (offset, len(data))
        return offset, len(data)

    def add(
        self,
        *,
        family: str,
        category: str,
        name: str,
        source_path: str,
        source: bytes,
        raw: bytes,
        decoded: bytes,
        metadata: dict[str, Any] | None = None,
        rom: dict[str, Any] | None = None,
        flags: Iterable[str] = (),
    ) -> dict[str, Any]:
        source_digest = sha256_hex(source)
        raw_digest = sha256_hex(raw)
        decoded_digest = sha256_hex(decoded)
        raw_offset, raw_size = self.blob(raw)
        decoded_offset, decoded_size = self.blob(decoded)
        record = {
            "id": len(self.records) + 1,
            "family": family,
            "category": category,
            "name": name,
            "source_path": source_path,
            "source_sha256": source_digest,
            "raw_sha256": raw_digest,
            "decoded_sha256": decoded_digest,
            "source_size": len(source),
            "raw_size": len(raw),
            "decoded_size": len(decoded),
            "raw_payload_offset": raw_offset,
            "decoded_payload_offset": decoded_offset,
            "flags": sorted(set(flags)),
            "metadata": metadata or {},
        }
        if rom:
            record.update(rom)
        self.records.append(record)
        return record

    def add_source(self, **kwargs: Any) -> dict[str, Any]:
        source = kwargs.pop("source")
        return self.add(source=source, raw=source, decoded=source, **kwargs)


def _write_source_blob(output: Path, category: str, name: str, raw: bytes, decoded: bytes) -> None:
    safe = re.sub(r"[^A-Za-z0-9_.-]+", "_", name)
    directory = output / "payloads" / category
    directory.mkdir(parents=True, exist_ok=True)
    (directory / f"{safe}.raw").write_bytes(raw)
    (directory / f"{safe}.decoded").write_bytes(decoded)


def _extract_direct_texture_payloads(root: Path, model_name: str, source_text: str, blob: bytes) -> dict[int, dict[str, Any]]:
    """Slice embedded model texels and decode every declared mip level."""
    try:
        from prepare_native_title_textures import bytes_per_pixel, decode_direct, model_rows, texture_commands
    except ImportError as error:
        raise PreparationError("direct texture decoder is unavailable") from error
    rows = model_rows(source_text)
    commands = texture_commands(source_text)
    direct_offsets = sorted(resource_id & 0x00FFFFFF for _, resource_id, *_ in rows if not (resource_id & 0x80000000))
    results: dict[int, dict[str, Any]] = {}
    for row_index, row in enumerate(rows):
        token, resource_id, width, height, mip, type_value, depth, s_flags, t_flags = row
        if resource_id & 0x80000000:
            continue
        source_offset = resource_id & 0x00FFFFFF
        if source_offset not in commands:
            raise PreparationError(f"{model_name}: no texture-image command for {token} at 0x{source_offset:x}")
        fmt, command_size, _command_load_bytes = commands[source_offset]
        storage_size = {0: 0, 1: 1, 2: 2, 3: 3}.get(depth)
        if storage_size is None:
            raise PreparationError(f"{model_name}: unsupported texture depth for {token}: {depth}")
        numerator, denominator = bytes_per_pixel(storage_size)
        levels = max(1, int(mip))
        level_specs: list[dict[str, Any]] = []
        span = (width * height * numerator + denominator - 1) // denominator
        if levels > 1:
            following = [offset for offset in direct_offsets if offset > source_offset]
            span = (min(following) - source_offset) if following else len(blob) - source_offset
        if source_offset + span > len(blob) or span <= 0:
            raise PreparationError(f"{model_name}: embedded texture span exceeds model blob for {token}")
        raw_span = blob[source_offset : source_offset + span]
        cursor = 0
        for level in range(levels):
            level_width = max(1, width >> level)
            level_height = max(1, height >> level)
            level_bytes = (level_width * level_height * numerator + denominator - 1) // denominator
            if cursor + level_bytes > len(raw_span):
                raise PreparationError(f"{model_name}: mip level {level} exceeds source span for {token}")
            raw_level = raw_span[cursor : cursor + level_bytes]
            pixels = decode_direct(raw_level, level_width, level_height, fmt, storage_size)
            level_specs.append({"level": level, "width": level_width, "height": level_height, "raw": raw_level, "decoded": pixels, "source_offset": source_offset + cursor})
            cursor += level_bytes
        results[row_index] = {
            "resource": token,
            "source_offset": source_offset,
            "source_span": span,
            "source_row_handle": _resource_handle(model_name, "texture_row", token),
            "raw": raw_span,
            "decoded": b"".join(level["decoded"] for level in level_specs),
            "levels": level_specs,
            "width": width,
            "height": height,
            "mip_levels": levels,
            "type": type_value,
            "depth": depth,
            "s_flags": s_flags,
            "t_flags": t_flags,
            "format": fmt,
            "size": storage_size,
        }
    return results


def _add_direct_texture_payload_records(catalog: Catalog, model_name: str, source: bytes, payloads: dict[int, dict[str, Any]]) -> dict[int, dict[str, Any]]:
    metadata: dict[int, dict[str, Any]] = {}
    payload_family = model_name if model_name in {"legalpage", "nintendologo", "goldeneyelogo", "walletbond", "headbrosnansuit", "suitbond", "chrwppk"} else f"cast_{model_name}"
    for texture_index, payload in payloads.items():
        texture_name = f"{model_name}.texture_payload.{texture_index}"
        texture_record = catalog.add(
            family=payload_family, category="texture_payload", name=texture_name,
            source_path=f"assets/obseg/{'prop' if model_name in {'legalpage','nintendologo','goldeneyelogo','walletbond','chrwppk'} else 'chr'}/{model_name}/Model.c",
            source=source, raw=payload["raw"], decoded=payload["decoded"],
            metadata={"source_offset": payload["source_offset"], "source_span": payload["source_span"], "width": payload["width"], "height": payload["height"], "mip_levels": payload["mip_levels"], "source_row": payload["resource"]},
            flags=("EMBEDDED_TEXELS", "DECODED_RGBA8_LEVELS"),
        )
        levels: list[dict[str, Any]] = []
        for level in payload["levels"]:
            mip_name = f"{model_name}.texture.{texture_index}.mip.{level['level']}"
            mip_record = catalog.add(
                family=payload_family, category="mip_payload", name=mip_name,
                source_path=texture_record["source_path"], source=source,
                raw=level["raw"], decoded=level["decoded"],
                metadata={"texture_index": texture_index, "level": level["level"], "source_offset": level["source_offset"], "source_row": payload["resource"], "width": level["width"], "height": level["height"]},
                flags=("EMBEDDED_MIP", "DECODED_RGBA8"),
            )
            levels.append({"name": mip_name, "record_id": mip_record["id"], **{key: value for key, value in level.items() if key not in ("raw", "decoded")}})
        metadata[texture_index] = {key: value for key, value in payload.items() if key not in ("raw", "decoded", "levels")} | {"texture_payload_name": texture_name, "texture_record_id": texture_record["id"], "levels": levels}
    return metadata


def _prepare_generated_text(root: Path, output: Path) -> tuple[Path, Path]:
    script = root / "scripts/prepare_native_title_text.py"
    if not script.is_file():
        raise PreparationError(f"title text preparation script is missing: {script}")
    try:
        subprocess.run(
            [sys.executable, str(script), "--project-root", str(root), "--output-root", str(output / "derived"), "--report", str(output / "derived/native-title-text-report.txt")],
            check=True,
            cwd=str(root),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise PreparationError("source font/text packet preparation failed") from error
    getf = output / "derived/title-font.getf"
    getc = output / "derived/LtitleE.gecat"
    if not getf.is_file() or not getc.is_file():
        raise PreparationError("source font/text packet outputs are incomplete")
    return getf, getc


def _prepare_icon_decoder(root: Path, output: Path) -> Path:
    script = root / "scripts/prepare_native_title_icons.py"
    if not script.is_file():
        raise PreparationError(f"title icon preparation script is missing: {script}")
    try:
        subprocess.run(
            [sys.executable, str(script), "--project-root", str(root), "--output-root", str(output / "derived"), "--report", str(output / "derived/native-title-icons-report.txt")],
            check=True,
            cwd=str(root),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise PreparationError("source icon packet preparation failed") from error
    packet = output / "derived/title-icons.geti"
    if not packet.is_file():
        raise PreparationError("source icon packet output is incomplete")
    return packet


def _prepare_rom_dependency(catalog: Catalog, root: Path, rom: Path, key: str, family: str, category: str, name: str, source_path: str, source: bytes, output_name: str, row: str, flags: Iterable[str] = ()) -> dict[str, Any]:
    raw, decoded, info = extract_rom_row(root, rom, row, catalog.output / "payloads" / "rom" / output_name)
    _write_source_blob(catalog.output, category, output_name, raw, decoded)
    record = catalog.add(family=family, category=category, name=name, source_path=source_path, source=source, raw=raw, decoded=decoded, rom=info, flags=(*flags, "ROM_PREPARED"))
    # Preparation-only sidecar lowering needs the decompressed model/blob
    # bytes.  Keep them out of the manifest record; they are consumed
    # immediately to create exact texture payload records.
    return {"record": record, "_raw_bytes": raw, "_decoded_bytes": decoded}


def _add_model(catalog: Catalog, root: Path, rom: Path, spec: dict[str, Any], rows: dict[str, str], image_sources: dict[str, bytes], image_mip_levels: dict[str, int], texture_payload_specs: dict[str, dict[int, dict[str, Any]]]) -> dict[str, Any]:
    source = guarded_source(root, spec["path"])
    parsed = parse_model_listing(source, spec["name"])
    model_dependency = _prepare_rom_dependency(catalog, root, rom, spec["rom"], spec["family"], "model", spec["name"], spec["path"], source, spec["name"], rows[spec["rom"]], flags=("EMBEDDED_MODEL",))
    if not any(texture["resource"].startswith("IMAGE_") for texture in parsed["textures"]):
        direct_payloads = _extract_direct_texture_payloads(root, spec["name"], source.decode("utf-8"), model_dependency["_decoded_bytes"])
        texture_payload_specs[spec["name"]] = _add_direct_texture_payload_records(catalog, spec["name"], source, direct_payloads)
    # Enumerate the source hierarchy as independent records while retaining
    # one deduplicated source listing blob in the envelope.
    for node in parsed["nodes"]:
        category = "switch" if node["opcode"] == "MODELNODE_OPCODE_SWITCH" else "node"
        catalog.add_source(family=spec["family"], category=category, name=f"{spec['name']}.node.0x{node['offset']:x}", source_path=spec["path"], source=source, metadata=node, flags=("SOURCE_HIERARCHY",))
    for display_list in parsed["display_lists"]:
        catalog.add_source(family=spec["family"], category="display_list", name=display_list, source_path=spec["path"], source=source, metadata={"reachable": True}, flags=("SOURCE_DISPLAY_LIST",))
    for group in parsed["vertex_groups"]:
        catalog.add_source(family=spec["family"], category="vertex_group", name=f"{spec['name']}.{group['name']}", source_path=spec["path"], source=source, metadata=group, flags=("SOURCE_VERTEX_GROUP",))
    for texture in parsed["textures"]:
        mip_levels = max(1, texture["mip_tiles"])
        texture_meta = dict(texture)
        texture_meta["mip_levels"] = mip_levels
        catalog.add_source(family=spec["family"], category="texture", name=f"{spec['name']}.texture.{texture['index']}", source_path=spec["path"], source=source, metadata=texture_meta, flags=("EMBEDDED_TEXTURE_ROW",))
        for level in range(mip_levels):
            catalog.add_source(family=spec["family"], category="mip", name=f"{spec['name']}.texture.{texture['index']}.mip.{level}", source_path=spec["path"], source=source, metadata={"texture_index": texture["index"], "level": level}, flags=("SOURCE_MIP_LEVEL",))
        resource = texture["resource"]
        image_name = resource.removeprefix("IMAGE_") if resource.startswith("IMAGE_") else None
        if image_name:
            image_sources.setdefault(image_name, source)
            image_mip_levels[image_name] = max(image_mip_levels.get(image_name, 1), max(1, texture["mip_tiles"]))
        if texture["type"] in (4, 5) or texture["resource"].startswith("IMAGE_") and texture["depth"] in (0, 1):
            # The source image stream is retained separately below; this
            # record explicitly marks the palette/TLUT dependency rather than
            # silently baking it into a texture row.
            catalog.add_source(family=spec["family"], category="tlut", name=f"{spec['name']}.texture.{texture['index']}.tlut", source_path=spec["path"], source=source, metadata={"texture_index": texture["index"], "palette_source": image_name or resource}, flags=("TLUT_DEPENDENCY",))
    catalog.add_source(family=spec["family"], category="model_manifest", name=f"{spec['name']}.manifest", source_path=spec["path"], source=source, metadata={"counts": parsed}, flags=("COUNT_GUARD",))
    return parsed


def _downsample_rgba8(pixels: bytes, width: int, height: int) -> tuple[int, int, bytes]:
    next_width = max(1, width // 2)
    next_height = max(1, height // 2)
    output = bytearray(next_width * next_height * 4)
    for y in range(next_height):
        for x in range(next_width):
            samples = []
            for dy in (0, 1):
                for dx in (0, 1):
                    sx = min(width - 1, x * 2 + dx)
                    sy = min(height - 1, y * 2 + dy)
                    offset = (sy * width + sx) * 4
                    samples.append(pixels[offset : offset + 4])
            offset = (y * next_width + x) * 4
            for channel in range(4):
                output[offset + channel] = sum(sample[channel] for sample in samples) // len(samples)
    return next_width, next_height, bytes(output)


def _add_image_streams(catalog: Catalog, root: Path, output: Path, image_names: Iterable[str], source_owners: dict[str, bytes], image_mip_levels: dict[str, int], image_tlut_specs: dict[str, dict[str, Any]]) -> int:
    image_root = root / "assets/images/split"
    # The frontend always needs these seven rows even when no model texture
    # references them directly.
    required = {"COPYICON", "DELICON", "SELECTFILE", "CROSSHAIR1", "CHECK", "DOT", "X"}
    names = sorted(set(image_names) | required)
    decoded_count = 0
    for name in names:
        path = image_root / f"{name}.bin"
        if not path.is_file():
            raise PreparationError(f"required global image stream is missing: assets/images/split/{name}.bin")
        source = path.read_bytes()
        expected = IMAGE_SOURCE_HASH_GUARDS.get(name)
        if expected and sha256_hex(source) != expected:
            raise PreparationError(f"global image source SHA-256 mismatch for {name}")
        pixels, metadata, decoded_levels = decode_image_stream(
            root, path, source, output / "payloads" / "images" / name
        )
        if not any(pixels) and name in {"COPYICON", "DELICON", "SELECTFILE", "CROSSHAIR1", "CHECK", "DOT", "X"}:
            raise PreparationError(f"visible frontend image {name} decoded to all zero pixels")
        requested_levels = max(1, image_mip_levels.get(name, 1))
        if metadata["explicit_lods"] and requested_levels != len(decoded_levels):
            raise PreparationError(
                f"global image {name} authored mip count {len(decoded_levels)} does not match source texture request {requested_levels}"
            )
        levels = list(decoded_levels)
        if not metadata["explicit_lods"] and requested_levels > len(levels):
            try:
                from goldeneye_pd_image_decoder_v6 import generate_source_mips
                generated = generate_source_mips(source, requested_levels, flip=False)
                generated_inspection = generate_source_mips(source, requested_levels, flip=True)
            except Exception as error:
                raise PreparationError(f"source-generated mip lowering failed for {name}") from error
            if len(generated) != requested_levels or len(generated_inspection) != requested_levels:
                raise PreparationError(f"source-generated mip count mismatch for {name}")
            levels = []
            output_base = output / "payloads" / "images" / name
            for image, inspected in zip(generated, generated_inspection):
                decoded_path = output_base.with_suffix(".decoded" if image.level == 0 else f".mip{image.level}.decoded")
                inspection_path = output_base.with_suffix(".inspection.decoded" if image.level == 0 else f".mip{image.level}.inspection.decoded")
                decoded_path.write_bytes(image.rgba8)
                inspection_path.write_bytes(inspected.rgba8)
                levels.append({
                    "level": image.level,
                    "width": image.width,
                    "height": image.height,
                    "decoded": image.rgba8,
                    "inspection": inspected.rgba8,
                    "storage": image.storage,
                    "decoded_path": decoded_path.name,
                    "inspection_path": inspection_path.name,
                    "source_explicit": False,
                    "source_generated": image.level > 0,
                })
        if len(levels) != requested_levels:
            raise PreparationError(f"global image {name} produced {len(levels)} levels, expected {requested_levels}")
        metadata = {
            **metadata,
            "mip_levels": len(levels),
            "source_level_count": len(decoded_levels),
            "derived_level_count": len(levels) - len(decoded_levels),
            "source_offset": 0,
            "source_row": name,
        }
        _write_source_blob(output, "image", name, source, pixels)
        image_record = catalog.add(family="frontend", category="image_stream", name=name, source_path=relative_path(root, path), source=source, raw=source, decoded=pixels, metadata={**metadata, "image_stream_order": "source"}, flags=("GLOBAL_IMAGE", "DECODED_BASE_LEVEL", "PROVENANCE_ONLY", "SOURCE_ORDER_RGBA8"))
        catalog.add(family="frontend", category="texture_payload", name=f"{name}.payload", source_path=relative_path(root, path), source=source, raw=source, decoded=pixels, metadata={**metadata, "image_stream_record_id": image_record["id"], "image_stream_order": "source"}, flags=("GLOBAL_TEXTURE_PAYLOAD", "DECODED_RGBA8_BASE_LEVEL", "SOURCE_ORDER_RGBA8"))
        palette = _extract_pd_palette(source)
        if palette is not None:
            palette_raw, palette_decoded, palette_metadata = palette
            palette_name = f"{name}.tlut"
            palette_record = catalog.add(family="frontend", category="tlut_payload", name=palette_name, source_path=relative_path(root, path), source=source, raw=palette_raw, decoded=palette_decoded, metadata={**palette_metadata, "source_row": name}, flags=("PD_TLUT", "DECODED_RGBA8_ENTRIES"))
            image_tlut_specs[name] = {"name": palette_name, "record_id": palette_record["id"], **palette_metadata}
        for level_data in levels[1:]:
            level = int(level_data["level"])
            mip_record = catalog.add(
                family="frontend", category="mip_payload", name=f"{name}.mip.{level}",
                source_path=relative_path(root, path), source=source,
                raw=bytes(level_data["storage"]), decoded=bytes(level_data["decoded"]),
                metadata={
                    "texture_index": 0,
                    "level": level,
                    "source_offset": 0,
                    "source_row": name,
                    "width": int(level_data["width"]),
                    "height": int(level_data["height"]),
                    "source_explicit": bool(level_data.get("source_explicit", False)),
                    "source_generated": bool(level_data.get("source_generated", False)),
                    "source_order": "source",
                    "inspection_order": "vertical_flip",
                    "source_storage_sha256": sha256_hex(bytes(level_data["storage"])),
                },
                flags=("GLOBAL_IMAGE_MIP", "SOURCE_AUTHORED_MIP" if level_data.get("source_explicit", False) else "SOURCE_GENERATED_MIP", "DECODED_RGBA8", "SOURCE_ORDER_RGBA8"),
            )
        decoded_count += sum(len(bytes(level_data["decoded"])) for level_data in levels)
    return decoded_count


def _add_rareware(catalog: Catalog, root: Path, rom: Path, rows: dict[str, str]) -> dict[str, Any]:
    source_path = "assets/rarewarelogo.c"
    source = guarded_source(root, source_path)
    parsed = parse_rareware_listing(source)
    _prepare_rom_dependency(catalog, root, rom, "rarewarelogo", "rareware", "rom_asset", "rarewarelogo.bin", source_path, source, "rarewarelogo", rows["rarewarelogo"], flags=("RAREWARE_BINARY",))
    catalog.add_source(family="rareware", category="source_listing", name="rarewarelogo.c", source_path=source_path, source=source, metadata={"counts": parsed}, flags=("HAND_AUTHORED_RAREWARE",))
    rareware_payload_specs: dict[int, dict[str, Any]] = {}
    text = _strip_comments(source.decode("utf-8"))
    texture_arrays = []
    for array_index, (array_name, body) in enumerate(re.findall(r"^u32\s+([A-Za-z0-9_]+)\[\]\s*=\s*\{(.*?)\n\};", text, re.M | re.S)):
        words = [int(value, 16) for value in re.findall(r"0x([0-9A-Fa-f]+)", body)]
        raw = b"".join(value.to_bytes(4, "big") for value in words)
        mip_levels = 6 if array_name in parsed["texture_image_order"] else 1
        # The source comments identify both terminal arrays as RGBA16 32x32.
        # D_02004FE8 contains an additional source tail; keep that tail in a
        # separate provenance record while exposing exactly one 32x32 texture.
        width, height = 32, 32
        levels: list[dict[str, Any]] = []
        cursor = 0
        for level in range(mip_levels):
            level_width = max(1, width >> level)
            level_height = max(1, height >> level)
            level_bytes = level_width * level_height * 2
            if cursor + level_bytes > len(raw):
                raise PreparationError(f"rareware texture {array_name} mip {level} exceeds source array")
            raw_level = raw[cursor : cursor + level_bytes]
            decoded = bytearray()
            for offset in range(0, len(raw_level), 2):
                pixel = int.from_bytes(raw_level[offset : offset + 2], "big")
                decoded.extend((((pixel >> 11) & 0x1F) * 255 // 31, ((pixel >> 6) & 0x1F) * 255 // 31, ((pixel >> 1) & 0x1F) * 255 // 31, 255 if pixel & 1 else 0))
            levels.append({"level": level, "width": level_width, "height": level_height, "raw": raw_level, "decoded": bytes(decoded), "source_offset": cursor})
            cursor += level_bytes
        texel_raw = raw[:cursor]
        tail = raw[cursor:]
        payload = {
            "resource": array_name, "source_offset": 0, "source_span": len(raw),
            "source_row_handle": _resource_handle("rarewarelogo", "texture_row", array_name),
            "raw": texel_raw, "decoded": b"".join(level["decoded"] for level in levels),
            "levels": levels, "width": width, "height": height, "mip_levels": mip_levels,
            "type": 0, "depth": 2, "s_flags": 0, "t_flags": 0,
        }
        texture_record = catalog.add(family="rareware", category="texture_payload", name=f"{array_name}.payload", source_path=source_path, source=source, raw=payload["raw"], decoded=payload["decoded"], metadata={"source_offset": 0, "source_span": len(raw), "source_row": array_name, "width": width, "height": height, "mip_levels": mip_levels}, flags=("RAREWARE_TEXELS", "DECODED_RGBA8_LEVELS"))
        if tail:
            catalog.add(family="rareware", category="rareware_array_tail", name=f"{array_name}.tail", source_path=source_path, source=source, raw=tail, decoded=tail, metadata={"source_offset": cursor, "source_span": len(tail), "source_row": array_name}, flags=("RAREWARE_SOURCE_TAIL",))
        level_meta = []
        for level in levels:
            mip_name = f"{array_name}.mip.{level['level']}"
            mip_record = catalog.add(family="rareware", category="mip_payload", name=mip_name, source_path=source_path, source=source, raw=level["raw"], decoded=level["decoded"], metadata={"texture_index": array_index, "level": level["level"], "source_offset": level["source_offset"], "source_row": array_name, "width": level["width"], "height": level["height"]}, flags=("RAREWARE_MIP", "DECODED_RGBA8"))
            level_meta.append({"name": mip_name, "record_id": mip_record["id"], **{key: value for key, value in level.items() if key not in ("raw", "decoded")}})
        payload["texture_payload_name"] = f"{array_name}.payload"
        payload["texture_record_id"] = texture_record["id"]
        payload["levels"] = level_meta
        rareware_payload_specs[array_index] = {key: value for key, value in payload.items() if key not in ("raw", "decoded")}
    for name in parsed["texture_arrays"]:
        levels = 6 if name in parsed["texture_image_order"] else 1
        catalog.add_source(family="rareware", category="texture", name=name, source_path=source_path, source=source, metadata={"levels": levels, "format": "RGBA16"}, flags=("RAREWARE_TEXTURE",))
        for level in range(levels):
            catalog.add_source(family="rareware", category="mip", name=f"{name}.mip.{level}", source_path=source_path, source=source, metadata={"texture": name, "level": level}, flags=("RAREWARE_MIP",))
    for name in parsed["display_lists"]:
        catalog.add_source(family="rareware", category="display_list", name=name, source_path=source_path, source=source, flags=("RAREWARE_DISPLAY_LIST",))
    for name in parsed["vertex_arrays"]:
        catalog.add_source(family="rareware", category="vertex_group", name=name, source_path=source_path, source=source, flags=("RAREWARE_GEOMETRY",))
    parsed["payload_specs"] = rareware_payload_specs
    return parsed


def _add_source_dependencies(catalog: Catalog, root: Path, rom: Path, rows: dict[str, str], text_packets: tuple[Path, Path]) -> dict[str, int]:
    front_source = guarded_source(root, "src/game/front.c")
    title_source = guarded_source(root, "src/game/title.c")
    legal_strings = parse_legal_text_count(front_source)
    blood_source = guarded_source(root, "src/game/blood_animation.c")
    catalog.add_source(family="legal", category="text", name="legal_screen_text_array", source_path="src/game/front.c", source=front_source, metadata={"string_count": legal_strings}, flags=("SOURCE_TEXT",))
    catalog.add_source(family="gunbarrel", category="blood", name="die_blood_image_1", source_path="src/game/blood_animation.c", source=blood_source, metadata={"width": 80, "height": 96, "format": "I4_ENCRYPTED_SOURCE"}, flags=("BLOOD_SOURCE", "RLE_OR_ENCRYPTED"))
    catalog.add_source(family="gunbarrel", category="background", name="gunbarrel_render_path", source_path="src/game/title.c", source=title_source, metadata={"rom_asset": "gunbarrel_background"}, flags=("SOURCE_RENDER_PATH",))
    _prepare_rom_dependency(catalog, root, rom, "gunbarrel_background", "gunbarrel", "background", "gunbarrel-background", "src/game/title.c", title_source, "gunbarrel-background", rows["gunbarrel_background"], flags=("RLE_BACKGROUND",))
    for path in ("assets/embedded/skeletons/standard_gun.inc.c", "assets/embedded/skeletons/gun_kf7.inc.c"):
        source = guarded_source(root, path)
        catalog.add_source(family="gunbarrel", category="weapon_animation", name=Path(path).stem, source_path=path, source=source, metadata={"contains_muzzle_nodes": True}, flags=("SKELETON_SOURCE", "MUZZLE_FLASH_DEPENDENCY"))
    # Global tables remain their own category.  They are not folded into
    # wallet texture rows or into the decoded image payloads.
    for path in ("assets/images.def", "assets/image_externs.h"):
        source = guarded_source(root, path)
        catalog.add_source(family="frontend", category="global_image_table", name=Path(path).name, source_path=path, source=source, flags=("GLOBAL_IMAGE_TABLE",))
    zurich = guarded_source(root, "assets/font/fontZurichBold.c")
    bank = guarded_source(root, "assets/font/fontBankGothic.c")
    font_dl = guarded_source(root, "assets/font_dl.c")
    font_data = guarded_source(root, "assets/font_chardatae.c")
    catalog.add_source(family="frontend", category="font", name="fontZurichBold", source_path="assets/font/fontZurichBold.c", source=zurich, metadata={"glyph_count": 94}, flags=("FONT_SOURCE",))
    catalog.add_source(family="frontend", category="font", name="fontBankGothic", source_path="assets/font/fontBankGothic.c", source=bank, flags=("FONT_SOURCE",))
    catalog.add_source(family="frontend", category="font_display_list", name="font_dl", source_path="assets/font_dl.c", source=font_dl, flags=("FONT_RENDER_SOURCE",))
    catalog.add_source(family="frontend", category="font_chardata", name="font_chardatae", source_path="assets/font_chardatae.c", source=font_data, flags=("FONT_RENDER_SOURCE",))
    text_source = guarded_source(root, "assets/obseg/text/LtitleE.c")
    getf, getc = text_packets
    catalog.add(family="frontend", category="font_packet", name="title-font.getf", source_path="assets/font/fontZurichBold.c", source=zurich, raw=zurich, decoded=getf.read_bytes(), metadata={"glyph_count": 94}, flags=("DERIVED_PACKET",))
    catalog.add(family="frontend", category="text_catalog", name="LtitleE.gecat", source_path="assets/obseg/text/LtitleE.c", source=text_source, raw=text_source, decoded=getc.read_bytes(), metadata={"string_count": 302, "legal_string_count": legal_strings}, flags=("DERIVED_PACKET", "SOURCE_TEXT_CATALOG"))
    for key, path in (
        ("font_zurich_kerning", "assets/font/fontZurichBold_kerning.bin"),
        ("font_zurich_chartable", "assets/font/fontZurichBold_fontchartable.bin"),
        ("font_bank_kerning", "assets/font/fontBankGothic_kerning.bin"),
        ("font_bank_chartable", "assets/font/fontBankGothic_fontchartable.bin"),
        ("jfont_dl", "assets/ge007.u.117880.jfont_dl.bin"),
        ("jfont_chardata", "assets/ge007.u.117940.jfont_chardata.bin"),
        ("efont_chardata", "assets/ge007.u.123040.efont_chardata.bin"),
    ):
        _prepare_rom_dependency(catalog, root, rom, key, "frontend", "font_payload", Path(path).name, path, text_source if "font" not in key else (zurich if "zurich" in key else bank), f"font-{key}", rows[key], flags=("FONT_PAYLOAD",))
    return {"legal_text_strings": legal_strings, "title_catalog_strings": 302}


def _add_audio(catalog: Catalog, root: Path, rom: Path, rows: dict[str, str]) -> int:
    music_source = guarded_source(root, "assets/music/music.s")
    music_header = guarded_source(root, "src/music.h")
    sbk = guarded_source(root, "assets/music/music.sbk")
    catalog.add_source(family="audio", category="source_listing", name="music.s", source_path="assets/music/music.s", source=music_source, flags=("AUDIO_SOURCE",))
    catalog.add_source(family="audio", category="source_header", name="music.h", source_path="src/music.h", source=music_header, metadata={"track_count": 63}, flags=("AUDIO_SOURCE",))
    catalog.add_source(family="audio", category="soundbank", name="music.sbk", source_path="assets/music/music.sbk", source=sbk, flags=("AUDIO_SOURCE",))
    for key, name in (
        ("audio_instruments_ctl", "instruments.ctl"),
        ("audio_instruments_tbl", "instruments.tbl"),
        ("audio_sfx_ctl", "sfx.ctl"),
        ("audio_sfx_tbl", "sfx.tbl"),
        ("audio_intro", "Mintro_eye"),
        ("audio_folders", "Mfolders"),
        ("audio_nintendo_rare", "Mnint_rare_logo"),
    ):
        _prepare_rom_dependency(catalog, root, rom, key, "audio", "sequence" if key.startswith("audio_") and key not in ("audio_instruments_ctl", "audio_instruments_tbl", "audio_sfx_ctl", "audio_sfx_tbl") else "bank", name, "assets/music/music.s", music_source, name, rows[key], flags=("FRONTEND_AUDIO",))
    return 7


def _canonical_manifest(catalog: Catalog, rom_sha1: str, root: Path) -> tuple[bytes, dict[str, Any]]:
    records = sorted(catalog.records, key=lambda record: (record["id"]))
    counts: dict[str, int] = {}
    for record in records:
        counts[record["category"]] = counts.get(record["category"], 0) + 1
    source_concat = b"".join(bytes.fromhex(record["source_sha256"]) for record in records)
    source_catalog_sha = sha256_hex(source_concat)
    manifest: dict[str, Any] = {
        "manifest_version": VERSION,
        "magic": MAGIC.decode("ascii"),
        "goal": "native-boot-menu-attract-120",
        "runtime_rom_access": False,
        "external_rom_sha1": rom_sha1,
        "source_catalog_sha256": source_catalog_sha,
        "counts": counts,
        "records": records,
        "sidecars": sorted(catalog.sidecars, key=lambda sidecar: sidecar["name"]),
        "provenance": {
            "linux_reference_command": REFERENCE_COMMAND,
            "linux_reference_hash_command": REFERENCE_HASH_COMMAND,
            "rom_copied_into_checkout": False,
            "rom_copied_into_bundle": False,
            "private_payloads_copied_into_checkout": False,
            "private_payloads_copied_into_bundle": False,
            "source_paths_are_relative": True,
        },
    }
    encoded = json.dumps(manifest, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return encoded, manifest


def write_packet(catalog: Catalog, rom_sha1: str) -> tuple[Path, dict[str, Any]]:
    manifest_bytes, manifest = _canonical_manifest(catalog, rom_sha1, catalog.root)
    payload = b"".join(catalog.blobs)
    source_bytes = sum(record["source_size"] for record in catalog.records)
    zero_header = HEADER.pack(MAGIC, VERSION, len(catalog.records), len(manifest_bytes), len(payload), source_bytes, 0, bytes.fromhex(manifest["source_catalog_sha256"]), bytes(32), 0)
    packet_hash = hashlib.sha256(zero_header + manifest_bytes + payload).digest()
    header = HEADER.pack(MAGIC, VERSION, len(catalog.records), len(manifest_bytes), len(payload), source_bytes, 0, bytes.fromhex(manifest["source_catalog_sha256"]), packet_hash, 0)
    packet = header + manifest_bytes + payload
    catalog.output.mkdir(parents=True, exist_ok=True)
    packet_path = catalog.output / "source-frontend-v6.gefv"
    temp_path = packet_path.with_suffix(".gefv.tmp")
    temp_path.write_bytes(packet)
    temp_path.replace(packet_path)
    manifest["packet_sha256"] = packet_hash.hex()
    manifest["packet_bytes"] = len(packet)
    manifest["payload_bytes"] = len(payload)
    manifest_path = catalog.output / "source-frontend-v6-manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    lines = [
        "manifest_version=6",
        "magic=GEFV",
        "goal=native-boot-menu-attract-120",
        "status=PASS",
        "runtime_rom_access=false",
        f"external_rom_sha1={rom_sha1}",
        f"source_catalog_sha256={manifest['source_catalog_sha256']}",
        f"packet_sha256={packet_hash.hex()}",
        f"record_count={len(catalog.records)}",
        f"payload_bytes={len(payload)}",
        "rom_copied_into_checkout=false",
        "rom_copied_into_bundle=false",
        "private_payloads_copied_into_checkout=false",
        "private_payloads_copied_into_bundle=false",
        "source_paths_are_relative=true",
    ]
    for key in sorted(manifest["counts"]):
        lines.append(f"count_{key}={manifest['counts'][key]}")
    lines.append(f"sidecar_count={len(manifest['sidecars'])}")
    for sidecar in manifest["sidecars"]:
        lines.append(
            f"sidecar_{sidecar['name']}=path:{sidecar['path']},packet_sha256:{sidecar['packet_sha256']},"
            f"nodes:{sidecar['nodes']},display_lists:{sidecar['display_lists']},commands:{sidecar['commands']},"
            f"vertices:{sidecar['vertices']},textures:{sidecar['textures']},mips:{sidecar['mips']},tluts:{sidecar['tluts']},"
            f"raw_gfx:{catalog.sidecar_raw_gfx.get(sidecar['name'], 0)},"
            f"unsupported_macros:{','.join(sidecar['unsupported_macros']) or 'none'}"
        )
    for record in catalog.records:
        lines.append(
            "entry_{id}={family}:{family},category:{category},name:{name},source:{source_path},source_sha256:{source_sha256},raw_sha256:{raw_sha256},decoded_sha256:{decoded_sha256},raw_size:{raw_size},decoded_size:{decoded_size}".format(**record)
        )
    (catalog.output / "source-frontend-v6-manifest.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return packet_path, manifest


def verify_packet(packet_path: Path) -> dict[str, Any]:
    """Verify envelope bounds, packet hash, payload bounds and every digest."""
    data = packet_path.read_bytes()
    if len(data) < HEADER.size:
        raise PreparationError("GEFV packet is truncated before header")
    magic, version, record_count, manifest_size, payload_size, source_size, flags, source_catalog, packet_digest, reserved = HEADER.unpack_from(data, 0)
    if (magic, version, flags, reserved) != (MAGIC, VERSION, 0, 0):
        raise PreparationError("GEFV header magic/version/reserved mismatch")
    end_manifest = HEADER.size + manifest_size
    end_packet = end_manifest + payload_size
    if end_manifest > len(data) or end_packet != len(data):
        raise PreparationError("GEFV manifest/payload bounds mismatch")
    canonical_header = HEADER.pack(magic, version, record_count, manifest_size, payload_size, source_size, flags, source_catalog, bytes(32), reserved)
    actual_packet_digest = hashlib.sha256(canonical_header + data[HEADER.size:]).digest()
    if actual_packet_digest != packet_digest:
        raise PreparationError("GEFV packet SHA-256 mismatch")
    try:
        manifest = json.loads(data[HEADER.size:end_manifest].decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise PreparationError("GEFV manifest JSON is invalid") from error
    records = manifest.get("records")
    if not isinstance(records, list) or len(records) != record_count:
        raise PreparationError("GEFV record count mismatch")
    if manifest.get("manifest_version") != VERSION or manifest.get("magic") != MAGIC.decode("ascii"):
        raise PreparationError("GEFV manifest identity mismatch")
    if manifest.get("source_catalog_sha256") != source_catalog.hex():
        raise PreparationError("GEFV source catalog hash mismatch")
    payload = data[end_manifest:]
    source_bytes_sum = 0
    for record in records:
        source_bytes_sum += int(record.get("source_size", 0))
        for offset_key, size_key, digest_key in (("raw_payload_offset", "raw_size", "raw_sha256"), ("decoded_payload_offset", "decoded_size", "decoded_sha256")):
            offset = int(record[offset_key])
            size = int(record[size_key])
            if offset < 0 or size < 0 or offset + size > len(payload):
                raise PreparationError(f"GEFV payload bounds mismatch for record {record.get('id')}")
            if sha256_hex(payload[offset : offset + size]) != record[digest_key]:
                raise PreparationError(f"GEFV {digest_key} mismatch for record {record.get('id')}")
    if source_bytes_sum != source_size:
        raise PreparationError("GEFV source byte count mismatch")
    return {
        "packet_sha256": packet_digest.hex(),
        "record_count": record_count,
        "payload_bytes": payload_size,
        "source_catalog_sha256": source_catalog.hex(),
        "manifest": manifest,
    }


def prepare(args: argparse.Namespace) -> tuple[Path, dict[str, Any]]:
    root = args.project_root.resolve()
    output = (args.output_root or root / "build/native/source-frontend-v6").resolve()
    ensure_output_guard(root, output)
    rom, rom_sha1 = verify_external_rom(root, args.rom.resolve())
    rows = filelist_rows(root)
    output.mkdir(parents=True, exist_ok=True)
    catalog = Catalog(root=root, output=output)
    image_sources: dict[str, bytes] = {}
    image_mip_levels: dict[str, int] = {}
    image_tlut_specs: dict[str, dict[str, Any]] = {}
    texture_payload_specs: dict[str, dict[int, dict[str, Any]]] = {}
    model_summaries = {}
    sidecar_specs: list[tuple[str, str, bytes, dict[str, Any]]] = []
    for spec in MODEL_SPECS:
        model_summaries[spec["name"]] = _add_model(catalog, root, rom, spec, rows, image_sources, image_mip_levels, texture_payload_specs)
        model_source = guarded_source(root, spec["path"])
        sidecar_specs.append((spec["name"], spec["family"], model_source, build_model_graph(model_source, spec["name"], model_summaries[spec["name"]], texture_payload_specs.get(spec["name"]))))
    rareware = _add_rareware(catalog, root, rom, rows)
    rareware_source = guarded_source(root, "assets/rarewarelogo.c")
    sidecar_specs.append(("rarewarelogo", "rareware", rareware_source, build_rareware_graph(rareware_source, rareware.get("payload_specs"))))
    text_packets = _prepare_generated_text(root, output)
    _prepare_icon_decoder(root, output)
    dependency_summary = _add_source_dependencies(catalog, root, rom, rows, text_packets)
    # Source ownership is represented by model records, while image streams
    # retain their own exact bytes and decoded pixels.
    decoded_image_bytes = _add_image_streams(catalog, root, output, image_sources.keys(), image_sources, image_mip_levels, image_tlut_specs)
    audio_count = _add_audio(catalog, root, rom, rows)
    for _, _, _, sidecar_graph in sidecar_specs:
        sidecar_graph["tlut_specs"] = image_tlut_specs
    for sidecar_name, sidecar_family, sidecar_source, sidecar_graph in sidecar_specs:
        write_sidecar(catalog, sidecar_name, sidecar_family, sidecar_source, sidecar_graph)
    packet_path, manifest = write_packet(catalog, rom_sha1)
    verified = verify_packet(packet_path)
    manifest["model_summaries"] = model_summaries
    manifest["rareware_summary"] = rareware
    manifest["dependency_summary"] = dependency_summary
    manifest["decoded_image_bytes"] = decoded_image_bytes
    manifest["frontend_audio_dependency_count"] = audio_count
    (output / "source-frontend-v6-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    report_lines = [
        "report_version=1",
        "goal=native-boot-menu-attract-120",
        "status=PASS",
        "runtime_rom_access=false",
        f"external_rom_sha1={rom_sha1}",
        f"packet_sha256={verified['packet_sha256']}",
        f"record_count={verified['record_count']}",
        f"payload_bytes={verified['payload_bytes']}",
        f"legal_text_strings={dependency_summary['legal_text_strings']}",
        f"title_catalog_strings={dependency_summary['title_catalog_strings']}",
        f"rareware_texture_arrays={len(rareware['texture_arrays'])}",
        f"rareware_mip_chains={len(rareware['mip_chains'])}",
        f"rareware_vertex_arrays={len(rareware['vertex_arrays'])}",
        f"frontend_audio_dependencies={audio_count}",
        f"decoded_image_bytes={decoded_image_bytes}",
        f"texture_payload_records={sum(1 for record in catalog.records if record['category'] == 'texture_payload')}",
        f"mip_payload_records={sum(1 for record in catalog.records if record['category'] == 'mip_payload')}",
        f"tlut_payload_records={sum(1 for record in catalog.records if record['category'] == 'tlut_payload')}",
        f"rareware_array_tail_records={sum(1 for record in catalog.records if record['category'] == 'rareware_array_tail')}",
        f"sidecar_count={len(catalog.sidecars)}",
        # This lane proves source/catalog coverage only.  Visible-command
        # lowering is owned by the renderer lane and must not be represented
        # as an acceptance result here.
        "unsupported_visible_command_count=not_evaluated",
        "rom_copied_into_checkout=false",
        "rom_copied_into_bundle=false",
        "private_payloads_copied_into_checkout=false",
        "private_payloads_copied_into_bundle=false",
    ]
    for sidecar in sorted(catalog.sidecars, key=lambda item: item["name"]):
        report_lines.extend(
            [
                f"sidecar_{sidecar['name']}_path={sidecar['path']}",
                f"sidecar_{sidecar['name']}_packet_sha256={sidecar['packet_sha256']}",
                f"sidecar_{sidecar['name']}_nodes={sidecar['nodes']}",
                f"sidecar_{sidecar['name']}_display_lists={sidecar['display_lists']}",
                f"sidecar_{sidecar['name']}_commands={sidecar['commands']}",
                f"sidecar_{sidecar['name']}_vertices={sidecar['vertices']}",
                f"sidecar_{sidecar['name']}_textures={sidecar['textures']}",
                f"sidecar_{sidecar['name']}_mips={sidecar['mips']}",
                f"sidecar_{sidecar['name']}_tluts={sidecar['tluts']}",
                f"sidecar_{sidecar['name']}_raw_gfx={catalog.sidecar_raw_gfx.get(sidecar['name'], 0)}",
                f"sidecar_{sidecar['name']}_unsupported_macros={','.join(sidecar['unsupported_macros']) or 'none'}",
            ]
        )
        for handle_kind, audit in sorted(sidecar.get("handle_audit", {}).items()):
            report_lines.extend(
                [
                    f"sidecar_{sidecar['name']}_handles_{handle_kind}_declared={audit['declared']}",
                    f"sidecar_{sidecar['name']}_handles_{handle_kind}_referenced={audit['referenced']}",
                    f"sidecar_{sidecar['name']}_handles_{handle_kind}_unused={audit['unused']}",
                ]
            )
    for name in sorted(model_summaries):
        summary = model_summaries[name]
        report_lines.extend(
            [
                f"{name}_nodes={len(summary['nodes'])}",
                f"{name}_display_lists={len(summary['display_lists'])}",
                f"{name}_vertex_total={summary['vertex_total']}",
                f"{name}_textures={len(summary['textures'])}",
                f"{name}_switch_nodes={summary['switch_nodes']}",
                f"{name}_switch_records={summary['switch_records']}",
                f"{name}_mip_levels={sum(max(1, texture['mip_tiles']) for texture in summary['textures'])}",
            ]
        )
    (output / "source-frontend-v6-report.txt").write_text("\n".join(report_lines) + "\n", encoding="utf-8")
    return packet_path, manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--rom", type=Path, default=Path(os.environ.get("GOLDENEYE_US_ROM", str(DEFAULT_ROM_PATH))))
    parser.add_argument("--output-root", type=Path, default=None)
    parser.add_argument("--verify", type=Path, default=None, help="verify an existing GEFV packet and do not access the ROM")
    parser.add_argument("--verify-sidecar", type=Path, default=None, help="verify an existing GESM V6 sidecar and do not access the ROM")
    args = parser.parse_args()
    try:
        if args.verify is not None:
            result = verify_packet(args.verify.resolve())
            print("native source frontend V6 packet verify: PASS")
            print(f"packet_sha256={result['packet_sha256']}")
            print(f"record_count={result['record_count']}")
            return 0
        if args.verify_sidecar is not None:
            result = verify_sidecar(args.verify_sidecar.resolve())
            print("native source frontend V6 GESM sidecar verify: PASS")
            print(f"packet_sha256={result['packet_sha256']}")
            print(f"record_count={result['record_count']}")
            return 0
        packet_path, manifest = prepare(args)
    except (OSError, PreparationError, ValueError) as error:
        print(f"native source frontend V6 preparation failed: {error}", file=sys.stderr)
        return 1
    print("native source frontend V6 preparation: PASS")
    print(f"packet={packet_path}")
    print(f"packet_sha256={manifest['packet_sha256']}")
    print(f"record_count={manifest['counts'] and len(manifest['records'])}")
    print("runtime_rom_access=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
