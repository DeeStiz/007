# Porting Goal: Classic GBI Static Prop Replay

## Status

Complete — M0 provenance, M1–M4 classic replay, M5 Metal 4 prop rendering, and
M6 acceptance evidence pass. No commit or push was performed.

## Target

Extend the existing Swift 6/AppKit/direct Metal 4 vertical slice into a bounded,
real classic GoldenEye GE/F3D replay path. The completed goal must:

- preserve the canonical N64 source lane and exact Linux qemu-irix reference-build
  evidence;
- keep the user-provided US ROM external, untracked, and outside application
  bundles;
- add a separate versioned fixed-width replay ABI without changing the proven V1
  triangle contract;
- track classic command order, vertex-cache loads, geometry/other-mode/combiner
  state, texture identity, segment handles, list depth, and immutable per-draw
  state snapshots;
- resolve bounded classic `G_DL` push/branch traversal and `G_ENDDL` returns with
  cycle, depth, command-budget, and malformed-input rejection;
- decode classic `G_MTX`/`G_POPMTX`, fixed-point matrices, modelview/projection
  stacks, and deterministic viewport transforms without exposing N64 pointers;
- ingest the verified ROM-derived `Pammo_crate1Z.bin` ammo-crate geometry through
  an explicit extracted-asset manifest and replay its 40 vertices and 20
  triangles through a synthetic outer display list;
- render the transformed prop through Metal 4 argument tables, residency, and
  completion-fenced frame slots using an explicitly labeled vertex-color
  diagnostic material. Texture/TMEM/TLUT/combiner fidelity remains a separate
  later goal, although the replay state records the prop's texture and mode
  commands;
- produce deterministic replay/event evidence, a captured screenshot artifact,
  clean Metal validation, and an inspected GPU capture. Raw window pixel hashes
  are recorded separately because this host compositor can vary SDR channels by
  one code between captures.

This goal proves a real bounded classic GBI-to-host replay path and one
ROM-derived prop geometry. It does not claim GoldenEye boot, texture parity,
full RSP/RDP fidelity, gameplay, emulator parity, sustained performance, or
release acceptance.

## Selection Rationale

The first goal proved only a synthetic three-vertex fixture. The smallest next
feature delta that materially advances the port is the CPU-side classic replay
boundary: immutable state snapshots, nested-list control flow, matrix stacks,
and one real extracted prop. The existing source and asset pipeline already
provide authoritative classic GE/F3D semantics and a deterministic
`Pammo_crate1Z.bin` artifact, while the full game loop would still pull in MIPS,
OS scheduler, PI/VI, audio, controller, and physical-address dependencies.

The ammo crate is the chosen prop because its canonical generated display list
contains classic `G_TRI4` (`0xB1`), `G_SETTEX` (`0xC0`), `G_MTX` (`0x01`),
multiple `G_VTX` (`0x04`) loads, sync/other-mode transitions, and `G_ENDDL`
(`0xB8`). Its own list is intentionally wrapped by a small fixed-width outer
`G_DL` fixture so nested-list traversal is exercised without inventing a
replacement for the source-authored list.

## Key Decisions

- **Language/platform:** carry forward Swift 6, Apple Clang C, AppKit, macOS 27,
  and direct Metal 4.
- **Renderer strategy:** keep the narrow native GBI interpreter/draw-packet
  boundary; do not introduce a general RHI, emulator renderer, OpenGL, Vulkan,
  MoltenVK, SceneKit, SpriteKit, `MTKView`, or Metal 3 fallback.
- **ABI:** freeze all V1 records and add a distinct V2 replay contract with
  fixed-width integers, copied arrays, bounded counts, deterministic resource
  handles, and value-only return records. No host `Gfx`, pointer, segmented
  address, mutable C graph, or SDK object crosses into Swift.
- **Semantic ownership:** C owns classic GBI decoding, segment resolution,
  replay control flow, matrix state, and draw snapshots. Swift owns lifecycle,
  owner-thread orchestration, Metal objects, and immutable packet consumption.
- **Classic command set:** support the commands needed by the crate and replay
  wrapper, including `G_MTX 0x01`, `G_VTX 0x04`, `G_DL 0x06`, `G_TRI4 0xB1`,
  `G_SETTEX 0xC0`, `G_TRI1 0xBF`, `G_POPMTX 0xBD`, geometry/other-mode/sync
  commands, and `G_ENDDL 0xB8`. Unknown or malformed commands fail closed with
  opcode, byte offset, and list-depth diagnostics.
- **Nested replay:** `G_DL` resources are identified by deterministic 32-bit
  handles. Push and no-push branch behavior is explicit; active-list cycles,
  stack overflow, command-budget exhaustion, invalid handles, and premature
  root returns are errors.
- **Transforms:** decode N64 s15.16 matrix payloads and apply modelview and
  projection stacks plus a deterministic host viewport. Matrix data is copied
  into fixed-width ABI records; the prop's runtime segment-3 matrix is supplied
  by an explicit identity/model transform fixture.
- **Prop provenance:** canonical source row is
  `scripts/filelist.u.csv:308` (`8052448,576,...Pammo_crate1Z.bin,1,1`). The
  external ROM is `/Users/derek/Documents/GoldenEye 007 (USA).z64` with SHA-1
  `abe01e4aeb033b6c0836819f549c791b26cfde83`. The extracted uncompressed prop
  is validated at 1488 bytes, SHA-1
  `2902e2f28defaa2f99e514c12039a731e78072d7`, SHA-256
  `ca13ff3f26a399767435767fc748cd91027db675ac630d89bfbacc7705b760c9`.
  The compressed 1172 artifact is 576 bytes with SHA-256
  `aae993c36f98527510578a5d5b0dd707a54117884385c68ddc781def96af0ec9`.
  No ROM or generated private asset is tracked or bundled.
- **Texture boundary:** `G_SETTEX`, texture IDs, and mode transitions are
  preserved in state/event snapshots. The visible acceptance shader uses
  captured vertex colors as an explicit diagnostic material; actual texture
  decoding, TMEM/TLUT uploads, and combiner lowering are deferred and must not
  be described as complete.
- **Metal 4:** retain device-created reusable command buffers, one allocator
  per in-flight slot, argument tables, explicit residency, GPU-address buffer
  bindings, queue-level drawable waits/signals, and shared-event retirement.
  Do not use `set*Bytes`, per-encoder resource binding, managed storage, blit
  encoders, or queue-created command buffers.
- **Evidence:** preserve the exact Linux reference command and hash proof from
  `.porting/m0-provenance.md`. Keep deterministic replay, sanitizers, leaks,
  HUD/resource stability, screenshots, Metal validation, and `gpudebug` checks
  separate. Native screenshots/captures prove only this exercised replay path,
  not N64 visual parity.
- **Workflow:** use Luna-max workers with disjoint file ownership for execution
  and independent validation review. The primary agent owns this goal document,
  the public ABI schema, package/project integration, porting-memory, handoff,
  and final reconciliation. Do not commit, push, branch, clean, or reset.

## Milestones

| # | Name | Success Criterion | Status |
|---|---|---|---|
| M0 | Reference and prop guard | Re-verify the external ROM SHA-1 and the extracted ammo-crate size/hash; preserve the exact Linux `make -j8 IDO_RECOMP=NO VERSION=US COMPARE=1 VERBOSE=1` plus `sha1sum -c ge007.u.sha1` evidence; assert no ROM/asset is tracked or bundled. | Complete |
| M1 | Classic replay ABI and state snapshots | Add a versioned fixed-width replay contract while keeping V1 unchanged. A deterministic fixture records command order, segment/resource handles, vertex-cache loads, geometry/other-mode/combiner/texture state, list depth, transform state, and complete immutable draw snapshots; malformed state fails closed. | Complete |
| M2 | Nested display-list and segment replay | Decode classic `G_DL` push/branch and `G_ENDDL` return semantics, `G_MOVEWORD` segment updates, and resource handles. A nested wrapper fixture produces deterministic enter/return/event hashes and rejects cycles, bad handles, depth overflow, and command-budget exhaustion. | Complete |
| M3 | Matrix stacks and viewport transforms | Decode classic fixed-point `G_MTX`/`G_POPMTX` payloads, implement modelview/projection load/multiply/push/pop, apply a deterministic viewport, and pass identity/translation/scale plus malformed-matrix tests with transformed vertex hashes. | Complete |
| M4 | ROM-derived ammo-crate ingestion | Validate and parse the external extracted `Pammo_crate1Z.bin` into copied fixed-width vertices, list resources, texture identities, and canonical 22-command words. Replay emits exactly 40 render vertices and 20 `G_TRI4` triangles in source order, with stable command/event hashes and no raw pointers. | Complete |
| M5 | Metal 4 static-prop replay | Replay the authored outer `G_DL` wrapper into transformed draw packets and render the visible ammo-crate geometry through the existing Metal 4 argument-table/residency path using the explicit vertex-color diagnostic material. A captured frame shows labeled prop resources and expected draw groups; replay/event hashes are stable, a screenshot artifact is recorded, and Metal API/shader validation reports no fault. | Complete |
| M6 | Acceptance and handoff | Independently run deterministic replay, ASan/UBSan, normal non-HUD leaks, Metal HUD/resource stability, resize/shutdown, screenshot, and inspected `gpudebug` checks. Record known texture/parity limits, update porting-memory and the final handoff, and leave all repository publishing to the user. | Complete |

## Architecture Notes

### Source and prop lanes

```text
Canonical N64 decomp + external US ROM + Linux qemu-irix hash proof
                              |
                              | source semantics / extracted prop bytes
                              v
                 Fixed-width classic replay ABI (C)
                              |
                              | copied immutable state/draw snapshots
                              v
                 Swift 6 owner loop and Metal 4 renderer
```

- The prior V1 normalizer is intentionally synthetic and remains a regression
  lane. Do not reinterpret its `G_VTX` count or `G_TRI1` bytes as classic
  semantics; the new replay ABI has separate V2 records.
- Classic `Gfx` commands are exactly two 32-bit wire words even though
  `include/PR/gbi.h` exposes host `uintptr_t` fields. Segment/resource handles
  replace pointer-bearing addresses at the native boundary.
- The canonical ammo-crate binary uses big-endian data and `0x05000000`-relative
  model pointers. The native loader converts only validated offsets into copied
  arrays; it never compiles or traverses generated pointer-bearing `Model.c`.
- The crate primary list contains 22 commands, five `G_TRI4` operations, three
  vertex loads (16, 16, and 8), a runtime segment-3 matrix reference, and no
  nested `G_DL`. A fixed outer wrapper supplies the nested call/return test.
- C draw packets snapshot every state value consumed by the shader/renderer;
  command order is never globally reordered around sync or mode changes.
- Metal 4 render passes should remain grouped for Apple TBDR. Per-draw
  constants use a per-frame transient shared buffer and GPU-address argument
  binding, with the backing buffer resident until the shared-event fence retires.

### Evidence boundary

- Exact Linux ROM-build/hash evidence remains provenance proof, not a claim that
  the macOS portability lane produces the same bytes.
- A successful replay hash proves decoding and state/event determinism for the
  exercised resources only.
- A visible ammo-crate frame proves transformed ROM-derived geometry and the
  explicit diagnostic material path; it does not prove texture, combiner,
  lighting, clipping, depth, or N64 pixel parity.
- Missing/mismatched extracted assets fail closed; the native host never falls
  back to reading the external ROM at runtime.

## Skills

| Milestone | Skills to load |
|---|---|
| M0 | `porting-methodology`; macOS build/run guidance; provenance and asset-pipeline inspection |
| M1 | `porting-methodology`, `swift-testing-expert`, `swift-concurrency`; authoritative classic `gbi.h`/`gbi_extension.h` inspection |
| M2 | `porting-methodology`, `swift-testing-expert`; classic GBI control-flow and segment semantics |
| M3 | `porting-methodology`, `swift-testing-expert`; fixed-point matrix/viewport source inspection |
| M4 | `porting-methodology`, `swift-testing-expert`; ROM extraction and generated-asset provenance review |
| M5 | `translating-to-metal4-api`, `managing-metal4-resources`, `managing-metal4-synchronization`, `presenting-metal-drawables`, `using-metal-validation`, `creating-metal4-shader-pipelines`, `using-gpucapture`, `using-gpudebug`, `debugging-rendering-issues` |
| M6 | `porting-methodology`, `using-metal-validation`, `using-gpucapture`, `using-gpudebug`, `swift-testing-expert`; independent Luna-max validation review |

## Future Goal Horizon

Texture/TMEM/TLUT decoding and uploads, combiner/render-mode lowering, depth,
fog, alpha/coverage, real source display-list production, title/level boot,
controller gameplay, audio, parity, performance, and release work remain
outside this goal.
