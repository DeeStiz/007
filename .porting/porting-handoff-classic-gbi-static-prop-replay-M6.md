# Porting Handoff: Classic GBI Static Prop Replay — M6

## Status

The `classic-gbi-static-prop-replay` goal is complete. No commit, push, branch,
cleanup, or reset was performed. The worktree still contains the prior
Darwin/native changes and the new untracked native/replay artifacts for the
user to review and preserve.

## What Was Done

- Added a separate fixed-width V2 classic replay ABI while leaving the proven
  V1 synthetic triangle ABI unchanged.
- Implemented C-authoritative classic GE/F3D replay for `G_MTX`, `G_VTX`,
  `G_DL`, `G_TRI4`, `G_TRI1`, `G_POPMTX`, `G_MOVEWORD`, texture/other-mode/
  combiner state, sync commands, and `G_ENDDL`.
- Added bounded list stack, active-list cycle rejection, command/depth budgets,
  resource validation, fixed s15.16 matrix conversion, modelview/projection
  stacks, viewport mapping, immutable per-draw state/transform snapshots, and
  deterministic packet/event/state hashes.
- Added external ROM/asset provenance scripts for the canonical
  `Pammo_crate1Z.bin` row. The ROM remains external and is never copied into the
  checkout or application bundle.
- Added a Metal 4 renderer and shader that replay the authored outer `G_DL`
  wrapper and draw four transformed prop packets through resident shared
  vertex/index/transient buffers and argument-table GPU addresses. The visible
  material is explicitly vertex-color diagnostic; texture/TMEM/TLUT/combiner
  fidelity is not claimed.
- Added build, C/Swift smoke, sanitizer, runtime, screenshot, capture, and
  `gpudebug` harnesses.

## Validation Evidence

### Provenance

`scripts/test_classic_prop_asset.sh` passes with:

- External ROM size `12,582,912`, SHA-1
  `abe01e4aeb033b6c0836819f549c791b26cfde83`.
- Canonical Linux reference command preserved:
  `make -j8 IDO_RECOMP=NO VERSION=US COMPARE=1 VERBOSE=1`.
- Canonical hash check preserved: `sha1sum -c ge007.u.sha1`.
- Compressed prop: 576 bytes, SHA-256
  `aae993c36f98527510578a5d5b0dd707a54117884385c68ddc781def96af0ec9`.
- Decompressed prop: 1488 bytes, SHA-1
  `2902e2f28defaa2f99e514c12039a731e78072d7`, SHA-256
  `ca13ff3f26a399767435767fc748cd91027db675ac630d89bfbacc7705b760c9`.

Manifest: `build/native/classic-prop/classic-prop-manifest.txt`.

### Replay and sanitizers

`scripts/test_classic_gbi.sh` passes C, Swift, malformed-input, cycle/depth/
budget/resource/matrix, and ASan/UBSan smoke tests.

- Nested fixture: commands `8`, enters `2`, returns `2`, one draw, three
  vertices, three triangles; packet hash `65363635960931316`, event hash
  `905714786767796339`, state hash `10439205544326414085`.
- Ammo crate: commands `24`, enters `2`, returns `2`, four draw packets,
  `40` loaded vertices, `20` triangles; packet hash
  `10577044718902439990`, event hash `8571243223740837031`, state hash
  `3848924740578548625`.

Logs:

- `build/native/classic-replay/classic-replay-smoke.log`
- `build/native/classic-replay/classic-replay-sanitized.log`
- `build/native/classic-replay/classic-replay-swift-smoke.log`

### Runtime / Metal

`scripts/test_m10_classic_prop.sh` passes a development-signed macOS 27 app:

```text
status=0 commands=24 enters=2 returns=2 drawPackets=4 vertices=40 triangles=20
packetHash=10577044718902439990 eventHash=8571243223740837031
stateHash=3848924740578548625 frames=60 draws=240 lastSignal=60 resourceAllocations=3
```

Resize and shutdown probes pass:

```text
resize=1 first=960x540 second=800x450 third=1024x576
shutdown=1
```

Normal non-HUD leak probe passes:

```text
Process 46223: 0 leaks for 0 total leaked bytes.
```

Metal API and GPU validation were enabled in the runtime run. The final log
contains the validation-enabled records and no GoldenEyeHost Metal fault,
validation error, shader-validation error, or assertion failure.

Screenshot artifact: [m10-classic-prop.png](</Users/derek/Developer/goldeneye-swift/build/native/m10-classic-prop.png>)
with the recorded raw hash in `build/native/m10-pixel.sha256`. The geometry is
repeatable, but the local window compositor can vary SDR channels by one code
between raw captures; this is tracked as an evidence limitation, not replay
state nondeterminism.

GPU trace: `build/native/m10-classic-prop.gputrace` (about 2.1 MB).
`build/native/m10-gpudebug.log` statically inspects one command buffer, one
render encoder, four labeled draw groups, the `GoldenEye.M5.ClassicProp`
pipeline, the 2 KiB vertex buffer, 240-byte index buffer, 128-byte transient
buffer, and a first draw of 24 UInt32 indices. Resource fetching remains an
environment limitation and is not part of the acceptance claim.

## Ground Truth Comparison

No emulator, N64 hardware, RenderDoc XML, reference screenshot, or reference
GPU capture exists in the repository or discovery artifacts. Therefore there is
no source-platform pixel comparison to report. The inspected native trace and
screenshot prove only the declared fixed-width classic replay, transform, and
Metal 4 diagnostic-material path.

## What's Deferred

- Texture decoding and upload, TMEM/TLUT, samplers, combiner lowering, render
  modes, depth, fog, alpha/coverage, lighting, and clipping.
- Full source display-list production, `bossEntry`/`bossMainloop`/`lvlRender`,
  N64 scheduler/boot, gameplay, controllers, audio, saves, parity, performance,
  notarization, and release packaging.

## Known Issues and Watch For

- `ge_classic_replay_prop_blob` validates the fixed blob size and structure;
  cryptographic ROM/prop provenance is deliberately enforced by the external
  preparation script and manifest rather than duplicating SHA-1 in the C core.
- `tools/1172inflate.sh` emits its expected truncated-wrapper gzip warning while
  producing the validated 1488-byte output.
- The generated ignored `assets/obseg/prop/*/Model.c` remains pointer-bearing
  source representation and must not be compiled into the native target.
- Raw screenshot hashes may drift by one SDR channel code under the local
  compositor; rely on replay/event hashes and inspected GPU state for
  deterministic acceptance.
- A fresh `scripts/test_m8_triangle.sh` rerun hit the same raw window-capture
  byte comparison variance; the existing M8 packet/hash/GPU evidence remains
  unchanged, and the M1/M7 V1 regression suites pass.

## Key Decisions

- `Pammo_crate1Z.bin` was selected over a texture-free prop because it exercises
  the classic custom commands needed for this goal. Its texture state is
  recorded, not rendered faithfully.
- The V1 ABI and M8/M9 synthetic triangle path remain frozen regression lanes.
- The outer `G_DL` wrapper is an explicit bounded fixture because the crate's
  own primary list contains no nested `G_DL`.
- No external ROM, generated private prop, or application bundle asset was
  tracked by the new work.

## Skills Used

`porting-methodology`, `translating-to-metal4-api`, `swift-concurrency`,
`swift-testing-expert`, `managing-metal4-resources`,
`managing-metal4-synchronization`, `presenting-metal-drawables`,
`creating-metal4-shader-pipelines`, `using-metal-validation`,
`using-gpucapture`, `using-gpudebug`, and `debugging-rendering-issues`.

## Next Goal

The next bounded goal should be texture/TMEM/TLUT decoding and upload for the
ammo-crate material, followed by explicit combiner/render-mode lowering. Start a
fresh planning session with `/porting-plan-goal` when ready.
