# Native Boot/Menu/Attract/120 Hz — Demo Renderer Handoff (M27)

## State

M27 remains in progress. The V7 gameplay-camera packet path is source-scoped
and fail-closed: it lowers a non-identity camera, portal-visible room data,
and the admitted pad-backed static-prop subset for all seven source stages
while retaining the full-scene `0x38` character/AI/effects contract. Current
source packet strict/ASan/UBSan and Metal API/shader supplied-drawable harness
validation are green; canonical Release-app gameplay submission and the
remaining dynamic categories stay open.

The external ROM remains preparation-only:

`/Users/derek/Documents/GoldenEye 007 (USA).z64`

SHA-1: `abe01e4aeb033b6c0836819f549c791b26cfde83`

## Ground-truth validation

- `bash scripts/test_stage_gameplay_camera_packet_v7.sh
  build/native/stage-assets-image-decoder-v6
  build/native/ramrom-visible-dependencies-v6` — PASS strict/ASan/UBSan:
  Dam camera hash `17166107536987602611`, packet hash
  `4344127377687538898`, `28` environment commands, `197/197` props, and
  `1183` scene draws; Facility camera hash `9901855664259801205`, packet hash
  `2739797606600666455`, `48` environment commands, `267/267` props, and
  `1444` scene draws. Both scoped masks are `0x0`, retained full-scene mask is
  `0x38`, deterministic/fail-closed are `1/1`; the Dam dynamic fixture hashes
  are `2020772946810887752` and `17747242490227606699`.
- The all-14 reference-capture command was rebuilt with Metal API/shader
  validation but currently records
  `goldeneye_stage_gameplay_camera_reference_capture_v6_smoke: SKIP (Metal 4
  unavailable)`. Existing ignored checkpoint PNG/JSON/RAW artifacts remain
  under `build/native/stage-gameplay-camera-reference-capture-v6/` from the
  earlier Metal-capable run; they are retained artifacts, not a new current
  device claim.
- The earlier `test_stage_gameplay_camera_production_capture_v7.sh` attempts
  were clean Metal-4-unavailable SKIPs; the current 2026-08-22 run now passes
  all seven supplied-drawable stages after the source placement/raster fixes.
- `bash scripts/test_stage_environment_metal_reference_capture_v6.sh
  build/native/stage-assets-image-decoder-v6` — all seven current attempts
  record clean `SKIP (Metal 4 device unavailable)`. The harness now exits
  successfully for an all-unavailable run while still failing partial or
  unexpected results. Archived ignored captures remain under
  `build/native/stage-environment-metal-reference-capture-v6/`.
- M25/M26 scene/material/gameplay owner lanes remain green and continue to
  report static props only; no unsupported full-scene category is hidden.

## Seven-stage packet continuation

The V7 packet and production harness stage list is now all seven source stages
`33,34,35,9,20,26,25`. Strict/ASan/UBSan packet validation passes with
distinct deterministic hashes, scoped `unsupportedMask=0`, retained full-scene
`0x38`, and the narrowed source static-prop coverage `105/105`, `158/158`,
`43/43`, `59/59`, `54/54`, `78/78`, and `130/130`. The source placement
lowerer now carries checked-in model scale metadata and reconstructs runtime
ObjectRecord matrices from pad basis/position; collectable/ammo/monitor/
autogun/vehicle categories remain explicit diagnostics.

The Metal 4 supplied-drawable harness passes API/shader validation for all
seven stages with draw counts `363,648,203,201,279,654,298`. Raw hashes and
metadata are under `build/native/stage-gameplay-camera-production-capture-v7/`.
The raw SHA-256 values in stage order are
`d92c8a7706140fefc115586e4a999cb2356ae9f6c184865ce3612584befbba14`,
`ab86a02b3cfaaf37ea0f285393cc4df9d57b8967bc7b4e3aed6fba15dbf6e29`,
`a4bc1b5d0524890de0f285393cc4df13e5ae653ec336358fe50ca9d6e2d60091`,
`baa4ffc947f2858a771ae36dd1f40cdc7af299e34da5046df427f8e6eb902530`,
`e119c695f260fa565d9be5d15a4f3ff6cbf22d71746f1b4f04ca33562d1750c6`,
`7e0834597be1b6ab1b0c3a4f4b669d892d528c1d02bffe50e1e750c8d69f40ba`, and
`9d741b2755b518f69bb86ebed7d8fd87a1f29d607344685e462166fabc7c6cb8`.
The inspected trace is
`build/native/stage-gameplay-camera-production-capture-v7/gputrace/stage-all-seven.gputrace`;
`gpudebug` reports eight command buffers, seven source-scene render buffers,
640x480 BGRA8 plus Depth32Float attachments, and a representative 12-index
draw with two vertex buffers and a bound 64x64 RGBA8 texture. This validates
the production-shaped harness, not canonical Release-app cadence or N64 pixel
parity.

The canonical source-faithful Release was rebuilt after these source changes;
its executable SHA-256 is
`85a7c8f86abbba1709e30f5cc4689bf6ce1a59a22c941657729b1c1e262cd916`, with
Release history/provenance and R0 passing under the external-ROM boundary.

The refreshed compositor-independent environment captures also pass all seven
stages with `nonBlack=1` and `textured=1`. Source triangle/Metal draw counts
are `13982/2237`, `15481/2336`, `3298/868`, `5512/1411`, `28639/2575`,
`18757/2537`, and `10415/2090` in the same stage order; raw hashes are
`d558a4f3385d0776879db376b3f000dddd230f6676a6c1f49e6b59f133b7845f`,
`7f823ae5b8bc82046588cc9ff19b6547cae7eaeb86b88b206603c6a141f09dbd`,
`96d1cb504e328377ab6c150d3a0eb7e71fe47e2ac82743b1bc3f0fcfc91c19f1`,
`428b1ab1e67013e99ec4dd999b3edbf10a0a493ee1a4ef8a61381476321d5266`,
`72d6181dfbae662a6989f669e9abd7aba28499b427a5c8da100bad5e51d5b825`,
`4df37aa184a9a6e6cec34d6a6d7862868ba38f7e058b07f33016bd7e7ed78e9a`, and
`dc5f57a8ee510ec3b9780bce30294b3ee620abc2e50f38c2bf1930129514015a`.

## Evidence boundary and deferred work

- The V7 packet is not a full gameplay renderer. Do not clear `0x38`, bypass
  the product renderer guard, or treat an identity-camera composition as
  supplied-drawable proof.
- Metal validation, offscreen PNGs, and archived captures do not establish
  current physical presentation or N64 pixel parity. A Metal 4-capable host
  must rerun the reference and production commands, inspect a `.gputrace`, and
  verify raw output/scene draws before this gate can close.
- Characters, effects, AI, HUD, weapons, collision, sky, glass, and explosions
  remain explicit M26/M27 diagnostics.

## Watch for next milestone

- Preserve V7 camera/packet hashes, scoped/full-scene masks, prop counts, and
  dynamic-door source hashes while advancing M28 playback/acceptance.
- Keep any remaining Metal 4 SKIPs (reference/physical Release routes)
  visible and do not relabel archived captures as fresh production evidence.

## Reproduction

```sh
cd /Users/derek/Developer/goldeneye-swift
bash scripts/test_stage_gameplay_camera_packet_v7.sh \
  build/native/stage-assets-image-decoder-v6 \
  build/native/ramrom-visible-dependencies-v6
bash scripts/test_stage_gameplay_camera_reference_capture_v6.sh \
  build/native/stage-assets-image-decoder-v6 build/native/boot-assets \
  build/native/ramrom-visible-dependencies-v6
bash scripts/test_stage_gameplay_camera_production_capture_v7.sh \
  build/native/stage-assets-image-decoder-v6 \
  build/native/ramrom-visible-dependencies-v6
bash scripts/test_stage_environment_metal_reference_capture_v6.sh \
  build/native/stage-assets-image-decoder-v6
```

No commit, push, branch, reset, clean, or external-ROM bundling was performed.

## 2026-08-22 source-visible room-set continuation

- The V7 packet and production-capture harnesses now use the same copied
  current-room-plus-one-hop portal-neighbor room set as the owner camera
  adapter. This removes the prior one-room fixture mismatch without adding
  recursive PVS inference or changing the explicit static-prop-only scope.
- Updated packet strict/ASan/UBSan validation passes all seven stages. New
  packet metrics are Dam `28` commands/`363` draws, Facility `84`/`657`,
  Runway `513`/`270`, Bunker I `224`/`235`, Silo `344`/`279`, Frigate
  `2823`/`1144`, and Train `136`/`298`; scoped `unsupportedMask=0` and full
  scene `0x38` remain unchanged.
- Updated packet hashes in stage order `33,34,35,9,20,26,25` are
  `9691731936558540317`, `1361423520639327845`, `12839844755602817467`,
  `18348473008274347972`, `16691602544368876791`, `16956423305747631152`, and
  `6925925173978220218`. Dam's dynamic-door mutation remains deterministic
  with dynamic packet hash `1437994578478843349`.
- The current Metal production harness run records
  `SKIP (Metal 4 device unavailable)`, so the previous one-room supplied-
  drawable captures and `stage-all-seven.gputrace` are preserved as archived
  evidence only and must not be presented as current proof for this contract.

The next required M27 evidence remains a fresh Metal-4 supplied-drawable run,
inspected trace, and canonical Release reachability; characters, AI, effects,
HUD, weapons, collision, sky, glass, and explosions remain fail-closed.

## 2026-08-22 canonical Release stage-frame continuation

- The source authority/Gunbarrel/Cast reachability seam is now green through
  GoldenEye tick 3582, and the Release owner reaches RAMROM without clearing
  the paired authority or full-scene category mask.
- A clean signed Release run at
  `build/native/boot-runtime/cadence/runs/m23-cast-v7-freeze-20260822-120/120/`
  publishes a supplied-drawable Facility frame (demo 4, stage 34, tick 4324):
  room 68, 158/158 visible static props, 42 dynamic doors, 1,191 scene draws,
  camera packet hash `4171253561713628972`, composition hash
  `9008813320083006498`, scoped unsupported `0`, retained full-scene `0x38`.
  The archived `stage-gameplay-camera-owner.log` and
  `stage-gameplay-camera-renderer.log` are the direct Release evidence.
- The run has logic `119.9994 Hz`, zero dropped ticks, zero fatal debt, and
  zero renderer failures; presented timestamps/FPS remain unavailable under
  the login-window session. Metal-4 production/reference harnesses still SKIP
  on this host, so no current gputrace or physical presentation claim closes
  M27. The later tick-11298 source gap occurs after demo completion and does
  not invalidate the earlier submitted-drawable frame.

## 2026-08-22 source-anchor window continuation

- The opt-in V7 owner now publishes a bounded source-anchor window. The
  default is four frames spaced by 120 native ticks, with an in-flight queue
  guard, failure mailbox, append-only owner/renderer evidence, and queue drain
  at reset. Cast/SWITCH suppression and the scoped `props` contract remain
  unchanged.
- Independent Release runs pass with ticks `4324,4444,4564,4684`, identical
  camera/packet/environment/composition hashes, `158/158` props, `42` dynamic
  doors, `1191` draws, scoped unsupported `0`, and retained full-scene `0x38`.
  The final run reports `sourceAuthorityFailure=none`, logic `119.9982 Hz`,
  zero dropped/fatal debt ticks, and zero renderer failures.
- Evidence paths:
  `build/native/boot-runtime/cadence/runs/m27-anchor-window-spaced-20260822-30/120/`
  and `.../m27-anchor-window-spaced-repeat-20260822-30/120/`. Current signed
  Release SHA-256 is
  `aadf9c2bfcda56eef17ee5efa34b70271c5f87d3cd325be5d15704f5b12bc681`;
  preparation, codesign, provenance, and R0 pass.
- Adjacent-anchor bursts remain intentionally rejected by cadence evidence
  (`fatalDebtTicks=241`); do not reduce the interval or weaken the owner debt
  guard. Characters, AI, effects, HUD, weapons, collision, physical
  presentation, and Metal-4/gputrace acceptance remain deferred.
- A post-build Metal API/shader capture rerun at `2026-08-22 07:16:57` remains
  an explicit `SKIP (Metal 4 device unavailable)`.
- The latest diagnostic rerun at `2026-08-22 07:33:00` reports
  `MTLDevice unavailable device=nil`, so this CLI session cannot create a
  Metal capture device at all.
- The windowed 120-second Release run at
  `build/native/boot-runtime/cadence/runs/m27-anchor-window-long-windowed-20260822-120/120/`
  records the same four submissions, `sourceAuthorityFailure=none`, logic
  `120.0003 Hz`, zero dropped/fatal debt ticks, and zero renderer failures.
  Its `pass=0` result is solely the current login-window/no-presented-FPS
  boundary, not a source or renderer failure.
