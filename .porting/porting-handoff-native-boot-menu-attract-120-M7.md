# Native Boot/Menu/Attract/120 Hz — Model/Node Ingestion Handoff (M7)

## What was done

M7 model/node ingestion is complete for the bounded source graph. The value-only
GESM runtime now exposes a typed `GoldenEyeSourceModelV6.NodeKind` view for the
source ModelNode opcode handles, and graph traversal consumes that view rather
than maintaining a second raw-hash switch table. The source-model smoke rejects
unknown node families and asserts the complete bounded M7 family set. Existing
GETN title packets remain unchanged and continue to load through the title
route.

## Ground-truth validation

- `bash scripts/test_source_model_v6.sh build/native/source-frontend-v6` — PASS
  strict/ASan/UBSan. Eight GESM sidecars retain 225 nodes, 225 scalar records,
  and deterministic packet hashes. Node-family counts are:
  `group=19, groupSimple=1, bbox=20, displayList=71,
  displayListCollision=28, bsp=18, switchNode=42, lod=22, shadow=1,
  head=1, gunfire=1, header=1`; all nine required M7 families are present.
- `bash scripts/test_native_source_frontend_v6.sh` — PASS. The 1,517-record
  GEFV and all eight GESM sidecars pass generation, bounds, hash, and tamper
  rejection checks.
- `bash scripts/test_native_title_nodes.sh` — PASS. Four GETN packets retain
  `138` nodes and `92` texture metadata rows with deterministic hashes.
- `bash scripts/test_source_frontend_catalog_v6.sh build/native/source-frontend-v6`
  — PASS, including packet/hash/path/bounds/unknown-field negative cases.
- `bash scripts/test_title_route_v5.sh` — PASS strict/ASan/UBSan and Swift
  route integration (`cast=34`, `demos=14`).
- `bash scripts/test_m7_gbi.sh` — PASS; the frozen classic GBI hash remains
  `1522029846112142469`.
- `swift build --disable-sandbox --configuration debug` — PASS.

No source pointers, segmented addresses, raw Gfx, or mutable object graphs cross
the Swift boundary. `git diff --check` passes.

## Deferred work

- Full display-list/material/texture consumption remains in M8–M10; this handoff
  does not promote GETU or dynamic skeletal sidecars to default rendering.
- `rarewarelogo`, `headbrosnansuit`, `suitbond`, and `chrwppk` continue to emit
  typed dynamic-dependency diagnostics until their M8–M10 material/animation/
  attachment contracts are complete. No fallback scene is produced.
- Physical Metal 4 supplied-drawable capture, sustained presentation cadence,
  and stage character/effect/AI closure remain open under later milestones.

## Watch for next milestone

- Preserve the typed node-family mapping and fail-closed unknown-opcode behavior
  when adding texture/material lowering.
- Keep packet hashes and the frozen M7 GBI ABI unchanged.
- M8 work will need the Metal 4 resource, texture upload, validation, capture,
  and GPU-debug skills before touching renderer consumption.

## Reproduction

```sh
cd /Users/derek/Developer/goldeneye-swift
bash scripts/test_source_model_v6.sh build/native/source-frontend-v6
bash scripts/test_native_source_frontend_v6.sh
bash scripts/test_native_title_nodes.sh
bash scripts/test_source_frontend_catalog_v6.sh build/native/source-frontend-v6
bash scripts/test_title_route_v5.sh
bash scripts/test_m7_gbi.sh
```

No commit, push, branch, reset, clean, or external-ROM bundling was performed.
