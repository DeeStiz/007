#!/bin/bash
set -eo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$BASH_SOURCE")" && pwd -P)
ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd -P)
BUILD_ROOT="$ROOT/build/native/ramrom-character-head-selection-v6"
MODULE_CACHE="$BUILD_ROOT/module-cache"
mkdir -p "$BUILD_ROOT" "$MODULE_CACHE"

SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun --sdk macosx --find clang)
SWIFTC=$(xcrun --sdk macosx --find swiftc)

build_and_run() {
    label="$1"
    sanitizer="$2"
    gameplay_object="$BUILD_ROOT/$label-ge_ramrom_gameplay_v6.o"
    ramrom_object="$BUILD_ROOT/$label-ge_ramrom_v5.o"
    scene_object="$BUILD_ROOT/$label-ge_source_scene_v6.o"
    guard_object="$BUILD_ROOT/$label-ge_guard_door_owner_v6.o"
    weapon_object="$BUILD_ROOT/$label-ge_weapon_effect_owner_v6.o"
    binary="$BUILD_ROOT/goldeneye_ramrom_character_head_selection_v6_smoke_$label"
    if [[ -n "$sanitizer" ]]; then
        "$CC" -target arm64-apple-macosx27.0 -isysroot "$SDKROOT" \
            -std=c11 -Wall -Wextra -Werror -pedantic -O2 \
            -I "$ROOT/native/include" -fsanitize="$sanitizer" \
            -c "$ROOT/native/source_port/gameplay_v6/ge_ramrom_gameplay_v6.c" \
            -o "$gameplay_object"
        "$CC" -target arm64-apple-macosx27.0 -isysroot "$SDKROOT" \
            -std=c11 -Wall -Wextra -Werror -pedantic -O2 \
            -I "$ROOT/native/include" -fsanitize="$sanitizer" \
            -c "$ROOT/native/src/ge_ramrom_v5.c" -o "$ramrom_object"
        "$CC" -target arm64-apple-macosx27.0 -isysroot "$SDKROOT" \
            -std=c11 -Wall -Wextra -Werror -pedantic -O2 \
            -I "$ROOT/native/include" -fsanitize="$sanitizer" \
            -c "$ROOT/native/src/ge_source_scene_v6.c" -o "$scene_object"
        "$CC" -target arm64-apple-macosx27.0 -isysroot "$SDKROOT" \
            -std=c11 -Wall -Wextra -Werror -pedantic -O2 \
            -I "$ROOT/native/include" -fsanitize="$sanitizer" \
            -c "$ROOT/native/source_port/gameplay_v6/ge_guard_door_owner_v6.c" \
            -o "$guard_object"
        "$CC" -target arm64-apple-macosx27.0 -isysroot "$SDKROOT" \
            -std=c11 -Wall -Wextra -Werror -pedantic -O2 \
            -I "$ROOT/native/include" -fsanitize="$sanitizer" \
            -c "$ROOT/native/source_port/gameplay_v6/ge_weapon_effect_owner_v6.c" \
            -o "$weapon_object"
        CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" "$SWIFTC" \
            -swift-version 6 -warnings-as-errors -target arm64-apple-macosx27.0 \
            -sdk "$SDKROOT" -sanitize="$sanitizer" \
            -import-objc-header "$ROOT/native/tests/goldeneye_ramrom_gameplay_v6_bridging.h" \
            -Xcc "-I$ROOT/native/include" \
            "$ROOT/native/host/goldeneye_ramrom_character_head_selection_v6.swift" \
            "$ROOT/native/tests/goldeneye_ramrom_character_head_selection_v6_smoke.swift" \
            "$gameplay_object" "$ramrom_object" "$scene_object" "$guard_object" \
            "$weapon_object" -o "$binary"
    else
        "$CC" -target arm64-apple-macosx27.0 -isysroot "$SDKROOT" \
            -std=c11 -Wall -Wextra -Werror -pedantic -O2 \
            -I "$ROOT/native/include" \
            -c "$ROOT/native/source_port/gameplay_v6/ge_ramrom_gameplay_v6.c" \
            -o "$gameplay_object"
        "$CC" -target arm64-apple-macosx27.0 -isysroot "$SDKROOT" \
            -std=c11 -Wall -Wextra -Werror -pedantic -O2 \
            -I "$ROOT/native/include" \
            -c "$ROOT/native/src/ge_ramrom_v5.c" -o "$ramrom_object"
        "$CC" -target arm64-apple-macosx27.0 -isysroot "$SDKROOT" \
            -std=c11 -Wall -Wextra -Werror -pedantic -O2 \
            -I "$ROOT/native/include" \
            -c "$ROOT/native/src/ge_source_scene_v6.c" -o "$scene_object"
        "$CC" -target arm64-apple-macosx27.0 -isysroot "$SDKROOT" \
            -std=c11 -Wall -Wextra -Werror -pedantic -O2 \
            -I "$ROOT/native/include" \
            -c "$ROOT/native/source_port/gameplay_v6/ge_guard_door_owner_v6.c" \
            -o "$guard_object"
        "$CC" -target arm64-apple-macosx27.0 -isysroot "$SDKROOT" \
            -std=c11 -Wall -Wextra -Werror -pedantic -O2 \
            -I "$ROOT/native/include" \
            -c "$ROOT/native/source_port/gameplay_v6/ge_weapon_effect_owner_v6.c" \
            -o "$weapon_object"
        CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" "$SWIFTC" \
            -swift-version 6 -warnings-as-errors -target arm64-apple-macosx27.0 \
            -sdk "$SDKROOT" \
            -import-objc-header "$ROOT/native/tests/goldeneye_ramrom_gameplay_v6_bridging.h" \
            -Xcc "-I$ROOT/native/include" \
            "$ROOT/native/host/goldeneye_ramrom_character_head_selection_v6.swift" \
            "$ROOT/native/tests/goldeneye_ramrom_character_head_selection_v6_smoke.swift" \
            "$gameplay_object" "$ramrom_object" "$scene_object" "$guard_object" \
            "$weapon_object" -o "$binary"
    fi
    if [[ "$label" == "asan" ]]; then
        ASAN_OPTIONS=halt_on_error=1:detect_leaks=0 "$binary" | tee "$BUILD_ROOT/$label.log"
    elif [[ "$label" == "ubsan" ]]; then
        UBSAN_OPTIONS=halt_on_error=1 "$binary" | tee "$BUILD_ROOT/$label.log"
    else
        "$binary" | tee "$BUILD_ROOT/$label.log"
    fi
    grep -Fq 'goldeneye_ramrom_character_head_selection_v6_smoke: PASS' \
        "$BUILD_ROOT/$label.log"
}

build_and_run strict ''
build_and_run asan address
build_and_run ubsan undefined
echo 'RAMROM character source head-selection V6 validation: PASS'
