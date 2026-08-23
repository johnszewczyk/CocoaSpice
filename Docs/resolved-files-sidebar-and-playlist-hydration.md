# Resolved: Files Sidebar Loading and Playlist Hydration

## Status

Resolved in code and covered by regression tests on 2026-08-11.

Canonical current behavior and engineering constraints live in:

- [Database Browser](/Users/john/Downloads/Code/VGMMan/CocoaSpice/ai/subsystem-human/database-browser.md)
- [Library Browser Database](/Users/john/Downloads/Code/VGMMan/CocoaSpice/ai/subsystem-agent/library-browser-database.md)
- [Database Sidebar Presentation](/Users/john/Downloads/Code/VGMMan/CocoaSpice/ai/subsystem-agent/database-sidebar-presentation.md)

This report retains the measured closeout evidence for the original bug.

## Verified Behavior

- Files loading has one owner, `DatabaseSidebarLoader`, with explicit database-read and tree-index phases. Completion clears `isLoadingFiles` and `fileLoadingStatus` on the main actor.
- Files data remains cached until explicit invalidation. Switching modes or applying an unchanged empty search does not rebuild it.
- A source leaf is addressed by `root_id + path`. Archive leaves return every indexed archive member and subtrack for that source.
- The exact-source query uses `tracks_source_lookup_index`; it does not scan the full root to satisfy presentation ordering.
- Folder rows retain disclosure behavior and do not hydrate a playlist as a side effect.
- Database read failures are distinct from legitimate empty results and are shown in the sidebar with Retry.

## Performance Evidence

- The old dirty-projection fallback grouped the live JoshW root from `tracks` in about `11.86 s`.
- Reading the durable `file_sidebar_buckets` projection measured about `0.10 s`.
- A representative exact-source hydration query measured about `0.02 s` after using `tracks_source_lookup_index`.

The GENH console repair dirties only the Games projection because it does not change Files source paths or counts.

## Regression Coverage

- `fileSidebarArchiveLeafLoadsEveryIndexedMemberThroughTheQueue`
- `fileSidebarDatabaseFailureIsNotReportedAsAnEmptyPlaylist`
- `fileSidebarLegitimateEmptyResultRemainsSuccessful`
- `fileSidebarBucketsServeStoredSourceLeavesAndDirtyRootFallbacks`
- `databaseSidebarLoaderRetainsFilesUntilExplicitInvalidation`
- `databaseFileSidebarKeepsTheCachedTreeOnAnUnchangedEmptySearch`

## Database Publication Safety

Full rescans persist into a disabled staging root while the last committed sidebar remains readable. Both sidebar projections are built against the hidden root first; publish then moves the staged rows and prepared projections, records completion statistics, and removes the staging root in one short transaction. Cancellation, projection failure, or failure before publication deletes only staged rows. The primary startup connection removes abandoned staging roots after a crash, while secondary connections deliberately leave active stages alone. Incremental scans retain the existing changed-source transaction. Metrics report staging, publication, projection, and WAL growth separately.

## Relevant Code

- [DatabaseSidebarLoader.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/DatabaseSidebarLoader.swift)
- [LibraryDatabase.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase.swift)
- [LibraryDatabase+ReadQueries.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase+ReadQueries.swift)
- [PlaylistQueueLoader.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/PlaylistQueueLoader.swift)
