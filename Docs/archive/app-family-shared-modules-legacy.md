# App Family Shared Modules — Current Architecture and Remaining Work

## Current Production Boundary

CocoaSpice is the native SwiftUI frontend/reference application for the current
app family. VGMBoy owns the shared playback/decoder core and compiled
dependency staging used by the family.
ScanSong is the only schema-23 catalog writer. CocoaSpice and SPCBoy select
and validate a catalog, open it through OS-level read-only SQLite handles, load
stored rows into playlists, and play those rows without database writeback.

The former Library controls in both players are read-only catalog status pages.
Root mutation, scanning, repair, metadata persistence, and projection building
belong to ScanSong. SPCBoy's JavaScript catalog scanner has been removed.

ScanSong currently lives in its own repository so its process and package
boundaries remain explicit. The eventual app-family repository may contain
multiple frontends while continuing to build the scanner and catalog reader as
separate modules:

- CocoaSpice: native SwiftUI frontend/reference application.
- SPCBoy: Electron frontend with the current web UI.
- SWIFTBoy: planned Swift core plus WKWebView frontend using the SPCBoy skin.
- ScanSong: native GUI/CLI and sole catalog writer.
- VGMBoy: playback/decoder core, dependency staging, and scanner-facing
  inspection plugin builds.

## Completed Verification

- ScanSong creates schema-23 catalogs, stages a full root, checkpoints one
  complete loose source or archive, resumes validated checkpoints, and
  publishes atomically.
- Cancellation retains unpublished completed work and leaves the prior live
  library intact.
- TAR.ZST extraction uses a bounded complete temporary TAR and no longer relies
  on an early-closing producer pipe. The two reported Hoot fixtures completed
  as 56 tracks with no zstd exit-code-13 failures.
- NSF/GBS and other libgme containers enumerate native child tracks.
- CocoaSpice's integration test reads a ScanSong catalog through its
  production read-only adapter and resolves the stored game into a playable
  playlist row.
- SPCBoy's canonical-reader test resolves a stored game into its playback row,
  exposes no mutation API, and uses an OS-level read-only SQLite worker.
- The writer uses rollback-journal (`DELETE`) mode, leaving one self-contained
  database file that either player can open without WAL/SHM writes.
- ScanSong loads attached roots from the selected catalog, displays
  per-root unscanned/clean/issue status, and treats checked roots as the scan or
  detach selection.
- Test Files validates distinct physical sources and marks missing sources in
  `dead_sources` without deleting track, metadata, inventory, or fingerprint
  rows. Both readers already hide those inactive rows. Clear Dead Links is the
  confirmed destructive purge.

## Scanner and decoder ownership

ScanSong consumes inspection executables built through VGMBoy's explicit
boundary. It does not reach into CocoaSpice's application target or launch
player helpers. VGMBoy currently builds the vgmstream scanner CLI and the
Highly Complete inspection product; the shared upstream source checkout is in
VGMBoy's shared source garden. CocoaSpice has no local decoder source or plugin build path.

Correctness gaps remain feature work, not ownership migration. A source
requiring one of these adapters currently fails explicitly and retains the last
known-good catalog rows instead of publishing an invented single track.

1. Add/extend vgmstream required-dependency resolution and
   subsong enumeration, including TXTP and bank/container families.
2. Add bounded gzip-aware VGZ GD3/timing inspection equivalent to plain VGM.
3. Audit PSF/PSF2, USF, 2SF, and SSF dependency families against representative
   loose and archived sets; direct tags alone must not hide structural needs.
4. Add malformed/truncated fixtures and child-process termination tests for
   every external archive/decoder adapter.
5. Add unique, collision-safe relocation recognition for inactive sources so a
   moved file can reuse retained metadata by strong fingerprint. Same-path
   restoration works now; path-independent matching is not yet claimed.

## CocoaSpice Cleanup Tranche

CocoaSpice is no longer the owner of scanner-plugin or playback-core build
outputs. Its build delegates shared dependency staging to VGMBoy, while the
shared upstream source checkout remains here until a separate source-relocation
pass can validate every consumer. Production does not open the writer or scan
controller. Remaining cleanup is therefore limited to:

1. Remove legacy schema migration and catalog-write sources from the CocoaSpice
   application target.
2. Remove obsolete scan-controller, staging, projection-write, and metadata
   writeback tests, retaining reader and ScanSong integration coverage.
3. Split playback-only archive materialization from any remaining scan-named
   types and files.
4. Make `ScanSongKit` and a shared read-only `MediaCatalogKit` explicit
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

The ordinary Scan is already the fast path: it performs required discovery and
structure work, reuses matching fingerprints/checkpoints, and permits optional
metadata for known single-track sources to remain empty. Rebuild bypasses reuse
and runs every metadata adapter currently available. Required child/dependency
discovery may not be deferred. Add a separately named Fast Scan mode only if
measurements show that the current incremental path is insufficient.

## Repository Direction

Do not merge the repositories until module boundaries are independently
buildable and their tests run without a frontend. A future monorepo should keep
separate products/targets for scanner writer, catalog reader, playback core,
CocoaSpice, SPCBoy, SWIFTBoy, and developer tools. Repository consolidation
must not recreate shared behavior by source copying.
