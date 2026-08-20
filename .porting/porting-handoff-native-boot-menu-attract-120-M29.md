# Native Boot/Menu/Attract/120 Hz — Active Handoff (M29 refresh)

## State

`native-boot-menu-attract-120` remains active and incomplete. This is an
evidence handoff, not a completion claim. The worktree is intentionally dirty;
no commit, push, branch, reset, clean, or unrelated deletion was performed.

Signed Release app:

`/Users/derek/Developer/goldeneye-swift/build/native/boot-runtime/GoldenEyeHost.app`

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
  `build/native/boot-runtime/GoldenEyeHost.app`.
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
- `scripts/test_stage_background_draw_packet.sh build/native/stage-assets`
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

## Open acceptance gates

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
- Native stage room display-list triangles, collision, AI, weapons, effects,
  Metal scene submission, and RAMROM execution against those systems remain
  open; the new M27 room/portal packet is diagnostic overlay evidence only.
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
scripts/test_stage_setup_packet.sh build/native/stage-assets
scripts/test_stage_scene_packet.sh build/native/stage-assets
scripts/test_stage_background_draw_packet.sh build/native/stage-assets
scripts/test_stage_gameplay_runtime.sh build/native/stage-assets build/native/boot-assets
scripts/test_ramrom_all14.sh build/native/boot-assets/ramrom build/native/stage-assets
```

Do not treat the build, launch, screenshot, or local GPU trace as N64 pixel or
performance parity. Runtime must continue to avoid opening the ROM; private
prepared assets remain beneath ignored `build/native/` directories.
