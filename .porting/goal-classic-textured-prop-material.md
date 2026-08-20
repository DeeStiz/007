# Porting Goal: Classic Textured Prop Material

## Status

Complete — executed autonomously after the completed
`classic-gbi-static-prop-replay` goal.

## Target

Render the same ROM-derived ammo crate with its real source textures and UVs
through the bounded classic replay and direct Metal 4 path. The completed goal
must provide:

- a new fixed-width texture/material ABI while preserving V1 and V2 unchanged;
- UV-carrying immutable draw packets and deterministic material/event hashes;
- provenance-guarded extraction and decoding of the three source payloads:
  `AMMOCRATE1` (I8/Huffman-blur, 64x32), `AMMOTEXT765` (IA4/Huffman-lookup,
  128x16), and `CRATEROPE` (RGBA16-CI8 with a 256-entry palette, 32x32);
- bounded expansion of the custom `G_SETTEX`/`G_TEXTURE` material sequence into
  texture-image, tile, TMEM, and TLUT load plans for the commands actually
  required by this prop;
- private resident Metal 4 textures and samplers uploaded through the unified
  compute encoder, explicit synchronization, and argument-table bindings;
- a textured ammo-crate frame with inspected GPU texture bindings and no silent
  vertex-color fallback;
- deterministic replay/material/pixel artifacts, clean validation, sanitizer and
  leak evidence, resize/shutdown evidence, and an inspected GPU capture.

This goal does not claim generic RDP combiner parity, depth/fog/alpha parity,
full game boot, gameplay, emulator parity, sustained performance, or release
acceptance.

## Selection Rationale

The completed classic replay goal already produces correct bounded geometry,
state snapshots, transforms, and custom texture selection for `Pammo_crate1Z`.
The remaining visible gap is the source texture path. The repository contains
the authoritative PD texture decoder semantics in `tools/mktex/src/libpdtex`,
the extracted source payloads, and the source material metadata. This goal adds
the smallest material feature delta while keeping the full RDP and game-loop
port out of scope.

The prop's 22-command primary list contains custom `G_SETTEX`/`G_TEXTURE`, but
not generic `G_SETTIMG`/`G_SETTILE`/`G_LOADBLOCK`/`G_LOADTLUT` commands. The
native implementation must reproduce the source runtime's bounded expansion
from `ModelFileTextures` and decoded payloads; it must not pretend those loads
were authored in the prop list.

## Key Decisions

- Carry forward Swift 6, Apple Clang C, AppKit, macOS 27, direct Metal 4, the
  external US ROM boundary, and exact Linux qemu-irix reference-build evidence.
- Preserve all V1/V2 ABI layouts and hashes. Texture/material records use a new
  version and remain value-only, fixed-width, copied, and bounded.
- Keep C authoritative for texture format decoding, UV/material state, source
  order, tile/TMEM/TLUT planning, and immutable draw snapshots. Swift owns
  lifecycle and Metal objects.
- Re-extract only to ignored build output. Never track or bundle the ROM or
  private source payloads.
- Use existing `libpdtex` behavior as the source decoder reference; PNG output
  from `tex2png` is diagnostic only and is not runtime truth.
- Sequence decoder work by risk: AMMOCRATE1 I8 first, AMMOTEXT765 IA4 second,
  and CRATEROPE RGBA16-CI8/TLUT third.
- Upload with `MTL4ComputeCommandEncoder.copyFromBuffer(...toTexture:...)` into
  private shader-readable textures. Use shared staging buffers, committed
  residency, queue events/barriers, and explicit staging retirement.
- The first textured material is an explicit `TEXEL0 * vertex shade` diagnostic
  combiner. Generic combiner lowering is a later goal.
- No worker may commit, push, branch, reset, clean, or perform unrelated
  cleanup. The primary agent owns ABI reconciliation, Package.swift/host
  integration, `.porting` artifacts, and final handoff.

## Milestones

| # | Name | Success Criterion | Status |
|---|---|---|---|
| M0 | Texture provenance guard | Verify the external ROM SHA-1, exact Linux reference command/hash evidence, `imagelist.u.csv` offsets, all three payload sizes/hashes/formats/dimensions, and no tracked/bundled private assets. | Complete |
| M1 | Texture ABI and UV snapshots | Add V3 fixed-width texture/material records and UV-carrying draw packets. V1/V2 layouts, hashes, and tests remain unchanged. | Complete |
| M2 | AMMOCRATE1 decoder | Decode I8/Huffman-blur payloads, dimensions, mip metadata, and texels with deterministic hashes and truncation/invalid-Huffman rejection. | Complete |
| M3 | AMMOTEXT765 decoder | Decode IA4/Huffman-lookup payloads with deterministic intensity/alpha output and malformed-input rejection. | Complete |
| M4 | CRATEROPE/TLUT decoder | Decode RGBA16-CI8 payloads and 256-entry palette data; validate TLUT bounds, palette hashes, and source dimensions. | Complete |
| M5 | Classic texture/TMEM state | Expand custom `G_SETTEX`/`G_TEXTURE` plus source material metadata into bounded tile/TMEM/TLUT load plans. Reject overflow, overlap, invalid tile state, and unsupported formats. | Complete |
| M6 | Metal 4 texture resources | Upload decoded textures through the unified compute encoder into private textures, bind samplers/textures via argument tables, and prove residency, staging retirement, and synchronization in a capture. | Complete |
| M7 | Textured ammo-crate material | Render all crate draw groups with source UVs and sampled source textures. Runtime hashes, material IDs, texture bindings, frame counts, and validation logs are stable with no diagnostic fallback. | Complete |
| M8 | Acceptance and handoff | Run regression, malformed-input, ASan/UBSan, leaks, HUD/resource stability, resize/shutdown, screenshot, Metal validation, GPU capture, and `gpudebug` texture-binding inspection. Update memory and write the handoff without commit/push. | Complete |

## Autonomous Execution Contract

After this goal is approved, the agent advances through every milestone's
prepare, execute, validate, and handoff phases without requesting milestone-by-
milestone confirmation. Luna-max workers run in disjoint lanes:

1. C ABI/replay/material state;
2. texture extraction and decoder;
3. Swift/Metal resources and shaders;
4. independent validation/evidence review.

The primary agent integrates and verifies all worker output. Ordinary compile,
test, and capture failures receive targeted repair iterations automatically.
The methodology's five-hypothesis escalation limit remains active. The run
stops only for a hard blocker, writes the current handoff, and reports the exact
missing authority or external state.

## Hard Stop Conditions

- external ROM missing, inside the checkout, or SHA-1 mismatch;
- Linux reference command/hash evidence missing or changed;
- source texture format or decoder semantics cannot be established from
  repository evidence;
- Metal 4 device/compiler/compute upload path unavailable;
- texture bindings/residency cannot be verified in a GPU capture or equivalent;
- persistent failure after bounded repair iterations;
- requested work would expand into generic combiner/RDP, game boot, gameplay,
  audio, performance, or release architecture.

Human visual/parity review remains a separate evidence boundary: machine
validation can prove hashes, dimensions, draw/material counts, texture bindings,
and screenshot existence, but cannot claim N64 visual parity.

## Evidence Artifacts

- `build/native/classic-textures/classic-texture-manifest.txt`
- `build/native/classic-textures/prepare-classic-textures.log`
- deterministic decoded/replay/material logs
- ASan/UBSan and normal leak logs
- `build/native/m11-classic-textured-prop.png`
- `build/native/m11-pixel.sha256`
- `build/native/m11-runtime.log`
- `build/native/m11-runtime-resize.log`
- `build/native/m11-resize.log`
- `build/native/m11-leaks.log`
- `build/native/m11-shutdown.log`
- `build/native/m11-classic-textured-prop.gputrace`
- `build/native/m11-gpudebug.log`
- `.porting/porting-handoff-classic-textured-prop-material-M8.md`

## Completion Evidence

The frozen V1/V2 replay hashes remain `1522029846112142469`,
`65363635960931316`, `905714786767796339`, and `10439205544326414085`.
The V3 textured replay reports 24 commands, four draws, 40 vertices, and 20
triangles with packet hash `11580554792388204033`, event hash
`9845751795158270468`, and material hash `14168780479827987350`. The M11
runtime matches those hashes for 60 frames and 240 draws with six resource
allocations. The inspected capture proves three compute texture blits, four
render draws, the three expected texture dimensions, and one texture plus one
sampler binding. Resize, zero-leak, shutdown, Metal validation, and
ASan/UBSan evidence are recorded in the artifacts above.

## Architecture Notes

- `assets/images.def` maps the crate texture IDs: `0x21` AMMOCRATE1, `0x25`
  CRATEROPE, and `0x27` AMMOTEXT765. `imagelist.u.csv` supplies their ROM
  offsets and compressed sizes.
- `tools/mktex/src/libpdtex/reader.c` supports the PD texture container,
  Huffman/RLE/lookup compression, mip levels, and palettes. Native decoding
  must copy its semantics into a bounded C API rather than compile the tool's
  PNG writer into the host.
- The existing Metal argument table has one texture and one sampler slot; it
  must be explicitly expanded before textured shaders are bound.
- Texture resources and staging buffers must be retained until shared-event
  retirement because Metal 4 command buffers do not retain resources.

## Skills

| Milestone | Skills |
|---|---|
| M0–M5 | `porting-methodology`, `swift-testing-expert`, `swift-concurrency`; source `gbi.h`/texture decoder inspection |
| M6 | `translating-to-metal4-api`, `managing-metal4-resources`, `managing-metal4-synchronization`, `using-metal-validation` |
| M7 | `creating-metal4-shader-pipelines`, `presenting-metal-drawables`, `using-metal-validation`, `debugging-rendering-issues` |
| M8 | `using-gpucapture`, `using-gpudebug`, `using-metal-validation`, `swift-testing-expert`, `porting-methodology` |

## Next Goal Horizon

After this goal: explicit combiner/render-mode lowering, then depth/fog/alpha,
then source display-list production and native title/level boot. Full gameplay,
parity, sustained performance, and release remain later goals.
