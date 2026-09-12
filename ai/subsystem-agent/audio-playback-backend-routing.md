# VGMBoy Playback Integration

## Scope

- CocoaSpice's in-process connection to VGMBoyKit.

## Ownership

- VGMBoyKit owns format routing, decoder bridges, audio output, timing, Long Play, tempo, fade, and equalizer processing.
- CocoaSpice owns playlist membership, queue navigation, repeat/shuffle policy,
  database rows, archive source identity/cache presentation, UI, and macOS
  transport registration. `FrontendCore.ArchivePlaybackMaterializer` owns the
  shared selected-entry/complete-set materialization orchestration and
  dependency preparation used by both CocoaSpice and SPCBoyWK; CocoaSpice does
  not access decoder implementations.
- CocoaSpice owns the remembered AAC destination and the playlist context-menu
  action; the shared intake produces a naked playable file and VGMBoy owns the
  offline AAC render.

## Invariants

- `VGMBoyKit.FormatRegistry.playbackDescriptors` is the complete frontend capability projection.
  CocoaSpice's `PlaybackFormatRegistry` is only an archive-admission adapter and must not rebuild
  extension unions, backend IDs, Long Play, tempo, or natural-ending flags.
- `VGMBoyKit.PlaybackPreferences` owns timing, fade, EQ, volume, mono, and native-tempo
  normalization. `AppSessionPersistence` retains CocoaSpice's UserDefaults keys and legacy-shape
  compatibility while passing values through that shared semantic model.

- `FrontendCore.PlaybackTransportCore.PlaybackTransportCoordinator` is the
  shared native playback façade. It owns the serialized `PlaybackController`,
  newest-request token, loaded naked-file identity, timing reconfiguration,
  output controls, status, diagnostics, and the generation-checked one-shot
  natural-end event.
- CocoaSpice's `VGMBoyPlaybackEngine` is only a TrackItem/archive-materializer
  adapter around that coordinator. SPCBoyWK's `WKPlaybackBridge` is only a
  JSON request adapter around the same coordinator. Neither frontend owns a
  second controller or serial executor.
- `VGMBoyPlaybackEngine` retains its frontend `TrackItem` snapshot behind a
  lock because async playback requests and transport callbacks use different
  executors. Callback identity comes from the coordinator's queue-confined
  string ID; callbacks must not read the adapter's mutable TrackItem.
- `PlaybackRequestCore.PlaybackRequestLifecycle` owns newest-request
  invalidation for CocoaSpice's frontend playback request. Its
  `PlaybackRequestState` adapter retains only the pending `TrackItem` and
  presentation-facing end state. Queue identity and completion target policy
  live in `PlaybackQueueCore`; CocoaSpice retains only native model mapping and
  presentation state. Native transport request invalidation is shared and occurs
  before a stop or replacement can race a start.
- `PlaybackControlSurface` is read by the shared coordinator and is the
  capability gate for frontend Audio-panel mappings. Volume, Mono, EQ, timing,
  and transport commands all reach VGMBoy through that one mapping point; no
  frontend audio DSP or alternative output path exists.
- CocoaSpice passes a materialized naked playable file path and its subtrack
  index to VGMBoy. The format-owned materialization requirement comes from
  `VGMBoyKit.FormatRegistry`; `FrontendCore.ArchivePlaybackMaterializer`
  owns cache identity, warm-hit behavior, atomic staging, completion markers,
  limit enforcement, dependency preparation, playable-output validation, and
  cache-lease activation. CocoaSpice supplies only cache preferences and
  catalog/playback presentation around that shared result.
- `PlaybackTransportCoordinator` builds the shared `PlaybackTimingRequest` from the selected path and
  Long Play state. Ordinary file-default timing sends no play length, so VGMBoy derives the
  natural window from decoder metadata. Long Play alone supplies the manual duration; a catalog
  duration remains a display/queue fact and is not authoritative for the core's finite playback
  cap.
- CocoaSpice does not submit a missing-length timed request. The core's bounded safety value is
  for unknown-duration/timed operations, not ordinary FLAC, WAV, or other finite audio.
- Database playlist hydration is shared CatalogReader work. CocoaSpice adapts the returned catalog
  rows into native queue models but does not retain duplicate source, folder, or path SQL.
- CocoaSpice persists separate Long Play and unknown-duration values. The latter is sent through
  the shared typed request and applies only when the decoder provides no natural duration.
- AAC export passes the playlist display name and the already-effective finite playback timing to
  `PlaybackTransportCoordinator`, which calls `PlaybackController.exportAAC`.
  CocoaSpice never gives VGMBoy catalog access or asks it to derive
  a title; VGMBoy performs filename sanitation and no-overwrite collision handling. CocoaSpice shows
  native render progress in its status bar and sends Abort through the shared cancellation token;
  VGMBoy removes the unfinished partial file before it returns cancellation.
- CocoaSpice does not link its former decoder bridges or create an audio engine. Duplicate playback implementations are unsupported.
- CocoaSpice is not the owner of ScanSong's vgmstream or Highly Complete inspection plugins. Those
  executables are built and handed off by VGMBoy; CocoaSpice only provides the shared upstream
  source/build inputs used by the app family.
- Core status updates CocoaSpice display state, while the coordinator's
  one-shot natural-end event returns the shared completion target. CocoaSpice
  maps that stable ID into its native queue model and retains only frontend-local
  random choice and presentation handoff; the shared core prevents duplicate or
  stale completion delivery.
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
