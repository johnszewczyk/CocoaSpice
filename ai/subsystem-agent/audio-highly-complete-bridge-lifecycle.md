# Highly Complete Bridge Lifecycle

## Scope

- Native bridge ownership for `gsf` and `minigsf`.
- `psflib` load flow into headless `mGBA`.
- Core teardown, restart, and seek rebuild rules.
- Swift-side bridge serialization requirements.

## Current State

- `CHighlyComplete` is the only native bridge target for the `Highly Complete` backend.
- `psflib` resolves PSF-family chaining, including `_lib` references in `minigsf` sets, before playback starts.
- The bridge assembles the resolved GBA ROM image in memory, then creates a `VFile` view over that image for `mGBA`.
- `mCoreFindVF` chooses the GBA core, `core->init` allocates the real emulator state, and `core->loadROM` transfers ownership of the ROM view into the core.
- Playback, seek, and metadata access stay behind the C bridge API exposed by
  [highlycomplete_bridge.h](/Users/john/Documents/Code/CocoaSpice/Sources/CHighlyComplete/include/highlycomplete_bridge.h).
- Swift serializes all `Highly Complete` bridge entry points behind a single lock in
  [PlaybackDecoderRouting.swift](/Users/john/Documents/Code/CocoaSpice/Sources/SPCBoy/App/PlaybackDecoderRouting.swift)
  because rapid concurrent inspect or create or render activity can destabilize this backend even when other decoders remain fine.

## Critical Notes

- `highlycomplete_inspect_file` must remain metadata-only.
  It exists so library scan, drag-drop intake, and sidebar inspection do not boot a full `mGBA` core.
- After `core->loadROM`, the bridge must treat the `VFile` as core-owned.
  Do not close the ROM view again during bridge teardown.
- `mCoreConfigDeinit(&core->config)` must happen before `core->deinit(core)`.
- `core->deinit(core)` frees the core object for the GBA path.
  Do not touch `handle->core` after that call except to null it out.
- Backward seek is implemented as core rebuild plus fast discard.
  The bridge does not rely on stable random-access native seek inside `mGBA`.

## Rules

- Keep all PSF parsing and GBA execution inside the native bridge, not in Swift.
- Keep bridge entry points narrow and backend-specific; the shared app should only see decoder protocol behavior.
- Do not bypass the Swift-side `HighlyCompleteBridgeGate` for new bridge calls.
- Do not move `gsf` or `minigsf` special cases into sidebar, playlist, or queue code.

## Files

- [PlaybackDecoderRouting.swift](/Users/john/Documents/Code/CocoaSpice/Sources/SPCBoy/App/PlaybackDecoderRouting.swift)
- [highlycomplete_bridge.h](/Users/john/Documents/Code/CocoaSpice/Sources/CHighlyComplete/include/highlycomplete_bridge.h)
- [highlycomplete_bridge.cpp](/Users/john/Documents/Code/CocoaSpice/Sources/CHighlyComplete/highlycomplete_bridge.cpp)
- [psflib.h](/Users/john/Documents/Code/CocoaSpice/Sources/CHighlyComplete/third_party/psflib/psflib.h)
- [psflib.c](/Users/john/Documents/Code/CocoaSpice/Sources/CHighlyComplete/third_party/psflib/psflib.c)
- [audio-highly-complete-gsf-backend.md](/Users/john/Documents/Code/CocoaSpice/ai/subsystem-agent/audio-highly-complete-gsf-backend.md)
