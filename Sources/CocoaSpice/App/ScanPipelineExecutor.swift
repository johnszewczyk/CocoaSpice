import Foundation

enum ScanPipelineError: LocalizedError {
    case operationTimedOut(String, seconds: Int)

    var errorDescription: String? {
        switch self {
        case .operationTimedOut(let description, let seconds):
            return "Timed out after \(seconds) seconds: \(description)"
        }
    }
}

enum ScanOperationTimeout {
    enum Kind {
        case archiveListing
        case archiveExtraction
        case metadataInspection

        var seconds: Int {
            switch self {
            case .archiveListing: return 30
            // A valid large archive can take several minutes to extract on a
            // slower disk. This is a validity boundary, not a speed governor.
            case .archiveExtraction: return 600
            case .metadataInspection: return 60
            }
        }
    }

    static func run<T: Sendable>(
        kind: Kind = .metadataInspection,
        description: String,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(kind.seconds) * 1_000_000_000)
                throw ScanPipelineError.operationTimedOut(description, seconds: kind.seconds)
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
    let inspectionScheduler: ScanResourceScheduler

    init(
        pluginRegistry: ScanPluginRegistry = ScanCoreHandlers.registry,
        handlerRegistry: ScanPluginHandlerRegistry = ScanCoreHandlers.handlers,
        archiveProvider: (any ScanArchiveProvider)? = nil,
        scheduler: ScanResourceScheduler? = nil
    ) {
        self.pluginRegistry = pluginRegistry
        self.handlerRegistry = handlerRegistry
        // Archive tools and metadata decoders have different bottlenecks.
        // They deliberately receive independent lanes: a slow extractor no
        // longer occupies an inspection permit, while callers/tests that pass
        // one scheduler retain their explicit shared-budget behavior.
        let archiveScheduler = scheduler ?? ScanResourceScheduler(
            permits: max(1, ProcessInfo.processInfo.activeProcessorCount)
        )
        self.inspectionScheduler = scheduler ?? ScanResourceScheduler(
            permits: max(1, ProcessInfo.processInfo.activeProcessorCount)
        )
        self.archiveProvider = archiveProvider ?? ZipScanArchiveProvider(
            registry: pluginRegistry,
            scheduler: archiveScheduler
        )
    }

    func process(
        plan: ScanPlan,
        progress: @escaping @Sendable (Int, Int, String) -> Void = { _, _, _ in },
        activity: @escaping @Sendable (Int, Int, String) -> Void = { _, _, _ in },
        issue: @escaping @Sendable (ScanFailure) -> Void = { _ in },
        persist: @escaping @Sendable ([ScanPipelineResult]) async throws -> Void
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
                        let results = await self.process(candidate) { detail in
                            activity(completionCounter.current(), plan.count, detail)
                        }
                        // A huge archive can produce thousands of leaves.
                        // Persist bounded batches instead of asking SQLite to
                        // retain one giant transaction/result array at once.
                        for resultBatch in results.batched(maximumCount: 128) {
                            let batch = Array(resultBatch)
                            let acceptedResults: [ScanPipelineResult]
                            do {
                                try await persist(batch)
                                acceptedResults = batch
                            } catch {
                                // A disk/database failure belongs to this item. It must not
                                // cancel unrelated validation work.
                                acceptedResults = batch.map { $0.persistenceFailure(message: error.localizedDescription) }
                            }
                            for acceptedResult in acceptedResults {
                                try await accumulator.accept(acceptedResult)
                                if case .failure(let failure) = acceptedResult {
                                    issue(failure)
                                }
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

    func process(
        _ candidate: ScanCandidate,
        activity: @escaping @Sendable (String) -> Void = { _ in }
    ) async -> [ScanPipelineResult] {
        do {
            if ZipArchiveSupport.canHandle(candidate.sourceURL), candidate.identity.archiveEntry == nil {
                return await processArchive(candidate, activity: activity)
            }
            if let archiveEntry = candidate.identity.archiveEntry {
                let materializedURL = try await materialize(candidate, archiveEntry: archiveEntry)
                return [try await processFile(candidate, fileURL: materializedURL)]
            }
            return [try await processFile(candidate)]
        } catch is CancellationError {
            return [failure(candidate, stage: .metadata, message: "Cancelled")]
        } catch {
            return [failure(candidate, stage: .metadata, message: error.localizedDescription)]
        }
    }

    private func processArchive(
        _ candidate: ScanCandidate,
        activity: @escaping @Sendable (String) -> Void
    ) async -> [ScanPipelineResult] {
        do {
            activity("Listing (candidate.sourceURL.lastPathComponent)…")
            let archiveListing = try await ScanOperationTimeout.run(
                kind: .archiveListing,
                description: "listing \(candidate.sourceURL.lastPathComponent)"
            ) {
                try await archiveProvider.listMembers(
                    in: candidate.sourceURL,
                    supportedExtensions: pluginRegistry.supportedExtensions
                )
            }
            let members = archiveListing.members
            let completedCandidate = ScanCandidate(
                identity: candidate.identity,
                fingerprint: ScanFingerprint(
                    fileSize: candidate.fingerprint.fileSize,
                    modifiedAt: candidate.fingerprint.modifiedAt,
                    contentSignature: archiveListing.scanSignature
                ),
                sourceURL: candidate.sourceURL,
                route: candidate.route
            )

            var results: [ScanPipelineResult] = []
            results.reserveCapacity(members.count)
            guard !members.isEmpty else {
                return [.archiveCompleted(await ArchiveScanSignature.enrich(completedCandidate))]
            }
            let memberCandidates = members.map { member in
                ScanCandidate(
                    identity: ScanItemIdentity(
                        rootID: candidate.identity.rootID,
                        path: member.archiveURL.path,
                        archiveEntry: member.entryPath
                    ),
                    fingerprint: member.fingerprint,
                    sourceURL: member.archiveURL,
                    route: member.route
                )
            }
            guard let materializationPolicy = PlaybackFormatRegistry.scanArchiveMaterializationForInspection(
                entryPaths: members.map(\.entryPath)
            ) else {
                throw ZipArchiveSupport.ArchiveError.invalidEntryPath(
                    members.first?.entryPath ?? ""
                )
            }
            let materializedRoot: URL
            do {
                activity("Extracting (members.count) playable member\(members.count == 1 ? "" : "s") from (candidate.sourceURL.lastPathComponent)…")
                switch materializationPolicy {
                case .selectedEntry:
                    materializedRoot = try await ScanOperationTimeout.run(
                        kind: .archiveExtraction,
                        description: "extracting playable members from \(candidate.sourceURL.lastPathComponent)"
                    ) {
                        try await archiveProvider.materializeEntriesForScan(
                            archiveURL: candidate.sourceURL,
                            entryPaths: members.map(\.entryPath)
                        )
                    }
                case .completeSet, .completeSetWithLazyUSFAliases:
                    materializedRoot = try await ScanOperationTimeout.run(
                        kind: .archiveExtraction,
                        description: "extracting dependency set \(candidate.sourceURL.lastPathComponent)"
                    ) {
                        try await archiveProvider.materializeArchiveForScan(at: candidate.sourceURL)
                    }
                }
            } catch is CancellationError {
                return memberCandidates.map {
                    failure($0, stage: .archiveExtraction, message: "Cancelled")
                }
            } catch {
                return memberCandidates.map {
                    failure($0, stage: .archiveExtraction, message: error.localizedDescription)
                }
            }

            if materializationPolicy == .completeSetWithLazyUSFAliases {
                do {
                    try ZipArchiveSupport.prepareLazyUSFDependencies(in: materializedRoot)
                } catch {
                    await archiveProvider.discardScanMaterialization(at: materializedRoot)
                    return memberCandidates.map {
                        failure($0, stage: .archiveExtraction, message: error.localizedDescription)
                    }
                }
            }
            if members.contains(where: { $0.route?.formatExtension == "txtp" }) {
                do {
                    try ZipArchiveSupport.prepareTXTPDependencies(in: materializedRoot)
                } catch {
                    await archiveProvider.discardScanMaterialization(at: materializedRoot)
                    return memberCandidates.map {
                        failure($0, stage: .archiveExtraction, message: error.localizedDescription)
                    }
                }
            }

            let memberCursor = ScanPlanCursor(count: members.count)
            let memberWorkerCount = min(
                ZipArchiveSupport.archiveProcessConcurrency,
                members.count
            )
            let memberCompletionCounter = ScanCompletionCounter()
            activity("Inspecting 0 / (members.count) members in (candidate.sourceURL.lastPathComponent)…")
            var orderedResults = Array<ScanPipelineResult?>(repeating: nil, count: members.count)
            await withTaskGroup(of: (Int, ScanPipelineResult).self) { group in
                for _ in 0..<memberWorkerCount {
                    guard let index = memberCursor.take() else { break }
                    group.addTask {
                        let result = await self.processMaterializedArchiveMember(
                            member: members[index],
                            candidate: memberCandidates[index],
                            materializedRoot: materializedRoot
                        )
                        let completed = memberCompletionCounter.increment()
                        if completed == 1 || completed == members.count || completed.isMultiple(of: 25) {
                            activity("Inspecting (completed) / (members.count) members in (candidate.sourceURL.lastPathComponent)…")
                        }
                        return (index, result)
                    }
                }

                while let (index, result) = await group.next() {
                    orderedResults[index] = result
                    guard let nextIndex = memberCursor.take() else { continue }
                    group.addTask {
                        let result = await self.processMaterializedArchiveMember(
                            member: members[nextIndex],
                            candidate: memberCandidates[nextIndex],
                            materializedRoot: materializedRoot
                        )
                        let completed = memberCompletionCounter.increment()
                        if completed == members.count || completed.isMultiple(of: 25) {
                            activity("Inspecting (completed) / (members.count) members in (candidate.sourceURL.lastPathComponent)…")
                        }
                        return (nextIndex, result)
                    }
                }
            }
            results.append(contentsOf: orderedResults.compactMap { $0 })
            await archiveProvider.discardScanMaterialization(at: materializedRoot)
            // Known non-playable resources are a completed archive outcome,
            // not a reason to repeatedly rematerialize the whole container.
            if results.allSatisfy({ result in
                switch result {
                case .success, .unsupported:
                    return true
                case .archiveCompleted, .failure:
                    return false
                }
            }) {
                results.append(.archiveCompleted(await ArchiveScanSignature.enrich(completedCandidate)))
            }
            return results
        } catch {
            return [failure(candidate, stage: .archiveListing, message: error.localizedDescription)]
        }
    }

    private func materialize(_ candidate: ScanCandidate, archiveEntry: String) async throws -> URL {
        let extensionName = candidate.route?.formatExtension
            ?? URL(fileURLWithPath: archiveEntry).pathExtension
        guard let module = PlaybackFormatRegistry.module(forPathExtension: extensionName) else {
            throw ZipArchiveSupport.ArchiveError.invalidEntryPath(archiveEntry)
        }

        switch module.archiveMaterialization {
        case .selectedEntry:
            return try await ScanOperationTimeout.run(kind: .archiveExtraction, description: "extracting \(candidate.identityDescription)") {
                try await archiveProvider.materialize(archiveURL: candidate.sourceURL, entryPath: archiveEntry)
            }
        case .completeSet, .completeSetWithLazyUSFAliases:
            let root = try await ScanOperationTimeout.run(kind: .archiveExtraction, description: "extracting dependency set \(candidate.sourceURL.lastPathComponent)") {
                try await archiveProvider.materializeArchive(at: candidate.sourceURL)
            }
            if case .completeSetWithLazyUSFAliases = module.archiveMaterialization {
                try ZipArchiveSupport.prepareLazyUSFDependencies(in: root)
            }
            if extensionName.lowercased() == "txtp" {
                try ZipArchiveSupport.prepareTXTPDependencies(in: root)
            }
            return ZipArchiveSupport.archiveMemberURL(in: root, entryPath: archiveEntry)
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
        if KDTSequenceDetector.isSilentHillSequenceBank(fileURL ?? candidate.sourceURL) {
            return .unsupported(candidate)
        }
        if WwiseBankDetector.isEventBank(fileURL ?? candidate.sourceURL) {
            return .unsupported(candidate)
        }
        if HeaderlessSS2Detector.isUnsupportedResource(fileURL ?? candidate.sourceURL) {
            return .unsupported(candidate)
        }
        let inspection = try await inspectionScheduler.withPermit {
            try await ScanOperationTimeout.run(kind: .metadataInspection, description: "inspecting \(candidate.identityDescription)") {
                try await handler.inspect(fileURL: fileURL ?? candidate.sourceURL, route: route)
            }
        }
        return .success(candidate, inspection)
    }

    private func processMaterializedArchiveMember(
        member: ScanArchiveMember,
        candidate: ScanCandidate,
        materializedRoot: URL
    ) async -> ScanPipelineResult {
        do {
            try Task.checkCancellation()
            let materializedURL = ZipArchiveSupport.archiveMemberURL(
                in: materializedRoot,
                entryPath: member.entryPath
            )
            return try await processFile(candidate, fileURL: materializedURL)
        } catch is CancellationError {
            return failure(candidate, stage: .archiveExtraction, message: "Cancelled")
        } catch {
            return failure(candidate, stage: .metadata, message: error.localizedDescription)
        }
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

    func current() -> Int {
        lock.lock()
        defer { lock.unlock() }
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

private extension Array {
    func batched(maximumCount: Int) -> [ArraySlice<Element>] {
        guard !isEmpty else { return [] }
        let size = Swift.max(1, maximumCount)
        return stride(from: startIndex, to: endIndex, by: size).map {
            self[$0..<Swift.min($0 + size, endIndex)]
        }
    }
}
