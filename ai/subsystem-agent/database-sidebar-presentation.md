# Database Sidebar Presentation

## Scope

- Dense database-list presentation.
- In-memory sidebar filtering.
- Database-row status text and scan-root readouts.

## Current State

- The sidebar presents database games as a dense native list by default. System Mode instead shows expandable `System → Game` rows using the same game items and activation path.
- Duplicate game titles are disambiguated in the visible label with system text only when needed.
- Sidebar filtering runs in memory over loaded game rows rather than issuing live recursive filesystem work.
- Game selection status text is standardized as `name • N tracks`.
- Library scan-root status text is standardized as enabled state, display order, indexed track count, and last completed scan time or error.
- Sidebar presentation state owns loaded rows, the visible filtered subset, and native selection independently from queue and playback state.
- In System Mode, root system rows only expand or collapse. Game leaves retain selection, multi-select, Return, double-click, and context-menu behavior.

## Rules

- Keep dense-list presentation behavior separate from queue mutation and playback control.
- Keep sidebar filtering effectively instant.
- Keep sidebar search focused on game leaves; it does not become a separate system search mode.
- Keep row-status text and scan-root readouts centralized so wording changes do not drift across call sites.

## Files

- [DatabaseSidebarPresentation.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/DatabaseSidebarPresentation.swift)
- [DatabaseSidebarState.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/DatabaseSidebarState.swift)
- [MainView.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/MainView.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
- [LibraryModels.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryModels.swift)
