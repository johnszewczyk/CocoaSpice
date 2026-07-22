# CocoaSpice

CocoaSpice is a native macOS player and library for game music. It pairs a scanned Database browser with an editable Playlist and plays every supported format through one shared low-latency audio path.

## Highlights

- Fast Scan for filename-only intake, or Deep Scan for archive members, metadata, duration, and subsongs.
- Drag files, folders, and supported archives straight into the playlist.
- Universal Long Play: one extended-playback setting for every supported decoder.
- A ten-band 31 Hz–16 kHz Equalizer, shared by every playback format.
- Native transport controls, seek, repeat, library/playlist random play, spectrum display, and AAC export.

## Supported playback

| Family | Formats |
| --- | --- |
| Classic game music | `ay`, `gbs`, `hes`, `kss`, `nsf`, `nsfe`, `sap`, `spc` |
| Sega / VGM | `gym`, `s98`, `vgm`, `vgz` |
| GBA / Nintendo 64 / DS | `gsf`, `minigsf`, `usf`, `miniusf`, `2sf`, `mini2sf` |
| PlayStation | `psf`, `minipsf`, `psf2`, `minipsf2`, `xa` |
| Streamed game audio | `adx`, `ads`, `aus`, `hd`, `hbd`, `iecs`, `int`, `mib`, `mtaf`, `rws`, `ss2`, `svag`, `vag` |

Supported containers are ZIP, 7z, RSN, `.tar.zst`, and `.tzst`. A container is expanded only for supported members; it is not itself a playable track.

## Build and run

Requires current macOS, Xcode, Homebrew `game-music-emu`, CMake, 7-Zip, and unar.

```bash
./build.sh
./launch.sh
```

## Decoder and emulator components

CocoaSpice is possible because of these projects:

- [Game Music Emu / libgme](https://github.com/libgme/game-music-emu)
- [libvgm](https://github.com/ValleyBell/libvgm)
- [vgmstream](https://github.com/vgmstream/vgmstream)
- [mGBA](https://github.com/mgba-emu/mgba), used by the Highly Complete GSF path
- [lazyusf2](https://gitlab.com/kode54/lazyusf2)
- [2sf2wav](https://bitbucket.org/ahigerd/2sf2wav)
- [Play!](https://github.com/jpd002/Play-)

Thank you to their maintainers and contributors for making these formats accessible and preservable.

## License and notices

CocoaSpice currently has no separate top-level project license. It bundles decoder and emulator code with different licenses, including LGPL-2.1-or-later, GPL-2.0-or-later, MPL-2.0, ISC, and BSD-style terms. Redistributing CocoaSpice must preserve and comply with every applicable upstream notice and source obligation. See [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) and the notices in `vendor/` for the distribution details.
