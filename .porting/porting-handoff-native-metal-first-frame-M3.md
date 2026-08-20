# Porting Handoff: Native Metal First Frame — M3

## Status

M3 keyboard input is complete. AppKit responder events now update a bounded
fixed-width keyboard state and submit copied snapshots to the M2 owner queue.

## Implemented

- Added `native/host/keyboard_input_state.swift` with layout-independent macOS
  virtual-key mappings, held/pressed/released edge accumulation, repeat
  suppression, modifier handling, sequence numbers, and deterministic reset.
- `GoldenEyeViewController` is a first responder and overrides `keyDown`,
  `keyUp`, and `flagsChanged` without forwarding unhandled keys to AppKit's
  beep path.
- `NSApplication.willResignActiveNotification` clears both the responder state
  and the owner queue's pending snapshot, preventing stuck keys after focus loss.
- Added `native/tests/keyboard_input_smoke.swift` and
  `scripts/test_m3_input.sh` for pure-state edge/reset coverage.

## Validation evidence

- `scripts/test_m3_input.sh` passed all key, repeat, modifier, unknown-key,
  edge-consumption, sequence, and reset assertions.
- `scripts/test_m3_gui_events.sh` passed the AppKit `sendEvent` responder path
  for W key down/up and recorded the deactivate/activate probe. This GUI session
  did not emit OS focus notifications; pure-state reset remains authoritative.
- `scripts/build_m2_app.sh` rebuilt the SwiftPM host with the M3 responder path.
- GUI-escalated `scripts/test_m2_app.sh` passed after M3 integration; the signed
  app launched and recorded `initialized=1 ticks=60 shutdown=0`.
- The C ABI remains unchanged and continues to be covered by the M1 ASan/UBSan
  and layout smoke suite.

## Watch items for M4

- Keep input snapshots immutable when handing them to the Metal owner loop.
- Do not add drawable acquisition or presentation in the device-capability
  milestone; M5 owns that contract.
- Preserve the M1 owner-thread rule for all future Metal object mutation.

## Next milestone

`/porting-start-milestone m4` (automated continuation authorized for this task)
