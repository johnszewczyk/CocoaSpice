# Library Scan Roots

## Scope

- Scan-root configuration.
- SQLite root persistence.
- Scan lifecycle and status.

## Current State

- `LibraryOperationsState` owns observable scan-root, scan/link-test progress (including clamping and aggregate-operation selection), database-cleanup, cache-cleanup, and sidebar-loading state, plus the active library-maintenance task and generation guard. `PlayerViewModel` forwards that state while retaining the UI-facing scan commands.
- Scan roots are configured from Options.
- Scan roots persist in SQLite.
- Adding a scan root starts a scan automatically.
- Scan progress counts source files and archives; a successful archive can produce many playable member rows.
- Root addition, recursive discovery, scan planning, archive inspection, and SQLite scan persistence run in a utility task with a dedicated database connection. The main actor receives only throttled status/progress publication, including an indeterminate preparing bar before discovery determines a total.
- Recursive discovery walks every accessible subdirectory explicitly, records supported files and archives, and reports inaccessible subtrees as scan issues.
- After inventory, file/archive inspection uses bounded concurrency. Archive extraction and decoder ownership remain independently bounded so neither can stall unrelated workers. libgme metadata inspection permits at most three concurrent decoder instances; other decoder backends remain serialized unless their module explicitly declares a safe higher limit.
- Archive scans report the current member filename while listing and inspecting a container, rather than appearing stuck on the outer archive filename.
- Scan status publication is throttled and does not await the main actor for every discovered member.
- The modern scan pipeline is the only scan route; root additions, per-root scans, and enabled-root rescans use it. It always creates complete indexed rows through normal archive member listing, extraction, metadata inspection, and multi-track expansion. Incremental selection skips successful entries whose file-size/modification fingerprint is unchanged. A fully successful ZIP, 7z, or TAR+Zstandard scan also persists a parent archive record containing only tool-reported details: 7-Zip's archive listing report for ZIP/7z and `zstd -lv`'s report for TAR+Zstandard. A matching report skips a timestamp-only archive change without extraction or decoder inspection; failed, changed, unsupported, and legacy-unfingerprinted entries are scheduled normally.
- On the first fresh member batch for a changed archive, scan persistence removes all prior member tracks and member inventory for that source before inserting the replacement set. This is intentionally archive-wide: TAR and archive tools may normalize member paths differently after a repack (such as adding `./`), and per-member replacement would retain obsolete metadata rows.
- Database schema 13 repairs rows created by the earlier per-member behavior once on launch. An archived track or member-inventory row whose outer file-size/modification fingerprint differs from its current parent archive record is stale and is removed; the current matching rows remain. This repair covers repacks that were scanned before archive-wide replacement existed, without requiring the source archive to change again.
- Scans use the vgmstream inspector for PlayStation XA and SVAG/IECS-family PlayStation 2 audio, so supported streams contribute decoder-derived subsongs, length, and loop metadata while file size remains part of the scan fingerprint.
- Scans have a scan-only metadata shortcut layer ahead of the decoder inspector. SPC reads ID666/xID6 and VGM/VGZ reads header/GD3 directly; PSF, PSF2, USF, and 2SF read their container `[TAG]` footer directly. The decoder remains the fallback for malformed files and for formats that need subtrack enumeration; malformed SPC extended metadata must never become a scanner failure by itself.
- `ScanMetadataShortcuts` is the single top-level registry for these per-format scan optimizations. Add a rule there only when the format has a reliable metadata-only source; every rule must return the normal `DecoderCoreScanHandler` fallback for malformed files, absent tags, or cases requiring subtrack enumeration. Do not add hidden one-off parser branches to the generic scan executor.
- Playback archive materialization and scan materialization are separate module contracts. Playback still materializes complete sets for GSF, 2SF, PSF/PSF2, and USF-family files so sibling libraries remain available. Tag-only PSF-family scans materialize only selected playable members; SPC and other independent members do the same. LazyUSF alias preparation remains a playback complete-set concern.
- Reset Database deletes indexed tracks, metadata, scan inventory, scan status, and scan logs for every root in one transaction, but never deletes configured root rows or their path, enabled, or ordering values. Options must obtain explicit confirmation before invoking it.
- Removing a library path detaches it from the active Database without deleting its indexed tracks or scan inventory. Re-adding the same path restores that root identity and uses the prior file-size/modification fingerprints for an incremental scan. Reset Database is the only action that deletes detached-root records.
- Remove Path and Reset Paths persist their detach operation through short-lived utility SQLite connections. Reset Paths requires an explicit Options confirmation before it detaches every active root. Test Links likewise reads its source inventory and persists missing-source marks off the main actor; all three publish their status through the active library-operation generation before refreshing visible state.
- A scan retains the existing library while it runs and persists each completed source/archive in one transaction, so a bad file or interrupted scan cannot erase already indexed results or force a transaction per archive member.
- The Library Paths panel inserts one full-width linear progress bar directly below its heading while a library operation is active. The bar uses a short ease-in-out slide/opacity transition and cancelling invalidates the active scan generation.
- The scan task yields once after publishing its active state so Options can render disabled scan-start controls and an indeterminate linear progress bar before setup starts. Keep progress publication lightweight; unthrottled per-candidate UI work can delay playback completion delivery and queue advancement.
- The visible Scan and Scan All controls run incremental mode unless the Options Deep Scan checkbox is set. Deep Scan runs `newScan`: it clears the live rows for each root and schedules every discovered source, bypassing same-fingerprint and archive-signature skips while preserving unlinked-source records. A same-size/same-modification-date source is not reopened only in incremental mode; a timestamp-only changed ZIP, 7z, or TAR+Zstandard archive gets a lightweight native signature check before any member inspection.
- A scan request received during an active scan is appended to the `LibraryScanRequestQueue` FIFO rather than cancelling the active work. The queue stores root IDs, not stale root values; on completion the next queued set resolves against current roots in request order. Requests whose roots were removed while waiting are discarded and do not prevent later queued scans. Stop cancels the active generation and clears pending requests.
- A new scan replaces live root inventory and track rows, while preserving sources marked unlinked. A rediscovered unlinked source is restored before selection so its existing fingerprint, archive signature, and metadata can be reused; only Reset Database or Clean Unlinked permanently removes those rows.
- `Fix Missing` performs one whole-library file-existence pass over unique active indexed source paths. It does not open archives or read metadata; it marks confirmed-missing sources unlinked and hides them. Options shows the checked/total count, progress bar, current source, and final mark result. Clean Unlinked is in the Database cleanup area, not scan controls, because it permanently removes the matching tracks, metadata, and scan inventory.
- Unlinked-source counts and Clean Unlinked use a short-lived `LibraryDatabaseMaintenance` SQLite connection on a utility task. They must not synchronously count or delete a large library on the main actor; cleanup refreshes roots and the database sidebar only after the transaction completes. Unlinked source count and unlinked track count are intentionally separate because an archive source can own many tracks.
- Archive subprocess completion is event-driven, while bounded cancellation checks and a timeout remain active. Successful tiny listings and extractions do not wait for a polling interval, and a failed 7z operation cannot strand a later retry.
- Scanner timeouts reflect the operation: archive listing has a 30-second boundary, metadata inspection 60 seconds, and archive extraction 10 minutes. The extraction window accepts valid large archives; it does not reduce concurrency or otherwise throttle fast machines.
- Archive listing and extraction stream standard output to short-lived files under CocoaSpice's managed archive cache rather than the system temporary directory or in-memory pipes. Their stderr pipe endpoints must be explicitly closed after every subprocess; otherwise a whole-tree scan eventually exhausts file descriptors and manifests as cascading archive, metadata, and SQLite failures.
- Scans materialize archive members into isolated `ArchiveCache/ScanScratch` directories. The scratch directory is removed as soon as every selected member of that archive has been inspected, including on extraction failure; scan extraction must never populate the durable playback cache.
- Durable playback-cache locations include the archive path, byte size, and modification time. A repacked archive therefore rematerializes for playback even if a preservation workflow restores its original modification time but changes its size.
- Options reports the managed archive-cache file count and size. Clearing it stops active playback first and is disabled while any library scan might own a scratch directory.
- ZIP listing and extraction both use 7-Zip path names; do not mix a separate ZIP lister with 7-Zip extraction, because legacy member encodings can otherwise resolve to different paths.
- Scans include playable members from ZIP, 7z, RSN, and TAR+Zstandard (`.tar.zst`/`.tzst`) archives. SPC files are inspected through libgme during scanning, so the stored metadata and duration match playback before a playlist is opened. Multi-track members are stored as one row per subtrack.
- TAR+Zstandard archive listings stream `zstd -d -c` directly into `tar -tf -`, avoiding full extraction before discovery and bypassing BSD tar's unreliable concurrent Zstandard helper. A normal downstream SIGPIPE, or zstd exit 70 whose stderr explicitly reports a write-error broken pipe, after tar finishes listing is not a listing failure. Selected-member and complete-set extraction both decompress through `zstd` into a short-lived plain TAR before extraction, avoiding BSD tar's unreliable Zstandard helper. Preserve TAR member names literally, including leading/trailing spaces; escape only TAR pattern metacharacters because BSD tar otherwise treats `*`, `?`, and `[` as patterns. Invalid filename bytes and BSD tar display-octal escapes such as `\\302\\255` are retained as reversible octal text for the UI/database, then decoded to original raw bytes through NUL-delimited tar selection input during extraction.
- A known non-playable archive member (such as a Silent Hill KDT1/SdDt sequence bank) persists as `unsupported` without a scan error. It still permits the parent archive completion marker, so incremental rescans do not repeatedly extract a healthy archive solely because it contains that documented resource type.
- SPC is registered as a single-track libgme format, so direct folder/archive playlist loading can publish its rows before metadata hydration. Multi-track GME containers retain pre-publication track enumeration; subsequent SPC metadata changes are coalesced into targeted table-row refreshes rather than structural playlist reloads.
- Scans read valid GD3 metadata and timing directly from tagged VGM/VGZ files, including gzip-compressed VGZ members. Untagged or malformed VGM/VGZ and the GYM/S98 formats retain the libVGM inspector fallback.
- LazyUSF archive members materialize their complete archive set into one cache directory so `.miniusf` files retain access to sibling `.usf` and `.usflib` dependencies.
- Database state restores from the existing database on launch and does not rescan automatically.
- The live SQLite handle remains open for the lifetime of the model; removing the last root does not delete the open database file.
- Database setup and scan-root persistence errors remain visible through scan status instead of being converted into an empty root list.
- SQLite persistence errors include the extended SQLite result code so a filesystem write failure can be distinguished from ordinary lock contention or malformed scan metadata.
- Each root's Log button opens a plain-text scan log. The stable native title identifies the root, and an in-window summary header carries live/completed statistics; the content is only error lines. Persisted logs and the text view are byte/row bounded, and historical issues are inserted as one batch so a failed large scan cannot stall or crash the app when Log opens.
- `scripts/scan-pipeline.sh <root>` runs the scan pipeline from the command line; `COCOASPICE_SCAN_PERSIST=1` exercises the SQLite coordinator as well.

## Rules

- Keep scan-root persistence in SQLite, not `UserDefaults`.
- Keep scan-root management separate from playlist behavior and playback behavior.
- Keep automatic scan behavior explicit.
- Keep scanning complete and database-oriented: archive member listing and decoder metadata inspection happen during scanning, while playlist activation reads the stored rows directly.

## Files

- [OptionsView.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/OptionsView.swift)
- [LibraryDatabase.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase.swift)
- [LibraryDatabase+Roots.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase+Roots.swift)
- [LibraryDatabaseMaintenance.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabaseMaintenance.swift)
- [LibraryScanRequestQueue.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryScanRequestQueue.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
- [LibraryScanCoordinator.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryScanCoordinator.swift)
- [LibraryScanLog.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryScanLog.swift)
- [LibraryScanLiveLogWindow.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryScanLiveLogWindow.swift)
- [ScanPipelineExecutor.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/ScanPipelineExecutor.swift)
- [ZipArchiveSupport.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/ZipArchiveSupport.swift)
