# Options

- The Options window stays above CocoaSpice while it is open.

## Library

- Scan roots: add and manage folders used by the database.
- Library Paths: Add Path, Enable All / Disable All, Reset Paths, Scan All, and Test Links are the library-wide controls. The compact circled-check control switches every configured path on or off together. Reset Paths asks for confirmation before removing every configured path; retained indexed data remains available if a path is added again. Test Links marks missing indexed sources dead while retaining their metadata for rediscovery.
- Scanner Options: Deep Scan is the sole scanner setting. It makes Scan and Scan All re-inspect every discovered file, including unchanged archives, and replaces the root's live indexed results with the fresh scan.
- Stop Scan: stops the active scan without removing indexed library entries already written.
- Data: is a separate Options sidebar page with Database and Cache panels.
- Database: reports total indexed tracks, unlinked tracks, and unlinked sources. It retains file data when files move on disk to speed up scans; Clean Unlinked permanently removes retained unlinked sources and their tracks, metadata, and scan inventory. One unlinked source can retain many tracks, especially an archive, so the source and track counts need not match. Its count and cleanup work begin only when this Data panel is opened, run in the background, and refresh the sidebar only after cleanup completes. Reset Database asks for confirmation, then removes all indexed files, metadata, scan inventory, and scan status while retaining configured library paths.
- Cache: defaults to on with a 2 GB limit; choose 2 GB, 4 GB, 8 GB, or 16 GB. The panel reports cached usage, file count, and free space on the cache volume. Cached archive material is pruned least-recently-used after a successful materialization. Cache off uses disposable playback storage, removed when playback stops. At launch, CocoaSpice removes only its own abandoned scan scratch, disposable playback material, incomplete extraction staging, and obsolete cache-layout entries. Every archive materialization reserves 1 GB of free disk space and refuses material that cannot fit its active storage limit. Clear Cache stops playback and removes cached or disposable archive material; it is unavailable while a library scan is running.
- Scan Status: a separate bottom Library panel slides in only while a scan or Test Links is active. It shows separate fixed one-line Current Activity, File Path, and File Name fields, each shortened in the middle when necessary, plus a full-width progress bar and the only cancel control, so library-path rows never shift while work is running.
- Test Links checks only whether each unique indexed source path exists, then reports checked and found-unlinked source totals before hiding confirmed-missing sources while retaining their tracks, metadata, and scan inventory. It does not detect changed files or archives, open archives, or read metadata; use Scan or Scan All to refresh changed content. Rediscovery restores an unlinked source; only Clean Unlinked or Reset Database permanently discards it.
- Library paths are automatically sorted by path. Each compact row has enablement, its green/yellow/red result icon, an abbreviated path with the full path on hover, and glyph actions for Scan, Log, and Delete. Enablement changes immediately, then coalesce into one background persistence/sidebar refresh so several checkboxes can be changed without waiting. The row Scan action works even when that path is unchecked, without enabling it for the Database or Scan All. Scan reuses prior results for unchanged successful files unless Deep Scan is checked; failed or changed files are attempted again automatically.
- Scan requests queue behind an active scan instead of interrupting it. Stop clears the active scan and all pending scans. Test Links is unavailable while scanning.
- Logs use a stable `Scan Log` window title and a header line for scan date, duration, success/total, and issue count; the body is the error list.
- A grey outlined check means the path has not been scanned yet; green means a complete non-empty scan, yellow means some files did not process completely (or Test Links changed the path), and red means the scan found no playable files.

## Audio

- Volume: its explanation appears directly below the panel heading; the App Volume slider lowers CocoaSpice playback from its standard 100% output level without adding gain. macOS volume keys continue to control system volume.
- Mono: combines the left and right channels and duplicates that mixed signal to both speakers.
- Interface Style: one font size, color, and monospace setting applies consistently to both the database sidebar and playlist.
- Options opens on Library after a new app launch without restoring a prior control focus. Its page stays selected only while the app remains open.
- Equalizer: enable ten shared 31 Hz–16 kHz bands, adjust each by ±12 dB, and reset all gains to flat. The setting applies to every playback format and can also be toggled from the main toolbar.

## Playback

- Long Play: enable shared extended playback.
- Duration: set a manual playback target.
- End Fade: enable or disable the standard six-second fade. With it off, metadata-timed tracks use their native ending.
- Faded Skip: optionally uses that same six-second duration for Next and Previous while the live source continues playing; press again to advance immediately.
- Library Behavior: Playlist Follows Cursor applies to the Games browser; the Files browser queues only on double-click or Return. Double-Click Enqueues remains a playback control for Games.
- Playback Diagnostics: reports current PCM buffer headroom plus per-track underruns and source over-scale samples. These counters reset for each new track; source clipping cannot detect amplifier or speaker distortion.

## Interface

- Spectrum analyzer: off by default. It analyzes audio 10 times per second and redraws the compact toolbar widget at 60 FPS only while enabled and playing; it stops completely when hidden or stopped. Choose 10, 20, or 40 full-range bands and Spectrum Base, Peak, and Cap colors; Reset restores the default colors.
- Spectrum analyzer: 10/20/40 means 1/2/4 bands per octave from 20 Hz through 20.48 kHz.
- Spectrum analyzer: `Enable Spectrum` can disable spectrum analysis and its toolbar display while playback continues.
- Random playback: the main toolbar cycles between Off, Library random, and current Playlist-view random modes.
- About: the macOS application menu opens the external-component inventory with source and license links.
- Sidebar and Playlist appearance cards flow side by side when space permits and stack in a narrow Options window.
- Database sidebar: set 6–18pt font size, primary/secondary/tertiary color, and system fixed-width text.
- Playlist: set 6–18pt font size, primary/secondary/tertiary color, and system fixed-width text for every track-table text column.
- Each appearance card Reset restores its own default primary 12pt appearance.
- Sidebar Options: Group by Console sorts the Database game list into consoles using metadata and parent-folder information. Files Disclosure Gap sets 0–16 pt spacing between folder triangles and names in Files view. Hide File Extensions changes only Files-view labels, never filenames stored by the database or passed to playback.
- Every Options panel places a horizontal rule below its heading. Checkbox options use a leading checkbox with any explanatory text aligned beneath its label.

## Window

- Options opens in a native titled macOS window.
- The window initially opens at 800pt wide and 600pt tall, can be freely resized down to 320pt by 240pt, and remembers its last size and position.
- Windows Reset restores the default size and centered position for the main, Options, and About windows.
- The Options sidebar is alphabetized: Audio, Data, Interface, Library, Playback, and Plugins.
- Plugins currently lists the external decoder/emulation software and versions used by CocoaSpice. It is an inventory only; runtime plugin loading and configuration are not exposed there yet.

## Files

- [OptionsView.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/OptionsView.swift)
