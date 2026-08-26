# GUI Sidebar Core

## Scope

- Left pane sidebar behavior.
- Shared sidebar search field placement.
- Database-browser role of the left pane.

## Current State

- The sidebar search field stays at the top of the left pane.
- The search field now sits tighter to the top chrome with the extra top gap removed.
- The left pane is either the scanned persistent database browser or an explicitly enabled local-files browser rooted at one user-selected folder.
- The bottom sidebar mode switch has been removed.
- The primary sidebar view is a dense native list of database game rows. Options can enable `Group by Console`, stored internally as `sidebarSystemMode`, which renders expandable console rows with game leaves underneath.
- Sidebar search filters the database list instead of switching to a separate legacy result view.
- Right-clicking a sidebar row opens its context menu without changing sidebar selection.
- Favorites is not a sidebar mode. Command-Shift-D replaces the playlist with a
  snapshot of shared Favorites while leaving the current catalog/sidebar view
  and its selection context unchanged.
- Individual native navigation-toolbar items own the library-mode and
  fold/unfold controls beside the native sidebar disclosure button. They use
  the same regular toolbar-item sizing and borderless treatment as the native
  disclosure control; they must not be regrouped into a SwiftUI capsule.
  Playback controls remain in the separate main transport toolbar; do not
  place library controls in the sidebar column toolbar or transport group.
  The library-mode control cycles exactly `Console View` and `Path View`; it is
  not a dropdown.
- The View menu exposes those exact two library commands plus the separate `Local Files` command through `FrontendCommandCore`. The Favorites Playlist command uses Command-Shift-D and does not change the sidebar. Command-O opens a file or folder as the local-browser context.

## Rules

- Keep the left pane as a source browser, not the active queue.
- Local browsing must use `LocalFileBrowserCore`, stay rooted at the chosen folder, and never become a recursive scan. While enabled, database browsing is disabled.
- Keep sidebar behavior separate from queue behavior.
- Keep catalog aggregation in the shared CatalogBrowserCore/CatalogReader boundary. Favorite membership and history live in FrontendCore's shared native sidecar and must not be written into the scan catalog.
- CocoaSpice reloads the shared favorites store when the app becomes active.
  The retired per-app favorites payload and rollback migration are no longer
  runtime state.
- Folder/leaf click, disclosure, repeated-click, and activation intent comes
  from `CatalogBrowserCore.SidebarRowInteraction`; SwiftUI still owns visuals.
- Keep the two-view catalog command vocabulary shared while keeping SwiftUI row
  rendering and favorite storage native to this skin. Favorites playlist
  projection is a queue action, not a sidebar action.

## Files

- [MainView.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/MainView.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
- [NativeSearchField.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/NativeSearchField.swift)
- [FavoriteTrackCore.swift](/Users/john/Downloads/Code/VGMMan/FrontendCore/Sources/FavoriteTrackCore/FavoriteTrackCore.swift)
- [FavoriteStore.swift](/Users/john/Downloads/Code/VGMMan/FrontendCore/Sources/FavoriteStoreCore/FavoriteStore.swift)
