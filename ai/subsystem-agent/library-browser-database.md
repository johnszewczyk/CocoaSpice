# Library Browser Database

## Scope

- Query-only schema-23 catalog access.
- Games, Files, Search, activation, and queue loading.

## Ownership

- MediaScanner is the sole catalog writer and owns roots, scanning, metadata,
  console identity, checkpoints, and sidebar projections.
- `LibraryDatabase.configuredDatabaseURL` owns launch-time path selection.
- CocoaSpice opens the selected file with `SQLITE_OPEN_READONLY` plus
  `PRAGMA query_only`, validates schema 23, and exposes read APIs only in the
  production app path.
- `DatabaseSidebarLoader` owns snapshots and retains the last valid snapshot
  when a query fails.
- `CatalogSessionCore` supplies the read-only Games/Files bucket reader and
  the generation-guarded task owner used by the native loader.
- `ArchiveCacheCore` owns cache-root cleanup and LRU eviction mechanics;
  its playback lease, and the policy value model; CocoaSpice retains archive
  format/tool selection, preference keys, and Options presentation.
- `ArchiveMaterializationCore.ArchiveMaterializationPlan` owns the shared
  selected-entry versus complete-set contract. CocoaSpice still owns its
  format-specific extractor and dependency preparation.
- `PlaylistQueueLoader` converts stored game/file identities into playlist rows
  without rescanning source media.

## Invariants

- Browse persists only an absolute standardized path accepted by CocoaSpice's
  read-only schema-23 validation; a changed location applies after restart.
  Reloading the active location invalidates cached read-only sidebar snapshots
  and loads the current published catalog without changing playback.
- CocoaSpice never creates, migrates, scans into, resets, cleans, rewrites, or
  hydrates metadata into the selected catalog.
- Track identity is root, source path, archive member, and subtrack index.
- Game identity is `root_id + browser_game + browser_system`; same-title games
  in separate roots remain distinct.
- Games, Files, and activation consume MediaScanner's stored projections and
  playable leaves. They do not walk or regroup the filesystem.
- Search is a temporary Games view independent of the underlying Games/Files
  choice. Clearing search restores that choice.
- Archive source leaves resolve their stored members; libgme source leaves
  resolve their stored child tracks.
- Query failure remains visible and cannot trigger a writable fallback database
  or an in-app scan.

## Performance

- Folder-first Games reads use `game_sidebar_buckets`; metadata-first Games
  reads use the selected read-only console expression over `tracks` and
  `track_metadata`. Files reads use `file_sidebar_buckets`; search uses stored
  FTS/projection data.
- Files loads only when opened and begins with roots collapsed.
- Sidebar requests retain the last successful result while a retryable failure
  is displayed.

## Files

- [LibraryDatabase.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase.swift)
- [LibraryDatabase+ReadQueries.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase+ReadQueries.swift)
- [DatabaseSidebarLoader.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/DatabaseSidebarLoader.swift)
- [CatalogSessionCore.swift](/Users/john/Downloads/Code/VGMMan/CatalogReader/Sources/CatalogSessionCore/CatalogSessionCore.swift)
- [ArchiveCacheLifecycle.swift](/Users/john/Downloads/Code/VGMMan/FrontendCore/Sources/ArchiveCacheCore/ArchiveCacheLifecycle.swift)
- [ArchivePlaybackLease.swift](/Users/john/Downloads/Code/VGMMan/FrontendCore/Sources/ArchiveCacheCore/ArchivePlaybackLease.swift)
- [DatabaseSidebarPresentation.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/DatabaseSidebarPresentation.swift)
- [PlaylistQueueLoader.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/PlaylistQueueLoader.swift)
- [DatabaseFileSidebarSelectionTests.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Tests/CocoaSpiceTests/DatabaseFileSidebarSelectionTests.swift)
