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
- `PlayerViewModel` remains the authoritative implementation of playlist,
  playback-policy, catalog-browser, cache, and persisted-settings behavior.
- The native `OptionsView` owns `NSOpenPanel` presentation only. It passes the
  chosen URL to `PlayerViewModel.selectLibraryDatabase(at:)`, the same
  path-taking action exposed by the control surface.

## Current Surface

- `CocoaSpiceFrontendSurface.v1` declares the available `options` and
  `main_playback` features.
- `CocoaSpiceOptionsSnapshot` includes every current Options preference,
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

## Deliberate Boundary

- Playlist tables, database/file sidebar selection, and AppKit-specific
  keyboard/drag-drop behavior still bind directly to `PlayerViewModel`.
  They need their own selection/query contract before a second full skin can
  replace the native main shell.
- CocoaSpice remains read-only with respect to MediaScanner catalogs. The
  control surface validates a selected catalog path but never scans, writes,
  migrates, or enriches it.

## Files

- [CocoaSpiceFrontendControlSurface.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/CocoaSpiceFrontendControlSurface.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
