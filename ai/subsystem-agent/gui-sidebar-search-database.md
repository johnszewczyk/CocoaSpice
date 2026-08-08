# GUI Sidebar Search Database

## Scope

- Database-mode sidebar search.
- Search-field debounce.
- In-memory database game-list filtering.

## Current State

- Sidebar search uses the single database search field.
- Sidebar placeholder text is `Search Database` in Games and `Search Files` in Files.
- The native field delays a new non-empty query 250 ms, then follow-up edits 100 ms. Pending AppKit text is never overwritten by unrelated SwiftUI refreshes.
- Games filter the loaded database list. Files filter a prebuilt normalized index on a utility task; stale tasks are cancelled by `LatestTaskOwner`.
- Search results stay inside the same dense sidebar list or folder tree instead of switching to an older result view.
- Search should not interrupt playback.
- Files search matches stored filename and path, preserving the folder hierarchy that reaches matching source files.
- A non-empty Files query expands all folders in the filtered tree. Clear restores the pre-search expanded-folder set.

## Rules

- Database-mode search must remain effectively instant.
- Search must remain database-oriented, not filesystem-recursive.
- Do not swap into a separate legacy search-results surface without a product reason.

## Files

- [DatabaseSidebarPresentation.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/DatabaseSidebarPresentation.swift)
- [MainView.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/MainView.swift)
- [NativeSearchField.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/NativeSearchField.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
- [LibraryDatabase.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase.swift)
