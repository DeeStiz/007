# GoldenEye Swift Porting Memory

## Active Goal

- Goal: `classic-gbi-static-prop-replay`
- Goal document: `.porting/goal-classic-gbi-static-prop-replay.md`
- Current milestone: None — `classic-gbi-static-prop-replay` complete
- Status: Complete; prior `native-metal-first-frame` goal remains complete

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
- Audio, full controller mapping, real assets, title/level boot, and gameplay remain outside the active goal.
- The successor goal keeps V1 triangle ABI and M8/M9 evidence frozen; add a separate V2 classic replay ABI rather than changing the synthetic normalizer.
- Canonical ROM-derived prop input is `scripts/filelist.u.csv:308`, `Pammo_crate1Z.bin` at compressed ROM offset `8052448` and size `576`; the validated uncompressed artifact is 1488 bytes, SHA-1 `2902e2f28defaa2f99e514c12039a731e78072d7`, SHA-256 `ca13ff3f26a399767435767fc748cd91027db675ac630d89bfbacc7705b760c9`.
- The prop primary list is 22 classic commands with five `G_TRI4` operations (20 triangles), three `G_VTX` loads (16/16/8), a runtime segment-3 matrix reference, `G_SETTEX` state, and no nested `G_DL`; the replay goal must wrap it with a bounded outer list for push/return coverage.
- Texture/TMEM/TLUT/combiner fidelity is explicitly deferred. Replay records texture/mode state, while the visible prop acceptance uses an explicitly labeled vertex-color diagnostic material.
- Missing or mismatched extracted assets must fail closed. The native host must never fall back to reading the external ROM or bundle generated private assets.
- The M10 replay/event hashes are stable, but raw `CGWindowListCreateImage` screenshots can vary SDR channels by one code between captures because of the local compositor; retain the screenshot artifact and treat the replay/GPU evidence as the deterministic acceptance baseline.

# Feature Status

| Feature Domain | Status | Notes |
|---|---|---|
| Source provenance / Git | Implemented | Shallow local `HEAD` references upstream `c4356466796c697dfd298010b9bed261f9ed8c6a`; tracked source matches except documented Darwin portability edits. |
| Original N64 build baseline | Implemented | The native Linux qemu-irix reference lane passes `sha1sum -c ge007.u.sha1` with the expected US ROM hash; macOS remains a documented portability lane. |
| External ROM provenance | Implemented | Correct US ROM SHA-1 verified; remains external and untracked. |
| Extracted asset pipeline | Partial | Assets extracted; no native manifest, bundle policy, or repeatability proof. |
| Native Apple-Clang archive | Implemented | M1 archive/test harnesses pass under `scripts/test_native_m1.sh`; N64 objects remain out of the archive. |
| Fixed-width C/Swift ABI | Implemented | C and Swift layout assertions, malformed-input tests, and pointer-free V1/V2 boundary checks pass. |
| Deterministic fixture producer | Implemented | Synthetic three-vertex/two-command triangle fixture is deterministic; GBI normalization remains M7. |
| AppKit window | Implemented | M2 Apple Development-signed macOS 27 bundle launches a raw scale-correct `CAMetalLayer`; no `MTKView`. |
| Owner-thread lifecycle / main loop | Implemented | Dedicated serial owner queue advances 60 C ticks and records clean shutdown evidence. |
| Keyboard input | Implemented | M3 key/down/up and modifier edges feed fixed-width snapshots; live AppKit key delivery and pure-state focus reset pass, while this session emits no OS focus notification. |
| GameController gameplay input | Not started | Deferred beyond this goal. |
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
| Matrix / viewport / transforms | Implemented | Classic s15.16 matrices, modelview/projection stacks, viewport mapping, and transformed draw hashes pass; lighting/clipping remain deferred. |
| ROM-derived ammo-crate ingestion | Implemented | External `Pammo_crate1Z.bin` manifest/hash guard and C parser replay 40 vertices/20 triangles in source order pass. |
| Static prop Metal replay | Implemented | Four transformed draw packets render through Metal 4 argument tables/residency with explicit vertex-color diagnostic material. |
| Textures / TMEM / TLUT / samplers | Not started | Deferred. |
| Combiner / raster / depth / fog | Not started | Deferred. |
| Full source display-list production | Not started | `bossEntry`, `bossMainloop`, and `lvlRender` deferred. |
| Audio | Not started | Deferred. |
| Saves / replay | Not started | Deferred. |
| Debug markers / resource labels | Implemented | M8/M10 frame, encoder, pipeline, buffer, and draw labels are present in inspected captures. |
| Metal validation | Implemented | M4–M9 real-device runs use API/load/store/shader validation; no reported Metal fault. |
| GPU capture / `gpudebug` | Implemented | M5/M8/M10 `.gputrace` capture plus command-tree, draw, pipeline, binding, and attachment inspection pass; resource fetch remains environment-limited. |
| ASan / UBSan / leaks | Implemented | C/M1/M7 and bounded Swift/AppKit host ASan/UBSan runs pass; the separate normal non-HUD host reports zero leaks. |
| Metal HUD / resource stability | Implemented | M9 synthetic and M10 classic-prop runs pass 60 frames, explicit residency/resource counts, resize, and no Metal fault log. |
| Emulator/reference visual parity | Not started | No reference artifacts currently available. |
| Sustained performance / release | Not started | Deferred beyond this goal. |

Status values: Not started, Stubbed, Partial, Implemented.

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
- Bounded ASan, leaks, and HUD runs do not prove unexercised paths or indefinite stability.
