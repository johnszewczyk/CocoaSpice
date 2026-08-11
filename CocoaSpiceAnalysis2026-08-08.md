# CocoaSpice analysis — 2026-08-08

## Scope

Read-only handoff from the SPCBoy scanner and playback-speed pass. This is not
an implementation plan approval and does not change CocoaSpice behavior.

## Verified observations

### 1. The registry is the right capability boundary

`PlaybackFormatRegistry` already owns extension admission, decoder ownership,
scan descriptors, archive-materialization policy, subtrack enumeration, and
Long Play eligibility. Its static `PlaybackDecoderModule` entries are the
right place to add a small, explicit playback-speed capability rather than
adding backend-name checks to `PlayerViewModel` or scanner code.

Evidence:

- `Sources/CocoaSpice/App/GMEFormatSupport.swift`
- `Sources/CocoaSpice/App/PlaybackDecoderRouting.swift`
- `Sources/CocoaSpice/App/PlaybackTimingPolicy.swift`

### 2. SPC speed is a clean, narrow first candidate

The SPC-specific libgme registry entry is already distinct from the libgme
multi-track entry. This provides a natural capability boundary: expose speed
for `.spc` first, keep every other extension at normal speed, and only widen
the list after format-specific seek, duration, and PCM tests pass.

The inspected CocoaSpice sources did not expose a tempo/speed setting or a
`gme_set_tempo()` call. A safe implementation would:

1. Store speed as a reduced positive rational (`numerator`, `denominator`),
   accepting decimal and fractional UI input without storing a floating-point
   approximation.
2. Restrict the first UI and native capability to SPC, with a bounded range
   such as 1/4× through 4×.
3. Apply libgme tempo before the native playback session is primed.
4. Derive the displayed pre-fade duration and native play limit through
   integer-millisecond rational scaling. Keep the fade in output time.
5. Verify normal playback, 1/2×, 5/4×, seeking, Long Play, fades, and an
   archive-materialized SPC with real multi-chunk non-silent PCM.

This is intentionally a tempo feature, not an output-resampling feature.

### 3. libvgm has a separate, unexposed speed control

`Sources/CLibVGM/libvgm_bridge.cpp` currently assigns
`PlayerA::Config.pbSpeed = 1.0` in `libvgm_player_configure`. That makes VGM,
VGZ, GYM, and S98 a possible future speed experiment, but it is unrelated to
SPC and must not be grouped with it by default.

Before exposing it, measure whether `pbSpeed` preserves the intended pitch,
loop/end behavior, timing metadata, seek position, and native-session
readout. Add a backend-specific capability plus fixtures first.

### 4. vgmstream is not an SPC speed path

vgmstream handles streamed audio; it does not decode sequenced SPC music.
Its source-rate conversion must continue to make decoded streams play at the
correct pitch and duration. Do not relabel sample-rate override or a custom
resampler as generic playback speed without a format-specific contract and
tests.

### 5. 2sf2wav's command-line `--speed` is a curiosity, not a product API

`vendor/2sf2wav/main.cpp` accepts `--speed` by altering the player's sample
rate. That may be useful for diagnostics, but it needs a separate audition and
seek/pitch review before it can be considered a user-facing speed capability.
It should not inherit the SPC UI merely because it has a similarly named
option.

### 6. CocoaSpice would benefit from an external compatibility runner

CocoaSpice already has strong integration coverage and a central registry, but
the inspected surfaces did not reveal a user/CI-facing command that runs the
production discovery, archive materialization, routing, inspection, and PCM
health path against an arbitrary corpus without changing the persistent
library database.

The SPCBoy version is a useful model, not a copy target:

- use the real scan pipeline with an in-memory/ephemeral persistence adapter;
- accept one or more folders and emit text plus structured JSON;
- report typed outcomes by source, archive member, backend, and stage;
- add an opt-in PCM mode that decodes at least two consecutive bounded chunks
  for every subtrack and rejects empty or wholly silent output;
- keep regular user scans unchanged and never write the selected corpus into
  the user's library database.

This would make it much easier to validate new registry entries, archive
dependency behavior, and decoder upgrades against a real collection or CI
fixtures.

## Recommended implementation order

1. Add the external compatibility runner and small representative fixture
   roots. This provides the acceptance mechanism for every later decoder or
   timing change.
2. Add an SPC-only rational tempo capability to the registry, settings model,
   timing policy, native session, and Playback Options.
3. Use the runner plus manual audition to prove SPC playback at 1×, 1/2×, and
   5/4×, including an archive member and a seek while playing.
4. Evaluate libvgm `pbSpeed` separately. Do not enable vgmstream or 2SF speed
   based solely on their implementation details.

## Existing strengths to preserve

- The registry already prevents scanner/playlist/archive admission drift.
- The SPC and libgme-multitrack entries are separate, making a narrow initial
  capability feasible.
- The existing scan pipeline has structured timing and archive boundaries;
  an external runner should drive those boundaries, not duplicate them.
- CocoaSpice's native streamed output path should remain the playback
  authority. Decoder and tempo work must stay off real-time audio callbacks.

## Non-goals

- No claim that every libgme format, libvgm format, vgmstream format, or 2SF
  supports a safe user-facing speed feature.
- No generic pitch-preserving time-stretch proposal.
- No scanner/database rewrite, and no change to normal library scan behavior.
