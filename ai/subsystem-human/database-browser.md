# Database Browser

## Display

- Database: scanned game-music library in the left pane.
- Favorites: Command-Shift-D replaces the playlist with a snapshot of shared
  Favorites without changing the current sidebar view. Command-D toggles the
  selected track or selected game/group. Options > Database > Favorites chooses
  Historical (added order) or Alphabetical display for the next snapshot.
- Local Files: Options > Database can choose one folder and enable direct disk browsing. This disables the database library until Local Files is turned off. Command-O opens a file or folder into this browser.
- Rows: dense list of scanned games by default.
- Path View: the sidebar mode button switches to a folder tree built only from scanned database records. It uses the same dense native row style as Console View, with `▾`/`▸` disclosure glyphs and nested text indentation. It loads only when opened and starts with library roots collapsed, so a very large collection does not delay launch.
- Files: selecting a source file queues its stored tracks; archive files remain one source-file leaf and queue their indexed members.
- Files: source-file leaves are stored with the scan database. Opening or revisiting Files reads that stored tree; it does not regroup every indexed track.
- Group by Console: Options can group games under expandable console headings. `Prefer Folders over Metadatas` uses the catalog's recognized parent console folder (including the parent of a `.tar.zst` game archive) before embedded console metadata; when that folder tag is empty, the embedded metadata fills the gap. Disabling it reverses that source priority. Changing it reloads the read-only sidebar without rewriting the catalog.
- Game names: use the inspected game tag when present, otherwise the archive filename for archived tracks or immediate parent-folder name for loose tracks. A recognized terminal console tag is omitted from an archive game name, while unrelated suffixes such as `[USA]` remain part of the title.
- Rows: show track counts and scan-root status. The same game/system scanned from different library paths remains separate; only those duplicate rows include their compact source-root name (for example, `JoshW` or `SNESMusicOrg`).
- ScanSong incremental scans retain successful unchanged ZIP, 7z, and TAR+Zstandard archive results instead of re-inspecting their playable members.
- When a changed archive is rescanned, its stored member set is replaced as a whole. Renamed or removed members therefore cannot remain in the Database after a repack.
- While ScanSong writes, CocoaSpice continues showing its opened read-only snapshot. Choose Options > Database > Reload Library after publication to consume the current catalog without restarting or interrupting playback.
- If a database sidebar read fails, the existing list remains available and an inline Retry message shows the error instead of presenting an empty library.
- Database reads show a loading status while the indexed snapshot is being obtained; the database view never expands by walking source folders.

## Search

- Search: accepts typing immediately, waits 250 ms before a new first-character query, then filters follow-up typing after 100 ms.
- Search: temporarily presents the indexed game results in the dense list while preserving the stored Games or Files mode. Clearing it returns to that mode.
- Search: matches game titles and compact source-root names; console headings organize the results but are not an additional search field.
- Search: preserves the active database selection when the query changes.
- Search: Return and list navigation act on the visible indexed game results even when Files is the covered underlying view.
- Search: clearing the query folds all Group by Console headings, returning the sidebar to its compact state.

## Selection

- Selection: supports native multi-selection and drag-range selection in both Games and Files views.
- Files: selecting a folder only expands or collapses it. Selecting a
  multi-track source or archive populates the playlist; a single-track file
  remains selection-only until double-click or Return.
- Files: dragging selected file rows to the Playlist appends their stored tracks without rescanning their sources.
- Files: clicking a single archive source immediately loads its stored archive-member tracks into the playlist.
- Files: right-click offers Show on Disk, Set as Playlist, and Add to Playlist for source files and folders. Folder actions use the clicked folder and include all of its indexed descendant leaves.
- Context menu: opens without changing the selected row.

## Activation

- Rows: double-click follows the configured activation behavior.
- Rows: Return loads the selected game or games into the playlist.
- Files: double-clicking a folder replaces the playlist with all indexed descendant files. Double-clicking selected file rows or pressing Return replaces the playlist with those files.
- Repeated activation of scanned games or files loads their stored playlist rows directly from the database without rescanning or archive extraction.

## Files

- [MainView.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/MainView.swift)
- [LibraryDatabase.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase.swift)
- [LibraryModels.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/LibraryModels.swift)
