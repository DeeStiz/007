# Native Boot/Menu/Attract/120 Hz — Visual and Window Regression Handoff (M30)

## State

The six regressions reported from the 2026-08-21 screenshots are implemented
in the native Swift/AppKit/Metal 4 path. This handoff records the bounded
source/Metal evidence; it does not claim N64 pixel parity, sustained physical
120/60 presentation, or completed gameplay-category rendering.

The external ROM remains preparation-only:

`/Users/derek/Documents/GoldenEye 007 (USA).z64`

SHA-1: `abe01e4aeb033b6c0836819f549c791b26cfde83`

## Six-fix resolution

1. Nintendo is not alpha-transparent in the source packets. The production
   Enhanced-HD lane now lifts the low I8 silver toe through RGB treatment while
   preserving the authored ambient fade and opaque draw contract. The 320x240
   reference lane remains source-faithful.

2. Rareware no longer pre-mixes adjacent mip levels. The combiner receives the
   distinct authored levels and performs the source LOD equation once. The
   canonical Rareware state is restored (`rawH=0x00192c00`, bilinear filter,
   six prepared mip levels); the source ambient/directional lighting split is
   preserved.

3. The mode-2 sight sweep submits separate leading and trailing source rings
   at `g_TitleX` and `titleTransitionX`. Each draw has its own immutable Metal
   uniform lane, and the shader uses analytic edge coverage with the source
   solid primitive color. Motion therefore produces the intended overlapping
   stretch instead of a sequence of popping dots.

4. Gunbarrel auxiliary draws no longer alias one constant record. Background,
   both sight rings, blood, red wash, black fade, and clear-black each use a
   completion-fenced uniform lane. The blood stream decodes to exactly 42
   frames/2,524 bytes; mode 5 transitions only after the final acknowledged
   frame, so Bond and the barrel remain present beneath the blood/fade modes.

5. Natalya uses the source Cast screen-7 lighting path and the ROM-authentic
   randomized `spicebond` body variant. The private Cast preparation root was
   regenerated with 80 verified sidecars and source-row-2 packet preparation
   resolves `spicebond` with no missing prepared model. A fresh source-row-2
   Metal capture was not obtained on this host.

6. AppKit focus loss resets held input but does not pause the source authority,
   owner scheduler, audio service, or renderer. The source input bridge keeps a
   neutral keyboard-backed controller connected so Legal/File/Mode/Cast/RAMROM
   clocks continue while unfocused. Window setup now uses a full-size content
   view, opaque black CAMetalLayer, backing-scale drawable sizing, fullscreen
   menu support, and a runtime activity assertion.

## Validation

Passed in the available code-side and archived validation lanes:

- Debug and Release `GoldenEyeHost` builds.
- `scripts/build_native_boot.sh` Release gate, codesign, bundle payload guard,
  and external-ROM provenance check.
- Strict source/API/shader contracts for the source scene, Nintendo, Rareware,
  Cast, source-2D, and Gunbarrel lanes; fresh title/Cast hardware captures
  require a Metal 4 device.
- Gunbarrel strict/ASan/UBSan smoke, 42-frame blood handshake, and Metal
  temporal sweep across modes 2...9.
- Archived Cast repeat/reference evidence remains available, but the current
  source-row-2 `spicebond` hardware capture is not claimed.
- Owner/input/focus suites, including zero scheduler/audio pause counters for
  the focus-independent owner/audio contract.
- Source pipeline corpus, title route, source-title material, and source-2D
  contract suites.

Representative artifacts are under ignored `build/native/`, including:

- `build/native/nintendo-reference-capture-v6/`
- `build/native/rareware-reference-capture-v6/`
- `build/native/gunbarrel-metal-reference-capture-v6/`
- `build/native/cast-reference-capture-v6/spicebond-strict-20260821/` (mislabeled
  identity `1`/`boilerbond` artifact; not source-row-2 `spicebond` proof)
- `build/native/boot-runtime/source-faithful/GoldenEyeHost.app`

## 2026-08-21 validation refresh

- Gunbarrel strict/ASan/UBSan and the expanded Metal temporal sweep pass. The
  sweep covers modes 2–9 plus timers 40, 50, 100, 136, 137, 152, 168, 169,
  212, 230, 348, and 400; mode 2 is `70` draws / `872` triangles, and mode 5
  plus timer 230 are `71` draws / `874` triangles with the blood/muzzle lanes.
  The 42-frame blood handshake and mode 5→6 transition remain source guarded.
- Owner/window validation passes: runtime smoke `ticks=5 pauses=1 resumes=1`,
  headless soak `ticks=242 rate=120.00000999834108 dropped=0 maxDebt=1`, M5
  clear `frames=60 lastSignal=60 completionSignaled=60 resourceAllocations=0`,
  title route strict/ASan/UBSan, input/controller, and GUI-event suites. This
  headless session still cannot prove physical focus notifications or visible
  desktop presentation.
- Rareware LOD, Cast composer/attachment/chrfnp90, Cast texture preparation,
  source-title material, source pipeline, title route/reference, and raster
  catalog suites pass. Fresh Nintendo, Rareware, Cast, and source-row-2 Metal
  capture attempts all record `SKIP (Metal 4 device unavailable)`; the
  mislabeled `spicebond-strict-20260821` directory must not be used as row-2
  proof.
- The canonical signed Release was rebuilt after this refresh. Stage
  preparation reports `resources=21`; executable SHA-256 is
  `c4f4f4b9e4f3772f7c47052e32559084e1e9fb0869b3c4f037844b0e4c1516a7`, and
  Release history/provenance passes under the external ROM boundary.

## Evidence boundary

The local WindowServer/login-window session did not establish an active,
visible cadence gate for the bounded 120/60 measurement, and a direct external
window switch did not emit a physical OS focus notification. The owner still
ran at approximately 120 Hz with `pauseCount=0`, `audioPauseCount=0`, and no
source-authority failure. Physical click-away behavior and sustained presented
FPS must be rechecked on an active visible desktop; the automated headless run
is not acceptance evidence for that claim.

## Reproduction commands

```sh
cd /Users/derek/Developer/goldeneye-swift
swift build --disable-sandbox --configuration release --product GoldenEyeHost
bash scripts/test_gunbarrel_v6.sh
GE_GUNBARREL_TEMPORAL_SWEEP=1 bash scripts/test_gunbarrel_metal_reference_capture_v6.sh
bash scripts/test_nintendo_reference_capture_v6.sh
bash scripts/test_rareware_lod_pipeline_v6.sh
bash scripts/test_rareware_reference_capture_v6.sh \
  build/native/source-frontend-v6-image-decoder-v6 \
  build/native/source-scene-renderer-v6/GoldenEyeSourceSceneV6.metallib
GE_CAST_STRICT_REGRESSION=1 bash scripts/test_cast_reference_capture_v6.sh \
  build/native/cast-frontend-v6-image-decoder-v6-fullweapons \
  build/native/gunbarrel-v6-prepared/gunbarrel.gbar \
  build/native/source-scene-renderer-v6/GoldenEyeSourceSceneV6.metallib
bash scripts/test_engine_owner_runtime.sh
bash scripts/test_m5_clear.sh
```

Do not bundle or commit the external ROM or ignored generated preparation
artifacts. The source-faithful Release app remains a local validation product,
not a store/release acceptance artifact.

## 2026-08-21 current M30 refresh

- The final source-faithful Release after the display-observer change is
  `85a7c8f86abbba1709e30f5cc4689bf6ce1a59a22c941657729b1c1e262cd916`; its
  external-ROM provenance and R0 gates pass.
- Source/CPU regression lanes pass again: title material strict/ASan/UBSan on
  the authoritative `build/native/source-frontend-v6` root (`92` textures,
  `199` mips, `2` TLUTs), title route (`cast=34`, `demos=14`), Gunbarrel
  strict/ASan/UBSan (`modes=2...9`, `42` blood frames), transition projection,
  and Rareware LOD/FORCE_BLEND guards.
- Elevated GUI/input probes pass keyboard/controller/owner routing and
  synthetic focus deactivation/activation. The headless session still does
  not deliver physical focus notifications; the harness records that as
  session-unavailable rather than claiming desktop focus proof.
- Fresh current Metal API/shader reference captures pass for Nintendo
  (`build/native/nintendo-reference-capture-v6/20260822T024348Z/`), Rareware
  (`build/native/rareware-reference-capture-v6/20260822T024429Z/`), and strict
  Cast identity 1 (`build/native/cast-reference-capture-v6/20260822T024522Z/`).
  Cast remains explicitly source-row-1 `boilerbond`, not `spicebond` row 2.
- The current Gunbarrel Metal API/shader temporal sweep passes modes `2...9`
  and timers `40,50,100,136,137,152,168,169,212,230,348,400`; mode 2 is
  `70` draws/`872` triangles and timer 230 is `71`/`874`.
- Current M30 gaps are active-display presented-FPS/migration, physical focus
  notifications, live Cast supplied-drawable output, and canonical Release-app
  stage gameplay submission. The separate all-seven production-shaped stage
  harness now has current supplied-drawable/gputrace evidence; do not promote
  that harness to the canonical Release-app or physical cadence gates.
- A corrected source-row-2 `spicebond` Cast reference was captured offscreen
  with Metal API/shader validation using explicit source second random word
  `GE_CAST_RANDOM_WORD=3`:
  `build/native/cast-reference-capture-v6/20260822T-cast-spicebond-row2-randomword3/`.
  It passes `capturedIdentity=2`, `capturedBody=spicebond`,
  `randomWord=3`, `missingPrepared=0`, `unsupportedVisibleCount=0`,
  `drawCount=61`, `triangleCount=755`, and repeats byte-identically with raw
  hashes `64766bd2d6667ab0ec1d633922f8424addb6d56fd7e04bb2a17bf3e6c3a04663`
  (320x240) and `c5c38bce7123d960d89e6966284fb8ad5835a914d9200eaa162687d63f27b60c`
  (Faithful HD). The earlier `...row2-current` artifact resolves `natalya`
  with the default even random word and is not Spicebond evidence. This is
  source/API evidence only; it is not live Cast supplied-drawable or physical
  presentation acceptance.
- Added explicit AppKit routing for `NSWindow.didChangeScreenNotification`,
  `NSWindow.didChangeScreenProfileNotification`,
  `NSWindow.didChangeBackingPropertiesNotification`, and
  `NSApplication.didChangeScreenParametersNotification`. Each refreshes the
  drawable size and preferred frame-rate range and records a display-change
  event; the owner/runtime and GUI probes still pass after this change.
- The production Cast probe now forwards optional `GE_CAST_SOURCE_INDEX` and
  `GE_CAST_RANDOM_WORD` launch fixtures into the owner. This permits an active
  session to exercise row-2 `spicebond` with the copied second random word
  while leaving the normal source-ordered route unchanged.
- A fresh final-Release 120 Hz probe at
  `build/native/boot-runtime/cadence/runs/m30-current-20260822-120/120/`
  records `ticks=4442`, `logicTickRateHz=120.00156`, `droppedTicks=0`, and
  `rendererCallbackCount=5`, but `presentedTimeSamples=0`, `presentedFPS=0`,
  `rejectedPresentedTimeSamples=5`, and `pass=0` with `frontmost=loginwindow`.
  This confirms the remaining physical Aqua presentation blocker after the
  final Release rebuild; it does not indicate a source renderer failure.

## 2026-08-22 M24 continuation and Release refresh

- The corrected stage catalog now has an integrated
  `GoldenEyeStagePayloadStoreV6` owner. It activates one stage's three
  decoded resources, validates size/digest, serves bounded reads, and releases
  the payloads in the same order as the pointer-free lifecycle. Strict,
  ASan, UBSan, debug build, and owner route guards pass; this does not widen
  M27's visible categories or clear the retained full-scene mask.
- The signed Release was rebuilt after this source change. Preparation,
  production build, signing/bundle gates, R0, and elevated provenance pass;
  executable SHA-256 is
  `fdc0f66a371e076398010e130df25c743905c64cf2639ce973e863182d6a778e`.
- The canonical Release audit identifies a source-side reachability blocker
  before Cast/V7: the current paired owner can stop at the Gunbarrel
  model-result timing boundary (`native 5`, `original 6`, around tick 3072)
  before the Cast handoff. Do not bypass this authority or promote the
  offscreen seven-stage harness to canonical evidence.
- Fresh opt-in V7 cadence against the new Release at
  `build/native/boot-runtime/cadence/runs/m24-payload-current-20260822/120/`
  reproduces the same `authorityFailure` at tick 3072. It measures
  `logicTickRateHz=120.001486`, `droppedTicks=0`, five callbacks, and zero
  presented samples/FPS under the login-window session; the payload-store
  integration did not change the blocker.
- After the source-visible one-hop change and final Release rebuild, the
  diagnostic at
  `build/native/boot-runtime/cadence/runs/m24-visible-current-20260822/120/`
  still reports `authorityFailure=paired projection mismatch at tick 3072
  field gunbarrelMode: native 5 original 6`, `logicTickRateHz=120.001829`,
  zero dropped ticks, five callbacks, and zero presented samples/FPS.
- The V7 packet harness was then aligned to that one-hop room set and passes
  strict/ASan/UBSan with updated hashes. Its current Metal production run is
  `SKIP (Metal 4 device unavailable)`; the earlier one-room trace/raw/PNG
  captures remain archived but are not current evidence for the updated
  visibility contract.

## 2026-08-22 source authority and canonical V7 continuation

- Paired source authority now preserves the 42-frame blood route, Cast timer
  181 transitions, and signed head sentinels. Strict/ASan/UBSan source
  reference, standard paired authority, optional Cast paired authority, and
  Gunbarrel transition projection pass through GoldenEye tick 3582.
- Release runtime fixes include a blood mailbox latch, renderer publication
  lock, heap-backed 1,972,424-byte guard-owner state, selected-route gameplay
  prewarm/rebase, Cast/SWITCH playback continuity, even-anchor return input,
  source-room-ID visibility, visible-manifest prop filtering, and explicit
  scoped props-category lowering. No unsupported category bit is cleared by
  inference.
- Final Release executable SHA-256 is
  `289a98e3173fd3770ff081f3ef54d20310c63883a530ab2d7bcbc22bd5de6e0e`;
  codesign, Release provenance, and R0 pass.
- Canonical supplied-drawable evidence is archived under
  `build/native/boot-runtime/cadence/runs/m28-blood-reset-20260822-120/120/`.
  The owner/renderer logs record demo 4 Facility (stage 34), tick 4324, room
  68, dynamic doors 42, props 158/158, camera packet hash
  `4171253561713628972`, environment hash `16368508742986671446`, material
  hash `808239429714295832`, composition hash `9008813320083006498`, 1,191
  scene draws, scoped unsupported `0`, and retained full-scene `0x38`.
  RAMROM reaches packet 559/559 at tick 7678; cadence remains 119.9994 Hz
  with zero fatal debt and zero renderer failures.
- Physical presentation remains unproven: the headless/login-window run has
  zero presented timestamps/FPS, and current Metal-4 capture attempts remain
  explicit SKIPs. The bounded full loop now ends with paired authority clean
  after the repeated-Gunbarrel blood reset.

## 2026-08-22 M24 transfer-contract Release refresh

- The source-faithful Release was rebuilt after adding the deterministic stage
  file index and bounded decoded-payload transfer queue. The signed executable
  SHA-256 is
  `0738a1202ea27a5949fb7fe10e1889d5c7d27f53ed634d5594ab81f61d535f33`;
  preparation, provenance, codesign, bundle, and R0 gates pass.
- The post-Release stage gameplay-camera production harness ran with API and
  shader validation enabled and cleanly records `SKIP (Metal 4 device
  unavailable)`. No stale ignored GPU trace is promoted; physical presentation
  and the remaining unsupported gameplay categories stay open.

## 2026-08-22 repeated Gunbarrel Release refresh

- The source owner now resets the copied Gunbarrel blood stream on the
  authoritative screen transition, covering Cast/SWITCH frames that bypass
  renderer submission. The fresh 120-second Release route reaches the former
  tick-14370 boundary with `sourceAuthorityFailure=none`; mode 5 remains until
  the source continuation stream completes and mode 6 follows later.
- Current Release SHA-256 is
  `fcc912c92170f2943a8981d5e87e08460e0d38b0c31696b89e11d35b55d62279`;
  provenance, codesign, and R0 pass. The Metal-4 production capture remains
  `SKIP (Metal 4 device unavailable)`, and physical presentation/category
  closure remains open.

## 2026-08-22 M27 anchor-window Release refresh

- The opt-in V7 route now retains four authoritative source-anchor frames at
  120-native-tick spacing, with queue coalescing and reset fencing. Independent
  runs agree on ticks `4324,4444,4564,4684`, hashes, `158/158` props, and
  `1191` draws; logic remains near 120 Hz with zero fatal debt.
- Current Release SHA-256 is
  `aadf9c2bfcda56eef17ee5efa34b70271c5f87d3cd325be5d15704f5b12bc681`.
  Physical presentation and Metal-4/gputrace/category closure remain open.

## 2026-08-22 M24 source-catalog parity refresh

- The stage file index now validates all 21 Swift rows against the C packet
  stream and stage lookup, preserving RAMROM order (`33,34,35,9,20,26,25`)
  and failing closed on `sourceCatalogMismatch`. The transfer negative tamper
  case and strict/ASan/UBSan pass with
  `fileIndexHash=14890358892990385005`, `transferHash=16820286361146389937`,
  and `sourceParity=1`.
- Fresh signed Release SHA-256 is
  `425ee3d6f88d86b3318a61fc80ef12175f3c9153621914fa34e99cdb6d95e635`;
  preparation, history/provenance, codesign, bundle guards, and R0 pass.
  The post-build Metal API/shader capture at `2026-08-22 07:51:38` remains
  `SKIP (MTLDevice unavailable device=nil)`; physical presentation and
  full-scene category closure remain open.

## 2026-08-22 transfer-backed M24 owner refresh

- The stage scene loader now reads all 21 prepared rows through the validated
  transfer queue before parsing; `NativeTitleOwner` retains the queue across
  stage activation and logs `completedRequests=21` with transfer hash
  `13486978902238770849`. Direct/transfer packet equality remains
  `468` rooms, `2016864` payload bytes, hash `13284805027105908470`.
- Fresh signed Release cadence reaches four V7 Facility anchors with
  `158/158` props, `1191` draws, scoped `0`, retained full-scene `0x38`, and
  no authority/debt/renderer failures. Current Release SHA-256 is
  `28a7aef35302c753aec800db6f1c61a7b3a2a5fea9dace950e95114edc226d61`.
- The current Metal API/shader production harness at `2026-08-22 08:36:49`
  still reports `SKIP (MTLDevice unavailable device=nil)`; login-window
  presented cadence and remaining gameplay categories remain open.

## 2026-08-22 GPU-capture boundary audit

- `gpucapture list` sees the signed Release only as `non-debuggable`; its
  Release entitlements do not include `get-task-allow`, so a canonical Release
  `.gputrace` cannot be captured without changing signing policy.
- A separate Debug owner was launched with `MTL_CAPTURE_ENABLED=1` and shader
  validation disabled as required by gpucapture. The Layer trace
  `build/native/m29-debug-owner-capture-20260822/debug-owner-layer.gputrace`
  contains zero command buffers/API calls/resources under the login-window
  session and remains diagnostic-only.

## 2026-08-22 Release-gate harness refresh

- The renderer-environment guard's Swift frontend parse now uses a writable
  build module cache. `test_native_boot_release_gate.sh` passes its complete
  renderer/fidelity/dry-run/shader-policy/preserved-catalog/forbidden-bundle
  suite; this fixes validation infrastructure only and does not alter the
  signed Release entitlements or capture boundary.

## 2026-08-22 chunked/RZIP Release refresh

- The integrated owner now transfers scene resources in bounded 64 KiB chunks;
  the scene smoke remains byte-identical to direct loading with `44` requests,
  transfer hash `10384286454254812603`, and packet hash
  `13284805027105908470`. Compressed 1172 catalog rows now pass through the C
  decompressor callback contract with no stored pointer/context.
- Current signed Release SHA-256 is
  `759a84bf47bfe37870942474b8ce01314d1f453e014f5fe61187fec02f14c869`;
  Release gates pass. The fresh owner run reaches four V7 anchors with logic
  `120.0024038 Hz`, zero dropped/fatal/renderer failures, and no authority
  failure. Metal capture remains `MTLDevice unavailable device=nil` and
  presented cadence remains unavailable in the login-window session.

## 2026-08-22 unlocked Aqua cadence and trace refresh

- Fresh short signed Release cadence passes both displays:
  `120.000946 FPS` at 120 and `59.951023 FPS` at fixed-60, with zero dropped
  ticks, rejected samples, render failures, focus pauses, and migration errors.
- The 120-second route reaches Cast/V7 but fails sustained presentation
  (`113.190118`/`57.633275 FPS`); no-V7 control also reaches only
  `112.338963 FPS` and records a `3515 ms` target stall/`fatalDebtTicks=241`.
  Retain this as a pacing regression, not a source category failure.
- A capture-entitled copy of the Release code produced
  `build/native/m29-release-capture-entitled-20260822/release-code-layer.gputrace`.
  Static inspection confirms one command buffer, labeled MTL4 source render
  encoder, six draws, 960x540 BGRA8 + Depth32Float, and a 54-index draw; it is
  not canonical Release entitlement or physical-presentation proof.

## 2026-08-22 current Release and physical-session follow-up

- Rebuilt Release executable SHA-256:
  `803dc0db99e4786b7eb03893191d1c24a3330fcb90cbf063f5e2be4457990dfa`.
  All Release provenance/signature/fidelity/renderer-policy bundle gates pass;
  stage packet, transfer, catalog, and V7 packet strict/ASan/UBSan gates pass.
- V7 owner/renderer logs retain four valid room/static-prop frames with
  `unsupportedMask=0`, full-scene `0x38`, `158/158` props, and `1191` draws.
  The run is not physical acceptance because the foreground probe saw
  `loginwindow` and the cadence gate had zero presented timestamps.
- The legacy no-V7 path still incurs the explicit source gameplay-orchestrator
  begin stall at tick `4322`; no V7 owner reuse or category-mask bypass was
  introduced. The next M30 gate is active-session supplied-drawable timing plus
  Metal-4 API/shader/gputrace inspection after unlock.

## 2026-08-22 cache-enabled Release timing refresh

- Prepared stage draws/batching are cached only for identical immutable
  snapshots; generation fencing preserves fail-closed route ownership.
- Cache-enabled Release hash is
  `4354c852da73c6343566c2c0f891744bb32f1fd4c9211b9e21a3f0dfc5c28eb5`.
  Locked diagnostics show 67 stage cache hits and renderer callback p95
  `3.95 ms`; physical cadence/capture is not claimed under `loginwindow`.

## 2026-08-23 background-window behavior refresh

- Background mode (`GOLDENEYE_NATIVE_BACKGROUND=1`) keeps the source owner
  alive without foreground activation; both the scripted source launch and
  cadence measurement default to it. Active-display cadence requires explicit
  `GOLDENEYE_NATIVE_BACKGROUND=0`.
- The actual `run_native_boot.sh` LaunchServices verification records `3,124`
  source ticks under `frontmost=loginwindow`; presentation remains correctly unclaimed until an
  active display is available. Release SHA-256:
  `4fb60d7fa26ad9e4904ebf640caaf0342edb7a7fc4a313e933942cd210ab7e5a`.

## 2026-08-24 M30 unlocked production render and launch policy

- Metal 4 supplied-drawable production capture passes with API/shader
  validation for all seven source-order stages. It draws all scoped room and
  static-prop geometry (`3,246` total draws across the seven frame captures),
  reports scoped `unsupportedMask=0`, and retains full-scene `0x38`.
- `gpudebug` inspection of
  `build/native/stage-gameplay-camera-production-capture-v7/gputrace-20240824-stage-v7.gputrace`
  confirms eight command buffers and eight encoders (seven source-scene render
  encoders plus one texture-upload encoder), BGRA8/depth attachments, and
  indexed source draws; the full log is retained beside the trace. Strict/
  ASan/UBSan packet validation and the clean production harness
  pass. The typed `0x0055_2d58` decal tuple is the only new raster admission.
- The signed Release was rebuilt and gated with SHA-256
  `d6df59f20c118eda87ec1e27f3e65153bd95b5ae03319512a5106dc519f718e5`.
  `run_native_boot.sh` now launches background mode with `open -g -n`; a live
  check preserved Safari as frontmost while GoldenEye stayed alive. This
  addresses owner/frontmost coupling while preserving the rule that visible
  presentation and FPS require an active display.

## 2026-08-24 passive background window/fullscreen correction

- Background mode is now a passive owner surface: normal level, no all-Spaces
  promotion, `ignoresMouseEvents`, no mouse-movement acceptance, `orderBack`,
  and no fullscreen. The runner forcibly overrides fullscreen to `0` for this
  mode; fullscreen is permitted only with exact interactive background `0`.
- Release policy and Debug compilation pass. A rebuilt Release runtime check
  passed `GOLDENEYE_NATIVE_FULLSCREEN=1` to background mode and still found
  GoldenEye `onscreen=0`, zero bounds, and non-frontmost. A real click activated
  Stocks rather than GoldenEye, proving click-through; the owner then stopped
  cleanly. Current Release SHA-256:
  `6962a842aa9ed3f32eaa25dc0c9ac8c3acd996740e1d5fe45a39ffd794ca9ba8`.
  Evidence: `build/native/boot-runtime/cadence/runs/m30-background-clickthrough-20260824/window-policy.log`.

## 2026-08-24 display-specific cadence continuation

- Startup and display-change requests now derive the preferred range from the
  screen's `maximumFramesPerSecond`: built-in 120 Hz is `60–120/120`, fixed
  DELL 60 Hz is `60–60/60`. The cadence harness defaults its fixed-60 case to
  the same explicit override.
- Serialized Release evidence: windowed DELL 60 Hz reports `3601` ticks,
  `1764` presented samples, `58.8823 FPS`, 16.65 ms median, zero render/debt/
  fatal/focus failures, and `preferredFrameRateRange=60.0-60.0/60.0`.
  Built-in 120 Hz reports `3601` ticks, `119.9993 Hz`, and
  `preferredFrameRateRange=60.0-120.0/120.0`; composited presentation is
  `108.27 FPS`. Fullscreen external migration remains separately open at
  about `49.86 FPS` with marshaled callbacks.
- Current rebuilt signed Release SHA-256:
  `7c90733c61e5654647a066227d8fdfa3216deb6a67f4d15c9586139b5a71e56f`.

## 2026-08-24 direct-launch passive default

- The source Release now treats omitted background configuration as passive;
  `GOLDENEYE_NATIVE_BACKGROUND=0` is the sole interactive opt-out.
  Unset, malformed, cadence, legacy, title, input, and stage probe environments
  remain passive.
- Direct `open -n` with no background variable and fullscreen requested stayed
  Safari-frontmost, had GoldenEye `onscreen=0` zero-bounds windows, and passed
  a real click through to Stocks. Current Release SHA-256:
  `6d4241043c40c9013abb4f7c86796bbb9ea117a9c08b2dd7c515e77b742acaab`.
  Evidence: `build/native/boot-runtime/cadence/runs/m30-direct-launch-passive-20260824/direct-no-env-policy.log`.

## 2026-08-24 migration acknowledgement and publication-lock continuation

- Unexpected-thread drawable callbacks now use bounded synchronous
  acknowledgement (two display periods, capped at 50 ms), pending-range
  deadlines, timeout telemetry, and immediate queued-callback removal. Owner
  smoke passes completion/timeout/cancel tests.
- Published scene/underlay state is copied under the publication lock and Metal
  work is serialized separately. External fullscreen DELL evidence records
  `3602` ticks, `120.0005 Hz`, `1754` presented, `58.5483 FPS`, 16.65 ms median,
  and zero migration/renderer failures. Strict 59 FPS remains open.
- Cast lock-fix validation still stops before Cast at Gunbarrel tick `2924`,
  `castSubmit=0`, no crash/authority error. Current signed Release SHA-256:
  `afd99228c5365467930dabe1fe912210b14666e8349a7af2953ee9db0b20b77c`.
  Current-hash passive evidence: `build/native/boot-runtime/cadence/runs/m30-direct-launch-passive-20260824-r2/direct-no-env-policy.log`.

## 2026-08-24 Cast validation keepalive isolation

- The repeated foreground cadence keepalive was removed from production.
  The Cast harness defaults to passive source-authority/scene-composition
  validation; Metal encode/shader/capture remains a separate explicit
  foreground lane.
- The isolated run still stops pre-Cast at Gunbarrel (`castSubmit=0`, no crash/
  authority error), so this is a harness-negative result rather than Cast
  acceptance. Current signed Release SHA-256:
  `20694ab3c22615a7ad7908960dd8c9dbe0e6e0c657edd8352ff44bad1d79c6ea`.

## 2026-08-24 fully passive AppKit runtime closure

- Root cause was the cadence keepalive reasserting activation and key-window
  status every 250 ms. Production no longer has that loop, a floating cadence
  window, or `orderFrontRegardless`. Exact background `0` is the only path
  allowed to activate, key, or enter fullscreen.
- Passive launch policy is applied before AppKit runs and is fail-closed. The
  window is alpha-zero, normal-level, click-through, outside first-responder
  ownership, and re-deactivated on real key/active notifications; initial
  focus loss neutralizes keyboard and controller input. Reopen is suppressed.
- Runtime harnesses use shared serialization and exact-PID cleanup. Background
  cadence validates owner/source/audio/non-interference; foreground HID and GPU
  capture require explicit disruptive opt-ins and are not inferred from it.
- Final source-faithful Release is signed, bundle/provenance-gated, and hashes
  to `1a1831ba059a8831c43b04dd8379095400e7771c81d797a612e491285c18ae3d`.
  Final evidence at
  `build/native/boot-runtime/cadence/runs/m30-final-passive-background-20260824/120/`
  records ChatGPT frontmost, inactive/non-key/windowed state at start and end,
  zero background focus violations, alpha zero, `362` ticks/source frames at
  `120.2059 Hz`, `sourceAuthorityFailure=none`, zero audio/owner pause, zero
  render/fatal/migration failures, and clean bounded termination.
- Presentation remains explicitly `background-unverified`: callbacks occurred,
  but zero visible pixels and rejected presented timestamps are not active-
  display FPS, Metal HUD, physical visual, or human-review evidence.

## 2026-08-24 current Release passive/Cast evidence

- Fresh Release bundle gate/codesign PASS; executable SHA-256:
  `75b030d6d8e11ee1de14bd6de34a834fb23c626fda12bc59dd94c27add9ca86e`.
- Passive direct-bundle run remained alive for 70 seconds with NetSward
  frontmost, GoldenEye inactive/non-key, alpha-zero/normal-level/click-through,
  and source owner ticks through `4314`.
- Source Cast owner submission reached `castSubmit=1` at tick `4313` for
  source index `2` (body `16`, animation `63`, 49 draws, 2,100 vertices,
  16 poses). Evidence root:
  `build/native/boot-runtime/cadence/runs/m30-release-passive-cast-20260824/`.
- This does not close the foreground supplied-drawable Cast Metal gate. Debug
  API/shader validation still hits the explicit Gunbarrel performance/debt
  boundary before Cast; the route remains fail-closed and no fallback/mask
  clearing is authorized.
- A final exact `open -g -n` launch with no background variable and fullscreen
  requested remained passive under the same hash: NetSward stayed frontmost,
  GoldenEye was not frontmost, and fullscreen was suppressed. Evidence:
  `build/native/boot-runtime/cadence/runs/m30-direct-noenv-final-20260824/`.
- Fresh stage gameplay-camera production supplied-drawable capture passes for
  demo 0/stages `33,34,35,9,20,26,25` with non-identity cameras, all static
  props drawable, deterministic raw hashes, API/shader validation, scoped
  unsupported `0`, and retained full-scene `0x38`.
