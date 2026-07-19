# Audio Format Support

## Scope

This is the current admission matrix for file discovery, database scanning, playlist intake, and playback. An extension is supported only when it appears in the central decoder registry.

## Supported Audio Formats

| Decoder backend | Extensions | Archive handling |
| --- | --- | --- |
| `libgme` | `ay`, `gbs`, `hes`, `kss`, `nsf`, `nsfe`, `sap`, `spc` | Supported member is inspected or materialized from a supported archive through the same decoder metadata path used for playback. |
| `libvgm` | `gym`, `s98`, `vgm`, `vgz` | Supported member is inspected or materialized from a supported archive. VGZ input is gzip-inflated before decoder intake. |
| Highly Complete | `gsf`, `minigsf` | Archive-backed playback materializes the complete archive set, preserving miniGSF library dependencies. |
| `lazyusf2` | `usf`, `miniusf` | Archive-backed playback and scanning materialize the complete archive set, preserving miniUSF dependency files. |
| `2sf2wav` | `2sf`, `mini2sf` | Archive-backed playback materializes the complete archive set, preserving archive-relative 2SF libraries. Metadata scanning reads PSF tags directly. |
| `vgmstream` | `adx`, `ads`, `aus`, `hd`, `hbd`, `iecs`, `int`, `mib`, `mtaf`, `rws`, `ss2`, `svag`, `vag`, `xa` | Native PlayStation XA and PlayStation 2/game-audio streams and banks. Deep scans open the decoder for subsongs, stream length, loop metadata, and format names; archive members are materialized before inspection/playback. Playback is finite by default; Long Play reopens in forced-loop/play-forever mode while the shared app plan retains the finite manual stop and fade. |
| `Play! PSF` | `psf`, `minipsf` | Native PlayStation PSF emulator playback through the UI-free vendored Play! `PsfCore` bridge. Full archive materialization preserves sibling `_lib` and PSFLIB dependencies; tags and declared length are available to deep scans. |
| `Play! PSF2` | `psf2`, `minipsf2` | Native PlayStation 2 PSF emulator playback through the same Play! bridge and complete-set archive policy. |

## Supported Containers

`zip`, `7z`, and `rsn` are accepted as containers when they hold one of the supported audio formats above. ZIP member discovery uses 7-Zip's own path representation so legacy-encoded member names can be extracted consistently. A container itself is not a playable format.

## Not Currently Admitted

Every extension absent from `GMEFormatSupport.supportedExtensions` is unsupported by discovery, database scanning, playlist intake, and playback. This includes standard audio formats such as MP3, AAC/M4A, ALAC, FLAC, and WAV. AAC export support does not add AAC playback support.

## Implementation Rules

- `GMEFormatSupport` is the source of truth for extension admission and backend routing.
- Each registered backend declares whether its files require eager subtrack enumeration. Single-track formats can enter a playlist before metadata hydration; multi-track formats are inspected before their rows are finalized.
- The same registration declares selected-member versus complete-set archive materialization, including the LazyUSF alias preparation policy required after complete-set extraction.
- Adding a format requires a decoder module or an explicit extension registration, plus compatible inspection and playback paths.
- Archive support must be validated for the format's dependency model. Formats with sibling or library dependencies cannot use selected-member-only materialization.
- PSFLIB files are dependency resources for PSF tracks and are not admitted as independent playlist or library rows.

## Files

- [GMEFormatSupport.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/GMEFormatSupport.swift)
- [PlaybackDecoderRouting.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaybackDecoderRouting.swift)
- [ZipArchiveSupport.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/ZipArchiveSupport.swift)
- [audio-playback-backend-routing.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/audio-playback-backend-routing.md)
