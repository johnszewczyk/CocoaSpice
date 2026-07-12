# Async Task Ownership

## Scope

- Async task ownership.
- Cancellation boundaries.
- Generation-guarded work.

## Current State

- Playback requests use a dedicated task owner.
- Playlist metadata prefetch uses a dedicated task owner.
- Library scanning uses a dedicated task owner.
- Folder-selection browsing uses a dedicated task owner.
- Queue construction uses a dedicated task owner.
- Sidebar search uses a dedicated task owner.
- Generation counters drop stale async results when newer requests supersede them.

## Rules

- If a new async task is added, document its cancellation owner here.
- Keep stale async results from clobbering newer UI state.
- Keep async ownership explicit rather than implied.

## Files

- [PlayerViewModel.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
