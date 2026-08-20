# VGMBoy Playback Integration

## Scope

- CocoaSpice's in-process connection to VGMBoyKit.

## Ownership

- VGMBoyKit owns format routing, decoder bridges, audio output, timing, Long Play, tempo, fade, and equalizer processing.
- CocoaSpice owns playlist membership, queue navigation, repeat/shuffle policy, database rows, archive materialization, UI, and macOS transport registration.

## Invariants

- `VGMBoyPlaybackEngine` is the only CocoaSpice playback façade and submits typed `PlaybackControlRequest` values to `PlaybackController`.
- `PlaybackControlSurface` is read once from the bundled controller and is the capability gate for CocoaSpice Audio-panel mappings. Volume and Mono submit their core requests through that one mapping point; no CocoaSpice audio DSP or alternative output path exists.
- CocoaSpice passes a materialized naked playable file path and its subtrack index to VGMBoy. Archive policy remains CocoaSpice-owned.
- CocoaSpice does not link its former decoder bridges or create an audio engine. Duplicate playback implementations are unsupported.
- Core status and natural-end events update CocoaSpice display state; CocoaSpice alone chooses the following queue item.
- The CocoaSpice equalizer UI maps directly to VGMBoy's ten 31 Hz–16 kHz bands, constrained to -12...+12 dB.
- CocoaSpice persists its chosen App Volume and Mono preferences, then reapplies them to a newly created bundled core. VGMBoy owns the actual attenuation and real-time channel downmix.
- `build.sh` packages VGMBoy's dynamic decoder requirements under `Contents/Frameworks`; SID uses the bundled `libsidplayfp.7.dylib` via `@executable_path`, never a runtime Homebrew path or a user-chosen core executable.

## Files

- [VGMBoyPlaybackEngine.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/VGMBoyPlaybackEngine.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
