# Native Boot/Menu/Attract/120 Hz — File Select Handoff (M21)

## What was done

M21 File Select is complete for the bounded source path. The C authority owns
four-folder selection, copy, erase, idle return, and Mode transition; Swift
receives value-only frames and SaveStore snapshots. The Wallet GESM SWITCH graph,
source text/icon/background packets, adaptive layout, and two-stage erase
confirmation use the authored source coordinates and default Cancel choice.

## Ground-truth validation

- `bash scripts/test_file_mode_v6.sh` — PASS strict/ASan/UBSan/paired Swift
  authority validation.
- `bash scripts/test_source_frontend_file_mode_integration_v6.sh build/native/source-frontend-v6`
  — PASS source frontend integration.
- `bash scripts/test_wallet_switch_text_v6.sh build/native/source-frontend-v6`
  — PASS strict/ASan, `wallet-switches=42`, source-order `43`, semantic hash
  `634483250829429547`.
- `bash scripts/test_file_mode_reference_capture_v6.sh build/native/source-frontend-v6`
  — PASS: wallet `90/42/982/765/84/186/2`, 42 branch routes, blank/completed
  surfaces, erase dialog, Mode rows, `reference=320x240 faithful-hd=1760x1320`
  and `unsupported=0`.
- `bash scripts/test_file_mode_background_v6.sh build/native/source-frontend-v6`
  — PASS background `440x299`, x-offset `-28`, source hash
  `b0704f2db5c0fc820050317a2848bba93b95dec4d37f6c1e040ffadb2bad8cf5`.
- `bash scripts/test_native_title_text.sh`, `bash scripts/test_native_title_icons.sh`,
  and `bash scripts/test_title_reference_v5.sh` — PASS shared text/icon/title
  reference contracts.

## Evidence boundary and deferred work

- Semantic/layout packets and headless authority tests do not prove physical
  mouse/controller interaction, active-display cadence, or N64 pixel parity.
- Full source save/UI parity, live visual presentation, and store acceptance
  remain open.

## Watch for next milestone

- Preserve source Wallet SWITCH order, branch metadata, and default erase
  Cancel behavior when adding Mode Select actions.
- Keep cursor hit testing in 440×330 source space and apply adaptive transforms
  only at output.
- M22 will need source availability/mode-selection authority and persistence
  validation without inventing multiplayer state.

## Reproduction

```sh
cd /Users/derek/Developer/goldeneye-swift
bash scripts/test_file_mode_v6.sh
bash scripts/test_source_frontend_file_mode_integration_v6.sh build/native/source-frontend-v6
bash scripts/test_wallet_switch_text_v6.sh build/native/source-frontend-v6
bash scripts/test_file_mode_reference_capture_v6.sh build/native/source-frontend-v6
bash scripts/test_file_mode_background_v6.sh build/native/source-frontend-v6
```

No commit, push, branch, reset, clean, or external-ROM bundling was performed.
