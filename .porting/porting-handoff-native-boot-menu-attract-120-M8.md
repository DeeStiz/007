# Native Boot/Menu/Attract/120 Hz — Texture/TMEM/TLUT Handoff (M8)

## What was done

M8 texture/TMEM/TLUT lowering is complete for the bounded source-product path.
The existing source setup resolver and texture store were validated as one
source-authoritative contract: exact format/size and image-load state, sampler
address/mirror/clamp flags, texture scale/LOD, full source mip relationships,
and TLUT/palette records are copied into fixed-width upload descriptors. Metal 4
uploads private RGBA8 textures from shared staging through the unified compute
encoder with persistent residency and explicit visibility synchronization.

## Ground-truth validation

- `bash scripts/test_source_texture_setup_v6.sh build/native/source-frontend-v6`
  — PASS strict/ASan/UBSan (`embedded=14`, `wallet=41`, `aliases=19`,
  `wallet_palettes=13`).
- `bash scripts/test_source_texture_store_v6.sh build/native/source-frontend-v6`
  — PASS strict/ASan/UBSan. Source plan: `textures=122`, `levels=322`,
  `validated_palettes=25`, `unique_handles=122`. Metal 4 upload smoke passes
  `textures=123`, `levels=329`, `validated_palettes=26`, `gpu_palettes=0`,
  `bytes=2208836`; GPU TLUT allocation remains intentionally absent.
- `bash scripts/test_source_irregular_mip_v6.sh` — PASS strict/ASan/Metal 4;
  authored dimensions `65,33,17,9,5,3,1`, `levels=13`, `slices=7`.
- `bash scripts/test_stage_texture_catalog_v6.sh build/native/stage-assets-image-decoder-v6`
  — PASS: `textures=436`, `tluts=248`, `bindings=3575`, `levels=568`,
  `resources=101`, `boundDraws=2237`, `gpuRepresentable=1`,
  `unrepresentableMips=0`.
- `bash scripts/test_source_scene_texture_binding_v6.sh build/native/source-frontend-v6`
  — PASS strict/ASan (`resources=3`, `mips=14`, `palettes=1`).
- `bash scripts/test_source_title_material_contract_v6.sh build/native/source-frontend-v6`
  — PASS strict/ASan/UBSan (`textures=92`, `mips=199`, `tluts=2`, aggregate
  `4247163796f6616e44965ad3ad846d5de46311005d75984f9a4a7be9c201d848`).
- `bash scripts/test_native_source_frontend_v6.sh` — PASS generation, all
  eight GESM sidecar hashes, bounds, and tamper rejection.
- `swift build --disable-sandbox --configuration debug` — PASS.

## Evidence boundary and deferred work

- The legacy GETT title diagnostic packet remains base-level-only; it preserves
  source mip-tail provenance but is not promoted as full title material.
- GPU TLUT sampling and generic CI/IA/I shader consumers remain unclaimed. The
  source-product path is normalized to validated RGBA8 resources while retaining
  palette records for the future material lowerer.
- Physical Metal 4 supplied-drawable title/gameplay capture, sustained cadence,
  and complete source visual/pixel parity remain later acceptance gates.

## Watch for next milestone

- Preserve private texture storage, one shared staging allocation per upload
  plan, queue-level residency, and completion-event retirement. Never add
  `StorageModeManaged`, blit encoders, per-encoder bindings, or fallback
  textures.
- M9 should consume these records for explicit combiner/raster state; do not
  infer a TLUT sample or silently promote the legacy GETT base-level path.
- GPU capture/inspection remains required on a Metal 4-capable host before any
  visual material claim.

## Reproduction

```sh
cd /Users/derek/Developer/goldeneye-swift
bash scripts/test_source_texture_setup_v6.sh build/native/source-frontend-v6
bash scripts/test_source_texture_store_v6.sh build/native/source-frontend-v6
bash scripts/test_source_irregular_mip_v6.sh
bash scripts/test_stage_texture_catalog_v6.sh build/native/stage-assets-image-decoder-v6
bash scripts/test_source_scene_texture_binding_v6.sh build/native/source-frontend-v6
bash scripts/test_source_title_material_contract_v6.sh build/native/source-frontend-v6
bash scripts/test_native_source_frontend_v6.sh
```

No commit, push, branch, reset, clean, or external-ROM bundling was performed.
