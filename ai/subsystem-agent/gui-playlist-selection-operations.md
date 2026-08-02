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
- A single-row selection uses a short 180 ms standard ease-in/ease-out background transition and a capsule with semicircular ends, matching the sidebar's silhouette. Multi-selection and programmatic selection synchronization update immediately.
- The browsing selection remains stable while playback starts, completes, or moves through previous/next media commands; the playing row is represented independently by current transport state.

## Rules

- Keep Finder-style multiselect expectations.
- Keep selection separate from playback.
- Arrow-key movement is owned by the native playlist table; the following SwiftUI update must not overwrite the newly moved selection. Enter activates the table's current selected row, enabling arrow-key plus Enter seek/play workflows.
- The custom background highlight is non-interactive and stays below row content. Retarget its layer animation from its presentation position so repeated arrow-key navigation does not snap backward.
- If row activation behavior changes, update both selection semantics and playback-target semantics.

## Files

- [PlaylistTableView.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaylistTableView.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
