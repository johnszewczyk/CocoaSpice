# GUI Playlist Selection Operations

## Scope

- Native row selection behavior.
- Row multiselect.
- Drag reorder.
- Selection-driven queue operations.

## Current State

- Multi-selection follows native `Shift` and `Command` semantics.
- Right-click rows open queue-action menus.
- Drag reorder is supported for selected rows.
- One primary selected row and a multiselect set can both exist.
- The browsing selection remains stable while playback starts, completes, or moves through previous/next media commands; the playing row is represented independently by current transport state.

## Rules

- Keep Finder-style multiselect expectations.
- Keep selection separate from playback.
- Arrow-key movement is owned by the native playlist table; the following SwiftUI update must not overwrite the newly moved selection. Enter activates the table's current selected row, enabling arrow-key plus Enter seek/play workflows.
- If row activation behavior changes, update both selection semantics and playback-target semantics.

## Files

- [PlaylistTableView.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaylistTableView.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
