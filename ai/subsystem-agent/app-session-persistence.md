# App Session Persistence

## Scope

- Shared persisted state.
- Restore order.
- Mode-aware saved context.

## Current State

- `PlayerViewModel` is the shared app model.
- User-defaults serialization now lives in a dedicated persistence helper rather than inline throughout the view model.
- Playback timing persistence is now unified to one `Long Play` toggle and one manual duration key.
- Spectrum analyzer colors persist as explicit `Base`, `Peak`, and `Cap` settings in `UserDefaults`.
- Playlist state is separate from sidebar state.
- Persisted playlist restore includes queued paths, selected track path, and current track path.
- The current database sidebar persists its last selected library folder path independently from queued playlist state.
- Sidebar double-click behavior and `Playlist Follows Cursor` persist in `UserDefaults`.
- Audio-export destination history persists as the last used output folder.
- Playlist sort state persists independently from broader playback preferences.
- Playlist column order, visibility, and widths restore through the shared persistence helper rather than direct view-level `UserDefaults` reads.
- Library scan roots are loaded from SQLite rather than `UserDefaults`.
- Launch restores playback preferences, library scan roots, persisted playlist state, then sidebar mode and root context.
- Options close writes the current preference bundle explicitly.
- Session playlist and sidebar selection context are saved on app termination or main-window close rather than being rewritten on ordinary selection movement.

## Rules

- Keep persistence explicit and mode-aware.
- Keep selection separate from playback.
- Keep queue state separate from browser state.
- Prefer narrow writes for narrow UI actions; do not wire incidental table interactions to full preference saves.
- Remove retired preference migrations once the live app no longer writes them.

## Files

- [AppSessionPersistence.swift](/Users/john/Documents/Code/CocoaSpice/Sources/SPCBoy/App/AppSessionPersistence.swift)
- [PlayerViewModel.swift](/Users/john/Documents/Code/CocoaSpice/Sources/SPCBoy/App/PlayerViewModel.swift)
- [LibraryDatabase.swift](/Users/john/Documents/Code/CocoaSpice/Sources/SPCBoy/App/LibraryDatabase.swift)
