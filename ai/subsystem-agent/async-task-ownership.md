# Async Task Ownership

## Scope

- Async task ownership.
- Cancellation boundaries.
- Generation-guarded work.

## Current State

- Playback requests use a dedicated task owner.
- Playlist presentation refreshes are synchronous from the current queue and catalog metadata snapshot; no decoder-inspection task exists.
- `CatalogSessionCore.LatestTaskOwner` centralizes replacement, cancellation, completion invalidation, and generation checks for independently cancellable UI workflows.
- Database-sidebar refreshes each use their own shared `LatestTaskOwner`; stale results cannot overwrite a newer read-only snapshot.
- Remote transport receives a value-only `RemoteTransportNowPlaying` snapshot and command closures. It must not read or retain `PlayerViewModel` directly.
- `PlaybackRequestState` owns the pending playback request, task generation, cancellation, end marker, and auto-advance guard. A stale request may never publish an error or clear the active request's loading state.
- Folder-selection browsing uses its own `LatestTaskOwner`; selecting another folder, changing the root, or clearing sidebar context invalidates pending folder results.
- Files-sidebar search uses its own `LatestTaskOwner`; new search text cancels the prior utility filter/index task and only the current query may update the native tree.
- Queue construction uses its own `LatestTaskOwner` across database activation, folder loading, dropped imports, and sidebar-path activation. A newer queue request or cleared library/sidebar context invalidates older loading results.
- `DatabaseSidebarLoader` owns independent latest-task lifecycles for Games and Files reads. It owns cached snapshot invalidation and stale-result rejection; `PlayerViewModel` supplies only mode policy and post-load behavior.
- Random-library loading uses its own `LatestTaskOwner`; changing random scope or refreshing the database sidebar invalidates a pending random-game load before it can start playback.
- Sidebar search uses a dedicated task owner.
- Generation counters drop stale async results when newer requests supersede them.

## Rules

- If a new async task is added, document its cancellation owner here.
- Keep stale async results from clobbering newer UI state.
- Keep async ownership explicit rather than implied.

## Files

- [CatalogSessionCore.swift](/Users/john/Downloads/Code/VGMMan/CatalogReader/Sources/CatalogSessionCore/CatalogSessionCore.swift)
- [PlaybackRequestState.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/PlaybackRequestState.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
