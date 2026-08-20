#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
BUILD_DIR="${PROJECT_ROOT}/build/native/source-model-v6"
mkdir -p "${BUILD_DIR}"

if command -v xcrun >/dev/null 2>&1; then
    SWIFTC=$(xcrun --sdk macosx --find swiftc)
    SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
else
    SWIFTC=${SWIFTC:-swiftc}
    SDKROOT=${SDKROOT:-}
fi

SWIFT_ARGS=(-O -warnings-as-errors)
if [[ -n "${SDKROOT}" ]]; then
    SWIFT_ARGS+=(-target arm64-apple-macosx27.0 -sdk "${SDKROOT}")
fi

SMOKE="${BUILD_DIR}/goldeneye_source_model_v6_smoke"
LOG="${BUILD_DIR}/source-model-v6-smoke.log"
WORDS="${BUILD_DIR}/source-model-v6-words.tsv"
ORACLE="${BUILD_DIR}/source-model-v6-gbi-oracle"

echo "Building strict GESM V6 runtime parser/compiler smoke"
"${SWIFTC}" "${SWIFT_ARGS[@]}" \
    "${PROJECT_ROOT}/native/host/goldeneye_source_model_v6.swift" \
    "${PROJECT_ROOT}/native/tests/goldeneye_source_model_v6_smoke.swift" \
    -o "${SMOKE}"

echo "Running all eight generated sidecars"
"${SMOKE}" "${PROJECT_ROOT}/build/native/source-frontend-v6" "${WORDS}" | tee "${LOG}"

echo "Building strict old-GE/F3D macro oracle"
if command -v xcrun >/dev/null 2>&1; then
    CC=$(xcrun --sdk macosx --find clang)
    CFLAGS=(-target arm64-apple-macosx27.0 -isysroot "${SDKROOT}")
else
    CC=${CC:-clang}
    CFLAGS=()
fi
"${CC}" -std=c11 -Wall -Wextra -Werror "${CFLAGS[@]}" \
    -idirafter "${PROJECT_ROOT}/include" -x c -o "${ORACLE}" - <<'EOF'
typedef long ptrdiff_t;
#define _LANGUAGE_C
#define _SHIFTL(v, s, w) ((uint32_t)((((uint32_t)(v)) & ((w) == 32 ? 0xffffffffu : ((1u << (w)) - 1u))) << (s)))
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "gbi_extension.h"

static void macro_probe(void) {
    static const Gfx p0 = gsDPPipeSync();
    static const Gfx p1 = gsDPLoadSync();
    static const Gfx p2 = gsSPEndDisplayList();
    static const Gfx p3 = gsSPSetGeometryMode(0x2000);
    static const Gfx p4 = gsSPClearGeometryMode(0x2000);
    static const Gfx p5 = gsSPMatrix((void *)(uintptr_t)0x1234, G_MTX_MODELVIEW | G_MTX_LOAD | G_MTX_NOPUSH);
    static const Gfx p6 = gsSPVertex((void *)(uintptr_t)0x1234, 8, 0);
    static const Gfx p7 = gsSPTexture(0xffff, 0xffff, 2, 0, 1);
    static const Gfx p8 = gsSPUseTexture(1, 1, 2, 0, 0, TEXTURETYPE_MIPMAP, 0, 0, 0xabcdef);
    static const Gfx p9 = gsSPSetOtherMode(G_SETOTHERMODE_H, 20, 2, G_CYC_2CYCLE);
    static const Gfx p10 = gsDPSetCycleType(G_CYC_2CYCLE);
    static const Gfx p11 = gsDPSetTextureDetail(G_TD_CLAMP);
    static const Gfx p12 = gsDPSetTextureFilter(G_TF_BILERP);
    static const Gfx p13 = gsDPSetTextureLOD(G_TL_LOD);
    static const Gfx p14 = gsDPSetRenderMode(G_RM_AA_OPA_SURF, G_RM_AA_OPA_SURF2);
    static const Gfx p15 = gsDPSetCombine(0x26a004, 0xabcdef01);
    static const Gfx p16 = gsDPSetCombineLERP(TEXEL0, 0, PRIMITIVE, 0, TEXEL0, 0, PRIMITIVE, 0,
                                              TEXEL0, 0, PRIMITIVE, 0, TEXEL0, 0, PRIMITIVE, 0);
    static const Gfx p17 = gsDPSetTextureImage(G_IM_FMT_RGBA, G_IM_SIZ_16b, 1, (void *)(uintptr_t)0x1234);
    static const Gfx p18 = gsDPSetTile(G_IM_FMT_RGBA, G_IM_SIZ_16b, 8, 0, 0, 0, 5, 0, 0, 5, 0, 0);
    static const Gfx p19 = gsDPLoadBlock(7, 0, 0, 1023, 256);
    static const Gfx p20 = gsDPSetTileSize(0, 2, 2, 126, 126);
    static const Gfx p21 = gsSP1Triangle(0, 1, 2, 0);
    static const Gfx p22 = gsSP2Triangles(0, 1, 2, 0, 0, 2, 3, 0);
    static const Gfx p23 = gsSP4Triangles(0, 1, 2, 0, 2, 3, 4, 3, 4, 5, 6, 4);
    (void)p0; (void)p1; (void)p2; (void)p3; (void)p4; (void)p5; (void)p6; (void)p7; (void)p8; (void)p9; (void)p10; (void)p11; (void)p12; (void)p13; (void)p14; (void)p15; (void)p16; (void)p17; (void)p18; (void)p19; (void)p20; (void)p21; (void)p22; (void)p23;
}

static int source_word_fixtures(void) {
    Gfx legal_h = gsSPSetOtherMode(G_SETOTHERMODE_H, 20, 2, 0x00000000);
    Gfx legal_l = gsSPSetOtherMode(G_SETOTHERMODE_L, 3, 29, 0x00502048);
    Gfx legal_c = gsDPSetCombine(0xFFFFFF, 0xFFFE793C);
    Gfx nintendo_h = gsSPSetOtherMode(G_SETOTHERMODE_H, 20, 2, 0x00000000);
    Gfx nintendo_l = gsSPSetOtherMode(G_SETOTHERMODE_L, 3, 29, 0x00502048);
    Gfx nintendo_c = gsDPSetCombine(0x127E24, 0xFFFFF9FC);
    Gfx goldeneye_h = gsSPSetOtherMode(G_SETOTHERMODE_H, 20, 2, 0x00100000);
    Gfx goldeneye_l = gsSPSetOtherMode(G_SETOTHERMODE_L, 3, 29, 0x0C182048);
    Gfx goldeneye_c = gsDPSetCombine(0x26A004, 0x1F1093FF);
    return (uint32_t)legal_h.words.w1 == 0x00000000 && (uint32_t)legal_l.words.w1 == 0x00502048 && (uint32_t)legal_c.words.w1 == 0xFFFE793C &&
           (uint32_t)nintendo_h.words.w1 == 0x00000000 && (uint32_t)nintendo_l.words.w1 == 0x00502048 && (uint32_t)nintendo_c.words.w1 == 0xFFFFF9FC &&
           (uint32_t)goldeneye_h.words.w1 == 0x00100000 && (uint32_t)goldeneye_l.words.w1 == 0x0C182048 && (uint32_t)goldeneye_c.words.w1 == 0x1F1093FF;
}

static uint32_t parse_u32(const char *value) {
    return (uint32_t)strtoull(value, NULL, 10);
}

static Gfx expand0(const char *macro) {
    if (!strcmp(macro, "gsDPPipeSync")) { Gfx g = gsDPPipeSync(); return g; }
    if (!strcmp(macro, "gsDPLoadSync")) { Gfx g = gsDPLoadSync(); return g; }
    if (!strcmp(macro, "gsSPEndDisplayList")) { Gfx g = gsSPEndDisplayList(); return g; }
    return (Gfx){{0, 0}};
}

static Gfx expand1(const char *macro, const uint32_t *a) {
    if (!strcmp(macro, "gsSPSetGeometryMode")) { Gfx g = gsSPSetGeometryMode(a[0]); return g; }
    if (!strcmp(macro, "gsSPClearGeometryMode")) { Gfx g = gsSPClearGeometryMode(a[0]); return g; }
    if (!strcmp(macro, "gsDPSetCycleType")) { Gfx g = gsDPSetCycleType(a[0]); return g; }
    if (!strcmp(macro, "gsDPSetTextureDetail")) { Gfx g = gsDPSetTextureDetail(a[0]); return g; }
    if (!strcmp(macro, "gsDPSetTextureFilter")) { Gfx g = gsDPSetTextureFilter(a[0]); return g; }
    if (!strcmp(macro, "gsDPSetTextureLOD")) { Gfx g = gsDPSetTextureLOD(a[0]); return g; }
    return (Gfx){{0, 0}};
}

static Gfx expand2(const char *macro, const uint32_t *a) {
    if (!strcmp(macro, "gsSPMatrix")) { Gfx g = gsSPMatrix((void *)(uintptr_t)a[0], a[1]); return g; }
    if (!strcmp(macro, "gsDPSetCombine")) { Gfx g = gsDPSetCombine(a[0], a[1]); return g; }
    if (!strcmp(macro, "gsDPSetRenderMode")) { Gfx g = gsDPSetRenderMode(a[0], a[1]); return g; }
    return (Gfx){{0, 0}};
}

static Gfx expand3(const char *macro, const uint32_t *a) {
    if (!strcmp(macro, "gsSPVertex")) { Gfx g = gsSPVertex((void *)(uintptr_t)a[0], a[1], a[2]); return g; }
    return (Gfx){{0, 0}};
}

static Gfx expand4(const char *macro, const uint32_t *a) {
    if (!strcmp(macro, "gsSP1Triangle")) { Gfx g = gsSP1Triangle(a[0], a[1], a[2], a[3]); return g; }
    if (!strcmp(macro, "gsSPSetOtherMode")) { Gfx g = gsSPSetOtherMode(a[0], a[1], a[2], a[3]); return g; }
    if (!strcmp(macro, "gsDPSetTextureImage")) { Gfx g = gsDPSetTextureImage(a[0], a[1], a[2], (void *)(uintptr_t)a[3]); return g; }
    return (Gfx){{0, 0}};
}

static Gfx expand5(const char *macro, const uint32_t *a) {
    if (!strcmp(macro, "gsSPTexture")) { Gfx g = gsSPTexture(a[0], a[1], a[2], a[3], a[4]); return g; }
    if (!strcmp(macro, "gsDPLoadBlock")) { Gfx g = gsDPLoadBlock(a[0], a[1], a[2], a[3], a[4]); return g; }
    if (!strcmp(macro, "gsDPSetTileSize")) { Gfx g = gsDPSetTileSize(a[0], a[1], a[2], a[3], a[4]); return g; }
    return (Gfx){{0, 0}};
}

static Gfx expand8(const char *macro, const uint32_t *a) {
    if (!strcmp(macro, "gsSP2Triangles")) { Gfx g = gsSP2Triangles(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7]); return g; }
    return (Gfx){{0, 0}};
}

static Gfx expand9(const char *macro, const uint32_t *a) {
    if (!strcmp(macro, "gsSPUseTexture")) { Gfx g = gsSPUseTexture(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8]); return g; }
    return (Gfx){{0, 0}};
}

static Gfx expand12(const char *macro, const uint32_t *a) {
    if (!strcmp(macro, "gsDPSetTile")) { Gfx g = gsDPSetTile(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11]); return g; }
    if (!strcmp(macro, "gsSP4Triangles")) { Gfx g = gsSP4Triangles(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11]); return g; }
    return (Gfx){{0, 0}};
}

static Gfx expandOtherMode(const uint32_t *a) {
    Gfx g = gsSPSetOtherMode(a[0], a[1], a[2], a[3]); return g;
}

static int expandCombineLERP(const char *semantic, Gfx *out) {
    if (!strcmp(semantic, "gsDPSetCombineLERP(TEXEL0,0,PRIMITIVE,0,TEXEL0,0,PRIMITIVE,0,TEXEL0,0,PRIMITIVE,0,TEXEL0,0,PRIMITIVE,0)")) {
        *out = (Gfx)gsDPSetCombineLERP(TEXEL0,0,PRIMITIVE,0,TEXEL0,0,PRIMITIVE,0,TEXEL0,0,PRIMITIVE,0,TEXEL0,0,PRIMITIVE,0); return 1;
    }
    if (!strcmp(semantic, "gsDPSetCombineLERP(TEXEL0,TEXEL0,LOD_FRACTION,TEXEL0,TEXEL0,TEXEL0,LOD_FRACTION,TEXEL0,COMBINED,0,PRIMITIVE,0,COMBINED,0,PRIMITIVE,0)")) {
        *out = (Gfx)gsDPSetCombineLERP(TEXEL0,TEXEL0,LOD_FRACTION,TEXEL0,TEXEL0,TEXEL0,LOD_FRACTION,TEXEL0,COMBINED,0,PRIMITIVE,0,COMBINED,0,PRIMITIVE,0); return 1;
    }
    return 0;
}

static int expand(const char *macro, const char *semantic, const uint32_t *a, size_t n, uint32_t *w0, uint32_t *w1) {
    Gfx g;
    if (!strcmp(macro, "rawGfx") && n == 2) {
        g.words.w0 = a[0]; g.words.w1 = a[1];
        *w0 = (uint32_t)g.words.w0; *w1 = (uint32_t)g.words.w1;
        return 1;
    }
    if (n == 0) g = expand0(macro);
    else if (n == 1) g = expand1(macro, a);
    else if (n == 2) g = expand2(macro, a);
    else if (n == 3) g = expand3(macro, a);
    else if (n == 4) g = expand4(macro, a);
    else if (n == 5) g = expand5(macro, a);
    else if (n == 8) g = expand8(macro, a);
    else if (n == 9) g = expand9(macro, a);
    else if (n == 12) g = expand12(macro, a);
    else if (n == 16) { if (!expandCombineLERP(semantic, &g)) return 0; }
    else if (!strcmp(macro, "gsSPSetOtherMode") && n == 4) g = expandOtherMode(a);
    else return 0;
    *w0 = (uint32_t)g.words.w0; *w1 = (uint32_t)g.words.w1;
    return 1;
}

int main(int argc, char **argv) {
    macro_probe();
    if (!source_word_fixtures()) return 9;
    if (argc != 2) return 2;
    FILE *file = fopen(argv[1], "r");
    if (!file) return 3;
    char line[4096]; unsigned long rows = 0;
    if (!fgets(line, sizeof(line), file)) return 4;
    while (fgets(line, sizeof(line), file)) {
        char *fields[64] = {0}; size_t count = 0;
        for (char *field = strtok(line, "\t\r\n"); field && count < 64; field = strtok(NULL, "\t\r\n")) fields[count++] = field;
        if (count < 7) return 5;
        const char *macro = fields[2]; const char *semantic = fields[3]; uint32_t expected0 = parse_u32(fields[4]); uint32_t expected1 = parse_u32(fields[5]); size_t argcnt = (size_t)parse_u32(fields[6]);
        if (count < 7 + argcnt) return 6;
        uint32_t args[32] = {0}; if (argcnt > 32) return 7;
        for (size_t i = 0; i < argcnt; ++i) args[i] = parse_u32(fields[7 + i]);
        uint32_t actual0 = 0, actual1 = 0;
        if (!expand(macro, semantic, args, argcnt, &actual0, &actual1) || actual0 != expected0 || actual1 != expected1) {
            fprintf(stderr, "old-GE oracle mismatch model=%s command=%s macro=%s expected=%08x/%08x actual=%08x/%08x\n", fields[0], fields[1], macro, expected0, expected1, actual0, actual1); return 8;
        }
        rows++;
    }
    fclose(file);
    printf("source-model-v6 C old-GE oracle: PASS rows=%lu\n", rows);
    return 0;
}
EOF
"${ORACLE}" "${WORDS}"

grep -q "source-model-v6 validation: PASS models=8 macros=25" "${LOG}"
grep -q "source-model-v6 word manifest: rows=\(.*\) path=" "${LOG}"
grep -q "source-model-v6 compiler: legalpage .* PASS" "${LOG}"
grep -q "source-model-v6 compiler: walletbond .* PASS" "${LOG}"
grep -q "source-model-v6 compiler: rarewarelogo dynamic diagnostic=" "${LOG}"
grep -q '^packet_sha256=b9247beab28b0e101c471c1a94d0d4baebf8a3ea85e306981bef1365d3e485ad$' "${PROJECT_ROOT}/build/native/source-frontend-v6/source-frontend-v6-manifest.txt"
grep -q '^record_count=1517$' "${PROJECT_ROOT}/build/native/source-frontend-v6/source-frontend-v6-manifest.txt"

git -C "${PROJECT_ROOT}" diff --check -- \
    native/host/goldeneye_source_model_v6.swift \
    native/tests/goldeneye_source_model_v6_smoke.swift \
    scripts/test_source_model_v6.sh

echo "Source model V6 validation: PASS"
echo "Artifact: ${LOG}"
