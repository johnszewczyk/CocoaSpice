# Audio Playback Transport

## Scope

- Previous, play-pause, and next commands.
- Toolbar transport controls.
- Media-key and remote-command integration.

## Current State

- Transport supports previous, play, pause, and next.
- Toolbar transport buttons drive the active queue.
- `F8` or play-pause uses explicit pause-or-resume semantics, not a blind toggle chain.
- Previous and next wrap within the active queue.
- When a track completes, playback continues into the current queue when a next item exists.
- Remote media commands integrate with the same playback flow as the toolbar.
- Explicit remote play and remote pause commands are handled separately rather than both feeding a toggle path.
- Queue-navigation policy for previous, next, resume fallback, and completion advance now lives in a dedicated helper rather than inline throughout the view model.
- Rapid previous or next commands are not throttled by a same-key time gate.
- A newer playback request cancels stale request tasks before they enter decoder loading.
- Playback-state changes are published by the audio engine so transport UI and Media Session state do not depend solely on polling.

## Rules

- Keep queue editing independent from transport state.
- Keep play-pause semantics explicit.
- Keep transport ownership aligned across toolbar and remote commands.
- Keep rapid navigation latest-wins; canceled requests must not proceed into decoder loading after a newer request exists.

## Files

- [MainView.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/MainView.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
- [QueueTransportNavigation.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/QueueTransportNavigation.swift)
- [RemoteTransportController.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/RemoteTransportController.swift)
