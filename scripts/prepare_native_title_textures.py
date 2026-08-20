#!/usr/bin/env python3
"""Lower guarded frontend model/image rows into additive GETT packets.

The direct model rows are copied from the already-prepared generated model
blobs at their source-local offsets.  Wallet rows use the checked-in PD image
streams and the repository's ``tex2png`` decoder.  Neither path opens the
external ROM.  The packet contains only fixed-width metadata, hashes, and
decoded RGBA8 pixels.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import struct
import subprocess
import tempfile
from pathlib import Path

from prepare_native_title_icons import decode_png, find_tex2png, stream_format_and_compression


MAGIC = b"GETT"
VERSION = 1
ABI_VERSION = 1
HEADER = struct.Struct("<4sIIIIIIIII32s32s6I")
RECORD = struct.Struct("<IIIIIIIIIIIIIIIIIIII32s32s")
assert HEADER.size == 128
assert RECORD.size == 144

FORMAT_RGBA = 0
FORMAT_YUV = 1
FORMAT_CI = 2
FORMAT_IA = 3
FORMAT_I = 4

SIZE_4B = 0
SIZE_8B = 1
SIZE_16B = 2
SIZE_32B = 3

FLAG_DIRECT_MODEL = 1 << 0
FLAG_IMAGE_STREAM = 1 << 1
FLAG_DECODED_RGBA8 = 1 << 2
FLAG_MIP_CHAIN = 1 << 3
FLAG_SYMBOLIC_ID = 1 << 4
FLAG_TILED = 1 << 5
FLAG_CLAMP_S = 1 << 6
FLAG_CLAMP_T = 1 << 7
FLAG_MIRROR_S = 1 << 8
FLAG_MIRROR_T = 1 << 9
FLAG_BILERP = 1 << 10
FLAG_DETAIL_CLAMP = 1 << 11
FLAG_MASK = (1 << 12) - 1

MODEL_SPECS = (
    ("legalpage", 4, "assets/obseg/prop/legalpage/Model.c"),
    ("nintendologo", 5, "assets/obseg/prop/nintendologo/Model.c"),
    ("goldeneyelogo", 3, "assets/obseg/prop/goldeneyelogo/Model.c"),
    ("walletbond", 6, "assets/obseg/prop/walletbond/Model.c"),
)


class PacketError(ValueError):
    pass


def parse_int(value: str) -> int:
    value = re.sub(r"/\*.*?\*/", "", value, flags=re.S)
    value = re.sub(r"//[^\n]*", "", value).strip()
    value = re.sub(r"[uUlL]+$", "", value)
    return int(value, 16 if value.lower().startswith("0x") else 10)


def fnv_token(value: str) -> int:
    hashed = 2166136261
    for byte in value.encode("utf-8"):
        hashed = ((hashed ^ byte) * 16777619) & 0xFFFFFFFF
    return 0x80000000 | (hashed & 0x7FFFFFFF)


def model_rows(source_text: str) -> list[tuple[str, int, int, int, int, int, int, int]]:
    match = re.search(
        r"ModelFileTextures\s+proptextures\[[^]]+\]\s*=\s*\{(.*?)\};",
        source_text,
        re.S,
    )
    if not match:
        raise PacketError("proptextures table is missing")
    rows = []
    for row in re.finditer(r"\{([^{}]+)\}", match.group(1)):
        values = [part.strip() for part in row.group(1).split(",") if part.strip()]
        if len(values) != 8:
            raise PacketError("malformed ModelFileTextures row")
        try:
            resource_id = parse_int(values[0])
        except ValueError:
            # Wallet keeps symbolic IMAGE_* IDs as a deterministic value-only
            # token.  It is resolved to an image stream below, never a path.
            resource_id = fnv_token(values[0].removeprefix("IMAGE_"))
        parsed = [parse_int(part) if not part.startswith("IMAGE_") else 0 for part in values[1:]]
        rows.append((values[0], resource_id, *parsed))
    if not rows:
        raise PacketError("proptextures table is empty")
    return rows


def texture_commands(source_text: str) -> dict[int, tuple[int, int, int | None]]:
    """Return source-local texture id -> (G_IM_FMT, G_IM_SIZ, load bytes)."""
    result: dict[int, tuple[int, int, int | None]] = {}
    formats = {"G_IM_FMT_RGBA": FORMAT_RGBA, "G_IM_FMT_YUV": FORMAT_YUV,
               "G_IM_FMT_CI": FORMAT_CI, "G_IM_FMT_IA": FORMAT_IA,
               "G_IM_FMT_I": FORMAT_I}
    sizes = {"G_IM_SIZ_4b": SIZE_4B, "G_IM_SIZ_8b": SIZE_8B,
             "G_IM_SIZ_16b": SIZE_16B, "G_IM_SIZ_32b": SIZE_32B}
    pattern = re.compile(
        r"gsDPSetTextureImage\(\s*(G_IM_FMT_[A-Z0-9]+)\s*,\s*"
        r"(G_IM_SIZ_[0-9]+b)\s*,\s*[^,]+,\s*0x05000000?([0-9A-Fa-f]+)\s*\)"
    )
    # The source uses both 0x05000090 and 0x0500000090 spellings; normalize
    # with a looser expression after the first pass if needed.
    pattern = re.compile(
        r"gsDPSetTextureImage\(\s*(G_IM_FMT_[A-Z0-9]+)\s*,\s*"
        r"(G_IM_SIZ_[0-9]+b)\s*,\s*[^,]+,\s*0x([0-9A-Fa-f]+)\s*\)"
    )
    matches = list(pattern.finditer(source_text))
    for index, match in enumerate(matches):
        image_offset = int(match.group(3), 16) & 0x00FFFFFF
        if match.group(1) not in formats or match.group(2) not in sizes:
            continue
        end = matches[index + 1].start() if index + 1 < len(matches) else len(source_text)
        body = source_text[match.end():end]
        load_bytes: int | None = None
        load = re.search(
            r"gsDPLoadBlock\(\s*[^,]+,\s*[^,]+,\s*[^,]+,\s*([^,]+),",
            body,
        )
        if load:
            try:
                texel_count = parse_int(load.group(1)) + 1
                command_size = sizes[match.group(2)]
                if command_size == SIZE_4B:
                    load_bytes = (texel_count + 1) // 2
                elif command_size == SIZE_8B:
                    load_bytes = texel_count
                elif command_size == SIZE_16B:
                    load_bytes = texel_count * 2
                elif command_size == SIZE_32B:
                    load_bytes = texel_count * 4
            except ValueError:
                load_bytes = None
        result[image_offset] = (formats[match.group(1)], sizes[match.group(2)], load_bytes)
    return result


def bytes_per_pixel(size: int) -> tuple[int, int]:
    if size == SIZE_4B:
        return (1, 2)  # numerator, denominator
    if size == SIZE_8B:
        return (1, 1)
    if size == SIZE_16B:
        return (2, 1)
    if size == SIZE_32B:
        return (4, 1)
    raise PacketError(f"unsupported texture size {size}")


def rgba5551_to_rgba8(pixel: int) -> tuple[int, int, int, int]:
    return (
        ((pixel >> 11) & 0x1F) * 255 // 31,
        ((pixel >> 6) & 0x1F) * 255 // 31,
        ((pixel >> 1) & 0x1F) * 255 // 31,
        255 if (pixel & 1) else 0,
    )


def decode_direct(raw: bytes, width: int, height: int, fmt: int, size: int) -> bytes:
    if fmt == FORMAT_RGBA and size == SIZE_16B:
        if len(raw) != width * height * 2:
            raise PacketError("RGBA16 source byte count mismatch")
        output = bytearray()
        for offset in range(0, len(raw), 2):
            output.extend(rgba5551_to_rgba8(int.from_bytes(raw[offset:offset + 2], "big")))
        return bytes(output)
    if fmt == FORMAT_I and size == SIZE_8B:
        if len(raw) != width * height:
            raise PacketError("I8 source byte count mismatch")
        return b"".join(bytes((value, value, value, 255)) for value in raw)
    if fmt == FORMAT_I and size == SIZE_4B:
        if len(raw) * 2 != width * height:
            raise PacketError("I4 source byte count mismatch")
        output = bytearray()
        for value in raw:
            high = value >> 4
            low = value & 0x0F
            output.extend((high * 17, high * 17, high * 17, 255))
            output.extend((low * 17, low * 17, low * 17, 255))
        return bytes(output)
    raise PacketError(f"unsupported direct texture format/size ({fmt},{size})")


def source_flags(row: tuple[int, ...], direct: bool, fmt: int, size: int) -> int:
    # row = id, width, height, mip, type, depth, sflags, tflags
    _, _, _, mip, _, _, s_flags, t_flags = row
    flags = FLAG_DIRECT_MODEL if direct else FLAG_IMAGE_STREAM
    flags |= FLAG_DECODED_RGBA8
    if mip > 1:
        flags |= FLAG_MIP_CHAIN
    if not direct:
        flags |= FLAG_SYMBOLIC_ID
    # G_TX_WRAP=0, G_TX_MIRROR=1, G_TX_CLAMP=2 in the source tables.
    if s_flags == 2:
        flags |= FLAG_CLAMP_S
    elif s_flags == 1:
        flags |= FLAG_MIRROR_S
    if t_flags == 2:
        flags |= FLAG_CLAMP_T
    elif t_flags == 1:
        flags |= FLAG_MIRROR_T
    if not direct or fmt in (FORMAT_RGBA, FORMAT_I):
        # All title display lists select bilinear filtering and clamp detail;
        # wallet streams retain their source sampler metadata in the row.
        flags |= FLAG_BILERP | FLAG_DETAIL_CLAMP
    if direct:
        flags |= FLAG_TILED
    return flags & FLAG_MASK


def record(
    *,
    row: tuple[int, ...],
    fmt: int,
    size: int,
    source_stride: int,
    source_offset: int,
    source_bytes: bytes,
    pixels: bytes,
    flags: int,
    payload_offset: int,
) -> tuple:
    _, resource_id, width, height, mip, type_value, depth, s_flags, t_flags = row
    if width <= 0 or height <= 0 or width > 4096 or height > 4096:
        raise PacketError("texture dimensions exceed guard")
    if len(pixels) != width * height * 4:
        raise PacketError("decoded RGBA8 size mismatch")
    if not source_bytes:
        raise PacketError("source texture row is empty")
    return (
        ABI_VERSION, RECORD.size, VERSION, resource_id, width, height,
        mip, type_value, depth, s_flags, t_flags, fmt, size, source_stride,
        len(pixels), source_offset, payload_offset, flags, len(source_bytes), 0,
        hashlib.sha256(source_bytes).digest(), hashlib.sha256(pixels).digest(),
    )


def packet(model_handle: int, rows: list[tuple], payload_records: list[tuple], source_concat: bytes, flags: int) -> bytes:
    payload = bytearray()
    records = bytearray()
    for fields, pixels in payload_records:
        mutable = list(fields)
        mutable[16] = len(payload)  # payload_offset in the fixed record
        payload.extend(pixels)
        records.extend(RECORD.pack(*mutable))
    source_hash = hashlib.sha256(source_concat).digest()
    zero_header = HEADER.pack(
        MAGIC, VERSION, ABI_VERSION, HEADER.size, model_handle, len(rows),
        RECORD.size, len(payload), len(source_concat), flags, source_hash,
        bytes(32), 0, 0, 0, 0, 0, 0,
    )
    canonical = zero_header + records + bytes(payload)
    packet_hash = hashlib.sha256(canonical).digest()
    header = HEADER.pack(
        MAGIC, VERSION, ABI_VERSION, HEADER.size, model_handle, len(rows),
        RECORD.size, len(payload), len(source_concat), flags, source_hash,
        packet_hash, 0, 0, 0, 0, 0, 0,
    )
    return header + bytes(records) + bytes(payload)


def lower_direct(root: Path, output_root: Path, name: str, handle: int, relative: str) -> tuple[bytes, dict]:
    source_path = root / relative
    blob_path = output_root / f"{name}.bin"
    if not source_path.is_file() or not blob_path.is_file():
        raise PacketError(f"direct source/blob missing for {name}")
    source_text = source_path.read_text(encoding="utf-8")
    rows_raw = model_rows(source_text)
    commands = texture_commands(source_text)
    blob = blob_path.read_bytes()
    payload_records = []
    source_concat = bytearray()
    cursor = 0
    mip_tail_bytes = 0
    direct_offsets = sorted(
        (resource_id & 0x00FFFFFF)
        for _, resource_id, *_ in rows_raw
        if not (resource_id & 0x80000000)
    )
    for row_raw in rows_raw:
        token, resource_id, width, height, mip, type_value, depth, s_flags, t_flags = row_raw
        if resource_id & 0x80000000:
            raise PacketError(f"unexpected symbolic direct row {token}")
        source_offset = resource_id & 0x00FFFFFF
        if source_offset not in commands:
            raise PacketError(f"no G_SETTIMG evidence for {token} at 0x{source_offset:x}")
        fmt, command_size, command_load_bytes = commands[source_offset]
        # ModelFileTextures.RenderDepth is the storage depth used by the
        # loaded source row.  G_SETTIMG's image size is retained in `size` as
        # command evidence; title rows are all 16-bit image commands.
        storage_size = {0: SIZE_4B, 1: SIZE_8B, 2: SIZE_16B, 3: SIZE_32B}.get(depth)
        if storage_size is None:
            raise PacketError(f"unsupported RenderDepth {depth} for {token}")
        numerator, denominator = bytes_per_pixel(storage_size)
        base_byte_count = (width * height * numerator + denominator - 1) // denominator
        source_byte_count = base_byte_count
        # Preserve the complete source mip span in provenance.  The decoded
        # RGBA8 payload intentionally remains the base level until the MTL4
        # texture-view/material lane consumes all levels.  Generated model
        # blobs carry alignment padding between rows, so the next source-local
        # row boundary is the authoritative span for a multi-level row.
        if mip > 1:
            following = [offset for offset in direct_offsets if offset > source_offset]
            if not following:
                raise PacketError(f"mip-chain row {token} has no following source boundary")
            following_span = min(following) - source_offset
            source_byte_count = command_load_bytes or following_span
            if source_byte_count > following_span:
                raise PacketError(f"mip-chain row {token} exceeds following source boundary")
            if source_byte_count < base_byte_count:
                raise PacketError(f"mip-chain row {token} is shorter than its base level")
        end = source_offset + source_byte_count
        if end > len(blob):
            raise PacketError(f"source row {token} exceeds prepared model blob")
        source_bytes = blob[source_offset:end]
        pixels = decode_direct(source_bytes[:base_byte_count], width, height, fmt, storage_size)
        if mip > 1:
            mip_tail_bytes += len(source_bytes) - base_byte_count
        flags = source_flags((resource_id, width, height, mip, type_value, depth, s_flags, t_flags), True, fmt, storage_size)
        fields = record(
            row=(token, resource_id, width, height, mip, type_value, depth, s_flags, t_flags),
            fmt=fmt, size=command_size, source_stride=width * numerator // denominator,
            source_offset=source_offset, source_bytes=source_bytes, pixels=pixels,
            flags=flags, payload_offset=cursor,
        )
        payload_records.append((fields, pixels))
        source_concat.extend(source_bytes)
        cursor += len(pixels)
    packet_bytes = packet(handle, rows_raw, payload_records, bytes(source_concat), FLAG_DIRECT_MODEL)
    path = output_root / f"{name}.gett"
    path.write_bytes(packet_bytes)
    return packet_bytes, {
        "name": name, "handle": handle, "records": len(rows_raw), "payload": cursor,
        "mip_payload_lowered": "base-only", "mip_tail_bytes": mip_tail_bytes,
        "path": str(path),
    }


def lower_wallet(root: Path, output_root: Path, handle: int) -> tuple[bytes, dict]:
    source_path = root / "assets/obseg/prop/walletbond/Model.c"
    if not source_path.is_file():
        raise PacketError("walletbond Model.c is missing")
    rows_raw = model_rows(source_path.read_text(encoding="utf-8"))
    tex2png = find_tex2png(root)
    payload_records = []
    source_concat = bytearray()
    cursor = 0
    with tempfile.TemporaryDirectory(prefix="goldeneye-title-textures-") as temp:
        temp_root = Path(temp)
        for row_raw in rows_raw:
            token, resource_id, width, height, mip, type_value, depth, s_flags, t_flags = row_raw
            if not (resource_id & 0x80000000):
                raise PacketError(f"wallet row {token} is not symbolic")
            image_path = root / "assets/images/split" / f"{token.removeprefix('IMAGE_')}.bin"
            if not image_path.is_file():
                raise PacketError(f"wallet source image is missing: {image_path}")
            source_bytes = image_path.read_bytes()
            stream_format, _ = stream_format_and_compression(source_bytes)
            result = subprocess.run(
                [str(tex2png), str(image_path), str(temp_root)],
                check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            )
            del result
            png_path = temp_root / f"{token.removeprefix('IMAGE_')}-0.png"
            if not png_path.is_file():
                raise PacketError(f"tex2png did not emit base image for {token}")
            decoded_width, decoded_height, pixels = decode_png(png_path.read_bytes())
            if (decoded_width, decoded_height) != (width, height):
                raise PacketError(
                    f"wallet {token} dimensions {(decoded_width, decoded_height)} != {(width, height)}"
                )
            flags = source_flags((resource_id, width, height, mip, type_value, depth, s_flags, t_flags), False, stream_format, depth)
            fields = record(
                row=(token, resource_id, width, height, mip, type_value, depth, s_flags, t_flags),
                fmt=stream_format, size=depth, source_stride=0,
                source_offset=0, source_bytes=source_bytes, pixels=pixels,
                flags=flags, payload_offset=cursor,
            )
            payload_records.append((fields, pixels))
            source_concat.extend(source_bytes)
            cursor += len(pixels)
    packet_bytes = packet(handle, rows_raw, payload_records, bytes(source_concat), FLAG_IMAGE_STREAM)
    path = output_root / "walletbond.gett"
    path.write_bytes(packet_bytes)
    return packet_bytes, {
        "name": "walletbond", "handle": handle, "records": len(rows_raw), "payload": cursor,
        "mip_payload_lowered": "base-only", "mip_tail_bytes": "encoded-stream-source-preserved",
        "path": str(path),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    root = args.project_root.resolve()
    output_root = args.output_root.resolve()
    output_root.mkdir(parents=True, exist_ok=True)
    rows = []
    packets = []
    for name, handle, relative in MODEL_SPECS[:3]:
        packet_bytes, detail = lower_direct(root, output_root, name, handle, relative)
        packets.append(packet_bytes)
        rows.append(detail)
    packet_bytes, detail = lower_wallet(root, output_root, MODEL_SPECS[3][1])
    packets.append(packet_bytes)
    rows.append(detail)
    report_lines = [
        "report_version=1",
        "goal=native-boot-menu-attract-120",
        "runtime_rom_access=false",
        "visual_parity=not-claimed",
        "status=PASS",
    ]
    for detail, packet_bytes in zip(rows, packets):
        report_lines.extend([
            f"{detail['name']}_handle={detail['handle']}",
            f"{detail['name']}_records={detail['records']}",
            f"{detail['name']}_payload_bytes={detail['payload']}",
            f"{detail['name']}_mip_payload_lowered={detail['mip_payload_lowered']}",
            f"{detail['name']}_mip_tail_bytes={detail['mip_tail_bytes']}",
            f"{detail['name']}_packet_sha256={hashlib.sha256(packet_bytes).hexdigest()}",
            f"{detail['name']}_path={detail['path']}",
        ])
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text("\n".join(report_lines) + "\n", encoding="utf-8")
    print("native title textures: PASS")
    for detail, packet_bytes in zip(rows, packets):
        print(
            f"  {detail['name']}: handle={detail['handle']} records={detail['records']} "
            f"payload={detail['payload']} packet={hashlib.sha256(packet_bytes).hexdigest()}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
