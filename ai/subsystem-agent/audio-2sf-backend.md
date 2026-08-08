# Nintendo DS 2SF / mini2SF Backend

## Scope

`2sf` and `mini2sf` are admitted for playback, metadata scanning, playlists, folder scans, and supported archives. Raw `.nds` ROMs are not music input.

## Ownership

The app vendors the GPL-2.0-or-later `2sf2wav` core and builds it as `lib2sf.a` through `scripts/build-2sf.sh`. `C2SF` exposes a narrow C API to Swift for decoder lifetime, tag inspection, timing, stereo PCM, seeking, and error ownership. This is separate from the GBA-only Highly Complete/mGBA backend.

2SF is PSF-derived: a mini2SF can depend on a sibling 2SF library. For archive tracks, `ZipArchiveSupport` materializes the complete set before playback so those relative dependencies remain available. Metadata scans read tags without creating a playback session.

## Invariants

- `PlaybackFormatRegistry` is the sole extension-admission and decoder-routing table; the `twosf` scanner descriptor inherits it.
- `TwoSFBridgeGate` serializes every bridge call, including tag inspection, because the DS core is not concurrent-safe.
- `length` and `fade` tags become `TrackMetadata` timing fields. `Nintendo DS` is always the system fallback.
- Archive dependency paths must remain relative to the extracted set; malformed or missing libraries fail only their own scan or playback item.
- The bridge discards the DS core's short boot transient before it supplies audio to the shared playback queue.

## Files

- `Package.swift`
- `Sources/CocoaSpice/App/GMEFormatSupport.swift`
- `Sources/CocoaSpice/App/ScanCoreHandlers.swift`
- `Sources/CocoaSpice/App/PlaybackDecoderRouting.swift`
- `Sources/CocoaSpice/App/ZipArchiveSupport.swift`
- `Tests/CocoaSpiceTests/PlaybackFoundationTests.swift`
