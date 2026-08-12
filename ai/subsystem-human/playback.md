# Playback

## Formats

- Supported formats: [supported-formats.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-human/supported-formats.md) lists every supported extension, archive container, and notable compatibility rule.
- Standard audio: AIFF, FLAC, M4A/AAC, MP3, and WAV use macOS audio support. Monkey's Audio APE uses the bundled FFmpeg decoder.

## Playback Controls

- Controls: play, pause, stop, previous, and next.
- Controls: media keys and standard transport commands.
- Controls: Play and Pause are explicit desired states. Repeated Play after an output-device reconnect cannot toggle a resumed track back to Paused.
- Repeat: the toolbar cycles Off, Repeat Playlist, and Repeat Song.
- Controls: rapid previous or next commands use the newest requested track.
- Playback: starts through a streamed audio path.
- Track changes: starting or skipping to another track clears prior decoded audio before the new track begins.
- Archives: supported game-music files can play from ZIP, 7z, RSN, and TAR+Zstandard (`.tar.zst`/`.tzst`) containers; the selected member is materialized into the cache.
- Library playlists: choosing an item in the sidebar reads its stored track list and metadata from the database. It does not reopen or extract files until playback starts.
- USF archives: USF and miniUSF playback materializes the complete archive set so miniUSF dependency files remain available.
- 2SF archives: 2SF and mini2SF playback materializes the complete archive set so mini2SF library dependencies remain available.
- PSF family: PSF, miniPSF, PSF2, and miniPSF2 use the vendored Play! PSF core. Archive playback materializes the complete set so `_lib` and PSFLIB dependencies resolve relative to the selected file; PSF tags provide scanner metadata and declared length.
- PlayStation XA: XA streams use vgmstream and expose embedded subsongs as separate playlist tracks when present.
- PlayStation 3 and PSP: MSF uses vgmstream as PlayStation 3 audio; shared ATRAC3 streams use vgmstream as PlayStation 3 / PSP audio.
- 3DO streams: AIFC, GENH, and NeuroDancer STREAM files use vgmstream and are identified as 3DO tracks.
- Seeking: supports forward and backward movement.
- Audio output: resumes at the current position after an output-device change when playback was active.
- Changing Long Play or its target while a supported track is active reapplies the native loop policy at the current playback position instead of restarting the track.
- Transitions: track changes, seek, pause/resume, stop, and Long Play changes briefly mute before the audio stream changes, then restore the chosen App Volume. Pause keeps the configured audio route alive at silence and preserves the exact buffered playback frame for resume. This reduces transport pops without changing system volume.
- Faded Skip: when enabled in Playback Options, the first Next or Previous keeps the live source playing through a six-second output fade, then advances. A second command advances immediately through the short transport mute.
- Random playback has three toolbar states: off, random selection from the indexed library, and random selection from the current playlist. All three toolbar glyphs are native SF Symbols.
- Random Library queues the requested playback action while a small track-count-weighted library pool loads, so Next and end-of-track advance cannot race an empty asynchronous pool or require hydrating the entire indexed library.

## Timing

- Long Play: one shared setting for loop-capable game-music decoders, available in Playback Options and from the infinity button beside the main transport controls. Finite audio such as WAV, AIFF, FLAC, MP3, and M4A retains its native duration even when Long Play is on.
- Timing: supports manual duration and fade behavior.
- End Fade: the shared six-second end fade is enabled by default and can be disabled in Playback Options.

## Files

- [PlaybackEngine.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaybackEngine.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
