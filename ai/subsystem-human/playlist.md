# Playlist

## Display

- Display: file metadata in a headed table.
- Columns: transport, favorite, index, file, title, game, author, system, path, and length. The favorite glyph is immediately before # and lights for favorited tracks.
- Columns: missing metadata falls back to useful file or folder text.
- Columns: includes a user-configurable Size column for direct files; archive entries show an unavailable marker until archive-entry sizing is modeled separately.
- Metadata: catalog-backed queues display only the fields published in the selected catalog; incomplete fields remain incomplete until MediaScanner republishes them.
- Directly opened files have no catalog metadata. Their title and game cells use filename and folder display fallbacks; author, system, and duration remain unknown.
- Columns: visible columns auto-size after queue publication without changing the current row selection.
- Columns: drag-and-drop resize.
- Columns: double-click a divider to auto-size to current content.
- Columns: the header menu can auto-size one column or all visible columns.
- Columns: Path shows the complete filesystem source path. Archive tracks retain their member provenance as `archive-path#member-path`.
- Font: an Interface preference can render all playlist text columns in a monospaced font.

## Selection

- Selection: standard Shift and Command multi-selection.
- Selection: selected rows can be dragged together.
- Selection: moving a single selected row glides its background to the next row over 100 ms; multi-selection remains immediate.

## Activation

- Rows: double-click starts playback.
- Rows: Return starts playback of the primary selected row.
- Rows: transport button plays or stops the row.
- Favorites: Command-D toggles the selected track; the favorite glyph toggles the clicked track directly.
- Queue: cut, paste, delete, move, and drag-reorder.
- Context menu: `Export AAC` renders the clicked playlist track through bundled VGMBoy into the
  configured AAC Export Folder. It uses the active Long Play/end-fade timing and does not interrupt
  current playback. The filename begins with the catalog track title, or the displayed playlist name
  when that title is absent.
- Files: Finder drops add supported files, folders, and ZIP, 7z, or RSN archives.
- Files: queueing a folder expands supported archive members and multi-track containers into playlist leaves.
- Playlists: dropping an `.m3u` appends its playable entries to the current queue.
- Playlists: `Open Playlist…` and opening an `.m3u` from Finder replace the current queue.

## Persistence

- Playlists: save and load as `.m3u`.
- Playlists: preserve multi-track identity.

## Files

- [PlaylistTableView.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/PlaylistTableView.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
