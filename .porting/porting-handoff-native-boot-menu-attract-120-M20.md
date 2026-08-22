# Native Boot/Menu/Attract/120 Hz — GoldenEye Logo Handoff (M20)

## What was done

M20 GoldenEye logo is complete for the bounded source path. The source GESM
graph, exact two-cycle LOD/combiner tuple, seven-level texture contract,
reflection/material state, paired title timing, and File/Mode route handoff are
validated through the source Metal 4 renderer. Unsupported material/texgen
states remain explicit diagnostics.

## Ground-truth validation

- `bash scripts/test_goldeneye_logo_reference_capture_v6.sh build/native/source-frontend-v6`
  — PASS with Metal API/shader validation. Metadata records source commands
  `162`, source triangles `339`, source slots `341`, vertices `438`, textures
  `2`, mip levels `7`, TLUTs `0`, zero unsupported visible work, and complete
  projection consumption. Paired ticks are `3423/3424`, source timers `0/1`.
- Fresh 320×240 and Faithful-HD PNGs were visually inspected; the GoldenEye
  wordmark and red ring render on the source black canvas. This is native-port
  evidence, not N64 pixel parity.
- `bash scripts/test_source_title_material_contract_v6.sh build/native/source-frontend-v6`
  — PASS strict/ASan/UBSan, `textures=92`, `mips=199`, `tluts=2`, aggregate
  `4247163796f6616e44965ad3ad846d5de46311005d75984f9a4a7be9c201d848`.
- `bash scripts/test_rareware_lod_pipeline_v6.sh` — PASS canonical LOD,
  one-level alias, missing-chain, tuple, and translucent guards.
- `bash scripts/test_title_route_v5.sh` and
  `bash scripts/test_native_title_projection_evidence.sh` — PASS route and
  all-eight packet projection aggregate `17378376777734745904`.

## Evidence boundary and deferred work

- Full N64 texgen/reflection/lighting/pixel parity and active physical cadence
  remain unclaimed; captures are native source-semantic evidence.
- GPU TLUT sampling and generic unsupported material variants remain fail-closed
  for later material work.

## Watch for next milestone

- Preserve the two-cycle LOD/combiner state, source mip levels, and paired title
  timing when advancing File/Mode or Cast route integration.
- M21 File Select must retain source wallet switch visibility and save actions;
  do not replace source UI with procedural geometry.

## Reproduction

```sh
cd /Users/derek/Developer/goldeneye-swift
bash scripts/test_goldeneye_logo_reference_capture_v6.sh build/native/source-frontend-v6
bash scripts/test_source_title_material_contract_v6.sh build/native/source-frontend-v6
bash scripts/test_rareware_lod_pipeline_v6.sh
bash scripts/test_title_route_v5.sh
bash scripts/test_native_title_projection_evidence.sh
```

No commit, push, branch, reset, clean, or external-ROM bundling was performed.
