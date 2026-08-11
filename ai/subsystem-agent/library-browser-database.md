# Library Browser Database

## Scope

- Database-mode library browsing.
- Game-list activation.
- Database-mode queue loading.

## Current State

- Track identity is root-scoped: `tracks` is unique on root, source path, archive member, and subtrack index. This permits an intentionally overlapping root (for example, `JoshW` and `JoshW/USF`) to index the same archive without turning valid tracks into persistence failures.

- The sidebar database browser is a scanned persistent browser, not a raw filesystem tree.
- A full scan writes bounded committed batches into a disabled staging root while sidebar readers continue seeing the previous root and projections. Publish reassigns the staged rows to the real root in one short transaction, then refreshes the projections; cancellation removes only the staging root. Incremental scans retain one outer WAL transaction because they write only selected changed sources.
- The normal sidebar displays a dense flat list of games derived from scanned metadata. Optional System Mode groups the same game leaves below expandable root-level system rows.
- Sidebar game buckets and game-row identities are root-scoped: `root_id + game title + system`. This keeps same-title/same-system entries from separate library paths distinct and makes game activation bind the full `tracks_browser_bucket_index` key.
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
- `tracks.browser_game` and `tracks.browser_system` are persisted alongside scan results and are activated with `root_id`; do not rebuild the game bucket from `track_metadata` in a selection query, omit the selected root, or turn every sidebar activation into a whole-library scan.
- `LibraryConsoleResolver` owns persisted sidebar-console selection. Decoder routing remains independent: vgmstream container defaults are not embedded console tags, so resolve their console from the nearest recognized folder below the scan root. Keep intermediate format folders such as KSS, VGM, and VGZ out of that decision.
- `DatabaseFileItem` groups scanned track rows by `root_id + source path`; `tracks_file_tree_index` supports the database-only Files tree. Archive members never become filesystem tree leaves: their archive source is the leaf and activation loads its indexed members through the matching root.
- The Games browser has a separate covering `tracks_game_sidebar_index` for grouped startup reads and unlinked-source filtering. Schema 19 upgrades in place to schema 20 by adding only the scan-staging registry; older unsupported schemas are reset.
- The Files browser has the durable root-scoped `file_sidebar_buckets` projection (`root_id + source path`), carrying folder, archive, and playable-track count. Normal reads must use it rather than grouping `tracks`; a dirty enabled root uses the direct grouping only until its projection rebuilds. A metadata-only repair (such as correcting a vgmstream console) may invalidate game buckets but must not dirty this file projection.
- File-path activation resolves the scanned playable leaves for that file path, so NSF containers contribute subtracks rather than the raw container file.
- File-tree file selection stores source-file IDs. A normal folder-row selection toggles expansion and does not alter the playlist or file selection.
- A file-tree folder double-click resolves tracks by the indexed folder path and all descendant folder paths. File activation replaces the playlist only on double-click or Return.
- File-tree drags use the app-owned `databaseFileSidebarDragType` payload. The playlist consumes selected file rows through the library database and appends them; it must not treat the drag as a filesystem import or rescan archive members.
- Database-backed queue loading now lives in a dedicated queue-loader helper rather than inline throughout the main view model.
- Sidebar snapshot reads never translate a SQLite failure into an empty library. `DatabaseSidebarLoader` retains the last valid snapshot, publishes the exact failure, and exposes Retry in the sidebar.
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
- [LibraryConsoleResolver.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryConsoleResolver.swift)
- [MainView.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/MainView.swift)
- [PlaylistQueueLoader.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaylistQueueLoader.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
