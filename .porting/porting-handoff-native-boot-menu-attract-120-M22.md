# Native Boot/Menu/Attract/120 Hz — Mode Select Handoff (M22)

## What was done

M22 Mode Select is complete for the bounded source path. Solo and multiplayer
  rows use source controller-count gating, previous-tab/back behavior and
  selected-wallet persistence. The Wallet SWITCH/material graph is lowered into
  selected-wallet scene packets and rendered through the same source Metal 4
  scene/2D compositor used by File Select. The release-consumable image-decoder
  asset root is required; the legacy root contains black diagnostic wallet rows
  and is not valid current evidence.

## Ground-truth validation

- `bash scripts/test_file_mode_v6.sh` — PASS strict/ASan/UBSan/paired authority.
- `bash scripts/test_wallet_switch_text_v6.sh build/native/source-frontend-v6`
  — PASS strict/ASan, 42 switches, source order 43, semantic hash
  `634483250829429547`.
- `GE_FILE_MODE_CAPTURE_RUN_ID=m22-final bash scripts/test_file_mode_metal_reference_capture_v6.sh build/native/source-frontend-v6-image-decoder-v6`
  — PASS Metal API/shader validation. Solo/multiplayer selected-wallet scenes
  are non-black; reference draw/triangle count is `12/47`. Faithful-HD and
  adaptive-widescreen offscreen captures pass with deterministic hashes. File
  Select 3D is `32` draws/`112` triangles; source 2D background is `299` rows.
- `bash scripts/test_file_mode_reference_capture_v6.sh build/native/source-frontend-v6`
  — PASS semantic File/Mode frames, erase overlay, and layout evidence.
- `bash scripts/test_source_frontend_file_mode_integration_v6.sh build/native/source-frontend-v6`
  — PASS source authority integration.
- `bash scripts/test_native_title_text.sh`, `bash scripts/test_native_title_icons.sh`,
  and `bash scripts/test_title_reference_v5.sh` — PASS shared text/icon/title
  route contracts.

## Evidence boundary and deferred work

- The Metal capture is native source-semantic evidence, not N64 pixel parity or
  physical interactive UI acceptance.
- Complete multiplayer gameplay parity, physical controller/mouse interaction,
  sustained presentation, and store acceptance remain open.
- Do not use legacy `build/native/source-frontend-v6` for current release visual
  claims; use the image-decoder root or regenerate guarded assets.

## Watch for next milestone

- Preserve selected-wallet material linkage and controller-count gating when
  entering Cast. Keep source route/back behavior separate from gameplay.
- M23 Cast work will need character attachment, texture/render-mode, Metal
  capture, and live supplied-drawable evidence boundaries.

## Reproduction

```sh
cd /Users/derek/Developer/goldeneye-swift
bash scripts/test_file_mode_v6.sh
bash scripts/test_wallet_switch_text_v6.sh build/native/source-frontend-v6
GE_FILE_MODE_CAPTURE_RUN_ID=m22-final bash scripts/test_file_mode_metal_reference_capture_v6.sh build/native/source-frontend-v6-image-decoder-v6
bash scripts/test_file_mode_reference_capture_v6.sh build/native/source-frontend-v6
bash scripts/test_source_frontend_file_mode_integration_v6.sh build/native/source-frontend-v6
```

No commit, push, branch, reset, clean, or external-ROM bundling was performed.
