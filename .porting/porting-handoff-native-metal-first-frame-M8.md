# Porting Handoff: Native Metal First Frame — M8

## Status

M8 vertex drawing is complete. The normalized M7 packet now produces a visible
colored triangle through Metal 4 argument-table and residency bindings.

## Implemented

- Added `native/host/metal_triangle_renderer.swift`, which consumes
  `ge_native_normalize_gbi(ge_native_gbi_fixture_stream())`, converts the copied
  fixed-width vertices to a shared transient-style GPU buffer, adds it to the
  committed scene residency set, binds its GPU address at argument-table index 0,
  and issues exactly one labeled triangle draw per frame.
- Added explicit `GoldenEye.M8.Triangle.VertexBuffer`,
  `GoldenEye.M8.Triangle.RenderEncoder`, and `GoldenEye.M8.Triangle.Draw.0`
  labels for capture correlation.
- Added app-specific CoreGraphics window capture helper so screenshots target
  the actual window even when the GUI runtime places it on a secondary display.
- Added `scripts/test_m8_triangle.sh` and `scripts/capture_m8_triangle.sh`.

## Validation evidence

Command: `scripts/test_m8_triangle.sh` (GUI escalation)

- Metal API and shader validation launch passed.
- Runtime evidence: `frames=60 draws=60 packetHash=1522029846112142469
  lastSignal=60`.
- Two consecutive actual-window screenshots were byte-identical.
- Stable screenshot SHA-256 from the active-screen capture rerun:
  `9fef700b607853da79c154c28467b53d5c13d9cf1276ecb0b4539fc0e1e00265`.
- Visual inspection of `build/native/m8-triangle-a.png` shows the expected
  interpolated red/green/blue triangle on the dark clear background.

Command: `scripts/capture_m8_triangle.sh` (GUI escalation)

- Preserved trace: `build/native/m8-triangle.gputrace` (2.1 MB).
- Static archive inspection found the labeled MTL4 triangle frame, vertex buffer,
  render encoder, draw group, and `mtl4-command-queue` entries.
- `gpudebug` now successfully inspects the M8 command tree and draw: one command
  buffer, one render encoder, one triangle draw, the M6 pipeline and entry
  points, the 96-byte vertex buffer, and the 960x540 BGRA8 attachment are all
  recorded in `build/native/m8-gpudebug.log`. Resource fetch still encounters
  an XPC interruption while the replayer loads.

## Watch items for M9

- M9 must separate deterministic replay, sanitizer, leaks, HUD/resource
  stability, resize/shutdown, screenshot, and trace-inspection evidence.
- Keep the M8 screenshot/pixel hash as a regression fixture, but do not claim
  N64 visual parity from this synthetic triangle.
- The M0 N64 byte-match gap remains external-toolchain evidence, not a reason to
  weaken the native first-frame acceptance boundaries.

## Next milestone

`/porting-start-milestone m9` (automated continuation authorized for this task)
