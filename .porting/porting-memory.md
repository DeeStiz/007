# GoldenEye Swift Porting Memory

## Active Goal

- Goal: `native-boot-menu-attract-120`
- Goal document: `.porting/goal-native-boot-menu-attract-120.md`
- Current handoff: `.porting/porting-handoff-native-boot-menu-attract-120-M30.md`
- Current milestone: M14–M29 integration in progress; M0–M6 foundation gates,
  bounded title geometry, route seams, and realtime output foundation are
  implemented
- Status: In progress; prior `classic-combiner-render-mode`,
  `classic-textured-prop-material`, `classic-gbi-static-prop-replay`, and
  `native-metal-first-frame` goals remain complete

# Watch List

- A local Git reference now points at upstream `c4356466796c697dfd298010b9bed261f9ed8c6a`; all tracked differences are intentional Darwin build-portability edits documented in `m0-provenance.md`. Porting artifacts and extracted/private assets remain intentionally untracked or ignored.
- The verified external ROM is `/Users/derek/Documents/GoldenEye 007 (USA).z64`, SHA-1 `abe01e4aeb033b6c0836819f549c791b26cfde83`. Never copy it into source control or application bundles.
- The extracted local asset tree is about 53.3 MB across 4,715 files and includes 2,698 image payloads. These are local provenance inputs, not native rendering or fidelity evidence.
- The upstream microcode extraction helper assumes a root-level ROM and its process-substitution path failed in the sandbox. This does not block the bounded classic replay goal; do not silently substitute generated microcode.
- `Gfx.words` uses `uintptr_t`; host `Gfx` can be 16 bytes while N64 commands are 8 bytes. No raw `Gfx` layout or pointer crosses the native C/Swift boundary.
- Pointer-bearing GBI commands require deterministic resource handles. Never truncate a macOS pointer into a 32-bit N64 command field.
- `rspGfxTaskStart` still packages and submits an N64 `OSTask`; it is not a GBI interpreter. The host replacement seam is now the separate bounded V2 replay core and does not pull the full scheduler into Swift.
- GoldenEye uses the classic GE/F3D opcode layout plus custom commands including `G_TRI4` (`0xB1`) and `G_SETTEX` (`0xC0`). F3DEX2 assumptions are invalid.
- GBI decoding, RSP transform/lighting/clipping, and RDP combiner/raster behavior are distinct semantic layers. Do not report command decoding as faithful rendering.
- The original N64 Makefile lane remains canonical and separate. The native archive must exclude MIPS assembly, N64 boot/hardware services, process entry points, and broad game-loop dependencies.
- Swift owns AppKit and Metal objects; C owns GoldenEye-derived semantics. Cross-language state is copied, immutable, versioned, fixed-width POD.
- One owner thread owns lifecycle, packet production, and mutable renderer state. Do not share mutable C graphs with the display-link callback.
- Metal 4 command buffers are device-created, reusable, explicitly begun/ended, and do not retain resources. Allocator reuse, residency, resource retention, and shared-event retirement must be proven.
- `set*Bytes`, per-encoder legacy binding, `MTLBlitCommandEncoder`, managed storage mode, and queue-created command buffers are invalid for the planned Metal 4 path.
- No emulator, hardware screenshot, RenderDoc capture, `.gputrace`, Metal System Trace, or memgraph reference exists. Local screenshots and GPU captures cannot establish N64 visual parity.
- Run Metal validation, GPU capture, normal leaks, ASan/UBSan, and HUD/performance evidence separately when instrumentation can interfere.
- Rendering milestones require a captured and inspected GPU frame. Creating a trace without reading its encoders, resources, bindings, and output is not validation.
- The native boot successor now owns guarded title/audio/RAMROM assets, the 120 Hz paired scheduler, controller mailbox, logical saves, title state, and the bounded title renderer. It must not read the external ROM at runtime.
- Native audio currently renders all three boot music sequences and guarded ADPCM/raw16 waves deterministically. The owner now refills the lock-free 8,192-frame 22,050 Hz ring into an Objective-C `AVAudioSourceNode`; additive V6 fixed-point reverb/composite-SFX vectors and title/menu SFX IDs 18/77/79/111/118/197/199/222/258 pass strict/ASan/UBSan/Release, while the product music/title path applies bounded reverb and schedules source SFX. Full source mix tuning and long-soak A/V evidence remain open.
- The title renderer now consumes source-derived `.gepk` geometry packets for Legal, Nintendo, GoldenEye, Rareware, walletbond, head/suit, and WPPK plus a guarded 64x86 RGBA8 Rareware atlas, seven-row GETI icon packet (`ad3bce58...c256c9`, 23,572 decoded bytes), and the prepared gunbarrel RLE background. Full source lighting/material/animation parity remains unclaimed.
- The native host now validates the guarded `LtitleE` source text catalog (287 decoded strings, SHA-256 `941cad932f414b9d3d86e3dc542c549f6c6c0de0725c4eeb4832be8496b3b4f1`) plus the source GETC packet (302 strings), GETF Zurich packet (94 glyphs/169 kerning entries), direct Legal/File/Mode glyph geometry, source UI bounds, reusable inverse-hit-test layout at 4:3/320x240/16:9/ultrawide, and canonical 440x330 shader letterboxing; full icon pixels remain open.
- All 14 RAMROM recordings now have guarded extracted blobs, a strict parser/playback controller, title-route launch/abort/restore seams, and ASan/UBSan smokes. Stage/gameplay execution and full scene rendering remain unimplemented.
- The seven-stage foundation now has a Swift manifest/catalog validator with deterministic source/decoded/stage hashes, C metadata packet copy-out/decoded-arena view contracts, a Swift 21-resource loader, value-only scene/setup packets for all seven stage payload sets, 468 background rooms, 2,225 setup objects, 2,230 pads/bound pads, and 612 portals (`payload_bytes=2016864`, scene packet hash `13284805027105908470`). A bounded native stage runtime now steps fixed-point player/camera/pad/room/portal state and source object summaries across all seven stages plus one RAMROM trace (`samples=1578`, aggregate `4774828755625742329`); collision, AI, weapons/effects, and Metal scene rendering remain explicit diagnostics.
- The independent Swift/C title parity trace now covers 20,000 native ticks / 10,000 even anchors, verifies the cast-to-RAMROM transition at native tick 6788, and records the remaining unsupported gunbarrel dynamics, GoldenEye odd-tick timer projection, and render-hash fields explicitly.
- A signed Release windowed run recorded 1,530 native ticks, 1,519 supplied drawables, 1,508 presented-time samples, and a 7.8353 ms minimum target interval. An explicit demo-0 launch prepared stage 33, consumed all 454 RAMROM packets, and returned with matching recording/RNG hashes. The all-14 validation lane now runs every demo twice (`runs=28`, `abort_restore=14`) with matching recording/packet/input/checksum/RNG hashes; this still does not substitute for native gameplay/rendering.
- The cadence harness now records named-display logic/target/presented/focus/migration/resize metrics. Direct automated launches prove approximately 120 Hz logic but currently show bursty display callbacks, target p95 near 1 second, and zero presented-time samples on the local WindowServer path; sustained presentation acceptance remains unproven and active.
- The successor goal keeps V1 triangle ABI and M8/M9 evidence frozen; add a separate V2 classic replay ABI rather than changing the synthetic normalizer.
- Canonical ROM-derived prop input is `scripts/filelist.u.csv:308`, `Pammo_crate1Z.bin` at compressed ROM offset `8052448` and size `576`; the validated uncompressed artifact is 1488 bytes, SHA-1 `2902e2f28defaa2f99e514c12039a731e78072d7`, SHA-256 `ca13ff3f26a399767435767fc748cd91027db675ac630d89bfbacc7705b760c9`.
- The prop primary list is 22 classic commands with five `G_TRI4` operations (20 triangles), three `G_VTX` loads (16/16/8), a runtime segment-3 matrix reference, `G_SETTEX` state, and no nested `G_DL`; the replay goal must wrap it with a bounded outer list for push/return coverage.
- Generic texture/TMEM/TLUT and full RDP fidelity remain bounded/deferred; the completed V4 sidecar now lowers only the canonical Type-4 combiner/render-mode state and does not claim generic parity.
- Missing or mismatched extracted assets must fail closed. The native host must never fall back to reading the external ROM or bundle generated private assets.
- The M10 replay/event hashes are stable, but raw `CGWindowListCreateImage` screenshots can vary SDR channels by one code between captures because of the local compositor; retain the screenshot artifact and treat the replay/GPU evidence as the deterministic acceptance baseline.
- The next goal must preserve V1/V2 replay hashes and add V3 texture/material records; do not retrofit texture pointers or mutable texture graphs into existing ABI records.
- Ammo texture source facts are fixed by repository evidence: AMMOCRATE1 is I8/Huffman-blur 64x32, AMMOTEXT765 is IA4/Huffman-lookup 128x16, and CRATEROPE is RGBA16-CI8 with a 256-entry palette at 32x32.
- The crate primary list contains custom `G_SETTEX`/`G_TEXTURE` but no generic texture-load commands. Reproduce the source runtime's bounded material expansion from `ModelFileTextures` and decoded payloads; do not invent source commands or claim generic RDP coverage.
- Metal 4 texture upload requires private shader-readable textures, shared staging, unified compute-encoder copies, committed residency, and explicit event/barrier synchronization. Never silently fall back to the vertex-color diagnostic material.
- The completed M11 textured lane is bounded to the three ROM-derived payloads and the crate's custom `G_SETTEX`/`G_TEXTURE` expansion. The exact replay hashes are packet `11580554792388204033`, event `9845751795158270468`, and material `14168780479827987350`; the runtime matches these hashes at 60 frames/240 draws with six resource allocations.
- M11 provenance is captured in `build/native/classic-textures/classic-texture-manifest.txt`; the external ROM remains outside the checkout and bundle. PNGs are diagnostic only. The inspected capture proves three texture uploads (`64x32`, `128x16`, `32x32` RGBA8Unorm), three compute blits, four render draws, and one texture plus one sampler binding per stage.
- M11 lifecycle evidence is separate from the capture run: resize `960x540 -> 800x450 -> 1024x576`, normal-process leaks `0 leaks for 0 total leaked bytes`, and `shutdown=1`. Local screenshots remain compositor evidence, not N64 visual parity.
- The combiner/render-mode successor is a V4 sidecar: preserve V1/V2/V3 layouts and frozen hashes; never retrofit lowering fields into existing records.
- Source setup for the ammo crate is repository-backed: `ModelType = 4` dispatches `modelApplyRenderModeType4`, whose normal primary path emits two-cycle `G_CC_TRILERP`/`G_CC_MODULATEIA2` and `B900031D C4112078`; the authored prop list later applies `B900031D C4104DD8` for the last two groups. Lower depth/fog/alpha/coverage into auditable deferred fields, not silent defaults.
- The completed V4 sidecar lowers four draw groups at offsets `0x50/0x68/0x90/0xb0` with texture IDs `0x21/0x21/0x27/0x25`; stable hashes are setup `6213740136672363482`, event `5747731189711370311`, and key `16733630809188353388`. V1/V2/V3 hashes remain frozen.
- M12 evidence is isolated under `build/native/m12-*` and `build/native/classic-combiner/`: signed MTL4 pipeline/shader, 60-frame/240-draw runtime, three upload blits, four draws, six allocations, resize, zero leaks, shutdown, screenshot, and inspected `gpudebug` trace. Depth/fog/alpha/coverage are explicit deferred fields, not parity claims.
- Validation refresh 2026-08-18: the final signed Release app rebuild passes
  codesign and the bundle private-payload guard; the external ROM remains
  outside the checkout with SHA-1 `abe01e4aeb033b6c0836819f549c791b26cfde83`.
  Frozen replay, title, audio, stage, RAMROM, and owner-runtime lanes pass,
  plus Swift debug build and `git diff --check`. A bounded API/shader
  validation launch reports no Metal faults. The named-display cadence harness
  still proves near-120-Hz logic/target intervals but can produce bursty
  callbacks and zero presented-time samples under WindowServer automation; do
  not close the 120/60 acceptance gate from this evidence.
- Cadence-owner audit 2026-08-18: direct/fullscreen and WindowServer runs
  reproduced `callbacks=3`, ~120 Hz logic, zero render failures, and zero
  presented-time samples while `CGDisplayIsAsleep` reported
  `active=0 asleep=1 online=1`; bounded `caffeinate` raised callbacks to
  `13/17`. The display-link/drawable path is not diagnosed as a code defect.
  Rerun on an active visible display before closing 120/60.
- M9 raster refresh 2026-08-18: `GEClassicRasterStateV5` is additive and
  hash-stable (`aggregate=2633078999532620274`, states
  `7950540911125037649`/`11514046475163631228`). M12 GPU evidence shows the
  resident `Depth32Float` attachment and `GoldenEye.M9.Depth.*` state; generic
  RDP raster coverage is still deferred.
- M8 title-texture refresh 2026-08-18: additive GETT packets are hash-stable
  and validated at 92 records (Legal 5, Nintendo 1, GoldenEye 2, walletbond
  84) with public C layout, Swift parser/tamper, ASan, and UBSan coverage.
  Direct rows preserve source format/size metadata and GoldenEye's 696-byte
  mip tail; the decoded Metal upload is explicitly base-level-only. The title
  renderer binds the first validated RGBA8 record for Legal/Nintendo/
  GoldenEye/File/Mode and keeps it resident; this is not full mip/TMEM/TLUT
  parity.
- The M8 renderer resource hardening now uses GPU-private shader-readable
  textures plus shared staging buffers, one-time Metal 4 compute copies and
  explicit blit-to-fragment barriers; staging remains resident until the
  renderer drains the GPU at shutdown. Runtime evidence records
  `titleTextureUploadPending=false` and `lastError=none` after submission.
- M9 title-raster refresh 2026-08-18: eight source tuples across Legal,
  Nintendo, GoldenEye, Rareware, and wallet pass `scripts/test_title_raster_v5.sh`
  with aggregate `11519430422207814888`; forced-blend/coverage behavior stays
  explicit and deferred.
- `scripts/test_native_title_raster_catalog.sh` now validates the same eight
  states through a C-to-Swift value-only catalog and associates copied state
  hashes with title screen evidence; no unsupported Metal blend/coverage
  equivalence is implied.
- M10 projection refresh 2026-08-18: additive Projection V10 passes strict and
  ASan vectors with packet hash `15192084148729639549`, covering source
  s15.16 quantization, fixed-width Q16.16 transforms, six-plane clipping,
  winding/culling, and rational 440x330/widescreen inverse mapping. Full
  title/stage draw consumption, lighting, look-at, and texgen remain open.
- M10 title projection consumption refresh: `scripts/test_native_title_projection_evidence.sh`
  consumes all eight guarded GETP packets through canonical 440x330 and
  1920x1080 rational viewports with aggregate `17378376777734745904` under
  strict/ASan; this is transform evidence, not full source lighting/texgen.
- M13 audio soak refresh: `scripts/test_audio_long_soak_v5.sh` passes the
  accelerated 600-second-equivalent source-clock/ring run (`ticks=72000`,
  `frames=13230000`, PCM hash `14458218251061804860`, zero underruns/drops)
  and validates title SFX IDs 18/77/79/111/258. Live AVAudio/A/V evidence is
  still separate.
- GETU title UV refresh: `scripts/test_native_title_uv.sh` passes 1,251
  corner-expanded signed-UV/material records (Legal 36, Nintendo 192,
  GoldenEye 1,023) with source command/vertex hashes and C/Swift sanitizer
  guards. GETU is preparation/parser evidence only; no title draw binding yet.
- The signed title runtime now has an explicit `GOLDENEYE_TITLE_GETU_DRAW=1`
  opt-in homogeneous-triangle binding path: draw indices `6/192/852`, skipped
  corners `30/0/171`, private GETT materials resident, and no Metal validation
  faults. Default fullscreen/GETT rendering remains authoritative.
- M27 stage-background refresh: `scripts/test_stage_background_draw_packet.sh`
  passes a seven-scene diagnostic room/portal overlay packet (`468` rooms,
  `612` portals, `1080` commands, `4032` vertices, aggregate
  `4308406056569914737`) plus standalone Metal shader compilation. Source room
  display-list triangles and stage object/effect rendering remain unsupported.
- The signed `GOLDENEYE_M27_STAGE_OVERLAY=1` route renders stage 33's bounded
  overlay under validation (`frames=3`, `draws=993`, private vertex upload
  complete, `lastError=none`); this does not claim source scene geometry.
- Cadence harness refresh: `GOLDENEYE_CADENCE_WAKE_DISPLAY=1` and
  `GOLDENEYE_CADENCE_STRESS=0` produce an awake no-stress baseline of
  `119.9939 Hz`/`119.9873 Hz` logic on the named 120/60 displays with zero
  dropped ticks, but WindowServer callback counts remain 25/19 and
  `presentedTimeSamples=0`; do not call this presented-fps acceptance.
- Nintendo title refresh: `GoldenEyeBootFlow` now advances the source
  one-degree/60-Hz rotation as a fixed 0.5-degree native half-step, applies
  the source 1.07977 geometric scale growth/clamp, and projects the source
  ambient-light equation into `titleLightQ8`; the Metal title shader consumes
  those values for the procedural Nintendo pass. Texture/material/swoosh
  parity remains open.
- M29 autonomous refresh 2026-08-20: the current guarded stage catalog is
  `build/native/stage-assets-image-decoder-v6`; the legacy `stage-assets`
  directory lacks `resource_count=21`/`manifest_status=PASS` and must not be
  used for current scene validation. Fresh stage setup/scene/background/
  gameplay, all-14 RAMROM, source-scene, title, audio, Rareware, Gunbarrel,
  and File/Mode lanes pass with the corrected root.
- M29 rendering evidence refresh 2026-08-20: the signed source-faithful
  Release executable SHA-256 is
  `4d811c66564164d7fffbce11dfb0b5a70e66a3bf8d1bff08fa92a225ec0aa9ab`;
  codesign and bundle guards pass. The fresh M27 supplied-drawable trace is
  `build/native/m27-stage-background/goldeneye-m27-stage-background.gputrace`
  with one compute encoder, one 331-draw render encoder, a BGRA8 drawable, and
  the labeled private vertex resource confirmed by `gpudebug`.
- Gunbarrel cache refresh 2026-08-20: immutable decoded topology/state/
  material/provenance caching preserves C authority and lowers model-build p95
  from `31.592 ms` to `25.362 ms`; dynamic pose/matrix work remains the 120 Hz
  risk. The separate V7 gameplay-camera room+static-prop adapter passes strict,
  ASan, and UBSan for demo 0/stages 33 and 34 (`197/197` and `267/267`
  drawable props, scoped mask `0x0`) while retaining the full-scene `0x38`
  unsupported mask; it is not yet owner/Release integrated.
- Cadence refresh 2026-08-20: headless/login-window measurement records logic
  `120.0023 Hz`, renderer callback p95 `0.75 ms`, but zero presented
  timestamps and target p95 `1008.35 ms`; this is not 120/60 acceptance.
- M29 autonomous refresh 2026-08-21: canonical signed Release app is
  `build/native/boot-runtime/source-faithful/GoldenEyeHost.app`, executable
  SHA-256 `e8c0636bf0d8e7daeea9593ed40ca9e2c690c0927d1503e789450a870d49797e`;
  bundle and frozen Release history/provenance gates pass. V7 gameplay-camera
  owner/renderer integration is opt-in and fail-closed; strict/ASan/UBSan
  demo-0 stage 33/34 packets pass with `197/197` and `267/267` props, scoped
  mask `0x0`, retained full-scene `0x38`, and deterministic hashes.
- Cast M29 refresh 2026-08-21: source-row/full-handle texture aliases,
  per-model source render modes, embedded-head attachment handling, and exact
  vertex provenance pass strict/ASan/UBSan attachment plus chrfnp90 builder
  lanes (`commands=64`, `setups=7`, `vertexResources=10`, `draws=7`,
  `unsupported=0`). Strict Metal/API+shader Cast reference output repeats
  byte-identically (`15e657b9...` reference raw,
  `cbeaee5f...` Faithful HD raw). Source-preserving prewarm caches 76 Cast
  topologies in `6,603,487 us` and a first-route three-model builder packet in
  `67,374 us`; it does not relax the debt guard or skip per-tick C pose work.
- Fresh stage M29 validation: all seven source-environment Metal captures pass
  API/shader validation with `nonBlack=1`/`textured=1`; all-14 gameplay-camera
  checkpoints pass (`42` records); bounded gameplay remains explicitly
  unsupported for `effects,ai,weapons,collision`. The supplied-drawable stage
  binding probe and inspected M27 trace pass. The live AppKit Cast attempt is
  retained as `castSubmit=0`, `latestCrash=none` at the headless/login-window
  boundary, not as source-render failure.
- M29 dynamic-pose/title/fog continuation 2026-08-21: immutable correction and
  texture-coordinate caches reduce suitbond production-shaped timing from
  `29,281/29,719 us` p50/p95 to `11,437/11,509 us` while preserving scene/render
  hashes; GBI/Gunbarrel/chrfnp90 strict/ASan/UBSan pass. GoldenEye's exact
  `0x00112000/0x0C182048` two-cycle LOD tuple now passes strict/ASan corpus and
  two API+shader captures with identical raw hashes (`4eec74ef...` 320x240,
  `f7ec1001...` Faithful HD). Fog has a typed source-hashed fixed-point factor
  contract and sanitizer coverage, but production remains fail-closed because
  the fragment path does not yet consume the preserved eye-space Z/clip-W
  payload.
- The final signed Release after this continuation is
  `build/native/boot-runtime/source-faithful/GoldenEyeHost.app`, executable
  SHA-256 `d74d1ee9bda3c1546b018deedff3d7ec18c8a208cf5213b37372985c575b3ce5`;
  Release policy and frozen history/provenance gates pass.
- Corrected offscreen Cast row-2 evidence now exists at
  `build/native/cast-reference-capture-v6/20260822T-cast-spicebond-row2-randomword3/`:
  Metal API/shader validation passes `capturedIdentity=2`,
  `capturedBody=spicebond`, `randomWord=3`, `missingPrepared=0`,
  `unsupportedVisibleCount=0`, and a byte-identical repeat. Raw hashes are
  `64766bd2d6667ab0ec1d633922f8424addb6d56fd7e04bb2a17bf3e6c3a04663` and
  `c5c38bce7123d960d89e6966284fb8ad5835a914d9200eaa162687d63f27b60c`.
  The earlier `...row2-current` artifact resolves Natalya with an even random
  word and is explicitly not Spicebond evidence. Keep this separate from the
  still-blocked live Cast supplied-drawable gate.
- Final `d74d1ee9...` cadence run at
  `build/native/boot-runtime/cadence/runs/20260821-final-lod-headless/` keeps
  logic near 120 Hz with zero dropped ticks (120: `119.9913 Hz`, fixed-60:
  `120.0021 Hz`) but zero presented timestamps and harness `pass=0`; do not
  close physical 120/60 acceptance from headless evidence.
- Stage fog payload continuation: `GoldenEyeStageBackgroundDrawPacket` now
  carries an additive parallel eye-space-Z array computed from the source
  camera model-view before projection and preserved through clipping into the
  copied stage snapshot/GPU vertex view. The historical 32-byte vertex and
  frozen C ABI are unchanged; seven-stage source-environment strict/ASan/UBSan
  passes with aggregate `10879306652781644554`. Exact `gSPFogPosition` fragment
  binding consumes the signed fm/fo and source color for the admitted fog mode;
  other fog modes remain fail-closed.
- Packet-coordinate-only Release verification 2026-08-21: strict codesign,
  Release history/provenance, debug build, Metal source-scene, host ASan/UBSan,
  fog-lowering, source-scene corpus, and V7 gameplay-camera packet lanes pass.
  The current canonical executable SHA-256 is
  `e8c0636bf0d8e7daeea9593ed40ca9e2c690c0927d1503e789450a870d49797e`; retained
  headless cadence artifacts still have no presented timestamps.
- Exact-fog continuation 2026-08-21: per-stage clip ranges, Q16 homogeneous
  clipping/recompute, distinct eye/fog hash domains, composition/V7 sidecar
  propagation, and environment-only mask retention are covered by strict,
  ASan, and UBSan lanes. Stage environment aggregate is
  `10879306652781644554`; V7 packet hashes are
  `11113608939106626920`/`15466404641097031372` for stages 33/34. Fresh
  all-14 gameplay-camera Metal API/shader checkpoints pass (`42` records), and
  repeated Cast reference raw hashes are `7edb15fd...`/`765f3c38...`. The
  current signed Release executable is
  `e8c0636bf0d8e7daeea9593ed40ca9e2c690c0927d1503e789450a870d49797e`.
- Fresh current-Release cadence attempts at
  `build/native/boot-runtime/cadence/runs/20260821-final-exact-fog-loginwindow/`
  and its fixed-60 sibling measure logic `119.9964`/`120.0033 Hz`, zero dropped
  ticks and zero renderer failures, but zero presented timestamps because the
  host remains behind `loginwindow`; this is not physical 120/60 acceptance.
- Follow-up Luna audits found no source-complete next dynamic category: guard/
  character routes still lack authoritative animation/head-RNG/SwitchNode and
  render-context fields, while HUD/effects records lack live weapon/inventory
  producers. Keep those diagnostics and the full-scene mask fail-closed.
- Fresh title texture/raster lanes pass (`92` GETT records, raster aggregate
  `11519430422207814888`); source mip-tail/TLUT evidence is validated, while
  the legacy fullscreen title consumer remains base-level-only.

# Feature Status

| Feature Domain | Status | Notes |
|---|---|---|
| Source provenance / Git | Implemented | Shallow local `HEAD` references upstream `c4356466796c697dfd298010b9bed261f9ed8c6a`; tracked source matches except documented Darwin portability edits. |
| Original N64 build baseline | Implemented | The native Linux qemu-irix reference lane passes `sha1sum -c ge007.u.sha1` with the expected US ROM hash; macOS remains a documented portability lane. |
| External ROM provenance | Implemented | Correct US ROM SHA-1 verified; remains external and untracked. |
| Extracted asset pipeline | Implemented | M11 provenance extraction is repeatable, guarded by exact ROM/imagelist offsets and hashes, and writes only ignored build output; private payloads are not bundled. |
| Native Apple-Clang archive | Implemented | M1 archive/test harnesses pass under `scripts/test_native_m1.sh`; N64 objects remain out of the archive. |
| Fixed-width C/Swift ABI | Implemented | C and Swift layout assertions, malformed-input tests, and pointer-free V1/V2 boundary checks pass. |
| Deterministic fixture producer | Implemented | Synthetic three-vertex/two-command triangle fixture is deterministic; GBI normalization remains M7. |
| AppKit window | Implemented | M2 Apple Development-signed macOS 27 bundle launches a raw scale-correct `CAMetalLayer`; no `MTKView`. |
| Owner-thread lifecycle / main loop | Implemented | Native successor adds a dedicated Thread/CFRunLoop, raw-clock 120 Hz scheduler, paired anchors, pause/rebase, and debt telemetry; legacy probes remain intact. |
| Keyboard input | Implemented | Native successor adds a 256-event raw-clock mailbox, source mappings, once-only edges, focus suppression, and pure smoke coverage. |
| GameController gameplay input | Partial | Buffered polling with queue depth 20, analog conversion, connection/disconnect handling, and mapping smoke are implemented; long physical-controller acceptance remains. |
| Metal 4 device / capabilities | Implemented | M4 rejects non-Metal4 and creates a labeled device-owned queue; no silent Metal3 fallback. |
| Metal 4 queue / frame slots | Implemented | Two reusable labeled command-buffer/allocator pairs are created and retained. |
| Argument tables / residency | Implemented | Initialized labeled argument table, scene residency, layer residency, and shared completion event are proven. |
| Presentation / first clear | Implemented | M5 queue-level acquire/wait/commit/signal/present, shared-event slot retirement, synthetic pause/resume probe, validation, and trace evidence pass. |
| Baseline MSL / pipeline state | Implemented | M6 MSL AIR/metallib and labeled MTL4 function-descriptor pipeline pass with zero draws. |
| Fixed-width GBI wire format | Implemented | M7 stream/normalization records use fixed words, resource handles, and value-only return records. |
| Minimal GBI normalization | Implemented | Valid and malformed/unsupported `G_VTX 0x04`, `G_TRI1 0xBF`, `G_ENDDL 0xB8` cases pass C/Swift/ASan tests. |
| Vertex drawing | Implemented | M8 draws the normalized M7 packet through MTL4 argument-table GPU-address binding and resident shared vertex data. |
| Classic replay ABI v2 / state snapshots | Implemented | Fixed-width copied commands, segment/resource handles, state snapshots, source offsets, and deterministic event hashes pass while V1 remains frozen. |
| Nested display lists / segments | Implemented | Classic `G_DL` push/branch/return, `G_MOVEWORD` segment aliases, cycle rejection, and command/depth budgets pass. |
| Matrix / viewport / transforms | Implemented | Classic s15.16 matrices, modelview/projection stacks, viewport mapping, transformed draw hashes, and additive Projection V10 clipping/culling/inverse-layout vectors pass; lighting/look-at/texgen draw consumption remains deferred. |
| ROM-derived ammo-crate ingestion | Implemented | External `Pammo_crate1Z.bin` manifest/hash guard and C parser replay 40 vertices/20 triangles in source order pass. |
| Static prop Metal replay | Implemented | Four transformed draw packets render through Metal 4 argument tables/residency; V2 remains the explicit vertex-color diagnostic lane. |
| Texture/material ABI v3 | Implemented | Fixed-width V3 UV/material/TMEM/TLUT records and deterministic packet/event/material hashes preserve V1/V2 layouts and hashes. |
| PD texture decoding | Implemented | Bounded native decoders cover I8/Huffman-blur, IA4/Huffman-lookup, and RGBA16-CI8/TLUT with malformed-input tests and deterministic decoded hashes. |
| TMEM/TLUT material state | Implemented | The crate's custom `G_SETTEX`/`G_TEXTURE` sequence expands to bounded texture-image, tile, TMEM, and TLUT plans; generic RDP load commands remain out of scope. |
| Metal 4 texture upload/sampling | Implemented | Private RGBA8 textures use shared staging and unified compute copies with residency, event/barrier synchronization, argument-table texture/sampler bindings, and no fallback. |
| Textured ammo-crate material | Implemented | All four crate draw groups render source UVs with the explicit `TEXEL0 * vertex shade` material; runtime and capture bindings are inspected. |
| Textures / TMEM / TLUT / samplers | Partial | Bounded M8 GETT title rows and M11 crate material paths are implemented; title decoded uploads are base-level-only, while generic texture database, full mip/TMEM/TLUT, RDP load commands, and full combiner parity remain deferred. |
| Classic combiner / render-mode lowering | Implemented | V4 sidecar decodes the canonical Type-4 setup and authored mode transitions into four deterministic draw keys; Metal consumes bounded TRILERP/MODULATEIA2 and blend variants, and the additive M9 title-raster audit covers eight source tuples with forced-blend/coverage explicitly deferred. |
| Depth / fog / alpha / coverage parity | Partial | Additive `GEClassicRasterStateV5` lowers canonical ammo-crate modes `C4112078`/`C4104DD8`; M12 Metal 4 binds a resident Depth32Float attachment, depth compare/write states, alpha compare/dither, source fog `(0,0,0,38)`, alpha-to-coverage, and explicit coverage diagnostics. Generic RDP coverage/raster parity remains deferred. |
| Full source display-list production | Partial | M7 now gives the bounded source graph a typed node-family view across eight GESM sidecars (225 nodes, all required group/BBOX/DL/BSP/SWITCH/LOD/shadow/head/gunfire families) and the additive GETN title packets copy 138 hierarchy nodes/92 texture rows; GETU still copies 1,251 signed-UV/material corners, while full display-list command/material traversal and stage production remain deferred to M8–M10. |
| Audio | Partial | Guarded bank/CSeq parsing, ADPCM/raw16 decoding, deterministic 22,050 Hz boot-track PCM, lock-free SPSC/source-node output, additive V6 reverb/composite-SFX vectors, product small-room reverb integration, route recovery, and a 600-second-equivalent zero-underrun synthetic soak pass; full source mix and live long-soak A/V acceptance remain. |
| Saves / replay | Partial | Exact 596-byte logical save codec/store/recovery, async owner persistence, all 14 RAMROM blob/parser checks, paired playback controller, Swift owner service, all-14 twice/abort-restore validation, one explicit stage-scene runtime route, and title-route restore seams pass; source stage/gameplay rendering remains. |
| Native title/menu boot | Partial | Paired Swift title state reaches Legal/Nintendo/Rareware/Gunbarrel/GoldenEye/File/Mode/Cast/RAMROM states with input/save/route smokes; guarded GETF/GETC/GETI/GETN/GETT/GETU packets, direct geometry, UI bounds, inverse-hit-test layout, widescreen letterboxing, title SFX routing, and two-stage erase confirmation are integrated; GETU draw binding is opt-in and partial, and full source model/material parity remains. |
| Native stage renderer | Partial | All-seven source environment/material lanes, exact G_FOG SHADE binding, and opt-in V7 room/static-prop gameplay-camera compositions pass with scoped `unsupportedMask=0x0`; the dedicated production supplied-drawable capture harness compiles and is explicit SKIP when no Metal 4 device is available, so room-plus-props pixel/gputrace acceptance remains open. Characters, effects, AI, HUD, and full gameplay scene submission remain deferred. |
| Native title Metal renderer | Partial | Metal 4 supplied-drawable pipeline, source-derived title/Gunbarrel/Cast fixtures, exact GoldenEye two-cycle LOD/combiner admission and deterministic repeat captures, GETN/GETT packets, first-level RGBA8 bindings, Cast texture/render-mode/attachment lowering, Cast topology/first-route prewarm, canonical letterboxing, signed bundle, API validation, and inspected GPU capture pass; full lighting/material/mip/animation parity and live Cast presentation remain open. |
| Debug markers / resource labels | Implemented | M8/M10/M11/M12 frame, encoder, pipeline, buffer, texture, staging, and draw labels are present in inspected captures. |
| Metal validation | Implemented | M4–M12 real-device runs use API/load/store/shader validation; no reported Metal fault. |
| GPU capture / `gpudebug` | Implemented | M5/M8/M10/M11/M12 `.gputrace` captures plus command-tree, compute, draw, texture, pipeline, sampler, binding, and attachment inspection pass; resource fetch remains environment-limited. |
| ASan / UBSan / leaks | Implemented | C/M1/M7/M11/M12 ASan/UBSan runs pass; the separate normal M11/M12 textured hosts report zero leaks. |
| Metal HUD / resource stability | Implemented | M9 synthetic, M10 classic-prop, and M11 textured runs pass 60 frames with explicit residency/resource counts; M11 resize, shutdown, and validation also pass. |
| Emulator/reference visual parity | Not started | No reference artifacts currently available. |
| Sustained performance / release | Partial | Signed Release boot/menu, dynamic-pose timing improvement (`29,281/29,719 us` to `11,437/11,509 us` p50/p95), one explicit RAMROM stage-scene run, supplied-drawable telemetry, target-presentation interval/presented-time fields, local 60/120 evidence, and current screenshots pass; sustained owner-loop 120/60 presented-time, CPU/GPU p95, and all-route soak remain. |

Status values: Not started, Stubbed, Partial, Implemented.

# 2026-08-21 source head-selection continuation

- Added goldeneye_ramrom_character_head_selection_v6.swift with exact
  bodiesReset/bodyChooseHead RNG consumption through the existing C transition.
  Character snapshots accept the selected value record but keep animation,
  render-context, and SwitchNode attachment diagnostics fail-closed.
- Strict/ASan/UBSan head-selection and character-scene gates pass. The signed
  Release rebuild has executable SHA-256
  c93c0c0a297ad99e4ef43dbdae5cf8a2a83791b0e66fe76a8a10f124bf96398b; Release
  history/provenance passes in the signing keychain context.

# 2026-08-21 projection/dependency/material continuation

- Stage gameplay projection now uses raw source viSetZRange ranges and maps
  source symmetric depth into Metal depth; the fog sidecar retains
  source-symmetric coordinates. Fresh stage environment/V7 strict,
  ASan, and UBSan gates pass with environment aggregate
  2034083543171337301 and V7 hashes
  10787550995629497797/5096764590307538101.
- GuardRecord type-9 dependency extraction now reads bodyAI at +0x08 rather
  than chrnum. Setup references=1783, unique=141; Dam bodyID 37 maps to
  greatguard2. Corrected body joins pass setup/gameplay/character/all-14
  validation, while animation, attachments, and render context remain open.
- Source-title GESM contract smoke passes with textures=92, mips=199,
  TLUTs=2, aggregate
  4247163796f6616e44965ad3ad846d5de46311005d75984f9a4a7be9c201d848.
  GPU TLUT lookup remains unclaimed.
- Current signed Release executable SHA-256 is
  5cf6baf72fed8f6ba855d924f111e0dad418c2c7b105306364e644eebf4b9f4f.

# 2026-08-21 fresh scoped-lane validation

- Re-ran V7 gameplay-camera, source fog, corrected setup dependency,
  head-selection, title-material, gameplay-orchestrator, and character-scene
  strict/ASan/UBSan gates. V7 remains props 197/197 and 267/267 with scoped
  mask 0x0 and retained full-scene mask 0x38; orchestrator aggregate remains
  4035581654071229827.
- The direct supplied-drawable production harness compiled with Metal API and
  shader validation, then explicitly SKIPped because this host has no Metal 4
  device. No physical pixel or gputrace acceptance is claimed; character
  animation, attachments, and render-context diagnostics remain fail-closed.
- The bounded C guard/door owner now follows source portal lifecycle state
  rather than current open fraction, preserving portal activation from open
  start through close completion. Guard-door strict/ASan/UBSan/Swift adapter
  validation passes with portalLifecycle=1; STAN geometry and full collision
  traversal remain unimplemented.
- The canonical source-faithful Release was rebuilt after the C change with
  stage preparation resources=21, codesign, boot-release verification, and
  history/provenance passing. Executable SHA-256 is
  5cf6baf72fed8f6ba855d924f111e0dad418c2c7b105306364e644eebf4b9f4f.

# 2026-08-21 additive STAN topology continuation

- An additive GEPlayerCameraStanLinkV7 sidecar now preserves source
  StandTilePoint.link edges using firstTile - 0x80 + (link << 3), without
  changing frozen V6 tile layouts. The topology-aware owner accepts only
  linked cross-room floor transitions and rejects disconnected-room movement.
- Fresh player-camera/orchestrator strict/ASan/UBSan lanes pass. Link counts
  by stage are 6750/5748/1210/2760/6050/4230/1488; orchestrator aggregate is
  1689065738426998688 (player-camera) and 4410795521714608326 (orchestrator).
  Portal polygons, level-scale, door collision, and full
  STAN edge-slide behavior remain unimplemented.

# 2026-08-21 source portal geometry continuation

- Added a value-only V7 portal geometry catalog parsing all 612 setup portal
  polygons from exact big-endian float32 `bg_portal_entry` records, preserving
  Q16.16 points, raw rooms/control bytes, hashes, and fail-closed bounds.
  Strict/ASan/UBSan passes; door portal assignment still needs source STAN
  room sampling and bgGetPortalBetweenRooms.
- Guard/door pages now derive all 397 portal IDs from bound-pad center ±50
  source STAN samples and polygon intersection (`67` unique IDs,
  portalHash=13325078266282593292). Character/AI page readiness remains
  fail-closed; no dynamic door renderer submission is claimed.

# 2026-08-21 dynamic door source-submission continuation

- The door-only source owner is heap allocated, uses C validation to retain
  only valid door rows, and publishes bounded 32-item pages. It carries source
  record/object/model/portal identity, lifecycle/open state, Q16.16 position,
  all sixteen transform words, interpolation/anchor flags, and source hash;
  the full guard owner and its `sourceReady=0` diagnostics remain separate.
- The environment Dam route publishes four dynamic doors. Odd native ticks use
  C interpolation and even ticks consume source rows. Frame hashes include all
  transform words and dynamic fields. Restore snapshots copy the owner bytes;
  the all-14 strict/ASan/UBSan orchestrator smoke reports
  `environmentDynamicDoors=4 dynamicRestore=1`.
- V7 gameplay-camera dynamic transforms are type-1-only, visible-object-only,
  require sixteen finite Q16.16 words and a nonzero source hash, and alter
  packet/composition hashes (stage 33 `3209083801982227650`/
  `9272436217739127194`) while preserving scoped `unsupportedMask=0x0` and
  full-scene `0x38`. The production supplied-drawable probe compiles and
  explicitly SKIPs on this host because no Metal 4 device is available.
- Fresh signed Release executable SHA-256:
  `6e81f6faaf9cda114e014cfc970a3c7422afb615618822efd3abace28490dde4`.
  Stage preparation reports `resources=21`; frozen Release provenance passes.

# 2026-08-21 unified gameplay/traversal and active-display continuation

- Added fixed-width `GERamRomGameplayPlayerCameraSnapshotV7` reconciliation;
  direct C strict/ASan/UBSan passes (`layout=176 direct=2 eventHash=1`) and
  all-14 orchestrator strict/ASan/UBSan passes with gameplay/player-camera
  equality, aggregate `3432588557158677409`, and `environmentDynamicDoors=4`.
- Added source `levelscale` conversion for all seven STAN/pad/world paths and
  bounded source-style edge-slide projection. All 14 player/camera routes pass
  strict/ASan/UBSan with aggregate `5860224076221260218` and `stanEdgeSlide=1`.
- Fresh V7 stage packet sanitizer hashes: stage 33/34 packet
  `4344127377687538898`/`2739797606600666455`; dynamic stage-33 packet/
  composition `2020772946810887752`/`17747242490227606699`; scoped mask `0x0`,
  retained full mask `0x38`.
- Active Aqua cadence measured fixed-60 `59.951 FPS` with zero rejected
  samples, 120 short `118.653 FPS`, and 120 six-second `119.273 FPS` with
  readiness/rejection gaps. Supplied-drawable stage capture reached the
  renderer but failed closed on GBI lighting state `0xe2100001`; no gameplay
  pixel/gputrace acceptance. Current headless session prevents immediate rerun.
- Current signed Release executable SHA-256:
  `97adbc3668b1b2fef768bfe32972fc0ff592abda0a782107d90e05c281be5e6f`.

- Scale-domain follow-up: `GoldenEyeStagePlayerCameraSnapshotInputV6` now
  declares serialized versus runtime-scaled coordinates. NativeTitleOwner
  marks the runtime-scaled player handoff; the adapter converts it to
  serialized room space before level-scale rebasing. Stage environment
  strict/ASan/UBSan passes equivalent-domain matrix checks and aggregate
  `2034083543171337301`.
- Display-link follow-up: pause generation is carried through callback timing,
  queued callbacks are canceled on pause, stale pause-generation drawables are
  rejected, and presented handlers register before `present()`. Owner smoke and
  headless soak pass (`ticks=241 rate=120.0 dropped=0 maxDebt=1`); physical
  focus migration and sustained 120-Hz proof remain open.

# 2026-08-21 M22 Mode Select completion

- Mode Select now has fresh Metal API/shader-validated reference evidence using
  the release-consumable `build/native/source-frontend-v6-image-decoder-v6`
  root. Solo/multiplayer selected-wallet scenes render non-black; 320x240
  draw/triangle counts are `12/47`, and Faithful-HD/adaptive layout captures
  pass with deterministic hashes. Selected material payload linkage includes
  EYESONLY/FORYOUR/OHMSS/GBGRADIENT plus Wallet base rows.
- The initial crash was traced to using the legacy `build/native/source-frontend-v6`
  root, whose wallet decoded rows are black; current release root selection is
  now explicit in the reproduction command. The stale all-black payload
  assertion was replaced by source metadata completeness; rendered scene
  readbacks still require non-black output.
- Physical controller/mouse interaction, complete multiplayer parity, and N64
  pixel parity remain open.

# 2026-08-21 M21 File Select completion

- File Select bounded authority/integration passes strict/ASan/UBSan and paired
  Swift validation. Wallet graph retains `90` nodes, `42` SWITCH nodes,
  `43` source switch records, `982` commands, `765` vertices, `84` textures,
  `186` mips, and `2` TLUTs; `42` metadata-authorized branch routes pass.
- Source 2D File/Mode reference passes blank/completed wallet surfaces,
  corrected erase confirmation, Mode rows/previous tab, exact 320x240 and
  1760x1320 layout, and `unsupported=0`. Background contract is `440x299`,
  source x-offset `-28`, with source hash preserved.
- Full source save/UI/pixel parity and physical interaction remain open; no
  procedural folder or confirmation content is substituted.

# 2026-08-21 M20 GoldenEye-logo completion

- GoldenEye logo bounded source capture passes Metal API/shader validation:
  source `162` commands, `339` rendered triangles, `341` source triangle slots,
  `438` vertices, `7` mip levels, `2` textures, zero TLUTs, and zero unsupported
  visible work. Paired native ticks are `3423/3424` with source timers `0/1`;
  projection consumption is complete and source gold/red pixel checks pass.
- Fresh 320x240 and Faithful-HD PNGs were visually inspected; the logo and red
  ring are present on the source black canvas. Raw hashes are retained in
  `build/native/goldeneye-logo-reference-capture-v6/20260822T011107Z/`.
  This is native-port evidence, not N64 pixel parity.

# 2026-08-21 M19 Gunbarrel completion

- Gunbarrel bounded source path passes sidecar/root-motion/pose/dynamic builder
  and source transition gates. The prepared sidecar contains `24` clips and
  three skeletons; blood is exactly `42` frames and modes `2,3,4,5,6,7,8,9`
  are source-complete. Dynamic builder timing is bounded and exactDraws are
  source-provenance tracked with zero fallback draws.
- Fresh Metal API/shader-validated temporal capture passes modes 2–9 and timers
  `40,50,100,136,137,152,168,169,212,230,348,400`. Mode 2 is `70` draws/
  `872` triangles; mode 5 and timer 230 are `71`/`874`. The mode-5 capture was
  visually inspected; this is native evidence, not N64 pixel parity.
- Sustained live owner cadence, complete N64 skeletal/weapon parity, and full
  physical presentation remain open.

# 2026-08-21 M18 Rareware-screen completion

- Rareware bounded source capture passes with Metal API/shader validation:
  source `9` display lists, `389` commands, `268` triangles, `397` vertices,
  `6` textures, `26` mip levels across `4` chains, and zero unsupported visible
  work. Phases cover odd `t20` rotation `65536`/fade `72`, even `t70`
  rotation `6553600`/fade `255`, front `t200` rotation `23592960`/fade `110`,
  and late `t260` fade `0`; every phase consumes `268/268` projections.
- Fresh 320x240/Faithful-HD PNGs were visually inspected (including the source
  Rareware mark at t200); native capture is not N64 pixel parity. Canonical
  LOD/FORCE_BLEND negative guards and source SFX `258` pass.

# 2026-08-21 M17 Nintendo-screen completion

- Nintendo source timing/skip, fixed-point half-step rotation, 1.07977 scale
  clamp, and ambient-light projection pass the paired source authority. The
  fresh Metal API/shader-validated reference capture passes at native ticks
  `590/591`, source timer `50`, commands `821`, source triangles `1021`,
  rendered triangles `1018`, and non-black/textured output. Even/odd raw hashes
  are `1e3b7e0fde0fd36213572e5d3ccb5bd343c7bbf4adec214676b08f3277816788` /
  `672fa141b493f343249bdd775472af8942f52760cc1fab59d601c27ffb278ac2`.
- 320x240 and 640x480 Faithful-HD PNGs were visually inspected; this is native
  port evidence, not N64 pixel parity. Full source swoosh/material parity and
  sustained physical presentation remain open.

# 2026-08-21 M16 Legal-screen completion

- The bounded source Legal frame passes strict/ASan/UBSan: 58 GBI commands,
  12 triangles, five source texture/material groups, 12/12 projection
  consumption, 12 source text events, 253 glyphs, zero unsupported visible or
  decoder commands, and deterministic frame hash `4631003346486038644`.
- Legal timing/reference checks pass: 10,000 title anchors, 287-string text
  catalog, exact 241-tick first-boot rule, first-boot input suppression, and
  source text order `7...18`. The 320x240 semantic capture writes lossless
  raw/PNG/JSON artifacts; no physical N64 pixel parity is claimed.
- The File/Mode M11 correction keeps source cursor hit bounds authoritative and
  does not change Legal source hashes.

# 2026-08-21 M13 native synth/effects completion

- The bounded 22,050 Hz native synth/effects contract passes: V5 compact
  sequence voices/envelopes/loops/pitch/pan/gain, V6 Small/Big Room fixed-point
  reverb, composite SFX graph/bank lowering, and title SFX IDs
  `18,77,79,111,258`. Strict/ASan/UBSan/Release effects vectors are
  deterministic (`graph_hash=10304920864406538052`,
  `reverb_hash=6148009325550816421`).
- The 600-second-equivalent/72,000-tick soak passes with `13,230,000` frames,
  PCM hash `14458218251061804860`, zero underruns/drops, and block-size-
  independent hashes. `native_audio_service.swift` keeps the large reverb bus
  heap-backed to avoid owner-thread stack exhaustion.
- The frozen V5 `ge_audio_feature_status_v5` STUB responses remain a legacy
  compatibility boundary; production effects use the explicit V6 owner-side
  contract. The composite graph is currently offline-only; production renders
  individual V5 SFX plus Small Room reverb. The owner-side `ScheduledSFX`
  queue already provides bounded sample-indexed overlap; the graph lacks
  streaming voice state, matching wave-end semantics, prepared-bank caching,
  and persistent post-mix reverb. File/Mode sidecar SFX now forward through a
  separate source-audio binding namespace, while full source mix tuning and
  live AVAudio A/V evidence remain open.

# 2026-08-21 M13/M14 File-Mode SFX forwarding continuation

- File/Mode sidecar SFX events now enter `GoldenEyeNativeAudioService` through
  a separate `GoldenEyeSourceAudioBindingV6` state, isolating menu event
  sequences from the frontend audio sequence namespace. Forwarding remains
  sample-indexed and owner-side; realtime callback work is unchanged. The
  sidecar cursor resets on both active and inactive game resets and on menu
  authority session re-entry.
- Source binding namespace/duplicate tests, deterministic audio engine/effects
  strict/ASan/UBSan/Release lanes, and Swift debug build pass. Composite SFX
  remains an offline V6 graph and live AVAudio/A/V timing remains open.
- Expanded title/menu bank validation covers IDs `18,77,79,111,118,197,199,222,258`
  with combined hash `9686333082073475502`; menu-session reset and independent
  sequence cursors are covered.
- Current `test_audio_output_v5.sh` passes strict/ASan/UBSan C output and the
  AVAudioSourceNode adapter (`ticks=8`, `preroll=367`, `underruns=0`); the
  harness preserves explicit SKIP classification for unavailable audio routes.

# 2026-08-21 M11 2D/adaptive-layout completion

- The bounded source 2D path passes guarded font/catalog/icon packets, source
  fills/scissors/texture rects, File Select wallet/progress rows, Mode Select
  rows, and the two-stage erase-confirmation overlay. The corrected synthetic
  route reaches erase confirmation through the authored cursor hit bounds.
- Reference layout checks pass exact 320x240 and 1760x1320 source-to-output
  mapping, adaptive letterbox/inverse-hit-test contracts, and `unsupported=0`.
  Title textures/icons/nodes/raster and title-reference lanes remain passing;
  GPU capture is still a separate Metal 4 presentation gate.
- Physical visible-desktop UI/focus/cadence and complete source-identical UI
  parity remain open. Do not substitute procedural text or stretch the 440x330
  source canvas.

# 2026-08-21 M10 transform/lighting completion

- The bounded source transform/lighting path is complete: Projection V10
  preserves fixed-width Q16.16 projection/model-view, six-plane clip/cull and
  canonical/widescreen mappings; source lighting carries geometry mode,
  normal transform, ambient/directional colors/direction, reflection vectors,
  and per-draw model-view records through immutable snapshots.
- Strict/ASan/UBSan projection, lighting/texgen, projection binding/consumption,
  title projection, and source-scene renderer/shader lanes pass. Projection
  hash is `15192084148729639549`; title packet aggregate is
  `17378376777734745904`; source-scene Metal 4 shader compilation passes.
- Linear texgen and generic unclassified look-at/material variants remain
  typed fail-closed diagnostics. No default normal, light, reflection, or
  matrix is invented for an unknown source state.

# 2026-08-21 M9 combiner/raster completion

- The bounded M9 source contract now passes canonical one/two-cycle combiner
  selectors, primitive/environment/shade/fog inputs, depth, alpha compare,
  coverage, culling, blend, and render-mode policies. Classic raster V5,
  title-raster V5 (`8` tuples, aggregate `11519430422207814888`), source
  pipeline corpus, and Rareware/GoldenEye LOD/FORCE_BLEND guards pass strict
  and sanitized validation; invalid generic tuples remain typed fail-closed
  diagnostics.
- Canonical combiner replay remains frozen (`setup=6213740136672363482`,
  `event=5747731189711370311`, `key=16733630809188353388`), and the Metal
  shader path retains explicit fog/alpha/coverage fields. Full arbitrary RDP
  raster parity is not claimed.

# 2026-08-21 M8 texture/TMEM/TLUT lowering completion

- The bounded source-product texture path now has complete deterministic
  descriptors for all eight GESM models: `122` unique textures, `322` source
  mip levels, and `25` TLUT/palette records. Exact source tile/address state,
  wrapping/mirroring/clamping, texture scales, LOD, and sampler flags remain
  value-only records; source RGBA/CI/IA/I payloads are validated into RGBA8
  GPU upload descriptors without a fallback.
- Strict/ASan/UBSan source texture setup/store lanes pass. The Metal 4 store
  smoke passes private full-mip uploads with shared staging, one committed
  residency set, queue-level synchronization, and explicit blit-to-fragment
  visibility; irregular authored mip dimensions `65,33,17,9,5,3,1` pass.
  Stage texture catalog and source-scene binding pass with `436` textures,
  `248` TLUTs, `568` levels, and `3,575` bindings.
- The old GETT title diagnostic packet remains base-level-only and GPU TLUT
  sampling is not claimed; those are later generic material/visual-parity
  work, not a reason to weaken the source-product M8 contract.

# 2026-08-21 M7 model/node ingestion completion

- `GoldenEyeSourceModelV6.NodeKind` now gives the value-only GESM graph a
  typed, fail-closed view of source opcode families. Eight guarded sidecars
  contain 225 nodes and all nine required M7 families: group, BBOX, display
  list, BSP, SWITCH, LOD, shadow, head, and gunfire/attachment. Traversal uses
  the typed view rather than a second raw-hash switch table.
- The source-model smoke now rejects unknown node families, asserts the M7
  family set, and runs strict/ASan/UBSan. Current counts and packet hashes stay
  unchanged; the four GETN title packets remain 138 nodes and 92 texture rows.
- Full command/material/texture consumption and dynamic skeletal lowering are
  intentionally deferred to M8–M10; dynamic sidecars remain explicit typed
  diagnostics rather than fallbacks.

# 2026-08-21 source/render gap audit refresh

- The stage source/render recommendation is now represented by the existing
  opt-in V7 gameplay-camera route, not a new fallback. NativeTitleOwner gates
  `GOLDENEYE_STAGE_GAMEPLAY_CAMERA_V7=1`; the product renderer requires the
  full-scene `0x38` guard and publishes only a scoped room/static-prop packet
  with `unsupportedMask=0x0`.
- Fresh strict/ASan/UBSan packet evidence is deterministic: Dam camera/packet
  `17166107536987602611`/`4344127377687538898`, Facility
  `9901855664259801205`/`2739797606600666455`, props `197/197` and `267/267`,
  and scene draws `1183`/`1444`; reference capture is `14` demos / `42`
  checkpoints. The production supplied-drawable harness remains an explicit
  Metal 4-device `SKIP`, so no Release pixel/gputrace claim is valid yet. The
  rebuilt signed Release executable hash is
  `c4f4f4b9e4f3772f7c47052e32559084e1e9fb0869b3c4f037844b0e4c1516a7`, with
  history/provenance passing under the external ROM boundary.

# 2026-08-21 M23 Cast source/production refresh

- Cast source contracts remain green on the full-weapons image-decoder root:
  five bodies pass texture alias and exact attachment-matrix lowering;
  chrfnp90 passes `64` commands, `7` setups, `10` vertex resources, and `7`
  draws; oliveguard/Natalya texture setup passes `505/56` and `626/46`
  command/setup counts; and the composer passes `30` identities, `22`
  animations, and `30` prepared model combinations. Attachment strict/ASan/
  UBSan and chrfnp90 strict/ASan/UBSan lanes pass.
- Correct Cast/RAMROM invocation is
  `bash scripts/test_cast_ramrom_scene_v6.sh build/native/boot-assets
  build/native/stage-assets-image-decoder-v6`; it passes `castIdentity=30`,
  `animations=22`, `demos=14`, `runs=28`, `manifest=14`, aggregate
  `6107930928028985404`, and retains `stageVisual=FAIL_CLOSED`.
- The strict Metal API/shader Cast reference repeat is at
  `build/native/cast-reference-capture-v6/20260822T013921Z/`, identity 1
  `boilerbond` only (not source-row-2 `spicebond`), with raw hashes
  `878411975a89eb4290a0313794927756b719651e71b5f0dca45e6b5e6d7ff713` and
  `ab49953288dd7eda553f47509e6146082d852fd71e0a27e690ab619f1202494a`.
- Signed AppKit production attempts `m23-current` and `m23-long` both retain
  `castSubmit=0`, `latestCrash=none`; the longer bounded run stopped at source
  tick `2964`, Gunbarrel screen `3`, subphase `3`. This is the current
  login-window/headless cadence blocker. No supplied-drawable Cast frame,
  inspected `.gputrace`, or physical presentation claim is valid until a
  visible active session reaches the guarded Cast submission.

# 2026-08-21 M24 native platform-service lifecycle continuation

- Added `GoldenEyeStageLifecycleV6` as a pointer-free, scheduler-independent
  metadata lifecycle over the corrected 21-resource stage catalog. It consumes
  the existing C 1172/rebase/resource-view contracts and exposes guarded
  `unloaded`, `loaded`, and `active` phases with deterministic handles, arena
  offsets, source/decoded byte totals, and state hashes. It never retains a
  payload pointer or byte buffer and does not create gameplay or Metal state.
- Strict/ASan/UBSan lifecycle smoke passes seven stages with decoded arena
  `2016864`, resource-view hash `15083698972971979799`, state hash
  `360802037447672111`; double-load, active-reset, and active-unload cases
  reject fail-closed. The corrected-root catalog/resource/background/setup/
  scene foundation checks remain green (`21` resources, `468` rooms,
  `2225` objects, `2230` pads, `612` portals).
- Broader M24 memory/DMA/file-index/streaming replacement and production
  lifecycle integration remain open; retain the C `STUB(M24)` diagnostic and
  do not promote this bounded lifecycle evidence to full stage execution.
- NativeTitleOwner now integrates the lifecycle during stage preparation:
  selected stages activate, replacement stages deactivate/unload the prior
  stage, and game reset releases the active lifecycle. Owner/runtime guards and
  SwiftPM build pass; broader streaming/DMA replacement remains deferred.

# 2026-08-21 M25 seven-stage loading continuation

- All seven stage families now consume the corrected image-decoder root and
  M24 lifecycle metadata in the bounded loading path. Scene/setup packets pass
  `468` rooms, `2225` objects, `2230` pads, `612` portals, and deterministic
  payload/packet hashes.
- Stage texture/material closure passes `436` textures, `248` TLUTs, `568`
  levels, and `3575` bindings with `gpuRepresentable=1` and zero
  unrepresentable mips. Static props are drawable in every stage (Dam
  `197/197`, Facility `267/267`, Runway `88/88`, Bunker I `123/123`, Silo
  `165/165`, Frigate `147/147`, Train `200/200`).
- The full-scene model composer intentionally retains `unsupportedMask=0x38`
  and zero drawable characters; gameplay/AI/effects/HUD/weapon/collision
  owners remain M26/M27 work. Do not promote identity-camera composition to a
  presentable gameplay frame.

# 2026-08-21 M26 gameplay-owner continuation

- All 14 source RAMROM routes pass strict/ASan/UBSan gameplay ownership:
  fixed-point player/camera bridge (`layout=176`, `direct=2`, `eventHash=1`),
  dynamic-scene matrix (`routes=14`, fixture-only=1), and orchestrator
  (`runs=28`, aggregate `3432588557158677409`, Dam movement, four dynamic
  doors, restore=1). `sourceReady=0` remains intentional.
- Guard/door pages pass `guards=623`, `doors=397`, `transformedDoors=152`,
  `poseRows=5104`, and `resolvedPortalRows=397` with portal hash
  `13325078266282593292`. Weapon/effect integration and non-model authority/
  visuals pass sanitizer lanes with explicit missing-category records.
- The bounded stage runtime passes strict/ASan/UBSan with `1578` demo-1 Dam
  samples and aggregate `4774828755625742329`, retaining
  `effects,ai,weapons,collision` diagnostics. Character/AI/effect/weapon/HUD
  promotion remains unsafe until authoritative snapshots and M27 rendering
  evidence exist.

# 2026-08-21 M27 scoped renderer refresh

- Fresh V7 packet strict/ASan/UBSan passes with Dam camera/packet
  `17166107536987602611`/`4344127377687538898` and Facility
  `9901855664259801205`/`2739797606600666455`; static props remain `197/197`
  and `267/267`, scoped mask `0x0`, retained full-scene mask `0x38`.
- The current 42-checkpoint reference, Release supplied-drawable gameplay,
  and all-seven environment Metal runs compile with API/shader validation but
  explicitly SKIP because no Metal 4 device is available. The environment
  harness now treats an all-unavailable run as SKIP (not PASS) and still fails
  partial/unexpected outcomes. Archived ignored captures remain separate from
  current production evidence.
- Do not clear unsupported character/AI/effects/HUD/weapon/collision bits or
  infer physical presentation from archived/offscreen output.

# 2026-08-21 M28 all-14 RAMROM playback refresh

- Strict and ASan/UBSan all-14 parser/playback validation passes `demos=14`,
  `runs=28`, `abort_restore=14`, `unique_stages=7`, parser/playback/checksum/
  RNG PASS, with gameplay/renderer `STUB(M26/M27)`. Swift owner-service
  aggregate is `6851901412168630050`; Dam demo 1 retains `454` packets,
  `1578` records, terminal tick `3156`, and the source recording/RNG hashes.
- Paired V5 playback/parser lanes pass strict/ASan/UBSan independently, and
  the all-14 run still prepares corrected seven-stage scene packets (`468`
  rooms, `2016864` payload bytes, hash `13284805027105908470`). Do not infer
  native gameplay or renderer acceptance from playback/checksum proof.

# 2026-08-21 M29 integrated Release refresh

- Rebuilt the source-faithful signed Release after the lifecycle and harness
  changes. Stage preparation is `resources=21`; executable SHA-256 is
  `85a7c8f86abbba1709e30f5cc4689bf6ce1a59a22c941657729b1c1e262cd916`.
  Release history/provenance and bundle guards pass with final packet hash
  `b9247beab28b0e101c471c1a94d0d4baebf8a3ea85e306981bef1365d3e485ad`.
- Short current post-display-observer 120/fixed-60 cadence records show logic
  `119.9975`/`119.9879` Hz and zero dropped ticks, but `5/6` callbacks, zero
  presented timestamps/FPS, and `pass=0` in the headless/login window. Physical
  presentation is still unproven.
- Current Metal 4 stage/reference/production attempts skip explicitly on this
  host, and Cast production remains before `castSubmit=1`. Keep archived
  captures and current skips separate; do not claim integrated visual or
  physical acceptance.

# 2026-08-21 M30 visual/window refresh

- Final signed Release after the display-observer change is
  `85a7c8f86abbba1709e30f5cc4689bf6ce1a59a22c941657729b1c1e262cd916`; ROM
  provenance and R0 pass.
- Title material/route, Gunbarrel strict/ASan/UBSan and transition projection,
  and Rareware LOD/FORCE_BLEND source lanes pass. Elevated GUI/input probes
  pass synthetic keyboard/focus transitions, but the headless session does not
  deliver physical focus notifications.
- Fresh Metal API/shader reference captures pass Nintendo, Rareware, and strict
  Cast identity 1; Cast remains `boilerbond` row 1, not `spicebond` row 2.
- Current Gunbarrel Metal temporal sweep passes modes `2...9` and timers
  through `400`, including timer 230 at `71` draws/`874` triangles.
- Physical focus/window migration, sustained presented FPS, live Cast
  supplied-drawable, and stage gameplay Metal evidence remain open.
- The post-observer wake/fullscreen attempt records `119.9897` Hz and 64
  callbacks with displays awake, but `frontmost=loginwindow`, zero presented
  samples/FPS, 64 rejected samples, and `pass=0`; active Aqua remains required.
- `main.swift` now routes window screen/profile/backing-property and
  application screen-parameter notifications through a shared display refresh
  that updates drawable size, preferred frame rate, and evidence logging.
  Runtime/GUI probes pass; physical migration remains unexercised.

# 2026-08-21 V7 seven-stage packet expansion

- Expanded the V7 gameplay-camera packet and production-capture harness stage
  list to all seven source stages: `33,34,35,9,20,26,25`. Strict/ASan/UBSan
  packet validation passes with distinct packet/camera hashes and scoped
  `unsupportedMask=0` while retaining full-scene `0x38`.
- Fresh packet metrics are Dam `105/105` props and `363` draws, Facility
  `158/158` and `648`, Runway `43/43` and `203`, Bunker I `59/59` and
  `201`, Silo `54/54` and `279`, Frigate `78/78` and `654`, and Train
  `130/130` and `298`. The Dam dynamic-door mutation remains deterministic
  and changes both packet and composition hashes; unsupported-category guards
  stay fail-closed.
- The current Metal 4 supplied-drawable harness passes all seven stages with
  API/shader validation, nonblack readbacks, and distinct raw hashes. The
  inspected trace is `build/native/stage-gameplay-camera-production-capture-v7/
  gputrace/stage-all-seven.gputrace`; this is production-shaped harness
  evidence, not canonical Release-app cadence or N64 pixel parity.
- The refreshed compositor-independent environment Metal captures pass all
  seven stages with `nonBlack=1`/`textured=1`; source triangle/Metal draw pairs
  are `13982/2237`, `15481/2336`, `3298/868`, `5512/1411`, `28639/2575`,
  `18757/2537`, and `10415/2090`. Raw hashes are retained in
  `build/native/stage-environment-metal-reference-capture-v6/` and the
  validation log records API/shader validation PASS.
- Stage-order supplied-drawable raw hashes are
  `d92c8a7706140fefc115586e4a999cb2356ae9f6c184865ce3612584befbba14`,
  `ab86a02b3cfaaf37ea0f285393cc4df9d57b8967bc7b4e3aed6fba15dbf6e29`,
  `a4bc1b5d0524890de0f285393cc4df13e5ae653ec336358fe50ca9d6e2d60091`,
  `baa4ffc947f2858a771ae36dd1f40cdc7af299e34da5046df427f8e6eb902530`,
  `e119c695f260fa565d9be5d15a4f3ff6cbf22d71746f1b4f04ca33562d1750c6`,
  `7e0834597be1b6ab1b0c3a4f4b669d892d528c1d02bffe50e1e750c8d69f40ba`,
  and `9d741b2755b518f69bb86ebed7d8fd87a1f29d607344685e462166fabc7c6cb8`.
- `prepare_native_stage_setup_dependencies.py` now records source
  `model_scale_q16` from each checked-in prop/character model record. The
  placement lowerer reconstructs runtime ObjectRecord matrices from the
  source pad look/up/position basis and excludes collectable/ammo/monitor/
  autogun/vehicle categories from the static-prop allowlist instead of using
  zero or identity transforms.
- The canonical signed Release after this continuation is
  `build/native/boot-runtime/source-faithful/GoldenEyeHost.app`, executable
  SHA-256 `85a7c8f86abbba1709e30f5cc4689bf6ce1a59a22c941657729b1c1e262cd916`;
  history/provenance and R0 pass.
- Final Release cadence probe `m30-current-20260822-120` records
  `logicTickRateHz=120.00156`, `droppedTicks=0`, but five callbacks, zero
  presented timestamps/FPS, five rejected presented samples, and `pass=0`
  under `frontmost=loginwindow`. Retain the physical Aqua/session blocker.

# 2026-08-22 M24 decoded-payload ownership continuation

- Added `GoldenEyeStagePayloadStoreV6` over the corrected
  `stage-assets-image-decoder-v6` catalog. Explicit activation loads exactly
  the three decoded stage resources, rechecks size/SHA-256, permits bounded
  fixed-width reads only for the active stage, and fails closed on stale,
  oversized, out-of-range, replacement, active-unload, or reset transitions.
- `NativeTitleOwner` now owns the payload store alongside the pointer-free
  lifecycle, with the same stage replacement/reset ordering. This is payload
  ownership evidence only; it does not claim DMA scheduling, gameplay, or
  renderer/category closure.
- Strict/ASan/UBSan payload-store smoke passes all seven stages with first-stage
  aggregate `8556576272295209170` and all-stage aggregate
  `15436731694462652841`; debug `GoldenEyeHost` build and owner runtime guard
  pass after integration.
- The signed Release rebuild after this source change passes preparation,
  production build, codesign/bundle gates, R0, and elevated provenance; the
  current executable SHA-256 is
  `fdc0f66a371e076398010e130df25c743905c64cf2639ce973e863182d6a778e`.
- Current canonical Release reachability is still blocked before Cast/V7 by
  the paired Gunbarrel model-result timing boundary; keep the separate
  supplied-drawable seven-stage harness non-canonical.
- Fresh opt-in V7 cadence against this Release reproduces
  `authorityFailure=paired projection mismatch at tick 3072 field gunbarrelMode:
  native 5 original 6`, with logic `120.001486 Hz`, zero dropped ticks, five
  callbacks, and zero presented samples/FPS under `frontmost=loginwindow`.
- V7 owner visibility now uses the camera adapter's source current-room plus
  one-hop portal-neighbor seed. Source environment strict/ASan/UBSan remains
  green (`stages=7`, `environmentTriangles=96084`, `metalDraws=12679`); do not
  call this recursive portal/PVS parity.
- The V7 packet smoke now uses that same one-hop room set for all seven stages;
  strict/ASan/UBSan passes with updated packet hashes and no unsupported-mask
  change. The current production supplied-drawable harness records
  `SKIP (Metal 4 device unavailable)` after this contract change; the prior
  one-room supplied-drawable trace/raw captures are archived and non-current.
- Final rebuilt-Release opt-in cadence at
  `m24-visible-current-20260822` still reproduces the same paired Gunbarrel
  mismatch (`native 5`, `original 6`, tick `3072`) with logic `120.001829 Hz`,
  zero dropped ticks, five callbacks, and zero presented samples/FPS.

# Luna Max Delegation Protocol

- Use explicit `luna_worker` agents for delegated work; that role is pinned to Luna at maximum reasoning.
- Preparation agents are read-only and independently review source/ABI seams, milestone scope, Metal 4 contracts, and evidence boundaries.
- Execution agents start only after the user invokes `/porting-execute` and receive disjoint file ownership.
- Suggested ownership lanes: C ABI/fixture core, Swift AppKit host/input, Metal renderer, and test/evidence harnesses.
- The primary agent alone owns public ABI changes, Xcode integration, `.porting` artifacts, and final integration.
- Do not allow concurrent edits to the ABI header, renderer contract, or project file.
- Validation uses independent Luna max reviewers in a fresh validation session. Implementation agents do not self-certify acceptance.
- Every delegation states that other agents share the workspace, forbids unrelated cleanup/reverts/commits/pushes, and requires exact changed-file, command, artifact, assumption, and risk reporting.

# Evidence Boundaries

- Build/link proof is not runtime proof.
- Launch proof is not rendering proof.
- A clear frame is presentation proof only.
- One triangle proves only the declared fixture, normalization, and Metal path.
- Metal validation does not prove visual correctness.
- A port screenshot is not an N64 reference image.
- The verified ROM proves provenance, not game or renderer parity.
- GPU capture must be inspected and correlated with the intended packet/draw count.
- Texture decoder hashes, PNG diagnostics, and sampled Metal output do not establish N64 texture or pixel parity without emulator/reference artifacts.
- Bounded ASan, leaks, and HUD runs do not prove unexercised paths or indefinite stability.

## 2026-08-22 source authority and canonical V7 continuation

- Source blood timing is now stateful in the hosted original stub (frame 0 plus
  41 continuations), with paired/transition evidence through GoldenEye tick
  `3582`. Native Cast timer-181 transitions, signed `HEAD_FIXED=-1`/
  `HEAD_RANDOM=-97` sentinels, and the 32-slot wallet switch fixture keep the
  copied source path aligned without clearing unsupported masks.
- The source renderer latches the blood mailbox across native draw-only ticks,
  locks scene publication against the supplied-drawable callback, and lowers
  only the explicitly scoped `props` category. The 1,972,424-byte guard-owner
  state is heap-constructed; selected demo/stage gameplay is prewarmed before
  cadence and rebased at the Cast-end source anchor.
- The live owner now passes source-facing room IDs exactly once through the
  camera adapter and filters static props through the checked-in visible
  dependency manifest. RAMROM playback remains continuous across Cast/SWITCH
  frames; the return edge is injected only on an even source anchor.
- Final signed Release executable SHA-256:
  `289a98e3173fd3770ff081f3ef54d20310c63883a530ab2d7bcbc22bd5de6e0e`.
  Provenance, codesign, and R0 pass.
- Canonical evidence is archived at
  `build/native/boot-runtime/cadence/runs/m28-blood-reset-20260822-120/120/`:
  demo 4 / Facility (stage 34), native tick 4324, room 68, 158/158 props,
  42 dynamic doors, 1191 draws, camera packet hash
  `4171253561713628972`, composition hash `9008813320083006498`, scoped
  unsupported `0`, retained full-scene `0x38`; RAMROM reaches packet 559/559.
  The run has zero fatal debt and renderer failures but no presented timestamps
  or FPS under the current login-window session; the 120-second owner report
  retains `sourceAuthorityFailure=none` after packet return and the repeated
  Gunbarrel blood-state reset.

# 2026-08-22 M24 bounded file-index and transfer queue continuation

- Added `GoldenEyeStageFileIndexV6` over the corrected stage catalog. It
  preserves the source/decoded ranges, compression, asset handles, and
  source/decoded digests for all 21 rows as value-only metadata. The index
  hash is `12969746555383168713`; no ROM path, N64 pointer, or file descriptor
  is retained.
- Added `GoldenEyeStageTransferQueueV6` over the active decoded payload store.
  It provides bounded submit/complete requests, deterministic IDs and drain
  order, caller-owned byte copies, and fail-closed no-active, cross-stage,
  queue-full, invalid-range, replay, pending-replacement, and reset guards.
  This is a scheduler-independent transfer contract and must not be described
  as a ported N64 DMA scheduler.
- `bash scripts/test_stage_transfer_queue_v6.sh
  build/native/stage-assets-image-decoder-v6` passes strict/ASan/UBSan with
  `stages=7`, `entries=21`, three completed requests, and
  `transferHash=16820286361146389937`. Payload-store and lifecycle smokes also
  pass after the change.
- The debug `GoldenEyeHost` build, owner route guard, source boot-route smoke,
  and source-faithful Release preparation/build/signing/provenance/R0 gates
  pass. The current Release executable SHA-256 is
  `0738a1202ea27a5949fb7fe10e1889d5c7d27f53ed634d5594ab81f61d535f33`.
- This continuation leaves the C `STUB(M24)`, V7 opt-in, full-scene `0x38`,
  gameplay categories, and physical/Metal-4 gates unchanged. The fresh stage
  gameplay-camera production run is `SKIP (Metal 4 device unavailable)` and
  ignored old `gputrace/` artifacts are not current proof; presented cadence
  remains unavailable under `frontmost=loginwindow`.

# 2026-08-22 repeated Gunbarrel source-authority continuation

- The current long loop had a real repeated-entry mismatch at tick `14370`
  (`native 6`, `original 5`). Renderer-local blood state was stale because
  Cast/SWITCH frames bypass renderer submission; screen-entry inference from
  the renderer's last frame therefore missed the second Gunbarrel entry.
- Added `resetGunbarrelBloodStream()` to the source model lifecycle contract.
  `NativeTitleOwner` calls it on the authoritative copied transition into
  Gunbarrel, and the renderer clears only blood frame index, continuation
  count, and completion latch. Pairing, source C/original authority, and
  fail-closed masks remain intact.
- Focused paired authority (standard, Cast, full Cast) and Gunbarrel projection
  smokes pass. Fresh Release executable SHA-256 is
  `fcc912c92170f2943a8981d5e87e08460e0d38b0c31696b89e11d35b55d62279`;
  preparation, codesign, provenance, and R0 pass.
- Fresh 120-second Release route:
  `build/native/boot-runtime/cadence/runs/m28-repeat-reset-20260822-120/120/`.
  It records `sourceAuthorityFailure=none`, logic `119.9999 Hz`, zero dropped
  ticks, zero renderer failures, and Facility V7 supplied-drawable evidence
  (`158/158` props, `1191` draws, scoped `0`, full-scene `0x38`). At tick
  `14370`, mode 5/blood remains visible; mode 6 occurs later after the source
  continuation stream.
- Post-fix stage capture with API/shader validation remains
  `SKIP (Metal 4 device unavailable)`; physical presented FPS remains
  unavailable under `frontmost=loginwindow`.

# 2026-08-22 M27 source-anchor window continuation

- V7 now publishes a bounded source-anchor window (`4` frames by default,
  `120` native-tick spacing) with in-flight coalescing, failure reporting,
  append-only owner/renderer evidence, and reset-time queue drain. Adjacent
  anchor bursts correctly hit the owner debt guard and remain disallowed.
- Independent Release runs record identical ticks `4324,4444,4564,4684`,
  camera/packet/environment/composition hashes, `158/158` props, `42` dynamic
  doors, `1191` draws, scoped unsupported `0`, full-scene `0x38`, and no source
  authority/renderer/debt failure. Current Release SHA-256:
  `aadf9c2bfcda56eef17ee5efa34b70271c5f87d3cd325be5d15704f5b12bc681`.
- Physical presented cadence and Metal-4 supplied-drawable/gputrace evidence
  remain open; characters, AI, effects, HUD, weapons, and collision remain
  fail-closed.
- Windowed 120-second Release evidence at
  `build/native/boot-runtime/cadence/runs/m27-anchor-window-long-windowed-20260822-120/120/`
  repeats the four submissions with `sourceAuthorityFailure=none`, logic
  `120.0003 Hz`, zero dropped/fatal debt ticks, and zero renderer failures.
  `pass=0` is only the login-window/no-presented-FPS boundary.
- RAMROM authority/gameplay evidence is now append-only. The full run
  `build/native/boot-runtime/cadence/runs/m28-ramrom-append-long-20260822-120/120/`
  retains packet `0/559`, `558/559`, `559/559`, and the next-cycle `0/559`,
  alongside four V7 anchors. Current Release SHA-256:
  `ca09b6cb290ebb62f0874678a1dcabbf6278730beb62ec89e39d0c6f3de1af30`.
- Post-build Metal API/shader capture rerun at `2026-08-22 07:16:57` remains
  `SKIP (Metal 4 device unavailable)`; no stale trace is promoted.
- The latest capture diagnostic at `2026-08-22 07:33:00` reports
  `MTLDevice unavailable device=nil`, confirming this CLI session has no
  Metal device available to the standalone capture process.

# 2026-08-22 M26 character-owner audit

- Current character owner export strict/ASan/UBSan passes retain
  `missingFields=28`; all-14 character-scene strict/ASan/UBSan passes retain
  zero animation/attachments and explicit missing pose, attachment-switch,
  and ModelRenderData fields. Deterministic head selection remains green.
- No complete source ChrRecord/AI/effect page set exists for a truthful next
  character-render lane. Keep `sourceReady=0`, M26/M27 masks, and fail-closed
  diagnostics intact until those source pages are copied.

# 2026-08-22 M23 row-2 random-word contract continuation

- `goldeneye_cast_scene_composer_v6_smoke` now checks the source second random
  word explicitly for identity row 2: even `2` selects embedded `natalya`, odd
  `3` selects prepared `spicebond`, and both retain the embedded-head path.
- `bash scripts/test_cast_scene_composer_v6.sh
  build/native/cast-frontend-v6-image-decoder-v6-fullweapons` passes with
  `row2RandomBody=natalya/spicebond`. This is source-selection evidence only;
  it does not promote the skipped Metal reference or live Cast route.
- Fresh live row-2 probe
  `build/native/cast-production-route-v6/m23-spicebond-row2-current2/` used
  `GE_CAST_SOURCE_INDEX=2 GE_CAST_RANDOM_WORD=3` and records
  `castSubmit=0`, `latestCrash=none`; the current headless/login-window route
  stopped in Gunbarrel at tick `2952`. Keep the live Cast/Aqua/Metal-4 gate
  open and do not infer production evidence from the offscreen row-2 fixture.
- `test_cast_production_route_v6.sh` now forwards explicit fullscreen/stress
  policy. The fresh windowed/non-stress row-2 probe at
  `build/native/cast-production-route-v6/m23-spicebond-row2-windowed-20260822/`
  still records `castSubmit=0`, `latestCrash=none`, stopping at tick `2960`;
  the live blocker is not an implicit fullscreen/stress setting.

# 2026-08-22 M24 source-catalog parity continuation

- `GoldenEyeStageFileIndexV6` now performs a fail-closed parity check against
  all 21 C `ge_stage_v5_resource_packet` rows plus `ge_stage_v5_find_stage`
  stage identity before queue construction. Index rows retain C RAMROM order
  (`33,34,35,9,20,26,25`); a public value-catalog stage-label tamper is
  rejected as `sourceCatalogMismatch`.
- Fresh strict/ASan/UBSan transfer validation reports
  `fileIndexHash=14890358892990385005`, `transferHash=16820286361146389937`,
  and `sourceParity=1`. Resource-loader, payload-store, lifecycle, debug host,
  and engine-owner checks pass as well. This does not implement an N64 DMA
  scheduler or alter V7/full-scene mask policy.
- The rebuilt signed Release executable SHA-256 is
  `425ee3d6f88d86b3318a61fc80ef12175f3c9153621914fa34e99cdb6d95e635`;
  preparation, Release history/provenance, codesign, bundle guards, and R0
  pass. The current production capture remains
  `SKIP (MTLDevice unavailable device=nil)` at `2026-08-22 07:51:38`, and
  physical presented cadence remains unavailable under `frontmost=loginwindow`.

# 2026-08-22 M24 transfer-backed scene-owner continuation

- `GoldenEyeStageScenePacket.loadAll` now consumes all 21 prepared rows
  through the source-ordered transfer queue, parses copied bytes through the
  existing C background/setup validators, and releases each stage before the
  next. Direct/transfer equality remains `468` rooms, `2016864` payload bytes,
  packet hash `13284805027105908470`, with 21 requests and transfer hash
  `13486978902238770849`.
- `NativeTitleOwner` now owns the queue for stage preparation, replacement,
  activation, and reset. This remains synchronous/scheduler-independent and
  leaves C `STUB(M24)`, V7, and full-scene masks unchanged.
- Fresh Release owner evidence has four V7 anchors, Facility `158/158` props,
  `1191` draws, scoped `0`, full-scene `0x38`, zero authority/debt/renderer
  failures, and logic `120.0005896 Hz`. Release SHA-256 is
  `28a7aef35302c753aec800db6f1c61a7b3a2a5fea9dace950e95114edc226d61`;
  Metal capture remains `SKIP (MTLDevice unavailable device=nil)`.

# 2026-08-22 M24 chunked transfer and RZIP bridge continuation

- The owner queue now reassembles decoded resources through sequential 64 KiB
  requests. Direct/transfer scene equality remains `468` rooms,
  `2016864` bytes, packet hash `13284805027105908470`; strict/ASan/UBSan
  scene evidence reports `44` requests and transfer hash
  `10384286454254812603`.
- Compressed catalog rows now use the C `ge_stage_v5_decompress_1172`
  callback with a borrowed Apple Compression function; strict/ASan/UBSan
  catalog validation preserves catalog hash `16694764706485246250` and all
  stage hashes. This closes the RZIP bridge only, not the N64 scheduler.
- Current signed Release SHA-256 is
  `759a84bf47bfe37870942474b8ce01314d1f453e014f5fe61187fec02f14c869`;
  provenance, codesign, bundle, and R0 pass. Fresh owner logic is
  `120.0024038 Hz` with four V7 anchors and no authority/debt/renderer failure;
  Metal capture remains unavailable.

# 2026-08-22 M29/M30 GPU-capture boundary audit

- The signed Release is visible to `gpucapture` only as `non-debuggable`
  because its entitlements omit `get-task-allow`; no canonical Release trace
  can be captured without changing Release signing policy.
- A debuggable SwiftPM Debug owner capture was attempted without shader
  validation. The retained trace has zero command buffers/API calls/resources
  under the login-window session and is diagnostic-only; do not promote it as
  Release or physical evidence.

# 2026-08-22 Release-gate harness refresh

- The Release renderer-environment guard now directs Swift frontend parsing to
  a writable build module cache. Full Release-gate dry-run, fidelity-policy,
  shader/resource-policy, preserved-catalog, and forbidden-bundle checks pass.

# 2026-08-22 RZIP callback negative-path refresh

- C stage V5 strict/ASan/UBSan now covers malformed markers, undersized output,
  callback count mismatch, and callback failure around `ge_stage_v5_decompress_1172`.
  All remain fail-closed; no scheduler or renderer claim was added.

# 2026-08-22 M29 Aqua acceptance and trace continuation

- Fresh unlocked Aqua short cadence passes signed Release 120/60 at
  `120.000946` and `59.951023 FPS`, with zero dropped/rejected/render/focus/
  migration failures. The 120-second V7 route reaches Cast and stage handoff
  but sustains only `113.190118`/`57.633275 FPS`; no-V7 control reaches
  `112.338963 FPS` with a `3515 ms` stall and `fatalDebtTicks=241`.
- A capture-entitled Release-code trace is valid and statically inspected;
  canonical Release signing and long physical cadence remain separate gates.

# 2026-08-22 stage-prewarm Release rebuild and session boundary

- Source-faithful Release rebuilt with SHA-256
  `803dc0db99e4786b7eb03893191d1c24a3330fcb90cbf063f5e2be4457990dfa`;
  Release history/provenance, codesign, R0, renderer/fidelity policy, and
  bundle guards pass.
- Scene packet/transfer/catalog/V7 packet strict/ASan/UBSan pass. V7 Release
  logs record four scoped room/static-prop submissions at ticks
  `4324,4444,4564,4684`, props `158/158`, draws `1191`, scoped unsupported
  `0`, retained full-scene `0x38`.
- The long V7 run preflighted `frontmost=loginwindow`; do not cite it as
  physical cadence. No-V7 still stalls on uncached
  `GoldenEyeRamRomGameplayOrchestratorV6.fromEnvironment` at tick `4322`
  (about `3413 ms`, `fatalDebtTicks=241`). Keep V7 prewarm opt-in and masks
  fail-closed. Unlock the desktop again for the next active-session capture.

# 2026-08-22 V7 cache and publication-race refresh

- Renderer caches one consecutive immutable snapshot's prepared draws and
  batching plan by copied hash/native tick/topology/drawable dimensions; new
  anchors replace it while per-frame uniforms and source hashes remain live.
- Generation-token publication rejects stale asynchronous V7 completions;
  shutdown is synchronized and RAMROM return drains the V7 queue.
- Cache-enabled Release SHA-256 is
  `4354c852da73c6343566c2c0f891744bb32f1fd4c9211b9e21a3f0dfc5c28eb5`.
  Locked diagnostic shows `cacheHits=67` and renderer callback p95 `3.95 ms`;
  presented cadence remains unavailable until the desktop is unlocked.

# 2026-08-23 background-window behavior refresh

- `GOLDENEYE_NATIVE_BACKGROUND=1` keeps the GoldenEye owner/audio timeline
  alive without activating or keying the AppKit window; `run_native_boot.sh`
  and cadence measurement both default to background mode. Active-display
  cadence requires explicit `GOLDENEYE_NATIVE_BACKGROUND=0`.
- The actual `run_native_boot.sh` LaunchServices verification records `3,124`
  source ticks at `frontmost=loginwindow` in
  `build/native/boot-runtime/cadence/runs/m29-background-runner-20260823-locked/`.
  This is owner execution evidence only; presented FPS remains an active
  display contract.
- Current Release SHA-256 is
  `4fb60d7fa26ad9e4904ebf640caaf0342edb7a7fc4a313e933942cd210ab7e5a`.

# 2026-08-24 unlocked Metal 4 production and LaunchServices background mode

- The strict stage gameplay-camera production harness passes on the unlocked
  Metal 4 host with API/shader validation enabled for all seven source-order
  stages. Room/static-prop supplied-drawable output is present for every
  scoped placement; scene/Metal draws are `363,657,270,235,279,1144,298`,
  scoped unsupported is `0x0`, and retained full-scene unsupported is `0x38`.
- Trace
  `build/native/stage-gameplay-camera-production-capture-v7/gputrace-20240824-stage-v7.gputrace`
  and `gpudebug-stage-v7.log` are current inspected evidence: 8 command
  buffers/encoders and 3,246 source draws. The typed `0x0055_2d58` authored
  stage decal mapping is preserved; no masks were cleared. Packet strict,
  ASan, and UBSan remain passing.
- Rebuilt signed Release SHA-256 is
  `d6df59f20c118eda87ec1e27f3e65153bd95b5ae03319512a5106dc519f718e5`.
  `run_native_boot.sh` uses `open -g -n` in background mode so LaunchServices
  does not steal frontmost status. A live check kept Safari frontmost while
  GoldenEye remained alive; the locked `3,124`-tick proof remains owner
  execution only, not visible-presentation evidence.

# 2026-08-24 passive background window/fullscreen correction

- Background mode is now normal-level, not all-Spaces, click-through, mouse
  movement disabled, ordered behind the user window, and forcibly windowed.
  `run_native_boot.sh` overrides any fullscreen request to `0` for background
  mode; foreground/cadence fullscreen remains explicit.
- Rebuilt Release policy/Debug build gates pass. Runtime evidence reports the
  GoldenEye window `onscreen=0` with zero bounds; Stocks stays frontmost across
  a real click at the covered coordinate, so the click passes through.
- Current signed Release SHA-256 is
  `6962a842aa9ed3f32eaa25dc0c9ac8c3acd996740e1d5fe45a39ffd794ca9ba8`.
  Durable runtime evidence is
  `build/native/boot-runtime/cadence/runs/m30-background-clickthrough-20260824/window-policy.log`.

# 2026-08-24 display-specific cadence continuation

- `NSScreen.maximumFramesPerSecond` now drives the owner range at startup and
  display migration: built-in 120 Hz uses `60–120/120`; DELL fixed 60 Hz uses
  `60–60/60`. The cadence harness defaults fixed-60 runs to `60/60/60` so its
  override no longer masks the source display selection.
- Serialized rebuilt-Release windowed runs: DELL `3601` ticks / `1764`
  presented / `58.8823 FPS` / 16.65 ms median / zero render-debt-fatal-focus
  failures; built-in `3601` ticks / `119.9993 Hz` / `60–120/120` / `108.27`
  composited FPS. Fullscreen external migration remains open at `49.86 FPS`
  with marshaled callbacks.
- Current signed Release SHA-256 is
  `7c90733c61e5654647a066227d8fdfa3216deb6a67f4d15c9586139b5a71e56f`.

# 2026-08-24 direct-launch passive default

- Source Release launches are passive even when no environment is supplied:
  accessory activation policy, LaunchServices deactivation, behind-desktop
  ordering, click-through input, and fullscreen suppression. Explicit
  `GOLDENEYE_NATIVE_BACKGROUND=0` is the sole foreground opt-in; cadence and
  legacy probes remain passive without it.
- Direct no-env `open -n` with fullscreen requested stayed Safari-frontmost,
  exposed only zero-bounds `onscreen=0` GoldenEye windows, and passed a real
  click to Stocks. Current Release SHA-256:
  `6d4241043c40c9013abb4f7c86796bbb9ea117a9c08b2dd7c515e77b742acaab`.
  Durable evidence: `build/native/boot-runtime/cadence/runs/m30-direct-launch-passive-20260824/direct-no-env-policy.log`.

# 2026-08-24 migration acknowledgement and publication lock

- Unexpected-thread drawable callbacks use bounded acknowledgement (two
  display periods, max 50 ms), pending-range deadlines, timeout telemetry, and
  immediate queued-callback removal. Owner smoke covers completion, timeout,
  cancel, and idempotence.
- Renderer copies published state under the publication lock and performs
  Metal work under a separate render lock. External fullscreen DELL evidence:
  `120.0005 Hz`, `1754` presented, `58.5483 FPS`, zero unexpected/marshal/
  timeout/drop/stale/unhandled/render failures; strict 59 FPS remains open.
  Cast still stops pre-submit at Gunbarrel tick `2924`.
- Current Release SHA-256:
  `afd99228c5365467930dabe1fe912210b14666e8349a7af2953ee9db0b20b77c`.
  Current-hash passive evidence:
  `build/native/boot-runtime/cadence/runs/m30-direct-launch-passive-20260824-r2/direct-no-env-policy.log`.

# 2026-08-24 Cast harness isolation

- Repeated cadence AppKit keepalive activation was removed from production.
  Background Cast validation is owner authority/scene-composition evidence;
  visible Metal/shader/capture requires an explicit foreground lane.
- Isolated Cast still stops pre-submit around Gunbarrel tick `2924` with no
  crash/authority error. Current signed Release SHA-256:
  `20694ab3c22615a7ad7908960dd8c9dbe0e6e0c657edd8352ff44bad1d79c6ea`.

# 2026-08-24 fully passive AppKit runtime

- Remove, do not gate, any recurring AppKit activation/key-window keepalive.
  Exact `GOLDENEYE_NATIVE_BACKGROUND=0` is the sole interactive opt-in; unset,
  invalid, title, cadence, legacy, input, and stage probes remain passive.
- Passive host invariant: accessory policy before `app.run()`, alpha-zero
  normal window, `ignoresMouseEvents`, no background first responder, initial
  focus reset, fullscreen suppression, reopen suppression, and immediate
  deactivation/hiding after any real key/active notification.
- Serialize measurement/Cast GUI runtimes and clean up exact owned PIDs.
  Background Cast submission proves owner authority/composition only; visible
  Metal/shader/capture needs explicit foreground consent.
- Final signed Release SHA-256:
  `1a1831ba059a8831c43b04dd8379095400e7771c81d797a612e491285c18ae3d`.
  Final passive evidence is
  `build/native/boot-runtime/cadence/runs/m30-final-passive-background-20260824/120/`:
  ChatGPT remains frontmost; GoldenEye is inactive, non-key, windowed, alpha
  zero, and violation-free while `362` source frames run at `120.2059 Hz` with
  authority `none`, no owner/audio pause, and clean termination. Background
  callbacks/present rejection do not prove visible FPS or physical acceptance.

# 2026-08-24 current Release passive/Cast boundary

- Fresh signed Release hash:
  `75b030d6d8e11ee1de14bd6de34a834fb23c626fda12bc59dd94c27add9ca86e`.
- Current-hash passive direct-bundle evidence keeps NetSward frontmost while
  GoldenEye remains inactive/non-key, alpha-zero, normal-level/click-through,
  and the source owner reaches tick `4314`:
  `build/native/boot-runtime/cadence/runs/m30-release-passive-cast-20260824/`.
- Owner-side Cast composition reaches `castSubmit=1` at tick `4313` for source
  index 2 (49 draws, 2,100 vertices, 16 poses). This does not prove a visible
  Metal Cast frame, API/shader validation, or gputrace; the explicit foreground
  supplied-drawable gate remains open.
- Debug/API-validation Gunbarrel lowering is approximately 27 ms per even
  anchor and the owner fails closed at debt 241. Keep source masks/model-result
  guards intact; do not claim the pre-Cast negative harness as a source bug.
- Exact final-hash `open -g -n` with no background variable and fullscreen
  requested remained passive (NetSward frontmost, GoldenEye non-frontmost,
  fullscreen suppressed, owner tick 2960):
  `build/native/boot-runtime/cadence/runs/m30-direct-noenv-final-20260824/`.
- Fresh stage gameplay-camera production supplied-drawable validation passes
  for demo 0/stages `33,34,35,9,20,26,25`: non-identity cameras, all scoped
  room/static-prop draws, deterministic hashes, API/shader validation,
  `unsupportedMask=0`, and retained full-scene `0x38`.
