# Porting Handoff: Native Metal First Frame — M6

## Status

M6 baseline pipeline is complete. Minimal vertex/fragment MSL artifacts compile
to AIR/metallib, and a labeled Metal 4 function-descriptor pipeline is created
without submitting geometry.

## Implemented

- Added `native/shaders/GoldenEyeBaseline.metal` with deterministic baseline
  vertex/fragment entry points.
- Added `native/host/metal_baseline_pipeline.swift` using `MTL4Compiler`,
  `MTL4LibraryFunctionDescriptor`, and `MTL4RenderPipelineDescriptor`.
- Added `scripts/build_m6_pipeline.sh` to compile MSL with the Xcode 27 Metal
  toolchain, link the metallib, stage it into the signed app, and verify the
  bundle.
- Added `scripts/test_m6_pipeline.sh` for runtime pipeline creation with Metal
  API validation and a zero-draw assertion.

## Validation evidence

- `build/native/m6/GoldenEyeBaseline.air` and
  `build/native/m6/GoldenEyeBaseline.metallib` were produced.
- GUI-escalated `scripts/test_m6_pipeline.sh` passed.
- Runtime evidence: `pipeline=1 label=GoldenEye.M6.BaselinePipeline draws=0`.
- MTL4 compiler/function-descriptor creation completed without API validation
  faults. The M5 clear renderer is disabled for the M6 test, so no GBI geometry
  or draw call is submitted.

## Watch items for M7

- Keep the baseline pipeline's BGRA8Unorm_sRGB attachment identity stable.
- M7's C normalization must output immutable packets consumable by Swift without
  exposing `Gfx`, segmented pointers, or host addresses.
- Unsupported commands must fail closed with opcode and byte offset diagnostics;
  do not silently skip visible behavior.

## Next milestone

`/porting-start-milestone m7` (automated continuation authorized for this task)
