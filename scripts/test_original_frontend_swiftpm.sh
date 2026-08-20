#!/usr/bin/env bash
set -euo pipefail

# Production-link smoke for the isolated SwiftPM target. This intentionally
# builds GoldenEyeOriginalFrontendSmoke rather than the full app so unrelated
# host/UI lanes cannot hide whether the source target itself is linkable.

ROOT=$(cd "$(dirname "$0")/.." && pwd)
EVIDENCE_ROOT="$ROOT/build/native/original-source-v6/swiftpm"
mkdir -p "$EVIDENCE_ROOT"
FRONT_SHA_BEFORE=$(shasum -a 256 "$ROOT/src/game/front.c" | awk '{print $1}')
TITLE_SHA_BEFORE=$(shasum -a 256 "$ROOT/src/game/title.c" | awk '{print $1}')

audit_variant() {
    local variant="$1"
    local build_log="$EVIDENCE_ROOT/build-$variant.log"
    local smoke_log="$EVIDENCE_ROOT/smoke-$variant.log"
    local product_config="Debug"
    if [[ "$variant" == "release" ]]; then
        product_config="Release"
    fi
    local target_object="$ROOT/.build/out/Products/$product_config/GoldenEyeOriginalFrontend.o"
    local unresolved="$EVIDENCE_ROOT/unresolved-$variant.txt"

    if ! swift build --target GoldenEyeOriginalFrontend -c "$variant" >"$build_log" 2>&1; then
        cat "$build_log" >&2
        return 1
    fi
    if ! swift run GoldenEyeOriginalFrontendSmoke -c "$variant" >"$smoke_log" 2>&1; then
        cat "$smoke_log" >&2
        return 1
    fi
    if [[ ! -f "$target_object" ]]; then
        target_object=$(find "$ROOT/.build" -path "*/$product_config/*/GoldenEyeOriginalFrontend.o" -type f | sort | tail -n 1)
    fi
    if [[ -z "$target_object" || ! -f "$target_object" ]]; then
        echo "GoldenEyeOriginalFrontend $variant object not found" >&2
        return 1
    fi

    nm -u "$target_object" | sed 's/^_*//' | sort -u >"$unresolved"
    # These are the exact Apple runtime/compiler ABI symbols observed in the
    # target object. Release uses sincosf_stret; Debug uses separate sinf/cosf.
    if grep -Ev '^(bzero|cosf|memcpy|memset|sinf|sincosf_stret|sprintf|strcat|strcpy|strlen|chkstk_darwin|stack_chk_fail|stack_chk_guard)$' "$unresolved" | grep -q .; then
        echo "unexpected non-system unresolved symbol in GoldenEyeOriginalFrontend ($variant)" >&2
        grep -Ev '^(bzero|cosf|memcpy|memset|sinf|sincosf_stret|sprintf|strcat|strcpy|strlen|chkstk_darwin|stack_chk_fail|stack_chk_guard)$' "$unresolved" >&2
        return 1
    fi

    echo "variant=$variant target_object=$target_object"
    echo "variant=$variant unresolved_system_symbols=$(wc -l < "$unresolved")"
    echo "variant=$variant warnings=$(rg -c 'warning:' "$build_log" || true)"
}

audit_variant debug
audit_variant release

FRONT_SHA_AFTER=$(shasum -a 256 "$ROOT/src/game/front.c" | awk '{print $1}')
TITLE_SHA_AFTER=$(shasum -a 256 "$ROOT/src/game/title.c" | awk '{print $1}')
if [[ "$FRONT_SHA_BEFORE" != "$FRONT_SHA_AFTER" ||
      "$TITLE_SHA_BEFORE" != "$TITLE_SHA_AFTER" ]]; then
    echo "source translation units changed during SwiftPM build" >&2
    exit 1
fi

echo "test_original_frontend_swiftpm: PASS"
echo "front_sha256=$FRONT_SHA_AFTER"
echo "title_sha256=$TITLE_SHA_AFTER"
echo "evidence=$EVIDENCE_ROOT"
