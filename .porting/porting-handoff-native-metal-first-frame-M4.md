# Porting Handoff: Native Metal First Frame — M4

## Status

M4 Metal 4 device setup is complete. No drawable was acquired and no command
buffer was submitted or presented.

## Implemented

- Added `native/host/metal_device_state.swift` with explicit Metal 4 family
  rejection, labeled device-owned `MTL4CommandQueue`, two retained reusable
  `MTL4CommandBuffer`/`MTL4CommandAllocator` pairs, initialized argument-table
  descriptor, scene residency set, CAMetalLayer residency capture, and shared
  completion event.
- The host assigns the layer's device only after MTL4 support is verified and
  writes `/tmp/goldeneye-m4-device.log` for runtime evidence.
- `scripts/test_m4_device.sh` launches the signed app with `MTL_DEBUG_LAYER=1`
  and statically rejects drawable/present calls from the M4 state file.

## Validation evidence

Command: `scripts/test_m4_device.sh` (GUI escalation)

Runtime evidence:

`metal4=1 queue=GoldenEye.M4.Queue slots=2
slotLabels=GoldenEye.M4.FrameSlot.0.CommandBuffer,GoldenEye.M4.FrameSlot.1.CommandBuffer
argumentTable=GoldenEye.M4.ArgumentTable.Scene
sceneResidencyDescriptor=GoldenEye.M4.SceneResidency layerResidency=1
completionEvent=GoldenEye.M4.CompletionEvent`

- SwiftPM debug build and ad-hoc app signing/verification passed.
- Real LaunchServices launch passed with Metal API validation enabled.
- MTL4 support, queue, two slots, argument table, scene/layer residency, and
  shared event evidence passed.
- No drawable acquisition/presentation is present in M4 code.

## Watch items for M5

- Command buffers remain device-created and reusable; allocators must not reset
  until GPU completion.
- Keep all resources in committed residency before submission; MTL4 command
  buffers do not retain them.
- M5 owns `nextDrawable`/`waitForDrawable`/commit/signal/present and must use a
  fresh GPU validation pass.

## Next milestone

`/porting-start-milestone m5` (automated continuation authorized for this task)
