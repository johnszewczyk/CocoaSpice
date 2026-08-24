# VGMBoy Playback Integration

## Scope

- CocoaSpice's in-process connection to VGMBoyKit.

## Ownership

- VGMBoyKit owns format routing, decoder bridges, audio output, timing, Long Play, tempo, fade, and equalizer processing.
- CocoaSpice owns playlist membership, queue navigation, repeat/shuffle policy, database rows, archive materialization, UI, and macOS transport registration.
- CocoaSpice owns the remembered AAC destination and the playlist context-menu action; VGMBoy owns
  the offline AAC render once CocoaSpice has materialized an archive member to a naked playable file.

## Invariants

- `VGMBoyPlaybackEngine` is the only CocoaSpice playback façade and submits typed `PlaybackControlRequest` values to `PlaybackController`.
- `PlaybackControlSurface` is read once from the bundled controller and is the capability gate for CocoaSpice Audio-panel mappings. Volume and Mono submit their core requests through that one mapping point; no CocoaSpice audio DSP or alternative output path exists.
- CocoaSpice passes a materialized naked playable file path and its subtrack index to VGMBoy. Archive policy remains CocoaSpice-owned.
- `VGMBoyPlaybackEngine` builds the shared `PlaybackTimingRequest` from the selected path and
  Long Play state. Ordinary file-default timing sends no play length, so VGMBoy derives the
  natural window from decoder metadata. Long Play alone supplies the manual duration; a catalog
  duration remains a display/queue fact and is not authoritative for the core's finite playback
  cap.
- CocoaSpice does not submit a missing-length timed request. The core's bounded safety value is
  for unknown-duration/timed operations, not ordinary FLAC, WAV, or other finite audio.
- CocoaSpice's persisted manual duration is the Long Play target. It is not currently sent as a
  replacement for VGMBoyKit's fixed unknown-duration safety value when Long Play is off.
- AAC export passes the playlist display name and the already-effective finite playback timing to
  `PlaybackController.exportAAC`. CocoaSpice never gives VGMBoy catalog access or asks it to derive
  a title; VGMBoy performs filename sanitation and no-overwrite collision handling.
- CocoaSpice does not link its former decoder bridges or create an audio engine. Duplicate playback implementations are unsupported.
- CocoaSpice is not the owner of ScanSong's vgmstream or Highly Complete inspection plugins. Those
  executables are built and handed off by VGMBoy; CocoaSpice only provides the shared upstream
  source/build inputs used by the app family.
- Core status and natural-end events update CocoaSpice display state; CocoaSpice alone chooses the following queue item.
- VGMBoy retains one silent initialized macOS output endpoint for the host lifetime. CocoaSpice
  must express pause, replacement, seek, and completion only through the typed core controls; it
  must not stop/recreate a separate device path around those transitions.
- The CocoaSpice equalizer UI maps directly to VGMBoy's ten 31 Hz–16 kHz bands, constrained to -12...+12 dB.
- The libgme and libvgm Play Speed controls persist frontend preferences but submit only the shared `PlaybackTempo` value through VGMBoy's typed `set_tempo` command. Non-tempo decoder families always receive the default multiplier.
- CocoaSpice persists its chosen App Volume and Mono preferences, then reapplies them to a newly created bundled core. VGMBoy owns the actual attenuation and real-time channel downmix.
- `build.sh` packages VGMBoy's dynamic decoder requirements under `Contents/Frameworks`; SID uses the bundled `libsidplayfp.7.dylib` via `@executable_path`, never a runtime Homebrew path or a user-chosen core executable.

## Files

- [VGMBoyPlaybackEngine.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/VGMBoyPlaybackEngine.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
