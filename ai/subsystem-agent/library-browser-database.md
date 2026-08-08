# Library Browser Database

## Scope

- Database-mode library browsing.
- Game-list activation.
- Database-mode queue loading.

## Current State

- Track identity is root-scoped: `tracks` is unique on root, source path, archive member, and subtrack index. This permits an intentionally overlapping root (for example, `JoshW` and `JoshW/USF`) to index the same archive without turning valid tracks into persistence failures.

- The sidebar database browser is a scanned persistent browser, not a raw filesystem tree.
- The normal sidebar displays a dense flat list of games derived from scanned metadata. Optional System Mode groups the same game leaves below expandable root-level system rows.
- Sidebar game buckets are keyed by `game title + system`, not title alone, so cross-platform name collisions stay separate.
- The scanned database now stores one playable row per discovered subtrack for loose or archived multi-track `libgme` containers such as NSF, GBS, and KSS.
- Archive scans expand playable members from ZIP, 7z, and RSN containers, retaining archive path plus member path for later playback materialization.
- SPC members use libgme metadata during indexing; multi-track archive members are materialized and inspected during indexing so their playlist/database leaves carry track counts, indices, and playback durations.
- Metadata-free archive rows group by archive path, so each RSN/ZIP/7z set appears as its own database item instead of disappearing into the containing folder.
- Database rows support native multiselect.
- Database double-click follows the configured sidebar double-click behavior.
- Database `Return` activates the current selection.
- Database multi-row `Return` replaces the playlist with the combined selection.
- Games, file rows, and file-tree folder selections enter `PlaylistQueueLoader` as one typed `LibraryPlaylistLoadRequest`; the view model owns one queue-build lifecycle and applies the loaded playlist identically for replace or enqueue.
- Game activation loads playable leaves from the scanned database rather than rescanning the filesystem.
- `tracks.browser_game` and `tracks.browser_system` are persisted alongside scan results and indexed as the activation lookup key. Do not rebuild the game bucket from `track_metadata` in a selection query; that turns every sidebar activation into a whole-library scan.
- `DatabaseFileItem` groups scanned track rows by `root_id + source path`; `tracks_file_tree_index` supports the database-only Files tree. Archive members never become filesystem tree leaves: their archive source is the leaf and activation loads its indexed members through the matching root.
- The Games browser has a separate covering `tracks_game_sidebar_index` for grouped startup reads and unlinked-source filtering. The current schema creates it once before data exists; a noncurrent schema is reset instead of being migrated at launch.
- File-path activation resolves the scanned playable leaves for that file path, so NSF containers contribute subtracks rather than the raw container file.
- File-tree file selection stores source-file IDs. A normal folder-row selection toggles expansion and does not alter the playlist or file selection.
- A file-tree folder double-click resolves tracks by the indexed folder path and all descendant folder paths. File activation replaces the playlist only on double-click or Return.
- File-tree drags use the app-owned `databaseFileSidebarDragType` payload. The playlist consumes selected file rows through the library database and appends them; it must not treat the drag as a filesystem import or rescan archive members.
- Database-backed queue loading now lives in a dedicated queue-loader helper rather than inline throughout the main view model.
- Sidebar context-menu invocation does not mutate selection or trigger playlist-follow activation by itself. File-tree menu actions carry the clicked row's typed file/folder payload rather than reading the table selection, because folder rows are deliberately nonselectable.

## Rules

- Keep database browsing rooted in scanned metadata, not direct filesystem tree rendering.
- Keep activation and queue-loading behavior explicit.
- Treat current game rows as aggregations over playable leaves, not guaranteed one-file-one-track groupings.

## Files

- [DatabaseSidebarPresentation.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/DatabaseSidebarPresentation.swift)
- [LibraryDatabase.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase.swift)
- [LibraryDatabase+Schema.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase+Schema.swift)
- [LibraryModels.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryModels.swift)
- [MainView.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/MainView.swift)
- [PlaylistQueueLoader.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaylistQueueLoader.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
