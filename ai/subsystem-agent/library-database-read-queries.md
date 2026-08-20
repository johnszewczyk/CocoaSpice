# Library Database Read Queries

## Scope

- Read-only SQLite queries used by the Games and Files sidebars, sidebar search, folder browsing, and library-backed playlist construction.

## Ownership

- `CatalogReader` owns schema validation plus compact Games/Files sidebar projection reads.
- `LibraryDatabase+ReadQueries.swift` owns CocoaSpice's proven exact read-only playlist projections.
- MediaScanner owns all catalog writes and durable sidebar-projection rebuilds.

## Invariants

- Read queries exclude disabled roots and retained unlinked sources.
- Files-mode rows remain deferred until that sidebar mode is requested; they must not delay the initial Games sidebar.
- Files-row SQL does not apply a redundant display sort. The background Files-tree index applies the user-visible localized root, folder, and filename order after the read, avoiding SQLite's temporary sort tree.
- Folder-first Games reads use the current `game_sidebar_buckets` projection. Metadata-first grouping is an opt-in read-only `tracks` plus `track_metadata` query, so the player preference never rewrites catalog rows or buckets.
- Files loads from the published `file_sidebar_buckets` projection and remains proportional to source-file leaves, not playable subtracks.
- Games rows retain `root_id`. Folder-first activation binds `root_id + browser_game + browser_system`; metadata-first activation uses its matching read-only console expression. Never merge roots during either projection or activation.
- Files-source activation binds `root_id + path` and is backed by the direct `tracks_source_lookup_index`; it must not scan every track in a large library root to activate one archive source.
- Playlist hydration uses the narrow existing `tracksAndMetadataFor…` query matching its selected game, source, folder, or path. It returns identity, stored metadata, and width hints in one read; never replace it with a generic all-track reader or a fallback scan.
- Queue publication performs no decoder open, archive materialization, filesystem stat, metadata write, or catalog mutation.
- Query results are value types; UI publication and cancellation remain owned by the caller's task owner.

## Files

- [LibraryDatabase+ReadQueries.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase+ReadQueries.swift)
- [CatalogRootLoader.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/CatalogRootLoader.swift)
- [PlaylistQueueLoader.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaylistQueueLoader.swift)
