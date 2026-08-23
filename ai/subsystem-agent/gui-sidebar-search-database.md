# GUI Sidebar Search Database

## Scope

- Database-mode sidebar search.
- Search-field debounce.
- In-memory database game-list filtering.

## Current State

- Sidebar search uses the single database search field.
- Sidebar placeholder text is `Search Library`.
- The native field delays a new non-empty query 250 ms, then follow-up edits 100 ms. Pending AppKit text is never overwritten by unrelated SwiftUI refreshes.
- A non-empty query is an effective temporary Games view that filters the indexed game list while preserving the stored Games/Files mode. Clearing the query restores that mode unchanged.
- `SidebarViewResolution` is the production effective-view owner and executes the shared CocoaSpice/SPCBoy search-view contract. It preserves the stored mode while exposing Search as database content and normalizes whitespace-only queries as no search.
- Search results stay inside the same dense database list; `Group by Console` applies to those results.
- Search should not interrupt playback.
- The Files tree is not searched while the temporary Games view is active.

## Rules

- Database-mode search must remain effectively instant.
- Search must remain database-oriented, not filesystem-recursive.
- Do not replace the stored Games/Files mode or recreate the removed legacy search surface.

## Files

- [DatabaseSidebarPresentation.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/DatabaseSidebarPresentation.swift)
- [MainView.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/MainView.swift)
- [NativeSearchField.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/NativeSearchField.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
- [Cross-app search-view fixture](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Tests/CocoaSpiceTests/cross-app-sidebar-search-view-v1.json)
- [LibraryDatabase.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase.swift)
