# Database Sidebar Presentation

## Scope

- Dense database-list presentation.
- In-memory sidebar filtering.
- Database-row status text and scan-root readouts.

## Current State

- The sidebar presents database games as a dense native list by default. System Mode instead shows expandable `System → Game` rows using the same game items and activation path.
- Files mode presents an expandable `library root → stored folder → stored source file` tree derived from `DatabaseFileItem` records. Its folder expansion is in-memory presentation state; it must not enumerate the live filesystem or archives.
- Games and Files use one shared dense native-table chrome for table configuration, keyboard/Return activation, row menus, scroll host, text-cell geometry, colors, and visible-row reload. Files render folder disclosure and depth as `▾`/`▸` plus four-space text indentation in the row label; do not add a separate disclosure-button layout.
- Files-folder disclosure is handled only by an unmodified direct click. Folder rows are nonselectable during Shift/Command range selection, so multi-selecting file leaves never expands or collapses intermediate folders.
- Duplicate game titles are disambiguated in the visible label with system text only when needed.
- Sidebar filtering runs in memory over loaded game rows rather than issuing live recursive filesystem work. The native field debounces filter-state publication by 100 ms so typing does not rebuild the sidebar for every keypress.
- Game selection status text is standardized as `name • N tracks`.
- Library scan-root status text is standardized as enabled state, display order, indexed track count, and last completed scan time or error.
- Sidebar presentation state owns loaded rows, the visible filtered subset, and native selection independently from queue and playback state.
- In System Mode, root system rows only expand or collapse. Game leaves retain selection, multi-select, Return, double-click, and context-menu behavior.
- A non-empty sidebar search temporarily expands the matching system groups. Clearing the query folds every system group while retaining the library/sidebar root itself.
- Sidebar state publishes a content revision whenever the loaded or filtered game rows change. The native table caches the flattened rows for that revision and rebuilds them only after a content, System Mode, or expansion change.
- Database game/file aggregation and sorting load off the main actor at startup through one read-only `DatabaseSidebarContent` snapshot; Games and Files therefore apply rows from the same database moment while the sidebar displays its loading state.

## Rules

- Keep dense-list presentation behavior separate from queue mutation and playback control.
- Keep the native input responsive; debounce sidebar filtering by 100 ms rather than rebuilding rows for every keypress.
- Keep sidebar search focused on game leaves; it does not become a separate system search mode.
- Do not regroup or re-signature the complete sidebar during ordinary table redraws or scrolling.
- Keep row-status text and scan-root readouts centralized so wording changes do not drift across call sites.

## Files

- [DatabaseSidebarPresentation.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/DatabaseSidebarPresentation.swift)
- [DatabaseSidebarState.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/DatabaseSidebarState.swift)
- [DatabaseFileSidebarInteraction.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/DatabaseFileSidebarInteraction.swift)
- [LibraryDatabase.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase.swift)
- [MainView.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/MainView.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
- [LibraryModels.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryModels.swift)
