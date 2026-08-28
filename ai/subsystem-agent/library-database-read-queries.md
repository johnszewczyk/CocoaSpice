# Library Database Read Queries

## Scope

- Read-only SQLite queries used by the Games and Files sidebars, sidebar search, folder browsing, and library-backed playlist construction.

## Ownership

- `CatalogReader` owns schema validation and compact Games/Files sidebar projections.
- `CatalogSessionCore` owns the shared raw Games/Files sidebar reader and the
  latest-task generation/cancellation primitive used by frontend loaders.
- `CatalogPlaylistCore` owns the exact extracted CocoaSpice Games playlist query and projection.
- `LibraryDatabase+ReadQueries.swift` owns CocoaSpice's typed adapter for shared catalog rows plus its remaining Files/folder/path projections. Both its normal bucket read and dirty-root direct SQLite read pass game buckets through `CatalogBrowserCore.CatalogBrowserProjection` before creating native `DatabaseGameItem` rows.
- ScanSong owns all catalog writes and durable sidebar-projection rebuilds.

## Invariants

- Read queries exclude disabled roots and retained unlinked sources.
- Files-mode rows remain deferred until that sidebar mode is requested; they must not delay the initial Games sidebar.
- Files-row SQL does not apply a redundant display sort. The background Files-tree index applies the user-visible localized root, folder, and filename order after the read, avoiding SQLite's temporary sort tree.
- Games sidebar rows are loaded through `CatalogReader`'s shared bucket aggregation. Playlist activation is a separate exact query in `CatalogPlaylistCore`; folder-first mode binds `t.browser_system = ?`, while metadata-first mode uses the original metadata expression. The player preference is read-only and never rewrites catalog rows or buckets.
- Files loads from the published `file_sidebar_buckets` projection and remains proportional to source-file leaves, not playable subtracks.
- Games rows retain `root_id`. Activation preserves the original root/game/system bindings and does not merge roots or add a fallback predicate.
- Files-source activation binds `root_id + path` and is backed by the direct `tracks_source_lookup_index`; it must not scan every track in a large library root to activate one archive source.
- Games playlist hydration uses `CatalogPlaylistCore`'s exact shared multi-selection projection, returning the original source and stored metadata columns in one read; CocoaSpice adds only its typed track adapter, metadata map, and width hints. SPCBoyWK uses the same rows. Files/folder/path hydration uses the narrow existing `tracksAndMetadataFor…` projections. Never replace either path with a generic all-track reader or a fallback scan.
- Queue publication performs no decoder open, archive materialization, filesystem stat, metadata write, or catalog mutation.
- Query results are value types; UI publication remains owned by the caller,
  while cancellation and stale-result generation ownership use
  `CatalogSessionCore.LatestTaskOwner`.

## Files

- [LibraryDatabase+ReadQueries.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase+ReadQueries.swift)
- [CatalogRootLoader.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/CatalogRootLoader.swift)
- [PlaylistQueueLoader.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/PlaylistQueueLoader.swift)
- [CatalogPlaylistCore.swift](/Users/john/Downloads/Code/VGMMan/CatalogReader/Sources/CatalogPlaylistCore/CatalogPlaylistCore.swift)
- [CatalogSessionCore.swift](/Users/john/Downloads/Code/VGMMan/CatalogReader/Sources/CatalogSessionCore/CatalogSessionCore.swift)
