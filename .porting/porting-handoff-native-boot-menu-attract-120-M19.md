# Native Boot/Menu/Attract/120 Hz — Gunbarrel Handoff (M19)

## What was done

M19 Gunbarrel is complete for the bounded source path. The prepared source
sidecar carries 24 animation clips and guard/standard-gun/gun-KF7 skeletons;
source attachment/root-motion/pose lowering, mode transitions, auxiliary
uniform lanes, blood acknowledgment, muzzle timing, and source projection
remain deterministic. Metal 4 temporal captures cover all admitted modes and
timer checkpoints under API/shader validation.

## Ground-truth validation

- `bash scripts/test_gunbarrel_v6.sh` — PASS strict/ASan/UBSan-side contracts:
  sidecar hash `f6e111996ae7f9beead512ac51bb5010bc804b74367eed4b03611b2fcab3f07d`,
  `24` clips, three skeletons, `42` blood frames, modes `2...9`.
- `bash scripts/test_gunbarrel_dynamic_builder_v6.sh` — PASS strict/sanitized
  dynamic scene builders for suitbond/headbrosnansuit/chrwppk with zero
  unsupported/fallback draws in the admitted fixtures.
- `bash scripts/test_gunbarrel_transition_projection_v6.sh` — PASS every-even-
  anchor exact projection, modes `2,3,4,5,6,7,8,9`, and source handoff.
- `GE_GUNBARREL_TEMPORAL_SWEEP=1 bash scripts/test_gunbarrel_metal_reference_capture_v6.sh`
  — PASS with Metal API/shader validation. Modes 2–9 and timers
  `40,50,100,136,137,152,168,169,212,230,348,400` capture successfully;
  mode 2 is `70` draws/`872` triangles, mode 5 and timer 230 are `71`/`874`.
- The mode-5 320×240 PNG was visually inspected and shows the source barrel,
  Bond, and blood/fade composition. Native output remains not an N64 pixel
  comparison.
- `bash scripts/test_title_route_v5.sh` — PASS strict/ASan/UBSan route and
  Cast/RAMROM integration.

## Evidence boundary and deferred work

- Sustained live owner cadence, complete N64 skeletal/weapon animation parity,
  audio timing, and physical visible-desktop presentation remain open.
- Dynamic builder and offscreen/Metal reference captures do not prove live
  supplied-drawable cadence or store acceptance.

## Watch for next milestone

- Preserve separate leading/trailing sight-ring lanes and non-aliasing auxiliary
  uniform records; do not collapse them into a shared constant.
- Keep the blood 42-frame handshake and mode-5→6 transition source guarded.
- M20 GoldenEye logo work must retain source two-cycle LOD/combiner state and
  reflection/material provenance.

## Reproduction

```sh
cd /Users/derek/Developer/goldeneye-swift
bash scripts/test_gunbarrel_v6.sh
bash scripts/test_gunbarrel_dynamic_builder_v6.sh
bash scripts/test_gunbarrel_transition_projection_v6.sh
GE_GUNBARREL_TEMPORAL_SWEEP=1 bash scripts/test_gunbarrel_metal_reference_capture_v6.sh
bash scripts/test_title_route_v5.sh
```

No commit, push, branch, reset, clean, or external-ROM bundling was performed.
