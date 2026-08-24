# Playback

## Formats

- Supported formats: [supported-formats.md](/Users/john/Downloads/Code/VGMMan/CocoaSpice/ai/subsystem-human/supported-formats.md) lists every supported extension, archive container, and notable compatibility rule.
- Playback is provided by the bundled VGMBoy audio core.

## Playback Controls

- Controls: play, pause, stop, previous, and next.
- Controls: media keys and standard transport commands.
- Controls: Play and Pause are explicit desired states. Repeated Play after an output-device reconnect cannot toggle a resumed track back to Paused.
- Repeat: the toolbar cycles Off, Repeat Playlist, and Repeat Song.
- Controls: rapid previous or next commands use the newest requested track.
- Playback: starts through VGMBoy's shared audio session.
- Track changes: starting or skipping to another track makes a short clean output transition before
  the new track begins. The bundled audio endpoint stays ready between tracks, so CocoaSpice does
  not reopen the macOS device for each selection or pause.
- Archives: supported game-music files can play from ZIP, 7z, RSN, and TAR+Zstandard (`.tar.zst`/`.tzst`) containers; the selected member is materialized into the cache.
- Database playlists: choosing an item in the sidebar immediately publishes its stored source, archive-member, subtrack, and cached metadata rows. CocoaSpice does not rescan, inspect, extract, or write the catalog while hydrating that playlist.
- Format-specific decoding, dependency handling, subtrack behavior, and timing are owned by VGMBoyKit. CocoaSpice passes a materialized playable path and catalog subtrack index; it does not inspect decoder headers or tags.
- Seeking: supports forward and backward movement.
- Audio output: resumes at the current position after an output-device change when playback was active.
- Changing Long Play or its target while a supported track is active reapplies the native loop policy at the current playback position instead of restarting the track.
- Random playback has three toolbar states: off, random selection from the indexed library, and random selection from the current playlist. All three toolbar glyphs are native SF Symbols.
- Random Library queues the requested playback action while a small track-count-weighted library pool loads, so Next and end-of-track advance cannot race an empty asynchronous pool or require hydrating the entire indexed library.
- App Volume and Mono are applied by the bundled VGMBoy core. App Volume attenuates only CocoaSpice playback; Mono averages the rendered left and right channels and outputs that signal to both speakers.

## Timing

- Long Play: one shared setting for loop-capable game-music decoders, available in Playback Options and from the infinity button beside the main transport controls. Finite audio such as WAV, AIFF, FLAC, MP3, and M4A retains its native duration even when Long Play is on.
- Timing: supports manual duration and fade behavior.
- Tracks without decoder-provided timing, including SID music, use the configurable unknown-length default in the Long Play options area plus the configured end fade unless Long Play is enabled.
- End Fade: the shared six-second end fade is enabled by default and can be disabled in Playback Options.

## Files

- [VGMBoyPlaybackEngine.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/VGMBoyPlaybackEngine.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
