import Foundation

final class LibraryScanCoordinator {
    let database: LibraryDatabase
    let registry: ScanPluginRegistry
    let executor: ScanPipelineExecutor

    init(
        database: LibraryDatabase,
        registry: ScanPluginRegistry = ScanCoreHandlers.registry
    ) {
        self.database = database
        self.registry = registry
        self.executor = ScanPipelineExecutor(pluginRegistry: registry)
    }

    func run(
        root: LibraryScanRoot,
        mode: ScanMode,
        report: @escaping @Sendable (String) -> Void = { _ in },
        progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in },
        activity: @escaping @Sendable (Int, Int, ScanActivity) -> Void = { _, _, _ in },
        issues: @escaping @Sendable ([String]) -> Void = { _ in }
    ) async throws -> ScanSummary {
        let phaseTimeline = ScanPhaseTimeline()
        phaseTimeline.enter(.preparing)
        report("Starting scan: \(root.standardizedURL.lastPathComponent)")
        try database.markScanStarted(rootID: root.id)
        let atomicScan = try database.beginAtomicScan(
            rootID: root.id,
            replacingLiveData: true,
            mode: mode
        )
        do {
            if atomicScan.resumed {
                report("Resuming retained scan: \(root.standardizedURL.lastPathComponent)…")
            }
            report("Discovering supported files recursively: \(root.standardizedURL.lastPathComponent)…")
            phaseTimeline.enter(.discovery)
            let discovered = try await ScanFilesystemDiscovery.discover(
                rootID: root.id,
                rootURL: root.standardizedURL,
                registry: registry
            )
            try Task.checkCancellation()
            phaseTimeline.enter(.planning)
            report("Discovered \(discovered.count) files. Loading prior scan state…")
            try database.synchronizeStagingSources(
                rootID: root.id,
                discoveredPaths: discovered.map(\.identity.path)
            )
            let priorItems = try database.loadScanInventory(rootID: root.id)
            let priorByIdentity = Dictionary(uniqueKeysWithValues: priorItems.map { ($0.identity, $0) })
            let completedSources = Dictionary(uniqueKeysWithValues: try database
                .loadScanSourceCheckpoints(rootID: root.id)
                .map { ($0.path, $0.fingerprint) })

            // A retained checkpoint is useful only while the physical source is
            // still identical. Recompute its bounded content/archive signature
            // before skipping it so a timestamp-preserving rewrite cannot publish
            // stale staged rows after resume.
            let checkpointValidationIndexes = discovered.indices.filter { index in
                completedSources[discovered[index].identity.path]?.contentSignature != nil
            }
            let validatedCheckpointCandidates = try await enrichScanCandidates(
                checkpointValidationIndexes.map { discovered[$0] },
                maximumConcurrency: ZipArchiveSupport.archiveProcessConcurrency
            )
            var validatedDiscovered = discovered
            for (offset, index) in checkpointValidationIndexes.enumerated() {
                validatedDiscovered[index] = validatedCheckpointCandidates[offset]
            }

        var selected: [ScanCandidate] = []
        var candidatesNeedingSignature: [(candidate: ScanCandidate, prior: ScanInventoryItem)] = []
        selected.reserveCapacity(discovered.count)
        candidatesNeedingSignature.reserveCapacity(discovered.count)
        for candidate in validatedDiscovered {
            try Task.checkCancellation()
            if let completedFingerprint = completedSources[candidate.identity.path],
               completedFingerprint.matches(candidate.fingerprint) {
                continue
            }
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
            if prior.route != candidate.route {
                selected.append(candidate)
                continue
            }
            let requiresScan = ScanSelection.includes(
                prior,
                mode: mode,
                currentFingerprint: candidate.fingerprint
            )
            if mode == .incremental,
               prior.fingerprint.contentSignature != nil,
               !ArchiveScanSignature.supports(candidate.sourceURL) {
                // Revalidate the bounded content sample even when size and
                // mtime match. This catches timestamp-preserving rewrites;
                // unchanged content is then skipped below.
                candidatesNeedingSignature.append((candidate, prior))
                continue
            }
            guard requiresScan else {
                continue
            }
            guard ArchiveScanSignature.supports(candidate.sourceURL)
                    || prior.fingerprint.contentSignature != nil else {
                selected.append(candidate)
                continue
            }
            candidatesNeedingSignature.append((candidate, prior))
        }

        // Native manifest checks avoid extraction, but were previously awaited
        // one at a time after a bulk move or timestamp change. Keep archive
        // tool pressure bounded while letting independent signatures overlap.
        let enrichedCandidates = try await enrichScanCandidates(
            candidatesNeedingSignature.map(\.candidate),
            maximumConcurrency: ZipArchiveSupport.archiveProcessConcurrency
        )
        for (index, enriched) in enrichedCandidates.enumerated() {
            let prior = candidatesNeedingSignature[index].prior
            if !ScanSelection.includes(prior, mode: mode, currentFingerprint: enriched.fingerprint) {
                // A copied or timestamp-touched archive has the same native
                // manifest/checksum. Keep its successful inventory current so
                // the next incremental pass skips it without recomputing.
                try database.refreshScanFingerprint(
                    identity: enriched.identity,
                    fingerprint: enriched.fingerprint
                )
                continue
            }
            selected.append(enriched)
        }

        report("Planned \(selected.count) files for scan…")
        progress(0, selected.count)
        let progressReporter = ScanProgressReporter(report: report, progress: progress, activity: activity)
        let issueReporter = ScanIssueReporter(issues: issues)
        let persistence = ScanResultPersistence(database: database)
        let accumulator = try await executor.process(
            plan: ScanPlan(mode: mode, candidates: selected),
            progress: { current, total, detail in
                Task {
                    await progressReporter.update(current: current, total: total, detail: detail)
                }
            },
            activity: { current, total, activity in
                phaseTimeline.enter(activity.phase)
                Task {
                    await progressReporter.reportActivity(current: current, total: total, activity: activity)
                }
            },
            issue: { failure in
                let archiveEntry = failure.identity.archiveEntry.map { "#\($0)" } ?? ""
                let line = "\(failure.identity.path)\(archiveEntry): \(failure.stage.rawValue): \(failure.message)"
                Task {
                    await issueReporter.append(line)
                }
            },
            persist: { results in
                phaseTimeline.enter(.persistence)
                try await persistence.persist(results)
            }
        )
        await issueReporter.flush()
        let accumulatedSummary = await accumulator.summary
        try Task.checkCancellation()
        phaseTimeline.enter(.publication)
        report("Publishing scan: \(root.standardizedURL.lastPathComponent)…")
        try database.markScanCompleted(rootID: root.id)
        try database.commitAtomicScan()
        let summary = ScanSummary(
            discovered: accumulatedSummary.discovered,
            completed: accumulatedSummary.completed,
            successful: accumulatedSummary.successful,
            failed: accumulatedSummary.failed,
            unsupported: accumulatedSummary.unsupported,
            cancelled: accumulatedSummary.cancelled,
            failures: accumulatedSummary.failures,
            telemetry: phaseTimeline.snapshot()
        )
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
        } catch is CancellationError {
            phaseTimeline.enter(.cleanup)
            report("Pausing cancelled scan…")
            database.pauseAtomicScan()
            throw CancellationError()
        } catch {
            phaseTimeline.enter(.cleanup)
            report("Pausing failed scan…")
            database.pauseAtomicScan(failed: true, error: error.localizedDescription)
            try? database.markScanFailed(rootID: root.id, error: error.localizedDescription)
            throw error
        }
    }
}

private func enrichScanCandidates(
    _ candidates: [ScanCandidate],
    maximumConcurrency: Int
) async throws -> [ScanCandidate] {
    try Task.checkCancellation()
    guard candidates.count > 1 else {
        guard let candidate = candidates.first else { return [] }
        let enriched = await enrichScanCandidate(candidate)
        try Task.checkCancellation()
        return [enriched]
    }

    let workerCount = min(max(1, maximumConcurrency), candidates.count)
    var ordered = Array<ScanCandidate?>(repeating: nil, count: candidates.count)
    var nextIndex = workerCount
    await withTaskGroup(of: (Int, ScanCandidate).self) { group in
        for index in 0..<workerCount {
            group.addTask { (index, await enrichScanCandidate(candidates[index])) }
        }
        while let (index, candidate) = await group.next() {
            ordered[index] = candidate
            guard !Task.isCancelled else {
                group.cancelAll()
                continue
            }
            guard nextIndex < candidates.count else { continue }
            let queuedIndex = nextIndex
            nextIndex += 1
            group.addTask { (queuedIndex, await enrichScanCandidate(candidates[queuedIndex])) }
        }
    }
    try Task.checkCancellation()
    return ordered.enumerated().map { index, candidate in candidate ?? candidates[index] }
}

private func enrichScanCandidate(_ candidate: ScanCandidate) async -> ScanCandidate {
    if ArchiveScanSignature.supports(candidate.sourceURL) {
        return await ArchiveScanSignature.enrich(candidate)
    }
    return await ScanSourceContentSignature.enrich(candidate)
}

private actor ScanProgressReporter {
    private let report: @Sendable (String) -> Void
    private let progress: @Sendable (Int, Int) -> Void
    private let activity: @Sendable (Int, Int, ScanActivity) -> Void
    private var lastReportedCurrent = -1
    private var lastReportDate = Date.distantPast
    private var lastActivityDate = Date.distantPast

    init(
        report: @escaping @Sendable (String) -> Void,
        progress: @escaping @Sendable (Int, Int) -> Void,
        activity: @escaping @Sendable (Int, Int, ScanActivity) -> Void
    ) {
        self.report = report
        self.progress = progress
        self.activity = activity
    }

    func update(current: Int, total: Int, detail _: String) {
        let now = Date()
        let reachedEnd = current >= total
        let advancedEnough = current - lastReportedCurrent >= 25
        guard current == 1 || reachedEnd || advancedEnough || now.timeIntervalSince(lastReportDate) >= 0.5 else {
            return
        }
        lastReportedCurrent = current
        lastReportDate = now
        progress(current, total)
        report("Scanning \(current) / \(total)")
    }

    func reportActivity(current: Int, total: Int, activity: ScanActivity) {
        let now = Date()
        guard now.timeIntervalSince(lastActivityDate) >= 0.15 else { return }
        lastActivityDate = now
        self.activity(current, total, activity)
        report("Scanning \(current) / \(total)")
    }
}

private actor ScanIssueReporter {
    private let issues: @Sendable ([String]) -> Void
    private var pending: [String] = []
    private let batchSize = 25

    init(issues: @escaping @Sendable ([String]) -> Void) {
        self.issues = issues
    }

    func append(_ line: String) {
        pending.append(line)
        guard pending.count >= batchSize else { return }
        publishPending()
    }

    func flush() {
        publishPending()
    }

    private func publishPending() {
        guard !pending.isEmpty else { return }
        let lines = pending
        pending.removeAll(keepingCapacity: true)
        issues(lines)
    }
}

private actor ScanResultPersistence {
    private let database: LibraryDatabase

    init(database: LibraryDatabase) {
        self.database = database
    }

    func persist(_ results: [ScanPipelineResult]) throws {
        try database.checkpointScanSource(results)
    }
}
