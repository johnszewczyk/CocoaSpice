# Options

## Database

- Scan roots: add and manage folders used by the database.
- Scanning: opens a dedicated dialog with a bottom progress bar and `current / total` count on the left, plus a Cancel button on the right.
- The Library Paths section provides one `Trim Missing` action for the whole library. It checks only whether each unique indexed source path exists, then removes all entries backed by missing paths. It does not open archives or read metadata.
- Library paths are automatically sorted by path and expose Scan, Retry, Log, and Del actions; Log opens the latest scan issue report.
- Library paths show a small green check at the end of the path line when the latest scan reported no issues. If Trim Missing removed entries for a path, the same native check is yellow until that path is freshly scanned.

## Playback

- Long Play: enable shared extended playback.
- Duration: set a manual playback target.

## Interface

- Spectrum analyzer: choose base, peak, and cap colors.
- Database sidebar: set the sidebar font size in points.
- Database sidebar: choose primary, secondary, or tertiary text color.
- Reset restores the database sidebar to the default primary 12pt appearance.

## Window

- Options opens in a native titled macOS window.
- The window is 1280pt wide and 720pt tall.
- The sidebar contains Database, Interface, and Playback components in alphabetical order.

## Files

- [OptionsView.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/OptionsView.swift)
