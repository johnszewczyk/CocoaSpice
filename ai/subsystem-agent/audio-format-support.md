# Audio Format Support

## Scope

This is the current admission matrix for file discovery, database scanning, playlist intake, and playback. An extension is supported only when it appears in the central decoder registry.

## Supported Audio Formats

| Decoder backend | Extensions | Archive handling |
| --- | --- | --- |
| `libgme` | `ay`, `gbs`, `hes`, `kss`, `nsf`, `nsfe`, `sap`, `spc` | Supported member is inspected or materialized from a supported archive through the same decoder metadata path used for playback. |
| `libopenmpt` | `xm` | XM modules are independently playable, scan through native tracker metadata, and materialize only the selected archive member. |
| Core Audio | `flac`, `wav` | Native standard-audio decoding with PCM output, seeking, duration inspection, direct-file scanning, drag/drop, and selected-member archive materialization. |
| `libvgm` | `gym`, `s98`, `vgm`, `vgz` | Supported member is inspected or materialized from a supported archive. VGZ input is gzip-inflated before decoder intake. |
| Highly Complete | `gsf`, `minigsf` | Archive-backed playback materializes the complete archive set, preserving miniGSF library dependencies. |
| `lazyusf2` | `usf`, `miniusf` | Playback materializes the complete archive set, preserving miniUSF dependency files. Deep Scan reads the member's PSF tag footer and only materializes selected playable files. |
| `2sf2wav` | `2sf`, `mini2sf` | Playback materializes the complete archive set, preserving archive-relative 2SF libraries. Deep Scan reads PSF tags directly from selected members. |
| `vgmstream` | `adx`, `ads`, `aifc`, `aus`, `genh`, `hd`, `hbd`, `iecs`, `int`, `mib`, `mtaf`, `rws`, `ss2`, `stream`, `svag`, `vag`, `xa` | Native PlayStation XA, 3DO AIFC/GENH/STREAM, and PlayStation 2/game-audio streams and banks. Deep scans open the decoder for subsongs, stream length, loop metadata, and format names; archive members are materialized before inspection/playback. Playback is finite by default; Long Play reopens in forced-loop/play-forever mode while the shared app plan retains the finite manual stop and fade. |
| `Play! PSF` | `psf`, `minipsf` | Native PlayStation PSF emulator playback through the UI-free vendored Play! `PsfCore` bridge. Playback fully materializes sibling `_lib` and PSFLIB dependencies; Deep Scan reads `[TAG]` metadata from selected members. |
| `Play! PSF2` | `psf2`, `minipsf2` | Native PlayStation 2 PSF emulator playback through the same Play! bridge and complete-set playback policy; Deep Scan uses selected-member `[TAG]` metadata. |

## Supported Containers

`zip`, `7z`, `rsn`, `tar.zst`, and `tzst` are accepted as containers when they hold one of the supported audio formats above. TAR+Zstandard members are decompressed by `zstd` before `tar` lists or extracts them; ZIP member discovery uses 7-Zip's own path representation so legacy-encoded member names can be extracted consistently. A container itself is not a playable format.

## Not Currently Admitted

Every extension absent from `GMEFormatSupport.supportedExtensions` is unsupported by discovery, database scanning, playlist intake, and playback. This includes standard audio formats such as APE, MP3, AAC/M4A, and ALAC. AAC export support does not add AAC playback support.

## Implementation Rules

- `GMEFormatSupport` is the source of truth for extension admission and backend routing.
- Each registered backend declares whether its files require eager subtrack enumeration. Single-track formats can enter a playlist before metadata hydration; multi-track formats are inspected before their rows are finalized.
- The registration declares playback and scan materialization separately. Scan-only metadata shortcuts may use selected members, but playback must retain the full dependency policy and LazyUSF alias preparation.
- Adding a format requires a decoder module or an explicit extension registration, plus compatible inspection and playback paths.
- Archive support must be validated for the format's dependency model. Formats with sibling or library dependencies cannot use selected-member-only materialization.
- PSFLIB files are dependency resources for PSF tracks and are not admitted as independent playlist or library rows.

## Files

- [GMEFormatSupport.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/GMEFormatSupport.swift)
- [PlaybackDecoderRouting.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaybackDecoderRouting.swift)
- [ZipArchiveSupport.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/ZipArchiveSupport.swift)
- [audio-playback-backend-routing.md](/Users/john/Downloads/Code/CocoaSpice/ai/subsystem-agent/audio-playback-backend-routing.md)
