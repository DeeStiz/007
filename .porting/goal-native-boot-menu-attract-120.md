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
| M7 | Model/node ingestion | Bounded group, BBOX, DL, BSP, SWITCH, character, LOD, shadow, and attachment nodes copy into handle-based scene data. | Implemented for the bounded source graph — eight GESM sidecars pass typed handle/relationship/metadata validation, all nine required node families are present (225 nodes), the four GETN title packets retain 138 nodes/92 texture rows, and strict/ASan/UBSan plus title-route loading pass. Full geometry/material consumption remains in M8–M10. |
| M8 | Texture/TMEM/TLUT lowering | Required RGBA/CI/IA/I formats, palettes, mip chains, wrapping, clamping, and samplers lower through bounded native records. | Implemented for the bounded source-product path — all eight GESM models produce 122 unique texture descriptors, 322 validated mip levels, 25 TLUT records, exact source sampler/address state, and deterministic strict/ASan/UBSan plans; Metal 4 private full-mip uploads, staging, residency, barriers, and irregular authored dimensions pass. The legacy GETT title diagnostic remains base-level-only and GPU TLUT consumption is explicitly deferred to later material work. |
| M9 | Combiner/raster completion | General required one/two-cycle selectors, primitive/environment/fog colors, depth, alpha, coverage, culling, and render modes are explicit. | Implemented for the bounded source-admitted tuples — `GEClassicRasterStateV5`, title raster V5, canonical combiner replay, source pipeline corpus, exact G_FOG blender admission, alpha/coverage guards, and Rareware/GoldenEye LOD policies pass strict/sanitized validation; unsupported generic RDP tuples fail closed and remain outside the bounded source contract. |
| M10 | Transforms and lighting | Projection/modelview, clipping, normals, lighting, look-at, texgen/reflection, and source quantization produce immutable draw packets. | Implemented for the bounded source-admitted path — Projection V10 Q16.16 matrices, six-plane clipping/culling, explicit projection roles, normal transforms, ambient/directional lighting, reflection texgen, source fog coordinates, and per-draw model-view/geometry-mode records pass strict/ASan/UBSan and Metal 4 shader validation. Linear texgen and generic unclassified look-at/material variants remain typed fail-closed gaps. |
| M11 | 2D and adaptive layout | Fills, scissor, rectangles, fonts, icons, fades, 440×330 safe layout, wide anchors, and inverse hit testing pass at 4:3, 16:9, and ultrawide. | Implemented for the bounded source 2D/layout path — guarded GETF/GETC/GETI packets, File/Mode fills/scissors/erase overlay, source font rows, 4:3 320×240 and Faithful-HD 1760×1320 layout checks, adaptive letterboxing, and inverse hit testing pass; physical visual presentation and complete source UI parity remain acceptance gates. |
| M12 | Audio parsing | Guarded instrument/SFX banks and boot/menu sequences parse with bounded backreferences, loops, varints, and malformed-stream rejection. | Implemented — strict C smoke renders all three boot tracks and validates guarded banks. |
| M13 | Native synth | 22,050 Hz deterministic synthesis supports voices, envelopes, loops, pitch/pan/gain, composite SFX, reverb, and block-size-independent hashes. | Implemented for the bounded native synth/effects contract — V5 voices/envelopes/loops/pitch/pan/gain, V6 Small/Big Room fixed-point reverb, composite SFX graph/bank lowering, title SFX IDs 18/77/79/111/258, separate File/Mode SFX sequence forwarding, strict/ASan/UBSan/Release vectors, and the 600-second-equivalent block-size-independent soak pass; full source mix tuning and live AVAudio A/V acceptance remain open. |
| M14 | Audio output | Sample-indexed events feed the realtime SPSC ring and `AVAudioSourceNode` with no realtime allocation, lock, logging, or Swift calls. | Implemented as a bounded output seam — C ring, Objective-C source node, preroll/refill, route recovery, File/Mode SFX forwarding, and owner `tick(nativeTick:)` wiring pass; current AVAudioSourceNode adapter passes, while full mix fidelity/live long-soak A/V acceptance remains pending. |
| M15 | Boot state authority | Swift title state and immutable snapshots match an independent 60 Hz source adapter at every even anchor; rendering is pure. | Implemented for the bounded title route — paired Swift authority and C reference adapter pass 10,000 even-anchor comparisons, including cast→RAMROM at native tick 6788; gunbarrel dynamics, GoldenEye odd-tick projection, and render-hash parity remain explicit unsupported fields. |
| M16 | Legal screen | Source text/save validation, exact 241-tick timing, and first-boot unskippable input rule pass. | Implemented for the bounded source Legal path — exact paired timer/input rule, 287-string catalog, 12 source text events/253 glyphs, 58 GBI commands/12 triangles, five texture/material groups, projection consumption 12/12, strict/ASan/UBSan frame validation, and deterministic 320×240 semantic capture pass; physical pixel parity remains an acceptance gate. |
| M17 | Nintendo screen | Source rotation/scale/lighting, swoosh, duration, and skip rules pass with authentic audio. | Implemented for the bounded source Nintendo path — paired duration/skip authority, fixed-point half-step rotation/1.07977 scale clamp, source ambient-light projection, source node/GBI/material closure, Metal API/shader-validated 320×240 and Faithful-HD captures, and deterministic even/odd raw hashes pass; full N64 pixel/swoosh parity remains an acceptance boundary. |
| M18 | Rareware screen | Source rotation/fade, mip/LOD behavior, composite SFX, and timing pass. | Implemented for the bounded source Rareware path — source 9-list/268-triangle graph, 26 mip levels across four chains, canonical LOD/FORCE_BLEND guards, paired rotation/fade phases, source SFX 258, and fresh Metal API/shader-validated 320×240/Faithful-HD captures pass; exact N64 mip/pixel and live audio parity remain acceptance boundaries. |
| M19 | Gunbarrel | Suit/head/PP7 animation, attachments, flash, background, blood/fades, intro music, and transitions pass. | Implemented for the bounded source Gunbarrel path — 24 clips/three skeletons, source attachment/root-motion/pose lowering, 42-frame blood handshake, modes 2–9 and temporal timers, strict/ASan/UBSan, and fresh Metal API/shader-validated 320×240/1280×960 captures pass; sustained owner cadence and full N64 animation/pixel parity remain acceptance gates. |
| M20 | GoldenEye logo | Lighting, texgen/reflection, fade timing, and File Select versus cast routing pass. | Implemented for the bounded source GoldenEye path — source 162-command/339-triangle graph, seven mip levels, exact two-cycle LOD/combiner/material closure, projection consumption, paired native ticks `3423/3424`, deterministic 320×240/Faithful-HD Metal API/shader captures, and source gold/red pixel checks pass; full N64 lighting/pixel parity remains an acceptance boundary. |
| M21 | File Select | Four wallets, source UI, idle return, full folder actions, and adaptive widescreen pass. | Implemented for the bounded source File Select path — four-folder save/copy/erase authority, source Wallet SWITCH graph (42 nodes/43 records), source UI/text/icon/background packets, corrected erase-confirmation route, idle/Mode transition, adaptive layout, strict/ASan/UBSan/paired validation, and integration pass; full N64 save/UI parity remains an acceptance boundary. |
| M22 | Mode Select | Navigation, availability, back behavior, and persistence pass. | Implemented for the bounded source Mode Select path — solo/multiplayer controller-gated rows, previous-tab/back behavior, selected-wallet SWITCH/material linkage, persistence route, exact 320×240/Faithful-HD/adaptive offscreen captures, Metal API/shader validation, and deterministic draw/pixel hashes pass; complete N64 mode/pixel parity remains an acceptance boundary. |
| M23 | Cast reel | Body/head/weapon selection, skeletal animation, source timing, random entries, and exit rules pass. | In progress — 34-entry source route, unlock/guest gates, random/explicit demo selection, source attachment lowering, Cast texture/render-mode fixtures, abort/restore, and a validated byte-identical source-row-2 `spicebond` offscreen reference with explicit second random word `3` now pass; the canonical Release now records live supplied-drawable Cast submissions, while Metal-4/gputrace/physical cadence acceptance remains open. |
| M24 | Native platform services | Memory, DMA/file index, RZIP, arenas, stage lifecycle, and required platform services operate without the N64 scheduler. | In progress — bounded Swift stage catalog plus C 1172/rebase/decompress callback, metadata packet copy-out, decoded-arena views, value-only setup/portal packets, owner-side chunked scene transfer, pointer-free lifecycle, stage-scoped decoded-payload ownership, and a source-parity file-index/transfer queue now validate all 21 rows with strict/ASan/UBSan range/digest/single-active/chunk guards; true async streaming/DMA and broad platform replacement remain pending. |
| M25 | Demo-stage loading | Dam, Facility, Runway, Bunker I, Silo, Frigate, and Train scene/setup data load through deterministic handles. | In progress — all seven stage families load through the M24 lifecycle and corrected 21-resource root with 468 background rooms, 2,225 setup objects, 2,230 pads/bound pads, 612 portals, 436 textures/248 TLUTs/3,575 bindings, and deterministic scene/setup hashes; the source pad-backed static subset is drawable while collectables/ammo/monitors/autoguns/vehicles and gameplay categories remain pending. |
| M26 | Demo gameplay core | Demo-reachable player/camera/collision, props, doors, guards, AI, objectives, weapons, effects, and paired cadence run headlessly. | In progress — all 14 routes now pass bounded fixed-point player/camera, pad/room/portal, dynamic-door, guard/weapon-page, non-model visual, weapon/effect, orchestrator, and abort/restore lanes under strict/ASan/UBSan; `sourceReady=0` and collision/AI/characters/weapons/effects remain explicit diagnostics. |
| M27 | Demo renderer | Rooms, sky, props, characters, weapons, particles, glass, explosions, HUD/watch, and fades render through Metal 4. | In progress — V7 room/static-prop packets pass all seven stages with source pad-basis/model-scale transforms and the aligned current-room-plus-one-hop visibility contract, scoped `unsupportedMask=0`, and retained full-scene `0x38`; the canonical Release now records a supplied-drawable Facility room/static-prop frame, while current Metal-4 capture/gputrace/physical evidence and character/effect/AI/HUD/weapon categories remain pending. |
| M28 | RAMROM playback | All 14 recordings parse, preserve source-anchor packet/RNG consumption and speedframes, support abort, and restore title state. | In progress — all 14 recordings pass twice (`runs=28`, `abort_restore=14`) through strict/ASan/UBSan C and Swift owner-service parser/playback/checksum/RNG validation; the canonical demo 4 / Facility Release route now reaches packet return and a repeated attract cycle with `sourceAuthorityFailure=none`, while full all-demo native gameplay/category closure remains pending. |
| M29 | Integrated acceptance/handoff | Both launch routes, Release signing, 120/60 evidence, validation, sanitizers, capture inspection, and handoff artifacts pass. | In progress — rebuilt signed Release/provenance and V7 owner/renderer integration pass; current short cadence is near 120 Hz with zero dropped ticks but zero presented timestamps/FPS, current Metal 4 captures SKIP, live Cast supplied-drawable remains blocked, and full gameplay-category closure remains pending. |
| M30 | Visual/window regression recovery | Nintendo/Rareware/Gunbarrel/Cast visual fixes and AppKit focus/window behavior pass source/Metal validation without weakening cadence or fail-closed contracts. | In progress — six-fix implementation, source/CPU suites, elevated GUI/input probes, and fresh Nintendo/Rareware/Cast Metal API/shader captures pass; physical focus/window migration, sustained presented cadence, live Cast supplied-drawable output, and stage gameplay capture remain open. |

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
| R7 | Validate Faithful HD, deterministic 320×240 reference output, opt-in adaptive widescreen, traces, screenshots, sanitizers, cadence, signing, and handoff. | In progress — fresh signed Release/provenance, deterministic Cast reference repeat, all-seven stage environment Metal validation, all-seven gameplay-camera packet sanitizers, and source visibility guards pass; the current post-visibility supplied-drawable harness explicitly SKIPs without Metal 4, while active-display cadence and Release supplied-drawable Cast/gameplay capture remain blocked by the current login-window session. |

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

### Source/render gap audit refresh — 2026-08-21

- The stage source/render lane is implemented behind the opt-in
  `GOLDENEYE_STAGE_GAMEPLAY_CAMERA_V7=1` owner route. The product renderer
  retains the full-scene `0x38` character/AI/effects contract and publishes only
  the source-visible room/static-prop subset when its scoped mask is zero; the
  audit made no stage-source edits.
- Fresh strict/ASan/UBSan packet logs pass for demo 0 stages 33/34. Dam has
  camera/packet hashes `17166107536987602611` /
  `4344127377687538898`, `28` environment commands, `197/197` props, and
  `1183` scene draws. Facility has camera/packet hashes
  `9901855664259801205` / `2739797606600666455`, `48` environment commands,
  `267/267` props, and `1444` scene draws. Both report scoped `0x0`, retained
  full-scene `0x38`, deterministic `1`, and fail-closed `1`; reference capture
  passes `14` demos / `42` checkpoints.
- The fresh production supplied-drawable run has Metal API/shader validation
  enabled but records `SKIP (Metal 4 device unavailable)`. No Release pixel,
  supplied-drawable, gameplay gputrace, or physical validation evidence is
  promoted. The remaining gate is a Metal 4-capable host; do not broaden this
  route to characters/effects/AI or clear unsupported masks.
- The canonical signed Release was rebuilt afterward with stage preparation
  `resources=21`; executable SHA-256 is
  `c4f4f4b9e4f3772f7c47052e32559084e1e9fb0869b3c4f037844b0e4c1516a7`, and the
  Release history/provenance gate passes under the external ROM boundary.

### Cast source/production evidence refresh — 2026-08-21

- M23 Cast source contracts pass again on the full-weapons image-decoder root:
  five source bodies pass texture aliases and exact attachment matrices;
  chrfnp90 passes `64` commands, `7` setups, `10` vertex resources, and `7`
  draws; oliveguard and Natalya texture packets pass with `505/56` and
  `626/46` command/setup counts; and the Cast composer passes all `30`
  identities, `22` animations, and `30` prepared model combinations.
- Correctly parameterized Cast/RAMROM source-scene validation passes all `14`
  recordings twice (`castIdentity=30`, `animations=22`, `demos=14`,
  `runs=28`, `manifest=14`, aggregate `6107930928028985404`) while retaining
  `stageVisual=FAIL_CLOSED` for the unclaimed stage categories.
- The strict Cast reference capture at
  `build/native/cast-reference-capture-v6/20260822T013921Z/` passes Metal
  API/shader validation and byte-identical repeat. It is explicitly the
  source-row-1 `boilerbond` identity (`1`), with reference raw hash
  `878411975a89eb4290a0313794927756b719651e71b5f0dca45e6b5e6d7ff713` and
  Faithful-HD raw hash
  `ab49953288dd7eda553f47509e6146082d852fd71e0a27e690ab619f1202494a`;
  it is not source-row-2 `spicebond` proof.
- Two signed AppKit production attempts now retain explicit blockers under
  `build/native/cast-production-route-v6/m23-current/` and `m23-long/`:
  both record `castSubmit=0`, `latestCrash=none`; the longer bounded run
  remains at source tick `2964`, Gunbarrel screen `3`, subphase `3`. No
  supplied-drawable Cast frame, inspected `.gputrace`, or physical cadence
  claim is promoted. The current login-window/headless WindowServer session
  is the blocker; the source Cast guard remains fail-closed.

### Native platform-service lifecycle continuation — 2026-08-21

- Added `GoldenEyeStageLifecycleV6`, a value-only M24 service that consumes the
  corrected 21-resource catalog and loader views, preserves source asset
  handles and deterministic decoded-arena offsets, and exposes explicit
  `unloaded → loaded → active → loaded → unloaded` transitions. It retains no
  payload pointer or byte buffer and does not clear M25–M27 unsupported work.
- `bash scripts/test_stage_lifecycle_v6.sh
  build/native/stage-assets-image-decoder-v6` passes strict, ASan, and UBSan:
  seven stages, decoded arena `2016864` bytes, resource-view hash
  `15083698972971979799`, state hash `360802037447672111`, and invalid
  double-load/active-reset/unload transitions fail closed.
- Fresh corrected-root M24 foundation checks pass: stage C catalog strict/
  ASan/UBSan (`stages=7`), catalog strict/ASan plus malformed-manifest guard
  (`resources=21`), resource loader (`packets=21`, `views=21`), background
  strict/ASan/UBSan (`stages=7`), setup packet strict/ASan/UBSan
  (`objects=2225`, `pads=2230`, `portals=612`), and scene packet (`rooms=468`,
  `payload_bytes=2016864`).
- M24 remains open for the broader native memory/DMA/file-index/streaming
  service replacement and production lifecycle integration. The C
  `STUB(M24)` diagnostic remains explicit; no gameplay or renderer claim is
  inferred from the lifecycle smoke.
- `NativeTitleOwner.prepareStageScene` now integrates the lifecycle in the
  production preparation seam: selected stages activate, replacement stages
  deactivate/unload the prior owner, and game reset releases the lifecycle.
  Owner/source-selection/runtime guards and SwiftPM build pass; broader
  streaming/DMA replacement remains open.

### Seven-stage loading continuation — 2026-08-21

- M25 now consumes the bounded M24 lifecycle metadata and the corrected
  image-decoder root for all seven stage families. Scene packet validation
  passes `468` rooms and `payload_bytes=2016864`; setup packet validation passes
  `2225` objects, `2230` pads, and `612` portals under strict/ASan/UBSan.
- Stage texture/material validation passes `436` textures, `248` TLUTs,
  `568` levels, `3575` bindings, `gpuRepresentable=1`, and
  `unrepresentableMips=0`. Full seven-stage model composition keeps the
  source-visible static-prop set drawable: Dam `197/197`, Facility `267/267`,
  Runway `88/88`, Bunker I `123/123`, Silo `165/165`, Frigate `147/147`, and
  Train `200/200`.
- The model composer retains `unsupportedMask=0x38` and reports zero drawable
  characters; no character/effect/AI/HUD/weapon/collision category is lowered
  by inference. M26 gameplay ownership and M27 supplied-drawable renderer
  evidence remain the next bounded gaps.

### Gameplay-owner continuation — 2026-08-21

- M26 strict/ASan/UBSan lanes pass all 14 RAMROM routes: the source-page
  gameplay smoke reports `damEntities=238`, `sidecarComplete=1`,
  `sourceReady=0`; the player/camera bridge passes `layout=176`, `direct=2`,
  `eventHash=1`; and the dynamic-scene readiness matrix remains explicitly
  incomplete with a fixture-only ordered composition.
- The gameplay orchestrator passes `demos=14`, `runs=28`, aggregate
  `3432588557158677409`, Dam movement, four environment dynamic doors,
  deterministic restore, and source hashes. Guard/door pages pass `623`
  guards, `397` doors, `152` transformed doors, `5104` pose rows, and `397`
  resolved portal rows with portal hash `13325078266282593292`.
- Weapon/effect integration, non-model authority/visuals, and the bounded
  stage runtime pass strict/ASan/UBSan; the stage runtime reports
  `1578` samples and aggregate `4774828755625742329` with explicit
  `effects,ai,weapons,collision` diagnostics. No character/AI/effect/weapon
  record is manufactured and no `0x38` renderer mask is cleared.

### Scoped renderer evidence continuation — 2026-08-21

- Fresh V7 packet strict/ASan/UBSan validation retains the exact corrected
  Facility camera hash `9901855664259801205` and packet hash
  `2739797606600666455`; Dam remains `17166107536987602611` /
  `4344127377687538898`. Room/static-prop counts and scene draws remain
  `197/197` + `1183` and `267/267` + `1444`, with scoped `0x0` and retained
  full-scene `0x38`.
- Current all-14 checkpoint and Release supplied-drawable attempts compile
  with Metal API/shader validation but explicitly SKIP because this host has no
  Metal 4 device. The seven-stage environment harness now records all-seven
  clean SKIPs and exits successfully for that unavailable-device condition;
  partial/unexpected capture outcomes still fail. Archived ignored PNG/RAW/
  JSON captures remain separate from current production evidence.
- M27 remains open for a Metal 4-capable supplied-drawable frame, inspected
  `.gputrace`, and physical validation. Characters, AI, effects, HUD, weapons,
  collision, sky, glass, and explosions remain explicit unsupported categories.

### All-14 RAMROM playback continuation — 2026-08-21

- Fresh all-14 playback validation passes strict and ASan/UBSan with
  `demos=14`, `runs=28`, `abort_restore=14`, `unique_stages=7`, parser/playback/
  checksum/RNG PASS, and explicit gameplay/renderer `STUB(M26/M27)` boundaries.
  The Swift owner-service aggregate is `6851901412168630050`; Dam demo 1
  retains `packets=454`, `records=1578`, and `terminal_tick=3156`.
- Paired C playback and parser lanes pass strict/ASan/UBSan independently;
  the same all-14 command prepares the corrected seven-stage scene packets
  (`rooms=468`, `payload_bytes=2016864`, packet hash
  `13284805027105908470`). Playback evidence remains separate from native
  gameplay and supplied-drawable renderer acceptance.

### Integrated Release/cadence refresh — 2026-08-21

- Rebuilt the source-faithful Release after the M24/M26 harness changes;
  stage preparation reports `resources=21`, executable SHA-256 is
  `85a7c8f86abbba1709e30f5cc4689bf6ce1a59a22c941657729b1c1e262cd916`, and
  the frozen Release history/provenance gate passes with final packet hash
  `b9247beab28b0e101c471c1a94d0d4baebf8a3ea85e306981bef1365d3e485ad`.
- Short current post-display-observer 120/fixed-60 supplied-drawable cadence
  records retain logic `119.9975`/`119.9879` Hz and zero dropped ticks, but
  only `5/6` callbacks, zero presented timestamps/FPS, and `pass=0` in the
  current headless/login window. Physical 120/60 acceptance remains open.
- Current stage environment, V7 reference, and V7 Release supplied-drawable
  Metal attempts explicitly SKIP because no Metal 4 device is available; Cast
  production remains blocked before `castSubmit=1`. Do not promote archived
  captures or headless cadence to integrated acceptance.

### M30 visual/window regression refresh — 2026-08-21

- The final signed Release after the display-observer change is
  `85a7c8f86abbba1709e30f5cc4689bf6ce1a59a22c941657729b1c1e262cd916`; its
  external-ROM provenance and R0 gates pass.
- Source/CPU regression validation passes title material strict/ASan/UBSan,
  title route, Gunbarrel modes/blood/transition projection, and Rareware
  LOD/FORCE_BLEND guards. Elevated AppKit keyboard/controller and synthetic
  focus probes pass; physical focus notifications remain unavailable in the
  headless session.
- Fresh current Metal API/shader captures pass for Nintendo at
  `build/native/nintendo-reference-capture-v6/20260822T024348Z/`, Rareware at
  `build/native/rareware-reference-capture-v6/20260822T024429Z/`, and strict
  Cast identity 1 at `build/native/cast-reference-capture-v6/20260822T024522Z/`.
  The Cast artifact remains `boilerbond` row 1, not `spicebond` row 2.
- The current Gunbarrel Metal temporal sweep passes modes `2...9` and the
  authored timers through `400`, including the blood/muzzle timer-230 frame
  (`71` draws, `874` triangles).
- Physical focus/window migration, sustained presented FPS, live Cast
  supplied-drawable output, and current stage gameplay Metal capture remain
  unproven; keep those gates open.
- A post-observer wake/fullscreen attempt at
  `build/native/boot-runtime/cadence/runs/m30-wake-attempt/120/report.txt`
  reached `119.9897` Hz with 64 callbacks and displays awake, but still had
  `frontmost=loginwindow`, zero presented samples/FPS, 64 rejected samples,
  and `pass=0`. This confirms the remaining blocker is the active desktop/
  WindowServer session, not a missing logic-rate measurement.
- Added explicit AppKit display-change routing for window screen, screen
  profile, backing-property, and application screen-parameter notifications;
  each refreshes drawable size/frame-rate configuration and records evidence.
  Owner/runtime and GUI probes remain green, while physical migration still
  requires a visible desktop exercise.

### File/Mode audio sidecar continuation — 2026-08-21

- File/Mode SFX events now forward through a separate
  `GoldenEyeSourceAudioBindingV6` state in `GoldenEyeNativeAudioService`, so
  menu sequence numbers cannot suppress frontend audio events. The owner
  forwards the immutable sidecar events through the existing sample-indexed
  scheduling path; realtime callback behavior is unchanged.
- Namespace/duplicate binding tests, deterministic audio engine/effects
  strict/ASan/UBSan/Release lanes, and the Swift debug build pass. Live
  AVAudio output/A-V timing and exact source mix parity remain acceptance gaps.
- The expanded bank smoke covers IDs `18,77,79,111,118,197,199,222,258`
  with combined hash `9686333082073475502`; File/Mode session reset and
  independent sequence cursors are tested.

### M24 decoded-payload ownership continuation — 2026-08-22

- Added and integrated `GoldenEyeStagePayloadStoreV6`. Explicit activation
  owns the three decoded resources for one stage, rechecks decoded byte counts
  and SHA-256 digests, exposes bounded fixed-width reads only while active,
  and enforces single-active replacement, active-unload, and reset guards.
- Strict/ASan/UBSan validation passes all seven corrected stage families with
  first-stage aggregate `8556576272295209170` and all-stage aggregate
  `15436731694462652841`; debug `GoldenEyeHost` and owner route guards pass.
- The signed Release rebuild after this source change passes preparation,
  production build, codesign/bundle gates, R0, and elevated Release
  provenance. Current executable SHA-256 is
  `fdc0f66a371e076398010e130df25c743905c64cf2639ce973e863182d6a778e`.
- The canonical Release route still stops before Cast/V7 on the paired
  Gunbarrel model-result timing boundary in the current headless run; the
  separate seven-stage supplied-drawable harness remains non-canonical. Do
  not infer physical presentation or full gameplay-category closure.
- Fresh opt-in V7 cadence against this rebuilt Release reproduces
  `authorityFailure=paired projection mismatch at tick 3072 field gunbarrelMode:
  native 5 original 6`, while measuring `logicTickRateHz=120.001486`, zero
  dropped ticks, five callbacks, and zero presented samples/FPS under the
  login-window session.
- The V7 owner now copies the camera adapter's guarded current-room-plus
  one-hop portal-neighbor source-visible room set instead of declaring only
  the current room. Source environment strict/ASan/UBSan validation remains
  PASS (`stages=7`, `environmentTriangles=96084`, `metalDraws=12679`); this
  is still a bounded visibility seed, not recursive portal/PVS parity.
- The final rebuilt-Release opt-in cadence at
  `build/native/boot-runtime/cadence/runs/m24-visible-current-20260822/120/`
  still reports the paired Gunbarrel mismatch (`native 5`, `original 6`, tick
  `3072`) with logic `120.001829 Hz`, zero dropped ticks, five callbacks, and
  zero presented samples/FPS.
- Updated all-seven packet hashes for the aligned room set, in stage order
  `33,34,35,9,20,26,25`, are
  `9691731936558540317`, `1361423520639327845`, `12839844755602817467`,
  `18348473008274347972`, `16691602544368876791`, `16956423305747631152`, and
  `6925925173978220218`; current production supplied-drawable capture is
  explicitly SKIP without a Metal 4 device.

### Source authority and canonical V7 reachability continuation — 2026-08-22

- The hosted original title oracle now preserves the source blood stream: mode
  5 primes frame 0 and completes only after 41 continuations. The paired
  authority and full transition projection pass the source anchors through
  mode 2...9 and GoldenEye at native tick `3582`; the optional paired Cast
  route also passes the Cast-end transition. The original C/Swift reference
  lane remains strict/ASan/UBSan green.
- The source Cast interface now requests its copied timer-181 Cast transition;
  hosted `HEAD_FIXED=-1`/`HEAD_RANDOM=-97` sentinels preserve the source's
  signed enum semantics, and the value-only wallet fixture has 32 switch slots
  for `GFXHIT0_PICS=21`. These are source/fixture correctness fixes, not
  renderer fallbacks.
- The product renderer latches the blood completion mailbox across native
  draw-only substeps, serializes scene publication against the display-link
  callback, and keeps the V7 scoped composer on an explicit `props` category.
  The RAMROM guard-owner state is constructed directly in heap storage (the
  1,972,424-byte C state no longer crosses the owner-thread stack); the selected
  Cast route is prewarmed before cadence and rebased at the source handoff.
- The final signed Release is
  `build/native/boot-runtime/source-faithful/GoldenEyeHost.app`, executable
  SHA-256 `289a98e3173fd3770ff081f3ef54d20310c63883a530ab2d7bcbc22bd5de6e0e`.
  Release history/provenance, codesign, and R0 pass with the external ROM
  boundary.
- Canonical Release run
  `build/native/boot-runtime/cadence/runs/m28-blood-reset-20260822-120/120/`
  reaches a real supplied-drawable V7 frame: demo `4`, Facility stage `34`,
  native tick `4324`, source room `68`, `158/158` visible static props,
  `42` dynamic doors, `1191` scene draws, scoped unsupported `0`, retained
  full-scene mask `0x38`, camera packet hash `4171253561713628972`, and
  composition hash `9008813320083006498`. Archived owner/renderer logs are
  `stage-gameplay-camera-owner.log` and `stage-gameplay-camera-renderer.log`;
  RAMROM reaches packet `559/559` at tick `7678`.
- The same bounded run measures logic `119.9994 Hz`, zero dropped ticks,
  zero fatal debt, zero renderer failures, and a supplied-drawable contract;
  presented timestamps/FPS remain `0` in the login-window/headless session;
  this full-loop run ends with `sourceAuthorityFailure=none` after the
  repeated-Gunbarrel blood reset; packet return and the second attract cycle
  remain paired through the bounded window.
- Current Metal-4 production/reference capture attempts remain explicit
  `SKIP (Metal 4 device unavailable)`; no current `.gputrace` or physical
  presentation claim is promoted. Characters, AI, effects, HUD, weapons,
  collision, sky, glass, and explosions remain fail-closed.

### M24 bounded file-index and transfer-queue continuation — 2026-08-22

- Added `GoldenEyeStageFileIndexV6`, a deterministic value-only index over the
  corrected seven-stage/21-resource catalog. Each row preserves the source
  offset/size, decoded size, compression flag, asset handle, and verified
  source/decoded digests; no ROM path, pointer, or retained file descriptor
  crosses the contract.
- Added `GoldenEyeStageTransferQueueV6`, a bounded submit/complete queue over
  the active decoded payload store. It rejects missing active stages, cross-
  stage requests, queue overflow, invalid decoded ranges, replayed request
  IDs, and replacement/reset while work is pending. Completion copies bytes
  into caller-owned values and hashes the deterministic request/byte stream;
  it is explicitly not an N64 scheduler or asynchronous DMA implementation.
- `bash scripts/test_stage_transfer_queue_v6.sh
  build/native/stage-assets-image-decoder-v6` passes strict/ASan/UBSan:
  `stages=7`, `entries=21`, `fileIndexHash=12969746555383168713`, three
  completed requests, `transferHash=16820286361146389937`, and queue/range/
  single-active/reset guards. The debug `GoldenEyeHost` build, owner route
  guard, source boot-route smoke, payload-store/lifecycle smokes, and the
  source-faithful Release rebuild also pass.
- The current Release executable SHA-256 is
  `0738a1202ea27a5949fb7fe10e1889d5c7d27f53ed634d5594ab81f61d535f33`;
  preparation reports `resources=21`, Release history/provenance, codesign,
  and R0 pass. This lane does not promote M24's C `STUB(M24)`, gameplay or
  renderer categories, or any physical/Metal-4 acceptance claim.
- The fresh stage gameplay-camera production harness remains an explicit
  `SKIP (Metal 4 device unavailable)`; stale ignored `gputrace/` files remain
  non-current evidence. Presented timestamps/FPS remain unavailable under the
  login-window session.

### Repeated Gunbarrel source-authority continuation — 2026-08-22

- The authoritative 120-second Release run had a repeated-entry mismatch at
  tick `14370` because renderer-local blood state could remain stale while
  Cast/SWITCH frames bypassed renderer submission. The source owner now resets
  the copied Gunbarrel blood stream on the authoritative transition into the
  Gunbarrel screen, rather than inferring entry from the renderer's last frame.
- The reset is a narrow lifecycle operation: it clears only the copied blood
  frame index, continuation count, and completion latch. The paired authority,
  original source oracle, source C state, and fail-closed renderer masks remain
  unchanged.
- Fresh signed Release:
  `build/native/boot-runtime/source-faithful/GoldenEyeHost.app`, executable
  SHA-256 `fcc912c92170f2943a8981d5e87e08460e0d38b0c31696b89e11d35b55d62279`.
  Preparation, codesign, Release history/provenance, and R0 pass.
- Fresh 120-second route:
  `build/native/boot-runtime/cadence/runs/m28-repeat-reset-20260822-120/120/`.
  It records `sourceAuthorityFailure=none`, logic `119.9999 Hz`, zero dropped
  ticks, zero renderer failures, and supplied-drawable Facility V7 at tick
  `4324` (`158/158` props, `1191` draws, scoped unsupported `0`, retained
  full-scene `0x38`). At tick `14370`, the renderer remains in source mode 5
  with blood visible; mode 6 appears later after the 41-continuation stream.
- The post-fix production capture reran with API/shader validation and remains
  `SKIP (Metal 4 device unavailable)` at `2026-08-22 06:19:43`. Presented
  timestamps/FPS remain unavailable under `frontmost=loginwindow`.

### M23 row-2 live probe refresh — 2026-08-22

- The correctly parameterized live Cast probe used
  `GE_CAST_SOURCE_INDEX=2 GE_CAST_RANDOM_WORD=3` and archived
  `build/native/cast-production-route-v6/m23-spicebond-row2-current2/`.
  It records `castSubmit=0`, `latestCrash=none`, and stops in the first
  Gunbarrel cycle at tick `2952` under the current headless/login-window
  session. No supplied-drawable Cast frame or trace is promoted.

### M23 live-launch policy refresh — 2026-08-22

- The Cast production launcher now forwards explicit fullscreen/stress policy
  instead of relying on hidden defaults. A fresh row-2 probe with
  `GE_CAST_SOURCE_INDEX=2 GE_CAST_RANDOM_WORD=3` and windowed/non-stress policy
  still records `castSubmit=0`, `latestCrash=none`, stopping at Gunbarrel tick
  `2960`; no live Cast frame or trace is claimed.

### M27 gameplay-camera source-anchor window continuation — 2026-08-22

- The opt-in V7 owner now publishes a bounded source-anchor window instead of
  a single frame. `GOLDENEYE_STAGE_GAMEPLAY_CAMERA_ANCHORS` defaults to `4`,
  and `GOLDENEYE_STAGE_GAMEPLAY_CAMERA_ANCHOR_INTERVAL` defaults to `120`
  native ticks. Submission is coalesced with an in-flight guard and failure
  mailbox; reset drains the queue before clearing route state.
- Adjacent-anchor bursts were rejected by the measured owner debt guard
  (`fatalDebtTicks=241`). The spaced contract preserves cadence: two
  independent 30-second Release runs record the same four ticks
  `4324,4444,4564,4684`, identical camera/packet/environment/composition
  hashes, scoped unsupported `0`, retained full-scene `0x38`, and
  `sourceAuthorityFailure=none`. The final run measures `119.9982 Hz`, zero
  dropped/fatal debt ticks, and zero renderer failures.
- Evidence paths:
  `build/native/boot-runtime/cadence/runs/m27-anchor-window-spaced-20260822-30/120/`
  and its `...-repeat...` counterpart. Current signed Release SHA-256 is
  `aadf9c2bfcda56eef17ee5efa34b70271c5f87d3cd325be5d15704f5b12bc681`;
  preparation, codesign, provenance, and R0 pass.
- A fresh windowed 120-second run at
  `build/native/boot-runtime/cadence/runs/m27-anchor-window-long-windowed-20260822-120/120/`
  also records the same four submissions and `sourceAuthorityFailure=none`,
  logic `120.0003 Hz`, zero dropped/fatal debt ticks, and zero renderer
  failures. The command remains `pass=0` only because the login-window
  session supplies no presented timestamps/FPS.
- A post-build production capture rerun at `2026-08-22 07:16:57` enables API
  and shader validation but cleanly records `SKIP (Metal 4 device unavailable)`.
- The diagnostic rerun at `2026-08-22 07:33:00` now distinguishes the blocker:
  `MTLDevice unavailable device=nil`; no Metal device exists in this CLI
  session, so no trace or supplied-drawable claim is possible.

### RAMROM authority evidence retention continuation — 2026-08-22

- RAMROM owner authority/gameplay logs now append instead of atomically
  overwriting each event. The windowed 120-second Release route at
  `build/native/boot-runtime/cadence/runs/m28-ramrom-append-long-20260822-120/120/`
  retains `packet=0/559`, `558/559`, `559/559`, and the next-cycle `packet=0/559`,
  plus all four V7 anchor submissions. It records
  `sourceAuthorityFailure=none`, logic `119.9997 Hz`, zero dropped/fatal debt,
  and zero renderer failures; `pass=0` remains only the no-presented-FPS
  login-window boundary.
- Current signed Release SHA-256 is
  `ca09b6cb290ebb62f0874678a1dcabbf6278730beb62ec89e39d0c6f3de1af30`;
  provenance, codesign, and R0 pass.
- The route remains explicitly room/static-prop scoped: each frame retains
  `158/158` props, `42` dynamic doors, `1191` scene draws, and no character,
  AI, effects, HUD, weapons, or collision mask is cleared. Physical presented
  timestamps/FPS and Metal-4 supplied-drawable capture remain open.

### M24 source-catalog parity continuation — 2026-08-22

- `GoldenEyeStageFileIndexV6` now validates its public value catalog against
  every C `ge_stage_v5_resource_packet` row and its `ge_stage_v5_find_stage`
  identity before a transfer queue can be constructed. The index emits the
  C RAMROM source order (`33,34,35,9,20,26,25`) rather than silently sorting
  numeric stage IDs, and rejects stage/resource drift with typed
  `sourceCatalogMismatch` diagnostics.
- The transfer smoke exercises a tampered stage identity and confirms the
  fail-closed path. Strict/ASan/UBSan pass with
  `fileIndexHash=14890358892990385005`, `transferHash=16820286361146389937`,
  three completed requests, and `sourceParity=1`. Loader, payload-store, and
  lifecycle strict/ASan/UBSan checks also pass; the loader reports
  `packets=21 views=21`, and lifecycle reports
  `viewHash=15083698972971979799` / `stateHash=360802037447672111`.
- The debug `GoldenEyeHost` build and engine-owner smoke pass with the
  writable module cache. The freshly rebuilt signed Release executable is
  `425ee3d6f88d86b3318a61fc80ef12175f3c9153621914fa34e99cdb6d95e635`;
  Release history/provenance, codesign, bundle guards, and R0 pass.
- The source parity change does not broaden M24's C `STUB(M24)`, V7 opt-in,
  scoped unsupported masks, or gameplay categories. The post-build Metal API/
  shader capture at `2026-08-22 07:51:38` remains an explicit
  `SKIP (MTLDevice unavailable device=nil)`; physical presented cadence and
  the full-scene `0x38` categories remain open.

### M24 transfer-backed scene-owner continuation — 2026-08-22

- `GoldenEyeStageScenePacket.loadAll` now has a transfer-backed path. It
  activates one stage at a time in C file-index order, submits/completes the
  three decoded resources through `GoldenEyeStageTransferQueueV6`, parses the
  copied bytes with the existing C background/setup validators, then unloads
  the stage before continuing. The direct file-backed loader remains for
  comparison; no asynchronous scheduler or ROM access was introduced.
- `NativeTitleOwner` now owns that queue for stage preparation, replacement,
  activation, and reset. Current owner telemetry records
  `completedRequests=21`, `transferHash=13486978902238770849`, and active
  Facility payload `decodedBytes=380848`; the scene packet remains identical
  to the direct path (`468` rooms, `2016864` payload bytes,
  `13284805027105908470`).
- Fresh Release owner evidence at
  `build/native/boot-runtime/cadence/runs/m24-transfer-owner-final-20260822-50/120/`
  records four V7 anchors (`4324,4444,4564,4684`), `158/158` props,
  `1191` draws, scoped `unsupportedMask=0`, retained full-scene `0x38`,
  `sourceAuthorityFailure=none`, and zero dropped/fatal/renderer failures.
  Logic is `120.0005896 Hz`; presented samples remain zero under the
  login-window session.
- The current signed Release executable SHA-256 is
  `28a7aef35302c753aec800db6f1c61a7b3a2a5fea9dace950e95114edc226d61`;
  Release history/provenance, codesign, bundle guards, and R0 pass. The
  post-build Metal API/shader harness at `2026-08-22 08:36:49` remains
  `SKIP (MTLDevice unavailable device=nil)`.

### M24 chunked transfer and RZIP bridge continuation — 2026-08-22

- The owner transfer queue now uses a bounded 64 KiB chunk size. Every decoded
  resource is reassembled from sequential source-ordered requests before the
  existing C background/setup parsers consume it; no asynchronous scheduler,
  retained callback, or ROM pointer was introduced.
- Direct/transfer scene equality remains `468` rooms, `2016864` payload bytes,
  packet hash `13284805027105908470`. The chunked scene smoke passes
  strict/ASan/UBSan with `44` completed requests and transfer hash
  `10384286454254812603`.
- The catalog's compressed 1172 rows now route through the existing C
  `ge_stage_v5_decompress_1172` callback contract with a borrowed,
  no-capture Apple Compression callback. Strict/ASan/UBSan catalog checks
  preserve catalog hash `16694764706485246250` and all seven stage hashes.
- Final signed Release SHA-256 is
  `759a84bf47bfe37870942474b8ce01314d1f453e014f5fe61187fec02f14c869`;
  Release history/provenance, codesign, bundle guards, and R0 pass. Fresh
  owner evidence at
  `build/native/boot-runtime/cadence/runs/m24-rzip-chunked-20260822-45/120/`
  records four Facility V7 anchors, `sourceAuthorityFailure=none`, zero
  dropped/fatal/renderer failures, and logic `120.0024038 Hz`.
- The current Metal API/shader harness remains
  `SKIP (MTLDevice unavailable device=nil)` and presented FPS remains
  unavailable under the login-window session.

### M29/M30 GPU-capture boundary audit — 2026-08-22

- A fresh signed Release launch with `MTL_CAPTURE_ENABLED=1` is visible to
  `gpucapture` but explicitly `non-debuggable` because the Release bundle has
  no `get-task-allow` entitlement; `gpucapture boundaries` therefore cannot
  capture the canonical Release process without changing its signing policy.
- A separate debuggable SwiftPM Debug owner was launched without shader
  validation (required by gpucapture). Its Layer-boundary trace
  `build/native/m29-debug-owner-capture-20260822/debug-owner-layer.gputrace`
  completed but contains `0 command buffers`, `0 API calls`, and `0 resources`
  under the login-window session. It is retained as diagnostic evidence only,
  not promoted to Release or physical acceptance.

### Release-gate harness refresh — 2026-08-22

- `test_release_renderer_environment_guard_v6.sh` now uses a writable build
  module cache for its Swift frontend parse, eliminating a sandbox-only
  `~/.cache/clang/ModuleCache` failure. The complete
  `test_native_boot_release_gate.sh` now passes its renderer-policy,
  fidelity-policy, prepared dry-run, shader/resource, preserved-catalog, and
  forbidden-bundle checks.

### RZIP callback negative-path refresh — 2026-08-22

- The C stage V5 smoke now asserts undersized output, malformed marker,
  callback-produced byte-count mismatch (`GE_STATUS_ASSET_MISMATCH`), and
  callback failure (`GE_STATUS_INTERNAL_ERROR`) in strict plus ASan/UBSan
  builds. The Apple Compression catalog callback remains borrowed and
  no-capture; no scheduler or renderer scope changed.

### M29 Aqua acceptance and trace continuation — 2026-08-22

- After unlock, fresh signed Release short cadence passed both displays:
  120 mode `120.000946 FPS` and fixed-60 mode `59.951023 FPS`, with zero
  dropped ticks, rejected samples, render failures, focus pauses, or migration
  errors. The longer route reached Cast and the V7 handoff.
- The 120-second route did not sustain the gate: 120 mode measured
  `113.190118 FPS`, fixed-60 `57.633275 FPS`; a no-V7 control measured
  `112.338963 FPS` with a `3515 ms` target stall and `fatalDebtTicks=241`.
  Logic remained near 120 Hz with zero dropped ticks, so this is retained as a
  sustained WindowServer/scheduling regression, not visual/category acceptance.
- A separate copy of the current Release bundle signed only with capture
  entitlements produced
  `build/native/m29-release-capture-entitled-20260822/release-code-layer.gputrace`.
  Static `gpudebug` inspection confirms one command buffer, one labeled MTL4
  source-scene render encoder, six draws, 960x540 BGRA8 + Depth32Float, and a
  representative 54-index draw. It is Release-code diagnostic evidence, not
  canonical Release signing evidence.

### Current Release rebuild and unlocked-session follow-up — 2026-08-22

- The source-faithful Release was rebuilt after moving immutable stage catalog,
  material, and 64 KiB transfer preparation before the measured owner starts.
  The executable SHA-256 is
  `803dc0db99e4786b7eb03893191d1c24a3330fcb90cbf063f5e2be4457990dfa`.
  Release history/provenance, codesign, R0, renderer-environment, fidelity,
  prepared dry-run, shader/resource, preserved-catalog, and forbidden-bundle
  gates all pass.
- The stage source lane remains deterministic and memory-clean: scene packet,
  transfer queue, asset catalog, and gameplay-camera packet strict/ASan/UBSan
  smokes pass. The current packet values remain `468` rooms,
  `2016864` payload bytes, packet hash `13284805027105908470`, `44` chunked
  requests, transfer hash `10384286454254812603`, catalog hash
  `16694764706485246250`, and V7 `unsupportedMask=0` with retained
  full-scene `0x38`.
- The current V7 Release route reached the intended four source-anchor
  submissions at ticks `4324,4444,4564,4684`; each was presentable with
  `158/158` props, `1191` scene draws, scoped unsupported `0`, and retained
  full-scene `0x38`. Its preflight was nevertheless `frontmost=loginwindow`,
  so the run has no valid presented-FPS or physical-Aqua claim.
- The no-V7 control confirms the remaining pacing seam is the uncached
  `GoldenEyeRamRomGameplayOrchestratorV6.fromEnvironment` at source-begin
  tick `4322` (target stall about `3413 ms`, `fatalDebtTicks=241`). The V7
  prewarm is therefore kept opt-in; the legacy route is not made to consume a
  V7 gameplay owner, and no unsupported category bit is cleared.
- A normal-audio control also produced a macOS code-signature invalid-page
  termination in the Core Audio callback (`ge_audio_source_node_v5.m:156`);
  that crash is retained as a separate runtime diagnostic, not treated as
  source-scene evidence or silently masked by disabling audio.
- The next acceptance step is a shorter rerun after the desktop is unlocked:
  capture active foreground/display state first, then obtain supplied-drawable
  Release presentation timestamps and a Metal-4 API/shader-validated trace.

### V7 prepared-draw cache and publication-race hardening — 2026-08-22

- The source renderer now caches one consecutive immutable snapshot's prepared
  draws and batching plan, keyed by copied-record aggregate hash, native tick,
  topology counts, and drawable dimensions. New camera anchors replace the
  entry; uniforms/vertex data remain copied per frame and source hashes are
  unchanged.
- V7 asynchronous publication now uses a renderer generation token. Stale
  completions cannot overwrite a newer title/stage route; shutdown is locked;
  RAMROM return drains the bounded submission queue. Timing logs are copied
  into each cadence case for auditability.
- Cache-enabled Release SHA-256 is
  `4354c852da73c6343566c2c0f891744bb32f1fd4c9211b9e21a3f0dfc5c28eb5`.
  Release history/provenance, codesign, R0, renderer-policy, fidelity, and
  bundle gates pass.
- Locked-session diagnostic
  `build/native/boot-runtime/cadence/runs/m29-cache-loginwindow-20260822-45/120/`
  records `cacheHit=1`, `cacheHits=67`, callback p95 `3.95 ms`, and no render
  failures. It has zero presented timestamps because `frontmost=loginwindow`;
  active foreground cadence and Metal capture remain open.

### Background-window behavior parity — 2026-08-23

- GoldenEye now supports `GOLDENEYE_NATIVE_BACKGROUND=1`. The scripted
  `run_native_boot.sh` defaults to that mode, does not activate or key the
  window, and keeps the owner/audio timeline independent of AppKit focus.
  Set `GOLDENEYE_NATIVE_BACKGROUND=0` for an interactive foreground launch;
  cadence measurement still defaults to foreground mode.
- The actual `run_native_boot.sh` LaunchServices background verification under
  the locked session retained `3,124` source ticks in
  `build/native/boot-runtime/cadence/runs/m29-background-runner-20260823-locked/`
  while `frontmost=loginwindow`. This proves owner execution, not visible
  presentation; CAMetalDisplayLink/presented-FPS remains an active-display
  contract.
- Background policy, debug build, owner soak, Release build, provenance,
  fidelity, renderer-policy, and bundle gates pass. Current Release SHA-256:
  `4fb60d7fa26ad9e4904ebf640caaf0342edb7a7fc4a313e933942cd210ab7e5a`.
