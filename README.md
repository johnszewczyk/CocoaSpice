# CocoaSpice

`CocoaSpice` is a native macOS game-music player built with SwiftUI, `AVAudioEngine`, `libgme`, `libvgm`, and `Highly Complete`.

## Layout

- Left pane: scanned database game list with sidebar search
- Right pane: editable playlist and queue
- Top toolbar: previous/play-pause/next
- Far-right titlebar: 20-bar live spectrum analyzer with customizable bar and cap colors

## Current Behavior

- Sidebar double-click behavior is configurable as `Set as Playlist` or `Add to Playlist`
- Selected playlist rows can export native AAC `.m4a` files with built-in macOS encoding
- Options opens with the standard `Command+,` shortcut

## CLI Workflow

Build the bundled app:

```bash
./build.sh
```

Launch it without Xcode:

```bash
./launch.sh
```

By default it will look for the library at:

`/Users/john/Documents/Code/SPC/spcsets_extracted`

Override that path for a launch with:

```bash
COCOASPICE_LIBRARY_ROOT="/path/to/spcsets_extracted" ./launch.sh
```

## Notes

- `libgme` is bundled into `dist/CocoaSpice.app/Contents/Frameworks`
- `libvgm` is vendored under `vendor/libvgm` and built statically into the app during `./build.sh`
- `Highly Complete` is provided by a local bridge target backed by vendored `mGBA` plus `psflib`
- the build currently expects Homebrew `game-music-emu` at `/opt/homebrew`
- the build currently expects `cmake` to be installed locally so `scripts/build-libvgm.sh` and `scripts/build-mgba.sh` can produce the static backend libraries
- the app now targets the current macOS generation in SwiftPM rather than macOS 14
- the UI is intentionally native and minimal rather than custom-skinned
