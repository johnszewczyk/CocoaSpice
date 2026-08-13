# CocoaSpice

**A native macOS library and player for game music, archives, and console-native audio.**

CocoaSpice reads a persistent Database produced by the shared native MediaScanner, plays supported files through one low-latency audio path, and keeps an editable Playlist beside the library. It is designed for the way game music is actually collected: multi-track formats, archive members, companion libraries, loop metadata, and unusual console streams—not just ordinary audio files with different extensions.

## Contents

- [What CocoaSpice does](#what-cocoaspice-does)
- [Long Play](#long-play--game-music-the-way-it-was-meant-to-loop)
- [Library workflow](#library-workflow)
- [Playback and interface](#playback-and-interface)
- [Supported playback formats](#supported-playback-formats)
- [Archive containers](#archive-containers)
- [Credits, build, and licensing](#decoder-emulator-and-codec-credits)

## What CocoaSpice does

| Library | Playback | Formats | macOS experience |
| --- | --- | --- | --- |
| Shared read-only MediaScanner database, indexed Games/Search, and direct Files browsing | Low-latency streamed PCM, seeking, repeat/random play, AAC export, and global app volume | Console-native streams, emulator-backed music, standard audio, and dependency-aware archive playback | Native windows, media keys, Finder drag and drop, light/dark-system controls, and independent Options panels |

Playback format admission is centralized. A format is not advertised merely because an extension is registered: decoder output is validated as real PCM. Catalog intake is owned separately by MediaScanner so CocoaSpice, SPCBoy, and future frontends share one database implementation.

## Long Play — game music the way it was meant to loop

Long Play is CocoaSpice’s defining playback feature. Enable it with the infinity button or in **Options → Playback**, choose a target duration, and compatible loop-aware game-music formats continue naturally through their console-style loop point before the optional end fade.

This is not ordinary “repeat the file” behavior. Long Play uses the decoder’s emulated music stream, so an SPC, NSF, GBS, KSS, HES, SAP, or related core game-music track can keep its music engine running just as it does on the original hardware. Turn it off whenever you prefer the file’s declared timing or native ending.

## Library workflow

1. **Choose the catalog** in **Options → Data → Database** when a non-default shared `Library.sqlite` is required. CocoaSpice validates schema 23 before saving the path and applies a changed location after restart. The default remains `~/Library/Application Support/CocoaSpice/Library.sqlite`.
2. **Build or update the catalog in MediaScanner.** Add complete roots there, choose folder-first or embedded-metadata-first console grouping, and run Scan or Rebuild. Cancel retains completed source/archive checkpoints for resume.
3. **Restart CocoaSpice** after choosing a different database. CocoaSpice opens it read-only and never changes roots, rows, metadata, or projections.
4. **Browse** Games for metadata-grouped titles, or Files for the scanned folder tree. Neither mode walks the live filesystem during ordinary browsing.
5. **Play from the database.** Activating a stored game or file loads its exact source, archive-member, and subtrack rows into the Playlist; playback materialization does not modify the catalog.

### Database rules

- The selected database path is explicit, absolute, persisted, and validated against the shared MediaScanner catalog contract before it can replace the launch-time path.
- A source is identified by its library root, source path, archive member, and subtrack index. One source does not produce duplicate database rows.
- A Games row is identified by its library root, game, and system. Matching titles from separate roots remain separate and load only that root's stored playlist rows.
- Game tags are used when present; otherwise archives use their filename and loose tracks use their parent folder. A recognized terminal filename tag such as `[PS2]`, then a recognized console folder, supplies collection console identity by default; the Options switch prefers normalized embedded console tags instead.
- MediaScanner incremental scans reuse unchanged results. A changed archive replaces its complete stored member set, so removed or renamed members cannot remain visible.
- MediaScanner publishes a structurally complete catalog atomically. Required embedded tracks are enumerated before publication; optional metadata for known single-track media may remain empty.

## Playback and interface

| Feature | Behavior |
| --- | --- |
| Playlist | Native multi-selection, keyboard activation, sortable columns, optional monospace display, and total-duration status. |
| Sidebar search | The first character waits 250 ms and follow-up typing waits 100 ms. A query temporarily shows the same indexed game results from either underlying Games or Files mode; clearing it restores that mode. |
| Long Play | Only loop-aware decoder modules participate. Ordinary finite media—WAV, AIFF, FLAC, MP3, M4A/AAC, and APE—always keep their native duration. |
| Audio controls | Ten-band EQ, app-level attenuation-only volume, mono output, and optional 10/20/40-band spectrum. Spectrum is off by default because it uses additional CPU while playing. |
| Transitions | Transport, seek, track changes, and Long Play reconfiguration use a brief output duck to reduce device-change clicks without altering the music stream or macOS system volume. |
| Appearance | Native Options controls follow macOS light/dark appearance. Sidebar and Playlist typography, color, and monospace styling are configurable. |

### Format-aware details

- Nintendo DS SWAV payloads misnamed as `.wav` are recognized from their header. Known NDS `_22.wav` assets without a WAV header are decoded as signed 8-bit, 22 kHz mono PCM instead of failing as malformed WAV.
- `.txtp` manifests and PSF/SSF/USF/2SF mini files preserve the necessary archive dependency set during playback.
- Multi-track files and embedded subsongs become separate playlist tracks.
- `.fsb` banks and `.txtp` manifests use vgmstream. PSF library files are dependencies, not standalone tracks.
- Doom `.mus`, raw AAC, and ALAC are currently not playback formats. Monkey's Audio `.ape` is supported through FFmpeg.

## Supported playback formats

All listed formats are supported for CocoaSpice playback, drag and drop, playlists, and direct opening. MediaScanner catalog support is independently verified because required enumeration and dependency handling may need a shared native adapter.

| Family | Extensions | Playback layer |
| --- | --- | --- |
| Classic chip and console music | `.ay`, `.gbs`, `.hes`, `.kss`, `.nsf`, `.nsfe`, `.sap`, `.spc` | [Game Music Emu / libgme](https://github.com/libgme/game-music-emu) |
| Tracker music | `.xm` | [libopenmpt](https://lib.openmpt.org/libopenmpt/) |
| Sega music logs | `.gym`, `.s98`, `.vgm`, `.vgz` | [libvgm](https://github.com/ValleyBell/libvgm) |
| Game Boy Advance PSF | `.gsf`, `.minigsf` | [mGBA / Highly Complete](https://github.com/mgba-emu/mgba) |
| Sega Saturn SSF | `.ssf`, `.minissf` | [Highly Theoretical](https://gitlab.com/kode54/highly_theoretical) |
| Sega Saturn Konami streams | `.dvi` | [vgmstream](https://github.com/vgmstream/vgmstream) |
| Sega Saturn Monkey's Audio | `.ape` | [FFmpeg](https://ffmpeg.org/) |
| Nintendo 64 | `.usf`, `.miniusf` | [lazyusf2](https://gitlab.com/kode54/lazyusf2) |
| Nintendo DS PSF | `.2sf`, `.mini2sf` | [2sf2wav](https://bitbucket.org/ahigerd/2sf2wav) |
| PlayStation PSF | `.psf`, `.minipsf` | [Play!](https://github.com/jpd002/Play-) PSF core |
| PlayStation 2 PSF | `.psf2`, `.minipsf2` | [Play!](https://github.com/jpd002/Play-) PSF core |
| Streamed console/game audio | `.aa3`, `.adx`, `.ads`, `.aifc`, `.at3`, `.aus`, `.bnk`, `.fsb`, `.genh`, `.hd`, `.hbd`, `.iecs`, `.int`, `.mib`, `.msf`, `.mtaf`, `.ogg`, `.rws`, `.ss2`, `.stream`, `.svag`, `.vag`, `.xa`, `.txtp` | [vgmstream](https://github.com/vgmstream/vgmstream) |
| Standard audio | `.aif`, `.aiff`, `.flac`, `.m4a`, `.mp3`, `.wav` | macOS audio frameworks |

For the live, implementation-level inventory, see [Supported Formats](ai/subsystem-human/supported-formats.md).

## Archive containers

| Container | Library behavior |
| --- | --- |
| `.zip`, `.7z`, `.rsn` | Scanned and opened when playable members are present. |
| `.tar.zst`, `.tzst` | Listed and extracted through an explicit Zstandard/TAR pipeline for reliable archive handling. |

Containers are sources, not tracks: MediaScanner indexes supported members with archive provenance, while CocoaSpice queues those stored rows and materializes them for playback. A normal incremental scan reuses unchanged archives; an edited or repacked archive replaces its complete member set.

## Decoder, emulator, and codec credits

CocoaSpice is possible because of these projects and the work of their maintainers:

| Component | Used for | Upstream |
| --- | --- | --- |
| Game Music Emu / libgme | Classic emulated game-music formats and Long Play | [GitHub](https://github.com/libgme/game-music-emu) |
| libopenmpt | XM tracker playback | [Project site](https://lib.openmpt.org/libopenmpt/) |
| libvgm | VGM-family playback | [GitHub](https://github.com/ValleyBell/libvgm) |
| vgmstream | Console-native streamed audio, banks, and TXTP | [GitHub](https://github.com/vgmstream/vgmstream) |
| FFmpeg | Monkey's Audio playback and vgmstream codec support | [Project site](https://ffmpeg.org/) |
| libogg / libvorbis | Ogg Vorbis support used by vgmstream | [Xiph.org](https://xiph.org/) |
| mGBA / Highly Complete | GSF and miniGSF | [GitHub](https://github.com/mgba-emu/mgba) |
| Highly Theoretical | Sega Saturn SSF and miniSSF | [GitLab](https://gitlab.com/kode54/highly_theoretical) |
| lazyusf2 | USF and miniUSF | [GitLab](https://gitlab.com/kode54/lazyusf2) |
| 2sf2wav | 2SF and mini2SF | [Bitbucket](https://bitbucket.org/ahigerd/2sf2wav) |
| Play! | PSF and PSF2 playback core | [GitHub](https://github.com/jpd002/Play-) |
| psflib | PSF chain loading | Bundled source; see notices below |

## Build and run

Requires macOS, Xcode, Homebrew `game-music-emu`, `ffmpeg`, `libopenmpt`, CMake, 7-Zip, and unar.

```bash
./build.sh
./launch.sh
```

### Repository map

| Path | Purpose |
| --- | --- |
| `Sources/CocoaSpice/App/` | Native SwiftUI/AppKit application, read-only database browser, playback archives, playback, and UI logic. |
| `Sources/C*/` | Narrow C/C++ bridges around decoder and emulator cores. |
| `vendor/` | Vendored upstream decoder, emulator, and codec source trees. |
| `ai/subsystem-human/` | Short current feature documentation. |
| `ai/subsystem-agent/` | Engineering ownership and invariants. |
| `THIRD_PARTY_LICENSES.md` | Component-by-component license inventory. |

## License and notices

CocoaSpice has no separate top-level project license. It embeds and links components under distinct upstream terms, including LGPL-2.1-or-later, GPL-2.0-or-later, MPL-2.0, ISC, BSD-style terms, and configured FFmpeg dependencies. A redistribution must preserve and comply with every applicable upstream notice, source offer, and license obligation.

Read the complete component-by-component inventory in [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md), and retain the relevant notices in `vendor/` when distributing a build.
