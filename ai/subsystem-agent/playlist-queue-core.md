# Playlist Queue Core

## Scope

- Active queue surface.
- Playlist row activation.
- Queue editing surface behavior.

## Current State

- The right pane playlist is the active editable queue.
- Rows are keyed by playable identity, which is file path plus subtrack index when needed.
- Rows can also be keyed by `archive path + archive member path + subtrack index` for ZIP-imported tracks.
- Double-click on a row starts playback of that row.
- `Return` starts playback of the primary selected row.
- The row transport button plays that row, or stops it if that row is the active playing track.
- Playlists can be saved to `.m3u` and loaded from `.m3u`.
- Playlist `.m3u` save and load preserve multi-track container identity through `#COCOASPICE:` metadata lines.
- Finder drops onto the playlist append supported files, folders, and `.zip`, `.7z`, or `.rsn` archives into the queue.
- Archive drops expand supported members before queue mutation, then expand multi-track members such as `nsf` into one playlist leaf per subtrack.
- Folder queueing uses the same archive/member and multi-track expansion path, so queued folders do not leave supported archive members behind.
- M3U drops decode relative paths from the playlist directory and append playable entries to the current queue.
- Menu and Finder opening of an M3U replaces the current queue through the same explicit open path.
- Queue edits include cut, paste, delete, move, and drag-reorder.

## Rules

- Queue edits never mutate files on disk.
- Queue edits should not stop the currently playing track by themselves.
- Archive import is read-only: it materializes members for inspection/queue identity without mutating the source archive.
- Keep the playing glyph attached to the actual playing track, not the most recently selected row.

## Files

- [PlaylistTableView.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaylistTableView.swift)
- [PlaylistM3UCodec.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaylistM3UCodec.swift)
- [PlaylistQueueLoader.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaylistQueueLoader.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
- [LibraryModels.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryModels.swift)
