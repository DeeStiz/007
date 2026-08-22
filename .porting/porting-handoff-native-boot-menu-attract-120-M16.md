# Native Boot/Menu/Attract/120 Hz — Legal Screen Handoff (M16)

## What was done

M16 Legal screen is complete for the bounded source path. The immutable Legal
frame consumes source authority at native tick 1, preserves the 241-tick
first-boot/unskippable-input rule, lowers the guarded Legal GESM/GBI packet and
five material groups, and emits source-ordered text events and Zurich glyphs.
Projection roles are consumed by every draw; no visible unsupported command or
fallback geometry is admitted.

## Ground-truth validation

- `bash scripts/test_legal_frame_v6.sh build/native/source-frontend-v6` — PASS
  strict/ASan/UBSan. Manifest: `source_gbi_commands=58`,
  `source_triangles=12`, `source_text_order=7,8,9,10,11,12,13,14,15,16,17,18`,
  `glyph_count=253`, `projection_consumption=12/12`, and zero unsupported
  visible/decoder commands. Frame hash is `4631003346486038644`.
- `bash scripts/test_legal_reference_capture_v6.sh build/native/source-frontend-v6`
  — PASS semantic 320×240 raw/PNG/JSON capture. The current host records the
  Metal-unavailable boundary explicitly; this is not physical pixel proof.
- `bash scripts/test_native_title_text.sh` — PASS source font packet/catalog,
  Legal 253 glyphs and 12,196 pixel quads, plus tamper rejection.
- `bash scripts/test_title_text_catalog.sh` — PASS 287 strings with source
  catalog hash `941cad932f414b9d3d86e3dc542c549f6c6c0de0725c4eeb4832be8496b3b4f1`.
- `bash scripts/test_title_reference_v5.sh` — PASS 10,000 even-anchor title
  comparisons and Cast→RAMROM transition.
- `bash scripts/test_title_route_v5.sh` — PASS strict/ASan/UBSan C and Swift
  route integration (`cast=34`, `demos=14`).

## Evidence boundary and deferred work

- The semantic 320×240 artifact proves source packet/lowering closure, not N64
  pixel parity or a physical supplied-drawable frame.
- Full source font/material visual parity and active-display presentation remain
  later acceptance gates; no procedural text fallback is promoted.

## Watch for next milestone

- Preserve the Legal source text order, coordinates, model packet hash, and
  projection consumption when adding Nintendo animation/material work.
- Keep first-boot Legal input suppression tied to the source 241-tick rule.
- M17 will need the title timing, source rotation/lighting, and Metal capture
  skills before changing Nintendo output.

## Reproduction

```sh
cd /Users/derek/Developer/goldeneye-swift
bash scripts/test_legal_frame_v6.sh build/native/source-frontend-v6
bash scripts/test_legal_reference_capture_v6.sh build/native/source-frontend-v6
bash scripts/test_native_title_text.sh
bash scripts/test_title_text_catalog.sh
bash scripts/test_title_reference_v5.sh
bash scripts/test_title_route_v5.sh
```

No commit, push, branch, reset, clean, or external-ROM bundling was performed.
