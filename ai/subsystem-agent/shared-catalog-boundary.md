# Shared Catalog Boundary

## Scope

- Selected catalog path, visible roots, and the boundary between CocoaSpice and
  the standalone MediaScanner.

## Ownership

- MediaScanner owns root mutation, Scan, Rebuild, cancellation, resume,
  diagnostics, link maintenance, and every catalog write.
- CocoaSpice owns only catalog path selection, explicit read-only reload, and
  presentation of indexed games and files.
- `OptionsView` directs users to MediaScanner for every catalog-maintenance action.

## Invariants

- CocoaSpice never initializes a scan controller in its production app model.
- CocoaSpice exposes no library-root or maintenance controls.
- The selected catalog is validated as schema 23 before its path is persisted.
- A catalog switch requires restart and never replaces a live SQLite handle.
  Reloading the active catalog is safe: it invalidates read-only sidebar
  snapshots and opens fresh reader connections without touching playback.
- MediaScanner preserves the catalog's durable SQLite journal mode (including
  WAL) so active CocoaSpice and SPCBoy readers can continue while it writes.
- Playback archive materialization and cache remain CocoaSpice-owned transient
  playback concerns; they never become scan writes.

## Failure Boundaries

- Missing, invalid, or incompatible catalogs surface an error; CocoaSpice does
  not create or repair them.
- Query failure retains the last valid sidebar snapshot.
- Playback telemetry may update the in-memory playback display only; it never supplies catalog metadata.

## Files

- [OptionsView.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/OptionsView.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
- [LibraryDatabase.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase.swift)
- [CatalogRootLoader.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/CatalogRootLoader.swift)
- [LibraryDatabase+ReadQueries.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase+ReadQueries.swift)
