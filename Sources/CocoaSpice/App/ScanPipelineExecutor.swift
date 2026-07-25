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
        persist: @escaping @MainActor @Sendable ([ScanPipelineResult]) throws -> Void
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
                        let acceptedResults = await MainActor.run { () -> [ScanPipelineResult] in
                            do {
                                try persist(results)
                                return results
                            } catch {
                                // A disk/database failure belongs to this item. It must not
                                // cancel unrelated validation work.
                                return results.map { $0.persistenceFailure(message: error.localizedDescription) }
                            }
                        }
                        for acceptedResult in acceptedResults {
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
            if ZipArchiveSupport.canHandle(candidate.sourceURL), candidate.identity.archiveEntry == nil {
                if archiveScanDepth == .fast {
                    return [fastArchiveContainerResult(candidate)]
                }
                return await processArchive(candidate)
            }
            if archiveScanDepth == .fast {
                return [fastFilenameResult(candidate)]
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

    private func processArchive(_ candidate: ScanCandidate) async -> [ScanPipelineResult] {
        do {
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
            guard let materializationPolicy = GMEFormatSupport.scanArchiveMaterializationForInspection(
                entryPaths: members.map(\.entryPath)
            ) else {
                throw ZipArchiveSupport.ArchiveError.invalidEntryPath(
                    members.first?.entryPath ?? ""
                )
            }
            let materializedRoot: URL
            do {
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

            let memberCursor = ScanPlanCursor(count: members.count)
            let memberWorkerCount = min(
                ZipArchiveSupport.archiveProcessConcurrency,
                members.count
            )
            var orderedResults = Array<ScanPipelineResult?>(repeating: nil, count: members.count)
            await withTaskGroup(of: (Int, ScanPipelineResult).self) { group in
                for _ in 0..<memberWorkerCount {
                    guard let index = memberCursor.take() else { break }
                    group.addTask {
                        (index, await self.processMaterializedArchiveMember(
                            member: members[index],
                            candidate: memberCandidates[index],
                            materializedRoot: materializedRoot
                        ))
                    }
                }

                while let (index, result) = await group.next() {
                    orderedResults[index] = result
                    guard let nextIndex = memberCursor.take() else { continue }
                    group.addTask {
                        (nextIndex, await self.processMaterializedArchiveMember(
                            member: members[nextIndex],
                            candidate: memberCandidates[nextIndex],
                            materializedRoot: materializedRoot
                        ))
                    }
                }
            }
            results.append(contentsOf: orderedResults.compactMap { $0 })
            await archiveProvider.discardScanMaterialization(at: materializedRoot)
            if results.allSatisfy({ result in
                if case .success = result { return true }
                return false
            }) {
                results.append(.archiveCompleted(await ArchiveScanSignature.enrich(completedCandidate)))
            }
            return results
        } catch {
            return [failure(candidate, stage: .archiveListing, message: error.localizedDescription)]
        }
    }

    private func fastFilenameResult(_ candidate: ScanCandidate) -> ScanPipelineResult {
        guard let route = candidate.route ?? pluginRegistry.route(
            for: URL(fileURLWithPath: candidate.identity.archiveEntry ?? candidate.sourceURL.path).pathExtension,
            archiveMember: candidate.isArchiveMember
        ) else {
            return .unsupported(candidate)
        }
        let archiveEntry = candidate.identity.archiveEntry
        let sourceName = candidate.sourceURL.deletingPathExtension().lastPathComponent
        let songName = archiveEntry.map {
            URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent
        } ?? sourceName
        return .success(
            candidate,
            ScanInspection(
                route: route,
                tracks: [
                    ScanTrackMetadata(
                        trackIndex: 0,
                        trackCount: 1,
                        metadata: TrackMetadata(
                            game: sourceName,
                            song: songName,
                            system: "",
                            author: "",
                            comment: FastScanPlaceholder.metadataComment,
                            introLengthMs: 0,
                            loopLengthMs: 0,
                            playLengthMs: 0,
                            fadeLengthMs: 0
                        )
                    )
                ]
            )
        )
    }

    private func fastArchiveContainerResult(_ candidate: ScanCandidate) -> ScanPipelineResult {
        let sourceName = candidate.sourceURL.deletingPathExtension().lastPathComponent
        let route = ScanRoute(
            pluginID: "archive-container",
            formatExtension: candidate.sourceURL.pathExtension.lowercased(),
            supportsArchiveMembers: true,
            supportsMultiTrack: false
        )
        return .success(
            candidate,
            ScanInspection(
                route: route,
                tracks: [
                    ScanTrackMetadata(
                        trackIndex: 0,
                        trackCount: 1,
                        metadata: TrackMetadata(
                            game: sourceName,
                            song: sourceName,
                            system: "",
                            author: "",
                            comment: FastScanPlaceholder.metadataComment,
                            introLengthMs: 0,
                            loopLengthMs: 0,
                            playLengthMs: 0,
                            fadeLengthMs: 0
                        )
                    )
                ]
            )
        )
    }

    private func materialize(_ candidate: ScanCandidate, archiveEntry: String) async throws -> URL {
        let extensionName = candidate.route?.formatExtension
            ?? URL(fileURLWithPath: archiveEntry).pathExtension
        guard let module = GMEFormatSupport.module(forPathExtension: extensionName) else {
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
        let inspection = try await scheduler.withPermit {
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
}

private extension ScanCandidate {
    var identityDescription: String {
        if let archiveEntry = identity.archiveEntry {
            return "\(identity.path)#\(archiveEntry)"
        }
        return identity.path
    }
}
