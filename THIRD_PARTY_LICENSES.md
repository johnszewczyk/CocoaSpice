# Third-Party Code and Licenses

CocoaSpice bundles VGMBoyKit and redistributes third-party decoder and emulator components through
the VGMBoy core. The decoder source garden and build ownership live in the sibling VGMBoy
repository; every distributed binary must preserve the applicable notices and license obligations
listed here.

| Component | Purpose | Upstream | License / notice location |
| --- | --- | --- | --- |
| libgme | Classic game-music decoding | [game-music-emu](https://github.com/libgme/game-music-emu) | LGPL-2.1-or-later; upstream license files and Homebrew package notice |
| libopenmpt | FastTracker XM module decoding | [libopenmpt](https://lib.openmpt.org/libopenmpt/) | BSD-3-Clause; Homebrew package notice |
| libvgm | VGM and Sega playback | [libvgm](https://github.com/ValleyBell/libvgm) | Mixed upstream component licenses; preserve source headers and bundled notices |
| vgmstream | Streamed game-audio playback through VGMBoyKit | [vgmstream](https://github.com/vgmstream/vgmstream) | ISC; VGMBoy `vendor/vgmstream/COPYING` |
| FFmpeg | ATRAC3 and related streamed-audio decoding used by vgmstream | [FFmpeg](https://ffmpeg.org/) | Preserve the Homebrew package license notices and the linked build's configured license terms. |
| libvorbis / libogg | Ogg Vorbis decoding used by vgmstream | [Xiph.org](https://xiph.org/) | BSD-style; preserve Homebrew package notices. |
| mGBA / Highly Complete | GBA GSF playback through VGMBoyKit | [mGBA](https://github.com/mgba-emu/mgba) | MPL-2.0; VGMBoy `vendor/mgba/LICENSE` |
| lazyusf2 | Nintendo 64 USF and miniUSF through VGMBoyKit | [lazyusf2](https://gitlab.com/kode54/lazyusf2) | GPL-2.0-or-later; VGMBoy source headers and `vendor/lazyusf2/rsp_hle/LICENSES` |
| 2sf2wav | Nintendo DS 2SF and mini2SF through VGMBoyKit | [2sf2wav](https://bitbucket.org/ahigerd/2sf2wav) | GPL-2.0-or-later; VGMBoy DeSmuME-derived source headers |
| Play! | PlayStation PSF and PSF2 playback core through VGMBoyKit | [Play!](https://github.com/jpd002/Play-) | BSD-style; VGMBoy `vendor/play/License.txt` and dependency notices |
| psflib | PSF chain loading for USF | bundled source | Preserve the imported source in VGMBoy and audit its upstream licensing before redistributing binaries |

The project currently has no separate top-level CocoaSpice license. Distribution must satisfy the applicable licenses above, including any copyleft source-distribution requirements. Highly Theoretical is no longer an active CocoaSpice/VGMBoy playback dependency.
