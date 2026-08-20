# Native Boot/Menu/Attract/120 Hz — Current Handoff

## State

The goal `native-boot-menu-attract-120` remains active and intentionally
incomplete. The worktree is dirty by design; no commit, branch, push, reset,
or cleanup was performed.

The signed Release product currently builds at:

`build/native/boot-runtime/GoldenEyeHost.app`

The external ROM remains outside the checkout at:

`/Users/derek/Documents/GoldenEye 007 (USA).z64`

with SHA-1 `abe01e4aeb033b6c0836819f549c791b26cfde83`.

## Implemented lanes

- V1–V4 hashes and Linux reference evidence remain frozen and pass.
- V5 fixed-width runtime, title, audio, stage, route, save, and RAMROM
  contracts are additive and pointer-free.
- Dedicated raw-clock owner scheduler and supplied-drawable Metal 4 display
  link are wired at 120 Hz authority cadence.
- Timestamped keyboard/controller mailbox, async 596-byte save persistence,
  source-derived Legal/Nintendo/GoldenEye/Rareware/walletbond packets plus a
  guarded Rareware atlas, prepared gunbarrel background, and readable
  File/Mode placeholder UI run in the
  signed app.
- C audio synth plus lock-free 8,192-frame SPSC/source-node output is wired;
  additive V6 reverb/composite-SFX vectors pass strict/ASan/UBSan/Release,
  title SFX IDs 18/77/79/111/258 are validated, and the product music/title path
  applies bounded reverb and schedules source SFX on a separate player node.
- GETF/GETC title font/catalog packets, direct Legal/File/Mode glyph geometry,
  source UI bounds, reusable inverse-hit-test layout for 4:3/16:9/ultrawide,
  seven guarded GETI icon rows, alpha-blended File Select icon draws, and
  shader letterboxing are guarded and build-green.
- File Select now enforces the source-style two-stage erase confirmation with
  Cancel as the default, and the boot-flow smoke covers select/create/erase
  confirmation behavior.
- Cast route, all 14 guarded RAMROM recordings, paired playback controller,
  owner playback service, seven-stage 21-resource catalog/bootstrap, and
  fixed resource packet/decoded-arena view copy-out plus the Swift 21-resource
  loader are validated. Value-only scene/setup packets now load all seven
  stage families, 468 background rooms, 2,225 setup objects, 2,230 pads/bound
  pads, 612 portals, and 2,016,864 decoded payload bytes; gameplay and Metal
  scene rendering remain explicit stubs.

## Validation evidence

- `scripts/build_native_boot.sh "/Users/derek/Documents/GoldenEye 007 (USA).z64"`
  passes Release build, Metal library compilation, signing, and codesign
  verification.
- `scripts/test_classic_combiner_replay.sh`
  preserves V1/V2/V3/V4 values exactly.
- Audio (including `scripts/test_audio_effects_v6.sh`), stage, title geometry,
  title text, title route, RAMROM parser/playback/service,
  owner, save, and 10,000-even-anchor title-reference smokes pass, including
  strict and sanitizer lanes where provided.
- `scripts/test_stage_scene_packet.sh build/native/stage-assets` passes with
  `stages=7 rooms=468 payload_bytes=2016864 hash=13284805027105908470`.
- `scripts/test_stage_setup_packet.sh build/native/stage-assets` passes strict,
  ASan, and UBSan setup/portal parsing with `objects=2225 pads=2230
  portals=612` and aggregate hash `1099511628177`.
- `scripts/test_stage_gameplay_runtime.sh build/native/stage-assets build/native/boot-assets`
  passes strict/ASan/UBSan over all seven stages and one RAMROM trace with
  `samples=1578 aggregate=4774828755625742329`; collision/AI/weapons/effects
  are explicit unsupported diagnostics rather than fake gameplay.
- `scripts/test_native_title_icons.sh` passes the guarded GETI packet with
  packet SHA-256 `ad3bce5805a36ee1bb3ab227ebbdcdab18629e53f5f1bedb47b50a2c0c256c9`
  and 23,572 decoded RGBA8 bytes.
- `/tmp/ge-gunbarrel-5.png` and `/tmp/goldeneye-m15-title.log` show the
  prepared body/head/WPPK packet handles 7/8/9 drawn over the guarded
  gunbarrel background; texture/lighting/animation parity remains unclaimed.
- `scripts/test_title_sfx.sh build/native/boot-assets` passes the five guarded
  frontend SFX IDs with deterministic hashes.
- `scripts/test_ramrom_all14.sh build/native/boot-assets/ramrom build/native/stage-assets`
  passes all 14 demos twice (`runs=28`, `abort_restore=14`) through strict,
  ASan/UBSan, Swift-service, and stage-scene preparation lanes.
- `scripts/test_title_layout.sh` passes the exact 320x240 8/11 scale,
  1920x1080 and 2560x1080 gutter transforms, round-trip inverse mapping, and
  shared File/Mode hit bounds.
- `build/native/boot-runtime/goldeneye-title-m15.gputrace` was inspected with
  `gpudebug`: one labeled title render encoder, fullscreen pass plus geometry
  draw, and a 960×540 BGRA8 drawable.
- Clean windowed Release telemetry: supplied drawable, 1,761 logic ticks,
  878 callbacks, zero unhandled callbacks, two resize applications.
- Fullscreen migration telemetry: supplied drawable and 1,244 callbacks;
  unexpected callbacks are marshaled to the owner run loop and counted.
- Latest fullscreen owner telemetry reached `ticks=2496`, `callbacks=2053`,
  and zero unhandled callbacks; the shutdown line now records target-
  presentation interval minima/maxima and available `presentedTime` samples.
- Latest signed Release windowed telemetry reached `ticks=1530`,
  `callbacks=1519`, `targetDeltaMinMs=7.8353`, and 1,508 presented-time
  samples. An explicit demo-0 run then prepared `stage=33 sceneReady=1`,
  consumed all 454 packets, and returned to title with matching recording/RNG
  hashes; all-14 stage/gameplay acceptance is still open.
- The cadence harness now records logic/target/presented/focus/migration/resize
  metrics for both named displays. Automated direct-launch runs prove roughly
  120 Hz logic but remain presentation-unproven on this WindowServer path:
  display callbacks arrive in bursts, target p95 is about 1 second, and
  presented-time samples can be zero. Do not treat this as 120 Hz acceptance;
  the cadence/visibility issue remains active.
- Latest clean Release shutdown: 1,201 logic ticks, 1,166 supplied-drawable
  callbacks, zero unexpected/marshaled/unhandled callbacks, `lastError=none`,
  and geometry handles `1,3,4,5,6` with prepared Rareware atlas.
- The guarded `LtitleE` source text catalog now validates 287 strings at
  runtime with decoded SHA-256
  `941cad932f414b9d3d86e3dc542c549f6c6c0de0725c4eeb4832be8496b3b4f1`.

## Explicit continuation work

1. Complete title wallet/icon pixels and full
   texture/combiner, mip/LOD, lighting, texgen, and render-mode lowering;
   current `.gepk` and Rareware atlas packets are bounded source-colored
   evidence, not pixel parity.
2. Finish source-mix/reverb tuning, composite Rareware SFX routing, and
   long-soak A/V acceptance.
3. Replace stage M26–M27 bounded runtime/renderer boundaries with native
   collision, AI, weapons/effects, and full Metal scene packets; setup/portal
   semantics and deterministic player/camera/room traversal now pass all
   seven stage families.
4. Exercise all 14 RAMROM recordings against those native stages twice,
   including abort/restore and checksum/RNG evidence.
5. Run sustained 120/60 presentation measurements, GPU/CPU p95, TSan/leaks,
   display migration, and final handoff only after the above closure.

## Required continuation commands

```sh
cd /Users/derek/Developer/goldeneye-swift
scripts/build_native_boot.sh "/Users/derek/Documents/GoldenEye 007 (USA).z64"
scripts/test_title_reference_v5.sh
scripts/test_stage_asset_catalog.sh build/native/stage-assets
scripts/test_stage_v5.sh
scripts/test_stage_resource_loader.sh build/native/stage-assets
scripts/test_stage_scene_packet.sh build/native/stage-assets
scripts/test_stage_setup_packet.sh build/native/stage-assets
scripts/test_native_title_geometry.sh
scripts/test_native_title_text.sh
scripts/test_native_title_icons.sh
scripts/test_audio_effects_v6.sh
scripts/test_title_sfx.sh build/native/boot-assets
scripts/test_ramrom_all14.sh build/native/boot-assets/ramrom build/native/stage-assets
scripts/test_title_text_catalog.sh
scripts/test_ramrom_playback_service.sh
```

Runtime never opens the ROM. Prepared/private payloads remain under ignored
`build/native/` and are not copied into the application bundle.

## Latest continuation delta

- Title preparation now emits five bounded packets: Legal, Nintendo,
  GoldenEye, Rareware, and walletbond. Rareware also has a guarded 64×86
  RGBA8 atlas; File Select draws walletbond geometry when available.
- Stage V5 now exposes deterministic metadata packet copy-out and decoded
-  arena view records in addition to the seven-stage catalog/bootstrap; the
  additive scene-packet lane copies decoded stage payloads and background
  rooms into bounded value-only packets.
- The title renderer now maps geometry/text packets through the canonical
  440x330 letterbox in the Metal vertex path, preserving the authored core on
  widescreen and narrow layouts.
- The integrated V6 audio source remains additive: V5 boot PCM hash
  `7358868759095366475` is unchanged while V6 graph/reverb vectors pass with
  graph hash `10304920864406538052` and reverb hash `6148009325550816421`.
- The latest Release build and codesign verification pass after these changes;
  strict stage, title-geometry, title-reference, and stage-catalog smokes pass.

## Validation refresh — 2026-08-18

- Rebuilt the signed Release app after the latest owner/title/input edits:
  `build/native/boot-runtime/GoldenEyeHost.app`. `codesign --verify
  --deep --strict` passes, the bundle contains no `.z64`, `.n64`, `.bin`, or
  `.rz` payload, and the external ROM still hashes to
  `abe01e4aeb033b6c0836819f549c791b26cfde83`.
- The focused lane is green: frozen classic-combiner/V1–V4 replay, title
  reference/route/layout/text/icon/geometry/SFX, audio effects/engine/output,
  stage setup/scene/gameplay, all-14 RAMROM, and owner-runtime smokes. The
  final Swift debug build and `git diff --check` pass.
- Metal API and shader validation were enabled before device creation for a
  bounded Release launch. The run reported only that validation was enabled;
  no Metal fault, shader error, assertion, or render failure was emitted.
- `gpudebug` inspection of the preserved M15 capture confirms the labeled
  supplied-drawable title encoder, fullscreen pass, geometry draw, BGRA8
  drawable, pipeline, and stage bindings. A fresh CLI capture was also made,
  but its short WindowServer run contained no command-buffer payload beyond
  the drawable boundary and is not used as stronger evidence.
- The clean named-display cadence harness continues to prove owner logic near
  120 Hz and the 60/120 target intervals, but automated direct/WindowServer
  launches still produce bursty callbacks and zero `presentedTime` samples in
  some runs. Sustained 120/60 presented-fps, CPU/GPU p95, and visual cadence
  acceptance remain open; no completion claim is made.
