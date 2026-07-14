# Audio Format Support

## Scope

This is the current admission matrix for file discovery, database scanning, playlist intake, and playback. An extension is supported only when it appears in the central decoder registry.

## Supported Audio Formats

| Decoder backend | Extensions | Archive handling |
| --- | --- | --- |
| `libgme` | `ay`, `gbs`, `hes`, `kss`, `nsf`, `nsfe`, `sap`, `spc` | Supported member is inspected or materialized from a supported archive. SPC metadata scanning uses its header path. |
| `libvgm` | `gym`, `s98`, `vgm`, `vgz` | Supported member is inspected or materialized from a supported archive. VGZ input is gzip-inflated before decoder intake. |
| Highly Complete | `gsf`, `minigsf` | Archive-backed playback materializes the complete archive set, preserving miniGSF library dependencies. |
| `lazyusf2` | `usf`, `miniusf` | Archive-backed playback and scanning materialize the complete archive set, preserving miniUSF dependency files. |
| `2sf2wav` | `2sf`, `mini2sf` | Archive-backed playback materializes the complete archive set, preserving archive-relative 2SF libraries. Metadata scanning reads PSF tags directly. |

## Supported Containers

`zip`, `7z`, and `rsn` are accepted as containers when they hold one of the supported audio formats above. ZIP member discovery uses 7-Zip's own path representation so legacy-encoded member names can be extracted consistently. A container itself is not a playable format.

## Not Currently Admitted

Every extension absent from `GMEFormatSupport.supportedExtensions` is unsupported by discovery, database scanning, playlist intake, and playback. This includes standard audio formats such as MP3, AAC/M4A, ALAC, FLAC, and WAV. AAC export support does not add AAC playback support.

## Implementation Rules

- `GMEFormatSupport` is the source of truth for extension admission and backend routing.
- Adding a format requires a decoder module or an explicit extension registration, plus compatible inspection and playback paths.
- Archive support must be validated for the format's dependency model. Formats with sibling or library dependencies cannot use selected-member-only materialization.

## Primary Files

- [GMEFormatSupport.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/GMEFormatSupport.swift)
- [PlaybackDecoderRouting.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaybackDecoderRouting.swift)
- [ZipArchiveSupport.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/ZipArchiveSupport.swift)
- [audio-playback-backend-routing.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/audio-playback-backend-routing.md)
