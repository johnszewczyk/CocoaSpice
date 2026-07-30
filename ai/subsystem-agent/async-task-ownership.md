# Async Task Ownership

## Scope

- Async task ownership.
- Cancellation boundaries.
- Generation-guarded work.

## Current State

- Playback requests use a dedicated task owner.
- Playlist metadata prefetch uses a dedicated task owner.
- `LatestTaskOwner` centralizes replacement, cancellation, completion invalidation, and generation checks for independently cancellable UI workflows.
- Library scanning, adding paths, and Test Links share `LibraryOperationsState` and its `LatestTaskOwner`, rather than leaving cancellation machinery mixed with playback and playlist state in `PlayerViewModel`.
- Dead-link summary reads and database-sidebar refreshes each use their own `LatestTaskOwner`; stale results cannot overwrite a newer refresh or database cleanup state.
- Folder-selection browsing uses a dedicated task owner.
- Queue construction uses a dedicated task owner.
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
- [PlayerViewModel.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
