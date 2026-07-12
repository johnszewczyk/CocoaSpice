# Playback

## Formats

- Playback: SPC, NSF, NSFE, GBS, HES, KSS, AY, SAP, VGM, VGZ, GYM, S98, GSF, miniGSF, USF, and miniUSF files.
- Playback does not currently accept standard audio files such as MP3, AAC/M4A, ALAC, FLAC, or WAV.

## Playback Controls

- Controls: play, pause, stop, previous, and next.
- Controls: media keys and standard transport commands.
- Controls: rapid previous or next commands use the newest requested track.
- Playback: starts through a streamed audio path.
- Archives: supported game-music files can play from ZIP, 7z, and RSN containers; the selected member is materialized into the cache.
- USF archives: USF and miniUSF playback materializes the complete archive set so miniUSF dependency files remain available.
- Seeking: supports forward and backward movement.
- Audio output: resumes at the current position after an output-device change when playback was active.

## Timing

- Long Play: one shared setting for supported game-music formats.
- Timing: supports manual duration and fade behavior.

## Files

- [PlaybackEngine.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaybackEngine.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
