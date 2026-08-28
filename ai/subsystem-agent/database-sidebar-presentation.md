# Database Sidebar Presentation

## Scope

- Dense database-list presentation.
- In-memory sidebar filtering.
- Database-row status text and scan-root readouts.

## Current State

- The sidebar presents database games as a dense native list by default. `Group by Console` (`sidebarSystemMode`) instead shows expandable `Console → Game` rows using the same game items and activation path.
- Files mode presents an expandable `library root → stored folder → stored source file` tree derived from `DatabaseFileItem` records. Its folder expansion is in-memory presentation state; it must not enumerate the live filesystem or archives. Each child depth adds its persisted child-indent offset beyond its parent title, so child triangles and file labels never share their parent's text column.
- Games and Files use one shared dense native-table chrome for table configuration, keyboard/Return activation, row menus, scroll host, text-cell geometry, colors, and visible-row reload. Files render folder disclosure and depth as `▾`/`▸` plus four-space text indentation in the row label; do not add a separate disclosure-button layout.
- Files-folder disclosure is handled by an unmodified direct click on its triangle or by repeating a plain click on the selected folder title. The initial folder selection expands it; repeating that click toggles it without changing the playlist. Return and double-click still activate the selected folder's descendant leaves.
- Duplicate game titles are disambiguated in the visible label with system text only when needed. Duplicate `game + system` rows across roots additionally show their compact root name; root identity is part of the game item and never discarded. This policy, including natural ordering, is owned by shared `CatalogBrowserCore.CatalogBrowserProjection`; CocoaSpice adapts its projected rows to `DatabaseGameItem` and does not reimplement it.
- Sidebar filtering runs in memory over loaded rows rather than issuing live recursive filesystem work. The native field keeps AppKit's uncommitted text while it waits 250 ms for a first query character and 100 ms for follow-up input, so unrelated SwiftUI refreshes never replace a fast typist's visible input with a stale query.
- Files filtering and its matching tree index run in a cancellable utility task. A compact normalized source-path key is built with the Files load, so query workers avoid repeated URL parsing and case folding. New input invalidates older work before it can publish; the main actor only swaps in a complete result.
- A committed query filters only the active Games or Files mode. The inactive sidebar retains the query until it is selected, avoiding a second large in-memory filter for every search update.
- Game selection status text is standardized as `name • N tracks`.
- Library scan-root status text is standardized as enabled state, display order, indexed track count, and last completed scan time or error.
- Sidebar presentation state owns loaded rows, the visible filtered subset, and native selection independently from queue and playback state.
- With `Group by Console` enabled, root console rows only expand or collapse. Game leaves retain selection, multi-select, Return, double-click, and context-menu behavior.
- A non-empty sidebar search temporarily expands the matching system groups. Clearing the query folds every system group while retaining the library/sidebar root itself.
- Sidebar state publishes a content revision whenever the loaded or filtered game rows change. The native table caches the flattened rows for that revision and rebuilds them only after a content, `Group by Console`, or expansion change.
- Disclosure-only changes preserve the current viewport. Selection
  synchronization scrolls to the selected row only after a real selection
  change, never merely because a console group was expanded or collapsed.
- After either native Games or Files table is first shown, both remain alive while the other is visible. A Games/Files toggle changes visibility only; it must not recreate an expanded Files hierarchy or reread SQLite.
- Startup loads only the sidebar mode that was last selected, on its own background connection. A persisted Files view begins its Files request immediately; Games remains deferred until Games is selected, and vice versa. A large Files listing must never wait behind the Games query or delay first-window creation.
- `DatabaseSidebarLoader` owns the Games/Files snapshot cache. A mode toggle reads an already loaded snapshot; only a scan, root-state change, maintenance write, or explicit database reset invalidates it.
- `DatabaseSidebarLoader` publishes observable loading phase and activity state. It clears the active-loading state before invoking its completion callback, so SwiftUI removes the loading surface without requiring a window-focus or input event.
- A failed snapshot refresh leaves the last committed snapshot intact and displays an inline error with Retry. Do not clear loaded rows or reinterpret a read failure as an empty database.
- Games reads and activation use CatalogReader's shared folder-versus-metadata aggregation. Folder-first mode prefers ScanSong's indexed `browser_system`, metadata-first mode prefers `track_metadata.system`, and either falls through when the preferred value is empty. Changing source preference reloads the view without mutating the scanner catalog.
- Games search caches the candidate indices from the preceding query when new terms extend it. Query changes that are not an extension intentionally restart from the complete game list so results stay exact.
- The candidate-index algorithm is shared through `CatalogBrowserCore.CatalogSearchIndex`; CocoaSpice adapts projected searchable fields to its native `DatabaseGameItem` rows and does not own a second matching policy.
- Playlist hydration is deliberately not a second Files/Games policy here:
  `PlaylistQueueLoader` reaches the shared `CatalogPlaylistReader` and
  `PlaybackQueueNavigation` boundary. `TrackItem`, metadata caches, and
  native column-width hints remain CocoaSpice adapters because SPCBoyWK's
  bridge/DOM row shape is different.
- File roots begin collapsed after a Files refresh. This keeps flattened native-table construction proportional to the folders the user opens instead of eagerly building every source-file row.
- The Files sidebar builds its reusable folder graph alongside the background SQLite read. Once published, a disclosure reload walks only expanded branches; it must never rebuild the full graph on the main actor.
- The reusable folder graph, stable IDs, ordering, row flattening, and
  cancellable source-path search now live in
  `CatalogBrowserCore.CatalogFileTreeIndex` and
  `CatalogBrowserCore.CatalogFileSearchIndex`, extracted from this native
  implementation. CocoaSpice retains only the `DatabaseFileItem`/native-row
  adapter and its AppKit disclosure, selection, scroll, and drag/menu state.

## Rules

- Keep dense-list presentation behavior separate from queue mutation and playback control.
- Keep the native input responsive; debounce a first sidebar character by 250 ms and follow-up input by 100 ms rather than rebuilding rows for every keypress.
- Keep sidebar search focused on game leaves; it does not become a separate system search mode.
- Do not regroup or re-signature the complete sidebar during ordinary table redraws or scrolling.
- Keep row-status text and scan-root readouts centralized so wording changes do not drift across call sites.
- Files mode uses a native tree interaction: triangle click, a repeat click on a
  selected folder, and Space toggle only that folder. Selecting a multi-track
  source or archive populates the playlist; double-click and Return activate the
  selected file or folder rather than changing disclosure. Single-track files
  remain selection-only until double-click or Return.
- Files disclosure geometry uses persisted point gap and child-indent values from Sidebar Options. The triangle glyph follows Sidebar Style font size while the user-selected triangle-to-label space and hierarchy offset stay exact. Child-indent changes reload visible native rows only.
- Database sidebar tables and the playlist use one non-interactive capsule-selection overlay on full-width table chrome. A single selection glides between rows with the standard ease-in/ease-out curve; multi-selections update as individual capsules. A user-driven sidebar selection must not be immediately re-synced before that transition begins. The overlay must remain below row content and never alter native selection semantics.
- Catalog snapshot loading remains a native session contract: Games and Files
  use independent `LatestTaskOwner` generations, publish only complete
  snapshots, and retain the previous snapshot on read failure. Do not replace
  this with a generic UI loader; the WK bridge needs an equivalent request
  generation at its native boundary first.
- Files-mode labels omit archive track counts. The optional extension-hiding preference is presentation-only and must not alter database paths, drag payloads, or playback URLs.
- Extension hiding removes an entire recognized compressed-TAR suffix (for example, `.tar.zst`) in one operation; it must never leave a misleading `.tar` label behind.
- Scan Status has fixed one-line Current Activity, File Path, and File Name fields. Each middle-truncates before its row can grow; do not collapse them into one variable-length status string.

## Files

- [DatabaseSidebarPresentation.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/DatabaseSidebarPresentation.swift)
- [DatabaseSidebarState.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/DatabaseSidebarState.swift)
- [DatabaseFileSidebarInteraction.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/DatabaseFileSidebarInteraction.swift)
- [LibraryDatabase.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase.swift)
- [MainView.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/MainView.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
- [LibraryModels.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/LibraryModels.swift)
