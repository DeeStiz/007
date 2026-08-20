# Static frontend +Y/CCW capture rebaseline

Capture date: 2026-08-19.  The corrected source asset root is
`build/native/source-frontend-v6-image-decoder-v6` (GEFV internal SHA-256
`b1d7c7b536cd49aef3a605837855a33d4ff2e3529fb97761178488f2c9a1f44e`).
The audited projection uses positive clip-Y and the static capture renderers
explicitly use counter-clockwise front faces.  These are capture artifacts;
production projection/renderer/pipeline files were not changed in this lane.

## Accepted captures

- Legal: `build/native/legal-reference-capture-v6/y-ccw-b1d7-20260819-r3/`
  (`sourceVertexCoverageMatches=true`, `sourceSemanticClosure=true`, six
  draws, twelve triangles, five isolated materials, unsupported visible work
  zero).  Composite 320 raw SHA-256 is
  `4fa74f78044e652016c228456abcba6c8244a8795e458fe60f18c31a49623ae3` and
  Faithful HD raw SHA-256 is
  `ad8c2b3d1c88e37e4172f317d9989193061b20cb9f389947395441c362c08d43`.
- Nintendo: `build/native/nintendo-reference-capture-v6/y-ccw-b1d7-20260819-r2/`
  (42 nodes, 23 display lists, 821 source commands, 1363 vertices, 1018
  rendered triangles, three source degenerate sentinels, source-order hash
  `9cc62b913ce52e5b`, unsupported visible work zero).  The 320 even/odd raw
  hashes are `59265076ac93222c1b174d6ba46a02b8274b19c318d2de7c981d57f0ee9513ae`
  and `6d419c860aeb4aaf6e55f245a57fb5b0aa0b944fb2a0ce719cab4cd996eae7eb`.
- GoldenEye: `build/native/goldeneye-logo-reference-capture-v6/y-ccw-b1d7-20260819-r3/`
  (3 nodes, one display list, 162 commands, 438 vertices, 339 emitted
  triangles plus two zero-sentinel slots, two materials, seven mip levels,
  source-order hash `be5c050badae9682`, projection complete, unsupported
  visible work zero).  The 320 raw hash is
  `dd392bd78a5686b0f44ae5ccaaf3a60f8fb5c350d8933387323dde7281b0d827` and
  Faithful HD raw hash is
  `1624c1e6dd4c55766c43297b7076ced2df4daf2f3051af88168327a457c5926f`.
- Rareware: `build/native/rareware-reference-capture-v6/y-ccw-b1d7-20260819-r3/`
  (nine source display lists, 389 commands, 397 vertices, 268 triangles,
  six textures, four six-level mip chains, complete projection consumption,
  and unsupported visible work zero).  The front-facing source-timer-200
  320 raw SHA-256 is
  `cfe4dce6e56d933c8cfc61d8aafab9008e22060c206928752a9d55dbb78ac7bb`
  and Faithful HD raw SHA-256 is
  `75936812e86050bde5c848c58ce64a8b47f5648887131addbb817ce3901128b3`.
  The timer-20, 70, 200, and 260 phase captures and all six isolated material
  draws passed Metal API and shader validation.
- File Select and Mode Select: `build/native/file-mode-metal-reference-capture-v6/y-ccw-b1d7-20260819-r3/`.
  Metal API/shader validation passed; the four-wallet File Select and both
  Mode Select routes produced 320x240 and Faithful HD PNG/raw artifacts with
  source background rows, source wallet materials, text, cursor, Copy/Erase,
  dialog, previous-tab, and mode-selection evidence.  The semantic capture
  smoke reports 90 wallet nodes, 42 switch nodes, 43 switch records, 84
  textures, 186 mips, and unsupported visible work zero.

## Supersession boundary

The archived pre-fix outputs remain untouched.  The newly listed versioned
captures supersede them for the +Y/CCW static frontend baseline.  In
particular, GoldenEye closure12 remains available under
`build/native/goldeneye-logo-reference-capture-v6/closure12/`, but its old
320/HD raw hashes (`0c1f6794...` / `a5943b9f...`) are not the current
rebaseline.  Prior Nintendo, Legal, and File/Mode capture roots likewise
remain available and are evidence history only.

## Validation

Passed: Legal, Nintendo, GoldenEye, Rareware, and File/Mode Metal API and
shader-validation captures; source-scene strict/ASan/UBSan and current Metal
metallib validation; source 2D and compositor-independent reference capture;
+Y projection binding strict/ASan/UBSan and projection-consumption checks;
corrected catalog, texture setup, and texture-store checks.
