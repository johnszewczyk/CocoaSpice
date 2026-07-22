# Playlist

## Display

- Display: file metadata in a headed table.
- Columns: transport, index, file, title, game, author, system, path, and length.
- Columns: missing metadata falls back to useful file or folder text.
- Columns: includes a user-configurable Size column for direct files; archive entries show an unavailable marker until archive-entry sizing is modeled separately.
- Metadata: playlist inspection fills available metadata, including SPC duration, while the playlist remains usable.
- Columns: visible columns auto-size after queue population and final metadata hydration without changing the current row selection.
- Columns: drag-and-drop resize.
- Columns: double-click a divider to auto-size to current content.
- Columns: the header menu can auto-size one column or all visible columns.
- Columns: Path shows the complete filesystem source path. Archive tracks retain their member provenance as `archive-path#member-path`.

## Selection

- Selection: standard Shift and Command multi-selection.
- Selection: selected rows can be dragged together.

## Activation

- Rows: double-click starts playback.
- Rows: Return starts playback of the primary selected row.
- Rows: transport button plays or stops the row.
- Queue: cut, paste, delete, move, and drag-reorder.
- Files: Finder drops add supported files, folders, and ZIP, 7z, or RSN archives.
- Files: queueing a folder expands supported archive members and multi-track containers into playlist leaves.
- Playlists: dropping an `.m3u` appends its playable entries to the current queue.
- Playlists: `Open Playlist…` and opening an `.m3u` from Finder replace the current queue.

## Persistence

- Playlists: save and load as `.m3u`.
- Playlists: preserve multi-track identity.

## Files

- [PlaylistTableView.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaylistTableView.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
