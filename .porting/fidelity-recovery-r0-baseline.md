# Fidelity Recovery R0 Baseline

This is the additive R0 provenance/rebaseline record for the source-faithful
renderer recovery. It does not replace or edit the existing porting goal,
handoffs, V1--V5 contracts, or prior evidence. The guard that produced this
record is `scripts/test_fidelity_recovery_r0.sh`.

## Scope and preservation rule

- Existing worktree changes and every prior artifact remain in place. A clean
  committed checkout is also a valid R0 input; the guard records an empty
  status snapshot with `status_state=clean` instead of treating cleanliness as
  a provenance failure.
- This lane performs no Git mutation: no commit, push, branch, reset, clean, or
  deletion.
- The guard writes only ignored output beneath
  `build/native/fidelity-recovery/`.
- The status capture is a point-in-time inventory. Later additive work may add
  status entries; the guard always records the current sorted status before
  validating the immutable provenance and ABI checks. The status state is
  `dirty` when entries are present and `clean` when the capture is empty.

## External ROM and reference evidence

- Preparation-only ROM: `/Users/derek/Documents/GoldenEye 007 (USA).z64`
- Required SHA-1: `abe01e4aeb033b6c0836819f549c791b26cfde83`
- The real path must remain outside this checkout:
  `/Users/derek/Developer/goldeneye-swift`
- Required Linux reference command:
  `make -j8 IDO_RECOMP=NO VERSION=US COMPARE=1 VERBOSE=1`
- Required Linux hash command: `sha1sum -c ge007.u.sha1`
- Evidence source: `.porting/m0-provenance.md`

## Frozen V1--V4 values

The guard requires these values to remain present in the existing replay
evidence; it never rewrites those artifacts.

| Contract | Frozen values | Evidence checked |
| --- | --- | --- |
| V1 | `1522029846112142469` | `build/native/classic-textures/texture-replay-smoke.log` |
| V2 | packet `65363635960931316`; event `905714786767796339`; state `10439205544326414085` | `build/native/classic-textures/texture-replay-smoke.log` |
| V3 | packet `11580554792388204033`; event `9845751795158270468`; material `14168780479827987350` | `build/native/classic-textures/texture-replay-smoke.log` |
| V4 | setup `6213740136672363482`; event `5747731189711370311`; key `16733630809188353388` | `build/native/classic-combiner/classic-combiner-run-a.log` |

## Current V5 public header snapshot

The R0 guard hashes the fixed V5 public headers and compiles a C layout probe.
The values below are the baseline expected by this guard. Any change to these
headers or sizes fails closed and requires an additive contract decision.

### Header SHA-256

| Header | SHA-256 |
| --- | --- |
| `native/include/ge_audio_engine_v5.h` | `ec530ddedde1c12527279609a8acdfb043aeb517120e90544d8c0e69278db5e3` |
| `native/include/ge_audio_output_v5.h` | `b6a74fb2e847fddfebbeb769e8e88a87a8e10e81418fa44c489ac107c1ffb549` |
| `native/include/ge_audio_source_node_v5.h` | `6c833ce78c969fa55a8ffc32c6c62a4b77d83119f36803bc5c9b2bff620c5644` |
| `native/include/ge_audio_v5.h` | `403fb3b3a15a67e02fc6ec28793e61d46ec3968941212610ce51018c63ba6868` |
| `native/include/ge_classic_raster_v5.h` | `510957f05f8ab1127e42f5526b3759b4dd4d9e022beac3554f21f0277fb38391` |
| `native/include/ge_native_runtime_v5.h` | `de83712f434e94c33dcfffdfa80831b695fbfcbf2eb313fbbcd716af943f6cde` |
| `native/include/ge_ramrom_playback_v5.h` | `71f5f75b4e765508ae2bff18ed0cca2da10a4aa3d9b4660c95619ac4678f83e5` |
| `native/include/ge_ramrom_v5.h` | `4d0514069fba55ecfe072150bddd3f0849761e1968f7c9e84b534cb6663d2f0c` |
| `native/include/ge_stage_v5.h` | `da5cafd87734d0c921f7fe6756a1bbf21cb5d5cc86272f16489b73e2e9812534` |
| `native/include/ge_title_raster_v5.h` | `988fce12a477ec3c7b337dbcde8077520919eaaab35546cb1bf6ff167e2f80ca` |
| `native/include/ge_title_route_v5.h` | `e8a3af485980f90d0d47a1a1b0bf60090bd8cdb2c097bd1eb990378419fe6c97` |
| `native/include/ge_native_foundation.h` | `2979dc66b760cb5d572c4e494737c16693fff8dec390ab5a6b87c4eaeec7e80d` |
The umbrella `native/include/goldeneye_native.h` is intentionally excluded
from this immutable V5 hash set. R1 may add V6 includes there while the direct
V1--V5 record layouts remain unchanged; the layout probe below includes the
direct V5 headers explicitly.

### C layout sizes (Apple arm64, C11)

```text
GEAbiHeaderV1=8
GEAudioDiagnosticV5=128
GECSeqInfoV5=32
GECSeqLoopStateV5=12
GECSeqStateV5=3340
GECSeqEventV5=56
GEAudioSchedulerV5=3392
GEAudioWaveV5=76
GEAudioBankV5=36
GEAudioVoiceV5=131164
GEAudioSynthV5=3148120
GEAudioRenderResultV5=80
GEAudioPCMSourceSnapshotV5=72
GEAudioPCMSourceV5=32848
GEAudioPCMRefillResultV5=64
GEAudioPCMReadResultV5=64
GEAudioAssetV5=104
GEAudioEventV5=56
GEAudioPCMBlockV5=64
GEAudioSnapshotV5=88
GEAudioClockV5=40
GEClassicRasterStateV5=104
GEClassicRasterInputV5=28
GEClassicRasterResultV5=240
GETimebaseConfigV5=56
GEInputEventV5=64
GEInputSnapshotV5=88
GETitleParitySnapshotV5=136
GESceneFrameV5=120
GEScenePageV5=56
GEAudioCommandV5=88
GERamRomSnapshotV5=128
GERamRomPlaybackInstallV5=320
GERamRomPlaybackInputV5=40
GERamRomPlaybackEventV5=168
GERamRomPlaybackStateV5=472
GERamRomHeaderV5=184
GERamRomPacketV5=80
GERamRomSampleV5=36
GERamRomParseSummaryV5=104
GERamRomCatalogEntryV5=48
GEStageDiagnosticV5=132
GEStageResourceV5=100
GEStageCatalogEntryV5=348
GEStage1172InfoV5=48
GEStageAssetViewV5=64
GEStageResourcePacketV5=120
GEStageResourceViewV5=64
GEStageBackgroundV5=112
GEStageBackgroundRoomV5=96
GETitleRasterSourceStateV5=24
GETitleRasterStateV5=112
GETitleRasterInputV5=208
GETitleRasterResultV5=928
GETitleRouteCastEntryV5=32
GETitleRouteCastInputV5=52
GETitleRouteCastDecisionV5=40
GETitleRouteDemoSelectionV5=80
GETitleRouteRestorePointV5=48
```

## App and private-payload boundary

The guard enumerates every existing `build/native/**/*.app` bundle and fails if
any bundle contains a ROM or extracted private payload (`.z64`, `.n64`, `.bin`,
`.rz`, `.ctl`, `.tbl`, or `.seq`). It also verifies that the new R0 output path
is ignored and that no ROM/private payload is tracked by Git. The exact bundle
inventory and current dirty-status capture are written to:

- `build/native/fidelity-recovery/dirty-status.txt`
- `build/native/fidelity-recovery/bundle-boundary.txt`
- `build/native/fidelity-recovery/v5-public-header-sha256.txt`
- `build/native/fidelity-recovery/v5-layout.txt`
- `build/native/fidelity-recovery/r0-guard.log`

## R0 guard execution evidence

The first guard run completed on 2026-08-19 with 191 sorted status entries:

- tracked modified entries: `7`
- untracked entries: `184`
- `dirty-status.txt` SHA-256:
  `178f9d987451e7e7ce84de079761b93b2632d3f715ae63e56e9451476a25a15c`
- `r0-guard.log` ends in `PASS`
- all four discovered app bundles reported `private_payloads=none`
- the external ROM measured 12,582,912 bytes and the required SHA-1

An immediate rerun after the first capture included one concurrent additive
status entry and completed with 192 entries and status SHA-256
`d9413c1148b711d2f45940c1cafd99af596ee5130f055510f9053b92d1c4b4c4`.

The status file is intentionally a snapshot: concurrent additive work may add
entries after this capture. Re-running the guard records a new deterministic
status hash while keeping the frozen ABI/provenance checks fail-closed.

A later run from the committed M30 checkout may legitimately have zero status
entries. That run still records the empty capture and `status_state=clean`; all
other R0 checks remain unchanged and fail closed.

## Reproduction

```sh
cd /Users/derek/Developer/goldeneye-swift
scripts/test_fidelity_recovery_r0.sh
```

The guard is read-only with respect to existing source and evidence. Its only
intentional writes are its own ignored R0 output files.
