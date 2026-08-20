#!/usr/bin/env bash
set -eo pipefail

# Compile the checked-in front.c/title.c units as hosted arm64 source
# semantics.  The resulting executable is a reference-oracle smoke only; it
# is not part of the application target and never opens a ROM.

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
BUILD_ROOT="$ROOT/build/native/original-source-v6"
SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CLANG=$(xcrun --sdk macosx --find clang)

mkdir -p "$BUILD_ROOT/strict" "$BUILD_ROOT/asan-ubsan"

if ! command -v "$CLANG" >/dev/null 2>&1; then
    echo "clang not found: $CLANG" >&2
    exit 1
fi

FRONT_SHA_BEFORE=$(shasum -a 256 "$ROOT/src/game/front.c" | awk '{print $1}')
TITLE_SHA_BEFORE=$(shasum -a 256 "$ROOT/src/game/title.c" | awk '{print $1}')

COMMON_FLAGS=(
    -std=gnu11
    -Wno-everything
    -I"$ROOT"
    -I"$ROOT/include"
    -I"$ROOT/src"
    -I"$ROOT/src/game"
    -I"$ROOT/src/inflate"
    -I"$ROOT/native/include"
    -isysroot "$SDKROOT"
    -ffunction-sections
    -fdata-sections
)

HOST_DEFINES=(
    -D_LANGUAGE_C
    -DVERSION_US
    -DLANG_US
    -DREFRESH_NTSC
    -DLEFTOVERDEBUG
    -DLEFTOVERSPECTRUM
    -DBUGFIX_R0
    -DBYTEMATCH
)

HOST_FLAGS=(-Wall -Wextra -Werror)

build_variant() {
    local variant="$1"
    shift
    local output="$BUILD_ROOT/$variant"
    local -a extra_flags=()
    if (( $# > 0 )); then
        extra_flags=("$@")
    fi

    # The wrappers include the unchanged source units directly; section GC
    # keeps the exercised route bounded without copying source logic.
    "$CLANG" "${COMMON_FLAGS[@]}" -Wno-everything "${extra_flags[@]}" -O0 \
        -c "$ROOT/native/source_port/original/ge_original_front_c.c" \
        -o "$output/front.o"
    "$CLANG" "${COMMON_FLAGS[@]}" -Wno-everything "${extra_flags[@]}" -O0 \
        -c "$ROOT/native/source_port/original/ge_original_title_c.c" \
        -o "$output/title.o"
    "$CLANG" "${COMMON_FLAGS[@]}" "${HOST_DEFINES[@]}" "${HOST_FLAGS[@]}" "${extra_flags[@]}" -O0 \
        -c "$ROOT/native/source_port/original/ge_original_frontend_v6.c" \
        -o "$output/adapter.o"
    "$CLANG" "${COMMON_FLAGS[@]}" "${HOST_DEFINES[@]}" "${HOST_FLAGS[@]}" "${extra_flags[@]}" -O0 \
        -c "$ROOT/native/source_port/original/ge_original_host_stubs.c" \
        -o "$output/stubs.o"
    "$CLANG" "${COMMON_FLAGS[@]}" "${HOST_DEFINES[@]}" "${HOST_FLAGS[@]}" "${extra_flags[@]}" -O0 \
        -c "$ROOT/native/source_port/original/ge_original_production_weak_stubs.c" \
        -o "$output/weak-stubs.o"
    "$CLANG" "${COMMON_FLAGS[@]}" "${HOST_DEFINES[@]}" "${HOST_FLAGS[@]}" "${extra_flags[@]}" -O0 \
        -c "$ROOT/native/source_port/original/ge_original_frontend_v6_smoke.c" \
        -o "$output/smoke.o"

    "$CLANG" "${extra_flags[@]}" \
        "$output/smoke.o" "$output/adapter.o" "$output/front.o" \
        "$output/title.o" "$output/stubs.o" "$output/weak-stubs.o" \
        -isysroot "$SDKROOT" -Wl,-dead_strip \
        -o "$output/ge_original_frontend_v6_smoke"

    if [[ "$variant" == "asan-ubsan" ]]; then
        ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 \
            "$output/ge_original_frontend_v6_smoke"
    else
        "$output/ge_original_frontend_v6_smoke"
        SWIFTC=$(xcrun --find swiftc)
        "$SWIFTC" -sdk "$SDKROOT" -target arm64-apple-macosx27.0 \
            -Xcc -I -Xcc "$ROOT/native/include" \
            -Xcc -I -Xcc "$ROOT/native/source_port/original" \
            -import-objc-header \
            "$ROOT/native/source_port/original/ge_original_frontend_v6_swift_bridge.h" \
            "$ROOT/native/source_port/original/ge_original_frontend_v6_swift_smoke.swift" \
            "$output/adapter.o" "$output/front.o" "$output/title.o" \
            "$output/stubs.o" "$output/weak-stubs.o" -Xlinker -dead_strip \
            -o "$output/ge_original_frontend_v6_swift_smoke"
        "$output/ge_original_frontend_v6_swift_smoke"
    fi

    # Keep the unresolved source inventory and the explicit host sink set as
    # inspectable evidence.  These files are private build artifacts.
    {
        echo "variant=$variant"
        echo "front_wrapper=$ROOT/native/source_port/original/ge_original_front_c.c"
        echo "title_wrapper=$ROOT/native/source_port/original/ge_original_title_c.c"
        echo "front_source=$ROOT/src/game/front.c"
        echo "title_source=$ROOT/src/game/title.c"
        echo "front_sha256=$FRONT_SHA_BEFORE"
        echo "title_sha256=$TITLE_SHA_BEFORE"
        echo "source_unresolved_symbols="
        nm -u "$output/front.o" "$output/title.o" | sed 's/^/  /'
        echo "host_sink_symbols="
        nm -g "$output/stubs.o" | sed 's/^/  /'
    } > "$output/dependency-map.txt"
}

build_variant strict
build_variant asan-ubsan -fsanitize=address,undefined -fno-omit-frame-pointer

FRONT_SHA_AFTER=$(shasum -a 256 "$ROOT/src/game/front.c" | awk '{print $1}')
TITLE_SHA_AFTER=$(shasum -a 256 "$ROOT/src/game/title.c" | awk '{print $1}')
if [[ "$FRONT_SHA_BEFORE" != "$FRONT_SHA_AFTER" ||
      "$TITLE_SHA_BEFORE" != "$TITLE_SHA_AFTER" ]]; then
    echo "source translation units changed during reference build" >&2
    exit 1
fi

if rg -n 'fopen|openat|open\(|GoldenEye.*\.z64|\.z64' \
    "$ROOT/native/source_port/original" >/dev/null; then
    echo "original source reference adapter contains a forbidden ROM/file open" >&2
    exit 1
fi

echo "test_original_frontend_reference_v6: PASS"
echo "front_sha256=$FRONT_SHA_AFTER"
echo "title_sha256=$TITLE_SHA_AFTER"
echo "evidence=$BUILD_ROOT"
