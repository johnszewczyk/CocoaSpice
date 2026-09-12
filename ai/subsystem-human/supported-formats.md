# Supported Formats

CocoaSpice admits the formats registered by its bundled VGMBoyKit playback core.
The authoritative extension list, decoder routes, upstream versions, and licenses
are maintained in [VGMBoy's README](../../../VGMBoy/README.md).

## Catalogs and Direct Imports

- A ScanSong catalog controls which library rows and subtracks appear in the
  Database browser. CocoaSpice displays its published metadata unchanged.
- Finder drops and `.m3u` files accept files that VGMBoyKit registers as playable.
  Direct imports use filename-derived display fallbacks; CocoaSpice does not read
  tags or decoder headers to enrich them.

## Archives

- ZIP, 7z, LHA, RSN, and TAR+Zstandard (`.tar.zst` and `.tzst`) containers can
  contribute playable members to a queue.
- CocoaSpice owns archive materialization for a selected member. VGMBoyKit receives
  a naked playable path and never receives an archive or catalog connection.
- LHA members use the same 7zz extraction route as 7z members. Amiga UADE files
  are admitted by their path prefix (for example `mod.title` or `med.song`),
  not by the final filename suffix, and their archive is expanded as a complete
  set so sibling data files remain available to the decoder.
