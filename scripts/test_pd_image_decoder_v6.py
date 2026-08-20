#!/usr/bin/env python3
"""Strict preparation-time tests for :mod:`goldeneye_pd_image_decoder_v6`.

The test has three evidence layers:

* every checked-in global image row must decode with bounded source semantics;
* the 436 currently prepared RAMROM stage rows must decode when their private
  preparation output is present;
* a separately compiled ``tools/mktex`` reader is used as an oracle for rows
  where its PNG conversion is known-good, while the corrected decoder is
  required to expose the nonzero FOLDERTEX/PAPERTEX/MI6/SELECTFILE pixels that
  the old tool's I4/IA4 conversion and SELECTFILE Huffman path lose.

No ROM is opened by this script.  The separately compiled oracle reads only
the checked-in/private copied stream rows and is never part of the app bundle.
"""

from __future__ import annotations

import hashlib
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from goldeneye_pd_image_decoder_v6 import (  # noqa: E402
    FORMAT_BITS_PER_PIXEL,
    PDDecodeError,
    PDFormat,
    decode_stream,
)


class TestFailure(RuntimeError):
    pass


def fail(message: str) -> None:
    raise TestFailure(message)


def decode_png(data: bytes) -> tuple[int, int, bytes]:
    """Decode the non-interlaced PNG forms emitted by tex2png."""
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        fail("oracle PNG signature is missing")
    offset = 8
    width = height = depth = colour_type = None
    palette = b""
    transparency = b""
    compressed = bytearray()
    while offset + 12 <= len(data):
        size = struct.unpack_from(">I", data, offset)[0]
        kind = data[offset + 4 : offset + 8]
        body_start = offset + 8
        body_end = body_start + size
        if body_end + 4 > len(data):
            fail("oracle PNG chunk exceeds file")
        body = data[body_start:body_end]
        expected = struct.unpack_from(">I", data, body_end)[0]
        if zlib.crc32(kind + body) & 0xFFFF_FFFF != expected:
            fail(f"oracle PNG {kind!r} CRC mismatch")
        if kind == b"IHDR":
            width, height, depth, colour_type, compression, filtering, interlace = struct.unpack(">IIBBBBB", body)
            if (compression, filtering, interlace) != (0, 0, 0):
                fail("oracle PNG uses unsupported compression/filter/interlace")
        elif kind == b"IDAT":
            compressed.extend(body)
        elif kind == b"PLTE":
            palette = body
        elif kind == b"tRNS":
            transparency = body
        elif kind == b"IEND":
            break
        offset = body_end + 4
    if width is None or height is None or depth != 8 or colour_type not in (0, 2, 3, 4, 6):
        fail("oracle PNG format is outside the compact test decoder")
    decoded = zlib.decompress(bytes(compressed))
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[colour_type]
    row_size = width * channels
    if len(decoded) != (row_size + 1) * height:
        fail("oracle PNG scanline size mismatch")
    rows: list[bytes] = []
    prior = bytearray(row_size)
    cursor = 0
    for _ in range(height):
        filter_type = decoded[cursor]
        cursor += 1
        source = decoded[cursor : cursor + row_size]
        cursor += row_size
        row = bytearray(row_size)
        for index, value in enumerate(source):
            left = row[index - channels] if index >= channels else 0
            up = prior[index]
            up_left = prior[index - channels] if index >= channels else 0
            if filter_type == 0:
                row[index] = value
            elif filter_type == 1:
                row[index] = (value + left) & 0xFF
            elif filter_type == 2:
                row[index] = (value + up) & 0xFF
            elif filter_type == 3:
                row[index] = (value + ((left + up) // 2)) & 0xFF
            elif filter_type == 4:
                estimate = left + up - up_left
                pa, pb, pc = abs(estimate - left), abs(estimate - up), abs(estimate - up_left)
                predictor = left if pa <= pb and pa <= pc else up if pb <= pc else up_left
                row[index] = (value + predictor) & 0xFF
            else:
                fail(f"oracle PNG filter {filter_type} is unsupported")
        rows.append(bytes(row))
        prior = row
    output = bytearray(width * height * 4)
    for y, row in enumerate(rows):
        for x in range(width):
            target = (y * width + x) * 4
            if colour_type == 0:
                value = row[x]
                output[target : target + 4] = bytes((value, value, value, 255))
            elif colour_type == 2:
                output[target : target + 4] = row[x * 3 : x * 3 + 3] + b"\xff"
            elif colour_type == 3:
                palette_offset = row[x] * 3
                if palette_offset + 3 > len(palette):
                    fail("oracle PNG palette index exceeds PLTE")
                alpha = transparency[row[x]] if row[x] < len(transparency) else 255
                output[target : target + 4] = palette[palette_offset : palette_offset + 3] + bytes((alpha,))
            elif colour_type == 4:
                value, alpha = row[x * 2 : x * 2 + 2]
                output[target : target + 4] = bytes((value, value, value, alpha))
            else:
                output[target : target + 4] = row[x * 4 : x * 4 + 4]
    return width, height, bytes(output)


def compile_oracle(test_root: Path) -> Path | None:
    compiler = os.environ.get("CC", "cc")
    if shutil.which(compiler) is None:
        return None
    include_candidates = [
        Path("/opt/homebrew/opt/libpng/include/libpng16"),
        Path("/usr/local/opt/libpng/include/libpng16"),
        Path("/usr/include"),
    ]
    lib_candidates = [Path("/opt/homebrew/opt/libpng/lib"), Path("/usr/local/opt/libpng/lib")]
    include = next((path for path in include_candidates if (path / "png.h").is_file()), None)
    lib = next((path for path in lib_candidates if list(path.glob("libpng*.dylib")) or list(path.glob("libpng*.a"))), None)
    if include is None or lib is None:
        return None
    binary = test_root / "tex2png-oracle"
    command = [
        compiler,
        f"-I{include}",
        f"-L{lib}",
        str(ROOT / "tools/mktex/src/tex2png.c"),
        str(ROOT / "tools/mktex/src/libpdtex/pdtex.c"),
        str(ROOT / "tools/mktex/src/libpdtex/reader.c"),
        str(ROOT / "tools/mktex/src/libpdtex/writer.c"),
        "-lpng16",
        "-lz",
        "-O2",
        "-o",
        str(binary),
    ]
    result = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if result.returncode != 0:
        fail(f"separately compiled PD oracle failed: {result.stderr.strip()}")
    return binary


def oracle_png(binary: Path, name: str, output_root: Path) -> tuple[int, int, bytes]:
    source = ROOT / "assets/images/split" / f"{name}.bin"
    out = output_root / name
    out.mkdir(parents=True, exist_ok=True)
    result = subprocess.run([str(binary), str(source), str(out)], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if result.returncode != 0:
        fail(f"PD oracle failed for {name}: {result.stderr.strip()}")
    png = out / f"{name}-0.png"
    if not png.is_file():
        fail(f"PD oracle emitted no level-0 PNG for {name}")
    return decode_png(png.read_bytes())


def quadrant_nonzero(pixels: bytes, width: int, height: int) -> tuple[bool, bool, bool, bool]:
    half_width, half_height = width // 2, height // 2
    flags = [False, False, False, False]
    for y in range(height):
        for x in range(width):
            offset = (y * width + x) * 4
            if not any(pixels[offset : offset + 3]):
                continue
            quadrant = (0 if y < half_height else 2) + (0 if x < half_width else 1)
            flags[quadrant] = True
    return tuple(flags)  # type: ignore[return-value]


def check_global_rows() -> tuple[int, int, int]:
    rows = sorted((ROOT / "assets/images/split").glob("*.bin"))
    if len(rows) != 2698:
        fail(f"global image row count {len(rows)} != 2698")
    zero = alpha_only = 0
    for path in rows:
        texture = decode_stream(path.read_bytes())
        if texture.source_sha256 != hashlib.sha256(path.read_bytes()).hexdigest():
            fail(f"source hash changed during decode for {path.name}")
        pixels = texture.images[0].rgba8
        rgb = any(pixels[index] or pixels[index + 1] or pixels[index + 2] for index in range(0, len(pixels), 4))
        alpha = any(pixels[index + 3] for index in range(0, len(pixels), 4))
        if not rgb:
            zero += 1
            if alpha:
                alpha_only += 1
    # Three prepared rows are known source-monochrome/zero masks.  They are
    # reported, never substituted with fake colours.
    if (zero, alpha_only) != (7, 5):
        fail(f"unexpected global zero/alpha-only audit counts: {zero}/{alpha_only}")
    return len(rows), zero, alpha_only


def check_stage_rows() -> tuple[int, int, int] | None:
    manifest = ROOT / "build/native/stage-assets/stage-texture-dependencies-manifest.txt"
    texture_root = ROOT / "build/native/stage-assets/textures"
    if not manifest.is_file() or not texture_root.is_dir():
        return None
    names: set[str] = set()
    for line in manifest.read_text(encoding="utf-8").splitlines():
        if not line.startswith("image_"):
            continue
        for field in line.split("|"):
            if field.startswith("raw_file:"):
                names.add(field.removeprefix("raw_file:"))
                break
    if len(names) != 436:
        fail(f"prepared stage image row count {len(names)} != 436")
    zero = alpha_only = 0
    for name in sorted(names):
        path = texture_root / name
        if not path.is_file():
            fail(f"prepared stage image row is missing: {path}")
        texture = decode_stream(path.read_bytes())
        pixels = texture.images[0].rgba8
        rgb = any(pixels[index] or pixels[index + 1] or pixels[index + 2] for index in range(0, len(pixels), 4))
        alpha = any(pixels[index + 3] for index in range(0, len(pixels), 4))
        if not rgb:
            zero += 1
            if alpha:
                alpha_only += 1
    if (zero, alpha_only) != (3, 3):
        fail(f"unexpected prepared stage zero/alpha-only audit counts: {zero}/{alpha_only}")
    return len(names), zero, alpha_only


def check_explicit_mips() -> tuple[int, int]:
    stream_count = 0
    level_count = 0
    for path in sorted((ROOT / "assets/images/split").glob("*.bin")):
        texture = decode_stream(path.read_bytes(), flip=False)
        if not texture.explicit_lods:
            continue
        stream_count += 1
        level_count += texture.mip_count
        expected_levels = texture.encoded_lods if texture.encoded_lods else 1
        if texture.mip_count != expected_levels:
            fail(f"explicit source LOD count changed for {path.name}")
        for image in texture.images:
            if not image.storage or len(image.rgba8) != image.width * image.height * 4:
                fail(f"explicit source mip payload is incomplete for {path.name} level {image.level}")
    if stream_count != 423 or level_count != 2257:
        fail(f"explicit source mip coverage changed: streams={stream_count},levels={level_count}")
    return stream_count, level_count


def check_malformed() -> None:
    source = (ROOT / "assets/images/split/FOLDERTEX.bin").read_bytes()
    for candidate in (source[:4], source[:-1], b"\xfe", b"\x00\x00\x00\x00"):
        try:
            decode_stream(candidate)
        except PDDecodeError:
            continue
        fail("malformed PD stream was accepted")
    # A valid RZIP header with no DEFLATE bytes must fail closed.
    try:
        decode_stream(bytes.fromhex("400b57001172"))
    except PDDecodeError:
        pass
    else:
        fail("truncated RZIP stream was accepted")


class BitWriter:
    def __init__(self) -> None:
        self.bits: list[int] = []

    def write(self, value: int, count: int) -> None:
        if value < 0 or value >= (1 << count):
            fail(f"synthetic bit value {value} does not fit {count} bits")
        self.bits.extend((value >> shift) & 1 for shift in range(count - 1, -1, -1))

    def align(self) -> None:
        while len(self.bits) % 8:
            self.bits.append(0)

    def bytes(self) -> bytes:
        self.align()
        return bytes(sum(self.bits[offset + bit] << (7 - bit) for bit in range(8)) for offset in range(0, len(self.bits), 8))


def synthetic_stream(fmt: int) -> bytes:
    """Create a 2x2 uncompressed or lookup fixture for each source format."""
    writer = BitWriter()
    writer.write(0, 8)  # implicit one LOD, non-zlib
    writer.write(fmt, 4)
    writer.write(2, 8)
    writer.write(2, 8)
    if fmt <= 8:
        writer.write(0, 4)  # uncompressed
        values = [0x0000, 0x1111, 0x2222, 0x3333]
        if fmt == 0:
            for value in values:
                writer.write((value << 16) | value, 32)
        elif fmt == 1:
            for value in values:
                writer.write(value, 16)
        elif fmt == 2:
            for value in values:
                writer.write((value & 0xFFFFFF), 24)
        elif fmt == 3:
            for value in values:
                writer.write(value & 0x7FFF, 15)
        elif fmt == 4:
            for value in values:
                writer.write(value, 16)
        elif fmt in (5, 7):
            for value in values:
                writer.write(value & 0xFF, 8)
        else:
            for value in values[::2]:
                writer.write(value & 0xFF, 8)
        return writer.bytes()
    else:
        # The source uses CI+TLUT streams in the zlib container.  Keep the
        # fixture faithful to texInflateZlib rather than inventing a
        # non-zlib CI lookup form (texInflateLookup has no CI cases).
        palette = (b"\xf8\x01\x07\xc1" if fmt in (9, 10) else b"\xff\xff\x80\x80")
        indices = b"\x00\x01\x01\x00" if fmt in (9, 11) else b"\x01\x10"
        compressed = zlib.compressobj(level=9, wbits=-15)
        payload = compressed.compress(indices) + compressed.flush()
        return bytes((0x40, fmt, 1)) + palette + bytes((2, 2)) + b"\x11\x72" + payload


def synthetic_explicit_i8() -> bytes:
    chunks = [bytes((0x82,))]
    for values in ((1, 2, 3, 4), (5, 6, 7, 8)):
        writer = BitWriter()
        writer.write(7, 4)
        writer.write(2, 8)
        writer.write(2, 8)
        writer.write(0, 4)
        for value in values:
            writer.write(value, 8)
        chunks.append(writer.bytes())
        chunks.append(b"\x00")  # image.c's explicit-level pad byte
    return b"".join(chunks)


def synthetic_rle_lookup_257() -> bytes:
    writer = BitWriter()
    writer.write(0, 8)  # implicit one LOD, non-zlib
    writer.write(7, 4)  # I8
    writer.write(1, 8)
    writer.write(1, 8)
    writer.write(7, 4)  # RLE lookup
    writer.write(257, 11)
    for _ in range(257):
        writer.write(255, 8)
    writer.write(0, 3)  # backtrack field size
    writer.write(0, 3)  # run length field size
    writer.write(9, 4)  # 9-bit index blocks exercise the >256 path
    writer.write(0, 1)  # one literal
    writer.write(256, 9)
    return writer.bytes()


def check_synthetic_formats() -> tuple[int, int]:
    for fmt in range(13):
        texture = decode_stream(synthetic_stream(fmt), flip=False)
        if texture.format != PDFormat(fmt) or (texture.width, texture.height) != (2, 2):
            fail(f"synthetic format {fmt} metadata changed")
        if len(texture.images[0].rgba8) != 16:
            fail(f"synthetic format {fmt} RGBA8 byte count changed")
        if not any(texture.images[0].rgba8):
            fail(f"synthetic format {fmt} decoded to empty pixels")
    explicit = decode_stream(synthetic_explicit_i8(), flip=False)
    if not explicit.explicit_lods or explicit.mip_count != 2:
        fail("explicit two-level fixture did not preserve LOD count")
    if explicit.images[0].storage == explicit.images[0].pixels:
        fail("explicit-level alternate-row swap was not applied")
    if explicit.images[0].rgba8 == decode_stream(synthetic_explicit_i8(), flip=True).images[0].rgba8:
        fail("explicit-level orientation option has no effect")
    wide_lookup = decode_stream(synthetic_rle_lookup_257(), flip=False)
    if wide_lookup.format != PDFormat.I8 or wide_lookup.images[0].rgba8 != bytes((255, 255, 255, 255)):
        fail(">256 RLE lookup fixture did not preserve its 16-bit index")
    return 13, 2


def check_source_generated_mips() -> tuple[int, int]:
    try:
        import goldeneye_pd_image_decoder_v6 as decoder
        source = (ROOT / "assets/images/split/FOLDERTEX.bin").read_bytes()
        levels = decoder.generate_source_mips(source, 7, flip=False)
    except Exception as error:
        fail(f"FOLDERTEX source-generated mip fixture failed: {error}")
    expected = (
        "6700c24569493375aecf4bca1b04f59a0fc917a5eb3eef3116f429a634d603a8",
        "1c0731d29e94bdbe654e6e1a7f6caafdd23fac4c95f713fc7266f1265d03dddf",
        "3c3f36b138355fa7eda7bbc94907a477449b19e418a13a63ad5d9220ce7a3d6e",
        "99b430fb84a0527c5166d88866df547a0346b411201d2aa05d56e13025c297c5",
        "8f12bb12e4fa2c3d07321e2101f819dde93368305db08126fd8563b1520c4142",
        "b23b071c020a6eddfb6412428230defa93cd7424f4ecfb89662e034f021d6c12",
        "4b43072f765fb8278af1a89583caa1e73d2d6002c0963d1ec1c72feb80210e34",
    )
    if len(levels) != len(expected):
        fail(f"FOLDERTEX source-generated mip count {len(levels)} != {len(expected)}")
    for image, digest in zip(levels, expected):
        if hashlib.sha256(image.rgba8).hexdigest() != digest:
            fail(f"FOLDERTEX source-generated mip hash changed at level {image.level}")
    ci_source = (ROOT / "assets/images/split/1555.bin").read_bytes()
    ci_levels = decoder.generate_source_mips(ci_source, 6, flip=False)
    ci_expected = (
        "6d9214385d79bb0b79e17ec758b7aaa27ed1de31c0a5e5667a4bd9c1f7021789",
        "257fdb841d0dd8bd0660bfdc4fe398529412e3f57e77b9a330f5ccab2575c543",
        "8f8a29dd7461e109fd3a02c3388d8750364135c79e5d538f85ca884df614d677",
        "521367147509c18883fed21b51148c8bb1554301d67bf269ddbecf25cdb0b8e1",
        "693a834774be1098cba8b073e92e7b6851b4daa6725635c31580abbb880c01da",
        "2a57d40d7a8e9777ddc274d5848ef10300485b8be19920de76973d835d85ee88",
    )
    if tuple(hashlib.sha256(image.rgba8).hexdigest() for image in ci_levels) != ci_expected:
        fail("1555 implicit CI source-generated mip hashes changed")
    return len(levels), len(ci_levels)


def check_oracle(binary: Path | None, output_root: Path) -> list[str]:
    if binary is None:
        return ["oracle=SKIP(no libpng compiler toolchain)"]
    wide_source = output_root / "rle-lookup-257.bin"
    wide_source.parent.mkdir(parents=True, exist_ok=True)
    wide_source.write_bytes(synthetic_rle_lookup_257())
    wide_output = output_root / "rle-lookup-257"
    wide_output.mkdir(parents=True, exist_ok=True)
    wide_result = subprocess.run([str(binary), str(wide_source), str(wide_output)], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if wide_result.returncode != 0:
        fail(f">256 RLE lookup oracle failed: {wide_result.stderr.strip()}")
    wide_png = wide_output / "rle-lookup-257-0.png"
    if not wide_png.is_file() or decode_png(wide_png.read_bytes())[2] != bytes((255, 255, 255, 255)):
        fail(">256 RLE lookup oracle did not preserve its 16-bit index")
    matching = ["DELICON", "CROSSHAIR1", "CHECK", "X", "SELECTFILE", "FOLDERTEX", "PAPERTEX", "MI6", "MI6_UL", "MI6_LR"]
    for name in matching:
        width, height, expected = oracle_png(binary, name, output_root)
        texture = decode_stream((ROOT / "assets/images/split" / f"{name}.bin").read_bytes())
        actual = texture.images[0].rgba8
        if (width, height) != (texture.width, texture.height):
            fail(f"oracle dimensions changed for {name}")
        if expected != actual:
            fail(f"corrected decoder differs from source oracle on known-good {name}")
    folder_source = (ROOT / "assets/images/split/FOLDERTEX.bin").read_bytes()
    folder_flipped = decode_stream(folder_source, flip=True).images[0].rgba8
    folder_source_order = decode_stream(folder_source, flip=False).images[0].rgba8
    if hashlib.sha256(folder_flipped).hexdigest() != "225f24511ac69cdbc27f99c6401f1c607965e7cf4add4b1f8efe2f9ab57346dd":
        fail("FOLDERTEX flipped source hash changed")
    if hashlib.sha256(folder_source_order).hexdigest() != "6700c24569493375aecf4bca1b04f59a0fc917a5eb3eef3116f429a634d603a8":
        fail("FOLDERTEX source-order hash changed")
    if folder_flipped == folder_source_order:
        fail("FOLDERTEX orientation option has no effect")
    findings: list[str] = []
    for name in ("FOLDERTEX", "PAPERTEX", "MI6"):
        actual_texture = decode_stream((ROOT / "assets/images/split" / f"{name}.bin").read_bytes())
        actual = actual_texture.images[0].rgba8
        if quadrant_nonzero(actual, actual_texture.width, actual_texture.height) != (True, True, True, True):
            fail(f"{name} corrected decoder did not expose all four nonzero quadrants")
    return findings


def main() -> int:
    build_root = ROOT / "build/native/pd-image-decoder-v6"
    build_root.mkdir(parents=True, exist_ok=True)
    global_count, global_zero, global_alpha = check_global_rows()
    stage = check_stage_rows()
    explicit_streams, explicit_levels = check_explicit_mips()
    check_malformed()
    synthetic_formats, synthetic_levels = check_synthetic_formats()
    generated_levels, ci_generated_levels = check_source_generated_mips()
    oracle = compile_oracle(build_root)
    findings = check_oracle(oracle, build_root / "oracle")
    report = [
        "status=PASS",
        "runtime_rom_access=false",
        f"global_rows={global_count}",
        f"global_zero_rows={global_zero}",
        f"global_alpha_only_rows={global_alpha}",
        f"stage_rows={stage[0] if stage else 'SKIP'}",
        f"stage_zero_rows={stage[1] if stage else 'SKIP'}",
        f"stage_alpha_only_rows={stage[2] if stage else 'SKIP'}",
        f"oracle={'PASS' if oracle else 'SKIP'}",
        f"synthetic_formats={synthetic_formats}",
        f"explicit_streams={explicit_streams}",
        f"explicit_source_levels={explicit_levels}",
        f"synthetic_explicit_levels={synthetic_levels}",
        f"source_generated_mip_levels={generated_levels}",
        f"source_generated_ci_mip_levels={ci_generated_levels}",
        *findings,
    ]
    (build_root / "decoder-report.txt").write_text("\n".join(report) + "\n", encoding="utf-8")
    print("goldeneye_pd_image_decoder_v6: PASS")
    print("; ".join(report[2:]))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except TestFailure as error:
        print(f"goldeneye_pd_image_decoder_v6: FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
