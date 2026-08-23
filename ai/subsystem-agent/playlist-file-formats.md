# Playlist File Formats

## Scope

- Playlist file save and load behavior.
- Multi-track playlist identity persistence.
- M3U-specific app extensions.

## Current State

- The app saves and loads playlists as `.m3u`.
- Export writes a standard `#EXTM3U` header.
- Multi-track container identity is preserved through `#COCOASPICE:` metadata lines that record `trackIndex` and `trackCount`.
- Import accepts absolute paths and paths relative to the playlist file location.
- Import discards missing files and unsupported extensions rather than failing the entire load.
- Playlist file encode and decode now live in a dedicated codec helper rather than inline in the main view model.

## Rules

- Keep playlist file parsing separate from queue editing and playback control.
- Preserve multi-track playable identity through save or load.
- If the playlist file format changes, document the app-specific extension behavior here.

## Files

- [PlaylistM3UCodec.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/PlaylistM3UCodec.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
- [CocoaSpiceApp.swift](/Users/john/Downloads/Code/VGMMan/CocoaSpice/Sources/CocoaSpice/App/CocoaSpiceApp.swift)
