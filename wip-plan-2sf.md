# WIP Plan: Nintendo DS 2SF / mini2SF Support

## Objective

Add reliable CocoaSpice support for Nintendo DS music files:

- `.2sf`
- `.mini2sf`

Support must cover direct files, folder scans, drag/drop, M3U entries, ZIP/7z archive members, library persistence, metadata, playback, seeking, and scan diagnostics.

Do **not** add raw `.nds` ROM playback or advertise `.nds` as supported input.

## Phase 0 Status

`2sf2wav` is the selected GPL-compatible core. Its DeSmuME-derived emulator sources provide the required `.2sf` / `.mini2sf` PSF dependency loader and a non-Windows build path. Prove its standalone macOS build and direct/dependent fixture playback before adding CocoaSpice routing or a bridge.

The interpreter-only static core and the narrow `C2SF` bridge now build and link in CocoaSpice. The bridge owns metadata, dependency-chain loading, PCM rendering, seek-by-replay, frame accounting, and teardown. It remains unregistered while archive dependency-set materialization and fixture coverage are added.

## Current App Architecture

Playback is backend-routed. Existing backend ownership:

- `libgme`: SPC, NSF/NSFE, GBS, HES, KSS, SAP, AY, and similar container formats.
- `libvgm`: VGM/VGZ, GYM, S98.
- `Highly Complete` + mGBA: GSF/miniGSF only.
- `LazyUSF`: USF/miniUSF only.

The extension registry is centralized in `GMEFormatSupport.swift` and `ScanCoreHandlers.swift`. Intake paths (folder scan, archive filtering, playlist/M3U, drag/drop) inherit supported extensions from this registry; do not add separate `.2sf` checks in UI or queue code.

Relevant files:

- `Package.swift`
- `Sources/CocoaSpice/App/GMEFormatSupport.swift`
- `Sources/CocoaSpice/App/ScanCoreHandlers.swift`
- `Sources/CocoaSpice/App/ScanPipelineExecutor.swift`
- `Sources/CocoaSpice/App/PlaybackDecoderRouting.swift`
- `Sources/CocoaSpice/App/ZipArchiveSupport.swift`
- `Sources/CocoaSpice/App/PlaybackEngine.swift`
- `Tests/CocoaSpiceTests/PlaybackFoundationTests.swift`

Read first:

- `ai/AGENTS.md`
- `ai/project-info.md`
- `ai/subsystem-agent/audio-playback-backend-routing.md`
- `ai/subsystem-agent/audio-2sf-backend-plan.md`
- `ai/subsystem-agent/library-scan-roots.md`

## Non-Negotiable Design Decisions

1. Create a **dedicated DS/2SF bridge**. Do not extend the GBA-only Highly Complete/mGBA bridge.
2. `.mini2sf` is a PSF-derived dependent format. Playback must resolve its `_lib` dependency safely.
3. For archive playback, materialize the **complete archive set**, preserving entry-relative paths, before constructing the decoder. Extracting only the requested `.mini2sf` is incorrect.
4. Metadata scan must be lightweight. If the chosen backend supports tag-only PSF loading, use it for scanning; reserve full emulator setup/dependency loading for playback.
5. Keep extension routing centralized in the plugin registry.
6. The native bridge must expose only app-needed operations: create/destroy, metadata, configure duration, render stereo PCM, seek, track-ended/frame position, metadata/error cleanup.
7. Treat malformed or missing dependencies as one precise per-item failure. Never let one bad file interrupt unrelated scan work.

## Phase 0: Select and Prove the Decoder Core

Evaluate a maintained 2SF-capable Nintendo DS audio core (likely `vio2sf` or an equivalent) before touching app routing.

Selection gates:

- Builds as a static library on Apple Silicon/macOS with the project toolchain.
- License is compatible with vendoring/distribution.
- Supports 2SF + mini2SF PSF dependency resolution.
- Can provide stereo PCM at a usable output rate or can be resampled predictably.
- Exposes or can be adapted to metadata tags: title, game/album, artist/composer, comment, `length`, `fade`, and `_lib`.
- Has deterministic teardown and does not leak file descriptors during repeated loads.

Create a small native proof of concept outside the app route first. It must open one standalone `.2sf`, one `.mini2sf` plus library, render a short PCM buffer, then destroy both cleanly.

Stop and document the blocker if no candidate meets these gates. Do not substitute raw NDS ROM emulation as a shortcut.

## Phase 1: Vendor and Bridge the Core

1. Add the selected upstream source under `vendor/` with provenance/license notes.
2. Extend `Package.swift` with build paths, static-library linkage, and a new C target, suggested name `C2SF`.
3. Add `Sources/C2SF/include/twosf_bridge.h` and native implementation.
4. Define an app-neutral metadata structure parallel to `lazyusf_metadata_t` / `highlycomplete_metadata_t`.
5. Define explicit ownership functions for every heap-returned string/error/metadata field.
6. Use a narrow handle API; do not expose emulator internals to Swift.

Suggested bridge operations:

```c
twosf_player_handle_t twosf_player_create(const char *path, int32_t sample_rate, char **error_message);
void twosf_player_destroy(twosf_player_handle_t handle);
int32_t twosf_inspect_metadata(const char *path, twosf_metadata_t *metadata, char **error_message);
int32_t twosf_player_read_metadata(twosf_player_handle_t handle, twosf_metadata_t *metadata, char **error_message);
int32_t twosf_player_configure(...);
int32_t twosf_player_render_s16(...);
int32_t twosf_player_seek_milliseconds(...);
int32_t twosf_player_track_ended(...);
int32_t twosf_player_played_frames(...);
void twosf_metadata_clear(twosf_metadata_t *metadata);
void twosf_error_message_free(char *error_message);
```

Use a dedicated Swift/native safety gate unless the selected core has been proven safe for concurrent bridge calls.

## Phase 2: Register Scan and Playback Routes

1. Add `2sf` and `mini2sf` to `GMEFormatSupport` as a dedicated set, suggested name `twoSFSupportedExtensions`.
2. Add a `twosf` `ScanPluginDescriptor` and handler in `ScanCoreHandlers`.
3. Add routing in `PlaybackDecoderRouting.swift`:
   - `TwoSFDecoder: AudioTrackDecoder`
   - `TwoSFFileInspector`
4. Map metadata to `TrackMetadata` with `Nintendo DS` as the fallback system.
5. Preserve existing timing policy: native `length`/`fade` when present; CocoaSpice Long Play otherwise.
6. Verify registry-derived behavior reaches folder scans, ZIP/7z filtering, M3U parsing, direct drops, and playlist imports without local special cases.

## Phase 3: Archive Dependency-Set Support

`ZipArchiveSupport` already has special complete-set handling for LazyUSF. Add equivalent behavior for the `twosf` route.

Requirements:

- Materialize the entire archive only once per archive scan/playback operation.
- Preserve nested archive entry paths exactly.
- Resolve `_lib` paths relative to the selected 2SF/mini2SF entry.
- Reject absolute paths and traversal outside the materialized root.
- Clean up through CocoaSpice’s archive cache lifecycle.
- Keep descriptor usage bounded. The prior JoshW fix explicitly closes stderr pipe endpoints after each archive subprocess; do not regress that behavior.

For scan metadata, only materialize the full set if the selected core requires dependent libraries to inspect tags. Prefer tag-only inspection if viable.

## Phase 4: Tests and Fixtures

Add minimal legal/redistributable fixtures or generate fixtures during tests. Required cases:

1. Standalone `.2sf` scans, exposes metadata, and starts at playback time zero.
2. `.mini2sf` resolves a sibling `_lib` and renders audio.
3. Missing `_lib` produces a focused metadata/playback failure, not a crash.
4. Tag parsing maps title, game, author, comment, length, and fade correctly.
5. ZIP and 7z archive sets with nested mini2SF/library paths resolve and play.
6. Archive path traversal in `_lib` is rejected.
7. Seek and frame accounting behave monotonically.
8. Repeated inspection/playback does not grow descriptor count.
9. Scan registry includes only `.2sf` and `.mini2sf`, never `.nds`.
10. Command-line scan probe handles a bounded real/synthetic 2SF directory with zero unexpected persistence failures.

Run at least:

```bash
swift test
git diff --check
./build.sh
```

Use the normal CocoaSpice command-line scan probe for a real NDS collection only after fixture coverage passes:

```bash
COCOASPICE_SCAN_PERSIST=1 bash ./scripts/scan-pipeline.sh <2sf-root>
```

## Rollout Criteria

Do not call the feature complete until all are true:

- Direct, M3U, folder, ZIP, and 7z 2SF/mini2SF flows work.
- Both standalone and dependent mini2SF playback begin at zero and seek correctly.
- Full-set archive dependency resolution is safe and cache-bounded.
- Failure logs identify the actual file and failure stage without cascading unrelated errors.
- A real collection scan completes without descriptor growth, bad file descriptors, database-open failures, or mass persistence errors.
- Documentation is updated after each implementation pass in the relevant `ai/subsystem-*` maps.

## Handoff Notes

This is a new decoder subsystem, not a trivial extension-list change. Start with the decoder-core proof before modifying CocoaSpice’s public routing. If the decoder cannot load mini2SF dependencies inside a materialized archive set, solve that bridge-level path behavior before adding scanner support.
