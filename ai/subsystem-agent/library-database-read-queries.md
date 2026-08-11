# Library Database Read Queries

## Scope

- Read-only SQLite queries used by the Games and Files sidebars, sidebar search, folder browsing, and library-backed playlist construction.

## Ownership

- `LibraryDatabase+ReadQueries.swift` owns read-only connection setup plus game/file/sidebar and track/metadata query shaping.
- `LibraryDatabase.swift` owns database opening, scan inventory, persistence, maintenance writes, schema-adjacent primitives, and shared SQLite binding/error helpers.
- `LibraryDatabase+GameSidebarBuckets.swift` owns the durable per-root Games projection and its dirty-root rebuild lifecycle.

## Invariants

- Read queries exclude disabled roots and retained unlinked sources.
- `loadSidebarContent` uses one read-only connection so Games and Files rows come from the same SQLite snapshot.
- Files-mode rows remain deferred until that sidebar mode is requested; they must not delay the initial Games sidebar.
- Files-row SQL does not apply a redundant display sort. The background Files-tree index applies the user-visible localized root, folder, and filename order after the read, avoiding SQLite's temporary sort tree.
- Clean enabled roots load Games from `game_sidebar_buckets`; the exact `tracks` grouping remains a correctness fallback only while an enabled root is dirty after an interrupted write or schema upgrade.
- Clean enabled roots load Files from `file_sidebar_buckets`; the exact source grouping over `tracks` is a dirty-root fallback only. The normal Files path must stay proportional to source-file leaves, not playable subtracks.
- Games rows retain `root_id`, and playlist activation binds `root_id + browser_game + browser_system`. Never merge roots during either projection or activation.
- Startup batches every dirty enabled root into one utility-task rebuild. Disabled roots are repaired only when they are scanned directly or enabled again.
- Scan completion rebuilds dirty root buckets before deriving its displayed track count from that same projection. Test Links, source restoration, force clears, archive member replacement, and normal scan writes mark only their affected roots dirty.
- Query results are value types; UI publication and cancellation remain owned by the caller's task owner.

## Files

- [LibraryDatabase+ReadQueries.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase+ReadQueries.swift)
- [LibraryDatabase+GameSidebarBuckets.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase+GameSidebarBuckets.swift)
- [LibraryDatabase.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase.swift)
- [PlaylistQueueLoader.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaylistQueueLoader.swift)
