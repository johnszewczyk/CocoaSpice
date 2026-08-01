# Supported Formats

CocoaSpice supports the following formats for library scanning, drag and drop, playlists, and playback. Files inside a supported archive are handled the same way as files on disk.

## Game-Music Formats

| Family | Extensions |
| --- | --- |
| SNES, NES, Game Boy, Sega, MSX, and related chip music | `.ay`, `.gbs`, `.hes`, `.kss`, `.nsf`, `.nsfe`, `.sap`, `.spc` |
| Tracker music | `.xm` |
| Sega music logs | `.gym`, `.s98`, `.vgm`, `.vgz` |
| Game Boy Advance PSF | `.gsf`, `.minigsf` |
| Sega Saturn SSF | `.ssf`, `.minissf` |
| Nintendo 64 USF | `.usf`, `.miniusf` |
| Nintendo DS PSF | `.2sf`, `.mini2sf` |
| PlayStation PSF | `.psf`, `.minipsf` |
| PlayStation 2 PSF | `.psf2`, `.minipsf2` |

## Streamed Game Audio

These formats use the built-in vgmstream decoder. This includes `.stream` files and a range of console-native streams and banks.

`.aa3`, `.adx`, `.ads`, `.aifc`, `.at3`, `.aus`, `.bnk`, `.fsb`, `.genh`, `.hd`, `.hbd`, `.iecs`, `.int`, `.mib`, `.msf`, `.mtaf`, `.ogg`, `.rws`, `.ss2`, `.stream`, `.svag`, `.vag`, `.xa`, `.txtp`

## Standard Audio

`.aif`, `.aiff`, `.flac`, `.m4a`, `.mp3`, and `.wav` play through macOS audio support. The verified `.m4a` route includes AAC audio. Archive `.m3u` playlists expand their supported sibling tracks in the order declared by the playlist. Nintendo DS SWAV audio that is incorrectly named `.wav` is recognized by its file header and played through the game-audio decoder. Known Nintendo DS `_22.wav` assets with no WAV header are recognized as signed 8-bit, 22 kHz mono PCM rather than sent to macOS as malformed WAV files.

`.fsb` banks and `.txtp` manifests play through vgmstream. TXTP manifests use their complete archive dependency set; CocoaSpice restores flat archive paths inside its playback cache only. Doom `.mus` is not supported because it requires a MIDI-event synthesizer backend, not an extension-only route.

## Archive Containers

`.zip`, `.7z`, `.rsn`, `.tar.zst`, and `.tzst` can be scanned and opened when they contain a supported format. Some formats require companion or library files, so CocoaSpice automatically retains the needed archive set while playing them.

## Not Supported for Playback

Raw AAC, ALAC, APE, and Doom MUS are not currently playback formats. PSF library files are dependency resources rather than independently playable tracks.

## Notes

- A file extension is only the first check: CocoaSpice also identifies Nintendo DS SWAV audio by its contents, and uses strict filename and payload checks for the known DS `_22.wav` raw-PCM layout.
- A detected Silent Hill KDT sequence bank (`.hd` with its matching `SdDt` `.td`) is catalogued as non-playable data. Its rendered audio files, such as `.msf`, remain playable.
- Format support is shared across scanning, drag and drop, playlists, and direct opening.
