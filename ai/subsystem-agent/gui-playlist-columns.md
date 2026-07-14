# GUI Playlist Columns

## Scope

- Playlist column set.
- Column fallback text.
- Column persistence and autosizing.

## Current State

- Current columns are transport, index, file, title, game, author, system, path, and length.
- Metadata-backed columns fall back to filename or parent-folder text when metadata is absent.
- Column visibility, order, and width are persisted in `UserDefaults`.
- Sort column and sort direction are persisted separately from column layout state.
- User-reorderable columns exclude the fixed transport column.
- Double-clicking a header divider autosizes that column to current content.

## Rules

- Keep the transport column fixed.
- Keep persisted column behavior aligned with the real table state.
- Keep sort persistence separate from broader preference writes.
- Treat column fallback text as playlist-display behavior, not metadata mutation.

## Files

- [PlaylistTableView.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaylistTableView.swift)
- [PlaylistTableAutoSizer.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaylistTableAutoSizer.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
