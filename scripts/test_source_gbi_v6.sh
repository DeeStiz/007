#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
BUILD_DIR="${PROJECT_ROOT}/build/native/source-gbi-v6"
mkdir -p "${BUILD_DIR}"

if command -v xcrun >/dev/null 2>&1; then
    CC=$(xcrun --sdk macosx --find clang)
    SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
else
    CC=${CC:-clang}
    SDKROOT=${SDKROOT:-}
fi

COMMON_CFLAGS=(-std=c11 -Wall -Wextra -Werror -O2
    -I "${PROJECT_ROOT}/native/include")
if [[ -n "${SDKROOT}" ]]; then
    COMMON_CFLAGS+=(-target arm64-apple-macosx27.0 -isysroot "${SDKROOT}")
fi

SMOKE="${BUILD_DIR}/goldeneye_source_gbi_v6_smoke"
SANITIZED="${BUILD_DIR}/goldeneye_source_gbi_v6_smoke_sanitized"

echo "Auditing checked-in source model listings against V6 capacities"
PROJECT_ROOT="${PROJECT_ROOT}" python3 - <<'PY'
import os
import re
from pathlib import Path

root = Path(os.environ["PROJECT_ROOT"])
header = (root / "native/include/ge_source_gbi_v6.h").read_text(encoding="utf-8")

def capacity(name: str) -> int:
    match = re.search(
        rf"#define\s+{re.escape(name)}\s+\(\(uint32_t\)(\d+)u\)",
        header,
    )
    assert match, f"missing {name}"
    return int(match.group(1))

capacities = {
    "commands": capacity("GE_SOURCE_GBI_V6_MAX_COMMANDS"),
    "vertices": capacity("GE_SOURCE_GBI_V6_MAX_VERTICES"),
    "draws": capacity("GE_SOURCE_GBI_V6_MAX_DRAWS"),
    "events": capacity("GE_SOURCE_GBI_V6_MAX_EVENTS"),
}
assert capacities["commands"] >= 2048, capacities
assert capacities["vertices"] >= 2048, capacities
assert capacities["draws"] >= 2048, capacities
assert capacities["events"] >= 4096, capacities

models = {
    "legal": ("assets/obseg/prop/legalpage/Model.c", 3, 1, 24, 12, 58),
    "nintendo": ("assets/obseg/prop/nintendologo/Model.c", 42, 23, 1363, 1021, 821),
    "goldeneye": ("assets/obseg/prop/goldeneyelogo/Model.c", 3, 1, 438, 341, 162),
    "wallet": ("assets/obseg/prop/walletbond/Model.c", 90, 46, 765, 440, 982),
    "headbrosnansuit": ("assets/obseg/chr/headbrosnansuit/Model.c", 4, 2, 290, 227, 119),
    "suit": ("assets/obseg/chr/suitbond/Model.c", 79, 25, 726, 627, 554),
    "chrwppk": ("assets/obseg/prop/chrwppk/Model.c", 4, 2, 50, 34, 35),
    "rareware": ("assets/rarewarelogo.c", 0, 9, 397, 268, 389),
}

def listing_counts(path: Path):
    source = path.read_text(encoding="utf-8")
    names = re.findall(r"\b(gs[A-Za-z0-9_]+)\s*\(", source)
    counts = {name: names.count(name) for name in set(names)}
    triangles = sum(
        counts.get(name, 0) * width
        for name, width in (("gsSP1Triangle", 1), ("gsSP2Triangles", 2), ("gsSP4Triangles", 4))
    )
    if path.name == "rarewarelogo.c":
        vertices = sum(
            len(re.findall(r"^\s*\{0x", body, re.MULTILINE))
            for body in re.findall(r"\bVtx\s+\w+\[\]\s*=\s*\{(.*?)\n\};", source, re.DOTALL)
        )
    else:
        vertices = sum(
            int(value)
            for value in re.findall(r"^#define\s+VERTEXGROUPCOUNT\d+\s+(\d+)", source, re.MULTILINE)
        )
    nodes = len(re.findall(r"^ModelNode\s+ModelNode_", source, re.MULTILINE))
    display_lists = (
        len(re.findall(r"^Gfx\s+", source, re.MULTILINE))
        if path.name == "rarewarelogo.c"
        else len(re.findall(r"^Gfx\s+GFX_", source, re.MULTILINE))
    )
    return nodes, display_lists, vertices, triangles, len(names)

for name, (relative, expected_nodes, expected_lists, expected_vertices,
           expected_triangles, expected_commands) in models.items():
    path = root / relative
    assert path.is_file(), relative
    actual = listing_counts(path)
    expected = (expected_nodes, expected_lists, expected_vertices,
                expected_triangles, expected_commands)
    assert actual == expected, f"{name}: expected {expected}, got {actual}"
    commands, vertices, draws = actual[4], actual[2], actual[3]
    events = commands + draws
    assert commands <= capacities["commands"], (name, "commands", commands)
    assert vertices <= capacities["vertices"], (name, "vertices", vertices)
    assert draws <= capacities["draws"], (name, "draws", draws)
    assert events <= capacities["events"], (name, "events", events)
    print(
        f"source-gbi-v6 audit: {name} nodes={actual[0]} lists={actual[1]} "
        f"vertices={vertices} triangles={draws} commands={commands} events={events} PASS"
    )

print(
    "source-gbi-v6 capacity audit: PASS "
    f"commands={capacities['commands']} vertices={capacities['vertices']} "
    f"draws={capacities['draws']} events={capacities['events']}"
)
PY

echo "Building strict source GBI V6 smoke"
"${CC}" "${COMMON_CFLAGS[@]}" \
    "${PROJECT_ROOT}/native/src/ge_source_gbi_v6.c" \
    "${PROJECT_ROOT}/native/tests/goldeneye_source_gbi_v6_smoke.c" \
    -o "${SMOKE}"

echo "Running deterministic source GBI V6 smoke"
"${SMOKE}" | tee "${BUILD_DIR}/source-gbi-v6-smoke.log"

echo "Building ASan/UBSan source GBI V6 smoke"
"${CC}" "${COMMON_CFLAGS[@]}" -O1 -fno-omit-frame-pointer \
    -fsanitize=address,undefined \
    "${PROJECT_ROOT}/native/src/ge_source_gbi_v6.c" \
    "${PROJECT_ROOT}/native/tests/goldeneye_source_gbi_v6_smoke.c" \
    -o "${SANITIZED}"

echo "Running ASan/UBSan source GBI V6 smoke"
ASAN_OPTIONS=halt_on_error=1 \
UBSAN_OPTIONS=halt_on_error=1 \
    "${SANITIZED}" | tee "${BUILD_DIR}/source-gbi-v6-sanitized.log"

if command -v swiftc >/dev/null 2>&1; then
    SWIFTC=$(command -v swiftc)
    if command -v xcrun >/dev/null 2>&1; then
        SWIFTC=$(xcrun --sdk macosx --find swiftc)
    fi
    SWIFT_ARGS=()
    if [[ -n "${SDKROOT}" ]]; then
        SWIFT_ARGS+=(-target arm64-apple-macosx27.0 -sdk "${SDKROOT}")
    fi
    echo "Importing V6 C header into Swift"
    printf '%s\n' \
        'import Foundation' \
        'let _: GEGBIResultV6.Type = GEGBIResultV6.self' \
        'let _: GEGBISourcePacketV6.Type = GEGBISourcePacketV6.self' \
        'let _: GEGBISourceVertexResourcePageV6.Type = GEGBISourceVertexResourcePageV6.self' \
        'precondition(MemoryLayout<GEGBISourceVertexResourcePageV6>.size == 1080)' \
        'precondition(MemoryLayout<GEGBIStateV6>.size == 320)' \
        'precondition(MemoryLayout<GEGBIDrawV6>.size == 64)' \
        | CLANG_MODULE_CACHE_PATH="${BUILD_DIR}/module-cache" \
          "${SWIFTC}" "${SWIFT_ARGS[@]}" \
          -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_native_bridging.h" \
          -Xcc "-I${PROJECT_ROOT}/native/include" \
          -Xcc -include -Xcc ge_source_gbi_v6.h \
          -o "${BUILD_DIR}/source-gbi-v6-swift-header-import" -
    "${BUILD_DIR}/source-gbi-v6-swift-header-import"
    echo "Source GBI V6 Swift header import: PASS"
else
    echo "Source GBI V6 Swift header import: SKIP (swiftc unavailable)"
fi

git -C "${PROJECT_ROOT}" diff --check -- \
    native/include/ge_source_gbi_v6.h \
    native/src/ge_source_gbi_v6.c \
    native/tests/goldeneye_source_gbi_v6_smoke.c \
    scripts/test_source_gbi_v6.sh

echo "Source GBI V6 validation: PASS"
echo "Artifacts: ${BUILD_DIR}/source-gbi-v6-smoke.log ${BUILD_DIR}/source-gbi-v6-sanitized.log"
