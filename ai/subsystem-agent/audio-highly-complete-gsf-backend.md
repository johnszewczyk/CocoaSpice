# Highly Complete GSF Backend

## Scope

- `gsf` and `minigsf` decoder ownership.
- Why the backend vendors `mGBA`.
- How `Highly Complete` fits into the app's otherwise generic decoder routing.
- Where to find the critical lifecycle, timing, and failure-mode notes.

## Current State

- `CHighlyComplete` is the native bridge target for the `Highly Complete` path.
- `gsf` and `minigsf` now route through `PlaybackDecoderFactory` the same way `libgme` and `libvgm` formats do.
- The bridge uses `psflib` to resolve PSF-family library chains such as `_lib` references inside `minigsf` sets.
- The bridge uses a headless `mGBA` core to execute the GBA audio code embedded by the format and render PCM frames for the app.
- The Swift app still treats this as a normal decoder backend:
  metadata inspection, playback, seek, and frame decoding all stay behind the shared decoder protocols.
- Long Play policy is still owned above the decoder by the app timing layer rather than by backend-specific UI branches.
- The detailed bridge lifecycle rules live in
  [audio-highly-complete-bridge-lifecycle.md](/Users/john/Documents/Code/CocoaSpice/ai/subsystem-agent/audio-highly-complete-bridge-lifecycle.md).
- The miniGSF timing and resampling rules live in
  [audio-highly-complete-minigsf-timing.md](/Users/john/Documents/Code/CocoaSpice/ai/subsystem-agent/audio-highly-complete-minigsf-timing.md).
- The runtime regression and failure notes live in
  [audio-highly-complete-runtime-failure-modes.md](/Users/john/Documents/Code/CocoaSpice/ai/subsystem-agent/audio-highly-complete-runtime-failure-modes.md).

## Rules

- Do not treat `mGBA` here as a user-facing emulator feature; it is an implementation dependency of the `Highly Complete` decoder path.
- Keep `gsf` and `minigsf` ownership centralized in backend routing rather than special-casing them in playlist, sidebar, or scan code.
- Keep PSF-chain parsing and GBA execution inside the native bridge, not in Swift.
- Preserve the `Highly Complete` name for this subsystem; do not obscure it behind vague decoder naming.

## Files

- [GMEFormatSupport.swift](/Users/john/Documents/Code/CocoaSpice/Sources/SPCBoy/App/GMEFormatSupport.swift)
- [PlaybackDecoderRouting.swift](/Users/john/Documents/Code/CocoaSpice/Sources/SPCBoy/App/PlaybackDecoderRouting.swift)
- [highlycomplete_bridge.h](/Users/john/Documents/Code/CocoaSpice/Sources/CHighlyComplete/include/highlycomplete_bridge.h)
- [highlycomplete_bridge.cpp](/Users/john/Documents/Code/CocoaSpice/Sources/CHighlyComplete/highlycomplete_bridge.cpp)
- [scripts/build-mgba.sh](/Users/john/Documents/Code/CocoaSpice/scripts/build-mgba.sh)
- [vendor/mgba/CMakeLists.txt](/Users/john/Documents/Code/CocoaSpice/vendor/mgba/CMakeLists.txt)
- [psflib.h](/Users/john/Documents/Code/CocoaSpice/Sources/CHighlyComplete/third_party/psflib/psflib.h)
- [psflib.c](/Users/john/Documents/Code/CocoaSpice/Sources/CHighlyComplete/third_party/psflib/psflib.c)
- [audio-highly-complete-bridge-lifecycle.md](/Users/john/Documents/Code/CocoaSpice/ai/subsystem-agent/audio-highly-complete-bridge-lifecycle.md)
- [audio-highly-complete-minigsf-timing.md](/Users/john/Documents/Code/CocoaSpice/ai/subsystem-agent/audio-highly-complete-minigsf-timing.md)
- [audio-highly-complete-runtime-failure-modes.md](/Users/john/Documents/Code/CocoaSpice/ai/subsystem-agent/audio-highly-complete-runtime-failure-modes.md)
