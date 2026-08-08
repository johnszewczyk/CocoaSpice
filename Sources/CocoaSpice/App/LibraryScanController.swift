import Foundation

/// Owns the active library scan lifecycle: queued root requests, cancellation,
/// live logs, background coordinator work, and progress publication. The view
/// model remains responsible for refreshing presentation state after a scan.
@MainActor
final class LibraryScanController {
    private let database: LibraryDatabase
    private let operations: LibraryOperationsState
    private let roots: () -> [LibraryScanRoot]
    private let didCompleteRoot: (LibraryScanRoot, ScanSummary) -> Void
    private let didFailRoot: (LibraryScanRoot) -> Void
    private var liveLogs: [Int64: LibraryScanLiveLogWindow] = [:]
    private let requestQueue = LibraryScanRequestQueue()

    init(
        database: LibraryDatabase,
        operations: LibraryOperationsState,
        roots: @escaping () -> [LibraryScanRoot],
        didCompleteRoot: @escaping (LibraryScanRoot, ScanSummary) -> Void,
        didFailRoot: @escaping (LibraryScanRoot) -> Void
    ) {
        self.database = database
        self.operations = operations
        self.roots = roots
        self.didCompleteRoot = didCompleteRoot
        self.didFailRoot = didFailRoot
    }

    var queuedRequestCount: Int { requestQueue.count }

    func scan(roots requestedRoots: [LibraryScanRoot], mode: ScanMode) {
        guard !requestedRoots.isEmpty else { return }
        if operations.scanInProgress {
            requestQueue.enqueue(roots: requestedRoots, mode: mode)
            operations.status = "Scan queued • \(requestQueue.count) waiting"
            return
        }

        start(requestedRoots, mode: mode)
    }

    func stop() {
        guard operations.scanInProgress else { return }
        operations.cancelActiveTask()
        operations.scanInProgress = false
        requestQueue.clear()
        operations.resetScanProgress()
        operations.status = "Scan stopped"
    }

    func closeLiveLog(rootID: Int64) {
        liveLogs[rootID]?.close()
        liveLogs[rootID] = nil
    }

    func hasLog(rootID: Int64) -> Bool {
        liveLogs[rootID] != nil
            || LibraryScanLogStore.exists(rootID: rootID)
            || roots().first(where: { $0.id == rootID })?.lastScanStartedAt != nil
    }

    func showLog(rootID: Int64) {
        if let liveLog = liveLogs[rootID] {
            liveLog.show()
            return
        }
        guard let root = roots().first(where: { $0.id == rootID }) else { return }
        let issues = LibraryScanLogStore.read(rootID: rootID)
        let summary: String?
        if let tally = try? database.scanResultTally(rootID: rootID) {
            let date = root.lastScanCompletedAt.map {
                DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .short)
            } ?? "not completed"
            let duration = root.lastScanStartedAt.flatMap { startedAt in
                root.lastScanCompletedAt.map { completedAt in
                    " • \(Int(completedAt.timeIntervalSince(startedAt).rounded()))s"
                }
            } ?? ""
            summary = "Last scan \(date)\(duration) • \(tally.successful) successful / \(tally.total) total • \(issues.count) issue\(issues.count == 1 ? "" : "s")"
        } else {
            summary = nil
        }
        let logWindow = LibraryScanLiveLogWindow(root: root, pastIssues: issues, summary: summary)
        liveLogs[rootID] = logWindow
        logWindow.show()
    }

    private func start(_ requestedRoots: [LibraryScanRoot], mode: ScanMode) {
        let generation = operations.beginTask()
        operations.scanInProgress = true
        operations.resetScanProgress()
        operations.status = mode == .newScan ? "Preparing forced scan…" : "Preparing incremental scan…"
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await Task.yield()
            for root in requestedRoots {
                await scanRoot(root, mode: mode, generation: generation)
            }
            if operations.isCurrentTask(generation) {
                operations.scanInProgress = false
                operations.finishTask(generation: generation)
                startNextQueuedScan()
            }
        }
        operations.installTask(task, generation: generation)
    }

    private func startNextQueuedScan() {
        guard !operations.scanInProgress else { return }
        while let request = requestQueue.dequeue() {
            let requestedRoots = request.rootIDs.compactMap { rootID in
                roots().first(where: { $0.id == rootID })
            }
            guard !requestedRoots.isEmpty else { continue }
            start(requestedRoots, mode: request.mode)
            return
        }
    }

    private func scanRoot(
        _ root: LibraryScanRoot,
        mode: ScanMode,
        generation: Int
    ) async {
        guard operations.isCurrentTask(generation), !Task.isCancelled else { return }
        let liveLog = LibraryScanLiveLogWindow(root: root)
        liveLogs[root.id] = liveLog
        operations.setScanProgress(rootID: root.id, current: 0, total: 0)
        operations.scanCurrentPath = root.standardizedURL.path
        operations.scanCurrentFile = "Preparing scan…"
        defer {
            if liveLogs[root.id] === liveLog {
                liveLogs[root.id] = nil
            }
            operations.clearScanProgress(rootID: root.id)
        }

        let modeTitle = mode == .newScan ? "forced" : "incremental"
        operations.status = "Preparing \(modeTitle) scan: \(root.standardizedURL.lastPathComponent)…"
        do {
            let databaseURL = database.databaseURL
            let summary = try await Task.detached(priority: .utility) {
                let scanDatabase = try LibraryDatabase(databaseURL: databaseURL)
                let coordinator = LibraryScanCoordinator(database: scanDatabase)
                return try await coordinator.run(root: root, mode: mode) { [weak self] status in
                    Task { @MainActor in
                        guard let self, self.operations.isCurrentTask(generation) else { return }
                        self.operations.status = status
                    }
                } progress: { [weak self] current, total in
                    Task { @MainActor in
                        guard let self, self.operations.isCurrentTask(generation) else { return }
                        self.operations.setScanProgress(rootID: root.id, current: current, total: total)
                    }
                } activity: { [weak liveLog] current, total, detail in
                    Task { @MainActor [weak self] in
                        guard let self, self.operations.isCurrentTask(generation) else { return }
                        self.operations.scanCurrentFile = detail
                        liveLog?.update(current: current, total: total, detail: detail)
                    }
                } issues: { [weak liveLog] lines in
                    Task { @MainActor in
                        liveLog?.append(lines)
                    }
                }
            }.value
            guard operations.isCurrentTask(generation) else { return }
            liveLog.finish(successful: summary.successful, failed: summary.failed, unsupported: summary.unsupported)
            operations.status = "\(summary.successful) / \(summary.successful + summary.failed + summary.unsupported)"
            didCompleteRoot(root, summary)
        } catch is CancellationError {
            guard operations.isCurrentTask(generation) else { return }
            operations.status = "Scan cancelled"
        } catch {
            guard operations.isCurrentTask(generation) else { return }
            operations.status = "Scan failed for \(root.standardizedURL.lastPathComponent): \(error.localizedDescription)"
            try? database.markScanFailed(rootID: root.id, error: error.localizedDescription)
            didFailRoot(root)
        }
    }
}
