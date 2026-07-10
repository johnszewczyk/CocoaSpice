# Library Scan Roots

## Scope

- Scan-root configuration.
- SQLite root persistence.
- Scan lifecycle and status.

## Current State

- Scan roots are configured from Options.
- Scan roots persist in SQLite.
- Adding a scan root starts a scan automatically.
- Scan status includes current-file progress text.
- Database state restores from the existing database on launch and does not rescan automatically.

## Rules

- Keep scan-root persistence in SQLite, not `UserDefaults`.
- Keep scan-root management separate from playlist behavior and playback behavior.
- Keep automatic scan behavior explicit.

## Files

- [OptionsView.swift](/Users/john/Documents/Code/CocoaSpice/Sources/SPCBoy/App/OptionsView.swift)
- [LibraryDatabase.swift](/Users/john/Documents/Code/CocoaSpice/Sources/SPCBoy/App/LibraryDatabase.swift)
- [PlayerViewModel.swift](/Users/john/Documents/Code/CocoaSpice/Sources/SPCBoy/App/PlayerViewModel.swift)
