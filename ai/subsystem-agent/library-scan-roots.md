# Library Scan Roots

## Scope

- Scan-root configuration.
- SQLite root persistence.
- Scan lifecycle and status.

## Current State

- Scan roots are configured from Options.
- Scan roots persist in SQLite.
- Adding a scan root starts a scan automatically.
- Scan progress counts source files and archives; a successful archive can produce many playable member rows.
- Initial recursive discovery and per-file/archive inspection run off the main actor; status reports preparation and discovered-file count before item processing begins.
- Recursive discovery walks every accessible subdirectory explicitly, records supported files and archives, and reports inaccessible subtrees as scan issues.
- After inventory, file/archive inspection uses bounded concurrency. Archive extraction and decoder ownership remain independently bounded so neither can stall unrelated workers. libgme metadata inspection permits at most three concurrent decoder instances; other decoder backends remain serialized unless their module explicitly declares a safe higher limit.
- Archive scans report the current member filename while listing and inspecting a container, rather than appearing stuck on the outer archive filename.
- Scan status publication is throttled and does not await the main actor for every discovered member.
- The modern scan pipeline is the only scan route; root additions, per-root scans, and enabled-root rescans use it. Incremental selection skips successful entries whose file-size/modification fingerprint is unchanged. A fully successful ZIP, 7z, or TAR+Zstandard deep scan also persists a parent archive record containing only tool-reported details: 7-Zip's archive listing report for ZIP/7z and `zstd -lv`'s report for TAR+Zstandard. A matching report skips a timestamp-only archive change without extraction or decoder inspection; failed, changed, unsupported, and legacy-unfingerprinted entries are scheduled normally.
- Fast Scan lists supported filesystem files and archive containers, then persists one filename-derived placeholder leaf per entry. It must never call a decoder inspector, list archive members, or decompress an archive member. Archive member listing begins only after the user places that archive in a playlist. Deep Scan retains full archive extraction, metadata inspection, and multi-track expansion.
- Fast Scan never clears or replaces existing Deep Scan tracks. Its placeholder metadata is hydrated only after its archive leaf enters a playlist; scanning must never decompress archive members merely to create the sidebar list.
- Deep Scan uses the vgmstream inspector for PlayStation XA and SVAG/IECS-family PlayStation 2 audio, so supported streams contribute decoder-derived subsongs, length, and loop metadata while file size remains part of the scan fingerprint.
- Deep Scan has a scan-only metadata shortcut layer ahead of the decoder inspector. SPC reads ID666/xID6 and VGM/VGZ reads header/GD3 directly; PSF, PSF2, USF, and 2SF read their container `[TAG]` footer directly. The decoder remains the fallback for malformed files and for formats that need subtrack enumeration.
- `ScanMetadataShortcuts` is the single top-level registry for these per-format scan optimizations. Add a rule there only when the format has a reliable metadata-only source; every rule must return the normal `DecoderCoreScanHandler` fallback for malformed files, absent tags, or cases requiring subtrack enumeration. Do not add hidden one-off parser branches to the generic scan executor.
- Playback archive materialization and scan materialization are separate module contracts. Playback still materializes complete sets for GSF, 2SF, PSF/PSF2, and USF-family files so sibling libraries remain available. Tag-only PSF-family scans materialize only selected playable members; SPC and other independent members do the same. LazyUSF alias preparation remains a playback complete-set concern.
- When a Fast Scan archive enters a playlist, archived GBS members are materialized and inspected so their multi-track leaves replace the single archive-member placeholder.
- Purging the database deletes indexed tracks, metadata, scan inventory, and scan status for every root in one transaction, but never deletes configured root rows or their path, enabled, or ordering values.
- Removing a library path detaches it from the active Database without deleting its indexed tracks or scan inventory. Re-adding the same path restores that root identity and uses the prior file-size/modification fingerprints for an incremental scan. Purge Database is the only action that deletes detached-root records.
- A scan retains the existing library while it runs and persists each completed source/archive in one transaction, so a bad file or interrupted scan cannot erase already indexed results or force a transaction per archive member.
- Each active Library Paths row owns a live label-free 200pt progress bar; cancelling invalidates the active scan generation.
- Scan persistence uses the main-actor-owned database connection. Keep progress publication lightweight; unthrottled per-candidate UI work can delay playback completion delivery and queue advancement.
- A new scan replaces both the root's scan inventory and track rows. Do not retain tracks from prior scans, because every displayed library entry must resolve to a currently discovered file or archive member.
- `Trim Missing` performs one whole-library file-existence pass over unique indexed source paths. It does not open archives or read metadata, and removes all rows backed by a confirmed-missing source path. Options shows the checked/total count, progress bar, current source, and final removal result.
- Archive subprocess completion is event-driven, while bounded cancellation checks and a timeout remain active. Successful tiny listings and extractions do not wait for a polling interval, and a failed 7z operation cannot strand a later retry.
- Scanner timeouts reflect the operation: archive listing has a 30-second boundary, metadata inspection 60 seconds, and archive extraction 10 minutes. The extraction window accepts valid large archives; it does not reduce concurrency or otherwise throttle fast machines.
- Archive listing and extraction stream standard output to short-lived files under CocoaSpice's managed archive cache rather than the system temporary directory or in-memory pipes. Their stderr pipe endpoints must be explicitly closed after every subprocess; otherwise a whole-tree scan eventually exhausts file descriptors and manifests as cascading archive, metadata, and SQLite failures.
- Deep Scan materializes archive members into isolated `ArchiveCache/ScanScratch` directories. The scratch directory is removed as soon as every selected member of that archive has been inspected, including on extraction failure; scan extraction must never populate the durable playback cache.
- ZIP listing and extraction both use 7-Zip path names; do not mix a separate ZIP lister with 7-Zip extraction, because legacy member encodings can otherwise resolve to different paths.
- Scans include playable members from ZIP, 7z, RSN, and TAR+Zstandard (`.tar.zst`/`.tzst`) archives. SPC files are inspected through libgme during scanning, so the stored metadata and duration match playback before a playlist is opened. Multi-track members are stored as one row per subtrack.
- TAR+Zstandard archive listings stream `zstd -d -c` directly into `tar -tf -`, avoiding full extraction before discovery and bypassing BSD tar's unreliable concurrent Zstandard helper. A normal downstream SIGPIPE after tar finishes listing is not a listing failure. Selected-member and complete-set extraction both decompress through `zstd` into a short-lived plain TAR before extraction, avoiding BSD tar's unreliable Zstandard helper. Selected TAR member paths are escaped as literal names because BSD tar otherwise treats `*`, `?`, and `[` as patterns.
- SPC is registered as a single-track libgme format, so direct folder/archive playlist loading can publish its rows before metadata hydration. Multi-track GME containers retain pre-publication track enumeration; subsequent SPC metadata changes are coalesced into targeted table-row refreshes rather than structural playlist reloads.
- Deep Scan reads valid GD3 metadata and timing directly from tagged VGM/VGZ files, including gzip-compressed VGZ members. Untagged or malformed VGM/VGZ and the GYM/S98 formats retain the libVGM inspector fallback.
- LazyUSF archive members materialize their complete archive set into one cache directory so `.miniusf` files retain access to sibling `.usf` and `.usflib` dependencies.
- Database state restores from the existing database on launch and does not rescan automatically.
- The live SQLite handle remains open for the lifetime of the model; removing the last root does not delete the open database file.
- Database setup and scan-root persistence errors remain visible through scan status instead of being converted into an empty root list.
- SQLite persistence errors include the extended SQLite result code so a filesystem write failure can be distinguished from ordinary lock contention or malformed scan metadata.
- Each root's Log button opens a plain-text scan log. Its native title bar carries concise live/completed scan statistics; the content is only error lines. Persisted logs and the text view are byte/row bounded, and historical issues are inserted as one batch so a failed large scan cannot stall or crash the app when Log opens.
- `scripts/scan-pipeline.sh <root>` runs the scan pipeline from the command line; `COCOASPICE_SCAN_PERSIST=1` exercises the SQLite coordinator as well.

## Rules

- Keep scan-root persistence in SQLite, not `UserDefaults`.
- Keep scan-root management separate from playlist behavior and playback behavior.
- Keep automatic scan behavior explicit.
- Keep Fast Scan limited to filesystem/archive-container enumeration and filename placeholders; archive member listing and decoder metadata inspection belong exclusively to playlist activation or Deep Scan.

## Files

- [OptionsView.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/OptionsView.swift)
- [LibraryDatabase.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase.swift)
- [LibraryDatabase+Roots.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase+Roots.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
- [LibraryScanCoordinator.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryScanCoordinator.swift)
- [LibraryScanLog.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryScanLog.swift)
- [LibraryScanLiveLogWindow.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryScanLiveLogWindow.swift)
- [ScanPipelineExecutor.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/ScanPipelineExecutor.swift)
- [ZipArchiveSupport.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/ZipArchiveSupport.swift)
