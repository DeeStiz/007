# RAMROM gameplay V6 source owner seam

This directory owns the additive, value-only C boundary for the native
RAMROM stage route. It is intentionally not wired into the Release renderer
until the source gameplay owner publishes the mutable state required by the
frame contract.

The current closure is source-backed and bounded:

- `src/game/ramromreplay.c`: source slot selection, borrowed recording bytes,
  packet/sample order, checksum and checkpoint publication.
- `src/random.s`: exact `randomGetNextFrom` transition exposed as a call-time
  `uint64_t` seed helper.
- `src/game/bondview_r.c`: `INTROTYPE_SPAWN` slot selection. The Swift page
  preparer parses the guarded decoded setup payload and selects the same pad
  for each RAMROM header `slot_number`.
- `src/game/stan.c`: decoded STAN tile traversal, source room bounds, floor
  tile selection and Q16 source bounds. The preparer retains only copied
  fixed-width values.
- Guarded setup/model/visible-dependency manifests: source object records,
  exact matrix words, model handles, prop/guard categories and provenance
  hashes.

`ge_ramrom_gameplay_v6_begin` fails closed unless source setup/model pages are
supplied through `ge_ramrom_gameplay_v6_begin_with_source_pages`. No default
entity, suit, camera offset, movement constant, AI branch, weapon event,
effect, or RNG call is manufactured. The current owner can install the exact
initial setup pages and consume paired recording metadata; `sourceReady`
remains false until mutable player/camera, guard animation/head/weapon,
objective, effect/projectile and stage-owner exports are supplied.

The corresponding smoke script validates corrected and legacy prepared roots
separately, all 14 recording headers/checkpoint/checksum streams, all seven
stage page sets, exact source slot pages, C/Swift layouts, paged copy-out, and
ASan/UBSan. A passing smoke is preparation evidence; it is not M26 gameplay
or visible-stage acceptance.
