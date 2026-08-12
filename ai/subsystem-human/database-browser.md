# Database Browser

## Display

- Database: scanned game-music library in the left pane.
- Rows: dense list of scanned games by default.
- Files: the standalone icon immediately left of the transport controls switches to a folder tree built only from scanned database records. It uses the same dense native row style as Games, with `▾`/`▸` disclosure glyphs and nested text indentation. Its own toolbar grouping distinguishes browser navigation from playback. It loads only when opened and starts with library roots collapsed, so a very large collection does not delay launch. It shows enabled library roots, scanned subfolders, and source files without live filesystem browsing.
- Files: selecting a source file queues its stored tracks; archive files remain one source-file leaf and queue their indexed members.
- Files: source-file leaves are stored with the scan database. Opening or revisiting Files reads that stored tree; it does not regroup every indexed track.
- Group by Console: Options can group games under expandable console headings. Embedded console metadata takes priority; streamed formats that only identify a decoder container use the nearest recognized console folder, so a GENH rip under Sega Saturn remains in Sega Saturn rather than 3DO.
- Rows: show track counts and scan-root status. The same game/system scanned from different library paths remains separate; only those duplicate rows include their compact source-root name (for example, `JoshW` or `SNESMusicOrg`).
- Incremental scans retain successful unchanged ZIP, 7z, and TAR+Zstandard archive results instead of re-inspecting their playable members.
- When a changed archive is rescanned, its stored member set is replaced as a whole. Renamed or removed members therefore cannot remain in the Database after a repack.
- During any scan, Games and Files continue showing the last completed library. Full scans build a hidden staged replacement and publish it only after scanning succeeds; incremental scans commit their changed-source transaction at the same boundary. A cancelled or failed scan keeps the previous library.
- If a database sidebar read fails, the existing list remains available and an inline Retry message shows the error instead of presenting an empty library.

## Search

- Search: accepts typing immediately, waits 250 ms before a new first-character query, then filters follow-up typing after 100 ms.
- Search: uses the same sidebar list rather than a separate results surface.
- Search: matches game titles and compact source-root names; console headings organize the results but are not an additional search field.
- Files search: matches the stored filename and path while preserving the folder hierarchy needed to reach matching source files.
- Files search: automatically opens every matching folder branch. Clearing search restores the folder folds that were open before searching.
- Search: preserves the active database selection when the query changes.
- Search: clearing the query folds all Group by Console headings, returning the sidebar to its compact state.

## Selection

- Selection: supports native multi-selection and drag-range selection in both Games and Files views.
- Files: selecting a folder only expands or collapses it; selection alone never changes the playlist.
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

- [MainView.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/MainView.swift)
- [LibraryDatabase.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase.swift)
- [LibraryModels.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryModels.swift)
