# Playback

## Formats

- Playback: SPC, NSF, NSFE, GBS, HES, KSS, AY, SAP, VGM, VGZ, GYM, S98, GSF, miniGSF, USF, miniUSF, 2SF, mini2SF, PSF2, miniPSF2, ADX, SS2, MIB, MTAF, VAG, SVAG, IECS, and related vgmstream formats.
- Playback does not currently accept standard audio files such as MP3, AAC/M4A, ALAC, FLAC, or WAV.

## Playback Controls

- Controls: play, pause, stop, previous, and next.
- Controls: media keys and standard transport commands.
- Repeat: the toolbar cycles Off, Repeat Playlist, and Repeat Song.
- Controls: rapid previous or next commands use the newest requested track.
- Playback: starts through a streamed audio path.
- Archives: supported game-music files can play from ZIP, 7z, and RSN containers; the selected member is materialized into the cache.
- USF archives: USF and miniUSF playback materializes the complete archive set so miniUSF dependency files remain available.
- 2SF archives: 2SF and mini2SF playback materializes the complete archive set so mini2SF library dependencies remain available.
- PSF2: PSF2 and miniPSF2 use the vendored Play! PSF core. Archive playback materializes the complete set so `_lib` dependencies resolve relative to the selected file; PSF tags provide scanner metadata and declared length.
- Seeking: supports forward and backward movement.
- Audio output: resumes at the current position after an output-device change when playback was active.
- Random playback has three toolbar states: off, random selection from the indexed library, and random selection from the currently visible playlist view.

## Timing

- Long Play: one shared setting for supported game-music formats.
- Timing: supports manual duration and fade behavior.

## Files

- [PlaybackEngine.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaybackEngine.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
