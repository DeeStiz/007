#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="${PROJECT_ROOT}/build/native/classic-textures"
ASSET_ROOT="${1:-${PROJECT_ROOT}/assets/images/split}"
PROP_PATH="${2:-${PROJECT_ROOT}/build/native/classic-prop/Pammo_crate1Z.bin}"
DECODER_SOURCE="${PROJECT_ROOT}/native/src/ge_texture_decode.c"
REPLAY_SOURCE="${PROJECT_ROOT}/native/src/ge_texture_replay.c"
TEST_SOURCE="${PROJECT_ROOT}/native/tests/goldeneye_texture_replay_smoke.c"
SWIFT_TEST_SOURCE="${PROJECT_ROOT}/native/tests/goldeneye_texture_replay_swift_smoke.swift"
mkdir -p "${BUILD_DIR}"

if [[ ! -f "${DECODER_SOURCE}" ]]; then
    echo "classic texture replay validation: decoder source unavailable; implementation is incomplete" >&2
    exit 1
fi
if [[ ! -f "${REPLAY_SOURCE}" ]]; then
    echo "classic texture replay validation: textured replay source unavailable; implementation is incomplete" >&2
    exit 1
fi
if [[ ! -f "${PROP_PATH}" ]]; then
    echo "classic texture replay validation: missing prop payload ${PROP_PATH}" >&2
    exit 1
fi

for texture in AMMOCRATE1 AMMOTEXT765 CRATEROPE; do
    if [[ ! -f "${ASSET_ROOT}/${texture}.bin" ]]; then
        echo "classic texture replay validation: missing payload ${ASSET_ROOT}/${texture}.bin" >&2
        exit 1
    fi
done

expected_size_for() {
    case "$1" in
        AMMOCRATE1) echo 1610 ;;
        AMMOTEXT765) echo 551 ;;
        CRATEROPE) echo 1003 ;;
        *) return 1 ;;
    esac
}

expected_sha256_for() {
    case "$1" in
        AMMOCRATE1) echo 7fefb1b76158430234fd17769798bc58319cb322bd88ae3a979f2bc1b8445ef5 ;;
        AMMOTEXT765) echo ec028a7399327a93b2300c42cfac3e1ab133d7ee1804fcd5bdd4b5a0dff05810 ;;
        CRATEROPE) echo 4fce6fc79c4f45ba5164e2b31a635e3644b8e535b8bffa46014365bf1c978038 ;;
        *) return 1 ;;
    esac
}

digest_sha256() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        echo "classic texture replay validation: no SHA-256 tool available" >&2
        return 1
    fi
}

for texture in AMMOCRATE1 AMMOTEXT765 CRATEROPE; do
    actual_size=$(wc -c < "${ASSET_ROOT}/${texture}.bin" | tr -d '[:space:]')
    actual_sha256=$(digest_sha256 "${ASSET_ROOT}/${texture}.bin")
    [[ "${actual_size}" == "$(expected_size_for "${texture}")" ]] || {
        echo "classic texture replay validation: ${texture} size mismatch" >&2
        exit 1
    }
    [[ "${actual_sha256}" == "$(expected_sha256_for "${texture}")" ]] || {
        echo "classic texture replay validation: ${texture} SHA-256 mismatch" >&2
        exit 1
    }
done

REFERENCE_EVIDENCE="${PROJECT_ROOT}/.porting/m0-provenance.md"
grep -Fq 'make -j8 IDO_RECOMP=NO VERSION=US COMPARE=1 VERBOSE=1' \
    "${REFERENCE_EVIDENCE}"
grep -Fq 'sha1sum -c ge007.u.sha1' "${REFERENCE_EVIDENCE}"
grep -Fq 'abe01e4aeb033b6c0836819f549c791b26cfde83' \
    "${REFERENCE_EVIDENCE}"

for row in \
    '9430830,1610,assets/images/split/image33.bin,0,1' \
    '9437354,1003,assets/images/split/image37.bin,0,1' \
    '9438632,551,assets/images/split/image39.bin,0,1'; do
    grep -Fqx "${row}" "${PROJECT_ROOT}/imagelist.u.csv"
done

if git -C "${PROJECT_ROOT}" ls-files -- '*.z64' '*.n64' '*.Z64' '*.N64' | \
    grep -q .; then
    echo "classic texture replay validation: tracked ROM boundary violation" >&2
    exit 1
fi
if git -C "${PROJECT_ROOT}" ls-files -- \
    'assets/images/split/AMMOCRATE1.bin' \
    'assets/images/split/AMMOTEXT765.bin' \
    'assets/images/split/CRATEROPE.bin' | grep -q .; then
    echo "classic texture replay validation: tracked private texture boundary violation" >&2
    exit 1
fi

if command -v xcrun >/dev/null 2>&1; then
    CC=$(xcrun --sdk macosx --find clang)
    SWIFTC=$(xcrun --sdk macosx --find swiftc)
    SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
else
    CC=${CC:-clang}
    SWIFTC=${SWIFTC:-swiftc}
    SDKROOT=${SDKROOT:-}
fi

COMMON_CFLAGS=(-std=c11 -Wall -Wextra -Werror -O2 -I "${PROJECT_ROOT}/native/include")
TARGET_ARGS=()
if [[ -n "${SDKROOT}" ]]; then
    TARGET_ARGS=(-target arm64-apple-macosx27.0 -isysroot "${SDKROOT}")
fi

SMOKE="${BUILD_DIR}/goldeneye_texture_replay_smoke"
SANITIZED="${BUILD_DIR}/goldeneye_texture_replay_smoke_sanitized"
SMOKE_LOG="${BUILD_DIR}/texture-replay-smoke.log"
SANITIZED_LOG="${BUILD_DIR}/texture-replay-sanitized.log"

echo "Building C classic texture replay smoke"
"${CC}" "${COMMON_CFLAGS[@]}" "${TARGET_ARGS[@]}" \
    "${PROJECT_ROOT}/native/src/goldeneye_native.c" \
    "${PROJECT_ROOT}/native/src/ge_classic_replay.c" \
    "${DECODER_SOURCE}" "${REPLAY_SOURCE}" "${TEST_SOURCE}" \
    -lm -lpthread -o "${SMOKE}"

echo "Running deterministic C texture replay smoke"
"${SMOKE}" "${ASSET_ROOT}" "${PROP_PATH}" | tee "${SMOKE_LOG}"

echo "Building C texture replay smoke with ASan/UBSan"
"${CC}" "${COMMON_CFLAGS[@]}" "${TARGET_ARGS[@]}" \
    -O1 -fno-omit-frame-pointer -fsanitize=address,undefined \
    "${PROJECT_ROOT}/native/src/goldeneye_native.c" \
    "${PROJECT_ROOT}/native/src/ge_classic_replay.c" \
    "${DECODER_SOURCE}" "${REPLAY_SOURCE}" "${TEST_SOURCE}" \
    -lm -lpthread -o "${SANITIZED}"

echo "Running ASan/UBSan texture replay smoke"
ASAN_OPTIONS=halt_on_error=1:detect_leaks=0 \
UBSAN_OPTIONS=halt_on_error=1 \
    "${SANITIZED}" "${ASSET_ROOT}" "${PROP_PATH}" | tee "${SANITIZED_LOG}"

if command -v "${SWIFTC}" >/dev/null 2>&1 || [[ -x "${SWIFTC}" ]]; then
    SWIFT_BUILD_DIR="${BUILD_DIR}/swift"
    mkdir -p "${SWIFT_BUILD_DIR}/module-cache"
    NATIVE_OBJECTS=()
    for source in goldeneye_native ge_classic_replay ge_texture_decode ge_texture_replay; do
        object="${SWIFT_BUILD_DIR}/${source}.o"
        "${CC}" "${COMMON_CFLAGS[@]}" "${TARGET_ARGS[@]}" -c \
            "${PROJECT_ROOT}/native/src/${source}.c" -o "${object}"
        NATIVE_OBJECTS+=("${object}")
    done
    ar rcs "${SWIFT_BUILD_DIR}/libgoldeneye_native.a" "${NATIVE_OBJECTS[@]}"
    cp "${SWIFT_TEST_SOURCE}" "${SWIFT_BUILD_DIR}/main.swift"

    SWIFT_ARGS=(-O)
    if [[ -n "${SDKROOT}" ]]; then
        SWIFT_ARGS+=(-target arm64-apple-macosx27.0 -sdk "${SDKROOT}")
    fi
    echo "Building Swift V3 ABI/V1/V2 regression smoke"
    CLANG_MODULE_CACHE_PATH="${SWIFT_BUILD_DIR}/module-cache" \
        "${SWIFTC}" "${SWIFT_ARGS[@]}" \
        -import-objc-header "${PROJECT_ROOT}/native/tests/goldeneye_native_bridging.h" \
        -Xcc "-I${PROJECT_ROOT}/native/include" \
        "${SWIFT_BUILD_DIR}/libgoldeneye_native.a" \
        "${SWIFT_BUILD_DIR}/main.swift" -Xlinker -lpthread \
        -o "${SWIFT_BUILD_DIR}/goldeneye_texture_replay_swift_smoke"
    "${SWIFT_BUILD_DIR}/goldeneye_texture_replay_swift_smoke" | \
        tee "${BUILD_DIR}/texture-replay-swift-smoke.log"
else
    echo "Swift texture replay smoke: SKIP (swiftc unavailable)"
fi

git -C "${PROJECT_ROOT}" diff --check -- \
    native/tests/goldeneye_texture_replay_smoke.c \
    native/tests/goldeneye_texture_replay_swift_smoke.swift \
    scripts/test_classic_texture_replay.sh

echo "Classic texture replay validation: PASS"
echo "Artifacts: ${SMOKE_LOG} ${SANITIZED_LOG}"
if [[ -f "${BUILD_DIR}/texture-replay-swift-smoke.log" ]]; then
    echo "Artifacts: ${BUILD_DIR}/texture-replay-swift-smoke.log"
fi
