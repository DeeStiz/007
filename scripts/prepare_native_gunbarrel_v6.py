#!/usr/bin/env python3
"""Prepare the source-owned dynamic Gunbarrel animation/attachment sidecar.

The sidecar is private ignored preparation output.  It contains copied raw
animation clip words, source skeleton joint tables, and the authored PP7
gunfire/attachment contract.  Runtime consumes this value packet only; it
never opens the source checkout or the external ROM.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import struct
from typing import Any


CLIP_SPECS = {
    "bond_eye_walk": {
        "entry_offset": 0x5484C,
        "data_offset": 0x4144,
        "header_word": 0x00230C01,
        "descriptor_offset": 0x40E8,
        "bit_stream_offset": 0x4100,
        "stride_word": 0x000F0220,
    },
    "bond_eye_fire": {
        "entry_offset": 0x55198,
        "data_offset": 0x4298,
        "header_word": 0x007C0C00,
        "descriptor_offset": 0x4158,
        "bit_stream_offset": 0x4170,
        "stride_word": 0x00130220,
    },
}

# The frontend Cast reel selects these source animation-table entries. They
# share the same packed guard skeleton/bitstream format as the two Gunbarrel
# clips above; their authored headers/descriptor offsets/strides are read
# directly from each ANIM_DATA_* row during preparation.
CAST_CLIP_NAMES = (
    "spotting_bond",
    "fire_standing_draw_one_handed_weapon_fast",
    "fire_standing_draw_one_handed_weapon_slow",
    "fire_step_right_one_handed_weapon",
    "fire_kneel_forward_one_handed_weapon_fast",
    "running_one_handed_weapon",
    "draw_one_handed_weapon_and_stand_up",
    "aim_one_handed_weapon_left_right",
    "cock_one_handed_weapon_and_turn_around",
    "cock_one_handed_weapon_turn_around_and_stand_up",
    "draw_one_handed_weapon_and_turn_around",
    "drop_weapon_and_show_fight_stance",
    "laughing_in_disbelief",
    "fire_hip_forward_one_handed_weapon",
    "fire_standing_left_one_handed_weapon_fast",
    "fire_kneel_left_one_handed_weapon_fast",
    "draw_one_handed_weapon_and_look_around",
    "aim_one_handed_weapon_left",
    "aim_one_handed_weapon_right",
    "conversation",
    "conversation_listener",
    "conversation_cleaned",
)

SKELETON_SPECS = {
    "guard": "assets/embedded/skeletons/guard.inc.c",
    "standard_gun": "assets/embedded/skeletons/standard_gun.inc.c",
    "gun_kf7": "assets/embedded/skeletons/gun_kf7.inc.c",
}

MODEL_SPECS = {
    "body": (8, "assets/obseg/chr/suitbond/Model.c", "guard"),
    "head": (7, "assets/obseg/chr/headbrosnansuit/Model.c", "guard"),
    "weapon": (9, "assets/obseg/prop/chrwppk/Model.c", "gun_kf7"),
}

SOURCE_HASH_GUARDS = {
    "assets/animationtable_data.c": "10c7d269838699e2514429b128bb8deca24c9a2855a76fed2930a53c2ab47320",
    "assets/animationtable_entries.c": "9b5e8898e10dc43f3e1dc70b7b43bea84d36b89dc5d25df4369688ce8f5aabbe",
    "src/game/model.c": "fe3499e4792103b338970b32a345a59633df1333116a3536c23b9df87baa6118",
    "assets/embedded/skeletons/guard.inc.c": "6e6ff302dda803129066b956fda52ea9cf5e9a7cb03fe014290560e2396e2074",
    "assets/embedded/skeletons/standard_gun.inc.c": "3fbed7795ebc79d7caef20956bb71efe644ce31047f5ce8e9a43f771479b212f",
    "assets/embedded/skeletons/gun_kf7.inc.c": "b8165dad93eddaedb00a6bf3d954737dd1b0d866673485383a3482c2f89e9906",
}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def source(root: pathlib.Path, relative: str) -> tuple[pathlib.Path, bytes]:
    path = root / relative
    data = path.read_bytes()
    expected = SOURCE_HASH_GUARDS.get(relative)
    if expected and sha256(data) != expected:
        raise ValueError(f"source hash guard failed for {relative}")
    return path, data


def numeric_values(body: str) -> list[int]:
    return [int(value, 0) for value in re.findall(r"0x[0-9A-Fa-f]+|\b\d+\b", body)]


def parse_array(text: str, prefix: str) -> list[int]:
    match = re.search(rf"u32\s+{re.escape(prefix)}\[\]\s*=\s*\{{(.*?)\}};", text, re.S)
    if not match:
        raise ValueError(f"missing {prefix}")
    return numeric_values(match.group(1))


def parse_joint_list(text: str, name: str) -> list[dict[str, int]]:
    match = re.search(rf"ModelJoint\s+JOINTLIST\({re.escape(name)}\)\[\]\s*=\s*\{{(.*?)\}};", text, re.S)
    if not match:
        raise ValueError(f"missing JOINTLIST({name})")
    joints = []
    for record in re.findall(r"\{\s*([^{}]+?)\s*\}", match.group(1)):
        values = numeric_values(record)
        if len(values) != 3:
            raise ValueError(f"malformed joint {name}: {record}")
        joints.append({"node_type": values[0], "mtx_a": values[1], "mtx_b": values[2]})
    if not joints:
        raise ValueError(f"empty JOINTLIST({name})")
    return joints


def words_to_bytes(words: list[int]) -> bytes:
    return b"".join(struct.pack(">I", value & 0xFFFFFFFF) for value in words)


def data_table_bytes(data_source: str) -> bytes:
    words: list[int] = []
    for match in re.finditer(
        r"u32\s+ANIM_DATA_[A-Za-z0-9_]+\[\]\s*=\s*\{(.*?)\};",
        data_source,
        re.S,
    ):
        for token in re.findall(
            r"PTR_[A-Za-z0-9_]+|0x[0-9A-Fa-f]+|\b\d+\b",
            match.group(1),
        ):
            words.append(0 if token.startswith("PTR_") else int(token, 0))
    return words_to_bytes(words)


def parse_clip(
    data_source: str,
    entries_source: str,
    data_table: bytes,
    name: str,
) -> dict[str, Any]:
    data_words = parse_array(data_source, f"ANIM_DATA_{name}")
    entry_words = parse_array(entries_source, f"ANIM_ENTRY_{name}")
    if not data_words or not entry_words:
        raise ValueError(f"empty animation {name}")
    header = data_words[0]
    spec = CLIP_SPECS.get(name)
    if spec is None:
        # ANIM_DATA rows carry the same offsets used by the expanded source
        # ModelAnimation record: descriptor table at word 2, packed bitstream
        # at word 4, and bit stride/frame size at word 3. Keep the copied
        # source offsets as evidence; no runtime pointer/address is emitted.
        if len(data_words) < 5:
            raise ValueError(f"{name} animation header is truncated")
        spec = {
            "entry_offset": 0,
            "data_offset": data_words[1],
            "header_word": header,
            "descriptor_offset": data_words[1],
            "bit_stream_offset": data_words[3],
            "stride_word": data_words[2],
        }
    elif header != spec["header_word"]:
        raise ValueError(f"{name} header 0x{header:x} != 0x{spec['header_word']:x}")
    # The packed source header stores frame count in the full 16-bit
    # high-half. Most clips fit in one byte, while Cast's spotting_bond uses
    # 0x01bf (447 frames) and must not truncate to 191.
    frame_count = (header >> 16) & 0xFFFF
    bit_width = (header >> 8) & 0xFF
    loop_flags = header & 0xFF
    stride = spec["stride_word"]
    bit_stride = (stride >> 16) & 0xFFFF
    frame_bits = stride & 0xFFFF
    if frame_bits == 0 or frame_bits % 8:
        raise ValueError(f"{name} frame bits are not byte aligned")
    frame_bytes = frame_bits // 8
    expected_bytes = frame_count * frame_bytes
    entry_bytes = words_to_bytes(entry_words)
    if len(entry_bytes) != expected_bytes:
        raise ValueError(f"{name} bytes {len(entry_bytes)} != {expected_bytes}")
    descriptor_bytes = data_table[
        spec["descriptor_offset"] : spec["descriptor_offset"] + 24
    ]
    if len(descriptor_bytes) != 24:
        raise ValueError(f"{name} root descriptor table is truncated")
    descriptors = []
    for offset in range(0, 24, 6):
        bit_offset, bit_count, padding, value_offset = struct.unpack_from(
            ">HBBH", descriptor_bytes, offset
        )
        if padding != 0 or bit_count > 16:
            raise ValueError(f"{name} root descriptor {offset // 6} is malformed")
        descriptors.append(
            {
                "bit_offset": bit_offset,
                "bit_count": bit_count,
                "value_offset": value_offset,
            }
        )
    return {
        "name": name,
        "entry_offset": spec["entry_offset"],
        "data_offset": spec["data_offset"],
        "descriptor_offset": spec["descriptor_offset"],
        "bit_stream_offset": spec["bit_stream_offset"],
        "frame_count": frame_count,
        "bit_width": bit_width,
        "loop_flags": loop_flags,
        "bit_stride": bit_stride,
        "frame_bytes": frame_bytes,
        "frame_bits": frame_bits,
        "entry_word_count": len(entry_words),
        "entry_sha256": sha256(entry_bytes),
        "entry_words": entry_words,
        "root_motion_descriptors": descriptors,
        "root_motion_descriptor_sha256": sha256(descriptor_bytes),
    }


def prepare(root: pathlib.Path) -> dict[str, Any]:
    data_path, data_bytes = source(root, "assets/animationtable_data.c")
    entries_path, entries_bytes = source(root, "assets/animationtable_entries.c")
    data_text = data_bytes.decode("utf-8")
    entries_text = entries_bytes.decode("utf-8")
    data_table = data_table_bytes(data_text)
    clip_names = (*CLIP_SPECS.keys(), *CAST_CLIP_NAMES)
    clips = [
        parse_clip(data_text, entries_text, data_table, name)
        for name in clip_names
    ]
    blood_path, blood_source_bytes = source(root, "src/game/blood_animation.c")
    blood_match = re.search(r"u8\s+die_blood_image_1\[\]\s*=\s*\{(.*?)\};", blood_source_bytes.decode("utf-8"), re.S)
    if not blood_match:
        raise ValueError("missing die_blood_image_1 source row")
    blood_encoded = bytes(numeric_values(blood_match.group(1)))
    if len(blood_encoded) != 2524:
        raise ValueError(f"blood encoded bytes {len(blood_encoded)} != 2524")

    skeletons = []
    for name, relative in SKELETON_SPECS.items():
        path, data = source(root, relative)
        joints = parse_joint_list(data.decode("utf-8"), name)
        mode_match = re.search(rf"MODELSKELETON\({re.escape(name)},\s*([^,]+),\s*([^\)]+)\)", data.decode("utf-8"))
        if not mode_match:
            raise ValueError(f"missing MODELSKELETON({name})")
        skeletons.append({
            "name": name,
            "source_path": relative,
            "source_sha256": sha256(data),
            "joint_count": len(joints),
            "skeleton_size": int(mode_match.group(2).strip(), 0),
            "joints": joints,
        })

    models = []
    for role, (handle, relative, skeleton) in MODEL_SPECS.items():
        _, data = source(root, relative)
        source_model_handle = None
        gesm_path = root / "build/native/source-frontend-v6" / ("suitbond.gesm" if role == "body" else "headbrosnansuit.gesm" if role == "head" else "chrwppk.gesm")
        if gesm_path.is_file():
            gesm = gesm_path.read_bytes()
            if len(gesm) >= 12 and gesm[:4] == b"GESM":
                source_model_handle = struct.unpack_from("<I", gesm, 8)[0]
        models.append({
            "role": role,
            "model_handle": handle,
            "source_model_handle": source_model_handle,
            "source_path": relative,
            "source_sha256": sha256(data),
            "skeleton": skeleton,
        })

    weapon_path, weapon_bytes = source(root, "assets/obseg/prop/chrwppk/Model.c")
    gunfire_match = re.search(
        r"ModelRoData_GunfireRecord\s+GunfireRecord_[^=]+\s*=\s*\{(.*?)\n\};\n\nu32 PADDING_0x434",
        weapon_bytes.decode("utf-8"),
        re.S,
    )
    if not gunfire_match:
        raise ValueError("missing PP7 GunfireRecord")
    floats = re.findall(r"[-+]?\d+(?:\.\d+)?f", gunfire_match.group(1))
    if len(floats) < 6:
        raise ValueError("PP7 GunfireRecord coordinates incomplete")
    gunfire = [round(float(value[:-1]) * 65536.0) for value in floats[:6]]

    payload = {
        "magic": "GEGB",
        "version": 6,
        "route": "gunbarrel",
        "runtime_rom_access": False,
        "source": {
            "animation_data": {"path": "assets/animationtable_data.c", "sha256": sha256(data_bytes)},
            "animation_entries": {"path": "assets/animationtable_entries.c", "sha256": sha256(entries_bytes)},
            "title": {"path": "src/game/title.c", "sha256": sha256((root / "src/game/title.c").read_bytes())},
            "model": {"path": "src/game/model.c", "sha256": sha256((root / "src/game/model.c").read_bytes())},
        },
        "models": models,
        "clips": clips,
        "blood": {
            "source_path": str(blood_path.relative_to(root)),
            "source_sha256": sha256(blood_source_bytes),
            "encoded_sha256": sha256(blood_encoded),
            "encoded_byte_count": len(blood_encoded),
            "source_width": 80,
            "source_height": 96,
            "texture_width": 96,
            "texture_height": 80,
            "encoded_bytes": list(blood_encoded),
        },
        "skeletons": skeletons,
        "attachment": {
            "body_model_handle": 8,
            "head_model_handle": 7,
            "weapon_model_handle": 9,
            "weapon_parent_switch": 3,
            "muzzle_flash_switch": 0,
            "muzzle_light_switch": 2,
            "gunfire_origin_q16": gunfire[:3],
            "gunfire_target_q16": gunfire[3:6],
            "gunfire_source_path": str(weapon_path.relative_to(root)),
            "gunfire_source_sha256": sha256(weapon_bytes),
        },
        "cadence": {
            "native_hz": 120,
            "source_hz": 60,
            "model_substeps_per_source_frame": 2,
            "animation_tick_owner": "native_tick",
            "autonomous_commit_phase": "even",
        },
    }
    canonical = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    payload["packet_sha256"] = sha256(canonical)
    return payload


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", type=pathlib.Path, default=pathlib.Path.cwd())
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    payload = prepare(args.project_root.resolve())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    args.output.write_text(encoded + "\n", encoding="utf-8")
    print(f"gunbarrel sidecar: {args.output}")
    print(f"packet_sha256={payload['packet_sha256']}")
    for clip in payload["clips"]:
        print(f"clip={clip['name']} frames={clip['frame_count']} bytes={clip['frame_count'] * clip['frame_bytes']} sha256={clip['entry_sha256']}")
    for skeleton in payload["skeletons"]:
        print(f"skeleton={skeleton['name']} joints={skeleton['joint_count']} sha256={skeleton['source_sha256']}")


if __name__ == "__main__":
    main()
