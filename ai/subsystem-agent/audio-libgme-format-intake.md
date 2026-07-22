# Audio libgme Format Intake

## Scope

- File-type admission into the app.
- `libgme` file opening and metadata inspection boundaries.
- Format policy that currently lives above the decoder.
- Expansion constraints for adding more `libgme` formats.

## Current State

- `libgme` supports playback and metadata inspection for `ay`, `gbs`, `hes`, `kss`, `nsf`, `nsfe`, `sap`, and `spc`.
- SPC is registered as a single-track format so playlist rows publish immediately and hydrate metadata afterward. The remaining libgme formats retain explicit subtrack enumeration before queue insertion.
- Long Play is a shared app feature for supported game-music formats, using one common toggle and one manual duration target.
- With Long Play disabled, supported formats use file or decoder default playback behavior.

## Rules

- Treat `PlaybackEngine` as the generic streamed playback host, not a `libgme`-only shell.
- Treat extension filtering and playback-plan selection as separate policy layers; they should not be conflated.
- When broadening format support, update every intake surface that shares the scanner allowlist instead of only the live playback path.
- Keep user-facing timing controls unified unless a concrete backend constraint forces a split.

## Files

- [PlaybackEngine.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlaybackEngine.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
- [ZipArchiveSupport.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/ZipArchiveSupport.swift)
- [SPCFileScanner.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/SPCFileScanner.swift)
- [OptionsView.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/OptionsView.swift)
