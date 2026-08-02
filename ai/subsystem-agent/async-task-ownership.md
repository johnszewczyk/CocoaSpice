# Async Task Ownership

## Scope

- Async task ownership.
- Cancellation boundaries.
- Generation-guarded work.

## Current State

- Playback requests use a dedicated task owner.
- Playlist metadata prefetch uses its own `LatestTaskOwner`; replacement, playback start, and archive-cache clearing invalidate it before stale inspection results can update the playlist.
- `LatestTaskOwner` centralizes replacement, cancellation, completion invalidation, and generation checks for independently cancellable UI workflows.
- `LibraryScanController` owns the active scan queue, cancellation, live logs, and background coordinator work. `LibraryOperationsState` supplies its observable progress/status and generation guard; `PlayerViewModel` remains the presentation-facing facade.
- Remove Path and Reset Paths also use `LibraryOperationsState`; their detached SQLite work must check the operation generation before closing logs or replacing library/sidebar state.
- Dead-link summary reads and database-sidebar refreshes each use their own `LatestTaskOwner`; stale results cannot overwrite a newer refresh or database cleanup state.
- Remote transport receives a value-only `RemoteTransportNowPlaying` snapshot and command closures. It must not read or retain `PlayerViewModel` directly.
- `PlaybackRequestState` owns the pending playback request, task generation, cancellation, end marker, and auto-advance guard. A stale request may never publish an error or clear the active request's loading state.
- Folder-selection browsing uses its own `LatestTaskOwner`; selecting another folder, changing the root, or clearing sidebar context invalidates pending folder results.
- Files-sidebar search uses its own `LatestTaskOwner`; new search text cancels the prior utility filter/index task and only the current query may update the native tree.
- Queue construction uses its own `LatestTaskOwner` across database activation, folder loading, dropped imports, and sidebar-path activation. A newer queue request or cleared library/sidebar context invalidates older loading results.
- Random-library loading uses its own `LatestTaskOwner`; changing random scope or refreshing the database sidebar invalidates a pending random-game load before it can start playback.
- Sidebar search uses a dedicated task owner.
- Task completion and cancellation both advance the library-operation generation so late detached callbacks cannot overwrite a completed or newer operation's UI state.
- Generation counters drop stale async results when newer requests supersede them.

## Rules

- If a new async task is added, document its cancellation owner here.
- Keep stale async results from clobbering newer UI state.
- Keep async ownership explicit rather than implied.

## Files

- [LatestTaskOwner.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LatestTaskOwner.swift)
- [LibraryOperationsState.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryOperationsState.swift)
- [LibraryScanController.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryScanController.swift)
- [PlaybackRequestState.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaybackRequestState.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
