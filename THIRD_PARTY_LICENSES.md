# Third-Party Code and Licenses

CocoaSpice embeds third-party decoder and emulator code. This repository does not provide a blanket substitute for those licenses: every distributed binary must preserve the applicable notices, source, and license obligations from `vendor/`.

| Component | Purpose | Upstream | License / notice location |
| --- | --- | --- | --- |
| libgme | Classic game-music decoding | [game-music-emu](https://github.com/libgme/game-music-emu) | LGPL-2.1-or-later; upstream license files and Homebrew package notice |
| libvgm | VGM and Sega playback | [libvgm](https://github.com/ValleyBell/libvgm) | Mixed upstream component licenses; preserve source headers and bundled notices |
| vgmstream | Streamed game-audio playback | [vgmstream](https://github.com/vgmstream/vgmstream) | ISC; `vendor/vgmstream/COPYING` |
| mGBA / Highly Complete | GBA GSF playback | [mGBA](https://github.com/mgba-emu/mgba) | MPL-2.0; `vendor/mgba/LICENSE` |
| lazyusf2 | Nintendo 64 USF and miniUSF | [lazyusf2](https://gitlab.com/kode54/lazyusf2) | GPL-2.0-or-later; vendored source headers and `vendor/lazyusf2/rsp_hle/LICENSES` |
| 2sf2wav | Nintendo DS 2SF and mini2SF | [2sf2wav](https://bitbucket.org/ahigerd/2sf2wav) | GPL-2.0-or-later; bundled DeSmuME-derived source headers |
| Play! | PlayStation PSF and PSF2 playback core | [Play!](https://github.com/jpd002/Play-) | BSD-style; `vendor/play/License.txt` and dependency notices |
| psflib | PSF chain loading for USF | bundled source | Preserve the imported source and audit its upstream licensing before redistributing binaries |

The project currently has no separate top-level CocoaSpice license. Distribution must satisfy the applicable licenses above, including any copyleft source-distribution requirements.
