# GUI Sidebar Core

## Scope

- Left pane sidebar behavior.
- Shared sidebar search field placement.
- Database-browser role of the left pane.

## Current State

- The sidebar search field stays at the top of the left pane.
- The search field now sits tighter to the top chrome with the extra top gap removed.
- The left pane is a scanned persistent database browser.
- The bottom sidebar mode switch has been removed.
- The primary sidebar view is a dense native list of database game rows.
- Sidebar search filters the database list instead of switching to a separate legacy result view.
- Right-clicking a sidebar row opens its context menu without changing sidebar selection.

## Rules

- Keep the left pane as a source browser, not the active queue.
- Keep the sidebar database-backed rather than reintroducing direct filesystem browsing.
- Keep sidebar behavior separate from queue behavior.

## Files

- [MainView.swift](/Users/john/Documents/Code/CocoaSpice/Sources/SPCBoy/App/MainView.swift)
- [PlayerViewModel.swift](/Users/john/Documents/Code/CocoaSpice/Sources/SPCBoy/App/PlayerViewModel.swift)
- [NativeSearchField.swift](/Users/john/Documents/Code/CocoaSpice/Sources/SPCBoy/App/NativeSearchField.swift)
