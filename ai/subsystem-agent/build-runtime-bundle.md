# Build Runtime Bundle

## Scope

- SwiftPM target graph.
- App bundle assembly.
- Runtime `libgme` and `libopenmpt` packaging.
- Local static `libvgm` build bootstrap.
- Local static `mGBA` build bootstrap for `Highly Complete`.
- Local launch behavior.

## Current State

- SwiftPM builds the executable into `.build`.
- `Package.swift` now targets macOS 26 for the app build.
- `Package.swift` now links a small local `CLibVGM` bridge target against static `libvgm` archives built under `.build/libvgm`.
- `Package.swift` now also links `CHighlyComplete` against a local static `mGBA` build under `.build/mgba`.
- `Package.swift` links `CPlayPSF` against the headless Play! PSF-family archive under `.build/play-psf` and links `CVGMStream` against the static vgmstream archive plus FFmpeg and Vorbis runtime libraries.
- `Package.swift` also defines the same `mGBA` feature flags for `CHighlyComplete` that the vendored static library was built with, then includes generated `mgba/flags.h` so the bridge sees the same ABI shape as the native archive.
- `build.sh` assembles a standalone app bundle under `dist/`.
- `build.sh` runs `scripts/build-libvgm.sh` before `swift build` so the vendored `libvgm` archives exist when SwiftPM links the executable.
- `build.sh` also runs `scripts/build-mgba.sh` so the vendored `mGBA` archive exists when SwiftPM links the `Highly Complete` backend.
- `build.sh` runs the bounded `scripts/build-play-psf.sh` and `scripts/build-vgmstream.sh` helpers before SwiftPM links their bridge targets. The vgmstream helper uses a SHA-256 input stamp and returns without CMake work when its vendored commit, dirty/untracked source inputs, compatibility patch, helper/configuration, compiler/CMake, and FFmpeg/Vorbis dependency versions are unchanged. Set `COCOASPICE_REBUILD_VGMSTREAM=1` to force its configure/build step.
- `build.sh` stages the `.app` in a temporary directory outside the project tree, copies `libgme.0.dylib` into the bundle, rewrites install names, clears recursive macOS extended attributes before and after signing, then copies the verified bundle back into `dist/`.
- `build.sh` also stages `libopenmpt` and its non-system runtime dylibs in `Contents/Frameworks`, then rewrites their mutual install names before signing.
- `build.sh` stages FFmpeg's directly linked components and recursively bundles their non-system Homebrew dylib closure, rewriting each bundled load path before signing. This supplies vgmstream's ATRAC3/MSF support without relying on a developer-installed FFmpeg at runtime.
- `launch.sh` invokes `build.sh` before launch.
- `launch.sh` writes app stdout or stderr to `/tmp/CocoaSpice.log`.
- `launch.sh` exports `COCOASPICE_LIBRARY_ROOT`, defaulting to the sibling `spcsets_extracted` path when unset.
- Launch restores prior user state first, then falls back to `COCOASPICE_LIBRARY_ROOT` only when the launch helper provides it.

## Rules

- Keep bundle assembly explicit.
- Do not rely on system-global `libgme` at runtime.
- Do not rely on system-global `libopenmpt`, `libmpg123`, `libogg`, or `libvorbis` at runtime.
- Keep `libvgm` statically linked so the app does not need a second third-party runtime dylib in the bundle.
- Keep `mGBA` statically linked as a backend dependency of `Highly Complete`; it is not a separate runtime app feature.
- Keep the bridge compile-time feature flags aligned with the vendored `mGBA` archive build; mismatched flags can corrupt `mCore` layout and crash playback immediately.
- Keep the app deployment target aligned with the linked `libgme` build target to avoid spurious linker-version mismatch warnings.
- Keep launch behavior aligned with restore behavior in app state.

## Files

- [Package.swift](/Users/john/Downloads/Code/CocoaSpice/Package.swift)
- [build.sh](/Users/john/Downloads/Code/CocoaSpice/build.sh)
- [launch.sh](/Users/john/Downloads/Code/CocoaSpice/launch.sh)
- [scripts/build-libvgm.sh](/Users/john/Downloads/Code/CocoaSpice/scripts/build-libvgm.sh)
- [scripts/build-mgba.sh](/Users/john/Downloads/Code/CocoaSpice/scripts/build-mgba.sh)
- [scripts/build-play-psf.sh](/Users/john/Downloads/Code/CocoaSpice/scripts/build-play-psf.sh)
- [scripts/build-vgmstream.sh](/Users/john/Downloads/Code/CocoaSpice/scripts/build-vgmstream.sh)
- [Resources/Info.plist](/Users/john/Downloads/Code/CocoaSpice/Resources/Info.plist)
- [Sources/CGME/shim.h](/Users/john/Downloads/Code/CocoaSpice/Sources/CGME/shim.h)
