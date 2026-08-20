# Porting Handoff: Native Metal First Frame — M2

## Status

M2 AppKit host is complete. The host app remains render-capability-unpublished:
it creates a raw layer and window, but does not create a Metal device or present
a drawable until M4/M5.

## Implemented

- Added SwiftPM package scaffolding with an isolated `GoldenEyeNative` C target
  and `GoldenEyeHost` executable target.
- Added `native/host/main.swift` with an AppKit `NSWindow`, `NSView` whose
  `makeBackingLayer()` returns a raw `CAMetalLayer`, backing-scale/drawable-size
  updates, and a dedicated owner queue that calls the M1 value-only C lifecycle.
- Added `scripts/build_m2_app.sh` to build with SwiftPM, stage a normal `.app`
  bundle, set the macOS 27 minimum/category metadata, and development-sign/
  verify it with the installed Apple Development identity.
- Added `scripts/test_m2_app.sh` for bundle metadata/signature checks and real
  GUI launch verification.

## Validation evidence

Command: `scripts/test_m2_app.sh` (run with GUI escalation because the sandbox
cannot register AppKit/LaunchServices applications)

- SwiftPM debug build passed.
- `.app` bundle passed `codesign --verify --deep --strict`.
- LaunchServices opened the signed bundle and a live `GoldenEyeHost` process was
  observed.
- `/tmp/goldeneye-m2-owner-loop.log` reported `initialized=1 ticks=60
  shutdown=0`, proving the owner queue advanced the bounded C lifecycle and
  shut down cleanly.
- `codesign -dvvv` reports `Authority=Apple Development: Derek Stiles
  (RWSPYS288D)`, Team ID `KV5KQJ3LLD`; `otool -l` reports Mach-O `minos 27.0`,
  aligned with `LSMinimumSystemVersion=27.0`.
- An initial pre-fix launch crash was diagnosed from the crash report as the
  view lacking `wantsLayer`; the fixed runtime pass completed without a new
  crash and the raw-layer assertion is now guarded by `makeBackingLayer`.

## Watch items for M3

- Keep keyboard state on the AppKit main/responder side and transfer only a
  copied fixed-width snapshot to the owner queue.
- Focus loss must clear held and pending edges before the next owner tick.
- Do not publish Metal capability or introduce drawable presentation in M3.

## Next milestone

`/porting-start-milestone m3` (automated continuation authorized for this task)
