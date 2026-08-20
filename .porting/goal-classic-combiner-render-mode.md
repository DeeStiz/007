# Porting Goal: Classic Combiner and Render-Mode Lowering

## Status

Complete — defined from the completed `classic-textured-prop-material` goal and
its M8 handoff, then executed autonomously under the user's Luna-max
delegation contract. No commit, push, branch, reset, clean, or unrelated
cleanup was performed.

## Target

Lower the classic GoldenEye GE/F3D combiner and render-mode state used by the
ROM-derived `Pammo_crate1Z` ammo crate into a new fixed-width, value-only native
material contract and consume that contract in the direct Metal 4 renderer.
The completed goal must:

- preserve every V1, V2, and V3 ABI layout and frozen hash from the completed
  first-frame, classic-replay, and textured-material goals;
- preserve the external US ROM boundary, the exact Linux qemu-irix
  reference-build/hash evidence, and all existing provenance, replay, texture,
  runtime, screenshot, and GPU-capture artifacts;
- establish the source setup for this ModelType-4 prop from repository
  evidence: `modelApplyRenderModeType4`, the `G_CC_TRILERP` /
  `G_CC_MODULATEIA2` two-cycle combiner, and the authored `0xC4104DD8`
  render-mode word used by the crate's primary list;
- decode bounded classic `G_SETCOMBINE`, `G_SETOTHERMODE_H`, and
  `G_SETOTHERMODE_L` words into explicit two-cycle combiner selectors,
  render-mode flags, alpha/depth source, cycle/filter/LOD state, and blender
  factors, rejecting malformed shifts, lengths, selectors, and unsupported
  combinations without changing the V3 replay result;
- produce deterministic V4 lowering records and hashes keyed to each of the
  four textured crate draw groups, while the original V1/V2/V3 packet/event/
  material hashes remain byte-for-byte unchanged;
- lower the bounded supported `TEXEL1/TEXEL0` LOD interpolation followed by
  `COMBINED * SHADE` IA material into an MSL fragment path driven by the V4 key
  (the one-texture host fixture explicitly aliases TEXEL1 to TEXEL0), and map
  the captured opaque and authored decal render modes into Metal 4 color-blend
  state. Depth/coverage/fog/alpha details are recorded in the key but remain
  explicitly deferred to the later depth/fog/alpha goal;
- retain Metal 4 argument-table binding, device-owned reusable command buffers,
  explicit residency, queue-level drawable pacing, and write-to-read barriers;
- prove the new path with deterministic C/Swift tests, malformed-input tests,
  ASan/UBSan, runtime hashes and draw counts, screenshot evidence, Metal API and
  shader validation, resize/shutdown/leak evidence, and an inspected GPU frame
  showing the lowered pipeline/material state.

This goal proves only the bounded source setup and material lowering exercised
by the ammo crate. It does not claim generic two-cycle RDP coverage, depth/fog/
alpha/coverage parity, full source display-list production, game boot,
gameplay, emulator parity, sustained performance, release acceptance, or human
visual acceptance.

## Selection Rationale

The prior goal decoded and sampled the crate's three source textures but
intentionally rendered an explicit `TEXEL0 * vertex shade` diagnostic material.
The next smallest visible and verifiable delta is to make the existing classic
state meaningful: source `modelApplyRenderModeType4` supplies the combiner and
render-mode setup around the ROM-derived primary list, while the list itself
contains the texture-selection and mode words that must be preserved in order.
Lowering these words before the Metal boundary exercises the semantic gap
between classic RDP state and Metal pipeline state without pulling in the
unbounded game loop or generic RDP implementation.

## Key Decisions

- Carry forward Swift 6, Apple Clang, AppKit, macOS 27, direct Metal 4, the
  external ROM boundary, and the exact Linux reference command/hash evidence.
- Add a distinct V4 combiner/render-mode ABI. Do not add fields to V1, V2, or
  V3 records and do not recompute or reinterpret their hashes.
- Keep C authoritative for classic word decoding, partial other-mode register
  updates, selector validation, source setup constants, lowering keys, and
  deterministic hashes. Swift owns lifecycle and consumes copied V4 values.
- Treat the canonical source facts as inputs, not guesses: `Model.c` for
  `ammo_crate1` declares `TEXTURECOUNT 3`, `ModelType = 4`, the 40-vertex
  primary list, custom `G_SETTEX`/`G_TEXTURE`, and the final
  `B900031D C4104DD8`; `src/game/model.c` `modelApplyRenderModeType4` emits
  the two-cycle/combiner setup before the list.
- Support only the selector and render-mode subset exercised by this prop plus
  explicit negative tests. Unknown combiner selectors or unsupported cycle/
  blend combinations fail closed; they never silently fall back to V3 vertex
  color or the old diagnostic shader.
- Keep all four draw groups in one Metal 4 render pass for Apple TBDR. Use one
  argument-table transient record per draw, a shared sampler/texture binding,
  and a V4-aware pipeline whose color attachment blend state is sourced from
  the lowered key.
- Record depth/alpha/coverage bits in V4 and report them as deferred rather
  than inventing a depth attachment or claiming parity. The later
  depth/fog/alpha goal owns those semantics.
- Reuse the existing capture scripts and artifact directory; write new
  evidence under `build/native/m12-*` and `build/native/classic-combiner/`.
- Workers are Luna-max, read-only for preparation and disjoint-file owners for
  implementation/validation. No worker commits, pushes, branches, resets,
  cleans, reverts, or removes unrelated user artifacts.

## Milestones

| # | Name | Success Criterion | Status |
|---|---|---|---|
| M0 | Frozen provenance and contract guard | Re-verify the external ROM SHA-1, exact Linux reference command/hash evidence, crate/texture manifests, no tracked or bundled private inputs, and all frozen V1/V2/V3 hashes/artifact paths. | Complete |
| M1 | Combiner/render-mode V4 ABI | Add fixed-width V4 source-setup, two-cycle combiner, other-mode, render-mode, draw-key, and result records with layout assertions. A parser applies bounded partial-register updates and deterministically lowers `G_CC_TRILERP`/`G_CC_MODULATEIA2` plus the captured mode; malformed words reject. | Complete |
| M2 | Crate lowering and regression | Lower the external ammo-crate blob plus ModelType-4 setup into four draw-group keys in source order. V1/V2/V3 replay/material hashes remain exact; V4 key/event hashes are stable across C, Swift, normal, and ASan/UBSan tests. | Complete |
| M3 | Metal 4 combiner pipeline | Compile a V4-aware MSL library and MTL4 pipeline. Drive the bounded `TRILERP`/`MODULATEIA2` color/alpha path (TEXEL1 aliases TEXEL0 in this one-texture fixture) and source blend mapping through argument tables, residency, and explicit barriers with no diagnostic fallback. | Complete |
| M4 | Render-mode frame and capture | Render the four crate groups through one labeled Metal 4 pass, apply the lowered blend state, and record runtime/frame/pixel/resize/shutdown evidence. An inspected GPU capture shows the V4 pipeline, bindings, draw count, and lowered state labels. | Complete |
| M5 | Acceptance and handoff | Run independent validation: deterministic/malformed tests, ASan/UBSan, Metal API/shader validation, normal leaks, HUD/resource stability, resize/shutdown, screenshot, GPU capture/`gpudebug`, data-flow and skill-driven review. Update memory and write the handoff with deferred depth/fog/alpha markers. | Complete |

## Architecture Notes

```text
source modelApplyRenderModeType4 + classic prop words
                    |
                    v
        fixed-width V4 lowering ABI (C)
                    |
       copied per-draw combiner/render key
                    v
        Swift owner loop + Metal 4 pipeline
```

- Source combiner setup for the crate's ModelType-4 path is
  `G_CC_TRILERP` / `G_CC_MODULATEIA2`, encoded by the repository's macros as
  `FC26A004 1F1093FF`. The primary setup render mode is
  `B900031D C4112078`; the authored list changes to
  `B900031D C4104DD8` before the later texture groups.
- The prop list's classic other-mode words include `BA001001 00010000`
  (texture LOD), `BA001102 00000000` (detail), `BA000C02 00002000`
  (bilinear filter), and `B900031D C4104DD8` (the authored render mode).
  The ModelType-4 setup supplies the two-cycle/combiner commands before the
  V4 fixture preserves both source setup and prop order.
- Classic old-style `G_SETOTHERMODE_*` words encode shift in `w0[15:8]` and
  bit length in `w0[7:0]`; V4 applies a checked mask to the copied register and
  rejects zero/overlong ranges. No host `Gfx`, pointer, segmented address, or
  SDK object crosses the ABI.
- Combiner selector fields follow `include/PR/gbi.h`: cycle 0 RGB A/C in
  `w0[23:20]/[19:15]`, alpha A/C in `[14:12]/[11:9]`, cycle 1 RGB A/C in
  `[8:5]/[4:0]`; `w1` carries the B/D and cycle-1 alpha fields. V4 stores both
  raw words and decoded selectors so hashes remain auditable.
- Render-mode bits are retained as raw `other_mode_l` plus explicit AA,
  Z-compare/update, image-read, coverage, Z-mode, alpha-compare, and blender
  factor fields. The bounded opaque and authored decal blend mappings are
  consumed by Metal; depth/fog/alpha/coverage are marked deferred.
- The V3 replay result remains the geometry/material source of truth. V4 is a
  sidecar lowering result keyed by `source_command_offset` and `texture_id`, so
  V3 packet/event/material hashes cannot drift.
- Metal 4 uses one render encoder/pass for the four draws, one mutable argument
  table rebound per draw, GPU-address buffer bindings, resource IDs for
  textures/samplers, committed residency, and `.device` visibility barriers.

## Evidence and Boundaries

- Frozen values from the prior goals: V1 `1522029846112142469`; V2 packet
  `65363635960931316`, event `905714786767796339`, state
  `10439205544326414085`; V3 packet `11580554792388204033`, event
  `9845751795158270468`, material `14168780479827987350`.
- External ROM remains `/Users/derek/Documents/GoldenEye 007 (USA).z64`, SHA-1
  `abe01e4aeb033b6c0836819f549c791b26cfde83`; the Linux reference evidence is
  `.porting/m0-provenance.md` with `make -j8 IDO_RECOMP=NO VERSION=US
  COMPARE=1 VERBOSE=1` and `sha1sum -c ge007.u.sha1`.
- The new evidence must remain separate from prior artifacts. A native
  screenshot/GPU capture proves only this exercised lowering path, not N64
  pixel parity; no source-platform reference artifact is currently available.

## Completion Evidence

- V4 C/Swift replay and malformed lanes pass in
  `scripts/test_classic_combiner_replay.sh`, including normal repeated output,
  ASan/UBSan, and frozen V1/V2/V3 hashes. Stable V4 hashes are setup
  `6213740136672363482`, event `5747731189711370311`, and key
  `16733630809188353388`.
- `scripts/test_m12_classic_combiner.sh` passes the signed macOS 27 bundle,
  Metal AIR/metallib, API/shader-validation runtime, 60 frames/240 draws, six
  resource allocations, resize, zero-leak, shutdown, screenshot, capture, and
  `gpudebug` inspection. The screenshot hash is recorded in
  `build/native/m12-pixel.sha256`; the trace is
  `build/native/m12-classic-combiner.gputrace` and inspection is in
  `build/native/m12-gpudebug.log`.
- The inspected frame contains three texture blits, four labeled draw groups,
  the `GoldenEye.M12.ClassicCombiner` pipeline, both render-mode variants,
  three expected RGBA8 textures, one texture/sampler binding, and the V4
  vertex/fragment entry points. LLDB attached to the running AppKit host with
  the owner loop at the normal event run loop and no crash.
- Existing M11 screenshot bytes/hash and runtime/capture artifacts remain
  unchanged and are asserted by the M12 replay guard.

## Skills

| Milestone | Skills |
|---|---|
| M0–M2 | `porting-methodology`, `swift-testing-expert`, `swift-concurrency`; classic `gbi.h` and `model.c` source inspection |
| M3–M4 | `translating-to-metal4-api`, `creating-metal4-shader-pipelines`, `managing-metal4-resources`, `managing-metal4-synchronization`, `presenting-metal-drawables`, `using-metal-validation`, `debugging-rendering-issues` |
| M5 | `porting-methodology`, `swift-testing-expert`, `using-metal-validation`, `using-gpucapture`, `using-gpudebug`, `debugging-rendering-issues` |

## Hard Stop Conditions

- external ROM missing or SHA-1 mismatch;
- Linux reference command/hash evidence missing or changed;
- any V1/V2/V3 layout or frozen hash changes that cannot be isolated;
- source setup cannot be established from `model.c`, `model.c` render-mode
  helpers, and `gbi.h`;
- Metal 4 compiler/device/argument-table/residency path unavailable;
- capture cannot be inspected or correlated with the intended V4 draw/pipeline
  state after bounded repair iterations;
- implementation would expand into generic RDP, depth/fog/alpha parity, game
  boot, gameplay, audio, performance, release, or external human acceptance.
