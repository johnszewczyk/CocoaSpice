# Highly Complete Runtime Failure Modes

## Scope

- Known `minigsf` and `gsf` failure patterns.
- What broke during integration.
- Guardrails that now exist in the bridge and Swift wrapper.
- What future changes must preserve.

## Current State

- `Highly Complete` supports `gsf` and `minigsf` playback through the shared decoder path.
- miniGSF output follows the live native rate and is resampled into the app's fixed output rate.

## Rules

### Critical Engineering Notes

- Keep scan and inspection metadata-only.
- Keep `Package.swift` bridge feature flags and generated `mgba/flags.h` aligned with the vendored static library ABI.
- Preserve ROM-view ownership transfer to `mGBA` after `loadROM`.
- Keep metadata inspection separate from full `mGBA` playback startup.
- Keep bridge and vendored `mGBA` feature flags aligned; mismatched `struct mCore` layouts can crash playback immediately.
- After `loadROM`, treat the ROM `VFile` as core-owned.
- Preserve bounded native render waits; an infinite empty-render loop can starve the serial playback queue.
- Preserve the bridge gate unless the backend is redesigned around a provably thread-safe native model.
- Preserve bounded wait behavior in native render.
- Preserve output-frame timebase semantics for Swift playback transport.
- When only GBA formats fail, inspect bridge concurrency, native-core restart, and native-rate handling before changing shared transport code.
- Keep these notes current when `Highly Complete` behavior changes; this backend has enough footguns that stale notes are dangerous.

## Files

- [Package.swift](/Users/john/Documents/Code/CocoaSpice/Package.swift)
- [PlaybackDecoderRouting.swift](/Users/john/Documents/Code/CocoaSpice/Sources/CocoaSpice/App/PlaybackDecoderRouting.swift)
- [highlycomplete_bridge.cpp](/Users/john/Documents/Code/CocoaSpice/Sources/CHighlyComplete/highlycomplete_bridge.cpp)
- [audio-highly-complete-bridge-lifecycle.md](/Users/john/Documents/Code/CocoaSpice/ai/subsystem-agent/audio-highly-complete-bridge-lifecycle.md)
- [audio-highly-complete-minigsf-timing.md](/Users/john/Documents/Code/CocoaSpice/ai/subsystem-agent/audio-highly-complete-minigsf-timing.md)
