# Porting Goal: Native Metal First Frame

## Status

Complete — M0 exact-ROM provenance and M9 native first-frame acceptance are
complete. The native vertical slice is implemented through M8; gpudebug
command-tree/state inspection passes, while resource fetching remains an
environment limitation and is not used as the pixel/trace acceptance claim.

## Target

Create a development-signed Swift 6 macOS 27 application that uses AppKit, a raw `CAMetalLayer`, and direct Metal 4 presentation to render one deterministic colored triangle produced from a fixed-width GoldenEye-style GBI fixture.

The completed goal must provide:

- a preserved and independently verifiable N64 source/ROM build lane;
- a small Apple-Clang C fixture core behind a versioned, fixed-width, pointer-free ABI;
- one owner-thread Swift lifecycle and input path;
- explicit Metal 4 command allocation, argument tables, residency, completion retirement, and drawable presentation;
- deterministic command-packet and pixel evidence;
- clean Metal validation and an inspected GPU capture.

This goal proves the first complete native host-to-GPU vertical slice. It does not claim that GoldenEye boots, that gameplay works, or that the pixels match the N64.

## Selection Rationale

The original codebase is N64-only and has no host platform layer or renderer abstraction. `rspGfxTaskStart` packages a display-list range into an N64 `OSTask` and submits it to the RSP/RDP scheduler; it is not an existing host renderer. Attempting `bossEntry`, `bossMainloop`, or `lvlRender` first would couple the initial Metal work to MIPS boot code, N64 threads, PI/VI services, physical-address DMA, stage loading, controller I/O, and audio.

The smallest visible and verifiable target is therefore a deterministic fixed-width display-list fixture feeding a direct Metal 4 draw. This establishes the contracts that later goals can extend with real GoldenEye display lists, textures, combiners, and the live game loop without allowing raw N64 pointers or mutable C graphs to leak into Swift.

The architecture deliberately reuses the proven SM64 Modern principles — parallel native target, versioned POD ABI, raw `CAMetalLayer`, one owner thread, immutable frame snapshots, reusable Metal 4 frame slots, argument tables, residency, and completion-fenced retirement — without reusing SM64-specific packet layouts, shader IDs, vertex strides, or rendering semantics.

## Key Decisions

- **Language and platform:** Swift 6, Apple Clang C, AppKit, macOS 27, Metal 4.
- **Renderer:** direct native Metal 4. No OpenGL, Vulkan, MoltenVK, emulator renderer, generic RHI, SceneKit, SpriteKit, `MTKView`, or cross-API translation layer.
- **Semantic ownership:** C owns GoldenEye-derived GBI interpretation and later gameplay semantics. Swift owns application lifecycle, owner-thread orchestration, immutable packet handoff, input adapters, and Metal objects.
- **Boundary:** Swift never retains or traverses raw `Gfx *`, N64 physical/segmented addresses, or mutable gameplay object graphs.
- **Wire command:** the host contract uses exactly two fixed-width words, conceptually `GECommandWordsV1 { uint32_t w0; uint32_t w1; }`. It does not expose `include/PR/gbi.h`'s host `Gfx` layout.
- **Resource references:** pointer-bearing commands use deterministic 32-bit resource handles resolved inside C. Host pointers are never truncated into command words.
- **Failure behavior:** malformed, truncated, unknown, over-budget, or wrong-state input fails closed with command identity and offset diagnostics. Unsupported visible behavior is never silently skipped.
- **Frame ownership:** one owner thread owns C lifecycle, packet production, and mutable renderer state. Display-link work consumes immutable snapshots only.
- **Input for this goal:** one keyboard path only. Full GoldenEye bindings and GameController gameplay are deferred.
- **Content for this goal:** a synthetic deterministic triangle fixture. ROM-derived textures, props, and levels are deferred.
- **ROM boundary:** `/Users/derek/Documents/GoldenEye 007 (USA).z64` remains external, untracked, and excluded from application bundles and distributable artifacts.
- **Source preservation:** the N64 Makefile lane remains independently buildable and must not be replaced by the native target.
- **Phase gates:** preparation, execution, validation, and handoff remain separate and advance only on explicit user invocation.
- **Authorization:** no commit, push, branch, cleanup, or release action is implied by this plan.

## Milestones

| # | Name | Success Criterion | Status |
|---|------|-------------------|--------|
| M0 | Legacy baseline | Trustworthy source provenance is restored or established for upstream `c4356466`; the external US ROM hash is verified; the existing N64 build produces the expected US ROM hash; no ROM or generated private asset is tracked or bundled. | Complete |
| M1 | Callable fixture core | Apple Clang builds a small native static archive exposing versioned initialize/step/shutdown and immutable fixture-packet APIs. C and Swift agree on every public layout; invalid version, size, state, and owner-thread calls are rejected; repeated fixture hashes match; no MIPS, N64 hardware service, process entry point, or raw pointer crosses the ABI. | Complete |
| M2 | AppKit host | A normally launched, development-signed `.app` opens an AppKit window backed by a scale-correct raw `CAMetalLayer`; one owner loop advances a bounded C tick counter and shuts down cleanly. Rendering capability remains unpublished. | Complete |
| M3 | Keyboard input | Keyboard down, up, pressed, and released edges reach the owner loop through a fixed-width snapshot, and focus loss clears held and pending state deterministically. | Complete |
| M4 | Metal 4 device | The app rejects non-Metal-4 devices and creates labeled device-owned queue, two reusable command-buffer/allocator slots, an initialized argument table, scene/layer residency, and a shared completion event. No drawable is presented. | Complete |
| M5 | First clear | A raw-layer drawable is cleared and presented through acquire → encode → `waitForDrawable` → commit → completion signal → drawable signal → present. Resize, pause, slot reuse, and GPU-drained shutdown pass with Metal validation and a captured clear frame. | Complete |
| M6 | Baseline pipeline | Minimal vertex and fragment MSL artifacts load, and a labeled Metal 4 render pipeline is created from function descriptors with deterministic identity. No GBI geometry is submitted. | Complete |
| M7 | GBI normalization | A C fixture containing only classic GoldenEye `G_VTX` (`0x04`), `G_TRI1` (`0xBF`), and `G_ENDDL` (`0xB8`) plus a resource-handle table normalizes into exactly one immutable draw packet. Packet/event hashes are repeatable, and malformed or unsupported streams fail with precise diagnostics. | Complete |
| M8 | Vertex drawing | The M7 packet produces one visible colored triangle through Metal 4 argument-table bindings and resident transient resources. A GPU capture shows one expected labeled render pass and draw; screenshot and pixel hash are stable; Metal API and shader validation report no fault. | Complete |
| M9 | First-frame acceptance | Separate deterministic replay, ASan/UBSan, normal non-HUD leak, Metal HUD/resource-stability, resize/shutdown, screenshot, and `gpudebug` inspections pass. The evidence bundle states exactly what the vertical slice proves and what remains unproven. | Complete |

## Scope Exclusions

The following are explicitly outside this goal:

- `bossEntry`, `bossMainloop`, `lvlRender`, the original scheduler, and full native game boot;
- nested display lists, segmented addressing, matrix stacks, viewport transforms, lighting, clipping, geometry modes, `G_TRI2`, GoldenEye `G_TRI4`, rectangles, and sync semantics beyond the declared fixture;
- textures, TMEM, TLUTs, mipmaps, N64 filtering, real extracted assets, props, and levels;
- combine modes, two-cycle rendering, fog, alpha compare, coverage, dithering, depth/raster fidelity, and dynamic shader generation;
- GameController gameplay mappings, mouse-look, rumble, audio, saves, multiplayer, and 60 Hz simulation changes;
- emulator/N64 visual parity, sustained performance/thermal acceptance, signing distribution, notarization, and release packaging.

## Architecture Notes

### Source and native lanes

```text
Canonical N64 decomp + external ROM build
                    |
                    | source semantics only
                    v
Apple-Clang C semantic/fixture core
                    |
                    | copied versioned fixed-width packets
                    v
Swift 6 AppKit host and owner loop
                    |
                    v
Direct Metal 4 renderer and CAMetalLayer presentation
```

- The current checkout contains about 220,021 C/header/assembly source lines and an extracted local asset tree of about 53.3 MB across 4,715 files, including 2,698 image payloads.
- Local `HEAD` is a shallow reference to upstream `c4356466796c697dfd298010b9bed261f9ed8c6a`; the tracked source lane matches that commit except for the explicitly documented Darwin build-portability edits. Porting artifacts and extracted/private assets remain outside the upstream tracked lane.
- `Gfx.words` uses `uintptr_t`; the host layout may become 16 bytes while the N64 command is 8 bytes. Public native records therefore use fixed-width words and resource IDs only.
- `rspGfxTaskStart` is the eventual replacement seam, but its current body only creates an N64 `OSTask`. It must not be described as an existing interpreter.
- GoldenEye uses the classic GE/F3D command layout, not F3DEX2. Later goals must account for its custom `G_TRI4` (`0xB1`) and texture selection (`0xC0`) semantics.
- C remains authoritative for command order and state interpretation. Each draw packet must snapshot the complete state needed by that draw; future implementations must never globally reorder display-list draws.

### Metal 4 invariants

- Command buffers are created from the device, reusable, and explicitly begun/ended with one allocator per in-flight slot.
- A slot allocator is not reset until its shared-event completion value has signaled.
- Metal 4 argument tables replace `set*Bytes` and per-encoder resource binding.
- All referenced resources are explicitly resident and retained through GPU completion; Metal 4 command buffers do not retain them.
- Queue-level layer/scene residency is explicit.
- The first goal uses one large render pass suitable for Apple TBDR.
- Command buffers, encoders, pipelines, argument tables, buffers, residency sets, and draw groups receive stable labels from the first rendering milestone.
- Metal API validation, shader validation, GPU capture, leaks, and HUD runs are separate when their instrumentation would interfere.
- Any GPU capture used as evidence must be inspected, not merely created.

### Evidence boundary

- A successful build does not prove launch, ABI correctness, rendering, input, memory safety, or fidelity.
- A clear frame proves presentation only.
- A captured triangle proves the exercised fixed-width packet and Metal path only.
- The verified ROM proves provenance, not visual parity.
- Without an emulator or hardware reference capture, this goal cannot establish GoldenEye visual fidelity.

## Luna Max Delegation Protocol

- Delegated work uses explicit `luna_worker` agents, which are pinned to Luna at maximum reasoning.
- **Prepare:** use parallel read-only Luna workers for source/ABI analysis, Metal 4 contract review, and evidence design.
- **Execute:** only after `/porting-execute`, assign one worker per non-overlapping file domain. Suggested lanes are C ABI/fixture core, Swift host/input, Metal renderer, and tests/evidence.
- **Integration authority:** the primary agent alone owns the public ABI schema, Xcode/project integration, `.porting` artifacts, and final reconciliation.
- Do not allow multiple agents to edit the ABI header, renderer contract, or Xcode project concurrently. Freeze a shared schema before parallel implementation begins.
- **Validate:** in a fresh validation session, use independent Luna max reviewers for ABI/provenance, Metal/GPU evidence, and adversarial acceptance boundaries.
- Every worker prompt must state that other agents share the workspace, prohibit unrelated cleanup/reverts/commits/pushes, define file ownership, require exact validation commands, and require reporting changed files, artifact paths, assumptions, and unresolved risks.
- The primary agent verifies all delegated output; subagent completion is not acceptance evidence by itself.

## Skills

| Milestone | Skills to load during preparation/execution/validation |
|---|---|
| M0–M1 | `porting-methodology`, macOS build/run/debug guidance, `swift-concurrency`, `swift-testing-expert` |
| M2 | `setting-up-macos-window`, macOS window-management/build guidance, `swift-concurrency` |
| M3 | `using-game-controller` for Apple keyboard/input contracts, `swift-concurrency` |
| M4 | `translating-to-metal4-api`, `managing-metal4-resources`, `using-metal-validation` |
| M5 | `presenting-metal-drawables`, `translating-to-metal4-api`, `managing-metal4-synchronization`, `using-metal-validation`, `using-gpucapture`, `using-gpudebug` |
| M6 | `creating-metal4-shader-pipelines`, `translating-to-metal4-api`, `using-metal-validation` |
| M7 | `porting-methodology`, `swift-testing-expert`; inspect authoritative GoldenEye GBI headers and generator scripts |
| M8–M9 | `translating-to-metal4-api`, `managing-metal4-resources`, `managing-metal4-synchronization`, `using-metal-validation`, `using-gpucapture`, `using-gpudebug`, `debugging-rendering-issues` |

## Future Goal Horizon

The expected sequence after this goal is:

1. Classic GoldenEye GBI state, nested-list replay, transforms, viewport, raster state, and a real static prop such as `Pammo_crate1Z.bin`.
2. Texture/TMEM/TLUT decoding and uploads across RGBA, CI, IA, and intensity formats.
3. Combiner/render-mode semantics, depth, fog, alpha/coverage, and canonical Metal pipeline caching.
4. Portable title/intro host and actual source-authored display-list production.
5. Playable level integration with Apple controller input.
6. Audio, saves, split-screen/multiplayer behavior, deterministic parity, performance, and release work.
