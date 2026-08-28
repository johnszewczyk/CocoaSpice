# Container Proposal

## Purpose

This document records the container boundary agreed for CocoaSpice,
SPCBoyWK, ScanSong, and VGMBoy. The goal is predictable intake and playback
without making either frontend own a decoder or inventing a second archive
engine.

## The important distinction

Zstandard (`.zst`/`.zstd`) is a compression codec, not a ZIP-like archive
format. A plain Zstandard frame normally has no member listing and does not
carry a reliable user-facing filename. A single-file payload therefore uses
an explicit basename convention when the original filename is available:

```text
track.vgm.zst   ->   track.vgm
song.flac.zstd  ->   song.flac
```

The inner suffix is the playable format identifier. ScanSong admits a
standalone Zstandard file only when that suffix is registered as a playable
format. A bare `file.zst` with no inferable playable suffix is rejected rather
than guessed or published as an opaque track.

This convention is not required for ZIP files because ZIP has an internal
member name and listing. It is needed here because standalone Zstandard does
not provide that archive layer.

## Proposed CS indexed archive/capsule

The larger opportunity is not to invent a replacement audio encoding. It is to
define a CS-aware archive that preserves the original playable files while
making their catalog metadata available without opening a decoder.

The working conversion should therefore be lossless at the payload level:

```text
original.nsf  ->  CS capsule containing original.nsf bytes
```

Unpacking the capsule must reproduce the complete original `.nsf` byte for
byte. The packer must not normalize, merge, rewrite, or translate NSF, SPC,
VGM, QSF, or other source formats. A `.nsf` remains an NSF; it is simply a
named payload member inside the capsule. Multi-file sets retain every original
file, including dependency files such as `miniqsf` libraries, rather than
creating a synthetic replacement file.

The capsule would put a bounded manifest/index near the beginning of the file,
followed by payload members stored in independently addressable Zstandard
frames. A manifest entry can contain:

- original basename and format extension
- raw payload size and BLAKE3 identity
- compressed-frame offset and size
- game, track, author, system, comment, timing, loop, and fade metadata
- track ordinal and total track count
- decoder/backend and dependency relationships
- metadata provenance and generator version

ScanSong could catalog the manifest without extraction or decoder startup.
CocoaSpice could locate the selected payload, decompress only that frame, and
pass the original bytes to VGMBoy. Independent frames preserve random access
and parallelism; an optional solid group mode can improve compression for
related dependency files when random access is less important.

The manifest is the fast catalog view, not a substitute for source truth. The
raw-member hash and extraction-size checks must remain authoritative. Metadata
can be regenerated from the preserved source if a future scanner improves its
interpretation. An optional editable metadata overlay may be useful, but it
must never silently alter the preserved payload or its provenance.

The extension is intentionally undecided. `UAC` sounds universal and implies
a broader standard than this format needs. `CUP` is a good CocoaSpice joke but
does not explain the format outside the app. A descriptive working name such
as `CS Capsule` or `CS Archive` is clearer until the header and ownership
boundary are settled.

## Container taxonomy and precedence

| Input | Meaning | Listing | Materialization |
| --- | --- | --- | --- |
| `track.ext` | Ordinary playable file | Not applicable | Pass the file to VGMBoy |
| `set.zip`, `set.7z`, `set.rsn` | Multi-member archive | Tool listing | Selected member or complete set, as required by VGMBoy |
| `set.tar` | Multi-member TAR | TAR listing | Selected member or complete set |
| `set.tar.zst`, `set.tar.zstd`, `set.tzst` | TAR compressed with Zstandard | Decompress into TAR listing/extraction stream | Selected member or complete set |
| `track.ext.zst`, `track.ext.zstd` | One payload compressed with Zstandard | One implicit member from the basename | Decompress that one payload |
| `set.<future-cs-extension>` | Metadata-indexed CS archive/capsule | Read front manifest/index | Selected original payload or dependency set |

Detection must check TAR+Zstandard names before the standalone suffix. Thus
`set.tar.zst` and `set.tar.zstd` can never fall through to standalone handling.
The same rule applies in ScanSong discovery, CocoaSpice dropped-file listing,
and shared playback materialization.

## Ownership and data flow

1. ScanSong owns catalog discovery, archive intake, native metadata inspection,
   and schema-23 publication. For a standalone Zstandard source it
   materializes one payload into disposable scan scratch, then inspects the
   extracted file using the normal registered format route.
2. CocoaSpice and SPCBoyWK own presentation, queue behavior, and frontend
   adapters. They do not access playback codecs or duplicate archive engines.
3. FrontendCore owns the shared native archive taxonomy, command routing,
   cache-backed playback materialization, path validation, and the selected
   member versus complete-set boundary.
4. VGMBoy owns format admission at playback, decoder access, timing, fade, and
   output. The frontends pass VGMBoy a normal extracted file path, never a
   decoder-specific archive implementation.

For `track.ext.zst`, the catalog identity remains the source archive plus its
implicit member name (`track.ext`). At playback, the shared materializer runs
Zstandard once into the configured disposable or durable cache and returns
that extracted path to VGMBoy. CocoaSpice and SPCBoyWK therefore use the same
materialization machinery and the same format-specific playback requirement.

## Dependency boundary

A standalone Zstandard file contains one payload. It cannot satisfy a format
whose playback requirement is a complete decoder/dependency set, such as a
PSF/USF family that needs sibling libraries. Those requests must fail
explicitly; they must not silently invoke a fallback or pretend that the
single payload is a complete archive.

This does not change LongPlay, natural duration, fade, or decoder policy.
Those remain VGMBoy concerns after the extracted file reaches the shared
playback core.

## Streaming decision

The current implementation intentionally materializes standalone Zstandard
payloads. This is the smallest correct boundary because VGMBoy currently
opens a playable path, not an arbitrary decompression stream. Large payloads
must be decompressed somewhere before path-based playback; small payloads do
not justify a second streaming/cache protocol.

TAR+Zstandard retains its existing stream topology (`zstd -dc` into TAR) for
listing and selected extraction. A future streaming design would need an
explicit VGMBoy stream/file-descriptor contract, bounded output handling,
cancellation, cache policy, and format-specific seek requirements. It should
not be introduced by treating standalone `.zst` as a fake ZIP archive.

## Safety and cleanliness rules

- Preserve TAR+Zstandard behavior and precedence.
- Validate source/member paths and reject traversal or symlink escapes.
- Enforce the scanner's expanded-size and member-count limits.
- Keep extraction cancellable and remove failed scratch output.
- Never invent a playable row for an unknown standalone `.zst`.
- Never stage or commit `.DS_Store`, editor swap files, build output, caches,
  or other generated junk.

## Current implementation status

The shared `ArchiveMaterializationCore` recognizes
`singleFileZstandard`, routes its payload through `zstd -d -q -c`, and rejects
complete-set requests for that container. ScanSong recognizes and scans the
implicit member. CocoaSpice recognizes the same member during dropped-file
playlist construction. SPCBoyWK already reaches the same shared playback
materializer through its thin native adapter.
