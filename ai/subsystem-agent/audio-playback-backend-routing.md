# VGMBoy Playback Integration

## Scope

- CocoaSpice's in-process connection to VGMBoyKit.

## Ownership

- VGMBoyKit owns format routing, decoder bridges, audio output, timing, Long Play, tempo, fade, and equalizer processing.
- CocoaSpice owns playlist membership, queue navigation, repeat/shuffle policy, database rows, archive materialization, UI, and macOS transport registration.

## Invariants

- `VGMBoyPlaybackEngine` is the only CocoaSpice playback façade and submits typed `PlaybackControlRequest` values to `PlaybackController`.
- CocoaSpice passes a materialized naked playable file path and its subtrack index to VGMBoy. Archive policy remains CocoaSpice-owned.
- CocoaSpice does not link its former decoder bridges or create an audio engine. Duplicate playback implementations are unsupported.
- Core status and natural-end events update CocoaSpice display state; CocoaSpice alone chooses the following queue item.
- The CocoaSpice equalizer UI maps directly to VGMBoy's ten 31 Hz–16 kHz bands, constrained to -12...+12 dB.

## Files

- [VGMBoyPlaybackEngine.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/VGMBoyPlaybackEngine.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
