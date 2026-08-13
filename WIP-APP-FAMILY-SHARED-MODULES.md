# App Family Shared Modules — Remaining Work

## Current Production Boundary

CocoaSpice is the parent/core application for the current app family.
MediaScanner is the only schema-23 catalog writer. CocoaSpice and SPCBoy select
and validate a catalog, open it through OS-level read-only SQLite handles, load
stored rows into playlists, and play those rows without database writeback.

The former Library controls in both players are read-only catalog status pages.
Root mutation, scanning, repair, metadata persistence, and projection building
belong to MediaScanner. SPCBoy's JavaScript catalog scanner has been removed.

MediaScanner currently lives in its own repository so its process and package
boundaries remain explicit. The eventual app-family repository may contain
multiple frontends while continuing to build the scanner and catalog reader as
separate modules:

- CocoaSpice: native SwiftUI parent/reference frontend.
- SPCBoy: Electron frontend with the current web UI.
- SWIFTBoy: planned Swift core plus WKWebView frontend using the SPCBoy skin.
- MediaScanner: native GUI/CLI and sole catalog writer.

## Completed Verification

- MediaScanner creates schema-23 catalogs, stages a full root, checkpoints one
  complete loose source or archive, resumes validated checkpoints, and
  publishes atomically.
- Cancellation retains unpublished completed work and leaves the prior live
  library intact.
- TAR.ZST extraction uses a bounded complete temporary TAR and no longer relies
  on an early-closing producer pipe. The two reported Hoot fixtures completed
  as 56 tracks with no zstd exit-code-13 failures.
- NSF/GBS and other libgme containers enumerate native child tracks.
- CocoaSpice's integration test reads a MediaScanner catalog through its
  production read-only adapter and resolves the stored game into a playable
  playlist row.
- SPCBoy's canonical-reader test resolves a stored game into its playback row,
  exposes no mutation API, and uses an OS-level read-only SQLite worker.
- The writer uses rollback-journal (`DELETE`) mode, leaving one self-contained
  database file that either player can open without WAL/SHM writes.

## Remaining Scanner Adapter Tranche

These are correctness gaps, not fallback requests. A source requiring one of
these adapters currently fails explicitly and retains the last known-good
catalog rows instead of publishing an invented single track.

1. Add a shared vgmstream adapter for required dependency resolution and
   subsong enumeration, including TXTP and bank/container families.
2. Move Highly Complete GSF/miniGSF dependency inspection into MediaScanner.
3. Add bounded gzip-aware VGZ GD3/timing inspection equivalent to plain VGM.
4. Audit PSF/PSF2, USF, 2SF, and SSF dependency families against representative
   loose and archived sets; direct tags alone must not hide structural needs.
5. Add malformed/truncated fixtures and child-process termination tests for
   every external archive/decoder adapter.

## CocoaSpice Cleanup Tranche

CocoaSpice still compiles its former scanner implementation because several
native decoder and archive adapters originated there. Production does not open
the writer or scan controller. After the adapters above live in MediaScanner:

1. Remove legacy schema migration and catalog-write sources from the CocoaSpice
   application target.
2. Remove obsolete scan-controller, staging, projection-write, and metadata
   writeback tests, retaining reader and MediaScanner integration coverage.
3. Split playback-only archive materialization from any remaining scan-named
   types and files.
4. Make `MediaScannerKit` and a shared read-only `MediaCatalogKit` explicit
   package products before combining repositories.

## Shared Reader Module

The two player adapters intentionally remain small, but their schema/version
validation and query semantics should converge into a shared read-only module:

- schema 23 and required-table validation;
- root/game/file/search projections;
- source/archive-member/subtrack identity;
- query-only and OS-level read-only connection enforcement;
- no migrations, directory creation, write pragmas, or mutation surface.

Swift frontends can link this module directly. Electron should continue using a
versioned process or narrow native boundary rather than duplicating SQL in the
renderer. Do not couple the reader to playback or UI models.

## Performance and Resilience Pass

Before changing concurrency or adding a user-visible Fast Scan mode, benchmark
a representative corpus containing loose files, small archives, solid
TAR.ZST, libgme multi-track containers, dependency sets, and malformed input.
Record cold/warm elapsed time by phase, bytes read/extracted, peak scratch/RSS,
database growth, reuse rate, cancellation latency, and sidebar-to-playlist
latency.

The default scan should remain structurally complete. Optional metadata for a
known single-track source may remain empty; required child/dependency discovery
may not. Add a second scan mode only if measured interaction, battery, or
throughput evidence justifies it.

## Repository Direction

Do not merge the repositories until module boundaries are independently
buildable and their tests run without a frontend. A future monorepo should keep
separate products/targets for scanner writer, catalog reader, playback core,
CocoaSpice, SPCBoy, SWIFTBoy, and developer tools. Repository consolidation
must not recreate shared behavior by source copying.
