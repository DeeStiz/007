# Native Boot/Menu/Attract/120 Hz — RAMROM Playback Handoff (M28)

## State

M28 remains in progress. All 14 source RAMROM recordings now parse and replay
twice through the strict and sanitized C path, preserving source packet/order,
checksums, RNG hashes, speedframes, abort, fade, and title restore. The Swift
owner service and all seven stage-scene preparation path are also green.
Native gameplay and renderer execution remain explicit `STUB(M26)`/
`STUB(M27)` boundaries; this handoff does not promote playback into a complete
stage frame.

The external ROM remains preparation-only:

`/Users/derek/Documents/GoldenEye 007 (USA).z64`

SHA-1: `abe01e4aeb033b6c0836819f549c791b26cfde83`

## Ground-truth validation

- `bash scripts/test_ramrom_all14.sh build/native/boot-assets/ramrom
  build/native/stage-assets-image-decoder-v6` — PASS strict and ASan/UBSan:
  `demos=14`, `runs=28`, `abort_restore=14`, `unique_stages=7`, parser/playback/
  checksum/RNG all PASS, gameplay `STUB(M26)`, renderer `STUB(M27)`.
  The Swift owner-service pass reports `aggregate=6851901412168630050`.
- `bash scripts/test_ramrom_playback_v5.sh build/native/boot-assets/ramrom` —
  PASS strict/ASan/UBSan paired 120/60 install/restore/abort diagnostics.
- `bash scripts/test_ramrom_v5.sh build/native/boot-assets/ramrom` — PASS
  strict/ASan/UBSan deterministic parser for all 14 demos.
- The all-14 run preserves per-demo packet/record/tick/checksum/RNG evidence in
  `build/native/ramrom-all14-validation/ramrom-all14.log`; representative Dam
  demo 1 values are `packets=454`, `records=1578`, `terminal_tick=3156`,
  recording hash `2965865516981191646`, and RNG hash `15626403191658321973`.
- The same all-14 script prepares the corrected stage root and passes seven
  scene packets (`rooms=468`, `payload_bytes=2016864`, packet hash
  `13284805027105908470`).

## Evidence boundary and deferred work

- Playback/parser/checksum/RNG evidence does not prove native gameplay,
  character/AI/effect/weapon/HUD rendering, Metal supplied-drawable output,
  physical presentation, or N64 pixel parity.
- Keep `STUB(M26)` and `STUB(M27)` diagnostics visible. Do not infer a scene
  frame from a playback packet or clear unsupported masks on return-to-title.
- M29 integrated acceptance still requires an active visible display, fresh
  Metal 4 traces, supplied-drawable Cast/gameplay evidence, sanitizers, and
  signed Release provenance.

## Watch for next milestone

- Preserve source route order, speedframes, exact packet/RNG/checksum hashes,
  real-input abort, fade, and title restore when integrating acceptance.
- Keep all 14 recording assets outside the runtime bundle and external ROM
  untracked.

## Reproduction

```sh
cd /Users/derek/Developer/goldeneye-swift
bash scripts/test_ramrom_all14.sh build/native/boot-assets/ramrom \
  build/native/stage-assets-image-decoder-v6
bash scripts/test_ramrom_playback_v5.sh build/native/boot-assets/ramrom
bash scripts/test_ramrom_v5.sh build/native/boot-assets/ramrom
```

No commit, push, branch, reset, clean, or external-ROM bundling was performed.

## 2026-08-22 canonical owner-loop continuation

- The source-faithful Release now runs the selected demo 4 / Facility route
  through packet return and a repeated attract cycle without paired authority
  failure. The repeated Gunbarrel blood stream is reset on each source-screen
  entry; the prior second-cycle mismatch (`native 6`, `original 5`) is gone.
- Final bounded run:
  `build/native/boot-runtime/cadence/runs/m28-blood-reset-20260822-120/120/`.
  It records `sourceAuthorityFailure=none`, `droppedTicks=0`,
  `fatalDebtTicks=0`, `renderFailures=0`, logic `120.0000 Hz`, and the
  Facility V7 frame at tick 4324 (`158/158` props, `1191` draws, scoped `0`,
  full-scene `0x38`). RAMROM reaches packet `559/559`.
- Presented timestamps/FPS remain unproven under the login-window session, and
  current Metal-4 capture/gputrace attempts still skip on this host. Native
  gameplay/category closure remains bounded to the explicit source-visible
  V7 subset.
- Final signed Release SHA-256:
  `289a98e3173fd3770ff081f3ef54d20310c63883a530ab2d7bcbc22bd5de6e0e`.

## 2026-08-22 repeated Gunbarrel source-authority continuation

- The previous long loop exposed a second-entry mismatch at tick `14370`
  (`native 6`, `original 5`). The cause was renderer-local blood state: the
  renderer did not observe Cast/SWITCH frames, so its last submitted frame
  still looked like Gunbarrel and its completion latch was not reset.
- `GoldenEyeSourceFrontendModelLifecycleV6` now exposes
  `resetGunbarrelBloodStream()`. `NativeTitleOwner` invokes it on the copied
  source transition into Gunbarrel, before Cast/RAMROM/source-frame routing;
  the renderer clears only blood frame index, continuation count, and the
  completion latch. The paired authority and full-scene fail-closed masks are
  unchanged.
- Focused standard/optional Cast/full-Cast paired authority and Gunbarrel
  projection smokes pass. The fresh Release is
  `fcc912c92170f2943a8981d5e87e08460e0d38b0c31696b89e11d35b55d62279` with
  preparation, codesign, provenance, and R0 PASS.
- Fresh 120-second evidence is at
  `build/native/boot-runtime/cadence/runs/m28-repeat-reset-20260822-120/120/`:
  `sourceAuthorityFailure=none`, `119.9999 Hz`, zero dropped ticks, zero
  renderer failures, and the Facility V7 frame at tick 4324 (`158/158` props,
  `1191` draws, scoped unsupported `0`, retained full-scene `0x38`). The old
  14370 boundary now remains mode 5 with blood visible; mode 6 follows only
  after the source continuation stream.
- Physical presentation remains unavailable (`presentedFPS=0` under the
  login-window session), and the post-fix Metal API/shader capture at
  `2026-08-22 06:19:43` remains an explicit `SKIP (Metal 4 device unavailable)`.

## 2026-08-22 RAMROM authority evidence retention continuation

- `NativeTitleOwner` now appends RAMROM authority/gameplay evidence instead of
  replacing the log on each fade/return marker. The full windowed Release run
  at `build/native/boot-runtime/cadence/runs/m28-ramrom-append-long-20260822-120/120/`
  retains packet `0/559`, `558/559`, `559/559`, and the next-cycle `0/559`.
- The same run retains all four V7 anchor submissions, reports
  `sourceAuthorityFailure=none`, logic `119.9997 Hz`, zero dropped/fatal debt,
  and zero renderer failures. Current Release SHA-256 is
  `ca09b6cb290ebb62f0874678a1dcabbf6278730beb62ec89e39d0c6f3de1af30`;
  provenance, codesign, and R0 pass.
- Presented timestamps/FPS remain unavailable in `loginwindow`; Metal 4
  capture remains an explicit device-unavailable SKIP.
