# Audio Export

## Export

- Export: selected playlist rows to AAC `.m4a` files.
- Export: preserves available track metadata.
- Export: shows the current output filename and concrete completed/remaining file counts.
- Export: uses separate current-file and whole-batch progress bars. The current-file bar is frame-based when the format supplies a concrete duration and indeterminate otherwise; the batch bar always advances from completed work.
- Export: can be cancelled from the standard progress window.
- Export: remembers the last output folder.

## Files

- [AudioExportAAC.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/AudioExportAAC.swift)
- [AudioExportProgressWindow.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/AudioExportProgressWindow.swift)
