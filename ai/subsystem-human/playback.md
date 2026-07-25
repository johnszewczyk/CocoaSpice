# Playback

## Formats

- Playback: WAV, FLAC, SPC, NSF, NSFE, GBS, HES, KSS, AY, SAP, XM, VGM, VGZ, GYM, S98, GSF, miniGSF, USF, miniUSF, 2SF, mini2SF, PSF, miniPSF, PSF2, miniPSF2, XA, AIFC, GENH, STREAM, ADX, SS2, MIB, MTAF, VAG, SVAG, IECS, and related vgmstream formats.
- Playback does not currently accept other standard audio files such as Monkey's Audio APE, MP3, AAC/M4A, or ALAC.

## Playback Controls

- Controls: play, pause, stop, previous, and next.
- Controls: media keys and standard transport commands.
- Repeat: the toolbar cycles Off, Repeat Playlist, and Repeat Song.
- Controls: rapid previous or next commands use the newest requested track.
- Playback: starts through a streamed audio path.
- Archives: supported game-music files can play from ZIP, 7z, RSN, and TAR+Zstandard (`.tar.zst`/`.tzst`) containers; the selected member is materialized into the cache.
- USF archives: USF and miniUSF playback materializes the complete archive set so miniUSF dependency files remain available.
- 2SF archives: 2SF and mini2SF playback materializes the complete archive set so mini2SF library dependencies remain available.
- PSF family: PSF, miniPSF, PSF2, and miniPSF2 use the vendored Play! PSF core. Archive playback materializes the complete set so `_lib` and PSFLIB dependencies resolve relative to the selected file; PSF tags provide scanner metadata and declared length.
- PlayStation XA: XA streams use vgmstream and expose embedded subsongs as separate playlist tracks when present.
- 3DO streams: AIFC, GENH, and NeuroDancer STREAM files use vgmstream and are identified as 3DO tracks.
- Seeking: supports forward and backward movement.
- Audio output: resumes at the current position after an output-device change when playback was active.
- Random playback has three toolbar states: off, random selection from the indexed library, and random selection from the current playlist. All three toolbar glyphs are native SF Symbols.
- Random Library queues the requested playback action while a small track-count-weighted library pool loads, so Next and end-of-track advance cannot race an empty asynchronous pool or require hydrating the entire indexed library.

## Timing

- Long Play: one shared setting for supported game-music formats, available in Playback Options and from the infinity button beside the main transport controls.
- Timing: supports manual duration and fade behavior.

## Files

- [PlaybackEngine.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaybackEngine.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
