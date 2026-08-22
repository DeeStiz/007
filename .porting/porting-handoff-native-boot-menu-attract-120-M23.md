# Native Boot/Menu/Attract/120 Hz — Cast Reel Handoff (M23)

## State

M23 remains in progress. The bounded source Cast route is covered through the
34-entry roster, unlock/guest gates, random and explicit selection, source
attachment lowering, Cast texture/render-mode preparation, deterministic
reference capture, and RAMROM handoff. The canonical Release now proves live
supplied-drawable Cast submissions; sustained physical presentation and Metal-4
capture acceptance remain open.

The external ROM remains preparation-only:

`/Users/derek/Documents/GoldenEye 007 (USA).z64`

SHA-1: `abe01e4aeb033b6c0836819f549c791b26cfde83`

## Ground-truth validation

- `bash scripts/test_cast_attachment_v6.sh` — PASS strict, ASan, and UBSan.
  Five bodies pass source texture audits and exact matrix lowering; each
  selected body reports 16 poses, 20 exact matrices, and 20 matrix transforms.
  The Natalya missing-`gsSPUseTexture` tamper is rejected fail-closed.
- `bash scripts/test_cast_chrfnp90_builder_v6.sh` — PASS strict, ASan, and
  UBSan: `commands=64`, `setups=7`, `vertexResources=10`, `draws=7`.
- `bash scripts/test_cast_texture_setup_v6.sh
  build/native/cast-frontend-v6-image-decoder-v6-fullweapons` — PASS for
  `oliveguard` (`commands=505`, `setups=56`) and `natalya` (`commands=626`,
  `setups=46`), with 12 Cast glyphs and 38 text rows in each packet.
- `bash scripts/test_cast_scene_composer_v6.sh
  build/native/cast-frontend-v6-image-decoder-v6-fullweapons` — PASS:
  `identities=30`, `animations=22`, `preparedModelCombinations=30`,
  `missingClosed=0`, `castTextFade=PASS`.
- `bash scripts/test_cast_ramrom_scene_v6.sh build/native/boot-assets
  build/native/stage-assets-image-decoder-v6` — PASS:
  `castIdentity=30`, `animations=22`, `demos=14`, `runs=28`, `manifest=14`,
  deterministic aggregate `6107930928028985404`. Stage visual work remains
  explicitly fail-closed in this Cast/RAMROM source-scene lane.
- `GE_CAST_STRICT_REGRESSION=1 bash scripts/test_cast_reference_capture_v6.sh
  build/native/cast-frontend-v6-image-decoder-v6-fullweapons
  build/native/gunbarrel-v6-prepared/gunbarrel.gbar
  build/native/source-scene-renderer-v6/GoldenEyeSourceSceneV6.metallib` —
  PASS with Metal API/shader validation and byte-identical repeat at
  `build/native/cast-reference-capture-v6/20260822T013921Z/`. This is the
  deterministic source-row-1 `boilerbond` capture (identity 1), not a
  `spicebond` identity claim: reference raw SHA-256
  `878411975a89eb4290a0313794927756b719651e71b5f0dca45e6b5e6d7ff713`,
  Faithful-HD raw SHA-256
  `ab49953288dd7eda553f47509e6146082d852fd71e0a27e690ab619f1202494a`.
- A corrected non-strict source-row-2 `spicebond` reference now passes with
  the same Metal API/shader validation when the source's second random word is
  carried explicitly as `GE_CAST_RANDOM_WORD=3` at
  `build/native/cast-reference-capture-v6/20260822T-cast-spicebond-row2-randomword3/`:
  `capturedIdentity=2`, `capturedBody=spicebond`, `randomWord=3`,
  `missingPrepared=0`, `unsupportedVisibleCount=0`, `drawCount=61`,
  `triangleCount=755`, and byte-identical repeat hashes
  `64766bd2d6667ab0ec1d633922f8424addb6d56fd7e04bb2a17bf3e6c3a04663` and
  `c5c38bce7123d960d89e6966284fb8ad5835a914d9200eaa162687d63f27b60c`.
  The earlier `...row2-current` artifact resolves `natalya` and is not
  Spicebond evidence. This is authoritative offscreen row-2 source evidence,
  not supplied-drawable or physical presentation acceptance.
- The correctly parameterized production route
  `GE_CAST_PRODUCTION_RUN_ID=m23-current bash
  scripts/test_cast_production_route_v6.sh "/Users/derek/Documents/GoldenEye
  007 (USA).z64"` builds and signs the debug capture app, but records
  `castSubmit=0`, `latestCrash=none` at
  `build/native/cast-production-route-v6/m23-current/blocker.txt`.
  A second bounded 240-second run with a 300-second cadence window records the
  same final source owner state (`tick=2964`, Gunbarrel `screen=3`,
  `subphase=3`) at
  `build/native/cast-production-route-v6/m23-long/blocker.txt`; no supplied-
  drawable Cast frame or `.gputrace` was produced.

## Evidence boundary

The source owner reaches and renders the Gunbarrel transition, but the current
login-window/headless WindowServer session stops delivering enough owner ticks
before the source GoldenEye-to-Cast transition. This is a display/session
cadence blocker, not evidence of a Cast source or Metal failure. Offscreen
Cast reference output is not substituted for a supplied-drawable production
claim. Keep the production Cast guard fail-closed and retain explicit blocker
diagnostics until an active visible desktop produces `castSubmit=1`, Metal API
and shader validation output, an inspected `.gputrace`, and sustained cadence.

## Watch for next milestone

- Preserve source Cast route ordering, random seed handling, attachment matrix
  provenance, and body/head/weapon resource aliases while advancing M24/M25.
- Keep the strict row-1 `boilerbond` capture separate from the new non-strict
  row-2 `spicebond` reference; neither is a live supplied-drawable Cast claim.
- Keep the external ROM untracked and out of bundles; do not commit generated
  `build/native` artifacts.

## Reproduction

```sh
cd /Users/derek/Developer/goldeneye-swift
bash scripts/test_cast_attachment_v6.sh
GE_CAST_ATTACHMENT_SANITIZER=address bash scripts/test_cast_attachment_v6.sh
GE_CAST_ATTACHMENT_SANITIZER=undefined bash scripts/test_cast_attachment_v6.sh
bash scripts/test_cast_chrfnp90_builder_v6.sh
GE_CAST_CHRFNP90_SANITIZER=address bash scripts/test_cast_chrfnp90_builder_v6.sh
GE_CAST_CHRFNP90_SANITIZER=undefined bash scripts/test_cast_chrfnp90_builder_v6.sh
bash scripts/test_cast_texture_setup_v6.sh \
  build/native/cast-frontend-v6-image-decoder-v6-fullweapons
bash scripts/test_cast_scene_composer_v6.sh \
  build/native/cast-frontend-v6-image-decoder-v6-fullweapons
bash scripts/test_cast_ramrom_scene_v6.sh build/native/boot-assets \
  build/native/stage-assets-image-decoder-v6
GE_CAST_STRICT_REGRESSION=1 bash scripts/test_cast_reference_capture_v6.sh \
  build/native/cast-frontend-v6-image-decoder-v6-fullweapons \
  build/native/gunbarrel-v6-prepared/gunbarrel.gbar \
  build/native/source-scene-renderer-v6/GoldenEyeSourceSceneV6.metallib
GE_CAST_SOURCE_INDEX=2 GE_CAST_RANDOM_WORD=3 \
  GE_CAST_RANDOM_SEED=0x12345678 GE_CAST_FLIP=false \
  GE_CAST_CAMERA_MODE=source-rng \
  bash scripts/test_cast_reference_capture_v6.sh \
  build/native/cast-frontend-v6-image-decoder-v6-fullweapons \
  build/native/gunbarrel-v6-prepared/gunbarrel.gbar \
  build/native/source-scene-renderer-v6/GoldenEyeSourceSceneV6.metallib
GE_CAST_PRODUCTION_RUN_ID=m23-current bash scripts/test_cast_production_route_v6.sh \
  "/Users/derek/Documents/GoldenEye 007 (USA).z64"
# Active-session row-2 production probe (requires Aqua/Metal 4):
GE_CAST_PRODUCTION_RUN_ID=m23-spicebond-row2 \
  GE_CAST_SOURCE_INDEX=2 GE_CAST_RANDOM_WORD=3 \
  bash scripts/test_cast_production_route_v6.sh \
  "/Users/derek/Documents/GoldenEye 007 (USA).z64"

## 2026-08-22 row-2 random-word contract continuation

- The non-rendering Cast composer smoke now explicitly checks the source
  second-random-word branch for identity row 2: even word `2` resolves the
  embedded `natalya` body, while odd word `3` resolves the prepared
  `spicebond` body. It also verifies both use the embedded-head contract.
- `bash scripts/test_cast_scene_composer_v6.sh
  build/native/cast-frontend-v6-image-decoder-v6-fullweapons` passes with
  `row2RandomBody=natalya/spicebond`, alongside the 30-row roster, text/fade,
  missing-model, and camera checks. This prevents the old even-word artifact
  from being mistaken for Spicebond evidence.
- The current Metal reference harness still skips without Metal 4, and the
  live supplied-drawable Cast route remains a separate Aqua/Metal acceptance
  gate. No renderer fallback or identity substitution was added.
- Fresh correctly parameterized live row-2 probe:
  `build/native/cast-production-route-v6/m23-spicebond-row2-current2/` with
  `GE_CAST_SOURCE_INDEX=2 GE_CAST_RANDOM_WORD=3`. It records
  `castSubmit=0`, `latestCrash=none`; the owner stops in the first Gunbarrel
  cycle at tick `2952` under the current headless/login-window session. No
  supplied-drawable Cast frame or `.gputrace` is claimed.
- The launcher now forwards explicit `GOLDENEYE_NATIVE_FULLSCREEN`,
  `GOLDENEYE_CADENCE_FULLSCREEN`, and `GOLDENEYE_CADENCE_STRESS` policy. A
  fresh windowed/non-stress row-2 probe at
  `build/native/cast-production-route-v6/m23-spicebond-row2-windowed-20260822/`
  still records `castSubmit=0`, `latestCrash=none`, stopping at Gunbarrel tick
  `2960`; the live supplied-drawable blocker is therefore not a hidden
  fullscreen/stress default.
```

No commit, push, branch, reset, clean, or external-ROM bundling was performed.

## 2026-08-22 canonical Cast supplied-drawable continuation

- The final signed Release now reaches the source Cast reel in the canonical
  owner. Durable source-owner evidence under
  `build/native/boot-runtime/cadence/runs/m23-cast-v7-freeze-20260822-120/120/`
  records `castSceneSubmit=1` beginning at tick `3952` and continuing through
  the Cast/return route; the renderer frame log now appends every supplied
  callback instead of retaining only the last line.
- The same run reaches the opt-in V7 handoff and publishes a supplied-drawable
  Facility frame at tick `4324`: demo `4`, room `68`, `158/158` props, `42`
  dynamic doors, `1191` draws, camera packet hash `4171253561713628972`,
  composition hash `9008813320083006498`, scoped unsupported `0`, retained
  full-scene `0x38`. Stage frame records appear in
  `source-product-renderer-frames.log` with `stageEnvironment=1`.
- Logic cadence remains approximately 120 Hz with zero dropped ticks, zero
  fatal debt, and zero renderer failures. Presented timestamps/FPS remain
  unavailable in the login-window session; current Metal-4 capture attempts
  still SKIP, so M23 is advanced but not physically or GPU-trace accepted.
- The final Release executable is
  `ab0cd792d212d220936a0d670208f47a187757094b08568daa3c820faf7b2368`.
