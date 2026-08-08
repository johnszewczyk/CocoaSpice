# CocoaSpice

**A native macOS library and player for game music, archives, and console-native audio.**

CocoaSpice scans a collection into a persistent Database, plays supported files through one low-latency audio path, and keeps an editable Playlist beside the library. It is designed for the way game music is actually collected: multi-track formats, archive members, companion libraries, loop metadata, and unusual console streams—not just ordinary audio files with different extensions.

## Long Play — game music the way it was meant to loop

Long Play is CocoaSpice’s defining playback feature. Enable it with the infinity button or in **Options → Playback**, choose a target duration, and compatible loop-aware game-music formats continue naturally through their console-style loop point before the optional end fade.

This is not ordinary “repeat the file” behavior. Long Play uses the decoder’s emulated music stream, so an SPC, NSF, GBS, KSS, HES, SAP, or related core game-music track can keep its music engine running just as it does on the original hardware. Turn it off whenever you prefer the file’s declared timing or native ending.

## Built for a real game-music library

- **Persistent scanned Database** — indexes files, archive members, metadata, durations, and subsongs; unchanged sources are reused on later scans, while a changed archive replaces its complete stored member set.
- **Archive-native browsing** — scan and play supported members from ZIP, 7z, RSN, TAR+Zstandard (`.tar.zst`, `.tzst`), including dependency sets where a format needs sibling libraries.
- **One intake path** — supported types work consistently for scanning, Finder drag and drop, direct opening, folders, archives, and playlist construction.
- **Modern native player** — streamed low-latency PCM output, seek, media keys, repeat, library/playlist random play, AAC export, shared ten-band EQ, app-level volume, and a full-range 10/20/40-band spectrum display.
- **Database-first library management** — scans run in the background with visible progress and queued requests; Test Links retains moved/missing-file data for fast rediscovery, while Clean Unlinked is the explicit permanent cleanup.
- **Flexible path control** — unchecked library paths stay out of the active Database and Scan All, but can still be scanned directly from their row when needed.

## Supported playback formats

All listed playable formats are admitted by the scanner, drag and drop, playlists, and direct opening. Archive members receive the same format handling as files on disk.

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

### Format-aware details

- Nintendo DS SWAV payloads misnamed as `.wav` are recognized from their header. Known NDS `_22.wav` assets without a WAV header are decoded as signed 8-bit, 22 kHz mono PCM instead of failing as malformed WAV.
- `.txtp` manifests and PSF/SSF/USF/2SF mini files preserve the necessary archive dependency set during playback.
- Multi-track files and embedded subsongs become separate playlist tracks.
- `.fsb` banks and `.txtp` manifests use vgmstream. PSF library files are dependencies, not standalone tracks.
- Doom `.mus`, raw AAC, and ALAC are currently not playback formats. Monkey's Audio `.ape` is supported through FFmpeg.

For the live, implementation-level inventory, see [Supported Formats](ai/subsystem-human/supported-formats.md).

## Archive containers

| Container | Library behavior |
| --- | --- |
| `.zip`, `.7z`, `.rsn` | Scanned and opened when playable members are present. |
| `.tar.zst`, `.tzst` | Listed and extracted through an explicit Zstandard/TAR pipeline for reliable archive handling. |

Containers are sources, not tracks: CocoaSpice indexes and queues their supported members while retaining each member’s archive provenance. A normal incremental scan reuses unchanged archives; when an archive is edited or repacked, CocoaSpice refreshes its current member set so renamed or removed members do not remain in the Database.

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

## License and notices

CocoaSpice has no separate top-level project license. It embeds and links components under distinct upstream terms, including LGPL-2.1-or-later, GPL-2.0-or-later, MPL-2.0, ISC, BSD-style terms, and configured FFmpeg dependencies. A redistribution must preserve and comply with every applicable upstream notice, source offer, and license obligation.

Read the complete component-by-component inventory in [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md), and retain the relevant notices in `vendor/` when distributing a build.
