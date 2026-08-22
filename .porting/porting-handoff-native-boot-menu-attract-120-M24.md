# Native Boot/Menu/Attract/120 Hz — Native Platform Services Handoff (M24)

## State

M24 remains in progress, with the safe scheduler-independent foundation now
explicitly covered. The stage catalog validates the guarded 21-resource root,
1172/RZIP decode and digest contract, C metadata packet copy-out, decoded-arena
views, and a pointer-free load/activate/deactivate/unload lifecycle. Full
platform replacement, streaming/DMA scheduling, gameplay ownership, and
renderer resource lifecycle remain deferred and fail-closed.

The external ROM remains preparation-only:

`/Users/derek/Documents/GoldenEye 007 (USA).z64`

SHA-1: `abe01e4aeb033b6c0836819f549c791b26cfde83`

## Ground-truth validation

- `bash scripts/test_stage_v5.sh` — PASS strict and ASan/UBSan C catalog,
  seven stages.
- `bash scripts/test_stage_asset_catalog.sh
  build/native/stage-assets-image-decoder-v6` — PASS strict/ASan, malformed
  manifest guard, seven stages/21 resources. Catalog hash is
  `16694764706485246250`; the current per-stage hashes are retained in
  `build/native/stage-asset-catalog/stage-asset-catalog.log`.
- `bash scripts/test_stage_resource_loader.sh
  build/native/stage-assets-image-decoder-v6` — PASS `packets=21`, `views=21`,
  deterministic partial copy-out status `2`, first arena base `4096`, last
  base `1938928`.
- `bash scripts/test_stage_background_v5.sh
  build/native/stage-assets-image-decoder-v6/background` — PASS strict and
  ASan/UBSan for all seven background payloads.
- `bash scripts/test_stage_setup_packet.sh
  build/native/stage-assets-image-decoder-v6` — PASS strict/ASan/UBSan:
  `objects=2225`, `pads=2230`, `portals=612`, malformed packet cases fail
  closed.
- `bash scripts/test_stage_scene_packet.sh
  build/native/stage-assets-image-decoder-v6` — PASS seven stages, 468 rooms,
  `payload_bytes=2016864`, packet hash `13284805027105908470`.
- `bash scripts/test_stage_lifecycle_v6.sh
  build/native/stage-assets-image-decoder-v6` — PASS strict/ASan/UBSan:
  `stages=7`, decoded arena `2016864` bytes, deterministic resource-view
  hash `15083698972971979799`, lifecycle state hash
  `360802037447672111`, and active-reset/double-load/unload transitions fail
  closed.
- `NativeTitleOwner.prepareStageScene` now owns the same lifecycle in the
  production preparation path: the selected stage transitions to `active`, a
  previous active stage is deactivated/unloaded before replacement, and game
  reset explicitly releases the active lifecycle. Owner/source-selection/runtime
  guards and the SwiftPM debug build pass after this integration.

## Evidence boundary and deferred work

- `GoldenEyeStageLifecycleV6` is metadata/arena ownership only. It retains no
  payload pointer or byte buffer and does not manufacture a DMA scheduler,
  gameplay state, Metal resource, or unsupported scene category.
- The legacy C `STUB(M24)` status remains an explicit diagnostic for the
  unimplemented broader platform service replacement. Do not relabel this
  bounded lifecycle smoke as full native stage execution.
- The corrected image-decoder root is required for current evidence;
  `build/native/stage-assets` is legacy preparation output and may fail the
  `resource_count=21`/`manifest_status=PASS` guard.

## Watch for next milestone

- M25 can consume the lifecycle snapshots while preserving asset handles,
  decoded offsets, source/decoded hashes, and stage ordering.
- Keep C ABI layouts frozen, payload ownership caller-bound, and the external
  ROM untracked. Do not clear M26/M27 stubs or broaden the renderer route.

## Reproduction

```sh
cd /Users/derek/Developer/goldeneye-swift
bash scripts/test_stage_v5.sh
bash scripts/test_stage_asset_catalog.sh build/native/stage-assets-image-decoder-v6
bash scripts/test_stage_resource_loader.sh build/native/stage-assets-image-decoder-v6
bash scripts/test_stage_background_v5.sh build/native/stage-assets-image-decoder-v6/background
bash scripts/test_stage_setup_packet.sh build/native/stage-assets-image-decoder-v6
bash scripts/test_stage_scene_packet.sh build/native/stage-assets-image-decoder-v6
bash scripts/test_stage_lifecycle_v6.sh build/native/stage-assets-image-decoder-v6
```

No commit, push, branch, reset, clean, or external-ROM bundling was performed.

## 2026-08-22 payload-service continuation

- Added `GoldenEyeStagePayloadStoreV6`, a scheduler-independent owner for the
  decoded bytes of one active prepared stage. It loads the corrected catalog's
  three decoded resources on explicit activation, rechecks decoded size and
  SHA-256, exposes bounded fixed-width range reads, and rejects stale,
  overflowing, oversized, replacement, active-unload, and reset transitions.
- `NativeTitleOwner` now creates the payload store with the existing stage
  lifecycle and activates/deactivates/unloads the same stage ID. The renderer
  and gameplay/category masks are unchanged; payload ownership does not claim
  stage execution or visual parity.
- `bash scripts/test_stage_payload_store_v6.sh
  build/native/stage-assets-image-decoder-v6` passes strict/ASan/UBSan:
  `stages=7`, `resources=3`, first-stage aggregate `8556576272295209170`,
  all-stage aggregate `15436731694462652841`,
  `singleActive=1`, `rangeGuard=1`, `digestGuard=1`, `reset=1`.
- `CLANG_MODULE_CACHE_PATH=/tmp/goldeneye-clang-module-cache swift build
  --disable-sandbox --configuration debug --product GoldenEyeHost` and
  `bash scripts/test_engine_owner_runtime.sh` pass after the integration.

This continuation still does not implement an N64 scheduler/DMA queue or
promote the canonical Release stage route. The active Release blocker remains
the paired Gunbarrel model-result timing before Cast/V7, followed by the
login-window/Aqua presentation boundary.

## 2026-08-22 source-route continuation

- The paired Gunbarrel blocker is resolved source-faithfully: the hosted blood
  oracle completes after 41 continuations, the renderer latches the completion
  mailbox, and source Cast/return transitions remain paired. The large guard
  owner is heap-backed and the selected RAMROM route is prewarmed before the
  cadence loop.
- Final canonical Release evidence reaches demo 4 / Facility stage 34 at
  tick 4324 with a supplied-drawable V7 frame (`158/158` props, `1191` draws,
  scoped unsupported `0`, retained full-scene `0x38`) and completes packet
  `559/559`. The final Release hash is
  `289a98e3173fd3770ff081f3ef54d20310c63883a530ab2d7bcbc22bd5de6e0e`.
- Physical presented FPS remains unavailable in the login-window session;
  current Metal-4 capture attempts still SKIP. The bounded full loop now
  remains paired through the repeated Gunbarrel return after the source blood
  state reset.

## 2026-08-22 bounded file-index and transfer-queue continuation

- Added `GoldenEyeStageFileIndexV6`, a deterministic value-only index for all
  seven corrected stage families and their 21 prepared resources. Rows retain
  source/decoded ranges, compression, handles, and verified digests without
  opening the external ROM or carrying a pointer/file descriptor.
- Added `GoldenEyeStageTransferQueueV6` over the active
  `GoldenEyeStagePayloadStoreV6`. The queue has fixed pending/chunk limits,
  deterministic request IDs and completion order, caller-owned copied bytes,
  and explicit guards for no-active-stage, cross-stage, out-of-range,
  overflow, replay, pending replacement, and reset transitions. It is a
  scheduler-independent transfer contract, not a claim of a ported N64 DMA
  scheduler.
- `bash scripts/test_stage_transfer_queue_v6.sh
  build/native/stage-assets-image-decoder-v6` passes strict/ASan/UBSan:
  `stages=7`, `entries=21`, `fileIndexHash=12969746555383168713`, three
  completed requests, `transferHash=16820286361146389937`, and
  `singleActive=1 rangeGuard=1 queueGuard=1 reset=1`.
- `CLANG_MODULE_CACHE_PATH=/tmp/goldeneye-clang-module-cache swift build
  --disable-sandbox --configuration debug --product GoldenEyeHost`,
  `CLANG_MODULE_CACHE_PATH=/tmp/goldeneye-clang-module-cache bash
  scripts/test_engine_owner_runtime.sh`, the source boot-route smoke,
  payload-store/lifecycle smokes, and the source-faithful Release build pass.
  Current Release executable SHA-256 is
  `0738a1202ea27a5949fb7fe10e1889d5c7d27f53ed634d5594ab81f61d535f33`;
  Release history/provenance, codesign, bundle guards, and R0 pass.
- The C `STUB(M24)` remains explicit for the broader platform replacement;
  no gameplay/renderer mask or V7 opt-in behavior changed. The fresh Metal-4
  production harness remains `SKIP (Metal 4 device unavailable)`, stale
  ignored GPU artifacts remain non-current, and physical presented cadence is
  still blocked by the login-window session.

## Reproduction addition

```sh
cd /Users/derek/Developer/goldeneye-swift
bash scripts/test_stage_transfer_queue_v6.sh build/native/stage-assets-image-decoder-v6
```

## 2026-08-22 source-catalog parity continuation

- `GoldenEyeStageFileIndexV6` now checks every Swift row against the C
  `ge_stage_v5_resource_packet` stream and `ge_stage_v5_find_stage` identity
  before constructing `GoldenEyeStageTransferQueueV6`. Rows are emitted in
  C/RAMROM order (`33,34,35,9,20,26,25`), and a public catalog drift fails
  closed with `sourceCatalogMismatch`.
- The transfer smoke's negative tamper case and strict/ASan/UBSan runs pass:
  `fileIndexHash=14890358892990385005`,
  `transferHash=16820286361146389937`, three completed requests, and
  `sourceParity=1`. Loader (`packets=21 views=21`), payload-store, lifecycle,
  debug host, and engine-owner checks pass.
- Fresh signed Release executable SHA-256:
  `425ee3d6f88d86b3318a61fc80ef12175f3c9153621914fa34e99cdb6d95e635`.
  Preparation, Release history/provenance, codesign, bundle guards, and R0
  pass. The C `STUB(M24)`, V7 opt-in, full-scene `0x38`, and gameplay masks
  remain unchanged. Production Metal API/shader capture at `2026-08-22
  07:51:38` is an explicit `SKIP (MTLDevice unavailable device=nil)`;
  physical presentation remains unproven.

## 2026-08-22 transfer-backed scene-owner continuation

- `GoldenEyeStageScenePacket.loadAll` now has a transfer-backed path that
  activates one stage in C file-index order, completes three bounded requests,
  parses the copied bytes with the existing C background/setup routines, and
  unloads the stage. Direct and transfer-backed packets compare equal:
  `stages=7`, `rooms=468`, `payload_bytes=2016864`, hash
  `13284805027105908470`, `transferRequests=21`, and transfer hash
  `13486978902238770849`.
- `NativeTitleOwner` owns the transfer queue for preparation, stage
  replacement, activation, and reset. The queue remains synchronous and
  scheduler-independent; C `STUB(M24)` and all gameplay/renderer masks remain
  explicit.
- Fresh signed Release owner route:
  `build/native/boot-runtime/cadence/runs/m24-transfer-owner-final-20260822-50/120/`
  records anchors `4324,4444,4564,4684`, Facility `158/158` props, `1191`
  draws, scoped `0`, full-scene `0x38`, zero dropped/fatal/renderer failures,
  and `sourceAuthorityFailure=none`. The signed executable SHA-256 is
  `28a7aef35302c753aec800db6f1c61a7b3a2a5fea9dace950e95114edc226d61`;
  provenance, codesign, bundle, and R0 pass. Physical presented cadence is
  still unavailable, and Metal capture remains `SKIP (MTLDevice unavailable
  device=nil)`.

## 2026-08-22 chunked transfer and RZIP bridge continuation

- The transfer-backed scene path now uses a bounded 64 KiB chunk limit and
  reassembles each resource from sequential queue requests. Direct/transfer
  equality remains `468` rooms, `2016864` bytes, packet hash
  `13284805027105908470`; strict/ASan/UBSan reports `44` requests and
  transfer hash `10384286454254812603`.
- `GoldenEyeStageAssetCatalog` now routes compressed 1172 rows through
  `ge_stage_v5_decompress_1172` with a borrowed no-capture Apple Compression
  callback. Catalog strict/ASan/UBSan preserves hash
  `16694764706485246250`; C `STUB(M24)` and renderer/gameplay masks remain.
- Fresh signed Release SHA-256:
  `759a84bf47bfe37870942474b8ce01314d1f453e014f5fe61187fec02f14c869`.
  Owner evidence at
  `build/native/boot-runtime/cadence/runs/m24-rzip-chunked-20260822-45/120/`
  records four V7 anchors, `sourceAuthorityFailure=none`, zero dropped/fatal/
  renderer failures, and logic `120.0024038 Hz`. Metal capture and physical
  presentation remain unavailable.
