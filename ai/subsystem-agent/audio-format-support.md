# Audio Format Support

## Scope

This is the current admission matrix for file discovery, database scanning, playlist intake, and playback. An extension is supported only when it appears in the central decoder registry.

## Supported Audio Formats

| Decoder backend | Extensions | Archive handling |
| --- | --- | --- |
| `libgme` | `ay`, `gbs`, `hes`, `kss`, `nsf`, `nsfe`, `sap`, `spc` | Supported member is inspected or materialized from a supported archive through the same decoder metadata path used for playback. |
| `libopenmpt` | `xm` | XM modules are independently playable, scan through native tracker metadata, and materialize only the selected archive member. |
| Core Audio | `aif`, `aiff`, `flac`, `m4a`, `mp3`, `wav` | Native standard-audio decoding with PCM output, seeking, duration inspection, direct-file scanning, drag/drop, and selected-member archive materialization. These finite containers retain their native duration and never use Long Play. `.m4a` includes verified AAC output. Raw `.aac` admission awaits a fixture-backed decoder check. Archive `.m3u` members are dependency manifests: their supported sibling members are queued in declared order. Nintendo DS SWAV payloads mislabeled `.wav` are sniffed by header and sent to vgmstream instead. The known DS `_22.wav` headerless layout is recognized by its filename, no RIFF/SWAV header, and a minimum raw-audio length; it uses signed 8-bit 22,050 Hz mono PCM, including intentionally silent tracks. |
| `libvgm` | `gym`, `s98`, `vgm`, `vgz` | Supported member is inspected or materialized from a supported archive. VGZ input is gzip-inflated before decoder intake. |
| Highly Complete | `gsf`, `minigsf` | Archive-backed playback materializes the complete archive set, preserving miniGSF library dependencies. |
| Highly Theoretical | `ssf`, `minissf` | Sega Saturn SCSP playback assembles sparse SSF program sections and their `_lib` dependencies into one bounded sound-RAM image before emulator initialization. Deep Scan reads the selected member's PSF tag footer without starting the emulator. |
| vgmstream | `dvi` | Konami `DVI.` Saturn ADPCM streams, including Castlevania: Symphony of the Night's Saturn release, are admitted through the shared archive/playback route and report `Sega Saturn`. |
| FFmpeg | `ape` | Monkey's Audio streams, including Panzer Dragoon's Saturn rip, decode through a bundled FFmpeg bridge and remain finite (Long Play disabled). |
| `lazyusf2` | `usf`, `miniusf` | Playback materializes the complete archive set, preserving miniUSF dependency files. Deep Scan reads the member's PSF tag footer and only materializes selected playable files. |
| `2sf2wav` | `2sf`, `mini2sf` | Playback materializes the complete archive set, preserving archive-relative 2SF libraries. Deep Scan reads PSF tags directly from selected members. |
| `vgmstream` | `aa3`, `adx`, `ads`, `aifc`, `at3`, `aus`, `bnk`, `fsb`, `genh`, `hd`, `hbd`, `iecs`, `int`, `mib`, `msf`, `mtaf`, `ogg`, `rws`, `ss2`, `stream`, `svag`, `vag`, `xa` | Native PlayStation XA, PlayStation 3 MSF, shared PlayStation 3/PSP ATRAC3/AA3, 3DO AIFC/GENH/STREAM, JoshW Grimoire of Souls FSB, Ogg Vorbis, and PlayStation 2/game-audio streams and banks. `.hd` banks are materialized with companions; an adjacent `SdDt` `.td` marks a KDT1 sequence bank, which is indexed as non-playable instead of being sent to the stream decoder. Deep scans open the decoder for playable subsongs, stream length, loop metadata, and format names. Playback is finite by default; Long Play reopens in forced-loop/play-forever mode while the shared app plan retains the finite manual stop and fade. |
| `vgmstream TXTP` | `txtp` | Playback and metadata scans materialize the complete archive set. Flat archives receive cache-only hard-link aliases for uniquely referenced sibling paths before vgmstream opens them; Windows `\\` references are normalized to archive-relative `/` paths. The bundled vgmstream build includes G.722.1/Siren 14 for Namco `.s14` layers. Source archives remain unchanged. Resident Evil 3, Jenga World Tour, Katamari Damacy, and Toy Story 3 are regression fixtures. Wwise `BKHD` `.bnk` event banks are indexed as non-playable resources; their TXTP/WEM content is the playable representation. |
| `Play! PSF` | `psf`, `minipsf` | Native PlayStation PSF emulator playback through the UI-free vendored Play! `PsfCore` bridge. Playback fully materializes sibling `_lib` and PSFLIB dependencies; Deep Scan reads `[TAG]` metadata from selected members. |
| `Play! PSF2` | `psf2`, `minipsf2` | Native PlayStation 2 PSF emulator playback through the same Play! bridge and complete-set playback policy; Deep Scan uses selected-member `[TAG]` metadata. |

## Supported Containers

`zip`, `7z`, `rsn`, `tar.zst`, and `tzst` are accepted as containers when they hold one of the supported audio formats above. TAR+Zstandard members are decompressed by `zstd` before `tar` lists or extracts them; harmless TAR-root `./` prefixes remain intact for exact member selection while cache paths are sanitized. ZIP member discovery uses 7-Zip's own path representation so legacy-encoded member names can be extracted consistently. A container itself is not a playable format.

## Not Currently Admitted

Every extension absent from `PlaybackFormatRegistry.supportedExtensions` is unsupported by discovery, database scanning, playlist intake, and playback. This includes raw AAC, ALAC, and Doom MUS. AAC-in-M4A playback is supported; AAC export does not by itself admit raw `.aac` input.

Headerless `.ss2` payloads are known unsupported resources: the SSHD decoder requires the `SShd` header for sample-rate and channel parameters. They are retained as unsupported scan inventory rather than metadata failures.

## Implementation Rules

- `PlaybackFormatRegistry` is the source of truth for extension admission, backend routing, archive dependency policy, scan concurrency, and multi-track behavior. Consumers call its admission API rather than open-coding extension membership checks.
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
