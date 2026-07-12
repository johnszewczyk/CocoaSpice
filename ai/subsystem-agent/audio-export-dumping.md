# Audio Export Dumping

## Scope

- Current export or dump behavior.
- Existing seams for right-click export actions.
- Metadata already available for tagged audio export.

## Current State

- Selected playlist rows can export to native AAC `.m4a` files through a right-click queue action or the Edit command path.
- Export always targets built-in macOS AAC encoding at `256 kbps`.
- Export runs off the live playback path with fresh decoder instances, so current playback is not stopped or repurposed for conversion.
- Export reuses the centralized decoder-routing factory, so both `libgme` and `libvgm` formats dump through the same app-side path.
- Export reuses existing format-agnostic metadata fields and maps them into AAC tags:
  song to title, author to artist, game to album, system to genre, and comment to comment.
- Export names files as `[Game Name] - [TN] - [title].m4a` when metadata is available.
- Export remembers the last chosen output folder.
- Export opens a small utility progress window sized for simple batch feedback:
  one progress bar,
  output path,
  and output filename on separate lines.
- The progress window closes automatically when the export finishes.
- The exporter renders stereo PCM at `44.1 kHz` before handing it to the AAC writer.
- Export uses the same playback timing plan logic as live playback, including the current fade setting.

## Rules

- Keep export separate from live playback scheduling; the rolling playback queue is not the export pipeline.
- Reuse the centralized decoder routing instead of branching by extension in UI code.
- Reuse existing metadata fields rather than inventing format-specific tag mapping in the menu layer.
- Keep the export UI minimal and non-blocking; it is progress feedback, not a second editor surface.

## Files

- [PlaybackDecoderRouting.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaybackDecoderRouting.swift)
- [PlaybackEngine.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaybackEngine.swift)
- [AudioExportAAC.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/AudioExportAAC.swift)
- [AudioExportProgressWindow.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/AudioExportProgressWindow.swift)
- [SPCModels.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/SPCModels.swift)
- [PlaylistTableView.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaylistTableView.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
