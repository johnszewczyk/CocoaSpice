import Foundation

enum ScanPipelineError: LocalizedError {
    case operationTimedOut(String)

    var errorDescription: String? {
        switch self {
        case .operationTimedOut(let description):
            return "Timed out after 30 seconds: \(description)"
        }
    }
}

enum ScanOperationTimeout {
    static func run<T: Sendable>(
        description: String,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                throw ScanPipelineError.operationTimedOut(description)
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw CancellationError()
            }
            return result
        }
    }
}

struct ScanPipelineExecutor: Sendable {
    let pluginRegistry: ScanPluginRegistry
    let handlerRegistry: ScanPluginHandlerRegistry
    let archiveProvider: any ScanArchiveProvider
    let scheduler: ScanResourceScheduler
    let archiveScanDepth: ArchiveScanDepth

    init(
        pluginRegistry: ScanPluginRegistry = ScanCoreHandlers.registry,
        handlerRegistry: ScanPluginHandlerRegistry = ScanCoreHandlers.handlers,
        archiveProvider: (any ScanArchiveProvider)? = nil,
        archiveScanDepth: ArchiveScanDepth = .deep,
        scheduler: ScanResourceScheduler = ScanResourceScheduler(
            permits: max(1, ProcessInfo.processInfo.activeProcessorCount)
        )
    ) {
        self.pluginRegistry = pluginRegistry
        self.handlerRegistry = handlerRegistry
        self.scheduler = scheduler
        self.archiveScanDepth = archiveScanDepth
        self.archiveProvider = archiveProvider ?? ZipScanArchiveProvider(
            registry: pluginRegistry,
            scheduler: scheduler
        )
    }

    func process(
        plan: ScanPlan,
        progress: @escaping @Sendable (Int, Int, String) -> Void = { _, _, _ in },
        issue: @escaping @Sendable (ScanFailure) -> Void = { _ in },
        persist: @escaping @MainActor @Sendable (ScanPipelineResult) throws -> Void
    ) async throws -> ScanResultAccumulator {
        let accumulator = ScanResultAccumulator(discovered: plan.count)
        let cursor = ScanPlanCursor(count: plan.candidates.count)
        let completionCounter = ScanCompletionCounter()
        let workerCount = min(
            ZipArchiveSupport.archiveProcessConcurrency,
            max(1, plan.candidates.count)
        )

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<workerCount {
                group.addTask {
                    while let index = cursor.take() {
                        try Task.checkCancellation()
                        let candidate = plan.candidates[index]
                        let results = await self.process(candidate)
                        for result in results {
                            let acceptedResult = await MainActor.run { () -> ScanPipelineResult in
                                do {
                                    try persist(result)
                                    return result
                                } catch {
                                    // A disk/database failure belongs to this item. It must not
                                    // cancel unrelated validation work.
                                    return result.persistenceFailure(message: error.localizedDescription)
                                }
                            }
                            try await accumulator.accept(acceptedResult)
                            if case .failure(let failure) = acceptedResult {
                                issue(failure)
                            }
                        }
                        let identityDescription = candidate.identity.archiveEntry.map {
                            "\(candidate.identity.path)#\($0)"
                        } ?? candidate.identity.path
                        let completed = completionCounter.increment()
                        progress(completed, plan.count, "Completed \(identityDescription)")
                    }
                }
            }
            try await group.waitForAll()
        }
        return accumulator
    }

    func process(_ candidate: ScanCandidate) async -> [ScanPipelineResult] {
        do {
            if let archiveEntry = candidate.identity.archiveEntry {
                let materializedURL = try await materialize(candidate, archiveEntry: archiveEntry)
                return [try await processFile(candidate, fileURL: materializedURL)]
            }
            if ZipArchiveSupport.canHandle(candidate.sourceURL), candidate.identity.archiveEntry == nil {
                return await processArchive(candidate)
            }
            return [try await processFile(candidate)]
        } catch is CancellationError {
            return [failure(candidate, stage: .metadata, message: "Cancelled")]
        } catch {
            return [failure(candidate, stage: .metadata, message: error.localizedDescription)]
        }
    }

    private func processArchive(_ candidate: ScanCandidate) async -> [ScanPipelineResult] {
        do {
            let members = try await ScanOperationTimeout.run(
                description: "listing \(candidate.sourceURL.lastPathComponent)"
            ) {
                try await archiveProvider.listMembers(
                    in: candidate.sourceURL,
                    supportedExtensions: pluginRegistry.supportedExtensions
                )
            }

            var results: [ScanPipelineResult] = []
            results.reserveCapacity(members.count)
            var archiveSetURL: URL?
            for member in members {
                try Task.checkCancellation()
                let identity = ScanItemIdentity(
                    rootID: candidate.identity.rootID,
                    path: member.archiveURL.path,
                    archiveEntry: member.entryPath
                )
                let memberCandidate = ScanCandidate(
                    identity: identity,
                    fingerprint: member.fingerprint,
                    sourceURL: member.archiveURL,
                    route: member.route
                )
                if archiveScanDepth == .fast {
                    results.append(fastArchiveMemberResult(memberCandidate))
                    continue
                }
                do {
                    let materializedURL: URL
                    if memberCandidate.route?.pluginID == "lazyusf" {
                        if archiveSetURL == nil {
                            archiveSetURL = try await ScanOperationTimeout.run(description: "extracting USF set \(candidate.sourceURL.lastPathComponent)") {
                                try await archiveProvider.materializeArchive(at: candidate.sourceURL)
                            }
                            try ZipArchiveSupport.prepareLazyUSFDependencies(in: archiveSetURL!)
                        }
                        materializedURL = ZipArchiveSupport.archiveMemberURL(in: archiveSetURL!, entryPath: member.entryPath)
                    } else {
                        materializedURL = try await materialize(memberCandidate, archiveEntry: member.entryPath)
                    }
                    results.append(try await processFile(
                        memberCandidate,
                        fileURL: materializedURL
                    ))
                } catch is CancellationError {
                    results.append(failure(memberCandidate, stage: .archiveExtraction, message: "Cancelled"))
                } catch {
                    results.append(failure(memberCandidate, stage: .metadata, message: error.localizedDescription))
                }
            }
            return results
        } catch {
            return [failure(candidate, stage: .archiveListing, message: error.localizedDescription)]
        }
    }

    private func fastArchiveMemberResult(_ candidate: ScanCandidate) -> ScanPipelineResult {
        guard let route = candidate.route else { return .unsupported(candidate) }
        return .success(
            candidate,
            ScanInspection(
                route: route,
                tracks: [ScanTrackMetadata(trackIndex: 0, trackCount: 1, metadata: nil)]
            )
        )
    }

    private func materialize(_ candidate: ScanCandidate, archiveEntry: String) async throws -> URL {
        if candidate.route?.pluginID == "lazyusf" {
            let root = try await ScanOperationTimeout.run(description: "extracting USF set \(candidate.sourceURL.lastPathComponent)") {
                try await archiveProvider.materializeArchive(at: candidate.sourceURL)
            }
            try ZipArchiveSupport.prepareLazyUSFDependencies(in: root)
            return ZipArchiveSupport.archiveMemberURL(in: root, entryPath: archiveEntry)
        }
        return try await ScanOperationTimeout.run(description: "extracting \(candidate.identityDescription)") {
            try await archiveProvider.materialize(archiveURL: candidate.sourceURL, entryPath: archiveEntry)
        }
    }

    private func processFile(
        _ candidate: ScanCandidate,
        fileURL: URL? = nil
    ) async throws -> ScanPipelineResult {
        guard let route = candidate.route ?? pluginRegistry.route(
            for: URL(fileURLWithPath: candidate.identity.archiveEntry ?? candidate.sourceURL.path).pathExtension,
            archiveMember: candidate.isArchiveMember
        ) else {
            return .unsupported(candidate)
        }
        guard let handler = handlerRegistry.handler(for: route) else {
            return failure(candidate, stage: .routing, message: "No handler registered for \(route.pluginID)")
        }
        let inspection = try await scheduler.withPermit {
            try await ScanOperationTimeout.run(description: "inspecting \(candidate.identityDescription)") {
                try await handler.inspect(fileURL: fileURL ?? candidate.sourceURL, route: route)
            }
        }
        return .success(candidate, inspection)
    }

    private func failure(
        _ candidate: ScanCandidate,
        stage: ScanFailureStage,
        message: String
    ) -> ScanPipelineResult {
        .failure(ScanFailure(
            identity: candidate.identity,
            fingerprint: candidate.fingerprint,
            route: candidate.route,
            stage: stage,
            message: message
        ))
    }
}

private final class ScanPlanCursor: @unchecked Sendable {
    private let lock = NSLock()
    private let count: Int
    private var nextIndex = 0

    init(count: Int) {
        self.count = count
    }

    func take() -> Int? {
        lock.lock()
        defer { lock.unlock() }
        guard nextIndex < count else { return nil }
        defer { nextIndex += 1 }
        return nextIndex
    }
}

private final class ScanCompletionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

private extension ScanCandidate {
    var identityDescription: String {
        if let archiveEntry = identity.archiveEntry {
            return "\(identity.path)#\(archiveEntry)"
        }
        return identity.path
    }
}
