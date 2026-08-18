# Porting Handoff: Native Metal First Frame — M1

## Status

M1 Callable fixture core is complete. M0's N64 byte-match remains an explicit
macOS host-toolchain gap: the canonical build reaches a ROM but does not match
the verified US ROM hash. M2 may proceed because it depends on the native ABI,
not on a byte-identical N64 build.

## Implemented

- Added `native/include/goldeneye_native.h`, a versioned fixed-width ABI with
  value-only lifecycle/step/fixture functions and no public pointers.
- Added `native/src/goldeneye_native.c` with strict version/size/reserved-field
  checks, cold/ready lifecycle, owner-thread capture/check, deterministic
  three-vertex/two-command fixture data, and canonical fixed-width FNV hashes.
- Added C and Swift ABI/behavior smoke tests plus a macOS build/test harness:
  `scripts/build_native_m1.sh` and `scripts/test_native_m1.sh`.

## Validation evidence

Command: `scripts/test_native_m1.sh`

- Apple Clang archive build passed.
- C smoke passed: malformed version/size/reserved inputs, cold/duplicate/repeated
  lifecycle, immutable packet/hash, valid step, and wrong-owner-thread step and
  shutdown.
- Swift smoke passed: all public `MemoryLayout` sizes/alignment, value-only API
  calls, malformed version/size, packet fields, and repeated hash equality.
- ASan/UBSan C smoke passed.
- `ar`/`nm` archive inspection showed only `goldeneye_native.o` and the four
  `ge_native_*` exports; no process entry, MIPS, N64, or hardware symbols.
- `git diff --check` passed.

## Generated evidence

- `build/native/m1/libgoldeneye_native.a`
- `build/native/m1/goldeneye_native_c_smoke`
- `build/native/m1/goldeneye_native_swift_smoke`
- `build/native/m1/sanitize/goldeneye_native_c_smoke_sanitized`

## Watch items for M2

- Keep the C archive independent from the N64 Makefile and never add raw
  `Gfx`/N64 pointers to the public ABI.
- The next host milestone should add only AppKit/window/lifecycle ownership;
  Metal capability remains unpublished until M4.
- Use the M1 owner-thread contract for the host loop and preserve immutable
  value snapshots across any future display-link callback.

## Next milestone

`/porting-start-milestone m2` (automated continuation authorized for this task)
