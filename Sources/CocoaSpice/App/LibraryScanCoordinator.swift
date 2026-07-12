import Foundation

@MainActor
final class LibraryScanCoordinator {
    let database: LibraryDatabase
    let registry: ScanPluginRegistry
    let executor: ScanPipelineExecutor

    init(database: LibraryDatabase, registry: ScanPluginRegistry = ScanCoreHandlers.registry) {
        self.database = database
        self.registry = registry
        self.executor = ScanPipelineExecutor(pluginRegistry: registry)
    }

    func run(
        root: LibraryScanRoot,
        mode: ScanMode,
        report: @escaping @MainActor @Sendable (String) -> Void = { _ in }
    ) async throws -> ScanSummary {
        let operationName = mode == .retryFailed ? "retry" : "scan"
        report("Starting \(operationName): \(root.standardizedURL.lastPathComponent)")
        try database.markScanStarted(rootID: root.id)
        if mode == .newScan {
            // Scan inventory is a report of the latest attempt. Keep the
            // playable library intact, but remove stale failures so a clean
            // completed rescan can accurately report a clean root.
            try database.clearScanInventory(rootID: root.id)
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

        let selected: [ScanCandidate]
        if mode == .retryFailed {
            selected = priorItems.filter { $0.state == .failed }.map { item in
                ScanCandidate(
                    identity: item.identity,
                    fingerprint: item.fingerprint,
                    sourceURL: URL(fileURLWithPath: item.identity.path),
                    route: item.route
                )
            }
        } else {
            selected = discovered.filter { candidate in
                guard let prior = priorByIdentity[candidate.identity] else { return true }
                return ScanSelection.includes(prior, mode: mode, currentFingerprint: candidate.fingerprint)
            }
        }

        report("Planned \(selected.count) files for \(operationName)…")
        let accumulator = try await executor.process(
            plan: ScanPlan(mode: mode, candidates: selected),
            progress: { current, total, detail in
                Task { @MainActor in
                    report("Scanning \(current)/\(total): \(detail)")
                }
            },
            persist: { [database] result in
                try database.persistScanResult(result)
                if case .success = result {
                    try database.persistScanTrackResults([result])
                }
            }
        )
        let summary = await accumulator.summary
        let results = await accumulator.results
        let trackCount = results.reduce(0) { partialResult, result in
            guard case .success(_, let inspection) = result else { return partialResult }
            return partialResult + inspection.tracks.count
        }
        try database.markScanCompleted(rootID: root.id, trackCount: trackCount)
        return summary
    }
}
