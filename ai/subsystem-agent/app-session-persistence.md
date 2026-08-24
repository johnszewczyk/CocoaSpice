# App Session Persistence

## Scope

- Shared persisted state.
- Restore order.
- Mode-aware saved context.

## Current State

- `PlayerViewModel` is the app orchestrator; focused observable coordinators own
  interface preferences, favorites, local-browser state, and queue state.
- User-defaults serialization now lives in a dedicated persistence helper rather than inline throughout the view model.
- Playback timing persistence is now unified to one `Long Play` toggle and one manual duration key.
- Playlist state is separate from sidebar state.
- Persisted playlist restore includes queued paths, selected track path, and current track path.
- Launch restores at most 1,024 queued entries and performs no filesystem existence walk. Remaining entries stay in the persisted session so startup work remains bounded; a missing source fails only if the user later activates it.
- The current database sidebar persists its last selected library folder path independently from queued playlist state.
- Sidebar double-click behavior, `Playlist Follows Cursor`, `Group by Console`, the Games/Files selection, and `Prefer Folders over Metadatas` persist in `UserDefaults`. A non-empty search temporarily displays Games results without rewriting the stored Games/Files selection.
- Sidebar and playlist monospace-font preferences persist in the shared playback preference bundle.
- Playlist sort state persists independently from broader playback preferences.
- Playlist column order, visibility, and widths restore through the shared persistence helper rather than direct view-level `UserDefaults` reads.
- Catalog roots are loaded read-only from SQLite rather than `UserDefaults`.
- `RestoredAppStartupState` gathers playback preferences, playlist state, column state, sidebar search, and root context in one typed read. Launch applies that snapshot after library roots load, preserving playback preferences, persisted playlist state, then sidebar mode and root context.
- Launch activates CocoaSpice so its first window is brought to the front.
- Options close writes the current preference bundle explicitly.
- Animation timing and per-window always-on-top values are typed by
  `FrontendPreferencesCore`; AppKit windows are matched by explicit main,
  settings, and about roles instead of title strings.
- Session playlist and sidebar selection context are saved on app termination or main-window close rather than being rewritten on ordinary selection movement.

## Rules

- Keep persistence explicit and mode-aware.
- Keep selection separate from playback.
- Keep queue state separate from browser state.
- Prefer narrow writes for narrow UI actions; do not wire incidental table interactions to full preference saves.
- Do not add preference migration or compatibility paths. Current CocoaSpice keys are the only persisted contract.

## Files

- [AppSessionPersistence.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/AppSessionPersistence.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
- [FrontendPreferencesCoordinator.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/FrontendPreferencesCoordinator.swift)
- [PlaylistQueueCoordinator.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/PlaylistQueueCoordinator.swift)
- [LibraryDatabase.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase.swift)
