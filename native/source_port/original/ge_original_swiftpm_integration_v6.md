# SwiftPM integration note

The source oracle is isolated in the `GoldenEyeOriginalFrontend` SwiftPM
target. `GoldenEyeHost` depends on that target, while the source-backed bridge
is opt-in through `GOLDENEYE_NATIVE_ORIGINAL_SOURCE=1`.

```swift
sources: [
    "ge_original_front_c.c",
    "ge_original_title_c.c",
    "ge_original_frontend_v6.c",
    "ge_original_host_stubs.c",
    "ge_original_production_weak_stubs.c",
],
cSettings: [
    .define("_LANGUAGE_C"),
    .define("VERSION_US"),
    .define("LANG_US"),
    .define("REFRESH_NTSC"),
    .define("LEFTOVERDEBUG"),
    .define("LEFTOVERSPECTRUM"),
    .define("BUGFIX_R0"),
    .define("BYTEMATCH"),
    .define("GE_ORIGINAL_FRONTEND_PRODUCTION"),
    .headerSearchPath("../../../"),
    .headerSearchPath("../../../include"),
    .headerSearchPath("../../../src"),
    .headerSearchPath("../../../src/game"),
    .headerSearchPath("../../../src/inflate"),
    .headerSearchPath("../../include"),
    .unsafeFlags([
        "-fno-modules",
        "-fno-implicit-modules",
        "-Wno-error=implicit-function-declaration",
        "-Wno-implicit-function-declaration",
        "-Wno-error=return-type",
        "-Wno-return-type",
    ]),
],
```

The wrapper translation units define the US/NTSC flags locally as well, so the
source semantics remain self-contained when compiled by the standalone
reference script.  No `F3DEX_GBI_2` or `F3DEX_GBI` define is permitted; the
checkout uses classic GE/F3D plus `include/gbi_extension.h`'s custom TRI4.

SwiftPM's relocatable C target prelinks its object members before the final
dead-strip pass. Directly adding only the source, adapter, and reference-stub
objects therefore left 103 unrelated source references unresolved despite
`-ffunction-sections` and `-dead_strip`; `ld` also rejects `-r -dead_strip`.
The production target includes deterministic weak zero-valued fallbacks for
those unexercised source branches. Its packaged target object now has only 12
normal system-library unresolved symbols (stack-check, math, and string
support), and `GoldenEyeOriginalFrontendSmoke` links and runs. The weak
fallbacks are not compiled by the reference oracle script.

The public fixed-width header for `GoldenEyeOriginalFrontend` is
`native/source_port/original/public/ge_original_frontend_v6.h`. It is
standalone, uses `GEOriginalAbiHeaderV1`/`uint32_t` status declarations, and
preserves the canonical record sizes and C function symbols. The private
implementation contract remains under `source_port/original` and includes the
native foundation header only by private relative path. The
`native/include/ge_original_frontend_v6.h` file is a SwiftPM marker that is
empty when `SWIFT_PACKAGE` is defined, so the GoldenEyeNative umbrella cannot
re-export or cycle back into the original module. The SwiftPM smoke imports
both modules and calls both APIs.

The original source adapter remains a 60 Hz source-anchor oracle. Its
`native_tick` input is the oracle's source-frame sequence; a future 120 Hz
caller must invoke it only at even outer ticks using `outerNativeTick >> 1`,
and must not run constructors on odd ticks. The current product bridge only
performs the link/init probe and makes no 120 Hz authority claim.

`ge_original_frontend_v6_step` now runs constructors only when the input
capture flag is set. Authority-only steps advance Legal/Nintendo/Rareware
source state without render mutation or source-gap events; explicit Rareware
capture remains the declared parity/render boundary.

## Symbols that must remain scoped

`front.c` owns source globals such as `current_menu`, `menu_update`,
`maybe_prev_menu`, `g_MenuTimer`, and `logoinst`; `title.c` owns
`gunbarrel_mode`, `D_8002A7D0`, `g_TitleX`, `chrModelInstance`, and
`gunModelInstance`.  The current native target has no same-named definitions,
but a second copy of either source translation unit would conflict.

`ge_original_host_stubs.c` intentionally supplies reference-only platform
sinks and generated data symbols (`viSet*`, `joyGet*`, `model*`, `music*`,
`PitemZ_entries`, `c_item_entries`, `g_ClockTimer`, and title segment/data
fixtures).  Adding production implementations of those same symbols to this
target creates duplicate definitions; replace the stubs at that boundary only
after the real source-resource services are available.

In the production target, unsupported model/resource services return null or
zero and the adapter emits a source-gap event plus an unsupported flag instead
of invoking the reference fake-model renderer. This target is linkable, not a
completion claim for the visual frontend.
