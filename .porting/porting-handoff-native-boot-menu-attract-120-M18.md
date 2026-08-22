# Native Boot/Menu/Attract/120 Hz — Rareware Screen Handoff (M18)

## What was done

M18 Rareware is complete for the bounded source path. The source nine-list
graph, 26-mip/four-chain texture contract, canonical LOD/FORCE_BLEND policy,
paired rotation/fade timing, source SFX 258, and projection consumption are
validated through the Metal 4 source renderer. Invalid LOD/mip/render-mode
combinations remain typed fail-closed diagnostics.

## Ground-truth validation

- `bash scripts/test_rareware_lod_pipeline_v6.sh` — PASS canonical key
  `f65fdea4bcfbd3f`, one-level TEXEL1 alias, missing-mip, non-Rareware tuple,
  and translucent mismatch guards.
- `bash scripts/test_rareware_reference_capture_v6.sh build/native/source-frontend-v6 build/native/source-scene-renderer-v6/GoldenEyeSourceSceneV6.metallib`
  — PASS with Metal API/shader validation. Source graph is `9` display lists,
  `389` commands, `268` triangles, `397` vertices, `6` textures, `26` mips,
  four mip chains, and zero unsupported visible commands. All phases consume
  projection `268/268`.
- Fresh phase metadata records:
  - odd `t20`: rotation Q16 `65536`, fade `72`;
  - even `t70`: rotation Q16 `6553600`, fade `255`;
  - front `t200`: rotation Q16 `23592960`, fade `110`;
  - late `t260`: fade `0`.
- 320×240 and Faithful-HD phase PNGs were visually inspected, including the
  t200 Rareware mark. This is native-port evidence, not N64 pixel parity.
- `bash scripts/test_title_route_v5.sh`, `bash scripts/test_native_title_textures.sh`,
  and `bash scripts/test_source_texture_store_v6.sh build/native/source-frontend-v6`
  — PASS; shared title route/material/mip resources remain deterministic.

## Evidence boundary and deferred work

- Exact N64 mip selection/pixel parity, complete source swoosh/audio mix, and
  physical sustained presentation remain open.
- The Rareware source capture is a compositor-independent native reference
  artifact; it does not prove live window cadence or store acceptance.

## Watch for next milestone

- Preserve the canonical LOD tuple and source mip chain; never pre-mix adjacent
  levels or substitute a one-level texture for a positive LOD request.
- M19 Gunbarrel must keep source attachment/pose timing separate from Rareware
  material state and continue to fail closed on unsupported dynamic paths.

## Reproduction

```sh
cd /Users/derek/Developer/goldeneye-swift
bash scripts/test_rareware_lod_pipeline_v6.sh
bash scripts/test_rareware_reference_capture_v6.sh build/native/source-frontend-v6 build/native/source-scene-renderer-v6/GoldenEyeSourceSceneV6.metallib
bash scripts/test_title_route_v5.sh
bash scripts/test_native_title_textures.sh
bash scripts/test_source_texture_store_v6.sh build/native/source-frontend-v6
```

No commit, push, branch, reset, clean, or external-ROM bundling was performed.
