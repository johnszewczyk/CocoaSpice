# WIP: Sidebar Path Mode and Playlist Hydration

## Status

**Blocked / regressions present. Do not treat the current Path sidebar as fixed.**

This is a handoff report for the agent owning the next repair. The user reports two current failures in the latest app:

1. The Files/Path library loading screen remains visible until the user clicks or focuses CocoaSpice, even after its background work should have completed.
2. Selecting a Path-mode source no longer hydrates the playlist at all. Console/Game mode continues to hydrate promptly.

The expected behavior is simple: Database mode grouped by Console and Database mode organized by Path must both hydrate the playlist directly from the same scanned SQLite data, without filesystem traversal, a focus requirement, or a material delay.

## User-Facing Reproduction

1. Launch CocoaSpice with the JoshW root enabled (`~470k` indexed tracks, `13,026` source-file leaves).
2. Switch the sidebar to Files/Path mode.
3. Wait without interacting. The loading display may remain until the window is clicked/focused.
4. Select a Path-mode archive/source that should replace the playlist.
5. Current result: no playlist hydration. Prior result: roughly four seconds before hydration.
6. Repeat from Games with Group by Console enabled. That path works quickly and must remain the reference behavior.

## Confirmed History

### Projection fallback (fixed in the live database)

The GENH console-repair migration dirtied `file_sidebar_buckets` even though it changed only `tracks.browser_system`. That forced Files sidebar loading to group the entire JoshW root from `tracks`.

- Direct fallback grouping measured about `11.86 s`.
- Reading the populated `file_sidebar_buckets` projection measured about `0.10 s`.
- The live JoshW projection was rebuilt and `file_sidebar_buckets_dirty` is `0` for both enabled roots.
- The migration code now invalidates only game buckets for this metadata-only repair.

Relevant code:

- `Sources/CocoaSpice/App/LibraryDatabase+Schema.swift`
- `Sources/CocoaSpice/App/LibraryDatabase+FileSidebarBuckets.swift`
- `Sources/CocoaSpice/App/LibraryDatabase+ReadQueries.swift`

### UI redraw (fixed but not sufficient)

`DatabaseSidebarTableChrome.reloadVisibleRows` previously reloaded `0..<tableView.numberOfRows`, despite its name. Every Files selection therefore redrew every expanded row. It now reloads the table's actual visible row range only.

Relevant code:

- `Sources/CocoaSpice/App/MainView.swift`

### Files cache and startup crash

The Files cache had two prior defects:

- An unchanged empty search advanced `DatabaseFileSidebarState.contentRevision` whenever Files mode was entered, defeating table caching.
- The root-path cache used `Dictionary(uniqueKeysWithValues:)` over every source row. Multiple source rows share a root ID, which crashed at startup with `EXC_BREAKPOINT` in `DatabaseFileSidebarState.installFileItems`.

The second defect was fixed with a first-value-per-root map. The crash report was:

- `~/Library/Logs/DiagnosticReports/CocoaSpice-2026-08-11-141749.ips`

Relevant code:

- `Sources/CocoaSpice/App/DatabaseFileSidebarState.swift`
- `Sources/CocoaSpice/App/DatabaseSidebarLoader.swift`

## Hydration Query Investigation

Games use `LibraryDatabase.tracksAndMetadataForGames`. Files use `LibraryDatabase.tracksAndMetadataForFiles`, via:

```
DatabaseFileListView selection
  -> PlayerViewModel.activateDatabaseFile
  -> PlaylistQueueLoader.loadLibraryTracksForFileSidebarSelection
  -> LibraryDatabase.tracksAndMetadataForFiles
```

For one exact source path, SQLite's original plan selected `tracks_file_tree_index (root_id, folder_path, path)` because of the Files query's `ORDER BY t.folder_path, t.filename, t.track_index`. That plan scanned the full root instead of using the exact source predicate. This explains the reported multi-second Path hydration delay.

The last change forced:

```
FROM tracks t INDEXED BY tracks_source_lookup_index
```

in `tracksAndMetadataForFiles`. A representative live query then measured `0.02 s`. **However, the user reports that the latest app no longer hydrates a Path selection at all. Treat this forced-index change as suspect until an integration test proves selected Files rows return tracks and replace the playlist.**

Potential failure points to inspect before changing anything else:

- Does `DatabaseFileListView.tableViewSelectionDidChange` actually call `activateDatabaseFile` for the selected row? It currently auto-activates only an item marked `isArchive`.
- Does `tracksAndMetadataForFiles` return zero rows or throw when invoked by the packaged application? Add narrow logging or an integration test using an archive source with multiple rows.
- Is `fileItems` empty, stale, or rooted incorrectly by the time `PlaylistQueueLoader` receives it?
- Is the `LatestTaskOwner` generation guard discarding a successful queue load before `PlayerViewModel` publishes it?
- Do not compare only raw SQLite timing. Verify the full UI selection -> queue -> playlist publication lifecycle.

## Loading Screen / Focus Bug

The current loader performs two detached phases:

1. `LibraryDatabase.loadFileSidebarItems(databaseURL:)`
2. `DatabaseFileSidebarTree.Index` plus `SearchIndex` construction

It publishes `fileLoadingStatus` between phases. The user reports the state change does not clear the loading UI until the app receives a click/focus event.

Investigate the main-actor publication path, not the progress control appearance:

- `DatabaseSidebarLoader.loadFilesIfNeeded`
- `DatabaseFileSidebarState.replaceFileItems`
- `PlayerViewModel.isLoadingDatabaseFileSidebar`
- `MainView` loading `Group` condition
- `LatestTaskOwner.finish(generation:)`

Verify from a non-focused launch whether `hasLoadedFiles`, `fileLoadTaskOwner.isActive`, and `fileItems.count` have already changed while the spinner remains on screen. If they have, the fault is an Observation/AppKit invalidation issue. If they have not, the detached task is stalled or its continuation is not resuming.

The indeterminate progress bar is intentionally not a meaningful duration estimate. Do not present it as progress. A replacement should report a real count, for example `N / total source leaves read`, or use named phases only if the UI clears reliably on completion.

## Constraints for the Repair

- Console/Game and Files/Path activation must be direct read-only SQLite work against scanned rows. Never rescan or walk source directories to hydrate a sidebar selection.
- A Path source is identified by `root_id + path`. Preserve root scope; overlapping roots are valid.
- Archive source selection must load all indexed archive-member/subtrack rows for that source.
- Folder selection behavior is separate from source selection. Do not make a normal folder click hydrate a playlist unless that is explicitly the chosen UI behavior.
- Do not use a global dirty-root fallback for normal clean Path reads.
- Keep loading lifecycle state owned by `DatabaseSidebarLoader`; do not scatter new flags through views.
- Add an end-to-end regression test that verifies one Path leaf produces the expected playlist tracks through `PlaylistQueueLoader`, plus a test that Files loader completion clears its loading state without a view interaction.

## Relevant Tests

- `Tests/CocoaSpiceTests/LibraryGameSidebarBucketTests.swift`
- `Tests/CocoaSpiceTests/SidebarSessionTests.swift`
- `Tests/CocoaSpiceTests/DatabaseFileSidebarSelectionTests.swift`
- `Tests/CocoaSpiceTests/LibraryScanPipelineTests.swift`

## Working Tree Warning

This checkout contains several uncommitted sidebar/database changes and unrelated pre-existing files. Inspect `git status --short` before editing; do not reset or discard the user’s work.
