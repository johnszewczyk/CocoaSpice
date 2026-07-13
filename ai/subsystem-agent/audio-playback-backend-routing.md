# Audio Playback Backend Routing

## Scope

- Which decoder backend owns which file types.
- How streamed playback stays backend-agnostic above the decoder layer.
- The current `libgme`, `libvgm`, and `Highly Complete` split.

## Current State

- `PlaybackEngine` now builds a decoder through a backend-routing factory rather than instantiating `libgme` directly.
- `libgme` remains the backend for container and dump formats such as `spc`, `nsf`, `nsfe`, `gbs`, `hes`, `kss`, `sap`, and `ay`.
- `lazyusf2` owns `usf` and `miniusf` through the `CLazyUSF` bridge; keep its PSF-chain loading and N64 emulation behind that bridge.
- LazyUSF scanning reads each file's PSF tags without constructing the emulator or loading its dependency chain; full chain loading remains playback-only.
- Backend modules expose app-owned PCM, metadata, seeking, and timing hooks; the player model must not call decoder-specific C APIs directly.
- `libvgm` now owns `vgm`, `vgz`, `gym`, and `s98`.
- `Highly Complete` now owns `gsf` and `minigsf`.
- The vendored `2sf2wav` core owns `2sf` and `mini2sf` through `C2SF`. Its bridge is serialized because the underlying DS core uses shared global state.
- File inspection and playback share the same backend-routing table, so scan results, playlist import, and playback no longer disagree about VGM-family ownership.
- `libvgm` is wrapped behind a small C bridge target so the Swift app can stay mostly ignorant of C++ details.
- `Highly Complete` is also wrapped behind a local native bridge target, using `psflib` plus a headless `mGBA` core for GBA-audio execution.
- The Swift wrapper serializes `Highly Complete` bridge calls behind a dedicated gate because this backend has stricter runtime-safety constraints than the others.
- `Highly Complete` also performs native-rate to output-rate resampling for `minigsf` and `gsf` so GBA titles can feed the shared fixed-rate playback engine correctly.
- Long Play policy is still selected above the decoder by extension profile, not by backend capability negotiation.
- `libvgm` currently relies on app-side fade shaping for bounded manual playback because the app still owns the final playback cap.

## Rules

- Keep backend routing centralized; do not re-encode extension decisions in UI or playlist code.
- Keep file intake policy, decoder routing, and Long Play policy as separate concerns.
- Archive materialization happens before backend creation. ZIP and 7z members stream through `7zz`; RSN members route through `unar` because RSN files are solid RAR-family archives.
- Prefer adding new decoder backends under the existing playback abstractions instead of branching the view model.
- Treat `Highly Complete` as a real backend subsystem, not as a one-off `minigsf` exception.
- Do not assume all decoder backends share identical threading or sample-rate behavior.
- 2SF archive playback materializes the complete archive set before bridge creation so `_lib` dependencies resolve beside the selected file.

## Files

- [PlaybackDecoderRouting.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaybackDecoderRouting.swift)
- [PlaybackEngine.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaybackEngine.swift)
- [GMEFormatSupport.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/GMEFormatSupport.swift)
- [libvgm_bridge.h](/Users/john/Downloads/Code/CocoaSpice/Sources/CLibVGM/include/libvgm_bridge.h)
- [libvgm_bridge.cpp](/Users/john/Downloads/Code/CocoaSpice/Sources/CLibVGM/libvgm_bridge.cpp)
- [highlycomplete_bridge.h](/Users/john/Downloads/Code/CocoaSpice/Sources/CHighlyComplete/include/highlycomplete_bridge.h)
- [highlycomplete_bridge.cpp](/Users/john/Downloads/Code/CocoaSpice/Sources/CHighlyComplete/highlycomplete_bridge.cpp)
- [twosf_bridge.cpp](/Users/john/Downloads/Code/CocoaSpice/Sources/C2SF/twosf_bridge.cpp)
