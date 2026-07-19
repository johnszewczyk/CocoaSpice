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
- After inventory, file/archive inspection uses bounded concurrency. Archive extraction and decoder ownership must remain independently bounded so neither can stall unrelated workers.
- Archive scans report the current member filename while listing and inspecting a container, rather than appearing stuck on the outer archive filename.
- Scan status publication is throttled and does not await the main actor for every discovered member.
- The modern scan pipeline is the only scan route; root additions, per-root scans, retries, and enabled-root rescans use it.
- Fast Scan lists supported filesystem files and archive containers, then persists one filename-derived placeholder leaf per entry. It must never call a decoder inspector, list archive members, or decompress an archive member. Archive member listing begins only after the user places that archive in a playlist. Deep Scan retains full archive extraction, metadata inspection, and multi-track expansion.
- Fast Scan never clears or replaces existing Deep Scan tracks. Its placeholder metadata is hydrated only after its archive leaf enters a playlist; scanning must never decompress archive members merely to create the sidebar list.
- Deep Scan uses the vgmstream inspector for PlayStation XA and SVAG/IECS-family PlayStation 2 audio, so supported streams contribute decoder-derived subsongs, length, and loop metadata while file size remains part of the scan fingerprint.
- Deep Scan derives archive extraction from the decoder module's materialization policy. GSF, 2SF, PSF/PSF2, and USF-family members reuse one complete-set extraction per archive so sibling libraries remain available; only LazyUSF additionally prepares extensionless library aliases.
- When a Fast Scan archive enters a playlist, archived GBS members are materialized and inspected so their multi-track leaves replace the single archive-member placeholder.
- Purging the database deletes indexed tracks, metadata, scan inventory, and scan status for every root in one transaction, but never deletes configured root rows or their path, enabled, or ordering values.
- A scan retains the existing library while it runs and persists each completed source/archive in one transaction, so a bad file or interrupted scan cannot erase already indexed results or force a transaction per archive member.
- Each active Library Paths row owns a live label-free 200pt progress bar; cancelling invalidates the active scan generation.
- Scan persistence uses the main-actor-owned database connection. Keep progress publication lightweight; unthrottled per-candidate UI work can delay playback completion delivery and queue advancement.
- A new scan replaces both the root's scan inventory and track rows. Do not retain tracks from prior scans, because every displayed library entry must resolve to a currently discovered file or archive member.
- `Trim Missing` performs one whole-library file-existence pass over unique indexed source paths. It does not open archives or read metadata, and removes all rows backed by a confirmed-missing source path. Options shows the checked/total count, progress bar, current source, and final removal result.
- Archive subprocesses are polled for cancellation and bounded by a timeout, so a failed 7z listing/extraction cannot strand a later retry.
- Archive listing and extraction stream standard output to short-lived files under CocoaSpice's managed archive cache rather than the system temporary directory or in-memory pipes. Their stderr pipe endpoints must be explicitly closed after every subprocess; otherwise a whole-tree scan eventually exhausts file descriptors and manifests as cascading archive, metadata, and SQLite failures.
- ZIP listing and extraction both use 7-Zip path names; do not mix a separate ZIP lister with 7-Zip extraction, because legacy member encodings can otherwise resolve to different paths.
- Scans include playable members from ZIP, 7z, and RSN archives. SPC files are inspected through libgme during scanning, so the stored metadata and duration match playback before a playlist is opened. Multi-track members are stored as one row per subtrack.
- LazyUSF archive members materialize their complete archive set into one cache directory so `.miniusf` files retain access to sibling `.usf` and `.usflib` dependencies.
- Database state restores from the existing database on launch and does not rescan automatically.
- The live SQLite handle remains open for the lifetime of the model; removing the last root does not delete the open database file.
- Database setup and scan-root persistence errors remain visible through scan status instead of being converted into an empty root list.
- Each root's Log button opens a scan-status window. During a scan it shows the root path, current file, total-file progress bar, bottom-line scan state, and live error-only details. After completion it reopens the persisted error history and completed state, including clean and zero-file scans.
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
