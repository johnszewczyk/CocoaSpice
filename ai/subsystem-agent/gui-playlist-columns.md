# GUI Playlist Columns

## Scope

- Playlist column set.
- Column fallback text.
- Column persistence and autosizing.

## Current State

- Current columns are favorite, index, file, title, game, author, system, path, and length. Favorite is fixed immediately before index, uses a star header, and is user-hideable but not reorderable. The obsolete Play/Stop transport column is not part of the table.
- Metadata-backed columns fall back to filename or parent-folder text when metadata is absent.
- The Path column uses `TrackItem.fullPathText`: a full filesystem path for ordinary files and `archive-path#member-path` for archive members.
- Column visibility, order, and width are persisted in `UserDefaults`.
- Playlist font size, text color, and monospaced styling are persisted with playback preferences. The native table reloads cells, adjusts row height, and remeasures columns when its font size or family changes.
- Sort column and sort direction are persisted separately from column layout state.
- User-reorderable columns exclude the fixed-position favorite column; every column, including favorite, can be hidden, and at least one column remains visible.
- Visible columns automatically size after queue population and again when final metadata width hints change. The resize is coalesced, defaults to ten ease-in-out updates over 200 ms, follows the Interface animation preference, and does not reload rows or change selection.
- Double-clicking a header divider autosizes that column to current content.
- The header context menu exposes both per-column and all-visible-column autosizing.

## Rules

- Keep the favorite column fixed immediately before the index column. Do not reintroduce a row-level Play/Stop control; playback is owned by playlist activation and the main transport.
- Keep persisted column behavior aligned with the real table state.
- Keep sort persistence separate from broader preference writes.
- Persist final auto-sized widths once, rather than writing every intermediate resize step.
- Treat column fallback text as playlist-display behavior, not metadata mutation.

## Files

- [PlaylistTableView.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/PlaylistTableView.swift)
- [PlaylistTableAutoSizer.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/PlaylistTableAutoSizer.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
