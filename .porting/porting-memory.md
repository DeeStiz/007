# GoldenEye Swift Porting Memory

## Active Goal

- Goal: `native-boot-menu-attract-120`
- Goal document: `.porting/goal-native-boot-menu-attract-120.md`
- Current handoff: `.porting/porting-handoff-native-boot-menu-attract-120-M29.md`
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
- Native audio currently renders all three boot music sequences and guarded ADPCM/raw16 waves deterministically. The owner now refills the lock-free 8,192-frame 22,050 Hz ring into an Objective-C `AVAudioSourceNode`; additive V6 fixed-point reverb/composite-SFX vectors and title SFX IDs 18/77/79/111/258 pass strict/ASan/UBSan/Release, while the product music/title path applies bounded reverb and schedules source SFX. Full source mix tuning and long-soak A/V evidence remain open.
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
| Full source display-list production | Partial | Additive GETN frontend node packets copy 138 group/BBOX/DL/BSP hierarchy nodes and 92 texture metadata rows, GETU copies 1,251 signed-UV/material corners, and the M27 stage packet copies bounded room/portal overlay data; runtime validates these value streams, while full display-list command/material traversal and stage production remain deferred. |
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
