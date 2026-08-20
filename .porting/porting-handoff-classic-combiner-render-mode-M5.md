# Porting Handoff: Classic Combiner and Render-Mode Lowering — M5

## Status

The `classic-combiner-render-mode` goal is complete. Preparation, execution,
validation, and handoff were run autonomously with Luna-max workers. No
commit, push, branch, reset, clean, or unrelated cleanup was performed.

## What Was Done

- Corrected the source contract to the canonical ammo-crate `ModelType = 4`.
  The source setup is the normal `modelApplyRenderModeType4` path: two-cycle
  `TRILERP`/`MODULATEIA2` (`FC26A004 1F1093FF`) with primary mode
  `C4112078`; the authored list changes to `C4104DD8` for the final two
  texture groups.
- Added the fixed-width V4 sidecar ABI in
  `native/include/ge_classic_combiner.h` and its C-authoritative lowerer in
  `native/src/ge_classic_combiner.c`. It checks classic partial other-mode
  updates, decodes two combiner cycles and render/blender fields, rejects
  malformed/unsupported words, and never changes V1/V2/V3 records.
- Added deterministic C and Swift smoke tests. Four V4 draw keys are emitted
  at offsets `0x50`, `0x68`, `0x90`, and `0xb0` for textures `0x21`, `0x21`,
  `0x27`, and `0x25`.
- Added `GoldenEyeClassicCombinerProp.metal` and the Metal 4 consumer
  `metal_classic_combiner_prop_renderer.swift`. The bounded shader aliases
  TEXEL1 to TEXEL0 for this one-texture fixture, applies the captured
  TRILERP/MODULATEIA2 expression, and the renderer selects labeled opaque and
  authored blend pipeline variants through argument tables and one render
  pass. Depth, fog, alpha compare, and coverage remain explicit deferred
  fields.
- Integrated the V4 source into SwiftPM, the AppKit host, the MTL4 capture
  path, and the M12 build/test harnesses.

## Deterministic Evidence

### Frozen lanes

- V1 packet: `1522029846112142469`
- V2 packet/event/state: `65363635960931316`, `905714786767796339`,
  `10439205544326414085`
- V3 packet/event/material: `11580554792388204033`,
  `9845751795158270468`, `14168780479827987350`
- M11 screenshot SHA-256 remains
  `fbc8fc7de88a3a24141281edb7bf4c866241449dafd8673f9a35d19de89e223c`.

### V4 lowering

`scripts/test_classic_combiner_replay.sh` passes normal repeated C output,
ASan/UBSan, Swift layout/malformed lanes, and all frozen hash checks.

```text
setupHash=6213740136672363482
eventHash=5747731189711370311
keyHash=16733630809188353388
draws=4 offsets=0x50/0x68/0x90/0xb0
modes=0xc4112078/0xc4112078/0xc4104dd8/0xc4104dd8
```

### Runtime and Metal 4

`scripts/test_m12_classic_combiner.sh` passes with a signed macOS 27 bundle,
Metal API and shader validation enabled:

```text
status=0 loweringStatus=0 replayStatus=0 commands=24 propCommands=22 setupCommands=3
drawPackets=4 vertices=40 triangles=20
frames=60 draws=240 uploadsPending=false lastSignal=60 resourceAllocations=6
```

Artifacts:

- `build/native/m12-runtime.log`
- `build/native/m12-runtime-resize.log`
- `build/native/m12-classic-combiner.png`
- `build/native/m12-pixel.sha256` (`5b1bbc71d09c1b2334c2771d90fa293c7ffb339a63500bb94f35d002b05d45d0`)
- `build/native/m12-classic-combiner.gputrace`
- `build/native/m12-gpudebug.log`
- `build/native/m12-validation.log`
- `build/native/m12-leaks.log` (`0 leaks for 0 total leaked bytes`)
- `build/native/m12-resize.log` (`960x540 -> 800x450 -> 1024x576`)
- `build/native/m12-shutdown.log` (`shutdown=1`)

The inspected GPU frame contains one compute encoder with three texture blits,
one render encoder with four labeled draws, three resident RGBA8 textures at
`64x32`, `128x16`, and `32x32`, the V4 vertex/fragment functions, one texture
and one sampler binding, and both labeled render-mode pipeline variants.
LLDB attached to the running AppKit host; it remained in the expected event
loop with no crash.

## Ground Truth Comparison

No emulator, N64 hardware, RenderDoc, or source-platform screenshot reference
artifact is available. The inspected native GPU capture is therefore evidence
of the V4 native pass structure, bindings, and output only; it is not N64 pixel
parity or generic RDP parity.

## What's Deferred

- Depth attachment/test/write, fog color/equation, alpha compare, coverage,
  and exact RDP blender/coverage parity remain for the later depth/fog/alpha
  goal. V4 records expose `GE_CLASSIC_COMBINER_DEFERRED_*` flags so these gaps
  are auditable rather than silently defaulted.
- Generic two-cycle combiner selectors, TEXEL1/mipmap/TMEM parity, full RDP
  load commands, source display-list production, title/level boot, gameplay,
  audio, performance, release, and emulator/reference parity remain out of
  scope.
- Deferred code paths carry `TODO(depth-fog-alpha-goal)` markers alongside the
  fixed-width V4 flags; grep that marker before starting the next goal.

## Known Issues

- The local macOS compositor can vary SDR screenshot channels between runs;
  the M12 pixel hash is retained as diagnostic evidence, while replay hashes
  and GPU inspection are the deterministic baseline.
- The M12 validation log includes the host's recent Metal validation launch
  records because the system log is not per-process resettable in this harness;
  the current run itself reports no Metal fault or validation error.

## Watch For

- Do not reinterpret `C4104DD8` as opaque: it is the authored later-group
  mode. `C4112078` is the primary opaque setup mode for this Type-4 path.
- Keep `GEClassicCombinerLoweringResultV4` a sidecar. Never add V4 fields to
  the frozen V1/V2/V3 ABI or regenerate their artifacts as part of a later
  feature.
- Keep the external ROM and ignored extracted payloads outside source control
  and application bundles.

## Key Decisions Made

- V4 public records retain the established native ABI envelope while the
  sidecar's semantic version is carried by its input/packet constants.
- TEXEL1 aliases TEXEL0 only because this bounded native fixture has one
  resident decoded texture per draw; this is explicit in both MSL and the
  handoff, not a generic mipmap claim.
- The four draws remain in one Metal 4 pass to preserve Apple TBDR behavior;
  color blend variants are pipeline state, while depth/fog/alpha/coverage are
  deferred instead of inventing a depth attachment.

## Skills Needed Next

For the next goal, load `porting-methodology`,
`translating-to-metal4-api`, `creating-metal4-shader-pipelines`,
`managing-metal4-resources`, `managing-metal4-synchronization`,
`presenting-metal-drawables`, `using-metal-validation`, `using-gpucapture`,
`using-gpudebug`, `debugging-rendering-issues`, and `swift-testing-expert`.
The natural next bounded goal is depth/fog/alpha/coverage lowering and a
depth attachment, still behind the external-ROM and source-platform evidence
boundaries.
