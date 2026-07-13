# Nintendo DS 2SF / mini2SF Backend Plan

## Goal

Add playback, metadata scanning, playlists, folder scans, and ZIP/7z archive support for Nintendo DS `.2sf` and `.mini2sf` files. Raw `.nds` ROM playback is out of scope.

## Architecture Decision

Implement a dedicated native 2SF bridge backed by a maintained 2SF-compatible Nintendo DS audio core (candidate: `vio2sf` or an equivalent library that builds cleanly on macOS and has an acceptable license). Do not extend the GBA-only Highly Complete/mGBA bridge.

2SF is a PSF-derived format: a mini2SF can depend on a sibling 2SF library. The bridge must own dependency resolution and the app must materialize a complete archive set before playback, following the LazyUSF archive rule.

## Delivery Passes

1. **Core spike**
   - Vendor and build the selected 2SF core in `Package.swift`.
   - Add `C2SF` with a narrow C API: create/destroy, read PSF tags, configure duration, render stereo PCM, seek, and free errors/metadata.
   - Prove standalone `.2sf` and `.mini2sf` playback with small known-good fixtures.

2. **Routing and intake**
   - Add `2sf` and `mini2sf` to `GMEFormatSupport` as a new `twosf` plugin route.
   - Add the descriptor and handler in `ScanCoreHandlers`.
   - Add Swift `TwoSFDecoder` and metadata inspector in `PlaybackDecoderRouting`; keep bridge calls behind a dedicated safety gate unless the selected core is proven concurrent-safe.
   - Ensure folders, drag/drop, M3U, and archive-entry filtering inherit support from the central route table.

3. **Archive dependency sets**
   - Extend `ZipArchiveSupport` to materialize the full archive set for the `twosf` route, not just the selected member.
   - Preserve archive-relative paths and reject dependency paths that escape the extracted set.
   - Reuse cache ownership/cleanup rules already used by LazyUSF.

4. **Metadata and playback correctness**
   - Scan tags without constructing a full long-lived playback session where the chosen core supports tag-only loading.
   - Respect `_lib`, `length`, and `fade` tags; map title/game/artist/system/comment into `TrackMetadata` with `Nintendo DS` as the fallback system.
   - Verify output-rate conversion, frame accounting, seeking, end-of-track behavior, and Long Play policy.

5. **Verification and rollout**
   - Fixtures: standalone 2SF, mini2SF plus library, missing library, malformed tags, ZIP/7z set, and nested archive-relative dependency paths.
   - Tests: route registration, metadata, playback start at zero, seek, archive playback, missing dependency error, and a bounded command-line scan.
   - Run a real NDS collection scan before enabling the format in a large root; confirm no descriptor growth or persistence cascade.

## Acceptance Criteria

- A standalone `.2sf` and dependent `.mini2sf` both scan and play from disk, M3U, ZIP, and 7z.
- Missing or invalid libraries create one precise per-file scan failure without interrupting other items.
- No raw `.nds` files are advertised or accepted as music input.
- The new route does not duplicate extension logic outside the registry/routing layer.

## Primary Touchpoints

- `Package.swift`
- `Sources/CocoaSpice/App/GMEFormatSupport.swift`
- `Sources/CocoaSpice/App/ScanCoreHandlers.swift`
- `Sources/CocoaSpice/App/PlaybackDecoderRouting.swift`
- `Sources/CocoaSpice/App/ZipArchiveSupport.swift`
- `Tests/CocoaSpiceTests/CocoaSpiceTests.swift`
