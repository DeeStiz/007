# Native Boot/Menu/Attract/120 Hz — Demo-Stage Loading Handoff (M25)

## State

M25 remains in progress, with all seven source stage families loading through
the corrected prepared asset root and the M24 lifecycle metadata contract. The
bounded scene/setup/material path is deterministic and source-owned: 468
background rooms, 2,225 setup objects, 2,230 pads/bound pads, 612 portals,
436 textures, 248 TLUTs, and 3,575 texture bindings validate. Static props are
drawable in every stage; character, AI, effects, HUD, weapon, and collision
categories remain explicit fail-closed work for M26/M27.

The external ROM remains preparation-only:

`/Users/derek/Documents/GoldenEye 007 (USA).z64`

SHA-1: `abe01e4aeb033b6c0836819f549c791b26cfde83`

## Ground-truth validation

- `bash scripts/test_stage_scene_packet.sh
  build/native/stage-assets-image-decoder-v6` — PASS seven stages, 468 rooms,
  `payload_bytes=2016864`, packet hash `13284805027105908470`.
- `bash scripts/test_stage_setup_packet.sh
  build/native/stage-assets-image-decoder-v6` — PASS strict/ASan/UBSan with
  `objects=2225`, `pads=2230`, `portals=612`; malformed packets fail closed.
- `bash scripts/test_stage_texture_catalog_v6.sh
  build/native/stage-assets-image-decoder-v6` — PASS textures `436`, TLUTs
  `248`, bindings `3575`, levels `568`, GPU representable `1`, unrepresentable
  mips `0`, and unclassified visibility `0`.
- `bash scripts/test_stage_model_scene_composer_v6.sh
  build/native/stage-assets-image-decoder-v6
  build/native/ramrom-visible-dependencies-v6` — PASS all seven stages. Static
  prop drawable counts are Dam `197/197`, Facility `267/267`, Runway `88/88`,
  Bunker I `123/123`, Silo `165/165`, Frigate `147/147`, and Train `200/200`.
  Character placements remain `0` drawable and the retained full-scene mask is
  `0x38` for every composition.
- The M24 lifecycle smoke remains a prerequisite and passes strict/ASan/UBSan
  with decoded arena `2016864` bytes, preserving handles and offsets without
  retaining payload pointers.

## Evidence boundary and deferred work

- These are source packet/composition and offscreen Metal preparation results;
  they are not N64 pixel parity, complete gameplay, or physical supplied-
  drawable acceptance.
- Do not clear `0x38` or treat identity-camera/full-scene compositions as
  presentable. The V7 gameplay-camera route is a separate opt-in scoped
  contract and only publishes a subset whose scoped unsupported mask is zero.
- M26 must supply authoritative player/camera/collision/AI and dynamic object
  ownership before characters, weapons, effects, HUD, or collision can be
  lowered. M27 still requires a Release supplied-drawable capture and inspected
  trace on a Metal 4-capable host.

## Watch for next milestone

- Preserve lifecycle stage ordering, asset handles, scene packet hashes,
  material binding hash `7101058211609237007`, and per-stage composition
  hashes while advancing gameplay ownership.
- Keep the corrected image-decoder root; the legacy `stage-assets` directory
  is not current release evidence.
- Keep external ROM and ignored generated artifacts out of commits/bundles.

## Reproduction

```sh
cd /Users/derek/Developer/goldeneye-swift
bash scripts/test_stage_scene_packet.sh build/native/stage-assets-image-decoder-v6
bash scripts/test_stage_setup_packet.sh build/native/stage-assets-image-decoder-v6
bash scripts/test_stage_texture_catalog_v6.sh build/native/stage-assets-image-decoder-v6
bash scripts/test_stage_model_scene_composer_v6.sh \
  build/native/stage-assets-image-decoder-v6 \
  build/native/ramrom-visible-dependencies-v6
bash scripts/test_stage_lifecycle_v6.sh build/native/stage-assets-image-decoder-v6
```

No commit, push, branch, reset, clean, or external-ROM bundling was performed.
