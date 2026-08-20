#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
ROM_PATH="${1:-${GOLDENEYE_US_ROM:-/Users/derek/Documents/GoldenEye 007 (USA).z64}}"
TEMP_ROOT=$(mktemp -d "${PROJECT_ROOT}/build/native/source-frontend-v6-test.XXXXXX")
trap 'rm -rf "${TEMP_ROOT}"' EXIT

python3 "${PROJECT_ROOT}/tests/source_frontend_v6/test_parser.py"
python3 "${SCRIPT_DIR}/prepare_native_source_frontend_v6.py" \
    --project-root "${PROJECT_ROOT}" \
    --rom "${ROM_PATH}" \
    --output-root "${TEMP_ROOT}"

REPORT="${TEMP_ROOT}/source-frontend-v6-report.txt"
MANIFEST="${TEMP_ROOT}/source-frontend-v6-manifest.json"
PACKET="${TEMP_ROOT}/source-frontend-v6.gefv"
test -f "${REPORT}"
test -f "${MANIFEST}"
test -f "${PACKET}"
grep -Fqx 'manifest_version=6' "${TEMP_ROOT}/source-frontend-v6-manifest.txt"
grep -Fqx 'magic=GEFV' "${TEMP_ROOT}/source-frontend-v6-manifest.txt"
grep -Fqx 'status=PASS' "${REPORT}"
grep -Fqx 'runtime_rom_access=false' "${REPORT}"
grep -Fqx 'external_rom_sha1=abe01e4aeb033b6c0836819f549c791b26cfde83' "${REPORT}"
grep -Fqx 'legal_text_strings=12' "${REPORT}"
grep -Fqx 'rareware_texture_arrays=6' "${REPORT}"
grep -Fqx 'rareware_mip_chains=4' "${REPORT}"
grep -Fqx 'walletbond_nodes=90' "${REPORT}"
grep -Fqx 'walletbond_switch_records=43' "${REPORT}"
grep -Fqx 'walletbond_display_lists=46' "${REPORT}"
grep -Fqx 'walletbond_textures=84' "${REPORT}"
grep -Fqx 'goldeneyelogo_vertex_total=438' "${REPORT}"
grep -Fqx 'nintendologo_nodes=42' "${REPORT}"
grep -Fqx 'nintendologo_display_lists=23' "${REPORT}"
grep -Fqx 'unsupported_visible_command_count=not_evaluated' "${REPORT}"
grep -Fqx 'sidecar_count=8' "${REPORT}"
grep -Fqx 'sidecar_legalpage_raw_gfx=12' "${REPORT}"
grep -Fqx 'sidecar_nintendologo_raw_gfx=69' "${REPORT}"
grep -Fqx 'sidecar_goldeneyelogo_raw_gfx=17' "${REPORT}"
grep -Fqx 'sidecar_walletbond_raw_gfx=0' "${REPORT}"
grep -Fqx 'count_texture_payload=127' "${TEMP_ROOT}/source-frontend-v6-manifest.txt"
grep -Fqx 'count_mip_payload=209' "${TEMP_ROOT}/source-frontend-v6-manifest.txt"
grep -Fqx 'count_tlut_payload=26' "${TEMP_ROOT}/source-frontend-v6-manifest.txt"

for sidecar in chrwppk goldeneyelogo headbrosnansuit legalpage nintendologo rarewarelogo suitbond walletbond; do
    test -f "${TEMP_ROOT}/${sidecar}.gesm"
    python3 "${SCRIPT_DIR}/prepare_native_source_frontend_v6.py" --verify-sidecar "${TEMP_ROOT}/${sidecar}.gesm"
done

python3 "${SCRIPT_DIR}/prepare_native_source_frontend_v6.py" --verify "${PACKET}"

python3 - "${MANIFEST}" "${PACKET}" "${TEMP_ROOT}/source-frontend-v6-tampered.gefv" "${TEMP_ROOT}" <<'PY'
import json
import pathlib
import re
import struct
import sys

manifest = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
packet = pathlib.Path(sys.argv[2])
tampered = pathlib.Path(sys.argv[3])
packet_bytes = packet.read_bytes()
packet_header = struct.Struct("<4sIIIIII32s32sI")
_, _, _, manifest_bytes, _, _, _, _, _, _ = packet_header.unpack_from(packet_bytes)
payload_base = packet_header.size + manifest_bytes
counts = manifest["counts"]
for key in ("model", "node", "display_list", "texture", "mip", "tlut", "image_stream", "font", "blood", "sequence", "bank"):
    if counts.get(key, 0) <= 0:
        raise SystemExit(f"missing required source category: {key}")
expected = {
    "legalpage": (3, 1, 58, 24, 5, 5, 0),
    "nintendologo": (42, 23, 821, 1363, 1, 1, 0),
    "goldeneyelogo": (3, 1, 162, 438, 2, 7, 0),
    "walletbond": (90, 46, 982, 765, 84, 186, 2),
    "headbrosnansuit": (4, 2, 119, 290, 5, 10, 5),
    "suitbond": (79, 25, 554, 726, 14, 69, 14),
    "chrwppk": (4, 2, 35, 50, 5, 18, 4),
    "rarewarelogo": (0, 9, 389, 397, 6, 26, 0),
}
expected_raw_gfx = {
    "legalpage": 12,
    "nintendologo": 69,
    "goldeneyelogo": 17,
    "walletbond": 0,
    "headbrosnansuit": 0,
    "suitbond": 0,
    "chrwppk": 0,
    "rarewarelogo": 0,
}
numeric_words = {
    "legalpage": (
        b"gsSPSetOtherMode(G_SETOTHERMODE_H,20,2,0x00000000)",
        b"gsSPSetOtherMode(G_SETOTHERMODE_L,3,29,0x00502048)",
        b"gsDPSetCombine(0xFFFFFF,0xFFFE793C)",
        b"gsDPSetCombine(0x121824,0xFF33FFFF)",
        b"gsDPSetCombine(0x127E24,0xFFFFF9FC)",
    ),
    "nintendologo": (
        b"gsSPSetOtherMode(G_SETOTHERMODE_H,20,2,0x00000000)",
        b"gsSPSetOtherMode(G_SETOTHERMODE_L,3,29,0x00502048)",
        b"gsDPSetCombine(0x127E24,0xFFFFF9FC)",
    ),
    "goldeneyelogo": (
        b"gsSPSetOtherMode(G_SETOTHERMODE_H,20,2,0x00100000)",
        b"gsSPSetOtherMode(G_SETOTHERMODE_L,3,29,0x0C182048)",
        b"gsDPSetCombine(0x26A004,0x1F1093FF)",
    ),
    "walletbond": (
        b"gsSPSetOtherMode(G_SETOTHERMODE_H,20,2,0x00100000)",
        b"gsSPSetOtherMode(G_SETOTHERMODE_L,3,29,0x0C182048)",
        b"gsSPSetOtherMode(G_SETOTHERMODE_L,3,29,0x0C184340)",
        b"gsSPSetOtherMode(G_SETOTHERMODE_H,20,2,0x00000000)",
        b"gsSPSetOtherMode(G_SETOTHERMODE_L,3,29,0x00502048)",
        b"gsDPSetCombine(0x26A004,0x1FFC93FC)",
        b"gsDPSetCombine(0x26A004,0x1F1093FF)",
        b"gsDPSetCombine(0x127E24,0xFFFFF9FC)",
        b"gsDPSetCombine(0xFFFFFF,0xFFFE793C)",
    ),
}
for sidecar in manifest["sidecars"]:
    name = sidecar["name"]
    if name not in expected:
        raise SystemExit(f"unexpected sidecar {name}")
    actual = tuple(sidecar[key] for key in ("nodes", "display_lists", "commands", "vertices", "textures", "mips", "tluts"))
    if actual != expected[name] or sidecar["unsupported_macros"]:
        raise SystemExit(f"{name}: sidecar metadata mismatch {actual}")
    for kind, audit in sidecar.get("handle_audit", {}).items():
        if audit["declared"] != audit["referenced"] or audit["unused"] != 0:
            raise SystemExit(f"{name}: {kind} handle audit is not fully joinable")
    sidecar_bytes = pathlib.Path(sys.argv[4], f"{name}.gesm").read_bytes()
    if b"&ModelNode" in sidecar_bytes:
        raise SystemExit(f"{name}: raw pointer leaked into sidecar")
    # C pointer syntax must never be retained in the fixed-width sidecar
    # string table.  Typed @address/@display_list/etc. markers are the
    # bounded, address-free representation and remain intentionally allowed.
    if re.search(rb"\(void\s*\*|\buintptr_t\b|&(?:ModelNode|DisplayList|Vertex_|verts)", sidecar_bytes):
        raise SystemExit(f"{name}: C pointer text leaked into sidecar")
    if name == "legalpage" and b"gsSPSetOtherMode(G_SETOTHERMODE_L,3,29,0x00502048)" not in sidecar_bytes:
        raise SystemExit("legalpage: numeric othermode literal was not preserved")
    if name == "legalpage" and b"@address:" not in sidecar_bytes:
        raise SystemExit("legalpage: gsSPMatrix address was not normalized to a handle")
    for literal in numeric_words.get(name, ()):
        if literal not in sidecar_bytes:
            raise SystemExit(f"{name}: source numeric render word was not preserved: {literal!r}")
    header = struct.Struct("<4s" + "I" * 15 + "32s32sI")
    node_size, scalar_size, display_size = 48, 64, 32
    command_size, token_size, vertex_size = 48, 28, 64
    texture_size, mip_size = 64, 48
    fields = header.unpack_from(sidecar_bytes)
    _, _, _, _, _, _, nodes, scalars, displays, commands, tokens, vertices, textures, mips, tluts, string_bytes, *_ = fields
    command_offset = header.size + nodes * node_size + scalars * scalar_size + displays * display_size
    token_offset = command_offset + commands * command_size
    string_offset = token_offset + tokens * token_size + vertices * vertex_size + textures * texture_size + mips * mip_size + tluts * 32
    command_record = struct.Struct("<12I")
    token_record = struct.Struct("<IIIIIQ")
    raw_count = 0
    for command_index in range(commands):
        command_values = command_record.unpack_from(sidecar_bytes, command_offset + command_index * command_size)
        semantic_offset, semantic_size = command_values[5], command_values[6]
        semantic = sidecar_bytes[string_offset + semantic_offset : string_offset + semantic_offset + semantic_size]
        if not semantic.startswith(b"rawGfx("):
            continue
        raw_count += 1
        if command_values[4] != 2:
            raise SystemExit(f"{name}: rawGfx command does not carry exactly two words")
        for token_index in range(command_values[3], command_values[3] + command_values[4]):
            encoded = token_record.unpack_from(sidecar_bytes, token_offset + token_index * token_size)[1]
            if token_index == command_values[3] and (encoded >> 24) not in (0xF2, 0xF5):
                raise SystemExit(f"{name}: rawGfx w0 is not a guarded F2/F5 word: {encoded:#010x}")
    if raw_count != expected_raw_gfx[name]:
        raise SystemExit(f"{name}: rawGfx count changed: {raw_count} != {expected_raw_gfx[name]}")
    texture_offset = header.size + nodes * node_size + scalars * scalar_size + displays * display_size + commands * command_size + tokens * token_size + vertices * vertex_size
    mip_offset = texture_offset + textures * texture_size
    texture_record = struct.Struct("<16I")
    mip_record = struct.Struct("<12I")
    for index in range(textures):
        values = texture_record.unpack_from(sidecar_bytes, texture_offset + index * texture_size)
        payload = manifest["records"][values[9] - 1]
        if payload["category"] != "texture_payload":
            raise SystemExit(f"{name}: texture payload points to {payload['category']}")
        if payload["raw_size"] <= 0 or payload["decoded_size"] <= 0 or payload["decoded_size"] % 4:
            raise SystemExit(f"{name}: invalid texture payload byte counts")
        if values[14] == 0:
            raise SystemExit(f"{name}: texture source-row handle is missing")
    for index in range(mips):
        values = mip_record.unpack_from(sidecar_bytes, mip_offset + index * mip_size)
        payload = manifest["records"][values[5] - 1]
        if payload["category"] not in ("mip_payload", "texture_payload"):
            raise SystemExit(f"{name}: mip payload points to {payload['category']}")
        if payload["raw_size"] <= 0 or payload["decoded_size"] <= 0 or payload["decoded_size"] % 4:
            raise SystemExit(f"{name}: invalid mip payload byte counts")
        if values[8] == 0:
            raise SystemExit(f"{name}: mip source-row handle is missing")
    tlut_offset = mip_offset + mips * mip_size
    tlut_record = struct.Struct("<8I")
    for index in range(tluts):
        values = tlut_record.unpack_from(sidecar_bytes, tlut_offset + index * 32)
        payload = manifest["records"][values[2] - 1]
        if payload["category"] != "tlut_payload":
            raise SystemExit(f"{name}: TLUT payload points to {payload['category']}")
        if payload["raw_size"] <= 0 or payload["decoded_size"] != (payload["raw_size"] // 2) * 4:
            raise SystemExit(f"{name}: invalid TLUT byte counts")
        if values[5] == 0:
            raise SystemExit(f"{name}: TLUT source-row handle is missing")
    for payload in manifest["records"]:
        if payload["category"] in ("texture_payload", "mip_payload", "tlut_payload") and payload["raw_size"]:
            # The exact byte payload is in the GEFV packet, but the record's
            # source hash and decoded size must not describe Model.c text.
            if payload["raw_size"] >= 8 and payload["raw_sha256"] == payload["source_sha256"] and payload["source_path"].endswith("Model.c"):
                raise SystemExit(f"{name}: texture payload still aliases Model.c text")
            raw_start = payload_base + payload["raw_payload_offset"]
            raw_bytes = packet_bytes[raw_start : raw_start + payload["raw_size"]]
            if raw_bytes.startswith((b"#include", b"ModelNode", b"#define", b"Gfx ")):
                raise SystemExit(f"{name}: texture payload begins with source text")
    if name in {"walletbond", "suitbond", "headbrosnansuit", "chrwppk"}:
        for index in range(textures):
            values = texture_record.unpack_from(sidecar_bytes, texture_offset + index * texture_size)
            if manifest["records"][values[9] - 1]["category"] == "image_stream":
                raise SystemExit(f"{name}: strict texture payload still references image_stream")
    node_records = [struct.unpack_from("<12I", sidecar_bytes, header.size + index * node_size) for index in range(nodes)]
    owned_display_ids = {values[9] for values in node_records if values[9] != 0xFFFFFFFF} | {values[10] for values in node_records if values[10] != 0xFFFFFFFF}
    if name in {"legalpage", "goldeneyelogo"} and owned_display_ids != {0}:
        raise SystemExit(f"{name}: one-list ownership mismatch")
    if name == "nintendologo" and owned_display_ids != set(range(23)):
        raise SystemExit("nintendologo: traversal does not own all 23 display lists")
    if name == "walletbond" and not owned_display_ids.issubset(set(range(46))):
        raise SystemExit("walletbond: display-list ownership escaped declared range")
    scalar_records = [struct.unpack_from("<IIIII9IQ", sidecar_bytes, header.size + nodes * node_size + index * scalar_size) for index in range(scalars)]
    switch_kind = 2166136261
    for byte in b"ModelRoData_SwitchRecord":
        switch_kind = ((switch_kind ^ byte) * 16777619) & 0xFFFFFFFF
    if name == "walletbond":
        switch_scalars = [record for record in scalar_records if record[1] == switch_kind]
        if len(switch_scalars) != 42 or any(record[6] != 1 for record in switch_scalars):
            raise SystemExit("walletbond: switch selection metadata is incomplete")
for array_name in ("D_02004FE8", "D_02005FF0"):
    payload = next(record for record in manifest["records"] if record["category"] == "texture_payload" and record["name"] == f"{array_name}.payload")
    if payload["raw_size"] != 2048 or payload["metadata"]["width"] != 32 or payload["metadata"]["height"] != 32:
        raise SystemExit(f"{array_name}: RGBA16 32x32 payload dimensions/bytes mismatch")
tail = next(record for record in manifest["records"] if record["category"] == "rareware_array_tail" and record["name"] == "D_02004FE8.tail")
if tail["raw_size"] != 2048:
    raise SystemExit("D_02004FE8 source tail was not preserved")
for image_name in ("COPYICON", "DELICON", "SELECTFILE", "CROSSHAIR1", "CHECK", "DOT", "X"):
    payload = next(record for record in manifest["records"] if record["category"] == "texture_payload" and record["name"] == f"{image_name}.payload")
    decoded_start = payload_base + payload["decoded_payload_offset"]
    decoded = packet_bytes[decoded_start : decoded_start + payload["decoded_size"]]
    if not decoded or not any(decoded):
        raise SystemExit(f"{image_name}: visible frontend payload is empty or all zero")
select_payload = next(record for record in manifest["records"] if record["category"] == "texture_payload" and record["name"] == "SELECTFILE.payload")
if select_payload["id"] != 1480 or select_payload["decoded_sha256"] != "a594b1636af95b3d563d2524fd26f52a4ce95e4030c6262c5b873e23232dcce8":
    raise SystemExit("SELECTFILE payload hash/record identity changed unexpectedly")
if "SOURCE_ORDER_RGBA8" not in select_payload["flags"] or select_payload["metadata"].get("source_order") != "source":
    raise SystemExit("SELECTFILE source-order payload contract is missing")
folder_mips = [record for record in manifest["records"] if record["category"] == "mip_payload" and record["name"].startswith("FOLDERTEX.mip.")]
if len(folder_mips) != 6 or any("SOURCE_GENERATED_MIP" not in record["flags"] for record in folder_mips):
    raise SystemExit("FOLDERTEX source-generated mip contract is incomplete")
mi6_mips = [record for record in manifest["records"] if record["category"] == "mip_payload" and record["name"].startswith("MI6_UL.mip.")]
if len(mi6_mips) != 6 or any("SOURCE_AUTHORED_MIP" not in record["flags"] for record in mi6_mips):
    raise SystemExit("MI6_UL authored mip contract is incomplete")
data = bytearray(packet.read_bytes())
data[-1] ^= 0x01
tampered.write_bytes(data)
PY
if python3 "${SCRIPT_DIR}/prepare_native_source_frontend_v6.py" --verify "${TEMP_ROOT}/source-frontend-v6-tampered.gefv"; then
    echo "tampered GEFV packet unexpectedly verified" >&2
    exit 1
fi

python3 - "${TEMP_ROOT}/legalpage.gesm" "${TEMP_ROOT}/legalpage-tampered.gesm" "${TEMP_ROOT}/legalpage-truncated.gesm" <<'PY'
import pathlib
import sys

data = pathlib.Path(sys.argv[1]).read_bytes()
tampered = bytearray(data)
tampered[-1] ^= 0x01
pathlib.Path(sys.argv[2]).write_bytes(tampered)
pathlib.Path(sys.argv[3]).write_bytes(data[:-1])
PY
if python3 "${SCRIPT_DIR}/prepare_native_source_frontend_v6.py" --verify-sidecar "${TEMP_ROOT}/legalpage-tampered.gesm"; then
    echo "tampered GESM sidecar unexpectedly verified" >&2
    exit 1
fi
if python3 "${SCRIPT_DIR}/prepare_native_source_frontend_v6.py" --verify-sidecar "${TEMP_ROOT}/legalpage-truncated.gesm"; then
    echo "truncated GESM sidecar unexpectedly verified" >&2
    exit 1
fi

if find "${TEMP_ROOT}" -type f \( -name '*.z64' -o -name '*.n64' -o -name '*.app' \) -print -quit | grep -q .; then
    echo "ROM-like or application-bundle output found under source frontend V6 output" >&2
    exit 1
fi

echo "Native source frontend V6 lossless catalog and tamper validation: PASS"
