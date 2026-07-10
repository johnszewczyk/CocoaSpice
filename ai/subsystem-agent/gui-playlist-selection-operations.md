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
- Drag reorder is disabled while playlist search filtering is active.
- One primary selected row and a multiselect set can both exist.

## Rules

- Keep Finder-style multiselect expectations.
- Keep selection separate from playback.
- If row activation behavior changes, update both selection semantics and playback-target semantics.

## Files

- [PlaylistTableView.swift](/Users/john/Documents/Code/CocoaSpice/Sources/SPCBoy/App/PlaylistTableView.swift)
- [PlayerViewModel.swift](/Users/john/Documents/Code/CocoaSpice/Sources/SPCBoy/App/PlayerViewModel.swift)
