#!/usr/bin/env python3
"""Emit guarded GESM/resource sidecars for setup-reachable stage models.

This is an additive stage catalog. It reuses the checked-in source model
parser and GESM writer, but scopes the input set to the corrected unique prop
and character rows already proven by ``stage-setup-model-dependencies-manifest``.
No MIPS, ROM access, or source pointer is introduced into the sidecar.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path


class PreparationError(RuntimeError):
    pass


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_rows(root: Path, visible_root: Path) -> list[dict[str, str]]:
    manifest = visible_root / "ramrom-visible-dependencies-v6-manifest.txt"
    if not manifest.is_file():
        raise PreparationError(f"setup dependency manifest is missing: {manifest}")
    lines = manifest.read_text(encoding="utf-8").splitlines()
    values = dict(
        line.split("=", 1)
        for line in lines
        if "=" in line and not re.match(r"dependency_\d+=", line)
    )
    if values.get("manifest_status") != "PASS" or values.get("dependency_count") != "953":
        raise PreparationError("visible dependency manifest is not the verified preparation")
    rows = []
    seen: set[tuple[str, str]] = set()
    for line in lines:
        if not re.match(r"dependency_\d+=", line):
            continue
        fields = dict(item.split(":", 1) for item in line.split("=", 1)[1].split("|"))
        if fields.get("category") not in {"props", "guards"}:
            continue
        kind = "prop" if fields["dependency_kind"] == "prop" else "character"
        symbol = fields["symbol"]
        model_name = symbol.split("_", 2)[-1]
        fields["kind"] = kind
        fields["model_name"] = model_name
        fields["decoded_path"] = fields["decoded_file"]
        key = (kind, fields["model_index"])
        if key in seen:
            continue
        seen.add(key)
        rows.append(fields)
    if len(rows) != 179:
        raise PreparationError(f"visible dependency model rows {len(rows)} != 179")
    return rows


def decode_global_image(root: Path, name: str, source: bytes, temp_root: Path):
    sys.path.insert(0, str(root / "scripts"))
    from prepare_native_title_icons import decode_png
    from goldeneye_pd_image_decoder_v6 import generate_source_mips

    input_path = temp_root / f"{name}.bin"
    output_dir = temp_root / name
    output_dir.mkdir(parents=True, exist_ok=True)
    input_path.write_bytes(source)
    tex2png = root / "tools/mktex/build/tex2png"
    if not tex2png.is_file():
        raise PreparationError("corrected tex2png is missing; run the PD decoder preparation first")
    subprocess.run(
        [str(tex2png), str(input_path), str(output_dir), "--no-flip"],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    levels = []
    for png in sorted(output_dir.glob(f"{name}-*.png"), key=lambda p: int(p.stem.rsplit("-", 1)[1])):
        level = int(png.stem.rsplit("-", 1)[1])
        width, height, pixels = decode_png(png.read_bytes())
        levels.append({"level": level, "width": width, "height": height, "decoded": pixels, "raw": pixels, "source_offset": 0})
    if not levels:
        raise PreparationError(f"global image {name} produced no source levels")
    if len(levels) < 1:
        raise PreparationError(f"global image {name} has no base level")
    return levels


def add_global_image_records(catalog, root: Path, image_name: str, owner_source: bytes, mip_levels: int, temp_root: Path, tlut_specs: dict[str, dict[str, str]]) -> None:
    sys.path.insert(0, str(root / "scripts"))
    from goldeneye_pd_image_decoder_v6 import generate_source_mips
    image_path = root / "assets/images/split" / f"{image_name}.bin"
    if not image_path.is_file():
        raise PreparationError(f"global image row is missing: {image_path}")
    source = image_path.read_bytes()
    levels = decode_global_image(root, image_name, source, temp_root)
    if mip_levels > len(levels):
        generated = generate_source_mips(source, mip_levels, flip=False)
        levels = [
            {"level": image.level, "width": image.width, "height": image.height, "decoded": image.rgba8, "raw": image.storage, "source_offset": 0}
            for image in generated
        ]
    if mip_levels > len(levels):
        raise PreparationError(f"global image {image_name} source levels {len(levels)} < requested {mip_levels}")
    base = levels[0]
    image_record = catalog.add(
        family="ramrom-stage", category="image_stream", name=image_name,
        source_path=f"assets/images/split/{image_name}.bin", source=source,
        raw=source, decoded=base["decoded"],
        metadata={"width": base["width"], "height": base["height"], "mip_levels": mip_levels, "source_offset": 0, "source_row": image_name},
        flags=("GLOBAL_IMAGE", "PROVENANCE_ONLY", "SOURCE_ORDER_RGBA8"),
    )
    catalog.add(
        family="ramrom-stage", category="texture_payload", name=f"{image_name}.payload",
        source_path=f"assets/images/split/{image_name}.bin", source=source,
        raw=source, decoded=base["decoded"],
        metadata={"width": base["width"], "height": base["height"], "mip_levels": mip_levels, "source_offset": 0, "source_row": image_name, "image_stream_record_id": image_record["id"]},
        flags=("GLOBAL_TEXTURE_PAYLOAD", "DECODED_RGBA8_BASE_LEVEL", "SOURCE_ORDER_RGBA8"),
    )
    try:
        from prepare_native_source_frontend_v6 import _extract_pd_palette
        palette = _extract_pd_palette(source)
    except Exception:
        palette = None
    if palette is not None:
        raw, decoded, metadata = palette
        name = f"{image_name}.tlut"
        catalog.add(
            family="ramrom-stage", category="tlut_payload", name=name,
            source_path=f"assets/images/split/{image_name}.bin", source=source,
            raw=raw, decoded=decoded,
            metadata={**metadata, "source_row": image_name},
            flags=("PD_TLUT", "DECODED_RGBA8_ENTRIES"),
        )
        tlut_specs[image_name] = {"name": name}
    for level in levels[1:mip_levels]:
        catalog.add(
            family="ramrom-stage", category="mip_payload", name=f"{image_name}.mip.{level['level']}",
            source_path=f"assets/images/split/{image_name}.bin", source=source,
            raw=level["raw"], decoded=level["decoded"],
            metadata={"texture_index": 0, "level": level["level"], "source_offset": 0, "source_row": image_name, "width": level["width"], "height": level["height"]},
            flags=("GLOBAL_IMAGE_MIP", "SOURCE_AUTHORED_MIP", "DECODED_RGBA8", "SOURCE_ORDER_RGBA8"),
        )


def validate_sidecar_mip_relationships(frontend, path: Path) -> None:
    data = path.read_bytes()
    fields = frontend.GESM_HEADER.unpack_from(data, 0)
    counts = {
        "nodes": fields[6], "scalars": fields[7], "display_lists": fields[8],
        "commands": fields[9], "tokens": fields[10], "vertices": fields[11],
        "textures": fields[12], "mips": fields[13], "tluts": fields[14],
    }
    offset = frontend.GESM_HEADER.size
    sections = {}
    for name, record_size in (
        ("nodes", frontend.GESM_NODE.size), ("scalars", frontend.GESM_SCALAR.size),
        ("display_lists", frontend.GESM_DISPLAY_LIST.size), ("commands", frontend.GESM_COMMAND.size),
        ("tokens", frontend.GESM_TOKEN.size), ("vertices", frontend.GESM_VERTEX.size),
        ("textures", frontend.GESM_TEXTURE.size), ("mips", frontend.GESM_MIP.size),
        ("tluts", frontend.GESM_TLUT.size),
    ):
        sections[name] = offset
        offset += counts[name] * record_size
    textures = [frontend.GESM_TEXTURE.unpack_from(data, sections["textures"] + i * frontend.GESM_TEXTURE.size) for i in range(counts["textures"])]
    mips = [frontend.GESM_MIP.unpack_from(data, sections["mips"] + i * frontend.GESM_MIP.size) for i in range(counts["mips"])]
    for texture in textures:
        index, handle, width, height, mip_count, *_rest = texture
        mip_start = texture[10]
        previous_width = width
        previous_height = height
        for level in range(mip_count):
            mip = mips[mip_start + level]
            valid_dimensions = (
                mip[2] == width and mip[3] == height
                if level == 0
                else 0 < mip[2] <= previous_width and 0 < mip[3] <= previous_height
            )
            if mip[0] != index or mip[1] != level or not valid_dimensions or mip[4] != handle:
                raise PreparationError(f"GESM texture {index} has unsupported source mip dimensions {mip[2]}x{mip[3]}")
            previous_width = mip[2]
            previous_height = mip[3]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--stage-asset-root", type=Path, required=True)
    parser.add_argument("--visible-dependency-root", type=Path, default=None)
    args = parser.parse_args()
    root = args.project_root.resolve()
    stage_root = args.stage_asset_root.resolve()
    visible_root = (args.visible_dependency_root or root / "build/native/ramrom-visible-dependencies-v6").resolve()
    sys.path.insert(0, str(root / "scripts"))
    try:
        import prepare_native_source_frontend_v6 as frontend
    except ImportError as error:
        raise PreparationError("source frontend GESM writer is unavailable") from error

    rows = read_rows(root, visible_root)
    visible_manifest_path = visible_root / "ramrom-visible-dependencies-v6-manifest.txt"
    visible_manifest_sha256 = sha256(visible_manifest_path.read_bytes())
    output = stage_root / "model-sidecars"
    output.mkdir(parents=True, exist_ok=True)
    catalog = frontend.Catalog(root=root, output=output)
    sidecars = []
    model_records = []
    image_sources: dict[str, bytes] = {}
    image_mip_levels: dict[str, int] = {}
    texture_payload_specs: dict[str, dict[int, dict]] = {}
    tlut_specs: dict[str, dict[str, str]] = {}
    unsupported_images: dict[str, str] = {}
    unsupported_models: dict[str, str] = {}
    with tempfile.TemporaryDirectory(prefix="goldeneye-stage-model-sidecars-") as temp:
        temp_root = Path(temp)
        for row in rows:
            kind = row["kind"]
            model_name = f"stage_{kind}_{int(row['model_index']):03d}_{row['model_name']}"
            source_path = root / row["source_path"]
            if not source_path.is_file():
                raise PreparationError(f"model source is missing: {source_path}")
            source = source_path.read_bytes()
            decoded_path = visible_root / row["decoded_path"]
            if not decoded_path.is_file():
                raise PreparationError(f"prepared model payload is missing: {decoded_path}")
            model_blob = decoded_path.read_bytes()
            parsed = frontend.parse_model_listing(source, model_name)
            # Populate global IMAGE rows before the sidecar writer resolves
            # their payload records. Embedded texels are lowered directly from
            # the copied model blob by the existing source helper.
            for texture in parsed["textures"]:
                resource = str(texture["resource"])
                if resource.startswith("IMAGE_"):
                    image_name = resource.removeprefix("IMAGE_")
                    image_mip_levels[image_name] = max(image_mip_levels.get(image_name, 1), max(1, int(texture["mip_tiles"])))
                    image_sources.setdefault(image_name, source)
            model_records.append((model_name, kind, source_path, source, decoded_path, model_blob, parsed))

        for image_name, owner_source in image_sources.items():
            try:
                add_global_image_records(catalog, root, image_name, owner_source, image_mip_levels[image_name], temp_root, tlut_specs)
            except Exception as error:
                unsupported_images[image_name] = str(error)

        for model_name, kind, source_path, source, decoded_path, model_blob, parsed in model_records:
            required_images = {
                str(texture["resource"]).removeprefix("IMAGE_")
                for texture in parsed["textures"]
                if str(texture["resource"]).startswith("IMAGE_")
            }
            blocked_images = sorted(required_images & unsupported_images.keys())
            if blocked_images:
                unsupported_models[model_name] = "global image dependencies: " + ",".join(blocked_images)
                continue
            payload_specs: dict[int, dict] = {}
            try:
                if not any(texture["resource"].startswith("IMAGE_") for texture in parsed["textures"]):
                    direct_payloads = frontend._extract_direct_texture_payloads(root, model_name, source.decode("utf-8"), model_blob)
                    payload_specs = frontend._add_direct_texture_payload_records(catalog, model_name, source, direct_payloads)
                graph = frontend.build_model_graph(
                    source, model_name, parsed,
                    payload_specs=payload_specs,
                    tlut_specs=tlut_specs,
                )
                family = "stage-prop" if kind == "prop" else "stage-character"
                metadata = frontend.write_sidecar(catalog, model_name, family, source, graph)
                validate_sidecar_mip_relationships(frontend, output / metadata["path"])
                sidecars.append(metadata)
            except Exception as error:
                unsupported_models[model_name] = str(error)

    # The GESM packet carries only fixed-width payload record IDs. Preserve
    # the guarded decoded bytes those IDs refer to beside the sidecars so the
    # runtime can upload source model textures without reopening the ROM or
    # silently aliasing a stage texture with different provenance.
    payload_records = []
    blob_data = b"".join(catalog.blobs)
    for record in catalog.records:
        if record["category"] not in {"texture_payload", "mip_payload", "tlut_payload"}:
            continue
        raw_offset = int(record["raw_payload_offset"])
        decoded_offset = int(record["decoded_payload_offset"])
        raw_size = int(record["raw_size"])
        decoded_size = int(record["decoded_size"])
        raw = blob_data[raw_offset:raw_offset + raw_size]
        decoded = blob_data[decoded_offset:decoded_offset + decoded_size]
        if len(raw) != raw_size or len(decoded) != decoded_size:
            raise PreparationError(f"sidecar payload blob bounds failed for record {record['id']}")
        safe_name = re.sub(r"[^A-Za-z0-9_.-]+", "_", record["name"])
        raw_file = f"payloads/{record['category']}/{safe_name}.raw"
        decoded_file = f"payloads/{record['category']}/{safe_name}.decoded"
        frontend._write_source_blob(output, record["category"], record["name"], raw, decoded)
        payload_records.append({
            "id": int(record["id"]),
            "category": record["category"],
            "name": record["name"],
            "raw_size": raw_size,
            "decoded_size": decoded_size,
            "raw_sha256": sha256(raw),
            "decoded_sha256": sha256(decoded),
            "raw_file": raw_file,
            "decoded_file": decoded_file,
            "metadata": record.get("metadata", {}),
            "flags": record.get("flags", []),
        })
    payload_manifest = {
        "manifest_version": 1,
        "status": "PASS",
        "runtime_opens_rom": False,
        "runtime_consumes_prepared_payloads_only": True,
        "record_count": len(payload_records),
        "records": sorted(payload_records, key=lambda row: row["id"]),
    }
    payload_manifest_path = output / "stage-model-sidecar-payloads-manifest.json"
    payload_manifest_path.write_text(
        json.dumps(payload_manifest, sort_keys=True, indent=2) + "\n", encoding="utf-8"
    )
    manifest = {
        "status": "PASS" if len(sidecars) == len(model_records) else "PARTIAL_FAIL_CLOSED",
        "asset_family": "ramrom_stage_model_sidecars",
        "runtime_rom_access": False,
        "model_count": len(model_records),
        "sidecar_count": len(sidecars),
        "sidecars": sorted(sidecars, key=lambda row: row["name"]),
        "props": sum(1 for _, kind, *_ in model_records if kind == "prop"),
        "characters": sum(1 for _, kind, *_ in model_records if kind == "character"),
        "visible_manifest_sha256": visible_manifest_sha256,
        "unsupported_images": unsupported_images,
        "unsupported_models": unsupported_models,
        "payload_manifest": payload_manifest_path.name,
        "payload_record_count": len(payload_records),
        "payload_status": "PASS",
    }
    (output / "stage-model-sidecars-manifest.json").write_text(
        __import__("json").dumps(manifest, sort_keys=True, indent=2) + "\n", encoding="utf-8"
    )
    (output / "stage-model-sidecars-manifest.txt").write_text(
        "\n".join([
            "manifest_version=1", "asset_family=ramrom_stage_model_sidecars", f"status={manifest['status']}",
            "runtime_rom_access=false", f"model_count={len(model_records)}", f"sidecar_count={len(sidecars)}",
            f"props={manifest['props']}", f"characters={manifest['characters']}",
            f"visible_manifest_sha256={visible_manifest_sha256}",
            f"unsupported_image_count={len(unsupported_images)}",
            f"unsupported_model_count={len(unsupported_models)}",
            f"payload_record_count={len(payload_records)}",
            "payload_status=PASS",
        ]) + "\n", encoding="utf-8"
    )
    print(f"Native stage GESM sidecar preparation: PASS models={len(model_records)} props={manifest['props']} characters={manifest['characters']}")
    print(f"Sidecar root: {output}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PreparationError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
