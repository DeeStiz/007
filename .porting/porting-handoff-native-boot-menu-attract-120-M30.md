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
   regenerated with 80 verified sidecars and the source-row-2 capture resolves
   `spicebond` with no missing prepared model.

6. AppKit focus loss resets held input but does not pause the source authority,
   owner scheduler, audio service, or renderer. The source input bridge keeps a
   neutral keyboard-backed controller connected so Legal/File/Mode/Cast/RAMROM
   clocks continue while unfocused. Window setup now uses a full-size content
   view, opaque black CAMetalLayer, backing-scale drawable sizing, fullscreen
   menu support, and a runtime activity assertion.

## Validation

Passed:

- Debug and Release `GoldenEyeHost` builds.
- `scripts/build_native_boot.sh` Release gate, codesign, bundle payload guard,
  and external-ROM provenance check.
- Strict Metal/API/shader validation for the source scene, Nintendo, Rareware,
  Cast, source-2D, and Gunbarrel lanes.
- Gunbarrel strict/ASan/UBSan smoke, 42-frame blood handshake, and Metal
  temporal sweep across modes 2...9.
- Cast strict repeat capture with byte-identical reference and Faithful-HD
  outputs, plus a source-row-2 `spicebond` capture.
- Owner/input/focus suites, including zero scheduler/audio pause counters for
  the always-active focus contract.
- Source pipeline corpus, title route, source-title material, and source-2D
  contract suites.

Representative artifacts are under ignored `build/native/`, including:

- `build/native/nintendo-reference-capture-v6/`
- `build/native/rareware-reference-capture-v6/`
- `build/native/gunbarrel-metal-reference-capture-v6/`
- `build/native/cast-reference-capture-v6/spicebond-strict-20260821/`
- `build/native/boot-runtime/source-faithful/GoldenEyeHost.app`

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
