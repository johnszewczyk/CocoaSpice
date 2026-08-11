# Resolved: Files Sidebar Loading and Playlist Hydration

## Status

**Resolved in code and covered by regression tests (2026-08-11).**

The Files sidebar now completes its background load without requiring window focus, and activating an indexed source hydrates the playlist directly from SQLite. Games and Files both use the scanned database; neither activation path walks the source filesystem.

## Fixed behavior

- Files loading has one owner, `DatabaseSidebarLoader`, with explicit database-read and tree-index phases. Completion clears `isLoadingFiles` and `fileLoadingStatus` on the main actor.
- Files data remains cached until explicit invalidation. Switching modes or applying an unchanged empty search does not rebuild it.
- A source leaf is addressed by `root_id + path`. Archive leaves return every indexed archive member and subtrack for that source.
- The exact-source query uses `tracks_source_lookup_index`; it does not scan the full root to satisfy presentation ordering.
- Folder rows retain disclosure behavior and do not hydrate a playlist as a side effect.
- Database read failures are distinct from legitimate empty results and are shown in the sidebar with Retry.

## Performance evidence

- The old dirty-projection fallback grouped the live JoshW root from `tracks` in about `11.86 s`.
- Reading the durable `file_sidebar_buckets` projection measured about `0.10 s`.
- A representative exact-source hydration query measured about `0.02 s` after using `tracks_source_lookup_index`.

The GENH console repair now dirties only the Games projection, because it does not change Files source paths or counts.

## Regression coverage

- `fileSidebarArchiveLeafLoadsEveryIndexedMemberThroughTheQueue`
- `fileSidebarDatabaseFailureIsNotReportedAsAnEmptyPlaylist`
- `fileSidebarLegitimateEmptyResultRemainsSuccessful`
- `fileSidebarBucketsServeStoredSourceLeavesAndDirtyRootFallbacks`
- `databaseSidebarLoaderRetainsFilesUntilExplicitInvalidation`
- `databaseFileSidebarKeepsTheCachedTreeOnAnUnchangedEmptySearch`

## Database publication safety

Full rescans now persist into a disabled staging root while the last committed sidebar remains readable. Publish reassigns the staged rows in a short transaction, refreshes both sidebar projections, and removes the staging root. Failed scans delete only staged rows; startup removes abandoned staging roots after a crash. Incremental scans retain the existing changed-source transaction.

Relevant code:

- `Sources/CocoaSpice/App/DatabaseSidebarLoader.swift`
- `Sources/CocoaSpice/App/LibraryDatabase.swift`
- `Sources/CocoaSpice/App/LibraryDatabase+ReadQueries.swift`
- `Sources/CocoaSpice/App/LibraryDatabase+FileSidebarBuckets.swift`
- `Sources/CocoaSpice/App/PlaylistQueueLoader.swift`
