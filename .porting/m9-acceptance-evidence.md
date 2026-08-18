# M9 First-Frame Acceptance Evidence

## Passing evidence

- `scripts/test_native_m1.sh`: C/Swift ABI, deterministic hash, wrong-thread,
  ASan/UBSan, and archive-symbol checks pass.
- `scripts/test_m7_gbi.sh`: C/Swift normalization, malformed/unsupported
  diagnostics, repeated packet/event hashes, and ASan/UBSan pass.
- `scripts/test_m3_input.sh`: keyboard edge/repeat/modifier/reset state pass.
- `scripts/test_host_sanitizers.sh`: isolated Swift/AppKit host ASan and UBSan
  builds each reached `initialized=1 ticks=60 shutdown=0` under a bounded run
  with no sanitizer diagnostics.
- M7 malformed-input coverage now includes `first_vertex=UINT32_MAX`; the
  parser rejects it without unsigned-addition overflow before copying vertices.
- `scripts/test_m3_gui_events.sh`: the AppKit responder path delivered a
  synthetic W key down/up with pressed/released masks and recorded the
  deactivate/activate attempt; this session did not emit OS focus notifications.
- HUD-enabled M8 runtime: `frames=60 draws=60 packetHash=1522029846112142469
  lastSignal=60 resourceAllocations=1`.
- Scripted resize: `resize=1 first=960x540 second=800x450 third=1024x576`.
- M5 synthetic lifecycle probe exercised `focusLost reset=1 paused=1` and
  `focusGained paused=0` while still retiring 60 clear frames; this is
  owner-loop pause evidence, not physical OS focus proof.
- Clean quit callback: `/tmp/goldeneye-m9-shutdown.log` reports `shutdown=1`.
- Metal validation/fault log scan produced no GPU fault, Metal validation error,
  or assertion-failure match.
- M8 actual-window screenshot is visually a colored triangle and has stable
  SHA-256 `9fef700b607853da79c154c28467b53d5c13d9cf1276ecb0b4539fc0e1e00265`.
- M8 trace `build/native/m8-triangle.gputrace` is 2.1 MB; static archive
  inspection finds the labeled frame, vertex buffer, render encoder, draw group,
  and MTL4 queue.
- Final bundle signing is Apple Development (`Apple Development: Derek Stiles
  (RWSPYS288D)`, Team ID `KV5KQJ3LLD`), and the executable Mach-O minimum is
  `27.0`, matching `LSMinimumSystemVersion=27.0`.
- `codesign --verify --deep --strict` and the designated requirement pass in the
  escalated build context; `spctl --assess` is rejected by this local trust
  environment, so distribution/Gatekeeper acceptance is not claimed.

## Incomplete external gates

- Final separate normal non-HUD host probe now produces a clean summary:
  `Process <GoldenEyeHost PID>: 0 leaks for 0 total leaked bytes.`
  The HUD-enabled runtime is terminated before this probe, so the evidence is
  scoped to the requested non-HUD process.
- A bounded `leaks --atExit -- /bin/sleep 1` control emits only MallocStackLogging
  warnings and no summary; the native host probe is the authoritative result for
  this goal.
- The earlier bounded xctrace fallback remains an unusable historical artifact;
  it is not used for the final leak claim because the direct non-HUD `leaks`
  report now succeeds.
- `gpudebug --list-devices` now succeeds after Developer Mode was enabled and
  identifies the local Apple M5 Max. M5 and M8 trace navigation/info inspection
  now succeeds: M5 shows one clear command buffer and a 960x540 BGRA8 drawable;
  M8 shows one command buffer, one render encoder, one triangle draw, the
  labeled M6 pipeline, vertex/fragment entry points, a 96-byte labeled vertex
  buffer, and the clear/store color attachment. Transcripts are in
  `build/native/m8-gpudebug.log` and `build/native/m5-gpudebug.log`.
- `gpudebug fetch` still encounters an XPC interruption while the replayer is
  loading, so resource extraction remains unavailable even though static draw
  tree and state inspection are now proven.
- `launchctl print gui/501/com.apple.gputoolsserviced` shows the daemon running
  but with `checked allocations reason = no host`; `launchctl` has no
  `com.apple.sysmond` job. This does not prevent the direct non-HUD `leaks`
  summary or static gpudebug inspection now that Developer Mode is enabled.
- Developer Mode is now enabled. The service was refreshed enough for static
  gpudebug inspection, but `gputoolsserviced` still reports `checked allocations
  reason = no host` for the separate leaks/task-port path.
- The M9 harness continues through HUD, resize, shutdown, and trace checks after
  the bounded leaks timeout; those checks pass and the shutdown log reports
  `shutdown=1`.
- M0 exact N64 byte match is now proven by the native Linux qemu-irix reference
  build; the detailed provenance is recorded in `.porting/m0-provenance.md`.

## Truth boundary

The native goal proves a development-signed AppKit/Metal 4 host, fixed-width
GoldenEye-style command normalization, one visible synthetic triangle, and the
captured/pixel-stable native path. It does not prove GoldenEye boots, N64 visual
parity, real asset rendering, gameplay, physical-device performance, or release
acceptance. The M0 exact-ROM gate must be resolved before marking the overall
goal complete.
