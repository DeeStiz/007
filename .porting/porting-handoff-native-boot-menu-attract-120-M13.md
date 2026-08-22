# Native Boot/Menu/Attract/120 Hz — Native Synth Handoff (M13)

## What was done

M13 native synthesis is complete for the bounded source contract. The V5 C
engine renders guarded compact sequences and AL-bank waves at 22,050 Hz with
fixed-point voices, envelopes, loops, pitch, pan, and gain. The explicit V6
effects sidecar adds Small/Big Room reverb and a bounded composite SFX graph,
including bank-backed title SFX IDs. Effects are owner-side and deterministic;
the realtime audio callback remains a separate M14 ring/source-node contract.

## Ground-truth validation

- `bash scripts/test_audio_engine_v5.sh build/native/boot-assets/audio` — PASS
  strict/ASan/UBSan: `division=384`, `tracks=13`, `wave_samples=8464`,
  `frames=4096`, `events=27`, PCM hash `7358868759095366475`.
- `bash scripts/test_audio_effects_v6.sh build/native/boot-assets/audio` —
  PASS strict/ASan/UBSan/Release: boot hash `7358868759095366475`, graph hash
  `10304920864406538052`, reverb hash `6148009325550816421`, active voices `4`.
- `bash scripts/test_audio_long_soak_v5.sh build/native/boot-assets/audio` —
  PASS strict/ASan/UBSan: `600` seconds, `72,000` ticks, `13,230,000` frames,
  PCM hash `14458218251061804860`, zero underruns/drops, producer tick `71999`.
- `bash scripts/test_source_audio_binding_v6.sh build/native/boot-assets/audio`
  — PASS.
- `bash scripts/test_title_sfx.sh` — PASS all nine guarded title/menu SFX IDs
  with combined hash `9686333082073475502`.
- The expanded source-audio binding smoke now accepts all nine guarded menu/
  title IDs `18,77,79,111,118,197,199,222,258`, rejects duplicates per
  sidecar session, preserves independent frontend/menu sequence cursors, and
  resets the menu cursor on both active and inactive game resets.
  The expanded C title-SFX bank smoke passes with combined hash
  `9686333082073475502`.
- The signed Release rebuilt after this forwarding change is executable hash
  `85a7c8f86abbba1709e30f5cc4689bf6ce1a59a22c941657729b1c1e262cd916` with
  the external-ROM provenance gate passing; live AVAudio output remains
  unverified in the login-window session.
- `bash scripts/test_audio_output_v5.sh` now reports strict/ASan/UBSan C
  output PASS and an explicit AVAudioSourceNode route status; the current run
  passes the adapter (`ticks=8`, `preroll=367`, `underruns=0`). The harness
  still classifies a known unavailable audio route as SKIP rather than hiding
  it.

## Evidence boundary and deferred work

- The frozen V5 `ge_audio_feature_status_v5` API continues to report its legacy
  M13 STUB values for compatibility. The owner-side production path uses the
  explicit V6 effects contract and does not silently reinterpret those calls.
- The V6 composite-SFX graph remains validated offline and is still separate
  from the production V5 source-node mix. The owner-side `ScheduledSFX` queue
  already provides exact sample-indexed overlap; the offline graph lacks a
  streaming cursor, equivalent wave-end semantics, prepared-bank caching, and
  persistent post-mix reverb, so integrating it here would weaken source
  fidelity. File/Mode sidecar SFX events are now forwarded through a separate
  `GoldenEyeSourceAudioBindingV6` namespace so menu sequence numbers cannot
  suppress frontend events; production still renders individual V5 SFX plus
  Small Room reverb.
- Full source mix/reverb tuning, exact N64 DSP parity, and live AVAudio A/V
  synchronization remain open. No live hardware audio acceptance is inferred
  from deterministic PCM or synthetic long-soak evidence.

## Watch for next milestone

- Keep all realtime callback work allocation-free, lock-free, and free of Swift
  calls/logging; owner-side V6 effects may allocate only outside the callback.
- Preserve the heap-backed `GEAudioReverbBusV6` storage in
  `native_audio_service.swift`; stack materialization previously exhausted the
  owner thread.
- M14 output validation must cover route recovery, preroll/refill, source-node
  sample origin, and physical audio timing separately from synth hashes.

## Reproduction

```sh
cd /Users/derek/Developer/goldeneye-swift
bash scripts/test_audio_engine_v5.sh build/native/boot-assets/audio
bash scripts/test_audio_effects_v6.sh build/native/boot-assets/audio
bash scripts/test_audio_long_soak_v5.sh build/native/boot-assets/audio
bash scripts/test_source_audio_binding_v6.sh build/native/boot-assets/audio
bash scripts/test_title_sfx.sh
```

No commit, push, branch, reset, clean, or external-ROM bundling was performed.
