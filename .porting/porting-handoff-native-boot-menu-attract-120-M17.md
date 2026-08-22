# Native Boot/Menu/Attract/120 Hz — Nintendo Screen Handoff (M17)

## What was done

M17 Nintendo is complete for the bounded source path. Paired authority timing
and skip rules retain the source duration, fixed-point half-step rotation and
1.07977 scale clamp are consumed by the frame, and source ambient-light
projection remains explicit. The source Nintendo GESM/GBI/material packet and
Metal 4 renderer produce deterministic 320×240 and Faithful-HD reference output
under API/shader validation.

## Ground-truth validation

- `bash scripts/test_nintendo_reference_capture_v6.sh build/native/source-frontend-v6`
  — PASS with Metal API/shader validation. Fresh metadata records ticks `590/591`,
  source timer `50`, source commands `821`, source triangles `1021`, rendered
  triangles `1018`, and textured/non-black output. Even/odd raw hashes are
  `1e3b7e0fde0fd36213572e5d3ccb5bd343c7bbf4adec214676b08f3277816788` and
  `672fa141b493f343249bdd775472af8942f52760cc1fab59d601c27ffb278ac2`.
- The same capture emits 320×240 and 640×480 PNGs; both were visually inspected
  and show the source Nintendo logo on the authored black canvas. These images
  are native-port evidence, not N64 pixel-parity proof.
- `bash scripts/test_title_route_v5.sh` — PASS strict/ASan/UBSan C and Swift
  route integration (`cast=34`, `demos=14`).
- `bash scripts/test_native_title_projection_evidence.sh` — PASS all eight
  packet aggregate `17378376777734745904`.
- `bash scripts/test_native_title_textures.sh` — PASS 92 guarded GETT rows and
  packet/hash/layout checks.
- `bash scripts/test_native_source_frontend_v6.sh` — PASS full GEFV/GESM
  generation and tamper rejection.

## Evidence boundary and deferred work

- Full authored swoosh and N64 texture/material/pixel parity remain unclaimed.
- Physical sustained 120/60 presentation and active desktop acceptance remain
  separate from the source reference capture.
- No procedural replacement or fallback geometry was introduced.

## Watch for next milestone

- Preserve paired even/odd rotation/scale hashes and source ambient-light
  values when adding Rareware fade/LOD work.
- Keep source order and source node/GBI draw counts stable; a non-black frame
  alone is not proof of source material closure.
- M18 will need source mip/LOD and title capture validation on Metal 4.

## Reproduction

```sh
cd /Users/derek/Developer/goldeneye-swift
bash scripts/test_nintendo_reference_capture_v6.sh build/native/source-frontend-v6
bash scripts/test_title_route_v5.sh
bash scripts/test_native_title_projection_evidence.sh
bash scripts/test_native_title_textures.sh
bash scripts/test_native_source_frontend_v6.sh
```

No commit, push, branch, reset, clean, or external-ROM bundling was performed.
