# Porting Goal: Native Boot, Menu, Attract Mode, and 120 Hz Runtime

## Status

In progress — fidelity recovery was rebaselined on 2026-08-19 after visual
inspection proved that the current title and stage output is a procedural/
diagnostic vertical slice, not a source-faithful GoldenEye renderer. All prior
work and evidence remain preserved, but none of the GETP/GETU/fullscreen-title
or room/portal-overlay captures count as visual parity. Additive V6 source
scene, static source-audit, GBI semantic, cadence, output-policy, and lossless
asset-catalog foundations are now being integrated. Full source model/texture/
combiner consumption, stage gameplay, and measured 120 Hz acceptance remain
pending. This goal follows
the completed `classic-combiner-render-mode` goal and preserves all earlier
artifacts and ABI records.

## Target

Build a native Swift 6/AppKit/macOS 27 application backed by direct Metal 4
that launches without executing MIPS, libultra, RSP/RDP emulation, or a ROM
runtime. It must show the source-ordered Legal, Nintendo, Rareware,
Gunbarrel, and GoldenEye sequence; reach interactive File Select and Mode
Select; and preserve the source hands-off cast/RAMROM attract route.

The native owner loop is authoritative at 120 Hz on every display. A capable
display presents at 120 Hz; a fixed-60 display presents every second immutable
state while logic, audio, and replay hashes remain equal at matching native
ticks. The 4:3 reference canvas remains exact, while wider windows use
adaptive layout that extends neutral background space and never stretches
source art.

C remains authoritative for deterministic source-derived runtime semantics,
asset interpretation, classic rendering lowering, and audio synthesis where
needed. Swift owns AppKit, Metal objects, input, persistence, audio lifecycle,
and platform services. Only copied fixed-width records cross the boundary.

## Frozen Provenance and Compatibility

- Preserve all existing dirty-worktree changes and artifacts. No commit, push,
  branch, reset, clean, or unrelated cleanup is part of this goal.
- Keep the V1/V2/V3/V4 records and hashes unchanged:

  - V1: `1522029846112142469`
  - V2 packet/event/state: `65363635960931316`, `905714786767796339`,
    `10439205544326414085`
  - V3 packet/event/material: `11580554792388204033`,
    `9845751795158270468`, `14168780479827987350`
  - V4 setup/event/key: `6213740136672363482`, `5747731189711370311`,
    `16733630809188353388`

- Preserve the external US ROM boundary. The verified ROM remains outside the
  checkout at `/Users/derek/Documents/GoldenEye 007 (USA).z64` with SHA-1
  `abe01e4aeb033b6c0836819f549c791b26cfde83`.
- Preserve the exact Linux reference commands recorded in
  `.porting/m0-provenance.md`:
  `make -j8 IDO_RECOMP=NO VERSION=US COMPARE=1 VERBOSE=1` and
  `sha1sum -c ge007.u.sha1`.
- Preparation may use an explicitly supplied external ROM only to regenerate
  ignored, hash-manifested private assets under `build/native/`. Runtime code
  never opens the ROM and never falls back to a bundled/private payload.

## V5 Boundary

The additive `native/include/ge_native_runtime_v5.h` sidecar carries
`GEAbiHeaderV1` in every record and uses reserved-zero validation:

- `GETimebaseConfigV5` describes the 120/60 paired scheduler, catch-up
  limits, policy flags, and the 22,050 Hz audio clock.
- `GEInputEventV5` and `GEInputSnapshotV5` carry timestamped keyboard/
  controller events, normalized buttons, Q16.16 axes, focus state, and edge
  state.
- `GETitleParitySnapshotV5` records source screen/subphase/timer state,
  paired ticks, Q16.16 transform values, selection, and state/render/audio
  hashes.
- `GESceneFrameV5` and `GEScenePageV5` carry immutable frame metadata and
  bounded page descriptors for transforms, resources, draw commands, UI, and
  diagnostics. Payloads are copied through call-time buffers, never pointers.
- `GEAudioCommandV5` and the canonical `ge_audio_v5.h` PCM/snapshot records
  carry sample-indexed events and immutable audio observations. The realtime
  ring remains owner-side.
- `GERamRomSnapshotV5` records demo/stage identity, packet position,
  speedframes, RNG checkpoints, and state/render/audio hashes.

All V5 record hashes use explicit little-endian FNV-1a field encoding. Public
records contain no pointers, host addresses, paths, raw `Gfx`, ROM addresses,
or mutable object graphs.

## Milestones

| # | Name | Success criterion | Status |
|---|---|---|---|
| M0 | Provenance and artifact freeze | Recheck the ROM boundary, Linux reference evidence, current artifacts, and V1–V4 hashes without changing them. | Implemented — classic-combiner replay/hash guard and guarded asset manifest pass. |
| M1 | V5 contract guard | C/Swift layouts, reserved fields, enum/range checks, malformed records, and deterministic hashes pass. | Implemented — strict C smoke and package build pass. |
| M2 | 120 Hz owner scheduler | A dedicated owner thread runs rational 120/60 paired ticks, exact source anchors, bounded catch-up, pause/resume rebasing, and debt diagnostics. | Implemented — isolated scheduler smoke and product-mode owner integration pass. |
| M3 | Drawable presentation | Owner-thread `CAMetalDisplayLink` consumes its supplied drawable, uses fenced frame slots, supports display migration and apply-after-present resize, and drains cleanly. | Implemented for the native title lane — supplied-drawable renderer and GPU capture pass; 120 Hz acceptance remains display-dependent. |
| M4 | Keyboard/controller input | Timestamped keyboard events, buffered GameController states, normalized mappings, once-only edges, focus loss, and disconnect recovery pass. | Implemented — mailbox/controller mapping smoke passes; host bridge remains additive. |
| M5 | Native saves | Four logical folders support select/create/copy/erase, atomic replacement, backup recovery, corruption quarantine, and relaunch persistence. | Implemented — codec/store/recovery smoke passes. |
| M6 | Title/attract asset catalog | Title, font, audio, cast, RAMROM, and demo-stage rows have source provenance and exact raw/decoded hashes; missing rows fail closed. | Implemented for the current boot/attract foundation — 31 guarded boot assets, 21 guarded stage resources, four source-derived title geometry packets, and the Rareware atlas pass; full cast/stage dependency catalog remains pending. |
| M7 | Model/node ingestion | Bounded group, BBOX, DL, BSP, SWITCH, character, LOD, shadow, and attachment nodes copy into handle-based scene data. | In progress — additive GETN packets now copy the four frontend ModelNode trees (138 nodes, 92 texture metadata rows), parent/child/sibling links, source-local record/display-list/vertex offsets, model types, and malformed-link/hash guards; runtime loads the packets for title evidence while full geometry/material traversal remains pending. |
| M8 | Texture/TMEM/TLUT lowering | Required RGBA/CI/IA/I formats, palettes, mip chains, wrapping, clamping, and samplers lower through bounded native records. | In progress — additive GETT packets validate 92 source-derived rows (Legal 5, Nintendo 1, GoldenEye 2, walletbond 84), decode bounded RGBA8 base levels, preserve source-byte hashes and GoldenEye’s 696-byte mip tail, and reject tampering in strict/ASan/UBSan C/Swift tests. Metal 4 binds the first validated record for Legal/Nintendo/GoldenEye/File/Mode title passes using GPU-private textures, shared staging, one-time compute copies, explicit barriers, and persistent residency; full mip-level upload, Rareware source mip/LOD, and generic TMEM/TLUT remain pending. |
| M9 | Combiner/raster completion | General required one/two-cycle selectors, primitive/environment/fog colors, depth, alpha, coverage, culling, and render modes are explicit. | In progress — additive `GEClassicRasterStateV5` lowers the canonical ammo-crate modes `C4112078`/`C4104DD8` into explicit depth, fog, alpha, blender, and coverage policies; Metal 4 binds depth32 state, alpha compare/dither, source fog, alpha-to-coverage, and diagnostics. Additive title raster V5 now audits eight source tuples across Legal/Nintendo/GoldenEye/Rareware/wallet (`aggregate=11519430422207814888`); generic RDP raster coverage remains pending. |
| M10 | Transforms and lighting | Projection/modelview, clipping, normals, lighting, look-at, texgen/reflection, and source quantization produce immutable draw packets. | In progress — additive Projection V10 provides fixed-width Q16.16 source-matrix quantization, modelview/projection transforms, six-plane clipping, culling, canonical 440×330 identity, rational widescreen inverse mapping, and deterministic packet hash `15192084148729639549`; `scripts/test_native_title_projection_evidence.sh` consumes all eight GETP packets (`aggregate=17378376777734745904`), and additive GETU consumes 1,251 signed-UV/material corners (Legal 36, Nintendo 192, GoldenEye 1,023) with source command/vertex hashes. Title/stage draw consumption and full lighting/look-at/texgen remain pending. |
| M11 | 2D and adaptive layout | Fills, scissor, rectangles, fonts, icons, fades, 440×330 safe layout, wide anchors, and inverse hit testing pass at 4:3, 16:9, and ultrawide. | In progress — GETF/GETC font/catalog, seven guarded GETI icon rows (23,572 decoded RGBA8 bytes), direct Legal/File/Mode geometry, source UI bounds, reusable inverse-hit-test layout, alpha-blended File Select icon draws, and shader letterboxing pass; full source-identical layout remains pending. |
| M12 | Audio parsing | Guarded instrument/SFX banks and boot/menu sequences parse with bounded backreferences, loops, varints, and malformed-stream rejection. | Implemented — strict C smoke renders all three boot tracks and validates guarded banks. |
| M13 | Native synth | 22,050 Hz deterministic synthesis supports voices, envelopes, loops, pitch/pan/gain, composite SFX, reverb, and block-size-independent hashes. | In progress — additive V6 fixed-point Small/Big Room reverb, composite graph, and title SFX IDs 18/77/79/111/258 pass strict/ASan/UBSan/Release vectors; the new `scripts/test_audio_long_soak_v5.sh` passes a 600-second-equivalent/72,000-tick deterministic soak (`13,230,000` frames, zero underruns/drops) with block-size-independent PCM hashes; complete source mix/reverb tuning and live AVAudio A/V evidence remain pending. |
| M14 | Audio output | Sample-indexed events feed the realtime SPSC ring and `AVAudioSourceNode` with no realtime allocation, lock, logging, or Swift calls. | Implemented as a bounded output seam — C ring, Objective-C source node, preroll/refill, route recovery, and owner `tick(nativeTick:)` wiring pass; full mix fidelity/long-soak acceptance remains pending. |
| M15 | Boot state authority | Swift title state and immutable snapshots match an independent 60 Hz source adapter at every even anchor; rendering is pure. | Implemented for the bounded title route — paired Swift authority and C reference adapter pass 10,000 even-anchor comparisons, including cast→RAMROM at native tick 6788; gunbarrel dynamics, GoldenEye odd-tick projection, and render-hash parity remain explicit unsupported fields. |
| M16 | Legal screen | Source text/save validation, exact 241-tick timing, and first-boot unskippable input rule pass. | In progress — exact paired timer/input rule, validated 287-string source catalog, and source-derived Legal geometry packet pass; font/material parity remains pending. |
| M17 | Nintendo screen | Source rotation/scale/lighting, swoosh, duration, and skip rules pass with authentic audio. | In progress — exact paired duration/skip rule plus new fixed-point half-step rotation/1.07977 scale clamp and source ambient-light projection; boot-track output and geometry packet pass, while full texture/material/swoosh parity remains pending. |
| M18 | Rareware screen | Source rotation/fade, mip/LOD behavior, composite SFX, and timing pass. | In progress — source-derived Rareware geometry plus a guarded 64×86 RGBA8 atlas, source timing/route seam, and guarded asset pass; full mip/LOD/composite SFX parity remains pending. |
| M19 | Gunbarrel | Suit/head/PP7 animation, attachments, flash, background, blood/fades, intro music, and transitions pass. | In progress — prepared background, paired state machine, source attachment lowering, and immutable topology cache pass focused lanes; sustained dynamic cadence and full visual parity remain pending. |
| M20 | GoldenEye logo | Lighting, texgen/reflection, fade timing, and File Select versus cast routing pass. | In progress — source-derived GoldenEye geometry plus exact two-cycle LOD/combiner tuple and deterministic Metal captures pass; full lighting/texgen/reflection/fade/material parity remains pending. |
| M21 | File Select | Four wallets, source UI, idle return, full folder actions, and adaptive widescreen pass. | In progress — persistent four-folder actions, async save integration, two-stage erase confirmation (default Cancel), source-derived walletbond/icon geometry, 440×330 viewport, inverse hit bounds, and interactive UI pass; full source save/UI parity remains pending. |
| M22 | Mode Select | Navigation, availability, back behavior, and persistence pass. | In progress — interactive navigation/back/persistence boundary and runtime screenshot pass; source model/text/multiplayer availability parity remains pending. |
| M23 | Cast reel | Body/head/weapon selection, skeletal animation, source timing, random entries, and exit rules pass. | In progress — 34-entry source route, unlock/guest gates, random/explicit demo selection, source attachment lowering, Cast texture/render-mode fixtures, and abort/restore pass; live supplied-drawable Cast cadence remains unproven. |
| M24 | Native platform services | Memory, DMA/file index, RZIP, arenas, stage lifecycle, and required platform services operate without the N64 scheduler. | In progress — bounded Swift stage catalog plus C 1172/rebase, metadata packet copy-out, decoded-arena views, value-only setup/portal packets, and owner-side scene-packet preparation validate all 21 prepared rows; full lifecycle/platform replacement remains pending. |
| M25 | Demo-stage loading | Dam, Facility, Runway, Bunker I, Silo, Frigate, and Train scene/setup data load through deterministic handles. | In progress — all seven stage families load bounded decoded payloads, 468 background rooms, 2,225 setup objects, 2,230 pads/bound pads, 612 portals, source materials/TLUTs, and deterministic scene/setup hashes; source environment plus static-prop Metal lanes pass, while gameplay categories remain pending. |
| M26 | Demo gameplay core | Demo-reachable player/camera/collision, props, doors, guards, AI, objectives, weapons, effects, and paired cadence run headlessly. | In progress — bounded runtime owns fixed-point player/camera state, pad lookup, room/portal traversal, door/guard/objective summaries, deterministic 120 Hz stepping, and abort/restore; V7 camera packets lower room/static-prop visibility, while collision/AI/weapons/effects remain explicit diagnostics. |
| M27 | Demo renderer | Rooms, sky, props, characters, weapons, particles, glass, explosions, HUD/watch, and fades render through Metal 4. | In progress — all seven source environment/material Metal captures and V7 room/static-prop compositions pass with non-identity camera packets; character/effect/AI/HUD categories and a Release supplied-drawable gameplay capture remain pending. |
| M28 | RAMROM playback | All 14 recordings parse, preserve source-anchor packet/RNG consumption and speedframes, support abort, and restore title state. | In progress — all 14 recordings now pass twice (`runs=28`) through strict/ASan/UBSan C and Swift owner-service abort/fade/return/restore validation with matching recording/packet/input/checksum/RNG hashes; all-14 native stage/gameplay execution remains explicitly unsupported. |
| M29 | Integrated acceptance/handoff | Both launch routes, Release signing, 120/60 evidence, validation, sanitizers, capture inspection, and handoff artifacts pass. | In progress — fresh signed Release, frozen provenance, V7 owner/renderer integration, Cast attachment/texture/render-mode fixtures, Cast topology/first-packet prewarm, stage environment/static-prop Metal captures, strict/ASan/UBSan, and deterministic Cast reference capture pass; physical 120/60 presentation, live Cast supplied-drawable evidence, and full gameplay-category closure remain pending. |

## Fidelity Recovery Rebaseline — 2026-08-19

The recovery work below supersedes any visual-readiness implication in M7–M29
without deleting or rewriting those artifacts. Release must not execute the
procedural title shader, partial GETP/GETU paths, or diagnostic stage overlay.

| # | Recovery gate | Status |
|---|---|---|
| R0 | Preserve the dirty worktree and artifacts; reverify V1–V5, the external-ROM boundary, exact Linux evidence, and bundle guards. | Complete — `.porting/fidelity-recovery-r0-baseline.md` and `scripts/test_fidelity_recovery_r0.sh` pass. |
| R1 | Add fixed-width V6 source resources, geometry, transforms, poses, render state, draws, text/audio events, frame summaries, static source audits, and a dynamic original-source oracle. | Complete — fixed V6 layouts/hashes, reachable-source counts, classic GE/F3D decoding, and strict/sanitized arm64 builds of the unchanged `front.c`/`title.c` oracle pass with deterministic pointer handles. |
| R2 | Prepare and consume a lossless guarded frontend catalog with full node, display-list, vertex, texture, mip, TLUT, font, blood, animation, and audio dependencies. | Complete — final GEFV has 1,517 guarded records; eight GESM graphs preserve typed node/DL/vertex/texture ownership; 3,022 commands match checked-in macros; 122 textures/322 levels/25 TLUTs validate and upload with no fallback. |
| R3 | Replace handwritten Swift title authority with portable source-derived C semantics that emit immutable V6 frames. | Complete for the branded boot/File/Mode authority path — Release executes the directly compiled `front.c`/`title.c` target on every even anchor, publishes original-canonical scalar frames, and fails closed on projection/event divergence; odd ticks remain explicitly marked native 120 Hz extensions. |
| R4 | Consume complete source frames through the GE/F3D semantic lowerer and direct Metal 4 renderer with no visible unsupported commands. | In progress — the generic decoder/lowerer preserves source textures, render state, transforms, batching, and per-`gsSPVertex` matrix provenance without changing frozen layouts. Static frontend/Gunbarrel/Cast fixtures, exact GoldenEye LOD/combiner admission, exact stage G_FOG binding, and all-seven stage environment/material lanes pass Metal validation; dynamic skeletal and gameplay-category closure remain open. |
| R5 | Close Legal, Nintendo, GoldenEye, Rareware, File/Mode, Gunbarrel, Cast, and all seven RAMROM-stage surfaces; remove Release fallbacks. | In progress — Cast attachment/texture/render-mode fixtures and deterministic seed-93e5 captures pass, and 76 immutable Cast topologies plus a first-route packet are prewarmed before cadence. Stage room/static-prop scoped frames and source fog pass with mask `0x0`; guard/weapon/effect/HUD pages remain unsupported. |
| R6 | Use one 120 Hz title/menu/cast timeline, exact 60 Hz RAMROM authority with 120 Hz presentation, source-clock audio, and fixed-60 presentation. | In progress — owner, original-paired authority, Gunbarrel even-anchor parity, File/Mode half-step rebasing, audio source clock, BLOOD_COMPLETE handoff, and all-14 RAMROM orchestration pass focused tests. Physical 120/60 evidence, sustained live dynamic-scene cadence, and complete guard/weapon gameplay authority remain open. |
| R7 | Validate Faithful HD, deterministic 320×240 reference output, opt-in adaptive widescreen, traces, screenshots, sanitizers, cadence, signing, and handoff. | In progress — fresh signed Release, deterministic Cast reference repeat, all-seven stage environment Metal validation, all-14 gameplay-camera checkpoints, inspected supplied-drawable stage trace, and sanitizer gates pass; active-display cadence and Release supplied-drawable Cast/gameplay capture remain blocked by the current login-window session. |

Selected defaults are Faithful HD with the authored 440×330 composition,
deterministic 320×240 reference output, and opt-in adaptive widescreen. The
validation oracle is source-only: completion may claim source-complete native
output, but not pixel-perfect or hardware-identical N64 output.

## Acceptance Gates

- No ROM/emulator path is present in the runtime or application bundle.
- Every even native tick matches the independent 60 Hz source projection for
  title timers, transitions, selections, and hashes; odd ticks provide
  distinct deterministic continuous states.
- Boot audio and visual transitions are source-ordered and source-permitted;
  no production auto-skip is introduced.
- On a real 120 Hz display, Release/fullscreen evidence shows 119–121 logic
  ticks/s, median presentation near 8.333 ms, no one-second window under 110
  presented fps, p95 presentation no greater than 10 ms, and no dropped logic
  or fatal debt. On fixed 60 Hz, presentation is 59–61 fps while logic remains
  119–121 ticks/s with matching hashes.
- Audio timestamps remain within one native tick of visual cues, with no
  underrun or dropped-event evidence after preroll.
- File Select persistence and recovery tests cover fresh, copied, erased,
  interrupted, corrupt-primary, corrupt-backup, and unknown-newer-schema
  cases.
- All 14 RAMROM demos parse and execute in explicit test selection with zero
  checksum/RNG divergence; no-input production selection remains source
  randomized.
- Metal API/shader validation, ASan/UBSan, TSan/leak checks, resize/display
  migration, focus loss, shutdown, and inspected GPU captures pass. Screenshots
  and local captures remain native-port evidence, not N64 pixel-parity proof.

## Hard Stops

Stop with a documented blocker only if canonical source/reference evidence or
required assets are missing or mismatched; an earlier ABI/hash cannot remain
unchanged; a required exercised graphics command cannot be lowered; a RAMROM
record diverges after timing/save/input restoration; required Metal 4 APIs are
unavailable; or measured 120 Hz acceptance cannot be reached after bounded,
evidence-driven optimization.

## Autonomous Execution

Preparation, execution, validation, and handoff proceed through all milestones
without milestone-by-milestone approval requests. Luna-max workers use
disjoint file ownership; the primary agent owns ABI reconciliation, project
integration, `.porting` artifacts, and final acceptance. No worker commits,
pushes, branches, resets, cleans, or removes unrelated artifacts.

## Current Implementation Evidence

### Fidelity recovery refresh — 2026-08-19

- Release now publishes `originalCanonical` even-anchor frames from the
  directly compiled unchanged `front.c`/`title.c` target. The richer native V6
  event arrays are retained only as verified lowering sidecars; deliberate
  source/native projection mutation fails closed. Odd frames are labeled
  `native120Extension`.
- File Select and Mode Select now use private paired-anchor rebasing: odd
  cursor/mode frames apply a Q16 half-step, even frames restore and commit the
  exact source endpoint, idle advances only on source anchors, and odd input
  actions commit once. Frozen File/Mode layouts remain unchanged.
- The source GBI decoder now emits an independent 44-byte vertex-load
  provenance sidecar and a one-pass combined decode API. Mixed triangles keep
  the model-view active at each `gsSPVertex` load; frozen
  `GEGBIResultV6` (`1,020,056` bytes) and `GEGBIDrawV6` (`64` bytes) remain
  unchanged. Static GBI builder strict/ASan/UBSan validation passes with prior
  title counts and hashes unchanged.
- Corrected stage preparation now contains 179/179 sidecars, 4,237 payloads,
  436 textures, 248 TLUTs, and 3,575 bindings. All seven prop composition
  manifests pass; the exact remaining unsupported stage mask is `0x38`
  (characters/effects/HUD families).
- All-14 RAMROM gameplay orchestration passes strict/ASan/UBSan twice with
  deterministic aggregate `4035581654071229827`, real Dam movement, and
  restore. Guard/door and weapon/effect owners expose precise missing AI,
  pose, transform, and resource evidence rather than promoting fixtures.
- The integrated SwiftPM Release product builds with Swift warnings-as-errors.
  R0 and frozen V1–V4 replay/hash guards pass unchanged. Build success remains
  separate from visual and physical cadence acceptance.
- Current visual blockers are preserved, not hidden. Cast's exploded/fan
  geometry is fixed by exact address-range vertex loads plus the C provenance
  sidecar; the Metal-validated seed-93e5 capture is upright and recognizable,
  and source-preserving topology/first-route caches now prewarm before cadence.
  Full roster/text/fade, facet/blend cleanup, sustained dynamic cadence, and
  live supplied-drawable Cast evidence remain open. The earlier unscoped
  gameplay-camera stage run 15 moves correctly but projects most room geometry
  far outside NDC and fails demo 2 with zero surviving triangles, so it is not
  accepted visual evidence; the newer scoped V7 lane is tracked separately.
- Production crash recovery (2026-08-20): the attached owner-thread SIGTRAP
  was a Swift duplicate-key trap in Rareware producer setup at
  `goldeneye_gbi_scene_builder_v6.swift:1071`, not a Metal fault. Producer
  setup ordinals now live outside the source command namespace, collisions
  return a typed fail-closed error, and `GEGBISourcePacketV6` is heap-owned
  during construction so the owner thread cannot overflow its stack. The
  product also supplies the validated Rareware vertex overrides, merges the
  full Cast model catalog into the matrix provider, rebases Gunbarrel indices,
  and exports the prepared Gunbarrel sidecar through launch scripts. Focused
  GBI/Gunbarrel/owner/route lanes pass; a live 30-second Release route reaches
  Gunbarrel without a crash, but still hits the explicit 240-tick debt guard
  while dynamic Gunbarrel scenes are rebuilt, so 120-Hz production cadence and
  hands-off Cast submission remain open.
- A bounded topology cache now reuses the compiled Gunbarrel GESM scenes and
  texture-setup rows while retaining per-tick source pose/matrix lowering;
  the cache does not reuse mutable Metal state or skip C authority ticks. The
  owner no longer overflows its stack, and the latest route reaches the
  source Gunbarrel mode-3 transition without a memory fault. A measured
  capture audit still reports approximately 33 ms p95 for full dynamic model
  builds, so sustained 120-Hz title/cast performance is not yet accepted.
- The source blood boundary is now wired through the product result mailbox:
  a frame containing the typed BLOOD_TICK event returns EXECUTED|BLOOD_COMPLETE
  rather than DRAW-only. The paired-authority regression proves the previous
  DRAW-only gap and the source transition trace proves Gunbarrel modes 2...9
  and GoldenEye at tick 3422.
- The GBI builder now heap-caches immutable packet/decode/provenance topology
  keyed by source packet/scene/matrix handles; negative missing-resource tests
  remain isolated by the complete key. This removes repeated C decode and
  vertex-resource construction from the live dynamic path, but the measured
  owner still reaches only about 111 logic ticks/s before the explicit debt
  guard. A GPU-side pose/reframe path or equivalent source-preserving CPU
  optimization is still required for the final 120-Hz gate.
- Stage texture preparation now links palette handles in the A9 namespace
  (`0xA9000000 | texture low24`); the seven-stage source environment, TLUT,
  strict/sanitizer, and Metal capture lanes pass. Fog is source-described but
  remains production fail-closed until the generic scene contract carries a
  typed per-fragment fog coordinate. RAMROM player/camera and playback pass;
  guard AI pages, exact weapon model hashes/transforms, and effect templates
  remain explicitly absent and therefore sourceReady=0.
- Additive V7 gameplay-camera packet preparation now consumes copied player/
  camera input plus guarded stage scene/material/sidecar catalogs, emits a
  non-identity camera and room+static-prop source-visible subset, and passes
  strict/ASan/UBSan for demo 0 on stages 33 and 34 (`197/197` and `267/267`
  drawable props, scoped unsupported mask `0x0`, full-scene mask `0x38`). The
  later continuation wires the adapter into the opt-in owner/Release
  submission path for validated type-1 dynamic doors; full stage
  gameplay/rendering remains open.

- `swift build -c debug` passes with the additive V5 native sources, title
  geometry renderer, owner scheduler, input mailbox, save runtime, realtime
  audio bridge, title route, and RAMROM parser/playback sources.
- `scripts/test_classic_combiner_replay.sh` and
  `scripts/test_m12_classic_combiner.sh` still pass the frozen V1–V4 values.
- `scripts/prepare_native_boot_assets.sh` passes the external ROM guard and
  produces 31 title/audio/RAMROM assets plus eight source-derived `.gepk`
  geometry packets, guarded Rareware `.getx` atlas, and guarded GETI icon
  packet under ignored
  `build/native/boot-assets/` with
  `rom_copied_into_bundle=false`. `scripts/prepare_native_stage_assets.sh`
  independently passes all 21 Dam/Facility/Runway/Bunker I/Silo/Frigate/Train
  background/STAN/setup rows under ignored `build/native/stage-assets-image-decoder-v6/`.
- `scripts/test_audio_engine_v5.sh`, `scripts/test_audio_effects_v6.sh`,
  `scripts/test_audio_output_v5.sh`,
  `scripts/test_ramrom_v5.sh`, `scripts/test_ramrom_playback_v5.sh`,
  `scripts/test_stage_v5.sh`, `scripts/test_title_route_v5.sh`,
  `scripts/test_title_reference_v5.sh`, `scripts/test_native_title_geometry.sh`,
  `scripts/test_native_title_icons.sh`, `scripts/test_stage_scene_packet.sh`,
  `scripts/test_stage_setup_packet.sh`, `scripts/test_title_layout.sh`, and
  `scripts/test_title_sfx.sh`
  pass their strict and sanitizer
  lanes. The Swift RAMROM playback-service and stage-asset-catalog smokes
  pass, as does `scripts/test_stage_resource_loader.sh`; input, save/runtime,
  title-flow, owner, and V5 contract smokes pass.
- `scripts/test_classic_raster_v5.sh` passes strict and ASan/UBSan vectors for
  the additive M9 sidecar. The M12 runtime records a resident
  `GoldenEye.M9.ClassicCombiner.Depth` texture, uses labeled depth-stencil
  states, and preserves the frozen V4 hashes; Metal validation and M12 GPU
  inspection remain clean. The M9 aggregate hash is
  `2633078999532620274` with state hashes
  `7950540911125037649`/`11514046475163631228`.
- `scripts/test_native_title_textures.sh` passes the additive GETT lane: 92
  records, source/decoded hashes, reserved-field and tamper rejection, C
  layout strict/ASan/UBSan, and Swift parser validation. The signed title
  renderer loads four packets, binds resident first-level RGBA8 textures, and
  records GoldenEye’s preserved 696-byte source mip tail as base-level-only
  evidence rather than claiming full mip upload.
- `scripts/test_title_raster_v5.sh` passes eight source-derived title raster
  tuples with aggregate hash `11519430422207814888`; `scripts/test_native_projection_v10.sh`
  passes strict/ASan fixed-width projection, clipping, culling, and rational
  viewport vectors with packet hash `15192084148729639549`.
- `scripts/test_native_title_raster_catalog.sh` passes the C-to-Swift
  value-only title-raster catalog (`states=8`, aggregate
  `11519430422207814888`), associating source state hashes with title screen
  evidence while keeping forced-blend/coverage behavior explicitly deferred.
- `scripts/test_native_title_projection_evidence.sh` consumes all eight guarded
  GETP title packets through Projection V10 and passes strict/ASan with
  aggregate evidence hash `17378376777734745904`.
- `scripts/test_native_title_uv.sh` passes the additive GETU lane with 1,251
  signed-UV/material corners (Legal 36, Nintendo 192, GoldenEye 1,023),
  source command/vertex hashes, and strict C/ASan/UBSan/Swift packet guards;
  GETU remains prepared/parsed evidence and is not yet a title draw path.
- The signed Release title runtime supports the explicit
  `GOLDENEYE_TITLE_GETU_DRAW=1` opt-in path. A Metal API/shader-validation
  launch records three GETU resources (`drawIndices=6/192/852`, skipped
  corners `30/0/171`) with `titleUVDrawEnabled=1` and no validation faults;
  fullscreen/GETT remains the default route.
- `scripts/test_stage_background_draw_packet.sh build/native/stage-assets-image-decoder-v6`
  passes the bounded M27 diagnostic overlay foundation for all seven scenes
  (`rooms=468`, `portals=612`, `commands=1080`, `vertices=4032`, aggregate
  `4308406056569914737`) and compiles its standalone Metal shader; source room
  triangles and stage object/effect rendering remain unsupported.
- The signed Release `GOLDENEYE_M27_STAGE_OVERLAY=1` route renders the bounded
  stage-33 diagnostic packet (`rooms=137`, `portals=194`, `commands=331`,
  `vertices=1210`, `frames=3`, `draws=993`, `privateVertex=1`,
  `uploadComplete=1`, `lastError=none`) under Metal API/shader validation;
  this remains room/portal overlay evidence only.
- `scripts/test_audio_long_soak_v5.sh` passes a deterministic 600-second-
  equivalent source-clock/ring soak (`ticks=72000`, `frames=13230000`, PCM
  hash `14458218251061804860`, zero underruns/drops); this remains synthetic
  evidence rather than live AVAudio mix/A/V proof.
- `scripts/test_native_title_nodes.sh` passes the new GETN packet lane: four
  frontend models, 138 nodes, 92 texture metadata rows, and deterministic
  packet hashes. The signed title runtime loads all four packets and records
  `titleNodeCount=4 titleNodeNodes=138 titleNodeTextures=92` without retaining
  source pointers or raw display-list words.
- `scripts/test_ramrom_all14.sh build/native/boot-assets/ramrom build/native/stage-assets-image-decoder-v6`
  passes all 14 demos twice (`runs=28`, `abort_restore=14`) through strict,
  ASan/UBSan, Swift-service, and seven-stage scene preparation lanes.
- `scripts/test_stage_setup_packet.sh build/native/stage-assets-image-decoder-v6` passes strict,
  ASan, and UBSan setup/portal parsing with 2,225 objects, 2,230 pads, 612
  portals, and aggregate setup hash `1099511628177`.
- `scripts/test_stage_gameplay_runtime.sh build/native/stage-assets-image-decoder-v6 build/native/boot-assets`
  passes strict/ASan/UBSan over all seven stages and one RAMROM trace with
  1,578 samples, deterministic aggregate `4774828755625742329`, and explicit
  effects/AI/weapons/collision diagnostics.
- `scripts/build_native_boot.sh` produces a signed
  `build/native/boot-runtime/source-faithful/GoldenEyeHost.app` with the title
  metallib.
  `scripts/run_native_boot.sh` launches the native title path and schedules
  the Nintendo/gunbarrel/File Select tracks through the owner-refilled
  22,050 Hz SPSC/source-node path, with the AVAudioPlayerNode fallback kept
  for route failures.
- A captured title frame is preserved at
  `build/native/boot-runtime/goldeneye-title.gputrace`: one labeled Metal 4
  title pipeline/draw, a 960×540 BGRA8 drawable, prepared title texture and
  supplied-drawable presentation sequence. The inspected output is preserved
  as `build/native/boot-runtime/goldeneye-title-gpudebug-output.png`.
- The current M15 capture is additionally preserved at
  `build/native/boot-runtime/goldeneye-title-m15.gputrace`; `gpudebug` shows
  one `GoldenEye.M15.Title.RenderEncoder` with the fullscreen pass plus the
  source-derived geometry draw and a 960×540 BGRA8 drawable.
- Current runtime screenshots include `/tmp/ge-boot-current-2.png` (prepared
  gunbarrel background), `/tmp/ge-gunbarrel-5.png` (native head/suit/WPPK
  packet draws), `/tmp/ge-current-window.png` (interactive Mode
  Select), `/tmp/ge-goldeneye-current.png` (attract placeholder), and the
  current durable Mode Select capture at
  `build/native/boot-runtime/native-mode-select-final.png`. These are native
  runtime evidence only and do not claim N64 pixel parity.
- Signed fullscreen HUD evidence on the local 120 Hz-capable screen reports
  repeated 8.33 ms presentation intervals. The windowed fixed-60 screen
  correctly reports 16.68 ms; this is expected display behavior, not a logic
  rate change.
- A clean windowed Release run logged `state=stopped`, `ticks=1761`,
  `callbacks=878`, `unexpectedCallbacks=0`, `resizeApplies=2`, and
  `suppliedDrawable=1`; the same fullscreen run logged `ticks=1422` and
  `callbacks=1244` during screen migration. These are pacing/ownership
  telemetry, not the final sustained 120 Hz acceptance gate.
- The latest clean runtime shutdown logged `ticks=1201`, `callbacks=1166`,
  zero unexpected/marshaled/unhandled callbacks, `lastError=none`, and
  geometry handles `1,3,4,5,6,7,8,9` (Rareware, GoldenEye, Legal, Nintendo,
  walletbond, head, suit, WPPK) with `preparedRareware=1`, a 64×86 atlas,
  seven GETI icon rows, and
  `titleTextCount=287` from the guarded `LtitleE` catalog.
- The latest signed Release windowed run logged `ticks=1530`,
  `callbacks=1519`, `targetDeltaMinMs=7.8353`,
  `presentedTimeSamples=1508`, and `lastError=none`. A subsequent explicit
  RAMROM demo-0 run reached `stage=33 sceneReady=1`, consumed all 454 packets,
  and returned a `kind=returnToTitle` event with matching recording/RNG hashes;
  this is stage-scene/runtime evidence for one demo, not the all-14 gameplay
  acceptance gate.
- `scripts/test_ramrom_all14.sh build/native/boot-assets/ramrom build/native/stage-assets-image-decoder-v6`
  passes `demos=14 runs=28 abort_restore=14`, all seven stage packets, and
  strict/ASan/UBSan/Swift service lanes; gameplay/renderer remain STUB(M26/M27).
- `scripts/measure_native_runtime.sh` now emits signed Release logic/target/
  presented/focus/migration/resize telemetry. Current automated direct-launch
  runs prove ~120 Hz logic but remain unproven for sustained presentation
  because the local WindowServer path intermittently throttles the display
  link (target p95 about 1 s, zero presented-time samples); this is an active
  runtime-fix/evidence lane, not a completion claim.
- Remaining unimplemented scope is explicit: full title model/display-list
  texture/combiner/material lowering beyond the bounded source-colored Legal/
  Nintendo/GoldenEye/Rareware packets and atlas, source fonts/wallets and
  Rareware material/mip parity, complete source audio mix/long-soak A/V,
  full stage gameplay systems and Metal scene rendering, and
  RAMROM execution against real stage gameplay.
  The current title visuals combine source-derived geometry, the prepared
  gunbarrel RLE background, and source-shaped frontend passes; they do not
  claim N64 pixel parity.

### Validation refresh — 2026-08-18

- Final signed Release rebuild passes after the latest native title owner and
  input mapping edits. The app bundle remains free of private ROM/payload files;
  the external ROM boundary and SHA-1 are unchanged.
- The focused strict/ASan/UBSan lanes pass for frozen V1–V4 replay, title
  reference/route/layout/text/icon/geometry/SFX, audio V5/V6, stage setup/
  scene/gameplay, all-14 RAMROM, and owner runtime. `swift build` and
  `git diff --check` pass.
- A bounded Release launch with `MTL_DEBUG_LAYER=1`,
  `MTL_SHADER_VALIDATION=1`, and stderr reporting emitted no Metal or shader
  faults. Preserved `gpudebug` inspection covers the labeled supplied-drawable
  M15 title encoder and bindings.
- The title renderer keeps all guarded GETP packets available for evidence but
  suppresses unsupported branded geometry by default; setting
  `GOLDENEYE_TITLE_PARTIAL_GEOMETRY=1` enables the diagnostic draw path. This
  removes known opaque white-block artifacts without claiming the missing
  source material/display-list lowering is complete.
- Cadence remains an active evidence gap: logic is near 120 Hz and target
  intervals match the named displays, but this WindowServer automation path can
  throttle callbacks and return no nonzero `presentedTime` samples. The goal
  stays in progress until sustained 120/60 presentation and the remaining
  source/gameplay/rendering parity gates are measured.
- The refreshed cadence harness can wake the display and run a no-stress
  baseline. The latest awake baseline measured logic `119.9939 Hz` on the
  named 120 display and `119.9873 Hz` on the named 60 display with zero dropped
  ticks, but only 25/19 callbacks and zero nonzero `presentedTime` samples;
  presented-fps acceptance remains unproven.
- The cadence-owner audit reproduced callbacks `3` with ~120 Hz logic, zero
  render failures, and zero presented-time samples while
  `CGDisplayIsAsleep(CGMainDisplayID())` reported `active=0 asleep=1 online=1`.
  Bounded `caffeinate` increased callbacks to `13/17`, identifying display/
  compositor backpressure. This is evidence, not a hard blocker; acceptance
  must be rerun on an active visible display.

### Autonomous validation refresh — 2026-08-21

- Rebuilt and re-signed the canonical source-faithful Release app at
  `build/native/boot-runtime/source-faithful/GoldenEyeHost.app` from the
  external ROM. Bundle verification and frozen Release history/provenance pass;
  the executable SHA-256 is
  `e8c0636bf0d8e7daeea9593ed40ca9e2c690c0927d1503e789450a870d49797e`.
- The V7 gameplay-camera seam is integrated at both owner and product renderer
  boundaries behind `GOLDENEYE_STAGE_GAMEPLAY_CAMERA_V7=1`. Strict, ASan, and
  UBSan evidence passes for demo 0/stages 33 and 34 with camera hashes
  `17166107536987602611`/`9901855664259801205`, static props `197/197` and
  `267/267`, scoped `unsupportedMask=0x0`, retained full-scene `0x38`, and
  deterministic packet/composition hashes. The owner writes an explicit
  submission record; unsupported categories are not cleared or hidden.
- Cast source repair covers source-row/full-handle texture aliases, per-model
  source render modes, embedded-head attachment handling, and fail-closed
  vertex provenance. Strict/ASan/UBSan attachment and chrfnp90 builder lanes
  pass (`commands=64`, `setups=7`, `vertexResources=10`, `draws=7`,
  `unsupported=0`). A strict Metal API/shader-validated Cast reference
  capture and byte-identical repeat pass with reference raw hash
  `15e657b9a47b3fca22cb03ad45127b329283623963edd03253aed4de38e0051f` and
  Faithful HD raw hash
  `cbeaee5f72a0589c3718d57505aade826574e5d12973704cf8eac19397b95b92`.
- Before cadence begins, the product prewarms 76 immutable Cast GESM/texture
  topologies in `6,603,487 us` and a deterministic first-route three-model
  builder packet in `67,374 us`; live pose, attachments, matrices, and hashes
  remain per-tick source work. This is a source-preserving cache, not a debt
  limit relaxation or fallback path.
- Fresh all-seven stage environment captures pass Metal API/shader validation
  with `nonBlack=1` and `textured=1` for every stage. Fresh all-14 gameplay-
  camera checkpoints pass (`42` records); the stage gameplay runtime remains
  bounded and reports explicit `effects,ai,weapons,collision` diagnostics. The
  supplied-drawable stage binding probe passes and produces the inspected trace
  `build/native/m27-stage-background/goldeneye-m27-stage-background.gputrace`.
- The actual AppKit Cast production attempt produced
  `build/native/cast-production-route-v6/cast-topology-prewarm-20260821/` with
  the prewarm logs and `blocker.txt` (`castSubmit=0`, `latestCrash=none`). The
  owner stopped advancing around source tick 2876 in the current
  login-window/headless session before the Cast transition; this is retained
  as a display/session evidence blocker, not promoted to a Cast source failure.
- Final short Release cadence evidence is retained at
  `build/native/boot-runtime/cadence/runs/20260821-final-headless-v2/`: the
  120 case measured `logicTickRateHz=119.9995`, `droppedTicks=0`, callback p95
  `1.45 ms`; the fixed-60 case measured `logicTickRateHz=120.0041`,
  `droppedTicks=0`, callback p95 `1.75 ms`. Both cases had
  `presentedTimeSamples=0`, `presentedFPS=0`, and the harness returned `pass=0`;
  active visible WindowServer presentation evidence remains required.
- Dynamic source-pose optimization now caches immutable texture-coordinate and
  correction-matrix work while preserving C pose/matrix semantics and scene/
  render hashes. Suitbond production-shaped timing improved from
  `p50/p95=29,281/29,719 us` to `11,437/11,509 us`; Release `-O` timing is
  `1,122/1,154 us`. GBI and chrfnp90 strict/ASan/UBSan lanes remain green.
- The exact GoldenEye logo LOD/combiner tuple is now admitted only for
  `OtherMode.H=0x00112000`, `OtherMode.L=0x0C182048`, and the guarded
  `0x26A004/0x1F1093FF` selectors. Strict/ASan pipeline corpus and two
  Metal API/shader-validated captures pass with `162` source commands,
  `339` triangles, `7` mips, `2` materials, and zero unsupported work. Both
  320x240 raw captures hash
  `4eec74efa4d3fadbdb78ebdef982cc1cea5a13efec5eb1751512f046eb8c2a23`; the
  Faithful HD raw hash is
  `f7ec1001fd8690fff46fe9e26ecb8e6f297ec568300dcda5fd69090afaef4cd3`.
- Fog now has an exact source `gSPFogPosition` fixed-point contract and
  strict/ASan/UBSan coverage (`stages=7`, `enabled=4`, aggregate
  `9870053433528827143`). The production shader consumes signed `fm/fo`,
  source fog color, and a screen-linear clip-Z/clip-W varying only for
  `G_FOG + G_RM_FOG_SHADE_A`; `G_RM_FOG_PRIM_A` and malformed fog modes remain
  fail-closed.
- Final short cadence evidence for the `d74d1ee9...` Release is retained at
  `build/native/boot-runtime/cadence/runs/20260821-final-lod-headless/`: the
  120 case measured `logicTickRateHz=119.9913`, `droppedTicks=0`, callback p95
  `1.85 ms`; fixed-60 measured `logicTickRateHz=120.0021`, `droppedTicks=0`,
  callback p95 `1.75 ms`. Both cases had zero presented samples and the
  harness returned `pass=0` under the current headless WindowServer session.
- The stage packet now carries a parallel source eye-space-Z array computed
  from the camera model-view before projection and preserved through
  homogeneous clipping into the copied scene snapshot/GPU vertex view; the
  historical 32-byte stage vertex and frozen C ABI remain unchanged. Seven
  stage source-environment strict/ASan/UBSan lanes pass with the updated packet
  aggregate `10879306652781644554`. The eye/fog sidecars use distinct hash
  domains, survive homogeneous clipping, composition, and V7 scoped snapshots,
  and retain the full-scene `0x38` category mask.
- A packet-coordinate-only Release rebuild then passed strict codesign,
  Release history/provenance, debug build, Metal source-scene, host ASan/UBSan,
  fog-lowering, source-scene corpus, and V7 gameplay-camera packet lanes. The
  current canonical executable hash is
  `e8c0636bf0d8e7daeea9593ed40ca9e2c690c0927d1503e789450a870d49797e`;
  the fresh all-14 gameplay-camera capture passes 42 checkpoints with Metal
  API/shader validation, while physical presented timestamps remain absent.
- The exact fog/payload continuation also passes the fresh stage environment
  and V7 strict/ASan/UBSan lanes after distinct eye/fog hash domains were
  added. V7 packet hashes are `11113608939106626920`/`15466404641097031372`,
  and repeated Cast reference raw hashes are
  `7edb15fd82da9181bf71c25686f6dd818feed24241a12373f6d357c4be95099d` and
  `765f3c385fd58e8bbcf42b3a8f658d5eeb21a67b10bb3bd24b835d039226fe2a`.
- Follow-up dynamic-category audits found no source-complete guard/character,
  HUD, or effects slice to lower safely next: authoritative animation,
  head-RNG/SwitchNode attachment, render-context, and live weapon/inventory
  producers are still missing. Their unsupported diagnostics remain explicit.

### Scoped gameplay-camera production evidence — 2026-08-21

- Added scripts/test_stage_gameplay_camera_production_capture_v7.sh and
  native/tests/goldeneye_stage_gameplay_camera_production_capture_v7_smoke.swift.
  It consumes the V7 demo-scoped room/static-prop composition through the
  direct Metal supplied-drawable renderer, checks non-identity camera/
  projection, requires every requested prop placement to draw, and records
  packet/composition/render hashes with raw/PNG/JSON artifacts.
- Fresh code-side V7 evidence remains demo 0/stages 33 and 34, props 197/197
  and 267/267, scoped mask 0x0, retained full-scene mask 0x38, deterministic
  1, and fail-closed 1. The production harness compiled cleanly, but this
  host has no Metal 4 device; its pixel/supplied-drawable run is explicit
  SKIP and does not close the physical/gputrace gate.

### Source head-selection continuation — 2026-08-21

- Added a value-only head-selection authority that mirrors the exact
  bodiesReset/bodyChooseHead seed boundary: three reset transitions, male
  offset consumption, female current-index reuse, and explicit-head
  no-consumption behavior through the existing C random transition.
- Character snapshots can consume that selected-head record, but the
  animation, render-context, and SwitchNode attachment requirements remain
  fail-closed. Strict/ASan/UBSan head-selection and full character-scene
  validation pass; all 14 real-demo character rows remain non-presentable.
- Rebuilt the signed Release after this additive seam. The current executable
  SHA-256 is c93c0c0a297ad99e4ef43dbdae5cf8a2a83791b0e66fe76a8a10f124bf96398b.
  Release history/provenance passes with the external ROM boundary intact.

### Projection, dependency, and title-material continuation — 2026-08-21

- Stage gameplay projection now follows raw source viSetZRange values and
  maps source symmetric depth into Metal depth, with a separate
  source-symmetric fog sidecar. Stage environment and V7 strict/ASan/UBSan
  gates pass; current aggregates are 2034083543171337301 and V7 packet hashes
  10787550995629497797/5096764590307538101.
- Type-9 setup dependencies now derive bodyID from GuardRecord.bodyAI rather
  than chrnum. The corrected manifest is references=1783/unique=141, with
  Dam bodyID 37 mapped to greatguard2. Body/character joins now consume the
  corrected source offset contract while retaining animation/attachment
  fail-closed diagnostics.
- Added a GESM title material contract smoke: 92 textures, 199 mip payloads,
  two TLUT records, deterministic aggregate
  4247163796f6616e44965ad3ad846d5de46311005d75984f9a4a7be9c201d848, and
  strict/ASan/UBSan pass. GPU TLUT consumption remains unclaimed.
- Rebuilt the signed Release; executable SHA-256 is
  5cf6baf72fed8f6ba855d924f111e0dad418c2c7b105306364e644eebf4b9f4f.

### Additive STAN topology continuation — 2026-08-21

- Preserved source `StandTilePoint.link` records in an additive V7 sidecar;
  frozen V6 tile layouts remain unchanged. The topology-aware player-camera
  step constrains cross-room acceptance to authored linked target tiles and
  rejects disconnected-room movement.
- All 14 routes pass strict/ASan/UBSan with deterministic link counts
  Dam/Facility/Runway/Bunker I/Silo/Frigate/Train =
  `6750/5748/1210/2760/6050/4230/1488`; the orchestrator aggregate is
  `1689065738426998688` (topology-enabled player-camera smoke) and
  `4410795521714608326` (orchestrator). Full portal geometry, level-scale conversion, door
  collision, and complete edge-slide parity remain open.

### Source portal geometry continuation — 2026-08-21

- Added a value-only V7 parser for all setup portal geometry offsets,
  preserving bounded Q16.16 polygon points, raw room/control metadata,
  deterministic hashes, and fail-closed malformed geometry checks. All seven
  stages/612 portals pass strict/ASan/UBSan.
- Door portal assignment remains open until the source STAN room sample and
  `bgGetPortalBetweenRooms` lookup are implemented; no door or renderer
  unsupported bit was cleared by this parser.
- The page builder now consumes the catalog and source STAN room samples to
  derive `portal_number` for all `397/397` guarded door rows (`67` unique IDs,
  portal hash `13325078266282593292`). Guard pages remain fail-closed and no
  dynamic door draw is claimed.

### Dynamic door source-submission continuation — 2026-08-21

- Added a heap-owned, door-only source owner path. Invalid rows are filtered
  through `ge_guard_door_owner_v6_validate_door`; the C state is copied out in
  32-item pages and never returned by value. The full guard owner remains
  separate with `sourceReady=0`, preserving the character/AI fail-closed
  boundary.
- The Dam environment route publishes four dynamic doors with source object/
  model/portal identity, lifecycle/open state, Q16.16 position, source hash,
  interpolation/anchor flags, and all sixteen transform words. Odd/even 120 Hz
  stepping follows the C interpolation/source-row contract. Restore snapshots
  copy the owner bytes and verify a replayed dynamic publication; strict,
  ASan, and UBSan output reports `environmentDynamicDoors=4 dynamicRestore=1`.
- V7 gameplay-camera submission accepts only visible setup objects with source
  type `1`, finite sixteen-word Q16.16 transforms, and a nonzero source hash.
  The stage-33 dynamic fixture hashes are packet
  `3209083801982227650` and composition `9272436217739127194`; it keeps
  scoped mask `0x0` while retaining full-scene `0x38`. No unsupported category
  is cleared without the scoped source-visible contract.
- Fresh focused gates pass: V7 packet, portal geometry, guard/door pages, and
  all-14 gameplay orchestrator strict/ASan/UBSan lanes. The supplied-drawable
  production harness compiles with Metal API/shader validation but explicitly
  SKIPs on this host because no Metal 4 device is available.
- Fresh signed Release executable SHA-256 is
  `6e81f6faaf9cda114e014cfc970a3c7422afb615618822efd3abace28490dde4`;
  stage preparation reports `resources=21`, and frozen Release provenance
  remains passing. Physical 120/60 presentation, live Cast/gameplay supplied-
  drawable capture, and full characters/AI/effects/HUD/weapons/collision
  parity remain open.

### Unified gameplay/traversal and active-display continuation — 2026-08-21

- Added a fixed-width V7 player-camera-to-gameplay bridge. The authoritative
  player/camera publication now updates the gameplay player row and camera
  fields with recomputed state/render/audio/event hashes, while preserving all
  unsupported object categories. Direct C strict/ASan/UBSan passes
  (`layout=176 direct=2 eventHash=1`); all-14 orchestrator strict/ASan/UBSan
  passes with equality assertions, aggregate `3432588557158677409`, and
  `environmentDynamicDoors=4`.
- Added source `levelscale` conversion across the seven-stage STAN/pad/world
  path and bounded source-style edge-slide projection with authored link edges
  excluded as walls. All 14 player/camera routes pass strict/ASan/UBSan with
  aggregate `5860224076221260218` and `stanEdgeSlide=1`; frozen V6 layouts and
  full-scene `0x38` remain intact.
- Fresh V7 stage packet sanitizer lanes pass. Stage 33/34 retain props
  `197/197` and `267/267`, scoped mask `0x0`, full-scene `0x38`; current packet
  hashes are `4344127377687538898`/`2739797606600666455`, and the stage-33
  dynamic fixture hashes are `2020772946810887752`/
  `17747242490227606699`.
- Active Aqua evidence improved the presentation boundary: fixed-60 reached
  `59.951 FPS` with zero rejected samples, while 120 Hz reached `118.653 FPS`
  short-run and `119.273 FPS` over six seconds with readiness/rejection gaps.
  Supplied-drawable stage rendering reached the renderer but failed closed on
  missing decoded GBI lighting state `0xe2100001`; no gameplay pixel/gputrace
  acceptance is claimed. Character/attachment promotion remains unsafe.
- Rebuilt signed Release executable SHA-256:
  `97adbc3668b1b2fef768bfe32972fc0ff592abda0a782107d90e05c281be5e6f`.
  Frozen provenance passes. Physical sustained 120/60 acceptance, live Cast,
  full character/AI/effects/HUD/weapons/collision parity, and the lighting
  state capture remain open.
- Added an explicit serialized/runtime-scaled camera-coordinate domain. The
  player owner publishes runtime units, NativeTitleOwner marks that handoff
  `.runtimeScaled`, and the stage adapter converts back to serialized room
  space before rebasing. Stage source-environment strict/ASan/UBSan passes with
  equivalent-domain matrix checks and aggregate `2034083543171337301`.
- The display-link runtime now carries a monotonic pause generation, cancels
  queued callbacks on pause, rejects stale drawables across focus transitions,
  and registers presented handlers before `present()`. Owner/runtime smoke and
  headless soak pass (`ticks=241 rate=120.0 dropped=0 maxDebt=1`), but physical
  sustained cadence remains unproven.

### Fresh scoped-lane validation — 2026-08-21

- The V7 gameplay-camera packet, source fog, corrected GuardRecord dependency,
  head-selection, title-material, gameplay-orchestrator, and character-scene
  strict/ASan/UBSan gates were re-run. V7 remains demo 0/stages 33 and 34 with
  props 197/197 and 267/267, scoped mask 0x0, retained full-scene mask 0x38;
  the all-14 orchestrator aggregate remains 4035581654071229827.
- The supplied-drawable production harness compiled with Metal API/shader
  validation and explicitly skipped because this host has no Metal 4 device.
  No physical pixel/gputrace acceptance is claimed. Character rows continue
  to report animation/attachment/render-context gaps rather than clearing
  unsupported bits.
- The bounded C door owner now derives portal activation from the source door
  lifecycle, retaining an active linked portal from open start through close
  completion even at zero displacement. Strict/ASan/UBSan/Swift adapter
  validation reports `portalLifecycle=1`; collision geometry and character
  rendering remain open.
- The canonical source-faithful Release was rebuilt after this C change:
  stage preparation `resources=21`, codesign, boot-release verification, and
  history/provenance pass. Executable SHA-256 is
  `5cf6baf72fed8f6ba855d924f111e0dad418c2c7b105306364e644eebf4b9f4f`.
