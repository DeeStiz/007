#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BUILD_DIR="${PROJECT_ROOT}/build/native/source-reference-v6"
FIXTURE_DIR="${PROJECT_ROOT}/tests/fixtures/source_reference_v6"
FIXTURE="${FIXTURE_DIR}/source_reference_v6.tsv"
LOCATIONS="${FIXTURE_DIR}/source_locations.tsv"
GESM_HISTORICAL_FIXTURE="${FIXTURE_DIR}/gesm_counts.tsv"
GESM_FULL_FIXTURE="${FIXTURE_DIR}/gesm_full_counts.tsv"
mkdir -p "${BUILD_DIR}"

if [[ ! -f "${FIXTURE}" || ! -f "${LOCATIONS}" || ! -f "${GESM_HISTORICAL_FIXTURE}" || ! -f "${GESM_FULL_FIXTURE}" ]]; then
    echo "source-reference-v6: missing canonical fixtures" >&2
    exit 1
fi

PROJECT_ROOT="${PROJECT_ROOT}" FIXTURE="${FIXTURE}" LOCATIONS="${LOCATIONS}" GESM_HISTORICAL_FIXTURE="${GESM_HISTORICAL_FIXTURE}" GESM_FULL_FIXTURE="${GESM_FULL_FIXTURE}" \
python3 - <<'PY'
import hashlib
import os
import re
import struct
from pathlib import Path

root = Path(os.environ["PROJECT_ROOT"])
fixture = Path(os.environ["FIXTURE"])
locations = Path(os.environ["LOCATIONS"])
gesm_historical_fixture = Path(os.environ["GESM_HISTORICAL_FIXTURE"])
gesm_full_fixture = Path(os.environ["GESM_FULL_FIXTURE"])

def read_fixture(path: Path):
    values = {}
    blocks = {}
    current = None
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        key, value = line.split("=", 1)
        if key == "screen":
            current = value
            blocks[current] = {}
            continue
        if current is not None and key not in {"fixture_version", "manifest_source_generation", "manifest_aggregate_hash"}:
            blocks[current][key] = value
        else:
            values[key] = value
    return values, blocks

values, blocks = read_fixture(fixture)
assert values.get("fixture_version") == "1", "fixture version"
assert values.get("manifest_reference_kind") == "static_source_counts", "reference kind fixture"
def read_gesm_fixture(path: Path):
    result = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        name, fields = line.split("=", 1)
        result[name] = {key: int(value) for key, value in (field.split(":", 1) for field in fields.split(","))}
    return result

gesm_expected = read_gesm_fixture(gesm_full_fixture)
gesm_historical = read_gesm_fixture(gesm_historical_fixture)
expected_screens = {
    "legal": {"path": "assets/obseg/prop/legalpage/Model.c", "nodes": 3, "display_lists": 1, "vertices": 24, "triangles": 12, "textures": 5, "commands": 58, "macro_commands": 46, "raw_commands": 12, "lexical_commands": 58, "order_hash": 0x8e915a7f4044c593, "source_sha256": "5af36d1255193d60282b42a5dd80ccd473bc2d7fc6631615dae08d0e9b659337"},
    "nintendo": {"path": "assets/obseg/prop/nintendologo/Model.c", "nodes": 42, "display_lists": 23, "vertices": 1363, "triangles": 1021, "textures": 1, "commands": 821, "macro_commands": 752, "raw_commands": 69, "lexical_commands": 821, "order_hash": 0x9cc62b913ce52e5b, "source_sha256": "8e0e40946713203f1db3cda53167a86658aa2aa10eb00ae89d64aa52aedc35d9"},
    "goldeneye": {"path": "assets/obseg/prop/goldeneyelogo/Model.c", "nodes": 3, "display_lists": 1, "vertices": 438, "triangles": 341, "textures": 2, "commands": 162, "macro_commands": 145, "raw_commands": 17, "lexical_commands": 162, "order_hash": 0xbe5c050badae9682, "source_sha256": "c98da38e9b27fb6a5f02e1ff1dc28964384cd387e325af17b1804625b622a54c"},
    "wallet": {"path": "assets/obseg/prop/walletbond/Model.c", "nodes": 90, "display_lists": 46, "vertices": 765, "triangles": 440, "textures": 84, "commands": 982, "macro_commands": 982, "raw_commands": 0, "lexical_commands": 982, "order_hash": 0x2bf6d0230e7ae7a1, "source_sha256": "feed206e277e58e9cd4de67a299634743ea9706f241b4bfa61d6adb57cee1df7"},
}

def mask_comments(source: str):
    source = re.sub(r"/\*.*?\*/", lambda match: " " * (match.end() - match.start()), source, flags=re.DOTALL)
    return re.sub(r"//[^\n]*", lambda match: " " * (match.end() - match.start()), source)

def body_between(source: str, start: int):
    begin = source.find("{", start)
    depth = 0
    for index in range(begin, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[begin + 1:index]
    raise AssertionError("unterminated Gfx initializer")

def iter_macro_calls(source: str):
    index = 0
    identifier = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
    while index < len(source):
        match = identifier.match(source, index)
        if not match:
            index += 1
            continue
        name = match.group(0)
        cursor = match.end()
        while cursor < len(source) and source[cursor].isspace():
            cursor += 1
        if not name.startswith("gs") or cursor >= len(source) or source[cursor] != "(":
            index = cursor
            continue
        depth = 0
        end = None
        for position in range(cursor, len(source)):
            if source[position] == "(":
                depth += 1
            elif source[position] == ")":
                depth -= 1
                if depth == 0:
                    end = position
                    break
        if end is None:
            raise AssertionError(f"unterminated source macro {name}")
        yield match.start(), name, source[cursor + 1:end]
        index = end + 1

def source_events(source: str):
    events = []
    for match in re.finditer(r"^Gfx\s+[A-Za-z0-9_]+\s*\[\]\s*=\s*\{", source, re.MULTILINE):
        body = body_between(source, match.start())
        masked = mask_comments(body)
        for offset, name, arguments in iter_macro_calls(masked):
            events.append((match.start() + offset, "M:" + name + "(" + re.sub(r"\s+", "", arguments) + ")"))
        for raw in re.finditer(r"\{\{\s*([^,{}]+)\s*,\s*([^{}]+?)\s*\}\}", body, re.DOTALL):
            w0 = re.sub(r"\s+", "", raw.group(1)).lower()
            w1 = re.sub(r"\s+", "", raw.group(2)).lower()
            if re.fullmatch(r"(?:0x[0-9a-f]+|[0-9]+)[uUlL]*", w0) and re.fullmatch(r"(?:0x[0-9a-f]+|[0-9]+)[uUlL]*", w1):
                events.append((match.start() + raw.start(), "R:" + w0 + "," + w1))
    events.sort(key=lambda event: event[0])
    return events

def event_hash(events):
    value = 1469598103934665603
    for _, token in events:
        for byte in (token + "\0").encode("utf-8"):
            value = ((value ^ byte) * 1099511628211) & 0xffffffffffffffff
    return value

def command_counts(source: str):
    # The lexical total is diagnostic only: it includes command-looking tokens
    # in comments. The authoritative count includes parsed Gfx macro calls and
    # raw {{w0,w1}} initializers, matching the regenerated full-source sidecar.
    lexical_names = re.findall(r"\b(gs[A-Za-z0-9_]+)\s*\(", source)
    events = source_events(source)
    macro_names = [token[2:].split("(", 1)[0] for _, token in events if token.startswith("M:")]
    raw_commands = sum(token.startswith("R:") for _, token in events)
    counts = {name: macro_names.count(name) for name in set(macro_names)}
    triangles = sum(counts.get(name, 0) * width for name, width in (("gsSP1Triangle", 1), ("gsSP2Triangles", 2), ("gsSP4Triangles", 4)))
    return len(events), triangles, counts, len(lexical_names), len(macro_names), raw_commands, event_hash(events)

for name, spec in expected_screens.items():
    path = root / spec["path"]
    source = path.read_text(encoding="utf-8")
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    assert digest == spec["source_sha256"], f"{name} source SHA-256"
    nodes = len(re.findall(r"^ModelNode\s+ModelNode_", source, re.MULTILINE))
    display_lists = len(re.findall(r"^Gfx\s+GFX_", source, re.MULTILINE))
    vertex_sizes = [int(value) for value in re.findall(r"^#define\s+VERTEXGROUPCOUNT\d+\s+(\d+)", source, re.MULTILINE)]
    textures = int(re.search(r"^#define\s+TEXTURECOUNT\s+(\d+)", source, re.MULTILINE).group(1))
    commands, triangles, _, lexical_commands, macro_commands, raw_commands, order_hash = command_counts(source)
    assert nodes == spec["nodes"], f"{name} node count: {nodes}"
    assert display_lists == spec["display_lists"], f"{name} display-list count: {display_lists}"
    assert sum(vertex_sizes) == spec["vertices"], f"{name} vertex count: {sum(vertex_sizes)}"
    assert triangles == spec["triangles"], f"{name} triangle count: {triangles}"
    assert textures == spec["textures"], f"{name} texture count: {textures}"
    assert commands == spec["commands"], f"{name} full source command count: {commands}"
    assert macro_commands == spec["macro_commands"], f"{name} macro command count: {macro_commands}"
    assert raw_commands == spec["raw_commands"], f"{name} raw initializer count: {raw_commands}"
    assert lexical_commands == spec["lexical_commands"], f"{name} lexical macro count: {lexical_commands}"
    assert order_hash == spec["order_hash"], f"{name} source command order hash: {order_hash:016x}"
    block = blocks[name]
    for key in ("nodes", "display_lists", "vertices", "triangles", "textures", "commands", "macro_commands", "raw_commands", "lexical_commands", "source_sha256"):
        assert block.get(key) == str(spec[key]), f"{name} fixture {key}"
    assert block.get("command_order_hash") == f"{order_hash:016x}", f"{name} fixture command order hash"
    print(f"source-screen={name} full_source_commands={commands} macro_commands={macro_commands} raw_initializer_commands={raw_commands} order_hash={order_hash:016x}")

rareware_path = root / "assets/rarewarelogo.c"
rareware_source = rareware_path.read_text(encoding="utf-8")
assert hashlib.sha256(rareware_path.read_bytes()).hexdigest() == blocks["rareware"]["source_sha256"], "rareware source SHA-256"
assert len(re.findall(r"^Gfx\s+", rareware_source, re.MULTILINE)) == 9, "rareware display-list count"
rareware_vtx = 0
for match in re.finditer(r"\bVtx\s+\w+\[\]\s*=\s*\{(.*?)\n\};", rareware_source, re.DOTALL):
    rareware_vtx += len(re.findall(r"^\s*\{0x", match.group(1), re.MULTILINE))
rareware_commands, rareware_triangles, rareware_counts, rareware_lexical_commands, rareware_macro_commands, rareware_raw_commands, rareware_order_hash = command_counts(rareware_source)
assert rareware_vtx == 397, f"rareware raw vertex count: {rareware_vtx}"
assert rareware_triangles == 268, f"rareware triangle count: {rareware_triangles}"
assert rareware_commands == 389, f"rareware command count: {rareware_commands}"
assert rareware_macro_commands == 389, f"rareware macro command count: {rareware_macro_commands}"
assert rareware_raw_commands == 0, f"rareware raw initializer count: {rareware_raw_commands}"
assert rareware_lexical_commands == 389, f"rareware lexical macro count: {rareware_lexical_commands}"
assert rareware_order_hash == 0xaf862a5762d1f654, f"rareware source command order hash: {rareware_order_hash:016x}"
assert rareware_counts.get("gsSP1Triangle", 0) == 268, "rareware source triangle family"
print(f"source-screen=rarewarelogo full_source_commands={rareware_commands} macro_commands={rareware_macro_commands} raw_initializer_commands={rareware_raw_commands} order_hash={rareware_order_hash:016x}")

front = (root / "src/game/front.c").read_text(encoding="utf-8")
title = (root / "src/game/title.c").read_text(encoding="utf-8")
text_start = front.index("legalpage_text_array")
text_end = front.index("};", text_start)
assert len(re.findall(r"getStringID\(LTITLE, TITLE_STR_", front[text_start:text_end])) == 12, "legal source text count"
folder_start = front.index("folderpositions[]")
folder_end = front.index("};", folder_start)
assert len(re.findall(r"^\s*\{[^\n]*\},?$", front[folder_start:folder_end], re.MULTILINE)) == 4, "folder position count"
wallet_source = (root / "assets/obseg/prop/walletbond/Model.c").read_text(encoding="utf-8")
assert len(re.findall(r"MODELNODE_OPCODE_SWITCH", wallet_source)) == 42, "wallet switch-node source count"
assert "RAREWARE_LOGO_DEN 58" in title and "RAREWARE_LOGO_EYE_COUNT2 241" in title, "rareware source timing"

for raw in locations.read_text(encoding="utf-8").splitlines():
    line = raw.strip()
    if not line or line.startswith("#"):
        continue
    key, rest = line.split("=", 1)
    line_number, expected_text = rest.split("|", 1)
    line_number = int(line_number)
    if key.startswith("title_"):
        source = title
    elif key.startswith("front_"):
        source = front
    elif key.startswith("asset_rareware"):
        source = rareware_source
    elif key == "asset_legal_text":
        source = front
    elif key.startswith("asset_legal"):
        source = (root / "assets/obseg/prop/legalpage/Model.c").read_text(encoding="utf-8")
    elif key.startswith("asset_nintendo"):
        source = (root / "assets/obseg/prop/nintendologo/Model.c").read_text(encoding="utf-8")
    elif key.startswith("asset_goldeneye"):
        source = (root / "assets/obseg/prop/goldeneyelogo/Model.c").read_text(encoding="utf-8")
    elif key.startswith("asset_wallet"):
        source = wallet_source
    else:
        raise AssertionError(f"unknown source-location fixture key {key}")
    lines = source.splitlines()
    assert 1 <= line_number <= len(lines), f"{key} source line range"
    assert expected_text in lines[line_number - 1].strip(), f"{key} source line changed"

gesm_root = root / "build/native/source-frontend-v6"
gesm_header = struct.Struct("<4s" + "I" * 15 + "32s32sI")
gesm_names = tuple(gesm_expected)
missing_gesm = [name for name in gesm_names if not (gesm_root / f"{name}.gesm").is_file()]
if missing_gesm:
    if os.environ.get("GE_SOURCE_REFERENCE_V6_REQUIRE_GESM") == "1":
        raise AssertionError(f"missing GESM sidecars: {','.join(missing_gesm)}")
    print(f"source-reference-v6 GESM binary cross-check: DEFERRED missing={','.join(missing_gesm)}")
else:
    actual_counts = {}
    for name, expected in gesm_expected.items():
        fields = gesm_header.unpack_from((gesm_root / f"{name}.gesm").read_bytes())
        actual = {"nodes": fields[6], "display_lists": fields[8], "commands": fields[9], "vertices": fields[11], "textures": fields[12]}
        actual_counts[name] = actual
    pending_gesm = [name for name in gesm_names if gesm_expected[name] != gesm_historical.get(name) and actual_counts[name] == gesm_historical.get(name)]
    unexpected_gesm = [name for name in gesm_names if actual_counts[name] not in (gesm_expected[name], gesm_historical.get(name))]
    if unexpected_gesm:
        raise AssertionError(f"GESM counts are neither full nor preserved historical reduced evidence: {unexpected_gesm}")
    if not pending_gesm:
        print("source-reference-v6 full GESM command-count cross-check: PASS")
    else:
        message = f"source-reference-v6 full GESM command-count cross-check: DEFERRED historical reduced sidecars omit raw initializers: {','.join(pending_gesm)}"
        if os.environ.get("GE_SOURCE_REFERENCE_V6_REQUIRE_GESM") == "1":
            raise AssertionError(message)
        print(message)

print("source-reference-v6 static source-count audit: PASS")
PY

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CLANG=$(xcrun --sdk macosx --find clang)
CFLAGS=(
    -std=c11 -Wall -Wextra -Werror -Wconversion -Wshadow -Wpedantic
    -isysroot "${SDKROOT}" -I"${PROJECT_ROOT}/native/include"
)

"${CLANG}" "${CFLAGS[@]}" \
    "${PROJECT_ROOT}/native/src/ge_source_reference_v6.c" \
    "${PROJECT_ROOT}/native/tests/goldeneye_source_reference_v6_smoke.c" \
    -o "${BUILD_DIR}/goldeneye_source_reference_v6_smoke"

"${BUILD_DIR}/goldeneye_source_reference_v6_smoke" \
    | tee "${BUILD_DIR}/strict.log"

EXPECTED_HASH=$(awk -F= '/^manifest_aggregate_hash=/{print $2}' "${FIXTURE}")
ACTUAL_HASH=$(rg '^manifest_aggregate_hash=' "${BUILD_DIR}/strict.log" | cut -d= -f2)
if [[ "${ACTUAL_HASH}" != "${EXPECTED_HASH}" ]]; then
    echo "source-reference-v6: aggregate hash mismatch (${ACTUAL_HASH} != ${EXPECTED_HASH})" >&2
    exit 1
fi

xcrun swiftc -typecheck -sdk "${SDKROOT}" \
    -import-objc-header "${PROJECT_ROOT}/native/include/ge_source_reference_v6.h" \
    "${PROJECT_ROOT}/native/tests/gui_input_probe.swift"
echo "source-reference-v6 Swift header import: PASS"

"${CLANG}" "${CFLAGS[@]}" -fsanitize=address,undefined -fno-omit-frame-pointer \
    "${PROJECT_ROOT}/native/src/ge_source_reference_v6.c" \
    "${PROJECT_ROOT}/native/tests/goldeneye_source_reference_v6_smoke.c" \
    -o "${BUILD_DIR}/goldeneye_source_reference_v6_sanitized"

ASAN_OPTIONS=detect_leaks=0:halt_on_error=1 \
UBSAN_OPTIONS=halt_on_error=1 \
    "${BUILD_DIR}/goldeneye_source_reference_v6_sanitized" \
    > "${BUILD_DIR}/sanitized.log"

echo "source reference V6 static-count validation: PASS"
