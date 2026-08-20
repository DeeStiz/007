#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="${PROJECT_ROOT}/build/native/classic-combiner"
PROP_PATH="${PROJECT_ROOT}/build/native/classic-prop/Pammo_crate1Z.bin"
TEXTURE_ROOT="${PROJECT_ROOT}/build/native/classic-textures"
ROM_PATH="${GOLDENEYE_US_ROM:-/Users/derek/Documents/GoldenEye 007 (USA).z64}"
REFERENCE_EVIDENCE="${PROJECT_ROOT}/.porting/m0-provenance.md"

mkdir -p "${BUILD_DIR}"

fail() {
    echo "classic combiner replay validation: $*" >&2
    exit 1
}

require_file() {
    [[ -f "$1" ]] || fail "missing file $1"
}

require_nonempty() {
    require_file "$1"
    [[ -s "$1" ]] || fail "empty file $1"
}

require_line() {
    local expected="$1"
    local path="$2"
    grep -Fqx "${expected}" "${path}" ||
        fail "missing exact line in ${path}: ${expected}"
}

digest_sha1() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 1 "$1" | awk '{print $1}'
    else
        sha1sum "$1" | awk '{print $1}'
    fi
}

digest_sha256() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        sha256sum "$1" | awk '{print $1}'
    fi
}

echo "Checking M0 provenance and external-input boundaries"
require_nonempty "${REFERENCE_EVIDENCE}"
grep -Fq 'make -j8 IDO_RECOMP=NO VERSION=US COMPARE=1 VERBOSE=1' \
    "${REFERENCE_EVIDENCE}" || fail "Linux reference command changed"
grep -Fq 'sha1sum -c ge007.u.sha1' "${REFERENCE_EVIDENCE}" ||
    fail "Linux reference hash command changed"
grep -Fq 'abe01e4aeb033b6c0836819f549c791b26cfde83' \
    "${REFERENCE_EVIDENCE}" || fail "reference ROM SHA-1 changed"

ROM_REAL_PATH=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' \
    "${ROM_PATH}")
case "${ROM_REAL_PATH}" in
    "${PROJECT_ROOT}"|"${PROJECT_ROOT}"/*)
        fail "external ROM is inside checkout: ${ROM_REAL_PATH}"
        ;;
esac
[[ "$(wc -c < "${ROM_REAL_PATH}" | tr -d '[:space:]')" == "12582912" ]] ||
    fail "external ROM size mismatch"
[[ "$(digest_sha1 "${ROM_REAL_PATH}")" == \
    "abe01e4aeb033b6c0836819f549c791b26cfde83" ]] ||
    fail "external ROM SHA-1 mismatch"

require_nonempty "${PROJECT_ROOT}/build/native/classic-prop/classic-prop-manifest.txt"
require_nonempty "${PROJECT_ROOT}/build/native/classic-prop/prepare-classic-prop-asset.log"
require_nonempty "${PROJECT_ROOT}/build/native/classic-textures/classic-texture-manifest.txt"
require_line 'manifest_status=PASS' \
    "${PROJECT_ROOT}/build/native/classic-prop/prepare-classic-prop-asset.log"
require_line 'manifest_status=PASS' \
    "${PROJECT_ROOT}/build/native/classic-textures/classic-texture-manifest.txt"
require_line 'rom_copied_into_checkout=false' \
    "${PROJECT_ROOT}/build/native/classic-prop/classic-prop-manifest.txt"
require_line 'rom_copied_into_bundle=false' \
    "${PROJECT_ROOT}/build/native/classic-prop/classic-prop-manifest.txt"
require_line 'rom_copied_into_checkout=false' \
    "${PROJECT_ROOT}/build/native/classic-textures/classic-texture-manifest.txt"
require_line 'rom_copied_into_bundle=false' \
    "${PROJECT_ROOT}/build/native/classic-textures/classic-texture-manifest.txt"
require_line 'private_payloads_copied_into_checkout=false' \
    "${PROJECT_ROOT}/build/native/classic-textures/classic-texture-manifest.txt"
require_line 'private_payloads_copied_into_bundle=false' \
    "${PROJECT_ROOT}/build/native/classic-textures/classic-texture-manifest.txt"
require_line 'external_rom_sha1=abe01e4aeb033b6c0836819f549c791b26cfde83' \
    "${PROJECT_ROOT}/build/native/classic-prop/classic-prop-manifest.txt"
require_line 'external_rom_sha1=abe01e4aeb033b6c0836819f549c791b26cfde83' \
    "${PROJECT_ROOT}/build/native/classic-textures/classic-texture-manifest.txt"
require_line 'binary_size=1488' \
    "${PROJECT_ROOT}/build/native/classic-prop/classic-prop-manifest.txt"
require_line 'binary_sha1=2902e2f28defaa2f99e514c12039a731e78072d7' \
    "${PROJECT_ROOT}/build/native/classic-prop/classic-prop-manifest.txt"
require_line 'texture_AMMOCRATE1_raw_sha256=7fefb1b76158430234fd17769798bc58319cb322bd88ae3a979f2bc1b8445ef5' \
    "${PROJECT_ROOT}/build/native/classic-textures/classic-texture-manifest.txt"
require_line 'texture_CRATEROPE_raw_sha256=4fce6fc79c4f45ba5164e2b31a635e3644b8e535b8bffa46014365bf1c978038' \
    "${PROJECT_ROOT}/build/native/classic-textures/classic-texture-manifest.txt"
require_line 'texture_AMMOTEXT765_raw_sha256=ec028a7399327a93b2300c42cfac3e1ab133d7ee1804fcd5bdd4b5a0dff05810' \
    "${PROJECT_ROOT}/build/native/classic-textures/classic-texture-manifest.txt"

if git -C "${PROJECT_ROOT}" ls-files -- '*.z64' '*.n64' '*.Z64' '*.N64' |
    grep -q .; then
    fail "a ROM is tracked"
fi
if git -C "${PROJECT_ROOT}" ls-files -- \
    'assets/obseg/prop/Pammo_crate1Z.bin' \
    'assets/images/split/AMMOCRATE1.bin' \
    'assets/images/split/AMMOTEXT765.bin' \
    'assets/images/split/CRATEROPE.bin' | grep -q .; then
    fail "a private extracted payload is tracked"
fi
git -C "${PROJECT_ROOT}" check-ignore -q "${BUILD_DIR}" ||
    fail "classic-combiner output is not ignored"

echo "Checking frozen V1/V2/V3 artifacts without rewriting them"
for artifact in \
    "${PROJECT_ROOT}/build/native/classic-textures/texture-replay-smoke.log" \
    "${PROJECT_ROOT}/build/native/classic-textures/texture-replay-sanitized.log" \
    "${PROJECT_ROOT}/build/native/classic-textures/texture-replay-swift-smoke.log" \
    "${PROJECT_ROOT}/build/native/m11-runtime.log" \
    "${PROJECT_ROOT}/build/native/m11-runtime-resize.log" \
    "${PROJECT_ROOT}/build/native/m11-classic-textured-prop.png" \
    "${PROJECT_ROOT}/build/native/m11-pixel.sha256" \
    "${PROJECT_ROOT}/build/native/m11-classic-textured-prop.gputrace/index" \
    "${PROJECT_ROOT}/build/native/m11-gpudebug.log"; do
    require_nonempty "${artifact}"
done

FROZEN_HASHES=(
    'v1=1522029846112142469'
    'v2Packet=65363635960931316'
    'v2Event=905714786767796339'
    'v2State=10439205544326414085'
    'packetHash=11580554792388204033'
    'eventHash=9845751795158270468'
    'materialHash=14168780479827987350'
)
for hash in "${FROZEN_HASHES[@]}"; do
    grep -Fq "${hash}" \
        "${PROJECT_ROOT}/build/native/classic-textures/texture-replay-smoke.log" ||
        fail "frozen hash missing from texture replay log: ${hash}"
done
grep -Fq 'frames=60 draws=240 uploadsPending=false lastSignal=60 resourceAllocations=6' \
    "${PROJECT_ROOT}/build/native/m11-runtime.log" ||
    fail "M11 runtime baseline changed"
grep -Fq 'frames=60 draws=240 uploadsPending=false lastSignal=60 resourceAllocations=6' \
    "${PROJECT_ROOT}/build/native/m11-runtime-resize.log" ||
    fail "M11 resize runtime baseline changed"
grep -Fq 'fbc8fc7de88a3a24141281edb7bf4c866241449dafd8673f9a35d19de89e223c' \
    "${PROJECT_ROOT}/build/native/m11-pixel.sha256" ||
    fail "M11 screenshot hash changed"
rg -q 'ce0.*3 blits' \
    "${PROJECT_ROOT}/build/native/m11-gpudebug.log" ||
    fail "M11 capture upload baseline changed"
rg -q 're1.*4 draws' \
    "${PROJECT_ROOT}/build/native/m11-gpudebug.log" ||
    fail "M11 capture draw baseline changed"

[[ "$(digest_sha256 "${PROJECT_ROOT}/build/native/m11-classic-textured-prop.png")" == \
    'fbc8fc7de88a3a24141281edb7bf4c866241449dafd8673f9a35d19de89e223c' ]] ||
    fail "M11 screenshot bytes changed"

for texture in AMMOCRATE1 AMMOTEXT765 CRATEROPE; do
    require_nonempty "${TEXTURE_ROOT}/${texture}.bin"
done
require_nonempty "${PROP_PATH}"

if command -v xcrun >/dev/null 2>&1; then
    CC=$(xcrun --sdk macosx --find clang)
    SWIFTC=$(xcrun --sdk macosx --find swiftc)
    SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
else
    CC=${CC:-clang}
    SWIFTC=${SWIFTC:-swiftc}
    SDKROOT=${SDKROOT:-}
fi

V4_SOURCES=()
while IFS= read -r source; do
    [[ -n "${source}" ]] && V4_SOURCES+=("${source}")
done < <(
    find "${PROJECT_ROOT}/native/src" -maxdepth 1 -type f \
        \( -name '*combiner*.c' -o -name '*render*mode*.c' -o -name '*lower*.c' \) \
        -print | sort
)
[[ "${#V4_SOURCES[@]}" -gt 0 ]] ||
    fail "no V4 combiner/render-mode C source found"

C_TESTS=()
while IFS= read -r test_source; do
    [[ -n "${test_source}" ]] && C_TESTS+=("${test_source}")
done < <(
    find "${PROJECT_ROOT}/native/tests" -maxdepth 1 -type f \
        \( -name '*combiner*smoke.c' -o -name '*render*mode*smoke.c' -o -name '*lower*smoke.c' \) \
        -print | sort
)
[[ "${#C_TESTS[@]}" -eq 1 ]] ||
    fail "expected exactly one V4 C smoke test, found ${#C_TESTS[@]}"
V4_TEST="${C_TESTS[0]}"

COMMON_CFLAGS=(-std=c11 -Wall -Wextra -Werror -O2 -I "${PROJECT_ROOT}/native/include")
TARGET_ARGS=()
if [[ -n "${SDKROOT}" ]]; then
    TARGET_ARGS=(-target arm64-apple-macosx27.0 -isysroot "${SDKROOT}")
fi

COMMON_SOURCES=(
    "${PROJECT_ROOT}/native/src/goldeneye_native.c"
    "${PROJECT_ROOT}/native/src/ge_classic_replay.c"
    "${PROJECT_ROOT}/native/src/ge_texture_decode.c"
    "${PROJECT_ROOT}/native/src/ge_texture_replay.c"
)
NORMAL="${BUILD_DIR}/classic_combiner_smoke"
SANITIZED="${BUILD_DIR}/classic_combiner_smoke_sanitized"
RUN_A="${BUILD_DIR}/classic-combiner-run-a.log"
RUN_B="${BUILD_DIR}/classic-combiner-run-b.log"
SANITIZED_LOG="${BUILD_DIR}/classic-combiner-sanitized.log"

echo "Building bounded V4 C smoke: ${V4_TEST}"
"${CC}" "${COMMON_CFLAGS[@]}" "${TARGET_ARGS[@]}" \
    "${COMMON_SOURCES[@]}" "${V4_SOURCES[@]}" "${V4_TEST}" \
    -lm -lpthread -o "${NORMAL}"
"${CC}" "${COMMON_CFLAGS[@]}" "${TARGET_ARGS[@]}" \
    -O1 -fno-omit-frame-pointer -fsanitize=address,undefined \
    "${COMMON_SOURCES[@]}" "${V4_SOURCES[@]}" "${V4_TEST}" \
    -lm -lpthread -o "${SANITIZED}"

echo "Running deterministic C V4 smoke twice"
"${NORMAL}" "${PROP_PATH}" | tee "${RUN_A}"
"${NORMAL}" "${PROP_PATH}" | tee "${RUN_B}"
cmp -s "${RUN_A}" "${RUN_B}" || fail "C V4 smoke output is nondeterministic"

echo "Running ASan/UBSan C V4 smoke"
ASAN_OPTIONS=halt_on_error=1:detect_leaks=0 \
UBSAN_OPTIONS=halt_on_error=1 \
    "${SANITIZED}" "${PROP_PATH}" | tee "${SANITIZED_LOG}"

for log in "${RUN_A}" "${SANITIZED_LOG}"; do
    rg -q -i 'v4|combiner|render.?mode|lower' "${log}" ||
        fail "V4 lowering evidence missing from ${log}"
    rg -q '(draws|drawPackets|draw_count)=4' "${log}" ||
        fail "four draw groups missing from ${log}"
    rg -q 'commands=22' "${log}" ||
        fail "22-command prop lowering missing from ${log}"
    rg -q 'setup=3' "${log}" ||
        fail "three-command ModelType-4 setup missing from ${log}"
done

SWIFT_TESTS=()
while IFS= read -r swift_test; do
    [[ -n "${swift_test}" ]] && SWIFT_TESTS+=("${swift_test}")
done < <(
    find "${PROJECT_ROOT}/native/tests" -maxdepth 1 -type f \
        \( -name '*combiner*swift*smoke.swift' -o -name '*render*mode*swift*smoke.swift' -o -name '*lower*swift*smoke.swift' \) \
        -print | sort
)
[[ "${#SWIFT_TESTS[@]}" -eq 1 ]] ||
    fail "expected exactly one V4 Swift smoke test, found ${#SWIFT_TESTS[@]}"
SWIFT_TEST="${SWIFT_TESTS[0]}"

SWIFT_BUILD_DIR="${BUILD_DIR}/swift"
mkdir -p "${SWIFT_BUILD_DIR}/module-cache"
NATIVE_OBJECTS=()
for source in "${COMMON_SOURCES[@]}" "${V4_SOURCES[@]}"; do
    object="${SWIFT_BUILD_DIR}/$(basename "${source}" .c).o"
    "${CC}" "${COMMON_CFLAGS[@]}" "${TARGET_ARGS[@]}" -c "${source}" -o "${object}"
    NATIVE_OBJECTS+=("${object}")
done
ar rcs "${SWIFT_BUILD_DIR}/libgoldeneye_native.a" "${NATIVE_OBJECTS[@]}"
SWIFT_ARGS=(-O)
if [[ -n "${SDKROOT}" ]]; then
    SWIFT_ARGS+=(-target arm64-apple-macosx27.0 -sdk "${SDKROOT}")
fi
SWIFT_BINARY="${SWIFT_BUILD_DIR}/classic_combiner_swift_smoke"
echo "Building and running Swift V4 smoke: ${SWIFT_TEST}"
CLANG_MODULE_CACHE_PATH="${SWIFT_BUILD_DIR}/module-cache" \
    "${SWIFTC}" "${SWIFT_ARGS[@]}" \
    -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_native_bridging.h" \
    -Xcc "-I${PROJECT_ROOT}/native/include" \
    "${NATIVE_OBJECTS[@]}" "${SWIFT_TEST}" \
    -Xlinker -lpthread -o "${SWIFT_BINARY}"
"${SWIFT_BINARY}" | tee "${BUILD_DIR}/classic-combiner-swift-smoke.log"
rg -q -i 'v4|combiner|render.?mode|lower' \
    "${BUILD_DIR}/classic-combiner-swift-smoke.log" ||
    fail "Swift V4 lowering evidence missing"
for hash in "${FROZEN_HASHES[@]}"; do
    grep -Fq "${hash}" "${BUILD_DIR}/classic-combiner-swift-smoke.log" ||
        fail "frozen hash missing from Swift V4 smoke: ${hash}"
done

git -C "${PROJECT_ROOT}" diff --check -- \
    scripts/build_m12_classic_combiner.sh \
    scripts/test_classic_combiner_replay.sh \
    native/tests/goldeneye_classic_combiner_swift_smoke.swift

echo "Classic combiner replay validation: PASS"
echo "C logs: ${RUN_A} ${RUN_B} ${SANITIZED_LOG}"
echo "Swift log: ${BUILD_DIR}/classic-combiner-swift-smoke.log"
