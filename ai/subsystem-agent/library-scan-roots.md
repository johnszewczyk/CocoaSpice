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
- A scan retains the existing library while it runs and persists each completed item independently, so a bad file or interrupted scan cannot erase already indexed results.
- The scan dialog owns live progress and cancellation. Its bottom bar displays candidate `current / total` progress; cancelling invalidates the active scan generation.
- Scan persistence uses the main-actor-owned database connection. Keep dialog-log updates throttled; unthrottled per-candidate UI updates can delay playback completion delivery and queue advancement.
- A new scan replaces both the root's scan inventory and track rows. Do not retain tracks from prior scans, because every displayed library entry must resolve to a currently discovered file or archive member.
- `Trim Missing` performs one whole-library file-existence pass over unique indexed source paths. It does not open archives or read metadata, and removes all rows backed by a confirmed-missing source path.
- Archive subprocesses are polled for cancellation and bounded by a timeout, so a failed 7z listing/extraction cannot strand a later retry.
- Archive listing and extraction use temporary output files rather than in-memory process-output pipes.
- ZIP listing and extraction both use 7-Zip path names; do not mix a separate ZIP lister with 7-Zip extraction, because legacy member encodings can otherwise resolve to different paths.
- Scans include playable members from ZIP, 7z, and RSN archives; archived SPC members use lightweight header metadata extraction, while multi-track archive members are inspected into one row per subtrack.
- LazyUSF archive members materialize their complete archive set into one cache directory so `.miniusf` files retain access to sibling `.usf` and `.usflib` dependencies.
- Database state restores from the existing database on launch and does not rescan automatically.
- The live SQLite handle remains open for the lifetime of the model; removing the last root does not delete the open database file.
- Database setup and scan-root persistence errors remain visible through scan status instead of being converted into an empty root list.
- Each scan root has one internal latest-scan log under CocoaSpice Application Support; the Options Log button opens it in a basic text viewer.
- `scripts/scan-pipeline.sh <root>` runs the scan pipeline from the command line; `COCOASPICE_SCAN_PERSIST=1` exercises the SQLite coordinator as well.

## Rules

- Keep scan-root persistence in SQLite, not `UserDefaults`.
- Keep scan-root management separate from playlist behavior and playback behavior.
- Keep automatic scan behavior explicit.

## Files

- [OptionsView.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/OptionsView.swift)
- [LibraryDatabase.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/LibraryDatabase.swift)
- [PlayerViewModel.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/PlayerViewModel.swift)
- [ScanPipelineExecutor.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/ScanPipelineExecutor.swift)
- [ZipArchiveSupport.swift](/Users/john/Downloads/Code/CocoaSpice/Sources/CocoaSpice/App/ZipArchiveSupport.swift)
