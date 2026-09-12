# Options

- Windows has independent Always on Top switches for the main and Options windows; both default off. Main keeps CocoaSpice above other apps; Options keeps the Options window above the main window.

## Database

- CocoaSpice reads the selected ScanSong catalog but never modifies it. Scan paths, scanning, link checks, cleanup, and console-tag maintenance exist only in ScanSong.
- Database displays the configured shared `Library.sqlite` path in a full-width selectable path bar with a native folder button. Reload Library, Use Default, and Show in Finder are equal-width standard system buttons filling the bottom of the panel, in that order. Reload Library invalidates CocoaSpice's read-only browser snapshots and loads the catalog ScanSong has just published; it does not affect the current playlist or playback. Browse accepts only an existing ScanSong canonical schema-23 catalog and reports its track count; changing the location is persisted for the next launch and never swaps a live SQLite connection. The default is CocoaSpice's Application Support database.
- Cache: defaults to on with a 2 GB limit; choose 2 GB, 4 GB, 8 GB, or 16 GB from the right side of the Cache row. The row explains that decompressed files can be retained to reduce load time and reports `Usage: ...` on one subtext line. Cached archive material is pruned least-recently-used after a successful materialization. When disabled, playback uses disposable storage that is removed when playback stops. At launch, CocoaSpice removes only its own disposable playback material, incomplete extraction staging, and obsolete cache-layout entries. Every archive materialization reserves 1 GB of free disk space and refuses material that cannot fit its active storage limit. Clear Cache stops playback and removes cached or disposable archive material; Show in Finder opens the managed cache folder.

## Audio and Interface

- VGMBoy Audio order is Volume, Mono, Equalizer. Volume's explanation appears directly below the panel heading; the App Volume slider lowers CocoaSpice playback from its standard 100% output level without adding gain. macOS volume keys continue to control system volume.
- Mono: combines the left and right channels and duplicates that mixed signal to both speakers.
- Options opens on Database after a new app launch without restoring a prior control focus. Its page stays selected only while the app remains open.
- Equalizer: the Audio page keeps the ten shared 31 Hz–16 kHz bands visible at the top of the page, allows each to be adjusted by ±12 dB, and resets all gains to flat. The setting applies to every playback format and can also be toggled from the main toolbar.

## Playback

- Long Play: enable shared extended playback.
- Play Speed: independently enable and set tempo for libgme (SPC, NSF/NSFE, GBS, HES, KSS, AY, SAP) and libvgm (GYM, S98, VGM, VGZ, DRO). Decimal and fractional input is accepted and snapped to musical 1/32 increments before it is persisted through the shared VGMBoy tempo control.
- Duration: set a manual playback target.
- End Fade: enable or disable the fade and configure its duration (default six seconds). With it off, metadata-timed tracks use their native ending.
- End Fade: Faded Skip is appended to this panel and optionally uses that same configured duration for Next and Previous while the live source continues playing; press again to advance immediately. It is not a separate options page.
- Library Behavior: Playlist Follows Cursor applies to the Games browser. In
  Files view, selecting a multi-track source or archive populates the playlist;
  single-track files queue only on double-click or Return. Double-Click Enqueues
  remains a playback control for Games.
- Diagnostics: reports current PCM buffer headroom and per-track underruns from the bundled VGMBoy output. These counters cannot detect amplifier or speaker distortion.

## Export

- AAC Export Folder: a full-width selectable path bar with a native folder button chooses where `Export AAC` writes its output. The default is the user’s
  Downloads folder. CocoaSpice remembers only this folder preference; VGMBoy creates the sanitized,
  non-overwriting `.aac` filename and renders the audio offline.

## Interface

- Random playback: the main toolbar cycles between Off, Library random, and current Playlist-view random modes.
- About: the macOS application menu opens the external-component inventory with source and license links.
- Interface Style: font size, text color, and monospace settings apply consistently to both the database sidebar and playlist. Selection highlights use `NSColor.controlAccentColor`, so CocoaSpice follows the user's macOS accent and has no app-specific accent-color preference. CocoaSpice's standard macOS buttons and labels keep their native system styling.
- Each appearance card Reset restores its own default primary 12pt appearance.
- Sidebar Options: Group by Console sorts the Database game list into consoles. Prefer Folders over Metadatas chooses the scanned archive or file's parent console folder before embedded console metadata; disabling it reverses that preference. It is a read-only sidebar reload, not a scan or database rewrite. Files Disclosure Gap sets 0–16 pt spacing between folder triangles and names in Files view. Files Child Indent is a numeric 0–32 pt field that offsets every Files-view child level; its default 8 pt is about one character at the default font size. Hide File Extensions changes only Files-view labels, never filenames stored by the database or passed to playback.
- Library Behavior belongs to Interface: Playlist Follows Cursor applies to the
  Games browser. In Files view, multi-track sources and archives populate the
  playlist on selection; single-track files queue only on double-click or
  Return. Double-Click Enqueues remains a browser behavior control for Games.
- Every Options panel places a horizontal rule below its heading. Checkbox options use a leading checkbox with any explanatory text aligned beneath its label.
- Playlist Options: Column Auto-size defaults on and automatically resizes columns for content width on selection.
- Animations: Auto-Resize and Selection Bar are independently checkbox-enabled (both default on) and retain their configured 0–1000 ms values when disabled; disabling one makes its effective duration 0 ms.
- Shared ownership: preference persistence and cache policy come from FrontendCore; playback timing and AAC conversion come from VGMBoyKit. CocoaSpice supplies only its native controls, destination-folder choice, and archive materialization adapter.

## Window

- Options opens in a native titled macOS window.
- The window initially opens at 800pt wide and 600pt tall, can be freely resized down to 320pt by 240pt, and remembers its last size and position.
- Windows Reset restores the default size and centered position for the main, Options, and About windows.
- Interface > Animations exposes checkbox-enabled auto-resize and playlist/sidebar selection-bar durations. Both default on at 200 ms and accept 0–1000 ms.
- The Options sidebar is alphabetized within two groups: CocoaSpice contains Database, Interface, and Windows; VGMBoy contains Audio, Diagnostics, and Playback.
- The former Plugins inventory page is not part of Options. Component ownership and licenses remain documented in VGMBoy.

## Playback controls

- CocoaSpice's main window uses a native SwiftUI macOS toolbar for transport, Long Play, Repeat, Random, and Equalizer. SPCBoy WK exposes equivalent commands in its WKWebView toolbar; the command/state boundary is shared, but the SwiftUI toolbar view itself is not reusable by the HTML renderer.

## Files

- [OptionsView.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/OptionsView.swift)
