# GUI Sidebar Search Database

## Scope

- Database-mode sidebar search.
- Search-field debounce.
- In-memory database game-list filtering.

## Current State

- Sidebar search uses the single database search field.
- Sidebar placeholder text is `Search Database`.
- Search uses a short debounce interval for responsive native filtering.
- Search currently filters the already-loaded dense database game list in memory.
- Search results stay inside the same dense sidebar list instead of switching to the older folder or music-note result view.
- Search should not interrupt playback.
- Search is not yet leaf-granular even though the scanned database can contain multi-track playable leaves.

## Rules

- Database-mode search must remain effectively instant.
- Search must remain database-oriented, not filesystem-recursive.
- Do not swap into a separate legacy search-results surface without a product reason.

## Files

- [DatabaseSidebarPresentation.swift](/Users/john/Documents/Code/CocoaSpice/Sources/CocoaSpice/App/DatabaseSidebarPresentation.swift)
- [MainView.swift](/Users/john/Documents/Code/CocoaSpice/Sources/CocoaSpice/App/MainView.swift)
- [NativeSearchField.swift](/Users/john/Documents/Code/CocoaSpice/Sources/CocoaSpice/App/NativeSearchField.swift)
- [PlayerViewModel.swift](/Users/john/Documents/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
- [LibraryDatabase.swift](/Users/john/Documents/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase.swift)
