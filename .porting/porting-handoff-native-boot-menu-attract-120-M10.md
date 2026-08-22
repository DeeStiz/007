# Native Boot/Menu/Attract/120 Hz — Transform/Lighting Handoff (M10)

## What was done

M10 transform/lighting lowering is complete for the bounded source-admitted
path. Projection V10 preserves fixed-width source quantization, explicit
projection/viewport roles, six-plane clipping, culling, canonical 4:3 and
widescreen mappings, and deterministic hashes. Immutable source draw packets
carry per-state model-view and geometry-mode records, normal transforms,
ambient/directional light values, reflection vectors for texgen, and exact
source fog coordinates. Unknown or linear-texgen states remain fail-closed.

## Ground-truth validation

- `bash scripts/test_native_projection_v10.sh` — PASS strict/ASan,
  `size=216`, hash `15192084148729639549`.
- `bash scripts/test_source_lighting_v6.sh` — PASS strict/ASan lighting and
  reflection-texgen fixture.
- `bash scripts/test_source_projection_binding_v6.sh` — PASS strict/ASan/UBSan,
  hash `cda3a6456e3056bc`.
- `bash scripts/test_source_projection_consumption_v6.sh` — PASS explicit
  projection roles and per-draw clip binding (`draws=12/12`).
- `bash scripts/test_native_title_projection_evidence.sh` — PASS all eight
  GETP packets, aggregate `17378376777734745904`.
- `bash scripts/test_metal_source_scene_v6.sh` — PASS strict/ASan source-scene
  renderer smoke and direct Metal 4 metallib compilation.
- Existing stage source-environment/V7 lanes retain exact fog sidecars and
  per-state lighting maps; the supplied-drawable production gate remains
  hardware-dependent and fail-closed.

## Evidence boundary and deferred work

- Linear texgen, generic unclassified look-at/material states, complete
  arbitrary RDP lighting, and N64 pixel parity remain unclaimed.
- The active supplied-drawable lighting failure observed in an earlier Metal 4
  session (`missing decoded GBI lighting state 0xe2100001`) remains a runtime
  diagnostic unless reproduced with a current Metal-capable session; current
  value-side tests require every admitted draw to carry an explicit lighting
  context/state mapping.
- Physical sustained 120/60 presentation and full gameplay-category rendering
  remain later acceptance gates.

## Watch for next milestone

- Preserve the source projection matrix/viewport role records and camera scale
  domain when adding 2D/layout work.
- Keep normal/reflection vectors value-only and reject non-finite or unsupported
  texgen states rather than falling back to identity lighting.
- M11 will need the window/layout, Metal validation, capture, and visual
  evidence skills before changing UI or adaptive-widescreen output.

## Reproduction

```sh
cd /Users/derek/Developer/goldeneye-swift
bash scripts/test_native_projection_v10.sh
bash scripts/test_source_lighting_v6.sh
bash scripts/test_source_projection_binding_v6.sh
bash scripts/test_source_projection_consumption_v6.sh
bash scripts/test_native_title_projection_evidence.sh
bash scripts/test_metal_source_scene_v6.sh
```

No commit, push, branch, reset, clean, or external-ROM bundling was performed.
