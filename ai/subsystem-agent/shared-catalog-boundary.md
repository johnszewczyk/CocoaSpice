# Shared Catalog Boundary

## Scope

- Selected catalog path, visible roots, and the boundary between CocoaSpice and
  the standalone MediaScanner.

## Ownership

- MediaScanner owns root mutation, Scan, Rebuild, cancellation, resume,
  diagnostics, link maintenance, and every catalog write.
- CocoaSpice owns only catalog path selection and read-only presentation of the
  roots and scan status already stored in that catalog.
- `OptionsView` directs users to MediaScanner for catalog maintenance.

## Invariants

- CocoaSpice never initializes a scan controller in its production app model.
- Library-root and maintenance controls are disabled in CocoaSpice.
- The selected catalog is validated as schema 23 before its path is persisted.
- A catalog switch requires restart and never replaces a live SQLite handle.
- MediaScanner publishes a self-contained rollback-journal database so the
  player can use a true read-only handle without sidecar-file writes.
- Playback archive materialization and cache remain CocoaSpice-owned transient
  playback concerns; they never become scan writes.

## Failure Boundaries

- Missing, invalid, or incompatible catalogs surface an error; CocoaSpice does
  not create or repair them.
- Query failure retains the last valid sidebar snapshot.
- Playback-time metadata may update the in-memory playlist only.

## Files

- [OptionsView.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/OptionsView.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
- [LibraryDatabase.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase.swift)
- [CanonicalCatalog.swift](/Users/john/Downloads/Code/MediaScanner/Sources/MediaScannerKit/CanonicalCatalog.swift)
- [MediaScannerCatalogIntegrationTests.swift](/Users/john/Downloads/Code/CocoaSpice/Tests/CocoaSpiceTests/MediaScannerCatalogIntegrationTests.swift)
