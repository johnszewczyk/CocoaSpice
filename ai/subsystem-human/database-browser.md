# Database Browser

## Display

- Database: scanned game-music library in the left pane.
- Rows: dense list of scanned games by default.
- Console View: Options can group games under expandable console headings.
- Rows: show track counts and scan-root status.
- Fast Scan playlist activation expands archived GBS files into their individual subtracks.
- Incremental scans retain successful unchanged ZIP, 7z, and TAR+Zstandard archive results instead of re-inspecting their playable members.

## Search

- Search: filters the loaded database list.
- Search: uses the same sidebar list rather than a separate results surface.
- Search: matches game titles; console headings organize the results but are not an additional search field.
- Search: preserves the active database selection when the query changes.
- Search: clearing the query folds all Console View headings, returning the sidebar to its compact state.

## Selection

- Selection: supports native multi-selection.
- Context menu: opens without changing the selected row.

## Activation

- Rows: double-click follows the configured activation behavior.
- Rows: Return loads the selected game or games into the playlist.

## Files

- [MainView.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/MainView.swift)
- [LibraryDatabase.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase.swift)
- [LibraryModels.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryModels.swift)
