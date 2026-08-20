# Porting Handoff: Native Metal First Frame — M5

## Status

M5 first clear and presentation are complete. The raw CAMetalLayer drawable
contract is now exercised through Metal 4's queue-level API.

## Implemented

- Added `native/host/metal_clear_renderer.swift` with two-slot allocator/command
  reuse, shared-event waits/signals, explicit scene/layer residency, labeled
  clear render pass, and the ordered flow:
  `nextDrawable` → encode → `waitForDrawable` → commit → shared-event signal →
  `signalDrawable` → `present`.
- Added `scripts/test_m5_clear.sh` for Metal API/load/store validation and
  60-frame slot-reuse/retirement evidence.
- Added `scripts/capture_m5_clear.sh` and enabled an opt-in programmatic capture
  fallback behind `GOLDENEYE_M5_CAPTURE=1` plus `MTL_CAPTURE_ENABLED=1`.

## Validation evidence

Command: `scripts/test_m5_clear.sh` (GUI escalation)

- Signed SwiftPM app built and launched.
- Metal API validation, load-action validation, and store-action validation
  completed without a reported fault.
- `/tmp/goldeneye-m5-clear.log`: `frames=60 lastSignal=60`.
- The test-only NotificationCenter lifecycle probe recorded
  `focusLost reset=1 paused=1` followed by `focusGained paused=0` while still
  retiring 60 active frames. This proves the owner-loop pause gate, not a
  physical OS focus transition.
- Static source check confirmed the Metal 4 queue-level path and no legacy
  `presentDrawable`/Metal 3 command queue calls.

Command: `scripts/capture_m5_clear.sh` (GUI escalation)

- Preserved trace: `build/native/m5-clear.gputrace` (4.1 MB in the final
  macOS 27 capture).
- `strings` inspection found `GoldenEye.M5.Clear.Frame.0`,
  `GoldenEye.M5.Clear.RenderEncoder`, and `mtl4-command-queue` labels in the
  trace archive.
- `gpudebug` now successfully lists the M5 command buffer and render encoder,
  and `info color0` confirms the 960x540 BGRA8 clear/store attachment. Resource
  fetch remains unavailable while the background replayer reports an XPC
  interruption; the transcript is preserved in `build/native/m5-gpudebug.log`.

## Watch items for M6

- M6 must keep the M5 queue-level presentation and allocator/event retirement
  contract unchanged while adding only pipeline creation.
- Metal 4 pipeline descriptors use function descriptors and explicit compiler
  artifacts; do not fall back to Metal 3 render pipeline creation.
- The first pipeline may be created without submitting GBI geometry.

## Next milestone

`/porting-start-milestone m6` (automated continuation authorized for this task)
