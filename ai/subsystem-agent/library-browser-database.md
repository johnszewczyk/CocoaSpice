# Library Browser Database

## Scope

- Database-mode library browsing.
- Game-list activation.
- Database-mode queue loading.

## Current State

- The sidebar database browser is a scanned persistent browser, not a raw filesystem tree.
- The sidebar displays a dense flat list of games derived from scanned metadata.
- Sidebar game buckets are keyed by `game title + system`, not title alone, so cross-platform name collisions stay separate.
- The scanned database now stores one playable row per discovered subtrack for multi-track `libgme` containers such as NSF.
- Database rows support native multiselect.
- Database double-click follows the configured sidebar double-click behavior.
- Database `Return` activates the current selection.
- Database multi-row `Return` replaces the playlist with the combined selection.
- Game activation loads playable leaves from the scanned database rather than rescanning the filesystem.
- File-path activation resolves the scanned playable leaves for that file path, so NSF containers contribute subtracks rather than the raw container file.
- Database-backed queue loading now lives in a dedicated queue-loader helper rather than inline throughout the main view model.
- Sidebar context-menu invocation does not mutate selection or trigger playlist-follow activation by itself.

## Rules

- Keep database browsing rooted in scanned metadata, not direct filesystem tree rendering.
- Keep activation and queue-loading behavior explicit.
- Treat current game rows as aggregations over playable leaves, not guaranteed one-file-one-track groupings.

## Files

- [DatabaseSidebarPresentation.swift](/Users/john/Documents/Code/CocoaSpice/Sources/CocoaSpice/App/DatabaseSidebarPresentation.swift)
- [LibraryDatabase.swift](/Users/john/Documents/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase.swift)
- [LibraryModels.swift](/Users/john/Documents/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryModels.swift)
- [MainView.swift](/Users/john/Documents/Code/CocoaSpice/Sources/CocoaSpice/App/MainView.swift)
- [PlaylistQueueLoader.swift](/Users/john/Documents/Code/CocoaSpice/Sources/CocoaSpice/App/PlaylistQueueLoader.swift)
- [PlayerViewModel.swift](/Users/john/Documents/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
