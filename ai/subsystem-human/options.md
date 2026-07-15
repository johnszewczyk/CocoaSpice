# Options

## Database

- Scan roots: add and manage folders used by the database.
- Scan All: rescans every enabled library path.
- Stop Scan: stops the active scan without removing indexed library entries already written.
- Purge Database: removes all indexed files, metadata, scan inventory, and scan status while retaining configured library paths.
- Fast Scan: indexes supported files and archive containers using filenames only, without decoder metadata scans, archive member listing, or archive decompression. Archive members and their metadata load after an archive enters the playlist.
- Scanning: each active library path shows its own label-free 200pt progress bar at the bottom-right of that path's panel.
- The Library Paths section provides one `Trim Missing` action for the whole library. It checks only whether each unique indexed source path exists, then removes all entries backed by missing paths. It does not open archives or read metadata.
- Library paths are automatically sorted by path and expose Scan, Retry, Log, and Del actions. Log shows current scan progress and errors while active, and reopens the latest completed scan details afterward.
- The path is the top detail; current scan state is below it, and the right-aligned tally shows processed items over total items. A green check means a complete non-empty scan, yellow means some files did not process completely (or Trim Missing changed the path), and red means the scan found no playable files.

## Playback

- Long Play: enable shared extended playback.
- Duration: set a manual playback target.
- Library Behavior: Playlist Follows Cursor and Double-Click Enqueues are playback controls.

## Interface

- Spectrum analyzer: choose base, peak, and cap colors.
- Database sidebar: set the sidebar font size in points.
- Database sidebar: choose primary, secondary, or tertiary text color.
- Database sidebar: enable a monospaced font or Console View grouping.
- Reset restores the database sidebar to the default primary 12pt appearance.

## Window

- Options opens in a native titled macOS window.
- The window is 1280pt wide and 720pt tall.
- The sidebar contains Database, Interface, and Playback components in alphabetical order.

## Files

- [OptionsView.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/OptionsView.swift)
