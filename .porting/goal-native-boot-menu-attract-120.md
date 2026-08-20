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
| M19 | Gunbarrel | Suit/head/PP7 animation, attachments, flash, background, blood/fades, intro music, and transitions pass. | In progress — prepared gunbarrel background, paired state machine, and intro track/output pass; suit/head/PP7 model/attachment lowering remains pending. |
| M20 | GoldenEye logo | Lighting, texgen/reflection, fade timing, and File Select versus cast routing pass. | In progress — source-derived GoldenEye geometry packet and cast/file routing pass; full texgen/reflection/material parity remains pending. |
| M21 | File Select | Four wallets, source UI, idle return, full folder actions, and adaptive widescreen pass. | In progress — persistent four-folder actions, async save integration, two-stage erase confirmation (default Cancel), source-derived walletbond/icon geometry, 440×330 viewport, inverse hit bounds, and interactive UI pass; full source save/UI parity remains pending. |
| M22 | Mode Select | Navigation, availability, back behavior, and persistence pass. | In progress — interactive navigation/back/persistence boundary and runtime screenshot pass; source model/text/multiplayer availability parity remains pending. |
| M23 | Cast reel | Body/head/weapon selection, skeletal animation, source timing, random entries, and exit rules pass. | Implemented as a bounded route seam — 34-entry source order, unlock/guest gates, random/explicit demo selection, abort/restore pass; cast model/animation rendering remains pending. |
| M24 | Native platform services | Memory, DMA/file index, RZIP, arenas, stage lifecycle, and required platform services operate without the N64 scheduler. | In progress — bounded Swift stage catalog plus C 1172/rebase, metadata packet copy-out, decoded-arena views, value-only setup/portal packets, and owner-side scene-packet preparation validate all 21 prepared rows; full lifecycle/platform replacement remains pending. |
| M25 | Demo-stage loading | Dam, Facility, Runway, Bunker I, Silo, Frigate, and Train scene/setup data load through deterministic handles. | In progress — all seven stage families now load bounded decoded payloads, 468 background rooms, 2,225 setup objects, 2,230 pads/bound pads, 612 portals, and deterministic scene/setup hashes; gameplay and Metal scene consumption remain pending. |
| M26 | Demo gameplay core | Demo-reachable player/camera/collision, props, doors, guards, AI, objectives, weapons, effects, and paired cadence run headlessly. | In progress — bounded native stage runtime now owns fixed-point player/camera state, pad lookup, room/portal traversal, door/guard/objective summaries, deterministic 120 Hz stepping, and abort/restore; collision/AI/weapons/effects remain explicit diagnostics. |
| M27 | Demo renderer | Rooms, sky, props, characters, weapons, particles, glass, explosions, HUD/watch, and fades render through Metal 4. | In progress — bounded stage-background diagnostic draw packets now cover all seven scenes (468 rooms, 612 portals, 1,080 room/portal commands, 4,032 line vertices) through Projection V10 with six explicit unsupported-work diagnostics; source room display lists/geometry, props, characters, effects, and actual Metal stage submission remain pending. |
| M28 | RAMROM playback | All 14 recordings parse, preserve source-anchor packet/RNG consumption and speedframes, support abort, and restore title state. | In progress — all 14 recordings now pass twice (`runs=28`) through strict/ASan/UBSan C and Swift owner-service abort/fade/return/restore validation with matching recording/packet/input/checksum/RNG hashes; all-14 native stage/gameplay execution remains explicitly unsupported. |
| M29 | Integrated acceptance/handoff | Both launch routes, Release signing, 120/60 evidence, validation, sanitizers, capture inspection, and handoff artifacts pass. | In progress — clean signed Release rebuild now passes after the additive raster layout guard was corrected to its actual 928-byte result layout; GETT/GETU/M9/M10/M27 tests, V1–V4 replay/hash guards, stage/RAMROM lanes, and focused sanitizer/Metal compile lanes pass; complete title draw binding, stage/gameplay rendering, and visual/performance acceptance remain pending. |

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
| R4 | Consume complete source frames through the GE/F3D semantic lowerer and direct Metal 4 renderer with no visible unsupported commands. | In progress — the generic decoder/lowerer now preserves source textures, render state, transforms, batching, and additive per-`gsSPVertex` matrix provenance without changing frozen result/draw layouts. Static frontend surfaces and Gunbarrel pass focused Metal validation; dynamic skeletal and stage-camera closure remain open. |
| R5 | Close Legal, Nintendo, GoldenEye, Rareware, File/Mode, Gunbarrel, Cast, and all seven RAMROM-stage surfaces; remove Release fallbacks. | In progress — Legal/Nintendo/GoldenEye/Rareware/File/Mode/Gunbarrel and Cast fixtures have source-driven captures; the live Cast owner route remains performance-limited. Stage palette/TLUT linkage and all seven environment/material packet lanes pass, but fog is typed and fail-closed, gameplay-camera images are not visual closure, and guard/weapon/effect pages remain fail-closed. |
| R6 | Use one 120 Hz title/menu/cast timeline, exact 60 Hz RAMROM authority with 120 Hz presentation, source-clock audio, and fixed-60 presentation. | In progress — owner, original-paired authority, Gunbarrel even-anchor parity, File/Mode half-step rebasing, audio source clock, BLOOD_COMPLETE handoff, and all-14 RAMROM orchestration pass focused tests. Physical 120/60 evidence, sustained live dynamic-scene cadence, and complete guard/weapon gameplay authority remain open. |
| R7 | Validate Faithful HD, deterministic 320×240 reference output, opt-in adaptive widescreen, traces, screenshots, sanitizers, cadence, signing, and handoff. | Pending. |

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
  but full roster/text/fade, facet/blend cleanup, and performance caching remain
  open. Gameplay-camera stage run 15 moves correctly but projects most room
  geometry far outside NDC and fails demo 2 with zero surviving triangles, so
  it is not accepted visual evidence.
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
  background/STAN/setup rows under ignored `build/native/stage-assets/`.
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
- `scripts/test_stage_background_draw_packet.sh build/native/stage-assets`
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
- `scripts/test_ramrom_all14.sh build/native/boot-assets/ramrom build/native/stage-assets`
  passes all 14 demos twice (`runs=28`, `abort_restore=14`) through strict,
  ASan/UBSan, Swift-service, and seven-stage scene preparation lanes.
- `scripts/test_stage_setup_packet.sh build/native/stage-assets` passes strict,
  ASan, and UBSan setup/portal parsing with 2,225 objects, 2,230 pads, 612
  portals, and aggregate setup hash `1099511628177`.
- `scripts/test_stage_gameplay_runtime.sh build/native/stage-assets build/native/boot-assets`
  passes strict/ASan/UBSan over all seven stages and one RAMROM trace with
  1,578 samples, deterministic aggregate `4774828755625742329`, and explicit
  effects/AI/weapons/collision diagnostics.
- `scripts/build_native_boot.sh` produces a signed
  `build/native/boot-runtime/GoldenEyeHost.app` with the title metallib.
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
- `scripts/test_ramrom_all14.sh build/native/boot-assets/ramrom build/native/stage-assets`
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
