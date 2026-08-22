# Native Boot/Menu/Attract/120 Hz — Combiner/Raster Handoff (M9)

## What was done

M9 combiner/raster lowering is complete for the bounded source-admitted
contracts. Classic V4 replay remains frozen, `GEClassicRasterStateV5` carries
explicit depth/fog/alpha/blender/coverage policy, the title raster catalog
audits eight source tuples, and the source-scene shader consumes typed
one/two-cycle selectors, primitive/environment/shade/fog inputs, LOD fraction,
alpha, and coverage. Unsupported generic RDP combinations remain typed
fail-closed diagnostics rather than guessed state.

## Ground-truth validation

- `bash scripts/test_classic_raster_v5.sh` — PASS strict and ASan/UBSan:
  `states=2`, aggregate `2633078999532620274`.
- `bash scripts/test_native_title_raster_catalog.sh` — PASS strict and
  sanitized: `states=8`, aggregate `11519430422207814888`.
- `bash scripts/test_title_raster_v5.sh` — PASS source audit for Legal,
  Nintendo, GoldenEye, wallet, and Rareware; `uniqueTuples=8`, aggregate
  `11519430422207814888`.
- `bash scripts/test_source_scene_pipeline_corpus_v6.sh build/native/source-frontend-v6`
  — PASS canonical Legal/Nintendo/GoldenEye/Wallet/Rareware keys, exact
  G_FOG/G_RM_FOG_SHADE_A admission, alpha/coverage guards, and negative typed
  diagnostics.
- `bash scripts/test_rareware_lod_pipeline_v6.sh` — PASS canonical LOD,
  one-level TEXEL1 alias, missing-mip, non-Rareware tuple, and translucent
  mismatch guards.
- `bash scripts/test_classic_combiner_replay.sh` — PASS strict C, ASan/UBSan C,
  and Swift replay. Frozen hashes remain setup
  `6213740136672363482`, event `5747731189711370311`, key
  `16733630809188353388`.
- Existing Metal 4 shader/resource labels retain explicit combiner/raster
  fields; fresh hardware capture remains an environment-dependent validation
  step, not a substitute for the source packet tests.

## Evidence boundary and deferred work

- The bounded source tuples are admitted and rendered through the existing
  Metal 4 path; arbitrary RDP combiner/raster state, complete coverage math,
  and full N64 pixel parity remain unclaimed.
- Generic source lighting/look-at/texgen consumption belongs to M10. Dynamic
  skeletal/gameplay categories and physical sustained presentation remain open.
- Do not replace unsupported tuples with default blend/depth/texture state.

## Watch for next milestone

- Preserve exact raw OtherMode/combiner words and source hashes when adding
  transform/lighting lowering.
- Keep fog coordinates and source fog blender admission coupled; a fog color
  without the exact source render mode must fail closed.
- M10 rendering work should reload the Metal 4 pipeline, validation, capture,
  and GPU-debug skills before changing shaders or pipeline descriptors.

## Reproduction

```sh
cd /Users/derek/Developer/goldeneye-swift
bash scripts/test_classic_raster_v5.sh
bash scripts/test_native_title_raster_catalog.sh
bash scripts/test_title_raster_v5.sh
bash scripts/test_source_scene_pipeline_corpus_v6.sh build/native/source-frontend-v6
bash scripts/test_rareware_lod_pipeline_v6.sh
bash scripts/test_classic_combiner_replay.sh
```

No commit, push, branch, reset, clean, or external-ROM bundling was performed.
