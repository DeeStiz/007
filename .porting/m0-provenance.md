# M0 Legacy Baseline Evidence

## Source provenance

- Upstream remote: `https://github.com/n64decomp/007.git`
- Reference commit: `c4356466796c697dfd298010b9bed261f9ed8c6a`
- Reference subject: `james bond will return.`
- Local reference: `HEAD` resolves to the same commit after a depth-one fetch.
- `git status --short --untracked-files=no` reports only the intentional
  Darwin/build-baseline edits in `.gitignore`, `Makefile`, `ge007.ld`,
  `Dockerfile`, `tools/1172compress.sh`, `tools/data_compress.sh`, and
  `tools/ido5.3_recomp/Makefile`; all other tracked source/configuration files
  match the fetched upstream tree byte-for-byte.
- Local `.porting/` artifacts are goal-local additions and are not part of the upstream source lane.

## ROM provenance

- External input: `/Users/derek/Documents/GoldenEye 007 (USA).z64`
- SHA-1: `abe01e4aeb033b6c0836819f549c791b26cfde83`
- Expected US build hash: `ge007.u.sha1` records the same SHA-1 for `build/u/ge007.u.z64`.
- `git ls-files '*.z64'` returns no paths. The ROM is not tracked, copied into the checkout, or intended for an application bundle.
- The extracted asset tree is local build input only; it is not source provenance or visual parity evidence.

## Build attempts

- The canonical command is `make VERSION=US VERBOSE=1`.
- Darwin portability fixes now cover the vendored IDO linker flag, 1172 compression byte trimming, linker-script token pasting, and data-segment map/stat parsing. The canonical command reaches final ROM generation on macOS.
- The linker script now aligns the embedded GSP/ASP data block to the source-authored `0x8005c820` boundary; the corrected ASP text extraction and alignment move `_bssSegmentStart` to `0x8005d2e0`, matching the verified ROM's startup address sequence.
- The corrected RSP/ASP extraction now uses the canonical `aspMainTextSize=0xDC0`; the macOS arm64 lane remains buildable but is not the byte-match authority.
- The corrected linker alignment places `.bss` at the expected `0x8005d2e0`.
- A native Linux arm64 Colima container built qemu-irix from the upstream fork at
  `/Users/derek/Developer/qemu-irix-arm-src` (commit `6d7d1fde2f68adf795e51a19ad2572a48931884e`) and ran the original IRIX compiler with `IDO_RECOMP=NO`.
- Canonical reference command: `make -j8 IDO_RECOMP=NO VERSION=US COMPARE=1 VERBOSE=1`.
  The generated 12,582,912-byte ROM passes `sha1sum -c ge007.u.sha1` with the
  expected SHA-1 `abe01e4aeb033b6c0836819f549c791b26cfde83`.
- The aligned object audit reports 26 object-section hash differences, but the
  final linked ROM is an exact byte match; these are relocatable/object
  representation differences and do not invalidate the M0 ROM criterion.
- The Docker reference image required `libglib2.0-0` for qemu-irix; that missing
  dependency is now declared in `Dockerfile`.
- Rebuilding the vendored IDO toolchain with Homebrew GCC 16 on arm64 before
  the ASP/alignment corrections produced the same ROM SHA-1
  (`69d98db3e4ba6a1e417a2e4807c3fdbc3dfd7f25`). An x86_64
  Darwin/Rosetta experiment could not execute the recompiler (both processes
  became uninterruptible), so it produced no alternate build evidence.
- Earlier macOS-native QEMU and Rosetta experiments remain historical only; the
  native Linux qemu-irix container is now the authoritative reference evidence.
