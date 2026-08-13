# Library Browser Database

## Scope

- Database-mode library browsing.
- Game-list activation.
- Database-mode queue loading.

## Current State

- `LibraryDatabase.configuredDatabaseURL` owns launch-time path selection. Options validates a selected file through `MediaScannerKit.CanonicalCatalog`, persists only an absolute standardized path, and requires restart rather than replacing a live connection.
- CocoaSpice's production connection uses `SQLITE_OPEN_READONLY` plus `PRAGMA query_only`, requires schema 23, never initializes the scan controller, and skips playlist-metadata writeback. Library-root, scan, console-identity rewrite, reset, and unlinked-cleanup actions are disabled. The legacy writer implementation remains compiled only while its persistence and decoder code moves into MediaScanner; it is not opened by the app's production path.
- Track identity is root-scoped: `tracks` is unique on root, source path, archive member, and subtrack index. This permits an intentionally overlapping root (for example, `JoshW` and `JoshW/USF`) to index the same archive without turning valid tracks into persistence failures.

- The sidebar database browser is a scanned persistent browser, not a raw filesystem tree.
- The retained legacy scan implementation writes complete physical-source checkpoints into a disabled staging root while readers continue seeing the previous root and projections. It is not started by CocoaSpice during the MediaScanner extraction.
- Interrupted-stage recovery is a primary-connection startup responsibility. It retains stages containing completed source checkpoints, marks formerly active work paused, and removes empty/legacy stages. Short-lived scan, maintenance, and root-management connections must never run recovery, because they can coexist with an active scan.
- Scan metrics separate staging, publication, and projection time and record WAL growth. Use those measurements before replacing the shadow-root design with broader generation-scoped queries.
- The normal sidebar displays a dense flat list of games derived from scanned metadata. The visible `Group by Console` option, stored internally as `sidebarSystemMode`, groups the same game leaves below expandable root-level console rows.
- Sidebar game buckets and game-row identities are root-scoped: `root_id + game title + system`. This keeps same-title/same-system entries from separate library paths distinct and makes game activation bind the full `tracks_browser_bucket_index` key.
- The scanned database now stores one playable row per discovered subtrack for loose or archived multi-track `libgme` containers such as NSF, GBS, and KSS.
- Archive scans expand playable members from ZIP, 7z, and RSN containers, retaining archive path plus member path for later playback materialization.
- SPC members use libgme metadata during indexing; multi-track archive members are materialized and inspected during indexing so their playlist/database leaves carry track counts, indices, and playback durations.
- Sidebar game identity uses an inspected game tag when present. Metadata-free archive rows use the archive filename without its archive suffix; metadata-free loose rows use their immediate parent-folder name. Absolute source paths are never persisted as visible game labels.
- Database rows support native multiselect.
- Database double-click follows the configured sidebar double-click behavior.
- Database `Return` activates the current selection.
- Database multi-row `Return` replaces the playlist with the combined selection.
- Games, file rows, and file-tree folder selections enter `PlaylistQueueLoader` as one typed `LibraryPlaylistLoadRequest`; the view model owns one queue-build lifecycle and applies the loaded playlist identically for replace or enqueue.
- Game activation loads playable leaves from the scanned database rather than rescanning the filesystem.
- `tracks.browser_game` and `tracks.browser_system` are persisted alongside scan results and are activated with `root_id`; do not rebuild the game bucket from `track_metadata` in a selection query, omit the selected root, or turn every sidebar activation into a whole-library scan.
- `LibraryConsoleResolver` owns persisted sidebar identity and executes the shared CocoaSpice/SPCBoy identity contract. A usable game tag wins; otherwise archives use the outer filename without a recognized terminal console tag and loose files use their immediate parent. Console collection mode uses a recognized terminal filename tag, then the nearest recognized console ancestor, then normalized embedded metadata; `Prefer Embedded Console Tags` selects normalized metadata first. Unknown folders never become console identity. Decoder routing remains independent, so a vgmstream container label cannot override collection identity.
- Console-tag source changes that require rewriting stored identity are unavailable in CocoaSpice's query-only mode. Existing schema-23 buckets remain readable; MediaScanner must own future rewrites.
- `DatabaseFileItem` groups scanned track rows by `root_id + source path`; `tracks_file_tree_index` supports the database-only Files tree. Archive members never become filesystem tree leaves: their archive source is the leaf and activation loads its indexed members through the matching root.
- The Games browser has a separate covering `tracks_game_sidebar_index` for grouped startup reads and unlinked-source filtering. Schemas 16 through 22 upgrade in place to schema 23 by applying only their missing index, data-repair, resumable-scan, scanner-policy, and sidebar-identity steps. Other unsupported schemas are reset.
- The Files browser has the durable root-scoped `file_sidebar_buckets` projection (`root_id + source path`), carrying folder, archive, and playable-track count. Normal reads must use it rather than grouping `tracks`; a dirty enabled root uses the direct grouping only until its projection rebuilds. A metadata-only repair (such as correcting a vgmstream console) may invalidate game buckets but must not dirty this file projection.
- File-path activation resolves the scanned playable leaves for that file path, so NSF containers contribute subtracks rather than the raw container file.
- File-tree file selection stores source-file IDs. A normal folder-row selection toggles expansion and does not alter the playlist or file selection.
- A file-tree folder double-click resolves tracks by the indexed folder path and all descendant folder paths. File activation replaces the playlist only on double-click or Return.
- File-tree drags use the app-owned `databaseFileSidebarDragType` payload. The playlist consumes selected file rows through the library database and appends them; it must not treat the drag as a filesystem import or rescan archive members.
- Database-backed queue loading now lives in a dedicated queue-loader helper rather than inline throughout the main view model.
- Sidebar snapshot reads never translate a SQLite failure into an empty library. `DatabaseSidebarLoader` retains the last valid snapshot, publishes the exact failure, and exposes Retry in the sidebar.
- Sidebar context-menu invocation does not mutate selection or trigger playlist-follow activation by itself. File-tree menu actions carry the clicked row's typed file/folder payload rather than reading the table selection, because folder rows are deliberately nonselectable.
- `SidebarViewResolution` resolves the stored Games/Files selection and trimmed query into Games, Files, or temporary Search. Search always uses Games content, and clearing it reveals the latest stored selection without rewriting it.

## Rules

- Keep database browsing rooted in scanned metadata, not direct filesystem tree rendering.
- Keep activation and queue-loading behavior explicit.
- Treat current game rows as aggregations over playable leaves, not guaranteed one-file-one-track groupings.

## Files

- [DatabaseSidebarPresentation.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/DatabaseSidebarPresentation.swift)
- [DatabaseSidebarLoader.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/DatabaseSidebarLoader.swift)
- [LibraryDatabase.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase.swift)
- [LibraryDatabase+Schema.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase+Schema.swift)
- [LibraryDatabase+GameSidebarBuckets.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase+GameSidebarBuckets.swift)
- [LibraryDatabase+FileSidebarBuckets.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase+FileSidebarBuckets.swift)
- [LibraryModels.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryModels.swift)
- [LibraryConsoleResolver.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryConsoleResolver.swift)
- [Cross-app identity fixture](/Users/john/Downloads/Code/CocoaSpice/Tests/CocoaSpiceTests/cross-app-library-identity-v1.json)
- [Cross-app search-view fixture](/Users/john/Downloads/Code/CocoaSpice/Tests/CocoaSpiceTests/cross-app-sidebar-search-view-v1.json)
- [Cross-app playlist activation fixture](/Users/john/Downloads/Code/CocoaSpice/Tests/CocoaSpiceTests/cross-app-playlist-activation-v1.json)
- [Sister-app conformance contract](/Users/john/Downloads/Code/DocMan/Docs/cocoaspice-spcboy-conformance.md)
- [MainView.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/MainView.swift)
- [PlaylistQueueLoader.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaylistQueueLoader.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
