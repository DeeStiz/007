# Porting Handoff: Classic Textured Prop Material — M8

## Status

The `classic-textured-prop-material` goal is complete. Preparation, execution,
validation, and handoff were run autonomously. No commit, push, branch, reset,
or unrelated cleanup was performed. The external ROM and private extracted
payloads remain outside source control and application bundles.

## What Was Done

- Added the fixed-width V3 texture/material ABI and UV-carrying immutable draw
  packets while preserving V1/V2 layouts and regression hashes.
- Added bounded C-authoritative decoders for the three verified crate payloads:
  I8/Huffman-blur, IA4/Huffman-lookup, and RGBA16-CI8 with a 256-entry TLUT.
- Expanded the crate's authored custom `G_SETTEX`/`G_TEXTURE` sequence using
  source material metadata into bounded texture-image, tile, TMEM, and TLUT
  plans. The primary list has no generic `G_SETTIMG`, `G_SETTILE`,
  `G_LOADBLOCK`, or `G_LOADTLUT`; generic RDP command coverage is not claimed.
- Added the explicit diagnostic material `TEXEL0 * vertex shade`, with source
  UV normalization and no silent vertex-color fallback.
- Added Metal 4 private RGBA8 textures, shared staging, unified compute-encoder
  copies, committed residency, shared-event retirement, barriers, and
  argument-table texture/sampler bindings.
- Added repeatable provenance, replay, sanitizer, runtime, screenshot, capture,
  resize, leak, shutdown, and `gpudebug` acceptance harnesses.

## Validation Evidence

### Provenance

`scripts/test_classic_texture_assets.sh` and the M11 acceptance script pass.

- External ROM: `/Users/derek/Documents/GoldenEye 007 (USA).z64`, size
  `12,582,912`, SHA-1 `abe01e4aeb033b6c0836819f549c791b26cfde83`.
- Linux reference evidence remains `.porting/m0-provenance.md` with command
  `make -j8 IDO_RECOMP=NO VERSION=US COMPARE=1 VERBOSE=1` and hash check
  `sha1sum -c ge007.u.sha1`.
- `AMMOCRATE1`: 1610 bytes, SHA-1
  `a6291b4f2b1440cb123475d5f0ae22314402af65`, SHA-256
  `7fefb1b76158430234fd17769798bc58319cb322bd88ae3a979f2bc1b8445ef5`,
  I8/Huffman-blur, 64x32.
- `CRATEROPE`: 1003 bytes, SHA-1
  `b3fa9d916ef81d69fcfbf3e6a2ba8851d3f094ae`, SHA-256
  `4fce6fc79c4f45ba5164e2b31a635e3644b8e535b8bffa46014365bf1c978038`,
  RGBA16-CI8/RZIP palette container, 32x32, 256 entries.
- `AMMOTEXT765`: 551 bytes, SHA-1
  `84785fc84ee5534940959e4fd52827454b404d4b`, SHA-256
  `ec028a7399327a93b2300c42cfac3e1ab133d7ee1804fcd5bdd4b5a0dff05810`,
  IA4/Huffman-lookup, 128x16.

The manifest is `build/native/classic-textures/classic-texture-manifest.txt`.
`rom_copied_into_checkout=false`, `rom_copied_into_bundle=false`,
`private_payloads_copied_into_checkout=false`, and
`private_payloads_copied_into_bundle=false`. `tex2png` output is diagnostic
only; native decoder output is the runtime truth.

### Replay and decoders

`scripts/test_classic_texture_replay.sh` passes normal, ASan/UBSan, Swift V3,
and V1/V2 regression lanes.

```text
V1 hash       1522029846112142469
V2 packet     65363635960931316
V2 event      905714786767796339
V2 state      10439205544326414085

V3 commands 24, draws 4, vertices 40, triangles 20
V3 packet    11580554792388204033
V3 event     9845751795158270468
V3 material  14168780479827987350

AMMOCRATE1 source 96c331f295054786 decoded e3be26de8e688ff5
AMMOTEXT765 source 0b91dd635318355a decoded c8d7069691ef6243
CRATEROPE source bc68a84830d902be decoded e1b6f50bafb817a2
```

Malformed/truncated payload cases reject cleanly. Logs:

- `build/native/classic-textures/texture-replay-smoke.log`
- `build/native/classic-textures/texture-replay-sanitized.log`
- `build/native/classic-textures/texture-replay-swift-smoke.log`

### Runtime, Metal 4, and lifecycle

`scripts/test_m11_classic_textured_prop.sh` passes with API and shader
validation enabled for the runtime run:

```text
status=0 commands=24 drawPackets=4 vertices=40 triangles=20
packetHash=11580554792388204033 eventHash=9845751795158270468
materialHash=14168780479827987350
frames=60 draws=240 uploadsPending=false lastSignal=60 resourceAllocations=6
```

Texture records in the same runtime report source and decoded hashes for IDs
33, 37, and 39. The raw screenshot artifact is
`build/native/m11-classic-textured-prop.png`, with hash recorded in
`build/native/m11-pixel.sha256` (`fbc8fc7de88a3a24141281edb7bf4c866241449dafd8673f9a35d19de89e223c`).
The local compositor may vary SDR screenshot channels; this is not used as a
replacement for deterministic replay or GPU evidence.

The inspected capture is `build/native/m11-classic-textured-prop.gputrace` and
`build/native/m11-gpudebug.log` proves:

- one compute encoder with three blits and one render encoder with four draws;
- resident RGBA8Unorm textures `64x32`, `128x16`, and `32x32`;
- vertex and fragment stages with one texture and one sampler;
- a first indexed draw with 24 UInt32 indices.

Separate lifecycle evidence is recorded in:

- `build/native/m11-resize.log`: `960x540 -> 800x450 -> 1024x576`;
- `build/native/m11-leaks.log`: `0 leaks for 0 total leaked bytes`;
- `build/native/m11-shutdown.log`: `shutdown=1`;
- `build/native/m11-runtime-resize.log`: the same V3 hashes and 60-frame/
  240-draw resource counts under resize and validation.

`build/native/m11-validation.log` contains Metal API/GPU validation enabled
records and no GoldenEyeHost GPU fault, validation error, shader-validation
error, or assertion failure.

### Regression and boundaries

`scripts/test_native_m1.sh`, `scripts/test_m7_gbi.sh`, `swift build -c debug`,
and `git diff --check` pass. No emulator, N64 hardware capture, RenderDoc
reference, or source-platform screenshot exists, so this handoff does not claim
N64 pixel parity, generic RDP combiner parity, depth/fog/alpha parity,
sustained performance, gameplay, title/level boot, release acceptance, or
human visual acceptance.

## Deferred Work / Next Goal

The next bounded goal should lower the captured classic combiner and render-mode
state for this prop, then add depth/fog/alpha coverage. Full source display-list
production, native title/level boot, gameplay, audio, performance, parity, and
release remain later goals.

## Skills Used

`porting-methodology`, `porting-plan-goal`, `translating-to-metal4-api`,
`managing-metal4-resources`, `managing-metal4-synchronization`,
`creating-metal4-shader-pipelines`, `presenting-metal-drawables`,
`using-metal-validation`, `using-gpucapture`, `using-gpudebug`,
`debugging-rendering-issues`, `swift-testing-expert`, and `swift-concurrency`.
