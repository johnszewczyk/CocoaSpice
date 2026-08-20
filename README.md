# CocoaSpice

CocoaSpice is the native macOS playlist and catalog frontend for the game-music app family.
It reads a published MediaScanner SQLite catalog, owns the editable queue and frontend behavior,
and bundles VGMBoyKit in-process for audio playback. It is not a scanner and it is not a separate
audio server.

## App-family boundary

| Component | Owns | Does not own |
| --- | --- | --- |
| MediaScanner | Catalog discovery, metadata, schema-23 SQLite publication, and sidebar projections | Playback, CocoaSpice playlists, or UI state |
| CocoaSpice | Read-only catalog browsing, playlist membership, queue transitions, repeat/shuffle, archive materialization, native UI, and macOS transport integration | Catalog writes, scanning, decoder bridges, or an audio device |
| VGMBoyKit | Format routing, decoder bridges, decoded transport, timing, Long Play, tempo, fades, ten-band EQ, and macOS audio output | Catalogs, playlists, repeat/shuffle, or frontend persistence |

The components communicate through files and in-process APIs:

1. MediaScanner publishes a schema-23 SQLite catalog.
2. CocoaSpice opens that database read-only and shows its stored Games and Files projections.
3. Activating a row performs one narrow stored playlist query. It publishes source, archive-member,
   subtrack, metadata, and column-hint values without rescanning, archive extraction, decoder work,
   filesystem probing, or catalog mutation.
4. When the user plays a row, CocoaSpice materializes a selected archive member if necessary and
   passes the naked playable path plus subtrack index to its bundled VGMBoyKit controller.
5. VGMBoy emits playback status and natural-end events. CocoaSpice applies the next playlist,
   repeat, shuffle, and UI decision.

SPCBoy continues to use its working playback implementation until its separate VGMBoy migration.

## What CocoaSpice does

- Opens an explicitly selected MediaScanner database read-only.
- Browses compact stored Games and Files projections without live filesystem browsing.
- Builds editable playlists from exact indexed game, source, folder, or path queries.
- Handles playlist navigation, repeat off/playlist/song, random scope, persistence, and native macOS UI.
- Materializes selected archive members for playback without modifying the source archive or catalog.
- Presents VGMBoy controls including play, pause, stop, seek, Long Play, tempo where supported,
  and the existing CocoaSpice-compatible ten-band EQ UI.

## Catalog and playlist rules

- MediaScanner is the only catalog writer. CocoaSpice never scans, creates, migrates, repairs, or
  enriches the opened database.
- Database queue hydration uses the proven exact `tracksAndMetadataFor…` read projections. Do not
  replace them with a generic all-track reader, fallback scan, decoder inspection, or table-cell I/O.
- Queue identity is source path, optional archive-member path, and subtrack index. A game identity
  includes its catalog root, game, and system, so matching titles in separate roots remain separate.
- Playback-time inspection is transient. It never writes back into the MediaScanner catalog.

## Playback formats and upstream cores

CocoaSpice admits the formats registered by the bundled VGMBoy core. The authoritative current
plugin list, upstream revisions, and direct build dependencies are maintained in
[VGMBoy’s README](../VGMBoy/README.md).

Supported archive containers are ZIP, 7z, RSN, TAR+Zstandard (`.tar.zst`/`.tzst`). CocoaSpice
owns archive materialization policy; VGMBoy receives a playable file path rather than an archive.

## Build and run

This checkout expects sibling `VGMBoy` and `CatalogReader` packages under the same parent folder.
MediaScanner is required only to create or update the catalog that CocoaSpice reads.

```bash
./build.sh
./launch.sh
```

`./launch.sh` packages and opens `dist/CocoaSpice.app`. Choose a published MediaScanner database
from CocoaSpice’s Database options if the default catalog path is not the desired one.

## Engineering documentation

Read [ai/project-info.md](ai/project-info.md) after the DocMan routing documents. Current
user-facing behavior is in `ai/subsystem-human/`; current ownership and constraints are in
`ai/subsystem-agent/`. Historical decoder and scanner implementation notes do not belong in this
frontend.

## License and notices

CocoaSpice bundles VGMBoyKit and therefore redistributes upstream components under their own
terms. Preserve the relevant notices in [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) and
the vendored source trees when distributing a build.
