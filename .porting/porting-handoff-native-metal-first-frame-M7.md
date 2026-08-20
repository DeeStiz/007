# Porting Handoff: Native Metal First Frame — M7

## Status

M7 GBI normalization is complete for the deliberately bounded classic
GoldenEye fixture.

## Implemented

- Extended `native/include/goldeneye_native.h` with fixed-width resource
  handles, a four-command stream record, and a normalization result carrying
  opcode/byte-offset diagnostics.
- Added `ge_native_gbi_fixture_stream()` and
  `ge_native_normalize_gbi()` to `native/src/goldeneye_native.c`.
- The normalizer handles only `G_VTX 0x04`, `G_TRI1 0xBF`, and `G_ENDDL 0xB8`,
  resolves a deterministic `0x100` vertex resource handle, and fails closed on
  unsupported opcodes, missing handles, out-of-range indices, malformed order,
  invalid versions/sizes, and reserved bits.
- Added C and Swift M7 smoke tests plus ASan/UBSan coverage in
  `scripts/test_m7_gbi.sh`.

## Validation evidence

- `scripts/test_m7_gbi.sh` passed C valid/invalid cases, Swift layout/value
  calls, repeated packet/event hashes, and ASan/UBSan.
- Valid output contains exactly three vertices and two immutable commands
  (`0xBF` triangle and `0xB8` end marker).
- Unsupported/error results report the exact opcode and byte offset (for
  example `0x99` at offset `8`).
- The public ABI remains value-only and pointer-free; resource references are
  deterministic 32-bit handles.

## Watch items for M8

- Consume the normalized packet without traversing or retaining any C pointer.
- Bind vertex data through MTL4 argument-table GPU addresses and keep all
  referenced resources in committed residency sets.
- Preserve draw order and emit exactly one labeled draw; capture and inspect a
  trace with the expected pass/draw count.

## Next milestone

`/porting-start-milestone m8` (automated continuation authorized for this task)
