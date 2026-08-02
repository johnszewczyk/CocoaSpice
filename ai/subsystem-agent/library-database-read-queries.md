# Library Database Read Queries

## Scope

- Read-only SQLite queries used by the Games and Files sidebars, sidebar search, folder browsing, and library-backed playlist construction.

## Ownership

- `LibraryDatabase+ReadQueries.swift` owns read-only connection setup plus game/file/sidebar and track/metadata query shaping.
- `LibraryDatabase.swift` owns database opening, scan inventory, persistence, maintenance writes, schema-adjacent primitives, and shared SQLite binding/error helpers.

## Invariants

- Read queries exclude disabled roots and retained unlinked sources.
- `loadSidebarContent` uses one read-only connection so Games and Files rows come from the same SQLite snapshot.
- Files-mode rows remain deferred until that sidebar mode is requested; they must not delay the initial Games sidebar.
- Query results are value types; UI publication and cancellation remain owned by the caller's task owner.

## Files

- [LibraryDatabase+ReadQueries.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase+ReadQueries.swift)
- [LibraryDatabase.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase.swift)
- [PlaylistQueueLoader.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaylistQueueLoader.swift)
