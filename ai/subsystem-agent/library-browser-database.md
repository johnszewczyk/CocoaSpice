# Library Browser Database

## Scope

- Query-only schema-23 catalog access.
- Games, Files, Search, activation, and queue loading.

## Ownership

- ScanSong is the sole catalog writer and owns roots, scanning, metadata,
  console identity, checkpoints, and sidebar projections.
- `LibraryDatabase.configuredDatabaseURL` owns launch-time path selection.
- CocoaSpice opens the selected file with `SQLITE_OPEN_READONLY` plus
  `PRAGMA query_only`, validates schema 23, and exposes read APIs only in the
  production app path.
- `DatabaseSidebarLoader` owns snapshots and retains the last valid snapshot
  when a query fails.
- `CatalogSessionCore` supplies the read-only Games/Files bucket reader and
  the generation-guarded task owner used by the native loader.
- `ArchiveCacheCore` owns cache-root cleanup, stable archive identity, free
  space checks, LRU eviction mechanics, playback lease, and policy value model;
  CocoaSpice retains only archive format/tool selection, preference keys,
  Options presentation, user-facing error mapping, and maintenance scheduling.
- `VGMBoyFormatCore.VGMArchiveMaterializationRequirement` and
  `VGMBoyKit.FormatRegistry` own the format decision about selected-entry
  versus complete-set preparation. `ArchiveMaterializationCore` owns PSF
  closure, complete-set staging, lazyUSF aliases, TXTP aliases, cache identity,
  warm-hit checks, atomic staging, completion markers, and cache-limit
  orchestration plus cache-lease activation. CocoaSpice retains only
  archive-tool closures, archive listing/manifest reads, TAR+Zstandard piping,
  cleanup scheduling, and app-facing error mapping.
- `ArchiveMaterializationCore.ArchiveListingParser` owns bounded
  7-Zip/TAR/RSN listing parsing and reversible BSD-tar octal pathname
  rendering. `ArchiveManifestReader` owns temporary, non-cache manifest reads;
  CocoaSpice retains only process execution and tool selection.
- `ArchiveMaterializationCore.ArchiveProcessRunner` owns bounded archive
  process permits, cancellation/timeout observation, captured stdout limits,
  and stderr collection. CocoaSpice retains the format-specific executable
  topology, arguments, and connected zstd/tar pipeline.
- `ArchiveMaterializationCore.ArchiveEntryPath` owns archive-member path
  normalization, traversal rejection, safe destination components, and BSD
  tar octal-display preservation. CocoaSpice delegates its existing local
  adapters to this contract; SPCBoyWK receives the same behavior through
  `ArchiveMaterializer`.
- `ArchiveMaterializationCore.ArchiveContainerKind` and `ArchiveToolRouting`
  own exact archive-container detection and extraction command specifications.
  CocoaSpice retains executable discovery, process execution, error mapping,
  and the specialized TAR+Zstandard raw-name pipeline.
- `PlaylistQueueLoader` converts stored game/file identities into playlist rows
  without rescanning source media.
- `CatalogPlaylistCore` owns the indexed Games playlist projection. Its
  folder-system and metadata-system fallback branches must remain separate so
  the `tracks_game_sidebar_index` can be used; CocoaSpice may adapt the shared
  rows to `TrackItem`, but must not recreate the query or inspect source files.
- `PlaybackQueueCore` is the extracted source of truth for queue target,
  adjacency, completion, and replacement-state transitions. Its
  `PlaybackQueueState` value contract also carries current/selected/pending
  identity. CocoaSpice keeps only TrackItem adapters around those ID-based
  rules; SPCBoyWK consumes the same module through its native bridge.

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
- Games, Files, and activation consume ScanSong's stored projections and
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
  `track_metadata`, with index-preserving fallback branches. Files reads use
  `file_sidebar_buckets`; search uses stored FTS/projection data.
- Files loads only when opened and begins with roots collapsed.
- Sidebar requests retain the last successful result while a retryable failure
  is displayed.

## Files

- [LibraryDatabase.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase.swift)
- [LibraryDatabase+ReadQueries.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase+ReadQueries.swift)
- [DatabaseSidebarLoader.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/DatabaseSidebarLoader.swift)
- [CatalogSessionCore.swift](/Users/john/Downloads/Code/VGMMan/CatalogReader/Sources/CatalogSessionCore/CatalogSessionCore.swift)
- [ArchiveCacheLifecycle.swift](/Users/john/Downloads/Code/VGMMan/FrontendCore/Sources/ArchiveCacheCore/ArchiveCacheLifecycle.swift)
- [ArchiveCacheStore.swift](/Users/john/Downloads/Code/VGMMan/FrontendCore/Sources/ArchiveCacheCore/ArchiveCacheStore.swift)
- [ArchivePlaybackLease.swift](/Users/john/Downloads/Code/VGMMan/FrontendCore/Sources/ArchiveCacheCore/ArchivePlaybackLease.swift)
- [ArchiveProcessRunner.swift](/Users/john/Downloads/Code/VGMMan/FrontendCore/Sources/ArchiveMaterializationCore/ArchiveProcessRunner.swift)
- [ArchiveCacheMaterializer.swift](/Users/john/Downloads/Code/VGMMan/FrontendCore/Sources/ArchiveMaterializationCore/ArchiveCacheMaterializer.swift)
- [ArchiveMaterializationSession.swift](/Users/john/Downloads/Code/VGMMan/FrontendCore/Sources/ArchiveMaterializationCore/ArchiveMaterializationSession.swift)
- [ArchiveListingParser.swift](/Users/john/Downloads/Code/VGMMan/FrontendCore/Sources/ArchiveMaterializationCore/ArchiveListingParser.swift)
- [ArchiveManifestReader.swift](/Users/john/Downloads/Code/VGMMan/FrontendCore/Sources/ArchiveMaterializationCore/ArchiveManifestReader.swift)
- [ArchiveEntryPath.swift](/Users/john/Downloads/Code/VGMMan/FrontendCore/Sources/ArchiveMaterializationCore/ArchiveEntryPath.swift)
- [ArchiveToolRouting.swift](/Users/john/Downloads/Code/VGMMan/FrontendCore/Sources/ArchiveMaterializationCore/ArchiveToolRouting.swift)
- [DatabaseSidebarPresentation.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/DatabaseSidebarPresentation.swift)
- [PlaylistQueueLoader.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/PlaylistQueueLoader.swift)
- [PlaybackQueueNavigation.swift](/Users/john/Downloads/Code/VGMMan/FrontendCore/Sources/PlaybackQueueCore/PlaybackQueueNavigation.swift)
- [DatabaseFileSidebarSelectionTests.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Tests/CocoaSpiceTests/DatabaseFileSidebarSelectionTests.swift)
