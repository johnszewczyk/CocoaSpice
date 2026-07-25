import Foundation

@MainActor
final class LibraryScanCoordinator {
    let database: LibraryDatabase
    let registry: ScanPluginRegistry
    let executor: ScanPipelineExecutor
    let archiveScanDepth: ArchiveScanDepth

    init(
        database: LibraryDatabase,
        registry: ScanPluginRegistry = ScanCoreHandlers.registry,
        archiveScanDepth: ArchiveScanDepth = .deep
    ) {
        self.database = database
        self.registry = registry
        self.archiveScanDepth = archiveScanDepth
        self.executor = ScanPipelineExecutor(pluginRegistry: registry, archiveScanDepth: archiveScanDepth)
    }

    func run(
        root: LibraryScanRoot,
        mode: ScanMode,
        report: @escaping @MainActor @Sendable (String) -> Void = { _ in },
        progress: @escaping @MainActor @Sendable (Int, Int) -> Void = { _, _ in },
        activity: @escaping @MainActor @Sendable (Int, Int, String) -> Void = { _, _, _ in },
        issue: @escaping @MainActor @Sendable (String) -> Void = { _ in }
    ) async throws -> ScanSummary {
        report("Starting scan: \(root.standardizedURL.lastPathComponent)")
        try database.markScanStarted(rootID: root.id)
        if mode == .newScan, archiveScanDepth == .deep {
            // A new scan is a replacement inventory. Retaining old tracks
            // here would surface entries whose file or archive member no
            // longer exists after a source changes.
            try database.clearScanInventory(rootID: root.id)
            try database.clearTracks(rootID: root.id)
        }
        report("Discovering supported files recursively: \(root.standardizedURL.lastPathComponent)…")
        let discovered = await ScanFilesystemDiscovery.discover(
            rootID: root.id,
            rootURL: root.standardizedURL,
            registry: registry
        )
        report("Discovered \(discovered.count) files. Loading prior scan state…")
        let priorItems = try database.loadScanInventory(rootID: root.id)
        let priorByIdentity = Dictionary(uniqueKeysWithValues: priorItems.map { ($0.identity, $0) })

        var selected: [ScanCandidate] = []
        selected.reserveCapacity(discovered.count)
        for candidate in discovered {
            guard let prior = priorByIdentity[candidate.identity] else {
                // The deep archive listing will supply its native signature
                // while the archive is already being scanned. Do not spend a
                // separate process on first discovery.
                selected.append(candidate)
                continue
            }
            guard mode == .incremental else {
                selected.append(candidate)
                continue
            }
            guard ScanSelection.includes(prior, mode: mode, currentFingerprint: candidate.fingerprint) else {
                continue
            }

            let enriched = await ArchiveScanSignature.enrich(candidate)
            if !ScanSelection.includes(prior, mode: mode, currentFingerprint: enriched.fingerprint) {
                // A copied or timestamp-touched archive has the same native
                // manifest/checksum. Keep its successful inventory current so
                // the next incremental pass skips it without recomputing.
                try database.refreshScanFingerprint(
                    identity: candidate.identity,
                    fingerprint: enriched.fingerprint
                )
                continue
            }
            selected.append(enriched)
        }

        report("Planned \(selected.count) files for scan…")
        progress(0, selected.count)
        let preserveExistingTracks = archiveScanDepth == .fast
        let progressReporter = ScanProgressReporter(report: report, progress: progress, activity: activity)
        let accumulator = try await executor.process(
            plan: ScanPlan(mode: mode, candidates: selected),
            progress: { current, total, detail in
                Task { @MainActor in
                    progressReporter.update(current: current, total: total, detail: detail)
                }
            },
            issue: { failure in
                let archiveEntry = failure.identity.archiveEntry.map { "#\($0)" } ?? ""
                let line = "\(failure.identity.path)\(archiveEntry): \(failure.stage.rawValue): \(failure.message)"
                Task { @MainActor in
                    issue(line)
                }
            },
            persist: { [database, preserveExistingTracks] results in
                try database.persistScanResults(
                    results,
                    preservingExistingTracks: preserveExistingTracks
                )
            }
        )
        let summary = await accumulator.summary
        try database.markScanCompleted(rootID: root.id)
        let issues = summary.failures.map {
            "\($0.identity.path)\($0.identity.archiveEntry.map { "#\($0)" } ?? ""): \($0.stage.rawValue): \($0.message)"
        }
        // Progress is measured in scan candidates (files/archives), while a
        // successful archive can yield many playable leaves.
        LibraryScanLogStore.write(
            rootID: root.id,
            issues: issues
        )
        return summary
    }
}

@MainActor
private final class ScanProgressReporter {
    private let report: @MainActor @Sendable (String) -> Void
    private let progress: @MainActor @Sendable (Int, Int) -> Void
    private let activity: @MainActor @Sendable (Int, Int, String) -> Void
    private var lastReportedCurrent = -1
    private var lastReportDate = Date.distantPast

    init(
        report: @escaping @MainActor @Sendable (String) -> Void,
        progress: @escaping @MainActor @Sendable (Int, Int) -> Void,
        activity: @escaping @MainActor @Sendable (Int, Int, String) -> Void
    ) {
        self.report = report
        self.progress = progress
        self.activity = activity
    }

    func update(current: Int, total: Int, detail: String) {
        progress(current, total)

        let now = Date()
        let reachedEnd = current >= total
        let advancedEnough = current - lastReportedCurrent >= 25
        guard current == 1 || reachedEnd || advancedEnough || now.timeIntervalSince(lastReportDate) >= 0.5 else {
            return
        }
        lastReportedCurrent = current
        lastReportDate = now
        activity(current, total, detail)
        report("Scanning \(current)/\(total): \(detail)")
    }
}
