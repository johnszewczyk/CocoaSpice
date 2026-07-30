# Options

- The Options window stays above CocoaSpice while it is open.

## Library

- Scan roots: add and manage folders used by the database.
- Library Paths: Add Path, Reset Paths, Scan All, and Test Links are the library-wide controls. Test Links marks missing indexed sources dead while retaining their metadata for rediscovery.
- Deep Scan: the checkbox below the library controls makes Scan and Scan All unzip and read metadata for every discovered file, including unchanged archives.
- Stop Scan: stops the active scan without removing indexed library entries already written.
- Data: is a separate Options sidebar page with Database and Cache panels.
- Database: reports total indexed tracks and unlinked tracks. It retains file data when files move on disk to speed up scans; Clean Links permanently removes only the retained dead sources and their tracks, metadata, and scan inventory. Its count and cleanup work run in the background, then the sidebar refreshes when complete. Clear Database removes all indexed files, metadata, scan inventory, and scan status while retaining configured library paths.
- Cache: shows the managed archive-cache size and file count. Clear Cache stops playback and removes cached archive material; it is unavailable while a library scan is running.
- Scanning: Library Paths shows one right-aligned 100pt progress bar in its header while a scan or link test is active; it hides when the operation completes.
- Test Links checks only whether each unique indexed source path exists, then marks confirmed-missing sources dead and hides them while retaining their tracks, metadata, and scan inventory. It does not open archives or read metadata. Rediscovery restores a dead source; only Clean Links or Clear Database permanently discards it.
- Library paths are automatically sorted by path. Each compact row has enablement, its green/yellow/red result icon, an abbreviated path with the full path on hover, and glyph actions for Scan, Log, and Delete. Scan reuses prior results for unchanged successful files unless Deep Scan is checked; failed or changed files are attempted again automatically.
- Scan requests queue behind an active scan instead of interrupting it. Stop clears the active scan and all pending scans. Test Links is unavailable while scanning.
- Logs use a stable `Scan Log` window title and a header line for scan date, duration, success/total, and issue count; the body is the error list.
- A green check means a complete non-empty scan, yellow means some files did not process completely (or Test Links changed the path), and red means the scan found no playable files.

## Playback

- Long Play: enable shared extended playback.
- Duration: set a manual playback target.
- End Fade: enable or disable the standard six-second fade. With it off, metadata-timed tracks use their native ending.
- Library Behavior: Playlist Follows Cursor applies to the Games browser; the Files browser queues only on double-click or Return. Double-Click Enqueues remains a playback control for Games.
- Playback Diagnostics: reports current PCM buffer headroom plus per-track underruns and source over-scale samples. These counters reset for each new track; source clipping cannot detect amplifier or speaker distortion.
- Equalizer: enable ten shared 31 Hz–16 kHz bands, adjust each by ±12 dB, and reset all gains to flat. The setting applies to every playback format and can also be toggled from the main toolbar.

## Interface

- Spectrum analyzer: choose 10, 20, or 40 full-range bands and Base, Peak, and Cap colors.
- Spectrum analyzer: 10/20/40 means 1/2/4 bands per octave from 20 Hz through 20.48 kHz.
- Spectrum analyzer: `Enable Spectrum` can disable spectrum analysis and its toolbar display while playback continues.
- Random playback: the main toolbar cycles between Off, Library random, and current Playlist-view random modes.
- About: the macOS application menu opens the external-component inventory with source and license links.
- Database sidebar: set the sidebar font size in points.
- Database sidebar: choose primary, secondary, or tertiary text color.
- Database sidebar: enable a monospaced font or Console View grouping.
- Reset restores the database sidebar to the default primary 12pt appearance.
- Playlist: enable a monospaced font for every track-table text column.

## Window

- Options opens in a native titled macOS window.
- The window initially opens at 800pt wide and 600pt tall, can be freely resized down to 320pt by 240pt, and remembers its last size and position.
- `Reset Windows` restores the default size and centered position for the main, Options, and About windows.
- The sidebar contains Library, Interface, Playback, and Plugins components.
- Plugins currently lists the external decoder/emulation software and versions used by CocoaSpice. It is an inventory only; runtime plugin loading and configuration are not exposed there yet.

## Files

- [OptionsView.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/OptionsView.swift)
