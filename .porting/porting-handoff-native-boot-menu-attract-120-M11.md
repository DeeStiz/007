# Native Boot/Menu/Attract/120 Hz — 2D/Adaptive Layout Handoff (M11)

## What was done

M11 2D/adaptive layout is complete for the bounded source UI path. Guarded
GETF/GETC/GETI packets, source font rows, icon and texture rectangles, fills,
scissors, File Select wallet/progress text, Mode Select rows, erase-confirmation
overlay, 440×330 source layout, reference 320×240 output, Faithful-HD scaling,
and inverse hit testing all pass. The File/Mode reference sequence was corrected
to reach the authored erase icon before selecting a completed wallet; no runtime
fallback or source coordinate stretch was introduced.

## Ground-truth validation

- `bash scripts/test_native_title_textures.sh` — PASS, 92 guarded GETT records
  and deterministic packet/hash/layout checks.
- `bash scripts/test_native_title_icons.sh` — PASS, 23,572 decoded RGBA8 bytes,
  hash/tamper/reserved-field checks.
- `bash scripts/test_native_title_nodes.sh` — PASS, four GETN packets with
  138 nodes and 92 texture rows.
- `bash scripts/test_native_title_raster_catalog.sh` — PASS, eight states,
  aggregate `11519430422207814888`.
- `bash scripts/test_title_reference_v5.sh` — PASS, 10,000 even-anchor
  comparisons and verified Cast→RAMROM transition.
- `bash scripts/test_file_mode_reference_capture_v6.sh build/native/source-frontend-v6`
  — PASS: wallet graph `90/42/982/765/84/186/2`, 42 metadata-authorized
  switch routes, blank/completed File Select packets, erase dialog, Mode rows,
  `reference=320x240 faithful-hd=1760x1320 unsupported=0`.

## Evidence boundary and deferred work

- This proves copied source UI/layout packets and deterministic coordinate
  contracts, not a physical visible-desktop screenshot or N64 pixel parity.
- Complete source UI material/font parity, interactive physical focus behavior,
  and sustained 120/60 presentation remain later acceptance gates.
- GPU capture remains deferred until the direct Metal 4 scene/compositor route
  is available on a capable host; no procedural UI fallback is promoted.

## Watch for next milestone

- Preserve 440×330 source coordinates and apply one adaptive transform at the
  output boundary. Keep inverse hit testing in source space.
- Keep File/Mode erase confirmation defaulting to Cancel and route state owned
  by the C authority; test cursor hit bounds against source constants.
- M12 audio parsing/synthesis work must retain source-clock timestamps and avoid
  realtime allocation or Swift calls in the audio callback.

## Reproduction

```sh
cd /Users/derek/Developer/goldeneye-swift
bash scripts/test_native_title_textures.sh
bash scripts/test_native_title_icons.sh
bash scripts/test_native_title_nodes.sh
bash scripts/test_native_title_raster_catalog.sh
bash scripts/test_title_reference_v5.sh
bash scripts/test_file_mode_reference_capture_v6.sh build/native/source-frontend-v6
```

No commit, push, branch, reset, clean, or external-ROM bundling was performed.
