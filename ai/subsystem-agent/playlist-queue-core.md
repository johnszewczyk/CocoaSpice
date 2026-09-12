# Playlist Queue Core

## Scope

- Active queue surface.
- Playlist row activation.
- Queue editing surface behavior.

## Current State

- The right pane playlist is the active editable queue.
- The playlist is shown directly without a second search/filter field or hidden filtered state; database search remains in the sidebar.
- Rows use the versioned, delimiter-safe `pt1` playable identity: source path,
  optional archive member path, and zero-based subtrack index. The format is
  owned by shared `PlaylistIdentityCore`; metadata and display values are
  excluded, so catalog metadata can never replace the row.
- Double-click on a row starts playback of that row.
- `Return` starts playback of the primary selected row.
- The row transport button plays that row, or stops it if that row is the active playing track.
- Playlists can be saved to `.m3u` and loaded from `.m3u`.
- Playlist `.m3u` save and load preserve multi-track container identity through `#COCOASPICE:` metadata lines.
- Finder drops onto the playlist append supported files, folders, and supported
  `.zip`, `.7z`, `.lha`, `.rsn`, or TAR+Zstandard archives into the queue. LHA
  Amiga members may require complete-set materialization; companion files remain
  dependency data rather than additional queue rows.
- Archive drops expand supported members before queue mutation.
- Directly imported files and archive members enter as one queue row. Catalog-backed queues retain their scanner-published subtrack identity.
- Folder queueing uses the same archive/member and multi-track expansion path, so queued folders do not leave supported archive members behind.
- M3U drops decode relative paths from the playlist directory and append playable entries to the current queue.
- Menu and Finder opening of an M3U replaces the current queue through the same explicit open path.
- Queue edits include cut, paste, delete, move, and drag-reorder.
- Direct Finder imports use filename-derived display fallbacks; they do not inspect media for metadata.
- Database-backed queues use only their published metadata snapshot. They do not inspect media or materialize archives during hydration; VGMBoy receives the selected playable item only when playback begins.
- Database-backed queue loads distinguish a successful empty result from a SQLite failure. A query failure is logged and shown in status without replacing or partially updating the current queue; combined file/folder selections are applied atomically only after every query succeeds.
- Queue publication computes its column hints from the stored metadata snapshot and does not schedule background hydration.

## Rules

- Queue edits never mutate files on disk.
- Queue edits should not stop the currently playing track by themselves.
- Archive import is read-only: it enumerates members for queue identity without mutating the source archive.
- Keep the playing glyph attached to the actual playing track, not the most recently selected row.
- Never add decoder-backed metadata repair or hydration to the playlist path.
- Do not perform source-file I/O from table cells or automatic column sizing; database queue publication is in-memory after its query completes.
- Treat decoder-driven subtrack enumeration as an explicit format capability rather than a playlist extension special case.

## Files

- [PlaylistTableView.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/PlaylistTableView.swift)
- [PlaylistM3UCodec.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/PlaylistM3UCodec.swift)
- [PlaylistQueueLoader.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/PlaylistQueueLoader.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
- [LibraryModels.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/LibraryModels.swift)
- [Cross-app playlist activation fixture](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Tests/CocoaSpiceTests/cross-app-playlist-activation-v1.json)
