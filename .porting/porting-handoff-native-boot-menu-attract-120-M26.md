# Native Boot/Menu/Attract/120 Hz — Demo Gameplay Core Handoff (M26)

## State

M26 remains in progress. The bounded source gameplay owners now exercise all 14
RAMROM routes with fixed-point player/camera, pad and room/portal traversal,
door lifecycle, guard/weapon source pages, non-model visuals, weapon/effect
integration, deterministic 120 Hz stepping, and abort/restore. Dynamic
character/AI/effect/weapon scene promotion remains fail-closed: the gameplay
owners report `sourceReady=0` and the dynamic-scene readiness matrix does not
claim a presentable frame.

The external ROM remains preparation-only:

`/Users/derek/Documents/GoldenEye 007 (USA).z64`

SHA-1: `abe01e4aeb033b6c0836819f549c791b26cfde83`

## Ground-truth validation

- `bash scripts/test_ramrom_gameplay_v6.sh
  build/native/stage-assets-image-decoder-v6 build/native/boot-assets
  build/native/ramrom-visible-dependencies-v6` — PASS strict/ASan/UBSan:
  seven stages, 14 recordings, 14 route pages, `damEntities=238`,
  `sidecarComplete=1`, `sourceReady=0`, `runtimeInstall=1`.
- `bash scripts/test_ramrom_gameplay_player_camera_v7.sh` — PASS strict,
  ASan, UBSan: `layout=176`, `direct=2`, `eventHash=1`.
- `bash scripts/test_ramrom_dynamic_scene_v6.sh` — PASS strict/ASan/UBSan:
  `routes=14`, missing readiness matrix `14`, fixture-only composition `1`,
  ordered elements `9`. The harness required its complete source dependency
  list; that list is now explicit and no gameplay fallback was added.
- `bash scripts/test_ramrom_gameplay_orchestrator_v6.sh
  build/native/stage-assets-image-decoder-v6 build/native/boot-assets
  build/native/ramrom-visible-dependencies-v6` — PASS strict/ASan/UBSan:
  `demos=14`, `runs=28`, aggregate `3432588557158677409`, `dam1Moved=1`,
  `environmentDynamicDoors=4`, `dynamicRestore=1`, `restore=1`.
- `bash scripts/test_ramrom_guard_door_pages_v6.sh
  build/native/stage-assets-image-decoder-v6
  build/native/ramrom-visible-dependencies-v6` — PASS strict/ASan/UBSan:
  `guards=623`, `doors=397`, `transformedDoors=152`, `weaponChoices=543`,
  `poseRows=5104`, `resolvedPortalRows=397`, `uniquePortals=67`, portal hash
  `13325078266282593292`; AI/pose/weapon evidence remains source-page
  diagnostics and `sourceReady=0`.
- `bash scripts/test_ramrom_gameplay_weapon_effect_integration_v6.sh
  build/native/boot-assets` and `bash scripts/test_weapon_effect_owner_v6.sh
  build/native/ramrom-visible-dependencies-v6` — PASS strict/ASan/UBSan,
  `install=1`, `paired=1`, `entities=3`, missing categories fail-closed;
  source owner reports 14 demos, odd interpolation and one-shot coverage.
- `bash scripts/test_ramrom_non_model_authority_v6.sh build/native/boot-assets
  build/native/ramrom-visible-dependencies-v6` — PASS strict/ASan/UBSan:
  14 demos/28 runs, `samples=20465`, `skyFrames=40944`, `fadeFrames=14`,
  aggregate `16086702808210831681`.
- `bash scripts/test_ramrom_non_model_visuals_v6.sh
  build/native/ramrom-visible-dependencies-v6` — PASS strict/ASan/UBSan:
  dependencies `178`, payloads `173`, semantic records `5`, missing categories
  `9`, composition hash `6353911455530622628`.
- `bash scripts/test_stage_gameplay_runtime.sh
  build/native/stage-assets-image-decoder-v6` — PASS strict/ASan/UBSan:
  demo-1 Dam trace `1578` samples, aggregate `4774828755625742329`, with
  explicit `effects,ai,weapons,collision` diagnostics.

## Evidence boundary and deferred work

- These are deterministic source-owner and fail-closed composition contracts,
  not complete gameplay parity, character animation/attachment rendering, or
  physical 120 Hz acceptance.
- The dynamic-scene matrix requires gameplay/player-camera/guard-door/
  weapon-effect snapshots, intro item mapping, complete sidecars, pose pages,
  and effect pages before it can be presentable. Do not manufacture those
  records from setup rows or clear the `0x38` renderer mask.
- M27 still requires a Metal 4 Release supplied-drawable gameplay capture and
  inspected trace for the scoped room/static-prop route; character/effect/AI/
  HUD/weapon categories remain open.

## Watch for next milestone

- Preserve all-14 route ordering, source-anchor/odd interpolation hashes,
  dynamic door restore, portal lifecycle, and explicit missing-category
  diagnostics while advancing M27.
- Keep the corrected image-decoder stage root and full-weapons/source roots;
  do not use legacy asset roots or bundle the external ROM.

## Reproduction

```sh
cd /Users/derek/Developer/goldeneye-swift
bash scripts/test_ramrom_gameplay_v6.sh \
  build/native/stage-assets-image-decoder-v6 build/native/boot-assets \
  build/native/ramrom-visible-dependencies-v6
bash scripts/test_ramrom_gameplay_player_camera_v7.sh
bash scripts/test_ramrom_dynamic_scene_v6.sh
bash scripts/test_ramrom_gameplay_orchestrator_v6.sh \
  build/native/stage-assets-image-decoder-v6 build/native/boot-assets \
  build/native/ramrom-visible-dependencies-v6
bash scripts/test_ramrom_guard_door_pages_v6.sh \
  build/native/stage-assets-image-decoder-v6 \
  build/native/ramrom-visible-dependencies-v6
bash scripts/test_ramrom_gameplay_weapon_effect_integration_v6.sh \
  build/native/boot-assets
bash scripts/test_weapon_effect_owner_v6.sh \
  build/native/ramrom-visible-dependencies-v6
bash scripts/test_stage_gameplay_runtime.sh \
  build/native/stage-assets-image-decoder-v6
```

No commit, push, branch, reset, clean, or external-ROM bundling was performed.

## 2026-08-22 current character-owner audit

- Fresh `test_ramrom_character_owner_export_v6.sh` passes strict/ASan/UBSan
  for the anchor/midpoint owner contract, retaining `missingFields=28`.
- Fresh `test_ramrom_character_scene_v6.sh` passes strict/ASan/UBSan across
  all 14 demos and seven stages, but every character row remains explicitly
  fail-closed (`animation=0`, `attachments=0`, and missing animation pose,
  attachment-switch, and `ModelRenderData` fields). Head selection remains
  deterministic and source-owned.
- This audit found no complete source-authoritative ChrRecord/AI/effect page
  set to lower next. Do not classify setup character rows as gameplay-owned
  animation or clear the M26/M27 unsupported categories; the next valid lane
  still requires those copied source pages and render-context contracts.
