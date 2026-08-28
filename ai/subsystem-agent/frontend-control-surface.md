# Frontend Control Surface

## Scope

The skin-neutral, in-process presentation boundary for CocoaSpice. It is a
typed Swift interface now and its snapshot/command values are Codable so a
future WebKit bridge can carry the exact same values without SwiftUI or AppKit
knowledge.

## Ownership

- `CocoaSpiceOptionsControlSurface` owns the Options query/command boundary.
- `CocoaSpiceMainPlaybackControlSurface` owns the main transport and
  playback-policy query/command boundary.
- `PlayerViewModel` orchestrates playback and catalog behavior. Typed
  coordinators own frontend preferences, favorites, local browsing, and queue
  state so those domains no longer live as undifferentiated model storage.
- The native `OptionsView` owns `NSOpenPanel` presentation only. It passes the
  chosen URL to `PlayerViewModel.selectLibraryDatabase(at:)`, the same
  path-taking action exposed by the control surface.
- Native Options presents CocoaSpice-owned settings separately from the
  VGMBoy Remote Interface settings. Path values are selectable full-width
  readouts; browsing remains a native window concern and playback commands
  remain in the typed control boundary.

## Current Surface

- `CocoaSpiceFrontendSurface.v1` declares the available `options` and
  `main_playback` features and carries the canonical `VGMBoyEndpointSurface`
  from `VGMBoyEndpointCore`.
- `CocoaSpiceOptionsSnapshot` includes the shared `FrontendOptionsManifest`,
  typed interface/window preferences, every current CocoaSpice preference,
  catalog/cache presentation value, and read-only playback diagnostic value.
- `CocoaSpiceOptionsCommand` changes those options and performs each
  non-window-specific Options action. It does not accept catalog rows,
  decoder metadata, playback paths, or scanner work.
- The snapshot/command contract includes the AAC export folder. Native CocoaSpice presents its
  folder chooser with `NSOpenPanel`; a future skin supplies the chosen folder path through the
  same `selectAACExportDirectory` command. Export itself remains a playlist action routed to
  VGMBoy, not an Options-side encoder.
- `CocoaSpiceMainPlaybackSnapshot` and `CocoaSpiceMainPlaybackCommand` cover
  the visible transport, seek, Long Play, repeat, and random controls.
- A caller queries a fresh snapshot after a command. There is no WebKit
  message bridge or alternate renderer in this repository yet.
- CocoaSpice and SPCBoy WK consume the same VGMBoy endpoint capability map;
  app-specific control surfaces may expose fewer UI features, but they must
  not rename or reinterpret the shared endpoint operations.
- AppKit windows carry explicit `FrontendWindowRole` identifiers. Window-level
  policy never depends on localized titles.

## Deliberate Boundary

- Playlist tables, database/file sidebar selection, and AppKit-specific
  keyboard/drag-drop behavior still bind directly to `PlayerViewModel`.
  They need their own selection/query contract before a second full skin can
  replace the native main shell.
- CocoaSpice remains read-only with respect to ScanSong catalogs. The
  control surface validates a selected catalog path but never scans, writes,
  migrates, or enriches it.

## Files

- [CocoaSpiceFrontendControlSurface.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/CocoaSpiceFrontendControlSurface.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
- [FrontendPreferencesCoordinator.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/FrontendPreferencesCoordinator.swift)
- [FavoritesCoordinator.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/FavoritesCoordinator.swift)
- [LocalBrowserCoordinator.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/LocalBrowserCoordinator.swift)
- [PlaylistQueueCoordinator.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/PlaylistQueueCoordinator.swift)
