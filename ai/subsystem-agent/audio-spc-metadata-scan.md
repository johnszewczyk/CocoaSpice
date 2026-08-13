# SPC Metadata Scan

## Current State

- Scanner inspection reads valid SPC ID666 and xID6 metadata directly through `SPCMetadataReader`; it does not create a libgme inspector for ordinary tagged SPC files. Deep Scan changes reuse policy only and uses this same metadata route.
- The reader recognizes legacy text and binary ID666 layouts, then applies xID6 song, game, artist, comment, and playback fields when present. A malformed xID6 suffix never discards an otherwise valid legacy ID666 tag.
- SPC files without readable ID666/xID6 metadata fall back to the generic libgme inspector so unusual valid files retain the decoder's behavior.
- An archive scan materializes the required set once, then inspects its members with bounded workers. Results are restored to archive-entry order before persistence.

## Rules

- Keep SPC metadata parsing separate from playback. Direct parsing is scan-only; live audio remains owned by libgme.
- Treat malformed SPC headers and malformed xID6 chunks without a valid legacy ID666 tag as scan errors rather than inventing metadata.
- Preserve the generic fallback for untagged SPC variants.
- Do not reintroduce serial inspection of all members after a successful archive-set materialization.

## Files

- [SPCMetadataReader.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/SPCMetadataReader.swift)
- [ScanCoreHandlers.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/ScanCoreHandlers.swift)
- [ScanPipelineExecutor.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/ScanPipelineExecutor.swift)
