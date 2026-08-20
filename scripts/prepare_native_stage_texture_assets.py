#!/usr/bin/env python3
"""Prepare the source-selected stage texture dependency sidecar.

The stage room mappings do not contain a final ``G_SETTIMG`` for every
material.  The checked-in frontend instead emits the custom F3D ``G_NOOP``
(``0xc0`` in the F3D display-list dialect) consumed by ``texLoadFromGdl``.
Its low 12 bits select an entry in ``g_Textures``; the entry's data offset is
the cumulative ``IMAGE(..., size, ...)`` table offset in the global image
segment.  This helper follows that source path directly:

    room primary/secondary GDL -> G_SETTEX/G_NOOP texture number
      -> g_Textures/images.def entry -> imagelist.u.csv ROM row

It writes only copied, decoded payloads and a fixed-provenance manifest under
ignored ``build/native`` output.  The ROM is verified input and is never
retained by the application or copied into the checkout.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import struct
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


ROM_SHA1_EXPECTED = "abe01e4aeb033b6c0836819f549c791b26cfde83"
ROM_SIZE_EXPECTED = 12_582_912
REFERENCE_COMMAND = "make -j8 IDO_RECOMP=NO VERSION=US COMPARE=1 VERBOSE=1"
REFERENCE_HASH_COMMAND = "sha1sum -c ge007.u.sha1"
IMAGE_COUNT = 2698
IMAGE_SEGMENT_ROM_START = 9_403_888
G_NOOP_F3D = 0xC0
G_ENDDL_F3D = frozenset((0xB8, 0xDF))
TEXTURETYPE_DETAIL = 1
_TEX2PNG_READY = False

# These are the source files that define the trace.  The hashes make a
# regenerated sidecar fail closed if the source producer or table layout was
# changed without an explicit preparation review.
SOURCE_HASH_GUARDS = {
    "scripts/goldeneye_pd_image_decoder_v6.py": "b7e30cd52c937f78d48e1e221a5880ccd06f0b88f0d5dd106d7d5dd1b8801a75",
    "src/game/tex.c": "35fc7fa95003fbeb47cd5a1cfde32cbf8cd907c2bc10c07aaed71145cca85483",
    "src/game/image.c": "00005dd6536db7e8757c5b86cdd04e971e81d263d2b0a9ca0525dca5fc7e5da5",
    "src/game/image.h": "54e47074009f1040b8dfa14016f43f1259f8eb928e01408bebe822c1bb93e9ea",
    "src/game/initimages.c": "01f38cf180a6539773b4030e9e88459ca014a43e4120a8eb5cab98d6fe6e9bee",
    "src/game/bg.c": "b7207454d5ffb1c0ae45b267949d691a519bb28325f083f825108103ff7d042a",
    "assets/images.def": "01fde9bf2934b82460eaefc55ed7e8c2d706290489eeef8b3f9bbb243973ea09",
    "imagelist.u.csv": "0192d653c34d459ad98a5e671dbccaf97277a536824a5414c7e0ba80a4aba8ff",
    "scripts/filelist.u.csv": "b33fae98f0f72745171eae666638477cd730118c228211310db3ba32ad96834f",
    "tools/1172inflate.sh": "947b82bd3aeabb3155d34aa5ffb6df13c400e871d8c0bf72c5e6ef3a3bd6e389",
    "tools/mktex/src/libpdtex/pdtex.c": "dc3173be2e001b449305654f6164328cf7c64bd027b71a73bab5ea69f994e9cd",
    "tools/mktex/src/libpdtex/reader.c": "57f946d48202a0deed32fc98fb12f78441833cc0f6cb6b0151447b8885bd08ed",
    "tools/mktex/src/tex2png.c": "9e7a32d8e4502045f0c1d363a8430bdd9e67f4916f937943f5b58e8b6f69143e",
}

STAGES = (
    "Dam",
    "Facility",
    "Runway",
    "Bunker I",
    "Silo",
    "Frigate",
    "Train",
)


class PreparationError(RuntimeError):
    pass


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha1(data: bytes) -> str:
    return hashlib.sha1(data).hexdigest()


def safe_stage_name(stage: str) -> str:
    return stage.replace(" ", "_")


def require_file(path: Path, description: str | None = None) -> None:
    if not path.is_file():
        raise PreparationError(f"required file is missing: {description or path}")


def parse_int(text: str) -> int:
    value = text.strip()
    value = re.sub(r"/\*.*?\*/", "", value, flags=re.S)
    value = re.sub(r"//.*", "", value).strip()
    value = re.sub(r"[uUlL]+$", "", value)
    return int(value, 16 if value.lower().startswith("0x") else 10)


def verify_source_guards(root: Path) -> dict[str, str]:
    digests: dict[str, str] = {}
    for relative, expected in SOURCE_HASH_GUARDS.items():
        path = root / relative
        require_file(path, relative)
        actual = sha256(path.read_bytes())
        if actual != expected:
            raise PreparationError(
                f"source SHA-256 mismatch for {relative}: expected {expected}, got {actual}"
            )
        digests[relative] = actual
    return digests


def verify_external_rom(root: Path, rom_path: Path) -> tuple[Path, str]:
    if not rom_path.is_absolute():
        raise PreparationError(f"external ROM path must be absolute: {rom_path}")
    require_file(rom_path, "external ROM")
    real = rom_path.resolve()
    project = root.resolve()
    if real == project or project in real.parents:
        raise PreparationError(f"the ROM must remain outside the checkout: {real}")
    if real.stat().st_size != ROM_SIZE_EXPECTED:
        raise PreparationError(
            f"external ROM size mismatch: expected {ROM_SIZE_EXPECTED}, got {real.stat().st_size}"
        )
    digest = sha1(real.read_bytes())
    if digest != ROM_SHA1_EXPECTED:
        raise PreparationError(
            f"external ROM SHA-1 mismatch: expected {ROM_SHA1_EXPECTED}, got {digest}"
        )
    evidence = root / ".porting/m0-provenance.md"
    require_file(evidence, str(evidence))
    evidence_text = evidence.read_text(encoding="utf-8")
    for required in (REFERENCE_COMMAND, REFERENCE_HASH_COMMAND, ROM_SHA1_EXPECTED):
        if required not in evidence_text:
            raise PreparationError(f"Linux provenance evidence is missing: {required}")
    return real, digest


def verify_output_guard(root: Path, output: Path) -> None:
    output = output.resolve()
    allowed = (root / "build/native").resolve()
    if output == root.resolve() or allowed not in output.parents:
        raise PreparationError(f"stage texture output must remain below build/native: {output}")
    try:
        subprocess.run(["git", "-C", str(root), "check-ignore", "-q", str(output)], check=True)
    except (OSError, subprocess.CalledProcessError) as error:
        raise PreparationError(f"stage texture output is not ignored: {output}") from error


@dataclass(frozen=True)
class ImageTableRow:
    index: int
    name: str
    declared_bytes: int
    rom_offset: int
    rom_bytes: int
    source_row: str
    image_segment_offset: int
    flags: tuple[str, ...]


def parse_images_def(root: Path) -> list[tuple[str, int, tuple[str, ...]]]:
    path = root / "assets/images.def"
    entries: list[tuple[str, int, tuple[str, ...]]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped.startswith("IMAGE(") or not stripped.endswith(")"):
            continue
        fields = [field.strip() for field in stripped[6:-1].split(",")]
        if len(fields) != 8:
            raise PreparationError(f"images.def entry has {len(fields)} fields: {stripped}")
        name, size = fields[0], parse_int(fields[1])
        if not re.fullmatch(r"[A-Za-z0-9_]+", name):
            raise PreparationError(f"image name is not a bounded source token: {name!r}")
        entries.append((name, size, tuple(fields[2:])))
    if len(entries) != IMAGE_COUNT:
        raise PreparationError(f"images.def entry count {len(entries)} != {IMAGE_COUNT}")
    return entries


def parse_image_rows(root: Path, image_defs: list[tuple[str, int, tuple[str, ...]]]) -> list[ImageTableRow]:
    path = root / "imagelist.u.csv"
    lines = [line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if len(lines) != IMAGE_COUNT + 1:
        raise PreparationError(f"imagelist.u.csv row count {len(lines)} != {IMAGE_COUNT + 1}")

    rows: list[ImageTableRow] = []
    previous_end: int | None = None
    segment_offset = 0
    for index, line in enumerate(lines[:IMAGE_COUNT]):
        fields = line.split(",")
        if len(fields) != 5:
            raise PreparationError(f"imagelist row {index} has {len(fields)} fields")
        rom_offset, rom_bytes = parse_int(fields[0]), parse_int(fields[1])
        if rom_offset < 0 or rom_bytes <= 0:
            raise PreparationError(f"imagelist row {index} has invalid range")
        if previous_end is not None and rom_offset != previous_end:
            raise PreparationError(
                f"imagelist row {index} is not contiguous: expected {previous_end}, got {rom_offset}"
            )
        name, declared_bytes, flags = image_defs[index]
        if declared_bytes != rom_bytes:
            raise PreparationError(
                f"image {index} ({name}) size mismatch: images.def={declared_bytes}, imagelist={rom_bytes}"
            )
        rows.append(
            ImageTableRow(
                index=index,
                name=name,
                declared_bytes=declared_bytes,
                rom_offset=rom_offset,
                rom_bytes=rom_bytes,
                source_row=line,
                image_segment_offset=segment_offset,
                flags=flags,
            )
        )
        previous_end = rom_offset + rom_bytes
        segment_offset += rom_bytes

    if rows[0].rom_offset != IMAGE_SEGMENT_ROM_START:
        raise PreparationError(
            f"image segment ROM start {rows[0].rom_offset} != {IMAGE_SEGMENT_ROM_START}"
        )
    dummy = lines[IMAGE_COUNT].split(",")
    if len(dummy) != 5 or parse_int(dummy[1]) != 8 or parse_int(dummy[0]) != previous_end:
        raise PreparationError("imagelist dummy tail row is not the guarded 8-byte continuation")
    return rows


def parse_stage_manifest(stage_root: Path) -> dict[str, Path]:
    manifest = stage_root / "stage-assets-manifest.txt"
    require_file(manifest, str(manifest))
    lines = [line.strip() for line in manifest.read_text(encoding="utf-8").splitlines() if line.strip()]
    keys = dict(
        line.split("=", 1)
        for line in lines
        if "=" in line and not re.match(r"resource_\d+=", line)
    )
    if keys.get("manifest_status", "PASS") != "PASS":
        raise PreparationError("stage asset manifest is not the verified 21-resource preparation")
    resource_lines = [line for line in lines if re.match(r"resource_\d+=", line)]
    declared_count = keys.get("resource_count")
    if declared_count is not None and declared_count != "21":
        raise PreparationError("stage asset manifest is not the verified 21-resource preparation")
    if len(resource_lines) != 21:
        raise PreparationError(f"stage asset manifest exposes {len(resource_lines)} resources, expected 21")
    backgrounds: dict[str, Path] = {}
    for line in lines:
        if not re.match(r"resource_\d+=", line):
            continue
        _, payload = line.split("=", 1)
        fields = payload.split("|")
        if len(fields) != 9:
            raise PreparationError(f"stage resource row has {len(fields)} fields")
        stage, kind, name = fields[:3]
        source_bytes = int(fields[4])
        compressed = int(fields[5])
        decoded_bytes = int(fields[6])
        source_digest, decoded_digest = fields[7:9]
        if kind != "background":
            continue
        if compressed != 0 or source_bytes != decoded_bytes:
            raise PreparationError(f"background {stage} is unexpectedly compressed")
        safe = f"{safe_stage_name(stage)}__background__{name}.bin"
        path = stage_root / "background" / safe
        require_file(path, f"prepared background {stage}")
        actual = path.read_bytes()
        if len(actual) != decoded_bytes or sha256(actual) != decoded_digest:
            raise PreparationError(f"prepared background digest mismatch for {stage}")
        # Keep the source digest in the trace, even though it is identical for
        # uncompressed background rows.
        if source_digest != sha256(actual):
            raise PreparationError(f"prepared background source digest mismatch for {stage}")
        backgrounds[stage] = path
    if tuple(backgrounds) != STAGES:
        raise PreparationError(f"background stage set {tuple(backgrounds)} != {STAGES}")
    return backgrounds


def read_be32(data: bytes, offset: int, context: str) -> int:
    if offset < 0 or offset + 4 > len(data):
        raise PreparationError(f"{context}: 32-bit read exceeds payload at 0x{offset:x}")
    return struct.unpack_from(">I", data, offset)[0]


@dataclass(frozen=True)
class RoomStream:
    stage: str
    room: int
    kind: str
    source_record_offset: int
    source_offset: int
    source_bytes: int
    source: bytes
    decoded: bytes


def room_streams(stage: str, background: bytes, inflater: Path, temp_root: Path) -> list[RoomStream]:
    if len(background) < 20:
        raise PreparationError(f"{stage}: background header is truncated")
    room_table = read_be32(background, 4, f"{stage} header") & 0x00FFFFFF
    if room_table < 20 or room_table + 24 > len(background):
        raise PreparationError(f"{stage}: room table offset is outside background")
    records: list[tuple[int, tuple[int, ...]]] = []
    offset = room_table + 24
    while True:
        if offset + 24 > len(background):
            raise PreparationError(f"{stage}: room table has no zero sentinel")
        words = tuple(read_be32(background, offset + index * 4, f"{stage} room") for index in range(6))
        if not any(words):
            break
        records.append((offset, words))
        if len(records) > 4096:
            raise PreparationError(f"{stage}: room count exceeds bounded capacity")
        offset += 24
    streams: list[RoomStream] = []
    for kind_index, kind in ((1, "primary"), (2, "secondary")):
        pointers = sorted({words[kind_index] & 0x00FFFFFF for _, words in records if words[kind_index]})
        for room_index, (record_offset, words) in enumerate(records):
            segmented = words[kind_index]
            if segmented == 0:
                continue
            if segmented & 0xFF000000 != 0x0F000000:
                raise PreparationError(f"{stage} room {room_index} {kind} is not segment 0x0f")
            source_offset = segmented & 0x00FFFFFF
            try:
                next_offset = next(value for value in pointers if value > source_offset)
            except StopIteration:
                next_offset = len(background)
            if source_offset < offset or next_offset <= source_offset or next_offset > len(background):
                raise PreparationError(f"{stage} room {room_index} {kind} range is invalid")
            source = background[source_offset:next_offset]
            if source[:2] != b"\x11\x72":
                # A few source room records alias the terminal payload
                # address for an intentionally empty mapping.  Preserve that
                # source fact without inventing a texture command; any
                # non-empty address that is not an 1172 stream remains a hard
                # preparation error.
                if not any(source):
                    continue
                raise PreparationError(f"{stage} room {room_index} {kind} lacks 1172 prefix")
            source_path = temp_root / f"{safe_stage_name(stage)}-{kind}-{room_index}.rz"
            decoded_path = temp_root / f"{safe_stage_name(stage)}-{kind}-{room_index}.bin"
            source_path.write_bytes(source)
            try:
                subprocess.run(
                    [str(inflater), str(source_path), str(decoded_path)],
                    cwd=str(inflater.parent.parent),
                    env={**os.environ, "GZ": "gzip"},
                    check=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                )
            except (OSError, subprocess.CalledProcessError) as error:
                raise PreparationError(f"{stage} room {room_index} {kind} 1172 inflate failed") from error
            decoded = decoded_path.read_bytes()
            if not decoded:
                raise PreparationError(f"{stage} room {room_index} {kind} decoded to zero bytes")
            streams.append(
                RoomStream(
                    stage=stage,
                    room=room_index,
                    kind=kind,
                    source_record_offset=record_offset,
                    source_offset=source_offset,
                    source_bytes=len(source),
                    source=source,
                    decoded=decoded,
                )
            )
    return streams


@dataclass(frozen=True)
class TextureBinding:
    stage: str
    room: int
    kind: str
    stream_source_offset: int
    stream_source_bytes: int
    stream_decoded_bytes: int
    source_record_offset: int
    command_offset: int
    word0: int
    word1: int
    texture_type: int
    selector: str
    texture_id: int


def trace_texture_bindings(stream: RoomStream) -> list[TextureBinding]:
    bindings: list[TextureBinding] = []
    offset = 0
    while offset + 8 <= len(stream.decoded):
        word0, word1 = struct.unpack_from(">2I", stream.decoded, offset)
        opcode = word0 >> 24
        if opcode in G_ENDDL_F3D:
            break
        if opcode == G_NOOP_F3D:
            texture_type = word0 & 7
            base_id = word1 & 0x0FFF
            bindings.append(
                TextureBinding(
                    stage=stream.stage,
                    room=stream.room,
                    kind=stream.kind,
                    stream_source_offset=stream.source_offset,
                    stream_source_bytes=stream.source_bytes,
                    stream_decoded_bytes=len(stream.decoded),
                    source_record_offset=stream.source_record_offset,
                    command_offset=offset,
                    word0=word0,
                    word1=word1,
                    texture_type=texture_type,
                    selector="base",
                    texture_id=base_id,
                )
            )
            if texture_type == TEXTURETYPE_DETAIL:
                bindings.append(
                    TextureBinding(
                        stage=stream.stage,
                        room=stream.room,
                        kind=stream.kind,
                        stream_source_offset=stream.source_offset,
                        stream_source_bytes=stream.source_bytes,
                        stream_decoded_bytes=len(stream.decoded),
                        source_record_offset=stream.source_record_offset,
                        command_offset=offset,
                        word0=word0,
                        word1=word1,
                        texture_type=texture_type,
                        selector="detail",
                        texture_id=(word1 >> 12) & 0x0FFF,
                    )
                )
        offset += 8
    if offset == len(stream.decoded) and len(stream.decoded) % 8 != 0:
        raise PreparationError(f"{stream.stage} room {stream.room} {stream.kind} GDL is not 8-byte aligned")
    return bindings


def flip_rgba8(pixels: bytes, width: int, height: int) -> bytes:
    row_bytes = width * 4
    return b"".join(
        pixels[row * row_bytes : (row + 1) * row_bytes]
        for row in range(height - 1, -1, -1)
    )


def decode_levels(root: Path, image_name: str, source: bytes, output_base: Path) -> tuple[list[tuple[int, int, int, int, str, str, str, str]], int, int, str]:
    """Decode every source mip emitted by the checked-in tex2png tool."""
    try:
        sys.path.insert(0, str(root / "scripts"))
        from prepare_native_title_icons import decode_png, find_tex2png, stream_format_and_compression
    except ImportError as error:
        raise PreparationError("source tex2png decoder is unavailable") from error
    output_base.parent.mkdir(parents=True, exist_ok=True)
    output_base.with_suffix(".raw").write_bytes(source)
    with tempfile.TemporaryDirectory(prefix="goldeneye-stage-image-") as temp:
        temp_root = Path(temp)
        input_path = temp_root / f"{image_name}.bin"
        png_root = temp_root / "decoded"
        png_root.mkdir()
        input_path.write_bytes(source)
        try:
            global _TEX2PNG_READY
            corrected = root / "tools/mktex/build/tex2png"
            if not _TEX2PNG_READY:
                corrected.parent.mkdir(parents=True, exist_ok=True)
                try:
                    subprocess.run(
                        ["make", "-C", str(root / "tools/mktex"), "tex2png"],
                        check=True,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                    )
                except (OSError, subprocess.CalledProcessError):
                    compiler = os.environ.get("CC", "cc")
                    include_flags = [
                        flag for flag in ("/opt/homebrew/include", "/usr/local/include")
                        if Path(flag).is_dir()
                    ]
                    library_flags = [
                        flag for flag in ("/opt/homebrew/lib", "/usr/local/lib")
                        if Path(flag).is_dir()
                    ]
                    subprocess.run(
                        [
                            compiler,
                            *[f"-I{flag}" for flag in include_flags],
                            str(root / "tools/mktex/src/tex2png.c"),
                            str(root / "tools/mktex/src/libpdtex/pdtex.c"),
                            str(root / "tools/mktex/src/libpdtex/reader.c"),
                            str(root / "tools/mktex/src/libpdtex/writer.c"),
                            *[f"-L{flag}" for flag in library_flags],
                            "-lpng", "-lz", "-O3", "-o", str(corrected),
                        ],
                        check=True,
                        cwd=str(root),
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                    )
                _TEX2PNG_READY = True
            corrected = root / "tools/mktex/build/tex2png"
            tex2png = corrected if corrected.is_file() and os.access(corrected, os.X_OK) else find_tex2png(root)
            subprocess.run(
                [str(tex2png), str(input_path), str(png_root)],
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
        except (OSError, subprocess.CalledProcessError) as error:
            raise PreparationError(f"tex2png failed for stage image {image_name}") from error
        pngs = sorted(
            png_root.glob(f"{image_name}-*.png"),
            key=lambda path: int(path.stem.rsplit("-", 1)[1]),
        )
        if not pngs:
            raise PreparationError(f"tex2png emitted no levels for stage image {image_name}")
        explicit_lods = (source[0] >> 7) & 1
        expected_levels = max(1, source[0] & 0x3F) if explicit_lods else 1
        if len(pngs) != expected_levels:
            raise PreparationError(
                f"stage image {image_name} emitted {len(pngs)} levels, expected source {expected_levels}"
            )
        levels: list[tuple[int, int, int, int, str, str, str, str]] = []
        for png in pngs:
            level = int(png.stem.rsplit("-", 1)[1])
            width, height, pixels = decode_png(png.read_bytes())
            suffix = ".decoded" if level == 0 else f".mip{level}.decoded"
            output_path = output_base.with_suffix(suffix)
            output_path.write_bytes(pixels)
            inspection = flip_rgba8(pixels, width, height)
            inspection_path = output_base.with_suffix(
                ".inspection.decoded" if level == 0 else f".mip{level}.inspection.decoded"
            )
            inspection_path.write_bytes(inspection)
            levels.append((
                level, width, height, len(pixels), sha256(pixels), output_path.name,
                sha256(inspection), inspection_path.name,
            ))
    stream_format, stream_compression = stream_format_and_compression(source)
    base = output_base.with_suffix(".decoded").read_bytes()
    rgb_nonzero = any(base[index] or base[index + 1] or base[index + 2] for index in range(0, len(base), 4))
    alpha_nonzero = any(base[index + 3] for index in range(0, len(base), 4))
    if rgb_nonzero:
        visibility = "colored"
    elif alpha_nonzero and stream_format in (5, 6, 7, 8):
        visibility = "source-monochrome-black"
    elif not alpha_nonzero and stream_format in (5, 6, 7, 8):
        visibility = "source-monochrome-zero"
    elif alpha_nonzero:
        visibility = "unclassified-alpha-only"
    else:
        visibility = "unclassified-zero"
    return levels, stream_format, stream_compression, visibility


def decode_levels(root: Path, image_name: str, source: bytes, output_base: Path) -> tuple[list[tuple[int, int, int, int, str, str, str, str]], int, int, str]:
    """Decode source-order levels through the bounded PD decoder.

    This definition intentionally follows the legacy helper above so older
    diagnostics remain available in the file history while all preparation
    calls resolve to the source-faithful path below.
    """
    del root, image_name
    try:
        from goldeneye_pd_image_decoder_v6 import PDDecodeError, decode_stream
    except ImportError as error:
        raise PreparationError("source PD image decoder is unavailable") from error
    output_base.parent.mkdir(parents=True, exist_ok=True)
    output_base.with_suffix(".raw").write_bytes(source)
    try:
        decoded = decode_stream(source, flip=False)
        inspection = decode_stream(source, flip=True)
    except PDDecodeError as error:
        raise PreparationError("source PD image decoder rejected stage stream") from error
    expected_levels = max(1, decoded.encoded_lods) if decoded.explicit_lods else 1
    if len(decoded.images) != expected_levels or len(inspection.images) != expected_levels:
        raise PreparationError(f"stage stream emitted {len(decoded.images)} levels, expected source {expected_levels}")
    levels: list[tuple[int, int, int, int, str, str, str, str]] = []
    for image, inspected in zip(decoded.images, inspection.images):
        if (image.width, image.height) != (inspected.width, inspected.height):
            raise PreparationError(f"source/inspection dimensions differ at level {image.level}")
        suffix = ".decoded" if image.level == 0 else f".mip{image.level}.decoded"
        output_path = output_base.with_suffix(suffix)
        output_path.write_bytes(image.rgba8)
        inspection_path = output_base.with_suffix(".inspection.decoded" if image.level == 0 else f".mip{image.level}.inspection.decoded")
        inspection_path.write_bytes(inspected.rgba8)
        levels.append((image.level, image.width, image.height, len(image.rgba8), sha256(image.rgba8), output_path.name, sha256(inspected.rgba8), inspection_path.name))
    if not levels:
        raise PreparationError("source PD image decoder emitted no levels")
    stream_format = int(decoded.format)
    stream_compression = int(decoded.images[0].compression)
    base = output_base.with_suffix(".decoded").read_bytes()
    rgb_nonzero = any(base[index] or base[index + 1] or base[index + 2] for index in range(0, len(base), 4))
    alpha_nonzero = any(base[index + 3] for index in range(0, len(base), 4))
    if rgb_nonzero:
        visibility = "colored"
    elif alpha_nonzero and stream_format in (5, 6, 7, 8):
        visibility = "source-monochrome-black"
    elif not alpha_nonzero and stream_format in (5, 6, 7, 8):
        visibility = "source-monochrome-zero"
    elif alpha_nonzero:
        visibility = "unclassified-alpha-only"
    else:
        visibility = "unclassified-zero"
    return levels, stream_format, stream_compression, visibility


def write_payloads(
    root: Path,
    rom: Path,
    output_dir: Path,
    rows: list[ImageTableRow],
    texture_ids: Iterable[int],
) -> tuple[dict[int, dict[str, object]], dict[int, dict[str, object]]]:
    try:
        sys.path.insert(0, str(root / "scripts"))
        from prepare_native_source_frontend_v6 import _extract_pd_palette
    except ImportError as error:
        raise PreparationError("source PD palette decoder is unavailable") from error
    by_id = {row.index: row for row in rows}
    image_records: dict[int, dict[str, object]] = {}
    tlut_records: dict[int, dict[str, object]] = {}
    with rom.open("rb") as stream:
        for texture_id in sorted(set(texture_ids)):
            row = by_id.get(texture_id)
            if row is None:
                raise PreparationError(f"stage texture number {texture_id} is outside g_Textures")
            stream.seek(row.rom_offset)
            source = stream.read(row.rom_bytes)
            if len(source) != row.rom_bytes:
                raise PreparationError(f"image row {texture_id} is truncated in the external ROM")
            raw_digest = sha256(source)
            base = output_dir / f"image_{row.index:04d}_{row.name}"
            levels, stream_format, stream_compression, visibility = decode_levels(root, row.name, source, base)
            palette = _extract_pd_palette(source)
            palette_info: dict[str, object] | None = None
            if palette is not None:
                palette_raw, palette_decoded, metadata = palette
                palette_base = output_dir / f"image_{row.index:04d}_{row.name}.tlut"
                palette_raw_path = Path(str(palette_base) + ".raw")
                palette_decoded_path = Path(str(palette_base) + ".decoded")
                palette_raw_path.write_bytes(palette_raw)
                palette_decoded_path.write_bytes(palette_decoded)
                palette_info = {
                    "raw_bytes": len(palette_raw),
                    "decoded_bytes": len(palette_decoded),
                    "raw_sha256": sha256(palette_raw),
                    "decoded_sha256": sha256(palette_decoded),
                    "source_offset": int(metadata["source_offset"]),
                    "format": int(metadata["format"]),
                    "entries": int(metadata["entries"]),
                    "raw_file": palette_raw_path.name,
                    "decoded_file": palette_decoded_path.name,
                }
                tlut_records[texture_id] = palette_info
            image_records[texture_id] = {
                "index": row.index,
                "name": row.name,
                "declared_bytes": row.declared_bytes,
                "rom_offset": row.rom_offset,
                "rom_bytes": row.rom_bytes,
                "source_row": row.source_row,
                "image_segment_offset": row.image_segment_offset,
                "source_sha256": raw_digest,
                "stream_format": stream_format,
                "stream_compression": stream_compression,
                "visibility": visibility,
                "source_level_count": len(levels),
                "source_explicit_lods": bool((source[0] >> 7) & 1),
                "source_encoded_lods": source[0] & 0x3F,
                "upload_row_order": "source",
                "inspection_row_order": "vertical_flip",
                "levels": levels,
                "raw_file": base.with_suffix(".raw").name,
                "tlut": palette_info,
            }
    return image_records, tlut_records


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--rom", type=Path, required=True)
    parser.add_argument(
        "--stage-asset-root",
        type=Path,
        default=None,
        help="verified stage asset root (defaults to build/native/stage-assets)",
    )
    args = parser.parse_args()
    root = args.project_root.resolve()
    stage_root = (args.stage_asset_root or root / "build/native/stage-assets").resolve()
    texture_root = stage_root / "textures"
    manifest_path = stage_root / "stage-texture-dependencies-manifest.txt"
    verify_output_guard(root, texture_root)
    source_digests = verify_source_guards(root)
    rom, rom_sha1 = verify_external_rom(root, args.rom.resolve())
    backgrounds = parse_stage_manifest(stage_root)
    image_defs = parse_images_def(root)
    image_rows = parse_image_rows(root, image_defs)
    inflater = root / "tools/1172inflate.sh"
    require_file(inflater, str(inflater))
    if not os.access(inflater, os.X_OK):
        raise PreparationError(f"1172 inflater is not executable: {inflater}")

    all_streams: list[RoomStream] = []
    bindings: list[TextureBinding] = []
    with tempfile.TemporaryDirectory(prefix="goldeneye-stage-gdl-") as temp:
        temp_root = Path(temp)
        for stage in STAGES:
            streams = room_streams(stage, backgrounds[stage].read_bytes(), inflater, temp_root)
            all_streams.extend(streams)
            for stream in streams:
                bindings.extend(trace_texture_bindings(stream))

    if not bindings:
        raise PreparationError("source stage GDL trace produced no G_SETTEX/G_NOOP bindings")
    texture_ids = sorted({binding.texture_id for binding in bindings})
    texture_root.mkdir(parents=True, exist_ok=True)
    image_records, tlut_records = write_payloads(root, rom, texture_root, image_rows, texture_ids)

    texture_root.resolve().mkdir(parents=True, exist_ok=True)
    manifest_lines = [
        "manifest_version=1",
        "asset_family=ramrom_stage_texture_dependencies",
        "trace_contract=texLoadFromGdl:G_NOOP(0xc0).words.w1&0xfff->g_Textures->images.def/imagelist.u.csv",
        f"external_rom_size={rom.stat().st_size}",
        f"external_rom_sha1={rom_sha1}",
        f"image_segment_rom_start={IMAGE_SEGMENT_ROM_START}",
        f"image_table_count={len(image_rows)}",
        f"stage_count={len(STAGES)}",
        f"stream_count={len(all_streams)}",
        f"binding_count={len(bindings)}",
        f"unique_texture_count={len(texture_ids)}",
        f"unique_tlut_count={len(tlut_records)}",
        f"source_trace_tex_sha256={source_digests['src/game/tex.c']}",
        f"source_trace_image_sha256={source_digests['src/game/image.c']}",
        f"source_trace_image_header_sha256={source_digests['src/game/image.h']}",
        f"source_trace_initimages_sha256={source_digests['src/game/initimages.c']}",
        f"source_trace_bg_sha256={source_digests['src/game/bg.c']}",
        f"source_trace_images_def_sha256={source_digests['assets/images.def']}",
        f"source_trace_imagelist_sha256={source_digests['imagelist.u.csv']}",
        "rom_copied_into_checkout=false",
        "rom_copied_into_bundle=false",
        "runtime_opens_rom=false",
        "runtime_consumes_prepared_payloads_only=true",
        "upload_row_order=source",
        "inspection_row_order=vertical_flip",
        "decoder_contract=goldeneye_pd_image_decoder_v6",
        "source_level_semantics=explicit_levels_authored_implicit_level0_only",
    ]

    for texture_id in texture_ids:
        record = image_records[texture_id]
        levels = ";".join(
            f"{level}:{width}:{height}:{count}:{source_digest}:{filename}:{inspection_digest}:{inspection_filename}"
            for level, width, height, count, source_digest, filename, inspection_digest, inspection_filename in record["levels"]  # type: ignore[index]
        )
        manifest_lines.append(
            "image_{}=".format(texture_id)
            + "|".join(
                (
                    f"index:{record['index']}",
                    f"name:{record['name']}",
                    f"declared_bytes:{record['declared_bytes']}",
                    f"rom_offset:{record['rom_offset']}",
                    f"rom_bytes:{record['rom_bytes']}",
                    f"image_segment_offset:{record['image_segment_offset']}",
                    f"source_sha256:{record['source_sha256']}",
                    f"stream_format:{record['stream_format']}",
                    f"stream_compression:{record['stream_compression']}",
                    f"visibility:{record['visibility']}",
                    f"source_level_count:{record['source_level_count']}",
                    f"source_explicit_lods:{str(record['source_explicit_lods']).lower()}",
                    f"source_encoded_lods:{record['source_encoded_lods']}",
                    f"upload_row_order:{record['upload_row_order']}",
                    f"inspection_row_order:{record['inspection_row_order']}",
                    f"source_row:{record['source_row']}",
                    f"raw_file:{record['raw_file']}",
                    f"levels:{levels}",
                    f"tlut:{json.dumps(record['tlut'], sort_keys=True, separators=(',', ':'))}",
                )
            )
        )

    for index, binding in enumerate(bindings):
        record = image_records[binding.texture_id]
        manifest_lines.append(
            f"command_{index}="
            + "|".join(
                (
                    f"stage:{binding.stage}",
                    f"room:{binding.room}",
                    f"kind:{binding.kind}",
                    f"source_record_offset:{binding.source_record_offset}",
                    f"stream_source_offset:{binding.stream_source_offset}",
                    f"stream_source_bytes:{binding.stream_source_bytes}",
                    f"stream_decoded_bytes:{binding.stream_decoded_bytes}",
                    f"command_offset:{binding.command_offset}",
                    f"word0:0x{binding.word0:08x}",
                    f"word1:0x{binding.word1:08x}",
                    f"texture_type:{binding.texture_type}",
                    f"selector:{binding.selector}",
                    f"texture_id:{binding.texture_id}",
                    f"image_index:{record['index']}",
                    f"image_name:{record['name']}",
                    f"image_source_sha256:{record['source_sha256']}",
                    "upload_row_order:source",
                    "inspection_row_order:vertical_flip",
                )
            )
        )

    manifest_lines.extend(
        (
            "source_trace_status=PASS",
            "payload_status=PASS",
            "manifest_status=PASS",
        )
    )
    manifest_path.write_text("\n".join(manifest_lines) + "\n", encoding="utf-8")
    print(
        "Native stage texture preparation: PASS "
        f"stages={len(STAGES)} streams={len(all_streams)} bindings={len(bindings)} "
        f"textures={len(texture_ids)} tluts={len(tlut_records)}"
    )
    print(f"Manifest: {manifest_path}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PreparationError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
