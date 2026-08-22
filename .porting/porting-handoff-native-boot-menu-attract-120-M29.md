# Native Boot/Menu/Attract/120 Hz — Active Handoff (M29 refresh)

## State

`native-boot-menu-attract-120` remains active and incomplete. This is an
evidence handoff, not a completion claim. The worktree is intentionally dirty;
no commit, push, branch, reset, clean, or unrelated deletion was performed.

Signed Release app:

`/Users/derek/Developer/goldeneye-swift/build/native/boot-runtime/source-faithful/GoldenEyeHost.app`

External ROM boundary (preparation only):

`/Users/derek/Documents/GoldenEye 007 (USA).z64`

SHA-1: `abe01e4aeb033b6c0836819f549c791b26cfde83`

## Verified in this refresh

- Release preparation/build/signing passes. `codesign --verify --deep --strict`
  passes and the app bundle contains no `.z64`, `.n64`, `.bin`, or `.rz`
  private payload.
- A clean scratch-path Release compile also passes after the additive title
  raster layout guard was corrected to the actual `GETitleRasterResultV5`
  size of 928 bytes; the signed product remains at
  `build/native/boot-runtime/source-faithful/GoldenEyeHost.app`.
- Frozen V1/V2/V3/V4 replay and hash guard pass unchanged:
  `1522029846112142469`,
  `65363635960931316/905714786767796339/10439205544326414085`,
  `11580554792388204033/9845751795158270468/14168780479827987350`, and
  `6213740136672363482/5747731189711370311/16733630809188353388`.
- Title reference/route/layout/text/icon/geometry/SFX lanes pass. File Select
  now has the source-style two-stage erase confirmation with Cancel default;
  keyboard X is not a hidden B shortcut.
- Partial branded GETP rows remain loaded and hash-checked, but the product
  renderer now suppresses their unsupported-command geometry by default to
  avoid turning missing texture/state lowering into opaque white blocks.
  `GOLDENEYE_TITLE_PARTIAL_GEOMETRY=1` re-enables that diagnostic draw path;
  complete source material/display-list lowering remains an open milestone.
- Audio V5/V6 effects/engine/output, stage setup/scene/gameplay, all-14
  RAMROM, and owner-runtime tests pass. All-14 evidence is parser/playback/
  checksum/RNG/abort-restore plus bounded stage packet preparation; M26/M27
  gameplay and renderer remain explicit boundaries.
- Final Swift debug build and `git diff --check` pass.
- A bounded Release launch with Metal API/shader validation enabled reports no
  Metal fault, shader error, assertion, or render failure. Preserved M15
  `gpudebug` inspection covers the supplied-drawable title encoder, fullscreen
  pass, geometry draw, BGRA8 drawable, pipeline, and bindings.
- The bounded M9 raster lane is now additive: `scripts/test_classic_raster_v5.sh`
  passes strict and ASan/UBSan. The M12 runtime preserves V1–V4 hashes while
  binding a labeled resident `Depth32Float` attachment/depth state, explicit
  alpha compare/dither and source fog policy, alpha-to-coverage, and coverage
  diagnostics. M12 `gpudebug`, validation, shutdown, and leak evidence pass;
  generic RDP raster coverage remains open. The M9 aggregate hash is
  `2633078999532620274` with state hashes
  `7950540911125037649`/`11514046475163631228`.
- The additive M8 GETT lane now passes `scripts/test_native_title_textures.sh`
  with 92 records (Legal 5, Nintendo 1, GoldenEye 2, walletbond 84), public
  C layout plus strict/ASan/UBSan checks, Swift parser/tamper checks, and
  source/decoded hashes. The title renderer keeps four validated textures
  resident and samples the first level for branded screens. GoldenEye’s
  source mip span is preserved in provenance (`mip_tail_bytes=696`), while
  the current decoded upload is explicitly base-level-only.
  Current packet SHA-256 values are Legal
  `7ea86c4d8a5416452c4514662fd5afdd35765850945dabe878af33c2e12eb5b6`,
  Nintendo `65796d808cc742b285ea66d713449e6456cb2c493ee97018d68779b2fbd473d7`,
  GoldenEye `a51d02c9298d4de4a3986ef4add025dc4d899280a5ce58366b0e17232c9ae872`,
  and walletbond `3c118b40f29d7ee61553ae1d95035ff79cdad7f37b7c922741efe16191323e9a`.
- The title texture upload now follows the Metal 4 resource contract: GPU-
  private shader-readable textures, shared staging buffers, a one-time compute
  copy plus blit-to-fragment barrier, persistent residency, and staged buffers
  retained until GPU-drained shutdown. The runtime evidence records
  `titleTextureUploadPending=false` and `lastError=none` after the first title
  submission.
- The additive M9 title raster audit passes eight source tuples with aggregate
  hash `11519430422207814888`; the additive M10 Projection V10 lane passes
  strict and ASan vectors with packet hash `15192084148729639549` for source
  matrix quantization, six-plane clipping, culling, and rational 440x330/
  widescreen mapping. These are bounded contracts; full title material,
  lighting, mip/LOD, and draw-packet consumption remain open.
- `scripts/test_native_title_raster_catalog.sh` passes the C-to-Swift
  value-only catalog (`states=8`, aggregate `11519430422207814888`) and
  associates Legal/Nintendo/GoldenEye/Rareware/Wallet screen evidence with
  copied state hashes. It does not claim unsupported forced-blend/coverage
  equivalence or full Metal pipeline variants.
- `scripts/test_native_title_projection_evidence.sh` consumes all eight guarded
  GETP packets through Projection V10 and passes strict/ASan with aggregate
  evidence hash `17378376777734745904`; this validates the transform seam but
  does not claim full source lighting/look-at/texgen.
- `scripts/test_native_title_uv.sh` passes 1,251 additive GETU signed-UV/
  material corners (Legal 36, Nintendo 192, GoldenEye 1,023) with C/Swift
  envelope/hash and ASan/UBSan guards. The packets preserve source command and
  vertex hashes but are not yet consumed by the title draw encoder.
- The signed Release title runtime now has an explicit
  `GOLDENEYE_TITLE_GETU_DRAW=1` opt-in. Under Metal API/shader validation it
  records three resident GETU resources with draw indices `6/192/852`, skipped
  corners `30/0/171`, `titleUVDrawEnabled=1`, and no validation faults; the
  existing fullscreen/GETT path remains the default.
- `scripts/test_stage_background_draw_packet.sh build/native/stage-assets-image-decoder-v6`
  passes a bounded M27 diagnostic packet/shader foundation for all seven scenes
  (`rooms=468`, `portals=612`, `commands=1080`, `vertices=4032`, aggregate
  `4308406056569914737`). It emits room markers/portal edges only and records
  six unsupported-work diagnostics; it is not source stage geometry rendering.
- The signed Release `GOLDENEYE_M27_STAGE_OVERLAY=1` route also runs under
  Metal API/shader validation: stage 33 reports `rooms=137`, `portals=194`,
  `commands=331`, `vertices=1210`, `frames=3`, `draws=993`, private vertex
  upload complete, and `lastError=none`. This is a diagnostic overlay, not
  full room geometry/props/characters/effects rendering.
- `scripts/test_audio_long_soak_v5.sh` passes a 600-second-equivalent,
  72,000-native-tick deterministic source-clock/ring soak with 13,230,000
  frames, PCM hash `14458218251061804860`, and zero underruns/drops. Live
  AVAudio mix and A/V timing evidence remain open.
- The new additive M7 GETN lane passes `scripts/test_native_title_nodes.sh`:
  four frontend model packets, 138 nodes, 92 texture metadata rows, and
  deterministic packet hashes. The signed title runtime loads and records all
  four packets; full display-list/material traversal remains open.
- Nintendo title animation now consumes fixed-point source-shaped rotation,
  scale growth/clamp, and ambient-light projection on the paired 120 Hz path;
  texture/material/swoosh parity remains explicitly open.

## 2026-08-21 Autonomous Validation Refresh

- The guarded stage root is `build/native/stage-assets-image-decoder-v6`; the
  old `build/native/stage-assets` path is legacy preparation output and is not
  valid for the current scene catalog. The goal and continuation commands now
  use the corrected root.
- Rebuilt and re-signed the source-faithful Release product after the current
  owner/renderer/Cast changes. `codesign --verify --deep --strict` and the
  frozen Release history/provenance gate pass; the executable SHA-256 is
  `d74d1ee9bda3c1546b018deedff3d7ec18c8a208cf5213b37372985c575b3ce5`.
- Fresh strict/ASan/UBSan and source-fidelity lanes pass for V1–V4 replay,
  title reference/route/GETT/GETU/GETN/raster/projection, source scene and
  texture binding, title cache, stage setup/scene/background/gameplay,
  all-14 RAMROM, audio soak, Rareware, Gunbarrel, and File/Mode capture.
- The current M27 stage-background supplied-drawable run passes Metal API and
  shader validation and produces an inspected trace at
  `build/native/m27-stage-background/goldeneye-m27-stage-background.gputrace`.
  `gpudebug` confirms one compute encoder, one 331-draw render encoder, the
  960x540 BGRA8 drawable, and the labeled private vertex resource.
- The disjoint Gunbarrel GBI cache lowers measured model-build p95 from
  `31.592 ms` to `25.362 ms` while retaining C authority, pose/matrix lowering,
  and frozen result layouts. Dynamic pose work still prevents the 120 Hz gate.
- The V7 gameplay-camera packet adapter now passes strict, ASan, and UBSan for
  demo 0 on stages 33 and 34 and is integrated into the owner/product renderer
  behind `GOLDENEYE_STAGE_GAMEPLAY_CAMERA_V7=1`. It emits camera hashes
  `17166107536987602611`/`9901855664259801205`, `197/197` and `267/267`
  drawable static props, scoped mask `0x0`, and retains the full-scene `0x38`
  character/AI/effects mask with deterministic packet hashes and fail-closed
  unsupported-category tests.
- Fresh final headless cadence evidence remains non-acceptance: logic is
  `120.0023 Hz`, renderer callback p95 `0.75 ms`, but the login-window session
  produces `presentedTimeSamples=0`, target p95 `1008.35 ms`, and `pass=0`.
  Sustained 120/60 presented-fps and physical-display evidence still require an
  active visible WindowServer session.

## 2026-08-21 Cast/stage continuation evidence

- Cast source repair now resolves source-row/full-handle texture aliases,
  per-model source render modes, embedded-head attachments, and exact vertex
  provenance fail-closed. Strict/ASan/UBSan attachment and chrfnp90 builder
  lanes pass (`commands=64`, `setups=7`, `vertexResources=10`, `draws=7`,
  `unsupported=0`). The deterministic strict Cast reference capture with
  Metal API/shader validation passes twice with identical raw hashes:
  reference `15e657b9a47b3fca22cb03ad45127b329283623963edd03253aed4de38e0051f`
  and Faithful HD
  `cbeaee5f72a0589c3718d57505aade826574e5d12973704cf8eac19397b95b92`.
- `GoldenEyeSourceProductRendererV6.prewarmSourceTitleScenes()` now copies 76
  immutable Cast GESM/texture topologies before cadence (`6,603,487 us`) and
  runs a source-index-1 three-model first-route builder packet prewarm
  (`67,374 us`). Live C-authoritative pose, attachment, camera, and hash work
  remains per tick; `maxDebtTicks` was not changed and no fallback was added.
- V7 owner integration is explicit and fail-closed: opt-in owner snapshots are
  submitted through `GoldenEyeStageGameplayCameraFrameRendererV7`, while the
  default environment route remains unchanged. Strict/ASan/UBSan packet lanes
  pass for stages 33/34 (`197/197`, `267/267`, scoped `0x0`, full `0x38`).
- Fresh all-seven source-environment Metal captures pass API/shader validation
  with `nonBlack=1` and `textured=1`. Fresh all-14 gameplay-camera checkpoints
  pass (`42` records), the bounded gameplay runtime passes with explicit
  `effects,ai,weapons,collision` diagnostics, and the supplied-drawable stage
  probe passes with inspected trace
  `build/native/m27-stage-background/goldeneye-m27-stage-background.gputrace`.
- The headless AppKit Cast attempt is retained at
  `build/native/cast-production-route-v6/cast-topology-prewarm-20260821/`:
  `castTopologyPrewarm=1`, `castBuilderPacketPrewarm=1`,
  `blocker.txt: castSubmit=0`, `latestCrash=none`. The owner stopped advancing
  around source tick 2876 in the current login-window session before the Cast
  transition, so live supplied-drawable Cast acceptance remains open rather
  than being inferred from the offscreen capture.
- Final short Release cadence evidence is retained at
  `build/native/boot-runtime/cadence/runs/20260821-final-headless-v2/`. The
  120 case measured `logicTickRateHz=119.9995`, `droppedTicks=0`, callback p95
  `1.45 ms`; the fixed-60 case measured `logicTickRateHz=120.0041`,
  `droppedTicks=0`, callback p95 `1.75 ms`. Both cases had
  `presentedTimeSamples=0`, `presentedFPS=0`,
  `rejectedPresentedTimeSamples=60`/`46`, and the harness returned `pass=0`;
  active visible WindowServer presentation evidence is still required.

## 2026-08-21 dynamic/title/fog continuation

- Dynamic source-pose lowering now caches immutable texture-coordinate and
  correction-matrix work without changing C pose/matrix authority or scene/
  render hashes. Suitbond production-shaped timing improved from
  `29,281/29,719 us` p50/p95 to `11,437/11,509 us`; Release `-O` timing is
  `1,122/1,154 us`. GBI, Gunbarrel, and chrfnp90 strict/ASan/UBSan lanes pass.
- The exact GoldenEye two-cycle LOD tuple is now admitted only for
  `OtherMode.H=0x00112000`, `OtherMode.L=0x0C182048`, and source combiner
  `0x26A004/0x1F1093FF`; nearby tuples and one-level auxiliary textures with
  nonzero maxLOD fail closed. Pipeline corpus strict/ASan and two Metal
  API/shader-validated captures pass (`162` commands, `339` triangles,
  `7` mips, `2` materials, `unsupported=0`). Repeat raw hashes are
  `4eec74efa4d3fadbdb78ebdef982cc1cea5a13efec5eb1751512f046eb8c2a23`
  (320x240) and
  `f7ec1001fd8690fff46fe9e26ecb8e6f297ec568300dcda5fd69090afaef4cd3`
  (Faithful HD).
- Fog lowering now exposes the exact source `gSPFogPosition` fixed-point
  contract with strict/ASan/UBSan coverage (`stages=7`, `enabled=4`, aggregate
  `9870053433528827143`). The production shader consumes signed `fm/fo`, source
  fog color, and the preserved clip-Z/clip-W coordinate only for
  `G_FOG + G_RM_FOG_SHADE_A`; other fog modes remain fail-closed.
- Final signed Release after these changes is
  `build/native/boot-runtime/source-faithful/GoldenEyeHost.app`, executable
  SHA-256
  `e8c0636bf0d8e7daeea9593ed40ca9e2c690c0927d1503e789450a870d49797e`.
- Final short cadence evidence for this exact Release is retained at
  `build/native/boot-runtime/cadence/runs/20260821-final-lod-headless/`: 120
  logic `119.9913 Hz`, fixed-60 logic `120.0021 Hz`, zero dropped ticks and
  callback p95 `1.85`/`1.75 ms`; both cases had `presentedTimeSamples=0` and
  the harness returned `pass=0` because the active WindowServer session still
  does not provide presentation timestamps.
- The stage source packet now carries a parallel eye-space-Z array computed
  from `projection.modelView` before projection, preserved through clipping,
  and copied into the stage scene GPU-vertex view without changing the
  historical 32-byte vertex or frozen C ABI. The updated seven-stage source
  environment strict/ASan/UBSan gate passes with packet aggregate
  `10879306652781644554`; eye/fog sidecars use distinct hash domains and retain
  their parallel values through clipping.

## 2026-08-21 packet-coordinate Release verification

- A packet-coordinate-only Release rebuild produced the canonical signed
  executable SHA-256
  `e8c0636bf0d8e7daeea9593ed40ca9e2c690c0927d1503e789450a870d49797e`.
  Strict codesign verification and the frozen Release history/provenance gate
  pass with the external ROM SHA-1 unchanged.
- The updated debug build, Metal source-scene strict/ASan/Metal-4 lane, host
  ASan/UBSan bounded runtime, stage fog lowering, source-scene pipeline corpus,
  and V7 gameplay-camera packet strict/ASan/UBSan lanes pass. The V7 records
  remain `demo=0`, stages `33/34`, props `197/197` and `267/267`, scoped mask
  `0x0`, retained full-scene mask `0x38`, deterministic `1`, and fail-closed
  `1`.
- The current Release rebuild does not alter the presentation evidence: the
  retained headless cadence artifacts still contain zero presented timestamps,
  while the exact fragment fog factor/color binding is now covered by the
  source shader and focused Metal contract lanes.

## 2026-08-21 exact-fog and fresh-capture continuation

- Per-stage source clip ranges now derive from the copied visibility/fog rows;
  clipping recomputes `clipZ/clipW` after interpolation, and the V7 scoped
  composition preserves the sidecars without clearing the full-scene `0x38`
  mask. Environment-only capture retains room/background bits when unknown
  visible opcodes remain.
- Fresh strict/ASan/UBSan stage environment and V7 packet lanes pass. V7
  packet hashes are `11113608939106626920` (stage 33) and
  `15466404641097031372` (stage 34), with `197/197` and `267/267` props,
  scoped mask `0x0`, full-scene mask `0x38`, deterministic `1`, fail-closed
  `1`.
- Fresh all-14 gameplay-camera Metal API/shader-validated capture passes all
  `42` checkpoints at
  `build/native/stage-gameplay-camera-reference-capture-v6/` (`black_without_fade=4`).
  The exact Cast reference was repeated byte-identically with raw hashes
  `7edb15fd82da9181bf71c25686f6dd818feed24241a12373f6d357c4be95099d` and
  `765f3c385fd58e8bbcf42b3a8f658d5eeb21a67b10bb3bd24b835d039226fe2a`.
- Current canonical signed Release hash is
  `e8c0636bf0d8e7daeea9593ed40ca9e2c690c0927d1503e789450a870d49797e`;
  Release history/provenance and strict codesign pass. Physical presentation
  still requires an unlocked visible Aqua session.
- Fresh short cadence attempts on this exact Release are retained at
  `build/native/boot-runtime/cadence/runs/20260821-final-exact-fog-loginwindow/`
  and `...-60/`: 120 logic `119.9964 Hz` and fixed-60 logic `120.0033 Hz`,
  zero dropped ticks and zero renderer failures, but both have
  `presentedTimeSamples=0` because readiness timed out behind `loginwindow`.
- Follow-up dynamic-category audits found no safe source-complete guard,
  character, HUD, or effects implementation to promote next. Character
  routes still lack authoritative animation/head-RNG/SwitchNode attachment and
  render-context fields; HUD/effects records lack live weapon/inventory/state
  producers. Their unsupported diagnostics and the full-scene category mask
  remain unchanged.
- Fresh title texture/raster catalog lanes pass with `92` validated GETT
  records across four models and raster aggregate
  `11519430422207814888`. The packets preserve source mip-tail/TLUT evidence,
  but the legacy fullscreen title renderer still consumes only its bounded
  base-level material; full source mip/TLUT sampling remains open.

## 2026-08-21 dynamic door source-submission continuation

- The bounded door-only owner now allocates the fixed-width C state on the
  heap, filters invalid source door rows through the C validator, and copies
  door pages in the declared 32-item chunks. It publishes source record/object
  identity, model handle, portal number, lifecycle/open state, Q16.16 open
  position, all 16 transform words, source-anchor/interpolation flags, and the
  source hash. The full guard owner remains separate and `sourceReady=0`; no
  guard or character promotion was made.
- The environment orchestrator route publishes `dynamicDoors=4` for Dam in
  the current source packet. Odd native ticks use the C interpolation step and
  even ticks consume the validated source door rows. Frame hashes include all
  16 transform words and the dynamic source fields. Restore snapshots copy the
  heap owner bytes and replay the same dynamic door publication; the strict,
  ASan, and UBSan orchestrator gate reports
  `environmentDynamicDoors=4 dynamicRestore=1`.
- The V7 gameplay-camera adapter accepts dynamic transforms only for visible
  setup objects of source type `1`, requires sixteen finite Q16.16 words and a
  nonzero source hash, and applies the transform through the existing camera
  model-view. Stage 33 reports dynamic packet/composition hashes
  `3209083801982227650`/`9272436217739127194`; the fixture changes both while
  retaining scoped `unsupportedMask=0x0` and full-scene `0x38`; no unsupported
  category is cleared blindly.
- Fresh focused validation passes: V7 packet strict/ASan/UBSan, portal
  geometry strict/ASan/UBSan (`612` portals), guard/door page strict/ASan/UBSan
  (`397/397` portal rows, `67` unique IDs), and all-14 orchestrator
  strict/ASan/UBSan (`runs=28`). The supplied-drawable V7 production probe
  compiles with Metal API/shader validation but explicitly SKIPs because this
  host has no Metal 4 device; no physical pixel or gameplay gputrace is claimed.
- A fresh signed source-faithful Release was rebuilt from the external ROM;
  stage preparation reports `resources=21`, boot release verification and
  frozen V1-V5 history/provenance pass, and the executable SHA-256 is
  `6e81f6faaf9cda114e014cfc970a3c7422afb615618822efd3abace28490dde4`.
  The external ROM remains `/Users/derek/Documents/GoldenEye 007 (USA).z64`
  with SHA-1 `abe01e4aeb033b6c0836819f549c791b26cfde83`; it is not copied into
  the checkout or bundle.

## 2026-08-21 scoped gameplay-camera production submission

- Added scripts/test_stage_gameplay_camera_production_capture_v7.sh and
  goldeneye_stage_gameplay_camera_production_capture_v7_smoke.swift. The seam
  consumes the V7 demo-scoped packet through the production
  GoldenEyeSourceSceneRendererV6.render(snapshot:suppliedDrawable:) path,
  rather than the compositor-independent environment-only capture.
- The strict value contract remains fresh for demo 0/stages 33 and 34:
  non-identity camera/projection, room commands, static props 197/197 and
  267/267, scoped unsupportedMask=0x0, retained full-scene 0x38,
  deterministic packet/composition hashes, and scene draws greater than
  room-only draws. The new capture smoke also records supplied-drawable pixel,
  source-manifest, and batch-manifest hashes plus raw/PNG/JSON outputs.
- The new production capture compiled cleanly and reached its Metal validation
  launch, but this host reported no Metal 4 device, so the supplied-drawable
  pixel/gputrace portion is an explicit SKIP, not a pass. Re-run the script on
  a Metal 4 host; do not promote the prior environment-only trace to
  room-plus-props presentation evidence.

## 2026-08-21 source head-selection continuation

- Added the value-only source head authority in
  native/host/goldeneye_ramrom_character_head_selection_v6.swift. It mirrors
  src/game/initguards.c bodiesReset and src/game/chraction.c bodyChooseHead:
  three seed transitions at the level boundary, male offset random consumption,
  female current-index reuse, and explicit-head no-consumption behavior.
- The character scene accepts an optional head-selection record and resolves
  the source head without clearing animation, render-context, or SwitchNode
  diagnostics. The selected-head fixture is sourceSelected but remains
  non-presentable; the full 14-demo character scene still reports
  animation=0/attachments=0 and retains its unsupported mask.
- Strict/ASan/UBSan head-selection and character-scene gates pass. The
  canonical Release was rebuilt and signed; executable SHA-256 is
  c93c0c0a297ad99e4ef43dbdae5cf8a2a83791b0e66fe76a8a10f124bf96398b.
  The Release history/provenance gate passes in the signing keychain context;
  the external ROM SHA-1 remains unchanged. The bounded host ASan/UBSan
  owner-loop run also passes at 60 ticks with no sanitizer diagnostics.

## 2026-08-21 projection/dependency/material continuation

- Corrected stage gameplay projection to the raw source viSetZRange ranges:
  Dam 5/15000, Facility 10/5000, Runway 10/15000, Train 10/1500. The
  Metal-depth matrix now maps source symmetric depth into [0,1], while the
  parallel fog sidecar retains source-symmetric 2*depth-1 coordinates.
  Strict/ASan/UBSan stage-environment and V7 gates pass. The new source
  environment aggregate is 2034083543171337301; V7 packet hashes are
  10787550995629497797 (stage 33) and 5096764590307538101 (stage 34).
- Corrected GuardRecord type-9 dependency extraction to use bodyAI at
  record offset +0x08 instead of chrnum. The guarded setup manifest is now
  references=1783, unique=141; Dam offset 23000 resolves bodyID 37 to
  greatguard2. Setup dependency, malformed-record, character, gameplay-page,
  owner-export, stage-composer, and all-14 RAMROM gates pass. Character rows
  now retain correct body sidecars/heads but remain non-presentable with
  animation, SwitchNode attachment, and render-context diagnostics.
- Added a source-title GESM material contract smoke covering 92 textures,
  199 mip payloads, both Wallet TLUT records, deterministic aggregate
  4247163796f6616e44965ad3ad846d5de46311005d75984f9a4a7be9c201d848, and
  fail-closed missing-palette evidence. GPU TLUT consumption remains
  explicitly unclaimed; GETT/GETU remain diagnostic-only.
- Rebuilt the signed Release after these changes. The executable SHA-256 is
  5cf6baf72fed8f6ba855d924f111e0dad418c2c7b105306364e644eebf4b9f4f;
  Release history/provenance passes with the external ROM boundary intact.

## Open acceptance gates

## Fresh scoped-lane validation — 2026-08-21

- Re-ran the strict/ASan/UBSan V7 gameplay-camera packet gate after the
  projection, fog, and corrected type-9 dependency changes. Demo 0 stages 33
  and 34 remain deterministic with packet hashes
  `10787550995629497797`/`5096764590307538101`, camera hashes
  `17166107536987602611`/`9901855664259801205`, static props `197/197` and
  `267/267`, scoped `unsupportedMask=0x0`, and retained full-scene
  `0x38`.
- Re-ran the source-title material contract: strict/ASan/UBSan pass with
  `textures=92`, `mips=199`, `tluts=2`, and aggregate
  `4247163796f6616e44965ad3ad846d5de46311005d75984f9a4a7be9c201d848`.
  GPU TLUT consumption remains explicitly unclaimed.
- Re-ran the corrected Dam GuardRecord dependency gate: strict/ASan/UBSan
  pass with `references=1783`, `unique=141`, and Dam offset `23000` resolving
  `bodyID=37`/`AIListID=1037` to `greatguard2`.
- Re-ran the all-14 gameplay orchestrator: strict/ASan/UBSan pass with
  aggregate `4035581654071229827`, Dam movement/restore pass, and the player
  camera publication kept separate from the incomplete character/AI/effects
  categories.
- Re-ran the character scene gate: strict/ASan/UBSan pass with all 14 rows
  retaining `animation=0`, `attachments=0`, and explicit unsupported fields;
  no character bit was cleared by this iteration.
- Re-ran the direct supplied-drawable production harness with Metal API and
  shader validation enabled. It compiled and reached the device check, then
  exited as `SKIP (Metal 4 device unavailable)`; no pixel hash, physical
  supplied-drawable frame, or new `.gputrace` is claimed on this host.
- Corrected the bounded C door-owner portal lifecycle: source-authoritative
  stepping now keeps a linked portal active from `doorStartOpen` through the
  closing terminal position, even when the current open fraction is still
  zero. The strict/ASan/UBSan guard-door owner gate and Swift adapter pass with
  `portalLifecycle=1`; this does not promote collision geometry or clear any
  stage render unsupported bit.
- Rebuilt the canonical signed source-faithful Release after the C change.
  Stage preparation (`resources=21`), native boot release verification,
  codesign, and Release history/provenance all pass. The current executable
  SHA-256 is `5cf6baf72fed8f6ba855d924f111e0dad418c2c7b105306364e644eebf4b9f4f`;
  the external ROM SHA-1 remains `abe01e4aeb033b6c0836819f549c791b26cfde83`.

## 2026-08-21 additive STAN topology continuation

- Added an additive `GEPlayerCameraStanLinkV7` sidecar without changing the
  frozen 176-byte `GEPlayerCameraStanTileV6` record. The Swift source STAN
  decoder now preserves every nonzero `StandTilePoint.link`, resolves targets
  using the exact `firstTile - 0x80 + (link << 3)` source rule, and rejects
  malformed targets before the owner receives them.
- The player-camera wrapper now uses the topology-aware C step for populated
  pages. A room transition is accepted only when the candidate is near a
  source-linked target tile; the legacy V6 API remains unchanged for callers
  without the sidecar. This is bounded linked-floor traversal evidence, not
  full portal polygon, level-scale, door-obstacle, or edge-slide parity.
- Fresh strict/ASan/UBSan player-camera and orchestrator lanes pass. All 14
  routes carry deterministic link counts/hashes: Dam `6750`, Facility `5748`,
  Runway `1210`, Bunker I `2760`, Silo `6050`, Frigate `4230`, Train `1488`.
  The all-14 orchestrator aggregate is `4410795521714608326`; Dam player and
  camera hashes are `13542178762661775407` and `6366479994531155444`.
- The topology-enabled all-14 player-camera smoke aggregate is
  `1689065738426998688`; source link hashes are deterministic across both
  strict runs.
- The focused C topology fixture proves both an authored cross-room link and a
  disconnected-room rejection. It reports `stanTopology=1` under the existing
  source player-camera strict/ASan/UBSan gate. Portal polygon assignment,
  source level-scale conversion, door collision, and full STAN edge sliding
  remain explicit next gates.

## 2026-08-21 source portal geometry continuation

- Added a value-only `GoldenEyeStagePortalGeometryCatalogV7` that parses the
  exact `bg_portal_entry` byte layout at each setup `geometryOffset`: bounded
  point counts, finite big-endian float32 coordinates converted to Q16.16,
  raw connected rooms, split control bytes, per-portal hashes, and a
  segment/polygon intersection helper. Malformed geometry fails closed.
- Strict/ASan/UBSan portal-geometry validation passes all seven stages and all
  `612` portals with deterministic aggregates. Per-stage aggregate hashes are
  `8029997828878432379`, `17331706062178012756`, `17140895277787453372`,
  `10299716895101914447`, `1107760455522435187`, `8568155555256919522`, and
  `17247629026481752267` in Dam/Facility/Runway/Bunker I/Silo/Frigate/Train
  order.
- The catalog by itself is preparatory evidence; door assignment requires the
  source STAN room sample (`sub_GAME_7F00324C`) and geometric
  `bgGetPortalBetweenRooms` contract. The page builder now applies that
  bounded value-only derivation, but dynamic door activation/rendering is
  still not promoted.
- The guard/door page builder now uses the catalog plus source STAN room
  samples at bound-pad center ±50 units to derive door portal IDs. Strict,
  ASan, and UBSan page validation resolves all `397/397` door rows with
  `67` unique portal IDs and portal hash `13325078266282593292`; the pages
  remain `sourceReady=0` because guard AI/pose/render producers are still
  incomplete. This is source door metadata evidence, not dynamic door
  renderer submission or collision acceptance.

- The owner scheduler is near 120 Hz and target intervals follow the named
  displays, but automated direct/WindowServer runs can throttle display-link
  callbacks and return zero nonzero `presentedTime` samples. Sustained 120/60
  presented-fps, CPU/GPU p95, and visual cadence evidence is not proven.
- Full source title material/lighting/mip/LOD/texgen/combiner parity and
  complete File/Mode pixel parity remain open.
- GETT texture upload is intentionally first-level-only for this handoff;
  complete source mip-chain/TMEM/TLUT/sampler lowering, Rareware source mip
  selection, and generic title display-list material traversal remain open.
- GETU signed-UV/material packets are bound only by the explicit
  `GOLDENEYE_TITLE_GETU_DRAW=1` opt-in and remain a homogeneous-triangle,
  first-material partial path; the default renderer still uses the bounded
  fullscreen/GETT route and partial GETP diagnostics.
- Full audio mix/reverb tuning and long-soak A/V evidence remain open.
- Native stage character/effect/AI/HUD categories, collision, weapons, full
  Metal gameplay submission, and RAMROM execution against those systems remain
  open; exact source fog is now bound for the admitted geometry mode. V7
  room/static-prop frames are scoped source-visible evidence, while the M27
  room/portal packet remains diagnostic overlay evidence only.
- The cadence-owner audit reproduced callbacks `3`, logic near `120 Hz`, zero
  render failures, and zero presented-time samples. `CGDisplayIsAsleep` reported
  `active=0 asleep=1 online=1`; bounded `caffeinate` raised callbacks to
  `13/17`, confirming compositor/display backpressure rather than an owner or
  drawable-order defect. Re-run on an active visible display (`active=1`,
  `asleep=0`) before treating the presentation gate as a product regression.
- The harness now has an explicit display-wake option and no-stress baseline.
  The latest awake run measured logic `119.9939 Hz` on Color LCD and
  `119.9873 Hz` on the named fixed-60 display with zero dropped ticks; the
  WindowServer still supplied only 25/19 callbacks and zero presented-time
  samples, so this is stronger scheduler evidence but not presented-fps proof.

## 2026-08-21 unified gameplay/traversal and active-display continuation

- Added a fixed-width `GERamRomGameplayPlayerCameraSnapshotV7` bridge and an
  additive C apply operation. Each gameplay frame now reconciles the copied
  player position/velocity/room/pad, weapon/action/animation/health, and camera
  vectors from the authoritative player/camera owner, then recomputes valid
  gameplay/render/audio/event hashes. Direct C layout/ASan/UBSan validation
  passes (`layout=176 direct=2 eventHash=1`); the all-14 orchestrator passes
  strict/ASan/UBSan with gameplay/player-camera equality assertions,
  `runs=28`, aggregate `3432588557158677409`, and
  `environmentDynamicDoors=4`.
- The player/camera owner now applies the source `levelscale` for all seven
  stages through STAN floor queries, pads, world bounds, and player snapshots,
  and adds bounded source-style STAN edge-slide projection while excluding
  authored link edges from obstacle selection. All 14 routes pass strict,
  ASan, and UBSan with deterministic aggregate `5860224076221260218` and
  `stanEdgeSlide=1` fixture evidence; frozen V6 records and the full-scene
  unsupported mask remain unchanged.
- Fresh V7 stage packet strict/ASan/UBSan passes after the scale/reconciliation
  changes. Stage 33/34 retain non-identity cameras, `197/197` and `267/267`
  props, scoped mask `0x0`, full-scene `0x38`; current packet hashes are
  `4344127377687538898` and `2739797606600666455`, with dynamic fixture hashes
  `2020772946810887752` and `17747242490227606699` for stage 33.
- An active Aqua/Metal 4 session produced real cadence evidence: fixed-60
  reached `59.951 FPS` with zero rejected samples; the short 120 run reached
  `118.653 FPS`, and the 6-second run reached `119.273 FPS` with readiness/
  rejection failures. The supplied-drawable stage attempt reached rendering
  but failed closed on missing decoded GBI lighting state `0xe2100001`; no
  pixel or gameplay gputrace is claimed. Current headless probes are again
  `frontmost=none`, `window_count=0`, so the active run cannot yet be repeated.
- Character/attachment and title-material audits remain fail-closed: no safe
  character promotion exists until exact pose/RNG/head, SwitchNode, secondary
  render-mode, fog, and held-weapon records are composed; the GoldenEye logo
  full-mip path is already safely lowered but default GETT/GETU promotion is
  not justified.
- The canonical signed Release was rebuilt after the combined changes. Stage
  preparation reports `resources=21`, debug build and frozen Release
  history/provenance pass, and the current executable SHA-256 is
  `97adbc3668b1b2fef768bfe32972fc0ff592abda0a782107d90e05c281be5e6f`.
- Follow-up scale-contract validation added an explicit serialized versus
  runtime-scaled camera domain. The player owner publishes runtime units;
  NativeTitleOwner marks that path `.runtimeScaled`, while structural V7
  fixtures remain `.serialized`. The adapter converts runtime coordinates back
  to serialized room space before the existing room-origin/visibility scale.
  Stage source-environment strict/ASan/UBSan passes with equivalent-domain
  camera matrices and the historical aggregate `2034083543171337301`.
- The display-link runtime now carries a monotonic pause generation through
  callback timing records, cancels marshaled callbacks on pause, rejects
  drawable callbacks crossing a pause/focus generation, and registers the
  presented handler before `present()`. Owner/runtime strict smoke and the
  headless 120-Hz soak pass (`ticks=241 rate=120.0 dropped=0 maxDebt=1`);
  physical focus migration and sustained 120-Hz acceptance remain open.

## 2026-08-21 source/render gap audit refresh

- The delegated source/render audit confirms that the recommended stage lane is
  already implemented as the opt-in V7 gameplay-camera route. NativeTitleOwner
  gates it behind `GOLDENEYE_STAGE_GAMEPLAY_CAMERA_V7=1`, publishes copied
  demo/stage/player-camera input, and the product renderer performs the strict
  full-scene `0x38` guard before publishing only the scoped room/static-prop
  composition. No stage-source files changed in this audit.
- Fresh packet validation passed strict/ASan/UBSan. Dam (stage 33) reports
  camera hash `17166107536987602611`, packet hash
  `4344127377687538898`, environment commands `28`, scene draws `1183`, and
  static props `197/197`. Facility (stage 34) reports camera hash
  `9901855664259801205`, packet hash `2739797606600666455`, environment
  commands `48`, scene draws `1444`, and static props `267/267`. Both retain
  scoped `unsupportedMask=0x0`, full-scene `0x38`, deterministic `1`, and
  fail-closed `1`. The all-demo reference lane passes `14` demos / `42`
  checkpoints.
- The production supplied-drawable harness was freshly rebuilt and run with
  Metal API and shader validation. It reached the device gate and recorded
  `SKIP (Metal 4 device unavailable)` in
  `build/native/stage-gameplay-camera-production-capture-v7/strict.log`.
  Therefore no Release room-plus-props pixel hash, supplied-drawable frame,
  inspected gameplay gputrace, or physical validation proof is claimed. The
  legacy environment/material artifacts remain valid source evidence but keep
  `unsupportedMask=60` for their broader props/characters/AI/effects packet;
  the composed full-scene model evidence narrows that retained gap to `0x38`
  after the static-prop slice is lowered.
- The next bounded gate is a Metal 4-capable host running the signed Release
  with the opt-in environment, then inspecting the supplied-drawable raw/PNG/
  JSON hashes and gputrace while retaining the explicit full-scene category
  boundary. Characters, effects, AI, HUD, weapons, and collision remain out
  of scope for this route.
- The canonical source-faithful Release was rebuilt after this audit. Stage
  preparation reports `resources=21`; the signed executable SHA-256 is
  `c4f4f4b9e4f3772f7c47052e32559084e1e9fb0869b3c4f037844b0e4c1516a7`, and
  the Release history/provenance gate passes with the external ROM boundary.

## Required continuation

```sh
cd /Users/derek/Developer/goldeneye-swift
scripts/build_native_boot.sh "/Users/derek/Documents/GoldenEye 007 (USA).z64"
scripts/measure_native_runtime.sh "/Users/derek/Documents/GoldenEye 007 (USA).z64"
scripts/test_classic_combiner_replay.sh
scripts/test_classic_raster_v5.sh
scripts/test_native_title_textures.sh
scripts/test_native_title_raster_catalog.sh
scripts/test_native_title_projection_evidence.sh
scripts/test_native_title_uv.sh
scripts/test_audio_long_soak_v5.sh
scripts/test_native_title_nodes.sh
scripts/test_title_reference_v5.sh
scripts/test_title_route_v5.sh
scripts/test_native_title_icons.sh
scripts/test_title_sfx.sh
scripts/test_stage_setup_packet.sh build/native/stage-assets-image-decoder-v6
scripts/test_stage_scene_packet.sh build/native/stage-assets-image-decoder-v6
scripts/test_stage_background_draw_packet.sh build/native/stage-assets-image-decoder-v6
scripts/test_stage_gameplay_runtime.sh build/native/stage-assets-image-decoder-v6 build/native/boot-assets
scripts/test_player_camera_owner_v6.sh
scripts/test_player_camera_owner_swift_v6.sh build/native/stage-assets-image-decoder-v6 build/native/boot-assets build/native/ramrom-visible-dependencies-v6
scripts/test_stage_portal_geometry_v7.sh build/native/stage-assets-image-decoder-v6
scripts/test_ramrom_all14.sh build/native/boot-assets/ramrom build/native/stage-assets-image-decoder-v6
bash scripts/test_cast_attachment_v6.sh
bash scripts/test_cast_chrfnp90_builder_v6.sh
bash scripts/test_stage_gameplay_camera_packet_v7.sh build/native/stage-assets-image-decoder-v6
bash scripts/test_stage_gameplay_camera_production_capture_v7.sh build/native/stage-assets-image-decoder-v6 build/native/ramrom-visible-dependencies-v6
bash scripts/test_source_title_material_contract_v6.sh build/native/source-frontend-v6
bash scripts/test_stage_setup_guard_dependency_v6.sh "/Users/derek/Documents/GoldenEye 007 (USA).z64" build/native/stage-assets-image-decoder-v6
bash scripts/test_ramrom_character_head_selection_v6.sh
bash scripts/test_ramrom_character_scene_v6.sh build/native/stage-assets-image-decoder-v6 build/native/ramrom-visible-dependencies-v6
bash scripts/test_stage_gameplay_camera_reference_capture_v6.sh build/native/stage-assets-image-decoder-v6 build/native/boot-assets build/native/ramrom-visible-dependencies-v6
bash scripts/test_cast_reference_capture_v6.sh build/native/cast-frontend-v6-image-decoder-v6-fullweapons build/native/gunbarrel-v6-prepared/gunbarrel.gbar build/native/boot-runtime/source-faithful/GoldenEyeSourceSceneV6.metallib
bash scripts/test_stage_fog_lowering_v6.sh
bash scripts/test_source_fog_binding_v6.sh
bash scripts/test_source_scene_pipeline_corpus_v6.sh
bash scripts/test_goldeneye_logo_reference_capture_v6.sh build/native/source-frontend-v6-image-decoder-v6
bash scripts/test_gunbarrel_dynamic_builder_v6.sh
```

Do not treat the build, launch, screenshot, or local GPU trace as N64 pixel or
performance parity. Runtime must continue to avoid opening the ROM; private
prepared assets remain beneath ignored `build/native/` directories.

## 2026-08-21 current integrated refresh

- Rebuilt the signed source-faithful Release after the M24 lifecycle and
  validation-harness changes. Stage preparation reports `resources=21`; the
  executable SHA-256 is
  `85a7c8f86abbba1709e30f5cc4689bf6ce1a59a22c941657729b1c1e262cd916`.
- `scripts/test_native_boot_release_history_v6.py` passes the external ROM
  SHA-1 boundary, frozen V1–V5 history, bundle guard, and
  `final_packet_sha256=b9247beab28b0e101c471c1a94d0d4baebf8a3ea85e306981bef1365d3e485ad`.
  Elevated `codesign --verify --deep --strict` reports the bundle valid on
  disk and satisfying its designated requirement.
- Short post-display-observer supplied-drawable cadence measurements are
  retained at `build/native/boot-runtime/cadence/runs/m30-current-short/`:
  logic rates are `119.9975` and `119.9879` Hz with zero dropped ticks, but
  only `5/6` callbacks, zero presented-time samples, zero presented FPS, and
  `pass=0`. These are headless/window evidence, not physical 120/60
  acceptance.
- Current M27 Metal reference/production runs all explicitly SKIP without a
  Metal 4 device; current Cast production remains `castSubmit=0` in the M23
  blockers. Keep those gates open and do not infer visual or physical
  acceptance from archived captures.
- A post-observer wake/fullscreen attempt at
  `build/native/boot-runtime/cadence/runs/m30-wake-attempt/120/report.txt`
  reached `119.9897` Hz with displays awake, but `frontmost=loginwindow`, zero
  presented samples/FPS, 64 rejected samples, and `pass=0`; an active Aqua
  session is still required.

## 2026-08-22 M24 transfer-contract Release refresh

- The source-faithful Release was rebuilt after the bounded M24 file-index and
  transfer-queue addition. Stage preparation reports `resources=21`; the
  current signed executable SHA-256 is
  `0738a1202ea27a5949fb7fe10e1889d5c7d27f53ed634d5594ab81f61d535f33`.
- Release history/provenance, codesign, bundle guards, R0, debug host build,
  owner route guard, source boot-route smoke, payload-store/lifecycle smokes,
  and strict/ASan/UBSan transfer-queue validation pass. This metadata/transfer
  lane does not change the physical cadence or Metal-4 acceptance gates.
- The post-Release stage gameplay-camera capture was rerun with API and shader
  validation enabled and remains `SKIP (Metal 4 device unavailable)`; stale
  ignored traces are not current evidence. Presented timestamps/FPS remain
  unavailable in the login-window session.

## 2026-08-22 repeated Gunbarrel Release refresh

- Source-owner reset at the authoritative Gunbarrel screen transition removes
  the stale second-cycle blood latch. Fresh 120-second Release evidence at
  `build/native/boot-runtime/cadence/runs/m28-repeat-reset-20260822-120/120/`
  records `sourceAuthorityFailure=none`, `119.9999 Hz`, zero dropped ticks,
  zero renderer failures, and the supplied-drawable Facility V7 frame.
- Current signed executable SHA-256 is
  `fcc912c92170f2943a8981d5e87e08460e0d38b0c31696b89e11d35b55d62279`;
  provenance, codesign, and R0 pass. Physical presentation remains open, and
  current Metal-4 capture remains an explicit device-unavailable SKIP.

## 2026-08-22 M27 anchor-window Release refresh

- The final signed Release now carries a coalesced, 120-native-tick-spaced
  four-anchor V7 window. Independent 30-second runs agree on ticks
  `4324,4444,4564,4684` and all camera/packet/environment/composition hashes;
  both retain `sourceAuthorityFailure=none`, zero dropped/fatal debt ticks,
  and zero renderer failures. Current SHA-256 is
  `aadf9c2bfcda56eef17ee5efa34b70271c5f87d3cd325be5d15704f5b12bc681`.
- The run still has zero presented timestamps/FPS under the login-window
  session; Metal-4 capture remains unavailable. No full-scene category bit was
  cleared.

## 2026-08-22 RAMROM evidence retention refresh

- RAMROM authority/gameplay logs are now append-only. The full Release run at
  `build/native/boot-runtime/cadence/runs/m28-ramrom-append-long-20260822-120/120/`
  retains packet `0/559`, `558/559`, `559/559`, and the next-cycle `0/559`,
  plus four V7 anchor submissions. It reports `sourceAuthorityFailure=none`,
  logic `119.9997 Hz`, zero dropped/fatal debt, and zero renderer failures.
- Current signed executable SHA-256 is
  `ca09b6cb290ebb62f0874678a1dcabbf6278730beb62ec89e39d0c6f3de1af30`;
  provenance, codesign, and R0 pass. Physical presented cadence remains open.

## 2026-08-22 stage-prewarm Release rebuild and session boundary

- The rebuilt source-faithful Release SHA-256 is
  `803dc0db99e4786b7eb03893191d1c24a3330fcb90cbf063f5e2be4457990dfa`;
  Release history/provenance, codesign, R0, renderer-environment, fidelity,
  prepared dry-run, shader/resource, preserved-catalog, and forbidden-bundle
  gates pass.
- Scene packet, transfer queue, asset catalog, and V7 gameplay-camera strict,
  ASan, and UBSan checks pass. The V7 Release route records four valid scoped
  submissions at `4324,4444,4564,4684` (`158/158` props, `1191` draws,
  scoped `0`, full-scene `0x38`), but its preflight was `frontmost=loginwindow`
  and therefore supplies no physical cadence proof.
- The no-V7 control still exposes the uncached gameplay-orchestrator begin at
  tick `4322` (`3413 ms` target stall, `fatalDebtTicks=241`). Keep the V7
  gameplay-camera route opt-in and do not broaden masks. Unlock the desktop
  again before the next short active-session cadence/capture attempt.
