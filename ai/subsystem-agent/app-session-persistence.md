# App Session Persistence

## Scope

- Shared persisted state.
- Restore order.
- Mode-aware saved context.

## Current State

- `PlayerViewModel` is the shared app model.
- User-defaults serialization now lives in a dedicated persistence helper rather than inline throughout the view model.
- Playback timing persistence is now unified to one `Long Play` toggle and one manual duration key.
- Spectrum analyzer enabled state and explicit `Base`, `Peak`, and `Cap` colors persist in `UserDefaults`.
- Playlist state is separate from sidebar state.
- Persisted playlist restore includes queued paths, selected track path, and current track path.
- The current database sidebar persists its last selected library folder path independently from queued playlist state.
- Sidebar double-click behavior, `Playlist Follows Cursor`, and Sidebar System Mode persist in `UserDefaults`.
- Sidebar and playlist monospace-font preferences persist in the shared playback preference bundle.
- Audio-export destination history persists as the last used output folder.
- Playlist sort state persists independently from broader playback preferences.
- Playlist column order, visibility, and widths restore through the shared persistence helper rather than direct view-level `UserDefaults` reads.
- Library scan roots are loaded from SQLite rather than `UserDefaults`.
- `RestoredAppStartupState` gathers playback preferences, playlist state, column state, sidebar search, and root context in one typed read. Launch applies that snapshot after library roots load, preserving playback preferences, persisted playlist state, then sidebar mode and root context.
- Launch activates CocoaSpice so its first window is brought to the front.
- Options close writes the current preference bundle explicitly.
- Session playlist and sidebar selection context are saved on app termination or main-window close rather than being rewritten on ordinary selection movement.

## Rules

- Keep persistence explicit and mode-aware.
- Keep selection separate from playback.
- Keep queue state separate from browser state.
- Prefer narrow writes for narrow UI actions; do not wire incidental table interactions to full preference saves.
- Remove retired preference migrations once the live app no longer writes them.

## Files

- [AppSessionPersistence.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/AppSessionPersistence.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
- [LibraryDatabase.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase.swift)
